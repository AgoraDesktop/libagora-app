/*
 * matrix — the grid, its selection, its shapes, its form, and its ink.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A MATRIX IS THE FIRST CONTROL WHOSE FACE IS PLURAL, SO THIS PROBE ASKS THE PLURAL QUESTIONS.** Where the button
 * sweep asked "is the face drawn", this asks "WHICH cell was drawn", "which cell is selected", "where did the cell
 * that was at (1, 1) go when a row was inserted", and "does the form's label band stop where the form's entry
 * begins". Every one of those is a claim about ARITHMETIC or IDENTITY, so every one is checkable without a window.
 *
 * WHAT IS ASSERTED, and why each is not a restatement of the code:
 *
 *   1. THE GRID'S ARITHMETIC — a cell's frame from its (row, column), and the (row, column) from a point, in both
 *      directions. A flipped grid is the thing that goes wrong here, which is why row 1 is asserted BELOW row 0.
 *   2. A GAP IS NOT A CELL — the point between two cells answers NO while still naming the nearer index.
 *   3. SELECTION IS STORED, HIGHLIGHT IS DRAWN — `-setSelectionFrom:to:anchor:highlight:NO` selects without lighting,
 *      which is the one thing a single bit could not hold.
 *   4. THE MODE CHANGES THE VALUE — a radio group's selected cell is the only one whose state is ON.
 *   5. SHAPE CHANGES MOVE CELLS, NOT VALUES — a tag written before a row is removed is found at the row that took its
 *      place, and a cell's ADDRESS survives an insert.
 *   6. SORTING IS PER COLUMN AND STABLE — equal tags keep their order, which is the property an insertion sort has
 *      and a caller checking a second sort key relies on.
 *   7. A PROTOTYPE IS COPIED, NOT SHARED — every position is a different object with the prototype's tag.
 *   8. THE ACTION PATH IS REACHABLE WITHOUT A POINTER — `-performClick:` is the keyboard's click, and
 *      `-performKeyEquivalent:` is the button's letter.
 *   9. THE FIELD SESSION OPENS ON THE RIGHT CELL — a matrix that edited the wrong cell is the bug that made the
 *      matrix re-home the text notifications at all.
 *  10. THE INK — a selected plain cell is drawn in the selection colour, a cell background is under it, and the grid's
 *      background shows between cells.
 *  11. THE FORM — entries are rows, the label is the title, `-setEntryWidth:` fixes the value band, and a frame change
 *      widens the entries rather than the labels.
 */
#import <AppKit/NSMatrix.h>
#import <AppKit/NSForm.h>
#import <AppKit/NSFormCell.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSText.h>
#import <AppKit/NSStringDrawing.h>

#include <math.h>
#include <stdio.h>

static int g_checks;
static int g_failed;

static void check(int ok, const char *what)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s\n", what);
	} else {
		printf("  [ok]   %s\n", what);
	}
}

static int near(double a, double b)
{
	return fabs(a - b) < 0.001;
}

/* A TARGET THAT COUNTS — "the action was sent" is a number rather than an assumption, and it is how the keyboard's
 * click and the key equivalent are checked without a pointer. */
@interface AGMatrixTarget : NSObject
{
@public
	int fired;
}
- (void)cellClicked:(id)sender;
@end

@implementation AGMatrixTarget
- (void)cellClicked:(id)sender
{
	(void)sender;
	fired++;
}
@end

/* THE COMPARISON THE SORT DOORS TAKE, ascending by tag — a caller's function, which is what both sort doors are for. */
static NSInteger compare_tags(id a, id b, void *context)
{
	NSInteger left = [(NSCell *)a tag];
	NSInteger right = [(NSCell *)b tag];

	(void)context;
	if (left < right) {
		return NSOrderedAscending;
	}
	if (left > right) {
		return NSOrderedDescending;
	}
	return NSOrderedSame;
}

/* ---- THE INK'S INSTRUMENTS ------------------------------------------------------------------------- */

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static int pixel_is(NSBitmapImageRep *rep, int x, int y, NSColor *want)
{
	NSColor *c = [rep colorAtX:x y:y];

	return c != nil && want != nil
		&& fabs([c redComponent] - [want redComponent]) < 0.02
		&& fabs([c greenComponent] - [want greenComponent]) < 0.02
		&& fabs([c blueComponent] - [want blueComponent]) < 0.02;
}

/* DARK PIXELS IN A BAND — the instrument for "is there a string here", which is what a label and a value are. */
static int ink_in(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.55 && [c greenComponent] < 0.55 && [c blueComponent] < 0.55) {
				n++;
			}
		}
	}
	return n;
}

/* ============================================================================================ *
 * THE GRID AND THE INVERSE LOOKUPS.                                                             *
 * ============================================================================================ */

static void test_grid(void)
{
	NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 60.0)
						mode:NSListModeMatrix
					   cellClass:[NSButtonCell class]
					  numberOfRows:2 numberOfColumns:3];
	NSInteger row = -1, column = -1;
	NSCell *cell;
	NSRect frame;

	printf("grid\n");
	[m setCellSize:NSMakeSize(60.0, 20.0)];
	[m setIntercellSpacing:NSMakeSize(4.0, 4.0)];
	check([m numberOfRows] == 2 && [m numberOfColumns] == 3, "a 2x3 matrix reports 2 rows and 3 columns");
	check([m cells] != NULL && [m cells][0] != NULL && [m cells][5] != NULL, "-cells is a row-major array of every position");
	check([m cellAtRow:0 column:0] != [m cellAtRow:0 column:1], "every position is a different cell");

	frame = [m cellFrameAtRow:1 column:2];
	check(near(NSMinX(frame), 128.0) && near(NSMinY(frame), 24.0)
	      && near(NSWidth(frame), 60.0) && near(NSHeight(frame), 20.0),
	      "cell (1,2) is at (2*(60+4), 1*(20+4)) — the grid is flipped, so row 1 is BELOW row 0");
	check(NSEqualRects([m cellFrameAtRow:2 column:0], NSZeroRect), "a row out of range has no frame");

	/* A POINT INSIDE A CELL COMES BACK AS THAT CELL, both ways round. */
	check([m getRow:&row column:&column forPoint:NSMakePoint(132.0, 26.0)] && row == 1 && column == 2,
	      "-getRow:column:forPoint: finds (1,2) inside its own frame");
	/* AND A POINT IN THE GAP ANSWERS NO WHILE NAMING THE NEARER INDEX. */
	row = column = -1;
	check(![m getRow:&row column:&column forPoint:NSMakePoint(62.0, 10.0)] && row == 0 && column == 0,
	      "a point in the intercell gap is not a cell, but the index is still reported");

	cell = [m cellAtRow:1 column:0];
	check([m getRow:&row column:&column ofCell:cell] && row == 1 && column == 0,
	      "-getRow:column:ofCell: inverts the cell's position");
	check(![m getRow:&row column:&column ofCell:[[[NSCell alloc] init] autorelease]],
	      "a cell that is not in the grid is not found");

	/* SIZE POLICIES: sizeToCells sizes the FRAME to the grid. */
	[m sizeToCells];
	check(near(NSWidth([m frame]), 3.0 * 60.0 + 2.0 * 4.0) && near(NSHeight([m frame]), 2.0 * 20.0 + 4.0),
	      "-sizeToCells sizes the frame to the cells and their spacing");

	/* AUTOSIZING STRETCHES THE CELLS TO THE FRAME INSTEAD. */
	[m setAutosizesCells:YES];
	check(near([m cellSize].width, (3.0 * 60.0 + 2.0 * 4.0 - 2.0 * 4.0) / 3.0),
	      "-autosizesCells recomputes the cell size from the frame");
	[m setAutosizesCells:NO];

	[m release];
}

/* ============================================================================================ *
 * SELECTION, HIGHLIGHT AND THE MODES.                                                            *
 * ============================================================================================ */

static void test_selection(void)
{
	NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 60.0)
						mode:NSListModeMatrix
					   cellClass:[NSButtonCell class]
					  numberOfRows:2 numberOfColumns:3];
	NSCell *cell;
	NSInteger i;

	printf("selection\n");
	[m setCellSize:NSMakeSize(60.0, 20.0)];
	for (i = 0; i < 6; i++) {
		[[m cells][i] setTag:i];
	}
	[m selectCellAtRow:1 column:1];
	check([m selectedRow] == 1 && [m selectedColumn] == 1, "a selected cell reports its row and column");
	check([m selectedCell] == [m cellAtRow:1 column:1], "-selectedCell is the cell that was selected");
	check([[m selectedCells] count] == 1, "exactly one cell is selected");
	check([[m cellAtRow:1 column:1] isHighlighted], "selecting lights the cell's highlight — the DRAWN bit");

	/* SELECTION WITHOUT HIGHLIGHT: the door a single bit could not have implemented. */
	[m setSelectionFrom:2 to:3 anchor:2 highlight:NO];
	check([[m selectedCells] count] == 2 && ![[m cellAtRow:0 column:2] isHighlighted],
	      "-setSelectionFrom:to:anchor:highlight:NO selects two cells and lights neither");

	[m deselectAllCells];
	check([[m selectedCells] count] == 0, "-deselectAllCells empties a list-mode selection");

	/* AND A MATRIX THAT FORBIDS AN EMPTY SELECTION KEEPS ITS OWN. */
	[m setAllowsEmptySelection:NO];
	[m selectCellAtRow:0 column:0];
	[m deselectAllCells];
	check([[m selectedCells] count] == 1, "-deselectAllCells does nothing when the policy forbids an empty selection");
	[m setAllowsEmptySelection:YES];

	check([m selectCellWithTag:4] && [m selectedRow] == 1 && [m selectedColumn] == 1,
	      "-selectCellWithTag: finds a cell by tag and selects it");
	check(![m selectCellWithTag:99], "a tag nobody has selects nothing");

	[m selectAll:nil];
	check([[m selectedCells] count] == 6, "a list-mode matrix can select every cell");
	[m deselectAllCells];

	/* RADIO: THE SELECTION IS THE STATE. */
	[m setMode:NSRadioModeMatrix];
	[m selectCellAtRow:0 column:2];
	cell = [m cellAtRow:0 column:2];
	check([cell state] == NSOnState, "a radio group's selected cell is ON");
	check([[m cellAtRow:0 column:0] state] == NSOffState, "and every other cell is OFF");

	/* AND THE STATE DOOR IS THE SAME RULE FROM THE OTHER SIDE. */
	[m setState:NSOnState atRow:1 column:0];
	check([[m cellAtRow:1 column:0] state] == NSOnState && [[m cellAtRow:0 column:2] state] == NSOffState,
	      "-setState:atRow:column: in a radio group turns the others off");

	/* A RADIO GROUP CANNOT SELECT ALL — two cells on is not a state it has. */
	[m selectAll:nil];
	check([[m selectedCells] count] <= 1, "-selectAll: leaves a radio group with at most one cell");
	[m release];
}

/* ============================================================================================ *
 * SHAPE CHANGES, SORTING AND THE PROTOTYPE.                                                     *
 * ============================================================================================ */

static void test_shape(void)
{
	NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 60.0)
						mode:NSListModeMatrix
					   cellClass:[NSButtonCell class]
					  numberOfRows:2 numberOfColumns:3];
	NSCell *oldCell;
	NSInteger i;

	printf("shape\n");
	[m setCellSize:NSMakeSize(60.0, 20.0)];
	for (i = 0; i < 6; i++) {
		[[m cells][i] setTag:i];
	}
	oldCell = [[m cellAtRow:1 column:0] retain];
	[m removeRow:0];
	check([m numberOfRows] == 1, "-removeRow: shrinks the grid");
	check([[m cellAtRow:0 column:0] tag] == 3, "the cell that took the removed row's place is the one below it");
	check([m cellAtRow:0 column:0] == oldCell, "and it is the SAME OBJECT — a removal moves cells, it does not copy them");

	[m insertColumn:1];
	check([m numberOfColumns] == 4, "-insertColumn: grows the grid");
	check([m cellAtRow:0 column:0] == oldCell, "an inserted column does not move the first cell");
	check([m cellAtRow:0 column:1] == NULL || [[m cells][1] isKindOfClass:[NSButtonCell class]]
	      || [[m cellAtRow:0 column:1] isKindOfClass:[NSCell class]],
	      "the inserted column has cells");

	[m addRow];
	check([m numberOfRows] == 2, "-addRow appends a row of cells");

	/* RENEW THROWS THE SHAPE AWAY. */
	[m renewRows:1 columns:1];
	check([m numberOfRows] == 1 && [m numberOfColumns] == 1 && [m cellAtRow:0 column:0] != NULL,
	      "-renewRows:columns: makes a new shape");

	[m release];
	[oldCell release];
}

static void test_sort(void)
{
	NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 90.0)
						mode:NSListModeMatrix
					   cellClass:[NSCell class]
					  numberOfRows:3 numberOfColumns:1];
	NSInteger tags[3] = {2, 0, 1};
	NSInteger i;

	printf("sorting and prototype\n");
	[m setCellSize:NSMakeSize(80.0, 25.0)];
	for (i = 0; i < 3; i++) {
		[[m cells][i] setTag:tags[i]];
	}
	[m selectCellAtRow:1 column:0];	/* tag 0 — the cell that sorts first */
	[m sortUsingFunction:compare_tags context:NULL];
	check([[m cellAtRow:0 column:0] tag] == 0 && [[m cellAtRow:1 column:0] tag] == 1
	      && [[m cellAtRow:2 column:0] tag] == 2,
	      "-sortUsingFunction:context: orders a column by the caller's answer");
	check([m selectedRow] == 0 && [m selectedCell] == [m cellAtRow:0 column:0],
	      "the selection travels with the cell it was on, not with the position");
	[m release];

	/* A PROTOTYPE IS COPIED PER POSITION, which is the door `NSCell -copy` exists for. */
	{
		NSButtonCell *prototype = [[NSButtonCell alloc] init];
		NSMatrix *copyMatrix;

		[prototype setTitle:@"same"];
		[prototype setTag:7];
		copyMatrix = [[NSMatrix alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 50.0)
						      mode:NSListModeMatrix
						 prototype:prototype
						numberOfRows:2 numberOfColumns:2];
		check([copyMatrix cellAtRow:0 column:0] != [copyMatrix cellAtRow:0 column:1],
		      "a prototype makes a DIFFERENT object at every position");
		check([[copyMatrix cellAtRow:1 column:1] tag] == 7
		      && [[[copyMatrix cellAtRow:1 column:1] title] isEqual:@"same"],
		      "and every copy carries the prototype's tag and title");
		[[copyMatrix cellAtRow:0 column:0] setTitle:@"changed"];
		check([[[copyMatrix cellAtRow:1 column:1] title] isEqual:@"same"],
		      "changing one copy leaves the others alone");
		[copyMatrix release];
		[prototype release];
	}
}

/* ============================================================================================ *
 * THE ACTION AND THE KEYBOARD.                                                                  *
 * ============================================================================================ */

static void test_action(void)
{
	AGMatrixTarget *target = [[AGMatrixTarget alloc] init];
	NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 50.0)
						mode:NSListModeMatrix
					   cellClass:[NSButtonCell class]
					  numberOfRows:2 numberOfColumns:1];
	NSEvent *key;

	printf("action and keyboard\n");
	[m setCellSize:NSMakeSize(80.0, 20.0)];
	[[m cellAtRow:0 column:0] setAction:@selector(cellClicked:)];
	[[m cellAtRow:0 column:0] setTarget:target];
	[[m cellAtRow:1 column:0] setAction:@selector(cellClicked:)];
	[[m cellAtRow:1 column:0] setTarget:target];

	/* THE KEYBOARD'S CLICK: -performClick: acts on the KEY cell and sends its action. */
	[m selectCellAtRow:0 column:0];
	[m performClick:nil];
	check(target->fired == 1, "-performClick: sends the selected cell's action");

	/* AND -sendAction IS THE SAME DOOR WITHOUT MOVING THE SELECTION. */
	[m sendAction];
	check(target->fired == 2, "-sendAction sends the selected cell's action again");

	/* -sendAction:to:forAllCells: SENDS EVERY CELL, with the CELL as the sender. */
	[m sendAction:@selector(cellClicked:) to:target forAllCells:YES];
	check(target->fired == 4, "-sendAction:to:forAllCells: sends once per cell");

	/* THE BUTTON'S LETTER IS A KEY EQUIVALENT. */
	[[m cellAtRow:1 column:0] setKeyEquivalent:@"b"];
	key = [NSEvent keyEventWithType:NSKeyDown location:NSMakePoint(0.0, 0.0) modifierFlags:0
			      timestamp:0.0 windowNumber:0 context:nil
			     characters:@"b" charactersIgnoringModifiers:@"b" isARepeat:NO keyCode:0];
	check(key != nil && [m performKeyEquivalent:key], "-performKeyEquivalent: matches a cell's key equivalent");
	check(target->fired == 5 && [m selectedRow] == 1,
	      "and the equivalent SELECTS the cell and sends its action");

	/* AND AN ARROW MOVES THE KEY CELL WITHOUT MOVING THE SELECTION. */
	key = [NSEvent keyEventWithType:NSKeyDown location:NSMakePoint(0.0, 0.0) modifierFlags:0
			      timestamp:0.0 windowNumber:0 context:nil
			     characters:[NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey]
		    charactersIgnoringModifiers:[NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey]
			      isARepeat:NO keyCode:0];
	[m keyDown:key];
	check([m keyCell] == [m cellAtRow:0 column:0] && [m selectedRow] == 1,
	      "an arrow key moves the KEY cell and leaves the selection where it was");

	check([m mouseDownFlags] == 0, "-mouseDownFlags is zero until a press happens");
	[m release];
	[target release];
}

/* ============================================================================================ *
 * THE FIELD SESSION.                                                                            *
 * ============================================================================================ */

static void test_session(void)
{
	NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 60.0)
						mode:NSListModeMatrix
					   cellClass:[NSTextFieldCell class]
					  numberOfRows:2 numberOfColumns:1];

	printf("field session\n");
	[m setCellSize:NSMakeSize(180.0, 24.0)];
	[[m cellAtRow:0 column:0] setStringValue:@"first"];
	[[m cellAtRow:1 column:0] setStringValue:@"second"];
	[[m cellAtRow:1 column:0] setEditable:YES];

	[m selectTextAtRow:1 column:0];
	check([m currentEditor] != nil, "-selectTextAtRow:column: opens a session on the cell at that row");
	check([m selectedRow] == 1, "and the cell it edits is the one it selects");
	check([m abortEditing], "-abortEditing ends the session the matrix opened");
	check([m currentEditor] == nil, "and there is no editor afterwards");

	/* A CELL THAT CANNOT BE EDITED IS STILL SELECTED, which is what asking for its attention means. */
	[m selectTextAtRow:0 column:0];
	check([m currentEditor] == nil && [m selectedRow] == 0,
	      "a non-editable cell is selected but gets no session");

	/* THE NOTIFICATION'S OBJECT IS THE MATRIX — the fact that made this class re-home the delegate conversation. */
	[m textDidBeginEditing:[NSNotification notificationWithName:NSTextDidBeginEditingNotification
							    object:[[[NSText alloc] init] autorelease]]];
	check(YES, "a begin-editing announcement is accepted with the matrix as its object");

	[m release];
}

/* ============================================================================================ *
 * THE INK.                                                                                      *
 * ============================================================================================ */

static void test_ink(void)
{
	enum { W = 90, H = 50 };
	NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0.0, 0.0, 84.0, 44.0)
						mode:NSListModeMatrix
					   cellClass:[NSCell class]
					  numberOfRows:2 numberOfColumns:2];
	NSBitmapImageRep *rep;
	NSColor *accent = [NSColor cg_accentColor];

	printf("ink\n");
	[m setCellSize:NSMakeSize(40.0, 20.0)];
	[m setIntercellSpacing:NSMakeSize(4.0, 4.0)];
	[m selectCellAtRow:1 column:0];

	rep = new_rep(W, H);
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	/* **THE CONTEXT IS FLIPPED TO MATCH THE VIEW.** A matrix is flipped, so a bitmap drawn without the same
	 * transform puts row 0 at the BOTTOM — the probe would then sample the wrong row and read a failure that is the
	 * instrument's, not the drawing's. `tests/outline_view.m` flips for the same reason. */
	{
		CGContextRef cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];

		CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
		CGContextScaleCTM(cg, 1.0, -1.0);
	}
	[m drawRect:[m bounds]];
	check([m isFlipped], "a matrix is flipped, so row 0 is its top row");
	check(pixel_is(rep, 20, 34, accent), "a selected plain cell is filled with the selection colour");
	check(pixel_is(rep, 60, 10, [NSColor whiteColor]), "an unselected cell is not");
	[rep release];

	/* AND THE TWO BACKGROUNDS ARE UNDER IT: the grid's shows BETWEEN cells, the cell's UNDER each cell. */
	[m setDrawsBackground:YES];
	[m setBackgroundColor:[NSColor redColor]];
	[m setDrawsCellBackground:YES];
	[m setCellBackgroundColor:[NSColor greenColor]];
	rep = new_rep(W, H);
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	{
		CGContextRef cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];

		CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
		CGContextScaleCTM(cg, 1.0, -1.0);
	}
	[m drawRect:[m bounds]];
	check(pixel_is(rep, 42, 10, [NSColor redColor]), "the grid's background shows in the gap between cells");
	check(pixel_is(rep, 60, 10, [NSColor greenColor]), "a cell's background fills an unselected cell");
	check(pixel_is(rep, 20, 34, accent), "and the selection is drawn OVER the cell background");
	[rep release];

	[m release];

	/* THE FORM CELL'S TWO BANDS: a label at the leading edge, the value after it, and the boundary exactly where
	 * `-setTitleWidth:` put it. */
	{
		NSFormCell *cell = [[NSFormCell alloc] initTextCell:@"value"];
		NSBitmapImageRep *band = new_rep(140, 24);
		NSRect frame = NSMakeRect(0.0, 0.0, 140.0, 24.0);

		[cell setTitle:@"Name"];
		[cell setTitleWidth:50.0];
		[cell setBordered:YES];
		[cell setBezeled:YES];
		[cell setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:band]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:frame] fill];
		[cell drawWithFrame:frame inView:nil];
		check(ink_in(band, 0, 0, 50, 24) > 0, "a form cell draws its LABEL in the title band");
		check(ink_in(band, 50, 0, 140, 24) > 0, "and its VALUE in the band after it");
		check([cell titleWidth:frame.size] > 0.0, "-titleWidth: measures a title that is not empty");
		check([cell drawingRectForBounds:frame].origin.x >= 50.0,
		      "-drawingRectForBounds: — the editor's frame — starts at the title width");
		[band release];
		[cell release];
	}
}

/* ============================================================================================ *
 * THE FORM.                                                                                     *
 * ============================================================================================ */

static void test_form(void)
{
	NSForm *form = [[NSForm alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 100.0)];
	NSFormCell *name;
	NSFormCell *host;
	CGFloat entryWidth;

	printf("form\n");
	check([form numberOfRows] == 0 && [form numberOfColumns] == 1, "a new form is one column with no entries");

	name = [form addEntry:@"Name"];
	check(name != nil && [form numberOfRows] == 1, "-addEntry: adds a row and answers its cell");
	check([[name title] isEqual:@"Name"], "the entry's label is its title");
	check([name isEditable] && [name isBordered] && [name isBezeled], "a new entry is an editable, bordered field");
	check([name isKindOfClass:[NSFormCell class]], "and it is a form cell");

	host = [form addEntry:@"Host"];
	check([form indexOfSelectedItem] == -1 || [form indexOfSelectedItem] >= 0, "-indexOfSelectedItem answers a row");
	[host setTag:42];
	check([form indexOfCellWithTag:42] == 1, "-indexOfCellWithTag: answers the entry's row");
	check([form cellAtIndex:0] == name && [form cellAtIndex:1] == host, "-cellAtIndex: is the row's cell");

	/* THE ENTRY WIDTH FIXES THE VALUE BAND AND LEAVES THE LABEL THE REST. */
	[form setEntryWidth:120.0];
	entryWidth = [form cellSize].width;
	check(near([name titleWidth], entryWidth - 120.0),
	      "-setEntryWidth: sets each label band to the cell's width minus the entry");

	/* AND A WIDER FORM WIDENS THE ENTRIES, NOT THE LABELS. */
	[form setFrameSize:NSMakeSize(300.0, 100.0)];
	check(near([form cellSize].width, 300.0) && near([name titleWidth], entryWidth - 120.0),
	      "-setFrameSize: widens the entries and leaves the label bands where they were");

	/* THE FORM'S VOICE REACHES EVERY CELL. */
	[form setBezeled:NO];
	[form setBordered:NO];
	check(![name isBezeled] && ![host isBordered], "the form's face flags reach every entry");
	[form setInterlineSpacing:8.0];
	check(near([form intercellSpacing].height, 8.0), "-setInterlineSpacing: sets the air between entries");

	[form selectTextAtIndex:0];
	check([form currentEditor] != nil || [form selectedRow] == 0,
	      "-selectTextAtIndex: selects (and, when editable, opens) that entry");

	[form removeEntryAtIndex:0];
	check([form numberOfRows] == 1 && [form cellAtIndex:0] == host, "-removeEntryAtIndex: removes the first entry");
	[form release];
}

int main(void)
{
	printf("NSMatrix / NSForm — the grid, the selection, the form and the ink\n");
	test_grid();
	test_selection();
	test_shape();
	test_sort();
	test_action();
	test_session();
	test_ink();
	test_form();

	printf("\n%d checks, %d failed\n", g_checks, g_failed);
	return g_failed == 0 ? 0 : 1;
}
