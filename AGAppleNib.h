/*
 * AGAppleNib — Apple's compiled nib format, translated rather than guessed.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THIS IS A TRANSLATOR, NOT A SECOND DECODER.** An Apple nib is a keyed archive whose root is `NSIBObjectData`:
 * the objects live in `NSObjectsKeys`/`NSObjectsValues`, the connections in `NSConnections`, and each object is
 * archived with APPLE'S coding keys. This tree's AppKit archives with ITS OWN keys (`frame`, `hidden`, `subviews`,
 * …), so handing Apple's bytes to `-initWithCoder:` would satisfy every `-containsValueForKey:` with NO and build
 * default-valued objects — the "wrong value" failure `NSNib.h` refuses by name. This class therefore reads the
 * archive as a DOCUMENT, maps the keys it states in the table below, and builds the objects through a coder that
 * answers with the mapped values. A class or key outside the table is NOT guessed: an unmapped CLASS refuses the
 * whole nib by name, and an unmapped KEY is left at the class's own default (which is the same rule `NSNib.h`
 * states for a newer AGNib).
 *
 * WHAT IS TRANSLATED (the model is Apple's pre-autolayout "IB.objectdata" nib, which is what the corpus fixtures
 * are): `NSWindowTemplate` → `NSWindow`; `NSView`, `NSControl`, `NSButton`, `NSTextField`, `NSSplitView`,
 * `NSCustomView`; `NSBox` (its `NSContentView`/`NSTitleCell`/`NSOffsets` and the four box properties);
 * `NSScrollView` (its `NSContentView` plus `NSsFlags`' border/presence/autohide bits) and `NSClipView` (its
 * `NSDocView` and `NScvFlags`); `NSMatrix` (the flat `NSCells` regrouped into rows, the selected slot and the two
 * sizes); `NSSlider`/`NSSliderCell` (the value range, tick marks and increment); `NSFont` (the name and size a
 * cell's `NSSupport` names); `NSColor` (white, RGB and a catalog colour's resolved fallback, mapped into this tree's
 * calibrated RGBA); `NSMenu`/`NSMenuItem` (the item tree, titles, key equivalents, actions, tags, state, mnemonics,
 * separators and submenus); `NSImageView`/`NSImageCell` and named images (`NSCustomResource` → an NSImage with a
 * name); `NSBrowser`/`NSBrowserCell`; `NSClassSwapper`; `NSTextView` (its string followed through
 * `NSTextContainer` → `NSLayoutManager` → `NSTextStorage`, plus its min/max sizes and two resizable bits); `NSCell`,
 * `NSActionCell`, `NSButtonCell`, `NSTextFieldCell`; `NSCustomObject` (the file's owner becomes
 * `NSNibFileOwner` in connections, and a top-level custom object must be a class registered with
 * `+[NSNib registerDesignClass:]`); `NSNibOutletConnector` and `NSNibControlConnector`. Geometry strings become
 * `NSValue`s, `NSvFlags`/`NSCellFlags`/`NSCellFlags2` become the properties this tree archives separately, and
 * `NSSuperview`/`NSWindow`/`NSNextResponder`/`NSControlView` are DROPPED — they are live-graph state, which is
 * this tree's existing nib rule.
 *
 * **WHAT IS NOT TRANSLATED IS REFUSED BY NAME.** Toolbars, autolayout constraints and bindings are the next slices; a
 * nib that contains one is refused with the class that stopped it rather than loaded into a window that is missing a
 * piece. A text view's private `NSSharedData` (typing attributes and selection) is left to defaults and named in the
 * ledger; the text system's container, layout manager and storage are followed for the STRING and built fresh by the
 * view's own initialiser. A `DIRECT` `NSImage` (one carrying representations rather than a resource name) has no
 * translated record either, because this tree's NSImage codes a name and not image data. A key that this table does
 * not name (an `NSMenuItem`'s `NSTarget` or state images, a formatter, a tooltip source, an NSMatrix mode flag, a
 * font's trait flags, a colour space this translator cannot read) is ignored, so the object keeps this tree's default
 * for it;
 * `+unmappedKeysForAppleNibArchive:` reports them for a tool that wants to say so.
 */

#ifndef APPKIT_AGAPPLENIB_H
#define APPKIT_AGAPPLENIB_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AGAppleNib : NSObject

/* **THE FORMAT'S FINGERPRINT, asked of an already-parsed property list.** An Apple nib is `$top` holding
 * `IB.objectdata` over a `$objects` table; both must be there. Answers NO for an AGNib (whose root is a dictionary
 * of `AGNib*` keys) and for anything else. */
+ (BOOL)isAppleNibArchive:(nullable id)plist;

/* **THE WALK, WITHOUT INSTANTIATING ANYTHING.** Answers YES when every class in the archive is one this translator
 * maps and every kept property names a translated object (or the file's owner, for a connection). When it answers
 * NO, `reason` is a sentence naming the first problem — the same answer `+[NSNib refusalReasonForArchiveData:]`
 * returns, without a window or a view ever existing. */
+ (BOOL)validateAppleNibArchive:(id)plist reason:(NSString * _Nullable * _Nullable)reason;

/* **THE INSTANTIATION.** Builds the objects, applies nothing yet, and answers the top-level objects and the
 * connection records in AGNib's shape (`+[NSNib outletConnectionFrom:to:keyPath:]` /
 * `+[NSNib actionConnectionFrom:to:action:]`), so `NSNib` applies them with the one connection pass it already has.
 * A connection end that is the file's owner is the string `NSNibFileOwner`, which that pass substitutes. */
+ (BOOL)instantiateAppleNibArchive:(id)plist
                   topLevelObjects:(NSArray * _Nullable * _Nullable)topLevelObjects
                       connections:(NSArray * _Nullable * _Nullable)connections
                            reason:(NSString * _Nullable * _Nullable)reason;

/* **THE HONEST LEDGER.** Answers the Apple keys the translator dropped, sorted and deduplicated, as
 * `"Class.key"` strings — a tool can then say "this file also asks for X" instead of implying fidelity it does not
 * have. Answers an empty array for an archive it cannot read. */
+ (NSArray *)unmappedKeysForAppleNibArchive:(nullable id)plist;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_AGAPPLENIB_H */
