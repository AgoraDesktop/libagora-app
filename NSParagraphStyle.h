/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSParagraphStyle.h — THE LINE-BREAK VOCABULARY AND THE STYLE CLASS THAT CARRIES IT.
 *
 * **THE CLASS ARRIVED WITH ITS FIRST TWO READERS, AND THE LAYOUT READS THE GEOMETRY NOW TOO.** The vocabulary below
 * came first — `NSLineBreakMode` is what `NSCell`'s `-lineBreakMode` is declared in terms of, and Apple declares it
 * here because a line-break mode IS a paragraph property. What was owed was the pair of classes named beside it:
 * `NSParagraphStyle` is a VALUE OBJECT (a run's paragraph settings, copied not referenced) and `NSMutableParagraphStyle`
 * is the one a builder fills in. THE LAYOUT MANAGER READS NEARLY ALL OF IT: the ALIGNMENT offsets a line inside the
 * width the container gave it; the LINE-BREAK MODE goes into the attributed string the typesetter obeys; the two HEAD
 * INDENTS place the first line and the wrapped ones; the TAIL INDENT takes width off the line; `-lineSpacing` and the
 * two PARAGRAPH SPACINGS are the gaps between lines and across paragraph boundaries; and the LINE-HEIGHT MULTIPLE with
 * its MINIMUM and MAXIMUM set the band. WHAT IT STILL DOES NOT READ is the HYPHENATION FACTOR — and the reason is
 * NO LONGER THE ENGINE'S: the RESOURCE arrived, in `libagora-core/CFHyphenation.c`, which answers Core Foundation's
 * `CFStringGetHyphenationLocationBeforeIndex` — the very door platform AppKit reads this factor through — so the
 * factor is READABLE now and having the layout manager read it is what is owed — and THE BASE WRITING DIRECTION is
 * read only so far as NATURAL ALIGNMENT: it decides which edge "natural"
 * means, while reordering the glyphs of a right-to-left SCRIPT is the engine's (it now READS the direction — the line
 * hands it to the run, `CTRunGetStatus` — but does not reorder yet). Each is
 * named at its door below.
 *
 * **AND THE STYLE'S CONSUMER IS THE LAYOUT, NOT FOUR SEPARATE DOORS.** A paragraph style could have been four
 * properties on the view, and instead it is one object the store carries — which is what lets a run of text and the
 * geometry it is set in travel together, and what makes a wrapped line read the SAME style as the line it wrapped from.
 *
 * AND THE IMPORT BELOW IS APPLE'S OWN INCLUDE GRAPH: the era's `NSParagraphStyle.h` imports `AppKit/NSText.h`, because
 * a paragraph style has an ALIGNMENT — so the two headers this unit adds depend on each other in the same direction
 * Apple's do.
 *
 * THE VALUES ARE THE 10.6 HEADER'S, TRANSCRIBED IN ORDER: the mode is `NSUInteger` and the six cases run 0 through 5,
 * with `NSLineBreakByWordWrapping` first — WHICH IS ALSO THE TYPE'S ZERO, so a fresh style's line-break mode needs no
 * initialiser, unlike the alignment one file over, whose default is not its zero. The era's short gloss on each case is
 * kept, because "truncating head" and "truncating tail" are not shapes a reader can guess from the names alone.
 *
 * WHAT IS STILL NOT HERE, AND ITS ROWS STAY OPEN: `NSTextTab` IS HERE NOW, and with it `-tabStops` — the stops are
 * the layout's (`CTTextTab` is what `CTLine` advances a `\t` to), so this class carries them and the engine walks
 * them. `-defaultTabInterval` is the fallback after the last stop and is read too, and
 * `+[NSTextTab columnTerminatorsForLocale:]` and `NSTabColumnTerminatorsAttributeName` are here, and a DECIMAL TAB IS
 * ALIGNED NOW: the manager moves the stop left by the integer part's width so the point lands on it, reading the stop's
 * own `-options` terminators when it has them — which `-initWithType:location:options:` is the door that sets. Nothing
 * on that row is owed.
 */
#ifndef APPKIT_NSPARAGRAPHSTYLE_H
#define APPKIT_NSPARAGRAPHSTYLE_H

#import <AppKit/NSText.h>
#import <AppKit/NSTextTab.h>

@class NSTextBlock;

NS_ASSUME_NONNULL_BEGIN

/* WHAT TO DO WITH A LINE THAT IS TOO LONG. The era comments each case with the shape a caller gets, and the first
 * entry is the default — the class this type belongs to states that in as many words. */
enum {
	NSLineBreakByWordWrapping = 0,		/* Wrap at word boundaries; the default */
	NSLineBreakByCharWrapping,		/* Wrap at character boundaries */
	NSLineBreakByClipping,			/* Simply clip the overflow */
	NSLineBreakByTruncatingHead,		/* Truncate at the head: "...wxyz" */
	NSLineBreakByTruncatingTail,		/* Truncate at the tail: "abcd..." */
	NSLineBreakByTruncatingMiddle		/* Truncate the middle: "ab...yz" */
};
typedef NSUInteger NSLineBreakMode;

/* ============================================================================================ *
 * AND THE STYLE ITSELF, WHICH IS A VALUE: a run's paragraph settings, and NOT a reference another *
 * object keeps. Every door below answers a fact that was set when the style was made; the two the  *
 * layout manager reads are marked, and the rest say plainly that their reader is still owed.      *
 * ============================================================================================ */

@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying>
{
	NSTextAlignment _alignment;
	NSLineBreakMode _lineBreakMode;
	NSWritingDirection _baseWritingDirection;
	CGFloat _lineHeightMultiple;
	CGFloat _maximumLineHeight;
	CGFloat _minimumLineHeight;
	CGFloat _firstLineHeadIndent;
	CGFloat _headIndent;
	CGFloat _tailIndent;
	CGFloat _lineSpacing;
	CGFloat _paragraphSpacing;
	CGFloat _paragraphSpacingBefore;
	float _hyphenationFactor;
	float _tighteningFactorForTruncation;
	CGFloat _defaultTabInterval;
	/* **AND THE STOPS A TAB GOES TO, IN ORDER.** A `\t` advances to the first stop past the pen; after the last one the
	 * text falls back to `-defaultTabInterval`. The array is retained and its tabs are copied with the style, because a
	 * paragraph style is a value. */
	NSArray *_tabStops;	/* RETAINED */
	/* **AND THE BOXES THE PARAGRAPH IS SET IN, WHICH IS WHERE A TABLE CELL LIVES.** Apple attaches `NSTextBlock`s to a
	 * paragraph through the style rather than a character attribute, because a block is a PARAGRAPH property: every line
	 * of the paragraph shares the box, and a `NSTextTableBlock` in this array is what makes the paragraph a table
	 * cell. The array is retained; `NSParagraphStyle` is a value, so the blocks in it are copied with it. */
	NSArray *_textBlocks;	/* RETAINED */
}

/* **ONE SHARED DEFAULT, WHICH IS APPLE'S OWN DOOR AND THE REASON A RUN WITH NO STYLE STILL HAS ONE.** The default has
 * the left-aligned (natural), word-wrapping, zero-everything shape, and it is IMMUTABLE — a caller that wants to change
 * one asks for `-mutableCopy` rather than rewriting the shared instance. */
+ (NSParagraphStyle *)defaultParagraphStyle;

/* **THE DEFAULT DIRECTION FOR A LANGUAGE, WHICH IS WHAT A NATURAL DIRECTION READS.** "ar" and "he" answer
 * right-to-left, "en" and "fr" left-to-right — the language's OWN direction rather than a guess from the text — and a
 * nil language asks the current locale's. It is a class method because a caller consults it to RESOLVE a natural
 * direction before setting one. */
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(nullable NSString *)languageName;

/* **THE ALIGNMENT, WHICH THE LAYOUT MANAGER READS.** `NSNaturalTextAlignment` means the edge the BASE WRITING
 * DIRECTION names — left for a left-to-right paragraph, right for a right-to-left one — so it is RESOLVED rather than
 * fixed; the other three are left, right and centre as the line sits inside the container's width. JUSTIFICATION is a
 * fourth value the type carries and the layout does NOT stretch lines for yet — it draws a justified paragraph
 * left-aligned, which is named rather than silently wrong. */
- (NSTextAlignment)alignment;

/* **AND THE LINE-BREAK MODE, WHICH THE LAYOUT MANAGER READS.** It travels into the attributed string the TYPESETTER
 * breaks, so a mode other than word wrapping changes where lines end; the two truncating modes are obeyed by the
 * typesetter as "do not wrap" and the ellipsis is the drawing slice's, named there. */
- (NSLineBreakMode)lineBreakMode;

/* **THE DIRECTION THE RUN READS, WHICH DECIDES WHAT NATURAL ALIGNMENT MEANS.** `NSWritingDirectionNatural` is the
 * Unicode algorithm's (resolved through `+defaultWritingDirectionForLanguage:`), and the LAYOUT reads this field THAT
 * far: a natural paragraph in a right-to-left direction aligns RIGHT. REORDERING THE GLYPHS of a right-to-left SCRIPT
 * is the ENGINE's: its Core Text now READS the direction (the line hands it to the run, `CTRunGetStatus`) but does not
 * reorder yet, so a mixed-direction run is not this door's to fix — named rather than left to look done. */
- (NSWritingDirection)baseWritingDirection;

/* ---- THE GEOMETRY, WHICH THE LAYOUT NOW READS ---------------------------------------------------------- */

- (CGFloat)lineHeightMultiple;
- (CGFloat)maximumLineHeight;
- (CGFloat)minimumLineHeight;
- (CGFloat)firstLineHeadIndent;
- (CGFloat)headIndent;
- (CGFloat)tailIndent;
- (CGFloat)lineSpacing;
- (CGFloat)paragraphSpacing;
- (CGFloat)paragraphSpacingBefore;
- (float)hyphenationFactor;
- (float)tighteningFactorForTruncation;
- (CGFloat)defaultTabInterval;

/* ---- AND THE STOPS A TAB GOES TO ----------------------------------------------------------- */

/* **AN ORDERED ARRAY OF `NSTextTab`s.** The layout manager copies them into the `CTParagraphStyle` it builds, and
 * `CTLine` advances a tab to the next one; the array is by LOCATION, which is what an ordered list of stops is. */
- (NSArray *)tabStops;

/* ---- AND THE BLOCKS THE PARAGRAPH IS SET IN ------------------------------------------------ */

/* **AN ARRAY OF `NSTextBlock`s, DRAWN OUTWARD FROM THE TEXT IN THE ORDER GIVEN.** A paragraph in a table cell carries
 * its `NSTextTableBlock` here; a plain block is a box without a cell. The layout manager reads this array, finds the
 * block covering a line, and draws it; the grid across cells is the table's layout, not the style's. */
- (NSArray *)textBlocks;

@end

/* **AND THE MUTABLE ONE, WHICH IS WHAT A BUILDER FILLS IN.** It is a SUBCLASS and not a flag on the immutable class,
 * which is Apple's shape and the reason a style can be trusted once it is in a store: a caller that holds an
 * `NSParagraphStyle *` cannot change it, and a caller that wants to change one says `-mutableCopy` out loud. */
@interface NSMutableParagraphStyle : NSParagraphStyle
- (void)setAlignment:(NSTextAlignment)alignment;
- (void)setLineBreakMode:(NSLineBreakMode)lineBreakMode;
- (void)setBaseWritingDirection:(NSWritingDirection)baseWritingDirection;
- (void)setLineHeightMultiple:(CGFloat)lineHeightMultiple;
- (void)setMaximumLineHeight:(CGFloat)maximumLineHeight;
- (void)setMinimumLineHeight:(CGFloat)minimumLineHeight;
- (void)setFirstLineHeadIndent:(CGFloat)firstLineHeadIndent;
- (void)setHeadIndent:(CGFloat)headIndent;
- (void)setTailIndent:(CGFloat)tailIndent;
- (void)setLineSpacing:(CGFloat)lineSpacing;
- (void)setParagraphSpacing:(CGFloat)paragraphSpacing;
- (void)setParagraphSpacingBefore:(CGFloat)paragraphSpacingBefore;
- (void)setHyphenationFactor:(float)hyphenationFactor;
- (void)setTighteningFactorForTruncation:(float)tighteningFactorForTruncation;
- (void)setDefaultTabInterval:(CGFloat)defaultTabInterval;
- (void)setTabStops:(NSArray *)tabStops;
- (void)addTabStop:(NSTextTab *)textTab;
- (void)removeTabStop:(NSTextTab *)textTab;
- (void)setTextBlocks:(NSArray *)textBlocks;
- (void)addTextBlock:(NSTextBlock *)textBlock;
- (void)removeTextBlock:(NSTextBlock *)textBlock;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPARAGRAPHSTYLE_H */
