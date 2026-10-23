/*
 * control_tail — the last twenty-eight nodes of NSControl: the cell class, the one-cell selection, the
 * four paint/invalidate doors, the sender-value family, the formatter pair and validateEditing.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A CONTROL IS A VIEW WITH ONE CELL, SO ALMOST EVERY DOOR HERE IS A FORWARD AND THE PROBE HAS TO ASK THE CELL.**
 * The exceptions are the class factory, the paint/invalidate quartet and `-validateEditing`, and each of those is
 * measured by an effect rather than by a return value: a probe cell counts the paints and the calc, a real text field
 * proves the editor's string lands in the cell, and the sender family is one object with six different answers.
 *
 * WHAT IS ASSERTED, each one a behaviour that did not exist before this slice:
 *
 *   1. `+cellClass` answers `NSCell` until `+setCellClass:` names another, and the chosen class is what it answers.
 *   2. The one-cell selection: `-selectedCell` is the cell, `-selectedTag` is its tag (or -1 without one), and
 *      `-selectCell:` puts it in NSOnState.
 *   3. `-sendActionOn:` is the cell's mask door, returning the PREVIOUS mask.
 *   4. `-drawCell:` and `-drawCellInside:` paint the named cell only when it is this control's, and `-updateCell:` /
 *      `-updateCellInside:` / `-setNeedsDisplay` are invalidation.
 *   5. `-calcSize` asks the cell to recalculate its drawing information for the control's bounds.
 *   6. `-formatter`, `-setFormatter:`, `-setFloatingPointFormat:left:right:`, `-attributedStringValue` and
 *      `-baseWritingDirection` are the cell's state, and the float format's reader is the cell's own `-stringValue`.
 *   7. The six `-take…ValueFrom:` doors take the sender's six answers and write them through the control.
 *   8. `-refusesFirstResponder` is the cell's keyboard flag.
 *   9. `-validateEditing` copies the running editor's string into the cell without ending the session.
 */
#import <AppKit/NSControl.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSText.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* **A CELL THAT COUNTS THE FOUR DOORS THE CONTROL FORWARDS.** The counts are the proof that `-drawCell:` reached the
 * cell and that a cell the control does not own was not painted. */
@interface AGCountCell : NSCell
{
@public
	int draws;
	int interiors;
	int calcs;
	BOOL sawCalcRect;
}
@end

@implementation AGCountCell
- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame; (void)controlView;
	draws++;
}
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame; (void)controlView;
	interiors++;
}
- (void)calcDrawInfo:(NSRect)aRect
{
	sawCalcRect = (NSWidth(aRect) > 0.0 && NSHeight(aRect) > 0.0);
	calcs++;
}
@end

/* ONE OBJECT WITH SIX DIFFERENT ANSWERS, so each `-take…ValueFrom:` is visibly asking the right question. */
@interface AGSixValueSender : NSObject
@end

@implementation AGSixValueSender
- (int)intValue { return 11; }
- (NSInteger)integerValue { return 13; }
- (float)floatValue { return 2.5f; }
- (double)doubleValue { return 3.25; }
- (NSString *)stringValue { return @"taken"; }
- (id)objectValue { return @"object"; }
@end

int main(void)
{
	@autoreleasepool {
		NSControl *control = [[NSControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 30.0)];
		AGCountCell *probe = [[AGCountCell alloc] initTextCell:@"probe"];
		AGCountCell *other = [[AGCountCell alloc] initTextCell:@"other"];

		/* 1. THE CLASS FACTORY. */
		check([NSControl cellClass] == [NSCell class], "`+cellClass` answers NSCell by default");
		[NSControl setCellClass:[NSButtonCell class]];
		check([NSControl cellClass] == [NSButtonCell class], "and `+setCellClass:` names the class it answers");
		[NSControl setCellClass:[NSCell class]];

		/* 2. THE ONE-CELL SELECTION, WITH AND WITHOUT A CELL. */
		check([control selectedCell] == nil && [control selectedTag] == -1,
		      "a control with no cell answers no selected cell and tag -1");
		[probe setTag:7];
		[control setCell:probe];
		check([control selectedCell] == probe, "`-selectedCell` is the cell the control owns");
		check([control selectedTag] == 7, "and `-selectedTag` is that cell's tag");
		[probe setState:NSOffState];
		[control selectCell:probe];
		check([probe state] == NSOnState, "`-selectCell:` puts the named cell in NSOnState");
		[control selectCell:other];
		check([other state] == NSOffState, "and a cell the control does not own is not selected");

		/* 3. THE ACTION MASK, AND ITS PREVIOUS-VALUE RETURN. */
		check([control sendActionOn:NSLeftMouseDownMask] == 0,
		      "`-sendActionOn:` answers the previous mask — zero on a fresh cell");
		check([control sendActionOn:(NSLeftMouseDownMask | NSLeftMouseUpMask)] == NSLeftMouseDownMask,
		      "and the mask it just set is what the next call answers");

		/* 4. THE PAINT AND INVALIDATE QUARTET. */
		probe->draws = probe->interiors = 0;
		[control drawCell:probe];
		[control drawCellInside:probe];
		check(probe->draws == 1 && probe->interiors == 1,
		      "`-drawCell:` and `-drawCellInside:` paint the control's own cell");
		[control drawCell:other];
		[control drawCellInside:other];
		check(probe->draws == 1 && probe->interiors == 1,
		      "and a cell the control does not own is not painted");
		[control setNeedsDisplay:NO];
		[control updateCell:probe];
		check([control needsDisplay], "`-updateCell:` marks the control for display");
		[control setNeedsDisplay:NO];
		[control updateCellInside:probe];
		check([control needsDisplay], "and so does `-updateCellInside:`");
		[control setNeedsDisplay:NO];
		[control setNeedsDisplay];
		check([control needsDisplay], "and the no-argument `-setNeedsDisplay` means YES");

		/* 5. THE CALC DOOR. */
		check(probe->calcs == 0, "the cell has not been asked to recalculate its drawing information yet");
		[control calcSize];
		check(probe->calcs == 1 && probe->sawCalcRect,
		      "`-calcSize` asks the cell with the control's real bounds");

		/* 6. THE FORMATTER, THE FLOAT FORMAT AND THE TWO VALUE SHAPES. */
		{
			NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
			NSTextFieldCell *text = [[NSTextFieldCell alloc] initTextCell:@""];
			NSAttributedString *rich = [[NSAttributedString alloc] initWithString:@"Rich"];

			[control setCell:text];
			[control setFormatter:formatter];
			check([control formatter] == formatter && [text formatter] == formatter,
			      "`-setFormatter:` is the cell's formatter");
			[control setDoubleValue:3.14159];
			[control setFloatingPointFormat:NO left:1 right:2];
			printf("  (note: with the formatter set the value is '%s')\n", [[control stringValue] UTF8String]);
			/* **THE FORMATTER SUPERSEDES THE FLOAT FORMAT**, which is the cell's own documented precedence and the
			 * reason the first version of this check saw "3.142" rather than "3.14": the number formatter was still
			 * attached. Clearing it is what makes the deprecated door's reader visible. */
			check(![[control stringValue] isEqualToString:@"3.14"],
			      "a formatter supersedes the deprecated float format");
			[control setFormatter:nil];
			printf("  (note: without it the value is '%s')\n", [[control stringValue] UTF8String]);
			check([[control stringValue] isEqualToString:@"3.14"],
			      "and without a formatter the float format is read back by the cell's own -stringValue");
			[control setAttributedStringValue:rich];
			check([[control attributedStringValue] isEqual:rich],
			      "the attributed value round-trips through the cell");
			[control setBaseWritingDirection:NSWritingDirectionRightToLeft];
			check([control baseWritingDirection] == NSWritingDirectionRightToLeft,
			      "and the writing direction is the cell's");
			[rich release];
			[text release];
			[formatter release];
		}

		/* 7. THE SIX SENDER-VALUE DOORS. */
		{
			AGSixValueSender *sender = [[AGSixValueSender alloc] init];
			NSTextFieldCell *text = [[NSTextFieldCell alloc] initTextCell:@""];

			[control setCell:text];
			[control takeIntValueFrom:sender];
			check([control intValue] == 11, "`-takeIntValueFrom:` takes intValue from the sender");
			[control takeIntegerValueFrom:sender];
			check([control integerValue] == 13, "`-takeIntegerValueFrom:` takes integerValue");
			[control takeFloatValueFrom:sender];
			check(fabs((double)[control floatValue] - 2.5) < 0.01, "`-takeFloatValueFrom:` takes floatValue");
			[control takeDoubleValueFrom:sender];
			check(fabs([control doubleValue] - 3.25) < 0.01, "`-takeDoubleValueFrom:` takes doubleValue");
			[control takeStringValueFrom:sender];
			check([[control stringValue] isEqualToString:@"taken"], "`-takeStringValueFrom:` takes stringValue");
			[control takeObjectValueFrom:sender];
			check([[control objectValue] isEqual:@"object"], "`-takeObjectValueFrom:` takes objectValue");
			[sender release];
			[text release];
		}

		/* 8. THE KEYBOARD REFUSAL. */
		[control setRefusesFirstResponder:YES];
		check([control refusesFirstResponder], "`-setRefusesFirstResponder:` round-trips");
		[control setRefusesFirstResponder:NO];
		check(![control refusesFirstResponder], "and so does clearing it");

		/* 9. VALIDATING A LIVE EDITOR SESSION. */
		{
			NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 200.0, 40.0)
				styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
			NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 40.0)];
			NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(10.0, 8.0, 160.0, 23.0)];
			NSText *editor;

			[window setContentView:content];
			[content addSubview:field];
			[field setStringValue:@"before"];
			[field setEditable:YES];
			[field selectText:nil];
			editor = [field currentEditor];
			check(editor != nil, "the field opens an editor session");
			if (editor != nil) {
				[editor setString:@"after"];
				[field validateEditing];
				check([[field stringValue] isEqualToString:@"after"],
				      "`-validateEditing` lands the editor's string in the cell");
				check([field currentEditor] == editor,
				      "and does NOT end the session — ending stays the editor's or -abortEditing's job");
				[field abortEditing];
			}
			[field release];
			[content release];
			[window release];
		}

		printf("control_tail: %d case(s) failed\n", s_failed);
		[control release];
		[probe release];
		[other release];
	}
	return s_failed != 0;
}
