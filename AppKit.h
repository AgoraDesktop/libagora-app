/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * AppKit.h — the umbrella.
 *
 * A consumer writes `#import <AppKit/AppKit.h>` and gets the whole surface, the way it writes
 * `#import <Foundation/Foundation.h>` for the layer underneath. Without this file the only way to use the AppKit
 * from outside this repository is to name a dozen headers by hand and to discover the rest by grep, which is not a
 * public interface — it is a directory listing.
 *
 * **EVERY HEADER THIS COMPONENT INSTALLS IS EITHER NAMED HERE OR NAMED AS INTERNAL, AND `tests/umbrella.m` IS THE
 * CENSUS THAT SAYS SO.** `CMakeLists.txt` installs `*.h` with a glob, so a new header becomes part of the installed
 * surface the moment it exists; a list that drifts silently is the failure mode this file would otherwise have, and
 * it is a failure a program cannot see until it cannot compile. The test compares the two sets on every build and
 * fails with the header that is in neither list, so adding a class means classifying it — one line, in this file or
 * in the test's list of internals.
 *
 * **THE INTERNAL ONES ARE ABSENT ON PURPOSE.** `*_internal.h` carries a class's own workings (the layout solver's
 * rows, the toolbar's item database, the image rep's caches) and the `AG*` headers are this tier's own machinery:
 * the Apple-nib translator, the chrome theme, the input methods, the icon catalogue, the XPM reader. They are
 * installed by the same glob — an "include what the tree builds" rule that keeps a sibling component's build
 * working — but they are not API, and a program that imports one is depending on a detail this tier may change
 * without saying so.
 *
 * **THE ORDER IS A READING ORDER, NOT A DEPENDENCY ONE.** Every header here imports what it needs (the tree's rule
 * for its own headers), so a consumer may import any one of them alone; the sections below exist so that a person
 * looking for a class has somewhere to look other than the alphabet.
 *
 * What is NOT in this tier is not hidden: `AppKitRefusal.h` is where a class that refuses a door says why, and the
 * refusals are the honest description of the surface's edges (see `COCOA-10.11-SURFACE-PLAN.md` in the workspace
 * repository for the audit that produces them).
 */
#ifndef APPKIT_APPKIT_H
#define APPKIT_APPKIT_H

/* THE ROOT'S VOCABULARY, AND WHAT THIS TIER REFUSES BY NAME */
#import <AppKit/AppKitRefusal.h>
#import <AppKit/NSErrors.h>
#import <AppKit/NSUserInterfaceValidation.h>
#import <AppKit/NSAccessibility.h>
#import <AppKit/NSKeyValueBinding.h>
#import <AppKit/NSAnimation.h>

/* GRAPHICS, COLOUR, FONTS AND IMAGES */
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSShadow.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColorList.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageRep.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSCachedImageRep.h>
#import <AppKit/NSCIImageRep.h>
#import <AppKit/NSCustomImageRep.h>
#import <AppKit/NSEPSImageRep.h>
#import <AppKit/NSPDFImageRep.h>
#import <AppKit/NSPICTImageRep.h>
#import <AppKit/NSImageCell.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontDescriptor.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSGlyphInfo.h>
#import <AppKit/NSStringDrawing.h>

/* RESPONDERS, EVENTS, MENUS AND THE PASTEBOARD */
#import <AppKit/NSResponder.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSSound.h>
#import <AppKit/NSPasteboardItem.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSMenuItemCell.h>
#import <AppKit/NSMenuView.h>

/* VIEWS AND CONTROLS */
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSActionCell.h>
#import <AppKit/NSBox.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSScrollerCell.h>
#import <AppKit/NSSplitView.h>
#import <AppKit/NSTabView.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSColorWell.h>
#import <AppKit/NSComboBox.h>
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSDatePicker.h>
#import <AppKit/NSForm.h>
#import <AppKit/NSFormCell.h>
#import <AppKit/NSLevelIndicator.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSPathCell.h>
#import <AppKit/NSPathComponentCell.h>
#import <AppKit/NSPathControl.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSRuleEditor.h>
#import <AppKit/NSPredicateEditor.h>
#import <AppKit/NSPredicateEditorRowTemplate.h>
#import <AppKit/NSSearchField.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSSecureTextField.h>
#import <AppKit/NSSecureTextFieldCell.h>
#import <AppKit/NSSegmentedControl.h>
#import <AppKit/NSSegmentedCell.h>
#import <AppKit/NSSlider.h>
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSStepper.h>
#import <AppKit/NSStepperCell.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSTokenField.h>
#import <AppKit/NSTokenFieldCell.h>
#import <AppKit/NSDrawer.h>

/* THE TEXT SYSTEM */
#import <AppKit/NSText.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextInputClient.h>
#import <AppKit/NSTextInputContext.h>
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSTextBlock.h>
#import <AppKit/NSTextList.h>
#import <AppKit/NSTextTable.h>
#import <AppKit/NSTextTab.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSLayoutSolver.h>
#import <AppKit/NSRulerView.h>

/* WINDOWS, CONTROLLERS AND DOCUMENTS */
#import <AppKit/NSWindow.h>
#import <AppKit/NSWindowController.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSViewController.h>
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSPersistentDocument.h>
#import <AppKit/NSController.h>
#import <AppKit/NSObjectController.h>
#import <AppKit/NSArrayController.h>
#import <AppKit/NSDictionaryController.h>
#import <AppKit/NSTreeController.h>
#import <AppKit/NSUserDefaultsController.h>

/* TABLES, OUTLINES, BROWSERS AND COLLECTIONS */
#import <AppKit/NSTableView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderCell.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSTreeNode.h>
#import <AppKit/NSBrowser.h>
#import <AppKit/NSBrowserCell.h>
#import <AppKit/NSCollectionView.h>
#import <AppKit/NSCollectionViewItem.h>

/* LAYOUT */
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSLayoutAnchor.h>

/* NIB, CONNECTIONS AND THE BUNDLE */
#import <AppKit/NSNib.h>
#import <AppKit/NSNibConnector.h>
#import <AppKit/NSNibDeclarations.h>
#import <AppKit/NSNibSource.h>
#import <AppKit/NSBundleAdditions.h>

/* PANELS, PRINTING AND SYSTEM SERVICES */
#import <AppKit/NSAlert.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSPageLayout.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSPrintPanel.h>
#import <AppKit/NSPrinter.h>
#import <AppKit/NSFontPanel.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSColorPicker.h>
#import <AppKit/NSSpellChecker.h>
#import <AppKit/NSWorkspace.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSDockTile.h>
#import <AppKit/NSDockMenu.h>
#import <AppKit/NSStatusBar.h>
#import <AppKit/NSStatusItem.h>
#import <AppKit/NSOpenGL.h>

/* TOOLBARS */
#import <AppKit/NSToolbar.h>
#import <AppKit/NSToolbarItem.h>
#import <AppKit/NSToolbarItemGroup.h>

/* THE APPLICATION */
#import <AppKit/NSApplication.h>

/* THIS TREE'S OWN CLASSES THAT AN APPLICATION MAY USE. `AGImageSourceRep` is the one a viewer needs: every format
 * CoreGraphics' `CGImageSource` decodes, as a representation `NSImage` can hold. */
#import <AppKit/AGImageSourceRep.h>

#endif /* APPKIT_APPKIT_H */
