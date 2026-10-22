/*
 * NSTextViewPasteboard.m — the text view's clipboard, its type registry and its drags.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE VIEW WRITES THREE SPELLINGS OF ONE SELECTION AND READS THE RICHEST IT CAN.** A copy puts the selection on a
 * pasteboard as RTFD (which can carry an attachment), as RTF and as a plain string; a paste asks the board for the
 * richest type the view can read and falls back to the string. That is Apple's own order, and it is why the two type
 * lists are the view's declaration rather than a constant: a caller may subclass and narrow them.
 *
 * **A PASTE GOES THROUGH `-insertText:` AND THEN WEARS THE ATTRIBUTES.** The characters are inserted by the view's own
 * edit path — string mirror, selection, notifications, layout — and the paste's runs are applied over the range it
 * landed in. A second edit path that wrote the store directly would have to reproduce all four, and the first one to
 * forget would be a view whose text and mirror disagree.
 *
 * **AND A DROP LANDS AT THE INSERTION POINT.** Mapping a dragged point to a character index needs the layout manager's
 * point-to-glyph door, which this tier has not got; the drop inserts where the caret is and the header says so.
 */
#import <AppKit/NSTextView.h>

#import <AppKit/NSAttributedString.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSView.h>
#import <AppKit/NSStringDrawing.h>

/* THE VIEW'S OWN PRIVATE DOORS, WHICH THIS CATEGORY NEEDS AND `NSTextView.m` OWNS. A declaration here is a promise the
 * linker checks, not a second implementation. */
@interface NSTextView (AGTextPasteboardPrivate)
- (void)cg_fitHeight;
- (NSAttributedString *)ag_attributedSelection;
- (BOOL)ag_insertAttributedString:(NSAttributedString *)attributed;
- (NSAttributedString *)ag_strippingAttachmentsFrom:(NSAttributedString *)attributed;
@end

@implementation NSTextView (AGTextPasteboard)

/* ============================================================================================ *
 * THE TYPE REGISTRY.                                                                            *
 * ============================================================================================ */

/* **THE ORDER IS THE PREFERENCE**: RTFD carries a picture, RTF carries the runs, the string carries the characters. The
 * MODERN name (`NSPasteboardTypeString`, a UTI) is accepted after the legacy one because another application on this
 * system may well write it. */
- (NSArray *)readablePasteboardTypes
{
	return [NSArray arrayWithObjects:NSRTFDPboardType, NSRTFPboardType, NSStringPboardType,
		NSPasteboardTypeString, nil];
}

- (NSArray *)writablePasteboardTypes
{
	return [NSArray arrayWithObjects:NSRTFDPboardType, NSRTFPboardType, NSStringPboardType, nil];
}

- (NSArray *)acceptableDragTypes
{
	return [self readablePasteboardTypes];
}

/* **THE FIRST TYPE THE BOARD OFFERS THAT THE VIEW MAY READ.** Both arrays are the caller's; the answer is nil when they
 * do not meet, which is the empty value a paste tests for. */
- (NSString *)preferredPasteboardTypeFromArray:(NSArray *)availableTypes
		      restrictedToTypesFromArray:(NSArray *)allowedTypes
{
	NSUInteger i;

	for (i = 0; i < [availableTypes count]; i++) {
		NSString *type = [availableTypes objectAtIndex:i];

		if ([allowedTypes containsObject:type]) {
			return type;
		}
	}
	return nil;
}

/* ============================================================================================ *
 * WRITING AND READING THE SELECTION.                                                            *
 * ============================================================================================ */

/* **AN EMPTY SELECTION COPIES ITS PARAGRAPH**, which is Apple's rule for a text view and the reason a person can copy a
 * line without selecting it first. */
- (NSAttributedString *)ag_attributedSelection
{
	NSRange range = (_selectedRange.length > 0) ? _selectedRange
						    : [self rangeForUserParagraphAttributeChange];

	if (range.location > [_cg_textStorage length]) {
		return nil;
	}
	if (range.location + range.length > [_cg_textStorage length]) {
		range.length = [_cg_textStorage length] - range.location;
	}
	if (range.length == 0) {
		return nil;
	}
	return [_cg_textStorage attributedSubstringFromRange:range];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard type:(NSString *)type
{
	NSAttributedString *selection;

	if (pboard == nil || type == nil) {
		return NO;
	}
	selection = [self ag_attributedSelection];
	if (selection == nil) {
		return NO;
	}
	if ([type isEqual:NSStringPboardType]) {
		[pboard setString:[selection string] forType:type];
		return YES;
	}
	if ([type isEqual:NSRTFPboardType]) {
		NSData *data = [selection RTFRepresentation];

		if (data == nil) {
			return NO;
		}
		[pboard setData:data forType:type];
		return YES;
	}
	if ([type isEqual:NSRTFDPboardType]) {
		NSRange whole = NSMakeRange(0, [selection length]);
		NSData *data = [selection RTFDFromRange:whole documentAttributes:NULL];

		if (data == nil) {
			return NO;
		}
		[pboard setData:data forType:type];
		return YES;
	}
	return NO;
}

/* **ONE DECLARATION, THEN ONE WRITE PER TYPE.** A type the view cannot produce simply does not appear on the board, so
 * the declaration is narrowed to what was actually written — which is what makes a reader's `-types` honest. */
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
	NSMutableArray *written = [NSMutableArray array];
	NSUInteger i;

	if (pboard == nil || [types count] == 0) {
		return NO;
	}
	for (i = 0; i < [types count]; i++) {
		NSString *type = [types objectAtIndex:i];
		NSAttributedString *selection = [self ag_attributedSelection];

		if (selection == nil) {
			break;
		}
		if ([type isEqual:NSStringPboardType]) {
			[written addObject:type];
		} else if ([type isEqual:NSRTFPboardType] && [selection RTFRepresentation] != nil) {
			[written addObject:type];
		} else if ([type isEqual:NSRTFDPboardType]
			   && [selection RTFDFromRange:NSMakeRange(0, [selection length]) documentAttributes:NULL] != nil) {
			[written addObject:type];
		}
	}
	if ([written count] == 0) {
		return NO;
	}
	[pboard declareTypes:written owner:nil];
	for (i = 0; i < [written count]; i++) {
		(void)[self writeSelectionToPasteboard:pboard type:[written objectAtIndex:i]];
	}
	return YES;
}

/* **AN ATTACHMENT IS DROPPED FROM A PASTE THE VIEW DOES NOT ALLOW PICTURES IN.** The runs keep their own attributes;
 * only the attachment CHARACTERS and their attribute go, which is what "image editing is off" means for a paste. */
- (NSAttributedString *)ag_strippingAttachmentsFrom:(NSAttributedString *)attributed
{
	NSMutableAttributedString *result;
	NSUInteger index = 0;
	NSUInteger length = [attributed length];

	if ([self allowsImageEditing] || attributed == nil) {
		return attributed;
	}
	if ([attributed length] == 0) {
		return attributed;
	}
	result = [[[NSMutableAttributedString alloc] init] autorelease];
	while (index < length) {
		NSRange run;
		NSDictionary *attributes = [attributed attributesAtIndex:index effectiveRange:&run];
		NSString *chunk = [[attributed string] substringWithRange:run];
		NSMutableString *kept = [NSMutableString string];
		NSUInteger i;

		for (i = 0; i < [chunk length]; i++) {
			if ([chunk characterAtIndex:i] != (unichar)NSAttachmentCharacter) {
				[kept appendFormat:@"%C", [chunk characterAtIndex:i]];
			}
		}
		if ([kept length] > 0) {
			NSAttributedString *piece = [[[NSAttributedString alloc] initWithString:kept
										    attributes:attributes] autorelease];

			[result appendAttributedString:piece];
		}
		index = run.location + run.length;
	}
	return result;
}

/* **THE CHARACTERS GO IN THROUGH `-insertText:` AND THE RUNS ARE APPLIED OVER THEM.** One edit path: the view's mirror,
 * its selection, its notifications and the layout all follow from the insert; the attributes are then written over the
 * range the insertion landed in. A paste that is only a string takes the same path with no attributes to apply. */
- (BOOL)ag_insertAttributedString:(NSAttributedString *)attributed
{
	NSRange target;
	NSUInteger start;
	NSString *text;

	if (attributed == nil || [attributed length] == 0) {
		return NO;
	}
	text = [attributed string];
	target = _selectedRange;
	if (![self shouldChangeTextInRange:target replacementString:text]) {
		return NO;
	}
	start = MIN(target.location, [_cg_textStorage length]);
	[self insertText:text];
	{
		NSUInteger index = 0;
		NSUInteger length = [attributed length];
		NSUInteger documentLength = [_cg_textStorage length];

		while (index < length) {
			NSRange run;
			NSDictionary *attributes = [attributed attributesAtIndex:index effectiveRange:&run];
			NSRange inDocument;

			if (start + run.location + run.length > documentLength) {
				break;
			}
			inDocument = NSMakeRange(start + run.location, run.length);
			[_cg_textStorage addAttributes:attributes range:inDocument];
			index = run.location + run.length;
		}
	}
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
	return YES;
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard
{
	NSString *type;

	if (pboard == nil) {
		return NO;
	}
	type = [self preferredPasteboardTypeFromArray:[pboard types]
			      restrictedToTypesFromArray:[self readablePasteboardTypes]];
	if (type == nil) {
		return NO;
	}
	return [self readSelectionFromPasteboard:pboard type:type];
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard type:(NSString *)type
{
	if (pboard == nil || type == nil) {
		return NO;
	}
	if ([type isEqual:NSStringPboardType] || [type isEqual:NSPasteboardTypeString]) {
		NSString *string = [pboard stringForType:type];

		if (string == nil) {
			return NO;
		}
		[self insertText:string];
		return YES;
	}
	if ([type isEqual:NSRTFPboardType] || [type isEqual:NSRTFDPboardType]) {
		NSData *data = [pboard dataForType:type];
		NSAttributedString *attributed;

		if (data == nil) {
			return NO;
		}
		attributed = ([type isEqual:NSRTFDPboardType])
			? [[[NSAttributedString alloc] initWithRTFD:data documentAttributes:NULL] autorelease]
			: [[[NSAttributedString alloc] initWithRTF:data documentAttributes:NULL] autorelease];
		if (attributed == nil) {
			return NO;
		}
		return [self ag_insertAttributedString:[self ag_strippingAttachmentsFrom:attributed]];
	}
	return NO;
}

/* ============================================================================================ *
 * THE FIVE COMMANDS.                                                                            *
 * ============================================================================================ */

- (void)copy:(id)sender
{
	(void)sender;
	(void)[self writeSelectionToPasteboard:[NSPasteboard generalPasteboard]
					types:[self writablePasteboardTypes]];
}

- (void)cut:(id)sender
{
	(void)sender;
	if ([self writeSelectionToPasteboard:[NSPasteboard generalPasteboard]
				       types:[self writablePasteboardTypes]]) {
		[self insertText:@""];
	}
}

- (void)delete:(id)sender
{
	(void)sender;
	if (_selectedRange.length > 0) {
		[self insertText:@""];
	}
}

- (void)paste:(id)sender
{
	(void)sender;
	(void)[self readSelectionFromPasteboard:[NSPasteboard generalPasteboard]];
}

- (void)pasteAsPlainText:(id)sender
{
	NSPasteboard *pboard = [NSPasteboard generalPasteboard];
	NSString *string;

	(void)sender;
	string = [pboard stringForType:NSStringPboardType];
	if (string == nil) {
		string = [pboard stringForType:NSPasteboardTypeString];
	}
	if (string != nil) {
		[self insertText:string];
	}
}

- (void)pasteAsRichText:(id)sender
{
	(void)sender;
	(void)[self readSelectionFromPasteboard:[NSPasteboard generalPasteboard]
					   type:[self preferredPasteboardTypeFromArray:
							[[NSPasteboard generalPasteboard] types]
						 restrictedToTypesFromArray:
							[NSArray arrayWithObjects:NSRTFDPboardType, NSRTFPboardType, nil]]];
}

/* ============================================================================================ *
 * THE DRAG SOURCE AND THE DROP.                                                                 *
 * ============================================================================================ */

- (BOOL)allowsImageEditing
{
	return _cg_allowsImageEditing;
}

- (void)setAllowsImageEditing:(BOOL)flag
{
	_cg_allowsImageEditing = flag ? YES : NO;
}

/* **THE DRAG'S IMAGE IS THE SELECTION'S INK, DRAWN INTO AN IMAGE**, and its origin is the point in the view the image
 * hangs from: the selection's first line, at the left inset. The size is the string measured in the first run's font —
 * which is the same measurement a line uses — so the image is as big as what it shows rather than as big as the view. */
- (NSImage *)dragImageForSelectionWithEvent:(NSEvent *)event origin:(NSPointPointer)origin
{
	NSAttributedString *selection = [self ag_attributedSelection];
	NSImage *image;
	NSSize size;
	NSDictionary *attributes;
	NSFont *font;

	(void)event;
	if (selection == nil) {
		return nil;
	}
	attributes = ([selection length] > 0) ? [selection attributesAtIndex:0 effectiveRange:NULL] : nil;
	font = [attributes objectForKey:NSFontAttributeName];
	if (font == nil) {
		font = (NSFont *)[self font];
	}
	size = [[selection string] sizeWithAttributes:
		[NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, nil]];
	if (size.width < 1.0) {
		size.width = 1.0;
	}
	if (size.height < 1.0) {
		size.height = 1.0;
	}
	image = [[[NSImage alloc] initWithSize:size] autorelease];
	[image lockFocus];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, size.width, size.height)] fill];
	[selection drawAtPoint:NSMakePoint(0.0, 0.0)];
	[image unlockFocus];
	if (origin != NULL) {
		*origin = NSMakePoint(NS_TEXT_INSET, NSHeight([self bounds]) - NS_TEXT_INSET);
	}
	return image;
}

- (void)updateDragTypeRegistration
{
	[self registerForDraggedTypes:[self acceptableDragTypes]];
}

- (void)cleanUpAfterDragOperation
{
	/* NOTHING IS HELD BETWEEN A DRAG AND ITS END: the pasteboard is the drag session's and the image is the session's,
	 * so there is no scratch state here to release. The door exists because Apple publishes it, and a subclass that
	 * keeps state of its own overrides it. */
}

- (NSDragOperation)dragOperationForDraggingInfo:(id <NSDraggingInfo>)dragInfo type:(NSString *)type
{
	(void)dragInfo;
	(void)type;
	/* **A DROP FROM THIS VIEW IS A COPY**, because a text selection dragged from one place to another leaves the
	 * original in place until the person cuts it. */
	return NSDragOperationCopy;
}

/* **THE LEGACY DRAG DOOR IS THE ONE THAT TAKES A PASTEBOARD**, and this method has just filled one — the same choice
 * `NSColorPanel -dragColor:withEvent:fromView:` records. The view is the source, so the session asks it for the
 * operation through `-draggingSourceOperationMaskForLocal:` below. */
- (BOOL)dragSelectionWithEvent:(NSEvent *)event offset:(NSSize)mouseOffset slideBack:(BOOL)slideBack
{
	NSImage *image;
	NSPasteboard *board;
	NSPoint origin = NSZeroPoint;

	if (event == nil) {
		return NO;
	}
	board = [NSPasteboard pasteboardWithName:NSDragPboard];
	if (board == nil) {
		return NO;
	}
	if (![self writeSelectionToPasteboard:board types:[self writablePasteboardTypes]]) {
		return NO;
	}
	image = [self dragImageForSelectionWithEvent:event origin:&origin];
	if (image == nil) {
		return NO;
	}
	origin.x += mouseOffset.width;
	origin.y += mouseOffset.height;
	[self dragImage:image at:origin offset:NSZeroSize event:event pasteboard:board source:self
	     slideBack:slideBack];
	return [NSDraggingSession cg_activeSession] != nil;
}

/* AND THE SOURCE'S ONE REQUIRED ANSWER, which the session asks on the way in. */
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	(void)isLocal;
	return NSDragOperationCopy;
}

/* ============================================================================================ *
 * THE DESTINATION.                                                                              *
 * ============================================================================================ */

/* **A DRAG THE VIEW CAN READ IS WELCOMED WITH A COPY**, and one it cannot is refused — the same predicate the paste
 * uses, so a type the view can paste is a type it can accept. */
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	NSPasteboard *board = [sender draggingPasteboard];
	NSString *type = [self preferredPasteboardTypeFromArray:[board types]
			      restrictedToTypesFromArray:[self readablePasteboardTypes]];

	return (type != nil) ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
	return [self draggingEntered:sender];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
	return [self draggingEntered:sender] != NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	/* **THE DROP LANDS AT THE INSERTION POINT**, because this tier cannot map a dragged point to a character index;
	 * see the header. The text is read through the same door a paste uses, so a drop and a paste cannot disagree about
	 * what a type means. */
	return [self readSelectionFromPasteboard:[sender draggingPasteboard]];
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
	(void)sender;
	[self setNeedsDisplay:YES];
}

@end
