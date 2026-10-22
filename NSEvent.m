/*
 * NSEvent — the event value a seam produces and a responder consumes.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE CLASS IS STORAGE PLUS ONE ASSERTION, and the assertion is the interesting half: Apple's event
 * accessors answer what the event was BUILT with, and nothing here computes or normalises anything. The
 * evidence for that is the first probe check that would fail if it did — a mouse event's `-characters` is
 * nil, a key event's `-deltaX` is zero, and no accessor invents a value for the other kind.
 *
 * THE MRC OWNERSHIP IS FOUR POINTERS AND IT IS EXPLICIT: `_context`, the two character strings and
 * `_vendorDefined` are retained in the constructors and released in `-dealloc`. `-init` therefore has to
 * clear them all to NULL before anything else can happen, because a factory that builds an event field by
 * field and fails halfway must not leave a garbage pointer for `-dealloc` to release.
 *
 * AND THE CLASS STATE IS THE DEVIATION THE HEADER DECLARES: `+mouseLocation`, `+modifierFlags` and
 * `+pressedMouseButtons` answer from the last event this class was ASKED TO CREATE, because there is no
 * window server behind them: the seam is `AGWindowServer`, and it PUSHES input through this class rather
 * than answering a query. The mouse location
 * is only ever taken from an event whose `windowNumber` is 0 — a window-relative location is not a screen
 * location, and `+mouseLocation` is defined in screen coordinates — and the button mask is maintained by
 * watching the down/up/dragged types, with an "other" button's number read out of `data1`, which is where
 * `+otherEventWithType:…` puts it.
 *
 * THE OTHER TWO PIECES OF CLASS STATE ARE REAL RATHER THAN DECLARED, WHICH IS WHY THEY LIVE HERE AND NOT IN
 * THE APPLICATION: a monitor registry and a periodic source. WHAT MAKES THEM REAL IS THAT SOMETHING READS
 * THEM — `-[NSApplication sendEvent:]` runs the local monitors before it dispatches, and
 * `-[NSApplication nextEventMatchingMask:…]` asks for a due periodic event at the top of every pass. The two
 * hooks are `cg_`-prefixed and declared in the class extension below, with the application declaring the
 * same pair in a category of its own; that is the shape `+[NSWindow cg_waitForEventInMilliseconds:]` already
 * uses for the wait the application does not own.
 *
 * AND THE REFUSALS NAME THEIR SUBSYSTEM, because four of these doors cross into software this tree has not
 * got: the Carbon Event Manager (`-eventRef`), Quartz Event Services (`-CGEvent`), the window server's input
 * controls (the three intervals) and a touch source (`-touchesMatchingPhase:inView:`, whose class is
 * PARKED). Each answers its type's DOCUMENTED empty value and prints why, so a caller can tell "this tier
 * cannot do that" from "this tier did it and the answer was empty".
 */
#import <AppKit/NSEvent.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>

#include "AppKitRefusal.h"	/* fn_refuse_window — the one refusal message, in one place (the .m files
				 * import it, never the headers: NSView.m, NSWindow.m and NSApplication.m all do). */
#include <Block.h>	/* Block_copy/Block_release: the runtime entry points, which the house rule requires for a
			 * stored block — the same treatment FNAuthenticationChallengeSender gives a continuation. */
#include <stdlib.h>

/* THE DEVICE STATE AS FAR AS THIS CLASS HAS BEEN TOLD. Static because the three class services are class
 * methods and Apple's are too; there is one device set, so there is one copy. */
static NSPoint s_mouseLocation;
static NSUInteger s_modifierFlags;
static NSUInteger s_pressedMouseButtons;

/* THE COALESCING FLAG IS INITIALISED RATHER THAN ZEROED, because Apple's default is YES and a `static` with
 * no initialiser would answer NO — the one place in this file where the zero value is the wrong one. */
static BOOL s_mouseCoalescing = YES;

/* AND THE PERIODIC SOURCE: whether it is on, how long between events, and when the next one is due on the
 * reference-date clock `+[NSDate timeIntervalSinceReferenceDate]` reads. */
static BOOL s_periodicOn;
static NSTimeInterval s_periodicPeriod;
static NSTimeInterval s_periodicDue;

/* THE MONITOR REGISTRY, created on first use. One array of `FNEventMonitor`, in registration order, which is
 * the order Apple documents the blocks as running in. */
static NSMutableArray *s_monitors;

/* THE TWO PRIVATE DOORS, DECLARED IN A CLASS EXTENSION RATHER THAN INVENTED IN THE HEADER: they are this
 * file's own business, a caller cannot reach them, and putting them in the public header would declare two
 * members that Apple does not have. */
@interface NSEvent ()
- (instancetype)cg_initWithType:(NSEventType)type
		      location:(NSPoint)location
		 modifierFlags:(NSUInteger)flags
		     timestamp:(NSTimeInterval)time
		  windowNumber:(NSInteger)windowNum
		       context:(NSGraphicsContext *)context;
- (void)cg_noteOtherButton:(NSInteger)button down:(BOOL)down;
/* AND THE TWO THE APPLICATION'S PUMP CALLS. */
+ (nullable NSEvent *)cg_monitorLocalEvent:(NSEvent *)event;
+ (nullable NSEvent *)cg_periodicEventIfDueMatchingMask:(NSUInteger)mask;
@end

/* A REGISTERED MONITOR. The block is COPIED — `Block_copy` in the factory, `Block_release` in `-dealloc` —
 * because a caller that builds its handler in a loop or on a stack frame owns nothing after it returns. */
@interface FNEventMonitor : NSObject
{
@public
	NSEventMask mask;
	BOOL isGlobal;
	void *handler;
}
@end

@implementation FNEventMonitor
- (void)dealloc
{
	Block_release(handler);
	[super dealloc];
}
@end

@implementation NSEvent

@synthesize type = _type;
@synthesize modifierFlags = _modifierFlags;
@synthesize timestamp = _timestamp;
@synthesize windowNumber = _windowNumber;

/* **THE WINDOW IS THE APPLICATION'S REGISTRY'S ANSWER, NOT A POINTER THIS OBJECT KEEPS.** A retained window would keep a
 * closed window alive for as long as any event that touched it was in flight; the number is the era's own indirection and
 * the registry is the one place that knows which window still exists. An event with no window answers nil, which is what
 * the registry says for a number no live window carries. */
- (NSWindow *)window
{
	return [[NSApplication sharedApplication] windowWithWindowNumber:_windowNumber];
}
@synthesize context = _context;
@synthesize locationInWindow = _locationInWindow;
@synthesize clickCount = _clickCount;
@synthesize buttonNumber = _buttonNumber;
@synthesize eventNumber = _eventNumber;
@synthesize trackingNumber = _trackingNumber;
@synthesize pressure = _pressure;
@synthesize deltaX = _deltaX;
@synthesize deltaY = _deltaY;
@synthesize deltaZ = _deltaZ;
@synthesize characters = _characters;
@synthesize charactersIgnoringModifiers = _charactersIgnoringModifiers;
@synthesize keyCode = _keyCode;
@synthesize subtype = _subtype;
@synthesize data1 = _data1;
@synthesize data2 = _data2;
@synthesize userData = _userData;
@synthesize magnification = _magnification;
@synthesize deviceID = _deviceID;
@synthesize rotation = _rotation;
@synthesize absoluteX = _absoluteX;
@synthesize absoluteY = _absoluteY;
@synthesize absoluteZ = _absoluteZ;
@synthesize buttonMask = _buttonMask;
@synthesize tilt = _tilt;
@synthesize tangentialPressure = _tangentialPressure;
@synthesize vendorDefined = _vendorDefined;
@synthesize vendorID = _vendorID;
@synthesize tabletID = _tabletID;
@synthesize pointingDeviceID = _pointingDeviceID;
@synthesize systemTabletID = _systemTabletID;
@synthesize vendorPointingDeviceType = _vendorPointingDeviceType;
@synthesize pointingDeviceSerialNumber = _pointingDeviceSerialNumber;
@synthesize uniqueID = _uniqueID;
@synthesize capabilityMask = _capabilityMask;
@synthesize pointingDeviceType = _pointingDeviceType;

/* THE COMMON PREAMBLE, AND THE THREE SIDE EFFECTS THAT MAKE THE CLASS SERVICES MEAN ANYTHING. Every
 * constructor goes through here so that they cannot disagree about what creating an event does to the
 * device state — and so that the answer to "what did the caller last tell us" has exactly one definition. */
- (instancetype)cg_initWithType:(NSEventType)type
		      location:(NSPoint)location
		 modifierFlags:(NSUInteger)flags
		     timestamp:(NSTimeInterval)time
		  windowNumber:(NSInteger)windowNum
		       context:(NSGraphicsContext *)context
{
	if ((self = [super init]) != nil) {
		_type = type;
		_modifierFlags = flags;
		_timestamp = time;
		_windowNumber = windowNum;
		_context = [context retain];
		_locationInWindow = location;
		_characters = nil;
		_charactersIgnoringModifiers = nil;
		_vendorDefined = nil;
		_userData = NULL;

		s_modifierFlags = flags;
		/* A SCREEN LOCATION ONLY WHEN THE EVENT SAYS IT IS ONE: `windowNumber` 0 means the location is
		 * already in screen coordinates, which is the space `+mouseLocation` answers in. */
		if (windowNum == 0) {
			s_mouseLocation = location;
		}
		/* AND THE BUTTON MASK, FROM THE TYPE. An "other" button carries its number in `data1`, which is
		 * where this class's own `+otherEventWithType:…` puts it and where Apple's does too. */
		switch (type) {
		case NSLeftMouseDown:
		case NSLeftMouseDragged:
			s_pressedMouseButtons |= 1U;
			break;
		case NSLeftMouseUp:
			s_pressedMouseButtons &= ~1U;
			break;
		case NSRightMouseDown:
		case NSRightMouseDragged:
			s_pressedMouseButtons |= 2U;
			break;
		case NSRightMouseUp:
			s_pressedMouseButtons &= ~2U;
			break;
		default:
			break;
		}
	}
	return self;
}

/* THE ONE PLACE AN "OTHER" BUTTON TOUCHES THE MASK, kept apart from the preamble because the number is
 * not known until the caller has set `data1`. */
- (void)cg_noteOtherButton:(NSInteger)button down:(BOOL)down
{
	NSUInteger bit;

	if (button <= 1) {
		return;		/* 0 and 1 are the left and right buttons, handled by the type */
	}
	bit = (NSUInteger)1 << (NSUInteger)button;
	if (down) {
		s_pressedMouseButtons |= bit;
	} else {
		s_pressedMouseButtons &= ~bit;
	}
}

- (instancetype)init
{
	return [self cg_initWithType:NSAppKitDefined
			    location:NSMakePoint(0.0, 0.0)
		       modifierFlags:0
			   timestamp:0.0
			windowNumber:0
			     context:nil];
}

/* THE ERA'S SPELLING, so they are methods rather than synthesized property getters — the same reason
 * `-isEnteringProximity` is one, since the ledger's property row names the flag without its `is`. */
- (BOOL)isARepeat
{
	return _isARepeat;
}

- (BOOL)isEnteringProximity
{
	return _enteringProximity;
}

- (void)dealloc
{
	[_context release];
	[_characters release];
	[_charactersIgnoringModifiers release];
	[_vendorDefined release];
	[super dealloc];
}

+ (nullable NSEvent *)mouseEventWithType:(NSEventType)type
				location:(NSPoint)location
			   modifierFlags:(NSUInteger)flags
			       timestamp:(NSTimeInterval)time
			    windowNumber:(NSInteger)windowNum
				 context:(NSGraphicsContext *)context
			     eventNumber:(NSInteger)eventNum
			      clickCount:(NSInteger)clickNum
				pressure:(float)pressureValue
{
	NSEvent *e = [[self alloc] cg_initWithType:type
					  location:location
				     modifierFlags:flags
					 timestamp:time
				      windowNumber:windowNum
					   context:context];

	if (e == nil) {
		return nil;
	}
	/* THE PRIVATE IVARS ARE REACHED THROUGH THE PUBLIC ACCESSORS' OWN STORAGE — this is the class's own
	 * implementation, so `->_` is available without a door being invented for it. */
	e->_eventNumber = eventNum;
	e->_clickCount = clickNum;
	e->_pressure = pressureValue;
	e->_buttonNumber = 0;
	return [e autorelease];
}

+ (nullable NSEvent *)keyEventWithType:(NSEventType)type
			      location:(NSPoint)location
			 modifierFlags:(NSUInteger)flags
			     timestamp:(NSTimeInterval)time
			  windowNumber:(NSInteger)windowNum
			       context:(NSGraphicsContext *)context
			    characters:(NSString *)keys
	   charactersIgnoringModifiers:(NSString *)ukeys
			     isARepeat:(BOOL)repeat
			       keyCode:(unsigned short)code
{
	NSEvent *e = [[self alloc] cg_initWithType:type
					  location:location
				     modifierFlags:flags
					 timestamp:time
				      windowNumber:windowNum
					   context:context];

	if (e == nil) {
		return nil;
	}
	/* COPIED, NOT RETAINED: Apple's events hold their characters as a value, and a caller that passes a
	 * mutable string and then edits it must not be able to change an event that already happened. */
	e->_characters = [keys copy];
	e->_charactersIgnoringModifiers = [ukeys copy];
	e->_isARepeat = repeat;
	e->_keyCode = code;
	return [e autorelease];
}

+ (nullable NSEvent *)enterExitEventWithType:(NSEventType)type
				    location:(NSPoint)location
			       modifierFlags:(NSUInteger)flags
				   timestamp:(NSTimeInterval)time
				windowNumber:(NSInteger)windowNum
				     context:(NSGraphicsContext *)context
				 eventNumber:(NSInteger)eventNum
			      trackingNumber:(NSInteger)trackingNum
				    userData:(void *)data
{
	NSEvent *e = [[self alloc] cg_initWithType:type
					  location:location
				     modifierFlags:flags
					 timestamp:time
				      windowNumber:windowNum
					   context:context];

	if (e == nil) {
		return nil;
	}
	e->_eventNumber = eventNum;
	e->_trackingNumber = trackingNum;
	e->_userData = data;
	return [e autorelease];
}

+ (nullable NSEvent *)otherEventWithType:(NSEventType)type
				location:(NSPoint)location
			   modifierFlags:(NSUInteger)flags
			       timestamp:(NSTimeInterval)time
			    windowNumber:(NSInteger)windowNum
				 context:(NSGraphicsContext *)context
				 subtype:(short)subtype
				   data1:(NSInteger)d1
				   data2:(NSInteger)d2
{
	NSEvent *e = [[self alloc] cg_initWithType:type
					  location:location
				     modifierFlags:flags
					 timestamp:time
				      windowNumber:windowNum
					   context:context];

	if (e == nil) {
		return nil;
	}
	e->_subtype = subtype;
	e->_data1 = d1;
	e->_data2 = d2;
	/* THE ONLY BUTTON THIS CONSTRUCTOR CAN DESCRIBE, and it does describe it: an other-mouse type with a
	 * button number in `data1` updates the mask, which is what makes `+pressedMouseButtons` usable for the
	 * middle button and beyond when this is the door a seam has. */
	if (type == NSOtherMouseDown || type == NSOtherMouseDragged) {
		[e cg_noteOtherButton:d1 down:YES];
	} else if (type == NSOtherMouseUp) {
		[e cg_noteOtherButton:d1 down:NO];
	}
	return [e autorelease];
}

+ (NSPoint)mouseLocation
{
	return s_mouseLocation;
}

+ (NSUInteger)modifierFlags
{
	return s_modifierFlags;
}

+ (NSUInteger)pressedMouseButtons
{
	return s_pressedMouseButtons;
}

/* ---- THE INPUT INTERVALS, EACH REFUSED BY NAME ---------------------------------------------------- *
 * THE VALUE BELONGS TO THE COMPOSITOR AND THE SEAM DOES NOT SURFACE IT: `AGKeyboard` reads the keymap the
 * compositor sends, and the repeat delays and the double-click interval are settings the compositor keeps —
 * this tree has no door to them. A copied constant here would be a second copy that drifts the first time
 * either side changes, which is a wrong value rather than an unfinished one. */
+ (NSTimeInterval)doubleClickInterval
{
	fn_refuse_window("+doubleClickInterval", "the window server's input controls (the seam exposes no setting)");
	return 0.0;
}

+ (NSTimeInterval)keyRepeatDelay
{
	fn_refuse_window("+keyRepeatDelay", "the window server's input controls (the seam exposes no setting)");
	return 0.0;
}

+ (NSTimeInterval)keyRepeatInterval
{
	fn_refuse_window("+keyRepeatInterval", "the window server's input controls (the seam exposes no setting)");
	return 0.0;
}

/* ---- THE COALESCING FLAG, WHICH IS THIS CLASS'S OWN STATE ------------------------------------------ *
 * The flag is stored and answered; what it cannot yet do is change anything, because the coalescing itself
 * happens in the compositor, and the seam does not surface it. The header says which half this is. */
+ (void)setMouseCoalescingEnabled:(BOOL)flag
{
	s_mouseCoalescing = flag;
}

+ (BOOL)isMouseCoalescingEnabled
{
	return s_mouseCoalescing;
}

/* ---- THE PERIODIC SOURCE -------------------------------------------------------------------------- *
 * Arm a deadline and let the pump ask for it. A PERIOD OF ZERO OR LESS IS REFUSED RATHER THAN STORED: a
 * source with no period would make `-nextEventMatchingMask:…` hand an event back on every pass, which is a
 * run loop that never waits, and that is a worse answer than no source at all. */
+ (void)startPeriodicEventsAfterDelay:(NSTimeInterval)delay withPeriod:(NSTimeInterval)period
{
	if (period <= 0.0) {
		fn_refuse_window("+startPeriodicEventsAfterDelay:withPeriod:",
				 "a positive period (zero would make the run loop never wait)");
		return;
	}
	if (delay < 0.0) {
		delay = 0.0;
	}
	s_periodicPeriod = period;
	s_periodicDue = [NSDate timeIntervalSinceReferenceDate] + delay;
	s_periodicOn = YES;
}

+ (void)stopPeriodicEvents
{
	s_periodicOn = NO;
}

/* AND THE DOOR THE PUMP ASKS. It answers nil unless the source is armed, the mask selects `NSPeriodic` and
 * the deadline has passed — and it RE-ARMS BY ADDING PERIODS rather than by adding one period to `now`, so
 * a pump that ran late does not make every later event late by the same amount. */
+ (nullable NSEvent *)cg_periodicEventIfDueMatchingMask:(NSUInteger)mask
{
	NSTimeInterval now;
	NSEvent *e;

	if (!s_periodicOn || (mask & ((NSUInteger)1 << NSPeriodic)) == 0) {
		return nil;
	}
	now = [NSDate timeIntervalSinceReferenceDate];
	if (now < s_periodicDue) {
		return nil;
	}
	do {
		s_periodicDue += s_periodicPeriod;
	} while (s_periodicDue <= now);
	/* A PERIODIC EVENT CARRIES A TIMESTAMP AND NOTHING ELSE, which is what Apple's does: it is the tick
	 * a tracking loop wakes on, and every other field of it is empty. */
	e = [self otherEventWithType:NSPeriodic
			    location:NSMakePoint(0.0, 0.0)
		       modifierFlags:0
			   timestamp:now
			windowNumber:0
			     context:nil
			     subtype:0
			       data1:0
			       data2:0];
	return e;
}

/* ---- THE EVENT MONITORS --------------------------------------------------------------------------- *
 * A LOCAL monitor is real: the pump runs it before dispatching, and it may replace the event or drop it.
 * A GLOBAL monitor observes other applications, and this tier has neither another application nor an event
 * tap — so it is registered (the object contract a caller relies on is kept) and refused by name. */
+ (nullable id)addLocalMonitorForEventsMatchingMask:(NSEventMask)mask
					    handler:(nullable NSEvent * (^)(NSEvent *event))block
{
	FNEventMonitor *m;

	if (block == nil) {
		return nil;
	}
	if (s_monitors == nil) {
		s_monitors = [[NSMutableArray alloc] init];
	}
	m = [[FNEventMonitor alloc] init];
	m->mask = mask;
	m->isGlobal = NO;
	m->handler = Block_copy(block);
	[s_monitors addObject:m];
	/* NOT AUTORELEASED: Apple's door hands back a RETAINED object, and it is the token the caller passes
	 * back to `+removeMonitor:`. The registry holds its own reference. */
	return m;
}

+ (nullable id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask
					     handler:(nullable void (^)(NSEvent *event))block
{
	FNEventMonitor *m;

	if (block == nil) {
		return nil;
	}
	fn_refuse_window("+addGlobalMonitorForEventsMatchingMask:handler:",
			 "an event tap (this tier has no other applications to observe)");
	if (s_monitors == nil) {
		s_monitors = [[NSMutableArray alloc] init];
	}
	m = [[FNEventMonitor alloc] init];
	m->mask = mask;
	m->isGlobal = YES;
	m->handler = Block_copy(block);
	[s_monitors addObject:m];
	return m;
}

+ (void)removeMonitor:(nullable id)eventMonitor
{
	if (eventMonitor == nil || s_monitors == nil) {
		return;
	}
	/* BY IDENTITY: two monitors registered with the same mask are two objects, and the token decides. */
	[s_monitors removeObjectIdenticalTo:eventMonitor];
}

/* AND THE HOOK `-[NSApplication sendEvent:]` RUNS: every local monitor whose mask selects this event, in
 * registration order, each handed the event the one before it returned. A nil stops the dispatch, which is
 * Apple's own contract for the door. */
+ (nullable NSEvent *)cg_monitorLocalEvent:(NSEvent *)event
{
	NSUInteger i, n;

	if (event == nil || s_monitors == nil) {
		return event;
	}
	n = [s_monitors count];
	for (i = 0; i < n && i < [s_monitors count]; i++) {
		FNEventMonitor *m = [s_monitors objectAtIndex:i];
		NSEvent * (^block)(NSEvent *);

		if (m->isGlobal) {
			continue;
		}
		if (m->mask != NSAnyEventMask && !(m->mask & ((NSEventMask)1 << (NSUInteger)[event type]))) {
			continue;
		}
		block = (NSEvent * (^)(NSEvent *))m->handler;
		event = block(event);
		if (event == nil) {
			return nil;	/* the dispatch stops where a monitor stopped it */
		}
	}
	return event;
}

/* ---- THE 10.5 DOORS INTO ANOTHER SYSTEM, AND THE TOUCH DOOR --------------------------------------- *
 * The answers below are the ones Apple's own documentation gives for the case where no such object
 * corresponds — NULL and nil — so a caller that checks its result reads the truth either way. */
- (nullable const void *)eventRef
{
	fn_refuse_window("-eventRef", "the Carbon Event Manager");
	return NULL;
}

+ (nullable NSEvent *)eventWithEventRef:(nullable const void *)eventRef
{
	(void)eventRef;
	fn_refuse_window("+eventWithEventRef:", "the Carbon Event Manager");
	return nil;
}

- (nullable void *)CGEvent
{
	fn_refuse_window("-CGEvent", "Quartz Event Services");
	return NULL;
}

+ (nullable NSEvent *)eventWithCGEvent:(nullable void *)cgEvent
{
	(void)cgEvent;
	fn_refuse_window("+eventWithCGEvent:", "Quartz Event Services");
	return nil;
}

- (nullable NSSet *)touchesMatchingPhase:(NSUInteger)phase inView:(nullable id)view
{
	(void)phase;
	(void)view;
	fn_refuse_window("-touchesMatchingPhase:inView:",
			 "a touch input source (NSTouch is PARKED: the seam's seat reports none)");
	return nil;
}

/* **AND THE TRACKING AREA, WHICH IS NOW AN ANSWER WITH CONTENT.** The tier's own engine (`NSWindow
 * -cg_updateTrackingForPoint:`) sets it on the enter/exit events it builds, so an owner can read WHICH of its areas
 * fired — and, through `[[event trackingArea] userInfo]`, tell two areas in one view apart. An event built for a
 * tracking RECT carries none and answers nil, which is what Apple's header documents for it. */
- (NSTrackingArea *)trackingArea
{
	return _trackingArea;
}

@end

@implementation NSEvent (APPKITTrackingEngine)

/* **THE ENGINE'S DOOR, AND IT IS THE ONLY WRITER.** Not public because it is not a caller's business: an event's area
 * is decided by whoever built the event for a tracking area, and a caller who could set it could make an event claim
 * an area that never fired. */
- (void)cg_setTrackingArea:(NSTrackingArea *)area
{
	_trackingArea = area;	/* NOT RETAINED — see the ivar's note */
}

/* **THE POINTER'S ABSOLUTE POSITION, WHICH IS WHAT A TITLE-BAR DRAG MEASURES AGAINST.** Written by the
 * translation that builds the event from the seam's, and read by the drag — never by a caller, because an event
 * whose absolute point a caller could set would be an event that lies about where the pointer was. */
- (void)cg_setGlobalPoint:(NSPoint)point
{
	_cg_globalPoint = point;
	_cg_hasGlobalPoint = YES;
}

- (NSPoint)cg_globalPoint
{
	return _cg_globalPoint;
}

- (BOOL)cg_hasGlobalPoint
{
	return _cg_hasGlobalPoint;
}

@end
