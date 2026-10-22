#!/usr/bin/env python3
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

"""Read the spike's own pixels back out of a screenshot.

The client cannot screenshot the compositor, so this is the independent half of the test: the markers the
client drew (red at buffer 0,0 and green at buffer W-1,H-1) are searched for in an X11 screenshot of the
nested compositor. Their positions prove orientation and that the shared-memory buffer reached an output;
the white bar's movement between two captures proves the compositor composited more than once.
"""
import sys
import numpy as np
from PIL import Image

RED = (224, 48, 48)
GREEN = (53, 192, 74)


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int16)


def matching(img, colour, tol=2):
    m = np.abs(img - np.array(colour, dtype=np.int16)).max(axis=2) <= tol
    ys, xs = np.nonzero(m)
    return set(zip(xs.tolist(), ys.tolist()))


def largest_blob(points):
    """The marker is a solid square; the desktop has other red and green on it, so take the biggest blob."""
    left = set(points)
    best = []
    while left:
        seed = left.pop()
        stack, cur = [seed], [seed]
        while stack:
            x, y = stack.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    p = (x + dx, y + dy)
                    if p in left:
                        left.discard(p)
                        stack.append(p)
                        cur.append(p)
        if len(cur) > len(best):
            best = cur
    xs = [p[0] for p in best]
    ys = [p[1] for p in best]
    return min(xs), min(ys), max(xs), max(ys), len(best)


def bar(img, rect):
    x0, y0, x1, y1 = rect
    band0, band1 = y0 + int((y1 - y0) * 0.30), y0 + int((y1 - y0) * 0.70)
    white = (img[:, :, 0] > 235) & (img[:, :, 1] > 235) & (img[:, :, 2] > 235)
    cols = [x for x in range(x0, x1 + 1) if white[band0:band1, x].mean() > 0.8]
    return (cols[0], cols[-1]) if cols else None


def deciles(img, x0, y0, x1, y1, axis):
    """Mean colour of the first and last tenth of a row or column, IGNORING near-white pixels. The moving
    bar is white and can sit against either edge, so sampling a fixed pixel made this check fail whenever the
    bar happened to be there -- which it did."""
    if axis == "x":
        line = img[(y0 + y1) // 2, x0:x1 + 1].astype(np.int32)
    else:
        line = img[y0:y1 + 1, (x0 + x1) // 2].astype(np.int32)
    keep = line[(line[:, 0] < 240) | (line[:, 1] < 240) | (line[:, 2] < 240)]
    if len(keep) < 10:
        keep = line
    n = max(1, len(keep) // 10)
    return keep[:n].mean(axis=0), keep[-n:].mean(axis=0)


def square(blob):
    """A marker is a square, but NOT necessarily a filled one. A real compositor ROUNDS THE WINDOW'S TOP
    CORNERS, and the red marker is drawn at buffer (0,0) — so its upper-left quarter comes back cut by a
    clean arc, identical in both captures. That is the compositor's decoration, not a stride or an
    orientation defect, so the assertion is a square bounding box that is mostly filled rather than a solid
    one; the corner checks below are what pin the orientation."""
    x0, y0, x1, y1, n = blob
    w, h = x1 - x0 + 1, y1 - y0 + 1
    return abs(w - h) <= 2 and n >= 0.5 * w * h


def main():
    if len(sys.argv) < 2:
        print("usage: inspect.py SHOT [SHOT2]")
        return 2
    a = load(sys.argv[0 + 1])
    red = largest_blob(matching(a, RED))
    green = largest_blob(matching(a, GREEN))
    rect = (red[0], red[1], green[2], green[3])
    w, h = rect[2] - rect[0] + 1, rect[3] - rect[1] + 1
    print(f"red marker   : {red[4]} px at ({red[0]},{red[1]})..({red[2]},{red[3]})")
    print(f"green marker : {green[4]} px at ({green[0]},{green[1]})..({green[2]},{green[3]})")
    print(f"window on screen: {w}x{h} at ({rect[0]},{rect[1]})")

    left, right = deciles(a, *rect, axis="x")
    top, bottom = deciles(a, *rect, axis="y")
    checks = [
        ("red marker is the top-left corner", (red[0], red[1]) == (rect[0], rect[1])),
        ("green marker is the bottom-right corner", (green[2], green[3]) == (rect[2], rect[3])),
        ("both markers are square (the upper-left one loses a wedge to the compositor's corner rounding)",
         square(red) and square(green)),
        (f"gradient R rises left to right ({left[0]:.0f} -> {right[0]:.0f})", right[0] > left[0] + 20),
        (f"gradient G rises top to bottom ({top[1]:.0f} -> {bottom[1]:.0f})", bottom[1] > top[1] + 20),
    ]

    ba = bar(a, rect)
    checks.append(("a white bar is present", ba is not None))
    if ba:
        print(f"white bar    : x {ba[0]}..{ba[1]}")

    if len(sys.argv) > 2:
        b = load(sys.argv[2])
        bb = bar(b, rect)
        if ba and bb:
            ca, cb = (ba[0] + ba[1]) // 2, (bb[0] + bb[1]) // 2
            print(f"bar moved    : {cb - ca:+d} px between the two captures")
            checks.append(("the bar MOVED between captures", cb != ca))
        else:
            checks.append(("the bar MOVED between captures", False))

    print()
    for name, ok in checks:
        print(f"  [{'ok' if ok else 'FAIL'}] {name}")
    return 0 if all(ok for _, ok in checks) else 1


if __name__ == "__main__":
    sys.exit(main())
