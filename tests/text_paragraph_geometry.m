/*
 * text_paragraph_geometry.m — THE PARAGRAPH STYLE'S GEOMETRY: THE INDENTS, THE SPACINGS AND THE LINE HEIGHTS.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE PROPERTIES THAT WERE CARRIED AND UNREAD ARE READ NOW, AND EACH ONE IS A MEASUREMENT.** The line's x comes from
 * the two head indents, its WIDTH from the tail indent, its HEIGHT from the multiple and the two clamps, and the SPACE
 * between lines from `-lineSpacing` or the two paragraph spacings. The probe reads the manager's own geometry — a
 * fragment's used rect and a glyph's baseline — because that is what the view, the caret and the ink are all placed by.
 *
 * **AND THE DEFAULTS ARE STILL ONE LINE APART.** A store with no paragraph style must lay out exactly as it did before
 * this slice: every indent zero, the natural line height, no gaps. The first case pins that, so the geometry cannot be
 * made right by changing what no style means.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSMutableParagraphStyle *new_style(void)
{
	return [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
}

static void set_text(NSTextStorage *store, NSString *text)
{
	[store replaceCharactersInRange:NSMakeRange(0, [store length]) withString:text];
}

static void apply_style(NSTextStorage *store, NSParagraphStyle *style)
{
	[store addAttribute:NSParagraphStyleAttributeName value:style
		       range:NSMakeRange(0, [[store string] length])];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo\nthree"];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 400.0)];
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	CGFloat base = [font ascender] - [font descender];

	setvbuf(stdout, NULL, _IONBF, 0);
	[store addLayoutManager:manager];
	[manager addTextContainer:container];

	/* 0. **THE DEFAULTS ARE UNMOVED.** */
	{
		NSRect used = [manager usedRectForTextContainer:container];
		CGFloat baseline = [manager cg_baselineForGlyphAtIndex:4];

		printf("  (note: default — used (%g,%g %gx%g), line 1 baseline %g, base line height %g)\n",
		       (double)used.origin.x, (double)used.origin.y, (double)used.size.width, (double)used.size.height,
		       (double)baseline, (double)base);
		check(used.origin.x == 10.0 && fabs(used.size.height - 3.0 * base) < 0.01,
		      "with no style the layout is the old one: padding at x=10 and three natural lines");
		check(fabs(baseline - (base + [font ascender])) < 0.01,
		      "and the second line's baseline is one natural line down");
	}

	/* 1. **AND `-lineSpacing` IS THE GAP BETWEEN LINES OF ONE PARAGRAPH.** A paragraph that WRAPS (so its lines share a
	 * paragraph) gets a gap between each pair; a hard newline is a new paragraph, where the paragraph spacings apply
	 * instead — which is why this case uses a wrapping paragraph rather than three newline-separated ones. */
	{
		NSMutableParagraphStyle *style = new_style();
		NSTextContainer *narrow = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(96.0, 400.0)];
		NSTextStorage *para = [[NSTextStorage alloc] initWithString:@"aaaa bbbb cccc dddd eeee ffff"];
		NSLayoutManager *m = [[NSLayoutManager alloc] init];
		NSUInteger count;
		CGFloat plainHeight, spacedHeight;

		[para addLayoutManager:m];
		[m addTextContainer:narrow];
		count = [m cg_lineFragmentCountForTextContainer:narrow];
		plainHeight = [m usedRectForTextContainer:narrow].size.height;
		[style setLineSpacing:5.0];
		[para addAttribute:NSParagraphStyleAttributeName value:style
			      range:NSMakeRange(0, [[para string] length])];
		spacedHeight = [m usedRectForTextContainer:narrow].size.height;
		printf("  (note: lineSpacing 5 — %lu wrapped lines, height %g against %g plain)\n",
		       (unsigned long)count, (double)spacedHeight, (double)plainHeight);
		check(count > 1 && fabs(spacedHeight - (plainHeight + 5.0 * (CGFloat)(count - 1))) < 0.01,
		      "`-lineSpacing:` adds its gap BETWEEN the lines of one paragraph");
		[style release];
		[narrow release];
		[m release];
		[para release];
	}

	/* 2. **AND THE TWO PARAGRAPH SPACINGS ARE THE GAP ACROSS A PARAGRAPH BOUNDARY.** `one\ntwo`: the second line is a new
	 * paragraph, so the gap above it is `-paragraphSpacing` of the first plus `-paragraphSpacingBefore` of the second. */
	{
		NSMutableParagraphStyle *style = new_style();
		NSRect used;

		[style setParagraphSpacing:6.0];
		[style setParagraphSpacingBefore:4.0];
		apply_style(store, style);
		used = [manager usedRectForTextContainer:container];
		printf("  (note: paragraph 6 + before 4 — used height %g, against %g)\n",
		       (double)used.size.height, (double)(3.0 * base + 20.0));
		check(fabs(used.size.height - (3.0 * base + 20.0)) < 0.01,
		      "the paragraph spacings are added at BOTH boundaries, not once");
		[style release];
		[store removeAttribute:NSParagraphStyleAttributeName range:NSMakeRange(0, [[store string] length])];
	}

	/* 3. **AND THE TWO HEAD INDENTS PLACE THE FIRST LINE AND THE WRAPPED ONES DIFFERENTLY.** A paragraph that wraps: its
	 * first line starts at the FIRST-LINE indent and its continuation at the head indent. */
	{
		NSMutableParagraphStyle *style = new_style();
		NSTextContainer *narrow = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(96.0, 400.0)];
		NSTextStorage *para = [[NSTextStorage alloc] initWithString:@"aaaa bbbb cccc dddd"];
		NSLayoutManager *m = [[NSLayoutManager alloc] init];
		CGFloat firstX, nextX;
		NSUInteger count;

		[para addLayoutManager:m];
		[m addTextContainer:narrow];
		[style setFirstLineHeadIndent:20.0];
		[style setHeadIndent:8.0];
		[para addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [[para string] length])];
		count = [m cg_lineFragmentCountForTextContainer:narrow];
		firstX = [m lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL].origin.x;
		{
			NSRange second = [m cg_lineFragmentRangeAtIndex:1 inTextContainer:narrow];
			NSRect secondUsed = (second.location != NSNotFound && second.length > 0)
				? [m lineFragmentUsedRectForGlyphAtIndex:second.location effectiveRange:NULL] : NSZeroRect;

			nextX = secondUsed.origin.x;
		}
		printf("  (note: first-line indent 20, head indent 8 — line 0 x=%g, line 1 x=%g, %lu lines)\n",
		       (double)firstX, (double)nextX, (unsigned long)count);
		check(fabs(firstX - 30.0) < 0.01, "the FIRST line starts at the padding plus `-firstLineHeadIndent:`");
		check(count > 1 && fabs(nextX - 18.0) < 0.01, "and the wrapped line at the padding plus `-headIndent:`");
		[style release];
		[narrow release];
		[m release];
		[para release];
	}

	/* 4. **AND THE TAIL INDENT NARROWS THE LINE, SO THE SAME PARAGRAPH WRAPS SOONER.** A right inset of 100 leaves
	 * 180 points instead of 280. THE INSET IS 100 RATHER THAN 60 BECAUSE 60 LEFT 220, AND THE PARAGRAPH IS 214
	 * POINTS WIDE IN THE BUNDLED FIGTREE: the old fixture fit by six points and the case became a fact about the
	 * face rather than about the indent. 180 is below every bundled UI face's width for this string. */
	{
		NSMutableParagraphStyle *style = new_style();
		NSTextContainer *wide = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 400.0)];
		NSTextStorage *para = [[NSTextStorage alloc] initWithString:@"aaaa bbbb cccc dddd eeee ffff gggg"];
		NSLayoutManager *m = [[NSLayoutManager alloc] init];
		NSUInteger plainCount, insetCount;

		[para addLayoutManager:m];
		[m addTextContainer:wide];
		plainCount = [m cg_lineFragmentCountForTextContainer:wide];
		[style setTailIndent:100.0];
		[para addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [[para string] length])];
		insetCount = [m cg_lineFragmentCountForTextContainer:wide];
		printf("  (note: tail indent 100 — %lu lines, against %lu with none)\n",
		       (unsigned long)insetCount, (unsigned long)plainCount);
		check(insetCount > plainCount, "`-tailIndent:` takes width off the line, so the paragraph wraps into more lines");
		[style release];
		[wide release];
		[m release];
		[para release];
	}

	/* 5. **AND THE THREE LINE-HEIGHT PROPERTIES: A MULTIPLE SCALES, THE MINIMUM RAISES, THE MAXIMUM LOWERS.** */
	{
		NSMutableParagraphStyle *style = new_style();
		CGFloat multipleHeight, minHeight, maxHeight;

		[store replaceCharactersInRange:NSMakeRange(0, [store length]) withString:@"one"];
		[style setLineHeightMultiple:2.0];
		apply_style(store, style);
		multipleHeight = [manager usedRectForTextContainer:container].size.height;
		[style setLineHeightMultiple:0.0];
		[style setMinimumLineHeight:base + 12.0];
		apply_style(store, style);
		minHeight = [manager usedRectForTextContainer:container].size.height;
		[style setMinimumLineHeight:0.0];
		[style setMaximumLineHeight:base - 4.0];
		apply_style(store, style);
		maxHeight = [manager usedRectForTextContainer:container].size.height;
		printf("  (note: line heights — multiple 2 gave %g, minimum %g gave %g, maximum %g gave %g)\n",
		       (double)multipleHeight, (double)(base + 12.0), (double)minHeight, (double)(base - 4.0), (double)maxHeight);
		check(fabs(multipleHeight - 2.0 * base) < 0.01, "`-lineHeightMultiple:` scales the natural line height");
		check(fabs(minHeight - (base + 12.0)) < 0.01, "`-minimumLineHeight:` raises a shorter line");
		check(fabs(maxHeight - (base - 4.0)) < 0.01, "and `-maximumLineHeight:` lowers a taller one");
		[style release];
		[store removeAttribute:NSParagraphStyleAttributeName range:NSMakeRange(0, [[store string] length])];
	}

	[container release];
	[manager release];
	[store release];
	[pool release];
	printf("text_paragraph_geometry: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
