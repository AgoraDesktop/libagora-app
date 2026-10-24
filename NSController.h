/*
 * NSController.h — the common ancestor of AppKit's controllers: the editing bookkeeping, and nothing else.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THIS CLASS IS THE PART EVERY CONTROLLER SHARES, WHICH IS EDITING AND ITS END.** A controller is what a view
 * registers with while the user is changing something: `-objectDidBeginEditing:` is the registration,
 * `-objectDidEndEditing:` the withdrawal, `-isEditing` the question, and the three commit doors run over whatever is
 * registered. `NSObjectController` (and through it `NSArrayController`) inherits this file's whole surface and adds
 * content and selection; nothing here knows what a content object is.
 *
 * **THE EDITORS ARE NOT RETAINED, WHICH IS APPLE'S RULE AND THIS TIER'S DELIBERATE CHOICE.** The controller holds the
 * addresses (boxed in `NSValue`s) and nothing else: an editor is owned by the view or window that is editing, and a
 * controller that retained it would keep a field editor — and through it a window — alive after the editing ended.
 * The consequence is stated rather than hidden: an editor that dies without `-objectDidEndEditing:` leaves a dangling
 * address, and the next commit messages it. The pairing is the caller's contract, exactly as it is for a KVO
 * observation.
 *
 * **A COMMIT WALKS A SNAPSHOT AND SKIPS WHAT HAS ALREADY WITHDRAWN.** Committing editor A may end A's editing (and
 * even start a different edit), so the walk is over a copy of the registration list, and each editor is asked only
 * while it is STILL registered. Without that, one commit could message an editor the previous commit had already
 * finished with — the same use-after-free the non-retaining rule makes possible, arrived at from inside this file.
 *
 * **THE DELEGATE CALLBACK IS A THREE-ARGUMENT SEND AND THIS TIER CAN MAKE IT.** Apple's
 * `-commitEditingWithDelegate:didCommitSelector:contextInfo:` sends the delegate `(editor, didCommit, contextInfo)`;
 * the send goes through `objc_msgSend` cast to that shape, which is what `NSKeyValueBinding`'s default already does
 * for the no-editor case. A nil delegate, or a nil selector, is a silent no-op rather than an exception — the door
 * has nothing to report to and the commit still happened.
 */
#ifndef APPKIT_NSCONTROLLER_H
#define APPKIT_NSCONTROLLER_H

#import <Foundation/NSArray.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;

@interface NSController : NSObject
{
	/* RETAINED: `NSValue` boxes over the editors. The boxes are owned; the objects inside them are NOT retained,
	 * per the header block. Registration order is kept, because it is the order a commit walks. */
	NSMutableArray *_editors;
}

/* **THE QUESTION THE THREE COMMIT DOORS ARE ABOUT.** YES while at least one editor is registered. */
- (BOOL)isEditing;

/* THE REGISTRATION PAIR. Registering the same editor twice is one registration — a view that begins editing again
 * before it ended the first time must not be committed twice. Registering nil does nothing. */
- (void)objectDidBeginEditing:(id)editor;
- (void)objectDidEndEditing:(id)editor;

/* **THE COMMIT DOORS.** `-commitEditing` asks each registered editor, in registration order, and answers NO if any
 * one of them refused; it answers YES when there are none. `-discardEditing` asks each to discard and reports
 * nothing. The delegate form runs the same commit and then sends the delegate's selector once, with THIS controller,
 * the result, and the context pointer. */
- (BOOL)commitEditing;
- (void)discardEditing;
- (void)commitEditingWithDelegate:(nullable id)delegate
	       didCommitSelector:(nullable SEL)didCommitSelector
		     contextInfo:(nullable void *)contextInfo;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCONTROLLER_H */
