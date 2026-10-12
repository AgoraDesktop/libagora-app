/*
 * NSAttributedString.m (AppKit) — the attribute names, defined once.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import "NSAttributedString.h"

/* **THE LITERALS ARE THIS TIER'S, AND THE HEADER SAYS WHY** (the era annotates each name with its value's TYPE
 * and default and publishes no literal). They are Apple's long-standing spellings, and what makes them correct
 * HERE is that they are the keys this library's own doors read: the probe passes one of these in a dictionary
 * and asserts that the ink changes, which is the only form of the claim that can be checked in this tier. */
NSString *NSFontAttributeName = @"NSFont";
NSString *NSForegroundColorAttributeName = @"NSColor";
