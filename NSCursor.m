/*
 * NSCursor — the pointer's state: its image, its hot spot, and the stack a view pushes.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THE STACK IS THE WHOLE POINT, and it is why this class is worth writing before any window exists. A view
 * that wants a resize cursor while the mouse is over its divider does not set one and remember to put the
 * old one back — it PUSHES on entry and POPS on exit, and the stack is what makes that composable: three
 * nested views can each push, and each pop restores exactly the cursor the previous one had.
 *
 * SO THE CURRENT CURSOR IS THE TOP OF A STACK, NOT A SETTING, and `+currentCursor` answers it. `-set`
 * exists beside it for the caller that wants to replace the current cursor rather than return to it.
 *
 * THE MRC OWNERSHIP IS THE POINT OF THE STACK'S EXISTENCE: a pushed cursor is RETAINED by the stack,
 * because the view that pushed it may be gone by the time it is popped, and `-pop` releases what it
 * removes. `-initWithImage:hotSpot:` retains the image and nothing else. The sixteen shared system cursors
 * are created once each and never released, which is what "shared, one per class" means and is Apple's
 * behaviour too.
 *
 * AND THE MOUSE DOORS ARE PLAIN METHODS, WHICH IS A CORRECTION TO WHAT THIS FILE FIRST CLAIMED: they are
 * NOT a hop in the responder chain — NSCursor is not a responder, Apple's is not either, and `[super
 * mouseEntered:]` had nothing to reach. They are what A VIEW CALLS when the mouse crosses it, and the
 * view's own `-mouseEntered:` is the chain's half of the job. A view that installs a cursor with
 * `-setOnMouseEntered:` sends the cursor the event as well as handling it itself.
 */
#import <AppKit/NSCursor.h>

/* THE STACK. Fourteen is a view hierarchy's worth of nested cursor changes and more than any probe here
 * pushes; a push past the top is dropped rather than corrupting the stack, which is the safe direction for
 * a cosmetic feature. */
#define CG_CURSOR_STACK_MAX 14
static NSCursor *s_stack[CG_CURSOR_STACK_MAX];
static int s_depth;
static NSCursor *s_current;
/* THE HIDE STATE, class-level because Apple's pair is a CLASS method: a cursor object is an image
 * and a hot spot, and "hidden" belongs to the pointer rather than to one of them. */
static int s_hiddenCount;
static BOOL s_hiddenUntilMouseMoves;

@interface NSCursor ()
+ (NSCursor *)cg_sharedCursor:(NSCursor **)slot named:(nullable NSString *)name;
@end

@implementation NSCursor

@synthesize image = _image;
@synthesize hotSpot = _hotSpot;
@synthesize name = _name;
@synthesize isSetOnMouseEntered = _onMouseEntered;
@synthesize isSetOnMouseExited = _onMouseExited;

- (instancetype)initWithImage:(NSImage *)newImage hotSpot:(NSPoint)point
{
	if ((self = [super init]) != nil) {
		_image = [newImage retain];
		_hotSpot = point;
		/* **AND NO NAME, WHICH THE WINDOW TURNS INTO THE COMPOSITOR's DEFAULT.** A cursor made from an image is a
		 * shape no theme has: its pixels are in `_image` and cannot cross the protocol yet (`set_cursor` carries a NAME),
		 * so the honest thing to show is the theme's arrow rather than a name invented for it. See `-name` in the
		 * header. */
		_name = nil;
		_onMouseEntered = NO;
		_onMouseExited = NO;
	}
	return self;
}

- (instancetype)initWithImage:(NSImage *)newImage
	  foregroundColorHint:(NSColor *)fg
	  backgroundColorHint:(NSColor *)bg
		     hotSpot:(NSPoint)point
{
	/* THE TWO HINTS ARE ADVISORY — Apple's own header calls them hints for the window server about the
	 * background a cursor is drawn over — and this tree has no server to advise, so they are accepted and
	 * dropped rather than stored as state nothing reads. */
	(void)fg;
	(void)bg;
	return [self initWithImage:newImage hotSpot:point];
}

- (void)dealloc
{
	[_image release];
	[_name release];
	[super dealloc];
}

/* ------------------------------------------------------------------------- */
/* The stack                                                                  */
/* ------------------------------------------------------------------------- */

- (void)push
{
	if (s_depth < CG_CURSOR_STACK_MAX) {
		s_stack[s_depth++] = [self retain];
	}
	/* AND IT BECOMES CURRENT EITHER WAY: a push past the top still shows the cursor the caller asked for,
	 * which is the useful half of the request. */
	[self set];
}

- (void)set
{
	NSCursor *old = s_current;

	if (old == self) {
		return;
	}
	s_current = [self retain];
	[old release];
}

- (void)pop
{
	if (s_depth > 0) {
		NSCursor *top = s_stack[--s_depth];

		if (top != nil) {
			/* RESTORE WHAT IS UNDERNEATH — the next entry down, or nothing at all if this was the first
			 * push, in which case the current cursor is left as a cursor rather than a dangling pointer. */
			NSCursor *under = (s_depth > 0) ? s_stack[s_depth - 1] : nil;

			if (under != s_current) {
				NSCursor *old = s_current;

				s_current = [under retain];
				[old release];
			}
			[top release];
		}
	}
}

+ (void)pop
{
	[s_current pop];
}

+ (NSCursor *)currentCursor
{
	return s_current;
}

+ (NSCursor *)currentSystemCursor
{
	/* THE SAME ANSWER, AND SAYING WHY: Apple distinguishes the cursor this application set from the one the
	 * window server is showing, and without a server the two cannot differ. */
	return s_current;
}

/* ------------------------------------------------------------------------- */
/* The two flags, and the doors that use them                                  */
/* ------------------------------------------------------------------------- */

- (void)setOnMouseEntered:(BOOL)flag
{
	_onMouseEntered = flag;
}

- (void)setOnMouseExited:(BOOL)flag
{
	_onMouseExited = flag;
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	if (_onMouseEntered) {
		[self push];
	}
	(void)theEvent;
}

- (void)mouseExited:(NSEvent *)theEvent
{
	if (_onMouseExited) {
		[NSCursor pop];
	}
	(void)theEvent;
}

/* ------------------------------------------------------------------------- */
/* The shared system cursors and the names their shapes are known by         */
/* ------------------------------------------------------------------------- */

/* **ONE HELPER, ONE STATIC PER METHOD, NO LOCK: created on first ask and immortal, which is what a shared
 * cursor is.** The slot is a local static's address, so each cursor has exactly one. `name` is the Xcursor name the
 * compositor resolves into artwork, and it is set HERE rather than in a lookup table elsewhere for one reason worth
 * naming: a shared cursor is created once and never asked again, so a name assigned at creation cannot disagree with the
 * object it belongs to — which is exactly the bug a second table keyed by pointer identity would eventually have.
 *
 * **EVERY NAME BELOW WAS CHECKED AGAINST THE VENDORED THEME, NOT INVENTED.** `ls window-server/assets/cursors/Vimix/cursors`
 * carries them all, and a name no theme has costs a fallback the compositor reports once — a pointer that simply does not
 * change is the failure this list exists to prevent. The one cursor with NO name is `disappearingItemCursor`: a poof of
 * smoke is not in an Xcursor theme (the nearest entries, `dnd-none` and `no-drop`, are about a refused drop) and the
 * default arrow is a better answer than a name that would draw something else. */
+ (NSCursor *)cg_sharedCursor:(NSCursor **)slot named:(NSString *)name
{
	if (*slot == nil) {
		*slot = [[self alloc] init];
		(*slot)->_name = [name copy];
	}
	return *slot;
}

+ (NSCursor *)arrowCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"left_ptr"];
}

+ (NSCursor *)IBeamCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"text"];
}

+ (NSCursor *)pointingHandCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"pointer"];
}

+ (NSCursor *)closedHandCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"closedhand"];
}

+ (NSCursor *)openHandCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"openhand"];
}

+ (NSCursor *)resizeLeftCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"left_side"];
}

+ (NSCursor *)resizeRightCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"right_side"];
}

+ (NSCursor *)resizeLeftRightCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"sb_h_double_arrow"];
}

+ (NSCursor *)resizeUpCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"top_side"];
}

+ (NSCursor *)resizeDownCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"bottom_side"];
}

+ (NSCursor *)resizeUpDownCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"sb_v_double_arrow"];
}

+ (NSCursor *)crosshairCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"crosshair"];
}

+ (NSCursor *)disappearingItemCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:nil];
}

+ (NSCursor *)operationNotAllowedCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"not-allowed"];
}

+ (NSCursor *)dragLinkCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"link"];
}

+ (NSCursor *)dragCopyCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"dnd-copy"];
}

+ (NSCursor *)contextualMenuCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"context-menu"];
}

/* **AND THE TWO DIAGONALS, WHICH APPLE DOES NOT PUBLISH** — see `NSCursor.h`. A window's corner resizes and the era's
 * public cursors have no shape for it, so the pointer there used to be the arrow while a press began a resize. The names
 * are the theme's own, so the artwork is the same vendored Vimix art every other pointer comes from. */
+ (NSCursor *)cg_resizeNorthWestSouthEastCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"nwse-resize"];
}

+ (NSCursor *)cg_resizeNorthEastSouthWestCursor
{
	static NSCursor *s;

	return [self cg_sharedCursor:&s named:@"nesw-resize"];
}


/* ---- THE HIDE COUNTER ----------------------------------------------------------------------- */

+ (void)hide
{
	s_hiddenCount++;
}

+ (void)unhide
{
	/* A FLOOR RATHER THAN AN UNDERFLOW, which is Apple's own contract ("each call must be balanced") read in
	 * the only direction that cannot make the pointer appear twice: an unbalanced unhide leaves it at zero. */
	if (s_hiddenCount > 0) {
		s_hiddenCount--;
	}
}

+ (void)setHiddenUntilMouseMoves:(BOOL)flag
{
	s_hiddenUntilMouseMoves = flag;
}

/* THE PRIVATE SEAM — see the header for why it exists at all: the era index carries no public door for the
 * hidden state, so this is what makes the three doors above assertable, and it is what stage C's display
 * seam will read when the pointer's visibility becomes the server's business. */
+ (BOOL)cg_isHidden
{
	return s_hiddenCount > 0 || s_hiddenUntilMouseMoves;
}

@end
