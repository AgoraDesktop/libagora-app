/*
 * appkit_partial_damage — a window that repaints a strip tells the compositor about THE STRIP.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHAT THIS HOLDS UP. The client damaged its WHOLE buffer on every commit — `wl_surface_damage_buffer(0, 0, width,
 * height)` — so a terminal repainting one row of text made the compositor blend 1280x720, whatever the AppKit's own
 * damage tracking had worked out. `AGWindowDamage` is the seam door that names the rectangles instead, and this case is
 * the proof that the AppKit reaches it with the pixels it actually painted.
 *
 * THE QUESTION IS ASKED WHERE THE ANSWER LIVES: `AGWindowLastDamage` reports what the last commit told the compositor,
 * so the assertion is about the wire rather than about the AppKit's intention. Three things are checked:
 *
 *   1. A FULL PAINT DAMAGES THE WHOLE BUFFER. That is the default for a frame that names nothing, and it must not have
 *      been lost — a window whose first frame damaged a corner would show the rest of itself as whatever the buffer
 *      allocation held.
 *   2. A STRIP PAINT DAMAGES A STRIP. After the two-buffer ledger has warmed up (a full paint, then a paint or two),
 *      marking twenty pixels dirty must produce a damage whose AREA is a small fraction of the window's — and whose
 *      rectangles reach the paint, which is the half that keeps a missing pixel from being a stale one.
 *   3. AND THE RECTANGLES ARE IN THE COMPOSITOR'S SPACE: inside the buffer, non-empty, and in buffer pixels (which is
 *      not the window's point space at a fractional output scale — the whole point of a device-space door).
 *
 *   4. AND A STRIP'S ROWS ARE THE STRIP'S ROWS. Check 3's "inside the buffer" is a weak test: a fractional scale that
 *      was never applied to the y axis reports a band shifted by `height - height * scale` rows and every rectangle is
 *      still legal — MEASURED, it is how a Workspace file window came to leave a whole 192-row strip of the frame
 *      before it on the glass while naming 634 of 826 rows as changed. So the rows are compared with the ones the
 *      painted strip really occupies, in device pixels, at whatever scale the runner gave the compositor. At scale 1
 *      this check cannot fail, which is why the scaled runner (`run-appkit-scaled.sh`) exists beside the plain one.
 *
 * THE RUNNER SUPPLIES A COMPOSITOR, so a machine without one SKIPS (exit 77) rather than failing.
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

static int g_checks;
static int g_failed;

/* **THE WINDOW HAS TO BE CONFIGURED BEFORE IT CAN BE PAINTED.** The seam hands out a buffer only once the compositor
 * has configured the surface (and only when it is not holding the previous one), and both of those arrive on the
 * connection — so every paint in this case is preceded and followed by a turn of the run loop, which is the app's own
 * source-driven wait. */
static void pump(void)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static void check(int ok, const char *what, const char *detail)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s%s%s\n", what, (detail != NULL) ? " — " : "", (detail != NULL) ? detail : "");
	} else {
		printf("  [ok]   %s\n", what);
	}
}

/* THE TWO PRIVATE DOORS THIS CASE ASKS: the seam's window handle, and the damage the last commit reported. */
@interface NSWindow (AGSeamDamageDoor)
- (AGWindow *)cg_seamWindow;
@end

@interface AGPaintView : NSView
@end

@implementation AGPaintView
- (void)drawRect:(NSRect)dirtyRect
{
	[[NSColor whiteColor] set];
	NSRectFill(dirtyRect);
	[[NSColor blackColor] set];
	NSRectFill(NSMakeRect(4.0, 4.0, dirtyRect.size.width > 40.0 ? 40.0 : 4.0, 4.0));
}
@end

/* THE DAMAGE THE LAST COMMIT NAMED, as an area in BUFFER pixels and the rectangles themselves. */
struct damage_report {
	int count;
	long area;
	int inside;
	int empty;
};

static struct damage_report last_damage(NSWindow *window, int buffer_width, int buffer_height)
{
	struct damage_report report;
	AGWindow *seam = [window cg_seamWindow];
	int i;

	memset(&report, 0, sizeof(report));
	report.count = AGWindowLastDamage(seam, -1, NULL);
	report.inside = 1;
	for (i = 0; i < report.count && i < 16; i++) {
		int rect[4] = { 0, 0, 0, 0 };

		(void)AGWindowLastDamage(seam, i, rect);
		report.area += (long)rect[2] * (long)rect[3];
		if (rect[2] <= 0 || rect[3] <= 0) {
			report.empty = 1;
		}
		if (rect[0] < 0 || rect[1] < 0 || rect[0] + rect[2] > buffer_width ||
		    rect[1] + rect[3] > buffer_height) {
			report.inside = 0;
		}
	}
	return report;
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGPaintView *view;
		int buffer_width, buffer_height;
		long whole_area;
		int i;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 200.0)
						    styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						      backing:NSBackingStoreBuffered
							defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_partial_damage: NO WINDOW WAS MADE\n");
			return 1;
		}
		view = [[AGPaintView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		[window setContentView:view];
		[window orderFront:nil];

		/* **THE BUFFER IS THE WHOLE FRAME, NOT THE CONTENT.** The window reserves its title bar between the frame and
		 * the content, and the buffer covers both — so a damage rectangle is bounded by the FRAME's size at the output
		 * scale. Guessing the content's size here is what made the first version call a correct 20x20 strip "outside
		 * the buffer": its rows sit near the bottom of a buffer 22 points taller than the content. */
		{
			NSRect frame = [window frame];
			double scale = (double)[window userSpaceScaleFactor];

			buffer_width = (int)(frame.size.width * scale + 0.5);
			buffer_height = (int)(frame.size.height * scale + 0.5);
		}
		whole_area = (long)buffer_width * (long)buffer_height;
		printf("window frame %gx%g points, buffer %dx%d device pixels (scale %.3f)\n",
		       (double)[window frame].size.width, (double)[window frame].size.height, buffer_width,
		       buffer_height, (double)[window userSpaceScaleFactor]);

		/* 1. A FULL PAINT NAMES THE WHOLE BUFFER. */
		pump();
		[window display];
		pump();
		{
			struct damage_report report = last_damage(window, buffer_width, buffer_height);

			check(report.count >= 1, "the first frame damaged something", NULL);
			check(report.area >= whole_area, "a full paint damaged the WHOLE buffer (the caller named nothing)",
			      NULL);
			check(report.inside, "and its rectangle is inside the buffer", NULL);
		}

		/* 2. A STRIP PAINT NAMES A STRIP, once the two-buffer ledger is warm: the first paint into a buffer that
		 * has never been described is the whole frame by design, so a few passes are needed before a small repaint
		 * can be small. */
		for (i = 0; i < 4; i++) {
			[view setNeedsDisplayInRect:NSMakeRect(10.0, 10.0, 20.0, 20.0)];
			[window displayIfNeeded];
			pump();
		}
		{
			struct damage_report report = last_damage(window, buffer_width, buffer_height);
			char detail[160];

			snprintf(detail, sizeof(detail), "%d rect(s), %ld px of %ld (%.1f%%)", report.count,
				 report.area, whole_area, 100.0 * (double)report.area / (double)whole_area);
			check(report.count >= 1, "a strip repaint damaged something", NULL);
			check(report.area * 100 < whole_area * 30,
			      "and it is a STRIP rather than the whole window", detail);
			check(report.area > 0, "the damage is not empty", detail);
			check(report.inside, "with every rectangle inside the buffer", detail);
			check(!report.empty, "and none of them empty", detail);
		}

		/* 2b. **AND THE ROWS IT NAMED ARE THE STRIP'S OWN.** The strip was invalidated in POINTS at (10, 10) inside a
		 * view 200 points tall; the buffer is the whole frame in DEVICE pixels and its rows count down from its height.
		 * The painted rectangle is converted to window points first (`-convertRect:toView:` puts the content view's
		 * strip in the frame's space, title bar included) and only then multiplied by the scale — the two steps the
		 * damage reporter has to take, and the second one is the one that was missing. */
		{
			AGWindow *seam = [window cg_seamWindow];
			NSRect stripInWindow = [view convertRect:NSMakeRect(10.0, 10.0, 20.0, 20.0) toView:nil];
			double scale = (double)[window userSpaceScaleFactor];
			int expectedTop = buffer_height - (int)ceil((double)((stripInWindow.origin.y +
									 stripInWindow.size.height) * scale));
			int expectedBottom = buffer_height - (int)floor((double)(stripInWindow.origin.y * scale));
			int top = buffer_height;
			int bottom = 0;
			int rects = AGWindowLastDamage(seam, -1, NULL);
			char detail[200];
			int k;

			for (k = 0; k < rects && k < 16; k++) {
				int rect[4] = { 0, 0, 0, 0 };

				(void)AGWindowLastDamage(seam, k, rect);
				if (rect[1] < top) {
					top = rect[1];
				}
				if (rect[1] + rect[3] > bottom) {
					bottom = rect[1] + rect[3];
				}
			}
			snprintf(detail, sizeof(detail),
				 "rows %d..%d of %d, and the strip is rows %d..%d (scale %.3f)",
				 top, bottom, buffer_height, expectedTop, expectedBottom, scale);
			check(abs(top - expectedTop) <= 1 && abs(bottom - expectedBottom) <= 1,
			      "the damage's rows are the strip's rows in DEVICE pixels", detail);
		}

		/* 3. AND A FULL PAINT AFTER IT GOES BACK TO THE WHOLE BUFFER: the strip case must not have latched. */
		[view setNeedsDisplay:YES];
		[window display];
		pump();
		{
			struct damage_report report = last_damage(window, buffer_width, buffer_height);

			check(report.area >= whole_area, "a full paint still damages the whole buffer afterwards", NULL);
		}

		[window close];
		printf("%s (%d check%s)\n", g_failed ? "FAILURES" : "all checks passed", g_checks,
		       (g_checks == 1) ? "" : "s");
	}
	return g_failed ? 1 : 0;
}
