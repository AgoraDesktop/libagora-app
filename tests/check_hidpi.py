#!/usr/bin/env python3
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: LGPL-3.0-or-later
"""Where did a shape drawn at a known POINT land, in DEVICE pixels?

usage: check_hidpi.py SHOT SCALE WIN_X WIN_Y WIN_W WIN_H

The client drew a white window (WIN_W x WIN_H points at WIN_X, WIN_Y) with one 20x20-point red square at (20, 20)
inside it. On an output of SCALE this must appear as:

    the window          WIN_W*SCALE x WIN_H*SCALE device pixels at (WIN_X*SCALE, WIN_Y*SCALE)
    the red square      20*SCALE square, 20*SCALE in from the window's left and bottom edges

A client that ignored the scale would draw the square 20 device pixels wide, 20 from the corner — half the size and
half the distance, which on a HiDPI screen is the whole UI shrunk into a corner.
"""
import sys


def read_ppm(path):
    with open(path, "rb") as handle:
        data = handle.read()
    fields, offset = [], 0
    while len(fields) < 4:
        while offset < len(data) and data[offset:offset + 1].isspace():
            offset += 1
        if data[offset:offset + 1] == b"#":
            while offset < len(data) and data[offset:offset + 1] != b"\n":
                offset += 1
            continue
        start = offset
        while offset < len(data) and not data[offset:offset + 1].isspace():
            offset += 1
        fields.append(data[start:offset])
    offset += 1
    width, height = int(fields[1]), int(fields[2])
    return width, height, data[offset:offset + width * height * 3]


def main():
    if len(sys.argv) != 7:
        print("usage: check_hidpi.py SHOT SCALE X Y W H", file=sys.stderr)
        return 2
    shot = sys.argv[1]
    scale, wx, wy, ww, wh = (int(v) for v in sys.argv[2:7])
    width, height, pixels = read_ppm(shot)
    failures = 0

    def at(x, y):
        base = (y * width + x) * 3
        return (pixels[base], pixels[base + 1], pixels[base + 2])

    def is_red(c):
        return c[0] > 170 and c[1] < 90 and c[2] < 90

    def is_white(c):
        return min(c) > 200

    def check(ok, what):
        nonlocal failures
        print(("  ok    " if ok else "  FAIL  ") + what)
        if not ok:
            failures += 1

    # **THE RED SQUARE IS THE ANCHOR, BECAUSE IT IS THE ONE THING WITH A KNOWN SIZE IN BOTH SPACES.** It is 20 points
    # across and 20 points in from the window's left and bottom edges, so: 20*scale device pixels, and those same
    # distances from the edges. Measuring the window's rectangle directly instead would mean encoding the title bar's
    # height and the flip the compositor applies to y — two facts this case is not about, and two ways to be wrong.
    red = [(x, y) for y in range(0, height) for x in range(0, width)
           if is_red(at(x, y))]
    if not red:
        check(False, "a red square was drawn at all")
        print("check_hidpi: %d failure(s)" % failures)
        return 1
    xs = [p[0] for p in red]
    ys = [p[1] for p in red]
    left, right = min(xs), max(xs)
    top, bottom = min(ys), max(ys)
    side = 20 * scale

    print("  (note: red spans device x %d..%d, y %d..%d)" % (left, right, top, bottom))
    check(abs((right - left + 1) - side) <= 2,
          "the 20-point square is %d DEVICE pixels across (measured %d)" % (side, right - left + 1))
    check(abs((bottom - top + 1) - side) <= 2,
          "and %d device pixels tall (measured %d)" % (side, bottom - top + 1))

    # ONE SQUARE, NOT TWO: a client that drew at both scales would leave a second, and a client that ignored the scale
    # would leave a 20-device-pixel one beside this one.
    check(len(red) <= side * side * 3, "there is ONE square of that size, not a smear or a second copy")

    # **AND ITS DISTANCE FROM THE WINDOW'S OWN EDGES IS THE SAME 20 POINTS.** The left edge is at 20*scale to the left
    # of the square and the bottom edge 20*scale below it, so the window's corner can be found from the square alone —
    # which is what makes this a test of the SCALE rather than of the title bar's height.
    win_left = left - 20 * scale
    win_bottom = bottom + 20 * scale
    check(is_white(at(win_left + 2, (top + bottom) // 2)),
          "the window's left edge is 20 points left of the square, at device x %d" % win_left)
    check(not is_white(at(win_left - 3, (top + bottom) // 2)),
          "and nothing of the window is outside it")
    check(is_white(at((left + right) // 2, win_bottom - 2)),
          "the window's bottom edge is 20 points below it, at device y %d" % win_bottom)

    # AND THE WINDOW IS WHERE IT WAS ASKED TO BE: its left edge is WIN_X points from the output's left, x scale.
    check(abs(win_left - wx * scale) <= 3,
          "the window is at WIN_X=%d points from the left, which is device x %d (measured %d)"
          % (wx, wx * scale, win_left))

    print("check_hidpi: %d failure(s)" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
