/*
 * NSControl — a view that delegates its face and its value to a cell.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLASS IS MOSTLY FORWARDING, AND THAT IS THE DESIGN RATHER THAN A SHORTCUT.** Every value door asks the cell
 * because the cell is where the coercion and the formatter live; every face door asks the cell, or redraws and lets
 * the cell draw; and the two doors this class actually implements are the two a VIEW owns: `-drawRect:`, which hands
 * the cell its bounds, and `-mouseDown:`, which is the tracking — highlight, drag, and act on the button coming up
 * inside.
 *
 * AND THE TRACKING LOOP IS SHAPED LIKE THE MENU'S, FOR THE SAME REASON: a control that blocks waiting for its release
 * is a control that has stopped the rest of the interface, so the loop pumps the application's own event stream one
 * pass at a time and repaints between passes. `-performClick:` IS THE SAME ACTION WITHOUT THE POINTER, which is what
 * a key equivalent needs.
 */
#import <AppKit/NSControl.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSTrackingArea.h>

@implementation NSControl

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_cell = nil;
	}
	return self;
}

- (void)dealloc
{
	/* THE AREA GOES FIRST, WHILE THE CELL IS STILL ALIVE: removing it can fire a `-mouseExited:` at this control (a
	 * caller who frees a control the pointer is resting on), and that door writes to the cell. */
	if (_cg_hoverArea != nil) {
		[self removeTrackingArea:_cg_hoverArea];
		[_cg_hoverArea release];
	}
	[_cell release];
	[super dealloc];
}

/* ---- THE CELL, AND THE ONE THING SETTING IT DOES BESIDES STORING IT ---------------------------- */

- (NSCell *)cell
{
	return _cell;
}

- (void)setCell:(NSCell *)aCell
{
	if (aCell != _cell) {
		NSCell *held = [aCell retain];

		[_cell release];
		_cell = held;
		/* **AND THE CELL IS TOLD WHERE IT IS DRAWN, WHICH IS NOT BOOKKEEPING.** A cell that changes its own state —
		 * `-highlight:withFrame:inView:` — asks this back-reference for the view to redraw, so a cell whose
		 * `-controlView` is nil sets its state and NOTHING REPAINTS. This one line is what makes the highlight
		 * appear. */
		[_cell setControlView:self];
		[self setNeedsDisplay:YES];
	}
}

/* ---- THE TARGET/ACTION PAIR, WHICH IS THE CELL'S ------------------------------------------------ */

- (id)target
{
	return _cell != nil ? [_cell target] : nil;
}

- (void)setTarget:(id)anObject
{
	[_cell setTarget:anObject];
}

- (SEL)action
{
	return _cell != nil ? [_cell action] : NULL;
}

- (void)setAction:(SEL)aSelector
{
	[_cell setAction:aSelector];
}

/* ---- ENABLE, HIGHLIGHT, AND THE REDISPLAY EACH OWES -------------------------------------------- */

- (BOOL)isEnabled
{
	return _cell != nil ? [_cell isEnabled] : NO;
}

- (void)setEnabled:(BOOL)flag
{
	[_cell setEnabled:flag];
	[self setNeedsDisplay:YES];
}

- (BOOL)isHighlighted
{
	return _cell != nil ? [_cell isHighlighted] : NO;
}

- (void)setHighlighted:(BOOL)flag
{
	[_cell setHighlighted:flag];
	[self setNeedsDisplay:YES];
}

/* ---- THE VALUE, FORWARDED, EACH SETTER REDRAWING ------------------------------------------------ */

- (id)objectValue
{
	return [_cell objectValue];
}

- (void)setObjectValue:(id)obj
{
	[_cell setObjectValue:obj];
	[self setNeedsDisplay:YES];
}

- (NSString *)stringValue
{
	return [_cell stringValue];
}

- (void)setStringValue:(NSString *)aString
{
	[_cell setStringValue:aString];
	[self setNeedsDisplay:YES];
}

- (int)intValue
{
	return [_cell intValue];
}

- (void)setIntValue:(int)anInt
{
	[_cell setIntValue:anInt];
	[self setNeedsDisplay:YES];
}

- (NSInteger)integerValue
{
	return [_cell integerValue];
}

- (void)setIntegerValue:(NSInteger)anInteger
{
	[_cell setIntegerValue:anInteger];
	[self setNeedsDisplay:YES];
}

- (float)floatValue
{
	return [_cell floatValue];
}

- (void)setFloatValue:(float)aFloat
{
	[_cell setFloatValue:aFloat];
	[self setNeedsDisplay:YES];
}

- (double)doubleValue
{
	return [_cell doubleValue];
}

- (void)setDoubleValue:(double)aDouble
{
	[_cell setDoubleValue:aDouble];
	[self setNeedsDisplay:YES];
}

/* ---- AND THE FACE'S TWO PROPERTIES, AND THE CONTROL'S OWN TAG ----------------------------------- */

- (id)font
{
	return [_cell font];
}

- (void)setFont:(id)font
{
	[_cell setFont:font];
	[self setNeedsDisplay:YES];
}

- (NSTextAlignment)alignment
{
	return [_cell alignment];
}

- (void)setAlignment:(NSTextAlignment)mode
{
	[_cell setAlignment:mode];
	[self setNeedsDisplay:YES];
}

- (BOOL)isContinuous
{
	return _cell != nil ? [_cell isContinuous] : NO;
}

- (void)setContinuous:(BOOL)flag
{
	[_cell setContinuous:flag];
}

- (BOOL)ignoresMultiClick
{
	return _ignoresMultiClick;
}

- (void)setIgnoresMultiClick:(BOOL)flag
{
	_ignoresMultiClick = flag;
}

/* ---- AND THE TWO DOORS A VIEW OWNS: THE FACE AND THE CLICK -------------------------------------- */

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	/* **THE CELL IS GIVEN THE VIEW'S OWN BOUNDS, WHICH IS WHAT MAKES A CONTROL'S COORDINATES ITS CELL'S.** The cell
	 * is not told where the control is in its superview; it is told the rectangle it fills, which is the same rule
	 * every drawing class in this tree uses. */
	if (_cell != nil) {
		[_cell drawWithFrame:[self bounds] inView:self];
	}
}

- (BOOL)acceptsFirstResponder
{
	return _cell != nil && [_cell acceptsFirstResponder];
}

/* ---- AND THE POINTER ENTERING AND LEAVING, WHICH IS WHERE A PRELIGHT COMES FROM -------------------- */

/* **THE CONTROL OWNS A TRACKING AREA, WHICH IS WHAT REPLACES THE WINDOW'S OLD BLANKET SYNTHESIS.** Before the class
 * existed the window decided "the pointer crossed into the deepest view under it" for EVERY view of whatever window the
 * pointer was over — INCLUDING A WINDOW OF AN APPLICATION THAT WAS NOT ACTIVE. An area's scope word is what makes the
 * interest explicit, and it belongs here, on the control.
 *
 * THE SCOPE IS `NSTrackingActiveInActiveApp` RATHER THAN `…InKeyWindow`, AND THAT IS A DECISION WITH A MEASURED
 * GROUND. This tier's activation is per-APPLICATION — the window server says "this client has the keyboard" and
 * `NSApplication -isActive` follows — while its windows are borderless and `-canBecomeKeyWindow` answers NO for those
 * (Apple's own default, kept), so NO WINDOW IN AN APPLICATION BUILT ON THIS TIER IS EVER KEY. Key-scoping a control
 * here would leave every button in every window permanently dark, which is exactly what happened the first time this
 * area was written; app-scoping is the honest reading of "this application is the one in front", and it still excludes
 * the case the old synthesis got wrong — a window whose application is NOT active no longer prelights.
 *
 * AND `NSTrackingInVisibleRect` MAKES THE REGION THE CONTROL'S VISIBLE RECTANGLE, so a control that is resized,
 * clipped or scrolled away needs no `-updateTrackingAreas` pass at all: the engine recomputes the rectangle from
 * `-visibleRect` on every motion.
 *
 * THE OWNER IS THE CONTROL, so the callbacks arrive at the two doors below and reach the cell — which is where the
 * face is, and therefore where the answer belongs. */
- (void)cg_installHoverArea
{
	if (_cg_hoverArea == nil) {
		_cg_hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
							   options:(NSTrackingMouseEnteredAndExited |
								    NSTrackingActiveInActiveApp |
								    NSTrackingInVisibleRect)
							     owner:self userInfo:nil];
	}
	if ([self window] != nil) {
		[self addTrackingArea:_cg_hoverArea];
	}
}

/* **AND THE AREA COMES AND GOES WITH THE WINDOW, WHICH IS WHY THIS HOOK IS OVERRIDDEN.** The engine finds areas by
 * walking the tree from the window's content view, so an area on a view with no window is unreachable — installing one
 * at construction would be claiming an interest nothing can deliver on. Leaving a window also CLEARS the cell's bit:
 * the exits that would have cleared it belong to an engine that is no longer walking this view. */
- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	if ([self window] != nil) {
		[self cg_installHoverArea];
	} else if (_cg_hoverArea != nil) {
		[self removeTrackingArea:_cg_hoverArea];
		[_cell cg_setMouseInside:NO];
	}
}

/* **THE CELL IS TOLD, AND THE CHAIN IS NOT BROKEN.** The state is stored on the cell because the face is the cell's;
 * and the forward to `super` is what keeps `-mouseEntered:` the responder-chain door `NSResponder` documents rather
 * than a trap this class swallowed — a content view that wants to watch the pointer still sees it pass. */
- (void)mouseEntered:(NSEvent *)event
{
	[_cell cg_setMouseInside:YES];
	[super mouseEntered:event];
}

- (void)mouseExited:(NSEvent *)event
{
	[_cell cg_setMouseInside:NO];
	[super mouseExited:event];
}

/* **THE TRACKING, WHICH IS THE ONE PIECE OF BEHAVIOUR THIS CLASS OWNS.** A press highlights the cell; the loop reads
 * the application's own events one at a time — so the rest of the desktop keeps turning — and takes the highlight
 * off when the pointer leaves the control's bounds and puts it back when it returns; and the ACTION GOES OUT ONLY IF
 * THE BUTTON CAME UP INSIDE, which is what makes a drag off a button cancel it. A DISABLED control highlights
 * nothing and sends nothing, which is what `-isEnabled` is FOR.
 *
 * **AND THE CELL'S THREE TRACKING HOOKS RUN INSIDE THIS LOOP, WHICH IS WHAT MAKES A SLIDER POSSIBLE WITHOUT A SECOND
 * LOOP.** `-startTrackingAt:inView:` takes the press and `-continueTracking:at:inView:` takes every point after it —
 * release included, so a value that follows the pointer lands on the point the button came up at rather than the last
 * one it was DRAGGED to — and `-stopTracking:at:inView:mouseIsUp:` closes. THE CELL IS THEREFORE WHERE "WHAT VALUE IS
 * THIS POINT" LIVES, and this loop only pumps events and decides when a changed value is worth a message.
 *
 * AND THAT LAST DECISION IS THE ONLY READING WORTH NAMING: the loop tracks until the button comes up rather than
 * until `-continueTracking:at:inView:` answers no, because dragging off a button and back must cancel and un-cancel
 * it and this tier's `NSButtonCell` does not override that hook to say so. The hook's answer is what
 * `-trackMouse:inRect:ofView:untilMouseUp:` reads — a door this tier still owes (§A10bq) — so the two are not the
 * same question and this loop asks the cell for the VALUE only. */
- (void)mouseDown:(NSEvent *)event
{
	NSApplication *app = [NSApplication sharedApplication];
	NSWindow *window = [self window];
	NSRect bounds = [self bounds];
	NSPoint lastPoint;
	BOOL inside = NO;
	BOOL continuous = [self isContinuous];

	if (_cell == nil || ![_cell isEnabled]) {
		return;
	}
	lastPoint = [self convertPoint:[event locationInWindow] fromView:nil];
	[_cell highlight:YES withFrame:bounds inView:self];
	(void)[_cell startTrackingAt:lastPoint inView:self];
	[self setNeedsDisplay:YES];
	if (window != nil) {
		[window displayIfNeeded];
	}
	/* **A PROGRAM WITH NO RUN LOOP HAS NO EVENT SOURCE**, so the state above is the whole of what can be done and the
	 * caller drives the rest — the same guard, for the same measured reason, `NSMenuView`'s tracking loop carries. */
	if (![app isRunning]) {
		[_cell stopTracking:lastPoint at:lastPoint inView:self mouseIsUp:NO];
		[_cell highlight:NO withFrame:bounds inView:self];
		return;
	}
	/* THE PRESS ITSELF IS A VALUE, so a continuous cell speaks before the pointer has moved at all: a click on a
	 * track puts the knob there, and a caller watching a continuous slider sees that immediately. */
	if (continuous) {
		[self sendAction:[_cell action] to:[_cell target]];
	}
	for (;;) {
		NSEvent *next;
		NSPoint where;
		BOOL over;

		if (window != nil) {
			[window displayIfNeeded];
		}
		next = [app nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)
					untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
					   inMode:nil
					  dequeue:YES];
		if (next == nil) {
			continue;	/* nothing happened this turn: the control is still pressed */
		}
		if (![app isRunning]) {
			break;
		}
		where = [self convertPoint:[next locationInWindow] fromView:nil];
		(void)[_cell continueTracking:lastPoint at:where inView:self];
		lastPoint = where;
		over = NSPointInRect(where, bounds);
		if (over != [_cell isHighlighted]) {
			[_cell highlight:over withFrame:bounds inView:self];
			[self setNeedsDisplay:YES];
		}
		if (continuous) {
			[self sendAction:[_cell action] to:[_cell target]];
		}
		if ([next type] == NSLeftMouseUp) {
			inside = over;
			break;
		}
	}
	[_cell stopTracking:lastPoint at:lastPoint inView:self mouseIsUp:inside];
	[_cell highlight:NO withFrame:bounds inView:self];
	/* ONE MESSAGE FOR A NON-CONTINUOUS CONTROL, AT THE END — and none at all if the button came up outside, which is
	 * the cancel a drag off a button performs. A CONTINUOUS CELL HAS ALREADY SPOKEN for every point including this
	 * one, so a second send would be the same value twice. */
	if (inside && !continuous) {
		[self sendAction:[_cell action] to:[_cell target]];
	}
}

- (BOOL)sendAction:(SEL)theAction to:(id)theTarget
{
	/* **A NIL TARGET MEANS THE RESPONDER CHAIN, AND THE APPLICATION OWNS THAT WALK** — the same door `NSMenu` uses one
	 * class over, so there is one definition of "who receives an action whose target is nobody". A nil SELECTOR is
	 * refused rather than sent: there is nothing to send. */
	if (theAction == NULL) {
		return NO;
	}
	return [[NSApplication sharedApplication] sendAction:theAction to:theTarget from:self];
}

- (void)performClick:(id)sender
{
	(void)sender;
	[self sendAction:[_cell action] to:[_cell target]];
}

- (void)sizeToFit
{
	if (_cell == nil) {
		return;
	}
	[self setFrameSize:[_cell cellSize]];
}

@end
