/*
 * AGChromeTheme.m — the XFWM theme behind `AGChromeTheme.h`.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import "AGChromeTheme.h"
#import "AGXPM.h"

#import <AppKit/NSBitmapImageRep.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>

#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGDataProvider.h>
#import <CoreGraphics/CGImage.h>

#include <stdlib.h>
#include <string.h>

/* THE FILE NAMES XFWM USES, WHICH ARE ALSO THIS CLASS'S TWO ENUMS SPELLED OUT. */
static const char *const fn_button_names[AGChromeButtonCount] = { "close", "hide", "maximize", "menu" };
static const char *const fn_state_names[AGChromeButtonStateCount] = { "active", "inactive", "prelight", "pressed" };

/* THE FRAME PIECES' FILE NAMES, WHICH ARE `AGChromeFramePiece` SPELLED OUT — the same shape as the buttons'. */
static const char *const fn_frame_names[AGChromeFramePieceCount] = {
	"top-left", "top-right", "title-1", "title-2", "title-3", "title-4", "title-5"
};

static AGChromeTheme *s_shared = nil;
static BOOL s_resolved = NO;

/* ============================================================================================ *
 * PIXELS INTO IMAGES.                                                                           *
 * ============================================================================================ */

/* THE PROVIDER OWNS THE PIXELS FROM HERE ON, which is why the callback is a `free` and why the pixmap's pointer is
 * cleared once the image adopts it — the same one-owner rule the rest of this tree's buffers keep. */
static void fn_release_pixels(void *info, const void *data, size_t size)
{
	(void)info;
	(void)size;
	free((void *)data);
}

static CGImageRef fn_image_from_pixmap(AGXPMPixmap *pixmap)
{
	CGDataProviderRef provider;
	CGColorSpaceRef space;
	CGImageRef image;
	uint32_t info = (uint32_t)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

	provider = CGDataProviderCreateWithData(NULL, pixmap->pixels,
						(size_t)pixmap->width * pixmap->height * 4,
						fn_release_pixels);
	if (provider == NULL) {
		return NULL;
	}
	space = CGColorSpaceCreateDeviceRGB();
	image = CGImageCreate(pixmap->width, pixmap->height, 8, 32, (size_t)pixmap->width * 4,
			      space, info, provider, NULL, false, kCGRenderingIntentDefault);
	CGColorSpaceRelease(space);
	CGDataProviderRelease(provider);	/* the image retains it; this drops OUR reference */
	if (image == NULL) {
		return NULL;			/* the provider's release just freed the pixels */
	}
	pixmap->pixels = NULL;			/* now the provider's, so `AGXPMPixmapFree` must not free it too */
	return image;
}

static CGImageRef fn_load_xpm(NSString *path)
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	AGXPMPixmap pixmap;
	CGImageRef image;

	if (data == nil) {
		return NULL;
	}
	memset(&pixmap, 0, sizeof pixmap);
	if (AGXPMParse((const char *)[data bytes], (size_t)[data length], &pixmap) != 0) {
		return NULL;
	}
	image = fn_image_from_pixmap(&pixmap);
	AGXPMPixmapFree(&pixmap);		/* a no-op once ownership moved, and the free if it did not */
	return image;
}

/* A PNG GOES THROUGH THE EXISTING DECODER AND COMES BACK OWNED. `+imageRepWithData:` is a factory (so the rep is
 * autoreleased), and its `-CGImage` is BORROWED — the rep owns it — so the retain is what makes the image outlive
 * the pool. That is not a second decoder: PNG and JPEG are what this tree already reads. */
static CGImageRef fn_load_png(NSString *path)
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	NSBitmapImageRep *rep;
	CGImageRef image;

	if (data == nil) {
		return NULL;
	}
	rep = [NSBitmapImageRep imageRepWithData:data];
	if (rep == nil) {
		return NULL;
	}
	image = [rep CGImage];
	if (image != NULL) {
		CGImageRetain(image);
	}
	return image;
}

/* `<name>.xpm` first, then `<name>.png`: XFWM 4.x reads both, and a theme that ships PNG needs no new code at
 * all. Both missing answers NULL, which is the caller's cue to fall back. */
static CGImageRef fn_load_named(NSString *directory, NSString *base)
{
	NSString *xpm = [directory stringByAppendingPathComponent:[base stringByAppendingString:@".xpm"]];
	NSString *png = [directory stringByAppendingPathComponent:[base stringByAppendingString:@".png"]];
	CGImageRef image;

	if ([[NSFileManager defaultManager] fileExistsAtPath:xpm]) {
		image = fn_load_xpm(xpm);
		if (image != NULL) {
			return image;
		}
	}
	if ([[NSFileManager defaultManager] fileExistsAtPath:png]) {
		image = fn_load_png(png);
		if (image != NULL) {
			return image;
		}
	}
	return NULL;
}

/* ============================================================================================ *
 * WHERE THE THEME IS.                                                                           *
 * ============================================================================================ */

/* A ROOT is the directory the files are in, or a theme with an `xfwm4/` inside it. `close-active.xpm` is the
 * probe because a theme without a close button is not one this chrome can draw. */
static NSString *fn_theme_root(NSString *root)
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *nested;

	if ([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"close-active.xpm"]]) {
		return root;
	}
	nested = [root stringByAppendingPathComponent:@"xfwm4"];
	if ([fm fileExistsAtPath:[nested stringByAppendingPathComponent:@"close-active.xpm"]]) {
		return nested;
	}
	return nil;
}

static NSString *fn_resolve_directory(void)
{
	const char *env = getenv("AGORA_CHROME_THEME");

	if (env != NULL && *env != '\0') {
		NSString *root = [NSString stringWithUTF8String:env];
		NSString *found = (root != nil) ? fn_theme_root(root) : nil;

		if (found != nil) {
			return found;
		}
	}
	/* **A THEME IS AN APPLICATION'S SUPPORT DATA, SO IT LIVES WHERE THE INSTALLATION PUTS THOSE.** The order
	 * is the account's theme first and the machine's second — `~/Library/Application Support/agora/chrome`,
	 * then `/Library/Application Support/agora/chrome` — and the directories are ASKED FOR rather than spelled:
	 * this used to be `$XDG_DATA_HOME/agora/chrome`, which names a directory a complete Agora installation
	 * does not carry. `AGORA_CHROME_THEME` above still wins, which is how a development tree points at its own
	 * copy of a theme it does not ship. */
	{
		NSArray *directories = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
									  NSUserDomainMask | NSLocalDomainMask, YES);
		NSUInteger i;

		for (i = 0; i < [directories count]; i++) {
			NSString *root = [[directories objectAtIndex:i] stringByAppendingPathComponent:@"agora/chrome"];
			NSString *found = fn_theme_root(root);

			if (found != nil) {
				return found;
			}
		}
	}
	return nil;
}

/* ============================================================================================ *
 * themerc: TWO NUMBERS AND NOTHING ELSE.                                                        *
 *                                                                                                *
 * XFWM's themerc is a list of `key=value` lines, and two of them are geometry the chrome needs: *
 * how far the buttons sit from the window's edge and how far apart they are. **A COMMENTED LINE  *
 * IS SKIPPED**, which is the one rule the format has — the file is full of `#button_layout=…`    *
 * alternatives that must not be read as settings. Everything else in it belongs to XFWM.         *
 * ============================================================================================ */
static void fn_read_themerc(NSString *directory, CGFloat *offset, CGFloat *spacing)
{
	NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"themerc"]];
	const char *bytes;
	size_t length, start, i;

	/* XFWM's own defaults when the file or the key is absent. */
	*offset = 0.0;
	*spacing = 0.0;
	if (data == nil) {
		return;
	}
	bytes = [data bytes];
	length = (size_t)[data length];
	start = 0;
	for (i = 0; i <= length; i++) {
		if (i == length || bytes[i] == '\n') {
			size_t lineLength = i - start;

			if (lineLength > 0 && bytes[start] != '#') {
				if (lineLength > 14 && memcmp(bytes + start, "button_offset=", 14) == 0) {
					*offset = (CGFloat)strtod(bytes + start + 14, NULL);
				} else if (lineLength > 15 && memcmp(bytes + start, "button_spacing=", 15) == 0) {
					*spacing = (CGFloat)strtod(bytes + start + 15, NULL);
				}
			}
			start = i + 1;
		}
	}
}

/* ============================================================================================ *
 * THE OBJECT.                                                                                   *
 * ============================================================================================ */

/* THE RESOLVING INITIALISER IS PRIVATE — a caller gets the singleton or nothing — and the height probe is declared
 * here because the initialiser below uses it while its definition carries the explanation. */
static BOOL fn_probe_height(NSString *directory, NSString *base, CGFloat *outHeight);

@interface AGChromeTheme ()
- (instancetype)initResolving;
@end

@implementation AGChromeTheme

+ (instancetype)sharedTheme
{
	if (!s_resolved) {
		s_resolved = YES;
		s_shared = [[AGChromeTheme alloc] initResolving];
	}
	return s_shared;
}

- (instancetype)initResolving
{
	NSString *directory = fn_resolve_directory();
	CGImageRef probe = NULL;
	CGFloat probed;

	if (directory == nil) {
		[self release];
		return nil;
	}
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* THE RESOLVED DIRECTORY IS RETAINED, not the autoreleased string the search returned. */
	_directory = [directory copy];
	fn_read_themerc(_directory, &_buttonOffset, &_buttonSpacing);

	/* THE CLOSE BUTTON IS WHAT SAYS HOW BIG A BUTTON IS. A theme that ships only the inactive one is drawing the
	 * same button, so it is read as the surrogate rather than refused — and the cache says which one it was. */
	probe = fn_load_named(_directory, @"close-active");
	_probed[AGChromeButtonClose][AGChromeButtonStateActive] = YES;
	if (probe != NULL) {
		_images[AGChromeButtonClose][AGChromeButtonStateActive] = probe;
	} else {
		probe = fn_load_named(_directory, @"close-inactive");
		_probed[AGChromeButtonClose][AGChromeButtonStateInactive] = YES;
		_images[AGChromeButtonClose][AGChromeButtonStateInactive] = probe;
	}
	if (probe == NULL) {
		[_directory release];
		[self release];
		return nil;			/* a directory with no close button is not a theme this chrome can use */
	}
	_buttonSize = NSMakeSize((CGFloat)CGImageGetWidth(probe), (CGFloat)CGImageGetHeight(probe));
	_titleBarHeight = _buttonSize.height;

	/* **AND THE STRIP IS AS TALL AS THE TALLEST THING THE THEME PUTS IN IT**, which for a real theme is the frame
	 * corner or the title piece: the buttons fill the bar rather than the bar being sized to them, and 1:1 means
	 * the bar takes the theme's height, not the buttons'. */
	if (fn_probe_height(_directory, @"top-left-active.xpm", &probed) && probed > _titleBarHeight) {
		_titleBarHeight = probed;
	}
	if (fn_probe_height(_directory, @"title-1-active.xpm", &probed) && probed > _titleBarHeight) {
		_titleBarHeight = probed;
	}
	return self;
}

/* A PROBE THAT ONLY WANTS THE HEIGHT, so it releases the image it decoded. It takes the file NAME without an
 * extension and is what the initialiser asks about the frame corners and the title pieces. */
static BOOL fn_probe_height(NSString *directory, NSString *base, CGFloat *outHeight)
{
	CGImageRef image = fn_load_named(directory, base);

	if (image == NULL) {
		return NO;
	}
	*outHeight = (CGFloat)CGImageGetHeight(image);
	CGImageRelease(image);
	return YES;
}

- (NSString *)directory
{
	return _directory;
}

- (CGFloat)titleBarHeight
{
	return _titleBarHeight;
}

- (CGFloat)buttonOffset
{
	return _buttonOffset;
}

- (CGFloat)buttonSpacing
{
	return _buttonSpacing;
}

- (NSSize)buttonSize
{
	return _buttonSize;
}

- (CGImageRef)imageForButton:(AGChromeButton)button state:(AGChromeButtonState)state
{
	AGChromeButtonState order[AGChromeButtonStateCount];
	int count = 0;
	int i;

	if (button < 0 || button >= AGChromeButtonCount || state < 0 || state >= AGChromeButtonStateCount) {
		return NULL;
	}
	/* THE EXACT STATE FIRST, THEN THE FAMILY IT BELONGS TO: a theme with no `pressed` art still presses by showing
	 * its `prelight`, and a theme with two graphics per button still draws four states. The order is stated so a
	 * theme that ships the third is not silently served the second. */
	order[count++] = state;
	if (state == AGChromeButtonStatePressed) {
		order[count++] = AGChromeButtonStatePrelight;
	}
	if (state != AGChromeButtonStateActive) {
		order[count++] = AGChromeButtonStateActive;
	}
	if (state != AGChromeButtonStateInactive) {
		order[count++] = AGChromeButtonStateInactive;
	}
	for (i = 0; i < count; i++) {
		AGChromeButtonState candidate = order[i];

		if (!_probed[button][candidate]) {
			NSString *base = [NSString stringWithFormat:@"%s-%s",
					  fn_button_names[button], fn_state_names[candidate]];

			_probed[button][candidate] = YES;
			_images[button][candidate] = fn_load_named(_directory, base);
		}
		if (_images[button][candidate] != NULL) {
			return _images[button][candidate];	/* BORROWED: the cache owns it */
		}
	}
	return NULL;
}

- (CGImageRef)framePiece:(AGChromeFramePiece)piece active:(BOOL)active
{
	int s = active ? 0 : 1;

	if (piece < 0 || piece >= AGChromeFramePieceCount) {
		return NULL;
	}
	/* PROBED ONCE EITHER WAY, so a theme with no title pieces does not look for them every frame. */
	if (!_frameProbed[piece][s]) {
		NSString *base = [NSString stringWithFormat:@"%s-%s", fn_frame_names[piece],
				  active ? "active" : "inactive"];

		_frameProbed[piece][s] = YES;
		_frameImages[piece][s] = fn_load_named(_directory, base);
	}
	return _frameImages[piece][s];	/* BORROWED: the cache owns it */
}

- (void)dealloc
{
	int button, state;
	int piece, half;

	for (button = 0; button < AGChromeButtonCount; button++) {
		for (state = 0; state < AGChromeButtonStateCount; state++) {
			if (_images[button][state] != NULL) {
				CGImageRelease(_images[button][state]);
			}
		}
	}
	for (piece = 0; piece < AGChromeFramePieceCount; piece++) {
		for (half = 0; half < 2; half++) {
			if (_frameImages[piece][half] != NULL) {
				CGImageRelease(_frameImages[piece][half]);
			}
		}
	}
	[_directory release];
	[super dealloc];
}

@end

CGFloat AGChromeThemeTitleBarHeight(void)
{
	AGChromeTheme *theme = [AGChromeTheme sharedTheme];

	return (theme != nil) ? [theme titleBarHeight] : 0.0;
}
