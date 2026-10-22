/*
 * NSTextTab.m — a location, a kind, and the options Apple names no key for.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLASS IS A VALUE, SO `-copy` IS A RETAIN** and the only arithmetic is the mapping between the type and the
 * alignment, which are the same vocabulary spelled two ways. A decimal tab has no alignment counterpart — it lines
 * numbers up on their point rather than along an edge — so its `-alignment` answers `NSNaturalTextAlignment`, which is
 * stated here rather than guessed at. A decimal stop's terminators are the LOCALE's (`+columnTerminatorsForLocale:`)
 * or its own `-options`, and `-initWithType:location:options:` is the door that pairs a TYPE with them, because the
 * alignment door cannot name a decimal.
 */
#import <AppKit/NSTextTab.h>
#import <Foundation/NSLocale.h>

/* **THE ONE OPTIONS KEY THIS TIER NAMES.** Its value is an array of the characters that end a decimal tab's column;
 * it is declared so a caller writing `-initWithTextAlignment:location:options:` has a spelling for it. */
NSString *const NSTabColumnTerminatorsAttributeName = @"NSTabColumnTerminators";

@implementation NSTextTab

/* **AND THE TERMINATORS FOR A LOCALE, WHICH ARE ITS DECIMAL SEPARATOR.** `NSLocale -decimalSeparator` reads ICU's
 * data, so this is per-locale without a table of our own; a nil locale is the current one, and a locale whose
 * separator ICU has no answer for falls back to the period rather than to an empty array. */
+ (NSArray *)columnTerminatorsForLocale:(NSLocale *)aLocale
{
	NSLocale *locale = (aLocale != nil) ? aLocale : [NSLocale currentLocale];
	NSString *separator = [locale decimalSeparator];

	return [NSArray arrayWithObject:(separator != nil) ? separator : @"."];
}

/* THE ALIGNMENT DOOR, WHICH IS APPLE'S NEWER ONE. `NSNaturalTextAlignment` and `NSJustifiedTextAlignment` have no tab
 * STOP of their own — a natural tab is a left one, and a justified one is left too because a stop is a single
 * position — so both answer `NSLeftTabStopType` and the divergence is stated. */
- (instancetype)initWithTextAlignment:(NSTextAlignment)alignment location:(CGFloat)loc
			      options:(NSDictionary *)options
{
	self = [super init];
	if (self != nil) {
		_location = loc;
		_options = [options retain];
		switch (alignment) {
		case NSRightTextAlignment:
			_tabStopType = NSRightTabStopType;
			break;
		case NSCenterTextAlignment:
			_tabStopType = NSCenterTabStopType;
			break;
		default:
			_tabStopType = NSLeftTabStopType;
			break;
		}
	}
	return self;
}

- (instancetype)initWithType:(NSTextTabType)type location:(CGFloat)loc
{
	return [self initWithType:type location:loc options:nil];
}

/* **AND THE TYPE WITH OPTIONS, WHICH IS THE PAIRING THE OTHER TWO DOORS LEAVE APART.** A decimal stop wants to carry
 * `NSTabColumnTerminatorsAttributeName`; this is where it does. */
- (instancetype)initWithType:(NSTextTabType)type location:(CGFloat)loc options:(NSDictionary *)options
{
	self = [super init];
	if (self != nil) {
		_location = loc;
		_options = [options retain];
		_tabStopType = (type <= NSDecimalTabStopType) ? type : NSLeftTabStopType;
	}
	return self;
}

- (void)dealloc
{
	[_options release];
	[super dealloc];
}

/* IMMUTABLE, SO THE COPY IS THE ORIGINAL — the answer `NSColor -copy` gives, and the reason a tab can be handed to a
 * store and trusted. */
- (id)copy
{
	return [self retain];
}

- (CGFloat)location
{
	return _location;
}

- (NSTextTabType)tabStopType
{
	return _tabStopType;
}

- (NSTextAlignment)alignment
{
	switch (_tabStopType) {
	case NSRightTabStopType:
		return NSRightTextAlignment;
	case NSCenterTabStopType:
		return NSCenterTextAlignment;
	case NSDecimalTabStopType:
		/* A DECIMAL TAB HAS NO ALIGNMENT COUNTERPART: it aligns on a character, not on an edge. */
		return NSNaturalTextAlignment;
	default:
		return NSLeftTextAlignment;
	}
}

- (NSDictionary *)options
{
	return _options;
}

@end
