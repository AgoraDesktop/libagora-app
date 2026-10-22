/*
 * NSTextInputContext.h — THE OBJECT BETWEEN A KEY AND A TEXT VIEW, AND WHERE A COMPOSITION LIVES.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **APPLE'S OWN SENTENCE FOR THIS CLASS IS "an object that represents the input context for a text view", AND THE
 * CONTEXT IS WHERE KEY EVENTS GO BEFORE THE TEXT VIEW SEES THEM.** `NSResponder -interpretKeyEvents:` hands each key
 * to `[[self inputContext] handleEvent:]`; the context sends it to the input source (a keyboard layout, an input
 * method, a dead-key table), which composes text by calling the `NSTextInput` doors on its CLIENT — the text view —
 * and, WHEN NO INPUT SOURCE CONSUMES THE EVENT, falls back to the STANDARD KEY BINDING: a command selector for the
 * key, or `-insertText:` for a printable character. So the direct mapping every text surface needs lives HERE, one
 * step away from the responder, and an input method slots in between without the responder changing.
 *
 * **AND THIS TIER'S HONEST SHAPE IS THAT THE SOURCE IS OPTIONAL.** `-textInputSources` answers the one source a stock
 * keyboard has and `-selectedInputSource` names it; a caller installs a COMPOSING source with `-setInputSource:`, and
 * then `-handleEvent:` sends each key to it FIRST — the source composes through the client's marked-text doors and
 * answers whether it consumed the event, and only what it DECLINES reaches the standard key binding below. THE TIER
 * SHIPS TWO SUCH SOURCES: `AGInputMethod`, a dead-key table that composes an accent with the next letter, and
 * `AGVariantsInputMethod`, which offers a letter's readings in an `AGCandidateWindow` — the candidate list, placed at
 * the caret the client reports and moved by `-invalidateCharacterCoordinates`.
 */
#ifndef APPKIT_NSTEXTINPUTCONTEXT_H
#define APPKIT_NSTEXTINPUTCONTEXT_H

#import <Foundation/Foundation.h>

@class NSEvent;
@class NSTextInputContext;
@protocol NSTextInput;

NS_ASSUME_NONNULL_BEGIN

/* **THE DOOR AN INPUT METHOD IS INSERTED AT.** A source is handed each key and answers whether it CONSUMED it: YES
 * means it composed through the client's `NSTextInput` doors — marked text, an insertion, a command — and the context
 * must not fall back; NO means the context's standard key binding runs. That is the whole contract, and it is why the
 * mapping could move out of the responder: the source stands between the key and it. */
@protocol NSTextInputSource <NSObject>
- (NSString *)inputSourceIdentifier;
- (BOOL)handleEvent:(NSEvent *)event context:(NSTextInputContext *)context;

@optional
/* **AND WHEN THE COMPOSITION IS TAKEN AWAY OUTSIDE THE SOURCE.** The context's `-discardMarkedText` clears the client's
 * marked text itself; a source that holds state across keystrokes clears it here, so it does not compose with the NEXT
 * key into a composition that is already gone. */
- (void)discardComposition;
/* **AND WHEN THE CARET MOVED.** A source with a candidate window re-places it here; the context calls this from
 * `-invalidateCharacterCoordinates`. */
- (void)invalidateCharacterCoordinates;
@end

/* **THE SENTINEL THAT MEANS "NO LOCALE RESTRICTION".** Apple declares it beside this class and compares against the
 * SYMBOL rather than its value; the value is `"@"`, its spelling in the era's header. A caller that wants every source
 * writes `NSAllowsAnyInputSource` and never the literal — which is what makes the constant worth declaring even where the
 * value matters to nobody. */
extern NSString *const NSAllowsAnyInputSource;

@interface NSTextInputContext : NSObject
{
	/* **AND THE CLIENT IS BORROWED**, like every back-pointer in this tree: the client (a text view) owns its context,
	 * so a context that retained the client would keep a view alive from the object it is drawing for. */
	id <NSTextInput> _client;	/* NOT RETAINED */
	id <NSTextInputSource> _inputSource;	/* RETAINED; nil means the stock keyboard */
	BOOL _active;
	/* **AND THE SWEEP'S TWO PIECES OF CONTEXT STATE.** `_acceptsGlyphInfo` is the input method contract's flag (recorded;
	 * this tier's keyboard source sends no glyph info, so nothing here consults it and the header says so).
	 * `_allowedInputSourceLocales` is the list a caller narrows the OFFERED sources to, and its reader is
	 * `-textInputSources`: a context restricted to `de_DE` offers the German layout rather than every layout. */
	BOOL _acceptsGlyphInfo;
	NSArray *_allowedInputSourceLocales;	/* RETAINED; nil means "any", which is `NSAllowsAnyInputSource` */
}

/* **THE ONE ACTIVE CONTEXT.** Apple's door, and it is set by `-activate` and cleared by `-deactivate`; a fresh process
 * has none, which is what `nil` says. */
+ (nullable NSTextInputContext *)currentInputContext;

- (instancetype)initWithClient:(id <NSTextInput>)client;
- (id <NSTextInput>)client;

/* **THE DOOR A KEY COMES IN THROUGH.** It sends the event to the input source; with none, it does the standard key
 * binding on the client — the command for the key, or `-insertText:` for a printable character. */
- (void)handleEvent:(NSEvent *)event;

/* **AND THE SOURCE KEYS ARE SENT TO FIRST.** A caller installs a composing input method; with none — the default —
 * `-handleEvent:` does the standard key binding directly, which is exactly what a stock keyboard is. The context
 * RETAINS the source, because it is a value the caller hands over. */
- (void)setInputSource:(nullable id <NSTextInputSource>)source;
- (nullable id <NSTextInputSource>)inputSource;

/* **AND THE COMPOSITION, WHICH IS THE PART THIS TIER CAN ACT ON.** A context that is told to discard its marked text
 * takes the composition back through the client, and tells a source that holds composition state so it can clear it;
 * `-invalidateCharacterCoordinates` says the caret's rectangle — what a candidate window is placed at — has moved,
 * which is a fact with no window to move here. */
- (void)discardMarkedText;
- (void)invalidateCharacterCoordinates;

/* **THE SOURCES A CALLER CAN PICK FROM.** With no input method installed that is the one stock keyboard; with one it is
 * that method, and `-selectedInputSource` names it. A caller listing sources gets the truth rather than an empty array
 * pretending there is no keyboard. */
- (NSArray *)textInputSources;
- (nullable id)selectedInputSource;

/* ============================================================================================ *
 * AND THE EIGHT THE SWEEP ADDS: THE KEYBOARD'S INPUT SOURCES, AND THE CONTEXT'S TWO LIMITS.       *
 * ============================================================================================ */
/* **A KEYBOARD LAYOUT IS AN INPUT SOURCE, AND THE LIST IS MEASURED RATHER THAN DECLARED.** Apple's input-source registry
 * is a system service; this layer has xkbcommon and the machine's XKB data, so `+keyboardInputSources` answers the layout
 * identifiers THIS MACHINE CAN ACTUALLY BUILD A KEYMAP FOR — each candidate is compiled once and dropped when it does not
 * build. A distribution without a layout's data therefore does not offer it, which is the difference between a list of
 * promises and a list of facts.
 *
 * THE SELECTED ONE IS A CLASS-WIDE SETTING (Apple's, and a session has one keyboard), it is validated against the same
 * buildable list, and its READER is the ORDER of the list: the selected layout comes FIRST, so a caller that takes the
 * first source gets the one that was chosen. `+localizedNameForInputSource:` names a layout for a menu, and a layout this
 * table has never heard of answers its own identifier rather than a made-up name. */
+ (NSArray *)keyboardInputSources;
+ (nullable NSString *)selectedKeyboardInputSource;
+ (void)setSelectedKeyboardInputSource:(nullable NSString *)identifier;
+ (NSString *)localizedNameForInputSource:(NSString *)inputSourceIdentifier;

/* **AND THE TWO LIMITS A CONTEXT PUTS ON ITS SOURCES.** `-allowedInputSourceLocales` is a list of locale identifiers
 * (`de_DE`, `fr`, …) a caller narrows the offered sources to, with `NSAllowsAnyInputSource` as the default and the
 * meaning of "no restriction"; `-setAllowedInputSourceLocales:` takes that sentinel or a list. `-acceptsGlyphInfo` is
 * the input-method contract's flag: recorded here, and stated to be UNREAD, because the one source this tier ships is a
 * keyboard and a keyboard sends no glyph info — the door exists for the input method written against it. */
- (NSArray *)allowedInputSourceLocales;
- (void)setAllowedInputSourceLocales:(nullable NSArray *)locales;
- (BOOL)acceptsGlyphInfo;
- (void)setAcceptsGlyphInfo:(BOOL)flag;

- (void)activate;
- (void)deactivate;
- (BOOL)isActive;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTINPUTCONTEXT_H */
