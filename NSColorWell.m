/*
 * NSColorWell — a swatch that opens the colour panel.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE WELL IS THE PANEL'S CLIENT AND THE PANEL IS THE WELL'S FACE.** A click activates the well, which sets the panel's
 * target and action to itself; every change the panel then makes comes back through `-takeColorFrom:`, which stores the
 * colour and sends the well's own action. That indirection is Apple's and it is why a well holds no reference to the
 * panel: the panel's target is a weak back-pointer the well installs and removes.
 *
 * THE SWATCH IS DRAWN OPAQUE. A transparent colour's swatch is a checkerboard in Apple's own control; this tier keeps
 * the opaque fill and says so here, because the alternative is a second transparency rule beside the panel's ramp.
 */
#import <AppKit/NSColorWell.h>

#import <AppKit/NSColorPanel.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSEvent.h>

@implementation NSColorWell

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_color = [[NSColor whiteColor] retain];
		_bordered = YES;
		_draggedThisPress = NO;
	}
	return self;
}

- (void)dealloc
{
	/* A WELL THAT GOES AWAY WHILE IT IS THE PANEL'S TARGET TAKES ITSELF OUT FIRST, or the panel would send its action to
	 * freed storage — the same rule `NSControl`'s tracking area follows on the way out. */
	if (_active) {
		[self deactivate];
	}
	[_color release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE COLOUR AND THE FACE.                                                                      *
 * ============================================================================================ */

- (NSColor *)color
{
	return (_color != nil) ? _color : [NSColor whiteColor];
}

- (void)setColor:(NSColor *)color
{
	NSColor *old = _color;

	if (color == nil) {
		return;
	}
	_color = [color retain];
	[old release];
	/* **A WELL SETS ITS OWN COLOUR AND DOES NOT PUSH IT BACK TO THE PANEL, AND THAT IS WHAT BREAKS A CYCLE.** The
	 * panel's target IS an active well, so a well that called `-setColor:` on the panel from here would have the panel
	 * send `-takeColorFrom:` straight back — MEASURED as unbounded recursion the first time the probe set a colour on
	 * an active well. The panel is told where a well's colour starts, at `-activate:`; a caller changing the well
	 * afterwards is changing the well. */
	[self setNeedsDisplay:YES];
}

- (BOOL)isBordered
{
	return _bordered;
}

- (void)setBordered:(BOOL)flag
{
	_bordered = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (void)drawWellInside:(NSRect)insideRect
{
	NSColor *colour = [self color];

	[[colour colorWithAlphaComponent:1.0] setFill];
	[[NSBezierPath bezierPathWithRect:insideRect] fill];
	if (_bordered) {
		NSBezierPath *edge = [NSBezierPath bezierPathWithRect:insideRect];

		[[NSColor controlDarkShadowColor] setStroke];
		[edge setLineWidth:1.0];
		[edge stroke];
	}
}

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	[self drawWellInside:_bordered ? NSInsetRect([self bounds], 1.0, 1.0) : [self bounds]];
}

/* ============================================================================================ *
 * ACTIVATION.                                                                                   *
 * ============================================================================================ */

- (BOOL)isActive
{
	return _active;
}

- (void)activate:(id)sender
{
	NSColorPanel *panel = [NSColorPanel sharedColorPanel];

	_active = YES;
	[panel setTarget:self];
	[panel setAction:@selector(takeColorFrom:)];
	[panel setColor:[self color]];
	[panel orderFront:sender];
	[self setNeedsDisplay:YES];
}

- (void)deactivate
{
	NSColorPanel *panel;

	_active = NO;
	if (![NSColorPanel sharedColorPanelExists]) {
		return;
	}
	panel = [NSColorPanel sharedColorPanel];
	/* **ONLY IF THE PANEL IS STILL THIS WELL'S.** Another well may have activated since, and taking its target away
	 * would leave a person changing a colour that nobody hears about. */
	if ([panel target] == self) {
		[panel setTarget:nil];
		[panel setAction:NULL];
	}
	[self setNeedsDisplay:YES];
}

- (void)takeColorFrom:(id)sender
{
	if (sender == nil || ![sender respondsToSelector:@selector(color)]) {
		return;
	}
	[self setColor:(NSColor *)[sender color]];
	[self sendAction:[self action] to:[self target]];
}

/* ============================================================================================ *
 * THE POINTER.                                                                                  *
 * ============================================================================================ */

- (void)mouseDown:(NSEvent *)event
{
	_draggedThisPress = NO;
	[self activate:self];
	(void)event;
}

- (void)mouseDragged:(NSEvent *)event
{
	/* **A DRAG OUT OF THE WELL HAPPENS ONCE PER PRESS**, at the first motion: the panel's session then owns the pointer
	 * until the button comes up, so a second call would be a second drag for one gesture. */
	if (_draggedThisPress) {
		return;
	}
	_draggedThisPress = YES;
	(void)[[NSColorPanel sharedColorPanel] dragColor:[self color] withEvent:event fromView:self];
}

- (void)performClick:(id)sender
{
	[self activate:sender];
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

/* ============================================================================================ *
 * THE TARGET AND THE ACTION, WHICH ARE THE WELL'S OWN.                                          *
 * ============================================================================================ */

- (id)target
{
	return _target;
}

- (void)setTarget:(id)anObject
{
	_target = anObject;
}

- (SEL)action
{
	return _action;
}

- (void)setAction:(SEL)aSelector
{
	_action = aSelector;
}

/* ============================================================================================ *
 * ARCHIVING: THE COLOUR AND THE BORDER.                                                         *
 * ============================================================================================ */

static NSString * const AGCoderWellColorKey = @"NSColorWellColor";
static NSString * const AGCoderWellBorderedKey = @"NSColorWellBordered";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_color forKey:AGCoderWellColorKey];
	[aCoder encodeBool:_bordered forKey:AGCoderWellBorderedKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self != nil) {
		if ([aDecoder containsValueForKey:AGCoderWellColorKey]) {
			_color = [[aDecoder decodeObjectForKey:AGCoderWellColorKey] retain];
		} else {
			_color = [[NSColor whiteColor] retain];
		}
		_bordered = [aDecoder containsValueForKey:AGCoderWellBorderedKey]
			? [aDecoder decodeBoolForKey:AGCoderWellBorderedKey] : YES;
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

@end
