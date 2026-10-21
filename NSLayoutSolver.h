/*
 * NSLayoutSolver.h — the private half of Auto Layout: equations in, frames out.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS IS NOT APPLE'S API AND IS NOT INSTALLED FOR A CLIENT TO CALL.** It is the engine `NSView` uses, split into
 * its own file because a solver and a view are different jobs: the view owns a tree, a window and a drawing model,
 * and the solver owns nothing but arithmetic. `NSView -layoutSubtreeIfNeeded` is the public door; these three
 * functions are the seam between them.
 *
 * THE SOLVER'S MODEL, STATED ONCE SO THE LIMITS ARE NOT A SURPRISE:
 *
 *   * Every managed view contributes four unknowns — its x, y, width and height in its SUPERVIEW's coordinates.
 *     A view named by no active constraint is not managed: its frame is a constant the equations may read and no
 *     pass will move it.
 *   * The equation is solved in the ROOT's coordinate space. A view's visual top and left are accumulated through
 *     its ancestors, with each ancestor's flippedness deciding whether a frame origin is measured from the top or
 *     the bottom. That is what lets a constraint relate a view to its uncle without either class knowing about the
 *     other.
 *   * Required constraints (priority 1000) are projected fully; optional ones are projected by a fraction of their
 *     priority, so two wishes at 750/250 settle at the 3:1 point between them rather than at whichever was visited
 *     last. This is an ITERATIVE PROJECTION solver, not Cassowary: it converges on the equations it is given, and
 *     it reports an unsatisfiable required set by name rather than pretending it solved it.
 *   * A view with `translatesAutoresizingMaskIntoConstraints` YES contributes constraints equivalent to its
 *     autoresizing mask, measured against the frame it has when the pass begins. That is the same rule Apple
 *     states: the mask is translated, so a view that wants constraints of its own must turn the flag off.
 *
 * WHAT IT DOES NOT DO: priorities are traded continuously rather than lexicographically; a baseline attribute is
 * refused; margins and layout guides do not exist here; and a constraint owned by a view OUTSIDE the subtree being
 * solved is not gathered. Each is recorded where a caller would meet it.
 */
#ifndef APPKIT_NSLAYOUTSOLVER_H
#define APPKIT_NSLAYOUTSOLVER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSView;

/* **ONE PASS IS A CRITICAL SECTION, NOT A FLAG ON A VIEW.** While a pass is running, a frame set made by the solver
 * (or by a `-layout` override it called) must not start a second pass: that would re-enter the same equations with
 * half-applied frames and could oscillate. `NSView -setFrameSize:` asks this before it considers a layout. */
BOOL AGLayoutIsInPass(void);
void AGLayoutEnterPass(void);
void AGLayoutLeavePass(void);

/* **SOLVE EVERY CONSTRAINT IN `root`'s SUBTREE AND WRITE THE FRAMES BACK.** The root itself is a fixed reference:
 * its own frame is whatever its caller set, and its bounds are the coordinate system its descendants' equations
 * are expressed against. Returns the number of views whose frame changed, which is what a probe uses to tell "the
 * pass ran and agreed" from "the pass ran and did nothing". */
NSUInteger AGLayoutSolveSubtree(NSView *root);

/* AND WHETHER THERE IS ANYTHING TO SOLVE, for a caller that wants the cheap answer before it builds a pass. */
BOOL AGLayoutSubtreeHasConstraints(NSView *root);

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLAYOUTSOLVER_H */
