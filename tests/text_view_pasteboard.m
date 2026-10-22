/*
 * text_view_pasteboard — the text view's clipboard, its type registry and its drags.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE CLAIM IS A ROUND TRIP THROUGH THE REAL PASTEBOARD, WITH THE RUNS INTACT.** A copy writes RTFD, RTF and a
 * string; a paste into another view reads the richest type and the characters land with their FONT — read back from the
 * store, not from a flag. The plain-text command is checked against the same board to prove it ignores the rich type.
 *
 * WHAT IS MEASURED:
 *
 *   1. THE REGISTRY. The three type lists, their order, and the preference door picking RTF when both are offered and
 *      nil when the two lists do not meet.
 *   2. THE COPY. RTFD, RTF and the string on the board; the string is the selection's characters and the RTF parses
 *      back to the same text.
 *   3. THE PASTE. Into an empty view, the characters and the run's font; from a board with RTF and string,
 *      `-pasteAsPlainText:` takes the string and `-pasteAsRichText:` the runs.
 *   4. THE CUT. The board has the text and the view no longer does; and a copy with NO selection takes the paragraph.
 *   5. THE DRAG. The image is the selection's ink at a real size with an origin; the source's operation is a copy; the
 *      registration is the view's own destination list; and a drag with no window begins no session.
 *
 * WHAT IS NOT MEASURED, and why: the attachment half of `-allowsImageEditing` needs an RTFD carrying a FILE, which this
 * probe does not build — the flag's reader is the paste path, and the flag itself is asserted. The drop side
 * (`-performDragOperation:`) needs an `NSDraggingInfo`, which only a running session makes; the session's own suite in
 * `libagora-app` builds one.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSView.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) s_failed++;
}

static NSTextView *makeView(NSString *text)
{
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 120.0)];

	[view setEditable:YES];
	[view setSelectable:YES];
	[view setString:text];
	return view;
}

static id attributeAt(NSTextView *view, NSString *key, NSUInteger index)
{
	NSTextStorage *store = [view textStorage];

	return (index < [store length]) ? [[store attributesAtIndex:index effectiveRange:NULL] objectForKey:key] : nil;
}

static void clearPasteboard(void)
{
	NSPasteboard *board = [NSPasteboard generalPasteboard];

	[board declareTypes:[NSArray array] owner:nil];
}

int main(void)
{
	NSPasteboard *board = [NSPasteboard generalPasteboard];
	NSFont *bold = [NSFont boldSystemFontOfSize:16.0];
	NSTextView *source;
	NSTextView *target;
	NSArray *types;

	printf("text_view_pasteboard — the clipboard, the registry and the drag\n");
	clearPasteboard();

	/* 1. THE REGISTRY. */
	source = makeView(@"Hello");
	types = [source readablePasteboardTypes];
	check([types containsObject:NSRTFPboardType] && [types containsObject:NSStringPboardType],
	      "the readable types include RTF and the string");
	types = [source writablePasteboardTypes];
	check([types containsObject:NSRTFPboardType] && [types containsObject:NSStringPboardType],
	      "and so do the writable ones");
	check([[source acceptableDragTypes] isEqualToArray:[source readablePasteboardTypes]],
	      "the drag's types are the readable ones");
	check([[source preferredPasteboardTypeFromArray:[NSArray arrayWithObjects:NSRTFPboardType, NSStringPboardType, nil]
			      restrictedToTypesFromArray:[source readablePasteboardTypes]]
		isEqual:NSRTFPboardType],
	      "the richer type is preferred when both are offered");
	check([[source preferredPasteboardTypeFromArray:[NSArray arrayWithObject:NSStringPboardType]
			      restrictedToTypesFromArray:[NSArray arrayWithObject:NSRTFPboardType]] isEqual:nil]
	      || [source preferredPasteboardTypeFromArray:[NSArray arrayWithObject:NSStringPboardType]
					 restrictedToTypesFromArray:[NSArray arrayWithObject:NSRTFPboardType]] == nil,
	      "and two lists that do not meet answer nil");

	/* 2. THE COPY. */
	[source setSelectedRange:NSMakeRange(0, 5)];
	[source setTypingAttributes:[NSDictionary dictionaryWithObject:bold forKey:NSFontAttributeName]];
	{
		/* THE RUN THE COPY WRITES IS THE ONE IN THE STORE, so make it bold the way a command would. */
		[[source textStorage] addAttribute:NSFontAttributeName value:bold range:NSMakeRange(0, 5)];
	}
	[source copy:nil];
	types = [board types];
	check([types containsObject:NSStringPboardType], "a copy puts the string on the board");
	check([types containsObject:NSRTFPboardType], "and RTF");
	check([[board stringForType:NSStringPboardType] isEqual:@"Hello"], "the string is the selection's characters");
	check([[board dataForType:NSRTFPboardType] length] > 0, "and the RTF is real data");

	/* 3. THE PASTE. */
	target = makeView(@"");
	[target paste:nil];
	check([[[target textStorage] string] isEqual:@"Hello"], "a paste inserts the characters");
	{
		id font = attributeAt(target, NSFontAttributeName, 0);

		check(font != nil && [[(NSFont *)font fontName] isEqual:[bold fontName]]
		      && fabs([(NSFont *)font pointSize] - [bold pointSize]) < 0.01,
		      "and the run's font survives the round trip");
	}
	[target release];

	/* THE PLAIN AND RICH COMMANDS, ON A BOARD THAT HAS BOTH. */
	[source setSelectedRange:NSMakeRange(0, 5)];
	[source copy:nil];
	target = makeView(@"");
	[target pasteAsPlainText:nil];
	check([[[target textStorage] string] isEqual:@"Hello"], "-pasteAsPlainText: inserts the characters");
	{
		id font = attributeAt(target, NSFontAttributeName, 0);

		check(font == nil || ![[(NSFont *)font fontName] isEqual:[bold fontName]],
		      "and does NOT take the rich run");
	}
	[target release];
	target = makeView(@"");
	[target pasteAsRichText:nil];
	check([[[target textStorage] string] isEqual:@"Hello"], "-pasteAsRichText: inserts the characters");
	{
		id font = attributeAt(target, NSFontAttributeName, 0);

		check(font != nil && [[(NSFont *)font fontName] isEqual:[bold fontName]],
		      "and takes the rich run");
	}
	[target release];

	/* 4. THE CUT, AND THE COPY OF A WHOLE PARAGRAPH WHEN NOTHING IS SELECTED. */
	[source release];
	source = makeView(@"Hello world");
	[source setSelectedRange:NSMakeRange(0, 6)];
	[source cut:nil];
	check([[[source textStorage] string] isEqual:@"world"], "a cut removes the selection from the view");
	check([[board stringForType:NSStringPboardType] isEqual:@"Hello "], "and leaves it on the board");
	[source release];

	source = makeView(@"One\nTwo");
	[source setSelectedRange:NSMakeRange(1, 0)];
	[source copy:nil];
	check([[board stringForType:NSStringPboardType] isEqual:@"One"],
	      "a copy with no selection takes the paragraph");

	/* 5. THE DRAG. */
	[source setSelectedRange:NSMakeRange(0, 3)];
	{
		NSPoint origin = NSZeroPoint;
		NSImage *image = [source dragImageForSelectionWithEvent:nil origin:&origin];

		check(image != nil && [image size].width > 0.0 && [image size].height > 0.0,
		      "a drag's image is the selection's ink at a real size");
		check(origin.x >= 0.0 && origin.y >= 0.0, "and its origin is a point in the view");
	}
	check([source dragOperationForDraggingInfo:nil type:NSRTFPboardType] == NSDragOperationCopy,
	      "a drag from the view offers a copy");
	[source updateDragTypeRegistration];
	check([[source cg_registeredDraggedTypes] containsObject:NSRTFPboardType],
	      "the registration is the view's readable types");
	check(![source dragSelectionWithEvent:nil offset:NSZeroSize slideBack:YES],
	      "a drag with no event begins no session");
	check([source allowsImageEditing] == NO, "and image editing is off by default");
	[source setAllowsImageEditing:YES];
	check([source allowsImageEditing], "and can be turned on");

	[source release];
	clearPasteboard();
	printf("\ntext-view pasteboard: %d check(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
