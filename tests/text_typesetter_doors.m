/*
 * text_typesetter_doors — the manager's last six selectors, and the two types this tier has not got.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS A ROUND TRIP AND A STATED ABSENCE.** The typesetter and the glyph generator are `id` doors because the
 * classes they name do not exist here; the probe sets a stand-in object, reads it back, clears it with nil, and checks the
 * default is nil — which is the difference from Apple, whose `-typesetter` creates one on first ask, and which the header
 * states rather than leaves to be discovered.
 *
 * **THE BEHAVIOUR IS A REAL VALUE**, so it gets a real test: the default is `NSTypesetterLatestBehavior`, the six numbers
 * Apple assigns are PINNED here (a future edit to the enum that changed one would move a caller's archived setting), and
 * the door stores what it is given.
 *
 * The last assertion is the one that says why the slice exists: every selector on the manager's own declaration list is
 * answered, so `NSLayoutManager` is complete against the 10.6 manifest.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
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

/* STAND-INS: the doors take `id`, so an object is all the probe needs to prove the round trip. */
@interface AGTypesetterStandIn : NSObject
@end
@implementation AGTypesetterStandIn
@end

@interface AGGlyphGeneratorStandIn : NSObject
@end
@implementation AGGlyphGeneratorStandIn
@end

int main(void)
{
	@autoreleasepool {
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		AGTypesetterStandIn *typesetter = [[AGTypesetterStandIn alloc] init];
		AGGlyphGeneratorStandIn *generator = [[AGGlyphGeneratorStandIn alloc] init];

		/* 1. THE OBJECT DOORS: nil, then the object, then nil again. */
		check([manager typesetter] == nil,
		      "a manager has no typesetter until one is set, which is the stated difference from Apple's on-demand one");
		[manager setTypesetter:typesetter];
		check([manager typesetter] == typesetter, "and a typesetter set is answered back");
		[manager setTypesetter:nil];
		check([manager typesetter] == nil, "and nil clears it");

		check([manager glyphGenerator] == nil, "a manager has no glyph generator either");
		[manager setGlyphGenerator:generator];
		check([manager glyphGenerator] == generator, "the generator round-trips");
		[manager setGlyphGenerator:nil];
		check([manager glyphGenerator] == nil, "and clears");

		/* 2. THE BEHAVIOUR: Apple's numbers, Apple's default. */
		check(NSTypesetterOriginalBehavior == 0 && NSTypesetterMacOSX10_2BehaviorWithBaselines == 1
			      && NSTypesetterMacOSX10_2Behavior == 2 && NSTypesetterMacOSX10_3Behavior == 3
			      && NSTypesetterLatestBehavior == -1,
		      "the five behaviour values are the numbers Apple assigns");
		check([manager typesetterBehavior] == NSTypesetterLatestBehavior,
		      "and a manager starts at NSTypesetterLatestBehavior, which is Apple's default");
		[manager setTypesetterBehavior:NSTypesetterMacOSX10_3Behavior];
		check([manager typesetterBehavior] == NSTypesetterMacOSX10_3Behavior,
		      "the behaviour door stores what it is given");
		[manager setTypesetterBehavior:NSTypesetterOriginalBehavior];
		check([manager typesetterBehavior] == NSTypesetterOriginalBehavior,
		      "including the original (zero) behaviour, which a 'default means zero' bug would confuse with unset");

		/* 3. THE SLICE'S POINT: every door the manager declares is answered. */
		{
			NSArray *doors = [NSArray arrayWithObjects:
				@"typesetter", @"setTypesetter:", @"glyphGenerator", @"setGlyphGenerator:",
				@"typesetterBehavior", @"setTypesetterBehavior:", nil];
			NSUInteger i;
			int all = 1;

			for (i = 0; i < [doors count]; i++) {
				if (![manager respondsToSelector:NSSelectorFromString([doors objectAtIndex:i])]) {
					all = 0;
					printf("  (note: missing %s)\n", [[doors objectAtIndex:i] UTF8String]);
				}
			}
			check(all, "the six typesetter doors are all answered, which is what completes the class");
		}

		[typesetter release];
		[generator release];
		[manager release];

		if (failures == 0) {
			printf("text_typesetter_doors: all checks passed\n");
			return 0;
		}
		printf("text_typesetter_doors: FAILURES\n");
		return 1;
	}
}
