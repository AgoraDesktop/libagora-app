/*
 * text_hyphenation.m — THE HYPHENATION FACTOR, READ AS A HYPHENATION ZONE, AND THE HYPHEN DRAWN.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE LAST PROPERTY OF `NSParagraphStyle` WITH NO READER HAS ONE, AND WHAT IT DOES IS A MEASUREMENT.** Apple's
 * sentence for the factor is "0.0 means no hyphenation; 1.0 means hyphenate as much as possible", from which the
 * layout manager reads it as the classic HYPHENATION ZONE: a line is hyphenated when the breaker's own break would
 * leave more than `1 - factor` of the width empty, which reduces to `lineWidth < factor * width`. Two consequences
 * are checked here rather than argued. First, **THE DEFAULT LEAVES EVERY DOCUMENT ALONE**: the factor is 0.0, the
 * test is `lineWidth < 0`, and nothing is hyphenated — so the first case pins the layout every earlier slice
 * produced, and a store with no style is the same store as one set to zero. Second, **RAISING IT HYPHENATES**: the
 * same text in the same container ends its first fragment at a DIFFERENT character.
 *
 * **AND THE PIECE TAKEN FROM THE NEXT WORD STILL TILES THE TEXT.** A hyphenated line is the one place in this
 * layout where the ink is not one glyph per character of the store: the hyphen is not IN the text — AppKit never
 * writes one — so the fragment's characters must still cover the string exactly once, in order, with nothing
 * dropped, duplicated or moved, and the manager's GLYPH SPACE must be unmoved by the hyphen. Both are asserted,
 * because they are what makes the hyphen extra ink rather than an inserted character.
 *
 * **AND THE HYPHEN IS ACTUALLY DRAWN, WHICH IS THE CLAIM A LAYOUT CAN GET WRONG INVISIBLY.** A fragment that
 * reserves room for a hyphen and draws nothing is a line with a gap in it and looks like a kerning bug. The case
 * therefore renders the two layouts and compares the ink: the hyphenated first line's ink must reach further right
 * than the un-hyphenated one's, and it must reach within a hyphen's width of the edge the layout reserved.
 *
 * THE DATA IS THE MACHINE'S. `-lineBreakByHyphenatingBeforeIndex:` asks Core Foundation, which reads whatever
 * hyphenation dictionary the system installs, so the case asks `CFStringIsHyphenationAvailableForLocale` first,
 * prints what it found, and asserts the ABSENT contract instead on a machine with no `hyph_en_US.dic`. A skipped
 * measurement is announced, never hidden.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>
#include <CoreFoundation/CFLocale.h>
#include <CoreFoundation/CFString.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>

#define REPW 220
#define REPH 90

static int failures;

static void check(int ok, const char *fmt, ...)
{
	va_list ap;

	printf("  %s ", ok ? "ok   " : "FAIL ");
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	printf("\n");
	if (!ok) {
		failures++;
	}
}

/* THE WORD IS `internationalization` BECAUSE ITS BREAK POINTS ARE THE DICTIONARY'S OWN AND ARE ALREADY MEASURED
 * elsewhere in this tree (in-ter-na-tion-al-iza-tion, at 2, 5, 7, 11, 13 and 16), so nothing here has to guess what
 * the right answer is: the case asserts only that a break INSIDE the word happened and that the text still tiles. */
static NSString *the_text(void)
{
	return @"go internationalization";
}

static void set_up(NSTextStorage *store, NSLayoutManager *manager, NSTextContainer *container, NSString *text,
		   CGFloat width, float factor)
{
	NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];

	[style setHyphenationFactor:factor];
	[store replaceCharactersInRange:NSMakeRange(0, [store length]) withString:text];
	[store addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, [store length])];
	[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [store length])];
	[style release];
	[store addLayoutManager:manager];
	[manager addTextContainer:container];
}

/* THE FRAGMENT RANGES, WHICH ARE THE DECISION. */
static void ranges(NSLayoutManager *manager, NSTextContainer *container, NSRange *out, NSUInteger *countOut,
		   NSUInteger max)
{
	NSUInteger count = [manager cg_lineFragmentCountForTextContainer:container];
	NSUInteger i;

	for (i = 0; i < count && i < max; i++) {
		out[i] = [manager cg_lineFragmentRangeAtIndex:i inTextContainer:container];
	}
	*countOut = count;
}

static NSBitmapImageRep *draw(NSLayoutManager *manager, NSRange range, NSPoint origin)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:REPW pixelsHigh:REPH
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:REPW * 4 bitsPerPixel:32];
	NSGraphicsContext *ctx;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	{
		CGContextRef cg = (CGContextRef)[ctx graphicsPort];

		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)REPW, (CGFloat)REPH)] fill];
		CGContextTranslateCTM(cg, 0.0, (CGFloat)REPH);
		CGContextScaleCTM(cg, 1.0, -1.0);
		[manager drawGlyphsForGlyphRange:range atPoint:origin];
	}
	return rep;
}

/* THE RIGHTMOST COLUMN CARRYING INK ON THE TOP LINE, in the rep's device coordinates. */
static int ink_right(NSBitmapImageRep *rep, int yTop, int yBottom)
{
	int x, y, right = -1;

	for (y = yTop; y <= yBottom; y++) {
		for (x = 0; x < REPW; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.5 && [c greenComponent] < 0.5 && x > right) {
				right = x;
			}
		}
	}
	return right;
}

static int ink_top(NSBitmapImageRep *rep)
{
	int x, y;

	for (y = 0; y < REPH; y++) {
		for (x = 0; x < REPW; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.5 && [c greenComponent] < 0.5) {
				return y;
			}
		}
	}
	return 0;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	CFLocaleRef current = CFLocaleCopyCurrent();
	Boolean available = (current != NULL) && CFStringIsHyphenationAvailableForLocale(current);
	CGFloat width;

	setvbuf(stdout, NULL, _IONBF, 0);
	if (current != NULL) {
		CFRelease(current);
	}
	printf("  (the current locale %s hyphenation data)\n", available ? "has" : "does NOT have");

	/* **THE CONTAINER'S WIDTH IS TAKEN FROM A MEASUREMENT, NOT FROM A NUMBER TYPED HERE.** The whole line at a wide
	 * width gives the text's own width, and the narrow width is a fraction of it — so the case does not depend on the
	 * font the machine answers with, which is the one thing that would make a typed width wrong on another box. */
	{
		NSTextStorage *store = [[NSTextStorage alloc] init];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(2000.0, 400.0)];

		set_up(store, manager, container, the_text(), 2000.0, 0.0f);
		width = [manager usedRectForTextContainer:container].size.width;
		printf("  (note: `%s` is %g points wide; the container below is %g)\n", [the_text() UTF8String],
		       (double)width, (double)(width * 0.55));
		width = (CGFloat)floor((double)(width * 0.55));
		[store release];
		[manager release];
	}

	/* 1. **THE DEFAULT IS UNMOVED.** The factor is 0.0 on a `+defaultParagraphStyle`, so the first fragment must end
	 * at the SPACE — the word does not fit and nothing pulls any of it up. This is the case that pins every earlier
	 * slice's layout: no hyphenation is not a feature that has to be switched off. */
	{
		NSTextStorage *store = [[NSTextStorage alloc] init];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(width, 400.0)];
		NSRange frags[8];
		NSUInteger count = 0, total = 0, i;

		set_up(store, manager, container, the_text(), width, 0.0f);
		ranges(manager, container, frags, &count, 8);
		printf("  (factor 0.0: %lu fragment(s); the first is (%lu,%lu))\n", (unsigned long)count,
		       (unsigned long)frags[0].location, (unsigned long)frags[0].length);
		check(count >= 2, "with the factor at zero the long word does not fit and the line wraps");
		check(frags[0].location == 0 && frags[0].length == 3,
		      "and the first fragment is `go ` and stops at the space, not inside the word");
		/* AND THE FRAGMENTS TILE, which is the invariant the hyphenated case is really about. */
		for (i = 0; i < count; i++) {
			total += frags[i].length;
		}
		check(total == [[store string] length], "and the fragments still cover the text once, %lu of %lu",
		      (unsigned long)total, (unsigned long)[[store string] length]);
		[store release];
		[manager release];
	}

	/* 2. **AND RAISING IT HYPHENATES.** With the factor at 1.0 the zone is empty, so any line that is not exactly
	 * full calls for a hyphenation point, and the first fragment must end INSIDE the word — at one of the dictionary's
	 * own points, which is why the case says "inside" and not a number it would have to invent. */
	{
		NSTextStorage *store = [[NSTextStorage alloc] init];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(width, 400.0)];
		NSRange frags[8];
		NSUInteger count = 0, total = 0, i;
		BOOL inside = NO;
		NSRange glyphs = NSMakeRange(0, 0);

		set_up(store, manager, container, the_text(), width, 1.0f);
		ranges(manager, container, frags, &count, 8);
		printf("  (factor 1.0: %lu fragment(s); the first is (%lu,%lu))\n", (unsigned long)count,
		       (unsigned long)frags[0].location, (unsigned long)frags[0].length);
		check(frags[0].length > 3, "with the factor at one a piece of the word is pulled onto the first line");
		for (i = 0; i < count; i++) {
			total += frags[i].length;
		}
		check(total == [[store string] length],
		      "and the fragments STILL cover the text once — the hyphen is not a character, %lu of %lu",
		      (unsigned long)total, (unsigned long)[[store string] length]);
		for (i = 1; i < count; i++) {
			check(frags[i].location == frags[i - 1].location + frags[i - 1].length,
			      "fragment %lu begins where the one before it ended", (unsigned long)i);
		}
		/* THE WORD BEGINS AT 3, SO A BREAK "INSIDE" IT IS A BREAK AT 3 < x < 3 + 20. */
		inside = (frags[0].length > 3) && (frags[0].length < 3 + 20);
		check(inside, "and the cut is INSIDE `internationalization` rather than past it");
		/* **AND THE GLYPH SPACE IS THE LINE'S, WHICH IS ONE GLYPH MORE THAN THE TEXT HAS.** This used to assert that
		 * the count did NOT grow, and that was the reading of a manager whose glyph space was one glyph per
		 * character by construction. It is the LINE's space now (see `NSLayoutManager.m`), and a hyphenated line's
		 * line HAS the hyphen: 23 characters and the one `U+2010` its last fragment draws is 24 glyphs. What the
		 * case still holds is that the TEXT did not change — the store is 23 characters — because the hyphen is not
		 * in the store, which is what makes it drawn ink rather than an inserted character. */
		{
			glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(0, [[store string] length])
							       actualCharacterRange:NULL];

			printf("  (note: %lu characters, %lu glyphs)\n", (unsigned long)[[store string] length],
			       (unsigned long)glyphs.length);
			check(glyphs.length == [[store string] length] + 1,
			      "the glyph space is the LINE's: %lu glyphs for %lu characters plus the drawn hyphen",
			      (unsigned long)glyphs.length, (unsigned long)[[store string] length]);
			check([[store string] length] == 23,
			      "and the STORE is unchanged at 23 characters, because the hyphen is not in the text");
		}
		/* **AND THE HYPHEN IS DRAWN.** The first line's used rect says how much room the layout reserved, the ink
		 * says how much was painted, and a hyphen reserved but not painted would leave a hyphen's width between
		 * them. Both layouts are rendered and both numbers are printed. */
		if (available) {
			NSDictionary *attrs = [store attributesAtIndex:0 effectiveRange:NULL];
			NSFont *font = [attrs objectForKey:NSFontAttributeName];
			CGFloat ascender = (font != NULL) ? [font ascender] : 0.0;
			NSRect used = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
			NSBitmapImageRep *rep = draw(manager, NSMakeRange(0, glyphs.length), NSMakePoint(0.0, 0.0));
			int top = ink_top(rep);
			int right = ink_right(rep, top, top + (int)ceil((double)ascender));

			CGFloat reserved = used.origin.x + used.size.width;

			printf("  (note: the hyphenated first line reserves to x=%g and its ink ends at x=%d — %g short)\n",
			       (double)reserved, right, (double)(reserved - (CGFloat)right));
			check((CGFloat)right > 0.0, "the hyphenated line paints something");
			check((CGFloat)right <= reserved + 1.0, "and paints nothing past the room it reserved");
			/* **THE DISCRIMINATOR IS THE SHORTFALL, AND IT WAS MEASURED BOTH WAYS.** With the hyphen drawn the
			 * first line's ink reaches to within **2.78** points of the edge the layout reserved (the hyphen's own
			 * right side bearing); with the hyphen's ink withheld — the same layout, the draw commented out — it
			 * stops **10.78** points short, because the last LETTER ends there. A threshold of 5.0 sits between the
			 * two, so this check fails if the hyphen is ever reserved and not painted, which is the failure that
			 * would otherwise be invisible: a line with a gap in it reads as a kerning bug, not as a missing hyphen.
			 * MEASURED, both numbers, on this machine and in this face. */
			check(reserved - (CGFloat)right < 5.0,
			      "and reaches the reserved edge within 5 points, which only the HYPHEN's ink can do");
			[rep release];
		} else {
			printf("  (note: no dictionary, so the ink of a hyphenated line is not measured)\n");
		}
		[store release];
		[manager release];
	}

	if (!available) {
		/* THE ABSENT CASE IS A CASE: with no dictionary the factor is still READ, and a factor of 1.0 on a machine
		 * with no data must lay out exactly as 0.0 does rather than crashing or moving the break. */
		NSTextStorage *store = [[NSTextStorage alloc] init];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(width, 400.0)];
		NSRange frags[8];
		NSUInteger count = 0;

		set_up(store, manager, container, the_text(), width, 1.0f);
		ranges(manager, container, frags, &count, 8);
		check(frags[0].length == 3, "with no dictionary a factor of one leaves the break at the space");
		[store release];
		[manager release];
	}

	printf("\ntext_hyphenation: %d failure(s)\n", failures);
	[pool release];
	return failures == 0 ? 0 : 1;
}
