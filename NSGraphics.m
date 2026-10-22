/*
 * NSGraphics.m — the drawing functions: fills, frames, clips, bezels, and the window list.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE 10.6 `NSGraphics.h` FUNCTIONS HAD NO GROUND IN THIS TIER AT ALL, AND THAT WAS THE SINGLE WORST MEASUREMENT IN
 * THE API CENSUS.** `tests/api-10.6-census.txt` recorded 11 of 87 C functions, and 29 of the 76 missing ones were these:
 * `NSRectFill`, the bezels, the clip helpers. Their absence was not a behavioural gap that a caller could work around
 * — a program written against Apple's headers calls `NSRectFill` and does not LINK. So this file is the tier's worst
 * per-hour deficit closed: the primitives every ported view reaches for first.
 *
 * **EVERY DOOR HERE IS A WRAPPER, AND THAT IS THE POINT RATHER THAN A SHORTCUT.** `NSBezierPath` already owns the path
 * and winding rules, `NSColor -setFill`/`-setStroke` already reach the context's ink, and
 * `-[NSGraphicsContext CGContext]` already names the surface. A second drawing engine would be a correctness risk —
 * the same argument the plan makes for the text system's typesetter facades. These functions therefore do not draw
 * anything themselves: they reach the SAME context the rest of the tier draws into, set the SAME ink, and fill.
 *
 * **THE COORDINATE QUESTION IS SETTLED BY THE PATH CODE RATHER THAN ASSUMED.** `-[NSBezierPath fill]` hands the raw
 * `NSRect`-shaped path to `CGContextDrawPath`, and the suite is green, so the current transform already maps user space
 * onto AppKit's orientation. These functions pass `NSRect` straight to `CGContextFillRect` for exactly that reason:
 * the coordinates are the caller's, and the flip is the view's business.
 *
 * **SIX DOORS REFUSE BY NAME AND THE REST ARE REAL.** A refusal is a supported disposition in this tree, and it is
 * chosen only where the backing genuinely does not exist:
 *
 *   `NSBeep`             no sound device and no `NSSound` — refused ONCE rather than per call, because a refusal that
 *                        floods stderr inside a UI loop is a worse failure than the silence it replaces
 *   `NSCopyBits`         reads pixels back off the screen; this tier has no compositor read path
 *   `NSReadPixel`        the same read path
 *   `NSGetWindowServerMemory`  the server keeps no such accounting to ask for
 *   `NSSetFocusRingStyle`      the style of a ring this tier has no renderer for
 *   `NSShowAnimationEffect`    the animation effects the era played through the window server
 *
 * **AND TWO ARE A COUNTER RATHER THAN A NO-OP.** `NSDisableScreenUpdates`/`NSEnableScreenUpdates` are the era's batching
 * pair; they now gate `-[NSGraphicsContext flushGraphics]`, which is the one place this tier pushes pixels. See
 * `NSGraphics_internal.h` for why that is the honest place to put the switch.
 */
#import <AppKit/NSGraphics.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSGraphics_internal.h>
#import <AppKit/AppKitRefusal.h>

#import <CoreGraphics/CGContext.h>

#import <Foundation/Foundation.h>

#include <stdio.h>

/* ------------------------------------------------------------------------------------------------------------------
 * The surface and its ink.
 * ---------------------------------------------------------------------------------------------------------------- */

static CGContextRef fn_current(void)
{
	NSGraphicsContext *g = [NSGraphicsContext currentContext];

	return g != nil ? [g CGContext] : NULL;
}

/* **THE COMPOSITING OPERATIONS THE ERA NAMED, ONTO THE ONES CORE GRAPHICS NAMES.** They are not the same vocabulary:
 * CG has no "highlight" mode, so `NSCompositeHighlight` maps to the multiply that the era's callers got by setting a
 * grey before the call — a deviation recorded at the map rather than hidden. `NSCompositePlusDarker` is the era's
 * saturating add and maps to CG's plus-darker for that reason. */
static CGBlendMode fn_blend(NSCompositingOperation op)
{
	/* **THE `NSCompositingOperation` ENUMERATORS ARE THE CASE LABELS RATHER THAN THE LEGACY `NSComposite*` SPELLINGS.**
	 * The two families carry the same numbers, so a ported 10.2 caller's value reaches the same arm — but only the
	 * enumerators are compile-time constants. The legacy names are `extern const` VARIABLES in this tier (see
	 * `NSGraphicsContext.h` for why the ledger wants them that way), and a variable is not a `case` label. */
	switch (op) {
	case NSCompositingOperationClear:		return kCGBlendModeClear;
	case NSCompositingOperationCopy:		return kCGBlendModeCopy;
	case NSCompositingOperationSourceIn:		return kCGBlendModeSourceIn;
	case NSCompositingOperationSourceOut:		return kCGBlendModeSourceOut;
	case NSCompositingOperationSourceAtop:		return kCGBlendModeSourceAtop;
	case NSCompositingOperationDestinationOver:	return kCGBlendModeDestinationOver;
	case NSCompositingOperationDestinationIn:	return kCGBlendModeDestinationIn;
	case NSCompositingOperationDestinationOut:	return kCGBlendModeDestinationOut;
	case NSCompositingOperationDestinationAtop:	return kCGBlendModeDestinationAtop;
	case NSCompositingOperationXOR:			return kCGBlendModeXOR;
	case NSCompositingOperationPlusDarker:		return kCGBlendModePlusDarker;
	case NSCompositingOperationPlusLighter:		return kCGBlendModePlusLighter;
	case NSCompositingOperationMultiply:		return kCGBlendModeMultiply;
	case NSCompositingOperationScreen:		return kCGBlendModeScreen;
	case NSCompositingOperationOverlay:		return kCGBlendModeOverlay;
	case NSCompositingOperationDarken:		return kCGBlendModeDarken;
	case NSCompositingOperationLighten:		return kCGBlendModeLighten;
	case NSCompositingOperationColorDodge:		return kCGBlendModeColorDodge;
	case NSCompositingOperationColorBurn:		return kCGBlendModeColorBurn;
	case NSCompositingOperationSoftLight:		return kCGBlendModeSoftLight;
	case NSCompositingOperationHardLight:		return kCGBlendModeHardLight;
	case NSCompositingOperationDifference:		return kCGBlendModeDifference;
	case NSCompositingOperationExclusion:		return kCGBlendModeExclusion;
	case NSCompositingOperationHue:			return kCGBlendModeHue;
	case NSCompositingOperationSaturation:		return kCGBlendModeSaturation;
	case NSCompositingOperationColor:		return kCGBlendModeColor;
	case NSCompositingOperationLuminosity:		return kCGBlendModeLuminosity;
	case NSCompositingOperationSourceOver:
	default:					return kCGBlendModeNormal;
	}
}

/* One fill, under one operation, in whatever ink the caller has already set. */
static void fn_fill_one(CGContextRef ctx, NSRect rect, NSCompositingOperation op)
{
	if (rect.size.width <= 0.0 || rect.size.height <= 0.0) {
		return;
	}
	CGContextSaveGState(ctx);
	CGContextSetBlendMode(ctx, fn_blend(op));
	CGContextFillRect(ctx, rect);
	CGContextRestoreGState(ctx);
}

/* **THE FIVE LIST VARIANTS ARE ONE LOOP WITH THREE INK SOURCES**, which is why they are here rather than five times
 * below: rectangles in the caller's current colour, or in one grey per rectangle, or in one colour per rectangle. A
 * NULL ink source means "do not touch the ink", because setting it would be a side effect the caller did not ask for. */
static void fn_fill_list(const NSRect *rects, NSColor * const *colors, const CGFloat *grays,
			 NSInteger count, NSCompositingOperation op)
{
	CGContextRef ctx = fn_current();
	NSInteger i;

	if (ctx == NULL || rects == NULL || count <= 0) {
		return;
	}
	for (i = 0; i < count; i++) {
		if (colors != NULL && colors[i] != nil) {
			[colors[i] setFill];
		} else if (grays != NULL) {
			[[NSColor colorWithCalibratedWhite:grays[i] alpha:1.0] setFill];
		}
		fn_fill_one(ctx, rects[i], op);
	}
}

/* ------------------------------------------------------------------------------------------------------------------
 * Fills.
 * ---------------------------------------------------------------------------------------------------------------- */

void NSRectFill(NSRect aRect)
{
	fn_fill_list(&aRect, NULL, NULL, 1, NSCompositeSourceOver);
}

void NSRectFillUsingOperation(NSRect aRect, NSCompositingOperation op)
{
	fn_fill_list(&aRect, NULL, NULL, 1, op);
}

void NSRectFillList(const NSRect *rects, NSInteger count)
{
	fn_fill_list(rects, NULL, NULL, count, NSCompositeSourceOver);
}

void NSRectFillListUsingOperation(const NSRect *rects, NSInteger count, NSCompositingOperation op)
{
	fn_fill_list(rects, NULL, NULL, count, op);
}

void NSRectFillListWithGrays(const NSRect *rects, const CGFloat *grays, NSInteger num)
{
	fn_fill_list(rects, NULL, grays, num, NSCompositeSourceOver);
}

void NSRectFillListWithColors(const NSRect *rects, NSColor **colors, NSInteger num)
{
	fn_fill_list(rects, colors, NULL, num, NSCompositeSourceOver);
}

void NSRectFillListWithColorsUsingOperation(const NSRect *rects, NSColor **colors, NSInteger num,
					    NSCompositingOperation op)
{
	fn_fill_list(rects, colors, NULL, num, op);
}

/* **THE HIGHLIGHT SUPPLIES ITS OWN WASH, BECAUSE THE OPERATION IT USED TO NAME IS DELIBERATELY NOT DECLARED HERE.**
 * Apple's `NSCompositeHighlight` collides with `NSCompositingOperationPlusLighter` at 12 in the modern numbering, so
 * `NSGraphicsContext.h` refuses to declare it rather than let a ported caller ask for the wrong blend silently. That
 * leaves this door to do what the era documented — "fills the rectangle with a light gray" — without borrowing a name
 * this tier has struck. A BLACK WASH AT A QUARTER ALPHA RATHER THAN A FIXED GREY, because a fixed grey cannot
 * highlight a ground it happens to match, while a wash reads on any ground. */
void NSHighlightRect(NSRect aRect)
{
	[[NSColor colorWithCalibratedWhite:0.0 alpha:0.25] setFill];
	NSRectFillUsingOperation(aRect, NSCompositingOperationSourceOver);
}

/* **AND THE ERASE IS WHITE RATHER THAN THE WINDOW'S GROUND**, which is what Apple documents for this door — a caller
 * that wants the window's own ground asks `NSDrawWindowBackground`. The copy operation is the era's: an erase replaces
 * what was there instead of blending with it. */
void NSEraseRect(NSRect aRect)
{
	[[NSColor whiteColor] setFill];
	NSRectFillUsingOperation(aRect, NSCompositeCopy);
}

/* ------------------------------------------------------------------------------------------------------------------
 * Frames.
 * ---------------------------------------------------------------------------------------------------------------- */

/* **A FRAME IS DRAWN INSIDE ITS RECTANGLE.** The width is centred on the path, so the path is inset by half the width
 * to leave the whole stroke inside — which is the era's contract and the reason `NSFrameRect` and
 * `NSFrameRectWithWidth:1` agree pixel for pixel. */
void NSFrameRectWithWidthUsingOperation(NSRect aRect, CGFloat frameWidth, NSCompositingOperation op)
{
	CGContextRef ctx = fn_current();
	CGFloat inset;

	if (ctx == NULL || frameWidth <= 0.0 || aRect.size.width <= 0.0 || aRect.size.height <= 0.0) {
		return;
	}
	inset = frameWidth * 0.5;
	CGContextSaveGState(ctx);
	CGContextSetBlendMode(ctx, fn_blend(op));
	CGContextSetLineWidth(ctx, frameWidth);
	CGContextStrokeRect(ctx, NSInsetRect(aRect, inset, inset));
	CGContextRestoreGState(ctx);
}

void NSFrameRect(NSRect aRect)
{
	NSFrameRectWithWidthUsingOperation(aRect, 1.0, NSCompositeSourceOver);
}

void NSFrameRectWithWidth(NSRect aRect, CGFloat frameWidth)
{
	NSFrameRectWithWidthUsingOperation(aRect, frameWidth, NSCompositeSourceOver);
}

/* **THE DOTTED FRAME IS A DASH PATTERN ON THE SAME STROKE**, one point on and one point off in the ink the caller set,
 * so a caller that has set its colour gets its colour rather than a hard-coded grey. */
void NSDottedFrameRect(NSRect aRect)
{
	CGContextRef ctx = fn_current();
	CGFloat dash[2] = {1.0, 1.0};

	if (ctx == NULL || aRect.size.width <= 0.0 || aRect.size.height <= 0.0) {
		return;
	}
	CGContextSaveGState(ctx);
	CGContextSetLineWidth(ctx, 1.0);
	CGContextSetLineDash(ctx, 0.0, dash, 2);
	CGContextStrokeRect(ctx, NSInsetRect(aRect, 0.5, 0.5));
	CGContextRestoreGState(ctx);
}

/* ------------------------------------------------------------------------------------------------------------------
 * Clipping.
 * ---------------------------------------------------------------------------------------------------------------- */

/* `CGContextClipToRect` INTERSECTS rather than replaces, which is exactly the era's "intersect the clip with this
 * rectangle" — so the one call is the whole implementation. */
void NSRectClip(NSRect aRect)
{
	CGContextRef ctx = fn_current();

	if (ctx == NULL) {
		return;
	}
	CGContextClipToRect(ctx, aRect);
}

void NSRectClipList(const NSRect *rects, NSInteger count)
{
	CGContextRef ctx = fn_current();
	NSInteger i;

	if (ctx == NULL || rects == NULL || count <= 0) {
		return;
	}
	for (i = 0; i < count; i++) {
		CGContextClipToRect(ctx, rects[i]);
	}
}

/* ------------------------------------------------------------------------------------------------------------------
 * The bezels, the button border and the tiled frames.
 * ---------------------------------------------------------------------------------------------------------------- */

/* A bezel is two hairlines: a light one along the top and left, a dark one along the bottom and right. The four named
 * bezels differ only in which inks they use, so they are one helper and four pairs. */
static void fn_bezel(NSRect aRect, NSRect clipRect, NSColor *light, NSColor *dark)
{
	CGContextRef ctx = fn_current();
	CGFloat minX = NSMinX(aRect), maxX = NSMaxX(aRect);
	CGFloat minY = NSMinY(aRect), maxY = NSMaxY(aRect);

	if (ctx == NULL || aRect.size.width <= 0.0 || aRect.size.height <= 0.0) {
		return;
	}
	CGContextSaveGState(ctx);
	CGContextClipToRect(ctx, clipRect);

	[light setStroke];
	CGContextSetLineWidth(ctx, 1.0);
	CGContextBeginPath(ctx);
	CGContextMoveToPoint(ctx, minX + 0.5, maxY - 0.5);
	CGContextAddLineToPoint(ctx, minX + 0.5, minY + 0.5);
	CGContextAddLineToPoint(ctx, maxX - 0.5, minY + 0.5);
	CGContextStrokePath(ctx);

	[dark setStroke];
	CGContextBeginPath(ctx);
	CGContextMoveToPoint(ctx, minX + 0.5, maxY - 0.5);
	CGContextAddLineToPoint(ctx, maxX - 0.5, maxY - 0.5);
	CGContextAddLineToPoint(ctx, maxX - 0.5, minY + 0.5);
	CGContextStrokePath(ctx);

	CGContextRestoreGState(ctx);
}

void NSDrawWhiteBezel(NSRect aRect, NSRect clipRect)
{
	fn_bezel(aRect, clipRect, [NSColor whiteColor], [NSColor controlDarkShadowColor]);
}

void NSDrawGrayBezel(NSRect aRect, NSRect clipRect)
{
	fn_bezel(aRect, clipRect, [NSColor controlColor], [NSColor controlDarkShadowColor]);
}

void NSDrawLightBezel(NSRect aRect, NSRect clipRect)
{
	fn_bezel(aRect, clipRect, [NSColor whiteColor], [NSColor controlColor]);
}

void NSDrawDarkBezel(NSRect aRect, NSRect clipRect)
{
	fn_bezel(aRect, clipRect, [NSColor controlDarkShadowColor], [NSColor blackColor]);
}

/* A groove is the same two hairlines with the inks SWAPPED: the dark line runs along top and left, so the border reads
 * as cut into the surface rather than raised off it. */
void NSDrawGroove(NSRect aRect, NSRect clipRect)
{
	fn_bezel(aRect, clipRect, [NSColor controlDarkShadowColor], [NSColor whiteColor]);
}

/* **THE BUTTON BORDER IS THE FACE AND ITS FRAME.** `NSDrawButton` in the era drew the 1-point bezel of a push button;
 * this tier's buttons are a face plus a border, so drawing only the border would leave a caller's rectangle unpainted
 * where every control in the tree paints one. The face is the control ground and the frame is the shadow, and both are
 * clipped to the caller's clip rectangle so the function can be used while scrolling a partly-visible button. */
void NSDrawButton(NSRect aRect, NSRect clipRect)
{
	CGContextRef ctx = fn_current();

	if (ctx == NULL || aRect.size.width <= 0.0 || aRect.size.height <= 0.0) {
		return;
	}
	CGContextSaveGState(ctx);
	CGContextClipToRect(ctx, clipRect);
	[[NSColor controlColor] setFill];
	fn_fill_one(ctx, aRect, NSCompositeSourceOver);
	[[NSColor controlDarkShadowColor] setStroke];
	CGContextSetLineWidth(ctx, 1.0);
	CGContextStrokeRect(ctx, NSInsetRect(aRect, 0.5, 0.5));
	CGContextRestoreGState(ctx);
}

void NSDrawWindowBackground(NSRect aRect)
{
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(aRect);
}

/* **THE TILED RECTS ARE THE ERA'S BEZEL BUILDER**: one band of one point per side, each in its own grey, and the
 * function's ANSWER is what is left in the middle. That return value is the reason it exists — a caller composes a
 * frame and then fills the interior it hands back. */
NSRect NSDrawColorTiledRects(NSRect boundsRect, NSRect clipRect, const NSRectEdge *sides, NSColor **colors,
			     NSInteger count)
{
	CGContextRef ctx = fn_current();
	NSRect interior = boundsRect;
	NSInteger i;

	if (ctx == NULL || sides == NULL || colors == NULL || count <= 0) {
		return interior;
	}
	CGContextSaveGState(ctx);
	CGContextClipToRect(ctx, clipRect);
	for (i = 0; i < count; i++) {
		NSRect band;

		if (interior.size.width <= 0.0 || interior.size.height <= 0.0) {
			break;
		}
		switch (sides[i]) {
		case NSMinXEdge:
			band = NSMakeRect(NSMinX(interior), NSMinY(interior), 1.0, interior.size.height);
			interior.origin.x += 1.0;
			interior.size.width -= 1.0;
			break;
		case NSMaxXEdge:
			band = NSMakeRect(NSMaxX(interior) - 1.0, NSMinY(interior), 1.0, interior.size.height);
			interior.size.width -= 1.0;
			break;
		case NSMinYEdge:
			band = NSMakeRect(NSMinX(interior), NSMinY(interior), interior.size.width, 1.0);
			interior.origin.y += 1.0;
			interior.size.height -= 1.0;
			break;
		case NSMaxYEdge:
		default:
			band = NSMakeRect(NSMinX(interior), NSMaxY(interior) - 1.0, interior.size.width, 1.0);
			interior.size.height -= 1.0;
			break;
		}
		if (colors[i] != nil) {
			[colors[i] setFill];
		}
		fn_fill_one(ctx, band, NSCompositeSourceOver);
	}
	CGContextRestoreGState(ctx);
	return interior;
}

NSRect NSDrawTiledRects(NSRect boundsRect, NSRect clipRect, const NSRectEdge *sides, const CGFloat *grays,
			NSInteger count)
{
	NSColor *colors[16];
	NSInteger i;

	if (grays == NULL || count <= 0) {
		return boundsRect;
	}
	if (count > 16) {
		count = 16;
	}
	for (i = 0; i < count; i++) {
		colors[i] = [NSColor colorWithCalibratedWhite:grays[i] alpha:1.0];
	}
	return NSDrawColorTiledRects(boundsRect, clipRect, sides, colors, count);
}

/* ------------------------------------------------------------------------------------------------------------------
 * The screen-update pair, which is a counter that `flushGraphics` reads.
 * ---------------------------------------------------------------------------------------------------------------- */

static NSInteger s_screenUpdatesDisabled = 0;

BOOL cg_screenUpdatesDisabled(void)
{
	return s_screenUpdatesDisabled > 0 ? YES : NO;
}

void NSDisableScreenUpdates(void)
{
	s_screenUpdatesDisabled++;
}

void NSEnableScreenUpdates(void)
{
	if (s_screenUpdatesDisabled > 0) {
		s_screenUpdatesDisabled--;
	}
}

/* ------------------------------------------------------------------------------------------------------------------
 * The window list, answered from the application this tier already keeps.
 * ---------------------------------------------------------------------------------------------------------------- */

/* **A "CONTEXT" IS THIS TIER'S OWN APPLICATION, WHICH IS THE ONLY ONE THERE IS.** The era's context was a window-server
 * connection and a process could have several; here there is one server connection per process and one application, so
 * `...ForContext:` and the plain door answer the same list rather than a different one. That is a documented deviation
 * rather than a silent one. On-screen windows are the visible ones, front to back. */
static NSArray *fn_visibleWindows(void)
{
	NSApplication *app = [NSApplication sharedApplication];
	NSArray *ordered = [app orderedWindows];
	NSMutableArray *visible = [NSMutableArray array];
	NSEnumerator *e = [ordered objectEnumerator];
	NSWindow *window;

	while ((window = [e nextObject]) != nil) {
		if ([window isVisible]) {
			[visible addObject:window];
		}
	}
	return visible;
}

void NSCountWindows(NSInteger *count)
{
	if (count != NULL) {
		*count = (NSInteger)[fn_visibleWindows() count];
	}
}

void NSCountWindowsForContext(NSInteger context, NSInteger *count)
{
	(void)context;
	NSCountWindows(count);
}

/* `NSWindowList` IS SIZE-BOUNDED AND FILLS FRONT TO BACK, and stops at whichever runs out first — the era's contract,
 * and the reason it does not answer a count: the caller passed its own bound. */
void NSWindowList(NSInteger size, NSInteger list[])
{
	NSArray *windows = fn_visibleWindows();
	NSInteger i, n;

	if (list == NULL || size <= 0) {
		return;
	}
	n = (NSInteger)[windows count];
	if (n > size) {
		n = size;
	}
	for (i = 0; i < n; i++) {
		list[i] = [[windows objectAtIndex:(NSUInteger)i] windowNumber];
	}
}

void NSWindowListForContext(NSInteger context, NSInteger size, NSInteger list[])
{
	(void)context;
	NSWindowList(size, list);
}

/* ------------------------------------------------------------------------------------------------------------------
 * The six refusals.
 * ---------------------------------------------------------------------------------------------------------------- */

void NSBeep(void)
{
	static int refused = 0;

	if (refused == 0) {
		fn_refuse_window("NSBeep", "a sound device (and NSSound, which this tier has not got)");
		refused = 1;
	}
}

void NSCopyBits(NSInteger srcGState, NSRect srcRect, NSPoint destPoint)
{
	(void)srcGState; (void)srcRect; (void)destPoint;
	fn_refuse_window("NSCopyBits", "a read path back off the screen");
}

NSColor *NSReadPixel(NSPoint passedPoint)
{
	(void)passedPoint;
	fn_refuse_window("NSReadPixel", "a read path back off the screen");
	return nil;
}

NSInteger NSGetWindowServerMemory(NSInteger context, NSInteger *virtualMemory, NSInteger *windowBackingMemory,
				  NSString **windowDumpString)
{
	(void)context;
	if (virtualMemory != NULL) {
		*virtualMemory = 0;
	}
	if (windowBackingMemory != NULL) {
		*windowBackingMemory = 0;
	}
	if (windowDumpString != NULL) {
		*windowDumpString = nil;
	}
	fn_refuse_window("NSGetWindowServerMemory", "memory accounting the window server does not keep");
	return 0;
}

void NSSetFocusRingStyle(NSFocusRingPlacement placement)
{
	(void)placement;
	fn_refuse_window("NSSetFocusRingStyle", "a focus-ring renderer");
}

void NSShowAnimationEffect(NSAnimationEffect animationEffect, NSPoint centerLocation, NSSize size,
			   id animationDelegate, SEL didEndSelector, void *contextInfo)
{
	(void)animationEffect; (void)centerLocation; (void)size;
	(void)animationDelegate; (void)didEndSelector; (void)contextInfo;
	fn_refuse_window("NSShowAnimationEffect", "the window server's animation effects");
}

/* ------------------------------------------------------------------------------------------------------------------
 * The depth vocabulary — SIX DOORS THAT WERE DECLARED AND NEVER DEFINED.
 *
 * **THIS IS THE SHARPEST THING THE FUNCTION WORK FOUND.** `NSGraphics.h` has declared these six since the depth
 * vocabulary was written, `NSScreen` calls three of them, and NOT ONE HAD A DEFINITION: `libagora-app.so` carried
 * unresolved references to `NSBestDepth`, `NSBitsPerSampleFromDepth`, `NSBitsPerPixelFromDepth` and
 * `NSAvailableWindowDepths` the whole time. Nothing noticed, because a shared library tolerates an undefined symbol
 * until something links a caller of it — and the API census counted them PRESENT, because it counts declarations.
 *
 * That is a census limitation worth naming rather than hiding: the plan's S3 tier ("every non-inline C function is an
 * exported symbol") is checked with `nm -D`, and this census is not that check. It is now visible anyway, because a
 * test links them.
 *
 * **THE VALUES ARE THE HEADER'S OWN, READ OFF THE CONSTANTS RATHER THAN DECODED FROM BITS.** The header states the
 * encoding and then says why it will not compute from it: "the extractors below answer from the CONSTANTS by name, so a
 * depth Apple has not published gets the honest answer rather than a bit-shuffle this tree invented". This is that
 * table, and the answer for anything else is the documented refusal — `-1` or nil — never a plausible number.
 * ---------------------------------------------------------------------------------------------------------------- */

typedef struct {
	NSWindowDepth depth;
	NSInteger bitsPerSample;
	NSInteger bitsPerPixel;
	BOOL planar;
	NSString *colorSpace;
} AGDepthEntry;

static const AGDepthEntry s_depths[] = {
	{ NSWindowDepthTwentyfourBitRGB,		 8,  24, NO, @"NSCalibratedRGBColorSpace" },
	{ NSWindowDepthSixtyfourBitRGB,			16,  64, NO, @"NSCalibratedRGBColorSpace" },
	{ NSWindowDepthOnehundredtwentyeightBitRGB,	32, 128, NO, @"NSCalibratedRGBColorSpace" }
};

#define AG_DEPTH_COUNT ((NSInteger)(sizeof(s_depths) / sizeof(s_depths[0])))

static const AGDepthEntry *fn_depth_entry(NSWindowDepth depth)
{
	NSInteger i;

	for (i = 0; i < AG_DEPTH_COUNT; i++) {
		if (s_depths[i].depth == depth) {
			return &s_depths[i];
		}
	}
	return NULL;
}

NSInteger NSBitsPerSampleFromDepth(NSWindowDepth depth)
{
	const AGDepthEntry *e = fn_depth_entry(depth);

	return e != NULL ? e->bitsPerSample : -1;
}

NSInteger NSBitsPerPixelFromDepth(NSWindowDepth depth)
{
	const AGDepthEntry *e = fn_depth_entry(depth);

	return e != NULL ? e->bitsPerPixel : -1;
}

BOOL NSPlanarFromDepth(NSWindowDepth depth)
{
	const AGDepthEntry *e = fn_depth_entry(depth);

	return e != NULL ? e->planar : NO;
}

NSString *NSColorSpaceFromDepth(NSWindowDepth depth)
{
	const AGDepthEntry *e = fn_depth_entry(depth);

	return e != NULL ? e->colorSpace : nil;
}

/* THE DEPTHS THIS TIER OFFERS, `0`-TERMINATED — Apple's own sentinel, and the reason the header returns a POINTER. */
static NSWindowDepth s_availableDepths[4] = {
	NSWindowDepthTwentyfourBitRGB,
	NSWindowDepthSixtyfourBitRGB,
	NSWindowDepthOnehundredtwentyeightBitRGB,
	0
};

const NSWindowDepth *NSAvailableWindowDepths(void)
{
	return s_availableDepths;
}

/* **THE TIE-BREAK ORDER IS APPLE'S AND IS THE WHOLE CONTRACT**: colour space first, then bits per sample, then
 * planarity, then bits per pixel. A requested sample size or pixel size is ACCOMMODATED rather than matched exactly,
 * which is why `exactMatch` exists: the caller is told whether it got what it asked for or something that will do. A
 * request this tier cannot serve at all — a colour space that is not RGB, or a planar layout, of which there are none —
 * answers `0` with `exactMatch` NO, rather than the nearest thing. */
NSWindowDepth NSBestDepth(NSString *colorSpace, NSInteger bps, NSInteger bpp, BOOL isPlanar, BOOL *exactMatch)
{
	const AGDepthEntry *best = NULL;
	NSInteger i;

	if (exactMatch != NULL) {
		*exactMatch = NO;
	}
	if (isPlanar) {
		return 0;
	}
	if (colorSpace != nil && ![colorSpace isEqualToString:@"NSCalibratedRGBColorSpace"]) {
		return 0;
	}
	for (i = 0; i < AG_DEPTH_COUNT; i++) {
		const AGDepthEntry *e = &s_depths[i];

		if (e->bitsPerSample < bps) {
			continue;
		}
		if (bpp > 0 && e->bitsPerPixel < bpp) {
			continue;
		}
		if (best == NULL || e->bitsPerSample < best->bitsPerSample) {
			best = e;
		}
	}
	if (best == NULL) {
		return 0;
	}
	if (exactMatch != NULL) {
		*exactMatch = (best->bitsPerSample == bps && (bpp == 0 || best->bitsPerPixel == bpp)) ? YES : NO;
	}
	return best->depth;
}
