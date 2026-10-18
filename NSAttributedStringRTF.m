/*
 * NSAttributedStringRTF.m — the RTF reader, which is the half this tier's Foundation does not have.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE PARSER UNDERSTANDS THE SUBSET THE TIER CAN DRAW.** RTF is ASCII with control words and two tables: a FONT
 * TABLE (`\fN` names a face) and a COLOUR TABLE (`\redN\greenN\blueN` is one entry, indexed from 1 because index 0
 * is RTF's "auto"). A run's formatting is the control words in force where it sits, so the reader carries that
 * state — the face, the size, the two inks, the two rules, the paragraph's alignment — and pushes an
 * ATTRIBUTE MARK whenever the state changes; the marks then become the runs of the attributed string it builds.
 * `\par` and `\line` are the breaks, `\tab` a tab, `\uN?` a Unicode character, `\'hh` a byte, and `\ { }` and
 * `\\` the literal escapes. ANY OTHER CONTROL WORD IS IGNORED, which is the boundary of a codec for a vocabulary
 * this tier actually has; a document carrying bold or italic survives with those bits dropped rather than wrong.
 */
#import "NSAttributedStringRTF_internal.h"
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSTextAttachment.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdint.h>

/* ============================================================================================ *
 * AND THE WRITER, WHICH IS THE SAME CODEC THE OTHER WAY                                            *
 * ============================================================================================ */

/* A CONTROL WORD RUNS UNTIL A NON-ALPHABETIC, so one followed by text needs a delimiting space — which is the space
 * the reader eats rather than putting into the text. */
static void fn_emit_word(NSMutableString *out, NSString *word)
{
	[out appendString:word];
	[out appendString:@" "];
}

/* THE FONT TABLE'S INDEX FOR A NAME, adding it when the run names a face not seen yet. */
static NSInteger fn_font_index(NSMutableArray *names, NSString *name)
{
	NSUInteger k;

	for (k = 0; k < [names count]; k++) {
		if ([[names objectAtIndex:k] isEqualToString:name]) {
			return (NSInteger)k;
		}
	}
	[names addObject:name];
	return (NSInteger)[names count] - 1;
}

/* THE COLOUR TABLE STARTS WITH RTF'S "auto" AT 0, so a colour stored at index k in the array is written at k + 1. */
static NSInteger fn_colour_index(NSMutableArray *colours, NSColor *colour)
{
	NSUInteger k;

	for (k = 0; k < [colours count]; k++) {
		NSColor *c = [colours objectAtIndex:k];

		if (fabs([c redComponent] - [colour redComponent]) < 0.002
		    && fabs([c greenComponent] - [colour greenComponent]) < 0.002
		    && fabs([c blueComponent] - [colour blueComponent]) < 0.002) {
			return (NSInteger)k + 1;
		}
	}
	[colours addObject:colour];
	return (NSInteger)[colours count];
}

/* **A PICTURE, WRITTEN AS RTF's OWN GROUP.** `{\pict\pngblip\picw<px>\pich<px>\picwgoal<tw>\pichgoal<tw> <hex>}` is
 * the shape every RTF writer emits for a PNG, and the bytes come from `NSBitmapImageRep`'s encoder — which is Core
 * Graphics' `CGImageDestination` — so this method has no image code in it either. THE PIXEL SIZE AND THE GOAL SIZE ARE
 * BOTH WRITTEN because they say different things: `\picw`/`\pich` are the picture's own pixels, `\picwgoal`/
 * `\pichgoal` are how big to draw it in TWIPS (1/1440 inch), and the goal is the pixel size at 72 dpi — twenty twips to
 * the pixel — which is the same size a rep drawn at its natural size has.
 *
 * FALSE MEANS "NOTHING WAS WRITTEN", and the caller then writes the character itself: an attachment with no image is a
 * character that draws nothing, and dropping it from the document would lose the caller's text. */
static BOOL fn_emit_picture(NSMutableString *out, NSTextAttachment *attachment)
{
	NSImage *image = [attachment image];
	NSData *png = nil;
	NSSize size;
	NSImageRep *rep;
	long width = 0, height = 0;
	const unsigned char *bytes;
	NSUInteger k;

	if (image == nil) {
		return NO;
	}
	size = [image size];
	rep = [image bestRepresentationForRect:NSMakeRect(0, 0, size.width, size.height) context:nil hints:nil];
	if (![rep isKindOfClass:[NSBitmapImageRep class]]) {
		return NO;
	}
	png = [(NSBitmapImageRep *)rep representationUsingType:NSPNGFileType properties:nil];
	if (png == nil || [png length] == 0) {
		return NO;
	}
	width = (long)[(NSBitmapImageRep *)rep pixelsWide];
	height = (long)[(NSBitmapImageRep *)rep pixelsHigh];
	if (width <= 0 || height <= 0) {
		return NO;
	}
	[out appendString:@"{\\pict\\pngblip"];
	[out appendFormat:@"\\picw%ld\\pich%ld\\picwgoal%ld\\pichgoal%ld ", width, height, width * 20, height * 20];
	bytes = (const unsigned char *)[png bytes];
	for (k = 0; k < [png length]; k++) {
		[out appendFormat:@"%02X", bytes[k]];
	}
	[out appendString:@"}"];
	return YES;
}

/* **AND A PICTURE AS A FILE RATHER THAN AS BYTES, WHICH IS WHAT A PACKAGE DOCUMENT IS.** RTFD keeps each attachment in
 * its own file beside the text and has the text REFER to it, so this writes the format's own reference —
 * `{\NeXTGraphic <filename> \width<twips>\height<twips>}` — and hands the bytes to the caller to put in the package.
 * The filename is the attachment's own preferred name when it has one, so a document that was read from a package
 * writes back with the same names; otherwise a numbered one is invented, and the dictionary returned through
 * `attachmentFiles` is what the package is built from. THE FILE IS NAMED BEFORE THE BYTES ARE MADE, because the name
 * is what the text says and the two must not be able to disagree. */
static BOOL fn_emit_attachment_reference(NSMutableString *out, NSTextAttachment *attachment,
					 NSMutableDictionary *attachmentFiles)
{
	NSImage *image = [attachment image];
	NSData *png = nil;
	NSString *name = nil;
	NSSize size;
	NSImageRep *rep;
	long width, height;

	if (image == nil) {
		return NO;
	}
	size = [image size];
	rep = [image bestRepresentationForRect:NSMakeRect(0, 0, size.width, size.height) context:nil hints:nil];
	if (![rep isKindOfClass:[NSBitmapImageRep class]]) {
		return NO;
	}
	width = (long)[(NSBitmapImageRep *)rep pixelsWide];
	height = (long)[(NSBitmapImageRep *)rep pixelsHigh];
	if (width <= 0 || height <= 0) {
		return NO;
	}
	{
		NSFileWrapper *wrapper = [attachment fileWrapper];
		NSString *preferred = [wrapper preferredFilename];

		if (preferred != nil && [preferred length] > 0) {
			name = preferred;
		} else {
			name = [NSString stringWithFormat:@"Attachment-%lu.png",
							 (unsigned long)([attachmentFiles count] + 1)];
		}
	}
	png = [(NSBitmapImageRep *)rep representationUsingType:NSPNGFileType properties:nil];
	if (png == nil || [png length] == 0) {
		return NO;
	}
	[attachmentFiles setObject:png forKey:name];
	[out appendFormat:@"{\\NeXTGraphic %@ \\width%ld\\height%ld}", name, width * 20, height * 20];
	return YES;
}

NSString *fn_rtf_text(NSAttributedString *source, NSMutableDictionary *attachmentFiles)
{
	NSString *string = [source string];
	NSUInteger n = [string length];
	NSMutableArray *fontNames = [NSMutableArray array];
	NSMutableArray *colours = [NSMutableArray array];
	NSMutableString *out = [NSMutableString string];
	NSInteger curFont = -1, curFg = -1, curBg = -1, curHalf = -1;
	BOOL curUnder = NO, curStrike = NO;
	NSUInteger i;

	for (i = 0; i < n; i++) {
		NSDictionary *a = [source attributesAtIndex:i effectiveRange:NULL];
		NSFont *font = [a objectForKey:NSFontAttributeName];
		NSColor *fg = [a objectForKey:NSForegroundColorAttributeName];
		NSColor *bg = [a objectForKey:NSBackgroundColorAttributeName];

		if (font != nil) {
			fn_font_index(fontNames, [font fontName]);
		}
		if (fg != nil) {
			fn_colour_index(colours, fg);
		}
		if (bg != nil) {
			fn_colour_index(colours, bg);
		}
	}

	[out appendString:@"{\\rtf1\\ansi\\ansicpg1252\\deff0\n"];
	[out appendString:@"{\\fonttbl"];
	for (i = 0; i < [fontNames count]; i++) {
		[out appendFormat:@"{\\f%lu %@;}", (unsigned long)i, [fontNames objectAtIndex:i]];
	}
	[out appendString:@"}\n{\\colortbl;"];
	for (i = 0; i < [colours count]; i++) {
		NSColor *c = [colours objectAtIndex:i];

		[out appendFormat:@"\\red%ld\\green%ld\\blue%ld;",
			(long)lround([c redComponent] * 255.0), (long)lround([c greenComponent] * 255.0),
			(long)lround([c blueComponent] * 255.0)];
	}
	[out appendString:@"}\n\\pard "];

	for (i = 0; i < n; i++) {
		unichar c = [string characterAtIndex:i];
		NSDictionary *a;
		NSFont *font;
		NSColor *fg, *bg;
		NSNumber *under, *strike;

		if (i == 0 || [string characterAtIndex:i - 1] == '\n') {
			NSParagraphStyle *ps = [[source attributesAtIndex:i effectiveRange:NULL]
				objectForKey:NSParagraphStyleAttributeName];
			NSInteger align = (ps != nil) ? [ps alignment] : NSLeftTextAlignment;

			fn_emit_word(out, (align == NSCenterTextAlignment) ? @"\\qc"
				: (align == NSRightTextAlignment) ? @"\\qr"
				: (align == NSJustifiedTextAlignment) ? @"\\qj" : @"\\ql");
		}
		if (c == '\n') {
			[out appendString:@"\\par\n"];
			continue;
		}
		if (c == '\t') {
			[out appendString:@"\\tab "];
			continue;
		}
		if (c == (unichar)NSAttachmentCharacter) {
			/* **AN ATTACHMENT WITH A PICTURE IS A PICTURE GROUP, NOT A CHARACTER.** One without a picture is
			 * written as the character it is, because dropping it would lose the caller's text. */
			NSTextAttachment *attachment = [[source attributesAtIndex:i effectiveRange:NULL]
				objectForKey:NSAttachmentAttributeName];

			if (attachment != nil) {
				BOOL emitted = (attachmentFiles == nil)
					? fn_emit_picture(out, attachment)
					: fn_emit_attachment_reference(out, attachment, attachmentFiles);

				if (emitted) {
					continue;
				}
			}
		}
		a = [source attributesAtIndex:i effectiveRange:NULL];
		font = [a objectForKey:NSFontAttributeName];
		if (font != nil) {
			NSInteger idx = fn_font_index(fontNames, [font fontName]);
			NSInteger half = (NSInteger)lround([font pointSize] * 2.0);

			if (idx != curFont) {
				fn_emit_word(out, [NSString stringWithFormat:@"\\f%ld", (long)idx]);
				curFont = idx;
			}
			if (half != curHalf) {
				fn_emit_word(out, [NSString stringWithFormat:@"\\fs%ld", (long)half]);
				curHalf = half;
			}
		}
		fg = [a objectForKey:NSForegroundColorAttributeName];
		{
			NSInteger idx = (fg != nil) ? fn_colour_index(colours, fg) : 0;

			if (idx != curFg) {
				fn_emit_word(out, [NSString stringWithFormat:@"\\cf%ld", (long)idx]);
				curFg = idx;
			}
		}
		bg = [a objectForKey:NSBackgroundColorAttributeName];
		{
			NSInteger idx = (bg != nil) ? fn_colour_index(colours, bg) : 0;

			if (idx != curBg) {
				fn_emit_word(out, [NSString stringWithFormat:@"\\highlight%ld", (long)idx]);
				curBg = idx;
			}
		}
		under = [a objectForKey:NSUnderlineStyleAttributeName];
		{
			BOOL on = (under != nil && [under integerValue] != NSUnderlineStyleNone);

			if (on != curUnder) {
				fn_emit_word(out, on ? @"\\ul" : @"\\ulnone");
				curUnder = on;
			}
		}
		strike = [a objectForKey:NSStrikethroughStyleAttributeName];
		{
			BOOL on = (strike != nil && [strike integerValue] != NSUnderlineStyleNone);

			if (on != curStrike) {
				fn_emit_word(out, on ? @"\\strike" : @"\\strike0");
				curStrike = on;
			}
		}
		/* THE THREE LITERAL ESCAPES, the printable ASCII as itself, and everything else as `\uN?` — the reader's own
		 * Unicode control word, with the `?` as the substitution character a parser that cannot do Unicode would take. */
		if (c == '\\' || c == '{' || c == '}') {
			[out appendFormat:@"\\%C", c];
		} else if (c >= 0x20 && c < 0x7F) {
			[out appendFormat:@"%C", c];
		} else {
			[out appendFormat:@"\\u%ld?", (long)(int16_t)c];
		}
	}
	[out appendString:@"}\n"];
	return out;
}

@implementation NSAttributedString (NSAttributedStringKitAdditions)

- (instancetype)initWithRTF:(NSData *)data documentAttributes:(NSDictionary **)dict
{
	NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSMutableString *text;
	NSMutableString *pendingName;
	NSMutableArray *markIndexes;
	NSMutableArray *markAttrs;
	NSMutableArray *fontNames;
	NSMutableArray *colours;
	NSUInteger n, i;
	NSInteger curFont = 0, curFg = 0, curBg = 0;
	CGFloat curSize = 12.0;
	BOOL curUnderline = NO, curStrike = NO;
	NSTextAlignment curAlign = NSLeftTextAlignment;
	NSInteger destination = 0;	/* 0 body, 1 font table, 2 colour table, 3 picture */
	/* **A PICTURE IS A DESTINATION TOO, AND ITS BODY IS HEX RATHER THAN TEXT.** The group's control words say what
	 * kind of blip it is; the hex digits that follow are the image itself, collected here and decoded when the group
	 * closes. A `\pict` this reader cannot decode leaves the text exactly as it was, which is the same boundary the
	 * rest of this codec draws. */
	NSMutableString *pictureHex = nil;
	NSTextAttachment *pendingAttachment = nil;
	NSInteger depth = 0;
	NSInteger destDepth = 0;
	BOOL colourFirst = NO;
	NSInteger pendingFont = -1;
	int pendingR = 0, pendingG = 0, pendingB = 0;

	if (source == nil || [source rangeOfString:@"\\rtf"].location == NSNotFound) {
		/* **A DOCUMENT WITH NO RTF HEADER IS NOT RTF**, and answering nil is how a caller tells. */
		[source release];
		[self release];
		return nil;
	}
	text = [[NSMutableString alloc] init];
	pendingName = [[NSMutableString alloc] init];
	pictureHex = [[NSMutableString alloc] init];
	markIndexes = [[NSMutableArray alloc] init];
	markAttrs = [[NSMutableArray alloc] init];
	fontNames = [[NSMutableArray alloc] init];
	colours = [[NSMutableArray alloc] init];
	/* INDEX 0 OF THE COLOUR TABLE IS RTF'S "auto", so a real colour at RTF index N lives at N here. */
	[colours addObject:[NSNull null]];

	/* THE RUN'S ATTRIBUTES, BUILT FROM THE STATE. A mark is pushed whenever the state changes, so the segments
	 * between marks each get the dictionary in force over them. */
	#define FN_PUSH_MARK() do { \
		NSMutableDictionary *a = [NSMutableDictionary dictionary]; \
		NSFont *f = nil; \
		if (curFont >= 0 && (NSUInteger)curFont < [fontNames count]) { \
			f = [NSFont fontWithName:[fontNames objectAtIndex:curFont] size:curSize]; } \
		/* A FACE THIS TIER CANNOT RESOLVE IS SUBSTITUTED, which is what an RTF reader is supposed to do: the size — the
		 * thing the layout measures with — is kept, and the system font stands in for the named one. */ \
		if (f == nil) { f = [NSFont systemFontOfSize:curSize]; } \
		[a setObject:f forKey:NSFontAttributeName]; \
		if (curFg > 0 && (NSUInteger)curFg < [colours count] && [colours objectAtIndex:curFg] != [NSNull null]) { \
			[a setObject:[colours objectAtIndex:curFg] forKey:NSForegroundColorAttributeName]; } \
		if (curBg > 0 && (NSUInteger)curBg < [colours count] && [colours objectAtIndex:curBg] != [NSNull null]) { \
			[a setObject:[colours objectAtIndex:curBg] forKey:NSBackgroundColorAttributeName]; } \
		if (curUnderline) { [a setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle] forKey:NSUnderlineStyleAttributeName]; } \
		if (curStrike) { [a setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle] forKey:NSStrikethroughStyleAttributeName]; } \
		if (pendingAttachment != nil) { [a setObject:pendingAttachment forKey:NSAttachmentAttributeName]; } \
		if (curAlign != NSLeftTextAlignment) { \
			NSMutableParagraphStyle *ps = [[NSParagraphStyle defaultParagraphStyle] mutableCopy]; \
			[ps setAlignment:curAlign]; \
			[a setObject:ps forKey:NSParagraphStyleAttributeName]; \
			[ps release]; \
		} \
		[markIndexes addObject:[NSNumber numberWithUnsignedInteger:[text length]]]; \
		[markAttrs addObject:a]; \
	} while (0)

	/* THE FIRST MARK IS AT 0, so text before any control word has a run of its own. */
	FN_PUSH_MARK();

	n = [source length];
	for (i = 0; i < n; i++) {
		unichar c = [source characterAtIndex:i];

		if (c == '{') {
			depth++;
			continue;
		}
		if (c == '}') {
			depth--;
			if (destination != 0 && depth < destDepth) {
				if (destination == 3) {
					/* **THE PICTURE IS DECODED HERE, WHERE ITS GROUP ENDS.** The hex becomes bytes, the
					 * bytes become an image through the same decoder `-initWithData:` uses, and the image
					 * becomes an attachment on ONE character: a mark carrying it, the character, and a mark
					 * putting the plain attributes back. A picture this build cannot decode leaves no
					 * character at all, which is better than a U+FFFC that draws nothing. */
					NSMutableData *bytes = [NSMutableData data];
					NSUInteger h = 0;
					BOOL odd = NO;

					(void)odd;
					while (h + 1 < [pictureHex length]) {
						unsigned value = 0;

						if (sscanf([[pictureHex substringWithRange:NSMakeRange(h, 2)] UTF8String], "%2x",
							   &value) == 1) {
							unsigned char byte = (unsigned char)value;

							[bytes appendBytes:&byte length:1];
						}
						h += 2;
					}
					if ([bytes length] > 0) {
						NSImage *image = [[NSImage alloc] initWithData:bytes];

						if (image != nil) {
							NSTextAttachment *attachment = [[NSTextAttachment alloc] init];

							[attachment setImage:image];
							pendingAttachment = attachment;
							FN_PUSH_MARK();
							[text appendFormat:@"%C", (unichar)NSAttachmentCharacter];
							pendingAttachment = nil;
							FN_PUSH_MARK();
							[attachment release];
						} else {
							fprintf(stderr, "APPKIT-REFUSE: -initWithRTF: found a picture this build "
									"cannot decode, and left it out rather than drawing nothing\n");
						}
						[image release];
					}
				}
				destination = 0;	/* the destination's own group closed */
			}
			continue;
		}
		if (c != '\\') {
			/* **RTF's OWN LINE BREAKS ARE INSIGNIFICANT WHITESPACE**, not text: the writer puts `\par` for a break
			 * and a real newline after it for a human reading the bytes, and a reader that took the newline as text
			 * would get two breaks for every one. */
			if (c == '\r' || c == '\n') {
				continue;
			}
			if (destination == 1 && pendingFont >= 0) {
				/* INSIDE A FONT ENTRY: the name runs to the `;`. */
				if (c == ';') {
					while ((NSInteger)[fontNames count] <= pendingFont) {
						[fontNames addObject:@"Times"];
					}
					[fontNames replaceObjectAtIndex:(NSUInteger)pendingFont
						withObject:(([pendingName length] > 0) ? (NSString *)pendingName : (NSString *)@"Times")];
					pendingFont = -1;
					[pendingName setString:@""];
				} else {
					[pendingName appendFormat:@"%C", c];
				}
				continue;
			}
			if (destination == 2 && c == ';') {
				if (colourFirst) {
					colourFirst = NO;	/* the leading `;` IS index 0, the auto colour */
				} else {
					[colours addObject:[NSColor colorWithCalibratedRed:(CGFloat)pendingR / 255.0
						green:(CGFloat)pendingG / 255.0 blue:(CGFloat)pendingB / 255.0 alpha:1.0]];
				}
				continue;
			}
			if (destination == 3) {
				/* THE BODY OF A PICTURE IS HEX DIGITS, and whitespace between them is the writer's formatting. */
				if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
					[pictureHex appendFormat:@"%C", c];
				}
				continue;
			}
			if (destination == 0) {
				[text appendFormat:@"%C", c];
			}
			continue;
		}
		/* A CONTROL WORD OR AN ESCAPE. */
		if (i + 1 < n && ([source characterAtIndex:i + 1] == '\\' || [source characterAtIndex:i + 1] == '{'
				  || [source characterAtIndex:i + 1] == '}')) {
			if (destination == 0) {
				[text appendFormat:@"%C", [source characterAtIndex:i + 1]];
			}
			i++;
			continue;
		}
		if (i + 1 < n && [source characterAtIndex:i + 1] == '\'') {
			unsigned value = 0;
			NSUInteger k;

			for (k = 0; k < 2 && i + 2 + k < n; k++) {
				unichar h = [source characterAtIndex:i + 2 + k];

				value <<= 4;
				if (h >= '0' && h <= '9') value |= (h - '0');
				else if (h >= 'a' && h <= 'f') value |= (h - 'a' + 10);
				else if (h >= 'A' && h <= 'F') value |= (h - 'A' + 10);
			}
			if (destination == 0) {
				[text appendFormat:@"%C", (unichar)value];
			}
			i += 3;
			continue;
		}
		/* THE WORD, ITS PARAMETER, AND THE DELIMITING SPACE. */
		{
			NSUInteger start = i + 1;
			NSUInteger k = start;
			NSInteger param = 0;
			BOOL negative = NO;
			NSString *word;

			while (k < n) {
				unichar w = [source characterAtIndex:k];

				if ((w >= 'a' && w <= 'z') || (w >= 'A' && w <= 'Z')) {
					k++;
				} else {
					break;
				}
			}
			word = [source substringWithRange:NSMakeRange(start, k - start)];
			if (k < n && [source characterAtIndex:k] == '-') {
				negative = YES;
				k++;
			}
			while (k < n) {
				unichar d = [source characterAtIndex:k];

				if (d >= '0' && d <= '9') {
					param = param * 10 + (d - '0');
					k++;
				} else {
					break;
				}
			}
			if (negative) {
				param = -param;
			}
			if (k < n && [source characterAtIndex:k] == ' ') {
				k++;
			}
			i = k - 1;

			if ([word isEqualToString:@"fonttbl"]) {
				destination = 1;
				destDepth = depth;
				pendingFont = -1;
				continue;
			}
			if ([word isEqualToString:@"pict"]) {
				destination = 3;
				destDepth = depth;
				[pictureHex setString:@""];
			} else if ([word isEqualToString:@"colortbl"]) {
				destination = 2;
				destDepth = depth;
				colourFirst = YES;
				continue;
			}
			if (destination == 1) {
				if ([word isEqualToString:@"f"]) {
					pendingFont = param;
				}
				continue;
			}
			if (destination == 2) {
				if ([word isEqualToString:@"red"]) pendingR = (int)param;
				else if ([word isEqualToString:@"green"]) pendingG = (int)param;
				else if ([word isEqualToString:@"blue"]) pendingB = (int)param;
				continue;
			}
			/* THE BODY. */
			if ([word isEqualToString:@"f"]) {
				curFont = param;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"fs"]) {
				curSize = (CGFloat)param / 2.0;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"cf"]) {
				curFg = param;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"highlight"]) {
				curBg = param;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"ul"]) {
				curUnderline = YES;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"ulnone"]) {
				curUnderline = NO;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"strike"]) {
				curStrike = YES;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"strike0"]) {
				curStrike = NO;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"ql"]) {
				curAlign = NSLeftTextAlignment;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"qc"]) {
				curAlign = NSCenterTextAlignment;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"qr"]) {
				curAlign = NSRightTextAlignment;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"qj"]) {
				curAlign = NSJustifiedTextAlignment;
				FN_PUSH_MARK();
			} else if ([word isEqualToString:@"par"] || [word isEqualToString:@"line"]) {
				[text appendString:@"\n"];
			} else if ([word isEqualToString:@"tab"]) {
				[text appendString:@"\t"];
			} else if ([word isEqualToString:@"u"]) {
				[text appendFormat:@"%C", (unichar)(int16_t)param];
				if (i + 1 < n && [source characterAtIndex:i + 1] == '?') {
					i++;
				}
			}
			/* EVERY OTHER CONTROL WORD IS IGNORED, which is the subset boundary this codec draws. */
		}
	}

	/* **AND THE MARKS BECOME RUNS.** The segment from a mark to the next (or to the end) takes that mark's
	 * attributes; a mark with no attributes contributes nothing, which is the plain-text case. */
	{
		NSMutableAttributedString *built = [[NSMutableAttributedString alloc] initWithString:text];
		NSUInteger m;

		for (m = 0; m < [markIndexes count]; m++) {
			NSUInteger from = [[markIndexes objectAtIndex:m] unsignedIntegerValue];
			NSUInteger to = (m + 1 < [markIndexes count])
				? [[markIndexes objectAtIndex:m + 1] unsignedIntegerValue] : [text length];
			NSDictionary *attrs = [markAttrs objectAtIndex:m];

			if (to > from && [attrs count] > 0) {
				[built addAttributes:attrs range:NSMakeRange(from, to - from)];
			}
		}
		if (dict != NULL) {
			*dict = [NSDictionary dictionaryWithObject:@"NSUTF8StringEncoding" forKey:@"CharacterEncoding"];
		}
		self = [self initWithAttributedString:built];
		[built release];
	}

	[colours release];
	[fontNames release];
	[markAttrs release];
	[markIndexes release];
	[pendingName release];
	[text release];
	[source release];
	#undef FN_PUSH_MARK
	return self;
}


/* **AND THE WRITER.** The tables are built in a FIRST pass so every face and colour an index is written for is already
 * declared; the body then walks the string and emits a control word only when the state CHANGES, which is what makes
 * the output small and what the reader's mark mechanism expects. Alignment is a PARAGRAPH property, so it is written
 * where each paragraph starts; every other state is a run's and is written at the character where it changes. The
 * subset is the reader's, which is the point: what this writes, `-initWithRTF:` reads back. */
- (NSData *)RTFRepresentation
{
	NSString *text = fn_rtf_text(self, nil);

	return (text != nil) ? [text dataUsingEncoding:NSUTF8StringEncoding] : nil;
}

@end
