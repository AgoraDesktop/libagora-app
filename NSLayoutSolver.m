/*
 * NSLayoutSolver.m — linear equations, iteratively projected, written back as frames.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **WHY A PROJECTION SOLVER RATHER THAN CASSOWARY.** Every constraint here is a linear equation, a half-space or a
 * pair of them, over the four numbers of each managed view's frame. Required constraints are convex sets the answer
 * must lie in; optional ones are convex sets it should lie near, weighted by priority. Alternating projection —
 * visit each constraint, move the current point the shortest distance into its set — converges for the systems a
 * layout produces, needs no tableau, and has the property this tier wants most: THE POINT IT STARTS FROM IS THE
 * VIEWS' CURRENT FRAMES, so an underdetermined system stays where it is instead of jumping to an arbitrary vertex.
 * Cassowary's incremental simplex would give exact lexicographic priorities and prove infeasibility; this solver
 * trades both for a few hundred lines with no incremental state to invalidate, and it reports an unsatisfiable
 * required set when the residual is still large after the sweeps rather than pretending.
 *
 * THE PRIORITY IS THE STEP SIZE. A required constraint is projected fully, so it is met exactly once its neighbours
 * settle. An optional constraint at priority p moves the point by min(0.95, max(0.05, p/1000)) of the distance to
 * its set, per visit. Two conflicting wishes at 750 and 250 therefore settle near the 3:1 point between them —
 * which is the same compromise a weighted-error solver makes — while a required equation is not traded at all.
 *
 * THE COORDINATE SPACE IS THE ROOT'S, AND A FORM IS HOW A VIEW REACHES IT. A view's frame is expressed in its own
 * superview's coordinates, so its "left" is its parent's left plus its x — and if the parent is unflipped, its
 * visual top is the parent's height minus y minus height. Composing that up the chain gives each attribute as a
 * linear form over the unknowns, which is what makes a constraint between two cousins ordinary arithmetic.
 */
#import <AppKit/NSLayoutSolver.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSView.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ============================================================================================ *
 * THE PASS FLAG.                                                                                *
 * ============================================================================================ */

static int s_pass_depth;

BOOL AGLayoutIsInPass(void)
{
	return s_pass_depth > 0;
}

void AGLayoutEnterPass(void)
{
	s_pass_depth++;
}

void AGLayoutLeavePass(void)
{
	if (s_pass_depth > 0) {
		s_pass_depth--;
	}
}

/* ============================================================================================ *
 * FORMS: a linear expression over the pass's unknowns, plus a constant.                          *
 * ============================================================================================ */

typedef struct {
	int index;
	double coefficient;
} AGTerm;

typedef struct {
	AGTerm *terms;
	int count;
	int capacity;
	double constant;
} AGForm;

static void ag_form_init(AGForm *form)
{
	form->terms = NULL;
	form->count = 0;
	form->capacity = 0;
	form->constant = 0.0;
}

static void ag_form_free(AGForm *form)
{
	free(form->terms);
	ag_form_init(form);
}

static void ag_form_add_term(AGForm *form, int index, double coefficient)
{
	if (fabs(coefficient) < 1e-12) {
		return;
	}
	if (form->count == form->capacity) {
		int capacity = (form->capacity == 0) ? 4 : form->capacity * 2;

		form->terms = realloc(form->terms, (size_t)capacity * sizeof(AGTerm));
		form->capacity = capacity;
	}
	form->terms[form->count].index = index;
	form->terms[form->count].coefficient = coefficient;
	form->count++;
}

static void ag_form_add_scaled(AGForm *destination, const AGForm *source, double scale)
{
	int i;

	for (i = 0; i < source->count; i++) {
		ag_form_add_term(destination, source->terms[i].index, source->terms[i].coefficient * scale);
	}
	destination->constant += source->constant * scale;
}

/* ============================================================================================ *
 * THE PASS: the root, its managed views, and the values being solved for.                       *
 * ============================================================================================ */

typedef struct {
	NSView *root;
	NSView **views;
	NSUInteger viewCount;
	NSUInteger viewCapacity;
	int variableCount;
	double *values;
} AGPass;

static BOOL ag_is_in_subtree(NSView *view, NSView *root)
{
	NSView *walk;

	for (walk = view; walk != nil; walk = [walk superview]) {
		if (walk == root) {
			return YES;
		}
	}
	return NO;
}

static void ag_pass_init(AGPass *pass, NSView *root)
{
	pass->root = root;
	pass->views = NULL;
	pass->viewCount = 0;
	pass->viewCapacity = 0;
	pass->variableCount = 0;
	pass->values = NULL;
}

static void ag_pass_free(AGPass *pass)
{
	free(pass->views);
	free(pass->values);
	ag_pass_init(pass, pass->root);
}

static void ag_pass_add_view(AGPass *pass, NSView *view)
{
	NSUInteger i;

	if (view == nil || view == pass->root) {
		return;
	}
	for (i = 0; i < pass->viewCount; i++) {
		if (pass->views[i] == view) {
			return;
		}
	}
	if (pass->viewCount == pass->viewCapacity) {
		NSUInteger capacity = (pass->viewCapacity == 0) ? 8 : pass->viewCapacity * 2;

		pass->views = realloc(pass->views, capacity * sizeof(NSView *));
		pass->viewCapacity = capacity;
	}
	pass->views[pass->viewCount++] = view;
}

/* THE BASE VARIABLE IS -1 FOR A VIEW THE PASS DOES NOT MANAGE, which is the difference between "this view may move"
 * and "this view's frame is a number the equations may read". */
static int ag_base_for_view(AGPass *pass, NSView *view)
{
	NSUInteger i;

	for (i = 0; i < pass->viewCount; i++) {
		if (pass->views[i] == view) {
			return (int)(i * 4);
		}
	}
	return -1;
}

/* ============================================================================================ *
 * THE VISUAL FRAME: left, top, width and height as forms in the root's coordinate space.        *
 * ============================================================================================ */

/* **THE FOUR OUTPUT FORMS ARE ACCUMULATED, NOT ASSIGNED**, so the caller initialises them and frees them; the
 * recursion below only adds. The root is its own coordinate system, so its visual frame is (0, 0, W, H) by
 * definition — bounds, not frame, because a constraint against the root is a constraint against the space its
 * descendants live in. */
static void ag_visual_frame(AGPass *pass, NSView *view, AGForm out[4])
{
	NSView *parent;
	AGForm parentFrame[4];
	AGForm x, y, width, height, flippedY;
	NSRect frame;
	int base;

	if (view == pass->root) {
		NSRect bounds = [view bounds];

		out[0].constant += 0.0;
		out[1].constant += 0.0;
		out[2].constant += bounds.size.width;
		out[3].constant += bounds.size.height;
		return;
	}

	parent = [view superview];
	if (parent == nil) {
		/* A DETACHED VIEW HAS NO PARENT FRAME TO COMPOSE WITH.** Treat its own frame as a constant in the root's
		 * space: a constraint between two detached views is refused at activation, so this is reached only for an
		 * ancestor the solver was handed without one, and a constant is the honest answer. */
		frame = [view frame];
		out[0].constant += frame.origin.x;
		out[1].constant += frame.origin.y;
		out[2].constant += frame.size.width;
		out[3].constant += frame.size.height;
		return;
	}

	ag_form_init(&parentFrame[0]);
	ag_form_init(&parentFrame[1]);
	ag_form_init(&parentFrame[2]);
	ag_form_init(&parentFrame[3]);
	ag_visual_frame(pass, parent, parentFrame);

	ag_form_init(&x);
	ag_form_init(&y);
	ag_form_init(&width);
	ag_form_init(&height);
	frame = [view frame];
	base = ag_base_for_view(pass, view);
	if (base >= 0) {
		ag_form_add_term(&x, base + 0, 1.0);
		ag_form_add_term(&y, base + 1, 1.0);
		ag_form_add_term(&width, base + 2, 1.0);
		ag_form_add_term(&height, base + 3, 1.0);
	} else {
		x.constant = frame.origin.x;
		y.constant = frame.origin.y;
		width.constant = frame.size.width;
		height.constant = frame.size.height;
	}

	/* **THE FLIP IS WHERE THE TWO COORDINATE SYSTEMS MEET.** A flipped parent already measures y down from its visual
	 * top, so the child's y is the offset wanted. An unflipped parent measures up from its visual bottom, so the
	 * offset from the top is `parentHeight - y - height` — the parent's own height form, not a number, because the
	 * parent may itself be one of the unknowns. */
	ag_form_init(&flippedY);
	if ([parent isFlipped]) {
		ag_form_add_scaled(&flippedY, &y, 1.0);
	} else {
		ag_form_add_scaled(&flippedY, &parentFrame[3], 1.0);
		ag_form_add_scaled(&flippedY, &y, -1.0);
		ag_form_add_scaled(&flippedY, &height, -1.0);
	}

	ag_form_add_scaled(&out[0], &parentFrame[0], 1.0);
	ag_form_add_scaled(&out[0], &x, 1.0);
	ag_form_add_scaled(&out[1], &parentFrame[1], 1.0);
	ag_form_add_scaled(&out[1], &flippedY, 1.0);
	ag_form_add_scaled(&out[2], &width, 1.0);
	ag_form_add_scaled(&out[3], &height, 1.0);

	ag_form_free(&x);
	ag_form_free(&y);
	ag_form_free(&width);
	ag_form_free(&height);
	ag_form_free(&flippedY);
	ag_form_free(&parentFrame[0]);
	ag_form_free(&parentFrame[1]);
	ag_form_free(&parentFrame[2]);
	ag_form_free(&parentFrame[3]);
}

/* **LEADING AND TRAILING ARE LEFT AND RIGHT HERE, AND THAT IS A STATED SIMPLIFICATION.** Apple resolves them against
 * the user interface layout direction; this tier has no direction on a view, so the LTR reading is the one the
 * engine uses. A right-to-left client gets the mirrored equation by swapping the two sides itself. */
static BOOL ag_attribute_form(AGPass *pass, NSView *view, NSLayoutAttribute attribute, AGForm *out)
{
	AGForm visual[4];

	ag_form_init(&visual[0]);
	ag_form_init(&visual[1]);
	ag_form_init(&visual[2]);
	ag_form_init(&visual[3]);
	ag_visual_frame(pass, view, visual);

	switch (attribute) {
	case NSLayoutAttributeLeft:
	case NSLayoutAttributeLeading:
		ag_form_add_scaled(out, &visual[0], 1.0);
		break;
	case NSLayoutAttributeRight:
	case NSLayoutAttributeTrailing:
		ag_form_add_scaled(out, &visual[0], 1.0);
		ag_form_add_scaled(out, &visual[2], 1.0);
		break;
	case NSLayoutAttributeTop:
		ag_form_add_scaled(out, &visual[1], 1.0);
		break;
	case NSLayoutAttributeBottom:
		ag_form_add_scaled(out, &visual[1], 1.0);
		ag_form_add_scaled(out, &visual[3], 1.0);
		break;
	case NSLayoutAttributeWidth:
		ag_form_add_scaled(out, &visual[2], 1.0);
		break;
	case NSLayoutAttributeHeight:
		ag_form_add_scaled(out, &visual[3], 1.0);
		break;
	case NSLayoutAttributeCenterX:
		ag_form_add_scaled(out, &visual[0], 1.0);
		ag_form_add_scaled(out, &visual[2], 0.5);
		break;
	case NSLayoutAttributeCenterY:
		ag_form_add_scaled(out, &visual[1], 1.0);
		ag_form_add_scaled(out, &visual[3], 0.5);
		break;
	default:
		ag_form_free(&visual[0]);
		ag_form_free(&visual[1]);
		ag_form_free(&visual[2]);
		ag_form_free(&visual[3]);
		return NO;
	}
	ag_form_free(&visual[0]);
	ag_form_free(&visual[1]);
	ag_form_free(&visual[2]);
	ag_form_free(&visual[3]);
	return YES;
}

/* ============================================================================================ *
 * ROWS: one constraint, in the pass's variables.                                                *
 * ============================================================================================ */

typedef struct {
	double *coefficients;
	double rhs;
	NSLayoutRelation relation;
	double priority;
	int order;
} AGRow;

typedef struct {
	AGRow *rows;
	int count;
	int capacity;
} AGRows;

static void ag_rows_init(AGRows *rows)
{
	rows->rows = NULL;
	rows->count = 0;
	rows->capacity = 0;
}

static void ag_rows_free(AGRows *rows)
{
	int i;

	for (i = 0; i < rows->count; i++) {
		free(rows->rows[i].coefficients);
	}
	free(rows->rows);
	ag_rows_init(rows);
}

static void ag_rows_add(AGRows *rows, AGPass *pass, AGForm *form, double rhs,
			NSLayoutRelation relation, double priority)
{
	AGRow *row;
	int i;

	if (pass->variableCount == 0) {
		return;
	}
	if (rows->count == rows->capacity) {
		int capacity = (rows->capacity == 0) ? 16 : rows->capacity * 2;

		rows->rows = realloc(rows->rows, (size_t)capacity * sizeof(AGRow));
		rows->capacity = capacity;
	}
	row = &rows->rows[rows->count];
	row->coefficients = calloc((size_t)pass->variableCount, sizeof(double));
	row->rhs = rhs - form->constant;
	row->relation = relation;
	row->priority = priority;
	row->order = rows->count;
	for (i = 0; i < form->count; i++) {
		row->coefficients[form->terms[i].index] += form->terms[i].coefficient;
	}
	rows->count++;
}

static int ag_row_compare(const void *left, const void *right)
{
	const AGRow *a = left;
	const AGRow *b = right;

	/* **WEAKEST FIRST, REQUIRED LAST.** Within one sweep the last visit wins a conflict, so putting the strongest
	 * constraint last is what makes the final state the strongest one's — and the sweep repeats until the required
	 * set is met. Ties keep their construction order, which is the order the caller activated them in. */
	if (a->priority < b->priority) {
		return -1;
	}
	if (a->priority > b->priority) {
		return 1;
	}
	return (a->order < b->order) ? -1 : ((a->order > b->order) ? 1 : 0);
}

static double ag_row_evaluate(const AGRow *row, const double *values, int count)
{
	double sum = 0.0;
	int i;

	for (i = 0; i < count; i++) {
		if (row->coefficients[i] != 0.0) {
			sum += row->coefficients[i] * values[i];
		}
	}
	return sum;
}

static double ag_row_violation(const AGRow *row, const double *values, int count)
{
	double difference = ag_row_evaluate(row, values, count) - row->rhs;

	switch (row->relation) {
	case NSLayoutRelationEqual:
		return fabs(difference);
	case NSLayoutRelationGreaterThanOrEqual:
		return (difference < 0.0) ? -difference : 0.0;
	case NSLayoutRelationLessThanOrEqual:
		return (difference > 0.0) ? difference : 0.0;
	}
	return fabs(difference);
}

/* ============================================================================================ *
 * THE SWEEP.                                                                                    *
 * ============================================================================================ */

static void ag_project(AGRows *rows, AGPass *pass, double tolerance)
{
	const int maximumSweeps = 400;
	double *pending = calloc((size_t)pass->variableCount, sizeof(double));
	double *sweepStart = calloc((size_t)pass->variableCount, sizeof(double));
	int sweep;

	for (sweep = 0; sweep < maximumSweeps; sweep++) {
		double maximumRequiredViolation = 0.0;
		double maximumChange = 0.0;
		double weightSum = 0.0;
		int i;

		/* **THE CONVERGENCE TEST IS THE NET CHANGE, NOT THE SUM OF EVERY PROJECTION.** The optional phase pulls and
		 * the required phase pushes back on the same variables; a required projection that exactly undoes an
		 * optional one still counts as a large move if each step is measured, so the loop would run its whole
		 * budget without the answer changing. Remembering the values at the sweep's start and comparing at its end
		 * is the question the break actually means. */
		if (pass->variableCount > 0) {
			memcpy(sweepStart, pass->values, (size_t)pass->variableCount * sizeof(double));
		}

		/* **OPTIONAL CONSTRAINTS MOVE TOGETHER, BY A WEIGHTED AVERAGE OF THEIR PROJECTIONS.** Sequential full
		 * projections would let whichever constraint was visited last win the argument; averaging makes two wishes
		 * on one variable settle at their priority ratio — 750 and 250 at 3:1 — which is the compromise Apple's
		 * weighted-error solver makes. The moves are accumulated and applied once, so the order of the rows does not
		 * matter within the priority band. */
		memset(pending, 0, (size_t)pass->variableCount * sizeof(double));
		for (i = 0; i < rows->count; i++) {
			AGRow *row = &rows->rows[i];
			double sum, difference, norm, weight;
			int j;

			if (row->priority >= NSLayoutPriorityRequired) {
				continue;
			}
			sum = ag_row_evaluate(row, pass->values, pass->variableCount);
			difference = row->rhs - sum;
			/* A SATISFIED WISH STILL COUNTS IN THE DENOMINATOR, with a zero projection. Dropping it would make the
			 * average a ratio of only the currently-violated constraints, which is how a 250 wish pulled a 750
			 * wish's answer all the way to 100 on one sweep instead of to the 3:1 point. */
			if (row->relation == NSLayoutRelationGreaterThanOrEqual && difference <= tolerance) {
				difference = 0.0;
			}
			if (row->relation == NSLayoutRelationLessThanOrEqual && difference >= -tolerance) {
				difference = 0.0;
			}
			if (fabs(difference) <= tolerance) {
				difference = 0.0;
			}
			norm = 0.0;
			for (j = 0; j < pass->variableCount; j++) {
				norm += row->coefficients[j] * row->coefficients[j];
			}
			if (norm < 1e-12) {
				continue;
			}
			weight = (double)row->priority / 1000.0;
			if (weight < 0.01) {
				weight = 0.01;
			}
			for (j = 0; j < pass->variableCount; j++) {
				if (row->coefficients[j] != 0.0) {
					pending[j] += weight * (difference / norm) * row->coefficients[j];
				}
			}
			weightSum += weight;
		}
		if (weightSum > 0.0) {
			int j;

			for (j = 0; j < pass->variableCount; j++) {
				double change = pending[j] / weightSum;

				if (fabs(change) > 1e-12) {
					pass->values[j] += change;
					if (fabs(change) > maximumChange) {
						maximumChange = fabs(change);
					}
				}
			}
		}

		/* **REQUIRED CONSTRAINTS ARE PROJECTED LAST, FULLY, AND TO CONVERGENCE.** One pass over the required rows
		 * per sweep is not enough when two demands are COUPLED: a leading and a trailing constraint share the
		 * view's x and width, so projecting the trailing one moves the x the leading one just set. With an
		 * optional intrinsic pull also in the mix, that pair settles at a compromise instead of at the demanded
		 * edges — MEASURED, a control pinned to both edges of a 700-point parent landed at x=76 with an intrinsic
		 * width of 10. Repeating the required projection until its own residual is gone makes the demand exact
		 * between the optional pulls; a genuinely contradictory set still reaches the refusal below, which reads
		 * only required rows. */
		{
			int requiredSweep;

			for (requiredSweep = 0; requiredSweep < 64; requiredSweep++) {
				double requiredViolation = 0.0;

				for (i = 0; i < rows->count; i++) {
					AGRow *row = &rows->rows[i];
					double sum, target, delta, norm;
					int j;

					if (row->priority < NSLayoutPriorityRequired) {
						continue;
					}
					sum = ag_row_evaluate(row, pass->values, pass->variableCount);
					target = row->rhs;
					if (row->relation == NSLayoutRelationGreaterThanOrEqual && sum >= target - tolerance) {
						continue;
					}
					if (row->relation == NSLayoutRelationLessThanOrEqual && sum <= target + tolerance) {
						continue;
					}
					if (fabs(target - sum) <= tolerance) {
						continue;
					}
					norm = 0.0;
					for (j = 0; j < pass->variableCount; j++) {
						norm += row->coefficients[j] * row->coefficients[j];
					}
					if (norm < 1e-12) {
						continue;	/* 0 == c: nothing to move, and the residual check below reports it. */
					}
					delta = (target - sum) / norm;
					for (j = 0; j < pass->variableCount; j++) {
						double change;

						if (row->coefficients[j] == 0.0) {
							continue;
						}
						change = delta * row->coefficients[j];
						pass->values[j] += change;
						if (fabs(change) > maximumChange) {
							maximumChange = fabs(change);
						}
					}
				}
				for (i = 0; i < rows->count; i++) {
					if (rows->rows[i].priority >= NSLayoutPriorityRequired) {
						double violation = ag_row_violation(&rows->rows[i], pass->values,
										    pass->variableCount);

						if (violation > requiredViolation) {
							requiredViolation = violation;
						}
					}
				}
				if (requiredViolation <= 1e-7) {
					break;
				}
			}
		}

		for (i = 0; i < rows->count; i++) {
			if (rows->rows[i].priority >= NSLayoutPriorityRequired) {
				double violation = ag_row_violation(&rows->rows[i], pass->values, pass->variableCount);

				if (violation > maximumRequiredViolation) {
					maximumRequiredViolation = violation;
				}
			}
		}
		maximumChange = 0.0;
		for (i = 0; i < pass->variableCount; i++) {
			double change = fabs(pass->values[i] - sweepStart[i]);

			if (change > maximumChange) {
				maximumChange = change;
			}
		}
		/* **A POINT IS THE UNIT, SO THE BREAK IS IN POINTS.** The required set is met to a millionth of a point and
		 * the net move has to be no larger; a tighter test than that made an ordinary file window run its whole
		 * 400-sweep budget because two intrinsic pulls kept trading a fraction of a point with the required edges.
		 * The refusal below still fires for a real contradiction, which is orders of magnitude larger. */
		if (sweep >= 4 && maximumRequiredViolation <= 1e-5 && maximumChange <= 1e-5) {
			break;
		}
		if (sweep == maximumSweeps - 1 && maximumRequiredViolation > 1e-3) {
			/* **AN UNSATISFIABLE REQUIRED SET IS NAMED, NOT SILENTLY APPROXIMATED.** Apple logs the same condition;
			 * the number is the largest residual left after every sweep, so a caller can tell a rounding difference
			 * from a contradiction. */
			fprintf(stderr, "APPKIT-REFUSE: AutoLayout could not satisfy the required constraints under %p; the "
					"largest residual after %d sweeps is %g. A required equation conflicts with another, or "
					"a view still has translatesAutoresizingMaskIntoConstraints set\n",
				(void *)pass->root, maximumSweeps, maximumRequiredViolation);
		}
	}
	free(pending);
	free(sweepStart);
}

/* ============================================================================================ *
 * BUILDING THE PASS.                                                                            *
 * ============================================================================================ */

static void ag_gather_constraints(NSView *view, NSMutableArray *constraints)
{
	NSArray *own = [view constraints];
	NSArray *subviews = [view subviews];
	NSUInteger i;

	for (i = 0; i < [own count]; i++) {
		[constraints addObject:[own objectAtIndex:i]];
	}
	for (i = 0; i < [subviews count]; i++) {
		ag_gather_constraints([subviews objectAtIndex:i], constraints);
	}
}

static BOOL ag_attribute_is_supported(NSLayoutAttribute attribute)
{
	switch (attribute) {
	case NSLayoutAttributeLeft:
	case NSLayoutAttributeRight:
	case NSLayoutAttributeTop:
	case NSLayoutAttributeBottom:
	case NSLayoutAttributeLeading:
	case NSLayoutAttributeTrailing:
	case NSLayoutAttributeWidth:
	case NSLayoutAttributeHeight:
	case NSLayoutAttributeCenterX:
	case NSLayoutAttributeCenterY:
		return YES;
	default:
		return NO;
	}
}

static BOOL ag_constraint_is_usable(NSLayoutConstraint *constraint, NSView *root)
{
	id first = [constraint firstItem];
	id second = [constraint secondItem];

	if (![constraint isActive]) {
		return NO;
	}
	if (![first isKindOfClass:[NSView class]] || !ag_is_in_subtree((NSView *)first, root)) {
		return NO;
	}
	if (second != nil &&
	    (![second isKindOfClass:[NSView class]] || !ag_is_in_subtree((NSView *)second, root))) {
		return NO;
	}
	if (!ag_attribute_is_supported([constraint firstAttribute])) {
		return NO;
	}
	if (second != nil && [constraint secondAttribute] != NSLayoutAttributeNotAnAttribute &&
	    !ag_attribute_is_supported([constraint secondAttribute])) {
		return NO;
	}
	/* A SINGLE-ITEM CONSTRAINT IS SPELLED WITH A NIL SECOND ITEM; a non-nil item with NotAnAttribute would have
	 * been refused at construction, and if it survived it is read as a single-item equation because the second-side
	 * attribute check above already let NotAnAttribute through. */
	return YES;
}

/* **THE MASK TRANSLATION IS THE ONE PLACE THE ENGINE STILL SPEAKS SPRINGS AND STRUTS.** A view that has not opted
 * out of the translated-mask system gets the equations its mask describes, measured against the frame it has when
 * the pass begins. The right, top and bottom gaps are taken from the CURRENT size, so a parent's growth is what
 * moves the child; nothing here stores a gap, which is what keeps two consecutive passes from compounding a delta.
 *
 * THE EQUATIONS ARE EDGE DIFFERENCES, NOT EDGE POSITIONS. "The left margin is 10" is `childLeft - parentLeft == 10`;
 * writing it as `parentLeft == -10` would pin the PARENT, which was the first draft's mistake and is exactly the
 * kind a test that only ever looks at one child cannot see. */
static void ag_add_edge_row(AGRows *rows, AGPass *pass, AGForm *childEdge, AGForm *parentEdge, double offset)
{
	AGForm form;

	ag_form_init(&form);
	ag_form_add_scaled(&form, childEdge, 1.0);
	if (parentEdge != NULL) {
		ag_form_add_scaled(&form, parentEdge, -1.0);
	}
	ag_rows_add(rows, pass, &form, offset, NSLayoutRelationEqual, NSLayoutPriorityRequired);
	ag_form_free(&form);
}

static void ag_add_autoresizing_constraints(AGRows *rows, AGPass *pass, NSView *view)
{
	NSUInteger mask = [view autoresizingMask];
	NSView *parent = [view superview];
	NSRect frame = [view frame];
	NSSize parentSize;
	AGForm parentVisual[4];
	AGForm parentRight, parentBottom;
	AGForm left, top, width, height, right, bottom;
	double parentWidth;
	double parentHeight;
	double rightMargin;
	double topMargin;
	double bottomMargin;

	if (parent == nil) {
		return;
	}
	/* **THE GAPS COME FROM THE CAPTURE, NOT FROM THE CURRENT FRAME.** By the time a pass runs, the parent may have
	 * already grown: recomputing the right gap from the new parent size and the child's old frame would report the
	 * resize as a larger gap and pin the child where it was. The first pass over a managed view records the frame
	 * and parent size, and those are what the mask is translated against until the mask or parent changes. */
	if (![view cg_getCapturedAutoresizingFrame:&frame parentSize:&parentSize]) {
		parentSize = [parent frame].size;
		[view cg_setCapturedAutoresizingFrame:frame parentSize:parentSize];
	}
	ag_form_init(&parentVisual[0]);
	ag_form_init(&parentVisual[1]);
	ag_form_init(&parentVisual[2]);
	ag_form_init(&parentVisual[3]);
	ag_visual_frame(pass, parent, parentVisual);
	ag_form_init(&parentRight);
	ag_form_add_scaled(&parentRight, &parentVisual[0], 1.0);
	ag_form_add_scaled(&parentRight, &parentVisual[2], 1.0);
	ag_form_init(&parentBottom);
	ag_form_add_scaled(&parentBottom, &parentVisual[1], 1.0);
	ag_form_add_scaled(&parentBottom, &parentVisual[3], 1.0);

	ag_form_init(&left);
	ag_form_init(&top);
	ag_form_init(&width);
	ag_form_init(&height);
	ag_attribute_form(pass, view, NSLayoutAttributeLeft, &left);
	ag_attribute_form(pass, view, NSLayoutAttributeTop, &top);
	ag_attribute_form(pass, view, NSLayoutAttributeWidth, &width);
	ag_attribute_form(pass, view, NSLayoutAttributeHeight, &height);
	ag_form_init(&right);
	ag_form_add_scaled(&right, &left, 1.0);
	ag_form_add_scaled(&right, &width, 1.0);
	ag_form_init(&bottom);
	ag_form_add_scaled(&bottom, &top, 1.0);
	ag_form_add_scaled(&bottom, &height, 1.0);

	parentWidth = parentSize.width;
	parentHeight = parentSize.height;
	rightMargin = parentWidth - (frame.origin.x + frame.size.width);
	topMargin = parentHeight - (frame.origin.y + frame.size.height);
	bottomMargin = frame.origin.y;

	/* HORIZONTAL. The left gap is the MinX margin, the right gap the MaxX margin. A flexible margin is a spring, a
	 * fixed one is a strut, and a sizable width means the two struts stay while the width moves. */
	if ((mask & NSViewWidthSizable) != 0) {
		ag_add_edge_row(rows, pass, &left, &parentVisual[0], frame.origin.x);
		ag_add_edge_row(rows, pass, &right, &parentRight, -rightMargin);
	} else {
		ag_add_edge_row(rows, pass, &width, NULL, frame.size.width);
		if ((mask & NSViewMinXMargin) == 0) {
			ag_add_edge_row(rows, pass, &left, &parentVisual[0], frame.origin.x);
		}
		if ((mask & NSViewMaxXMargin) == 0) {
			ag_add_edge_row(rows, pass, &right, &parentRight, -rightMargin);
		}
	}

	/* VERTICAL. In the visual space the top gap is the MaxY margin and the bottom gap is the MinY margin — the names
	 * are the frame's, the geometry is the screen's. */
	if ((mask & NSViewHeightSizable) != 0) {
		ag_add_edge_row(rows, pass, &top, &parentVisual[1], topMargin);
		ag_add_edge_row(rows, pass, &bottom, &parentBottom, -bottomMargin);
	} else {
		ag_add_edge_row(rows, pass, &height, NULL, frame.size.height);
		if ((mask & NSViewMaxYMargin) == 0) {
			ag_add_edge_row(rows, pass, &top, &parentVisual[1], topMargin);
		}
		if ((mask & NSViewMinYMargin) == 0) {
			ag_add_edge_row(rows, pass, &bottom, &parentBottom, -bottomMargin);
		}
	}

	ag_form_free(&parentVisual[0]);
	ag_form_free(&parentVisual[1]);
	ag_form_free(&parentVisual[2]);
	ag_form_free(&parentVisual[3]);
	ag_form_free(&parentRight);
	ag_form_free(&parentBottom);
	ag_form_free(&left);
	ag_form_free(&top);
	ag_form_free(&width);
	ag_form_free(&height);
	ag_form_free(&right);
	ag_form_free(&bottom);
}

static void ag_add_intrinsic_constraints(AGRows *rows, AGPass *pass, NSView *view)
{
	NSSize intrinsic = [view intrinsicContentSize];
	AGForm form;

	if (intrinsic.width != NSViewNoIntrinsicMetric) {
		ag_form_init(&form);
		ag_attribute_form(pass, view, NSLayoutAttributeWidth, &form);
		/* HUGGING KEEPS A VIEW FROM GROWING PAST ITS CONTENT; COMPRESSION RESISTANCE KEEPS IT FROM SHRINKING
		 * BELOW. Both are optional by definition, which is why the two priorities are the caller's. */
		ag_rows_add(rows, pass, &form, intrinsic.width, NSLayoutRelationLessThanOrEqual,
			    [view contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationHorizontal]);
		ag_rows_add(rows, pass, &form, intrinsic.width, NSLayoutRelationGreaterThanOrEqual,
			    [view contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal]);
		ag_form_free(&form);
	}
	if (intrinsic.height != NSViewNoIntrinsicMetric) {
		ag_form_init(&form);
		ag_attribute_form(pass, view, NSLayoutAttributeHeight, &form);
		ag_rows_add(rows, pass, &form, intrinsic.height, NSLayoutRelationLessThanOrEqual,
			    [view contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationVertical]);
		ag_rows_add(rows, pass, &form, intrinsic.height, NSLayoutRelationGreaterThanOrEqual,
			    [view contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationVertical]);
		ag_form_free(&form);
	}
}

/* ============================================================================================ *
 * THE SOLVE.                                                                                    *
 * ============================================================================================ */

BOOL AGLayoutSubtreeHasConstraints(NSView *root)
{
	NSArray *own = [root constraints];
	NSArray *subviews = [root subviews];
	NSUInteger i;

	if ([own count] > 0) {
		return YES;
	}
	for (i = 0; i < [subviews count]; i++) {
		if (AGLayoutSubtreeHasConstraints([subviews objectAtIndex:i])) {
			return YES;
		}
	}
	return NO;
}

NSUInteger AGLayoutSolveSubtree(NSView *root)
{
	NSMutableArray *constraints;
	AGPass pass;
	AGRows rows;
	NSUInteger i;
	NSUInteger changed = 0;

	if (root == nil) {
		return 0;
	}
	constraints = [[NSMutableArray alloc] init];
	ag_gather_constraints(root, constraints);
	if ([constraints count] == 0) {
		[constraints release];
		return 0;
	}

	ag_pass_init(&pass, root);
	ag_rows_init(&rows);

	/* FIRST PASS: WHICH VIEWS THE EQUATIONS NAME. Only these move; a view named by nothing keeps its frame, which
	 * is what lets an Auto Layout container coexist with a manually laid out sibling. */
	for (i = 0; i < [constraints count]; i++) {
		NSLayoutConstraint *constraint = [constraints objectAtIndex:i];

		if (!ag_constraint_is_usable(constraint, root)) {
			continue;
		}
		ag_pass_add_view(&pass, (NSView *)[constraint firstItem]);
		if ([constraint secondItem] != nil) {
			ag_pass_add_view(&pass, (NSView *)[constraint secondItem]);
		}
	}
	pass.variableCount = (int)(pass.viewCount * 4);
	if (pass.variableCount == 0) {
		ag_pass_free(&pass);
		ag_rows_free(&rows);
		[constraints release];
		return 0;
	}
	pass.values = calloc((size_t)pass.variableCount, sizeof(double));
	for (i = 0; i < pass.viewCount; i++) {
		NSRect frame = [pass.views[i] frame];

		pass.values[i * 4 + 0] = frame.origin.x;
		pass.values[i * 4 + 1] = frame.origin.y;
		pass.values[i * 4 + 2] = frame.size.width;
		pass.values[i * 4 + 3] = frame.size.height;
	}

	/* SECOND PASS: EACH CONSTRAINT AS A ROW. */
	for (i = 0; i < [constraints count]; i++) {
		NSLayoutConstraint *constraint = [constraints objectAtIndex:i];
		NSView *first;
		NSView *second;
		AGForm firstForm;
		AGForm secondForm;
		AGForm lhs;

		if (!ag_constraint_is_usable(constraint, root)) {
			continue;
		}
		first = (NSView *)[constraint firstItem];
		second = (NSView *)[constraint secondItem];
		ag_form_init(&firstForm);
		ag_form_init(&secondForm);
		ag_form_init(&lhs);
		if (!ag_attribute_form(&pass, first, [constraint firstAttribute], &firstForm)) {
			ag_form_free(&firstForm);
			ag_form_free(&secondForm);
			ag_form_free(&lhs);
			continue;
		}
		ag_form_add_scaled(&lhs, &firstForm, 1.0);
		if (second != nil && [constraint secondAttribute] != NSLayoutAttributeNotAnAttribute) {
			if (ag_attribute_form(&pass, second, [constraint secondAttribute], &secondForm)) {
				ag_form_add_scaled(&lhs, &secondForm, -(double)[constraint multiplier]);
			}
		}
		ag_rows_add(&rows, &pass, &lhs, (double)[constraint constant], [constraint relation],
			    (double)[constraint priority]);
		ag_form_free(&firstForm);
		ag_form_free(&secondForm);
		ag_form_free(&lhs);
	}

	/* AND THE TWO SOURCES OF EQUATIONS NOBODY WROTE: the autoresizing mask and the intrinsic size. */
	for (i = 0; i < pass.viewCount; i++) {
		NSView *view = pass.views[i];

		if ([view translatesAutoresizingMaskIntoConstraints]) {
			ag_add_autoresizing_constraints(&rows, &pass, view);
		}
		ag_add_intrinsic_constraints(&rows, &pass, view);
	}

	if (rows.count > 0) {
		qsort(rows.rows, (size_t)rows.count, sizeof(AGRow), ag_row_compare);
		ag_project(&rows, &pass, 1e-9);
	}

	/* WRITE BACK. A NEGATIVE SIZE IS CLAMPED TO ZERO rather than assigned: Auto Layout does not produce one, and a
	 * frame setter that accepted it would hand a drawing routine a rectangle that runs backwards. */
	for (i = 0; i < pass.viewCount; i++) {
		NSView *view = pass.views[i];
		NSRect frame = [view frame];
		NSRect solved;

		solved.origin.x = pass.values[i * 4 + 0];
		solved.origin.y = pass.values[i * 4 + 1];
		solved.size.width = pass.values[i * 4 + 2];
		solved.size.height = pass.values[i * 4 + 3];
		if (solved.size.width < 0.0) {
			solved.size.width = 0.0;
		}
		if (solved.size.height < 0.0) {
			solved.size.height = 0.0;
		}
		if (fabs(solved.origin.x - frame.origin.x) > 1e-9 || fabs(solved.origin.y - frame.origin.y) > 1e-9 ||
		    fabs(solved.size.width - frame.size.width) > 1e-9 ||
		    fabs(solved.size.height - frame.size.height) > 1e-9) {
			[view setFrame:solved];
			changed++;
		}
	}

	ag_rows_free(&rows);
	ag_pass_free(&pass);
	[constraints release];
	return changed;
}
