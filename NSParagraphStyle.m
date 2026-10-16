/*
 * NSParagraphStyle.m — the paragraph settings a run carries, as a value.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLASS IS A LEDGER AND A COPY, WHICH IS THE WHOLE OF IT.** Every door above answers a scalar that was set when
 * the style was made; the only arithmetic is the copy that turns an immutable style into a mutable one and back. THAT
 * IS WHY THE MUTABLE CLASS IS A SUBCLASS and not a flag: a caller holding an `NSParagraphStyle *` has a value it can
 * hand to a store and trust, and a caller that wants to change one asks for `-mutableCopy` in as many words.
 *
 * AND `-copy`, NOT `-copyWithZone:`, BECAUSE THIS TREE HAS NO ZONES: `NSCopying`'s only member is `-copy` (NSObject.h
 * states the decision and its cost), so a zone-taking door here would be a second copy protocol nobody conforms to.
 */
#import <AppKit/NSParagraphStyle.h>
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
		/* **AND THE BLOCKS ARE COPIED, not shared**, because a paragraph style is a value: a caller that changed an
		 * array it had handed to a store would be changing the document behind the store's back. The array is immutable
		 * and every block in it is copied. */
		_textBlocks = [[NSArray alloc] initWithArray:style->_textBlocks copyItems:YES];
		_tabStops = [[NSArray alloc] initWithArray:style->_tabStops copyItems:YES];
	}
	return self;
}

- (void)dealloc
{
	[_textBlocks release];
	[_tabStops release];
	[super dealloc];
}

/* AN IMMUTABLE STYLE HAS NOTHING TO COPY: the object cannot have changed since it was made, so the copy IS the
 * original and the retain is the whole implementation — the same answer `NSColor -copy` gives. */
- (id)copy
{
	return [self retain];
}

/* AND THE MUTABLE COPY IS A SECOND LEDGER FILLED FROM THIS ONE. */
- (id)mutableCopy
{
	return [[NSMutableParagraphStyle alloc] initWithParagraphStyle:self];
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

- (NSArray *)textBlocks
{
	return (_textBlocks != nil) ? _textBlocks : [NSArray array];
}

@end

@implementation NSMutableParagraphStyle

/* THE SETTERS ARE ONE ASSIGNMENT EACH, because the value is already validated by its TYPE — an alignment is one of five
 * cases and a distance is a CGFloat, so there is nothing here to refuse. */
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
- (id)copy
{
	return [[NSParagraphStyle alloc] initWithParagraphStyle:self];
}

@end
