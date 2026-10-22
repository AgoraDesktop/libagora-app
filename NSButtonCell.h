/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
 * TWENTY PROPERTIES ON THIS CLASS AND THE ONES THAT CARRY A VALUE ARE HERE — `alternateImage`, `attributedTitle`,
 * `attributedAlternateTitle`, `imageScaling`, `keyEquivalentFont` — and the ones that do not are named rather than
 * declared. `keyEquivalentFont` WAS owed on the ground that no font class existed; `NSFont` is here now, so the
 * property is declared, stored, released and answered, AND NOTHING DRAWS WITH IT YET, which is a fact about the
 * drawing half and is stated instead of implied.
 */
#ifndef APPKIT_NSBUTTONCELL_H
#define APPKIT_NSBUTTONCELL_H

#import <AppKit/NSActionCell.h>

@class NSEvent;

NS_ASSUME_NONNULL_BEGIN

/* **THE TWO ENUMS A BUTTON'S FACE IS DRAWN FROM — APPLE'S OWN, WITH THE ERA'S NUMBERS.** They are declared HERE
 * rather than on `NSCell` because a cell that is not a button has no button type: this is the class that knows it is
 * a button, so this is the class the vocabulary belongs to. THE DRAWING BELOW BRANCHES ON `-buttonType` FIRST and on
 * `-bezelStyle` second, which is Apple's precedence: a switch and a radio are drawn as an indicator and a label
 * whatever bezel they carry, and everything else is drawn as a bezel with its contents centred in it. */
typedef enum {
	NSMomentaryLightButton = 0,
	NSPushOnPushOffButton = 1,
	NSToggleButton = 2,
	NSSwitchButton = 3,
	NSRadioButton = 4,
	NSMomentaryChangeButton = 5,
	NSOnOffButton = 6,
	NSMomentaryPushInButton = 7,
	NSMomentaryPushButton = 8,
	NSAcceleratorButton = 9,
	NSMultiLevelAcceleratorButton = 10
} NSButtonType;

/* **AND HOW THAT BEZEL IS SHADED, WHICH IS THE ONE GRADIENT THIS TIER HAS.** The era's five members: no shading at
 * all, and four named by the shape the shading suggests — CONCAVE is a face pressed IN (dark at the top, light at the
 * bottom) and CONVEX a face bulging OUT toward the light above it (light at the top, dark at the bottom), each in a
 * WEAK and a STRONG depth. It is declared here for the same reason the two enums above are: a cell that is not a
 * button has no bezel to shade. */
typedef enum {
	NSGradientNone = 0,
	NSGradientConcaveWeak = 1,
	NSGradientConcaveStrong = 2,
	NSGradientConvexWeak = 3,
	NSGradientConvexStrong = 4
} NSGradientType;

typedef enum {
	NSRoundedBezelStyle = 1,
	NSRegularSquareBezelStyle = 2,
	NSThickSquareBezelStyle = 3,
	NSThickerSquareBezelStyle = 4,
	NSDisclosureBezelStyle = 5,
	NSShadowlessSquareBezelStyle = 6,
	NSCircularBezelStyle = 7,
	NSTexturedSquareBezelStyle = 8,
	NSHelpButtonBezelStyle = 9,
	NSSmallSquareBezelStyle = 10,
	NSTexturedRoundedBezelStyle = 11,
	NSRoundRectBezelStyle = 12,
	NSRecessedBezelStyle = 13,
	NSRoundedDisclosureBezelStyle = 14,
	NSInlineBezelStyle = 15
} NSBezelStyle;

@interface NSButtonCell : NSActionCell <NSSecureCoding>
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
	/* AND THE TWO PIECES OF STATE THE DRAWING SLICE ADDS, both plain values whose zero is the wrong answer for one
	 * of them: a fresh button cell is a MOMENTARY LIGHT BUTTON (`NSMomentaryLightButton`, 0 — zero is right) with a
	 * ROUNDED BEZEL (`NSRoundedBezelStyle`, 1 — zero is NOT a bezel style at all, which is why `-init` says it out
	 * loud, the fifth default in this family Objective-C's zeroing would get wrong). */
	NSButtonType _buttonType;
	NSBezelStyle _bezelStyle;
	/* **AND THE REST OF A BUTTON'S FACE: THE PICTURES AND THE ATTRIBUTED STRINGS, WHICH THE FIRST SLICE LEFT OWED
	 * BECAUSE IT DREW NOTHING.** Three of them are OWNED — an image is retained (this tree's rule) and the two
	 * attributed strings are COPIES, like their plain counterparts — and the fourth, the key equivalent's font, is
	 * retained for the same reason `NSCell -font` is. `_imageScaling` is how a picture meets its rectangle; the two
	 * periodic floats are the delay and interval a repeating button uses; and `_maxAcceleratorLevel` is the depth a
	 * multi-level accelerator answers, which is a value the button owns and nothing here reads. */
	NSImage *_alternateImage;		/* RETAINED */
	NSAttributedString *_attributedTitle;	/* RETAINED (a copy) */
	NSAttributedString *_attributedAlternateTitle;	/* RETAINED (a copy) */
	id _keyEquivalentFont;			/* RETAINED */
	NSImageScaling _imageScaling;
	float _periodicDelay;
	float _periodicInterval;
	NSInteger _maxAcceleratorLevel;
	/* **AND THE TWO PIECES THE SWEEP ADDS, both of which are the SECOND of a pair the class already had**: the index
	 * into `_alternateTitle` of the character its mnemonic marks (`NSNotFound` when there is none — the same spelling
	 * and the same reason `NSCell`'s own `_mnemonicLocation` gives), and the bezel's shading. The mnemonic index is an
	 * INDEX INTO ITS TITLE, so `-setAlternateTitle:` has to clear it for exactly the reason the title's is cleared. */
	NSUInteger _alternateMnemonicLocation;
	NSGradientType _gradientType;
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

/* **WHAT KIND OF BUTTON THIS IS, AND HOW ITS FACE IS BUILT.** Two enums, two properties, and neither needs anything
 * this class has not got: a button type decides whether the face is an indicator and a label (a switch, a radio) or a
 * bezel with contents (`everything else`), and a bezel style decides the shape of that bezel. */
@property NSButtonType buttonType;
- (void)setButtonType:(NSButtonType)aType;
@property NSBezelStyle bezelStyle;
- (void)setBezelStyle:(NSBezelStyle)style;

/* **THE PICTURE THAT REPLACES THE OTHER ONE WHILE THE BUTTON IS DOWN**, which is how a button changes its whole look
 * on a press without changing its state; and the SCALING that decides how a picture meets the rectangle it is given. */
@property (nullable, retain) NSImage *alternateImage;
- (void)setAlternateImage:(nullable NSImage *)anImage;
@property NSImageScaling imageScaling;
- (void)setImageScaling:(NSImageScaling)scaling;

/* **AND THE TWO ATTRIBUTED STRINGS, WHICH WIN OVER THE PLAIN ONES WHEN THEY ARE SET.** Apple declares these on the
 * CELL and on the BUTTON, and the cell's answer is "the attributed string if there is one, the plain title
 * otherwise" — which is why `-drawInteriorWithFrame:inView:` below asks for the attributed form FIRST. */
@property (nullable, copy) NSAttributedString *attributedTitle;
- (void)setAttributedTitle:(nullable NSAttributedString *)aString;
@property (nullable, copy) NSAttributedString *attributedAlternateTitle;
- (void)setAttributedAlternateTitle:(nullable NSAttributedString *)aString;

/* THE FONT A KEY EQUIVALENT IS DRAWN IN, which is a button's own and not the title's. Typed `id` for the reason
 * every cross-class door in this family is: the header does not include `NSFont`. */
@property (nullable, retain) id keyEquivalentFont;
- (void)setKeyEquivalentFont:(nullable id)font;

/* **AND THE ERA'S TWO-ARGUMENT FORM OF THE SAME DOOR, WHICH NAMES THE FONT INSTEAD OF HANDING ONE OVER.** It is
 * spelled `-setKeyEquivalentFont:size:` and the first argument is a FAMILY NAME (`nil` means the system font), which
 * is what makes it the 10.2 door rather than a second setter for the object above: it is for a caller that has a
 * name and a size from a plist and no `NSFont` in hand. */
- (void)setKeyEquivalentFont:(nullable NSString *)fontName size:(CGFloat)fontSize;

/* **THE ALTERNATE TITLE'S OWN MNEMONIC, WHICH IS THE PAIR `NSCell` ALREADY HAS ONE TITLE OVER.** `&` marks the
 * character that follows, the mark is stripped out of the alternate title, and `-alternateMnemonic` answers that
 * character — an EMPTY STRING when there is none, which is the same answer `-mnemonic` gives and the same reading of
 * "a string or nil" as the primary pair. The location is an index into the ALTERNATE title and `NSNotFound` means
 * none, so a caller can set it directly the way `-setMnemonicLocation:` allows on the primary. */
- (nullable NSString *)alternateMnemonic;
- (NSUInteger)alternateMnemonicLocation;
- (void)setAlternateMnemonicLocation:(NSUInteger)location;
- (void)setAlternateTitleWithMnemonic:(nullable NSString *)stringWithAmpersand;

/* **AND THE BEZEL'S SHADING, WHICH THE FACE BELOW READS.** The flag round-trips and -drawBezelWithFrame:inView:
 * paints it: a convex face is light at the top and dark at the bottom, a concave one the other way round, and the
 * STRONG pair is twice the WEAK pair's alpha. `NSGradientNone` is the default and paints the flat face this cell has
 * always drawn, so a button nobody configures is unchanged. */
- (NSGradientType)gradientType;
- (void)setGradientType:(NSGradientType)gradientType;

/* **AND THE PERIODIC PAIR A REPEATING BUTTON USES, AND ONE VALUE NOTHING HERE READS.** The delay and the interval
 * are the two the CELL's own `-getPeriodicDelay:interval:` answers by name (0.2/0.025); a BUTTON's are 0.4/0.075, and
 * this pair is the button's. `-maxAcceleratorLevel` is the depth a multi-level accelerator button answers — stored so
 * a caller can read it back, and read by nothing, which is stated rather than implied. */
- (void)setPeriodicDelay:(float)delay interval:(float)interval;
- (void)getPeriodicDelay:(nullable float *)delay interval:(nullable float *)interval;
@property NSInteger maxAcceleratorLevel;
- (void)setMaxAcceleratorLevel:(NSInteger)level;

/* **AND THE INK — THE DOORS `NSCell` SPLITS SO THAT THIS CLASS CAN OVERRIDE THEM.** `-drawWithFrame:inView:` is
 * the whole face; `-drawInteriorWithFrame:inView:` paints what is ON it, and is overridden here only because a button
 * lays an image and a title out against each other by `-imagePosition` rather than centring each one, which is what
 * the cell below does. The two rect doors are overridden for the same reason: a switch's title begins to the RIGHT of
 * its indicator rather than in the middle of the cell.
 *
 * **AND THE THREE PIECES APPLE LETS A SUBCLASS REPLACE ONE AT A TIME.** `-drawWithFrame:inView:` is the two calls
 * below it: the FACE (`-drawBezelWithFrame:inView:` — the bezel, or a switch's or radio's indicator) and then the
 * CONTENTS (`-drawInteriorWithFrame:inView:`, which is `-drawImage:withFrame:inView:` and `-drawTitle:withFrame:inView:`
 * with the rects its own layout computed). The split is not decoration: it is the seam a subclass with its own face
 * overrides, and it is why the two content doors are given FINISHED rects — the layout is the interior's, so a
 * subclass that replaces only the words does not have to re-derive where the picture goes. And because each content
 * door is HANDED the picture or the title it draws rather than reading the cell's state, the alternate-title decision
 * is made once, in the interior, and handed down — a subclass overriding one door cannot disagree with the layout
 * about which of the two it was given. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawBezelWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawImage:(nullable NSImage *)image withFrame:(NSRect)frame inView:(nullable id)controlView;
- (void)drawTitle:(nullable NSAttributedString *)title withFrame:(NSRect)frame inView:(nullable id)controlView;

/* **AND THE POINTER'S TWO DOORS, WHICH THIS CELL ANSWERS RATHER THAN THE VIEW.** A control's tracking area already
 * tells the CELL where the pointer is through `NSCell -cg_setMouseInside:`; these are the era's names for the same
 * fact, and they are what `-showsBorderOnlyWhileMouseInside` above is a statement about. */
- (void)mouseEntered:(nullable NSEvent *)event;
- (void)mouseExited:(nullable NSEvent *)event;
/* **THE INK A BUTTON'S CONTENTS ARE DRAWN IN, WHICH IS ONE QUESTION WITH TWO READERS.** The interior asks it for the
 * title and the image; a SUBCLASS whose face takes the same states asks it too rather than keeping a second copy of
 * the rule — `NSPopUpButtonCell` draws its own title, and a title that inverted while its face did not is exactly what
 * a second copy of this would cost. It is typed `id` where Apple would say `NSColor` for the reason every cross-class
 * door in this family is: this header does not include `NSColor.h`, and a file that includes a BUTTON CELL should not
 * have to carry a colour inventory to ask what colour it draws in. */
- (id)cg_inkColor;
- (NSRect)titleRectForBounds:(NSRect)theRect;
- (NSRect)imageRectForBounds:(NSRect)theRect;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBUTTONCELL_H */
