/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

/* NSClipView.m — the view that clips and scrolls a document.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 */
#import <AppKit/NSClipView.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>

#import "NSWindow_internal.h"

/* **THE TWO PRIVATE DOORS THIS CLASS NEEDS FROM ITS SUPERCLASS AND ITS WINDOW.** The dirty record is `NSView`'s and is
 * narrowed rather than cleared (`-cg_clearDirtyRegion` also walks the SUBVIEWS, which here is the document — its own
 * damage is not the clip view's to throw away), and the copy itself is the window's, because the window is what holds
 * the frame on the glass. */
@interface NSView (AGClipViewDamage)
- (void)cg_setDirtyRect:(NSRect)rect;
@end

/* **AND THE WINDOW'S DOOR, DECLARED WHERE IT IS CALLED RATHER THAN IN A HEADER.** The window is the only object that can
 * move pixels — it owns the frame on the glass and the surface being drawn — and this is the one call that asks it to.
 * `rect` is in the clip view's coordinates, `delta` is what the content moved in points, and NO means the copy cannot be
 * taken (no committed frame, a GPU buffer, another scroll already pending), which leaves this class's whole bounds dirty:
 * the repaint the door exists to avoid, and never a wrong picture. */
@interface NSWindow (AGScrollCopy)
- (BOOL)cg_scrollContentInRect:(NSRect)rect inView:(NSView *)view by:(NSSize)delta;
@end

@implementation NSClipView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* **A CLIP VIEW IS FLIPPED, WHICH IS WHY A SCROLLED DOCUMENT'S ORIGIN IS ITS TOP-LEFT.** Apple's own
		 * coordinate-system guide says so, it is what makes a scroll point read as "how far down", and it is what
		 * the `-documentRect` rule below turns on — a NON-flipped clip view would want its document's extent
		 * unioned with its own bounds instead. */
		[self setFlipped:YES];
		_drawsBackground = YES;	/* the flag's default, and the one the ivar's spelling in Apple's header implies */
		_copiesOnScroll = YES;
	}
	return self;
}

- (void)dealloc
{
	/* **AND THE WATCH ENDS WITH THE VIEW.** The document is a retained subview and is still alive here, so the
	 * registration can be named exactly — but `-removeObserver:` without a name is the one removal that cannot go
	 * stale, and nothing else in this class registers. */
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_backgroundColor release];
	[super dealloc];
}

/* ---- THE DOCUMENT VIEW, AND WHAT A FRAME CHANGE DOES TO THE SCROLL ---------------------------- */

- (void)setDocumentView:(NSView *)aView
{
	/* A BORROWED POINTER AND AN OWNED SUBVIEW: the view is ADDED, so the tree retains it and this class does not —
	 * the same shape as `NSView`'s own superview relationship, which is why `_superview` is borrowed too. */
	if (_docView != nil) {
		/* **AND THE OLD DOCUMENT STOPS BEING WATCHED BEFORE THE NEW ONE STARTS.** A frame or bounds change is
		 * ANNOUNCED by `NSView` itself (`-setPostsFrameChangedNotifications`, whose default is YES), so
		 * re-constraining the scroll after a document changed shape is a question of LISTENING — see the two
		 * handlers below. A REPLACED document that was still watched would move a clip view that no longer holds
		 * it, which is exactly the bug a second `-setDocumentView:` would otherwise hide. */
		[[NSNotificationCenter defaultCenter] removeObserver:self
			name:NSViewFrameDidChangeNotification object:_docView];
		[[NSNotificationCenter defaultCenter] removeObserver:self
			name:NSViewBoundsDidChangeNotification object:_docView];
		[_docView removeFromSuperview];
	}
	_docView = aView;
	if (aView != nil) {
		[self addSubview:aView];
		/* **THE WIRE THE TWO HANDLERS BELOW WERE ALWAYS WRITTEN FOR.** They existed and nothing ever called them,
		 * because the clip view was never registered for the document's own announcements — so "a document that
		 * SHRANK pulls the visible area back with it" was a promise the header made and the class did not keep.
		 * `tests/clip_view.m` drives a document's frame directly and asks whether the visible origin moved; this is
		 * what makes the answer yes. Registered on the DOCUMENT and not the clip view, so a scroll's own
		 * `-setBoundsOrigin:` cannot call back into the handler that made it. */
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(viewFrameChanged:)
			name:NSViewFrameDidChangeNotification object:aView];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(viewBoundsChanged:)
			name:NSViewBoundsDidChangeNotification object:aView];
	}
	/* **AND THE NEW DOCUMENT IS MEASURED AGAINST THE ORIGIN THE CLIP ALREADY HAS — CLAMPED, NOT CENTRED.** A document that
	 * ARRIVES may be larger than the one before, and the origin then lies past its end; that origin is pulled back into
	 * range. It is deliberately NOT centred when the document is short, because centring is the answer to a SCROLL, not
	 * to a document arriving — a clip view that recentred on every `-setDocumentView:` would move a caller's visible
	 * region every time it swapped its content. MEASURED as a bug one class up before this existed: a scroll view given
	 * its bars before its document kept the origin a `-tile` pass had computed with no document at all (-92.5, -92.5 in
	 * a 185-point clip), and the first line scroll then clamped to 0 instead of stepping. */
	if (aView != nil) {
		NSRect doc = [self documentRect];
		NSRect visible = [self bounds];
		NSPoint origin = visible.origin;
		BOOL moved = NO;

		if (NSWidth(doc) >= NSWidth(visible)) {
			if (origin.x < NSMinX(doc)) {
				origin.x = NSMinX(doc);
				moved = YES;
			} else if (origin.x > NSMaxX(doc) - NSWidth(visible)) {
				origin.x = NSMaxX(doc) - NSWidth(visible);
				moved = YES;
			}
		}
		if (NSHeight(doc) >= NSHeight(visible)) {
			if (origin.y < NSMinY(doc)) {
				origin.y = NSMinY(doc);
				moved = YES;
			} else if (origin.y > NSMaxY(doc) - NSHeight(visible)) {
				origin.y = NSMaxY(doc) - NSHeight(visible);
				moved = YES;
			}
		}
		if (moved) {
			[self setBoundsOrigin:origin];
			if ([[self superview] respondsToSelector:@selector(reflectScrolledClipView:)]) {
				[[self superview] reflectScrolledClipView:self];
			}
		}
	}
}

- (NSView *)documentView
{
	return _docView;
}

- (NSRect)documentRect
{
	NSRect r;

	if (_docView == nil) {
		return NSZeroRect;
	}
	/* THE DOCUMENT VIEW'S FRAME IS ALREADY IN THIS VIEW'S COORDINATES — it is a subview. AND FOR A NON-FLIPPED
	 * CLIP VIEW THAT IS NOT THE WHOLE EXTENT: its origin sits at the BOTTOM, so the document's extent also
	 * includes the area below it, which is what a scroll shows when the document is shorter than the clip view.
	 * Apple's rule, and the reason scrolling past the end is legal in that geometry. */
	r = [_docView frame];
	if (![self isFlipped]) {
		r = NSUnionRect(r, [self bounds]);
	}
	return r;
}

- (NSRect)documentVisibleRect
{
	/* IN THE DOCUMENT'S OWN COORDINATES, which is the question a caller asks: "what of MY content is showing?"
	 *
	 * **AND IT IS WRITTEN OUT RATHER THAN ASKED OF `-convertRect:toView:`.** This tier's view conversion does not
	 * carry a FLIP between a flipped parent and a non-flipped child — the simple relationship `NSView`'s own
	 * header states — and a clip view IS flipped while a document view usually is not, so the conversion returned
	 * a y of ZERO where the answer is the scroll offset. The probe measured that rather than a reader guessing:
	 * the arithmetic is the bounds shifted by the document's origin, which is what the conversion means wherever
	 * the two views agree about which way is up. */
	NSRect b;
	NSRect f;

	if (_docView == nil) {
		return NSZeroRect;
	}
	b = [self bounds];
	f = [_docView frame];
	return NSMakeRect(b.origin.x - f.origin.x, b.origin.y - f.origin.y, b.size.width, b.size.height);
}

/* ---- THE SCROLL ARITHMETIC ------------------------------------------------------------------- */

- (NSPoint)constrainScrollPoint:(NSPoint)newOrigin
{
	NSRect doc;
	NSSize clip = [self bounds].size;
	NSPoint p = newOrigin;

	/* **NO DOCUMENT IS NOT "A DOCUMENT THAT FITS".** With nothing to scroll, the extent is empty, and the centring
	 * branch below would read that emptiness as a zero-sized document and place the origin at `-(clip - 0)/2` — which
	 * is a real number and a wrong one. It left a clip view at (-92.5, -92.5) before any document existed, so the
	 * origin a caller read was negative and the first scroll had to travel back to zero before it could step. A clip
	 * view with no document has nothing to constrain against, so the origin is left where the caller put it. */
	if (_docView == nil) {
		return newOrigin;
	}
	doc = [self documentRect];
	/* **A DOCUMENT SHORTER THAN THE CLIP VIEW IS CENTRED, NOT PINNED** — Apple's rule, and the reason a small
	 * document sits in the middle of a window rather than at one corner of it. */
	if (doc.size.width <= clip.width) {
		p.x = doc.origin.x - (clip.width - doc.size.width) / 2.0;
	} else if (p.x < doc.origin.x) {
		p.x = doc.origin.x;
	} else if (p.x > doc.origin.x + doc.size.width - clip.width) {
		p.x = doc.origin.x + doc.size.width - clip.width;
	}
	if (doc.size.height <= clip.height) {
		p.y = doc.origin.y - (clip.height - doc.size.height) / 2.0;
	} else if (p.y < doc.origin.y) {
		p.y = doc.origin.y;
	} else if (p.y > doc.origin.y + doc.size.height - clip.height) {
		p.y = doc.origin.y + doc.size.height - clip.height;
	}
	return p;
}

/* **A SCROLL POSITION IS A WHOLE NUMBER OF DEVICE PIXELS, ON PURPOSE.** `NSClipView`'s origin is in points, but a
 * scroll is a TRANSLATION OF PIXELS and the two only agree on a device grid: at this machine's 1.332 the demo's
 * 17.58-point step is 23.4 pixels, and a copy that has to move by whole pixels would leave the content 0.4 px out of
 * place — once, and then again on the next step, until a full repaint snapped it back. MEASURED before this rounding:
 * an incremental scroll to the bottom differed from a full repaint of the same state along the outline of every glyph.
 * Snapping costs at most half a pixel of scroll fidelity, which no eye resolves, and buys an exact translation, which
 * is what makes the copy in `-setBoundsOrigin:` pixel-for-pixel the same picture a repaint would produce. */
static CGFloat ag_snap_to_device(CGFloat value, CGFloat scale)
{
	if (!(scale > 0.0)) {
		return value;
	}
	return (CGFloat)(floor((double)(value * scale) + 0.5) / (double)scale);
}

- (void)scrollToPoint:(NSPoint)newOrigin
{
	NSPoint constrained = [self constrainScrollPoint:newOrigin];
	CGFloat scale = [[self window] userSpaceScaleFactor];

	/* CONSTRAINED FIRST, WHICH IS THE WHOLE REASON THIS DOOR EXISTS RATHER THAN A BARE `-setBoundsOrigin:`, and then
	 * snapped: the constraint decides WHERE, and the grid decides which pixel that is. */
	constrained.x = ag_snap_to_device(constrained.x, scale);
	constrained.y = ag_snap_to_device(constrained.y, scale);
	[self setBoundsOrigin:constrained];
	/* AND THE ENCLOSING VIEW IS TOLD, which is Apple's contract: a scroller draws the knob from this, so a scroll
	 * that nobody was told about would leave the knob where it was. */
	if ([[self superview] respondsToSelector:@selector(reflectScrolledClipView:)]) {
		[[self superview] reflectScrolledClipView:self];
	}
}

/* **A SCROLL MOVES PIXELS; IT DOES NOT REDRAW THEM, AND THAT IS WHAT `-copiesOnScroll` HAS ALWAYS MEANT.** The flag has
 * been stored by this class and read by nothing: every scroll marked the whole clip view dirty, so the window redrew the
 * entire visible area — every label, every glyph, every image — to slide the content up sixteen points. MEASURED on the
 * demo's gallery: 22 ms a step, which is a scroller knob that trails the hand.
 *
 * The pixels for everything but the strip that came into view are already on the glass, in the frame this window last
 * committed, and the window can read them (`AGWindowPreviousFrameSized`). So the window is handed the translation and
 * this class keeps only the strip dirty: one copy plus one small draw, and the content is pixel-identical to a full
 * repaint (the screenshot comparison in the notes at the end of this file's README section holds it).
 *
 * **IT IS `-setBoundsOrigin:` RATHER THAN `-scrollToPoint:` BECAUSE EVERY SCROLL GOES THROUGH IT** — a scroller's
 * action, `-autoscroll:`, a document's own frame change, a caller's direct `-setBoundsOrigin:`. A plain `NSView` has
 * nothing better to offer here, so the superclass's answer (mark everything) is taken first and then narrowed; that
 * order is what keeps this class correct when the window declines the copy. */
- (void)setBoundsOrigin:(NSPoint)newOrigin
{
	NSRect oldVisible;
	NSRect newVisible;
	NSRect oldFrame;
	NSRect exposed;
	NSPoint before;
	NSPoint after;
	NSSize movement;

	oldVisible = [self bounds];
	oldFrame = [self frame];
	before = [self convertPoint:NSMakePoint(0.0, 0.0) toView:nil];
	[super setBoundsOrigin:newOrigin];
	/* **NOTHING TO COPY IS NOT A FAILURE: IT IS A REPAINT.** `-copiesOnScroll` off, no document, no window (the
	 * offscreen probes), a scroll that did not move (a re-constrain after a document resize): super's whole-bounds
	 * damage is the answer in every one of them. */
	if (!_copiesOnScroll || _docView == nil || [self window] == nil) {
		return;
	}
	newVisible = [self bounds];
	if (NSEqualPoints(oldVisible.origin, newVisible.origin)) {
		return;
	}
	/* **AND A CLIP VIEW THAT CHANGED SHAPE IS NOT A SCROLL.** A scroller appearing or leaving re-tiles this view, and the
	 * strip arithmetic below describes a translation of unchanged geometry: narrowing the damage after a resize would
	 * leave the pixels the new size uncovered. The frame-change mark `-setFrame:` made stands. */
	if (!NSEqualSizes(oldFrame.size, [self frame].size)) {
		return;
	}
	/* THE MOVEMENT IS MEASURED, NOT DERIVED: the same content point in window space before and after the origin change, so
	 * the answer is right for a flipped clip view inside a flipped document and inside an unflipped one alike. */
	after = [self convertPoint:NSMakePoint(0.0, 0.0) toView:nil];
	movement = NSMakeSize(after.x - before.x, after.y - before.y);
	if (movement.width == 0.0 && movement.height == 0.0) {
		return;
	}
	/* **THE WINDOW IS ASKED BEFORE THE DAMAGE IS NARROWED.** Its NO means the pixels are not going to move — no committed
	 * frame, a GPU buffer, another scroll already pending — and then the whole visible area must still be drawn. */
	if (![[self window] cg_scrollContentInRect:newVisible inView:self by:movement]) {
		return;
	}
	/* **THE BANDS THE NEW RANGE HAS AND THE OLD ONE DID NOT, IN THIS VIEW'S OWN (BOUNDS) SPACE** — which is the space
	 * `-drawRect:` is handed, and the space the damage record lives in. The vertical pair is the common case (one strip,
	 * either at the bottom when scrolled down or at the top when scrolled up); the horizontal pair is unioned with it
	 * when both axes moved. */
	exposed = NSZeroRect;
	if (newVisible.origin.y > oldVisible.origin.y) {
		exposed = NSMakeRect(newVisible.origin.x, oldVisible.origin.y + oldVisible.size.height,
				     newVisible.size.width, newVisible.origin.y - oldVisible.origin.y);
	} else if (newVisible.origin.y < oldVisible.origin.y) {
		exposed = NSMakeRect(newVisible.origin.x, newVisible.origin.y, newVisible.size.width,
				     oldVisible.origin.y - newVisible.origin.y);
	}
	if (newVisible.origin.x != oldVisible.origin.x) {
		BOOL rightward = newVisible.origin.x > oldVisible.origin.x;
		NSRect column = NSMakeRect(rightward ? oldVisible.origin.x + oldVisible.size.width : newVisible.origin.x,
					   newVisible.origin.y,
					   rightward ? newVisible.origin.x - oldVisible.origin.x
						     : oldVisible.origin.x - newVisible.origin.x,
					   newVisible.size.height);

		exposed = NSIsEmptyRect(exposed) ? column : NSUnionRect(exposed, column);
	}
	/* A scroll longer than the view is a page: the bands then cover everything, which is the same answer as before. */
	[self cg_setDirtyRect:NSIntersectionRect(exposed, newVisible)];
	/* **AND THE SUB-PIXEL SLIVERS AT THE EDGES ARE LEFT TO THE COPY, WHICH DELIBERATELY DOES NOT TAKE THEM.** They are
	 * the pixels between the visible rect's fractional device edge and the nearest whole row/column — a clip view is laid
	 * out in points and at a fractional scale its edges are not on the pixel grid. A copy cannot move a fraction of a
	 * pixel, and PAINTING them is worse than leaving them: a repaint of a 1-point band whose edges are fractional
	 * composites the new ink over the old at partial coverage, which is a WASHED ROW rather than the right picture —
	 * MEASURED as the faint white line a person saw through the demo's buttons. So those pixels keep the previous
	 * step's content, a sub-pixel sliver one scroll step behind, at the very edge of the visible area. Exactness there
	 * would require a layout on the device grid, and that is a rendering question this door must not decide. */
}

- (BOOL)autoscroll:(NSEvent *)theEvent
{
	NSRect visible = [self bounds];
	NSPoint where;
	NSPoint target;
	NSSize step = NSMakeSize(16.0, 16.0);

	if (_docView == nil) {
		return NO;
	}
	where = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	/* INSIDE THE VISIBLE RECTANGLE IS NOT A REASON TO SCROLL AT ALL, which is the answer Apple's door gives by
	 * returning NO — the drag is not at an edge. */
	if (NSPointInRect(where, visible)) {
		return NO;
	}
	target = visible.origin;
	if (where.x < NSMinX(visible)) {
		target.x -= step.width;
	} else if (where.x > NSMaxX(visible)) {
		target.x += step.width;
	}
	if (where.y < NSMinY(visible)) {
		target.y -= step.height;
	} else if (where.y > NSMaxY(visible)) {
		target.y += step.height;
	}
	[self scrollToPoint:target];
	return YES;
}

- (void)viewFrameChanged:(NSNotification *)notification
{
	(void)notification;
	/* THE DOCUMENT CHANGED SHAPE, SO THE VISIBLE ORIGIN IS RE-CONSTRAINED: a document that SHRANK must pull the
	 * area back with it, or the view would be left showing a region the document no longer has. */
	[self scrollToPoint:[self bounds].origin];
}

- (void)viewBoundsChanged:(NSNotification *)notification
{
	(void)notification;
	/* AND A BOUNDS CHANGE IS THE SAME PROBLEM FROM THE OTHER SIDE, for the same reason. */
	[self scrollToPoint:[self bounds].origin];
}

/* ---- THE BACKGROUND, THE CURSOR AND THE COPY FLAG --------------------------------------------- */

- (void)setBackgroundColor:(NSColor *)color
{
	NSColor *old = _backgroundColor;

	_backgroundColor = [color retain];
	[old release];
	[self setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor
{
	return _backgroundColor;
}

- (void)setDrawsBackground:(BOOL)flag
{
	_drawsBackground = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)drawsBackground
{
	return _drawsBackground;
}

- (void)setDocumentCursor:(NSCursor *)anObj
{
	_documentCursor = anObj;	/* BORROWED — the cursors are `NSCursor`'s shared instances */
}

- (NSCursor *)documentCursor
{
	return _documentCursor;
}

- (void)setCopiesOnScroll:(BOOL)flag
{
	_copiesOnScroll = flag ? YES : NO;
}

- (BOOL)copiesOnScroll
{
	return _copiesOnScroll;
}

- (void)drawRect:(NSRect)rect
{
	/* THE BACKGROUND IS FILLED WHEN THE FLAG SAYS SO, and the fill goes through the same context every other
	 * view draws into — so "drawn" and "not drawn" are decided in one place rather than by an ancestor. */
	if (_drawsBackground && _backgroundColor != nil) {
		CGContextRef c = [[NSGraphicsContext currentContext] CGContext];

		if (c != NULL) {
			/* **AN `NSColor` IS A `CGColorRef` IN THIS TREE, SO THE FILL TAKES THE COLOUR ITSELF.** There is no
			 * component accessor to call and no conversion to make: `-CGColor` is the bridge, and going through
			 * it is what keeps this from being a second implementation of the colour's own state. */
			CGContextSetFillColorWithColor(c, [_backgroundColor CGColor]);
			CGContextFillRect(c, CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height));
		}
	}
}

@end

/* ============================================================================================ *
 * AND THE SUPERVIEW'S TWO DOORS, WHICH ARE `NSView`'s AND NOT THIS CLASS'S.                      *
 *                                                                                                *
 * THEY WERE DECLARED ON AN `NSView` CATEGORY AND IMPLEMENTED HERE, ON THE WRONG CLASS — and a   *
 * declared-but-undefined door is a trap this tree has recorded: the probe found it as an         *
 * unimplemented-message abort, and the abort named it because the default uncaught handler now   *
 * prints which message went nowhere.                                                            *
 * ============================================================================================ */
@implementation NSView (NSClipViewSuperview)

- (void)reflectScrolledClipView:(NSClipView *)aClipView
{
	/* NOTHING, WHICH IS APPLE'S DEFAULT: the notification is for a view that draws something from it (a
	 * scroller), and a plain view holding a clip view has nothing to draw. */
	(void)aClipView;
}

- (void)scrollClipView:(NSClipView *)aClipView toPoint:(NSPoint)aPoint
{
	[aClipView scrollToPoint:aPoint];
}

@end
