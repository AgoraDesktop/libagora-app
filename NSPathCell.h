/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSPathCell.h — a path as a row of component cells.
 *
 * **THE CELL OWNS THE PATH, AND THE COMPONENTS ARE ITS ROWS.** `-setURL:` replaces the component array with one cell
 * per path component, each carrying its own prefix URL; a caller may instead set the array by hand. The geometry is
 * the path's: components are laid out left to right with separators between them, and when the natural row is wider
 * than the frame the MIDDLE components are hidden and an ellipsis is drawn in their place, because the first and last
 * components are the two a person navigates by.
 *
 * **THE THREE PATH STYLES ARE THREE FACES, NOT THREE VALUES.** Standard is the light-blue bar with small arrows;
 * NavigationBar is the breadcrumb bar with chevrons and small control size; PopUp shows the last component and opens a
 * menu of the whole path when pressed. Standard and NavigationBar track component clicks; PopUp tracks a menu choice.
 *
 * WHAT THIS SLICE DOES NOT DO: the editable/drop half of the 10.6 class. The drag session exists now
 * (`NSDragging.h`), but this cell does not register as a destination or begin a drag; the open panel and the animated
 * hover expansion are still absent. `allowedTypes`, `doubleAction`, the delegate hooks and the control-size
 * propagation are stored/implemented; the two delegate hooks are called only from the PopUp menu and the open panel is
 * not shown.
 *
 * Written from `NSPathCell.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSPATHCELL_H
#define APPKIT_NSPATHCELL_H

#import <AppKit/NSActionCell.h>
#import <AppKit/NSPathComponentCell.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSAttributedString;
@class NSColor;
@class NSEvent;
@class NSMenu;
@class NSOpenPanel;
@class NSPathCell;
@class NSString;
@class NSURL;
@class NSView;

/* THE ERA'S THREE STYLES. Apple publishes the case names and their order; the values are the header's own. */
enum {
	NSPathStyleStandard = 0,
	NSPathStyleNavigationBar = 1,
	NSPathStylePopUp = 2
};
typedef NSInteger NSPathStyle;

@protocol NSPathCellDelegate <NSObject>
@optional
/* The 10.6 open-panel hook. It is declared and never called, because this tier has no NSOpenPanel; the header says
 * so rather than letting a delegate believe it will be asked. */
- (void)pathCell:(NSPathCell *)pathCell willDisplayOpenPanel:(NSOpenPanel *)openPanel;
/* Called before the PopUp style's menu is shown, so a delegate can add or remove rows. */
- (void)pathCell:(NSPathCell *)pathCell willPopUpMenu:(NSMenu *)menu;
@end

@interface NSPathCell : NSActionCell <NSSecureCoding>
{
	NSMutableArray *_cells;			/* RETAINED: NSPathComponentCell objects */
	NSPathComponentCell *_clickedCell;	/* BORROWED: a cell in `_cells`, valid while the action is sent */
	NSPathComponentCell *_hoveredCell;	/* BORROWED */
	NSURL *_url;				/* RETAINED */
	NSColor *_backgroundColor;		/* RETAINED */
	BOOL _cgBackgroundUserSet;
	NSArray *_allowedTypes;			/* COPIED */
	SEL _doubleAction;
	id <NSPathCellDelegate> _delegate;	/* NOT RETAINED */
	NSPathStyle _pathStyle;
	NSString *_placeholderString;		/* COPIED */
	NSAttributedString *_placeholderAttributedString;	/* RETAINED */
}

- (NSPathStyle)pathStyle;
- (void)setPathStyle:(NSPathStyle)style;

- (nullable NSURL *)URL;
- (void)setURL:(nullable NSURL *)url;
- (void)setObjectValue:(nullable id <NSCopying>)obj;

- (nullable NSArray *)allowedTypes;
- (void)setAllowedTypes:(nullable NSArray *)allowedTypes;

- (nullable id <NSPathCellDelegate>)delegate;
- (void)setDelegate:(nullable id <NSPathCellDelegate>)value;

+ (Class)pathComponentCellClass;

- (NSArray *)pathComponentCells;
- (void)setPathComponentCells:(NSArray *)cells;

- (NSRect)rectOfPathComponentCell:(NSPathComponentCell *)cell
			withFrame:(NSRect)frame inView:(nullable NSView *)view;
- (nullable NSPathComponentCell *)pathComponentCellAtPoint:(NSPoint)point
						withFrame:(NSRect)frame inView:(nullable NSView *)view;
- (nullable NSPathComponentCell *)clickedPathComponentCell;

- (void)mouseEntered:(NSEvent *)event withFrame:(NSRect)frame inView:(nullable NSView *)view;
- (void)mouseExited:(NSEvent *)event withFrame:(NSRect)frame inView:(nullable NSView *)view;

- (nullable SEL)doubleAction;
- (void)setDoubleAction:(nullable SEL)action;

- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)backgroundColor;

- (void)setPlaceholderString:(nullable NSString *)string;
- (nullable NSString *)placeholderString;
- (void)setPlaceholderAttributedString:(nullable NSAttributedString *)string;
- (nullable NSAttributedString *)placeholderAttributedString;

- (void)setControlSize:(NSControlSize)size;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPATHCELL_H */
