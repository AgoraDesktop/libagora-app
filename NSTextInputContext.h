/*
 * NSTextInputContext.h — THE OBJECT BETWEEN A KEY AND A TEXT VIEW, AND WHERE A COMPOSITION LIVES.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **APPLE'S OWN SENTENCE FOR THIS CLASS IS "an object that represents the input context for a text view", AND THE
 * CONTEXT IS WHERE KEY EVENTS GO BEFORE THE TEXT VIEW SEES THEM.** `NSResponder -interpretKeyEvents:` hands each key
 * to `[[self inputContext] handleEvent:]`; the context sends it to the input source (a keyboard layout, an input
 * method, a dead-key table), which composes text by calling the `NSTextInput` doors on its CLIENT — the text view —
 * and, WHEN NO INPUT SOURCE CONSUMES THE EVENT, falls back to the STANDARD KEY BINDING: a command selector for the
 * key, or `-insertText:` for a printable character. So the direct mapping every text surface needs lives HERE, one
 * step away from the responder, and an input method slots in between without the responder changing.
 *
 * **AND THIS TIER'S HONEST SHAPE IS THAT THERE IS NO INPUT SOURCE.** `-textInputSources` answers the one source a
 * stock keyboard has and `-selectedInputSource` names it, but there is no keymap to translate through and no
 * composition engine, so `-handleEvent:` goes STRAIGHT to the key-binding fallback — which is exactly what a context
 * with a dead-key-less source does. WHAT THE CONTEXT REALLY OWNS, and what has a reader here, is the MARKED-TEXT
 * half: `-discardMarkedText` takes a composition back through its client's `-unmarkText`, and `+currentInputContext`
 * is the active one. A real input method is a class this tier does not have; the DOOR it would be inserted at is
 * this one.
 */
#ifndef APPKIT_NSTEXTINPUTCONTEXT_H
#define APPKIT_NSTEXTINPUTCONTEXT_H

#import <Foundation/Foundation.h>

@class NSEvent;
@protocol NSTextInput;

NS_ASSUME_NONNULL_BEGIN

@interface NSTextInputContext : NSObject
{
	/* **AND THE CLIENT IS BORROWED**, like every back-pointer in this tree: the client (a text view) owns its context,
	 * so a context that retained the client would keep a view alive from the object it is drawing for. */
	id <NSTextInput> _client;	/* NOT RETAINED */
	BOOL _active;
}

/* **THE ONE ACTIVE CONTEXT.** Apple's door, and it is set by `-activate` and cleared by `-deactivate`; a fresh process
 * has none, which is what `nil` says. */
+ (nullable NSTextInputContext *)currentInputContext;

- (instancetype)initWithClient:(id <NSTextInput>)client;
- (id <NSTextInput>)client;

/* **THE DOOR A KEY COMES IN THROUGH.** It sends the event to the input source; with none, it does the standard key
 * binding on the client — the command for the key, or `-insertText:` for a printable character. */
- (void)handleEvent:(NSEvent *)event;

/* **AND THE COMPOSITION, WHICH IS THE PART THIS TIER CAN ACT ON.** A context that is told to discard its marked text
 * takes the composition back through the client; `-invalidateCharacterCoordinates` says the caret's rectangle — what a
 * candidate window is placed at — has moved, which is a fact with no window to move here. */
- (void)discardMarkedText;
- (void)invalidateCharacterCoordinates;

/* THE INPUT SOURCES, WHICH IN THIS TIER IS ONE STOCK KEYBOARD and no composition: an array of one identifier and that
 * identifier as the selected one. A caller listing sources gets the truth rather than an empty array pretending there
 * is no keyboard. */
- (NSArray *)textInputSources;
- (nullable id)selectedInputSource;

- (void)activate;
- (void)deactivate;
- (BOOL)isActive;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTINPUTCONTEXT_H */
