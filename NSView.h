/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSView.h — A RECTANGLE IN A TREE, and the coordinate systems that tree implies (C8.14).
 *
 * THIS SLICE IS THE GEOMETRY, NOT THE DRAWING, and the split is deliberate rather than a stop halfway:
 * almost everything a view does — where it is, what is inside it, which subview a click landed on, what
 * part of it is visible — is answered by the TREE and nothing else. None of that needs a display server,
 * so all of it is provable now. The drawing (`-drawRect:` being called, and being called with a context
 * to draw into) is the next slice, because THAT is where a substrate has to be chosen: this AppKit has
 * no window server, so the honest answer is an offscreen one, and that decision deserves its own turn
 * rather than a guess smuggled in with the geometry.
 *
 * `-drawRect:` IS DECLARED IN THIS SLICE AND DOES NOTHING — which is also what Apple's plain `NSView`
 * does, since a view with no subclass draws nothing and the method exists to be OVERRIDDEN — **AND
 * `-cacheDisplayInRect:toBitmapImageRep:` IS WHAT CALLS IT.** That method is this layer's SUBSTRATE
 * ANSWER: with no window server, a view is asked to draw into a BITMAP the caller supplies, which is the
 * one thing a window system would otherwise be doing for it. `-display` and `-displayIfNeeded` stay
 * ABSENT because they mean "draw me where I live", and nothing here can answer where that is.
 *
 * THE TWO PARTS OF A VIEW'S GEOMETRY, AND WHY BOTH EXIST: `frame` is the view's rectangle in its
 * SUPERVIEW's coordinates, and `bounds` is its own coordinate system. They are usually the same size and
 * both start at the origin, which is why the pair looks redundant until a view scrolls or scales — this
 * layer keeps them SEPARATE and states the relationship it does not model: setting one sets the other's
 * SIZE and leaves its ORIGIN alone. Apple's bounds/frame relationship is richer (a bounds origin that is
 * not zero is a scroll offset), and the richer part is not claimed here.
 *
 * `flipped` IS THE DIRECTION OF THE Y AXIS, and it is the reason coordinate conversion is not arithmetic
 * on the frame alone: an unflipped view has its origin at its BOTTOM-LEFT and y growing up, a flipped one
 * at its TOP-LEFT with y growing down, so the same point converts differently. Getting this wrong is
 * visible as a mirrored drawing rather than as an error, which is why the probe checks a FLIPPED
 * SUPERVIEW against an UNFLIPPED CHILD rather than only the easy case.
 *
 * WHAT IS NOT HERE, AND WHY: `window`, and everything that needs one (`-display`,
 * `-displayIfNeeded`, `-viewDidMoveToWindow`, the layer and backing-scale members
 * `-convertPointToBacking:`/`-convertPointToLayer:` and their siblings) — there is no window server, and
 * a scale factor needs a screen to ask. `-graphicsContext`, `-lockFocus`, `-unlockFocus`,
 * `-lockFocusIfCanDraw` and the `…ToBase`/`…FromBase` conversions are ABSENT BECAUSE THEY ARE `struck`
 * ROWS: deprecated at this tree's pinned vintage, and the modern replacements
 * (`-cacheDisplayInRect:toBitmapImageRep:`, `-convertPoint:fromView:`) are the ones a caller should
 * have. The responder chain, the layer tree, `NSView`'s layout constraints and its `NSMenu`/tooltip
 * surface each need a subsystem that does not exist here; each is absent rather than stubbed.
 */

#import <AppKit/NSResponder.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSTrackingArea.h>
/* AND `NSGraphics.h` IS IMPORTED RATHER THAN ASSUMED, because this header USES `NSFocusRingType` for a property and
 * two doors (`-focusRingType`, `-setFocusRingType:`, `+defaultFocusRingType`) and no longer declares it: the type
 * moved to its APPLE home, which is the drawing vocabulary's header. AppKit's own `NSView.h` declares the type itself,
 * so the move is a deviation from the era's FILE LAYOUT made deliberately, and the reason is the one this plan's
 * blanket rule gives — the LEDGER names `AppKit/NSGraphics.h` as the ground for its three cases, and the tree follows
 * the ledger's ground. */
#import <AppKit/NSGraphics.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

/* FORWARDED: both are pointer parameters or return types here, and neither header is owed — a `@class` is a
 * forward declaration and not an `@interface`. */
@class NSCursor;
@class NSGraphicsContext;
@class NSWindow;
/* AND `NSScreen`, FOR THE SAME REASON AND WITH THE SAME SAFETY: its class row is shipped, so a forward
 * declaration cannot move it. */
@class NSScreen;

/* NAMED BECAUSE APPLE'S SIGNATURES FOR THE DOORS BELOW NAME THEM. A forward declaration only FLIPS a `class` row
 * the ledger still holds OPEN — the trap recorded for this sweep — and these four (NSEvent, NSImage, NSImageRep,
 * NSPasteboard) are all shipped, so naming them cannot move anything. */
@class NSEvent;
@class NSImage;
@class NSPasteboard;


/* ============================================================================================ *
 * THE FOCUS-RING VOCABULARY, WHICH LIVES IN `NSGraphics.h` RATHER THAN HERE.                   *
 * ============================================================================================ */

/* **`NSFocusRingType` USED TO BE DECLARED AT THIS LINE, AND IT MOVED — BECAUSE APPLE DECLARES IT IN `NSGraphics.h`.**
 * The blanket rule this plan works under is "match Apple, including which header", and the era's own tree puts the
 * focus-ring type beside the drawing vocabulary (the ledger's rows for its three cases name `AppKit/NSGraphics.h` as
 * their source). What did not change is the values or the compiler's view of them: this header imports `NSGraphics.h`
 * below, so every reader of a view's `-focusRingType` still sees the type, and the three case rows stay shipped
 * exactly as they were — a MOVE, not a re-declaration and not a new row. */

/* ============================================================================================ *
 * THE VIEW'S VOCABULARIES: FOUR ENUMS, THE AUTORESIZING MASKS, TWO TAGS AND TEN NAMED VALUES.    *
 * ============================================================================================ */

/* **APPLE PUBLISHES CASE NAMES FOR ALL FOUR OF THESE AND NO VALUES, WHICH IS THE STANDING RULE'S CASE: WHAT IS
 * WRITTEN HERE IS THE ARTEFACT'S, IN THE HEADER'S OWN ORDER, AND A CALLER MAY RELY ON THE NAMES RATHER THAN THE
 * NUMBERS.**
 *
 * AND THE LEDGER'S TWO `var` ROWS FOR THE BACKGROUND STYLE — `NSBackgroundStyleDark`, `NSBackgroundStyleLight` —
 * ARE THE SAME ENUM'S LIVE CASE NAMES, so they are declared ONCE, as cases: the modern spelling of that pair moved
 * from a free constant to an enumerator, and a row is answered by a declaration of THAT NAME rather than by the
 * shape the row happens to have. A `...DarkName` placeholder stood here in the first draft, which was scaffolding
 * rather than an implementation. */
typedef enum {
	NSBackgroundStyleLight = 0,
	NSBackgroundStyleDark,
	NSBackgroundStyleRaised,
	NSBackgroundStyleLowered
} NSBackgroundStyle;

typedef enum {
	NSNoBorder = 0,
	NSLineBorder,
	NSGrooveBorder,
	NSBezelBorder
} NSBorderType;

typedef enum {
	NSViewLayerContentsPlacementScaleAxesIndependently = 0,
	NSViewLayerContentsPlacementScaleProportionallyToFit,
	NSViewLayerContentsPlacementScaleProportionallyToFill,
	NSViewLayerContentsPlacementCenter,
	NSViewLayerContentsPlacementTop,
	NSViewLayerContentsPlacementTopRight,
	NSViewLayerContentsPlacementRight,
	NSViewLayerContentsPlacementBottomRight,
	NSViewLayerContentsPlacementBottom,
	NSViewLayerContentsPlacementBottomLeft,
	NSViewLayerContentsPlacementLeft,
	NSViewLayerContentsPlacementTopLeft
} NSViewLayerContentsPlacement;

typedef enum {
	NSViewLayerContentsRedrawNever = 0,
	NSViewLayerContentsRedrawOnSetNeedsDisplay,
	NSViewLayerContentsRedrawBeforeViewResize,
	NSViewLayerContentsRedrawDuringViewResize
} NSViewLayerContentsRedrawPolicy;

/* THE AUTORESIZING MASKS ARE BITS RATHER THAN AN ORDERED SET, which is why their values are the long-standing ones
 * rather than a sequence: a view's struts and springs are a MASK, and this tree's layout already treats them as one
 * (frames plus parent-relative masks, no sibling bindings). NO MARGIN IS 0 — a view that does not resize. */
enum {
	NSViewNotSizable = 0,
	NSViewMinXMargin = 1,
	NSViewWidthSizable = 2,
	NSViewMaxXMargin = 4,
	NSViewMinYMargin = 8,
	NSViewHeightSizable = 16,
	NSViewMaxYMargin = 32
};

typedef NSInteger NSToolTipTag;
typedef NSInteger NSTrackingRectTag;

/* AND THE NAMED VALUES: TWO NOTIFICATIONS, THREE FULL-SCREEN DICTIONARY KEYS AND THE DEFINITION-PRESENTATION
 * ENTRIES. THE STRINGS ARE THE NAMES, which is the house pattern every notification in this tree already follows —
 * Apple's own values for the last of these are `@"DictionaryApplication"` and `@"Overlay"` stored under the key. */
extern NSString *NSViewDidUpdateTrackingAreasNotification;
extern NSString *NSViewFocusDidChangeNotification;
extern NSString *NSFullScreenModeSetting;
extern NSString *NSFullScreenModeAllScreens;
extern NSString *NSFullScreenModeApplicationPresentationOptions;
extern NSString *NSDefinitionPresentationTypeKey;
extern NSString *NSDefinitionPresentationTypeDictionaryApplication;
extern NSString *NSDefinitionPresentationTypeOverlay;

@interface NSView : NSResponder
{
	/* THE FRAME IS THE VIEW IN ITS SUPERVIEW; THE BOUNDS ARE ITS OWN SYSTEM. See the note above for the
	 * relationship this layer keeps simple. */
	NSRect _frame;
	/* **WHETHER THIS VIEW ASKS TO BE HEARD WHEN ITS FRAME CHANGES, AND WHETHER ONE CHANGED WHILE IT WAS NOT
	 * ASKING.** The second is Apple's own edge case rather than bookkeeping of ours: a change made while the flag
	 * was off must still be announced the moment the flag comes back on. */
	BOOL _postsFrameChangedNotifications;
	BOOL _cg_frameChangedWhileMuted;
	NSRect _bounds;
	BOOL _flipped;
	BOOL _needsDisplay;
	BOOL _hidden;
	/* OWNED. The subviews are ordered BACK TO FRONT — index 0 is the bottom, the LAST is the top — which
	 * is Apple's order and the reason `-hitTest:` walks the array in REVERSE. */
	NSMutableArray *_subviews;
	/* BORROWED, as Apple's is: a view does not own its superview, and a parent owns its children. */
	NSView *_superview;
	/* THE KEY-VIEW CHAIN'S LINK, BORROWED as the superview is: a view does not own the view Tab goes to, and a
	 * chain of retained links would keep a whole tree alive from one pointer. The WINDOW computes the default
	 * loop; this is where a caller puts a different one. */
	NSView *_nextKeyView;
	/* THE CURSOR RECTS, OWNED, as pairs of a rect and the cursor for it. They are REBUILT rather than edited by a
	 * caller: a view adds them in `-resetCursorRects`, and the window calls that when the rects are stale. */
	NSMutableArray *_cursorRects;
	/* AND WHETHER THEY NEED REBUILDING. A view that moved, resized or changed what it shows says so through its
	 * window, which is the only object that knows when a cursor pass is due. */
	BOOL _cursorRectsStale;
	/* AND THE WINDOW, BORROWED TOO. A view tree's root is in a window and every view needs to know which, for
	 * the two move notifications and for the coordinate conversion the FRAME is expressed in. */
	NSWindow *_window;
	/* WHAT NEEDS DRAWING, AS A REGION RATHER THAN A FLAG: `-setNeedsDisplayInRect:` invalidates a PART of a
	 * view, and the union of those parts is what `-displayIfNeededInRect:` consults. The boolean above stays
	 * as the coarse "something needs display" because that is what the ledger's `-needsDisplay` answers. */
	NSRect _dirtyRect;
	BOOL _hasDirtyRect;
	/* THE SET `-registerForDraggedTypes:` KEEPS: see the doors. */
	NSMutableArray *_cg_registeredDraggedTypes;
	CGFloat _alphaValue;
	NSInteger _tag;
	NSUInteger _autoresizingMask;
	BOOL _autoresizesSubviews;
	BOOL _postsBoundsChangedNotifications;
	NSString *_toolTip;
	NSMutableArray *_trackingAreas;
	NSMutableArray *_toolTips;
	/* AND THE LEGACY TRACKING RECTS' OWN TAGS — see the note at the doors: the two families shared one array, which was
	 * survivable while both held placeholders and would not be once that array holds real `NSTrackingArea`s. */
	NSMutableArray *_cg_trackingRects;
	NSPoint _cg_translation;
	NSSize _cg_unitSquareSize;
	CGFloat _cg_rotation;
	NSViewLayerContentsPlacement _layerContentsPlacement;
	NSViewLayerContentsRedrawPolicy _layerContentsRedrawPolicy;
	BOOL _acceptsTouchEvents;
	BOOL _wantsRestingTouches;
	BOOL _canDrawConcurrently;
	BOOL _wantsDefaultClipping;
	BOOL _wantsLayer;
	NSArray *_backgroundFilters;
	id _compositingFilter;
	NSArray *_contentFilters;
	id _shadow;
	id _pageHeader;
	id _pageFooter;
	NSFocusRingType _focusRingType;
	NSView *_focusView;
	CGFloat _frameCenterRotation;
}

/* THE DESIGNATED INITIALISER. The frame is given in the SUPERVIEW's coordinates, and the bounds start as
 * the same size at the origin, which is what every view begins as. */
- (instancetype)initWithFrame:(NSRect)frameRect;

/* THE GEOMETRY. Setting either sets the other's SIZE and leaves its ORIGIN alone. */
@property NSRect frame;
@property NSRect bounds;

/* THE Y AXIS DIRECTION. `-isFlipped` is the getter, as Apple's is. */
@property (getter=isFlipped) BOOL flipped;

/* WHETHER THE VIEW HAS BEEN DRAWN SINCE SOMETHING CHANGED. A NEW VIEW NEEDS DISPLAY, because nothing has
 * drawn it yet. Nothing in this slice acts on the flag — the drawing slice does — but a caller can set
 * and read it, and the setter is Apple's `-setNeedsDisplay:`. */
@property BOOL needsDisplay;

/* AND WHETHER IT IS HIDDEN. Not a drawing decision: `-hitTest:` ignores a hidden view, which is the one
 * thing this slice can honour about it. */
@property (getter=isHidden) BOOL hidden;

/* THE TREE. `-addSubview:` RETAINS and re-parents (removing the view from a previous superview first,
 * as Apple's does); `-removeFromSuperview` clears the borrowed link. `_superview` is BORROWED, so a view
 * that is still in a parent's list must outlive nothing — the parent owns it. */
@property (readonly, copy) NSArray *subviews;
@property (nullable, readonly) NSView *superview;
@property (nullable, readonly) NSWindow *window;
/* THE OFFSCREEN RENDER. The view draws ITSELF AND ITS SUBVIEWS into the caller's bitmap — which is what
 * Apple's method of this name does, and the reason it is the right door here: it needs no window, it
 * takes the destination from the caller, and it is a `open` row rather than a deprecated one.
 *
 * THE PIXELS GO THROUGH A CANVAS AND THEN INTO THE REP, rather than the context being made over the
 * rep's own bytes, and the reason is MEASURED: this tree's bitmap context is premultiplied-FIRST
 * little-endian and a rep's bytes are premultiplied-LAST, so the two cannot be the same buffer. The
 * canvas comes from `NSImage`'s offscreen implementation — one canvas, one channel swizzle, stated once
 * — and the copy into the rep is then a row-ordered byte move between two buffers that agree.
 *
 * A rep with no writable bytes (a CGIMAGE-BACKED one, which is what `+imageRepWithData:` produces) is
 * REFUSED BY NAME: caching into it would need a second copy this layer has no way to hand back.
 * `-drawRect:` IS GIVEN THE REP'S RECT IN THE VIEW'S OWN COORDINATES, and every view in the tree is
 * given the CONSERVATIVE dirty rect — its whole bounds — rather than a finer clip; that is a stated
 * simplification, not a claim about the argument's precision. */
- (void)cacheDisplayInRect:(NSRect)rect toBitmapImageRep:(nullable NSBitmapImageRep *)bitmapImageRep;

- (void)addSubview:(NSView *)aView;
- (void)removeFromSuperview;

/* THE TREE QUERIES. `-isDescendantOf:` asks the ancestor chain; `-hitTest:` asks the tree the other way
 * round — WHICH VIEW IS AT THIS POINT — and takes its point in the SUPERVIEW's coordinates, as Apple's
 * does. It walks the subviews in REVERSE (topmost first), and answers self only if the point is inside
 * its bounds. */
- (BOOL)isDescendantOf:(NSView *)aView;
- (nullable NSView *)hitTest:(NSPoint)point;

/* COORDINATE CONVERSION, WHICH IS WHERE `flipped` HAS TEETH. A NULL VIEW MEANS "the window's coordinate
 * system", and with no window here the ROOT VIEW stands in for it — the one place this slice has to give
 * NULL a meaning, and it is stated rather than implied. */
- (NSPoint)convertPoint:(NSPoint)point fromView:(nullable NSView *)view;
- (NSPoint)convertPoint:(NSPoint)point toView:(nullable NSView *)view;
- (NSRect)convertRect:(NSRect)rect fromView:(nullable NSView *)view;
- (NSRect)convertRect:(NSRect)rect toView:(nullable NSView *)view;

/* THE PART OF THE VIEW NOT CLIPPED AWAY BY ITS ANCESTORS, in the view's own coordinates. */
@property (readonly) NSRect visibleRect;

/* THE OVERRIDE POINT, WHICH THIS SLICE DECLARES AND DOES NOT CALL. A plain view draws nothing. */

/* ============================================================================================ *
 * THE VIEW TREE'S OWN DISPLAY DOORS. Until this slice the WINDOW called the content view's    *
 * `-drawRect:` directly, which paints ONE view; these are what paint a TREE, because the      *
 * recursion belongs to the view and not to an observer of it.                                 *
 *                                                                                                *
 * AND THE DIRTY REGION IS WHY `-setNeedsDisplayInRect:` EXISTS AT ALL: a flag can only say     *
 * "everything", and a scrolling or typing view invalidates a strip. The union of what has been  *
 * invalidated is kept here, and `-displayIfNeededInRect:` is the door that honours it.          *
 * ============================================================================================ */

/* WHAT NEEDS DRAWING. `-needsDisplayInRect:` answers whether any INVALIDATED part intersects the rect, which
 * is the question an optimising caller asks; the boolean `-needsDisplay` is the coarse one. */
- (void)setNeedsDisplayInRect:(NSRect)invalidRect;
- (BOOL)needsDisplayInRect:(NSRect)rect;

/* DRAWING A TREE. `-displayRect:` draws the receiver AND its subviews within the rect, which is the recursion
 * the window used to leave to the content view. The `IgnoringOpacity` forms differ only in that no opacity
 * layer is asked for — and this tree asks for none anywhere, so they are the same drawing with the name a
 * caller used, stated rather than pretended. */
- (void)displayRect:(NSRect)rect;
- (void)displayRectIgnoringOpacity:(NSRect)rect context:(NSGraphicsContext *)context;
- (void)displayIfNeededInRect:(NSRect)rect;
- (void)displayIfNeededInRectIgnoringOpacity:(NSRect)rect;
- (void)displayIfNeededIgnoringOpacity;

/* THE GEOMETRY, PIECE BY PIECE. Each of the three setters invalidates the view and tells its SUBVIEWS to
 * resize, because a frame change is the only thing that rearranges them. */
- (void)setFrameSize:(NSSize)newSize;

/* ============================================================================================ *
 * THE VIEW'S LAST SIXTY-FOUR DOORS: THE ONES THAT DO REAL WORK, AND THE ONES THAT NAME A          *
 * SUBSTRATE THIS TIER HAS NOT GOT.                                                                *
 * ============================================================================================ */

/* **THE ONES THAT COMPUTE.** `-ancestorSharedWithView:` and `-viewWithTag:` walk the tree this class owns;
 * `-replaceSubview:with:` swaps a child keeping the Z-order it had; `-needsToDrawRect:` asks the dirty rect;
 * `-centerScanRect:` snaps a rectangle to whole pixels, which is arithmetic rather than a substrate;
 * `-bitmapImageRepForCachingDisplayInRect:` MAKES the rep the drawing door already fills; the key-view relations are
 * `-ancestorSharedWithView:`'s cousins; and the gate's rectangles are this class's own dirty-rect bookkeeping. */
- (nullable NSView *)ancestorSharedWithView:(NSView *)aView;
- (nullable id)viewWithTag:(NSInteger)aTag;
- (void)replaceSubview:(NSView *)oldView with:(NSView *)newView;
- (BOOL)needsToDrawRect:(NSRect)aRect;
- (NSRect)centerScanRect:(NSRect)aRect;
- (nullable NSBitmapImageRep *)bitmapImageRepForCachingDisplayInRect:(NSRect)rect;
- (void)getRectsBeingDrawn:(const NSRect * _Nullable * _Nullable)rects count:(NSInteger * _Nullable)count;
- (void)getRectsExposedDuringLiveResize:(NSRect * _Nullable)exposedRects count:(NSInteger * _Nullable)count;
- (void)translateRectsNeedingDisplayInRect:(NSRect)clipRect by:(NSSize)delta;
- (void)setKeyboardFocusRingNeedsDisplayInRect:(NSRect)rect;
- (void)scrollPoint:(NSPoint)aPoint;
- (BOOL)scrollRectToVisible:(NSRect)aRect;
- (NSRect)adjustScroll:(NSRect)newVisible;
- (void)scrollRect:(NSRect)aRect by:(NSSize)delta;

/* AND THE HOOKS A SUBCLASS OVERRIDES, which this class must DECLARE and must not invent behaviour for: the two
 * subview notices, the three visibility and live-resize notices, and `-viewWillDraw`. The first two are abstract
 * here because their bodies belong to whoever overrides them — declaring them is the whole point, and the tree's
 * rule that nothing is declared without a definition is met by bodies that do nothing, which is what a plain view
 * has to do. */
- (void)didAddSubview:(NSView *)subview;
- (void)willRemoveSubview:(NSView *)subview;
- (void)viewDidHide;
- (void)viewDidUnhide;
- (void)viewWillDraw;
- (void)viewWillStartLiveResize;
- (void)viewDidEndLiveResize;
- (void)layout;
/* **AND THE DOOR THAT RECOMPUTES AN AREA'S REGION, WHICH USED TO BE A RECORDED NO-OP.** Apple calls it when the view's
 * geometry changed, and this class calls it from `-cg_frameDidChangeFrom:` — the one place a frame change is noticed.
 * Its default POSTS `NSViewDidUpdateTrackingAreasNotification` and otherwise does nothing, which is the honest answer
 * for this engine: a region is resolved against the view's CURRENT position on every motion (see
 * `NSWindow -cg_updateTrackingForPoint:`), so a plain area never needs recomputing and neither does one whose rect
 * follows the view's own bounds. The case the hook exists for is `NSTrackingInVisibleRect`, whose rectangle is
 * `-visibleRect` — and even that is computed, so the hook is where a caller recomputes what THEY baked, not where
 * this class repairs itself. */
- (void)updateTrackingAreas;

/* **THE TRACKING AND TOOL-TIP FAMILY, AND THE AREA HALF IS NOW A REAL MECHANISM RATHER THAN A STORE.** The two AREA
 * doors take a real `NSTrackingArea` — the class was a row this tier had not earned when these were written, so they
 * were spelled `id` and the array was a list nobody read. The class exists now, so the type is named and the window's
 * tracking engine is what reads the list.
 *
 * THE TRACKING-RECT PAIR IS THE PRE-10.5 FORM OF THE SAME IDEA AND STILL STORES TAGS RATHER THAN FIRING CALLBACKS,
 * which is stated rather than implied: the areas are the engine it will be built on, and until that is done a caller
 * who wants enter and exit gets them from an area. Its tags live in their OWN list, because the two doors shared one
 * array and mixing tags with areas is how `-trackingAreas` would have started answering a mixture of two types. */
- (NSTrackingRectTag)addTrackingRect:(NSRect)aRect owner:(nullable id)anObject userData:(nullable void *)data assumeInside:(BOOL)flag;
- (void)removeTrackingRect:(NSTrackingRectTag)tag;
- (void)addTrackingArea:(NSTrackingArea *)trackingArea;
- (void)removeTrackingArea:(NSTrackingArea *)trackingArea;
- (NSToolTipTag)addToolTipRect:(NSRect)aRect owner:(nullable id)anObject userData:(nullable void *)data;
- (void)removeToolTip:(NSToolTipTag)tag;
- (void)removeAllToolTips;

/* AND THE FOUR ANSWERED HANDS AND FLAGS, each for its own reason: `-acceptsFirstMouse:` is NO for a plain view
 * (Apple's own default, an override point), `-shouldDelayWindowOrderingForEvent:` likewise, `-shouldDrawColor` is
 * YES, `-menuForEvent:` is nil because this tier has no menus, `-makeBackingLayer` is nil because it has no layers,
 * and `-mouse:inRect:` — the pre-10.0 door — reports that the point was outside the rectangle rather than
 * pretending to hit-test. */
- (BOOL)acceptsFirstMouse:(nullable NSEvent *)theEvent;
- (BOOL)shouldDelayWindowOrderingForEvent:(nullable NSEvent *)theEvent;
- (BOOL)shouldDrawColor;
- (nullable id)menuForEvent:(nullable NSEvent *)theEvent;
- (nullable id)makeBackingLayer;
- (BOOL)mouse:(NSPoint)aPoint inRect:(NSRect)aRect;

/* AND THE OLD GRAPHICS-STATE DOORS. `-lockFocusIfCanDraw` is REAL — it is the question "may I draw", and this
 * view answers it the way `-canDraw` does — while the four state-stack doors are REFUSED BY NAME, because this
 * tier draws through a `CGContext` and has no state stack for them to push and pop. */
- (BOOL)lockFocusIfCanDraw;
- (BOOL)lockFocusIfCanDrawInContext:(nullable NSGraphicsContext *)context;
- (void)allocateGState;
/* **AND THE THREE COORDINATE-SYSTEM DOORS, WHICH ARE RECORDED WITH THEIR EFFECT NAMED.** Apple's doors translate the
 * receiver's coordinate system, scale its unit square and rotate it — a TRANSFORM this tier's drawing does not apply,
 * because a view is drawn into the caller's context in its own frame's coordinates. What the doors can do honestly is
 * keep the request, so each does that and the three seams below are how a probe reads it back: a store with no reader
 * is indistinguishable from one that was never written. */
- (void)translateOriginToPoint:(NSPoint)translation;
- (void)scaleUnitSquareToSize:(NSSize)newUnitSize;
- (void)rotateByAngle:(CGFloat)angle;
- (NSPoint)cg_translation;
- (NSSize)cg_unitSquareSize;
- (CGFloat)cg_rotation;
- (void)releaseGState;
- (void)setUpGState;
- (void)renewGState;

/* AND THE PRINTING FAMILY, REFUSED BY NAME TOGETHER: the two document doors, the two page doors, the two border
 * drawers, the page-range question, the two page-adjustment questions, the page rectangle, the print location, the
 * ruler, the definition look-up and the two EPS/PDF writers. */
- (void)beginDocument;
- (void)endDocument;
- (void)beginPageInRect:(NSRect)aRect atPlacement:(NSPoint)location;
- (void)endPage;
- (void)drawPageBorderWithSize:(NSSize)borderSize;
- (void)drawSheetBorderWithSize:(NSSize)borderSize;
/* AND THE PAGE-RANGE QUESTION TAKES A NULLABLE OUT-PARAMETER, which is what the implementation accepts: it is a
 * REFUSAL (`fn_refuse_window`), so it reads nothing through the pointer — a caller asking "do you know your page
 * range" and passing NULL must get the refusal rather than undefined behaviour, and the probe asserts exactly that. */
- (BOOL)knowsPageRange:(nullable NSRangePointer)range;
- (void)adjustPageWidthNew:(CGFloat *)newRight left:(CGFloat)oldLeft right:(CGFloat)oldRight limit:(CGFloat)rightLimit;
- (void)adjustPageHeightNew:(CGFloat *)newBottom top:(CGFloat)oldTop bottom:(CGFloat)oldBottom limit:(CGFloat)bottomLimit;
- (NSRect)rectForPage:(NSInteger)page;
- (NSPoint)locationOfPrintRect:(NSRect)aRect;
- (nullable id)rulerView;
- (void)showDefinitionForAttributedString:(NSAttributedString *)attrString atPoint:(NSPoint)textBaselineOrigin;
- (void)writeEPSInsideRect:(NSRect)rect toPasteboard:(nullable NSPasteboard *)pasteboard;
- (void)writePDFInsideRect:(NSRect)rect toPasteboard:(nullable NSPasteboard *)pasteboard;

/* AND THE DRAG AND FULL-SCREEN DOORS, on the grounds their class-mates already state: no drag session, and the
 * full-screen mode is the manager's. */
- (BOOL)dragFile:(NSString *)filename fromRect:(NSRect)rect slideBack:(BOOL)aFlag event:(nullable NSEvent *)event;
- (BOOL)dragPromisedFilesOfTypes:(NSArray *)typeArray fromRect:(NSRect)rect source:(nullable id)sourceObject
			slideBack:(BOOL)aFlag event:(nullable NSEvent *)event;
- (BOOL)enterFullScreenMode:(nullable NSScreen *)screen withOptions:(nullable NSDictionary *)options;
- (void)exitFullScreenModeWithOptions:(nullable NSDictionary *)options;

/* **THE WINDOW LINK, WHICH A VIEW GETS BY BEING PUT INTO ONE.** `-window` answers the window a view is in, and the
 * link is a POINTER this class carries down a subtree rather than a walk up one: `-addSubview:` sets it for the
 * subtree it adopts, and a window setting its content view has to do the same. A private door declared here because
 * the two classes are where it is used, and because a content view whose subtree has no window is a view whose
 * `-window`, `-nextValidKeyView` and coordinate conversions all answer nothing. */
- (void)cg_setWindow:(nullable NSWindow *)aWindow;

/* ============================================================================================ *
 * THE VIEW'S PROPERTIES: NINE THAT COMPUTE, AND THE REST THAT STORE OR ANSWER.                   *
 * ============================================================================================ */

/* **THE ONES THAT COMPUTE, which is where this class's real behaviour is.** `-hiddenOrHasHiddenAncestor` and
 * `-opaqueAncestor` walk the SUPERVIEW chain, the second stopping at the first view whose `-isOpaque` says YES;
 * `-rectPreservedDuringLiveResize` asks the door the promise is declared on; `-registeredDraggedTypes` reports the
 * set the drag pair keeps. AND `-enclosingScrollView` CANNOT WALK FOR ANYTHING: `NSScrollView` is not in this tier
 * at all — NSClipView.h says as much, a scroll view being the frame, the scrollers and the ruler — so nil is the
 * answer with that reason rather than a search of a tree for a class that does not exist. The same reading costs
 * `-enclosingMenuItem` its search: this tier has no menus. */
- (BOOL)hiddenOrHasHiddenAncestor;
- (nullable NSView *)opaqueAncestor;
- (nullable NSView *)enclosingScrollView;
- (nullable NSView *)enclosingMenuItem;
- (BOOL)rectPreservedDuringLiveResize;
- (nullable NSArray *)registeredDraggedTypes;
- (nullable NSView *)previousKeyView;
- (nullable NSView *)nextValidKeyView;
- (nullable NSView *)previousValidKeyView;
- (BOOL)canBecomeKeyView;
- (BOOL)canDraw;
- (BOOL)mouseDownCanMoveWindow;
- (BOOL)needsPanelToBecomeKey;
- (BOOL)inFullScreenMode;
- (BOOL)rotatedFromBase;
- (BOOL)rotatedOrScaledFromBase;
- (CGFloat)boundsRotation;
- (CGFloat)frameRotation;
- (CGFloat)frameCenterRotation;
- (void)setFrameCenterRotation:(CGFloat)angle;
- (CGFloat)heightAdjustLimit;
- (CGFloat)widthAdjustLimit;

/* **THE STORED ONES**, each with the effect named where the effect is someone else's: a tag is this class's own
 * bookkeeping, the autoresizing mask is what this tree's layout ALREADY treats as a mask, whether subviews resize
 * with it is a flag the layout reads, the bounds-changed announcement is a promise this tier STATES rather than
 * keeps, and the layer-content placement and redraw policy are the two enums this class declares — RECORDED,
 * because there is no layer here to redraw. */
- (NSInteger)tag;
- (void)setTag:(NSInteger)anInteger;
- (NSUInteger)autoresizingMask;
- (void)setAutoresizingMask:(NSUInteger)mask;
- (BOOL)autoresizesSubviews;
- (void)setAutoresizesSubviews:(BOOL)flag;
- (BOOL)postsBoundsChangedNotifications;
- (void)setPostsBoundsChangedNotifications:(BOOL)flag;
- (nullable NSString *)toolTip;
- (void)setToolTip:(nullable NSString *)string;
- (nullable NSArray *)trackingAreas;
- (NSViewLayerContentsPlacement)layerContentsPlacement;
- (void)setLayerContentsPlacement:(NSViewLayerContentsPlacement)placement;
- (NSViewLayerContentsRedrawPolicy)layerContentsRedrawPolicy;
- (void)setLayerContentsRedrawPolicy:(NSViewLayerContentsRedrawPolicy)policy;

/* AND THE FLAGS AND ANSWERS WHOSE SUBSTRATE THIS TIER HAS NOT GOT: layers, filters, touches, the shadow, the input
 * context, the default menu and the printing furniture. Each is recorded or answered, with the substrate named. */
- (BOOL)acceptsTouchEvents;
- (void)setAcceptsTouchEvents:(BOOL)flag;
- (BOOL)wantsRestingTouches;
- (void)setWantsRestingTouches:(BOOL)flag;
- (BOOL)canDrawConcurrently;
- (void)setCanDrawConcurrently:(BOOL)flag;
- (BOOL)wantsDefaultClipping;
- (void)setWantsDefaultClipping:(BOOL)flag;
- (BOOL)wantsLayer;
- (void)setWantsLayer:(BOOL)flag;
- (nullable id)layer;
- (nullable NSArray *)backgroundFilters;
- (void)setBackgroundFilters:(nullable NSArray *)filters;
- (nullable id)compositingFilter;
- (void)setCompositingFilter:(nullable id)filter;
- (nullable NSArray *)contentFilters;
- (void)setContentFilters:(nullable NSArray *)filters;
- (nullable id)shadow;
- (void)setShadow:(nullable id)shadow;
- (nullable id)inputContext;
- (nullable id)defaultMenu;
- (nullable id)pageHeader;
- (void)setPageHeader:(nullable id)header;
- (nullable id)pageFooter;
- (void)setPageFooter:(nullable id)footer;
- (nullable NSString *)printJobTitle;
- (NSFocusRingType)focusRingType;
- (void)setFocusRingType:(NSFocusRingType)focusRingType;
+ (NSFocusRingType)defaultFocusRingType;
- (nullable NSView *)focusView;
- (void)setFocusView:(nullable NSView *)aView;


/* ============================================================================================ *
 * THE DOORS APPLE DECLARES ON THE VIEW AND THIS TIER CANNOT MEET, plus the three that answer.    *
 * ============================================================================================ */

/* THESE ARE THE LEDGER'S OWN ROWS, SHIPPED UNTIL NOW ON NSWindow's DECLARATIONS — the sweep matches names
 * globally, and the check that demanded those rows be flipped said so in as many words. Apple's 10.6 NSView.h
 * declares all seven, so they were always owed HERE, on the class whose rows they are. The signatures are
 * Apple's, including the ones that differ from the window's (`at:(NSPoint)viewLocation`). */
- (nullable NSData *)dataWithEPSInsideRect:(NSRect)rect;	/* needs a PDF/EPS producer: this tree's CG has none */
- (nullable NSData *)dataWithPDFInsideRect:(NSRect)rect;	/* the same substrate, and the PDF half is parked */
- (void)print:(nullable id)sender;			/* needs the printing system (NSPrintOperation) */
- (void)dragImage:(nullable NSImage *)anImage		/* needs a drag SESSION: the window server's drag loop */
		   at:(NSPoint)viewLocation
	       offset:(NSSize)initialOffset
		event:(nullable NSEvent *)event
	   pasteboard:(nullable NSPasteboard *)pboard
	       source:(nullable id)sourceObj
	    slideBack:(BOOL)slideFlag;

/* AND THE THREE THAT ANSWER RATHER THAN REFUSE.

 * `-gState` ANSWERS 0 FOR THE SAME REASON THE WINDOW'S DOES: Apple's door returns the receiver's graphics-state ID,
 * and this tier draws through a `CGContext` rather than a state stack, so there is no ID and 0 is the truth.

 * THE DRAG PAIR IS RECORDED, AND ON THE VIEW THAT IS CLOSER TO THE REAL CONTRACT THAN ON THE WINDOW: what consumes
 * a registered type is this view's own drag acceptance, so the set kept here is what a content view's registration
 * would be read back through. There is still no drag session, and the set is stated rather than made to look
 * effective. */
- (NSInteger)gState;
- (void)registerForDraggedTypes:(nullable NSArray *)newTypes;
- (void)unregisterDraggedTypes;
- (nullable NSArray *)cg_registeredDraggedTypes;
- (void)setBoundsOrigin:(NSPoint)newOrigin;
- (void)setBoundsSize:(NSSize)newSize;
- (NSSize)convertSize:(NSSize)aSize toView:(nullable NSView *)view;
- (NSSize)convertSize:(NSSize)aSize fromView:(nullable NSView *)view;

/* AND THE BASE-COORDINATE FAMILY, WHICH IS `toView:nil` UNDER A 10.0 NAME — deprecated, and therefore owed
 * (the 2026-09-26 policy), so they are declared and they forward to the door above rather than repeating its
 * arithmetic six times. */
- (NSPoint)convertPointToBase:(NSPoint)aPoint;
- (NSPoint)convertPointFromBase:(NSPoint)aPoint;
- (NSRect)convertRectToBase:(NSRect)aRect;
- (NSRect)convertRectFromBase:(NSRect)aRect;
- (NSSize)convertSizeToBase:(NSSize)aSize;
- (NSSize)convertSizeFromBase:(NSSize)aSize;

/* THE MOVE NOTIFICATIONS, WHICH ARE WHAT A VIEW USES TO FOLLOW ITS CONTEXT: a view that leaves a window lets
 * go of what it held, and one that arrives asks for what it needs. */
- (void)viewWillMoveToSuperview:(nullable NSView *)newSuperview;
- (void)viewDidMoveToSuperview;
- (void)viewWillMoveToWindow:(nullable NSWindow *)newWindow;
- (void)viewDidMoveToWindow;

/* AND THE ARRANGEMENT DOORS. `-resizeSubviewsWithOldSize:` is the hook a layout overrides, and
 * `-resizeWithOldSuperviewSize:` is what a SUPERVIEW calls on a child when IT changed size. */
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize;
- (void)resizeWithOldSuperviewSize:(NSSize)oldSize;
- (void)sortSubviewsUsingFunction:(NSInteger (*)(id, id, void *))compare context:(nullable void *)context;
- (void)removeFromSuperviewWithoutNeedingDisplay;

/* AND WHAT THE TREE TELLS A CLIENT. Three notifications and one window level, all of them names whose VALUES
 * are their own — the rule this tier follows wherever Apple publishes a symbol and not a string. */
extern NSString *NSViewFrameDidChangeNotification;

/* **AND THE FLAG THAT GATES IT.** `-setFrame:` and `-setFrameSize:` post a frame-changed notification, and whether
 * they do is this view's own choice. Apple's contract, which is the ground for every rule below:
 *
 *   * THE DEFAULT IS YES — a view posts a frame change unless it is told not to.
 *   * THE NOTIFICATION IS NOT POSTED WHEN THE FRAME IS SET TO THE VALUE IT ALREADY HAS: no net change, nothing to
 *     announce.
 *   * THE NOTIFICATION'S OBJECT IS THE VIEW whose frame changed.
 *   * AND IF THE FLAG WAS OFF WHEN THE FRAME CHANGED, TURNING IT BACK ON POSTS IMMEDIATELY — even though nothing has
 *     changed since. That is why the muted state is REMEMBERED rather than dropped.
 *
 * `NSViewGlobalFrameDidChangeNotification` IS DELIBERATELY LEFT UNANNOUNCED: its subject is the view's frame in
 * WINDOW coordinates, so it fires for every DESCENDANT of a view that moves as well as for the view itself, and that
 * walk is not one this tier does. It stays declared, and no row here pretends otherwise. */
- (BOOL)postsFrameChangedNotifications;
- (void)setPostsFrameChangedNotifications:(BOOL)flag;
extern NSString *NSViewBoundsDidChangeNotification;
extern NSString *NSViewGlobalFrameDidChangeNotification;
extern const CGFloat NSFullScreenModeWindowLevel;


- (void)drawRect:(NSRect)dirtyRect;


/* THE KEY-VIEW CHAIN. `-nextKeyView` is the view a Tab from THIS one goes to — a CHAIN rather than an array,
 * because a view may be linked into whatever order a caller wants, and a loop that ran off an array would have
 * to be rebuilt every time one link changed. The window computes a default loop; a caller overrides links in
 * it by setting this. THE LINK IS BORROWED, as `-superview` is. */
- (nullable NSView *)nextKeyView;
- (void)setNextKeyView:(nullable NSView *)aView;


/* ============================================================================================ *
 * THE CURSOR RECTS: WHAT THE POINTER LOOKS LIKE OVER A VIEW.                                     *
 *                                                                                                *
 * A VIEW DOES NOT SET THE CURSOR — IT DECLARES WHICH ONE IT WANTS OVER WHICH PART OF ITSELF,   *
 * IN `-resetCursorRects`, and the WINDOW resolves the winner as the pointer moves. That        *
 * indirection is what makes the answer a FUNCTION OF THE POINT rather than of the last event   *
 * that happened to arrive, and it is why the resolution can be checked without moving a mouse. *
 * ============================================================================================ */
- (void)addCursorRect:(NSRect)aRect cursor:(NSCursor *)aCursor;
- (void)removeCursorRect:(NSRect)aRect cursor:(NSCursor *)aCursor;
/* THE HOOK A VIEW OVERRIDES. Apple's default does nothing, and a view that wants a cursor over part of itself
 * calls `-addCursorRect:cursor:` from here — which is why this is a hook and not a setter. */
- (void)resetCursorRects;
- (void)discardCursorRects;


/* **THE VIEW'S THREE, WHICH THE LEDGER FLIPPED ON THE WINDOW'S DECLARATIONS** — Apple declares `-alphaValue`,
 * `-isOpaque` and `-inLiveResize` on NSView.h at 10.6, so they were always this class's rows.

 * ALL THREE ARE THE VIEW'S IN APPLE'S SURFACE AND ONLY ONE IS STORED. `-alphaValue` is RECORDED with its effect
 * named: the effect is how this view's drawing composites, which this tier's substrate has not got to.
 * `-isOpaque` is a GETTER with no setter in this header, and that is Apple's own shape — a view answers whether
 * what it DRAWS is opaque, a plain view draws nothing, and NO is what nothing is. `-inLiveResize` is COMPOSED
 * rather than stored: Apple's comment says it is "called from drawRect: to decide between cheap and full drawing",
 * so the view answers what its window says. */
- (void)setAlphaValue:(CGFloat)viewAlpha;
- (CGFloat)alphaValue;
- (BOOL)isOpaque;
- (BOOL)inLiveResize;
/* **AND THE VIEW'S OWN HALF OF THE LIVE-RESIZE QUESTION, WHOSE PROSE APPLE PUTS ON THE DECLARATION:** "A view that
 * returns YES for -preservesContentDuringLiveResize is responsible for invalidating its own dirty rects during live
 * resize". So YES is a PROMISE WITH WORK ATTACHED, which is why the base answers NO: a plain view takes on no such
 * responsibility, and there is no setter in Apple's 10.6 header to promise it with. */
- (BOOL)preservesContentDuringLiveResize;

@end

NS_ASSUME_NONNULL_END
