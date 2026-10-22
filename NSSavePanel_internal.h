/*
 * NSSavePanel_internal.h — the save panel's own doors, shared by it and the open panel.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The public header has the era's doors; these are the ones the two classes use on each other: the builder, the
 * listing, the accept path, the finish path and the two deprecated-sheet wrappers. They are not Apple's and are not in
 * `NSSavePanel.h` because no caller outside the pair needs them.
 */
#ifndef APPKIT_NSSAVEPANEL_INTERNAL_H
#define APPKIT_NSSAVEPANEL_INTERNAL_H

#import "NSSavePanel.h"

@interface NSSavePanel (AGInternal)

- (void)cg_buildWithSize:(NSSize)size;
- (void)cg_reloadEntries;
- (void)cg_navigateToURL:(nullable NSURL *)url;
- (void)cg_selectionDidChange;
- (BOOL)cg_accept;
- (BOOL)cg_validateURL:(NSURL *)url;
- (void)cg_finishWithCode:(NSInteger)code;
- (void)cg_sheetDidEnd:(nullable NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(nullable void *)contextInfo;
- (void)cg_callCompletion:(NSInteger)code;
- (void)cg_retainSession;
- (void)cg_updateLabels;
- (NSInteger)cg_entryCount;
- (nullable NSString *)cg_entryNameAtIndex:(NSInteger)index;
- (BOOL)cg_entryIsDirectoryAtIndex:(NSInteger)index;
- (nullable NSString *)cg_displayNameAtIndex:(NSInteger)index;
- (nullable NSURL *)cg_urlForName:(nullable NSString *)name;
- (void)cg_appendURLForEntryAtIndex:(NSInteger)index to:(NSMutableArray *)urls;
- (void)cg_goUp:(nullable id)sender;
- (void)cg_newFolder:(nullable id)sender;
- (void)cg_tableDoubleClicked:(nullable id)sender;
- (void)cg_toggleExtension:(nullable id)sender;

@end

#endif /* APPKIT_NSSAVEPANEL_INTERNAL_H */
