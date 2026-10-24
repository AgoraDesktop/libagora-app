/*
 * NSParagraphStyle.m — the paragraph settings a run carries, as a value.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CLASS IS A LEDGER AND A COPY, WHICH IS THE WHOLE OF IT.** Every door above answers a scalar that was set when
 * the style was made; the only arithmetic is the copy that turns an immutable style into a mutable one and back. THAT
 * IS WHY THE MUTABLE CLASS IS A SUBCLASS and not a flag: a caller holding an `NSParagraphStyle *` has a value it can
 * hand to a store and trust, and a caller that wants to change one asks for `-mutableCopy` in as many words.
 *
 * COCOA'S COPY DOORS, with the zone supplied by the caller.
 */
#import <AppKit/NSParagraphStyle.h>
#import "NSTextList_internal.h"

/* **THE STACK IS A CHAIN, AND THIS IS WHERE IT IS MADE.** `-textLists` is "nested from outermost to innermost", so each
 * list has to know the one immediately outside it — which is the only fact `NSTextListPrependEnclosingMarker` needs and
 * the only fact no public API carries (10.6 declares Apple's private `_listSecondary` slot, which this tier's
 * `NSTextList` uses for it). The link is made HERE rather than by the caller because it is a fact about THIS STYLE's
 * stack: the same list object handed to two styles at different depths would otherwise hold one of them.
 *
 * AND IT IS WHY THE STYLE COPIES THE LISTS RATHER THAN SHARING THEM. A shared list whose enclosing pointer this style
 * set would be a caller's object changed behind their back, so `-setTextLists:` takes copies — the same value semantics
 * `-textBlocks` has with `copyItems:YES` at copy time. */
static void fn_link_list_stack(NSArray *lists)
{
	NSUInteger k;

	for (k = 1; k < [lists count]; k++) {
		[(NSTextList *)[lists objectAtIndex:k] _setEnclosingList:[lists objectAtIndex:k - 1]];
	}
}
#import <Foundation/NSObject.h>
#import <Foundation/NSLocale.h>

/* THE ONE SHARED DEFAULT, made on first ask and held for the life of the process — the same shape this tree's other
 * shared values use. It is IMMUTABLE, so the sharing is safe. */
static NSParagraphStyle *fn_defaultParagraphStyle = nil;

/* THE ONE INITIALISER EVERY COPY GOES THROUGH, private because it is a copying detail and not a way to make a style:
 * a caller makes a style by asking for the default and copying it MUTABLE. It is the same class's ivars it reads, so
 * the ledger copy is one assignment per field rather than fifteen setter calls. */
@interface NSParagraphStyle (FNPrivateCopy)
- (instancetype)initWithParagraphStyle:(NSParagraphStyle *)style;
@end

@implementation NSParagraphStyle

+ (NSParagraphStyle *)defaultParagraphStyle
{
	if (fn_defaultParagraphStyle == nil) {
		fn_defaultParagraphStyle = [[NSParagraphStyle alloc] init];
	}
	return fn_defaultParagraphStyle;
}

/* **AND THE LANGUAGE'S OWN DIRECTION, WHICH IS WHAT A NATURAL DIRECTION MEANS.** `NSLocale` answers the character
 * direction for a language code (ICU's data), and only one of its four cases is a direction this tier's layout can
 * express as a paragraph: RIGHT-TO-LEFT is right-to-left, and everything else — left-to-right, and the two vertical
 * script directions — is answered left-to-right, which is the tier's own default and the honest answer for a value it
 * cannot lay out. A nil language asks the CURRENT LOCALE's language, which is the only language this process knows. */
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(NSString *)languageName
{
	NSLocaleLanguageDirection direction;
	NSString *code = languageName;

	if (code == nil) {
		code = [[NSLocale currentLocale] languageCode];
	}
	direction = [NSLocale characterDirectionForLanguage:code];
	return (direction == NSLocaleLanguageDirectionRightToLeft) ? NSWritingDirectionRightToLeft
								   : NSWritingDirectionLeftToRight;
}

/* THE DEFAULTS ARE THE ERA'S, and the two that are not zero are worth stating: the alignment is NATURAL (which this
 * left-to-right tier draws as left) and the writing direction is NATURAL (the Unicode algorithm's), so a fresh style
 * says "let the text decide" rather than picking a side a caller did not ask for. EVERY GEOMETRIC VALUE IS ZERO, and
 * zero means NATURAL for all of them — no extra gap and no clamped line height. */
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_alignment = NSNaturalTextAlignment;
		_lineBreakMode = NSLineBreakByWordWrapping;
		_baseWritingDirection = NSWritingDirectionNatural;
	}
	return self;
}

- (instancetype)initWithParagraphStyle:(NSParagraphStyle *)style
{
	self = [super init];
	if (self != nil) {
		_alignment = style->_alignment;
		_lineBreakMode = style->_lineBreakMode;
		_baseWritingDirection = style->_baseWritingDirection;
		_lineHeightMultiple = style->_lineHeightMultiple;
		_maximumLineHeight = style->_maximumLineHeight;
		_minimumLineHeight = style->_minimumLineHeight;
		_firstLineHeadIndent = style->_firstLineHeadIndent;
		_headIndent = style->_headIndent;
		_tailIndent = style->_tailIndent;
		_lineSpacing = style->_lineSpacing;
		_paragraphSpacing = style->_paragraphSpacing;
		_paragraphSpacingBefore = style->_paragraphSpacingBefore;
		_hyphenationFactor = style->_hyphenationFactor;
		_tighteningFactorForTruncation = style->_tighteningFactorForTruncation;
		_defaultTabInterval = style->_defaultTabInterval;
		_headerLevel = style->_headerLevel;
		/* **AND THE BLOCKS ARE COPIED, not shared**, because a paragraph style is a value: a caller that changed an
		 * array it had handed to a store would be changing the document behind the store's back. The array is immutable
		 * and every block in it is copied. */
		_textBlocks = [[NSArray alloc] initWithArray:style->_textBlocks copyItems:YES];
		_textLists = [[NSArray alloc] initWithArray:style->_textLists copyItems:YES];
		fn_link_list_stack(_textLists);
		_tabStops = [[NSArray alloc] initWithArray:style->_tabStops copyItems:YES];
	}
	return self;
}

- (void)dealloc
{
	[_textBlocks release];
	[_textLists release];
	[_tabStops release];
	[super dealloc];
}

/* AN IMMUTABLE STYLE HAS NOTHING TO COPY: the object cannot have changed since it was made, so the copy IS the
 * original and the retain is the whole implementation — the same answer `NSColor -copy` gives. */
- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return [self retain];
}

/* AND THE MUTABLE COPY IS A SECOND LEDGER FILLED FROM THIS ONE. */
- (id)mutableCopyWithZone:(NSZone *)zone
{
	(void)zone;
	return [[NSMutableParagraphStyle allocWithZone:zone] initWithParagraphStyle:self];
}

- (NSTextAlignment)alignment
{
	return _alignment;
}

- (NSLineBreakMode)lineBreakMode
{
	return _lineBreakMode;
}

- (NSWritingDirection)baseWritingDirection
{
	return _baseWritingDirection;
}

- (CGFloat)lineHeightMultiple
{
	return _lineHeightMultiple;
}

- (CGFloat)maximumLineHeight
{
	return _maximumLineHeight;
}

- (CGFloat)minimumLineHeight
{
	return _minimumLineHeight;
}

- (CGFloat)firstLineHeadIndent
{
	return _firstLineHeadIndent;
}

- (CGFloat)headIndent
{
	return _headIndent;
}

- (CGFloat)tailIndent
{
	return _tailIndent;
}

- (CGFloat)lineSpacing
{
	return _lineSpacing;
}

- (CGFloat)paragraphSpacing
{
	return _paragraphSpacing;
}

- (CGFloat)paragraphSpacingBefore
{
	return _paragraphSpacingBefore;
}

- (float)hyphenationFactor
{
	return _hyphenationFactor;
}

- (float)tighteningFactorForTruncation
{
	return _tighteningFactorForTruncation;
}

- (CGFloat)defaultTabInterval
{
	return _defaultTabInterval;
}

- (NSArray *)tabStops
{
	return (_tabStops != nil) ? _tabStops : [NSArray array];
}

- (NSArray *)textLists
{
	return (_textLists != nil) ? _textLists : [NSArray array];
}

- (void)setTextLists:(NSArray *)textLists
{
	NSMutableArray *owned = [NSMutableArray array];
	NSUInteger k;

	for (k = 0; k < [textLists count]; k++) {
		[owned addObject:[[[textLists objectAtIndex:k] copy] autorelease]];
	}
	fn_link_list_stack(owned);
	[_textLists release];
	_textLists = [owned copy];
}

- (NSArray *)textBlocks
{
	return (_textBlocks != nil) ? _textBlocks : [NSArray array];
}

- (NSInteger)headerLevel
{
	return _headerLevel;
}


@end

@implementation NSMutableParagraphStyle

/* THE SETTERS ARE ONE ASSIGNMENT EACH, because the value is already validated by its TYPE — an alignment is one of five
 * cases and a distance is a CGFloat, so there is nothing here to refuse. */
- (void)setHeaderLevel:(NSInteger)level { _headerLevel = level; }

/* **THE BULK ASSIGNMENT, PROPERTY BY PROPERTY.** Every scalar is an assignment; the three arrays go through this class's
 * own copying setters, so a caller that later changed the source style's blocks cannot reach into the receiver. */
- (void)setParagraphStyle:(NSParagraphStyle *)style
{
	if (style == nil || style == self) {
		return;
	}
	_alignment = style->_alignment;
	_lineBreakMode = style->_lineBreakMode;
	_baseWritingDirection = style->_baseWritingDirection;
	_lineHeightMultiple = style->_lineHeightMultiple;
	_maximumLineHeight = style->_maximumLineHeight;
	_minimumLineHeight = style->_minimumLineHeight;
	_firstLineHeadIndent = style->_firstLineHeadIndent;
	_headIndent = style->_headIndent;
	_tailIndent = style->_tailIndent;
	_lineSpacing = style->_lineSpacing;
	_paragraphSpacing = style->_paragraphSpacing;
	_paragraphSpacingBefore = style->_paragraphSpacingBefore;
	_hyphenationFactor = style->_hyphenationFactor;
	_tighteningFactorForTruncation = style->_tighteningFactorForTruncation;
	_defaultTabInterval = style->_defaultTabInterval;
	_headerLevel = style->_headerLevel;
	[self setTabStops:style->_tabStops];
	[self setTextBlocks:style->_textBlocks];
	[self setTextLists:style->_textLists];
}

- (void)setAlignment:(NSTextAlignment)alignment { _alignment = alignment; }
- (void)setLineBreakMode:(NSLineBreakMode)lineBreakMode { _lineBreakMode = lineBreakMode; }
- (void)setBaseWritingDirection:(NSWritingDirection)baseWritingDirection { _baseWritingDirection = baseWritingDirection; }
- (void)setLineHeightMultiple:(CGFloat)lineHeightMultiple { _lineHeightMultiple = lineHeightMultiple; }
- (void)setMaximumLineHeight:(CGFloat)maximumLineHeight { _maximumLineHeight = maximumLineHeight; }
- (void)setMinimumLineHeight:(CGFloat)minimumLineHeight { _minimumLineHeight = minimumLineHeight; }
- (void)setFirstLineHeadIndent:(CGFloat)firstLineHeadIndent { _firstLineHeadIndent = firstLineHeadIndent; }
- (void)setHeadIndent:(CGFloat)headIndent { _headIndent = headIndent; }
- (void)setTailIndent:(CGFloat)tailIndent { _tailIndent = tailIndent; }
- (void)setLineSpacing:(CGFloat)lineSpacing { _lineSpacing = lineSpacing; }
- (void)setParagraphSpacing:(CGFloat)paragraphSpacing { _paragraphSpacing = paragraphSpacing; }
- (void)setParagraphSpacingBefore:(CGFloat)paragraphSpacingBefore { _paragraphSpacingBefore = paragraphSpacingBefore; }
- (void)setHyphenationFactor:(float)hyphenationFactor { _hyphenationFactor = hyphenationFactor; }
- (void)setTighteningFactorForTruncation:(float)tighteningFactorForTruncation { _tighteningFactorForTruncation = tighteningFactorForTruncation; }
- (void)setDefaultTabInterval:(CGFloat)defaultTabInterval { _defaultTabInterval = defaultTabInterval; }

- (void)setTabStops:(NSArray *)tabStops
{
	NSArray *held = (tabStops != nil) ? [[NSArray alloc] initWithArray:tabStops copyItems:YES] : nil;

	[_tabStops release];
	_tabStops = held;
}

- (void)addTabStop:(NSTextTab *)textTab
{
	NSMutableArray *stops = (_tabStops != nil) ? [_tabStops mutableCopy] : [[NSMutableArray alloc] init];

	[stops addObject:textTab];
	[_tabStops release];
	_tabStops = stops;
}

- (void)removeTabStop:(NSTextTab *)textTab
{
	NSMutableArray *stops = [_tabStops mutableCopy];

	[stops removeObjectIdenticalTo:textTab];
	[_tabStops release];
	_tabStops = stops;
}

- (void)setTextBlocks:(NSArray *)textBlocks
{
	NSArray *held = (textBlocks != nil) ? [[NSArray alloc] initWithArray:textBlocks copyItems:YES] : nil;

	[_textBlocks release];
	_textBlocks = held;
}

- (void)addTextBlock:(NSTextBlock *)textBlock
{
	NSMutableArray *blocks = (_textBlocks != nil) ? [_textBlocks mutableCopy] : [[NSMutableArray alloc] init];

	[blocks addObject:textBlock];
	[_textBlocks release];
	_textBlocks = blocks;
}

- (void)removeTextBlock:(NSTextBlock *)textBlock
{
	NSMutableArray *blocks = [_textBlocks mutableCopy];

	[blocks removeObjectIdenticalTo:textBlock];
	[_textBlocks release];
	_textBlocks = blocks;
}

/* **AND A MUTABLE STYLE'S `-copy` IS AN IMMUTABLE ONE**, which is the door that lets a builder be frozen before it goes
 * into a store. It is the same ledger copy the superclass's `-mutableCopy` writes, into the immutable class. */
- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return [[NSParagraphStyle allocWithZone:zone] initWithParagraphStyle:self];
}

@end
