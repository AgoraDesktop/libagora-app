/*
 * NSResponder — the chain, and the one behaviour in it that does anything.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
 * to put the error in — is what Apple's own final step needs; and `-interpretKeyEvents:` HANDS EACH EVENT TO THE
 * RECEIVER'S INPUT CONTEXT, which is where an input method belongs and where the standard key binding now lives.
 */
#import <AppKit/NSResponder.h>
#import <AppKit/NSTextInputContext.h>
#import <AppKit/NSAlert.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>

#include "AppKitRefusal.h"	/* fn_refuse_window — the one refusal message, in one place. */

/* THE VIEW'S INPUT CONTEXT, DECLARED HERE SO THIS FILE CAN ASK FOR IT WITHOUT PUTTING A VIEW'S DOOR IN THE RESPONDER'S
 * HEADER. A responder that is not a view does not answer it, which the guard in `-interpretKeyEvents:` allows for. */
@interface NSResponder (FNInputContext)
- (nullable id)inputContext;
@end

typedef void (*AGErrorDidPresentIMP)(id, SEL, BOOL, void *);

@interface AGErrorPresentationContext : NSObject
{
@public
	id _delegate;
	SEL _selector;
	void *_contextInfo;
}
- (instancetype)initWithDelegate:(id)delegate selector:(SEL)selector contextInfo:(void *)contextInfo;
- (void)finish;
@end

@implementation AGErrorPresentationContext

- (instancetype)initWithDelegate:(id)delegate selector:(SEL)selector contextInfo:(void *)contextInfo
{
	self = [super init];
	if (self != nil) {
		_delegate = [delegate retain];
		_selector = selector;
		_contextInfo = contextInfo;
	}
	return self;
}

- (void)dealloc
{
	[_delegate release];
	[super dealloc];
}

- (void)finish
{
	if (_delegate != nil && _selector != NULL && [_delegate respondsToSelector:_selector]) {
		AGErrorDidPresentIMP imp = (AGErrorDidPresentIMP)[_delegate methodForSelector:_selector];

		imp(_delegate, _selector, NO, _contextInfo);
	}
	[self release];
}

@end

@implementation NSResponder

/* ============================================================================================
 * ARCHIVING: THE ROOT OF EVERY DESIGN CLASS'S CHAIN, AND THE PLACE THE CHAIN STARTS CHAINING.
 * ============================================================================================ */

/* THE KEYS ARE PROPERTY NAMES, because the format's vocabulary is the public API rather than a private dialect: a
 * design file says `interfaceStyle` because that is what a caller sets, and a reader can be checked against the
 * header. Two things are deliberately NOT here — `_nextResponder`, which is the shape of a LIVE chain rather than
 * the shape of a design (a container rebuilds it), and `_menu`, which IS archived: a context menu is part of a
 * design and `NSMenu` is on the reader's allow-list. */
static NSString * const AGCoderInterfaceStyleKey = @"interfaceStyle";
static NSString * const AGCoderMenuKey = @"menu";

/* **`NSObject` IS NOT ARCHIVABLE, SO THIS IS WHERE THE CHAIN STOPS.** `-encodeWithCoder:` here does NOT call
 * `[super encodeWithCoder:]` — there is no such method to reach, and sending it would be an unrecognized selector at
 * archive time. Every class BELOW this one does chain, which is what makes a view's archive carry its responder
 * state and what `NSViewController`'s note was waiting for. */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeInteger:(NSInteger)_interfaceStyle forKey:AGCoderInterfaceStyleKey];
	[aCoder encodeObject:_menu forKey:AGCoderMenuKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	if (self != nil) {
		_interfaceStyle = (NSInterfaceStyle)[aDecoder decodeIntegerForKey:AGCoderInterfaceStyleKey];
		_menu = [[aDecoder decodeObjectForKey:AGCoderMenuKey] retain];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

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
	/* **THE END OF THE CHAIN PRESENTS THE ERROR NOW.** `NSAlert` exists, so the last responder builds an alert
	 * from the error — its localized description, failure reason and recovery options are the alert factory's —
	 * and runs it. */
	{
		NSAlert *alert = [NSAlert alertWithError:custom];

		(void)[alert runModal];
		return YES;	/* the alert was presented; this tier has no recovery delegate to report */
	}
}

/* **THE END OF THE CHAIN PRESENTS THE MODAL FORM TOO.** A window gets a sheet; a windowless call gets the
 * application-modal alert. The caller's `didPresentSelector` receives `didRecover:NO` — this tier has no recovery
 * delegate to attempt a recovery option with, which is the honest answer rather than a second recovery model. */

- (void)presentError:(NSError *)error
       modalForWindow:(NSWindow *)window
	     delegate:(id)delegate
   didPresentSelector:(SEL)didPresentSelector
	contextInfo:(void *)contextInfo
{
	NSError *custom = [self willPresentError:error];

	if ([self nextResponder] != nil) {
		[[self nextResponder] presentError:custom
				    modalForWindow:window
					  delegate:delegate
				didPresentSelector:didPresentSelector
				       contextInfo:contextInfo];
		return;
	}
	{
		NSAlert *alert = [NSAlert alertWithError:custom];
		AGErrorPresentationContext *context = [[AGErrorPresentationContext alloc] initWithDelegate:delegate
												 selector:didPresentSelector
											      contextInfo:contextInfo];

		if (window != nil && [[NSApplication sharedApplication] isRunning]) {
			[alert beginSheetModalForWindow:window modalDelegate:self
					  didEndSelector:@selector(cg_errorAlertDidEnd:returnCode:contextInfo:)
					     contextInfo:context];
			return;
		}
		(void)[alert runModal];
		[context finish];
	}
}

- (void)cg_errorAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)contextInfo
{
	(void)alert;
	(void)code;
	[(AGErrorPresentationContext *)contextInfo finish];
}

/* ------------------------------------------------------------------------- */
/* The standard key-binding commands                                        */
/* ------------------------------------------------------------------------- */

/* **EVERY ONE OF THESE DEFAULTS TO THE SAME THING: HAND IT TO THE NEXT RESPONDER.** That is not a stub — it is the
 * contract of an informal protocol, and it is what makes a command work in a window whose editor is a view the sender
 * has never heard of: an Edit menu's Copy item carries `-copy:` with a NIL target, the chain is walked, and the first
 * responder that IMPLEMENTS it stops the walk. A responder that does not implement it is not refusing it.
 *
 * THE CHAIN'S END IS SILENT because this tier has no beep: Apple's last responder rings the system bell, and there is
 * no bell here to ring — stated rather than left as a mystery about why a stray keystroke does nothing. */
- (void)insertText:(id)insertString
{
	(void)insertString;
	[[self nextResponder] insertText:insertString];
}

/* **AND THIS ONE'S DEFAULT IS SUBTLY DIFFERENT, WHICH IS THE POINT OF IT.** An input context calls
 * `-doCommandBySelector:` to ask the responder to PERFORM a command, so the responder's own implementation is tried
 * FIRST and only an unimplemented command is forwarded — otherwise a text view that answers `-moveLeft:` and forwards
 * blindly would send its own command past itself. The `-respondsToSelector:` check is the whole difference, and the
 * guard against this very selector is what keeps a responder whose ``-doCommandBySelector:`` is the only thing it
 * implements from calling itself forever. */
- (void)doCommandBySelector:(SEL)aSelector
{
	if (aSelector == NULL) {
		return;
	}
	if (aSelector != @selector(doCommandBySelector:) && [self respondsToSelector:aSelector]) {
		[self performSelector:aSelector withObject:nil];
		return;
	}
	[[self nextResponder] doCommandBySelector:aSelector];
}

- (void)moveLeft:(id)sender				{ [[self nextResponder] moveLeft:sender]; }
- (void)moveRight:(id)sender				{ [[self nextResponder] moveRight:sender]; }
- (void)moveLeftAndModifySelection:(id)sender		{ [[self nextResponder] moveLeftAndModifySelection:sender]; }
- (void)moveRightAndModifySelection:(id)sender		{ [[self nextResponder] moveRightAndModifySelection:sender]; }
- (void)moveToBeginningOfLine:(id)sender			{ [[self nextResponder] moveToBeginningOfLine:sender]; }
- (void)moveToEndOfLine:(id)sender			{ [[self nextResponder] moveToEndOfLine:sender]; }
- (void)moveToBeginningOfLineAndModifySelection:(id)sender
{
	[[self nextResponder] moveToBeginningOfLineAndModifySelection:sender];
}
- (void)moveToEndOfLineAndModifySelection:(id)sender
{
	[[self nextResponder] moveToEndOfLineAndModifySelection:sender];
}
- (void)moveWordLeft:(id)sender				{ [[self nextResponder] moveWordLeft:sender]; }
- (void)moveWordRight:(id)sender				{ [[self nextResponder] moveWordRight:sender]; }
- (void)moveWordLeftAndModifySelection:(id)sender	{ [[self nextResponder] moveWordLeftAndModifySelection:sender]; }
- (void)moveWordRightAndModifySelection:(id)sender	{ [[self nextResponder] moveWordRightAndModifySelection:sender]; }
- (void)moveUp:(id)sender				{ [[self nextResponder] moveUp:sender]; }
- (void)moveDown:(id)sender				{ [[self nextResponder] moveDown:sender]; }
- (void)moveUpAndModifySelection:(id)sender		{ [[self nextResponder] moveUpAndModifySelection:sender]; }
- (void)moveDownAndModifySelection:(id)sender		{ [[self nextResponder] moveDownAndModifySelection:sender]; }
- (void)moveToBeginningOfDocument:(id)sender		{ [[self nextResponder] moveToBeginningOfDocument:sender]; }
- (void)moveToEndOfDocument:(id)sender			{ [[self nextResponder] moveToEndOfDocument:sender]; }
- (void)moveToBeginningOfDocumentAndModifySelection:(id)sender
{
	[[self nextResponder] moveToBeginningOfDocumentAndModifySelection:sender];
}
- (void)moveToEndOfDocumentAndModifySelection:(id)sender
{
	[[self nextResponder] moveToEndOfDocumentAndModifySelection:sender];
}
- (void)deleteBackward:(id)sender			{ [[self nextResponder] deleteBackward:sender]; }
- (void)deleteForward:(id)sender			{ [[self nextResponder] deleteForward:sender]; }
- (void)deleteWordBackward:(id)sender			{ [[self nextResponder] deleteWordBackward:sender]; }
- (void)deleteWordForward:(id)sender			{ [[self nextResponder] deleteWordForward:sender]; }
- (void)deleteToBeginningOfLine:(id)sender		{ [[self nextResponder] deleteToBeginningOfLine:sender]; }
- (void)deleteToEndOfLine:(id)sender			{ [[self nextResponder] deleteToEndOfLine:sender]; }
- (void)insertNewline:(id)sender			{ [[self nextResponder] insertNewline:sender]; }
- (void)insertTab:(id)sender				{ [[self nextResponder] insertTab:sender]; }
- (void)insertBacktab:(id)sender			{ [[self nextResponder] insertBacktab:sender]; }
- (void)transpose:(id)sender				{ [[self nextResponder] transpose:sender]; }
- (void)insertParagraphSeparator:(id)sender		{ [[self nextResponder] insertParagraphSeparator:sender]; }
- (void)insertNewlineIgnoringFieldEditor:(id)sender	{ [[self nextResponder] insertNewlineIgnoringFieldEditor:sender]; }
- (void)insertTabIgnoringFieldEditor:(id)sender		{ [[self nextResponder] insertTabIgnoringFieldEditor:sender]; }
- (void)cancelOperation:(id)sender			{ [[self nextResponder] cancelOperation:sender]; }
- (void)selectAll:(id)sender				{ [[self nextResponder] selectAll:sender]; }
- (void)copy:(id)sender					{ [[self nextResponder] copy:sender]; }
- (void)cut:(id)sender					{ [[self nextResponder] cut:sender]; }
- (void)paste:(id)sender					{ [[self nextResponder] paste:sender]; }
- (void)delete:(id)sender				{ [[self nextResponder] delete:sender]; }

/* ------------------------------------------------------------------------- */
/* The rest of the era's command set: forwarders, and nothing else             */
/* ------------------------------------------------------------------------- */

/* **A FORWARDER IS THE WHOLE IMPLEMENTATION, AND THE HEADER SAYS WHY.** A command is sent to the first responder and
 * travels the chain until somebody answers it; the base class is the class that passes it on. Writing these the other
 * way — a refusal — is what this tree did once and had to undo: the declared-only door left a key binding with nothing
 * to name. THE LAST FIVE ARE THE ONES NO VIEW IN THIS TIER ANSWERS YET, and forwarding them is still right: a window
 * with a text view that has nothing to page simply does nothing, which is what Apple's base does too. */

/* THE OLDER SPELLINGS, which an old key binding (or a ported nib) may still name. */
- (void)moveBackward:(id)sender			{ [[self nextResponder] moveBackward:sender]; }
- (void)moveBackwardAndModifySelection:(id)sender
{
	[[self nextResponder] moveBackwardAndModifySelection:sender];
}
- (void)moveForward:(id)sender				{ [[self nextResponder] moveForward:sender]; }
- (void)moveForwardAndModifySelection:(id)sender
{
	[[self nextResponder] moveForwardAndModifySelection:sender];
}
- (void)moveWordBackward:(id)sender			{ [[self nextResponder] moveWordBackward:sender]; }
- (void)moveWordBackwardAndModifySelection:(id)sender
{
	[[self nextResponder] moveWordBackwardAndModifySelection:sender];
}
- (void)moveWordForward:(id)sender			{ [[self nextResponder] moveWordForward:sender]; }
- (void)moveWordForwardAndModifySelection:(id)sender
{
	[[self nextResponder] moveWordForwardAndModifySelection:sender];
}

/* THE LINE'S TWO ENDS BY THEIR OWN NAMES. */
- (void)moveToLeftEndOfLine:(id)sender			{ [[self nextResponder] moveToLeftEndOfLine:sender]; }
- (void)moveToLeftEndOfLineAndModifySelection:(id)sender
{
	[[self nextResponder] moveToLeftEndOfLineAndModifySelection:sender];
}
- (void)moveToRightEndOfLine:(id)sender			{ [[self nextResponder] moveToRightEndOfLine:sender]; }
- (void)moveToRightEndOfLineAndModifySelection:(id)sender
{
	[[self nextResponder] moveToRightEndOfLineAndModifySelection:sender];
}

/* THE PARAGRAPH FAMILY. */
- (void)moveToBeginningOfParagraph:(id)sender		{ [[self nextResponder] moveToBeginningOfParagraph:sender]; }
- (void)moveToEndOfParagraph:(id)sender			{ [[self nextResponder] moveToEndOfParagraph:sender]; }
- (void)moveToBeginningOfParagraphAndModifySelection:(id)sender
{
	[[self nextResponder] moveToBeginningOfParagraphAndModifySelection:sender];
}
- (void)moveToEndOfParagraphAndModifySelection:(id)sender
{
	[[self nextResponder] moveToEndOfParagraphAndModifySelection:sender];
}
- (void)moveParagraphBackwardAndModifySelection:(id)sender
{
	[[self nextResponder] moveParagraphBackwardAndModifySelection:sender];
}
- (void)moveParagraphForwardAndModifySelection:(id)sender
{
	[[self nextResponder] moveParagraphForwardAndModifySelection:sender];
}
- (void)deleteToBeginningOfParagraph:(id)sender		{ [[self nextResponder] deleteToBeginningOfParagraph:sender]; }
- (void)deleteToEndOfParagraph:(id)sender		{ [[self nextResponder] deleteToEndOfParagraph:sender]; }

/* THE SELECTION'S UNIT COMMANDS. */
- (void)selectWord:(id)sender				{ [[self nextResponder] selectWord:sender]; }
- (void)selectLine:(id)sender				{ [[self nextResponder] selectLine:sender]; }
- (void)selectParagraph:(id)sender			{ [[self nextResponder] selectParagraph:sender]; }

/* PAGING AND SCROLLING — four that move the insertion point and six that move the viewport. */
- (void)pageUp:(id)sender				{ [[self nextResponder] pageUp:sender]; }
- (void)pageDown:(id)sender				{ [[self nextResponder] pageDown:sender]; }
- (void)pageUpAndModifySelection:(id)sender		{ [[self nextResponder] pageUpAndModifySelection:sender]; }
- (void)pageDownAndModifySelection:(id)sender		{ [[self nextResponder] pageDownAndModifySelection:sender]; }
- (void)scrollPageUp:(id)sender				{ [[self nextResponder] scrollPageUp:sender]; }
- (void)scrollPageDown:(id)sender			{ [[self nextResponder] scrollPageDown:sender]; }
- (void)scrollLineUp:(id)sender				{ [[self nextResponder] scrollLineUp:sender]; }
- (void)scrollLineDown:(id)sender			{ [[self nextResponder] scrollLineDown:sender]; }
- (void)scrollToBeginningOfDocument:(id)sender		{ [[self nextResponder] scrollToBeginningOfDocument:sender]; }
- (void)scrollToEndOfDocument:(id)sender		{ [[self nextResponder] scrollToEndOfDocument:sender]; }
- (void)centerSelectionInVisibleArea:(id)sender		{ [[self nextResponder] centerSelectionInVisibleArea:sender]; }

/* THE MARK AND THE KILL RING. */
- (void)setMark:(id)sender				{ [[self nextResponder] setMark:sender]; }
- (void)selectToMark:(id)sender				{ [[self nextResponder] selectToMark:sender]; }
- (void)deleteToMark:(id)sender				{ [[self nextResponder] deleteToMark:sender]; }
- (void)swapWithMark:(id)sender				{ [[self nextResponder] swapWithMark:sender]; }
- (void)yank:(id)sender					{ [[self nextResponder] yank:sender]; }

/* THE CASE AND DIRECTION FAMILIES. */
- (void)capitalizeWord:(id)sender			{ [[self nextResponder] capitalizeWord:sender]; }
- (void)lowercaseWord:(id)sender			{ [[self nextResponder] lowercaseWord:sender]; }
- (void)uppercaseWord:(id)sender			{ [[self nextResponder] uppercaseWord:sender]; }
- (void)changeCaseOfLetter:(id)sender			{ [[self nextResponder] changeCaseOfLetter:sender]; }
- (void)transposeWords:(id)sender			{ [[self nextResponder] transposeWords:sender]; }
- (void)makeBaseWritingDirectionLeftToRight:(id)sender
{
	[[self nextResponder] makeBaseWritingDirectionLeftToRight:sender];
}
- (void)makeBaseWritingDirectionRightToLeft:(id)sender
{
	[[self nextResponder] makeBaseWritingDirectionRightToLeft:sender];
}
- (void)makeBaseWritingDirectionNatural:(id)sender
{
	[[self nextResponder] makeBaseWritingDirectionNatural:sender];
}
- (void)makeTextWritingDirectionLeftToRight:(id)sender
{
	[[self nextResponder] makeTextWritingDirectionLeftToRight:sender];
}
- (void)makeTextWritingDirectionRightToLeft:(id)sender
{
	[[self nextResponder] makeTextWritingDirectionRightToLeft:sender];
}
- (void)makeTextWritingDirectionNatural:(id)sender
{
	[[self nextResponder] makeTextWritingDirectionNatural:sender];
}

/* THE LAST FIVE, WHICH NO VIEW HERE ANSWERS YET — and forwarding is still the right body. */
- (void)indent:(id)sender				{ [[self nextResponder] indent:sender]; }
- (void)complete:(id)sender				{ [[self nextResponder] complete:sender]; }
- (void)insertLineBreak:(id)sender			{ [[self nextResponder] insertLineBreak:sender]; }
- (void)insertContainerBreak:(id)sender			{ [[self nextResponder] insertContainerBreak:sender]; }
- (void)insertSingleQuoteIgnoringSubstitution:(id)sender
{
	[[self nextResponder] insertSingleQuoteIgnoringSubstitution:sender];
}
- (void)insertDoubleQuoteIgnoringSubstitution:(id)sender
{
	[[self nextResponder] insertDoubleQuoteIgnoringSubstitution:sender];
}
- (void)deleteBackwardByDecomposingPreviousCharacter:(id)sender
{
	[[self nextResponder] deleteBackwardByDecomposingPreviousCharacter:sender];
}

/* ------------------------------------------------------------------------- */
/* The door that turns events into commands                                    */
/* ------------------------------------------------------------------------- */

/* **AND THE KEY GOES TO THE INPUT CONTEXT, WHICH IS WHERE AN INPUT METHOD WOULD SEE IT FIRST.** Apple's
 * `-interpretKeyEvents:` is a hand-off: the context sends the event to the input source, the source composes through
 * the `NSTextInput` doors, and what it does not consume falls back to the standard key binding — which is why the
 * MAPPING LIVES IN `NSTextInputContext` NOW rather than here. THE CONTEXT IS THE VIEW'S, and a responder that has none
 * — one that is not a view, or a view that is not a text input client — handles no keys here, which is the truth for
 * a responder with no text behavior. */
- (void)interpretKeyEvents:(NSArray *)eventArray
{
	NSUInteger i, count = [eventArray count];
	id context = [self respondsToSelector:@selector(inputContext)] ? [self inputContext] : nil;

	if (context == nil) {
		return;
	}
	for (i = 0; i < count; i++) {
		[(NSTextInputContext *)context handleEvent:[eventArray objectAtIndex:i]];
	}
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
