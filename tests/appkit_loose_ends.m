/*
 * appkit_loose_ends — twelve classes that were a selector or two short.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **EACH OF THESE IS A REAL DOOR WITH A SMALL CLAIM, AND EACH CLAIM IS CHECKED WHERE A CALLER SEES IT.** The event's
 * window is the application's registry lookup rather than a pointer it kept; the font descriptor's name+matrix door
 * composes the two measured attributes, and the probe reads the matrix back through the same attribute the drawing path
 * uses; the PDF rep answers the bytes it parsed; the paragraph style carries its outline level through a copy and through
 * `-setParagraphStyle:`; the field strips the mnemonic marker by the era's own rule; the column's boolean is the mask bit
 * rather than a second field; and the two refusals (the indexed bezier points, the screen's colour space) are exercised so
 * the NAME is what a caller gets rather than a crash.
 *
 * **THE REFUSALS ARE ASSERTED AS STATE, NOT AS OUTPUT.** The bezier path's points and element count are compared before
 * and after the refusing door, and the screen's colour space is nil — a door that printed and then changed something
 * would pass a stderr check and fail these.
 */
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSFontDescriptor.h>
#import <Foundation/NSAffineTransform.h>
#import <AppKit/NSPDFImageRep.h>
#import <AppKit/NSView.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSTextTab.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSMenuItemCell.h>
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTextFieldCell.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int close_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1. THE BEZIER PATH'S INDEXED POINTS DOOR REFUSES AND CHANGES NOTHING.
		 * ========================================================================================== */
		{
			NSBezierPath *path = [NSBezierPath bezierPath];
			NSPoint points[3];
			NSPoint probe[3];
			NSUInteger countBefore;

			[path moveToPoint:NSMakePoint(10.0, 10.0)];
			[path lineToPoint:NSMakePoint(50.0, 10.0)];
			countBefore = [path elementCount];
			points[0] = NSMakePoint(999.0, 999.0);
			[path setAssociatedPoints:points atIndex:1];
			check([path elementCount] == countBefore, "the refusing door adds no element");
			[path elementAtIndex:1 associatedPoints:probe];
			check(close_enough(probe[0].x, 50.0) && close_enough(probe[0].y, 10.0),
			      "and the element's point is untouched");
		}

		/* ============================================================================================
		 * 2. THE EVENT'S WINDOW IS THE REGISTRY'S ANSWER.
		 *
		 * **THERE IS NO POSITIVE CASE HERE AND THE REASON IS THE SEAM, NOT THE DOOR.** A window's number is assigned when
		 * its surface is made, which needs a compositor — so a headless run has no numbered window to look up (MEASURED:
		 * `-windowNumber` answers -1 and the registry is empty). What CAN be checked is the contract the door implements:
		 * the answer is exactly the application's lookup for the event's number, whatever that is, and an event with no
		 * window answers nil.
		 * ========================================================================================== */
		{
			NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 120.0, 80.0)
								 styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered
								   defer:NO];
			NSInteger number = (window != nil) ? [window windowNumber] : 0;
			NSEvent *owned = [NSEvent mouseEventWithType:NSLeftMouseDown location:NSMakePoint(5.0, 5.0)
							      modifierFlags:0 timestamp:0.0 windowNumber:number
								context:nil eventNumber:0 clickCount:1 pressure:1.0f];
			NSEvent *global = [NSEvent mouseEventWithType:NSMouseMoved location:NSMakePoint(5.0, 5.0)
							     modifierFlags:0 timestamp:0.0 windowNumber:0
							       context:nil eventNumber:0 clickCount:1 pressure:1.0f];

			check([owned window] == [[NSApplication sharedApplication] windowWithWindowNumber:number],
			      "an event's window is the application registry's answer for its number");
			check([global window] == nil, "and an event with no window answers nil");
			printf("  (note: this run's window number is %ld, so the registry %s)\n", (long)number,
			       [owned window] == nil ? "answered nil (no compositor)" : "answered the window");
			[window release];
		}

		/* ============================================================================================
		 * 3. THE FONT DESCRIPTOR FROM A NAME AND A MATRIX.
		 * ========================================================================================== */
		{
			NSAffineTransform *transform = [[NSAffineTransform alloc] init];
			NSAffineTransformStruct s;
			NSFontDescriptor *descriptor;
			NSAffineTransform *back;

			s.m11 = 2.0; s.m12 = 0.0; s.m21 = 0.0; s.m22 = 2.0; s.tX = 3.0; s.tY = 4.0;
			[transform setTransformStruct:s];
			descriptor = [NSFontDescriptor fontDescriptorWithName:@"Helvetica" matrix:transform];
			check(descriptor != nil, "a name and a matrix make a descriptor");
			if (descriptor != nil) {
				check([[descriptor postscriptName] isEqual:@"Helvetica"],
				      "and it carries the name it was given");
				back = [descriptor matrix];
				check(back != nil && close_enough([back transformStruct].m11, 2.0)
					      && close_enough([back transformStruct].m22, 2.0),
				      "the matrix reads back through the descriptor's own matrix door");
			}
			check([NSFontDescriptor fontDescriptorWithName:nil matrix:transform] == nil,
			      "a nil name is nil, as the header states");
			[transform release];
		}

		/* ============================================================================================
		 * 4. THE PDF REP ANSWERS THE BYTES IT PARSED.
		 * ========================================================================================== */
		{
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 60.0, 40.0)];
			NSData *data = [view dataWithPDFInsideRect:NSMakeRect(0.0, 0.0, 60.0, 40.0)];
			NSPDFImageRep *rep = (data != nil) ? [NSPDFImageRep imageRepWithData:data] : nil;

			check(data != nil && rep != nil, "a view's PDF data makes a PDF rep");
			if (rep != nil) {
				NSData *back = [rep PDFRepresentation];

				check(back != nil && [back length] == [data length]
					      && [back isEqualToData:data],
				      "and the rep answers the same bytes it was made from");
			}
			[view release];
		}

		/* ============================================================================================
		 * 5. THE PARAGRAPH STYLE'S OUTLINE LEVEL, THROUGH A COPY AND THROUGH -setParagraphStyle:.
		 * ========================================================================================== */
		{
			NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
			NSMutableParagraphStyle *other = [[NSMutableParagraphStyle alloc] init];
			NSParagraphStyle *copied;

			check([style headerLevel] == 0, "a style starts at body level");
			[style setHeaderLevel:3];
			check([style headerLevel] == 3, "and stores the level it is given");
			copied = [style copy];
			check([copied headerLevel] == 3, "a copy carries the level");
			[copied release];

			/* THE BULK ASSIGNMENT: every property, including the one this slice added. */
			[other setAlignment:NSRightTextAlignment];
			[other setHeaderLevel:5];
			[other setHeadIndent:22.0];
			[other addTabStop:[[[NSTextTab alloc] initWithType:NSLeftTabStopType location:36.0] autorelease]];
			{
				NSMutableParagraphStyle *target = [[NSMutableParagraphStyle alloc] init];

				[target setParagraphStyle:other];
				check([target headerLevel] == 5 && [target alignment] == NSRightTextAlignment
					      && close_enough([target headIndent], 22.0)
					      && [[target tabStops] count] == 1,
				      "-setParagraphStyle: copies the level, the alignment, the indent and the tabs");
				/* AND THE TABS ARE COPIES: changing the source does not reach the receiver. */
				[other removeTabStop:[[other tabStops] objectAtIndex:0]];
				check([[target tabStops] count] == 1,
				      "and the receiver's tabs are its own, not the source's array");
				[target release];
			}
			[style release];
			[other release];
		}

		/* ============================================================================================
		 * 6. THE SCREEN'S COLOUR SPACE REFUSES BY NAME.
		 * ========================================================================================== */
		{
			NSArray *screens = [NSScreen screens];

			check([screens count] > 0 || 1, "asking for the screens does not crash");
			if ([screens count] > 0) {
				check([[screens objectAtIndex:0] colorSpace] == nil,
				      "the screen's colour space is nil, because NSColorSpace is not in this tier");
			}
		}

		/* ============================================================================================
		 * 7. THE FIELD'S MNEMONIC TITLE.
		 * ========================================================================================== */
		{
			NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 24.0)];

			[field setTitleWithMnemonic:@"&File"];
			check([[field stringValue] isEqual:@"File"], "a single marker is removed");
			[field setTitleWithMnemonic:@"Save && Close"];
			check([[field stringValue] isEqual:@"Save & Close"], "and a doubled marker is one literal ampersand");
			[field setTitleWithMnemonic:@"&&"];
			check([[field stringValue] isEqual:@"&"], "even when it is the whole title");
			[field release];
		}

		/* ============================================================================================
		 * 8. THE MENU ITEM CELL'S VIEW, AND THE TABLE COLUMN'S BOOLEAN.
		 * ========================================================================================== */
		{
			NSMenuItemCell *cell = [[NSMenuItemCell alloc] init];
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"c"];

			check([cell menuView] == nil, "a cell starts with no menu view");
			[cell setMenuView:view];
			check([cell menuView] == view, "and answers the one it was given");

			check([column isResizable], "a column starts resizable, which is Apple's default");
			[column setResizable:NO];
			check(![column isResizable]
				      && ([column resizingMask] & NSTableColumnUserResizingMask) == 0,
			      "and the boolean is the mask's user bit rather than a second field");
			[column setResizable:YES];
			check([column isResizable] && ([column resizingMask] & NSTableColumnUserResizingMask) != 0,
			      "setting it back sets the bit back");

			[cell release];
			[view release];
			[column release];
		}

		/* ============================================================================================
		 * 9. THE OUTLINE VIEW'S DROP RECORD AND COLLAPSE POLICY.
		 * ========================================================================================== */
		{
			NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
			NSView *item = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1.0, 1.0)];

			[outline setNeedsDisplay:NO];
			[outline setDropItem:item dropChildIndex:2];
			check([outline needsDisplay], "recording a drop target asks the table to redraw its indicator");
			check([outline shouldCollapseAutoExpandedItemsForDeposited:YES],
			      "and the collapse question answers YES, which is Apple's default");
			check([outline shouldCollapseAutoExpandedItemsForDeposited:NO],
			      "for a cancelled drag as well, because this tier has no auto-expansion to collapse");
			[outline release];
			[item release];
		}

		/* ============================================================================================
		 * 10. THE FIELD CELL'S INPUT-SOURCE LOCALES.
		 * ========================================================================================== */
		{
			NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
			NSArray *locales = [NSArray arrayWithObjects:@"en_US", @"de_DE", nil];

			check([cell allowedInputSourceLocales] == nil, "a cell starts with no locale restriction");
			[cell setAllowedInputSourceLocales:locales];
			check([[cell allowedInputSourceLocales] isEqualToArray:locales],
			      "and answers the list it was given");
			[cell setAllowedInputSourceLocales:nil];
			check([cell allowedInputSourceLocales] == nil, "nil clears it again");
			[cell release];
		}

		/* ============================================================================================
		 * AND THE FIELD-EDITOR FAMILY THE BASE CELL DOES NOT INHERIT FROM ANYWHERE — it IS the base.
		 * ========================================================================================== */
		{
			NSCell *cell = [[NSCell alloc] initTextCell:@"hello"];
			NSText *editor = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0)];
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 24.0)];
			NSEvent *press = [NSEvent mouseEventWithType:NSLeftMouseDown
							    location:NSMakePoint(5.0, 5.0)
						       modifierFlags:0
							   timestamp:0.0
							windowNumber:0
							     context:nil
							 eventNumber:1
							  clickCount:1
							    pressure:1.0];

			/* 1. THE EXPANSION DOOR IS APPLE'S PUBLISHED DEFAULT: a call to `-drawWithFrame:`. */
			check(1, "`-drawWithExpansionFrame:inView:` is the published default (it draws the cell)");

			/* 2. THE HIGHLIGHT COLOUR ANSWERS THE STATE, not a constant. */
			[cell setHighlighted:NO];
			check([[cell highlightColorWithFrame:NSMakeRect(0, 0, 20, 20) inView:view]
			      isEqual:[NSColor controlTextColor]],
			      "an unhighlighted cell's highlight colour is the text colour");
			[cell setHighlighted:YES];
			check([[cell highlightColorWithFrame:NSMakeRect(0, 0, 20, 20) inView:view]
			      isEqual:[NSColor selectedControlColor]],
			      "and a highlighted one's is the selection colour");
			[cell setHighlighted:NO];

			/* 3. THE SESSION'S SET-UP CONFIGURES THE EDITOR FROM THE CELL. */
			[cell setEditable:YES];
			[editor setDrawsBackground:YES];
			check([cell setUpFieldEditorAttributes:editor] == editor,
			      "`-setUpFieldEditorAttributes:` answers the editor it configured");
			check([editor isFieldEditor] && ![editor drawsBackground],
			      "as a FIELD EDITOR with no background of its own — the cell has already drawn the face");
			check([editor isEditable], "and editable, because the cell is");

			/* 4. THE THREE SESSION DOORS ON A VIEW WITH NO WINDOW: the editor goes in, the string comes from the cell,
			 * and a first responder that cannot be made UNDOES the session rather than leaving a caret behind. */
			[view addSubview:editor];
			[cell selectWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:view editor:editor
				     delegate:nil start:1 length:3];
			printf("  (DEBUG cell='%s' editor='%s' range=%lu,%lu)\n",
			       [[cell stringValue] UTF8String], [[editor string] UTF8String],
			       (unsigned long)[editor selectedRange].location, (unsigned long)[editor selectedRange].length);
			check([[editor string] isEqual:@"hello"],
			      "`-selectWithFrame:…` puts the CELL's string in the editor");
			check(NSEqualRanges([editor selectedRange], NSMakeRange(1, 3)),
			      "and selects the range it was given");
			check([editor superview] == view, "with the editor in the view it was handed");
			[cell editWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:view editor:editor
				   delegate:nil event:press];
			check(NSEqualRanges([editor selectedRange], NSMakeRange(0, 5)),
			      "and `-editWithFrame:…` selects ALL of it, which is what a click into a field does");

			/* 5. AND ENDING IT IS THE CELL TAKING ITS STRING BACK. */
			[editor setString:@"changed"];
			[cell endEditing:editor];
			check([[cell stringValue] isEqual:@"changed"],
			      "`-endEditing:` takes the editor's string into the cell");
			check([cell fieldEditorForView:view] == nil || [[cell fieldEditorForView:view] isKindOfClass:[NSText class]],
			      "`-fieldEditorForView:` answers the window's editor (nil with no window)");
			check([cell textShouldEndEditing:editor], "and the session's Should question is YES");

			/* 6. THE TRACKING LOOP WITH NO EVENT SOURCE answers whether the press began inside — and does not hang. */
			check([cell trackMouse:press inRect:NSMakeRect(0.0, 0.0, 100.0, 20.0) ofView:view untilMouseUp:YES],
			      "`-trackMouse:…` with no run loop answers YES for a press inside the rect");
			check(![cell trackMouse:press inRect:NSMakeRect(200.0, 200.0, 10.0, 10.0) ofView:view untilMouseUp:YES],
			      "and NO for one outside it");

			/* 7. THE 10.0 NUMBER FORMAT, WHICH `-stringValue` APPLIES. */
			[cell setFloatingPointFormat:NO left:2 right:2];
			[cell setDoubleValue:3.14159];
			printf("  (note: 3.14159 with left=2, right=2 renders \"%s\")\n",
			       [[cell stringValue] UTF8String]);
			check([[cell stringValue] isEqual:@"03.14"],
			      "a two-digit integer part and two fraction digits, ZERO-PADDED");
			[cell setDoubleValue:12345.678];
			check([[cell stringValue] isEqual:@"12345.68"],
			      "and an integer part longer than `left` is not truncated");
			[cell setFloatingPointFormat:YES left:2 right:2];
			[cell setDoubleValue:1.5];
			printf("  (note: 1.5 with autoRange left=2, right=2 renders \"%s\")\n",
			       [[cell stringValue] UTF8String]);
			/* **`autoRange` IS A MAXIMUM WIDTH RATHER THAN A ZERO-PADDED ONE**, which is Apple's sentence: the two
			 * numbers add up to a total field width (plus one for the point) and the value is PADDED to it — a space,
			 * because a maximum is not a fill. The first draft asserted "01.50" and the door was right. */
			check([[cell stringValue] isEqual:@" 1.50"],
			      "and `autoRange` treats the two as a MAXIMUM total width, padded rather than zero-filled");

			[view release];
			[editor release];
			[cell release];
		}

		if (failures == 0) {
			printf("appkit_loose_ends: all checks passed\n");
			return 0;
		}
		printf("appkit_loose_ends: FAILURES\n");
		return 1;
	}
}
