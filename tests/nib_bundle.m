/*
 * nib_bundle — a nib in a BUNDLE, loaded BY NAME, into a view controller.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **EVERY OTHER NIB TEST SO FAR USED A PATH, AND AN APPLICATION NEVER DOES.** A Mac application says
 * `[[NSViewController alloc] initWithNibName:@"Main" bundle:nil]`, the bundle finds `Contents/Resources/Main.nib`,
 * `-loadView` instantiates it with the CONTROLLER as the file's owner, and the `view` outlet lands on `-setView:`. Every
 * link in that chain has been implemented and none of it had been exercised: the name lookup, the resource directory, the
 * controller's load-on-first-ask, and the owner outlet.
 *
 * SO THIS BUILDS A REAL `.app`-SHAPED BUNDLE — `Contents/Info.plist`, `Contents/Resources/Main.nib` — writes a nib into
 * it COMPILED FROM SOURCE, and then does what an application does. What it asserts:
 *
 *   1. `+[NSBundle bundleWithPath:]` accepts a bundle-shaped directory and finds the resource BY NAME.
 *   2. `+[NSNib nibNamed:bundle:]`'s path (record the name, resolve at instantiation) reads it — the branch of the
 *      reader that no test had touched, including the fallback from `Main.nib` to `Main`.
 *   3. A nib whose file's owner has the `view` outlet puts THAT view on the controller, and a second `-view` does not
 *      reload it (the load happens once).
 *   4. A nib that does NOT wire the owner still yields a view: the first top-level view is taken.
 *   5. A name the bundle does not have is an EXCEPTION from `-loadView`, not a nil view — the failure mode this class
 *      exists to make loud.
 */
#import "NSNibSource.h"

#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <AppKit/NSViewController.h>
#import <AppKit/NSCell.h>

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("%s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* THE CONTROLLER'S OUTLET, which is what `-loadView` fills from the file's owner. Declared the way an application
 * declares it: a property KVC can reach. */
@interface BundleController : NSViewController
@end

/* NOTHING IS OVERRIDDEN: the load, the outlet and the caching are all `NSViewController`'s, which is the point — the base
 * class is what an application subclasses, and the base class is what this test drives. (`_view` is the controller's own
 * ivar; a subclass that re-declared it would shadow the one `-loadView` writes.) */
@implementation BundleController
@end

/* **THE ONE SOURCE IS A FILE IN THE REPOSITORY** (`fixtures/Main.nibsource`), read from a path the harness passes in.
 * Every other fixture here is a C string inside a test binary; a design file that cannot be opened in an editor is a
 * design file nobody can look at, and this one is also what `ibtool compile` is documented with. */

static const char *kWithoutOwnerSource =
	"{ version = 1;\n"
	"  objects = ( { class = NSView; properties = { frame = \"0 0 60 40\"; tag = 9; }; } );\n"
	"}\n";

static BOOL write_file(NSString *path, NSData *data)
{
	NSFileManager *fm = [NSFileManager defaultManager];

	[fm createDirectoryAtPath:[path stringByDeletingLastPathComponent]
	      withIntermediateDirectories:YES
			       attributes:nil
				    error:NULL];
	return [data writeToFile:path atomically:YES];
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *fixturePath = (argc > 1) ? [NSString stringWithUTF8String:argv[1]] : nil;
	NSString *bundlePath = @"/tmp/agora-nib-bundle/Fixture.app";
	NSString *resources = [bundlePath stringByAppendingPathComponent:@"Contents/Resources"];
	NSBundle *bundle;
	NSString *error = nil;

	/* ---- THE BUNDLE ---------------------------------------------------------------------------- */
	check(write_file([bundlePath stringByAppendingPathComponent:@"Contents/Info.plist"],
			 [@"{ CFBundleIdentifier = \"org.agora.Fixture\"; CFBundlePackageType = APPL; "
			  "CFBundleName = Fixture; }" dataUsingEncoding:NSUTF8StringEncoding]),
	      "the bundle's Info.plist was written");

	/* AND THE TWO NIBS, COMPILED FROM SOURCE RATHER THAN CHECKED IN. */
	{
		NSData *archive;

		check(fixturePath != nil, "the harness passed the fixture's path");
		archive = [NSNibSource archiveFromSourceFile:fixturePath error:&error];
		if (archive == nil) {
			fprintf(stderr, "  (%s)\n", [(error != nil ? error : @"?") UTF8String]);
		}
		check(archive != nil, "the checked-in fixture COMPILES");
		check(write_file([resources stringByAppendingPathComponent:@"Main.nib"], archive),
		      "and was written into Contents/Resources/Main.nib");

		archive = [NSNibSource archiveFromSourceData:
			[NSData dataWithBytes:kWithoutOwnerSource length:strlen(kWithoutOwnerSource)] error:&error];
		check(archive != nil, "the unwired source compiles");
		check(write_file([resources stringByAppendingPathComponent:@"Bare.nib"], archive),
		      "and was written as Bare.nib");
	}

	bundle = [NSBundle bundleWithPath:bundlePath];
	check(bundle != nil, "+[NSBundle bundleWithPath:] accepted the bundle-shaped directory");
	check([bundle resourcePath] != nil, "the bundle answers a resource path");
	if (bundle != nil) {
		check([[bundle pathForResource:@"Main" ofType:@"nib"] hasSuffix:@"Main.nib"],
		      "the bundle finds Main.nib BY NAME");
		check([bundle pathForResource:@"Absent" ofType:@"nib"] == nil,
		      "and answers nil for a name it has not got");
	}

	/* ---- 2. NSNib BY NAME, WHICH RESOLVES AT INSTANTIATION ------------------------------------- */
	{
		NSNib *nib = [[NSNib alloc] initWithNibNamed:@"Main" bundle:bundle];
		NSArray *top = nil;
		BundleController *owner = [[BundleController alloc] init];

		check(nib != nil, "the reader RECORDED a nib by name");
		check([nib instantiateNibWithOwner:owner topLevelObjects:&top],
		      "and read it through the bundle when asked to instantiate");
		check([top count] == 1, "one top-level object");
		check([owner view] != nil, "the owner's `view` outlet was set through the connection");
		[owner release];
		[nib release];
	}

	/* ---- 3. THE CONTROLLER, WHICH IS THE DOOR AN APPLICATION USES ------------------------------ */
	{
		BundleController *controller = [[BundleController alloc]
			initWithNibName:@"Main" bundle:bundle];
		NSView *view;

		check(controller != nil, "a view controller was made with a nib name and a bundle");
		view = [controller view];	/* THE LOAD HAPPENS HERE, not in the initialiser */
		check(view != nil, "-view loaded the nib and answered the owner's view");
		check([view tag] == 7, "the view is the one the nib named (by tag)");
		check([[view subviews] count] == 2,
		      "and it came with its subtree (the fixture's heading and button)");
		check([controller view] == view, "asking again answers the SAME view — the load happens once");
		[controller release];
	}

	/* ---- 4. NO OWNER OUTLET: THE FIRST TOP-LEVEL VIEW IS THE VIEW ------------------------------ */
	{
		BundleController *controller = [[BundleController alloc]
			initWithNibName:@"Bare" bundle:bundle];

		check([[controller view] tag] == 9,
		      "a nib that wires no owner still yields its first top-level view");
		[controller release];
	}

	/* ---- 5. A NAME THAT IS NOT THERE IS AN EXCEPTION, NOT A NIL VIEW --------------------------- */
	{
		BundleController *controller = [[BundleController alloc]
			initWithNibName:@"Absent" bundle:bundle];
		BOOL raised = NO;

		@try {
			(void)[controller view];
		} @catch (NSException *exception) {
			raised = YES;
		}
		check(raised, "-loadView RAISES for a nib the bundle has not got");
		[controller release];
	}

	[pool release];
	if (s_failed != 0) {
		fprintf(stderr, "%d failure(s)\n", s_failed);
		return 1;
	}
	printf("all nib-bundle assertions passed\n");
	return 0;
}
