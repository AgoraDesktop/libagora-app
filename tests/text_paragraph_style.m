/*
 * text_paragraph_style.m — THE PARAGRAPH STYLE: THE VALUE OBJECT, AND THE TWO PROPERTIES THE LAYOUT READS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLASS IS A LEDGER, SO THE FIRST HALF OF THE PROBE READS THE LEDGER.** `+defaultParagraphStyle` answers the
 * era's defaults (natural alignment, word wrapping, zero everywhere else), a `-mutableCopy` of it takes every setter,
 * and a `-copy` of THAT is frozen — the door a builder uses before handing a style to a store.
 *
 * **AND THE SECOND HALF IS THE TWO PROPERTIES WITH READERS.** The ALIGNMENT moves a line inside the width the
 * container gave it, which is why a centred run's first glyph is no longer at the padding; the LINE-BREAK MODE travels
 * into the attributed string the typesetter breaks, so a word-wrapped paragraph ends its first line on a space and a
 * character-wrapped one does not, and a CLIPPED paragraph is one fragment however long it is. The other properties
 * are carried and answered and await their readers, which `NSParagraphStyle.h` names.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextView.h>
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

/* A STORE SET IN ONE PARAGRAPH STYLE, which is the shape the layout reads today. `NSTextStorage` inherits an
 * attributed string, which has no `-setString:` — the whole range is replaced — so that is what this says. */
static void set_store_text(NSTextStorage *store, NSString *text)
{
	[store replaceCharactersInRange:NSMakeRange(0, [store length]) withString:text];
}

static void apply_style(NSTextStorage *store, NSParagraphStyle *style)
{
	[store addAttribute:NSParagraphStyleAttributeName value:style
		       range:NSMakeRange(0, [[store string] length])];
}

static NSMutableParagraphStyle *new_style(void)
{
	return [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"aaaa bbbb cccc dddd"];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(96.0, 400.0)];
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];

	setvbuf(stdout, NULL, _IONBF, 0);
	[store addLayoutManager:manager];
	[manager addTextContainer:container];
	(void)font;

	/* 1. **THE DEFAULT STYLE AND THE COPY THAT CHANGES IT.** */
	{
		NSParagraphStyle *def = [NSParagraphStyle defaultParagraphStyle];
		NSMutableParagraphStyle *mutable;
		NSParagraphStyle *frozen;

		check([def alignment] == NSNaturalTextAlignment && [def lineBreakMode] == NSLineBreakByWordWrapping
		      && [def lineSpacing] == 0.0 && [def firstLineHeadIndent] == 0.0,
		      "the default style is natural-aligned, word-wrapping and zero everywhere");
		mutable = new_style();
		[mutable setAlignment:NSCenterTextAlignment];
		[mutable setLineBreakMode:NSLineBreakByCharWrapping];
		[mutable setLineSpacing:4.0];
		check([mutable alignment] == NSCenterTextAlignment && [mutable lineBreakMode] == NSLineBreakByCharWrapping
		      && [mutable lineSpacing] == 4.0, "a mutable copy takes every setter");
		check([def alignment] == NSNaturalTextAlignment, "and changing the copy leaves the shared DEFAULT alone");
		frozen = [mutable copy];
		check([frozen alignment] == NSCenterTextAlignment && [frozen lineSpacing] == 4.0,
		      "a -copy of the builder is an immutable style carrying what was built");
		check(![frozen isKindOfClass:[NSMutableParagraphStyle class]], "and it is NOT the mutable class");
		[mutable release];
		[frozen release];
	}

	/* 2. **THE ALIGNMENT MOVES THE LINE INSIDE ITS WIDTH.** The first glyph's x is the padding for a left-aligned run
	 * and further right for a centred or right-aligned one, in that order. */
	{
		NSMutableParagraphStyle *style = new_style();
		CGFloat left, centre, right;

		set_store_text(store, @"one");
		[style setAlignment:NSLeftTextAlignment];
		apply_style(store, style);
		left = [manager cg_offsetForGlyphAtIndex:0];
		[style setAlignment:NSCenterTextAlignment];
		apply_style(store, style);
		centre = [manager cg_offsetForGlyphAtIndex:0];
		[style setAlignment:NSRightTextAlignment];
		apply_style(store, style);
		right = [manager cg_offsetForGlyphAtIndex:0];
		printf("  (note: glyph 0's x — left %g, centre %g, right %g)\n", (double)left, (double)centre, (double)right);
		check(fabs(left - 10.0) < 0.01, "a LEFT-aligned line begins at the fragment padding");
		check(centre > left && right > centre, "a centred line is further right, and a right-aligned one further still");
		[style release];
	}

	/* 3. **AND THE LINE-BREAK MODE CHANGES WHERE LINES END.** The same paragraph word-wrapped ends its first line on a
	 * space; character-wrapped fills the width and ends mid-word; and CLIPPED is one fragment however long it is. */
	{
		NSMutableParagraphStyle *style = new_style();
		NSRange wordFirst, charFirst;
		NSUInteger wordCount, charCount, clipCount;
		NSString *string = [store string];
		unichar wordEnd, charEnd;

		set_store_text(store, @"aaaa bbbb cccc dddd");
		string = [store string];		[style setLineBreakMode:NSLineBreakByWordWrapping];
		apply_style(store, style);
		wordCount = [manager cg_lineFragmentCountForTextContainer:container];
		wordFirst = [manager cg_lineFragmentRangeAtIndex:0 inTextContainer:container];
		[style setLineBreakMode:NSLineBreakByCharWrapping];
		apply_style(store, style);
		charCount = [manager cg_lineFragmentCountForTextContainer:container];
		charFirst = [manager cg_lineFragmentRangeAtIndex:0 inTextContainer:container];
		[style setLineBreakMode:NSLineBreakByClipping];
		apply_style(store, style);
		clipCount = [manager cg_lineFragmentCountForTextContainer:container];
		wordEnd = [string characterAtIndex:wordFirst.location + wordFirst.length - 1];
		charEnd = [string characterAtIndex:charFirst.location + charFirst.length - 1];
		printf("  (note: %lu word-wrapped fragments ending `%c`, %lu char-wrapped ending `%c`, %lu clipped)\n",
		       (unsigned long)wordCount, (char)wordEnd, (unsigned long)charCount, (char)charEnd,
		       (unsigned long)clipCount);
		check(wordEnd == ' ', "WORD wrapping backs off to the space it fitted and ends the line there");
		check(charEnd != ' ', "CHARACTER wrapping fills the width and ends mid-word");
		check(charFirst.length >= wordFirst.length,
		      "so a character-wrapped line holds at least as much as a word-wrapped one");
		check(clipCount == 1, "and CLIPPING does not wrap at all — one fragment for the paragraph");
		[style release];
	}

	/* 4. **AND THE VIEW'S ALIGNMENT IS THE STORE'S PARAGRAPH STYLE.** Setting it on the view puts a style in the store
	 * and reading it back answers the same, which retires the base class's "stored and does not move the glyphs". */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 60.0)];
		id inStore;

		[view setString:@"one\ntwo"];
		[view setAlignment:NSCenterTextAlignment];
		inStore = [[[view textStorage] attributesAtIndex:0 effectiveRange:NULL]
				objectForKey:NSParagraphStyleAttributeName];
		check(inStore != nil && [inStore alignment] == NSCenterTextAlignment,
		      "`-setAlignment:` on the view writes a paragraph style into the store");
		check([view alignment] == NSCenterTextAlignment, "and `-alignment` reads it back from the store");
		[view alignRight:nil];
		check([view alignment] == NSRightTextAlignment,
		      "and `-alignRight:` — a PARAGRAPH command — is the same door by another name");
		[view alignJustified:nil];
		check([view alignment] == NSJustifiedTextAlignment, "as is `-alignJustified:`");
		[view release];
	}

	[container release];
	[manager release];
	[store release];
	[pool release];
	printf("text_paragraph_style: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
