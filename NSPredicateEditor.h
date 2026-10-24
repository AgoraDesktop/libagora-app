/*
 * NSPredicateEditor.h — a rule editor whose rows are built from row templates.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE EDITOR IS ITS OWN DELEGATE, AND THAT IS THE WHOLE TRICK.** `NSRuleEditor` builds no predicates of its own: it
 * asks its delegate for the PARTS of each criterion and assembles them. A predicate editor has that knowledge in its
 * `rowTemplates`, so it sets itself as the delegate and answers the parts door from the template that matches the row —
 * which means `-predicate` and `-predicateForRow:` are the base class's, correctly assembled, with no second
 * implementation here. The rule editor's delegate is not retained, so the self-reference is not a cycle.
 *
 * **A ROW STORES ITS PARTS, NOT JUST ITS DISPLAY VALUE.** Each row's criterion is a small dictionary carrying the key
 * path, the operator, the modifier and the options the predicate used, and its display value is the right-hand
 * constant; that is what lets a predicate with an operator other than "is" survive the round trip through the rows. A
 * row added by the user gets the first template's first expression and operator, with an empty value — the editor
 * answers the rule editor's three required delegate doors to make that true, because it is its own delegate.
 *
 * **WHAT THE TEMPLATES DECIDE AND WHAT THEY DO NOT.** `-setObjectValue:` takes a predicate apart into one row per
 * comparison — an AND/OR compound's subpredicates become rows, joined by the rule editor's own AND — and
 * `-objectValue` answers the assembled predicate. A NOT compound, and a predicate no template matches, are not
 * representable as rows in this tier and are skipped rather than half-built.
 */
#ifndef APPKIT_NSPREDICATEEDITOR_H
#define APPKIT_NSPREDICATEEDITOR_H

#import <AppKit/NSRuleEditor.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@class NSPredicateEditorRowTemplate;

@interface NSPredicateEditor : NSRuleEditor <NSRuleEditorDelegate>
{
	NSArray *_rowTemplates;		/* COPIED: the vocabulary the rows are built from */
}

/* THE TEMPLATES, in the order the editor tries them. Setting them re-builds the rows when the editor's object value is
 * a predicate. */
- (nullable NSArray *)rowTemplates;
- (void)setRowTemplates:(nullable NSArray *)rowTemplates;

/* THE CONTROL'S VALUE, SPELLED AS A PREDICATE: `-setObjectValue:` takes one apart into rows and `-objectValue` answers
 * the one the rows mean. */
- (void)setObjectValue:(nullable id)objectValue;
- (nullable id)objectValue;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPREDICATEEDITOR_H */
