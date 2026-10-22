/*
 * NSOpenPanel.h — THE SAVE PANEL, ASKED A DIFFERENT QUESTION: WHAT TO OPEN, AND HOW MANY.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE BROWSER IS THE SAME ONE; THE FLAGS ARE THE CLASS.** An open panel is an `NSSavePanel` whose prompt is "Open",
 * whose title is "Open", whose name label is "Name:", and which accepts files or directories according to
 * `-canChooseFiles`/`-canChooseDirectories` and one or many according to `-allowsMultipleSelection`. `-URLs` is the whole
 * accepted set (one URL when multiple selection is off), and `-filenames` is the deprecated path spelling of it.
 *
 * **A DIRECTORY IS NAVIGATED OR CHOSEN BY THE FLAGS, NOT BY THE CLICK.** With `-canChooseDirectories` NO a double-click or
 * Open on a directory walks into it; with it YES the same press chooses the directory. That is the one behaviour the two
 * kinds of open panel have to differ in, and it is stated here rather than discovered from the button's answer.
 *
 * **`-resolvesAliases` IS A SYMLINK RESOLUTION IN THIS TIER.** The file system has symlinks; the Finder's alias records
 * are a metadata format this tree has not got, so the flag resolves symbolic links and the alias-file form is a named
 * refusal at the door that would need it.
 */
#ifndef APPKIT_NSOPENPANEL_H
#define APPKIT_NSOPENPANEL_H

#import <AppKit/NSSavePanel.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSOpenPanel : NSSavePanel

+ (NSOpenPanel *)openPanel;

/* THE RESULT: every accepted URL, or an empty array before an accept. `-URL` is the first of them. */
- (NSArray *)URLs;

- (BOOL)resolvesAliases;
- (void)setResolvesAliases:(BOOL)flag;
- (BOOL)canChooseDirectories;
- (void)setCanChooseDirectories:(BOOL)flag;
- (BOOL)allowsMultipleSelection;
- (void)setAllowsMultipleSelection:(BOOL)flag;
- (BOOL)canChooseFiles;
- (void)setCanChooseFiles:(BOOL)flag;

/* ---- THE 10.3 SPELLINGS --------------------------------------------------------------------------- */

- (NSArray *)filenames;
- (void)beginSheetForDirectory:(nullable NSString *)path file:(nullable NSString *)name types:(nullable NSArray *)fileTypes
		modalForWindow:(NSWindow *)docWindow modalDelegate:(nullable id)delegate
	       didEndSelector:(nullable SEL)didEndSelector contextInfo:(nullable void *)contextInfo;
- (void)beginForDirectory:(nullable NSString *)path file:(nullable NSString *)name types:(nullable NSArray *)fileTypes
	 modelessDelegate:(nullable id)delegate didEndSelector:(nullable SEL)didEndSelector
	      contextInfo:(nullable void *)contextInfo;
- (NSInteger)runModalForDirectory:(nullable NSString *)path file:(nullable NSString *)name
			    types:(nullable NSArray *)fileTypes;
- (NSInteger)runModalForTypes:(nullable NSArray *)fileTypes;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSOPENPANEL_H */
