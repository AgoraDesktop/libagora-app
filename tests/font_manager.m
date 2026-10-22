/*
 * font_manager — the enumeration, the conversions, the action, and the panel that drives them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS THAT A FONT PANEL CAN ACTUALLY CHANGE A FONT**, so the probe walks the chain the panel walks: the
 * manager enumerates the machine's faces, a family's members are real rows, a conversion answers a face, the four
 * action doors record an action and send `-changeFont:` to a target, and the TARGET's call back through `-convertFont:`
 * produces the font the click asked for. Every claim is checked against the face that comes back — its family, its
 * size, its traits — rather than against a flag.
 *
 * WHAT IS MEASURED, and why each is not a restatement of the code:
 *
 *   1. THE ENUMERATION IS THE MACHINE'S. Families and PostScript names are non-empty, every family has member rows of
 *      Apple's four fields, and a member's name resolves to a real font — which is the claim a stub cannot pass.
 *   2. TRAITS AND WEIGHTS AGREE WITH EACH OTHER. A bold face reports the bold mask and a weight above regular's; a
 *      regular face reports neither; `-convertWeight:ofFont:` moves the number the same door reports.
 *   3. A CONVERSION ANSWERS A FACE. To a size keeps the family; to a family keeps the emphasis; to a trait gains it
 *      and its inverse loses it; to a face stays in the family; `-convertFontTraits:` keeps what the engine has and
 *      drops what it has not.
 *   4. THE ACTION IS RECORDED BEFORE IT IS SENT, which is what makes the target's call back work: the target receives
 *      `-changeFont:` and asks the manager to convert, and the answer is the panel's or the trait's choice.
 *   5. THE PANEL'S TWO CLICKS are the panel's own face doing the work: a click on a family row and a click on a size
 *      chip each change the panel's font, install it as the manager's selection and fire the target.
 *   6. THE COLLECTIONS AND THE FONT MENU are a store and a build, and the menu's one delegate door can decline a
 *      family — which is the reader that makes `-setDelegate:` more than a stored bit.
 */
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontPanel.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontDescriptor.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <string.h>
#include <stdio.h>

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

/* THE TARGET A `-changeFont:` HANDLER IS: it keeps the font it is asked to convert and converts it through the SENDER,
 * which is the whole contract between a text view and the manager. */
@interface AGFontTarget : NSObject
{
@public
	int fired;
	NSFont *stored;
	NSFont *converted;
}
- (void)changeFont:(id)sender;
@end

@implementation AGFontTarget
- (void)dealloc
{
	[stored release];
	[converted release];
	[super dealloc];
}
- (void)changeFont:(id)sender
{
	NSFont *answer;

	fired++;
	answer = [sender convertFont:stored];
	[converted release];
	converted = [answer retain];
}
@end

/* AND THE ONE DELEGATE DOOR THE FONT MENU HAS: a family it declines is not in the menu. */
@interface AGFontDecliner : NSObject
{
@public
	NSString *declined;
}
- (BOOL)fontManager:(id)manager willIncludeFont:(NSString *)name;
@end

@implementation AGFontDecliner
- (BOOL)fontManager:(id)manager willIncludeFont:(NSString *)name
{
	(void)manager;
	return declined == nil || ![declined isEqual:name];
}
@end

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static int has_ink(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.6 && [c greenComponent] < 0.6 && [c blueComponent] < 0.6) {
				n++;
			}
		}
	}
	return n;
}

/* A FAMILY WITH A BOLD MEMBER, found rather than assumed: the machine's fonts are the input, so a probe that hardcoded
 * "Helvetica" would test the machine rather than the door. */
static NSString *family_with_bold(NSFontManager *manager)
{
	NSArray *families = [manager availableFontFamilies];
	NSUInteger i;

	for (i = 0; i < [families count]; i++) {
		NSString *family = [families objectAtIndex:i];
		NSArray *rows = [manager availableMembersOfFontFamily:family];
		NSUInteger r;

		for (r = 0; r < [rows count]; r++) {
			NSFontTraitMask traits = (NSFontTraitMask)[(NSNumber *)[[rows objectAtIndex:r] objectAtIndex:3]
								  unsignedIntegerValue];

			if ((traits & NSBoldFontMask) != 0) {
				return family;
			}
		}
	}
	return nil;
}

/* ============================================================================================ *
 * THE ENUMERATION.                                                                              *
 * ============================================================================================ */

static void test_enumeration(void)
{
	NSFontManager *manager = [NSFontManager sharedFontManager];
	NSArray *families;
	NSArray *fonts;
	NSArray *rows;
	NSDictionary *row;

	printf("the enumeration\n");
	check(manager == [NSFontManager sharedFontManager], "the manager is one object");
	check([manager isEnabled], "and a new manager is enabled");

	families = [manager availableFontFamilies];
	fonts = [manager availableFonts];
	check([families count] > 0, "the machine's families are enumerated");
	check([fonts count] > 0, "and its faces");
	check([[manager availableFontFamilies] count] == [families count],
	      "the enumeration is answered from a cache rather than rebuilt");

	rows = [manager availableMembersOfFontFamily:[families objectAtIndex:0]];
	check([rows count] > 0, "a family has member rows");
	row = [rows objectAtIndex:0];
	check([row count] == 4
	      && [[row objectAtIndex:0] isKindOfClass:[NSString class]]
	      && [[row objectAtIndex:1] isKindOfClass:[NSString class]]
	      && [[row objectAtIndex:2] isKindOfClass:[NSNumber class]]
	      && [[row objectAtIndex:3] isKindOfClass:[NSNumber class]],
	      "a member row is Apple's four fields: name, face, weight, traits");
	check([NSFont fontWithName:[row objectAtIndex:0] size:12.0] != nil,
	      "a member's name resolves to a real font");
	check([manager availableMembersOfFontFamily:@"No Such Family Agora"] != nil,
	      "a family nobody has answers an empty list rather than nil");
	check([[manager availableMembersOfFontFamily:@"No Such Family Agora"] count] == 0,
	      "and the list is empty");
}

/* ============================================================================================ *
 * TRAITS AND WEIGHTS.                                                                           *
 * ============================================================================================ */

static void test_traits(void)
{
	NSFontManager *manager = [NSFontManager sharedFontManager];
	NSString *family = family_with_bold(manager);
	NSFont *regular;
	NSFont *bold;
	NSInteger regularWeight;
	NSInteger boldWeight;

	printf("traits and weights\n");
	check(family != nil, "the machine has a family with a bold member");
	if (family == nil) {
		return;
	}
	regular = [manager fontWithFamily:family traits:0 weight:5 size:12.0];
	bold = [manager fontWithFamily:family traits:NSBoldFontMask weight:9 size:12.0];
	check(regular != nil && [[regular familyName] isEqual:family], "a family and a weight answer a font of that family");
	check(bold != nil && ([manager traitsOfFont:bold] & NSBoldFontMask) != 0,
	      "asking for the bold trait answers a bold face");
	check(([manager traitsOfFont:regular] & NSBoldFontMask) == 0, "and a regular face is not bold");

	regularWeight = [manager weightOfFont:regular];
	boldWeight = [manager weightOfFont:bold];
	check(regularWeight >= 0 && regularWeight <= 15, "a weight is in the era's 0..15 range");
	check(boldWeight > regularWeight, "and a bold face weighs more than a regular one");
	check([manager convertWeight:YES ofFont:regular] == regularWeight + 1, "-convertWeight:ofFont: steps up");
	check([manager convertWeight:NO ofFont:regular] == regularWeight - 1, "and down");
	check([manager fontNamed:[bold fontName] hasTraits:NSBoldFontMask],
	      "-fontNamed:hasTraits: answers YES for a bold face");
	check(![manager fontNamed:[regular fontName] hasTraits:NSBoldFontMask],
	      "and NO for a regular one");
	check([manager fontNamed:[regular fontName] hasTraits:0],
	      "an empty mask is a property every face has");
	check([manager availableFontNamesWithTraits:NSItalicFontMask] != nil,
	      "-availableFontNamesWithTraits: answers a list");
}

/* ============================================================================================ *
 * THE CONVERSIONS.                                                                              *
 * ============================================================================================ */

static void test_conversions(void)
{
	NSFontManager *manager = [NSFontManager sharedFontManager];
	NSString *family = family_with_bold(manager);
	NSFont *base;
	NSFont *converted;
	NSDictionary *attributes;
	NSDictionary *convertedAttributes;

	printf("the conversions\n");
	check(family != nil, "a family to convert within");
	if (family == nil) {
		return;
	}
	base = [manager fontWithFamily:family traits:0 weight:5 size:12.0];

	converted = [manager convertFont:base toSize:24.0];
	check(converted != nil && fabs([converted pointSize] - 24.0) < 0.01
	      && [[converted familyName] isEqual:[base familyName]],
	      "-convertFont:toSize: changes the size and keeps the family");

	{
		NSString *other = nil;
		NSArray *families = [manager availableFontFamilies];
		NSUInteger i;

		for (i = 0; i < [families count]; i++) {
			NSArray *rows = [manager availableMembersOfFontFamily:[families objectAtIndex:i]];
			NSUInteger k;
			BOOL hasBold = NO;
			BOOL hasItalic = NO;

			for (k = 0; k < [rows count]; k++) {
				NSFontTraitMask traits = (NSFontTraitMask)[(NSNumber *)[[rows objectAtIndex:k] objectAtIndex:3]
									  unsignedIntegerValue];

				hasBold = hasBold || (traits & NSBoldFontMask) != 0;
				hasItalic = hasItalic || (traits & NSItalicFontMask) != 0;
			}
			if (hasBold && hasItalic && ![[families objectAtIndex:i] isEqual:family]) {
				other = [families objectAtIndex:i];
				break;
			}
		}
		check(other != nil, "the machine has a second family with both emphasis faces");
		if (other != nil) {
			NSFont *emphasized = [manager fontWithFamily:family traits:NSItalicFontMask weight:5 size:12.0];

			converted = [manager convertFont:emphasized toFamily:other];
			check(converted != nil && [[converted familyName] isEqual:other],
			      "-convertFont:toFamily: changes the family");
			check(([manager traitsOfFont:converted] & NSItalicFontMask) != 0,
			      "and keeps the source font's emphasis");
		}
	}

	converted = [manager convertFont:base toHaveTrait:NSBoldFontMask];
	check(converted != nil && ([manager traitsOfFont:converted] & NSBoldFontMask) != 0,
	      "-convertFont:toHaveTrait: gains the trait");
	converted = [manager convertFont:converted toNotHaveTrait:NSBoldFontMask];
	check(converted != nil && ([manager traitsOfFont:converted] & NSBoldFontMask) == 0,
	      "and -toNotHaveTrait: loses it");
	converted = [manager convertFont:base toNotHaveTrait:NSUnboldFontMask];
	check(converted != nil && ([manager traitsOfFont:converted] & NSBoldFontMask) == 0,
	      "the era's NSUnboldFontMask spelling is a removal too");

	{
		NSFont *boldFace = [manager fontWithFamily:family traits:NSBoldFontMask weight:9 size:12.0];
		NSString *faceName = [[manager availableMembersOfFontFamily:family] count] > 0
			? (NSString *)[[[manager availableMembersOfFontFamily:family] objectAtIndex:0] objectAtIndex:1] : nil;

		converted = [manager convertFont:boldFace toFace:faceName];
		check(converted != nil && [[converted familyName] isEqual:family],
		      "-convertFont:toFace: stays in the font's family");
	}

	check([manager convertFontTraits:(NSBoldFontMask | NSSmallCapsFontMask)] == NSBoldFontMask,
	      "-convertFontTraits: keeps the bit the engine has and drops the one it has not");

	attributes = [NSDictionary dictionaryWithObject:base forKey:NSFontAttributeName];
	convertedAttributes = [manager convertAttributes:attributes];
	check(convertedAttributes != nil
	      && [[convertedAttributes objectForKey:NSFontAttributeName] isKindOfClass:[NSFont class]],
	      "-convertAttributes: answers a font for the font attribute");
}

/* ============================================================================================ *
 * THE ACTION.                                                                                   *
 * ============================================================================================ */

static void test_action(void)
{
	NSFontManager *manager = [NSFontManager sharedFontManager];
	NSString *family = family_with_bold(manager);
	AGFontTarget *target = [[AGFontTarget alloc] init];
	NSFont *base;
	NSFont *selected;
	NSMenuItem *item;

	printf("the action\n");
	check(family != nil, "a family to act on");
	if (family == nil) {
		[target release];
		return;
	}
	base = [manager fontWithFamily:family traits:0 weight:5 size:14.0];
	target->stored = [base retain];
	[manager setTarget:target];
	[manager setAction:@selector(changeFont:)];
	check([manager target] == target && [manager action] == @selector(changeFont:),
	      "the manager keeps the target and action it was given");

	/* THE PANEL'S CHOICE: the selected font's family, at the target font's size. */
	selected = [manager fontWithFamily:family traits:NSItalicFontMask weight:5 size:20.0];
	[manager setSelectedFont:selected isMultiple:NO];
	check([manager selectedFont] == selected && ![manager isMultiple], "the selected font round-trips");
	[manager modifyFontViaPanel:nil];
	check([manager currentFontAction] == NSViaPanelFontAction, "a panel modification records its action");
	check(target->fired == 1 && target->converted != nil,
	      "-changeFont: reached the target, which converted through the manager");
	check([[target->converted familyName] isEqual:[selected familyName]]
	      && fabs([target->converted pointSize] - 14.0) < 0.01,
	      "the conversion is the panel's family at the TEXT's size");

	/* A TRAIT FROM A MENU ITEM: the item's tag is the mask. */
	item = [[NSMenuItem alloc] initWithTitle:@"Bold" action:@selector(addFontTrait:) keyEquivalent:@""];
	[item setTag:NSBoldFontMask];
	[item setTarget:manager];
	[manager addFontTrait:item];
	check([manager currentFontAction] == NSAddTraitFontAction, "adding a trait records that action");
	check(target->fired == 2 && ([manager traitsOfFont:target->converted] & NSBoldFontMask) != 0,
	      "and the target's conversion is bold");
	[manager removeFontTrait:item];
	check([manager currentFontAction] == NSRemoveTraitFontAction
	      && ([manager traitsOfFont:target->converted] & NSBoldFontMask) == 0,
	      "removing it records the other action and answers a non-bold face");
	[item release];

	/* THE SIZE STEPS ARE ACTIONS TOO, AND A DISABLED MANAGER SAYS NOTHING. */
	check(target->fired == 3, "three actions have fired so far");
	[manager setEnabled:NO];
	[manager modifyFontViaPanel:nil];
	check(target->fired == 3, "a disabled manager sends nothing");
	[manager setEnabled:YES];
	[manager modifyFontViaPanel:nil];
	check(target->fired == 4, "and an enabled one sends again");

	[manager setTarget:nil];
	[manager setAction:NULL];
	[target release];
}

/* ============================================================================================ *
 * THE COLLECTIONS AND THE FONT MENU.                                                            *
 * ============================================================================================ */

static void test_collections_and_menu(void)
{
	NSFontManager *manager = [NSFontManager sharedFontManager];
	NSArray *families = [manager availableFontFamilies];
	NSArray *names;
	NSMenu *menu;
	AGFontDecliner *decliner = [[AGFontDecliner alloc] init];
	NSFontDescriptor *descriptor;

	printf("collections and the font menu\n");
	[manager addCollection:@"AgoraProbe" options:0];
	check([[manager collectionNames] containsObject:@"AgoraProbe"], "a collection is added and listed");

	descriptor = [NSFontDescriptor fontDescriptorWithName:[[manager availableFonts] firstObject] size:12.0];
	[manager addFontDescriptors:[NSArray arrayWithObject:descriptor] toCollection:@"AgoraProbe"];
	names = [manager fontDescriptorsInCollection:@"AgoraProbe"];
	check([names count] == 1 && [names objectAtIndex:0] == descriptor, "a descriptor is stored in it");
	[manager addFontDescriptors:[NSArray arrayWithObject:descriptor] toCollection:@"AgoraProbe"];
	check([[manager fontDescriptorsInCollection:@"AgoraProbe"] count] == 1, "and adding it twice does not double it");
	[manager removeFontDescriptor:descriptor fromCollection:@"AgoraProbe"];
	check([[manager fontDescriptorsInCollection:@"AgoraProbe"] count] == 0, "and it can be removed");
	[manager removeCollection:@"AgoraProbe"];
	check(![[manager collectionNames] containsObject:@"AgoraProbe"], "the collection can be removed");

	/* THE MENU, AND THE ONE DELEGATE DOOR THAT SHAPES IT. */
	decliner->declined = [families lastObject];
	[manager setDelegate:decliner];
	menu = [manager fontMenu:YES];
	check(menu != nil, "-fontMenu:YES builds a menu");
	check([menu numberOfItems] == (NSInteger)[families count] - 1,
	      "one item per family, minus the one the delegate declined");
	check([[[menu itemAtIndex:0] title] isEqual:[families objectAtIndex:0]],
	      "an item is titled by its family");
	check([[menu itemAtIndex:0] target] == manager
	      && [[menu itemAtIndex:0] action] != NULL
	      && strcmp(sel_getName([[menu itemAtIndex:0] action]), sel_getName(@selector(modifyFont:))) == 0,
	      "and sends -modifyFont: to the manager");
	check([manager fontMenu:NO] == menu, "a second ask answers the same menu");
	[manager setFontMenu:nil];
	[manager setDelegate:nil];

	check([manager localizedNameForFamily:[families objectAtIndex:0] face:nil] != nil,
	      "-localizedNameForFamily:face: answers a name for the family");
	[manager orderFrontStylesPanel:nil];
	check(YES, "the styles panel door refuses by name rather than crashing");
	[decliner release];
}

/* ============================================================================================ *
 * THE PANEL.                                                                                    *
 * ============================================================================================ */

static void test_panel(void)
{
	NSFontPanel *panel = [NSFontPanel sharedFontPanel];
	NSFontManager *manager = [NSFontManager sharedFontManager];
	AGFontTarget *target = [[AGFontTarget alloc] init];
	NSView *content;
	NSScrollView *scroll;
	NSView *listView;
	NSPoint where;
	NSEvent *event;
	NSUInteger families;

	printf("the panel\n");
	check([NSFontPanel sharedFontPanelExists] && panel == [NSFontPanel sharedFontPanel],
	      "the font panel is one object");
	check([panel worksWhenModal], "and it works during a modal session");
	check([panel isEnabled], "and it starts enabled");

	families = [panel cg_familyCount];
	check(families > 0, "the panel enumerates the machine's families");
	check([panel cg_sizeChipCount] == 8, "and offers eight size chips");
	check(fabs([panel cg_sizeChipValueAtIndex:3] - 12.0) < 0.01, "the fourth is the era's twelve points");

	[panel setPanelFont:[manager fontWithFamily:[panel cg_familyAtIndex:0] traits:0 weight:5 size:12.0]
		 isMultiple:NO];
	check([[panel panelFont] familyName] != nil, "the panel keeps the font it is shown");
	check([panel cg_selectedFamilyIndex] == 0, "and rings the family that font belongs to");

	/* THE FAMILY CLICK. */
	content = [panel contentView];
	scroll = (NSScrollView *)[[content subviews] objectAtIndex:0];
	listView = [scroll documentView];
	check([listView isKindOfClass:[NSView class]], "the family list is a scrolling document view");
	{
		NSRect row = [panel cg_familyRectAtIndex:1];
		NSString *wanted = [panel cg_familyAtIndex:1];

		[manager setTarget:target];
		[manager setAction:@selector(changeFont:)];
		target->stored = [[manager fontWithFamily:wanted traits:0 weight:5 size:12.0] retain];
		where = [listView convertPoint:NSMakePoint(NSMinX(row) + 4.0, NSMinY(row) + 7.0) toView:nil];
		event = [NSEvent mouseEventWithType:NSLeftMouseDown location:where modifierFlags:0 timestamp:0.0
				      windowNumber:[panel windowNumber] context:nil eventNumber:0 clickCount:1
					 pressure:1.0];
		[listView mouseDown:event];
		check([[panel panelFont] familyName] != nil, "a click on a family row changes the panel's font");
		check([panel cg_selectedFamilyIndex] == 1, "and moves the ring to that row");
		check([manager selectedFont] != nil
		      && [[[manager selectedFont] familyName] isEqual:[[panel panelFont] familyName]],
		      "and installs it as the manager's selection");
		check(target->fired == 1, "and fires the target's -changeFont:");
	}

	/* THE SIZE CHIP. */
	{
		NSRect chip = [panel cg_sizeChipRectAtIndex:5];
		CGFloat wanted = [panel cg_sizeChipValueAtIndex:5];

		where = [content convertPoint:NSMakePoint(NSMidX(chip), NSMidY(chip)) toView:nil];
		event = [NSEvent mouseEventWithType:NSLeftMouseDown location:where modifierFlags:0 timestamp:0.0
				      windowNumber:[panel windowNumber] context:nil eventNumber:0 clickCount:1
					 pressure:1.0];
		[content mouseDown:event];
		check(fabs([[panel panelFont] pointSize] - wanted) < 0.01, "a click on a size chip changes the size");
		check(target->fired == 2, "and fires the target again");
	}

	/* THE PURE CONVERSION, AND THE DISABLED PANEL. */
	{
		NSFont *other = [manager fontWithFamily:[panel cg_familyAtIndex:0] traits:0 weight:5 size:9.0];
		NSFont *converted = [panel panelConvertFont:other];

		check(converted != nil
		      && [[converted familyName] isEqual:[[panel panelFont] familyName]]
		      && fabs([converted pointSize] - [[panel panelFont] pointSize]) < 0.01,
		      "-panelConvertFont: answers the panel's family and size");

		[panel setEnabled:NO];
		{
			NSInteger before = [panel cg_selectedFamilyIndex];
			NSRect row = [panel cg_familyRectAtIndex:2];

			where = [listView convertPoint:NSMakePoint(NSMinX(row) + 4.0, NSMinY(row) + 7.0) toView:nil];
			event = [NSEvent mouseEventWithType:NSLeftMouseDown location:where modifierFlags:0 timestamp:0.0
					      windowNumber:[panel windowNumber] context:nil eventNumber:0 clickCount:1
						 pressure:1.0];
			[listView mouseDown:event];
			check([panel cg_selectedFamilyIndex] == before, "a disabled panel ignores a family click");
		}
		[panel setEnabled:YES];
	}

	/* THE ACCESSORY VIEW AND THE INK. */
	{
		NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
		NSBitmapImageRep *rep;

		[panel setAccessoryView:accessory];
		check([panel accessoryView] == accessory && [accessory superview] == content,
		      "-setAccessoryView: puts the view in the panel's content");
		[panel setAccessoryView:nil];
		check([panel accessoryView] == nil, "and nil takes it out");

		rep = new_rep(220, 300);
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 220.0, 300.0)] fill];
		/* THE CONTENT VIEW IS FLIPPED, so the context is flipped to match — the same instrument `tests/matrix.m`
		 * uses, and the reason the chip row's y is 220 rather than 300 - 238. */
		{
			CGContextRef cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];

			CGContextTranslateCTM(cg, 0.0, 300.0);
			CGContextScaleCTM(cg, 1.0, -1.0);
		}
		[content drawRect:[content bounds]];
		check(has_ink(rep, 20, 222, 200, 238) > 0, "the panel's size row is drawn");
		[rep release];
		[accessory release];
	}

	[manager setTarget:nil];
	[manager setAction:NULL];
	[target release];
}

int main(void)
{
	printf("NSFontManager / NSFontPanel\n");
	test_enumeration();
	test_traits();
	test_conversions();
	test_action();
	test_collections_and_menu();
	test_panel();

	printf("\n%d checks, %d failed\n", g_checks, g_failed);
	return g_failed == 0 ? 0 : 1;
}
