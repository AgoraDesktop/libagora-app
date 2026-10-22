/*
 * NSForm — a one-column matrix of form cells.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **EVERY DOOR HERE IS A ROW OR A LOOP OVER ROWS, AND THAT IS THE CLASS.** A form's entry index is a matrix row; its
 * column is always zero; its cells are `NSFormCell`s. So there is no geometry here — `NSMatrix` owns that — and no
 * editing session either: `-selectTextAtIndex:` is `-selectTextAtRow:column:` with the column supplied. What this file
 * decides is the four things a form has that a matrix does not: the DEFAULT CELL SIZE (a measured line, not the
 * six-point height an empty text cell reports), the shape (zero rows and one column, so `-addEntry:` has somewhere to
 * put the first one), the editing defaults an entry is born with, and the arithmetic of `-setEntryWidth:`.
 */
#import <AppKit/NSForm.h>

#import <AppKit/NSFormCell.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSText.h>

#include <math.h>

@implementation NSForm

/* ============================================================================================ *
 * THE SHAPE, AND THE SIZE A CELL STARTS AT.                                                     *
 * ============================================================================================ */

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect mode:NSRadioModeMatrix cellClass:[NSFormCell class]
			 numberOfRows:0 numberOfColumns:1];
	if (self != nil) {
		/* **THE DEFAULT CELL SIZE IS MEASURED RATHER THAN INHERITED, AND THE REASON IS MEASURED TOO**: a form cell
		 * with no value reports the height of nothing — about six points of padding — because `NSCell -cellSize`
		 * measures the cell's TEXT. A form whose first entry is six points tall is a form whose first entry cannot be
		 * read, so the height is raised to a line of the system font inside the field's own padding. The width is the
		 * era's entry width for a form that has not been given one: 100 points. */
		NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
		NSSize line = [@" " sizeWithAttributes:[NSDictionary dictionaryWithObject:font
								  forKey:NSFontAttributeName]];

		/* **AND THE ENTRY IS AS WIDE AS THE FORM IT IS IN**, because a form is one column: a cell narrower than the
		 * matrix would leave the value band short of the form's own edge, which is the one thing a caller looking at a
		 * form would call wrong. A form made with a zero width keeps the era's 100-point entry as its starting width. */
		{
			CGFloat width = (NSWidth(frameRect) > 0.0) ? NSWidth(frameRect) : 100.0;

			[self setCellSize:NSMakeSize(width,
						     ceil(line.height) + 2.0 * NS_TEXT_INSET + 2.0 * NS_CELL_BEZEL_WIDTH)];
		}
		[self setIntercellSpacing:NSMakeSize(0.0, 4.0)];
	}
	return self;
}

/* ============================================================================================ *
 * THE ENTRIES.                                                                                  *
 * ============================================================================================ */

- (NSFormCell *)insertEntry:(NSString *)title atIndex:(NSInteger)index
{
	NSFormCell *cell;

	if (index < 0) {
		index = 0;
	}
	if (index > [self numberOfRows]) {
		index = [self numberOfRows];
	}
	[self insertRow:index];
	cell = [self cellAtIndex:index];
	if (cell != nil) {
		/* **AN ENTRY IS BORN BORDERED, BEZELED AND EDITABLE** — a form's value band is something a person types into,
		 * and a cell that defaulted to a label would be a form nobody can fill in. The label is the title. */
		[cell setBordered:YES];
		[cell setBezeled:YES];
		[cell setEditable:YES];
		[cell setSelectable:YES];
		[cell setTitle:title];
		[cell setStringValue:@""];
	}
	[self setNeedsDisplay:YES];
	return cell;
}

- (NSFormCell *)addEntry:(NSString *)title
{
	return [self insertEntry:title atIndex:[self numberOfRows]];
}

- (void)removeEntryAtIndex:(NSInteger)index
{
	if (index < 0 || index >= [self numberOfRows]) {
		return;
	}
	[self removeRow:index];
	[self setNeedsDisplay:YES];
}

- (NSFormCell *)cellAtIndex:(NSInteger)index
{
	return (NSFormCell *)[self cellAtRow:index column:0];
}

- (void)drawCellAtIndex:(NSInteger)index
{
	[self drawCellAtRow:index column:0];
}

- (void)selectTextAtIndex:(NSInteger)index
{
	[self selectTextAtRow:index column:0];
}

- (NSInteger)indexOfSelectedItem
{
	return [self selectedRow];
}

- (NSInteger)indexOfCellWithTag:(NSInteger)tag
{
	NSCell *cell = [self cellWithTag:tag];
	NSInteger row = -1, column = -1;

	(void)column;
	if (cell == nil || ![self getRow:&row column:&column ofCell:cell]) {
		return -1;
	}
	return row;
}

/* ============================================================================================ *
 * THE FORM'S VOICE.                                                                             *
 * ============================================================================================ */

/* THE LOOP IS THE CLASS'S ONE IDIOM, written once as a block-shaped helper would be if this class had state to keep.
 * Setting a property on every cell is the whole of "the form's font/alignment/direction". */
- (void)setTitleFont:(NSFont *)font
{
	NSInteger i;

	for (i = 0; i < [self numberOfRows]; i++) {
		[[self cellAtIndex:i] setTitleFont:font];
	}
	[self setNeedsDisplay:YES];
}

- (void)setTextFont:(NSFont *)font
{
	NSInteger i;

	for (i = 0; i < [self numberOfRows]; i++) {
		[[self cellAtIndex:i] setFont:font];
	}
	[self setNeedsDisplay:YES];
}

- (void)setTitleAlignment:(NSTextAlignment)mode
{
	NSInteger i;

	for (i = 0; i < [self numberOfRows]; i++) {
		[[self cellAtIndex:i] setTitleAlignment:mode];
	}
	[self setNeedsDisplay:YES];
}

- (void)setTextAlignment:(NSTextAlignment)mode
{
	NSInteger i;

	for (i = 0; i < [self numberOfRows]; i++) {
		[[self cellAtIndex:i] setAlignment:mode];
	}
	[self setNeedsDisplay:YES];
}

- (void)setTitleBaseWritingDirection:(NSWritingDirection)mode
{
	NSInteger i;

	for (i = 0; i < [self numberOfRows]; i++) {
		[[self cellAtIndex:i] setTitleBaseWritingDirection:mode];
	}
	[self setNeedsDisplay:YES];
}

- (void)setTextBaseWritingDirection:(NSWritingDirection)mode
{
	NSInteger i;

	for (i = 0; i < [self numberOfRows]; i++) {
		[[self cellAtIndex:i] setBaseWritingDirection:mode];
	}
	[self setNeedsDisplay:YES];
}

/* **THE ENTRY WIDTH IS THE VALUE BAND, SO THE LABEL BAND IS THE REST.** `NSFormCell`'s `-titleWidth` is where the field
 * starts, so a form that wants `width` points of entry sets each cell's title width to the cell's own width minus that
 * — clamped at zero, because a form narrower than its entry has no label band and must not have a negative one. */
- (void)setEntryWidth:(CGFloat)width
{
	NSInteger i;
	CGFloat cellWidth = [self cellSize].width;

	for (i = 0; i < [self numberOfRows]; i++) {
		NSFormCell *cell = [self cellAtIndex:i];
		CGFloat band = cellWidth - width;

		[cell setTitleWidth:(band > 0.0) ? band : 0.0];
	}
	[self setNeedsDisplay:YES];
}

- (void)setInterlineSpacing:(CGFloat)spacing
{
	[self setIntercellSpacing:NSMakeSize([self intercellSpacing].width, (spacing > 0.0) ? spacing : 0.0)];
	[self setNeedsDisplay:YES];
}

- (void)setBezeled:(BOOL)flag
{
	NSInteger i;

	for (i = 0; i < [self numberOfRows]; i++) {
		[[self cellAtIndex:i] setBezeled:flag];
	}
	[self setNeedsDisplay:YES];
}

- (void)setBordered:(BOOL)flag
{
	NSInteger i;

	for (i = 0; i < [self numberOfRows]; i++) {
		[[self cellAtIndex:i] setBordered:flag];
	}
	[self setNeedsDisplay:YES];
}

/* **A FRAME CHANGE IS AN ENTRY-WIDTH CHANGE.** One column means the whole of a new width belongs to the entry, so the
 * cell size's width follows the frame and the labels keep their stored bands. The height is left alone: a form's rows
 * are as tall as its cell size says, and a frame change is not a request to re-measure a typeface. */
- (void)setFrameSize:(NSSize)newSize
{
	NSSize size;

	[super setFrameSize:newSize];
	if ([self numberOfRows] <= 0) {
		return;
	}
	size = [self cellSize];
	size.width = newSize.width;
	[self setCellSize:size];
	[self setNeedsDisplay:YES];
}

@end
