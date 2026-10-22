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
#import <AppKit/AppKitRefusal.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSTextTab.h>
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSTextTable.h>
#import "NSTextTable_internal.h"
#import <AppKit/NSTextView.h>
#import <AppKit/NSRulerView.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSLocale.h>

#include <CoreGraphics/CGContext.h>
#include <CoreFoundation/CFAttributedString.h>
#include <CoreText/CTLine.h>
#include <CoreText/CTParagraphStyle.h>
#include <CoreText/CTRun.h>
#include <CoreText/CTRunDelegate.h>
#include <CoreText/CTStringAttributes.h>
#include <CoreText/CTTextTab.h>
#include <CoreText/CTTypesetter.h>
#include <math.h>
#include <stdlib.h>

/* **THE ONE PIECE OF STATE A FRAGMENT IS: TWO RANGES, TWO RECTS AND THE GLYPHS THEMSELVES.** Apple distinguishes
 * the FRAGMENT rect — the whole width the container gives a line — from the USED rect, which is the part the glyphs
 * actually fill; a selection and a highlight want the second and a background wants the first, which is why both are
 * kept. THE CHARACTER RANGE IS THE BREAKER'S (trailing whitespace INCLUDED) and the GLYPH range is the same span in
 * the manager's glyph space; the LINE below is the glyph STORE for this fragment — the generated glyphs, kept rather
 * than rebuilt per draw, and counting one glyph per character because that is what this tier's `CTLine` maps. A
 * tiny object rather than a struct because the fragments live in an `NSMutableArray` and an array of PODs would be a
 * second lifetime to manage by hand. */
/* **AND THE ONE THING A FRAGMENT CAN CARRY THAT IS NOT A GLYPH: A BOX.** An attachment is a character that stands for
 * something of a FIXED SIZE, and THE ENGINE RESERVES ITS WIDTH NOW — a `CTRunDelegate` set on the character (see
 * `-cg_attributedStringByAddingRunDelegates:`) makes `CTLine` and `CTTypesetter` measure the box, so the offsets the
 * line answers already include it and `engineAdvance` here IS the width. This object is what the MANAGER still keeps:
 * which character the box belongs to, what to draw at it (the attachment), and the numbers the hit test and the draw
 * need. THE EXTRA (`width - engineAdvance`) is therefore zero when the engine did the reservation, and the arithmetic
 * that adds it is kept because it is what makes the manager correct if ever it must place a box the engine did not. */
@interface FNBox : NSObject
{
@public
	NSUInteger index;	/* the character index in the STORE */
	CGFloat width;		/* what the box occupies */
	CGFloat engineAdvance;	/* what the glyph it replaces advanced */
	CGFloat ascent;
	CGFloat descent;
	id content;		/* the attachment, BORROWED */
}
+ (id)boxWithIndex:(NSUInteger)anIndex width:(CGFloat)aWidth engineAdvance:(CGFloat)anAdvance
	    ascent:(CGFloat)anAscent descent:(CGFloat)aDescent content:(id)someContent;
@end

@implementation FNBox
+ (id)boxWithIndex:(NSUInteger)anIndex width:(CGFloat)aWidth engineAdvance:(CGFloat)anAdvance
	    ascent:(CGFloat)anAscent descent:(CGFloat)aDescent content:(id)someContent
{
	FNBox *box = [[[FNBox alloc] init] autorelease];

	box->index = anIndex;
	box->width = aWidth;
	box->engineAdvance = anAdvance;
	box->ascent = anAscent;
	box->descent = aDescent;
	box->content = someContent;
	return box;
}
@end

@interface FNFragment : NSObject
{
@public
	NSRange range;		/* characters: what the breaker decided, trailing whitespace and all */
	NSRange glyphs;		/* the same span in the LINE's glyph space, which is the SHAPER's count and not the text's */
	NSRect rect;		/* the whole flow band: any LEADING space (line or paragraph) plus the line */
	NSRect used;		/* the text band: where the glyphs sit, after the indents and the alignment */
	CGFloat baseline;	/* the baseline's y in the CONTAINER's coordinates */
	CTLineRef line;		/* the glyph store; OWNED, and NULL for an empty fragment */
	BOOL hyphenated;	/* the line ends in a DRAWN HYPHEN that is not a character of the store */
	NSArray *boxes;		/* RETAINED; FNBox objects sorted by character index, or nil */
}
+ (id)fragmentWithRange:(NSRange)aRange glyphRange:(NSRange)aGlyphRange rect:(NSRect)aRect usedRect:(NSRect)aUsedRect baseline:(CGFloat)aBaseline line:(CTLineRef)aLine boxes:(NSArray *)someBoxes;
@end

@implementation FNFragment
+ (id)fragmentWithRange:(NSRange)aRange glyphRange:(NSRange)aGlyphRange rect:(NSRect)aRect usedRect:(NSRect)aUsedRect baseline:(CGFloat)aBaseline line:(CTLineRef)aLine boxes:(NSArray *)someBoxes
{
	FNFragment *fragment = [[[FNFragment alloc] init] autorelease];

	fragment->range = aRange;
	fragment->glyphs = aGlyphRange;
	fragment->rect = aRect;
	fragment->used = aUsedRect;
	fragment->baseline = aBaseline;
	fragment->line = aLine;		/* ownership transferred to the fragment */
	fragment->boxes = [someBoxes retain];
	return fragment;
}

/* THE LINE AND THE BOXES ARE THE ONLY THINGS HERE THAT ARE NOT SCALARS, so they are what dealloc releases. */
- (void)dealloc
{
	if (line != NULL) {
		CFRelease(line);
	}
	[boxes release];
	[super dealloc];
}
@end

/* **AND THE ONE PIECE OF STATE A COLLAPSING TABLE NEEDS THAT IS NOT A LINE: A CELL'S BOX.** A cell is the run of
 * fragments sharing one `NSTextTableBlock`; its CONTENT is their union, its FRAME is that content grown by the block's
 * own layers, and the EDGES it draws are all four unless a neighbour's box shares one — in which case ONE of the two
 * draws it, and this is where that decision is recorded before either is drawn. The frame and the mask are computed
 * in one pass over the whole grid, which is why they live here rather than being computed at the draw. */
@interface FNCellBox : NSObject
{
@public
	NSTextBlock *block;	/* BORROWED; the cell's own block */
	NSRect content;		/* the union of the cell's fragments' FLOW bands (its cell, not its text) */
	NSUInteger containerIndex;
	NSRange range;
	NSRect frame;		/* content grown by the block's layers */
	NSTextBlockEdge edges;	/* which of the four edges THIS cell draws */
	NSTextBlockEdge outer;	/* which of its edges meet ANOTHER CELL (the rest are the table's own edge) */
}
@end

@implementation FNCellBox
@end

/* **AND ONE BLOCK'S TWO RECTANGLES, WHEN A CALLER DICTATED THEM.** The setters store one of these; the getters search the
 * list before they compute. The block pointer is BORROWED for the same reason `FNCellBox`'s is: the paragraph style in
 * the store is what owns the block, and a manager that retained it would outlive the document that named it. */
@interface FNBlockRect : NSObject
{
@public
	NSTextBlock *block;	/* BORROWED; the block this rect was set for */
	NSRect bounds;		/* the value the caller gave */
	NSRect layout;
	BOOL hasBounds;
	BOOL hasLayout;
}
@end

@implementation FNBlockRect
@end

/* **AND A TEMPORARY ATTRIBUTE IS A RUN: A RANGE AND THE DICTIONARY THE DRAWING PASS SEES INSTEAD OF THE STORE'S.** The
 * list of them is kept sorted and non-overlapping, and adjacent runs that carry the SAME dictionary are merged, which is
 * what makes `longestEffectiveRange:` tell the truth: an attribute set over {2,4} and then over {4,6} with the same value
 * is one run {2,8}, because that is the range over which the value does not change. */
@interface FNTextMark : NSObject
{
@public
	NSRange range;
	NSMutableDictionary *attributes;	/* RETAINED */
}
+ (id)markWithRange:(NSRange)aRange attributes:(NSDictionary *)someAttributes;
@end

@implementation FNTextMark
+ (id)markWithRange:(NSRange)aRange attributes:(NSDictionary *)someAttributes
{
	FNTextMark *mark = [[[FNTextMark alloc] init] autorelease];

	mark->range = aRange;
	mark->attributes = [someAttributes mutableCopy];
	return mark;
}
- (void)dealloc
{
	[attributes release];
	[super dealloc];
}
@end

/* THE TEMPORARY-ATTRIBUTE TABLE AND THE MERGE THE DRAWING PASS READS. Declared before the implementation because the ink
 * and background passes call the merge helper and are defined in the main body; implemented in a category at the foot of
 * the file, where the run table lives beside its own prose. */
@interface NSLayoutManager (AGTemporaryAttributes)
- (NSDictionary *)cg_drawingAttributesAtIndex:(NSUInteger)index longestEffectiveRange:(NSRange *)range
				      inRange:(NSRange)rangeLimit;
@end

@implementation NSLayoutManager

/* ============================================================================================ *
 * THE BOXES, AS RUN DELEGATES: THE ENGINE RESERVES THE WIDTH NOW                                      *
 * ============================================================================================ */

/* **THE THREE ANSWERS A DELEGATE GIVES, TAKEN FROM THE ATTACHMENT'S OWN CELL.** The `refCon` IS the attachment, which
 * the store's attribute retains, so the delegate outlives the line that reads it. A cell that has gone away answers a
 * box of no width rather than a crash. */
static NSSize fn_attachment_size(void *refCon)
{
	NSTextAttachment *attachment = (NSTextAttachment *)refCon;
	NSCell<NSTextAttachmentCell> *cell = [attachment attachmentCell];

	return (cell != nil) ? [cell cellSize] : NSZeroSize;
}

static CGFloat fn_attachment_ascent(void *refCon)
{
	return fn_attachment_size(refCon).height;
}

static CGFloat fn_attachment_descent(void *refCon)
{
	return 0.0;
}

static CGFloat fn_attachment_width(void *refCon)
{
	return fn_attachment_size(refCon).width;
}

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
		/* AND THE THREE OVERRIDE TABLES, EMPTY: a manager that computes its own layout has nothing to consult them for. */
		_blockRectOverrides = [[NSMutableArray alloc] init];
		_attachmentSizes = [[NSMutableDictionary alloc] init];
		/* **PROPORTIONALLY DOWN IS APPLE'S DEFAULT AND THE ONE A LINE OF TEXT NEEDS.** An attachment taller than its
		 * line, drawn at its own size, would overlap the lines above and below it; shrinking it to fit is what keeps a
		 * picture inside the text that asked for it. */
		_defaultAttachmentScaling = NSImageScaleProportionallyDown;
		/* AND THE TEMPORARY RUNS, EMPTY; the rect buffer starts NULL and is grown by the first rectArray call. */
		_temporaryMarks = [[NSMutableArray alloc] init];
		_rectArray = NULL;
		_rectArrayCount = 0;
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
	[_blockRectOverrides release];
	[_attachmentSizes release];
	[_temporaryMarks release];
	if (_rectArray != NULL) {
		free(_rectArray);
	}
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

/* **AND THE MANAGER'S GLYPH SPACE IS THE LINE'S, WHICH IS THE SHAPER'S AND NOT THE TEXT'S.** `cg_layOut` advances its
 * glyph base by the GLYPH COUNT of the line it just made, and every fragment records that span — so the space is the
 * one `CTLine` defines, where a ligature is three characters and one glyph and a composed mark is one character and
 * one. The two doors below therefore cannot translate by arithmetic: `location` minus the fragment's start is the
 * IDENTITY map's answer, and it is out by one for every ligature before the point.
 *
 * **THE MAP IS THE RUN'S OWN STRING INDICES.** `CTRunGetStringIndices` is the cluster the shaper answered with,
 * counted from the line's own range, so walking a fragment's runs gives both directions: the glyph before a character
 * is a count of glyphs walked, and the character a glyph belongs to is that index. **THE WALK IS OVER EVERY RUN IN
 * ORDER**, because a fragment can hold several faces and a glyph offset is only meaningful across all of them. */
static NSUInteger fn_glyphOffsetForCharacterInLine(CTLineRef line, NSUInteger charOffset)
{
	CFArrayRef runs = (line != NULL) ? CTLineGetGlyphRuns(line) : NULL;
	CFIndex r, runCount = (runs != NULL) ? CFArrayGetCount(runs) : 0;
	NSUInteger walked = 0;

	for (r = 0; r < runCount; r++) {
		CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
		CFIndex glyphs = CTRunGetGlyphCount(run);
		const CFIndex *indices = CTRunGetStringIndicesPtr(run);
		CFIndex k;

		for (k = 0; k < glyphs; k++) {
			if (indices != NULL && indices[k] >= (CFIndex)charOffset) {
				return walked;
			}
			walked++;
		}
	}
	return walked;
}

/* THE OTHER DIRECTION, CLAMPED TO THE CHARACTERS THE LINE HAS: a glyph with no character of its own — the hyphen a
 * hyphenated line draws, which IS one of the line's glyphs — answers with the index one past the last character
 * rather than inventing one. That is what keeps `-characterRangeForGlyphRange:` from ever reporting more characters
 * than the text has. */
static NSUInteger fn_characterForGlyphOffsetInLine(CTLineRef line, NSUInteger glyphOffset)
{
	CFArrayRef runs = (line != NULL) ? CTLineGetGlyphRuns(line) : NULL;
	CFIndex r, runCount = (runs != NULL) ? CFArrayGetCount(runs) : 0;
	NSUInteger walked = 0;
	NSUInteger last = 0;

	for (r = 0; r < runCount; r++) {
		CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
		CFIndex glyphs = CTRunGetGlyphCount(run);
		const CFIndex *indices = CTRunGetStringIndicesPtr(run);
		CFIndex k;

		for (k = 0; k < glyphs; k++) {
			if (indices != NULL) {
				last = (NSUInteger)indices[k];
			}
			if (walked == glyphOffset) {
				return last;
			}
			walked++;
		}
	}
	/* **PAST THE LAST GLYPH THE LINE HAD, AND IN THE SAME COORDINATES AS EVERY OTHER ANSWER HERE.** The clusters this
	 * walk reads are LINE-RELATIVE — the shaper's indices into the characters it was given — so the answer for an
	 * offset past the end must be the line's CHARACTER COUNT and not the index the line's range ends at in the string.
	 * MEASURED, and it is the bug this comment replaces: returning `stringRange.location + length` made a range reach
	 * one line past the fragment answer with the NEXT line's characters, so a range of three characters came back as
	 * five. */
	if (line == NULL) {
		return 0;
	}
	return (NSUInteger)CTLineGetStringRange(line).length;
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
	/* **AND THE END IS MAPPED IN ITS OWN FRAGMENT, BECAUSE A RANGE CAN SPAN THE BREAK.** Mapping only the start and
	 * reporting the character length was right while a glyph was a character and the space was contiguous; now a
	 * range that runs into the next line has to find that line's base for its end, or the length comes back short by
	 * whatever the two fragments' glyph counts differ by. */
	{
		FNFragment *endFragment = nil;
		NSUInteger endChar = charRange.location + charRange.length;
		NSUInteger glyphStart, glyphEnd;

		for (i = 0; i < [_fragments count] && endFragment == nil; i++) {
			NSMutableArray *fragments = [_fragments objectAtIndex:i];

			for (j = 0; j < [fragments count]; j++) {
				FNFragment *f = [fragments objectAtIndex:j];

				if (endChar >= f->range.location && endChar <= f->range.location + f->range.length) {
					endFragment = f;
					break;
				}
			}
		}
		if (endFragment == nil) {
			endFragment = fragment;
		}
		glyphStart = fragment->glyphs.location
			+ ((fragment->line != NULL)
			   ? fn_glyphOffsetForCharacterInLine(fragment->line,
							      charRange.location - fragment->range.location)
			   : (charRange.location - fragment->range.location));
		glyphEnd = endFragment->glyphs.location
			+ ((endFragment->line != NULL)
			   ? fn_glyphOffsetForCharacterInLine(endFragment->line, endChar - endFragment->range.location)
			   : (endChar - endFragment->range.location));
		return NSMakeRange(glyphStart, (glyphEnd > glyphStart) ? (glyphEnd - glyphStart) : 0);
	}
}

- (NSRange)characterRangeForGlyphRange:(NSRange)glyphRange actualGlyphRange:(NSRange *)actualGlyphRange
{
	FNFragment *fragment = nil;
	NSUInteger i, j;

	if (actualGlyphRange != NULL) {
		*actualGlyphRange = glyphRange;
	}
	[self cg_ensureLayout];
	/* **THE LAST FRAGMENT HOLDING THE INDEX WINS, WHICH IS THIS CLASS'S OWN RULE EVERYWHERE ELSE** — contiguous
	 * fragments share their boundary glyph, and a glyph at the end of one line is the start of the next. Breaking at
	 * the FIRST match was survivable while the mapping was arithmetic, because the offset came out the same either
	 * way; with the LINE's map it is not, and the walk has to agree with `cg_fragmentForGlyphAtIndex:`. */
	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *f = [fragments objectAtIndex:j];

			if (glyphRange.location >= f->glyphs.location
			    && glyphRange.location <= f->glyphs.location + f->glyphs.length) {
				fragment = f;
			}
		}
	}
	if (fragment == nil) {
		return glyphRange;
	}
	/* AND THE SAME WALK BACKWARDS, with both ends clamped to the characters the line has. */
	{
		NSUInteger at = glyphRange.location - fragment->glyphs.location;
		NSUInteger start, end;

		if (fragment->line != NULL) {
			start = fn_characterForGlyphOffsetInLine(fragment->line, at);
			end = fn_characterForGlyphOffsetInLine(fragment->line, at + glyphRange.length);
			return NSMakeRange(fragment->range.location + start, (end > start) ? (end - start) : 0);
		}
		return NSMakeRange(fragment->range.location + at, glyphRange.length);
	}
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

/* **THE PARAGRAPH STYLE THE TYPESETTER BREAKS BY, TAKEN FROM THE STORE'S FIRST RUN.** The typesetter obeys one thing
 * here — the LINE-BREAK MODE — and it reads it from the attributed string's `kCTParagraphStyleAttributeName`, so the
 * manager builds the Core Text style from the `NSParagraphStyle` the store carries at index 0. A store with no style
 * (the common case) gets word wrapping, which is the mode the typesetter already defaulted to; a store with one gets
 * the mode it named. PER-PARAGRAPH STYLES are named rather than half-done: this reads the style at the START of the
 * store and applies it to every line, which is right for a document set in one paragraph style and is where the
 * run-by-run slice will start. */
/* **AND THE STYLE CORE TEXT IS GIVEN, WITH THE STOPS THE CALLER NAMES.** The global build passes the style's own
 * `-tabStops`; the per-line decimal rebuild passes an array whose decimal stops have been moved. */
- (CTParagraphStyleRef)cg_createParagraphStyleForStyle:(NSParagraphStyle *)style stops:(NSArray *)stopsOverride
{
	CTLineBreakMode mode = kCTLineBreakByWordWrapping;
	CFMutableArrayRef tabs = NULL;
	CGFloat interval = 0.0;
	CTParagraphStyleSetting settings[3];
	CFIndex count = 0;

	if (style != nil) {
		NSArray *stops = (stopsOverride != nil) ? stopsOverride : [style tabStops];
		NSUInteger i;

		mode = (CTLineBreakMode)[style lineBreakMode];
		interval = [style defaultTabInterval];
		/* **AND THE TAB STOPS TRAVEL INTO CORE TEXT, WHICH IS WHAT WALKS THEM.** Each `NSTextTab`'s type is an alignment
		 * here — the two vocabularies are the same three edges — and A DECIMAL TAB HAS NO CORE TEXT COUNTERPART, so it is
		 * carried as a LEFT stop and that divergence is named here rather than silently drawn as something else. */
		/* **AND AN EMPTY ARRAY IS SET WHEN THERE ARE NO STOPS BUT THERE IS AN INTERVAL**, because Core Text's OWN default
		 * is twelve stops at 28-point multiples — so leaving TabStops unset would let that default win over the
		 * `-defaultTabInterval` the caller asked for. Setting an EMPTY array suppresses it and the interval applies. */
		if ([stops count] > 0 || interval > 0.0) {
			tabs = CFArrayCreateMutable(kCFAllocatorDefault, (CFIndex)[stops count], &kCFTypeArrayCallBacks);
			for (i = 0; i < [stops count] && tabs != NULL; i++) {
				NSTextTab *stop = [stops objectAtIndex:i];
				CTTextAlignment alignment = kCTLeftTextAlignment;
				CTTextTabRef tab;

				switch ([stop tabStopType]) {
				case NSRightTabStopType:
					alignment = kCTRightTextAlignment;
					break;
				case NSCenterTabStopType:
					alignment = kCTCenterTextAlignment;
					break;
				default:
					alignment = kCTLeftTextAlignment;
					break;
				}
				tab = CTTextTabCreate(alignment, (double)[stop location], NULL);
				if (tab != NULL) {
					CFArrayAppendValue(tabs, tab);
					CFRelease(tab);
				}
			}
		}
	}
	settings[count].spec = kCTParagraphStyleSpecifierLineBreakMode;
	settings[count].valueSize = sizeof(mode);
	settings[count].value = &mode;
	count++;
	if (tabs != NULL) {
		settings[count].spec = kCTParagraphStyleSpecifierTabStops;
		settings[count].valueSize = sizeof(CFArrayRef);
		settings[count].value = &tabs;
		count++;
	}
	settings[count].spec = kCTParagraphStyleSpecifierDefaultTabInterval;
	settings[count].valueSize = sizeof(interval);
	settings[count].value = &interval;
	count++;
	{
		CTParagraphStyleRef created = CTParagraphStyleCreate(settings, count);

		if (tabs != NULL) {
			CFRelease(tabs);
		}
		return created;
	}
}

/* **AND THE GLOBAL STYLE, WHICH IS THE ONE AT THE START OF THE STORE** — this tier applies one paragraph style to every
 * line, so this is what the whole store is set in; the per-line decimal rebuild asks for the variant above instead. */
- (CTParagraphStyleRef)cg_createParagraphStyle
{
	NSParagraphStyle *style = nil;

	if ([_textStorage length] > 0) {
		style = [[_textStorage attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSParagraphStyleAttributeName];
	}
	return [self cg_createParagraphStyleForStyle:style stops:nil];
}

/* **AND THE STOPS A LINE WITH A DECIMAL TAB ACTUALLY NEEDS.** Core Text has no decimal alignment, so the provisional
 * line lays a decimal tab out as a LEFT one and the number after it starts AT the stop. To put the number's POINT at
 * the stop instead, that stop is moved LEFT by the width of what goes before the point — the integer part, or the
 * whole number when it has no point — and the line is rebuilt with the moved stop, which is a LEFT one again. Each
 * decimal tab is read from the PROVISIONAL line's own offsets, so this does not have to re-derive which stop a tab
 * reached. A line with no decimal tab (or no tab at all) answers nil and is left exactly as the engine made it. */
- (NSArray *)cg_adjustedStopsForStyle:(NSParagraphStyle *)style line:(CTLineRef)line range:(NSRange)range
{
	NSArray *stops = [style tabStops];
	NSString *string = [_textStorage string];
	NSMutableArray *adjusted = nil;
	NSUInteger k;

	if ([stops count] == 0 || line == NULL) {
		return nil;
	}
	for (k = range.location; k < range.location + range.length; k++) {
		CFIndex rel;
		CGFloat landing;
		NSUInteger si, usedIndex = NSNotFound;
		NSTextTab *used = nil;
		NSUInteger numStart, numEnd, termIndex = NSNotFound, q;
		NSArray *terms;
		CGFloat leftWidth, adjustedLocation;
		NSTextTab *moved;

		if ([string characterAtIndex:k] != '\t') {
			continue;
		}
		rel = (CFIndex)(k - range.location);
		/* THE CHARACTER AFTER THE TAB BEGINS AT THE STOP THE TAB REACHED. */
		landing = (CGFloat)CTLineGetOffsetForStringIndex(line, rel + 1, NULL);
		for (si = 0; si < [stops count]; si++) {
			NSTextTab *stop = [stops objectAtIndex:si];

			if (fabs([stop location] - landing) < 0.5) {
				used = stop;
				usedIndex = si;
				break;
			}
		}
		if (used == nil || [used tabStopType] != NSDecimalTabStopType) {
			continue;
		}
		/* THE NUMBER: from the tab to the next tab or the end of the line. */
		numStart = k + 1;
		numEnd = numStart;
		while (numEnd < range.location + range.length && [string characterAtIndex:numEnd] != '\t') {
			numEnd++;
		}
		if (numEnd <= numStart) {
			continue;
		}
		/* THE TERMINATOR: the stop's own options when it has them, the locale's otherwise. */
		terms = [[used options] objectForKey:NSTabColumnTerminatorsAttributeName];
		if (terms == nil) {
			terms = [NSTextTab columnTerminatorsForLocale:[NSLocale currentLocale]];
		}
		for (q = numStart; q < numEnd; q++) {
			NSString *ch = [string substringWithRange:NSMakeRange(q, 1)];

			if ([terms containsObject:ch]) {
				termIndex = q;
				break;
			}
		}
		{
			CFIndex from = (CFIndex)(numStart - range.location);
			CFIndex to = (CFIndex)(((termIndex != NSNotFound) ? termIndex : numEnd) - range.location);

			leftWidth = (CGFloat)(CTLineGetOffsetForStringIndex(line, to, NULL)
					      - CTLineGetOffsetForStringIndex(line, from, NULL));
		}
		adjustedLocation = [used location] - leftWidth;
		if (adjustedLocation < 0.0) {
			adjustedLocation = 0.0;
		}
		if (adjusted == nil) {
			adjusted = [NSMutableArray arrayWithArray:stops];
		}
		moved = [[NSTextTab alloc] initWithType:NSLeftTabStopType location:adjustedLocation];
		[adjusted replaceObjectAtIndex:usedIndex withObject:moved];
		[moved release];
	}
	return adjusted;
}

/* **AND THE LINE A RANGE GETS, WITH A DECIMAL TAB ALIGNED ON ITS POINT WHEN ONE LANDS HERE.** The provisional line is
 * the engine's own; if it has no decimal tab the provisional line IS the answer. Otherwise the adjusted stops are
 * computed from it and the line is REBUILT from a SUBSTRING of the same attributed string — so the character
 * attributes and the attachment run delegates travel with it — carrying a paragraph style with the moved stops. */
- (CTLineRef)cg_createLineForRange:(NSRange)range style:(NSParagraphStyle *)style
		attributedString:(CFAttributedStringRef)rich typesetter:(CTTypesetterRef)ts font:(NSFont *)font
{
	CTLineRef line = CTTypesetterCreateLine(ts, CFRangeMake(range.location, range.length));
	NSArray *adjusted;

	if (line == NULL) {
		return [self cg_createLineForRange:range font:font];
	}
	if (rich == NULL) {
		return line;
	}
	adjusted = [self cg_adjustedStopsForStyle:style line:line range:range];
	if (adjusted != nil) {
		CTParagraphStyleRef paragraphStyle = [self cg_createParagraphStyleForStyle:style stops:adjusted];
		CFAttributedStringRef sub = CFAttributedStringCreateWithSubstring(kCFAllocatorDefault, rich,
			CFRangeMake(range.location, range.length));
		CFMutableAttributedStringRef mutable = (sub != NULL)
			? CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 0, sub) : NULL;
		CTLineRef rebuilt = NULL;

		if (sub != NULL) {
			CFRelease(sub);
		}
		if (mutable != NULL) {
			if (paragraphStyle != NULL) {
				CFAttributedStringSetAttribute(mutable, CFRangeMake(0, range.length),
					kCTParagraphStyleAttributeName, paragraphStyle);
			}
			rebuilt = CTLineCreateWithAttributedString(mutable);
			CFRelease(mutable);
		}
		if (paragraphStyle != NULL) {
			CFRelease(paragraphStyle);
		}
		if (rebuilt != NULL) {
			CFRelease(line);
			line = rebuilt;
		}
	}
	return line;
}

/* **WHETHER A CHARACTER IS ONE A HYPHENATION POINT CAN SIT INSIDE, AND IT IS THE DOOR'S OWN RULE.** The word to
 * hyphenate is the run of LETTERS the break left behind, because `-lineBreakByHyphenatingBeforeIndex:` itself
 * refuses a location whose predecessor is not a letter — so asking it about a run that is not all letters would be
 * asking a question it has already answered "no" to, and a break taken there would be a break with no hyphen. */
static BOOL fn_letter_char(unichar c)
{
	return [[NSCharacterSet letterCharacterSet] characterIsMember:c];
}

/* **THE LINE FOR A PIECE THAT ENDS IN A HYPHEN, WHICH IS ONE GLYPH LONGER THAN ITS RANGE HAS CHARACTERS.**
 * AppKit never writes a hyphen into the text, so the hyphen is appended to a COPY of the piece's attributed
 * string and the line is built from that. **APPENDING IS WHAT MAKES IT SAFE**: the store's characters keep their
 * glyph indices and their offsets — the hyphen lands at the line's END, where nothing before it can move — so
 * `CTLineGetOffsetForStringIndex:` still answers for every character of the range, and `glyphRange` for the
 * fragment is unchanged. What it costs is that the LINE has one more glyph than the fragment claims characters,
 * which is why the draw pass widens the LAST run by that one glyph and why `hyphenated` is a flag on the fragment
 * rather than something a reader could infer.
 *
 * A DECIMAL TAB IS NOT RE-ALIGNED ON A HYPHENATED LINE, AND THAT IS A LIMITATION NAMED RATHER THAN HIDDEN: the
 * alignment needs the provisional line's tab positions and this line is built with the style's own stops. A line
 * that both ends in a hyphen AND carries a decimal tab is not a case this tier claims. */
- (CTLineRef)cg_createHyphenatedLineForRange:(NSRange)range attributedString:(CFAttributedStringRef)rich
{
	CFAttributedStringRef sub = CFAttributedStringCreateWithSubstring(kCFAllocatorDefault, rich,
		CFRangeMake((CFIndex)range.location, (CFIndex)range.length));
	CFMutableAttributedStringRef mutable = (sub != NULL)
		? CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 0, sub) : NULL;
	CTLineRef line = NULL;

	if (sub != NULL) {
		CFRelease(sub);
	}
	if (mutable != NULL) {
		/* **THE HYPHEN CARRIES THE ATTRIBUTES OF THE CHARACTER BEFORE IT**, which is the face, the size and the
		 * colour the hyphen should be drawn in; there is no other character it could take them from. */
		CFDictionaryRef attrs = CFAttributedStringGetAttributes(rich,
			(CFIndex)(range.location + range.length - 1), NULL);

		CFAttributedStringReplaceString(mutable, CFRangeMake((CFIndex)range.length, 0), CFSTR("\u2010"));
		if (attrs != NULL) {
			CFAttributedStringSetAttributes(mutable, CFRangeMake((CFIndex)range.length, 1), attrs, true);
		}
		line = CTLineCreateWithAttributedString(mutable);
		CFRelease(mutable);
	}
	return line;
}

/* **THE HYPHENATION ZONE, AND IT IS DERIVED FROM APPLE'S OWN TWO ENDPOINTS RATHER THAN CHOSEN FREELY.** Apple's
 * sentence for the factor is "0.0 means no hyphenation; 1.0 means hyphenate as much as possible", so the factor is
 * a THRESHOLD and a LARGER one means MORE hyphenation — which pins the direction and rules out the obvious-looking
 * "fraction of the line the piece must fill". Read as a zone, the two endpoints fall out: a line is hyphenated when
 * the breaker's own break would leave more than `1 - factor` of the width EMPTY, and since the slack is
 * `width - lineWidth`, that condition is exactly **`lineWidth < factor * width`**. At 0.0 it is `lineWidth < 0`,
 * which nothing satisfies — so the DEFAULT (the factor is 0.0) leaves every existing document laid out as it was,
 * without a special case; at 1.0 it is `lineWidth < width`, which is every line that is not exactly full, which is
 * "as much as possible". **THE MAPPING IS THIS TIER'S AND IS SAID SO HERE**: AppKit's own numbers for the zone are
 * not published, and what is modelled is the threshold, not whatever arithmetic AppKit uses behind it. */
- (CTLineRef)cg_hyphenatedLineForRange:(NSRange *)range style:(NSParagraphStyle *)style
	attributedString:(CFAttributedStringRef)rich typesetter:(CTTypesetterRef)ts font:(NSFont *)font
	width:(CGFloat)width
{
	NSUInteger length = [_textStorage length];
	NSUInteger wordStart = NSMaxRange(*range);
	NSUInteger wordEnd = wordStart;
	CFIndex ceiling;

	/* **THE WORD THAT DID NOT FIT IS THE ONE THAT BEGINS WHERE THE BREAK LEFT OFF.** A break at a line ending, at
	 * the end of the text, or before something that is not a letter has no word to hyphenate, and this answers NULL
	 * for all three rather than moving the break. */
	if (wordStart >= length || !fn_letter_char([[_textStorage string] characterAtIndex:wordStart])) {
		return NULL;
	}
	while (wordEnd < length && fn_letter_char([[_textStorage string] characterAtIndex:wordEnd])) {
		wordEnd++;
	}
	/* **THE DOOR GIVES THE POINTS BACKWARD AND THE LONGEST PIECE IS TRIED FIRST**, so the first piece that FITS is
	 * the longest that fits — which is the only piece worth taking, because a shorter one would leave the line even
	 * emptier than the break the typesetter already chose. `ceiling` walks down one point at a time and the loop
	 * ends when the door runs out or when a piece would be too short to be a line. */
	for (ceiling = (CFIndex)wordEnd; ceiling > (CFIndex)wordStart + 1;) {
		CFIndex at = (CFIndex)[_textStorage lineBreakByHyphenatingBeforeIndex:(NSUInteger)ceiling
							withinRange:NSMakeRange(wordStart, wordEnd - wordStart)];
		NSRange piece;
		CTLineRef line;

		if (at == (CFIndex)NSNotFound || at <= (CFIndex)range->location) {
			break;
		}
		piece = NSMakeRange(range->location, (NSUInteger)(at - (CFIndex)range->location));
		line = [self cg_createHyphenatedLineForRange:piece attributedString:rich];
		if (line != NULL) {
			CGFloat pieceWidth = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);

			if (pieceWidth <= width) {
				*range = piece;
				return line;
			}
			CFRelease(line);
		}
		ceiling = at;
	}
	return NULL;
}

/* **AND THE BLOCK A LINE IS SET IN, WHICH IS THE FIRST `NSTextTableBlock` IN ITS PARAGRAPH STYLE — or the first plain
 * block when there is no table cell.** A block is a paragraph property, so every line of the paragraph reads the same
 * one; a table cell is preferred over a plain block because a cell IS the inner box. */
- (NSTextBlock *)cg_blockForFragment:(FNFragment *)fragment
{
	NSParagraphStyle *style = [self cg_paragraphStyleAt:fragment->range.location];
	NSArray *blocks = [style textBlocks];
	NSTextBlock *plain = nil;
	NSUInteger i;

	for (i = 0; i < [blocks count]; i++) {
		id block = [blocks objectAtIndex:i];

		if ([block isKindOfClass:[NSTextTableBlock class]]) {
			return block;
		}
		if (plain == nil) {
			plain = block;
		}
	}
	return plain;
}

/* **AND ONE BLOCK'S FRAME, WHICH IS ITS CONTENT GROWN BY ITS OWN LAYERS.** The union of the group's used rects is the
 * content; the block's `-boundsRectForContentRect:` grows it by padding, border and margin on each edge; the
 * container's origin offsets the whole thing. THE FRAME IS SEPARATE FROM THE DRAW because a COLLAPSING table has to
 * know every cell's frame before it can decide which edge each cell draws. */
- (NSRect)cg_frameForBlock:(NSTextBlock *)block union:(NSRect)unionRect containerIndex:(NSUInteger)index
		    origin:(NSPoint)origin characterRange:(NSRange)charRange
{
	NSTextContainer *container = [_textContainers objectAtIndex:index];
	NSRect containerRect = NSMakeRect(0.0, 0.0, [container containerSize].width, [container containerSize].height);
	NSRect bounds = [block boundsRectForContentRect:unionRect inRect:containerRect
					  textContainer:container characterRange:charRange];

	return NSMakeRect(bounds.origin.x + origin.x, bounds.origin.y + origin.y,
			  bounds.size.width, bounds.size.height);
}

/* **AND ONE BLOCK GROUP DRAWN, WITH THE EDGES IT OWNS.** All four for a plain block; the mask comes from the grid when
 * the block is a cell of a table that collapses its borders. */
- (void)cg_drawBlock:(NSTextBlock *)block union:(NSRect)unionRect containerIndex:(NSUInteger)index
	      origin:(NSPoint)origin characterRange:(NSRange)charRange edges:(NSTextBlockEdge)edges
{
	NSTextContainer *container = [_textContainers objectAtIndex:index];
	NSRect frame = [self cg_frameForBlock:block union:unionRect containerIndex:index origin:origin
				characterRange:charRange];

	[block drawBackgroundWithFrame:frame inView:[container textView] characterRange:charRange layoutManager:self
		edges:edges];
}

- (void)cg_drawBlock:(NSTextBlock *)block union:(NSRect)unionRect containerIndex:(NSUInteger)index
	      origin:(NSPoint)origin characterRange:(NSRange)charRange
{
	[self cg_drawBlock:block union:unionRect containerIndex:index origin:origin characterRange:charRange
		edges:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge | NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
}

/* **AND A CELL ADDED TO THE GRID BEING COLLECTED.** A cell is the run of fragments sharing one block object, so a
 * fragment either opens a cell or joins the one it belongs to. The search is linear because a table's cells are few
 * and the alternative — a dictionary keyed by a borrowed pointer — needs the same lifetime argument anyway.
 *
 * **AND A CELL'S BOX IS ITS CELL, NOT ITS TEXT.** The union is taken over the fragments' FLOW BAND (`rect` — the
 * column's content width) rather than their USED rect (the glyphs' own extent), so a short cell's box still reaches
 * its column's edge and two neighbours' boxes actually MEET. That is what makes a shared border something two cells
 * can disagree about drawing once; with a text-tight box the two borders float apart and there is nothing to collapse. */
- (void)cg_addCell:(FNFragment *)fragment block:(NSTextBlock *)block containerIndex:(NSUInteger)index
		to:(NSMutableArray *)cells
{
	NSUInteger k;

	for (k = 0; k < [cells count]; k++) {
		FNCellBox *cell = [cells objectAtIndex:k];

		if (cell->block == block) {
			cell->content = NSUnionRect(cell->content, fragment->rect);
			cell->range.length = (fragment->range.location + fragment->range.length) - cell->range.location;
			return;
		}
	}
	{
		FNCellBox *cell = [[[FNCellBox alloc] init] autorelease];

		cell->block = block;
		cell->content = fragment->rect;
		cell->containerIndex = index;
		cell->range = fragment->range;
		[cells addObject:cell];
	}
}

/* TWO INTERVALS OVERLAP WHEN EACH STARTS BEFORE THE OTHER ENDS, with the epsilon the whole file uses for a
 * measurement it did not compute itself. */
static BOOL fn_spans_overlap(CGFloat a0, CGFloat a1, CGFloat b0, CGFloat b1)
{
	return (a0 < b1 - 0.01) && (b0 < a1 - 0.01);
}

/* **WHICH OF TWO CELLS THAT SHARE AN EDGE DRAWS IT.** The WIDER border wins, so the collapsed edge comes out as heavy
 * as the heaviest of the two — and it is that cell's own colour, because the cell that owns the edge draws it. WHEN
 * THE WIDTHS ARE EQUAL the cell on the MIN side (left or top) keeps it, which is the rule this tier had before and
 * keeps the choice stable and symmetric. Both cells reach the same answer from their own side, because the comparison
 * and the tie-break are the same viewed from either. */
static BOOL fn_cell_owns_edge(CGFloat thisWidth, CGFloat otherWidth, BOOL tieGoesToThisCell)
{
	if (thisWidth > otherWidth) {
		return YES;
	}
	if (otherWidth > thisWidth) {
		return NO;
	}
	return tieGoesToThisCell;
}

/* **AND WHICH OF A CELL'S FOUR EDGES IT DRAWS WHEN THE BORDERS COLLAPSE.** A cell's box shares an edge with a
 * neighbour when the neighbour's OPPOSITE edge lies on it and their bands overlap: the neighbour to the LEFT shares
 * this cell's MinX, the one to the RIGHT its MaxX, the one ABOVE its MinY and the one BELOW its MaxY. EACH SHARED
 * EDGE IS AWARDED to one of the two cells — the wider border, ties to the min-side cell — and the cell that LOSES it
 * suppresses that one edge while keeping the other three. THE EDGES NO CELL MEETS are reported back through `outer`:
 * those are the TABLE's own edge to compete for, which is why this door says which ones are outer rather than only
 * which ones to draw. The test is by GEOMETRY rather than by row and column, so two boxes that do NOT actually meet
 * (a short cell above a tall one) keep both their edges rather than collapsing a line they do not share. */
- (NSTextBlockEdge)cg_edgesForCell:(FNCellBox *)cell inCells:(NSMutableArray *)cells
			     outer:(NSTextBlockEdge *)outerPtr
{
	NSTextBlockEdge edges = (NSTextBlockMinXEdge | NSTextBlockMaxXEdge | NSTextBlockMinYEdge | NSTextBlockMaxYEdge);
	NSTextBlockEdge outer = edges;
	CGFloat left = cell->frame.origin.x, right = NSMaxX(cell->frame);
	CGFloat top = cell->frame.origin.y, bottom = NSMaxY(cell->frame);
	NSUInteger k;

	for (k = 0; k < [cells count]; k++) {
		FNCellBox *other = [cells objectAtIndex:k];
		BOOL vertical, horizontal;

		if (other == cell) {
			continue;
		}
		vertical = fn_spans_overlap(top, bottom, other->frame.origin.y, NSMaxY(other->frame));
		horizontal = fn_spans_overlap(left, right, other->frame.origin.x, NSMaxX(other->frame));

		/* THE LEFT NEIGHBOUR'S MaxX AND THIS CELL'S MinX ARE ONE EDGE, and the LEFT cell is the min side. */
		if (vertical && fabs(left - NSMaxX(other->frame)) < 0.01) {
			outer &= ~NSTextBlockMinXEdge;
			if (!fn_cell_owns_edge([cell->block widthForLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge],
					       [other->block widthForLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge], NO)) {
				edges &= ~NSTextBlockMinXEdge;
			}
		}
		/* THE RIGHT NEIGHBOUR'S MinX AND THIS CELL'S MaxX ARE ONE EDGE, and THIS cell is the min side. */
		if (vertical && fabs(right - other->frame.origin.x) < 0.01) {
			outer &= ~NSTextBlockMaxXEdge;
			if (!fn_cell_owns_edge([cell->block widthForLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge],
					       [other->block widthForLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge], YES)) {
				edges &= ~NSTextBlockMaxXEdge;
			}
		}
		/* THE NEIGHBOUR ABOVE'S MaxY AND THIS CELL'S MinY ARE ONE EDGE, and the ABOVE cell is the min side. */
		if (horizontal && fabs(top - NSMaxY(other->frame)) < 0.01) {
			outer &= ~NSTextBlockMinYEdge;
			if (!fn_cell_owns_edge([cell->block widthForLayer:NSTextBlockBorder edge:NSTextBlockMinYEdge],
					       [other->block widthForLayer:NSTextBlockBorder edge:NSTextBlockMaxYEdge], NO)) {
				edges &= ~NSTextBlockMinYEdge;
			}
		}
		/* THE NEIGHBOUR BELOW'S MinY AND THIS CELL'S MaxY ARE ONE EDGE, and THIS cell is the min side. */
		if (horizontal && fabs(bottom - other->frame.origin.y) < 0.01) {
			outer &= ~NSTextBlockMaxYEdge;
			if (!fn_cell_owns_edge([cell->block widthForLayer:NSTextBlockBorder edge:NSTextBlockMaxYEdge],
					       [other->block widthForLayer:NSTextBlockBorder edge:NSTextBlockMinYEdge], YES)) {
				edges &= ~NSTextBlockMaxYEdge;
			}
		}
	}
	if (outerPtr != NULL) {
		*outerPtr = outer;
	}
	return edges;
}

/* **AND THE TABLE'S RUN DRAWN — FIRST ITS OWN BOX, THEN EVERY CELL'S.** The cells' frames are computed first, because
 * the table's box is the box around THEM (their frames, not their text) and a collapsing table must know every frame
 * before it can award any edge. THE TABLE ITSELF JOINS THE COLLAPSE ON ITS OUTER EDGES: a side the table borders
 * competes with the outer cells that meet it by the same heavier-border rule, so the grid ends up with ONE outer
 * border rather than the table's and the cells' drawn one over the other. Otherwise each block draws its whole frame,
 * which is Apple's default and what this tier did before the collapse existed. */
- (void)cg_drawTable:(NSTextTable *)table cells:(NSMutableArray *)cells
      containerIndex:(NSUInteger)tableContainer origin:(NSPoint)origin characterRange:(NSRange)tableRange
{
	NSTextBlockEdge sides[4] = { NSTextBlockMinXEdge, NSTextBlockMaxXEdge, NSTextBlockMinYEdge, NSTextBlockMaxYEdge };
	/* WHICH SIDE IS THE MIN ONE: the table is outside on the LEFT and TOP, so a tie there is the table's; on the
	 * right and bottom the OUTER CELL is the min side, so a tie is the cell's. */
	BOOL tieToTable[4] = { YES, NO, YES, NO };
	NSTextBlockEdge tableEdges = (NSTextBlockMinXEdge | NSTextBlockMaxXEdge | NSTextBlockMinYEdge | NSTextBlockMaxYEdge);
	NSRect cellsUnion = NSZeroRect;
	BOOL collapse = [table collapsesBorders];
	BOOL haveOuter[4] = { NO, NO, NO, NO };
	CGFloat tableWidth[4];
	CGFloat maxCellWidth[4] = { 0.0, 0.0, 0.0, 0.0 };
	NSUInteger k, s;

	for (k = 0; k < [cells count]; k++) {
		FNCellBox *cell = [cells objectAtIndex:k];
		NSRect frame = [self cg_frameForBlock:cell->block union:cell->content
			containerIndex:cell->containerIndex origin:origin characterRange:cell->range];

		cell->frame = frame;
		cell->edges = (NSTextBlockEdge)(NSTextBlockMinXEdge | NSTextBlockMaxXEdge
			| NSTextBlockMinYEdge | NSTextBlockMaxYEdge);
		/* THE UNION IS KEPT IN CONTAINER COORDINATES, because the table's frame is grown from it and
		 * `-cg_frameForBlock:` adds the origin itself. */
		frame.origin.x -= origin.x;
		frame.origin.y -= origin.y;
		cellsUnion = (k == 0) ? frame : NSUnionRect(cellsUnion, frame);
	}
	if (collapse) {
		/* EVERY CELL'S SHARED EDGES FIRST; then the table competes for the OUTER ones. */
		for (k = 0; k < [cells count]; k++) {
			FNCellBox *cell = [cells objectAtIndex:k];

			cell->edges = [self cg_edgesForCell:cell inCells:cells outer:&cell->outer];
		}
		for (s = 0; s < 4; s++) {
			tableWidth[s] = [table widthForLayer:NSTextBlockBorder edge:sides[s]];
			for (k = 0; k < [cells count]; k++) {
				FNCellBox *cell = [cells objectAtIndex:k];

				if ((cell->outer & sides[s]) != 0) {
					CGFloat w = [cell->block widthForLayer:NSTextBlockBorder edge:sides[s]];

					haveOuter[s] = YES;
					if (w > maxCellWidth[s]) {
						maxCellWidth[s] = w;
					}
				}
			}
			/* **THE TABLE KEEPS A SIDE ONLY IF IT WINS IT**; where it loses, the outer cells keep theirs. */
			if (haveOuter[s] && !fn_cell_owns_edge(tableWidth[s], maxCellWidth[s], tieToTable[s])) {
				tableEdges &= ~sides[s];
			}
			for (k = 0; k < [cells count]; k++) {
				FNCellBox *cell = [cells objectAtIndex:k];

				if ((cell->outer & sides[s]) != 0
				    && fn_cell_owns_edge(tableWidth[s], maxCellWidth[s], tieToTable[s])) {
					cell->edges &= ~sides[s];
				}
			}
		}
	}
	[self cg_drawBlock:table union:cellsUnion containerIndex:tableContainer origin:origin characterRange:tableRange
		edges:tableEdges];
	for (k = 0; k < [cells count]; k++) {
		FNCellBox *cell = [cells objectAtIndex:k];

		[self cg_drawBlock:cell->block union:cell->content containerIndex:cell->containerIndex
			origin:origin characterRange:cell->range edges:cell->edges];
	}
}

/* **AND THE PASS THAT GROUPS CONSECUTIVE LINES BY THEIR BLOCK — AND BY THEIR TABLE, WHICH IS BEHIND IT.** A run of
 * fragments sharing the same block object is one box; a run sharing the same `NSTextTable` is the table's own box,
 * drawn FIRST so every cell's ground sits on it and every border frames it. A fragment with no block closes both runs
 * in flight. The pass is separate from the run walk because a box is BEHIND every run background.
 *
 * **A TABLE'S CELLS ARE COLLECTED RATHER THAN DRAWN AS THEY ARRIVE**, because a collapsing table cannot decide who
 * owns a shared edge until it has seen both cells that meet there. Everything else is drawn when its run closes. */
- (void)cg_drawBlocksForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
{
	NSTextBlock *current = nil;
	NSTextTable *currentTable = nil;
	NSRect unionRect = NSZeroRect;
	NSUInteger containerForBlock = 0;
	NSUInteger containerForTable = 0;
	NSRange range = NSMakeRange(0, 0);
	NSRange tableRange = NSMakeRange(0, 0);
	NSMutableArray *tableCells = nil;
	BOOL haveUnion = NO;
	NSUInteger i, j;

	(void)glyphsToShow;
	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *fragment = [fragments objectAtIndex:j];
			NSTextBlock *block = [self cg_blockForFragment:fragment];
			NSTextTable *table = [block isKindOfClass:[NSTextTableBlock class]]
				? [(NSTextTableBlock *)block table] : nil;

			/* A CHANGE OF TABLE CLOSES THE TABLE RUN IN FLIGHT, and a table OPENING closes any plain-block run
			 * first, so the two kinds of box stay in the order they were laid out in. */
			if (table != currentTable) {
				if (currentTable != nil) {
					[self cg_drawTable:currentTable cells:tableCells
						containerIndex:containerForTable origin:origin characterRange:tableRange];
				}
				if (table != nil && haveUnion) {
					[self cg_drawBlock:current union:unionRect containerIndex:containerForBlock origin:origin
						characterRange:range];
					haveUnion = NO;
					current = nil;
				}
				currentTable = table;
				tableCells = (table != nil) ? [NSMutableArray array] : nil;
				if (table != nil) {
					tableRange = fragment->range;
					containerForTable = i;
				}
			} else if (table != nil) {
				tableRange.length = (fragment->range.location + fragment->range.length) - tableRange.location;
			}
			if (table != nil) {
				[self cg_addCell:fragment block:block containerIndex:i to:tableCells];
				continue;
			}

			/* AND EACH PLAIN BLOCK'S BOX. */
			if (block == nil) {
				if (haveUnion) {
					[self cg_drawBlock:current union:unionRect containerIndex:containerForBlock origin:origin
						characterRange:range];
					haveUnion = NO;
				}
				current = nil;
				continue;
			}
			if (block != current) {
				if (haveUnion) {
					[self cg_drawBlock:current union:unionRect containerIndex:containerForBlock origin:origin
						characterRange:range];
				}
				current = block;
				unionRect = fragment->used;
				containerForBlock = i;
				range = fragment->range;
				haveUnion = YES;
			} else {
				unionRect = NSUnionRect(unionRect, fragment->used);
				range.length = (fragment->range.location + fragment->range.length) - range.location;
			}
		}
	}
	if (haveUnion) {
		[self cg_drawBlock:current union:unionRect containerIndex:containerForBlock origin:origin
			characterRange:range];
	}
	if (currentTable != nil) {
		[self cg_drawTable:currentTable cells:tableCells containerIndex:containerForTable
			origin:origin characterRange:tableRange];
	}
}

/* **THE PARAGRAPH STYLE A LINE BELONGS TO, WHICH IS THE ONE AT ITS PARAGRAPH'S START.** A paragraph begins at the first
 * character of the store or after a newline, so a wrapped line in the middle of a paragraph reads the same style as the
 * line above it — which is the whole point of a PARAGRAPH style as against a character one. A store with no style
 * answers nil, and every scalar read from nil is zero, which is exactly the default style. */
- (NSParagraphStyle *)cg_paragraphStyleAt:(NSUInteger)start
{
	NSString *string = [_textStorage string];
	NSUInteger paragraphStart = start;

	if ([_textStorage length] == 0) {
		return nil;
	}
	if (paragraphStart >= [string length]) {
		paragraphStart = [string length] - 1;
	}
	while (paragraphStart > 0 && [string characterAtIndex:paragraphStart - 1] != '\n') {
		paragraphStart--;
	}
	return [[_textStorage attributesAtIndex:paragraphStart effectiveRange:NULL]
			objectForKey:NSParagraphStyleAttributeName];
}

/* **THE ALIGNMENT OF THE PARAGRAPH A LINE STARTS IN, WHICH IS THE PARAGRAPH'S OWN AND NOT THE LINE'S.** NATURAL is
 * resolved HERE, because it is not an edge of its own: it is the edge the BASE WRITING DIRECTION names — left for a
 * left-to-right paragraph, RIGHT for a right-to-left one — so the direction has a reader and the three EXPLICIT
 * alignments are untouched by it. */
- (NSTextAlignment)cg_alignmentForParagraphAt:(NSUInteger)start
{
	NSParagraphStyle *style = [self cg_paragraphStyleAt:start];
	NSTextAlignment alignment = [style alignment];

	if (alignment == NSNaturalTextAlignment && [style baseWritingDirection] == NSWritingDirectionRightToLeft) {
		return NSRightTextAlignment;
	}
	return alignment;
}

/* **AND THE FLOAT IS THE LINE'S PLACE INSIDE THE WIDTH IT WAS GIVEN** — 0 for left, 1 for right, 0.5 for centre, and the
 * engine's own `-CTLineGetPenOffsetForFlush` does the arithmetic so the answer agrees with the glyphs it will set. A
 * justified paragraph is drawn LEFT for now; stretching a line is the door this slice does not carry, and it is named
 * in `NSParagraphStyle.h` rather than silently pretended. */
- (CGFloat)cg_alignmentOffsetForLine:(CTLineRef)line alignment:(NSTextAlignment)alignment width:(CGFloat)width
{
	CGFloat factor = 0.0;
	CGFloat offset;

	if (alignment == NSCenterTextAlignment) {
		factor = 0.5;
	} else if (alignment == NSRightTextAlignment) {
		factor = 1.0;
	}
	if (line == NULL || factor == 0.0 || width <= 0.0) {
		return 0.0;
	}
	offset = (CGFloat)CTLineGetPenOffsetForFlush(line, factor, (double)width);
	return (offset > 0.0) ? offset : 0.0;
}

/* ============================================================================================ *
 * THE TABLE GRID, WHICH IS A SECOND LAYOUT MODE                                                       *
 * ============================================================================================ */

/* **THE CELL A PARAGRAPH IS IN, OR NIL.** A table cell is a `NSTextTableBlock` in the paragraph's style, which is
 * where Apple attaches it; a paragraph with a plain block but no cell answers nil, because a plain block is drawn
 * around a single paragraph and has no grid to belong to. */
- (NSTextTableBlock *)cg_cellAtParagraphStart:(NSUInteger)index
{
	NSArray *blocks = [[self cg_paragraphStyleAt:index] textBlocks];
	NSUInteger i;

	for (i = 0; i < [blocks count]; i++) {
		id block = [blocks objectAtIndex:i];

		if ([block isKindOfClass:[NSTextTableBlock class]]) {
			return block;
		}
	}
	return nil;
}

/* THE WIDTH A RANGE WANTS WHEN IT IS SET AS ONE LINE, which is how an AUTOMATIC column measures its content. */
- (CGFloat)cg_naturalWidthOfRange:(NSRange)range font:(NSFont *)font
{
	CTLineRef line = [self cg_createLineForRange:range font:font];
	CGFloat width = 0.0;

	if (line != NULL) {
		width = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
		CFRelease(line);
	}
	return width;
}

/* **THE SIZE AN ATTACHMENT CHARACTER OCCUPIES: THE CALLER'S IF THERE IS ONE, ELSE THE CELL'S.** It is a door of its own
 * because the layout, the draw and the public accessor all have to agree about the number, and three copies of "ask the
 * override, then the cell" is three chances to disagree. */
- (NSSize)cg_attachmentSizeForCharacterIndex:(NSUInteger)index fallback:(NSSize)fallback
{
	NSValue *value = [_attachmentSizes objectForKey:[NSNumber numberWithUnsignedInteger:index]];

	return (value != nil) ? [value sizeValue] : fallback;
}

/* **THE BOXES A RANGE CARRIES: ONE PER ATTACHMENT CHARACTER, WITH THE WIDTH IT OCCUPIES.** The engine measured a
 * placeholder glyph for the character, so both numbers are recorded — the box's width and the advance the glyph had —
 * and the difference is what shifts everything after it. A range with no attachment answers nil, which is the common
 * case. */
- (NSArray *)cg_boxesForRange:(NSRange)range line:(CTLineRef)line
{
	NSMutableArray *boxes = nil;
	NSUInteger pos = range.location;
	NSUInteger end = range.location + range.length;

	while (pos < end) {
		NSRange runRange;
		NSDictionary *attrs = [_textStorage attributesAtIndex:pos longestEffectiveRange:&runRange inRange:range];
		NSTextAttachment *attachment = [attrs objectForKey:NSAttachmentAttributeName];
		NSUInteger runEnd = runRange.location + runRange.length;

		if (runEnd > end) {
			runEnd = end;
		}
		if (runEnd <= pos) {
			runEnd = pos + 1;
		}
		if (attachment != nil && line != NULL) {
			NSCell<NSTextAttachmentCell> *cell = [attachment attachmentCell];
			NSSize cellSize = (cell != nil) ? [cell cellSize] : NSZeroSize;
			NSUInteger k;

			/* **THE SIZE IS ASKED PER CHARACTER, BECAUSE A CALLER MAY HAVE OVERRIDDEN ONE OF THEM.** The cell's own
			 * size is the fallback; `-setAttachmentSize:forGlyphRange:` is what makes the layout reserve something
			 * else, and this is the one place the override has to reach for the layout to move. */
			for (k = pos; k < runEnd; k++) {
				NSSize size = [self cg_attachmentSizeForCharacterIndex:k fallback:cellSize];
				CFIndex rel;
				CGFloat advance;

				if (size.width <= 0.0) {
					continue;
				}
				rel = (CFIndex)(k - range.location);
				advance = (CGFloat)(CTLineGetOffsetForStringIndex(line, rel + 1, NULL)
						    - CTLineGetOffsetForStringIndex(line, rel, NULL));
				if (boxes == nil) {
					boxes = [NSMutableArray array];
				}
				[boxes addObject:[FNBox boxWithIndex:k width:size.width engineAdvance:advance
					ascent:size.height descent:0.0 content:attachment]];
			}
		}
		pos = runEnd;
	}
	return boxes;
}

/* THE WIDTH A RANGE'S BOXES ADD beyond what the engine measured. */
- (CGFloat)cg_boxExtra:(NSArray *)boxes
{
	CGFloat extra = 0.0;
	NSUInteger i;

	for (i = 0; i < [boxes count]; i++) {
		FNBox *box = [boxes objectAtIndex:i];

		extra += box->width - box->engineAdvance;
	}
	return extra;
}

/* AND THE PART OF THAT EXTRA THAT LIES BEFORE A CHARACTER: the shift every x at or after it takes. */
- (CGFloat)cg_boxExtraBeforeIndex:(NSUInteger)index inFragment:(FNFragment *)fragment
{
	CGFloat extra = 0.0;
	NSUInteger i;

	for (i = 0; i < [fragment->boxes count]; i++) {
		FNBox *box = [fragment->boxes objectAtIndex:i];

		if (box->index >= index) {
			break;
		}
		extra += box->width - box->engineAdvance;
	}
	return extra;
}

/* **AND THE x OF A CHARACTER, WHICH IS THE ENGINE'S OFFSET PLUS THE BOXES BEFORE IT.** Every caller that draws or
 * places by an x comes through here, so the shift cannot be applied in one place and forgotten in another. */
- (CGFloat)cg_xInFragment:(FNFragment *)fragment forCharacterIndex:(NSUInteger)index
{
	CFIndex rel = (CFIndex)(index - fragment->range.location);
	CGFloat x = fragment->used.origin.x + [self cg_boxExtraBeforeIndex:index inFragment:fragment];

	if (fragment->line != NULL) {
		if (rel < 0) {
			rel = 0;
		}
		if ((NSUInteger)rel > fragment->range.length) {
			rel = (CFIndex)fragment->range.length;
		}
		x += (CGFloat)CTLineGetOffsetForStringIndex(fragment->line, rel, NULL);
	}
	return x;
}

/* **ONE CELL'S PARAGRAPH, LAID OUT INSIDE ITS COLUMN'S CONTENT WIDTH.** The line geometry is the paragraph style's,
 * exactly as a normal paragraph's is; the only difference is that the available width is the CELL's. A NIL `out` is a
 * MEASUREMENT — the height is the return value and no fragment is made — which is how a row's height is found before
 * its cells are placed. The leading gap is per-paragraph, so a cell of several paragraphs stacks them the same way
 * the document does. */
- (CGFloat)cg_layOutCell:(NSTextTableBlock *)cell range:(NSRange)paraRange typesetter:(CTTypesetterRef)ts
	    attributedString:(CFAttributedStringRef)rich font:(NSFont *)font
	    baseAscent:(CGFloat)baseAscent baseLineHeight:(CGFloat)baseLineHeight
		       x:(CGFloat)x width:(CGFloat)cellWidth into:(NSMutableArray *)out top:(CGFloat)top
	   glyphBase:(NSUInteger *)glyphBasePtr
{
	CFIndex start = (CFIndex)paraRange.location;
	CFIndex end = (CFIndex)(paraRange.location + paraRange.length);
	CGFloat y = top;
	BOOL first = YES;
	NSParagraphStyle *previous = nil;

	while (start < end) {
		NSParagraphStyle *style = [self cg_paragraphStyleAt:(NSUInteger)start];
		BOOL paragraphStart = (start == (CFIndex)paraRange.location);
		CGFloat indent = paragraphStart ? [style firstLineHeadIndent] : [style headIndent];
		CGFloat tailIndent = [style tailIndent];
		CGFloat leadingEdge = x + indent;
		CGFloat trailingEdge = (tailIndent >= 0.0) ? (x + cellWidth - tailIndent) : (x - tailIndent);
		CGFloat width = trailingEdge - leadingEdge;
		CGFloat multiple = [style lineHeightMultiple];
		CGFloat lineHeight;
		CGFloat lineAscent;
		CGFloat leading;
		CFIndex count;
		CTLineRef line = NULL;
		CGFloat lineWidth = 0.0;
		NSRange range;

		if (width < 1.0) {
			width = 1.0;
		}
		if (multiple <= 0.0) {
			multiple = 1.0;
		}
		lineHeight = baseLineHeight * multiple;
		if ([style minimumLineHeight] > 0.0 && lineHeight < [style minimumLineHeight]) {
			lineHeight = [style minimumLineHeight];
		}
		if ([style maximumLineHeight] > 0.0 && lineHeight > [style maximumLineHeight]) {
			lineHeight = [style maximumLineHeight];
		}
		lineAscent = baseAscent * multiple;
		if (lineAscent > lineHeight) {
			lineAscent = lineHeight;
		}
		if (lineAscent < 0.0) {
			lineAscent = 0.0;
		}
		if (first) {
			leading = 0.0;
		} else if (paragraphStart) {
			leading = [previous paragraphSpacing] + [style paragraphSpacingBefore];
		} else {
			leading = [style lineSpacing];
		}
		count = CTTypesetterSuggestLineBreak(ts, start, (double)width);
		if (count <= 0) {
			count = 1;
		}
		if (start + count > end) {
			count = end - start;
		}
		range = NSMakeRange((NSUInteger)start, (NSUInteger)count);
		line = [self cg_createLineForRange:range style:style attributedString:rich typesetter:ts font:font];
		if (line != NULL) {
			lineWidth = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
			if (lineWidth > width) {
				lineWidth = width;
			}
		}
		if (out != nil) {
			CGFloat textTop = y + leading;
			CGFloat baseline = textTop + lineAscent;
			CGFloat alignOffset = [self cg_alignmentOffsetForLine:line
				alignment:[self cg_alignmentForParagraphAt:(NSUInteger)start] width:width];
			NSArray *boxes = [self cg_boxesForRange:range line:line];

			/* **AND A CELL'S LINE OCCUPIES THE GLYPHS ITS LINE HAS, FROM ONE RUNNING BASE.** This used to record
			 * `range.location` — the string's own index — as a GLYPH index, which was never the manager's glyph
			 * space and is further from it now that a line's glyph count is the shaper's. The base is threaded in
			 * from the layout that appends the fragments, so the space stays contiguous across a table. */
			NSUInteger cellGlyphs = (line != NULL) ? (NSUInteger)CTLineGetGlyphCount(line) : 0;
			NSUInteger cellBase = (glyphBasePtr != NULL) ? *glyphBasePtr : 0;

			[out addObject:[FNFragment fragmentWithRange:range
				glyphRange:NSMakeRange(cellBase, cellGlyphs)
				rect:NSMakeRect(x, y, cellWidth, leading + lineHeight)
				usedRect:NSMakeRect(leadingEdge + alignOffset, textTop, lineWidth + [self cg_boxExtra:boxes], lineHeight)
				baseline:baseline line:line boxes:boxes]];
			if (glyphBasePtr != NULL) {
				*glyphBasePtr = cellBase + cellGlyphs;
			}
		} else if (line != NULL) {
			CFRelease(line);
		}
		y = y + leading + lineHeight;
		previous = style;
		first = NO;
		start += count;
	}
	return y - top;
}

/* **AND THE GRID ITSELF.** The table's character range is the run of consecutive paragraphs whose cells belong to the
 * SAME table; its columns are measured (automatic: the widest cell in each column, its span divided out, scaled to fit
 * the container) or fixed (equal shares); and its rows are as tall as the tallest cell in them. Each cell's content is
 * laid out inside its own columns' width and PLACED at its column's x, so cells in one row sit side by side. THE
 * GLYPH MAP IS THE IDENTITY HERE — a cell's glyph range is its character range — because the cells are in character
 * order, which is what keeps `-glyphRangeForCharacterRange:` a walk of the fragment list. **AND A TABLE FLOWS ACROSS
 * CONTAINERS AT A ROW BOUNDARY**: a row that does not fit the container it is being laid into begins the next one,
 * with the columns measured from EVERY cell so the widths do not change halfway through the table. */
/* **AND A CELL'S OWN LAYERS ARE RESERVED IN THE COLUMN'S WIDTH.** The grid measures a column by its widest cell and
 * then the cell's padding, border and margin are ADDED, so the ground and the border have room and neighbouring cells
 * do not touch; the content is placed INSIDE them. The widths are read as ABSOLUTE points here — a percentage layer
 * belongs to the block's own `-boundsRectForContentRect:`, which resolves it against a rectangle the grid does not
 * have when it measures. */
- (CGFloat)cg_tableCellInset:(NSTextTableBlock *)cell edge:(NSTextBlockEdge)edge
{
	return [cell widthForLayer:NSTextBlockPadding edge:edge]
	     + [cell widthForLayer:NSTextBlockBorder edge:edge]
	     + [cell widthForLayer:NSTextBlockMargin edge:edge];
}

/* **AND THE PARAGRAPH A TABLE BEGINS AT, FOUND BY WALKING BACK.** When a table flows across containers the manager
 * resumes at a row in the MIDDLE, and the columns must be measured from EVERY cell — so the scan has to begin at the
 * table's first paragraph, not at the resume point. A paragraph before `index` whose cell belongs to the SAME table is
 * part of it; another table, plain text, or the start of the store is the boundary. */
- (NSUInteger)cg_tableStartFor:(NSUInteger)index
{
	NSString *string = [_textStorage string];
	NSTextTable *table = [[self cg_cellAtParagraphStart:index] table];
	NSUInteger p = index;

	while (p > 0 && [string characterAtIndex:p - 1] == '\n') {
		NSUInteger prevStart = p - 1;
		NSTextTableBlock *prevCell;

		while (prevStart > 0 && [string characterAtIndex:prevStart - 1] != '\n') {
			prevStart--;
		}
		prevCell = [self cg_cellAtParagraphStart:prevStart];
		if (prevCell == nil || [prevCell table] != table) {
			break;
		}
		p = prevStart;
	}
	return p;
}

- (NSUInteger)cg_layOutTableStartingAt:(NSUInteger)start typesetter:(CTTypesetterRef)ts
	attributedString:(CFAttributedStringRef)rich font:(NSFont *)font
	baseAscent:(CGFloat)baseAscent baseLineHeight:(CGFloat)baseLineHeight
	fragments:(NSMutableArray *)fragments container:(NSTextContainer *)container
	y:(CGFloat *)yPtr glyphBase:(NSUInteger *)glyphBasePtr
{
	NSString *string = [_textStorage string];
	NSUInteger n = [string length];
	NSTextTable *table = [[self cg_cellAtParagraphStart:start] table];
	NSUInteger tableStart = [self cg_tableStartFor:start];
	NSMutableArray *cells = [NSMutableArray array];
	NSMutableArray *ranges = [NSMutableArray array];
	NSUInteger p = tableStart;
	NSUInteger tableEnd;
	NSUInteger resume = NSNotFound;
	NSInteger rows = 0, columns = 0, firstRow = 0;
	CGFloat padding = [container lineFragmentPadding];
	CGFloat containerWidth = [container containerSize].width;
	CGFloat containerHeight = [container containerSize].height;
	CGFloat available = containerWidth - 2.0 * padding;
	NSRect containerBounds = NSMakeRect(0.0, 0.0, containerWidth, containerHeight);
	CGFloat *widths;
	CGFloat y = *yPtr;
	BOOL placed = NO;
	NSInteger row, column;

	/* **AND THE WHOLE TABLE IS SCANNED, NOT ONLY THE PART STILL TO PLACE.** A table that resumed in a later container
	 * must measure its columns from EVERY cell, or the widths would change halfway through it. */
	while (p < n) {
		NSTextTableBlock *cell = [self cg_cellAtParagraphStart:p];
		NSUInteger paraEnd;

		if (cell == nil || [cell table] != table) {
			break;
		}
		paraEnd = p;
		while (paraEnd < n && [string characterAtIndex:paraEnd] != '\n') {
			paraEnd++;
		}
		[cells addObject:cell];
		[ranges addObject:[NSValue valueWithRange:NSMakeRange(p, paraEnd - p)]];
		if ([cell startingRow] + [cell rowSpan] > rows) {
			rows = [cell startingRow] + [cell rowSpan];
		}
		if ([cell startingColumn] + [cell columnSpan] > columns) {
			columns = [cell startingColumn] + [cell columnSpan];
		}
		p = (paraEnd < n) ? paraEnd + 1 : paraEnd;
	}
	tableEnd = p;
	if ([cells count] == 0) {
		return start;
	}
	/* WHICH ROW THIS CALL BEGINS AT: the row of the cell the caller resumed on, or the first row. */
	{
		NSUInteger ci;

		for (ci = 0; ci < [cells count]; ci++) {
			if ([[ranges objectAtIndex:ci] rangeValue].location == start) {
				firstRow = [[cells objectAtIndex:ci] startingRow];
				break;
			}
		}
	}
	if (columns < 1) {
		columns = 1;
	}
	if (rows < 1) {
		rows = 1;
	}
	widths = (CGFloat *)malloc((size_t)columns * sizeof(CGFloat));
	for (column = 0; column < columns; column++) {
		widths[column] = 0.0;
	}
	if ([table layoutAlgorithm] == NSTextTableFixedLayoutAlgorithm) {
		for (column = 0; column < columns; column++) {
			widths[column] = available / (CGFloat)columns;
		}
	} else {
		NSUInteger ci;
		CGFloat total = 0.0;

		for (ci = 0; ci < [cells count]; ci++) {
			NSTextTableBlock *cell = [cells objectAtIndex:ci];
			NSRange r = [[ranges objectAtIndex:ci] rangeValue];
			/* **A COLUMN IS A WHOLE POINT WIDE, BECAUSE A LINE THAT EXACTLY FILLS ITS COLUMN IS THE LINE
			 * THAT BREAKS.** MEASURED with Figtree: the natural width of `aa` is 13.26, the column was set to
			 * 13.26, and `CTTypesetterSuggestLineBreak` — which asks whether the line fits, not whether it is
			 * within a rounding error — broke after the first `a`, so every one-character cell became two
			 * fragments and the second cell landed on the next row. `ceil` gives the line the fraction of a
			 * point it needs; the table's own width scaling still runs afterwards if the columns overflow. */
			CGFloat natural = ceil([self cg_naturalWidthOfRange:r font:font]
					+ [self cg_tableCellInset:cell edge:NSTextBlockMinXEdge]
					+ [self cg_tableCellInset:cell edge:NSTextBlockMaxXEdge]);
			NSInteger span = [cell columnSpan];
			NSInteger c;

			if (span < 1) {
				span = 1;
			}
			for (c = [cell startingColumn]; c < [cell startingColumn] + span && c < columns; c++) {
				if (natural / (CGFloat)span > widths[c]) {
					widths[c] = natural / (CGFloat)span;
				}
			}
		}
		for (column = 0; column < columns; column++) {
			total += widths[column];
		}
		if (total > available && total > 0.0) {
			for (column = 0; column < columns; column++) {
				widths[column] *= available / total;
			}
		} else if (total <= 0.0) {
			for (column = 0; column < columns; column++) {
				widths[column] = available / (CGFloat)columns;
			}
		}
	}
	/* **AND THE GRID IS PUBLISHED TO THE TABLE**, so that a cell's content rect can be ASKED OF IT rather than computed
	 * here: `-rectForBlock:layoutAtPoint:inRect:textContainer:characterRange:` is Apple's delegation door for exactly this
	 * arithmetic, and a subclass that overrides it moves its cells. ONE measurement, one place to override. */
	[table _setColumnWidths:widths count:columns padding:padding];

	for (row = 0; row < rows; row++) {
		CGFloat rowHeight = 0.0;
		NSUInteger ci;

		if (row < firstRow) {
			continue;	/* placed in an earlier container */
		}
		/* MEASURE THE ROW: the tallest cell sets it. */
		for (ci = 0; ci < [cells count]; ci++) {
			NSTextTableBlock *cell = [cells objectAtIndex:ci];
			NSRange r;
			CGFloat x, width, height;

			if ([cell startingRow] != row) {
				continue;
			}
			r = [[ranges objectAtIndex:ci] rangeValue];
			/* **THE CELL'S CONTENT RECT IS THE TABLE'S ANSWER**, through the delegation door the rest of the block's
			 * geometry already goes through: the default reproduces the arithmetic this loop used to do inline. */
			{
				/* THE POINT IS THE TABLE'S ORIGIN, not the first column's: `-rectForBlock:layoutAtPoint:...` adds the
				 * table's own padding, so passing the padding here would count it twice. */
				NSRect content = [cell rectForLayoutAtPoint:NSMakePoint(0.0, 0.0) inRect:containerBounds
							     textContainer:container characterRange:r];

				x = content.origin.x;
				width = content.size.width;
			}
			height = [self cg_layOutCell:cell range:r typesetter:ts attributedString:rich font:font
				baseAscent:baseAscent baseLineHeight:baseLineHeight x:x width:width into:nil top:0.0
				glyphBase:NULL];
			/* **AND THE VERTICAL LAYERS ARE RESERVED IN THE ROW'S HEIGHT.** Without this the content starts at the
			 * row's top and the box grows UPWARD from it, so two stacked cells' boxes OVERLAP by both their vertical
			 * insets and no edge is shared. Adding the insets here and starting the content below the top one below
			 * makes the boxes meet at the row boundary, which is what a collapsed border needs. */
			height += [self cg_tableCellInset:cell edge:NSTextBlockMinYEdge]
				+ [self cg_tableCellInset:cell edge:NSTextBlockMaxYEdge];
			if (height > rowHeight) {
				rowHeight = height;
			}
		}
		if (rowHeight <= 0.0) {
			rowHeight = baseLineHeight;
		}
		/* **AND THE CONTAINER'S OWN HEIGHT IS THE OVERFLOW EDGE**, once this container has taken a row: a table flows
		 * across containers by breaking at a ROW boundary, and the row that does not fit resumes in the next one. A
		 * container shorter than a single row still gets that row, which is what keeps the flow from looping. */
		if (containerHeight > 0.0 && placed && y + rowHeight > containerHeight + 0.001) {
			for (ci = 0; ci < [cells count]; ci++) {
				NSTextTableBlock *cell = [cells objectAtIndex:ci];

				if ([cell startingRow] == row) {
					resume = [[ranges objectAtIndex:ci] rangeValue].location;
					break;
				}
			}
			break;
		}
		/* PLACE THE ROW: every cell starts at the row's top, at its own columns' x. */
		for (ci = 0; ci < [cells count]; ci++) {
			NSTextTableBlock *cell = [cells objectAtIndex:ci];
			NSRange r;
			CGFloat x, width;

			if ([cell startingRow] != row) {
				continue;
			}
			r = [[ranges objectAtIndex:ci] rangeValue];
			/* **AND THE PLACING PASS ASKS THE SAME DOOR**, which is what makes an override take effect: the measuring pass
			 * decides a row's HEIGHT, and this one decides WHERE the cell's text goes. With only the first asking, a
			 * subclass could change the height a cell reserved and not the place it was drawn — MEASURED, which is why
			 * this site exists as a second call rather than a shared variable. */
			{
				/* THE POINT IS THE TABLE'S ORIGIN, not the first column's: `-rectForBlock:layoutAtPoint:...` adds the
				 * table's own padding, so passing the padding here would count it twice. */
				NSRect content = [cell rectForLayoutAtPoint:NSMakePoint(0.0, 0.0) inRect:containerBounds
							     textContainer:container characterRange:r];

				x = content.origin.x;
				width = content.size.width;
			}
			[self cg_layOutCell:cell range:r typesetter:ts attributedString:rich font:font
				baseAscent:baseAscent baseLineHeight:baseLineHeight x:x width:width into:fragments
				top:y + [self cg_tableCellInset:cell edge:NSTextBlockMinYEdge]
				glyphBase:glyphBasePtr];
		}
		placed = YES;
		y += rowHeight;
	}
	free(widths);
	*yPtr = y;
	/* **THE GLYPH BASE IS NOT TOUCHED HERE, AND THAT IS THE POINT.** It is advanced by each line the cells appended
	 * (`cg_layOutCell`), so it is already the glyph end of everything this table laid out; the two assignments that
	 * used to stand here wrote a CHARACTER index — `resume`, `tableEnd` — into a GLYPH base, which was wrong as soon
	 * as a line's glyph count stopped being its character count. */
	if (resume != NSNotFound) {
		return resume;
	}
	return tableEnd;
}

/* **AND THE BOXES, SET AS RUN DELEGATES SO THE ENGINE — NOT THIS CLASS — RESERVES THEIR WIDTH.** Every attachment's
 * character range gets a `CTRunDelegate` whose three answers come from the attachment's own cell, so the typesetter
 * measures the box and the line's offsets already include it; the manager's own `FNBox` arithmetic then sees an
 * `engineAdvance` equal to the width and adds nothing. THE DELEGATE IS RELEASED AFTER BEING SET because the mutable
 * string retains it, and it is kept alive by the attributed string the typesetter and the line retain. */
- (CFAttributedStringRef)cg_attributedStringByAddingRunDelegates:(CFAttributedStringRef)base
{
	CFMutableAttributedStringRef mutable = CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 0, base);
	NSUInteger n = [_textStorage length];
	NSUInteger pos = 0;

	if (mutable == NULL) {
		return NULL;
	}
	while (pos < n) {
		NSRange runRange;
		NSDictionary *attrs = [_textStorage attributesAtIndex:pos longestEffectiveRange:&runRange
								  inRange:NSMakeRange(0, n)];
		NSTextAttachment *attachment = [attrs objectForKey:NSAttachmentAttributeName];

		if (attachment != nil) {
			CTRunDelegateCallbacks callbacks = { 0, fn_attachment_ascent, fn_attachment_descent,
							     fn_attachment_width };
			CTRunDelegateRef delegate = CTRunDelegateCreate(&callbacks, attachment);

			if (delegate != NULL) {
				CFAttributedStringSetAttribute(mutable, CFRangeMake(runRange.location, runRange.length),
							       kCTRunDelegateAttributeName, delegate);
				CFRelease(delegate);
			}
		}
		pos = runRange.location + runRange.length;
		if (pos <= runRange.location) {
			break;
		}
	}
	return mutable;
}

- (void)cg_ensureLayout
{
	NSString *string;
	NSUInteger n;
	NSFont *font;
	CGFloat baseAscent;
	CGFloat baseLineHeight;
	CFMutableDictionaryRef attributes;
	CFAttributedStringRef s;
	CTTypesetterRef ts;
	CFIndex start;
	NSUInteger i;
	NSUInteger glyphBase = 0;
	NSUInteger lastContainer = 0;
	CGFloat lastY = 0.0;
	CGFloat lastAscent = 0.0;
	CGFloat lastLineHeight = 0.0;
	NSParagraphStyle *previousStyle = nil;
	BOOL firstFragment = YES;

	if (_invalidatedRange.location == NSNotFound) {
		return;
	}
	for (i = 0; i < [_fragments count]; i++) {
		[[_fragments objectAtIndex:i] removeAllObjects];
	}
	string = [_textStorage string];
	n = [string length];
	font = [self cg_font];
	baseAscent = [font ascender];
	baseLineHeight = [font ascender] - [font descender];

	if ([_textContainers count] == 0) {
		_invalidatedRange = NSMakeRange(NSNotFound, 0);
		return;
	}
	if (n == 0) {
		NSTextContainer *container = [_textContainers objectAtIndex:0];

		[[_fragments objectAtIndex:0] addObject:
			[FNFragment fragmentWithRange:NSMakeRange(0, 0) glyphRange:NSMakeRange(0, 0)
				rect:NSMakeRect(0.0, 0.0, [container containerSize].width, baseLineHeight)
				usedRect:NSMakeRect([container lineFragmentPadding], 0.0, 0.0, baseLineHeight)
				baseline:baseAscent line:NULL boxes:nil]];
		_invalidatedRange = NSMakeRange(NSNotFound, 0);
		return;
	}
	attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
			&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionarySetValue(attributes, kCTFontAttributeName, ((NSFont *)font)->_font);
	{
		CTParagraphStyleRef paragraphStyle = [self cg_createParagraphStyle];
		CFAttributedStringRef plain;

		if (paragraphStyle != NULL) {
			CFDictionarySetValue(attributes, kCTParagraphStyleAttributeName, paragraphStyle);
		}
		plain = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)string, attributes);
		CFRelease(attributes);
		if (paragraphStyle != NULL) {
			CFRelease(paragraphStyle);
		}
		/* **AND THE BOXES, ON THE STRING THE ENGINE READS**: the delegates are set here, so the TYPESETTER measures
		 * each attachment's width and the LINE's offsets already include it — the reservation is Core Text's, and this
		 * class's `FNBox` arithmetic below finds an advance that IS the width and adds nothing. */
		s = (plain != NULL) ? [self cg_attributedStringByAddingRunDelegates:plain] : NULL;
		if (plain != NULL) {
			CFRelease(plain);
		}
	}
	ts = (s != NULL) ? CTTypesetterCreateWithAttributedString(s) : NULL;
	/* **AND A STORE THE TYPESETTER WILL NOT TAKE IS STILL LAID OUT**, as one fragment, so a glyph can be found and a
	 * line drawn even when the engine refused the string. */
	if (ts == NULL) {
		NSTextContainer *container = [_textContainers objectAtIndex:0];
		CGFloat padding = [container lineFragmentPadding];
		CGFloat containerWidth = [container containerSize].width;
		CTLineRef line = [self cg_createLineForRange:NSMakeRange(0, n) font:font];

		[[_fragments objectAtIndex:0] addObject:
			[FNFragment fragmentWithRange:NSMakeRange(0, n) glyphRange:NSMakeRange(0, n)
				rect:NSMakeRect(0.0, 0.0, containerWidth, baseLineHeight)
				usedRect:NSMakeRect(padding, 0.0, containerWidth - 2.0 * padding, baseLineHeight)
				baseline:baseAscent line:line boxes:nil]];
		if (s != NULL) {
			CFRelease(s);
		}
		_invalidatedRange = NSMakeRange(NSNotFound, 0);
		return;
	}
	start = 0;
	for (i = 0; i < [_textContainers count] && start < (CFIndex)n; i++) {
		NSTextContainer *container = [_textContainers objectAtIndex:i];
		NSMutableArray *fragments = [_fragments objectAtIndex:i];
		CGFloat padding = [container lineFragmentPadding];
		CGFloat containerWidth = [container containerSize].width;
		CGFloat containerHeight = [container containerSize].height;
		/* **AND WHETHER ITS REGION IS THE CHEAP RECTANGLE OR A SHAPE THE CONTAINER MUST ANSWER FOR.** Apple's own
		 * door says the answer is what a layout manager uses to decide whether it may take the cheap route, so a
		 * simple container keeps the arithmetic this class has always used — including its convention that a ZERO
		 * HEIGHT is unbounded, which a scrolling text view's container carries — and a shaped one is ASKED. */
		BOOL simpleContainer = [container isSimpleRectangularTextContainer];
		CGFloat y = 0.0;

		while (start < (CFIndex)n) {
			/* **A TABLE IS A SECOND LAYOUT MODE, AND IT IS ASKED FIRST.** A paragraph whose style carries a
			 * `NSTextTableBlock` is a CELL, and the whole table — every cell's paragraphs — lays out as one grid that
			 * APPENDS its own fragments and advances `start` past the table. A paragraph without a cell falls through to
			 * the ordinary one-line-at-a-time flow below, which is what every document that is not a table uses. */
			if ([self cg_cellAtParagraphStart:(NSUInteger)start] != nil) {
				NSTextTable *tableInProgress = [[self cg_cellAtParagraphStart:(NSUInteger)start] table];

				start = (CFIndex)[self cg_layOutTableStartingAt:(NSUInteger)start typesetter:ts
					attributedString:s font:font
					baseAscent:baseAscent baseLineHeight:baseLineHeight fragments:fragments
					container:container y:&y glyphBase:&glyphBase];
				previousStyle = [self cg_paragraphStyleAt:(start > 0) ? (NSUInteger)(start - 1) : 0];
				firstFragment = NO;
				lastContainer = i;
				lastY = y;
				lastAscent = baseAscent;
				lastLineHeight = baseLineHeight;
				/* **AND A TABLE THAT DID NOT FINISH GOES ON IN THE NEXT CONTAINER**: `start` is still a cell of the
				 * SAME table, so this container is done and the outer loop advances. */
				if (start < (CFIndex)n && [self cg_cellAtParagraphStart:(NSUInteger)start] != nil
				    && [[self cg_cellAtParagraphStart:(NSUInteger)start] table] == tableInProgress) {
					break;
				}
				continue;
			}
			/* **THE PARAGRAPH'S OWN GEOMETRY, READ AT THE PARAGRAPH'S START.** A nil style answers zero for every
			 * scalar and `NSLeftTextAlignment` for the alignment, which IS the default style, so a store with no style
			 * takes the same path as one set in `+defaultParagraphStyle`. */
			NSParagraphStyle *style = [self cg_paragraphStyleAt:(NSUInteger)start];
			BOOL paragraphStart = (start == 0) || ([string characterAtIndex:(NSUInteger)start - 1] == '\n');
			CGFloat indent = paragraphStart ? [style firstLineHeadIndent] : [style headIndent];
			CGFloat tailIndent = [style tailIndent];
			CGFloat multiple = [style lineHeightMultiple];
			CGFloat lineHeight;
			CGFloat lineAscent;
			CGFloat leading;
			NSRect proposed;
			NSRect part;
			NSRect remaining = NSZeroRect;
			BOOL firstPart = YES;

			if (multiple <= 0.0) {
				multiple = 1.0;
			}
			lineHeight = baseLineHeight * multiple;
			if ([style minimumLineHeight] > 0.0 && lineHeight < [style minimumLineHeight]) {
				lineHeight = [style minimumLineHeight];
			}
			if ([style maximumLineHeight] > 0.0 && lineHeight > [style maximumLineHeight]) {
				lineHeight = [style maximumLineHeight];
			}
			lineAscent = baseAscent * multiple;
			if (lineAscent > lineHeight) {
				lineAscent = lineHeight;
			}
			if (lineAscent < 0.0) {
				lineAscent = 0.0;
			}
			/* **AND THE LEADING IS WHAT SITS ABOVE THIS LINE**: the gap between lines WITHIN a paragraph, or the two
			 * paragraph spacings across a paragraph boundary. A new paragraph takes the PREVIOUS paragraph's
			 * `-paragraphSpacing` plus its own `-paragraphSpacingBefore`; a wrapped line takes the line spacing. */
			if (firstFragment) {
				leading = 0.0;
			} else if (paragraphStart) {
				leading = [previousStyle paragraphSpacing] + [style paragraphSpacingBefore];
			} else {
				leading = [style lineSpacing];
			}

			/* THE CONTAINER'S OWN HEIGHT IS THE OVERFLOW EDGE — but only once it has taken a line, so a container
			 * shorter than one line still gets one rather than looping forever. */
			if (containerHeight > 0.0 && y + leading + lineHeight > containerHeight + 0.001 && [fragments count] > 0) {
				break;
			}
			/* **AND THE REGION THIS LINE MUST FIT: THE CONTAINER ANSWERS FOR A SHAPED ONE.** The proposed band is the
			 * container's whole width at this line's place, and a shaped container returns the FIRST subrect that fits
			 * plus, when its region has a hole or a concavity, the REMAINING subrect after it — which is where the same
			 * line's text continues, at the same baseline. A SIMPLE RECTANGLE takes the band itself, so every document
			 * that existed before this slice lays out byte for byte as it did. */
			proposed = NSMakeRect(0.0, y + leading, containerWidth, lineHeight);
			if (simpleContainer) {
				part = proposed;
			} else {
				part = [container lineFragmentRectForProposedRect:proposed
					sweepDirection:NSLineSweepRight movementDirection:NSLineDoesntMove
					remainingRect:&remaining];
				if (NSIsEmptyRect(part)) {
					/* NO ROOM AT THIS LINE'S PLACE, so the rest of this container's text starts in the next one — the
					 * same outcome the height check above gives a container that has run out of room. */
					break;
				}
			}
			while (start < (CFIndex)n) {
				CGFloat partPadding = padding;
				CGFloat partIndent = firstPart ? indent : 0.0;
				BOOL lastPart = NSIsEmptyRect(remaining);
				CGFloat partTail = lastPart ? tailIndent : 0.0;
				CGFloat leadingEdge = part.origin.x + partPadding + partIndent;
				CGFloat trailingEdge = (partTail >= 0.0)
					? (part.origin.x + part.size.width - partPadding - partTail)
					: (part.origin.x + partPadding - partTail);
				CGFloat width = trailingEdge - leadingEdge;
				CFIndex count;
				CTLineRef line = NULL;
				CGFloat lineWidth = 0.0;
				BOOL hyphenated = NO;
				NSRange range;
				NSUInteger lineGlyphs;

				if (width < 1.0) {
					width = 1.0;
				}
				count = CTTypesetterSuggestLineBreak(ts, start, (double)width);
				if (count <= 0) {
					count = 1;
				}
				if (start + count > (CFIndex)n) {
					count = (CFIndex)n - start;
				}
				range = NSMakeRange((NSUInteger)start, (NSUInteger)count);
				line = [self cg_createLineForRange:range style:style attributedString:s typesetter:ts font:font];
				if (line != NULL) {
					lineWidth = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
					if (lineWidth > width) {
						lineWidth = width;
					}
				}
				/* **THEN THE ZONE IS ASKED, BEFORE THE FRAGMENT IS MADE, because the answer changes the fragment.** The
				 * factor's reading is at `cg_hyphenatedLineForRange:`, including why the test is `lineWidth < factor *
				 * width` and why the default leaves every existing document alone. A hyphenated line REPLACES the
				 * breaker's, and the piece it took from the next word moves `count`, `range` and the width with it. */
				hyphenated = NO;
				if (line != NULL && [style hyphenationFactor] > 0.0f
				    && lineWidth < (CGFloat)[style hyphenationFactor] * width) {
					NSRange extended = range;
					CTLineRef hyphenatedLine = [self cg_hyphenatedLineForRange:&extended style:style
								  attributedString:s typesetter:ts font:font width:width];

					if (hyphenatedLine != NULL) {
						CFRelease(line);
						line = hyphenatedLine;
						range = extended;
						count = (CFIndex)extended.length;
						lineWidth = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
						hyphenated = YES;
					}
				}
				{
					CGFloat textTop = y + leading;
					CGFloat baseline = textTop + lineAscent;
					CGFloat alignOffset = [self cg_alignmentOffsetForLine:line
							alignment:[self cg_alignmentForParagraphAt:(NSUInteger)start] width:width];
					NSArray *boxes = [self cg_boxesForRange:range line:line];
					/* **THE FRAGMENT OCCUPIES THE GLYPHS ITS LINE HAS, WHICH IS THE SHAPER'S COUNT.** Its RECT is the
					 * subrect the container gave (x and width), and two parts of one line share the same y and baseline
					 * because they are one line set in two places. */
					lineGlyphs = (line != NULL) ? (NSUInteger)CTLineGetGlyphCount(line) : 0;
					FNFragment *made = [FNFragment fragmentWithRange:range
						glyphRange:NSMakeRange(glyphBase, lineGlyphs)
						rect:NSMakeRect(part.origin.x, y, part.size.width, leading + lineHeight)
						usedRect:NSMakeRect(leadingEdge + alignOffset, textTop,
								    lineWidth + [self cg_boxExtra:boxes], lineHeight)
						baseline:baseline line:line boxes:boxes];

					made->hyphenated = hyphenated;
					[fragments addObject:made];
					glyphBase += lineGlyphs;
				}
				start += count;
				/* **A HARD BREAK ENDS THE LINE**, so there is no remaining rect to put more of it in. */
				if (range.length > 0
				    && [string characterAtIndex:range.location + range.length - 1] == '\n') {
					break;
				}
				if (NSIsEmptyRect(remaining) || start >= (CFIndex)n) {
					break;
				}
				/* **THE SAME LINE CONTINUES IN THE PART THE SHAPE LEFT**, at the same baseline — and the remaining
				 * rect is ASKED ABOUT TOO, because it may itself hold a later hole. A container that answers the same
				 * subrect again is the one case this stops on, so a malformed region cannot spin the loop. */
				{
					NSRect nextProposed = remaining;
					NSRect next;
					NSRect nextRemaining = NSZeroRect;

					next = [container lineFragmentRectForProposedRect:nextProposed
						sweepDirection:NSLineSweepRight movementDirection:NSLineDoesntMove
						remainingRect:&nextRemaining];
					if (NSIsEmptyRect(next) || NSEqualRects(next, part)) {
						break;
					}
					part = next;
					remaining = nextRemaining;
					firstPart = NO;
				}
			}
			y = y + leading + lineHeight;
			previousStyle = style;
			lastContainer = i;
			lastY = y;
			lastAscent = lineAscent;
			lastLineHeight = lineHeight;
			firstFragment = NO;
		}
	}
	if (s != NULL) {
		CFRelease(s);
	}
	CFRelease(ts);
	/* **AND A TRAILING NEWLINE OWES AN EMPTY LAST FRAGMENT IN THE CONTAINER THE TEXT ENDED IN.** */
	if (start >= (CFIndex)n && [string characterAtIndex:n - 1] == '\n') {
		NSTextContainer *container = [_textContainers objectAtIndex:lastContainer];

		[[_fragments objectAtIndex:lastContainer] addObject:
			[FNFragment fragmentWithRange:NSMakeRange(n, 0) glyphRange:NSMakeRange(glyphBase, 0)
				rect:NSMakeRect(0.0, lastY, [container containerSize].width, lastLineHeight)
				usedRect:NSMakeRect([container lineFragmentPadding], lastY, 0.0, lastLineHeight)
				baseline:(lastY + lastAscent) line:NULL boxes:nil]];
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
		/* **AND THE RANGE IT REPORTS IS A GLYPH RANGE**, which is what the caller asked for and what the door's own
		 * name promises. It used to report the fragment's CHARACTER range, which was the same numbers only while a
		 * glyph was a character. */
		*effectiveGlyphRange = found->glyphs;
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

	if (fragment == nil) {
		return 0.0;
	}
	return [self cg_xInFragment:fragment forCharacterIndex:glyphIndex];
}

/* **AND THE INVERSE: THE GLYPH NEAREST A POINT**, which is what a click asks. The FRAGMENT is chosen by WALKING the
 * fragments' own flow bands — the line heights are the paragraph style's, so a division by one height would be wrong the
 * moment a style set `-lineSpacing` or `-minimumLineHeight` — and only the x is Core Text's. A point past the last band
 * clamps to the last fragment, and one before the first to the first. */
- (NSUInteger)cg_glyphIndexForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container
{
	NSUInteger containerIndex = [_textContainers indexOfObjectIdenticalTo:container];
	NSMutableArray *fragments;
	FNFragment *fragment = nil;
	CFIndex index = 0;
	NSUInteger i;

	if (containerIndex == NSNotFound) {
		return NSNotFound;
	}
	[self cg_ensureLayout];
	fragments = [_fragments objectAtIndex:containerIndex];
	if ([fragments count] == 0) {
		return 0;
	}
	/* **A LINE CAN NOW BE SET IN MORE THAN ONE PLACE**, so the y band alone is not enough: among the fragments whose
	 * band contains the point, the one whose SUBRECT also contains its x wins, and a point in a gap chooses the
	 * nearest part. With a simple rectangular container every fragment is the full width, so this is the same answer
	 * the y-only walk gave. */
	{
		FNFragment *band = nil;
		CGFloat bestDistance = 0.0;

		for (i = 0; i < [fragments count]; i++) {
			FNFragment *candidate = [fragments objectAtIndex:i];
			BOOL inBand = (point.y >= candidate->rect.origin.y
				       && point.y <= candidate->rect.origin.y + candidate->rect.size.height);

			if (fragment == nil) {
				fragment = candidate;
			}
			if (inBand) {
				CGFloat distance = 0.0;

				if (point.x < candidate->rect.origin.x) {
					distance = candidate->rect.origin.x - point.x;
				} else if (point.x > candidate->rect.origin.x + candidate->rect.size.width) {
					distance = point.x - (candidate->rect.origin.x + candidate->rect.size.width);
				}
				if (band == nil || distance < bestDistance) {
					band = candidate;
					bestDistance = distance;
				}
				if (distance == 0.0) {
					break;
				}
			}
			if (point.y > candidate->rect.origin.y) {
				fragment = candidate;
			}
		}
		if (band != nil) {
			fragment = band;
		}
	}
	/* **AND A BOX IS HIT BY ITS OWN FACE, NOT BY THE PLACEHOLDER GLYPH's OFFSET.** The point's x is walked past the
	 * boxes in order: inside one answers that box's character, and past it the x loses the box's extra so the engine can
	 * answer for the glyphs beyond. */
	{
		CGFloat localX = point.x - fragment->used.origin.x;
		CGFloat extraBefore = 0.0;
		NSUInteger b;

		for (b = 0; b < [fragment->boxes count]; b++) {
			FNBox *box = [fragment->boxes objectAtIndex:b];
			CGFloat rel = (CGFloat)(box->index - fragment->range.location);
			CGFloat boxX = (fragment->line != NULL)
				? (CGFloat)CTLineGetOffsetForStringIndex(fragment->line, (CFIndex)rel, NULL) : 0.0;

			if (localX >= boxX + extraBefore && localX < boxX + extraBefore + box->width) {
				return box->index;
			}
			if (boxX + extraBefore + box->width <= localX) {
				extraBefore += box->width - box->engineAdvance;
			}
		}
		localX -= extraBefore;
		if (fragment->line != NULL) {
			index = CTLineGetStringIndexForPosition(fragment->line, CGPointMake(localX, 0.0));
		}
	}
	if (index < 0) {
		index = 0;
	}
	if ((NSUInteger)index > fragment->range.length) {
		index = (CFIndex)fragment->range.length;
	}
	return fragment->range.location + (NSUInteger)index;
}

/* **AND THE BASELINE A GLYPH SITS ON, WHICH IS PER-FRAGMENT NOW.** The view needs it for the caret and the composition
 * rule, and with a paragraph style's line spacing and line-height clamps there is no single baseline arithmetic — each
 * fragment recorded its own when it was laid out. */
- (CGFloat)cg_baselineForGlyphAtIndex:(NSUInteger)glyphIndex
{
	FNFragment *fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:NULL];

	return (fragment != nil) ? fragment->baseline : 0.0;
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
	NSUInteger i, j, rangeEnd;

	if (cg == NULL || [_textStorage length] == 0) {
		return;
	}
	[self cg_ensureLayout];
	font = [self cg_font];
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
			baselineY = origin.y + fragment->baseline;
			/* THE GLYPHS, RUN BY RUN. */
			pos = drawn.location;
			while (pos < drawn.location + drawn.length) {
				NSRange runRange;
				NSDictionary *attrs = [self cg_drawingAttributesAtIndex:pos longestEffectiveRange:&runRange
										inRange:drawn];
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
				/* **AND AN ATTACHMENT IS DRAWN WHERE ITS BOX IS, INSTEAD OF THE GLYPHS.** The run carries
				 * `NSAttachmentAttributeName`, so the manager asks the attachment's cell for its size and calls
				 * `-drawWithFrame:inView:` at the character's own SHIFTED x with the frame ABOVE the baseline; the glyphs of that
				 * run are skipped because the picture stands in their place. THE FRAME IS IN THE CONTAINER's y-DOWN SPACE, so
				 * "above the baseline" is the smaller y. AND THE BOX's WIDTH IS RESERVED — `cg_boxesForRange:` recorded it and
				 * every x after it is shifted by the difference — so the text flows around the picture. */
				if ([attrs objectForKey:NSAttachmentAttributeName] != nil) {
					NSTextAttachment *attachment = [attrs objectForKey:NSAttachmentAttributeName];
					NSCell<NSTextAttachmentCell> *cell = [attachment attachmentCell];
					/* **THE SAME SIZE THE BOX RESERVED, NOT THE CELL'S AGAIN.** An overridden attachment would
					 * otherwise reserve one width and paint at another, which is a picture over its neighbours. */
					NSSize size = [self cg_attachmentSizeForCharacterIndex:pos
							 fallback:((cell != nil) ? [cell cellSize] : NSZeroSize)];

					if (cell != nil && size.width > 0.0 && size.height > 0.0) {
						CGFloat x = origin.x + [self cg_xInFragment:fragment forCharacterIndex:pos];
						NSRect frame = NSMakeRect(x, baselineY - size.height, size.width, size.height);
						NSView *view = (i < [_textContainers count])
							? (NSView *)[[_textContainers objectAtIndex:i] textView] : nil;

						[cell drawWithFrame:frame inView:view];
					}
					pos = runEnd;
					continue;
				}
				[(colour != nil) ? colour : [NSColor controlTextColor] setFill];
				/* **AND THE CONTEXT IS MIRRORED ABOUT THE BASELINE, WHICH IS WHAT A FLIPPED CONTAINER NEEDS.** The fragments
				 * are y-DOWN — a container's coordinates are a text view's — and Core Text's own run UP from the baseline. THE x IS
				 * SHIFTED BY EVERY BOX BEFORE THIS RUN, which is what keeps text after an attachment off its face. */
				CGContextSaveGState(cg);
				CGContextTranslateCTM(cg, origin.x + fragment->used.origin.x
					+ [self cg_boxExtraBeforeIndex:pos inFragment:fragment], baselineY);
				CGContextScaleCTM(cg, 1.0, -1.0);
				CGContextSetTextPosition(cg, 0.0, 0.0);
				if (runs != NULL && CFArrayGetCount(runs) > 0 && a < b) {
					CTRunDraw((CTRunRef)CFArrayGetValueAtIndex(runs, 0), cg, CFRangeMake(a, b - a));
				}
				CGContextRestoreGState(cg);
				pos = runEnd;
			}
			/* **AND A HYPHENATED FRAGMENT'S HYPHEN IS DRAWN HERE, BECAUSE THE WALK ABOVE CANNOT REACH IT.** That walk
			 * draws each attribute run over the fragment's CHARACTERS, and the hyphen is the one glyph the line has that
			 * no character owns — so it is drawn on its own, as the LAST glyph of the line's last run, at the position the
			 * line gave it. **IT IS DRAWN RATHER THAN ASSUMED**: the fragment reserved room for it out of the line's own
			 * advance, and a hyphen reserved and not painted is a line with a gap in it that reads as a kerning bug. The
			 * colour comes from the character before it, which is the character whose attributes the hyphen was built
			 * with, and the x carries every box that precedes it so a hyphen after an attachment lands in the right
			 * place. MEASURED by `tests/text_hyphenation.m`, which renders this line and the same layout with the
			 * hyphen's ink withheld: the reserved edge moves by the hyphen's own width. */
			if (fragment->hyphenated && fragment->line != NULL) {
				CFArrayRef hyphenRuns = CTLineGetGlyphRuns(fragment->line);
				CFIndex runCount = (hyphenRuns != NULL) ? CFArrayGetCount(hyphenRuns) : 0;

				if (runCount > 0) {
					CTRunRef last = (CTRunRef)CFArrayGetValueAtIndex(hyphenRuns, runCount - 1);
					CFIndex glyphCount = CTRunGetGlyphCount(last);
					/* **THE HYPHEN IS INK TOO, SO IT READS THE MERGED TABLE.** A temporary attribute over the
					 * character the hyphen was built with would otherwise paint the word in red and its hyphen in the
					 * store's colour — the one place the drawing pass would still be reading the store alone. */
					NSDictionary *endAttrs = [self cg_drawingAttributesAtIndex:
						(fragment->range.location + fragment->range.length - 1)
						longestEffectiveRange:NULL inRange:fragment->range];
					NSColor *endColour = [endAttrs objectForKey:NSForegroundColorAttributeName];
					NSUInteger end = fragment->range.location + fragment->range.length;

					if (glyphCount > 0) {
						[(endColour != nil) ? endColour : [NSColor controlTextColor] setFill];
						CGContextSaveGState(cg);
						CGContextTranslateCTM(cg, origin.x + fragment->used.origin.x
							+ [self cg_boxExtraBeforeIndex:end inFragment:fragment], baselineY);
						CGContextScaleCTM(cg, 1.0, -1.0);
						CGContextSetTextPosition(cg, 0.0, 0.0);
						CTRunDraw(last, cg, CFRangeMake(glyphCount - 1, 1));
						CGContextRestoreGState(cg);
					}
				}
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
		x0 = origin.x + [self cg_xInFragment:fragment forCharacterIndex:pos];
		x1 = origin.x + [self cg_xInFragment:fragment forCharacterIndex:runEnd];
		(void)a;
		(void)b;
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
	NSUInteger i, j, rangeEnd;

	if (cg == NULL || [_textStorage length] == 0) {
		return;
	}
	[self cg_ensureLayout];
	/* **THE BLOCKS FIRST, BECAUSE A BOX IS BEHIND EVERY RUN BACKGROUND AND THE RUN WALK IS BEHIND THE GLYPHS.** */
	[self cg_drawBlocksForGlyphRange:glyphsToShow atPoint:origin];
	string = [_textStorage string];
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
				NSDictionary *attrs = [self cg_drawingAttributesAtIndex:pos longestEffectiveRange:&runRange
						       inRange:NSMakeRange(fragment->range.location,
									   end - fragment->range.location)];
				NSColor *background = [attrs objectForKey:NSBackgroundColorAttributeName];
				NSUInteger runEnd = runRange.location + runRange.length;

				if (runEnd > end) {
					runEnd = end;
				}
				if (runEnd <= pos) {
					runEnd = pos + 1;
				}
				if (background != nil) {
					CGFloat x0 = origin.x + [self cg_xInFragment:fragment forCharacterIndex:pos];
					CGFloat x1 = origin.x + [self cg_xInFragment:fragment forCharacterIndex:runEnd];

					[background setFill];
					CGContextFillRect(cg, CGRectMake(x0, origin.y + fragment->used.origin.y, x1 - x0,
									 fragment->used.size.height));
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


/* ==================================================================================================================
 * THE FRAGMENT QUERIES.
 *
 * See the header for what these can and cannot answer: they are arithmetic over the fragments the manager already
 * keeps, and the two glyph-to-character doors are deliberately absent because they would need the shaper's cluster
 * table. **A RESULT FROM A DOOR THAT CANNOT BE SURE IS WORSE THAN NO DOOR**, which is the same rule the depth
 * vocabulary states — "-1/nil answers for a depth that is not one of the three" — applied to an index.
 * ================================================================================================================ */

@implementation NSLayoutManager (AGFragmentQueries)

- (BOOL)isValidGlyphIndex:(NSUInteger)glyphIndex
{
	[self cg_ensureLayout];
	return glyphIndex < [self numberOfGlyphs] ? YES : NO;
}

- (NSUInteger)firstUnlaidCharacterIndex
{
	[self cg_ensureLayout];
	return [[self textStorage] length];
}

- (NSUInteger)firstUnlaidGlyphIndex
{
	[self cg_ensureLayout];
	return [self numberOfGlyphs];
}

/* The glyph range a whole container carries, taken from its fragments rather than from the store: the union runs from
 * the first fragment's start to the last one's end, which is what "the range this container holds" means. */
- (NSRange)ag_glyphRangeForContainer:(NSTextContainer *)container
{
	NSUInteger count = [self cg_lineFragmentCountForTextContainer:container];
	NSRange first, last;

	if (count == 0) {
		return NSMakeRange(NSNotFound, 0);
	}
	first = [self cg_lineFragmentRangeAtIndex:0 inTextContainer:container];
	last = [self cg_lineFragmentRangeAtIndex:count - 1 inTextContainer:container];
	if (first.location == NSNotFound || last.location == NSNotFound) {
		return NSMakeRange(NSNotFound, 0);
	}
	return NSMakeRange(first.location, last.location + last.length - first.location);
}

- (NSTextContainer *)textContainerForGlyphAtIndex:(NSUInteger)glyphIndex
				   effectiveRange:(NSRangePointer)effectiveGlyphRange
{
	NSArray *containers;
	NSUInteger i, count;

	[self cg_ensureLayout];
	containers = [self textContainers];
	count = [containers count];
	for (i = 0; i < count; i++) {
		NSTextContainer *container = [containers objectAtIndex:i];
		NSRange range = [self ag_glyphRangeForContainer:container];

		if (range.location != NSNotFound && glyphIndex >= range.location
		    && glyphIndex < range.location + range.length) {
			if (effectiveGlyphRange != NULL) {
				*effectiveGlyphRange = range;
			}
			return container;
		}
	}
	if (effectiveGlyphRange != NULL) {
		*effectiveGlyphRange = NSMakeRange(NSNotFound, 0);
	}
	return nil;
}

- (NSTextContainer *)textContainerForGlyphAtIndex:(NSUInteger)glyphIndex
				   effectiveRange:(NSRangePointer)effectiveGlyphRange
			    withoutAdditionalLayout:(BOOL)flag
{
	(void)flag;
	return [self textContainerForGlyphAtIndex:glyphIndex effectiveRange:effectiveGlyphRange];
}

- (NSRect)lineFragmentRectForGlyphAtIndex:(NSUInteger)glyphIndex
			  effectiveRange:(NSRangePointer)effectiveGlyphRange
		   withoutAdditionalLayout:(BOOL)flag
{
	(void)flag;
	return [self lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:effectiveGlyphRange];
}

- (NSRect)lineFragmentUsedRectForGlyphAtIndex:(NSUInteger)glyphIndex
			      effectiveRange:(NSRangePointer)effectiveGlyphRange
		       withoutAdditionalLayout:(BOOL)flag
{
	(void)flag;
	return [self lineFragmentUsedRectForGlyphAtIndex:glyphIndex effectiveRange:effectiveGlyphRange];
}

@end


/* ==================================================================================================================
 * THE GLYPH-TO-CHARACTER MAPPING.
 *
 * **`-cg_glyphIndexForPoint:inTextContainer:` IS MISNAMED AND THIS FILE HAS TO SAY SO**: it answers a CHARACTER index —
 * its last line adds `fragment->range.location` to what `CTLineGetStringIndexForPosition` returned, an index into the
 * line's CHARACTERS. The glyph doors below therefore convert, and that conversion is why they are not one-line
 * forwards. Renaming the helper was the alternative and was rejected: it is public in the header and its name is the
 * one the view already calls.
 *
 * **THE FRACTION IS MEASURED BETWEEN INSERTION POINTS**, which is what makes a ligature decide correctly: the two
 * points are the character's own boundaries, so a point inside `fi` answers before-or-after rather than a position
 * inside a glyph that has two characters in it. A zero-width pair — a combining mark, or the last character of a line —
 * answers 0 rather than dividing by zero.
 * ================================================================================================================ */

/* ==================================================================================================================
 * ONE GLYPH'S RECORD — the unit the store is an array of.
 *
 * **IT IS A CLASS RATHER THAN PARALLEL ARRAYS** because the doors address a glyph by index and read four different
 * fields of it; four arrays would be four chances to fall out of step on an insert. The fields are Apple's: the glyph
 * itself, the character it stands for, where it sits inside its line fragment, the two flags a typesetter sets, and a
 * tag-keyed integer table.
 * ================================================================================================================ */
@interface FNGlyph : NSObject
{
@public
	NSGlyph glyph;
	NSUInteger characterIndex;
	NSPoint location;
	BOOL notShown;
	BOOL drawsOutside;
	NSMutableDictionary *attributes;
}
@end

@implementation FNGlyph
- (void)dealloc
{
	[attributes release];
	[super dealloc];
}
@end

@implementation NSLayoutManager (AGGlyphMapping)

- (NSUInteger)characterIndexForGlyphAtIndex:(NSUInteger)glyphIndex
{
	FNFragment *fragment;
	NSUInteger local;

	/* **THE RANGE IS CHECKED BEFORE THE FRAGMENT IS ASKED FOR.** `-cg_fragmentForGlyphAtIndex:` matches its fragment
	 * INCLUSIVELY at the end, because a range boundary is a legitimate place for its own callers to ask about — so one
	 * past the last glyph found the final fragment and came back with an index instead of the NSNotFound this door
	 * promises. The guard is here rather than in the helper because the helper's other callers rely on that boundary. */
	if (glyphIndex >= [self numberOfGlyphs]) {
		return NSNotFound;
	}
	/* THE STORE ANSWERS FIRST, because a caller may have MOVED this glyph's character with `-setCharacterIndex:`. The
	 * shaper is the fallback for a fragment with no line, where there are no glyphs to copy. */
	[self cg_syncGlyphStore];
	if (glyphIndex < [_glyphStore count]) {
		return ((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->characterIndex;
	}
	fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:NULL];
	if (fragment == nil) {
		return NSNotFound;
	}
	if (fragment->line == NULL || glyphIndex >= fragment->glyphs.location + fragment->glyphs.length) {
		/* Past the shaper's last glyph: the tail of a line is one glyph per character, so the arithmetic answer is
		 * the right one there and asking the shaper would read past its table. */
		return fragment->range.location + (glyphIndex - fragment->glyphs.location);
	}
	local = fn_characterForGlyphOffsetInLine(fragment->line, glyphIndex - fragment->glyphs.location);
	return fragment->range.location + local;
}

- (NSUInteger)glyphIndexForCharacterAtIndex:(NSUInteger)charIndex
{
	NSRange glyphs;

	if (charIndex >= [[self textStorage] length]) {
		return NSNotFound;
	}
	glyphs = [self glyphRangeForCharacterRange:NSMakeRange(charIndex, 1) actualCharacterRange:NULL];
	return glyphs.location;
}

- (NSPoint)locationForGlyphAtIndex:(NSUInteger)glyphIndex
{
	FNFragment *fragment;
	NSUInteger charIndex;
	CGFloat x;

	if (glyphIndex >= [self numberOfGlyphs]) {
		return NSZeroPoint;
	}
	/* The store first, for the same reason: `-setLocation:forStartOfGlyphRange:` writes there. */
	[self cg_syncGlyphStore];
	if (glyphIndex < [_glyphStore count]) {
		return ((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->location;
	}
	fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:NULL];
	if (fragment == nil) {
		return NSZeroPoint;
	}
	charIndex = [self characterIndexForGlyphAtIndex:glyphIndex];
	if (charIndex == NSNotFound) {
		return NSZeroPoint;
	}
	x = [self cg_xInFragment:fragment forCharacterIndex:charIndex] - fragment->rect.origin.x;
	return NSMakePoint(x, fragment->baseline - fragment->rect.origin.y);
}

/* How far between two insertion points a point fell, clamped to [0,1], zero when the pair has no width. */
static CGFloat fn_fraction_between(FNFragment *fragment, CGFloat localX, NSUInteger fromCharacter, NSUInteger toCharacter)
{
	CGFloat a, b, span, fraction;

	if (fragment == NULL || fragment->line == NULL) {
		return 0.0;
	}
	a = (CGFloat)CTLineGetOffsetForStringIndex(fragment->line,
		(CFIndex)(fromCharacter - fragment->range.location), NULL);
	b = (CGFloat)CTLineGetOffsetForStringIndex(fragment->line,
		(CFIndex)(toCharacter - fragment->range.location), NULL);
	span = b - a;
	if (span <= 0.0) {
		return 0.0;
	}
	fraction = (localX - a) / span;
	if (fraction < 0.0) {
		return 0.0;
	}
	return (fraction > 1.0) ? 1.0 : fraction;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
		     inTextContainer:(NSTextContainer *)container
     fractionOfDistanceBetweenInsertionPoints:(CGFloat *)partialFraction
{
	NSUInteger charIndex = [self cg_glyphIndexForPoint:point inTextContainer:container];
	NSUInteger glyphIndex;
	FNFragment *fragment;
	NSUInteger length;

	if (partialFraction != NULL) {
		*partialFraction = 0.0;
	}
	if (charIndex == NSNotFound || partialFraction == NULL) {
		return charIndex;
	}
	glyphIndex = [self glyphIndexForCharacterAtIndex:charIndex];
	fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:NULL];
	length = [[self textStorage] length];
	if (fragment != NULL && charIndex < length
	    && charIndex + 1 <= fragment->range.location + fragment->range.length) {
		*partialFraction = fn_fraction_between(fragment, point.x - fragment->used.origin.x,
						       charIndex, charIndex + 1);
	}
	return charIndex;
}

- (NSUInteger)glyphIndexForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container
{
	NSUInteger charIndex = [self cg_glyphIndexForPoint:point inTextContainer:container];

	if (charIndex == NSNotFound) {
		return NSNotFound;
	}
	return [self glyphIndexForCharacterAtIndex:charIndex];
}

- (NSUInteger)glyphIndexForPoint:(NSPoint)point
		 inTextContainer:(NSTextContainer *)container
     fractionOfDistanceThroughGlyph:(CGFloat *)partialFraction
{
	NSUInteger glyphIndex = [self glyphIndexForPoint:point inTextContainer:container];

	if (partialFraction != NULL) {
		*partialFraction = [self fractionOfDistanceThroughGlyphForPoint:point inTextContainer:container];
	}
	return glyphIndex;
}

- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container
{
	NSUInteger charIndex = [self cg_glyphIndexForPoint:point inTextContainer:container];
	NSUInteger glyphIndex, nextCharacter, length;
	FNFragment *fragment;

	if (charIndex == NSNotFound) {
		return 0.0;
	}
	glyphIndex = [self glyphIndexForCharacterAtIndex:charIndex];
	fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:NULL];
	if (fragment == NULL || fragment->line == NULL) {
		return 0.0;
	}
	length = [[self textStorage] length];
	nextCharacter = charIndex + 1;
	if (nextCharacter > length) {
		nextCharacter = length;
	}
	return fn_fraction_between(fragment, point.x - fragment->used.origin.x, charIndex, nextCharacter);
}

@end


/* ==================================================================================================================
 * THE GLYPH STORE.
 *
 * See the header for why this is a SHADOW of the layout rather than its source, and why the three count-changing doors
 * refuse: adding or removing a glyph makes the text and the store disagree about how many there are, and the next
 * re-layout would silently undo the edit. Everything that changes a FIELD of a glyph is real here, because a field is
 * something the fragments do not own.
 *
 * **THE REBUILD READS THE SHAPER DIRECTLY** — `CTRunGetGlyphs`, `CTRunGetStringIndices`, `CTRunGetPositions` — rather
 * than going through this class's own query doors, which now read the store. That is what keeps the build and the
 * queries from depending on each other, and it is why a fragment with no `CTLine` (an empty line, or a paragraph break)
 * contributes records with a placeholder glyph rather than none: the glyph count has to stay the character count or
 * every index after the break shifts.
 * ================================================================================================================ */

@implementation NSLayoutManager (AGGlyphStore)

- (void)cg_syncGlyphStore
{
	if (_glyphStore == nil || _glyphStoreStale || _invalidatedRange.location != NSNotFound) {
		[self cg_rebuildGlyphStore];
	}
}

- (void)cg_rebuildGlyphStore
{
	NSUInteger c, f;

	[self cg_ensureLayout];
	if (_glyphStore == nil) {
		_glyphStore = [[NSMutableArray alloc] init];
	}
	[_glyphStore removeAllObjects];
	_glyphStoreStale = NO;
	for (c = 0; c < [_fragments count]; c++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:c];

		for (f = 0; f < [fragments count]; f++) {
			FNFragment *fragment = [fragments objectAtIndex:f];
			CFArrayRef runs;
			CFIndex r, runCount;

			if (fragment->line == NULL) {
				NSUInteger k;

				for (k = 0; k < fragment->range.length; k++) {
					FNGlyph *record = [[[FNGlyph alloc] init] autorelease];

					record->glyph = (NSGlyph)(fragment->range.location + k);
					record->characterIndex = fragment->range.location + k;
					record->location = NSMakePoint(fragment->used.origin.x - fragment->rect.origin.x,
								       fragment->baseline - fragment->rect.origin.y);
					[_glyphStore addObject:record];
				}
				continue;
			}
			runs = CTLineGetGlyphRuns(fragment->line);
			runCount = (runs != NULL) ? CFArrayGetCount(runs) : 0;
			for (r = 0; r < runCount; r++) {
				CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
				CFIndex glyphs = CTRunGetGlyphCount(run);
				CFIndex k;

				for (k = 0; k < glyphs; k++) {
					CFRange one = CFRangeMake(k, 1);
					CGGlyph shaped = 0;
					CFIndex stringIndex = 0;
					CGPoint position = CGPointZero;
					FNGlyph *record = [[[FNGlyph alloc] init] autorelease];

					CTRunGetGlyphs(run, one, &shaped);
					CTRunGetStringIndices(run, one, &stringIndex);
					CTRunGetPositions(run, one, &position);
					record->glyph = (NSGlyph)shaped;
					record->characterIndex = fragment->range.location + (NSUInteger)stringIndex;
					record->location = NSMakePoint(fragment->used.origin.x + (CGFloat)position.x
								       - fragment->rect.origin.x,
								       fragment->baseline - fragment->rect.origin.y);
					[_glyphStore addObject:record];
				}
			}
			/* A line whose shaped glyphs are FEWER than its characters — a ligature — leaves the tail unrecorded by
			 * the runs, so the shortfall is filled with one record per remaining character. Without this the store
			 * would be shorter than `-numberOfGlyphs` and every index past a ligature would answer for the wrong glyph. */
			{
				NSUInteger recorded = fragment->glyphs.length;
				NSUInteger k;

				for (k = recorded; k < fragment->range.length; k++) {
					FNGlyph *record = [[[FNGlyph alloc] init] autorelease];

					record->glyph = (NSGlyph)(fragment->range.location + k);
					record->characterIndex = fragment->range.location + k;
					record->location = NSMakePoint(fragment->used.origin.x - fragment->rect.origin.x,
								       fragment->baseline - fragment->rect.origin.y);
					[_glyphStore addObject:record];
				}
			}
		}
	}
}

- (NSGlyph)glyphAtIndex:(NSUInteger)glyphIndex
{
	return [self glyphAtIndex:glyphIndex isValidIndex:NULL];
}

- (NSGlyph)glyphAtIndex:(NSUInteger)glyphIndex isValidIndex:(BOOL *)isValidIndex
{
	[self cg_syncGlyphStore];
	if (glyphIndex >= [_glyphStore count]) {
		if (isValidIndex != NULL) {
			*isValidIndex = NO;
		}
		return 0;	/* NSNullGlyph */
	}
	if (isValidIndex != NULL) {
		*isValidIndex = YES;
	}
	return ((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->glyph;
}

- (void)getGlyphs:(NSGlyph *)glyphArray range:(NSRange)glyphRange
{
	NSUInteger i;

	if (glyphArray == NULL) {
		return;
	}
	[self cg_syncGlyphStore];
	for (i = 0; i < glyphRange.length; i++) {
		NSUInteger index = glyphRange.location + i;

		glyphArray[i] = (index < [_glyphStore count])
			? ((FNGlyph *)[_glyphStore objectAtIndex:index])->glyph : 0;
	}
}

- (BOOL)notShownAttributeForGlyphAtIndex:(NSUInteger)glyphIndex
{
	[self cg_syncGlyphStore];
	if (glyphIndex >= [_glyphStore count]) {
		return NO;
	}
	return ((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->notShown;
}

- (void)setNotShownAttribute:(BOOL)flag forGlyphAtIndex:(NSUInteger)glyphIndex
{
	[self cg_syncGlyphStore];
	if (glyphIndex < [_glyphStore count]) {
		((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->notShown = flag ? YES : NO;
	}
}

- (BOOL)drawsOutsideLineFragmentForGlyphAtIndex:(NSUInteger)glyphIndex
{
	[self cg_syncGlyphStore];
	if (glyphIndex >= [_glyphStore count]) {
		return NO;
	}
	return ((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->drawsOutside;
}

- (void)setDrawsOutsideLineFragment:(BOOL)flag forGlyphAtIndex:(NSUInteger)glyphIndex
{
	[self cg_syncGlyphStore];
	if (glyphIndex < [_glyphStore count]) {
		((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->drawsOutside = flag ? YES : NO;
	}
}

- (NSInteger)intAttribute:(NSInteger)attributeTag forGlyphAtIndex:(NSUInteger)glyphIndex
{
	FNGlyph *record;
	NSNumber *value;

	[self cg_syncGlyphStore];
	if (glyphIndex >= [_glyphStore count]) {
		return 0;
	}
	record = [_glyphStore objectAtIndex:glyphIndex];
	value = [record->attributes objectForKey:[NSString stringWithFormat:@"%ld", (long)attributeTag]];
	return value != nil ? (NSInteger)[value longValue] : 0;
}

- (void)setIntAttribute:(NSInteger)attributeTag value:(NSInteger)val forGlyphAtIndex:(NSUInteger)glyphIndex
{
	FNGlyph *record;

	[self cg_syncGlyphStore];
	if (glyphIndex >= [_glyphStore count]) {
		return;
	}
	record = [_glyphStore objectAtIndex:glyphIndex];
	if (record->attributes == nil) {
		record->attributes = [[NSMutableDictionary alloc] init];
	}
	[record->attributes setObject:[NSNumber numberWithLong:(long)val]
			       forKey:[NSString stringWithFormat:@"%ld", (long)attributeTag]];
}

- (void)setLocation:(NSPoint)location forStartOfGlyphRange:(NSRange)glyphRange
{
	[self cg_syncGlyphStore];
	if (glyphRange.location < [_glyphStore count]) {
		((FNGlyph *)[_glyphStore objectAtIndex:glyphRange.location])->location = location;
	}
}

- (void)setCharacterIndex:(NSUInteger)charIndex forGlyphAtIndex:(NSUInteger)glyphIndex
{
	[self cg_syncGlyphStore];
	if (glyphIndex < [_glyphStore count]) {
		((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->characterIndex = charIndex;
	}
}

- (void)replaceGlyphAtIndex:(NSUInteger)glyphIndex withGlyph:(NSGlyph)newGlyph
{
	[self cg_syncGlyphStore];
	if (glyphIndex < [_glyphStore count]) {
		((FNGlyph *)[_glyphStore objectAtIndex:glyphIndex])->glyph = newGlyph;
	}
}

/* THE THREE THAT CHANGE HOW MANY GLYPHS THERE ARE. See the header: the store is a shadow, so an edit to its length
 * would be undone by the next re-layout, and a door that lies about that is worse than one that says why. */
- (void)insertGlyph:(NSGlyph)glyph atGlyphIndex:(NSUInteger)glyphIndex characterIndex:(NSUInteger)characterIndex
{
	(void)glyph; (void)glyphIndex; (void)characterIndex;
	fn_refuse_window("-insertGlyph:atGlyphIndex:characterIndex:",
			 "an authoritative glyph store (this tier's glyphs are shaped from the text, so a glyph the text has "
			 "not got would be discarded by the next layout)");
}

- (void)insertGlyphs:(const NSGlyph *)glyphs length:(NSUInteger)length
	forStartingGlyphAtIndex:(NSUInteger)glyphIndex characterIndex:(NSUInteger)characterIndex
{
	(void)glyphs; (void)length; (void)glyphIndex; (void)characterIndex;
	fn_refuse_window("-insertGlyphs:length:forStartingGlyphAtIndex:characterIndex:",
			 "an authoritative glyph store");
}

- (void)deleteGlyphsInRange:(NSRange)glyphRange
{
	(void)glyphRange;
	fn_refuse_window("-deleteGlyphsInRange:", "an authoritative glyph store");
}

@end


/* ==================================================================================================================
 * THE UNDERLINE DOORS.
 *
 * See the header for the split between deciding and drawing, and for why the ink is the caller's stroke colour. What is
 * NOT obvious from Apple's signatures is where the line goes vertically: `lineFragmentRect` and `containerOrigin` are
 * both in container coordinates and neither carries a baseline, so the baseline is read from the FRAGMENT that holds the
 * glyphs. That is exact rather than approximate — the fragment's `CTLine` already knows where it sits.
 * ================================================================================================================ */

@implementation NSLayoutManager (AGUnderline)

/* The x at which a glyph's character ink starts and ends, in container coordinates. */
- (CGFloat)ag_xForGlyph:(NSUInteger)glyphIndex inFragment:(FNFragment *)fragment
{
	NSUInteger character = [self characterIndexForGlyphAtIndex:glyphIndex];

	if (character == NSNotFound) {
		return fragment->used.origin.x;
	}
	return [self cg_xInFragment:fragment forCharacterIndex:character];
}

- (void)drawUnderlineForGlyphRange:(NSRange)glyphRange
		     underlineType:(NSInteger)underlineVal
		    baselineOffset:(CGFloat)baselineOffset
		  lineFragmentRect:(NSRect)lineRect
	   lineFragmentGlyphRange:(NSRange)lineGlyphRange
		   containerOrigin:(NSPoint)containerOrigin
{
	FNFragment *fragment;
	CGContextRef cg;
	NSGraphicsContext *context;
	CGFloat x0, x1, y, width;
	BOOL dotted, thick, doubled;

	(void)lineRect;
	(void)lineGlyphRange;
	context = [NSGraphicsContext currentContext];
	cg = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;
	if (cg == NULL || glyphRange.length == 0) {
		return;
	}
	fragment = [self cg_fragmentForGlyphAtIndex:glyphRange.location effectiveRange:NULL];
	if (fragment == NULL) {
		return;
	}
	x0 = [self ag_xForGlyph:glyphRange.location inFragment:fragment];
	x1 = [self ag_xForGlyph:glyphRange.location + glyphRange.length inFragment:fragment];
	if (x1 <= x0) {
		return;
	}
	/* **THE LINE SITS BELOW THE BASELINE**, by the requested offset (callers pass a small negative number) and one
	 * point further so it does not touch the descenders. The fragment's baseline is in container coordinates already. */
	y = containerOrigin.y + fragment->baseline + baselineOffset - 1.0;
	width = x1 - x0;

	/* NSUnderlineStyle: 0x01 single, 0x02 thick, 0x09 double, and the pattern in the high byte. */
	thick = (underlineVal & 0x02) ? YES : NO;
	doubled = ((underlineVal & 0x09) == 0x09) ? YES : NO;
	dotted = (underlineVal & 0x0100) ? YES : NO;

	CGContextSaveGState(cg);
	if (dotted) {
		CGFloat dash[2] = {1.0, 2.0};

		CGContextSetLineDash(cg, 0.0, dash, 2);
	}
	CGContextSetLineWidth(cg, thick ? 2.0 : 1.0);
	CGContextBeginPath(cg);
	CGContextMoveToPoint(cg, x0, y);
	CGContextAddLineToPoint(cg, x0 + width, y);
	CGContextStrokePath(cg);
	if (doubled) {
		CGContextBeginPath(cg);
		CGContextMoveToPoint(cg, x0, y - 2.0);
		CGContextAddLineToPoint(cg, x0 + width, y - 2.0);
		CGContextStrokePath(cg);
	}
	CGContextRestoreGState(cg);
}

- (void)underlineGlyphRange:(NSRange)glyphRange
	      underlineType:(NSInteger)underlineVal
	   lineFragmentRect:(NSRect)lineRect
    lineFragmentGlyphRange:(NSRange)lineGlyphRange
	    containerOrigin:(NSPoint)containerOrigin
{
	FNFragment *fragment;
	NSRange trimmed = glyphRange;
	NSUInteger first, last;
	NSString *string;

	if (glyphRange.length == 0) {
		return;
	}
	fragment = [self cg_fragmentForGlyphAtIndex:glyphRange.location effectiveRange:NULL];
	if (fragment == NULL) {
		return;
	}
	/* **THE WHITESPACE IS TRIMMED HERE, WHICH IS THE WHOLE REASON THIS DOOR EXISTS.** A run of underlined text usually
	 * carries the space after it; underlining that space is the "looks like a bug" Apple's own note describes. The trim
	 * is done on CHARACTERS, because that is what whitespace is. */
	string = [[self textStorage] string];
	first = [self characterIndexForGlyphAtIndex:glyphRange.location];
	last = [self characterIndexForGlyphAtIndex:glyphRange.location + glyphRange.length - 1];
	if (first == NSNotFound || last == NSNotFound) {
		return;
	}
	while (first <= last && first < [string length]
	       && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[string characterAtIndex:first]]) {
		first++;
	}
	while (last >= first && last < [string length]
	       && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[string characterAtIndex:last]]) {
		if (last == 0) {
			break;
		}
		last--;
	}
	if (first > last) {
		return;
	}
	trimmed = [self glyphRangeForCharacterRange:NSMakeRange(first, last - first + 1) actualCharacterRange:NULL];
	[self drawUnderlineForGlyphRange:trimmed underlineType:underlineVal baselineOffset:-1.0
		   lineFragmentRect:lineRect lineFragmentGlyphRange:lineGlyphRange
		   containerOrigin:containerOrigin];
}

@end

/* ==================================================================================================================
 * THE RULER'S TWO DOORS.
 *
 * The four tab images are made once, on first use, by drawing into a 9x8 image: a stem and a foot, with the foot on the
 * side the alignment points and, for a decimal tab, a dot where the point lands. They are hand-drawn rather than loaded
 * because this tier has no artwork for them and a missing image would make a marker zero-thickness and invisible —
 * which is exactly the failure a tab-stop ruler must not have. The images are y-down (the ruler is flipped), so a foot
 * at the bottom of the image is the end nearest the text.
 * ================================================================================================================ */

@interface NSLayoutManager (AGRuler)
@end

static NSImage *sTabMarkerImages[4];

static void fn_fill_image_rect(CGFloat x, CGFloat y, CGFloat w, CGFloat h)
{
	[[NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)] fill];
}

static NSImage *fn_tab_marker_image(NSTextTabType type)
{
	NSUInteger slot = ((NSUInteger)type < 4) ? (NSUInteger)type : (NSUInteger)NSLeftTabStopType;
	NSImage *image = sTabMarkerImages[slot];

	if (image != nil) {
		return image;
	}
	image = [[NSImage alloc] initWithSize:NSMakeSize(9.0, 8.0)];
	[image lockFocusFlipped:YES];
	[[NSColor blackColor] setFill];
	/* THE STEM, WHICH EVERY KIND HAS: the two middle columns, top to bottom. */
	fn_fill_image_rect(4.0, 0.0, 1.0, 8.0);
	switch (slot) {
	case NSRightTabStopType:
		fn_fill_image_rect(0.0, 6.0, 5.0, 1.0);
		break;
	case NSCenterTabStopType:
		fn_fill_image_rect(1.0, 6.0, 7.0, 1.0);
		break;
	case NSDecimalTabStopType:
		fn_fill_image_rect(4.0, 5.0, 2.0, 2.0);
		break;
	case NSLeftTabStopType:
	default:
		fn_fill_image_rect(4.0, 6.0, 5.0, 1.0);
		break;
	}
	[image unlockFocus];
	sTabMarkerImages[slot] = image;
	return image;
}

@implementation NSLayoutManager (AGRuler)

- (NSArray *)rulerMarkersForTextView:(NSTextView *)aTextView
		      paragraphStyle:(NSParagraphStyle *)style
			       ruler:(NSRulerView *)aRulerView
{
	NSMutableArray *markers = [NSMutableArray array];
	NSArray *stops = (style != nil) ? [style tabStops] : nil;
	CGFloat offset = (aRulerView != nil) ? [aRulerView originOffset] : 0.0;
	NSUInteger i;

	(void)aTextView;
	for (i = 0; i < [stops count]; i++) {
		NSTextTab *tab = [stops objectAtIndex:i];
		NSRulerMarker *marker = [[NSRulerMarker alloc] initWithRulerView:aRulerView
									 markerLocation:offset + [tab location]
										  image:fn_tab_marker_image([tab tabStopType])
								    imageOrigin:NSZeroPoint];

		/* **THE TAB TRAVELS WITH THE MARKER**, which is what lets a drag end as a changed paragraph: the client view
		 * rebuilds the paragraph's tab list from the markers and reads each one's kind back out of this. */
		[marker setRepresentedObject:tab];
		[markers addObject:marker];
		[marker release];
	}
	return markers;
}

/* THE DOCUMENTED REFUSAL. See this header's comment: nil is the empty value of `NSView *`, and the accessory strip is a
 * control cluster this tier has not built. Saying so on stderr is the difference between a gap and a stub. */
- (NSView *)rulerAccessoryViewForTextView:(NSTextView *)aTextView
			    paragraphStyle:(NSParagraphStyle *)style
				      ruler:(NSRulerView *)aRulerView
				    enabled:(BOOL)isEnabled
{
	/* **SAID ONCE PER PROCESS, BECAUSE THIS DOOR IS ASKED ON EVERY RULER UPDATE.** A refusal that printed on every caret
	 * move would be noise rather than information, and the fact does not change between them; the other refusals in this
	 * tree are per-call because they are per-call DOORS. */
	static BOOL said = NO;

	(void)aTextView;
	(void)style;
	(void)aRulerView;
	(void)isEnabled;
	if (!said) {
		said = YES;
		fn_refuse_window("NSLayoutManager -rulerAccessoryViewForTextView:paragraphStyle:ruler:enabled:",
				 "the tab-type control cluster Apple's text system puts in the ruler's accessory band; the ruler "
				 "reserves nothing for it and the markers are still draggable");
	}
	return nil;
}

@end

/* ==================================================================================================================
 * THE BLOCK RECTANGLES AND THE ATTACHMENT'S SIZE — the doors declared in the header's last section.
 *
 * Three helpers do all the work: the OVERRIDE LOOKUP (a caller's rect wins), the GROUP (the union of the fragments that
 * share a block, which container they are in, and the range they span), and the two frames the group produces — the
 * block's own drawn frame from `-cg_frameForBlock:`, and the text band the glyphs occupy. The public doors are two
 * spellings of each, by range and by one glyph, and Apple's `atIndex:` pair is glyph-indexed, so its effective range
 * comes back in GLYPHS.
 *
 * **A TABLE CELL'S BOUNDS ARE MEASURED FROM ITS FLOW BAND, NOT ITS TEXT**, because that is what the drawing pass does
 * (`-cg_addCell:` unions `fragment->rect`) and a bounds rect that disagreed with the drawn border would be a door that
 * answers a rectangle nobody painted. The LAYOUT rect is the text band for every kind of block: it is where the glyphs
 * are, which is the whole of what its name promises.
 * ================================================================================================================ */

@interface NSLayoutManager (AGBlockRects)
@end

@implementation NSLayoutManager (AGBlockRects)

/* THE OVERRIDE, OR NIL. Linear for the same reason the cell grid's search is: a document has few blocks, and a dictionary
 * keyed by a borrowed pointer buys nothing but a lifetime argument. */
- (FNBlockRect *)cg_overrideEntryForBlock:(NSTextBlock *)block create:(BOOL)create
{
	NSUInteger i;

	for (i = 0; i < [_blockRectOverrides count]; i++) {
		FNBlockRect *entry = [_blockRectOverrides objectAtIndex:i];

		if (entry->block == block) {
			return entry;
		}
	}
	if (!create || block == nil) {
		return nil;
	}
	{
		FNBlockRect *entry = [[[FNBlockRect alloc] init] autorelease];

		entry->block = block;
		entry->bounds = NSZeroRect;
		entry->layout = NSZeroRect;
		entry->hasBounds = NO;
		entry->hasLayout = NO;
		[_blockRectOverrides addObject:entry];
		return entry;
	}
}

/* THE BLOCK'S GROUP: the union of its fragments' bands, the glyph range they span, and the container the FIRST of them
 * is in. `flow` chooses the band: YES is the fragment's whole flow rect (a table cell's own box) and NO its used rect
 * (where the glyphs are). A block with no fragments answers NO — it is not in the layout. */
- (BOOL)cg_blockGroup:(NSTextBlock *)block content:(NSRect *)contentPtr range:(NSRange *)rangePtr
	 container:(NSUInteger *)containerPtr flow:(BOOL)flow
{
	BOOL found = NO;
	NSUInteger i, j;

	if (block == nil) {
		return NO;
	}
	[self cg_ensureLayout];
	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *fragment = [fragments objectAtIndex:j];

			if ([self cg_blockForFragment:fragment] != block) {
				continue;
			}
			if (!found) {
				*contentPtr = flow ? fragment->rect : fragment->used;
				*rangePtr = fragment->glyphs;
				if (containerPtr != NULL) {
					*containerPtr = i;
				}
				found = YES;
			} else {
				NSRect band = flow ? fragment->rect : fragment->used;
				NSUInteger end = fragment->glyphs.location + fragment->glyphs.length;
				NSUInteger start = rangePtr->location;

				*contentPtr = NSUnionRect(*contentPtr, band);
				rangePtr->length = end - start;
			}
		}
	}
	return found;
}

- (NSRect)cg_boundsForBlock:(NSTextBlock *)block range:(NSRange *)rangePtr
{
	FNBlockRect *override = [self cg_overrideEntryForBlock:block create:NO];
	NSRect content = NSZeroRect;
	NSRange range = NSMakeRange(0, 0);
	NSUInteger container = 0;
	BOOL flow = [block isKindOfClass:[NSTextTableBlock class]];

	if (override != nil && override->hasBounds) {
		if (rangePtr != NULL) {
			/* **AN OVERRIDE STILL REPORTS THE BLOCK'S RANGE**, because the caller asked where the block IS as well as
			 * where it was put; the rect is what changed, not the glyphs. */
			NSRect ignored = NSZeroRect;

			(void)[self cg_blockGroup:block content:&ignored range:&range container:&container flow:flow];
			*rangePtr = range;
		}
		return override->bounds;
	}
	if (![self cg_blockGroup:block content:&content range:&range container:&container flow:flow]) {
		if (rangePtr != NULL) {
			*rangePtr = NSMakeRange(NSNotFound, 0);
		}
		return NSZeroRect;
	}
	if (rangePtr != NULL) {
		*rangePtr = range;
	}
	return [self cg_frameForBlock:block union:content containerIndex:container origin:NSZeroPoint
			characterRange:range];
}

- (NSRect)cg_layoutForBlock:(NSTextBlock *)block range:(NSRange *)rangePtr
{
	FNBlockRect *override = [self cg_overrideEntryForBlock:block create:NO];
	NSRect content = NSZeroRect;
	NSRange range = NSMakeRange(0, 0);
	NSUInteger container = 0;

	if (override != nil && override->hasLayout) {
		if (rangePtr != NULL) {
			NSRect ignored = NSZeroRect;

			(void)[self cg_blockGroup:block content:&ignored range:&range container:&container flow:NO];
			*rangePtr = range;
		}
		return override->layout;
	}
	if (![self cg_blockGroup:block content:&content range:&range container:&container flow:NO]) {
		if (rangePtr != NULL) {
			*rangePtr = NSMakeRange(NSNotFound, 0);
		}
		return NSZeroRect;
	}
	if (rangePtr != NULL) {
		*rangePtr = range;
	}
	(void)container;
	return content;
}

- (NSRect)boundsRectForTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange
{
	(void)glyphRange;	/* the block's own range is what the frame is made from; the argument names WHICH block */
	return [self cg_boundsForBlock:block range:NULL];
}

- (NSRect)layoutRectForTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange
{
	(void)glyphRange;
	return [self cg_layoutForBlock:block range:NULL];
}

- (void)setBoundsRect:(NSRect)rect forTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange
{
	FNBlockRect *entry = [self cg_overrideEntryForBlock:block create:(block != nil)];

	(void)glyphRange;
	if (entry == nil) {
		return;
	}
	entry->bounds = rect;
	entry->hasBounds = YES;
}

- (void)setLayoutRect:(NSRect)rect forTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange
{
	FNBlockRect *entry = [self cg_overrideEntryForBlock:block create:(block != nil)];

	(void)glyphRange;
	if (entry == nil) {
		return;
	}
	entry->layout = rect;
	entry->hasLayout = YES;
}

/* **THE `atIndex:` PAIR, AND ITS INDEX IS A GLYPH'S.** Apple's own parameter names in this pair are `glyphIndex` and
 * `glyphRange`, so a caller that passes a character index here is already wrong in Apple's terms; the door finds the
 * glyph's fragment, checks that the block it belongs to is the one asked for, and answers the GROUP's range. */
- (NSRect)boundsRectForTextBlock:(NSTextBlock *)block atIndex:(NSUInteger)glyphIndex
		  effectiveRange:(NSRange *)glyphRange
{
	FNFragment *fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:NULL];
	NSRect rect;

	if (fragment == nil || [self cg_blockForFragment:fragment] != block) {
		if (glyphRange != NULL) {
			*glyphRange = NSMakeRange(NSNotFound, 0);
		}
		return NSZeroRect;
	}
	rect = [self cg_boundsForBlock:block range:glyphRange];
	return rect;
}

- (NSRect)layoutRectForTextBlock:(NSTextBlock *)block atIndex:(NSUInteger)glyphIndex
		  effectiveRange:(NSRange *)glyphRange
{
	FNFragment *fragment = [self cg_fragmentForGlyphAtIndex:glyphIndex effectiveRange:NULL];
	NSRect rect;

	if (fragment == nil || [self cg_blockForFragment:fragment] != block) {
		if (glyphRange != NULL) {
			*glyphRange = NSMakeRange(NSNotFound, 0);
		}
		return NSZeroRect;
	}
	rect = [self cg_layoutForBlock:block range:glyphRange];
	return rect;
}

/* ---- THE ATTACHMENT'S SIZE ------------------------------------------------------------------------------ */

- (void)setAttachmentSize:(NSSize)attachmentSize forGlyphRange:(NSRange)glyphRange
{
	NSRange chars;
	NSUInteger i;

	[self cg_ensureLayout];
	chars = [self characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
	if (chars.location == NSNotFound || chars.length == 0) {
		return;
	}
	for (i = chars.location; i < chars.location + chars.length; i++) {
		[_attachmentSizes setObject:[NSValue valueWithSize:attachmentSize]
				     forKey:[NSNumber numberWithUnsignedInteger:i]];
	}
	/* **AND THE LAYOUT IS TOLD, BECAUSE THE SIZE IS A LAYOUT FACT.** Without this the override would reach the answer
	 * and not the engine, which is the failure mode this door exists to avoid: a caller measuring a box the layout
	 * never made. */
	[self invalidateLayoutForCharacterRange:chars actualCharacterRange:NULL];
}

- (NSSize)attachmentSizeForGlyphAtIndex:(NSUInteger)glyphIndex
{
	NSValue *overrideValue;
	NSUInteger charIndex;
	NSUInteger i, j;

	[self cg_ensureLayout];
	charIndex = [self characterIndexForGlyphAtIndex:glyphIndex];
	/* THE BOX THE LAYOUT MADE WINS, because that is the size the text actually flowed around. */
	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *fragment = [fragments objectAtIndex:j];
			NSUInteger b;

			if (fragment->boxes == nil
			    || charIndex < fragment->range.location
			    || charIndex >= fragment->range.location + fragment->range.length) {
				continue;
			}
			for (b = 0; b < [fragment->boxes count]; b++) {
				FNBox *box = [fragment->boxes objectAtIndex:b];

				if (box->index == charIndex) {
					return NSMakeSize(box->width, box->ascent + box->descent);
				}
			}
		}
	}
	overrideValue = [_attachmentSizes objectForKey:[NSNumber numberWithUnsignedInteger:charIndex]];
	if (overrideValue != nil) {
		return [overrideValue sizeValue];
	}
	/* AND A GLYPH WITH NO BOX ANSWERS THE CELL'S SIZE WHEN THE STORE STILL CARRIES AN ATTACHMENT THERE, which is the
	 * case before a layout has run. */
	if (charIndex < [_textStorage length]) {
		NSDictionary *attrs = [_textStorage attributesAtIndex:charIndex effectiveRange:NULL];
		NSTextAttachment *attachment = [attrs objectForKey:NSAttachmentAttributeName];

		if (attachment != nil && [attachment attachmentCell] != nil) {
			return [[attachment attachmentCell] cellSize];
		}
	}
	return NSZeroSize;
}

- (NSImageScaling)defaultAttachmentScaling
{
	return _defaultAttachmentScaling;
}

- (void)setDefaultAttachmentScaling:(NSImageScaling)newScaling
{
	_defaultAttachmentScaling = newScaling;
}

/* **THE CELL DRAWN INTO A RECTANGLE, SCALED BY THE MODE THE MANAGER CARRIES.** The cell draws itself into whatever frame
 * it is handed, so scaling is the frame's business: proportionally-down shrinks an oversized picture to fit, up-or-down
 * fits either way, axes-independently fills, and none keeps the cell's own size. THE DRAW IS CLIPPED TO THE RECTANGLE in
 * every mode, because a picture that overflows its line is a picture over its neighbours. */
- (void)showAttachmentCell:(NSCell *)cell inRect:(NSRect)rect characterIndex:(NSUInteger)characterIndex
{
	NSTextContainer *container = [self textContainerForGlyphAtIndex:
		[self glyphIndexForCharacterAtIndex:characterIndex] effectiveRange:NULL];
	NSView *view = (container != nil) ? (NSView *)[container textView] : nil;
	NSSize natural = (cell != nil) ? [cell cellSize] : NSZeroSize;
	NSValue *overrideValue = [_attachmentSizes objectForKey:
		[NSNumber numberWithUnsignedInteger:characterIndex]];
	NSRect frame = rect;

	if (cell == nil) {
		return;
	}
	if (overrideValue != nil) {
		natural = [overrideValue sizeValue];
	}
	if (natural.width > 0.0 && natural.height > 0.0 && !NSIsEmptyRect(rect)) {
		switch (_defaultAttachmentScaling) {
		case NSImageScaleProportionallyDown:
		case NSImageScaleProportionallyUpOrDown: {
			CGFloat sx = NSWidth(rect) / natural.width;
			CGFloat sy = NSHeight(rect) / natural.height;
			CGFloat scale = (sx < sy) ? sx : sy;

			if (_defaultAttachmentScaling == NSImageScaleProportionallyDown && scale > 1.0) {
				scale = 1.0;
			}
			frame = NSMakeRect(NSMidX(rect) - natural.width * scale * 0.5,
					   NSMidY(rect) - natural.height * scale * 0.5,
					   natural.width * scale, natural.height * scale);
			break;
		}
		case NSImageScaleAxesIndependently:
			frame = rect;
			break;
		case NSImageScaleNone:
		default:
			frame = NSMakeRect(NSMidX(rect) - natural.width * 0.5, NSMidY(rect) - natural.height * 0.5,
					   natural.width, natural.height);
			break;
		}
	}
	NSRectClip(rect);
	if ([cell respondsToSelector:@selector(drawWithFrame:inView:characterIndex:)]) {
		[(id<NSTextAttachmentCell>)cell drawWithFrame:frame inView:view characterIndex:characterIndex];
	} else {
		[cell drawWithFrame:frame inView:view];
	}
}

@end

/* ==================================================================================================================
 * THE TEMPORARY ATTRIBUTES AND THE RECT ARRAYS — the last two families declared in the header.
 *
 * The run table is four operations, and every public door is one of them or a lookup: SET replaces a range's attributes
 * (splitting the runs it crosses and keeping their tails), ADD merges into whatever is there, REMOVE deletes a key, and
 * LOOKUP answers a run. Adjacent runs with equal dictionaries are merged after every change, because
 * `longestEffectiveRange:` promises the range over which a value does not change and two abutting runs with one value are
 * one range.
 *
 * **AND THE DRAWING PASS IS WHAT MAKES THE TABLE MEAN ANYTHING.** `-cg_drawingAttributesAtIndex:…` merges the store's
 * run with the temporary one, asks the delegate's `shouldUseTemporaryAttributes:` question when there IS one, and is the
 * only path the glyph and background passes read their ink through — so a temporary foreground colour reaches the pixels
 * and a delegate that declines reaches none of them.
 * ================================================================================================================ */

@implementation NSLayoutManager (AGTemporaryAttributes)

/* THE BUFFER'S ENDS. The store is the limit: a temporary attribute past the text is an attribute on characters that do
 * not exist, and a table that stored it would answer a run nobody can draw. */
- (NSRange)cg_clipToStore:(NSRange)range
{
	NSUInteger length = [_textStorage length];

	if (range.location >= length) {
		return NSMakeRange(length, 0);
	}
	if (NSMaxRange(range) > length) {
		range.length = length - range.location;
	}
	return range;
}

- (FNTextMark *)cg_markAtCharacterIndex:(NSUInteger)index
{
	NSUInteger i;

	for (i = 0; i < [_temporaryMarks count]; i++) {
		FNTextMark *mark = [_temporaryMarks objectAtIndex:i];

		if (index >= mark->range.location && index < NSMaxRange(mark->range)) {
			return mark;
		}
	}
	return nil;
}

/* THE START OF THE NEXT RUN AFTER AN INDEX, or `limit` when there is none — which is how "split the add into the pieces
 * the existing runs define" walks without an index-per-character table. */
- (NSUInteger)cg_nextMarkStartAfter:(NSUInteger)index upTo:(NSUInteger)limit
{
	NSUInteger i;
	NSUInteger best = limit;

	for (i = 0; i < [_temporaryMarks count]; i++) {
		NSUInteger start = ((FNTextMark *)[_temporaryMarks objectAtIndex:i])->range.location;

		if (start > index && start < best) {
			best = start;
		}
	}
	return best;
}

/* MERGE THE NEIGHBOURS: equal dictionaries and abutting ranges are one run. It runs after every change, so the table
 * never holds two runs that a lookup would have to walk past to answer a "longest" question. */
- (void)cg_compactMarks
{
	NSMutableArray *sorted = [NSMutableArray arrayWithCapacity:[_temporaryMarks count]];
	NSUInteger i;

	/* INSERTION SORT: a table of marks is small, and a comparator built for it would be more code than the sort. */
	for (i = 0; i < [_temporaryMarks count]; i++) {
		FNTextMark *mark = [_temporaryMarks objectAtIndex:i];
		NSUInteger at = 0;

		while (at < [sorted count]
		       && ((FNTextMark *)[sorted objectAtIndex:at])->range.location <= mark->range.location) {
			at++;
		}
		[sorted insertObject:mark atIndex:at];
	}
	[_temporaryMarks setArray:sorted];
	for (i = 1; i < [_temporaryMarks count]; ) {
		FNTextMark *previous = [_temporaryMarks objectAtIndex:i - 1];
		FNTextMark *mark = [_temporaryMarks objectAtIndex:i];

		if (NSMaxRange(previous->range) == mark->range.location
		    && [previous->attributes isEqualToDictionary:mark->attributes]) {
			previous->range.length += mark->range.length;
			[_temporaryMarks removeObjectAtIndex:i];
			continue;
		}
		i++;
	}
}

/* REPLACE, which is the primitive: every run the range touches is trimmed to the parts outside it (a left head and a
 * right tail), and the new run goes in. A SET with an empty dictionary is a REMOVE, because a run with no attributes is
 * a run that says nothing. */
- (void)cg_setMarkAttributes:(NSDictionary *)attributes inRange:(NSRange)range
{
	NSMutableArray *kept = [NSMutableArray array];
	NSUInteger i;

	range = [self cg_clipToStore:range];
	if (range.length == 0) {
		return;
	}
	for (i = 0; i < [_temporaryMarks count]; i++) {
		FNTextMark *mark = [_temporaryMarks objectAtIndex:i];
		NSRange run = mark->range;

		if (NSMaxRange(run) <= range.location || run.location >= NSMaxRange(range)) {
			[kept addObject:mark];
			continue;
		}
		if (run.location < range.location) {
			mark->range.length = range.location - run.location;
			[kept addObject:mark];
		}
		if (NSMaxRange(run) > NSMaxRange(range)) {
			NSRange tail = NSMakeRange(NSMaxRange(range), NSMaxRange(run) - NSMaxRange(range));

			[kept addObject:[FNTextMark markWithRange:tail attributes:mark->attributes]];
		}
	}
	if ([attributes count] > 0) {
		[kept addObject:[FNTextMark markWithRange:range attributes:attributes]];
	}
	[_temporaryMarks setArray:kept];
	[self cg_compactMarks];
}

/* ADD, ONE PIECE AT A TIME: the range is walked in the pieces the existing runs define, and each piece's merged
 * dictionary is SET. That is what makes an add to the middle of a run split it with the same value on both sides and the
 * new one in between. */
- (void)cg_addAttributes:(NSDictionary *)attributes inRange:(NSRange)range
{
	NSUInteger position;
	NSUInteger end;

	range = [self cg_clipToStore:range];
	position = range.location;
	end = NSMaxRange(range);
	while (position < end) {
		FNTextMark *mark = [self cg_markAtCharacterIndex:position];
		NSUInteger stop = (mark != nil) ? MIN(end, NSMaxRange(mark->range))
						: [self cg_nextMarkStartAfter:position upTo:end];
		NSMutableDictionary *merged = [NSMutableDictionary dictionary];
		NSRange piece;

		if (mark != nil) {
			[merged addEntriesFromDictionary:mark->attributes];
		}
		[merged addEntriesFromDictionary:attributes];
		piece = NSMakeRange(position, stop - position);
		[self cg_setMarkAttributes:merged inRange:piece];
		position = stop;
	}
}

- (void)cg_removeAttribute:(NSString *)name inRange:(NSRange)range
{
	NSUInteger position;
	NSUInteger end;

	range = [self cg_clipToStore:range];
	position = range.location;
	end = NSMaxRange(range);
	while (position < end) {
		FNTextMark *mark = [self cg_markAtCharacterIndex:position];
		NSUInteger stop;
		NSMutableDictionary *remaining;

		if (mark == nil) {
			position = [self cg_nextMarkStartAfter:position upTo:end];
			continue;
		}
		stop = MIN(end, NSMaxRange(mark->range));
		remaining = [[mark->attributes mutableCopy] autorelease];
		[remaining removeObjectForKey:name];
		[self cg_setMarkAttributes:remaining inRange:NSMakeRange(position, stop - position)];
		position = stop;
	}
}

- (void)setTemporaryAttributes:(NSDictionary *)attrs forCharacterRange:(NSRange)charRange
{
	[self cg_setMarkAttributes:attrs inRange:charRange];
}

- (void)addTemporaryAttributes:(NSDictionary *)attrs forCharacterRange:(NSRange)charRange
{
	[self cg_addAttributes:attrs inRange:charRange];
}

- (void)addTemporaryAttribute:(NSString *)attrName value:(id)value forCharacterRange:(NSRange)charRange
{
	if (value == nil) {
		[self removeTemporaryAttribute:attrName forCharacterRange:charRange];
		return;
	}
	[self cg_addAttributes:[NSDictionary dictionaryWithObject:value forKey:attrName] inRange:charRange];
}

- (void)removeTemporaryAttribute:(NSString *)attrName forCharacterRange:(NSRange)charRange
{
	[self cg_removeAttribute:attrName inRange:charRange];
}

- (NSDictionary *)temporaryAttributesAtCharacterIndex:(NSUInteger)location effectiveRange:(NSRange *)range
{
	FNTextMark *mark = [self cg_markAtCharacterIndex:location];

	if (range != NULL) {
		*range = (mark != nil) ? mark->range : NSMakeRange(location, 0);
	}
	return (mark != nil) ? mark->attributes : nil;
}

- (id)temporaryAttribute:(NSString *)attrName atCharacterIndex:(NSUInteger)location effectiveRange:(NSRange *)range
{
	NSDictionary *attributes = [self temporaryAttributesAtCharacterIndex:location effectiveRange:range];

	return (attributes != nil) ? [attributes objectForKey:attrName] : nil;
}

- (NSDictionary *)temporaryAttributesAtCharacterIndex:(NSUInteger)location
				longestEffectiveRange:(NSRange *)range inRange:(NSRange)rangeLimit
{
	FNTextMark *mark = [self cg_markAtCharacterIndex:location];
	NSRange clipped;

	if (mark == nil) {
		if (range != NULL) {
			*range = NSMakeRange(location, 0);
		}
		return nil;
	}
	clipped = NSIntersectionRange(mark->range, rangeLimit);
	if (clipped.length == 0) {
		clipped = NSMakeRange(location, 0);
	}
	if (range != NULL) {
		*range = clipped;
	}
	return mark->attributes;
}

- (id)temporaryAttribute:(NSString *)attrName atCharacterIndex:(NSUInteger)location
     longestEffectiveRange:(NSRange *)range inRange:(NSRange)rangeLimit
{
	NSDictionary *attributes = [self temporaryAttributesAtCharacterIndex:location
					   longestEffectiveRange:range inRange:rangeLimit];

	return (attributes != nil) ? [attributes objectForKey:attrName] : nil;
}

/* **THE ONE PLACE THE TWO TABLES MEET, AND THE DELEGATE'S VETO.** The store's run is read first (it is the one with a
 * length); a temporary run that covers the index merges over it; and when the delegate implements the era's question it
 * is asked with the temporary dictionary and may decline, in which case the store's answer stands alone. */
- (NSDictionary *)cg_drawingAttributesAtIndex:(NSUInteger)index longestEffectiveRange:(NSRange *)range
				      inRange:(NSRange)rangeLimit
{
	NSRange permanentRange = NSMakeRange(0, 0);
	NSDictionary *permanent = [_textStorage attributesAtIndex:index longestEffectiveRange:&permanentRange
							    inRange:rangeLimit];
	FNTextMark *mark = [self cg_markAtCharacterIndex:index];
	NSMutableDictionary *merged;
	NSRange effective;

	if (mark == nil) {
		/* **AND A STORE RUN STOPS AT THE NEXT TEMPORARY RUN, EVEN THOUGH IT IS NOT INSIDE ONE.** The drawing walk
		 * advances by the effective range it is handed, so a run that claimed the whole line would step OVER the
		 * temporary attribute in the middle of it and the ink would never change. MEASURED: that is exactly what
		 * happened — a red character in the middle of a green line drew green, and only a delegate test noticed,
		 * because its temporary run started at index 0. */
		NSRange effective = permanentRange;
		NSUInteger next = [self cg_nextMarkStartAfter:index upTo:NSMaxRange(permanentRange)];

		if (next < NSMaxRange(effective)) {
			effective.length = next - effective.location;
		}
		if (range != NULL) {
			*range = effective;
		}
		return permanent;
	}
	if (_delegate != nil && [_delegate respondsToSelector:
			@selector(layoutManager:shouldUseTemporaryAttributes:forDrawingToScreen:atCharacterIndex:effectiveRange:)]) {
		NSRange asked = NSIntersectionRange(permanentRange, mark->range);

		if (![_delegate layoutManager:self shouldUseTemporaryAttributes:mark->attributes
			     forDrawingToScreen:YES atCharacterIndex:index effectiveRange:&asked]) {
			if (range != NULL) {
				*range = permanentRange;
			}
			return permanent;
		}
	}
	effective = NSIntersectionRange(permanentRange, mark->range);
	if (effective.length == 0) {
		effective = NSMakeRange(index, 1);
	}
	if (range != NULL) {
		*range = effective;
	}
	merged = [NSMutableDictionary dictionaryWithDictionary:permanent];
	[merged addEntriesFromDictionary:mark->attributes];
	return merged;
}

/* ==================================================================================================================
 * THE RECT ARRAYS.
 * ================================================================================================================ */

/* WHICH CONTAINER A FRAGMENT IS IN, by identity — the arrays are index-matched, so this is a scan of the outer list. */
- (NSUInteger)cg_containerIndexForFragment:(FNFragment *)fragment
{
	NSUInteger i, j;

	for (i = 0; i < [_fragments count]; i++) {
		NSMutableArray *fragments = [_fragments objectAtIndex:i];

		for (j = 0; j < [fragments count]; j++) {
			if ([fragments objectAtIndex:j] == fragment) {
				return i;
			}
		}
	}
	return NSNotFound;
}

- (NSRect *)cg_rectsForGlyphRange:(NSRange)glyphRange selected:(NSRange)selGlyphRange
		   inTextContainer:(NSTextContainer *)container rectCount:(NSUInteger *)rectCount
{
	NSMutableArray *rects;
	NSUInteger containerIndex;

	[self cg_ensureLayout];
	if (rectCount != NULL) {
		*rectCount = 0;
	}
	if (container == nil) {
		return NULL;
	}
	containerIndex = [_textContainers indexOfObjectIdenticalTo:container];
	if (containerIndex == NSNotFound) {
		return NULL;
	}
	rects = [NSMutableArray array];
	/* **A CARET IS ONE RECT, ON THE LINE IT SITS IN.** The boundary between two lines belongs to the line it OPENS,
	 * which is the rule `-cg_fragmentForGlyphAtIndex:` records — so the fragment is asked for rather than scanned for,
	 * and the loop below then handles only a range with glyphs in it. */
	if (glyphRange.length == 0) {
		FNFragment *caret = [self cg_fragmentForGlyphAtIndex:glyphRange.location effectiveRange:NULL];
		NSUInteger caretContainer = [self cg_containerIndexForFragment:caret];

		if (caret != nil && caretContainer == containerIndex) {
			CGFloat x = [self cg_offsetForGlyphAtIndex:glyphRange.location];

			[rects addObject:[NSValue valueWithRect:NSMakeRect(x, NSMinY(caret->rect), 0.0,
									   NSHeight(caret->rect))]];
		}
	} else {
		NSMutableArray *fragments = [_fragments objectAtIndex:containerIndex];
		NSUInteger j;

		for (j = 0; j < [fragments count]; j++) {
			FNFragment *fragment = [fragments objectAtIndex:j];
			NSRange overlap;
			CGFloat x0;
			CGFloat x1;

			overlap = NSIntersectionRange(glyphRange, fragment->glyphs);
			if (overlap.length == 0) {
				/* **AND AN EMPTY FRAGMENT — the extra line a trailing newline opens — ONLY WHEN THE RANGE REACHES THE
				 * END AND THE SELECTION COVERS IT**, which is the one thing the `withinSelected…` argument decides: a
				 * selection that ends before it leaves it undrawn, and one that includes it draws its line. */
				if (fragment->glyphs.length == 0 && NSMaxRange(glyphRange) == fragment->glyphs.location
				    && selGlyphRange.length > 0 && fragment->glyphs.location >= selGlyphRange.location
				    && fragment->glyphs.location < NSMaxRange(selGlyphRange)) {
					[rects addObject:[NSValue valueWithRect:NSMakeRect(
						NSMinX(fragment->used), NSMinY(fragment->rect),
						NSWidth(fragment->used), NSHeight(fragment->rect))]];
				}
				continue;
			}
			x0 = [self cg_offsetForGlyphAtIndex:overlap.location];
			x1 = (NSMaxRange(overlap) < NSMaxRange(fragment->glyphs))
				? [self cg_offsetForGlyphAtIndex:NSMaxRange(overlap)] : NSMaxX(fragment->used);
			if (x1 < x0) {
				x1 = x0;
			}
			[rects addObject:[NSValue valueWithRect:NSMakeRect(x0, NSMinY(fragment->rect), x1 - x0,
									   NSHeight(fragment->rect))]];
		}
	}
	if ([rects count] == 0) {
		return NULL;
	}
	if (_rectArrayCount < [rects count]) {
		_rectArray = realloc(_rectArray, sizeof(NSRect) * [rects count]);
	}
	_rectArrayCount = [rects count];
	{
		NSUInteger k;

		for (k = 0; k < [rects count]; k++) {
			_rectArray[k] = [[rects objectAtIndex:k] rectValue];
		}
	}
	if (rectCount != NULL) {
		*rectCount = _rectArrayCount;
	}
	return _rectArray;
}

- (NSRect *)rectArrayForGlyphRange:(NSRange)glyphRange
	 withinSelectedGlyphRange:(NSRange)selGlyphRange
		   inTextContainer:(NSTextContainer *)textContainer
			 rectCount:(NSUInteger *)rectCount
{
	return [self cg_rectsForGlyphRange:glyphRange selected:selGlyphRange inTextContainer:textContainer
		     rectCount:rectCount];
}

- (NSRect *)rectArrayForCharacterRange:(NSRange)charRange
	 withinSelectedCharacterRange:(NSRange)selCharRange
		      inTextContainer:(NSTextContainer *)textContainer
			   rectCount:(NSUInteger *)rectCount
{
	NSRange glyphs = [self glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
	NSRange selected = [self glyphRangeForCharacterRange:selCharRange actualCharacterRange:NULL];

	return [self cg_rectsForGlyphRange:glyphs selected:selected inTextContainer:textContainer
		     rectCount:rectCount];
}

@end

/* ==================================================================================================================
 * THE INVALIDATION AND ENSURE FAMILY, THE CONTAINER TIDINGS, THE EXTRA LINE AND TWO FONT MEASUREMENTS.
 *
 * The three kinds of staleness this tier has are one: a store edit marks the layout stale and the next question rebuilds
 * it. So the ensure doors ask for the layout, the glyph and layout invalidation doors mark it, and the display doors go
 * to the VIEW — which is the only place a pixel can be asked for. The conversion that is not a no-op is the glyph-range
 * one: a caller names glyphs and the record is keyed by characters, so it translates through the map the manager already
 * keeps.
 * ================================================================================================================ */

@implementation NSLayoutManager (AGInvalidation)

- (void)ensureGlyphsForCharacterRange:(NSRange)charRange
{
	(void)charRange;
	/* **A TIER THAT LAYS OUT IN FULL NEEDS NO RANGE.** The question "make sure these characters have glyphs" is answered
	 * by laying out, and laying out produces every glyph; a partial pass would be a second layout path with nothing to
	 * gain while the fragments are rebuilt from the store in one walk. */
	[self cg_ensureLayout];
}

- (void)ensureGlyphsForGlyphRange:(NSRange)glyphRange
{
	(void)glyphRange;
	[self cg_ensureLayout];
}

- (void)invalidateGlyphsForCharacterRange:(NSRange)charRange changeInLength:(NSInteger)delta
		     actualCharacterRange:(NSRange *)actualCharRange
{
	/* **THE DELTA IS THE STORE'S ALREADY.** Apple's parameter is the length change the caller made, which the store
	 * reports through `-textStorage:edited:…`; by the time a caller sends this the string is the new one, so the delta
	 * changes nothing about WHAT is stale and is recorded only in this comment. */
	(void)delta;
	[self invalidateLayoutForCharacterRange:charRange actualCharacterRange:actualCharRange];
}

- (void)invalidateGlyphsOnLayoutInvalidationForGlyphRange:(NSRange)glyphRange
{
	NSRange chars = [self characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];

	/* The layout is keyed by CHARACTERS, so a caller naming glyphs is translated — which is the one thing this door does
	 * that the two-character-range door beside it does not. */
	[self invalidateLayoutForCharacterRange:chars actualCharacterRange:NULL];
}

- (void)invalidateLayoutForCharacterRange:(NSRange)charRange isSoft:(BOOL)flag
		     actualCharacterRange:(NSRange *)actualCharRange
{
	/* **SOFTNESS IS RECORDED IN THE SENTENCE AND NOWHERE ELSE.** Apple's soft invalidation defers the layout of marked
	 * text; this tier lays out only when somebody asks, so the deferral is the only behaviour there is. */
	(void)flag;
	[self invalidateLayoutForCharacterRange:charRange actualCharacterRange:actualCharRange];
}

/* **THE DAMAGE RECT IS THE LAYOUT'S, MOVED INTO THE VIEW.** The bounding rect is in container coordinates; this tier's
 * text views put their container at their own origin plus the line-fragment padding, so the rect is offset by that
 * padding before the view is asked. A view that put its container somewhere else would get a slightly wrong rect — and
 * the padding's growth on BOTH axes is what keeps the answer safe rather than merely close. */
- (void)cg_invalidateDisplayForGlyphRange:(NSRange)glyphRange
{
	NSUInteger i;

	[self cg_ensureLayout];
	for (i = 0; i < [_textContainers count]; i++) {
		NSTextContainer *container = [_textContainers objectAtIndex:i];
		NSTextView *view = (NSTextView *)[container textView];
		NSRect bounds;

		if (view == nil) {
			continue;
		}
		bounds = [self boundingRectForGlyphRange:glyphRange inTextContainer:container];
		if (NSIsEmptyRect(bounds)) {
			continue;
		}
		{
			CGFloat padding = [container lineFragmentPadding];

			bounds = NSInsetRect(bounds, -padding, -padding);
		}
		[view setNeedsDisplayInRect:bounds];
	}
}

- (void)invalidateDisplayForGlyphRange:(NSRange)glyphRange
{
	[self cg_invalidateDisplayForGlyphRange:glyphRange];
}

- (void)invalidateDisplayForCharacterRange:(NSRange)charRange
{
	NSRange glyphs = [self glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];

	[self cg_invalidateDisplayForGlyphRange:glyphs];
}

- (void)getFirstUnlaidCharacterIndex:(NSUInteger *)charIndex glyphIndex:(NSUInteger *)glyphIndex
{
	/* THE TWO ANSWERS THIS TIER ALREADY HAS, ASKED TOGETHER — which is what Apple's door is for. */
	[self cg_ensureLayout];
	if (charIndex != NULL) {
		*charIndex = [self firstUnlaidCharacterIndex];
	}
	if (glyphIndex != NULL) {
		*glyphIndex = [self firstUnlaidGlyphIndex];
	}
}

- (NSRange)glyphRangeForBoundingRect:(NSRect)bounds inTextContainer:(NSTextContainer *)container
{
	NSUInteger index;
	NSMutableArray *fragments;
	NSRange range = NSMakeRange(NSNotFound, 0);
	NSUInteger i;

	if (container == nil) {
		return range;
	}
	index = [_textContainers indexOfObjectIdenticalTo:container];
	if (index == NSNotFound) {
		return range;
	}
	[self cg_ensureLayout];
	fragments = [_fragments objectAtIndex:index];
	for (i = 0; i < [fragments count]; i++) {
		FNFragment *fragment = [fragments objectAtIndex:i];

		/* **A FRAGMENT IS HIT BY ITS FLOW BAND, NOT ITS INK.** A rect that clips the end of a line still covers that
		 * line's glyphs, and a caller redrawing a band should be told about the whole line it intersected; the used rect
		 * would answer "no glyphs here" for the leading space of an indented line. */
		if (!NSIntersectsRect(fragment->rect, bounds)) {
			continue;
		}
		if (range.location == NSNotFound) {
			range = fragment->glyphs;
		} else {
			NSUInteger lo = MIN(range.location, fragment->glyphs.location);
			NSUInteger hi = MAX(NSMaxRange(range), NSMaxRange(fragment->glyphs));

			range = NSMakeRange(lo, hi - lo);
		}
	}
	return range;
}

- (NSRange)glyphRangeForBoundingRectWithoutAdditionalLayout:(NSRect)bounds inTextContainer:(NSTextContainer *)container
{
	return [self glyphRangeForBoundingRect:bounds inTextContainer:container];
}

/* A GEOMETRY CHANGE RE-WRAPS EVERYTHING: the container's size is what the breaker was handed, and in this tier every
 * container's fragments are rebuilt together, so the whole store is stale rather than the container's share of it. */
- (void)textContainerChangedGeometry:(NSTextContainer *)container
{
	(void)container;
	[self invalidateLayoutForCharacterRange:NSMakeRange(0, [_textStorage length]) actualCharacterRange:NULL];
}

/* **AND A VIEW THAT CHANGED IS A PICTURE THAT MOVED.** There is no layout to redo — the geometry is the container's —
 * so the view is asked to repaint, which is the whole of what this door can mean here. */
- (void)textContainerChangedTextView:(NSTextContainer *)container
{
	NSTextView *view = (NSTextView *)[container textView];

	[view setNeedsDisplay:YES];
}

- (NSRect)extraLineFragmentRect
{
	return _extraLineRect;
}

- (NSRect)extraLineFragmentUsedRect
{
	return _extraLineUsedRect;
}

- (NSTextContainer *)extraLineFragmentTextContainer
{
	return _extraLineContainer;
}

- (void)setExtraLineFragmentRect:(NSRect)aRect usedRect:(NSRect)usedRect textContainer:(NSTextContainer *)aContainer
{
	_extraLineRect = aRect;
	_extraLineUsedRect = usedRect;
	_extraLineContainer = aContainer;	/* BORROWED */
}

- (CGFloat)defaultLineHeightForFont:(NSFont *)aFont
{
	if (aFont == nil) {
		return 0.0;
	}
	/* **ASCENDER MINUS A NEGATIVE DESCENDER, PLUS THE LEADING** — the font's own numbers, which is Apple's contract for
	 * this door and the same arithmetic the layout's baseline uses. */
	return [aFont ascender] - [aFont descender] + [aFont leading];
}

- (CGFloat)defaultBaselineOffsetForFont:(NSFont *)aFont
{
	return (aFont != nil) ? [aFont ascender] : 0.0;
}

@end
