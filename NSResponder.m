/*
 * NSResponder — the chain, and the one behaviour in it that does anything.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE WHOLE CLASS IS TWO IDEAS, and they are worth separating because only one of them is a behaviour.
 *
 * THE FIRST IS THE WALK. `-tryToPerform:with:` asks the receiver, and on a refusal asks the receiver's
 * next responder, and so on to the end — which is what makes an UNTARGETED action reach whatever in a view
 * hierarchy actually implements it. It is written here as recursion through `-nextResponder` rather than as
 * a loop over `self`, because that is what the contract says: ANY responder in the chain can override the
 * walk, and a loop would take that away.
 *
 * THE SECOND IS THE FORWARDING, AND IT IS DELIBERATELY DULL. Every event method below is one line, and each
 * one is Apple's documented default: hand the event to the next responder. A class that returned without
 * forwarding would silently swallow input, and a class that did something clever would be impossible to
 * override selectively — the two failure modes of a responder base are opposite, and this is neither.
 *
 * AND THE STATUS DEFAULTS ARE THE ASYMMETRY THE HEADER DESCRIBES: `-acceptsFirstResponder` is NO because
 * accepting the role is opt-in, while `-becomeFirstResponder`/`-resignFirstResponder` answer YES because
 * performing the transition is what a responder does unless it objects.
 *
 * MRC OWNERSHIP IS ONE RETAINED POINTER NOW: `_nextResponder` is a non-retained back-pointer (a chain that
 * retained its successor would leak a view hierarchy from its root) and `_menu` IS retained, because it is
 * an object the responder was handed and nothing else in the chain owns. That is the whole of `-dealloc`.
 *
 * AND THE DOORS THAT ARE NEITHER A WALK NOR A FORWARD ARE EACH A DIFFERENT KIND OF THING, which the header
 * states and this file has to honour: the interface style and the menu are STORED (`-interfaceStyle` walks
 * only when it has no opinion of its own, which is what `NSNoInterfaceStyle` means); `-undoManager` IS a
 * walk and nothing else, because Foundation ships the class it answers; the error-presentation pair runs
 * Apple's hook and then REFUSES AT THE END OF THE CHAIN, where the thing this tier has not got — an NSAlert
 * to put the error in — is what Apple's own final step needs; and `-interpretKeyEvents:` REFUSES WITHOUT
 * FORWARDING, because an event handed on uninterpreted would claim a keystroke had been dealt with.
 */
#import <AppKit/NSResponder.h>

#include "AppKitRefusal.h"	/* fn_refuse_window — the one refusal message, in one place. */

@implementation NSResponder

/* ------------------------------------------------------------------------- */
/* The chain                                                                  */
/* ------------------------------------------------------------------------- */

- (NSResponder *)nextResponder
{
	return _nextResponder;
}

- (void)setNextResponder:(NSResponder *)aResponder
{
	/* ASSIGNMENT, NOT RETENTION: a link that retained its successor would make a chain a cycle and leak a
	 * view hierarchy from its root. The caller owns the structure; the chain only refers to it. */
	_nextResponder = aResponder;
}

- (BOOL)tryToPerform:(SEL)anAction with:(id)anObject
{
	if (anAction == NULL) {
		return NO;
	}
	if ([self respondsToSelector:anAction]) {
		[self performSelector:anAction withObject:anObject];
		return YES;
	}
	/* THE END OF THE CHAIN IS WHERE `-noResponderFor:` IS THE SENDER'S TO CALL: this method answers NO
	 * rather than invoking it, because the sender is the one that knows the selector it tried. */
	return [[self nextResponder] tryToPerform:anAction with:anObject];
}

- (void)noResponderFor:(SEL)eventSelector
{
	/* APPLE'S DEFAULT DOES NOTHING and NSWindow's is the one that beeps, which is why this is quiet rather
	 * than a complaint: a responder that logged here would log on every unhandled keystroke. */
	(void)eventSelector;
}

- (void)dealloc
{
	[_menu release];
	[super dealloc];
}

/* ------------------------------------------------------------------------- */
/* The event methods: every one forwards, and none of them decides anything    */
/* ------------------------------------------------------------------------- */

- (void)mouseDown:(NSEvent *)theEvent
{
	[[self nextResponder] mouseDown:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent
{
	[[self nextResponder] mouseUp:theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	[[self nextResponder] mouseDragged:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	[[self nextResponder] mouseMoved:theEvent];
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	[[self nextResponder] mouseEntered:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent
{
	[[self nextResponder] mouseExited:theEvent];
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
	[[self nextResponder] rightMouseDown:theEvent];
}

- (void)rightMouseUp:(NSEvent *)theEvent
{
	[[self nextResponder] rightMouseUp:theEvent];
}

- (void)rightMouseDragged:(NSEvent *)theEvent
{
	[[self nextResponder] rightMouseDragged:theEvent];
}

- (void)otherMouseDown:(NSEvent *)theEvent
{
	[[self nextResponder] otherMouseDown:theEvent];
}

- (void)otherMouseUp:(NSEvent *)theEvent
{
	[[self nextResponder] otherMouseUp:theEvent];
}

- (void)otherMouseDragged:(NSEvent *)theEvent
{
	[[self nextResponder] otherMouseDragged:theEvent];
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	[[self nextResponder] scrollWheel:theEvent];
}

- (void)keyDown:(NSEvent *)theEvent
{
	[[self nextResponder] keyDown:theEvent];
}

- (void)keyUp:(NSEvent *)theEvent
{
	[[self nextResponder] keyUp:theEvent];
}

- (void)flagsChanged:(NSEvent *)theEvent
{
	[[self nextResponder] flagsChanged:theEvent];
}

- (void)tabletPoint:(NSEvent *)theEvent
{
	[[self nextResponder] tabletPoint:theEvent];
}

- (void)tabletProximity:(NSEvent *)theEvent
{
	[[self nextResponder] tabletProximity:theEvent];
}

- (void)cursorUpdate:(NSEvent *)event
{
	[[self nextResponder] cursorUpdate:event];
}

- (void)magnifyWithEvent:(NSEvent *)event
{
	[[self nextResponder] magnifyWithEvent:event];
}

- (void)rotateWithEvent:(NSEvent *)event
{
	[[self nextResponder] rotateWithEvent:event];
}

- (void)swipeWithEvent:(NSEvent *)event
{
	[[self nextResponder] swipeWithEvent:event];
}

- (void)beginGestureWithEvent:(NSEvent *)event
{
	[[self nextResponder] beginGestureWithEvent:event];
}

- (void)endGestureWithEvent:(NSEvent *)event
{
	[[self nextResponder] endGestureWithEvent:event];
}

- (void)touchesBeganWithEvent:(NSEvent *)event
{
	[[self nextResponder] touchesBeganWithEvent:event];
}

- (void)touchesMovedWithEvent:(NSEvent *)event
{
	[[self nextResponder] touchesMovedWithEvent:event];
}

- (void)touchesEndedWithEvent:(NSEvent *)event
{
	[[self nextResponder] touchesEndedWithEvent:event];
}

- (void)touchesCancelledWithEvent:(NSEvent *)event
{
	[[self nextResponder] touchesCancelledWithEvent:event];
}

- (void)helpRequested:(NSEvent *)eventPtr
{
	[[self nextResponder] helpRequested:eventPtr];
}

- (void)showContextHelp:(id)sender
{
	/* APPLE'S DEFAULT PRESENTS THE CONTEXTUAL HELP FOR THE RECEIVER'S CONTEXT, and there is no help system
	 * in this tree yet — so this forwards rather than pretending, which keeps the chain intact for a
	 * subclass that does have something to say. */
	[[self nextResponder] showContextHelp:sender];
}

/* ------------------------------------------------------------------------- */
/* The status doors                                                           */
/* ------------------------------------------------------------------------- */

- (BOOL)acceptsFirstResponder
{
	/* OPT-IN, which is the whole reason this is NO: a responder becomes first responder only by saying so,
	 * and Apple's NSView answers NO here and YES where it means it. */
	return NO;
}

- (BOOL)becomeFirstResponder
{
	return YES;
}

- (BOOL)resignFirstResponder
{
	return YES;
}

/* ------------------------------------------------------------------------- */
/* The four that answer rather than forward                                    */
/* ------------------------------------------------------------------------- */

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
	/* NO MEANS "I DID NOT ACT ON IT", and every responder that has no key equivalent answers exactly that,
	 * which is what lets the event travel on to the one that does. */
	(void)theEvent;
	return NO;
}

- (BOOL)performMnemonic:(NSString *)theString
{
	(void)theString;
	return NO;
}

- (BOOL)shouldBeTreatedAsInkEvent:(NSEvent *)theEvent
{
	(void)theEvent;
	return NO;
}

- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
	/* NIL MEANS "NOT ME" — the answer that keeps a services request moving up the chain instead of stopping
	 * at the first responder it reaches. */
	(void)sendType;
	(void)returnType;
	return nil;
}

- (void)flushBufferedKeyEvents
{
	/* NOTHING IS BUFFERED HERE YET: an input method that buffers key events is a stage-J concern, and a
	 * no-op is the honest default until one exists. */
}

/* ------------------------------------------------------------------------- */
/* The interface style: stored, with the walk                                 */
/* ------------------------------------------------------------------------- */

- (NSInterfaceStyle)interfaceStyle
{
	/* AN OPINION OF THIS RESPONDER'S OWN WINS; without one the question belongs to the next link — and
	 * `NSNoInterfaceStyle` is "unset" rather than a failure, which is why a fresh responder is silent. The
	 * chain's end answers 0 by the message-to-nil rule, so there is no terminal case to write. */
	if (_interfaceStyle != NSNoInterfaceStyle) {
		return _interfaceStyle;
	}
	return [[self nextResponder] interfaceStyle];
}

- (void)setInterfaceStyle:(NSInterfaceStyle)interfaceStyle
{
	_interfaceStyle = interfaceStyle;
}

/* ------------------------------------------------------------------------- */
/* The contextual menu: stored, and it owns what it was given                 */
/* ------------------------------------------------------------------------- */

- (id)menu
{
	return _menu;
}

- (void)setMenu:(id)menu
{
	/* RETAINED, because nothing else in the chain owns it: the caller that hands a responder a menu is not
	 * promising to keep it alive, and a menu that vanished under a right-click would be a worse failure
	 * than a retain cycle that cannot happen here (nothing in this design points back at the responder). */
	if (menu != _menu) {
		[menu retain];
		[_menu release];
		_menu = menu;
	}
}

/* ------------------------------------------------------------------------- */
/* The undo manager: a walk, because Foundation ships the class               */
/* ------------------------------------------------------------------------- */

- (NSUndoManager *)undoManager
{
	/* APPLE ANSWERS THIS FROM THE WINDOW AND ITS DELEGATE, and a window reaches its delegate through
	 * `-windowWillReturnUndoManager:`. So the walk IS the implementation: a responder with no manager of
	 * its own hands the question up the chain, and nil at the end of it is the truth — there is no
	 * document, and therefore no undo stack, behind this responder. */
	return [[self nextResponder] undoManager];
}

/* ------------------------------------------------------------------------- */
/* The error presentation: the hook is real, the presentation is refused       */
/* ------------------------------------------------------------------------- */

- (NSError *)willPresentError:(NSError *)error
{
	/* APPLE'S DEFAULT HANDS THE ERROR BACK UNCHANGED, and that is the whole of the extension point: a
	 * subclass that wants a more specific message replaces it here, and every caller of `-presentError:`
	 * sees the replacement. */
	return error;
}

- (BOOL)presentError:(NSError *)error
{
	NSError *custom = [self willPresentError:error];

	/* THE HOOK RUNS AT EVERY LINK, WHICH IS WHAT MAKES AN OVERRIDE ANYWHERE IN THE CHAIN EFFECTIVE: a
	 * responder that customises the error does it on the way up, before anyone can present it. */
	if ([self nextResponder] != nil) {
		return [[self nextResponder] presentError:custom];
	}
	/* AND WHERE THE CHAIN ENDS THIS TIER CANNOT FINISH THE JOB: Apple's own last step puts the error in an
	 * NSAlert and begins it as a sheet, and NSAlert is a class this tier has not got. NO means "not
	 * presented", so a caller can tell a refusal from a presentation. */
	fn_refuse_window("-presentError:", "an alert to present the error in (NSAlert is not in this tier)");
	return NO;
}

- (void)presentError:(NSError *)error
       modalForWindow:(NSWindow *)window
	     delegate:(id)delegate
   didPresentSelector:(SEL)didPresentSelector
	contextInfo:(void *)contextInfo
{
	/* THE MODAL FORM IS THE SAME SHAPE and is refused in the same place — at the END of the chain, so a
	 * responder that CAN present (none in this tier can yet) would have taken it first. Handing an alert to
	 * a sheet is what the window layer would do; what is missing is the alert, not the sheet. */
	if ([self nextResponder] != nil) {
		[[self nextResponder] presentError:error
				    modalForWindow:window
					  delegate:delegate
				didPresentSelector:didPresentSelector
				       contextInfo:contextInfo];
		return;
	}
	fn_refuse_window("-presentError:modalForWindow:delegate:didPresentSelector:contextInfo:",
			 "an alert to present the error in (NSAlert is not in this tier)");
}

/* ------------------------------------------------------------------------- */
/* The key door that needs an input method                                    */
/* ------------------------------------------------------------------------- */

- (void)interpretKeyEvents:(NSArray *)eventArray
{
	/* REFUSED BY NAME, AND IT DOES NOT FORWARD EITHER, which is the difference between this and the event
	 * methods above: Apple hands each event to the receiver's INPUT CONTEXT and the answers come back as
	 * `-insertText:` and `-doCommandBySelector:`. With no input context the events would have nowhere to go,
	 * and forwarding them would pretend a keystroke had been interpreted by handing it on as if nothing had
	 * happened. Saying what is missing is the only honest answer. */
	(void)eventArray;
	fn_refuse_window("-interpretKeyEvents:", "the input-method machinery (an input context and the key"
			 " bindings that answer it; the commands themselves are stage J's)");
}

@end

/* ------------------------------------------------------------------------- */
/* The two globals the interface-style family is read through                 */
/* ------------------------------------------------------------------------- */

/* THE KEY IS ITS OWN NAME, which is how this tree writes a constant whose only job is to be a name (NSNib's
 * `owner` and `topLevelObjects` do the same). What this tier has NOT got is the preferences domain the key
 * would be filed under — an interface style is 10.0-era API Apple itself deprecated — and that is what the
 * function below says rather than invents. */
NSString *NSInterfaceStyleDefault = @"NSInterfaceStyleDefault";

NSInterfaceStyle NSInterfaceStyleForKey(NSString *_Nullable key, NSResponder *_Nullable responder)
{
	/* APPLE ANSWERS THIS FROM THE USER'S DEFAULTS, keyed by the string passed in. There is no such domain
	 * here, so the answer is the RESPONDER the caller gave — the part of the contract this tier can honour,
	 * and the part that matters to a ported program. A nil responder answers NSNoInterfaceStyle, the
	 * artefact's own "default value" constant, which is what Apple tells a caller with no responder to
	 * expect. */
	(void)key;
	if (responder == nil) {
		return NSNoInterfaceStyle;
	}
	return [responder interfaceStyle];
}
