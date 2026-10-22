/*
 * NSActionCell — the link between a cell and the control that reads it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THE IMPLEMENTATION IS EMPTY ON PURPOSE AND THE HEADER SAYS WHY: this class adds no member, because the three
 * Apple declares on it — `target`, `action` and `tag` — are already on this tree's `NSCell`, which is where the era
 * header puts them too. An empty `@implementation` is the truthful body for a class whose contribution is the
 * HIERARCHY, and filling it with doors that belong one level up would be a way of hiding that.
 *
 * WHAT IT MEANS FOR A CALLER: `-respondsToSelector:` and `-isKindOfClass:` now answer the way Apple's do for a cell
 * that has an action, which is what a control that stores its cells by class will ask.
 */
#import <AppKit/NSActionCell.h>

@implementation NSActionCell

/* ============================================================================================
 * ARCHIVING: NOTHING, AND THAT IS THE POINT.
 * ============================================================================================ */
/* **THIS CLASS ADDS NO STORAGE, SO IT ADDS NO CODING.** `NSCell`'s methods are exactly right for it, and the census in
 * `NSNib` accepts an inherited method when `class_getInstanceSize` says there is nothing to lose — which for this class
 * is the truth rather than an exemption. The conformance is declared so that `-conformsToProtocol:` answers what the
 * allow-list asks. */
+ (BOOL)supportsSecureCoding
{
	return YES;
}

@end
