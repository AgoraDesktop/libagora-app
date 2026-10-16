/*
 * text_writing_direction.m — THE BASE DIRECTION DECIDES WHAT "NATURAL" ALIGNMENT MEANS.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **`NSNaturalTextAlignment` IS NOT AN EDGE, IT IS A QUESTION, AND THE BASE DIRECTION IS THE ANSWER.** A left-to-right
 * paragraph aligns natural text LEFT and a right-to-left one aligns it RIGHT, so the layout manager resolves the one
 * through the other; the three EXPLICIT alignments are untouched. The probe reads the line's used rect: a natural
 * paragraph in a right-to-left direction ends at the container's RIGHT edge, which is the whole of the claim.
 *
 * **AND THE DIRECTION A LANGUAGE DEFAULTS TO IS `NSLocale`'s.** `+defaultWritingDirectionForLanguage:` asks ICU through
 * the locale — "ar" and "he" answer right-to-left, "en" left-to-right — so a caller can resolve a natural direction
 * before setting one.
 *
 * **WHAT IS NOT TESTED HERE IS GLYPH REORDERING.** The tier's Core Text reads no writing direction, so a right-to-left
 * SCRIPT is not reordered; that is the engine's, and it is named at the door rather than pretended.
 */
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSText.h>
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

/* THE LINE'S USED RECT FOR A STYLE, which is where the alignment shows: its x is the leading edge plus the alignment's
 * offset, and its right edge is the trailing edge when the line is flush right. */
static NSRect used_rect_for_style(NSParagraphStyle *style, NSString *text)
{
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:text];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 100.0)];
	NSRect used;

	[container setLineFragmentPadding:10.0];
	[store addLayoutManager:manager];
	[manager addTextContainer:container];
	[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [store length])];
	used = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
	[container release];
	[manager release];
	[store release];
	return used;
}

static NSMutableParagraphStyle *style_with(NSWritingDirection direction, NSTextAlignment alignment)
{
	NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];

	[style setBaseWritingDirection:direction];
	[style setAlignment:alignment];
	return style;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE LANGUAGE'S DIRECTION COMES FROM THE LOCALE.** */
	{
		NSWritingDirection fromNil = [NSParagraphStyle defaultWritingDirectionForLanguage:nil];
		NSWritingDirection fromLocale =
			[NSParagraphStyle defaultWritingDirectionForLanguage:[[NSLocale currentLocale] languageCode]];

		printf("  (note: ar -> %d, he -> %d, en -> %d)\n",
		       (int)[NSParagraphStyle defaultWritingDirectionForLanguage:@"ar"],
		       (int)[NSParagraphStyle defaultWritingDirectionForLanguage:@"he"],
		       (int)[NSParagraphStyle defaultWritingDirectionForLanguage:@"en"]);
		check([NSParagraphStyle defaultWritingDirectionForLanguage:@"ar"] == NSWritingDirectionRightToLeft
		      && [NSParagraphStyle defaultWritingDirectionForLanguage:@"he"] == NSWritingDirectionRightToLeft,
		      "a right-to-left language answers right-to-left");
		check([NSParagraphStyle defaultWritingDirectionForLanguage:@"en"] == NSWritingDirectionLeftToRight
		      && [NSParagraphStyle defaultWritingDirectionForLanguage:@"fr"] == NSWritingDirectionLeftToRight,
		      "and a left-to-right one answers left-to-right");
		check(fromNil == fromLocale, "a nil language asks the CURRENT locale's language");
	}

	/* 2. **AND IT DECIDES WHAT NATURAL ALIGNMENT MEANS.** */
	{
		NSString *text = @"abc";
		NSRect ltr;			/* natural, left-to-right: the default shape */
		NSRect rtl;			/* natural, right-to-left: natural becomes RIGHT */
		NSRect rtlExplicitLeft;		/* an EXPLICIT left is not moved by the direction */
		NSRect ltrExplicitRight;
		NSMutableParagraphStyle *style;

		style = style_with(NSWritingDirectionNatural, NSNaturalTextAlignment);
		ltr = used_rect_for_style(style, text);
		[style release];

		style = style_with(NSWritingDirectionRightToLeft, NSNaturalTextAlignment);
		rtl = used_rect_for_style(style, text);
		[style release];

		style = style_with(NSWritingDirectionRightToLeft, NSLeftTextAlignment);
		rtlExplicitLeft = used_rect_for_style(style, text);
		[style release];

		style = style_with(NSWritingDirectionLeftToRight, NSRightTextAlignment);
		ltrExplicitRight = used_rect_for_style(style, text);
		[style release];

		printf("  (note: used rects — LTR natural x=%.2f, RTL natural right=%.2f, RTL explicit-left x=%.2f)\n",
		       (double)ltr.origin.x, (double)(rtl.origin.x + rtl.size.width), (double)rtlExplicitLeft.origin.x);
		check(fabs(ltr.origin.x - 10.0) < 0.01,
		      "a natural paragraph read left-to-right begins at the leading edge");
		check(fabs((rtl.origin.x + rtl.size.width) - 290.0) < 0.01,
		      "and a natural paragraph read right-to-left ENDS at the trailing edge");
		check(fabs(rtlExplicitLeft.origin.x - 10.0) < 0.01,
		      "an EXPLICIT left alignment is not moved by the direction");
		check(fabs((ltrExplicitRight.origin.x + ltrExplicitRight.size.width) - 290.0) < 0.01,
		      "and an explicit right still ends at the trailing edge");
	}

	[pool release];
	printf("text_writing_direction: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
