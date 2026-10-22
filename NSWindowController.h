/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

/* NSWindowController.h — a controller for a window.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 *
 * THE PAIR TO `NSViewController`, and the same 10.6 ground: the era's surface for this class is 12 members and the
 * rest of its ledger rows are post-10.6, struck WITH THE CLASS rather than left as work this tier owes.
 *
 * **AND ONE SIGNATURE IS DELIBERATELY WIDER THAN APPLE'S.** `-setDocument:` takes an `NSDocument *` there, and
 * `NSDocument` is a class this tier does not ship — writing `@class NSDocument;` to name the parameter is the trap
 * this tree has RECORDED and has already been walked into once this stage, because the ledger's rule is that a
 * class is declared when its NAME is declared and a forward is a declaration. So the parameter is `id`: it accepts
 * an `NSDocument` exactly as Apple's does, it claims no class, and the deviation is stated here rather than
 * discovered by whoever finds the row shipped.
 */
#ifndef APPKIT_NSWINDOWCONTROLLER_H
#define APPKIT_NSWINDOWCONTROLLER_H

#import <AppKit/NSResponder.h>
#import <Foundation/NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class NSWindow;

@interface NSWindowController : NSResponder <NSSecureCoding>
{
	NSWindow *_window;			/* RETAINED: a controller owns the window it manages */
	NSString *_windowNibName;		/* copied */
	NSString *_windowNibPath;		/* copied */
	NSString *_frameAutosaveName;		/* copied, and handed to the window when it arrives */
	id _owner;				/* NOT retained — the nib's owner belongs to the caller */
	id _document;				/* NOT retained — a document owns its controllers, not the reverse */
	BOOL _shouldCascadeWindows;
	BOOL _shouldCloseDocument;
}

/* THE FOUR WAYS IN, and the two nib ones remember the name and REFUSE TO LOAD IT: `NSNib` is a class this tier
 * has not got, exactly as for `NSViewController`, and the refusal is by name in `-loadWindow` below. */
- (instancetype)initWithWindow:(nullable NSWindow *)window;
- (instancetype)initWithWindowNibName:(NSString *)windowNibName;
- (instancetype)initWithWindowNibName:(NSString *)windowNibName owner:(nullable id)owner;
- (instancetype)initWithWindowNibPath:(NSString *)windowNibPath owner:(nullable id)owner;

- (nullable NSString *)windowNibName;
- (nullable NSString *)windowNibPath;
- (nullable id)owner;

/* THE WINDOW AND ITS LOADING. `-window` LOADS ON DEMAND — Apple's implementation does — and `-loadWindow` is the
 * override point, with `-windowWillLoad` and `-windowDidLoad` around it. */
- (nullable NSWindow *)window;
- (void)setWindow:(nullable NSWindow *)window;
- (BOOL)isWindowLoaded;
- (void)loadWindow;
- (void)windowWillLoad;
- (void)windowDidLoad;
- (void)showWindow:(nullable id)sender;
- (void)close;

/* THE AUTOSAVE NAME, WHICH THE WINDOW DOES NOT GET AT THE TIME IT IS SET. Apple's own comment says the controller
 * makes sure its window gets the name "whenever it gets its window set" — so the name is STORED here and handed
 * over in `-setWindow:`, which is what happens when a window arrives after the name did. */
- (void)setWindowFrameAutosaveName:(NSString *)name;
- (nullable NSString *)windowFrameAutosaveName;

/* AND THE CASCADING FLAG. **APPLE'S HEADER DOES NOT STATE A DEFAULT FOR IT**, so this tier chose NO: the behaviour
 * it enables moves a window the caller has just been handed, and a controller that repositions a window nobody
 * asked it to move is the surprising default. */
- (void)setShouldCascadeWindows:(BOOL)flag;
- (BOOL)shouldCascadeWindows;

/* THE DOCUMENT RELATIONSHIP — see the note about the parameter's type above. */
- (nullable id)document;
- (void)setDocument:(nullable id)document;
- (void)setDocumentEdited:(BOOL)dirtyFlag;
- (void)setShouldCloseDocument:(BOOL)flag;
- (BOOL)shouldCloseDocument;
- (void)synchronizeWindowTitleWithDocumentName;
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName;
/* AND THE ONE DOOR `NSCoding` OWES THAT THIS HEADER NEVER SPELLED — the same gap as the view controller's, and
 * the same reason: a protocol conformance is not a declaration. `-initWithCoder:` is implemented here (with the
 * keys `-encodeWithCoder:` writes) and the ledger row was open because a `<NSCoding>` conformance promises
 * nothing about WHICH class answers it. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSWINDOWCONTROLLER_H */
