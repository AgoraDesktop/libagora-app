/*
 * eps_app — AppKit's EPS door end to end: a view writes an EPS page, the bytes carry the PostScript header and
 * the view's ink, and the pasteboard carries the same bytes under NSPostScriptPboardType.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * THE RENDERER IS GHOSTSCRIPT, when the host has it: this tree has no PostScript interpreter, so the only
 * honest proof that the view's drawing survived is another implementation reading the file. The structural
 * checks run either way; the pixel check SKIPS (does not fail) without `gs`.
 */
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSView.h>

#import <CoreGraphics/CGContext.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSData.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *format, ...)
{
	va_list ap;

	printf("  %s   ", ok ? "ok  " : "FAIL");
	va_start(ap, format);
	vprintf(format, ap);
	va_end(ap);
	printf("\n");
	if (!ok) {
		s_failed++;
	}
}

@interface AgoraEPSProbeView : NSView
@end

@implementation AgoraEPSProbeView

- (BOOL)isFlipped
{
	return YES;
}

- (void)drawRect:(NSRect)rect
{
	CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];

	(void)rect;
	if (cg == NULL) {
		return;
	}
	CGContextSetRGBFillColor(cg, 0.0, 0.0, 1.0, 1.0);
	CGContextFillRect(cg, NSMakeRect(10.0, 10.0, 50.0, 30.0));
	CGContextSetRGBFillColor(cg, 1.0, 0.0, 0.0, 1.0);
	CGContextFillRect(cg, NSMakeRect(70.0, 10.0, 20.0, 20.0));
	CGContextSetRGBFillColor(cg, 0.0, 1.0, 0.0, 1.0);
	CGContextFillRect(cg, NSMakeRect(150.0, 50.0, 30.0, 20.0));
}

@end

struct ppm {
	unsigned char *data;
	size_t width;
	size_t height;
};

static int fn_ppm_token(FILE *file, char *out, size_t cap)
{
	size_t length = 0;
	int c;

	do {
		c = fgetc(file);
		if (c == '#') {
			while ((c = fgetc(file)) != EOF && c != '\n') {
			}
		}
	} while (c != EOF && (c == ' ' || c == '\t' || c == '\r' || c == '\n'));
	if (c == EOF) {
		return 0;
	}
	while (c != EOF && c != ' ' && c != '\t' && c != '\r' && c != '\n') {
		if (length + 1 < cap) {
			out[length++] = (char)c;
		}
		c = fgetc(file);
	}
	out[length] = '\0';
	return 1;
}

static int fn_read_ppm(const char *path, struct ppm *out)
{
	FILE *file = fopen(path, "rb");
	char token[32];
	unsigned width;
	unsigned height;
	unsigned maxval;

	if (file == NULL) {
		return 0;
	}
	if (!fn_ppm_token(file, token, sizeof token) || strcmp(token, "P6") != 0) {
		fclose(file);
		return 0;
	}
	if (!fn_ppm_token(file, token, sizeof token)) {
		fclose(file);
		return 0;
	}
	width = (unsigned)strtoul(token, NULL, 10);
	if (!fn_ppm_token(file, token, sizeof token)) {
		fclose(file);
		return 0;
	}
	height = (unsigned)strtoul(token, NULL, 10);
	if (!fn_ppm_token(file, token, sizeof token)) {
		fclose(file);
		return 0;
	}
	maxval = (unsigned)strtoul(token, NULL, 10);
	if (maxval != 255) {
		fclose(file);
		return 0;
	}
	out->width = width;
	out->height = height;
	out->data = malloc((size_t)width * height * 3);
	if (out->data == NULL) {
		fclose(file);
		return 0;
	}
	if (fread(out->data, 3, (size_t)width * height, file) != (size_t)width * height) {
		free(out->data);
		out->data = NULL;
		fclose(file);
		return 0;
	}
	fclose(file);
	return 1;
}

/* PPM ROWS ARE TOP-DOWN; the PostScript user space is bottom-up. */
static void fn_pixel(const struct ppm *image, int x, int y, unsigned char rgb[3])
{
	int row = (int)image->height - 1 - y;

	if (x < 0 || row < 0 || (size_t)x >= image->width || (size_t)row >= image->height) {
		rgb[0] = rgb[1] = rgb[2] = 0;
		return;
	}
	memcpy(rgb, image->data + ((size_t)row * image->width + (size_t)x) * 3, 3);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AgoraEPSProbeView *view = [[AgoraEPSProbeView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
	NSData *data;
	NSPasteboard *board;
	NSData *pasted;
	const char *path = "/tmp/agora-eps-app.eps";
	const char *ppm_path = "/tmp/agora-eps-app.ppm";
	FILE *file;
	int has_gs;

	check(view != nil, "the probe view was created");
	data = view != nil ? [view dataWithEPSInsideRect:NSMakeRect(0, 0, 200, 100)] : nil;
	check(data != nil && [data length] > 100, "-dataWithEPSInsideRect: returned data");
	check(data != nil && [data length] >= 23 &&
	      memcmp([data bytes], "%!PS-Adobe-3.0 EPSF-3.0", 23) == 0,
	      "the data begins with an EPSF header");
	check(data != nil && [[[NSString alloc] initWithBytes:[data bytes] length:[data length]
						      encoding:NSASCIIStringEncoding] autorelease] != nil,
	      "the data is ASCII text");

	if (data != nil) {
		NSString *text = [[[NSString alloc] initWithBytes:[data bytes] length:[data length]
							  encoding:NSASCIIStringEncoding] autorelease];

		check([text rangeOfString:@"%%BoundingBox: 0 0 200 100"].location != NSNotFound,
		      "the BoundingBox is the view's rectangle");
		check([text rangeOfString:@"%%EOF"].location != NSNotFound, "the EPS trailer is present");
		file = fopen(path, "wb");
		if (file != NULL) {
			fwrite([data bytes], 1, (size_t)[data length], file);
			fclose(file);
		}
	}

	board = [NSPasteboard pasteboardWithUniqueName];
	[view writeEPSInsideRect:NSMakeRect(0, 0, 200, 100) toPasteboard:board];
	pasted = [board dataForType:NSPostScriptPboardType];
	check(pasted != nil && [pasted length] > 100,
	      "-writeEPSInsideRect:toPasteboard: put EPS data on the board");
	check(pasted != nil && [pasted length] >= 4 && memcmp([pasted bytes], "%!PS", 4) == 0,
	      "the pasteboard data has a PostScript header");

	has_gs = system("gs --version >/dev/null 2>&1") == 0;
	if (!has_gs) {
		printf("  SKIP  Ghostscript is not installed; the pixel check was not run\n");
	} else {
		char command[512];
		struct ppm image;

		snprintf(command, sizeof command,
			 "gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=ppmraw -dEPSCrop -r72 -sOutputFile=%s %s",
			 ppm_path, path);
		check(system(command) == 0, "Ghostscript read the view's EPS");
		if (fn_read_ppm(ppm_path, &image)) {
			unsigned char rgb[3];

			check(image.width == 200 && image.height == 100,
			      "Ghostscript produced a 200x100 page");
			/* The view is flipped: its blue rectangle at view y 10..40 is page y 60..90. */
			fn_pixel(&image, 35, 75, rgb);
			check(rgb[2] > 200 && rgb[0] < 60 && rgb[1] < 60,
			      "the view's blue rectangle is on the page (R=%u G=%u B=%u)", rgb[0], rgb[1],
			      rgb[2]);
			fn_pixel(&image, 80, 80, rgb);
			check(rgb[0] > 200 && rgb[1] < 60 && rgb[2] < 60,
			      "the view's red rectangle is on the page (R=%u G=%u B=%u)", rgb[0], rgb[1],
			      rgb[2]);
			fn_pixel(&image, 165, 40, rgb);
			check(rgb[1] > 200 && rgb[0] < 60 && rgb[2] < 60,
			      "the view's green rectangle is on the page (R=%u G=%u B=%u)", rgb[0], rgb[1],
			      rgb[2]);
			free(image.data);
		} else {
			check(0, "Ghostscript wrote no readable PPM");
		}
	}

	[view release];
	[pool release];
	if (s_failed != 0) {
		fprintf(stderr, "%d EPS AppKit check(s) failed\n", s_failed);
	}
	return s_failed == 0 ? 0 : 1;
}
