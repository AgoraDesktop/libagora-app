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

PANEL = (240, 240, 240)      # the OLD flat panel colour, kept only as the record of what this used to key on
ROW = 22                     # NSMenuRowHeight
PAD = 4                      # NSMenuPanelPadding — the panel's own air, above, below and at the sides
BAR_ROWS = 24                # the menu bar's strip, which is a panel too and is NOT the dropdown
BORDER = 139                 # the dropdown's own hairline border, and nothing else in the picture has it


def is_panel_top(r, g, b):
    """The dropdown panel's TOP EDGE: neutral, and brighter than the menu bar.

    **THE MARKER USED TO BE THE PANEL'S BORDER, AND THE BORDER IS GONE.** That is the change this detector had to
    survive: it matched "a neutral grey in the 120..165 band", which was `APPKIT_MENU_PANEL_BORDER` (0.545) and
    nothing else in the scene — so with the hairline removed it started matching the antialiased pixels of the menu's
    own TEXT instead, and the box it returned was the text's spread rather than the panel's (MEASURED: 133x32, which
    is not a whole number of rows, where the panel is 155x44).

    WHAT IDENTIFIES A PANEL NOW IS ITS OWN COLOUR. The panel's ramp runs 0.985 down to 0.925 (251 to 236), the menu
    bar is a flat 235 and the window behind it a flat 237, and the wallpaper is not neutral at all — so the panel's
    TOP is the brightest neutral thing below the bar, and that is what this finds. Its BOTTOM cannot be found by
    colour alone, because the end of the ramp is one level BELOW the window's grey; the walk in `main` uses
    neutrality instead, which the wallpaper fails and the panel passes.
    """
    return abs(r - g) < 4 and abs(g - b) < 4 and r >= 245


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
    # **AND THE BOTTOM BY WALKING DOWN THE MIDDLE OF IT.** The panel is a ramp and the wallpaper is not neutral, so
    # the panel's own rows are exactly the run of neutral pixels below its top — which is what makes the height a
    # measurement of the panel rather than of wherever its ink happens to be.
    panel = []
    if top_cols:
        midx = (min(top_cols) + max(top_cols)) // 2
        for y in range(top_row, h):
            r, g, b = px[midx, y]
            if not (abs(r - g) < 4 and abs(g - b) < 4):
                break
            panel.extend((x, y) for x in range(min(top_cols), max(top_cols) + 1))

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
