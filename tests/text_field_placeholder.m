/*
 * text_field_placeholder.m — WHAT AN EMPTY FIELD SAYS IT IS FOR, AND THAT IT IS NOT A VALUE.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A PLACEHOLDER IS INK, SO THIS PROBE READS INK.** The claims worth making are not about an ivar: that an empty field
 * with a placeholder DRAWS something and one without draws NOTHING; that what it draws is DIMMER than the field's real
 * text, which is the whole distinction between a hint and a value; that it sits where the value would sit; and that an
 * ATTRIBUTED placeholder is drawn with the attributes it carries. Each is read out of a bitmap rep the cell was drawn
 * into, clear of the border, so "there is ink here" is a measurement rather than an intention.
 *
 * **AND A SESSION IS PART OF THE CLAIM RATHER THAN AN AFTERTHOUGHT.** While a field is being edited the words on
 * screen are the EDITOR's, so "is this field empty" is a question about the LIVE text — which is why the placeholder
 * must survive a click into an empty field and must vanish the moment a character arrives. That half is driven through
 * a real session on a real window, because it is the half a plain ivar read would get wrong.
 */
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSText.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSStringDrawing.h>
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>

#define W 120
#define H 24

/* THE TEXT AREA, CLEAR OF THE ONE-POINT BORDER AT 0..1 ON EVERY SIDE: a read inside this box cannot be a read of the
 * border, so every ink claim below is about what the field SAYS. */
#define IN_X0 3
#define IN_Y0 3
#define IN_X1 (W - 3)
#define IN_Y1 (H - 3)

static int failures = 0;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* INK IS ANYTHING MARKEDLY DARKER THAN THE WHITE SURFACE — which catches BOTH the black of a real value and the grey
 * of a placeholder, so "is anything written here" is one question at one threshold. */
static int ink_in(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.80) {
				n++;
			}
		}
	}
	return n;
}

/* THE DARKEST PIXEL IN A BOX, which is how a grey and a black are told apart: a placeholder's floor is its own grey and
 * a value's floor is the ink colour, so the MINIMUM is the measurement and the count above is not. */
static double darkest(NSBitmapImageRep *rep)
{
	int x, y;
	double min = 2.0;

	for (y = IN_Y0; y < IN_Y1; y++) {
		for (x = IN_X0; x < IN_X1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil) {
				double v = ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3.0;

				if (v < min) {
					min = v;
				}
			}
		}
	}
	return min;
}

/* THE FIRST COLUMN CARRYING INK, so "where does what is written begin" is a number. */
static int first_column(NSBitmapImageRep *rep)
{
	int x, y;

	for (x = IN_X0; x < IN_X1; x++) {
		for (y = IN_Y0; y < IN_Y1; y++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.80) {
				return x;
			}
		}
	}
	return -1;
}

/* AND A RED PIXEL, WHICH THE DARKNESS THRESHOLD CANNOT SEE: pure red is 1.0 in its red channel, so an attributed
 * placeholder drawn red would be invisible to `-ink_in`. This asks the question directly. */
static int has_red(NSBitmapImageRep *rep)
{
	int x, y;

	for (y = IN_Y0; y < IN_Y1; y++) {
		for (x = IN_X0; x < IN_X1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4) {
				return 1;
			}
		}
	}
	return 0;
}

static NSBitmapImageRep *draw_cell(NSTextFieldCell *cell)
{
	NSBitmapImageRep *rep = new_rep();
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[cell drawWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H) inView:view];
	[view release];
	return rep;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
	NSBitmapImageRep *rep;

	[cell setBordered:YES];
	[cell setBezeled:YES];

	/* 1. **THE TWO SHAPES, AND THAT BOTH ARE COPIES.** A placeholder is what the field SHOWS, so a caller must not be
	 * able to change it by keeping its own mutable string. */
	{
		NSMutableString *mut = [NSMutableString stringWithString:@"type here"];

		[cell setPlaceholderString:mut];
		[mut appendString:@" CHANGED"];
		check([[cell placeholderString] isEqualToString:@"type here"],
		      "a placeholder STRING is copied — mutating the caller's string does not change the field");
		check([cell placeholderAttributedString] == nil,
		      "and the attributed form is separate state, empty until it is set");
	}
	{
		NSMutableAttributedString *mut = [[NSMutableAttributedString alloc] initWithString:@"attributed"];
		NSAttributedString *held;

		[cell setPlaceholderAttributedString:mut];
		[mut replaceCharactersInRange:NSMakeRange(0, [mut length]) withString:@"completely different"];
		held = [cell placeholderAttributedString];
		check(held != nil && [[held string] isEqualToString:@"attributed"],
		      "an ATTRIBUTED placeholder is copied too");
		[mut release];
	}

	/* **FROM HERE THE ATTRIBUTED ONE WOULD WIN, SO IT IS CLEARED** — the plain string is what the next cases are about. */
	[cell setPlaceholderAttributedString:nil];
	[cell setPlaceholderString:nil];

	/* 2. **AN EMPTY FIELD WITH NO PLACEHOLDER DRAWS NOTHING IN ITS TEXT AREA; WITH ONE, IT DRAWS.** This is the pair
	 * that makes every later claim about "what is drawn" a claim about the placeholder. */
	rep = draw_cell(cell);
	check(ink_in(rep, IN_X0, IN_Y0, IN_X1, IN_Y1) == 0,
	      "an empty field with NO placeholder writes nothing — it is its face and its border");
	[rep release];

	[cell setPlaceholderString:@"type here"];
	rep = draw_cell(cell);
	printf("  (note: empty + placeholder — %d ink pixels, darkest %.2f)\n",
	       ink_in(rep, IN_X0, IN_Y0, IN_X1, IN_Y1), darkest(rep));
	check(ink_in(rep, IN_X0, IN_Y0, IN_X1, IN_Y1) > 0, "an empty field WITH a placeholder writes the hint");

	/* 3. **AND WHAT IT WRITES IS DIMMER THAN A VALUE, WHICH IS THE WHOLE DISTINCTION.** The hint's floor is the
	 * placeholder grey; the value's floor is the black ink colour. A field that drew its hint in the same ink would
	 * make a form unreadable — a person could not tell what has been filled in from what has not. */
	{
		double hintFloor = darkest(rep);
		int hintCol = first_column(rep);
		NSBitmapImageRep *valueRep;
		int valueCol;

		[cell setStringValue:@"type here"];	/* the SAME words, as a VALUE */
		valueRep = draw_cell(cell);
		valueCol = first_column(valueRep);
		printf("  (note: the same words as a VALUE — darkest %.2f; as a hint — %.2f; first column %d vs %d)\n",
		       darkest(valueRep), hintFloor, valueCol, hintCol);
		check(hintFloor > 0.35 && hintFloor < 0.75,
		      "a placeholder is drawn in a GREY — a hint, not the value's black");
		check(darkest(valueRep) < hintFloor - 0.30,
		      "and a real value is drawn markedly darker than the hint in the same field");
		/* AND WHERE THEY START IS THE SAME COLUMN, so a hint and a value are not two layouts. */
		check(hintCol >= 0 && valueCol == hintCol,
		      "the hint begins in the same column the value does, because both use the field's text rect");
		[valueRep release];
		[rep release];
	}

	/* 4. **AND A FIELD WITH A VALUE WRITES THE VALUE, NOT THE PLACEHOLDER.** The string is two letters and the
	 * placeholder is long, so where the ink STOPS tells the two apart: a field that drew its hint under its value
	 * would run to the hint's width. */
	{
		int stop;
		int hint_width;
		NSBitmapImageRep *rep2;

		[cell setStringValue:@"Wg"];
		[cell setPlaceholderString:@"a much longer placeholder than the value"];
		rep2 = draw_cell(cell);
		for (stop = IN_X1 - 1; stop >= IN_X0; stop--) {
			int y;
			int found = 0;

			for (y = IN_Y0; y < IN_Y1 && !found; y++) {
				NSColor *c = [rep2 colorAtX:stop y:y];

				found = (c != nil && [c redComponent] < 0.80);
			}
			if (found) {
				break;
			}
		}
		hint_width = (int)[[cell placeholderString] sizeWithAttributes:
			[NSDictionary dictionaryWithObjectsAndKeys:
				([cell font] != nil ? [cell font] : [NSFont systemFontOfSize:[NSFont systemFontSize]]),
				NSFontAttributeName, nil]].width;
		printf("  (note: value \"Wg\" with a %d-point hint set — ink stops at x=%d)\n", hint_width, stop);
		check(stop >= 0 && stop < IN_X0 + hint_width,
		      "a field that HAS a value writes the value, not the longer placeholder under it");
		[rep2 release];
	}

	/* 5. **AND AN EMPTY FIELD STILL MEASURES A LINE, WHICH IS WHAT LETS A FIELD BE SIZED BEFORE IT IS TYPED INTO.**
	 * `-sizeToFit` asks the cell, and `-cg_contentText` for an empty field is the empty string — so if an empty string
	 * measured NOTHING, a field built empty would come out one padding-band tall and grow the moment a character
	 * arrived. That is a metric this door owes the demonstration, which opens with an EMPTY field wearing a
	 * placeholder. */
	{
		NSTextFieldCell *empty = [[NSTextFieldCell alloc] initTextCell:@""];
		NSTextFieldCell *full = [[NSTextFieldCell alloc] initTextCell:@"Wg"];
		NSSize emptySize = [empty cellSizeForBounds:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		NSSize fullSize = [full cellSizeForBounds:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

		printf("  (note: empty cell measures %.2f high, one with a value %.2f)\n", emptySize.height, fullSize.height);
		check(emptySize.height > 0.0 && fabs(emptySize.height - fullSize.height) < 0.01,
		      "an EMPTY field measures the same LINE a value does, so `-sizeToFit` gives it its full height");
		[empty release];
		[full release];
	}

	/* 6. **AND AN ATTRIBUTED PLACEHOLDER IS DRAWN WITH THE ATTRIBUTES IT CARRIES.** Red is the colour the darkness
	 * threshold cannot see, so this is the case that proves the ATTRIBUTED string reaches the text layer rather than
	 * merely being stored. */
	{
		NSAttributedString *red = [[NSAttributedString alloc] initWithString:@"Wg"
			attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor],
				NSForegroundColorAttributeName, nil]];
		NSBitmapImageRep *rep3;
		NSBitmapImageRep *plainRep;

		[cell setStringValue:@""];
		[cell setPlaceholderString:@"plain grey"];
		[cell setPlaceholderAttributedString:nil];
		plainRep = draw_cell(cell);
		check(!has_red(plainRep), "sanity: a plain placeholder is not drawn in red");
		[plainRep release];

		[cell setPlaceholderAttributedString:red];
		rep3 = draw_cell(cell);
		check(has_red(rep3), "an ATTRIBUTED placeholder is drawn in its own colour (red), not the grey");
		[rep3 release];
		[red release];
	}

	/* 7. **AND THE PLACEHOLDER SURVIVES A CLICK INTO AN EMPTY FIELD AND LEAVES THE MOMENT A CHARACTER ARRIVES.** The
	 * live text is the EDITOR's during a session, which is the half a plain ivar read would get wrong. */
	{
		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 120.0)
							       styleMask:NSBorderlessWindowMask
								 backing:NSBackingStoreBuffered defer:NO];
		NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 120.0)];
		NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		NSText *editor;
		NSBitmapImageRep *liveRep;

		[window setContentView:content];
		[content addSubview:field];
		[(NSTextFieldCell *)[field cell] setPlaceholderString:@"click here to type"];
		[field selectText:nil];
		editor = (NSText *)[field currentEditor];
		check(editor != nil, "a session opens on the empty field");

		liveRep = draw_cell((NSTextFieldCell *)[field cell]);
		check(ink_in(liveRep, IN_X0, IN_Y0, IN_X1, IN_Y1) > 0,
		      "the placeholder is STILL drawn while the empty field is being edited");
		[liveRep release];

		[editor replaceCharactersInRange:NSMakeRange(0, 0) withString:@"X"];
		liveRep = draw_cell((NSTextFieldCell *)[field cell]);
		check(ink_in(liveRep, IN_X0, IN_Y0, IN_X1, IN_Y1) == 0,
		      "and it VANISHES the moment the editor has a character — the cell draws no string during a session");
		[liveRep release];

		[editor setString:@""];
		liveRep = draw_cell((NSTextFieldCell *)[field cell]);
		check(ink_in(liveRep, IN_X0, IN_Y0, IN_X1, IN_Y1) > 0,
		      "and comes BACK when the editor is emptied again");
		[liveRep release];

		[field abortEditing];
		[field release];
		[content release];
		[window release];
	}

	[cell release];
	[pool release];
	printf("text_field_placeholder: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
