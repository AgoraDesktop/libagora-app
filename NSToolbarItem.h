/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSToolbarItem.h — one thing in a toolbar.
 *
 * **AN ITEM IS MOSTLY STORAGE, AND THE FEW DECISIONS ARE NAMED.** It holds an identifier, a label, a palette label,
 * a tool tip, an image, an optional custom view, a target/action pair, a tag and a size range. The decisions are:
 * the palette label falls back to the label, the menu-form representation is MADE on first ask (a singleton item
 * carrying the label and the same target/action), and `-validate` asks the target in Apple's order — the toolbar's
 * own protocol first, then the generic UI-validation protocol, then the plain "does it answer the action" rule.
 *
 * **A CUSTOM VIEW WINS OVER THE STANDARD FACE, AND THE SETTERS STILL FORWARD.** Apple's contract is that an item
 * with a view forwards `-setTarget:`, `-setAction:`, `-setTag:`, `-setEnabled:` and `-setImage:` to the view when the
 * view answers them; the item keeps the value as well, because the toolbar's validation and the item's menu form both
 * read it. That is what makes a custom control inside a toolbar behave like the standard item it replaced.
 *
 * Written from `NSToolbarItem.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSTOOLBARITEM_H
#define APPKIT_NSTOOLBARITEM_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import <AppKit/NSUserInterfaceValidation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSImage;
@class NSMenuItem;
@class NSString;
@class NSToolbar;
@class NSView;

/* THE ERA'S PRIORITY VALUES. A toolbar too narrow for its items pushes the lowest priority out first; this tier
 * CLIPS rather than building an overflow menu (there is no menu-tracking session for a toolbar here), but the values
 * are still read by the layout and recorded, so a caller's ordering is not thrown away. */
enum {
	NSToolbarItemVisibilityPriorityStandard = 0,
	NSToolbarItemVisibilityPriorityLow = -1000,
	NSToolbarItemVisibilityPriorityHigh = 1000,
	NSToolbarItemVisibilityPriorityUser = 2000
};

@interface NSToolbarItem : NSObject <NSCopying, NSValidatedUserInterfaceItem>
{
	NSString *_itemIdentifier;		/* COPIED: the delegate and the toolbar identify an item by this */
	NSString *_label;			/* COPIED */
	NSString *_paletteLabel;		/* COPIED, falling back to `_label` */
	NSString *_toolTip;			/* COPIED */
	NSImage *_image;			/* RETAINED */
	NSMenuItem *_menuFormRepresentation;	/* RETAINED, made on demand when nil */
	NSView *_view;				/* RETAINED: the item owns the view it was given */
	id _target;				/* NOT RETAINED: target/action convention */
	SEL _action;
	NSInteger _tag;
	BOOL _enabled;
	BOOL _autovalidates;
	NSInteger _visibilityPriority;
	NSSize _minSize;
	NSSize _maxSize;
	NSToolbar *_toolbar;			/* NOT RETAINED: the toolbar owns the item while it holds it */
}

- (instancetype)initWithItemIdentifier:(NSString *)itemIdentifier;
- (NSString *)itemIdentifier;
- (nullable NSToolbar *)toolbar;

/* THE LABELS AND THE TOOL TIP. `-paletteLabel` answers the label when no palette label was set, which is Apple's
 * documented fallback and the only useful one for the ordinary item. */
- (void)setLabel:(nullable NSString *)label;
- (nullable NSString *)label;
- (void)setPaletteLabel:(nullable NSString *)paletteLabel;
- (nullable NSString *)paletteLabel;
- (void)setToolTip:(nullable NSString *)toolTip;
- (nullable NSString *)toolTip;

/* THE MENU FORM. A toolbar item that does not fit is reachable from an overflow menu on the Mac; this tier clips
 * instead, so the representation is still stored and made on demand, but no menu consumes it yet. */
- (void)setMenuFormRepresentation:(nullable NSMenuItem *)menuItem;
- (nullable NSMenuItem *)menuFormRepresentation;

/* THE ACTION, THE TAG AND THE ENABLED FLAG. Each forwards to the custom view when the view answers the setter. */
- (void)setTag:(NSInteger)tag;
- (NSInteger)tag;
- (void)setTarget:(nullable id)target;
- (nullable id)target;
- (void)setAction:(nullable SEL)action;
- (nullable SEL)action;
- (void)setEnabled:(BOOL)enabled;
- (BOOL)isEnabled;

/* THE PICTURE AND THE CUSTOM VIEW. A custom view wins over the standard face; `-setView:` also tells the toolbar to
 * lay itself out again. */
- (void)setImage:(nullable NSImage *)image;
- (nullable NSImage *)image;
- (void)setView:(nullable NSView *)view;
- (nullable NSView *)view;

/* THE SIZE RANGE. Zero in an axis means "no bound in that axis", the same convention `NSWindow`'s min/max sizes use. */
- (void)setMinSize:(NSSize)size;
- (NSSize)minSize;
- (void)setMaxSize:(NSSize)size;
- (NSSize)maxSize;

/* THE PRIORITY AND THE TWO FLAGS. `-autovalidates` starts YES, which is what makes `-validateVisibleItems` do
 * anything without a caller arranging it; `-allowsDuplicatesInToolbar` is a subclass's answer and defaults to NO. */
- (void)setVisibilityPriority:(NSInteger)visibilityPriority;
- (NSInteger)visibilityPriority;
- (void)setAutovalidates:(BOOL)flag;
- (BOOL)autovalidates;
- (BOOL)allowsDuplicatesInToolbar;

/* VALIDATION. A custom-view item does nothing, because its view owns its own state; a standard item asks its target
 * in the order named at the top of this file. */
- (void)validate;

@end

/* THE INFORMAL PROTOCOL A VALIDATOR IMPLEMENTS. It is a category on NSObject rather than a protocol so that a target
 * written before the toolbar existed can answer it without declaring conformance — the shape `NSMenu.h` uses for
 * `-validateMenuItem:`. */
@interface NSObject (NSToolbarItemValidation)
- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTOOLBARITEM_H */
