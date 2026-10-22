/*
 * NSSearchField.m — a search field is a text field whose cell has two ornaments, and a press that can miss the text.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import <AppKit/NSSearchField.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSEvent.h>

@implementation NSSearchField

/* ============================================================================================
 * ARCHIVING: NOTHING OF ITS OWN: ITS ORNAMENTS, MENU AND BEHAVIOUR ARE ITS CELL'S.
 * ============================================================================================ */
/* Its ornaments, menu and behaviour are its CELL's. A class with no instance storage can inherit both coding methods — `class_getInstanceSize` is what
 * says so, and `NSNib`'s census accepts exactly that case. The conformance is declared so the allow-list's
 * `-conformsToProtocol:` question answers YES. */
+ (BOOL)supportsSecureCoding
{
	return YES;
}


/* **THE INITIALISER SWAPS THE CELL, AND THEN SETS THE FOUR FLAGS AND THE PLACEHOLDER ON IT.** `NSTextField`'s
 * initialiser has already made a text field cell and applied its defaults, so this is the same field with the one
 * subclass that owns the ornaments — there is no second window model, no second editor and no second face. */
- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSSearchFieldCell *cell = [[NSSearchFieldCell alloc] initTextCell:@""];

		[cell setEditable:YES];
		[cell setSelectable:YES];
		[cell setBordered:YES];
		[cell setBezeled:YES];
		[cell setPlaceholderString:@"Search"];
		[self setCell:cell];
		[cell release];
		if (frameRect.size.width <= 0.0 || frameRect.size.height <= 0.0) {
			[self sizeToFit];
		}
	}
	return self;
}

/* ---- THE RECENTS, WHICH ARE THE CELL'S --------------------------------------------------------------- */

- (void)setRecentSearches:(NSArray *)searches
{
	NSSearchFieldCell *cell = (NSSearchFieldCell *)[self cell];

	if ([cell isKindOfClass:[NSSearchFieldCell class]]) {
		[cell setRecentSearches:searches];
	}
}

- (NSArray *)recentSearches
{
	NSSearchFieldCell *cell = (NSSearchFieldCell *)[self cell];

	if ([cell isKindOfClass:[NSSearchFieldCell class]]) {
		return [cell recentSearches];
	}
	return [NSArray array];
}

- (void)setRecentsAutosaveName:(NSString *)string
{
	NSSearchFieldCell *cell = (NSSearchFieldCell *)[self cell];

	if ([cell isKindOfClass:[NSSearchFieldCell class]]) {
		[cell setRecentsAutosaveName:string];
	}
}

- (NSString *)recentsAutosaveName
{
	NSSearchFieldCell *cell = (NSSearchFieldCell *)[self cell];

	if ([cell isKindOfClass:[NSSearchFieldCell class]]) {
		return [cell recentsAutosaveName];
	}
	return nil;
}

/* ---- THE PRESS, WHICH IS THE ONE THING THE VIEW DECIDES ----------------------------------------------- */

/* **THE ORNAMENTS GET THE PRESS BEFORE THE TEXT DOES.** A click on the clear button is not a click into the field:
 * letting the base's press run would open a session over the value the button is about to clear, and the caret would
 * be left in a field with nothing in it. So the point is converted, the cell's own hit test runs, and only a miss
 * reaches `-super`. The conversion is the line the control contributes; the rectangles are the cell's. */
- (void)mouseDown:(NSEvent *)event
{
	NSSearchFieldCell *cell = (NSSearchFieldCell *)[self cell];

	if ([cell isKindOfClass:[NSSearchFieldCell class]] && event != nil) {
		NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];

		if ([cell cg_handleClickAtPoint:point inView:self]) {
			return;
		}
	}
	[super mouseDown:event];
}

@end
