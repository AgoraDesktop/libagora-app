/*
 * NSSecureTextField.h — A FIELD WHOSE INK IS BULLETS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CLASS IS THE CELL, INSTALLED.** Apple declares no selectors of its own on `NSSecureTextField` — the whole surface is
 * `NSTextField`'s — so this class is one `-initWithFrame:` that makes an `NSSecureTextFieldCell` instead of a plain field
 * cell. That is also why the class is COMPLETE the moment it exists: the manifest gives it nothing to owe.
 *
 * A caller may still reach the flag through the cell (`[[field cell] setEchosBullets:NO]`), which is how Apple's own API
 * exposes it.
 */
#ifndef APPKIT_NSSECURETEXTFIELD_H
#define APPKIT_NSSECURETEXTFIELD_H

#import <AppKit/NSTextField.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSSecureTextField : NSTextField <NSSecureCoding>

/* The cell it makes is an `NSSecureTextFieldCell`, which is the whole of the class's behaviour. */
- (instancetype)initWithFrame:(NSRect)frameRect;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSECURETEXTFIELD_H */
