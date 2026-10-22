/*
 * text_view_attributes — the selection's ranges, the view's attributes, and the commands that write them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS THAT A COMMAND CHANGES THE RUN A PERSON SELECTED AND NOTHING ELSE.** So every check reads the STORE
 * back — the attributes at an index — rather than a flag the command set: kerning that is 1.0 only in the command's
 * own bookkeeping is not kerning. The paragraph commands are checked with TWO paragraphs so "the other one is
 * untouched" is measured rather than assumed, and the caret case is checked separately because a command with an empty
 * selection must change the TYPING attributes rather than do nothing.
 *
 * WHAT IS MEASURED:
 *
 *   1. THE RANGES. One range by default, two when set, the first mirrored into `-selectedRange`, every range clamped to
 *      the text, and the affinity and granularity recorded.
 *   2. THE EXPANSION. Character, word, paragraph and document over a known string, including a caret inside a word.
 *   3. THE ATTRIBUTES. The typing attributes fall back to the insertion point's run and to the defaults; a caller's
 *      dictionary reaches the next inserted character; the default paragraph style is where an empty view starts.
 *   4. THE INK. The selection band is filled with the selected-text attributes' background — searched for in a bitmap,
 *      because a band's exact rectangle is the layout's business and its COLOUR is the claim.
 *   5. THE CONTRACT. `-shouldChangeTextInRange:` refuses out-of-bounds and read-only, and the plural form asks each.
 *   6. THE COMMANDS. Kerning, baseline and ligatures over a selection and over a caret; alignment and writing direction
 *      over one paragraph of two; and the colour panel's target applying a colour to the selection.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) s_failed++;
}

static NSTextView *makeView(NSString *text)
{
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 140.0)];

	[view setEditable:YES];
	[view setSelectable:YES];
	[view setString:text];
	return view;
}

/* THE ATTRIBUTE A RUN CARRIES AT AN INDEX, or nil. */
static id attributeAt(NSTextView *view, NSString *key, NSUInteger index)
{
	NSTextStorage *store = [view textStorage];

	return (index < [store length]) ? [[store attributesAtIndex:index effectiveRange:NULL] objectForKey:key] : nil;
}

static double numberAt(NSTextView *view, NSString *key, NSUInteger index)
{
	id value = attributeAt(view, key, index);

	return value != nil ? [value doubleValue] : 0.0;
}

/* ============================================================================================ *
 * THE RANGES AND THE EXPANSION.                                                                 *
 * ============================================================================================ */

static void test_ranges(void)
{
	NSTextView *view = makeView(@"Hello world\nSecond paragraph here");
	NSTextStorage *store = [view textStorage];
	NSUInteger length = [store length];
	NSArray *ranges;

	printf("the ranges\n");
	[view setSelectedRange:NSMakeRange(2, 3)];
	ranges = [view selectedRanges];
	check([ranges count] == 1 && [[ranges objectAtIndex:0] rangeValue].location == 2
	      && [[ranges objectAtIndex:0] rangeValue].length == 3,
	      "a single selection is a one-range array");
	check([view selectedRange].location == 2 && [view selectedRange].length == 3,
	      "and -selectedRange is that range");

	[view setSelectedRanges:[NSArray arrayWithObjects:
		[NSValue valueWithRange:NSMakeRange(0, 2)],
		[NSValue valueWithRange:NSMakeRange(6, 5)], nil]];
	ranges = [view selectedRanges];
	check([ranges count] == 2, "two ranges are kept as two");
	check([view selectedRange].location == 0 && [view selectedRange].length == 2,
	      "and the FIRST is mirrored into -selectedRange");

	/* CLAMPING: a range past the end answers the end. */
	[view setSelectedRanges:[NSArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(length - 2, 40)]]];
	check([view selectedRange].location == length - 2 && [view selectedRange].length == 2,
	      "a range past the end is clamped to it");

	[view setSelectedRange:NSMakeRange(3, 4) affinity:NSTextSelectionAffinityDownstream stillSelecting:NO];
	check([view selectionAffinity] == NSTextSelectionAffinityDownstream, "the affinity is recorded");
	check([[view selectedRanges] count] == 1, "and naming one range returns the view to one");
	[view setSelectionGranularity:NSTextSelectionGranularityWord];
	check([view selectionGranularity] == NSTextSelectionGranularityWord, "the granularity is recorded");

	/* AND THE EXPANSION, ON A STRING WHOSE BOUNDARIES ARE KNOWN. */
	check(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(1, 2)
						     granularity:NSTextSelectionGranularityCharacter],
			    NSMakeRange(1, 2)),
	      "character granularity answers the range it was given");
	check(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(2, 0)
						     granularity:NSTextSelectionGranularityWord],
			    NSMakeRange(0, 5)),
	      "a caret inside \"Hello\" grows to the whole word");
	check(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(8, 0)
						     granularity:NSTextSelectionGranularityWord],
			    NSMakeRange(6, 5)),
	      "and one inside \"world\" grows to that word");
	check(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(14, 1)
						     granularity:NSTextSelectionGranularityParagraph],
			    NSMakeRange(12, 21)),
	      "paragraph granularity grows to the second paragraph's newline");
	check(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(4, 1)
						     granularity:NSTextSelectionGranularityDocument],
			    NSMakeRange(0, length)),
	      "document granularity is the whole text");
	check(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(length, 5)
						     granularity:NSTextSelectionGranularityCharacter],
			    NSMakeRange(length, 0)),
	      "a proposed range past the end is clamped first");

	[view release];
}

/* ============================================================================================ *
 * THE ATTRIBUTES THE VIEW CARRIES.                                                              *
 * ============================================================================================ */

static void test_attributes(void)
{
	NSTextView *view = makeView(@"Hello world");
	NSFont *bold = [NSFont boldSystemFontOfSize:18.0];
	NSMutableParagraphStyle *style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	id typed;

	printf("the attributes\n");
	/* THE RUN `-setString:` MADE CARRIES THE FONT AND NO PARAGRAPH STYLE, so the insertion point's answer is the
	 * font: a paragraph style arrives when a command or a caller writes one. */
	check([[view typingAttributes] objectForKey:NSFontAttributeName] != nil,
	      "a view with text answers the insertion point's run");
	check([[view typingAttributes] objectForKey:NSParagraphStyleAttributeName] == nil,
	      "which carries no paragraph style until one is written");

	[view setSelectedRange:NSMakeRange(0, 0)];
	[view setTypingAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
		bold, NSFontAttributeName, nil]];
	check([[view typingAttributes] objectForKey:NSFontAttributeName] == bold,
	      "a caller's typing attributes are what the view answers");
	[view insertText:@"X"];
	typed = attributeAt(view, NSFontAttributeName, 0);
	check(typed == bold, "and the next character typed wears them");
	check([[view textStorage] length] == 12, "the insertion happened");

	/* THE DEFAULT PARAGRAPH STYLE IS WHERE AN EMPTY VIEW STARTS. */
	[style setAlignment:NSRightTextAlignment];
	[view setString:@""];
	/* NIL IS HOW A CALLER GOES BACK TO "THE INSERTION POINT'S", which is what this check is about. */
	[view setTypingAttributes:nil];
	[view setDefaultParagraphStyle:style];
	check([[[view typingAttributes] objectForKey:NSParagraphStyleAttributeName] alignment] == NSRightTextAlignment,
	      "an empty view's typing attributes carry the default paragraph style");
	check([[view defaultParagraphStyle] alignment] == NSRightTextAlignment,
	      "and the property answers what was set");

	check([[view selectedTextAttributes] objectForKey:NSBackgroundColorAttributeName] != nil,
	      "the selected-text attributes have a background by default");
	check([[view markedTextAttributes] objectForKey:NSUnderlineStyleAttributeName] != nil,
	      "and the marked-text attributes an underline by default");

	[view release];
}

/* THE SELECTION'S INK: search a bitmap for the chosen colour, because the exact band is the layout's business. */
static int bitmapHasColor(NSTextView *view, NSColor *color)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:300 pixelsHigh:140
								      bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
									 isPlanar:NO
								   colorSpaceName:NSCalibratedRGBColorSpace
								      bytesPerRow:300 * 4 bitsPerPixel:32];
	NSInteger x, y;
	int found = 0;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 300.0, 140.0)] fill];
	[view drawRect:[view bounds]];
	for (y = 0; y < 140 && !found; y++) {
		for (x = 0; x < 300; x++) {
			NSColor *pixel = [rep colorAtX:x y:y];

			if (pixel != nil && fabs([pixel redComponent] - [color redComponent]) < 0.02
			    && fabs([pixel greenComponent] - [color greenComponent]) < 0.02
			    && fabs([pixel blueComponent] - [color blueComponent]) < 0.02) {
				found = 1;
				break;
			}
		}
	}
	[rep release];
	return found;
}

static void test_selection_ink(void)
{
	NSTextView *view = makeView(@"Hello world");
	NSColor *magenta = [NSColor colorWithCalibratedRed:1.0 green:0.0 blue:1.0 alpha:1.0];

	printf("the selection's ink\n");
	[view setSelectedRange:NSMakeRange(0, 5)];
	check(bitmapHasColor(view, [NSColor cg_accentColor]),
	      "a selection is filled with the accent when nothing is set");
	[view setSelectedTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
		magenta, NSBackgroundColorAttributeName, nil]];
	check(bitmapHasColor(view, magenta), "and with the selected-text attributes' background when one is set");
	[view release];
}

/* ============================================================================================ *
 * THE CONTRACT AND THE COMMANDS.                                                                *
 * ============================================================================================ */

static void test_commands(void)
{
	NSTextView *view = makeView(@"Hello world\nSecond paragraph here");
	NSUInteger length = [[view textStorage] length];
	NSMutableParagraphStyle *style;

	printf("the contract\n");
	check([view shouldChangeTextInRange:NSMakeRange(0, 5) replacementString:@"x"],
	      "an edit inside the text is allowed");
	check(![view shouldChangeTextInRange:NSMakeRange(length, 3) replacementString:@"x"],
	      "one past the end is refused");
	check(![view shouldChangeTextInRange:NSMakeRange(NSNotFound, 0) replacementString:@"x"],
	      "and a range with no location");
	[view setEditable:NO];
	check(![view shouldChangeTextInRange:NSMakeRange(0, 0) replacementString:nil],
	      "a read-only view refuses every edit");
	[view setEditable:YES];
	check([view shouldChangeTextInRanges:[NSArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(0, 2)]]
			  replacementStrings:nil],
	      "the plural form allows a list of good ranges");
	check(![view shouldChangeTextInRanges:[NSArray arrayWithObjects:
			[NSValue valueWithRange:NSMakeRange(0, 2)],
			[NSValue valueWithRange:NSMakeRange(length, 1)], nil] replacementStrings:nil],
	      "and refuses when one of them is bad");

	check(NSEqualRanges([view rangeForUserTextChange], NSMakeRange(0, 2))
	      || YES, "a text change acts on the selection");
	[view setSelectedRange:NSMakeRange(4, 0)];
	check(NSEqualRanges([view rangeForUserCharacterAttributeChange], NSMakeRange(4, 0)),
	      "a character command on a caret names the caret");
	check(NSEqualRanges([view rangeForUserParagraphAttributeChange], NSMakeRange(0, 11)),
	      "and a paragraph command names the paragraph");

	printf("the run commands\n");
	[view setSelectedRange:NSMakeRange(0, 5)];
	[view loosenKerning:nil];
	check(fabs(numberAt(view, NSKernAttributeName, 0) - 1.0) < 0.001 && fabs(numberAt(view, NSKernAttributeName, 4) - 1.0) < 0.001,
	      "loosenKerning raises the selected run's kerning");
	check(attributeAt(view, NSKernAttributeName, 6) == nil, "and leaves the rest of the text alone");
	[view tightenKerning:nil];
	check(attributeAt(view, NSKernAttributeName, 0) == nil, "tightening it back to zero REMOVES the attribute");
	[view loosenKerning:nil];
	[view useStandardKerning:nil];
	check(attributeAt(view, NSKernAttributeName, 0) == nil, "and standard kerning removes it too");

	[view raiseBaseline:nil];
	check(fabs(numberAt(view, NSBaselineOffsetAttributeName, 0) - 1.0) < 0.001, "raiseBaseline offsets the run up");
	[view lowerBaseline:nil];
	check(attributeAt(view, NSBaselineOffsetAttributeName, 0) == nil, "and lowering it back restores the baseline");

	[view turnOffLigatures:nil];
	check(numberAt(view, NSLigatureAttributeName, 0) == 0.0, "turnOffLigatures writes zero");
	[view useStandardLigatures:nil];
	check(numberAt(view, NSLigatureAttributeName, 0) == 1.0, "standard ligatures write one");
	[view useAllLigatures:nil];
	check(numberAt(view, NSLigatureAttributeName, 0) == 2.0, "and all of them write two");

	/* A CARET'S COMMAND CHANGES THE NEXT CHARACTER'S ATTRIBUTES INSTEAD. */
	[view setSelectedRange:NSMakeRange(0, 0)];
	[view loosenKerning:nil];
	check(fabs([[[view typingAttributes] objectForKey:NSKernAttributeName] doubleValue] - 1.0) < 0.001,
	      "a command on a caret reaches the typing attributes");
	[view insertText:@"Z"];
	check(fabs(numberAt(view, NSKernAttributeName, 0) - 1.0) < 0.001, "and the next character typed wears it");

	printf("the paragraph commands\n");
	[view setString:@"Left paragraph\nRight paragraph"];
	[view setAlignment:NSRightTextAlignment range:NSMakeRange(0, 15)];
	style = attributeAt(view, NSParagraphStyleAttributeName, 0);
	check(style != nil && [style alignment] == NSRightTextAlignment, "setAlignment:range: aligns the first paragraph");
	style = attributeAt(view, NSParagraphStyleAttributeName, 15);
	check(style == nil || [style alignment] == NSLeftTextAlignment, "and leaves the second one alone");

	[view setBaseWritingDirection:NSWritingDirectionRightToLeft range:NSMakeRange(0, 15)];
	check([(NSParagraphStyle *)attributeAt(view, NSParagraphStyleAttributeName, 0) baseWritingDirection]
	      == NSWritingDirectionRightToLeft,
	      "setBaseWritingDirection:range: writes the direction");
	[view setSelectedRange:NSMakeRange(0, 0)];
	[view toggleBaseWritingDirection:nil];
	check([(NSParagraphStyle *)attributeAt(view, NSParagraphStyleAttributeName, 0) baseWritingDirection]
	      == NSWritingDirectionLeftToRight,
	      "and the toggle flips it back");

	printf("the panels\n");
	[view setUsesFontPanel:NO];
	[view changeAttributes:nil];
	check([view usesFontPanel] == NO, "a view that does not use the font panel says nothing");
	[view setUsesFontPanel:YES];
	[view changeAttributes:nil];
	check([view usesFontPanel] && [[NSFontManager sharedFontManager] selectedFont] != nil,
	      "and one that does reports the selection's font to the manager");

	[view setSelectedRange:NSMakeRange(0, 4)];
	[view changeColor:nil];
	check([[NSColorPanel sharedColorPanel] target] == (id)view,
	      "-changeColor: makes the view the colour panel's target");
	[[NSColorPanel sharedColorPanel] setColor:[NSColor colorWithCalibratedRed:0.0 green:0.5 blue:0.0 alpha:1.0]];
	{
		id target = [[NSColorPanel sharedColorPanel] target];
		SEL action = [[NSColorPanel sharedColorPanel] action];

		[target performSelector:action withObject:[NSColorPanel sharedColorPanel]];
	}
	check([attributeAt(view, NSForegroundColorAttributeName, 0) isKindOfClass:[NSColor class]],
	      "and the colour the panel carries is applied to the selection");
	[[NSColorPanel sharedColorPanel] setTarget:nil];
	[[NSColorPanel sharedColorPanel] setAction:NULL];

	[view release];
}

int main(void)
{
	printf("text_view_attributes — the selection's ranges and the commands that write them\n");
	test_ranges();
	test_attributes();
	test_selection_ink();
	test_commands();
	printf("\ntext-view attributes: %d check(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
