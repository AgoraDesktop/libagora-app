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

PANEL = (240, 240, 240)      # NSMenuView's own panel colour
ROW = 22                     # NSMenuRowHeight
BAR_ROWS = 24                # the menu bar's strip, which is a panel too and is NOT the dropdown


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
    panel = [(x, y) for y in range(BAR_ROWS, h) for x in range(w) if px[x, y] == PANEL]

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
        checks.append((f"it is a whole number of {ROW}-pixel rows ({(y1 - y0 + 1) // ROW})",
                       (y1 - y0 + 1) % ROW == 0 and (y1 - y0 + 1) // ROW >= 2))
        checks.append((f"and its rows have TEXT in them ({ink} ink pixel(s))", ink > 0))
    failed = 0
    for name, ok in checks:
        print(f"  [{'ok' if ok else 'FAIL'}] {name}")
        failed += 0 if ok else 1
    print(f"check: {len(checks)} checks, {failed} failed" + (" -- all checks passed" if not failed else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
