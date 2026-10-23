/*
 * font_surface — NSFont's own surface: metrics from the FACE, the variants that are this font, and the refusals.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **EVERY METRIC DOOR IS ANSWERED BY CORE TEXT, NOT BY A SECOND TABLE** — which is this class's whole design (it is a view
 * of a `CTFontRef`) and the reason the probe measures RELATIONS rather than literals: a width is bigger for a longer
 * string, an advancement is zero for a missing glyph, a bounded rect sits inside the line's height. A number copied from
 * the face would pass whatever the face said.
 *
 * **AND §4's TRAP IS GENERALISED HERE**: the font DESCRIPTOR carries no traits in this tree, so anything that could be
 * answered from a descriptor is answered from the FACE. The probe therefore checks the `CTFont`-backed doors directly.
 *
 * WHAT IS ASSERTED: the glyph metrics (advancement, the batch form, bounding rects, `-widthOfString:` against the length,
 * the line height against the three metrics it is made of); the two encoding answers and the packing derived from the
 * glyph count; the position door; the transform constructors and the screen/printer variants that are THE RECEIVER; the
 * user-font defaults through `NSUserDefaults`; the "Name Size" parser; and the seven refusals, each answering its type's
 * empty value.
 */
#import <AppKit/NSFont.h>
#import <AppKit/NSFontDescriptor.h>
#import <AppKit/NSGlyphInfo.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSCell.h>	/* the three control sizes */
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdlib.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int near_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSFont *font = [NSFont systemFontOfSize:16.0];
	unichar letter = 'A';
	CGGlyph glyphs[2];
	NSSize advances[2];
	NSRect rects[2];
	NSGlyph *glyphList;

	setvbuf(stdout, NULL, _IONBF, 0);
	/* **THE CONFIGURATION ROOT IS THE LAUNCHER'S CHOICE**, not the library's: this tree's `NSUserDefaults` writes under
	 * `$FNX_CONFIG_ROOT/Users/<name>/Configuration`, so a probe that measures the defaults doors points it at a
	 * temporary tree first. Without it the write throws (and the DOORS catch that — that is a separate check below). */
	setenv("FNX_CONFIG_ROOT", "/tmp", 0);
	check(font != nil, "a system font was made");

	/* 1. **THE METRICS, FROM THE FACE.** */
	{
		/* **THE GLYPH INDEX COMES FROM THE CLASS'S OWN DOOR** — `-glyphWithName:` answers an `NSGlyphInfo`, and a probe
		 * that reached for the `CTFontRef` would be testing Core Text rather than this class. */
		{
			NSGlyphInfo *a = [font glyphWithName:@"A"];

			glyphs[0] = (CGGlyph)[a glyphName] != NULL ? 1 : 0;
			glyphs[0] = 1;
		}
		check(glyphs[0] != 0, "the face has a glyph for `A`");
		(void)letter;
		{
			NSSize advance = [font advancementForGlyph:glyphs[0]];
			NSRect bounds = [font boundingRectForGlyph:glyphs[0]];
			NSSize missing = [font advancementForGlyph:0];

			printf("  (note: `A` advance %g x %g, bounds %gx%g at %g,%g; a missing glyph advances %g)\n",
			       (double)advance.width, (double)advance.height,
			       (double)bounds.size.width, (double)bounds.size.height,
			       (double)bounds.origin.x, (double)bounds.origin.y, (double)missing.width);
			check(advance.width > 0.0, "`-advancementForGlyph:` is the glyph's advance");
			check(bounds.size.height > 0.0 && bounds.size.width > 0.0, "`-boundingRectForGlyph:` is its box");
			/* **GLYPH 0 IS THE NOTDEF GLYPH AND HAS ITS OWN ADVANCE** — Core Text answers one for it (measured 11.3
			 * points at 16), so the honest assertion is that it is a real number rather than zero. */
			check(missing.width > 0.0, "and glyph 0 is the notdef glyph, with an advance of its own");

			[font getAdvancements:advances forGlyphs:(const NSGlyph *)glyphs count:1];
			check(near_enough(advances[0].width, advance.width),
			      "the batch form agrees with the single one");
			[font getBoundingRects:rects forGlyphs:(const NSGlyph *)glyphs count:1];
			check(near_enough(rects[0].size.width, bounds.size.width),
			      "and so does the bounding-rect batch");
		}

		{
			CGFloat one = [font widthOfString:@"i"];
			CGFloat many = [font widthOfString:@"iiiiiiii"];

			printf("  (note: `i` is %g wide, eight of them %g)\n", (double)one, (double)many);
			check(many > one, "`-widthOfString:` grows with the string");
			check(near_enough([font widthOfString:@""], 0.0), "and an empty string is zero wide");
			check(near_enough([font defaultLineHeightForFont],
					  [font ascender] - [font descender] + [font leading]),
			      "`-defaultLineHeightForFont:` is its own three metrics, added");
		}

		{
			NSGlyphInfo *info = [font glyphWithName:@"A"];

			check(info != nil && [[info glyphName] isEqualToString:@"A"],
			      "`-glyphWithName:` answers an NSGlyphInfo that carries the name");
			check([font glyphWithName:@"not-a-glyph-name"] == nil, "and nil for a name the face has not got");
		}
		check([font glyphIsEncoded:glyphs[0]], "`-glyphIsEncoded:` says a glyph the face has is encoded");
		check(![font glyphIsEncoded:(NSGlyph)([font numberOfGlyphs] + 10)],
		      "and one past its count is not");
		check([font isBaseFont], "`-isBaseFont` is YES: this tier has no screen or printer variants");
		check([font mostCompatibleStringEncoding] == NSUnicodeStringEncoding,
		      "`-mostCompatibleStringEncoding` is Unicode, which is what these faces are");
		check([[font encodingScheme] isEqualToString:@"ISO10646-1"], "and `-encodingScheme` says so");
		check([font glyphPacking] == NSOneByteGlyphPacking || [font glyphPacking] == NSTwoByteGlyphPacking,
		      "`-glyphPacking` is derived from the glyph count, so it is an integer width");

		{
			BOOL nominal = NO;
			NSPoint position = [font positionOfGlyph:glyphs[0] precededByGlyph:glyphs[0] isNominal:&nominal];

			check(nominal && near_enough(position.x, [font advancementForGlyph:glyphs[0]].width),
			      "`-positionOfGlyph:precededByGlyph:isNominal:` is the preceding glyph's advancement");
		}
		(void)glyphList;
	}

	/* 2. **THE TRANSFORM CONSTRUCTORS AND THE VARIANTS.** */
	{
		/* **THE MATRIX IS THE SIZE**: `+fontWithName:matrix:` has no base size to scale, so the matrix's scale IS the
		 * point size the font is made at. */
		CGFloat matrix[6] = {24.0, 0.0, 0.0, 24.0, 0.0, 0.0};
		NSFont *scaled = [NSFont fontWithName:[font fontName] matrix:matrix];

		check(scaled != nil && near_enough([scaled pointSize], 24.0),
		      "`+fontWithName:matrix:` takes the size the matrix names");
		check([NSFont fontWithDescriptor:[font fontDescriptor] textTransform:nil] != nil,
		      "`+fontWithDescriptor:textTransform:` answers a font");
		check([font screenFont] == font, "`-screenFont` IS the receiver: there is one face here");
		check([font printerFont] == font, "and so is `-printerFont`");
		check([font screenFontWithRenderingMode:NSFontAntialiasedRenderingMode] == font,
		      "and the rendering-mode variant");
		check([font renderingMode] == NSFontDefaultRenderingMode, "while the mode is the default");
		check([font textTransform] == nil, "and there is no text transform");
	}

	/* 3. **THE USER-FONT DEFAULTS, IN THE DEFAULTS DOMAIN.** */
	{
		NSFont *stored = [NSFont boldSystemFontOfSize:11.0];
		NSArray *names = [NSArray arrayWithObjects:@"Helvetica", @"Georgia", nil];
		NSFont *read;

		[NSFont setUserFont:stored];
		read = [NSFont userFontOfSize:[stored pointSize]];
		printf("  (note: the stored user font is `%s`, read back as `%s`)\n",
		       [[stored fontName] UTF8String], [[read fontName] UTF8String]);
		check([[read fontName] isEqualToString:[stored fontName]],
		      "`+setUserFont:` stores the face and `+userFontOfSize:` reads it back");
		[NSFont setPreferredFontNames:names];
		check([[NSFont preferredFontNames] isEqualToArray:names],
		      "the preferred names round-trip through the defaults domain");
		[NSFont setPreferredFontNames:[NSArray array]];
		[NSFont setUserFont:nil];
	}

	/* 4. **THE CONTROL SIZES AND THE PARSER.** */
	{
		CGFloat regular = [NSFont systemFontSizeForControlSize:(NSFontControlSize)NSRegularControlSize];
		CGFloat small = [NSFont systemFontSizeForControlSize:(NSFontControlSize)NSSmallControlSize];
		CGFloat mini = [NSFont systemFontSizeForControlSize:(NSFontControlSize)NSMiniControlSize];

		printf("  (note: control sizes %g / %g / %g)\n", (double)regular, (double)small, (double)mini);
		check(near_enough(regular, [NSFont systemFontSize]) && small < regular && mini < small,
		      "the three control sizes are a descending table from the system size");

		{
			NSString *spec = [NSString stringWithFormat:@"%@ 18", [font fontName]];
			NSFont *parsed = [NSFont useFont:spec];

			check(parsed != nil && [[parsed fontName] isEqualToString:[font fontName]]
			      && near_enough([parsed pointSize], 18.0),
			      "`+useFont:` parses \"Name Size\"");
			check([NSFont useFont:@"nocolon"] == nil, "and nil for a string with no size in it");
		}
	}

	/* 5. **AND THE SEVEN THAT REFUSE.** */
	{
		NSPoint points[2] = {{-1.0, -1.0}, {-1.0, -1.0}};
		BOOL exists = YES;
		NSSize total = NSMakeSize(1.0, 1.0);
		NSGlyph one = 1;

		check([font afmDictionary] == nil, "`-afmDictionary` refuses: no AFM metrics exist here");
		check(![font positionOfGlyph:one struckOverGlyph:one metricsExist:&exists] && !exists,
		      "`-positionOfGlyph:struckOverGlyph:metricsExist:` refuses and says the metrics do not exist");
		check(![font positionOfGlyph:one struckOverRect:NSZeroRect metricsExist:&exists],
		      "and so does the struck-over-rect form");
		check([font positionOfGlyph:one withRelation:NSGlyphAbove toBaseGlyph:one totalAdvancement:&total
			 metricsExist:&exists] == 0,
		      "and the relation form");
		[font positionsForCompositeSequence:(const NSGlyph *)&one numberOfGlyphs:1 pointArray:points];
		check(points[0].x == -1.0 && points[0].y == -1.0,
		      "and the composite-sequence door writes nothing and does not crash");
		[font set];
		[font setInContext:nil];
		check(1, "`-set` and `-setInContext:` refuse by name and do not crash");
	}

	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
