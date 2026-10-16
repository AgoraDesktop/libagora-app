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
#include <CoreText/CTRun.h>
#include <CoreText/CTStringAttributes.h>
#include <CoreText/CTTypesetter.h>

/* **THE ONE PIECE OF STATE A FRAGMENT IS: TWO RANGES, TWO RECTS AND THE GLYPHS THEMSELVES.** Apple distinguishes
 * the FRAGMENT rect — the whole width the container gives a line — from the USED rect, which is the part the glyphs
 * actually fill; a selection and a highlight want the second and a background wants the first, which is why both are
 * kept. THE CHARACTER RANGE IS THE BREAKER'S (trailing whitespace INCLUDED) and the GLYPH range is the same span in
 * the manager's glyph space; the LINE below is the glyph STORE for this fragment — the generated glyphs, kept rather
 * than rebuilt per draw, and counting one glyph per character because that is what this tier's `CTLine` maps. A
 * tiny object rather than a struct because the fragments live in an `NSMutableArray` and an array of PODs would be a
 * second lifetime to manage by hand. */
@interface FNFragment : NSObject
{
@public
	NSRange range;		/* characters: what the breaker decided, trailing whitespace and all */
	NSRange glyphs;		/* the same span in the manager's glyph space */
	NSRect rect;
	NSRect used;
	CTLineRef line;		/* the glyph store; OWNED, and NULL for an empty fragment */
}
+ (id)fragmentWithRange:(NSRange)aRange glyphRange:(NSRange)aGlyphRange rect:(NSRect)aRect usedRect:(NSRect)aUsedRect line:(CTLineRef)aLine;
@end

@implementation FNFragment
+ (id)fragmentWithRange:(NSRange)aRange glyphRange:(NSRange)aGlyphRange rect:(NSRect)aRect usedRect:(NSRect)aUsedRect line:(CTLineRef)aLine
{
	FNFragment *fragment = [[[FNFragment alloc] init] autorelease];

	fragment->range = aRange;
	fragment->glyphs = aGlyphRange;
	fragment->rect = aRect;
	fragment->used = aUsedRect;
	fragment->line = aLine;		/* ownership transferred to the fragment */
	return fragment;
}

/* THE LINE IS THE ONLY THING HERE THAT IS NOT A SCALAR, so it is the only thing dealloc has to release. */
- (void)dealloc
{
	if (line != NULL) {
		CFRelease(line);
	}
	[super dealloc];
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

/* **BOTH DOORS WALK THE GLYPH STORE, WHICH IS WHY THEY ARE ARITHMETIC RATHER THAN A DECLARATION.** The character a
 * caller names is found in the fragment whose range holds it; the glyph index is that fragment's own glyph base plus
 * the distance into it. Because this tier's `CTLine` maps one glyph per character, the LENGTH comes back unchanged —
 * but it is counted from the store, so a shaper that made a ligature would make this wrong rather than making the
 * identity wrong. A range the store cannot honour is CLAMPED first, as Apple's contract requires. */
- (NSUInteger)numberOfGlyphs
{
	NSUInteger total = 0;
	NSUInteger i, j;

	[self cg_ensureLayout];
	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			total = ((FNFragment *)[fragments objectAtIndex:j])->glyphs.location
				+ ((FNFragment *)[fragments objectAtIndex:j])->glyphs.length;
		}
	}
	return total;
}

- (NSRange)glyphRangeForCharacterRange:(NSRange)charRange actualCharacterRange:(NSRange *)actualCharRange
{
	NSUInteger n = [_textStorage length];
	FNFragment *fragment = nil;
	NSUInteger i, j;

	if (charRange.location > n) {
		charRange.location = n;
	}
	if (charRange.location + charRange.length > n) {
		charRange.length = n - charRange.location;
	}
	if (actualCharRange != NULL) {
		*actualCharRange = charRange;
	}
	[self cg_ensureLayout];
	for (i = 0; i < [_fragments count] && fragment == nil; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *f = [fragments objectAtIndex:j];

			if (charRange.location >= f->range.location
			    && charRange.location <= f->range.location + f->range.length) {
				fragment = f;
				break;
			}
		}
	}
	if (fragment == nil) {
		return charRange;
	}
	return NSMakeRange(fragment->glyphs.location + (charRange.location - fragment->range.location),
			   charRange.length);
}

- (NSRange)characterRangeForGlyphRange:(NSRange)glyphRange actualGlyphRange:(NSRange *)actualGlyphRange
{
	FNFragment *fragment = nil;
	NSUInteger i, j;

	if (actualGlyphRange != NULL) {
		*actualGlyphRange = glyphRange;
	}
	[self cg_ensureLayout];
	for (i = 0; i < [_fragments count] && fragment == nil; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *f = [fragments objectAtIndex:j];

			if (glyphRange.location >= f->glyphs.location
			    && glyphRange.location <= f->glyphs.location + f->glyphs.length) {
				fragment = f;
				break;
			}
		}
	}
	if (fragment == nil) {
		return glyphRange;
	}
	return NSMakeRange(fragment->range.location + (glyphRange.location - fragment->glyphs.location),
			   glyphRange.length);
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
 * and the part the glyphs fill. THE GENERATED LINE IS KEPT, not released — that is the glyph store — so a draw sets
 * the glyphs the layout already made instead of remaking them. A trailing newline owes an EMPTY last fragment,
 * exactly as it owes an empty last line in the text view, because the caret sits there.
 *
 * **AND THE FLOW IS THE CONTAINERS', IN ORDER.** A line that would fall past a container's own height is carried to
 * the NEXT container on the list rather than out of the region, which is what makes two containers one document: the
 * first fills, the second takes the rest, and each container's fragments are in its own coordinates. A container with
 * a ZERO height is unbounded — the common case for a scrolling text view — so one container still takes everything. */
- (CGFloat)cg_lineHeight
{
	NSFont *font = [self cg_font];

	return [font ascender] - [font descender];
}

- (void)cg_ensureLayout
{
	NSString *string;
	NSUInteger n;
	NSFont *font;
	CGFloat lineHeight;
	CFMutableDictionaryRef attributes;
	CFAttributedStringRef s;
	CTTypesetterRef ts;
	CFIndex start;
	NSUInteger i;
	NSUInteger glyphBase = 0;
	NSUInteger lastContainer = 0;
	CGFloat lastY = 0.0;

	if (_invalidatedRange.location == NSNotFound) {
		return;
	}
	for (i = 0; i < [_fragments count]; i++) {
		[[_fragments objectAtIndex:i] removeAllObjects];
	}
	string = [_textStorage string];
	n = [string length];
	font = [self cg_font];
	lineHeight = [font ascender] - [font descender];

	if ([_textContainers count] == 0) {
		_invalidatedRange = NSMakeRange(NSNotFound, 0);
		return;
	}
	if (n == 0) {
		NSTextContainer *container = [_textContainers objectAtIndex:0];

		[[_fragments objectAtIndex:0] addObject:
			[FNFragment fragmentWithRange:NSMakeRange(0, 0) glyphRange:NSMakeRange(0, 0)
				rect:NSMakeRect(0.0, 0.0, [container containerSize].width, lineHeight)
				usedRect:NSMakeRect([container lineFragmentPadding], 0.0, 0.0, lineHeight) line:NULL]];
		_invalidatedRange = NSMakeRange(NSNotFound, 0);
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
	/* **AND A STORE THE TYPESETTER WILL NOT TAKE IS STILL LAID OUT**, as one fragment, so a glyph can be found and a
	 * line drawn even when the engine refused the string. */
	if (ts == NULL) {
		NSTextContainer *container = [_textContainers objectAtIndex:0];
		CGFloat padding = [container lineFragmentPadding];
		CGFloat containerWidth = [container containerSize].width;
		CTLineRef line = [self cg_createLineForRange:NSMakeRange(0, n) font:font];

		[[_fragments objectAtIndex:0] addObject:
			[FNFragment fragmentWithRange:NSMakeRange(0, n) glyphRange:NSMakeRange(0, n)
				rect:NSMakeRect(0.0, 0.0, containerWidth, lineHeight)
				usedRect:NSMakeRect(padding, 0.0, containerWidth - 2.0 * padding, lineHeight) line:line]];
		_invalidatedRange = NSMakeRange(NSNotFound, 0);
		return;
	}
	start = 0;
	for (i = 0; i < [_textContainers count] && start < (CFIndex)n; i++) {
		NSTextContainer *container = [_textContainers objectAtIndex:i];
		NSMutableArray *fragments = [_fragments objectAtIndex:i];
		CGFloat padding = [container lineFragmentPadding];
		CGFloat containerWidth = [container containerSize].width;
		CGFloat width = containerWidth - 2.0 * padding;
		CGFloat containerHeight = [container containerSize].height;
		CGFloat y = 0.0;

		while (start < (CFIndex)n) {
			CFIndex count;
			CTLineRef line = NULL;
			CGFloat lineWidth = 0.0;
			NSRange range;

			/* THE CONTAINER'S OWN HEIGHT IS THE OVERFLOW EDGE — but only once it has taken a line, so a container
			 * shorter than one line still gets one rather than looping forever. */
			if (containerHeight > 0.0 && y + lineHeight > containerHeight + 0.001 && [fragments count] > 0) {
				break;
			}
			count = (width > 0.0) ? CTTypesetterSuggestLineBreak(ts, start, (double)width)
					      : (CFIndex)(n - (NSUInteger)start);
			if (count <= 0) {
				count = 1;
			}
			if (start + count > (CFIndex)n) {
				count = (CFIndex)n - start;
			}
			range = NSMakeRange((NSUInteger)start, (NSUInteger)count);
			line = CTTypesetterCreateLine(ts, CFRangeMake(start, count));
			if (line == NULL) {
				line = [self cg_createLineForRange:range font:font];
			}
			if (line != NULL) {
				lineWidth = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
				if (width > 0.0 && lineWidth > width) {
					lineWidth = width;
				}
			}
			[fragments addObject:[FNFragment fragmentWithRange:range
				glyphRange:NSMakeRange(glyphBase, (NSUInteger)count)
				rect:NSMakeRect(0.0, y, containerWidth, lineHeight)
				usedRect:NSMakeRect(padding, y, lineWidth, lineHeight) line:line]];
			glyphBase += (NSUInteger)count;
			start += count;
			y += lineHeight;
			lastContainer = i;
			lastY = y;
		}
	}
	CFRelease(ts);
	/* **AND A TRAILING NEWLINE OWES AN EMPTY LAST FRAGMENT IN THE CONTAINER THE TEXT ENDED IN.** */
	if (start >= (CFIndex)n && [string characterAtIndex:n - 1] == '\n') {
		NSTextContainer *container = [_textContainers objectAtIndex:lastContainer];

		[[_fragments objectAtIndex:lastContainer] addObject:
			[FNFragment fragmentWithRange:NSMakeRange(n, 0) glyphRange:NSMakeRange(glyphBase, 0)
				rect:NSMakeRect(0.0, lastY, [container containerSize].width, lineHeight)
				usedRect:NSMakeRect([container lineFragmentPadding], lastY, 0.0, lineHeight) line:NULL]];
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

/* **AND EACH CONTAINER ANSWERS THE GLYPHS THAT LANDED IN IT**, which is the range from its first fragment's glyph base to
 * its last fragment's end — the flow having put the earlier containers' glyphs before it. A container that is not this
 * manager's, or that took no glyphs, answers the empty range at the end of the store. */
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)container
{
	NSUInteger index = [_textContainers indexOfObjectIdenticalTo:container];
	NSMutableArray *fragments;
	NSUInteger n = [_textStorage length];

	if (index == NSNotFound) {
		return NSMakeRange(n, 0);
	}
	[self cg_ensureLayout];
	fragments = [_fragments objectAtIndex:index];
	if ([fragments count] == 0) {
		return NSMakeRange(n, 0);
	}
	{
		FNFragment *first = [fragments objectAtIndex:0];
		FNFragment *last = [fragments lastObject];
		NSUInteger location = first->glyphs.location;
		NSUInteger end = last->glyphs.location + last->glyphs.length;

		return NSMakeRange(location, end - location);
	}
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
 * placing a caret asks for, and the reason the fragments are kept as ranges rather than as rects alone. ALL THE
 * CONTAINERS ARE SEARCHED, in flow order, and the LAST fragment that holds the index WINS: contiguous fragments share
 * their boundary index, and the glyph at the END of one line is the START of the next — so a caret at index 4 in
 * `one\ntwo` belongs to `two`'s fragment, and the index at the very end of the store belongs to the empty fragment a
 * trailing newline opened rather than to the line before it. */
- (FNFragment *)cg_fragmentForGlyphAtIndex:(NSUInteger)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange
{
	FNFragment *found = nil;
	NSUInteger i, j;

	[self cg_ensureLayout];
	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *fragment = [fragments objectAtIndex:j];

			if (glyphIndex >= fragment->glyphs.location
			    && glyphIndex <= fragment->glyphs.location + fragment->glyphs.length) {
				found = fragment;
			}
		}
	}
	if (found != nil && effectiveGlyphRange != NULL) {
		*effectiveGlyphRange = found->range;
	}
	return found;
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
 * THE REVERSE LOOKUPS A VIEW ASKS FOR                                                                *
 * ============================================================================================ */

/* **THE ORDINAL FRAGMENT'S RANGE, WHICH IS WHAT A VIEW'S VISUAL LINE IS.** A line index past the last answers the empty
 * range at the end of the store rather than a wrong one, and a container that is not this manager's answers nothing. */
- (NSRange)cg_lineFragmentRangeAtIndex:(NSUInteger)index inTextContainer:(NSTextContainer *)container
{
	NSUInteger containerIndex = [_textContainers indexOfObjectIdenticalTo:container];
	NSMutableArray *fragments;

	if (containerIndex == NSNotFound) {
		return NSMakeRange(NSNotFound, 0);
	}
	[self cg_ensureLayout];
	fragments = [_fragments objectAtIndex:containerIndex];
	if (index >= [fragments count]) {
		return NSMakeRange([_textStorage length], 0);
	}
	return ((FNFragment *)[fragments objectAtIndex:index])->range;
}

/* AND WHICH ORDINAL FRAGMENT A GLYPH IS IN — the same containment the fragment lookup uses, numbered, and the LAST
 * match wins for the same boundary reason. */
- (NSUInteger)cg_lineFragmentIndexForGlyphAtIndex:(NSUInteger)glyphIndex inTextContainer:(NSTextContainer *)container
{
	NSUInteger containerIndex = [_textContainers indexOfObjectIdenticalTo:container];
	NSMutableArray *fragments;
	NSUInteger i, found = NSNotFound;

	if (containerIndex == NSNotFound) {
		return NSNotFound;
	}
	[self cg_ensureLayout];
	fragments = [_fragments objectAtIndex:containerIndex];
	for (i = 0; i < [fragments count]; i++) {
		FNFragment *fragment = [fragments objectAtIndex:i];

		if (glyphIndex >= fragment->range.location
		    && glyphIndex <= fragment->range.location + fragment->range.length) {
			found = i;
		}
	}
	return found;
}

/* **AND THE X OF A GLYPH FROM THE CONTAINER'S LEFT EDGE**, which is the fragment padding plus Core Text's own offset —
 * the same sum `-drawGlyphsForGlyphRange:` writes, so a caret and the glyph it stands before cannot disagree. */
- (CGFloat)cg_offsetForGlyphAtIndex:(NSUInteger)glyphIndex
{
	FNFragment *fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:NULL];
	CFIndex relative;

	if (fragment == nil) {
		return 0.0;
	}
	if (fragment->line == NULL) {
		return fragment->used.origin.x;
	}
	relative = (CFIndex)(glyphIndex - fragment->range.location);
	if (relative < 0) {
		relative = 0;
	}
	if ((NSUInteger)relative > fragment->range.length) {
		relative = (CFIndex)fragment->range.length;
	}
	return fragment->used.origin.x + (CGFloat)CTLineGetOffsetForStringIndex(fragment->line, relative, NULL);
}

/* **AND THE INVERSE: THE GLYPH NEAREST A POINT**, which is what a click asks. The FRAGMENT is chosen by the y — the
 * line height is uniform, so the arithmetic is a division — and only the x is Core Text's. */
- (NSUInteger)cg_glyphIndexForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container
{
	NSUInteger containerIndex = [_textContainers indexOfObjectIdenticalTo:container];
	NSMutableArray *fragments;
	CGFloat lineHeight = [self cg_lineHeight];
	NSUInteger line;
	FNFragment *fragment;
	CFIndex index = 0;

	if (containerIndex == NSNotFound) {
		return NSNotFound;
	}
	[self cg_ensureLayout];
	fragments = [_fragments objectAtIndex:containerIndex];
	if ([fragments count] == 0) {
		return 0;
	}
	if (lineHeight <= 0.0 || point.y <= 0.0) {
		line = 0;
	} else {
		line = (NSUInteger)(point.y / lineHeight);
	}
	if (line >= [fragments count]) {
		line = [fragments count] - 1;
	}
	fragment = [fragments objectAtIndex:line];
	if (fragment->line != NULL) {
		index = CTLineGetStringIndexForPosition(fragment->line,
			CGPointMake(point.x - fragment->used.origin.x, 0.0));
	}
	if (index < 0) {
		index = 0;
	}
	if ((NSUInteger)index > fragment->range.length) {
		index = (CFIndex)fragment->range.length;
	}
	return fragment->range.location + (NSUInteger)index;
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

/* **THE TRAILING WHITESPACE OFF A FRAGMENT'S RANGE, WHICH IS NOT INK.** The breaker keeps a space or a newline because
 * it is part of what it MEASURED; taking it off the range a glyph is set for is what makes the boundary between two
 * lines unambiguous. The GLYPHS for it are still in the store — `-numberOfGlyphs` counts them — they are simply not
 * drawn, which is the same split the text view used to make by hand. */
- (NSRange)cg_drawnRangeForFragment:(FNFragment *)fragment
{
	NSRange range = fragment->range;
	NSString *string = [_textStorage string];
	NSUInteger n = [string length];

	if (range.location >= n) {
		return NSMakeRange(range.location, 0);
	}
	if (range.location + range.length > n) {
		range.length = n - range.location;
	}
	while (range.length > 0) {
		unichar c = [string characterAtIndex:range.location + range.length - 1];

		if (c == ' ' || c == '\t' || c == '\n') {
			range.length--;
		} else {
			break;
		}
	}
	return range;
}

/* **AND THE INK, WHICH IS NOW A RUN WALK RATHER THAN ONE COLOUR PER LINE.** The fragments the range touches are drawn,
 * each line set at the origin the caller gave PLUS the fragment's own place, and the trailing whitespace comes off the
 * drawn range as above. WITHIN a fragment the store's attribute runs are walked: each run's foreground colour is set
 * and only ITS glyphs are drawn — `CTRunDraw` over a subrange, the store being one glyph per character — so a line
 * whose text changes colour halfway comes out in both colours. THAT IS THE "INHERITS RUNS" the view could not do
 * while it drew a plain string of its own.
 *
 * **AND THE UNDERLINE IS DRAWN AFTER THE GLYPHS, IN THE CONTAINER'S OWN y-DOWN SPACE**, because a rule below a baseline
 * is a rectangle and needs no mirroring. The style is the low nibble of `NSUnderlineStyleAttributeName` and the
 * pattern its high byte; the colour is `NSUnderlineColorAttributeName` or the run's foreground. A double rule is two
 * hairlines, a dashed one is the same line stroked with a dash pattern. */
- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;
	NSFont *font;
	CGFloat ascender;
	NSUInteger i, j, rangeEnd;

	if (cg == NULL || [_textStorage length] == 0) {
		return;
	}
	[self cg_ensureLayout];
	font = [self cg_font];
	ascender = [font ascender];
	rangeEnd = glyphsToShow.location + glyphsToShow.length;
	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *fragment = [fragments objectAtIndex:j];
			NSRange drawn;
			CFArrayRef runs;
			CGFloat baselineY;
			NSUInteger pos;

			if (fragment->glyphs.location >= rangeEnd) {
				continue;
			}
			if (fragment->glyphs.location + fragment->glyphs.length <= glyphsToShow.location) {
				continue;
			}
			if (fragment->line == NULL) {
				continue;
			}
			drawn = [self cg_drawnRangeForFragment:fragment];
			if (drawn.length == 0) {
				continue;
			}
			runs = CTLineGetGlyphRuns(fragment->line);
			baselineY = origin.y + fragment->rect.origin.y + ascender;
			/* THE GLYPHS, RUN BY RUN. */
			pos = drawn.location;
			while (pos < drawn.location + drawn.length) {
				NSRange runRange;
				NSDictionary *attrs = [_textStorage attributesAtIndex:pos longestEffectiveRange:&runRange inRange:drawn];
				NSColor *colour = [attrs objectForKey:NSForegroundColorAttributeName];
				NSUInteger runEnd = runRange.location + runRange.length;
				CFIndex a, b;

				if (runEnd > drawn.location + drawn.length) {
					runEnd = drawn.location + drawn.length;
				}
				if (runEnd <= pos) {
					runEnd = pos + 1;
				}
				a = (CFIndex)(pos - fragment->range.location);
				b = (CFIndex)(runEnd - fragment->range.location);
				[(colour != nil) ? colour : [NSColor controlTextColor] setFill];
				/* **AND THE CONTEXT IS MIRRORED ABOUT THE BASELINE, WHICH IS WHAT A FLIPPED CONTAINER NEEDS.** The fragments
				 * are y-DOWN — a container's coordinates are a text view's — and Core Text's own run UP from the baseline. */
				CGContextSaveGState(cg);
				CGContextTranslateCTM(cg, origin.x + fragment->used.origin.x, baselineY);
				CGContextScaleCTM(cg, 1.0, -1.0);
				CGContextSetTextPosition(cg, 0.0, 0.0);
				if (runs != NULL && CFArrayGetCount(runs) > 0 && a < b) {
					CTRunDraw((CTRunRef)CFArrayGetValueAtIndex(runs, 0), cg, CFRangeMake(a, b - a));
				}
				CGContextRestoreGState(cg);
				pos = runEnd;
			}
			/* **AND THE TWO RULES BESIDE THE GLYPHS: THE UNDERLINE BELOW THE BASELINE AND THE STRIKETHROUGH THROUGH THE
			 * MIDDLE OF THE X-HEIGHT.** They are the same run walk and the same arithmetic at two offsets, which is why both
			 * are one helper below the loop. */
			[self cg_drawRulesForFragment:fragment drawn:drawn styleKey:NSUnderlineStyleAttributeName
				colorKey:NSUnderlineColorAttributeName defaultColour:[NSColor controlTextColor]
				y:(baselineY - [font underlinePosition]) origin:origin context:cg];
			[self cg_drawRulesForFragment:fragment drawn:drawn styleKey:NSStrikethroughStyleAttributeName
				colorKey:NSStrikethroughColorAttributeName defaultColour:[NSColor controlTextColor]
				y:(baselineY - [font xHeight] / 2.0) origin:origin context:cg];
		}
	}
}

/* **ONE RULE, DRAWN THE SAME WAY FOR AN UNDERLINE AND A STRIKETHROUGH.** The style's low nibble is the shape and its
 * high byte the pattern; the caller says WHERE the rule sits, because that is the only thing the two differ in. A
 * double rule is two hairlines, a dashed one is the same line stroked with a dash pattern, and a solid one is a fill. */
- (void)cg_drawRuleFromX:(CGFloat)x0 toX:(CGFloat)x1 y:(CGFloat)y style:(NSInteger)style
		  colour:(NSColor *)colour context:(CGContextRef)cg
{
	NSInteger shape = style & 0x0F;
	NSInteger pattern = style & 0xFF00;
	CGFloat thickness = (shape == NSUnderlineStyleThick) ? 2.0 : 1.0;

	if (shape == NSUnderlineStyleNone) {
		return;
	}
	if (pattern == NSUnderlinePatternSolid) {
		[colour setFill];
		if (shape == NSUnderlineStyleDouble) {
			CGContextFillRect(cg, CGRectMake(x0, y, x1 - x0, 1.0));
			CGContextFillRect(cg, CGRectMake(x0, y + 2.0, x1 - x0, 1.0));
		} else {
			CGContextFillRect(cg, CGRectMake(x0, y, x1 - x0, thickness));
		}
	} else {
		CGFloat dash[2];
		CGPoint points[2];

		switch (pattern) {
		case NSUnderlinePatternDot: dash[0] = 1.0; dash[1] = 1.0; break;
		case NSUnderlinePatternDash: dash[0] = 3.0; dash[1] = 2.0; break;
		case NSUnderlinePatternDashDot: dash[0] = 3.0; dash[1] = 2.0; break;
		case NSUnderlinePatternDashDotDot: dash[0] = 3.0; dash[1] = 2.0; break;
		default: dash[0] = 1.0; dash[1] = 1.0; break;
		}
		points[0] = CGPointMake(x0, y + thickness / 2.0);
		points[1] = CGPointMake(x1, y + thickness / 2.0);
		[colour setStroke];
		CGContextSetLineWidth(cg, thickness);
		CGContextSetLineDash(cg, 0.0, dash, 2);
		CGContextStrokeLineSegments(cg, points, 2);
		CGContextSetLineDash(cg, 0.0, NULL, 0);
	}
}

/* **AND THE RUN WALK EITHER RULE DOOR USES.** The style and the colour are read per run — the keys are the caller's,
 * so the same walk serves the underline pair and the strikethrough pair — and each run's rule spans the x its own
 * glyphs occupy. A run with no colour falls back to the run's foreground and then to the caller's default. */
- (void)cg_drawRulesForFragment:(FNFragment *)fragment drawn:(NSRange)drawn styleKey:(NSString *)styleKey
		       colorKey:(NSString *)colorKey defaultColour:(NSColor *)defaultColour
			    y:(CGFloat)y origin:(NSPoint)origin context:(CGContextRef)cg
{
	NSUInteger pos = drawn.location;

	while (pos < drawn.location + drawn.length) {
		NSRange runRange;
		NSDictionary *attrs = [_textStorage attributesAtIndex:pos longestEffectiveRange:&runRange inRange:drawn];
		NSNumber *styleNumber = [attrs objectForKey:styleKey];
		NSColor *colour = [attrs objectForKey:colorKey];
		NSInteger style = (styleNumber != nil) ? [styleNumber integerValue] : NSUnderlineStyleNone;
		NSUInteger runEnd = runRange.location + runRange.length;
		CFIndex a, b;
		CGFloat x0, x1;

		if (runEnd > drawn.location + drawn.length) {
			runEnd = drawn.location + drawn.length;
		}
		if (runEnd <= pos) {
			runEnd = pos + 1;
		}
		if ((style & 0x0F) == NSUnderlineStyleNone) {
			pos = runEnd;
			continue;
		}
		if (colour == nil) {
			colour = [attrs objectForKey:NSForegroundColorAttributeName];
		}
		if (colour == nil) {
			colour = defaultColour;
		}
		a = (CFIndex)(pos - fragment->range.location);
		b = (CFIndex)(runEnd - fragment->range.location);
		x0 = origin.x + fragment->used.origin.x
			+ (CGFloat)CTLineGetOffsetForStringIndex(fragment->line, a, NULL);
		x1 = origin.x + fragment->used.origin.x
			+ (CGFloat)CTLineGetOffsetForStringIndex(fragment->line, b, NULL);
		[self cg_drawRuleFromX:x0 toX:x1 y:y style:style colour:colour context:cg];
		pos = runEnd;
	}
}

/* **AND THE BACKGROUND THE GLYPHS SIT ON, WHICH IS THE OTHER HALF OF THE RUN WALK.** Each run carrying
 * `NSBackgroundColorAttributeName` fills the used rect of ITS OWN glyphs, so two backgrounds on one line are two
 * rectangles. THE SELECTION IS NOT PAINTED HERE: it belongs to the VIEW, which is the only object that knows where it
 * is, and that is the division the header states. */
- (void)drawBackgroundForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;
	NSString *string;
	CGFloat lineHeight;
	NSUInteger i, j, rangeEnd;

	if (cg == NULL || [_textStorage length] == 0) {
		return;
	}
	[self cg_ensureLayout];
	string = [_textStorage string];
	lineHeight = [self cg_lineHeight];
	rangeEnd = glyphsToShow.location + glyphsToShow.length;
	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *fragment = [fragments objectAtIndex:j];
			NSUInteger pos, end;

			if (fragment->glyphs.location >= rangeEnd) {
				continue;
			}
			if (fragment->glyphs.location + fragment->glyphs.length <= glyphsToShow.location) {
				continue;
			}
			if (fragment->line == NULL) {
				continue;
			}
			pos = fragment->range.location;
			end = fragment->range.location + fragment->range.length;
			if (end > [string length]) {
				end = [string length];
			}
			while (pos < end) {
				NSRange runRange;
				NSDictionary *attrs = [_textStorage attributesAtIndex:pos longestEffectiveRange:&runRange
									  inRange:NSMakeRange(fragment->range.location, end - fragment->range.location)];
				NSColor *background = [attrs objectForKey:NSBackgroundColorAttributeName];
				NSUInteger runEnd = runRange.location + runRange.length;

				if (runEnd > end) {
					runEnd = end;
				}
				if (runEnd <= pos) {
					runEnd = pos + 1;
				}
				if (background != nil) {
					CFIndex a = (CFIndex)(pos - fragment->range.location);
					CFIndex b = (CFIndex)(runEnd - fragment->range.location);
					CGFloat x0 = origin.x + fragment->used.origin.x
						+ (CGFloat)CTLineGetOffsetForStringIndex(fragment->line, a, NULL);
					CGFloat x1 = origin.x + fragment->used.origin.x
						+ (CGFloat)CTLineGetOffsetForStringIndex(fragment->line, b, NULL);

					[background setFill];
					CGContextFillRect(cg, CGRectMake(x0, origin.y + fragment->rect.origin.y, x1 - x0, lineHeight));
				}
				pos = runEnd;
			}
		}
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
