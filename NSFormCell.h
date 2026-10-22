/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSFormCell.h — THE CELL A FORM'S ENTRY IS: A LABEL AND AN EDITABLE FIELD BESIDE IT.
 *
 * **A FORM ENTRY IS TWO STRINGS IN ONE CELL.** The TITLE is the label — "Name", "Server" — drawn in its own band at
 * the leading edge in the title font, right-aligned by default so every label in a form ends at the same x. The VALUE
 * is the cell's ordinary string, drawn in the field that takes the rest of the cell's width, inside a bezel when the
 * cell is bordered or bezeled. Editing reaches the value and never the title, which is why the field editor's frame
 * comes from `-drawingRectForBounds:`: that door returns the VALUE band, and every other door in this class is
 * arithmetic about where the boundary is.
 *
 * **THE BOUNDARY IS `-titleWidth`, AND ZERO MEANS "MEASURE IT".** A cell with an explicit width divides the cell at
 * that width; a cell with zero measures its own title and leaves `NS_CELL_CONTENT_GAP` of air after it, which is what
 * a form of entries laid out without a second pass gets. `NSForm -setEntryWidth:` is the door that turns a form's
 * cells from measured to fixed in one call. `-titleWidth:` (the one with an argument) is the measurement itself,
 * published because Apple publishes it and because a caller sizing a form by hand needs the same number this class does.
 *
 * THE DEFAULTS ARE THIS TREE'S, NAMED RATHER THAN LEFT TO THE STORAGE: the title is RIGHT-aligned (every form in the
 * era reads that way and a left-aligned form is the exception a caller asks for), the title font is the bold system
 * font at the system size (a label is the emphasized half of the pair), and the title width is ZERO, meaning measured.
 * None of those three is a zero in the storage and none of them is Apple's published default either — Apple's class
 * reference does not state one — so they are written out here where a caller can find them.
 *
 * WHAT THIS CLASS DOES NOT DO: there is no crystal or rounded bezel of its own (`-bezeled`/`-bordered` draw the same
 * rounded rectangle `NSTextFieldCell` does), and a title longer than its band is CLIPPED rather than truncated with an
 * ellipsis — the field's own drawing has the truncation rule and a label does not need a second one.
 *
 * Written from `NSFormCell.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSFORMCELL_H
#define APPKIT_NSFORMCELL_H

#import <AppKit/NSActionCell.h>
#import <AppKit/NSCell.h>

@class NSAttributedString;
@class NSColor;
@class NSFont;

NS_ASSUME_NONNULL_BEGIN

@interface NSFormCell : NSActionCell <NSSecureCoding>
{
	/* THE TITLE IS `NSCell`'s (`_title`), because Apple declares `-title`/`-setTitle:` again here rather than giving
	 * the label a second home; what is NEW is everything about how it is drawn. The two placeholders are this class's
	 * own strings, RETAINED, for the same reason `NSTextFieldCell`'s are: a hint belongs to the field it is in. */
	NSFont *_titleFont;			/* RETAINED */
	CGFloat _titleWidth;			/* 0 == measure the title */
	NSTextAlignment _titleAlignment;
	NSWritingDirection _titleBaseWritingDirection;
	NSString *_placeholderString;		/* RETAINED */
	NSAttributedString *_placeholderAttributedString;	/* RETAINED */
	NSAttributedString *_attributedTitle;		/* RETAINED; overrides the plain title when set */
}

/* **THE DESIGNATED INITIALISER SETS THE VALUE, AS ITS NAME SAYS.** `-initTextCell:` is the same door
 * `NSTextFieldCell` has and means the same thing there: the string a caller passes is the cell's VALUE. A form then
 * sets the LABEL through `-setTitle:`, which is one string on one cell with two doors — the trap `NSCell`'s own
 * `-initTextCell:` taught, where storing only the title left `-stringValue` answering nil. */
- (instancetype)initTextCell:(nullable NSString *)aString;

/* THE LABEL: ITS TEXT, FONT, BAND WIDTH, ALIGNMENT AND DIRECTION. `-titleWidth` of 0 is "measure it"; the door with a
 * size argument is the measurement for a cell that size, in points, including the gap the value band starts after. */
- (nullable NSString *)title;
- (void)setTitle:(nullable NSString *)aString;
- (nullable NSFont *)titleFont;
- (void)setTitleFont:(nullable NSFont *)font;
- (CGFloat)titleWidth;
- (void)setTitleWidth:(CGFloat)width;
- (CGFloat)titleWidth:(NSSize)aSize;
- (NSTextAlignment)titleAlignment;
- (void)setTitleAlignment:(NSTextAlignment)mode;
- (NSWritingDirection)titleBaseWritingDirection;
- (void)setTitleBaseWritingDirection:(NSWritingDirection)mode;

/* **THE ATTRIBUTED FORM OF THE LABEL**, stored as itself when a caller wants attributes this class's font and colour
 * cannot express. Setting it is what `-titleFont` no longer decides for that cell; reading the plain title back gives
 * the attributed string's characters, which is the same rule `NSButtonCell` states. */
- (nullable NSAttributedString *)attributedTitle;
- (void)setAttributedTitle:(nullable NSAttributedString *)obj;

/* AND THE TITLE'S MNEMONIC, WHICH IS `NSCell`'s RULE APPLIED TO THE LABEL** — `&&` is a literal `&`, a single `&` is
 * dropped and remembered as the mnemonic's position. Declared here because Apple redeclares it on this class, and
 * forwarded because the storage is the one `NSCell` already has. */
- (void)setTitleWithMnemonic:(nullable NSString *)stringWithAmpersand;

/* THE HINT THE VALUE BAND SHOWS WHILE THE CELL IS EMPTY. */
- (nullable NSString *)placeholderString;
- (void)setPlaceholderString:(nullable NSString *)string;
- (nullable NSAttributedString *)placeholderAttributedString;
- (void)setPlaceholderAttributedString:(nullable NSAttributedString *)string;

/* **AND THE ANSWER THAT SAYS THIS CELL PAINTS ONLY ITS OWN TWO BANDS.** A form cell over a window's face leaves the
 * face visible between its label and its field, so it is not opaque; a caller that assumed otherwise would composite
 * a white rectangle over the panel. */
- (BOOL)isOpaque;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSFORMCELL_H */
