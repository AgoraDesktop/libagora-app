/*
 * NSAnimation.h — A DURATION, A CURVE, AND A VALUE THAT MOVES.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **AN ANIMATION IS A NUMBER THAT GOES FROM 0 TO 1 OVER A DURATION**, and everything else is how that number is produced and
 * who is told about it. `-currentProgress` is the linear fraction of the duration that has passed; `-currentValue` is that
 * fraction MAPPED by the curve (or by the delegate's own `-animation:valueForProgress:`); and the delegate hears about three
 * moments — a progress mark reached, the end, and a stop that was not the end.
 *
 * **IT IS DRIVEN BY A TIMER AT `-frameRate`**, which is the era's mechanism and this tier's too: `-startAnimation` schedules
 * an `NSTimer` and each firing sets the progress from the wall clock. A caller that wants to drive it by hand — a test, or a
 * view that already has a frame loop — calls `-setCurrentProgress:` directly, which is the same door the timer uses.
 *
 * **THE CURVES ARE THIS TIER'S OWN ARITHMETIC AND ARE NAMED AS SUCH.** Apple's ease-in and ease-out are cubic Béziers whose
 * control points it does not publish; this tier uses the standard quadratic pair (`p²` and `1-(1-p)²`) and a smoothstep for
 * ease-in-out (`3p²-2p³`). They are monotonic, they agree with the straight line at both ends, and they are the shape the
 * names promise — which is the claim a caller can check.
 *
 * **`-startWhenAnimation:reachesProgress:` IS HOW ANIMATIONS CHAIN**: an animation can start or stop ANOTHER one when it
 * passes a mark, which is the era's way to sequence two effects without a completion block (there were no blocks).
 */
#ifndef APPKIT_NSANIMATION_H
#define APPKIT_NSANIMATION_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@class NSTimer;
@class NSAnimation;

/* THE CURVE AND THE BLOCKING MODE, in Apple's order. A blocking animation spins its own run loop for its duration, which is
 * why a caller has to ask for it. */
typedef NSUInteger NSAnimationCurve;
enum {
	NSEaseInOut = 0,
	NSEaseIn = 1,
	NSEaseOut = 2,
	NSLinear = 3
};

typedef NSUInteger NSAnimationBlockingMode;
enum {
	NSAnimationBlocking = 0,
	NSAnimationNonblocking = 1,
	NSAnimationNonblockingThreaded = 2
};

typedef float NSAnimationProgress;

/* **THE THREE THINGS A DELEGATE IS TOLD, AND THE ONE IT DECIDES.** `-animation:valueForProgress:` is the interesting one:
 * a delegate that answers it REPLACES the curve, which is how a caller animates something with a shape of its own. */
@protocol NSAnimationDelegate <NSObject>
@optional
- (float)animation:(NSAnimation *)animation valueForProgress:(NSAnimationProgress)progress;
- (void)animation:(NSAnimation *)animation didReachProgressMark:(NSAnimationProgress)progress;
- (void)animationDidEnd:(NSAnimation *)animation;
- (void)animationDidStop:(NSAnimation *)animation;
@end

@interface NSAnimation : NSObject
{
	NSTimeInterval _duration;
	float _frameRate;
	NSAnimationCurve _curve;
	NSAnimationBlockingMode _blockingMode;
	id _delegate;			/* NOT RETAINED: this tree's rule for every delegate */
	NSAnimationProgress _currentProgress;
	float _currentValue;
	NSMutableArray *_progressMarks;	/* RETAINED: NSNumber floats, ascending */
	/* THE TWO CHAINS: an animation to start (or stop) when this one reaches a progress. Each entry is a two-element array
	 * of the other animation and its mark. */
	NSMutableArray *_startChain;
	NSMutableArray *_stopChain;
	BOOL _animating;
	NSTimer *_timer;		/* RETAINED while it runs; the run loop also holds it */
	NSDate *_startDate;		/* RETAINED while it runs */
	NSString *_runLoopMode;	/* RETAINED: the one mode the timer runs in */
}

/* THE DESIGNATED INITIALISER: a duration in seconds and the curve. */
- (instancetype)initWithDuration:(NSTimeInterval)duration animationCurve:(NSAnimationCurve)animationCurve;

- (NSTimeInterval)duration;
- (void)setDuration:(NSTimeInterval)duration;
- (NSAnimationCurve)animationCurve;
- (void)setAnimationCurve:(NSAnimationCurve)animationCurve;
/* THE TIMER'S RATE, in firings per second. A rate of zero or less is refused (the setter keeps the old one), because a timer
 * that never fires is an animation that never moves. */
- (float)frameRate;
- (void)setFrameRate:(float)frameRate;
- (NSAnimationBlockingMode)animationBlockingMode;
- (void)setAnimationBlockingMode:(NSAnimationBlockingMode)animationBlockingMode;

- (nullable id <NSAnimationDelegate>)delegate;
- (void)setDelegate:(nullable id <NSAnimationDelegate>)delegate;

/* **THE TWO NUMBERS THAT MOVE**, and the door that sets the first: `-setCurrentProgress:` is what the timer calls, and it is
 * public because a caller with its own frame loop is expected to call it too. */
- (NSAnimationProgress)currentProgress;
- (void)setCurrentProgress:(NSAnimationProgress)progress;
- (float)currentValue;

/* THE MARKS A DELEGATE WANTS TO BE TOLD ABOUT, and whether the animation is running now. */
- (void)addProgressMark:(NSAnimationProgress)progressMark;
- (void)removeProgressMark:(NSAnimationProgress)progressMark;
- (NSArray *)progressMarks;
- (void)setProgressMarks:(NSArray *)progressMarks;
- (BOOL)isAnimating;

/* START AND STOP, and the chains: this animation starts (or stops) ANOTHER one when it reaches a progress. */
- (void)startAnimation;
- (void)stopAnimation;
- (void)startWhenAnimation:(NSAnimation *)animation reachesProgress:(NSAnimationProgress)startProgress;
- (void)stopWhenAnimation:(NSAnimation *)animation reachesProgress:(NSAnimationProgress)stopProgress;
- (void)clearStartAnimation;
- (void)clearStopAnimation;

/* THE MODES THE TIMER RUNS IN, which is `NSDefaultRunLoopMode` unless a caller says otherwise. */
- (NSArray *)runLoopModesForAnimating;

@end

/* ==================================================================================================================
 * THE CONTEXT: THE DURATION AN IMPLICIT ANIMATION USES.
 * ================================================================================================================ */

/* **A GROUPING IS A SCOPE FOR A DURATION.** `+currentContext` answers the one in force; `-beginGrouping`/`-endGrouping`
 * bracket a region in which the context's duration applies (and nesting restores the outer duration on the way out). This
 * tier has no implicit-animation machinery to read it — the explicit `NSAnimation` above is how a value moves — so the
 * context is a STACK OF DURATIONS that a caller sets and reads, which is what the era's own API is once the `animator` proxy
 * is taken away. */
@interface NSAnimationContext : NSObject
{
	NSTimeInterval _duration;
}

+ (NSAnimationContext *)currentContext;

- (void)beginGrouping;
- (void)endGrouping;

- (NSTimeInterval)duration;
- (void)setDuration:(NSTimeInterval)duration;

@end

/* ==================================================================================================================
 * THE VIEW ANIMATION: FRAMES AND FADES FOR EXISTING VIEWS.
 * ================================================================================================================ */

/* **THE FOUR KEYS AND THE TWO EFFECTS.** Each entry of the array is a dictionary: the view under the target key, and either a
 * START and END frame or a FADE effect. */
extern NSString * const NSViewAnimationTargetKey;
extern NSString * const NSViewAnimationStartFrameKey;
extern NSString * const NSViewAnimationEndFrameKey;
extern NSString * const NSViewAnimationEffectKey;
extern NSString * const NSViewAnimationFadeInEffect;
extern NSString * const NSViewAnimationFadeOutEffect;

@interface NSViewAnimation : NSAnimation
{
	NSArray *_viewAnimations;	/* RETAINED: the dictionaries, as given */
}

/* THE ARRAY IS THE WHOLE ANIMATION: each entry names a view and what to do to it. */
- (instancetype)initWithViewAnimations:(NSArray *)viewAnimations;
- (NSArray *)viewAnimations;
- (void)setViewAnimations:(NSArray *)viewAnimations;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSANIMATION_H */
