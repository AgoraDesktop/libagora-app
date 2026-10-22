/*
 * NSSecureTextFieldCell.h — A FIELD CELL THAT SHOWS BULLETS INSTEAD OF THE STRING.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE VALUE IS THE STRING; THE INK IS BULLETS.** A password field holds what was typed and shows a dot per character, and
 * this tier has one place where a field's displayed text is decided — `-cg_contentText`, which the base class's drawing AND
 * its measurement both read. So the substitution is one override, and the field measures its bullets exactly as it measures
 * any other text: a two-character password and a fifteen-character one are different widths because the DRAWING and the
 * MEASURING agree.
 *
 * **`-echosBullets` IS THE ERA'S FLAG, AND IT DEFAULTS TO YES**, which is what makes an `NSSecureTextField` secure the
 * moment it exists. Setting it NO shows the string, which is the "reveal password" state a person reaches for.
 *
 * **THE BULLET IS U+2022**, the era's own character for it, so a password drawn here looks like a password drawn next door.
 */
#ifndef APPKIT_NSSECURETEXTFIELDCELL_H
#define APPKIT_NSSECURETEXTFIELDCELL_H

#import <AppKit/NSTextFieldCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSSecureTextFieldCell : NSTextFieldCell
{
	BOOL _echosBullets;
}

/* YES by default: a secure cell that showed its string until asked not to would be a password field leaking its password. */
- (BOOL)echosBullets;
- (void)setEchosBullets:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSECURETEXTFIELDCELL_H */
