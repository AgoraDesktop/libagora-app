/*
 * popup_color_menu — NSPopUpButton/Cell, NSColor and NSMenu: the item arithmetic, the colour-space doors and the menu's
 * deprecated pair.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE POP-UP'S ITEM ARITHMETIC IS THE MENU'S, AND THE CELL IS WHERE IT IS SPELLED.** The probe adds, inserts and removes
 * titles through the button, reads them back as an array, finds an item by its represented object and by its
 * target/action, and selects one — then checks the CELL's two behavioural flags: a pick copies the item's title onto the
 * button (unless `-usesItemFromMenu` is NO), and `-altersStateOfSelectedItem` makes a pick toggle the row's own state
 * rather than clear the others.
 *
 * **A COLOUR KNOWS ITS SPACE, AND `-set` IS THE PIXEL.** `-colorSpace` wraps the engine's space, `-colorSpaceName` maps a
 * named space to the calibrated name and an unnamed device space to the device name, and `-set` makes the colour the
 * context's fill — which is checked by filling a bitmap and reading the pixel back red.
 *
 * **THE MENU'S TWO FLAGS ROUND-TRIP.** `-isTornOff` is the 10.6 spelling of the state this tier already keeps, and
 * `-allowsContextMenuPlugIns` survives a mechanism Apple removed: it stores the answer and there is no plug-in to load.
 */
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSImageRep.h>	/* the device colour-space names */
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSView.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int failures;

static const char *space_name(NSColor *colour)
{
	NSString *name = [colour colorSpaceName];

	return (name != nil) ? [name UTF8String] : "(nil)";
}

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

@interface AGMenuTarget : NSObject
- (void)chosen:(id)sender;
@end

@implementation AGMenuTarget
- (void)chosen:(id)sender { (void)sender; }
@end

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);

		/* ============================================================================================
		 * 1. THE POP-UP BUTTON'S ITEMS.
		 * ========================================================================================== */
		{
			NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 160.0, 24.0)
									   pullsDown:NO];
			NSPopUpButtonCell *cell = (NSPopUpButtonCell *)[button cell];
			AGMenuTarget *target = [[AGMenuTarget alloc] init];
			NSArray *titles;

			[button addItemsWithTitles:[NSArray arrayWithObjects:@"One", @"Two", @"Three", nil]];
			check([button numberOfItems] == 3, "addItemsWithTitles: adds all three");
			titles = [button itemTitles];
			printf("  (note: titles are %s)\n", [[titles componentsJoinedByString:@", "] UTF8String]);
			check([titles count] == 3 && [[titles objectAtIndex:0] isEqualToString:@"One"]
				      && [[titles objectAtIndex:2] isEqualToString:@"Three"],
			      "and itemTitles answers them in menu order");

			[button insertItemWithTitle:@"Zero" atIndex:0];
			check([button numberOfItems] == 4
				      && [[[button itemTitles] objectAtIndex:0] isEqualToString:@"Zero"],
			      "insertItemWithTitle:atIndex: puts the title where asked");
			[button insertItemWithTitle:@"End" atIndex:99];
			check([[[button itemTitles] lastObject] isEqualToString:@"End"],
			      "and an index past the end appends rather than crashing");
			[button removeItemWithTitle:@"Two"];
			check(![[button itemTitles] containsObject:@"Two"] && [button numberOfItems] == 4,
			      "removeItemWithTitle: removes the row it names");

			/* THE TWO INDEX LOOKUPS THAT ARE NOT BY TITLE. */
			{
				NSMenuItem *first = [button itemAtIndex:0];
				NSNumber *payload = [NSNumber numberWithInt:42];	/* the SAME object: the menu compares by identity */
				NSInteger found;

				[first setRepresentedObject:payload];
				found = [button indexOfItemWithRepresentedObject:payload];
				check(found == 0, "an item is found by its represented object");
				[first setTarget:target];
				[first setAction:@selector(chosen:)];
				found = [button indexOfItemWithTarget:target andAction:@selector(chosen:)];
				check(found == 0, "and by its target and action");
			}

			[button selectItem:[button itemAtIndex:1]];
			check([button indexOfSelectedItem] == 1, "selectItem: moves the selection");
			check([[button titleOfSelectedItem] isKindOfClass:[NSString class]],
			      "and the title of the selection is answered");

			check([button autoenablesItems], "autoenablesItems starts YES, which is the menu's default");
			[button setAutoenablesItems:NO];
			check(![button autoenablesItems], "and the button's door reaches the menu's flag");

			/* ============================================================================================
			 * 2. THE CELL'S TWO BEHAVIOURAL FLAGS.
			 * ========================================================================================== */
			check([cell usesItemFromMenu], "the cell takes its title from the menu by default");
			[cell setUsesItemFromMenu:NO];
			[cell setTitle:@"Own"];
			[cell synchronizeTitleAndSelectedItem];
			check([[cell title] isEqualToString:@"Own"],
			      "with the flag off, a synchronise leaves the cell's own title alone");
			[cell setUsesItemFromMenu:YES];
			[cell synchronizeTitleAndSelectedItem];
			check(![[cell title] isEqualToString:@"Own"], "with it on, the selected item's title wins again");

			{
				NSMenuItem *row = [cell itemAtIndex:2];
				NSInteger before = [row state];

				[cell setAltersStateOfSelectedItem:YES];
				[cell itemSelected:row];
				printf("  (note: alters-state pick moved the row from %ld to %ld)\n",
				       (long)before, (long)[row state]);
				check([row state] != before, "an altering pick toggles the chosen row's state");
				[cell itemSelected:row];
				check([row state] == before, "and a second pick toggles it back");
			}

			[target release];
			[button release];
		}

		/* ============================================================================================
		 * 3. THE COLOUR-SPACE DOORS, AND -set AS A PIXEL.
		 * ========================================================================================== */
		{
			NSColor *calibrated = [NSColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:1.0];
			NSColor *device = [NSColor colorWithDeviceRed:0.0 green:0.0 blue:1.0 alpha:1.0];
			NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:8
				pixelsHigh:8 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:32 bitsPerPixel:32];

			printf("  (note: red's space is \"%s\", the device blue's is \"%s\")\n",
			       space_name(calibrated), space_name(device));
			check([calibrated colorSpace] != nil, "a colour answers an NSColorSpace");
			check([calibrated colorSpaceName] != nil,
			      "a colour made by a constructor answers a space name");
			check([[device colorSpaceName] isEqualToString:NSDeviceRGBColorSpace],
			      "and a device-space colour answers the device name");

			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[calibrated set];
			NSRectFill(NSMakeRect(0.0, 0.0, 8.0, 8.0));
			{
				NSColor *pixel = [rep colorAtX:4 y:4];

				printf("  (note: after -set and a fill the pixel is %.2f/%.2f/%.2f)\n",
				       pixel ? (double)[pixel redComponent] : -1.0,
				       pixel ? (double)[pixel greenComponent] : -1.0,
				       pixel ? (double)[pixel blueComponent] : -1.0);
				check(pixel != nil && [pixel redComponent] > 0.9
					      && [pixel greenComponent] < 0.1 && [pixel blueComponent] < 0.1,
				      "-set makes the colour the context's fill");
			}
			[rep release];
		}

		/* ============================================================================================
		 * 4. THE MENU'S TWO FLAGS.
		 * ========================================================================================== */
		{
			NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Probe"];

			check(![menu isTornOff], "a menu is not torn off");
			check([menu allowsContextMenuPlugIns], "and allows context-menu plug-ins by default");
			[menu setAllowsContextMenuPlugIns:NO];
			check(![menu allowsContextMenuPlugIns], "the flag round-trips");
			[menu release];
		}

		if (failures == 0) {
			printf("popup_color_menu: all checks passed\n");
			return 0;
		}
		printf("popup_color_menu: FAILURES\n");
		return 1;
	}
}
