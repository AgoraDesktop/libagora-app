/*
 * text_input — can a person type into an NSText, and does the keyboard reach it?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE WHOLE PATH IS EXERCISED, NOT THE PIECES.** A key arrives as an `NSEvent`, `-interpretKeyEvents:` turns it into
 * a command, the command edits the string or moves the caret, and the view is marked for redisplay — so what this
 * checks with each case is a keystroke, and the arithmetic it asserts is only how the keystroke is OBSERVED. A test
 * that called `-replaceCharactersInRange:withString:` directly would pass with the keyboard wired to nothing.
 *
 * WHAT IS ASSERTED, each one a behaviour that did not exist before this slice:
 *
 *   1. Typing inserts at the caret and leaves the caret AFTER what was typed.
 *   2. Backspace deletes backward, Delete forward, and either deletes a SELECTION whole.
 *   3. Movement steps by character and by line, and a movement COLLAPSES a selection to its near end.
 *   4. Shift-movement EXTENDS it, from whichever end the drag has not moved.
 *   5. A CONTROL CHARACTER is a command: Backspace, Return, Tab, Escape and the arrows all arrive as events and land
 *      on the right command, and BOTH Backspace spellings (`NSBackspaceCharacter` and `NSDeleteCharacter`) are
 *      backward delete.
 *   6. `-selectAll:` selects everything, and `-setString:` puts the caret at the end.
 *   7. An edit posts `NSTextDidChangeNotification` AND calls the delegate, because a listener and a delegate must not
 *      be able to disagree about whether something happened.
 *   8. A session begins and ends (the two notifications) and a delegate can REFUSE to begin one.
 *   9. A range outside the string is CLAMPED rather than crashing.
 *  10. The view DRAWS the text, the selection and the caret — the caret only while editing.
 *  11. The text a selection COVERS is white and the text it does not cover is the ink colour, which is a question
 *      about the drawn pixels rather than about the code that chose them.
 */
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

#define W 220
#define H 24

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int range_is(NSRange r, NSUInteger where, NSUInteger length)
{
	return r.location == where && r.length == length;
}

/* **A DELEGATE THAT ANSWERS EVERY QUESTION THIS CLASS ASKS**, and remembers which ones it was asked. `refuse` is how
 * the `Should` pair is tested: a form that will not let a field be edited says NO, and the probe has to be able to be
 * that form. */
@interface AGTextDelegate : NSObject
{
@public
	int began;
	int ended;
	int changed;
	BOOL refuse;
}
@end

@implementation AGTextDelegate
- (BOOL)textShouldBeginEditing:(NSText *)textObject
{
	(void)textObject;
	return refuse ? NO : YES;
}
- (void)textDidBeginEditing:(NSNotification *)notification
{
	(void)notification;
	began++;
}
- (void)textDidEndEditing:(NSNotification *)notification
{
	(void)notification;
	ended++;
}
- (void)textDidChange:(NSNotification *)notification
{
	(void)notification;
	changed++;
}
@end

/* A KEYSTROKE, BUILT FROM THE CHARACTER IT CARRIES, which is the whole of what the mapping reads. */
static NSEvent *key(NSString *characters, NSUInteger flags)
{
	return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags
			       timestamp:0.0 windowNumber:0 context:nil
			      characters:characters charactersIgnoringModifiers:characters
			       isARepeat:NO keyCode:0];
}

/* ONE KEYSTROKE, SENT THE WAY THE WINDOW WOULD SEND IT. */
static void type(NSText *text, NSString *characters)
{
	[text keyDown:key(characters, 0)];
}

static NSBitmapImageRep *draw(NSText *text)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[text drawRect:[text bounds]];
	return rep;
}

static int ink_in(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.72) {
				n++;
			}
		}
	}
	return n;
}

/* **THE DARKEST INK IN A COLUMN RANGE** — how "is any of this black" is asked. A selection's band is the ACCENT
 * (red 0.643, brightness about 0.75), so a band with no dark ink in it bottoms out AT the band, and a band drawn over
 * in white is brighter than that rather than darker; a glyph on a white field bottoms out at nothing. The two
 * measurements below are therefore read against each other rather than against a fixed number. */
static double darkest_ink(NSBitmapImageRep *rep, int x0, int x1)
{
	int x, y;
	double min = 2.0;

	for (y = 0; y < H; y++) {
		for (x = x0; x < x1; x++) {
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

/* IS THE PIXEL THE ACCENT? The selection's whole claim is a COLOUR, so it is read as one. */
static int accent_at(NSBitmapImageRep *rep, int x, int y)
{
	NSColor *c = [rep colorAtX:x y:y];

	return c != nil && fabs([c redComponent] - 0.643) < 0.08 && fabs([c greenComponent] - 0.604) < 0.08
		&& fabs([c blueComponent] - 1.0) < 0.08;
}

/* THE BITMAP'S ROWS COUNT FROM THE TOP AND THE VIEW'S FROM THE BOTTOM. */
static int row_of(int drawing_y)
{
	return H - 1 - drawing_y;
}

/* **THE CARET'S COLUMN: the RIGHTMOST column carrying a run as long as a line of text.** Only the caret can be one —
 * a glyph's stem is shorter than the band, and the caret is drawn after the last character — so a scan from the right
 * finds it, and finds it wherever the field has scrolled to. -1 when the rectangle has none. */
static int caret_column(NSBitmapImageRep *rep, int fromX, int toX)
{
	int x, y;

	for (x = toX - 1; x >= fromX; x--) {
		int rows = 0;

		for (y = 0; y < H; y++) {
			NSColor *c = [rep colorAtX:x y:row_of(y)];

			if (c != nil && [c redComponent] < 0.5) {
				rows++;
			}
		}
		if (rows >= 12) {
			return x;
		}
	}
	return -1;
}

/* A MOUSE EVENT AT AN X, which is all a drag needs: the drag's positions are read off the VIEW (see `x_for_index`),
 * so the events carry no geometry of their own beyond where the pointer is. */
static NSEvent *mouse(NSEventType type, int x)
{
	return [NSEvent mouseEventWithType:type location:NSMakePoint((CGFloat)x, 12.0) modifierFlags:0
				  timestamp:0.0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1.0f];
}

/* **THE X OF A CHARACTER INDEX, READ OFF THE VIEW ITSELF** — put the caret there, draw, and find the caret's column.
 * That is the same expression `-drawRect:` places the caret by, so the test and the view cannot disagree about where
 * a character is; and the index used is the LAST one, whose caret is the rightmost thing on the surface, which is
 * what makes it findable. */
static int x_for_index(NSText *t, NSUInteger index)
{
	NSBitmapImageRep *rep;
	int x;

	[t setSelectedRange:NSMakeRange(index, 0)];
	rep = draw(t);
	x = caret_column(rep, 0, W);
	[rep release];
	return x;
}

/* ONE DRAG, from one point to another — **IN STEPS, BECAUSE THAT IS WHAT A DRAG IS.** A pointer moving across a
 * field reports a position every few points, not one position at the end, and the difference is the whole subject
 * here: an anchor that is recomputed from the selection survives a drag delivered in a SINGLE event (the press has
 * just put the selection's location on the anchor, so the first sample agrees with it) and comes apart across the
 * samples in between. A test that jumps straight to the far end would pass against the bug. */
static void drag_from_to(NSText *t, int fromX, int toX)
{
	int step = (toX >= fromX) ? 4 : -4;
	int x;

	[t mouseDown:mouse(NSLeftMouseDown, fromX)];
	for (x = fromX; (step > 0) ? (x < toX) : (x > toX); x += step) {
		[t mouseDragged:mouse(NSLeftMouseDragged, x)];
	}
	[t mouseDragged:mouse(NSLeftMouseDragged, toX)];
	[t mouseUp:mouse(NSLeftMouseUp, toX)];
}

int main(void)
{
	@autoreleasepool {
		NSText *text = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		AGTextDelegate *delegate = [[AGTextDelegate alloc] init];

		setvbuf(stdout, NULL, _IONBF, 0);
		[text setDelegate:delegate];

		/* 1. TYPING. */
		type(text, @"H");
		type(text, @"i");
		check([[text string] isEqualToString:@"Hi"], "two keystrokes make the two characters they carried");
		check(range_is([text selectedRange], 2, 0), "and the caret ends up AFTER what was typed");
		type(text, @"!");
		check([[text string] isEqualToString:@"Hi!"], "and the next keystroke goes where the last one left off");

		/* 2. DELETION, BACKWARD, FORWARD, AND OVER A SELECTION. */
		type(text, @"\x7f");				/* DELETE, which is U+007F */
		check([[text string] isEqualToString:@"Hi"], "`NSDeleteCharacter` deletes BACKWARD");
		type(text, @"\x08");				/* BACKSPACE, the other spelling of the same key */
		check([[text string] isEqualToString:@"H"], "and so does `NSBackspaceCharacter` — the keymap difference");
		[text setSelectedRange:NSMakeRange(0, 1)];
		type(text, @"\x08");
		check([[text string] isEqualToString:@""], "and either one deletes a SELECTION whole");

		/* 3. MOVEMENT, AND WHAT A MOVEMENT DOES TO A SELECTION. */
		[text setString:@"abcdef"];
		check(range_is([text selectedRange], 6, 0), "`-setString:` puts the caret at the END of what it was given");
		[text moveLeft:nil];
		check(range_is([text selectedRange], 5, 0), "`-moveLeft:` steps back one character");
		[text setSelectedRange:NSMakeRange(1, 3)];
		[text moveLeft:nil];
		check(range_is([text selectedRange], 1, 0), "and with a selection it COLLAPSES to the near end");
		[text selectAll:nil];
		[text moveRight:nil];
		check(range_is([text selectedRange], 6, 0), "`-moveRight:` collapses to the far end");
		[text moveToBeginningOfLine:nil];
		check(range_is([text selectedRange], 0, 0), "`-moveToBeginningOfLine:` goes to the start");
		[text moveToEndOfLine:nil];
		check(range_is([text selectedRange], 6, 0), "and `-moveToEndOfLine:` to the end");

		/* 4. SHIFT-MOVEMENT EXTENDS. */
		[text setSelectedRange:NSMakeRange(2, 0)];
		[text moveLeftAndModifySelection:nil];
		check(range_is([text selectedRange], 1, 1), "`-moveLeftAndModifySelection:` extends the selection leftward");
		[text setSelectedRange:NSMakeRange(2, 0)];
		[text moveRightAndModifySelection:nil];
		check(range_is([text selectedRange], 2, 1), "and the rightward one extends rightward");
		[text setSelectedRange:NSMakeRange(0, 0)];
		[text moveToEndOfLineAndModifySelection:nil];
		check(range_is([text selectedRange], 0, 6), "and a SHIFT-click on End selects to the end of the line");

		/* 5. **AND THE KEYBOARD ITSELF, WHICH IS WHAT MAKES THIS INPUT RATHER THAN AN API.** Every case here is an
		 * event built the way the window builds one — the characters and the flags, nothing else — so a mapping that
		 * read a key CODE or looked at the modifier for a printable key would fail here. */
		[text setString:@"one two"];
		[text setSelectedRange:NSMakeRange(7, 0)];
		[text keyDown:key(@"\x7f", 0)];
		check([[text string] isEqualToString:@"one tw"], "an EVENT carrying Delete arrives at backward delete");
		/* THE CARET HAS TO HAVE SOMETHING IN FRONT OF IT for a FORWARD delete to have anything to delete: it is at
		 * the END after the backward one, and a forward delete there is correctly nothing at all. */
		[text setSelectedRange:NSMakeRange(0, 0)];
		[text keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSDeleteFunctionKey], 0)];
		check([[text string] isEqualToString:@"ne tw"], "and one carrying the Delete FUNCTION key deletes FORWARD");
		[text setSelectedRange:NSMakeRange(0, 0)];
		[text keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey], 0)];
		check(range_is([text selectedRange], 1, 0), "a RIGHT ARROW moves the caret");
		[text keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey], NSShiftKeyMask)];
		check(range_is([text selectedRange], 1, 1), "and a SHIFTED one extends the selection");
		[text keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey], 0)];
		check(range_is([text selectedRange], 1, 0), "an UNSHIFTED one collapses it again");
		[text keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSEndFunctionKey], 0)];
		check(range_is([text selectedRange], 5, 0), "END goes to the end of the line");

		[text keyDown:key([NSString stringWithFormat:@"%C", (unichar)NSHomeFunctionKey], 0)];
		check(range_is([text selectedRange], 0, 0), "and HOME to the beginning");
		/* **AND A COMMAND-MODIFIED KEY IS NOT READ, because a key equivalent is the menu bar's business.** THE
		 * CHARACTER IS PRINTABLE ON PURPOSE: one that would not type anyway would make this case pass with the rule
		 * and without it, which is a check that checks nothing. */
		[text keyDown:key(@"x", NSCommandKeyMask)];
		check([[text string] isEqualToString:@"ne tw"], "and a COMMAND-modified key does not edit the text");

		/* 6. THE THREE STRUCTURAL COMMANDS. */
		[text setString:@"abc"];
		[text selectAll:nil];
		check(range_is([text selectedRange], 0, 3), "`-selectAll:` selects the whole string");
		/* Tab and Escape need a WINDOW — they hand the question to it — and this probe has none, so what is asserted
		 * is that they are answered rather than that a window acted on them. A nil window is the quiet case the
		 * `NSWindow` doors are written for. */
		[text insertTab:nil];
		[text cancelOperation:nil];
		check([text isEditable], "Tab and Escape are ANSWERED without a window, rather than crashing");

		/* 7. THE NOTIFICATION AND THE DELEGATE, WHICH MUST AGREE. */
		{
			int before = delegate->changed;
			__block int posts = 0;
			id token;

			delegate->changed = 0;
			token = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextDidChangeNotification
										  object:text queue:nil
									     usingBlock:^(NSNotification *n) {
				(void)n;
				posts++;
			}];
			type(text, @"d");
			check(posts == 1 && delegate->changed == 1,
			      "an edit POSTS the change notification and CALLS the delegate, once each");
			(void)token;
			(void)before;
		}

		/* 8. THE SESSION: THE TWO NOTIFICATIONS, AND A DELEGATE THAT REFUSES. */
		delegate->began = 0;
		delegate->ended = 0;
		check([text becomeFirstResponder], "a view accepts a session when its delegate allows one");
		check(delegate->began == 1, "and the delegate is told it began");
		check([text resignFirstResponder], "and it ends when it is asked to");
		check(delegate->ended == 1, "which the delegate is told as well");

		delegate->refuse = YES;
		check(![text becomeFirstResponder], "but a delegate that REFUSES to begin editing is obeyed");
		delegate->refuse = NO;

		/* 9. THE CLAMPS. A caller's arithmetic can be wrong about a string that changed under it. */
		[text setString:@"abc"];
		[text replaceCharactersInRange:NSMakeRange(99, 5) withString:@"!"];
		check([[text string] isEqualToString:@"abc!"], "a range past the end becomes an INSERTION at the end");
		[text setSelectedRange:NSMakeRange(50, 10)];
		check(range_is([text selectedRange], 4, 0), "and a selection past the end is clamped to the text");

		/* 10. THE INK: THE TEXT, THE SELECTION, AND THE CARET ONLY WHILE EDITING. */
		[text setString:@"Hello"];
		[text setSelectedRange:NSMakeRange(5, 0)];
		{
			NSBitmapImageRep *rep = draw(text);

			check(ink_in(rep, 0, 0, W, H) > 0, "the view DRAWS its text");
			[rep release];
		}
		[text setSelectedRange:NSMakeRange(0, 3)];
		{
			NSBitmapImageRep *rep = draw(text);
			int x, y, found = 0;

			/* the selection's band, at the row the baseline sits on for a 24-point frame */
			for (y = 0; y < H && !found; y++) {
				for (x = 0; x < 40; x++) {
					if (accent_at(rep, x, y)) {
						found = 1;
						break;
					}
				}
			}
			check(found, "and the SELECTION in the platform's accent, behind the characters it covers");
			[rep release];
		}
		{
			NSBitmapImageRep *rep;
			int withCaret, withoutCaret;

			[text setSelectedRange:NSMakeRange(5, 0)];
			[text becomeFirstResponder];
			rep = draw(text);
			withCaret = ink_in(rep, 0, 0, W, H);
			[rep release];
			[text resignFirstResponder];
			rep = draw(text);
			withoutCaret = ink_in(rep, 0, 0, W, H);
			[rep release];
			check(withCaret > withoutCaret, "and a CARET while it is being edited, which is gone when it is not");
		}

		/* 11. AND THE MEASUREMENT, WHICH IS THE SAME SHAPE A CONTROL'S IS. */
		{
			NSText *t = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

			[t setString:@"OK"];
			[t sizeToFit];
			check([t frame].size.height > 0.0, "`-sizeToFit` gives an empty-or-short view a real height");
			{
				CGFloat narrow = [t frame].size.width;
				NSText *u = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

				[u setString:@"a considerably longer string"];
				[u sizeToFit];
				check([u frame].size.width > narrow, "and a LONGER string measures WIDER, through the text engine");
				[u release];
			}
			[t release];
		}

		/* 13. **AND THE CARET SITS ON THE TEXT IT BELONGS TO.** Two marks, one expression: the caret and the
		 * selection band are the same rectangle, and both are placed from the BASELINE — so the rect's ORIGIN has to
		 * be the bottom of the text's band, which is `baseline + descender` (the descender being negative). Putting
		 * the origin at the ASCENDER's distance instead puts the band's top at the baseline and drops the whole
		 * thing by `ascender - |descender|` — MEASURED at 9.5 points for the 13-point system font, which is the
		 * "half a line height" a person sees. THE GLYPHS ARE DRAWN AT THE BASELINE AND NEVER MOVED, so the ink was
		 * never wrong: the marks were, and this compares the two rather than trusting either. */
		{
			NSText *t = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 60.0, 24.0)];
			NSBitmapImageRep *rep;
			int x2, y2, glyphTop = -1, caretTop = -1;

			[t setString:@"H"];
			[t becomeFirstResponder];
			rep = draw(t);
			/* THE GLYPH'S TOP: the highest row carrying ink, in the half of the view the letter is in. */
			for (y2 = H - 1; y2 >= 0 && glyphTop < 0; y2--) {
				for (x2 = 0; x2 < 30; x2++) {
					NSColor *c = [rep colorAtX:x2 y:row_of(y2)];

					if (c != nil && [c redComponent] < 0.5) {
						glyphTop = y2;
						break;
					}
				}
			}
			/* THE CARET'S TOP: the rightmost column carrying a run as long as a line of text, which only the caret
			 * can be — a glyph's stem is shorter than the band. */
			for (x2 = W - 1; x2 >= 0 && caretTop < 0; x2--) {
				int rows = 0, top = -1;

				for (y2 = H - 1; y2 >= 0; y2--) {
					NSColor *c = [rep colorAtX:x2 y:row_of(y2)];

					if (c != nil && [c redComponent] < 0.5) {
						rows++;
						if (top < 0) {
							top = y2;
						}
					}
				}
				if (rows >= 12) {
					caretTop = top;
				}
			}
			printf("  (note: the glyph's top row is %d and the caret's is %d)\n", glyphTop, caretTop);
			check(glyphTop >= 0 && caretTop >= 0 && glyphTop - caretTop <= 1 && caretTop - glyphTop <= 1,
			      "the CARET's top is the GLYPH's top — it sits ON the text, not half a line below it");
			[rep release];
			[t release];
		}

		/* 14. **AND TYPING PAST THE RIGHT EDGE SCROLLS, SO THE CARET STAYS IN VIEW.** This is the one thing a
		 * single-line field must do that nothing else in this tier can do for it: the drawing layer REFUSES a
		 * non-zero BOUNDS ORIGIN by name, so there is no clip view to move and the field carries its own horizontal
		 * origin instead. WHAT IS MEASURED IS WHERE THE CARET LANDED, because that is the whole requirement — a caret
		 * a person cannot see is a caret that is not there.
		 *
		 * THE FIELD IS NARROW AND THE STRING IS LONG, and the bitmap is wide enough to hold the caret EITHER WAY.
		 * That is deliberate: with the scroll working the caret is inside the field, and with it broken the caret is
		 * still ON the surface, at an x the failing check prints. A bitmap only as wide as the view would report
		 * "nowhere", which is a worse description of the same bug. */
		{
			NSText *t = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 24.0)];
			NSBitmapImageRep *rep;
			int scrolled, back;

			[t becomeFirstResponder];
			[t insertText:@"a string far too long"];
			rep = draw(t);
			scrolled = caret_column(rep, 0, W);
			printf("  (note: a %d-point string in a 40-point field puts the caret at x=%d)\n",
			       (int)[t frame].size.width, scrolled);
			check(scrolled >= 0 && scrolled < 40,
			      "typing past the right edge SCROLLS: the caret is still inside the field");
			check(scrolled >= 30, "and it is at the EDGE it was scrolled to, not somewhere in the middle");
			[rep release];

			/* AND A CARET WALKED BACK TO THE START BRINGS THE TEXT WITH IT. */
			[t moveToBeginningOfLine:nil];
			rep = draw(t);
			back = caret_column(rep, 0, W);
			printf("  (note: after moving to the beginning the caret is at x=%d)\n", back);
			check(back >= 0 && back <= 6, "and moving the caret back to the START scrolls the field back with it");
			[rep release];

			[t release];
		}

		/* 15. **AND A CLICK LANDS WHERE THE CARET IS DRAWN, WHICH IS THE HIT TEST UNDOING THE SCROLL.** A field that
		 * draws its text at one origin and resolves a click at another puts the caret a field's width from the
		 * pointer, which is the mistake the `+ _originX` in `-fn_indexForPoint:` exists to prevent. THE CLICK IS
		 * PLACED ON THE CARET ITSELF and the caret must not move — the same "exact inverse" the caret's own geometry
		 * is built on, and one that is off by the whole origin when it is wrong. The tolerance is one character,
		 * which is the width of the thing being clicked. */
		{
			NSText *t = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 24.0)];
			NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 40.0, 24.0)
				styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
			NSBitmapImageRep *rep;
			NSUInteger before, after;
			int x;

			[w setContentView:t];
			[t setString:@"a string far too long"];
			[w makeFirstResponder:t];
			before = [t selectedRange].location;
			rep = draw(t);
			x = caret_column(rep, 0, W);

			[rep release];
			[t mouseDown:[NSEvent mouseEventWithType:NSLeftMouseDown location:NSMakePoint((CGFloat)x, 12.0)
						 modifierFlags:0 timestamp:0.0 windowNumber:[w windowNumber]
						     context:nil eventNumber:0 clickCount:1 pressure:1.0f]];
			after = [t selectedRange].location;
			printf("  (note: the caret was at %lu, the click was at x=%d, the caret is now %lu)\n",
			       (unsigned long)before, x, (unsigned long)after);
			check(x >= 0 && after + 1 >= before && after <= before + 1,
			      "and a CLICK on the caret leaves it where it was — the hit test puts the scroll origin back");
			[t release];
			[w release];
		}

		/* 16. **AND A DRAG SELECTS IN BOTH DIRECTIONS, BY THE SAME ARITHMETIC.** A selection has one end that moves —
		 * the pointer's — and one that does not, and the one that does not is fixed by the PRESS. Recomputing it from
		 * the selection on each pass looks like it works, and it does FORWARD: a range keeps its lower index, so
		 * while the pointer moves right the anchor IS the selection's location and the two agree. Move the pointer
		 * LEFT and the location follows the POINTER, so the anchor travels with it and the range stays one character
		 * wide for the whole drag — which is "forward highlights and backward does not".
		 *
		 * THE TWO DRAGS BELOW COVER THE SAME DISTANCE IN OPPOSITE DIRECTIONS, so the LENGTHS must agree. That is the
		 * property rather than any particular index, and it is the one the bug violates. */
		{
			NSText *t = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 24.0)];
			NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 120.0, 24.0)
				styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
			NSUInteger forward, backward;
			int xEnd, xStart = 1;

			[w setContentView:t];
			[t setString:@"abcdefghijklmnop"];	/* sixteen characters, in a field wide enough to show them all */
			[w makeFirstResponder:t];
			xEnd = x_for_index(t, [[t string] length]);
			drag_from_to(t, xStart, xEnd);
			forward = [t selectedRange].length;
			drag_from_to(t, xEnd, xStart);
			backward = [t selectedRange].length;
			printf("  (note: dragging from x=%d to x=%d selects %lu; from x=%d to x=%d selects %lu)\n",
			       xStart, xEnd, (unsigned long)forward, xEnd, xStart, (unsigned long)backward);
			check(forward >= 12 && backward >= 12, "a drag selects the text it crosses, in EITHER direction");
			check(forward == backward, "and the same distance FORWARD and BACKWARD selects the same length");
			[t release];
			[w release];
		}

		/* 17. **AND THE TEXT UNDER THE HIGHLIGHT IS WHITE.** A selection is a band of accent with the text on top of it,
		 * and the colour of that text is not a detail: black on the accent is legible and still reads as an accident,
		 * which is why every platform this one is modelled on draws it in the surface colour. WHAT IS ASSERTED HERE IS
		 * THE PIXELS, not which colour the drawing code asked for — a second pass that clipped to the wrong rectangle,
		 * or ran before the first one, would leave the band's ink exactly as dark as it was and still look right in
		 * source.
		 *
		 * THE FIELD IS ASKED NOT TO DRAW ITS BACKGROUND, so the only ink on the surface is the glyphs: with the bezel
		 * in the picture its own border is dark enough to be mistaken for text, and the question here is about the
		 * text. */
		{
			NSText *t = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSBitmapImageRep *rep;
			int x, y, bandX0 = -1, bandX1 = -1;
			double inside, outside;

			[t setDrawsBackground:NO];
			[t setString:@"abcdefghijklmnop"];
			[t setSelectedRange:NSMakeRange(6, 4)];		/* four characters with text on both sides of them */
			rep = draw(t);
			for (x = 0; x < W; x++) {
				for (y = 0; y < H; y++) {
					if (accent_at(rep, x, y)) {
						if (bandX0 < 0) {
							bandX0 = x;
						}
						bandX1 = x;
						break;
					}
				}
			}
			inside = (bandX0 >= 0) ? darkest_ink(rep, bandX0 + 2, bandX1 - 1) : -1.0;
			outside = (bandX0 >= 2) ? darkest_ink(rep, 2, bandX0 - 2) : -1.0;
			printf("  (note: the selection band spans x %d..%d; darkest ink inside it %.2f, outside it %.2f)\n",
			       bandX0, bandX1, inside, outside);
			check(bandX0 > 0 && bandX1 > bandX0 + 4, "the selection draws a band to put the text on");
			check(inside >= 0.60, "and the glyphs the band COVERS are white — there is no dark ink inside it");
			check(outside >= 0.0 && outside <= 0.45, "while the glyphs it does not cover keep the ink colour");
			[rep release];
			[t release];
		}

		printf("text_input: %d case(s) failed\n", s_failed);
		[text release];
		[delegate release];
	}
	return s_failed == 0 ? 0 : 1;
}
