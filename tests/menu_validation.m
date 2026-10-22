/*
 * menu_validation — does a menu VALIDATE its items, and does an item SAY it is on?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **TWO THINGS A MENU HAS TO BE ABLE TO SAY, AND NEITHER COULD BE SAID.** Menu VALIDATION is what greys out an
 * item that cannot be chosen right now, and its protocol (`NSMenuValidation`) is also the one place an item's
 * target may CHANGE the item while it answers — which is how a "Check for Updates" item carries a checkmark.
 * The item's own CHECKED state is the other half, and this tier stored it and drew nothing: the state images
 * default to the system checkmark on the Mac, this tree ships no system image, so an item that was ON with no
 * picture of its own showed nothing at all.
 *
 * WHAT IS ASSERTED, each one a behaviour that was absent:
 *
 *   1. A target that implements `-validateMenuItem:` DECIDES enablement — not `-respondsToSelector:` of the
 *      action.
 *   2. And it may CHANGE the item while it answers (its state), which is the reason the walk must call it.
 *   3. A target that does NOT validate falls back to the plain rule: enabled exactly when it answers the action.
 *   4. An item with no target is DISABLED when nobody in the responder chain answers it — the walk finds the
 *      receiver, and no receiver means no action to offer.
 *   5. An item that is ON with no state image of its own DRAWS a checkmark, in the state column.
 *   6. A DISABLED item's title is DRAWN DIMMED, so a person can see it cannot be chosen.
 *   7. A NIL-TARGET item is validated against the FIRST RESPONDER that answers its action: enabled when that
 *      responder answers, disabled when its `-validateMenuItem:` says no, and DISPATCHED to it on a pick.
 */
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSMenuItemCell.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

#include <stdio.h>

#define W 200
#define H 22

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* A TARGET THAT VALIDATES: it counts its calls, answers what it was told to, and — the second half of the
 * protocol — sets the item's state as it answers. */
@interface AGValidatingTarget : NSObject
{
@public
	int calls;
	BOOL answer;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)action:(id)sender;
@end

@implementation AGValidatingTarget
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	calls++;
	[item setState:NSOnState];
	return answer;
}
- (void)action:(id)sender
{
	(void)sender;
}
@end

/* A TARGET THAT DOES NOT VALIDATE but does answer the action, so the fallback rule has something to find. */
@interface AGPlainTarget : NSObject
- (void)action:(id)sender;
@end

@implementation AGPlainTarget
- (void)action:(id)sender
{
	(void)sender;
}
@end

/* **A FIRST RESPONDER THAT ANSWERS AN ACTION, SO A NIL-TARGET ITEM HAS SOMEBODY IN THE CHAIN TO FIND.** The
 * second one also VALIDATES, which is the chain's other half: the walk hands the item to whoever would receive
 * the action, and that responder decides whether the item is enabled. */
@interface AGChainView : NSView
{
@public
	int calls;
}
/* **AND IT ACCEPTS THE KEYBOARD, WHICH IS WHAT MAKES IT A FIRST RESPONDER RATHER THAN A VIEW SOMEBODY NAMED.**
 * `-makeFirstResponder:` asks this now, as Apple's does, so a view that does not answer YES is never actually made
 * one — and this probe's whole subject is what the walk finds when the FIRST RESPONDER answers. Without this the
 * cases below would pass through the CONTENT VIEW instead, which is a different door and a weaker claim. */
- (BOOL)acceptsFirstResponder;
- (void)chainAction:(id)sender;
@end

@implementation AGChainView
- (BOOL)acceptsFirstResponder
{
	return YES;
}
- (void)chainAction:(id)sender
{
	(void)sender;
	calls++;
}
@end

@interface AGValidatingChainView : AGChainView
{
@public
	BOOL allow;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end

@implementation AGValidatingChainView
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	(void)item;
	return allow;
}
@end

/* THE APPLICATION'S OWN REGISTRY DOOR, declared here the way `NSWindow.m` declares it: a window has to JOIN the
 * registry to become the app's KEY window, and `-targetForAction:` starts at that window's first responder.
 * `-orderFront:` would do it too, but only with a compositor, and this suite is offscreen. */
@interface NSApplication (AGMenuValidationTestRegistry)
- (void)cg_addWindow:(NSWindow *)aWindow;
@end

/* THE HIGHLIGHT DECISION THE TRACKING LOOP MAKES ON EVERY MOVE, declared here so the check can ask it directly:
 * a row that cannot be chosen takes no highlight. */
@interface NSMenu (AGMenuValidationTestHighlight)
- (BOOL)cg_itemTakesHighlight:(NSMenuItem *)item;
@end

/* Ink anywhere in a horizontal band of a bitmap, and the number of pixels darker than a threshold. */
static int band_ink(NSBitmapImageRep *rep, int x0, int x1, double below)
{
	int x, y, n = 0;

	for (y = 0; y < H; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < below) {
				n++;
			}
		}
	}
	return n;
}

int main(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Test"];
	AGValidatingTarget *validator = [[AGValidatingTarget alloc] init];
	AGPlainTarget *plain = [[AGPlainTarget alloc] init];
	NSMenuItem *validated;
	NSMenuItem *plainItem;
	NSMenuItem *noTarget;

	/* 1-3: the three shapes of an item with a target. */
	validated = [[NSMenuItem alloc] initWithTitle:@"Validated" action:@selector(action:) keyEquivalent:@""];
	[validated setTarget:validator];
	[menu addItem:validated];
	[validated release];

	plainItem = [[NSMenuItem alloc] initWithTitle:@"Plain" action:@selector(action:) keyEquivalent:@""];
	[plainItem setTarget:plain];
	[menu addItem:plainItem];
	[plainItem release];

	/* A THIRD ITEM WHOSE TARGET DOES NOT ANSWER THE ACTION — the fallback must disable it. */
	{
		NSMenuItem *dead = [[NSMenuItem alloc] initWithTitle:@"Dead" action:@selector(nowhereAtAll:)
							   keyEquivalent:@""];

		[dead setTarget:plain];
		[menu addItem:dead];
		[dead release];
	}

	noTarget = [[NSMenuItem alloc] initWithTitle:@"Responder" action:@selector(action:) keyEquivalent:@""];
	[noTarget setEnabled:YES];
	[menu addItem:noTarget];
	[noTarget release];

	check([menu autoenablesItems], "a menu auto-enables its items by default");

	/* 1. A VALIDATING TARGET THAT SAYS NO DISABLES THE ITEM. The first version of the walk read
	 * `-respondsToSelector:` of the ACTION alone, so this item — whose target answers the action perfectly —
	 * would have stayed enabled. */
	validator->answer = NO;
	[menu update];
	check([validated isEnabled] == NO, "a target's `-validateMenuItem:` NO DISABLES the item it validates");
	check(validator->calls == 1, "and the validator was actually ASKED");
	/* 2. AND IT MAY CHANGE THE ITEM WHILE IT ANSWERS — which is how a checked item comes to be checked. */
	check([validated state] == NSOnState, "and the validator could SET THE ITEM'S STATE as it answered");

	/* And the other answer enables it again. */
	validator->answer = YES;
	[menu update];
	check([validated isEnabled] == YES, "and a YES enables it");

	/* 3. THE FALLBACK: no validator, so enabled exactly when the target answers the action. */
	check([plainItem isEnabled] == YES, "a target with no validator is enabled when it ANSWERS the action");
	{
		NSMenuItem *dead = [menu itemAtIndex:2];

		check([dead isEnabled] == NO, "and disabled when it does NOT");
	}

	/* 4. NO TARGET MEANS THE RESPONDER CHAIN, and with NOBODY in it the item is DISABLED — an enabled item whose
	 * action nobody answers is a promise the menu cannot keep. (7 below gives the chain a first responder that
	 * DOES answer, which is the other half of the same rule.) */
	[noTarget setEnabled:YES];
	[menu update];
	check([noTarget isEnabled] == NO, "an item with NO target is DISABLED when nobody in the chain answers it");

	/* 5. THE DEFAULT CHECKMARK: an item ON with no state image of its own. */
	{
		NSMenu *m = [[NSMenu alloc] initWithTitle:@"Check"];
		NSMenuView *view;
		NSBitmapImageRep *rep;
		NSMenuItem *on;

		on = [[NSMenuItem alloc] initWithTitle:@"Show Grid" action:NULL keyEquivalent:@""];
		[on setState:NSOnState];
		check([on onStateImage] == nil, "the item has NO state image of its own");
		[m addItem:on];
		[on release];

		rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
		view = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		[view setMenu:m];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
		[view drawRect:[view bounds]];
		check(band_ink(rep, 0, 20, 0.5) > 0, "an item that is ON DRAWS a checkmark in the state column, with no image");
	}

	/* 6. A DISABLED TITLE IS DIMMED. Two identical items, one enabled and one not: the disabled title's ink is
	 * the quiet grey, so it has pixels in the mid range and the enabled one has near-black. */
	{
		NSMenuItemCell *en = [[NSMenuItemCell alloc] initTextCell:@""];
		NSMenuItemCell *dis = [[NSMenuItemCell alloc] initTextCell:@""];
		NSMenuItem *a = [[NSMenuItem alloc] initWithTitle:@"Save a Copy" action:NULL keyEquivalent:@""];
		NSMenuItem *b = [[NSMenuItem alloc] initWithTitle:@"Save a Copy" action:NULL keyEquivalent:@""];
		NSBitmapImageRep *er = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
		NSBitmapImageRep *dr = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
		NSRect frame = NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H);
		int en_dark, dis_dark;

		[b setEnabled:NO];
		[en setMenuItem:a];
		[dis setMenuItem:b];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:er]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:frame] fill];
		[en drawTitleWithFrame:frame inView:nil];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:dr]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:frame] fill];
		[dis drawTitleWithFrame:frame inView:nil];
		/* "DARK" HERE IS NEAR-BLACK: the enabled item has it, the disabled one is grey and does not. */
		en_dark = band_ink(er, 0, W, 0.25);
		dis_dark = band_ink(dr, 0, W, 0.25);
		check(en_dark > 0, "an enabled title draws near-black ink");
		check(dis_dark == 0, "and a DISABLED title is drawn in the quiet grey instead, not near-black");
		printf("  (note: near-black ink — enabled %d, disabled %d)\n", en_dark, dis_dark);
	}

	/* 7. THE RESPONDER CHAIN: a nil-target item is validated against WHOEVER WOULD RECEIVE ITS ACTION. */
	{
		NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 100.0, 100.0)
						 styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
		AGValidatingChainView *view = [[AGValidatingChainView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
		NSMenu *chainMenu = [[NSMenu alloc] initWithTitle:@"Chain"];
		NSMenuItem *chainItem = [[NSMenuItem alloc] initWithTitle:@"Do It"
								  action:@selector(chainAction:) keyEquivalent:@""];

		[w setContentView:view];
		[[NSApplication sharedApplication] cg_addWindow:w];	/* makes it the KEY window */
		[chainMenu addItem:chainItem];
		[chainItem release];

		/* 7a. The first responder answers the action and does not object. */
		[w makeFirstResponder:view];
		view->allow = YES;
		[chainMenu update];
		check([chainItem isEnabled], "a nil-target item is ENABLED when the FIRST RESPONDER answers its action");
		check([chainMenu performActionForItemAtIndex:0], "and dispatching it REACHES the responder chain");
		check(view->calls == 1, "and the first responder's action actually ran");

		/* 7b. The same responder VALIDATES it away — enabled is the validator's to say, not the action's. */
		view->allow = NO;
		[chainMenu update];
		check([chainItem isEnabled] == NO,
		      "and DISABLED when the first responder's `-validateMenuItem:` says no");

		/* 7c. Nothing in the chain answers it at all: the item is disabled, because an enabled item nobody can
		 * perform is a promise the menu cannot keep. THE OLD RESPONDER HAS TO GO FIRST — a view that does not accept
		 * the keyboard cannot displace one that does, so leaving the previous one in place would make this case pass
		 * because the OLD first responder still answered rather than because nothing did. */
		{
			NSView *dead = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];

			[w makeFirstResponder:nil];
			[w setContentView:dead];
			[w makeFirstResponder:dead];
			[chainMenu update];
			check([chainItem isEnabled] == NO, "and DISABLED when NOTHING in the chain answers it");
			[dead release];
		}
	}

	/* 8. A ROW THAT CANNOT BE CHOSEN TAKES NO HIGHLIGHT. */
	{
		NSMenu *m = [[NSMenu alloc] initWithTitle:@"Hover"];
		NSMenuItem *on = [[NSMenuItem alloc] initWithTitle:@"On" action:@selector(action:) keyEquivalent:@""];
		NSMenuItem *off = [[NSMenuItem alloc] initWithTitle:@"Off" action:@selector(action:) keyEquivalent:@""];
		NSMenuItem *sep = [NSMenuItem separatorItem];

		[m addItem:on];
		[m addItem:off];
		[m addItem:sep];
		[off setEnabled:NO];
		check([m cg_itemTakesHighlight:on], "an ENABLED row takes the highlight");
		check(![m cg_itemTakesHighlight:off], "a DISABLED row takes NONE");
		check(![m cg_itemTakesHighlight:sep], "and neither does a SEPARATOR");
		check(![m cg_itemTakesHighlight:nil], "and neither does nothing at all");
	}

	printf("menu_validation: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
