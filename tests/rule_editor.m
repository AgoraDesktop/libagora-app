/*
 * rule_editor — NSRuleEditor: the tree, the flat numbering, the four nesting modes, the drawing and the refusals.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE DRIVES THE DELEGATE'S TREE RATHER THAN A STORED COPY OF IT.** Every row's criteria come from the
 * delegate's answers, so the checks are: the initial path (first root, then first child to a leaf), the extension of a
 * set path to a leaf, the re-ask that keeps the longest valid prefix when the tree changes, and the display values that
 * are the parallel spelling of the path. The flat numbering is measured from both sides (`-parentRowForRow:`,
 * `-subrowIndexesForRow:`) because a second, cached order is exactly the bug this design avoids.
 *
 * WHAT IS ASSERTED, and the sender each one names:
 *
 *   1. The defaults: no rows, a 22-point row, Compound nesting, editable, can-remove-all, Apple's row class and the four
 *      key-path names, and no formatting.
 *   2. Insertion: a root's initial path, a subrow's parent, the flat order, and the BOUNDARY rule (an index inside
 *      another row's subtree raises `NSInvalidArgumentException`).
 *   3. The four nesting modes, each with what it forbids, and `-addRow:`'s mode-dependent choice.
 *   4. Row information and its `NSRangeException`s.
 *   5. `-setCriteria:andDisplayValues:forRowAtIndex:`: extension to a leaf, filling values from the delegate, and nil
 *      arrays refused.
 *   6. `-reloadCriteria`: a changed tree moves the row to the surviving path.
 *   7. Removal: adoption of orphans, and `includeSubrows:` taking the subtree.
 *   8. Selection and the pointer: click, extend, empty-space clear, and `-isEditable` gating the click.
 *   9. The drawing: the selected band's accent ink, the formatting dictionary changing the text, and a VIEW display
 *      value becoming a subview of its band.
 *  10. The predicate doors: nil answers with a named refusal, and the delegate's parts door asked first.
 *  11. The rows-changed announcement, both as the notification and as the delegate method.
 */
#import <AppKit/NSRuleEditor.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSMenuItem.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

#define VIEW_W 420.0
#define VIEW_H 220.0

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSEvent *mouse(NSPoint where)
{
	return [NSEvent mouseEventWithType:NSLeftMouseDown location:where modifierFlags:0
				 timestamp:0.0 windowNumber:0 context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

static int string_array_equal(NSArray *a, NSArray *b)
{
	NSUInteger i;

	if ([a count] != [b count]) {
		return 0;
	}
	for (i = 0; i < [a count]; i++) {
		if (![[a objectAtIndex:i] isEqual:[b objectAtIndex:i]]) {
			return 0;
		}
	}
	return 1;
}

/* ============================================================================================ *
 * THE DELEGATE: A MUTABLE TREE, SO `-reloadCriteria` HAS SOMETHING TO SEE                            *
 * ============================================================================================ */
@interface AGRuleDelegate : NSObject <NSRuleEditorDelegate>
{
@public
	NSMutableDictionary *rootsByType;	/* NSNumber(type) -> NSArray of root criteria */
	NSMutableDictionary *children;		/* criterion -> NSArray of children */
	BOOL viewForDate;
	NSInteger partsAsked;
	NSInteger rowsChanged;
	NSNotification *lastNote;
	NSView *lastView;
}
@end

@implementation AGRuleDelegate

- (id)init
{
	self = [super init];
	if (self != nil) {
		rootsByType = [[NSMutableDictionary alloc] init];
		children = [[NSMutableDictionary alloc] init];
		[rootsByType setObject:[NSArray arrayWithObjects:@"Name", @"Kind", @"Date", nil]
				forKey:[NSNumber numberWithInt:(int)NSRuleEditorRowTypeSimple]];
		[rootsByType setObject:[NSArray arrayWithObjects:@"ANY", @"ALL", nil]
				forKey:[NSNumber numberWithInt:(int)NSRuleEditorRowTypeCompound]];
		[children setObject:[NSArray arrayWithObjects:@"contains", @"starts with", @"ends with", nil]
			     forKey:@"Name"];
		[children setObject:[NSArray arrayWithObject:@"is"] forKey:@"Kind"];
		[children setObject:[NSArray arrayWithObjects:@"before", @"after", nil] forKey:@"Date"];
	}
	return self;
}

- (void)dealloc
{
	[rootsByType release];
	[children release];
	[lastNote release];
	[super dealloc];
}

- (NSInteger)ruleEditor:(NSRuleEditor *)editor
  numberOfChildrenForCriterion:(id)criterion
	     withRowType:(NSRuleEditorRowType)rowType
{
	(void)editor;
	if (criterion == nil) {
		NSArray *roots = [rootsByType objectForKey:[NSNumber numberWithInt:(int)rowType]];

		return (NSInteger)[roots count];
	}
	{
		NSArray *kids = [children objectForKey:criterion];

		return (kids != nil) ? (NSInteger)[kids count] : 0;
	}
}

- (id)ruleEditor:(NSRuleEditor *)editor
	    child:(NSInteger)index
     forCriterion:(id)criterion
      withRowType:(NSRuleEditorRowType)rowType
{
	NSArray *list = (criterion == nil)
		? [rootsByType objectForKey:[NSNumber numberWithInt:(int)rowType]]
		: [children objectForKey:criterion];

	(void)editor;
	if (index < 0 || (NSUInteger)index >= [list count]) {
		return nil;
	}
	return [list objectAtIndex:(NSUInteger)index];
}

- (id)ruleEditor:(NSRuleEditor *)editor
  displayValueForCriterion:(id)criterion
		    inRow:(NSInteger)row
{
	(void)editor;
	(void)row;
	if (viewForDate && [criterion isEqual:@"Date"]) {
		lastView = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 30.0, 10.0)] autorelease];
		return lastView;
	}
	return [NSString stringWithFormat:@"show:%@", criterion];
}

- (NSDictionary *)ruleEditor:(NSRuleEditor *)editor
     predicatePartsForCriterion:(id)criterion
		withDisplayValue:(id)value
			  inRow:(NSInteger)row
{
	(void)editor;
	(void)criterion;
	(void)value;
	(void)row;
	partsAsked++;
	return [NSDictionary dictionaryWithObject:@"part" forKey:NSRuleEditorPredicateLeftExpression];
}

- (void)ruleEditorRowsDidChange:(NSNotification *)notification
{
	rowsChanged++;
	[lastNote release];
	lastNote = [notification retain];
}

@end

/* A shade test: the selected band is the platform accent, which is a light periwinkle — blue above red by a margin. */
static int accent_pixels(NSBitmapImageRep *rep, NSInteger y0, NSInteger y1)
{
	NSInteger x, y, count = 0;

	for (y = y0; y < y1; y++) {
		for (x = 0; x < (NSInteger)VIEW_W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c blueComponent] > 0.9 && [c redComponent] > 0.55 && [c redComponent] < 0.75
			    && [c greenComponent] > 0.5 && [c greenComponent] < 0.7) {
				count++;
			}
		}
	}
	return count;
}

static int dark_pixels(NSBitmapImageRep *rep, NSInteger y0, NSInteger y1)
{
	NSInteger x, y, count = 0;

	for (y = y0; y < y1; y++) {
		for (x = 0; x < (NSInteger)VIEW_W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.5 && [c greenComponent] < 0.5 && [c blueComponent] < 0.5) {
				count++;
			}
		}
	}
	return count;
}

static NSBitmapImageRep *render_view(NSView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:(NSInteger)VIEW_W pixelsHigh:(NSInteger)VIEW_H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
		isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)VIEW_W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
	return rep;
}

int main(void)
{
	@autoreleasepool {
		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)
							      styleMask:NSBorderlessWindowMask
								backing:NSBackingStoreBuffered
								  defer:NO];
		NSRuleEditor *editor = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)];
		AGRuleDelegate *delegate = [[AGRuleDelegate alloc] init];
		BOOL caught;

		[window setContentView:editor];
		[editor setDelegate:delegate];

		/* 1. THE DEFAULTS. */
		check([editor numberOfRows] == 0, "a fresh rule editor has no rows");
		check([editor rowHeight] == 22.0, "a 22-point row height");
		check([editor nestingMode] == NSRuleEditorNestingModeCompound, "Compound nesting by default");
		check([editor isEditable] && [editor canRemoveAllRows], "editable, and removable to empty");
		check([editor rowClass] == [NSMutableDictionary class], "Apple's rows-binding class");
		check([[editor rowTypeKeyPath] isEqual:@"rowType"]
		      && [[editor subrowsKeyPath] isEqual:@"subrows"]
		      && [[editor criteriaKeyPath] isEqual:@"criteria"]
		      && [[editor displayValuesKeyPath] isEqual:@"displayValues"],
		      "and the four binding key paths Apple names");
		check([editor formattingDictionary] == nil && [editor formattingStringsFilename] == nil,
		      "no formatting dictionary and no strings file");
		check([editor delegate] == delegate, "the delegate is answered back");
		check([editor isFlipped], "the view is flipped: row 0 is at the top");

		/* 2. INSERTION AND THE INITIAL PATH. */
		[editor insertRowAtIndex:0 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
		check([editor numberOfRows] == 1, "a root row at index 0");
		check([editor rowTypeForRow:0] == NSRuleEditorRowTypeSimple, "of the requested type");
		check([editor parentRowForRow:0] == -1, "with no parent");
		check(string_array_equal([editor criteriaForRow:0], [NSArray arrayWithObjects:@"Name", @"contains", nil]),
		      "its path is the first root and then the first child to a leaf");
		check([[editor displayValuesForRow:0] count] == 2
		      && [[[editor displayValuesForRow:0] objectAtIndex:0] isEqual:@"show:Name"],
		      "and the display values spell the same two steps");
		[editor insertRowAtIndex:1 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
		check([editor numberOfRows] == 2 && [editor parentRowForRow:1] == -1, "a second root follows it");

		/* A SUBROW SITS BENEATH ITS PARENT IN THE FLAT ORDER. */
		[editor insertRowAtIndex:1 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:0 animate:NO];
		check([editor numberOfRows] == 3, "a subrow adds a third row");
		check([editor parentRowForRow:1] == 0, "whose parent is row 0");
		check([[editor subrowIndexesForRow:0] isEqual:[NSIndexSet indexSetWithIndex:1]],
		      "and row 0's subrow index is 1");
		check([editor parentRowForRow:2] == -1, "while the old second root is now row 2");
		check([[editor subrowIndexesForRow:-1] containsIndex:0]
		      && [[editor subrowIndexesForRow:-1] containsIndex:2]
		      && ![[editor subrowIndexesForRow:-1] containsIndex:1],
		      "the roots are 0 and 2, and NOT the subrow at 1");

		/* 3. THE BOUNDARY RULE. */
		caught = NO;
		@try {
			[editor insertRowAtIndex:3 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:0 animate:NO];
		} @catch (NSException *exception) {
			caught = [[exception name] isEqual:NSInvalidArgumentException];
		}
		check(caught, "an index inside another row's subtree raises NSInvalidArgumentException");

		/* 4. THE NESTING MODES. */
		{
			NSRuleEditor *list = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)];
			NSRuleEditor *single = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)];
			NSRuleEditor *simple = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)];

			[list setDelegate:delegate];
			[list setNestingMode:NSRuleEditorNestingModeList];
			[list insertRowAtIndex:0 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
			check([list numberOfRows] == 1, "LIST takes a simple root");
			caught = NO;
			@try {
				[list insertRowAtIndex:1 withType:NSRuleEditorRowTypeCompound asSubrowOfRow:-1 animate:NO];
			} @catch (NSException *exception) {
				caught = YES;
			}
			check(caught, "LIST refuses a compound row");

			[single setDelegate:delegate];
			[single setNestingMode:NSRuleEditorNestingModeSingle];
			[single insertRowAtIndex:0 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
			caught = NO;
			@try {
				[single insertRowAtIndex:1 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
			} @catch (NSException *exception) {
				caught = YES;
			}
			check(caught, "SINGLE refuses a second row");

			[simple setDelegate:delegate];
			[simple setNestingMode:NSRuleEditorNestingModeSimple];
			[simple insertRowAtIndex:0 withType:NSRuleEditorRowTypeCompound asSubrowOfRow:-1 animate:NO];
			[simple insertRowAtIndex:1 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:0 animate:NO];
			check([simple numberOfRows] == 2, "SIMPLE takes one root and a simple subrow");
			caught = NO;
			@try {
				[simple insertRowAtIndex:2 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
			} @catch (NSException *exception) {
				caught = YES;
			}
			check(caught, "SIMPLE refuses a second root");
			caught = NO;
			@try {
				[simple insertRowAtIndex:2 withType:NSRuleEditorRowTypeCompound asSubrowOfRow:0 animate:NO];
			} @catch (NSException *exception) {
				caught = YES;
			}
			check(caught, "SIMPLE refuses a compound subrow");

			[list release];
			[single release];
			[simple release];
		}

		/* 5. -addRow: CHOOSES WHAT THE MODE CAN HOLD. */
		{
			NSRuleEditor *mode = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)];

			[mode setDelegate:delegate];
			[mode addRow:nil];
			[mode addRow:nil];
			check([mode numberOfRows] == 2 && [mode parentRowForRow:1] == -1,
			      "Compound's `-addRow:` appends roots");
			[mode setNestingMode:NSRuleEditorNestingModeSingle];
			[mode addRow:nil];
			check([mode numberOfRows] == 2, "and SINGLE's does nothing once a row exists");
			[mode release];
		}

		/* 6. ROW INFORMATION AND ITS RANGE RAISES. */
		{
			NSInteger i;
			int raised = 0;

			for (i = 0; i < 4; i++) {
				caught = NO;
				@try {
					if (i == 0) { [editor subrowIndexesForRow:3]; }
					else if (i == 1) { [editor parentRowForRow:3]; }
					else if (i == 2) { [editor rowTypeForRow:3]; }
					else { [editor criteriaForRow:3]; }
				} @catch (NSException *exception) {
					caught = [[exception name] isEqual:NSRangeException];
				}
				if (caught) {
					raised++;
				}
			}
			check(raised == 4, "the row-information doors raise NSRangeException past the last row");
		}

		/* 7. THE PATH AND ITS VALUES, SET BY THE CALLER. */
		[editor setCriteria:[NSArray arrayWithObject:@"Kind"]
	     andDisplayValues:[NSArray array]
		forRowAtIndex:2];
		check(string_array_equal([editor criteriaForRow:2], [NSArray arrayWithObjects:@"Kind", @"is", nil]),
		      "a short path is extended to a leaf through the delegate");
		check([[editor displayValuesForRow:2] count] == 2
		      && [[[editor displayValuesForRow:2] objectAtIndex:1] isEqual:@"show:is"],
		      "and an empty values array is filled for every step");
		caught = NO;
		@try {
			NSArray *noCriteria = nil;

			[editor setCriteria:noCriteria andDisplayValues:[NSArray array] forRowAtIndex:0];
		} @catch (NSException *exception) {
			caught = [[exception name] isEqual:NSInvalidArgumentException];
		}
		check(caught, "a nil criteria array raises NSInvalidArgumentException");

		/* 8. -reloadCriteria KEEPS THE LONGEST VALID PREFIX. */
		[editor setCriteria:[NSArray arrayWithObjects:@"Name", @"contains", nil]
	     andDisplayValues:[NSArray array]
		forRowAtIndex:0];
		[delegate->children setObject:[NSArray arrayWithObject:@"matches"] forKey:@"Name"];
		[editor reloadCriteria];
		check(string_array_equal([editor criteriaForRow:0], [NSArray arrayWithObjects:@"Name", @"matches", nil]),
		      "a criterion that is no longer a child is replaced from the surviving path");
		[delegate->children setObject:[NSArray arrayWithObjects:@"contains", @"starts with", @"ends with", nil]
			     forKey:@"Name"];

		/* 9. REMOVAL ADOPTS OR TAKES THE SUBTREE. */
		{
			NSInteger before = [editor numberOfRows];

			/* **THE PARENT LEAVES AND ITS CHILD TAKES ITS PLACE AS A ROOT**, so the count falls by one: the subtree had
			 * two rows and now has the child alone. */
			[editor removeRowAtIndex:0];
			check([editor numberOfRows] == before - 1,
			      "removing a parent adopts its subrow as a root and drops one row");
			check([editor parentRowForRow:0] == -1, "and the adopted row is a root");
			check([editor rowTypeForRow:0] == NSRuleEditorRowTypeSimple, "with its own type kept");
		}
		[editor removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:0] includeSubrows:NO];
		check([editor numberOfRows] == 1, "the plural door with adoption removes what it names");
		{
			NSInteger before = [editor numberOfRows];

			[editor insertRowAtIndex:before withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
			[editor insertRowAtIndex:before + 1 withType:NSRuleEditorRowTypeSimple
				   asSubrowOfRow:before animate:NO];
			check([editor numberOfRows] == before + 2, "a root and its subrow arrive");
			[editor removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)before]
				 includeSubrows:YES];
			check([editor numberOfRows] == before, "and includeSubrows:YES takes the whole subtree");
		}
		/* TWO ROWS AGAIN, FOR THE POINTER AND THE SELECTION SECTIONS BELOW. */
		[editor insertRowAtIndex:1 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
		check([editor numberOfRows] == 2, "a second root is restored for the pointer checks");

		/* 10. SELECTION AND THE POINTER. */
		[editor selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
		check([[editor selectedRowIndexes] count] == 1 && [[editor selectedRowIndexes] containsIndex:0],
		      "a selection is stored");
		[editor selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:YES];
		check([[editor selectedRowIndexes] count] == 2, "and `extend` unions with it");
		caught = NO;
		@try {
			[editor selectRowIndexes:[NSIndexSet indexSetWithIndex:99] byExtendingSelection:NO];
		} @catch (NSException *exception) {
			caught = [[exception name] isEqual:NSRangeException];
		}
		check(caught, "a selection past the last row raises NSRangeException");

		[editor selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
		[editor mouseDown:mouse([editor convertPoint:NSMakePoint(20.0, 10.0) toView:nil])];
		check([[editor selectedRowIndexes] count] == 1 && [[editor selectedRowIndexes] containsIndex:0],
		      "a click selects the row whose band holds the point");
		[editor mouseDown:mouse([editor convertPoint:NSMakePoint(20.0, 22.0 + 10.0) toView:nil])];
		check([[editor selectedRowIndexes] count] == 1 && [[editor selectedRowIndexes] containsIndex:1],
		      "and a click on the next band moves it");
		[editor setEditable:NO];
		[editor mouseDown:mouse([editor convertPoint:NSMakePoint(20.0, 10.0) toView:nil])];
		check([[editor selectedRowIndexes] count] == 1 && [[editor selectedRowIndexes] containsIndex:1],
		      "a NON-editable editor ignores the pointer");
		check(![editor acceptsFirstResponder], "and cannot become first responder");
		[editor setEditable:YES];
		check([window makeFirstResponder:editor] && [editor acceptsFirstResponder],
		      "an editable one can");

		/* 11. THE DRAWING: THE SELECTED BAND, THE FORMATTING DICTIONARY, AND A VIEW VALUE. */
		[editor selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
		{
			NSBitmapImageRep *rep = render_view(editor);
			int selected = accent_pixels(rep, 0, 20);
			int unselected = accent_pixels(rep, 24, 40);
			NSColor *probe = [rep colorAtX:5 y:5];

			printf("  (note: accent pixels — row 0 %d, row 1 %d; pixel(5,5)=(%.2f,%.2f,%.2f))\n",
			       selected, unselected, (double)[probe redComponent],
			       (double)[probe greenComponent], (double)[probe blueComponent]);
			check(selected > 100 && unselected == 0,
			      "the selected band is filled with the accent and its neighbour is not");
			[rep release];
		}
		[editor selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
		[editor setCriteria:[NSArray arrayWithObjects:@"Name", @"contains", nil]
	     andDisplayValues:[NSArray array]
		forRowAtIndex:0];
		{
			NSBitmapImageRep *rep = render_view(editor);
			int plain = dark_pixels(rep, 0, 20);

			[rep release];
			[editor setFormattingDictionary:
				[NSDictionary dictionaryWithObject:@"a much longer replacement"
							    forKey:@"show:Name"]];
			rep = render_view(editor);
			{
				int formatted = dark_pixels(rep, 0, 20);

				printf("  (note: dark pixels — plain %d, formatted %d)\n", plain, formatted);
				check(formatted > plain,
				      "the formatting dictionary rewrites the display string the row draws");
			}
			[rep release];
			[editor setFormattingDictionary:nil];
		}
		delegate->viewForDate = YES;
		[editor setCriteria:[NSArray arrayWithObject:@"Date"]
	     andDisplayValues:[NSArray array]
		forRowAtIndex:0];
		{
			NSArray *values = [editor displayValuesForRow:0];
			NSView *valueView = nil;
			NSUInteger i;

			for (i = 0; i < [values count]; i++) {
				if ([[values objectAtIndex:i] isKindOfClass:[NSView class]]) {
					valueView = [values objectAtIndex:i];
				}
			}
			check(valueView != nil && [valueView superview] == editor,
			      "a VIEW display value is adopted as a subview of its band");
			check(valueView != nil && [valueView frame].origin.x > 0.0,
			      "and it is placed after the earlier values, not at the origin");
		}
		delegate->viewForDate = NO;

		/* 12. THE PREDICATE DOORS: ASK, THEN REFUSE. */
		delegate->partsAsked = 0;
		check([editor predicate] == nil && delegate->partsAsked > 0,
		      "`-predicate` asks the delegate's parts door and answers nil");
		delegate->partsAsked = 0;
		check([editor predicateForRow:0] == nil && delegate->partsAsked > 0,
		      "`-predicateForRow:` does the same for one row");
		delegate->partsAsked = 0;
		[editor reloadPredicate];
		check(delegate->partsAsked > 0, "and `-reloadPredicate` is the same asking");

		/* 13. THE ANNOUNCEMENT. */
		delegate->rowsChanged = 0;
		[editor addRow:nil];
		check(delegate->rowsChanged == 1 && delegate->lastNote != nil,
		      "a row change sends the delegate's announcement");
		check([[delegate->lastNote name] isEqual:NSRuleEditorRowsDidChangeNotification]
		      && [delegate->lastNote object] == editor,
		      "with the notification name and the editor as its object");

		/* 14. THE FORMATTING FILENAME IS RECORDED, THE LOAD REFUSED. */
		[editor setFormattingStringsFilename:@"Rules.strings"];
		check([[editor formattingStringsFilename] isEqual:@"Rules.strings"],
		      "the strings-file name round-trips");
		check([editor formattingDictionary] == nil,
		      "and the dictionary is not invented from a file this tier cannot read");

		printf("rule_editor: %d case(s) failed\n", s_failed);
		[delegate release];
		[editor release];
		[window release];
	}
	return s_failed != 0;
}
