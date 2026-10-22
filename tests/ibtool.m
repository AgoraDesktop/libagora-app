/*
 * ibtool — the first-party nib format's command line, and the reason the format is a UNIT rather than a feature.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A FORMAT WHOSE ONLY CLIENT IS A GUI IS A FORMAT NOBODY CAN TEST.** `DEVELOPMENT-TOOLS.md` puts this tool ahead of the
 * canvas for exactly that reason: it reads, checks and re-writes the same archives the reader and the writer do, with no
 * display, no window and no owner, so the format's rules are checked by a shell rather than by a person clicking.
 *
 * IT IS A DEVELOPMENT TOOL AND LIVES IN `tests/`, not in the installed SDK: the eventual home for a compiler of this kind
 * is its own repository (the one-component-one-repository rule), and moving it later should be a move rather than a
 * rewrite. What it does NOT do is `compile`: there is no text source format yet, so there is nothing to compile FROM —
 * that is the next unit, and this tool's `dump`/`validate`/`roundtrip` are what it will be tested with.
 *
 * THE FOUR VERBS:
 *
 *   dump <file>        what the archive says — version, top-level objects with their classes and design facts, and every
 *                      connection in the order the file lists them
 *   validate <file>    the reader's own checks, without instantiating anything and without needing an owner; exit 1 with
 *                      a sentence when the file would be refused
 *   roundtrip <file>   decode, re-encode and compare the two dumps — the format's closure, as a command
 *   compile <source> <out.nib>
 *                      the TEXT SOURCE (see NSNibSource.h) into the archive a nib is; the same three checks the reader
 *                      makes are applied to what was built before it is written
 *   decompile <in.nib> <out.nibsource>
 *                      the archive back into text — the format closed in both directions. It refuses what the source
 *                      grammar cannot express (an object-valued property such as a colour or a font) rather than
 *                      dropping it
 *   help               this text
 */
#import "NSNibSource.h"

#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSControl.h>

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static void usage(void)
{
	printf("usage: ibtool <verb> <file> [<out.nib>]\n"
	       "       ibtool help\n"
	       "\n"
	       "verbs:\n"
	       "  dump       what the archive says: version, objects, connections\n"
	       "  validate   the reader's checks, instantiated by nobody and needing no owner\n"
	       "  roundtrip  decode, re-encode, and compare — the format's closure\n"
	       "  compile    a TEXT SOURCE into a nib: ibtool compile in.nibsource out.nib\n"
	       "  decompile  a nib back into text:    ibtool decompile in.nib out.nibsource\n");
}

/* **A DESIGN FACT, ASKED THROUGH THE PUBLIC DOORS RATHER THAN OUT OF AN IVAR.** The dump describes what a CALLER can see:
 * a frame, a tag, a title, a cell's value. Reading `_frame` here would work and would be a lie about the contract — the
 * tool would keep describing a field after its meaning changed. */
static NSString *describe_object(id object)
{
	NSMutableString *line = [[NSMutableString alloc] init];

	[line appendFormat:@"%s", [NSStringFromClass([object class]) UTF8String]];
	if ([object isKindOfClass:[NSView class]]) {
		NSRect frame = [(NSView *)object frame];

		[line appendFormat:@" frame=%g,%g,%g,%g", (double)frame.origin.x, (double)frame.origin.y,
			(double)frame.size.width, (double)frame.size.height];
		[line appendFormat:@" tag=%ld", (long)[(NSView *)object tag]];
		if ([[(NSView *)object subviews] count] > 0) {
			[line appendFormat:@" subviews=%lu", (unsigned long)[[(NSView *)object subviews] count]];
		}
		if ([[(NSView *)object constraints] count] > 0) {
			[line appendFormat:@" constraints=%lu", (unsigned long)[[(NSView *)object constraints] count]];
		}
		if ([(NSView *)object isHidden]) {
			[line appendString:@" hidden"];
		}
	}
	if ([object isKindOfClass:[NSWindow class]]) {
		[line appendFormat:@" title=\"%s\"", [[(NSWindow *)object title] UTF8String]];
	}
	if ([object isKindOfClass:[NSControl class]]) {
		NSCell *cell = [(NSControl *)object cell];

		if (cell != nil) {
			[line appendFormat:@" cell=%s", [NSStringFromClass([cell class]) UTF8String]];
			if ([cell title] != nil) {
				[line appendFormat:@" title=\"%s\"", [[cell title] UTF8String]];
			}
		}
	}
	return [line autorelease];
}

/* **THE TREE IS DUMPED AS A TREE.** A nib's interesting objects are mostly SUBVIEWS, so a dump that only listed the
 * top-level ones would answer "NSView subviews=2" and say nothing about the two — and the button's cell, which is where a
 * button's face actually lives, would never appear. The recursion is the same order `-subviews` reports, which is the
 * order a reader rebuilds. */
static void dump_view_tree(NSView *view, NSMutableString *text, int depth)
{
	int k;
	NSArray *subviews;

	for (k = 0; k < depth; k++) {
		[text appendString:@"  "];
	}
	[text appendFormat:@"  %@\n", describe_object(view)];
	subviews = [view subviews];
	{
		NSUInteger i;

		for (i = 0; i < [subviews count]; i++) {
			id child = [subviews objectAtIndex:i];

			if ([child isKindOfClass:[NSView class]]) {
				dump_view_tree(child, text, depth + 1);
			}
		}
	}
}

/* THE DUMP IS THE COMPARAND THE ROUND TRIP USES, so it must be a function of the GRAPH and not of a path or a pointer. */
static NSData *dump_bytes(NSData *archive, NSMutableString *text)
{
	NSString *refusal = [NSNib refusalReasonForArchiveData:archive];
	id root;
	NSArray *objects;
	NSArray *connections;
	NSUInteger i;
	NSError *error = nil;

	if (refusal != nil) {
		[text appendFormat:@"refused: %@\n", refusal];
		return nil;
	}
	root = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSNib supportedClasses]
						     fromData:archive
							error:&error];
	if (![root isKindOfClass:[NSDictionary class]]) {
		[text appendFormat:@"refused: the root did not decode (%@)\n",
			(error != nil) ? [error localizedDescription] : @"no reason given"];
		return nil;
	}
	[text appendFormat:@"version: %ld\n", (long)[[(NSDictionary *)root objectForKey:NSNibFormatVersionKey]
							   integerValue]];
	objects = [(NSDictionary *)root objectForKey:NSNibTopLevelObjectsKey];
	[text appendFormat:@"top-level objects: %lu\n", (unsigned long)[objects count]];
	for (i = 0; i < [objects count]; i++) {
		id object = [objects objectAtIndex:i];

		if ([object isKindOfClass:[NSView class]]) {
			dump_view_tree(object, text, 0);
		} else {
			[text appendFormat:@"  [%lu] %@\n", (unsigned long)i, describe_object(object)];
		}
	}
	connections = [(NSDictionary *)root objectForKey:NSNibConnectionsKey];
	[text appendFormat:@"connections: %lu\n", (unsigned long)[connections count]];
	for (i = 0; i < [connections count]; i++) {
		id record = [connections objectAtIndex:i];
		id source = [record objectForKey:NSNibConnectionSourceKey];
		id destination = [record objectForKey:NSNibConnectionDestinationKey];
		NSString *keyPath = [record objectForKey:NSNibConnectionKeyPathKey];
		NSString *action = [record objectForKey:NSNibConnectionActionKey];
		const char *from = [source isKindOfClass:[NSString class]]
			? [(NSString *)source UTF8String] : [NSStringFromClass([source class]) UTF8String];
		const char *to = [destination isKindOfClass:[NSString class]]
			? [(NSString *)destination UTF8String] : [NSStringFromClass([destination class]) UTF8String];

		if (keyPath != nil) {
			[text appendFormat:@"  [%lu] outlet %s.%s <- %s\n", (unsigned long)i, from,
				[keyPath UTF8String], to];
		} else {
			[text appendFormat:@"  [%lu] action %s -> %s @%s\n", (unsigned long)i, from, to,
				[(action != nil) ? action : @"?" UTF8String]];
		}
	}
	return [text dataUsingEncoding:NSUTF8StringEncoding];
}

/* AND THE RE-ENCODE, which is what makes `roundtrip` mean something: a decoded graph written back through the writer. The
 * bytes need not be identical — the archiver's table order is its own — so the comparison is between the DUMPS. */
static NSData *reencode(NSData *archive)
{
	id root;
	NSArray *objects;
	/* **AND THE CONNECTIONS ARE AN ARRAY TOO, WHICH IS THE TYPE `-archivedDataWithTopLevelObjects:connections:` TAKES.**
	 * Both collections the nib archive carries are arrays indexed in the same order — `dump_bytes` above already reads
	 * connections with `-objectAtIndex:` — so declaring this one `NSDictionary` described neither the archive nor the
	 * writer's parameter, and the writer's call was rejected for it. */
	NSArray *connections = nil;
	NSError *error = nil;

	root = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSNib supportedClasses]
						     fromData:archive
							error:&error];
	if (![root isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	objects = [(NSDictionary *)root objectForKey:NSNibTopLevelObjectsKey];
	connections = [(NSDictionary *)root objectForKey:NSNibConnectionsKey];
	if (![objects isKindOfClass:[NSArray class]]) {
		return nil;
	}
	return [NSNib archivedDataWithTopLevelObjects:objects connections:connections];
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	int status = 0;

	if (argc < 2) {
		usage();
		[pool release];
		return 2;
	}
	if (strcmp(argv[1], "help") == 0 || strcmp(argv[1], "--help") == 0) {
		usage();
		[pool release];
		return 0;
	}
	if (argc < 3) {
		fprintf(stderr, "ibtool: %s needs a file\n", argv[1]);
		usage();
		[pool release];
		return 2;
	}
	if (strcmp(argv[1], "decompile") == 0) {
		NSString *reason = nil;
		NSData *written;
		NSData *archive;

		if (argc < 4) {
			fprintf(stderr, "ibtool: decompile needs a nib and an output path\n");
			usage();
			[pool release];
			return 2;
		}
		archive = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
		if (archive == nil) {
			fprintf(stderr, "ibtool: cannot read %s\n", argv[2]);
			[pool release];
			return 2;
		}
		written = [NSNibSource sourceFromArchiveData:archive error:&reason];
		if (written == nil) {
			printf("%s: refused — %s\n", argv[2],
			       [(reason != nil ? reason : @"unknown") UTF8String]);
			[pool release];
			return 1;
		}
		if (![written writeToFile:[NSString stringWithUTF8String:argv[3]] atomically:YES]) {
			fprintf(stderr, "ibtool: cannot write %s\n", argv[3]);
			[pool release];
			return 2;
		}
		printf("%s: decompiled %lu bytes to %s\n", argv[2], (unsigned long)[written length], argv[3]);
		[pool release];
		return 0;
	}

	/* **`compile` IS THE ONE VERB THAT WRITES**, so it is handled before the read-only path below and takes two files. */
	if (strcmp(argv[1], "compile") == 0) {
		NSString *reason = nil;
		NSData *archive;

		if (argc < 4) {
			fprintf(stderr, "ibtool: compile needs a source and an output path\n");
			usage();
			[pool release];
			return 2;
		}
		archive = [NSNibSource archiveFromSourceFile:[NSString stringWithUTF8String:argv[2]]
						       error:&reason];
		if (archive == nil) {
			printf("%s: refused — %s\n", argv[2],
			       [(reason != nil ? reason : @"unknown") UTF8String]);
			[pool release];
			return 1;
		}
		/* AND THE FILE IT JUST BUILT GOES BACK THROUGH THE READER'S OWN CHECKS before it is written, because a
		 * compiler that emits a file its reader refuses has hidden the bug in the artifact rather than here. */
		reason = [NSNib refusalReasonForArchiveData:archive];
		if (reason != nil) {
			printf("%s: compiled to a file the reader refuses — %s\n", argv[2],
			       [reason UTF8String]);
			[pool release];
			return 1;
		}
		if (![archive writeToFile:[NSString stringWithUTF8String:argv[3]] atomically:YES]) {
			fprintf(stderr, "ibtool: cannot write %s\n", argv[3]);
			[pool release];
			return 2;
		}
		printf("%s: compiled %lu bytes to %s\n", argv[2], (unsigned long)[archive length], argv[3]);
		[pool release];
		return 0;
	}

	{
		NSString *path = [NSString stringWithUTF8String:argv[2]];
		NSData *archive = [NSData dataWithContentsOfFile:path];

		if (archive == nil) {
			fprintf(stderr, "ibtool: cannot read %s\n", argv[2]);
			[pool release];
			return 2;
		}

		if (strcmp(argv[1], "validate") == 0) {
			NSString *refusal = [NSNib refusalReasonForArchiveData:archive];

			if (refusal != nil) {
				printf("%s: refused — %s\n", argv[2], [refusal UTF8String]);
				status = 1;
			} else {
				printf("%s: ok (version %ld)\n", argv[2], (long)[NSNib formatVersion]);
			}
		} else if (strcmp(argv[1], "dump") == 0) {
			NSMutableString *text = [[NSMutableString alloc] init];
			NSData *bytes = dump_bytes(archive, text);

			if (bytes == nil) {
				fprintf(stderr, "%s", [text UTF8String]);
				status = 1;
			} else {
				printf("%s", [text UTF8String]);
			}
			[text release];
		} else if (strcmp(argv[1], "roundtrip") == 0) {
			NSMutableString *before = [[NSMutableString alloc] init];
			NSMutableString *after = [[NSMutableString alloc] init];
			NSData *again;

			if (dump_bytes(archive, before) == nil) {
				fprintf(stderr, "%s", [before UTF8String]);
				status = 1;
			} else {
				again = reencode(archive);
				if (again == nil || dump_bytes(again, after) == nil) {
					fprintf(stderr, "ibtool: the archive did not survive a re-encode\n");
					status = 1;
				} else if (![[before description] isEqualToString:[after description]]) {
					/* A DIFF, NOT A VERDICT: the two dumps are printed so the difference is visible. */
					printf("roundtrip: DIFFERENT\n--- before ---\n%s--- after ---\n%s",
						[before UTF8String], [after UTF8String]);
					status = 1;
				} else {
					printf("roundtrip: identical\n%s", [before UTF8String]);
				}
			}
			[before release];
			[after release];
		} else {
			fprintf(stderr, "ibtool: unknown verb %s\n", argv[1]);
			usage();
			status = 2;
		}
	}

	[pool release];
	return status;
}
