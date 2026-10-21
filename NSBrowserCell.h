/*
 * NSBrowserCell.h — the cell a browser's rows draw.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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

NS_ASSUME_NONNULL_BEGIN

@interface NSBrowserCell : NSTextFieldCell <NSSecureCoding>
{
	BOOL _leaf;
	BOOL _loaded;
}
- (BOOL)isLeaf;
- (void)setLeaf:(BOOL)flag;
- (BOOL)isLoaded;
- (void)setLoaded:(BOOL)flag;
- (void)reset;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBROWSERCELL_H */
