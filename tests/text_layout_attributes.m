/*
 * text_layout_attributes.m — THE BACKGROUND AND THE UNDERLINE: THE TWO INK KEYS THE MANAGER NOW READS.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIM IS A COLOUR IN A PIXEL, WHICH IS THE ONLY WAY AN ATTRIBUTE THAT DRAWS SOMETHING BESIDES GLYPHS CAN BE
 * SEEN.** A foreground colour is gleaned from the glyphs themselves; a BACKGROUND fills the space BETWEEN and BEHIND
 * them, and an UNDERLINE is a rule BELOW the baseline where no glyph need be. So the probe draws each one alone and
 * counts its colour: green behind the line, blue below it, and — for the two-run case — two colours on one line.
 *
 * **AND THE RUN WALK IS WHAT MAKES THE TWO-RUN CASE THE POINT.** Before this slice the manager took ONE colour per
 * fragment; here a line whose text changes colour halfway, or changes background halfway, has to come out in BOTH —
 * which a single-colour-per-line draw cannot do. The double underline is the second claim of the same arithmetic: it
 * is two rules, so twice the ink of one.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGContext.h>
#include <math.h>
#include <stdio.h>

#define W 220
#define H 70

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* **THE SAME MIRROR THE OTHER DRAW PROBES USE**, because the manager lays in a flipped container's coordinates and a
 * rep's context is not flipped. Both draw doors are called, background first, so the ink order is the one a view uses. */
static NSBitmapImageRep *draw(NSLayoutManager *manager, BOOL background)
{
	NSBitmapImageRep *rep = new_rep();
	NSGraphicsContext *ctx;
	CGContextRef cg;
	NSUInteger n = [[[manager textStorage] string] length];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	cg = (CGContextRef)[ctx graphicsPort];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
	CGContextScaleCTM(cg, 1.0, -1.0);
	if (background) {
		[manager drawBackgroundForGlyphRange:NSMakeRange(0, n) atPoint:NSMakePoint(0.0, 0.0)];
	}
	[manager drawGlyphsForGlyphRange:NSMakeRange(0, n) atPoint:NSMakePoint(0.0, 0.0)];
	return rep;
}

/* HOW MANY PIXELS ARE (APPROXIMATELY) A GIVEN COLOUR, with a tolerance because a filled rectangle lands on whole
 * pixels while a colour read can round. */
static int count_colour(NSBitmapImageRep *rep, CGFloat r, CGFloat g, CGFloat b)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c == nil) {
				continue;
			}
			if (fabs([c redComponent] - r) < 0.2 && fabs([c greenComponent] - g) < 0.2
			    && fabs([c blueComponent] - b) < 0.2) {
				count++;
			}
		}
	}
	return count;
}

/* **AND A ONE-POINT RULE IS NOT A SOLID FILL, SO IT NEEDS A DIFFERENT QUESTION.** An underline is a hairline at a
 * fractional y, and the rasteriser anti-aliases its two half-covered rows: a pure-blue test finds NOTHING even though
 * the rule is plainly there — MEASURED, which is why this counter asks "is BLUE the dominant channel" rather than "is
 * this exactly blue". A filled rectangle the height of a line still passes it, and a half-covered hairline does too. */
static int count_bluish(NSBitmapImageRep *rep)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c == nil) {
				continue;
			}
			if ([c blueComponent] - [c redComponent] > 0.15 && [c blueComponent] - [c greenComponent] > 0.15
			    && [c blueComponent] > 0.4) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"abcd"];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 100.0)];
	NSRange all = NSMakeRange(0, 4);

	setvbuf(stdout, NULL, _IONBF, 0);
	[store addLayoutManager:manager];
	[manager addTextContainer:container];

	/* 1. **A BACKGROUND COLOUR FILLS THE LINE'S USED RECT, WHICH IS INK BESIDE THE GLYPHS AND NOT GLYPHS THEMSELVES.**
	 * Green behind black text: the glyphs and the ground are different colours in the same band. */
	{
		NSBitmapImageRep *rep;
		int green;

		[store addAttribute:NSBackgroundColorAttributeName value:[NSColor greenColor] range:all];
		rep = draw(manager, YES);
		green = count_colour(rep, 0.0, 1.0, 0.0);
		printf("  (note: a GREEN background attribute put %d green pixel(s) behind `abcd`)\n", green);
		check(green > 100, "the background attribute fills the line's used rect with its colour");
		[rep release];
		[store removeAttribute:NSBackgroundColorAttributeName range:all];
	}

	/* 2. **AND THE UNDERLINE IS A RULE BELOW THE BASELINE.** Blue, so the ink is separable from the glyphs; a single
	 * rule has some, none has none, and a double rule has more than one. */
	{
		NSBitmapImageRep *plain = draw(manager, NO);
		int none = count_bluish(plain);
		int single, doubleRule;

		[plain release];
		[store addAttribute:NSUnderlineColorAttributeName value:[NSColor blueColor] range:all];
		[store addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
			      range:all];
		{
			NSBitmapImageRep *rep = draw(manager, NO);

			single = count_bluish(rep);
			[rep release];
		}
		[store addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInteger:NSUnderlineStyleDouble]
			      range:all];
		{
			NSBitmapImageRep *rep = draw(manager, NO);

			doubleRule = count_bluish(rep);
			[rep release];
		}
		printf("  (note: blue pixels — no underline %d, single %d, double %d)\n", none, single, doubleRule);
		check(none == 0, "with no underline attribute there is no rule");
		check(single > 0, "a SINGLE underline draws a rule in the run's own colour");
		check(doubleRule > single, "and a DOUBLE underline draws TWO rules — measurably more ink than one");
		[store removeAttribute:NSUnderlineStyleAttributeName range:all];
		[store removeAttribute:NSUnderlineColorAttributeName range:all];
	}

	/* 3. **AND TWO RUNS ON ONE LINE ARE TWO COLOURS, WHICH IS THE RUN WALK ITSELF.** The first two characters red, the
	 * last two blue: both must appear, which one colour per line cannot produce. */
	{
		NSBitmapImageRep *rep;
		int red, blue;

		[store addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, 2)];
		[store addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:NSMakeRange(2, 2)];
		rep = draw(manager, NO);
		red = count_colour(rep, 1.0, 0.0, 0.0);
		blue = count_colour(rep, 0.0, 0.0, 1.0);
		printf("  (note: two foreground runs on one line gave %d red and %d blue pixel(s))\n", red, blue);
		check(red > 0 && blue > 0, "a line whose text changes colour halfway is drawn in BOTH colours");
		[rep release];
		[store removeAttribute:NSForegroundColorAttributeName range:all];
	}

	/* 4. **AND THE SAME IS TRUE OF TWO BACKGROUNDS**, which is the claim that makes the two rectangles two rather than
	 * one band. */
	{
		NSBitmapImageRep *rep;
		int green, yellow;

		[store addAttribute:NSBackgroundColorAttributeName value:[NSColor greenColor] range:NSMakeRange(0, 2)];
		[store addAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] range:NSMakeRange(2, 2)];
		rep = draw(manager, YES);
		green = count_colour(rep, 0.0, 1.0, 0.0);
		yellow = count_colour(rep, 1.0, 1.0, 0.0);
		printf("  (note: two background runs on one line gave %d green and %d yellow pixel(s))\n", green, yellow);
		check(green > 0 && yellow > 0, "two backgrounds on one line are TWO rectangles in two colours");
		[rep release];
		[store removeAttribute:NSBackgroundColorAttributeName range:all];
	}

	[container release];
	[manager release];
	[store release];
	[pool release];
	printf("text_layout_attributes: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
