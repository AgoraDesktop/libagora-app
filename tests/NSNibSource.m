/*
 * NSNibSource.m — the text parser and the compiler into the archive.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * See the header for the syntax and the schema. What is worth saying here is the shape of the two halves:
 *
 *   THE PARSER is a recursive descent over one pass of the bytes. Positions are tracked as an offset and a LINE, and
 *   every error carries the line, because a design file's mistake is a design file's mistake and "syntax error" with no
 *   line is a sentence a person cannot act on.
 *
 *   THE COMPILER is a walk of the property list the parser produced. It FAILS CLOSED: an unknown key in an object, an
 *   unknown symbolic attribute, a reference to an undeclared id, a class not on `NSNib`'s allow-list, a property the
 *   class does not have — all of them are refusals with a sentence, not silent skips. The one thing it deliberately
 *   tolerates is a property whose VALUE type the compiler cannot express: a dictionary or an array handed to a scalar
 *   property raises through KVC and is reported like any other bad property.
 */
#import "NSNibSource.h"

#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ============================================================================================
 * THE PARSER
 * ============================================================================================ */

typedef struct {
	const char *bytes;
	size_t length;
	size_t pos;
	unsigned line;
	NSString *error;
} AGSrc;

static void ag_error(AGSrc *s, NSString *format, ...)
{
	va_list args;

	if (s->error != nil) {
		return;	/* the FIRST error is the one worth reporting */
	}
	va_start(args, format);
	s->error = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
}

static BOOL ag_at_end(AGSrc *s)
{
	return s->pos >= s->length;
}

static char ag_peek(AGSrc *s)
{
	return ag_at_end(s) ? '\0' : s->bytes[s->pos];
}

static char ag_advance(AGSrc *s)
{
	char c = s->bytes[s->pos++];

	if (c == '\n') {
		s->line++;
	}
	return c;
}

/* WHITESPACE AND THE TWO COMMENT FORMS, because a design file is read by people. */
static void ag_skip(AGSrc *s)
{
	for (;;) {
		char c;

		while (!ag_at_end(s) && (ag_peek(s) == ' ' || ag_peek(s) == '\t' || ag_peek(s) == '\n' ||
					 ag_peek(s) == '\r')) {
			ag_advance(s);
		}
		if (ag_at_end(s)) {
			return;
		}
		if (ag_peek(s) == '/' && s->pos + 1 < s->length && s->bytes[s->pos + 1] == '/') {
			while (!ag_at_end(s) && ag_peek(s) != '\n') {
				ag_advance(s);
			}
			continue;
		}
		if (ag_peek(s) == '/' && s->pos + 1 < s->length && s->bytes[s->pos + 1] == '*') {
			ag_advance(s);
			ag_advance(s);
			for (;;) {
				if (ag_at_end(s)) {
					ag_error(s, @"line %u: a block comment is never closed", s->line);
					return;
				}
				c = ag_advance(s);
				if (c == '*' && !ag_at_end(s) && ag_peek(s) == '/') {
					ag_advance(s);
					break;
				}
			}
			continue;
		}
		return;
	}
}

static BOOL ag_accept(AGSrc *s, char wanted)
{
	ag_skip(s);
	if (ag_peek(s) != wanted) {
		return NO;
	}
	ag_advance(s);
	return YES;
}

static BOOL ag_expect(AGSrc *s, char wanted, const char *what)
{
	if (ag_accept(s, wanted)) {
		return YES;
	}
	ag_error(s, @"line %u: expected %s, found %s", s->line, what,
		 ag_at_end(s) ? "the end of the file" : "something else");
	return NO;
}

/* A QUOTED STRING, WITH THE FOUR ESCAPES A DESIGN FILE ACTUALLY NEEDS. */
static NSString *ag_string(AGSrc *s)
{
	NSMutableData *buffer = [[NSMutableData alloc] init];
	NSString *result;

	ag_advance(s);	/* the opening quote */
	for (;;) {
		char c;

		if (ag_at_end(s)) {
			ag_error(s, @"line %u: a quoted string is never closed", s->line);
			[buffer release];
			return nil;
		}
		c = ag_advance(s);
		if (c == '"') {
			break;
		}
		if (c == '\\') {
			if (ag_at_end(s)) {
				ag_error(s, @"line %u: a backslash ends the file", s->line);
				[buffer release];
				return nil;
			}
			c = ag_advance(s);
			switch (c) {
			case 'n': c = '\n'; break;
			case 't': c = '\t'; break;
			case 'r': c = '\r'; break;
			case '"': break;
			case '\\': break;
			default:
				ag_error(s, @"line %u: \\%c is not an escape this format has", s->line, c);
				[buffer release];
				return nil;
			}
		}
		[buffer appendBytes:&c length:1];
	}
	result = [[NSString alloc] initWithBytes:[buffer bytes]
					  length:[buffer length]
					encoding:NSUTF8StringEncoding];
	[buffer release];
	return [result autorelease];
}

static BOOL ag_is_word_char(char c)
{
	if (c == '\0' || c == ' ' || c == '\t' || c == '\n' || c == '\r') {
		return NO;
	}
	switch (c) {
	case '{': case '}': case '(': case ')': case '=': case ';': case ',': case '"':
		return NO;
	default:
		return YES;
	}
}

/* **A BARE WORD IS TYPED, WHICH IS THIS FORMAT'S ONE EXTENSION OVER APPLE'S.** An integer, a real, YES and NO become
 * numbers; everything else is a string. The check is `strtod`'s own, done on a copy, and it requires the WHOLE word to be
 * consumed — otherwise a class name like `NSView3` would become the number 3 followed by junk. */
static id ag_word(AGSrc *s)
{
	size_t start = s->pos;
	size_t length;
	char *text;
	char *end = NULL;
	NSString *string;

	while (!ag_at_end(s) && ag_is_word_char(ag_peek(s))) {
		ag_advance(s);
	}
	length = s->pos - start;
	text = (char *)malloc(length + 1);
	memcpy(text, s->bytes + start, length);
	text[length] = '\0';

	if (strcmp(text, "YES") == 0) {
		free(text);
		return [NSNumber numberWithBool:YES];
	}
	if (strcmp(text, "NO") == 0) {
		free(text);
		return [NSNumber numberWithBool:NO];
	}
	if (length > 0 && (text[0] == '-' || text[0] == '+' || (text[0] >= '0' && text[0] <= '9'))) {
		double value = strtod(text, &end);

		if (end != NULL && *end == '\0') {
			BOOL integral = (strchr(text, '.') == NULL && strchr(text, 'e') == NULL &&
					 strchr(text, 'E') == NULL);

			free(text);
			return integral
				? [NSNumber numberWithLongLong:(long long)value]
				: [NSNumber numberWithDouble:value];
		}
	}
	string = [[NSString alloc] initWithBytes:text length:length encoding:NSUTF8StringEncoding];
	free(text);
	return [string autorelease];
}

static id ag_value(AGSrc *s);

static NSDictionary *ag_dictionary(AGSrc *s)
{
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

	ag_advance(s);	/* { */
	for (;;) {
		NSString *key;
		id value;

		ag_skip(s);
		if (ag_peek(s) == '}') {
			ag_advance(s);
			break;
		}
		if (ag_at_end(s)) {
			ag_error(s, @"line %u: a dictionary is never closed", s->line);
			[dict release];
			return nil;
		}
		if (ag_peek(s) == '"') {
			key = ag_string(s);
		} else if (ag_is_word_char(ag_peek(s))) {
			key = ag_word(s);
			if (![key isKindOfClass:[NSString class]]) {
				key = [(NSNumber *)key description];
			}
		} else {
			ag_error(s, @"line %u: a dictionary needs a key here", s->line);
			[dict release];
			return nil;
		}
		if (key == nil) {
			[dict release];
			return nil;
		}
		if (!ag_expect(s, '=', "\"=\"")) {
			[dict release];
			return nil;
		}
		value = ag_value(s);
		if (value == nil) {
			[dict release];
			return nil;
		}
		[dict setObject:value forKey:key];
		if (!ag_expect(s, ';', "\";\" after a dictionary entry")) {
			[dict release];
			return nil;
		}
	}
	return [dict autorelease];
}

static NSArray *ag_array(AGSrc *s)
{
	NSMutableArray *array = [[NSMutableArray alloc] init];

	ag_advance(s);	/* ( */
	for (;;) {
		id value;

		ag_skip(s);
		if (ag_peek(s) == ')') {
			ag_advance(s);
			break;
		}
		if (ag_at_end(s)) {
			ag_error(s, @"line %u: an array is never closed", s->line);
			[array release];
			return nil;
		}
		value = ag_value(s);
		if (value == nil) {
			[array release];
			return nil;
		}
		[array addObject:value];
		/* **THE COMMA IS OPTIONAL, WHICH IS THE ONE PLACE THIS SYNTAX LEAVES APPLE'S.** An array whose values are
		 * separated by newlines is what the header's own example shows and what a person writes; requiring a comma
		 * would make the documented example invalid, and accepting both costs one `if`. */
		ag_skip(s);
		if (ag_peek(s) == ',') {
			ag_advance(s);
		}
	}
	return [array autorelease];
}

/* **A VALUE LITERAL, WHICH IS THE ONE THING A PROPERTY MAP COULD NOT SAY.** A colour, a font and an image are objects,
 * and the grammar's `properties` block holds values a person can type: so they get a literal spelling that is
 * UNAMBIGUOUS in the value position — an `@` a name and a parenthesised body:
 *
 *   textColor = @color(#ff0000);      themeColor = @color(#0a0a0aff);   tint = @color(orange);
 *   font      = @font("Helvetica Neue" 13);
 *   image     = @image(icon-run);
 *
 * The body is kept as TEXT and parsed by the compiler, because each literal's shape is the compiler's business and this
 * function's job is to find its edges. A quoted string inside the body may contain a `)`.
 */
static id ag_literal(AGSrc *s)
{
	size_t nameStart;
	size_t bodyStart;
	NSString *name;
	NSString *body;
	NSMutableData *buffer;
	BOOL quoted = NO;

	ag_advance(s);	/* the @ */
	nameStart = s->pos;
	if (!ag_is_word_char(ag_peek(s))) {
		ag_error(s, @"line %u: an @ must be followed by a literal's name", s->line);
		return nil;
	}
	while (!ag_at_end(s) && ag_is_word_char(ag_peek(s))) {
		ag_advance(s);
	}
	name = [[[NSString alloc] initWithBytes:s->bytes + nameStart
					length:s->pos - nameStart
				      encoding:NSUTF8StringEncoding] autorelease];
	if (!ag_expect(s, '(', "\"(\" after a literal's name")) {
		return nil;
	}
	bodyStart = s->pos;
	buffer = [[NSMutableData alloc] init];
	for (;;) {
		char c;

		if (ag_at_end(s)) {
			ag_error(s, @"line %u: the literal @%s is never closed", s->line, [name UTF8String]);
			[buffer release];
			return nil;
		}
		c = ag_peek(s);
		if (c == '"') {
			quoted = !quoted;
		}
		if (c == ')' && !quoted) {
			ag_advance(s);
			break;
		}
		[buffer appendBytes:&c length:1];
		ag_advance(s);
	}
	(void)bodyStart;
	body = [[[NSString alloc] initWithBytes:[buffer bytes]
					 length:[buffer length]
				       encoding:NSUTF8StringEncoding] autorelease];
	[buffer release];
	return [NSDictionary dictionaryWithObjectsAndKeys:
		name, @"$literal",
		[body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], @"$value",
		nil];
}

static id ag_value(AGSrc *s)
{
	ag_skip(s);
	if (ag_at_end(s)) {
		ag_error(s, @"line %u: a value is expected and the file ends", s->line);
		return nil;
	}
	switch (ag_peek(s)) {
	case '{':
		return ag_dictionary(s);
	case '(':
		return ag_array(s);
	case '"':
		return ag_string(s);
	case '@':
		return ag_literal(s);
	default:
		if (!ag_is_word_char(ag_peek(s)) || ag_peek(s) == ';' || ag_peek(s) == ',' ||
		    ag_peek(s) == ')' || ag_peek(s) == '}' || ag_peek(s) == '=') {
			ag_error(s, @"line %u: expected a value, found \"%c\"", s->line, ag_peek(s));
			return nil;
		}
		return ag_word(s);
	}
}

/* ============================================================================================
 * THE COMPILER
 * ============================================================================================ */

static NSLayoutAttribute ag_attribute(NSString *name, BOOL *found)
{
	static struct {
		const char *name;
		NSLayoutAttribute value;
	} table[] = {
		{ "none", NSLayoutAttributeNotAnAttribute },
		{ "left", NSLayoutAttributeLeft },
		{ "right", NSLayoutAttributeRight },
		{ "top", NSLayoutAttributeTop },
		{ "bottom", NSLayoutAttributeBottom },
		{ "leading", NSLayoutAttributeLeading },
		{ "trailing", NSLayoutAttributeTrailing },
		{ "width", NSLayoutAttributeWidth },
		{ "height", NSLayoutAttributeHeight },
		{ "centerX", NSLayoutAttributeCenterX },
		{ "centerY", NSLayoutAttributeCenterY },
		{ "lastBaseline", NSLayoutAttributeLastBaseline },
		{ "firstBaseline", NSLayoutAttributeFirstBaseline },
	};
	size_t i;

	*found = NO;
	for (i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
		if ([name isEqualToString:[NSString stringWithUTF8String:table[i].name]]) {
			*found = YES;
			return table[i].value;
		}
	}
	return NSLayoutAttributeNotAnAttribute;
}

static NSLayoutRelation ag_relation(NSString *name, BOOL *found)
{
	*found = YES;
	if (name == nil || [name isEqualToString:@"equal"]) {
		return NSLayoutRelationEqual;
	}
	if ([name isEqualToString:@"lessThanOrEqual"]) {
		return NSLayoutRelationLessThanOrEqual;
	}
	if ([name isEqualToString:@"greaterThanOrEqual"]) {
		return NSLayoutRelationGreaterThanOrEqual;
	}
	*found = NO;
	return NSLayoutRelationEqual;
}

/* A GEOMETRY PROPERTY IS FOUR REALS IN A STRING, which is how a design file states a frame without inventing a second
 * number syntax: `frame = "0 0 320 240";`. The scan is `NSScanner`'s and it requires the whole string to be consumed, so
 * `"0 0 320"` is an error rather than a rect with a zero side. */
static BOOL ag_parse_rect(NSString *text, NSRect *rectOut)
{
	NSScanner *scanner = [NSScanner scannerWithString:text];
	double x, y, w, h;
	BOOL ok;

	/* **TWO NUMBERS ARE A SIZE AND FOUR ARE A RECT**, and which one a property wants is the property's business — this
	 * returns a rect either way, with the size's numbers read into the SIZE and the origin left at zero. A single number,
	 * or five, is a mistake in the file and is refused. */
	if (![scanner scanDouble:&x]) {
		return NO;
	}
	if (![scanner scanDouble:&y]) {
		return NO;
	}
	if ([scanner isAtEnd]) {
		rectOut->origin.x = 0.0;
		rectOut->origin.y = 0.0;
		rectOut->size.width = x;
		rectOut->size.height = y;
		return YES;
	}
	w = 0.0;
	h = 0.0;
	if (![scanner scanDouble:&w]) {
		return NO;
	}
	if (![scanner scanDouble:&h]) {
		return NO;
	}
	ok = [scanner isAtEnd];
	/* AND THE SEPARATORS ARE NOT CHECKED FOR, because `NSScanner`'s double scan skips whitespace and a coordinate list
	 * is the one place a comma is noise. What IS checked is that nothing else was in the string. */
	rectOut->origin.x = x;
	rectOut->origin.y = y;
	rectOut->size.width = w;
	rectOut->size.height = h;
	return ok;
}

/* ============================================================================================
 * A VALUE LITERAL, BUILT
 * ============================================================================================ */

static NSColor *ag_color_from_hex(NSString *text, NSString **error);

/* THE NAMED COLOURS, by the words a person would type. Apple's own names are the long ones (`redColor`); the literal's
 * vocabulary is the short one, and the table is small on purpose: a colour that is not here is written as hex. */
static NSColor *ag_named_color(NSString *name)
{
	struct {
		const char *word;
		NSColor *(*make)(void);
	} table[] = {
		{ "black",   NULL }, { "white", NULL }, { "red", NULL }, { "green", NULL },
		{ "blue",    NULL }, { "cyan",  NULL }, { "magenta", NULL }, { "yellow", NULL },
		{ "orange",  NULL }, { "purple", NULL }, { "brown", NULL }, { "gray", NULL },
	};
	(void)table;
	if ([name isEqualToString:@"black"]) { return [NSColor blackColor]; }
	if ([name isEqualToString:@"white"]) { return [NSColor whiteColor]; }
	if ([name isEqualToString:@"red"]) { return [NSColor redColor]; }
	if ([name isEqualToString:@"green"]) { return [NSColor greenColor]; }
	if ([name isEqualToString:@"blue"]) { return [NSColor blueColor]; }
	if ([name isEqualToString:@"cyan"]) { return [NSColor cyanColor]; }
	if ([name isEqualToString:@"magenta"]) { return [NSColor magentaColor]; }
	if ([name isEqualToString:@"yellow"]) { return [NSColor yellowColor]; }
	if ([name isEqualToString:@"orange"]) { return [NSColor orangeColor]; }
	if ([name isEqualToString:@"purple"]) { return [NSColor purpleColor]; }
	if ([name isEqualToString:@"brown"]) { return [NSColor brownColor]; }
	if ([name isEqualToString:@"gray"]) { return [NSColor grayColor]; }
	return nil;
}

static NSColor *ag_color_from_hex(NSString *text, NSString **error)
{
	unsigned int red = 0, green = 0, blue = 0, alpha = 255;
	size_t length = [text length];

	if ([text hasPrefix:@"#"]) {
		text = [text substringFromIndex:1];
		length = [text length];
	}
	if (length != 6 && length != 8) {
		*error = [NSString stringWithFormat:@"@color(%@) needs six or eight hex digits", text];
		return nil;
	}
	{
		unsigned long long value = 0;
		NSScanner *scanner = [NSScanner scannerWithString:text];

		if (![scanner scanHexLongLong:&value] || ![scanner isAtEnd]) {
			*error = [NSString stringWithFormat:@"@color(%@) is not hexadecimal", text];
			return nil;
		}
		if (length == 8) {
			red = (unsigned int)((value >> 24) & 0xFF);
			green = (unsigned int)((value >> 16) & 0xFF);
			blue = (unsigned int)((value >> 8) & 0xFF);
			alpha = (unsigned int)(value & 0xFF);
		} else {
			red = (unsigned int)((value >> 16) & 0xFF);
			green = (unsigned int)((value >> 8) & 0xFF);
			blue = (unsigned int)(value & 0xFF);
		}
	}
	return [NSColor colorWithCalibratedRed:(CGFloat)red / 255.0
					green:(CGFloat)green / 255.0
					 blue:(CGFloat)blue / 255.0
					alpha:(CGFloat)alpha / 255.0];
}

/* THE LITERAL'S BODY, AS A STRING OR A STRING AND A NUMBER. A font's name may have spaces and is therefore quoted; a
 * literal that needs only one word may leave it bare (`@image(icon-run)`), which is what makes the common case short. */
static NSString *ag_first_word(NSString *body, NSString * *restOut)
{
	NSScanner *scanner = [NSScanner scannerWithString:body];
	NSString *word = nil;

	if ([body hasPrefix:@"\""]) {
		NSString *quoted = nil;

		if ([scanner scanString:@"\"" intoString:NULL] && [scanner scanUpToString:@"\"" intoString:&quoted]) {
			(void)[scanner scanString:@"\"" intoString:NULL];
			word = quoted;
		}
	} else {
		(void)[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet]
				     intoString:&word];
	}
	if (restOut != NULL) {
		*restOut = [body substringFromIndex:[scanner scanLocation]];
	}
	return word;
}

/* THE THREE LITERALS, EACH IN ONE PLACE SO THE COMPILER AND THE ERROR MESSAGE CANNOT DISAGREE ABOUT THE SYNTAX. */
static id ag_object_from_literal(NSDictionary *literal, NSString **error)
{
	NSString *name = [literal objectForKey:@"$literal"];
	NSString *body = [literal objectForKey:@"$value"];

	if ([name isEqualToString:@"color"]) {
		NSColor *named = ag_named_color(body);

		if (named != nil) {
			return named;
		}
		return ag_color_from_hex(body, error);
	}
	if ([name isEqualToString:@"font"]) {
		NSString *rest = nil;
		NSString *fontName = ag_first_word(body, &rest);
		NSScanner *scanner = [NSScanner scannerWithString:(rest != nil) ? rest : @""];
		double size = 0.0;
		NSFont *font;

		if (fontName == nil || ![scanner scanDouble:&size] || size <= 0.0) {
			*error = [NSString stringWithFormat:@"@font(%@) needs a name and a size: @font(\"Helvetica\" 12)", body];
			return nil;
		}
		font = [NSFont fontWithName:fontName size:(CGFloat)size];
		if (font == nil) {
			*error = [NSString stringWithFormat:@"@font: this machine has no font named \"%@\"", fontName];
		}
		return font;
	}
	if ([name isEqualToString:@"image"]) {
		NSString *imageName = ag_first_word(body, NULL);
		NSImage *image = (imageName != nil) ? [NSImage imageNamed:imageName] : nil;

		if (image == nil) {
			*error = [NSString stringWithFormat:@"@image: there is no image named \"%@\"", imageName];
		}
		return image;
	}
	*error = [NSString stringWithFormat:@"@%@ is not a literal this format has (color, font, image)", name];
	return nil;
}

static id ag_resolve(NSDictionary *registry, NSString *name)
{
	if (name == nil) {
		return nil;
	}
	if ([name isEqualToString:@"owner"]) {
		return NSNibFileOwner;
	}
	return [registry objectForKey:name];
}

/* THE KEYS AN OBJECT MAY HAVE, so a typo is a refusal rather than a silently absent property. */
static BOOL ag_is_object_key(NSString *key)
{
	return [key isEqualToString:@"id"] || [key isEqualToString:@"class"] ||
	       [key isEqualToString:@"properties"] || [key isEqualToString:@"cell"] ||
	       [key isEqualToString:@"contentView"] || [key isEqualToString:@"subviews"] ||
	       [key isEqualToString:@"constraints"];
}

static NSLayoutConstraint *ag_constraint(NSDictionary *record, NSDictionary *registry, NSString **error)
{
	NSString *firstName = [record objectForKey:@"first"];
	NSString *secondName = [record objectForKey:@"second"];
	id first = ag_resolve(registry, firstName);
	id second = ag_resolve(registry, secondName);
	BOOL found = NO;
	NSLayoutAttribute firstAttribute;
	NSLayoutAttribute secondAttribute;
	NSLayoutRelation relation;
	NSLayoutConstraint *constraint;

	if (first == nil) {
		*error = [NSString stringWithFormat:@"a constraint's first side \"%@\" is not an id this file declares",
			  firstName];
		return nil;
	}
	if (secondName != nil && second == nil) {
		*error = [NSString stringWithFormat:@"a constraint's second side \"%@\" is not an id this file declares",
			  secondName];
		return nil;
	}
	firstAttribute = ag_attribute([record objectForKey:@"firstAttribute"], &found);
	if (!found) {
		*error = [NSString stringWithFormat:@"\"%@\" is not a layout attribute", [record objectForKey:@"firstAttribute"]];
		return nil;
	}
	if (second == nil) {
		secondAttribute = NSLayoutAttributeNotAnAttribute;
	} else {
		secondAttribute = ag_attribute([record objectForKey:@"secondAttribute"], &found);
		if (!found) {
			*error = [NSString stringWithFormat:@"\"%@\" is not a layout attribute",
				  [record objectForKey:@"secondAttribute"]];
			return nil;
		}
	}
	relation = ag_relation([record objectForKey:@"relation"], &found);
	if (!found) {
		*error = [NSString stringWithFormat:@"\"%@\" is not a layout relation", [record objectForKey:@"relation"]];
		return nil;
	}
	/* **AN ABSENT MULTIPLIER IS ONE, AND A ZERO ONE IS AN ERROR.** `nil doubleValue` is 0.0, which the constraint's own
	 * constructor refuses — correctly, since a zero multiplier would take the second side out of the equation — so the
	 * default is spelled here rather than left to a nil message. */
	{
		id multiplier = [record objectForKey:@"multiplier"];
		double value = (multiplier != nil) ? [multiplier doubleValue] : 1.0;

		if (value <= 0.0) {
			*error = [NSString stringWithFormat:@"a constraint's multiplier must be greater than zero (got %g)",
				  value];
			return nil;
		}
		constraint = [NSLayoutConstraint constraintWithItem:first
							 attribute:firstAttribute
							 relatedBy:relation
							    toItem:second
							 attribute:secondAttribute
							multiplier:value
							  constant:[[record objectForKey:@"constant"] doubleValue]];
	}
	if (constraint == nil) {
		*error = @"the constraint could not be made (see NSLayoutConstraint's own refusal on stderr)";
		return nil;
	}
	if ([record objectForKey:@"priority"] != nil) {
		[constraint setPriority:(NSLayoutPriority)[[record objectForKey:@"priority"] doubleValue]];
	}
	if ([[record objectForKey:@"identifier"] isKindOfClass:[NSString class]]) {
		[constraint setIdentifier:[record objectForKey:@"identifier"]];
	}
	return constraint;
}

static id ag_build_object(NSDictionary *record, NSDictionary *registry, NSString **error)
{
	NSString *className = [record objectForKey:@"class"];
	NSString *name = [record objectForKey:@"id"];
	Class cls;
	id object;
	NSEnumerator *keys;
	NSString *key;

	if (![className isKindOfClass:[NSString class]]) {
		*error = @"an object needs a \"class\" name";
		return nil;
	}
	cls = NSClassFromString(className);
	if (cls == Nil) {
		*error = [NSString stringWithFormat:@"there is no class named \"%@\"", className];
		return nil;
	}
	if (![NSNib isSupportedClass:cls]) {
		*error = [NSString stringWithFormat:@"\"%@\" is not a class this format may build (see NSNib's "
			  "allow-list)", className];
		return nil;
	}
	keys = [record keyEnumerator];
	while ((key = [keys nextObject]) != nil) {
		if (!ag_is_object_key(key)) {
			*error = [NSString stringWithFormat:@"\"%@\" is not a key an object may have", key];
			return nil;
		}
	}

	object = [[cls alloc] init];
	if (object == nil) {
		*error = [NSString stringWithFormat:@"\"%@\" could not be made", className];
		return nil;
	}
	/* **THE NAME IS REGISTERED AS SOON AS THE OBJECT EXISTS, RATHER THAN WHEN IT IS FINISHED.** A constraint on a child
	 * names its PARENT, and the parent is still being built when the child's constraints are compiled — so a registry
	 * that only learned a name at the end would make every parent-relative constraint impossible. What is still refused
	 * is a reference to an id the file has not reached yet, which is a design that names something not yet made and is
	 * exactly the kind of forward reference a text format should not have to resolve. */
	if ([name isKindOfClass:[NSString class]]) {
		[registry setObject:object forKey:name];
	}
	/* THE CELL FIRST, because everything else a control says is applied TO its cell. */
	if ([record objectForKey:@"cell"] != nil) {
		id cell = ag_build_object([record objectForKey:@"cell"], registry, error);

		if (cell == nil) {
			[object release];
			return nil;
		}
		if ([object respondsToSelector:@selector(setCell:)]) {
			[object setCell:cell];	/* the control retains it; the builder owns nothing */
		}
	}
	/* THEN THE PROPERTIES, THROUGH KVC — the same door the archive's own decoder uses, so a source and a decoded archive
	 * apply the same vocabulary and a key that works in one works in the other. */
	{
		NSDictionary *properties = [record objectForKey:@"properties"];

		if (properties != nil) {
			if (![properties isKindOfClass:[NSDictionary class]]) {
				*error = @"\"properties\" must be a dictionary";
				[object release];
				return nil;
			}
			keys = [properties keyEnumerator];
			while ((key = [keys nextObject]) != nil) {
				id value = [properties objectForKey:key];
				BOOL geometry = [key isEqualToString:@"frame"] || [key isEqualToString:@"bounds"];

				/* **A LITERAL IS BUILT HERE, BEFORE ANY OTHER RULE SEES IT.** `@color(…)` and its siblings arrive from the
				 * parser as a marked dictionary; the compiler is the half that knows what each one MEANS, and a literal it
				 * cannot build (a colour that is not hex, a font this machine has not got) is a refusal by name. */
				if ([value isKindOfClass:[NSDictionary class]] &&
				    [(NSDictionary *)value objectForKey:@"$literal"] != nil) {
					NSString *literalError = nil;
					id built = ag_object_from_literal(value, &literalError);

					if (built == nil) {
						*error = [NSString stringWithFormat:@"\"%@\": %@", key,
							  (literalError != nil) ? literalError : @"the literal could not be built"];
						[object release];
						return nil;
					}
					@try {
						[object setValue:built forKey:key];
					} @catch (NSException *exception) {
						*error = [NSString stringWithFormat:@"\"%@\" did not take \"%@\": %@", className,
							  key, [exception reason]];
						[object release];
						return nil;
					}
					continue;
				}
				if (![value isKindOfClass:[NSString class]] && !geometry) {
					/* scalars arrive already typed from the parser; objects are not expressible in a property map */
					if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
						*error = [NSString stringWithFormat:@"\"%@\" cannot be a dictionary or an array; "
							  "use a nested object key instead", key];
						[object release];
						return nil;
					}
				}
				if (geometry) {
					NSRect rect;

					if (![value isKindOfClass:[NSString class]] || !ag_parse_rect(value, &rect)) {
						*error = [NSString stringWithFormat:@"\"%@\" needs four numbers in a string: "
							  "\"x y width height\"", key];
						[object release];
						return nil;
					}
					if ([key isEqualToString:@"frame"] && [object respondsToSelector:@selector(setFrame:)]) {
						[object setFrame:rect];
						continue;
					}
					/* **A WINDOW'S FRAME GOES THROUGH ITS OWN DOOR**, which is `-setFrame:display:` and not `-setFrame:` —
					 * a window has no plain frame setter, so the generic KVC path below would raise for the one property
					 * every window nib states. */
					if ([key isEqualToString:@"frame"] &&
					    [object respondsToSelector:@selector(setFrame:display:)]) {
						[object setFrame:rect display:NO];
						continue;
					}
					if ([key isEqualToString:@"bounds"] && [object respondsToSelector:@selector(setBoundsSize:)]) {
						[object setBoundsSize:rect.size];
						continue;
					}
					/* ANY OTHER GEOMETRY PROPERTY TAKES THE VALUE KVC ALREADY UNDERSTANDS: an `NSValue` rect when the
					 * string had four numbers, a size when it had two. That is what makes `minSize = "80 60"` work without
					 * a table of which properties are sizes. */
					@try {
						[object setValue:([value rangeOfString:@" "].location != NSNotFound &&
								  [value componentsSeparatedByString:@" "].count > 2)
							? [NSValue valueWithRect:rect]
							: [NSValue valueWithSize:rect.size]
							   forKey:key];
					} @catch (NSException *exception) {
						*error = [NSString stringWithFormat:@"\"%@\" did not take \"%@\": %@", className,
							  key, [exception reason]];
						[object release];
						return nil;
					}
					continue;
				}
				@try {
					[object setValue:value forKey:key];
				} @catch (NSException *exception) {
					*error = [NSString stringWithFormat:@"\"%@\" did not take \"%@\": %@", className, key,
						  [exception reason]];
					[object release];
					return nil;
				}
			}
		}
	}
	/* THE CONTENT VIEW BEFORE THE CONSTRAINTS (a constraint may name it) AND AFTER THE PROPERTIES. */
	if ([record objectForKey:@"contentView"] != nil) {
		id view = ag_build_object([record objectForKey:@"contentView"], registry, error);

		if (view == nil) {
			[object release];
			return nil;
		}
		if ([object respondsToSelector:@selector(setContentView:)]) {
			[object setContentView:view];	/* the window retains it */
		}
	}
	if ([record objectForKey:@"subviews"] != nil) {
		NSArray *subviews = [record objectForKey:@"subviews"];
		NSUInteger i;

		if (![subviews isKindOfClass:[NSArray class]]) {
			*error = @"\"subviews\" must be an array";
			[object release];
			return nil;
		}
		for (i = 0; i < [subviews count]; i++) {
			id child = ag_build_object([subviews objectAtIndex:i], registry, error);

			if (child == nil) {
				[object release];
				return nil;
			}
			if (![object respondsToSelector:@selector(addSubview:)]) {
				*error = [NSString stringWithFormat:@"\"%@\" cannot hold subviews", className];
				[object release];
				return nil;
			}
			[object addSubview:child];	/* the parent retains it */
		}
	}
	if ([record objectForKey:@"constraints"] != nil) {
		NSArray *constraints = [record objectForKey:@"constraints"];
		NSUInteger i;

		if (![constraints isKindOfClass:[NSArray class]]) {
			*error = @"\"constraints\" must be an array";
			[object release];
			return nil;
		}
		if (![object respondsToSelector:@selector(addConstraint:)]) {
			*error = [NSString stringWithFormat:@"\"%@\" cannot own constraints", className];
			[object release];
			return nil;
		}
		for (i = 0; i < [constraints count]; i++) {
			id record2 = [constraints objectAtIndex:i];
			NSLayoutConstraint *constraint;

			if (![record2 isKindOfClass:[NSDictionary class]]) {
				*error = @"a constraint must be a dictionary";
				[object release];
				return nil;
			}
			constraint = ag_constraint(record2, registry, error);
			if (constraint == nil) {
				[object release];
				return nil;
			}
			[object addConstraint:constraint];
		}
	}
	return [object autorelease];
}

/* ============================================================================================
 * THE DECOMPILER'S TWO HELPERS
 * ============================================================================================ */

/* **THE KEY VOCABULARY IS READ OFF THE CODER RATHER THAN TABULATED HERE.** A decompiler that kept its own list of which
 * property each class codes would be a second copy of every `-encodeWithCoder:` in the tree, and the two copies would
 * drift the first time a class gained a key. So each object is archived ON ITS OWN, once, and the keys of that little
 * archive's root entry ARE the keys the class codes — the coder remains the only definition. What KVC then reads is the
 * LIVE value, which is what the source should say. */
static NSArray *ag_coded_keys_for_object(id object)
{
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object];
	id plist;
	id objects;
	id first;

	if (data == nil) {
		return nil;
	}
	plist = [NSPropertyListSerialization propertyListWithData:data
							  options:NSPropertyListImmutable
							   format:NULL
							    error:NULL];
	if (![plist isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	objects = [(NSDictionary *)plist objectForKey:@"$objects"];
	if (![objects isKindOfClass:[NSArray class]] || [(NSArray *)objects count] < 2) {
		return nil;
	}
	first = [(NSArray *)objects objectAtIndex:1];
	if (![first isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	return [(NSDictionary *)first allKeys];
}

/* THE KEYS THAT ARE STRUCTURE RATHER THAN PROPERTIES, because they are emitted as nested objects and connections. */
static BOOL ag_is_structural_key(NSString *key)
{
	return [key isEqualToString:@"subviews"] || [key isEqualToString:@"constraints"] ||
	       [key isEqualToString:@"cell"] || [key isEqualToString:@"contentView"];
}

static NSString *ag_attribute_name(NSLayoutAttribute attribute);
static NSString *ag_relation_name(NSLayoutRelation relation);

@interface AGNibWriter : NSObject
{
	NSMutableString *_out;
	NSMutableDictionary *_ids;	/* object -> name, by identity */
	NSUInteger _next;
	NSString *_error;
}
@end

@implementation AGNibWriter

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_out = [[NSMutableString alloc] init];
		_ids = [[NSMutableDictionary alloc] init];
		_next = 1;
	}
	return self;
}

- (void)dealloc
{
	[_out release];
	[_ids release];
	[_error release];
	[super dealloc];
}

- (NSString *)error
{
	return _error;
}

- (NSString *)takeOutput
{
	return [[_out copy] autorelease];
}

- (void)fail:(NSString *)format, ...
{
	va_list args;

	if (_error != nil) {
		return;
	}
	va_start(args, format);
	_error = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
}

/* A NAME FOR AN OBJECT, STABLE WITHIN ONE RUN AND DERIVED FROM ITS CLASS, because a person reads this file. */
- (NSString *)nameFor:(id)object
{
	NSString *existing = [_ids objectForKey:[NSValue valueWithPointer:object]];

	if (existing != nil) {
		return existing;
	}
	{
		NSString *name = [NSString stringWithFormat:@"%@%lu",
				  [NSStringFromClass([object class]) lowercaseString],
				  (unsigned long)_next++];

		[_ids setObject:name forKey:[NSValue valueWithPointer:object]];
		return name;
	}
}

/* **A SCALAR, AS THE WORDS THIS GRAMMAR ALREADY HAS**: a number as a word, a string quoted, a geometry value as the
 * `"x y w h"` form the compiler parses for `frame`. Answers nil for something it cannot express, and leaves the CALLER to
 * refuse with the key's name. */
- (NSString *)scalarText:(id)value
{
	if ([value isKindOfClass:[NSNumber class]]) {
		const char *type = [(NSNumber *)value objCType];

		if (type != NULL && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, "c") == 0)) {
			return [(NSNumber *)value boolValue] ? @"YES" : @"NO";
		}
		if (type != NULL && (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0)) {
			return [NSString stringWithFormat:@"%.17g", [(NSNumber *)value doubleValue]];
		}
		return [NSString stringWithFormat:@"%lld", (long long)[(NSNumber *)value longLongValue]];
	}
	if ([value isKindOfClass:[NSString class]]) {
		return [NSString stringWithFormat:@"\"%@\"",
			[(NSString *)value stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
	}
	if ([value isKindOfClass:[NSValue class]]) {
		const char *type = [(NSValue *)value objCType];
		NSRect rect;

		if (type != NULL && strcmp(type, @encode(NSRect)) == 0) {
			rect = [(NSValue *)value rectValue];
			return [NSString stringWithFormat:@"\"%g %g %g %g\"", (double)rect.origin.x,
				(double)rect.origin.y, (double)rect.size.width, (double)rect.size.height];
		}
		if (type != NULL && strcmp(type, @encode(NSSize)) == 0) {
			NSSize size = [(NSValue *)value sizeValue];

			return [NSString stringWithFormat:@"\"%g %g\"", (double)size.width, (double)size.height];
		}
		if (type != NULL && strcmp(type, @encode(NSPoint)) == 0) {
			NSPoint point = [(NSValue *)value pointValue];

			return [NSString stringWithFormat:@"\"%g %g\"", (double)point.x, (double)point.y];
		}
	}
	return nil;
}

/* **THE THREE OBJECT-VALUED PROPERTIES, AS THE LITERALS THE COMPILER BUILDS BACK.** A colour is emitted as hex (six digits
 * when it is opaque, eight when it is not), a font as its PostScript name and size, and an image as its name — the same
 * three spellings the header documents, so `decompile` and `compile` are inverses on the values a design actually sets.
 * Answers nil for anything else, and the caller falls back to a scalar or refuses. */
- (NSString *)literalText:(id)value
{
	if ([value isKindOfClass:[NSColor class]]) {
		CGFloat red = [(NSColor *)value redComponent];
		CGFloat green = [(NSColor *)value greenComponent];
		CGFloat blue = [(NSColor *)value blueComponent];
		CGFloat alpha = [(NSColor *)value alphaComponent];
		unsigned int r = (unsigned int)(red * 255.0 + 0.5);
		unsigned int g = (unsigned int)(green * 255.0 + 0.5);
		unsigned int b = (unsigned int)(blue * 255.0 + 0.5);
		unsigned int a = (unsigned int)(alpha * 255.0 + 0.5);

		if (a == 255) {
			return [NSString stringWithFormat:@"@color(#%02x%02x%02x)", r, g, b];
		}
		return [NSString stringWithFormat:@"@color(#%02x%02x%02x%02x)", r, g, b, a];
	}
	if ([value isKindOfClass:[NSFont class]]) {
		NSString *name = [(NSFont *)value fontName];

		if (name == nil) {
			return nil;
		}
		return [NSString stringWithFormat:@"@font(\"%@\" %g)", name, (double)[(NSFont *)value pointSize]];
	}
	if ([value isKindOfClass:[NSImage class]]) {
		NSString *name = [(NSImage *)value name];

		if (name == nil) {
			return nil;
		}
		return [NSString stringWithFormat:@"@image(%@)", name];
	}
	return nil;
}

/* THE PROPERTIES AN OBJECT CAN STATE, as `key = value;` lines. Anything object-valued that is not structure is a
 * REFUSAL, because this grammar has no literal for it yet. */
- (BOOL)writePropertiesOf:(id)object indent:(NSString *)indent
{
	NSArray *keys = ag_coded_keys_for_object(object);
	NSUInteger i;
	NSMutableArray *lines = [[NSMutableArray alloc] init];

	if (keys == nil) {
		[self fail:@"%@ could not be asked what it codes", NSStringFromClass([object class])];
		[lines release];
		return NO;
	}
	for (i = 0; i < [keys count]; i++) {
		NSString *key = [keys objectAtIndex:i];
		id value;
		NSString *text;

		if (ag_is_structural_key(key)) {
			continue;
		}
		/* **A SELECTOR IS NOT A PROPERTY THIS GRAMMAR CAN STATE**, and KVC hands one back as the string
		 * `"<null selector>"` — which would compile into a nonsense selector. The ACTION that matters is the connection,
		 * which this file emits from the archive's own records; a cell's or a browser's action alone is skipped. */
		if ([key isEqualToString:@"action"] || [key isEqualToString:@"doubleAction"]) {
			continue;
		}
		/* **`frame` IS READ THROUGH ITS OWN DOOR.** Key Value Coding cannot box an `NSRect` on this tree's KVC — the
		 * getter returns a struct and `-valueForKey:` has no type to box it with — so the one geometry property a design
		 * file states is read directly rather than skipped. Everything else goes through KVC, and a key it cannot read is
		 * skipped rather than refused (a selector is the case that matters: a cell's `action` is not a property a source
		 * can state, and the connection that carried it is emitted instead). */
		if ([key isEqualToString:@"frame"] && [object isKindOfClass:[NSView class]]) {
			NSRect frame = [(NSView *)object frame];

			text = [NSString stringWithFormat:@"\"%g %g %g %g\"", (double)frame.origin.x,
				(double)frame.origin.y, (double)frame.size.width, (double)frame.size.height];
			[lines addObject:[NSString stringWithFormat:@"%@  %@ = %@;", indent, key, text]];
			continue;
		}
		value = nil;
		@try {
			value = [object valueForKey:key];
		} @catch (NSException *exception) {
			/* A KEY THE CODER WRITES BUT KVC CANNOT READ is not a property a source can state — a good example is a
			 * cell's `action`, a selector. It is SKIPPED and named rather than refused: the archive keeps it, and a
			 * source that drops a selector keeps the connection that actually carried it. */
			continue;
		}
		if (value == nil) {
			continue;
		}
		text = [self literalText:value];
		if (text == nil) {
			text = [self scalarText:value];
		}
		if (text == nil) {
			[self fail:@"%@'s \"%@\" is a %@, and this grammar has no literal for one",
				NSStringFromClass([object class]), key, NSStringFromClass([value class])];
			[lines release];
			return NO;
		}
		[lines addObject:[NSString stringWithFormat:@"%@  %@ = %@;", indent, key, text]];
	}
	if ([lines count] > 0) {
		[_out appendFormat:@"%@properties = {\n", indent];
		for (i = 0; i < [lines count]; i++) {
			[_out appendFormat:@"%@\n", [lines objectAtIndex:i]];
		}
		[_out appendFormat:@"%@};\n", indent];
	}
	[lines release];
	return YES;
}

/* THE ID IS WRITTEN BEFORE THE BODY so that a name is stable for the whole file even when an object refers to itself
 * (a menu item's submenu, a view constrained to its own parent). */
- (BOOL)writeObject:(id)object indent:(NSString *)indent isTopLevel:(BOOL)topLevel
{
	(void)topLevel;
	NSString *inner = [indent stringByAppendingString:@"  "];
	/* **EVERY OBJECT IS NAMED, NOT ONLY THE TOP-LEVEL ONES.** A connection and a constraint refer to a view by `id`, and
	 * those views are usually SUBVIEWS — so a name emitted only for top-level objects would leave the common case
	 * unwritable. The names are generated and stable within one decompile (see `-nameFor:`), and the compiler registers
	 * an `id` wherever it appears. */
	NSString *name = [self nameFor:object];
	NSArray *subviews = nil;

	[_out appendFormat:@"%@{\n", indent];
	[_out appendFormat:@"%@  id = \"%@\";\n", inner, name];
	[_out appendFormat:@"%@  class = %@;\n", inner, NSStringFromClass([object class])];
	if (![self writePropertiesOf:object indent:[inner stringByAppendingString:@"  "]]) {
		return NO;
	}
	/* **A NESTED OBJECT IS A DICTIONARY VALUE, SO IT ENDS WITH A SEMICOLON** — `cell = { … };` — and its own body is
	 * indented from here rather than from column zero, which is what makes the file readable as text. */
	if ([object isKindOfClass:[NSControl class]] && [(NSControl *)object cell] != nil) {
		[_out appendFormat:@"%@  cell = ", inner];
		if (![self writeObject:[(NSControl *)object cell]
				indent:[inner stringByAppendingString:@"  "]
			    isTopLevel:NO]) {
			return NO;
		}
		[_out appendString:@";\n"];
	}
	if ([object isKindOfClass:[NSWindow class]] && [(NSWindow *)object contentView] != nil) {
		[_out appendFormat:@"%@  contentView = ", inner];
		if (![self writeObject:[(NSWindow *)object contentView]
				indent:[inner stringByAppendingString:@"  "]
			    isTopLevel:NO]) {
			return NO;
		}
		[_out appendString:@";\n"];
	}
	if ([object isKindOfClass:[NSView class]]) {
		subviews = [(NSView *)object subviews];
		if ([subviews count] > 0) {
			NSUInteger i;

			[_out appendFormat:@"%@  subviews = (\n", inner];
			for (i = 0; i < [subviews count]; i++) {
				if (![self writeObject:[subviews objectAtIndex:i]
						indent:[inner stringByAppendingString:@"  "]
					    isTopLevel:NO]) {
					return NO;
				}
				[_out appendFormat:@"\n"];
			}
			[_out appendFormat:@"%@  );\n", inner];
		}
		if ([[(NSView *)object constraints] count] > 0) {
			NSArray *constraints = [(NSView *)object constraints];
			NSUInteger i;

			[_out appendFormat:@"%@  constraints = (\n", inner];
			for (i = 0; i < [constraints count]; i++) {
				NSLayoutConstraint *c = [constraints objectAtIndex:i];
				id first = [c firstItem];
				id second = [c secondItem];

				[_out appendFormat:@"%@    { first = \"%@\";", inner,
					[first isKindOfClass:[NSString class]] ? first : [self nameFor:first]];
				[_out appendFormat:@" firstAttribute = %@;", ag_attribute_name([c firstAttribute])];
				if (second != nil) {
					[_out appendFormat:@" second = \"%@\"; secondAttribute = %@;",
						[second isKindOfClass:[NSString class]] ? second : [self nameFor:second],
						ag_attribute_name([c secondAttribute])];
				}
				[_out appendFormat:@" relation = %@; multiplier = %.17g; constant = %.17g;",
					ag_relation_name([c relation]), (double)[c multiplier], (double)[c constant]];
				if ([c priority] != NSLayoutPriorityRequired) {
					[_out appendFormat:@" priority = %g;", (double)[c priority]];
				}
				if ([c identifier] != nil) {
					[_out appendFormat:@" identifier = \"%@\";", [c identifier]];
				}
				[_out appendFormat:@" }\n"];
			}
			[_out appendFormat:@"%@  );\n", inner];
		}
	}
	[_out appendFormat:@"%@}", indent];
	return YES;
}

@end

static NSString *ag_attribute_name(NSLayoutAttribute attribute)
{
	switch (attribute) {
	case NSLayoutAttributeLeft: return @"left";
	case NSLayoutAttributeRight: return @"right";
	case NSLayoutAttributeTop: return @"top";
	case NSLayoutAttributeBottom: return @"bottom";
	case NSLayoutAttributeLeading: return @"leading";
	case NSLayoutAttributeTrailing: return @"trailing";
	case NSLayoutAttributeWidth: return @"width";
	case NSLayoutAttributeHeight: return @"height";
	case NSLayoutAttributeCenterX: return @"centerX";
	case NSLayoutAttributeCenterY: return @"centerY";
	case NSLayoutAttributeLastBaseline: return @"lastBaseline";
	case NSLayoutAttributeFirstBaseline: return @"firstBaseline";
	default: return @"none";
	}
}

static NSString *ag_relation_name(NSLayoutRelation relation)
{
	switch (relation) {
	case NSLayoutRelationLessThanOrEqual: return @"lessThanOrEqual";
	case NSLayoutRelationGreaterThanOrEqual: return @"greaterThanOrEqual";
	default: return @"equal";
	}
}

@implementation NSNibSource

+ (id)propertyListFromSourceData:(NSData *)data error:(NSString **)error
{
	AGSrc s;
	id root;

	if (error != NULL) {
		*error = nil;
	}
	if (data == nil || [data length] == 0) {
		if (error != NULL) {
			*error = @"the source is empty";
		}
		return nil;
	}
	memset(&s, 0, sizeof(s));
	s.bytes = (const char *)[data bytes];
	s.length = (size_t)[data length];
	s.line = 1;

	root = ag_value(&s);
	if (root == nil) {
		if (error != NULL) {
			*error = (s.error != nil) ? s.error : @"the source could not be parsed";
		}
		return nil;
	}
	ag_skip(&s);
	if (!ag_at_end(&s)) {
		if (error != NULL) {
			*error = [NSString stringWithFormat:@"line %u: the file continues after the root value", s.line];
		}
		return nil;
	}
	return root;
}

+ (NSData *)archiveFromSourceData:(NSData *)data error:(NSString **)error
{
	id plist;
	id version;
	id objects;
	id connections;
	NSMutableDictionary *registry;
	NSMutableArray *builtObjects;
	NSMutableArray *builtConnections;
	NSUInteger i;

	if (error != NULL) {
		*error = nil;
	}
	plist = [self propertyListFromSourceData:data error:error];
	if (plist == nil) {
		return nil;
	}
	if (![plist isKindOfClass:[NSDictionary class]]) {
		if (error != NULL) {
			*error = @"the source's root must be a dictionary";
		}
		return nil;
	}
	version = [(NSDictionary *)plist objectForKey:@"version"];
	if (![version isKindOfClass:[NSNumber class]]) {
		if (error != NULL) {
			*error = @"the source has no \"version\"";
		}
		return nil;
	}
	if ([version integerValue] > [NSNib formatVersion]) {
		if (error != NULL) {
			*error = [NSString stringWithFormat:@"the source is version %ld and this compiler writes %ld",
				  (long)[version integerValue], (long)[NSNib formatVersion]];
		}
		return nil;
	}
	objects = [(NSDictionary *)plist objectForKey:@"objects"];
	if (![objects isKindOfClass:[NSArray class]] || [(NSArray *)objects count] == 0) {
		if (error != NULL) {
			*error = @"the source has no \"objects\" array, or it is empty";
		}
		return nil;
	}

	registry = [[NSMutableDictionary alloc] init];
	builtObjects = [[NSMutableArray alloc] init];
	for (i = 0; i < [(NSArray *)objects count]; i++) {
		id record = [(NSArray *)objects objectAtIndex:i];
		id object;

		if (![record isKindOfClass:[NSDictionary class]]) {
			if (error != NULL) {
				*error = [NSString stringWithFormat:@"object %lu is not a dictionary", (unsigned long)i];
			}
			[registry release];
			[builtObjects release];
			return nil;
		}
		object = ag_build_object(record, registry, error);
		if (object == nil) {
			[registry release];
			[builtObjects release];
			return nil;
		}
		[builtObjects addObject:object];
	}

	builtConnections = [[NSMutableArray alloc] init];
	connections = [(NSDictionary *)plist objectForKey:@"connections"];
	if (connections != nil) {
		if (![connections isKindOfClass:[NSArray class]]) {
			if (error != NULL) {
				*error = @"\"connections\" must be an array";
			}
			[registry release];
			[builtObjects release];
			[builtConnections release];
			return nil;
		}
		for (i = 0; i < [(NSArray *)connections count]; i++) {
			id record = [(NSArray *)connections objectAtIndex:i];
			id source;
			id destination;
			NSString *keyPath;
			NSString *action;

			if (![record isKindOfClass:[NSDictionary class]]) {
				if (error != NULL) {
					*error = [NSString stringWithFormat:@"connection %lu is not a dictionary",
						  (unsigned long)i];
				}
				[registry release];
				[builtObjects release];
				[builtConnections release];
				return nil;
			}
			source = ag_resolve(registry, [record objectForKey:@"source"]);
			destination = ag_resolve(registry, [record objectForKey:@"destination"]);
			keyPath = [record objectForKey:@"keyPath"];
			action = [record objectForKey:@"action"];
			if (destination == nil && [record objectForKey:@"destination"] != nil) {
				if (error != NULL) {
					*error = [NSString stringWithFormat:@"connection %lu names a destination this file "
						  "does not declare", (unsigned long)i];
				}
				[registry release];
				[builtObjects release];
				[builtConnections release];
				return nil;
			}
			if (source == nil) {
				if (error != NULL) {
					*error = [NSString stringWithFormat:@"connection %lu names a source this file does "
						  "not declare", (unsigned long)i];
				}
				[registry release];
				[builtObjects release];
				[builtConnections release];
				return nil;
			}
			if (keyPath != nil) {
				[builtConnections addObject:[NSNib outletConnectionFrom:source
									     to:destination
								  keyPath:keyPath]];
			} else if (action != nil) {
				[builtConnections addObject:[NSNib actionConnectionFrom:source
									     to:destination
									 action:action]];
			} else {
				if (error != NULL) {
					*error = [NSString stringWithFormat:@"connection %lu is neither an outlet (keyPath) "
						  "nor an action", (unsigned long)i];
				}
				[registry release];
				[builtObjects release];
				[builtConnections release];
				return nil;
			}
		}
	}

	{
		NSData *archive = [NSNib archivedDataWithTopLevelObjects:builtObjects
							     connections:([builtConnections count] > 0)
								 ? builtConnections : nil];

		if (archive == nil && error != NULL) {
			*error = @"the archive could not be written";
		}
		[registry release];
		[builtObjects release];
		[builtConnections release];
		return archive;
	}
}

+ (NSData *)archiveFromSourceFile:(NSString *)path error:(NSString **)error
{
	NSData *data = [NSData dataWithContentsOfFile:path];

	if (data == nil) {
		if (error != NULL) {
			*error = [NSString stringWithFormat:@"cannot read %@", path];
		}
		return nil;
	}
	return [self archiveFromSourceData:data error:error];
}

/* ============================================================================================
 * THE DECOMPILER'S DOOR
 * ============================================================================================ */

+ (NSData *)sourceFromArchiveData:(NSData *)archive error:(NSString **)error
{
	NSString *refusal;
	id root;
	NSArray *objects;
	NSArray *connections;
	NSMutableString *text;
	AGNibWriter *writer;
	NSUInteger i;

	if (error != NULL) {
		*error = nil;
	}
	refusal = [NSNib refusalReasonForArchiveData:archive];
	if (refusal != nil) {
		if (error != NULL) {
			*error = refusal;
		}
		return nil;
	}
	root = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSNib supportedClasses]
						     fromData:archive
							error:NULL];
	if (![root isKindOfClass:[NSDictionary class]]) {
		if (error != NULL) {
			*error = @"the archive did not decode";
		}
		return nil;
	}
	objects = [(NSDictionary *)root objectForKey:NSNibTopLevelObjectsKey];
	connections = [(NSDictionary *)root objectForKey:NSNibConnectionsKey];

	/* ONE WRITER FOR THE WHOLE FILE, so that an object's generated name is the same wherever it appears — a constraint
	 * naming its parent and a connection naming the same view must agree, and they only agree if the name table is
	 * shared. */
	writer = [[AGNibWriter alloc] init];
	text = [[NSMutableString alloc] init];
	[text appendString:@"// written by ibtool decompile — edit it and compile it again\n{\n"];
	[text appendFormat:@"  version = %ld;\n", (long)[NSNib formatVersion]];
	[text appendString:@"  objects = (\n"];
	for (i = 0; i < [objects count]; i++) {
		if (![writer writeObject:[objects objectAtIndex:i] indent:@"    " isTopLevel:YES]) {
			break;
		}
	}
	if ([writer error] == nil) {
		[text appendString:[writer takeOutput]];
	}
	[text appendString:@"  );\n"];
	if ([writer error] == nil && [connections count] > 0) {
		[text appendString:@"  connections = (\n"];
		for (i = 0; i < [connections count]; i++) {
			NSDictionary *record = [connections objectAtIndex:i];
			id source = [record objectForKey:NSNibConnectionSourceKey];
			id destination = [record objectForKey:NSNibConnectionDestinationKey];
			NSString *keyPath = [record objectForKey:NSNibConnectionKeyPathKey];
			NSString *action = [record objectForKey:NSNibConnectionActionKey];
			/* **THE PLACEHOLDER HAS A SOURCE SPELLING AND AN ARCHIVE SPELLING.** The archive carries the string
			 * `NSNibFileOwner`; the grammar says `owner`. Writing the archive's spelling would produce a file the
			 * compiler cannot resolve, so the translation is here, where the two vocabularies meet. */
			NSString *from = [source isKindOfClass:[NSString class]]
				? ([source isEqualToString:NSNibFileOwner] ? @"owner" : source)
				: [writer nameFor:source];
			NSString *to = [destination isKindOfClass:[NSString class]]
				? ([destination isEqualToString:NSNibFileOwner] ? @"owner" : destination)
				: [writer nameFor:destination];

			if (keyPath != nil) {
				[text appendFormat:@"    { source = \"%@\"; keyPath = \"%@\"; destination = \"%@\"; }\n",
					from, keyPath, to];
			} else {
				[text appendFormat:@"    { source = \"%@\"; action = \"%@\"; destination = \"%@\"; }\n",
					from, action, to];
			}
		}
		[text appendString:@"  );\n"];
	}
	[text appendString:@"}\n"];

	if ([writer error] != nil) {
		if (error != NULL) {
			*error = [[[writer error] retain] autorelease];
		}
		[writer release];
		[text release];
		return nil;
	}
	[writer release];
	{
		NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];

		[text release];
		return data;
	}
}

@end
