/*
 * appkit_principal_class — which class is the one application?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE QUESTION AN APPLICATION THAT SUBCLASSES `NSApplication` CANNOT ANSWER FOR ITSELF.** `+sharedApplication`
 * constructed `[[NSApplication alloc] init]` no matter which class received the message, so a subclass that wanted
 * to customize event dispatch, own background work or extend the lifecycle had no supported way to be the object
 * `NSApp` names — the instance was always the base class, and no door said otherwise. `NSApplicationMain` had no
 * principal-class selection either.
 *
 * The selection is now: an explicitly set class; `NSPrincipalClass` from the main bundle's `Info.plist`; and
 * otherwise the RECEIVING class. This case drives the two ends a test can reach — the explicit door and the
 * receiving class — and the two refusals, because a refusal that is silent is how a bootstrap mistake becomes an
 * application that is subtly the wrong class.
 *
 * **THE ORDER OF THE CHECKS IS THE TEST.** The static instance is one, so the class has to be chosen before
 * anything asks for it; a case that created the application first and then checked the selection would be
 * measuring its own mistake.
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>

#include <stdio.h>
#include <string.h>

static int g_checks;
static int g_failed;

static void check(int ok, const char *what)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s\n", what);
	} else {
		printf("  [ok]   %s\n", what);
	}
}

/* THE SUBCLASS THE APPLICATION SHOULD BE. It adds nothing: what is under test is which CLASS the instance is, and a
 * subclass with behaviour of its own would make a failure ambiguous. */
@interface AGPrincipalApplication : NSApplication
@end

@implementation AGPrincipalApplication
@end

/* AND A SECOND ONE, for the "the class cannot change after the instance exists" refusal. */
@interface AGSecondApplication : NSApplication
@end

@implementation AGSecondApplication
@end

/* A CLASS THAT IS NOT AN APPLICATION AT ALL, for the other refusal. */
@interface AGNotAnApplication : NSObject
@end

@implementation AGNotAnApplication
@end

int main(void)
{
	@autoreleasepool {
		NSApplication *application;

		setvbuf(stdout, NULL, _IONBF, 0);

		/* 1. A CLASS THAT IS NOT A SUBCLASS IS REFUSED, and the refusal leaves the default in place rather than
		 *    storing something that would fail at the first message to `NSApp` instead. */
		[NSApplication setSharedApplicationClass:[AGNotAnApplication class]];
		check(NSApp == nil, "refusing a non-application class leaves the application uncreated");

		/* 2. THE RECEIVING CLASS IS THE APPLICATION'S CLASS, which is what makes a subclass usable without any
		 *    registration call at all. */
		application = [AGPrincipalApplication sharedApplication];
		check(application != nil, "the application exists");
		check([application isKindOfClass:[AGPrincipalApplication class]],
		      "and it is an instance of the class the message was sent to");
		check(NSApp == application, "and `NSApp` names it");

		/* 3. AND ONCE IT EXISTS THE CLASS CANNOT CHANGE, because the instance is one: accepting a new class here
		 *    would leave `NSApp` naming an object of a class nobody asked for. */
		[NSApplication setSharedApplicationClass:[AGSecondApplication class]];
		check([NSApp isKindOfClass:[AGPrincipalApplication class]],
		      "setting a class after the application exists does not change the instance");

		/* 4. AND `NSApplication` HANDS BACK THE SAME INSTANCE, not a second base-class one — the check that
		 *    catches a selection implemented as "make a new one when the class differs". */
		check([NSApplication sharedApplication] == application,
		      "a later `+sharedApplication` answers the same object, not a fresh base-class one");

		printf("appkit_principal_class: %d checks, %d failed%s\n", g_checks, g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");
	}
	return g_failed == 0 ? 0 : 1;
}
