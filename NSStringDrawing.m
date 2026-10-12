/*
 * NSStringDrawing.m — the ink layer: a string, a point or a rectangle, and Core Text underneath.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS FILE IS WHERE THE SUBSTRATE MEETS THE SURFACE, AND THE MEETING COSTS ONE TRANSLATION — WHICH IS THE COST
 * OF `dec-7dca575a46b17524` MADE MEASURABLE.** `CTLineCreateWithAttributedString` reads the font out of the
 * attributes with a raw cast:
 *
 *     CTFontRef font = (CTFontRef)[attributes objectForKey:kCTFontAttributeName];      (CTLine.m:389)
 *
 * In Apple's world that cast is sound because `NSFont` and `CTFont` are TOLL-FREE BRIDGED — one object answers to
 * both names. **IN THIS TIER THEY ARE NOT**: §A10bu measured that the era declares no CT type on `NSFont`, so
 * `NSFont` is a WRAPPER holding a private `CTFontRef`, and handing Core Text an `NSFont` is handing it a pointer
 * it cannot use. The first draft of this file did exactly that, and the probe's verdict was total: the measuring
 * door answered a size of ZERO and a direct `CTLineDraw` put down no ink at all, because a line with no usable
 * font is refused before anything is drawn.
 *
 * **SO THE TRANSLATION BELOW IS THE WHOLE REASON THIS FILE SITS BETWEEN TWO WORLDS**: an AppKit attributes
 * dictionary becomes a Core Text one (`NSFontAttributeName` → `kCTFontAttributeName`, carrying the font's own
 * substrate), and the colour does NOT travel in the dictionary at all — Core Text draws in the context's fill
 * colour, so the colour is applied to the CONTEXT, which is also Apple's behaviour.
 *
 * **SIX DOORS, TWO ENGINES, ONE DEFAULT.** The single-line doors are one `CTLine`; the rectangle doors are a
 * `CTFramesetter` in a path, which is what makes `-drawInRect:` WRAP. Both take the same translated attributes,
 * so a single line and a wrapped block cannot disagree about the font.
 */
#import "NSStringDrawing.h"

#import "NSColor.h"
#import "NSFont.h"
#import "NSGraphicsContext.h"

#include <CoreGraphics/CGContext.h>
#include <CoreGraphics/CGPath.h>
#include <CoreText/CTFramesetter.h>
#include <CoreText/CTLine.h>
#include <CoreText/CTStringAttributes.h>

/* **THE DIVERGENT DEFAULT, IN ONE PLACE**: "Helvetica 12" is Apple's sentence and this tier has one system font,
 * so the default is that font at the same size. Retained once — it is a font object, not a measurement. */
static NSFont *apk_default_font(void)
{
	static NSFont *font = nil;

	if (font == nil) {
		font = [[NSFont systemFontOfSize:(CGFloat)12.0] retain];
	}
	return font;
}

/* **THE STRING'S OWN ATTRIBUTES, ASKED THROUGH THE DOOR APPLE ACTUALLY HAS.** The first draft of this file asked
 * for `-attributes`, which is not an `NSAttributedString` door at all — the tree's Foundation raised
 * `is not implemented` when the probe drew an attributed string, which is how an invented accessor announces
 * itself. `-attributesAtIndex:effectiveRange:` is the real one, and an EMPTY string has no index to ask about, so
 * the empty case answers an empty dictionary rather than raising. */
static NSDictionary *apk_attributes_of(NSAttributedString *string)
{
	if ([string length] == 0) {
		return [NSDictionary dictionary];
	}
	return [string attributesAtIndex:0 effectiveRange:NULL];
}

/* THE ATTRIBUTES A DRAW ACTUALLY USES: the caller's, with this tier's default font filled in when none was
 * named. Still AppKit's vocabulary — the translation below happens separately, so the two questions stay apart. */
static NSDictionary *apk_effective_attributes(NSDictionary *attrs)
{
	NSMutableDictionary *effective;

	if (attrs != nil && [attrs objectForKey:NSFontAttributeName] != nil) {
		return attrs;
	}
	/* THE CAST IS THE TREE'S OWN TYPING, NOT AN OVERSIGHT: `+dictionaryWithDictionary:` answers an
	 * `NSDictionary *` here even though it is a mutable one, so a caller that means to set keys must say so. */
	effective = (NSMutableDictionary *)[NSMutableDictionary dictionaryWithDictionary:
		(attrs == nil ? [NSDictionary dictionary] : attrs)];
	/* **AND A FONT THAT IS NOT THERE IS NOT INSERTED — WHICH IS THE WHOLE DEFECT, IN ONE LINE.** `-setObject:`
	 * raises on a nil value, and `+[NSFont systemFontOfSize:]` ANSWERS NIL IN THIS TREE (measured, not inferred),
	 * so every call to `-sizeWithAttributes:` died inside this dictionary insertion instead of measuring a string.
	 * Apple's contract for these three doors ALLOWS a nil attributes dictionary, and a caller that names no font
	 * gets the default — so when the default is missing the answer is NO FONT ATTRIBUTE, which Core Text fills
	 * with its own default, rather than an exception. A door that raises where the API it clones permits a call is
	 * not a refusal by name; it is a crash with a good excuse.
	 *
	 * **THE ROOT CAUSE IS STILL OWED AND IS NARROW: `+[NSFont systemFontOfSize:]` RETURNS NIL.** That is a FONT
	 * SERVICE problem rather than a drawing one — the face lookup has nothing to answer with on this host — and it
	 * belongs to `NSFont`'s row. What THIS file owes is staying usable while it is true. */
	{
		NSFont *font = apk_default_font();

		if (font != nil) {
			[effective setObject:font forKey:NSFontAttributeName];
		}
	}
	return effective;
}

/* **THE TRANSLATION, AND THE ONE LINE OF IT THAT MATTERS**: Core Text wants a `CTFont` under its own key, so the
 * `NSFont` the caller named is unwrapped to the substrate it holds (`NSFont.h`'s `@public` ivar, which exists for
 * this library's own code — the rule `CTRun.h` states for its arrays). Keys the caller set that Core Text does
 * not know are NOT passed on: Core Text would ignore them, and a dictionary mixing two vocabularies is harder to
 * reason about than one that does not. */
static NSAttributedString *apk_core_text_string(NSString *characters, NSDictionary *effective)
{
	NSFont *font = [effective objectForKey:NSFontAttributeName];
	CFMutableDictionaryRef attributes;
	CFAttributedStringRef s;

	attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	if (font != nil) {
		CFDictionarySetValue(attributes, kCTFontAttributeName, font->_font);
	}
	s = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)characters, attributes);
	CFRelease(attributes);
	return [(NSAttributedString *)s autorelease];
}

/* **A DRAW WITH NO CONTEXT DRAWS NOTHING, AND THAT IS THE ANSWER RATHER THAN A CRASH** — Apple's own behaviour
 * for a draw outside a drawing context, and the reason every door below returns early instead of asserting. */
static CGContextRef apk_current_context(void)
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];

	return context == nil ? NULL : (CGContextRef)[context graphicsPort];
}

static void apk_apply_colour(NSDictionary *attrs, CGContextRef ctx)
{
	NSColor *colour = [attrs objectForKey:NSForegroundColorAttributeName];

	if (colour != nil) {
		CGContextSetFillColorWithColor(ctx, [colour CGColor]);
	}
}

/* ONE LINE AT A BASELINE ORIGIN, which is Core Text's own meaning of a text position — and the fill colour is
 * scoped by a save/restore, so **a drawing door does not leak its colour into the caller's graphics state**. */
static void apk_draw_line(NSAttributedString *ctString, NSDictionary *effective, CGContextRef ctx, NSPoint point)
{
	CTLineRef line = CTLineCreateWithAttributedString(ctString);

	if (line == NULL) {
		return;
	}
	CGContextSaveGState(ctx);
	apk_apply_colour(effective, ctx);
	CGContextSetTextPosition(ctx, point.x, point.y);
	CTLineDraw(line, ctx);
	CGContextRestoreGState(ctx);
	CFRelease(line);
}

static NSSize apk_size_of_line(NSAttributedString *ctString)
{
	CTLineRef line = CTLineCreateWithAttributedString(ctString);
	CGFloat ascent = 0.0, descent = 0.0, leading = 0.0;
	double width;
	NSSize size = { 0.0, 0.0 };

	if (line == NULL) {
		return size;
	}
	/* **THE TYPOGRAPHIC BOUNDS, WHICH ARE THE LINE'S OWN ANSWER**: the advance for the width and the three
	 * vertical metrics for the height, which is what a caller reserving room for one line needs. */
	width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
	CFRelease(line);
	size.width = (CGFloat)width;
	size.height = ascent + descent + leading;
	return size;
}

static void apk_draw_in_rect(NSAttributedString *ctString, NSDictionary *effective, CGContextRef ctx, NSRect rect)
{
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(ctString);
	CGPathRef path;
	CTFrameRef frame;

	if (framesetter == NULL) {
		return;
	}
	CGContextSaveGState(ctx);
	apk_apply_colour(effective, ctx);
	/* **THE RECT PATH IS FOUR LINES OVER `CGPathAddRect`, WHICH IS WHAT `CGPath.h` PRESCRIBES**: the one-shot
	 * `CGPathCreateWithRect` is macOS 10.7 and was deliberately removed from this tree as out of era, and its own
	 * note says how to spell it instead. */
	path = CGPathCreateMutable();
	if (path != NULL) {
		CGPathAddRect((CGMutablePathRef)path, NULL, rect);
	}
	/* **THE RANGE IS THE WHOLE STRING, SPELLED OUT, BECAUSE THIS ENGINE TAKES IT LITERALLY.** The first version
	 * passed `NSMakeRange(0, 0)` on the belief that a zero-length range means "the whole string" — an assumption,
	 * not a contract — and the framesetter's own arithmetic says otherwise:
	 *
	 *     start = stringRange.location;  end = stringRange.location + stringRange.length;   (CTFramesetter.m:226)
	 *
	 * With both ends at zero there is no text to lay out, so it answered a frame with ZERO LINES, and the probe's
	 * control (Core Text's own string, Core Text's own keys, straight through the framesetter) reproduced it — so
	 * the fault was never the door. The explicit range is unambiguous under either reading. */
	frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, [ctString length]), path, NULL);
	if (frame != NULL) {
		CTFrameDraw(frame, ctx);
		CFRelease(frame);
	}
	if (path != NULL) {
		CGPathRelease(path);
	}
	CGContextRestoreGState(ctx);
	CFRelease(framesetter);
}

@implementation NSString (NSStringDrawing)

- (NSSize)sizeWithAttributes:(NSDictionary *)attrs
{
	return apk_size_of_line(apk_core_text_string(self, apk_effective_attributes(attrs)));
}

- (void)drawAtPoint:(NSPoint)point withAttributes:(NSDictionary *)attrs
{
	CGContextRef ctx = apk_current_context();
	NSDictionary *effective = apk_effective_attributes(attrs);

	if (ctx != NULL) {
		apk_draw_line(apk_core_text_string(self, effective), effective, ctx, point);
	}
}

- (void)drawInRect:(NSRect)rect withAttributes:(NSDictionary *)attrs
{
	CGContextRef ctx = apk_current_context();
	NSDictionary *effective = apk_effective_attributes(attrs);

	if (ctx != NULL) {
		apk_draw_in_rect(apk_core_text_string(self, effective), effective, ctx, rect);
	}
}

@end

@implementation NSAttributedString (NSStringDrawing)

/* THE STRING'S OWN ATTRIBUTES, SO THE ONLY DEFAULT THAT CAN APPLY IS THE FONT ONE — and an attributed string
 * built by a caller who named no font gets this tier's default at 12 points rather than nothing at all. */
- (NSSize)size
{
	return apk_size_of_line(apk_core_text_string([self string],
						    apk_effective_attributes(apk_attributes_of(self))));
}

- (void)drawAtPoint:(NSPoint)point
{
	CGContextRef ctx = apk_current_context();
	NSDictionary *effective = apk_effective_attributes(apk_attributes_of(self));

	if (ctx != NULL) {
		apk_draw_line(apk_core_text_string([self string], effective), effective, ctx, point);
	}
}

- (void)drawInRect:(NSRect)rect
{
	CGContextRef ctx = apk_current_context();
	NSDictionary *effective = apk_effective_attributes(apk_attributes_of(self));

	if (ctx != NULL) {
		apk_draw_in_rect(apk_core_text_string([self string], effective), effective, ctx, rect);
	}
}

@end
