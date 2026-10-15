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
 * **THE ONE THING THAT SHAPES THIS FILE IS A CLASS THIS TIER DOES NOT HAVE.** In Apple's AppKit an `NSComboBoxCell`
 * is an `NSTextFieldCell`, and THAT is where its editing comes from: the base class holds the string, the selection
 * and the field editor's protocol, and the combo box adds a list and a chip to them. This tier has neither
 * `NSTextFieldCell` nor `NSTextField` — its `NSText` is a VIEW that holds a string and edits its own single line (see
 * that header for why the tier stopped there) — so there is no field CELL for this one to derive from, and the
 * nearest base that exists is `NSActionCell`: the same base, two steps up Apple's own chain.
 *
 * **AND THAT IS WHY EDITING IS THE ROW THIS SLICE LEAVES OPEN, WHICH IS STATED HERE RATHER THAN LEFT TO BE FOUND.**
 * A person cannot type into this control yet. What this cell does is DRAW ITS FIELD, hold a LIST of objects and a
 * SELECTION, and answer what is chosen — which is the whole of what the sample's gallery shows, since a gallery row
 * is a still picture of a closed control. Making it editable means giving the cell a string, a selection and a
 * keyboard path, and that is the slice that `NSTextFieldCell` would have handed over for free. `-isEditable` and its
 * setter are ANSWERED AND STORED AND OBEY NOTHING, in the shape `NSText`'s own `-isRichText` records for a flag whose
 * machinery is not here yet.
 */
#ifndef APPKIT_NSCOMBOBOXCELL_H
#define APPKIT_NSCOMBOBOXCELL_H

#import <AppKit/NSActionCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSComboBoxCell : NSActionCell
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
	/* APPLE'S TWO SHAPE DOORS. `-_numberOfVisibleItems` is how tall the list should be when it opens, and it is
	 * STORED AND ANSWERED here for the same reason the editable flag is: the list does not open yet. */
	NSInteger _numberOfVisibleItems;
	BOOL _completes;
	BOOL _usesDataSource;
	/* **AND `-_editable` IS NOT HERE BECAUSE `NSCell` ALREADY HAS IT**, along with the `-isEditable` and
	 * `-setEditable:` pair that answers it. This class adds nothing to that flag yet, so it inherits both rather than
	 * shadowing them with a second copy that would have to be kept in step — which is the same reason the two doors
	 * are not redeclared below. What Apple's `NSComboBoxCell` does to that flag (it decides whether a person may type)
	 * is the machinery this slice leaves open, stated at the top of this file. */
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
/* AND `-isEditable` / `-setEditable:` ARE INHERITED FROM `NSCell` rather than redeclared: this class does not change
 * what they do, so a caller reads the base's answer and there is one implementation of it. */

/* ---- THE INK ---------------------------------------------------------------------------------------- */

/* **THE INK THAT CLEARS THIS CELL'S FACE, IN THE SAME THREE ANSWERS THE POP-UP GIVES.** A disabled box wears the
 * era's dimmed grey, a box whose face has taken the accent wears white, and a box at rest or under the pointer wears
 * `+controlTextColor`. It is declared here because a subclass that draws beside a title needs the same answer the
 * title got — `NSPopUpButtonCell`'s own arrow is that first caller — and it is REACHED rather than shared because the
 * two cells have no common ancestor that knows what a face is: `NSButtonCell` declares its own, and this class is not
 * a button. The rule is three lines and is spelled twice; hoisting it to a base the two agree on is a tidy-up worth
 * making when a THIRD cell needs it, and not before. */
- (nullable id)cg_inkColor;

/* **AND THE FACE IS A FIELD'S RATHER THAN A BEZEL'S, EXACTLY AS THE POP-UP'S IS.** `NSActionCell` draws nothing at
 * all, so what this override contributes is the field: the same `NS_CELL_BEZEL_*` constants, the same four states,
 * and the same greys as the control beside it. A combo box and a pop-up drawn from two sets of numbers would be the
 * pair the sample draws together disagreeing about their own border. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;

/* **AND WHAT THE BOX MEASURES, WHICH IS THE CHIP'S ZONE PLUS THE MARGIN ITS OWN TITLE BEGINS AT.** The pop-up's
 * version of this door explains both halves; this one is the same arithmetic because the two controls are the same
 * field, and it is written rather than inherited because the two cells share no ancestor that measures a chip. */
- (NSSize)cellSizeForBounds:(NSRect)aRect;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOMBOBOXCELL_H */
