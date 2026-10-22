/*
 * stepper_and_secure — four classes: the stepper pair and the secure field pair.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE STEPPER'S CLAIM IS THAT THE PRESS IS THE STEP, AND THAT THE ARROW PRESSED DECIDES THE DIRECTION.** The probe drives
 * the cell's own tracking hooks — the non-modal protocol the slider uses — with points in each half of the control, and
 * checks the value, the clamp at the ends, the wrap, the action the target receives, and that a drag does NOT step again.
 * The direction check is the one a flip can break, so the probe runs the same press on a FLIPPED and an UNFLIPPED view and
 * requires opposite answers from the same half. **AND THE PICTURE HAS TO AGREE WITH THE PRESS**: the render checks that the
 * up arrow is WIDEST AT ITS BASE, because the first version drew both triangles pointing inward — a top arrow that pointed
 * down — and every press assertion still passed, since a press reads a band rather than a triangle.
 *
 * **AND THE SECURE FIELD'S CLAIM IS THE INK.** `-cg_contentText` is what the base draws AND measures, so the test checks
 * that a secure cell answers one bullet per character (and the same count back with `-echosBullets` off), then renders the
 * field and requires DOTS rather than the letters — through the pixel count, because a substitution that is not drawn is
 * not a password field.
 */
#import <AppKit/NSStepper.h>
#import <AppKit/NSStepperCell.h>
#import <AppKit/NSSecureTextField.h>
#import <AppKit/NSSecureTextFieldCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* A TARGET THAT RECORDS THE ACTIONS IT IS SENT. */
@interface AGStepTarget : NSObject
{
@public
	NSInteger actions;
	SEL lastAction;
}
@end

@implementation AGStepTarget
- (void)stepped:(id)sender
{
	(void)sender;
	actions++;
	lastAction = @selector(stepped:);
}
@end

/* A FLIPPED VIEW AND AN UNFLIPPED ONE, so the direction test can ask both. */
@interface AGPlainView : NSView
@end
@implementation AGPlainView
- (BOOL)isFlipped { return NO; }
@end

@interface AGFlippedView : NSView
@end
@implementation AGFlippedView
- (BOOL)isFlipped { return YES; }
@end

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);
		/* ============================================================================================
		 * 1. THE STEPPER'S DEFAULTS ARE APPLE'S.
		 * ========================================================================================== */
		{
			NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(0.0, 0.0, 19.0, 27.0)];

			check(stepper != nil, "a stepper is made");
			check([stepper minValue] == 0.0 && [stepper maxValue] == 59.0,
			      "with Apple's default range of 0 to 59");
			check([stepper increment] == 1.0, "and a step of one");
			check([stepper valueWraps] && [stepper autorepeat],
			      "and both policies on, which is Apple's default");
			check([[stepper cell] isKindOfClass:[NSStepperCell class]],
			      "and the cell it made is an NSStepperCell");

			/* THE FORWARDS REACH THE CELL. */
			[stepper setMinValue:10.0];
			[stepper setMaxValue:20.0];
			[stepper setIncrement:2.0];
			[stepper setValueWraps:NO];
			[stepper setAutorepeat:NO];
			check([stepper minValue] == 10.0 && [stepper maxValue] == 20.0
				      && [stepper increment] == 2.0 && ![stepper valueWraps] && ![stepper autorepeat],
			      "and every property forward is answered by the cell");
			[stepper setIncrement:0.0];
			check([stepper increment] == 2.0, "a zero step is refused, because a stepper that cannot move is broken");
			[stepper release];
		}

		/* ============================================================================================
		 * 2. THE PRESS IS THE STEP, AND THE ARROW DECIDES THE DIRECTION — in both flips.
		 * ========================================================================================== */
		{
			AGPlainView *plain = [[AGPlainView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 40.0)];
			AGFlippedView *flipped = [[AGFlippedView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 40.0)];
			/* **THE CONTROL VIEW IS THE CONTROL, because that is what a cell's action goes THROUGH**: `-sendAction:to:`
			 * is `NSControl`'s, and a cell whose "control view" was a bare `NSView` would step silently and send nothing —
			 * which is exactly what the first version of this probe measured. */
			NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 40.0)];
			NSStepperCell *cell = (NSStepperCell *)[stepper cell];
			AGStepTarget *target = [[AGStepTarget alloc] init];

			[cell setMinValue:0.0];
			[cell setMaxValue:10.0];
			[cell setIncrement:1.0];
			[cell setValueWraps:NO];
			[cell setTarget:target];
			[cell setAction:@selector(stepped:)];
			[stepper setTarget:target];
			[stepper setAction:@selector(stepped:)];
			[cell setDoubleValue:5.0];

			/* UNFLIPPED: the UPPER half is the LARGER y. */
			check([cell startTrackingAt:NSMakePoint(20.0, 35.0) inView:stepper],
			      "a press on the upper arrow starts tracking");
			check([cell doubleValue] == 6.0, "and steps the value UP in an unflipped view");
			check(target->actions == 1, "sending the action once");
			[cell stopTracking:NSMakePoint(20.0, 35.0) at:NSMakePoint(20.0, 35.0) inView:stepper mouseIsUp:YES];

			check([cell startTrackingAt:NSMakePoint(20.0, 5.0) inView:stepper], "a press on the lower arrow tracks");
			check([cell doubleValue] == 5.0, "and steps it DOWN");
			check(target->actions == 2, "and sends the action again");
			[cell stopTracking:NSMakePoint(20.0, 5.0) at:NSMakePoint(20.0, 5.0) inView:stepper mouseIsUp:YES];

			/* FLIPPED: the SAME upper press is the SMALLER y. */
			[cell setDoubleValue:5.0];
			check([cell startTrackingAt:NSMakePoint(20.0, 5.0) inView:flipped], "the upper arrow in a flipped view");
			check([cell doubleValue] == 6.0, "is the smaller y, and it still steps UP");
			[cell stopTracking:NSMakePoint(20.0, 5.0) at:NSMakePoint(20.0, 5.0) inView:flipped mouseIsUp:YES];

			/* **THE CLAMP AND THE WRAP.** The target's count is reset first, because a flippage press above sent its
			 * action through a bare view (a cell's action needs a CONTROL to go through) and this assertion is about what
			 * the NO-CHANGE press does, not about the running total. */
			target->actions = 0;
			[cell setDoubleValue:10.0];
			[cell startTrackingAt:NSMakePoint(20.0, 35.0) inView:stepper];
			check([cell doubleValue] == 10.0,
			      "at the maximum with wrapping off the value STOPS");
			check(target->actions == 0, "and the action is not sent for a press that changed nothing");
			[cell stopTracking:NSMakePoint(20.0, 35.0) at:NSMakePoint(20.0, 35.0) inView:stepper mouseIsUp:YES];

			[cell setValueWraps:YES];
			[cell startTrackingAt:NSMakePoint(20.0, 35.0) inView:stepper];
			check([cell doubleValue] == 0.0, "with wrapping ON the maximum wraps to the minimum");
			[cell stopTracking:NSMakePoint(20.0, 35.0) at:NSMakePoint(20.0, 35.0) inView:stepper mouseIsUp:YES];

			/* **A DRAG ACROSS THE CELL DOES NOT STEP AGAIN.** */
			{
				double before = [cell doubleValue];

				[cell startTrackingAt:NSMakePoint(20.0, 5.0) inView:stepper];
				[cell continueTracking:NSMakePoint(20.0, 5.0) at:NSMakePoint(20.0, 35.0) inView:stepper];
				[cell continueTracking:NSMakePoint(20.0, 35.0) at:NSMakePoint(20.0, 5.0) inView:stepper];
				check([cell doubleValue] == (before == 0.0 ? 10.0 : before - 1.0),
				      "one press is one step, however far the pointer is dragged");
				[cell stopTracking:NSMakePoint(20.0, 5.0) at:NSMakePoint(20.0, 5.0) inView:stepper mouseIsUp:YES];
			}

			/* AND THE CELL DRAWS: ink inside the frame, in the platform's control greys. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:40 pixelsHigh:40 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:160 bitsPerPixel:32];
				int x, y, ink = 0;

				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, 40.0, 40.0) inView:plain];
				for (y = 0; y < 40; y++) {
					for (x = 0; x < 40; x++) {
						NSColor *c = [rep colorAtX:x y:y];

						if (c != nil && [c alphaComponent] > 0.4 && [c redComponent] < 0.75) {
							ink++;
						}
					}
				}
				printf("  (note: the stepper cell drew %d dark pixels)\n", ink);
				check(ink > 40, "the cell paints its bezel and two arrows");
				/* **AND THE ARROW POINTS OUT, NOT IN.** The press tests above read the BAND, so a cell that drew its
				 * top triangle pointing down would pass every one of them — which is what shipped until this check.
				 * The up arrow's apex is near the top of its band and its base near the middle, so the row nearer the
				 * middle must have MORE ink. The bitmap's rows run opposite the drawing, so y converts once. */
				{
					int apex = 0, base = 0;

					for (x = 15; x < 25; x++) {
						NSColor *a = [rep colorAtX:x y:(39 - 35)];
						NSColor *b = [rep colorAtX:x y:(39 - 25)];

						if (a != nil && [a redComponent] < 0.75) {
							apex++;
						}
						if (b != nil && [b redComponent] < 0.75) {
							base++;
						}
					}
					printf("  (note: the up arrow's apex row has %d ink pixels, its base row %d)\n", apex, base);
					check(base > apex, "and its up arrow is widest at the base: it points UP, not inward");
				}
				[rep release];
			}

			[stepper release];
			[target release];
			[plain release];
			[flipped release];
		}

		/* ============================================================================================
		 * 3. THE SECURE FIELD: BULLETS IN THE TEXT THE BASE DRAWS, AND IN THE PIXELS.
		 * ========================================================================================== */
		{
			NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 160.0, 24.0)];
			NSSecureTextFieldCell *cell = (NSSecureTextFieldCell *)[field cell];

			check(cell != nil && [cell isKindOfClass:[NSSecureTextFieldCell class]],
			      "a secure field is made with a secure cell");
			check([cell echosBullets], "and the cell echoes bullets by default, which is what makes it secure");

			[field setStringValue:@"hunter2"];
			check([[cell cg_contentText] length] == 7,
			      "the text the cell DRAWS is one character per character of the value");
			check([[cell cg_contentText] isEqual:@"•••••••"],
			      "and each of them is the era's bullet");

			[cell setEchosBullets:NO];
			check([[cell cg_contentText] isEqual:@"hunter2"], "with the flag off the cell shows the string");

			/* **THE PIXELS, because a substitution that is not drawn is not a password field.** The field is rendered twice —
			 * bullets and letters — and the dark ink differs: seven bullets are not seven letters. */
			{
				NSBitmapImageRep *bullets = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:160 pixelsHigh:24 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:640 bitsPerPixel:32];
				NSBitmapImageRep *letters = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:160 pixelsHigh:24 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:640 bitsPerPixel:32];
				int bx, by;
				int bulletsInk = 0;
				int lettersInk = 0;

				[cell setEchosBullets:YES];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bullets]];
				[field displayRect:[field bounds]];
				[cell setEchosBullets:NO];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:letters]];
				[field displayRect:[field bounds]];

				for (by = 0; by < 24; by++) {
					for (bx = 0; bx < 160; bx++) {
						NSColor *a = [bullets colorAtX:bx y:by];
						NSColor *b = [letters colorAtX:bx y:by];

						if (a != nil && [a alphaComponent] > 0.4 && [a redComponent] < 0.5) {
							bulletsInk++;
						}
						if (b != nil && [b alphaComponent] > 0.4 && [b redComponent] < 0.5) {
							lettersInk++;
						}
					}
				}
				printf("  (note: bullets drew %d dark pixels, letters %d)\n", bulletsInk, lettersInk);
				check(bulletsInk > 0, "the secure rendering draws the bullets");
				check(bulletsInk != lettersInk,
				      "and it is NOT the same ink as the letters, so the substitution reached the pixels");
				[bullets release];
				[letters release];
			}

			[field release];
		}

		if (failures == 0) {
			printf("stepper_and_secure: all checks passed\n");
			return 0;
		}
		printf("stepper_and_secure: FAILURES\n");
		return 1;
	}
}
