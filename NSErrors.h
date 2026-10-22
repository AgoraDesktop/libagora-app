/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSErrors.h — THE APPKIT'S NAMED EXCEPTIONS.
 *
 * **THIS FILE IS NEW HERE AND ITS NAME IS APPLE'S, WHICH IS THE RULE THIS PLAN WORKS UNDER: MATCH APPLE, INCLUDING WHICH
 * HEADER.** The 10.6 SDK declares `NSBadComparisonException` in `AppKit/NSErrors.h` (its line 45), and the ledger's row
 * for that name carries `AppKit/NSErrors.h` as its own source — so a tree that declared the constant somewhere else
 * would be answering a row from a file the row does not come from. §A10bl created two headers for exactly this reason
 * (`NSText.h`, `NSParagraphStyle.h`), and this is the third.
 *
 * AND CREATING A FILE IS CHEAP IN THIS LIBRARY SPECIFICALLY, WHICH IS WORTH KNOWING BEFORE THE NEXT ONE: AppKit's
 * sources are enumerated BY WILDCARD on both sides — `APPKIT_MSRCS` in mk/00-base.mk for the guest library and
 * `HOST_APPKIT_MSRCS` in mk/60-host.mk for the host one, each a `wildcard` of the AppKit source directory — so a new
 * `.m` beside this header is compiled into both without a build-list edit of any kind. And `mk/20-userland.mk` stages
 * the headers with a `cp` of the directory's `.h` files, so a new header reaches the guest the same way. §A10bl
 * recorded the header half of that; this unit is the one that leaned on the source half.
 *
 * AND THE DECLARATION'S SPELLING IS THIS TREE'S RATHER THAN APPLE'S, WHICH IS THE ONLY THING HERE THAT IS NOT A
 * TRANSCRIPTION: the SDK's line is `APPKIT_EXTERN NSString *NSBadComparisonException;`, and THIS TREE HAS NO
 * `APPKIT_EXTERN` — it is the SDK's export macro. Foundation's own named exceptions are spelled
 * `NSString *const NSInvalidArgumentException = @"…";` in `NSException.h`/`.m`, and this constant follows the tree for
 * the same reason a caller would never see the difference: the NAME, the TYPE and the FILE are Apple's.
 */
#ifndef APPKIT_NSERRORS_H
#define APPKIT_NSERRORS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* RAISED BY `-[NSCell compare:]` WHEN THE OTHER OBJECT IS NOT A CELL — Apple's own sentence for that door, and the only
 * raiser of this name anywhere in the AppKit. It is a STRING because that is what an exception's name is: a caller
 * catches one by comparing `-name` against this constant, which is why the value and the identifier are the same word
 * and why it is declared `NSString *const` rather than an enum. */
extern NSString *const NSBadComparisonException;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSERRORS_H */
