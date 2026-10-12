/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSResponder.h — the responder chain, and the class NSView should always have inherited from (stage A).
 *
 * THIS IS THE BASE THE VIEW LAYER IS WRITTEN AGAINST, and it is why stage A is the responder and the event
 * rather than a widget: every mouse, key and tablet method below takes the `NSEvent` the previous unit
 * shipped, and every one of them has the same default behaviour — FORWARD TO THE NEXT RESPONDER. That
 * single rule is what makes a chain a chain, and it is the thing the probe drives.
 *
 * THE DEFAULTS ARE APPLE'S, AND EACH ONE IS A DECISION RATHER THAN AN OMISSION:
 *
 *   `-tryToPerform:with:` WALKS. It answers YES if the receiver responds to the selector — invoking it —
 *   and otherwise asks the next responder, and only answers NO at the end of the chain. This is the one
 *   member here that does real work, and it is the reason `-noResponderFor:` exists to be called.
 *
 *   THE EVENT METHODS DO NOTHING BUT FORWARD. Apple's default for `-mouseDown:` and its two dozen siblings
 *   is `[[self nextResponder] mouseDown:theEvent]`, and that is what this is: a class that handled them
 *   itself would be a class no view could override selectively.
 *
 *   AND `-acceptsFirstResponder` IS NO WHILE `-becomeFirstResponder`/`-resignFirstResponder` ARE YES. That
 *   asymmetry is Apple's and it is deliberate: becoming the first responder is something a responder
 *   performs successfully unless it says otherwise, while ACCEPTING the role is opt-in.
 *
 * THE REST OF THE ERA'S SURFACE IS HERE NOW, AND EACH DOOR SAYS WHICH KIND IT IS — which is the distinction
 * that matters in a tier with no window server of its own:
 *
 *   `-undoManager` WALKS THE CHAIN and answers Foundation's NSUndoManager, which this tree HAS. A window's
 *   own answer is the delegate's (`-windowWillReturnUndoManager:`, which NSWindow declares), so the walk is
 *   the whole implementation and nil at the end of the chain is the truth rather than a refusal.
 *
 *   `-willPresentError:` IS REAL AND IS A HOOK: Apple's default returns the error UNCHANGED, and a subclass
 *   that wants a less generic message overrides it — the documented extension point, and the only part of
 *   error presentation that needs nothing this tier has not got. `-presentError:` runs that hook and
 *   forwards; where the chain ends, IT REFUSES BY NAME, because presenting needs NSAlert.
 *
 *   THE INTERFACE STYLE IS STORED, WITH THE WALK AND THE TWO GLOBALS: Apple keeps this family in its own
 *   header (NSInterfaceStyle.h) and hangs it on this class through a category; the declarations live HERE
 *   because every one of the ledger's rows for it is this class's or unowned. WHAT IS OURS IS THE ANSWER:
 *   the style is a user preference, and this tier has no preferences domain for one, so an unset style
 *   walks the chain and the chain's end is `NSNoInterfaceStyle` — which the artefact's own comment defines
 *   as the DEFAULT value, not as a failure. `NSInterfaceStyleForKey` therefore answers the responder it is
 *   given rather than a table this tier cannot read, and says so.
 *
 *   `-interpretKeyEvents:` IS REFUSED BY NAME. Apple hands each event to the receiver's INPUT CONTEXT, and
 *   the answers come back as `-insertText:` and `-doCommandBySelector:`; there is no input method in this
 *   tier, and the key-binding commands themselves are stage J's informal protocol. A door that quietly did
 *   nothing would swallow keystrokes, so it says what is missing instead.
 *
 * AND TWO DECLARATIONS ARE SPELLED `id` FOR A REASON THAT HAS NOTHING TO DO WITH THIS CLASS: `-menu` and
 * `-setMenu:` hold an `NSMenu`, which is a class this tier does not ship — naming it, even forward, would
 * make the ledger credit NSMenu's own class row, the over-crediting family recorded in §58 and again in
 * NSEvent.h. A responder that HOLDS a menu needs no more than `id`; configuring one will need the class, and
 * that is stage D's work.
 */
#ifndef APPKIT_NSRESPONDER_H
#define APPKIT_NSRESPONDER_H

#import <Foundation/Foundation.h>
#import <AppKit/NSEvent.h>

@class NSWindow;

NS_ASSUME_NONNULL_BEGIN

/* THE INTERFACE STYLE, whose values are the artefact's (NSInterfaceStyle.h) and whose type is an NSUInteger
 * behind a typedef — 10.0-era API that Apple deprecated later, which by this tree's policy makes it OWED
 * rather than struck. */
enum {
	NSNoInterfaceStyle = 0,		/* the DEFAULT value, per the artefact's own comment */
	NSNextStepInterfaceStyle = 1,
	NSWindows95InterfaceStyle = 2,
	NSMacintoshInterfaceStyle = 3
};
typedef NSUInteger NSInterfaceStyle;

@interface NSResponder : NSObject
{
	/* NOT RETAINED, and it cannot be: a chain whose links retained each other would be a cycle, and a view
	 * hierarchy would leak its root. Apple's is not retained either. */
	NSResponder *_nextResponder;
	/* AND THE TWO PIECES OF STATE THIS CLASS OWNS. `NSNoInterfaceStyle` is "unset", which is what lets
	 * `-interfaceStyle` walk: a responder answers its OWN style only when it has one. */
	NSInterfaceStyle _interfaceStyle;
	id _menu;			/* RETAINED (an NSMenu, a class this tier does not ship) */
}

- (nullable NSResponder *)nextResponder;
- (void)setNextResponder:(nullable NSResponder *)aResponder;

/* THE CHAIN'S ONE REAL BEHAVIOUR, and the probe's centre: YES when this receiver performs the action. */
- (BOOL)tryToPerform:(nullable SEL)anAction with:(nullable id)anObject;

/* AND THE HOOK APPLE CALLS WHEN NOTHING DID. Its default does nothing; NSWindow's is the one that beeps. */
- (void)noResponderFor:(SEL)eventSelector;

/* THE EVENT METHODS. Every one of them forwards; none of them draws, moves or decides anything. */
- (void)mouseDown:(NSEvent *)theEvent;
- (void)mouseUp:(NSEvent *)theEvent;
- (void)mouseDragged:(NSEvent *)theEvent;
- (void)mouseMoved:(NSEvent *)theEvent;
- (void)mouseEntered:(NSEvent *)theEvent;
- (void)mouseExited:(NSEvent *)theEvent;
- (void)rightMouseDown:(NSEvent *)theEvent;
- (void)rightMouseUp:(NSEvent *)theEvent;
- (void)rightMouseDragged:(NSEvent *)theEvent;
- (void)otherMouseDown:(NSEvent *)theEvent;
- (void)otherMouseUp:(NSEvent *)theEvent;
- (void)otherMouseDragged:(NSEvent *)theEvent;
- (void)scrollWheel:(NSEvent *)theEvent;
- (void)keyDown:(NSEvent *)theEvent;
- (void)keyUp:(NSEvent *)theEvent;
- (void)flagsChanged:(NSEvent *)theEvent;
- (void)tabletPoint:(NSEvent *)theEvent;
- (void)tabletProximity:(NSEvent *)theEvent;
- (void)cursorUpdate:(NSEvent *)event;
- (void)magnifyWithEvent:(NSEvent *)event;
- (void)rotateWithEvent:(NSEvent *)event;
- (void)swipeWithEvent:(NSEvent *)event;
- (void)beginGestureWithEvent:(NSEvent *)event;
- (void)endGestureWithEvent:(NSEvent *)event;
- (void)touchesBeganWithEvent:(NSEvent *)event;
- (void)touchesMovedWithEvent:(NSEvent *)event;
- (void)touchesEndedWithEvent:(NSEvent *)event;
- (void)touchesCancelledWithEvent:(NSEvent *)event;

- (void)helpRequested:(NSEvent *)eventPtr;
- (void)showContextHelp:(nullable id)sender;

/* THE STATUS DOORS, whose defaults are the asymmetry described above. */
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;

/* AND THE FOUR THAT ANSWER RATHER THAN FORWARD. */
- (BOOL)performKeyEquivalent:(NSEvent *)theEvent;
- (BOOL)performMnemonic:(NSString *)theString;
- (BOOL)shouldBeTreatedAsInkEvent:(NSEvent *)theEvent;
- (nullable id)validRequestorForSendType:(nullable NSString *)sendType
			      returnType:(nullable NSString *)returnType;
- (void)flushBufferedKeyEvents;

/* THE INTERFACE STYLE, STORED WITH A WALK. `NSNoInterfaceStyle` means "this responder has no opinion", which
 * is why setting it back to that value is the same as never having set one. */
- (NSInterfaceStyle)interfaceStyle;
- (void)setInterfaceStyle:(NSInterfaceStyle)interfaceStyle;

/* THE CONTEXTUAL MENU. See the `id` note at the top of this file: the object is an NSMenu and this tier has
 * no NSMenu, but holding one is not configuring one. */
- (nullable id)menu;
- (void)setMenu:(nullable id)menu;

/* THE UNDO MANAGER, WHICH THIS TIER DOES HAVE: Foundation ships NSUndoManager, so the walk is the whole
 * implementation and a responder with nothing to say lets the chain answer. */
- (nullable NSUndoManager *)undoManager;

/* THE ERROR PRESENTATION. `-willPresentError:` is the hook a subclass overrides and its default is to hand
 * the error back unchanged; `-presentError:` runs the hook and forwards; the modal form needs a sheet AND an
 * NSAlert to put in it. */
- (NSError *)willPresentError:(NSError *)error;
- (BOOL)presentError:(NSError *)error;
- (void)presentError:(NSError *)error
       modalForWindow:(nullable NSWindow *)window
	     delegate:(nullable id)delegate
   didPresentSelector:(nullable SEL)didPresentSelector
	contextInfo:(nullable void *)contextInfo;

/* AND THE ONE KEY DOOR THAT NEEDS AN INPUT METHOD, REFUSED BY NAME. */
- (void)interpretKeyEvents:(NSArray *)eventArray;

@end

/* THE TWO GLOBALS THE INTERFACE-STYLE FAMILY IS READ THROUGH, and they are INSIDE the nullability region on
 * purpose: an unannotated pointer in a public header is a warning this tree's build does not ship. BOTH
 * ARGUMENTS ARE NULLABLE, and that is Apple's own contract rather than laziness — the artefact's comment on
 * the function says "the responder should always be passed, but in situations where a responder is not
 * available, pass nil", and the KEY is nullable for the same reason, since passing nil is how a caller asks
 * for the global setting. AND THE SPELLING IS `_Nullable` RATHER THAN `nullable` ON PURPOSE: the short form
 * is clang's CONTEXTUAL keyword, which the parser accepts in a method or property declaration and NOT in a
 * plain C prototype — measured, it is `unknown type name 'nullable'` there. `_Nullable` is the language's
 * own keyword and is what Foundation's C prototypes use (FNSpellServerDispatch.h). */
extern NSInterfaceStyle NSInterfaceStyleForKey(NSString *_Nullable key, NSResponder *_Nullable responder);
extern NSString *NSInterfaceStyleDefault;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSRESPONDER_H */
