/*
 * auto_layout — does a constraint become a frame, in the parent's coordinates and both ways up?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THIS IS THE FIRST SLICE OF AUTO LAYOUT, AND ITS SUBJECT IS THE EQUATION RATHER THAN THE API TOUR.** A view's
 * geometry is the four numbers of its frame; a constraint is an equation those numbers must satisfy. The probe
 * therefore builds small trees whose answers can be computed by hand and then asserts the FRAMES — which is the only
 * evidence that the model, the coordinate accumulation through flipped and unflipped ancestors, and the solver's
 * priorities agree with each other.
 *
 * WHAT IS ASSERTED, each a behaviour that did not exist before this slice:
 *
 *   1. The constraint: the two sides, the relation, the multiplier, the constant, the priority and the identifier
 *      read back exactly as given, and priority is clamped to the required ceiling.
 *   2. A width constraint becomes a width, and nothing else moves.
 *   3. Four edge constraints place a child in an UNFLIPPED parent, including the y flip: "top" is the visual top.
 *   4. The same four constraints place it in a FLIPPED parent, where the frame origin's y IS the top.
 *   5. Centre anchors put a view in the middle of its parent.
 *   6. A sibling constraint reads the other sibling's edge, not its origin.
 *   7. A required width beats a higher-than-default optional one.
 *   8. Two optional widths settle between their targets in proportion to their priorities, rather than at whichever
 *      the solver visited last.
 *   9. An intrinsic size sizes a view from one pinned edge, through the hugging/compression pair.
 *  10. A required width overrides the intrinsic compression resistance.
 *  11. `translatesAutoresizingMaskIntoConstraints` YES translates the mask: a sizable view follows its parent.
 *  12. A constraint can relate two views with different parents — cousins — because the forms are accumulated to the
 *      common ancestor.
 *  13. `-updateConstraints` runs in the pass, and `-layout` runs after the frames are written.
 *  14. `+activateConstraints:` owns a constraint at the items' common ancestor, and deactivation removes it.
 *  15. A view named by no constraint is not moved: Auto Layout is opt-in per view, not per window.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSLayoutAnchor.h>
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

static int near(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

static int rect_is(NSRect r, CGFloat x, CGFloat y, CGFloat w, CGFloat h)
{
	return near(r.origin.x, x) && near(r.origin.y, y) && near(r.size.width, w) && near(r.size.height, h);
}

/* A VIEW WITH AN OPINION ABOUT ITS SIZE: the intrinsic-size door is the whole of what it adds, and the engine is
 * expected to turn that into the hugging/compression pair without the view naming a width. */
@interface AGIntrinsicView : NSView
@end

@implementation AGIntrinsicView
- (NSSize)intrinsicContentSize
{
	return NSMakeSize(100.0, 30.0);
}
@end

/* AND A VIEW THAT ADDS ITS CONSTRAINT IN THE UPDATE PASS, which is the hook `-updateConstraints` exists for. It
 * counts the calls as well as adding, so the probe can tell "the pass ran the hook" from "the frame happened to be
 * right". */
@interface AGUpdatingView : NSView
{
@public
	int updates;
	BOOL added;
}
@end

@implementation AGUpdatingView
- (void)updateConstraints
{
	updates++;
	/* ADDED ONCE, BECAUSE THE HOOK RUNS ON EVERY PASS.** A real subclass would add the constraint when the content
	 * that needs it appears and not again; the flag is that discipline in one line. */
	if (!added) {
		added = YES;
		[self addConstraint:[[self widthAnchor] constraintEqualToConstant:70.0]];
	}
	[super updateConstraints];
}
@end

/* AND ONE THAT COUNTS ITS LAYOUT CALLS, to pin the order: `-layout` after the frames, once per requested pass. */
@interface AGLayoutView : NSView
{
@public
	int layouts;
}
@end

@implementation AGLayoutView
- (void)layout
{
	layouts++;
	[super layout];
}
@end

int main(void)
{
	@autoreleasepool {
		/* 1. THE CLASS. */
		{
			NSView *a = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSView *b = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSLayoutConstraint *c = [NSLayoutConstraint constraintWithItem:a
									attribute:NSLayoutAttributeWidth
									relatedBy:NSLayoutRelationEqual
									   toItem:b
									attribute:NSLayoutAttributeHeight
								   multiplier:2.0
								     constant:10.0];

			check([c firstItem] == a && [c secondItem] == b, "a constraint answers the two sides it was given");
			check([c firstAttribute] == NSLayoutAttributeWidth &&
				      [c secondAttribute] == NSLayoutAttributeHeight,
			      "and their two attributes");
			check([c relation] == NSLayoutRelationEqual && near([c multiplier], 2.0) && near([c constant], 10.0),
			      "and the relation, multiplier and constant");
			check([c priority] == NSLayoutPriorityRequired, "a new constraint is REQUIRED");
			[c setPriority:5000.0f];
			check([c priority] == NSLayoutPriorityRequired, "and priority is clamped to the required ceiling");
			[c setPriority:NSLayoutPriorityDefaultHigh];
			check(near([c priority], 750.0), "while a legal priority is kept as given");
			[c setIdentifier:@"probe"];
			check([[c identifier] isEqualToString:@"probe"], "and the identifier is a label, not a side effect");
			check(![c isActive], "a fresh constraint is INACTIVE: building an equation does not add it to a tree");
			[a release];
			[b release];
		}

		/* 2. A WIDTH. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(10.0, 10.0, 50.0, 40.0)];
			NSLayoutConstraint *width;

			[root addSubview:child];
			[child release];
			[child setTranslatesAutoresizingMaskIntoConstraints:NO];
			width = [[child widthAnchor] constraintEqualToConstant:120.0];
			[root addConstraint:width];
			[root layoutSubtreeIfNeeded];
			check(near([child frame].size.width, 120.0), "a width constraint becomes the view's width");
			check(near([child frame].origin.x, 10.0) && near([child frame].origin.y, 10.0),
			      "and an unconstrained position stays where it was");
			check(near([child frame].size.height, 40.0), "and an unconstrained height stays too");
			check([width isActive], "adding a constraint activates it");
			[root removeConstraint:width];
			check(![width isActive], "and removing it deactivates it");
			[root release];
		}

		/* 3. THE FOUR EDGES, UNFLIPPED PARENT. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(1.0, 2.0, 3.0, 4.0)];

			[root addSubview:child];
			[child release];
			[child setTranslatesAutoresizingMaskIntoConstraints:NO];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[child leftAnchor] constraintEqualToAnchor:[root leftAnchor] constant:10.0],
				[[child topAnchor] constraintEqualToAnchor:[root topAnchor] constant:20.0],
				[[child rightAnchor] constraintEqualToAnchor:[root rightAnchor] constant:-10.0],
				[[child bottomAnchor] constraintEqualToAnchor:[root bottomAnchor] constant:-30.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			/* The parent is 300 tall and unflipped, so a visual top at 20 is a frame y of 300-20-height, and a
			 * visual bottom 30 from the bottom is a height of 300-20-30. */
			check(rect_is([child frame], 10.0, 30.0, 380.0, 250.0),
			      "four edges place a child in an unflipped parent, y flip included");
			[root release];
		}

		/* 4. THE SAME FOUR EDGES, FLIPPED PARENT. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(1.0, 2.0, 3.0, 4.0)];

			[root setFlipped:YES];
			[root addSubview:child];
			[child release];
			[child setTranslatesAutoresizingMaskIntoConstraints:NO];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[child leftAnchor] constraintEqualToAnchor:[root leftAnchor] constant:10.0],
				[[child topAnchor] constraintEqualToAnchor:[root topAnchor] constant:20.0],
				[[child widthAnchor] constraintEqualToConstant:100.0],
				[[child heightAnchor] constraintEqualToConstant:50.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			check(rect_is([child frame], 10.0, 20.0, 100.0, 50.0),
			      "in a flipped parent the frame origin's y IS the visual top");
			[root release];
		}

		/* 5. CENTRES. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 50.0)];

			[root addSubview:child];
			[child release];
			[child setTranslatesAutoresizingMaskIntoConstraints:NO];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[child centerXAnchor] constraintEqualToAnchor:[root centerXAnchor]],
				[[child centerYAnchor] constraintEqualToAnchor:[root centerYAnchor]],
				[[child widthAnchor] constraintEqualToConstant:100.0],
				[[child heightAnchor] constraintEqualToConstant:50.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			check(rect_is([child frame], 150.0, 125.0, 100.0, 50.0),
			      "centre anchors put the view in the middle of its parent");
			[root release];
		}

		/* 6. SIBLINGS. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *a = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0)];
			NSView *b = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0)];

			[root addSubview:a];
			[a release];
			[root addSubview:b];
			[b release];
			[a setTranslatesAutoresizingMaskIntoConstraints:NO];
			[b setTranslatesAutoresizingMaskIntoConstraints:NO];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[a leftAnchor] constraintEqualToAnchor:[root leftAnchor]],
				[[a widthAnchor] constraintEqualToConstant:100.0],
				[[b leftAnchor] constraintEqualToAnchor:[a rightAnchor] constant:8.0],
				[[b widthAnchor] constraintEqualToConstant:100.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			check(near([a frame].origin.x, 0.0) && near([b frame].origin.x, 108.0),
			      "a sibling constraint reads the other sibling's EDGE, not its origin");
			[root release];
		}

		/* 7. REQUIRED BEATS OPTIONAL. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSLayoutConstraint *demand = [[child widthAnchor] constraintEqualToConstant:100.0];
			NSLayoutConstraint *wish = [[child widthAnchor] constraintEqualToConstant:200.0];

			[root addSubview:child];
			[child release];
			[child setTranslatesAutoresizingMaskIntoConstraints:NO];
			[wish setPriority:NSLayoutPriorityDefaultHigh];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:demand, wish, nil]];
			[root layoutSubtreeIfNeeded];
			check(near([child frame].size.width, 100.0), "a required width is not traded for a 750 wish");
			[root release];
		}

		/* 8. OPTIONAL AGAINST OPTIONAL, IN PROPORTION. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 10.0)];
			NSLayoutConstraint *strong = [[child widthAnchor] constraintEqualToConstant:200.0];
			NSLayoutConstraint *weak = [[child widthAnchor] constraintEqualToConstant:100.0];

			[root addSubview:child];
			[child release];
			[child setTranslatesAutoresizingMaskIntoConstraints:NO];
			[strong setPriority:NSLayoutPriorityDefaultHigh];
			[weak setPriority:NSLayoutPriorityDefaultLow];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:strong, weak, nil]];
			[root layoutSubtreeIfNeeded];
			/* The 750 wish and the 250 wish are 3:1, so the compromise is 175 — not 100, not 200. */
			check([child frame].size.width > 165.0 && [child frame].size.width < 185.0,
			      "two optional widths settle at their priority ratio, not at the last one visited");
			[root release];
		}

		/* 9. AN INTRINSIC SIZE. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			AGIntrinsicView *child = [[AGIntrinsicView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 5.0, 5.0)];

			[root addSubview:child];
			[child release];
			[child setTranslatesAutoresizingMaskIntoConstraints:NO];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[child leftAnchor] constraintEqualToAnchor:[root leftAnchor] constant:12.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			check(near([child frame].size.width, 100.0) && near([child frame].size.height, 30.0),
			      "an intrinsic size sizes the view from one pinned edge");
			check(near([child frame].origin.x, 12.0), "and the pinned edge is still where it was pinned");
			[root release];
		}

		/* 10. A REQUIRED SIZE OVERRIDES INTRINSIC COMPRESSION. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			AGIntrinsicView *child = [[AGIntrinsicView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 5.0, 5.0)];

			[root addSubview:child];
			[child release];
			[child setTranslatesAutoresizingMaskIntoConstraints:NO];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[child widthAnchor] constraintEqualToConstant:60.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			check(near([child frame].size.width, 60.0), "a required width beats the 750 compression resistance");
			check(near([child frame].size.height, 30.0), "while the unconstrained axis keeps its intrinsic size");
			[root release];
		}

		/* 11. THE TRANSLATED MASK. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
			NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(10.0, 20.0, 50.0, 60.0)];

			[root addSubview:child];
			[child release];
			/* The view keeps the translated flag (YES by default) and its mask says both axes are sizable. The
			 * redundant constraint is what makes it MANAGED; without it the engine would leave its frame alone. */
			[child setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
			[root addConstraint:[[child widthAnchor] constraintGreaterThanOrEqualToConstant:0.0]];
			[root layoutSubtreeIfNeeded];
			check(rect_is([child frame], 10.0, 20.0, 50.0, 60.0), "the mask leaves the initial frame alone");
			[root setFrameSize:NSMakeSize(300.0, 300.0)];
			/* Right gap was 200-(10+50)=140, top gap 200-(20+60)=120, bottom gap 20. */
			check(rect_is([child frame], 10.0, 20.0, 150.0, 160.0),
			      "and a sizable mask follows the parent's new size, keeping its struts");
			[root release];
		}

		/* 12. COUSINS. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *leftParent = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 300.0)];
			NSView *rightParent = [[NSView alloc] initWithFrame:NSMakeRect(100.0, 0.0, 100.0, 300.0)];
			NSView *a = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];
			NSView *b = [[NSView alloc] initWithFrame:NSMakeRect(20.0, 0.0, 20.0, 20.0)];

			[root addSubview:leftParent];
			[leftParent release];
			[root addSubview:rightParent];
			[rightParent release];
			[leftParent addSubview:a];
			[a release];
			[rightParent addSubview:b];
			[b release];
			[a setTranslatesAutoresizingMaskIntoConstraints:NO];
			[b setTranslatesAutoresizingMaskIntoConstraints:NO];
			{
				NSRect bFrame = [b frame];

				bFrame.origin.x = 20.0;
				[b setFrame:bFrame];
			}
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[a leftAnchor] constraintEqualToAnchor:[b leftAnchor] constant:10.0],
				[[b leftAnchor] constraintEqualToAnchor:[rightParent leftAnchor] constant:20.0],
				[[b widthAnchor] constraintEqualToConstant:20.0],
				[[a widthAnchor] constraintEqualToConstant:20.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			/* b's parent sits at x=100 and b is pinned 20 inside it, so b's left is 120 in the common ancestor's
			 * space; a is 10 to the right of that. The frame is still expressed in a's OWN parent: 130. */
			check(near([a frame].origin.x, 130.0) && near([b frame].origin.x, 20.0),
			      "a constraint relates views with different parents through their common ancestor");
			[root release];
		}

		/* 13. THE TWO HOOKS. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			AGUpdatingView *updating = [[AGUpdatingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			AGLayoutView *laidOut = [[AGLayoutView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 40.0)];

			[root addSubview:updating];
			[updating release];
			[root addSubview:laidOut];
			[laidOut release];
			[updating setTranslatesAutoresizingMaskIntoConstraints:NO];
			[laidOut setTranslatesAutoresizingMaskIntoConstraints:NO];
			/* One required constraint makes both views managed; the updating view adds its own width in the update
			 * pass, which is what proves the pass runs before the solve. */
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[updating leftAnchor] constraintEqualToAnchor:[root leftAnchor]],
				[[laidOut leftAnchor] constraintEqualToAnchor:[root leftAnchor]],
				nil]];
			[updating setNeedsUpdateConstraints:YES];
			[laidOut setNeedsLayout:YES];
			[root layoutSubtreeIfNeeded];
			check(updating->updates > 0, "-updateConstraints runs in the layout pass");
			check(near([updating frame].size.width, 70.0), "and the constraint it adds is solved in the same pass");
			check(laidOut->layouts > 0, "-layout runs after the frames are written");
			[root release];
		}

		/* 14. ACTIVATION AND THE COMMON ANCESTOR. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *a = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];
			NSView *b = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];
			NSLayoutConstraint *c;

			[root addSubview:a];
			[a release];
			[root addSubview:b];
			[b release];
			[a setTranslatesAutoresizingMaskIntoConstraints:NO];
			[b setTranslatesAutoresizingMaskIntoConstraints:NO];
			c = [[a rightAnchor] constraintEqualToAnchor:[b leftAnchor] constant:-5.0];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObject:c]];
			check([c isActive] && [c cg_owner] == root, "activation puts the constraint on the items' common ancestor");
			check([[root constraints] indexOfObjectIdenticalTo:c] != NSNotFound, "which is where -constraints finds it");
			[NSLayoutConstraint deactivateConstraints:[NSArray arrayWithObject:c]];
			check(![c isActive] && [[root constraints] indexOfObjectIdenticalTo:c] == NSNotFound,
			      "and deactivation takes it out of that array");
			[root release];
		}

		/* 15. A VIEW NAMED BY NO CONSTRAINT IS NOT MOVED. */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *managed = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSView *bystander = [[NSView alloc] initWithFrame:NSMakeRect(77.0, 33.0, 44.0, 55.0)];

			[root addSubview:managed];
			[managed release];
			[root addSubview:bystander];
			[bystander release];
			[managed setTranslatesAutoresizingMaskIntoConstraints:NO];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[managed widthAnchor] constraintEqualToConstant:90.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			check(near([managed frame].size.width, 90.0), "the managed view is solved");
			check(rect_is([bystander frame], 77.0, 33.0, 44.0, 55.0),
			      "and the view named by no constraint is untouched");
			[root release];
		}

		/* 16. A CONTROL WITH AN INTRINSIC SIZE PINNED TO ALL FOUR EDGES. Its optional hugging and compression
		 * constraints pull on the same x and width as the required leading and trailing pair, which is the case a
		 * one-pass required projection left at a compromise (MEASURED: x=76 in a 700-point parent with an
		 * intrinsic width of 10). */
		{
			NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 700.0, 400.0)];
			NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(17.0, 0.0, 660.0, 22.0)];

			[root addSubview:field];
			[field release];
			[field setTranslatesAutoresizingMaskIntoConstraints:NO];
			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[field leadingAnchor] constraintEqualToAnchor:[root leadingAnchor]],
				[[field trailingAnchor] constraintEqualToAnchor:[root trailingAnchor]],
				[[field bottomAnchor] constraintEqualToAnchor:[root bottomAnchor]],
				[[field heightAnchor] constraintEqualToConstant:22.0],
				nil]];
			[root layoutSubtreeIfNeeded];
			check(rect_is([field frame], 0.0, 0.0, 700.0, 22.0),
			      "required edges win over a control's intrinsic pull on the same axis");
			[root release];
		}
	}

	printf("%s\n", s_failed == 0 ? "auto_layout: all checks passed" : "auto_layout: FAILURES");
	return s_failed == 0 ? 0 : 1;
}
