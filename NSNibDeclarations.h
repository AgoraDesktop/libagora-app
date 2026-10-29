/*
 * NSNibDeclarations.h — the two declarations an interface file needs from a class, and the reason they are
 * ATTRIBUTES rather than nothing at all.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * **AN OUTLET IS A KEY PATH AND AN ACTION IS A SELECTOR, AND A COMPILER CAN ALREADY SAY SO.**
 *
 * `NSNib.h` gives the runtime's side of the contract: an outlet connection is `-setValue:forKeyPath:` on the
 * source — so the name resolves by Key Value Coding's rules (`NSKeyValueCoding.h`: `-setRunButton:` first, then
 * the ivars `_runButton` and `runButton`) — and an action connection is `-setTarget:`/`-setAction:` with the
 * selector. Nothing in that needs a macro: a plain ivar is already a legal outlet, and a plain method is already
 * a legal action.
 *
 * WHAT THE *TOOL* NEEDS IS A DIFFERENT QUESTION, and the answer is not a registry. An interface editor has to
 * offer the names a class declares, and the runtime cannot answer: `class_copyIvarList` lists *storage*, so a
 * `delegate` looks exactly like an outlet. Clang, however, has understood these two declarations since long
 * before this tree existed — it PRE-DEFINES both macros as attributes (`iboutlet` and `ibaction`), which the AST
 * carries on the ivar, the property and the method, and which cost nothing in the binary:
 *
 *     IBOutlet NSButton *_runButton;      →  ObjCIvarDecl,        inner: IBOutletAttr
 *     @property (assign) IBOutlet id box; →  ObjCPropertyDecl,    inner: IBOutletAttr
 *     - (IBAction)go:(id)sender;          →  ObjCMethodDecl,      inner: IBActionAttr
 *
 * So this header does NOT redefine them on clang. `#ifndef` is the whole body: on clang the built-in wins and
 * the attribute reaches the AST; on a compiler without them the macros degrade to what they mean at run time —
 * nothing — and the file still compiles. A file that uses `IBOutlet` therefore says something a tool can read
 * and costs the program nothing, which is the property that makes it worth writing down.
 *
 * **AND THE EXTRACTOR IS `tools/nib-outlets`.** It runs clang with `-Xclang -ast-dump=json` and answers, per
 * class, the outlet keys and action selectors with their declared types; `--c` turns that into a table a
 * program can compile in, so an editor (or the application itself) can answer "what outlets does this class
 * have" without parsing anything at run time and without a registration call to forget.
 *
 * THE OWNERSHIP RULE AN OUTLET SHOULD FOLLOW is the connector's, not ARC's: `NSNibConnector` BORROWS both ends
 * ("the object graph owns both ends"), so an outlet is a plain ivar or an `-assign` property. A retaining outlet
 * to a view its superview already owns is redundant; a retaining outlet to the OWNER's window is the one case
 * where the file's owner genuinely owns what the nib built.
 */
#ifndef APPKIT_NSNIBDECLARATIONS_H
#define APPKIT_NSNIBDECLARATIONS_H

/* CLANG PRE-DEFINES BOTH. These guards exist so that a compiler without them still accepts the same source. */
#ifndef IBOutlet
#define IBOutlet
#endif

/* THE BUILT-IN SPELLING IS `void)__attribute__((ibaction)`, so it is written between the parentheses of a
 * method declaration: `- (IBAction)doThing:(id)sender;`. The fallback has to be the same shape. */
#ifndef IBAction
#define IBAction void
#endif

#endif /* APPKIT_NSNIBDECLARATIONS_H */
