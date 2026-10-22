/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSMatrix.h — A RECTANGULAR GRID OF CELLS, AND THE LAST BIG VIEW OF THE ERA'S SURFACE.
 *
 * **THE MATRIX IS THE CONTROL THAT HAS MORE THAN ONE CELL.** `NSControl` owns exactly one, and every door it has
 * forwards to it; this class owns `rows × columns` of them, laid out on a grid, with a selection that spans cells and a
 * tracking loop that moves between them. That is the whole of Apple's design and the reason the class is worth 95
 * selectors: it is not a view with a bigger face, it is a view with a RELATIONSHIP between faces.
 *
 * **THE THREE THINGS THIS CLASS OWNS THAT A CONTROL DOES NOT:**
 *
 *   1. THE GRID. Rows, columns, a cell size and an intercell spacing place cell `(row, column)` at
 *      `(column * (w + sx), row * (h + sy))` — and the matrix is FLIPPED, so row 0 is the TOP row, which is how Apple
 *      lays a matrix out and why `-getRow:column:forPoint:` reads a pointer the way a person reads the grid.
 *   2. THE SELECTION. `-selectedCell`, `-selectedCells`, `-selectedRow`, `-selectedColumn`, `-selectCellAtRow:column:`
 *      and the range door at the foot of this file. The selection is STORED SEPARATELY from the cells' highlight bits,
 *      because `-setSelectionFrom:to:anchor:highlight:` distinguishes "selected" from "drawn as selected" and a single
 *      bit cannot hold two facts.
 *   3. THE SESSION. A cell's editor is opened by the MATRIX (`-selectTextAtRow:column:`), the field editor's delegate
 *      notifications are re-homed to the matrix, and the matrix's own `textShould…` doors are where a delegate may
 *      refuse one. That is why the five `text…` doors at the foot of this file are declared here rather than inherited
 *      from `NSControl`: a control has ONE cell to edit and a matrix has to know WHICH.
 *
 * **THE MODE IS THE POLICY FOR A CLICK, AND THE FOUR ARE THE ERA'S OWN.** `NSRadioModeMatrix` keeps exactly one cell
 * on, `NSListModeMatrix` keeps a selection a caller can extend, `NSTrackModeMatrix` clicks and lets go (a grid of push
 * buttons), and `NSHighlightModeMatrix` highlights while the pointer is down and remembers nothing. The mode changes
 * the CLICK POLICY, never the arithmetic: geometry, cells, drawing and the editing session are identical in all four.
 *
 * WHAT THIS SLICE DOES NOT DO, named at the door rather than left to be discovered: `-setAutoscroll:` scrolls a
 * tracked cell into view when a drag leaves the matrix, but only when the matrix is inside a scroll view's clip view;
 * `-setToolTip:forCell:` stores a tool tip per cell and reads it back, but the window does not yet surface tool tips
 * for any view (see `NSView -addToolTipRect:owner:userData:`); and `-sortUsingFunction:context:` sorts each COLUMN
 * with an insertion sort rather than Apple's unspecified algorithm, because the comparison is a caller's function and
 * a stable answer is the one a caller can check.
 *
 * Written from `NSMatrix.h` in the MacOSX10.6 SDK; the mode enum's four values are the header's own (see
 * PROVENANCE.md).
 */
#ifndef APPKIT_NSMATRIX_H
#define APPKIT_NSMATRIX_H

#import <AppKit/NSControl.h>
#import <AppKit/NSCell.h>

@class NSColor;
@class NSMatrix;
@class NSText;

NS_ASSUME_NONNULL_BEGIN

/* **THE FOUR POLICIES, WITH THE ERA'S VALUES.** `NSRadioModeMatrix` is 0 because Apple's header makes it the first
 * case, which is also why a zeroed matrix behaves as a radio group rather than as anything else. */
typedef enum {
	NSRadioModeMatrix = 0,
	NSListModeMatrix = 1,
	NSTrackModeMatrix = 2,
	NSHighlightModeMatrix = 3
} NSMatrixMode;

/* **AND THE DELEGATE PROTOCOL ADDS NO DOOR OF ITS OWN IN THIS ERA.** Apple declares `NSMatrixDelegate` as a refinement
 * of `NSControlTextEditingDelegate` and puts the text-editing conversation there; a matrix's delegate is thus told
 * about a field session through `-control:textShouldBeginEditing:` and its three siblings, and told about the click
 * through nothing at all (an `NSMatrix` has no `-matrix:didClickCell:` in 10.6). It is declared so that
 * `-conformsToProtocol:` answers, and so that the type of `-delegate` is the type a caller conforms to. */
@protocol NSMatrixDelegate <NSControlTextEditingDelegate>
@end

@interface NSMatrix : NSControl <NSSecureCoding>
{
	/* ---- THE GRID ------------------------------------------------------------------------------------ */
	NSInteger _rows;
	NSInteger _columns;
	/* **THE CELLS ARE A FLAT C ARRAY IN ROW-MAJOR ORDER, WHICH IS THE SHAPE `-cells` PUBLISHES** — Apple's
	 * `- (NSCell **)cells` is a `rows × columns` array a caller may index linearly, not an array of row arrays. Each
	 * entry is RETAINED by the array (this tree is manual-retain, so insertion retains and removal releases). */
	NSCell **_cells;
	/* **AND THE SELECTION IS A PARALLEL ARRAY OF BITS, NOT THE CELLS' HIGHLIGHT STATE.** See the header's third
	 * paragraph: `-setSelectionFrom:to:anchor:highlight:` must be able to select without drawing the selection, so the
	 * two facts get two homes. `_anchor` is the linear index a shift-click extends FROM, and -1 means "none yet". */
	BOOL *_selected;
	NSInteger _anchor;
	Class _cellClass;
	NSCell *_prototype;			/* RETAINED; copied for each new cell when set */
	NSSize _cellSize;
	NSSize _intercellSpacing;

	/* ---- THE POLICY ---------------------------------------------------------------------------------- */
	NSMatrixMode _mode;
	BOOL _allowsEmptySelection;
	BOOL _selectionByRect;
	BOOL _autosizesCells;
	BOOL _validateSize;
	BOOL _autoscroll;
	BOOL _tabKeyTraversesCells;
	BOOL _scrollable;
	BOOL _drawsBackground;
	BOOL _drawsCellBackground;
	NSColor *_backgroundColor;		/* RETAINED */
	NSColor *_cellBackgroundColor;		/* RETAINED */
	id <NSMatrixDelegate> _delegate;	/* ASSIGN, as every delegate in this tree */
	SEL _doubleAction;
	NSInteger _mouseDownFlags;

	/* ---- THE SESSION AND THE TRACKING ----------------------------------------------------------------- */
	/* THE CELL A LIVE FIELD SESSION BELONGS TO, as a linear index, or -1. The editor is the cell's; this is what makes
	 * `-currentEditor` and `-abortEditing` answer for the RIGHT cell rather than for the last one a caller selected. */
	NSInteger _editingIndex;
	/* THE CELL THE POINTER IS DOWN ON, or -1. `-sendAction` reads it so a track-mode click sends the CLICKED cell's
	 * action even though a track-mode click leaves no selection behind. */
	NSInteger _trackingIndex;
	/* THE CELL THE KEYBOARD IS ON. Separate from the selection: a radio group can have its "on" cell selected and its
	 * keyboard cell elsewhere, and a tab through a form moves this without changing what is chosen. */
	NSInteger _keyRow;
	NSInteger _keyColumn;

	/* ---- THE MATRIX'S OWN TARGET/ACTION, WHICH IS NOT A CELL'S ------------------------------------------ */
	/* **`NSControl` KEEPS THIS PAIR ON ITS CELL AND A MATRIX HAS NO SINGLE CELL**, so the four doors are OVERRIDDEN
	 * here rather than forwarded: a matrix's target/action is what the double-click action and the cells that have
	 * none of their own fall back to. Each cell still keeps its own, which is what `-sendAction:to:forAllCells:` and a
	 * caller's per-cell target use. */
	id _target;				/* ASSIGN */
	SEL _action;

	/* ---- THE TOOL TIPS, KEYED BY THE CELL THEY BELONG TO ------------------------------------------------ */
	/* **KEYED BY THE CELL RATHER THAN BY ITS POSITION**, because a tool tip belongs to a face and an insertion must
	 * not move it to the cell that took over the index. A cell removed from the grid leaves an entry nothing can ask
	 * for — the map is cleared when the grid is freed, which is the one place the leak is bounded. */
	NSMutableDictionary *_cellToolTips;
}

/* ============================================================================================ *
 * THE DESIGNATED INITIALISERS. THREE DOORS AND THREE DIFFERENT ANSWERS ABOUT WHERE CELLS COME FROM. *
 * ============================================================================================ */

/* NO CELLS AT ALL. Apple's `-initWithFrame:` leaves the matrix empty, and a caller then asks for a shape with
 * `-renewRows:columns:` or builds it a row at a time. It is a real state: a matrix with no cells draws nothing and
 * tracks nothing, and every door below answers for it rather than crashing. */
- (instancetype)initWithFrame:(NSRect)frameRect;

/* A FRESH CELL OF `cellClass` PER POSITION. The cell size is taken from one instance of the class, so a matrix of
 * buttons gets a button's natural size without a second door being called. */
- (instancetype)initWithFrame:(NSRect)aRect mode:(NSMatrixMode)aMode cellClass:(nullable Class)aClass
		 numberOfRows:(NSInteger)numberOfRows numberOfColumns:(NSInteger)numberOfColumns;

/* AND THE SAME, FROM A CELL A CALLER BUILT. The prototype is retained and every position gets `-copy` of it, which is
 * what makes a matrix of configured buttons one call rather than `rows × columns` of them. */
- (instancetype)initWithFrame:(NSRect)aRect mode:(NSMatrixMode)aMode prototype:(NSCell *)aCell
		 numberOfRows:(NSInteger)numberOfRows numberOfColumns:(NSInteger)numberOfColumns;

/* ============================================================================================ *
 * THE GRID: WHAT THE SHAPE IS, AND THE CELLS IN IT.                                              *
 * ============================================================================================ */

- (void)getNumberOfRows:(nullable NSInteger *)rowCount columns:(nullable NSInteger *)columnCount;
- (NSInteger)numberOfRows;
- (NSInteger)numberOfColumns;

/* **THE FLAT CELL ARRAY, ROW-MAJOR, WHICH IS APPLE'S SHAPE RATHER THAN THIS TREE'S CONVENIENCE.** A caller that wants
 * cell `(r, c)` indexes `r * numberOfColumns + c`, and `-cellAtRow:column:` is that arithmetic with the bounds check
 * it needs. The array is the matrix's own storage: it is valid until the shape changes, and the matrix may MOVE it
 * when a row or column is added, so a caller holds the pointer across no such call. */
- (NSCell **)cells;
- (nullable NSCell *)cellAtRow:(NSInteger)row column:(NSInteger)column;

/* AND THE ONE DOOR THAT IS A LOOKUP RATHER THAN AN INDEX. Apple's contract is the FIRST cell with the tag; a matrix
 * with two cells of one tag answers the earlier one, which is the row-major order above. */
- (nullable NSCell *)cellWithTag:(NSInteger)tag;

/* THE FOUR SHAPE CHANGES, EACH WITH A CELLS VARIANT WHOSE ARGUMENT IS THE NEW ROW OR COLUMN'S CELLS (or NULL for
 * cells this class makes). `-addRow` and `-addColumn` append; `-insertRow:` and `-insertColumn:` place. */
- (void)addRow;
- (void)addRowWithCells:(NSCell * _Nullable *)newCells;
- (void)addColumn;
- (void)addColumnWithCells:(NSCell * _Nullable *)newCells;
- (void)insertRow:(NSInteger)row;
- (void)insertRow:(NSInteger)row withCells:(NSCell * _Nullable *)newCells;
- (void)insertColumn:(NSInteger)column;
- (void)insertColumn:(NSInteger)column withCells:(NSCell * _Nullable *)newCells;
- (void)removeRow:(NSInteger)row;
- (void)removeColumn:(NSInteger)column;

/* **AND THE DOOR THAT THROWS THE GRID AWAY AND MAKES A NEW ONE.** Every existing cell is released; a prototype makes
 * copies and a class makes instances. This is what resets a caller's matrix, and it is also what `-initWithFrame:`
 * leaves for a caller who built the frame first and the shape second. */
- (void)renewRows:(NSInteger)newRows columns:(NSInteger)newColumns;

/* PUT ONE CELL WHERE ANOTHER WAS, AND (RE)MAKE ONE. `-putCell:atRow:column:` takes ownership of `newCell`; a nil cell
 * is a hole rather than an error, which is what makes it the door for removing a single position without changing the
 * shape. `-makeCellAtRow:column:` is the construction rule the shape changes use, published so a subclass can
 * override where cells come from. */
- (void)putCell:(nullable NSCell *)newCell atRow:(NSInteger)row column:(NSInteger)column;
- (nullable NSCell *)makeCellAtRow:(NSInteger)row column:(NSInteger)column;

/* THE CLASS AND THE PROTOTYPE, as the two answers to "what is a new cell". Setting a prototype sets the cell class to
 * the prototype's own, which is Apple's rule and the reason the two doors cannot disagree. Neither touches cells that
 * already exist. */
- (nullable Class)cellClass;
- (void)setCellClass:(Class)cellClass;
- (nullable NSCell *)prototype;
- (void)setPrototype:(nullable NSCell *)aCell;

/* ============================================================================================ *
 * THE GEOMETRY: WHERE A CELL IS, WHICH POINT IS WHICH CELL, AND HOW BIG.                          *
 * ============================================================================================ */

- (NSSize)cellSize;
- (void)setCellSize:(NSSize)aSize;
- (NSSize)intercellSpacing;
- (void)setIntercellSpacing:(NSSize)aSize;

/* **THE MATRIX IS FLIPPED.** Row 0 is the top row. This is not an aesthetic choice: Apple lays a matrix out from the
 * top, a form's first entry is its first row, and a browser-style grid reads downward. Declared here because a caller
 * that computes a cell's frame itself has to know which way y runs. */
- (BOOL)isFlipped;

/* AND THE FRAME OF A CELL, in the matrix's own coordinates. Row and column out of range is `NSZeroRect`, which is the
 * answer that composes with "no cell" rather than a reason to stop. */
- (NSRect)cellFrameAtRow:(NSInteger)row column:(NSInteger)column;

/* **THE TWO INVERSE LOOKUPS, BOTH ANSWERING WHETHER THEY FOUND ANYTHING.** `-getRow:column:forPoint:` takes a point in
 * the matrix's coordinates and answers NO when it falls in the SPACING between cells — a gap is not a cell, and a
 * caller clicking one has clicked the matrix and no face. `-getRow:column:ofCell:` asks the same question of a cell. */
- (BOOL)getRow:(nullable NSInteger *)row column:(nullable NSInteger *)column forPoint:(NSPoint)aPoint;
- (BOOL)getRow:(nullable NSInteger *)row column:(nullable NSInteger *)column ofCell:(NSCell *)aCell;

/* **AND THE THREE SIZE POLICIES, WHICH ARE DIFFERENT QUESTIONS.** `-sizeToCells` sizes the RECEIVER to its cells.
 * `-autosizesCells` says the cells stretch to fill whatever frame the receiver has, recomputed at layout time.
 * `-setValidateSize:` says a frame CHANGE resizes the stored cell size once, so the size a caller reads back is the
 * one in use. The first moves the view, the second and third move the cells, and the difference between the last two
 * is WHEN the arithmetic happens rather than what it is. */
- (void)sizeToCells;
- (BOOL)autosizesCells;
- (void)setAutosizesCells:(BOOL)flag;
- (void)setValidateSize:(BOOL)flag;

/* Whether a CELL's contents scroll inside it (a text cell's long string) — forwarded to every cell, which is where
 * the flag lives. */
- (void)setScrollable:(BOOL)flag;

/* ============================================================================================ *
 * THE SELECTION.                                                                                 *
 * ============================================================================================ */

- (NSMatrixMode)mode;
- (void)setMode:(NSMatrixMode)aMode;
- (BOOL)allowsEmptySelection;
- (void)setAllowsEmptySelection:(BOOL)flag;
- (BOOL)isSelectionByRect;
- (void)setSelectionByRect:(BOOL)flag;

- (nullable NSCell *)selectedCell;
- (nullable NSArray *)selectedCells;
- (NSInteger)selectedRow;
- (NSInteger)selectedColumn;

- (void)selectCellAtRow:(NSInteger)row column:(NSInteger)column;
- (BOOL)selectCellWithTag:(NSInteger)tag;
- (void)selectAll:(nullable id)sender;
- (void)deselectAllCells;
- (void)deselectSelectedCell;

/* **THE RANGE DOOR, WHICH IS WHY SELECTION AND HIGHLIGHT ARE TWO FACTS.** The three positions are LINEAR indices
 * (`row * columns + column`), `-highlight:` says whether the selection is DRAWN as selected, and the anchor is where
 * a later shift-click extends from. A caller that wants a selection a person cannot see — a matrix that is showing
 * one pane of a two-pane choice — passes NO. */
- (void)setSelectionFrom:(NSInteger)startPos to:(NSInteger)endPos anchor:(NSInteger)anchorPos highlight:(BOOL)lit;

/* **THE KEYBOARD'S CELL, WHICH IS NOT THE SELECTION.** A tab through a form moves the key cell; a click moves the
 * selection. They coincide until one of the two is moved alone, and a matrix that kept one field for both would move
 * a selection on a tab that Apple says does not. */
- (nullable NSCell *)keyCell;
- (void)setKeyCell:(nullable NSCell *)aCell;

/* ============================================================================================ *
 * THE FACE: WHAT IS DRAWN, AND WHERE IT IS DRAWN FROM.                                           *
 * ============================================================================================ */

- (void)drawCellAtRow:(NSInteger)row column:(NSInteger)column;

- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)flag;
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;

/* **AND THE SAME PAIR FOR A CELL RATHER THAN THE GRID** — a matrix whose faces sit on a cell-sized chip of their own,
 * which is what a checkerboard or a calendar's cells want. */
- (BOOL)drawsCellBackground;
- (void)setDrawsCellBackground:(BOOL)flag;
- (nullable NSColor *)cellBackgroundColor;
- (void)setCellBackgroundColor:(nullable NSColor *)color;

/* ============================================================================================ *
 * THE CLICK, THE ACTION AND THE KEYBOARD.                                                        *
 * ============================================================================================ */

- (nullable id <NSMatrixDelegate>)delegate;
- (void)setDelegate:(nullable id <NSMatrixDelegate>)anObject;
- (nullable SEL)doubleAction;
- (void)setDoubleAction:(nullable SEL)aSelector;

/* **THE THREE SENDERS, WHICH ARE THREE DIFFERENT AUDIENCES.** `-sendAction` is the SELECTED cell's action, sent with
 * the matrix as sender (the control a target was set on). `-sendDoubleAction` is the matrix's own double-click action.
 * `-sendAction:to:forAllCells:` is every cell's — each cell sent as the sender — which is a form's "commit all" and
 * the door a dialog's OK button reaches for. */
- (void)sendAction;
- (void)sendDoubleAction;
- (void)sendAction:(nullable SEL)aSelector to:(nullable id)target forAllCells:(BOOL)flag;

/* **THE TRACKING LOOP, AND THE ONE FACT IT RECORDS.** `-mouseDownFlags` is the modifier word of the most recent press,
 * which a subclass reads in `-mouseDown:` to decide what a shift-click means after the event is gone. Apple publishes
 * it as a read-only door and this class keeps it a scalar rather than an `NSEvent`. */
- (NSInteger)mouseDownFlags;
- (BOOL)acceptsFirstMouse:(nullable NSEvent *)theEvent;
- (BOOL)performKeyEquivalent:(NSEvent *)theEvent;

/* **AUTOSCROLL IS A DRAG THAT LEAVES THE MATRIX.** When it is on and the tracked cell is outside the matrix's visible
 * rectangle, `-scrollCellToVisibleAtRow:column:` runs — which needs an enclosing scroll view and does nothing without
 * one. A click with no drag never asks. */
- (BOOL)isAutoscroll;
- (void)setAutoscroll:(BOOL)flag;
- (void)scrollCellToVisibleAtRow:(NSInteger)row column:(NSInteger)column;

/* Whether Tab moves the KEY CELL to the next cell or leaves the matrix. Read by `-keyDown:` and by the end of a field
 * session whose movement was Tab. */
- (BOOL)tabKeyTraversesCells;
- (void)setTabKeyTraversesCells:(BOOL)flag;

/* THE CELL'S CURSOR RECTS, forwarded so a cell that wants an I-beam can say so. */
- (void)resetCursorRects;

/* ============================================================================================ *
 * TOOL TIPS AND SORTING.                                                                         *
 * ============================================================================================ */

/* Stored per cell and read back. The window's tool-tip machinery is a placeholder in this tree (see
 * `NSView -addToolTipRect:owner:userData:`), so the registration is made and the string is what a caller can verify. */
- (void)setToolTip:(nullable NSString *)string forCell:(NSCell *)cell;
- (nullable NSString *)toolTipForCell:(NSCell *)cell;

/* **SORTING SORTS EACH COLUMN.** Apple's contract is a comparison function over cells, and this tree's implementation
 * is an insertion sort so that equal answers keep their order — the property a caller checking a sorted grid actually
 * relies on. `-sortUsingSelector:` is the same walk with the comparison sent as a message. */
- (void)sortUsingFunction:(NSInteger (*)(id, id, void *))compare context:(nullable void *)context;
- (void)sortUsingSelector:(SEL)comparator;

/* ============================================================================================ *
 * THE CELL'S STATE AND HIGHLIGHT, BY POSITION.                                                   *
 * ============================================================================================ */

/* `-setState:atRow:column:` writes the cell's state (and in a radio matrix turns the others off, which is the one
 * place the mode reaches a value rather than a policy). `-highlightCell:atRow:column:` sets the cell's DRAWN highlight
 * and changes no selection — it is what the tracking loop uses while the pointer is moving. */
- (void)setState:(NSInteger)value atRow:(NSInteger)row column:(NSInteger)column;
- (void)highlightCell:(BOOL)flag atRow:(NSInteger)row column:(NSInteger)column;

/* ============================================================================================ *
 * THE FIELD SESSION, WHICH A MATRIX OPENS AND WHICH CELL IT BELONGS TO.                           *
 * ============================================================================================ */

- (void)selectText:(nullable id)sender;
- (void)selectTextAtRow:(NSInteger)row column:(NSInteger)column;

/* **THE FIVE DOORS THE FIELD EDITOR'S DELEGATE CONVERSATION ARRIVES THROUGH.** They are declared on `NSMatrix` because
 * a matrix is what knows which cell is being edited, and they are re-homed to the delegate exactly as `NSTextField`'s
 * are: the notification's object is the MATRIX and the editor travels in the `userInfo` under
 * `NSFieldEditorUserInfoKey`. The `Should` pair is asked and answered, and NO is honoured. */
- (BOOL)textShouldBeginEditing:(nullable NSText *)textObject;
- (BOOL)textShouldEndEditing:(nullable NSText *)textObject;
- (void)textDidBeginEditing:(nullable NSNotification *)notification;
- (void)textDidChange:(nullable NSNotification *)notification;
- (void)textDidEndEditing:(nullable NSNotification *)notification;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSMATRIX_H */
