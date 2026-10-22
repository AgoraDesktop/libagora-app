/*
 * NSComboBoxCell.h — THE OTHER FIELD WITH A CHIP IN IT, AND THE ONE TRIANGLE THAT TELLS THEM APART.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS CELL DRAWS THE SAME FIELD AS `NSPopUpButtonCell` AND DIFFERS IN ONE MARK.** The sample's gallery draws the
 * two controls on adjacent rows, and it draws them as the same control twice: a one-point bordered rectangle, radius
 * four, with an accent-filled chip 20 x 20 inset five points from its right border. What differs is what is knocked
 * out of that chip, and it is MEASURABLE rather than a matter of reading: the pop-up's chip carries TWO runs of white
 * down its centre column (the sample's rows y=405..409 and y=414..418 — an up triangle above a down one) and this
 * one carries ONE (y=447..451), whose widest row is at its TOP. A single triangle with its base up and its apex
 * down.
 *
 * **AND THE MARK IS A SENTENCE ABOUT WHAT THE CONTROL DOES**, which is why it is not decoration: a pop-up chooses
 * both ways through its list — the up arrow is the previous choice and the down arrow the next — and a combo box
 * opens ONE list and leaves the choosing to a person who may also type. The doubled arrow therefore belongs to the
 * pop-up and the single one to this control, and each control's header says so where its own ink is drawn.
 *
 * **AND IT IS NOW AN `NSTextFieldCell`, WHICH IS THE CLASS THAT CLOSED THE ROW THIS HEADER USED TO RECORD.** This
 * cell began at `NSActionCell` because the tier had no field cell: the field's face was drawn here by hand, the string
 * was not held at all, and the header said in as many words that a person could not type into the control. Apple's own
 * `NSComboBoxCell` is an `NSTextFieldCell` — that is where a combo box's string, its selection and its edit session
 * come from — and now so is this one.
 *
 * **SO WHAT IS LEFT HERE IS WHAT IS ACTUALLY A COMBO BOX'S OWN.** A LIST of objects and a selection over them; the
 * CHIP and its single down triangle; the fill a control's field takes as the pointer and the session move over it; and
 * one measurement that is genuinely this control's rather than a field's — the rect the words get stops where the chip
 * begins, which is what keeps a typed string out from under it. The face, the border, the margin, the string and the
 * three doors of an edit are all inherited and are not restated below.
 */
#ifndef APPKIT_NSCOMBOBOXCELL_H
#define APPKIT_NSCOMBOBOXCELL_H

#import <AppKit/NSTextFieldCell.h>

@class NSMenu;
@class NSMenuItem;
@class NSComboBoxCell;

NS_ASSUME_NONNULL_BEGIN

/* **THE CELL'S OWN DATA SOURCE, WHICH IS A DIFFERENT PROTOCOL FROM THE VIEW'S BECAUSE THE TWO ASK ABOUT DIFFERENT
 * OBJECTS.** Apple spells the cell's pair `-numberOfItemsInComboBoxCell:` and `-comboBoxCell:objectValueForItemAtIndex:`
 * — the noun is the CELL — and the view's pair names the view. That is not duplication for its own sake: a data source
 * written for a cell can be handed to a view only if the view adapts the call, and this tier's view does exactly
 * that (see `NSComboBox`'s own protocol), so each class asks the question its own name is in.
 *
 * THE TWO OPTIONAL MEMBERS ARE THE ONES THAT MAKE THE LIST USEFUL RATHER THAN MERELY FILLED: an index for a typed
 * string, and the completion of a prefix. `-indexOfItemWithStringValue:` answers `NSNotFound` when nothing matches,
 * which is why its type is `NSUInteger` rather than `NSInteger` — Apple's own spelling, and the one this header keeps. */
@protocol NSComboBoxCellDataSource <NSObject>
@required
- (NSInteger)numberOfItemsInComboBoxCell:(NSComboBoxCell *)comboBoxCell;
- (nullable id)comboBoxCell:(NSComboBoxCell *)comboBoxCell objectValueForItemAtIndex:(NSInteger)index;
@optional
- (NSUInteger)comboBoxCell:(NSComboBoxCell *)comboBoxCell indexOfItemWithStringValue:(nullable NSString *)string;
- (nullable NSString *)comboBoxCell:(NSComboBoxCell *)comboBoxCell completedString:(nullable NSString *)uncompletedString;
@end

@interface NSComboBoxCell : NSTextFieldCell <NSSecureCoding>
{
	/* **THE LIST IS THE OBJECTS THEMSELVES, IN APPLE'S OWN VOCABULARY.** A combo box's rows are typed `id` — the
	 * docs' name for the door is `-addItemWithObjectValue:` — because a combo box may hold something other than a
	 * string and show it through `-description`; the pop-up's rows are menu ITEMS, which is a different thing wearing a
	 * similar shape. RETAINED, because a caller who builds an array inline and hands it over has nothing left to keep
	 * it alive with — the same rule, and the same reason, that `NSPopUpButtonCell` retains its menu. */
	NSMutableArray *_objectValues;	/* RETAINED */
	/* **AND THE SELECTION IS AN INDEX, WHICH IS THIS CLASS'S ONE PIECE OF ARITHMETIC.** Apple's `NSComboBoxCell`
	 * keeps the selected OBJECT and derives the rest, and a combo box — unlike a pop-up — has no menu items whose
	 * `-state` could be the truth, so there is nothing to be in step with and the index is the fact rather than a
	 * cache of one. `-1` is "nothing chosen", which is also what an empty box answers, and it is why this is an
	 * `NSInteger` and not a count of anything. */
	NSInteger _selectedIndex;
	/* APPLE'S TWO SHAPE DOORS. `-_numberOfVisibleItems` is how tall the list should be when it opens. It is STORED
	 * AND ANSWERED but not yet OBEYED: the list DOES open now (see `-cg_attachListWithFrame:inView:`), and its height
	 * is not yet taken from this number — a row of its own rather than a silent approximation. */
	NSInteger _numberOfVisibleItems;
	BOOL _completes;
	BOOL _usesDataSource;
	/* **AND THE SLICE THAT MAKES THE DATA SOURCE REAL.** `_dataSource` is NOT RETAINED — Apple's rule for a data
	 * source, and this tree's rule for every delegate-shaped connection: a source that was owned by the box it feeds
	 * could never be freed while the box lives. It is consulted only when `_usesDataSource` is on, which is Apple's
	 * own split and the reason the flag exists rather than a nil check: a caller may keep a source around while asking
	 * the box to show its own items.
	 *
	 * `_itemHeight` AND `_intercellSpacing` ARE THE LIST'S SHAPE, and they are read where the list is BUILT: the rows
	 * are a menu session's in this tier, so the cell hands these two numbers to the menu (`-cg_setRowHeight:intercellSpacing:`)
	 * and the session's own paint and hit test then agree about them. ZERO IS "THE SESSION'S OWN", so a box that nobody
	 * shaped produces the list this control has always produced. `_buttonBordered` is whether the CHIP wears its plate —
	 * YES by default, which is Apple's default and the picture this class draws. */
	id _dataSource;			/* NOT RETAINED */
	CGFloat _itemHeight;
	NSSize _intercellSpacing;
	BOOL _buttonBordered;
	/* **AND `-_editable` IS NOT HERE BECAUSE `NSCell` ALREADY HAS IT**, along with the `-isEditable` and
	 * `-setEditable:` pair that answers it. This class therefore inherits both rather than shadowing them with a
	 * second copy that would have to be kept in step — the same reason the two doors are not redeclared below. WHAT
	 * THIS CLASS DOES DO IS SET IT: `-initTextCell:` turns it on, because a combo box IS a field, and the control
	 * above reads that very flag to decide whether a press opens an edit. */
}

/* **THE INITIALISER IS APPLE'S, AND IT TAKES ONE FACT RATHER THAN TWO.** A pop-up's init asks whether it pulls down,
 * because that changes what its first row means; a combo box has no such fork, so the inherited `-initTextCell:` is
 * the only way in and it is restated here only to say that the list starts empty. */
- (instancetype)initTextCell:(nullable NSString *)stringValue;

/* ---- THE LIST, WHICH IS PLAIN OBJECTS RATHER THAN MENU ITEMS -------------------------------------- */

- (NSInteger)numberOfItems;
- (void)addItemWithObjectValue:(nullable id)object;
- (void)addItemsWithObjectValues:(nullable NSArray *)objects;
- (void)insertItemWithObjectValue:(nullable id)object atIndex:(NSInteger)index;
- (void)removeAllItems;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeItemWithObjectValue:(nullable id)object;
- (nullable id)itemObjectValueAtIndex:(NSInteger)index;
- (nullable NSArray *)objectValues;
- (NSInteger)indexOfItemWithObjectValue:(nullable id)object;

/* ---- WHAT IS CHOSEN, AND HOW IT IS SAID ------------------------------------------------------------ */

/* **ONE FACT WITH THREE SPELLINGS, AND ONLY ONE OF THEM WRITES.** The index is the truth; the object and the title
 * the box therefore displays are derived from it, which is why `-selectItemAtIndex:` is the only door here that moves
 * anything and the other two find an index and call it. That is the same shape `NSPopUpButtonCell` uses for its
 * selection, and it is the shape a caller who reads two of these can rely on agreeing. */
- (NSInteger)indexOfSelectedItem;
- (void)selectItemAtIndex:(NSInteger)index;
- (void)selectItemWithObjectValue:(nullable id)object;
- (nullable id)objectValueOfSelectedItem;

/* ---- THE TWO SHAPE FLAGS, WHICH ARE STORED AND OBEY NOTHING YET ------------------------------------ */

/* A list that opens has a height and a box that completes as a person types; neither exists here yet, and both are
 * answered rather than refused so that a caller who sets one can read it back. See the header's note. */
- (NSInteger)numberOfVisibleItems;
- (void)setNumberOfVisibleItems:(NSInteger)count;
- (BOOL)completes;
- (void)setCompletes:(BOOL)flag;
- (BOOL)usesDataSource;
- (void)setUsesDataSource:(BOOL)flag;

/* ---- THE DATA SOURCE, AND WHAT IT REPLACES ------------------------------------------------------- */

/* **A BOX WITH A SOURCE TAKES ITS ROWS FROM THE SOURCE RATHER THAN FROM ITS OWN ARRAY, AND EVERY ROW DOOR ASKS WHICH.**
 * `-numberOfItems`, `-itemObjectValueAtIndex:`, `-objectValues`, `-indexOfItemWithObjectValue:`, `-selectItemAtIndex:`,
 * the list it builds and the completion it offers all read through ONE pair of private doors, so a data source cannot
 * be honoured in three places and forgotten in a fourth. The array doors (`-addItemWithObjectValue:` and its siblings)
 * REFUSE BY NAME while the source is in use: they would write storage nothing reads, which is worse than a refusal
 * because it looks like it worked. */
- (void)setDataSource:(nullable id <NSComboBoxCellDataSource>)aSource;
- (nullable id <NSComboBoxCellDataSource>)dataSource;

/* **AND THE TWO WAYS THE OWNER OF A SOURCE SAYS "THE ROWS MOVED".** `-noteNumberOfItemsChanged` is the lighter one —
 * the count may have changed, so the selection is clamped into it and the shown value re-read; `-reloadData` is the
 * same thing said about the CONTENTS, and for this class it is the same act because nothing is cached: the rows are
 * read from the source on demand. Both are real doors rather than stored bits, and the difference between them is
 * stated where they are implemented. */
- (void)reloadData;
- (void)noteNumberOfItemsChanged;

/* **AND THE COMPLETION OF A TYPED PREFIX, WHICH IS WHAT `-completes` IS THE SWITCH FOR.** The argument is what has been
 * typed; the answer is the first row whose words begin with it, or nil when none does. With a data source that
 * answers `-comboBoxCell:completedString:` the source speaks; otherwise the rows are scanned. */
- (nullable NSString *)completedString:(nullable NSString *)uncompletedString;

/* ---- THE LIST'S SHAPE, WHICH THE SESSION NOW OBEYS ----------------------------------------------- */

/* **`-itemHeight` AND `-intercellSpacing` ARE HANDED TO THE LIST WHEN IT IS BUILT.** A combo box's list in this tier is
 * a menu session (see `-cg_attachListWithFrame:inView:`), and a menu's rows are its own height with no air between
 * them; these two numbers are how the box says otherwise. ZERO IS "THE SESSION'S OWN" on both axes — a height of 0
 * keeps `NSMenuRowHeight` and a spacing of (0, 0) leaves the rows abutting and flush — because Apple's published
 * defaults for a list window this tier does not have are not a thing to transcribe into one it does. */
- (CGFloat)itemHeight;
- (void)setItemHeight:(CGFloat)itemHeight;
- (NSSize)intercellSpacing;
- (void)setIntercellSpacing:(NSSize)aSize;

/* **AND WHETHER THE CHIP WEARS ITS PLATE.** YES by default: the accent square with the hole knocked out of it. NO
 * draws the TRIANGLE ALONE, in the field's ink, which is the era's borderless-button look and is measurable in pixels. */
- (BOOL)isButtonBordered;
- (void)setButtonBordered:(BOOL)flag;

/* **AND THE ONE SHAPE DOOR THE SESSION HAS NOT GOT: A SCROLLER.** A list taller than its space needs a bar and a
 * scroll offset, and this tier's session has neither — `NSMenu` clamps a menu to the screen and draws no bar. So the
 * flag is REFUSED BY NAME when set, and the two scroll doors below are refusals too: a list with no offset has nothing
 * to scroll, and a "scroll to this row" door that silently did nothing would be the worst of both. */
- (BOOL)hasVerticalScroller;
- (void)setHasVerticalScroller:(BOOL)flag;
- (void)scrollItemAtIndexToTop:(NSInteger)index;
- (void)scrollItemAtIndexToVisible:(NSInteger)index;

/* **AND ONE LIST DOOR THAT IS REAL WITHOUT A SCROLLER.** `-deselectItemAtIndex:` clears the selection when the index
 * given is the one held, which is the only reading under which it is not `-selectItemAtIndex:` under a second name:
 * it un-chooses, and the box goes back to holding nothing. */
- (void)deselectItemAtIndex:(NSInteger)index;
/* AND `-isEditable` / `-setEditable:` ARE INHERITED FROM `NSCell` rather than redeclared: this class does not change
 * what they do, so a caller reads the base's answer and there is one implementation of it. */

/* ---- THE INK, WHICH IS THE BASE'S IN EVERY STATE ---------------------------------------------------- */

/* **AND THIS CLASS OVERRIDES NEITHER THE INK NOR THE FILL, WHICH IS A DECISION RATHER THAN AN OMISSION.** Both were
 * declared here once — the ink to put white words on an accent field, the fill to answer the accent while the list was
 * open and the prelight grey under the pointer, copying the POP-UP because the sample draws the two controls as a pair.
 * A POP-UP IS A CONTROL and a COMBO BOX IS A FIELD: a value is typed into it, and a field does not change colour
 * because a person is near it or typing in it. The IMPLEMENTATIONS went in the commit that settled that — the field is
 * white in every state — and the DECLARATIONS were left behind, so this header asked for two methods no `.m` defined
 * and the compiler said so on every build until this line removed them. What they were for is named rather than
 * silently dropped: the combo box no longer says "my list is open" by taking the accent. If that signal is wanted back
 * it is one method returning `+cg_accentColor` when `-isHighlighted`, and the LIST it belongs to is the thing that
 * should carry it.
 *
 * SO THE FACE — border, radius, margin, fill and ink — is `NSTextFieldCell`'s in every state, which is what makes a
 * combo box and the plain field beside it impossible to tell apart but for the chip. The one thing this class still
 * draws OVER that face is the chip, and the triangle knocked out of it is white because the CHIP is the accent and not
 * because the field is. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;

/* **AND THE RECT THE WORDS GET STOPS WHERE THE CHIP BEGINS.** Overridden rather than clipped because an edit session
 * is handed this same rect: a clip would stop the DRAWING of a long string at the chip while letting the EDITOR draw
 * over it, which is a field that behaves one way at rest and another while being typed into. */
- (NSRect)drawingRectForBounds:(NSRect)theRect;

/* **AND WHAT THE BOX MEASURES, WHICH IS THE CHIP'S ZONE PLUS THE MARGIN ITS OWN TITLE BEGINS AT.** The pop-up's
 * version of this door explains both halves; this one is the same arithmetic because the two controls are the same
 * field, and it is written rather than inherited because the two cells share no ancestor that measures a chip. */
- (NSSize)cellSizeForBounds:(NSRect)aRect;

/* **AND THE CHIP'S RECT IS PUBLIC BECAUSE A CONTROL HAS TO KNOW WHERE THE CHIP IS.** The press is split between the
 * two things this control does — the chip opens the list and the text begins an edit — and only the CELL knows where
 * the chip is, because the chip's size is a fraction of the field's height. */
- (NSRect)cg_chipRectInFrame:(NSRect)cellFrame;

/* ---- THE LIST ---------------------------------------------------------------------------------------- */

/* **AND THE ROWS ARE BUILT BY A DOOR OF THEIR OWN, BECAUSE THE ROWS ARE WHAT A PROBE CAN CHECK.** The session needs a
 * display — a borderless window, a traversal loop, a dismissal — and none of that is needed to ask what the list
 * CONTAINS: how many rows, what they say, which one is marked and what each one is wired to are facts about a menu that
 * has been built and never shown. It is also where the held row's mark is set, which is a fact about the list rather
 * than about the session that displays it. */
- (nullable NSMenu *)cg_buildListMenu;

/* **AND THIS IS THE DOOR A PRESS ON THE CHIP COMES THROUGH.** It builds the rows from the list this cell holds, anchors
 * them under the chip and runs the session — see the implementation for why the session is `NSMenu`'s rather than a
 * list window's own, which is the departure this control carries. */
- (void)cg_attachListWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;

/* **AND THE PICK COMES BACK THROUGH THE ITEM'S OWN TARGET/ACTION**, which is why every row this cell builds is pointed
 * at this message with its index as the receiver's tag. Public because the probe that proves the wiring has to be able
 * to send what the list sends. */
- (void)itemSelected:(nullable id)sender;

/* **AND THE ROW THE POINTER IS OVER, WHICH IS THE OTHER THING A LIST IS ASKED.** The list this cell builds is a menu, and
 * the cell is that menu's DELEGATE: `-menu:willHighlightItem:` turns a highlight change into the tag on the row, which is
 * the same index the pick carries — so the control hears "the pointer moved to row 3" and "row 3 was chosen" through one
 * vocabulary. Public because the menu sends it and a probe may too. */
- (void)menu:(nullable NSMenu *)menu willHighlightItem:(nullable NSMenuItem *)item;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOMBOBOXCELL_H */
