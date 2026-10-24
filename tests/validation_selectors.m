/*
 * validation_selectors — an item built OUTSIDE the library validates against a document and its controller.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE ITEM HAS TO COME FROM ANOTHER IMAGE, OR THE PROBE MEASURES NOTHING.** This runtime gives each compilation unit
 * its own `objc_selector` struct for the same name — only the index inside it is shared — so a selector an application
 * builds is a different ADDRESS from the library's `@selector(saveDocument:)`. The item below is built HERE, in the test
 * binary, which is what an application's toolbar item is; a `==` comparison in the library answers NO for it and
 * `sel_isEqual` answers YES. The probe therefore fails against the old code and passes against the fix.
 */
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSUserInterfaceValidation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* THE ITEM, BUILT IN THIS IMAGE: a selector and a tag, which is the protocol's whole surface. */
@interface AGItem : NSObject <NSValidatedUserInterfaceItem>
{
	SEL _action;
	NSInteger _tag;
}
- (id)initWithAction:(SEL)action;
@end

@implementation AGItem
- (id)initWithAction:(SEL)action
{
	self = [super init];
	if (self != nil) {
		_action = action;
	}
	return self;
}
- (SEL)action { return _action; }
- (NSInteger)tag { return _tag; }
@end

int main(void)
{
	@autoreleasepool {
		NSDocument *document = [[NSDocument alloc] initWithType:@"AGProbeType" error:NULL];
		NSDocumentController *controller = [[NSDocumentController alloc] init];
		AGItem *save = [[AGItem alloc] initWithAction:@selector(saveDocument:)];
		AGItem *revert = [[AGItem alloc] initWithAction:@selector(revertDocumentToSaved:)];
		AGItem *other = [[AGItem alloc] initWithAction:@selector(copy:)];

		/* **THE RUNTIME FACT THE FIX RESTS ON.** A selector with the same NAME is `sel_isEqual` this image's literal
		 * whether or not the runtime happened to unify the two addresses; a fix that went back to `==` would fail the
		 * document checks below, not this one. */
		check(sel_isEqual([save action], @selector(saveDocument:)),
		      "a selector from this image is sel_isEqual the same name");

		/* AN UNTITLED DOCUMENT CANNOT BE SAVED IN PLACE. */
		check(![document validateUserInterfaceItem:save],
		      "an untitled document says no to Save");
		/* AND A TITLED ONE CAN — which the `==` comparison answered NO to, for every caller outside this library. */
		[document setFileURL:[NSURL fileURLWithPath:@"/tmp/agora-validation-probe.txt"]];
		check([document fileURL] != nil && [document fileType] != nil,
		      "the document now has a URL and a type");
		check([document validateUserInterfaceItem:save],
		      "a titled document says yes to Save");
		check([document validateUserInterfaceItem:revert],
		      "and to Revert, through the same cross-image selector");
		check(![document validateUserInterfaceItem:other],
		      "and no to an action it does not own");

		/* THE CONTROLLER'S FOUR, EACH FROM THIS IMAGE. */
		check([controller validateUserInterfaceItem:[[[AGItem alloc] initWithAction:@selector(newDocument:)] autorelease]],
		      "the controller says yes to New");
		check([controller validateUserInterfaceItem:[[[AGItem alloc] initWithAction:@selector(openDocument:)] autorelease]],
		      "and to Open");
		check([controller validateUserInterfaceItem:
			[[[AGItem alloc] initWithAction:@selector(saveAllDocuments:)] autorelease]],
		      "and to Save All");
		check([controller validateUserInterfaceItem:
			[[[AGItem alloc] initWithAction:@selector(clearRecentDocuments:)] autorelease]],
		      "and to Clear Recent");
		check(![controller validateUserInterfaceItem:other],
		      "and no to an action it does not own");

		printf("validation_selectors: %d case(s) failed\n", s_failed);
		[save release];
		[revert release];
		[other release];
		[document release];
		[controller release];
	}
	return s_failed != 0;
}
