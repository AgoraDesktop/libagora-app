#!/usr/bin/env python3
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

"""system-images.py — the artwork behind `+[NSImage imageNamed:]`'s NSImageName… names.

WHAT THIS IS. Twenty named template images — back, forward, refresh, stop, add, remove, share, the two
full-screen arrows, Quick Look, the path chevron, the three view-mode marks, home and the two Trash faces —
drawn on the same 16-unit grid Bootstrap Icons uses and then rasterized to the two sizes the tier draws at.
Each glyph is DERIVED from a Bootstrap Icons shape (twbs/icons v1.13.2, MIT) and RESTYLED: the anchors and
proportions are Bootstrap's, while the ink is drawn as a 1.5-unit stroke with round caps and round joins
instead of a filled outline, which is what makes a glyph read like the era's toolbar art rather than like a
web glyph. The derivation is geometry and not pixels: nothing of Bootstrap's SVG text is copied.

THE OUTPUT IS A C TABLE, NOT A FILE. `SystemImageMasks.c` carries 8-bit coverage per glyph per size, and
`libagora-app` turns that into an image mask at load time — so an application gets the platform's named
images with no resource directory to install, no path to find and nothing to ship beside the library. That
is the same reason the chrome's marks are numbers in `NSWindow.m` rather than XFWM's `.xpm`: art that the
platform itself draws should not depend on somebody else's directory layout.

COVERAGE, NOT MASK SAMPLES. Each byte is how much of the pixel the glyph covers: 255 is solid ink, 0 is
empty. CoreGraphics' image masks are the inverse (0 paints), so `AGSystemImages` flips them on the way in,
in one place, where the reason is written down.

    ./tools/system-images.py            # rewrite art/system-images/*.svg and SystemImageMasks.[ch]
    ./tools/system-images.py --check    # exit 1 if the committed files are not what this would write

Needs `rsvg-convert` (librsvg) to rasterize; needs nothing else.
"""

import math
import os
import shutil
import subprocess
import sys

# The grid. Bootstrap Icons is drawn on 16 units; the stroke is 1.5 of them, which is the weight that reads
# as the era's ~1.5-point optical stroke at 16 points and still holds together at 32.
GRID = 16.0
STROKE = 1.5
# **THE SIZES THE TIER ACTUALLY DRAWS AT, NOT A POWER-OF-TWO PAIR.** A toolbar's regular item is 24 points and its
# small one 16; 32 is the high-resolution rep of the 16-point image. A stencil drawn at a size it was not made for
# is SCALED, and scaling was measurably blocky before the sampler interpolated — so the sizes that are asked for
# most are the sizes that are generated.
SIZES = (16, 24, 32)

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(HERE, "art", "system-images")
OUT_C = os.path.join(HERE, "SystemImageMasks.c")
OUT_H = os.path.join(HERE, "SystemImageMasks.h")
OUT_NAMES = os.path.join(HERE, "SystemImageNames.m")
OUT_NAMES_H = os.path.join(HERE, "SystemImageNames.h")


# ---- the drawing kit -------------------------------------------------------------------------------

def line(x1, y1, x2, y2):
    return "M%g %gL%g %g" % (x1, y1, x2, y2)


def poly(*points):
    head, rest = points[0], points[1:]
    return "M%g %g" % head + "".join("L%g %g" % p for p in rest)


def arc(cx, cy, r, start_deg, end_deg, steps=48):
    """A circular arc as a polyline. Polylines are exact enough at these sizes and, unlike a swept `A`, they
    rasterize identically in every renderer."""
    pts = []
    for i in range(steps + 1):
        a = math.radians(start_deg + (end_deg - start_deg) * i / steps)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return poly(*pts)


def circle(cx, cy, r):
    return ("M%g %g" % (cx - r, cy)) + \
           ("a%g %g 0 1 0 %g 0" % (r, r, 2 * r)) + \
           ("a%g %g 0 1 0 %g 0" % (r, r, -2 * r))


def rect(x, y, w, h, r=0.0):
    if r <= 0.0:
        return "M%g %gh%gv%gh%gz" % (x, y, w, h, -w)
    # A rounded rectangle as four arcs and four lines, so it strokes with round joins cleanly.
    return ("M%g %g" % (x + r, y) +
            "h%g" % (w - 2 * r) + "a%g %g 0 0 1 %g %g" % (r, r, r, r) +
            "v%g" % (h - 2 * r) + "a%g %g 0 0 1 %g %g" % (r, r, -r, r) +
            "h%g" % (2 * r - w) + "a%g %g 0 0 1 %g %g" % (r, r, -r, -r) +
            "v%g" % (2 * r - h) + "a%g %g 0 0 1 %g %g" % (r, r, r, -r) + "z")


def head(tip, toward_deg, size):
    """An arrow head at `tip`, opening back along `toward_deg` — two strokes, so it has round ends like the
    shaft it belongs to."""
    t = math.radians(toward_deg)
    a = t + math.radians(38)
    b = t - math.radians(38)
    return poly((tip[0] - size * math.cos(a), tip[1] - size * math.sin(a)), tip,
                (tip[0] - size * math.cos(b), tip[1] - size * math.sin(b)))


# ---- the glyphs ------------------------------------------------------------------------------------

GLYPHS = {}


def glyph(name, *parts):
    GLYPHS[name] = parts


# BACK AND FORWARD: a shaft with a barbed head, the head's arms at 38 degrees so it reads as a drawn arrow
# rather than a chevron bolted to a line.
# A SHAFT THAT STOPS AT THE HEAD'S SHOULDER, and a head long enough to read at sixteen pixels: Apple's arrow is
# mostly head, and a stub of shaft poking past the barb is what made the first version look like a nail.
glyph("go-left", line(13.5, 8.0, 5.6, 8.0), head((2.6, 8.0), 180.0, 6.0))
glyph("go-right", line(2.5, 8.0, 10.4, 8.0), head((13.4, 8.0), 0.0, 6.0))

# REFRESH: three quarters of a circle with the head on the clockwise end, which is Apple's arrangement.
# The gap sits at the top right, which is where the era put it, and the head is on the clockwise end of the
# sweep so the glyph reads "round again" rather than "reverse".
_END = -55.0
_START = _END + 290.0
_TIP_R = 5.2
glyph("refresh", arc(8.0, 8.0, 4.5, _END, _START),
      line(8.0 + 4.5 * math.cos(math.radians(_END)), 8.0 + 4.5 * math.sin(math.radians(_END)),
           8.0 + _TIP_R * math.cos(math.radians(_END)), 8.0 + _TIP_R * math.sin(math.radians(_END))),
      head((8.0 + _TIP_R * math.cos(math.radians(_END)), 8.0 + _TIP_R * math.sin(math.radians(_END))),
           _END - 90.0, 3.6))

# STOP, TWO FACES. The progress face is a circle with a square in it; the freestanding one is a plain X.
glyph("stop-progress", circle(8.0, 8.0, 6.1), rect(5.4, 5.4, 5.2, 5.2, 0.4))
glyph("stop-freestanding", line(4.0, 4.0, 12.0, 12.0), line(12.0, 4.0, 4.0, 12.0))

glyph("add", line(8.0, 2.8, 8.0, 13.2), line(2.8, 8.0, 13.2, 8.0))
glyph("remove", line(2.8, 8.0, 13.2, 8.0))

# SHARE (and the Action menu item that wears it): a box with its top left open and an arrow coming out.
glyph("share", poly((5.6, 7.3), (3.2, 7.3), (3.2, 13.0), (12.8, 13.0), (12.8, 7.3), (10.4, 7.3)),
      line(8.0, 9.8, 8.0, 3.2), head((8.0, 2.6), 90.0, 4.0))

# FULL SCREEN: two heads and shafts on the diagonal, out and in.
glyph("enter-fullscreen",
      poly((2.7, 9.3), (2.7, 13.3), (6.7, 13.3)), line(3.1, 12.9, 7.6, 8.4),
      poly((13.3, 6.7), (13.3, 2.7), (9.3, 2.7)), line(12.9, 3.1, 8.4, 7.6))
glyph("exit-fullscreen",
      line(2.7, 2.7, 6.6, 6.6), head((7.2, 7.2), 45.0, 4.4),
      line(13.3, 13.3, 9.4, 9.4), head((8.8, 8.8), 225.0, 4.4))

# QUICK LOOK: a lens and a pupil.
glyph("quicklook", poly((1.7, 8.0), (4.4, 4.7), (8.0, 3.4), (11.6, 4.7), (14.3, 8.0),
                        (11.6, 11.3), (8.0, 12.6), (4.4, 11.3), (1.7, 8.0)),
      circle(8.0, 8.0, 1.9))

glyph("path", poly((4.2, 6.1), (8.0, 9.9), (11.8, 6.1)))

# BOOKMARKS: a ribbon, which is the shape the era used for it.
glyph("bookmarks", poly((4.6, 2.8), (11.4, 2.8), (11.4, 13.2), (8.0, 10.1), (4.6, 13.2), (4.6, 2.8)))

# VIEW MODES. Icon view is the 2x2 field the era used; list view is bullets and rules; column view is three
# columns, the last one shorter because that is what a column view looks like when it has run out of levels.
glyph("icon-view", rect(2.6, 2.6, 4.9, 4.9, 0.8), rect(8.5, 2.6, 4.9, 4.9, 0.8),
      rect(2.6, 8.5, 4.9, 4.9, 0.8), rect(8.5, 8.5, 4.9, 4.9, 0.8))
glyph("list-view", line(5.6, 4.0, 13.4, 4.0), line(5.6, 8.0, 13.4, 8.0), line(5.6, 12.0, 13.4, 12.0),
      circle(3.2, 4.0, 0.85), circle(3.2, 8.0, 0.85), circle(3.2, 12.0, 0.85))
glyph("column-view", rect(2.2, 3.0, 3.9, 10.0, 0.7), rect(6.1, 2.5, 3.9, 11.0, 0.7),
      rect(10.0, 3.6, 3.9, 7.8, 0.7))

# HOME: roof and walls, one path so the eave has a round join.
glyph("home", poly((2.4, 7.5), (8.0, 2.6), (13.6, 7.5)), poly((4.2, 7.1), (4.2, 13.2), (11.8, 13.2), (11.8, 7.1)))

# TRASH: lid and handle, a tapering body, and two ribs. The full face fills the body.
glyph("trash-empty", line(2.9, 4.5, 13.1, 4.5), poly((6.1, 4.5), (6.1, 3.1), (9.9, 3.1), (9.9, 4.5)),
      poly((4.2, 4.5), (4.8, 13.3), (11.2, 13.3), (11.8, 4.5)),
      line(6.7, 6.6, 6.9, 11.2), line(9.3, 6.6, 9.1, 11.2))
glyph("trash-full", line(2.9, 4.5, 13.1, 4.5), poly((6.1, 4.5), (6.1, 3.1), (9.9, 3.1), (9.9, 4.5)),
      rect(4.7, 5.4, 6.6, 7.4, 0.5))


def svg_for(parts):
    body = "\n".join('  <path d="%s"/>' % p for p in parts)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" '
            'fill="none" stroke="#000" stroke-width="%g" stroke-linecap="round" stroke-linejoin="round">\n'
            '%s\n</svg>\n' % (STROKE, body))


# ---- what the AppKit names ask for ----------------------------------------------------------------

# The names Apple publishes, the glyph each one wears, and — because a few of them are the same picture under
# two names — the note that says so. `+[NSImage imageNamed:]` is the only reader.
NAMES = [
    ("NSImageNameGoLeftTemplate", "go-left", "the back button"),
    ("NSImageNameGoRightTemplate", "go-right", "the forward button"),
    ("NSImageNameRefreshTemplate", "refresh", "refresh, in a toolbar"),
    ("NSImageNameRefreshFreestandingTemplate", "refresh", "the same picture without a bezel to sit in"),
    ("NSImageNameStopProgressTemplate", "stop-progress", "stop a progress, in a bezel"),
    ("NSImageNameStopProgressFreestandingTemplate", "stop-freestanding", "stop a progress, on its own"),
    ("NSImageNameAddTemplate", "add", "add"),
    ("NSImageNameRemoveTemplate", "remove", "remove"),
    ("NSImageNameActionTemplate", "share", "the Action menu's own glyph"),
    ("NSImageNameEnterFullScreenTemplate", "enter-fullscreen", "enter full screen"),
    ("NSImageNameExitFullScreenTemplate", "exit-fullscreen", "leave full screen"),
    ("NSImageNameQuickLookTemplate", "quicklook", "Quick Look"),
    ("NSImageNamePathTemplate", "path", "the path control's chevron"),
    ("NSImageNameIconViewTemplate", "icon-view", "icon view"),
    ("NSImageNameListViewTemplate", "list-view", "list view"),
    ("NSImageNameColumnViewTemplate", "column-view", "column view"),
    ("NSImageNameBookmarksTemplate", "bookmarks", "bookmarks"),
    ("NSImageNameHomeTemplate", "home", "home"),
    ("NSImageNameTrashEmpty", "trash-empty", "an empty Trash"),
    ("NSImageNameTrashFull", "trash-full", "a full Trash"),
]


def render_coverage(name, size, workdir):
    """Rasterize one glyph at one size and answer its 8-bit COVERAGE, row by row."""
    svg = os.path.join(ART, name + ".svg")
    png = os.path.join(workdir, "%s-%d.png" % (name, size))
    out = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", png, svg],
                         capture_output=True)
    if out.returncode != 0:
        raise SystemExit("rsvg-convert failed for %s: %s" % (name, out.stderr.decode()))
    # Read the PNG with the standard library alone: an 8-bit RGBA PNG is a zlib stream of filter-prefixed rows,
    # and this only ever has to read what rsvg-convert writes.
    import zlib
    import struct
    with open(png, "rb") as handle:
        data = handle.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, width, height, depth, colour = 8, b"", 0, 0, 0, 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
        pos += 12 + length
    assert depth == 8 and colour in (4, 6), "expected 8-bit grey+alpha or RGBA"
    channels = 2 if colour == 4 else 4
    stride = width * channels
    raw = zlib.decompress(idat)
    rows, prev = [], bytearray(stride)
    at = 0
    for _ in range(height):
        filt = raw[at]
        at += 1
        row = bytearray(raw[at:at + stride])
        at += stride
        for i in range(stride):			# undo the five PNG filters
            a = row[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if filt == 1:
                row[i] = (row[i] + a) & 0xFF
            elif filt == 2:
                row[i] = (row[i] + b) & 0xFF
            elif filt == 3:
                row[i] = (row[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[i] = (row[i] + pred) & 0xFF
        rows.append(bytes(row[channels - 1::channels]))	# the ALPHA channel is the coverage
        prev = row
    return b"".join(rows)


def c_table(glyphs, coverage):
    lines = []
    for name in glyphs:
        for size in SIZES:
            data = coverage[(name, size)]
            lines.append("/* %s at %d points */" % (name, size))
            lines.append("static const unsigned char s_%s_%d[%d] = {" %
                         (name.replace("-", "_"), size, len(data)))
            for i in range(0, len(data), 16):
                lines.append("\t" + ", ".join("0x%02x" % b for b in data[i:i + 16]) + ",")
            lines.append("};")
    return "\n".join(lines) + "\n"


def main():
    check = "--check" in sys.argv
    if not os.path.isdir(ART):
        os.makedirs(ART)
    problems = []

    def write(path, text):
        if check:
            existing = open(path).read() if os.path.exists(path) else None
            if existing != text:
                problems.append(path)
        else:
            with open(path, "w") as handle:
                handle.write(text)

    for name in sorted(GLYPHS):
        write(os.path.join(ART, name + ".svg"), svg_for(GLYPHS[name]))

    if check and problems:
        print("out of date: " + ", ".join(os.path.relpath(p) for p in problems))
        return 1

    if shutil.which("rsvg-convert") is None:
        print("rsvg-convert is missing: the SVGs are written and the C table is not")
        return 1

    workdir = os.path.join(ART, ".raster")
    if not os.path.isdir(workdir):
        os.makedirs(workdir)
    coverage = {}
    for name in sorted(GLYPHS):
        for size in SIZES:
            coverage[(name, size)] = render_coverage(name, size, workdir)
    shutil.rmtree(workdir, ignore_errors=True)

    total = sum(len(v) for v in coverage.values())
    header = '''/*
 * SystemImageMasks.h — the coverage behind the platform's named images. GENERATED by tools/system-images.py;
 * edit the glyphs there, not here.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later AND MIT
 *
 * THE ART IS DERIVED FROM BOOTSTRAP ICONS v1.13.2 (MIT, © 2019-2024 The Bootstrap Authors) AND RESTYLED; see
 * art/system-images/PROVENANCE for the derivation and the notice, which travels with any copy of this table.
 *
 * A GLYPH IS THREE SIZES OF 8-BIT COVERAGE. Not colour: these are template images — one ink, chosen by the
 * control that draws them — so a glyph is a mask, and 255 means "this pixel is ink". `AGSystemImages` turns
 * a row into a CGImage mask (which is the INVERSE convention: a mask's 0 paints) at load time.
 */
#ifndef AGORA_SYSTEM_IMAGE_MASKS_H
#define AGORA_SYSTEM_IMAGE_MASKS_H

#include <stddef.h>

typedef struct {
\tconst char *name;		/* the glyph's own name, and the file it is drawn from */
\tconst unsigned char *coverage16;\t/* 16x16, 256 bytes, row-major, top row first */
\tconst unsigned char *coverage24;\t/* 24x24, 576 bytes: a toolbar's regular item, drawn 1:1 */
\tconst unsigned char *coverage32;\t/* 32x32, 1024 bytes, the same shape at twice the size */
} AGSystemImageGlyph;


/* One row per glyph, sorted by name; the count is `AGSystemImageGlyphCount`. */
extern const AGSystemImageGlyph AGSystemImageGlyphs[];
extern const size_t AGSystemImageGlyphCount;


#endif /* AGORA_SYSTEM_IMAGE_MASKS_H */
'''
    body = '''/*
 * SystemImageMasks.c — GENERATED by tools/system-images.py. Do not edit; see that file for the glyphs.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later AND MIT
 *
 * Derived from Bootstrap Icons v1.13.2 (MIT, © 2019-2024 The Bootstrap Authors), restyled as a stroke on their
 * 16-unit grid. The notice is in art/system-images/PROVENANCE and travels with this table.
 *
 * PLAIN C ON PURPOSE: this file is the pixels and nothing else, so it compiles into the library without
 * dragging Foundation into a translation unit that has no use for it.
 */
#include "SystemImageMasks.h"

''' + c_table(sorted(GLYPHS), coverage) + "\nconst AGSystemImageGlyph AGSystemImageGlyphs[] = {\n" + \
        "".join('\t{ "%s", s_%s_16, s_%s_24, s_%s_32 },\n' % (n, n.replace("-", "_"),
                                                              n.replace("-", "_"), n.replace("-", "_"))
                for n in sorted(GLYPHS)) + \
        "};\n\nconst size_t AGSystemImageGlyphCount = sizeof AGSystemImageGlyphs / sizeof AGSystemImageGlyphs[0];\n"

    names = '''/*
 * SystemImageNames.m — GENERATED by tools/system-images.py. Which glyph each `NSImageName…` wears.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later AND MIT
 *
 * **THE PAIRS ARE SPELLED WITH THE CONSTANTS AND NOT WITH THEIR STRINGS.** `NSImageNameGoLeftTemplate` is an
 * identifier whose value is a string this tree chose, so naming the identifier here means a rename breaks the
 * BUILD rather than the comparison — and a probe that walks this table walks exactly what `+imageNamed:` sees.
 */
#import "SystemImageNames.h"

#import <AppKit/NSImage.h>

#include "SystemImageMasks.h"

const AGSystemImageName AGSystemImageNames[] = {
''' + "".join('\t{ &%s, "%s" },\n' % (apple, glyph) for apple, glyph, _ in NAMES) + \
        "};\n\nconst size_t AGSystemImageNameCount = sizeof AGSystemImageNames / sizeof AGSystemImageNames[0];\n"

    names_header = '''/*
 * SystemImageNames.h — GENERATED by tools/system-images.py. Which glyph each `NSImageName…` wears.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later AND MIT
 *
 * **THE PAIRS ARE SPELLED WITH THE ADDRESSES OF THE CONSTANTS.** A global variable's VALUE is not a constant
 * expression in C, so `{ NSImageNameGoLeftTemplate, … }` does not compile in a static initializer while
 * `{ &NSImageNameGoLeftTemplate, … }` does. The address also keeps `NSImage.h` the single source of truth: a
 * rename breaks the build rather than quietly comparing against a string nobody updates.
 */
#ifndef AGORA_SYSTEM_IMAGE_NAMES_H
#define AGORA_SYSTEM_IMAGE_NAMES_H

#import <Foundation/NSString.h>
#import <stddef.h>

typedef struct {
	NSString *const *appleName;	/* ADDRESS of an `NSImageName…` constant */
	const char *glyph;		/* the row in `AGSystemImageGlyphs` that draws it */
} AGSystemImageName;

extern const AGSystemImageName AGSystemImageNames[];
extern const size_t AGSystemImageNameCount;

#endif /* AGORA_SYSTEM_IMAGE_NAMES_H */
'''

    write(OUT_H, header)
    write(OUT_C, body)
    write(OUT_NAMES, names)
    write(OUT_NAMES_H, names_header)
    if check and problems:
        print("out of date: " + ", ".join(os.path.relpath(p) for p in problems))
        return 1
    print("%d glyphs, %d coverage bytes, %d names" % (len(GLYPHS), total, len(NAMES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
