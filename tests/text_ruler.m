/*
 * text_ruler — the text system's ruler: tab stops as markers, and a drag that reaches the layout.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLAIM IS A ROUND TRIP, NOT A COUNT.** Showing a text view's ruler asks the layout manager for one marker per tab
 * stop; dragging a marker asks the ruler's client to rebuild the paragraph's tab stops from the marker list; and the
 * LAYOUT then reflows. So the test measures the x of a character after a tab, drags the tab's marker fifty points to the
 * right, and measures it again — a claim that the gesture reached the engine rather than a claim that a list changed.
 *
 * **AND THE COPY/PASTE PAIR IS THE OTHER ROUND TRIP.** `-copyRuler:` writes the paragraph's format plus the run's font
 * under `NSRulerPboardType`; `-pasteRuler:` writes them onto the selection's paragraph. The test copies the first
 * paragraph's ruler, pastes it onto a second paragraph that had none, and reads the tab stops back out of the store.
 *
 * Everything else here is the arithmetic around those two: the marker location includes the origin offset (so a tab and
 * a hash mark agree), the reserved band is the tallest marker, `-usesRuler:NO` means no ruler at all, and the manager's
 * accessory door answers nil with a reason rather than pretending to build the era's control cluster.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextTab.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSRulerView.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSEvent.h>
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

static int close_enough(CGFloat a, CGFloat b, CGFloat tolerance)
{
	return fabs((double)(a - b)) <= (double)tolerance;
}

static NSEvent *mouse(NSEventType type, NSPoint point)
{
	return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0.0
			      windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1.0f];
}

/* THE PARAGRAPH STYLE AT AN INDEX, read back out of the store the way a caller would. */
static NSParagraphStyle *style_at(NSTextView *view, NSUInteger index)
{
	NSDictionary *attributes = [[view textStorage] attributesAtIndex:index effectiveRange:NULL];

	return [attributes objectForKey:NSParagraphStyleAttributeName];
}

static CGFloat glyph_x(NSTextView *view, NSUInteger character)
{
	NSLayoutManager *manager = [view layoutManager];

	return [manager cg_offsetForGlyphAtIndex:[manager glyphIndexForCharacterAtIndex:character]];
}

int main(void)
{
	@autoreleasepool {
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 200.0)];
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 240.0)];
		NSTextStorage *store;
		NSLayoutManager *manager;
		NSMutableParagraphStyle *first;
		NSTextTab *tabA;
		NSTextTab *tabB;

		[scroll setDocumentView:view];
		store = [view textStorage];
		manager = [view layoutManager];
		[view setString:@"a\tb\nsecond\tparagraph\n"];

		/* 1. PARAGRAPH ONE GETS TWO TABS; PARAGRAPH TWO GETS NONE. */
		first = [[NSMutableParagraphStyle alloc] init];
		tabA = [[NSTextTab alloc] initWithType:NSLeftTabStopType location:100.0];
		tabB = [[NSTextTab alloc] initWithType:NSRightTabStopType location:200.0];
		[first addTabStop:tabA];
		[first addTabStop:tabB];
		[first setAlignment:NSLeftTextAlignment];
		[store addAttribute:NSParagraphStyleAttributeName value:first range:NSMakeRange(0, 5)];
		[tabA release];
		[tabB release];
		[first release];

		/* 2. THE VIEW DEFAULTS: USES A RULER, SHOWS NONE. */
		check([view usesRuler], "a text view uses a ruler by default");
		check(![view isRulerVisible], "and shows none until it is asked");
		check([scroll horizontalRulerView] == nil, "and the scroll view has built no ruler yet");

		[view setSelectedRange:NSMakeRange(0, 0)];
		[view setRulerVisible:YES];
		check([view isRulerVisible], "asking shows it");
		check([scroll hasHorizontalRuler] && [scroll rulersVisible], "which means the scroll view has one and shows it");
		{
			NSRulerView *ruler = [scroll horizontalRulerView];

			check(ruler != nil && [ruler orientation] == NSHorizontalRuler, "a text ruler is horizontal");
			check([ruler clientView] == view, "its client is the text view");
			check(close_enough([ruler originOffset], (CGFloat)NS_TEXT_INSET, 0.001),
			      "its zero is the text's own inset, which is what a tab stop is measured from");
			check(close_enough([ruler ruleThickness], 14.0, 0.001), "and its rule strip is the strip the marks need");

			/* 3. ONE MARKER PER TAB STOP, AT THE TAB'S LOCATION PLUS THE OFFSET. */
			check([[ruler markers] count] == 2, "the paragraph's two tab stops are two markers");
			{
				NSRulerMarker *m0 = [[ruler markers] objectAtIndex:0];
				NSRulerMarker *m1 = [[ruler markers] objectAtIndex:1];

				check(close_enough([m0 markerLocation], 104.0, 0.001),
				      "the first marker's location is the tab's 100 plus the four-point offset");
				check(close_enough([m1 markerLocation], 204.0, 0.001), "and the second's is its 200 plus the same");
				check([(NSTextTab *)[m0 representedObject] tabStopType] == NSLeftTabStopType,
				      "and each marker carries the tab it stands for, kind and all");
				check([(NSTextTab *)[m1 representedObject] tabStopType] == NSRightTabStopType,
				      "including the right tab");
				check(close_enough([ruler reservedThicknessForMarkers],
						   [m0 thicknessRequiredInRuler], 0.001),
				      "the reserved band is the height the markers need");
				check(close_enough([ruler requiredThickness],
						   14.0 + [ruler reservedThicknessForMarkers], 0.001),
				      "so the strip is the rule plus that band, and nothing is clipped");
			}
		}

		/* 4. THE MARKER LIST FOLLOWS THE INSERTION POINT'S PARAGRAPH — on the selection change alone, which is where
		 * the view hangs the update, so no caller has to remember to ask. */
		[view setSelectedRange:NSMakeRange(8, 0)];
		check([[[scroll horizontalRulerView] markers] count] == 0,
		      "moving the caret into a paragraph with no tabs empties the ruler");

		[view setSelectedRange:NSMakeRange(0, 0)];
		check([[[scroll horizontalRulerView] markers] count] == 2,
		      "and moving back restores them, without an explicit -updateRuler");

		/* 5. THE DRAG REACHES THE ENGINE: a marker moved fifty points changes where the tab sends the text. */
		{
			NSRulerView *ruler = [scroll horizontalRulerView];
			NSRulerMarker *marker = [[ruler markers] objectAtIndex:0];
			CGFloat before = glyph_x(view, 2);
			CGFloat after;

			check([ruler trackMarker:marker withMouseEvent:mouse(NSLeftMouseDown, NSMakePoint(104.0, 5.0))],
			      "the drag begins on the marker");
			[ruler mouseDragged:mouse(NSLeftMouseDragged, NSMakePoint(154.0, 5.0))];
			check(close_enough([marker markerLocation], 154.0, 0.001), "the marker follows the pointer");
			[ruler mouseUp:mouse(NSLeftMouseUp, NSMakePoint(154.0, 5.0))];
			after = glyph_x(view, 2);
			check(close_enough(after - before, 50.0, 1.0),
			      "and the text after the tab moved fifty points, so the gesture reached the layout");
			check(close_enough([[[style_at(view, 0) tabStops] objectAtIndex:0] location], 150.0, 0.001),
			      "the paragraph's first tab stop is the new location, with the ruler's offset taken back out");
			check([[[style_at(view, 0) tabStops] objectAtIndex:0] tabStopType] == NSLeftTabStopType,
			      "and it kept its kind, because the marker carried the tab");
		}

		/* 6. ADDING AND REMOVING MARKERS IS ADDING AND REMOVING TABS. */
		{
			NSRulerView *ruler = [scroll horizontalRulerView];
			NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(9.0, 8.0)];
			NSRulerMarker *extra = [[NSRulerMarker alloc] initWithRulerView:ruler markerLocation:304.0
										image:image imageOrigin:NSZeroPoint];

			[ruler addMarker:extra];
			check([[style_at(view, 0) tabStops] count] == 3,
			      "a marker added to the ruler becomes a tab stop in the paragraph");
			check(close_enough([[[style_at(view, 0) tabStops] objectAtIndex:2] location], 300.0, 0.001),
			      "at the location the marker names, offset removed");
			check([[[style_at(view, 0) tabStops] objectAtIndex:2] tabStopType] == NSLeftTabStopType,
			      "and a marker that stands for no tab is a LEFT one, which is the era's default tab");

			[ruler removeMarker:extra];
			check([[style_at(view, 0) tabStops] count] == 2,
			      "removing the marker removes the tab stop again");
			check([view rulerView:ruler shouldAddMarker:extra], "the client allows an add");
			check([view rulerView:ruler shouldMoveMarker:extra], "and a move");
			check([view rulerView:ruler shouldRemoveMarker:extra], "and a remove");
			[extra release];
			[image release];
		}

		/* 7. COPY AND PASTE, WHICH IS THE PARAGRAPH'S FORMAT PLUS THE RUN'S FONT. */
		{
			NSMutableParagraphStyle *second = [[NSMutableParagraphStyle alloc] init];
			NSParagraphStyle *pasted;

			[second setAlignment:NSRightTextAlignment];
			[store addAttribute:NSParagraphStyleAttributeName value:second range:NSMakeRange(8, 16)];
			[second release];
			check([[style_at(view, 8) tabStops] count] == 0, "the second paragraph starts with no tabs");

			[view setSelectedRange:NSMakeRange(0, 0)];
			[view copyRuler:nil];
			[view setSelectedRange:NSMakeRange(8, 0)];
			[view pasteRuler:nil];
			pasted = style_at(view, 8);
			check(pasted != nil && [[pasted tabStops] count] == 2,
			      "pasting the ruler gives the second paragraph the first one's two tab stops");
			check(close_enough([[[pasted tabStops] objectAtIndex:0] location], 150.0, 0.001),
			      "at the locations the first paragraph had after the drag");
			check([[[pasted tabStops] objectAtIndex:1] tabStopType] == NSRightTabStopType,
			      "with each tab's kind preserved");
			check([pasted alignment] == NSLeftTextAlignment,
			      "and the alignment travels with it, because a ruler is the whole paragraph format");
		}

		/* 8. THE ACCESSORY DOOR REFUSES, AND THE RESERVE COSTS NOTHING. */
		{
			NSRulerView *ruler = [scroll horizontalRulerView];
			NSView *accessory = [manager rulerAccessoryViewForTextView:view
							     paragraphStyle:style_at(view, 0)
								      ruler:ruler
								    enabled:YES];

			check(accessory == nil, "the accessory strip is refused rather than faked");
			check(close_enough([ruler reservedThicknessForAccessoryView], 0.0, 0.001),
			      "and the ruler reserves nothing for it");
		}

		/* 9. THE TWO WAYS TO STOP SHOWING IT. */
		[view toggleRuler:nil];
		check(![view isRulerVisible], "-toggleRuler: hides a visible ruler");
		[view toggleRuler:nil];
		check([view isRulerVisible], "and shows a hidden one");
		[view setUsesRuler:NO];
		check(![view isRulerVisible], "a view that stops using a ruler stops showing it");
		[view setRulerVisible:YES];
		check(![view isRulerVisible], "and asking to show one again does nothing, because there is none to show");
		[view setUsesRuler:YES];

		[scroll release];
		[view release];

		if (failures == 0) {
			printf("text_ruler: all checks passed\n");
			return 0;
		}
		printf("text_ruler: FAILURES\n");
		return 1;
	}
}
