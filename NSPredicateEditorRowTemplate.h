/*
 * NSPredicateEditorRowTemplate.h — one row of a predicate editor: which expressions it compares, with what, and how.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A TEMPLATE IS THE VOCABULARY OF ONE ROW.** It names the left-hand expressions the row may compare (key paths, in
 * the common case), the right-hand expressions or the ATTRIBUTE TYPE of the right-hand field, the comparison modifier,
 * the operators it allows, the comparison options, and — for a row that is a CONJUNCTION — the compound types it may
 * stand for. `-predicateWithSubpredicates:` builds the compound predicate such a row means, and `-matchForPredicate:`
 * answers whether the template can represent a given predicate, which is how a predicate is taken apart into rows.
 *
 * **`-templateViews` IS THE EDITOR'S PART, NOT THIS CLASS'S.** It answers the three controls a row shows — left
 * expression, operator, right value — built from the vocabulary above, and `-setPredicate:` puts a predicate's parts
 * into them. Nothing here lays the views out or runs them: that is the row's job, and this tier has no predicate
 * editor row view to do it.
 *
 * **`+templatesWithAttributeKeyPaths:inEntityDescription:` IS REAL AND NEEDS CORE DATA.** The attribute key paths are
 * looked up in the entity's `-attributesByName`, and each becomes a template whose right-hand type is the attribute's
 * own and whose operators are the ones that type can bear (a string compares with contains/begins/ends, a number with
 * the ordering operators). A key path the entity does not name is skipped rather than turned into a template that could
 * never match.
 */
#ifndef APPKIT_NSPREDICATEEDITORROWTEMPLATE_H
#define APPKIT_NSPREDICATEEDITORROWTEMPLATE_H

#import <CoreData/NSAttributeDescription.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSEntityDescription;
@class NSPredicate;
@class NSString;

@interface NSPredicateEditorRowTemplate : NSObject
{
	NSArray *_leftExpressions;		/* COPIED: the expressions the left-hand popup offers */
	NSArray *_rightExpressions;		/* COPIED: constants, for a template built with them */
	NSAttributeType _rightExpressionAttributeType;	/* the type of the right-hand field's value */
	NSComparisonPredicateModifier _modifier;	/* COPIED from the initialiser; a number */
	NSArray *_operators;			/* COPIED: NSNumber-wrapped NSPredicateOperatorTypes */
	NSUInteger _options;			/* the comparison options */
	NSArray *_compoundTypes;		/* COPIED: NSNumber-wrapped NSCompoundPredicateTypes */
	NSArray *_templateViews;		/* RETAINED, built on first ask */
	NSPredicate *_predicate;		/* RETAINED: what -setPredicate: was last given */
}

/* THE ATTRIBUTE-DRIVEN FACTORY: one template per key path the entity describes. */
+ (NSArray *)templatesWithAttributeKeyPaths:(NSArray *)keyPaths
		      inEntityDescription:(NSEntityDescription *)entity;

/* THE TWO SHAPES OF A ROW: expressions on the right, or an attribute type for the right-hand field; and the compound
 * shape, where the row stands for a NOT/AND/OR of its subpredicates. */
- (id)initWithLeftExpressions:(NSArray *)leftExpressions
	     rightExpressions:(NSArray *)rightExpressions
		     modifier:(NSComparisonPredicateModifier)modifier
		    operators:(NSArray *)operators
		      options:(NSUInteger)options;
- (id)initWithLeftExpressions:(NSArray *)leftExpressions
      rightExpressionAttributeType:(NSAttributeType)attributeType
		     modifier:(NSComparisonPredicateModifier)modifier
		    operators:(NSArray *)operators
		      options:(NSUInteger)options;
- (id)initWithCompoundTypes:(NSArray *)compoundTypes;

/* THE VOCABULARY, ANSWERED BACK. */
- (nullable NSArray *)leftExpressions;
- (nullable NSArray *)rightExpressions;
- (NSAttributeType)rightExpressionAttributeType;
- (NSComparisonPredicateModifier)modifier;
- (nullable NSArray *)operators;
- (NSUInteger)options;
- (nullable NSArray *)compoundTypes;

/* THE THREE CONTROLS: left expression, operator, right value — made on first ask and kept. */
- (NSArray *)templateViews;

/* PUT A PREDICATE INTO THE VIEWS: the left expression it names, the operator it uses, and its right-hand constant. */
- (void)setPredicate:(NSPredicate *)predicate;

/* THE ROW'S MEANING: a compound predicate over the subpredicates, of the template's first compound type (AND when it
 * names none). */
- (NSPredicate *)predicateWithSubpredicates:(NSArray *)subpredicates;

/* THE PREDICATE'S PARTS, for a compound the template can represent; nil otherwise. */
- (nullable NSArray *)displayableSubpredicatesOfPredicate:(NSPredicate *)predicate;

/* SELF WHEN THE TEMPLATE CAN REPRESENT THE PREDICATE, nil when it cannot. */
- (nullable NSPredicateEditorRowTemplate *)matchForPredicate:(NSPredicate *)predicate;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPREDICATEEDITORROWTEMPLATE_H */
