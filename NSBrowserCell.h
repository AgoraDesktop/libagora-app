/*
 * NSBrowserCell.h — the cell a browser's rows draw.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE BROWSER'S CELL IS A TEXT-FIELD CELL WITH TWO BROWSER FACTS.** A row has a picture and a title like any cell,
 * and it is a LEAF (nothing opens to its right) or a BRANCH, and LOADED when its column has been read. The drawing is
 * the one this tree's sidebar uses: the picture in a sixteen-point box, the title inset beside it.
 *
 * The class is written from `NSBrowserCell.h` in the MacOSX10.6 SDK; the later `-setImage:`/`-image` pair is
 * inherited from `NSCell` here, exactly as it is in Apple's header.
 */
#ifndef APPKIT_NSBROWSERCELL_H
#define APPKIT_NSBROWSERCELL_H

#import <AppKit/NSTextFieldCell.h>

@class NSColor;
@class NSImage;
@class NSView;

NS_ASSUME_NONNULL_BEGIN

@interface NSBrowserCell : NSTextFieldCell <NSSecureCoding>
{
	BOOL _leaf;
	BOOL _loaded;
	/* **AND THE PICTURE A HIGHLIGHTED ROW SHOWS INSTEAD OF ITS OWN**, which is `NSButtonCell`'s alternate-image idea in a
	 * browser's vocabulary: a white glyph for a selected row. RETAINED, and released in `-dealloc` — the one thing this
	 * slice adds that owns anything. */
	NSImage *_alternateImage;
}
- (BOOL)isLeaf;
- (void)setLeaf:(BOOL)flag;
- (BOOL)isLoaded;
- (void)setLoaded:(BOOL)flag;
- (void)reset;

/* **AND THE FOUR DOORS A BROWSER'S ROW NEEDS THAT A TEXT CELL HAS NOT GOT.** `-alternateImage:` is what a SELECTED row
 * shows in place of its own picture (a white glyph on the accent chip); `+branchImage` and `+highlightedBranchImage` are
 * the CLASS doors for the mark drawn at a BRANCH's trailing edge — the chevron that says "there is a column to the
 * right" — one for a plain row and one for a selected one; and `-highlightColorInView:` is the colour a row is
 * highlighted WITH, asked of the cell because a cell is what knows whether it is in a source list.
 *
 * THE TWO CLASS IMAGES ARE DRAWN RATHER THAN SHIPPED. This tier has no artwork for them, and a mark whose shape is
 * arithmetic needs no font, no resource and no registry — the same rule the System menu's hamburger and the checkbox's
 * checkmark follow. They are ten points square and they point RIGHT, because a branch opens the column to its right. */
- (nullable NSImage *)alternateImage;
- (void)setAlternateImage:(nullable NSImage *)anImage;
+ (NSImage *)branchImage;
+ (NSImage *)highlightedBranchImage;
- (NSColor *)highlightColorInView:(nullable NSView *)controlView;

/* **AND `-set`, WHICH IS THE ERA'S ONE-WORD SHORTHAND FOR "THIS ROW IS SELECTED".** Apple declares it here rather than
 * on `NSCell` (10.6's `NSCell.h` has no `-set`), and the answer is `NSOnState` plus the highlight — the two facts a
 * selected row is, in the order a cell's own drawing reads them. */
- (void)set;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBROWSERCELL_H */
