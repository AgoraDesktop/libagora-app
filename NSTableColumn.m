/*
 * NSTableColumn — one column's width, cells and sort prototype.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * The width is the only piece with arithmetic: a set clamps to the range, a range change pulls the width back inside
 * it, and every change asks the table to re-tile because a column's width is the table's frame. The two cells are
 * retained here and nowhere else; the table lends the data cell to each row it draws.
 */
#import "NSTableColumn.h"
#import "NSTableHeaderCell.h"
#import "NSTableView.h"

#import "NSTextFieldCell.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSSortDescriptor.h>

#define AG_TABLE_COLUMN_DEFAULT_WIDTH 100.0
#define AG_TABLE_COLUMN_MIN_WIDTH 10.0
#define AG_TABLE_COLUMN_MAX_WIDTH 1000000.0

@implementation NSTableColumn

- (instancetype)initWithIdentifier:(id)identifier
{
	self = [super init];
	if (self != nil) {
		_identifier = [(identifier != nil ? identifier : @"") copy];
		_tableView = nil;
		_width = AG_TABLE_COLUMN_DEFAULT_WIDTH;
		_minWidth = AG_TABLE_COLUMN_MIN_WIDTH;
		_maxWidth = AG_TABLE_COLUMN_MAX_WIDTH;
		/* THE HEADER'S DEFAULT TITLE IS THE IDENTIFIER, which is Apple's own default and the one that makes a column
		 * added by a caller readable before any title is set. */
		_headerCell = [[NSTableHeaderCell alloc] initTextCell:[_identifier description]];
		[_headerCell setAlignment:NSCenterTextAlignment];
		{ /* A HEADER'S FACE IS THE TABLE'S, NOT A FIELD'S: no border, no background, no editor. */
			NSTableHeaderCell *header = (NSTableHeaderCell *)_headerCell;
			[header setBordered:NO];
			[header setBezeled:NO];
			[header setDrawsBackground:NO];
			[header setEditable:NO];
		}
		_dataCell = [[NSTextFieldCell alloc] initTextCell:@""];
		[_dataCell setBordered:NO];
		[_dataCell setBezeled:NO];
		[(NSTextFieldCell *)_dataCell setDrawsBackground:NO];
		[_dataCell setEditable:NO];
		[_dataCell setAlignment:NSLeftTextAlignment];
		_resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
		_editable = NO;
		_hidden = NO;
		_headerToolTip = nil;
		_sortDescriptorPrototype = nil;
	}
	return self;
}

- (void)dealloc
{
	[_identifier release];
	[_headerCell release];
	[_dataCell release];
	[_headerToolTip release];
	[_sortDescriptorPrototype release];
	[super dealloc];
}

- (void)setIdentifier:(id)identifier
{
	id copy = [(identifier != nil ? identifier : @"") copy];

	[_identifier release];
	_identifier = copy;
	/* AND THE HEADER FOLLOWS THE NAME when nobody has given it a title of its own. A column whose identifier changed
	 * and whose header still said the old one is two names for one thing. */
	if ([_headerCell isKindOfClass:[NSTableHeaderCell class]]) {
		[_headerCell setStringValue:[_identifier description]];
	}
}

- (id)identifier
{
	return _identifier;
}

- (void)setTableView:(NSTableView *)tableView
{
	_tableView = tableView;	/* NOT RETAINED */
}

- (NSTableView *)tableView
{
	return _tableView;
}

/* ---- THE WIDTH AND ITS RANGE ------------------------------------------------------------------- */

static CGFloat fn_column_clamp(NSTableColumn *column, CGFloat width)
{
	if (width < [column minWidth]) {
		width = [column minWidth];
	}
	if ([column maxWidth] > 0.0 && width > [column maxWidth]) {
		width = [column maxWidth];
	}
	return width;
}

- (void)setWidth:(CGFloat)width
{
	CGFloat clamped = fn_column_clamp(self, width);

	if (clamped == _width) {
		return;
	}
	_width = clamped;
	[_tableView tile];
	[_tableView setNeedsDisplay:YES];
}

- (CGFloat)width
{
	return _width;
}

- (void)setMinWidth:(CGFloat)minWidth
{
	_minWidth = minWidth;
	if (_maxWidth > 0.0 && _minWidth > _maxWidth) {
		_maxWidth = _minWidth;
	}
	if (_width < _minWidth) {
		_width = _minWidth;
		[_tableView tile];
	}
}

- (CGFloat)minWidth
{
	return _minWidth;
}

- (void)setMaxWidth:(CGFloat)maxWidth
{
	_maxWidth = maxWidth;
	if (_maxWidth > 0.0 && _maxWidth < _minWidth) {
		_minWidth = _maxWidth;
	}
	if (_maxWidth > 0.0 && _width > _maxWidth) {
		_width = _maxWidth;
		[_tableView tile];
	}
}

- (CGFloat)maxWidth
{
	return _maxWidth;
}

/* ---- THE TWO CELLS ----------------------------------------------------------------------------- */

- (void)setHeaderCell:(NSCell *)cell
{
	[cell retain];
	[_headerCell release];
	_headerCell = cell;
	[_tableView setNeedsDisplay:YES];
}

- (NSCell *)headerCell
{
	return _headerCell;
}

- (void)setDataCell:(NSCell *)cell
{
	[cell retain];
	[_dataCell release];
	_dataCell = cell;
	[_tableView setNeedsDisplay:YES];
}

- (NSCell *)dataCell
{
	return _dataCell;
}

- (NSCell *)dataCellForRow:(NSInteger)row
{
	(void)row;
	return _dataCell;
}

/* ---- EDITABILITY, SIZE AND RESIZING ------------------------------------------------------------ */

- (void)setEditable:(BOOL)flag
{
	_editable = flag ? YES : NO;
	[_dataCell setEditable:_editable];
}

- (BOOL)isEditable
{
	return _editable;
}

- (void)sizeToFit
{
	CGFloat header = 0.0;

	if (_headerCell != nil) {
		header = [_headerCell cellSizeForBounds:NSMakeRect(0.0, 0.0, AG_TABLE_COLUMN_MAX_WIDTH, 20.0)].width;
	}
	/* THE HEADER'S WORD PLUS THE CELL'S PADDING IS THE MEASUREMENT.** A data cell's own measure would be the widest
	 * value that happens to be in the model, which a column fitted to its header should not depend on. */
	[self setWidth:header + 16.0];
}

- (void)setResizingMask:(NSUInteger)resizingMask
{
	_resizingMask = resizingMask;
}

- (NSUInteger)resizingMask
{
	return _resizingMask;
}

/* ---- THE SORT PROTOTYPE, THE TOOL TIP AND HIDDEN ------------------------------------------------ */

- (void)setSortDescriptorPrototype:(NSSortDescriptor *)sortDescriptor
{
	[sortDescriptor retain];
	[_sortDescriptorPrototype release];
	_sortDescriptorPrototype = sortDescriptor;
}

- (NSSortDescriptor *)sortDescriptorPrototype
{
	return _sortDescriptorPrototype;
}

- (void)setHeaderToolTip:(NSString *)string
{
	NSString *copy = [string copy];

	[_headerToolTip release];
	_headerToolTip = copy;
}

- (NSString *)headerToolTip
{
	return _headerToolTip;
}

- (BOOL)isHidden
{
	return _hidden;
}

- (void)setHidden:(BOOL)hidden
{
	_hidden = hidden ? YES : NO;
	[_tableView tile];
	[_tableView setNeedsDisplay:YES];
}

@end
