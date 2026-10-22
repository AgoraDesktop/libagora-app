/*
 * NSLayoutAnchor.h — the constraint factories, one per axis.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **AN ANCHOR IS A VIEW AND ONE ATTRIBUTE, AND NOTHING ELSE.** `[label leadingAnchor]` answers "label's leading
 * edge"; the three comparison doors turn two anchors into the equation in `NSLayoutConstraint.h`. The point of the
 * spelling is type direction: an x-axis anchor compares to another x-axis anchor and a dimension to a dimension, so
 * the sentence a caller writes is the sentence they mean. The compiler checks the class; the engine checks the rest.
 *
 * **THIS IS 10.11'S SURFACE AND IT IS HERE FOR THE SAME RECORDED REASON AS THE CONSTRAINT** — see that header. The
 * anchor door is newer than the class it builds, but a client writing Auto Layout today writes anchors, and a tier
 * that offered only `+constraintWithItem:...` would make every caller spell a five-line equation by hand.
 *
 * THE MULTIPLIER BELONGS TO DIMENSIONS, which is why only `NSLayoutDimension` declares the forms that take one: a
 * width may be twice another width, while "left is twice right" is a relationship no layout means. The constant
 * belongs to every anchor and is on the base class.
 *
 * NOTHING HERE CHECKS THAT THE TWO ANCHORS' ITEMS SHARE A WINDOW.** That check belongs to activation, where the
 * common ancestor is found, and it is stated there rather than duplicated as a weaker test here.
 */
#ifndef APPKIT_NSLAYOUTANCHOR_H
#define APPKIT_NSLAYOUTANCHOR_H

#import <AppKit/NSLayoutConstraint.h>

NS_ASSUME_NONNULL_BEGIN

@class NSView;

@interface NSLayoutAnchor : NSObject
{
	/* BORROWED, as a constraint's two sides are: the view owns its anchors' lifetime use, and an anchor that kept a
	 * view alive would turn `[[v widthAnchor] constraintEqualToConstant:1]` into an owner nobody can see. */
	NSView *_item;
	NSLayoutAttribute _attribute;
}

/* THE THREE COMPARISONS, with the constant on the RIGHT-HAND side of the equation:
 *
 *     self.item.self.attribute  relation  anchor.item.anchor.attribute + c
 */
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)anchor;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)anchor;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)anchor;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)anchor constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)anchor constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)anchor constant:(CGFloat)c;

/* **THE ANCHOR'S NAME IS FOR THE LOG AND THE DESCRIPTION**, not for the engine: it is the attribute's own name, and
 * it is what makes a constraint's `-description` readable when the identifier is nil. */
- (NSString *)name;

/* THE TIER'S OWN DOORS, so the subclasses can build the equation without a public initialiser. */
- (NSView *)cg_item;
- (NSLayoutAttribute)cg_attribute;

@end

/* **THE TWO AXES ADD NO METHODS AND EXIST TO BE TYPES.** `-constraintEqualToAnchor:` inherited from the base takes an
 * `NSLayoutAnchor`, which a caller may pass a dimension to; the subclass is the promise that they did not, and the
 * compiler is the one enforcing it. */
@interface NSLayoutXAxisAnchor : NSLayoutAnchor
@end

@interface NSLayoutYAxisAnchor : NSLayoutAnchor
@end

/* **AND THE DIMENSION IS THE ONE THAT TAKES A MULTIPLIER AND A CONSTANT-ONLY EQUATION.** `width == 120` has no
 * second anchor, which is why the three constant doors exist here and not on the axes. */
@interface NSLayoutDimension : NSLayoutAnchor
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m constant:(CGFloat)c;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLAYOUTANCHOR_H */
