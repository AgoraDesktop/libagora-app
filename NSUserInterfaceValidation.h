/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSUserInterfaceValidation.h — the two protocols an item and its validator speak.
 *
 * **THIS FILE IS SMALL BECAUSE THE MECHANISM IS.** Apple's `NSUserInterfaceValidation.h` declares one protocol for
 * the thing being validated (`-action` and `-tag`) and one for the object that decides (`-validateUserInterfaceItem:`),
 * and AppKit's menu and toolbar items are the two standard validated objects. This tree shipped the menu half
 * informally on `NSMenu.h` because `-validateMenuItem:` was the only door it had; the toolbar is the second caller,
 * so the era's own header arrives with it rather than a third private protocol being invented for one item class.
 *
 * **IT IS A PROTOCOL FILE AND NOT A CLASS, AND THAT IS WHY IT ADDS NO MACHINERY.** A validator is whatever object a
 * target/action pair resolves to; this header only gives the question a name. The toolbar's `-validate` asks the
 * specific protocol first (`validateToolbarItem:`) and falls back to the generic door here, which is Apple's own
 * order and the reason a standard text view can enable a toolbar item without knowing what a toolbar is.
 *
 * Written from `NSUserInterfaceValidation.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSUSERINTERFACEVALIDATION_H
#define APPKIT_NSUSERINTERFACEVALIDATION_H

#import <Foundation/NSObject.h>

@protocol NSValidatedUserInterfaceItem
- (SEL)action;
- (NSInteger)tag;
@end

@protocol NSUserInterfaceValidations
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;
@end

#endif /* APPKIT_NSUSERINTERFACEVALIDATION_H */
