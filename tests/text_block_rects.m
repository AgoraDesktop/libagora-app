/*
 * text_block_rects — the block's two rectangles and an attachment's size, which are the layout's answers to a caller.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIMS ARE THREE AND EACH IS CHECKABLE WITHOUT KNOWING THE LAYOUT'S ARITHMETIC.**
 *
 * First, the two rects differ by EXACTLY the block's own layers: a block with six points of padding and two of border
 * on every edge answers a bounds rect that is its layout rect inset by `-(4 + 2)` — the number `NSTextBlock` itself
 * grows a content rect by. A door that returned the content rect twice, or one that grew by the wrong sum, fails here.
 *
 * Second, a caller can DICTATE either rect and the other stays computed, which is what Apple's two setters are for.
 *
 * Third — and this is the one that reaches the engine — an attachment's size can be overridden, and the text after it
 * MOVES by the difference. So the override is measured as a reflow, not as a changed answer.
 *
 * The attachment doors are also read at both ends: the size the layout reserved, and the scaling the drawing applies
 * when the rectangle it was given is not the picture's size.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextBlock.h>
#import <AppKit/NSTextTable.h>
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

#define W 80
#define H 50

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int close_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* A PICTURE THAT IS ONE FLAT COLOUR, so a pixel read says whether it was drawn and where. */
static NSImage *red_image(CGFloat w, CGFloat h)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
		isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)w * 4 bitsPerPixel:32];
	NSImage *image;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, w, h)] fill];
	image = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
	[image addRepresentation:rep];
	[rep release];
	return image;
}

/* **THE ROWS ARE NOT THE DRAWING'S ROWS.** `-colorAtX:y:` indexes from the opposite end to the drawing coordinates —
 * the handoff records the same trap from the bitmap sampler — so a rect is converted ONCE, here, into the row band it
 * covers: row `H - 1 - y`. A test that compared a drawing rect with a bitmap row directly would report a correct draw as
 * missing (MEASURED: a 40x40 picture filled its rect exactly, and the naive band called 80 of its pixels "outside"). */
static void row_band(NSRect rect, int *y0, int *y1)
{
	*y0 = H - (int)ceil((double)NSMaxY(rect));
	*y1 = H - 1 - (int)floor((double)NSMinY(rect));
}

static int count_red(NSBitmapImageRep *rep, NSRect rect, BOOL inside)
{
	int x, y, count = 0;
	int x0 = (int)floor((double)NSMinX(rect));
	int x1 = (int)ceil((double)NSMaxX(rect)) - 1;
	int y0, y1;

	row_band(rect, &y0, &y1);
	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];
			BOOL inRect = (x >= x0 && x <= x1 && y >= y0 && y <= y1);

			if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4
			    && (inside ? inRect : !inRect)) {
				count++;
			}
		}
	}
	return count;
}

static int red_inside(NSBitmapImageRep *rep, NSRect rect)
{
	return count_red(rep, rect, YES);
}

static int red_outside(NSBitmapImageRep *rep, NSRect rect)
{
	return count_red(rep, rect, NO);
}

/* A BLOCK WITH SIX POINTS OF PADDING AND TWO OF BORDER ON EVERY EDGE, and no margin: the bounds rect has to be the
 * layout rect inset by eight, which is the number the block's own `-boundsRectForContentRect:` grows it by. */
static NSTextBlock *new_block(void)
{
	NSTextBlock *block = [[NSTextBlock alloc] init];

	[block setWidth:6.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
	[block setWidth:0.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockMargin];
	[block setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge];
	[block setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge];
	[block setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSTextBlockMinYEdge];
	[block setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSTextBlockMaxYEdge];
	return block;
}

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1. THE TWO RECTS DIFFER BY THE BLOCK'S OWN LAYERS.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 200.0)];
			NSTextStorage *store;
			NSTextBlock *block = new_block();
			NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
			NSRange effective = NSMakeRange(0, 0);
			NSRect layout;
			NSRect bounds;

			store = [[NSTextStorage alloc] initWithString:@"one\ntwo\n"];
			[store addLayoutManager:manager];
			[manager addTextContainer:container];
			[style addTextBlock:block];
			[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [store length])];
			[style release];
			(void)container;

			layout = [manager layoutRectForTextBlock:block atIndex:0 effectiveRange:&effective];
			check(!NSIsEmptyRect(layout), "a laid-out block has a layout rect");
			check(effective.location == 0 && effective.length >= 8,
			      "and the effective range is the block's own glyphs, both paragraphs of them");
			check(layout.origin.x >= 6.0,
			      "the layout rect starts at the text's inset, not at a negative offset");

			bounds = [manager boundsRectForTextBlock:block glyphRange:NSMakeRange(0, 8)];
			check(close_enough(NSMinX(bounds), NSMinX(layout) - 8.0)
				      && close_enough(NSMinY(bounds), NSMinY(layout) - 8.0)
				      && close_enough(NSWidth(bounds), NSWidth(layout) + 16.0)
				      && close_enough(NSHeight(bounds), NSHeight(layout) + 16.0),
			      "and the bounds rect is that rect grown by padding plus border on every edge");

			/* THE OTHER SPELLING OF THE SAME QUESTION ANSWERS THE SAME RECT. */
			check(NSEqualRects(bounds, [manager boundsRectForTextBlock:block atIndex:3 effectiveRange:NULL]),
			      "the atIndex: spelling agrees with the glyphRange: one");
			check(NSEqualRects(layout, [manager layoutRectForTextBlock:block glyphRange:NSMakeRange(0, 8)]),
			      "and so does the layout pair");

			/* A BLOCK THAT IS NOT IN THE LAYOUT HAS NO RECT, and says so in the range. */
			{
				NSTextBlock *stranger = new_block();
				NSRange missing = NSMakeRange(0, 0);
				NSRect none = [manager boundsRectForTextBlock:stranger atIndex:0 effectiveRange:&missing];

				check(NSIsEmptyRect(none) && missing.location == NSNotFound,
				      "a block that was never laid out answers NSZeroRect and NSNotFound");
				[stranger release];
			}

			/* AND THE SETTERS ARE A SUBCLASS'S: what one stores, the getter answers. */
			[manager setBoundsRect:NSMakeRect(10.0, 20.0, 30.0, 40.0) forTextBlock:block
				 glyphRange:NSMakeRange(0, 8)];
			check(NSEqualRects([manager boundsRectForTextBlock:block glyphRange:NSMakeRange(0, 8)],
					   NSMakeRect(10.0, 20.0, 30.0, 40.0)),
			      "a stored bounds rect is what the door answers");
			check(NSEqualRects([manager layoutRectForTextBlock:block glyphRange:NSMakeRange(0, 8)], layout),
			      "and storing it leaves the computed layout rect alone");
			[manager setLayoutRect:NSMakeRect(1.0, 2.0, 3.0, 4.0) forTextBlock:block
				 glyphRange:NSMakeRange(0, 8)];
			check(NSEqualRects([manager layoutRectForTextBlock:block glyphRange:NSMakeRange(0, 8)],
					   NSMakeRect(1.0, 2.0, 3.0, 4.0)),
			      "a stored layout rect is answered too");
			check(NSEqualRects([manager boundsRectForTextBlock:block glyphRange:NSMakeRange(0, 8)],
					   NSMakeRect(10.0, 20.0, 30.0, 40.0)),
			      "and the bounds override still stands beside it");

			[block release];
			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 2. A TABLE CELL'S BOUNDS ARE MEASURED FROM ITS FLOW BAND, which is what the drawing pass draws.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 200.0)];
			NSTextStorage *store;
			NSTextTable *table = [[NSTextTable alloc] init];
			NSTextTableBlock *cell;
			NSMutableParagraphStyle *style;
			NSRect layout;
			NSRect bounds;

			[table setNumberOfColumns:1];
			cell = [[NSTextTableBlock alloc] initWithTable:table startingRow:0 rowSpan:1
						       startingColumn:0 columnSpan:1];
			[cell setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder];
			[cell setWidth:4.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
			store = [[NSTextStorage alloc] initWithString:@"cell\n"];
			[store addLayoutManager:manager];
			[manager addTextContainer:container];
			style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
			[style addTextBlock:cell];
			[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [store length])];
			[style release];
			(void)container;

			layout = [manager layoutRectForTextBlock:cell atIndex:0 effectiveRange:NULL];
			bounds = [manager boundsRectForTextBlock:cell glyphRange:NSMakeRange(0, 4)];
			check(!NSIsEmptyRect(layout), "a table cell has a layout rect");
			check(NSContainsRect(bounds, layout), "and its bounds rect encloses it");
			/* **A CELL'S CONTENT IS ITS COLUMN BAND, NOT ITS TEXT**, so the bounds exceed the LAYOUT rect by
			 * more than the layers alone: the band is the cell's width and the text is narrower. What is exact is
			 * that the bounds reach outside the text by at least padding+border on every side. */
			check(NSMinX(bounds) <= NSMinX(layout) - 6.0 && NSMinY(bounds) <= NSMinY(layout) - 6.0
				      && NSMaxX(bounds) >= NSMaxX(layout) + 6.0
				      && NSMaxY(bounds) >= NSMaxY(layout) + 6.0,
			      "and it reaches outside the text by at least the cell's padding and border on every side");

			[cell release];
			[table release];
			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 3. THE ATTACHMENT'S SIZE, AND THE REFLOW AN OVERRIDE CAUSES.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 100.0)];
			NSTextStorage *store;
			NSImage *image = red_image(12.0, 12.0);
			NSTextAttachment *attachment = [NSTextAttachment textAttachmentWithImage:image];
			unichar chars[5];
			NSString *text;
			NSSize reserved;
			CGFloat attachX, afterX, movedX;

			chars[0] = 'a'; chars[1] = 'b'; chars[2] = (unichar)NSAttachmentCharacter; chars[3] = 'c'; chars[4] = 'd';
			text = [NSString stringWithCharacters:chars length:5];
			store = [[NSTextStorage alloc] initWithString:text];
			[store addLayoutManager:manager];
			[manager addTextContainer:container];
			[store addAttribute:NSAttachmentAttributeName value:attachment range:NSMakeRange(2, 1)];

			/* THE SIZE THE LAYOUT RESERVED IS THE CELL'S OWN. */
			reserved = [manager attachmentSizeForGlyphAtIndex:2];
			check(close_enough(reserved.width, 12.0) && close_enough(reserved.height, 12.0),
			      "an attachment's size is its cell's size to begin with");

			attachX = [manager cg_offsetForGlyphAtIndex:2];
			afterX = [manager cg_offsetForGlyphAtIndex:3];
			check(close_enough(afterX - attachX, 12.0), "and the character after it is that far past it");

			/* OVERRIDE IT: THE DOOR ANSWERS THE NEW SIZE AND THE TEXT MOVES BY THE DIFFERENCE. */
			[manager setAttachmentSize:NSMakeSize(40.0, 30.0) forGlyphRange:NSMakeRange(2, 1)];
			reserved = [manager attachmentSizeForGlyphAtIndex:2];
			check(close_enough(reserved.width, 40.0) && close_enough(reserved.height, 30.0),
			      "a stored attachment size is what the door answers");
			movedX = [manager cg_offsetForGlyphAtIndex:3] - attachX;
			check(close_enough(movedX, 40.0),
			      "and the layout reserved THAT width, so the text after it moved by the difference");
			check(close_enough([manager attachmentSizeForGlyphAtIndex:0].width, 0.0),
			      "a glyph that stands for nothing has no attachment size");

			/* THE SCALING MODE, STORED AND ANSWERED. */
			check([manager defaultAttachmentScaling] == NSImageScaleProportionallyDown,
			      "the default scaling is proportionally down");
			[manager setDefaultAttachmentScaling:NSImageScaleAxesIndependently];
			check([manager defaultAttachmentScaling] == NSImageScaleAxesIndependently,
			      "and the mode it is given comes back");

			/* ========================================================================================
			 * 4. THE CELL DRAWN INTO A RECTANGLE: scaled to fit, and NEVER outside it.
			 *
			 * A manager of its own, with no size override on the character — the natural size of the drawing is
			 * the CELL's, so a test that reused this manager would be drawing at the 40x30 the override above
			 * stored and measuring the wrong thing (MEASURED: it did).
			 * ====================================================================================== */
			{
				NSLayoutManager *drawManager = [[NSLayoutManager alloc] init];
				NSTextContainer *drawContainer = [[NSTextContainer alloc]
					initWithContainerSize:NSMakeSize(300.0, 100.0)];
				NSTextStorage *drawStore;
				NSBitmapImageRep *rep;
				NSRect rect = NSMakeRect(10.0, 6.0, 40.0, 40.0);
				NSImage *bigImage = red_image(40.0, 40.0);
				NSTextAttachment *bigAttachment = [NSTextAttachment textAttachmentWithImage:bigImage];
				NSString *drawText = [NSString stringWithFormat:@"a%Cb", (unichar)NSAttachmentCharacter];

				drawStore = [[NSTextStorage alloc] initWithString:drawText];
				[drawStore addLayoutManager:drawManager];
				[drawManager addTextContainer:drawContainer];
				[drawStore addAttribute:NSAttachmentAttributeName value:attachment range:NSMakeRange(1, 1)];

				/* A 12x12 picture into a 40x40 rect, proportionally DOWN: it keeps its own size (about 144
				 * pixels) rather than filling the rect (1600). That is what distinguishes scaling for the fit
				 * from scaling to fill. */
				rep = new_rep();
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[drawManager showAttachmentCell:[attachment attachmentCell] inRect:rect characterIndex:1];
				check(red_inside(rep, rect) > 80 && red_inside(rep, rect) < 400,
				      "a small picture in a big rect keeps its own size when the mode scales down only");
				check(red_outside(rep, rect) == 0, "and nothing is painted outside the rectangle");
				[rep release];

				/* A 40x40 picture into a 20x20 rect: it is shrunk to fit, and still inside. */
				rep = new_rep();
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[drawManager showAttachmentCell:[bigAttachment attachmentCell]
							 inRect:NSMakeRect(5.0, 5.0, 20.0, 20.0) characterIndex:1];
				check(red_inside(rep, NSMakeRect(5.0, 5.0, 20.0, 20.0)) > 200,
				      "a big picture is shrunk into a small rect");
				check(red_outside(rep, NSMakeRect(5.0, 5.0, 20.0, 20.0)) == 0,
				      "and it does not spill outside it");
				[rep release];

				/* SCALE NONE CAN OVERFLOW THE RECTANGLE IT IS GIVEN, so the draw is CLIPPED: no ink outside. */
				rep = new_rep();
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[drawManager setDefaultAttachmentScaling:NSImageScaleNone];
				[drawManager showAttachmentCell:[bigAttachment attachmentCell]
							 inRect:NSMakeRect(5.0, 5.0, 20.0, 20.0) characterIndex:1];
				check(red_outside(rep, NSMakeRect(5.0, 5.0, 20.0, 20.0)) == 0,
				      "an unscaled picture is clipped to its rectangle rather than painted over its neighbours");
				[rep release];

				[bigImage release];
				[drawStore release];
				[drawManager release];
				[drawContainer release];
			}

			[store release];
			[manager release];
			[container release];
			[image release];
		}

		/* ============================================================================================
		 * AND THE SWEEP'S TEN: THE GENERIC VALUE DOOR, THE CONTENT WIDTH, AND THE TWO NAMES.
		 * ========================================================================================== */
		{
			NSTextBlock *block = [[NSTextBlock alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 200.0)];
			NSRect containing = NSMakeRect(0.0, 0.0, 200.0, 200.0);
			NSRect grown;

			(void)container;

			/* 1. THE LAYER DIMENSIONS ARE THE SAME STORAGE AS THE PAIRS, which is the whole argument for one word. */
			[block setValue:10.0 type:NSTextBlockAbsoluteValueType
			   forDimension:(NSTextBlockBorderDimension | NSTextBlockMinXEdge)];
			check(close_enough([block widthForLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge], 10.0),
			      "a BORDER dimension lands in the border/edge slot the pair door reads");
			check(close_enough([block valueForDimension:(NSTextBlockBorderDimension | NSTextBlockMinXEdge)], 10.0),
			      "and the generic door reads it back");
			check([block valueTypeForDimension:(NSTextBlockBorderDimension | NSTextBlockMinXEdge)]
				      == NSTextBlockAbsoluteValueType,
			      "with its value type");
			[block setValue:50.0 type:NSTextBlockPercentageValueType
			   forDimension:(NSTextBlockPaddingDimension | NSTextBlockMaxYEdge)];
			check(close_enough([block widthForLayer:NSTextBlockPadding edge:NSTextBlockMaxYEdge], 50.0) &&
			      [block valueTypeForDimension:(NSTextBlockPaddingDimension | NSTextBlockMaxYEdge)]
				      == NSTextBlockPercentageValueType,
			      "and a PERCENTAGE dimension keeps its type as well as its number");

			/* 2. THE CONTENT WIDTH IS THE WIDTH DIMENSION, UNDER TWO NAMES. */
			[block setValue:120.0 type:NSTextBlockAbsoluteValueType forDimension:NSTextBlockWidth];
			check(close_enough([block contentWidth], 120.0) &&
			      [block contentWidthValueType] == NSTextBlockAbsoluteValueType,
			      "the WIDTH dimension is the content width, and its type with it");
			[block setContentWidth:60.0 type:NSTextBlockPercentageValueType];
			check(close_enough([block valueForDimension:NSTextBlockWidth], 60.0),
			      "and the named setter is the same field the generic door reads");

			/* 3. AND THE CONTENT WIDTH IS READ BY THE GEOMETRY: a box grows around the width that was SET, not around
			 * whatever rect the caller happened to pass. */
			[block setContentWidth:100.0 type:NSTextBlockAbsoluteValueType];
			grown = [block boundsRectForContentRect:NSMakeRect(0.0, 0.0, 40.0, 20.0) inRect:containing
						  textContainer:container characterRange:NSMakeRange(0, 1)];
			printf("  (note: a 40-point content rect through a 100-point block came out %.1f wide)\n",
			       (double)NSWidth(grown));
			check(close_enough(NSWidth(grown), 100.0 + 10.0),
			      "a 100-point content width plus the left border is what the box measures");
			[block setContentWidth:50.0 type:NSTextBlockPercentageValueType];
			grown = [block boundsRectForContentRect:NSMakeRect(0.0, 0.0, 40.0, 20.0) inRect:containing
						  textContainer:container characterRange:NSMakeRange(0, 1)];
			check(close_enough(NSWidth(grown), 100.0 + 10.0),
			      "and a 50-percent width resolves against the CONTAINING rect — 100 of 200, plus the border");
			[block setContentWidth:0.0 type:NSTextBlockAbsoluteValueType];
			grown = [block boundsRectForContentRect:NSMakeRect(0.0, 0.0, 40.0, 20.0) inRect:containing
						  textContainer:container characterRange:NSMakeRange(0, 1)];
			check(close_enough(NSWidth(grown), 40.0 + 10.0),
			      "and a block with NO content width grows around the rect it was given, as before");

			/* 4. A HEIGHT IS NOT A THING A BLOCK CAN SIZE, and the door answers zero rather than storing one. */
			[block setValue:99.0 type:NSTextBlockAbsoluteValueType forDimension:NSTextBlockHeight];
			check(close_enough([block valueForDimension:NSTextBlockHeight], 0.0),
			      "a HEIGHT dimension is answered 0: a block's height is its content's");

			/* 5. ONE COLOUR, FOUR EDGES — and the older name for the value type is the same answer. */
			[block setBorderColor:[NSColor redColor]];
			check([[block borderColorForEdge:NSTextBlockMinXEdge] isEqual:[NSColor redColor]] &&
			      [[block borderColorForEdge:NSTextBlockMaxYEdge] isEqual:[NSColor redColor]],
			      "`-setBorderColor:` colours all four edges at once");
			check([block widthValueTypeForLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge] ==
			      [block valueTypeForLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge],
			      "and `-widthValueTypeForLayer:edge:` is the value type under its older name");

			/* 6. THE ALIGNMENT ROUND-TRIPS, and a COPY carries the three new fields. */
			check([block verticalAlignment] == NSTextBlockTopAlignment,
			      "a fresh block aligns its content at the top");
			[block setVerticalAlignment:NSTextBlockMiddleAlignment];
			check([block verticalAlignment] == NSTextBlockMiddleAlignment,
			      "`-setVerticalAlignment:` round-trips");
			{
				NSTextBlock *copied = [block copy];

				check(close_enough([copied contentWidth], [block contentWidth]) &&
				      [copied verticalAlignment] == NSTextBlockMiddleAlignment,
				      "and a copy keeps the content width and the alignment — a copy that lost them would be a cell "
				      "with a different shape");
				[copied release];
			}
			[block release];
		}

		if (failures == 0) {
			printf("text_block_rects: all checks passed\n");
			return 0;
		}
		printf("text_block_rects: FAILURES\n");
		return 1;
	}
}
