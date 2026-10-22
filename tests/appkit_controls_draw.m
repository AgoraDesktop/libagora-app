/*
 * appkit_controls_draw — a window full of CONTROLS under a real MENU BAR, on a display.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE DEMONSTRATION FOR THE CONTROL LAYER, AND IT IS A DEMONSTRATION RATHER THAN A TEST.** The offscreen
 * `control_ink` test asserts the pixels; this puts the controls in a real window on Agora's window server so what the
 * slice draws can be LOOKED at — and it is what found the subview-placement defect in `NSView -displayRect:`, which
 * no offscreen draw of a single view could have shown.
 *
 * **AND IT SETS A MAIN MENU, WHICH THE FIRST VERSION DID NOT.** A window with controls and no `-setMainMenu:` leaves
 * the bar showing only the server's System menu — the application's own menus are put there BY the application, so a
 * demonstration that never sets one shows no application menus at all. It sets one now, and the two halves
 * demonstrate EACH OTHER: the View menu's "Show Grid" is a CHECKED item whose state is validated against the
 * checkbox below it, "Undo" is DISABLED by the same validator, and the push button TOGGLES the checkbox — so a click
 * on a control changes a menu item, and the menu reports what the control says.
 *
 * **AND IT WEARS A TOOLBAR, WHICH IS THE STRIP THE `NSToolbar` SLICE EXISTS TO SHOW.** The window grows by the band
 * and the controls stay where they were; the items are the SAME actions the menus use ("Show Grid" toggles the
 * checkbox, "Playground" opens the text window, "Action" is the no-op), plus a separator, a flexible space and one
 * disabled item. The three pictures are drawn in this file, so the demonstration needs no icon files and no search
 * path. `tests/toolbar.m` asserts the behaviour; this is where it can be looked at.
 *
 * **AND IT OPENS A TABLE & OUTLINE WINDOW**, from the toolbar's "Table" item, the Data menu, or `--data` on the
 * command line. The left side is an `NSOutlineView` with disclosure triangles and nested levels; the right is an
 * `NSTableView` with three columns, a header and alternating rows. Both are the real classes from the last two
 * slices, not painted pictures of them.
 *
 * **AND THE NEW-CONTROLS STRIP, WHICH IS WHAT THIS REVISION ADDS.** The window's right column now carries every control
 * class the later slices landed, in two columns where the scroll panel used to have the whole height: a
 * continuous `NSLevelIndicator` above the warning threshold and a RATING one, an `NSStepper` with its value beside it,
 * an `NSSecureTextField` and an `NSSearchField`, an `NSDatePicker` in the text-and-stepper style, an `NSProgressIndicator`
 * as a bar with its SPINNER beside it, an `NSBox` with a button inside it, and an `NSTabView` whose two panes are the date
 * picker's TEXT-FIELD and CLOCK-AND-CALENDAR styles. The third face, text-and-stepper, is the picker in the column to the
 * left, so all three are in the window and two of them are one tab click apart. The scroll panel below them is shorter than
 * it was; the values and pictures it makes visible are the point of the change.
 *
 * **AND `--no-playground` IS FOR LOOKING AT THIS WINDOW RATHER THAN THE TEXT.** The playground is mapped last so it is in
 * front, which is right for the text and wrong for the controls it covers — `run-controls.sh --no-playground` leaves it
 * unmapped.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSSlider.h>
#import <AppKit/NSSegmentedControl.h>
#import <AppKit/NSPathControl.h>
#import <AppKit/NSTextField.h>	/* the field CONTROL — a cell, a click, and the window's field editor */
#import <AppKit/NSCell.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/AGChromeTheme.h>	/* the chrome's theme, which this demonstration loads by DEFAULT */
#import <AppKit/NSEvent.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSComboBox.h>	/* the other field with a chip, and the one-triangle mark that tells them apart */
#import <AppKit/NSLevelIndicator.h>	/* the value that becomes a bar, segments or stars, and a colour */
#import <AppKit/NSStepper.h>	/* two arrows, one step, and the value pair a numeric cell owns */
#import <AppKit/NSSecureTextField.h>	/* a field whose ink is bullets */
#import <AppKit/NSSearchField.h>	/* a field with a search chip and a cancel chip */
#import <AppKit/NSProgressIndicator.h>	/* a value as a bar, and a spinner that has no timer here */
#import <AppKit/NSDatePicker.h>	/* a formatted date, and the three frames it can wear */
#import <AppKit/NSBox.h>		/* the titled frame around other views */
#import <AppKit/NSTabView.h>	/* the selection over views, used here to swap two date-picker styles */
#import <AppKit/AGSwitch.h>	/* the tier's own control: a track and a knob, 32 x 20 */
#import <AppKit/NSToolbar.h>	/* the band above the content, and the items in it */
#import <AppKit/NSToolbarItem.h>
#import <AppKit/NSToolbar_internal.h>	/* the band height and view, for the geometry line */
#import <AppKit/NSTableView.h>	/* the cell-based table and the outline that flattens a tree */
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSSplitView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSAttributedString.h>
/* **AND THE TEXT SYSTEM, WHICH IS WHAT THIS DEMONSTRATION NOW HAS TO SHOW.** The store the view reads, the tab stops a
 * `\t` goes to, the attachment that stands for a picture, and the table whose cells are paragraphs. */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextTab.h>
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSTextTable.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSBitmapImageRep.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* **THE PANE'S CARD, WHICH IS THE MOCKUP'S ROUNDED PANEL RATHER THAN A SQUARE SCROLL VIEW.** The split view owns the
 * gutter and its three rings; a pane that wants the white rounded face draws it itself, exactly as an application's
 * content view would. The card fills white, strokes the tier's `#BCBCBC` border, insets its content by one point so
 * the border survives, and CLIPS THE CONTENT to a rounded path in `-displayRect:` — without the clip the content's
 * square corners paint over the card's rounded ones. */
@interface AGDemoPaneView : NSView
{
	NSView *_content;	/* RETAINED, and also retained by the subview list */
}
- (instancetype)initWithFrame:(NSRect)frame content:(NSView *)content;
- (void)cg_drawBorder;
@end

@implementation AGDemoPaneView

- (instancetype)initWithFrame:(NSRect)frame content:(NSView *)content
{
	self = [super initWithFrame:frame];
	if (self != nil) {
		_content = [content retain];
		[self addSubview:_content];
		[self cg_layoutContent];
	}
	return self;
}

- (void)dealloc
{
	[_content release];
	[super dealloc];
}

- (void)cg_layoutContent
{
	[_content setFrame:NSInsetRect([self bounds], 1.0, 1.0)];
}

- (void)setFrame:(NSRect)frame
{
	[super setFrame:frame];
	[self cg_layoutContent];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
	[super resizeSubviewsWithOldSize:oldSize];
	[self cg_layoutContent];
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self bounds], 0.5, 0.5)
							     xRadius:5.0 yRadius:5.0];

	(void)dirtyRect;
	[[NSColor whiteColor] setFill];
	[path fill];
}

/* THE BORDER IS DRAWN AFTER THE CONTENT, NOT BEFORE IT. The card's own `-drawRect:` and its content are both clipped
 * to the INNER rounded path so the content's square corners cannot spill outside the card; drawing the border there
 * would clip the outer edge away with them. It is stroked on top, outside that clip, which is what makes the rounded
 * outline the topmost ink in the pane. */
- (void)cg_drawBorder
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self bounds], 0.5, 0.5)
							     xRadius:5.0 yRadius:5.0];

	[[NSColor controlDarkShadowColor] setStroke];
	[path setLineWidth:1.0];
	[path stroke];
}

- (void)displayRect:(NSRect)rect
{
	CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
	NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self bounds], 1.0, 1.0)
							     xRadius:4.0 yRadius:4.0];

	if (cg != NULL) {
		CGContextSaveGState(cg);
	}
	[clip addClip];
	[super displayRect:rect];
	if (cg != NULL) {
		CGContextRestoreGState(cg);
	}
	[self cg_drawBorder];
}

@end

/* **THE TARGET BOTH HALVES POINT AT.** A menu item's action, a button's action and a validator all end here, which
 * is what makes the checkbox and the View menu one piece of state rather than two that look alike. */
@interface AGControlsController : NSObject <NSToolbarDelegate>
{
@public
	NSButton *checkbox;
	/* **AND THE SLIDER PAIR: the control, and the button whose TITLE is used as a readout.** A slider's whole
	 * difference from a checkbox is that its value MOVES while it is dragged, so the demonstration needs something
	 * that shows a value and not a state — and a button with a changing title is the one such surface this tier has.
	 *
	 * AND THERE ARE TWO SLIDERS RATHER THAN ONE, because the grabber's SHAPE depends on the tick count: with tick
	 * marks to point at it is a teardrop, and without them it is a circle. A demonstration of a rule that shows only
	 * one side of it is a demonstration of half a rule. */
	NSButton *readout;
	NSSlider *slider;
	NSSlider *plain;
	/* **AND THE STEPPER'S READOUT, WHICH IS A LABEL RATHER THAN A BUTTON.** A stepper has no value of its own on screen,
	 * so the number beside it is what makes a press readable; it is a non-editable `NSTextField`, the same shape the data
	 * window's captions use, because this tier's label is a field with its doors turned off. */
	NSTextField *stepperReadout;
	/* **AND THE PLAYGROUND WINDOW, KEPT SO A SECOND CHOICE BRINGS IT FORWARD rather than making another.** */
	NSWindow *_playground;
	/* THE TOOLBAR'S THREE PICTURES, made once in `main` before the toolbar asks for its items. They are borrowed
	 * here — the items retain them when they are set — and they are small enough that a drawing helper is cheaper
	 * than shipping icon files a demonstration would have to find. */
	NSImage *gridIcon;
	NSImage *playgroundIcon;
	NSImage *actionIcon;
	NSImage *tableIcon;
	/* THE TABLE & OUTLINE WINDOW AND THE OBJECTS THAT FEED IT. The table and outline do not retain their data
	 * sources, so the controller keeps them for as long as the window lives. */
	NSWindow *_dataWindow;
	id _tableSource;
	id _outlineSource;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)toggleCheckbox:(id)sender;
- (void)sliderMoved:(id)sender;
- (void)stepperMoved:(id)sender;
- (void)dateChanged:(id)sender;
- (void)noop:(id)sender;
- (void)choiceMade:(id)sender;
- (void)showPlayground:(id)sender;
- (void)showDataViews:(id)sender;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag;
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar;
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
@end

/* ============================================================================================ *
 * THE TEXT PLAYGROUND: A SCROLLABLE, EDITABLE `NSTextView` THAT SHOWS WHAT THE TEXT SLICES DRAW.   *
 *                                                                                                *
 * **IT IS A THING TO PLAY WITH RATHER THAN A TEST.** Type in it, select, click; every feature the *
 * text slices added is in ONE store so the eye can move between them: runs of colour and the two  *
 * rules, a background span, a centred paragraph, tab stops that line a column up, an attachment   *
 * that stands for a picture, and a two-cell table. THE STORE IS THE VIEW'S OWN, reached through   *
 * `-textStorage` — which is the slice this whole playground exists to make visible.              *
 * ============================================================================================ */

/* A PICTURE WITH SOMETHING TO SEE: a small two-tone tile, built in a bitmap and handed to an `NSImage`. An attachment
 * over a blank image would prove the box but show nothing. */
static NSImage *fn_playground_picture(CGFloat w, CGFloat h)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)w
		pixelsHigh:(NSInteger)h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)w * 4 bitsPerPixel:32];
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor colorWithCalibratedRed:0.20 green:0.45 blue:0.85 alpha:1.0] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, w, h)] fill];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(w * 0.25, h * 0.25, w * 0.5, h * 0.5)] fill];
	[image addRepresentation:rep];
	[rep release];
	return [image autorelease];
}

/* **THE TOOLBAR'S PICTURES, DRAWN RATHER THAN FOUND.** A toolbar's icon is the one picture the demonstration would
 * otherwise have to ship as a file, and a file is a path that has to resolve from wherever the binary was run. Three
 * 18-point tiles, one per item, are drawn from the same shapes the rest of this file uses: a grid of rules, three
 * lines of text, and a triangle. The round rect is the button face the rest of the tier's controls wear. */
static NSImage *fn_toolbar_icon(int kind)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:18 pixelsHigh:18
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:18 * 4 bitsPerPixel:32];
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(18.0, 18.0)];
	NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.0, 0.0, 18.0, 18.0)
							      xRadius:4.0 yRadius:4.0];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	if (kind == 0) {
		[[NSColor colorWithCalibratedRed:0.20 green:0.45 blue:0.85 alpha:1.0] setFill];
	} else if (kind == 1) {
		[[NSColor colorWithCalibratedRed:0.85 green:0.42 blue:0.20 alpha:1.0] setFill];
	} else if (kind == 3) {
		[[NSColor colorWithCalibratedRed:0.45 green:0.32 blue:0.72 alpha:1.0] setFill];
	} else {
		[[NSColor colorWithCalibratedRed:0.22 green:0.60 blue:0.35 alpha:1.0] setFill];
	}
	[face fill];
	[[NSColor whiteColor] setFill];
	if (kind == 0) {
		/* A GRID: two rules each way, and the outer frame. */
		[[NSBezierPath bezierPathWithRect:NSMakeRect(4.0, 4.0, 10.0, 1.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(4.0, 8.0, 10.0, 1.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(4.0, 12.0, 10.0, 1.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(4.0, 4.0, 1.0, 9.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(8.0, 4.0, 1.0, 9.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(12.0, 4.0, 1.0, 9.0)] fill];
	} else if (kind == 1) {
		/* THREE LINES OF TEXT, the last one short — a page rather than a picture. */
		[[NSBezierPath bezierPathWithRect:NSMakeRect(4.0, 12.0, 10.0, 2.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(4.0, 8.0, 8.0, 2.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(4.0, 4.0, 6.0, 2.0)] fill];
	} else if (kind == 3) {
		/* A TABLE: a frame, two horizontal rules and one vertical rule. */
		[[NSBezierPath bezierPathWithRect:NSMakeRect(4.0, 4.0, 10.0, 10.0)] fill];
		[[NSColor colorWithCalibratedRed:0.45 green:0.32 blue:0.72 alpha:1.0] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(5.0, 6.5, 8.0, 1.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(5.0, 9.5, 8.0, 1.0)] fill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(8.0, 5.0, 1.0, 8.0)] fill];
	} else {
		NSBezierPath *play = [NSBezierPath bezierPath];

		[play moveToPoint:NSMakePoint(6.0, 4.0)];
		[play lineToPoint:NSMakePoint(14.0, 9.0)];
		[play lineToPoint:NSMakePoint(6.0, 14.0)];
		[play closePath];
		[play fill];
	}
	[image addRepresentation:rep];
	[rep release];
	return [image autorelease];
}

/* **AND THE STORE, FILLED SECTION BY SECTION.** Each block is appended to a string and its range remembered, so an
 * attribute can be set over exactly the characters a person can see; the ranges are arithmetic over the string rather
 * than numbers written down, so moving a word does not silently move an attribute onto it. */
static void fn_playground_fill(NSTextView *view)
{
	NSMutableString *text = [[NSMutableString alloc] init];
	NSTextStorage *store;
	NSFont *titleFont = [NSFont systemFontOfSize:20.0];
	NSFont *bodyFont = [NSFont systemFontOfSize:14.0];
	NSRange titleRange, runsRange, red, blue, struck, highlight;
	NSRange tabsRange, attachRange, box, leftRange, rightRange;
	NSTextAttachment *attachment = [NSTextAttachment textAttachmentWithImage:fn_playground_picture(28.0, 20.0)];
	NSTextTable *table = [[[NSTextTable alloc] init] autorelease];
	NSTextTableBlock *leftCell = [[[NSTextTableBlock alloc] initWithTable:table startingRow:0 rowSpan:1
		startingColumn:0 columnSpan:1] autorelease];
	NSTextTableBlock *rightCell = [[[NSTextTableBlock alloc] initWithTable:table startingRow:0 rowSpan:1
		startingColumn:1 columnSpan:1] autorelease];
	NSMutableParagraphStyle *centre = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	NSMutableParagraphStyle *tabs = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	NSMutableParagraphStyle *leftStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	NSMutableParagraphStyle *rightStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	unichar boxChar = (unichar)NSAttachmentCharacter;

	/* **THE STRING IS BUILT FIRST AND THE ATTRIBUTES SECOND**, so every range below is arithmetic over characters a
	 * person can see rather than a number written down that a moved word would silently miss. */
	titleRange.location = [text length];
	[text appendString:@"Agora's text playground\n\n"];
	titleRange.length = [text length] - titleRange.location;

	runsRange.location = [text length];
	[text appendString:@"Runs: red blue struck highlight — type here and inherit what you type into.\n\n"];
	runsRange.length = [text length] - runsRange.location;
	red = NSMakeRange(runsRange.location + 6, 3);
	blue = NSMakeRange(runsRange.location + 10, 4);
	struck = NSMakeRange(runsRange.location + 15, 6);
	highlight = NSMakeRange(runsRange.location + 22, 9);

	tabsRange.location = [text length];
	[text appendString:@"Tabs:\talpha\tbeta\none:\tone\ttwo\n\n"];
	tabsRange.length = [text length] - tabsRange.location;

	attachRange.location = [text length];
	[text appendString:@"Attachment: "];
	box = NSMakeRange([text length], 1);
	[text appendFormat:@"%C", boxChar];
	[text appendString:@" sits inline; the text flows past it.\n\n"];
	attachRange.length = [text length] - attachRange.location;

	[text appendString:@"cell one\n"];
	leftRange = NSMakeRange(attachRange.location + attachRange.length, 9);
	[text appendString:@"cell two"];
	rightRange = NSMakeRange(leftRange.location + leftRange.length, 8);

	/* AND NOW THE VIEW OWNS THE STRING, which is the one edit that replaces everything. */
	[view setString:text];
	store = [view textStorage];
	[text release];

	/* THE TITLE: a larger face, centred. */
	[store addAttribute:NSFontAttributeName value:titleFont range:titleRange];
	[centre setAlignment:NSCenterTextAlignment];
	[store addAttribute:NSParagraphStyleAttributeName value:centre range:titleRange];

	/* THE RUNS: a red word, a blue underlined one, a struck-through one, and a highlighted span. */
	[store addAttribute:NSFontAttributeName value:bodyFont range:runsRange];
	[store addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:red];
	[store addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:blue];
	[store addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
		      range:blue];
	[store addAttribute:NSStrikethroughStyleAttributeName
		      value:[NSNumber numberWithInteger:NSUnderlineStyleSingle] range:struck];
	[store addAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] range:highlight];

	/* THE TAB STOPS: two lines whose columns land on the same two places. */
	[tabs addTabStop:[[[NSTextTab alloc] initWithType:NSLeftTabStopType location:90.0] autorelease]];
	[tabs addTabStop:[[[NSTextTab alloc] initWithType:NSLeftTabStopType location:180.0] autorelease]];
	[store addAttribute:NSFontAttributeName value:bodyFont range:tabsRange];
	[store addAttribute:NSParagraphStyleAttributeName value:tabs range:tabsRange];

	/* THE ATTACHMENT: a picture that occupies a character's worth of the line and none of its ink. */
	[store addAttribute:NSFontAttributeName value:bodyFont range:attachRange];
	[store addAttribute:NSAttachmentAttributeName value:attachment range:box];

	/* THE TABLE: two cells in one row, each a paragraph carrying its block. */
	[table setNumberOfColumns:2];
	[table setBackgroundColor:[NSColor colorWithCalibratedWhite:0.94 alpha:1.0]];
	[table setBorderColor:[NSColor darkGrayColor] forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge
							  | NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
	[table setWidth:1.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder];
	[table setWidth:6.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
	/* **AND EACH CELL CARRIES ITS OWN, WHICH IS WHAT THE GRID RESERVES.** The table's layers frame the WHOLE grid; a
	 * cell's layers are what the grid adds to its column's width, so a cell with none would have its text touching its
	 * neighbour — which is what the first cut of this demonstration showed. */
	[leftCell setWidth:1.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder];
	[leftCell setWidth:6.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
	[leftCell setBorderColor:[NSColor lightGrayColor] forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge
							      | NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
	[rightCell setWidth:1.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder];
	[rightCell setWidth:6.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
	[rightCell setBorderColor:[NSColor lightGrayColor] forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge
							       | NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
	[leftStyle addTextBlock:leftCell];
	[rightStyle addTextBlock:rightCell];
	[store addAttribute:NSFontAttributeName value:bodyFont range:leftRange];
	[store addAttribute:NSFontAttributeName value:bodyFont range:rightRange];
	[store addAttribute:NSParagraphStyleAttributeName value:leftStyle range:leftRange];
	[store addAttribute:NSParagraphStyleAttributeName value:rightStyle range:rightRange];

	[view setNeedsDisplay:YES];
}


/* ============================================================================================ *
 * THE TABLE & OUTLINE WINDOW'S TWO MODELS.                                                       *
 *                                                                                                *
 * **THE TABLE'S MODEL IS ROWS OF DICTIONARIES AND THE OUTLINE'S IS A TREE OF NODES.** Neither  *
 * source is retained by its view — AppKit's data sources are borrowed — so the controller keeps  *
 * them in `_tableSource` and `_outlineSource` for as long as the window lives.                   *
 * ============================================================================================ */

@interface AGDemoTableSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
	NSArray *_rows;
}
@end

@implementation AGDemoTableSource

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_rows = [[NSArray alloc] initWithObjects:
			[NSDictionary dictionaryWithObjectsAndKeys:@"Notes.txt", @"name", @"Today 09:12", @"modified", @"4 KB", @"size", nil],
			[NSDictionary dictionaryWithObjectsAndKeys:@"Budget.numbers", @"name", @"Yesterday", @"modified", @"38 KB", @"size", nil],
			[NSDictionary dictionaryWithObjectsAndKeys:@"Agora plan.pdf", @"name", @"12 Oct 2026", @"modified", @"1.2 MB", @"size", nil],
			[NSDictionary dictionaryWithObjectsAndKeys:@"Beach.png", @"name", @"10 Oct 2026", @"modified", @"840 KB", @"size", nil],
			[NSDictionary dictionaryWithObjectsAndKeys:@"Family.jpg", @"name", @"03 Oct 2026", @"modified", @"2.1 MB", @"size", nil],
			[NSDictionary dictionaryWithObjectsAndKeys:@"agora.zip", @"name", @"28 Sep 2026", @"modified", @"6.4 MB", @"size", nil],
			[NSDictionary dictionaryWithObjectsAndKeys:@"window-server", @"name", @"18 Oct 2026", @"modified", @"folder", @"size", nil],
			[NSDictionary dictionaryWithObjectsAndKeys:@"workspace", @"name", @"17 Oct 2026", @"modified", @"folder", @"size", nil],
			nil];
	}
	return self;
}

- (void)dealloc
{
	[_rows release];
	[super dealloc];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return (NSInteger)[_rows count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	return [[_rows objectAtIndex:(NSUInteger)row] objectForKey:[tableColumn identifier]];
}

/* **THE DEMONSTRATION WEARS THE TABLE'S OTHER HALF TOO.** Rows vary in height so the row geometry is visible, and
 * the name column answers the type-select string so typing a prefix selects a row. */
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	(void)tableView;
	return 20.0 + (CGFloat)(row % 3) * 6.0;
}

- (NSString *)tableView:(NSTableView *)tableView
   typeSelectStringForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	if ([[tableColumn identifier] isEqual:@"name"]) {
		return [[_rows objectAtIndex:(NSUInteger)row] objectForKey:@"name"];
	}
	return nil;
}

@end

@interface AGDemoNode : NSObject
{
@public
	NSString *name;
	NSMutableArray *children;
}
- (instancetype)initWithName:(NSString *)aName;
@end

@implementation AGDemoNode
- (instancetype)initWithName:(NSString *)aName
{
	self = [super init];
	if (self != nil) {
		name = [aName copy];
		children = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[name release];
	[children release];
	[super dealloc];
}
@end

@interface AGDemoOutlineSource : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
{
	NSMutableArray *_roots;
@public
	AGDemoNode *documents;
	AGDemoNode *photos;
}
@end

@implementation AGDemoOutlineSource

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		AGDemoNode *notes = [[AGDemoNode alloc] initWithName:@"Notes.txt"];
		AGDemoNode *budget = [[AGDemoNode alloc] initWithName:@"Budget.numbers"];
		AGDemoNode *beach = [[AGDemoNode alloc] initWithName:@"Beach.png"];
		AGDemoNode *family = [[AGDemoNode alloc] initWithName:@"Family.jpg"];
		AGDemoNode *archive = [[AGDemoNode alloc] initWithName:@"agora.zip"];
		AGDemoNode *app = [[AGDemoNode alloc] initWithName:@"libagora-app"];
		AGDemoNode *server = [[AGDemoNode alloc] initWithName:@"window-server"];
		AGDemoNode *workspace = [[AGDemoNode alloc] initWithName:@"workspace"];

		documents = [[AGDemoNode alloc] initWithName:@"Documents"];
		photos = [[AGDemoNode alloc] initWithName:@"Photos"];
		[photos->children addObject:beach];
		[documents->children addObject:notes];
		[documents->children addObject:budget];
		[documents->children addObject:photos];
		[documents->children addObject:family];

		{
			AGDemoNode *downloads = [[AGDemoNode alloc] initWithName:@"Downloads"];
			AGDemoNode *projects = [[AGDemoNode alloc] initWithName:@"Projects"];

			[downloads->children addObject:archive];
			[projects->children addObject:app];
			[projects->children addObject:server];
			[projects->children addObject:workspace];
			_roots = [[NSMutableArray alloc] initWithObjects:documents, downloads, projects, nil];
			[downloads release];
			[projects release];
		}
		[notes release];
		[budget release];
		[beach release];
		[family release];
		[archive release];
		[app release];
		[server release];
		[workspace release];
	}
	return self;
}

- (void)dealloc
{
	[_roots release];
	[documents release];
	[photos release];
	[super dealloc];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	(void)outlineView;
	if (item == nil) {
		return (NSInteger)[_roots count];
	}
	return (NSInteger)[((AGDemoNode *)item)->children count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	(void)outlineView;
	if (item == nil) {
		return [_roots objectAtIndex:(NSUInteger)index];
	}
	return [((AGDemoNode *)item)->children objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	(void)outlineView;
	if (item == nil) {
		return [_roots count] > 0;
	}
	return [((AGDemoNode *)item)->children count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	(void)outlineView;
	if (item == nil) {
		return @"";
	}
	if ([[tableColumn identifier] isEqualToString:@"name"]) {
		return ((AGDemoNode *)item)->name;
	}
	return [((AGDemoNode *)item)->children count] > 0 ? @"folder" : @"file";
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	(void)outlineView;
	(void)item;
	return YES;
}

@end

@implementation AGControlsController

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	NSString *title = [item title];

	/* THE CHECKED ITEM'S STATE COMES FROM THE CONTROL, so the menu and the checkbox cannot disagree: the menu is
	 * opened with `-update`, which asks this, and this reads the button. */
	if ([title isEqualToString:@"Show Grid"]) {
		[item setState:[checkbox state]];
		return YES;
	}
	/* AND ONE DISABLED ITEM TO LOOK AT: nothing here can undo, so the item greys out and refuses the highlight —
	 * the two halves of menu VALIDATION, shown rather than described. */
	if ([title isEqualToString:@"Undo"]) {
		return NO;
	}
	return YES;
}

/* **THE TOOLBAR'S ITEMS, MADE FROM THE SAME ACTIONS THE MENU USES.** "Show Grid" toggles the checkbox the View menu
 * validates against, "Playground" opens the text window, and "Action" is the no-op that prints its own name — so the
 * strip and the menus are two roads to the same three acts rather than a second set of commands. The separator,
 * flexible space and the disabled item are the other half of what a toolbar has to show: a spacer the delegate does
 * not make, and an item that says it cannot be pressed. */
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];

	(void)toolbar;
	(void)flag;
	if ([itemIdentifier isEqualToString:@"grid"]) {
		[item setLabel:@"Show Grid"];
		[item setPaletteLabel:@"Show Grid"];
		[item setImage:gridIcon];
		[item setTarget:self];
		[item setAction:@selector(toggleCheckbox:)];
		return item;
	}
	if ([itemIdentifier isEqualToString:@"playground"]) {
		[item setLabel:@"Playground"];
		[item setPaletteLabel:@"Playground"];
		[item setImage:playgroundIcon];
		[item setTarget:self];
		[item setAction:@selector(showPlayground:)];
		return item;
	}
	if ([itemIdentifier isEqualToString:@"table"]) {
		[item setLabel:@"Table"];
		[item setPaletteLabel:@"Table & Outline"];
		[item setImage:tableIcon];
		[item setTarget:self];
		[item setAction:@selector(showDataViews:)];
		return item;
	}
	if ([itemIdentifier isEqualToString:@"action"]) {
		[item setLabel:@"Action"];
		[item setPaletteLabel:@"Action"];
		[item setImage:actionIcon];
		[item setTarget:self];
		[item setAction:@selector(noop:)];
		return item;
	}
	if ([itemIdentifier isEqualToString:@"disabled"]) {
		[item setLabel:@"Disabled"];
		[item setPaletteLabel:@"Disabled"];
		[item setImage:actionIcon];
		[item setTarget:self];
		[item setAction:@selector(noop:)];
		[item setEnabled:NO];
		return item;
	}
	/* A SPACER IS THE TOOLBAR'S OWN, which is what returning nil asks for. */
	return nil;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	(void)toolbar;
	return [NSArray arrayWithObjects:@"grid", @"playground", @"table", NSToolbarSeparatorItemIdentifier,
					 @"action", NSToolbarFlexibleSpaceItemIdentifier, @"disabled", nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	(void)toolbar;
	return [NSArray arrayWithObjects:@"grid", @"playground", @"table", @"action", @"disabled",
					 NSToolbarSeparatorItemIdentifier, NSToolbarSpaceItemIdentifier,
					 NSToolbarFlexibleSpaceItemIdentifier, nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	(void)toolbar;
	/* THE GRID IS THE ONE MODE, so it is the one item a click can leave selected. The action items do something and
	 * come back up; a selected "Playground" would claim the window is a mode. */
	return [NSArray arrayWithObject:@"grid"];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
	NSString *identifier = [item itemIdentifier];

	/* THE DISABLED ITEM IS THE ONE THE STRIP SHOWS GREY, and it says NO here as well as being built disabled. The
	 * validator is what a later update pass asks, so the state cannot come back to life just because the window was
	 * updated. */
	if ([identifier isEqualToString:@"disabled"]) {
		return NO;
	}
	return YES;
}

- (void)toggleCheckbox:(id)sender
{
	(void)sender;
	[checkbox setState:([checkbox state] == NSOnState) ? NSOffState : NSOnState];
	[checkbox setNeedsDisplay:YES];
}

/* **THE SLIDER'S ACTION, WHICH IS WHERE CONTINUOUS TRACKING BECOMES VISIBLE.** A slider sends its action while it is
 * dragged rather than once when the button comes up, so this readout's title follows the knob — and if the flag were
 * off, the title would only change on release. That is the difference the probe pins one class over, shown here.
 *
 * **AND IT READS THE SENDER RATHER THAN A FIXED IVAR, BECAUSE THERE ARE TWO SLIDERS.** A handler that read one
 * slider's value would report the WRONG one the moment the other was dragged — which is the sort of thing a
 * demonstration with two of something exists to make impossible. */
- (void)sliderMoved:(id)sender
{
	NSSlider *moved = (NSSlider *)sender;

	[readout setTitle:[NSString stringWithFormat:@"Value: %.0f", [moved doubleValue]]];
	[readout setNeedsDisplay:YES];
	/* AND ONE LINE OUT, so that a live drag can be READ rather than only looked at: a continuous slider prints once
	 * per point, which is the behaviour the probe pins and this makes observable from outside the process. */
	fprintf(stderr, "controls: slider -> %.1f\n", [moved doubleValue]);
}

/* **THE STEPPER'S ACTION UPDATES THE LABEL BESIDE IT.** A stepper is the one control here whose value is not drawn ON
 * it, so the demonstration owes the number a surface — and printing it as well makes an arrow press readable in the
 * terminal without looking at the window. The label is written the way a caller writes a caption: the cell's string
 * value, because a label in this tier is a field with its editing doors off. */
- (void)stepperMoved:(id)sender
{
	double value = [(NSStepper *)sender doubleValue];

	[stepperReadout setStringValue:[NSString stringWithFormat:@"Value: %.0f", value]];
	[stepperReadout setNeedsDisplay:YES];
	fprintf(stderr, "controls: stepper -> %.0f\n", value);
}

/* **AND THE DATE PICKER'S ACTION, PRINTED RATHER THAN READ OUT.** A date field's value is its text, so there is nothing
 * extra to draw; what a person cannot see from outside is WHICH instant the text stands for, and the formatter's
 * answer is one line on stderr. The same door is on both pickers below, so a step, a typed digit or a calendar click
 * says what it stored. */
- (void)dateChanged:(id)sender
{
	NSDate *date = [(NSDatePicker *)sender dateValue];

	fprintf(stderr, "controls: date -> %s\n", date != nil ? [[date description] UTF8String] : "(nil)");
}

/* AN ITEM WITH NO WORK TO DO BUT SOMETHING TO BE: a menu item whose action is NULL is DISABLED by the auto-enabling
 * walk (nothing answers it), so the items that are here to be LOOKED at carry this instead — enabled, and honestly
 * doing nothing but saying so. */
- (void)noop:(id)sender
{
	/* **THE SAME ACTION IS A MENU ITEM'S AND A TOOLBAR ITEM'S, SO IT READS EITHER.** A menu item has a title and a
	 * toolbar item has a label; an action that cast blindly to `NSMenuItem` would print a title out of an object that
	 * does not have one — the crash a shared target is supposed to avoid, not cause. */
	NSString *name = nil;

	if ([sender isKindOfClass:[NSMenuItem class]]) {
		name = [(NSMenuItem *)sender title];
	} else if ([sender isKindOfClass:[NSToolbarItem class]]) {
		name = [(NSToolbarItem *)sender label];
	} else if ([sender isKindOfClass:[NSButton class]]) {
		name = [(NSButton *)sender title];
	}
	fprintf(stderr, "controls: action chosen: %s\n", name != nil ? [name UTF8String] : "?");
}

/* **A POP-UP BUTTON'S ACTION, AND IT READS THE SENDER THE WAY THE SLIDER'S DOES.** The sender is the BUTTON — not the
 * menu item that was picked — which is the whole point of the two classes: a caller who wants the row can ask the
 * button for it, and a caller who wants to know WHICH BUTTON can tell one from another. Printed rather than drawn,
 * so a live choice can be READ from outside the process, exactly as the slider's value is. */
- (void)choiceMade:(id)sender
{
	fprintf(stderr, "controls: popup chose \"%s\" at index %ld\n",
		[[(NSPopUpButton *)sender titleOfSelectedItem] UTF8String],
		(long)[(NSPopUpButton *)sender indexOfSelectedItem]);
}

/* **THE PLAYGROUND WINDOW, MADE ONCE AND BROUGHT FORWARD AFTER.** A scrollable, EDITABLE `NSTextView` over the store
 * `-fn_playground_fill` builds, so a person can type and select in exactly the text the slices drew. Its width is the
 * scroll view's content width, which is what makes the wrap visible when the window is resized by its edge. */
- (void)showPlayground:(id)sender
{
	NSUInteger mask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;

	(void)sender;
	if (_playground == nil) {
		/* **A WINDOW IS PLACED INSIDE THE VISIBLE FRAME, WHICH IS WHAT EXCLUDES THE MENU BAR.** The first cut placed it
		 * at (180,180) with a 486-point frame on a 600-tall screen, so its TITLE BAR sat ABOVE the menu — which is
		 * unacceptable at any size, and the reason the placement is arithmetic here rather than three numbers. */
		NSRect visible = [[NSScreen mainScreen] visibleFrame];
		NSRect content;
		NSRect frameRect;
		NSWindow *w;
		NSScrollView *scroll;
		NSTextView *tv;

		if (NSIsEmptyRect(visible)) {
			visible = NSMakeRect(0.0, 0.0, 900.0, 600.0);
		}
		content.size.width = 520.0;
		content.size.height = 380.0;
		if (content.size.width > NSWidth(visible) - 40.0) {
			content.size.width = NSWidth(visible) - 40.0;
		}
		if (content.size.height > NSHeight(visible) - 60.0) {
			content.size.height = NSHeight(visible) - 60.0;
		}
		content.origin.x = NSMaxX(visible) - content.size.width - 20.0;
		content.origin.y = NSMinY(visible) + 20.0;
		/* THE FRAME IS TALLER THAN THE CONTENT BY THE CHROME STRIP, so the fit is checked on the FRAME: if the title bar
		 * would leave the visible area the content is moved down until it does not. */
		frameRect = [NSWindow frameRectForContentRect:content styleMask:mask];
		if (NSMaxY(frameRect) > NSMaxY(visible)) {
			content.origin.y -= (NSMaxY(frameRect) - NSMaxY(visible));
		}
		if (NSMaxX(frameRect) > NSMaxX(visible)) {
			content.origin.x -= (NSMaxX(frameRect) - NSMaxX(visible));
		}
		if (NSMinY(content) < NSMinY(visible)) {
			content.origin.y = NSMinY(visible);
		}
		if (NSMinX(content) < NSMinX(visible)) {
			content.origin.x = NSMinX(visible);
		}
		w = [[NSWindow alloc] initWithContentRect:content styleMask:mask backing:NSBackingStoreBuffered defer:NO];
		/* AND THE FRAME IS CLAMPED ONCE MORE, now that the window knows its own chrome: a clamp on the object cannot be
		 * wrong, and it is the line that makes the guarantee hold for a screen this code did not imagine. */
		frameRect = [w frame];
		if (NSMaxY(frameRect) > NSMaxY(visible)) {
			frameRect.origin.y = NSMaxY(visible) - NSHeight(frameRect);
		}
		if (NSMinY(frameRect) < NSMinY(visible)) {
			frameRect.origin.y = NSMinY(visible);
		}
		if (NSMaxX(frameRect) > NSMaxX(visible)) {
			frameRect.origin.x = NSMaxX(visible) - NSWidth(frameRect);
		}
		if (NSMinX(frameRect) < NSMinX(visible)) {
			frameRect.origin.x = NSMinX(visible);
		}
		[w setFrame:frameRect display:YES];

		scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, content.size.width, content.size.height)];
		[scroll setBorderType:NSLineBorder];
		[scroll setHasVerticalScroller:YES];
		[scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
		tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, content.size.width - 16.0, content.size.height)];
		[tv setDrawsBackground:YES];
		[tv setBackgroundColor:[NSColor whiteColor]];
		[tv setVerticallyResizable:YES];
		fn_playground_fill(tv);
		[scroll setDocumentView:tv];
		[w setContentView:scroll];
		[w setTitle:@"Text playground"];
		[w setReleasedWhenClosed:NO];
		_playground = w;
		[tv release];
		[scroll release];
		fprintf(stderr, "controls: playground opened — window %.0f,%.0f %.0fx%.0f; visible %.0f,%.0f %.0fx%.0f; "
			"text = %lu chars\n",
			[w frame].origin.x, [w frame].origin.y, [w frame].size.width, [w frame].size.height,
			visible.origin.x, visible.origin.y, visible.size.width, visible.size.height,
			(unsigned long)[[[(NSTextView *)[scroll documentView] textStorage] string] length]);
	}
	[_playground orderFront:nil];
}

/* **A WINDOW FOR THE TWO DATA VIEWS: THE OUTLINE ON THE LEFT AND THE TABLE ON THE RIGHT, IN ONE SPLIT VIEW.** The
 * divider is the real `NSSplitView` — the class this demonstration used to say was the next slice — so the panels
 * can be resized against each other and the geometry is the platform's rather than two frames placed by hand; the
 * two panels still show the real classes and each one's own header. `--data` opens this window at startup so a
 * screenshot can find it. */
- (void)showDataViews:(id)sender
{
	NSRect visible;
	NSRect content;
	NSWindow *w;
	NSView *root;
	NSSplitView *splitView;
	AGDemoPaneView *outlineCard;
	AGDemoPaneView *tableCard;
	NSScrollView *outlineScroll;
	NSOutlineView *outline;
	NSTableColumn *outlineName;
	NSTableColumn *outlineKind;
	NSScrollView *tableScroll;
	NSTableView *table;
	NSTableColumn *tableName;
	NSTableColumn *tableModified;
	NSTableColumn *tableSize;
	AGDemoOutlineSource *outlineSource;
	AGDemoTableSource *tableSource;
	NSTextField *outlineLabel;
	NSTextField *tableLabel;

	(void)sender;
	if (_dataWindow != nil) {
		[_dataWindow makeKeyAndOrderFront:nil];
		return;
	}
	visible = [[NSScreen mainScreen] visibleFrame];
	if (NSIsEmptyRect(visible)) {
		visible = NSMakeRect(0.0, 0.0, 900.0, 600.0);
	}
	content = NSMakeRect(20.0, 20.0, 900.0, 520.0);
	if (NSMaxX(content) > NSMaxX(visible)) {
		content.origin.x = NSMaxX(visible) - NSWidth(content);
	}
	if (NSMaxY(content) > NSMaxY(visible)) {
		content.origin.y = NSMaxY(visible) - NSHeight(content);
	}
	if (NSMinX(content) < NSMinX(visible)) {
		content.origin.x = NSMinX(visible);
	}
	if (NSMinY(content) < NSMinY(visible)) {
		content.origin.y = NSMinY(visible);
	}
	w = [[NSWindow alloc] initWithContentRect:content
			styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
			backing:NSBackingStoreBuffered defer:NO];
	root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 900.0, 520.0)];

	outlineLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0, 478.0, 410.0, 20.0)];
	[outlineLabel setStringValue:@"Outline view — disclosure, levels, item selection"];
	[outlineLabel setEditable:NO];
	[outlineLabel setSelectable:NO];
	[outlineLabel setBordered:NO];
	[outlineLabel setBezeled:NO];
	[outlineLabel setDrawsBackground:NO];
	[outlineLabel setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
	[root addSubview:outlineLabel];
	[outlineLabel release];

	tableLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(450.0, 478.0, 430.0, 20.0)];
	[tableLabel setStringValue:@"Table view — columns, header, alternating rows"];
	[tableLabel setEditable:NO];
	[tableLabel setSelectable:NO];
	[tableLabel setBordered:NO];
	[tableLabel setBezeled:NO];
	[tableLabel setDrawsBackground:NO];
	[tableLabel setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
	[root addSubview:tableLabel];
	[tableLabel release];

	outlineScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20.0, 20.0, 410.0, 450.0)];
	[outlineScroll setBorderType:NSNoBorder];
	[outlineScroll setHasVerticalScroller:YES];
	[outlineScroll setHasHorizontalScroller:YES];
	outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 410.0, 450.0)];
	[outline setRowHeight:20.0];
	[outline setUsesAlternatingRowBackgroundColors:YES];
	outlineName = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	outlineKind = [[NSTableColumn alloc] initWithIdentifier:@"kind"];
	[outlineName setWidth:260.0];
	[outlineKind setWidth:110.0];
	[outline addTableColumn:outlineName];
	[outline addTableColumn:outlineKind];
	[outline setOutlineTableColumn:outlineName];
	outlineSource = [[AGDemoOutlineSource alloc] init];
	[outline setDataSource:outlineSource];
	[outline setDelegate:outlineSource];
	[outlineScroll setDocumentView:outline];
	[outline reloadData];
	[outline expandItem:outlineSource->documents];
	[outline expandItem:outlineSource->photos];
	[outline selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];

	tableScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(450.0, 20.0, 430.0, 450.0)];
	[tableScroll setBorderType:NSNoBorder];
	[tableScroll setHasVerticalScroller:YES];
	[tableScroll setHasHorizontalScroller:YES];
	table = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 430.0, 450.0)];
	[table setRowHeight:20.0];
	[table setUsesAlternatingRowBackgroundColors:YES];
	[table setAllowsMultipleSelection:YES];
	tableName = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	tableModified = [[NSTableColumn alloc] initWithIdentifier:@"modified"];
	tableSize = [[NSTableColumn alloc] initWithIdentifier:@"size"];
	[tableName setWidth:170.0];
	[tableModified setWidth:130.0];
	[tableSize setWidth:80.0];
	[table addTableColumn:tableName];
	[table addTableColumn:tableModified];
	[table addTableColumn:tableSize];
	tableSource = [[AGDemoTableSource alloc] init];
	[table setDataSource:tableSource];
	[table setDelegate:tableSource];
	[tableScroll setDocumentView:table];
	[table reloadData];
	[table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
	/* THE SPLIT VIEW IS THE PANES' SUPERVIEW, so the two scroll views are added to it rather than to the root. Its
	 * frame is the pair's shared area and the thin divider is the one between them. */
	splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(20.0, 20.0, 860.0, 450.0)];
	[splitView setVertical:YES];
	[splitView setDividerStyle:NSSplitViewDividerStylePaneSplitter];
	outlineCard = [[AGDemoPaneView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 410.0, 450.0)
						    content:outlineScroll];
	tableCard = [[AGDemoPaneView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 450.0, 450.0)
						  content:tableScroll];
	[splitView addSubview:outlineCard];
	[splitView addSubview:tableCard];
	[splitView adjustSubviews];
	[root addSubview:splitView];
	[w setContentView:root];
	[w setTitle:@"Table & Outline"];
	[w setReleasedWhenClosed:NO];
	[w makeKeyAndOrderFront:nil];
	_dataWindow = w;
	_outlineSource = [outlineSource retain];
	_tableSource = [tableSource retain];
	fprintf(stderr, "controls: data window — outline %.0fx%.0f, table %.0fx%.0f, split %.0f/%.0f, %lu outline rows, "
		"%lu table rows\n",
		[outlineScroll frame].size.width, [outlineScroll frame].size.height,
		[tableScroll frame].size.width, [tableScroll frame].size.height,
		[outlineScroll frame].size.width, [tableScroll frame].size.width,
		(unsigned long)[outline numberOfRows], (unsigned long)[table numberOfRows]);
	[outline release];
	[table release];
	[outlineName release];
	[outlineKind release];
	[tableName release];
	[tableModified release];
	[tableSize release];
	[outlineScroll release];
	[tableScroll release];
	[outlineCard release];
	[tableCard release];
	[splitView release];
	[outlineSource release];
	[tableSource release];
	[root release];
}

@end

/* ONE TITLE, ITS ITEMS, AND WHOSE ACTION THEY CARRY. Written as a helper because the bar below makes four of them and
 * the repetition is the shape of a menu rather than a decision. */
/* **A KEY EQUIVALENT, WITH THE MODIFIER MASK THE MATCHER WANTS.** `-performKeyEquivalent:` compares an event's
 * `-charactersIgnoringModifiers` — which the seam produces WITH Shift applied, so a shifted key arrives as an
 * UPPERCASE letter — against the item's key equivalent, and it compares the MASK EXACTLY. So an uppercase key takes
 * both bits and a lowercase one Command alone, which is what makes Cmd-Z undo and Shift-Cmd-Z redo rather than two
 * spellings of one shortcut. THE MASK IS SET EXPLICITLY rather than left to a default: a fresh item in this tier
 * carries NO modifier at all, and a shortcut nobody meant to type is not a shortcut. */
static void fn_set_key(NSMenuItem *item, NSString *key)
{
	NSUInteger mask = NSCommandKeyMask;

	if ([key length] == 1) {
		unichar c = [key characterAtIndex:0];

		if (c >= 'A' && c <= 'Z') {
			mask |= NSShiftKeyMask;
		}
	}
	[item setKeyEquivalent:key];
	[item setKeyEquivalentModifierMask:mask];
}

static NSMenuItem *add_menu(NSMenu *bar, NSString *title, NSArray *itemTitles, NSArray *keys, id target, SEL action)
{
	NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
	NSMenu *contents = [[NSMenu alloc] initWithTitle:title];
	NSUInteger i;

	for (i = 0; i < [itemTitles count]; i++) {
		NSString *name = [itemTitles objectAtIndex:i];
		NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:name action:action keyEquivalent:@""];

		/* THE KEYS ARE A PARALLEL ARRAY rather than part of the title, because a key equivalent is an ITEM's and
		 * not a menu's: two items in one menu may carry different modifiers (undo and redo), so the pair travels
		 * with the item. */
		if (i < [keys count]) {
			fn_set_key(entry, [keys objectAtIndex:i]);
		}
		[entry setTarget:target];
		[contents addItem:entry];
		[entry release];
	}
	[titleItem setSubmenu:contents];
	[contents release];
	[bar addItem:titleItem];
	return titleItem;
}

/* ============================================================================================ *
 * THE SCROLLABLE DOCUMENT, WHICH IS WHAT THE SCROLLING SLICE DRAWS.                             *
 *                                                                                                *
 * **A DOCUMENT BIGGER THAN THE WINDOW IT IS IN, WITH LANDMARKS A SCROLL CAN BE READ AGAINST.**  *
 * A scroll panel that drew one flat colour would prove nothing: the point of it is that        *
 * dragging a knob MOVES something a person can name. So the document is a grid of numbered     *
 * rows with a RED mark at its start and a GREEN one at its end — scroll to the bottom and the  *
 * green is what shows, scroll back and the red returns.                                        *
 *                                                                                                *
 * AND IT IS NOT FLIPPED, WHICH IS THE SUBTLE PART. A clip view IS flipped, so the mirror the    *
 * drawing layer applies on the way in leaves this view in a y-up context — which is the one    *
 * `-drawAtPoint:withAttributes:` puts upright text in. A flipped document would have drawn its  *
 * labels upside down, which is the sort of thing a demonstration exists to not do.             *
 * ============================================================================================ */
#define AG_DOC_W 900.0
#define AG_DOC_H 1400.0

@interface AGScrollDoc : NSView
@end

@implementation AGScrollDoc

- (void)drawRect:(NSRect)rect
{
	NSRect b = [self bounds];
	/* **THE TEXT'S OWN COLOUR IS NAMED, AND IT HAS TO BE.** `apk_apply_colour` only touches the fill when
	 * `NSForegroundColorAttributeName` is present, so text drawn without one inherits whatever fill was last set —
	 * here the band it sits on — and comes out invisible. MEASURED: the labels were absent until this key was added.
	 * The font is added only when the service answers one, because `+systemFontOfSize:` can answer nil on a host
	 * with no faces and `-setObject:forKey:` raises on a nil value. */
	NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
	NSFont *font = [NSFont systemFontOfSize:11.0];
	NSInteger row;

	(void)rect;
	[attrs setObject:[NSColor blackColor] forKey:NSForegroundColorAttributeName];
	if (font != nil) {
		[attrs setObject:font forKey:NSFontAttributeName];
	}
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:b] fill];
	/* THE ROWS, EACH WITH ITS OWN y, so a scroll can be read as a NUMBER moving and not only as a colour. */
	for (row = 0; (CGFloat)(row * 50) < NSHeight(b); row++) {
		NSRect band = NSMakeRect(0.0, (CGFloat)(row * 50), NSWidth(b), 25.0);

		if (row % 2 == 0) {
			[[NSColor colorWithCalibratedRed:0.90 green:0.94 blue:1.0 alpha:1.0] setFill];
		} else {
			[[NSColor colorWithCalibratedRed:1.0 green:0.95 blue:0.89 alpha:1.0] setFill];
		}
		[[NSBezierPath bezierPathWithRect:band] fill];
		[[NSString stringWithFormat:@"row %ld   ·   y = %ld", (long)row, (long)(row * 50)]
			drawAtPoint:NSMakePoint(12.0, (CGFloat)(row * 50) + 6.0) withAttributes:attrs];
	}
	/* AND A LINE EVERY HUNDRED POINTS ACROSS, so a HORIZONTAL scroll is visible as well as a vertical one. */
	{
		NSInteger col;
		NSBezierPath *lines = [NSBezierPath bezierPath];

		for (col = 0; (CGFloat)(col * 100) <= NSWidth(b); col++) {
			[lines moveToPoint:NSMakePoint((CGFloat)(col * 100), 0.0)];
			[lines lineToPoint:NSMakePoint((CGFloat)(col * 100), NSHeight(b))];
		}
		[lines setLineWidth:1.0];
		[[NSColor colorWithCalibratedWhite:0.72 alpha:1.0] setStroke];
		[lines stroke];
	}
	/* THE TWO ENDS: red where the document begins, green where it ends. */
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, NSHeight(b) - 80.0, 220.0, 80.0)] fill];
	[[NSColor greenColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(NSWidth(b) - 240.0, 0.0, 240.0, 90.0)] fill];
}

@end

int main(int argc, char **argv)
{
	int seconds = 0;
	int showData = 0;
	int showPlaygroundWindow = 1;
	int i;

	/* **THE CHROME'S THEME IS THIS DEMONSTRATION'S DEFAULT, WHICH IS WHAT MAKES IT THE THING TO ITERATE ON.** The
	 * library reads a theme only when `AGORA_CHROME_THEME` names one — that is the whole of the mechanism, and it is
	 * the right default for a LIBRARY, which must not go looking for other people's art. A DEMONSTRATION is the other
	 * case: the chrome is the thing being looked at, so this points the variable at the tree's own `themes/` when a
	 * caller has not, and an explicit `AGORA_CHROME_THEME` still wins. A checkout with no theme there resolves none and
	 * falls back to the marks `NSWindow` draws, which is why the default can be unconditional. */
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
			seconds = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--data") == 0) {
			showData = 1;
		} else if (strcmp(argv[i], "--no-playground") == 0) {
			/* **THE PLAYGROUND IS MAPPED LAST SO IT IS IN FRONT, WHICH IS RIGHT FOR LOOKING AT THE TEXT AND WRONG FOR
			 * LOOKING AT THE CONTROLS** — it covers the right column, which is where the newest controls are. This flag
			 * leaves it unmapped, so `run-controls.sh --no-playground` opens on the controls window itself. */
			showPlaygroundWindow = 0;
		}
	}
#ifdef AGORA_CHROME_DEFAULT_THEME
	if (getenv("AGORA_CHROME_THEME") == NULL) {
		setenv("AGORA_CHROME_THEME", AGORA_CHROME_DEFAULT_THEME, 1);
	}
#endif
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		AGControlsController *controller = [[AGControlsController alloc] init];
		NSMenu *bar = [[NSMenu alloc] initWithTitle:@"MainMenu"];
		NSWindow *w;
		NSView *content;
		NSButton *push;
		NSButton *alt;
		NSButton *check;
		NSButton *radio;
		NSButton *off;
		NSButton *readout;
		NSSlider *slider;
		NSSlider *plain;
		NSSegmentedControl *segmented;
		NSPathControl *pathBar;
		/* **AND A TEXT FIELD, WHICH IS THE ONE CONTROL IN THIS WINDOW THAT TAKES THE KEYBOARD.** It is focused below,
		 * which opens its editor, so a keystroke goes to the field rather than nowhere: the window sends KEY EVENTS to its
		 * first responder, and a window with none has nobody to type at. (The responder that ends up holding the keyboard
		 * is the EDITOR, not the field — that is the arrangement the field control exists to set up.) */
		NSTextField *field;
		AGSwitch *sw;
		/* AND A SCROLL PANEL, which is the one thing in this window that shows the scrolling slice. */
		NSScrollView *scroll;
		NSPopUpButton *popup;
		NSComboBox *combo;
		/* **AND THE NEW-CONTROLS STRIP'S OWN SET**: two level indicators (a capacity bar and a rating), a stepper with
		 * its readout, the two fields that are about typing rather than about a value, a date picker, a progress bar and
		 * a spinner, a box, and a tab view whose panes are two more date pickers. */
		NSLevelIndicator *capacity;
		NSLevelIndicator *rating;
		NSStepper *stepper;
		NSTextField *stepperValue;
		NSSecureTextField *secure;
		NSSearchField *search;
		NSDatePicker *dateField;
		NSProgressIndicator *progress;
		NSProgressIndicator *spinner;
		NSBox *box;
		NSButton *boxButton;
		NSTabView *tabs;
		NSMenu *choices;
		AGScrollDoc *doc;
		NSToolbar *toolbar;

		[app finishLaunching];

		/* THE WINDOW AND ITS CONTROLS. The slider sits at the bottom with a readout button beside the checkbox, so a
		 * drag on the knob is visible without any other instrument.
		 *
		 * **AND EVERY PUSH BUTTON BELOW IS THE STANDARD 23 POINTS TALL**, which is what `-sizeToFit` and a degenerate frame
		 * now produce by themselves — the frames are explicit only because a demonstration says where its controls go. The
		 * two INDICATOR rows and the slider keep their own heights, which is the other half of the same rule: 23 is the
		 * BEZEL's metric, so a control with no bezel does not wear it. */
		/* **FOUR BITS, WHICH IS AGORA'S OWN CHROME RATHER THAN APPLE'S.** Agora's title bar is an X, a minus and a
		 * plus in one ink, so the closable, miniaturizable and resizable bits are three SYMBOLS and the window wants all
		 * three of them on screen. The previous revision left the resizable bit off on the ground that a zoom mark this
		 * tier cannot act on is worse than no mark at all; the chrome's redesign settles it the other way — an X, a minus
		 * and a plus are a SET, and a set with a hole in it reads as a window that is missing something. What the plus
		 * will do when this tier grows a resizable window is `NSResizableWindowMask`'s business and not this demo's.
		 *
		 * THE FRAME GROWS BY THE STRIP AND THE CONTENT DOES NOT MOVE, because the frame is bottom-left: the title bar is
		 * added ABOVE the 420x290 the controls are already laid out in. */
		/* **THE WINDOW SITS LOW ENOUGH FOR THE TOOLBAR IT IS ABOUT TO WEAR.** The content is still 760x420; a toolbar
		 * adds its 52-point band and the title bar another 22, so the frame is 494 tall and the origin is 60 rather than
		 * 120 — otherwise the default 900x600 demonstration would put the title bar above the screen. */
		w = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 60, 760, 420)
			styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
			backing:NSBackingStoreBuffered defer:NO];
		content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 760, 420)];
		push = [[NSButton alloc] initWithFrame:NSMakeRect(30, 234, 140, 23)];
		alt = [[NSButton alloc] initWithFrame:NSMakeRect(200, 234, 180, 23)];
		check = [[NSButton alloc] initWithFrame:NSMakeRect(30, 190, 170, 22)];
		readout = [[NSButton alloc] initWithFrame:NSMakeRect(230, 189, 150, 23)];
		radio = [[NSButton alloc] initWithFrame:NSMakeRect(30, 160, 260, 22)];
		off = [[NSButton alloc] initWithFrame:NSMakeRect(30, 129, 260, 23)];
		slider = [[NSSlider alloc] initWithFrame:NSMakeRect(30, 60, 350, 24)];
		/* THE SECOND ONE, WITH NO TICK MARKS AT ALL — which is the whole of what makes its grabber a circle rather
		 * than a teardrop. Same range and same action, so the only difference on screen is the shape. */
		plain = [[NSSlider alloc] initWithFrame:NSMakeRect(30, 25, 350, 24)];
		field = [[NSTextField alloc] initWithFrame:NSMakeRect(30, 95, 350, 22)];
		/* **AND A SWITCH, WHICH IS THIS TIER'S OWN CONTROL RATHER THAN AN ERA DOOR.** Apple has no `NSSwitch` until
		 * 10.15 and the era's `NSSwitchButton` is a checkbox, so the sample's pill is drawn by `AGSwitch` — a track and a
		 * knob, 32 x 20, with the four states the sample's legend gives. It sits beside the radio because the two are the
		 * same question asked two ways: one says its value with a filled circle, the other with where the knob is.
		 *
		 * AND IT IS PLACED OFF THE RADIO'S LABEL, WHICH IS A MEASUREMENT RATHER THAN A GUESS: the radio occupies x=30..290,
		 * so the switch goes to the right of it and to the left of the scroll panel at x=400, which is the only free room
		 * on the row. A demonstration is where a layout mistake is supposed to be visible, and the first position tried
		 * (230) would have drawn a track across the word "on". */
		sw = [[AGSwitch alloc] initWithFrame:NSMakeRect(330, 158, 0, 0)];
		[sw setState:NSOnState];
		/* THE SCROLL PANEL, TO THE RIGHT OF THE CONTROLS: a frame, and a document four times its height and twice and
		 * a half its width, so both knobs have somewhere to go and both ends have a landmark. **IT IS SHORTER THAN IT
		 * WAS**: the new-controls strip above it needs the room, and 150 points of a 1200-point document is still enough
		 * scrolling to show both bars doing their work. */
		scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(400, 25, 340, 150)];
		doc = [[AGScrollDoc alloc] initWithFrame:NSMakeRect(0, 0, AG_DOC_W, AG_DOC_H)];

		[push setTitle:@"Toggle the Checkbox"];
		[push setTarget:controller];
		[push setAction:@selector(toggleCheckbox:)];
		[alt setTitle:@"Longer Title Here"];
		[check setTitle:@"A Checkbox, on"];
		[check setButtonType:NSSwitchButton];
		[check setState:NSOnState];
		[readout setTitle:@"Value: 50"];
		[readout setTarget:controller];
		[readout setAction:@selector(noop:)];
		[radio setTitle:@"A Radio, on"];
		[radio setButtonType:NSRadioButton];
		[radio setState:NSOnState];
		[off setTitle:@"A disabled button"];
		[off setEnabled:NO];
		/* **THE SLIDER'S OWN SETTINGS, ALL FOUR OF THEM A DOOR THIS SLICE ADDED**: a range that is not 0…1, a value
		 * to start at, five ticks to look at, and the controller as the target of a drag that speaks continuously. */
		[slider setMinValue:0.0];
		[slider setMaxValue:100.0];
		[slider setDoubleValue:50.0];
		[slider setNumberOfTickMarks:5];
		[slider setTarget:controller];
		[slider setAction:@selector(sliderMoved:)];
		/* **AND THE SECOND SLIDER, WHICH IS THE SAME CONTROL WITH THE TICKS TAKEN AWAY.** `-setNumberOfTickMarks:`
		 * is left at its default of none, and the grabber's shape follows from that rather than from anything the
		 * demonstration asks for — which is the point of showing them side by side. */
		[plain setMinValue:0.0];
		[plain setMaxValue:100.0];
		[plain setDoubleValue:25.0];
		[plain setTarget:controller];
		[plain setAction:@selector(sliderMoved:)];
		/* **THE FIELD SHOWS A WHITE SURFACE BY DEFAULT, WHICH IS THE CELL'S OWN CHOICE RATHER THAN A CALLER'S**, and it
		 * opens EMPTY with a PLACEHOLDER: a hint drawn in grey where a value would go, which is what a field has to say
		 * about itself while it holds nothing. `-placeholderString` is the CELL's door in the era — Apple's control-level
		 * one is a 10.10 addition — so the demonstration reaches through the cell, exactly as a 10.6 caller would. */
		[(NSTextFieldCell *)[field cell] setPlaceholderString:@"Type here — this is a hint, not a value"];
		/* **AND IT IS SIZED TO ITS OWN TEXT RATHER THAN TO A NUMBER SOMEBODY WROTE DOWN.** `-sizeToFit`'s height is the
		 * FONT'S BAND plus this class's own padding — so the frame follows `NS_TEXT_INSET`, which is what the field
		 * beside it (a combo box) already does, and what a frame of twenty-two written by hand does NOT: MEASURED on
		 * the demonstration, that frame was sized for a two-point padding, and when the padding became four the text
		 * was left sitting in a field four points too short for it while the combo box beside it grew.
		 *
		 * THE WIDTH IS PUT BACK because the door sizes to the STRING as well, and a demonstration field is a wide one on
		 * purpose — it is where a person types, not a label that hugs its text. */
		[field sizeToFit];
		[field setFrameSize:NSMakeSize(350.0, [field frame].size.height)];
		/* **THE SCROLL PANEL'S OWN SETTINGS: BOTH BARS, A LINE BORDER, AND THE DOCUMENT.** The scrollers are asked for
		 * BEFORE the document so `-tile` has already sized the clip view when the document arrives and the knobs are
		 * given the right proportions on the first reflect. */
		[scroll setBorderType:NSLineBorder];
		[scroll setHasVerticalScroller:YES];
		[scroll setHasHorizontalScroller:YES];
		[scroll setDocumentView:doc];
		/* **AND THE POP-UP BUTTON, WHICH IS THE ONE CONTROL HERE THAT JOINS TWO SUBSYSTEMS.** It is a button whose
		 * press raises a MENU, so the thing to play with is not its face but the CHAIN: press it, choose a row, and
		 * the title on the bezel changes while the line on stderr says which row and what index — the same two facts
		 * a caller's action is handed. It goes above the push buttons because it is the NEWEST face and the room
		 * there is otherwise empty.
		 *
		 * THE SECOND ITEM IS THE ONE SELECTED, so the window opens with the button naming a row rather than wearing
		 * an empty title — a popup whose title is blank looks like a button that failed to load. */
		/* **AND A SEGMENTED CONTROL, THE FILE WINDOW'S VIEW SWITCHER.** Three segments, the first selected, in the free
		 * room above the pop-up row. It is a real NSSegmentedControl: the plate, the separators and the labels are the
		 * cell's, and clicking a segment moves the selection through the control's ordinary tracking loop. */
		segmented = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(30, 340, 260, 24)];
		[segmented setSegmentCount:3];
		[segmented setLabel:@"Icon" forSegment:0];
		[segmented setLabel:@"List" forSegment:1];
		[segmented setLabel:@"Column" forSegment:2];
		[segmented setSelectedSegment:0];
		[segmented setTarget:controller];
		[segmented setAction:@selector(noop:)];
		/* **AND THE PATH BAR, THE FILE WINDOW'S OTHER PIECE OF NAVIGATION CHROME.** A real NSPathControl in the
		 * navigation-bar style: the URL becomes component cells, and the chevrons between them are the cell's. */
		pathBar = [[NSPathControl alloc] initWithFrame:NSMakeRect(30, 305, 350, 24)];
		[pathBar setPathStyle:NSPathStyleNavigationBar];
		[pathBar setURL:[NSURL fileURLWithPath:@"/System/Library/CoreServices"]];
		[pathBar setTarget:controller];
		[pathBar setAction:@selector(noop:)];
		popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(30, 268, 0, 0) pullsDown:NO];
		choices = [[NSMenu alloc] initWithTitle:@"Choices"];
		[choices addItemWithTitle:@"First choice" action:NULL keyEquivalent:@""];
		[choices addItemWithTitle:@"Second choice" action:NULL keyEquivalent:@""];
		[choices addItemWithTitle:@"Third choice" action:NULL keyEquivalent:@""];
		[popup setMenu:choices];
		[popup selectItemAtIndex:1];
		/* **AND IT IS SIZED AFTER ITS MENU EXISTS, WHICH IS THE WHOLE POINT OF THE DOOR BELOW.** `-sizeToFit` asks
		 * the cell to measure itself, and a pop-up button's measurement is its TITLE PLUS ITS ARROW — so a button
		 * fitted before its menu is set is a button fitted to an empty title, and one fitted with the wrong order is
		 * one whose arrow lands on its last letter. It is fitted here, once, with everything in place; the sample's
		 * own button hugs its contents at both ends and this is what makes that true of this one. */
		[popup sizeToFit];
		[popup setTarget:controller];
		[popup setAction:@selector(choiceMade:)];
		[content addSubview:popup];
		[content addSubview:segmented];
		[content addSubview:pathBar];
		/* **AND THE COMBO BOX GOES BESIDE IT, WHICH IS WHERE THE SAMPLE PUTS THE PAIR.** The gallery draws these two on
		 * adjacent rows and this window puts them on ONE, because the whole difference between them is one mark and a
		 * person should be able to see both chips without moving their eye: the pop-up's carries two triangles knocked
		 * out of it and this one carries a single down arrow. It is given a title of its own rather than the pop-up's, so
		 * that the two are told apart by their words as well as by their arrows, and it is fitted the same way — after
		 * its list exists.
		 *
		 * AND IT IS A LIVE CONTROL NOW: its chip opens the list, and a row chosen from it becomes the box's value — so
		 * the press does the thing the chip promises. What it demonstrates BESIDE the pop-up is still the INK, which is
		 * what the sample's gallery specifies: one triangle where the pop-up knocks out two. */
		combo = [[NSComboBox alloc] initWithFrame:NSMakeRect(180, 268, 0, 0)];
		[combo addItemsWithObjectValues:[NSArray arrayWithObjects:@"NSComboBox", @"and its list", nil]];
		[combo selectItemAtIndex:0];
		[combo sizeToFit];
		[content addSubview:combo];

		/* **THE NEW-CONTROLS STRIP: THE CLASSES THE LATER SLICES LANDED, IN THE ROOM THE SHORTER SCROLL PANEL GIVES
		 * THEM.** Two columns of 162 points below the segmented/path/pop-up rows and above the scroll panel. The left
		 * column is the value-shaped controls and the two fields; the right is the two CONTAINERS — a box around a
		 * button and a tab view whose panes are the date picker's other two styles, so every face the date picker
		 * draws is in one window.
		 *
		 * **EVERY CONTROL IS SET TO THE STATE THAT MAKES ITS PICTURE SAY SOMETHING**, which is what a gallery is for:
		 * the capacity bar sits ABOVE its warning threshold so the fill is the platform's orange, the rating shows three
		 * of five stars, the stepper starts at 5 with its value beside it, the secure field holds a value (so it draws
		 * bullets rather than a placeholder), the search field holds a value (so its cancel chip is there to press), the
		 * progress bar is at 62 with its spinner turning, and the date pickers are all "now". */
		capacity = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(400, 372, 162, 18)];
		rating = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(400, 348, 162, 18)];
		stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(400, 314, 19, 27)];
		stepperValue = [[NSTextField alloc] initWithFrame:NSMakeRect(426, 318, 136, 20)];
		secure = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(400, 286, 162, 22)];
		search = [[NSSearchField alloc] initWithFrame:NSMakeRect(400, 258, 162, 22)];
		dateField = [[NSDatePicker alloc] initWithFrame:NSMakeRect(400, 230, 162, 22)];
		progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(400, 204, 140, 12)];
		spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(546, 202, 16, 16)];
		box = [[NSBox alloc] initWithFrame:NSMakeRect(574, 306, 162, 84)];
		boxButton = [[NSButton alloc] initWithFrame:NSMakeRect(8, 8, 140, 23)];
		tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(574, 190, 162, 110)];

		/* THE CAPACITY BAR'S TWO THRESHOLDS ARE THE REASON THE CLASS EXISTS: a progress bar says how far, a level
		 * indicator says how far AND whether that is bad. At 62 with a warning at 50 the fill is the orange one, and
		 * raising the value past 80 in a caller would turn it red. */
		[capacity setMinValue:0.0];
		[capacity setMaxValue:100.0];
		[capacity setWarningValue:50.0];
		[capacity setCriticalValue:80.0];
		[capacity setDoubleValue:62.0];
		/* THE RATING STYLE IS THE CELL'S DOOR: the control's initialiser makes a capacity cell, and `-cell` is how a
		 * caller reaches the style — the same shape a button's type takes through its cell. */
		[(NSLevelIndicatorCell *)[rating cell] setLevelIndicatorStyle:NSRatingLevelIndicatorStyle];
		[rating setMaxValue:5.0];
		[rating setDoubleValue:3.0];
		[stepper setMinValue:0.0];
		[stepper setMaxValue:10.0];
		[stepper setIncrement:1.0];
		[stepper setDoubleValue:5.0];
		[stepper setTarget:controller];
		[stepper setAction:@selector(stepperMoved:)];
		/* **THE READOUT IS A LABEL, NOT A SECOND KIND OF CONTROL**: a field with its editing, border and background
		 * doors off, which is what this tier (and the data window) uses a caption for. */
		[stepperValue setStringValue:@"Value: 5"];
		[stepperValue setEditable:NO];
		[stepperValue setSelectable:NO];
		[stepperValue setBordered:NO];
		[stepperValue setBezeled:NO];
		[stepperValue setDrawsBackground:NO];
		[(NSTextFieldCell *)[secure cell] setPlaceholderString:@"A secure field"];
		[secure setStringValue:@"hunter2"];	/* the bullets are the class's whole picture */
		[(NSTextFieldCell *)[search cell] setPlaceholderString:@"A search field"];
		[search setStringValue:@"Agora"];	/* a value is what puts the CANCEL chip on screen */
		[progress setStyle:NSProgressIndicatorBarStyle];
		[progress setIndeterminate:NO];
		[progress setMinValue:0.0];
		[progress setMaxValue:100.0];
		[progress setDoubleValue:62.0];
		[spinner setStyle:NSProgressIndicatorSpinningStyle];
		[spinner setIndeterminate:YES];
		[spinner setDisplayedWhenStopped:YES];
		[spinner startAnimation:nil];	/* the state a caller reads; this tier has no animation timer */
		[dateField setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
		[dateField setDateValue:[NSDate date]];
		[dateField setTarget:controller];
		[dateField setAction:@selector(dateChanged:)];
		[box setTitle:@"NSBox"];
		[boxButton setTitle:@"A box's button"];
		[boxButton setTarget:controller];
		[boxButton setAction:@selector(noop:)];
		{
			/* **THE CONTENT VIEW IS THE BOX'S, SO THE BOX RESIZES IT.** The frame here is a placeholder:
			 * `-setContentView:` immediately sets the view to the box's own content rectangle, and the button inside it
			 * keeps the frame a caller gave it. Passing the button itself as the content would stretch the button to fill
			 * the box instead. */
			NSView *boxContent = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 140.0, 50.0)];

			[boxContent addSubview:boxButton];
			[box setContentView:boxContent];
			[boxContent release];
		}
		/* **THE TAB VIEW'S TWO PANES ARE THE DATE PICKER'S OTHER TWO FACES.** The clock style is a picture of the time
		 * (a ring, ticks and three hands); the text-field style is the date and time as one formatted string. The strip's
		 * left column already shows the third, text-and-stepper style, so the three frames are one tab click apart. */
		{
			NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"clock"];
			NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 158.0, 80.0)];
			NSDatePicker *clockPicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(39.0, 0.0, 80.0, 80.0)];

			[clockPicker setDatePickerStyle:NSClockAndCalendarDatePickerStyle];
			[clockPicker setDatePickerElements:NSHourMinuteSecondDatePickerElementFlag];
			[clockPicker setDateValue:[NSDate date]];
			[clockPicker setTarget:controller];
			[clockPicker setAction:@selector(dateChanged:)];
			[pane addSubview:clockPicker];
			[clockPicker release];
			[item setLabel:@"Clock"];
			[item setView:pane];
			[pane release];
			[tabs addTabViewItem:item];
			[item release];
		}
		{
			NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"date"];
			NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 158.0, 80.0)];
			NSDatePicker *textPicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(6.0, 38.0, 146.0, 22.0)];
			NSTextField *caption = [[NSTextField alloc] initWithFrame:NSMakeRect(6.0, 8.0, 146.0, 20.0)];

			[textPicker setDatePickerStyle:NSTextFieldDatePickerStyle];
			/* HOUR AND MINUTE RATHER THAN THE SECONDS TOO: the pane is 146 points wide and the full
			 * "Oct 22, 2026, 1:28:53 PM" clips at its last word. A demonstration that shows a control's text cut
			 * off would be teaching the wrong thing about the control. */
			[textPicker setDatePickerElements:(NSYearMonthDayDatePickerElementFlag
				| NSHourMinuteDatePickerElementFlag)];
			[textPicker setDateValue:[NSDate date]];
			[textPicker setTarget:controller];
			[textPicker setAction:@selector(dateChanged:)];
			[pane addSubview:textPicker];
			[textPicker release];
			[caption setStringValue:@"A text field style"];
			[caption setEditable:NO];
			[caption setSelectable:NO];
			[caption setBordered:NO];
			[caption setBezeled:NO];
			[caption setDrawsBackground:NO];
			[caption setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
			[pane addSubview:caption];
			[caption release];
			[item setLabel:@"Date"];
			[item setView:pane];
			[pane release];
			[tabs addTabViewItem:item];
			[item release];
		}
		[content addSubview:capacity];
		[content addSubview:rating];
		[content addSubview:stepper];
		[content addSubview:stepperValue];
		[content addSubview:secure];
		[content addSubview:search];
		[content addSubview:dateField];
		[content addSubview:progress];
		[content addSubview:spinner];
		[content addSubview:box];
		[content addSubview:tabs];
		[content addSubview:push];
		[content addSubview:alt];
		[content addSubview:check];
		[content addSubview:readout];
		[content addSubview:radio];
		[content addSubview:off];
		[content addSubview:slider];
		[content addSubview:plain];
		[content addSubview:field];
		[content addSubview:sw];
		[content addSubview:scroll];
		[w setContentView:content];
		[w setTitle:@"Controls"];

		/* **AND THE TOOLBAR, WHICH IS THE STRIP THIS WINDOW NOW WEARS.** It is given the controller as its delegate,
		 * asked for labels beside its pictures (so the items are readable without a tooltip), and attached AFTER the
		 * content view so the window can grow the frame and leave the controls where they were. The icons are made
		 * once, before the delegate is asked for an item. */
		controller->gridIcon = fn_toolbar_icon(0);
		controller->playgroundIcon = fn_toolbar_icon(1);
		controller->actionIcon = fn_toolbar_icon(2);
		controller->tableIcon = fn_toolbar_icon(3);
		toolbar = [[NSToolbar alloc] initWithIdentifier:@"AGControlsToolbar"];
		[toolbar setDelegate:controller];
		[toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
		[toolbar setSelectedItemIdentifier:@"grid"];
		[w setToolbar:toolbar];

		/* **AND THE MENUS, WHICH ARE THE APPLICATION'S AND GO IN THE SERVER'S BAR.** View has the checked item and
		 * Edit the disabled one; both are validated against this controller, and the push button toggles the same
		 * checkbox their state is read from. */
		controller->checkbox = check;
		controller->readout = readout;
		controller->slider = slider;
		controller->stepperReadout = stepperValue;
		/* **AND EVERY ITEM WORTH TYPING CARRIES ITS SHORTCUT**, the Mac's own spellings: Cmd-N/O/W to make, open and
		 * close, Cmd-Z and Shift-Cmd-Z to undo and redo, Cmd-G/R for the two View toggles. HELP HAS NONE — a Help
		 * menu's own shortcut is a search field this tier has not got, and a made-up key would be one nobody typed. */
		add_menu(bar, @"File", [NSArray arrayWithObjects:@"New", @"Open", @"Close", nil],
			 [NSArray arrayWithObjects:@"n", @"o", @"w", nil], controller, @selector(noop:));
		/* **AND A DEMO MENU, WHERE THE TEXT PLAYGROUND LIVES.** One item, one window: the rich-text, tab-stop,
		 * attachment and table slices in a store a person can type in. */
		add_menu(bar, @"Demo", [NSArray arrayWithObjects:@"Text playground", nil],
			 [NSArray arrayWithObjects:@"t", nil], controller, @selector(showPlayground:));
		add_menu(bar, @"Data", [NSArray arrayWithObjects:@"Table & Outline", nil],
			 [NSArray arrayWithObjects:@"d", nil], controller, @selector(showDataViews:));
		add_menu(bar, @"Edit", [NSArray arrayWithObjects:@"Undo", @"Redo", nil],
			 [NSArray arrayWithObjects:@"z", @"Z", nil], controller, @selector(noop:));
		add_menu(bar, @"View", [NSArray arrayWithObjects:@"Show Grid", @"Show Ruler", nil],
			 [NSArray arrayWithObjects:@"g", @"r", nil], controller, @selector(toggleCheckbox:));
		add_menu(bar, @"Help", [NSArray arrayWithObjects:@"Agora Help", nil],
			 [NSArray arrayWithObjects:@"", nil], controller, @selector(noop:));
		[app setMainMenu:bar];

		/* **AND IT IS MADE KEY, WHICH IS WHAT A FRONTMOST WINDOW IS.** A theme's four states are the point of
		 * looking at it, and `-orderFront:` alone leaves the window inactive — so the ACTIVE art a theme ships for a
		 * focused window would never be on screen, and the thing being iterated on would be the grey half of it. On
		 * a real desktop the compositor's keyboard enter makes the APPLICATION active; the WINDOW is made key here. */
		[w makeKeyAndOrderFront:nil];
		/* **AND IT IS MADE THE KEYBOARD'S, WHICH IS HOW A FIELD IS FOCUSED AND NOT HOW IT IS MADE THE RESPONDER.**
		 * `-makeFirstResponder:` asks the field, the field opens a session, and the session makes the EDITOR the window's
		 * responder — so a field that is focused is a field a person can type into, and the line below is what makes
		 * that true rather than a decoration. */
		[w makeFirstResponder:field];
		/* **AND THE PLAYGROUND IS PUT ON SCREEN LAST, SO IT IS IN FRONT OF THE EYE.** The compositor stacks in map order,
		 * so a window mapped after the controls window sits above it; it is ORDERED FRONT rather than made key, so the
		 * CONTROLS keep the keyboard and their field keeps its editor while the playground is what a person sees. */
		if (showPlaygroundWindow) {
			[controller showPlayground:nil];
		}
		if (showData) {
			[controller showDataViews:nil];
		}
		/* ONE LINE OF GEOMETRY, so that a screenshot can be READ against the numbers the application believes rather
		 * than against a guess about where a window landed. */
		fprintf(stderr, "controls: toolbar = %.0f-point band, %.0f-wide view at y=%.0f, %lu items\n",
			[toolbar cg_toolbarHeight], [[toolbar cg_view] frame].size.width,
			[[toolbar cg_view] frame].origin.y, (unsigned long)[[toolbar items] count]);
		fprintf(stderr, "controls: window frame = %.0f,%.0f %.0fx%.0f; content = %.0fx%.0f; slider = %.0f,%.0f; "
			"field = %.0f,%.0f %.0fx%.0f\n",
			[w frame].origin.x, [w frame].origin.y, [w frame].size.width, [w frame].size.height,
			[content frame].size.width, [content frame].size.height,
			[slider frame].origin.x, [slider frame].origin.y,
			[field frame].origin.x, [field frame].origin.y, [field frame].size.width, [field frame].size.height);
		/* **AND THE NEW-CONTROLS STRIP'S GEOMETRY**, so a screenshot can be read against the frames the application
		 * believes rather than against a guess about where a control landed. The tab view's frame is printed too, because
		 * its panes are sized by the tab strip rather than by the caller. */
		fprintf(stderr, "controls: gallery = levels %.0fx%.0f, stepper %.0fx%.0f, secure %.0fx%.0f, search %.0fx%.0f, "
			"date %.0fx%.0f, progress %.0fx%.0f, box %.0fx%.0f, tabs %.0fx%.0f\n",
			[capacity frame].size.width, [capacity frame].size.height,
			[stepper frame].size.width, [stepper frame].size.height,
			[secure frame].size.width, [secure frame].size.height,
			[search frame].size.width, [search frame].size.height,
			[dateField frame].size.width, [dateField frame].size.height,
			[progress frame].size.width, [progress frame].size.height,
			[box frame].size.width, [box frame].size.height,
			[tabs frame].size.width, [tabs frame].size.height);
		/* **AND THE POP-UP BUTTON'S, WHICH IS THE ONE FRAME HERE THE CELL COMPUTED RATHER THAN THE CALLER.** It is
		 * fitted to its title plus its arrow, so its width is `-cellSizeForBounds:`'s answer and printing it is how
		 * a reader checks the measurement against the button they can see. */
		fprintf(stderr, "controls: popup frame = %.0f,%.0f %.0fx%.0f  bounds = %.0fx%.0f\n",
			[popup frame].origin.x, [popup frame].origin.y, [popup frame].size.width, [popup frame].size.height,
			[popup bounds].size.width, [popup bounds].size.height);
		/* AND WHO HAS THE KEYBOARD, which is what decides whether a keystroke reaches the text view at all: a window
		 * sends KEY events to its FIRST RESPONDER, so a field that is not the first responder is one nobody can type
		 * into — and printing this is cheaper than guessing when it is not. */
		fprintf(stderr, "controls: first responder = %s\n",
			([field currentEditor] != nil && [w firstResponder] == (id)[field currentEditor])
				? "the field's editor" : "NOT the field's editor");
		/* **AND WHICH CHROME THIS WINDOW WILL WEAR**, printed for the same reason the geometry is: iterating on a
		 * theme means knowing whether the one you pointed at is the one that resolved. */
		{
			AGChromeTheme *theme = [AGChromeTheme sharedTheme];

			if (theme != nil) {
				fprintf(stderr, "controls: chrome theme = %s (%g-point strip)\n",
					[[theme directory] UTF8String], (double)[theme titleBarHeight]);
			} else {
				fprintf(stderr, "controls: no chrome theme — drawing the chrome's own bar and marks\n");
			}
		}
		if (seconds > 0) {
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds];

			while ([deadline timeIntervalSinceNow] > 0.0) {
				NSEvent *e = [app nextEventMatchingMask:NSAnyEventMask
					untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
					inMode:nil dequeue:YES];

				if (e != nil) {
					[app sendEvent:e];
				}
				[app updateWindows];
			}
		} else {
			[app run];
		}
	}
	return 0;
}
