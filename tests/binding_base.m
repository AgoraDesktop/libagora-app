/*
 * binding_base — the generic binding layer: one object observes another and writes the value through KVC.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE PROBE BINDS ORDINARY OBJECTS, BECAUSE THE BASE IS FOR ORDINARY OBJECTS.** No view and no controller is
 * involved: a target's `title` is bound to a source's `name`, and every check is a value the target actually holds
 * after a write to the source. The Initial notification, the automatic setter's notification, the null placeholder,
 * the two markers and the NSEditor defaults are each measured where they land, and `-infoForBinding:` is read as the
 * record the binding claims to keep.
 */
#import <AppKit/NSKeyValueBinding.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ============================================================================================ *
 * A SOURCE WITH A KVO-OBSERVABLE NAME, A TARGET WITH A TITLE, AND AN EDITOR DELEGATE             *
 * ============================================================================================ */
@interface AGSource : NSObject
{
	id _name;
}
- (id)name;
- (void)setName:(id)value;
@end

@implementation AGSource
- (id)name { return _name; }
- (void)setName:(id)value { _name = value; }
@end

@interface AGTarget : NSObject
{
	id _title;
}
- (id)title;
- (void)setTitle:(id)value;
@end

@implementation AGTarget
- (id)title { return _title; }
- (void)setTitle:(id)value { _title = value; }
@end

@interface AGEditorDelegate : NSObject
{
@public
	id editor;
	BOOL didCommit;
	void *context;
	NSInteger calls;
}
@end

@implementation AGEditorDelegate
- (void)editor:(id)anEditor didCommit:(BOOL)flag contextInfo:(void *)contextInfo
{
	calls++;
	editor = anEditor;
	didCommit = flag;
	context = contextInfo;
}
@end

int main(void)
{
	@autoreleasepool {
		AGSource *source = [[AGSource alloc] init];
		AGTarget *target = [[AGTarget alloc] init];
		BOOL caught;

		/* 1. THE MARKERS. */
		check(NSMultipleValuesMarker != nil && NSNoSelectionMarker != nil && NSNotApplicableMarker != nil,
		      "the three markers exist");
		check(NSMultipleValuesMarker != NSNoSelectionMarker
		      && NSNoSelectionMarker != NSNotApplicableMarker
		      && NSNotApplicableMarker != NSMultipleValuesMarker,
		      "and are three distinct objects");
		check(NSIsControllerMarker(NSMultipleValuesMarker)
		      && NSIsControllerMarker(NSNoSelectionMarker)
		      && NSIsControllerMarker(NSNotApplicableMarker),
		      "`NSIsControllerMarker` recognizes all three");
		check(!NSIsControllerMarker(@"not a marker")
		      && !NSIsControllerMarker(target),
		      "and nothing else");

		/* 2. THE INITIAL VALUE AND THE AUTOMATIC SETTER. */
		[source setName:@"start"];
		[target bind:@"title" toObject:source withKeyPath:@"name" options:nil];
		check([[target title] isEqual:@"start"],
		      "binding applies the observed value immediately (the Initial notification)");
		[source setName:@"second"];
		check([[target title] isEqual:@"second"],
		      "and a setter called DIRECTLY on the source reaches the target");

		/* 3. THE RECORD. */
		{
			NSDictionary *info = [target infoForBinding:@"title"];

			check(info != nil, "`-infoForBinding:` answers a record");
			check([info objectForKey:NSObservedObjectKey] == source
			      && [[info objectForKey:NSObservedKeyPathKey] isEqual:@"name"],
			      "with the observed object and key path");
			check([info objectForKey:NSOptionsKey] != nil, "and an options dictionary");
		}
		check([target infoForBinding:@"untitled"] == nil, "an unbound name has no record");

		/* 4. UNBIND STOPS THE WATCH. */
		[target unbind:@"title"];
		[source setName:@"third"];
		check([[target title] isEqual:@"second"], "after `-unbind:` the target stops following");
		[target unbind:@"title"];	/* unbinding again is a no-op */
		check([target infoForBinding:@"title"] == nil, "and the record is gone");

		/* 5. REBIND REPLACES, SO ONE WRITE IS ONE DELIVERY. */
		[target bind:@"title" toObject:source withKeyPath:@"name" options:nil];
		[target bind:@"title" toObject:source withKeyPath:@"name" options:nil];
		[source setName:@"fourth"];
		check([[target title] isEqual:@"fourth"], "a rebind still delivers the value");
		[target unbind:@"title"];

		/* 6. THE NULL PLACEHOLDER OPTION. */
		[target bind:@"title" toObject:source withKeyPath:@"name"
		     options:[NSDictionary dictionaryWithObject:@"(none)"
							 forKey:NSNullPlaceholderBindingOption]];
		[source setName:nil];
		check([[target title] isEqual:@"(none)"],
		      "a nil value is written as the configured NSNull placeholder");
		[target unbind:@"title"];

		/* 7. A MARKER IS WRITTEN THROUGH, UNLESS THE OPTIONS ASK IT TO RAISE. */
		[target bind:@"title" toObject:source withKeyPath:@"name" options:nil];
		[source setName:NSNotApplicableMarker];
		check([target title] == NSNotApplicableMarker, "a marker is written through by default");
		[target unbind:@"title"];
		[source setName:@"plain"];
		[target bind:@"title" toObject:source withKeyPath:@"name"
		     options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
							 forKey:NSRaisesForNotApplicableKeysBindingOption]];
		caught = NO;
		@try {
			[source setName:NSMultipleValuesMarker];
		} @catch (NSException *exception) {
			caught = [[exception name] isEqual:NSInvalidArgumentException];
		}
		check(caught, "and raises when the options say to");
		[target unbind:@"title"];

		/* 8. EXPOSED BINDINGS. */
		check(![[target exposedBindings] containsObject:@"title"], "a name is not exposed until asked");
		[AGTarget exposeBinding:@"title"];
		check([[target exposedBindings] containsObject:@"title"],
		      "`+exposeBinding:` makes the name part of `-exposedBindings`");
		check([target valueClassForBinding:@"title"] == Nil, "and `-valueClassForBinding:` is nil by default");
		check([[target optionDescriptionsForBinding:@"title"] count] == 0,
		      "as is the interface-builder option list");

		/* 9. PLACEHOLDERS. */
		[AGTarget setDefaultPlaceholder:@"nothing selected" forMarker:NSNoSelectionMarker withBinding:@"title"];
		check([[AGTarget defaultPlaceholderForMarker:NSNoSelectionMarker withBinding:@"title"]
			isEqual:@"nothing selected"],
		      "a class placeholder round-trips");
		check([AGTarget defaultPlaceholderForMarker:NSMultipleValuesMarker withBinding:@"title"] == nil,
		      "and another marker has none");

		/* 10. THE NSEditor DEFAULTS. */
		check([target commitEditing], "a plain object commits editing");
		[target discardEditing];	/* no editors: a no-op, not a crash */
		{
			AGEditorDelegate *editorDelegate = [[AGEditorDelegate alloc] init];

			[target commitEditingWithDelegate:editorDelegate
				 didCommitSelector:@selector(editor:didCommit:contextInfo:)
				      contextInfo:(void *)0x55];
			check(editorDelegate->calls == 1 && editorDelegate->editor == target
			      && editorDelegate->didCommit && editorDelegate->context == (void *)0x55,
			      "and the asynchronous form calls the delegate with its answer and context");
			[editorDelegate release];
		}

		/* 11. THE ARGUMENT CHECKS. */
		caught = NO;
		@try {
			id noObservable = nil;

			[target bind:@"title" toObject:noObservable withKeyPath:@"name" options:nil];
		} @catch (NSException *exception) {
			caught = [[exception name] isEqual:NSInvalidArgumentException];
		}
		check(caught, "binding to a nil observable raises");
		caught = NO;
		@try {
			NSString *noPath = nil;

			[target bind:@"title" toObject:source withKeyPath:noPath options:nil];
		} @catch (NSException *exception) {
			caught = [[exception name] isEqual:NSInvalidArgumentException];
		}
		check(caught, "and so does a nil key path");

		[target unbind:@"title"];
		printf("binding_base: %d case(s) failed\n", s_failed);
		[target release];
		[source release];
	}
	return s_failed != 0;
}
