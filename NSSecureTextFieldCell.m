/*
 * NSSecureTextFieldCell — bullets where the string was.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * One override, in the door the base class draws and measures through: `-cg_contentText` answers a string of bullets as long
 * as the value. Nothing else in this file — the face, the border, the session — is a field's, and a secure field is a field.
 */
#import "NSSecureTextFieldCell.h"
#import "NSCell.h"

/* THE BULLET: U+2022, one per character of the value. */
#define AG_BULLET "\u2022"

@implementation NSSecureTextFieldCell

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		/* **YES, WHICH IS THE DIFFERENCE BETWEEN A SECURE FIELD AND A LEAK.** See the header. */
		_echosBullets = YES;
	}
	return self;
}

- (id)copy
{
	NSSecureTextFieldCell *copy = [super copy];

	copy->_echosBullets = _echosBullets;
	return copy;
}

- (BOOL)echosBullets
{
	return _echosBullets;
}

- (void)setEchosBullets:(BOOL)flag
{
	_echosBullets = flag ? YES : NO;
}

/* **THE ONE PLACE THE SUBSTITUTION LIVES.** `-cg_contentText` is what the base draws and what the base measures, so
 * answering bullets here makes the two agree by construction — a longer password IS wider, and its caret sits where its
 * bullets are. A string of the same LENGTH in UTF-16 units keeps the caret arithmetic honest for astral characters too. */
- (NSString *)cg_contentText
{
	NSString *text = [super cg_contentText];
	NSMutableString *bullets;
	NSUInteger i;

	if (!_echosBullets || text == nil || [text length] == 0) {
		return text;
	}
	bullets = [NSMutableString stringWithCapacity:[text length]];
	for (i = 0; i < [text length]; i++) {
		[bullets appendString:@AG_BULLET];
	}
	return bullets;
}

@end
