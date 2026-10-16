/*
 * text_view_wrapping.m — A LINE TOO WIDE FOR THE VIEW BECOMES SEVERAL VISUAL LINES.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE MODEL DID NOT CHANGE AND THE LAYOUT DID, SO BOTH ARE CHECKED.** `cg_lineCount` is still the count of
 * `\n`-terminated runs — a fact about the STRING, unmoved by the view's width — while `cg_visualLineCount` is the count
 * of lines as LAID OUT, which rises as the view narrows. The claim the slice makes is that they are two different
 * questions: the wide view wraps a long paragraph into ONE visual line and the narrow one into several, with the SAME
 * `cg_lineCount` in both.
 *
 * **AND THE PIECES ARE CHECKED WHERE THEY LAND.** The ranges the layout answers must be CONTIGUOUS and cover the
 * string; a resulting line must end on a SPACE (the engine's word-backoff) rather than mid-word; the click's y must
 * pick the visual line it is over; and the ink must be in more than one band only at the narrow width.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSText.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

#define REPW 220
#define REPH 90
#define WIDE 400
#define NARROW 96

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* **A PARAGRAPH LONG ENOUGH TO WRAP AT `NARROW` AND SHORT ENOUGH TO FIT AT `WIDE`**, with spaces at every four
 * characters so the breaker has somewhere to back off to. */
static NSString *paragraph(void)
{
	return @"aaaa bbbb cccc dddd eeee ffff gggg hhhh";
}

static int is_space(unichar c)
{
	return c == ' ' || c == '\t';
}

static void set_frame(NSTextView *view, CGFloat width)
{
	[view setFrameSize:NSMakeSize(width, (CGFloat)REPH)];
}

static void press(NSTextView *view, NSWindow *window, CGFloat x, CGFloat y)
{
	[view mouseDown:[NSEvent mouseEventWithType:NSLeftMouseDown location:NSMakePoint(x, y)
					 modifierFlags:0 timestamp:0.0 windowNumber:[window windowNumber]
					     context:nil eventNumber:0 clickCount:1 pressure:1.0f]];
}

static NSBitmapImageRep *draw(NSTextView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:REPW pixelsHigh:REPH
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:REPW * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)REPW, (CGFloat)REPH)] fill];
	[view drawRect:[view bounds]];
	return rep;
}

static int ink_in(NSBitmapImageRep *rep, int y0, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = 0; x < REPW; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.5) {
				n++;
			}
		}
	}
	return n;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)WIDE, (CGFloat)REPH)];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)WIDE, (CGFloat)REPH)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];

	setvbuf(stdout, NULL, _IONBF, 0);
	[window setContentView:view];

	/* 1. **THE SAME PARAGRAPH IS ONE MODEL LINE EITHER WAY AND MORE THAN ONE VISUAL LINE WHEN NARROW.** That pair is
	 * the whole slice: the model is the string's, the layout is the width's. */
	[view setString:paragraph()];
	set_frame(view, (CGFloat)WIDE);
	check([view cg_lineCount] == 1, "a paragraph with no newline is ONE model line");
	check([view cg_visualLineCount] == 1, "and fits on ONE visual line in a wide view");
	set_frame(view, (CGFloat)NARROW);
	printf("  (note: at width %d the paragraph is %lu visual lines; the model line count is still %lu)\n",
	       NARROW, (unsigned long)[view cg_visualLineCount], (unsigned long)[view cg_lineCount]);
	check([view cg_lineCount] == 1, "the MODEL line count does not move when the view narrows");
	check([view cg_visualLineCount] > 1, "while the VISUAL line count does — the paragraph wraps");

	/* 2. **AND THE RANGES ARE CONTIGUOUS AND COVER THE STRING, WHICH IS WHAT "A LAYOUT" MEANS.** A gap would be text
	 * nobody draws; an overlap would be text drawn twice. */
	{
		NSUInteger i, count = [view cg_visualLineCount];
		NSUInteger n = [[view string] length];
		NSUInteger cursor = 0;

		for (i = 0; i < count; i++) {
			NSRange r = [view cg_visualLineRangeAtIndex:i];

			if (r.location != cursor) {
				break;
			}
			cursor = r.location + r.length;
		}
		printf("  (note: %lu lines cover 0..%lu of a %lu-character string)\n",
		       (unsigned long)count, (unsigned long)cursor, (unsigned long)n);
		check(i == count && cursor == n, "the visual line ranges are contiguous and cover the whole string");
	}

	/* 3. **AND THE LINE THAT WRAPPED ENDED ON A SPACE, NOT IN THE MIDDLE OF A WORD.** The engine backs off to the last
	 * space that fits and keeps it; that is why `-insertText:`'s refusal to break a word is not needed here. */
	{
		NSRange first = [view cg_visualLineRangeAtIndex:0];
		unichar last = [[view string] characterAtIndex:first.location + first.length - 1];

		printf("  (note: the first wrapped line ends on `%c`)\n", (char)last);
		check(is_space(last), "a WORD-WRAPPED line ends on a SPACE — the breaker backed off a boundary");
	}

	/* 4. **AND A HARD BREAK STILL BREAKS, WITH A TRAILING ONE OWING AN EMPTY LAST LINE.** */
	[view setString:@"one\ntwo"];
	set_frame(view, (CGFloat)WIDE);
	check([view cg_lineCount] == 2 && [view cg_visualLineCount] == 2,
	      "an explicit newline is TWO model lines and TWO visual lines in a wide view");
	[view setString:@"one\n"];
	check([view cg_visualLineCount] == 2, "and a TRAILING newline is two visual lines too");
	{
		NSRange last = [view cg_visualLineRangeAtIndex:1];
		NSUInteger n = [[view string] length];

		check(last.location == n && last.length == 0,
		      "the second of which is the EMPTY last line the caret sits on after the break");
	}

	/* 5. **AND THE MOVEMENTS WALK THE VISUAL LINES.** End-of-line from the first wrapped line stops at the line's own
	 * end — mid-string — rather than at the document's; Down moves to the next visual line and Up comes back. */
	[view setString:paragraph()];
	set_frame(view, (CGFloat)NARROW);
	[view setSelectedRange:NSMakeRange(0, 0)];
	[view moveToEndOfLine:nil];
	{
		NSRange first = [view cg_visualLineRangeAtIndex:0];
		NSUInteger end = first.location + first.length;
		NSUInteger caret = [view selectedRange].location;
		NSUInteger n = [[view string] length];

		printf("  (note: End on line 0 puts the caret at %lu of %lu)\n", (unsigned long)caret, (unsigned long)n);
		/* THE LINE'S RANGE KEEPS ITS TRAILING SPACE and the caret goes to the end of what is DRAWN, which is the range
		 * less that space — so "the line's end" is the range's end or one before it, and never the document's. */
		check(caret != n && (caret == end || caret + 1 == end),
		      "`-moveToEndOfLine:` stops at the VISUAL line's end, not the document's");
	}
	[view moveToBeginningOfLine:nil];
	check([view selectedRange].location == 0, "and `-moveToBeginningOfLine:` at the start of the first line");
	{
		NSRange second = [view cg_visualLineRangeAtIndex:1];
		NSUInteger before = [view selectedRange].location;

		[view moveDown:nil];
		printf("  (note: Down from index %lu landed at %lu; line 1 starts at %lu)\n",
		       (unsigned long)before, (unsigned long)[view selectedRange].location, (unsigned long)second.location);
		check([view cg_visualLineIndexForCharacterIndex:[view selectedRange].location] > 0,
		      "`-moveDown:` puts the caret on a LATER visual line");
	}

	/* 6. **AND A CLICK LANDS ON THE VISUAL LINE IT IS OVER.** The pointer is put in the SECOND band's middle, which at
	 * the narrow width is the wrapped remainder of the same paragraph. */
	{
		NSFont *font = [view font];
		CGFloat lineHeight = [font ascender] - [font descender];
		CGFloat y = NSMaxY([view bounds]) - NS_TEXT_INSET - lineHeight / 2.0 - lineHeight;
		NSUInteger index;

		[view setString:paragraph()];
		set_frame(view, (CGFloat)NARROW);
		press(view, window, 6.0, y);
		index = [view selectedRange].location;
		printf("  (note: a click in the second band landed at index %lu)\n", (unsigned long)index);
		check(index > 0, "a click in the SECOND band lands past the first visual line's text");
		check([view cg_visualLineIndexForCharacterIndex:index] == 1,
		      "which is the second visual line — the hit test reads the y");
	}

	/* 7. **AND THE INK IS IN TWO BANDS ONLY WHEN THERE IS A SECOND VISUAL LINE.** The SAME paragraph, drawn at two
	 * widths: wide, everything is in the first band; narrow, the second band has ink. A layout that wrapped but drew
	 * one line would pass the counts and fail this. */
	{
		NSBitmapImageRep *wide;
		NSBitmapImageRep *narrow;

		[view setString:paragraph()];
		set_frame(view, (CGFloat)WIDE);
		wide = draw(view);
		set_frame(view, (CGFloat)NARROW);
		narrow = draw(view);
		printf("  (note: ink in the second band — wide %d, narrow %d)\n",
		       ink_in(wide, REPH / 3, 2 * REPH / 3), ink_in(narrow, REPH / 3, 2 * REPH / 3));
		check(ink_in(wide, 0, REPH / 3) > 0 && ink_in(wide, REPH / 3, REPH) == 0,
		      "at the WIDE width every glyph is in the first band");
		check(ink_in(narrow, REPH / 3, 2 * REPH / 3) > 0,
		      "and at the NARROW one the second band has ink — the wrap is DRAWN, not just counted");
		[wide release];
		[narrow release];
	}

	/* 8. **AND THE HEIGHT IS WHAT THE LAYOUT NEEDS AT THE WIDTH IT HAS.** `-sizeToFit` keeps the width it was given —
	 * a wrapping view that set its own width would re-wrap itself on the next layout — and answers the height. */
	{
		CGFloat wideHeight;
		CGFloat narrowHeight;

		[view setString:paragraph()];
		set_frame(view, (CGFloat)WIDE);
		[view sizeToFit];
		wideHeight = [view frame].size.height;
		set_frame(view, (CGFloat)NARROW);
		[view sizeToFit];
		narrowHeight = [view frame].size.height;
		printf("  (note: `-sizeToFit` gives the wide layout %.1f points high and the narrow one %.1f)\n",
		       (double)wideHeight, (double)narrowHeight);
		check([view frame].size.width == (CGFloat)NARROW,
		      "`-sizeToFit` leaves the WIDTH alone, because the width is the caller's");
		check(narrowHeight > wideHeight, "and the height grows when the same text wraps into more lines");
	}

	[window release];
	[view release];
	[pool release];
	printf("text_view_wrapping: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
