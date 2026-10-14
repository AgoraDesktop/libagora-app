/*
 * AGXPM.c — the XPM parser behind `AGXPM.h`.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#include "AGXPM.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ============================================================================================ *
 * THE STRING LITERALS, IN ORDER, WHICH IS THE WHOLE OF THE STRUCTURE THIS FILE READS.           *
 *                                                                                                *
 * An XPM is a C array: `static char *name[] = { "6 8 2 1", "o\tc None", ".", "o.....", ... }`,  *
 * and every piece of the format is ONE QUOTED STRING — the size first, then one per colour,     *
 * then one per row. So the parser collects the literals and never looks at the braces, the      *
 * `static` or the banner comment, which is what makes it independent of how the file was         *
 * formatted. `cpp` (the header's fourth number) is what splits a key from a pixel, so nothing    *
 * here has to know that a key may be a space or a tab.                                           *
 * ============================================================================================ */

typedef struct {
	char **items;
	int count;
	int capacity;
} fn_string_list;

static void fn_list_free(fn_string_list *list)
{
	int i;

	for (i = 0; i < list->count; i++) {
		free(list->items[i]);
	}
	free(list->items);
	list->items = NULL;
	list->count = 0;
	list->capacity = 0;
}

static int fn_list_push(fn_string_list *list, char *owned)
{
	if (list->count == list->capacity) {
		int grown = (list->capacity == 0) ? 64 : list->capacity * 2;
		char **next = realloc(list->items, (size_t)grown * sizeof *next);

		if (next == NULL) {
			free(owned);
			return -1;
		}
		list->items = next;
		list->capacity = grown;
	}
	list->items[list->count++] = owned;
	return 0;
}

/* Every double-quoted literal, unescaped. `\"` and `\\` are the only escapes an XPM needs and the only two
 * honoured; any other backslash is copied through with its character, which is what a C compiler would NOT do but
 * is the honest reading of a file that only ever escapes a quote. */
static int fn_collect_strings(const char *bytes, size_t length, fn_string_list *out)
{
	size_t i = 0;

	memset(out, 0, sizeof *out);
	while (i < length) {
		size_t start;
		char *value;
		size_t vlen = 0;

		if (bytes[i] != '"') {
			i++;
			continue;
		}
		i++;
		start = i;
		value = malloc(length - start + 1);
		if (value == NULL) {
			fn_list_free(out);
			return -1;
		}
		while (i < length && bytes[i] != '"') {
			if (bytes[i] == '\\' && i + 1 < length &&
			    (bytes[i + 1] == '"' || bytes[i + 1] == '\\')) {
				value[vlen++] = bytes[i + 1];
				i += 2;
				continue;
			}
			value[vlen++] = bytes[i++];
		}
		if (i >= length) {	/* an unterminated literal is a broken file, not a short one */
			free(value);
			fn_list_free(out);
			return -1;
		}
		i++;			/* the closing quote */
		value[vlen] = '\0';
		if (fn_list_push(out, value) != 0) {
			fn_list_free(out);
			return -1;
		}
	}
	return 0;
}

/* ============================================================================================ *
 * COLOURS.                                                                                      *
 * ============================================================================================ */

/* `#RRGGBB`, `#RGB`, `#RRRGGGBBB` and `#RRRRGGGGBBBB` — the four widths XPM defines — each channel scaled to 8
 * bits by its own maximum. The rounding adds half the maximum before dividing so that a mid-scale value does not
 * truncate downward; with our sources (2- and 4-digit-per-channel values are whole multiples of 17 and 257) it
 * changes nothing, and it is stated for the widths that are not. */
static int fn_parse_hex(const char *s, unsigned char out[3])
{
	size_t n = strlen(s);
	size_t per, i;

	if (n != 3 && n != 6 && n != 9 && n != 12) {
		return -1;
	}
	per = n / 3;
	for (i = 0; i < 3; i++) {
		char channel[5];
		char *end = NULL;
		unsigned long value;
		unsigned long maximum;

		memcpy(channel, s + i * per, per);
		channel[per] = '\0';
		value = strtoul(channel, &end, 16);
		if (end == channel || *end != '\0') {
			return -1;
		}
		maximum = (per >= 4) ? 65535UL : ((1UL << (4 * per)) - 1UL);
		out[i] = (unsigned char)((value * 255UL + maximum / 2UL) / maximum);
	}
	return 0;
}

/* ONE COLOUR ENTRY: the key is the first `cpp` characters, then the format's own key letters, of which only `c`
 * (colour) is read. A name rather than `None` or `#…` is REFUSED — the X11 colour table is not in this file, and
 * inventing a colour for a name would be exactly the kind of guess the refusals elsewhere make a point of not
 * making. Returns 0 and fills `rgba`, which starts fully transparent so that an entry with no `c` key reads as
 * transparent rather than as black. */
static int fn_parse_colour(const char *s, unsigned cpp, unsigned char rgba[4])
{
	size_t length = strlen(s);
	size_t i = cpp;

	rgba[0] = rgba[1] = rgba[2] = rgba[3] = 0;
	while (i < length) {
		char key[8];
		size_t k = 0;
		size_t vstart;
		char value[64];
		size_t v = 0;

		while (i < length && isspace((unsigned char)s[i])) {
			i++;
		}
		while (i < length && !isspace((unsigned char)s[i]) && k + 1 < sizeof key) {
			key[k++] = s[i++];
		}
		key[k] = '\0';
		while (i < length && isspace((unsigned char)s[i])) {
			i++;
		}
		vstart = i;
		while (i < length && !isspace((unsigned char)s[i])) {
			i++;
		}
		while (vstart < i && v + 1 < sizeof value) {
			value[v++] = s[vstart++];
		}
		value[v] = '\0';
		if (k == 0 || v == 0) {
			break;
		}
		if (strcmp(key, "c") != 0) {
			continue;	/* m / g / g4 / s describe other visuals; the colour is what is drawn */
		}
		if (strcmp(value, "None") == 0) {
			return 0;	/* already transparent */
		}
		if (value[0] != '#') {
			fprintf(stderr, "AGXPM-REFUSE: the colour name \"%s\" is not read — only `None` and `#` "
					"hex are, because the X11 colour table is not in this tree\n", value);
			return -1;
		}
		if (fn_parse_hex(value + 1, rgba) != 0) {
			fprintf(stderr, "AGXPM-REFUSE: \"%s\" is not a hex colour of 3, 6, 9 or 12 digits\n", value);
			return -1;
		}
		rgba[3] = 255;
		return 0;
	}
	return 0;
}

static int fn_colour_index(const char *keys, unsigned ncolors, unsigned cpp, const char *pixel)
{
	unsigned c;

	for (c = 0; c < ncolors; c++) {
		if (memcmp(keys + (size_t)c * cpp, pixel, cpp) == 0) {
			return (int)c;
		}
	}
	return -1;
}

int AGXPMParse(const char *bytes, size_t length, AGXPMPixmap *out)
{
	fn_string_list strings;
	unsigned width = 0, height = 0, ncolors = 0, cpp = 0;
	unsigned char *rgba = NULL;
	char *keys = NULL;
	unsigned char *pixels = NULL;
	unsigned c;
	unsigned y, x;

	if (out == NULL) {
		return -1;
	}
	out->width = out->height = 0;
	out->pixels = NULL;
	if (bytes == NULL || length == 0) {
		fprintf(stderr, "AGXPM-REFUSE: no bytes to parse\n");
		return -1;
	}
	if (fn_collect_strings(bytes, length, &strings) != 0 || strings.count < 1) {
		fprintf(stderr, "AGXPM-REFUSE: no string literals — this is not an XPM\n");
		return -1;
	}
	if (sscanf(strings.items[0], "%u %u %u %u", &width, &height, &ncolors, &cpp) != 4 ||
	    width == 0 || height == 0 || ncolors == 0 || cpp == 0 || cpp > 4) {
		fprintf(stderr, "AGXPM-REFUSE: the header \"%s\" is not `width height ncolors cpp`\n",
			strings.items[0]);
		fn_list_free(&strings);
		return -1;
	}
	if ((unsigned)strings.count < 1 + ncolors + height) {
		fprintf(stderr, "AGXPM-REFUSE: %d literals for %u colours and %u rows\n",
			strings.count, ncolors, height);
		fn_list_free(&strings);
		return -1;
	}
	rgba = malloc((size_t)ncolors * 4);
	keys = malloc((size_t)ncolors * cpp);
	pixels = malloc((size_t)width * height * 4);
	if (rgba == NULL || keys == NULL || pixels == NULL) {
		fprintf(stderr, "AGXPM-REFUSE: out of memory for %ux%u\n", width, height);
		goto fail;
	}
	for (c = 0; c < ncolors; c++) {
		const char *entry = strings.items[1 + c];

		if (strlen(entry) < cpp) {
			fprintf(stderr, "AGXPM-REFUSE: colour %u is shorter than its %u-character key\n", c, cpp);
			goto fail;
		}
		memcpy(keys + (size_t)c * cpp, entry, cpp);
		if (fn_parse_colour(entry, cpp, rgba + (size_t)c * 4) != 0) {
			goto fail;
		}
	}
	for (y = 0; y < height; y++) {
		const char *row = strings.items[1 + ncolors + y];

		if (strlen(row) < (size_t)width * cpp) {
			fprintf(stderr, "AGXPM-REFUSE: row %u has %zu characters where %u pixels of %u need %zu\n",
				y, strlen(row), width, cpp, (size_t)width * cpp);
			goto fail;
		}
		for (x = 0; x < width; x++) {
			int index = fn_colour_index(keys, ncolors, cpp, row + (size_t)x * cpp);

			if (index < 0) {
				fprintf(stderr, "AGXPM-REFUSE: row %u names a key with no colour entry\n", y);
				goto fail;
			}
			memcpy(pixels + ((size_t)y * width + x) * 4, rgba + (size_t)index * 4, 4);
		}
	}
	free(rgba);
	free(keys);
	fn_list_free(&strings);
	out->width = width;
	out->height = height;
	out->pixels = pixels;
	return 0;

fail:
	free(rgba);
	free(keys);
	free(pixels);
	fn_list_free(&strings);
	return -1;
}

void AGXPMPixmapFree(AGXPMPixmap *pixmap)
{
	if (pixmap == NULL) {
		return;
	}
	free(pixmap->pixels);
	pixmap->pixels = NULL;
	pixmap->width = pixmap->height = 0;
}
