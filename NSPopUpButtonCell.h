/*
 * NSPopUpButtonCell.h — THE CELL THAT RAISES A MENU, AND THE FIRST CONTROL THAT JOINS TWO SUBSYSTEMS.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **EVERY CONTROL IN THIS TIER SO FAR HAS BEEN ONE SUBSYSTEM WEARING A CELL.** A button is the cell layer; a slider
 * is the cell layer with a value that is a position; a scroller is the cell layer with a value that is a fraction.
 * THIS ONE IS TWO: a button whose press RAISES A MENU, so the control layer and the menu subsystem meet inside it.
 *
 * AND THE MENU HALF ALREADY WORKED, which is the whole reason this class is small. `NSMenu
 * -popUpMenuPositioningItem:atLocation:inView:` builds a session — it sizes the panel from the rows the view
 * measured, makes the borderless window, takes the pointer's fallback grab, repaints, announces itself and then
 * tracks until it is dismissed — and `NSMenu.h` says so where the door is declared: it "already does everything a
 * session's beginning needs". WHAT WAS MISSING WAS A CONTROL THAT CALLED IT. This is the first caller.
 *
 * **A PICK COMES BACK THROUGH THE ITEM'S OWN TARGET/ACTION, WHICH IS WHY `-setMenu:` RE-POINTS EVERY ITEM.** The
 * menu's tracking loop ends a session by sending the PICKED ITEM's action to the PICKED ITEM's target, with the
 * item as the argument (see `-performActionForItemAtIndex:`). So a popup button that wants to know which row was
 * chosen has to be that target: `-setMenu:` walks the items and points each one at this cell's `-itemSelected:`,
 * which is what Apple's does and is the only wiring in this class that is not a forward. Everything a caller reads
 * afterwards — the selected item, the title the button wears, the index — is derived from that one message.
 *
 * A MENU IS TYPED `id` HERE FOR THE REASON `NSCell`'s is: this header does not include `NSMenu.h`, and a file that
 * includes a BUTTON CELL should not have to carry a framework's menu inventory to say so. The one place it costs
 * anything is `-itemArray`, whose elements are menu items rather than the menu — an `NSArray` of them, which needs
 * no type at all.
 */
#ifndef APPKIT_NSPOPUPBUTTONCELL_H
#define APPKIT_NSPOPUPBUTTONCELL_H

#import <AppKit/NSButtonCell.h>

NS_ASSUME_NONNULL_BEGIN

/* **WHERE THE ARROW SITS, WHICH IS THE ONE THING ABOUT THIS CONTROL'S FACE THAT HAS TWO ANSWERS.** At the BOTTOM it
 * sits at the right edge of the button, which is the shape every popup button has and the one this tier draws; at
 * the CENTRE it sits in the middle and the title moves out of its way, which is what a TEXT STYLE control wants —
 * the mockup's own gallery draws one of each (`Argentum Mockup.png`: the `B / I / U` segmented track, and the gear
 * with its `▼`). Both are declared and both are honoured, because the difference is one measurement.
 *
 * THE NUMBERS ARE APPLE'S, and they are the wrong way round for a reason worth stating: `AtBottom` is 0, so a cell's
 * zeroing `-init` lands on the shape a caller who says nothing means. */
typedef enum {
	NSPopUpArrowAtBottom = 0,
	NSPopUpArrowAtCenter = 1
} NSPopUpArrowPosition;

@interface NSPopUpButtonCell : NSButtonCell
{
	/* **THERE IS NO `_menu` HERE: THE MENU IS THE FIELD THIS CLASS INHERITS**, and what this class changes is HOW
	 * THAT FIELD IS KEPT. `NSCell`'s `menu` is NOT retained and says why — "a menu outlives the cell that may raise
	 * it", which is true of the CONTEXT menu that field was added for, since a view's menu belongs to the view. A
	 * POPUP BUTTON'S MENU IS THE BUTTON'S OWN: a caller who builds one inline and hands it over has nothing left to
	 * keep it alive with, so `-setMenu:` here RETAINS the new one and releases the old, and `-dealloc` releases what
	 * is left. That is Apple's rule for this class and the opposite of its ancestor's. */
	BOOL _pullsDown;
	NSRectEdge _preferredEdge;
	NSPopUpArrowPosition _arrowPosition;
	/* **THE SELECTION IS AN INDEX, AND THE ITEM IS THE TRUTH.** Apple keeps the selection in the ITEMS' `-state` and
	 * this tier keeps the index of the same fact — one number that has to be kept in step with one `-state`, which is
	 * `-synchronizeTitleAndSelectedItem`'s whole job. It is -1 for "nothing chosen", which is also what a menu-less
	 * button answers, and that is why it is an `NSInteger` and not a count of anything. */
	NSInteger _selectedIndex;
}

/* **THE INITIALISER, WHICH IS APPLE'S AND TAKES THE ONE FACT THE INHERITED ONE CANNOT.** A popup button is a pull-
 * down or it is not, and the difference is visible before any menu is set: a pull-down's first item is its TITLE and
 * is never a choice, so choosing anything under it leaves the title alone. `NSButtonCell`'s `-initTextCell:` is the
 * other way in and means `pullsDown:NO`, which is what a caller who wants a menu of choices wants. */
- (instancetype)initTextCell:(nullable NSString *)stringValue pullsDown:(BOOL)pullDown;

/* THE MENU, WHICH IS THE CELL'S WHOLE SUBJECT. Setting one RE-POINTS EVERY ITEM at this cell — see the note at the
 * top — which is why this is a door with work in it rather than a stored pointer. */
/* **SPELLED AS A METHOD PAIR AND NOT AS A PROPERTY, WHICH IS THE HONEST FORM OF WHAT THIS CLASS DOES.** `NSCell`
 * declares `menu` as `assign`; this class RETAINS it. A property redeclared with `retain` is a compiler warning and,
 * worse, a header saying two things at once — so the pair is written out and the divergence is stated here, where a
 * reader meets it. */
- (nullable id)menu;
- (void)setMenu:(nullable id)aMenu;
@property BOOL pullsDown;
- (void)setPullsDown:(BOOL)flag;
@property NSRectEdge preferredEdge;
- (void)setPreferredEdge:(NSRectEdge)edge;
@property NSPopUpArrowPosition arrowPosition;
- (void)setArrowPosition:(NSPopUpArrowPosition)position;

/* ---- WHAT IS IN THE MENU, WHICH IS ALL THE MENU'S OWN ARITHMETIC --------------------------------- */

/* EVERY ONE OF THESE IS A FORWARD, and they are declared here because Apple declares them on this class: a caller
 * holding a popup button's CELL should not have to reach through it to the menu for a count or a title. The four
 * verbs that CHANGE the menu (`-addItemWithTitle:`, `-removeItemAtIndex:`, `-removeAllItems`, and the inserts) go
 * through `-setMenu:`'s re-pointing on their way out, so an item added to a live button is wired the moment it
 * exists — which is the bug this pair of doors exists to not have. */
- (NSInteger)numberOfItems;
- (nullable id)itemAtIndex:(NSInteger)index;
- (nullable NSArray *)itemArray;
- (nullable id)lastItem;
- (nullable NSString *)itemTitleAtIndex:(NSInteger)index;
- (NSInteger)indexOfItem:(nullable id)item;
- (NSInteger)indexOfItemWithTitle:(NSString *)title;
- (NSInteger)indexOfItemWithTag:(NSInteger)tag;
- (nullable id)itemWithTitle:(NSString *)title;
- (nullable id)itemWithTag:(NSInteger)tag;

/* AND THE FOUR THAT WRITE. `-addItemWithTitle:` is Apple's convenience over the menu's own
 * `-addItemWithTitle:action:keyEquivalent:` with the action and the key blank, because a popup's items are chosen
 * with the pointer and carry no key equivalents of their own. */
- (void)addItemWithTitle:(NSString *)title;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeAllItems;

/* ---- WHAT IS CHOSEN, WHICH IS WHERE THE TITLE COMES FROM ------------------------------------------ */

/* **THE SELECTION IS ONE FACT WITH THREE SPELLINGS, AND ALL THREE WRITE THE SAME ONE.** An index, an item, and the
 * title the button therefore wears: `-selectItemAtIndex:` is the only one that moves anything, and the other two
 * find an index and call it. `-synchronizeTitleAndSelectedItem` is the odd one out — it goes the OTHER way, reading
 * the items' own `-state` back into the index — and it exists because a caller who sets an item's state directly
 * (which is a legitimate thing to do: it is how a menu of radio-like choices is built) has told the cell about the
 * selection in the only vocabulary the MENU has. */
- (nullable id)selectedItem;
- (void)setSelectedItem:(nullable id)item;
- (NSInteger)indexOfSelectedItem;
- (void)selectItemAtIndex:(NSInteger)index;
- (void)selectItemWithTitle:(NSString *)title;
- (void)selectItemWithTag:(NSInteger)tag;
- (nullable NSString *)titleOfSelectedItem;
- (void)synchronizeTitleAndSelectedItem;

/* ---- RAISING IT, WHICH IS THE ONE DOOR THAT IS NOT A FORWARD ------------------------------------- */

/* **THE PRESS, IN TWO HALVES BECAUSE THAT IS HOW A CELL AND A CONTROL SPLIT.** The cell owns what happens — begin
 * the session under its own frame, take the pick, put the highlight up and down — and `NSPopUpButton -mouseDown:`
 * is one line that hands it a frame and a view. `-dismissPopUp` is the other half of the pair: it ends a session
 * that this cell did NOT open, which is what a caller driving a menu itself needs, and it is a forward to
 * `-cancelTracking`.
 *
 * THE SESSION BLOCKS WHILE THE APPLICATION IS RUNNING, because that is what a menu does; with no run loop it
 * returns at once with the session up, which is what makes any of this testable offscreen (see `NSMenu`'s note on
 * `_callerDrives`). Either way the HIGHLIGHT is this door's to put up and take down, since nothing else knows the
 * press and the session are one gesture. */
- (void)attachPopUpWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)dismissPopUp;

/* **AND THE FACE IS A FIELD'S RATHER THAN A BUTTON'S, WHICH IS WHY THIS OVERRIDE EXISTS.** `NSButtonCell` draws a
 * raised bezel — a thing you press — and `Argentum Mockup.png` draws a pop-up button as a TEXT FIELD: white, one
 * point, radius four. So the face is `NSText`'s ink through the same `NS_CELL_BEZEL_*` constants, and the bezel
 * `NSButtonCell` would have drawn is not drawn at all. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;

/* AND THE CONTENTS, WHICH ARE A LEFT-ALIGNED TITLE AND THE CHIP. `NSButtonCell` centres what it draws — a button's
 * title and picture sit in the middle of its face — and a field's text begins at its inset, so the title is drawn
 * here rather than forwarded. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;

/* **AND WHAT THE BUTTON MEASURES, WHICH IS THE OTHER HALF OF THE SAME THING.** `NSButtonCell` sizes itself to its
 * title and knows nothing about a pop-up arrow, so `-sizeToFit` on one of these handed back a frame exactly wide
 * enough for the words and the arrow was then drawn ON TOP of the last letter. The sample's own button is 47 points
 * wide for a 15-point glyph — it hugs its contents AND its arrow — and this is the door that makes that true here.
 * The zone added is the same fraction the arrow is drawn in, so the measurement and the ink cannot drift apart. */
- (NSSize)cellSizeForBounds:(NSRect)aRect;

/* **THE PICK, WHICH IS THE ONE MESSAGE EVERY ITEM IN THE MENU IS POINTED AT.** The menu sends it with the item as
 * the argument, and what it does is the whole of this class's behaviour: move the selection, put the item's title on
 * the button, and forward the CELL's own action to the CELL's own target so the caller hears about it. It is public
 * because Apple's is — a caller may raise a popup by hand and send this — and because a probe that wants to prove
 * the wiring has to be able to send what the menu sends. */
- (void)itemSelected:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPOPUPBUTTONCELL_H */
