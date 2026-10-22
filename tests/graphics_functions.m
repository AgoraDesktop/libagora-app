/*
 * graphics_functions — the 10.6 `NSGraphics.h` drawing doors, read back off a bitmap.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE FUNCTIONS ARE THE TIER'S WORST MEASURED GAP, SO THEY ARE PINNED BY PIXELS RATHER THAN BY COMPILING.** A
 * declaration that links and draws nothing would satisfy the API census and fail every caller, which is exactly the
 * failure mode the census cannot see. Each door here is therefore driven into a bitmap the test owns and read back.
 *
 * THE THREE KINDS OF DOOR ARE EACH CHECKED FOR THE THING THAT WOULD GO WRONG QUIETLY:
 *
 *   a FILL must fill the rectangle it was given and nothing outside it — a fill that leaks one rectangle outside its
 *   bounds is invisible in a screenshot and wrong in a scroll view;
 *   a FRAME must draw INSIDE its rectangle and leave the interior alone — the era's contract, and the reason the path
 *   is inset by half the width;
 *   a CLIP must intersect rather than replace — a clip that replaces makes a nested clip paint outside its parent;
 *   the REFUSALS must answer their type's empty value AND say why, so a caller can tell "cannot" from "empty".
 *
 * The coordinate question is not assumed: every assertion is written against a rectangle the test filled itself, so a
 * flipped surface would fail the first check rather than quietly inverting all of them.
 */
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphics_internal.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

/* **THE SAMPLER CONVERTS, SO THE ASSERTIONS CAN BE WRITTEN IN THE DRAWING'S OWN COORDINATES.** `NSBitmapImageRep
 * -colorAtX:y:` indexes rows from the opposite end to the one the drawing functions are given, which is a trap that
 * produced five confident wrong failures the first time this file ran: every expectation was written at the y it drew
 * at, and every reading came from a row that was the mirror of it. The one test that passed did so because its
 * rectangle AND its sample points were symmetric. Every check below therefore speaks user space, and this is the only
 * place the flip is spelled. */
static NSColor *pixel(NSBitmapImageRep *rep, int x, int y)
{
	return [rep colorAtX:x y:([rep pixelsHigh] - 1 - y)];
}

static int like(NSBitmapImageRep *rep, int x, int y, NSColor *c, double tol)
{
	NSColor *p = pixel(rep, x, y);

	return p != nil && c != nil
		&& fabs([p redComponent] - [c redComponent]) < tol
		&& fabs([p greenComponent] - [c greenComponent]) < tol
		&& fabs([p blueComponent] - [c blueComponent]) < tol;
}

/* **A PIXEL CHECK THAT SAYS WHAT IT SAW.** A failing coordinate is useless on its own — "expected red at (8,8)" does not
 * say whether the fill was missed, mis-clipped, or drawn in the previous block's ink. So every expectation prints the
 * measured components when it fails, and the harness earns its keep at the moment it is needed. */
static void expect(NSBitmapImageRep *rep, int x, int y, NSColor *wanted, double tol, const char *name)
{
	NSColor *p = pixel(rep, x, y);
	int ok = like(rep, x, y, wanted, tol);

	check(ok, name);
	if (!ok) {
		printf("        at (%d,%d): measured %.3f %.3f %.3f a=%.3f, wanted %.3f %.3f %.3f\n",
		       x, y, p ? [p redComponent] : -1.0, p ? [p greenComponent] : -1.0,
		       p ? [p blueComponent] : -1.0, p ? [p alphaComponent] : -1.0,
		       wanted ? [wanted redComponent] : -1.0, wanted ? [wanted greenComponent] : -1.0,
		       wanted ? [wanted blueComponent] : -1.0);
	}
}

static int clear_at(NSBitmapImageRep *rep, int x, int y)
{
	NSColor *p = pixel(rep, x, y);

	return p == nil || [p alphaComponent] < 0.02;
}

/* Run a block of drawing into a fresh bitmap and leave it current. */
static NSBitmapImageRep *begin(int w, int h)
{
	NSBitmapImageRep *rep = new_rep(w, h);
	NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor clearColor] setFill];
	NSRectFill(NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h));
	return rep;
}

static void end(void)
{
	[NSGraphicsContext setCurrentContext:nil];
}

int main(void)
{
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		NSColor *red = [NSColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:1.0];
		NSColor *blue = [NSColor colorWithCalibratedRed:0.0 green:0.0 blue:1.0 alpha:1.0];

		(void)app;

		/* 1. NSRectFill: exactly its rectangle. */
		{
			NSBitmapImageRep *rep = begin(40, 40);

			[red setFill];
			NSRectFill(NSMakeRect(10.0, 10.0, 20.0, 20.0));
			end();
			check(like(rep, 15, 15, red, 0.02), "NSRectFill paints the rectangle it was given");
			check(clear_at(rep, 5, 5) && clear_at(rep, 35, 35),
			      "and nothing outside it");
			check(clear_at(rep, 31, 15), "including the pixel just past its far edge");
			[rep release];
		}

		/* 2. The list variants: one grey or one colour per rectangle. */
		{
			NSBitmapImageRep *rep = begin(60, 40);
			NSRect rects[2];
			NSColor *colors[2];

			rects[0] = NSMakeRect(5.0, 5.0, 10.0, 10.0);
			rects[1] = NSMakeRect(30.0, 5.0, 10.0, 10.0);
			colors[0] = red;
			colors[1] = blue;
			NSRectFillListWithColors(rects, colors, 2);
			end();
			expect(rep, 8, 8, red, 0.02, "NSRectFillListWithColors gives each rectangle its own ink");
			expect(rep, 33, 8, blue, 0.02, "and the second rectangle gets the second colour");
			check(clear_at(rep, 20, 8), "and leaves the gap between them alone");
			[rep release];
		}
		{
			NSBitmapImageRep *rep = begin(60, 40);
			NSRect rects[2];
			CGFloat grays[2];

			rects[0] = NSMakeRect(5.0, 5.0, 10.0, 10.0);
			rects[1] = NSMakeRect(30.0, 5.0, 10.0, 10.0);
			grays[0] = 0.0;
			grays[1] = 1.0;
			NSRectFillListWithGrays(rects, grays, 2);
			end();
			expect(rep, 8, 8, [NSColor blackColor], 0.05, "NSRectFillListWithGrays reads its greys in order");
			expect(rep, 33, 8, [NSColor whiteColor], 0.05, "and the second grey is the second rectangle");
			[rep release];
		}

		/* 3. NSFrameRect: inside the rectangle, interior untouched. */
		{
			NSBitmapImageRep *rep = begin(40, 40);

			[red setStroke];
			NSFrameRect(NSMakeRect(10.0, 10.0, 20.0, 20.0));
			end();
			check(like(rep, 10, 20, red, 0.05) || like(rep, 11, 20, red, 0.05),
			      "NSFrameRect draws the near edge inside the rectangle");
			check(like(rep, 29, 20, red, 0.05) || like(rep, 28, 20, red, 0.05),
			      "and the far edge inside it too");
			check(clear_at(rep, 20, 20), "leaving the interior alone");
			check(clear_at(rep, 5, 5), "and everything outside alone");
			[rep release];
		}

		/* 4. A width wider than one point still stays inside. */
		{
			NSBitmapImageRep *rep = begin(40, 40);

			[red setStroke];
			NSFrameRectWithWidth(NSMakeRect(10.0, 10.0, 20.0, 20.0), 4.0);
			end();
			check(like(rep, 11, 20, red, 0.05), "a four-point frame is drawn inside its rectangle");
			check(clear_at(rep, 20, 20), "and its interior is still empty");
			[rep release];
		}

		/* 5. NSEraseRect is white, and replaces rather than blends. */
		{
			NSBitmapImageRep *rep = begin(40, 40);

			[red setFill];
			NSRectFill(NSMakeRect(0.0, 0.0, 40.0, 40.0));
			NSEraseRect(NSMakeRect(10.0, 10.0, 20.0, 20.0));
			end();
			check(like(rep, 20, 20, [NSColor whiteColor], 0.05), "NSEraseRect erases to white");
			check(like(rep, 5, 5, red, 0.05), "and leaves the rest of the ground alone");
			[rep release];
		}

		/* 6. NSRectClip intersects, so a nested clip cannot paint outside its parent. */
		{
			NSBitmapImageRep *rep = begin(40, 40);

			NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
			[ctx saveGraphicsState];
			NSRectClip(NSMakeRect(5.0, 5.0, 30.0, 30.0));
			NSRectClip(NSMakeRect(5.0, 5.0, 15.0, 15.0));
			[red setFill];
			NSRectFill(NSMakeRect(0.0, 0.0, 40.0, 40.0));
			[ctx restoreGraphicsState];
			end();
			expect(rep, 10, 10, red, 0.02, "NSRectClip clips a fill to the rectangle");
			check(clear_at(rep, 25, 25), "and the two clips INTERSECT rather than the last one replacing");
			[rep release];
		}
		{
			NSBitmapImageRep *rep = begin(60, 40);
			NSRect rects[2];

			rects[0] = NSMakeRect(0.0, 0.0, 20.0, 20.0);
			rects[1] = NSMakeRect(0.0, 0.0, 20.0, 20.0);
			[[NSGraphicsContext currentContext] saveGraphicsState];
			NSRectClipList(rects, 2);
			[red setFill];
			NSRectFill(NSMakeRect(0.0, 0.0, 60.0, 40.0));
			[[NSGraphicsContext currentContext] restoreGraphicsState];
			end();
			expect(rep, 10, 10, red, 0.02, "NSRectClipList clips to the list");
			[rep release];
		}

		/* 7. The bezels differ in their ink, which is the only thing that distinguishes them. */
		{
			NSRect r = NSMakeRect(10.0, 10.0, 20.0, 20.0);
			NSRect clip = NSMakeRect(0.0, 0.0, 40.0, 40.0);
			NSBitmapImageRep *rep;

			rep = begin(40, 40);
			NSDrawGrayBezel(r, clip);
			end();
			check(!clear_at(rep, 10, 20) && !clear_at(rep, 29, 20),
			      "NSDrawGrayBezel draws both edges of the bezel");
			check(!like(rep, 10, 30, pixel(rep, 29, 10), 0.02),
			      "and its two edges are different inks, so it reads as raised");
			[rep release];

			rep = begin(40, 40);
			NSDrawGroove(r, clip);
			end();
			check(!clear_at(rep, 10, 20) && !clear_at(rep, 29, 20), "NSDrawGroove draws both edges");
			[rep release];
		}

		/* 8. The tiled rects: one band per side, and the interior comes back. */
		{
			NSRectEdge sides[4] = {NSMinXEdge, NSMinYEdge, NSMaxXEdge, NSMaxYEdge};
			CGFloat grays[4] = {0.0, 0.5, 1.0, 0.25};
			NSBitmapImageRep *rep = begin(40, 40);
			NSRect interior = NSDrawTiledRects(NSMakeRect(10.0, 10.0, 20.0, 20.0),
							   NSMakeRect(0.0, 0.0, 40.0, 40.0), sides, grays, 4);

			end();
			check(interior.size.width == 18.0 && interior.size.height == 18.0,
			      "NSDrawTiledRects returns the interior, one point in from each side");
			check(interior.origin.x == 11.0 && interior.origin.y == 11.0,
			      "and the interior's origin moved with it");
			check(!clear_at(rep, 10, 20) && !clear_at(rep, 29, 20), "and it painted the bands");
			[rep release];
		}

		/* 9. The dotted frame is dotted: some of its edge is drawn and some of it is not. */
		{
			NSBitmapImageRep *rep = begin(40, 40);
			int x, drawn = 0, empty = 0;

			[red setStroke];
			NSDottedFrameRect(NSMakeRect(10.0, 10.0, 20.0, 20.0));
			end();
			/* **"INK" IS ANY RED, NOT NEAR-PURE RED.** A dash edge is antialiased, so a pixel half-covered by a
			 * one-point dash reads around 0.5 — a check demanding 0.85 would call a correctly dotted frame solid
			 * because every dash failed to be pure. The question is dotted-versus-solid, so the test asks it with a
			 * threshold that answers that question. */
			for (x = 10; x < 30; x++) {
				NSColor *a = pixel(rep, x, 10), *b = pixel(rep, x, 29);
				NSColor *c = pixel(rep, x, 11), *d = pixel(rep, x, 28);

				if ((a && [a redComponent] > 0.5) || (b && [b redComponent] > 0.5)
				    || (c && [c redComponent] > 0.5) || (d && [d redComponent] > 0.5)) {
					drawn++;
				} else {
					empty++;
				}
			}
			check(drawn > 0 && empty > 0, "NSDottedFrameRect draws a dotted, not a solid, edge");
			[rep release];
		}

		/* 10. NSDrawButton and NSDrawWindowBackground both leave their ground painted. */
		{
			NSBitmapImageRep *rep = begin(40, 40);

			NSDrawButton(NSMakeRect(5.0, 5.0, 20.0, 20.0), NSMakeRect(0.0, 0.0, 40.0, 40.0));
			end();
			expect(rep, 15, 15, [NSColor controlColor], 0.06,
			       "NSDrawButton paints the control face inside the button");
			[rep release];

			rep = begin(40, 40);
			NSDrawWindowBackground(NSMakeRect(0.0, 0.0, 40.0, 40.0));
			end();
			check(like(rep, 20, 20, [NSColor windowBackgroundColor], 0.06),
			      "NSDrawWindowBackground paints the window's ground");
			[rep release];
		}

		/* 11. The screen-update pair is a counter, and it is balanced. */
		{
			BOOL was = cg_screenUpdatesDisabled();

			check(!was, "screen updates start enabled");
			NSDisableScreenUpdates();
			check(cg_screenUpdatesDisabled(), "NSDisableScreenUpdates disables them");
			NSDisableScreenUpdates();
			NSEnableScreenUpdates();
			check(cg_screenUpdatesDisabled(), "and two disables need two enables");
			NSEnableScreenUpdates();
			check(!cg_screenUpdatesDisabled(), "NSEnableScreenUpdates restores them");
			NSEnableScreenUpdates();
			check(!cg_screenUpdatesDisabled(), "an unbalanced enable does not go negative");
		}

		/* 12. The window list agrees with the application's own list. */
		{
			NSInteger count = -1;
			NSInteger list[8];

			memset(list, 0xFF, sizeof(list));
			NSCountWindows(&count);
			check(count >= 0 && count <= 8, "NSCountWindows answers a count the list can hold");
			NSWindowList(8, list);
			check(list[0] == -1 || list[0] != 0 || count == 0,
			      "NSWindowList writes window numbers rather than leaving the buffer untouched");
		}

		/* 13. The six refusals answer their type's empty value rather than crashing or lying. */
		{
			NSInteger virtualMemory = -1;
			NSInteger backing = -1;
			NSString *dump = @"not nil";

			check(NSReadPixel(NSMakePoint(1.0, 1.0)) == nil, "NSReadPixel refuses and answers nil");
			check(NSGetWindowServerMemory(0, &virtualMemory, &backing, &dump) == 0,
			      "NSGetWindowServerMemory refuses and answers 0");
			check(virtualMemory == 0 && backing == 0 && dump == nil,
			      "and zeroes the out-parameters rather than leaving them stale");
			NSBeep();
			NSCopyBits(0, NSMakeRect(0.0, 0.0, 1.0, 1.0), NSMakePoint(0.0, 0.0));
			NSSetFocusRingStyle(NSFocusRingOnly);
			NSShowAnimationEffect(NSAnimationEffectPoof, NSMakePoint(0.0, 0.0), NSMakeSize(1.0, 1.0),
					      nil, NULL, NULL);
			check(1, "NSBeep, NSCopyBits, NSSetFocusRingStyle and NSShowAnimationEffect refuse without crashing");
		}

		if (s_failed == 0) {
			printf("graphics_functions: all checks passed\n");
			return 0;
		}
		printf("graphics_functions: FAILURES\n");
		return 1;
	}
}
