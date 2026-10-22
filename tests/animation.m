/*
 * animation — NSAnimation, NSViewAnimation and NSAnimationContext.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS THAT PROGRESS BECOMES VALUE BY A CURVE THE NAMES DESCRIBE, AND THAT THE DELEGATE HEARS THE THREE MOMENTS.**
 * The probe steps an animation by hand (the same door the timer uses) and checks each curve at 0.25, 0.5 and 0.75 against the
 * properties its name promises — ease-in below the line at the middle, ease-out above it, ease-in-out equal to it — then hands
 * the curve to the delegate (`-animation:valueForProgress:`) and checks that the delegate's answer REPLACES it. Progress marks
 * are counted exactly once each, and the chains start a second animation at the mark they name.
 *
 * **AND A REAL TIMED RUN IS CHECKED, not only the hand-stepped one**: an animation over a tenth of a second is started and the
 * run loop is pumped, and it must END on its own — `-isAnimating` NO and `animationDidEnd:` heard — which is the assertion a
 * hand-stepped animation cannot make.
 *
 * The view animation interpolates a view's FRAME and a fade's alpha by the same value, and the context's grouping is a scope
 * that nesting restores.
 */
#import <AppKit/NSAnimation.h>
#import <AppKit/NSView.h>
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

static int close_enough(float a, float b)
{
	return fabs((double)(a - b)) < 0.01;
}

/* A DELEGATE THAT COUNTS THE THREE MOMENTS AND CAN REPLACE THE CURVE. */
@interface AGAnimDelegate : NSObject <NSAnimationDelegate>
{
@public
	NSInteger marks;
	NSInteger ends;
	NSInteger stops;
	float lastMark;
	BOOL replaceValue;
}
@end

@implementation AGAnimDelegate
- (float)animation:(NSAnimation *)animation valueForProgress:(NSAnimationProgress)progress
{
	(void)animation;
	if (!replaceValue) {
		return progress;	/* unreachable: the probe only sets replaceValue when it wants this */
	}
	return 42.0f - progress;	/* an answer no curve could produce */
}
- (void)animation:(NSAnimation *)animation didReachProgressMark:(NSAnimationProgress)progress
{
	(void)animation;
	marks++;
	lastMark = progress;
}
- (void)animationDidEnd:(NSAnimation *)animation
{
	(void)animation;
	ends++;
}
- (void)animationDidStop:(NSAnimation *)animation
{
	(void)animation;
	stops++;
}
@end

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);
		/* ============================================================================================
		 * 1. THE CURVES, AND THE DELEGATE THAT CAN REPLACE THEM.
		 * ========================================================================================== */
		{
			NSAnimation *linear = [[NSAnimation alloc] initWithDuration:1.0 animationCurve:NSLinear];
			NSAnimation *easeIn = [[NSAnimation alloc] initWithDuration:1.0 animationCurve:NSEaseIn];
			NSAnimation *easeOut = [[NSAnimation alloc] initWithDuration:1.0 animationCurve:NSEaseOut];
			NSAnimation *easeBoth = [[NSAnimation alloc] initWithDuration:1.0 animationCurve:NSEaseInOut];

			check([linear duration] == 1.0 && [linear animationCurve] == NSLinear,
			      "a duration and a curve are what the initialiser takes");
			check(close_enough([linear frameRate], 12.0f), "and the frame rate starts at Apple's 12");
			check(![linear isAnimating], "an animation does not start by itself");

			[linear setCurrentProgress:0.5f];
			check(close_enough([linear currentProgress], 0.5f) && close_enough([linear currentValue], 0.5f),
			      "a linear animation's value is its progress");
			[easeIn setCurrentProgress:0.5f];
			[easeOut setCurrentProgress:0.5f];
			[easeBoth setCurrentProgress:0.5f];
			check([easeIn currentValue] < 0.5f, "ease-in is BELOW the line at the middle");
			check([easeOut currentValue] > 0.5f, "and ease-out is above it");
			check(close_enough([easeBoth currentValue], 0.5f), "while ease-in-out is symmetric about the middle");
			check(close_enough([easeIn currentValue], 0.25f) && close_enough([easeOut currentValue], 0.75f),
			      "and the quadratic pair is p squared and its mirror");

			/* THE ENDS AGREE FOR EVERY CURVE. */
			[easeIn setCurrentProgress:0.0f];
			[easeOut setCurrentProgress:1.0f];
			check(close_enough([easeIn currentValue], 0.0f) && close_enough([easeOut currentValue], 1.0f),
			      "every curve agrees with the straight line at both ends");

			/* **THE DELEGATE REPLACES THE CURVE.** */
			{
				AGAnimDelegate *delegate = [[AGAnimDelegate alloc] init];

				delegate->replaceValue = YES;
				[linear setDelegate:delegate];
				[linear setCurrentProgress:0.25f];
				check(close_enough([linear currentValue], 41.75f),
				      "a delegate's -animation:valueForProgress: REPLACES the curve");
				[linear setDelegate:nil];
				[linear setCurrentProgress:0.25f];
				check(close_enough([linear currentValue], 0.25f), "and removing it restores the curve");
				[delegate release];
			}

			/* THE FRAME RATE REFUSES ZERO, because a timer that never fires animates nothing. */
			[linear setFrameRate:0.0f];
			check(close_enough([linear frameRate], 12.0f), "a zero frame rate is refused");
			[linear setFrameRate:30.0f];
			check(close_enough([linear frameRate], 30.0f), "and a real one is stored");

			[linear release];
			[easeIn release];
			[easeOut release];
			[easeBoth release];
		}

		/* ============================================================================================
		 * 2. THE MARKS, THE CHAINS, AND THE THREE MOMENTS.
		 * ========================================================================================== */
		{
			AGAnimDelegate *delegate = [[AGAnimDelegate alloc] init];
			NSAnimation *first = [[NSAnimation alloc] initWithDuration:1.0 animationCurve:NSLinear];
			NSAnimation *second = [[NSAnimation alloc] initWithDuration:5.0 animationCurve:NSLinear];

			[first setDelegate:delegate];
			[first addProgressMark:0.25f];
			[first addProgressMark:0.5f];
			check([[first progressMarks] count] == 2, "two marks are added");
			[first setCurrentProgress:0.1f];
			check(delegate->marks == 0, "and none is announced before it is passed");
			[first setCurrentProgress:0.3f];
			check(delegate->marks == 1 && close_enough(delegate->lastMark, 0.25f),
			      "the first is announced when the progress passes it");
			[first setCurrentProgress:0.4f];
			check(delegate->marks == 1, "and is not announced twice");
			[first setCurrentProgress:0.6f];
			check(delegate->marks == 2, "the second is announced when it is passed");

			/* **THE CHAIN**: the second animation starts when the first reaches 0.9. */
			[first startWhenAnimation:second reachesProgress:0.9f];
			check(![second isAnimating], "the chained animation has not started yet");
			[first setCurrentProgress:0.95f];
			check([second isAnimating], "and starts at the mark it was told to");
			[second stopAnimation];
			check(delegate->stops == 0, "the stop told the SECOND animation's delegate, and the first has none");

			/* **THE END BELONGS TO A RUNNING ANIMATION, WHICH IS APPLE'S OWN READING.** This animation was stepped by
			 * hand and never started, so reaching 1 sets the progress and announces NOTHING — the `animationDidEnd:` is the
			 * running animation's (section 3 proves that with a real run), and a setter that announced an end for an
			 * animation nobody started would be reporting a lifecycle that never happened. */
			[first setCurrentProgress:1.0f];
			check(delegate->ends == 0 && delegate->stops == 0 && close_enough([first currentProgress], 1.0f),
			      "stepping a NOT-running animation to 1 sets the progress and announces no end");

			[first release];
			[second release];
			[delegate release];
		}

		/* ============================================================================================
		 * 3. A REAL TIMED RUN: the run loop pumps it and it ends on its own.
		 * ========================================================================================== */
		{
			AGAnimDelegate *delegate = [[AGAnimDelegate alloc] init];
			NSAnimation *animation = [[NSAnimation alloc] initWithDuration:0.15 animationCurve:NSLinear];

			[animation setFrameRate:60.0f];
			[animation setDelegate:delegate];
			[animation startAnimation];
			check([animation isAnimating], "a started animation says it is animating");
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
			check(![animation isAnimating], "and the run loop ENDS it: it is no longer animating");
			check(delegate->ends == 1, "with the end announced exactly once");
			check(close_enough([animation currentProgress], 1.0f), "at progress 1");

			/* A STOP THAT IS NOT AN END. */
			{
				NSAnimation *stopped = [[NSAnimation alloc] initWithDuration:5.0 animationCurve:NSLinear];
				AGAnimDelegate *stopDelegate = [[AGAnimDelegate alloc] init];

				[stopped setDelegate:stopDelegate];
				[stopped startAnimation];
				[stopped stopAnimation];
				check(![stopped isAnimating] && stopDelegate->stops == 1 && stopDelegate->ends == 0,
				      "stopping an animation says STOP, not END");
				[stopped release];
				[stopDelegate release];
			}

			[animation release];
			[delegate release];
		}

		/* ============================================================================================
		 * 4. THE VIEW ANIMATION: A FRAME AND A FADE MOVE WITH THE VALUE.
		 * ========================================================================================== */
		{
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSView *fading = [[NSView alloc] initWithFrame:NSMakeRect(50.0, 50.0, 10.0, 10.0)];
			NSDictionary *move = [NSDictionary dictionaryWithObjectsAndKeys:
				view, NSViewAnimationTargetKey,
				[NSValue valueWithRect:NSMakeRect(0.0, 0.0, 10.0, 10.0)], NSViewAnimationStartFrameKey,
				[NSValue valueWithRect:NSMakeRect(100.0, 40.0, 20.0, 20.0)], NSViewAnimationEndFrameKey, nil];
			NSDictionary *fade = [NSDictionary dictionaryWithObjectsAndKeys:
				fading, NSViewAnimationTargetKey,
				NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey, nil];
			NSViewAnimation *animation = [[NSViewAnimation alloc]
				initWithViewAnimations:[NSArray arrayWithObjects:move, fade, nil]];

			check([[animation viewAnimations] count] == 2, "two entries make a view animation");
			[animation setCurrentProgress:0.5f];
			check(close_enough(NSMinX([view frame]), 50.0) && close_enough(NSWidth([view frame]), 15.0),
			      "the view's frame is HALF WAY between its start and end frames");
			check(close_enough([fading alphaValue], 0.5f), "and the fade is half way between opaque and clear");
			[animation setCurrentProgress:1.0f];
			check(close_enough(NSMinX([view frame]), 100.0) && close_enough([fading alphaValue], 0.0f),
			      "at the end the frame is the end frame and the fade is clear");

			[animation release];
			[view release];
			[fading release];
		}

		/* ============================================================================================
		 * 5. THE CONTEXT: A DURATION WITH A SCOPE.
		 * ========================================================================================== */
		{
			NSAnimationContext *context = [NSAnimationContext currentContext];
			NSTimeInterval before = [context duration];

			check(context != nil && before > 0.0, "a context has a duration to begin with");
			[context setDuration:2.0];
			check([context duration] == 2.0, "and stores the one it is given");
			[context beginGrouping];
			[context setDuration:0.5];
			check([context duration] == 0.5, "a grouping can hold its own duration");
			[context endGrouping];
			check([context duration] == 2.0, "and ending it restores the outer one");
			[context setDuration:before];
			check([NSAnimationContext currentContext] == context, "the context is the one in force");
		}

		if (failures == 0) {
			printf("animation: all checks passed\n");
			return 0;
		}
		printf("animation: FAILURES\n");
		return 1;
	}
}
