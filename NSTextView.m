/*
 * NSTextView.m — many lines where `NSText` holds one, and the layout now READ FROM THE MANAGER rather than computed here.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE VIEW USED TO CARRY ITS OWN LAYOUT AND DOES NOT ANY MORE.** Slice IV built the trio — `NSTextStorage`,
 * `NSTextContainer`, `NSLayoutManager` — and the manager already knew how to break a store into line fragments, place a
 * glyph, hit-test a point and draw the ink. This class had a SECOND copy of that arithmetic (`_cg_visual`, a typesetter
 * walk, a `CTLine` per line), which is exactly the kind of duplication that drifts. So the copy is GONE: the view owns
 * the trio, `-string` is the STORE's string, and every layout question is forwarded to the manager. WHAT THE VIEW
 * KEEPS IS WHAT IS ACTUALLY THE VIEW'S: the selection, the caret, the pointer, the key commands, and the height.
 *
 * **AND THE ONE THING THAT IS NOT A FORWARD IS THE base CLASS'S STRING.** `NSText` holds a `NSMutableString` and its
 * character and word movement read it directly, so the view keeps that string as a MIRROR of the store, refreshed by
 * `NSTextStorageDidProcessEditingNotification`. The store is the authority; the mirror is what lets two decades of
 * `NSText` arithmetic keep working unchanged.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSSpellChecker.h>
#import <AppKit/AppKitRefusal.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSTextTab.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSRulerView.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSPropertyListSerialization.h>
#import <Foundation/NSData.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>

/* ONE NOTIFICATION, POSTED AND HANDED TO THE DELEGATE — the same pair `NSText.m` spells, because this class owns the
 * edit primitive rather than the base and the two halves must still happen together. */
static void cg_announce(NSText *text, NSString *name, SEL delegateSelector)
{
	NSNotification *note = [NSNotification notificationWithName:name object:text];
	id delegate = [text delegate];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (delegate != nil && [delegate respondsToSelector:delegateSelector]) {
		[delegate performSelector:delegateSelector withObject:note];
	}
}

/* **THE PRIVATE DOORS THIS FILE ASKS OF `NSTextViewEditing.m`.** The smart insertion and the undo registration are the
 * editing category's (see that file for why the split is by subject): the edit path here is what asks them, once each,
 * so the two files cannot disagree about which string is inserted or which range the undo action names. */
@interface NSTextView (AGEditingPrivate)
- (NSString *)cg_textWithSmartInsertionForString:(NSString *)text range:(NSRange)range;
- (void)cg_noteEditInRange:(NSRange)range
	      insertedText:(NSString *)inserted
	      replacedText:(NSString *)replaced;
@end

@implementation NSTextView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	return [self initWithFrame:frameRect textContainer:nil];
}

/* **APPLE'S DESIGNATED INITIALISER, AND THE ONE A CALLER WITH A CONTAINER OF ITS OWN USES.** A `nil` container builds
 * this class's own — the same one `-initWithFrame:` has always built — so the two doors differ in one branch and a view
 * can never be made with no container by accident. A container that IS supplied is adopted: it is retained here, told
 * whose container it is, put on the manager's list, and given the view's width, because a wrapping view's container is
 * its width and a container narrower than its view would draw text in a column the frame does not show. */
- (instancetype)initWithFrame:(NSRect)frameRect textContainer:(NSTextContainer *)container
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		BOOL supplied = (container != nil);

		/* APPLE'S DEFAULT FOR A TEXT VIEW, and the one a scroll view needs: the view is as tall as its text. */
		_cg_verticallyResizable = YES;
		/* **AND A TEXT VIEW USES A RULER UNLESS IT IS TOLD NOT TO**, which is Apple's default: the line a ruler
		 * draws is there for the asking, and merely asking does not build one. */
		_usesRuler = YES;
		_cg_markedRange = NSMakeRange(NSNotFound, 0);
		/* **THE MARGIN IS THE VIEW'S AND THE PADDING IS THE CONTAINER'S.** The default is Apple's (0, 0) with this
		 * tier's own four-point first-line inset added to the height — see the header for why that deviation exists
		 * and why the width defaults to zero (the container's line-fragment padding supplies the left air). */
		_cg_textContainerInset = NSMakeSize(0.0, NS_TEXT_INSET);
		_cg_textContainerOrigin = NSMakePoint(_cg_textContainerInset.width, _cg_textContainerInset.height);
		_cg_originValid = YES;
		/* **NO EDIT RUN IS IN PROGRESS**, which is what makes the first edit open an undo group rather than close an
		 * empty one. The two editing flags (`-smartInsertDeleteEnabled`, `-allowsUndo`) are NO by the zero fill, which
		 * is Apple's default for a programmatically made view; the header says so where a reader will look. */
		_cg_lastEditEnd = NSNotFound;
		/* **AND THE TRIO IS BUILT HERE, IN THE ONE DIRECTION THAT CANNOT CYCLE.** The view retains the STORE, the
		 * store retains the MANAGER, the manager retains the CONTAINER, and the container holds a BORROWED pointer
		 * back to this view. The padding is the field's own inset, so the manager's lines start where every other
		 * text surface in this tier starts. */
		_cg_textStorage = [[NSTextStorage alloc] init];
		_cg_layoutManager = [[NSLayoutManager alloc] init];
		if (container == nil) {
			container = [[[NSTextContainer alloc] initWithContainerSize:frameRect.size] autorelease];
			[container setLineFragmentPadding:NS_TEXT_INSET];
		}
		_cg_textContainer = [container retain];
		[_cg_textContainer setTextView:self];
		[_cg_textStorage addLayoutManager:_cg_layoutManager];
		[_cg_layoutManager addTextContainer:_cg_textContainer];
		if (supplied) {
			[self cg_sizeContainerToFrame];
		}
		/* **AND EVERY EDIT THE STORE ANNOUNCES REACHES THE MIRROR.** A direct store edit — a caller adding a run —
		 * and the view's own edits alike, so the base class's string is never older than the store by more than the
		 * synchronous notification itself. */
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cg_textStorageDidProcessEditing:)
			name:NSTextStorageDidProcessEditingNotification object:_cg_textStorage];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextStorageDidProcessEditingNotification
		object:_cg_textStorage];
	[self cg_endAttachmentTracking];
	[_cg_insertionPointColor release];
	[_cg_textContainer setTextView:nil];
	[_cg_textContainer release];
	[_cg_layoutManager release];
	[_cg_textStorage release];
	[super dealloc];
}

/* **AND A TEXT VIEW IS FLIPPED, WHICH IS APPLE'S OWN ANSWER AND THE ONE SCROLLING NEEDS.** y runs DOWN from the top,
 * so the FIRST line sits at the clip view's origin and grows downward as a reader expects. The base, `NSText`, is a
 * y-up single-line field and stays one; what this class flips is ITS OWN coordinates, and every measurement below is
 * written in them. THE MANAGER'S CONTAINER COORDINATES ARE THE SAME ONES, which is why the view adds only its inset. */
- (BOOL)isFlipped
{
	return YES;
}

/* ============================================================================================ *
 * THE TRIO, AND WHAT REACHES IT                                                                 *
 * ============================================================================================ */

- (NSTextStorage *)textStorage
{
	return _cg_textStorage;
}

/* **MOVING THE VIEW TO ANOTHER STORE IS FOUR WIRES AND A MIRROR.** Off the old store's list (which clears the
 * manager's back-pointer), onto the new one's (which sets it), the observer moved, and the base's string re-read — the
 * layout is invalidated by the manager's own `-setTextStorage:` along the way, so there is nothing else to forget. */
- (void)setTextStorage:(NSTextStorage *)storage
{
	if (storage == _cg_textStorage) {
		return;
	}
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextStorageDidProcessEditingNotification
		object:_cg_textStorage];
	if (_cg_textStorage != nil) {
		[_cg_textStorage removeLayoutManager:_cg_layoutManager];
	}
	[storage retain];
	[_cg_textStorage release];
	_cg_textStorage = storage;
	if (_cg_textStorage != nil) {
		[_cg_textStorage addLayoutManager:_cg_layoutManager];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cg_textStorageDidProcessEditing:)
			name:NSTextStorageDidProcessEditingNotification object:_cg_textStorage];
	}
	[self cg_mirrorString];
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

- (NSLayoutManager *)layoutManager
{
	return _cg_layoutManager;
}

- (NSTextContainer *)textContainer
{
	return _cg_textContainer;
}

/* ============================================================================================ *
 * THE CONTAINER, ITS INSET, ITS ORIGIN AND THE INSERTION POINT                                  *
 * ============================================================================================ */

/* **THE FRAME'S WIDTH REACHES THE CONTAINER LESS THE TWO SIDES OF THE INSET**, which is what makes an inset a MARGIN
 * rather than a shift: with the default width of zero this is the frame's width exactly, which is the arithmetic every
 * line in this class was written against. The height stays ZERO — unbounded — for the reason `-cg_setHeightToLayout`
 * gives: a wrapping document's height is the layout's answer, never an input. */
- (void)cg_sizeContainerToFrame
{
	CGFloat width = [self frame].size.width - 2.0 * _cg_textContainerInset.width;

	if (width < 0.0) {
		width = 0.0;
	}
	[_cg_textContainer setContainerSize:NSMakeSize(width, 0.0)];
	/* **AND A NEW CONTAINER WIDTH IS A NEW WRAP**, which the manager cannot see for itself: nothing observes a
	 * container's size, so a caller that changes it without invalidating gets the OLD lines laid out in the new width —
	 * MEASURED in this slice's own probe, which set a narrow frame and counted one line where three were asked for. */
	[_cg_layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0, [_cg_textStorage length])
					     actualCharacterRange:NULL];
}

/* **THE ONE PLACE A CONTAINER IS HANDED OVER, AND THE THREE THINGS THAT MUST MOVE TOGETHER.** The old container leaves
 * the manager's list (its borrowed back-pointer cleared first, because a detached container that still names a view is
 * the shape that sends a message to a dead object), the new one joins it and is told whose it is, and the origin is
 * invalidated because a different container is a different origin. `sizedToFrame` is the ONLY difference between the
 * two public doors: `-setTextContainer:` adopts a container as this view's, so the view's width reaches it;
 * `-replaceTextContainer:` re-points the text system without the geometry following. */
- (void)cg_adoptTextContainer:(NSTextContainer *)container sizedToFrame:(BOOL)sizedToFrame
{
	NSTextContainer *previous = _cg_textContainer;

	_cg_textContainer = [container retain];
	if (previous != nil) {
		NSArray *held;
		NSUInteger i;

		[previous setTextView:nil];
		held = [[_cg_layoutManager textContainers] retain];
		for (i = 0; i < [held count]; i++) {
			if ([held objectAtIndex:i] == previous) {
				[_cg_layoutManager removeTextContainerAtIndex:i];
				break;
			}
		}
		[held release];
		[previous release];
	}
	if (_cg_textContainer != nil) {
		[_cg_textContainer setTextView:self];
		/* **A CONTAINER THIS MANAGER ALREADY HOLDS IS NOT ADDED TWICE.** `-addTextContainer:` appends, so adopting
		 * the view's own empty second container again would leave the manager laying the same text out twice. */
		if ([_cg_textContainer layoutManager] != _cg_layoutManager) {
			[_cg_layoutManager addTextContainer:_cg_textContainer];
		}
		if (sizedToFrame) {
			[self cg_sizeContainerToFrame];
		}
	}
	[self invalidateTextContainerOrigin];
	[self setNeedsDisplay:YES];
	/* **AND ONLY AN ADOPTION RE-SIZES THE VIEW.** `-replaceTextContainer:` is documented as re-pointing the text system
	 * without the view's geometry following, so it must not re-fit the height — a re-fit would carry the frame's width
	 * into the new container, which is the very thing that door does not do. */
	if (sizedToFrame) {
		[self cg_fitHeight];
	}
}

- (void)setTextContainer:(NSTextContainer *)container
{
	if (container == _cg_textContainer) {
		return;
	}
	[self cg_adoptTextContainer:container sizedToFrame:YES];
}

- (void)replaceTextContainer:(NSTextContainer *)newContainer
{
	if (newContainer == _cg_textContainer) {
		return;
	}
	[self cg_adoptTextContainer:newContainer sizedToFrame:NO];
}

- (NSSize)textContainerInset
{
	return _cg_textContainerInset;
}

/* **MOVING THE MARGIN MOVES EVERYTHING THE VIEW DRAWS**, which is why this door invalidates the origin, the display and
 * the height in that order: the origin is what the drawing, the hit test and the caret all read, the display is stale
 * because the ink moved, and the height is settled again because a narrower container re-wraps. */
- (void)setTextContainerInset:(NSSize)inset
{
	if (NSEqualSizes(inset, _cg_textContainerInset)) {
		return;
	}
	_cg_textContainerInset = inset;
	[self invalidateTextContainerOrigin];
	[self cg_sizeContainerToFrame];
	[_cg_layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0, [_cg_textStorage length])
					     actualCharacterRange:NULL];
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

/* **THE ORIGIN IS THE INSET, AND IT IS CACHED ON PURPOSE.** In a flipped view the container's origin in view coordinates
 * IS the inset — there is no other term today. Apple's door exists because in Apple's text system there IS another term
 * (the ruler's reserved band and the container's own origin), so the cache is the seam that term will be added behind;
 * `-invalidateTextContainerOrigin` is the door that will have to be called when it is, and every reader below already
 * goes through this accessor rather than reading the ivar. A cache that is always right is still a cache: it is built
 * once per invalidation, and `-setTextContainerInset:` is one of the two things that invalidates it. */
- (NSPoint)textContainerOrigin
{
	if (!_cg_originValid) {
		_cg_textContainerOrigin = NSMakePoint(_cg_textContainerInset.width, _cg_textContainerInset.height);
		_cg_originValid = YES;
	}
	return _cg_textContainerOrigin;
}

- (void)invalidateTextContainerOrigin
{
	_cg_originValid = NO;
	[self setNeedsDisplay:YES];
}

/* **`-setConstrainedFrameSize:` IS THE FLOOR UNDER A WRAPPING VIEW'S HEIGHT.** The width is the caller's — it is the
 * container's width, so it is the one number that decides the wrap — and the height is the larger of what was asked for
 * and what the layout needs, because a frame shorter than its text clips a document that has no scroll bar of its own.
 * A view that is NOT vertically resizable takes the height it was handed: it was given a frame on purpose, and
 * constraining it would be the second opinion this door exists to avoid. */
- (void)setConstrainedFrameSize:(NSSize)desiredSize
{
	NSSize size = desiredSize;

	[self cg_sizeContainerToFrame];
	if (_cg_verticallyResizable && _cg_textContainer != nil) {
		CGFloat width = desiredSize.width - 2.0 * _cg_textContainerInset.width;
		CGFloat needed;

		if (width < 0.0) {
			width = 0.0;
		}
		[_cg_textContainer setContainerSize:NSMakeSize(width, 0.0)];
		[_cg_layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0, [_cg_textStorage length])
						     actualCharacterRange:NULL];
		[_cg_layoutManager ensureLayoutForTextContainer:_cg_textContainer];
		needed = [_cg_layoutManager usedRectForTextContainer:_cg_textContainer].size.height
			 + 2.0 * _cg_textContainerInset.height;
		if (size.height < needed) {
			size.height = needed;
		}
	}
	[super setFrameSize:size];
}

/* ============================================================================================ *
 * THE BACKDROP, THE CARET AND THE TWO DOORS THAT SAY WHO DECIDES                                *
 * ============================================================================================ */

/* **THE BACKDROP IS A DOOR BECAUSE IT IS THE ONE PART OF THE DRAWING A SUBCLASS REPLACES.** Apple's view fills here and
 * its `-drawRect:` calls it before the selection and the glyphs; so does this one, and `-drawsBackground` is what it
 * reads. A view with the flag off fills nothing rather than filling white, which is the difference between a document
 * and a label. */
- (void)drawViewBackgroundInRect:(NSRect)rect
{
	(void)rect;
	if (!_drawsBackground) {
		return;
	}
	[[self backgroundColor] != nil ? [self backgroundColor] : [NSColor controlBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
}

/* **WHETHER A CARET IS WANTED AT ALL.** `_editing` IS the field-editor relationship in this tier — it is set while the
 * view is the window's first responder and an edit is in flight — so this is the same condition `-drawRect:` used to
 * spell inline, now named where a subclass can answer it differently. */
- (BOOL)shouldDrawInsertionPoint
{
	return (_editing && [self isEditable]);
}

/* **THE CARET IS FILLED IN THE CALLER'S COLOUR, AND `turnedOn:NO` DRAWS NOTHING.** Apple's flag is the blink's erase
 * half; this tier's caret does not blink (there is no timer, see below), and the view repaints the whole rect it
 * dirties, so "off" is the absence of ink rather than a background-coloured bar — which is what a turned-off caret looks
 * like on a document whose background the view does not own. */
- (void)drawInsertionPointInRect:(NSRect)rect color:(NSColor *)color turnedOn:(BOOL)turnedOn
{
	if (!turnedOn) {
		return;
	}
	[(color != nil ? color : [NSColor controlTextColor]) setFill];
	[[NSBezierPath bezierPathWithRect:rect] fill];
}

- (NSColor *)insertionPointColor
{
	return _cg_insertionPointColor;
}

/* **THE SETTER TOUCHES THE CARET'S RECT AND NOT THE WHOLE VIEW.** Changing the pen colour changes one point-wide bar, so
 * a caller changing it per keystroke does not repaint a document — which is the reason `-setNeedsDisplayInRect:` is
 * used here rather than `-setNeedsDisplay:YES`. */
- (void)setInsertionPointColor:(NSColor *)color
{
	if (color == _cg_insertionPointColor) {
		return;
	}
	[color retain];
	[_cg_insertionPointColor release];
	_cg_insertionPointColor = color;
	[self setNeedsDisplayInRect:[self cg_rectForCharacterIndex:_selectedRange.location]];
}

/* **THERE IS NO TIMER TO RESTART, SO THE DOOR DIRTIES THE CARET'S RECT INSTEAD.** Apple's view blinks its insertion point
 * from a timer this class does not own; the state change a blink would follow — the caret moved, the view became
 * editable, the selection changed — is exactly what makes the caret's rect stale, so that is what the door does. It is a
 * real door with a real effect rather than a note about an absent timer. */
- (void)updateInsertionPointStateAndRestartTimer:(BOOL)flag
{
	(void)flag;
	[self setNeedsDisplayInRect:[self cg_rectForCharacterIndex:_selectedRange.location]];
}

/* **A DIRTY RECT THAT MAY NOT RE-LAY-OUT.** The flag exists so that a caller repainting a narrow strip cannot trigger a
 * layout pass. NOTHING in this tier's `-drawRect:` lays out: the layout is invalidated by EDITS and WIDTH CHANGES and by
 * nothing else, so the second argument has nothing to suppress and the forward is the whole behaviour. Said here
 * because a stored flag nobody reads is the failure this tree keeps re-learning. */
- (void)setNeedsDisplayInRect:(NSRect)invalidRect avoidAdditionalLayout:(BOOL)flag
{
	(void)flag;
	[self setNeedsDisplayInRect:invalidRect];
}

/* **WHICH CHARACTER AN INSERTION AT A POINT LANDS BEFORE**, in this view's coordinates: the manager's
 * point-to-glyph door, given the point moved out of the view's margin and into the container's coordinates. This is the
 * inverse of `-cg_rectForCharacterIndex:`, and it is what makes a drop land where it was dropped rather than at the
 * insertion point. A point past the last line answers the end of the text — an insertion there is legal and is what a
 * drop below the last line means — and NSNotFound is reserved for a view with no layout to ask at all. */
- (NSUInteger)characterIndexForInsertionAtPoint:(NSPoint)point
{
	NSUInteger length = [_cg_textStorage length];
	NSPoint origin = [self textContainerOrigin];
	NSUInteger index;

	if (_cg_textContainer == nil) {
		return NSNotFound;
	}
	index = [_cg_layoutManager cg_glyphIndexForPoint:NSMakePoint(point.x - origin.x, point.y - origin.y)
						inTextContainer:_cg_textContainer];
	if (index == NSNotFound) {
		return NSNotFound;
	}
	return (index > length) ? length : index;
}

/* THE MIRROR, AND THE TWO THINGS THAT HAPPEN WHEN IT MOVES: the display is stale and the height may be. */
- (void)cg_textStorageDidProcessEditing:(NSNotification *)note
{
	(void)note;
	[self cg_mirrorString];
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

- (void)cg_mirrorString
{
	NSString *current = (_cg_textStorage != nil) ? [_cg_textStorage string] : @"";

	if (![_string isEqualToString:current]) {
		[_string setString:current];
	}
}

/* **AND THE STRING A CALLER READS IS THE STORE'S**, which is the whole point of the slice: a caller that reads
 * `-string` and a caller that reads `-textStorage` get the same characters, and an edit to either is seen by both. */
- (NSString *)string
{
	return (_cg_textStorage != nil) ? [_cg_textStorage string] : @"";
}

/* ============================================================================================ *
 * THE MODEL: A LINE IS A `\n`-TERMINATED RUN                                                *
 * ============================================================================================ */

/* **AND THE COUNT COUNTS BREAKS RATHER THAN RUNS, WHICH IS WHAT MAKES A TRAILING NEWLINE AN EMPTY LAST LINE.** "a\n"
 * has one break in it and therefore TWO lines — "a" and "" — and that is the state a document is in when the caret
 * sits on a fresh line at the end. An EMPTY STRING is one empty line, not none. */
- (NSUInteger)cg_lineCount
{
	NSString *string = [self string];
	NSUInteger n = [string length];
	NSUInteger count = 1;
	NSUInteger i;

	for (i = 0; i < n; i++) {
		if ([string characterAtIndex:i] == '\n') {
			count++;
		}
	}
	return count;
}

/* THE LINE A CHARACTER INDEX IS ON, counting the breaks before it. An index AT a break belongs to the line the break
 * ends — the caret just after "ab" in "ab\ncd" is index 2, which is still line 0 — and an index one past it is the
 * next line's first character. */
- (NSUInteger)cg_lineIndexForCharacterIndex:(NSUInteger)index
{
	NSString *string = [self string];
	NSUInteger n = [string length];
	NSUInteger line = 0;
	NSUInteger i;

	if (index > n) {
		index = n;
	}
	for (i = 0; i < index; i++) {
		if ([string characterAtIndex:i] == '\n') {
			line++;
		}
	}
	return line;
}

/* **A LINE'S RANGE EXCLUDES ITS OWN TERMINATOR, WHICH IS THE DECISION THE MODEL TURNS ON.** A caller that wants to
 * replace a line's text must not have to know whether the break is inside the range it was handed. A LINE PAST THE
 * LAST answers the empty range at the end rather than a wrong one. */
- (NSRange)cg_characterRangeOfLine:(NSUInteger)line
{
	NSString *string = [self string];
	NSUInteger n = [string length];
	NSUInteger current = 0;
	NSUInteger start = 0;
	NSUInteger i;
	NSUInteger end;

	for (i = 0; i < n; i++) {
		if ([string characterAtIndex:i] != '\n') {
			continue;
		}
		if (current == line) {
			return NSMakeRange(start, i - start);
		}
		current++;
		start = i + 1;
	}
	if (current != line) {
		return NSMakeRange(n, 0);
	}
	end = start;
	while (end < n && [string characterAtIndex:end] != '\n') {
		end++;
	}
	return NSMakeRange(start, end - start);
}

/* ============================================================================================ *
 * THE LAYOUT, WHICH IS NOW THE MANAGER'S                                                        *
 * ============================================================================================ */

/* THE FONT A LINE IS MEASURED IN. The store's own attribute at the first character is the authority — that is what
 * makes a run's font reach the layout — and a store with none falls back to this view's own font and then the system's,
 * which is the same chain `NSText` uses. */
- (NSFont *)cg_font
{
	id font = nil;

	if ([_cg_textStorage length] > 0) {
		font = [[_cg_textStorage attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSFontAttributeName];
	}
	if (font == nil) {
		font = [self font];
	}
	return (font != nil) ? (NSFont *)font : [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

/* THE FONT'S OWN BAND, taken from the manager so the view and the lines it draws cannot disagree about it. */
- (CGFloat)cg_lineHeight
{
	return [_cg_layoutManager cg_lineHeight];
}

/* **THE VISUAL LINE IS THE MANAGER'S FRAGMENT, INDEX FOR INDEX** — the same object, not a second layout that happens
 * to agree. A line past the last answers the empty range at the end of the store. */
- (NSUInteger)cg_visualLineCount
{
	return [_cg_layoutManager cg_lineFragmentCountForTextContainer:_cg_textContainer];
}

- (NSRange)cg_visualLineRangeAtIndex:(NSUInteger)line
{
	return [_cg_layoutManager cg_lineFragmentRangeAtIndex:line inTextContainer:_cg_textContainer];
}

/* **AND THE RANGE A LINE DRAWS IS THE LAYOUT'S LESS ITS TRAILING WHITESPACE.** The breaker keeps a trailing space or
 * newline in the range because it is part of what it MEASURED; none of it is ink, and taking it off the range a glyph
 * is set for is what makes the boundary between two visual lines UNAMBIGUOUS. */
- (NSRange)cg_textRangeOfVisualLine:(NSUInteger)line
{
	NSRange r = [self cg_visualLineRangeAtIndex:line];
	NSString *string = [self string];
	NSUInteger n = [string length];
	NSUInteger end;

	if (r.location >= n) {
		return NSMakeRange(n, 0);
	}
	end = r.location + r.length;
	if (end > n) {
		end = n;
	}
	while (end > r.location) {
		unichar c = [string characterAtIndex:end - 1];

		if (c == ' ' || c == '\t' || c == '\n') {
			end--;
		} else {
			break;
		}
	}
	return NSMakeRange(r.location, end - r.location);
}

/* **WHICH VISUAL LINE A CARET INDEX BELONGS TO: THE FIRST FRAGMENT THAT HOLDS IT.** The fragment's own start is the
 * lower bound and the TRIMMED end the upper, which is what keeps the wrapped line's trailing space on the line it
 * ended and the next line's first character a different index. A line with no visible characters holds its own start. */
- (NSUInteger)cg_visualLineIndexForCharacterIndex:(NSUInteger)index
{
	NSUInteger i, count = [self cg_visualLineCount];

	for (i = 0; i < count; i++) {
		NSRange full = [self cg_visualLineRangeAtIndex:i];
		NSRange trimmed = [self cg_textRangeOfVisualLine:i];

		if (full.location <= index && index <= trimmed.location + trimmed.length) {
			return i;
		}
	}
	return (count > 0) ? (count - 1) : 0;
}

/* **A LINE'S BASELINE, MEASURED DOWN FROM THE TOP OF THE VIEW** — the container origin's y plus the baseline the
 * MANAGER recorded for the fragment, which is per-fragment once a paragraph style can change the line height. It takes
 * a VISUAL line's index: a wrapped line's second part is a line of its own for every purpose this file has. */
- (CGFloat)cg_baselineForLine:(NSUInteger)line
{
	NSRange range = [self cg_visualLineRangeAtIndex:line];

	return [self textContainerOrigin].y + [_cg_layoutManager cg_baselineForGlyphAtIndex:range.location];
}

/* **THE X OF A CHARACTER INDEX, IN THIS VIEW'S COORDINATES** — the container origin's x plus the manager's offset in the
 * container. The offset already includes the container's own line-fragment padding, and the origin is the margin the
 * view adds, so this is the one sum a caller needs; it used to be spelled as a subtraction of the padding here and an
 * addition of the same number at every call site, which only agreed while the two were the same constant. */
- (CGFloat)cg_xForIndex:(NSUInteger)index
{
	return [self textContainerOrigin].x + [_cg_layoutManager cg_offsetForGlyphAtIndex:index];
}

/* **THE INVERSE, WHICH IS WHAT A CLICK ASKS: WHICH VISUAL LINE FROM THE y, THEN WHICH CHARACTER FROM THE x.** The
 * manager does both; the view only moves the point out of its own margin and into the container's coordinates. */
- (NSUInteger)cg_indexForPoint:(NSPoint)point
{
	NSPoint origin = [self textContainerOrigin];

	return [_cg_layoutManager cg_glyphIndexForPoint:NSMakePoint(point.x - origin.x, point.y - origin.y)
					      inTextContainer:_cg_textContainer];
}

/* THE INDEX ON A GIVEN VISUAL LINE NEAREST TO AN X — the goal column of a vertical movement. The line's own y picks
 * the fragment and the x picks the character, so this is the same hit test aimed at a chosen line. THE Y IS THE USED
 * RECT'S CENTRE rather than a line height's multiple, because the paragraph style can put a gap above the text. */
- (NSUInteger)cg_indexOnLine:(NSUInteger)line atX:(CGFloat)x
{
	NSRange range = [self cg_visualLineRangeAtIndex:line];
	NSRect used = [_cg_layoutManager lineFragmentUsedRectForGlyphAtIndex:range.location effectiveRange:NULL];
	NSPoint origin = [self textContainerOrigin];

	return [_cg_layoutManager cg_glyphIndexForPoint:NSMakePoint(x - origin.x, used.origin.y + used.size.height / 2.0)
					      inTextContainer:_cg_textContainer];
}

/* ============================================================================================ *
 * THE MEASUREMENT: THE HEIGHT THE LAYOUT NEEDS AT THE WIDTH IT HAS                             *
 * ============================================================================================ */

/* **A WRAPPING VIEW'S WIDTH IS THE CALLER'S AND ITS HEIGHT IS ITS OWN.** `-sizeToFit` keeps the frame's width and
 * answers the height the manager's used rect implies, plus the view's own two insets. THE WIDTH IS NEVER TOUCHED — a
 * view that set its own width from its longest line would RE-WRAP ITSELF on the next layout. */
- (BOOL)isVerticallyResizable
{
	return _cg_verticallyResizable;
}

- (void)setVerticallyResizable:(BOOL)flag
{
	_cg_verticallyResizable = flag;
	if (flag) {
		[self cg_setHeightToLayout];
	}
}

- (void)cg_setHeightToLayout
{
	CGFloat width = [self frame].size.width;
	CGFloat height;

	[_cg_layoutManager ensureLayoutForTextContainer:_cg_textContainer];
	height = [_cg_layoutManager usedRectForTextContainer:_cg_textContainer].size.height
		 + 2.0 * [self textContainerOrigin].y;
	if (height != [self frame].size.height) {
		/* **THE CONTAINER FOLLOWS THE FRAME IN WIDTH AND NOT IN HEIGHT, AND THAT ASYMMETRY IS THE POINT.** The manager
		 * wraps to the container's width; a ZERO height means UNBOUNDED, which is what a scrolling document is — its
		 * height is the layout's answer rather than an input, so a container that carried the frame's short height would
		 * clip the very lines this method is measuring. `[super setFrameSize:]` is deliberate: the overridden door would
		 * set the container and invalidate the layout this method just asked for. */
		[_cg_textContainer setContainerSize:NSMakeSize(width, 0.0)];
		[super setFrameSize:NSMakeSize(width, height)];
	}
}

- (void)cg_fitHeight
{
	if (_cg_verticallyResizable) {
		[self cg_setHeightToLayout];
	}
}

/* **AND `-sizeToFit` FITS REGARDLESS**, because it is an explicit request rather than the automatic height above. */
- (void)sizeToFit
{
	[self cg_setHeightToLayout];
}

/* **AND BRINGING A RANGE INTO VIEW IS ASKING THE CLIP VIEW.** The caret's rectangle is computed from the manager's
 * fragment, and `-scrollRectToVisible:` walks up to the clip view just far enough. With WRAPPING there is nothing to
 * scroll sideways: every line is inside the width, so the question is vertical and the answer is a line. */
- (NSRect)cg_rectForCharacterIndex:(NSUInteger)index
{
	NSFont *font = [self cg_font];
	NSUInteger line = [self cg_visualLineIndexForCharacterIndex:index];
	CGFloat baseline = [self cg_baselineForLine:line];

	return NSMakeRect([self cg_xForIndex:index], baseline - [font ascender], 1.0,
			  [font ascender] - [font descender]);
}

- (void)scrollRangeToVisible:(NSRange)range
{
	[self scrollRectToVisible:[self cg_rectForCharacterIndex:range.location]];
}

/* ============================================================================================ *
 * THE THREE DOORS THAT CHANGE THE TEXT OR THE WIDTH                                             *
 * ============================================================================================ */

/* **THE EDIT PRIMITIVE IS THE STORE'S NOW, AND THE BASE'S STRING IS THE MIRROR.** Every other edit in the base class is
 * spelled in this door, so this is the one place a keystroke, a paste and a programmatic replacement all meet. THE
 * INSERTED TEXT INHERITS THE RUN AT THE INSERTION POINT — the character before it, or the first character if the edit
 * is at the start — which is what makes typing into a coloured run stay coloured; a store with no runs takes the view's
 * own font when it has one. */
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
	NSString *text = (string != nil) ? string : @"";
	NSUInteger length = [_cg_textStorage length];
	NSDictionary *inherited = nil;

	/* **A PLAIN EDIT ENDS A COMPOSITION, WHICH IS WHY THE MARK CLEARS HERE.** An input method re-marks on every
	 * keystroke of a composition anyway (`-setMarkedText:` puts the new range back after calling this), so an edit that
	 * is NOT part of a composition is exactly the case where the marked text should stop being marked. */
	_cg_markedRange = NSMakeRange(NSNotFound, 0);

	if (range.location > length) {
		range.location = length;
	}
	if (range.location + range.length > length) {
		range.length = length - range.location;
	}
	/* **THE TEXT THIS EDIT REPLACES IS READ BEFORE THE STORE IS TOUCHED**, because it is what the undo action has to put
	 * back and the store is about to forget it. Retained for the same reason the run above is: the dictionary the store
	 * hands back is its own, and `-replaceCharactersInRange:` can free the run it came from. */
	{
		NSString *replaced = [[[_cg_textStorage string] substringWithRange:range] retain];

		[self cg_noteEditInRange:range insertedText:text replacedText:replaced];
		[replaced release];
	}
	if (length > 0 && range.location > 0) {
		/* **AND THE RUN IS RETAINED ACROSS THE EDIT, WHICH IS NOT TIDINESS.** A store's `-attributesAtIndex:` hands back
		 * the RUN'S OWN dictionary rather than a copy, and the `-replaceCharactersInRange:` below can free that run — so a
		 * dictionary read before the edit and applied after it (the inheritance this door is FOR) must own itself or it is
		 * read after it is freed. MEASURED: not retaining it segfaulted on the second keystroke of a composition, inside
		 * the very `-setAttributes:range:` that was applying it. */
		inherited = [[_cg_textStorage attributesAtIndex:range.location - 1 effectiveRange:NULL] retain];
	} else if (length > 0) {
		inherited = [[_cg_textStorage attributesAtIndex:0 effectiveRange:NULL] retain];
	} else if ([self font] != nil) {
		inherited = [[NSDictionary dictionaryWithObject:[self font] forKey:NSFontAttributeName] retain];
	}
	[_cg_textStorage beginEditing];
	[_cg_textStorage replaceCharactersInRange:range withString:text];
	if (inherited != nil && [text length] > 0) {
		[_cg_textStorage setAttributes:inherited range:NSMakeRange(range.location, [text length])];
	}
	[_cg_textStorage endEditing];
	[inherited release];
	[self setSelectedRange:NSMakeRange(range.location + [text length], 0)];
	/* **THE CHANGE IS ANNOUNCED THROUGH ITS OWN DOOR** rather than inline, because `-didChangeText` is Apple's public
	 * hook for "an edit just happened" and a subclass that overrides it must see every edit this class makes. */
	[self didChangeText];
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

/* **THE ANNOUNCEMENT THE EDIT PATH MAKES, AND THE PUBLIC HOOK IT IS.** `NSTextDidChangeNotification` goes to the centre
 * and to the delegate's `-textDidChange:`, which is exactly the pair `NSText`'s own commands make — so a keystroke, a
 * paste, a drop and an undo replay all announce themselves the same way, and a subclass that overrides this door sees
 * all four. IT DOES NOT TOUCH THE UNDO GROUP: the group's boundary is decided where the edit is recorded
 * (`NSTextViewEditing.m`), because that is the only place that knows whether an edit continues the run. */
- (void)didChangeText
{
	cg_announce(self, NSTextDidChangeNotification, @selector(textDidChange:));
}

/* **AND `-setString:` REPLACES THE WHOLE STORE**, keeping the view's font as the run the new text is set in, because a
 * setter is a caller saying what the text is and not throwing the face away with it. */
- (void)setString:(NSString *)string
{
	NSString *text = (string != nil) ? string : @"";
	id font = [self font];

	_cg_markedRange = NSMakeRange(NSNotFound, 0);

	[_cg_textStorage beginEditing];
	[_cg_textStorage replaceCharactersInRange:NSMakeRange(0, [_cg_textStorage length]) withString:text];
	if (font != nil && [text length] > 0) {
		[_cg_textStorage addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, [text length])];
	}
	[_cg_textStorage endEditing];
	[self setSelectedRange:NSMakeRange([text length], 0)];
	cg_announce(self, NSTextDidChangeNotification, @selector(textDidChange:));
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

/* **AND THE ALIGNMENT IS THE STORE'S PARAGRAPH STYLE NOW, WHICH RETIRES THE BASE'S DEFERRAL.** `NSText -setAlignment:`
 * stores and answers and says it does not move the glyphs, because a single-line field has no width to align WITHIN;
 * a text view has the manager's container width, so the style goes into the store and the manager offsets the line
 * inside that width. THE OTHER PROPERTIES OF THE STYLE TRAVEL WITH IT — a caller that set `-lineSpacing` on the run
 * keeps it — because this door takes a MUTABLE COPY of what is there rather than writing a fresh style over it. */
- (NSTextAlignment)alignment
{
	id style = nil;

	if ([_cg_textStorage length] > 0) {
		style = [[_cg_textStorage attributesAtIndex:0 effectiveRange:NULL]
					objectForKey:NSParagraphStyleAttributeName];
	}
	return (style != nil) ? [style alignment] : [super alignment];
}

- (void)setAlignment:(NSTextAlignment)alignment
{
	NSUInteger n = [_cg_textStorage length];
	id existing;
	NSMutableParagraphStyle *style;

	[super setAlignment:alignment];
	if (n == 0) {
		return;
	}
	existing = [[_cg_textStorage attributesAtIndex:0 effectiveRange:NULL]
				objectForKey:NSParagraphStyleAttributeName];
	style = (existing != nil) ? [existing mutableCopy]
				  : [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	[style setAlignment:alignment];
	[_cg_textStorage addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, n)];
	[style release];
}

/* **AND THE FONT IS CARRIED INTO THE STORE.** `NSText` answers `-font` from its own ivar and the manager reads the
 * store; setting one without the other would be two answers to one question, so this door writes both: the ivar
 * through the base and the run through the store. */
- (void)setFont:(id)font
{
	[super setFont:font];
	if (font != nil && [_cg_textStorage length] > 0) {
		[_cg_textStorage addAttribute:NSFontAttributeName value:font
					 range:NSMakeRange(0, [_cg_textStorage length])];
	}
}

/* **AND THE WIDTH IS THE CONTAINER'S.** A resize carries the new size into the container — LESS THE TWO SIDES OF THE
 * VIEW'S INSET, so an inset is a margin around the text rather than a shift of it — marks the layout stale, and re-fits
 * when the WIDTH moved, because that is what re-wraps. */
- (void)setFrameSize:(NSSize)newSize
{
	BOOL widthChanged = (newSize.width != [self frame].size.width);

	[super setFrameSize:newSize];
	[self cg_sizeContainerToFrame];
	[_cg_layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0, [_cg_textStorage length])
					     actualCharacterRange:NULL];
	if (widthChanged) {
		[self cg_fitHeight];
	}
	[self setNeedsDisplay:YES];
}

/* ============================================================================================ *
 * THE DRAWING: THE BACKDROP, THE SELECTION, THE MANAGER'S INK, AND THE CARET                    *
 * ============================================================================================ */

/* **AND THE BEZEL IS GONE, WHICH IS A DIFFERENCE FROM THE BASE WORTH STATING.** `NSText` is the editable surface under
 * a CONTROL, so it draws the field's border; a TEXT VIEW is the document itself, and Apple's draws no bezel either.
 * What it keeps is the BACKGROUND FILL and the SELECTION, both of which are the VIEW's — the selection because only
 * the view knows where it is. THE GLYPHS AND THEIR RUNS ARE THE MANAGER'S: a foreground colour, a background colour and
 * an underline all come out of `NSLayoutManager`'s two draw doors. */
/* **AND A LINE'S INK IS CLIPPED TO THE SUBRECT THE CONTAINER GAVE IT.** With a shaped container one logical line can
 * be set in more than one fragment, and an index at the boundary answers the NEXT part's x — so a band drawn from it
 * would span the hole between them. The fragment's used rect IS that part's ink, and clamping each band to it keeps
 * the selection and the composition rule inside the line they belong to. A simple rectangular container is unaffected:
 * its band and its fragment are the same width. */
- (CGFloat)cg_clampBandX:(CGFloat)x toLine:(NSUInteger)line
{
	NSRange range = [self cg_visualLineRangeAtIndex:line];
	NSRect used = [_cg_layoutManager lineFragmentUsedRectForGlyphAtIndex:range.location effectiveRange:NULL];
	/* THE USED RECT IS THE CONTAINER'S AND THE BAND IS THE VIEW'S, so the margin is added to the bounds and not to the x:
	 * the answer has to be in the same coordinates as the argument. */
	CGFloat min = used.origin.x + [self textContainerOrigin].x;
	CGFloat max = min + used.size.width;

	if (x < min) {
		return min;
	}
	if (x > max) {
		return max;
	}
	return x;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;
	NSFont *font = [self cg_font];
	CGFloat bandHeight = [font ascender] - [font descender];
	NSUInteger n = [[self string] length];

	(void)dirtyRect;
	if (cg == NULL) {
		return;
	}
	/* **THE BACKDROP IS A DOOR, NOT THREE LINES OF THIS METHOD**, because it is the one part of a text view's drawing a
	 * subclass replaces: a document with a watermark, a gutter, a paper colour. Everything below reads what it did. */
	[self drawViewBackgroundInRect:dirtyRect];
	/* **THE SELECTION IS CLIPPED TO EACH VISUAL LINE, ONE LINE AT A TIME**, which is what makes a selection that spans
	 * a break or a wrap draw as a band on each line it covers. The newline itself carries no band: there is no glyph
	 * there to highlight. */
	if ([self isSelectable] && _selectedRange.length > 0) {
		NSUInteger selStart = _selectedRange.location;
		NSUInteger selEnd = selStart + _selectedRange.length;
		NSUInteger count = [self cg_visualLineCount];
		NSUInteger i;

		for (i = 0; i < count; i++) {
			NSRange lr = [self cg_textRangeOfVisualLine:i];
			NSUInteger caretEnd = lr.location + lr.length;
			NSUInteger lo = (selStart > lr.location) ? selStart : lr.location;
			NSUInteger hi = (selEnd < caretEnd) ? selEnd : caretEnd;

			if (lo < hi) {
				CGFloat baseline = [self cg_baselineForLine:i];
				CGFloat x0 = [self cg_clampBandX:[self cg_xForIndex:lo] toLine:i];
				CGFloat x1 = [self cg_clampBandX:[self cg_xForIndex:hi] toLine:i];

				{
					/* **THE SELECTION'S INK IS THE SELECTED-TEXT ATTRIBUTES' BACKGROUND WHEN THERE IS ONE**, else
					 * the platform's accent — so a caller that wants its own selection colour sets it on the view and
					 * the drawing reads it, rather than a second selection-drawing path existing for that caller. */
					NSColor *fill = [[self selectedTextAttributes] objectForKey:NSBackgroundColorAttributeName];

					[(fill != nil ? fill : [NSColor cg_accentColor]) setFill];
					[[NSBezierPath bezierPathWithRect:
						NSMakeRect(x0, baseline - [font ascender], x1 - x0, bandHeight)] fill];
				}
			}
		}
	}
	/* AND THE STORE'S OWN INK, WHICH IS THE MANAGER'S TO LAY DOWN — backgrounds first, then the glyphs and the rules. */
	[_cg_layoutManager drawBackgroundForGlyphRange:NSMakeRange(0, n)
		atPoint:NSMakePoint([self textContainerOrigin].x, [self textContainerOrigin].y)];
	[_cg_layoutManager drawGlyphsForGlyphRange:NSMakeRange(0, n)
		atPoint:NSMakePoint([self textContainerOrigin].x, [self textContainerOrigin].y)];
	/* **AND THE SPELLING MARKS, WHICH THE VIEW OWNS BECAUSE THE MANAGER DOES NOT DECIDE WHAT IS MISSPELLED.** Each range
	 * a caller marked through `-setSpellingState:range:` is drawn as the era's red dotted rule, through the manager's
	 * own underline door — so the geometry comes from the layout and only the DECISION is the view's. */
	[self cg_drawSpellingUnderlines];
	[self cg_drawFindIndicator];
	/* **AND THE MARKED TEXT'S COMPOSITION MARK, WHICH IS THE VIEW'S BECAUSE THE STORE CANNOT CARRY IT.** A one-point rule
	 * below the baseline of every visual line the marked range covers, clipped to the range the way the selection band is
	 * — so a composition split across a wrap is underlined on both lines and a trailing space carries nothing. */
	if ([self hasMarkedText]) {
		NSUInteger markStart = _cg_markedRange.location;
		NSUInteger markEnd = markStart + _cg_markedRange.length;
		NSUInteger count = [self cg_visualLineCount];
		NSUInteger i;

		for (i = 0; i < count; i++) {
			NSRange lr = [self cg_visualLineRangeAtIndex:i];
			NSRange tr = [self cg_textRangeOfVisualLine:i];
			NSUInteger lineEnd = tr.location + tr.length;
			NSUInteger lo = (markStart > lr.location) ? markStart : lr.location;
			NSUInteger hi = (markEnd < lineEnd) ? markEnd : lineEnd;

			if (lo < hi) {
				CGFloat baseline = [self cg_baselineForLine:i];
				CGFloat x0 = [self cg_clampBandX:[self cg_xForIndex:lo] toLine:i];
				CGFloat x1 = [self cg_clampBandX:[self cg_xForIndex:hi] toLine:i];

				[[NSColor controlTextColor] setFill];
				[[NSBezierPath bezierPathWithRect:NSMakeRect(x0, baseline + 2.0, x1 - x0, 1.0)] fill];
			}
		}
	}
	/* AND THE CARET, ON WHICHEVER VISUAL LINE IT IS ON — which is the LAST line that starts at or before it, so a caret
	 * just after a hard break sits on the empty line it opened. **AND IT GOES THROUGH THE DOOR, WHICH IS WHAT MAKES
	 * `-insertionPointColor` REAL**: the colour below is the view's own, and the rect is the same one a caller would
	 * compute, so a subclass that overrides the drawing door gets every caret in the view and not just one it draws. */
	if ([self shouldDrawInsertionPoint]) {
		NSUInteger caretLine = [self cg_visualLineIndexForCharacterIndex:_selectedRange.location];
		CGFloat baseline = [self cg_baselineForLine:caretLine];
		NSRect caret = NSMakeRect([self cg_xForIndex:_selectedRange.location], baseline - [font ascender], 1.0,
					  bandHeight);
		NSColor *pen = [self insertionPointColor];

		[self drawInsertionPointInRect:caret color:(pen != nil ? pen : [NSColor controlTextColor]) turnedOn:YES];
	}
}

/* ============================================================================================ *
 * THE POINTER: A CLICK LANDS ON THE VISUAL LINE IT IS OVER                                      *
 * ============================================================================================ */

/* **AND AN ATTACHMENT'S BOX IS WHERE THE MANAGER DRAWS IT, WHICH IS THE ONE ARITHMETIC THE VIEW NEEDS.** The manager
 * records the box on the attachment character and draws it ABOVE the baseline in container coordinates; the view's
 * own inset is the only translation, so the frame a hit test reads is the frame the ink occupies. A character with no
 * attachment, or one whose cell measures nothing, answers an EMPTY rect and is never hit. */
- (NSRect)cg_frameForAttachmentAtIndex:(NSUInteger)index
{
	NSTextAttachment *attachment;
	NSCell<NSTextAttachmentCell> *cell;
	NSSize size;
	NSUInteger line;

	if (_cg_textStorage == nil || index >= [_cg_textStorage length]) {
		return NSZeroRect;
	}
	attachment = [_cg_textStorage attribute:NSAttachmentAttributeName atIndex:index effectiveRange:NULL];
	cell = [attachment attachmentCell];
	size = (cell != nil) ? [cell cellSize] : NSZeroSize;
	if (size.width <= 0.0 || size.height <= 0.0) {
		return NSZeroRect;
	}
	line = [self cg_visualLineIndexForCharacterIndex:index];
	return NSMakeRect([self cg_xForIndex:index],
			  [self cg_baselineForLine:line] - size.height, size.width, size.height);
}

/* **AND WHICH CELL A POINT IS ON, IF ANY.** The hit test answers the NEAREST character, so a point in the right half
 * of a box can come back as the character AFTER the attachment — which is why the candidate and its predecessor are
 * both tried, and why the point must fall inside the FRAME rather than merely on the character's own index. */
- (BOOL)cg_attachmentAtPoint:(NSPoint)point cell:(NSCell<NSTextAttachmentCell> **)outCell
		       index:(NSUInteger *)outIndex frame:(NSRect *)outFrame
{
	NSUInteger hit;
	NSUInteger candidates[2];
	NSUInteger count = 0;
	NSUInteger i;

	if (_cg_textStorage == nil || [_cg_textStorage length] == 0) {
		return NO;
	}
	hit = [self cg_indexForPoint:point];
	if (hit < [_cg_textStorage length]
	    && [_cg_textStorage attribute:NSAttachmentAttributeName atIndex:hit effectiveRange:NULL] != nil) {
		candidates[count++] = hit;
	}
	if (hit > 0
	    && [_cg_textStorage attribute:NSAttachmentAttributeName atIndex:hit - 1 effectiveRange:NULL] != nil) {
		candidates[count++] = hit - 1;
	}
	for (i = 0; i < count; i++) {
		NSRect frame = [self cg_frameForAttachmentAtIndex:candidates[i]];

		if (frame.size.width > 0.0 && frame.size.height > 0.0 && NSPointInRect(point, frame)) {
			NSTextAttachment *attachment = [_cg_textStorage attribute:NSAttachmentAttributeName
									 atIndex:candidates[i] effectiveRange:NULL];

			if (outCell != NULL) {
				*outCell = [attachment attachmentCell];
			}
			if (outIndex != NULL) {
				*outIndex = candidates[i];
			}
			if (outFrame != NULL) {
				*outFrame = frame;
			}
			return YES;
		}
	}
	return NO;
}

/* **AND ONE EVENT TO THE TRACKED CELL, THROUGH THE MOST SPECIFIC DOOR IT ANSWERS.** The character-index variant is
 * asked first because it is the sophisticated half of Apple's protocol and the one that knows WHICH attachment it is;
 * a cell that implements only the plain door still works. NO from the cell means it declined the event. */
- (BOOL)cg_trackAttachmentWithEvent:(NSEvent *)event
{
	NSCell<NSTextAttachmentCell> *cell = (NSCell<NSTextAttachmentCell> *)_cg_trackingCell;

	if ([cell respondsToSelector:@selector(trackMouse:inRect:ofView:atCharacterIndex:untilMouseUp:)]) {
		return [cell trackMouse:event inRect:_cg_trackingFrame ofView:self
			atCharacterIndex:_cg_trackingIndex untilMouseUp:YES];
	}
	if ([cell respondsToSelector:@selector(trackMouse:inRect:ofView:untilMouseUp:)]) {
		return [cell trackMouse:event inRect:_cg_trackingFrame ofView:self untilMouseUp:YES];
	}
	return NO;
}

/* THE SESSION'S END, which releases the retained cell and forgets the frame it occupied. */
- (void)cg_endAttachmentTracking
{
	[(id)_cg_trackingCell release];
	_cg_trackingCell = nil;
	_cg_trackingIndex = 0;
	_cg_trackingFrame = NSZeroRect;
}

/* **A PRESS ON AN ATTACHMENT IS OFFERED TO ITS CELL BEFORE IT IS A CARET.** The cell that wants the mouse OWNS the
 * gesture: the view selects the attachment character so the click is visible, starts the session, and sends the DOWN
 * through the cell's tracking door. A cell that declines — or implements neither tracking door — leaves an ordinary
 * click, which is why that path falls through rather than swallowing the press. */
- (void)mouseDown:(NSEvent *)event
{
	NSPoint point;
	NSCell<NSTextAttachmentCell> *cell = nil;
	NSUInteger index = 0;
	NSRect frame = NSZeroRect;

	if ([self isEditable]) {
		[[self window] makeFirstResponder:self];
	}
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	if ([self cg_attachmentAtPoint:point cell:&cell index:&index frame:&frame] && cell != nil) {
		BOOL wants = NO;

		if ([cell respondsToSelector:@selector(wantsToTrackMouseForEvent:inRect:ofView:atCharacterIndex:)]) {
			wants = [cell wantsToTrackMouseForEvent:event inRect:frame ofView:self atCharacterIndex:index];
		} else if ([cell respondsToSelector:@selector(wantsToTrackMouse)]) {
			wants = [cell wantsToTrackMouse];
		}
		if (wants) {
			_cg_trackingCell = [cell retain];
			_cg_trackingIndex = index;
			_cg_trackingFrame = frame;
			[self setSelectedRange:NSMakeRange(index, 1)];
			if ([self cg_trackAttachmentWithEvent:event]) {
				_dragging = NO;
				return;
			}
			/* THE CELL DECLINED THE PRESS ITSELF, so the ordinary click below is what happens. */
			[self cg_endAttachmentTracking];
		}
	}
	if (![self isSelectable]) {
		return;
	}
	index = [self cg_indexForPoint:point];
	_dragAnchor = index;
	[self setSelectedRange:NSMakeRange(index, 0)];
	_dragging = YES;
}

- (void)mouseDragged:(NSEvent *)event
{
	NSUInteger here;

	if (_cg_trackingCell != nil) {
		[self cg_trackAttachmentWithEvent:event];
		return;
	}
	if (!_dragging) {
		return;
	}
	here = [self cg_indexForPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
	[self setSelectedRange:(here < _dragAnchor) ? NSMakeRange(here, _dragAnchor - here)
						    : NSMakeRange(_dragAnchor, here - _dragAnchor)];
}

/* **AND THE RELEASE ENDS THE SESSION WHATEVER THE CELL SAYS** — the up event is the last one the view will send it,
 * and the cell's answer is Apple's "came up inside" rather than an instruction to keep going. The base's own release
 * (which ends a text selection drag) runs when no attachment is being tracked. */
- (void)mouseUp:(NSEvent *)event
{
	if (_cg_trackingCell != nil) {
		[self cg_trackAttachmentWithEvent:event];
		[self cg_endAttachmentTracking];
		return;
	}
	[super mouseUp:event];
}

/* ============================================================================================ *
 * THE EDITING: WHAT A ONE-LINE VIEW REFUSES, AND WHY THIS ONE DOES NOT                           *
 * ============================================================================================ */

/* **A NEWLINE IS TEXT HERE, WHICH IS THE ONE REFUSAL THIS CLASS OVERTURNS.** `NSText -insertText:` drops a newline by
 * name because it holds one line; a text view's whole point is that the break is a character like any other, so the
 * edit goes through this class's own primitive — which edits the STORE — and the layout follows.
 *
 * **AND AN INSERT THAT CONFIRMS A COMPOSITION REPLACES THE MARKED RANGE RATHER THAN THE SELECTION.** An input method
 * commits what it was composing by calling this door, and the caret sits INSIDE the mark while it does — so replacing
 * the selection would splice the confirmed text into the middle of the composition instead of over it.
 *
 * **AND THE MODERN DOOR MAY NAME WHAT IT REPLACES.** `-insertText:replacementRange:` is the same edit with the target
 * handed in instead of inferred: a range with a location replaces exactly that range, and `NSNotFound` falls back to
 * the rule above (the marked range, else the selection). The characters are what is inserted, and the run they inherit
 * is the one at the insertion point — this view's standing rule — so an `NSAttributedString`'s ATTRIBUTES are not
 * applied by this pair; the marked-text drawing is the view's own (see `-drawRect:`). */
- (void)insertText:(id)insertString
{
	[self insertText:insertString replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)insertText:(id)insertString replacementRange:(NSRange)replacementRange
{
	NSString *text = ([insertString isKindOfClass:[NSAttributedString class]])
			 ? [(NSAttributedString *)insertString string] : (NSString *)insertString;
	NSRange target;

	if (![self isEditable] || text == nil) {
		return;
	}
	target = (replacementRange.location != NSNotFound)
		 ? replacementRange
		 : ([self hasMarkedText] ? _cg_markedRange : _selectedRange);
	/* **AND THE SMART SPACES ARE ADDED BEFORE ANYBODY IS ASKED ABOUT THE EDIT**, so `-shouldChangeTextInRange:…`
	 * and the delegate behind it are asked about the string that will actually be inserted rather than about the
	 * caller's, and the undo action records one edit instead of three. A COMPOSITION IS EXEMPT: an input method commits
	 * into the middle of a word it is still composing, where a space inserted by this rule would be wrong — the same
	 * reason the marked range is the target above. */
	if (_cg_smartInsertDelete && [text length] > 0 && ![self hasMarkedText]) {
		text = [self cg_textWithSmartInsertionForString:text range:target];
	}
	{
		NSRange edit = NSMakeRange(MIN(target.location, [_cg_textStorage length]),
					   MIN(target.length, [_cg_textStorage length] - MIN(target.location, [_cg_textStorage length])));

		if (![self shouldChangeTextInRange:edit replacementString:text]) {
			return;
		}
	}
	[self replaceCharactersInRange:target withString:text];
	/* **AND A CALLER'S TYPING ATTRIBUTES ARE APPLIED TO WHAT WAS JUST TYPED.** The store already gave the inserted run
	 * the attributes at the insertion point; a dictionary the caller set through `-setTypingAttributes:` then overrides
	 * them, which is what makes "bold is on" true for the next keystroke. */
	if (_cg_typingAttributes != nil) {
		NSUInteger length = [_cg_textStorage length];
		NSUInteger start = MIN((NSUInteger)target.location, length);
		NSUInteger inserted = MIN([text length], length - start);

		if (inserted > 0) {
			[_cg_textStorage addAttributes:_cg_typingAttributes range:NSMakeRange(start, inserted)];
		}
	}
}

/* **AND THE TWO KEYS THAT MEANT "I AM DONE WITH THIS FIELD" NOW MEAN "PUT A BREAK HERE" AND "PUT A TAB HERE".** */
- (void)insertNewline:(id)sender
{
	(void)sender;
	[self insertText:@"\n"];
}

- (void)insertTab:(id)sender
{
	(void)sender;
	[self insertText:@"\t"];
}

/* ============================================================================================ *
 * THE MARKED TEXT: WHAT AN INPUT METHOD IS COMPOSING, SAID IN `NSTextInput.h`                     *
 * ============================================================================================ */

/* **THE MARKED CHARACTERS ARE REALLY IN THE STORE**, which is what makes a composition an ordinary edit with an
 * ordinary caret: an input method replaces its marked range on every keystroke, the layout re-wraps, and the caret is
 * placed inside the composition by the range it was told. WHAT IS NOT IN THE STORE IS THE FACT THAT THEY ARE MARKED — a
 * character range cannot carry its own temporary state — so the RANGE lives here and the view draws the composition
 * mark itself (see `-drawRect:`). That is the same division the selection uses: the store holds text and attributes,
 * the view holds the transient facts about it. */
- (BOOL)hasMarkedText
{
	return _cg_markedRange.location != NSNotFound;
}

- (NSRange)markedRange
{
	return (_cg_markedRange.location != NSNotFound) ? _cg_markedRange : NSMakeRange(NSNotFound, 0);
}

/* **EVERY KEYSTROKE OF A COMPOSITION IS ONE CALL, AND THE STRING IS THE WHOLE COMPOSITION SO FAR.** The target is the
 * marked range when there is one — a composition grows by replacing itself — and the SELECTION otherwise, which is how
 * the first keystroke starts one. An EMPTY string clears the marked text, which is the input method taking a
 * composition back.
 *
 * **AND THE MODERN DOOR NAMES THE RANGE ITSELF**, with `NSNotFound` meaning the rule above. `selectedRange` is
 * measured INSIDE the string being inserted — the 10.6 header says so in as many words — which is why the caret is
 * written as `location + selectedRange.location` rather than taken as a document range. */
- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange
{
	NSRange target = [self hasMarkedText] ? _cg_markedRange : _selectedRange;

	[self cg_setMarkedText:string selectedRange:selectedRange inRange:target];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange
{
	NSRange target = (replacementRange.location != NSNotFound)
		 ? replacementRange
		 : ([self hasMarkedText] ? _cg_markedRange : _selectedRange);

	[self cg_setMarkedText:string selectedRange:selectedRange inRange:target];
}

/* THE BODY BOTH DOORS SHARE. The target is CLAMPED BEFORE its location is remembered: an explicit range past the end
 * would otherwise put the marked range's recorded location there even after the edit primitive brought the actual
 * replacement back inside the store. */
- (void)cg_setMarkedText:(id)string selectedRange:(NSRange)selectedRange inRange:(NSRange)target
{
	NSString *text = ([string isKindOfClass:[NSAttributedString class]])
			 ? [(NSAttributedString *)string string] : (NSString *)string;
	NSUInteger length = [_cg_textStorage length];
	NSUInteger location;

	if (target.location > length) {
		target.location = length;
	}
	if (target.location + target.length > length) {
		target.length = length - target.location;
	}
	location = target.location;
	if (text == nil) {
		text = @"";
	}
	[self replaceCharactersInRange:target withString:text];
	if ([text length] > 0) {
		_cg_markedRange = NSMakeRange(location, [text length]);
		/* **AND THE COMPOSITION WEARS THE MARKED ATTRIBUTES**, which is where that dictionary has its reader: the
		 * underline a caller set appears under the characters as they arrive, through the same store the layout
		 * manager draws from. */
		[_cg_textStorage addAttributes:[self markedTextAttributes] range:_cg_markedRange];
		[self setSelectedRange:NSMakeRange(location + selectedRange.location, selectedRange.length)];
	} else {
		_cg_markedRange = NSMakeRange(NSNotFound, 0);
	}
	[self setNeedsDisplay:YES];
}

- (void)unmarkText
{
	_cg_markedRange = NSMakeRange(NSNotFound, 0);
	[self setNeedsDisplay:YES];
}

/* THE ATTRIBUTES AN INPUT METHOD MAY SET ON WHAT IT INSERTS. This view can draw a foreground, a background and the two
 * rules, so those are what it offers; a view that supported nothing beyond plain text would answer an empty array. */
- (NSArray *)validAttributesForMarkedText
{
	return [NSArray arrayWithObjects:NSUnderlineStyleAttributeName, NSUnderlineColorAttributeName,
			NSBackgroundColorAttributeName, NSForegroundColorAttributeName, nil];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range
{
	NSUInteger n = [_cg_textStorage length];

	if (range.location > n) {
		range.location = n;
	}
	if (range.location + range.length > n) {
		range.length = n - range.location;
	}
	return [_cg_textStorage attributedSubstringFromRange:range];
}

/* **AND THE TWO SCREEN QUESTIONS A CANDIDATE WINDOW ASKS.** `-firstRectForCharacterRange:` is the caret's own rectangle
 * moved into SCREEN coordinates — the view's rectangle, into the window's, plus the window's frame origin — and
 * `-characterIndexForPoint:` is that conversion run backwards. THE CONVERSION IS THE WINDOW'S FRAME ORIGIN because this
 * tier has no `-convertRectToScreen:`; a window on Agora's own server is placed where its frame says, so the origin is
 * the whole of the transformation this tier owns. */
- (NSRect)firstRectForCharacterRange:(NSRange)range
{
	NSRect rect = [self cg_rectForCharacterIndex:range.location];
	NSRect inWindow = [self convertRect:rect toView:nil];
	NSRect frame = [[self window] frame];

	return NSMakeRect(inWindow.origin.x + frame.origin.x, inWindow.origin.y + frame.origin.y,
			  inWindow.size.width, inWindow.size.height);
}

/* **AND THE MODERN DOOR WRITES BACK WHAT IT ACTUALLY ANSWERED**, the same way the substring door does. The proposal is
 * clamped to the store's own length — an out-of-document range is answered as an empty range at the end — and the
 * clamped range is what `actualRange` receives. THE RECTANGLE IS THE FIRST CHARACTER's, which is the 10.6 header's own
 * wording ("the first logical rectangular area") and the old door's answer; this tier's text flows left to right, so a
 * range's first character is its first logical area. */
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange
{
	NSUInteger length = [_cg_textStorage length];
	NSRange clamped = range;

	if (clamped.location > length) {
		clamped.location = length;
	}
	if (clamped.location + clamped.length > length) {
		clamped.length = length - clamped.location;
	}
	if (actualRange != NULL) {
		*actualRange = clamped;
	}
	return [self firstRectForCharacterRange:clamped];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
	NSRect frame = [[self window] frame];
	NSPoint inWindow = NSMakePoint(point.x - frame.origin.x, point.y - frame.origin.y);

	return [self cg_indexForPoint:[self convertPoint:inWindow fromView:nil]];
}

/* ============================================================================================ *
 * AND THE `NSTextInputClient` DOORS, WHICH ARE THE ONES AN INPUT METHOD MODERN ENOUGH TO ASK FOR  *
 * A CANDIDATE WINDOW'S PLACEMENT NEEDS. Nine of the fifteen are new in this class; the other six are the
 * ones `NSTextInput` already had and `NSText`'s and `NSResponder`'s ancestors already answer.     *
 * ============================================================================================ */

/* **THE SUBSTRING, WITH THE RANGE IT ACTUALLY GOT.** The proposed range is CLAMPED to the store and the clamped one is
 * written back, which is the whole reason this door has two ranges where `NSTextInput`'s has one: a method asking for
 * more than the document holds is told what it received rather than being left to assume. */
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange
{
	NSUInteger n = [_cg_textStorage length];
	NSRange clamped = range;

	if (clamped.location > n) {
		clamped.location = n;
	}
	if (clamped.location + clamped.length > n) {
		clamped.length = n - clamped.location;
	}
	if (actualRange != NULL) {
		*actualRange = clamped;
	}
	return [_cg_textStorage attributedSubstringFromRange:clamped];
}

/* THE WHOLE DOCUMENT, which is what a method reads when it wants more context than a proposed range gives it. A COPY,
 * because the caller is not the owner — the same rule `-attributedSubstringFromRange:` follows. */
- (NSAttributedString *)attributedString
{
	return [[_cg_textStorage copy] autorelease];
}

/* **AND WHERE A POINT FALLS WITHIN THE GLYPH IT HIT** — measured against the CHARACTER's box, and the deviation is stated
 * rather than hidden: this layer sets one glyph per character except where a face ligates or composes, so a character's
 * box IS its glyph's for the text it draws, and the manager's `-boundingRectForGlyphRange:` is the FLOW BAND (the
 * column's width) rather than an ink box — MEASURED at 200 points for a single glyph, which is the whole view. So the box
 * comes from the view's own per-character rect, which is what the caret and the candidate window are placed from anyway.
 * A box of no width answers 0, the only honest fraction for it. */
- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point
{
	NSRect frame = [[self window] frame];
	NSPoint inWindow = NSMakePoint(point.x - frame.origin.x, point.y - frame.origin.y);
	NSPoint local = [self convertPoint:inWindow fromView:nil];
	NSRect box = [self cg_rectForCharacterIndex:[self cg_indexForPoint:local]];
	CGFloat fraction;

	if (box.size.width <= 0.0) {
		return 0.0;
	}
	fraction = (local.x - box.origin.x) / box.size.width;
	if (fraction < 0.0) {
		return 0.0;
	}
	return (fraction > 1.0) ? 1.0 : fraction;
}

/* **AND TWO ANSWERS THAT ARE FACTS ABOUT THIS LAYER RATHER THAN ABOUT THE POINT**: every line sits ON its baseline, so
 * the delta is zero; and there is no vertical text here, so nothing is drawn vertically. A caller that places a
 * candidate window with these gets the right place for a horizontal view, which is the only kind there is. */
- (CGFloat)baselineDeltaForCharacterAtIndex:(NSUInteger)anIndex
{
	(void)anIndex;
	return 0.0;
}

- (BOOL)drawsVerticallyForCharacterAtIndex:(NSUInteger)charIndex
{
	(void)charIndex;
	return NO;
}

/* THE WINDOW'S LEVEL, which is what a candidate window is ordered against — and `NSWindow`'s own door, not a second
 * opinion about it. A view with no window answers the normal level, because that is where a windowless view would be. */
- (NSInteger)windowLevel
{
	NSWindow *window = [self window];

	return (window != nil) ? [window level] : NSNormalWindowLevel;
}

/* ============================================================================================ *
 * THE MOVEMENT: "THE LINE" MEANS THE VISUAL LINE, WHICH IS WHAT A PERSON SEES                     *
 * ============================================================================================ */

- (void)moveToBeginningOfLine:(id)sender
{
	NSRange range = [self cg_textRangeOfVisualLine:
		[self cg_visualLineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location, 0)];
}

- (void)moveToEndOfLine:(id)sender
{
	NSRange range = [self cg_textRangeOfVisualLine:
		[self cg_visualLineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location + range.length, 0)];
}

- (void)moveToBeginningOfLineAndModifySelection:(id)sender
{
	NSRange range = [self cg_textRangeOfVisualLine:
		[self cg_visualLineIndexForCharacterIndex:_selectedRange.location]];
	NSUInteger end = _selectedRange.location + _selectedRange.length;

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location, end - range.location)];
}

- (void)moveToEndOfLineAndModifySelection:(id)sender
{
	NSRange range = [self cg_textRangeOfVisualLine:
		[self cg_visualLineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(_selectedRange.location,
					   range.location + range.length - _selectedRange.location)];
}

/* **A SELECTION COLLAPSES BEFORE THE STEP, AND TO THE END THE STEP IS GOING AWAY FROM** — the character movements'
 * rule, one line up: Down from a selection starts at its END (the bottom of it) and Up from its START. */
- (void)moveUp:(id)sender
{
	NSUInteger location = _selectedRange.location;
	NSUInteger line;
	CGFloat x;

	(void)sender;
	if (_selectedRange.length > 0) {
		[self setSelectedRange:NSMakeRange(location, 0)];
	}
	line = [self cg_visualLineIndexForCharacterIndex:location];
	if (line == 0) {
		return;
	}
	x = [self cg_xForIndex:location];
	[self setSelectedRange:NSMakeRange([self cg_indexOnLine:line - 1 atX:x], 0)];
}

- (void)moveDown:(id)sender
{
	NSUInteger end = _selectedRange.location + _selectedRange.length;
	NSUInteger location = end;
	NSUInteger line;
	CGFloat x;

	(void)sender;
	if (_selectedRange.length > 0) {
		[self setSelectedRange:NSMakeRange(end, 0)];
	}
	line = [self cg_visualLineIndexForCharacterIndex:location];
	if (line + 1 >= [self cg_visualLineCount]) {
		return;
	}
	x = [self cg_xForIndex:location];
	[self setSelectedRange:NSMakeRange([self cg_indexOnLine:line + 1 atX:x], 0)];
}

/* **AND EXTENDING BY A LINE MOVES THE ONE END THE DIRECTION MOVES.** */
- (void)moveUpAndModifySelection:(id)sender
{
	NSUInteger location = _selectedRange.location;
	NSUInteger end = location + _selectedRange.length;
	NSUInteger line = [self cg_visualLineIndexForCharacterIndex:location];
	NSUInteger target;

	(void)sender;
	if (line == 0) {
		return;
	}
	target = [self cg_indexOnLine:line - 1 atX:[self cg_xForIndex:location]];
	[self setSelectedRange:NSMakeRange(target, end - target)];
}

- (void)moveDownAndModifySelection:(id)sender
{
	NSUInteger location = _selectedRange.location;
	NSUInteger end = location + _selectedRange.length;
	NSUInteger line = [self cg_visualLineIndexForCharacterIndex:end];
	NSUInteger target;

	(void)sender;
	if (line + 1 >= [self cg_visualLineCount]) {
		return;
	}
	target = [self cg_indexOnLine:line + 1 atX:[self cg_xForIndex:end]];
	[self setSelectedRange:NSMakeRange(location, target - location)];
}

/* **AND THE TWO DOCUMENT ENDS, WHICH ARE THE STRING'S OWN TWO ENDS.** */
- (void)moveToBeginningOfDocument:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange(0, 0)];
}

- (void)moveToEndOfDocument:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange([[self string] length], 0)];
}

- (void)moveToBeginningOfDocumentAndModifySelection:(id)sender
{
	NSUInteger end = _selectedRange.location + _selectedRange.length;

	(void)sender;
	[self setSelectedRange:NSMakeRange(0, end)];
}

- (void)moveToEndOfDocumentAndModifySelection:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange(_selectedRange.location, [[self string] length] - _selectedRange.location)];
}

/* ==================================================================================================================
 * THE RULER.
 *
 * The view's side of it, in three layers: the show/hide state (`-usesRuler`, `-setRulerVisible:`), the reconciliation
 * (`-updateRuler` reads the paragraph at the insertion point and asks the manager for one marker per tab stop), and the
 * nine question the ruler asks its client back — of which the three `did` ones are the behaviour, because they rebuild
 * the paragraph's tab stops from the marker list.
 *
 * **THE PARAGRAPH IS THE INSERTION POINT'S, NOT THE SELECTION'S SPAN.** A ruler describes the paragraph the caret is in,
 * which is what Apple's text system does and what makes the markers change when the caret crosses a paragraph boundary.
 * A caller wanting a ruler for several paragraphs has a selection whose START is the paragraph in question.
 * ================================================================================================================ */

/* THE PAYLOAD'S KEYS, WHICH ARE THIS TIER'S RATHER THAN APPLE'S. `NSRulerPboardType` carries an opaque blob in Apple's
 * implementation; here it is a property list of the ruler's FACTS, because a `NSParagraphStyle` is not a property-list
 * type and a pasteboard that needed a keyed archive would be a heavier dependency than a ruler deserves. The names are
 * spelled once and read back by the same constants, so a paste can never disagree with a copy about a key. */
static NSString * const AGRulerAlignmentKey = @"Alignment";
static NSString * const AGRulerFontNameKey = @"FontName";
static NSString * const AGRulerFontSizeKey = @"FontSize";
static NSString * const AGRulerTabStopsKey = @"TabStops";
static NSString * const AGRulerTabLocationKey = @"Location";
static NSString * const AGRulerTabTypeKey = @"Type";
static NSString * const AGRulerHeadIndentKey = @"HeadIndent";
static NSString * const AGRulerFirstLineHeadIndentKey = @"FirstLineHeadIndent";
static NSString * const AGRulerTailIndentKey = @"TailIndent";
static NSString * const AGRulerLineSpacingKey = @"LineSpacing";
static NSString * const AGRulerParagraphSpacingKey = @"ParagraphSpacing";
static NSString * const AGRulerParagraphSpacingBeforeKey = @"ParagraphSpacingBefore";
static NSString * const AGRulerLineHeightMultipleKey = @"LineHeightMultiple";

/* **AND THE RULER FOLLOWS THE CARET'S PARAGRAPH.** Every movement and every edit ends in a selection change — `NSText`
 * makes that true — so hanging the ruler's update here is what makes it track the caret without a notification of its
 * own. It is guarded by the two flags, so a view with no ruler pays one comparison. */
- (void)setSelectedRange:(NSRange)range
{
	[super setSelectedRange:range];
	if (_usesRuler && [self isRulerVisible]) {
		[self updateRuler];
	}
}

- (BOOL)usesRuler
{
	return _usesRuler;
}

- (void)setUsesRuler:(BOOL)flag
{
	BOOL value = flag ? YES : NO;

	if (value == _usesRuler) {
		return;
	}
	_usesRuler = value;
	/* **A VIEW THAT STOPS USING A RULER PUTS IT AWAY.** Leaving a visible ruler measuring a view that no longer wants one
	 * is the state Apple's split exists to avoid. */
	if (!value) {
		[self setRulerVisible:NO];
	}
}

- (BOOL)isRulerVisible
{
	NSScrollView *scroll = [self enclosingScrollView];

	if (_usesRuler && scroll != nil) {
		return [scroll rulersVisible];
	}
	return NO;
}

/* **SHOWING IT IS THREE FACTS, IN THIS ORDER.** The scroll view must HAVE a horizontal ruler, it must be VISIBLE, and
 * then the markers are rebuilt from the paragraph — because a ruler that appeared with the previous paragraph's tabs
 * would be showing a document that is not there. Hiding it is one fact, and it keeps the markers, which is the
 * scroll view's own split between "has" and "shows". */
- (void)setRulerVisible:(BOOL)flag
{
	NSScrollView *scroll = [self enclosingScrollView];

	if (!flag) {
		[scroll setRulersVisible:NO];
		return;
	}
	if (!_usesRuler) {
		return;
	}
	if (scroll == nil) {
		fn_refuse_window("NSTextView -setRulerVisible:",
				 "an enclosing scroll view to wear the ruler; a text view laid out by hand has no strip to put it in");
		return;
	}
	[scroll setHasHorizontalRuler:YES];
	[scroll setRulersVisible:YES];
	{
		NSRulerView *ruler = [scroll horizontalRulerView];

		/* **THE RULE STRIP IS SIZED FOR MARKS AND NUMBERS, NOT FOR APPLE'S FIFTEEN.** A text ruler is a tab-stop strip:
		 * eight points of tick, a nine-point label above it, and the markers in the band the scroll view reserves for
		 * them — so fifteen is one point too many and fourteen is what the drawing actually spends. */
		[ruler setRuleThickness:14.0];
		/* **AND THE RULER'S ZERO IS WHERE THE TEXT'S ZERO IS**: the container's padding plus whatever margin the view
		 * has put around it, or a tab stop at 40 points would be drawn 40 points from the view's edge while the text
		 * it belongs to starts at the margin. */
		[ruler setOriginOffset:[self textContainerOrigin].x + NS_TEXT_INSET];
		[ruler setClientView:self];
	}
	[self updateRuler];
}

/* **THE RECONCILIATION.** One paragraph style in, one marker per tab stop out, and the reserve that keeps them inside
 * the strip. A view whose store is empty still gets a ruler — with no markers — because the STRIP is a fact about the
 * view and not about its text. */
- (void)updateRuler
{
	NSScrollView *scroll = [self enclosingScrollView];
	NSRulerView *ruler;
	NSParagraphStyle *style = nil;
	NSArray *markers;
	NSView *accessory;
	NSUInteger index = _selectedRange.location;
	CGFloat tallest = 0.0;
	NSUInteger i;

	if (!_usesRuler || scroll == nil || ![scroll rulersVisible]) {
		return;
	}
	ruler = [scroll horizontalRulerView];
	if (ruler == nil) {
		return;
	}
	[ruler setClientView:self];
	if ([_cg_textStorage length] > 0) {
		NSRange effective = NSMakeRange(0, 0);

		if (index >= [_cg_textStorage length]) {
			index = [_cg_textStorage length] - 1;
		}
		style = [[_cg_textStorage attributesAtIndex:index effectiveRange:&effective]
			    objectForKey:NSParagraphStyleAttributeName];
	}
	if (style == nil) {
		style = [NSParagraphStyle defaultParagraphStyle];
	}
	markers = [_cg_layoutManager rulerMarkersForTextView:self paragraphStyle:style ruler:ruler];
	[ruler setMarkers:markers];
	for (i = 0; i < [markers count]; i++) {
		CGFloat needed = [[markers objectAtIndex:i] thicknessRequiredInRuler];

		if (needed > tallest) {
			tallest = needed;
		}
	}
	[ruler setReservedThicknessForMarkers:tallest];
	/* **AND THE ACCESSORY, WHICH IS THE MANAGER'S ANSWER AND MAY BE NIL.** The reserve is set from what came back rather
	 * than assumed, so the refusal costs no thickness and a future accessory costs exactly its own. */
	accessory = [_cg_layoutManager rulerAccessoryViewForTextView:self paragraphStyle:style ruler:ruler enabled:YES];
	[ruler setAccessoryView:accessory];
	[ruler setReservedThicknessForAccessoryView:accessory != nil
		? (([ruler orientation] == NSVerticalRuler) ? NSWidth([accessory frame]) : NSHeight([accessory frame]))
		: 0.0];
	[ruler invalidateHashMarks];
}

/* ==================================================================================================================
 * THE MARKERS BECOME THE PARAGRAPH.
 *
 * **ONE PATH FOR ADD, MOVE AND REMOVE, BECAUSE THEY ARE THE SAME FACT.** The ruler's marker list is the truth after any
 * of the three, so the paragraph's tab stops are rebuilt from the WHOLE list — sorted by location, each one's kind read
 * back out of its `representedObject` — and written to the insertion point's paragraph. A per-gesture edit would be
 * three chances to disagree about ordering; this is one.
 * ================================================================================================================ */

- (void)cg_applyRulerMarkers:(NSRulerView *)ruler
{
	NSArray *markers;
	NSMutableArray *tabs;
	NSMutableParagraphStyle *style;
	NSRange paragraph;
	NSUInteger index;
	NSUInteger i;

	if (ruler == nil || [_cg_textStorage length] == 0) {
		return;
	}
	index = (_selectedRange.location < [_cg_textStorage length]) ? _selectedRange.location
								    : [_cg_textStorage length] - 1;
	style = [[[_cg_textStorage attributesAtIndex:index effectiveRange:NULL]
		     objectForKey:NSParagraphStyleAttributeName] mutableCopy];
	if (style == nil) {
		style = [[NSMutableParagraphStyle alloc] init];
	}
	markers = [ruler markers];
	tabs = [NSMutableArray arrayWithCapacity:[markers count]];
	for (i = 0; i < [markers count]; i++) {
		NSRulerMarker *marker = [markers objectAtIndex:i];
		id represented = [marker representedObject];
		NSTextTabType type = [represented isKindOfClass:[NSTextTab class]]
					 ? [(NSTextTab *)represented tabStopType] : NSLeftTabStopType;
		CGFloat location = [marker markerLocation] - [ruler originOffset];
		NSTextTab *tab;
		NSUInteger insertAt = 0;

		if (location < 0.0) {
			location = 0.0;
		}
		tab = [[NSTextTab alloc] initWithType:type location:location];
		/* **THE LIST IS KEPT SORTED AS IT IS BUILT**, because `-tabStops` is documented in ascending order and the
		 * layout walks it in order; a marker list mutated by three gestures would otherwise reach the engine unsorted. */
		while (insertAt < [tabs count] && [(NSTextTab *)[tabs objectAtIndex:insertAt] location] <= location) {
			insertAt++;
		}
		[tabs insertObject:tab atIndex:insertAt];
		[tab release];
	}
	[style setTabStops:tabs];
	paragraph = [[self string] paragraphRangeForRange:_selectedRange];
	if (paragraph.length == 0) {
		paragraph = NSMakeRange(index, 0);
	}
	[_cg_textStorage addAttribute:NSParagraphStyleAttributeName value:style range:paragraph];
	[style release];
	[self setNeedsDisplay:YES];
}

- (BOOL)rulerView:(NSRulerView *)aRulerView shouldAddMarker:(NSRulerMarker *)marker
{
	(void)aRulerView;
	(void)marker;
	return YES;
}

- (CGFloat)rulerView:(NSRulerView *)aRulerView willAddMarker:(NSRulerMarker *)marker atLocation:(CGFloat)location
{
	(void)aRulerView;
	(void)marker;
	return location;
}

- (void)rulerView:(NSRulerView *)aRulerView didAddMarker:(NSRulerMarker *)marker
{
	(void)marker;
	[self cg_applyRulerMarkers:aRulerView];
}

- (BOOL)rulerView:(NSRulerView *)aRulerView shouldMoveMarker:(NSRulerMarker *)marker
{
	(void)aRulerView;
	(void)marker;
	return YES;
}

- (CGFloat)rulerView:(NSRulerView *)aRulerView willMoveMarker:(NSRulerMarker *)marker toLocation:(CGFloat)location
{
	(void)aRulerView;
	(void)marker;
	return location;
}

- (void)rulerView:(NSRulerView *)aRulerView didMoveMarker:(NSRulerMarker *)marker
{
	(void)marker;
	[self cg_applyRulerMarkers:aRulerView];
}

- (BOOL)rulerView:(NSRulerView *)aRulerView shouldRemoveMarker:(NSRulerMarker *)marker
{
	(void)aRulerView;
	(void)marker;
	return YES;
}

- (void)rulerView:(NSRulerView *)aRulerView didRemoveMarker:(NSRulerMarker *)marker
{
	(void)marker;
	[self cg_applyRulerMarkers:aRulerView];
}

/* **A CLICK ON THE RULER THAT MISSES A MARKER MOVES THE INSERTION POINT**, which is the other half of the gesture: the
 * ruler's x names a place on the caret's own line, and the manager answers which character that place is. Without this a
 * click on the strip would be swallowed, which is exactly what a marker hit test alone would do. */
- (void)rulerView:(NSRulerView *)aRulerView handleMouseDown:(NSEvent *)event
{
	NSPoint point;
	CGFloat baseline;
	NSUInteger line;
	NSUInteger glyph;
	NSUInteger character;

	(void)aRulerView;
	if ([_cg_textStorage length] == 0) {
		return;
	}
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	line = [self cg_visualLineIndexForCharacterIndex:_selectedRange.location];
	baseline = [self cg_baselineForLine:line];
	if (point.x < 0.0) {
		point.x = 0.0;
	}
	glyph = [_cg_layoutManager cg_glyphIndexForPoint:NSMakePoint(point.x, baseline)
					  inTextContainer:_cg_textContainer];
	character = [_cg_layoutManager characterIndexForGlyphAtIndex:glyph];
	[self setSelectedRange:NSMakeRange(character, 0)];
}

/* ==================================================================================================================
 * THE TWO RULER COMMANDS THE BASE CLASS REFUSES.
 *
 * **WHAT A RULER COPIES IS THE PARAGRAPH'S FORMAT PLUS THE RUN'S FONT.** Tab stops, the three indents, the paragraph and
 * line spacing and the alignment are the `NSParagraphStyle`; the font is the run's. Both travel as a property list under
 * `NSRulerPboardType`, and `-pasteRuler:` writes them onto every paragraph the selection touches — which is what "paste
 * the ruler" means: a paragraph is the unit, so a selection inside one paragraph affects that paragraph, and a selection
 * across three affects all three.
 * ================================================================================================================ */

- (void)copyRuler:(id)sender
{
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	NSDictionary *attributes;
	NSMutableDictionary *facts;
	NSParagraphStyle *style;
	NSFont *font;
	NSArray *stops;
	NSMutableArray *tabs;
	NSData *data;
	NSUInteger index;

	(void)sender;
	if ([_cg_textStorage length] == 0) {
		fn_refuse_window("NSTextView -copyRuler:", "a paragraph to take a ruler from; this view's store is empty");
		return;
	}
	index = (_selectedRange.location < [_cg_textStorage length]) ? _selectedRange.location
								    : [_cg_textStorage length] - 1;
	attributes = [_cg_textStorage attributesAtIndex:index effectiveRange:NULL];
	style = [attributes objectForKey:NSParagraphStyleAttributeName];
	font = [attributes objectForKey:NSFontAttributeName];
	if (style == nil) {
		style = [NSParagraphStyle defaultParagraphStyle];
	}
	facts = [NSMutableDictionary dictionary];
	[facts setObject:[NSNumber numberWithInteger:(NSInteger)[style alignment]] forKey:AGRulerAlignmentKey];
	[facts setObject:[NSNumber numberWithDouble:(double)[style headIndent]] forKey:AGRulerHeadIndentKey];
	[facts setObject:[NSNumber numberWithDouble:(double)[style firstLineHeadIndent]]
		  forKey:AGRulerFirstLineHeadIndentKey];
	[facts setObject:[NSNumber numberWithDouble:(double)[style tailIndent]] forKey:AGRulerTailIndentKey];
	[facts setObject:[NSNumber numberWithDouble:(double)[style lineSpacing]] forKey:AGRulerLineSpacingKey];
	[facts setObject:[NSNumber numberWithDouble:(double)[style paragraphSpacing]] forKey:AGRulerParagraphSpacingKey];
	[facts setObject:[NSNumber numberWithDouble:(double)[style paragraphSpacingBefore]]
		  forKey:AGRulerParagraphSpacingBeforeKey];
	[facts setObject:[NSNumber numberWithDouble:(double)[style lineHeightMultiple]]
		  forKey:AGRulerLineHeightMultipleKey];
	if (font != nil) {
		if ([font fontName] != nil) {
			[facts setObject:[font fontName] forKey:AGRulerFontNameKey];
		}
		[facts setObject:[NSNumber numberWithDouble:(double)[font pointSize]] forKey:AGRulerFontSizeKey];
	}
	stops = [style tabStops];
	tabs = [NSMutableArray arrayWithCapacity:[stops count]];
	for (index = 0; index < [stops count]; index++) {
		NSTextTab *tab = [stops objectAtIndex:index];

		[tabs addObject:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithDouble:(double)[tab location]], AGRulerTabLocationKey,
			[NSNumber numberWithInteger:(NSInteger)[tab tabStopType]], AGRulerTabTypeKey, nil]];
	}
	[facts setObject:tabs forKey:AGRulerTabStopsKey];
	data = [NSPropertyListSerialization dataWithPropertyList:facts format:NSPropertyListXMLFormat_v1_0
							  options:0 error:NULL];
	if (data == nil) {
		fn_refuse_window("NSTextView -copyRuler:", "a serialisable ruler; the facts did not encode");
		return;
	}
	[pasteboard declareTypes:[NSArray arrayWithObject:NSRulerPboardType] owner:nil];
	[pasteboard setData:data forType:NSRulerPboardType];
}

- (void)pasteRuler:(id)sender
{
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	NSData *data = [pasteboard dataForType:NSRulerPboardType];
	id plist;
	NSDictionary *facts;
	NSMutableParagraphStyle *style;
	NSMutableArray *tabs;
	NSArray *encodedTabs;
	NSFont *font;
	NSRange paragraph;
	NSUInteger i;

	(void)sender;
	if (data == nil) {
		fn_refuse_window("NSTextView -pasteRuler:", "a ruler on the pasteboard; there is no NSRulerPboardType data");
		return;
	}
	plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
	if (![plist isKindOfClass:[NSDictionary class]]) {
		fn_refuse_window("NSTextView -pasteRuler:", "a ruler this tier can read; the payload is not its property list");
		return;
	}
	facts = plist;
	style = [[NSMutableParagraphStyle alloc] init];
	if ([facts objectForKey:AGRulerAlignmentKey] != nil) {
		[style setAlignment:(NSTextAlignment)[[facts objectForKey:AGRulerAlignmentKey] integerValue]];
	}
	if ([facts objectForKey:AGRulerHeadIndentKey] != nil) {
		[style setHeadIndent:(CGFloat)[[facts objectForKey:AGRulerHeadIndentKey] doubleValue]];
	}
	if ([facts objectForKey:AGRulerFirstLineHeadIndentKey] != nil) {
		[style setFirstLineHeadIndent:(CGFloat)[[facts objectForKey:AGRulerFirstLineHeadIndentKey] doubleValue]];
	}
	if ([facts objectForKey:AGRulerTailIndentKey] != nil) {
		[style setTailIndent:(CGFloat)[[facts objectForKey:AGRulerTailIndentKey] doubleValue]];
	}
	if ([facts objectForKey:AGRulerLineSpacingKey] != nil) {
		[style setLineSpacing:(CGFloat)[[facts objectForKey:AGRulerLineSpacingKey] doubleValue]];
	}
	if ([facts objectForKey:AGRulerParagraphSpacingKey] != nil) {
		[style setParagraphSpacing:(CGFloat)[[facts objectForKey:AGRulerParagraphSpacingKey] doubleValue]];
	}
	if ([facts objectForKey:AGRulerParagraphSpacingBeforeKey] != nil) {
		[style setParagraphSpacingBefore:(CGFloat)[[facts objectForKey:AGRulerParagraphSpacingBeforeKey] doubleValue]];
	}
	if ([facts objectForKey:AGRulerLineHeightMultipleKey] != nil) {
		[style setLineHeightMultiple:(CGFloat)[[facts objectForKey:AGRulerLineHeightMultipleKey] doubleValue]];
	}
	encodedTabs = [facts objectForKey:AGRulerTabStopsKey];
	tabs = [NSMutableArray arrayWithCapacity:[encodedTabs count]];
	for (i = 0; i < [encodedTabs count]; i++) {
		NSDictionary *entry = [encodedTabs objectAtIndex:i];
		NSTextTab *tab = [[NSTextTab alloc] initWithType:(NSTextTabType)
					      [[entry objectForKey:AGRulerTabTypeKey] integerValue]
							location:(CGFloat)[[entry objectForKey:AGRulerTabLocationKey] doubleValue]];

		[tabs addObject:tab];
		[tab release];
	}
	[style setTabStops:tabs];
	paragraph = [[self string] paragraphRangeForRange:_selectedRange];
	if (paragraph.length == 0 && [_cg_textStorage length] > 0) {
		paragraph = NSMakeRange((_selectedRange.location < [_cg_textStorage length]) ? _selectedRange.location
											  : [_cg_textStorage length] - 1, 0);
	}
	[_cg_textStorage addAttribute:NSParagraphStyleAttributeName value:style range:paragraph];
	font = nil;
	if ([facts objectForKey:AGRulerFontNameKey] != nil) {
		font = [NSFont fontWithName:[facts objectForKey:AGRulerFontNameKey]
				       size:(CGFloat)[[facts objectForKey:AGRulerFontSizeKey] doubleValue]];
	} else if ([facts objectForKey:AGRulerFontSizeKey] != nil) {
		font = [NSFont systemFontOfSize:(CGFloat)[[facts objectForKey:AGRulerFontSizeKey] doubleValue]];
	}
	if (font != nil) {
		[_cg_textStorage addAttribute:NSFontAttributeName value:font range:paragraph];
	}
	[style release];
	[self updateRuler];
}

@end


/* ==================================================================================================================
 * SPELLING AND SUBSTITUTION.
 *
 * See the header: the flags are the view's, the checking is `NSSpellChecker`'s, and `-setSpellingState:range:` records
 * what the drawing slice will underline. The toggles are here because Apple's are: a menu item sends one, and a caller
 * that had to read the flag and set it back would be writing the same two lines in every application.
 * ================================================================================================================ */

@implementation NSTextView (AGSspelling)

- (BOOL)isContinuousSpellCheckingEnabled
{
	return _continuousSpellChecking;
}

- (void)setContinuousSpellCheckingEnabled:(BOOL)flag
{
	_continuousSpellChecking = flag ? YES : NO;
}

- (void)toggleContinuousSpellChecking:(id)sender
{
	(void)sender;
	[self setContinuousSpellCheckingEnabled:![self isContinuousSpellCheckingEnabled]];
}

- (BOOL)isGrammarCheckingEnabled
{
	return _grammarChecking;
}

- (void)setGrammarCheckingEnabled:(BOOL)flag
{
	_grammarChecking = flag ? YES : NO;
}

- (void)toggleGrammarChecking:(id)sender
{
	(void)sender;
	[self setGrammarCheckingEnabled:![self isGrammarCheckingEnabled]];
}

- (BOOL)isAutomaticSpellingCorrectionEnabled
{
	return _automaticSpellingCorrection;
}

- (void)setAutomaticSpellingCorrectionEnabled:(BOOL)flag
{
	_automaticSpellingCorrection = flag ? YES : NO;
}

- (void)toggleAutomaticSpellingCorrection:(id)sender
{
	(void)sender;
	[self setAutomaticSpellingCorrectionEnabled:![self isAutomaticSpellingCorrectionEnabled]];
}

- (BOOL)isAutomaticQuoteSubstitutionEnabled
{
	return _automaticQuoteSubstitution;
}

- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)flag
{
	_automaticQuoteSubstitution = flag ? YES : NO;
}

- (void)toggleAutomaticQuoteSubstitution:(id)sender
{
	(void)sender;
	[self setAutomaticQuoteSubstitutionEnabled:![self isAutomaticQuoteSubstitutionEnabled]];
}

- (BOOL)isAutomaticDashSubstitutionEnabled
{
	return _automaticDashSubstitution;
}

- (void)setAutomaticDashSubstitutionEnabled:(BOOL)flag
{
	_automaticDashSubstitution = flag ? YES : NO;
}

- (void)toggleAutomaticDashSubstitution:(id)sender
{
	(void)sender;
	[self setAutomaticDashSubstitutionEnabled:![self isAutomaticDashSubstitutionEnabled]];
}

/* **THE RANGE IS RECORDED UNDER ITS OWN COORDINATES**, including length, so two calls for the same start do not
 * overwrite each other; the drawing slice walks the table and paints the ranges whose state is nonzero. */
- (void)setSpellingState:(NSInteger)value range:(NSRange)charRange
{
	NSString *key = [NSString stringWithFormat:@"%lu:%lu", (unsigned long)charRange.location,
			  (unsigned long)charRange.length];

	if (_spellingState == nil) {
		_spellingState = [[NSMutableDictionary alloc] init];
	}
	if (value == 0) {
		[_spellingState removeObjectForKey:key];
	} else {
		[_spellingState setObject:[NSNumber numberWithInteger:value] forKey:key];
	}
}

/* ONE TAG FOR THE VIEW'S LIFETIME, taken from the checker so it cannot collide with another document's. */
- (NSInteger)spellCheckerDocumentTag
{
	if (_spellCheckerDocumentTag == 0) {
		_spellCheckerDocumentTag = [NSSpellChecker uniqueSpellDocumentTag];
	}
	return _spellCheckerDocumentTag;
}

- (void)orderFrontSubstitutionsPanel:(id)sender
{
	(void)sender;
	fn_refuse_window("-orderFrontSubstitutionsPanel:", "a substitutions panel (this tier has no panel with a "
			 "substitution table)");
}

@end


/* A PRIVATE CATEGORY, because this door is the view's own drawing detail and no caller outside this file should see
 * it: the interface is here so the call in `-drawRect:` is declared, and the implementation follows immediately. */
@interface NSTextView (AGSpellingDraw)
- (void)cg_drawSpellingUnderlines;
- (void)cg_drawFindIndicator;
@end


@implementation NSTextView (AGSpellingDraw)
/* **THE FIND INDICATOR IS DRAWN WHERE THE SPELLING MARKS ARE**, because both are the view's marks over the manager's
 * geometry: the rect comes from the layout manager, so a match split across a wrap is ringed on both lines. It is drawn
 * for ONE pass — Apple's flash is animated and this tier's is static — and the flag is cleared afterwards so a later
 * redraw does not leave a yellow ring behind. */
- (void)cg_drawFindIndicator
{
	NSRect rect;

	if (!_cg_findIndicatorActive || _cg_layoutManager == nil || _cg_textStorage == nil) {
		return;
	}
	_cg_findIndicatorActive = NO;
	{
		NSRange glyphs = [_cg_layoutManager glyphRangeForCharacterRange:_cg_findIndicatorRange
					     actualCharacterRange:NULL];
		NSTextContainer *container = [[_cg_layoutManager textContainers] lastObject];

		if (glyphs.length == 0 || container == nil) {
			return;
		}
		rect = [_cg_layoutManager boundingRectForGlyphRange:glyphs inTextContainer:container];
	}
	rect.origin.x += [self textContainerOrigin].x;
	rect.origin.y += [self textContainerOrigin].y;
	rect = NSInsetRect(rect, -2.0, -1.0);
	[[NSColor colorWithCalibratedRed:1.0 green:0.85 blue:0.15 alpha:0.28] setFill];
	[[NSBezierPath bezierPathWithRect:rect] fill];
	[[NSColor colorWithCalibratedRed:0.85 green:0.65 blue:0.05 alpha:1.0] setStroke];
	[[NSBezierPath bezierPathWithRect:rect] stroke];
}

/* ==================================================================================================================
 * THE SPELLING UNDERLINES.
 *
 * **THIS IS THE SLICE THAT MAKES `-setSpellingState:range:` A VISIBLE THING RATHER THAN A RECORDED ONE.** The view keeps
 * the ranges; the manager knows where the glyphs are; so each marked range is converted once — characters to glyphs,
 * glyph to line fragment — and the manager's own `-underlineGlyphRange:…` puts the red down, which also means the leading
 * and trailing spaces of a marked range are NOT underlined, because that is the door's job.
 *
 * The ink is set here because this tier's underline door reads the caller's stroke colour (see its header): Apple would
 * read it from the temporary-attribute table, which is a slice this tier has not got.
 * ================================================================================================================ */
- (void)cg_drawSpellingUnderlines
{
	NSEnumerator *keys;
	NSString *key;

	if (_spellingState == nil || [_spellingState count] == 0 || _cg_layoutManager == nil) {
		return;
	}
	[[NSColor redColor] setStroke];
	keys = [_spellingState keyEnumerator];
	while ((key = [keys nextObject]) != nil) {
		NSArray *parts = [key componentsSeparatedByString:@":"];
		NSRange range;
		NSRange glyphRange;
		NSRange lineRange = NSMakeRange(NSNotFound, 0);
		NSRect lineRect;

		if ([parts count] != 2) {
			continue;
		}
		range = NSMakeRange((NSUInteger)[[parts objectAtIndex:0] integerValue],
				    (NSUInteger)[[parts objectAtIndex:1] integerValue]);
		if (range.length == 0 || range.location + range.length > [_cg_textStorage length]) {
			continue;
		}
		glyphRange = [_cg_layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
		if (glyphRange.length == 0) {
			continue;
		}
		lineRect = [_cg_layoutManager lineFragmentRectForGlyphAtIndex:glyphRange.location
								  effectiveRange:&lineRange];
		/* **THE ORIGIN IS THE ONE THE GLYPHS WERE DRAWN AT**, or the rule lands above the words it belongs to: the
		 * text is drawn at the container origin a few hundred lines up, and the underline door is told the same origin
		 * so the two agree. Getting this wrong is invisible in isolation and obvious on screen — and it is why the
		 * origin is asked for rather than spelled, so a view with a `-textContainerInset` keeps its rules under its
		 * words. */
		[_cg_layoutManager underlineGlyphRange:glyphRange
					 underlineType:NSUnderlinePatternDot | NSUnderlineStyleSingle
				      lineFragmentRect:lineRect
			       lineFragmentGlyphRange:lineRange
				       containerOrigin:[self textContainerOrigin]];
	}
}

@end


/* ==================================================================================================================
 * FINDING.
 *
 * **THE SEARCH IS A MANUAL SCAN, NOT `-rangeOfString:options:range:`.** This Foundation's `NSString` is a
 * from-scratch reimplementation and the ranged search doors are exactly the kind of thing it may or may not carry;
 * a case-insensitive single pass over the characters is a dozen lines, has no dependency on which doors exist, and
 * makes the wrap-around behaviour explicit rather than inferred from an API's edge cases.
 *
 * **NEXT AND PREVIOUS WRAP**, which is what a Find menu does and what the era's panel did before it grew a "wrap"
 * checkbox: the search starts at the end (or the start) of the current selection and comes back round once.
 * ================================================================================================================ */
@implementation NSTextView (AGFind)

/* -1 when there is no match. `backwards` decides the direction; both directions wrap around the whole string once. */
- (NSInteger)cg_findString:(NSString *)needle from:(NSUInteger)from backwards:(BOOL)backwards
{
	NSString *haystack = [self string];
	NSUInteger n = [haystack length];
	NSUInteger m = [needle length];
	NSUInteger i;

	if (m == 0 || n < m) {
		return -1;
	}
	if (backwards) {
		i = (from > n) ? n : from;
		while (i > 0) {
			NSUInteger start = i - 1;
			NSUInteger k;

			if (start + m > n) {
				i--;
				continue;
			}
			for (k = 0; k < m; k++) {
				unichar a = [haystack characterAtIndex:start + k];
				unichar b = [needle characterAtIndex:k];

				if (a >= 'A' && a <= 'Z') {
					a = (unichar)(a - 'A' + 'a');
				}
				if (b >= 'A' && b <= 'Z') {
					b = (unichar)(b - 'A' + 'a');
				}
				if (a != b) {
					break;
				}
			}
			if (k == m) {
				return (NSInteger)start;
			}
			i--;
		}
		return -1;
	}
	for (i = from; i + m <= n; i++) {
		NSUInteger k;

		for (k = 0; k < m; k++) {
			unichar a = [haystack characterAtIndex:i + k];
			unichar b = [needle characterAtIndex:k];

			if (a >= 'A' && a <= 'Z') {
				a = (unichar)(a - 'A' + 'a');
			}
			if (b >= 'A' && b <= 'Z') {
				b = (unichar)(b - 'A' + 'a');
			}
			if (a != b) {
				break;
			}
		}
		if (k == m) {
			return (NSInteger)i;
		}
	}
	return -1;
}

- (BOOL)usesFindPanel
{
	return _usesFindPanel;
}

- (void)setUsesFindPanel:(BOOL)flag
{
	_usesFindPanel = flag ? YES : NO;
}

- (void)performFindPanelAction:(id)sender
{
	NSInteger action = 0;
	NSRange selection = [self selectedRange];
	NSString *string = [self string];

	if (sender != nil) {
		if ([sender respondsToSelector:@selector(tag)]) {
			action = (NSInteger)[sender tag];
		} else if ([sender respondsToSelector:@selector(integerValue)]) {
			action = (NSInteger)[sender integerValue];
		}
	}
	switch (action) {
	case NSFindPanelActionSetFindString:
		/* THE SELECTION BECOMES THE SEARCH STRING, which is what the menu item of that name does. */
		if (selection.length > 0) {
			NSString *found = [string substringWithRange:selection];

			[found retain];
			[_cg_findString release];
			_cg_findString = found;
		}
		break;
	case NSFindPanelActionNext:
	case NSFindPanelActionPrevious:
	{
		NSUInteger from = (action == NSFindPanelActionNext)
			? selection.location + selection.length : selection.location;
		BOOL backwards = (action == NSFindPanelActionPrevious);
		NSInteger found;

		if (_cg_findString == nil || [_cg_findString length] == 0) {
			return;		/* nothing to search for: silence is the era's answer too */
		}
		found = [self cg_findString:_cg_findString from:from backwards:backwards];
		if (found < 0) {
			/* WRAP: once round, from the other end. */
			found = [self cg_findString:_cg_findString from:(backwards ? [string length] : 0)
					  backwards:backwards];
		}
		if (found >= 0) {
			NSRange match = NSMakeRange((NSUInteger)found, [_cg_findString length]);

			[self setSelectedRange:match];
			[self showFindIndicatorForRange:match];
			[self scrollRangeToVisible:match];
		}
		break;
	}
	case NSFindPanelActionSelectAll:
		[self setSelectedRange:NSMakeRange(0, [string length])];
		break;
	case NSFindPanelActionSelectAllInSelection:
		/* The era's "select all in selection" means the selection itself, since there is no narrower scope here. */
		break;
	case NSFindPanelActionShowFindPanel:
	case NSFindPanelActionReplaceAll:
	case NSFindPanelActionReplace:
	case NSFindPanelActionReplaceAndFind:
	case NSFindPanelActionReplaceAllInSelection:
		fn_refuse_window("-performFindPanelAction:",
				 "a find panel (this tier has no find or replace user interface; the Actions that do not need "
				 "one are real)");
		break;
	default:
		break;
	}
}

- (void)showFindIndicatorForRange:(NSRange)charRange
{
	_cg_findIndicatorRange = charRange;
	_cg_findIndicatorActive = (charRange.length > 0) ? YES : NO;
}

@end
