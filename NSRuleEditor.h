/*
 * NSRuleEditor.h — A LIST OF RULES, EACH ONE A PATH THROUGH A DELEGATE'S TREE.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A RULE EDITOR IS A TREE THE DELEGATE OWNS AND A FLAT LIST THE VIEW SHOWS.** Each ROW is a path through a tree of
 * arbitrary criterion objects: the delegate says how many children a criterion has, which child is at an index, and what
 * to display for it. The view asks for a root criterion of the row's type, then for its first child, and so on until a
 * criterion has no children — that path IS the row's criteria, and the matching display values are what the row draws.
 * `-reloadCriteria` re-asks, keeping the longest prefix of each path that is still valid, which is what keeps a row
 * meaningful when the delegate's tree changes under it.
 *
 * **ROWS ARE NUMBERED IN DISPLAY ORDER, WHICH IS PRE-ORDER.** Row 0 is the first root; a compound row's children follow
 * it before the next root. `-parentRowForRow:` and `-subrowIndexesForRow:` translate between that flat numbering and the
 * tree, and every manipulation door takes a flat index. `-insertRowAtIndex:withType:asSubrowOfRow:animate:` therefore
 * requires the index to be a BOUNDARY of the parent's children — the position before the first child or after one of
 * them — and raises `NSInvalidArgumentException` when it falls inside another row's subtree, which is Apple's rule.
 *
 * **THE DRAWING IS THE VIEW'S OWN AND ROWS ARE HORIZONTAL BANDS.** The view is flipped (row 0 at the top), `-rowHeight`
 * gives a band its height, a nested row is indented by its depth, and the band draws its display values left to right:
 * a string (through the formatting dictionary), a menu item's title, or — for an `NSView` value — the view itself, added
 * as a subview at the band. Selection fills the band with the platform accent and keeps its ink dark.
 *
 * **THE NESTING MODE IS ENFORCED AT THE INSERTION DOOR, NOT ADVERTISED AND IGNORED.** Single allows one root and no
 * nesting; List allows no compound rows and no nesting; Simple allows one root with Simple subrows beneath it and no
 * further nesting; Compound allows everything. `-addRow:` chooses the row type that the mode can hold. `-isEditable`
 * gates the POINTER — Apple's own sentence is that users can only interact with editable rule editors, and this tier's
 * only user gesture is selecting a row.
 *
 * **THE PREDICATE DOORS ASSEMBLE, NOW THAT THE FOUNDATION HAS THE MODEL.** `-predicate`, `-predicateForRow:` and
 * `-reloadPredicate` are Apple's rule-editor-to-`NSPredicate` bridge: the delegate answers a PARTS dictionary per
 * criterion (the `NSRuleEditorPredicate…` keys), and the door builds an `NSComparisonPredicate` from the expressions,
 * modifier, operator, options and custom selector it finds. A row's criteria are combined with the compound type a parts
 * dictionary names, or with AND when none does; the editor's predicate is the AND of its rows. A parts dictionary with
 * no left expression, or no right one and no custom selector, contributes nothing — a half-filled comparison is not a
 * predicate. **This is the model `NSPredicateEditor` and `NSPredicateEditorRowTemplate` are built on**; the old note here
 * said they would stay absent because the predicate family was, and `libagora-base` restored it (`d4e75ec`, `917c144`).
 *
 * **WHAT IS STORED AND NAMED AS HAVING NO READER.** The four key paths and `-rowClass` are the "rows" BINDING's
 * settings; this tier has no binding engine, so they are stored and answered and nothing reads them. `-canRemoveAllRows`
 * limits the USER's deletion, and this tier has no user deletion gesture (the plus/minus buttons are the missing half),
 * so the programmatic removal doors are not gated by it and the header says so. `-formattingStringsFilename:` refuses
 * by name because this Foundation has no `.strings` reader; `-formattingDictionary:` is stored and IS read, by the
 * drawing, as a substitution over string display values.
 */
#ifndef APPKIT_NSRULEEDITOR_H
#define APPKIT_NSRULEEDITOR_H

#import <AppKit/NSControl.h>

@class NSDictionary;
@class NSIndexSet;
@class NSMutableArray;
@class NSString;
@class NSView;
@protocol NSRuleEditorDelegate;

NS_ASSUME_NONNULL_BEGIN

/* **HOW MUCH NESTING THE VIEW ALLOWS.** The mode is read at every insertion and in `-addRow:`; it is not a decoration
 * that the drawing ignores. */
enum {
	NSRuleEditorNestingModeSingle = 0,	/* one row, no nesting, no plus/minus */
	NSRuleEditorNestingModeList = 1,	/* a flat list: no compound rows, no nesting */
	NSRuleEditorNestingModeCompound = 2,	/* unlimited nesting; the default */
	NSRuleEditorNestingModeSimple = 3	/* one root with Simple subrows, no further nesting */
};
typedef NSUInteger NSRuleEditorNestingMode;

/* **A ROW IS SIMPLE OR COMPOUND.** A compound row may contain subrows; a simple one may not. The type is a fact about
 * the row the delegate's tree is asked with, and about what the mode permits. */
enum {
	NSRuleEditorRowTypeSimple = 0,
	NSRuleEditorRowTypeCompound = 1
};
typedef NSUInteger NSRuleEditorRowType;

@interface NSRuleEditor : NSControl
{
	/* THE TREE, AND THE FLAT VIEW OF IT IS COMPUTED ON DEMAND.** Roots are rows; a row's children are the rows drawn
	 * beneath it. There is no second array of "all rows" to fall out of date. */
	NSMutableArray *_rootRows;		/* RETAINED */
	/* THE SELECTION, BY FLAT INDEX. Pruned whenever the rows change. */
	NSMutableIndexSet *_selection;		/* RETAINED */
	/* THE DELEGATE IS BORROWED, like every delegate in this tree. */
	id <NSRuleEditorDelegate> _delegate;	/* NOT RETAINED */
	NSRuleEditorNestingMode _nestingMode;
	CGFloat _rowHeight;
	BOOL _editable;
	BOOL _canRemoveAllRows;

	NSDictionary *_formattingDictionary;	/* RETAINED (a copy) */
	NSString *_formattingStringsFilename;	/* RETAINED (a copy) */
	Class _rowClass;			/* the rows binding's model class; see the header note */
	NSString *_rowTypeKeyPath;		/* RETAINED (copies) */
	NSString *_subrowsKeyPath;
	NSString *_criteriaKeyPath;
	NSString *_displayValuesKeyPath;
	/* **THE VIEWS A ROW HAS ADOPTED AS DISPLAY VALUES.** A delegate may answer an `NSView` for a criterion; the layout
	 * adds it to the band and keeps it here so the next layout can take the previous set out. */
	NSMutableArray *_valueViews;		/* RETAINED */
}

/* ---- CONFIGURATION ---------------------------------------------------------------------------------- */

/* **THE DELEGATE IS REQUIRED IN APPLE'S CONTRACT AND THE VIEW TOLERATES NIL HERE**: with none, a row is still a row
 * with no criteria and no display values, and the delegation questions simply answer zero. That is the same disposition
 * the other delegate-driven views record. */
- (void)setDelegate:(nullable id <NSRuleEditorDelegate>)delegate;
- (nullable id <NSRuleEditorDelegate>)delegate;

/* **THE FORMATTING DICTIONARY IS READ BY THE DRAWING** (string display values are rewritten through it); the strings
 * FILENAME is refused by name, because loading a `.strings` file needs a reader this Foundation does not have. Setting
 * the dictionary is the way to format in this tier. */
- (void)setFormattingStringsFilename:(nullable NSString *)stringsFilename;
- (nullable NSString *)formattingStringsFilename;
- (void)setFormattingDictionary:(nullable NSDictionary *)dictionary;
- (nullable NSDictionary *)formattingDictionary;

/* **RE-ASK THE DELEGATE, KEEPING THE LONGEST VALID PREFIX OF EACH PATH.** Each row's criteria are checked against the
 * tree as it is NOW: a criterion that is no longer a child of its predecessor is dropped, the row is extended with
 * first children until a criterion has none, and display values are asked again. This is the door a delegate calls when
 * its model changes. */
- (void)reloadCriteria;

- (void)setNestingMode:(NSRuleEditorNestingMode)mode;
- (NSRuleEditorNestingMode)nestingMode;

/* **THE ROW HEIGHT, AND APPLE'S SENTENCE THAT SETTING IT CHANGES THE FRAME.** The height becomes `rowHeight` times the
 * number of rows; the width is left as the caller set it. */
- (void)setRowHeight:(CGFloat)height;
- (CGFloat)rowHeight;

/* **EDITABLE GATES THE POINTER.** Apple's sentence: users can only interact with editable rule editors. This tier's
 * only user gesture is selecting a row, so a non-editable editor ignores the click; the programmatic doors are not
 * gated. */
- (void)setEditable:(BOOL)editable;
- (BOOL)isEditable;

/* **`-canRemoveAllRows` LIMITS THE USER'S DELETION, AND THIS TIER HAS NO USER DELETION GESTURE.** The plus/minus
 * buttons are the missing half; the removal doors below are programmatic and are NOT gated by it, which is Apple's own
 * distinction ("the rule editor can still be emptied programmatically"). Stored and answered. */
- (void)setCanRemoveAllRows:(BOOL)val;
- (BOOL)canRemoveAllRows;

/* ---- PREDICATE SUPPORT: REFUSED BY NAME ------------------------------------------------------------- */

/* **THE THREE DOORS AND THEIR ONE HONEST ANSWER.** `-predicate` and `-predicateForRow:` ask the delegate for its parts
 * (so the optional parts door is sent) and then answer nil with a named refusal: this Foundation has no `NSPredicate`
 * to build. `-reloadPredicate` performs the same asking and discards it. See the header block for why the predicate
 * EDITOR pair stays absent. */
- (nullable id)predicate;
- (void)reloadPredicate;
- (nullable id)predicateForRow:(NSInteger)row;

/* ---- ROW INFORMATION -------------------------------------------------------------------------------- */

/* THE NUMBER OF ROWS IN DISPLAY ORDER (pre-order: a compound row's subrows are counted beneath it). */
- (NSInteger)numberOfRows;

/* **THE IMMEDIATE SUBROWS OF A ROW, AS FLAT INDEXES; -1 ASKS FOR THE ROOTS.** Out of range raises `NSRangeException`. */
- (NSIndexSet *)subrowIndexesForRow:(NSInteger)rowIndex;

/* THE CHOSEN PATH AND ITS DISPLAY VALUES, IN COLUMN ORDER. */
- (nullable NSArray *)criteriaForRow:(NSInteger)row;
- (nullable NSArray *)displayValuesForRow:(NSInteger)row;

/* **A DISPLAY VALUE BACK TO ITS ROW, BY POINTER EQUALITY** — Apple's own rule, because the same text may appear twice.
 * nil raises `NSInvalidArgumentException`; a value in no row answers `NSNotFound`. */
- (NSInteger)rowForDisplayValue:(id)displayValue;

/* THE ROW'S TYPE AND ITS PARENT'S FLAT INDEX (-1 for a root). Out of range raises `NSRangeException`. */
- (NSRuleEditorRowType)rowTypeForRow:(NSInteger)rowIndex;
- (NSInteger)parentRowForRow:(NSInteger)rowIndex;

/* ---- MANIPULATING ROWS ------------------------------------------------------------------------------ */

/* **THE USER'S ADD, AND THE MODE CHOOSES WHAT IT MAKES.** Single: nothing when a row exists. Simple with a root: a
 * Simple subrow beneath the root. Otherwise: a Simple root appended at the end. The new row is selected and announced. */
- (void)addRow:(nullable id)sender;

/* **THE INSERTION DOOR AND ITS THREE RAISES.** The index must be in the row range and a BOUNDARY of the parent's
 * children (or of the roots); the parent must precede the index; and the nesting mode must allow the type and the
 * nesting. `animate` is RECORDED AS IGNORED: this tier has no row animation, and the header says so rather than
 * pretending. The new row is selected and announced. */
- (void)insertRowAtIndex:(NSInteger)rowIndex
		withType:(NSRuleEditorRowType)rowType
	 asSubrowOfRow:(NSInteger)parentRow
	       animate:(BOOL)shouldAnimate;

/* **SET THE PATH AND ITS VALUES, EXTENDING BOTH THE WAY APPLE DOCUMENTS.** The arrays must not be nil. If the last
 * criterion has children, the path is extended with first children until a leaf; if the values array is shorter than
 * the path, the delegate is asked for the rest. An empty values array asks for all of them. */
- (void)setCriteria:(NSArray *)criteria
  andDisplayValues:(NSArray *)values
    forRowAtIndex:(NSInteger)rowIndex;

/* **REMOVAL ADOPTS THE ORPHANS.** A removed row's subrows are adopted by its parent (or become roots); the plural door
 * deletes the subtrees instead when `includeSubrows` is YES. Out of range raises `NSRangeException`. */
- (void)removeRowAtIndex:(NSInteger)rowIndex;
- (void)removeRowsAtIndexes:(NSIndexSet *)rowIndexes includeSubrows:(BOOL)includeSubrows;

/* ---- SELECTION -------------------------------------------------------------------------------------- */

/* THE SELECTED ROWS, AND THE DOOR THAT CHANGES THEM. Out of range raises `NSRangeException`; `extend` unions with
 * the current selection instead of replacing it. */
- (NSIndexSet *)selectedRowIndexes;
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;

/* ---- BINDINGS SUPPORT: STORED, WITH NO BINDING ENGINE HERE ------------------------------------------ */

/* **THE "rows" BINDING'S FIVE SETTINGS.** Apple's default row class is `NSMutableDictionary`, and the four key paths
 * default to the names in the class comment. This tier has no binding engine, so these are stored and answered and
 * nothing reads them; that is a disposition, not an omission, and it is named at each pair. */
- (void)setRowClass:(Class)rowClass;
- (Class)rowClass;
- (void)setRowTypeKeyPath:(NSString *)keyPath;
- (NSString *)rowTypeKeyPath;
- (void)setSubrowsKeyPath:(NSString *)keyPath;
- (NSString *)subrowsKeyPath;
- (void)setCriteriaKeyPath:(NSString *)keyPath;
- (NSString *)criteriaKeyPath;
- (void)setDisplayValuesKeyPath:(NSString *)keyPath;
- (NSString *)displayValuesKeyPath;

@end

/* **THE DELEGATE, WITH THREE REQUIRED DOORS AND TWO OPTIONAL ONES.** The first three are the tree; the fourth is the
 * predicate parts the predicate doors ask for; the fifth is the rows-changed announcement, sent both as a method and as
 * the notification below. */
@protocol NSRuleEditorDelegate <NSObject>

@required

/* The children of a criterion, or — when `criterion` is nil — the number of root criteria of the row type. */
- (NSInteger)ruleEditor:(NSRuleEditor *)editor
  numberOfChildrenForCriterion:(nullable id)criterion
	     withRowType:(NSRuleEditorRowType)rowType;

/* The child at an index, or — when `criterion` is nil — the root criterion at that index. */
- (nullable id)ruleEditor:(NSRuleEditor *)editor
		    child:(NSInteger)index
	     forCriterion:(nullable id)criterion
	      withRowType:(NSRuleEditorRowType)rowType;

/* What a criterion looks like in a row: an `NSString`, an `NSMenuItem` or an `NSView`. */
- (nullable id)ruleEditor:(NSRuleEditor *)editor
  displayValueForCriterion:(id)criterion
		    inRow:(NSInteger)row;

@optional

/* The pieces of the predicate this criterion contributes. ASKED by `-predicate`/`-predicateForRow:` and assembled into
 * an `NSComparisonPredicate`; the keys are the `NSRuleEditorPredicate…` constants below. */
- (nullable NSDictionary *)ruleEditor:(NSRuleEditor *)editor
	 predicatePartsForCriterion:(id)criterion
		    withDisplayValue:(nullable id)value
			      inRow:(NSInteger)row;

/* The rows changed, sent with the notification whose object is the editor. */
- (void)ruleEditorRowsDidChange:(NSNotification *)notification;

@end

/* **AND THE PREDICATE PARTS' KEYS — STRINGS, WHICH IS ALL THIS TIER CAN HONESTLY DEFINE OF THEM.** The values Apple
 * expects are `NSExpression`/`NSNumber` objects from the predicate family this Foundation does not have; the keys are
 * still declared because a delegate written for the era may put them in a dictionary, and the doors ask for that
 * dictionary before refusing the assembly. */
extern NSString * const NSRuleEditorPredicateLeftExpression;
extern NSString * const NSRuleEditorPredicateRightExpression;
extern NSString * const NSRuleEditorPredicateComparisonModifier;
extern NSString * const NSRuleEditorPredicateOptions;
extern NSString * const NSRuleEditorPredicateOperatorType;
extern NSString * const NSRuleEditorPredicateCustomSelector;
extern NSString * const NSRuleEditorPredicateCompoundType;

/* POSTED WHENEVER THE ROWS CHANGE; the object is the editor and there is no userInfo. The delegate's
 * `-ruleEditorRowsDidChange:` is sent with the same notification. */
extern NSString * const NSRuleEditorRowsDidChangeNotification;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSRULEEDITOR_H */
