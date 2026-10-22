/*
 * NSLayoutAnchor.m — two views, one attribute each, and the equation between them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * EVERY DOOR HERE IS A CALL TO `+[NSLayoutConstraint constraintWithItem:...]`. That is deliberate rather than
 * incidental: the constructor is where the equation's shape is checked and where the refusal messages live, so an
 * anchor cannot smuggle in a malformed constraint by being convenient. The base class owns the comparison with a
 * constant; `NSLayoutDimension` owns the multiplier, because a width may be a multiple of another width and an axis
 * may not.
 */
#import <AppKit/NSLayoutAnchor.h>
#import <AppKit/NSLayoutAnchor_internal.h>
#import <AppKit/NSView.h>

static const char *fn_anchor_attribute_name(NSLayoutAttribute attribute)
{
	switch (attribute) {
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
	default: return "notAnAttribute";
	}
}

@implementation NSLayoutAnchor

- (instancetype)cg_initWithItem:(NSView *)item attribute:(NSLayoutAttribute)attribute
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_item = item;	/* BORROWED */
	_attribute = attribute;
	return self;
}

+ (instancetype)cg_anchorWithItem:(NSView *)item attribute:(NSLayoutAttribute)attribute
{
	return [[[self alloc] cg_initWithItem:item attribute:attribute] autorelease];
}

- (NSView *)cg_item
{
	return _item;
}

- (NSLayoutAttribute)cg_attribute
{
	return _attribute;
}

- (NSString *)name
{
	return [NSString stringWithUTF8String:fn_anchor_attribute_name(_attribute)];
}

- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)anchor
{
	return [self constraintEqualToAnchor:anchor constant:0.0];
}

- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)anchor
{
	return [self constraintGreaterThanOrEqualToAnchor:anchor constant:0.0];
}

- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)anchor
{
	return [self constraintLessThanOrEqualToAnchor:anchor constant:0.0];
}

- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)anchor constant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:NSLayoutRelationEqual
					       toItem:[anchor cg_item]
					    attribute:[anchor cg_attribute]
					   multiplier:1.0
					     constant:c];
}

- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)anchor constant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:(NSLayoutRelation)NSLayoutRelationGreaterThanOrEqual
					       toItem:[anchor cg_item]
					    attribute:[anchor cg_attribute]
					   multiplier:1.0
					     constant:c];
}

- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)anchor constant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:(NSLayoutRelation)NSLayoutRelationLessThanOrEqual
					       toItem:[anchor cg_item]
					    attribute:[anchor cg_attribute]
					   multiplier:1.0
					     constant:c];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %@.%@>", NSStringFromClass([self class]), self, _item,
		[self name]];
}

@end

@implementation NSLayoutXAxisAnchor
@end

@implementation NSLayoutYAxisAnchor
@end

@implementation NSLayoutDimension

- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:NSLayoutRelationEqual
					       toItem:nil
					    attribute:NSLayoutAttributeNotAnAttribute
					   multiplier:1.0
					     constant:c];
}

- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:NSLayoutRelationGreaterThanOrEqual
					       toItem:nil
					    attribute:NSLayoutAttributeNotAnAttribute
					   multiplier:1.0
					     constant:c];
}

- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:NSLayoutRelationLessThanOrEqual
					       toItem:nil
					    attribute:NSLayoutAttributeNotAnAttribute
					   multiplier:1.0
					     constant:c];
}

- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m
{
	return [self constraintEqualToAnchor:anchor multiplier:m constant:0.0];
}

- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m constant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:NSLayoutRelationEqual
					       toItem:[anchor cg_item]
					    attribute:[anchor cg_attribute]
					   multiplier:m
					     constant:c];
}

- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m
{
	return [self constraintGreaterThanOrEqualToAnchor:anchor multiplier:m constant:0.0];
}

- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)anchor
						 multiplier:(CGFloat)m
						   constant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:NSLayoutRelationGreaterThanOrEqual
					       toItem:[anchor cg_item]
					    attribute:[anchor cg_attribute]
					   multiplier:m
					     constant:c];
}

- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m
{
	return [self constraintLessThanOrEqualToAnchor:anchor multiplier:m constant:0.0];
}

- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)anchor
						multiplier:(CGFloat)m
						  constant:(CGFloat)c
{
	return [NSLayoutConstraint constraintWithItem:_item
					    attribute:_attribute
					    relatedBy:NSLayoutRelationLessThanOrEqual
					       toItem:[anchor cg_item]
					    attribute:[anchor cg_attribute]
					   multiplier:m
					     constant:c];
}

@end
