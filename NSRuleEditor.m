/*
 * NSRuleEditor.m — the row tree, the flat numbering, the drawing and the doors.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THERE IS ONE TREE AND THE FLAT INDEXES ARE COMPUTED FROM IT.** A row owns its subrows; the "row number" every door
 * speaks is the row's pre-order position, computed by flattening the tree on demand. Nothing stores the flat order, so
 * an insertion or a removal cannot leave a second array describing a tree that has changed — the failure mode a cached
 * index list grows.
 *
 * **AND THE INSERTION RULE IS A BOUNDARY RULE.** A flat index names a position between rows, and for a parent's children
 * only some positions are legal: the one before the first child and the one after each child's SUBTREE. The positions
 * are computed the same way the flat list is, and an index inside another row's subtree raises, which is Apple's "if
 * rowIndex would fall amongst the children of some other parent".
 *
 * **THE DRAWING AND THE LAYOUT ASK THE SAME QUESTIONS.** Both walk the flat rows, both advance x by the same measured
 * display-value widths, and both place a view value at the same band — so a string and a view in one row cannot drift
 * apart, and a click's row arithmetic (y divided by the row height) is the same rectangle the band painted.
 */
#import <AppKit/NSRuleEditor.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenuItem.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSString.h>

#import "AppKitRefusal.h"

#include <math.h>

NSString * const NSRuleEditorPredicateLeftExpression = @"NSRuleEditorPredicateLeftExpression";
NSString * const NSRuleEditorPredicateRightExpression = @"NSRuleEditorPredicateRightExpression";
NSString * const NSRuleEditorPredicateComparisonModifier = @"NSRuleEditorPredicateComparisonModifier";
NSString * const NSRuleEditorPredicateOptions = @"NSRuleEditorPredicateOptions";
NSString * const NSRuleEditorPredicateOperatorType = @"NSRuleEditorPredicateOperatorType";
NSString * const NSRuleEditorPredicateCustomSelector = @"NSRuleEditorPredicateCustomSelector";
NSString * const NSRuleEditorPredicateCompoundType = @"NSRuleEditorPredicateCompoundType";
NSString * const NSRuleEditorRowsDidChangeNotification = @"NSRuleEditorRowsDidChangeNotification";

/* ============================================================================================
 * THE ROW OBJECT, WHICH IS PRIVATE BECAUSE APPLE'S ROW VIEWS ARE.
 * ============================================================================================ */
/* **A ROW IS A TYPE, A PATH AND THE VALUES THAT SPELL IT, PLUS ITS CHILDREN.** The criteria and display values are
 * PARALLEL arrays — index i of one describes index i of the other — which is the whole of what a row means. */
@interface AGRuleEditorRow : NSObject
{
@public
	NSRuleEditorRowType type;
	NSMutableArray *criteria;
	NSMutableArray *displayValues;
	NSMutableArray *children;
}
@end

@implementation AGRuleEditorRow

- (id)init
{
	self = [super init];
	if (self != nil) {
		type = NSRuleEditorRowTypeSimple;
		criteria = [[NSMutableArray alloc] init];
		displayValues = [[NSMutableArray alloc] init];
		children = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[criteria release];
	[displayValues release];
	[children release];
	[super dealloc];
}

@end

/* ============================================================================================
 * THE PRIVATE DOORS.
 * ============================================================================================ */
@interface NSRuleEditor (AGRuleEditorPrivate)
- (NSArray *)cg_rows;
- (void)cg_flatten:(NSArray *)rows into:(NSMutableArray *)out;
- (AGRuleEditorRow *)cg_rowAtIndex:(NSInteger)index;
- (NSInteger)cg_indexOfRow:(AGRuleEditorRow *)row;
- (AGRuleEditorRow *)cg_parentOfRow:(AGRuleEditorRow *)row;
- (NSInteger)cg_subtreeSizeOf:(AGRuleEditorRow *)row;
- (NSArray *)cg_positionsForParent:(AGRuleEditorRow *)parent;
- (NSInteger)cg_depthOfRowAtIndex:(NSInteger)index;
- (void)cg_fillRow:(AGRuleEditorRow *)row atIndex:(NSInteger)rowIndex;
- (void)cg_reloadRow:(AGRuleEditorRow *)row atIndex:(NSInteger)rowIndex;
- (void)cg_removeRowAtIndex:(NSInteger)index includeSubrows:(BOOL)includeSubrows;
- (void)cg_pruneSelection;
- (void)cg_rowsChanged;
- (void)cg_updateFrameHeight;
- (void)cg_layoutValueViews;
- (NSString *)cg_textForDisplayValue:(id)value;
- (CGFloat)cg_widthOfDisplayValue:(id)value font:(NSFont *)font;
- (NSString *)cg_formattedString:(NSString *)string;
- (void)cg_askPredicatePartsForRow:(NSInteger)row;
@end

/* THE BASELINE RULE THE FIELD CELL USES, for the same reason: a flipped context and an unflipped one place a line
 * differently, and the sign is the CONTEXT's (`-isFlipped` on the context object is not a guide). */
static CGFloat fn_baseline_in_band(NSRect band, NSFont *font)
{
	CGContextRef cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	CGAffineTransform transform = (cg != NULL) ? CGContextGetCTM(cg) : CGAffineTransformIdentity;
	CGFloat ascender = [font ascender];
	CGFloat descent = (CGFloat)fabs((double)[font descender]);

	return NSMidY(band) + (transform.d >= 0.0 ? 1.0 : -1.0) * ((ascender - descent) / 2.0);
}

@implementation NSRuleEditor

/* ============================================================================================
 * INITIALISE: THE DEFAULTS APPLE NAMES, AND THIS TIER'S ROW HEIGHT.
 * ============================================================================================ */
/* **THE DESIGNATED INITIALISER IS `-initWithFrame:`, AND `-init` MUST GO THROUGH IT.** An inherited `-init` leaves the row
 * list nil, and an insertion into a nil container is a message to nil: the row vanishes, `-numberOfRows` stays zero, and
 * the selection that follows raises a range error about a row that was never there. It is the ordinary door — a caller
 * writing `[[NSPredicateEditor alloc] init]` gets it — so it answers an empty frame, which is what `NSSlider` does with
 * its default and what Apple's own views do with theirs. */
- (id)init
{
	return [self initWithFrame:NSZeroRect];
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_rootRows = [[NSMutableArray alloc] init];
		_selection = [[NSMutableIndexSet alloc] init];
		_valueViews = [[NSMutableArray alloc] init];
		_nestingMode = NSRuleEditorNestingModeCompound;
		/* **TWENTY-TWO POINTS IS THIS TIER'S ROW HEIGHT, NOT A NUMBER APPLE PUBLISHES** — the era's header names the
		 * door and not a default. A line's font plus its padding is what a band needs, and the caller may set another. */
		_rowHeight = 22.0;
		_editable = YES;
		_canRemoveAllRows = YES;
		/* THE BINDING'S DEFAULTS, WHICH APPLE STATES: NSMutableDictionary and the four key names. Stored and answered;
		 * this tier has no binding engine, and the header says so at the pair. */
		_rowClass = [NSMutableDictionary class];
		_rowTypeKeyPath = [@"rowType" copy];
		_subrowsKeyPath = [@"subrows" copy];
		_criteriaKeyPath = [@"criteria" copy];
		_displayValuesKeyPath = [@"displayValues" copy];
	}
	return self;
}

- (void)dealloc
{
	[_rootRows release];
	[_selection release];
	[_formattingDictionary release];
	[_formattingStringsFilename release];
	[_rowTypeKeyPath release];
	[_subrowsKeyPath release];
	[_criteriaKeyPath release];
	[_displayValuesKeyPath release];
	[_valueViews release];
	[super dealloc];
}

/* THE VIEW IS FLIPPED, LIKE THE TABLE AND THE COLLECTION VIEW: row 0 is at the TOP, and a click's row is `y ÷ height`. */
- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)acceptsFirstResponder
{
	return _editable;
}

- (BOOL)becomeFirstResponder
{
	return YES;
}

/* ---- CONFIGURATION ---------------------------------------------------------------------------------- */

- (void)setDelegate:(id <NSRuleEditorDelegate>)delegate
{
	_delegate = delegate;	/* NOT RETAINED, this tree's rule for every delegate */
}

- (id <NSRuleEditorDelegate>)delegate
{
	return _delegate;
}

/* **THE FILENAME IS RECORDED AND THE LOAD IS REFUSED, NAMED AT THE DOOR.** This Foundation has no `.strings` reader (the
 * format door was withdrawn with a measurement), so a filename cannot become a formatting dictionary here. The request
 * still round-trips through `-formattingStringsFilename`, and the refusal says what did not happen. */
- (void)setFormattingStringsFilename:(NSString *)stringsFilename
{
	NSString *copy = [stringsFilename copy];

	[_formattingStringsFilename release];
	_formattingStringsFilename = copy;
	fn_refuse_window("-setFormattingStringsFilename:", "a .strings reader (this Foundation withdrew its strings-file "
							 "format door), so the named file is recorded but NOT loaded");
}

- (NSString *)formattingStringsFilename
{
	return _formattingStringsFilename;
}

- (void)setFormattingDictionary:(NSDictionary *)dictionary
{
	NSDictionary *copy = (dictionary != nil) ? [dictionary copy] : nil;

	[_formattingDictionary release];
	_formattingDictionary = copy;
	[self setNeedsDisplay:YES];
}

- (NSDictionary *)formattingDictionary
{
	return _formattingDictionary;
}

- (void)setNestingMode:(NSRuleEditorNestingMode)mode
{
	_nestingMode = mode;
}

- (NSRuleEditorNestingMode)nestingMode
{
	return _nestingMode;
}

- (void)setRowHeight:(CGFloat)height
{
	_rowHeight = (height > 0.0) ? height : 0.0;
	[self cg_updateFrameHeight];
	[self cg_layoutValueViews];
	[self setNeedsDisplay:YES];
}

- (CGFloat)rowHeight
{
	return _rowHeight;
}

- (void)setEditable:(BOOL)editable
{
	_editable = editable ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)isEditable
{
	return _editable;
}

- (void)setCanRemoveAllRows:(BOOL)val
{
	_canRemoveAllRows = val ? YES : NO;
}

- (BOOL)canRemoveAllRows
{
	return _canRemoveAllRows;
}

/* ============================================================================================
 * THE FLAT VIEW OF THE TREE.
 * ============================================================================================ */
- (void)cg_flatten:(NSArray *)rows into:(NSMutableArray *)out
{
	NSUInteger i;

	for (i = 0; i < [rows count]; i++) {
		AGRuleEditorRow *row = (AGRuleEditorRow *)[rows objectAtIndex:i];

		[out addObject:row];
		[self cg_flatten:row->children into:out];
	}
}

- (NSArray *)cg_rows
{
	NSMutableArray *rows = [NSMutableArray array];

	[self cg_flatten:_rootRows into:rows];
	return rows;
}

- (AGRuleEditorRow *)cg_rowAtIndex:(NSInteger)index
{
	NSArray *rows;

	if (index < 0) {
		return nil;
	}
	rows = [self cg_rows];
	if ((NSUInteger)index >= [rows count]) {
		return nil;
	}
	return (AGRuleEditorRow *)[rows objectAtIndex:(NSUInteger)index];
}

- (NSInteger)cg_indexOfRow:(AGRuleEditorRow *)row
{
	NSArray *rows = [self cg_rows];
	NSUInteger index = [rows indexOfObjectIdenticalTo:row];

	return (index == NSNotFound) ? -1 : (NSInteger)index;
}

- (AGRuleEditorRow *)cg_parentOfRow:(AGRuleEditorRow *)row
{
	NSMutableArray *stack = [NSMutableArray arrayWithArray:_rootRows];

	while ([stack count] > 0) {
		AGRuleEditorRow *candidate = (AGRuleEditorRow *)[stack lastObject];

		[stack removeLastObject];
		if ([candidate->children indexOfObjectIdenticalTo:row] != NSNotFound) {
			return candidate;
		}
		[stack addObjectsFromArray:candidate->children];
	}
	return nil;
}

- (NSInteger)cg_subtreeSizeOf:(AGRuleEditorRow *)row
{
	NSInteger size = 1;
	NSUInteger i;

	for (i = 0; i < [row->children count]; i++) {
		size += [self cg_subtreeSizeOf:(AGRuleEditorRow *)[row->children objectAtIndex:i]];
	}
	return size;
}

/* **THE LEGAL INSERTION POSITIONS FOR A PARENT'S CHILDREN, AS FLAT INDEXES.** For the roots the first position is 0;
 * for a row it is the position immediately after that row. Each child then contributes the position AFTER its whole
 * subtree, which is what makes "inside another row's subtree" distinguishable from "after it". */
- (NSArray *)cg_positionsForParent:(AGRuleEditorRow *)parent
{
	NSMutableArray *positions = [NSMutableArray array];
	NSArray *children;
	NSInteger cursor;

	if (parent == nil) {
		cursor = 0;
		children = _rootRows;
	} else {
		cursor = [self cg_indexOfRow:parent] + 1;
		children = parent->children;
	}
	[positions addObject:[NSNumber numberWithInteger:cursor]];
	{
		NSUInteger i;

		for (i = 0; i < [children count]; i++) {
			cursor += [self cg_subtreeSizeOf:(AGRuleEditorRow *)[children objectAtIndex:i]];
			[positions addObject:[NSNumber numberWithInteger:cursor]];
		}
	}
	return positions;
}

- (NSInteger)cg_depthOfRowAtIndex:(NSInteger)index
{
	AGRuleEditorRow *row = [self cg_rowAtIndex:index];
	NSInteger depth = 0;

	while (row != nil) {
		AGRuleEditorRow *parent = [self cg_parentOfRow:row];

		if (parent == nil) {
			break;
		}
		depth++;
		row = parent;
	}
	return depth;
}

/* ============================================================================================
 * THE DELEGATE'S TREE, ASKED AT THE TWO PLACES THAT NEED IT.
 * ============================================================================================ */
/* **A ROW IS FILLED BY WALKING THE DELEGATE'S TREE FROM THE FIRST ROOT DOWN THE FIRST CHILD.** That is Apple's initial
 * path: "the view asks the criterion for its child items and then each of the children for their display value". A
 * criterion with no children ends the walk, so the row's path is exactly the criteria that had a next step. */
- (void)cg_fillRow:(AGRuleEditorRow *)row atIndex:(NSInteger)rowIndex
{
	NSInteger count;
	id criterion;

	[row->criteria removeAllObjects];
	[row->displayValues removeAllObjects];
	if (_delegate == nil) {
		return;
	}
	count = [_delegate ruleEditor:self numberOfChildrenForCriterion:nil withRowType:row->type];
	if (count <= 0) {
		return;
	}
	criterion = [_delegate ruleEditor:self child:0 forCriterion:nil withRowType:row->type];
	while (criterion != nil) {
		id value;

		[row->criteria addObject:criterion];
		value = [_delegate ruleEditor:self displayValueForCriterion:criterion inRow:rowIndex];
		[row->displayValues addObject:(value != nil ? value : [criterion description])];
		count = [_delegate ruleEditor:self numberOfChildrenForCriterion:criterion withRowType:row->type];
		if (count <= 0) {
			break;
		}
		criterion = [_delegate ruleEditor:self child:0 forCriterion:criterion withRowType:row->type];
	}
}

/* **THE RE-ASK KEEPS THE LONGEST VALID PREFIX.** A criterion at the head must still be a ROOT of the row's type; each
 * later one must still be a child of its predecessor. The first invalid step ends the prefix, and the row is extended
 * from there down first children again — so a tree that grew keeps the row where it was, and a tree that lost a branch
 * moves the row to the first surviving path rather than to nothing. */
- (void)cg_reloadRow:(AGRuleEditorRow *)row atIndex:(NSInteger)rowIndex
{
	NSMutableArray *kept = [NSMutableArray array];
	id previous = nil;
	NSUInteger i;

	if (_delegate == nil) {
		[row->criteria removeAllObjects];
		[row->displayValues removeAllObjects];
		return;
	}
	for (i = 0; i < [row->criteria count]; i++) {
		id criterion = [row->criteria objectAtIndex:i];
		BOOL valid = NO;
		NSInteger count;
		NSInteger childIndex;

		if (previous == nil) {
			count = [_delegate ruleEditor:self numberOfChildrenForCriterion:nil withRowType:row->type];
			for (childIndex = 0; childIndex < count; childIndex++) {
				id root = [_delegate ruleEditor:self child:childIndex forCriterion:nil withRowType:row->type];

				if (root != nil && [root isEqual:criterion]) {
					valid = YES;
					break;
				}
			}
		} else {
			count = [_delegate ruleEditor:self numberOfChildrenForCriterion:previous withRowType:row->type];
			for (childIndex = 0; childIndex < count; childIndex++) {
				id child = [_delegate ruleEditor:self child:childIndex
						    forCriterion:previous withRowType:row->type];

				if (child != nil && [child isEqual:criterion]) {
					valid = YES;
					break;
				}
			}
		}
		if (!valid) {
			break;
		}
		[kept addObject:criterion];
		previous = criterion;
	}
	if ([kept count] == 0) {
		id root = [_delegate ruleEditor:self child:0 forCriterion:nil withRowType:row->type];

		if (root != nil) {
			[kept addObject:root];
		}
	}
	while ([kept count] > 0) {
		id last = [kept lastObject];
		NSInteger count = [_delegate ruleEditor:self numberOfChildrenForCriterion:last withRowType:row->type];
		id child;

		if (count <= 0) {
			break;
		}
		child = [_delegate ruleEditor:self child:0 forCriterion:last withRowType:row->type];
		if (child == nil) {
			break;
		}
		[kept addObject:child];
	}
	[row->criteria setArray:kept];
	[row->displayValues removeAllObjects];
	for (i = 0; i < [kept count]; i++) {
		id value = [_delegate ruleEditor:self displayValueForCriterion:[kept objectAtIndex:i] inRow:rowIndex];

		[row->displayValues addObject:(value != nil ? value : [[kept objectAtIndex:i] description])];
	}
}

- (void)reloadCriteria
{
	NSArray *rows = [self cg_rows];
	NSUInteger i;

	for (i = 0; i < [rows count]; i++) {
		[self cg_reloadRow:(AGRuleEditorRow *)[rows objectAtIndex:i] atIndex:(NSInteger)i];
	}
	[self cg_rowsChanged];
}

/* ============================================================================================
 * ROW INFORMATION.
 * ============================================================================================ */
- (NSInteger)numberOfRows
{
	return (NSInteger)[[self cg_rows] count];
}

- (NSIndexSet *)subrowIndexesForRow:(NSInteger)rowIndex
{
	NSMutableIndexSet *indexes = [[[NSMutableIndexSet alloc] init] autorelease];
	NSInteger count = [self numberOfRows];
	NSInteger i;

	if (rowIndex < -1 || rowIndex >= count) {
		[NSException raise:NSRangeException format:@"-subrowIndexesForRow: %ld is outside -1..%ld",
			(long)rowIndex, (long)count - 1];
	}
	if (rowIndex == -1) {
		NSInteger cursor = 0;
		NSUInteger rootIndex;

		/* THE ROOTS' FLAT INDEXES: 0, then after each root's subtree. */
		for (rootIndex = 0; rootIndex < [_rootRows count]; rootIndex++) {
			[indexes addIndex:(NSUInteger)cursor];
			cursor += [self cg_subtreeSizeOf:(AGRuleEditorRow *)[_rootRows objectAtIndex:rootIndex]];
		}
		return indexes;
	}
	{
		AGRuleEditorRow *row = [self cg_rowAtIndex:rowIndex];

		for (i = 0; i < (NSInteger)[row->children count]; i++) {
			[indexes addIndex:(NSUInteger)[self cg_indexOfRow:(AGRuleEditorRow *)[row->children objectAtIndex:i]]];
		}
	}
	return indexes;
}

- (NSArray *)criteriaForRow:(NSInteger)row
{
	AGRuleEditorRow *aRow = [self cg_rowAtIndex:row];

	if (aRow == nil) {
		[NSException raise:NSRangeException format:@"-criteriaForRow: %ld is outside 0..%ld",
			(long)row, (long)[self numberOfRows] - 1];
	}
	return [NSArray arrayWithArray:aRow->criteria];
}

- (NSArray *)displayValuesForRow:(NSInteger)row
{
	AGRuleEditorRow *aRow = [self cg_rowAtIndex:row];

	if (aRow == nil) {
		[NSException raise:NSRangeException format:@"-displayValuesForRow: %ld is outside 0..%ld",
			(long)row, (long)[self numberOfRows] - 1];
	}
	return [NSArray arrayWithArray:aRow->displayValues];
}

- (NSInteger)rowForDisplayValue:(id)displayValue
{
	NSArray *rows;
	NSUInteger i;

	if (displayValue == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-rowForDisplayValue: nil names no value"];
	}
	rows = [self cg_rows];
	for (i = 0; i < [rows count]; i++) {
		AGRuleEditorRow *row = (AGRuleEditorRow *)[rows objectAtIndex:i];
		NSUInteger j;

		for (j = 0; j < [row->displayValues count]; j++) {
			if ([row->displayValues objectAtIndex:j] == displayValue) {
				return (NSInteger)i;
			}
		}
	}
	return NSNotFound;
}

- (NSRuleEditorRowType)rowTypeForRow:(NSInteger)rowIndex
{
	AGRuleEditorRow *row = [self cg_rowAtIndex:rowIndex];

	if (row == nil) {
		[NSException raise:NSRangeException format:@"-rowTypeForRow: %ld is outside 0..%ld",
			(long)rowIndex, (long)[self numberOfRows] - 1];
	}
	return row->type;
}

- (NSInteger)parentRowForRow:(NSInteger)rowIndex
{
	AGRuleEditorRow *row = [self cg_rowAtIndex:rowIndex];
	AGRuleEditorRow *parent;

	if (row == nil) {
		[NSException raise:NSRangeException format:@"-parentRowForRow: %ld is outside 0..%ld",
			(long)rowIndex, (long)[self numberOfRows] - 1];
	}
	parent = [self cg_parentOfRow:row];
	return (parent != nil) ? [self cg_indexOfRow:parent] : -1;
}

/* ============================================================================================
 * INSERTION.
 * ============================================================================================ */
- (void)insertRowAtIndex:(NSInteger)rowIndex
		withType:(NSRuleEditorRowType)rowType
	 asSubrowOfRow:(NSInteger)parentRow
	       animate:(BOOL)shouldAnimate
{
	NSInteger count = [self numberOfRows];
	AGRuleEditorRow *parent = nil;
	NSArray *positions;
	NSMutableArray *container;
	AGRuleEditorRow *row;
	BOOL legal = NO;
	NSUInteger i;
	NSInteger childIndex = 0;

	(void)shouldAnimate;	/* RECORDED AS IGNORED: this tier has no row animation. */
	if (rowIndex < 0 || rowIndex > count) {
		[NSException raise:NSRangeException format:@"-insertRowAtIndex: %ld is outside 0..%ld",
			(long)rowIndex, (long)count];
	}
	if (parentRow < -1 || parentRow >= count) {
		[NSException raise:NSInvalidArgumentException format:@"-insertRowAtIndex: parent %ld is outside -1..%ld",
			(long)parentRow, (long)count - 1];
	}
	if (parentRow >= rowIndex) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-insertRowAtIndex: parent %ld must precede the insertion index %ld",
			    (long)parentRow, (long)rowIndex];
	}
	/* **THE NESTING MODE IS CHECKED HERE, WHICH IS WHERE IT MATTERS.** */
	switch (_nestingMode) {
	case NSRuleEditorNestingModeSingle:
		if (rowType != NSRuleEditorRowTypeSimple || parentRow != -1 || count > 0) {
			[NSException raise:NSInvalidArgumentException
				    format:@"SINGLE nesting allows one simple row and no subrows"];
		}
		break;
	case NSRuleEditorNestingModeList:
		if (rowType != NSRuleEditorRowTypeSimple || parentRow != -1) {
			[NSException raise:NSInvalidArgumentException
				    format:@"LIST nesting allows simple rows and no subrows"];
		}
		break;
	case NSRuleEditorNestingModeSimple:
		if (parentRow == -1) {
			if (count > 0) {
				[NSException raise:NSInvalidArgumentException
					    format:@"SIMPLE nesting allows exactly one root row"];
			}
		} else if (parentRow != 0 || rowType != NSRuleEditorRowTypeSimple) {
			[NSException raise:NSInvalidArgumentException
				    format:@"SIMPLE nesting puts simple rows under the single root only"];
		}
		break;
	case NSRuleEditorNestingModeCompound:
		break;
	}
	if (parentRow >= 0) {
		parent = [self cg_rowAtIndex:parentRow];
	}
	/* **THE INDEX MUST BE A BOUNDARY OF THIS PARENT'S CHILDREN.** */
	positions = [self cg_positionsForParent:parent];
	for (i = 0; i < [positions count]; i++) {
		NSInteger position = [[positions objectAtIndex:i] integerValue];

		if (position == rowIndex) {
			legal = YES;
			childIndex = (NSInteger)i;
			break;
		}
		if (position < rowIndex) {
			childIndex = (NSInteger)i;
		}
	}
	if (!legal) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-insertRowAtIndex: %ld is inside another row's subtree for parent %ld",
			    (long)rowIndex, (long)parentRow];
	}
	row = [[AGRuleEditorRow alloc] init];
	row->type = rowType;
	[self cg_fillRow:row atIndex:rowIndex];
	container = (parent != nil) ? parent->children : _rootRows;
	if ((NSUInteger)childIndex > [container count]) {
		childIndex = (NSInteger)[container count];
	}
	[container insertObject:row atIndex:(NSUInteger)childIndex];
	[row release];
	[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)rowIndex] byExtendingSelection:NO];
	[self cg_rowsChanged];
}

/* **THE USER'S ADD CHOOSES WHAT THE MODE CAN HOLD.** Single stops at one row; Simple adds a Simple subrow under the one
 * root; everything else appends a Simple root (a compound row is what the INSERTION door is for). */
- (void)addRow:(id)sender
{
	NSInteger count = [self numberOfRows];

	(void)sender;
	if (_nestingMode == NSRuleEditorNestingModeSingle && count > 0) {
		return;
	}
	if (_nestingMode == NSRuleEditorNestingModeSimple && count > 0) {
		[self insertRowAtIndex:count withType:NSRuleEditorRowTypeSimple asSubrowOfRow:0 animate:NO];
		return;
	}
	[self insertRowAtIndex:count withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
}

/* ============================================================================================
 * CRITERIA AND REMOVAL.
 * ============================================================================================ */
- (void)setCriteria:(NSArray *)criteria andDisplayValues:(NSArray *)values forRowAtIndex:(NSInteger)rowIndex
{
	AGRuleEditorRow *row = [self cg_rowAtIndex:rowIndex];
	NSUInteger i;

	if (criteria == nil || values == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-setCriteria:andDisplayValues:forRowAtIndex: needs two arrays, not nil"];
	}
	if (row == nil) {
		[NSException raise:NSRangeException format:@"-setCriteria:…forRowAtIndex: %ld is outside 0..%ld",
			(long)rowIndex, (long)[self numberOfRows] - 1];
	}
	[row->criteria setArray:criteria];
	/* **THE PATH IS EXTENDED TO A LEAF FIRST, THEN THE VALUES ARE FILLED IN ORDER.** The caller's values are a PREFIX of
	 * the answer — Apple's own rule — so the extension cannot consume a slot the caller already filled, and the FIRST
	 * criterion's display value is asked for like every other one. The earlier version asked for each child's value
	 * inside the extension loop and then filled from the values count, which skipped the first criterion whenever the
	 * caller passed an empty array; a VIEW display value on that first criterion never became a subview. */
	while ([row->criteria count] > 0) {
		id last = [row->criteria lastObject];
		NSInteger children = (_delegate != nil)
			? [_delegate ruleEditor:self numberOfChildrenForCriterion:last withRowType:row->type] : 0;
		id child;

		if (children <= 0) {
			break;
		}
		child = [_delegate ruleEditor:self child:0 forCriterion:last withRowType:row->type];
		if (child == nil) {
			break;
		}
		[row->criteria addObject:child];
	}
	[row->displayValues setArray:values];
	while ([row->displayValues count] > [row->criteria count]) {
		[row->displayValues removeLastObject];
	}
	for (i = [row->displayValues count]; i < [row->criteria count]; i++) {
		id criterion = [row->criteria objectAtIndex:i];
		id value = (_delegate != nil)
			? [_delegate ruleEditor:self displayValueForCriterion:criterion inRow:rowIndex] : nil;

		[row->displayValues addObject:(value != nil ? value : [criterion description])];
	}
	[self cg_rowsChanged];
}

/* **A REMOVAL ADOPTS THE ORPHANS: the removed row's children are spliced into its parent's list at its position, or
 * become roots. The plural door's `includeSubrows:` chooses between adoption and taking the subtree with it. */
- (void)cg_removeRowAtIndex:(NSInteger)index includeSubrows:(BOOL)includeSubrows
{
	AGRuleEditorRow *row = [self cg_rowAtIndex:index];
	AGRuleEditorRow *parent;
	NSMutableArray *container;
	NSUInteger position;
	NSUInteger i;

	if (row == nil) {
		[NSException raise:NSRangeException format:@"-removeRowAtIndex: %ld is outside 0..%ld",
			(long)index, (long)[self numberOfRows] - 1];
	}
	parent = [self cg_parentOfRow:row];
	container = (parent != nil) ? parent->children : _rootRows;
	position = [container indexOfObjectIdenticalTo:row];
	if (position == NSNotFound) {
		return;
	}
	if (!includeSubrows) {
		for (i = 0; i < [row->children count]; i++) {
			[container insertObject:[row->children objectAtIndex:i] atIndex:position + 1 + i];
		}
	}
	[container removeObjectIdenticalTo:row];
}

- (void)removeRowAtIndex:(NSInteger)rowIndex
{
	[self cg_removeRowAtIndex:rowIndex includeSubrows:NO];
	[self cg_rowsChanged];
}

- (void)removeRowsAtIndexes:(NSIndexSet *)rowIndexes includeSubrows:(BOOL)includeSubrows
{
	NSInteger count = [self numberOfRows];
	NSUInteger index;

	for (index = [rowIndexes firstIndex]; index != NSNotFound; index = [rowIndexes indexGreaterThanIndex:index]) {
		if ((NSInteger)index >= count) {
			[NSException raise:NSRangeException format:@"-removeRowsAtIndexes: %lu is outside 0..%ld",
				(unsigned long)index, (long)count - 1];
		}
	}
	/* **DESCENDING, SO THE EARLIER INDEXES ARE STILL THE ROWS THEY NAMED.** */
	index = [rowIndexes lastIndex];
	while (index != NSNotFound) {
		[self cg_removeRowAtIndex:(NSInteger)index includeSubrows:includeSubrows];
		index = (index == 0) ? NSNotFound : [rowIndexes indexLessThanIndex:index];
	}
	[self cg_rowsChanged];
}

/* ============================================================================================
 * SELECTION.
 * ============================================================================================ */
- (NSIndexSet *)selectedRowIndexes
{
	return [[[NSIndexSet alloc] initWithIndexSet:_selection] autorelease];
}

- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
	NSInteger count = [self numberOfRows];
	NSUInteger index;

	if (indexes == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-selectRowIndexes: nil names no rows"];
	}
	for (index = [indexes firstIndex]; index != NSNotFound; index = [indexes indexGreaterThanIndex:index]) {
		if ((NSInteger)index >= count) {
			[NSException raise:NSRangeException format:@"-selectRowIndexes: %lu is outside 0..%ld",
				(unsigned long)index, (long)count - 1];
		}
	}
	if (!extend) {
		[_selection removeAllIndexes];
	}
	for (index = [indexes firstIndex]; index != NSNotFound; index = [indexes indexGreaterThanIndex:index]) {
		[_selection addIndex:index];
	}
	[self setNeedsDisplay:YES];
}

- (void)cg_pruneSelection
{
	NSInteger count = [self numberOfRows];
	NSUInteger index = [_selection firstIndex];

	while (index != NSNotFound) {
		NSUInteger next = [_selection indexGreaterThanIndex:index];

		if ((NSInteger)index >= count) {
			[_selection removeIndex:index];
		}
		index = next;
	}
}

/* ============================================================================================
 * THE PREDICATE DOORS: ASK FOR THE PARTS, REFUSE THE ASSEMBLY.
 * ============================================================================================ */
- (void)cg_askPredicatePartsForRow:(NSInteger)row
{
	AGRuleEditorRow *aRow = [self cg_rowAtIndex:row];
	NSUInteger i;

	if (aRow == nil || _delegate == nil ||
	    ![_delegate respondsToSelector:@selector(ruleEditor:predicatePartsForCriterion:withDisplayValue:inRow:)]) {
		return;
	}
	for (i = 0; i < [aRow->criteria count]; i++) {
		id value = (i < [aRow->displayValues count]) ? [aRow->displayValues objectAtIndex:i] : nil;

		(void)[_delegate ruleEditor:self predicatePartsForCriterion:[aRow->criteria objectAtIndex:i]
			      withDisplayValue:value inRow:row];
	}
}

/* **A PARTS DICTIONARY IS A COMPARISON, OR NOTHING.** The delegate supplies the two expressions and, optionally, the
 * modifier, the operator, the options and a custom selector; a dictionary with a left expression and a right one, or a
 * left and a custom selector, is a comparison predicate. Anything less contributes nothing — the alternative is a
 * predicate with a half-filled comparison, which evaluates to something nobody asked for. */
- (NSPredicate *)cg_predicateForParts:(NSDictionary *)parts
{
	NSExpression *left = [parts objectForKey:NSRuleEditorPredicateLeftExpression];
	NSExpression *right = [parts objectForKey:NSRuleEditorPredicateRightExpression];
	id custom = [parts objectForKey:NSRuleEditorPredicateCustomSelector];
	NSComparisonPredicateModifier modifier = NSDirectPredicateModifier;
	NSPredicateOperatorType type = NSEqualToPredicateOperatorType;
	NSUInteger options = 0;
	NSNumber *number;

	if (left == nil) {
		return nil;
	}
	if ((number = [parts objectForKey:NSRuleEditorPredicateComparisonModifier]) != nil) {
		modifier = (NSComparisonPredicateModifier)[number unsignedIntegerValue];
	}
	if ((number = [parts objectForKey:NSRuleEditorPredicateOperatorType]) != nil) {
		type = (NSPredicateOperatorType)[number unsignedIntegerValue];
	}
	if ((number = [parts objectForKey:NSRuleEditorPredicateOptions]) != nil) {
		options = [number unsignedIntegerValue];
	}
	if (custom != nil) {
		/* A SELECTOR CANNOT CROSS A DICTIONARY AS ONE, so the part is its NAME (or an NSValue holding the pointer). */
		SEL selector = NULL;

		if ([custom isKindOfClass:[NSString class]]) {
			selector = NSSelectorFromString((NSString *)custom);
		} else if ([custom isKindOfClass:[NSValue class]]) {
			selector = (SEL)[(NSValue *)custom pointerValue];
		}
		if (selector != NULL && right != nil) {
			/* **FOUNDATION REFUSES THE CUSTOM-SELECTOR OPERATOR, SO THIS DOOR REFUSES IT TOO** — by name, and by
			 * contributing nothing, rather than raising out of `-predicate`. `NSComparisonPredicate`'s own refusal says
			 * why (`-performSelector:withObject:` is not declared in this Foundation), and a predicate that silently
			 * answered NO would be worse than a part that is not there. */
			fprintf(stderr, "APPKIT-REFUSE: NSRuleEditor: a custom-selector criterion cannot be assembled — "
					"Foundation's NSComparisonPredicate does not implement the custom-selector operator\n");
			return nil;
		}
	}
	if (right == nil) {
		return nil;
	}
	return [NSComparisonPredicate predicateWithLeftExpression:left
							  rightExpression:right
								 modifier:modifier
								     type:type
								  options:options];
}

/* **A ROW IS ITS CRITERIA COMBINED, AND THE COMPOUND TYPE COMES FROM THE PARTS.** The delegate says what each criterion
 * contributes; a parts dictionary that names a compound type makes the row that compound over its criteria predicates,
 * and a row that names none is their AND. That is the one place the compound key is read, and it is stated in the
 * header rather than guessed at. */
- (NSPredicate *)cg_predicateForRow:(NSInteger)row
{
	NSArray *criteria = [self criteriaForRow:row];
	NSArray *values = [self displayValuesForRow:row];
	NSMutableArray *predicates = [NSMutableArray array];
	NSCompoundPredicateType compoundType = NSAndPredicateType;
	BOOL sawCompound = NO;
	NSUInteger i;

	if (row < 0 || [self cg_rowAtIndex:row] == nil) {
		return nil;
	}
	for (i = 0; i < [criteria count]; i++) {
		id value = (i < [values count]) ? [values objectAtIndex:i] : nil;
		NSDictionary *parts;
		NSPredicate *predicate;
		NSNumber *compound;

		if (_delegate == nil ||
		    ![_delegate respondsToSelector:@selector(ruleEditor:predicatePartsForCriterion:withDisplayValue:inRow:)]) {
			continue;
		}
		parts = [_delegate ruleEditor:self
		     predicatePartsForCriterion:[criteria objectAtIndex:i]
			    withDisplayValue:value
				     inRow:row];
		if (parts == nil) {
			continue;
		}
		if (!sawCompound && (compound = [parts objectForKey:NSRuleEditorPredicateCompoundType]) != nil) {
			compoundType = (NSCompoundPredicateType)[compound unsignedIntegerValue];
			sawCompound = YES;
		}
		predicate = [self cg_predicateForParts:parts];
		if (predicate != nil) {
			[predicates addObject:predicate];
		}
	}
	if ([predicates count] == 0) {
		return nil;
	}
	if ([predicates count] == 1) {
		return [predicates objectAtIndex:0];
	}
	return [[[NSCompoundPredicate alloc] initWithType:compoundType subpredicates:predicates] autorelease];
}

- (id)predicate
{
	NSMutableArray *rows = [NSMutableArray array];
	NSInteger count = [self numberOfRows];
	NSInteger i;

	/* EVERY ROW'S PARTS ARE ASKED FOR, which is what the door always did; the assembly is what is new. */
	for (i = 0; i < count; i++) {
		NSPredicate *predicate;

		[self cg_askPredicatePartsForRow:i];
		predicate = [self cg_predicateForRow:i];
		if (predicate != nil) {
			[rows addObject:predicate];
		}
	}
	if ([rows count] == 0) {
		return nil;
	}
	if ([rows count] == 1) {
		return [rows objectAtIndex:0];
	}
	return [[[NSCompoundPredicate alloc] initWithType:NSAndPredicateType subpredicates:rows] autorelease];
}

- (void)reloadPredicate
{
	NSInteger count = [self numberOfRows];
	NSInteger i;

	for (i = 0; i < count; i++) {
		[self cg_askPredicatePartsForRow:i];
	}
}

- (id)predicateForRow:(NSInteger)row
{
	if ([self cg_rowAtIndex:row] == nil) {
		[NSException raise:NSRangeException format:@"-predicateForRow: %ld is outside 0..%ld",
			(long)row, (long)[self numberOfRows] - 1];
	}
	[self cg_askPredicatePartsForRow:row];
	return [self cg_predicateForRow:row];
}

/* ============================================================================================
 * THE DRAWING AND THE VIEW LAYOUT.
 * ============================================================================================ */
/* THE FORMATTING DICTIONARY, APPLIED AS A SUBSTITUTION OVER STRING DISPLAY VALUES. Keys and values are strings, which is
 * the part of the `.strings` vocabulary this tier can honour. */
- (NSString *)cg_formattedString:(NSString *)string
{
	NSMutableString *result;
	NSArray *keys;
	NSUInteger i;

	if (string == nil || _formattingDictionary == nil || [_formattingDictionary count] == 0) {
		return string;
	}
	result = [[string mutableCopy] autorelease];
	keys = [_formattingDictionary allKeys];
	for (i = 0; i < [keys count]; i++) {
		NSString *key = [keys objectAtIndex:i];
		id value = [_formattingDictionary objectForKey:key];

		if (![value isKindOfClass:[NSString class]] || [key length] == 0) {
			continue;
		}
		[result replaceOccurrencesOfString:key withString:value options:0
					 range:NSMakeRange(0, [result length])];
	}
	return result;
}

- (NSString *)cg_textForDisplayValue:(id)value
{
	if ([value isKindOfClass:[NSString class]]) {
		return [self cg_formattedString:(NSString *)value];
	}
	if ([value isKindOfClass:[NSMenuItem class]]) {
		return [(NSMenuItem *)value title];
	}
	if ([value isKindOfClass:[NSView class]]) {
		return nil;	/* the view itself draws */
	}
	return [value description];
}

- (CGFloat)cg_widthOfDisplayValue:(id)value font:(NSFont *)font
{
	NSString *text = [self cg_textForDisplayValue:value];
	NSDictionary *attributes;

	if (text == nil || [text length] == 0) {
		return 0.0;
	}
	attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
	return [text sizeWithAttributes:attributes].width;
}

/* **A VIEW VALUE IS A SUBVIEW OF ITS BAND.** The previous set is taken out first, so a reload that returns a different
 * view object does not leave the old one on the glass; the width arithmetic is the drawing's own, so a string and a view
 * in one row cannot drift apart. */
- (void)cg_layoutValueViews
{
	NSArray *rows = [self cg_rows];
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	NSUInteger i;

	for (i = 0; i < [_valueViews count]; i++) {
		[[_valueViews objectAtIndex:i] removeFromSuperview];
	}
	[_valueViews removeAllObjects];
	for (i = 0; i < [rows count]; i++) {
		AGRuleEditorRow *row = (AGRuleEditorRow *)[rows objectAtIndex:i];
		NSInteger depth = [self cg_depthOfRowAtIndex:(NSInteger)i];
		CGFloat x = 8.0 + (CGFloat)depth * 16.0;
		CGFloat bandTop = (CGFloat)i * _rowHeight;
		NSUInteger j;

		for (j = 0; j < [row->displayValues count]; j++) {
			id value = [row->displayValues objectAtIndex:j];

			if ([value isKindOfClass:[NSView class]]) {
				NSView *view = (NSView *)value;
				NSSize size = [view frame].size;

				[view setFrame:NSMakeRect(x, bandTop + (_rowHeight - size.height) / 2.0,
							  size.width, size.height)];
				[self addSubview:view];
				[_valueViews addObject:view];
				x += size.width + 8.0;
			} else {
				x += [self cg_widthOfDisplayValue:value font:font] + 8.0;
			}
		}
	}
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSArray *rows;
	NSFont *font;
	NSRect bounds = [self bounds];
	NSUInteger i;

	rows = [self cg_rows];
	font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	[[NSColor controlBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:bounds] fill];
	for (i = 0; i < [rows count]; i++) {
		AGRuleEditorRow *row = (AGRuleEditorRow *)[rows objectAtIndex:i];
		NSRect band = NSMakeRect(0.0, (CGFloat)i * _rowHeight, bounds.size.width, _rowHeight);
		NSInteger depth = [self cg_depthOfRowAtIndex:(NSInteger)i];
		CGFloat x = 8.0 + (CGFloat)depth * 16.0;
		BOOL selected = [_selection containsIndex:i];
		NSUInteger j;

		if (!NSIntersectsRect(band, dirtyRect)) {
			continue;
		}
		if (selected) {
			[[NSColor cg_accentColor] setFill];
			[[NSBezierPath bezierPathWithRect:band] fill];
		}
		{
			NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
				font, NSFontAttributeName,
				[NSColor controlTextColor], NSForegroundColorAttributeName, nil];
			CGFloat baseline = fn_baseline_in_band(band, font);

			for (j = 0; j < [row->displayValues count]; j++) {
				id value = [row->displayValues objectAtIndex:j];
				NSString *text = [self cg_textForDisplayValue:value];

				if (text != nil && [text length] > 0) {
					[text drawAtPoint:NSMakePoint(x, baseline) withAttributes:attributes];
				}
				if ([value isKindOfClass:[NSView class]]) {
					x += [(NSView *)value frame].size.width + 8.0;
				} else {
					x += [self cg_widthOfDisplayValue:value font:font] + 8.0;
				}
			}
			/* **A COMPOUND ROW SHOWS THAT IT HAS CHILDREN, AND ONLY AN EDITABLE ONE SHOWS THE MARK.** The marker is the
			 * tier's stand-in for the disclosure control the era drew; a non-editable editor is display-only, so it
			 * draws none, which is where `-isEditable` reaches the picture. */
			if (_editable && [row->children count] > 0) {
				NSBezierPath *marker = [NSBezierPath bezierPath];

				[marker moveToPoint:NSMakePoint(x + 2.0, NSMidY(band) - 4.0)];
				[marker lineToPoint:NSMakePoint(x + 8.0, NSMidY(band))];
				[marker lineToPoint:NSMakePoint(x + 2.0, NSMidY(band) + 4.0)];
				[marker closePath];
				[[NSColor controlTextColor] setFill];
				[marker fill];
			}
		}
	}
}

/* ============================================================================================
 * THE POINTER AND THE ANNOUNCEMENT.
 * ============================================================================================ */
/* **ONLY AN EDITABLE EDITOR TAKES A CLICK** — Apple's sentence, and the reader `-isEditable` has. A click selects the
 * band under the pointer (Shift or Command extends); a click below the last row clears when no modifier is down. */
- (void)mouseDown:(NSEvent *)event
{
	NSInteger count = [self numberOfRows];
	NSPoint point;
	NSInteger index;
	NSUInteger modifiers;

	if (!_editable) {
		return;
	}
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	index = (_rowHeight > 0.0) ? (NSInteger)floor(point.y / _rowHeight) : -1;
	modifiers = [event modifierFlags];
	if ([self window] != nil) {
		[[self window] makeFirstResponder:self];
	}
	if (index < 0 || index >= count) {
		if ((modifiers & (NSCommandKeyMask | NSShiftKeyMask)) == 0) {
			[self selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
		}
		return;
	}
	[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index]
	  byExtendingSelection:((modifiers & (NSCommandKeyMask | NSShiftKeyMask)) != 0)];
}

- (void)cg_updateFrameHeight
{
	NSUInteger rows = (NSUInteger)[self numberOfRows];

	[self setFrameSize:NSMakeSize([self frame].size.width, _rowHeight * (CGFloat)rows)];
}

/* **EVERY ROW CHANGE ENDS HERE: PRUNE, RE-FRAME, RE-LAY THE VALUE VIEWS, REPAINT, ANNOUNCE.** The announcement is the
 * notification and the delegate's method carrying the same object, which is the arrangement the table and the menu use. */
- (void)cg_rowsChanged
{
	NSNotification *note;

	[self cg_pruneSelection];
	[self cg_updateFrameHeight];
	[self cg_layoutValueViews];
	[self setNeedsDisplay:YES];
	note = [NSNotification notificationWithName:NSRuleEditorRowsDidChangeNotification object:self];
	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(ruleEditorRowsDidChange:)]) {
		[_delegate ruleEditorRowsDidChange:note];
	}
}

/* ============================================================================================
 * THE BINDINGS SUPPORT: STORED AND ANSWERED, WITH NO BINDING ENGINE HERE.
 * ============================================================================================ */
- (void)setRowClass:(Class)rowClass
{
	_rowClass = rowClass;
}

- (Class)rowClass
{
	return _rowClass;
}

- (void)setRowTypeKeyPath:(NSString *)keyPath
{
	NSString *copy = [keyPath copy];

	[_rowTypeKeyPath release];
	_rowTypeKeyPath = copy;
}

- (NSString *)rowTypeKeyPath
{
	return _rowTypeKeyPath;
}

- (void)setSubrowsKeyPath:(NSString *)keyPath
{
	NSString *copy = [keyPath copy];

	[_subrowsKeyPath release];
	_subrowsKeyPath = copy;
}

- (NSString *)subrowsKeyPath
{
	return _subrowsKeyPath;
}

- (void)setCriteriaKeyPath:(NSString *)keyPath
{
	NSString *copy = [keyPath copy];

	[_criteriaKeyPath release];
	_criteriaKeyPath = copy;
}

- (NSString *)criteriaKeyPath
{
	return _criteriaKeyPath;
}

- (void)setDisplayValuesKeyPath:(NSString *)keyPath
{
	NSString *copy = [keyPath copy];

	[_displayValuesKeyPath release];
	_displayValuesKeyPath = copy;
}

- (NSString *)displayValuesKeyPath
{
	return _displayValuesKeyPath;
}

@end
