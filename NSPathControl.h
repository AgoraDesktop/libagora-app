/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPathControl.h — a path bar: a control whose face is a row of path components.
 *
 * **THE CONTROL IS A FORWARDER, THE CELL OWNS THE PATH.** URL, style, component cells, background, double action and
 * the clicked component all live on `NSPathCell`; this class creates that cell, forwards the 10.6 doors, and adds the
 * two things a CONTROL owns: the double-click gesture and the pointer's hover tracking. A single click goes through
 * `NSControl`'s ordinary tracking loop, so the action is sent with `-clickedPathComponentCell` answering the component
 * under the hand.
 *
 * **THE DRAG HALF IS DECLARED AND NOT WIRED, WHICH IS THE HONEST SHAPE HERE.** The drag SESSION exists now
 * (`NSDragging.h`), but this class neither begins one nor registers as a destination, and the open panel and the
 * editable path value are still absent. `allowedTypes` and the two PopUp delegate hooks are stored/implemented where
 * they can be, and the drag-source/destination methods are declared because the era's header declares them. They are
 * not called: what is missing is this class's policy, not the machinery.
 *
 * Written from `NSPathControl.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSPATHCONTROL_H
#define APPKIT_NSPATHCONTROL_H

#import <AppKit/NSControl.h>
#import <AppKit/NSPathCell.h>
#import <AppKit/NSDragging.h>

NS_ASSUME_NONNULL_BEGIN

@class NSMenu;
@class NSOpenPanel;
@class NSPasteboard;
@class NSPathComponentCell;
@class NSPathControl;
@class NSURL;
@protocol NSDraggingInfo;
@protocol NSPathControlDelegate;

@interface NSPathControl : NSControl <NSSecureCoding>
{
	NSDragOperation _cgLocalMask;
	NSDragOperation _cgNonLocalMask;
	id <NSPathControlDelegate> _delegate;	/* NOT RETAINED */
	NSTrackingArea *_cgTrackingArea;	/* RETAINED while installed */
}

- (nullable NSURL *)URL;
- (void)setURL:(nullable NSURL *)url;

- (nullable SEL)doubleAction;
- (void)setDoubleAction:(nullable SEL)action;

- (NSPathStyle)pathStyle;
- (void)setPathStyle:(NSPathStyle)style;

- (nullable NSPathComponentCell *)clickedPathComponentCell;
- (NSArray *)pathComponentCells;
- (void)setPathComponentCells:(NSArray *)cells;

- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)backgroundColor;

- (nullable id <NSPathControlDelegate>)delegate;
- (void)setDelegate:(nullable id <NSPathControlDelegate>)delegate;

/* THE DRAG SOURCE'S MASKS. Stored and answered; nothing consults them because this control begins no drag. */
- (void)setDraggingSourceOperationMask:(NSDragOperation)mask forLocal:(BOOL)isLocal;
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal;

/* The menu is the CELL's, as it is for a pop-up button. */
- (void)setMenu:(nullable NSMenu *)menu;
- (nullable NSMenu *)menu;

@end

@protocol NSPathControlDelegate <NSObject>
@optional

/* DECLARED AND NOT CALLED: the control is not a destination and begins no drag. The two pasteboard types and the drop
 * policy belong to a decision this class has not made; its header names the gap rather than pretending the drop works. */
- (BOOL)pathControl:(NSPathControl *)pathControl
    shouldDragPathComponentCell:(NSPathComponentCell *)pathComponentCell
		 withPasteboard:(NSPasteboard *)pasteboard;
- (NSDragOperation)pathControl:(NSPathControl *)pathControl validateDrop:(id <NSDraggingInfo>)info;
- (BOOL)pathControl:(NSPathControl *)pathControl acceptDrop:(id <NSDraggingInfo>)info;

/* THE TWO PopUp HOOKS. `willDisplayOpenPanel:` is declared and never called because there is no NSOpenPanel;
 * `willPopUpMenu:` is called before the PopUp style's menu is shown. */
- (void)pathControl:(NSPathControl *)pathControl willDisplayOpenPanel:(NSOpenPanel *)openPanel;
- (void)pathControl:(NSPathControl *)pathControl willPopUpMenu:(NSMenu *)menu;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPATHCONTROL_H */
