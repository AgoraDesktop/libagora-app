/*
 * NSAnimation — a duration, a curve, and a value that moves.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * The number goes 0 → 1 over the duration; the curve maps it; the delegate hears about marks and endings. The timer is the
 * driver and `-setCurrentProgress:` is the one door it uses, which is why a caller (or a test) can step the animation by hand.
 */
#import "NSAnimation.h"
#import "NSView.h"
#import "AppKitRefusal.h"

#import <Foundation/NSTimer.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

NSString * const NSViewAnimationTargetKey = @"NSViewAnimationTargetKey";
NSString * const NSViewAnimationStartFrameKey = @"NSViewAnimationStartFrameKey";
NSString * const NSViewAnimationEndFrameKey = @"NSViewAnimationEndFrameKey";
NSString * const NSViewAnimationEffectKey = @"NSViewAnimationEffectKey";
NSString * const NSViewAnimationFadeInEffect = @"NSViewAnimationFadeInEffect";
NSString * const NSViewAnimationFadeOutEffect = @"NSViewAnimationFadeOutEffect";

/* **THE CURVES, AS ARITHMETIC RATHER THAN AS A TABLE.** Each is monotonic, agrees with the straight line at 0 and 1, and is
 * the shape its name promises; see the header for why they are this tier's own. */
static float fn_curve_value(NSAnimationCurve curve, float p)
{
	switch (curve) {
	case NSEaseIn:
		return p * p;
	case NSEaseOut:
		return 1.0f - (1.0f - p) * (1.0f - p);
	case NSEaseInOut:
		return p * p * (3.0f - 2.0f * p);
	case NSLinear:
	default:
		return p;
	}
}

@interface NSAnimation (AGCcurve)
- (void)cg_finish;
@end

@implementation NSAnimation

- (instancetype)initWithDuration:(NSTimeInterval)duration animationCurve:(NSAnimationCurve)animationCurve
{
	self = [super init];
	if (self != nil) {
		_duration = (duration > 0.0) ? duration : 0.0;
		_curve = animationCurve;
		/* **APPLE'S DEFAULT FRAME RATE IS 12**, which is the era's number and enough for a fade at 10.6's screen rates. */
		_frameRate = 12.0f;
		_blockingMode = NSAnimationNonblocking;
		_delegate = nil;
		_currentProgress = 0.0f;
		_currentValue = 0.0f;
		_progressMarks = [[NSMutableArray alloc] init];
		_startChain = [[NSMutableArray alloc] init];
		_stopChain = [[NSMutableArray alloc] init];
		_animating = NO;
		_timer = nil;
		_startDate = nil;
		_runLoopMode = nil;
	}
	return self;
}

- (void)dealloc
{
	[_timer invalidate];
	[_timer release];
	[_startDate release];
	[_progressMarks release];
	[_startChain release];
	[_stopChain release];
	[_runLoopMode release];
	[super dealloc];
}

/* ---- THE FOUR FACTS ------------------------------------------------------------------------------- */

- (NSTimeInterval)duration { return _duration; }
- (void)setDuration:(NSTimeInterval)duration { _duration = (duration > 0.0) ? duration : 0.0; }
- (NSAnimationCurve)animationCurve { return _curve; }
- (void)setAnimationCurve:(NSAnimationCurve)animationCurve { _curve = animationCurve; }

- (float)frameRate { return _frameRate; }
- (void)setFrameRate:(float)frameRate
{
	if (frameRate <= 0.0f) {
		return;	/* a timer that never fires is an animation that never moves; see the header */
	}
	_frameRate = frameRate;
}

- (NSAnimationBlockingMode)animationBlockingMode { return _blockingMode; }
- (void)setAnimationBlockingMode:(NSAnimationBlockingMode)animationBlockingMode { _blockingMode = animationBlockingMode; }

- (id <NSAnimationDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id <NSAnimationDelegate>)delegate { _delegate = delegate; }	/* NOT RETAINED */

/* ---- THE NUMBER THAT MOVES ------------------------------------------------------------------------ */

- (NSAnimationProgress)currentProgress { return _currentProgress; }
- (float)currentValue { return _currentValue; }

/* **THE ONE DOOR THE TIMER USES, AND THE ONE A CALLER MAY.** It clamps, maps (through the delegate when it answers
 * `-animation:valueForProgress:` and the curve otherwise), tells the delegate about every mark it CROSSED — once each, in
 * the direction of travel — and when the progress reaches 1 it ends the animation. */
- (void)setCurrentProgress:(NSAnimationProgress)progress
{
	NSAnimationProgress previous = _currentProgress;
	NSUInteger i;

	if (progress < 0.0f) {
		progress = 0.0f;
	}
	if (progress > 1.0f) {
		progress = 1.0f;
	}
	_currentProgress = progress;
	if (_delegate != nil && [_delegate respondsToSelector:@selector(animation:valueForProgress:)]) {
		_currentValue = [_delegate animation:self valueForProgress:progress];
	} else {
		_currentValue = fn_curve_value(_curve, progress);
	}
	/* THE MARKS: each is told once, when the progress passes it going up (or down, for a progress that retreats). */
	for (i = 0; i < [_progressMarks count]; i++) {
		float mark = [[_progressMarks objectAtIndex:i] floatValue];
		BOOL crossed = (previous < mark && progress >= mark) || (previous > mark && progress <= mark);

		if (crossed && _delegate != nil
		    && [_delegate respondsToSelector:@selector(animation:didReachProgressMark:)]) {
			[_delegate animation:self didReachProgressMark:mark];
		}
	}
	/* AND THE TWO CHAINS: animations this one starts or stops AT a mark. */
	for (i = 0; i < [_startChain count]; i++) {
		NSArray *entry = [_startChain objectAtIndex:i];
		float mark = [[entry objectAtIndex:1] floatValue];

		if (previous < mark && progress >= mark) {
			[[entry objectAtIndex:0] startAnimation];
		}
	}
	for (i = 0; i < [_stopChain count]; i++) {
		NSArray *entry = [_stopChain objectAtIndex:i];
		float mark = [[entry objectAtIndex:1] floatValue];

		if (previous < mark && progress >= mark) {
			[[entry objectAtIndex:0] stopAnimation];
		}
	}
	if (progress >= 1.0f && _animating) {
		[self cg_finish];
	}
}

/* ---- THE MARKS ----------------------------------------------------------------------------------- */

- (void)addProgressMark:(NSAnimationProgress)progressMark
{
	NSNumber *number = [NSNumber numberWithFloat:progressMark];
	NSUInteger i;

	if (progressMark < 0.0f || progressMark > 1.0f) {
		return;
	}
	if ([_progressMarks containsObject:number]) {
		return;
	}
	/* KEPT ASCENDING, which is what makes the "crossed" walk above read in order. */
	for (i = 0; i < [_progressMarks count]; i++) {
		if ([[_progressMarks objectAtIndex:i] floatValue] > progressMark) {
			[_progressMarks insertObject:number atIndex:i];
			return;
		}
	}
	[_progressMarks addObject:number];
}

- (void)removeProgressMark:(NSAnimationProgress)progressMark
{
	[_progressMarks removeObject:[NSNumber numberWithFloat:progressMark]];
}

- (NSArray *)progressMarks
{
	return [[_progressMarks copy] autorelease];
}

- (void)setProgressMarks:(NSArray *)progressMarks
{
	NSUInteger i;

	[_progressMarks removeAllObjects];
	for (i = 0; progressMarks != nil && i < [progressMarks count]; i++) {
		[self addProgressMark:[[progressMarks objectAtIndex:i] floatValue]];
	}
}

/* ---- STARTING AND STOPPING ----------------------------------------------------------------------- */

- (BOOL)isAnimating { return _animating; }

/* **THE TIMER IS THE DRIVER.** A duration of zero ends at once, which is the honest answer for "animate over no time"; a
 * duration with a rate schedules a repeating timer and each firing asks the clock how far it has got. */
- (void)startAnimation
{
	if (_animating) {
		return;
	}
	_animating = YES;
	[_startDate release];
	_startDate = [[NSDate date] retain];
	[self setCurrentProgress:0.0f];
	if (_duration <= 0.0) {
		[self setCurrentProgress:1.0f];
		return;
	}
	[_timer invalidate];
	[_timer release];
	_timer = [[NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)(1.0 / (double)_frameRate)
						  target:self selector:@selector(cg_animationFired:)
						userInfo:nil repeats:YES] retain];
}

- (void)stopAnimation
{
	if (!_animating) {
		return;
	}
	_animating = NO;
	[_timer invalidate];
	[_timer release];
	_timer = nil;
	[_startDate release];
	_startDate = nil;
	if (_delegate != nil && [_delegate respondsToSelector:@selector(animationDidStop:)]) {
		[_delegate animationDidStop:self];
	}
}

/* THE END, WHICH IS NOT A STOP: the delegate is told `animationDidEnd:` and the timer is dropped. */
- (void)cg_finish
{
	_animating = NO;
	[_timer invalidate];
	[_timer release];
	_timer = nil;
	[_startDate release];
	_startDate = nil;
	if (_delegate != nil && [_delegate respondsToSelector:@selector(animationDidEnd:)]) {
		[_delegate animationDidEnd:self];
	}
}

- (void)cg_animationFired:(NSTimer *)timer
{
	NSTimeInterval elapsed;

	(void)timer;
	if (!_animating || _startDate == nil || _duration <= 0.0) {
		return;
	}
	elapsed = -[_startDate timeIntervalSinceNow];
	[self setCurrentProgress:(NSAnimationProgress)(elapsed / _duration)];
}

- (void)startWhenAnimation:(NSAnimation *)animation reachesProgress:(NSAnimationProgress)startProgress
{
	if (animation == nil) {
		return;
	}
	[_startChain addObject:[NSArray arrayWithObjects:animation,
				[NSNumber numberWithFloat:startProgress], nil]];
}

- (void)stopWhenAnimation:(NSAnimation *)animation reachesProgress:(NSAnimationProgress)stopProgress
{
	if (animation == nil) {
		return;
	}
	[_stopChain addObject:[NSArray arrayWithObjects:animation,
			       [NSNumber numberWithFloat:stopProgress], nil]];
}

- (void)clearStartAnimation { [_startChain removeAllObjects]; }
- (void)clearStopAnimation { [_stopChain removeAllObjects]; }

/* ONE MODE: the default one, because a timer scheduled in a mode nothing runs in is an animation that never fires. */
- (NSArray *)runLoopModesForAnimating
{
	if (_runLoopMode == nil) {
		_runLoopMode = [NSDefaultRunLoopMode retain];
	}
	return [NSArray arrayWithObject:_runLoopMode];
}

@end

/* ==================================================================================================================
 * THE CONTEXT.
 * ================================================================================================================ */

static NSAnimationContext *sCurrentContext = nil;

@implementation NSAnimationContext

+ (NSAnimationContext *)currentContext
{
	if (sCurrentContext == nil) {
		sCurrentContext = [[NSAnimationContext alloc] init];
	}
	return sCurrentContext;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		/* **A QUARTER OF A SECOND**, which is the era's default for an implicit animation. */
		_duration = 0.25;
	}
	return self;
}

/* **A GROUPING IS A SCOPE FOR THE DURATION, AND NESTING RESTORES IT.** The context is one object, so the scope is its own
 * state: beginning a grouping is a push and ending it is a pop — implemented as a stack of durations held here. */
static NSMutableArray *sGroupingStack = nil;

- (void)beginGrouping
{
	if (sGroupingStack == nil) {
		sGroupingStack = [[NSMutableArray alloc] init];
	}
	[sGroupingStack addObject:[NSNumber numberWithDouble:_duration]];
}

- (void)endGrouping
{
	NSNumber *previous;

	if ([sGroupingStack count] == 0) {
		return;
	}
	previous = [[sGroupingStack lastObject] retain];
	[sGroupingStack removeLastObject];
	_duration = [previous doubleValue];
	[previous release];
}

- (NSTimeInterval)duration { return _duration; }
- (void)setDuration:(NSTimeInterval)duration { _duration = (duration > 0.0) ? duration : 0.0; }

@end

/* ==================================================================================================================
 * THE VIEW ANIMATION: FRAMES AND FADES.
 * ================================================================================================================ */

@implementation NSViewAnimation

- (instancetype)initWithViewAnimations:(NSArray *)viewAnimations
{
	self = [super initWithDuration:0.25 animationCurve:NSEaseInOut];
	if (self != nil) {
		_viewAnimations = [viewAnimations copy];
	}
	return self;
}

- (void)dealloc
{
	[_viewAnimations release];
	[super dealloc];
}

- (NSArray *)viewAnimations { return [[_viewAnimations copy] autorelease]; }
- (void)setViewAnimations:(NSArray *)viewAnimations
{
	NSArray *held = [viewAnimations copy];

	[_viewAnimations release];
	_viewAnimations = held;
}

/* **EACH ENTRY IS APPLIED AT EVERY PROGRESS**, which is what makes this a VIEW animation rather than a number: a start and end
 * frame are interpolated by the value, and a fade sets the view's alpha (recorded — `NSView`'s header says the effect of its
 * alpha is not drawn by this tier, so the value is what a caller can read). */
- (void)setCurrentProgress:(NSAnimationProgress)progress
{
	NSUInteger i;
	float value;

	[super setCurrentProgress:progress];
	value = [self currentValue];
	for (i = 0; _viewAnimations != nil && i < [_viewAnimations count]; i++) {
		NSDictionary *entry = [_viewAnimations objectAtIndex:i];
		id target = [entry objectForKey:NSViewAnimationTargetKey];

		if (target == nil || ![target isKindOfClass:[NSView class]]) {
			continue;
		}
		{
			NSValue *start = [entry objectForKey:NSViewAnimationStartFrameKey];
			NSValue *end = [entry objectForKey:NSViewAnimationEndFrameKey];
			NSString *effect = [entry objectForKey:NSViewAnimationEffectKey];

			if (start != nil && end != nil) {
				NSRect a = [start rectValue];
				NSRect b = [end rectValue];
				NSRect frame = NSMakeRect(a.origin.x + (b.origin.x - a.origin.x) * value,
							  a.origin.y + (b.origin.y - a.origin.y) * value,
							  a.size.width + (b.size.width - a.size.width) * value,
							  a.size.height + (b.size.height - a.size.height) * value);

				[(NSView *)target setFrame:frame];
			}
			if ([effect isEqual:NSViewAnimationFadeInEffect]) {
				[(NSView *)target setAlphaValue:value];
			} else if ([effect isEqual:NSViewAnimationFadeOutEffect]) {
				[(NSView *)target setAlphaValue:1.0f - value];
			}
		}
	}
}

@end
