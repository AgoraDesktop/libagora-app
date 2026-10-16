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

NS_ASSUME_NONNULL_BEGIN

@interface NSComboBoxCell : NSTextFieldCell
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
/* AND `-isEditable` / `-setEditable:` ARE INHERITED FROM `NSCell` rather than redeclared: this class does not change
 * what they do, so a caller reads the base's answer and there is one implementation of it. */

/* ---- THE INK ---------------------------------------------------------------------------------------- */

/* **THE INK THAT CLEARS THIS CELL'S FACE, WHICH IS THE ONE THING ABOUT THE FACE THIS CLASS CHANGES.** The base's rule
 * is three answers — a colour a caller set, the era's dimmed grey when disabled, the control's text colour otherwise —
 * and a combo box's field can take the ACCENT, which is a fourth: white. Overriding the INK rather than the drawing is
 * what makes the string and the chip agree, because `NSTextFieldCell -drawInteriorWithFrame:` inks the words through
 * this door and `-cg_drawChipInFrame:` inks the triangle white for the same reason. */
- (nullable id)cg_inkColor;

/* **AND THE FACE IS INHERITED; ONLY ITS FILL IS THIS CONTROL'S.** The border, the radius and the margin come from
 * `NSTextFieldCell`, so a combo box and the field beside it cannot disagree about where their border is — and a
 * control's field answers the pointer and the session, which is the one thing a fill has to say. */
- (nullable NSColor *)cg_fieldFillColor;
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

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOMBOBOXCELL_H */
