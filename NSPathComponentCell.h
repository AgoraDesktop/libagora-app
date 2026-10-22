/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSPathComponentCell.h — one component of a path bar: its picture, its title and its URL.
 *
 * **THE CELL IS A TEXT FIELD CELL WITH TWO MORE PIECES OF STATE.** The title is the inherited `stringValue`; the
 * icon and the URL are this class's. The PATH CELL owns the components and draws their background and separators;
 * this cell draws only its interior, through `-drawInteriorWithFrame:inView:`, so a path style can change the surface
 * without a component cell painting a field's bezel in the middle of it.
 *
 * The URL is the component's own prefix of the whole path, which is what a clicked path component has to hand back.
 * A file URL's components are filled in by `NSPathCell -setURL:`; a caller may also make cells by hand, set their
 * `stringValue`, `image` and `URL`, and hand them over with `-setPathComponentCells:`.
 *
 * Written from `NSPathComponentCell.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSPATHCOMPONENTCELL_H
#define APPKIT_NSPATHCOMPONENTCELL_H

#import <AppKit/NSTextFieldCell.h>

NS_ASSUME_NONNULL_BEGIN

@class NSImage;
@class NSURL;

@interface NSPathComponentCell : NSTextFieldCell <NSSecureCoding>
{
	/* THE PICTURE IS `NSCell`'S OWN `_image`; this class re-declares the pair because Apple does, and adds the URL. */
	NSURL *_url;		/* RETAINED */
}

- (nullable NSImage *)image;
- (void)setImage:(nullable NSImage *)value;
- (nullable NSURL *)URL;
- (void)setURL:(nullable NSURL *)url;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPATHCOMPONENTCELL_H */
