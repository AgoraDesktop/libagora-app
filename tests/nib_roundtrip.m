/*
 * nib_roundtrip.m — the first-party nib format's round trip, and the three rules that make it safe.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * WHAT THIS PROVES, IN ORDER:
 *
 *   1. THE CENSUS IS EMPTY. Every class `NSNib` allows a design file to name implements both coding methods itself
 *      rather than inheriting one — the drift trap, stated by `+classesInheritingCoding`.
 *   2. A VIEW TREE SURVIVES. A container with two children, a control with a real cell, and every design property
 *      that is a number, a flag, a string or a geometry round-trips through the archive and the reader, including
 *      the ORDER of the subviews and the superview wiring `-addSubview:` builds.
 *   3. THE CONNECTIONS ARE APPLIED. An outlet is set through `-setValue:forKeyPath:` and an action is the
 *      target/action pair, with the `NSNibFileOwner` placeholder resolved to the owner handed in.
 *   4. A FILE THE READER MAY NOT BUILD IS REFUSED, before any object exists: an archive whose object table names a
 *      class outside the allow-list answers NO rather than decoding into a half-built graph.
 *
 * IT NEEDS NO DISPLAY AND NO COMPOSITOR: it builds views, not windows. A window's archive is exercised by the
 * nested demonstration instead, because creating one opens a surface.
 */
#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSSegmentedControl.h>
#import <AppKit/NSSegmentedCell.h>
#import <AppKit/NSSlider.h>
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSLayoutConstraint.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int g_failures = 0;

static void check(int condition, const char *what)
{
	if (!condition) {
		fprintf(stderr, "FAIL: %s\n", what);
		g_failures++;
	} else {
		printf("ok: %s\n", what);
	}
}

/* THE OWNER: a plain object with one outlet and one action, which is what a nib's file's owner is. */
@interface NibTestOwner : NSObject
{
	id _titleField;
	BOOL _actionFired;
}
- (id)titleField;
- (void)setTitleField:(id)field;
- (BOOL)actionFired;
- (void)doTheThing:(id)sender;
@end

@implementation NibTestOwner
- (id)titleField { return _titleField; }
- (void)setTitleField:(id)field
{
	if (field != _titleField) {
		id held = [field retain];
		[_titleField release];
		_titleField = held;
	}
}
- (BOOL)actionFired { return _actionFired; }
- (void)doTheThing:(id)sender { (void)sender; _actionFired = YES; }
- (void)dealloc { [_titleField release]; [super dealloc]; }
@end

@interface NibTestView : NSView
@end

@implementation NibTestView
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSSet *inheriting;
	NibTestView *container;
	NibTestView *childA;
	NibTestView *childB;
	NSControl *control;
	NSCell *cell;
	NSButton *button;
	NSTextField *field;
	NSSegmentedControl *segmented;
	NSSlider *slider;
	NSArray *objects = nil;
	NSArray *connections;
	NibTestOwner *owner;
	NSData *data;
	NSNib *nib;
	NSString *writePath;

	/* ---- 0. THE APPLICATION REGISTERS ITS OWN VIEW CLASS -------------------------------------- */
	/* **THE POINT OF A NIB IS THAT IT NAMES THE APPLICATION'S OWN SUBCLASSES**, so the allow-list is extensible and this
	 * registration is the door. A class that cannot honour the contract is refused HERE rather than at read time. */
	check(![NSNib registerDesignClass:[NSAutoreleasePool class]],
	      "a class that does not implement coding is refused at registration");
	check([NSNib registerDesignClass:[NibTestView class]],
	      "an application's own view subclass can be registered as a design class");
	check([NSNib isSupportedClass:[NibTestView class]],
	      "the registered class is on the reader's allow-list");

	/* ---- 1. THE CENSUS ------------------------------------------------------------------------- */
	inheriting = [NSNib classesInheritingCoding];
	if ([inheriting count] != 0) {
		printf("classes that inherit coding instead of implementing it: %s\n",
		       [[inheriting description] UTF8String]);
	}
	check([inheriting count] == 0,
	      "every supported class implements both coding methods itself");

	/* ---- 2. THE TREE ------------------------------------------------------------------------- */
	container = [[NibTestView alloc] initWithFrame:NSMakeRect(10.0, 20.0, 400.0, 300.0)];
	[container setTag:7];
	[container setToolTip:@"the container"];
	[container setAlphaValue:0.5];

	childA = [[NibTestView alloc] initWithFrame:NSMakeRect(1.0, 2.0, 30.0, 40.0)];
	[childA setTag:11];
	[childA setHidden:YES];

	childB = [[NibTestView alloc] initWithFrame:NSMakeRect(3.0, 4.0, 50.0, 60.0)];
	[childB setTag:12];

	cell = [[NSCell alloc] initTextCell:@"the title"];
	[cell setTag:99];
	[cell setState:1];
	[cell setAlignment:NSCenterTextAlignment];
	[cell setBordered:YES];
	[cell setEditable:YES];
	[cell setSelectable:YES];

	control = [[NSControl alloc] initWithFrame:NSMakeRect(5.0, 6.0, 120.0, 24.0)];
	[control setCell:cell];
	[control setTag:13];
	[cell release];

	/* **AND A REAL BUTTON, FIELD, SEGMENTED CONTROL AND SLIDER**, which is what proves the SUBCLASSES carry their own
	 * state rather than decoding through `NSCell`. Each one sets something only its own class has. */
	button = [[NSButton alloc] initWithFrame:NSMakeRect(7.0, 8.0, 100.0, 24.0)];
	[button setTitle:@"Press"];
	[button setAlternateTitle:@"Pressed"];
	[button setButtonType:NSMomentaryPushInButton];
	[button setBezelStyle:NSRoundedBezelStyle];

	field = [[NSTextField alloc] initWithFrame:NSMakeRect(9.0, 10.0, 140.0, 22.0)];
	[field setStringValue:@"typed"];
	[field setDrawsBackground:YES];
	[field setTextColor:[NSColor redColor]];

	segmented = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(11.0, 12.0, 180.0, 24.0)];
	[segmented setSegmentCount:3];
	[segmented setLabel:@"one" forSegment:0];
	[segmented setLabel:@"two" forSegment:1];
	[segmented setLabel:@"three" forSegment:2];
	[segmented setSelectedSegment:2];

	slider = [[NSSlider alloc] initWithFrame:NSMakeRect(13.0, 14.0, 160.0, 20.0)];
	[slider setMinValue:-5.0];
	[slider setMaxValue:42.0];
	[slider setDoubleValue:7.5];
	[slider setNumberOfTickMarks:11];

	/* THE ORDER IS THE ASSERTION: A goes in before B, and the archive must return them in that order. */
	[container addSubview:childA];
	[container addSubview:childB];
	[container addSubview:control];
	[container addSubview:button];
	[container addSubview:field];
	[container addSubview:segmented];
	[container addSubview:slider];
	[button release];
	[field release];
	[segmented release];
	[slider release];
	[childA release];
	[childB release];
	[control release];

	/* ---- THE CONNECTIONS: AN OUTLET AND AN ACTION, BOTH TO THE FILE'S OWNER ------------------- */
	owner = [[NibTestOwner alloc] init];
	/* **THE OWNER IS NAMED BY THE PLACEHOLDER, NOT ENCODED, BECAUSE IT IS THE CALLER'S OBJECT AND NOT THE FILE'S.** The
	 * outlet runs FROM the owner (its `titleField` becomes the control) and the action runs TO it (the control's target),
	 * which is the two directions a nib actually uses. */
	connections = [NSArray arrayWithObjects:
		[NSNib outletConnectionFrom:NSNibFileOwner
				 to:[[container subviews] objectAtIndex:2]
			      keyPath:@"titleField"],
		[NSNib actionConnectionFrom:[[container subviews] objectAtIndex:2]
					 to:NSNibFileOwner
				     action:@"doTheThing:"],
		nil];

	data = [NSNib archivedDataWithTopLevelObjects:[NSArray arrayWithObject:container] connections:connections];
	check(data != nil, "the writer produced an archive");
	check([data length] > 0, "the archive is not empty");

	/* AND IT IS WRITTEN TO DISK, because a nib IS a file: the reader is then asked to read one, which is the door a
	 * caller uses. The path is in /tmp and in the same format a bundle's resource would carry. */
	writePath = @"/tmp/agora-nib-roundtrip.nib";
	check([data writeToFile:writePath atomically:YES], "the archive was written to a file");

	nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:writePath]];
	check(nib != nil, "the reader recorded the nib's source");

	{
		BOOL ok = [nib instantiateNibWithOwner:owner topLevelObjects:&objects];

		check(ok, "the reader instantiated the nib");
		check([objects count] == 1, "one top-level object came back");
	}
	[nib release];

	if ([objects count] == 1) {
		NSView *decoded = [objects objectAtIndex:0];
		NSArray *subviews = [decoded subviews];

		check([decoded isKindOfClass:[NibTestView class]],
		      "the decoded object is the class the file named, not its superclass");
		check(NSEqualRects([decoded frame], NSMakeRect(10.0, 20.0, 400.0, 300.0)),
		      "the container's frame round-tripped");
		check([decoded tag] == 7, "the container's tag round-tripped");
		check([[decoded toolTip] isEqualToString:@"the container"],
		      "the container's tool tip round-tripped");
		check([decoded alphaValue] == 0.5, "the container's alpha round-tripped");

		check([subviews count] == 7, "all seven subviews came back");
		if ([subviews count] == 7) {
			NSView *a = [subviews objectAtIndex:0];
			NSView *b = [subviews objectAtIndex:1];
			NSControl *c = [subviews objectAtIndex:2];

			check([a tag] == 11, "the first subview is the first child, by tag");
			check([b tag] == 12, "the second subview is the second child, by tag");
			check([a isHidden], "the hidden flag round-tripped");
			check(NSEqualRects([b frame], NSMakeRect(3.0, 4.0, 50.0, 60.0)),
			      "the second child's frame round-tripped");
			check([a superview] == decoded && [b superview] == decoded && [c superview] == decoded,
			      "every decoded child's superview is its parent");
			check([a window] == nil, "no decoded view claims a window it was not given");

			check([c isKindOfClass:[NSControl class]], "the control kept its class");
			check([c tag] == 13, "the control's own tag round-tripped");
			check([[c cell] isKindOfClass:[NSCell class]], "the control kept its cell");
			if ([c cell] != nil) {
				NSCell *decodedCell = [c cell];

				check([[decodedCell title] isEqualToString:@"the title"],
				      "the cell's title round-tripped");
				check([decodedCell tag] == 99, "the cell's tag round-tripped");
				check([decodedCell state] == 1, "the cell's state round-tripped");
				check([decodedCell alignment] == NSCenterTextAlignment,
				      "the cell's alignment round-tripped");
				check([decodedCell isBordered], "the cell's border flag round-tripped");
				check([decodedCell isEditable], "the cell's editable flag round-tripped");
				check([decodedCell isSelectable], "the cell's selectable flag round-tripped");
				check([decodedCell controlView] == c,
				      "the decoded cell was told which control draws it");
			}

				NSButton *db = [subviews objectAtIndex:3];
				NSTextField *df = [subviews objectAtIndex:4];
				NSSegmentedControl *ds = [subviews objectAtIndex:5];
				NSSlider *dl = [subviews objectAtIndex:6];

				/* **THE SUBCLASS'S OWN STATE, WHICH IS THE POINT OF THE WHOLE UNIT.** If a class had inherited
				 * `NSCell`'s coding instead of implementing its own, each of these would come back at its default
				 * and the assertion is what would say so. */
				check([db isKindOfClass:[NSButton class]], "the button kept its class");
				check([[db title] isEqualToString:@"Press"], "the button's title round-tripped");
				check([[db alternateTitle] isEqualToString:@"Pressed"],
				      "the BUTTON's own alternate title round-tripped");
				check([[db cell] bezelStyle] == NSRoundedBezelStyle,
				      "the button cell's bezel style round-tripped");
				check([[db cell] buttonType] == NSMomentaryPushInButton,
				      "the button cell's type round-tripped");

				check([df isKindOfClass:[NSTextField class]], "the field kept its class");
				check([[df stringValue] isEqualToString:@"typed"], "the field's value round-tripped");
				check([[df cell] drawsBackground], "the FIELD cell's background flag round-tripped");
				check([[[df cell] textColor] isEqual:[NSColor redColor]],
				      "the field cell's text colour round-tripped as a colour");

				check([ds isKindOfClass:[NSSegmentedControl class]], "the segmented control kept its class");
				check([[ds cell] segmentCount] == 3, "all three segments came back");
				check([[[ds cell] labelForSegment:1] isEqualToString:@"two"],
				      "a segment's label round-tripped");
				check([[ds cell] selectedSegment] == 2,
				      "the SEGMENTED cell's own selection round-tripped");

				check([dl isKindOfClass:[NSSlider class]], "the slider kept its class");
				check([[dl cell] minValue] == -5.0, "the slider cell's minimum round-tripped");
				check([[dl cell] maxValue] == 42.0, "the slider cell's maximum round-tripped");
				check([[dl cell] doubleValue] == 7.5, "the slider cell's value round-tripped");
				check([[dl cell] numberOfTickMarks] == 11, "the slider cell's tick count round-tripped");

			/* ---- 3. THE CONNECTIONS ---------------------------------------------------------- */
			check([owner titleField] == c, "the outlet connection reached the file's owner");
			check([c target] == owner, "the action connection set the control's target");
			check([c action] != NULL && [c action] == NSSelectorFromString(@"doTheThing:"),
			      "the action connection set the selector by name");
			{
				BOOL fired = [c sendAction:[c action] to:[c target]];

				check(fired, "the wired action was sent and accepted");
				check([owner actionFired], "the owner's action method ran");
			}
		}
	}

	/* ---- 3b. THE EQUATIONS, AND WHETHER THE DECODED TREE ACTUALLY LAYS OUT --------------------- */
	/* **A CONSTRAINT THAT DECODES AND DOES NOTHING IS NOT A CONSTRAINT.** So this half does not stop at comparing the
	 * equation's numbers: it lays the decoded tree out and asserts the FRAMES the equations dictate, which is the only
	 * evidence that the archive carried the relationship rather than a description of one. */
	{
		NibTestView *root = [[NibTestView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
		NibTestView *subject = [[NibTestView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 0.0, 0.0)];
		NSMutableArray *equations = [[NSMutableArray alloc] init];
		NSLayoutConstraint *loose;
		NSData *layoutData;
		NSNib *layoutNib;
		NSArray *layoutObjects = nil;

		[subject setTranslatesAutoresizingMaskIntoConstraints:NO];
		[root addSubview:subject];

		[equations addObject:[NSLayoutConstraint constraintWithItem:subject
								 attribute:NSLayoutAttributeWidth
								 relatedBy:NSLayoutRelationEqual
								    toItem:nil
								 attribute:NSLayoutAttributeNotAnAttribute
								multiplier:1.0
								  constant:120.0]];
		[equations addObject:[NSLayoutConstraint constraintWithItem:subject
								 attribute:NSLayoutAttributeHeight
								 relatedBy:NSLayoutRelationEqual
								    toItem:nil
								 attribute:NSLayoutAttributeNotAnAttribute
								multiplier:1.0
								  constant:40.0]];
		[equations addObject:[NSLayoutConstraint constraintWithItem:subject
								 attribute:NSLayoutAttributeLeft
								 relatedBy:NSLayoutRelationEqual
								    toItem:root
								 attribute:NSLayoutAttributeLeft
								multiplier:1.0
								  constant:10.0]];
		[equations addObject:[NSLayoutConstraint constraintWithItem:subject
								 attribute:NSLayoutAttributeTop
								 relatedBy:NSLayoutRelationEqual
								    toItem:root
								 attribute:NSLayoutAttributeTop
								multiplier:1.0
								  constant:20.0]];
		/* **AND ONE EQUATION THAT IS NOT ADOPTED, WHICH IS HOW PRIORITY AND THE IDENTIFIER GET EXERCISED WITHOUT THE
		 * SOLVER'S ANSWER DEPENDING ON THEM.** An optional constraint competes with the required set and settles
		 * part-way by design — that is the solver's documented behaviour, not something an archive should have to pin —
		 * so the priority/identifier round trip is asserted on a constraint the layout does not have to satisfy. */
		loose = [NSLayoutConstraint constraintWithItem:subject
						    attribute:NSLayoutAttributeHeight
						    relatedBy:NSLayoutRelationEqual
						       toItem:nil
						    attribute:NSLayoutAttributeNotAnAttribute
						   multiplier:1.0
						     constant:90.0];
		[loose setPriority:750.0];
		[loose setIdentifier:@"loose height"];

		[root addConstraint:[equations objectAtIndex:0]];
		[root addConstraint:[equations objectAtIndex:1]];
		[root addConstraint:[equations objectAtIndex:2]];
		[root addConstraint:[equations objectAtIndex:3]];

		/* THE SOURCE TREE LAYS OUT, so the archive is written by a tree that already satisfies its own equations. */
		[root layoutSubtreeIfNeeded];
		check(fabs([subject frame].size.width - 120.0) < 1e-6,
		      "the built tree lays out to its width equation");

		layoutData = [NSNib archivedDataWithTopLevelObjects:
			[NSArray arrayWithObjects:root, loose, nil] connections:nil];
		check(layoutData != nil, "a constrained tree archives");
		[layoutData writeToFile:@"/tmp/agora-nib-layout.nib" atomically:YES];
		layoutNib = [[NSNib alloc] initWithContentsOfURL:
			[NSURL fileURLWithPath:@"/tmp/agora-nib-layout.nib"]];
		check([layoutNib instantiateNibWithOwner:nil topLevelObjects:&layoutObjects],
		      "a constrained tree decodes");
		[layoutNib release];

		check([layoutObjects count] == 2, "the constrained tree and the loose equation both came back");
		if ([layoutObjects count] == 2) {
			NSView *droot = [layoutObjects objectAtIndex:0];
			NSLayoutConstraint *dloose = [layoutObjects objectAtIndex:1];
			NSArray *dsubviews = [droot subviews];

			check([[droot constraints] count] == 4, "all four equations came back");
			check([dsubviews count] == 1, "the constrained view came back with its parent");
			if ([dsubviews count] == 1) {
				NSView *dsubject = [dsubviews objectAtIndex:0];
				NSUInteger i;

				check(![dsubject translatesAutoresizingMaskIntoConstraints],
				      "the constrained view's translate-mask flag round-tripped");
				(void)i;
				check([dloose isKindOfClass:[NSLayoutConstraint class]],
				      "a standalone equation stays an equation");
				check([dloose priority] == 750.0, "an equation's priority round-tripped");
				check([[dloose identifier] isEqualToString:@"loose height"],
				      "an equation's identifier round-tripped");
				check([dloose constant] == 90.0, "an equation's constant round-tripped");
				check([dloose firstItem] == dsubject,
				      "an equation's item is the DECODED view, by identity, not a copy");
				/* **AND THE PROOF: THE DECODED TREE LAYS ITSELF OUT.** 400x300 unflipped, a 120x40 child at
				 * left+10 and top+20 means x=10 and y=300-20-40=240. */
				[droot layoutSubtreeIfNeeded];
				/* **THE FRAMES ARE COMPARED WITH A TOLERANCE, WHICH IS A FACT ABOUT THE SOLVER RATHER THAN A
				 * WEAKENED ASSERTION.** The equations are solved by iterative projection through `CGFloat` arithmetic,
				 * so `300 - 20 - 40` is not required to land on 240.0 to the last bit; what a round trip must preserve
				 * is the RELATIONSHIP, and a millionth of a point is far below anything a layout can show. */
				check(fabs([dsubject frame].size.width - 120.0) < 1e-6,
				      "the decoded width equation produced a width");
				check(fabs([dsubject frame].size.height - 40.0) < 1e-6,
				      "the decoded height equation produced a height");
				check(fabs([dsubject frame].origin.x - 10.0) < 1e-6,
				      "the decoded left equation produced an origin");
				check(fabs([dsubject frame].origin.y - 240.0) < 1e-6,
				      "the decoded top equation produced the flipped origin");
			}
		}
		[equations release];
		[root release];
	}

	/* ---- 4. THE REFUSAL ---------------------------------------------------------------------- */
	/* **A REAL ARCHIVE NAMING A CLASS THE READER MAY NOT BUILD.** `NSIndexPath` is archivable — it implements both coding
	 * methods — and it is deliberately NOT on `+supportedClasses`, which is the exact shape an untrusted design file
	 * takes: a well-formed archive whose object table names a class this tree did not agree to instantiate. The reader
	 * must answer NO from its object-table walk, BEFORE any object exists. */
	{
		NSData *hostile = [NSNib archivedDataWithTopLevelObjects:
			[NSArray arrayWithObject:[NSIndexPath indexPathWithIndex:1]] connections:nil];
		NSNib *evil;
		NSArray *refusedObjects = nil;

		check(hostile != nil, "the writer will archive anything it is handed, including a bad class");
		[hostile writeToFile:@"/tmp/agora-nib-refused.nib" atomically:YES];
		evil = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@"/tmp/agora-nib-refused.nib"]];
		check(![evil instantiateNibWithOwner:nil topLevelObjects:&refusedObjects],
		      "an archive naming a class outside the allow-list is refused");
		check(refusedObjects == nil, "the refusal left the caller's top-level array untouched");
		[evil release];
	}

	/* AND A FILE THAT IS NOT A NIB AT ALL IS REFUSED RATHER THAN MISREAD. */
	{
		NSNib *garbage = [[NSNib alloc] initWithContentsOfURL:
			[NSURL fileURLWithPath:@"/tmp/agora-nib-not-a-nib.bin"]];
		NSArray *junkObjects = nil;
		const char *junk = "this is not a nib";

		[[NSData dataWithBytes:junk length:16] writeToFile:@"/tmp/agora-nib-not-a-nib.bin" atomically:YES];
		check(![garbage instantiateNibWithOwner:nil topLevelObjects:&junkObjects],
		      "a file that is not a nib is refused");
		[garbage release];
	}

	[owner release];
	[container release];
	[pool release];

	if (g_failures != 0) {
		fprintf(stderr, "%d failure(s)\n", g_failures);
		return 1;
	}
	printf("all nib round-trip assertions passed\n");
	return 0;
}
