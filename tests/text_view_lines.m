/*
 * text_view_lines.m — A TEXT VIEW: THE LINE MODEL, AND EVERYTHING THAT READS IT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A LINE IS A `\n`-TERMINATED RUN, SO EVERY CLAIM HERE IS A CLAIM ABOUT WHERE THINGS LAND.** The line model is
 * checked as arithmetic (counts and ranges, including the two edges a naive split gets wrong: a trailing newline is an
 * EMPTY last line, and an empty string is ONE line); the layout is checked as PIXELS (two lines write ink in two
 * bands, not one); and the behaviour a person drives is checked as KEYS and CLICKS, because the whole point of this
 * class is that the keys a one-line field refuses — Return, Tab, Up, Down — do something here.
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

#define W 200
#define H 60

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int range_is(NSRange r, NSUInteger where, NSUInteger length)
{
	return r.location == where && r.length == length;
}

static NSEvent *key(NSString *characters, NSUInteger flags)
{
	return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags
			       timestamp:0.0 windowNumber:0 context:nil
			      characters:characters charactersIgnoringModifiers:characters
			       isARepeat:NO keyCode:0];
}

static NSBitmapImageRep *draw(NSTextView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[view drawRect:[view bounds]];
	return rep;
}

static int ink_in(NSBitmapImageRep *rep, int y0, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = 0; x < W; x++) {
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
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
	/* **THE WINDOW OUTLIVES EVERY CASE, WHICH IS NOT TIDINESS.** A view's `-window` is a BORROWED pointer and a window
	 * releases its content view's back-reference when it goes, so a probe that released the window and then kept using
	 * the view would be sending `-setViewsNeedDisplay:` to freed memory the next time the view marked itself dirty —
	 * MEASURED, a segfault in the case AFTER the click. The window is made once and released at the end. */
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];

	setvbuf(stdout, NULL, _IONBF, 0);
	[window setContentView:view];

	/* 1. **THE LINE MODEL ITSELF, INCLUDING THE TWO EDGES A SPLIT GETS WRONG.** */
	[view setString:@"one\ntwo\nthree"];
	check([view cg_lineCount] == 3, "`one\\ntwo\\nthree` is three lines");
	check(range_is([view cg_characterRangeOfLine:0], 0, 3), "the first line is `one`, with no newline in its range");
	check(range_is([view cg_characterRangeOfLine:1], 4, 3), "the second is `two`");
	check(range_is([view cg_characterRangeOfLine:2], 8, 5), "and the third `three`");
	printf("  (note: line of index 3 is %lu, of 4 is %lu, of 8 is %lu)\n",
	       (unsigned long)[view cg_lineIndexForCharacterIndex:3],
	       (unsigned long)[view cg_lineIndexForCharacterIndex:4],
	       (unsigned long)[view cg_lineIndexForCharacterIndex:8]);
	check([view cg_lineIndexForCharacterIndex:3] == 0,
	      "the index AT a break is still the line the break ENDS");
	check([view cg_lineIndexForCharacterIndex:4] == 1, "and one past it is the next line's first character");

	[view setString:@"a\n"];
	check([view cg_lineCount] == 2 && range_is([view cg_characterRangeOfLine:1], 2, 0),
	      "a TRAILING newline is an empty last line");
	[view setString:@""];
	check([view cg_lineCount] == 1 && range_is([view cg_characterRangeOfLine:0], 0, 0),
	      "and an EMPTY string is one empty line, not none");

	/* 2. **AND THE KEYS A ONE-LINE FIELD REFUSES DO SOMETHING HERE.** Return puts a break in, Tab puts a tab in, and
	 * typing continues on the line the caret is on. */
	[view setString:@""];
	[view insertText:@"a"];
	[view insertNewline:nil];
	[view insertText:@"b"];
	check([[view string] isEqualToString:@"a\nb"], "Return INSERTS a break here, where a field ends its session");
	check([view cg_lineCount] == 2, "so the view is two lines");
	check(range_is([view selectedRange], 3, 0), "and the caret is after what was typed, on the second line");
	[view insertTab:nil];
	check([[view string] isEqualToString:@"a\nb\t"], "and Tab inserts a tab, where a field moves the focus");

	/* **AND THE BASE'S REFUSAL IS GONE**: `NSText` drops a newline on the floor and says so; this class accepts one. */
	[view setString:@""];
	[view insertText:@"one\ntwo"];
	check([[view string] isEqualToString:@"one\ntwo"] && [view cg_lineCount] == 2,
	      "a multi-line string typed at once KEEPS its break — the base refuses one");

	/* 3. **AND THE LINE COMMANDS MEAN THE CARET'S OWN LINE, WHERE A FIELD HAD ONLY ONE.** */
	[view setString:@"one\ntwo"];
	[view setSelectedRange:NSMakeRange(6, 0)];	/* inside `two` */
	[view moveToBeginningOfLine:nil];
	check(range_is([view selectedRange], 4, 0), "`-moveToBeginningOfLine:` goes to the start of the CARET's line");
	[view moveToEndOfLine:nil];
	check(range_is([view selectedRange], 7, 0), "and `-moveToEndOfLine:` to its end, not the document's");
	[view setSelectedRange:NSMakeRange(2, 0)];	/* the end of `one` */
	[view moveRight:nil];
	check(range_is([view selectedRange], 3, 0), "a plain Right steps across the BREAK one character at a time");

	/* 4. **AND THE VERTICAL PAIR, WHICH IS WHAT A LINE MODEL EXISTS FOR.** The line is read back from the caret's own
	 * index, so a movement that landed on the wrong line cannot pass by turning up in the right column. */
	[view moveDown:nil];
	check([view cg_lineIndexForCharacterIndex:[view selectedRange].location] == 1,
	      "`-moveDown:` puts the caret on the line below");
	[view moveUp:nil];
	check([view cg_lineIndexForCharacterIndex:[view selectedRange].location] == 0,
	      "and `-moveUp:` on the line above");
	[view setSelectedRange:NSMakeRange(1, 0)];
	[view moveUp:nil];
	check(range_is([view selectedRange], 1, 0), "`-moveUp:` at the FIRST line stays put");
	[view setSelectedRange:NSMakeRange(5, 0)];
	[view moveDown:nil];
	check(range_is([view selectedRange], 5, 0), "and `-moveDown:` at the LAST line does too");

	/* 5. **AND THE TWO DOCUMENT ENDS, WHICH ARE THE STRING'S OWN.** */
	[view moveToEndOfDocument:nil];
	check(range_is([view selectedRange], 7, 0), "`-moveToEndOfDocument:` goes to the end of the string");
	[view moveToBeginningOfDocument:nil];
	check(range_is([view selectedRange], 0, 0), "and `-moveToBeginningOfDocument:` to the start");

	/* 6. **AND THE LAYOUT IS PER LINE, WHICH IS A QUESTION ABOUT PIXELS.** Two lines write ink in TWO bands; one line
	 * writes ink in one. A view that drew the whole string as a single line — the base's behaviour — would put all the
	 * ink in the top band, which is exactly what this pair rules out. */
	{
		NSBitmapImageRep *two;
		int topTwo, bottomTwo;

		[view setString:@"a\nb"];
		two = draw(view);
		topTwo = ink_in(two, 0, H / 2);
		bottomTwo = ink_in(two, H / 2, H);
		printf("  (note: two lines — ink above the middle %d, below it %d)\n", topTwo, bottomTwo);
		check(topTwo > 0 && bottomTwo > 0,
		      "TWO lines write ink in two bands — one above the middle of the view and one below");
		[two release];

		[view setString:@"a"];
		two = draw(view);
		bottomTwo = ink_in(two, H / 2, H);
		printf("  (note: one line — ink below the middle %d)\n", bottomTwo);
		check(bottomTwo == 0, "while ONE line writes nothing below the first band");
		[two release];
	}

	/* 7. **AND A CLICK LANDS ON THE LINE IT IS OVER.** The pointer is put in the second line's band, near its left
	 * edge, and the caret must land in the second line — which is the hit test reading the y rather than always
	 * answering the first line. */
	{
		/* THE SECOND LINE'S BAND, IN THE VIEW'S OWN y-UP COORDINATES: the top line is the highest band, so a point
		 * just below it is in line 1. */
		NSFont *font = [view font];
		CGFloat lineHeight;
		CGFloat y;

		if (font == nil) {
			font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
		}
		lineHeight = [font ascender] - [font descender];
		y = NSMaxY([view bounds]) - NS_TEXT_INSET - lineHeight / 2.0 - lineHeight;
		[view setString:@"one\ntwo"];
		[view mouseDown:[NSEvent mouseEventWithType:NSLeftMouseDown location:NSMakePoint(6.0, y)
						 modifierFlags:0 timestamp:0.0 windowNumber:[window windowNumber]
						     context:nil eventNumber:0 clickCount:1 pressure:1.0f]];
		printf("  (note: a click at y=%.1f landed at index %lu)\n", (double)y,
		       (unsigned long)[view selectedRange].location);
		check([view cg_lineIndexForCharacterIndex:[view selectedRange].location] == 1,
		      "a click in the SECOND line's band puts the caret on the second line");
	}

	/* 8. **AND THE MEASUREMENT IS EVERY LINE'S HEIGHT.** A view sized to three lines is taller than one sized to a
	 * single line — which is what a clip view will read when there is one. */
	{
		CGFloat one;
		CGFloat three;

		[view setString:@"a"];
		[view sizeToFit];
		one = [view frame].size.height;
		[view setString:@"a\nb\nc"];
		[view sizeToFit];
		three = [view frame].size.height;
		printf("  (note: `-sizeToFit` gives one line %.1f points and three lines %.1f)\n", (double)one, (double)three);
		check(one > 0.0 && three > one, "`-sizeToFit` grows with the number of lines");
	}

	[window release];
	[view release];
	[pool release];
	printf("text_view_lines: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
