/*
 * NSTokenField.m — a token cell in a view, and the relay that turns tokenFieldCell: into tokenField:.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE VIEW'S TEN SELECTORS ARE THE CELL'S, AND ITS ONE REAL JOB IS THE RELAY.** An `NSTokenFieldCell` asks its
 * delegate `tokenFieldCell:…`; the caller's delegate speaks `tokenField:…`. Installing the field as the cell's delegate
 * and forwarding each message with `self` as the argument is exactly the arrangement `NSComboBox` uses for its data
 * source, and it is the reason the caller's object never has to know a cell exists.
 *
 * **AND THE FORWARDS ARE NOT PASS-THROUGHS.** Where the caller has no opinion the field must answer with the PROTOCOL'S
 * DEFAULT — accept the addition, no menu, the identity conversion, the cell's own style — because an answer of nil from
 * the field would be read by the cell as a caller's "no opinion" only where nil means that. The `shouldAddObjects:`
 * default in particular is the INPUT ARRAY, not nil: nil is Apple's error case there, and a field that returned it for
 * every caller without a delegate would refuse every typed token.
 *
 * **THE THREE STANDARD COMMANDS ARE THE FIELD'S, NOT THE CELL'S, BECAUSE A CELL HAS NO RESPONDER CHAIN.** `-copy:`,
 * `-cut:` and `-paste:` are `NSResponder`'s; they reach this view when it is the responder, which is when NO edit session
 * is running (a session's editor is the responder and owns those commands for text). With no session they move the whole
 * list through the cell's own pasteboard doors — the tier's named limitation, not an accident.
 */
#import <AppKit/NSTokenField.h>
#import <AppKit/NSTokenFieldCell.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSView.h>

#import <Foundation/NSString.h>

/* **THE FIELD IS THE CELL'S DELEGATE, AND SAYS SO PRIVATELY.** Apple does not publish `NSTokenField` as conforming to
 * `NSTokenFieldCellDelegate` — the conformance is an implementation detail of the relay — so it is a class extension
 * here rather than a public promise in the header. */
@interface NSTokenField () <NSTokenFieldCellDelegate>
@end

@implementation NSTokenField

/* ============================================================================================
 * ARCHIVING: THE BASE'S CHAIN, AND A RELAY RE-ESTABLISHED.
 * ============================================================================================ */
/* **A DELEGATE IS NOT ARCHIVED, BUT THE RELAY IS NOT THE SAME THING.** The cell's delegate is this field, and a decoded
 * cell's delegate is nil — so the decoder puts the relay back. That is not restoring a caller's state; it is rebuilding
 * the class's own wiring, the way `NSTextField` rebuilds its cell. */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self != nil) {
		[self cg_installRelay];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

+ (Class)cellClass
{
	return [NSTokenFieldCell class];
}

/* **THE INITIALISER MAKES THE CELL AND THE RELAY IN ONE PLACE.** A token field's cell must be a token cell — the ten
 * forwards below would send `tokenField…` selectors to a plain field cell and crash — and the cell's delegate must be
 * this field, or the caller's `tokenField:` methods would never be asked. The field defaults are the base's (editable,
 * selectable, bordered, bezeled), set out loud here because this initialiser does not run `NSTextField`'s. */
- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSTokenFieldCell *cell = [[NSTokenFieldCell alloc] initTextCell:@""];

		[cell setEditable:YES];
		[cell setSelectable:YES];
		[cell setBordered:YES];
		[cell setBezeled:YES];
		[self setCell:cell];
		[cell release];
		[self cg_installRelay];
		if (frameRect.size.width <= 0.0 || frameRect.size.height <= 0.0) {
			[self sizeToFit];
		}
	}
	return self;
}

/* **AND REPLACING THE CELL RE-ESTABLISHES THE RELAY, WHICH IS THE ONE THING A CALLER CAN BREAK.** `NSControl -setCell:`
 * is public; a caller may hand this view another cell. When that cell is a token cell it becomes the delegate's cell and
 * the relay is rewired; when it is not, the ten forwards are a caller's own problem and are not silently redirected. */
- (void)setCell:(NSCell *)aCell
{
	[super setCell:aCell];
	[self cg_installRelay];
}

- (void)cg_installRelay
{
	NSCell *cell = [self cell];

	if ([cell isKindOfClass:[NSTokenFieldCell class]]) {
		[(NSTokenFieldCell *)cell setDelegate:(id <NSTokenFieldCellDelegate>)self];
	}
}

- (NSTokenFieldCell *)cg_tokenCell
{
	NSCell *cell = [self cell];

	return [cell isKindOfClass:[NSTokenFieldCell class]] ? (NSTokenFieldCell *)cell : nil;
}

/* ---- THE DELEGATE, WHICH IS THE CALLER'S, IN THE BASE'S SLOT ---------------------------------------- */

- (id <NSTokenFieldDelegate>)delegate
{
	return (id <NSTokenFieldDelegate>)_delegate;
}

- (void)setDelegate:(id <NSTokenFieldDelegate>)anObject
{
	/* The base's slot, not a second one: a token field's session events and its token questions reach the SAME object,
	 * and two properties would be two chances for a caller to set one and expect the other. */
	_delegate = anObject;
	[self cg_installRelay];
}

/* ---- THE CELL'S FOUR PIECES OF STATE ---------------------------------------------------------------- */

- (void)setTokenStyle:(NSTokenStyle)style
{
	[[self cg_tokenCell] setTokenStyle:style];
	[self setNeedsDisplay:YES];
}

- (NSTokenStyle)tokenStyle
{
	return [[self cg_tokenCell] tokenStyle];
}

- (void)setTokenizingCharacterSet:(NSCharacterSet *)characterSet
{
	[[self cg_tokenCell] setTokenizingCharacterSet:characterSet];
}

- (NSCharacterSet *)tokenizingCharacterSet
{
	return [[self cg_tokenCell] tokenizingCharacterSet];
}

+ (NSCharacterSet *)defaultTokenizingCharacterSet
{
	return [NSTokenFieldCell defaultTokenizingCharacterSet];
}

- (void)setCompletionDelay:(NSTimeInterval)delay
{
	[[self cg_tokenCell] setCompletionDelay:delay];
}

- (NSTimeInterval)completionDelay
{
	return [[self cg_tokenCell] completionDelay];
}

+ (NSTimeInterval)defaultCompletionDelay
{
	return [NSTokenFieldCell defaultCompletionDelay];
}

/* ============================================================================================ *
 * THE RELAY: EACH CELL QUESTION, ANSWERED BY THE CALLER OR BY THE PROTOCOL'S OWN DEFAULT          *
 * ============================================================================================ */
/* **THE CALLER'S ANSWER WHEN THERE IS ONE, THE DEFAULT WHEN THERE IS NOT.** Each method below is the whole reason this
 * class is more than forwards, and the default is stated at each door because they are not all the same default: nil
 * means "no opinion" for the conversions and the menu, ACCEPT means "add them" for the review, and KEEP THE DEFAULT
 * WRITE means YES for the pasteboard writer. */
- (NSArray *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     completionsForSubstring:(NSString *)substring
		indexOfToken:(NSInteger)tokenIndex
     indexOfSelectedItem:(NSInteger *)selectedIndex
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:
		@selector(tokenField:completionsForSubstring:indexOfToken:indexOfSelectedItem:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self completionsForSubstring:substring
							 indexOfToken:tokenIndex
						  indexOfSelectedItem:selectedIndex];
	}
	return nil;
}

- (NSArray *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
	     shouldAddObjects:(NSArray *)tokens
		     atIndex:(NSUInteger)index
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:shouldAddObjects:atIndex:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self shouldAddObjects:tokens atIndex:index];
	}
	/* **THE DEFAULT IS THE INPUT, NOT NIL.** nil here is Apple's error case; the cell treats it as a rejection. A field
	 * with no delegate must therefore accept what was typed, which is what a token field without a delegate is for. */
	return tokens;
}

- (NSString *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     displayStringForRepresentedObject:(id)representedObject
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:displayStringForRepresentedObject:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self
				    displayStringForRepresentedObject:representedObject];
	}
	return nil;
}

- (NSString *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     editingStringForRepresentedObject:(id)representedObject
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:editingStringForRepresentedObject:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self
				    editingStringForRepresentedObject:representedObject];
	}
	return nil;
}

- (id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     representedObjectForEditingString:(NSString *)editingString
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:representedObjectForEditingString:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self
				    representedObjectForEditingString:editingString];
	}
	/* **THE IDENTITY, AND IT IS A DEFAULT RATHER THAN A FAILURE.** A field with no delegate stores the text it was
	 * given; that is what makes the class usable over `NSString`s without one. */
	return editingString;
}

- (BOOL)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     writeRepresentedObjects:(NSArray *)objects
	       toPasteboard:(NSPasteboard *)pboard
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:writeRepresentedObjects:toPasteboard:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self writeRepresentedObjects:objects
							  toPasteboard:pboard];
	}
	/* **YES KEEPS THE CELL'S DEFAULT STRING WRITE.** The cell has already put the editing strings on the board; a field
	 * with no delegate has nothing more to add and must not clear it. */
	return YES;
}

- (NSArray *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
	       readFromPasteboard:(NSPasteboard *)pboard
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:readFromPasteboard:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self readFromPasteboard:pboard];
	}
	return nil;
}

- (NSMenu *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     menuForRepresentedObject:(id)representedObject
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:menuForRepresentedObject:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self menuForRepresentedObject:representedObject];
	}
	return nil;
}

- (BOOL)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     hasMenuForRepresentedObject:(id)representedObject
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:hasMenuForRepresentedObject:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self
				   hasMenuForRepresentedObject:representedObject];
	}
	return NO;
}

- (NSTokenStyle)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     styleForRepresentedObject:(id)representedObject
{
	(void)tokenFieldCell;
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenField:styleForRepresentedObject:)]) {
		return [(id <NSTokenFieldDelegate>)_delegate tokenField:self styleForRepresentedObject:representedObject];
	}
	/* **AND THE DEFAULT IS THE FIELD'S OWN STYLE, WHICH THE CALLER SET AND THIS DOOR READS BACK.** Returning a constant
	 * here would make `-setTokenStyle:` with no delegate a setting nobody reads. */
	return [self tokenStyle];
}

/* ============================================================================================ *
 * THE MENU AND THE THREE STANDARD COMMANDS                                                      *
 * ============================================================================================ */
/* **A RIGHT-CLICK NAMES A TOKEN, AND THE CELL'S LAYOUT IS WHAT NAMES IT.** The event's point is converted into this
 * view's coordinates (the space the cell draws in) and handed to the cell's hit test; the delegate's menu, if any, is the
 * answer. No event, no point, no token — nil, which is what a view with no menu answers anyway. */
- (NSMenu *)menuForEvent:(NSEvent *)event
{
	NSTokenFieldCell *cell = [self cg_tokenCell];
	NSInteger index;

	if (cell == nil || event == nil) {
		return nil;
	}
	{
		NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];

		index = [cell cg_tokenIndexAtPoint:point inFrame:[self bounds]];
	}
	if (index == NSNotFound) {
		return nil;
	}
	return [cell cg_menuForRepresentedObjectAtIndex:index];
}

/* **COPY WRITES THE WHOLE LIST, BECAUSE THIS TIER HAS NO TOKEN SELECTION.** See the header: the list is the unit this
 * class can copy. The answer is the cell's, so a delegate that refuses the write is honoured. */
- (void)copy:(id)sender
{
	(void)sender;
	[[self cg_tokenCell] cg_writeTokensToPasteboard:[NSPasteboard generalPasteboard]];
}

/* AND CUT IS COPY FOLLOWED BY THE EMPTY, in that order: a cut that emptied before a failed write would lose the list. */
- (void)cut:(id)sender
{
	(void)sender;
	if ([[self cg_tokenCell] cg_writeTokensToPasteboard:[NSPasteboard generalPasteboard]]) {
		[[self cg_tokenCell] cg_removeAllRepresentedObjects];
		[self setNeedsDisplay:YES];
	}
}

/* **PASTE APPENDS, WHICH IS WHAT A LIST DOES.** The read is the cell's — delegate first, the board's string second — and
 * every pasted object passes the same addition review a typed one does. */
- (void)paste:(id)sender
{
	(void)sender;
	if ([[self cg_tokenCell] cg_readTokensFromPasteboard:[NSPasteboard generalPasteboard]]) {
		[self setNeedsDisplay:YES];
	}
}

@end
