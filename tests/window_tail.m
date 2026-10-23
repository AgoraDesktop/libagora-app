/*
 * window_tail — the last eighteen doors of NSWindow: the `is` aliases, the mutable style mask, the
 * represented filename, the default button cell, the backing/order/colour facts, the spaces flag, the
 * screen initialiser, the animated frame set, and the local event queue's two writers.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE WINDOW'S TAIL IS A SET OF SPELLINGS AND STORES AROUND THE STYLE MASK AND THE EVENT QUEUE, WITH TWO REAL
 * GEOMETRY DOORS.** The alias trio and the represented filename/default button/backing/order/colour/spaces doors are
 * state a caller can ask back; the animated frame set is the direct set with no frames in between; and the screen
 * initialiser is the direct initialiser with the one screen this tier has. The event queue pair is measured through
 * the same queue `-nextEventMatchingMask:` drains, so ordering and discarding are facts rather than return values.
 *
 * WHAT IS ASSERTED:
 *
 *   1. `-isResizable`, `-isMiniaturizable` and `-isZoomable` answer the style bits the older spellings answer.
 *   2. `-setStyleMask:` changes the mask, preserves the content rectangle, and grows/shrinks the frame by the chrome.
 *   3. `-setRepresentedFilename:` stores the path without changing the title, while
 *      `-setTitleWithRepresentedFilename:` still does both.
 *   4. `-setDefaultButtonCell:`, `-setPreferredBackingLocation:`, `-setOrderedIndex:` and
 *      `-setColorSpace:` round-trip, and the actual backing location stays main memory.
 *   5. The screen initialiser makes the same frame as the designated one, and `-setFrame:display:animate:` lands the
 *      frame directly.
 *   6. `-deviceDescription`, `-userSpaceScaleFactor` and the spaces flag answer the screen's facts and the stored one.
 *   7. `-postEvent:atStart:` orders head/tail and `-discardEventsMatchingMask:beforeEvent:` removes only the matching
 *      events before the named one (or all matching when the event is nil).
 */
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSColorSpace.h>
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

static int near(double a, double b)
{
	return fabs(a - b) < 0.51;
}

static NSEvent *key(char c, NSInteger windowNumber)
{
	NSString *string = [NSString stringWithFormat:@"%c", c];

	return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0
			       timestamp:0.0 windowNumber:windowNumber context:nil
				characters:string charactersIgnoringModifiers:string
				isARepeat:NO keyCode:(unsigned short)c];
}

static NSEvent *poll(NSWindow *window)
{
	return [window nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast]
				      inMode:nil dequeue:YES];
}

int main(void)
{
	@autoreleasepool {
		NSUInteger dressed = (NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
				      | NSResizableWindowMask);
		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 100.0, 100.0)
							      styleMask:dressed backing:NSBackingStoreBuffered defer:YES];

		/* 1. THE `is` ALIASES. */
		check([window isResizable] == [window resizable], "`-isResizable` is `-resizable`");
		check([window isMiniaturizable] == [window miniaturizable], "`-isMiniaturizable` is `-miniaturizable`");
		check([window isZoomable] == [window zoomable], "`-isZoomable` is `-zoomable`");
		check([window isResizable] && [window isMiniaturizable] && [window isZoomable],
		      "and the dressed mask answers all three YES");

		/* 2. THE MUTABLE STYLE MASK PRESERVES THE CONTENT RECT. */
		{
			NSSize contentBefore = [window contentRectForFrameRect:[window frame]].size;
			CGFloat frameHeightBefore = [window frame].size.height;

			[window setStyleMask:NSBorderlessWindowMask];
			check([window styleMask] == NSBorderlessWindowMask, "`-setStyleMask:` stores the new mask");
			check(near([window contentRectForFrameRect:[window frame]].size.width, contentBefore.width)
			      && near([window contentRectForFrameRect:[window frame]].size.height, contentBefore.height),
			      "and preserves the content rectangle");
			check([window frame].size.height < frameHeightBefore,
			      "while the frame loses the title bar's chrome");
			[window setStyleMask:dressed];
			check(near([window contentRectForFrameRect:[window frame]].size.height, contentBefore.height),
			      "and restoring the mask restores the chrome without changing the content");
		}

		/* 3. THE REPRESENTED FILENAME, WITH AND WITHOUT THE TITLE CHANGE. */
		[window setTitle:@"A Title"];
		[window setRepresentedFilename:@"/tmp/some/file.txt"];
		check([[window representedFilename] isEqualToString:@"/tmp/some/file.txt"],
		      "`-setRepresentedFilename:` stores the path");
		check([[window title] isEqualToString:@"A Title"],
		      "and leaves the title alone, which is the door's difference");
		[window setTitleWithRepresentedFilename:@"/tmp/other/name.txt"];
		check([[window representedFilename] isEqualToString:@"/tmp/other/name.txt"]
		      && [[window title] isEqualToString:@"name.txt"],
		      "while `-setTitleWithRepresentedFilename:` makes the file's name the title");

		/* 4. THE DEFAULT BUTTON, THE BACKING PREFERENCE, THE ORDER AND THE COLOUR SPACE. */
		{
			NSButtonCell *button = [[NSButtonCell alloc] initTextCell:@"OK"];
			NSColorSpace *space = [NSColorSpace sRGBColorSpace];

			[window setDefaultButtonCell:button];
			check([window defaultButtonCell] == button, "`-setDefaultButtonCell:` round-trips");
			[button release];

			check([window backingLocation] == NSWindowBackingLocationMainMemory,
			      "the ACTUAL backing location is main memory");
			[window setPreferredBackingLocation:NSWindowBackingLocationVideoMemory];
			check([window preferredBackingLocation] == NSWindowBackingLocationVideoMemory,
			      "while the PREFERENCE is the one a caller set");
			check([window backingLocation] == NSWindowBackingLocationMainMemory,
			      "and setting the preference changes no actual location");

			[window setOrderedIndex:3];
			check([window orderedIndex] == 3, "`-setOrderedIndex:` records the place a caller asked for");

			check([window colorSpace] != nil, "a window has a colour space from its screen");
			[window setColorSpace:space];
			check([window colorSpace] == space, "and a caller's colour space replaces it");
		}

		/* 5. THE SCREEN INITIALISER AND THE ANIMATED FRAME SET. */
		{
			NSRect contentRect = NSMakeRect(10.0, 20.0, 120.0, 80.0);
			NSWindow *screened = [[NSWindow alloc] initWithContentRect:contentRect styleMask:dressed
							backing:NSBackingStoreBuffered defer:YES
							screen:[NSScreen mainScreen]];
			NSWindow *plain = [[NSWindow alloc] initWithContentRect:contentRect styleMask:dressed
						     backing:NSBackingStoreBuffered defer:YES];

			check(NSEqualRects([screened frame], [plain frame]),
			      "the screen initialiser makes the same frame as the designated one");
			check(near([screened contentRectForFrameRect:[screened frame]].size.width, contentRect.size.width)
			      && near([screened contentRectForFrameRect:[screened frame]].size.height, contentRect.size.height),
			      "with the content rect it was handed");
			[window setFrame:NSMakeRect(5.0, 6.0, 140.0, 90.0) display:NO animate:YES];
			check(near([window frame].origin.x, 5.0) && near([window frame].origin.y, 6.0)
			      && near([window frame].size.width, 140.0) && near([window frame].size.height, 90.0),
			      "`-setFrame:display:animate:` lands the frame directly, with no frames in between");
			[screened release];
			[plain release];
		}

		/* 6. THE DEVICE DESCRIPTION, THE SCALE AND THE SPACES FLAG. */
		{
			NSDictionary *description = [window deviceDescription];

			check(description != nil, "`-deviceDescription` answers the screen's description");
			check([[description objectForKey:NSDeviceIsScreen] isEqual:NSDeviceIsScreen],
			      "whose NSDeviceIsScreen value is the constant itself");
			check(near([window userSpaceScaleFactor], 1.0), "`-userSpaceScaleFactor` is 1.0 — no backing scale");
			check(![window canBeVisibleOnAllSpaces], "the spaces flag starts NO");
			[window setCanBeVisibleOnAllSpaces:YES];
			check([window canBeVisibleOnAllSpaces], "and a caller's YES round-trips");
		}

		/* 7. THE LOCAL EVENT QUEUE'S TWO WRITERS. */
		{
			NSInteger number = [window windowNumber];
			NSEvent *a = key('a', number);
			NSEvent *b = key('b', number);
			NSEvent *c = key('c', number);
			NSEvent *got;

			[window postEvent:a atStart:NO];
			[window postEvent:b atStart:NO];
			[window postEvent:c atStart:YES];
			check(poll(window) == c, "`-postEvent:atStart:YES` puts the event at the head");
			check(poll(window) == a, "and the older event follows it");
			check(poll(window) == b, "then the tail event");

			[window postEvent:a atStart:NO];
			[window postEvent:b atStart:NO];
			[window postEvent:c atStart:NO];
			[window discardEventsMatchingMask:NSKeyDownMask beforeEvent:b];
			check(poll(window) == b, "`-discardEventsMatchingMask:beforeEvent:` removes the matching event(s) before it");
			check(poll(window) == c, "and leaves the named event and everything after it");

			[window postEvent:a atStart:NO];
			[window postEvent:b atStart:NO];
			[window discardEventsMatchingMask:NSKeyDownMask beforeEvent:nil];
			check(poll(window) == nil, "a nil before-event removes every matching event");
			got = poll(window);
			check(got == nil, "and the queue is empty afterwards");
		}

		printf("window_tail: %d case(s) failed\n", s_failed);
		[window release];
	}
	return s_failed != 0;
}
