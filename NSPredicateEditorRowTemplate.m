/*
 * NSPredicateEditorRowTemplate.m — the vocabulary, the three controls, and the two matching questions.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **MATCHING IS A QUESTION ABOUT PARTS, NOT ABOUT TEXT.** A comparison predicate matches when its operator is one the
 * template allows, its modifier and options are the template's, and its left expression is one the template names — by
 * KEY PATH when the expression is a key path, by equality otherwise. A compound predicate matches when its type is one
 * of the template's compound types. Everything else is "no", which is what lets an editor try its templates in order.
 *
 * **THE VIEWS ARE BUILT FROM THE VOCABULARY AND NEVER FROM THE PREDICATE.** One set of controls per template, made on
 * first ask; `-setPredicate:` then SELECTS the items and fills the field, so a row's views survive a new predicate and a
 * caller that holds them (a row being rebuilt) keeps the same objects.
 */
#import <AppKit/NSPredicateEditorRowTemplate.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSTextField.h>
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSString.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSAttributeDescription.h>

typedef struct {
	NSPredicateOperatorType type;
	const char *title;
} FNOperatorTitle;

/* THE OPERATOR VOCABULARY, one table, because the popup's titles and the matching question must agree about which
 * operator an item stands for. */
static const FNOperatorTitle fn_operator_titles[] = {
	{ NSEqualToPredicateOperatorType, "is" },
	{ NSNotEqualToPredicateOperatorType, "is not" },
	{ NSLessThanPredicateOperatorType, "<" },
	{ NSLessThanOrEqualToPredicateOperatorType, "<=" },
	{ NSGreaterThanPredicateOperatorType, ">" },
	{ NSGreaterThanOrEqualToPredicateOperatorType, ">=" },
	{ NSBeginsWithPredicateOperatorType, "begins with" },
	{ NSEndsWithPredicateOperatorType, "ends with" },
	{ NSContainsPredicateOperatorType, "contains" },
	{ NSLikePredicateOperatorType, "like" },
	{ NSMatchesPredicateOperatorType, "matches" },
	{ NSInPredicateOperatorType, "in" },
};

static NSString *fn_operator_title(NSPredicateOperatorType type)
{
	NSUInteger i;

	for (i = 0; i < sizeof(fn_operator_titles) / sizeof(fn_operator_titles[0]); i++) {
		if (fn_operator_titles[i].type == type) {
			return [NSString stringWithUTF8String:fn_operator_titles[i].title];
		}
	}
	return [NSString stringWithFormat:@"operator %lu", (unsigned long)type];
}

/* THE EXPRESSION'S NAME, as a row shows it: the key path when it is one, the description otherwise. */
static NSString *fn_expression_title(NSExpression *expression)
{
	NSString *keyPath = [expression keyPath];

	return (keyPath != nil) ? keyPath : [expression description];
}

/* A KEY PATH EXPRESSION IS COMPARED BY ITS PATH: two `expressionForKeyPath:@"name"` values are the same left-hand
 * side even though they are not the same object. */
static BOOL fn_same_expression(NSExpression *left, NSExpression *right)
{
	if (left == right) {
		return YES;
	}
	if (left == nil || right == nil) {
		return NO;
	}
	if ([left expressionType] != [right expressionType]) {
		return NO;
	}
	if ([left keyPath] != nil || [right keyPath] != nil) {
		return [[left keyPath] isEqual:[right keyPath]];
	}
	return [left isEqual:right];
}

static BOOL fn_operator_allowed(NSArray *operators, NSPredicateOperatorType type)
{
	NSUInteger i;

	if (operators == nil) {
		return YES;	/* no restriction: the template takes any comparison */
	}
	for (i = 0; i < [operators count]; i++) {
		if ([[operators objectAtIndex:i] unsignedIntegerValue] == (NSUInteger)type) {
			return YES;
		}
	}
	return NO;
}

/* THE OPERATORS A TYPED ATTRIBUTE CAN BEAR. A string has the text ones, a number and a date the ordering ones, and
 * anything else equality alone — the narrowest honest reading of "what can this value be compared with". */
static NSArray *fn_operators_for_attribute_type(NSAttributeType type)
{
	NSMutableArray *operators = [NSMutableArray array];

	switch (type) {
	case NSStringAttributeType:
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSEqualToPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSNotEqualToPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSContainsPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSBeginsWithPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSEndsWithPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSLikePredicateOperatorType]];
		break;
	case NSInteger16AttributeType:
	case NSInteger32AttributeType:
	case NSInteger64AttributeType:
	case NSDecimalAttributeType:
	case NSDoubleAttributeType:
	case NSFloatAttributeType:
	case NSBooleanAttributeType:
	case NSDateAttributeType:
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSEqualToPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSNotEqualToPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSLessThanPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSLessThanOrEqualToPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSGreaterThanPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSGreaterThanOrEqualToPredicateOperatorType]];
		break;
	default:
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSEqualToPredicateOperatorType]];
		[operators addObject:[NSNumber numberWithUnsignedInteger:NSNotEqualToPredicateOperatorType]];
		break;
	}
	return operators;
}

@implementation NSPredicateEditorRowTemplate

+ (NSArray *)templatesWithAttributeKeyPaths:(NSArray *)keyPaths
		      inEntityDescription:(NSEntityDescription *)entity
{
	NSMutableArray *templates = [NSMutableArray array];
	NSDictionary *attributes;
	NSUInteger i;

	if (keyPaths == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"+templatesWithAttributeKeyPaths:inEntityDescription: needs key paths"];
	}
	attributes = (entity != nil) ? [entity attributesByName] : nil;
	for (i = 0; i < [keyPaths count]; i++) {
		NSString *keyPath = [keyPaths objectAtIndex:i];
		NSAttributeDescription *attribute = [attributes objectForKey:keyPath];
		NSPredicateEditorRowTemplate *template;

		if (attribute == nil) {
			continue;	/* a key path the entity does not describe is not a row this template set can offer */
		}
		template = [[[self alloc]
			initWithLeftExpressions:[NSArray arrayWithObject:[NSExpression expressionForKeyPath:keyPath]]
		     rightExpressionAttributeType:[attribute attributeType]
				     modifier:NSDirectPredicateModifier
				    operators:fn_operators_for_attribute_type([attribute attributeType])
				      options:0] autorelease];
		[templates addObject:template];
	}
	return templates;
}

- (id)initWithLeftExpressions:(NSArray *)leftExpressions
	     rightExpressions:(NSArray *)rightExpressions
		     modifier:(NSComparisonPredicateModifier)modifier
		    operators:(NSArray *)operators
		      options:(NSUInteger)options
{
	self = [super init];
	if (self != nil) {
		_leftExpressions = [leftExpressions copy];
		_rightExpressions = [rightExpressions copy];
		_modifier = modifier;
		_operators = [operators copy];
		_options = options;
	}
	return self;
}

- (id)initWithLeftExpressions:(NSArray *)leftExpressions
      rightExpressionAttributeType:(NSAttributeType)attributeType
		     modifier:(NSComparisonPredicateModifier)modifier
		    operators:(NSArray *)operators
		      options:(NSUInteger)options
{
	self = [super init];
	if (self != nil) {
		_leftExpressions = [leftExpressions copy];
		_rightExpressionAttributeType = attributeType;
		_modifier = modifier;
		_operators = [operators copy];
		_options = options;
	}
	return self;
}

- (id)initWithCompoundTypes:(NSArray *)compoundTypes
{
	self = [super init];
	if (self != nil) {
		_compoundTypes = [compoundTypes copy];
	}
	return self;
}

- (void)dealloc
{
	[_leftExpressions release];
	[_rightExpressions release];
	[_operators release];
	[_compoundTypes release];
	[_templateViews release];
	[_predicate release];
	[super dealloc];
}

- (NSArray *)leftExpressions
{
	return _leftExpressions;
}

- (NSArray *)rightExpressions
{
	return _rightExpressions;
}

- (NSAttributeType)rightExpressionAttributeType
{
	return _rightExpressionAttributeType;
}

- (NSComparisonPredicateModifier)modifier
{
	return _modifier;
}

- (NSArray *)operators
{
	return _operators;
}

- (NSUInteger)options
{
	return _options;
}

- (NSArray *)compoundTypes
{
	return _compoundTypes;
}

/* ---- THE THREE CONTROLS ------------------------------------------------------------------------------- */

- (NSArray *)templateViews
{
	NSUInteger i;

	if (_templateViews != nil) {
		return _templateViews;
	}
	{
		NSPopUpButton *left = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
		NSPopUpButton *operatorPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
		NSTextField *right = [[NSTextField alloc] initWithFrame:NSZeroRect];
		NSMutableArray *leftTitles = [NSMutableArray array];
		NSMutableArray *operatorTitles = [NSMutableArray array];

		for (i = 0; i < [_leftExpressions count]; i++) {
			[leftTitles addObject:fn_expression_title([_leftExpressions objectAtIndex:i])];
		}
		for (i = 0; i < [_operators count]; i++) {
			[operatorTitles addObject:fn_operator_title((NSPredicateOperatorType)
				[[_operators objectAtIndex:i] unsignedIntegerValue])];
		}
		[left addItemsWithTitles:leftTitles];
		[operatorPopup addItemsWithTitles:operatorTitles];
		_templateViews = [[NSArray alloc] initWithObjects:left, operatorPopup, right, nil];
		[left release];
		[operatorPopup release];
		[right release];
	}
	return _templateViews;
}

/* **THE PREDICATE FILLS THE VIEWS IT ALREADY HAS.** The left popup selects the expression the predicate names, the
 * operator popup selects its operator, and the field shows the right-hand constant — a row's controls are not rebuilt
 * for a new predicate, which is what lets a row being re-used keep its views. */
- (void)setPredicate:(NSPredicate *)predicate
{
	NSPopUpButton *left;
	NSPopUpButton *operatorPopup;
	NSTextField *right;
	NSUInteger i;

	[predicate retain];
	[_predicate release];
	_predicate = predicate;
	if (![predicate isKindOfClass:[NSComparisonPredicate class]]) {
		return;
	}
	(void)[self templateViews];
	left = [[self templateViews] objectAtIndex:0];
	operatorPopup = [[self templateViews] objectAtIndex:1];
	right = [[self templateViews] objectAtIndex:2];
	{
		NSComparisonPredicate *comparison = (NSComparisonPredicate *)predicate;

		for (i = 0; i < [_leftExpressions count]; i++) {
			if (fn_same_expression([_leftExpressions objectAtIndex:i], [comparison leftExpression])) {
				[left selectItemAtIndex:(NSInteger)i];
				break;
			}
		}
		for (i = 0; i < [_operators count]; i++) {
			if ((NSPredicateOperatorType)[[_operators objectAtIndex:i] unsignedIntegerValue]
			    == [comparison predicateOperatorType]) {
				[operatorPopup selectItemAtIndex:(NSInteger)i];
				break;
			}
		}
		{
			id value = [[comparison rightExpression] constantValue];

			[right setStringValue:(value != nil) ? [value description] : @""];
		}
	}
}

/* ---- THE TWO QUESTIONS -------------------------------------------------------------------------------- */

- (NSPredicate *)predicateWithSubpredicates:(NSArray *)subpredicates
{
	NSCompoundPredicateType type = NSAndPredicateType;

	if ([_compoundTypes count] > 0) {
		type = (NSCompoundPredicateType)[[_compoundTypes objectAtIndex:0] unsignedIntegerValue];
	}
	return [[[NSCompoundPredicate alloc] initWithType:type subpredicates:subpredicates] autorelease];
}

- (NSArray *)displayableSubpredicatesOfPredicate:(NSPredicate *)predicate
{
	if ([self matchForPredicate:predicate] == nil) {
		return nil;
	}
	if (![predicate isKindOfClass:[NSCompoundPredicate class]]) {
		return nil;
	}
	return [(NSCompoundPredicate *)predicate subpredicates];
}

/* **A COMPOUND MATCHES BY ITS TYPE AND A COMPARISON BY ITS PARTS.** The operator must be one the template allows, the
 * modifier and options must be the template's, and the left expression must be one it names. */
- (NSPredicateEditorRowTemplate *)matchForPredicate:(NSPredicate *)predicate
{
	NSUInteger i;

	if (predicate == nil) {
		return nil;
	}
	if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
		NSCompoundPredicateType type = [(NSCompoundPredicate *)predicate compoundPredicateType];

		for (i = 0; i < [_compoundTypes count]; i++) {
			if ((NSCompoundPredicateType)[[_compoundTypes objectAtIndex:i] unsignedIntegerValue] == type) {
				return self;
			}
		}
		return nil;
	}
	if (![predicate isKindOfClass:[NSComparisonPredicate class]]) {
		return nil;
	}
	{
		NSComparisonPredicate *comparison = (NSComparisonPredicate *)predicate;

		if ([comparison comparisonPredicateModifier] != _modifier) {
			return nil;
		}
		if ([comparison options] != _options) {
			return nil;
		}
		if (!fn_operator_allowed(_operators, [comparison predicateOperatorType])) {
			return nil;
		}
		if ([_leftExpressions count] == 0) {
			return nil;	/* a row with no left-hand vocabulary cannot represent a comparison */
		}
		for (i = 0; i < [_leftExpressions count]; i++) {
			if (fn_same_expression([_leftExpressions objectAtIndex:i], [comparison leftExpression])) {
				return self;
			}
		}
	}
	return nil;
}

@end
