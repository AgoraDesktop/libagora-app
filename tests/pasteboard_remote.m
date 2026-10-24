/*
 * pasteboard_remote — does the general pasteboard cross a process boundary?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE ONE CLAIM `NSPasteboard` HAS NEVER BEEN ABLE TO MAKE HERE**: a paste in one application of something copied in
 * another. The in-process doors are old and tested; this drives the same public API — `-declareTypes:owner:`,
 * `-setData:forType:`, `-types`, `-dataForType:` — across two processes through the compositor's selection, so what is
 * asserted is that the ordinary pasteboard API is what crossed, not a private door standing in for it.
 *
 *   pasteboard_remote --offer MIME TEXT   own the selection and serve it
 *   pasteboard_remote --request MIME      read it back and print it
 *   pasteboard_remote --request MIME --expect-none   a type that is not there answers nil, and says why
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPasteboard.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
	@autoreleasepool {
		const char *offer = NULL, *request = NULL, *text = NULL;
		BOOL expect_none = NO;
		int i;

		setvbuf(stdout, NULL, _IONBF, 0);
		for (i = 1; i < argc; i++) {
			if (strcmp(argv[i], "--offer") == 0 && i + 1 < argc) {
				offer = argv[++i];
			} else if (strcmp(argv[i], "--text") == 0 && i + 1 < argc) {
				text = argv[++i];
			} else if (strcmp(argv[i], "--request") == 0 && i + 1 < argc) {
				request = argv[++i];
			} else if (strcmp(argv[i], "--expect-none") == 0) {
				expect_none = YES;
			}
		}

		if (offer != NULL) {
			NSPasteboard *board = [NSPasteboard generalPasteboard];
			NSArray *types = [NSArray arrayWithObject:[NSString stringWithUTF8String:offer]];

			[board declareTypes:types owner:nil];
			[board setData:[NSData dataWithBytes:(text != NULL ? text : "")
						      length:(text != NULL ? strlen(text) : 0)]
			       forType:[NSString stringWithUTF8String:offer]];
			printf("offered %s\n", offer);
			/* **AND IT STAYS ALIVE TO SERVE**, because an owner produces the bytes when somebody asks — a process
			 * that offered and exited would have offered nothing. */
			for (i = 0; i < 300; i++) {
				if (AGWindowServerDispatchTimeout(AGWindowServerShared(), 10) < 0) {
					break;
				}
			}
			return 0;
		}

		if (request != NULL) {
			NSPasteboard *board = [NSPasteboard generalPasteboard];
			NSData *data;
			NSString *string;

			/* ONE DISPATCH FIRST: the offer arrives unsolicited, and this is the turn that brings it. */
			AGWindowServerDispatchTimeout(AGWindowServerShared(), 200);
			data = [board dataForType:[NSString stringWithUTF8String:request]];
			if (expect_none) {
				printf("absent %s\n", data == nil ? "yes" : "NO");
				return data == nil ? 0 : 1;
			}
			if (data == nil) {
				printf("nothing\n");
				return 1;
			}
			string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
			printf("read %s\n", string != nil ? [string UTF8String] : "(not UTF-8)");
			return 0;
		}

		fprintf(stderr, "usage: pasteboard_remote --offer MIME [--text T] | --request MIME [--expect-none]\n");
		return 2;
	}
}
