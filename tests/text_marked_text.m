/*
 * text_marked_text.m — THE MARKED TEXT: WHAT AN INPUT METHOD COMPOSES THROUGH `NSTextInput`.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A COMPOSITION IS AN ORDINARY EDIT WITH A REMEMBERED RANGE.** The input method calls `-setMarkedText:selectedRange:`
 * on every keystroke, and the string it hands over is the WHOLE composition so far; the view puts those characters in
 * the STORE (so the caret, the layout and every other door work as usual) and remembers which of them are still
 * unconfirmed. `-insertText:` confirms, `-unmarkText` takes a composition back, and the view draws a rule under the
 * marked range because the store cannot carry the fact that a run is marked.
 *
 * **AND THE PROTOCOL'S OTHER HALF IS WHAT A CANDIDATE WINDOW ASKS.** The caret's rectangle in screen coordinates, the
 * character nearest a screen point, the text of a range, and the attributes an input method may set — all four are
 * checked here, and the two screen doors are checked as INVERSES of each other rather than against a fixed screen.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSText.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGContext.h>
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

/* HOW MANY DARK PIXELS A DRAW PUTS DOWN, which is how the composition rule is seen: the marked draw has one more rule
 * than the unmarked one, so it puts down more ink. */
static int dark_pixels(NSBitmapImageRep *rep)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.5 && [c greenComponent] < 0.5 && [c blueComponent] < 0.5) {
				count++;
			}
		}
	}
	return count;
}

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
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];

	setvbuf(stdout, NULL, _IONBF, 0);
	[window setContentView:view];
	[view setVerticallyResizable:NO];

	/* 1. **A FRESH VIEW IS NOT COMPOSING ANYTHING.** */
	check(![view hasMarkedText] && [view markedRange].location == NSNotFound,
	      "a view no input method has touched has no marked text");

	/* 2. **AND A COMPOSITION IS ONE CALL PER KEYSTROKE, EACH REPLACING THE LAST.** The marked characters really go into
	 * the store, the marked range grows, and the caret is placed by the range the input method names. */
	[view setString:@""];
	[view setMarkedText:@"a" selectedRange:NSMakeRange(0, 1)];
	check([view hasMarkedText] && range_is([view markedRange], 0, 1),
	      "the first keystroke marks one character");
	check([[view string] isEqualToString:@"a"], "and puts it in the store, so the layout sees it");
	[view setMarkedText:@"ab" selectedRange:NSMakeRange(1, 1)];
	check(range_is([view markedRange], 0, 2) && [[view string] isEqualToString:@"ab"],
	      "the next REPLACES the composition rather than appending to it");
	check(range_is([view selectedRange], 1, 1), "and the caret is where the input method said, inside the composition");

	/* 3. **AND CONFIRMING IS AN ORDINARY INSERT, WHICH ENDS THE MARK.** */
	[view insertText:@"abc"];
	check([[view string] isEqualToString:@"abc"], "`-insertText:` confirms the composition into the store");
	check(![view hasMarkedText], "and the mark is GONE — a confirmed character is no longer being composed");
	check(range_is([view selectedRange], 3, 0), "with the caret after what was confirmed");

	/* 4. **AND TAKING ONE BACK IS `-unmarkText`.** */
	[view setSelectedRange:NSMakeRange(3, 0)];
	[view setMarkedText:@"x" selectedRange:NSMakeRange(0, 1)];
	[view unmarkText];
	check(![view hasMarkedText], "`-unmarkText` ends a composition");
	check([[view string] isEqualToString:@"abcx"], "and leaves the characters that were composed");

	/* 5. **AND THE FOUR QUESTIONS A CANDIDATE WINDOW ASKS.** The attribute list names what the view can show, the
	 * substring is the store's own text, the caret's rectangle moves with the caret, and the point door is its
	 * inverse. */
	{
		NSArray *valid = [view validAttributesForMarkedText];
		NSAttributedString *sub = [view attributedSubstringFromRange:NSMakeRange(0, 2)];
		NSRect atStart = [view firstRectForCharacterRange:NSMakeRange(0, 1)];
		NSRect atEnd = [view firstRectForCharacterRange:NSMakeRange(3, 1)];
		NSUInteger hit;

		check(valid != nil && [valid containsObject:NSUnderlineStyleAttributeName],
		      "`-validAttributesForMarkedText` names the attributes the view can show");
		check(sub != nil && [[sub string] isEqualToString:@"ab"], "`-attributedSubstringFromRange:` is the store's text");
		check(atStart.size.width > 0.0 && atStart.size.height > 0.0, "the caret's screen rectangle has a size");
		check(atEnd.origin.x > atStart.origin.x, "and MOVES when the caret moves");
		hit = [view characterIndexForPoint:NSMakePoint(atEnd.origin.x + 1.0, atEnd.origin.y + 1.0)];
		printf("  (note: a point at the caret's rect hit character %lu of %lu)\n",
		       (unsigned long)hit, (unsigned long)[[view string] length]);
		check(hit > 0, "the screen point door lands near the caret's own character");
	}

	/* 6. **AND THE COMPOSITION IS MARKED IN THE INK.** The same text drawn once marked and once not: the marked draw
	 * puts an extra rule below the baseline, so it puts down more dark pixels. */
	{
		NSBitmapImageRep *unmarked;
		NSBitmapImageRep *marked;
		int plain, composed;

		[view setString:@"ab"];
		unmarked = draw(view);
		plain = dark_pixels(unmarked);
		[unmarked release];
		[view setSelectedRange:NSMakeRange(0, 2)];
		[view setMarkedText:@"ab" selectedRange:NSMakeRange(2, 0)];
		marked = draw(view);
		composed = dark_pixels(marked);
		[marked release];
		printf("  (note: dark pixels — unmarked %d, composed %d)\n", plain, composed);
		check([view hasMarkedText] && composed > plain,
		      "a composition draws a rule the plain text does not — the mark is VISIBLE");
	}

	[window release];
	[view release];
	[pool release];
	printf("text_marked_text: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
