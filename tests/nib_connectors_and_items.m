/*
 * nib_connectors_and_items — the two nib connections and the pasteboard item.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A CONNECTOR'S CLAIM IS THE GRAPH IT JOINS, SO THE PROBE CHECKS THE OBJECTS ON THE OTHER SIDE.** An outlet connector is
 * applied and the destination arrives through KVC on the source; an action connector is applied and the source is a control
 * whose TARGET and ACTION are set; a substituted placeholder is replaced at both ends and at neither when it is not there;
 * and the base class's `-establishConnection` is checked to CHANGE NOTHING, because "the base does nothing" is Apple's
 * contract rather than an omission.
 *
 * **AND THE ITEM'S CLAIM IS BOTH ENDS OF THE BOARD.** The value pairs are round trips, the provider is checked to be asked
 * LAZILY (a type it was given but nobody read stays unread), and then the item is written through
 * `NSPasteboard -writeObjects:` — the writer contract by `-respondsToSelector:` — and read back through the board's own
 * `-stringForType:`, so the claim is that a board carries what the item carried.
 */
#import <AppKit/NSNibConnector.h>
#import <AppKit/NSPasteboardItem.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSTextField.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* AN OBJECT WITH A PLAIN OUTLET, so the connector's KVC write lands somewhere the probe can read. */
@interface AGTarget : NSObject
{
@public
	id delegate;
}
@end
@implementation AGTarget
@end

/* A PROVIDER THAT COUNTS ITS ASKS, so laziness and caching are both visible. */
@interface AGDataProvider : NSObject
{
@public
	NSInteger asks;
}
@end
@implementation AGDataProvider
- (void)pasteboard:(NSPasteboard *)board item:(NSPasteboardItem *)item provideDataForType:(NSString *)type
{
	(void)board;
	asks++;
	[item setData:[@"from the provider" dataUsingEncoding:NSUTF8StringEncoding] forType:type];
}
@end

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);
		/* ============================================================================================
		 * 1. THE BASE CONNECTOR HOLDS THREE FACTS AND CHANGES NOTHING.
		 * ========================================================================================== */
		{
			AGTarget *source = [[AGTarget alloc] init];
			AGTarget *destination = [[AGTarget alloc] init];
			NSNibConnector *connector = [[NSNibConnector alloc] init];

			[connector setSource:source];
			[connector setDestination:destination];
			[connector setLabel:@"delegate"];
			check([connector source] == source && [connector destination] == destination
				      && [[connector label] isEqual:@"delegate"],
			      "the base connector answers the three facts it was given");
			[connector establishConnection];
			check(source->delegate == nil, "and its -establishConnection does nothing, which is Apple's contract");
			[connector release];
			[source release];
			[destination release];
		}

		/* ============================================================================================
		 * 2. THE OUTLET CONNECTOR: a key path on the source, and a substitution.
		 * ========================================================================================== */
		{
			AGTarget *source = [[AGTarget alloc] init];
			AGTarget *destination = [[AGTarget alloc] init];
			AGTarget *owner = [[AGTarget alloc] init];
			NSNibOutletConnector *connector = [[NSNibOutletConnector alloc] init];

			[connector setSource:source];
			[connector setDestination:destination];
			[connector setLabel:@"delegate"];
			[connector establishConnection];
			check(source->delegate == destination, "an outlet connector sets the destination by key path");

			/* **A PLACEHOLDER IS SUBSTITUTED BY IDENTITY, AT EITHER END.** */
			[connector setDestination:owner];
			check(source->delegate == destination, "changing the destination does not re-apply it by itself");
			[connector replaceObject:owner withObject:destination];
			check([connector destination] == destination, "a substitution replaces the object it names");
			[connector replaceObject:owner withObject:owner];
			check([connector destination] == destination, "and substituting an object that is not there changes nothing");

			/* A SOURCE THAT CANNOT TAKE A KEY PATH IS SKIPPED, NOT RAISED. */
			{
				NSNibOutletConnector *bad = [[NSNibOutletConnector alloc] init];

				[bad setSource:@"a string, which has no outlet"];	/* NSString answers setValue:forKeyPath:??? */
				[bad setDestination:destination];
				[bad setLabel:@"delegate"];
				[bad establishConnection];
				check(1, "a source that cannot take the outlet is skipped rather than raising");
				[bad release];
			}
			[connector release];
			[source release];
			[destination release];
			[owner release];
		}

		/* ============================================================================================
		 * 3. THE CONTROL CONNECTOR: a target and an action, on a real control.
		 * ========================================================================================== */
		{
			NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 24.0)];
			AGTarget *target = [[AGTarget alloc] init];
			NSNibControlConnector *connector = [[NSNibControlConnector alloc] init];

			[connector setSource:button];
			[connector setDestination:target];
			[connector setLabel:@"stepped:"];
			[connector establishConnection];
			check([button target] == target && [button action] == @selector(stepped:),
			      "a control connector sets the target AND the selector its label names");

			/* AND THE SELECTOR IS THE ONE THE NAME SPELLS. **COMPARED BY NAME, NOT BY POINTER**: this runtime keeps
			 * TYPED selector records, so the compiler's `@selector(description)` and the one `NSSelectorFromString` makes
			 * from the same spelling need not be one pointer — the NAME is what a nib's label can promise. */
			[connector setLabel:@"description"];
			[connector establishConnection];
			check([NSStringFromSelector([button action]) isEqual:@"description"],
			      "a different name is a different selector");
			check([button target] == target, "and the target is unchanged by the second application");

			[connector release];
			[button release];
			[target release];
		}

		/* ============================================================================================
		 * 4. THE ITEM: types, the three value pairs, and the lazy provider.
		 * ========================================================================================== */
		{
			NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
			AGDataProvider *provider = [[AGDataProvider alloc] init];
			NSDictionary *plist = [NSDictionary dictionaryWithObject:@"value" forKey:@"key"];
			id back;

			[item setData:[NSData dataWithBytes:"abc" length:3] forType:@"public.data"];
			[item setString:@"hello" forType:NSPasteboardTypeString];
			[item setPropertyList:plist forType:@"com.example.plist"];
			check([[item types] count] == 3, "an item carries the three types it was given");
			check([[item stringForType:NSPasteboardTypeString] isEqual:@"hello"], "the string round-trips");
			check([[item dataForType:@"public.data"] length] == 3, "the bytes come back as bytes");
			back = [item propertyListForType:@"com.example.plist"];
			check([back isKindOfClass:[NSDictionary class]] && [[back objectForKey:@"key"] isEqual:@"value"],
			      "and a property list comes back as the object it was");
			check([[item availableTypeFromArray:
				 [NSArray arrayWithObjects:@"public.png", NSPasteboardTypeString, nil]]
				isEqual:NSPasteboardTypeString],
			      "-availableTypeFromArray: answers the first type the item HAS");

			/* THE PROVIDER: unasked until a type it owns is read, and asked ONCE. */
			[item setDataProvider:provider forTypes:[NSArray arrayWithObject:@"com.example.late"]];
			check(provider->asks == 0, "a provider is not asked when it is installed");
			check([item dataForType:@"public.data"] != nil && provider->asks == 0,
			      "nor when a type it does not own is read");
			check([[item stringForType:@"com.example.late"] isEqual:@"from the provider"] && provider->asks == 1,
			      "it is asked ONCE when its own type is read");
			check([item dataForType:@"com.example.late"] != nil && provider->asks == 1,
			      "and the answer is cached, so a second read does not ask again");

			/* **AND THE BOARD TAKES IT.** `-writeObjects:` sends the writer contract by -respondsToSelector:, so an item is a
			 * writer without declaring the protocol this tier has not got. */
			{
				NSPasteboard *board = [NSPasteboard pasteboardWithUniqueName];

				check([board writeObjects:[NSArray arrayWithObject:item]],
				      "a board accepts an item through -writeObjects:");
				check([[board stringForType:NSPasteboardTypeString] isEqual:@"hello"],
				      "and carries the string the item carried");
				check([[board dataForType:@"public.data"] length] == 3,
				      "and the bytes, under the item's own type");
				[board releaseGlobally];
			}

			[item release];
			[provider release];
		}

		if (failures == 0) {
			printf("nib_connectors_and_items: all checks passed\n");
			return 0;
		}
		printf("nib_connectors_and_items: FAILURES\n");
		return 1;
	}
}
