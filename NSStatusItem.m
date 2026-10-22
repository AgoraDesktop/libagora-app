/*
 * NSStatusItem.m — one item in the status area, and the width is the whole of what its application says.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 */

#import "NSStatusItem.h"
#import "AGStatusBarItemView.h"
#import "NSStatusBar.h"
#import "NSWindow.h"
#import "NSView.h"
#import "NSApplication.h"
#import "NSMenu.h"
#import "NSColor.h"
#import "NSFont.h"
#import "NSImage.h"
#import "NSStringDrawing.h"
#import "NSBezierPath.h"
#import "NSGraphicsContext.h"

#import <Foundation/NSGeometry.h>

/* The seam door, declared here because this file is where it is CALLED — the same shape `NSWindow.m` uses for the
 * registry door. It is `NSWindow`'s business and not this file's which `AGWindow` an item ends up on. */
@interface NSWindow (AGORAStatusItemPrivate)
- (void)cg_setStatusItemLength:(CGFloat)length;
@end


/* ============================================================================================ *
 * THE ITEM'S OWN VIEW, WHICH IS WHAT MAKES THE ACTION PAIR AND THE THREE GATE DOORS REAL.        *
 * ============================================================================================ */
/* **A STATUS ITEM IS A WINDOW AND A VIEW IS WHAT TAKES A PRESS.** Apple's is a button (`NSStatusBarButton`); this tier's
 * is this class, and its whole job is the four things a person expects of a menu-bar item: draw what the item says, show
 * the pressed state when `-highlightMode:` is on, send the action (on the event the item asked for), and open the item's
 * menu when it has one. `-isEnabled`, `-sendActionOn:` and the tooltip are all obeyed HERE; without this class they would
 * be three stored values no press could reach, which is what the previous handoff recorded them as.
 *
 * THE BACKGROUND IS THE ITEM'S OWN. The compositor gives the strip a surface and places the item's window in it; what
 * fills that window is this view's `-drawRect:`, so a pressed item paints the selection colour and the strip's own grey
 * shows through otherwise (the window is borderless and draws no background of its own). */
@implementation AGStatusBarItemView

- (id)initWithStatusItem:(NSStatusItem *)item frame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self != nil) {
		_item = item;
	}
	return self;
}

- (void)cg_setStatusItem:(NSStatusItem *)item
{
	_item = item;
}

/* **THE PRESSED STATE IS THE VIEW'S, AND `-highlightMode:` IS WHETHER IT IS SHOWN.** An item with highlight mode off is
 * one that opens a menu or acts without saying so — Apple's own flag — and the press still tracks, it simply draws
 * nothing different. A DISABLED item draws its words in the era's grey, and the position stays readable. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSStatusItem *item = _item;
	NSRect bounds = [self bounds];
	BOOL highlighted = _pressed && [item highlightMode];
	BOOL enabled = [item isEnabled];
	NSImage *image;

	(void)dirtyRect;
	if (highlighted) {
		[[NSColor selectedControlColor] setFill];
		NSRectFill(bounds);
	}
	image = (highlighted && [item alternateImage] != nil) ? [item alternateImage] : [item image];
	if (image != nil) {
		NSSize size = [image size];
		NSRect box = NSMakeRect(floor(NSMidX(bounds) - size.width / 2.0),
					floor(NSMidY(bounds) - size.height / 2.0),
					size.width, size.height);

		if (!enabled) {
			CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];

			if (cg != NULL) {
				CGContextSetAlpha(cg, 0.5);
			}
			[image drawInRect:box];
			if (cg != NULL) {
				CGContextSetAlpha(cg, 1.0);
			}
			return;
		}
		[image drawInRect:box];
		return;
	}
	{
		NSAttributedString *attributed = [item attributedTitle];
		NSString *title = [item title];
		NSColor *ink;
		NSFont *font;
		NSDictionary *attributes;
		NSSize size;
		NSRect where;

		if (attributed != nil) {
			size = [attributed size];
			where = NSMakeRect(floor(NSMidX(bounds) - size.width / 2.0),
					   floor(NSMidY(bounds) - size.height / 2.0), size.width, size.height);
			[attributed drawInRect:where];
			return;
		}
		if (title == nil || [title length] == 0) {
			return;
		}
		ink = highlighted ? [NSColor whiteColor]
				  : (enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]);
		font = [NSFont systemFontOfSize:12.0];
		attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, ink,
			      NSForegroundColorAttributeName, nil];
		size = [title sizeWithAttributes:attributes];
		where = NSMakeRect(floor(NSMidX(bounds) - size.width / 2.0),
				   floor(NSMidY(bounds) - size.height / 2.0), size.width, size.height);
		[title drawInRect:where withAttributes:attributes];
	}
}

/* THE ACTION, SENT THE WAY A CONTROL SENDS ONE: with the ITEM as the sender, which is what a caller's target sees. A
 * disabled item sends nothing; a nil action sends nothing; and the mask decides whether the press or the release is the
 * moment. */
- (void)fn_sendAction:(SEL)action
{
	NSStatusItem *item = _item;

	if (action == NULL || ![item isEnabled]) {
		return;
	}
	[[NSApplication sharedApplication] sendAction:action to:[item target] from:item];
}

/* **THE PRESS RUNS THE LOOP THE CONTROL LAYER ALREADY RUNS**, for the same reason: the highlight follows the pointer and
 * the release is what decides. The action goes out on the DOWN when the item asked for the down, and on the UP when the
 * button came up inside — which is Apple's default (`NSLeftMouseUpMask`). A press with a menu opens the menu instead and
 * sends nothing: the menu's own rows are the answers then, which is what `-setMenu:` MEANS. */
- (void)mouseDown:(NSEvent *)event
{
	NSStatusItem *item = _item;
	NSApplication *app = [NSApplication sharedApplication];
	NSEventMask mask;
	NSRect bounds = [self bounds];
	BOOL inside = YES;

	if ([item menu] != nil) {
		[item popUpStatusItemMenu:[item menu]];
		return;
	}
	mask = [item cg_actionMask];
	_pressed = YES;
	[self setNeedsDisplay:YES];
	if (mask & NSLeftMouseDownMask) {
		[self fn_sendAction:[item action]];
	}
	/* A PROGRAM WITH NO RUN LOOP HAS NO EVENT SOURCE, the same guard the control layer's press carries: the state above
	 * is the whole of what can be done and the caller drives the rest. */
	if (![app isRunning]) {
		_pressed = NO;
		[self setNeedsDisplay:YES];
		return;
	}
	for (;;) {
		NSEvent *next = [app nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)
						 untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
						    inMode:nil
						   dequeue:YES];
		NSPoint where;
		BOOL over;

		if (next == nil) {
			[[self window] displayIfNeeded];
			continue;
		}
		where = [self convertPoint:[next locationInWindow] fromView:nil];
		over = NSPointInRect(where, bounds);
		if (over != _pressed) {
			/* **THE HIGHLIGHT FOLLOWS THE POINTER OUT OF THE ITEM**, which is the cancel a drag off a button performs. */
			_pressed = over;
			[self setNeedsDisplay:YES];
		}
		if ([next type] == NSLeftMouseUp) {
			inside = over;
			if ([next clickCount] >= 2 && [item doubleAction] != NULL) {
				[self fn_sendAction:[item doubleAction]];
			} else if (inside && (mask & NSLeftMouseUpMask)) {
				[self fn_sendAction:[item action]];
			}
			break;
		}
		[[self window] displayIfNeeded];
	}
	_pressed = NO;
	[self setNeedsDisplay:YES];
	[[self window] displayIfNeeded];
}

- (void)mouseUp:(NSEvent *)event
{
	/* THE LOOP ABOVE CONSUMES THE RELEASE; this is here so a caller driving events by hand (a probe, a test) has a
	 * matching door rather than a press that can only be ended by a run loop. */
	(void)event;
	_pressed = NO;
	[self setNeedsDisplay:YES];
}

@end

@implementation NSStatusItem

/* **THE TWO SENTINELS ARE RESOLVED HERE, AND THIS IS THE ONLY PLACE THEY ARE.** The server is never told a
 * sentinel, because only AppKit knows how wide a view wants to be: `NSVariableStatusItemLength` is the view's own
 * width and `NSSquareStatusItemLength` is the bar's thickness. An item with neither a length nor a view has
 * nothing to be wide, so it falls back to a square — visible and honest rather than silently absent. */
- (CGFloat)cg_resolvedLength
{
	CGFloat thickness = [[NSStatusBar systemStatusBar] thickness];

	if (_fLength == NSSquareStatusItemLength) {
		return thickness;
	}
	if (_fLength == NSVariableStatusItemLength) {
		if (_fView != nil) {
			NSRect bounds = [_fView frame];

			if (bounds.size.width > 0.0) {
				return bounds.size.width;
			}
		}
		return thickness;
	}
	return _fLength;
}

/* THE WINDOW, MADE WHEN THERE IS SOMETHING TO PUT IT ON. A status item IS a window — the server places one — and
 * an application draws into it through the item's view. Nothing is made when the bar has no thickness, because
 * that means there is no screen to put an item on and a zero-height window would be a lie about where it is. */
- (BOOL)cg_ensureStatusWindow
{
	CGFloat length, thickness;

	if (_fWindow != nil) {
		return YES;
	}
	thickness = [[NSStatusBar systemStatusBar] thickness];
	if (thickness <= 0.0) {
		return NO;
	}
	length = [self cg_resolvedLength];
	_fWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, length, thickness)
					      styleMask:NSBorderlessWindowMask
						backing:NSBackingStoreBuffered
						  defer:NO];
	if (_fWindow == nil) {
		return NO;
	}
	/* **THE LEVEL IS STILL THE APPLICATION'S.** The server decides WHERE in the strip the item goes and the
	 * application decides how it is ordered against everything else — which is why the two are separate doors and
	 * why the item asks for the status level rather than being given it. */
	[_fWindow setLevel:NSStatusWindowLevel];
	[_fWindow cg_setStatusItemLength:length];
	/* **AND THE ITEM DRAWS ITSELF WHEN THE APPLICATION HAS NOT GIVEN IT A VIEW.** A status item with a title and no view
	 * would be a window with nothing in it — which is what this class WAS before the sweep: `-setTitle:` stored a string
	 * and no press could ever reach `-action`. The internal view is the item's own face and its press. */
	if (_fView == nil) {
		_fInternalView = [[AGStatusBarItemView alloc] initWithStatusItem:self frame:NSMakeRect(0.0, 0.0, length, thickness)];
		[_fWindow setContentView:_fInternalView];
	}
	return YES;
}

- (id)cg_initWithStatusBar:(NSStatusBar *)bar length:(CGFloat)length
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_fStatusBar = bar;
	_fLength = length;
	_fHighlightMode = YES;
	/* **THE THREE DEFAULTS THE SWEEP ADDS, AND ALL THREE ARE APPLE'S.** An item is ENABLED (a menu extra that could not
	 * be pressed would be a decoration); its action goes out on the RELEASE, which is what a button does and what the
	 * header's `-sendActionOn:` note says; and it has no tooltip until one is given. */
	_fEnabled = YES;
	_fActionMask = NSLeftMouseUpMask;
	_fToolTip = nil;
	[self cg_ensureStatusWindow];
	return self;
}

- (void)dealloc
{
	[_fWindow release];
	[_fTitle release];
	[_fAttributedTitle release];
	[_fImage release];
	[_fAlternateImage release];
	[_fMenu release];
	[_fToolTip release];
	[_fInternalView release];
	[super dealloc];
}

- (NSStatusBar *)statusBar
{
	return _fStatusBar;
}

- (CGFloat)length
{
	return _fLength;
}

/* A LENGTH THE APPLICATION MAY CHANGE AT ANY TIME, sent again when it does: the server packs from the right edge
 * and a width that changed without telling it would leave the items after this one where they no longer belong. */
- (void)setLength:(CGFloat)length
{
	_fLength = length;
	if (_fWindow != nil) {
		[_fWindow cg_setStatusItemLength:(int)[self cg_resolvedLength]];
	}
}

- (SEL)action
{
	return _fAction;
}

- (void)setAction:(SEL)aSelector
{
	_fAction = aSelector;
}

- (SEL)doubleAction
{
	return _fDoubleAction;
}

- (void)setDoubleAction:(SEL)aSelector
{
	_fDoubleAction = aSelector;
}

- (id)target
{
	return _fTarget;
}

- (void)setTarget:(id)anObject
{
	_fTarget = anObject;
}

- (NSString *)title
{
	return _fTitle;
}

- (void)setTitle:(NSString *)aString
{
	NSString *copy = [aString copy];

	[_fTitle release];
	_fTitle = copy;
	[_fView setNeedsDisplay:YES];
}

- (NSAttributedString *)attributedTitle
{
	return _fAttributedTitle;
}

- (void)setAttributedTitle:(NSAttributedString *)aString
{
	NSAttributedString *copy = [aString copy];

	[_fAttributedTitle release];
	_fAttributedTitle = copy;
	[_fView setNeedsDisplay:YES];
}

- (NSImage *)image
{
	return _fImage;
}

- (void)setImage:(NSImage *)anImage
{
	[anImage retain];
	[_fImage release];
	_fImage = anImage;
	[_fView setNeedsDisplay:YES];
}

- (NSImage *)alternateImage
{
	return _fAlternateImage;
}

- (void)setAlternateImage:(NSImage *)anImage
{
	[anImage retain];
	[_fAlternateImage release];
	_fAlternateImage = anImage;
	[_fView setNeedsDisplay:YES];
}

- (BOOL)highlightMode
{
	return _fHighlightMode;
}

- (void)setHighlightMode:(BOOL)flag
{
	_fHighlightMode = flag;
	[_fView setNeedsDisplay:YES];
}

- (NSMenu *)menu
{
	return _fMenu;
}

- (void)setMenu:(NSMenu *)aMenu
{
	[aMenu retain];
	[_fMenu release];
	_fMenu = aMenu;
}

- (NSView *)view
{
	return _fView;
}

/* **THE VIEW IS THE APPLICATION'S, WHICH IS THE WHOLE POINT OF AN ITEM BEING A CLIENT.** The server owns the strip
 * and places the item; what is DRAWN in it belongs to whoever made it, and setting a view is how that happens. */
- (void)setView:(NSView *)aView
{
	if (![self cg_ensureStatusWindow]) {
		return;
	}
	if (aView != nil) {
		[aView retain];
	}
	[_fView release];
	_fView = aView;
	/* **A NIL VIEW MEANS "THE ITEM DRAWS ITSELF"**, which is Apple's reading of `-setView:nil` and the reason the
	 * internal view is kept rather than thrown away: the item keeps its face and its press instead of becoming a window
	 * with no content. */
	if (_fView == nil) {
		_fView = _fInternalView;
		if (_fWindow != nil) {
			[_fWindow setContentView:_fView];
		}
		return;
	}
	if (_fView != nil) {
		[_fWindow setContentView:_fView];
		/* **AND THE ITEM APPEARS, WHICH ON THE MAC IS APPKIT'S DOING RATHER THAN THE APPLICATION'S.** An item with
		 * a view is in the bar; nothing asks it to be. Ordering front is what joins the window to the run loop's
		 * registry, so the item draws on the same frame callbacks every other window does. */
		[_fWindow orderFront:nil];
	}
}

- (void)popUpStatusItemMenu:(NSMenu *)aMenu
{
	/* **AND THIS IS THE SESSION `NSMenu` GREW, SO IT IS NO LONGER OWED.** The item's window IS in the strip, and a menu
	 * opens from its own outer corner the way a menu bar's does — the location is in SCREEN coordinates, which is what a
	 * window's frame already is. The press that reached here is the view's; a caller may also open the menu by hand. */
	if (aMenu == nil || _fWindow == nil) {
		return;
	}
	[aMenu popUpMenuPositioningItem:nil
			     atLocation:NSMakePoint(NSMinX([_fWindow frame]), NSMinY([_fWindow frame]))
				 inView:nil];
}

/* ---- THE THREE GATE DOORS, AND THE MASK'S OWN ACCESSOR ---------------------------------------- */

- (BOOL)isEnabled
{
	return _fEnabled;
}

- (void)setEnabled:(BOOL)flag
{
	_fEnabled = flag ? YES : NO;
	[_fView setNeedsDisplay:YES];
}

/* **`-sendActionOn:` ANSWERS THE MASK IT REPLACED**, which is Apple's signature and the only reading under which the
 * answer is useful: a caller that wants the old behaviour back does not have to remember it. */
- (NSInteger)sendActionOn:(NSEventMask)mask
{
	NSEventMask previous = _fActionMask;

	_fActionMask = mask;
	return (NSInteger)previous;
}

- (NSEventMask)cg_actionMask
{
	return _fActionMask;
}

- (NSString *)toolTip
{
	return _fToolTip;
}

- (void)setToolTip:(NSString *)toolTip
{
	NSString *copy = [toolTip copy];

	[_fToolTip release];
	_fToolTip = copy;
	/* **AND THE VIEW IS WHAT SHOWS IT**, because a tooltip is a view's property in this tier (`NSView -setToolTip:`) and
	 * the item's view is the thing under the pointer. */
	[_fView setToolTip:_fToolTip];
}

- (void)drawStatusBarBackgroundInRect:(NSRect)rect withHighlight:(BOOL)highlight
{
	/* The item's view draws this; it is a call for a view that wants the bar's own background behind it. */
	(void)rect;
	(void)highlight;
}

@end
