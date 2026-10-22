/*
 * AGVariantsInputMethod.m — a composition held open while the person picks, and the variant table it picks from.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE COMPOSITION IS ONE MARKED LETTER AND AN INDEX.** The letter goes into the store as marked text through the
 * client's own door; the candidate window shows the plain letter and its variants with the index on one of them; and
 * committing REPLACES the marked range with the pick — which is exactly what `NSTextView -insertText:` does while a
 * mark is up, so no second edit path exists. Escape and a key that ends the composition both go through the marked
 * range too, and the window follows the caret through `-invalidateCharacterCoordinates`.
 */
#import <AppKit/AGVariantsInputMethod.h>
#import <AppKit/AGCandidateWindow.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSEvent.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

/* **THE TABLE: a base letter and one precomposed reading of it.** The plain letter is not in the table — the method
 * puts it first — so an entry is a VARIANT. The set is the Latin-1 and Latin Extended-A precomposed letters. */
typedef struct {
	unichar base;
	unichar variant;
} FNVariantReading;

static const FNVariantReading fn_readings[] = {
	{'a', 0x00E0}, {'a', 0x00E1}, {'a', 0x00E2}, {'a', 0x00E3}, {'a', 0x00E4}, {'a', 0x00E5},
	{'A', 0x00C0}, {'A', 0x00C1}, {'A', 0x00C2}, {'A', 0x00C3}, {'A', 0x00C4}, {'A', 0x00C5},
	{'e', 0x00E8}, {'e', 0x00E9}, {'e', 0x00EA}, {'e', 0x00EB},
	{'E', 0x00C8}, {'E', 0x00C9}, {'E', 0x00CA}, {'E', 0x00CB},
	{'i', 0x00EC}, {'i', 0x00ED}, {'i', 0x00EE}, {'i', 0x00EF},
	{'I', 0x00CC}, {'I', 0x00CD}, {'I', 0x00CE}, {'I', 0x00CF},
	{'o', 0x00F2}, {'o', 0x00F3}, {'o', 0x00F4}, {'o', 0x00F5}, {'o', 0x00F6}, {'o', 0x00F8},
	{'O', 0x00D2}, {'O', 0x00D3}, {'O', 0x00D4}, {'O', 0x00D5}, {'O', 0x00D6}, {'O', 0x00D8},
	{'u', 0x00F9}, {'u', 0x00FA}, {'u', 0x00FB}, {'u', 0x00FC},
	{'U', 0x00D9}, {'U', 0x00DA}, {'U', 0x00DB}, {'U', 0x00DC},
	{'y', 0x00FD}, {'y', 0x00FF},
	{'Y', 0x00DD}, {'Y', 0x0178},
	{'n', 0x00F1}, {'n', 0x0144},
	{'N', 0x00D1}, {'N', 0x0143},
	{'c', 0x00E7}, {'c', 0x0107}, {'c', 0x010D},
	{'C', 0x00C7}, {'C', 0x0106}, {'C', 0x010C},
	{'s', 0x015B}, {'s', 0x0161}, {'s', 0x015F},
	{'S', 0x015A}, {'S', 0x0160}, {'S', 0x015E},
	{'z', 0x017A}, {'z', 0x017C}, {'z', 0x017E},
	{'Z', 0x0179}, {'Z', 0x017B}, {'Z', 0x017D}
};

static NSUInteger fn_reading_count(void)
{
	return sizeof(fn_readings) / sizeof(fn_readings[0]);
}

/* THE VARIANT READINGS OF A BASE, or nil when it has none — which is the question that decides whether the method
 * takes the key at all. */
static NSArray *fn_variants_for(unichar base)
{
	NSMutableArray *variants = nil;
	NSUInteger i;

	for (i = 0; i < fn_reading_count(); i++) {
		if (fn_readings[i].base == base) {
			if (variants == nil) {
				variants = [NSMutableArray array];
			}
			[variants addObject:[NSString stringWithFormat:@"%C", fn_readings[i].variant]];
		}
	}
	return variants;
}

@implementation AGVariantsInputMethod

- (NSString *)inputSourceIdentifier
{
	return @"AgoraVariants";
}

- (void)dealloc
{
	[_candidates release];
	[_window release];
	[super dealloc];
}

- (BOOL)isComposing
{
	return _pending != 0;
}

- (NSArray *)candidates
{
	return _candidates;
}

- (NSInteger)selectedCandidateIndex
{
	return _selected;
}

- (AGCandidateWindow *)candidateWindow
{
	return _window;
}

/* **THE WINDOW IS MADE ONCE AND REUSED.** A candidate window per composition would be a window per keystroke in a
 * phonetic method; the list it shows is what changes. */
- (AGCandidateWindow *)cg_windowForClient:(id <NSTextInput>)client
{
	if (_window == nil) {
		_window = [[AGCandidateWindow alloc] initWithClient:client];
		[_window setReleasedWhenClosed:NO];
	}
	return _window;
}

- (void)cg_clearComposition
{
	_pending = 0;
	_selected = 0;
	[_candidates release];
	_candidates = nil;
	[_window hideCandidates];
}

/* BEGIN: the plain letter first — so typing on commits it — then the variants, and the mark goes into the store. */
- (void)cg_beginWithCharacter:(unichar)base client:(id <NSTextInput>)client
{
	NSMutableArray *list = [NSMutableArray array];
	NSArray *variants = fn_variants_for(base);
	NSUInteger i;

	[list addObject:[NSString stringWithFormat:@"%C", base]];
	for (i = 0; i < [variants count]; i++) {
		[list addObject:[variants objectAtIndex:i]];
	}
	_pending = base;
	_selected = 0;
	[_candidates release];
	_candidates = [[NSArray alloc] initWithArray:list];
	[client setMarkedText:[NSString stringWithFormat:@"%C", base] selectedRange:NSMakeRange(1, 0)];
	[[self cg_windowForClient:client] showCandidates:_candidates selected:_selected];
}

/* COMMIT AND CANCEL both replace the marked range: `-insertText:` with the pick (or with the plain letter, which is
 * the same characters back), `-setMarkedText:` with nothing to take it back. */
- (void)cg_commitWithClient:(id <NSTextInput>)client
{
	NSString *chosen = ((_selected >= 0) && (_selected < (NSInteger)[_candidates count]))
		? [_candidates objectAtIndex:(NSUInteger)_selected] : nil;

	_pending = 0;
	[client insertText:((chosen != nil) ? chosen : @"")];
	[self cg_clearComposition];
}

- (void)cg_cancelWithClient:(id <NSTextInput>)client
{
	_pending = 0;
	[client setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
	[self cg_clearComposition];
}

- (void)cg_moveSelection:(NSInteger)delta
{
	/* THE VIEW CLAMPS AND WRAPS, so the index is read back rather than kept here — one place decides where the mark
	 * is, and it is the list that draws it. */
	[_window setSelectedIndex:_selected + delta];
	_selected = [_window selectedIndex];
}

- (void)discardComposition
{
	[self cg_clearComposition];
}

- (BOOL)handleEvent:(NSEvent *)event context:(NSTextInputContext *)context
{
	id <NSTextInput> client = [context client];
	NSString *chars;
	unichar c;

	if (client == nil || event == nil || [event type] != NSKeyDown) {
		return NO;
	}
	if (([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask)) != 0) {
		return NO;
	}
	chars = [event characters];
	if ([chars length] != 1) {
		return NO;
	}
	c = [chars characterAtIndex:0];

	if (_pending != 0) {
		if (c == 0x1B) {				/* ESCAPE takes the composition back */
			[self cg_cancelWithClient:client];
			return YES;
		}
		if (c == NSLeftArrowFunctionKey || c == NSUpArrowFunctionKey) {
			[self cg_moveSelection:-1];
			return YES;
		}
		if (c == NSRightArrowFunctionKey || c == NSDownArrowFunctionKey) {
			[self cg_moveSelection:1];
			return YES;
		}
		if (c == NSNewlineCharacter || c == NSCarriageReturnCharacter || c == NSEnterCharacter || c == ' ') {
			[self cg_commitWithClient:client];
			return YES;
		}
		/* ANY OTHER KEY COMMITS THE PICK, and then begins the next composition when the key is itself a base with
		 * variants — so a run of letters offers each one's readings in turn — and otherwise is the binding's. */
		[self cg_commitWithClient:client];
		if (fn_variants_for(c) != nil) {
			[self cg_beginWithCharacter:c client:client];
			return YES;
		}
		return NO;
	}
	if (fn_variants_for(c) != nil) {
		[self cg_beginWithCharacter:c client:client];
		return YES;
	}
	return NO;
}

/* **AND THE CARET MOVED, WHICH IS THE CANDIDATE WINDOW'S CUE.** A method with no window answers nothing here. */
- (void)invalidateCharacterCoordinates
{
	[_window invalidatePlacement];
}

@end
