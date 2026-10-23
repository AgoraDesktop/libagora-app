/*
 * text_surface — NSText's own era surface: the run, the resizability, the RTF pair and the spelling check.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A FIELD HAS ONE RUN, AND MOST OF THIS SLICE IS ABOUT SAYING SO HONESTLY.** `-textColor`/`-setTextColor:` are the ink
 * the string is drawn in; the two RANGE doors set that same one run rather than pretending to a store. The RTF pair
 * carries the run out and takes only the CHARACTERS back, because a bold word pasted into a plain field would be bold on
 * screen and plain on the next keystroke. The resizability flags are read where they mean something — a resizable field
 * re-fits after every edit — and the limits clamp it. The spelling check is real and selects the first misspelling; the
 * panel it would be shown in refuses by name, with the four run commands beside it.
 */
#import <AppKit/NSText.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSSpellChecker.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <Foundation/Foundation.h>

#include <math.h>
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
	NSText *field = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
	NSFont *font = [NSFont systemFontOfSize:13.0];

	setvbuf(stdout, NULL, _IONBF, 0);
	[field setFont:font];
	[field setString:@"hello world"];

	/* 1. **THE INK, AND THE RANGE THAT IS THE WHOLE RUN.** */
	{
		NSColor *red = [NSColor redColor];

		check([field textColor] == nil, "a field has no text colour of its own until one is set");
		[field setTextColor:red];
		check([field textColor] == red, "`-setTextColor:` is what `-textColor` answers");
		[field setTextColor:[NSColor blueColor] range:NSMakeRange(0, 5)];
		check([[field textColor] isEqual:[NSColor blueColor]],
		      "a RANGE sets the one run this class has, which is what the header says it does");
		[field setFont:[NSFont boldSystemFontOfSize:13.0] range:NSMakeRange(6, 5)];
		check([[field font] isEqual:[NSFont boldSystemFontOfSize:13.0]], "and so does `-setFont:range:`");
		[field setFont:font];
	}

	/* 2. **THE DIRECTION IS READ BY THE DRAWING.** */
	{
		check([field baseWritingDirection] == NSWritingDirectionNatural, "a field's direction is natural to start");
		[field setBaseWritingDirection:NSWritingDirectionRightToLeft];
		check([field baseWritingDirection] == NSWritingDirectionRightToLeft, "and setting it is answered back");
		[field setBaseWritingDirection:NSWritingDirectionNatural];
	}

	/* 3. **THE RESIZABILITY IS READ BY THE EDIT PATH, AND THE LIMITS CLAMP.** */
	{
		CGFloat before;

		[field setString:@"short"];
		[field sizeToFit];
		before = [field frame].size.width;
		[field setString:@"a much longer string than before"];
		check(near_enough([field frame].size.width, before),
		      "a field with the flags OFF keeps its width after an edit");

		[field setHorizontallyResizable:YES];
		[field setString:@"a much longer string than before"];
		printf("  (note: resizable width %g, fixed width %g)\n",
		       (double)[field frame].size.width, (double)before);
		check([field frame].size.width > before,
		      "and with `-setHorizontallyResizable:YES` the same edit WIDENS it");
		check([field isHorizontallyResizable], "the flag answers itself");

		[field setMaxSize:NSMakeSize(before + 10.0, 0.0)];
		[field setString:@"an even longer string that would go past the limit"];
		check(near_enough([field frame].size.width, before + 10.0),
		      "while `-maxSize` clamps what the fitting may reach");
		[field setMaxSize:NSZeroSize];
		[field setMinSize:NSMakeSize(400.0, 0.0)];
		[field setString:@"x"];
		check(near_enough([field frame].size.width, 400.0), "and `-minSize` is a floor");
		[field setMinSize:NSZeroSize];
		[field setHorizontallyResizable:NO];
		check(![field isVerticallyResizable], "a field is not vertically resizable unless told");
		[field setVerticallyResizable:YES];
		check([field isVerticallyResizable], "and setting that flag answers itself");
		[field setVerticallyResizable:NO];
	}

	/* 4. **THE RTF ROUND TRIP.** */
	{
		NSData *rtf = [field RTFFromRange:NSMakeRange(0, [[field string] length])];

		check(rtf != nil && [rtf length] > 0, "`-RTFFromRange:` produces RTF for the range");
		if (rtf != nil) {
			NSText *other = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];

			[other setFont:font];
			[other setString:@""];
			[other replaceCharactersInRange:NSMakeRange(0, 0) withRTF:rtf];
			printf("  (note: the RTF carried back `%s`)\n", [[other string] UTF8String]);
			check([[other string] isEqualToString:[field string]],
			      "`-replaceCharactersInRange:withRTF:` puts the characters back");
			[other release];
		}
		check([field RTFDFromRange:NSMakeRange(0, 3)] != nil, "and `-RTFDFromRange:` produces the package form");

		{
			NSString *path = [NSString stringWithFormat:@"/tmp/agora-text-surface-%d.rtfd", (int)getpid()];
			NSText *written = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];

			[written setString:@"document"];
			check([written writeRTFDToFile:path atomically:YES], "`-writeRTFDToFile:atomically:` writes the package");
			[written setString:@"replaced"];
			[written readRTFDFromFile:path];
			check([[written string] isEqualToString:@"document"], "and `-readRTFDFromFile:` reads it back");
			[written release];
			[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		}
	}

	/* 5. **THE FONT PASTEBOARD, AND THE SPELLING CHECK THAT SELECTS.** */
	{
		NSText *other = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];

		[field setFont:[NSFont boldSystemFontOfSize:15.0]];
		[field copyFont:nil];
		[other setFont:font];
		[other pasteFont:nil];
		printf("  (note: pasted face %s at %g)\n",
		       [[[other font] fontName] UTF8String], (double)[[other font] pointSize]);
		check([[other font] pointSize] == 15.0, "a copied font round-trips through the font pasteboard");
		[other release];

		[field setString:@"this has a mispeled word in it"];
		[field setSelectedRange:NSMakeRange(0, 0)];
		[field checkSpelling:nil];
		printf("  (note: the check selected (%lu, %lu)\n",
		       (unsigned long)[field selectedRange].location, (unsigned long)[field selectedRange].length);
		check([field selectedRange].length > 0,
		      "`-checkSpelling:` SELECTS the first misspelling, which is the half this tier can show");
	}

	/* 6. **AND THE FIVE THAT REFUSE.** */
	{
		[field showGuessPanel:nil];
		[field subscript:nil];
		[field superscript:nil];
		[field unscript:nil];
		[field underline:nil];
		check([[field string] length] > 0, "the refusing doors change nothing and do not crash");
		check([field usesFontPanel] == NO, "a field does not use the font panel unless told");
		[field setUsesFontPanel:YES];
		check([field usesFontPanel], "and setting it answers itself");
	}

	[field release];
	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
