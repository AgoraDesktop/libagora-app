/*
 * predicate_editor — the rule editor's predicate assembly, the row templates, and the editor built on both.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE FOLLOWS THE PREDICATE THROUGH THREE LAYERS, AND EACH LAYER IS MEASURED BY EVALUATION, NOT BY SHAPE.** A
 * rule editor's parts are assembled into a predicate that must EVALUATE the way the delegate meant; a row template's
 * matching is measured by which predicates it accepts and which it refuses; and the predicate editor's round trip
 * (`-setObjectValue:` a predicate, edit a row, `-objectValue` again) is measured by what the second predicate evaluates
 * to — a shape test would pass for a predicate assembled backwards.
 */
#import <AppKit/NSRuleEditor.h>
#import <AppKit/NSPredicateEditor.h>
#import <AppKit/NSPredicateEditorRowTemplate.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSTextField.h>
#import <Foundation/Foundation.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSEntityDescription.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ============================================================================================ *
 * A MODEL, AND A DELEGATE THAT ANSWERS THE PARTS OF TWO KINDS OF CRITERION                      *
 * ============================================================================================ */
@interface AGPerson : NSObject
{
	id _name;
	id _age;
}
- (id)name;
- (void)setName:(id)value;
- (id)age;
- (void)setAge:(id)value;
@end

@implementation AGPerson
- (id)name { return _name; }
- (void)setName:(id)value { [value retain]; [_name release]; _name = value; }
- (id)age { return _age; }
- (void)setAge:(id)value { [value retain]; [_age release]; _age = value; }
- (void)dealloc { [_name release]; [_age release]; [super dealloc]; }
@end

/* THE CRITERION IS A STRING: "name" or "age". The delegate turns it into the parts the rule editor asks for. */
@interface AGPartsDelegate : NSObject <NSRuleEditorDelegate>
{
@public
	id row;			/* NOT retained */
	BOOL useCustomSelector;
	NSComparisonPredicateModifier modifier;
}
@end

@implementation AGPartsDelegate
- (NSInteger)ruleEditor:(NSRuleEditor *)editor
  numberOfChildrenForCriterion:(id)criterion
	     withRowType:(NSRuleEditorRowType)rowType
{
	(void)editor;
	(void)criterion;
	(void)rowType;
	return 0;
}

- (id)ruleEditor:(NSRuleEditor *)editor
	    child:(NSInteger)index
     forCriterion:(id)criterion
      withRowType:(NSRuleEditorRowType)rowType
{
	(void)editor;
	(void)index;
	(void)criterion;
	(void)rowType;
	return nil;
}

- (id)ruleEditor:(NSRuleEditor *)editor displayValueForCriterion:(id)criterion inRow:(NSInteger)rowIndex
{
	(void)editor;
	(void)rowIndex;
	return criterion;
}

- (NSDictionary *)ruleEditor:(NSRuleEditor *)editor
  predicatePartsForCriterion:(id)criterion
	    withDisplayValue:(id)displayValue
		     inRow:(NSInteger)rowIndex
{
	NSMutableDictionary *parts = [NSMutableDictionary dictionary];
	id value = displayValue;

	(void)editor;
	(void)rowIndex;
	[parts setObject:[NSExpression expressionForKeyPath:criterion]
		  forKey:NSRuleEditorPredicateLeftExpression];
	if (useCustomSelector) {
		[parts setObject:@"isEqual:"
			  forKey:NSRuleEditorPredicateCustomSelector];
		[parts setObject:[NSExpression expressionForConstantValue:value]
			  forKey:NSRuleEditorPredicateRightExpression];
		return parts;
	}
	[parts setObject:[NSExpression expressionForConstantValue:value]
		  forKey:NSRuleEditorPredicateRightExpression];
	[parts setObject:[NSNumber numberWithUnsignedInteger:NSEqualToPredicateOperatorType]
		  forKey:NSRuleEditorPredicateOperatorType];
	[parts setObject:[NSNumber numberWithUnsignedInteger:modifier]
		  forKey:NSRuleEditorPredicateComparisonModifier];
	[parts setObject:[NSNumber numberWithUnsignedInteger:0]
		  forKey:NSRuleEditorPredicateOptions];
	return parts;
}
@end

static NSPredicate *matching(void)
{
	return [NSPredicate predicateWithFormat:@"name == \"alice\""];
}

static AGPerson *person(NSString *name, NSInteger age)
{
	AGPerson *who = [[[AGPerson alloc] init] autorelease];

	[who setName:name];
	[who setAge:[NSNumber numberWithInteger:age]];
	return who;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		AGPartsDelegate *parts = [[AGPartsDelegate alloc] init];
		NSRuleEditor *editor = [[NSRuleEditor alloc] init];
		AGPerson *alice = person(@"alice", 30);
		AGPerson *bob = person(@"bob", 40);

		/* --------------------------------------------------------------------------------- *
		 * 1. THE RULE EDITOR ASSEMBLES A COMPARISON FROM THE PARTS                             *
		 * --------------------------------------------------------------------------------- */
		[editor setDelegate:parts];
		[editor setNestingMode:NSRuleEditorNestingModeList];
		[editor addRow:nil];
		[editor setCriteria:[NSArray arrayWithObject:@"name"]
		andDisplayValues:[NSArray arrayWithObject:@"alice"]
		 forRowAtIndex:0];
		{
			NSPredicate *built = [editor predicate];

			check(built != nil && [built isKindOfClass:[NSComparisonPredicate class]],
			      "the parts of one criterion assemble into a comparison predicate");
			check([built evaluateWithObject:alice] && ![built evaluateWithObject:bob],
			      "and it evaluates the way the parts meant");
			check([[editor predicateForRow:0] evaluateWithObject:alice],
			      "predicateForRow: answers that row's predicate");
		}

		/* TWO ROWS ARE AN AND; THE COMPOUND TYPE COMES FROM THE PARTS. */
		[editor addRow:nil];
		[editor setCriteria:[NSArray arrayWithObject:@"age"]
		andDisplayValues:[NSArray arrayWithObject:[NSNumber numberWithInteger:30]]
		 forRowAtIndex:1];
		{
			NSPredicate *both = [editor predicate];

			check([both isKindOfClass:[NSCompoundPredicate class]]
			      && [(NSCompoundPredicate *)both compoundPredicateType] == NSAndPredicateType,
			      "two rows are an AND of their predicates");
			check([both evaluateWithObject:alice] && ![both evaluateWithObject:bob],
			      "which evaluates across both rows");
		}

		/* TWO CRITERIA IN ONE ROW ARE A COMPOUND OF THAT ROW. */
		{
			NSRuleEditor *single = [[NSRuleEditor alloc] init];

			[single setDelegate:parts];
			[single addRow:nil];
			[single setCriteria:[NSArray arrayWithObjects:@"name", @"age", nil]
			andDisplayValues:[NSArray arrayWithObjects:@"alice", [NSNumber numberWithInteger:40], nil]
			 forRowAtIndex:0];
			check([[single predicate] isKindOfClass:[NSCompoundPredicate class]],
			      "a row with two criteria is a compound");
			check([[(NSCompoundPredicate *)[single predicate] subpredicates] count] == 2,
			      "over both criteria");
			check(![[single predicate] evaluateWithObject:alice]
			      && [[single predicate] evaluateWithObject:person(@"alice", 40)],
			      "and its subpredicates are both required");
			[single release];
		}

		/* A CUSTOM SELECTOR PART BUILDS THE CUSTOM-SELECTOR COMPARISON. */
		{
			NSRuleEditor *custom = [[NSRuleEditor alloc] init];

			parts->useCustomSelector = YES;
			[custom setDelegate:parts];
			[custom addRow:nil];
			[custom setCriteria:[NSArray arrayWithObject:@"name"]
			andDisplayValues:[NSArray arrayWithObject:@"alice"]
			 forRowAtIndex:0];
			/* **A CUSTOM-SELECTOR PART IS REFUSED BY NAME, NOT HALF-BUILT.** Foundation's NSComparisonPredicate does
			 * not implement the custom-selector operator (it raises), so the rule editor refuses the part and the
			 * predicate is the empty answer rather than an exception out of a getter. */
			check([custom predicate] == nil,
			      "a custom-selector part is refused and contributes no predicate");
			parts->useCustomSelector = NO;
			[custom release];
		}

		/* AN EMPTY EDITOR HAS NO PREDICATE, AND A PART WITH NO LEFT EXPRESSION CONTRIBUTES NOTHING. */
		{
			NSRuleEditor *empty = [[NSRuleEditor alloc] init];

			check([empty predicate] == nil, "an editor with no rows has no predicate");
			[empty release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 2. THE ROW TEMPLATE                                                                 *
		 * --------------------------------------------------------------------------------- */
		{
			NSPredicateEditorRowTemplate *nameTemplate;
			NSArray *lefts;
			NSArray *operators;

			lefts = [NSArray arrayWithObject:[NSExpression expressionForKeyPath:@"name"]];
			operators = [NSArray arrayWithObjects:
				[NSNumber numberWithUnsignedInteger:NSEqualToPredicateOperatorType],
				[NSNumber numberWithUnsignedInteger:NSBeginsWithPredicateOperatorType], nil];
			nameTemplate = [[[NSPredicateEditorRowTemplate alloc]
				initWithLeftExpressions:lefts
			       rightExpressionAttributeType:NSStringAttributeType
					       modifier:NSDirectPredicateModifier
					      operators:operators
						options:0] autorelease];
			check([[[nameTemplate leftExpressions] objectAtIndex:0] keyPath] != nil
			      && [[[[nameTemplate leftExpressions] objectAtIndex:0] keyPath] isEqual:@"name"],
			      "the template keeps its left expressions");
			check([nameTemplate rightExpressionAttributeType] == NSStringAttributeType
			      && [nameTemplate modifier] == NSDirectPredicateModifier
			      && [[nameTemplate operators] count] == 2 && [nameTemplate options] == 0,
			      "and its attribute type, modifier, operators and options");

			{
				NSArray *views = [nameTemplate templateViews];

				check([views count] == 3, "a template has three views");
				check([[views objectAtIndex:0] isKindOfClass:[NSPopUpButton class]]
				      && [[views objectAtIndex:1] isKindOfClass:[NSPopUpButton class]]
				      && [[views objectAtIndex:2] isKindOfClass:[NSTextField class]],
				      "a left popup, an operator popup and a right field");
				check([[[views objectAtIndex:0] itemTitles] containsObject:@"name"],
				      "the left popup offers the expression's key path");
				check([[[views objectAtIndex:1] itemTitles] containsObject:@"is"]
				      && [[[views objectAtIndex:1] itemTitles] containsObject:@"begins with"],
				      "and the operator popup the operator titles");
				check([views isEqualToArray:[nameTemplate templateViews]],
				      "and the same views are answered on a second ask");
			}

			{
				NSPredicate *matching = [NSPredicate predicateWithFormat:@"name == \"alice\""];
				NSPredicate *wrongLeft = [NSPredicate predicateWithFormat:@"age == 30"];
				NSPredicate *wrongOperator = [NSPredicate predicateWithFormat:@"name CONTAINS \"al\""];

				check([nameTemplate matchForPredicate:matching] == nameTemplate,
				      "the template matches a comparison with its key path and operator");
				check([nameTemplate matchForPredicate:wrongLeft] == nil,
				      "and refuses a comparison on another key path");
				check([nameTemplate matchForPredicate:wrongOperator] == nil,
				      "and one whose operator it does not allow");
				[nameTemplate setPredicate:matching];
				check([[[[nameTemplate templateViews] objectAtIndex:2] stringValue] isEqual:@"alice"],
				      "setPredicate: puts the right-hand value in the field");
			}

			{
				NSPredicateEditorRowTemplate *compound;
				NSArray *types = [NSArray arrayWithObject:
					[NSNumber numberWithUnsignedInteger:NSOrPredicateType]];

				compound = [[[NSPredicateEditorRowTemplate alloc] initWithCompoundTypes:types] autorelease];
				check([[compound compoundTypes] count] == 1, "a compound template keeps its types");
				check([[compound predicateWithSubpredicates:
					 [NSArray arrayWithObjects:matching(), matching(), nil]] isKindOfClass:
					[NSCompoundPredicate class]],
				      "and builds a compound over its subpredicates");
				check([compound matchForPredicate:
					 [NSCompoundPredicate orPredicateWithSubpredicates:
					  [NSArray arrayWithObjects:matching(), matching(), nil]]] == compound,
				      "it matches a compound of its type");
				check([compound matchForPredicate:matching()] == nil,
				      "but not a comparison");
				check([[compound displayableSubpredicatesOfPredicate:
					 [NSCompoundPredicate orPredicateWithSubpredicates:
					  [NSArray arrayWithObjects:matching(), matching(), nil]]] count] == 2,
				      "and displays a matching compound's subpredicates");
			}
		}

		/* THE ATTRIBUTE-DRIVEN FACTORY. */
		{
			NSEntityDescription *entity = [[[NSEntityDescription alloc] init] autorelease];
			NSAttributeDescription *nameAttribute = [[[NSAttributeDescription alloc] init] autorelease];
			NSAttributeDescription *ageAttribute = [[[NSAttributeDescription alloc] init] autorelease];
			NSArray *templates;

			[entity setName:@"Person"];
			[nameAttribute setName:@"name"];
			[nameAttribute setAttributeType:NSStringAttributeType];
			[ageAttribute setName:@"age"];
			[ageAttribute setAttributeType:NSInteger32AttributeType];
			[entity setProperties:[NSArray arrayWithObjects:nameAttribute, ageAttribute, nil]];
			templates = [NSPredicateEditorRowTemplate
				templatesWithAttributeKeyPaths:[NSArray arrayWithObjects:@"name", @"missing", nil]
					    inEntityDescription:entity];
			check([templates count] == 1,
			      "one template per key path the entity describes, and none for a key path it does not");
			check([[templates objectAtIndex:0] rightExpressionAttributeType] == NSStringAttributeType,
			      "with the attribute's own type");
			check([[[templates objectAtIndex:0] operators] count] > 2,
			      "and the string operators for a string attribute");
		}

		/* --------------------------------------------------------------------------------- *
		 * 3. THE PREDICATE EDITOR                                                             *
		 * --------------------------------------------------------------------------------- */
		{
			NSPredicateEditor *predicateEditor = [[NSPredicateEditor alloc] init];
			NSPredicateEditorRowTemplate *nameTemplate = [[[NSPredicateEditorRowTemplate alloc]
				initWithLeftExpressions:[NSArray arrayWithObject:[NSExpression expressionForKeyPath:@"name"]]
			       rightExpressionAttributeType:NSStringAttributeType
					       modifier:NSDirectPredicateModifier
					      operators:[NSArray arrayWithObjects:
						[NSNumber numberWithUnsignedInteger:NSEqualToPredicateOperatorType],
						[NSNumber numberWithUnsignedInteger:NSBeginsWithPredicateOperatorType], nil]
						options:0] autorelease];
			NSPredicateEditorRowTemplate *ageTemplate = [[[NSPredicateEditorRowTemplate alloc]
				initWithLeftExpressions:[NSArray arrayWithObject:[NSExpression expressionForKeyPath:@"age"]]
			       rightExpressionAttributeType:NSInteger32AttributeType
					       modifier:NSDirectPredicateModifier
					      operators:[NSArray arrayWithObject:
						[NSNumber numberWithUnsignedInteger:NSEqualToPredicateOperatorType]]
						options:0] autorelease];

			[predicateEditor setRowTemplates:[NSArray arrayWithObjects:nameTemplate, ageTemplate, nil]];
			check([[predicateEditor rowTemplates] count] == 2, "the editor keeps its templates");

			[predicateEditor setObjectValue:[NSPredicate predicateWithFormat:@"name == \"alice\""]];
			check([predicateEditor numberOfRows] == 1, "a predicate becomes one row");
			{
				NSPredicate *round = [predicateEditor objectValue];

				check([round isKindOfClass:[NSComparisonPredicate class]],
				      "and objectValue answers a comparison again");
				check([round evaluateWithObject:alice] && ![round evaluateWithObject:bob],
				      "which evaluates like the predicate it came from");
			}

			/* EDIT THE ROW'S DISPLAY VALUE: THE PREDICATE FOLLOWS. */
			[predicateEditor setCriteria:[predicateEditor criteriaForRow:0]
				    andDisplayValues:[NSArray arrayWithObject:@"bob"]
					 forRowAtIndex:0];
			{
				NSPredicate *edited = [predicateEditor objectValue];

				check([edited evaluateWithObject:bob] && ![edited evaluateWithObject:alice],
				      "editing a row's display value changes what the predicate evaluates to");
			}

			/* AN OPERATOR OTHER THAN "is" SURVIVES THE ROUND TRIP. */
			[predicateEditor setObjectValue:[NSPredicate predicateWithFormat:@"name BEGINSWITH \"al\""]];
			{
				NSPredicate *round = [predicateEditor objectValue];

				check([round isKindOfClass:[NSComparisonPredicate class]]
				      && [(NSComparisonPredicate *)round predicateOperatorType]
					 == NSBeginsWithPredicateOperatorType,
				      "the operator survives the round trip");
				check([round evaluateWithObject:alice] && ![round evaluateWithObject:bob],
				      "and it still means what it meant");
			}

			/* AN AND OF TWO COMPARISONS BECOMES TWO ROWS. */
			[predicateEditor setObjectValue:
				[NSPredicate predicateWithFormat:@"name == \"alice\" AND age == 30"]];
			check([predicateEditor numberOfRows] == 2, "an AND of two comparisons becomes two rows");
			{
				NSPredicate *round = [predicateEditor objectValue];

				check([round evaluateWithObject:alice] && ![round evaluateWithObject:bob],
				      "and the reassembled conjunction still evaluates");
			}

			/* A PREDICATE NO TEMPLATE NAMES HAS NO ROWS; A NEW ROW STARTS FROM THE FIRST TEMPLATE. */
			[predicateEditor setObjectValue:[NSPredicate predicateWithFormat:@"nickname == \"al\""]];
			check([predicateEditor numberOfRows] == 0,
			      "a comparison no template names builds no row");
			[predicateEditor addRow:nil];
			check([predicateEditor numberOfRows] == 1, "and a row the user adds is a row");
			{
				NSPredicate *fresh = [predicateEditor objectValue];

				check([fresh isKindOfClass:[NSComparisonPredicate class]]
				      && [[[(NSComparisonPredicate *)fresh leftExpression] keyPath] isEqual:@"name"],
				      "built from the first template's first expression");
			}

			[predicateEditor release];
		}

		printf("predicate_editor: %d case(s) failed\n", s_failed);
		[editor release];
		[parts release];
	}
	return s_failed != 0;
}
