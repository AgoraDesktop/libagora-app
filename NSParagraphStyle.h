/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSParagraphStyle.h — THE LINE-BREAK VOCABULARY AND THE STYLE CLASS THAT CARRIES IT.
 *
 * **THE CLASS ARRIVED WITH ITS FIRST TWO READERS, AND THE REST OF ITS PROPERTIES ARE CARRIED AND ANSWERED AND WAIT
 * FOR THEIRS.** The vocabulary below came first — `NSLineBreakMode` is what `NSCell`'s `-lineBreakMode` is declared in
 * terms of, and Apple declares it here because a line-break mode IS a paragraph property. What was owed was the pair
 * of classes named beside it: `NSParagraphStyle` is a VALUE OBJECT (a run's paragraph settings, copied not referenced)
 * and `NSMutableParagraphStyle` is the one a builder fills in. THE LAYOUT MANAGER READS TWO OF THE PROPERTIES TODAY —
 * the ALIGNMENT (it offsets a line inside the width the container gave it) and the LINE-BREAK MODE (it puts the style
 * into the attributed string the typesetter reads, which obeys the mode) — AND THE OTHERS ARE CARRIED because a
 * paragraph style without its spacing is not the class a caller can port against. `-lineSpacing`, the three indents,
 * the three line-height properties, the two paragraph spacings and the hyphenation factor have no reader in
 * `NSLayoutManager` YET; that is named at each door below rather than left for a caller to discover, and it is the
 * honest shape of a value object whose consumer is a slice behind it.
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
 * WHAT IS STILL NOT HERE, AND ITS ROWS STAY OPEN: `NSTextTab` — the tab-stop element `-tabStops` would hold — and with
 * it `-tabStops`, because a tab stop is a claim about a class this tier has not got; `-defaultTabInterval` is carried
 * without it because it is a bare distance. And `NSTabColumnTerminatorsAttributeName`.
 */
#ifndef APPKIT_NSPARAGRAPHSTYLE_H
#define APPKIT_NSPARAGRAPHSTYLE_H

#import <AppKit/NSText.h>

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
}

/* **ONE SHARED DEFAULT, WHICH IS APPLE'S OWN DOOR AND THE REASON A RUN WITH NO STYLE STILL HAS ONE.** The default has
 * the left-aligned (natural), word-wrapping, zero-everything shape, and it is IMMUTABLE — a caller that wants to change
 * one asks for `-mutableCopy` rather than rewriting the shared instance. */
+ (NSParagraphStyle *)defaultParagraphStyle;

/* **THE ALIGNMENT, WHICH THE LAYOUT MANAGER READS.** `NSNaturalTextAlignment` means "left" here because this tier
 * lays out left-to-right only; the other three are left, right and centre as the line sits inside the container's
 * width. JUSTIFICATION is a fourth value the type carries and the layout does NOT stretch lines for yet — it draws a
 * justified paragraph left-aligned, which is named rather than silently wrong. */
- (NSTextAlignment)alignment;

/* **AND THE LINE-BREAK MODE, WHICH THE LAYOUT MANAGER READS.** It travels into the attributed string the TYPESETTER
 * breaks, so a mode other than word wrapping changes where lines end; the two truncating modes are obeyed by the
 * typesetter as "do not wrap" and the ellipsis is the drawing slice's, named there. */
- (NSLineBreakMode)lineBreakMode;

/* THE DIRECTION THE RUN READS. Natural is the Unicode algorithm's; `-baseWritingDirectionForLanguage:` is the door that
 * would consult it, and this tier lays out left-to-right so the value is carried and not yet consulted. */
- (NSWritingDirection)baseWritingDirection;

/* ---- THE GEOMETRY, WHICH IS RECORDED AND ANSWERED AND HAS NO READER IN THE LAYOUT YET ------------------ */

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
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPARAGRAPHSTYLE_H */
