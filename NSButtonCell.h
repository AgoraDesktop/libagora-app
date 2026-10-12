/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSButtonCell.h — THE CELL THAT KNOWS IT IS A BUTTON (stage E).
 *
 * THIS IS THE LAST LINK BEFORE `NSMenuItemCell` CAN BE RE-BASED ONTO APPLE'S OWN CHAIN: `NSCell` ->
 * `NSActionCell` -> `NSButtonCell`, and that is the class Apple puts a menu ITEM's cell under. So the deviation this
 * plan has carried since §A10ab — a menu cell standing on `NSObject` because there was no cell stack to stand on —
 * ends when this class lands, and that is what it is for.
 *
 * AND THIS FIRST SLICE IS THE PART OF A BUTTON CELL THAT IS NOT INK: the flags (transparent, a border shown only
 * while the mouse is inside, whether the image dims when the button is disabled), the pieces of a button's face that
 * are VALUES rather than drawings (an alternate title, a background colour, where the image sits, what the cell
 * highlights by and shows its state by, the sound it makes), and the key equivalent's modifier mask. APPLE PUTS
 * TWENTY PROPERTIES ON THIS CLASS AND MOST OF THE REST ARE IMAGES AND FONTS — `alternateImage`, `attributedTitle`,
 * `keyEquivalentFont` — which need the drawing half and stay OWED, row by row, in the ledger.
 */
#ifndef APPKIT_NSBUTTONCELL_H
#define APPKIT_NSBUTTONCELL_H

#import <AppKit/NSActionCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSButtonCell : NSActionCell
{
	/* THE THREE FLAGS AND THE STATE THIS SLICE ADDS. `_alternateTitle` is a COPY and is therefore the one new thing
	 * `-dealloc` has to release; `_backgroundColor` and `_sound` are bare pointers, since both outlive a cell. */
	BOOL _transparent;
	BOOL _showsBorderOnlyWhileMouseInside;
	BOOL _imageDimsWhenDisabled;
	NSString *_alternateTitle;		/* RETAINED (a copy of what was set) */
	id _backgroundColor;			/* NOT RETAINED */
	NSCellImagePosition _imagePosition_bc;
	NSInteger _highlightsBy;
	NSInteger _showsStateBy;
	NSUInteger _keyEquivalentModifierMask_bc;
	id _sound;				/* NOT RETAINED */
}

/* THE FLAGS. Each getter is spelled where Apple spells one — `-isTransparent` — and each setter is declared as well
 * as its property, which is the rule this plan has now recorded often enough to stop counting. */
@property (getter=isTransparent) BOOL transparent;
- (void)setTransparent:(BOOL)flag;
@property BOOL showsBorderOnlyWhileMouseInside;
- (void)setShowsBorderOnlyWhileMouseInside:(BOOL)flag;
@property BOOL imageDimsWhenDisabled;
- (void)setImageDimsWhenDisabled:(BOOL)flag;

/* AND A BUTTON'S FACE, MINUS THE DRAWINGS: the title it shows when it ISN'T showing its title, where its image sits
 * (typed by `NSCellImagePosition`, this family's own enum, which is why the types had to land first), what it
 * highlights by and what it shows its state by — both of which are BITFIELDS a control composes from the cell masks
 * `NSCell.h` declares — and the colour behind it.
 *
 * `backgroundColor` IS TYPED `id` WHERE APPLE TYPES `NSColor`, for the reason this plan has used twice already: the
 * class IS in this tree, but this header does not include it, and pulling it in for one parameter would make every
 * file that includes a BUTTON cell carry a colour inventory it may not use. */
@property (nullable, copy) NSString *alternateTitle;
- (void)setAlternateTitle:(nullable NSString *)aString;
@property (nullable, assign) id backgroundColor;
- (void)setBackgroundColor:(nullable id)color;
@property NSCellImagePosition imagePosition;
- (void)setImagePosition:(NSCellImagePosition)aPosition;
@property NSInteger highlightsBy;
- (void)setHighlightsBy:(NSInteger)aType;
@property NSInteger showsStateBy;
- (void)setShowsStateBy:(NSInteger)aType;

/* AND THE KEY EQUIVALENT'S MASK, which a button cell carries of its own even though its key equivalent comes from
 * the cell it inherits — the two are one answer to a caller and two fields to this class. */
@property NSUInteger keyEquivalentModifierMask;
- (void)setKeyEquivalentModifierMask:(NSUInteger)mask;

/* AND THE SOUND a button makes when it is pressed. Typed `id` for the third time and the same reason: the class that
 * would type it is not included here, and a sound is a thing a caller hands over rather than one a cell measures. */
@property (nullable, assign) id sound;
- (void)setSound:(nullable id)aSound;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBUTTONCELL_H */
