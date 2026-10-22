/*
 * NSLayoutConstraint.h — Auto Layout's equation, its two vocabularies and its priority scale.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THIS IS A DELIBERATE POST-10.6 SLICE, AND IT SAYS SO RATHER THAN PRETENDING OTHERWISE.** The era pins this tier
 * is measured against are 10.2/10.5/10.6, and Auto Layout is 10.7's: the class, the attributes and the priorities in
 * this header did not exist in the SDK the rest of the AppKit is checked against. It is included because the reason
 * the class exists — a view's geometry stated as RELATIONSHIPS rather than as arithmetic performed in a resize hook
 * — is a reason a client of this tier has, and because this tree already carries one 10.7 class (`NSDraggingSession`)
 * on the same terms: the artefact is read, not guessed, and the vintage deviation is recorded where a reader meets
 * it. Everything this header declares is implemented; what is NOT here is listed at the bottom of the file rather
 * than stubbed into a silent no-op.
 *
 * THE EQUATION IS APPLE'S, AND IT IS WORTH STATING IN ONE PLACE because every door below is a spelling of it:
 *
 *     firstItem.firstAttribute  relation  multiplier × secondItem.secondAttribute + constant
 *
 * `relation` is `=`, `<=` or `>=`. A constraint with no second item is the same equation with the second side zero,
 * so `width == 120` is `first.width == 120`. `multiplier` is 1 and `constant` is 0 unless a caller says otherwise.
 * PRIORITY turns an equation into a preference: 1000 (`NSLayoutPriorityRequired`) is a demand the engine must meet,
 * and anything below it is a wish that is traded against the other wishes by its number.
 *
 * WHAT THIS SLICE DELIBERATELY DOES NOT HAVE, so a caller meets the absence here rather than at a link error:
 *
 *   * `+constraintsWithVisualFormat:` and the `NSLayoutFormatOptions` word — the visual format language is a parser,
 *     not a constraint, and it is a slice of its own;
 *   * the MARGIN attributes (`NSLayoutAttributeLeftMargin` and its siblings) and the `-layoutMargins` furniture they
 *     are measured from;
 *   * `NSLayoutGuide` and `NSLayoutAnchor`'s guide support — this tier's anchors attach to an `NSView` and nothing
 *     else;
 *   * `NSCoding` conformance. A constraint is an equation over live objects, and this tier has no nib to archive one
 *     into.
 *
 * AND THE BASELINE ATTRIBUTES ARE DECLARED BUT NOT SOLVED. `NSLayoutAttributeBaseline` and `FirstBaseline` are in
 * the enum because Apple's header puts them there and a ported caller may name them; the engine refuses a constraint
 * that uses one BY NAME, because a baseline is a font's answer and this tier's `NSView` has no font to ask.
 */
#ifndef APPKIT_NSLAYOUTCONSTRAINT_H
#define APPKIT_NSLAYOUTCONSTRAINT_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@class NSView;

/* ============================================================================================ *
 * THE TWO VOCABULARIES AND THE PRIORITY SCALE.                                                  *
 * ============================================================================================ */

/* **THE RELATION'S VALUES ARE THE ORDERING, NOT A SEQUENCE**, which is what lets an implementation clamp a relation
 * without a table: less-than is -1, equal is 0, greater-than is 1. The names and values are Apple's. */
typedef enum {
	NSLayoutRelationLessThanOrEqual = -1,
	NSLayoutRelationEqual = 0,
	NSLayoutRelationGreaterThanOrEqual = 1
} NSLayoutRelation;

/* **THE ATTRIBUTE NUMBERS ARE APPLE'S, INCLUDING THE GAP AT 0**, and a caller may rely on that: `NotAnAttribute` is
 * the absence of a side (the single-item constraint), and `Baseline` is an ALIAS of `LastBaseline` rather than a
 * second value — Apple spells both names for the same number, and so does this enum. */
typedef enum {
	NSLayoutAttributeNotAnAttribute = 0,
	NSLayoutAttributeLeft = 1,
	NSLayoutAttributeRight = 2,
	NSLayoutAttributeTop = 3,
	NSLayoutAttributeBottom = 4,
	NSLayoutAttributeLeading = 5,
	NSLayoutAttributeTrailing = 6,
	NSLayoutAttributeWidth = 7,
	NSLayoutAttributeHeight = 8,
	NSLayoutAttributeCenterX = 9,
	NSLayoutAttributeCenterY = 10,
	NSLayoutAttributeLastBaseline = 11,
	NSLayoutAttributeBaseline = NSLayoutAttributeLastBaseline,
	NSLayoutAttributeFirstBaseline = 12
} NSLayoutAttribute;

/* **THE ORIENTATION IS THE WORD THE INTRINSIC-SIZE PRIORITIES ARE INDEXED BY**, and it belongs here because Apple
 * declares it here: a view's content hugging and compression resistance are asked per axis with this type. */
typedef enum {
	NSLayoutConstraintOrientationHorizontal = 0,
	NSLayoutConstraintOrientationVertical = 1
} NSLayoutConstraintOrientation;

/* AND THE PRIORITIES ARE FLOATS RATHER THAN AN ENUM, because a caller may write 749.5 and mean it. The seven named
 * values are Apple's, and the four that a client actually names are the first, third and fourth: Required is the
 * engine's hard constraint, DefaultHigh is what a control's compression resistance is, and DefaultLow is what its
 * content hugging is. */
typedef float NSLayoutPriority;

extern const NSLayoutPriority NSLayoutPriorityRequired;
extern const NSLayoutPriority NSLayoutPriorityDefaultHigh;
extern const NSLayoutPriority NSLayoutPriorityDragThatCanResizeWindow;
extern const NSLayoutPriority NSLayoutPriorityWindowSizeStayPut;
extern const NSLayoutPriority NSLayoutPriorityDragThatCannotResizeWindow;
extern const NSLayoutPriority NSLayoutPriorityDefaultLow;
extern const NSLayoutPriority NSLayoutPriorityFittingSizeCompression;

/* ============================================================================================ *
 * THE CONSTRAINT.                                                                               *
 * ============================================================================================ */

@interface NSLayoutConstraint : NSObject <NSSecureCoding>
{
	/* THE TWO SIDES ARE BORROWED, as a view's superview is: a constraint is a statement ABOUT views, and retaining
	 * them would let one equation keep a whole window alive after the window let go. The OWNER — the view whose
	 * `-constraints` array holds this — does retain it, and clears these links when it is deallocated. */
	id _firstItem;
	id _secondItem;
	NSLayoutAttribute _firstAttribute;
	NSLayoutAttribute _secondAttribute;
	NSLayoutRelation _relation;
	CGFloat _multiplier;
	CGFloat _constant;
	NSLayoutPriority _priority;
	NSString *_identifier;
	BOOL _active;
	/* THE VIEW WHOSE ARRAY HOLDS THIS, BORROWED. It is how `-setActive:NO` finds the array to remove itself from;
	 * `-addConstraint:` and `-removeConstraint:` maintain it, and it is nil while the constraint is inactive. */
	NSView *_owner;
}

/* THE DESIGNATED DOOR. The only way to make a constraint, and the only place the equation's shape is checked:
 * `view2` nil means `attr2` is `NotAnAttribute`, and a non-nil `view2` with `NotAnAttribute` is the caller's
 * mistake. `multiplier` and `constant` are taken as given — the engine, not the constructor, decides what they
 * mean for each attribute. */
+ (instancetype)constraintWithItem:(id)view1
			 attribute:(NSLayoutAttribute)attr1
			 relatedBy:(NSLayoutRelation)relation
			    toItem:(nullable id)view2
			 attribute:(NSLayoutAttribute)attr2
			multiplier:(CGFloat)multiplier
			  constant:(CGFloat)c;

/* THE TWO SIDES, ANSWERED AS THEY WERE GIVEN. `-firstItem` and `-secondItem` are `id` because Apple's are: a layout
 * guide is an item too, even though this tier has no guide to hand one. */
@property (nullable, readonly, assign) id firstItem;
@property (nullable, readonly, assign) id secondItem;
@property (readonly) NSLayoutAttribute firstAttribute;
@property (readonly) NSLayoutAttribute secondAttribute;
@property (readonly) NSLayoutRelation relation;
@property (readonly) CGFloat multiplier;
@property (readonly) CGFloat constant;
/* THE PRIORITY IS WRITABLE ON A LIVE CONSTRAINT, which is Apple's contract and the reason a caller can promote a
 * wish to a demand without rebuilding it. */
@property NSLayoutPriority priority;
/* THE IDENTIFIER IS A LABEL FOR THE LOG, copied as Apple's is. */
@property (nullable, copy) NSString *identifier;

/* **ACTIVATION IS THE OWNERSHIP MOVE.** A constraint that is active is held by the view that represents its
 * items' common ancestor (a single-item constraint belongs to the item's superview), and that view's layout pass
 * is where it is solved. Inactive constraints are equations nobody is evaluating. Asking for YES twice is a no-op,
 * and asking for NO removes the constraint from its owner and releases the two borrowed links. */
@property (getter=isActive) BOOL active;

/* AND THE ARRAY FORMS ARE THE SAME TWO MOVES ON A LIST, which is how a caller adds a screenful without a loop of
 * its own. Each constraint goes to the owner its own items imply; one that cannot be owned by a view is REFUSED by
 * name and left inactive. */
+ (void)activateConstraints:(NSArray *)constraints;
+ (void)deactivateConstraints:(NSArray *)constraints;

/* ============================================================================================ *
 * THE TIER'S OWN DOORS.                                                                          *
 * ============================================================================================ */

/* **THE OWNER IS MAINTAINED BY THE VIEW, NOT BY THE CALLER**, and these two doors exist because `NSView` and the
 * solver live in different files. `-cg_setOwner:` is what `-addConstraint:` and `-removeConstraint:` call; it does
 * NOT add or remove the constraint from anyone's array, so it cannot re-enter the view's bookkeeping. */
- (nullable NSView *)cg_owner;
- (void)cg_setOwner:(nullable NSView *)owner;

/* AND THE FLAG IS SET BY THE OWNER WHILE IT IS ADDING OR REMOVING, so activation cannot recurse through
 * `-addConstraint:`. This is the write half of `-isActive`, and it maintains the process-wide count above. */
- (void)cg_setActiveFlag:(BOOL)flag;

/* **AND THE COUNT IS THE FAST PATH'S QUESTION.** A frame set with no active constraint in the process cannot need a
 * layout pass, and asking the count is one load rather than a walk of every view in a window. */
+ (NSUInteger)cg_activeConstraintCount;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLAYOUTCONSTRAINT_H */
