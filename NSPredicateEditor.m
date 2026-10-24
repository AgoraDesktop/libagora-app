/*
 * NSPredicateEditor.m — the rows from a predicate, and the parts from a row.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CRITERION IS THE ROW'S MEMORY.** The rule editor stores a criterion per row and a display value per criterion,
 * and it treats both as opaque — so the predicate editor's criterion is a dictionary of the comparison's PARTS (key
 * path, operator, modifier, options) and the display value is the right-hand constant. Nothing is kept in a parallel
 * array beside the rows, which is why a row removed by the user cannot desynchronise anything.
 *
 * **THE PARTS DOOR IS WHERE THE ROW BECOMES A PREDICATE.** `-ruleEditor:predicatePartsForCriterion:withDisplayValue:
 * inRow:` answers the four parts the base class needs, with the DISPLAY VALUE substituted as the right-hand side — so
 * editing the row changes the predicate, which is the entire point of an editor.
 */
#import <AppKit/NSPredicateEditor.h>
#import <AppKit/NSPredicateEditorRowTemplate.h>
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSString.h>

/* THE KEYS A ROW'S CRITERION CARRIES. Private, because a criterion is opaque to everything but this class. */
static NSString * const FNPairKeyPath = @"NSPredicateEditorKeyPath";
static NSString * const FNPairOperator = @"NSPredicateEditorOperator";
static NSString * const FNPairModifier = @"NSPredicateEditorModifier";
static NSString * const FNPairOptions = @"NSPredicateEditorOptions";

/* THE TEMPLATE THAT NAMES A KEY PATH, so a row built from a predicate can be answered back with its own vocabulary. */
static NSPredicateEditorRowTemplate *fn_template_for_key_path(NSArray *templates, NSString *keyPath)
{
	NSUInteger i;

	for (i = 0; i < [templates count]; i++) {
		NSPredicateEditorRowTemplate *template = [templates objectAtIndex:i];
		NSArray *lefts = [template leftExpressions];
		NSUInteger j;

		for (j = 0; j < [lefts count]; j++) {
			if ([[[lefts objectAtIndex:j] keyPath] isEqual:keyPath]) {
				return template;
			}
		}
	}
	return nil;
}

@implementation NSPredicateEditor

- (id)init
{
	self = [super init];
	if (self != nil) {
		/* THE DELEGATE IS NOT RETAINED (the rule editor's own rule), so this is not a cycle; it is how a predicate
		 * editor supplies the parts the base class assembles. */
		[self setDelegate:self];
	}
	return self;
}

- (NSArray *)rowTemplates
{
	return _rowTemplates;
}

- (void)setRowTemplates:(NSArray *)rowTemplates
{
	if (rowTemplates == _rowTemplates || [rowTemplates isEqual:_rowTemplates]) {
		return;
	}
	[rowTemplates retain];
	[_rowTemplates release];
	_rowTemplates = rowTemplates;
	if ([[self objectValue] isKindOfClass:[NSPredicate class]]) {
		[self setObjectValue:[self objectValue]];
	}
}

/* ---- THE PREDICATE IN, THE ROWS OUT ------------------------------------------------------------------ */

/* **ONE ROW PER COMPARISON; AN AND/OR COMPOUND'S SUBPREDICATES BECOME ROWS.** A NOT compound and a predicate no
 * template matches are skipped — half a predicate is not a predicate, and a row nothing can represent would edit into
 * nonsense. */
- (void)fn_buildRowsFromPredicate:(NSPredicate *)predicate
{
	NSMutableArray *predicates = [NSMutableArray array];
	NSUInteger i;

	if ([predicate isKindOfClass:[NSCompoundPredicate class]]
	    && [[(NSCompoundPredicate *)predicate subpredicates] count] > 0
	    && ([(NSCompoundPredicate *)predicate compoundPredicateType] == NSAndPredicateType
		|| [(NSCompoundPredicate *)predicate compoundPredicateType] == NSOrPredicateType)) {
		[predicates addObjectsFromArray:[(NSCompoundPredicate *)predicate subpredicates]];
	} else {
		[predicates addObject:predicate];
	}
	while ([self numberOfRows] > 0) {
		[self removeRowAtIndex:[self numberOfRows] - 1];
	}
	for (i = 0; i < [predicates count]; i++) {
		NSComparisonPredicate *comparison = [predicates objectAtIndex:i];
		NSPredicateEditorRowTemplate *template;
		NSMutableDictionary *criterion;
		NSString *keyPath;
		id value;

		if (![comparison isKindOfClass:[NSComparisonPredicate class]]) {
			continue;
		}
		keyPath = [[comparison leftExpression] keyPath];
		template = fn_template_for_key_path(_rowTemplates, keyPath);
		if (template == nil) {
			continue;	/* no template can show this comparison, so no row can represent it */
		}
		criterion = [NSMutableDictionary dictionary];
		[criterion setObject:(keyPath != nil ? (id)keyPath : (id)[[comparison leftExpression] description])
			      forKey:FNPairKeyPath];
		[criterion setObject:[NSNumber numberWithUnsignedInteger:[comparison predicateOperatorType]]
			      forKey:FNPairOperator];
		[criterion setObject:[NSNumber numberWithUnsignedInteger:[comparison comparisonPredicateModifier]]
			      forKey:FNPairModifier];
		[criterion setObject:[NSNumber numberWithUnsignedInteger:[comparison options]]
			      forKey:FNPairOptions];
		value = [[comparison rightExpression] constantValue];
		[self addRow:nil];
		[self setCriteria:[NSArray arrayWithObject:criterion]
		andDisplayValues:[NSArray arrayWithObject:(value != nil ? value : @"")]
		 forRowAtIndex:[self numberOfRows] - 1];
	}
}

- (void)setObjectValue:(id)objectValue
{
	if (![objectValue isKindOfClass:[NSPredicate class]]) {
		[super setObjectValue:objectValue];
		return;
	}
	[self fn_buildRowsFromPredicate:(NSPredicate *)objectValue];
}

- (id)objectValue
{
	return [self predicate];
}

/* ---- THE DELEGATE DOORS: A ROW HAS ONE CRITERION, AND IT COMES FROM THE FIRST TEMPLATE --------------- */

/* THE CRITERION A NEW ROW STARTS WITH: the first template's first expression and operator, an empty right-hand value.
 * It is a criterion of THIS editor's shape (the private keys above), which is what the parts door below answers. */
- (NSMutableDictionary *)fn_defaultCriterion
{
	NSPredicateEditorRowTemplate *template;
	NSMutableDictionary *criterion;
	NSArray *lefts;
	NSString *keyPath;

	if ([_rowTemplates count] == 0) {
		return nil;
	}
	template = [_rowTemplates objectAtIndex:0];
	lefts = [template leftExpressions];
	keyPath = ([lefts count] > 0) ? [[lefts objectAtIndex:0] keyPath] : nil;
	criterion = [NSMutableDictionary dictionary];
	[criterion setObject:(keyPath != nil ? (id)keyPath : (id)@"") forKey:FNPairKeyPath];
	[criterion setObject:[NSNumber numberWithUnsignedInteger:([[template operators] count] > 0)
			      ? (NSUInteger)[[[template operators] objectAtIndex:0] unsignedIntegerValue]
			      : (NSUInteger)NSEqualToPredicateOperatorType]
		      forKey:FNPairOperator];
	[criterion setObject:[NSNumber numberWithUnsignedInteger:[template modifier]] forKey:FNPairModifier];
	[criterion setObject:[NSNumber numberWithUnsignedInteger:[template options]] forKey:FNPairOptions];
	return criterion;
}

/* **ONE CRITERION PER ROW, AND A CRITERION HAS NO CHILDREN.** The rule editor asks this to fill a new row; answering one
 * root criterion is what makes a row the user adds a real comparison instead of an empty band. */
- (NSInteger)ruleEditor:(NSRuleEditor *)editor
  numberOfChildrenForCriterion:(id)criterion
	     withRowType:(NSRuleEditorRowType)rowType
{
	(void)editor;
	(void)rowType;
	if (criterion == nil) {
		return ([self fn_defaultCriterion] != nil) ? 1 : 0;
	}
	return 0;
}

- (id)ruleEditor:(NSRuleEditor *)editor
	    child:(NSInteger)index
     forCriterion:(id)criterion
      withRowType:(NSRuleEditorRowType)rowType
{
	(void)editor;
	(void)rowType;
	if (criterion != nil || index != 0) {
		return nil;
	}
	return [self fn_defaultCriterion];
}

- (id)ruleEditor:(NSRuleEditor *)editor displayValueForCriterion:(id)criterion inRow:(NSInteger)row
{
	(void)editor;
	(void)criterion;
	(void)row;
	return @"";	/* a new row's right-hand value starts empty; -setObjectValue: fills it from the predicate */
}

/* ---- THE PARTS DOOR, WHICH IS WHY THERE IS NO SECOND ASSEMBLY --------------------------------------- */

- (NSDictionary *)ruleEditor:(NSRuleEditor *)editor
    predicatePartsForCriterion:(id)criterion
	      withDisplayValue:(id)displayValue
		       inRow:(NSInteger)row
{
	NSMutableDictionary *parts;

	(void)editor;
	(void)row;
	if (![criterion isKindOfClass:[NSDictionary class]]) {
		return nil;	/* a criterion this editor did not build: it has no parts to give */
	}
	{
		NSDictionary *held = (NSDictionary *)criterion;
		NSString *keyPath = [held objectForKey:FNPairKeyPath];

		if (keyPath == nil) {
			return nil;
		}
		parts = [NSMutableDictionary dictionary];
		[parts setObject:[NSExpression expressionForKeyPath:keyPath]
			  forKey:NSRuleEditorPredicateLeftExpression];
		[parts setObject:[NSExpression expressionForConstantValue:displayValue]
			  forKey:NSRuleEditorPredicateRightExpression];
		[parts setObject:[held objectForKey:FNPairOperator]
			  forKey:NSRuleEditorPredicateOperatorType];
		[parts setObject:[held objectForKey:FNPairModifier]
			  forKey:NSRuleEditorPredicateComparisonModifier];
		[parts setObject:[held objectForKey:FNPairOptions]
			  forKey:NSRuleEditorPredicateOptions];
	}
	return parts;
}

@end
