/*
 * responder_commands — the era's command set: every door forwards, and the page keys land in a text view.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A COMMAND IS A SELECTOR A KEY BINDING NAMES AND A CHAIN DELIVERS.** Two claims follow from that sentence and this
 * probe measures both, because either one alone is a declaration rather than a behaviour:
 *
 *   1. THE BASE FORWARDS ALL OF THEM. `NSResponder` declares the whole 10.6 command set now — the movement families,
 *      the paragraph set, paging and scrolling, the mark and kill ring, the case and direction families — and each body
 *      is one `-nextResponder` send. The recorder below registers a single C function for all fifty-seven selectors and
 *      records `_cmd`, so the assertion is "the message ARRIVED at the end of the chain", not "the method exists".
 *   2. AND THE ONES `NSTextView` ANSWERS DO SOMETHING. Page Down moves the insertion point a VIEWPORT and scrolls to
 *      it; Page Up comes back; Shift extends; the scroll commands move the viewport and leave the caret alone; the
 *      paragraph pair crosses a WRAP (a paragraph is a newline-terminated run, not a visual line); the unit selections
 *      are the granularity door; the direction commands set the paragraph style.
 *
 * AND THE KEYS THEMSELVES ARE DRIVEN, not just the selectors: `NSTextInputContext` maps Page Up/Down and Option-Up/Down
 * to these commands, so a KEY DOWN EVENT through the view's own key handling has to reach them. That mapping said "a
 * page is a viewport's height and this tier has no viewport" for three slices after the clip view arrived; the last
 * section is what holds the correction.
 */
#import <AppKit/NSResponder.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSParagraphStyle.h>
#import <Foundation/Foundation.h>

#include <objc/runtime.h>
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

/* ============================================================================================ *
 * THE RECORDER: ONE IMP FOR FIFTY-SEVEN SELECTORS.                                             *
 *                                                                                              *
 * `class_addMethod` takes the selector as the IMP's `_cmd`, so a single function records every  *
 * command that arrives — which is the only way to assert fifty-seven forwarders without writing *
 * fifty-seven stubs that could each be wrong in the same way as the thing they test.            *
 * ============================================================================================ */
@interface AGCommandRecorder : NSResponder
{
@public
	SEL last;
	int count;
}
@end

static void fn_record(id self, SEL _cmd, id sender)
{
	AGCommandRecorder *recorder = (AGCommandRecorder *)self;

	(void)sender;
	recorder->last = _cmd;
	recorder->count++;
}

@implementation AGCommandRecorder
@end

/* THE FIFTY-SEVEN, IN THE ORDER THE HEADER DECLARES THEM. */
static const char *s_commands[] = {
	"moveBackward:", "moveBackwardAndModifySelection:", "moveForward:", "moveForwardAndModifySelection:",
	"moveWordBackward:", "moveWordBackwardAndModifySelection:", "moveWordForward:",
	"moveWordForwardAndModifySelection:",
	"moveToLeftEndOfLine:", "moveToLeftEndOfLineAndModifySelection:", "moveToRightEndOfLine:",
	"moveToRightEndOfLineAndModifySelection:",
	"moveToBeginningOfParagraph:", "moveToEndOfParagraph:", "moveToBeginningOfParagraphAndModifySelection:",
	"moveToEndOfParagraphAndModifySelection:", "moveParagraphBackwardAndModifySelection:",
	"moveParagraphForwardAndModifySelection:", "deleteToBeginningOfParagraph:", "deleteToEndOfParagraph:",
	"selectWord:", "selectLine:", "selectParagraph:",
	"pageUp:", "pageDown:", "pageUpAndModifySelection:", "pageDownAndModifySelection:",
	"scrollPageUp:", "scrollPageDown:", "scrollLineUp:", "scrollLineDown:", "scrollToBeginningOfDocument:",
	"scrollToEndOfDocument:", "centerSelectionInVisibleArea:",
	"setMark:", "selectToMark:", "deleteToMark:", "swapWithMark:", "yank:",
	"capitalizeWord:", "lowercaseWord:", "uppercaseWord:", "changeCaseOfLetter:", "transposeWords:",
	"makeBaseWritingDirectionLeftToRight:", "makeBaseWritingDirectionRightToLeft:",
	"makeBaseWritingDirectionNatural:", "makeTextWritingDirectionLeftToRight:",
	"makeTextWritingDirectionRightToLeft:", "makeTextWritingDirectionNatural:",
	"indent:", "complete:", "insertLineBreak:", "insertContainerBreak:",
	"insertSingleQuoteIgnoringSubstitution:", "insertDoubleQuoteIgnoringSubstitution:",
	"deleteBackwardByDecomposingPreviousCharacter:",
	NULL
};

static NSEvent *key(NSString *characters, NSUInteger flags)
{
	return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags
			       timestamp:0.0 windowNumber:0 context:nil
			      characters:characters charactersIgnoringModifiers:characters
			       isARepeat:NO keyCode:0];
}

/* A DOCUMENT OF `n` SHORT LINES, none of which wraps at the width below. */
static NSString *lines(NSUInteger n)
{
	NSMutableString *s = [NSMutableString string];

	while (n-- > 0) {
		[s appendFormat:@"line %lu\n", (unsigned long)n];
	}
	return s;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AGCommandRecorder *recorder = [[AGCommandRecorder alloc] init];
	NSResponder *head = [[NSResponder alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* ============================================================================================ *
	 * 1. EVERY DOOR FORWARDS, AND THE RECORDER HEARS ALL FIFTY-SEVEN.                               *
	 * ============================================================================================ */
	{
		int i, declared = 0, arrived = 0;

		[head setNextResponder:recorder];
		for (i = 0; s_commands[i] != NULL; i++) {
			class_addMethod([AGCommandRecorder class], sel_registerName(s_commands[i]),
					(IMP)fn_record, "v@:@");
		}
		for (i = 0; s_commands[i] != NULL; i++) {
			SEL command = sel_registerName(s_commands[i]);

			declared++;
			recorder->last = NULL;
			[head performSelector:command withObject:nil];
			if (recorder->last != NULL && strcmp(sel_getName(recorder->last), s_commands[i]) == 0) {
				arrived++;
			} else {
				printf("  (note: %s did not arrive — last was %s)\n", s_commands[i],
				       (recorder->last != NULL) ? sel_getName(recorder->last) : "(nothing)");
			}
		}
		printf("  (note: %d command(s) declared, %d forwarded to the end of the chain)\n", declared, arrived);
		check(declared == 57, "the era's command set is fifty-seven selectors");
		check(arrived == declared, "and EVERY one of them reaches the end of the responder chain");

		/* THE NEGATIVE: a command nobody implements anywhere stops at the chain's end rather than arriving. */
		recorder->count = 0;
		check(![head respondsToSelector:@selector(doesNotExistAnywhere:)], "a selector nobody declares is not answered");
		check(recorder->count == 0, "and nothing was sent for it");
	}

	/* ============================================================================================ *
	 * 2. THE PAGE KEYS AND THE COMMANDS THEY NAME, IN A REAL SCROLL VIEW.                            *
	 * ============================================================================================ */
	{
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 90.0)];
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 90.0)];
		NSClipView *clip;
		CGFloat lineHeight;
		NSInteger pageLines;

		[scroll setDocumentView:view];
		clip = (NSClipView *)[scroll contentView];
		[view setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
		[view setEditable:YES];
		[view setString:lines(60)];
		[view setSelectedRange:NSMakeRange(0, 0)];
		lineHeight = [NSFont systemFontOfSize:[NSFont systemFontSize]].ascender
			   - [NSFont systemFontOfSize:[NSFont systemFontSize]].descender;
		pageLines = (NSInteger)(NSHeight([clip bounds]) / lineHeight);
		printf("  (note: a %.0f-point clip view holds %ld line(s) of %.1f points)\n",
		       (double)NSHeight([clip bounds]), (long)pageLines, (double)lineHeight);
		check(pageLines >= 2, "there is more than one line to a page, so a page is worth measuring");

		/* PAGE DOWN: the caret goes a page down and the view follows it. */
		{
			NSUInteger before = [view selectedRange].location;

			[view pageDown:nil];
			check([view selectedRange].location > before, "`-pageDown:` moves the insertion point DOWN");
			check([view cg_visualLineIndexForCharacterIndex:[view selectedRange].location] >= (NSUInteger)pageLines - 1,
			      "by about a viewport's worth of lines");
			check(NSMinY([clip bounds]) > 0.0, "and the clip view scrolled to follow it");
		}

		/* PAGE UP COMES BACK TO THE TOP, AND THE CLAMP HOLDS AT EITHER END. */
		[view pageUp:nil];
		check([view selectedRange].location == 0, "`-pageUp:` comes back to the beginning");
		[view pageUp:nil];
		check([view selectedRange].location == 0, "and a page up at the top stays there rather than wrapping");

		/* SHIFT-PAGE DOWN EXTENDS, WHICH IS THE SAME MOVE WITH THE OTHER END PINNED. */
		[view setSelectedRange:NSMakeRange(0, 0)];
		[view pageDownAndModifySelection:nil];
		check([view selectedRange].location == 0 && [view selectedRange].length > 0,
		      "`-pageDownAndModifySelection:` extends the selection from where it started");
		check([view selectedRange].length >= (NSUInteger)pageLines * 2,
		      "and its length is a page's worth of characters");

		/* A SCROLL COMMAND MOVES THE VIEWPORT AND NOT THE CARET, which is the whole difference. */
		{
			NSUInteger caret;
			CGFloat origin;

			[view setSelectedRange:NSMakeRange(0, 0)];
			[view scrollPageDown:nil];
			origin = NSMinY([clip bounds]);
			caret = [view selectedRange].location;
			printf("  (note: after scrollPageDown the clip origin is %.1f and the caret is at %lu)\n",
			       (double)origin, (unsigned long)caret);
			check(origin > 0.0, "`-scrollPageDown:` scrolls the viewport");
			check(caret == 0, "and leaves the insertion point alone");
		}
		[view scrollToBeginningOfDocument:nil];
		check(NSMinY([clip bounds]) == 0.0, "`-scrollToBeginningOfDocument:` puts the viewport back at the top");
		[view scrollToEndOfDocument:nil];
		check(NSMinY([clip bounds]) > 0.0, "and `-scrollToEndOfDocument:` takes it to the bottom");
		[view scrollLineDown:nil];
		{
			CGFloat afterScroll = NSMinY([clip bounds]);

			[view scrollLineUp:nil];
			check(NSMinY([clip bounds]) < afterScroll, "a line scroll moves the viewport by a line");
		}

		/* AND CENTRING A LINE IS A SCROLL BY ARITHMETIC: the caret's midpoint ends up in the middle. */
		[view setSelectedRange:NSMakeRange([[view string] length] / 2, 0)];
		[view centerSelectionInVisibleArea:nil];
		{
			/* **THE CARET'S SCREEN RECT, CONVERTED BACK INTO THE VIEW** — `-firstRectForCharacterRange:` answers in
			 * screen coordinates, so the two subtractions below are the inverse of what it added. `-visibleRect` is
			 * the clip view's document rectangle in the VIEW's own coordinates, which is what the middle is measured
			 * against. */
			NSRect caret = [view firstRectForCharacterRange:[view selectedRange]];
			NSRect frame = [[view window] frame];
			NSPoint inWindow = NSMakePoint(caret.origin.x - frame.origin.x, caret.origin.y - frame.origin.y);
			NSPoint local = [view convertPoint:inWindow fromView:nil];
			CGFloat middle = NSMidY([view visibleRect]);

			printf("  (note: the caret is at view y %.1f and the visible rect's middle is %.1f)\n",
			       (double)local.y, (double)middle);
			check(fabs((double)(local.y - middle)) < (double)lineHeight,
			      "`-centerSelectionInVisibleArea:` puts the caret's line in the middle of the viewport");
		}

		/* AND THE KEY ITSELF: Page Down through the view's own key handling reaches the command. */
		[view scrollToBeginningOfDocument:nil];
		[view setSelectedRange:NSMakeRange(0, 0)];
		{
			NSUInteger before = [view selectedRange].location;

			[view keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSPageDownFunctionKey], 0)];
			printf("  (note: a Page Down KEY moved the caret from %lu to %lu)\n",
			       (unsigned long)before, (unsigned long)[view selectedRange].location);
			check([view selectedRange].location > before,
			      "a PAGE DOWN KEY reaches `-pageDown:` through the input context's binding");
		}

		/* AND OPTION-DOWN IS THE PARAGRAPH'S END, WHICH IS THE OTHER NEW BINDING. */
		{
			NSRange paragraph;

			[view setString:@"first paragraph\nsecond paragraph\n"];
			[view setSelectedRange:NSMakeRange(0, 0)];
			paragraph = [view cg_characterRangeOfLine:0];
			[view keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey], NSAlternateKeyMask)];
			check([view selectedRange].location == paragraph.location + paragraph.length,
			      "OPTION-DOWN goes to the end of the paragraph, through the binding and the chain");
			[view keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey], NSAlternateKeyMask)];
			check([view selectedRange].location == 0, "and OPTION-UP comes back to its beginning");
		}

		/* ============================================================================================ *
		 * 3. THE PARAGRAPH IS THE MODEL LINE, AND THAT IS THE POINT OF THE PAIR.                        *
		 * ============================================================================================ */
		{
			NSRange paragraph;

			/* A PARAGRAPH WIDER THAN THE VIEW, so its end is a WRAP away from its beginning. */
			[view setString:@"this paragraph is deliberately much longer than the width of the view so that it wraps "
				 @"over more than one visual line and its end is not where the second line begins\nsecond\n"];
			[view setSelectedRange:NSMakeRange(0, 0)];
			paragraph = [view cg_characterRangeOfLine:0];
			printf("  (note: paragraph 0 is (%lu, %lu) and the view makes %lu visual line(s) of it)\n",
			       (unsigned long)paragraph.location, (unsigned long)paragraph.length,
			       (unsigned long)[view cg_visualLineCount]);
			check(paragraph.length > 60, "the first paragraph is a long run");
			check([view cg_visualLineCount] > 2, "and it wraps over more than one visual line");
			[view moveToEndOfParagraph:nil];
			check([view selectedRange].location == paragraph.location + paragraph.length,
			      "`-moveToEndOfParagraph:` crosses the wraps to the newline");
			[view moveToBeginningOfParagraph:nil];
			check([view selectedRange].location == paragraph.location,
			      "and `-moveToBeginningOfParagraph:` comes back to the paragraph's first character");
			[view setSelectedRange:NSMakeRange(3, 0)];
			[view moveParagraphForwardAndModifySelection:nil];
			/* FROM THE CARET TO THE PARAGRAPH'S END, which is the double-click-and-drag shape: the anchor is where
			 * the selection started, so the range begins there and not at the paragraph's first character. */
			check([view selectedRange].location == 3
			      && [view selectedRange].length == paragraph.location + paragraph.length - 3,
			      "`-moveParagraphForwardAndModifySelection:` extends FROM THE CARET to the paragraph's end");
		}

		/* ============================================================================================ *
		 * 4. THE UNIT SELECTIONS AND THE TWO PARAGRAPH DELETIONS.                                       *
		 * ============================================================================================ */
		{
			[view setString:@"alpha beta gamma\nsecond line\n"];
			[view setSelectedRange:NSMakeRange(6, 0)];
			[view selectWord:nil];
			check([view selectedRange].location == 6 && [view selectedRange].length == 4,
			      "`-selectWord:` grows the caret to the word around it");
			[view setSelectedRange:NSMakeRange(6, 0)];
			[view selectParagraph:nil];
			check([view selectedRange].location == 0 && [view selectedRange].length == 16,
			      "`-selectParagraph:` grows it to the whole model line");

			/* THE DELETIONS GO THROUGH THE EDIT PATH, so they are undoable and the delegate is asked. */
			[view setString:@"one two three\nnext\n"];
			[view setSelectedRange:NSMakeRange(7, 0)];
			[view deleteToBeginningOfParagraph:nil];
			/* THE CARET SITS ON THE SPACE BEFORE `three`, so the space goes with the deleted run — which is what
			 * "back to the paragraph's beginning" means. */
			check([[view string] isEqualToString:@" three\nnext\n"],
			      "`-deleteToBeginningOfParagraph:` removes back to the paragraph's start");
			[view setString:@"one two three\nnext\n"];
			[view setSelectedRange:NSMakeRange(7, 0)];
			[view deleteToEndOfParagraph:nil];
			check([[view string] isEqualToString:@"one two\nnext\n"],
			      "`-deleteToEndOfParagraph:` removes forward to the newline and no further");
		}

		/* ============================================================================================ *
		 * 5. THE DIRECTION COMMANDS SET THE PARAGRAPH STYLE, AND THE UNANSWERED ONES DO NOTHING.         *
		 * ============================================================================================ */
		{
			id style;
			int textDirection;

			[view setString:@"direction\n"];
			[view setSelectedRange:NSMakeRange(0, 0)];
			[view makeBaseWritingDirectionRightToLeft:nil];
			style = [[[view textStorage] attributesAtIndex:0 effectiveRange:NULL]
					objectForKey:NSParagraphStyleAttributeName];
			check(style != nil && [style baseWritingDirection] == NSWritingDirectionRightToLeft,
			      "`-makeBaseWritingDirectionRightToLeft:` sets the paragraph's base direction");
			[view makeBaseWritingDirectionNatural:nil];
			style = [[[view textStorage] attributesAtIndex:0 effectiveRange:NULL]
					objectForKey:NSParagraphStyleAttributeName];
			check(style != nil && [style baseWritingDirection] == NSWritingDirectionNatural,
			      "and `-makeBaseWritingDirectionNatural:` puts it back to natural");

			/* THE ONES NOBODY ANSWERS: forwarded, silent, and no crash — the base class's whole contract. */
			textDirection = (int)[[view string] length];
			[view makeTextWritingDirectionRightToLeft:nil];
			[view yank:nil];
			[view complete:nil];
			[view insertLineBreak:nil];
			check((int)[[view string] length] == textDirection,
			      "a command no view answers changes nothing and does not crash");
		}

		/* AND A TEXT VIEW WITH NO SCROLL VIEW ANSWERS NO PAGE — it forwards, which is silent. */
		{
			NSTextView *lonely = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 90.0)];

			[lonely setString:@"no viewport here\n"];
			[lonely setSelectedRange:NSMakeRange(0, 0)];
			[lonely pageDown:nil];
			check([lonely selectedRange].location == 0,
			      "a text view with no enclosing scroll view has no page to move by");
			[lonely release];
		}

		[scroll release];
	}

	[head release];
	[recorder release];
	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
