/*
 * NSPathControl — the path bar as a control.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The cell owns the path and the drawing. This file creates the cell, forwards the 10.6 doors, adds the double-click
 * gesture and the per-component hover, and stores the drag-source masks the era's header declares. The single click
 * goes through `NSControl`'s ordinary tracking loop, so the action sees `-clickedPathComponentCell`.
 */
#import <AppKit/NSPathControl.h>
#import <AppKit/NSPathCell.h>
#import <AppKit/NSPathComponentCell.h>

#import <AppKit/NSControl.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSView.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSURL.h>

/* THE CELL'S PRIVATE DOORS THIS FILE CALLS. Same pattern as the rest of the tree: declared where used, defined by the
 * cell that owns the state. */
@interface NSPathCell (AGPathControlSeam)
- (void)cg_setClickedPathComponentCell:(NSPathComponentCell *)cell;
- (void)cg_popUpMenuWithEvent:(NSEvent *)event inView:(NSView *)view;
@end

@interface NSPathControl ()
- (NSPathCell *)fn_pathCell;
- (void)fn_installMouseMovedArea;
@end

@implementation NSPathControl

/* ============================================================================================
 * ARCHIVING: NOTHING: DRAG MASKS, A TRACKING AREA AND A DELEGATE.
 * ============================================================================================ */
/* **ALL FOUR MEMBERS ARE STATE OF A CONTROL THAT IS RUNNING OR A CONNECTION.** The two `_cg` drag masks are what the
 * current drag session is allowed to do, the tracking area is installed when the control enters a window, and the
 * delegate is the object that answers for it — which a nib wires with a CONNECTION, not with a value. The path itself is
 * the CONTROL's CELL (`NSPathCell`), which does archive its components. */

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	return [super initWithCoder:aDecoder];
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSPathCell *cell = [[NSPathCell alloc] init];

		[cell setEnabled:YES];
		/* THE CELL'S DELEGATE IS THE CONTROL, which is Apple's arrangement: the control forwards the two cell hooks to
		 * its own delegate so a caller implements one delegate, not two. */
		[cell setDelegate:(id)self];
		[self setCell:cell];
		[cell release];
		_cgLocalMask = NSDragOperationEvery;
		_cgNonLocalMask = NSDragOperationNone;
		_cgTrackingArea = nil;
		if (frameRect.size.height <= 0.0) {
			[self setFrameSize:NSMakeSize(frameRect.size.width, 24.0)];
		}
	}
	return self;
}

- (void)dealloc
{
	if (_cgTrackingArea != nil) {
		[self removeTrackingArea:_cgTrackingArea];
		[_cgTrackingArea release];
	}
	[super dealloc];
}

- (NSPathCell *)fn_pathCell
{
	return (NSPathCell *)[self cell];
}

/* ---- THE FORWARDS ------------------------------------------------------------------------------- */

- (NSURL *)URL
{
	return [[self fn_pathCell] URL];
}

- (void)setURL:(NSURL *)url
{
	[[self fn_pathCell] setURL:url];
	[self setNeedsDisplay:YES];
}

- (SEL)doubleAction
{
	return [[self fn_pathCell] doubleAction];
}

- (void)setDoubleAction:(SEL)action
{
	[[self fn_pathCell] setDoubleAction:action];
}

- (NSPathStyle)pathStyle
{
	return [[self fn_pathCell] pathStyle];
}

- (void)setPathStyle:(NSPathStyle)style
{
	[[self fn_pathCell] setPathStyle:style];
	[self setNeedsDisplay:YES];
}

- (NSPathComponentCell *)clickedPathComponentCell
{
	return [[self fn_pathCell] clickedPathComponentCell];
}

- (NSArray *)pathComponentCells
{
	return [[self fn_pathCell] pathComponentCells];
}

- (void)setPathComponentCells:(NSArray *)cells
{
	[[self fn_pathCell] setPathComponentCells:cells];
	[self setNeedsDisplay:YES];
}

- (void)setBackgroundColor:(NSColor *)color
{
	[[self fn_pathCell] setBackgroundColor:color];
	[self setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor
{
	return [[self fn_pathCell] backgroundColor];
}

- (id <NSPathControlDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(id <NSPathControlDelegate>)delegate
{
	_delegate = delegate;	/* NOT RETAINED */
	[[self fn_pathCell] setDelegate:(id)self];
}

- (void)setDraggingSourceOperationMask:(NSDragOperation)mask forLocal:(BOOL)isLocal
{
	if (isLocal) {
		_cgLocalMask = mask;
	} else {
		_cgNonLocalMask = mask;
	}
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	return isLocal ? _cgLocalMask : _cgNonLocalMask;
}

- (void)setMenu:(NSMenu *)menu
{
	[[self fn_pathCell] setMenu:menu];
}

- (NSMenu *)menu
{
	return (NSMenu *)[[self fn_pathCell] menu];
}

/* ---- THE CELL'S TWO DELEGATE HOOKS, FORWARDED TO THE CONTROL'S DELEGATE ------------------------- */

- (void)pathCell:(NSPathCell *)pathCell willPopUpMenu:(NSMenu *)menu
{
	(void)pathCell;
	if (_delegate != nil && [_delegate respondsToSelector:@selector(pathControl:willPopUpMenu:)]) {
		[_delegate pathControl:self willPopUpMenu:menu];
	}
}

- (void)pathCell:(NSPathCell *)pathCell willDisplayOpenPanel:(NSOpenPanel *)openPanel
{
	(void)pathCell;
	if (_delegate != nil && [_delegate respondsToSelector:@selector(pathControl:willDisplayOpenPanel:)]) {
		[_delegate pathControl:self willDisplayOpenPanel:openPanel];
	}
}

/* ---- THE POINTER --------------------------------------------------------------------------------- */

- (void)fn_installMouseMovedArea
{
	if (_cgTrackingArea == nil) {
		_cgTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
							       options:(NSTrackingMouseMoved |
									NSTrackingActiveInActiveApp |
									NSTrackingInVisibleRect)
								 owner:self userInfo:nil];
	}
	if ([self window] != nil) {
		[self addTrackingArea:_cgTrackingArea];
	}
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	if ([self window] != nil) {
		[self fn_installMouseMovedArea];
	} else if (_cgTrackingArea != nil) {
		[self removeTrackingArea:_cgTrackingArea];
	}
}

- (void)mouseMoved:(NSEvent *)event
{
	NSPathCell *cell = [self fn_pathCell];

	[cell mouseEntered:event withFrame:[self bounds] inView:self];
	[super mouseMoved:event];
}

- (void)mouseEntered:(NSEvent *)event
{
	[[self fn_pathCell] mouseEntered:event withFrame:[self bounds] inView:self];
	[super mouseEntered:event];
}

- (void)mouseExited:(NSEvent *)event
{
	[[self fn_pathCell] mouseExited:event withFrame:[self bounds] inView:self];
	[super mouseExited:event];
}

- (void)mouseDown:(NSEvent *)event
{
	NSPathCell *cell = [self fn_pathCell];

	if ([cell pathStyle] == NSPathStylePopUp) {
		[cell cg_popUpMenuWithEvent:event inView:self];
		return;
	}
	if ([event clickCount] >= 2 && [cell doubleAction] != NULL) {
		NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
		NSPathComponentCell *clicked = [cell pathComponentCellAtPoint:p
								   withFrame:[self bounds]
								      inView:self];

		[cell cg_setClickedPathComponentCell:clicked];
		[self sendAction:[cell doubleAction] to:[self target]];
		return;
	}
	[super mouseDown:event];
}

@end
