/*
 * NSTextList.m — the marker for an item number, in the formats Apple documents.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE NUMBERING IS ARITHMETIC AND IT IS THE ONLY ARITHMETIC HERE.** Four families cover the formats: positional
 * radix (decimal, hexadecimal, octal), Roman numerals, ALPHABETIC — which is BIJECTIVE base 26 rather than base 26,
 * because a list goes `…, z, aa, ab, …` and not `…, z, ba, …` — and the bullet glyphs, which ignore the number
 * entirely. Each is a small loop, and each is measured by the probe beside this file rather than asserted here.
 *
 * **AND THE VOCABULARY IS THE DOCUMENTED ONE, NOT THE HEADER'S**: 10.6's `NSTextList.h` declares no format constants,
 * so the strings below are what Apple's documentation names — `{decimal}`, `{lower-roman}`, `{upper-latin}`, `{disc}`
 * and the rest — and the table is the one place they are written. An unknown format is refused by name and answered in
 * decimal: a caller with a newer format gets a numbered marker and a message, which is more use than an empty string.
 */
#import <AppKit/NSTextList.h>
#import "NSTextList_internal.h"

#include <stdio.h>
#include <string.h>

/* THE BULLET GLYPHS, which are the formats that ignore the item number. `{hyphen}` is a hyphen and the other six are
 * the characters their names describe; they are written as escapes so the file stays ASCII and a reader can see which
 * code point is meant. */
static NSString *fn_bullet_for(NSString *format)
{
	if ([format isEqualToString:@"{disc}"]) {
		return @"\u2022";
	}
	if ([format isEqualToString:@"{circle}"]) {
		return @"\u25E6";
	}
	if ([format isEqualToString:@"{square}"]) {
		return @"\u25AA";
	}
	if ([format isEqualToString:@"{box}"]) {
		return @"\u2610";
	}
	if ([format isEqualToString:@"{check}"]) {
		return @"\u2713";
	}
	if ([format isEqualToString:@"{diamond}"]) {
		return @"\u25C6";
	}
	if ([format isEqualToString:@"{hyphen}"]) {
		return @"-";
	}
	return nil;
}

/* ROMAN, SUBTRACTIVE AS THE FORMAT IS: 4 is `iv` and 9 is `ix`, and the thousands repeat rather than bar. */
static void fn_append_roman(NSMutableString *out, NSInteger number)
{
	static const struct { NSInteger value; const char *digits; } kSteps[] = {
		{ 1000, "m" }, { 900, "cm" }, { 500, "d" }, { 400, "cd" },
		{ 100, "c" }, { 90, "xc" }, { 50, "l" }, { 40, "xl" },
		{ 10, "x" }, { 9, "ix" }, { 5, "v" }, { 4, "iv" }, { 1, "i" }
	};
	size_t k;

	if (number <= 0) {
		/* ROMAN NUMERALS HAVE NO ZERO, and a list that starts at 0 is a caller's arithmetic rather than a roman
		 * one: the marker is the numeral for the ABSOLUTE value, which is the only thing an alphabet can say. */
		number = (number < 0) ? -number : 1;
	}
	if (number > 3999) {
		/* ABOVE 3999 THE NOTATION NEEDS BARS OVER LETTERS, which no list marker uses; the thousands repeat, which
		 * is what a reader of a long list expects to see. */
		while (number > 3999) {
			[out appendString:@"m"];
			number -= 1000;
		}
	}
	for (k = 0; k < sizeof kSteps / sizeof kSteps[0]; k++) {
		while (number >= kSteps[k].value) {
			[out appendString:[NSString stringWithUTF8String:kSteps[k].digits]];
			number -= kSteps[k].value;
		}
	}
}

/* ALPHABETIC, AS BIJECTIVE BASE 26: 1 is `a`, 26 is `z`, 27 is `aa`. The loop takes a digit off the END each time,
 * which is what makes the rollover land on `aa` rather than on `ba`. */
static void fn_append_alpha(NSMutableString *out, NSInteger number, BOOL uppercase)
{
	char buffer[32];
	int used = 0;

	if (number <= 0) {
		number = (number < 0) ? -number : 1;
	}
	while (number > 0 && used < (int)sizeof buffer - 1) {
		NSInteger digit = (number - 1) % 26;

		buffer[used++] = (char)((uppercase ? 'A' : 'a') + digit);
		number = (number - 1) / 26;
	}
	while (used > 0) {
		[out appendFormat:@"%c", buffer[--used]];
	}
}

@implementation NSTextList

- (id)initWithMarkerFormat:(NSString *)format options:(NSUInteger)mask
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	if (format == nil || [format length] == 0) {
		fprintf(stderr, "APPKIT-REFUSE: -[NSTextList initWithMarkerFormat:options:] needs a format; a list with "
				"no format has no marker\n");
		[self release];
		return nil;
	}
	_markerFormat = [format copy];
	_listOptions = mask;
	_startingItemNumber = 1;
	return self;
}

- (void)dealloc
{
	[_markerFormat release];
	[_listSecondary release];
	[super dealloc];
}

/* **THE ENCLOSING LIST, WHICH IS THE PARAGRAPH STYLE'S TO SET** — see the internal header. A list retains the one
 * outside it, so a stack is a chain and a list handed to a style keeps its chain alive. */
- (void)_setEnclosingList:(NSTextList *)enclosing
{
	id held = [enclosing retain];

	[_listSecondary release];
	_listSecondary = held;
}

- (NSTextList *)_enclosingList
{
	return _listSecondary;
}

- (NSString *)markerFormat
{
	return _markerFormat;
}

- (NSUInteger)listOptions
{
	return _listOptions;
}

- (void)setStartingItemNumber:(NSInteger)itemNum
{
	_startingItemNumber = itemNum;
}

- (NSInteger)startingItemNumber
{
	return _startingItemNumber;
}

/* **AND THE MARKER**, which is the format applied to the item's number. The bullets ignore the number; everything else
 * formats it. The item number is taken as given rather than rebased on `-startingItemNumber`, because the door's
 * argument IS the item's number — the starting number is how a caller decides which number the first item has, which
 * is what a list that begins at 5 needs and what `-markerForItemNumber:` then formats. */
/* **THE MARKER BODY: THE FORMAT APPLIED TO THE NUMBER**, which is everything EXCEPT the enclosing marker. It is a
 * function rather than the first half of the method because the enclosing walk needs it too, and two copies of this
 * chain would be two chances for `1a` and `a` to disagree about what `a` is. */
static NSString *fn_marker_body(NSString *markerFormat, NSInteger itemNum)
{
	NSString *bullet = fn_bullet_for(markerFormat);
	NSMutableString *out;

	if (bullet != nil) {
		return bullet;
	}
	out = [NSMutableString string];
	if ([markerFormat isEqualToString:@"{decimal}"]) {
		[out appendFormat:@"%ld", (long)itemNum];
	} else if ([markerFormat isEqualToString:@"{lower-roman}"] || [markerFormat isEqualToString:@"{upper-roman}"]) {
		fn_append_roman(out, itemNum);
		if ([markerFormat isEqualToString:@"{upper-roman}"]) {
			return [out uppercaseString];
		}
	} else if ([markerFormat isEqualToString:@"{lower-alpha}"] || [markerFormat isEqualToString:@"{lower-latin}"]) {
		fn_append_alpha(out, itemNum, NO);
	} else if ([markerFormat isEqualToString:@"{upper-alpha}"] || [markerFormat isEqualToString:@"{upper-latin}"]) {
		fn_append_alpha(out, itemNum, YES);
	} else if ([markerFormat isEqualToString:@"{lower-hexadecimal}"]
		   || [markerFormat isEqualToString:@"{upper-hexadecimal}"]) {
		BOOL uppercase = [markerFormat isEqualToString:@"{upper-hexadecimal}"];

		[out appendFormat:(uppercase ? @"%lX" : @"%lx"), (unsigned long)((itemNum < 0) ? -itemNum : itemNum)];
	} else if ([markerFormat isEqualToString:@"{octal}"]) {
		[out appendFormat:@"%lo", (unsigned long)((itemNum < 0) ? -itemNum : itemNum)];
	} else {
		/* **A FORMAT THIS TIER DOES NOT KNOW IS REFUSED BY NAME AND ANSWERED IN DECIMAL**, because a caller with a
		 * format from a newer era can act on a number and cannot act on an empty string. */
		fprintf(stderr, "APPKIT-REFUSE: -[NSTextList markerForItemNumber:] does not know the marker format `%s`, "
				"and answers in decimal\n", [markerFormat UTF8String]);
		[out appendFormat:@"%ld", (long)itemNum];
	}
	return out;
}

/* **AND THE MARKER ITSELF, WHICH IS THE BODY OR THE BODY BEHIND ITS ENCLOSING LIST'S.** `NSTextListPrependEnclosingMarker`
 * means an item in a nested list is numbered `2a` rather than `a`, and the walk is RECURSIVE through the chain because a
 * list at the third level asks its own enclosing list, which asks its own — so three levels read `1a-` and not one
 * level's answer. There is NO SEPARATOR: Apple's documentation states none, and this tier does not invent punctuation
 * into a caller's marker; a caller who wants one puts it in the format.
 *
 * The chain is the paragraph style's (`NSTextList_internal.h`), so a list used outside a style simply has no enclosing
 * list and answers its body — which is what the outermost level should do anyway. */
- (NSString *)markerForItemNumber:(NSInteger)itemNum
{
	NSTextList *enclosing = (NSTextList *)_listSecondary;

	if ((_listOptions & NSTextListPrependEnclosingMarker) != 0 && enclosing != nil) {
		NSMutableString *nested = [NSMutableString string];
		NSString *outside = [enclosing markerForItemNumber:itemNum];

		if (outside != nil) {
			[nested appendString:outside];
		}
		[nested appendString:fn_marker_body(_markerFormat, itemNum)];
		return nested;
	}
	return fn_marker_body(_markerFormat, itemNum);
}

/* **THE ARCHIVE DOORS.** The keys are this tier's own — Apple publishes no key set for this class, and the strings are
 * named after what they carry the way `NSTrackingArea`'s are (`@"NSRect"`, `@"NSOptions"`). A DECODE WITH NO FORMAT, or
 * with an empty one, is refused through the designated initialiser, so an archive whose format key is missing cannot
 * become a list with no marker. */
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_markerFormat forKey:@"NSMarkerFormat"];
	[coder encodeInteger:(NSInteger)_listOptions forKey:@"NSListOptions"];
	[coder encodeInteger:_startingItemNumber forKey:@"NSStartingItemNumber"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	NSString *format = [coder decodeObjectForKey:@"NSMarkerFormat"];
	NSInteger options = [coder decodeIntegerForKey:@"NSListOptions"];
	NSInteger starting = [coder decodeIntegerForKey:@"NSStartingItemNumber"];
	NSTextList *list = [self initWithMarkerFormat:format options:(NSUInteger)options];

	[list setStartingItemNumber:starting];
	return list;
}

/* **`-copy` AND NOT `-copyWithZone:`, BECAUSE THIS TREE HAS NO ZONES** — `NSZone` is deliberately absent, exactly as
 * `NSColor.m` records for its own copy, so the door a caller uses is the one Cocoa spells `-copy`. The list is a value:
 * the format is immutable, so the copy shares nothing that could change under it. */
- (id)copy
{
	NSTextList *copy = [[NSTextList alloc] initWithMarkerFormat:_markerFormat options:_listOptions];

	[copy setStartingItemNumber:_startingItemNumber];
	return copy;
}

@end
