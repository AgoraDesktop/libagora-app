/* NSViewController.h — a controller for a view.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 *
 * **THE 10.6 SURFACE IS 13 MEMBERS AND THE OTHER 44 ROWS ARE POST-10.6, WHICH IS WHAT THE ARTEFACT SAYS.** The era
 * pins are 10.2/10.5/10.6, and everything this class is famous for — the child-controller containment API, the
 * `-viewDidLoad`/`-viewWillAppear:` lifecycle, `-presentViewController:`, the transition options — arrived in
 * 10.10. So this file declares what the era HAS, READ FROM APPLE'S PUBLIC HEADER, and the ledger strikes the rest
 * WITH THIS CLASS rather than leaving them as work this tier should have done.
 *
 * AND THE STRIKE IS DERIVED FROM THAT HEADER RATHER THAN FROM THE LEDGER'S ERA KEY. The key is unreliable for
 * PROPERTY rows — `NSScreen`'s `-frame` and `-visibleArea` were both marked "not era" while being 10.2 API — so a
 * strike derived from it would have struck the era's own members. The header is the artefact the pins are ABOUT.
 */
#ifndef APPKIT_NSVIEWCONTROLLER_H
#define APPKIT_NSVIEWCONTROLLER_H

#import <AppKit/NSResponder.h>
#import <Foundation/NSCoding.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSBundle;
@class NSView;

/* **WHAT THIS CLASS DOES WITH A NIB, AND WHY IT NOW LOADS ONE.** Apple's `-loadView` loads the nib named in the
 * initialiser with `NSNib` and takes the view from the file's owner's `view` outlet. That was refused here while
 * `NSNib` had no reader; the reader exists now (see `NSNib.h`), so `-loadView` instantiates the nib with SELF as the
 * owner — which is what makes the file's owner's `view` outlet land on this controller — and falls back to the first
 * `NSView` among the nib's top-level objects when the file does not wire an owner outlet. A nib that cannot be read is
 * an EXCEPTION rather than an empty view, because a controller showing nothing while claiming to have loaded is the
 * failure mode this class exists to make impossible. */
@interface NSViewController : NSResponder <NSSecureCoding>
{
	NSString *_nibName;
	NSBundle *_nibBundle;
	id _representedObject;	/* RETAINED, not copied — Apple's own contract for this property */
	NSString *_title;	/* COPIED — Apple's contract for this one, and the two differ ON PURPOSE */
	NSView *_view;		/* RETAINED */
}

/* THE DESIGNATED INITIALISER, and the two names it takes are the two it ANSWERS: `-nibName` and `-nibBundle`
 * return whatever was passed, which is the whole of Apple's default implementation. */
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
			 bundle:(nullable NSBundle *)nibBundleOrNil;

- (nullable NSString *)nibName;
- (nullable NSBundle *)nibBundle;

/* THE VIEW, AND `-view` IS THE DOOR THAT LOADS IT: Apple's implementation invokes `-loadView` when nothing has
 * been set, which is why a subclass overrides `-loadView` rather than `-view`. */
- (NSView *)view;
- (void)setView:(NSView *)view;
- (void)loadView;

/* THE OBJECT THE VIEW STANDS FOR, and the title the user sees. */
- (nullable id)representedObject;
- (void)setRepresentedObject:(nullable id)representedObject;
- (nullable NSString *)title;
- (void)setTitle:(nullable NSString *)title;

/* AND THE NSEditor INFORMAL PROTOCOL: a controller commits what its view is editing before the presentation ends.
 * `-commitEditing` answers YES because THERE ARE NO EDITORS TO FAIL — see the implementation for what a registered
 * editor would be and why there are none. */
- (BOOL)commitEditing;
- (void)discardEditing;
- (void)commitEditingWithDelegate:(nullable id)delegate
	       didCommitSelector:(nullable SEL)didCommitSelector
		     contextInfo:(nullable void *)contextInfo;
/* AND THE ONE DOOR `NSCoding` OWES THAT THIS HEADER NEVER SPELLED. The implementation has been here since the class
 * was written — `-initWithCoder:`, with the keys `-encodeWithCoder:` writes — and the LEDGER ROW still read open,
 * because A PROTOCOL CONFORMANCE IS NOT A DECLARATION: `<NSCoding>` says a class MAY answer this, and the
 * instrument reads headers, so the row was a door this tree had already built and would not admit to. Declared
 * now, so the round trip the probe already exercises is a contract rather than a coincidence. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSVIEWCONTROLLER_H */
