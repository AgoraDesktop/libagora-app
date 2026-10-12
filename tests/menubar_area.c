/*
 * menubar_area — does the server say where an application's own menus may begin?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE ASSERTION IS THAT TWO QUESTIONS GET TWO ANSWERS.** The work area is a VERTICAL reserve for windows and
 * begins at x = 0, because the bar spans the whole screen — that is the Mac's `-visibleFrame` and it is not going
 * to change. The menu bar's usable region is a HORIZONTAL reserve and begins where the SYSTEM MENU's square ends.
 * A server that answered the second with the first would put every application's first menu under the System menu,
 * and the bug would look like an application laying itself out wrongly.
 */
#include "AGWindowServer.h"

#include <stdio.h>

static int failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		failed++;
	}
}

int main(void)
{
	AGWindowServer *server = AGWindowServerConnect();
	int wx = -1, wy = -1, ww = -1, wh = -1;
	int mx = -1, my = -1, mw = -1, mh = -1;

	if (server == NULL) {
		printf("SKIP: no compositor\n");
		return 77;
	}
	AGWindowServerWorkArea(server, &wx, &wy, &ww, &wh);
	AGWindowServerMenuBarArea(server, &mx, &my, &mw, &mh);
	printf("  work area     x=%d y=%d %dx%d\n", wx, wy, ww, wh);
	printf("  menu bar area x=%d y=%d %dx%d\n", mx, my, mw, mh);

	check(mw > 0 && mh > 0, "the server named a menu bar region at all");
	check(mx > 0, "and it does NOT begin at x = 0 — the System menu's square is in the way");
	/* **AND IT IS THE STRIP: `mh` IS THE WORK AREA'S `y`, WHICH IS WHAT THE RESERVE MEANS.** The work area begins
	 * below the bar, so the bar's height IS that offset — not `wh - wy`, which is the work area's own height and
	 * was this check's first, wrong, formula. */
	check(my == 0 && mh == wy, "it is the strip: at the top, and as tall as the work area's offset");
	check(mx + mw == ww, "and it runs to the same right edge the work area does");
	check(wx == 0, "while the WORK AREA still begins at x = 0, as the Mac's -visibleFrame does");
	AGWindowServerDisconnect(server);
	printf("menubar_area: %d case(s) failed\n", failed);
	return failed == 0 ? 0 : 1;
}
