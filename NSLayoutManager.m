/*
 * NSLayoutManager.m — the web: a store it is told about, containers it owns, and staleness it records.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE ONE THING THIS SLICE COMPUTES IS A UNION.** Everything else is a retained pointer, a borrowed pointer and an
 * array — and the union is what "the layout is stale from here" means once there are no glyphs to be stale ABOUT: the
 * store reports an edit, the manager folds the report into one range, and the delegate is told. THAT IS THE SEAM the
 * glyph slice will hang everything on, and it is deliberately the part that does not need glyphs.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/NSArray.h>

#include <CoreGraphics/CGContext.h>
#include <CoreFoundation/CFAttributedString.h>
#include <CoreText/CTLine.h>
#include <CoreText/CTStringAttributes.h>
#include <CoreText/CTTypesetter.h>

/* **THE ONE PIECE OF STATE A FRAGMENT IS: A GLYPH RANGE AND TWO RECTS.** Apple distinguishes the FRAGMENT rect — the
 * whole width the container gives a line — from the USED rect, which is the part the glyphs actually fill; a selection
 * and a highlight want the second and a background wants the first, which is why both are kept. A tiny object rather
 * than a struct because the fragments live in an `NSMutableArray` and an array of PODs would be a second lifetime to
 * manage by hand. */
@interface FNFragment : NSObject
{
@public
	NSRange range;
	NSRect rect;
	NSRect used;
}
+ (id)fragmentWithRange:(NSRange)aRange rect:(NSRect)aRect usedRect:(NSRect)aUsedRect;
@end

@implementation FNFragment
+ (id)fragmentWithRange:(NSRange)aRange rect:(NSRect)aRect usedRect:(NSRect)aUsedRect
{
	FNFragment *fragment = [[[FNFragment alloc] init] autorelease];

	fragment->range = aRange;
	fragment->rect = aRect;
	fragment->used = aUsedRect;
	return fragment;
}
@end

@implementation NSLayoutManager

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		/* **A MANAGER STARTS WITHOUT A STORE AND WITHOUT A CONTAINER, WHICH IS APPLE'S OWN DESIGNATED-INITIALISER
		 * NOTE.** "The NSLayoutManager starts off without an NSTextStorage" — the store is added by
		 * `-addLayoutManager:` and the containers by this class's own doors. And NOTHING IS STALE, which is
		 * `NSNotFound` rather than a zero-length range at the start. */
		_textStorage = nil;
		_textContainers = [[NSMutableArray alloc] init];
		/* ONE FRAGMENT LIST PER CONTAINER, index-matched for as long as the two arrays are only ever changed together. */
		_fragments = [[NSMutableArray alloc] init];
		_invalidatedRange = NSMakeRange(NSNotFound, 0);
	}
	return self;
}

- (void)dealloc
{
	/* THE CONTAINERS' BACK-POINTERS GO FIRST, while both objects are still alive: a container that outlived this
	 * manager would otherwise hold a pointer to freed memory. */
	while ([_textContainers count] > 0) {
		NSTextContainer *container = [_textContainers lastObject];

		[container setLayoutManager:nil];
		[_textContainers removeLastObject];
	}
	[_textContainers release];
	[_fragments release];
	[_textStorage release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE STORE, WHICH THE STORAGE DRIVES                                                           *
 * ============================================================================================ */

- (NSTextStorage *)textStorage
{
	return _textStorage;
}

/* **THE PRIMITIVE STORES AND NOTHING ELSE.** It does NOT reach back into the storage's manager list, because that list
 * is what CALLS it — `-addLayoutManager:` sets this and then owns the reference — and a primitive that registered itself
 * would recurse. What a caller wants is `[store addLayoutManager:manager]` or `-replaceTextStorage:`. */
- (void)setTextStorage:(NSTextStorage *)aTextStorage
{
	if (aTextStorage != _textStorage) {
		NSTextStorage *held = [aTextStorage retain];

		[_textStorage release];
		_textStorage = held;
		[self invalidateLayoutForCharacterRange:NSMakeRange(0, [_textStorage length]) actualCharacterRange:NULL];
	}
}

/* **AND THIS IS THE DOOR A CALLER USES TO MOVE A MANAGER BETWEEN STORES.** Apple's comment says it is to be used
 * "instead of the primitive" precisely because the primitive cannot do the two halves that cross the object boundary:
 * OFF the old storage's list and ONTO the new one's. Each of those calls the primitive on this side, so the pointer is
 * never written by hand here. */
- (void)replaceTextStorage:(NSTextStorage *)newTextStorage
{
	if (_textStorage != nil) {
		[_textStorage removeLayoutManager:self];
	}
	if (newTextStorage != nil) {
		[newTextStorage addLayoutManager:self];
	}
}

- (NSAttributedString *)attributedString
{
	/* THE STORE, SEEN AS AN ATTRIBUTED STRING — which for a layout manager it IS, and Apple's own header says so. Nil
	 * when there is no store, because a glyph generator asking this before the web is built has nothing to be given. */
	return _textStorage;
}

/* ============================================================================================ *
 * THE CONTAINERS, WHICH THIS MANAGER OWNS AND THEY BORROW                                       *
 * ============================================================================================ */

- (NSArray *)textContainers
{
	return [[_textContainers copy] autorelease];
}

- (void)addTextContainer:(NSTextContainer *)container
{
	[self insertTextContainer:container atIndex:[_textContainers count]];
}

/* **THE CONTAINER IS TOLD WHO LAID IT OUT, WHICH IS THE OTHER HALF OF OWNERSHIP.** This manager RETAINS the container
 * (the array does), and the container holds a BORROWED pointer back — the same split `-superview` uses, and the reason
 * the container's `-setLayoutManager:` does not retain. Adding a container makes every character after the previous
 * last one stale, which is Apple's own note on the door and is the truth here too: the new container is room that did
 * not exist. */
- (void)insertTextContainer:(NSTextContainer *)container atIndex:(NSUInteger)index
{
	if (container == nil) {
		return;
	}
	/* **A CONTAINER IS LAID OUT IN ONE PLACE, SO IT LEAVES THE MANAGER IT WAS ON.** A container holds ONE borrowed
	 * pointer, so a manager that adopted it without releasing it from the previous one would leave the old manager
	 * LISTING a container that says it belongs to somebody else — and laying it out. MEASURED: an earlier version did
	 * exactly that, and the probe caught it from the other side (`[first textContainers]` still held it). */
	{
		NSLayoutManager *previous = [container layoutManager];

		if (previous != nil && previous != self) {
			NSArray *held = [[previous textContainers] retain];
			NSUInteger i;

			for (i = 0; i < [held count]; i++) {
				if ([held objectAtIndex:i] == container) {
					[previous removeTextContainerAtIndex:i];
					break;
				}
			}
			[held release];
		}
	}
	[_textContainers insertObject:container atIndex:index];
	[_fragments insertObject:[NSMutableArray array] atIndex:index];
	[container setLayoutManager:self];
	[self invalidateLayoutForCharacterRange:NSMakeRange(0, [_textStorage length]) actualCharacterRange:NULL];
}

- (void)removeTextContainerAtIndex:(NSUInteger)index
{
	NSTextContainer *container = [[_textContainers objectAtIndex:index] retain];

	[container setLayoutManager:nil];
	[_textContainers removeObjectAtIndex:index];
	[_fragments removeObjectAtIndex:index];
	[container release];
	[self invalidateLayoutForCharacterRange:NSMakeRange(0, [_textStorage length]) actualCharacterRange:NULL];
}

- (void)setTextContainer:(NSTextContainer *)aContainer
{
	while ([_textContainers count] > 0) {
		[self removeTextContainerAtIndex:([_textContainers count] - 1)];
	}
	if (aContainer != nil) {
		[self addTextContainer:aContainer];
	}
}

/* ============================================================================================ *
 * STALENESS                                                                                     *
 * ============================================================================================ */

/* **THE STORE'S REPORT, WHICH IS SPELLED IN THE DOOR BELOW.** The two ranges mean different things — the OLD range is
 * what the storage's record holds, the NEW one is what changed in the string it holds now, and attribute fixing is what
 * could make the second larger — and with no attribute fixing to do here they are the same span in the two strings. */
- (void)textStorage:(NSTextStorage *)aTextStorage
	     edited:(NSUInteger)editedMask
	      range:(NSRange)oldRange
   changeInLength:(NSInteger)delta
  invalidatedRange:(NSRange)newCharRange
{
	(void)aTextStorage;
	(void)editedMask;
	(void)oldRange;
	(void)delta;
	[self invalidateLayoutForCharacterRange:newCharRange actualCharacterRange:NULL];
}

/* AND THE DOOR EVERYTHING ELSE USES, which folds the range into the stale one and tells the delegate. */
- (void)invalidateLayoutForCharacterRange:(NSRange)charRange actualCharacterRange:(NSRange *)actualCharRange
{
	if (charRange.location == NSNotFound) {
		return;		/* nothing to mark: an empty record is not an edit */
	}
	if (_invalidatedRange.location == NSNotFound) {
		_invalidatedRange = charRange;
	} else {
		NSUInteger lo = (_invalidatedRange.location < charRange.location) ? _invalidatedRange.location
										 : charRange.location;
		NSUInteger a = _invalidatedRange.location + _invalidatedRange.length;
		NSUInteger b = charRange.location + charRange.length;

		_invalidatedRange = NSMakeRange(lo, ((a > b) ? a : b) - lo);
	}
	if (actualCharRange != NULL) {
		/* **THE RANGE THAT WAS ACTUALLY INVALIDATED**, which a caller uses to know how much of its request was
		 * answered. Nothing narrows the request here — there are no runs to walk — so it is the range asked for. */
		*actualCharRange = charRange;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(layoutManagerDidInvalidateLayout:)]) {
		[_delegate layoutManagerDidInvalidateLayout:self];
	}
}

- (NSRange)cg_invalidatedRange
{
	return _invalidatedRange;
}

/* ============================================================================================ *
 * THE CHARACTER-TO-GLYPH MAP, WHICH IS THE IDENTITY                                                  *
 * ============================================================================================ */

/* **BOTH DOORS ANSWER THE RANGE THEY WERE GIVEN, CLAMPED TO THE STORE.** Core Text maps characters to glyphs inside
 * `CTLine`, so there is no glyph STORE here and nothing for the two ranges to differ over; see the header for why the
 * identity is the honest answer rather than a placeholder. */
- (NSUInteger)numberOfGlyphs
{
	return [_textStorage length];
}

- (NSRange)glyphRangeForCharacterRange:(NSRange)charRange actualCharacterRange:(NSRange *)actualCharRange
{
	NSUInteger n = [_textStorage length];

	if (charRange.location > n) {
		charRange.location = n;
	}
	if (charRange.location + charRange.length > n) {
		charRange.length = n - charRange.location;
	}
	if (actualCharRange != NULL) {
		*actualCharRange = charRange;
	}
	return charRange;
}

- (NSRange)characterRangeForGlyphRange:(NSRange)glyphRange actualGlyphRange:(NSRange *)actualGlyphRange
{
	return [self glyphRangeForCharacterRange:glyphRange actualCharacterRange:actualGlyphRange];
}

/* ============================================================================================ *
 * THE LAYOUT: THE FRAGMENTS A CONTAINER IS FILLED WITH                                                  *
 * ============================================================================================ */

/* THE FONT A LINE IS MEASURED IN, taken from the store's own attributes at the first character and falling back to the
 * system font — which is the same default `NSText` and `NSTextView` use, so a store with no font attribute is not a
 * different document here than it is there. */
- (NSFont *)cg_font
{
	id font = nil;

	if ([_textStorage length] > 0) {
		font = [[_textStorage attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSFontAttributeName];
	}
	return (font != nil) ? (NSFont *)font : [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

/* **AND THIS IS THE LAYOUT: THE SAME TYPESETTER WALK THE TEXT VIEW MAKES, ASKED BY THE MANAGER INSTEAD.** The line's
 * width comes from the CONTAINER (its size less the fragment padding on both sides), the breaking is
 * `CTTypesetterSuggestLineBreak`'s, and what comes back is a fragment per line: the whole width the container gives it,
 * and the part the glyphs fill. A trailing newline owes an EMPTY last fragment, exactly as it owes an empty last line
 * in the text view, because the caret sits there.
 *
 * **ONE CONTAINER IS FILLED, WHICH IS WHAT ONE TEXT VIEW HAS.** Apple's flow moves what does not fit into the NEXT
 * container on the manager's list; this slice lays the whole store into the FIRST, and a manager with two containers
 * therefore has one full and one empty. That is NAMED rather than half-done: the overflow flow is the slice this one
 * does not carry. */
- (void)cg_layOutContainerAtIndex:(NSUInteger)index
{
	NSTextContainer *container = [_textContainers objectAtIndex:index];
	NSMutableArray *fragments = [_fragments objectAtIndex:index];
	NSString *string = [_textStorage string];
	NSUInteger n = [string length];
	CGFloat padding = [container lineFragmentPadding];
	CGFloat containerWidth = [container containerSize].width;
	CGFloat width = containerWidth - 2.0 * padding;
	NSFont *font = [self cg_font];
	CGFloat lineHeight = [font ascender] - [font descender];
	CGFloat y = 0.0;
	CFMutableDictionaryRef attributes;
	CFAttributedStringRef s;
	CTTypesetterRef ts;
	CFIndex start = 0;

	[fragments removeAllObjects];
	if (n == 0) {
		[fragments addObject:[FNFragment fragmentWithRange:NSMakeRange(0, 0)
							     rect:NSMakeRect(0.0, 0.0, containerWidth, lineHeight)
							 usedRect:NSMakeRect(padding, 0.0, 0.0, lineHeight)]];
		return;
	}
	attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
			&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionarySetValue(attributes, kCTFontAttributeName, ((NSFont *)font)->_font);
	s = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)string, attributes);
	CFRelease(attributes);
	ts = (s != NULL) ? CTTypesetterCreateWithAttributedString(s) : NULL;
	if (s != NULL) {
		CFRelease(s);
	}
	if (ts == NULL) {
		[fragments addObject:[FNFragment fragmentWithRange:NSMakeRange(0, n)
							     rect:NSMakeRect(0.0, 0.0, containerWidth, lineHeight)
							 usedRect:NSMakeRect(padding, 0.0, width, lineHeight)]];
		return;
	}
	while (start < (CFIndex)n) {
		CFIndex count = (width > 0.0) ? CTTypesetterSuggestLineBreak(ts, start, (double)width)
					      : (CFIndex)(n - (NSUInteger)start);
		CTLineRef line;
		CGFloat lineWidth = 0.0;

		if (count <= 0) {
			count = 1;
		}
		if (start + count > (CFIndex)n) {
			count = (CFIndex)n - start;
		}
		line = CTTypesetterCreateLine(ts, CFRangeMake(start, count));
		if (line != NULL) {
			lineWidth = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
			if (width > 0.0 && lineWidth > width) {
				lineWidth = width;
			}
			CFRelease(line);
		}
		[fragments addObject:[FNFragment fragmentWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)count)
							     rect:NSMakeRect(0.0, y, containerWidth, lineHeight)
							 usedRect:NSMakeRect(padding, y, lineWidth, lineHeight)]];
		start += count;
		y += lineHeight;
	}
	CFRelease(ts);
	if ([string characterAtIndex:n - 1] == '\n') {
		[fragments addObject:[FNFragment fragmentWithRange:NSMakeRange(n, 0)
							     rect:NSMakeRect(0.0, y, containerWidth, lineHeight)
							 usedRect:NSMakeRect(padding, y, 0.0, lineHeight)]];
	}
}

/* **AND EVERY LAYOUT DOOR GOES THROUGH HERE, WHICH IS ALSO WHAT CLEARS THE STALE RECORD.** A manager with nothing
 * stale has nothing to do — which is why `-usedRectForTextContainer:` costs no layout, as Apple's comment promises. */
- (void)cg_ensureLayout
{
	if (_invalidatedRange.location == NSNotFound) {
		return;
	}
	if ([_textContainers count] > 0) {
		[self cg_layOutContainerAtIndex:0];
	}
	_invalidatedRange = NSMakeRange(NSNotFound, 0);
}

- (void)ensureLayoutForTextContainer:(NSTextContainer *)container
{
	(void)container;
	[self cg_ensureLayout];
}

- (void)ensureLayoutForCharacterRange:(NSRange)charRange
{
	(void)charRange;
	[self cg_ensureLayout];
}

- (void)ensureLayoutForGlyphRange:(NSRange)glyphRange
{
	(void)glyphRange;
	[self cg_ensureLayout];
}

/* **ALL THE STORE IS IN THE FIRST CONTAINER AND NONE OF IT IS IN ANY OTHER**, which is the same single-container
 * statement the layout makes: an answer of `(0, n)` for the container that was filled and `(n, 0)` for one that was
 * not is the truth about this slice rather than a plausible-looking range. */
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)container
{
	NSUInteger n = [_textStorage length];

	if ([_textContainers count] > 0 && [_textContainers objectAtIndex:0] == container) {
		return NSMakeRange(0, n);
	}
	return NSMakeRange(n, 0);
}

/* **THE SIZE A VIEW WOULD NEED, WHICH IS THE UNION OF WHAT THE FRAGMENTS FILL.** Apple's comment says this causes
 * neither glyph generation nor layout, and that is exactly what falling through `-cg_ensureLayout` with a clean record
 * does: nothing is rebuilt, the fragments that are there are read. */
- (NSRect)usedRectForTextContainer:(NSTextContainer *)container
{
	NSUInteger index = [_textContainers indexOfObjectIdenticalTo:container];
	NSMutableArray *fragments;
	NSRect used = NSZeroRect;
	NSUInteger i;
	BOOL first = YES;

	if (index == NSNotFound) {
		return NSZeroRect;
	}
	[self cg_ensureLayout];
	fragments = [_fragments objectAtIndex:index];
	for (i = 0; i < [fragments count]; i++) {
		NSRect r = ((FNFragment *)[fragments objectAtIndex:i])->used;

		used = first ? r : NSUnionRect(used, r);
		first = NO;
	}
	return used;
}

/* THE FRAGMENT A GLYPH IS IN, with the range that shares it reported back — which is what a caller drawing a line or
 * placing a caret asks for, and the reason the fragments are kept as ranges rather than as rects alone. */
- (FNFragment *)cg_fragmentForGlyphAtIndex:(NSUInteger)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange
{
	NSMutableArray *fragments;
	NSUInteger i;

	[self cg_ensureLayout];
	if ([_fragments count] == 0) {
		return nil;
	}
	fragments = [_fragments objectAtIndex:0];
	for (i = 0; i < [fragments count]; i++) {
		FNFragment *fragment = [fragments objectAtIndex:i];

		if (glyphIndex >= fragment->range.location
		    && glyphIndex <= fragment->range.location + fragment->range.length) {
			if (effectiveGlyphRange != NULL) {
				*effectiveGlyphRange = fragment->range;
			}
			return fragment;
		}
	}
	return [fragments count] > 0 ? [fragments lastObject] : nil;
}

- (NSRect)lineFragmentRectForGlyphAtIndex:(NSUInteger)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange
{
	FNFragment *fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:effectiveGlyphRange];

	return (fragment != nil) ? fragment->rect : NSZeroRect;
}

- (NSRect)lineFragmentUsedRectForGlyphAtIndex:(NSUInteger)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange
{
	FNFragment *fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:effectiveGlyphRange];

	return (fragment != nil) ? fragment->used : NSZeroRect;
}

- (NSUInteger)cg_lineFragmentCountForTextContainer:(NSTextContainer *)container
{
	NSUInteger index = [_textContainers indexOfObjectIdenticalTo:container];

	if (index == NSNotFound) {
		return 0;
	}
	[self cg_ensureLayout];
	return [[_fragments objectAtIndex:index] count];
}

/* ============================================================================================ *
 * THE DRAWING                                                                                   *
 * ============================================================================================ */

/* THE LINE FOR A RANGE, SET IN THE STORE'S FONT — the same construction `NSTextView` makes and for the same reason: a
 * `CTLine` lays the string it is handed as ONE line, so a FRAGMENT's range is what it is given. */
- (CTLineRef)cg_createLineForRange:(NSRange)range font:(NSFont *)font
{
	NSString *sub = [[_textStorage string] substringWithRange:range];
	CFMutableDictionaryRef attributes;
	CFAttributedStringRef s;
	CTLineRef line;

	attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
			&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionarySetValue(attributes, kCTFontAttributeName, ((NSFont *)font)->_font);
	s = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)sub, attributes);
	CFRelease(attributes);
	if (s == NULL) {
		return NULL;
	}
	line = CTLineCreateWithAttributedString(s);
	CFRelease(s);
	return line;
}

/* **THE INK, AND THE DOOR `NSTextView` CALLS.** The fragments the range touches are drawn, each line set at the origin
 * the caller gave plus the fragment's own place, and the trailing whitespace is taken off the drawn range exactly as
 * the text view takes it off — the newline a breaker keeps is part of what it MEASURED and not a glyph to set.
 *
 * **AND THE COLOR IS THE STORE'S AT THE FRAGMENT'S START.** Apple draws each RUN in its own colour; reading attributes
 * run by run is the machinery a run walk needs, so this slice takes ONE colour per fragment and names the rest — which
 * is honest because a store carrying a single foreground colour (the common case) draws exactly right. */
- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;
	NSString *string;
	NSTextContainer *container;
	NSMutableArray *fragments;
	NSFont *font;
	CGFloat ascender, padding;
	NSUInteger i, rangeEnd, n;

	if (cg == NULL || [_textContainers count] == 0 || [_textStorage length] == 0) {
		return;
	}
	[self cg_ensureLayout];
	container = [_textContainers objectAtIndex:0];
	fragments = [_fragments objectAtIndex:0];
	font = [self cg_font];
	ascender = [font ascender];
	padding = [container lineFragmentPadding];
	string = [_textStorage string];
	n = [string length];
	rangeEnd = glyphsToShow.location + glyphsToShow.length;

	for (i = 0; i < [fragments count]; i++) {
		FNFragment *fragment = [fragments objectAtIndex:i];
		NSRange textRange = fragment->range;
		CTLineRef line;
		NSColor *colour;

		if (fragment->range.location >= rangeEnd) {
			break;
		}
		if (fragment->range.location + fragment->range.length <= glyphsToShow.location) {
			continue;
		}
		if (textRange.location + textRange.length > n) {
			textRange.length = n - textRange.location;
		}
		while (textRange.length > 0) {
			unichar c = [string characterAtIndex:textRange.location + textRange.length - 1];

			if (c == ' ' || c == '\t' || c == '\n') {
				textRange.length--;
			} else {
				break;
			}
		}
		if (textRange.length == 0) {
			continue;
		}
		line = [self cg_createLineForRange:textRange font:font];
		if (line == NULL) {
			continue;
		}
		colour = [[_textStorage attributesAtIndex:textRange.location effectiveRange:NULL]
					objectForKey:NSForegroundColorAttributeName];
		[(colour != nil) ? colour : [NSColor controlTextColor] setFill];
		/* **AND THE CONTEXT IS MIRRORED ABOUT THE BASELINE, WHICH IS WHAT A FLIPPED CONTAINER NEEDS.** The fragments are
		 * y-DOWN — the container's coordinates are a text view's — and Core Text's own run UP from the baseline. */
		CGContextSaveGState(cg);
		CGContextTranslateCTM(cg, origin.x + padding, origin.y + fragment->rect.origin.y + ascender);
		CGContextScaleCTM(cg, 1.0, -1.0);
		CGContextSetTextPosition(cg, 0.0, 0.0);
		CTLineDraw(line, cg);
		CGContextRestoreGState(cg);
		CFRelease(line);
	}
}

/* **AND THE RECT A RANGE OCCUPIES, WHICH IS THE UNION OF THE FRAGMENTS IT TOUCHES.** Apple: "the smallest bounding
 * rect which completely encloses the glyphs in the given glyphRange that are in the given container… always in
 * container coordinates", which is what an invalidation is spelled in. A range that touches nothing answers an empty
 * rect rather than the first fragment's. */
- (NSRect)boundingRectForGlyphRange:(NSRange)glyphRange inTextContainer:(NSTextContainer *)container
{
	NSUInteger index = [_textContainers indexOfObjectIdenticalTo:container];
	NSMutableArray *fragments;
	NSRect bounds = NSZeroRect;
	NSUInteger i, rangeEnd = glyphRange.location + glyphRange.length;
	BOOL first = YES;

	if (index == NSNotFound) {
		return NSZeroRect;
	}
	[self cg_ensureLayout];
	fragments = [_fragments objectAtIndex:index];
	for (i = 0; i < [fragments count]; i++) {
		FNFragment *fragment = [fragments objectAtIndex:i];
		NSUInteger lo = fragment->range.location;
		NSUInteger hi = lo + fragment->range.length;

		if (hi <= glyphRange.location || lo >= rangeEnd) {
			continue;
		}
		bounds = first ? fragment->rect : NSUnionRect(bounds, fragment->rect);
		first = NO;
	}
	return bounds;
}

- (id <NSLayoutManagerDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(id <NSLayoutManagerDelegate>)anObject
{
	/* NOT RETAINED, and not released on the way out: this tree's rule for every delegate. */
	_delegate = anObject;
}

@end
