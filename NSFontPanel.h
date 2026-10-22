/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSFontPanel.h — THE SHARED FONT PANEL: A FAMILY LIST, A SIZE ROW, AND THE MANAGER IT TALKS TO.
 *
 * **THE PANEL CHOOSES A FONT; THE MANAGER DOES THE CHANGING.** A click in the family list changes the panel's own font
 * and then asks `NSFontManager -modifyFontViaPanel:` to send `-changeFont:` to whatever the manager's target is; the
 * target calls back through `-convertFont:` and the manager applies the panel's choice. So this class owns the
 * SELECTION and the FACE, and nothing about how a font becomes another font.
 *
 * **THE FACE IS TWO LISTS AND ONE BAND.** A family list (every family the manager enumerates, with the panel's own
 * family ringed), a row of size chips (9, 10, 11, 12, 14, 18, 24, 36), and the caller's accessory view in a reserved
 * band at the foot — the same shape the colour panel's face has, for the same reason: a panel is a small window whose
 * content a caller extends.
 *
 * `-panelConvertFont:` is the pure conversion: it takes a font and answers the panel's family at the panel's size, which
 * is what a `-changeFont:` target can use without going through the manager's recorded action. `-setPanelFont:isMultiple:`
 * is the programmatic set and sends nothing, which is Apple's split between "the panel now shows this" and "a person
 * chose this".
 *
 * WHAT THIS CLASS DOES NOT DO, at the door: there is no size FIELD (the chips are the sizes a person can pick), no
 * style/face column (the family's regular member is chosen, and a caller wanting a face uses the manager's conversions),
 * and the era's "styles panel" is not here — `NSFontManager -orderFrontStylesPanel:` refuses by name.
 *
 * Written from `NSFontPanel.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSFONTPANEL_H
#define APPKIT_NSFONTPANEL_H

#import <AppKit/NSPanel.h>

@class NSFont;
@class NSView;

NS_ASSUME_NONNULL_BEGIN

@interface NSFontPanel : NSPanel
{
	NSFont *_panelFont;		/* RETAINED */
	BOOL _multiple;
	BOOL _enabled;
	NSView *_accessoryView;		/* RETAINED */
	NSArray *_families;		/* RETAINED: the manager's enumeration, reloaded on demand */
	NSInteger _selectedFamily;
	id _panelView;			/* RETAINED: the private content view */
	id _listScrollView;		/* RETAINED: the family list's scroller */
	id _listView;			/* RETAINED: its document view */
}

/* THE SINGLETON, AND THE FACTORY HOOK `NSFontManager +setFontPanelFactory:` REACHES. There is no `+setFontPanelFactory:`
 * here in Apple's header — the manager owns that door — so this one is the seam between them and says so. */
+ (NSFontPanel *)sharedFontPanel;
+ (BOOL)sharedFontPanelExists;
+ (void)setSharedPanelFactory:(nullable Class)factory;

/* THE SELECTION: the font the panel shows, and whether it stands for a multiple selection. */
- (void)setPanelFont:(NSFont *)fontObj isMultiple:(BOOL)flag;
- (nullable NSFont *)panelFont;
- (BOOL)isMultiple;

/* **THE PURE CONVERSION**: this font in the panel's family and size. Unlike a click, it sends nothing. */
- (nullable NSFont *)panelConvertFont:(NSFont *)fontObj;

/* Re-read the family list — after a face is registered, or when the panel is first shown. */
- (void)reloadDefaultFontFamilies;

/* THE ACCESSORY VIEW AND THE ENABLE FLAG. A disabled panel draws its lists dimmed and ignores a click. */
- (void)setAccessoryView:(nullable NSView *)aView;
- (nullable NSView *)accessoryView;
- (void)setEnabled:(BOOL)flag;
- (BOOL)isEnabled;

/* **A FONT PANEL WORKS DURING A MODAL SESSION**, which is Apple's rule for every panel and the reason the door exists:
 * the alert a person is answering may be choosing a font. */
- (BOOL)worksWhenModal;

/* ============================================================================================ *
 * THE INSTRUMENT'S DOORS, NOT APPLE'S: what the face draws and where it can be clicked.          *
 * ============================================================================================ */
- (NSUInteger)cg_familyCount;
- (nullable NSString *)cg_familyAtIndex:(NSUInteger)index;
- (NSRect)cg_familyRectAtIndex:(NSUInteger)index;
- (NSInteger)cg_selectedFamilyIndex;
- (NSUInteger)cg_sizeChipCount;
- (NSRect)cg_sizeChipRectAtIndex:(NSUInteger)index;
- (CGFloat)cg_sizeChipValueAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSFONTPANEL_H */
