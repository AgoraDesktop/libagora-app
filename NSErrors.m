/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSErrors.m — THE APPKIT'S NAMED EXCEPTIONS, DEFINED.
 *
 * ONE CONSTANT, BECAUSE THE APPKIT HAS ONE — and it is defined here rather than beside the class that raises it because
 * the standing rule is that a name declared in a header is DEFINED somewhere, and the header this name lives in is
 * Apple's `NSErrors.h`. A file whose name matches the header's is what makes that rule checkable by reading the tree
 * rather than by searching it.
 *
 * AND IT IS NOT AN EMPTY FILE'S WORTH OF MACHINERY FOR A REASON WORTH STATING: `-compare:` raising THIS NAME is the
 * difference between a caller catching the AppKit's documented exception and catching whatever a wrong argument type
 * happens to produce — so the probe asserts the name, not merely that something was raised. See appkit-plan.md §A10br.
 */
#import <AppKit/NSErrors.h>

/* THE VALUE IS THE IDENTIFIER, WHICH IS THE APPKIT'S OWN CONVENTION for a named exception (Foundation's are spelled the
 * same way in `NSException.m`, and `NSInvalidArgumentException`'s value is its own name) and is what lets a raise site
 * and a catch site agree on one word. */
NSString *const NSBadComparisonException = @"NSBadComparisonException";
