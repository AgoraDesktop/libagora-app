# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later
# Portions of this file may derive from GNUstep; see THIRD-PARTY.md.

#!/usr/bin/env python3
"""Read the compositor's own screenshot and assert that A MENU REACHED IT.

**THIS IS THE CHECK THE DISPLAY PATH DID NOT HAVE.** Everything else about menus is asserted offscreen — a bitmap
rep, a graphics context over it — which covers the CELL and the VIEW and covers NOTHING about whether either of
them reaches an output. The path from `NSMenuView -drawRect:` to a composited pixel runs through
`NSWindow -cg_drawFrame`, which is the only thing that presents, and no test went near it.

It found things twice: a four-row menu did not finish in twelve seconds because `+[NSFont systemFontOfSize:]` had
no cache and re-walked 118 font files per cell per frame, and before that a menu drew NOTHING AT ALL because the
tracking window had no content view and nothing presented it.
"""
import sys
from PIL import Image

PANEL = (235, 235, 235)      # the panel's colour, WHICH IS THE MENU BAR'S — the server's `AWS_MENU_BAR_COLOUR`
ROW = 22                     # NSMenuRowHeight
PAD = 2                      # NSMenuPanelPadding — the panel's own air, above, below and at the sides
BAR_ROWS = 24                # the menu bar's strip, which is a panel too and is NOT the dropdown


def is_panel_top(r, g, b):
    """The dropdown panel's TOP EDGE: EXACTLY the menu bar's colour, because the panel now IS that colour.

    **THIS DETECTOR USED TO KEY ON "BRIGHTER THAN THE BAR", AND THE MENU BEING THE BAR'S COLOUR IS THE CHANGE IT
    HAD TO SURVIVE.** The panel was a Snow-Leopard ramp of its own — 0.985 down to 0.925, 251 to 236 — while the
    bar was a flat 235, so the panel's top was the brightest neutral thing below the bar and `r >= 245` found it.
    The bar and the menus are the SAME colour now, so no brightness is left to key on; an EXACT match is what still
    separates the panel from everything else in the picture. The bar's own rows are excluded by row, and the
    wallpaper is not neutral at all.
    """
    return (r, g, b) == PANEL


def main():
    if len(sys.argv) < 2:
        print("usage: menu_shot.py SHOT.ppm")
        return 2
    im = Image.open(sys.argv[1]).convert("RGB")
    px = im.load()
    w, h = im.size
    # **THE MENU BAR IS A PANEL TOO, AND IT IS NOT THE DROPDOWN THIS TEST IS ABOUT.** An application's own menus
    # sit in a window of their own at the top of the screen, drawn by the same `NSMenuView`, so a bounding box over
    # EVERY panel pixel spans the bar AND the dropdown. MEASURED when the bar was added: "a whole number of
    # 22-pixel rows" began failing at 14 rows, because 14 was the distance from the bar's top to the dropdown's
    # bottom. The strip is excluded by row, which is the one thing that tells the two apart.
    # THE TOP EDGE FIRST: one row below the bar, the columns that are the panel's brightest shade.
    top_row = BAR_ROWS
    top_cols = [x for x in range(w) if is_panel_top(*px[x, top_row])]
    # **AND THE BOTTOM BY COUNTING ROWS THE PANEL IS STILL IN, NOT BY WALKING ONE COLUMN DOWN.** The panel's rows are
    # the run of rows below its top that contain the panel's colour at all — which is what makes the height a
    # measurement of the PANEL rather than of wherever its ink happens to be.
    #
    # **THE COLUMN WALK WAS RIGHT UNTIL A WINDOW COULD ROUND ITS CORNERS.** It walked the panel's padding column, one
    # point inside the panel's left edge — which is EXACTLY the column a rounded corner cuts. MEASURED, once the
    # compositor clipped windows to rounded corners, that column read 47 rows of 48 at a four-point radius and 12 of
    # 48 at six; the panel was right the whole time and the probe was measuring the corner.
    #
    # A ROW IS THE STURDIER UNIT. Text costs a row its ink but never its whole width — the spaces between the glyphs
    # are still the panel — and a rounded corner costs it a few pixels at each end, while the row past the panel's
    # bottom has none of the colour at all. FOUR PIXELS is the floor: a stray antialiased pixel on the wallpaper
    # cannot extend the panel by a row, and no row of the panel has fewer than four.
    panel = []
    if top_cols:
        left, right = min(top_cols), max(top_cols)
        for y in range(top_row, h):
            lit = sum(1 for x in range(left, right + 1) if px[x, y] == PANEL)

            if lit < 4:
                break
            panel.extend((x, y) for x in range(left, right + 1))

    checks = []
    if not panel:
        checks.append((f"a menu panel reached the composited output ({w}x{h})", False))
    else:
        xs = [p[0] for p in panel]
        ys = [p[1] for p in panel]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        ink = sum(1 for y in range(y0, y1 + 1) for x in range(x0, x1 + 1) if sum(px[x, y]) < 400)
        checks.append((f"a menu panel reached the composited output, {x1 - x0 + 1}x{y1 - y0 + 1} "
                       f"at ({x0},{y0})", True))
        checks.append((f"it is a whole number of {ROW}-pixel rows ({((y1 - y0 + 1) - 2*PAD) // ROW})",
                       ((y1 - y0 + 1) - 2*PAD) % ROW == 0 and ((y1 - y0 + 1) - 2*PAD) // ROW >= 2))
        checks.append((f"and its rows have TEXT in them ({ink} ink pixel(s))", ink > 0))
    failed = 0
    for name, ok in checks:
        print(f"  [{'ok' if ok else 'FAIL'}] {name}")
        failed += 0 if ok else 1
    print(f"check: {len(checks)} checks, {failed} failed" + (" -- all checks passed" if not failed else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
