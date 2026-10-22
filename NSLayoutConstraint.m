/*
 * NSLayoutConstraint.m — the equation, its activation, and the owner it is solved by.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * THE CLASS DOES NOT SOLVE ANYTHING. It is a value — two sides, a relation, a multiplier, a constant and a
 * priority — and the engine in `NSLayoutSolver.m` is what turns a window's worth of these into frames. Keeping
 * the two apart is what makes the equation testable without a tree and the solver testable without a caller: a
 * probe can build the exact constraint it means and read every field back, and the solver can be handed constraints
 * whose arithmetic does not depend on who constructed them.
 *
 * THE ACTIVE FLAG IS OWNERSHIP. `-setActive:YES` finds the view whose `-constraints` array represents the items'
 * common ancestor and hands the constraint to it; the view retains it, records itself as the owner, and marks its
 * subtree for a layout pass. `-setActive:NO` is the reverse, and it is the ONLY place the borrowed item links are
 * cleared. A constraint that cannot find a common ancestor is refused BY NAME and left inactive: an equation about
 * two views in different windows (or in no window at all) has no coordinate system in which both sides exist, and
 * pretending it was added would hide the caller's mistake.
 */
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSView.h>

#include <stdio.h>

const NSLayoutPriority NSLayoutPriorityRequired = 1000.0f;
const NSLayoutPriority NSLayoutPriorityDefaultHigh = 750.0f;
const NSLayoutPriority NSLayoutPriorityDragThatCanResizeWindow = 510.0f;
const NSLayoutPriority NSLayoutPriorityWindowSizeStayPut = 500.0f;
const NSLayoutPriority NSLayoutPriorityDragThatCannotResizeWindow = 490.0f;
const NSLayoutPriority NSLayoutPriorityDefaultLow = 250.0f;
const NSLayoutPriority NSLayoutPriorityFittingSizeCompression = 50.0f;

/* **THE PROCESS-WIDE COUNT IS THE FAST PATH, NOT A LEDGER.** `NSView -setFrameSize:` asks it before it considers a
 * layout pass: with no active constraint anywhere there is nothing a pass could change, and the answer is one load
 * rather than a walk of every view in every window. It is maintained by the active flag below, which is the one
 * place activation changes. */
static NSUInteger s_activeConstraintCount;

static BOOL fn_is_view(id item)
{
	return [item isKindOfClass:[NSView class]];
}

static const char *fn_attribute_name(NSLayoutAttribute attribute)
{
	switch (attribute) {
	case NSLayoutAttributeNotAnAttribute: return "notAnAttribute";
	case NSLayoutAttributeLeft: return "left";
	case NSLayoutAttributeRight: return "right";
	case NSLayoutAttributeTop: return "top";
	case NSLayoutAttributeBottom: return "bottom";
	case NSLayoutAttributeLeading: return "leading";
	case NSLayoutAttributeTrailing: return "trailing";
	case NSLayoutAttributeWidth: return "width";
	case NSLayoutAttributeHeight: return "height";
	case NSLayoutAttributeCenterX: return "centerX";
	case NSLayoutAttributeCenterY: return "centerY";
	case NSLayoutAttributeLastBaseline: return "lastBaseline";
	case NSLayoutAttributeFirstBaseline: return "firstBaseline";
	}
	return "?";
}

static const char *fn_relation_name(NSLayoutRelation relation)
{
	switch (relation) {
	case NSLayoutRelationLessThanOrEqual: return "<=";
	case NSLayoutRelationEqual: return "==";
	case NSLayoutRelationGreaterThanOrEqual: return ">=";
	}
	return "?";
}

/* **THE OWNER IS THE COMMON ANCESTOR, AND A SINGLE-ITEM CONSTRAINT BELONGS TO THE ITEM'S SUPERVIEW.** The second
 * rule is Apple's in effect: `width == 120` is a statement about the item in its parent's layout, and the parent
 * is the view whose pass has the item's frame in hand. A view with no superview owns its own single-item
 * constraint, which makes the constraint inert rather than lost — the solver's root has no variables, and says so. */
static NSView *fn_owner_for_items(id view1, id view2)
{
	NSView *a = fn_is_view(view1) ? (NSView *)view1 : nil;
	NSView *b = fn_is_view(view2) ? (NSView *)view2 : nil;

	if (a == nil) {
		return nil;
	}
	if (b == nil) {
		NSView *superview = [a superview];

		return (superview != nil) ? superview : a;
	}
	return [a ancestorSharedWithView:b];
}

@implementation NSLayoutConstraint

/* ============================================================================================
 * ARCHIVING: THE EQUATION, ITS TWO SIDES AND ITS PRIORITY — AND NOT ITS OWNER.
 * ============================================================================================ */

/* **`_owner` IS A BACK-LINK AND IS ABSENT, BECAUSE OWNERSHIP IS AN ACT RATHER THAN A VALUE.** A constraint is owned by the
 * view whose `-addConstraint:` was called, and that door also sets `_active`; a decoder that restored the owner field
 * directly would leave a constraint the pass never gathers. So the archive carries the EQUATION and the view that owns
 * it re-establishes the rest when it adopts it — the same rule a view's superview and a menu item's menu follow.
 *
 * `_active` IS archived even so, because a constraint can exist unowned: a design file may carry an equation that is
 * deactivated, and a decoded one that came back active without an owner would be a constraint the solver could not find. */
static NSString * const AGCoderConstraintFirstItemKey = @"firstItem";
static NSString * const AGCoderConstraintSecondItemKey = @"secondItem";
static NSString * const AGCoderConstraintFirstAttributeKey = @"firstAttribute";
static NSString * const AGCoderConstraintSecondAttributeKey = @"secondAttribute";
static NSString * const AGCoderConstraintRelationKey = @"relation";
static NSString * const AGCoderConstraintMultiplierKey = @"multiplier";
static NSString * const AGCoderConstraintConstantKey = @"constant";
static NSString * const AGCoderConstraintPriorityKey = @"priority";
static NSString * const AGCoderConstraintIdentifierKey = @"identifier";
static NSString * const AGCoderConstraintActiveKey = @"active";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	/* THE ITEMS ARE ENCODED AS OBJECTS AND NOT AS REFERENCES, which is what makes a constraint's tree implicit: whichever
	 * views the equation names are pulled into the same archive, once, and come back as the same objects. */
	[aCoder encodeObject:_firstItem forKey:AGCoderConstraintFirstItemKey];
	[aCoder encodeObject:_secondItem forKey:AGCoderConstraintSecondItemKey];
	[aCoder encodeInteger:(NSInteger)_firstAttribute forKey:AGCoderConstraintFirstAttributeKey];
	[aCoder encodeInteger:(NSInteger)_secondAttribute forKey:AGCoderConstraintSecondAttributeKey];
	[aCoder encodeInteger:(NSInteger)_relation forKey:AGCoderConstraintRelationKey];
	[aCoder encodeDouble:(double)_multiplier forKey:AGCoderConstraintMultiplierKey];
	[aCoder encodeDouble:(double)_constant forKey:AGCoderConstraintConstantKey];
	[aCoder encodeDouble:(double)_priority forKey:AGCoderConstraintPriorityKey];
	[aCoder encodeObject:_identifier forKey:AGCoderConstraintIdentifierKey];
	[aCoder encodeBool:_active forKey:AGCoderConstraintActiveKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* **THE TWO ITEMS ARE ASSIGNED AND NOT RETAINED, WHICH IS THIS CLASS'S OWN CONTRACT.** Apple's properties are
	 * `assign` — a constraint does not own the views it relates — and an archive that retained them would turn every
	 * equation into an owner. The graph that decoded them keeps them alive. */
	_firstItem = [aDecoder decodeObjectForKey:AGCoderConstraintFirstItemKey];
	_secondItem = [aDecoder decodeObjectForKey:AGCoderConstraintSecondItemKey];
	if ([aDecoder containsValueForKey:AGCoderConstraintFirstAttributeKey]) {
		_firstAttribute = (NSLayoutAttribute)[aDecoder decodeIntegerForKey:AGCoderConstraintFirstAttributeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderConstraintSecondAttributeKey]) {
		_secondAttribute = (NSLayoutAttribute)[aDecoder decodeIntegerForKey:AGCoderConstraintSecondAttributeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderConstraintRelationKey]) {
		_relation = (NSLayoutRelation)[aDecoder decodeIntegerForKey:AGCoderConstraintRelationKey];
	}
	if ([aDecoder containsValueForKey:AGCoderConstraintMultiplierKey]) {
		_multiplier = (CGFloat)[aDecoder decodeDoubleForKey:AGCoderConstraintMultiplierKey];
	} else {
		_multiplier = 1.0;
	}
	if ([aDecoder containsValueForKey:AGCoderConstraintConstantKey]) {
		_constant = (CGFloat)[aDecoder decodeDoubleForKey:AGCoderConstraintConstantKey];
	}
	if ([aDecoder containsValueForKey:AGCoderConstraintPriorityKey]) {
		_priority = (NSLayoutPriority)[aDecoder decodeDoubleForKey:AGCoderConstraintPriorityKey];
	}
	if ([aDecoder containsValueForKey:AGCoderConstraintIdentifierKey]) {
		_identifier = [[aDecoder decodeObjectForKey:AGCoderConstraintIdentifierKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderConstraintActiveKey]) {
		_active = [aDecoder decodeBoolForKey:AGCoderConstraintActiveKey];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

+ (instancetype)constraintWithItem:(id)view1
			 attribute:(NSLayoutAttribute)attr1
			 relatedBy:(NSLayoutRelation)relation
			    toItem:(id)view2
			 attribute:(NSLayoutAttribute)attr2
			multiplier:(CGFloat)multiplier
			  constant:(CGFloat)c
{
	NSLayoutConstraint *constraint = [[[self alloc] init] autorelease];

	/* THE SHAPE IS CHECKED HERE BECAUSE THIS IS THE ONLY DOOR THAT CAN SEE BOTH SIDES AT ONCE.** A second item
	 * with `NotAnAttribute` is not a single-item constraint; it is a caller who meant one and passed the other, and
	 * the solver would have to guess which half to believe. The equation is still built (so the caller can inspect
	 * what it asked for) but the refusal is named and it will not activate. */
	if (view2 == nil && attr2 != NSLayoutAttributeNotAnAttribute) {
		fprintf(stderr, "APPKIT-REFUSE: +[NSLayoutConstraint constraintWithItem:...] was given a nil second item "
				"with attribute %s; a single-item constraint names NotAnAttribute for its second side\n",
			fn_attribute_name(attr2));
	} else if (view2 != nil && attr2 == NSLayoutAttributeNotAnAttribute) {
		fprintf(stderr, "APPKIT-REFUSE: +[NSLayoutConstraint constraintWithItem:...] was given a second item "
				"with NotAnAttribute; name the attribute or pass nil for the item\n");
	}
	if (attr1 == NSLayoutAttributeNotAnAttribute) {
		fprintf(stderr, "APPKIT-REFUSE: +[NSLayoutConstraint constraintWithItem:...] was given no first "
				"attribute; an equation needs a left-hand side\n");
	}
	if (multiplier == 0.0) {
		/* APPLE REFUSES THIS TOO, and the reason is arithmetic rather than taste: `first = 0 * second + c` does
		 * not depend on the second side at all, so the caller either meant a single-item constraint or made a
		 * mistake. It is refused by name and multiplication is left as the caller wrote it. */
		fprintf(stderr, "APPKIT-REFUSE: +[NSLayoutConstraint constraintWithItem:...] was given a zero "
				"multiplier; the second side would not take part in the equation\n");
	}

	constraint->_firstItem = view1;
	constraint->_secondItem = view2;
	constraint->_firstAttribute = attr1;
	constraint->_secondAttribute = (view2 == nil) ? NSLayoutAttributeNotAnAttribute : attr2;
	constraint->_relation = relation;
	constraint->_multiplier = multiplier;
	constraint->_constant = c;
	constraint->_priority = NSLayoutPriorityRequired;
	constraint->_identifier = nil;
	constraint->_active = NO;
	constraint->_owner = nil;
	return constraint;
}

- (id)firstItem
{
	return _firstItem;
}

- (id)secondItem
{
	return _secondItem;
}

- (NSLayoutAttribute)firstAttribute
{
	return _firstAttribute;
}

- (NSLayoutAttribute)secondAttribute
{
	return _secondAttribute;
}

- (NSLayoutRelation)relation
{
	return _relation;
}

- (CGFloat)multiplier
{
	return _multiplier;
}

- (CGFloat)constant
{
	return _constant;
}

- (NSLayoutPriority)priority
{
	return _priority;
}

- (void)setPriority:(NSLayoutPriority)priority
{
	/* A NEGATIVE OR NAN PRIORITY IS NOT A PREFERENCE, so it is clamped to zero rather than passed to a solver that
	 * would have to decide what `-4` means. Required is the ceiling; Apple's engine rejects anything above it, and
	 * clamping is the same decision made once instead of at every comparison. */
	if (!(priority > 0.0f)) {
		priority = 0.0f;
	}
	if (priority > NSLayoutPriorityRequired) {
		priority = NSLayoutPriorityRequired;
	}
	_priority = priority;
}

- (NSString *)identifier
{
	return _identifier;
}

- (void)setIdentifier:(NSString *)identifier
{
	if (identifier == _identifier) {
		return;
	}
	[_identifier release];
	_identifier = [identifier copy];
}

- (BOOL)isActive
{
	return _active;
}

- (void)cg_setActiveFlag:(BOOL)flag
{
	if (flag == _active) {
		return;
	}
	_active = flag;
	if (flag) {
		s_activeConstraintCount++;
	} else {
		s_activeConstraintCount--;
	}
}

- (NSView *)cg_owner
{
	return _owner;
}

- (void)cg_setOwner:(NSView *)owner
{
	_owner = owner;	/* BORROWED — see the header. */
}

- (void)setActive:(BOOL)flag
{
	if (flag == _active) {
		return;
	}
	if (!flag) {
		/* THE OWNER REMOVES IT, because the owner is what holds the array. Clearing the flag here would leave a
		 * retained constraint in a view's list that no pass would solve — the worst of both states. */
		if (_owner != nil) {
			[_owner removeConstraint:self];
		} else {
			[self cg_setActiveFlag:NO];
			_firstItem = nil;
			_secondItem = nil;
		}
		return;
	}

	/* **THE TWO ITEMS MUST BE VIEWS, AND THE BASELINE IS REFUSED HERE RATHER THAN IN THE SOLVER.** A caller learns
	 * why at the door that activated the equation, not at a later layout pass that silently ignored it. */
	if (_firstItem != nil && !fn_is_view(_firstItem)) {
		fprintf(stderr, "APPKIT-REFUSE: NSLayoutConstraint %p names a first item that is not an NSView; this tier's "
				"Auto Layout has views as items and no layout guides\n", self);
		return;
	}
	if (_secondItem != nil && !fn_is_view(_secondItem)) {
		fprintf(stderr, "APPKIT-REFUSE: NSLayoutConstraint %p names a second item that is not an NSView; this tier's "
				"Auto Layout has views as items and no layout guides\n", self);
		return;
	}
	if (_firstAttribute == NSLayoutAttributeLastBaseline || _firstAttribute == NSLayoutAttributeFirstBaseline ||
	    _secondAttribute == NSLayoutAttributeLastBaseline || _secondAttribute == NSLayoutAttributeFirstBaseline) {
		fprintf(stderr, "APPKIT-REFUSE: NSLayoutConstraint %p uses a baseline attribute; a baseline is a font's "
				"answer and this tier's views have no font, so the equation is left inactive\n", self);
		return;
	}
	{
		NSView *owner = fn_owner_for_items(_firstItem, _secondItem);

		if (owner == nil) {
			fprintf(stderr, "APPKIT-REFUSE: NSLayoutConstraint %p relates views with no common ancestor; there is no "
					"coordinate system in which both sides exist, so it is left inactive\n", self);
			return;
		}
		[owner addConstraint:self];	/* which calls -cg_setOwner: and -cg_setActiveFlag:YES */
	}
}

+ (void)activateConstraints:(NSArray *)constraints
{
	NSUInteger i;

	for (i = 0; i < [constraints count]; i++) {
		[[constraints objectAtIndex:i] setActive:YES];
	}
}

+ (void)deactivateConstraints:(NSArray *)constraints
{
	NSUInteger i;

	for (i = 0; i < [constraints count]; i++) {
		[[constraints objectAtIndex:i] setActive:NO];
	}
}

+ (NSUInteger)cg_activeConstraintCount
{
	return s_activeConstraintCount;
}

- (BOOL)isEqual:(id)other
{
	NSLayoutConstraint *c;

	if (other == self) {
		return YES;
	}
	if (![other isKindOfClass:[NSLayoutConstraint class]]) {
		return NO;
	}
	c = other;
	return c->_firstItem == _firstItem && c->_secondItem == _secondItem &&
	       c->_firstAttribute == _firstAttribute && c->_secondAttribute == _secondAttribute &&
	       c->_relation == _relation && c->_multiplier == _multiplier && c->_constant == _constant &&
	       c->_priority == _priority;
}

- (NSUInteger)hash
{
	/* THE SIDES DOMINATE, which is what makes two constraints in a dictionary collide for the same reason a caller
	 * would consider them the same equation. The constant is mixed in last so `left == 10` and `left == 20` differ. */
	NSUInteger h = (NSUInteger)(uintptr_t)_firstItem;

	h = h * 31u + (NSUInteger)(uintptr_t)_secondItem;
	h = h * 31u + (NSUInteger)_firstAttribute;
	h = h * 31u + (NSUInteger)_secondAttribute;
	h = h * 31u + (NSUInteger)_relation;
	h = h * 31u + (NSUInteger)_constant;
	return h;
}

- (NSString *)description
{
	NSMutableString *s = [NSMutableString stringWithFormat:@"<NSLayoutConstraint %p", self];

	if (_identifier != nil) {
		[s appendFormat:@" \"%@\"", _identifier];
	}
	[s appendFormat:@": %@.%@ %s", _firstItem, [NSString stringWithUTF8String:fn_attribute_name(_firstAttribute)],
		fn_relation_name(_relation)];
	if (_secondItem != nil) {
		[s appendFormat:@" %g * %@.%@", (double)_multiplier, _secondItem,
			[NSString stringWithUTF8String:fn_attribute_name(_secondAttribute)]];
	}
	[s appendFormat:@" + %g (priority %g)", (double)_constant, (double)_priority];
	if (_active) {
		[s appendString:@", active"];
	}
	[s appendString:@">"];
	return s;
}

- (void)dealloc
{
	[_identifier release];
	[super dealloc];
}

@end
