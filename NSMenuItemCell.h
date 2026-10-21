/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSMenuItemCell.h — THE CELL THAT DRAWS ONE MENU ITEM (stage D).
 *
 * THIS IS THE DRAWING HALF OF A MENU ITEM, and it is the class the plan's own note has been pointing at since
 * NSMenu's slice was drawn: "NSMenuView/NSMenuItemView (the drawing half)". A menu ITEM holds the data; a menu
 * CELL knows where each part of it goes, which is why the two are separate objects in Apple's design and why the
 * ledger asks for two classes.
 *
 * **IT STANDS ON `NSButtonCell`, WHICH IS WHERE APPLE STANDS IT — AND THIS PARAGRAPH USED TO SAY OTHERWISE.** The
 * deviation it recorded (this class standing on `NSObject`, because Apple's cell family was not in this tier) was
 * CLOSED by §A10ax's re-base, and the paragraph was not retired with it: LINE 38 OF THIS FILE NAMED `NSButtonCell`
 * WHILE THIS LINE STILL NAMED `NSObject`, which is what a stale claim looks like when the code moves and the prose
 * does not. THE REASON THE DEVIATION EXISTED IS WORTH KEEPING, because it is the reason it could be closed: a class
 * named in a header is a class the ledger counts, so the family had to be COMPLETE — `NSCell`, `NSActionCell`,
 * `NSButtonCell` — BEFORE this declaration could name one. §A10bi supplied the last piece this class was missing
 * (the cell's two designated initialisers), and what this class now INHERITS is the frame, the font, the control
 * state and the constructors; what it OWNS is the item, the four widths, the three rects and the drawing.
 *
 * AND THE SPLIT INSIDE THIS CLASS IS THE SAME ONE EVERY DRAWING CLASS IN THIS TIER HAS HAD: **the GEOMETRY is real
 * and the INK is refused.** The three rect doors are pure arithmetic over the four widths, so they are computed
 * here and CHECKED rather than asserted; the six draw doors need a font and a text run, and this tier has no
 * metrics on this side of the library — the same gap `NSMenu`'s `-sizeToFit` refuses over, one class over.
 */
#ifndef APPKIT_NSMENUITEMCELL_H
#define APPKIT_NSMENUITEMCELL_H

#import <Foundation/Foundation.h>
#import <AppKit/NSMenuItem.h>
/* THE BASE CLASS IS IMPORTED RATHER THAN FORWARD-DECLARED, and it is a class THIS TREE owns: a superclass has to be
 * complete here, unlike the names inside the class's own members — which is why `NSMenuItem` above is a real import
 * and a `NSWindow` inside a door is a bare `id`. */
#import <AppKit/NSButtonCell.h>

NS_ASSUME_NONNULL_BEGIN

/* ============================================================================================ *
 * THE DROPDOWN'S OWN MEASURES, WHICH ARE SNOW LEOPARD'S.                                        *
 *                                                                                                *
 * THE VIEW LAYS THE ROWS OUT AND THE CELL DRAWS THEM, so the numbers they have to agree about    *
 * live in one place: a menu width computed from one gutter and a title drawn at another is a      *
 * menu whose ink runs under its own key equivalents.                                             *
 *                                                                                                *
 * A MENU ROW, LEFT TO RIGHT: a GUTTER that holds the checkmark (reserved for EVERY row, whether  *
 * or not it has one, so titles line up), the title, then the key equivalent pinned to the right   *
 * edge with the right padding outside it. The gap is the least air between a title and a key —    *
 * a menu is as wide as its WIDEST row, so the gap is a minimum and not a fixed space.            *
 * ============================================================================================ */
#define APPKIT_MENU_LEFT_GUTTER    20.0
#define APPKIT_MENU_RIGHT_PADDING  14.0
#define APPKIT_MENU_ITEM_GAP       18.0

@interface NSMenuItemCell : NSButtonCell <NSSecureCoding>
{
	/* NOT RETAINED, AND THAT IS APPLE'S ARRANGEMENT: a cell belongs to the menu view it draws in and points AT
	 * the item it draws, so retaining here would make the item and its cell own each other. */
	id _menuItem;
	/* THE FOUR WIDTHS `-calcSize` FILLS IN, and the two flags that say whether anything needs doing: `-needsSizing`
	 * is what makes `-calcSize` cheap to call often, and `-needsDisplay` is what the drawing doors consult. */
	CGFloat _stateImageWidth;
	CGFloat _imageWidth;
	CGFloat _titleWidth;
	CGFloat _keyEquivalentWidth;
	BOOL _needsSizing;
	BOOL _needsDisplay;
	/* **AND WHETHER THIS ROW'S TITLE IS SET IN THE BOLD SYSTEM FACE**, which is one item's due rather than a
	 * property of the item: the APPLICATION MENU carries it (see `NSMenuView`), and the name a desktop is judged by
	 * is the one at the far left of its menu bar. */
	BOOL _bold;
}

/* THE ITEM THIS CELL DRAWS, and the door is the WRITER of both flags below: giving a cell a different item
 * invalidates its measurements AND its appearance, so one call says both. */
@property (nullable, assign) id menuItem;

/* `-tag` IS THE ITEM'S TAG RATHER THAN A FIELD OF THE CELL'S OWN, which is Apple's reading and the reason a cell
 * needs no storage for it: a cell with no item answers zero, and the item's tag is the only tag there is.
 *
 * **AND IT IS A METHOD RATHER THAN A PROPERTY, WHICH IS APPLE'S OWN SPELLING AND — NOW THAT THIS CLASS INHERITS
 * FROM APPLE'S CHAIN — A NECESSITY**: `NSCell` declares `tag` READWRITE, so the `readonly` property that stood here
 * would RESTRICT an inherited attribute and warn (`-Wproperty-attribute-mismatch`). A legal override expressed as a
 * property, in other words, claiming something about the class it overrides. A METHOD DECLARATION OVERRIDES WITHOUT
 * CLAIMING ANY ATTRIBUTE, which is what a subclass override needs — and Apple's own `NSMenuItemCell.h` spells it
 * that way for the same reason. */
- (NSInteger)tag;

/* **WHETHER THIS ROW IS SET IN BOLD.** The face is the bold SYSTEM font at the system's size, so this is a
 * property OF THE ROW and not of the item it draws — which matches where the answer comes from: the menu BAR knows
 * that its own first item is the application menu, and the item itself has no idea. */
@property BOOL bold;

/* THE TWO FLAGS. `-needsSizing` IS READ BY `-calcSize`, which measures the item only when the answer is yes and
 * clears the flag when it has — so the flag is not a field stored and consulted nowhere, it is what makes
 * measuring idempotent. `-needsDisplay` IS READ BY THE DRAWING DOORS below: a cell that does not need display is
 * one the drawing doors leave alone, and the first thing a draw does is clear it. */
@property BOOL needsSizing;
@property BOOL needsDisplay;

/* THE MEASUREMENT. It fills the four widths in from the item — the state image's width and the image's width come
 * from the images themselves, AND THE TWO TEXT WIDTHS STAY ZERO because this tier cannot measure a string (stated
 * in the implementation, not hidden here). */
- (void)calcSize;
@property (readonly) CGFloat stateImageWidth;
@property (readonly) CGFloat imageWidth;
@property (readonly) CGFloat titleWidth;
@property (readonly) CGFloat keyEquivalentWidth;

/* ============================================================================================ *
 * THE THREE RECTS, WHICH ARE PURE ARITHMETIC OVER THE FOUR WIDTHS — THIS CLASS'S REAL HALF.      *
 * ============================================================================================ */

/* ONE ROW OF A MENU, LEFT TO RIGHT: the state image (a checkmark's column), the image, the title, the space that
 * separates them, and the key equivalent pinned to the right edge. These three doors place the first, third and
 * fifth of those; the space between is what `-titleRectForBounds:` takes and no door needs to name it. */
- (NSRect)stateImageRectForBounds:(NSRect)cellFrame;
- (NSRect)titleRectForBounds:(NSRect)cellFrame;
- (NSRect)keyEquivalentRectForBounds:(NSRect)cellFrame;

/* ============================================================================================ *
 * AND THE SIX DRAWING DOORS, EACH PRESENT AND REFUSING BY NAME.                                  *
 * ============================================================================================ */

/* THE CONVENTION IS THE ONE THIS PLAN HAS USED SINCE STAGE A: each door is DECLARED AND DEFINED, answers
 * nothing, and says what it needed — so a caller can compile against Apple's surface and learn by name what is
 * missing, and a row counts as shipped because a named refusal is shipped. WHAT THEY NEED IS THE SAME THING EVERY
 * TIME: THE INK — a font, a measured string, and the menu view's frame and state plumbing. This class owns where
 * a part goes; it does not own how the part is painted, because that is the drawing half's other half. */
- (void)drawSeparatorItemWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawStateImageWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawImageWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawTitleWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawKeyEquivalentWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawBorderAndBackgroundWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;

/* **AND THE ONE DOOR OF THE TWO THAT IS STILL THIS CLASS'S OWN, WHICH IS THE DECODER.** `-initTextCell:` was declared
 * here as well, and the declaration went with the override it belonged to: the class now INHERITS the cell's
 * designated initialiser (§A10bi) instead of refusing it, and a redeclaration would have been a second spelling of an
 * inherited signature — which the compiler caught, once, as a nullability conflict with `NSCell`'s `nullable` string.
 *
 * THE DECODER DOOR STILL REFUSES, and on a ground the re-base never touched: Apple's archived-cell key set is not
 * published, so there is no schema to read, which is the same reason every other archived object in this tier
 * refuses. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSMENUITEMCELL_H */
