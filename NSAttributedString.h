/*
 * NSAttributedString.h (AppKit) — the attribute NAMES, which are the AppKit's and not Foundation's.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **APPLE SPLITS THE ATTRIBUTED STRING BETWEEN TWO FRAMEWORKS, AND THIS FILE IS THE SPLIT.** Foundation owns the
 * CLASS (`NSAttributedString` and its range API, which this tree already ships); the AppKit owns the KEYS that
 * say what a run of text MEANS — and the era's own `NSStringDrawing.h` imports this header for exactly that
 * reason (10.6 line 11). So the keys live here, in an AppKit header Apple also names `NSAttributedString.h`.
 *
 * **AND WHAT THIS HEADER CARRIES IS THE KEYS THE TEXT LAYER READS, ARRIVING WITH THOSE READERS.** Apple's era header
 * declares twenty of these (`NSAttachmentAttributeName`, …) and each one is a claim about a VALUE TYPE this tier may
 * not have yet — an attachment, a marked range — so declaring them all would be writing twenty promises to satisfy one
 * unit. The nine below are the ones a caller can NAME TODAY: the font and the foreground colour a
 * `-drawAtPoint:withAttributes:` caller must have, the ink keys the layout manager's own doors read
 * (`-drawBackgroundForGlyphRange:atPoint:` and the rule half of `-drawGlyphsForGlyphRange:atPoint:`) — a background, an
 * underline and a strikethrough, each with its colour — and the paragraph style whose alignment and line-break mode it
 * lays out by. The rest arrive with the classes they name.
 *
 * **THE LITERALS ARE OURS, AND THE REASON IS MEASURED RATHER THAN ASSUMED**: the era header annotates each name
 * with the VALUE'S TYPE and default (`// NSFont, default Helvetica 12`) and publishes no literal, so no era
 * artifact fixes the strings. These are Apple's long-standing spellings; what the probes CAN prove is the
 * behaviour that matters — that a dictionary keyed by them reaches the text layer and changes what is drawn.
 */
#ifndef APP_KIT_NSATTRIBUTEDSTRING_H
#define APP_KIT_NSATTRIBUTEDSTRING_H

#import <Foundation/Foundation.h>

/* THE FONT OF A RUN OF TEXT. Apple's era annotation: "NSFont, default Helvetica 12" — and THE DEFAULT IS A
 * DIVERGENCE IN THIS TIER, because there is no Helvetica here: a string drawn with no font attribute is drawn in
 * this tier's own system font at 12 points, which is `+[NSFont systemFontOfSize:12.0]`'s answer. */
extern NSString *NSFontAttributeName;

/* THE COLOUR OF A RUN OF TEXT. Apple's era annotation: "NSColor, default blackColor" — and black is what this
 * tier draws with when the key is absent, so the default needs no divergence note. */
extern NSString *NSForegroundColorAttributeName;

/* **AND THE THREE KEYS THE LAYOUT MANAGER'S OWN INK READS.** Apple's era header annotates each with the VALUE'S
 * type and default, and the same rule holds: a key is declared here when the class that CONSUMES its value exists.
 * `-drawBackgroundForGlyphRange:atPoint:` and the underline half of `-drawGlyphsForGlyphRange:atPoint:` are those
 * consumers, so the three arrive with them rather than twenty arriving for one unit. `NSBackgroundColorAttributeName`
 * carries an `NSColor` and the two underline keys an `NSNumber` (an `NSUnderlineStyle`) and an `NSColor`. */
extern NSString *NSBackgroundColorAttributeName;
extern NSString *NSUnderlineStyleAttributeName;
extern NSString *NSUnderlineColorAttributeName;

/* **AND THE STRIKETHROUGH PAIR, WHICH SPENDS THE SAME STYLE NUMBER.** Apple's era header names no separate
 * `NSStrikethroughStyle` type: `NSStrikethroughStyleAttributeName` carries an `NSUnderlineStyle` value — the four
 * shapes and the pattern byte are the same vocabulary, and a line through the middle of a run is a line under it drawn
 * at a different offset. So the two keys below arrive with the door that draws them and no new type is invented. */
extern NSString *NSStrikethroughStyleAttributeName;
extern NSString *NSStrikethroughColorAttributeName;

/* **AND WHAT A WHOLE PARAGRAPH OF A RUN IS SET IN.** The value is an `NSParagraphStyle`, and the one part of it the
 * layout reads TODAY is the alignment and the line-break mode; see `NSParagraphStyle.h` for the property-by-property
 * account of what is carried and what has a reader. */
extern NSString *NSParagraphStyleAttributeName;

/* **AND THE OBJECT THAT STANDS IN FOR A PICTURE.** The value is an `NSTextAttachment`, and the character it is set
 * over is `NSAttachmentCharacter` (U+FFFC) — so an attachment travels with the run it sits in, and this key is what the
 * manager reads to know to draw a cell instead of the glyphs at that character. */
extern NSString *NSAttachmentAttributeName;

/* **AND THE STYLE THE NUMBER SPELLS, WHICH IS ONE ENUM BECAUSE A STYLE AND ITS PATTERN OR-TOGETHER.** The four
 * shapes are the low bits and the patterns the high byte, which is what makes `NSUnderlineStyleSingle |
 * NSUnderlinePatternDash` a legal value rather than two keys. THE VALUES ARE APPLE'S, GAP INCLUDED: the shapes run
 * 0x00, 0x01, 0x02 and then 0x09 — 0x03 through 0x08 are not underline styles — and `NSUnderlineByWord` is the
 * odd bit out at the top, a modifier that says WHERE the line goes rather than how it looks. The same spellings
 * exist in Core Text as `kCTUnderlineStyle…`, and the two must agree for a dictionary that crosses. */
enum {
	NSUnderlineStyleNone = 0x00,
	NSUnderlineStyleSingle = 0x01,
	NSUnderlineStyleThick = 0x02,
	NSUnderlineStyleDouble = 0x09,
	NSUnderlinePatternSolid = 0x0000,
	NSUnderlinePatternDot = 0x0100,
	NSUnderlinePatternDash = 0x0200,
	NSUnderlinePatternDashDot = 0x0300,
	NSUnderlinePatternDashDotDot = 0x0400,
	NSUnderlineByWord = 0x8000
};
typedef NSInteger NSUnderlineStyle;

/* ============================================================================================ *
 * AND THE DOOR THAT READS RICH TEXT FORMAT (RTF), WHICH IS THE HALF THIS TIER'S FOUNDATION DOES *
 * NOT HAVE. `libagora-base` already WRITES RTF — its `-RTFFromRange:documentAttributes:` is a real   *
 * writer, keyed on its own presentation-intent bits — but a READER has to turn RTF's control words   *
 * into the APPKIT's attribute keys (`NSFontAttributeName`, `NSForegroundColorAttributeName`, …),    *
 * which is exactly the vocabulary Foundation does not have. So the reader lives here, in the file   *
 * Apple declares the RTF category in, and it understands the subset this tier can draw: the font    *
 * table and `\f`/`\fs`, the colour table and `\cf`/`\highlight`, `\ul`/`\strike`, and the     *
 * paragraph alignments. **AND THE APPKIT-AWARE WRITER IS HERE BESIDE IT**: `-RTFRepresentation` encodes            *
 * NSFont/NSColor/the two rules and the paragraph style — rather than Foundation's intent bits — so a              *
 * document this tier built is written and read back by the reader above.                                             *
 * ============================================================================================ */

@interface NSAttributedString (NSAttributedStringKitAdditions)

/* **THE READER.** A failed parse answers nil rather than an empty string, because a caller that handed over bytes
 * which are not RTF should be able to tell. `documentAttributes` is filled with the document's own facts (the
 * character encoding), which is the one key this tier has an answer for. */
- (nullable instancetype)initWithRTF:(NSData *)data documentAttributes:(NSDictionary **)dict;

/* **AND THE WRITER, WHICH IS THE SAME CODEC THE OTHER WAY.** Foundation already writes RTF, but keyed on ITS
 * presentation-intent bits; this door encodes the APPKIT's own attributes — `NSFontAttributeName`,
 * `NSForegroundColorAttributeName`, `NSBackgroundColorAttributeName`, the two rules and the paragraph alignment —
 * building the font and colour tables `-initWithRTF:` reads, so a document this tier built survives a round trip. */
- (nullable NSData *)RTFRepresentation;

@end

#endif /* APP_KIT_NSATTRIBUTEDSTRING_H */
