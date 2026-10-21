/*
 * nib_compile — the text source, compiled, and every way the compiler refuses.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * **A COMPILER IS ONLY AS USEFUL AS ITS REFUSALS**, so this program spends as much of itself on the files that must NOT
 * compile as on the one that must. Each refusal is a sentence naming the object, the key and — for the parser — the line,
 * because a design file's mistake is a design file's mistake and a bare "syntax error" is not something a person can act
 * on.
 *
 * WHAT IS ASSERTED:
 *
 *   1. A source with a view, a constrained child, a real button with a CELL, and two connections compiles; the result is
 *      a nib `NSNib` accepts, whose tree, properties, connections and equations came out as written.
 *   2. The compiler DEFAULTS the multiplier to one and refuses zero, rather than letting a nil message become a zero.
 *   3. Six refusals, each naming what was wrong: an unknown object key, a class outside the allow-list, a class that does
 *      not exist, a reference to an id the file never declares, a geometry string that is not four numbers, and a
 *      property the class does not have.
 *   4. The typed words: `41` is a number, `4.5` is a real, `YES` is a boolean, and `NSView3` is a STRING (the whole-word
 *      rule, which a naive `isdigit` check gets wrong).
 */
#import "NSNibSource.h"

#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSLayoutConstraint.h>

#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

/* **THE OWNER HAS TO HAVE THE OUTLET THE SOURCE NAMES**, which is the point of an outlet: a nib wires a name on a class,
 * so an owner without that name is a source whose outlet does not exist. The test's owner therefore DECLARES it. */
@interface CompileOwner : NSObject
{
	id _subjectView;
}
- (id)subjectView;
- (void)setSubjectView:(id)view;
@end

@implementation CompileOwner
- (id)subjectView { return _subjectView; }
- (void)setSubjectView:(id)view
{
	if (view != _subjectView) {
		id held = [view retain];
		[_subjectView release];
		_subjectView = held;
	}
}
- (void)dealloc { [_subjectView release]; [super dealloc]; }
@end

static int s_failed;

static void check(int ok, const char *name)
{
	printf("%s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSData *source(const char *text)
{
	return [NSData dataWithBytes:text length:strlen(text)];
}

/* THE GOOD SOURCE, as a C string so the test cannot drift from a checked-in file. */
static const char *kGoodSource =
	"// the fixture: a view with a constrained child and a real button\n"
	"{\n"
	"  version = 1;\n"
	"  objects = (\n"
	"    {\n"
	"      id = \"root\";\n"
	"      class = NSView;\n"
	"      properties = { frame = \"0 0 400 300\"; tag = 41; };\n"
	"      subviews = (\n"
	"        { id = \"subject\"; class = NSView;\n"
	"          properties = { frame = \"0 0 0 0\";\n"
	"                         translatesAutoresizingMaskIntoConstraints = NO; tag = 42; }; }\n"
	"        { id = \"go\"; class = NSButton;\n"
	"          properties = { frame = \"10 40 90 24\"; };\n"
	"          cell = { class = NSButtonCell; properties = { title = \"Go\"; bordered = YES; }; }; }\n"
	"      );\n"
	"      constraints = (\n"
	"        { first = \"subject\"; firstAttribute = width; constant = 120; }\n"
	"        { first = \"subject\"; firstAttribute = height; constant = 40; priority = 750;\n"
	"          identifier = \"loose height\"; }\n"
	"        { first = \"subject\"; firstAttribute = left; second = \"root\";\n"
	"          secondAttribute = left; relation = equal; constant = 10; }\n"
	"      );\n"
	"    }\n"
	"  );\n"
	"  connections = (\n"
	"    { source = \"go\"; action = \"go:\"; destination = owner; }\n"
	"    { source = owner; keyPath = \"subjectView\"; destination = \"subject\"; }\n"
	"  );\n"
	"}\n";

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *error = nil;
	NSData *archive;
	id plist;

	/* ---- 1. THE PARSE AND THE TYPES ---------------------------------------------------------- */
	plist = [NSNibSource propertyListFromSourceData:source(kGoodSource) error:&error];
	check(plist != nil, "the fixture parses");
	check(error == nil, "and it parses without an error");
	if (plist != nil) {
		NSArray *objects = [(NSDictionary *)plist objectForKey:@"objects"];
		NSDictionary *rootRecord = [objects objectAtIndex:0];
		NSDictionary *properties = [rootRecord objectForKey:@"properties"];

		check([[properties objectForKey:@"tag"] isKindOfClass:[NSNumber class]],
		      "a bare integer word is a NUMBER");
		check([[properties objectForKey:@"frame"] isKindOfClass:[NSString class]],
		      "a quoted value is a STRING");
	}
	/* THE WHOLE-WORD RULE: a class name that begins with digits is not a number. */
	{
		id typed = [NSNibSource propertyListFromSourceData:source("{ a = NSView3; b = 4.5; c = YES; }")
							     error:&error];

		check(typed != nil, "a one-level dictionary parses");
		if (typed != nil) {
			check([[(NSDictionary *)typed objectForKey:@"a"] isKindOfClass:[NSString class]],
			      "NSView3 is a STRING and not the number 3");
			check([[(NSDictionary *)typed objectForKey:@"b"] isKindOfClass:[NSNumber class]],
			      "4.5 is a NUMBER");
			check([[(NSDictionary *)typed objectForKey:@"c"] boolValue],
			      "YES is a boolean that is true");
		}
	}

	/* ---- 2. THE COMPILE ---------------------------------------------------------------------- */
	error = nil;
	archive = [NSNibSource archiveFromSourceData:source(kGoodSource) error:&error];
	check(archive != nil, "the fixture compiles");
	if (archive != nil) {
		NSString *refusal = [NSNib refusalReasonForArchiveData:archive];

		check(refusal == nil, "what it compiled is a nib the READER accepts");
		check([NSNib refusalReasonForArchiveData:archive] == nil, "re-checked, still accepted");

		[archive writeToFile:@"/tmp/agora-compiled.nib" atomically:YES];
		/* **AND WITH AN OWNER THAT HAS THE OUTLET, AND WITHOUT ONE.** The fixture wires the file's owner twice, so a
		 * decode with no owner must be REFUSED (an unresolved placeholder is an error, not a nil) and a decode with an
		 * owner that lacks the outlet must be refused too — the second is `-setValue:forKey:`'s own refusal and the
		 * reader reports it rather than half-loading. */
		{
			NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@"/tmp/agora-compiled.nib"]];
			NSArray *top = nil;
			CompileOwner *owner = [[CompileOwner alloc] init];

			check(![nib instantiateNibWithOwner:nil topLevelObjects:&top],
			      "a nib wiring the owner is REFUSED with no owner");
			check(![nib instantiateNibWithOwner:[[[NSObject alloc] init] autorelease]
					  topLevelObjects:&top],
			      "and refused with an owner that lacks the outlet it names");
			check([nib instantiateNibWithOwner:owner topLevelObjects:&top],
			      "and accepted with an owner that has it");
			check([owner subjectView] != nil, "the outlet landed on the owner");
			[owner release];
			[nib release];
		}
	}

	/* ---- 3. THE DECODED TREE ------------------------------------------------------------------ */
	{
		NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@"/tmp/agora-compiled.nib"]];
		NSArray *top = nil;
		CompileOwner *owner = [[CompileOwner alloc] init];

		if ([nib instantiateNibWithOwner:owner topLevelObjects:&top] && [top count] == 1) {
			NSView *root = [top objectAtIndex:0];
			NSArray *subviews = [root subviews];

			check([root tag] == 41, "the root's tag came through the compiler");
			check([[root constraints] count] == 3, "all three equations were compiled");
			check([subviews count] == 2, "both subviews were compiled");
			if ([subviews count] == 2) {
				NSView *subject = [subviews objectAtIndex:0];
				NSButton *button = [subviews objectAtIndex:1];

				check([subject tag] == 42, "the child's tag came through");
				check(![subject translatesAutoresizingMaskIntoConstraints],
				      "the child's translate-mask flag came through");
				check([button isKindOfClass:[NSButton class]], "the button kept its class");
				check([[[button cell] title] isEqualToString:@"Go"],
				      "the CELL's title was compiled from a nested object");
				check([[button cell] isBordered], "and so was its border flag");
				check([button target] == owner,
				      "the action connection's target is the owner");
				check([button action] == NSSelectorFromString(@"go:"),
				      "and its selector came from the source by name");
			}
			/* THE PRIORITY AND THE IDENTIFIER OF THE OPTIONAL EQUATION, which no frame shows. */
			{
				NSUInteger i;
				BOOL sawPriority = NO;

				for (i = 0; i < [[root constraints] count]; i++) {
					NSLayoutConstraint *c = [[root constraints] objectAtIndex:i];

					if ([[c identifier] isEqualToString:@"loose height"]) {
						sawPriority = ([c priority] == 750.0);
					}
				}
				check(sawPriority, "an equation's priority and identifier came through the compiler");
			}
			/* AND THE EQUATIONS ACTUALLY LAY OUT, which is the only proof they were wired to the right views. */
			[root layoutSubtreeIfNeeded];
			if ([subviews count] == 2) {
				NSView *subject = [subviews objectAtIndex:0];

				check(fabs([subject frame].size.width - 120.0) < 1e-6,
				      "the compiled width equation produced a width");
				check(fabs([subject frame].origin.x - 10.0) < 1e-6,
				      "the compiled left equation produced an origin");
			}
		}
		[owner release];
		[nib release];
	}

	/* ---- 4. THE REFUSALS ---------------------------------------------------------------------- */
	/* EACH ONE IS A FILE THAT MUST NOT COMPILE, AND THE ASSERTION IS BOTH THAT IT FAILED AND THAT THE SENTENCE NAMES
	 * THE THING THAT WAS WRONG — a refusal that says only "failed" teaches nothing. */
	{
		struct {
			const char *what;
			const char *source;
			const char *mentions;
		} cases[] = {
			{ "an unknown object key is refused",
			  "{ version = 1; objects = ( { class = NSView; freckles = 3; } ); }",
			  "freckles" },
			{ "a class outside the allow-list is refused",
			  "{ version = 1; objects = ( { class = NSIndexPath; } ); }",
			  "NSIndexPath" },
			{ "a class that does not exist is refused",
			  "{ version = 1; objects = ( { class = NSWidgetOfTheFuture; } ); }",
			  "NSWidgetOfTheFuture" },
			{ "a reference to an undeclared id is refused",
			  "{ version = 1; objects = ( { class = NSView; constraints = ("
			  " { first = \"nobody\"; firstAttribute = width; constant = 1; }"
			  " ); } ); }",
			  "nobody" },
			{ "a geometry string that is not four numbers is refused",
			  "{ version = 1; objects = ( { class = NSView; properties = { frame = \"0 0 320\"; }; } ); }",
			  "frame" },
			{ "a property the class does not have is refused",
			  "{ version = 1; objects = ( { class = NSView; properties = { tagg = 7; }; } ); }",
			  "tagg" },
			{ "a zero multiplier is refused",
			  "{ version = 1; objects = ( { class = NSView; subviews = ("
			  " { id = \"c\"; class = NSView; }"
			  " ); constraints = ( { first = \"c\"; firstAttribute = width; multiplier = 0; constant = 1; } ); } ); }",
			  "multiplier" },
		};
		NSUInteger i;

		for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
			NSString *reason = nil;
			NSData *built = [NSNibSource archiveFromSourceData:source(cases[i].source) error:&reason];

			check(built == nil, cases[i].what);
			check(reason != nil &&
			      [reason rangeOfString:[NSString stringWithUTF8String:cases[i].mentions]].location !=
			      NSNotFound,
			      (i < 7) ? "…and the refusal names what was wrong" : "…and names it");
		}
	}

	/* ---- 5. THE VALUE LITERALS ------------------------------------------------------------------ */
	/* **THE THREE OBJECTS A PROPERTY MAP COULD NOT HOLD.** `@color(…)`, `@font(…)` and `@image(…)` are how a colour, a
	 * font and an image are written; each is built by the compiler and lands on the object through KVC. */
	{
		struct {
			const char *what;
			const char *source;
		} good[] = {
			{ "a hex colour compiles",
			  "{ version = 1; objects = ( { class = NSTextField;"
			  " cell = { class = NSTextFieldCell; properties = { textColor = @color(#ff0000); }; }; } ); }" },
			{ "an eight-digit colour carries its alpha",
			  "{ version = 1; objects = ( { class = NSTextField;"
			  " cell = { class = NSTextFieldCell; properties = { textColor = @color(#00ff0080); }; }; } ); }" },
			{ "a named colour compiles",
			  "{ version = 1; objects = ( { class = NSTextField;"
			  " cell = { class = NSTextFieldCell; properties = { textColor = @color(orange); }; }; } ); }" },
			{ "a font compiles",
			  "{ version = 1; objects = ( { class = NSTextField;"
			  " cell = { class = NSTextFieldCell; properties = { font = @font(\"Helvetica\" 13); }; }; } ); }" },
		};
		NSUInteger i;

		for (i = 0; i < sizeof(good) / sizeof(good[0]); i++) {
			NSString *reason = nil;
			NSData *built = [NSNibSource archiveFromSourceData:source(good[i].source) error:&reason];

			check(built != nil, good[i].what);
			if (built == nil && reason != nil) {
				printf("      (%s)\n", [reason UTF8String]);
			}
		}
		/* AND THE VALUES ACTUALLY LANDED. */
		{
			NSString *reason = nil;
			NSData *built = [NSNibSource archiveFromSourceData:source(good[0].source) error:&reason];
			NSString *path = @"/tmp/agora-literal.nib";

			[built writeToFile:path atomically:YES];
			{
				NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
				NSArray *top = nil;

				if ([nib instantiateNibWithOwner:nil topLevelObjects:&top] && [top count] == 1) {
					NSCell *cell = [(NSTextField *)[top objectAtIndex:0] cell];
					NSColor *colour = [cell textColor];

					check(colour != nil, "the colour reached the cell");
					check(fabs([colour redComponent] - 1.0) < 0.01 &&
					      fabs([colour greenComponent]) < 0.01 &&
					      fabs([colour blueComponent]) < 0.01,
					      "and it is the red the source asked for");
				}
				[nib release];
			}
		}
		/* AND THE REFUSALS. */
		{
			struct {
				const char *what;
				const char *source;
				const char *mentions;
			} bad[] = {
				{ "a colour that is not hex is refused",
				  "{ version = 1; objects = ( { class = NSTextField; cell = { class = NSTextFieldCell;"
				  " properties = { textColor = @color(#zzzzzz); }; }; } ); }", "@color" },
				{ "a font this machine has not got is refused",
				  "{ version = 1; objects = ( { class = NSTextField; cell = { class = NSTextFieldCell;"
				  " properties = { font = @font(\"NoSuchFontAtAll\" 12); }; }; } ); }", "NoSuchFontAtAll" },
				{ "a font with no size is refused",
				  "{ version = 1; objects = ( { class = NSTextField; cell = { class = NSTextFieldCell;"
				  " properties = { font = @font(\"Helvetica\"); }; }; } ); }", "@font" },
				{ "an unknown literal is refused",
				  "{ version = 1; objects = ( { class = NSView; properties = { tag = 1; }; } );"
				  " }", NULL },
			};
			NSUInteger i;

			for (i = 0; i < sizeof(bad) / sizeof(bad[0]) - 1; i++) {
				NSString *reason = nil;
				NSData *built = [NSNibSource archiveFromSourceData:source(bad[i].source) error:&reason];

				check(built == nil, bad[i].what);
				check(reason != nil && [reason rangeOfString:[NSString stringWithUTF8String:bad[i].mentions]]
							  .location != NSNotFound,
				      "…and the refusal names what was wrong");
			}
			/* THE UNKNOWN LITERAL, written separately because its own message is the one that has to list the three. */
			{
				NSString *reason = nil;
				NSData *built = [NSNibSource archiveFromSourceData:
					source("{ version = 1; objects = ( { class = NSView; properties ="
					       " { tag = @widget(1); }; } ); }") error:&reason];

				check(built == nil, "an unknown literal is refused");
				check(reason != nil && [reason rangeOfString:@"@widget"].location != NSNotFound,
				      "…naming it");
			}
		}
	}

	/* AND THE PARSER'S OWN DIAGNOSTICS CARRY A LINE NUMBER. */
	{
		NSString *reason = nil;
		NSData *built = [NSNibSource archiveFromSourceData:source("{\n  version = 1;\n  objects = (\n")
							     error:&reason];

		check(built == nil, "an unclosed array is refused");
		check(reason != nil && [reason rangeOfString:@"line"].location != NSNotFound,
		      "the parser's refusal names a LINE");
	}

	[pool release];
	if (s_failed != 0) {
		fprintf(stderr, "%d failure(s)\n", s_failed);
		return 1;
	}
	printf("all nib-source assertions passed\n");
	return 0;
}
