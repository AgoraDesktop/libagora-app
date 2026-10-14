/*
 * AGXPM.h — reading the X PixMap format, because an XFWM theme's window buttons ARE `.xpm`.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * WHY THIS EXISTS AT ALL. This tree's image pipeline decodes exactly two formats — PNG and JPEG, through Core
 * Graphics' own providers (see `NSBitmapImageRep +imageRepWithData:`) — and XPM is neither, so a theme's `.xpm`
 * files cannot go through `NSImage`. XPM is also TEXT rather than a compressed binary: it is a C array of string
 * literals holding a size, a colour table, and one string per row, which is why reading it is a parser of a few
 * dozen lines and not a codec.
 *
 * **IT IS NOT A PUBLIC API, AND THAT IS DELIBERATE.** Apple ships no XPM decoder, so putting one in Core Graphics
 * would be adding a door the API being matched does not have. This is Agora's own and private to the Application
 * Kit, and it is what lets the window chrome's buttons come from an XFWM theme rather than from something invented
 * here. A theme read from disk leaves Agora's MIT licensing untouched; only its FILES carry the theme's licence,
 * and this parser is Agora's code and carries none of it.
 *
 * WHAT IS SUPPORTED, AND WHAT IS REFUSED BY NAME. A colour entry is `None` (fully transparent) or a `#` run of hex
 * digits — 3, 6, 9 or 12, the four widths XPM defines — and an X11 colour NAME is refused rather than guessed at,
 * because guessing a name's RGB is inventing a colour table this file does not have. `cpp` (characters per pixel)
 * is honoured, so a theme that uses two-character keys parses.
 */
#ifndef AGORA_AGXPM_H
#define AGORA_AGXPM_H

#include <stddef.h>

/* AN XPM AS PIXELS: 8-bit RGBA, four bytes per pixel, rows TOP-DOWN. `pixels` is malloc'd and owned by the
 * caller (or transferred to whatever adopts it), and is NULL when a parse failed. */
typedef struct {
	unsigned int width;
	unsigned int height;
	unsigned char *pixels;	/* malloc'd width*height*4, or NULL */
} AGXPMPixmap;

/* 0 on success. On refusal a reason is printed to stderr and `out` is left with NULL pixels — a caller that has
 * the bytes but a broken theme should be told which of the two is wrong. */
int AGXPMParse(const char *bytes, size_t length, AGXPMPixmap *out);

/* Frees a parsed pixmap. Safe on a zeroed or already-freed one (it NULLs `pixels`). */
void AGXPMPixmapFree(AGXPMPixmap *pixmap);

#endif /* AGORA_AGXPM_H */
