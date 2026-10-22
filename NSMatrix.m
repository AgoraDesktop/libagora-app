/*
 * NSMatrix — a rectangular grid of cells.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE ONE CLASS IN THIS TIER WHOSE FACE IS PLURAL.** Every control before it owned a cell; this one owns a grid of
 * them, and everything hard about it comes from that: a click has to become a (row, column), a selection has to be a
 * set rather than a value, a tab has to move a cell rather than leave a control, and an edit session has to remember
 * WHICH cell it belongs to. The header states the three owned things; this file is where they are kept.
 *
 * THREE DECISIONS THIS FILE MAKES THAT THE HEADER DOES NOT, all of them about where a fact lives:
 *
 *   1. SELECTION AND HIGHLIGHT ARE TWO BITS. `_selected` is the selection; `[cell isHighlighted]` is whether it is
 *      DRAWN as selected. They are set together by every selecting door except
 *      `-setSelectionFrom:to:anchor:highlight:`, which is the door that exists because they can differ. A caller that
 *      calls `-highlightCell:atRow:column:` is changing the second and not the first.
 *   2. THE TARGET/ACTION PAIR IS THE MATRIX'S OWN, and the four `NSControl` doors are overridden rather than forwarded.
 *      `NSControl` stores the pair on its single cell; a matrix has no single cell, so forwarding would read a nil cell
 *      and answer nothing. Each CELL still keeps its own pair, which is what `-sendAction:to:forAllCells:` and a
 *      per-cell target read.
 *   3. THE GRID IS FLAT. `-cells` publishes `NSCell **` in row-major order because that is Apple's shape, so this file
 *      keeps one `rows × columns` array and indexes it — insertion and removal are memmoves rather than array-of-rows
 *      surgery. `_selected` is the same shape, so the two cannot drift.
 *
 * THE TRACKING LOOP IS `NSControl`'s, WITH A CELL UNDER THE POINTER RATHER THAN THE WHOLE VIEW. It is the same shape
 * deliberately: the same 1/60 s wait that paces a frame, the same drain of queued motions into one draw, the same
 * "nothing came" branch, and the same guard for a program with no event source — and `tests/matrix.m` drives the press
 * through it rather than through the selection doors, which is what makes the loop a tested claim.
 */
#import <AppKit/NSMatrix.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSText.h>
#import <Foundation/NSValue.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

/* ============================================================================================ *
 * PRIVATE DOORS. The house rule is that a class declares its surface in its header, so the    *
 * helpers that are not Apple's live in a class extension rather than in the public block.     *
 * ============================================================================================ */
@interface NSMatrix ()
/* THE DEFAULTS EVERY DESIGNATED INITIALISER STARTS FROM, in one place because the three must not chain through an
 * overridable initialiser — see the method's own note. */
- (void)fn_initDefaults;

/* THE ARRAYS. `-fn_allocate` makes `rows × columns` zeroed cells and selection bits; `-fn_free` releases what the
 * arrays retain and frees them. Every shape change goes through the pair rather than editing in place. */
- (void)fn_allocateRows:(NSInteger)rows columns:(NSInteger)columns;
- (void)fn_freeCells;
- (void)fn_freeSelection;

/* ONE CELL IN, ONE CELL OUT, with the control view wired — the one rule every insertion shares. */
- (void)fn_setCell:(nullable NSCell *)cell atIndex:(NSInteger)index;
- (nullable NSCell *)fn_makeCellAtRow:(NSInteger)row column:(NSInteger)column;

/* THE SELECTION'S FOUR PRIMITIVES, which the public doors are combinations of. */
- (BOOL)fn_isSelectedAtIndex:(NSInteger)index;
- (void)fn_setSelected:(BOOL)flag atIndex:(NSInteger)index highlight:(BOOL)lit;
- (void)fn_clearSelectionHighlighting:(BOOL)lit;
- (void)fn_selectOnlyIndex:(NSInteger)index highlight:(BOOL)lit;

/* THE INDEX ARITHMETIC AND THE INVERSE LOOKUPS. */
- (BOOL)fn_isLegalRow:(NSInteger)row column:(NSInteger)column;
- (NSInteger)fn_indexAtRow:(NSInteger)row column:(NSInteger)column;
- (NSInteger)fn_indexOfCell:(nullable NSCell *)cell;

/* THE TWO LAYOUT RULES: the size a cell is drawn at, and the frame of one. */
- (NSSize)fn_laidOutCellSize;
- (NSRect)fn_cellFrameAtIndex:(NSInteger)index;

/* THE CLICK: what a press on a cell means in the current mode, and what a drag to a point does. */
- (void)fn_applyClickAtRow:(NSInteger)row column:(NSInteger)column event:(nullable NSEvent *)event;
- (void)fn_trackPoint:(NSPoint)point;

/* THE ACTION'S CELL: the tracked one while a press is live, the selected one otherwise. */
- (nullable NSCell *)fn_actionCell;

/* THE EDITING CELL, as an index, and the editor that cell is using. */
- (void)fn_endSessionIfAny;
- (nullable NSCell *)fn_editingCell;

/* AND THE TWO ARITHMETICS A FRAME CHANGE CAN DO, named so the difference is in one place. */
- (void)fn_autosizeCellsToFrame;
@end

@implementation NSMatrix

/* ============================================================================================ *
 * LIFETIME AND THE SHAPE.                                                                       *
 * ============================================================================================ */

- (void)fn_initDefaults
{
	/* **THE DEFAULTS, EACH ONE A DECISION RATHER THAN A ZERO.** The mode is LIST because a matrix with no policy
	 * is a list of cells; the two selections defaults are Apple's (an empty selection is allowed, a rectangle
	 * drag is not); the tab traverses, because a form is the class's other face. THE BACKGROUND IS OFF, which is
	 * the one default worth naming: a matrix used for a row of radio buttons sits on its window's face, and a
	 * matrix that painted a grey rectangle under itself by default would be a grey rectangle in every dialog
	 * that did not ask for one. `NSForm` turns it on, because a form IS a panel.
	 *
	 * **IT IS A METHOD RATHER THAN THE BODY OF `-initWithFrame:` BECAUSE THE THREE DESIGNATED INITIALISERS MUST NOT
	 * CHAIN THROUGH AN OVERRIDABLE DOOR.** An earlier draft had the two `mode:` variants call `[self initWithFrame:]`,
	 * which is Apple's idiom and a trap here: `NSForm` overrides `-initWithFrame:` and calls the `mode:` variant, so
	 * the two called each other forever (MEASURED as a stack overflow in `-initWithFrame:`). The variants therefore
	 * start at `NSControl` and run this method themselves. */
		_rows = 0;
		_columns = 0;
		_cells = NULL;
		_selected = NULL;
		_anchor = -1;
		_cellClass = Nil;
		_prototype = nil;
		_cellSize = NSMakeSize(0.0, 0.0);
		_intercellSpacing = NSMakeSize(0.0, 0.0);
		_mode = NSListModeMatrix;
		_allowsEmptySelection = YES;
		_selectionByRect = NO;
		_autosizesCells = NO;
		_validateSize = NO;
		_autoscroll = NO;
		_tabKeyTraversesCells = YES;
		_scrollable = NO;
		_drawsBackground = NO;
		_drawsCellBackground = NO;
		_backgroundColor = nil;
		_cellBackgroundColor = nil;
		_delegate = nil;
		_doubleAction = NULL;
		_mouseDownFlags = 0;
		_editingIndex = -1;
		_trackingIndex = -1;
		_keyRow = 0;
		_keyColumn = 0;
		_target = nil;
		_action = NULL;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		[self fn_initDefaults];
	}
	return self;
}

- (void)dealloc
{
	/* **THE SESSION GOES FIRST.** An editor still up when its cell's matrix goes away is a field editor whose delegate
	 * points at freed storage; ending it here is the one order on which the rest of this teardown is safe. */
	[self fn_endSessionIfAny];
	[self fn_freeCells];
	[self fn_freeSelection];
	[_prototype release];
	[_backgroundColor release];
	[_cellBackgroundColor release];
	[_cellToolTips release];
	[super dealloc];
}

- (instancetype)initWithFrame:(NSRect)aRect mode:(NSMatrixMode)aMode cellClass:(Class)aClass
		 numberOfRows:(NSInteger)numberOfRows numberOfColumns:(NSInteger)numberOfColumns
{
	self = [super initWithFrame:aRect];
	if (self != nil) {
		[self fn_initDefaults];
		_mode = aMode;
		_cellClass = (aClass != Nil) ? aClass : [NSCell class];
		[self fn_allocateRows:numberOfRows columns:numberOfColumns];
		/* **AND THE CELL SIZE IS TAKEN FROM ONE INSTANCE OF THE CLASS**, which is Apple's rule and the only one that
		 * makes `initWithFrame:mode:cellClass:…` usable without a second call: a matrix of buttons should come out
		 * button-sized. A class whose cells have no opinion answers the base cell's (10000, 10000) sentinel, and the
		 * clamp below keeps that from becoming a grid larger than any screen — see `-fn_laidOutCellSize`. */
		{
			NSCell *probe = [[_cellClass alloc] init];
			NSSize measured = [probe cellSize];

			_cellSize = NSMakeSize(measured.width >= 10000.0 ? 0.0 : measured.width,
					       measured.height >= 10000.0 ? 0.0 : measured.height);
			[probe release];
		}
	}
	return self;
}

- (instancetype)initWithFrame:(NSRect)aRect mode:(NSMatrixMode)aMode prototype:(NSCell *)aCell
		 numberOfRows:(NSInteger)numberOfRows numberOfColumns:(NSInteger)numberOfColumns
{
	self = [super initWithFrame:aRect];
	if (self != nil) {
		NSSize measured;

		[self fn_initDefaults];
		_mode = aMode;
		[self setPrototype:aCell];
		measured = [aCell cellSize];
		_cellSize = NSMakeSize(measured.width >= 10000.0 ? 0.0 : measured.width,
				       measured.height >= 10000.0 ? 0.0 : measured.height);
		[self fn_allocateRows:numberOfRows columns:numberOfColumns];
	}
	return self;
}

/* ============================================================================================ *
 * THE ARRAYS AND ONE CELL.                                                                      *
 * ============================================================================================ */

- (void)fn_freeCells
{
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		[_cells[i] release];
	}
	free(_cells);
	_cells = NULL;
	[_cellToolTips removeAllObjects];
}

- (void)fn_freeSelection
{
	free(_selected);
	_selected = NULL;
}

- (void)fn_allocateRows:(NSInteger)rows columns:(NSInteger)columns
{
	NSInteger r, c;

	/* A NEGATIVE COUNT IS NO CELLS RATHER THAN A CRASH, because a shape computed by a caller can be either sign. */
	if (rows < 0) {
		rows = 0;
	}
	if (columns < 0) {
		columns = 0;
	}
	[self fn_freeCells];
	[self fn_freeSelection];
	_rows = rows;
	_columns = columns;
	/* **A SHAPE WITH ZERO ROWS IS A SHAPE, WHICH IS WHY THE COLUMN COUNT SURVIVES IT.** An empty `NSForm` is a
	 * one-column matrix with no entries, and collapsing it to zero columns — which an earlier draft of this method did —
	 * would leave `-addRow` with nowhere to put a cell. So the two counts are stored as given and only the ALLOCATION
	 * is conditional. */
	_anchor = -1;
	_editingIndex = -1;
	_trackingIndex = -1;
	_keyRow = 0;
	_keyColumn = 0;
	if (_rows <= 0 || _columns <= 0) {
		_rows = (_rows > 0) ? _rows : 0;
		_columns = (_columns > 0) ? _columns : 0;
		return;
	}
	_cells = (NSCell **)calloc((size_t)(_rows * _columns), sizeof(NSCell *));
	_selected = (BOOL *)calloc((size_t)(_rows * _columns), sizeof(BOOL));
	for (r = 0; r < _rows; r++) {
		for (c = 0; c < _columns; c++) {
			NSCell *cell = [self fn_makeCellAtRow:r column:c];

			if (cell != nil) {
				/* OWNED BY THE ARRAY from here: `-fn_makeCellAtRow:` hands back a +1 reference. */
				_cells[r * _columns + c] = cell;
			}
		}
	}
}

- (void)fn_setCell:(NSCell *)cell atIndex:(NSInteger)index
{
	NSCell *old;

	if (index < 0 || index >= _rows * _columns) {
		return;
	}
	old = _cells[index];
	if (cell != nil) {
		[cell setControlView:self];
		if (_scrollable) {
			[cell setScrollable:YES];
		}
		[cell retain];
	}
	_cells[index] = cell;
	[old release];
}

- (NSCell *)fn_makeCellAtRow:(NSInteger)row column:(NSInteger)column
{
	/* THE ROW AND COLUMN ARE NOT READ, and the parameters are here because a SUBCLASS overrides this door to make a
	 * different cell at a different position — which is Apple's reason for publishing it with them. */
	NSCell *cell = nil;

	(void)row;
	(void)column;
	if (_prototype != nil) {
		/* **A COPY OF THE PROTOTYPE, WHICH IS WHAT APPLE'S DOCUMENTATION PROMISES** — so every position starts from
		 * the same configured cell and not from one shared object drawn in N places. The copy is the cell's own
		 * `-copy`; see `NSCell -copyWithZone:` for how a cell clones itself in this tree. */
		cell = [_prototype copy];
	} else if (_cellClass != Nil) {
		cell = [[_cellClass alloc] init];
	}
	if (cell != nil) {
		[cell setControlView:self];
		if (_scrollable) {
			[cell setScrollable:YES];
		}
	}
	return cell;
}

/* ============================================================================================ *
 * THE GRID'S PUBLIC SHAPE.                                                                      *
 * ============================================================================================ */

- (void)getNumberOfRows:(NSInteger *)rowCount columns:(NSInteger *)columnCount
{
	if (rowCount != NULL) {
		*rowCount = _rows;
	}
	if (columnCount != NULL) {
		*columnCount = _columns;
	}
}

- (NSInteger)numberOfRows
{
	return _rows;
}

- (NSInteger)numberOfColumns
{
	return _columns;
}

- (NSCell **)cells
{
	return _cells;
}

- (BOOL)fn_isLegalRow:(NSInteger)row column:(NSInteger)column
{
	return row >= 0 && row < _rows && column >= 0 && column < _columns;
}

- (NSInteger)fn_indexAtRow:(NSInteger)row column:(NSInteger)column
{
	return [self fn_isLegalRow:row column:column] ? (row * _columns + column) : -1;
}

- (NSCell *)cellAtRow:(NSInteger)row column:(NSInteger)column
{
	NSInteger index = [self fn_indexAtRow:row column:column];

	return (index >= 0) ? _cells[index] : nil;
}

- (NSCell *)cellWithTag:(NSInteger)tag
{
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		if (_cells[i] != nil && [_cells[i] tag] == tag) {
			return _cells[i];
		}
	}
	return nil;
}

- (NSInteger)fn_indexOfCell:(NSCell *)cell
{
	NSInteger i, count = _rows * _columns;

	if (cell == nil) {
		return -1;
	}
	for (i = 0; i < count; i++) {
		if (_cells[i] == cell) {
			return i;
		}
	}
	return -1;
}

/* ---- AND THE FOUR SHAPE CHANGES ------------------------------------------------------------------- */

/* **A ROW OR COLUMN IS INSERTED BY COPYING THE ARRAYS UP AND SHIFTING ONE SLICE.** The row-major layout makes that a
 * memmove per column for a row, and a memmove per row for a column, so the two helpers below are the whole of both. */
- (void)addRow
{
	[self insertRow:_rows withCells:NULL];
}

- (void)addRowWithCells:(NSCell **)newCells
{
	[self insertRow:_rows withCells:newCells];
}

- (void)addColumn
{
	[self insertColumn:_columns withCells:NULL];
}

- (void)addColumnWithCells:(NSCell **)newCells
{
	[self insertColumn:_columns withCells:newCells];
}

- (void)insertRow:(NSInteger)row
{
	[self insertRow:row withCells:NULL];
}

- (void)insertRow:(NSInteger)row withCells:(NSCell **)newCells
{
	NSInteger newRows, r, c;
	NSInteger anchorRow = (_anchor >= 0 && _columns > 0) ? _anchor / _columns : -1;
	NSInteger anchorColumn = (_anchor >= 0 && _columns > 0) ? _anchor % _columns : -1;
	NSCell **oldCells = _cells;
	BOOL *oldSelected = _selected;

	if (row < 0) {
		row = 0;
	}
	if (row > _rows) {
		row = _rows;
	}
	newRows = _rows + 1;
	_cells = (NSCell **)calloc((size_t)(newRows * _columns > 0 ? newRows * _columns : 1), sizeof(NSCell *));
	_selected = (BOOL *)calloc((size_t)(newRows * _columns > 0 ? newRows * _columns : 1), sizeof(BOOL));
	for (r = 0; r < newRows; r++) {
		for (c = 0; c < _columns; c++) {
			NSInteger dest = r * _columns + c;

			if (r < row) {
				_cells[dest] = oldCells[r * _columns + c];
				_selected[dest] = oldSelected[r * _columns + c];
			} else if (r == row) {
				if (newCells != NULL && newCells[c] != nil) {
					_cells[dest] = [newCells[c] retain];
				} else {
					_cells[dest] = [self fn_makeCellAtRow:r column:c];
				}
				_selected[dest] = NO;
			} else {
				_cells[dest] = oldCells[(r - 1) * _columns + c];
				_selected[dest] = oldSelected[(r - 1) * _columns + c];
			}
		}
	}
	free(oldCells);
	free(oldSelected);
	_rows = newRows;
	/* **AN INSERTION ABOVE OR AT THE SELECTION MOVES ITS LINEAR INDEX, so the anchor is carried as a ROW AND COLUMN
	 * across the change and rebuilt after it** — a linear index kept as-is would name a different cell. The selection
	 * bits themselves travelled with their cells in the loop above. */
	if (anchorRow >= row) {
		anchorRow++;
	}
	_anchor = (anchorRow >= 0) ? (anchorRow * _columns + anchorColumn) : -1;
	_editingIndex = -1;
	_trackingIndex = -1;
	[self setNeedsDisplay:YES];
}

- (void)insertColumn:(NSInteger)column
{
	[self insertColumn:column withCells:NULL];
}

- (void)insertColumn:(NSInteger)column withCells:(NSCell **)newCells
{
	NSInteger newColumns, r, c;
	NSInteger anchorRow = (_anchor >= 0 && _columns > 0) ? _anchor / _columns : -1;
	NSInteger anchorColumn = (_anchor >= 0 && _columns > 0) ? _anchor % _columns : -1;
	NSCell **oldCells = _cells;
	BOOL *oldSelected = _selected;

	if (column < 0) {
		column = 0;
	}
	if (column > _columns) {
		column = _columns;
	}
	newColumns = _columns + 1;
	_cells = (NSCell **)calloc((size_t)(_rows * newColumns > 0 ? _rows * newColumns : 1), sizeof(NSCell *));
	_selected = (BOOL *)calloc((size_t)(_rows * newColumns > 0 ? _rows * newColumns : 1), sizeof(BOOL));
	for (r = 0; r < _rows; r++) {
		for (c = 0; c < newColumns; c++) {
			NSInteger dest = r * newColumns + c;

			if (c < column) {
				_cells[dest] = oldCells[r * _columns + c];
				_selected[dest] = oldSelected[r * _columns + c];
			} else if (c == column) {
				if (newCells != NULL && newCells[r] != nil) {
					_cells[dest] = [newCells[r] retain];
				} else {
					_cells[dest] = [self fn_makeCellAtRow:r column:c];
				}
				_selected[dest] = NO;
			} else {
				_cells[dest] = oldCells[r * _columns + (c - 1)];
				_selected[dest] = oldSelected[r * _columns + (c - 1)];
			}
		}
	}
	free(oldCells);
	free(oldSelected);
	_columns = newColumns;
	if (anchorColumn >= column) {
		anchorColumn++;
	}
	_anchor = (anchorRow >= 0) ? (anchorRow * _columns + anchorColumn) : -1;
	_editingIndex = -1;
	_trackingIndex = -1;
	[self setNeedsDisplay:YES];
}

- (void)removeRow:(NSInteger)row
{
	NSInteger newRows, r, c;
	NSCell **oldCells = _cells;
	BOOL *oldSelected = _selected;

	if (row < 0 || row >= _rows) {
		return;
	}
	newRows = _rows - 1;
	if (newRows == 0 || _columns == 0) {
		[self fn_freeCells];
		[self fn_freeSelection];
		/* **THE COLUMN COUNT SURVIVES THE LAST ROW'S REMOVAL** — see `-fn_allocateRows:columns:`: an empty form is one
		 * column with no entries, not a matrix with no shape. */
		_rows = 0;
		_anchor = -1;
		_editingIndex = -1;
		_trackingIndex = -1;
		[self setNeedsDisplay:YES];
		return;
	}
	_cells = (NSCell **)calloc((size_t)(newRows * _columns), sizeof(NSCell *));
	_selected = (BOOL *)calloc((size_t)(newRows * _columns), sizeof(BOOL));
	for (c = 0; c < _columns; c++) {
		[oldCells[row * _columns + c] release];
	}
	for (r = 0; r < newRows; r++) {
		NSInteger source = (r < row) ? r : (r + 1);

		for (c = 0; c < _columns; c++) {
			_cells[r * _columns + c] = oldCells[source * _columns + c];
			_selected[r * _columns + c] = oldSelected[source * _columns + c];
		}
	}
	free(oldCells);
	free(oldSelected);
	_rows = newRows;
	_anchor = -1;
	_editingIndex = -1;
	_trackingIndex = -1;
	[self setNeedsDisplay:YES];
}

- (void)removeColumn:(NSInteger)column
{
	NSInteger newColumns, r, c;
	NSCell **oldCells = _cells;
	BOOL *oldSelected = _selected;

	if (column < 0 || column >= _columns) {
		return;
	}
	newColumns = _columns - 1;
	if (_rows == 0 || newColumns == 0) {
		[self fn_freeCells];
		[self fn_freeSelection];
		/* AND THE ROW COUNT SURVIVES THE LAST COLUMN'S REMOVAL, for the same reason. */
		_columns = 0;
		_anchor = -1;
		_editingIndex = -1;
		_trackingIndex = -1;
		[self setNeedsDisplay:YES];
		return;
	}
	_cells = (NSCell **)calloc((size_t)(_rows * newColumns), sizeof(NSCell *));
	_selected = (BOOL *)calloc((size_t)(_rows * newColumns), sizeof(BOOL));
	for (r = 0; r < _rows; r++) {
		[oldCells[r * _columns + column] release];
		for (c = 0; c < newColumns; c++) {
			NSInteger source = (c < column) ? c : (c + 1);

			_cells[r * newColumns + c] = oldCells[r * _columns + source];
			_selected[r * newColumns + c] = oldSelected[r * _columns + source];
		}
	}
	free(oldCells);
	free(oldSelected);
	_columns = newColumns;
	_anchor = -1;
	_editingIndex = -1;
	_trackingIndex = -1;
	[self setNeedsDisplay:YES];
}

- (void)renewRows:(NSInteger)newRows columns:(NSInteger)newColumns
{
	[self fn_allocateRows:newRows columns:newColumns];
	[self setNeedsDisplay:YES];
}

- (void)putCell:(NSCell *)newCell atRow:(NSInteger)row column:(NSInteger)column
{
	NSInteger index = [self fn_indexAtRow:row column:column];

	if (index < 0) {
		return;
	}
	[self fn_setCell:newCell atIndex:index];
	_selected[index] = NO;
	[self setNeedsDisplay:YES];
}

- (NSCell *)makeCellAtRow:(NSInteger)row column:(NSInteger)column
{
	return [[self fn_makeCellAtRow:row column:column] autorelease];
}

- (Class)cellClass
{
	return _cellClass;
}

- (void)setCellClass:(Class)cellClass
{
	_cellClass = cellClass;
}

- (NSCell *)prototype
{
	return _prototype;
}

- (void)setPrototype:(NSCell *)aCell
{
	/* **SETTING A PROTOTYPE SETS THE CLASS TOO**, because Apple says so and because the two answers to "what is a new
	 * cell" must not disagree: a prototype whose class was not the cell class would make `-cellClass` a lie for every
	 * cell made after it. The prototype is retained as it was given, not copied. */
	NSCell *old = _prototype;

	_prototype = [aCell retain];
	[old release];
	if (aCell != nil) {
		_cellClass = [aCell class];
	}
}

/* ============================================================================================ *
 * THE GEOMETRY.                                                                                 *
 * ============================================================================================ */

- (BOOL)isFlipped
{
	return YES;
}

- (NSSize)cellSize
{
	return [self fn_laidOutCellSize];
}

- (void)setCellSize:(NSSize)aSize
{
	_cellSize = aSize;
	[self setNeedsDisplay:YES];
}

- (NSSize)intercellSpacing
{
	return _intercellSpacing;
}

- (void)setIntercellSpacing:(NSSize)aSize
{
	_intercellSpacing = aSize;
	[self setNeedsDisplay:YES];
}

/* **THE SIZE A CELL IS DRAWN AT, which is one question with two answers.** With `-autosizesCells` on it is the
 * arithmetic that fills the receiver's bounds, recomputed every time it is asked — which is why a frame change needs no
 * notification. Otherwise it is the stored `-cellSize`. A grid with no cells has no cell size and answers the stored
 * one, so a caller asking before the shape exists gets a number rather than a division by zero. */
- (NSSize)fn_laidOutCellSize
{
	if (!_autosizesCells || _rows <= 0 || _columns <= 0) {
		return _cellSize;
	}
	{
		NSRect bounds = [self bounds];
		CGFloat w = (NSWidth(bounds) - (CGFloat)(_columns - 1) * _intercellSpacing.width) / (CGFloat)_columns;
		CGFloat h = (NSHeight(bounds) - (CGFloat)(_rows - 1) * _intercellSpacing.height) / (CGFloat)_rows;

		/* A FRAME TOO SMALL FOR THE SPACING ALONE LEAVES ZERO-SIZED CELLS rather than negative ones: a negative width
		 * is a rectangle that draws backwards, and the caller sees a matrix with nothing in it, which is the truth. */
		return NSMakeSize(w > 0.0 ? w : 0.0, h > 0.0 ? h : 0.0);
	}
}

- (NSRect)fn_cellFrameAtIndex:(NSInteger)index
{
	NSInteger row, column;
	NSSize size;

	if (index < 0 || index >= _rows * _columns) {
		return NSZeroRect;
	}
	row = index / _columns;
	column = index % _columns;
	size = [self fn_laidOutCellSize];
	return NSMakeRect((CGFloat)column * (size.width + _intercellSpacing.width),
			  (CGFloat)row * (size.height + _intercellSpacing.height),
			  size.width, size.height);
}

- (NSRect)cellFrameAtRow:(NSInteger)row column:(NSInteger)column
{
	return [self fn_cellFrameAtIndex:[self fn_indexAtRow:row column:column]];
}

- (BOOL)getRow:(NSInteger *)row column:(NSInteger *)column forPoint:(NSPoint)aPoint
{
	NSSize size = [self fn_laidOutCellSize];
	CGFloat strideX = size.width + _intercellSpacing.width;
	CGFloat strideY = size.height + _intercellSpacing.height;
	NSInteger r, c;
	CGFloat withinX, withinY;

	if (_rows <= 0 || _columns <= 0 || size.width <= 0.0 || size.height <= 0.0 || aPoint.x < 0.0 || aPoint.y < 0.0) {
		if (row != NULL) {
			*row = -1;
		}
		if (column != NULL) {
			*column = -1;
		}
		return NO;
	}
	r = (NSInteger)floor(aPoint.y / strideY);
	c = (NSInteger)floor(aPoint.x / strideX);
	if (r >= _rows || c >= _columns) {
		if (row != NULL) {
			*row = -1;
		}
		if (column != NULL) {
			*column = -1;
		}
		return NO;
	}
	withinY = aPoint.y - (CGFloat)r * strideY;
	withinX = aPoint.x - (CGFloat)c * strideX;
	if (row != NULL) {
		*row = r;
	}
	if (column != NULL) {
		*column = c;
	}
	/* **A GAP IS NOT A CELL.** The row and column are still reported — they name the cell the point is nearest to
	 * the top-left corner of — but the answer is NO, which is what a caller deciding whether a press is on a face
	 * asks. Apple's contract is the BOOL; the two out-parameters are useful either way. */
	return withinX < size.width && withinY < size.height;
}

- (BOOL)getRow:(NSInteger *)row column:(NSInteger *)column ofCell:(NSCell *)cell
{
	NSInteger index = [self fn_indexOfCell:cell];

	if (index < 0) {
		if (row != NULL) {
			*row = -1;
		}
		if (column != NULL) {
			*column = -1;
		}
		return NO;
	}
	if (row != NULL) {
		*row = index / _columns;
	}
	if (column != NULL) {
		*column = index % _columns;
	}
	return YES;
}

- (void)sizeToCells
{
	NSSize size = [self fn_laidOutCellSize];

	if (_rows <= 0 || _columns <= 0) {
		return;
	}
	[self setFrameSize:NSMakeSize((CGFloat)_columns * size.width + (CGFloat)(_columns - 1) * _intercellSpacing.width,
				      (CGFloat)_rows * size.height + (CGFloat)(_rows - 1) * _intercellSpacing.height)];
}

- (BOOL)autosizesCells
{
	return _autosizesCells;
}

- (void)setAutosizesCells:(BOOL)flag
{
	_autosizesCells = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (void)setValidateSize:(BOOL)flag
{
	_validateSize = flag ? YES : NO;
	if (_validateSize) {
		[self fn_autosizeCellsToFrame];
	}
}

- (void)setScrollable:(BOOL)flag
{
	NSInteger i, count = _rows * _columns;

	_scrollable = flag ? YES : NO;
	for (i = 0; i < count; i++) {
		[_cells[i] setScrollable:_scrollable];
	}
}

/* **A FRAME CHANGE IS THE ONE PLACE `-setValidateSize:` HAS A READER.** With the flag on, the stored cell size is
 * recomputed to fill the new frame ONCE — after which `-cellSize` answers the size actually in use, which is what a
 * caller asking the question after resizing wants. `-autosizesCells` is the other policy and does the same arithmetic
 * every time it is ASKED instead; the two are not alternatives to each other, and a matrix may have both. */
- (void)fn_autosizeCellsToFrame
{
	NSRect bounds = [self bounds];

	if (_rows <= 0 || _columns <= 0) {
		return;
	}
	_cellSize = NSMakeSize((NSWidth(bounds) - (CGFloat)(_columns - 1) * _intercellSpacing.width) / (CGFloat)_columns,
			       (NSHeight(bounds) - (CGFloat)(_rows - 1) * _intercellSpacing.height) / (CGFloat)_rows);
	if (_cellSize.width < 0.0) {
		_cellSize.width = 0.0;
	}
	if (_cellSize.height < 0.0) {
		_cellSize.height = 0.0;
	}
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	if (_validateSize) {
		[self fn_autosizeCellsToFrame];
	}
	[self setNeedsDisplay:YES];
}

/* ============================================================================================ *
 * THE SELECTION'S FOUR PRIMITIVES, THEN THE PUBLIC DOORS THAT COMBINE THEM.                     *
 * ============================================================================================ */

- (BOOL)fn_isSelectedAtIndex:(NSInteger)index
{
	return (_selected != NULL && index >= 0 && index < _rows * _columns) ? _selected[index] : NO;
}

- (void)fn_setSelected:(BOOL)flag atIndex:(NSInteger)index highlight:(BOOL)lit
{
	NSCell *cell;

	if (_selected == NULL || index < 0 || index >= _rows * _columns) {
		return;
	}
	_selected[index] = flag ? YES : NO;
	cell = _cells[index];
	if (lit && cell != nil) {
		[cell setHighlighted:flag ? YES : NO];
	}
}

- (void)fn_clearSelectionHighlighting:(BOOL)lit
{
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		[self fn_setSelected:NO atIndex:i highlight:lit];
	}
	_anchor = -1;
}

- (void)fn_selectOnlyIndex:(NSInteger)index highlight:(BOOL)lit
{
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		[self fn_setSelected:(i == index) atIndex:i highlight:lit];
	}
	_anchor = index;
}

- (NSMatrixMode)mode
{
	return _mode;
}

- (void)setMode:(NSMatrixMode)aMode
{
	_mode = aMode;
	[self setNeedsDisplay:YES];
}

- (BOOL)allowsEmptySelection
{
	return _allowsEmptySelection;
}

- (void)setAllowsEmptySelection:(BOOL)flag
{
	_allowsEmptySelection = flag ? YES : NO;
}

- (BOOL)isSelectionByRect
{
	return _selectionByRect;
}

- (void)setSelectionByRect:(BOOL)flag
{
	_selectionByRect = flag ? YES : NO;
}

- (NSCell *)selectedCell
{
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		if ([self fn_isSelectedAtIndex:i]) {
			return _cells[i];
		}
	}
	return nil;
}

- (NSArray *)selectedCells
{
	NSMutableArray *cells = [NSMutableArray array];
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		if ([self fn_isSelectedAtIndex:i] && _cells[i] != nil) {
			[cells addObject:_cells[i]];
		}
	}
	return cells;
}

- (NSInteger)selectedRow
{
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		if ([self fn_isSelectedAtIndex:i]) {
			return i / _columns;
		}
	}
	return -1;
}

- (NSInteger)selectedColumn
{
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		if ([self fn_isSelectedAtIndex:i]) {
			return i % _columns;
		}
	}
	return -1;
}

- (void)selectCellAtRow:(NSInteger)row column:(NSInteger)column
{
	NSInteger index = [self fn_indexAtRow:row column:column];

	if (index < 0) {
		return;
	}
	/* **A RADIO GROUP'S SELECTION IS ITS STATE, so the two move together.** The selected cell is turned on and every
	 * other cell off — which is the one place the mode reaches a VALUE rather than a policy, and the reason a radio
	 * matrix's `-selectedCell` and its `-objectValue` cannot disagree. */
	if (_mode == NSRadioModeMatrix) {
		NSInteger i, count = _rows * _columns;

		for (i = 0; i < count; i++) {
			[_cells[i] setState:(i == index) ? NSOnState : NSOffState];
		}
	}
	[self fn_selectOnlyIndex:index highlight:YES];
	_keyRow = row;
	_keyColumn = column;
	[self setNeedsDisplay:YES];
}

- (BOOL)selectCellWithTag:(NSInteger)tag
{
	NSCell *cell = [self cellWithTag:tag];
	NSInteger row = -1, column = -1;

	if (cell == nil || ![self getRow:&row column:&column ofCell:cell]) {
		return NO;
	}
	[self selectCellAtRow:row column:column];
	return YES;
}

- (void)selectAll:(id)sender
{
	NSInteger i, count = _rows * _columns;

	(void)sender;
	/* **A RADIO GROUP CANNOT SELECT ALL**, because two cells on is not a state a radio group has. Apple's own
	 * documentation does not say so; the mode's meaning does, and a door that quietly did nothing would be worse than
	 * one that says this in its comment. */
	if (_mode == NSRadioModeMatrix) {
		return;
	}
	for (i = 0; i < count; i++) {
		[self fn_setSelected:YES atIndex:i highlight:YES];
	}
	_anchor = 0;
	[self setNeedsDisplay:YES];
}

- (void)deselectAllCells
{
	/* **AN EMPTY SELECTION IS A STATE A MATRIX MAY FORBID**, and then this door does nothing rather than leaving the
	 * matrix in a shape its policy says it cannot be in. */
	if (!_allowsEmptySelection) {
		return;
	}
	[self fn_clearSelectionHighlighting:YES];
	[self setNeedsDisplay:YES];
}

- (void)deselectSelectedCell
{
	NSInteger i, count = _rows * _columns;

	if (!_allowsEmptySelection) {
		return;
	}
	for (i = 0; i < count; i++) {
		if ([self fn_isSelectedAtIndex:i]) {
			[self fn_setSelected:NO atIndex:i highlight:YES];
		}
	}
	_anchor = -1;
	[self setNeedsDisplay:YES];
}

- (void)setSelectionFrom:(NSInteger)startPos to:(NSInteger)endPos anchor:(NSInteger)anchorPos highlight:(BOOL)lit
{
	NSInteger i, count = _rows * _columns;
	NSInteger from = MIN(startPos, endPos);
	NSInteger to = MAX(startPos, endPos);

	if (count <= 0) {
		return;
	}
	if (from < 0) {
		from = 0;
	}
	if (to >= count) {
		to = count - 1;
	}
	for (i = 0; i < count; i++) {
		[self fn_setSelected:(i >= from && i <= to) atIndex:i highlight:lit];
	}
	_anchor = (anchorPos >= 0 && anchorPos < count) ? anchorPos : from;
	[self setNeedsDisplay:YES];
}

- (NSCell *)keyCell
{
	return [self cellAtRow:_keyRow column:_keyColumn];
}

- (void)setKeyCell:(NSCell *)aCell
{
	NSInteger row = -1, column = -1;

	if (aCell == nil || ![self getRow:&row column:&column ofCell:aCell]) {
		return;
	}
	_keyRow = row;
	_keyColumn = column;
}

/* ============================================================================================ *
 * THE FACE.                                                                                     *
 * ============================================================================================ */

- (BOOL)drawsBackground
{
	return _drawsBackground;
}

- (void)setDrawsBackground:(BOOL)flag
{
	_drawsBackground = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor
{
	return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)color
{
	NSColor *old = _backgroundColor;

	_backgroundColor = [color retain];
	[old release];
	[self setNeedsDisplay:YES];
}

- (BOOL)drawsCellBackground
{
	return _drawsCellBackground;
}

- (void)setDrawsCellBackground:(BOOL)flag
{
	_drawsCellBackground = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (NSColor *)cellBackgroundColor
{
	return _cellBackgroundColor;
}

- (void)setCellBackgroundColor:(NSColor *)color
{
	NSColor *old = _cellBackgroundColor;

	_cellBackgroundColor = [color retain];
	[old release];
	[self setNeedsDisplay:YES];
}

- (void)drawCellAtRow:(NSInteger)row column:(NSInteger)column
{
	NSInteger index = [self fn_indexAtRow:row column:column];
	NSCell *cell;
	NSRect frame;

	if (index < 0) {
		return;
	}
	cell = _cells[index];
	if (cell == nil) {
		return;
	}
	frame = [self fn_cellFrameAtIndex:index];
	/* **A CELL BACKGROUND IS THE MATRIX'S INK, DRAWN BEFORE THE CELL SO THE CELL'S OWN FACE LANDS ON IT.** A cell
	 * that draws a bezel covers this completely, which is the division the two doors have. */
	if (_drawsCellBackground) {
		[(_cellBackgroundColor != nil ? _cellBackgroundColor : [NSColor controlBackgroundColor]) setFill];
		[[NSBezierPath bezierPathWithRect:frame] fill];
	}
	/* **AND A PLAIN CELL'S SELECTION IS THE MATRIX'S TO DRAW**, because `NSCell -drawWithFrame:` only paints a highlight
	 * when the cell has a bezel or a border of its own — a face-less cell has nothing to paint with. A bordered cell is
	 * left alone: it draws its own accent, and a fill underneath it would be a second selection in the same square. */
	if ([cell isHighlighted] && ![cell isBordered] && ![cell isBezeled]) {
		[[NSColor cg_accentColor] setFill];
		[[NSBezierPath bezierPathWithRect:frame] fill];
	}
	[cell drawWithFrame:frame inView:self];
	/* **AND THE FACE IS LEFT AS THE SELECTION SAYS IT IS.** A cell's `-isHighlighted` is the DRAWN bit; drawing is
	 * where the stored selection is turned back into it, so a cell a caller highlighted directly — a pointer tracking
	 * over it — keeps its own bit and the two do not fight. See the header's second paragraph. */
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSInteger r, c;

	if (_drawsBackground) {
		[(_backgroundColor != nil ? _backgroundColor : [NSColor controlColor]) setFill];
		[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
	}
	for (r = 0; r < _rows; r++) {
		for (c = 0; c < _columns; c++) {
			NSRect frame = [self cellFrameAtRow:r column:c];

			if (NSIsEmptyRect(frame) || !NSIntersectsRect(frame, dirtyRect)) {
				continue;
			}
			[self drawCellAtRow:r column:c];
		}
	}
}

- (void)resetCursorRects
{
	NSInteger i, count = _rows * _columns;

	for (i = 0; i < count; i++) {
		[_cells[i] resetCursorRect:[self fn_cellFrameAtIndex:i] inView:self];
	}
}

/* ============================================================================================ *
 * THE ACTION AND THE CLICK.                                                                     *
 * ============================================================================================ */

- (id <NSMatrixDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(id <NSMatrixDelegate>)anObject
{
	_delegate = anObject;	/* NOT RETAINED, this tree's rule for every delegate */
}

- (SEL)doubleAction
{
	return _doubleAction;
}

- (void)setDoubleAction:(SEL)aSelector
{
	_doubleAction = aSelector;
}

/* **THE FOUR `NSControl` DOORS, OVERRIDDEN BECAUSE A MATRIX HAS NO SINGLE CELL.** `NSControl`'s versions forward to
 * `_cell`, which this class never makes; forwarding would answer nil and NULL for a matrix whose own target is set.
 * The cell keeps its own pair untouched — this is the MATRIX's, and `-sendAction` is the door that chooses between the
 * two: the tracked or selected cell's where it has one, the matrix's otherwise. */
- (id)target
{
	return _target;
}

- (void)setTarget:(id)anObject
{
	_target = anObject;
}

- (SEL)action
{
	return _action;
}

- (void)setAction:(SEL)aSelector
{
	_action = aSelector;
}

- (NSCell *)fn_actionCell
{
	if (_trackingIndex >= 0 && _trackingIndex < _rows * _columns) {
		return _cells[_trackingIndex];
	}
	return [self selectedCell];
}

- (void)sendAction
{
	NSCell *cell = [self fn_actionCell];
	SEL action;
	id target;

	if (cell == nil) {
		return;
	}
	action = [cell action];
	target = [cell target];
	/* **A CELL WITH NO TARGET OF ITS OWN FALLS BACK TO THE MATRIX'S**, which is what makes a grid of buttons one
	 * target's business: the caller sets the target once on the matrix and every cell's action reaches it. */
	if (target == nil) {
		target = _target;
	}
	if (target == nil && action == NULL) {
		action = _action;
	}
	[self sendAction:action to:target];
}

- (void)sendDoubleAction
{
	if (_doubleAction == NULL) {
		return;
	}
	[[NSApplication sharedApplication] sendAction:_doubleAction to:_target from:self];
}

/* **AND THE KEYBOARD'S CLICK, WHICH `NSControl`'s VERSION CANNOT BE.** That door sends the ONE cell's action; a matrix's
 * is the KEY cell's — the cell the keyboard is on — and a press that arrives here without an event is the keyboard's. */
- (void)performClick:(id)sender
{
	NSInteger index = [self fn_indexAtRow:_keyRow column:_keyColumn];

	(void)sender;
	if (index >= 0) {
		[self fn_applyClickAtRow:_keyRow column:_keyColumn event:nil];
	}
}

- (void)sendAction:(SEL)aSelector to:(id)target forAllCells:(BOOL)flag
{
	NSInteger i, count = _rows * _columns;

	if (aSelector == NULL) {
		return;
	}
	if (!flag) {
		[self sendAction];
		return;
	}
	/* **THE CELL IS THE SENDER**, because that is the only thing a target's handler can tell apart when a whole grid
	 * shares one action — which is the whole reason this door exists rather than `-sendAction` in a loop. */
	for (i = 0; i < count; i++) {
		if (_cells[i] != nil) {
			[[NSApplication sharedApplication] sendAction:aSelector to:target from:_cells[i]];
		}
	}
}

- (NSInteger)mouseDownFlags
{
	return _mouseDownFlags;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	(void)theEvent;
	/* **A MATRIX IS ALWAYS A CLICK TARGET, ACTIVE WINDOW OR NOT.** A grid of buttons is precisely the kind of control a
	 * person clicks in a window they are about to activate; making the first click only activate would cost them the
	 * click they meant. */
	return YES;
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)setAutoscroll:(BOOL)flag
{
	_autoscroll = flag ? YES : NO;
}

- (BOOL)isAutoscroll
{
	return _autoscroll;
}

- (void)scrollCellToVisibleAtRow:(NSInteger)row column:(NSInteger)column
{
	/* **THE SCROLL VIEW IS THE ONLY THING THAT CAN SCROLL**, and a matrix outside one has nothing to ask: the door
	 * finds the clip view the matrix is a document of and moves its origin, then tells the scroll view to re-read it —
	 * the same two-call loop `NSClipView.h` documents. A cell at or above the visible top-left is scrolled to the top
	 * of the clip rather than left where it is, which is what "make it visible" means for a target a drag overshot. */
	NSScrollView *scrollView = [self enclosingScrollView];
	NSClipView *clipView;
	NSRect frame, visible;
	NSPoint origin;

	if (scrollView == nil) {
		return;
	}
	clipView = [scrollView contentView];
	if (clipView == nil) {
		return;
	}
	frame = [self cellFrameAtRow:row column:column];
	if (NSIsEmptyRect(frame)) {
		return;
	}
	visible = [clipView documentVisibleRect];
	origin = [clipView bounds].origin;
	if (NSMinY(frame) < NSMinY(visible)) {
		origin.y = NSMinY(frame);
	} else if (NSMaxY(frame) > NSMaxY(visible)) {
		origin.y = NSMaxY(frame) - NSHeight(visible);
	}
	if (NSMinX(frame) < NSMinX(visible)) {
		origin.x = NSMinX(frame);
	} else if (NSMaxX(frame) > NSMaxX(visible)) {
		origin.x = NSMaxX(frame) - NSWidth(visible);
	}
	[clipView scrollToPoint:origin];
	[scrollView reflectScrolledClipView:clipView];
}

- (BOOL)tabKeyTraversesCells
{
	return _tabKeyTraversesCells;
}

- (void)setTabKeyTraversesCells:(BOOL)flag
{
	_tabKeyTraversesCells = flag ? YES : NO;
}

/* **WHAT A CLICK MEANS, IN ONE PLACE, FOR EVERY MODE.** The four policies differ only here: a radio click selects
 * and turns its cell on; a list click replaces the selection unless a modifier asks for an extension; a track click
 * toggles the cell's state and leaves nothing selected; a highlight click leaves nothing behind at all. Every one of
 * them can send an action, which is the part they share. */
- (void)fn_applyClickAtRow:(NSInteger)row column:(NSInteger)column event:(NSEvent *)event
{
	NSInteger index = [self fn_indexAtRow:row column:column];
	NSUInteger flags = (event != nil) ? [event modifierFlags] : 0;
	BOOL extend = ((flags & NSShiftKeyMask) != 0 || (flags & NSCommandKeyMask) != 0);

	if (index < 0) {
		return;
	}
	switch (_mode) {
	case NSRadioModeMatrix:
		[self selectCellAtRow:row column:column];
		break;
	case NSListModeMatrix:
		if (extend && _anchor >= 0 && !_selectionByRect) {
			[self setSelectionFrom:_anchor to:index anchor:_anchor highlight:YES];
		} else {
			[self fn_selectOnlyIndex:index highlight:YES];
		}
		_keyRow = row;
		_keyColumn = column;
		break;
	case NSTrackModeMatrix:
		/* **A TRACK-MODE CLICK IS THE CELL'S OWN COMMAND, WHICH IS `-setNextState:`.** The matrix does not touch the
		 * selection because the mode says there is none; what changes is the value, and the cell is what owns it. */
		[_cells[index] setNextState];
		break;
	case NSHighlightModeMatrix:
		/* nothing persists: the highlight was the press */
		break;
	}
	[self setNeedsDisplay:YES];
	/* THE FIRST CLICK OF A DOUBLE CLICK SENDS THE CELL'S ACTION; the second sends the double action instead, which is
	 * why this branch asks the event's click count rather than keeping a timer. */
	if (event != nil && [event clickCount] >= 2 && _doubleAction != NULL) {
		[self sendDoubleAction];
	} else {
		[self sendAction];
	}
}

/* **THE DRAG, WHICH IS THE SELECTION-BY-RECT AND THE LIST EXTENSION IN ONE PLACE.** The pointer's cell is highlighted
 * while it is down, so a person sees which cell a release would choose; a rectangle drag moves the whole range; a
 * modifier-held drag extends from the anchor. Nothing is committed until the button comes up, which is why the
 * highlight is the only thing this method writes besides the selection a rectangle drag asks for. */
- (void)fn_trackPoint:(NSPoint)point
{
	NSInteger row = -1, column = -1;
	BOOL over = [self getRow:&row column:&column forPoint:point];
	NSInteger index = over ? [self fn_indexAtRow:row column:column] : -1;

	/* THE PREVIOUS CELL'S TRANSIENT HIGHLIGHT GOES FIRST, and only if the selection does not own it: a cell that is
	 * selected keeps its highlight when the pointer leaves it. */
	if (_trackingIndex >= 0 && _trackingIndex < _rows * _columns
	    && !_selected[_trackingIndex] && !(_mode == NSHighlightModeMatrix)) {
		[_cells[_trackingIndex] setHighlighted:NO];
	}
	_trackingIndex = index;
	if (index >= 0) {
		[_cells[index] setHighlighted:YES];
	}
	if (_selectionByRect && _anchor >= 0 && index >= 0) {
		[self setSelectionFrom:_anchor to:index anchor:_anchor highlight:YES];
	} else if (_mode == NSListModeMatrix && index >= 0
		   && (_mouseDownFlags & (NSShiftKeyMask | NSCommandKeyMask)) != 0 && _anchor >= 0) {
		[self setSelectionFrom:_anchor to:index anchor:_anchor highlight:YES];
	}
	/* **A DRAG THAT LEAVES THE MATRIX SCROLLS ITS CELL INTO VIEW**, and only when a caller asked for it: autoscroll is
	 * a policy, and a matrix that scrolled an enclosing clip view uninvited would move a document under a drag. */
	if (_autoscroll && !over && _trackingIndex >= 0) {
		[self scrollCellToVisibleAtRow:_trackingIndex / _columns column:_trackingIndex % _columns];
	}
	[self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
	NSApplication *app = [NSApplication sharedApplication];
	NSWindow *window = [self window];
	NSPoint where;
	NSInteger row = -1, column = -1;
	NSInteger index;
	NSCell *cell;
	BOOL inside = NO;
	BOOL up = NO;
	NSEvent *next;

	if (_rows <= 0 || _columns <= 0) {
		return;
	}
	_mouseDownFlags = (NSInteger)[event modifierFlags];
	where = [self convertPoint:[event locationInWindow] fromView:nil];
	if (![self getRow:&row column:&column forPoint:where]) {
		/* A PRESS IN THE SPACING IS A PRESS ON THE MATRIX AND NO FACE. It is not a selection and not a cancel: the
		 * header's `-getRow:column:forPoint:` says a gap is not a cell, and a click on one goes nowhere. */
		return;
	}
	index = [self fn_indexAtRow:row column:column];
	cell = _cells[index];
	if (cell == nil || ![cell isEnabled]) {
		return;
	}
	/* THE ANCHOR IS WHERE THIS PRESS STARTED, unless a modifier says this press EXTENDS an earlier one. */
	if (!((_mouseDownFlags & (NSShiftKeyMask | NSCommandKeyMask)) != 0) || _anchor < 0) {
		_anchor = index;
	}
	_trackingIndex = index;
	_keyRow = row;
	_keyColumn = column;
	[cell highlight:YES withFrame:[self cellFrameAtRow:row column:column] inView:self];
	(void)[cell startTrackingAt:where inView:self];
	[self setNeedsDisplay:YES];
	if (window != nil) {
		[window displayIfNeeded];
	}
	/* **A PROGRAM WITH NO RUN LOOP HAS NO EVENT SOURCE**, so the press is the whole of what can be applied: the click
	 * is committed — the selection and the state change, which is what the press MEANS — and the action is not sent,
	 * because a send is what a completed click does and there is no completion to observe. The same guard, for the same
	 * measured reason, `NSControl -mouseDown:` and `NSMenuView`'s tracking loop carry. */
	if (![app isRunning]) {
		[self fn_applyClickAtRow:row column:column event:event];
		[cell stopTracking:where at:where inView:self mouseIsUp:NO];
		[cell highlight:[self fn_isSelectedAtIndex:index] withFrame:[self cellFrameAtRow:row column:column] inView:self];
		_trackingIndex = -1;
		[self setNeedsDisplay:YES];
		return;
	}
	for (;;) {
		NSRect bounds = [self bounds];

		next = [app nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)
					untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
					   inMode:nil
					  dequeue:YES];
		if (next == nil) {
			if (window != nil) {
				[window displayIfNeeded];
			}
			continue;
		}
		if (![app isRunning]) {
			break;
		}
		/* EVERY OTHER MOTION ALREADY QUEUED IS APPLIED WITHOUT DRAWING — the value per motion, one frame per pass;
		 * `NSControl -mouseDown:` measures the reason (forty-three frames for forty motions otherwise). */
		for (;;) {
			where = [self convertPoint:[next locationInWindow] fromView:nil];
			[self fn_trackPoint:where];
			inside = NSPointInRect(where, bounds);
			if ([next type] == NSLeftMouseUp) {
				up = YES;
				break;
			}
			next = [app nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)
						untilDate:[NSDate distantPast]
						   inMode:nil
						  dequeue:YES];
			if (next == nil) {
				break;
			}
		}
		if (window != nil) {
			[window displayIfNeeded];
		}
		if (up) {
			break;
		}
	}
	{
		NSInteger releaseRow = -1, releaseColumn = -1;
		BOOL onCell = [self getRow:&releaseRow column:&releaseColumn forPoint:where];

		inside = inside && onCell;
		if (inside) {
			[cell stopTracking:where at:where inView:self mouseIsUp:YES];
			[self fn_applyClickAtRow:releaseRow column:releaseColumn event:event];
		} else {
			/* THE BUTTON CAME UP OFF A FACE, which is the cancel a drag off a button performs: the cell is told, the
			 * selection is put back the way it was, and no action is sent. */
			[cell stopTracking:where at:where inView:self mouseIsUp:NO];
			[self setNeedsDisplay:YES];
		}
	}
	_trackingIndex = -1;
	/* AND THE TRANSIENT HIGHLIGHT IS CLEARED, unless the selection now owns the cell. */
	{
		NSInteger i, count = _rows * _columns;

		for (i = 0; i < count; i++) {
			[_cells[i] setHighlighted:([self fn_isSelectedAtIndex:i] || (_mode == NSRadioModeMatrix && [_cells[i] state] == NSOnState))];
		}
	}
	[self setNeedsDisplay:YES];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
	NSString *chars = [event charactersIgnoringModifiers];
	NSInteger i, count = _rows * _columns;

	if ([chars length] == 0) {
		return NO;
	}
	/* **COMMAND IS THE MENU'S**, so a matrix does not compete for it: the era's matrices use plain characters as key
	 * equivalents (a dialog's "OK" button's `\r`, a radio's letter), and a Command-key press belongs to a menu item. */
	if (([event modifierFlags] & NSCommandKeyMask) != 0) {
		return NO;
	}
	for (i = 0; i < count; i++) {
		NSString *equivalent = [_cells[i] keyEquivalent];

		if (equivalent == nil || [equivalent length] == 0) {
			continue;
		}
		if ([equivalent caseInsensitiveCompare:chars] == NSOrderedSame) {
			NSInteger row = i / _columns;
			NSInteger column = i % _columns;

			/* THE EQUIVALENT IS A CLICK WITHOUT A POINTER: the selection and the action, in the mode's own terms. */
			[self fn_applyClickAtRow:row column:column event:event];
			return YES;
		}
	}
	return NO;
}

- (void)keyDown:(NSEvent *)event
{
	NSString *chars = [event charactersIgnoringModifiers];
	NSInteger index = [self fn_indexAtRow:_keyRow column:_keyColumn];
	unichar c = ([chars length] > 0) ? [chars characterAtIndex:0] : 0;

	/* **THE FOUR ARROWS MOVE THE KEY CELL**, which is Apple's behaviour and the reason the key cell is not the
	 * selection: moving the keyboard's cell does not choose anything. A move past an edge stays where it is. */
	if (c == NSUpArrowFunctionKey || c == NSDownArrowFunctionKey
	    || c == NSLeftArrowFunctionKey || c == NSRightArrowFunctionKey) {
		switch (c) {
		case NSUpArrowFunctionKey:
			if (_keyRow > 0) {
				_keyRow--;
			}
			break;
		case NSDownArrowFunctionKey:
			if (_keyRow + 1 < _rows) {
				_keyRow++;
			}
			break;
		case NSLeftArrowFunctionKey:
			if (_keyColumn > 0) {
				_keyColumn--;
			}
			break;
		default:
			if (_keyColumn + 1 < _columns) {
				_keyColumn++;
			}
			break;
		}
		[self setNeedsDisplay:YES];
		return;
	}
	/* **TAB MOVES ALONG THE GRID WHEN THE MATRIX SAYS IT TRAVERSES**, and otherwise leaves the matrix to the responder
	 * chain, which is what a form's last entry's Tab means. */
	if (c == NSTabCharacter || c == NSBackTabCharacter) {
		if (!_tabKeyTraversesCells) {
			[super keyDown:event];
			return;
		}
		if (c == NSTabCharacter) {
			if (_keyColumn + 1 < _columns) {
				_keyColumn++;
			} else if (_keyRow + 1 < _rows) {
				_keyRow++;
				_keyColumn = 0;
			}
		} else {
			if (_keyColumn > 0) {
				_keyColumn--;
			} else if (_keyRow > 0) {
				_keyRow--;
				_keyColumn = _columns - 1;
			}
		}
		[self setNeedsDisplay:YES];
		return;
	}
	/* AND SPACE OR RETURN ACTIVATES THE KEY CELL, which is the keyboard's click. */
	if (c == ' ' || c == '\r' || c == 3) {
		if (index >= 0) {
			[self fn_applyClickAtRow:_keyRow column:_keyColumn event:event];
		}
		return;
	}
	[super keyDown:event];
}

/* ============================================================================================ *
 * STATE, HIGHLIGHT, TOOL TIPS AND SORTING.                                                      *
 * ============================================================================================ */

- (void)setState:(NSInteger)value atRow:(NSInteger)row column:(NSInteger)column
{
	NSInteger index = [self fn_indexAtRow:row column:column];

	if (index < 0) {
		return;
	}
	/* **A RADIO GROUP HAS ONE ON CELL**, so writing one on turns the rest off — the same clause `-selectCellAtRow:column:`
	 * performs from the other direction, and the one place a STATE write is a group's business rather than a cell's. */
	if (_mode == NSRadioModeMatrix && value != NSOffState) {
		NSInteger i, count = _rows * _columns;

		for (i = 0; i < count; i++) {
			[_cells[i] setState:(i == index) ? value : NSOffState];
		}
	} else {
		[_cells[index] setState:value];
	}
	[self setNeedsDisplay:YES];
}

- (void)highlightCell:(BOOL)flag atRow:(NSInteger)row column:(NSInteger)column
{
	NSInteger index = [self fn_indexAtRow:row column:column];

	if (index < 0) {
		return;
	}
	[_cells[index] setHighlighted:flag ? YES : NO];
	[self setNeedsDisplay:YES];
}

- (void)setToolTip:(NSString *)string forCell:(NSCell *)cell
{
	NSValue *key;

	if (cell == nil) {
		return;
	}
	if (_cellToolTips == nil) {
		_cellToolTips = [[NSMutableDictionary alloc] init];
	}
	key = [NSValue valueWithPointer:cell];
	if (string != nil) {
		[_cellToolTips setObject:string forKey:key];
	} else {
		[_cellToolTips removeObjectForKey:key];
	}
	/* **AND THE REGISTRATION IS MADE**, because the door's name says a WINDOW should surface it — but this tree's
	 * `-addToolTipRect:owner:userData:` records a placeholder and no window reads it yet, so what a caller can verify
	 * is the round trip through `-toolTipForCell:`. Named here rather than left to be discovered. */
	(void)[self addToolTipRect:[self cellFrameAtRow:0 column:0] owner:self userData:NULL];
}

- (NSString *)toolTipForCell:(NSCell *)cell
{
	if (cell == nil || _cellToolTips == nil) {
		return nil;
	}
	return (NSString *)[_cellToolTips objectForKey:[NSValue valueWithPointer:cell]];
}

- (void)sortUsingFunction:(NSInteger (*)(id, id, void *))compare context:(void *)context
{
	NSInteger c, r;

	if (compare == NULL) {
		return;
	}
	/* **EACH COLUMN SORTS INDEPENDENTLY, AND IT IS AN INSERTION SORT.** Apple's page says the function sees the two
	 * CELLS; it does not name an algorithm, and an insertion sort is the one whose equal-answer behaviour a caller can
	 * predict — two cells that compare equal keep the order they had, which is what a second sort key relies on. The
	 * cells are COPIED out of the grid per column, sorted, and copied back, so a comparison that reads the grid (a
	 * cell's row, via `-getRow:column:ofCell:`) sees the grid it was given rather than a half-sorted one. */
	for (c = 0; c < _columns; c++) {
		NSCell **column = (NSCell **)malloc(sizeof(NSCell *) * (size_t)(_rows > 0 ? _rows : 1));
		BOOL *chosen = (BOOL *)malloc(sizeof(BOOL) * (size_t)(_rows > 0 ? _rows : 1));

		for (r = 0; r < _rows; r++) {
			column[r] = _cells[r * _columns + c];
			chosen[r] = _selected[r * _columns + c];
		}
		/* **THE SHUFFLE IS OVER BORROWED POINTERS, NOT OWNED ONES.** The grid's array keeps its own reference to every
		 * cell throughout, so the temporary array only reorders ADDRESSES: retaining inside the walk and releasing the
		 * slot afterwards unbalances the grid's ownership and frees cells that are still in it — MEASURED, as a crash
		 * in the first check after this door. */
		for (r = 1; r < _rows; r++) {
			NSCell *cell = column[r];
			BOOL wasChosen = chosen[r];
			NSInteger j = r;

			while (j > 0 && compare(column[j - 1], cell, context) > 0) {
				column[j] = column[j - 1];
				chosen[j] = chosen[j - 1];
				j--;
			}
			column[j] = cell;
			chosen[j] = wasChosen;
		}
		for (r = 0; r < _rows; r++) {
			_cells[r * _columns + c] = column[r];
			_selected[r * _columns + c] = chosen[r];
		}
		free(column);
		free(chosen);
	}
	[self setNeedsDisplay:YES];
}

- (void)sortUsingSelector:(SEL)comparator
{
	NSInteger c, r;

	if (comparator == NULL) {
		return;
	}
	/* THE SAME WALK, WITH THE COMPARISON SENT RATHER THAN CALLED — one implementation of the ordering, two doors. */
	for (c = 0; c < _columns; c++) {
		NSCell **column = (NSCell **)malloc(sizeof(NSCell *) * (size_t)(_rows > 0 ? _rows : 1));
		BOOL *chosen = (BOOL *)malloc(sizeof(BOOL) * (size_t)(_rows > 0 ? _rows : 1));

		for (r = 0; r < _rows; r++) {
			column[r] = _cells[r * _columns + c];
			chosen[r] = _selected[r * _columns + c];
		}
		for (r = 1; r < _rows; r++) {
			NSCell *cell = column[r];
			BOOL wasChosen = chosen[r];
			NSInteger j = r;

			while (j > 0) {
				NSInteger (*compare)(id, SEL, id) = (NSInteger (*)(id, SEL, id))
					[column[j - 1] methodForSelector:comparator];
				NSInteger answer = compare(column[j - 1], comparator, cell);

				if (answer <= 0) {
					break;
				}
				column[j] = column[j - 1];
				chosen[j] = chosen[j - 1];
				j--;
			}
			column[j] = cell;
			chosen[j] = wasChosen;
		}
		for (r = 0; r < _rows; r++) {
			_cells[r * _columns + c] = column[r];
			_selected[r * _columns + c] = chosen[r];
		}
		free(column);
		free(chosen);
	}
	[self setNeedsDisplay:YES];
}

/* ============================================================================================ *
 * THE FIELD SESSION.                                                                            *
 * ============================================================================================ */

- (NSCell *)fn_editingCell
{
	if (_editingIndex < 0 || _editingIndex >= _rows * _columns) {
		return nil;
	}
	return _cells[_editingIndex];
}

- (void)fn_endSessionIfAny
{
	NSCell *cell = [self fn_editingCell];

	if (cell != nil) {
		NSText *editor = [cell cg_currentEditor];

		if (editor != nil) {
			/* THE CELL IS THE EDITOR'S DELEGATE, so ending it with the editor is what takes the string back; the
			 * matrix then forgets which cell it was. */
			[cell endEditing:editor];
		}
	}
	_editingIndex = -1;
}

- (void)selectText:(id)sender
{
	NSInteger index = _editingIndex;
	NSCell *cell;

	(void)sender;
	if (index < 0) {
		/* NO SESSION IS LIVE: the selected cell is the one a caller asking for "the text" means, and the key cell is
		 * the fallback when nothing is selected. */
		cell = [self selectedCell];
		if (cell == nil) {
			index = [self fn_indexAtRow:_keyRow column:_keyColumn];
		} else {
			index = [self fn_indexOfCell:cell];
		}
	}
	if (index >= 0) {
		[self selectTextAtRow:index / _columns column:index % _columns];
	}
}

- (void)selectTextAtRow:(NSInteger)row column:(NSInteger)column
{
	NSInteger index = [self fn_indexAtRow:row column:column];
	NSCell *cell;
	NSWindow *window = [self window];
	NSText *editor;
	NSRect frame;

	if (index < 0) {
		return;
	}
	cell = _cells[index];
	if (cell == nil || ![cell isEditable]) {
		/* A CELL THAT CANNOT BE EDITED IS NOT AN ERROR: `-selectTextAtRow:column:` still SELECTS it, which is what a
		 * caller asking for the cell's attention meant. */
		[self selectCellAtRow:row column:column];
		return;
	}
	[self selectCellAtRow:row column:column];
	editor = (window != nil) ? [window fieldEditor:YES forObject:self] : nil;
	if (editor == nil) {
		/* **NO WINDOW, NO FIELD EDITOR — SO ONE IS MADE THE WAY THE WINDOW MAKES ITS OWN.** `NSCell -selectWithFrame:…`
		 * places an editor in a view with no window and does not ask for first responder (it records that measurement
		 * itself), so a caller with an offscreen matrix can still run a real session it can `-abortEditing`. The recipe is
		 * `NSWindow -fieldEditor:forObject:`'s, not a bare `-init`: MEASURED, a bare `NSText` has no layout state and
		 * `-setString:` faults inside the line it tries to build. */
		editor = [[[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 0.0, 0.0)] autorelease];
		[editor setFieldEditor:YES];
		[editor setEditable:YES];
		[editor setSelectable:YES];
	}
	frame = [self cellFrameAtRow:row column:column];
	_editingIndex = index;
	[cell selectWithFrame:frame inView:self editor:editor delegate:self
			start:0 length:(NSInteger)[[cell stringValue] length]];
	[self setNeedsDisplay:YES];
}

/* **THE MATRIX'S OWN EDITING DOORS, ASKED BY THE CELL AND ANSWERED BY THE DELEGATE.** The cell in a matrix is the
 * editor's delegate (see `NSCell -selectWithFrame:…`), so the `Should` pair is asked of the cell; the cell answers YES
 * unless it has a control that overrides it — and a form cell DOES, forwarding here, which is what makes a form's
 * delegate able to refuse a field. `NSFormCell -textShouldBeginEditing:` is the other half of this contract. */
- (BOOL)textShouldBeginEditing:(NSText *)textObject
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(control:textShouldBeginEditing:)]) {
		return [_delegate control:self textShouldBeginEditing:textObject];
	}
	return YES;
}

- (BOOL)textShouldEndEditing:(NSText *)textObject
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(control:textShouldEndEditing:)]) {
		return [_delegate control:self textShouldEndEditing:textObject];
	}
	return YES;
}

/* **EVERY ANNOUNCEMENT GOES OUT TWICE, EXACTLY AS `NSTextField`'S DO**: a notification with the MATRIX as its object
 * (the editor in the userInfo), and a delegate method for a conformer. A delegate that implements both is told twice,
 * which is Apple's design and the caller's own business. */
- (void)textDidBeginEditing:(NSNotification *)notification
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:[notification object] forKey:NSFieldEditorUserInfoKey];
	NSNotification *note = [NSNotification notificationWithName:NSControlTextDidBeginEditingNotification
							     object:self userInfo:info];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(controlTextDidBeginEditing:)]) {
		[_delegate controlTextDidBeginEditing:note];
	}
}

- (void)textDidChange:(NSNotification *)notification
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:[notification object] forKey:NSFieldEditorUserInfoKey];
	NSNotification *note = [NSNotification notificationWithName:NSControlTextDidChangeNotification
							     object:self userInfo:info];

	[self setNeedsDisplay:YES];
	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(controlTextDidChange:)]) {
		[_delegate controlTextDidChange:note];
	}
}

- (void)textDidEndEditing:(NSNotification *)notification
{
	id editor = [notification object];
	id raw = [[notification userInfo] objectForKey:NSTextMovementUserInfoKey];
	NSTextMovement movement = (raw != nil) ? (NSTextMovement)[raw integerValue] : NSTextMovementOther;
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
		editor, NSFieldEditorUserInfoKey,
		[NSNumber numberWithInteger:(NSInteger)movement], NSTextMovementUserInfoKey, nil];
	NSNotification *note = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification
							     object:self userInfo:info];
	NSInteger row = (_editingIndex >= 0) ? _editingIndex / _columns : _keyRow;
	NSInteger column = (_editingIndex >= 0) ? _editingIndex % _columns : _keyColumn;

	_editingIndex = -1;
	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(controlTextDidEndEditing:)]) {
		[_delegate controlTextDidEndEditing:note];
	}
	/* **TAB MOVES THE KEY CELL, AND RETURN SENDS THE ACTION** — the two movements a form's session ends on, and the
	 * same rule `NSTextField` states: a CANCEL commits nothing and therefore sends nothing. */
	if (movement == NSTextMovementTab && _tabKeyTraversesCells) {
		if (column + 1 < _columns) {
			column++;
		} else if (row + 1 < _rows) {
			row++;
			column = 0;
		}
		_keyRow = row;
		_keyColumn = column;
	} else if (movement == NSTextMovementBacktab && _tabKeyTraversesCells) {
		if (column > 0) {
			column--;
		} else if (row > 0) {
			row--;
			column = _columns - 1;
		}
		_keyRow = row;
		_keyColumn = column;
	} else if (movement == NSTextMovementReturn) {
		[self sendAction];
	}
	[self setNeedsDisplay:YES];
}

/* ---- AND THE TWO `NSControl` SESSION DOORS, OVERRIDDEN FOR THE CELL IN THE SESSION ------------------- */

- (NSText *)currentEditor
{
	return [[self fn_editingCell] cg_currentEditor];
}

- (BOOL)abortEditing
{
	NSCell *cell = [self fn_editingCell];
	BOOL aborted;

	if (cell == nil) {
		return NO;
	}
	aborted = [cell cg_abortEditing];
	_editingIndex = -1;
	[self setNeedsDisplay:YES];
	return aborted;
}

/* ============================================================================================ *
 * ARCHIVING: THE SHAPE, THE POLICY, AND THE CELLS.                                              *
 * ============================================================================================ */

static NSString * const AGCoderMatrixRowsKey = @"NSMatrixRows";
static NSString * const AGCoderMatrixColumnsKey = @"NSMatrixColumns";
static NSString * const AGCoderMatrixCellsKey = @"NSMatrixCells";
static NSString * const AGCoderMatrixSelectedKey = @"NSMatrixSelected";
static NSString * const AGCoderMatrixModeKey = @"NSMatrixMode";
static NSString * const AGCoderMatrixAllowsEmptyKey = @"NSMatrixAllowsEmptySelection";
static NSString * const AGCoderMatrixSelectionByRectKey = @"NSMatrixSelectionByRect";
static NSString * const AGCoderMatrixAutosizesKey = @"NSMatrixAutosizesCells";
static NSString * const AGCoderMatrixAutoscrollKey = @"NSMatrixAutoscroll";
static NSString * const AGCoderMatrixTabKey = @"NSMatrixTabKeyTraversesCells";
static NSString * const AGCoderMatrixCellSizeKey = @"NSMatrixCellSize";
static NSString * const AGCoderMatrixSpacingKey = @"NSMatrixIntercellSpacing";
static NSString * const AGCoderMatrixDrawsBackgroundKey = @"NSMatrixDrawsBackground";
static NSString * const AGCoderMatrixDrawsCellBackgroundKey = @"NSMatrixDrawsCellBackground";
static NSString * const AGCoderMatrixBackgroundKey = @"NSMatrixBackgroundColor";
static NSString * const AGCoderMatrixCellBackgroundKey = @"NSMatrixCellBackgroundColor";
static NSString * const AGCoderMatrixDoubleActionKey = @"NSMatrixDoubleAction";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	NSMutableArray *rows = [NSMutableArray array];
	NSMutableArray *chosen = [NSMutableArray array];
	NSInteger r, c;

	[super encodeWithCoder:aCoder];
	[aCoder encodeInteger:_rows forKey:AGCoderMatrixRowsKey];
	[aCoder encodeInteger:_columns forKey:AGCoderMatrixColumnsKey];
	for (r = 0; r < _rows; r++) {
		NSMutableArray *row = [NSMutableArray array];

		for (c = 0; c < _columns; c++) {
			NSCell *cell = _cells[r * _columns + c];

			[row addObject:(cell != nil ? (id)cell : (id)[NSNull null])];
			[chosen addObject:[NSNumber numberWithBool:_selected[r * _columns + c]]];
		}
		[rows addObject:row];
	}
	[aCoder encodeObject:rows forKey:AGCoderMatrixCellsKey];
	[aCoder encodeObject:chosen forKey:AGCoderMatrixSelectedKey];
	[aCoder encodeInteger:(NSInteger)_mode forKey:AGCoderMatrixModeKey];
	[aCoder encodeBool:_allowsEmptySelection forKey:AGCoderMatrixAllowsEmptyKey];
	[aCoder encodeBool:_selectionByRect forKey:AGCoderMatrixSelectionByRectKey];
	[aCoder encodeBool:_autosizesCells forKey:AGCoderMatrixAutosizesKey];
	[aCoder encodeBool:_autoscroll forKey:AGCoderMatrixAutoscrollKey];
	[aCoder encodeBool:_tabKeyTraversesCells forKey:AGCoderMatrixTabKey];
	[aCoder encodeSize:_cellSize forKey:AGCoderMatrixCellSizeKey];
	[aCoder encodeSize:_intercellSpacing forKey:AGCoderMatrixSpacingKey];
	[aCoder encodeBool:_drawsBackground forKey:AGCoderMatrixDrawsBackgroundKey];
	[aCoder encodeBool:_drawsCellBackground forKey:AGCoderMatrixDrawsCellBackgroundKey];
	[aCoder encodeObject:_backgroundColor forKey:AGCoderMatrixBackgroundKey];
	[aCoder encodeObject:_cellBackgroundColor forKey:AGCoderMatrixCellBackgroundKey];
	if (_doubleAction != NULL) {
		[aCoder encodeObject:NSStringFromSelector(_doubleAction) forKey:AGCoderMatrixDoubleActionKey];
	}
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	_cells = NULL;
	_selected = NULL;
	_mode = NSListModeMatrix;
	_allowsEmptySelection = YES;
	_tabKeyTraversesCells = YES;
	_editingIndex = -1;
	_trackingIndex = -1;
	_anchor = -1;
	if ([aDecoder containsValueForKey:AGCoderMatrixRowsKey]) {
		_rows = [aDecoder decodeIntegerForKey:AGCoderMatrixRowsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixColumnsKey]) {
		_columns = [aDecoder decodeIntegerForKey:AGCoderMatrixColumnsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixCellsKey]) {
		NSArray *rows = [aDecoder decodeObjectForKey:AGCoderMatrixCellsKey];
		NSArray *chosen = [aDecoder decodeObjectForKey:AGCoderMatrixSelectedKey];
		NSInteger r, c;

		if (_rows > 0 && _columns > 0) {
			_cells = (NSCell **)calloc((size_t)(_rows * _columns), sizeof(NSCell *));
			_selected = (BOOL *)calloc((size_t)(_rows * _columns), sizeof(BOOL));
		}
		for (r = 0; r < _rows && r < (NSInteger)[rows count]; r++) {
			NSArray *row = [rows objectAtIndex:(NSUInteger)r];

			for (c = 0; c < _columns && c < (NSInteger)[row count]; c++) {
				id cell = [row objectAtIndex:(NSUInteger)c];

				if (cell != (id)[NSNull null]) {
					_cells[r * _columns + c] = [cell retain];
					[_cells[r * _columns + c] setControlView:self];
				}
				if (chosen != nil && (NSUInteger)(r * _columns + c) < [chosen count]) {
					_selected[r * _columns + c] = [[chosen objectAtIndex:(NSUInteger)(r * _columns + c)] boolValue];
				}
			}
		}
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixModeKey]) {
		_mode = (NSMatrixMode)[aDecoder decodeIntegerForKey:AGCoderMatrixModeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixAllowsEmptyKey]) {
		_allowsEmptySelection = [aDecoder decodeBoolForKey:AGCoderMatrixAllowsEmptyKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixSelectionByRectKey]) {
		_selectionByRect = [aDecoder decodeBoolForKey:AGCoderMatrixSelectionByRectKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixAutosizesKey]) {
		_autosizesCells = [aDecoder decodeBoolForKey:AGCoderMatrixAutosizesKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixAutoscrollKey]) {
		_autoscroll = [aDecoder decodeBoolForKey:AGCoderMatrixAutoscrollKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixTabKey]) {
		_tabKeyTraversesCells = [aDecoder decodeBoolForKey:AGCoderMatrixTabKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixCellSizeKey]) {
		_cellSize = [aDecoder decodeSizeForKey:AGCoderMatrixCellSizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixSpacingKey]) {
		_intercellSpacing = [aDecoder decodeSizeForKey:AGCoderMatrixSpacingKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixDrawsBackgroundKey]) {
		_drawsBackground = [aDecoder decodeBoolForKey:AGCoderMatrixDrawsBackgroundKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixDrawsCellBackgroundKey]) {
		_drawsCellBackground = [aDecoder decodeBoolForKey:AGCoderMatrixDrawsCellBackgroundKey];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixBackgroundKey]) {
		_backgroundColor = [[aDecoder decodeObjectForKey:AGCoderMatrixBackgroundKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixCellBackgroundKey]) {
		_cellBackgroundColor = [[aDecoder decodeObjectForKey:AGCoderMatrixCellBackgroundKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderMatrixDoubleActionKey]) {
		_doubleAction = NSSelectorFromString([aDecoder decodeObjectForKey:AGCoderMatrixDoubleActionKey]);
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

@end
