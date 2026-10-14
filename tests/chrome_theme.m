/*
 * chrome_theme — does an XFWM theme's `.xpm` become the window chrome's buttons, at its own size?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE CLAIM IS THREE THINGS AND EACH IS A MEASUREMENT.** That this tier can READ an XPM at all (the pipeline's
 * decoders are PNG and JPEG, so nothing else could load one); that a resolved theme decides the chrome's GEOMETRY
 * — the strip's height and each button's rectangle — rather than being scaled into this file's constants; and that
 * the four STATES a theme ships are actually selected, by the window's key state and by the pointer.
 *
 * IT RUNS AGAINST `tests/fixtures/chrome`, WHICH IS AGORA'S OWN AND MIT — sixteen hand-written 6x8 XPMs, one per
 * button and state, each a single colour so a probe can tell which file was drawn. That is deliberate: the theme
 * that prompted this work is GPL, so it cannot be committed, and a test may not depend on a licence a checkout does
 * not carry. The GPL theme is read the same way and lives outside the repository.
 *
 * AND IT IS THE XPM READER'S OWN PROBE, because a decoder that answers the wrong pixels would make every other
 * check here pass by accident. `#336699` and a `None` pixel are read back before anything is drawn with them.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSEvent.h>
#import <AppKit/AGChromeTheme.h>
#import <AppKit/AGXPM.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

#define CW 100
#define CH 50

static int s_failed;
static int s_frameHeight;	/* the frame's height: the content PLUS the strip the theme sets */

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

/* A PIXEL BY WINDOW COORDINATE, which is what every rect in this test is written in. The rep counts rows from the
 * TOP and the painter's coordinates run up, so one subtraction is the whole conversion — and it is stated once so
 * a probe cannot quietly read the wrong row. */
static NSColor *at_win(NSBitmapImageRep *rep, int x, int windowY)
{
	return [rep colorAtX:x y:(s_frameHeight - 1 - windowY)];
}

static int is_rgb(NSColor *c, double r, double g, double b)
{
	return c != nil
		&& fabs([c redComponent] - r) < 0.03
		&& fabs([c greenComponent] - g) < 0.03
		&& fabs([c blueComponent] - b) < 0.03;
}

/* DRAW THE CHROME into a fresh rep over a white ground, at the FRAME's size — the surface the chrome actually has. */
static NSBitmapImageRep *draw_chrome(NSWindow *w)
{
	NSBitmapImageRep *rep = new_rep(CW, s_frameHeight);
	NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)s_frameHeight)] fill];
	[w cg_drawChromeInContext:ctx];
	return rep;
}

/* **THE CHROME'S HIT RECT, WHICH IS A TIER-INTERNAL DOOR AND REACHED THE WAY `tests/tracking_area.m` REACHES ITS
 * OWN.** A theme is loaded per process, so a test cannot ask for "the button under this point" any other way than
 * by moving the pointer there; this is the door the pointer's motion calls. */
@interface NSWindow (APPKITChromeThemeTest)
- (void)cg_updateTrackingForPoint:(NSPoint)windowPoint;
@end

/* **THE ABSOLUTE POINTER, WHICH ONLY A COMPOSITOR CAN SUPPLY AND ONLY A DRAG READS.** Declared so the offscreen
 * probe can put one on an event; without it the drag has only the relative fallback, which is the half that is
 * wrong for a fast hand. */
@interface NSEvent (APPKITGlobalPointTest)
- (void)cg_setGlobalPoint:(NSPoint)point;
@end

/* **THE DRAG'S MOVE IS DEFERRED TO THE END OF A PASS, so a probe has to make that pass.** Applying every motion
 * inside a frame would walk the window along the sampled path; the pass takes the latest. */
@interface NSWindow (APPKITPendingDragTest)
- (void)cg_applyPendingDrag;
@end

/* THE FIXTURE'S GEOMETRY, READ FROM THE THEME rather than written down twice: a 6x8 button, offset 2, spacing 1. */
static int s_buttonW, s_buttonH, s_offset;

static int close_x(void)    { return s_offset; }
static int hide_x(void)     { return s_offset + s_buttonW + 1; }
static int maximize_x(void) { return s_offset + 2 * (s_buttonW + 1); }
static int menu_x(void)     { return CW - s_offset - s_buttonW; }

int main(void)
{
	@autoreleasepool {
		/* 1. **THE READER FIRST**, because every check below is about a file it decoded. A two-pixel XPM with one
		 * `None` and one `#336699` exercises the header, the colour table, the transparency and the hex. */
		{
			const char *sample = "/* XPM */\nstatic char * s[] = {\n\"2 1 2 1\",\n"
					     "\"o\tc None\",\n\".\tc #336699\",\n\"o.\"\n};\n";
			AGXPMPixmap pixmap;

			memset(&pixmap, 0, sizeof pixmap);
			check(AGXPMParse(sample, strlen(sample), &pixmap) == 0, "a literal XPM parses");
			check(pixmap.width == 2 && pixmap.height == 1, "its size is read from the header");
			check(pixmap.pixels != NULL && pixmap.pixels[3] == 0,
			      "a `None` pixel comes out fully transparent");
			check(pixmap.pixels != NULL && pixmap.pixels[4] == 0x33 && pixmap.pixels[5] == 0x66
			      && pixmap.pixels[6] == 0x99 && pixmap.pixels[7] == 255,
			      "and a hex colour is written as its bytes");
			AGXPMPixmapFree(&pixmap);
		}

		/* 2. **THE THEME RESOLVES, AND ITS OWN NUMBERS ARE THE CHROME'S.** `AGORA_CHROME_THEME` is set to the
		 * fixture by the test's environment; nil here means the search or the reader failed before any drawing. */
		AGChromeTheme *theme = [AGChromeTheme sharedTheme];

		check(theme != nil, "the theme resolves from AGORA_CHROME_THEME");
		if (theme == nil) {
			printf("FAIL: no theme — the rest cannot be asked\n");
			return 1;
		}
		s_buttonW = (int)[theme buttonSize].width;
		s_buttonH = (int)[theme buttonSize].height;
		s_offset = (int)[theme buttonOffset];
		s_frameHeight = CH + (int)[theme titleBarHeight];
		check([theme titleBarHeight] == 8.0, "the strip is the THEME's height, not this file's 22");
		check(s_buttonW == 6 && s_buttonH == 8, "and a button is the theme's own 6x8, 1:1");
		check([theme buttonOffset] == 2.0 && [theme buttonSpacing] == 1.0,
		      "the themerc's offset and spacing are read");

		/* 3. **AND THE FRAME MATH AGREES**, which is the class method with no window to ask: 1:1 means the content
		 * frame grows by the theme's height and not by a constant. */
		{
			NSRect frame = [NSWindow frameRectForContentRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)CH)
							      styleMask:(NSTitledWindowMask | NSClosableWindowMask
									 | NSMiniaturizableWindowMask | NSResizableWindowMask)];

			check(frame.size.height == (CGFloat)s_frameHeight,
			      "a titled frame is the content plus the THEME's strip");
		}

		{
			NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)CH)
				styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
					   | NSResizableWindowMask)
				backing:NSBackingStoreBuffered defer:NO];
			const int y = CH + s_buttonH / 2;	/* the buttons fill the strip, so their middles are here */

			[w setTitle:@"Theme"];

			/* 4. **THE INACTIVE BUTTON, WHICH IS WHAT A WINDOW THAT IS NOT KEY WEARS.** `close-inactive` is
			 * `#00FF00`; the fixture gives every state a different colour precisely so this is unambiguous. */
			{
				NSBitmapImageRep *rep = draw_chrome(w);

				check(is_rgb(at_win(rep, close_x() + s_buttonW / 2, y), 0.0, 1.0, 0.0),
				      "a window that is NOT key draws the theme's INACTIVE close button");
				check(is_rgb(at_win(rep, menu_x() + s_buttonW / 2, y), 0.5, 0.5, 0.5),
				      "and the menu button is at the RIGHT edge, in its inactive colour");
				/* **AND THE BAR ITSELF IS THE THEME'S, NOT A FLAT FILL.** The corners are `top-left`/`top-right` and
				 * the middle is `title-1`…`title-5` tiled, so these three name a piece each: a chrome that read only
				 * the buttons would leave all three at the frame colour. */
				check(is_rgb(at_win(rep, 0, y), 0x0A / 255.0, 0x0A / 255.0, 0x0A / 255.0),
				      "the theme's INACTIVE top-left corner is drawn at the left edge");
				check(is_rgb(at_win(rep, CW - 1, y), 0x10 / 255.0, 0x10 / 255.0, 0x10 / 255.0),
				      "its inactive top-right corner at the right edge");
				check(is_rgb(at_win(rep, 85, y), 0x20 / 255.0, 0x20 / 255.0, 0x20 / 255.0),
				      "and its title pieces TILED between them");
				[rep release];
			}

			/* 5. **THE KEY WINDOW DRAWS THE ACTIVE ART.** `-makeKeyWindow` is the real door, so what is tested is
			 * the state the window really reports and not a flag set behind it. */
			{
				NSBitmapImageRep *rep;

				[w makeKeyWindow];
				rep = draw_chrome(w);
				check([w isKeyWindow] && is_rgb(at_win(rep, close_x() + s_buttonW / 2, y), 1.0, 0.0, 0.0),
				      "a KEY window draws the ACTIVE close button");
				check(is_rgb(at_win(rep, 0, y), 0x11 / 255.0, 0x22 / 255.0, 0x33 / 255.0),
				      "and its title bar's corners are the ACTIVE pieces");
				[rep release];
			}

			/* 6. **THE POINTER'S TWO STATES.** Moving the engine's point over the hide button prelights it; a press
			 * on the close button presses it; each is asked by pixels, and each would fail if the state were not
			 * selected — the fixture's four colours are all different. */
			{
				NSBitmapImageRep *rep;

				[w cg_updateTrackingForPoint:NSMakePoint((CGFloat)(hide_x() + s_buttonW / 2), (CGFloat)y)];
				rep = draw_chrome(w);
				check(is_rgb(at_win(rep, hide_x() + s_buttonW / 2, y), 0.5, 0.0, 0.0),
				      "the button UNDER THE POINTER draws its PRELIGHT art");
				[rep release];
			}
			{
				NSBitmapImageRep *rep;
				NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
					location:NSMakePoint((CGFloat)(close_x() + s_buttonW / 2), (CGFloat)y)
					modifierFlags:0 timestamp:0.0 windowNumber:[w windowNumber] context:nil
					eventNumber:0 clickCount:1 pressure:0.0f];

				[w sendEvent:down];
				rep = draw_chrome(w);
				check(is_rgb(at_win(rep, close_x() + s_buttonW / 2, y), 1.0, 1.0, 0.0),
				      "a PRESS on the close button draws its PRESSED art");
				[rep release];
			}

			/* 7. **A ROW IS A ROW: THE `None` PIXEL IS AT THE TOP.** The fixture's first pixel is transparent, and
			 * only the top-left pixel of a button — so the top shows the strip behind it and the BOTTOM shows the
			 * button's colour. A bitmap drawn upside down swaps those two, which is the one mistake a flip can make
			 * and the reason both ends are asked. */
			{
				NSBitmapImageRep *rep = draw_chrome(w);
				NSColor *top = at_win(rep, close_x(), CH + s_buttonH - 1);
				NSColor *bottom = at_win(rep, close_x(), CH);

				check(is_rgb(top, 0x11 / 255.0, 0x22 / 255.0, 0x33 / 255.0),
				      "the transparent top-left pixel of a button shows the theme's TITLE BAR through it");
				check(!is_rgb(bottom, 0x11 / 255.0, 0x22 / 255.0, 0x33 / 255.0),
				      "and the bottom-left pixel is the button's own colour — the image is not upside down");
				[rep release];
			}

			/* 8. **AND THE HAIRLINE BETWEEN THE CHROME AND THE CONTENT.** One dark grey point along the TOP row of the
			 * CONTENT, full width — which is the chrome's bottom edge as a person reads the window. It is the row
			 * BELOW the strip because a theme's buttons fill the strip, so a line on its last row would cut across
			 * the buttons' bottoms. */
			{
				NSBitmapImageRep *rep = draw_chrome(w);

				check(is_rgb(at_win(rep, 5, CH - 1), 0.45, 0.45, 0.45)
				      && is_rgb(at_win(rep, 50, CH - 1), 0.45, 0.45, 0.45)
				      && is_rgb(at_win(rep, CW - 5, CH - 1), 0.45, 0.45, 0.45),
				      "a grey HAIRLINE runs the full width between the chrome and the content");
				check(!is_rgb(at_win(rep, 50, CH - 2), 0.45, 0.45, 0.45),
				      "and it is one point, not a band");
				[rep release];
			}

			/* 9. **AND THE CHROME DRAGS THE WINDOW.** A press on the bar that misses the buttons starts a move, and the
			 * window's origin moves by exactly the pointer's own delta — the grabbed point stays under the pointer.
			 * Headless there is no seam to move a surface with, so what moves is the COCOA frame, which is the half
			 * `-setFrame:` updates either way and the half `AGWindowSetFrame` is told from. */
			{
				NSRect before = [w frame];
				NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
					location:NSMakePoint(50.0, CH + 4.0) modifierFlags:0 timestamp:0.0
					windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:0.0f];
				NSEvent *move = [NSEvent mouseEventWithType:NSLeftMouseDragged
					location:NSMakePoint(90.0, CH - 10.0) modifierFlags:0 timestamp:0.01
					windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:0.0f];
				NSEvent *up = [NSEvent mouseEventWithType:NSLeftMouseUp
					location:NSMakePoint(90.0, CH - 10.0) modifierFlags:0 timestamp:0.02
					windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:0.0f];

				[w sendEvent:down];
				[w sendEvent:move];
				[w cg_applyPendingDrag];	/* the pass would do this; the probe makes the pass */
				check(fabs([w frame].origin.x - (before.origin.x + 40.0)) < 0.5
				      && fabs([w frame].origin.y - (before.origin.y - 14.0)) < 0.5,
				      "a drag on the TITLE BAR moves the window by the pointer's own delta");

				/* AND A PRESS ON A BUTTON IS NOT A DRAG: the close button's own press must leave the frame where it
				 * is, or a click on a control would shove the window aside by however far the hand moved. */
				before = [w frame];
				[w sendEvent:[NSEvent mouseEventWithType:NSLeftMouseDown
					location:NSMakePoint((CGFloat)(close_x() + s_buttonW / 2), CH + 4.0)
					modifierFlags:0 timestamp:0.03 windowNumber:[w windowNumber] context:nil
					eventNumber:0 clickCount:1 pressure:0.0f]];
				[w sendEvent:up];
				check([w frame].origin.x == before.origin.x && [w frame].origin.y == before.origin.y,
				      "and a press on a BUTTON does not move the window");
			}

			/* 10. **AND THE ABSOLUTE POINTER, WHEN THE COMPOSITOR SENT ONE, IS WHAT THE DRAG USES.** The relative
			 * arithmetic above is only right while this client's frame and the compositor's surface agree — which a
			 * fast hand makes them stop doing. With an absolute pair the window goes to `pointer - offset`, which does
			 * not depend on where the window is at all. There is no compositor here, so the probe supplies the
			 * absolutes itself; `fn_translate` is what puts them on an event in a real run. */
			{
				NSRect before = [w frame];
				NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
					location:NSMakePoint(50.0, CH + 4.0) modifierFlags:0 timestamp:0.5
					windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:0.0f];
				NSEvent *move = [NSEvent mouseEventWithType:NSLeftMouseDragged
					location:NSMakePoint(0.0, 0.0) modifierFlags:0 timestamp:0.51
					windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:0.0f];

				[down cg_setGlobalPoint:NSMakePoint(200.0, 400.0)];
				[move cg_setGlobalPoint:NSMakePoint(260.0, 380.0)];
				[w sendEvent:down];
				[w sendEvent:move];
				[w cg_applyPendingDrag];
				/* The offset is the press minus the origin, so the new origin is the press origin plus (60,-20) — the
				 * POINTER's delta, whatever the window was doing. */
				check(fabs([w frame].origin.x - (before.origin.x + 60.0)) < 0.5
				      && fabs([w frame].origin.y - (before.origin.y - 20.0)) < 0.5,
				      "an ABSOLUTE pointer moves the window to `pointer - offset`, independent of its own position");
				[w sendEvent:[NSEvent mouseEventWithType:NSLeftMouseUp
					location:NSMakePoint(0.0, 0.0) modifierFlags:0 timestamp:0.52
					windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:0.0f]];
			}

			[w release];
		}
	}

	printf(s_failed == 0 ? "\nall checks passed\n" : "\n%d check(s) FAILED\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
