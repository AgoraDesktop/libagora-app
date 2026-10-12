/* NSScreen.m — the screen as the compositor describes its output.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 *
 * THE SIZE COMES FROM THE SEAM, WHICH LEARNS IT FROM `wl_output`: a Wayland client is not told the screen once
 * and for all, it is told the output's CURRENT MODE when the compositor sends it. So a screen with no answer
 * yet is a ZERO RECT rather than an invented size — the same rule the X version followed when the display was
 * unreachable.
 */
#import <AppKit/NSScreen.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include "AGWindowServer.h"

#include <stdio.h>

NSString *NSDeviceSize = @"NSDeviceSize";
NSString *NSDeviceResolution = @"NSDeviceResolution";
NSString *NSDeviceColorSpaceName = @"NSDeviceColorSpaceName";
NSString *NSDeviceBitsPerSample = @"NSDeviceBitsPerSample";
NSString *NSDeviceIsScreen = @"NSDeviceIsScreen";
NSString *NSDeviceIsPrinter = @"NSDeviceIsPrinter";
NSString *NSScreenColorSpaceDidChangeNotification = @"NSScreenColorSpaceDidChangeNotification";

/* ONE CONNECTION, MADE ON DEMAND — the same connection `NSWindow` uses, because the seam keeps one per process
 * and asking here is simply how a screen learns anything about the output. */
static NSScreen *s_main;

static AGWindowServer *fn_screen_server(void)
{
	return AGWindowServerConnect();
}

@implementation NSScreen

+ (NSArray *)screens
{
	NSScreen *main = [self mainScreen];

	/* ONE SCREEN, AND THE ARRAY IS REAL: a caller indexes it, and the count is the truth about this process's
	 * view of the server — see the header. `XineramaQueryScreens` would be the door to more, and it is a
	 * dependency this tier has not taken.
	 *
	 * **AND WITH NO SERVER THERE ARE ZERO SCREENS, WHICH IS A FIX RATHER THAN A STYLE.** This used to be
	 * `[NSArray arrayWithObject:[self mainScreen]]` unconditionally, and `+mainScreen` is nullable: an array
	 * built from a nil is not an array, it is undefined behaviour waiting for the first caller to run without a
	 * display. The count is the honest answer either way. */
	if (main == nil) {
		return [NSArray array];
	}
	return [NSArray arrayWithObject:main];
}

+ (NSScreen *)deepestScreen
{
	NSArray *all = [self screens];
	NSScreen *best = nil;
	NSInteger best_bits = -1;
	NSUInteger i;

	/* **THE DEEPEST OF THE SCREENS THIS PROCESS CAN SEE, COMPARED THROUGH THE DEPTH FAMILY.** Apple asks for the
	 * greatest bit depth, so the comparison goes through `NSBitsPerPixelFromDepth` rather than through an
	 * `NSWindowDepth`'s own ordering — which is a PACKED value whose order is not its depth and is not a
	 * documented order either. One family, one comparison. */
	for (i = 0; i < [all count]; i++) {
		NSScreen *s = [all objectAtIndex:i];
		NSInteger bits = (NSInteger)NSBitsPerPixelFromDepth([s depth]);

		if (best == nil || bits > best_bits) {
			best = s;
			best_bits = bits;
		}
	}
	return best;
}

+ (NSScreen *)mainScreen
{
	if (s_main == nil) {
		s_main = [[NSScreen alloc] init];
	}
	return s_main;
}

- (NSRect)frame
{
	int width = 0, height = 0;

	AGWindowServerScreenSize(fn_screen_server(), &width, &height, NULL);
	if (width <= 0 || height <= 0) {
		/* NO OUTPUT HAS DESCRIBED ITSELF YET — and a ZERO RECT rather than an invented size, which is the answer
		 * that makes a caller's arithmetic fail visibly instead of placing a window somewhere plausible and
		 * wrong. */
		return NSZeroRect;
	}
	return NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height);
}

- (NSRect)visibleFrame
{
	AGWindowServer *server = fn_screen_server();
	NSRect whole = [self frame];
	int x = 0, y = 0, width = 0, height = 0;

	/* **THE FURNITURE IS THE SERVER'S, SO THE WORK AREA IS THE SERVER'S TO SAY** — and that is what this door
	 * has been missing: it used to answer the frame itself, because there was no menu bar to subtract and a
	 * remembered height would have agreed with no menu bar anybody has. Now there is one, and the answer comes
	 * from the component that owns it. */
	AGWindowServerWorkArea(server, &x, &y, &width, &height);
	if (width <= 0 || height <= 0) {
		/* A COMPOSITOR THAT DOES NOT SAY gets the whole screen, which is the honest reading of "no furniture
		 * was reserved" rather than an invented one. */
		return whole;
	}
	/* THE SEAM MEASURES DOWN FROM THE TOP, AS A DISPLAY DOES; COCOA MEASURES UP FROM THE BOTTOM. */
	return NSMakeRect((CGFloat)x, whole.size.height - (CGFloat)(y + height), (CGFloat)width, (CGFloat)height);
}

- (NSDictionary *)deviceDescription
{
	NSMutableDictionary *into = [NSMutableDictionary dictionary];
	NSRect f = [self frame];

	/* **THE KEYS ARE APPLE'S, THE VALUES' TYPES ARE APPLE'S TOO, AND TWO KEYS ARE MISSING ON PURPOSE.** The
	 * first version of this filled `NSDeviceSize` with a NUMBER and `NSDeviceResolution` with an empty STRING —
	 * each is an `NSValue` wrapping an `NSSize`, and this tree's `NSValue` has no size-valued constructor, so a
	 * caller reading them would get the wrong CLASS rather than the wrong number. A missing key is a caller's
	 * `nil` check; a key of the wrong type is a crash waiting for one. The two arrive with the value type.
	 *
	 * AND `NSDeviceIsScreen`'S VALUE IS THE CONSTANT ITSELF, which is Apple's idiom: the key's PRESENCE is the
	 * question, and the answer is the key — so `[desc objectForKey:NSDeviceIsScreen] == NSDeviceIsScreen`. */
	(void)f;
	[into setObject:[NSNumber numberWithInt:8] forKey:NSDeviceBitsPerSample];
	[into setObject:@"NSCalibratedRGBColorSpace" forKey:NSDeviceColorSpaceName];
	[into setObject:NSDeviceIsScreen forKey:NSDeviceIsScreen];
	return into;
}

- (NSWindowDepth)depth
{
	int width = 0, height = 0;

	AGWindowServerScreenSize(fn_screen_server(), &width, &height, NULL);
	if (width <= 0 || height <= 0) {
		/* NO OUTPUT, NO DEPTH — "no depth" is the vocabulary's own word for it. */
		return 0;
	}
	/* **THE ANSWER COMES FROM THE FAMILY RATHER THAN FROM A BIT-SHUFFLE.** The seam's frame buffer is 32-bit
	 * `XRGB8888`, so the depth this tier can honestly claim is EIGHT BITS PER SAMPLE of RGB, and an
	 * `NSWindowDepth` is one of three PACKED values — so the mapping is asked of `NSBestDepth`, which is the
	 * function whose job the encoding is. Two implementations of it would eventually disagree; there is one. */
	return NSBestDepth(nil, 8, 0, NO, NULL);
}

- (const NSWindowDepth *)supportedWindowDepths
{
	return NSAvailableWindowDepths();
}

- (NSString *)localizedName
{
	const char *name = NULL;

	/* THE COMPOSITOR'S OWN MODEL STRING FOR THE OUTPUT, which is the closest thing to a user-visible name a
	 * Wayland client is given — Apple's is the name the display's preferences carry. */
	AGWindowServerScreenSize(fn_screen_server(), NULL, NULL, &name);
	return name != NULL ? [NSString stringWithUTF8String:name] : @"Display";
}

- (CGFloat)userSpaceScaleFactor
{
	/* ONE, BECAUSE NOTHING SCALES HERE: this tree's windows are in pixels and the compositor has one coordinate
	 * space. A Retina-shaped factor would be a promise about a backing store that does not exist yet. */
	return 1.0;
}

@end
