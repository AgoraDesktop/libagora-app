/*
 * NSTextViewAttributes.m — the text view's selection ranges, its attributes and its attribute commands.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A CATEGORY RATHER THAN A SECOND CLASS, AND A SECOND FILE RATHER THAN A LONGER `NSTextView.m`.** The doors here are
 * declared on `NSTextView` in its header, so they ARE the class's — a category is how one file can hold a second slice
 * of one deep class without the first file growing past the point where a reader can find anything. The category has
 * access to the ivars because it is the same class, which is why the private helpers below can be methods rather than
 * functions that cannot reach the storage.
 *
 * **EVERY COMMAND IS THE SAME THREE STEPS**: ask `-shouldChangeTextInRange:replacementString:`, take the range the
 * command acts on, edit the STORE. Nothing here touches the layout manager or the string mirror: the store notifies
 * both, which is the one edit path this view has. A CARET (an empty range) is not a no-op — a run nobody has typed yet
 * cannot be edited — so a command on a caret mutates the TYPING attributes, which is what makes the next keystroke
 * arrive bold rather than the previous one becoming bold.
 */
#import <AppKit/NSTextView.h>

#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSTextStorage.h>

#include <ctype.h>

/* THE PRIVATE DOORS, DECLARED BEFORE THEY ARE USED — the house rule for a helper that is not Apple's surface. */
@interface NSTextView (AGTextAttributesPrivate)
- (NSRange)ag_characterCommandRange;
- (void)ag_applyNumberAttribute:(NSString *)key by:(double)delta;
- (void)ag_setLigatureValue:(NSInteger)value;
- (void)ag_setParagraphStyleInRange:(NSRange)range alignment:(NSInteger)alignment hasAlignment:(BOOL)hasAlignment
			  direction:(NSInteger)direction hasDirection:(BOOL)hasDirection;
- (void)ag_takeColorFromPanel:(id)sender;
- (NSMutableDictionary *)ag_mutableTypingAttributes;
@end

@implementation NSTextView (AGTextAttributes)

/* ============================================================================================ *
 * THE SELECTION'S RANGES, ITS AFFINITY AND ITS GRANULARITY.                                     *
 * ============================================================================================ */

- (NSArray *)selectedRanges
{
	if (_cg_selectedRanges != nil && [_cg_selectedRanges count] > 0) {
		return [NSArray arrayWithArray:_cg_selectedRanges];
	}
	return [NSArray arrayWithObject:[NSValue valueWithRange:_selectedRange]];
}

- (void)setSelectedRanges:(NSArray *)ranges
{
	[self setSelectedRanges:ranges affinity:_cg_selectionAffinity stillSelecting:NO];
}

/* **EVERY RANGE IS CLAMPED TO THE STORAGE BEFORE IT IS KEPT.** A selection that pointed past the end would draw a band
 * over text that is not there and would make the next insertion a range error, so the clamp is here rather than at
 * every door that uses the ranges. The FIRST range is mirrored into `_selectedRange` — the inherited doors read that —
 * and the array exists only when there is more than one, so the single-selection shape stays the cheap one. */
- (void)setSelectedRanges:(NSArray *)ranges affinity:(NSTextSelectionAffinity)affinity
	     stillSelecting:(BOOL)stillSelecting
{
	NSUInteger length = [_cg_textStorage length];
	NSMutableArray *kept = [NSMutableArray array];
	NSUInteger i;

	(void)stillSelecting;	/* RECORDED BY THE CALL, NOT BY THE VIEW: this tier has no `-didChangeSelection` walk */
	if ([ranges count] == 0) {
		ranges = [NSArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(0, 0)]];
	}
	for (i = 0; i < [ranges count]; i++) {
		NSRange range = [[ranges objectAtIndex:i] rangeValue];
		NSRange clamped;

		if (range.location > length) {
			range.location = length;
		}
		if (range.location + range.length > length) {
			range.length = length - range.location;
		}
		clamped = range;
		[kept addObject:[NSValue valueWithRange:clamped]];
	}
	[_cg_selectedRanges release];
	_cg_selectedRanges = ([kept count] > 1) ? [kept copy] : nil;
	_cg_selectionAffinity = affinity;
	[self setSelectedRange:[[kept objectAtIndex:0] rangeValue]];
	if ([kept count] > 1) {
		[self setNeedsDisplay:YES];
	}
}

- (void)setSelectedRange:(NSRange)range affinity:(NSTextSelectionAffinity)affinity
	   stillSelecting:(BOOL)stillSelecting
{
	(void)stillSelecting;
	_cg_selectionAffinity = affinity;
	[_cg_selectedRanges release];
	_cg_selectedRanges = nil;
	[self setSelectedRange:range];
}

- (NSTextSelectionAffinity)selectionAffinity
{
	return _cg_selectionAffinity;
}

- (NSTextSelectionGranularity)selectionGranularity
{
	return _cg_selectionGranularity;
}

- (void)setSelectionGranularity:(NSTextSelectionGranularity)granularity
{
	_cg_selectionGranularity = granularity;
}

/* **THE EXPANSION IS BYTES, BECAUSE THIS TIER'S STRINGS ARE** (`HANDOFF-2.md` §4): a word is an ASCII letter, digit or
 * underscore, which is the same rule `-characterAtIndex:` and the date picker's parser already follow. A paragraph runs
 * from after the previous newline to the newline itself, and a document is the whole store. */
- (NSRange)selectionRangeForProposedRange:(NSRange)proposedRange
			      granularity:(NSTextSelectionGranularity)granularity
{
	NSUInteger length = [_cg_textStorage length];
	NSUInteger start, end;
	NSString *text = [_cg_textStorage string];

	if (proposedRange.location > length) {
		proposedRange.location = length;
	}
	if (proposedRange.location + proposedRange.length > length) {
		proposedRange.length = length - proposedRange.location;
	}
	start = proposedRange.location;
	end = start + proposedRange.length;
	if (granularity == NSTextSelectionGranularityCharacter) {
		return NSMakeRange(start, end - start);
	}
	if (granularity == NSTextSelectionGranularityDocument) {
		return NSMakeRange(0, length);
	}
	if (granularity == NSTextSelectionGranularityWord) {
		/* A CARET IN A WORD GROWS OVER THE WHOLE WORD; one between words answers the empty range it was given. */
		if (start == end && start > 0 && start <= length) {
			unsigned char c = (unsigned char)[text characterAtIndex:start - 1];

			if (isalnum(c) || c == '_') {
				start--;
			}
		}
		while (start > 0) {
			unsigned char c = (unsigned char)[text characterAtIndex:start - 1];

			if (!isalnum(c) && c != '_') {
				break;
			}
			start--;
		}
		while (end < length) {
			unsigned char c = (unsigned char)[text characterAtIndex:end];

			if (!isalnum(c) && c != '_') {
				break;
			}
			end++;
		}
		return NSMakeRange(start, end - start);
	}
	/* PARAGRAPH: back to just after the previous newline, forward past the next one. */
	while (start > 0 && [text characterAtIndex:start - 1] != '\n') {
		start--;
	}
	while (end < length && [text characterAtIndex:end] != '\n') {
		end++;
	}
	return NSMakeRange(start, end - start);
}

/* ============================================================================================ *
 * THE ATTRIBUTES THE VIEW CARRIES.                                                              *
 * ============================================================================================ */

- (NSMutableDictionary *)ag_mutableTypingAttributes
{
	return (_cg_typingAttributes != nil) ? [[_cg_typingAttributes mutableCopy] autorelease]
					     : [NSMutableDictionary dictionary];
}

/* **THE CALLER'S DICTIONARY, ELSE THE INSERTION POINT'S RUN, ELSE THE DEFAULTS.** The third arm is what makes a view
 * with no text at all still able to say what its first keystroke will wear. */
- (NSDictionary *)typingAttributes
{
	NSUInteger length = [_cg_textStorage length];

	if (_cg_typingAttributes != nil) {
		return _cg_typingAttributes;
	}
	if (length > 0) {
		NSUInteger at = MIN(_selectedRange.location, length - 1);

		return [_cg_textStorage attributesAtIndex:at effectiveRange:NULL];
	}
	{
		NSMutableDictionary *attributes = [NSMutableDictionary dictionary];

		[attributes setObject:[self defaultParagraphStyle] forKey:NSParagraphStyleAttributeName];
		if ([self font] != nil) {
			[attributes setObject:(NSFont *)[self font] forKey:NSFontAttributeName];
		}
		return attributes;
	}
}

- (void)setTypingAttributes:(NSDictionary *)attrs
{
	NSDictionary *old = _cg_typingAttributes;

	_cg_typingAttributes = [attrs copy];
	[old release];
}

- (NSParagraphStyle *)defaultParagraphStyle
{
	return (_cg_defaultParagraphStyle != nil) ? _cg_defaultParagraphStyle : [NSParagraphStyle defaultParagraphStyle];
}

- (void)setDefaultParagraphStyle:(NSParagraphStyle *)style
{
	NSParagraphStyle *old = _cg_defaultParagraphStyle;

	_cg_defaultParagraphStyle = [style copy];
	[old release];
}

/* **THE SELECTED RUNS' INK, WITH THE ACCENT AS THE DEFAULT.** The background colour is what `-drawRect:` fills the
 * selection band with; a caller that wants a different one sets it here and the drawing reads it. */
- (NSDictionary *)selectedTextAttributes
{
	if (_cg_selectedTextAttributes != nil) {
		return _cg_selectedTextAttributes;
	}
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSColor cg_accentColor], NSBackgroundColorAttributeName,
		[NSColor whiteColor], NSForegroundColorAttributeName, nil];
}

- (void)setSelectedTextAttributes:(NSDictionary *)attributes
{
	NSDictionary *old = _cg_selectedTextAttributes;

	_cg_selectedTextAttributes = [attributes copy];
	[old release];
	[self setNeedsDisplay:YES];
}

/* AND THE COMPOSITION'S UNDERLINE, which `-cg_setMarkedText:…` applies to the run as it arrives. */
- (NSDictionary *)markedTextAttributes
{
	if (_cg_markedTextAttributes != nil) {
		return _cg_markedTextAttributes;
	}
	return [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
					   forKey:NSUnderlineStyleAttributeName];
}

- (void)setMarkedTextAttributes:(NSDictionary *)attributes
{
	NSDictionary *old = _cg_markedTextAttributes;

	_cg_markedTextAttributes = [attributes copy];
	[old release];
}

/* ============================================================================================ *
 * THE EDITING CONTRACT.                                                                         *
 * ============================================================================================ */

/* **A SUBCLASS REFUSES AN EDIT BY ANSWERING NO HERE**, and every edit and every attribute command in this view asks.
 * The default checks the two things the view can know by itself: that it is editable, and that the range is inside the
 * text it has. */
- (BOOL)shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString
{
	NSUInteger length = [_cg_textStorage length];

	(void)replacementString;
	if (![self isEditable]) {
		return NO;
	}
	if (affectedCharRange.location == NSNotFound) {
		return NO;
	}
	if (affectedCharRange.location > length) {
		return NO;
	}
	if (affectedCharRange.location + affectedCharRange.length > length) {
		return NO;
	}
	return YES;
}

- (BOOL)shouldChangeTextInRanges:(NSArray *)affectedRanges replacementStrings:(NSArray *)replacementStrings
{
	NSUInteger i;

	(void)replacementStrings;
	for (i = 0; i < [affectedRanges count]; i++) {
		if (![self shouldChangeTextInRange:[[affectedRanges objectAtIndex:i] rangeValue] replacementString:nil]) {
			return NO;
		}
	}
	return YES;
}

- (NSRange)rangeForUserTextChange
{
	return _selectedRange;
}

- (NSArray *)rangesForUserTextChange
{
	return [self selectedRanges];
}

/* **A COMMAND ON A CARET ACTS ON THE NEXT CHARACTER, WHICH IS AN EMPTY RANGE AT THE CARET.** Returning the caret is
 * what lets the command decide for itself whether to mutate the typing attributes. */
- (NSRange)rangeForUserCharacterAttributeChange
{
	return (_selectedRange.length > 0) ? _selectedRange : NSMakeRange(_selectedRange.location, 0);
}

- (NSArray *)rangesForUserCharacterAttributeChange
{
	return [NSArray arrayWithObject:[NSValue valueWithRange:[self rangeForUserCharacterAttributeChange]]];
}

/* AND A PARAGRAPH COMMAND ACTS ON EVERY PARAGRAPH THE SELECTION TOUCHES. */
- (NSRange)rangeForUserParagraphAttributeChange
{
	return [self selectionRangeForProposedRange:_selectedRange
					 granularity:NSTextSelectionGranularityParagraph];
}

- (NSArray *)rangesForUserParagraphAttributeChange
{
	return [NSArray arrayWithObject:[NSValue valueWithRange:[self rangeForUserParagraphAttributeChange]]];
}

/* ============================================================================================ *
 * THE RUN COMMANDS: KERNING, BASELINE AND LIGATURES.                                            *
 * ============================================================================================ */

- (NSRange)ag_characterCommandRange
{
	return [self rangeForUserCharacterAttributeChange];
}

/* **THE THREE STEPS, ONCE.** A command with a TEXT selection edits the run; one with a caret edits the TYPING
 * attributes instead, because a run nobody has typed cannot be changed. A value of zero REMOVES the attribute, which is
 * what "standard" means when the font's own default is the answer. */
- (void)ag_applyNumberAttribute:(NSString *)key by:(double)delta
{
	NSRange range = [self ag_characterCommandRange];
	id existing = nil;
	double value;

	if (![self shouldChangeTextInRange:range replacementString:nil]) {
		return;
	}
	if (range.length == 0) {
		NSMutableDictionary *attributes = [self ag_mutableTypingAttributes];

		existing = [attributes objectForKey:key];
		value = (existing != nil ? [existing doubleValue] : 0.0) + delta;
		if (value == 0.0) {
			[attributes removeObjectForKey:key];
		} else {
			[attributes setObject:[NSNumber numberWithDouble:value] forKey:key];
		}
		[self setTypingAttributes:attributes];
		return;
	}
	existing = [[_cg_textStorage attributesAtIndex:range.location effectiveRange:NULL] objectForKey:key];
	value = (existing != nil ? [existing doubleValue] : 0.0) + delta;
	if (value == 0.0) {
		[_cg_textStorage removeAttribute:key range:range];
	} else {
		[_cg_textStorage addAttribute:key value:[NSNumber numberWithDouble:value] range:range];
	}
	[self setNeedsDisplay:YES];
}

- (void)loosenKerning:(id)sender
{
	(void)sender;
	[self ag_applyNumberAttribute:NSKernAttributeName by:1.0];
}

- (void)tightenKerning:(id)sender
{
	(void)sender;
	[self ag_applyNumberAttribute:NSKernAttributeName by:-1.0];
}

- (void)turnOffKerning:(id)sender
{
	(void)sender;
	[self ag_applyNumberAttribute:NSKernAttributeName by:-1.0];
}

- (void)useStandardKerning:(id)sender
{
	NSRange range = [self ag_characterCommandRange];

	(void)sender;
	if (![self shouldChangeTextInRange:range replacementString:nil]) {
		return;
	}
	if (range.length == 0) {
		NSMutableDictionary *attributes = [self ag_mutableTypingAttributes];

		[attributes removeObjectForKey:NSKernAttributeName];
		[self setTypingAttributes:attributes];
		return;
	}
	[_cg_textStorage removeAttribute:NSKernAttributeName range:range];
	[self setNeedsDisplay:YES];
}

/* **THE BASELINE IS THE SAME INCREMENT IN POINTS, AND ITS "STANDARD" IS ZERO RATHER THAN ABSENT** — a baseline offset
 * of zero is the text's own baseline, so the pair adds and subtracts and returns to it. */
- (void)lowerBaseline:(id)sender
{
	(void)sender;
	[self ag_applyNumberAttribute:NSBaselineOffsetAttributeName by:-1.0];
}

- (void)raiseBaseline:(id)sender
{
	(void)sender;
	[self ag_applyNumberAttribute:NSBaselineOffsetAttributeName by:1.0];
}

/* LIGATURES ARE A VALUE RATHER THAN A DELTA: 0 none, 1 standard, 2 all. */
- (void)ag_setLigatureValue:(NSInteger)value
{
	NSRange range = [self ag_characterCommandRange];

	if (![self shouldChangeTextInRange:range replacementString:nil]) {
		return;
	}
	if (range.length == 0) {
		NSMutableDictionary *attributes = [self ag_mutableTypingAttributes];

		[attributes setObject:[NSNumber numberWithInteger:value] forKey:NSLigatureAttributeName];
		[self setTypingAttributes:attributes];
		return;
	}
	[_cg_textStorage addAttribute:NSLigatureAttributeName value:[NSNumber numberWithInteger:value] range:range];
	[self setNeedsDisplay:YES];
}

- (void)turnOffLigatures:(id)sender
{
	(void)sender;
	[self ag_setLigatureValue:0];
}

- (void)useStandardLigatures:(id)sender
{
	(void)sender;
	[self ag_setLigatureValue:1];
}

- (void)useAllLigatures:(id)sender
{
	(void)sender;
	[self ag_setLigatureValue:2];
}

/* ============================================================================================ *
 * THE PARAGRAPH COMMANDS.                                                                       *
 * ============================================================================================ */

/* **A PARAGRAPH STYLE IS REPLACED BY A MUTABLE COPY OF ITSELF, ONE PARAGRAPH AT A TIME.** The range a command acts on
 * can span several paragraphs with different styles, and writing one style over all of them would silently drop every
 * other property (line spacing, indents, tab stops) those paragraphs carried — so each paragraph's own style is read,
 * the one property is changed, and it is written back. */
- (void)ag_setParagraphStyleInRange:(NSRange)range alignment:(NSInteger)alignment hasAlignment:(BOOL)hasAlignment
			  direction:(NSInteger)direction hasDirection:(BOOL)hasDirection
{
	NSUInteger length = [_cg_textStorage length];
	NSUInteger cursor;

	if (range.location > length) {
		range.location = length;
	}
	if (range.location + range.length > length) {
		range.length = length - range.location;
	}
	if (![self shouldChangeTextInRange:range replacementString:nil]) {
		return;
	}
	cursor = range.location;
	do {
		NSRange paragraph = [self selectionRangeForProposedRange:NSMakeRange(cursor, 0)
							     granularity:NSTextSelectionGranularityParagraph];
		id existing;
		NSMutableParagraphStyle *style;

		if (paragraph.length == 0 && paragraph.location >= length) {
			break;
		}
		existing = [[_cg_textStorage attributesAtIndex:MIN(cursor, length > 0 ? length - 1 : 0)
					      effectiveRange:NULL] objectForKey:NSParagraphStyleAttributeName];
		style = (existing != nil) ? [existing mutableCopy]
					  : [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		if (hasAlignment) {
			[style setAlignment:(NSTextAlignment)alignment];
		}
		if (hasDirection) {
			[style setBaseWritingDirection:(NSWritingDirection)direction];
		}
		if (paragraph.length > 0) {
			[_cg_textStorage addAttribute:NSParagraphStyleAttributeName value:style range:paragraph];
		}
		[style release];
		cursor = paragraph.location + paragraph.length + 1;	/* past the newline */
	} while (cursor < range.location + range.length);
	[self setNeedsDisplay:YES];
}

- (void)setAlignment:(NSTextAlignment)alignment range:(NSRange)range
{
	[self ag_setParagraphStyleInRange:range alignment:(NSInteger)alignment hasAlignment:YES
			      direction:0 hasDirection:NO];
}

- (void)setBaseWritingDirection:(NSWritingDirection)direction range:(NSRange)range
{
	[self ag_setParagraphStyleInRange:range alignment:0 hasAlignment:NO
			      direction:(NSInteger)direction hasDirection:YES];
}

/* AND THE TOGGLE READS WHAT THE SELECTION'S FIRST PARAGRAPH HAS, THEN WRITES THE OTHER ONE. */
- (void)toggleBaseWritingDirection:(id)sender
{
	NSRange range = [self rangeForUserParagraphAttributeChange];
	NSUInteger at = MIN(range.location, MAX((NSInteger)[_cg_textStorage length] - 1, 0));
	id style = nil;
	NSWritingDirection current = NSWritingDirectionNatural;

	(void)sender;
	if ([_cg_textStorage length] > 0) {
		style = [[_cg_textStorage attributesAtIndex:at effectiveRange:NULL]
				objectForKey:NSParagraphStyleAttributeName];
	}
	if (style != nil) {
		current = [style baseWritingDirection];
	}
	[self setBaseWritingDirection:(current == NSWritingDirectionRightToLeft)
		? NSWritingDirectionLeftToRight : NSWritingDirectionRightToLeft range:range];
}

/* ============================================================================================ *
 * THE TWO PANELS, AND THE REPORT BACK.                                                          *
 * ============================================================================================ */

- (BOOL)usesFontPanel
{
	return _cg_usesFontPanel;
}

- (void)setUsesFontPanel:(BOOL)flag
{
	_cg_usesFontPanel = flag ? YES : NO;
}

/* **`-updateFontPanel` TELLS THE MANAGER WHAT THE SELECTION IS SET IN**, which is what makes the panel's family and size
 * show the caret's font rather than whatever it was left at. A view that does not use the panel (`-usesFontPanel` NO)
 * says nothing, and that is the flag's reader. */
- (void)updateFontPanel
{
	NSFont *font;
	id candidate;

	if (!_cg_usesFontPanel) {
		return;
	}
	candidate = [[self typingAttributes] objectForKey:NSFontAttributeName];
	font = [candidate isKindOfClass:[NSFont class]] ? (NSFont *)candidate : (NSFont *)[self font];
	if (font == nil) {
		return;
	}
	[[NSFontManager sharedFontManager] setSelectedFont:font isMultiple:(_selectedRange.length > 0)];
}

/* AND `-changeAttributes:` IS THE FONT PANEL'S FRONT DOOR: it reports the selection's font and orders the panel, which
 * is Apple's own two steps in that order. */
- (void)changeAttributes:(id)sender
{
	if (!_cg_usesFontPanel) {
		return;
	}
	[self updateFontPanel];
	[[NSFontManager sharedFontManager] orderFrontFontPanel:sender];
}

/* **`-changeColor:` MAKES THIS VIEW THE COLOUR PANEL'S TARGET**, so the colour a person picks arrives here and is
 * applied to the selection. The action is removed again only when the view goes away; installing it twice is harmless
 * because it is the same pair. */
- (void)ag_takeColorFromPanel:(id)sender
{
	NSRange range = [self ag_characterCommandRange];
	NSColor *color = [sender respondsToSelector:@selector(color)] ? (NSColor *)[sender color] : nil;

	if (color == nil || ![self shouldChangeTextInRange:range replacementString:nil]) {
		return;
	}
	if (range.length == 0) {
		NSMutableDictionary *attributes = [self ag_mutableTypingAttributes];

		[attributes setObject:color forKey:NSForegroundColorAttributeName];
		[self setTypingAttributes:attributes];
		return;
	}
	[_cg_textStorage addAttribute:NSForegroundColorAttributeName value:color range:range];
	[self setNeedsDisplay:YES];
}

- (void)changeColor:(id)sender
{
	NSColorPanel *panel = [NSColorPanel sharedColorPanel];
	id existing = [[self typingAttributes] objectForKey:NSForegroundColorAttributeName];

	(void)sender;
	if ([existing isKindOfClass:[NSColor class]]) {
		[panel setColor:(NSColor *)existing];
	}
	[panel setTarget:self];
	[panel setAction:@selector(ag_takeColorFromPanel:)];
	[panel orderFront:sender];
	_cg_panelTargetInstalled = YES;
}

@end
