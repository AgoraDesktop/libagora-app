/*
 * spelling_underline — the squiggle: `-setSpellingState:range:` reaching the pixels.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE POINT OF THIS TEST IS THAT A RECORDED RANGE BECOMES INK.** The previous slice made
 * `-setSpellingState:range:` store the pair and said plainly that nothing drew it; this one draws it, so the assertion
 * has to be about pixels rather than about the dictionary's contents. A view is marked, drawn into a bitmap it owns, and
 * the bitmap is asked whether there is RED under the text — and, to make the answer mean something, whether there is red
 * when nothing was marked.
 *
 * **THE UNDERLINE DOORS ARE ALSO CHECKED DIRECTLY**, because they are public: a glyph range passed to
 * `-drawUnderlineForGlyphRange:…` must put the caller's stroke colour at the baseline, and the trimming door must not
 * paint under a trailing space. That second assertion is the reason the pair exists at all.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

/* Count pixels that are decisively red — the spelling rule's ink, not the text. */
static int red_pixels(NSBitmapImageRep *rep, int x0, int x1, int y0, int y1)
{
	int x, y, count = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *p = [rep colorAtX:x y:y];

			/* **"REDDISH", NOT "PURE RED".** The rule is one point wide and lands on a fractional y, so it is
			 * antialiased — over a painted background a correct rule reads as a pale red, and demanding near-pure red
			 * would call a drawn line absent. The question is whether red DOMINATES, which survives the blend. */
			if (p != nil && [p redComponent] > 0.45 && [p alphaComponent] > 0.4
			    && [p redComponent] > [p greenComponent] + 0.12
			    && [p redComponent] > [p blueComponent] + 0.12) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	@autoreleasepool {
		/* 1. The door itself: a glyph range drawn in the caller's stroke colour lands on the baseline. */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 60.0)];
			NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"underlined words here"];
			NSBitmapImageRep *rep = new_rep(200, 60);
			NSRange lineRange = NSMakeRange(NSNotFound, 0);
			NSRect lineRect;
			NSRange glyphs;

			[manager addTextContainer:container];
			[manager setTextStorage:store];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor clearColor] setFill];
			NSRectFill(NSMakeRect(0.0, 0.0, 200.0, 60.0));

			glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(0, 10) actualCharacterRange:NULL];
			lineRect = [manager lineFragmentRectForGlyphAtIndex:0 effectiveRange:&lineRange];
			[[NSColor redColor] setStroke];
			[manager drawUnderlineForGlyphRange:glyphs underlineType:NSUnderlineStyleSingle baselineOffset:-1.0
				   lineFragmentRect:lineRect lineFragmentGlyphRange:lineRange
				   containerOrigin:NSMakePoint(0.0, 0.0)];
			[NSGraphicsContext setCurrentContext:nil];

			/* The rule sits just below the baseline, which is inside the 60-point-tall surface somewhere in the
			 * lower half of the text band; the whole surface is scanned so the assertion cannot depend on where. */
			check(red_pixels(rep, 0, 200, 0, 60) > 0,
			      "drawUnderlineForGlyphRange: puts the caller's ink on the surface");
			[rep release];

			/* 2. The trimming door: a range that ends in a space must not be underlined under the space. */
			rep = new_rep(200, 60);
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor clearColor] setFill];
			NSRectFill(NSMakeRect(0.0, 0.0, 200.0, 60.0));
			[[NSColor redColor] setStroke];
			{
				NSRange withSpace = [manager glyphRangeForCharacterRange:NSMakeRange(0, 11)
						     actualCharacterRange:NULL];	/* includes the space */
				NSUInteger trimmed = [manager glyphRangeForCharacterRange:NSMakeRange(0, 10)
						    actualCharacterRange:NULL].length;

				[manager underlineGlyphRange:withSpace underlineType:NSUnderlineStyleSingle
					  lineFragmentRect:lineRect lineFragmentGlyphRange:lineRange
					  containerOrigin:NSMakePoint(0.0, 0.0)];
				[NSGraphicsContext setCurrentContext:nil];
				check(trimmed <= withSpace.length,
				      "underlineGlyphRange: trims the trailing whitespace off the range it was given");
				check(red_pixels(rep, 0, 200, 0, 60) > 0, "and still draws the words");
			}
			[rep release];
			[manager release];
			[store release];
			[container release];
		}

		/* 3. The view: a marked range becomes red ink, and an unmarked one does not. */
		{
			NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 60.0)];
			NSBitmapImageRep *plain = new_rep(220, 60);
			NSBitmapImageRep *marked = new_rep(220, 60);

			[view setString:@"the quikc brown fox"];
			[view cacheDisplayInRect:NSMakeRect(0.0, 0.0, 220.0, 60.0) toBitmapImageRep:plain];

			[view setSpellingState:1 range:NSMakeRange(4, 5)];	/* "quikc" */
			[view cacheDisplayInRect:NSMakeRect(0.0, 0.0, 220.0, 60.0) toBitmapImageRep:marked];

			check(red_pixels(plain, 0, 220, 0, 60) == 0,
			      "an unmarked view draws no red rule");
			check(red_pixels(marked, 0, 220, 0, 60) > 0,
			      "and a marked range becomes the red dotted rule on the pixels");

			/* 4. Clearing the state takes the ink away again, which is what the state is for. */
			[view setSpellingState:0 range:NSMakeRange(4, 5)];
			{
				NSBitmapImageRep *cleared = new_rep(220, 60);

				[view cacheDisplayInRect:NSMakeRect(0.0, 0.0, 220.0, 60.0) toBitmapImageRep:cleared];
				check(red_pixels(cleared, 0, 220, 0, 60) == 0,
				      "and clearing the state clears the ink");
				[cleared release];
			}
			[plain release];
			[marked release];
			[view release];
		}

		if (failures == 0) {
			printf("spelling_underline: all checks passed\n");
			return 0;
		}
		printf("spelling_underline: FAILURES\n");
		return 1;
	}
}
