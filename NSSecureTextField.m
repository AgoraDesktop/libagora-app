/*
 * NSSecureTextField — the cell, installed.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
#import "NSSecureTextField.h"
#import "NSSecureTextFieldCell.h"
#import "NSCell.h"

@implementation NSSecureTextField

- (instancetype)initWithFrame:(NSRect)frameRect
{
	NSSecureTextFieldCell *cell = [[NSSecureTextFieldCell alloc] init];

	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* **THE CELL, AND WHAT A FIELD'S CELL MUST ALREADY BE.** `NSTextField`'s initialiser made a plain field cell and
		 * measured the frame from it; this replaces it with the secure one, which answers every question the plain one did
		 * and draws bullets for the string. */
		[self setCell:cell];
		[cell setEditable:YES];
	}
	[cell release];
	return self;
}

@end
