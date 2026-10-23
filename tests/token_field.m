/*
 * token_field — NSTokenField and NSTokenFieldCell: the list, the three strings, the chips and the four mutations.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE DRIVES THE CONVERSIONS, NOT THE GETTERS.** A token field is a list seen four ways, so the checks are:
 * the list after a string is tokenized; the string after an array is set; the editor's text after a session opens on
 * editing strings that differ from the display strings; the chip INK after a delegate names a per-token style. A stored
 * style that never reaches the drawing, or a display string that is never asked for, would fail here.
 *
 * WHAT IS ASSERTED, and the sender each one names:
 *
 *   1. The factory: `+cellClass` is `NSTokenFieldCell`, a fresh field owns one, and a fresh cell delegates nothing.
 *   2. The defaults: `+defaultCompletionDelay` is 0.0 (completion ON), and `+defaultTokenizingCharacterSet` splits on a
 *      comma and a NEWLINE but not on a space — the reason "John Smith" is one token.
 *   3. The four forwards: style, separator, delay and the delegate are the cell's, and the separator is COPIED.
 *   4. Tokenizing: a typed string becomes a list, spaces around pieces are trimmed, empty pieces are dropped, and the
 *      display join round-trips.
 *   5. The conversions: display and editing strings are asked separately, a represented-object mapping is used on
 *      commit, and nil answers fall back to the object.
 *   6. The drawing: a rounded token lays down chip pixels where a plain token lays down almost none, and a per-token
 *      style is honoured inside one list.
 *   7. The session: `-selectWithFrame:` seeds the EDITING text, `-endEditing:` tokenizes it, and the addition review can
 *      refuse (empty), filter and rewrite (an array).
 *   8. The completion: a unique offer is inserted with the appended letters selected, a negative delay turns the
 *      question off, the token index counts the pieces before the partial, nested offer arrays are flattened, and an
 *      empty partial asks nothing.
 *   9. The pasteboard: copy writes the editing join, cut writes then empties, paste reads the board's string, and the
 *      delegate's read and write doors replace those defaults (a NO write clears the board).
 *  10. The menu: the hit test finds the chip under a point, and the delegate's `has` answer decides whether its menu is
 *      returned.
 */
#import <AppKit/NSTokenField.h>
#import <AppKit/NSTokenFieldCell.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSText.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

#define VIEW_W 420
#define VIEW_H 40

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ============================================================================================ *
 * THE DELEGATE: ONE OBJECT WITH A SWITCH FOR EACH DOOR, SO THE PROBE CAN NAME THE SENDER          *
 * ============================================================================================ */
@interface AGTokenDelegate : NSObject <NSTokenFieldDelegate>
{
@public
	BOOL decorateDisplay;		/* display = "D(" object ")" */
	BOOL mapTilde;			/* represented "~x" = "MAPPED" */
	BOOL rejectAllAdds;
	BOOL dropTheWordNo;
	BOOL menuForToken;
	BOOL writeReplacesTheBoard;
	BOOL refuseTheWrite;
	NSArray *completions;
	NSArray *readObjects;
	id plainObject;			/* the one object drawn with the plain style */

	/* THE RECORD OF WHAT WAS ASKED, which is the probe's witness that a door has a sender. */
	NSInteger completionsAsked;
	NSString *lastSubstring;
	NSInteger lastTokenIndex;
	NSInteger lastShouldAddIndex;
	BOOL menuAsked;
	BOOL hasMenuAsked;
	BOOL writeAsked;
	NSMenu *menu;
}
@end

@implementation AGTokenDelegate

- (NSArray *)tokenField:(NSTokenField *)tokenField
     completionsForSubstring:(NSString *)substring
		indexOfToken:(NSInteger)tokenIndex
     indexOfSelectedItem:(NSInteger *)selectedIndex
{
	(void)tokenField;
	completionsAsked++;
	lastSubstring = [substring copy];
	lastTokenIndex = tokenIndex;
	if (selectedIndex != NULL) {
		*selectedIndex = 0;
	}
	return completions;
}

- (NSArray *)tokenField:(NSTokenField *)tokenField
	       shouldAddObjects:(NSArray *)tokens
		       atIndex:(NSUInteger)index
{
	NSMutableArray *answer = [NSMutableArray array];

	(void)tokenField;
	lastShouldAddIndex = (NSInteger)index;
	if (rejectAllAdds) {
		return answer;
	}
	if (dropTheWordNo) {
		NSUInteger i;

		for (i = 0; i < [tokens count]; i++) {
			id object = [tokens objectAtIndex:i];

			if (![object isEqual:@"no"]) {
				[answer addObject:object];
			}
		}
		return answer;
	}
	return tokens;
}

- (NSString *)tokenField:(NSTokenField *)tokenField
     displayStringForRepresentedObject:(id)representedObject
{
	(void)tokenField;
	if (decorateDisplay) {
		return [NSString stringWithFormat:@"D(%@)", representedObject];
	}
	return nil;
}

- (NSString *)tokenField:(NSTokenField *)tokenField
     editingStringForRepresentedObject:(id)representedObject
{
	(void)tokenField;
	if (decorateDisplay) {
		return [NSString stringWithFormat:@"E(%@)", representedObject];
	}
	return nil;
}

- (id)tokenField:(NSTokenField *)tokenField
     representedObjectForEditingString:(NSString *)editingString
{
	(void)tokenField;
	if (mapTilde && [editingString hasPrefix:@"~"]) {
		return @"MAPPED";
	}
	return nil;
}

- (BOOL)tokenField:(NSTokenField *)tokenField
     writeRepresentedObjects:(NSArray *)objects
	       toPasteboard:(NSPasteboard *)pboard
{
	(void)tokenField;
	(void)objects;
	writeAsked = YES;
	if (refuseTheWrite) {
		return NO;
	}
	if (writeReplacesTheBoard) {
		[pboard setString:@"DELEGATE" forType:NSStringPboardType];
	}
	return YES;
}

- (NSArray *)tokenField:(NSTokenField *)tokenField readFromPasteboard:(NSPasteboard *)pboard
{
	(void)tokenField;
	(void)pboard;
	return readObjects;
}

- (NSMenu *)tokenField:(NSTokenField *)tokenField menuForRepresentedObject:(id)representedObject
{
	(void)tokenField;
	(void)representedObject;
	menuAsked = YES;
	return menu;
}

- (BOOL)tokenField:(NSTokenField *)tokenField hasMenuForRepresentedObject:(id)representedObject
{
	(void)tokenField;
	(void)representedObject;
	hasMenuAsked = YES;
	return menuForToken;
}

- (NSTokenStyle)tokenField:(NSTokenField *)tokenField styleForRepresentedObject:(id)representedObject
{
	(void)tokenField;
	if (plainObject != nil && [representedObject isEqual:plainObject]) {
		return NSPlainTextTokenStyle;
	}
	return NSRoundedTokenStyle;
}

@end

/* ============================================================================================ *
 * THE INK: A CHIP'S GREY AGAINST THE FIELD'S WHITE                                              *
 * ============================================================================================ */
static NSBitmapImageRep *render_view(NSView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:VIEW_W pixelsHigh:VIEW_H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:VIEW_W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)] fill];
	[view drawRect:[view bounds]];
	return rep;
}

/* **"CHIP PIXELS" ARE THE CONTROL GREY THE CHIP FILLS WITH, COUNTED AS A RATIO.** The negative is not "no grey at all"
 * — antialiased glyph edges on a white field produce greys through the whole range — so the claim is "a chip lays down
 * many times the grey a plain run does", which is the structural difference and not a single pixel's accident. */
static int chip_grey_pixels(NSBitmapImageRep *rep)
{
	int x, y, count = 0;

	for (y = 0; y < VIEW_H; y++) {
		for (x = 0; x < VIEW_W; x++) {
			NSColor *c = [rep colorAtX:x y:y];
			CGFloat r, g, b;

			if (c == nil) {
				continue;
			}
			r = [c redComponent];
			g = [c greenComponent];
			b = [c blueComponent];
			if (r > 0.86 && r < 0.99 && g > 0.86 && g < 0.99 && b > 0.86 && b < 0.99) {
				count++;
			}
		}
	}
	return count;
}

/* A notification shaped the way NSText sends one, so the cell's change path can be driven without a window. */
static NSNotification *change_note(NSText *editor)
{
	return [NSNotification notificationWithName:NSTextDidChangeNotification object:editor];
}

int main(void)
{
	@autoreleasepool {
		NSTokenField *field = [[NSTokenField alloc] initWithFrame:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)];
		NSTokenFieldCell *cell = (NSTokenFieldCell *)[field cell];
		AGTokenDelegate *delegate = [[AGTokenDelegate alloc] init];

		/* 1. THE FACTORY AND THE DEFAULTS. */
		check([NSTokenField cellClass] == [NSTokenFieldCell class], "`+cellClass` names NSTokenFieldCell");
		check([cell isKindOfClass:[NSTokenFieldCell class]], "a fresh token field owns a token cell");
		check([cell delegate] == (id)field, "and the cell's delegate is the field (the relay)");
		check([field delegate] == nil, "while the field's own delegate starts nil");
		check([NSTokenField defaultCompletionDelay] == 0.0, "`+defaultCompletionDelay` is 0.0 (completion on)");
		{
			NSCharacterSet *set = [NSTokenField defaultTokenizingCharacterSet];

			check([set characterIsMember:','] && [set characterIsMember:'\n'],
			      "the default separator holds a comma and a newline");
			check(![set characterIsMember:' '], "and NOT a space, so a name stays one token");
			check([cell tokenizingCharacterSet] != nil
			      && [[cell tokenizingCharacterSet] characterIsMember:','],
			      "a fresh cell carries the class separator");
		}
		check([cell tokenStyle] == NSDefaultTokenStyle, "a fresh cell's style is the default");
		check([cell completionDelay] == [NSTokenField defaultCompletionDelay],
		      "and its delay is the class default");

		/* 2. THE FOUR FORWARDS. */
		[field setTokenStyle:NSRoundedTokenStyle];
		check([cell tokenStyle] == NSRoundedTokenStyle, "`-setTokenStyle:` forwards to the cell");
		[field setCompletionDelay:-1.0];
		check([cell completionDelay] == -1.0, "the completion delay forwards");
		{
			NSMutableCharacterSet *mine = [[NSMutableCharacterSet alloc] init];

			[mine addCharactersInString:@";"];
			[field setTokenizingCharacterSet:mine];
			check([cell tokenizingCharacterSet] != mine, "the separator is COPIED, not aliased");
			check([[cell tokenizingCharacterSet] characterIsMember:';'],
			      "and the copy holds what the caller set");
			[mine addCharactersInString:@"|"];
			check(![[cell tokenizingCharacterSet] characterIsMember:'|'],
			      "so mutating the caller's set afterwards changes nothing");
			[mine release];
		}
		[field setTokenizingCharacterSet:nil];
		check([[cell tokenizingCharacterSet] characterIsMember:','],
		      "and nil restores the class default");
		[field setDelegate:delegate];
		check([field delegate] == delegate && [cell delegate] == (id)field,
		      "the field's delegate is the caller's while the cell's stays the relay");

		/* 3. TOKENIZING AND THE TWO STRINGS. */
		[field setStringValue:@"red, green , blue\nviolet"];
		{
			NSArray *list = [field objectValue];

			check([list isKindOfClass:[NSArray class]] && [list count] == 4,
			      "a typed string becomes a four-token list");
			check([[list objectAtIndex:0] isEqual:@"red"] && [[list objectAtIndex:1] isEqual:@"green"],
			      "in order, with the spaces around each piece trimmed");
			check([[list objectAtIndex:3] isEqual:@"violet"], "and a newline separates like a comma");
		}
		check([[field stringValue] isEqual:@"red, green, blue, violet"],
		      "and `-stringValue` joins the display strings with \", \"");
		[field setStringValue:@"a, , b"];
		check([[field objectValue] count] == 2, "an empty piece between commas is dropped, not a blank token");
		[field setStringValue:@""];
		check([[field objectValue] count] == 0 && [[field stringValue] isEqual:@""],
		      "the empty string is an empty list and an empty string back");
		[field setObjectValue:[NSArray arrayWithObjects:@"x", @"y", nil]];
		check([[field stringValue] isEqual:@"x, y"], "an array set directly is the list");
		[field setObjectValue:@"solo"];
		check([[field objectValue] count] == 1, "a bare object becomes a one-token list");
		[field setObjectValue:nil];
		check([field objectValue] != nil && [[field objectValue] count] == 0,
		      "and nil is an EMPTY list rather than a nil value");

		/* 4. THE CONVERSIONS, EACH WITH ITS DELEGATE. */
		delegate->decorateDisplay = YES;
		[field setObjectValue:[NSArray arrayWithObjects:@"one", @"two", nil]];
		check([[field stringValue] isEqual:@"D(one), D(two)"],
		      "the DISPLAY conversion is what `-stringValue` joins");
		check([[cell cg_editingText] isEqual:@"E(one), E(two)"],
		      "and the EDITING conversion is what a session is seeded with");
		delegate->decorateDisplay = NO;
		check([[field stringValue] isEqual:@"one, two"],
		      "a nil display answer falls back to the object's own text");
		delegate->mapTilde = YES;
		[field setStringValue:@"~draft, real"];
		check([[[field objectValue] objectAtIndex:0] isEqual:@"MAPPED"]
		      && [[[field objectValue] objectAtIndex:1] isEqual:@"real"],
		      "and a nil represented-object answer keeps the typed text while a mapped one is used");

		/* 5. THE DRAWING: A CHIP HAS INK A PLAIN RUN HAS NOT. */
		delegate->mapTilde = NO;
		/* **NO CALLER DELEGATE FOR THIS CHECK, BECAUSE THE CELL'S OWN STYLE IS WHAT IS BEING MEASURED.** The delegate
		 * above answers a per-token style, which correctly wins; with it out of the way the field's `-setTokenStyle:`
		 * is the only opinion, and the ink is the reader of it. */
		[field setDelegate:nil];
		[field setObjectValue:[NSArray arrayWithObjects:@"token", @"words", nil]];
		[field setTokenStyle:NSRoundedTokenStyle];
		{
			NSBitmapImageRep *rep = render_view(field);
			int rounded = chip_grey_pixels(rep);

			[rep release];
			[field setTokenStyle:NSPlainTextTokenStyle];
			rep = render_view(field);
			{
				int plain = chip_grey_pixels(rep);

				printf("  (note: chip grey pixels — rounded %d, plain %d)\n", rounded, plain);
				check(rounded > plain * 3, "a rounded token lays down chip pixels where a plain one does not");
			}
			[rep release];
		}
		[field setDelegate:delegate];
		/* **AND THE PER-TOKEN STYLE IS HONOURED INSIDE ONE LIST.** One rounded token and one plain token draw fewer chip
		 * pixels than two rounded ones, which is the only way a per-token answer can be seen from outside. */
		[field setTokenStyle:NSRoundedTokenStyle];
		{
			NSBitmapImageRep *rep = render_view(field);
			int both = chip_grey_pixels(rep);

			[rep release];
			delegate->plainObject = @"words";
			rep = render_view(field);
			{
				int mixed = chip_grey_pixels(rep);

				printf("  (note: chip grey pixels — two chips %d, one chip %d)\n", both, mixed);
				check(mixed < both && mixed > 100,
				      "a delegate's plain style for one token removes that chip and keeps the other");
			}
			[rep release];
			delegate->plainObject = nil;
		}

		/* 6. THE SESSION: SEEDED WITH EDITING TEXT, COMMITTED AS A REVIEWED LIST. */
		{
			NSText *editor = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 20.0)];

			delegate->decorateDisplay = YES;
			[field setObjectValue:[NSArray arrayWithObjects:@"one", @"two", nil]];
			[cell selectWithFrame:[field bounds] inView:field editor:editor delegate:field
					start:0 length:0];
			check([cell cg_currentEditor] == editor, "a session opens with the lent editor");
			check([[editor string] isEqual:@"E(one), E(two)"],
			      "and the editor is seeded with the EDITING strings, not the display ones");
			check([editor selectedRange].location == 0
			      && [editor selectedRange].length == [[editor string] length],
			      "with the whole run selected, because token ranges are not string ranges");

			[editor setString:@"E(three), E(four)"];
			[cell endEditing:editor];
			check([cell cg_currentEditor] == nil && [editor superview] == nil,
			      "ending the session takes the editor down");
			check([[field objectValue] count] == 2
			      && [[[field objectValue] objectAtIndex:0] isEqual:@"E(three)"],
			      "and commits the editor's string as the list");
			delegate->decorateDisplay = NO;
			[editor release];
		}
		{
			NSText *editor = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 20.0)];

			[field setObjectValue:[NSArray arrayWithObjects:@"keep", nil]];
			[cell selectWithFrame:[field bounds] inView:field editor:editor delegate:field
					start:0 length:0];
			[editor setString:@"rejected"];
			delegate->rejectAllAdds = YES;
			[cell endEditing:editor];
			/* **THE OLD LIST DOES NOT COME BACK, AND THAT IS THE HONEST ANSWER.** The session edited the WHOLE string;
			 * the old tokens were replaced on screen by the typed text, and an addition the delegate rejected simply
			 * does not land. Keeping them would resurrect a value the person deleted. */
			check([[field objectValue] count] == 0 && [[field stringValue] isEqual:@""],
			      "an empty `shouldAddObjects:` answer lets nothing land");
			delegate->rejectAllAdds = NO;
			[editor release];
		}
		{
			NSText *editor = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 20.0)];

			[cell selectWithFrame:[field bounds] inView:field editor:editor delegate:field
					start:0 length:0];
			[editor setString:@"yes, no, maybe"];
			delegate->dropTheWordNo = YES;
			[cell endEditing:editor];
			check([[field objectValue] count] == 2,
			      "a FILTERING `shouldAddObjects:` answer is what lands");
			check([[[field objectValue] objectAtIndex:0] isEqual:@"yes"]
			      && [[[field objectValue] objectAtIndex:1] isEqual:@"maybe"],
			      "and it lands without the rejected word");
			check(delegate->lastShouldAddIndex == 0, "a whole-string commit reviews at index 0");
			delegate->dropTheWordNo = NO;
			[editor release];
		}

		/* 7. THE COMPLETION: A UNIQUE OFFER, THE SIGN AS THE SWITCH, AND THE TOKEN INDEX. */
		/* **THE CHANGE PATH IS DRIVEN THROUGH THE EDITOR, WHICH IS THE REAL SENDER.** A session makes the cell the
		 * editor's delegate, so `-setString:` announces a change exactly as a keystroke does — the completion pass runs
		 * where it runs in the demonstration, not through a hand-made notification. */
		{
			NSText *editor = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 20.0)];

			[field setObjectValue:[NSArray arrayWithObject:@"seed"]];
			[cell selectWithFrame:[field bounds] inView:field editor:editor delegate:field
					start:0 length:0];
			check([cell cg_currentEditor] == editor, "a session is open for the completion path");

			delegate->completions = [NSArray arrayWithObject:@"alpha"];
			delegate->completionsAsked = 0;
			[field setCompletionDelay:0.0];
			[editor setString:@"al"];
			check([[editor string] isEqual:@"alpha"], "a unique completion is inserted");
			check([editor selectedRange].location == 2 && [editor selectedRange].length == 3,
			      "and the appended letters are selected, so the next key replaces the offer");
			check(delegate->completionsAsked >= 1 && [delegate->lastSubstring isEqual:@"al"],
			      "the delegate was asked for the partial token");

			[field setCompletionDelay:-1.0];
			delegate->completionsAsked = 0;
			[editor setString:@"be"];
			check([[editor string] isEqual:@"be"] && delegate->completionsAsked == 0,
			      "a NEGATIVE delay turns the completion question off");

			[field setCompletionDelay:0.0];
			delegate->completions = [NSArray arrayWithObject:@"alpha"];
			[editor setString:@"one, al"];
			check(delegate->lastTokenIndex == 1, "the token index counts the pieces before the partial");
			check([delegate->lastSubstring isEqual:@"al"], "and the partial is the text after the separator");

			delegate->completions = [NSArray arrayWithObject:
				[NSArray arrayWithObject:@"alpha"]];
			[editor setString:@"al"];
			check([[editor string] isEqual:@"alpha"], "an offer nested in an array is flattened");

			delegate->completionsAsked = 0;
			[editor setString:@"al, "];
			check(delegate->completionsAsked == 0, "an empty partial asks for nothing");

			/* close the session without committing the completion text as tokens */
			[cell endEditing:editor];
			[field setObjectValue:[NSArray array]];
			[editor release];
		}

		/* 8. THE PASTEBOARD: THE DEFAULT STRING, THE DELEGATE AND THE TWO GATES. */
		{
			NSPasteboard *board = [NSPasteboard generalPasteboard];

			[field setObjectValue:[NSArray arrayWithObjects:@"red", @"green", nil]];
			[field copy:nil];
			check([[board stringForType:NSStringPboardType] isEqual:@"red, green"],
			      "copy writes the editing strings joined");
			delegate->writeAsked = NO;
			delegate->writeReplacesTheBoard = YES;
			[field copy:nil];
			check(delegate->writeAsked && [[board stringForType:NSStringPboardType] isEqual:@"DELEGATE"],
			      "the delegate's write door runs after the default and can replace it");
			delegate->writeReplacesTheBoard = NO;
			delegate->refuseTheWrite = YES;
			[field copy:nil];
			check([board stringForType:NSStringPboardType] == nil,
			      "and a NO from that door clears the board it just wrote");
			delegate->refuseTheWrite = NO;

			[field cut:nil];
			check([[field objectValue] count] == 0, "cut writes and then empties the list");

			[board declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
			[board setString:@"blue, violet" forType:NSStringPboardType];
			[field paste:nil];
			check([[field objectValue] count] == 2
			      && [[[field objectValue] objectAtIndex:1] isEqual:@"violet"],
			      "paste reads the board's string and appends its pieces");

			delegate->readObjects = [NSArray arrayWithObject:@"fromDelegate"];
			[field paste:nil];
			check([[field objectValue] count] == 3
			      && [[[field objectValue] objectAtIndex:2] isEqual:@"fromDelegate"],
			      "a delegate's read door supplies the objects instead of the string");
			delegate->readObjects = nil;

			delegate->rejectAllAdds = YES;
			[field paste:nil];
			check([[field objectValue] count] == 3, "and a paste passes the addition review");
			delegate->rejectAllAdds = NO;
		}

		/* 9. THE MENU: THE HIT TEST AND THE DELEGATE'S TWO ANSWERS. */
		{
			NSMenu *menu = [[NSMenu alloc] initWithTitle:@"token"];
			NSRect bounds = [field bounds];
			NSInteger hit;
			NSInteger miss;

			/* ONE chip on the left: its chip starts at the drawing rect's left edge and is about 21 points tall. */
			[field setObjectValue:[NSArray arrayWithObject:@"token"]];
			hit = [cell cg_tokenIndexAtPoint:NSMakePoint(10.0, NSMidY(bounds)) inFrame:bounds];
			miss = [cell cg_tokenIndexAtPoint:NSMakePoint(NSMaxX(bounds) - 5.0, NSMidY(bounds)) inFrame:bounds];
			check(hit == 0, "the hit test finds the chip under a point");
			check(miss == NSNotFound, "and answers NSNotFound past the last token");

			delegate->menu = menu;
			delegate->menuForToken = NO;
			delegate->hasMenuAsked = NO;
			check([cell cg_menuForRepresentedObjectAtIndex:0] == nil && delegate->hasMenuAsked,
			      "`hasMenuForRepresentedObject:` NO answers nil and is the door asked");
			delegate->menuForToken = YES;
			check([cell cg_menuForRepresentedObjectAtIndex:0] == menu && delegate->menuAsked,
			      "and a YES returns the delegate's menu");
			check([cell cg_menuForRepresentedObjectAtIndex:7] == nil, "an out-of-range index has no menu");
			[menu release];
		}

		printf("token_field: %d case(s) failed\n", s_failed);
		[delegate release];
		[field release];
	}
	return s_failed != 0;
}
