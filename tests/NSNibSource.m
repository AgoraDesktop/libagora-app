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

	if (![scanner scanDouble:&x]) {
		return NO;
	}
	if (![scanner scanDouble:&y]) {
		return NO;
	}
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
					if ([key isEqualToString:@"bounds"] && [object respondsToSelector:@selector(setBoundsSize:)]) {
						[object setBoundsSize:rect.size];
						continue;
					}
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

@end
