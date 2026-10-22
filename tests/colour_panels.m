/*
 * colour_panels — a colour list, a well, the shared panel and the picker it hosts.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE SLICE'S CLAIM IS A CHAIN, SO THE PROBE WALKS IT.** A list is a file (`NSColorList`), a well is a control that
 * shows a colour and hands the panel its target (`NSColorWell`), the panel is one shared window with a face
 * (`NSColorPanel`), and the face's chooser is a picker with a grid that sets the panel's colour (`NSColorPicker`).
 * Each link is asserted on its own AND the chain is asserted end to end: a list written to the standard directory is
 * found by `+colorListNamed:`, which is what `+[NSColor colorWithCatalogName:colorName:]` — a refusal until this slice
 * — now reads.
 *
 * WHAT IS MEASURED RATHER THAN ASSUMED:
 *
 *   1. The list's ORDER survives a save and a load, because a palette that reorders itself between launches is the
 *      bug a dictionary-backed implementation ships.
 *   2. A system list is NOT editable and its three mutators refuse; a user list is.
 *   3. The well's swatch is the colour it holds, in PIXELS; activating makes it the panel's target; the panel's
 *      colour coming back through `-takeColorFrom:` fires the well's own action.
 *   4. The panel is ONE object, its modes are the era's eight, its chips are one per offered mode, and a click on a
 *      chip changes the mode.
 *   5. The picker's grid is generated, its first cell is an attached list's first colour, and a click in a cell sets
 *      the panel's colour to that cell's colour.
 *   6. The swatch and the alpha ramp are drawn where the content view says they are, and the ramp runs transparent to
 *      opaque.
 *   7. `-dragColor:withEvent:fromView:` puts the colour on `NSDragPboard` under `NSColorPboardType`, and the class's
 *      own `+colorFromPasteboard:` reads it back — the session itself cannot begin without a window, which is the
 *      documented answer and asserted as NO.
 */
#import <AppKit/NSColorList.h>
#import <AppKit/NSColorWell.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSColorPicker.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

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

static int colour_is(NSColor *c, CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
	return c != nil
		&& fabs([c redComponent] - r) < 0.01
		&& fabs([c greenComponent] - g) < 0.01
		&& fabs([c blueComponent] - b) < 0.01
		&& fabs([c alphaComponent] - a) < 0.01;
}

/* A TARGET THAT COUNTS, so "the action was sent" is a number rather than an assumption. */
@interface AGColorTarget : NSObject
{
@public
	int fired;
}
- (void)fired:(id)sender;
@end

@implementation AGColorTarget
- (void)fired:(id)sender
{
	(void)sender;
	fired++;
}
@end

/* ---- THE INK'S INSTRUMENTS ------------------------------------------------------------------------- */

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static int pixel_is(NSBitmapImageRep *rep, int x, int y, NSColor *want)
{
	NSColor *c = [rep colorAtX:x y:y];

	return c != nil && want != nil
		&& fabs([c redComponent] - [want redComponent]) < 0.04
		&& fabs([c greenComponent] - [want greenComponent]) < 0.04
		&& fabs([c blueComponent] - [want blueComponent]) < 0.04;
}

/* DRAW A VIEW that is flipped, into a rep, with the context flipped to match — the same instrument
 * `tests/matrix.m` uses, for the same reason. */
static NSBitmapImageRep *draw_flipped(NSView *view, int w, int h, BOOL flip)
{
	NSBitmapImageRep *rep = new_rep(w, h);

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
	if (flip) {
		CGContextRef cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];

		CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
		CGContextScaleCTM(cg, 1.0, -1.0);
	}
	[view drawRect:[view bounds]];
	return rep;
}

/* ============================================================================================ *
 * THE LIST.                                                                                     *
 * ============================================================================================ */

static void test_color_list(void)
{
	NSColorList *list = [[NSColorList alloc] initWithName:@"AgoraProbe"];
	NSColorList *loaded;
	NSString *path = @"/tmp/agora-colour-list-probe.clr";
	NSArray *keys;

	printf("colour list\n");
	check([[list name] isEqual:@"AgoraProbe"] && [list isEditable] && [[list allKeys] count] == 0,
	      "a list made here is named, editable and empty");

	[list setColor:[NSColor redColor] forKey:@"Red"];
	[list setColor:[NSColor greenColor] forKey:@"Green"];
	[list setColor:[NSColor blueColor] forKey:@"Blue"];
	keys = [list allKeys];
	check([keys count] == 3 && [[keys objectAtIndex:0] isEqual:@"Red"] && [[keys objectAtIndex:2] isEqual:@"Blue"],
	      "keys are answered in INSERTION order, not hash order");
	check(colour_is([list colorWithKey:@"Green"], 0.0, 1.0, 0.0, 1.0), "-colorWithKey: answers the colour set");

	[list insertColor:[NSColor whiteColor] key:@"White" atIndex:1];
	keys = [list allKeys];
	check([[keys objectAtIndex:1] isEqual:@"White"], "-insertColor:key:atIndex: places the key");
	[list setColor:[NSColor yellowColor] forKey:@"White"];
	check([[list colorWithKey:@"White"] isEqual:[NSColor yellowColor]]
	      && [[[list allKeys] objectAtIndex:1] isEqual:@"White"],
	      "replacing a key keeps its position");
	[list removeColorWithKey:@"White"];
	check([[list allKeys] count] == 3 && [list colorWithKey:@"White"] == nil, "-removeColorWithKey: removes it");

	/* AND THE FILE. */
	check([list writeToFile:path], "-writeToFile: writes the property list");
	loaded = [[NSColorList alloc] initWithName:@"AgoraProbe" fromFile:path];
	check(loaded != nil && [[loaded allKeys] count] == 3, "a list reads back from the file");
	check([[[loaded allKeys] objectAtIndex:0] isEqual:@"Red"]
	      && colour_is([loaded colorWithKey:@"Blue"], 0.0, 0.0, 1.0, 1.0),
	      "and it comes back with the same order and the same colours");
	[loaded removeFile];
	check(![[NSFileManager defaultManager] fileExistsAtPath:path], "-removeFile deletes it");
	[loaded release];

	/* A FILE OF ANOTHER SHAPE IS NOT A LIST. */
	[@"not a plist" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	loaded = [[NSColorList alloc] initWithName:@"Broken" fromFile:path];
	check(loaded == nil, "a file that is not a colour list answers nil rather than an empty list");
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

	check([[NSColorList availableColorLists] isKindOfClass:[NSArray class]],
	      "+availableColorLists answers an array (empty is a real answer)");
	check([NSColorList colorListNamed:@"NoSuchListAgora"] == nil, "+colorListNamed: answers nil for a name nobody has");
	[list release];
}

/* THE CHAIN: A LIST IN THE USER'S DIRECTORY, FOUND BY NAME, READ BY `NSColor`. */
static void test_catalog(void)
{
	NSColorList *list = [[NSColorList alloc] initWithName:@"AgoraCatalogProbe"];
	NSColorList *found;
	NSColor *colour;

	printf("the catalog chain\n");
	[list setColor:[NSColor colorWithCalibratedRed:0.25 green:0.5 blue:0.75 alpha:1.0] forKey:@"Slate"];
	check([list writeToFile:nil], "a list with no path writes to ~/Library/Colors");
	found = [NSColorList colorListNamed:@"AgoraCatalogProbe"];
	check(found != nil && [[[found allKeys] firstObject] isEqual:@"Slate"],
	      "+colorListNamed: finds it in the standard directory");

	colour = [NSColor colorWithCatalogName:@"AgoraCatalogProbe" colorName:@"Slate"];
	check(colour_is(colour, 0.25, 0.5, 0.75, 1.0),
	      "+[NSColor colorWithCatalogName:colorName:] reads the list and answers the colour");
	check([NSColor colorWithCatalogName:@"AgoraCatalogProbe" colorName:@"Nope"] == nil,
	      "a key the list does not have answers nil");
	check([NSColor colorWithCatalogName:@"NoSuchListAgora" colorName:@"Slate"] == nil,
	      "a list nobody has answers nil");
	[list removeFile];
	check([NSColorList colorListNamed:@"AgoraCatalogProbe"] == nil, "removing the file removes the list");
	[list release];
}

/* ============================================================================================ *
 * THE WELL.                                                                                     *
 * ============================================================================================ */

static void test_color_well(void)
{
	NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 44.0, 24.0)];
	NSColorPanel *panel;
	AGColorTarget *target = [[AGColorTarget alloc] init];
	NSBitmapImageRep *rep;

	printf("colour well\n");
	check([well isBordered] && ![well isActive], "a new well is bordered and inactive");
	check(colour_is([well color], 1.0, 1.0, 1.0, 1.0), "and holds white");

	[well setColor:[NSColor redColor]];
	rep = draw_flipped(well, 44, 24, NO);
	check(pixel_is(rep, 22, 12, [NSColor redColor]), "-drawRect: paints the colour it holds");
	[rep release];
	check(![NSColorPanel sharedColorPanelExists], "a well alone does not create the shared panel");

	/* ACTIVATION. */
	[well activate:nil];
	panel = [NSColorPanel sharedColorPanel];
	check([NSColorPanel sharedColorPanelExists] && panel != nil && [panel isEqual:[NSColorPanel sharedColorPanel]],
	      "activating a well creates the ONE shared panel");
	check([well isActive], "and the well is active");
	check([panel target] == well, "the panel's target is the active well");
	/* **THE SELECTORS ARE COMPARED BY NAME, NOT BY POINTER.** This runtime's selectors are TYPED, so the same
	 * selector reached from two compilation units need not be the same pointer — MEASURED here, where both names
	 * printed `takeColorFrom:` and `==` answered NO. */
	check([panel action] != NULL && strcmp(sel_getName([panel action]), sel_getName(@selector(takeColorFrom:))) == 0,
	      "and its action is the well's take-colour door");
	check(colour_is([panel color], 1.0, 0.0, 0.0, 1.0), "and the panel shows the well's colour");

	/* THE REPORT BACK. */
	[well setTarget:target];
	[well setAction:@selector(fired:)];
	[panel setColor:[NSColor blueColor]];
	[well takeColorFrom:panel];
	check(colour_is([well color], 0.0, 0.0, 1.0, 1.0), "-takeColorFrom: takes the sender's colour");
	check(target->fired == 1, "and sends the well's own action");

	/* DEACTIVATION GIVES THE PANEL BACK. */
	[well deactivate];
	check(![well isActive] && [panel target] == nil, "-deactivate clears the panel's target when it is this well");

	/* A PANEL TO NOTHING, A CONTINUOUS PANEL SPEAKS ON EVERY CHANGE. */
	[panel setTarget:target];
	[panel setAction:@selector(fired:)];
	[panel setContinuous:YES];
	[panel setColor:[NSColor greenColor]];
	check(target->fired == 2 && [panel isContinuous], "a continuous panel sends its action on every colour change");
	/* **THE PANEL'S TARGET IS NOT RETAINED, SO THE PROBE CLEARS IT BEFORE RELEASING THE TARGET** — which is the same
	 * duty a real caller has: a target that goes away without being cleared leaves the panel sending to freed
	 * storage, and the crash that follows is in the SEND, one test-case later. */
	[panel setTarget:nil];
	[panel setAction:NULL];

	[well release];
	[target release];
}

/* ============================================================================================ *
 * THE PANEL AND THE PICKER.                                                                     *
 * ============================================================================================ */

static void test_panel_face(void)
{
	NSColorPanel *panel = [NSColorPanel sharedColorPanel];
	NSColorWell *other = [[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 20.0)];
	NSColorList *list = [[NSColorList alloc] initWithName:@"AgoraPickerProbe"];
	NSColorPicker *picker;
	NSView *content;
	NSView *pickerView;
	NSBitmapImageRep *rep;
	NSEvent *event;
	NSPoint where;
	NSUInteger i;

	printf("the panel's face\n");
	[panel setShowsAlpha:YES];
	[panel setColor:[NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.6 alpha:0.5]];
	check([panel showsAlpha] && fabs([panel alpha] - 0.5) < 0.01,
	      "the panel's alpha is its colour's alpha component");

	/* THE CHIPS: ONE PER OFFERED MODE, AND THE MODE THE MASK HIDES IS NOT AMONG THEM. */
	check([panel cg_chipCount] == 8, "the default mask offers all eight modes, and each has a chip");
	[NSColorPanel setPickerMask:(NSColorPanelRGBModeMask | NSColorPanelGrayModeMask)];
	check([panel cg_chipCount] == 2, "a narrower mask offers fewer chips");
	[NSColorPanel setPickerMask:NSColorPanelAllModesMask];

	/* A CHIP CLICK CHANGES THE MODE — through the content view's own hit test. */
	content = [panel contentView];
	[panel setMode:NSHSBModeColorPanel];
	check([panel mode] == NSHSBModeColorPanel, "the panel reports the mode it was set to");
	where = [content convertPoint:NSMakePoint(NSMidX([panel cg_chipRectAtIndex:1]),
						  NSMidY([panel cg_chipRectAtIndex:1]))
			       toView:nil];
	event = [NSEvent mouseEventWithType:NSLeftMouseDown location:where modifierFlags:0 timestamp:0.0
			      windowNumber:[panel windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1.0];
	[content mouseDown:event];
	check([panel mode] == NSRGBModeColorPanel, "a click on the second chip selects its mode");

	/* THE PICKER AND ITS GRID. */
	[panel setMode:NSHSBModeColorPanel];
	picker = [panel cg_picker];
	pickerView = [panel cg_pickerView];
	check(picker != nil && [picker colorPanel] == panel, "the panel hosts a picker that knows its panel");
	check(pickerView != nil && NSEqualSizes([pickerView frame].size, [picker minContentSize]),
	      "the picker's view is hosted at the picker's minimum content size");
	check([[picker buttonToolTip] length] > 0, "a picker names its mode's tooltip");
	check([[picker provideNewButtonImage] size].width > 0.0, "a picker provides a chip image");

	/* AN ATTACHED LIST'S COLOURS COME FIRST IN THE GRID. */
	[list setColor:[NSColor colorWithCalibratedRed:0.9 green:0.1 blue:0.2 alpha:1.0] forKey:@"First"];
	[panel attachColorList:list];
	check(colour_is([picker cg_paletteColorAtIndex:0], 0.9, 0.1, 0.2, 1.0),
	      "an attached colour list's first colour is the grid's first cell");
	[panel detachColorList:list];
	check([picker cg_paletteColorAtIndex:0] != nil, "with no list the grid is still full");

	/* AND A CLICK IN A CELL SETS THE PANEL'S COLOUR TO THAT CELL'S COLOUR. */
	{
		NSColor *wanted = [picker cg_paletteColorAtIndex:10];
		NSPoint inside = NSMakePoint((CGFloat)(10 % 8) * 20.0 + 10.0, (CGFloat)(10 / 8) * 20.0 + 10.0);

		where = [pickerView convertPoint:inside toView:nil];
		event = [NSEvent mouseEventWithType:NSLeftMouseDown location:where modifierFlags:0 timestamp:0.0
				      windowNumber:[panel windowNumber] context:nil eventNumber:0 clickCount:1
					 pressure:1.0];
		[pickerView mouseDown:event];
		check(colour_is([panel color], [wanted redComponent], [wanted greenComponent], [wanted blueComponent],
				[wanted alphaComponent]),
		      "a click in a grid cell sets the panel's colour to that cell's colour");
	}

	/* THE SWATCH AND THE RAMP. */
	[panel setColor:[NSColor redColor]];
	[panel setShowsAlpha:YES];
	rep = draw_flipped(content, 220, 236, YES);
	check(pixel_is(rep, 110, 168, [NSColor redColor]), "the swatch band is painted with the panel's colour");
	check(pixel_is(rep, 10, 201, [NSColor whiteColor]), "the alpha ramp's left end is transparent over white");
	check(pixel_is(rep, 210, 201, [NSColor redColor]), "and its right end is the opaque colour");
	[rep release];

	/* THE ACCESSORY VIEW AND THE LIST COUNT. */
	{
		NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

		[panel setAccessoryView:accessory];
		check([panel accessoryView] == accessory && [accessory superview] == content,
		      "-setAccessoryView: puts the caller's view in the panel's content");
		[panel setAccessoryView:nil];
		check([panel accessoryView] == nil && [accessory superview] == nil,
		      "and setting nil takes it out again");
		[accessory release];
	}

	/* THE DRAG'S PASTEBOARD HALF. A SESSION CANNOT BEGIN WITHOUT A WINDOW, AND SAYS SO. */
	{
		NSPasteboard *board = [NSPasteboard pasteboardWithName:NSDragPboard];
		NSColor *dragged = [NSColor colorWithCalibratedRed:0.3 green:0.6 blue:0.9 alpha:1.0];

		[board declareTypes:[NSArray array] owner:nil];
		where = NSMakePoint(0.0, 0.0);
		event = [NSEvent mouseEventWithType:NSLeftMouseDragged location:where modifierFlags:0 timestamp:0.0
				      windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1.0];
		check(![panel dragColor:dragged withEvent:event fromView:other],
		      "-dragColor:withEvent:fromView: answers NO when there is no window to drag from");
		check([[board types] containsObject:NSColorPboardType],
		      "the colour is on the drag pasteboard under NSColorPboardType anyway");
		check(colour_is([NSColor colorFromPasteboard:board], 0.3, 0.6, 0.9, 1.0),
		      "and the class's own pasteboard reader reads it back");
	}

	/* AND TWO WELLS DO NOT FIGHT OVER THE PANEL. */
	[other activate:nil];
	check([panel target] == other, "a second well takes the panel's target");
	[other deactivate];
	check([panel target] == nil, "and deactivating it clears it");
	[other release];
	[list release];
}

/* ============================================================================================ *
 * THE PICKER ON ITS OWN.                                                                        *
 * ============================================================================================ */

static void test_picker(void)
{
	NSColorPanel *panel = [NSColorPanel sharedColorPanel];
	NSColorPicker *picker = [[NSColorPicker alloc] initWithPickerMask:NSColorPanelAllModesMask colorPanel:panel];
	NSButtonCell *cell = [[NSButtonCell alloc] init];
	NSImage *image;

	printf("the picker\n");
	check([picker colorPanel] == panel, "a picker answers the panel it was made for");
	check([picker supportsMode:NSWheelModeColorPanel], "the palette supports every mode");
	check(NSEqualSizes([picker minContentSize], NSMakeSize(160.0, 100.0)), "its minimum content size is the grid's");
	[picker setMode:NSRGBModeColorPanel];
	check([picker currentMode] == NSRGBModeColorPanel && [[picker buttonToolTip] isEqual:@"RGB"],
	      "-setMode: moves the mode and the tooltip with it");
	image = [picker provideNewButtonImage];
	check(image != nil && NSEqualSizes([image size], NSMakeSize(18.0, 18.0)), "the chip image is eighteen points");
	[picker insertNewButtonImage:image in:cell];
	check([cell image] == image, "-insertNewButtonImage:in: puts the image in the caller's cell");

	{
		NSView *view = [picker provideNewView:YES];

		check(view != nil && NSEqualSizes([view frame].size, [picker minContentSize]),
		      "-provideNewView: answers a view at the minimum size");
		check([view isEqual:[picker provideNewView:NO]], "and asks again for the same view rather than a second one");
	}
	[picker release];
	[cell release];
}

int main(void)
{
	printf("NSColorList / NSColorWell / NSColorPanel / NSColorPicker\n");
	test_color_list();
	test_catalog();
	test_color_well();
	test_panel_face();
	test_picker();

	printf("\n%d checks, %d failed\n", g_checks, g_failed);
	return g_failed == 0 ? 0 : 1;
}
