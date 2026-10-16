/*
 * AGInputMethod.m — the dead-key table, and the state it keeps between two keystrokes.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A DEAD KEY IS A COMPOSITION WITH ONE READING.** The first keystroke puts the accent in the store AS MARKED TEXT, so
 * the person sees it waiting and the caret sits after it; the second either REPLACES that mark with one composed
 * character (`NSTextView -insertText:` targets the marked range) or, when nothing composes, CONFIRMS the accent as a
 * literal and lets the standard key binding have the key. There is no candidate list because a dead key has nothing to
 * choose between — the table below is the whole vocabulary, and it is the Latin-1 accented set rather than an
 * invention.
 */
#import <AppKit/AGInputMethod.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSEvent.h>
#import <Foundation/NSString.h>

/* THE DEAD KEYS, as the SPACING CLONE the keymap emits for each. */
static BOOL fn_is_dead_key(unichar c)
{
	switch (c) {
	case 0x00B4:	/* ACUTE ACCENT */
	case 0x0060:	/* GRAVE ACCENT */
	case 0x005E:	/* CIRCUMFLEX ACCENT */
	case 0x007E:	/* TILDE */
	case 0x00A8:	/* DIAERESIS */
		return YES;
	default:
		return NO;
	}
}

/* **AND THE TABLE: an accent, a letter, and what the two make.** */
typedef struct {
	unichar accent;
	unichar base;
	unichar composed;
} FNAccent;

static const FNAccent fn_accents[] = {
	{0x00B4, 'a', 0x00E1}, {0x00B4, 'e', 0x00E9}, {0x00B4, 'i', 0x00ED},
	{0x00B4, 'o', 0x00F3}, {0x00B4, 'u', 0x00FA}, {0x00B4, 'y', 0x00FD},
	{0x00B4, 'A', 0x00C1}, {0x00B4, 'E', 0x00C9}, {0x00B4, 'I', 0x00CD},
	{0x00B4, 'O', 0x00D3}, {0x00B4, 'U', 0x00DA}, {0x00B4, 'Y', 0x00DD},
	{0x00B4, 'c', 0x0107}, {0x00B4, 'C', 0x0106}, {0x00B4, 'n', 0x0144},
	{0x00B4, 'N', 0x0143}, {0x00B4, 's', 0x015B}, {0x00B4, 'S', 0x015A},
	{0x00B4, 'z', 0x017A}, {0x00B4, 'Z', 0x0179},
	{0x0060, 'a', 0x00E0}, {0x0060, 'e', 0x00E8}, {0x0060, 'i', 0x00EC},
	{0x0060, 'o', 0x00F2}, {0x0060, 'u', 0x00F9},
	{0x0060, 'A', 0x00C0}, {0x0060, 'E', 0x00C8}, {0x0060, 'I', 0x00CC},
	{0x0060, 'O', 0x00D2}, {0x0060, 'U', 0x00D9},
	{0x005E, 'a', 0x00E2}, {0x005E, 'e', 0x00EA}, {0x005E, 'i', 0x00EE},
	{0x005E, 'o', 0x00F4}, {0x005E, 'u', 0x00FB},
	{0x005E, 'A', 0x00C2}, {0x005E, 'E', 0x00CA}, {0x005E, 'I', 0x00CE},
	{0x005E, 'O', 0x00D4}, {0x005E, 'U', 0x00DB},
	{0x007E, 'a', 0x00E3}, {0x007E, 'n', 0x00F1}, {0x007E, 'o', 0x00F5},
	{0x007E, 'A', 0x00C3}, {0x007E, 'N', 0x00D1}, {0x007E, 'O', 0x00D5},
	{0x00A8, 'a', 0x00E4}, {0x00A8, 'e', 0x00EB}, {0x00A8, 'i', 0x00EF},
	{0x00A8, 'o', 0x00F6}, {0x00A8, 'u', 0x00FC}, {0x00A8, 'y', 0x00FF},
	{0x00A8, 'A', 0x00C4}, {0x00A8, 'E', 0x00CB}, {0x00A8, 'I', 0x00CF},
	{0x00A8, 'O', 0x00D6}, {0x00A8, 'U', 0x00DC}, {0x00A8, 'Y', 0x0178}
};

static unichar fn_compose(unichar accent, unichar base)
{
	NSUInteger i, count = sizeof(fn_accents) / sizeof(fn_accents[0]);

	for (i = 0; i < count; i++) {
		if (fn_accents[i].accent == accent && fn_accents[i].base == base) {
			return fn_accents[i].composed;
		}
	}
	return 0;
}

@implementation AGInputMethod

- (NSString *)inputSourceIdentifier
{
	return @"AgoraInputMethod";
}

- (BOOL)isComposing
{
	return _pending != 0;
}

- (unichar)pendingDeadKey
{
	return _pending;
}

/* **THE SOURCE'S OWN HALF OF A DISCARD.** The context clears the client's marked text; this forgets the accent, so the
 * next key does not compose into a composition that is already gone. */
- (void)discardComposition
{
	_pending = 0;
}

- (BOOL)handleEvent:(NSEvent *)event context:(NSTextInputContext *)context
{
	id <NSTextInput> client = [context client];
	NSString *chars;
	unichar c;

	if (client == nil || event == nil || [event type] != NSKeyDown) {
		return NO;
	}
	/* A COMMAND OR CONTROL KEY IS THE MENU BAR'S, not this method's. */
	if (([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask)) != 0) {
		return NO;
	}
	chars = [event characters];
	if ([chars length] != 1) {
		return NO;
	}
	c = [chars characterAtIndex:0];
	/* ESCAPE TAKES AN UN-COMPOSED DEAD KEY BACK, which is what a person expects of a composition. */
	if (c == 0x1B) {
		if (_pending != 0) {
			_pending = 0;
			[client setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
			return YES;
		}
		return NO;
	}
	if (_pending == 0) {
		/* **THE FIRST KEYSTROKE OF A COMPOSITION IS A DEAD KEY**, shown marked so the person can see it waiting. */
		if (fn_is_dead_key(c)) {
			_pending = c;
			[client setMarkedText:[NSString stringWithFormat:@"%C", c] selectedRange:NSMakeRange(1, 0)];
			return YES;
		}
		return NO;
	}
	/* **THE SECOND KEYSTROKE EITHER COMBINES — which CONFIRMS by replacing the marked accent — or does not, and then
	 * the accent stands alone and THIS key is left to the standard key binding.** */
	{
		unichar composed = fn_compose(_pending, c);

		if (composed != 0) {
			_pending = 0;
			[client insertText:[NSString stringWithFormat:@"%C", composed]];
			return YES;
		}
	}
	{
		NSString *accent = [NSString stringWithFormat:@"%C", _pending];

		_pending = 0;
		[client insertText:accent];
	}
	return NO;
}

@end
