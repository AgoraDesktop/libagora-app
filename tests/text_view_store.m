/*
 * text_view_store.m — THE TEXT VIEW READS THE STORE THROUGH THE MANAGER.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THIS IS THE SLICE WHERE THE VIEW'S OWN LAYOUT GOES AWAY.** `NSTextView` used to hold a plain `NSMutableString` and
 * a `malloc`'d array of visual lines it computed itself; now it owns an `NSTextStorage`, an `NSLayoutManager` and an
 * `NSTextContainer`, `-string` is the STORE's string, and every layout question — a visual line's range, a caret's x,
 * a point's index, the ink — is forwarded to the manager. THE PROBE CHECKS BOTH ENDS OF EVERY WIRE: the view's line
 * count is the manager's fragment count, a run put in the store is DRAWN, an edit in the view reaches the store, and a
 * direct store edit reaches the view's string through the mirror.
 *
 * **AND THE RUN INHERITANCE IS THE RICH-TEXT HALF.** Typing where a coloured run ends inherits that run, which is what
 * makes an editor of runs rather than an editor of plain text with a coloured wrapper.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGContext.h>
#include <math.h>
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

static int has_red(NSBitmapImageRep *rep)
{
	int x, y;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4) {
				return 1;
			}
		}
	}
	return 0;
}

/* THE VIEW IS ENTERED THE WAY A SUPERVIEW WOULD — it is FLIPPED and this rep's context is not. */
static NSBitmapImageRep *draw(NSTextView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
	NSGraphicsContext *ctx;
	CGContextRef cg;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	cg = (CGContextRef)[ctx graphicsPort];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
	CGContextScaleCTM(cg, 1.0, -1.0);
	[view drawRect:[view bounds]];
	return rep;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE TRIO IS THE VIEW'S, AND `-string` IS THE STORE'S.** */
	{
		check([view textStorage] != nil && [view layoutManager] != nil && [view textContainer] != nil,
		      "a text view owns an NSTextStorage, an NSLayoutManager and an NSTextContainer");
		[view setString:@"abcd"];
		check([[view string] isEqualToString:@"abcd"], "`-string` answers what was set");
		check([[[view textStorage] string] isEqualToString:@"abcd"],
		      "and the STORE holds the same characters — the view's string IS the store's");
	}

	/* 2. **AND A DIRECT EDIT TO THE STORE REACHES THE VIEW'S STRING**, through the notification mirror. */
	{
		[[view textStorage] replaceCharactersInRange:NSMakeRange(4, 0) withString:@"e"];
		check([[view string] isEqualToString:@"abcde"], "a direct store edit is mirrored into the view's string");
	}

	/* 3. **AND AN EDIT IN THE VIEW REACHES THE STORE**, which is the other direction of the same wire. */
	{
		[view setSelectedRange:NSMakeRange(5, 0)];
		[view insertText:@"f"];
		check([[[view textStorage] string] isEqualToString:@"abcdef"], "typing edits the STORE");
	}

	/* 4. **AND THE LAYOUT IS THE MANAGER'S, NOT A SECOND COPY.** The view's visual line count IS the manager's
	 * fragment count for the view's own container, and narrowing the view changes both together. */
	{
		NSUInteger before = [view cg_visualLineCount];
		NSUInteger managerBefore = [[view layoutManager] cg_lineFragmentCountForTextContainer:[view textContainer]];

		check(before == managerBefore, "the view's visual line count IS the manager's fragment count");
		[view setString:@"aaaa bbbb cccc dddd eeee"];
		[view setFrameSize:NSMakeSize((CGFloat)W, (CGFloat)H)];
		check([view cg_visualLineCount]
		      == [[view layoutManager] cg_lineFragmentCountForTextContainer:[view textContainer]],
		      "and it stays the manager's count after a re-wrap");
	}

	/* 5. **AND A RUN PUT IN THE STORE IS THE INK THE VIEW DRAWS.** A red foreground over the whole store has to reach
	 * the view's pixels, which is what "reads the store through the manager" means at the drawing end. */
	{
		NSBitmapImageRep *plain;
		NSBitmapImageRep *red;

		[view setVerticallyResizable:NO];
		[view setFrameSize:NSMakeSize((CGFloat)W, (CGFloat)H)];
		[view setString:@"abcd"];
		plain = draw(view);
		check(!has_red(plain), "with no run the view draws the control's own ink");
		[plain release];
		[[view textStorage] addAttribute:NSForegroundColorAttributeName value:[NSColor redColor]
					   range:NSMakeRange(0, [[[view textStorage] string] length])];
		red = draw(view);
		check(has_red(red), "and a RED run in the store is the colour the VIEW draws — runs inherit");
		[red release];
	}

	/* 6. **AND TYPING INHERITS THE RUN AT THE INSERTION POINT.** With a red run over `abc`, a character typed at its
	 * end is red too, which is what makes the editor an editor of RUNS. */
	{
		NSRange effective = NSMakeRange(0, 0);
		NSDictionary *attrs;

		[view setString:@"abc"];
		[[view textStorage] addAttribute:NSForegroundColorAttributeName value:[NSColor redColor]
					   range:NSMakeRange(0, 3)];
		[view setSelectedRange:NSMakeRange(3, 0)];
		[view insertText:@"X"];
		attrs = [[view textStorage] attributesAtIndex:3 longestEffectiveRange:&effective inRange:NSMakeRange(0, 4)];
		check([[view string] isEqualToString:@"abcX"], "the typed character lands after the run");
		check([attrs objectForKey:NSForegroundColorAttributeName] == [NSColor redColor],
		      "and INHERITS the colour of the run it was typed into");
	}

	[view release];
	[pool release];
	printf("text_view_store: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
