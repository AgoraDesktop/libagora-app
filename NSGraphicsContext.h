/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSGraphicsContext.h — the AppKit bridge: a CoreGraphics context as an object (C8.1).
 *
 * THIS IS THE SEAM, NOT THE WIDGETS. It wraps a `CGContextRef` so AppKit-shaped code can hold one,
 * ask whether its drawing is flipped, save and restore its state, and set the rendering options a
 * view's drawing inherits; everything it draws, it draws by asking for `CGContext` and calling this
 * tree's CoreGraphics. The drawing CLASSES (`NSBezierPath`, `NSColor`, `NSImage`, …) are
 * the AppKit plan's business (docs/design/appkit-plan.md), and are not here — coregraphics-plan.md §7's C8 bullet says so, and §3
 * row 1 marks where the CG layer ends.
 *
 * THE SURFACE BELOW IS PINNED, NOT RECALLED: `tools/appkit-sweep.py --refresh` read Apple's own
 * navigator tree into docs/reference/appkit-apple-surface.txt, every member here is a live row from
 * it, and every member Apple documents that is NOT here is named below with its reason.
 *
 * WHAT IS NOT HERE, AND WHY — three kinds of reason, not one:
 *
 *   DEPRECATED, so out by §1's fourth and fifth decisions: `graphicsPort`,
 *   `+graphicsContextWithGraphicsPort:flipped:`, `+setGraphicsState:` and
 *   `+graphicsContextWithWindow:`. THIS IS THE FIRST THING THE PIN CHANGED: §7's C8 bullet named
 *   `-graphicsPort` as C8's seam, and it is the one member Apple deprecates — measured, not argued.
 *
 *   NO SUBSTRATE IN THIS TREE: `CIContext` (no Core Image here), and
 *   `+graphicsContextWithBitmapImageRep:` (needs `NSBitmapImageRep` — §3 row 1's class).
 *
 *   AND ONE THAT IS REAL COREGRAPHICS WORK, WITH ITS REASON MEASURED RATHER THAN ASSUMED:
 *   `colorRenderingIntent` needs `CGContextSetRenderingIntent`, which **Apple HAS** (an `open` row
 *   here), and what keeps it deferred is not the missing function but that nothing would CONSUME it -
 *   an intent names how a colour is converted DURING drawing, and this library's drawing does not
 *   convert (fills composite device numbers, images composite their own bytes).
 *
 *   AND THE GAP THAT WAS REAL IS CLOSED. `imageInterpolation` needed
 *   `CGContextSetInterpolationQuality`, `CGContextGetInterpolationQuality` and
 *   `CGInterpolationQuality` - **all three of which Apple has and this tree did not** - AND a sampler
 *   that honours them, because the image blit was nearest-only. That CoreGraphics slice landed
 *   (`17343a35`): a bilinear sampler that premultiplies each texel before weighting, with
 *   `kCGInterpolationLow` and `kCGInterpolationHigh` refused by name because this library has two
 *   filters and not four. **AND THIS IS THE ONE OPTION THAT READS THROUGH TO THE CONTEXT INSTEAD OF
 *   BEING STORED** - see its declaration below. The asymmetry is not an oversight: CoreGraphics has a
 *   getter for THIS one, which is exactly what made it a gap, and it is the same measurement that
 *   made the other three stored options the correct arrangement.
 *
 *     * `imageInterpolation` needs `CGContextSetInterpolationQuality` AND
 *       `CGContextGetInterpolationQuality`, and **Apple HAS both** (both are `open` rows in this
 *       tree's CoreGraphics ledger). So this one IS a genuine gap on OUR side — our `CGContext.h`
 *       has neither — and closing it means the two functions, the `CGInterpolationQuality` enum,
 *       **and bilinear sampling in the image blit**, which is nearest-only today (C5's probe says
 *       so). A setter whose value no drawing reads is a silent no-op, so this is a CoreGraphics
 *       slice rather than a one-line unblock.
 *     * `colorRenderingIntent` needs `CGContextSetRenderingIntent`, which **Apple also HAS** (an
 *       `open` row here). What keeps it deferred is not the missing function but that nothing would
 *       CONSUME it: an intent names how a colour is converted DURING drawing, and this library's
 *       drawing does not convert — fills composite device numbers and images composite their own
 *       bytes.
 *
 *   A CORRECTION, KEPT RATHER THAN QUIETLY DELETED, because it was the kind of mistake that looks
 *   like rigour. The first version of this header deferred FIVE members — the two above plus
 *   `compositingOperation`, `shouldAntialias` and `patternPhase` — reasoning that "an AppKit
 *   property needs both halves" and that `CGContextGetShouldAntialias`,
 *   `CGContextGetPatternPhase` and `CGContextGetBlendMode` do not exist. **Asked of Apple's index
 *   instead of of memory, those three getters do not exist in APPLE EITHER** — the ledger's only
 *   context getter in that family is `CGContextGetInterpolationQuality`. So Apple's own
 *   `NSGraphicsContext` cannot be reading them back from the context: **it stores them, and its
 *   setter applies them**. Storing is not an approximation here, it is the arrangement — and the
 *   objection that "a stored copy would disagree with the context the moment anyone drew through CG
 *   directly" describes Apple's behaviour too. Those three are therefore SHIPPED, below.
 *
 *   AND ONE THAT IS A FOLLOW-ON RATHER THAN A GAP: `attributes` and
 *   `+graphicsContextWithAttributes:` need the attribute KEYS, which the ledger pins
 *   (`NSGraphicsContextDestinationAttributeName`, `NSGraphicsContextPDFFormat`,
 *   `NSGraphicsContextPSFormat`,
 *   `NSGraphicsContextRepresentationFormatAttributeName`) but whose VALUES are format names and a
 *   dictionary this slice does not build.
 *
 * THE CONTEXT IS NOT RETAINED, which is Apple's arrangement: the graphics context belongs to
 * whoever made it, and this object only points at it, so a caller keeps their own reference alive
 * for as long as they draw. Said out loud because the alternative is a silent over-release on one
 * side or a leak on the other.
 */
#ifndef APPKIT_NSGRAPHICSCONTEXT_H
#define APPKIT_NSGRAPHICSCONTEXT_H

#import <CoreGraphics/CGColor.h>
#import <CoreGraphics/CGContext.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>



NS_ASSUME_NONNULL_BEGIN

/* AND THE TWO ENUMERATIONS APPLE FILES HERE THAT ARE WINDOW-SHAPED: how a window is backed, and where in
 * the stack an ordering call puts it. Both sets of numbers are the era header's own. */
enum {
	NSBackingStoreRetained = 0,
	NSBackingStoreNonretained,
	NSBackingStoreBuffered
};
typedef NSUInteger NSBackingStoreType;

enum {
	NSWindowAbove = 1,
	NSWindowBelow = -1,
	NSWindowOut = 0
};
typedef NSInteger NSWindowOrderingMode;



/* ============================================================================================ *
 * THE ERA'S REMAINING DOORS (the types and names; the methods are inside the interface below).   *
 * ============================================================================================ */

/* THE COLOUR RENDERING INTENT, AND THE ERA HEADER SAYS EXACTLY WHAT ITS VALUES ARE: "values
 * interchangeable with CGColorRenderingIntent values". They ARE this tree's CoreGraphics values — the same
 * five names in the same order — so the cases alias them rather than repeating the numbers.
 *
 * **AND THE TYPE IS AN ANONYMOUS `enum` PLUS `typedef NSInteger`, WHICH IS APPLE'S OWN SHAPE AND NOT A
 * CHOICE.** That is what makes the interchangeability true: `NSColorRenderingIntent` is an integer, so a
 * caller may compare it against a `CGColorRenderingIntent` without a cast. Writing it as a NAMED enum
 * instead — which is what this file did first — makes the same comparison a `-Wenum-compare` warning, and
 * the probe is what measured it. */
enum {
	NSColorRenderingIntentDefault = kCGRenderingIntentDefault,
	NSColorRenderingIntentAbsoluteColorimetric = kCGRenderingIntentAbsoluteColorimetric,
	NSColorRenderingIntentRelativeColorimetric = kCGRenderingIntentRelativeColorimetric,
	NSColorRenderingIntentPerceptual = kCGRenderingIntentPerceptual,
	NSColorRenderingIntentSaturation = kCGRenderingIntentSaturation
};
typedef NSInteger NSColorRenderingIntent;

/* THE FOUR NAMES A CONTEXT IS ASKED FOR BY. The two ATTRIBUTE names are keys in the dictionary
 * `+graphicsContextWithAttributes:` takes; the two FORMAT names are values for the second of them, and the
 * era's own comment says what they mean: "Specifies destination file format". Their VALUES ARE THEIR NAMES,
 * the rule this tier follows where Apple publishes a symbol and not a string. */
extern NSString *NSGraphicsContextDestinationAttributeName;
extern NSString *NSGraphicsContextRepresentationFormatAttributeName;
extern NSString *NSGraphicsContextPSFormat;
extern NSString *NSGraphicsContextPDFFormat;

/*
 * AND THE COLOUR-SPACE NAMES AND THE COMPONENT COUNTER, WHICH APPLE FILES IN `NSGraphics.h` TOO — the same
 * stand-in rule the bitmap function above states. The two DEVICE names a representation's designated
 * initialiser takes (`NSDeviceRGBColorSpace`, `NSDeviceGrayColorSpace`) live in NSImageRep.h instead,
 * because that class's own door is where a reader meets them; these seven are the rest of the family, and
 * `NSNumberOfColorComponents` is the table over all of them.
 *
 * THE COUNTS ARE APPLE'S OWN, read out of the era header's descriptive block rather than guessed —
 * "NSDeviceCMYKColorSpace Cyan, magenta, yellow, black, and alpha components", and so on for the rest.
 * THREE OF THE SEVEN HAVE NO SPACE BEHIND THEM HERE and say so in their own comment: a catalog list, a
 * tiled pattern and a custom gstate. Their NAMES are real API even so, which is why they are declared.
 */
extern NSString *NSCalibratedRGBColorSpace;
extern NSString *NSCalibratedWhiteColorSpace;
extern NSString *NSDeviceCMYKColorSpace;
extern NSString *NSDeviceWhiteColorSpace;
extern NSString *NSCustomColorSpace;   /* a custom gstate in an image — no space behind it here */
extern NSString *NSNamedColorSpace;    /* a catalog list — no space behind it here */
extern NSString *NSPatternColorSpace;  /* a tiled pattern — no space behind it here */

/* HOW MANY COMPONENTS A NAMED SPACE HAS, alpha included. An unknown name answers 0, which is the honest
 * "no such space" rather than a plausible-looking count. */
/* NULLABLE BECAUSE THE IMPLEMENTATION ACCEPTS IT: a nil name answers 0, which is the honest "no such
 * space" and the same answer an unknown name gets. Apple's parameter is non-null; this one is
 * annotated from what the code does, which is the rule this tree follows for every such gap. */
NSInteger NSNumberOfColorComponents(NSString * _Nullable colorSpaceName);


/* FORWARDED: NSDrawBitmap below takes one as a colour-space NAME, which is Apple's own spelling of the
 * parameter (a string, not a CGColorSpaceRef). */
@class NSBitmapImageRep;
@class NSDictionary;
@class NSString;

/*
 * THE COMPOSITING OPERATION IS 28 LIVE NAMES HERE, WHERE APPLE'S INDEX LISTS 30 PLUS 30 LEGACY
 * ALIASES. Apple files it under `NSGraphicsContext`, which is why it is declared in this header
 * rather than one of its own. EVERY CASE MAPS ONE-TO-ONE ONTO `CGBlendMode` —
 * `NSCompositingOperationSourceOver` IS `kCGBlendModeNormal`, the names track each other all the way
 * down, and `NSCompositingOperationPlusDarker` maps onto `kCGBlendModePlusDarker`, which CoreGraphics
 * composites BY HAND because pixman has no such operator (coregraphics-plan §44). So the setter
 * forwards every declared case and refuses nothing; its refusal arm survives only for a value that is
 * neither a live case nor a struck one.
 *
 * `NSCompositingOperationHighlight` IS NOT HERE, and neither is any of the fifteen legacy spellings
 * the LEDGER CALLS AFTER-10.6 (`NSCompositeMultiply`, `NSCompositeDarken`, … — the modern blenders
 * did not exist at the pins, so those really are post-10.6 rows and are struck).
 *
 * **THE THIRTEEN OTHER LEGACY SPELLINGS ARE A DIFFERENT CASE, AND THIS COMMENT USED TO GET IT WRONG.**
 * It said the ledger has "them all" as struck rows "which is the same policy that keeps `graphicsPort`
 * out". MEASURED (2026-10-07): the ledger splits the family in two, and the thirteen names the 10.2/10.5/
 * 10.6 headers actually declare — `NSCompositeClear`, `Copy`, `SourceOver`, `SourceIn`, `SourceOut`,
 * `SourceAtop`, `DestinationOver`, `DestinationIn`, `DestinationOut`, `DestinationAtop`, `XOR`,
 * `PlusDarker`, `PlusLighter` — are **OPEN** rows carrying `deprecated`, not struck ones. The
 * 2026-09-26 policy un-deprecates exactly this kind of row: they are owed for a ported 10.2 caller, so
 * they are declared below as CONSTANTS and the comparison the policy is about stays honest.
 *
 * `NSCompositeHighlight` IS THE ONE THAT CANNOT BE AN ALIAS, and the reason is a measured COLLISION
 * rather than a preference. The era enumerates it at 12 with `PlusLighter` at 13; Apple later dropped
 * Highlight and moved `PlusLighter` DOWN to 12. So 12 means `PlusLighter` here, and a legacy
 * `NSCompositeHighlight` declared with its era value would silently request the wrong blend — a
 * silent wrongness, which is the one thing this tree refuses to ship. It is therefore NOT declared,
 * and its ledger row stays open rather than being struck: it is era API we have not shipped.
 */
typedef enum {
	NSCompositingOperationClear = 0,
	NSCompositingOperationCopy,
	NSCompositingOperationSourceOver,
	NSCompositingOperationSourceIn,
	NSCompositingOperationSourceOut,
	NSCompositingOperationSourceAtop,
	NSCompositingOperationDestinationOver,
	NSCompositingOperationDestinationIn,
	NSCompositingOperationDestinationOut,
	NSCompositingOperationDestinationAtop,
	NSCompositingOperationXOR,
	NSCompositingOperationPlusDarker,
	NSCompositingOperationPlusLighter,
	NSCompositingOperationMultiply,
	NSCompositingOperationScreen,
	NSCompositingOperationOverlay,
	NSCompositingOperationDarken,
	NSCompositingOperationLighten,
	NSCompositingOperationColorDodge,
	NSCompositingOperationColorBurn,
	NSCompositingOperationSoftLight,
	NSCompositingOperationHardLight,
	NSCompositingOperationDifference,
	NSCompositingOperationExclusion,
	NSCompositingOperationHue,
	NSCompositingOperationSaturation,
	NSCompositingOperationColor,
	NSCompositingOperationLuminosity
} NSCompositingOperation;

/*
 * AND THE THIRTEEN LEGACY SPELLINGS, WHICH THE ERA HEADERS DECLARE AND THE LEDGER OWES. They are
 * `const` VARIABLES rather than extra enumerators, and that is the ledger's own shape: Apple indexes
 * them as `var` rows, not as `case` rows of the enum. Every one of them carries its LIVE case's value,
 * so a ported 10.2 caller's `NSCompositeCopy` and a modern caller's `NSCompositingOperationCopy` are
 * the same number and reach the same operator — which is the whole point of shipping them.
 *
 * THEY ARE `extern` AND NOT `static const` FOR THE USUAL REASON HERE: this tree's rule is that
 * everything declared is defined, and a `static const` in a header is a definition per translation
 * unit with no single home. The definitions are in NSGraphicsContext.m next to the operator switch.
 */
extern const NSCompositingOperation NSCompositeClear;
extern const NSCompositingOperation NSCompositeCopy;
extern const NSCompositingOperation NSCompositeSourceOver;
extern const NSCompositingOperation NSCompositeSourceIn;
extern const NSCompositingOperation NSCompositeSourceOut;
extern const NSCompositingOperation NSCompositeSourceAtop;
extern const NSCompositingOperation NSCompositeDestinationOver;
extern const NSCompositingOperation NSCompositeDestinationIn;
extern const NSCompositingOperation NSCompositeDestinationOut;
extern const NSCompositingOperation NSCompositeDestinationAtop;
extern const NSCompositingOperation NSCompositeXOR;
extern const NSCompositingOperation NSCompositePlusDarker;
extern const NSCompositingOperation NSCompositePlusLighter;

/*
 * NSDrawBitmap IS THE ERA'S ONE C DRAWING CALL, AND IT LIVES HERE BECAUSE APPLE FILES IT IN `NSGraphics.h`
 * AND THIS HEADER IS THAT FILE'S STAND-IN — the same reason the compositing operation above is declared
 * here rather than in a header of its own. Its parameters are the whole of a pixel layout: dimensions, a
 * bit depth, a channel count, a stride, whether the samples are planar, whether there is alpha, a colour
 * space name, and UP TO FIVE PLANES.
 *
 * THE IMPLEMENTATION BORROWS AND DRAWS, which is the honest shape rather than a second rasteriser: the
 * caller's plane 0 is ADOPTED by an `NSBitmapImageRep` (adopted, not copied — the buffer must outlive the
 * call, which is what a caller passing a live plane already means), the rep draws into the current
 * context, and the rep is released without freeing what it borrowed. Planar data and a missing plane are
 * refused BY NAME, because this tree's rep holds one plane — see NSBitmapImageRep.h.
 */
void NSDrawBitmap(NSRect rect, NSInteger width, NSInteger height, NSInteger bps, NSInteger spp,
                  NSInteger bpp, NSInteger bpr, BOOL isPlanar, BOOL hasAlpha,
                  NSString *colorSpaceName, const unsigned char *const _Nullable data[_Nonnull 5]);

/*
 * HOW AN IMAGE IS SAMPLED WHEN IT IS SCALED - a one-to-one mapping onto `CGInterpolationQuality`, so
 * the two levels this library cannot honour (`Low` and `High`) inherit THAT enum's refusals rather
 * than getting new ones: the property below forwards to CoreGraphics, which refuses them. All five
 * names are declared, because a caller's `switch` needs them and the refusal is the setter's job.
 */
typedef enum {
	NSImageInterpolationDefault = 0,
	NSImageInterpolationNone,
	NSImageInterpolationLow,
	NSImageInterpolationMedium,
	NSImageInterpolationHigh
} NSImageInterpolation;

@interface NSGraphicsContext : NSObject
{
	CGContextRef _context;      /* NOT owned — see the header note */
	BOOL _flipped;
	BOOL _drawingToScreen;
	/* THE THREE STORED OPTIONS, and storing them is APPLE'S ARRANGEMENT rather than a shortcut:
	 * CoreGraphics exposes no getter for any of the three (measured — see the correction above), so
	 * there is nothing to read back and the object must remember what it was asked for. The SETTERS
	 * are what reach the context. */
	BOOL _shouldAntialias;
	NSPoint _patternPhase;
	NSCompositingOperation _compositingOperation;
	/* AND THE TWO THE REMAINING ROWS NEED. The attributes are what the CREATING DOOR was handed — Apple's
	 * own contract for `-attributes` is "attributes used to create this instance" — so they are retained
	 * here, and a context invented from a raw `CGContextRef` answers nil, which is the truth for a context
	 * that had no dictionary. */
	NSDictionary *_attributes;	/* RETAINED */
	/* AND THE RENDERING INTENT IS STORED FOR THE SAME REASON THE THREE ABOVE ARE, WITH ONE DIFFERENCE ITS
	 * SETTER STATES: CoreGraphics has no getter for it either, so the object remembers it — but this
	 * library's drawing does not CONVERT colours, so the setter cannot apply it to the context and names
	 * what is missing instead of pretending. */
	NSColorRenderingIntent _colorRenderingIntent;
}

/* THE DOOR, and the only way to get one of these. Apple spells it
 * `+graphicsContextWithCGContext:flipped:` in Objective-C and `init(cgContext:flipped:)` in Swift;
 * the ledger holds the Objective-C spelling, and so does this header. */
+ (nullable NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)cgContext
                                                    flipped:(BOOL)initialFlippedState;

/* THE ONE FACTORY THIS TREE CAN HONOUR, and it is Apple's own convenience form of the attributes door: a
 * context that draws into a representation's PIXELS. `isPlanar:NO` only, which Apple's own comment states. */
+ (nullable NSGraphicsContext *)graphicsContextWithBitmapImageRep:(nullable NSBitmapImageRep *)bitmapRep;

/* AND THE GENERAL FACTORY. Its destination may be a window, a mutable data, a representation or a URL, and
 * THIS TREE HAS ONE OF THE FOUR: the representation is honoured and the other three are refused BY NAME —
 * a data or a URL destination means the POSTSCRIPT or PDF output formats, and there is no encoder here to
 * produce either. */
+ (nullable NSGraphicsContext *)graphicsContextWithAttributes:(nullable NSDictionary *)attributes;

/* ============================================================================================ *
 * THE REMAINING ROWS, AND ONE OF THEM CORRECTS A GROUND THAT WENT STALE.                         *
 * ============================================================================================ */

/* THE WINDOW DOOR, SHIPPED RATHER THAN REFUSED FOR BEING DEPRECATED. The note at the top of this file once
 * listed it under "DEPRECATED, so out by §1's fourth and fifth decisions", AND THAT GROUND NO LONGER EXISTS:
 * the deprecation policy was retired on 2026-09-26, so an Apple-deprecated row is OWED rather than struck,
 * and `tools/appkit-sweep.py` judges it by its declaration like any other. `-graphicsPort` and
 * `+graphicsContextWithGraphicsPort:flipped:` were shipped under the same corrected reading; this is the last
 * of that group.
 *
 * AND IT IS APPLE'S OWN COVER METHOD, taken literally: Apple's header defines it as
 * `+graphicsContextWithAttributes:` with `NSGraphicsContextDestinationAttributeName` → the window, so this
 * forwards to that door rather than inventing a second path. A WINDOW destination is one of the three that
 * door refuses by name, because a window's drawing is the display seam — reached through `AGWindowServer` in
 * this tier, not through a `CGContextRef` this class can hand out.
 *
 * THE PARAMETER IS SPELLED `id` AND THAT IS NOT THE OVER-CREDITING RULE: NSWindow IS a class this tier
 * ships. The reason is a header cycle — NSWindow.h imports THIS file, so a `@class NSWindow;` here would have
 * the two referring to each other for no gain — and the door needs nothing from the object but to pass it on. */
+ (nullable NSGraphicsContext *)graphicsContextWithWindow:(nullable id)window;

/* THE ATTRIBUTES THE CONTEXT WAS CREATED WITH — Apple's own words for the door — so they are STORED by the
 * door that takes a dictionary, and nil for a context made from a raw port. */
@property (nullable, readonly) NSDictionary *attributes;

/* AND THE PLATFORM PORT, WHICH IS THIS CLASS'S OLDEST NAME FOR THE SAME POINTER `-CGContext` ANSWERS. Apple
 * deprecated the spelling at 10.0 (the name says Core Graphics now) and it is owed here for the same reason
 * `+graphicsContextWithGraphicsPort:flipped:` is: a ported 10.0 caller spells it. THE TWO CANNOT DRIFT —
 * this is one accessor read two ways, not a second field. */
@property (nullable, readonly) void *graphicsPort;

/* AND THE RENDERING INTENT. Stored, like the three options above, because CoreGraphics exposes no getter for
 * it either — AND NAMED AS UNCONSUMED AT ITS SETTER, because unlike those three this library cannot apply
 * it: an intent names how a colour is converted DURING drawing, and the drawing here converts nothing (fills
 * composite device numbers, images composite their own bytes). */
@property (readonly) NSColorRenderingIntent colorRenderingIntent;
- (void)setColorRenderingIntent:(NSColorRenderingIntent)renderingIntent;

/* AND THE ONE WITH NO SUBSTRATE AT ALL: Core Image is not in this tree, so there is no CIContext to hand
 * back and the door answers nil with a refusal that says so. THE SPELLING IS `id` FOR THE OVER-CREDITING
 * RULE THIS TIME — writing `CIContext *` would need a forward declaration of a class this tier has not got,
 * and the ledger counts a forward declaration as declaring the class. */
@property (nullable, readonly) id CIContext;

/* THE DEPRECATED PORT DOOR, whose parameter the era header declares as `void *` ("usually CGContextRef").
 * It forwards to `+graphicsContextWithCGContext:flipped:` above, so the two spellings cannot drift. */
+ (nullable NSGraphicsContext *)graphicsContextWithGraphicsPort:(nullable void *)graphicsPort
						       flipped:(BOOL)initialFlippedState;

/* AND THREE THAT REFUSE BY NAME. `+setGraphicsState:` makes a context current from a GraphicsState that
 * Apple's own machinery hands out, and the focus stack is the pair the FOCUS RING is drawn with; neither a
 * gState id nor a focus ring exists in this tree, so there is nothing for these to name. */
+ (void)setGraphicsState:(NSInteger)gState;
- (nullable id)focusStack;
- (void)setFocusStack:(nullable id)stack;


/* THE CG CONTEXT, and the whole point of the object. NULL for an object that was never given one
 * (see the implementation's `-init` note). */
@property (nullable, readonly) CGContextRef CGContext;

/* THE CURRENT CONTEXT IS PER-THREAD, which is Apple's contract ("the current graphics context of
 * the current thread") and not a simplification: a current context is a property of the drawing
 * thread, and one global would let two threads' draws collide. `+setCurrentContext:` REPLACES it
 * rather than pushing — the stack is the save/restore pair below. */
+ (nullable NSGraphicsContext *)currentContext;
+ (void)setCurrentContext:(nullable NSGraphicsContext *)context;

/* THE COORDINATE SYSTEM, and the reason a caller asks: this library's bitmap contexts have y
 * increasing UPWARD while a view's own space usually does not, so the flip is carried here rather
 * than inferred later. */
@property (readonly, getter=isFlipped) BOOL flipped;

/* WHETHER THE DESTINATION IS THE SCREEN — and for every context THIS LIBRARY CAN MAKE it is NO,
 * because its CoreGraphics contexts are all bitmaps and there is no window- or screen-backed
 * `CGContextRef` here at all (the display is the seam's, a separate path). Answering NO is therefore a
 * fact about our contexts rather than a guess about someone else's. */
@property (readonly, getter=isDrawingToScreen) BOOL drawingToScreen;
+ (BOOL)currentContextDrawingToScreen;

/* THE SAVE/RESTORE PAIR IN BOTH SPELLINGS, AND THEY ARE NOT THE SAME OPERATION.
 *
 *   -saveGraphicsState / -restoreGraphicsState act on the RECEIVER: the instance pair is
 *   `CGContextSaveGState`/`CGContextRestoreGState` on its own context — the C2 state stack (CTM,
 *   clip, colours, line state) that already existed.
 *
 *   +saveGraphicsState / +restoreGraphicsState act on the CURRENT CONTEXT *and* on a per-thread
 *   stack OF CONTEXTS: save pushes the current one and sends it a save; restore pops, makes the
 *   popped one current, and sends it a restore. Apple's own abstracts say exactly that ("Pops a
 *   graphics context from the per-thread stack, makes it current, and sends the context a restore
 *   graphics state message"), and the difference is observable: a caller who sets a current
 *   context, saves, sets another and restores gets the FIRST one back, which the instance pair
 *   cannot do.
 *
 * The stack is BOUNDED, and an overflow is REFUSED with a message rather than silently
 * overwriting — the rule the graphics state's dash array already follows. */
- (void)saveGraphicsState;
- (void)restoreGraphicsState;
+ (void)saveGraphicsState;
+ (void)restoreGraphicsState;

/* "Make sure the drawing has arrived." For a bitmap context it already has when this returns, so
 * this forwards to `CGContextFlush` and inherits its honest no-op-ness (CGContext.h says why).
 * It exists because a caller writing code against a window-backed context will call it. */
- (void)flushGraphics;

/*
 * THE RENDERING OPTIONS. Each SETTER reaches the context — `CGContextSetShouldAntialias`,
 * `CGContextSetPatternPhase` (which takes a SIZE, so the point is converted) and
 * `CGContextSetBlendMode` — and each GETTER answers from what this object stored. THE DEFAULTS ARE
 * THE CONTEXT'S: antialiasing on, phase (0, 0), and `SourceOver`, which is `kCGBlendModeNormal`.
 */
@property BOOL shouldAntialias;
/* THE OFFSET APPLIED TO A PATTERN, in the user space of whatever draws next. A POINT here and a
 * SIZE at the CoreGraphics call, which is Apple's own asymmetry and not a slip. */
@property NSPoint patternPhase;
/* EVERY DECLARED `NSCompositingOperation` IS FORWARDED, `PlusDarker` included — see the enum. An
 * operation that is neither a live case nor a struck one is refused by name rather than approximated. */
@property NSCompositingOperation compositingOperation;

/*
 * AND THIS ONE IS NOT STORED, WHICH IS ITS WHOLE DIFFERENCE FROM THE THREE ABOVE. They remember what
 * they were asked for because CoreGraphics has no getter for any of them; THIS one has both halves on
 * the CoreGraphics side, so it READS THROUGH: `-imageInterpolation` asks the context, and a refused
 * `Low` or `High` therefore reports the quality ACTUALLY IN FORCE rather than the one that was asked
 * for and rejected. A stored copy here would be the disagreement the other three cannot avoid and
 * this one has no reason to accept.
 *
 * AND THE TWO ENUMS' ORDERS ARE NOT THE SAME — `NSImageInterpolationDefault` is 0 here while
 * `kCGInterpolationNone` is 0 there, because the CoreGraphics ordering is this tree's own decision
 * (`None` first, so a zeroed context means nearest). A CAST BETWEEN THEM WOULD THEREFORE SWAP
 * `Default` AND `None` SILENTLY, which is why the mapping below is an explicit switch.
 */
@property NSImageInterpolation imageInterpolation;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSGRAPHICSCONTEXT_H */
