/*
 * functions_target2 — the alert panels, the accessibility utilities, the services doors and the file-type phrases.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE MODAL AND SHEET DOORS ARE NOT RUN HERE, AND THAT IS A DELIBERATE LIMIT RATHER THAN AN OVERSIGHT.** `NSRunAlertPanel`
 * and `NSBeginAlertSheet` put a panel on screen and wait for a person; in a headless suite they would hang or block, so
 * what is verified is the half that is verifiable — the panel the GET family builds, its message, its buttons, and the
 * pair of ownership rules around it. The RUN family's own contribution is `-runModal`, which is `NSAlert`'s and is
 * already covered by that class's test.
 *
 * **`NSApplicationMain` IS CHECKED FOR LINKAGE AND NOT CALLED**, for the same reason doubled: calling it starts the
 * event loop, which would never return. Taking its address proves the symbol exists and has the era's type, which is
 * exactly what its absence used to break.
 *
 * THE ACCESSIBILITY UTILITIES ARE DRIVEN THROUGH A FAKE ELEMENT that answers the informal protocol, because that is what
 * makes them utilities: they must work over any object that answers, not only over a view.
 */
#import <AppKit/NSPanel.h>
#import <AppKit/NSAlert.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSAccessibility.h>
#import <AppKit/NSKeyValueBinding.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSWindow.h>
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

/* An element that answers the informal accessibility protocol, including being ignorable. */
@interface AGTestElement : NSObject
{
	BOOL _ignored;
	id _parent;
	NSMutableArray *_children;
	NSString *_role;
	NSString *_subrole;
}
- (id)initIgnored:(BOOL)ignored role:(NSString *)role subrole:(NSString *)subrole;
- (void)addChild:(id)child;
- (void)setParentElement:(id)parent;
@end

@implementation AGTestElement
- (id)initIgnored:(BOOL)ignored role:(NSString *)role subrole:(NSString *)subrole
{
	if ((self = [super init]) != nil) {
		_ignored = ignored;
		_role = [role retain];
		_subrole = [subrole retain];
		_children = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[_role release];
	[_subrole release];
	[_children release];
	[super dealloc];
}
- (void)addChild:(id)child
{
	[_children addObject:child];
	[child setParentElement:self];
}
- (void)setParentElement:(id)parent
{
	_parent = parent;
}
- (BOOL)accessibilityIsIgnored { return _ignored; }
- (id)accessibilityParent { return _parent; }
- (NSArray *)accessibilityChildren { return _children; }
- (NSString *)accessibilityRole { return _role; }
- (NSString *)accessibilitySubrole { return _subrole; }
@end

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];

		/* 1. The GET family builds a real panel, with the message and the buttons it was given. */
		{
			id panel = NSGetAlertPanel(@"Question", @"Discard %@?", @"Discard", @"Cancel", nil, @"the document");
			NSAlert *alert = (NSAlert *)panel;

			check(panel != nil, "NSGetAlertPanel answers a panel");
			check([[alert messageText] isEqualToString:@"Discard the document?"],
			      "the printf format is expanded, and a nil third button means no button");
			check([[alert buttons] count] == 2, "exactly the two buttons that were named");
			check([[[alert window] title] isEqualToString:@"Question"],
			      "the title is the panel's window title, the message is its body");
			NSReleaseAlertPanel(panel);
			check(1, "NSReleaseAlertPanel releases it without crashing");
		}
		{
			id critical = NSGetCriticalAlertPanel(@"Critical", @"%@", @"OK", nil, nil, @"stop");
			id informational = NSGetInformationalAlertPanel(@"Info", @"%@", @"OK", nil, nil, @"hello");

			check(critical != nil && [(NSAlert *)critical alertStyle] == NSCriticalAlertStyle,
			      "NSGetCriticalAlertPanel sets the critical style");
			check(informational != nil && [(NSAlert *)informational alertStyle] == NSInformationalAlertStyle,
			      "NSGetInformationalAlertPanel sets the informational style");
			NSReleaseAlertPanel(critical);
			NSReleaseAlertPanel(informational);
		}

		/* 2. The entry point exists with the era's type. */
		{
			int (*entry)(int, const char *[]) = NSApplicationMain;

			check(entry != NULL, "NSApplicationMain is defined and has Apple's signature");
		}

		/* 3. The services doors reach the application's own provider slot. */
		{
			id provider = [[[NSObject alloc] init] autorelease];

			NSRegisterServicesProvider(provider, @"MyService");
			check([[NSApplication sharedApplication] servicesProvider] == provider,
			      "NSRegisterServicesProvider installs the application's provider");
			NSUnregisterServicesProvider(@"MyService");
			check([[NSApplication sharedApplication] servicesProvider] == nil,
			      "NSUnregisterServicesProvider clears it");
			check(NSShowsServicesMenuItem(@"Open in Editor"),
			      "a service is shown by default");
			check(NSSetShowsServicesMenuItem(@"Open in Editor", NO) == 1,
			      "NSSetShowsServicesMenuItem accepts the change");
			check(!NSShowsServicesMenuItem(@"Open in Editor"),
			      "and the service is then hidden");
			NSSetShowsServicesMenuItem(@"Open in Editor", YES);
			check(NSShowsServicesMenuItem(@"Open in Editor"), "and shown again");
			check(!NSPerformService(@"No Such Service", [NSPasteboard generalPasteboard]),
			      "NSPerformService answers NO for a service that is not offered");
			NSUpdateDynamicServices();
			check(1, "NSUpdateDynamicServices is harmless when there are no dynamic services");
		}

		/* 4. The accessibility words. */
		{
			check([NSAccessibilityRoleDescription(@"AXButton", nil) isEqualToString:@"button"],
			      "a known role has a word");
			check([NSAccessibilityRoleDescription(@"AXButton", @"AXCloseButton") isEqualToString:@"close button"],
			      "a subrole wins over its role, which is the order Apple documents");
			check(NSAccessibilityRoleDescription(@"AXNotARole", nil) == nil,
			      "an unknown role answers nil rather than a plausible guess");
			check([NSAccessibilityActionDescription(@"AXPress") isEqualToString:@"press"],
			      "a known action has a word");
			check([NSAccessibilityActionDescription(@"AXCustom") isEqualToString:@"AXCustom"],
			      "an unknown action answers itself, so a custom action still has a label");
		}

		/* 5. The unignored tree, over elements that are not views. */
		{
			AGTestElement *wrapper = [[[AGTestElement alloc] initIgnored:YES role:@"AXGroup" subrole:nil] autorelease];
			AGTestElement *content = [[[AGTestElement alloc] initIgnored:NO role:@"AXButton" subrole:nil] autorelease];
			AGTestElement *hidden = [[[AGTestElement alloc] initIgnored:YES role:@"AXGroup" subrole:nil] autorelease];
			AGTestElement *leaf = [[[AGTestElement alloc] initIgnored:NO role:@"AXStaticText" subrole:nil] autorelease];

			[wrapper addChild:content];
			[wrapper addChild:hidden];
			[hidden addChild:leaf];

			check(NSAccessibilityUnignoredAncestor(content) == content,
			      "an element that is not ignored is its own unignored ancestor");
			check(NSAccessibilityUnignoredAncestor(wrapper) == wrapper,
			      "an ignored root with no parent answers itself rather than nil");
			check(NSAccessibilityUnignoredDescendant(wrapper) == content,
			      "the first unignored descendant is found through the wrapper");
			check([NSAccessibilityUnignoredChildren([wrapper accessibilityChildren]) count] == 2,
			      "an ignored child is replaced by its own unignored children");
			check(NSAccessibilityUnignoredChildrenForOnlyChild(wrapper) == nil,
			      "an element with two children has no ONLY-child answer, so the door answers nil");
		}

		/* 6. The bad-argument door raises, which IS its documented behaviour. */
		{
			BOOL raised = NO;

			@try {
				NSAccessibilityRaiseBadArgumentException(nil, @"AXTitle", @"value");
			} @catch (NSException *e) {
				raised = YES;
			}
			check(raised, "NSAccessibilityRaiseBadArgumentException raises an exception");
			NSAccessibilityPostNotification(nil, @"AXValueChanged");
			check(1, "NSAccessibilityPostNotification refuses by name without crashing");
		}

		/* 7. The file-type phrases are exact inverses. */
		{
			NSString *contents = NSCreateFileContentsPboardType(@"PDF");
			NSString *filename = NSCreateFilenamePboardType(@"TIFF");
			NSArray *both = [NSArray arrayWithObjects:contents, filename, @"junk", nil];

			check([contents isEqualToString:@"Apple PDF pasteboard type"],
			      "the file-contents phrase wraps the type");
			check([filename isEqualToString:@"TIFF filename"], "the filename phrase appends");
			check([NSGetFileType(contents) isEqualToString:@"PDF"], "and the contents phrase parses back");
			check([NSGetFileType(filename) isEqualToString:@"TIFF"], "and so does the filename phrase");
			check(NSGetFileType(@"junk") == nil, "a type that is neither answers nil");
			check([NSGetFileTypes(both) count] == 2,
			      "NSGetFileTypes maps a list, skipping what it cannot parse");
		}

		/* 8. No binding controller exists, so no object is a marker. */
		{
			check(!NSIsControllerMarker(nil), "NSIsControllerMarker is NO for nil");
			check(!NSIsControllerMarker([NSObject class]), "and NO for an ordinary object");
		}

		if (s_failed == 0) {
			printf("functions_target2: all checks passed\n");
			return 0;
		}
		printf("functions_target2: FAILURES\n");
		return 1;
	}
}
