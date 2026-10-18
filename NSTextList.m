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
	[super dealloc];
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
- (NSString *)markerForItemNumber:(NSInteger)itemNum
{
	NSString *bullet = fn_bullet_for(_markerFormat);
	NSMutableString *out;

	if (bullet != nil) {
		return bullet;
	}
	out = [NSMutableString string];
	if ([_markerFormat isEqualToString:@"{decimal}"]) {
		[out appendFormat:@"%ld", (long)itemNum];
	} else if ([_markerFormat isEqualToString:@"{lower-roman}"] || [_markerFormat isEqualToString:@"{upper-roman}"]) {
		fn_append_roman(out, itemNum);
		if ([_markerFormat isEqualToString:@"{upper-roman}"]) {
			return [out uppercaseString];
		}
	} else if ([_markerFormat isEqualToString:@"{lower-alpha}"] || [_markerFormat isEqualToString:@"{lower-latin}"]) {
		fn_append_alpha(out, itemNum, NO);
	} else if ([_markerFormat isEqualToString:@"{upper-alpha}"] || [_markerFormat isEqualToString:@"{upper-latin}"]) {
		fn_append_alpha(out, itemNum, YES);
	} else if ([_markerFormat isEqualToString:@"{lower-hexadecimal}"]
		   || [_markerFormat isEqualToString:@"{upper-hexadecimal}"]) {
		BOOL uppercase = [_markerFormat isEqualToString:@"{upper-hexadecimal}"];

		[out appendFormat:(uppercase ? @"%lX" : @"%lx"),
			(unsigned long)((itemNum < 0) ? -itemNum : itemNum)];
	} else if ([_markerFormat isEqualToString:@"{octal}"]) {
		[out appendFormat:@"%lo", (unsigned long)((itemNum < 0) ? -itemNum : itemNum)];
	} else {
		/* **A FORMAT THIS TIER DOES NOT KNOW IS REFUSED BY NAME AND ANSWERED IN DECIMAL**, because a caller with a
		 * format from a newer era can act on a number and cannot act on an empty string. */
		fprintf(stderr, "APPKIT-REFUSE: -[NSTextList markerForItemNumber:] does not know the marker format `%s`, "
				"and answers in decimal\n", [_markerFormat UTF8String]);
		[out appendFormat:@"%ld", (long)itemNum];
	}
	return out;
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
