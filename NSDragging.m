/*
 * NSDragging.m — the in-process drag session: the loop, the image, and the destination search.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE SESSION LIVES IN THE APPLICATION, NOT IN THE WINDOW SERVER.** A drag is a pointer that has left its view
 * but not its button: the source view's window takes the pointer for the duration (the same real capture a window
 * move and a resize use), every motion and the release arrive at that window, and `NSWindow -sendEvent:` hands them
 * here before any view sees them. The destination is then found by SCREEN POINT rather than by event routing —
 * `+[NSWindow windowNumberAtPoint:belowWindowWithWindowNumber:]` names the frontmost window of this application at
 * that point, and its content view's `-hitTest:` walks to the view that registered for the dragged types. That is
 * what lets one drag cross from one window to another and still be one drag.
 *
 * **THE DRAG IMAGE IS A BORDERLESS WINDOW.** A client cannot draw over another window's surface, so a floating
 * image has to be a window of its own: borderless, transparent, level `NSFloatingWindowLevel`, and
 * `-setIgnoresMouseEvents:YES` so the destination search never finds the image instead of the view beneath it. On a
 * machine with no compositor no window can be made, and the session still runs — the search, the masks and the
 * callbacks are arithmetic, and they are what the offscreen probe measures.
 *
 * **WHAT THIS IS NOT.** The cross-process half is the window server's: another application's pointer, another
 * application's pasteboard and another application's destination are a transport the shell protocol has not got.
 * The pasteboard here is the caller's (`NSDragPboard` for the modern door, the one handed in for 10.6's), so a
 * source writes its types before beginning. Neither of those is approximated; both are named where a reader meets
 * them, and `README.md` records the slice as the application half of W7.
 */
#import <AppKit/NSDragging.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSGeometry.h>

#include <string.h>

#import "AppKitRefusal.h"

/* THE SEAM'S DOORS, DECLARED HERE BECAUSE THIS IS THE FILE THAT USES THEM. The capture is `NSWindow`'s (it is the
 * same one a window move takes), and the server question is the one that decides whether an image window can be
 * made at all. Both are private for the reasons the tree's other `cg_` doors are: they are not Apple's API. */
@interface NSWindow (APPKITDragSeam)
- (void)cg_setPointerCapture:(BOOL)flag;
+ (BOOL)cg_hasWindowServer;
@end

/* THE COMPOSITOR'S ABSOLUTE POINTER, when the event carries it. A captured motion is relative to the SOURCE window
 * and may be far outside it; the absolute point is what the destination search needs, so it is preferred whenever
 * the seam supplied one. */
@interface NSEvent (APPKITDragGlobalPoint)
- (NSPoint)cg_globalPoint;
- (BOOL)cg_hasGlobalPoint;
@end

/* ============================================================================================ *
 * THE IMAGE'S WINDOW — ONE VIEW THAT DRAWS THE COMPOSED IMAGE, FILLING ITS FRAME.               *
 * ============================================================================================ */

@interface AGDragImageView : NSView
{
	NSImage *_image;	/* RETAINED */
}
- (void)setImage:(NSImage *)image;
@end

@implementation AGDragImageView
- (void)dealloc
{
	[_image release];
	[super dealloc];
}
- (void)setImage:(NSImage *)image
{
	if (_image == image) {
		return;
	}
	[image retain];
	[_image release];
	_image = image;
	[self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	/* THE IMAGE IS EXACTLY THE BOUNDS' SIZE — the window was made from it — so this is a copy rather than a scale. */
	if (_image != nil) {
		[_image drawInRect:[self bounds]];
	}
}
@end

/* ============================================================================================ *
 * THE INFO OBJECT — the protocol answered in the DESTINATION'S terms, reading live session state. *
 * ============================================================================================ */

@interface NSDraggingItem (APPKITContents)
- (id)cg_contents;
@end

@implementation NSDraggingItem (APPKITContents)
- (id)cg_contents { return _contents; }
@end

@interface NSDraggingSession (APPKITInfo)
- (NSWindow *)cg_destinationWindow;
- (NSPoint)cg_destinationLocation;
- (NSPoint)cg_draggedImageLocation;
- (NSImage *)cg_image;
- (NSPasteboard *)cg_pasteboard;
- (id <NSDraggingSource>)cg_source;
- (NSDragOperation)cg_sourceMask;
- (NSInteger)cg_sequenceNumber;
- (NSDraggingFormation)cg_formation;
- (void)cg_setFormation:(NSDraggingFormation)formation;
- (void)cg_slideImageToPoint:(NSPoint)screenPoint;
- (NSArray *)cg_namesOfPromisedFilesAtDestination:(NSURL *)destination;
@end

@interface AGDraggingInfo : NSObject <NSDraggingInfo>
{
	NSDraggingSession *_session;	/* BORROWED: the session outlives every callback it makes */
}
- (instancetype)initWithSession:(NSDraggingSession *)session;
@end

@implementation AGDraggingInfo
- (instancetype)initWithSession:(NSDraggingSession *)session
{
	self = [super init];
	if (self != nil) {
		_session = session;
	}
	return self;
}
- (NSWindow *)draggingDestinationWindow { return [_session cg_destinationWindow]; }
- (NSDragOperation)draggingSourceOperationMask { return [_session cg_sourceMask]; }
- (NSPoint)draggingLocation { return [_session cg_destinationLocation]; }
- (NSPoint)draggedImageLocation { return [_session cg_draggedImageLocation]; }
- (NSImage *)draggedImage { return [_session cg_image]; }
- (NSPasteboard *)draggingPasteboard { return [_session cg_pasteboard]; }
- (id)draggingSource { return [_session cg_source]; }
- (NSInteger)draggingSequenceNumber { return [_session cg_sequenceNumber]; }
- (void)slideDraggedImageTo:(NSPoint)screenPoint { [_session cg_slideImageToPoint:screenPoint]; }
- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination
{
	return [_session cg_namesOfPromisedFilesAtDestination:dropDestination];
}
- (NSDraggingFormation)draggingFormation { return [_session cg_formation]; }
- (void)setDraggingFormation:(NSDraggingFormation)formation { [_session cg_setFormation:formation]; }
- (NSInteger)numberOfValidItemsForDrop { return 1; }
- (void)setNumberOfValidItemsForDrop:(NSInteger)number { (void)number; }
@end

/* ============================================================================================ *
 * THE ITEM.                                                                                    *
 * ============================================================================================ */

@implementation NSDraggingItem
- (instancetype)initWithPasteboardWriter:(id)pasteboardWriter
{
	self = [super init];
	if (self != nil) {
		_item = [pasteboardWriter retain];
		_draggingFrame = NSZeroRect;
	}
	return self;
}
- (void)dealloc
{
	[_item release];
	[_contents release];
	[super dealloc];
}
- (id)item { return _item; }
- (NSRect)draggingFrame { return _draggingFrame; }
/* **THE SETTER THE `@property` DECLARES, WHICH HAD NO BODY.** `-setDraggingFrame:contents:` was implemented and
 * this one was not, so a caller setting only the frame got an unrecognized selector. It sets the frame and leaves
 * the contents alone, which is what the two-argument door does when its contents are nil — except that it does not
 * CLEAR them, because a caller asking to move an item did not ask to drop its picture. */
- (void)setDraggingFrame:(NSRect)frame
{
	_draggingFrame = frame;
}
- (NSArray *)imageComponents
{
	/* **NIL, BECAUSE THERE IS NO `NSDraggingImageComponent` IN THIS TREE.** Apple's answer is an array of components
	 * derived from the contents; handing back the NSImage itself would answer a different class under the same
	 * selector and invite a caller to message it as a component. The contents and the frame are what this tier has. */
	return nil;
}
- (void)setDraggingFrame:(NSRect)frame contents:(id)contents
{
	if (contents != nil && ![contents isKindOfClass:[NSImage class]]) {
		fn_refuse_window("-setDraggingFrame:contents:",
				 "an NSDraggingImageComponent array (this tree has no NSDraggingImageComponent); the "
				 "item keeps no image rather than guessing at one");
		contents = nil;
	}
	_draggingFrame = frame;
	[contents retain];
	[_contents release];
	_contents = contents;
}
@end

/* ============================================================================================ *
 * THE SESSION'S PRIVATE STATE AND THE ONE THAT IS LIVE.                                         *
 * ============================================================================================ */

static NSDraggingSession *s_activeSession;
static NSInteger s_sequenceNumber;

/* A SCREEN RECT FROM A VIEW RECT. Root space IS the window's space in this tier (the root view's own frame origin
 * is not applied — see `fn_up_to_root` in NSView.m), so the conversion is the view's own walk plus the frame origin. */
static NSPoint fn_screen_from_view(NSView *view, NSPoint point)
{
	NSWindow *window = [view window];
	NSPoint inWindow;
	NSRect frame;

	if (window == nil) {
		return point;
	}
	inWindow = [view convertPoint:point toView:nil];
	frame = [window frame];
	return NSMakePoint(frame.origin.x + inWindow.x, frame.origin.y + inWindow.y);
}

static BOOL fn_point_in_rect(NSPoint point, NSRect rect)
{
	return point.x >= rect.origin.x && point.x < (rect.origin.x + rect.size.width)
	       && point.y >= rect.origin.y && point.y < (rect.origin.y + rect.size.height);
}

/* THE WINDOW AT A SCREEN POINT. With a compositor this is Apple's own door. WITHOUT one there is no screen, so
 * "visible" cannot be asked — the application's registry is the only order there is, and a probe's windows are
 * candidates because they are the application's own geometry. That is a stated fallback rather than a second
 * definition of visibility: the compositor path is the one a running application takes. */
static NSWindow *fn_window_at_screen_point(NSPoint point)
{
	NSApplication *app = [NSApplication sharedApplication];
	NSArray *windows;
	NSUInteger i;

	if ([NSWindow cg_hasWindowServer]) {
		NSInteger number = [NSWindow windowNumberAtPoint:point belowWindowWithWindowNumber:0];

		return (number != 0) ? [app windowWithWindowNumber:number] : nil;
	}
	windows = [app windows];
	for (i = 0; i < [windows count]; i++) {
		NSWindow *w = [windows objectAtIndex:i];

		if ([w ignoresMouseEvents]) {
			continue;	/* the drag image's own window is one of these, by construction */
		}
		if (fn_point_in_rect(point, [w frame])) {
			return w;
		}
	}
	return nil;
}

/* THE TYPES A VIEW OR WINDOW REGISTERED, INTERSECTED WITH THE DRAG'S. A nil list intersects nothing. */
static BOOL fn_types_intersect(NSArray *registered, NSArray *dragged)
{
	NSUInteger i;

	if (registered == nil || dragged == nil) {
		return NO;
	}
	for (i = 0; i < [dragged count]; i++) {
		if ([registered containsObject:[dragged objectAtIndex:i]]) {
			return YES;
		}
	}
	return NO;
}

/* THE DESTINATION IS THE DEEPEST VIEW UNDER THE POINTER THAT WILL HAVE THE DRAG.** The walk begins at the hit
 * test's answer and climbs, so a registered container catches a drag over an unregistered child — which is how a
 * source list's row (a cell, not a view) can hand a drop to the table that owns it. A window's own registration is
 * the last chance, and its content view is the view that answers. */
static NSView *fn_destination_view(NSWindow *window, NSPoint windowPoint, NSArray *types)
{
	NSView *view = [[window contentView] hitTest:windowPoint];

	while (view != nil) {
		if ([view cg_acceptsDraggedTypes:types]) {
			return view;
		}
		view = [view superview];
	}
	if (fn_types_intersect([window cg_registeredDraggedTypes], types)) {
		return [window contentView];
	}
	return nil;
}

/* THE MODIFIER RULE, STATED RATHER THAN LEFT TO A FEELING. Option turns a permitted MOVE into a COPY when the
 * source allows copying; everything else is the destination's answer intersected with the source's mask. A source
 * that answers YES to `-ignoreModifierKeysWhileDragging` opts out entirely. */
static NSDragOperation fn_apply_modifiers(NSDragOperation operation, NSDragOperation mask, NSEvent *event,
					  BOOL ignoreModifiers)
{
	operation &= mask;
	if (ignoreModifiers || event == nil) {
		return operation;
	}
	if ((operation & NSDragOperationMove) != 0
	    && ([event modifierFlags] & NSAlternateKeyMask) != 0
	    && (mask & NSDragOperationCopy) != 0) {
		operation &= ~NSDragOperationMove;
		operation |= NSDragOperationCopy;
	}
	return operation;
}

/* ============================================================================================ *
 * THE SESSION.                                                                                 *
 * ============================================================================================ */

@interface NSDraggingSession ()
- (instancetype)cg_initWithItems:(NSArray *)items event:(NSEvent *)event source:(id <NSDraggingSource>)source
			    view:(NSView *)view pasteboard:(NSPasteboard *)pasteboard slideBack:(BOOL)slideBack;
- (void)cg_composeImage;
- (void)cg_updateImageWindow;
- (void)cg_moveToScreenPoint:(NSPoint)point event:(NSEvent *)event;
- (void)cg_updateDestinationAtPoint:(NSPoint)point event:(NSEvent *)event;
- (void)cg_leaveDestination;
- (void)cg_endAtPoint:(NSPoint)point cancelled:(BOOL)cancelled;
- (void)cg_finish;
@end

@implementation NSDraggingSession

+ (NSDraggingSession *)cg_activeSession
{
	return s_activeSession;
}

/* THE ONE WAY A SESSION BEGINS. The caller has already decided that the press became a drag; this makes the state,
 * composes the image and announces the start. It is retained by the tier so a source's ended callback can read it
 * even when the caller autoreleased what it was handed. */
+ (NSDraggingSession *)cg_beginWithItems:(NSArray *)items event:(NSEvent *)event
				  source:(id <NSDraggingSource>)source view:(NSView *)view
			      pasteboard:(NSPasteboard *)pasteboard slideBack:(BOOL)slideBack
{
	NSDraggingSession *session;

	if (s_activeSession != nil) {
		fn_refuse_window("a second drag session",
				 "one drag at a time — the pointer is already captured by the first; the running "
				 "session ends before another can begin");
		return nil;
	}
	if (view == nil || [view window] == nil || [items count] == 0) {
		fn_refuse_window("a drag session",
				 "a view in a window and at least one item; a drag with no place to begin is not one");
		return nil;
	}
	session = [[NSDraggingSession alloc] cg_initWithItems:items event:event source:source view:view
						    pasteboard:pasteboard slideBack:slideBack];
	if (session == nil) {
		return nil;
	}
	s_activeSession = [session retain];
	[session cg_composeImage];
	[session cg_updateImageWindow];
	/* **THE DRAG BEGINS UNDER THE POINTER, SO THE DESTINATION IS ASKED AT ONCE.** A drag can begin and end with no
	 * motion between (a threshold crossed by one event), and a session that waited for the next motion would report
	 * no destination for a drop that happened under one. */
	[session cg_updateDestinationAtPoint:[session draggingLocation] event:event];
	[[view window] cg_setPointerCapture:YES];

	if ([source respondsToSelector:@selector(draggingSession:willBeginAtPoint:)]) {
		[source draggingSession:session willBeginAtPoint:[session draggingLocation]];
	} else if ([source respondsToSelector:@selector(draggedImage:beganAt:)]) {
		[source draggedImage:[session cg_image] beganAt:[session draggingLocation]];
	}
	return [session autorelease];
}

- (instancetype)cg_initWithItems:(NSArray *)items event:(NSEvent *)event source:(id <NSDraggingSource>)source
			    view:(NSView *)view pasteboard:(NSPasteboard *)pasteboard slideBack:(BOOL)slideBack
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_items = [[NSMutableArray alloc] initWithArray:items];
	_pasteboard = [(pasteboard != nil ? pasteboard : [NSPasteboard pasteboardWithName:NSDragPboard]) retain];
	_source = [source retain];
	_sourceView = [view retain];
	_sourceWindow = [[view window] retain];
	_formation = NSDraggingFormationNone;
	_animatesToStartingPositionsOnCancelOrFail = YES;
	_slideBack = slideBack;
	_state = NSDragStateRunning;
	_sequenceNumber = ++s_sequenceNumber;

	if ([source respondsToSelector:@selector(draggingSession:sourceOperationMaskForDraggingContext:)]) {
		_sourceMask = [source draggingSession:self
			    sourceOperationMaskForDraggingContext:NSDraggingContextWithinApplication];
	} else if ([source respondsToSelector:@selector(draggingSourceOperationMaskForLocal:)]) {
		_sourceMask = [source draggingSourceOperationMaskForLocal:YES];
	} else {
		_sourceMask = NSDragOperationNone;
	}

	if (event != nil) {
		if ([event cg_hasGlobalPoint]) {
			_initialLocation = [event cg_globalPoint];
		} else {
			_initialLocation = fn_screen_from_view(view, [event locationInWindow]);
		}
	}
	_location = _initialLocation;
	return self;
}

- (void)dealloc
{
	[_items release];
	[_pasteboard release];
	[_source release];
	[_sourceView release];
	[_sourceWindow release];
	[_dragWindow release];
	[_destinationWindow release];
	[_destinationView release];
	[_image release];
	[super dealloc];
}

- (NSPoint)draggingLocation { return _location; }
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (id <NSDraggingSource>)draggingSource { return _source; }
- (NSDragOperation)sourceOperationMask { return _sourceMask; }
- (NSDragOperation)currentOperationMask { return _currentOperation; }
- (NSDraggingFormation)draggingFormation { return _formation; }
- (void)setDraggingFormation:(NSDraggingFormation)formation { _formation = formation; }
- (BOOL)animatesToStartingPositionsOnCancelOrFail { return _animatesToStartingPositionsOnCancelOrFail; }
- (void)setAnimatesToStartingPositionsOnCancelOrFail:(BOOL)flag
{
	_animatesToStartingPositionsOnCancelOrFail = flag ? YES : NO;
}
- (NSDragState)draggingState { return _state; }
- (NSInteger)draggingSequenceNumber { return _sequenceNumber; }
- (NSWindow *)cg_draggingWindow { return _dragWindow; }
- (NSWindow *)cg_sourceWindow { return _sourceWindow; }

/* ---- THE INFO'S READ SIDE ------------------------------------------------------------------- */

- (NSWindow *)cg_destinationWindow { return _destinationWindow; }
- (NSPoint)cg_destinationLocation { return _destinationPoint; }
- (NSImage *)cg_image { return _image; }
- (NSPasteboard *)cg_pasteboard { return _pasteboard; }
- (id <NSDraggingSource>)cg_source { return _source; }
- (NSDragOperation)cg_sourceMask { return _sourceMask; }
- (NSInteger)cg_sequenceNumber { return _sequenceNumber; }
- (NSDraggingFormation)cg_formation { return _formation; }
- (void)cg_setFormation:(NSDraggingFormation)formation { _formation = formation; }

- (NSPoint)cg_draggedImageLocation
{
	if (_destinationWindow != nil) {
		NSRect frame = [_destinationWindow frame];

		return NSMakePoint(_imageOrigin.x - frame.origin.x, _imageOrigin.y - frame.origin.y);
	}
	return _imageOrigin;
}

- (NSArray *)cg_namesOfPromisedFilesAtDestination:(NSURL *)destination
{
	if ([_source respondsToSelector:@selector(namesOfPromisedFilesDroppedAtDestination:)]) {
		return [_source namesOfPromisedFilesDroppedAtDestination:destination];
	}
	return nil;
}

- (void)cg_slideImageToPoint:(NSPoint)screenPoint
{
	/* THE IMAGE, NOT THE POINTER: `-slideDraggedImageTo:` is a destination telling the image where to finish, and
	 * the pointer is wherever the hand is. There is no animation here, which the header states. */
	_imageOrigin = screenPoint;
	if (_dragWindow != nil) {
		[_dragWindow setFrameOrigin:_imageOrigin];
	}
}

/* ---- THE IMAGE ------------------------------------------------------------------------------ */

/* THE COMPOSED IMAGE IS THE UNION OF THE ITEMS' FRAMES, WITH EACH ITEM DRAWN AT ITS OWN OFFSET.** Frames arrive in
 * the SOURCE VIEW's coordinates and are converted here, so the session (rather than every caller) owns the one
 * conversion. A formation other than `None` is recorded and not laid out: an item keeps the frame it was given. */
- (void)cg_composeImage
{
	NSRect unionRect = NSZeroRect;
	NSImage *image;
	NSUInteger i;
	BOOL first = YES;

	for (i = 0; i < [_items count]; i++) {
		NSDraggingItem *item = [_items objectAtIndex:i];
		NSRect frame = [item draggingFrame];
		NSPoint origin = fn_screen_from_view(_sourceView, frame.origin);
		NSRect screenFrame = NSMakeRect(origin.x, origin.y, frame.size.width, frame.size.height);

		unionRect = first ? screenFrame : NSUnionRect(unionRect, screenFrame);
		first = NO;
	}
	if (first || unionRect.size.width <= 0.0 || unionRect.size.height <= 0.0) {
		/* A DRAG WITH NO VISIBLE ITEM STILL NEEDS A PLACE FOR ITS IMAGE. Sixteen points is the smallest square the
		 * arithmetic below can move without dividing by a zero-sized window. */
		unionRect = NSMakeRect(_initialLocation.x, _initialLocation.y, 16.0, 16.0);
	}
	_imageFrame = unionRect;
	_imageOrigin = unionRect.origin;
	_pointerOffset = NSMakePoint(_initialLocation.x - unionRect.origin.x,
				     _initialLocation.y - unionRect.origin.y);

	image = [[NSImage alloc] initWithSize:unionRect.size];
	[image lockFocus];
	for (i = 0; i < [_items count]; i++) {
		NSDraggingItem *item = [_items objectAtIndex:i];
		id contents = [item cg_contents];
		NSRect frame = [item draggingFrame];

		if (![contents isKindOfClass:[NSImage class]]) {
			continue;
		}
		{
			NSPoint origin = fn_screen_from_view(_sourceView, frame.origin);

			[contents drawInRect:NSMakeRect(origin.x - unionRect.origin.x,
							origin.y - unionRect.origin.y,
							frame.size.width, frame.size.height)];
		}
	}
	[image unlockFocus];
	_image = image;
}

- (void)cg_updateImageWindow
{
	NSPoint origin = _imageOrigin;

	if (_state != NSDragStateRunning || _image == nil) {
		return;
	}
	if (_dragWindow == nil) {
		AGDragImageView *view;
		NSWindow *window;

		/* NO COMPOSITOR, NO IMAGE WINDOW. The session's arithmetic does not need one, and a window that cannot be
		 * shown would only add an APPKIT-REFUSE to a probe's stderr. */
		if (![NSWindow cg_hasWindowServer]) {
			return;
		}
		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(origin.x, origin.y,
									   _imageFrame.size.width,
									   _imageFrame.size.height)
						    styleMask:NSBorderlessWindowMask
						      backing:NSBackingStoreBuffered defer:NO];
		[window setOpaque:NO];
		[window setHasShadow:NO];
		[window setIgnoresMouseEvents:YES];
		[window setLevel:NSFloatingWindowLevel];
		view = [[AGDragImageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, _imageFrame.size.width,
								       _imageFrame.size.height)];
		[view setImage:_image];
		[window setContentView:view];
		[view release];
		[window orderFront:nil];
		_dragWindow = window;
		return;
	}
	[_dragWindow setFrameOrigin:origin];
}

/* ---- THE DESTINATION SEARCH AND THE CALLBACKS ----------------------------------------------- */

- (void)cg_clearDestination
{
	_entered = NO;
	_currentOperation = NSDragOperationNone;
	[_destinationWindow release];
	_destinationWindow = nil;
	[_destinationView release];
	_destinationView = nil;
}

- (void)cg_leaveDestination
{
	if (_entered && _destinationView != nil) {
		AGDraggingInfo *info = [[AGDraggingInfo alloc] initWithSession:self];

		if ([_destinationView respondsToSelector:@selector(draggingExited:)]) {
			[_destinationView draggingExited:info];
		}
		[info release];
	}
	[self cg_clearDestination];
}

- (void)cg_updateDestinationAtPoint:(NSPoint)point event:(NSEvent *)event
{
	NSWindow *window = fn_window_at_screen_point(point);
	NSView *view = nil;
	NSPoint windowPoint = NSZeroPoint;
	NSArray *types = [_pasteboard types];

	/* WITHOUT A COMPOSITOR THE SOURCE WINDOW NEED NOT BE IN THE APPLICATION'S REGISTRY (a probe's window is made
	 * for its geometry and never ordered in), so the window the drag began in is the last candidate. With a server
	 * the registry is the truth and this fallback is not reached. */
	if (window == nil && ![NSWindow cg_hasWindowServer] && _sourceWindow != nil
	    && fn_point_in_rect(point, [_sourceWindow frame])) {
		window = _sourceWindow;
	}
	if (window != nil) {
		NSRect frame = [window frame];

		windowPoint = NSMakePoint(point.x - frame.origin.x, point.y - frame.origin.y);
		view = fn_destination_view(window, windowPoint, types);
	}
	if (view != _destinationView) {
		[self cg_leaveDestination];
		if (view != nil) {
			AGDraggingInfo *info;

			_destinationWindow = [window retain];
			_destinationView = [view retain];
			_destinationPoint = windowPoint;
			info = [[AGDraggingInfo alloc] initWithSession:self];
			_currentOperation = NSDragOperationNone;
			if ([view respondsToSelector:@selector(draggingEntered:)]) {
				_currentOperation = [view draggingEntered:info];
			}
			_currentOperation = fn_apply_modifiers(_currentOperation, _sourceMask, event,
							       [self cg_ignoresModifiers]);
			_entered = YES;
			[info release];
		}
	} else if (_destinationView != nil) {
		AGDraggingInfo *info;

		_destinationPoint = windowPoint;
		info = [[AGDraggingInfo alloc] initWithSession:self];
		if ([_destinationView respondsToSelector:@selector(draggingUpdated:)]) {
			_currentOperation = [_destinationView draggingUpdated:info];
		}
		_currentOperation = fn_apply_modifiers(_currentOperation, _sourceMask, event,
						       [self cg_ignoresModifiers]);
		[info release];
	}
}

- (BOOL)cg_ignoresModifiers
{
	return ([_source respondsToSelector:@selector(ignoreModifierKeysWhileDragging)]
		&& [_source ignoreModifierKeysWhileDragging]) ? YES : NO;
}

- (void)cg_moveToScreenPoint:(NSPoint)point event:(NSEvent *)event
{
	_location = point;
	_imageOrigin = NSMakePoint(point.x - _pointerOffset.x, point.y - _pointerOffset.y);
	[self cg_updateImageWindow];
	[self cg_updateDestinationAtPoint:point event:event];
	if ([_source respondsToSelector:@selector(draggingSession:movedToPoint:)]) {
		[_source draggingSession:self movedToPoint:point];
	} else if ([_source respondsToSelector:@selector(draggedImage:movedTo:)]) {
		[_source draggedImage:_image movedTo:point];
	}
}

/* ---- ENDING --------------------------------------------------------------------------------- */

- (void)cg_endAtPoint:(NSPoint)point cancelled:(BOOL)cancelled
{
	NSDragOperation operation = NSDragOperationNone;
	BOOL performed = NO;

	if (_state != NSDragStateRunning) {
		return;
	}
	_location = point;
	_imageOrigin = NSMakePoint(point.x - _pointerOffset.x, point.y - _pointerOffset.y);
	[self cg_updateImageWindow];

	if (!cancelled && _destinationView != nil && _currentOperation != NSDragOperationNone) {
		AGDraggingInfo *info = [[AGDraggingInfo alloc] initWithSession:self];
		BOOL prepared = YES;

		if ([_destinationView respondsToSelector:@selector(prepareForDragOperation:)]) {
			prepared = [_destinationView prepareForDragOperation:info];
		}
		if (prepared) {
			if ([_destinationView respondsToSelector:@selector(performDragOperation:)]) {
				performed = [_destinationView performDragOperation:info];
			}
			if (performed) {
				operation = _currentOperation;
				if ([_destinationView respondsToSelector:@selector(concludeDragOperation:)]) {
					[_destinationView concludeDragOperation:info];
				}
			}
		}
		[info release];
	}
	if (_destinationView != nil) {
		AGDraggingInfo *info = [[AGDraggingInfo alloc] initWithSession:self];

		if ([_destinationView respondsToSelector:@selector(draggingEnded:)]) {
			[_destinationView draggingEnded:info];
		}
		[info release];
		[self cg_clearDestination];	/* no `-draggingExited:` after a drop, which is Apple's sequence */
	}

	_state = NSDragStateDone;
	/* **THE ACTIVE SLOT IS CLEARED BEFORE THE CALLBACKS, NOT AFTER.** A source that begins the next drag from its
	 * ended callback would otherwise have that new session nil'd out by this one's cleanup. The tier's own retain is
	 * what keeps this object alive to the bottom of the method. */
	s_activeSession = nil;
	/* THE IMAGE IS STILL ON THE GLASS WHEN THE SOURCE IS TOLD, which is Apple's contract for
	 * `-draggedImage:endedAt:operation:` and the reason the removal is below the callbacks. */
	if ([_source respondsToSelector:@selector(draggingSession:endedAtPoint:operation:)]) {
		[_source draggingSession:self endedAtPoint:point operation:operation];
	} else if ([_source respondsToSelector:@selector(draggedImage:endedAt:operation:)]) {
		[_source draggedImage:_image endedAt:point operation:operation];
	}
	if (_dragWindow != nil) {
		[_dragWindow orderOut:nil];
		[_dragWindow release];
		_dragWindow = nil;
	}
	[_sourceWindow cg_setPointerCapture:NO];
	[self release];	/* THE TIER'S RETAIN, taken in +cg_beginWithItems:... — the caller's is its own. */
}

- (void)cg_finish
{
	[self cg_endAtPoint:_location cancelled:YES];
}

/* ---- THE EVENT DOOR ------------------------------------------------------------------------- */

- (BOOL)cg_handleEvent:(NSEvent *)event
{
	NSPoint point;

	if (_state != NSDragStateRunning) {
		return NO;
	}
	switch ([event type]) {
	case NSLeftMouseDragged:
		if ([event cg_hasGlobalPoint]) {
			point = [event cg_globalPoint];
		} else {
			NSRect frame = [_sourceWindow frame];

			point = [event locationInWindow];
			point = NSMakePoint(frame.origin.x + point.x, frame.origin.y + point.y);
		}
		[self cg_moveToScreenPoint:point event:event];
		return YES;
	case NSLeftMouseUp:
		if ([event cg_hasGlobalPoint]) {
			point = [event cg_globalPoint];
		} else {
			NSRect frame = [_sourceWindow frame];

			point = [event locationInWindow];
			point = NSMakePoint(frame.origin.x + point.x, frame.origin.y + point.y);
		}
		[self cg_endAtPoint:point cancelled:NO];
		return YES;
	case NSKeyDown: {
		NSString *characters = [event characters];

		/* ESCAPE CANCELS, which is the one key a drag owns. Everything else is declined and reaches the responder
		 * chain, because a drag does not take the keyboard. */
		if ([characters length] > 0 && [characters characterAtIndex:0] == 0x1b) {
			[self cg_finish];
			return YES;
		}
		return NO;
	}
	default:
		return NO;
	}
}

@end
