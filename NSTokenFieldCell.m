/*
 * NSTokenFieldCell.m — the list, the three strings, the chips, and the four ways a list changes.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CELL'S WHOLE JOB IS ONE LIST AND FOUR SPELLINGS OF IT.** The list is the base class's `-_objectValue`, an array
 * of represented objects. Its spellings are `-objectValue` (the list), `-stringValue` (the display strings joined),
 * `-cg_editingText` (the editing strings joined) and the DRAWING (the same list as chips). Every mutation — a string
 * tokenized, an edit committed, a pasteboard read, a cut — goes through `-cg_storeTokens:`, so there is one place the
 * list changes and one place an open editor is told about it.
 *
 * **AND THE DELEGATE IS ASKED AT EACH CONVERSION, WITH THE IDENTITY AS THE FALLBACK.** Apple's contract is that a
 * delegate may answer nil for display/editing/represented and then "display string = editing string = the object"; this
 * class implements that literally, so a token field over `NSString`s needs no delegate and one over record objects needs
 * three methods. The same fallback rule makes the field-as-relay work: the field always ANSWERS, and its answers are the
 * caller's when the caller has one and these defaults when it does not.
 */
#import <AppKit/NSTokenFieldCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSMenu.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

/* **THE BASE'S THREE PRIVATE DOORS THIS CLASS NEEDS, DECLARED WHERE THEY ARE USED.** `-cg_inkColor` is the field's ink
 * rule, `-cg_drawPlaceholderInFrame:` is its placeholder drawing, and `-fn_finishEditing:keep:movement:` is the ONE
 * session teardown both endings go through. None is public API; the subclass declares them in a category the way the
 * handoff's rule for a deep class says, rather than editing the base's header to publish an internal seam. */
@interface NSTextFieldCell (AGTokenCellPrivate)
- (NSColor *)cg_inkColor;
- (void)cg_drawPlaceholderInFrame:(NSRect)cellFrame;
- (void)fn_finishEditing:(NSText *)textObj keep:(BOOL)keep movement:(NSTextMovement)movement;
- (void)textDidChange:(NSNotification *)notification;
@end

/* **THE CHIP'S GEOMETRY, IN ONE PLACE.** The horizontal pad is the air between a chip's edge and its words; the vertical
 * pad is the band above and below the line; the gap is what separates two chips; and the separator is what separates two
 * PLAIN tokens, because a plain token has no edge to put a gap against. These are the cell's own numbers and they are
 * the only ones the drawing, the measurement and the hit test share. */
static const CGFloat AGTokenHorizontalPad = 4.0;
static const CGFloat AGTokenVerticalPad = 2.0;
static const CGFloat AGTokenGap = 3.0;
static NSString * const AGTokenTextSeparator = @", ";

static NSString * const AGCoderTokenStyleKey = @"tokenStyle";
static NSString * const AGCoderTokenCompletionDelayKey = @"completionDelay";
static NSString * const AGCoderTokenizingSetKey = @"tokenizingCharacterSet";

@implementation NSTokenFieldCell

/* ============================================================================================
 * ARCHIVING: THE THREE SETTINGS, AND NOT THE DELEGATE.
 * ============================================================================================ */
/* **A DELEGATE IS A CONNECTION AND A SESSION IS RUNTIME STATE, SO NEITHER IS ARCHIVED.** What travels is the token
 * style, the completion delay and the separator — the three settings a cell OWNS — plus the base's value, which NSCell
 * already archives and which is where the list itself lives. A decoded cell therefore starts with its list and no
 * delegate, which is the same state a built one has until a caller sets one. */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeInteger:(NSInteger)_tokenStyle forKey:AGCoderTokenStyleKey];
	[aCoder encodeDouble:_completionDelay forKey:AGCoderTokenCompletionDelayKey];
	[aCoder encodeObject:_tokenizingCharacterSet forKey:AGCoderTokenizingSetKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	_tokenizingCharacterSet = [[[self class] defaultTokenizingCharacterSet] copy];
	_completionDelay = [[self class] defaultCompletionDelay];
	_tokenStyle = NSDefaultTokenStyle;
	if ([aDecoder containsValueForKey:AGCoderTokenStyleKey]) {
		_tokenStyle = (NSTokenStyle)[aDecoder decodeIntegerForKey:AGCoderTokenStyleKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTokenCompletionDelayKey]) {
		_completionDelay = [aDecoder decodeDoubleForKey:AGCoderTokenCompletionDelayKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTokenizingSetKey]) {
		NSCharacterSet *set = [aDecoder decodeObjectForKey:AGCoderTokenizingSetKey];

		if (set != nil) {
			[_tokenizingCharacterSet release];
			_tokenizingCharacterSet = [set copy];
		}
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

/* ============================================================================================
 * THE DEFAULTS, AND WHY A COMMA AND A NEWLINE ARE THE SEPARATOR.
 * ============================================================================================ */
/* **THE ERA'S DEFAULT DELAY IS 0.0, WHICH MEANS IMMEDIATE, AND THE SWITCH IS THE SIGN.** A caller that wants no
 * completion sets a negative delay; there is no separate flag in the 10.6 surface and inventing one would be a second
 * answer to the same question. */
+ (NSTimeInterval)defaultCompletionDelay
{
	return 0.0;
}

/* **THE SEPARATOR IS A COMMA AND A NEWLINE — NOT A SPACE.** A space belongs inside a token: the era's own token field is
 * an address field, and "John Smith" is one person. Splitting on whitespace would make the class's first use impossible,
 * so the set is named here and the reason is recorded at the declaration as well as at the reader. */
+ (NSCharacterSet *)defaultTokenizingCharacterSet
{
	return [NSCharacterSet characterSetWithCharactersInString:@",\n"];
}

/* **THE INITIALISER SETS THE DEFAULTS BEFORE THE BASE TOKENIZES ITS STRING.** `NSCell -initTextCell:` calls `-init` and
 * then `-setStringValue:`, and this class's `-setStringValue:` parses — so the separator and the delay have to exist
 * first, which is what this door is for. The base's own defaults (the face, the colour, the bezel) come from
 * `NSTextFieldCell -initTextCell:` after this returns. */
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_tokenizingCharacterSet = [[[self class] defaultTokenizingCharacterSet] copy];
		_completionDelay = [[self class] defaultCompletionDelay];
		_tokenStyle = NSDefaultTokenStyle;
	}
	return self;
}

- (void)dealloc
{
	[_tokenizingCharacterSet release];
	[super dealloc];
}

/* ---- THE STYLE, THE SEPARATOR AND THE DELAY --------------------------------------------------------- */

- (void)setTokenStyle:(NSTokenStyle)style
{
	_tokenStyle = style;
}

- (NSTokenStyle)tokenStyle
{
	return _tokenStyle;
}

/* **THE SEPARATOR IS COPIED SO A CALLER'S MUTABLE SET CANNOT CHANGE THIS CELL'S PARSING LATER.** The same rule the
 * field cell records for its placeholder strings. nil means "the class default", which is also what a decoded cell
 * without a stored set answers.
 *
 * **AND `-copy` IS NOT THE DOOR THAT MAKES A COPY IN THIS FOUNDATION, WHICH IS A TRAP RATHER THAN A PREFERENCE.**
 * `NSCharacterSet -copy` answers `[self retain]` — a correct optimisation for an immutable set and a WRONG one when the
 * receiver is an `NSMutableCharacterSet`, because the "copy" is still the caller's mutable object. MEASURED here: the
 * probe set a mutable separator, then mutated it, and the cell's parsing changed underneath. `-mutableCopy` DOES build a
 * new object (it allocates and replays the ranges), so it is the only door in this class family that produces one; the
 * stored set is independently owned even though its type is still mutable. */
- (void)setTokenizingCharacterSet:(NSCharacterSet *)characterSet
{
	NSCharacterSet *copy = (characterSet != nil)
		? [characterSet mutableCopy]
		: [[[self class] defaultTokenizingCharacterSet] mutableCopy];

	if (copy != _tokenizingCharacterSet) {
		[_tokenizingCharacterSet release];
		_tokenizingCharacterSet = copy;
	} else {
		[copy release];
	}
}

- (NSCharacterSet *)tokenizingCharacterSet
{
	return _tokenizingCharacterSet;
}

- (void)setCompletionDelay:(NSTimeInterval)delay
{
	_completionDelay = delay;
}

- (NSTimeInterval)completionDelay
{
	return _completionDelay;
}

- (void)setDelegate:(id <NSTokenFieldCellDelegate>)anObject
{
	/* NOT RETAINED, and not released on the way out: this tree's rule for every delegate. */
	_delegate = anObject;
}

- (id <NSTokenFieldCellDelegate>)delegate
{
	return _delegate;
}

/* ---- THE LIST, AND ITS FOUR SPELLINGS ---------------------------------------------------------------- */

/* **THE LIST IS THE BASE'S OBJECT VALUE, AND `-cg_tokens` IS THE TYPED READ OF IT.** A nil or non-array value can only
 * arrive from a decoder that carried something a token cell never wrote, so the typed read answers an empty list rather
 * than nil and the rest of the class may count without a test. */
- (NSArray *)cg_tokens
{
	id value = [super objectValue];

	return [value isKindOfClass:[NSArray class]] ? (NSArray *)value : [NSArray array];
}

/* **THE LIST IS ANSWERED AS AN ARRAY EVEN WHEN EMPTY.** Apple's token field has a list, and "no tokens" is an empty list
 * rather than the absence of one; a caller may enumerate the answer without a nil test. */
- (id)objectValue
{
	return [self cg_tokens];
}

/* **THE ONE STORE, AND IT TAKES THE THREE SHAPES A CALLER MAY HAND A CELL.** This override is deliberately the only
 * place `-_objectValue` is written: a string is tokenized (which is how the base's `-setStringValue:` reaches the list),
 * an array IS the list, a single object becomes a one-token list, and nil empties it. `[super setObjectValue:]` is the
 * base's own retain-and-store, so there is still exactly one owner of the value. */
- (void)setObjectValue:(id)value
{
	NSArray *tokens;

	if (value == nil) {
		tokens = [NSArray array];
	} else if ([value isKindOfClass:[NSString class]]) {
		tokens = [self cg_representedObjectsForString:(NSString *)value];
	} else if ([value isKindOfClass:[NSArray class]]) {
		tokens = (NSArray *)value;
	} else {
		tokens = [NSArray arrayWithObject:value];
	}
	[self cg_storeTokens:tokens];
}

/* **AND A STRING WRITTEN HERE IS TOKENIZED AND THEN SHOWN IN THE EDITOR AS EDITING TEXT.** The base's version writes the
 * same string into the editor; a token cell's editor shows the EDITING strings, which is the whole reason the delegate
 * has an editing conversion. `-cg_storeTokens:` tells the editor; this door only keeps the base's copy rule. */
- (void)setStringValue:(NSString *)aString
{
	[self setObjectValue:[[aString copy] autorelease]];
}

/* **`-stringValue` IS THE DISPLAY LIST, WHICH IS WHAT A PERSON READS.** An empty list answers an empty string rather
 * than nil: a field with no tokens has nothing in it, and the placeholder is drawn for exactly that state. */
- (NSString *)stringValue
{
	NSArray *tokens = [self cg_tokens];
	NSMutableArray *display = [NSMutableArray arrayWithCapacity:[tokens count]];
	NSUInteger i;
	NSUInteger count = [tokens count];

	for (i = 0; i < count; i++) {
		[display addObject:[self cg_displayStringForRepresentedObject:[tokens objectAtIndex:i]]];
	}
	return [display componentsJoinedByString:AGTokenTextSeparator];
}

/* **AND THE EDITING TEXT IS THE SAME JOIN OVER THE OTHER CONVERSION.** A session on a token field is a session over the
 * EDITING strings: the delegate that made a record show as a name on a chip may want the session to show a URL, and this
 * is the string that makes that possible. The display text is what the field shows when no session is running. */
- (NSString *)cg_editingText
{
	NSArray *tokens = [self cg_tokens];
	NSMutableArray *editing = [NSMutableArray arrayWithCapacity:[tokens count]];
	NSUInteger i;
	NSUInteger count = [tokens count];

	for (i = 0; i < count; i++) {
		[editing addObject:[self cg_editingStringForRepresentedObject:[tokens objectAtIndex:i]]];
	}
	return [editing componentsJoinedByString:AGTokenTextSeparator];
}

/* ---- THE FOUR CONVERSIONS, EACH WITH ITS DOCUMENTED FALLBACK ---------------------------------------- */

/* THE SEPARATOR, WITH THE CLASS DEFAULT STANDING IN FOR nil. */
- (NSCharacterSet *)cg_tokenizingSet
{
	return (_tokenizingCharacterSet != nil) ? _tokenizingCharacterSet
						: [[self class] defaultTokenizingCharacterSet];
}

/* **A STRING SPLIT ON THE SEPARATOR, WITH EACH PIECE TRIMMED AND EACH EMPTY PIECE DROPPED.** An empty string is an empty
 * list (not a list holding an empty token), and "a, , b" is two tokens — a person's stray comma does not create a
 * blank chip. Each surviving piece goes through the represented-object conversion, which is where the delegate turns text
 * into the model. */
- (NSArray *)cg_representedObjectsForString:(NSString *)string
{
	NSMutableArray *objects = [NSMutableArray array];
	NSString *trimmed;
	NSArray *pieces;
	NSUInteger i;
	NSUInteger count;

	if (string == nil || [string length] == 0) {
		return objects;
	}
	trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed length] == 0) {
		return objects;
	}
	pieces = [trimmed componentsSeparatedByCharactersInSet:[self cg_tokenizingSet]];
	count = [pieces count];
	for (i = 0; i < count; i++) {
		NSString *piece = [[pieces objectAtIndex:i]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

		if ([piece length] == 0) {
			continue;
		}
		[objects addObject:[self cg_representedObjectForEditingString:piece]];
	}
	return objects;
}

/* **THE DELEGATE FIRST AND THE OBJECT'S OWN TEXT SECOND** — Apple's fallback rule, written once here and reused by the
 * display conversion so the two cannot disagree about what "no opinion" means. */
- (NSString *)cg_editingStringForRepresentedObject:(id)object
{
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenFieldCell:editingStringForRepresentedObject:)]) {
		NSString *answer = [_delegate tokenFieldCell:self editingStringForRepresentedObject:object];

		if (answer != nil) {
			return answer;
		}
	}
	if ([object isKindOfClass:[NSString class]]) {
		return (NSString *)object;
	}
	{
		NSString *description = [object description];

		return (description != nil) ? description : @"";
	}
}

- (NSString *)cg_displayStringForRepresentedObject:(id)object
{
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenFieldCell:displayStringForRepresentedObject:)]) {
		NSString *answer = [_delegate tokenFieldCell:self displayStringForRepresentedObject:object];

		if (answer != nil) {
			return answer;
		}
	}
	/* **AND THE DISPLAY FALLS BACK TO THE EDITING STRING, NOT TO A THIRD RULE.** With only one of the two delegate
	 * methods implemented, the other conversion is still the object's text; "display = editing = object" is Apple's
	 * sentence and this is that sentence as code. */
	return [self cg_editingStringForRepresentedObject:object];
}

- (id)cg_representedObjectForEditingString:(NSString *)string
{
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenFieldCell:representedObjectForEditingString:)]) {
		id answer = [_delegate tokenFieldCell:self representedObjectForEditingString:string];

		if (answer != nil) {
			return answer;
		}
	}
	return string;
}

- (NSTokenStyle)cg_styleForRepresentedObject:(id)object
{
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenFieldCell:styleForRepresentedObject:)]) {
		return [_delegate tokenFieldCell:self styleForRepresentedObject:object];
	}
	/* **AND WITH NO DELEGATE THE STYLE IS THE CELL'S DEFAULT, AND DEFAULT MEANS ROUNDED.** `NSDefaultTokenStyle` is the
	 * era's "a rounded chip, but this may change"; this tier draws it as `NSRoundedTokenStyle` because a chip is the only
	 * thing it draws, and the two cases are kept distinct so the drawing's choice is visible rather than folded into the
	 * enum. */
	return _tokenStyle;
}

/* ---- THE ONE STORE, AND THE EDITOR IT TELLS ---------------------------------------------------------- */

/* **THE LIST IS COPIED, SO A CALLER'S MUTABLE ARRAY CANNOT CHANGE THE CELL UNDER IT.** The same value semantics NSCell
 * gives `-_objectValue`; the copy is immutable and the base retains it, so there is one owner and no aliasing. */
- (void)cg_storeTokens:(NSArray *)tokens
{
	[super setObjectValue:[[tokens copy] autorelease]];
	[self cg_tellEditor];
}

/* **AN OPEN EDITOR IS SHOWN THE EDITING TEXT WHENEVER THE LIST CHANGES.** The base class's own rule is that a value
 * changed mid-session has to reach BOTH the cell and the editor; the token version of "the value" is the list and the
 * editor's spelling of it is the editing text. The quiet flag is not cosmetic: setting an editor's string announces a
 * change, and this cell's change path asks the delegate for completions — a value written by the cell itself must not
 * complete itself. */
- (void)cg_tellEditor
{
	if (_cg_editor != nil && _cg_textEditing && !_cg_quiet) {
		BOOL wasQuiet = _cg_quiet;

		_cg_quiet = YES;
		[_cg_editor setString:[self cg_editingText]];
		[_cg_editor setSelectedRange:NSMakeRange(0, [[_cg_editor string] length])];
		_cg_quiet = wasQuiet;
	}
}

/* **AND AN ADDITION IS REVIEWED BEFORE IT LANDS** — Apple's `-shouldAddObjects:atIndex:`, with the two answers the header
 * names: an empty array rejects, and nil is the era's error case, which this tier treats as a rejection rather than
 * guessing at the caller's intent. Programmatic `-setObjectValue:` does NOT come through here: a model set by a caller
 * is not a person adding a token. */
- (NSArray *)cg_permittedObjects:(NSArray *)objects atIndex:(NSUInteger)index
{
	if (objects == nil) {
		return [NSArray array];
	}
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenFieldCell:shouldAddObjects:atIndex:)]) {
		NSArray *answer = [_delegate tokenFieldCell:self shouldAddObjects:objects atIndex:index];

		if (answer == nil) {
			return [NSArray array];
		}
		return answer;
	}
	return objects;
}

/* ============================================================================================
 * THE DRAWING, THE MEASUREMENT AND THE HIT TEST: ONE LAYOUT.
 * ============================================================================================ */
/* **A TOKEN'S RECTANGLE IS THE LAYOUT'S ANSWER AND EVERYTHING ELSE ASKS IT.** The drawing paints the rects, the hit test
 * contains a point in them, and the measurement takes the last one's right edge — so a chip cannot be painted one place
 * and clicked in another, which is the bug a second arithmetic copy always grows. A PLAIN token's rect is its text's
 * rect; a chip's rect is the text plus the horizontal and vertical pads. */
- (NSArray *)cg_tokenFramesInFrame:(NSRect)cellFrame
{
	NSMutableArray *frames = [NSMutableArray array];
	NSArray *tokens = [self cg_tokens];
	NSRect room = [self drawingRectForBounds:cellFrame];
	CGFloat lineHeight = [self cg_lineHeight];
	CGFloat chipHeight = lineHeight + 2.0 * AGTokenVerticalPad;
	CGFloat x = NSMinX(room);
	NSUInteger i;
	NSUInteger count = [tokens count];

	for (i = 0; i < count; i++) {
		id object = [tokens objectAtIndex:i];
		NSString *display = [self cg_displayStringForRepresentedObject:object];
		NSTokenStyle style = [self cg_styleForRepresentedObject:object];
		CGFloat textWidth = [self cg_widthOfString:display];
		NSRect frame;

		if (i > 0) {
			/* **THE SEPARATOR IS PART OF THE PLAIN STYLE'S OWN LAYOUT.** Two plain tokens read as a comma-separated run
			 * ("red, green"), not as two chips with air between them; two chips are separated by air because their
			 * edges already say where one ends. A mixed list takes the style of the token being placed, which is what
			 * makes a plain token after a chip read as a word after a badge. */
			if (style == NSPlainTextTokenStyle) {
				x += [self cg_widthOfString:AGTokenTextSeparator];
			} else {
				x += AGTokenGap;
			}
		}
		if (style == NSPlainTextTokenStyle) {
			frame = NSMakeRect(x, NSMidY(room) - lineHeight / 2.0, textWidth, lineHeight);
		} else {
			frame = NSMakeRect(x, NSMidY(room) - chipHeight / 2.0,
					   textWidth + 2.0 * AGTokenHorizontalPad, chipHeight);
		}
		[frames addObject:[NSValue valueWithRect:frame]];
		x = NSMaxX(frame);
	}
	return frames;
}

- (NSFont *)cg_font
{
	NSFont *font = (NSFont *)[self font];

	return (font != nil) ? font : [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

- (CGFloat)cg_lineHeight
{
	NSDictionary *attributes = [NSDictionary dictionaryWithObject:[self cg_font] forKey:NSFontAttributeName];
	NSSize line = [@" " sizeWithAttributes:attributes];

	return line.height;
}

- (CGFloat)cg_widthOfString:(NSString *)string
{
	NSDictionary *attributes = [NSDictionary dictionaryWithObject:[self cg_font] forKey:NSFontAttributeName];

	return [string sizeWithAttributes:attributes].width;
}

/* **THE DRAWING IS THE BASE'S FACE PLUS THE LIST, AND AN EMPTY FIELD IS THE BASE'S OWN PLACEHOLDER.** A token field with
 * no tokens is a field with nothing in it, so the superclass's interior — which is what draws the placeholder — is the
 * right answer for that state, and for a running session (the editor owns the words; the base returns without drawing).
 * Every other state is this class's: chips and plain runs, clipped to the cell the same way the base clips its string. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSArray *tokens = [self cg_tokens];
	NSArray *frames;
	NSUInteger i;
	NSUInteger count;

	if ([tokens count] == 0 || _cg_textEditing) {
		[super drawInteriorWithFrame:cellFrame inView:controlView];
		return;
	}
	frames = [self cg_tokenFramesInFrame:cellFrame];
	count = MIN([tokens count], [frames count]);
	[NSGraphicsContext saveGraphicsState];
	/* THE BASE'S CLIP RULE: the cell is a bound inside whatever the control established, not a replacement. */
	[[NSBezierPath bezierPathWithRect:cellFrame] addClip];
	for (i = 0; i < count; i++) {
		id object = [tokens objectAtIndex:i];
		NSRect frame = [[frames objectAtIndex:i] rectValue];
		NSString *display = [self cg_displayStringForRepresentedObject:object];
		NSTokenStyle style = [self cg_styleForRepresentedObject:object];
		NSFont *font = [self cg_font];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			font, NSFontAttributeName, [self cg_inkColor], NSForegroundColorAttributeName, nil];
		/* **THE BASELINE COMES FROM THE BASE'S ONE DOOR, IN EITHER Y DIRECTION.** A chip's mid and the line's mid are
		 * the same point, so the chip rect is what is handed over and a flipped context moves this text exactly as it
		 * moves the field's own. */
		CGFloat baseline = [self cg_centredBaselineInFrame:(style == NSPlainTextTokenStyle ? cellFrame : frame)
							     font:font];

		if (style == NSPlainTextTokenStyle && i > 0) {
			[AGTokenTextSeparator drawAtPoint:NSMakePoint(NSMinX(frame) -
				[self cg_widthOfString:AGTokenTextSeparator], baseline)
					   withAttributes:attributes];
		}
		if (style != NSPlainTextTokenStyle) {
			NSRect chipRect = frame;
			NSBezierPath *chip = [NSBezierPath bezierPathWithRoundedRect:chipRect
									     xRadius:NSHeight(chipRect) / 2.0
									     yRadius:NSHeight(chipRect) / 2.0];

			/* **THE CHIP IS A CONTROL-GREY FILL WITH THE ERA'S BORDER GREY.** A badge sits ON a field rather than being
			 * one, so it takes the two colours a raised control uses — the same pair the button cells record — and its
			 * words take the field's own ink. */
			[[NSColor controlColor] setFill];
			[chip fill];
			[[NSColor controlShadowColor] setStroke];
			[chip setLineWidth:1.0];
			[chip stroke];
			frame = NSInsetRect(frame, AGTokenHorizontalPad, 0.0);
		}
		[display drawAtPoint:NSMakePoint(NSMinX(frame), baseline) withAttributes:attributes];
	}
	[NSGraphicsContext restoreGraphicsState];
}

/* **AND THE MEASUREMENT IS THE SAME LAYOUT, FROM THE SAME RECT.** An empty list keeps the base's answer, because a field
 * of no tokens is sized like any empty field (one line high); a list measures from the drawing rect's left edge to the
 * last token's right edge, plus the two insets the drawing itself honours. */
- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSArray *tokens = [self cg_tokens];
	NSArray *frames;
	NSSize size;
	CGFloat width;

	if ([tokens count] == 0) {
		return [super cellSizeForBounds:aRect];
	}
	frames = [self cg_tokenFramesInFrame:aRect];
	if ([frames count] == 0) {
		return [super cellSizeForBounds:aRect];
	}
	{
		NSRect last = [[frames lastObject] rectValue];

		width = NSMaxX(last) - NSMinX([self drawingRectForBounds:aRect]);
	}
	width += 2.0 * NS_TEXT_INSET;
	size.width = MIN(width, aRect.size.width);
	size.height = MIN([self cg_lineHeight] + 2.0 * AGTokenVerticalPad + 2.0 * NS_TEXT_INSET, aRect.size.height);
	return size;
}

/* ---- THE HIT TEST AND THE MENU ---------------------------------------------------------------------- */

- (NSInteger)cg_tokenIndexAtPoint:(NSPoint)point inFrame:(NSRect)frame
{
	NSArray *frames = [self cg_tokenFramesInFrame:frame];
	NSUInteger i;

	for (i = 0; i < [frames count]; i++) {
		if (NSPointInRect(point, [[frames objectAtIndex:i] rectValue])) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

- (NSMenu *)cg_menuForRepresentedObjectAtIndex:(NSInteger)index
{
	NSArray *tokens = [self cg_tokens];
	id object;

	if (index < 0 || (NSUInteger)index >= [tokens count] || _delegate == nil) {
		return nil;
	}
	object = [tokens objectAtIndex:(NSUInteger)index];
	/* **THE `has` DOOR IS ASKED FIRST, AND ITS NO IS FINAL.** Apple's contract; a delegate that implements only the menu
	 * door is taken as YES, because answering a menu is a stronger statement than not answering the question. */
	if ([_delegate respondsToSelector:@selector(tokenFieldCell:hasMenuForRepresentedObject:)] &&
	    ![_delegate tokenFieldCell:self hasMenuForRepresentedObject:object]) {
		return nil;
	}
	if ([_delegate respondsToSelector:@selector(tokenFieldCell:menuForRepresentedObject:)]) {
		return [_delegate tokenFieldCell:self menuForRepresentedObject:object];
	}
	return nil;
}

/* ============================================================================================
 * THE PASTEBOARD: THE DEFAULT STRING FIRST, THE DELEGATE SECOND.
 * ============================================================================================ */
/* **COPY WRITES THE EDITING STRINGS BEFORE IT ASKS THE DELEGATE, WHICH IS APPLE'S ORDER AND HAS A REASON.** A caller with
 * no delegate still gets a pasteboard it can paste into another field; a delegate that knows a richer type adds it to
 * the same board. A NO answer CLEARS the board, because a delegate that says NO is saying the default write was wrong. */
- (BOOL)cg_writeTokensToPasteboard:(NSPasteboard *)pboard
{
	NSArray *tokens = [self cg_tokens];
	NSMutableArray *strings;
	NSUInteger i;

	if ([tokens count] == 0) {
		return NO;
	}
	strings = [NSMutableArray arrayWithCapacity:[tokens count]];
	for (i = 0; i < [tokens count]; i++) {
		[strings addObject:[self cg_editingStringForRepresentedObject:[tokens objectAtIndex:i]]];
	}
	[pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[pboard setString:[strings componentsJoinedByString:AGTokenTextSeparator] forType:NSStringPboardType];
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenFieldCell:writeRepresentedObjects:toPasteboard:)]) {
		if (![_delegate tokenFieldCell:self writeRepresentedObjects:tokens toPasteboard:pboard]) {
			[pboard declareTypes:[NSArray array] owner:nil];
			return NO;
		}
	}
	return YES;
}

/* **AND PASTE ASKS THE DELEGATE FOR OBJECTS FIRST, THEN FALLS BACK TO THE STRING.** A nil answer is "no opinion" rather
 * than Apple's error (that error belongs to the addition review), so the default string reader runs. Every object then
 * passes the SAME addition review a typed token does, and the answer says whether anything landed. */
- (BOOL)cg_readTokensFromPasteboard:(NSPasteboard *)pboard
{
	NSArray *objects = nil;
	NSArray *permitted;
	NSMutableArray *combined;

	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(tokenFieldCell:readFromPasteboard:)]) {
		objects = [_delegate tokenFieldCell:self readFromPasteboard:pboard];
	}
	if (objects == nil) {
		NSString *string = [pboard stringForType:NSStringPboardType];

		if (string == nil || [string length] == 0) {
			return NO;
		}
		objects = [self cg_representedObjectsForString:string];
	}
	permitted = [self cg_permittedObjects:objects atIndex:[[self cg_tokens] count]];
	if ([permitted count] == 0) {
		return NO;
	}
	combined = [NSMutableArray arrayWithArray:[self cg_tokens]];
	[combined addObjectsFromArray:permitted];
	[self cg_storeTokens:combined];
	return YES;
}

- (void)cg_removeAllRepresentedObjects
{
	[self cg_storeTokens:[NSArray array]];
}

/* ============================================================================================
 * THE SESSION: THE EDITING TEXT, AND THE COMMIT THAT REVIEWS ITS ADDITIONS.
 * ============================================================================================ */
/* **A SESSION OPENS ON THE EDITING STRINGS, NOT ON THE DISPLAY STRINGS.** The base class seeds its editor from
 * `-stringValue:`; a token cell's display text is what a person reads when nothing is being edited, and the editing text
 * is what a person edits. So the base's session runs and the seed is replaced, with the whole run selected — token ranges
 * do not map onto string ranges, so "select this token" is not a selection this tier can honour. */
- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj
	       delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength
{
	[super selectWithFrame:aRect inView:controlView editor:textObj delegate:anObject
			 start:selStart length:selLength];
	{
		NSText *editor = [self cg_currentEditor];

		if (editor != nil) {
			NSString *editing = [self cg_editingText];
			BOOL wasQuiet = _cg_quiet;

			_cg_quiet = YES;
			[editor setString:editing];
			[editor setSelectedRange:NSMakeRange(0, [editing length])];
			_cg_quiet = wasQuiet;
		}
	}
}

/* **AND ENDING A SESSION IS WHERE THE TYPED TEXT BECOMES A REVIEWED LIST.** The base's ending writes the editor's string
 * back through `-setStringValue:`; a token cell has to TOKENIZE it and ask `-shouldAddObjects:atIndex:` first, so this
 * override commits the list itself and then asks the base to tear the session down WITHOUT a second write-back. The
 * movement is handed to the base unchanged — Return and Tab still send the control's action, Escape still does not. */
- (void)fn_finishEditing:(NSText *)textObj keep:(BOOL)keep movement:(NSTextMovement)movement
{
	if (keep) {
		NSArray *typed = [self cg_representedObjectsForString:[textObj string]];
		NSArray *permitted = [self cg_permittedObjects:typed atIndex:0];
		BOOL wasQuiet = _cg_quiet;

		_cg_quiet = YES;
		[self cg_storeTokens:permitted];
		_cg_quiet = wasQuiet;
	}
	[super fn_finishEditing:textObj keep:NO movement:movement];
}

/* ---- THE COMPLETION PASS, AND WHAT A NEGATIVE DELAY TURNS OFF --------------------------------------- */

/* **THE DELAY'S SIGN IS THE SWITCH AND THIS DOOR IS THE ONLY PLACE IT IS READ.** A negative delay answers nil without
 * asking anyone; a non-negative one asks the delegate, and a delegate that does not implement the door answers nil for
 * the same reason. `selectedIndex` is passed through untouched because this tier has no list to select in. */
- (NSArray *)cg_completionsForSubstring:(NSString *)substring indexOfToken:(NSInteger)tokenIndex
		     indexOfSelectedItem:(NSInteger *)selectedIndex
{
	if (_completionDelay < 0.0 || _delegate == nil ||
	    ![_delegate respondsToSelector:
		@selector(tokenFieldCell:completionsForSubstring:indexOfToken:indexOfSelectedItem:)]) {
		return nil;
	}
	return [_delegate tokenFieldCell:self completionsForSubstring:substring indexOfToken:tokenIndex
				 indexOfSelectedItem:selectedIndex];
}

/* **THE OFFERS ARE FLATTENED AND THE FIRST USEFUL ONE WINS.** Apple's answer is an array of strings OR arrays of strings,
 * so this walks both shapes; a completion must be LONGER than what was typed and must begin with it, case-insensitively
 * — the combo box's rule, and the reason a delegate that echoes the prefix back is not mistaken for an offer. */
- (NSString *)cg_completionFromOffers:(NSArray *)offers forSubstring:(NSString *)substring
{
	NSUInteger i;

	if (offers == nil) {
		return nil;
	}
	for (i = 0; i < [offers count]; i++) {
		id offer = [offers objectAtIndex:i];

		if ([offer isKindOfClass:[NSArray class]]) {
			NSString *inner = [self cg_completionFromOffers:(NSArray *)offer forSubstring:substring];

			if (inner != nil) {
				return inner;
			}
		} else if ([offer isKindOfClass:[NSString class]]) {
			NSString *candidate = (NSString *)offer;

			if ([candidate length] > [substring length] &&
			    [candidate compare:substring options:NSCaseInsensitiveSearch
					range:NSMakeRange(0, [substring length])] == NSOrderedSame) {
				return candidate;
			}
		}
	}
	return nil;
}

/* **THE PARTIAL TOKEN IS THE TEXT AFTER THE LAST SEPARATOR, WITH LEADING SPACE TRIMMED.** A space INSIDE it is kept, for
 * the same reason the separator is not a space: "John Sm" is a partial name. A partial that is empty — the text ends
 * with a separator, or with nothing — asks nothing. */
- (NSRange)cg_partialTokenRangeInString:(NSString *)text
{
	NSUInteger end = [text length];
	NSRange separator = [text rangeOfCharacterFromSet:[self cg_tokenizingSet] options:NSBackwardsSearch];
	NSUInteger start = (separator.location == NSNotFound) ? 0 : NSMaxRange(separator);
	NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];

	while (start < end && [space characterIsMember:[text characterAtIndex:start]]) {
		start++;
	}
	if (start >= end) {
		return NSMakeRange(NSNotFound, 0);
	}
	return NSMakeRange(start, end - start);
}

/* **AND THE CHANGE PATH INSERTS A UNIQUE COMPLETION AND SELECTS THE APPENDED LETTERS.** The selection is what makes the
 * offer replaceable: the next key typed overwrites it rather than appending to it — the combo box's measured lesson. The
 * guard is not an optimisation: setting the editor's string announces another change, and one completion is enough. */
- (void)textDidChange:(NSNotification *)notification
{
	NSText *editor = [notification object];
	static BOOL sCompleting = NO;

	if (!_cg_quiet && !sCompleting && _completionDelay >= 0.0 && [editor isKindOfClass:[NSText class]]) {
		NSString *text = [editor string];
		NSRange partial = [self cg_partialTokenRangeInString:text];

		if (partial.location != NSNotFound) {
			NSString *substring = [text substringWithRange:partial];
			NSInteger tokenIndex = (NSInteger)[[self cg_representedObjectsForString:
				[text substringToIndex:partial.location]] count];
			NSInteger selected = -1;
			NSArray *offers = [self cg_completionsForSubstring:substring indexOfToken:tokenIndex
						     indexOfSelectedItem:&selected];
			NSString *completion = [self cg_completionFromOffers:offers forSubstring:substring];

			if (completion != nil) {
				NSString *head = [text substringToIndex:partial.location];
				NSUInteger typed = [substring length];

				sCompleting = YES;
				[editor setString:[NSString stringWithFormat:@"%@%@", head, completion]];
				[editor setSelectedRange:NSMakeRange(partial.location + typed,
								     [completion length] - typed)];
				sCompleting = NO;
			}
		}
	}
	[super textDidChange:notification];
}

@end
