/*
 * NSTextInputContext.m — the key binding, the composition's owner, and the one active context.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE STANDARD KEY BINDING MOVED HERE FROM `NSResponder`, AND THAT MOVE IS THE WHOLE POINT.** A key arrives, the
 * context sends it to the input source, and — when the source declines — what is left is the mapping a US keyboard
 * needs: a function key or a control character becomes the command it names, and anything else printable becomes
 * `-insertText:` on the CLIENT. The client is what the responder used to be, so the behavior is unchanged; what
 * changed is that an input method now has a door to stand in front of it — and the tier SHIPS one, `AGInputMethod`,
 * whose dead-key table consumes an accent and the letter after it.
 */
#import <AppKit/NSTextInputContext.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSEvent.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>
#include <stdlib.h>
#include "AppKitRefusal.h"
#include <xkbcommon/xkbcommon.h>

/* **THE ONE ACTIVE CONTEXT, SET BY `-activate:` AND CLEARED BY `-deactivate`.** A fresh process has none. */
static NSTextInputContext *fn_currentInputContext = nil;

/* **AND THE SENTINEL THAT MEANS "NO LOCALE RESTRICTION"** — see the header: the value is the era's spelling, and a caller
 * compares against the SYMBOL. */
NSString *const NSAllowsAnyInputSource = @"@";

/* ============================================================================================ *
 * THE KEYBOARD LAYOUTS, WHICH ARE THIS TIER'S INPUT SOURCES.                                     *
 * ============================================================================================ */
/* **A LAYOUT IS OFFERED WHEN THE MACHINE CAN BUILD ITS KEYMAP, WHICH IS A MEASUREMENT RATHER THAN A TABLE READ.**
 * xkbcommon compiles a keymap from the installed XKB data; a distribution that ships no German layout fails that compile,
 * and the source is then not offered. The table below is therefore a list of CANDIDATES: what a caller receives is the
 * subset this machine can honour, each with the locale it belongs to (the filter `-allowedInputSourceLocales` uses) and
 * the name a menu shows.
 *
 * NINE IS THE ERA'S SHAPE RATHER THAN A LIMIT: the common Latin layouts a US/European install has plus Russian and
 * Japanese, and a caller that wants another writes its identifier — `+setSelectedKeyboardInputSource:` accepts any layout
 * this machine can build, not only the nine. */
typedef struct {
	const char *identifier;
	const char *locale;
	const char *localizedName;
} FNXKBLayout;

static const FNXKBLayout fn_layouts[] = {
	{ "us", "en_US", "U.S." },
	{ "gb", "en_GB", "British" },
	{ "de", "de_DE", "German" },
	{ "fr", "fr_FR", "French" },
	{ "es", "es_ES", "Spanish" },
	{ "it", "it_IT", "Italian" },
	{ "se", "sv_SE", "Swedish" },
	{ "ru", "ru_RU", "Russian" },
	{ "jp", "ja_JP", "Japanese" }
};
#define FN_LAYOUT_COUNT ((NSInteger)(sizeof(fn_layouts) / sizeof(fn_layouts[0])))

/* THE ONE MEASUREMENT: does the installed XKB data build this layout? Each attempt makes and frees its own context, which
 * is slower than reusing one but keeps this function free of shared state — it is called once per candidate and the
 * answer is cached by the caller below. */
static BOOL fn_layout_builds(const char *layout)
{
	struct xkb_context *context;
	struct xkb_keymap *keymap;
	struct xkb_rule_names names;
	BOOL builds;

	if (layout == NULL) {
		return NO;
	}
	context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (context == NULL) {
		return NO;
	}
	names.rules = NULL;
	names.model = NULL;
	names.layout = layout;
	names.variant = NULL;
	names.options = NULL;
	keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
	builds = (keymap != NULL) ? YES : NO;
	if (keymap != NULL) {
		xkb_keymap_unref(keymap);
	}
	xkb_context_unref(context);
	return builds;
}

/* AND THE LOCALE A LAYOUT BELONGS TO, for the filter: an identifier the table knows answers its locale, and one it does not
 * answers the identifier itself (which is what "de_CH" would be — a locale, matched by its language prefix). */
static NSString *fn_locale_for_layout(NSString *identifier)
{
	NSInteger i;

	for (i = 0; i < FN_LAYOUT_COUNT; i++) {
		if ([identifier isEqualToString:[NSString stringWithUTF8String:fn_layouts[i].identifier]]) {
			return [NSString stringWithUTF8String:fn_layouts[i].locale];
		}
	}
	return identifier;
}

/* THE SELECTED LAYOUT, CLASS-WIDE. Nil until the first ask, which is how the environment's `XKB_DEFAULT_LAYOUT` gets a
 * chance to be the default without this file reading the environment in an initialiser. */
static NSString *fn_selectedLayout = nil;

@implementation NSTextInputContext

+ (NSTextInputContext *)currentInputContext
{
	return fn_currentInputContext;
}

- (instancetype)initWithClient:(id <NSTextInput>)client
{
	self = [super init];
	if (self != nil) {
		_client = client;	/* borrowed */
	}
	return self;
}

- (id <NSTextInput>)client
{
	return _client;
}

- (void)dealloc
{
	[_inputSource release];
	[super dealloc];
}

/* **AND THE SOURCE, WHICH IS RETAINED.** A context with none does the standard key binding directly, which is what a
 * stock keyboard is; one with a source sends every key to it first. */
- (void)setInputSource:(id <NSTextInputSource>)source
{
	if (source != _inputSource) {
		id held = [source retain];

		[_inputSource release];
		_inputSource = held;
	}
}

- (id <NSTextInputSource>)inputSource
{
	return _inputSource;
}

/* **THE KEY, MAPPED.** This is the direct binding the responder used to do, and the only reason it is here rather
 * than there is that an input method belongs BETWEEN the two — a source that composes would consume the event first
 * and call the client's marked-text doors, and only what it declined would reach this mapping.
 *
 * **AND PAGING IS MAPPED NOW, WHICH IT WAS NOT.** The old comment here said "a page is a viewport's height and this
 * tier has no viewport" — true when the text view was one line, false since the clip view and the wrapped document
 * arrived. Page Up/Down name `-pageUp:`/`-pageDown:`, Option with them extends the selection, and the view that
 * answers them is `NSTextView` (`NSTextView.m`, the paging block). A responder with no viewport has no answer, which
 * is what the chain is for.
 *
 * **WHAT IS DELIBERATELY NOT MAPPED HERE IS EVERY COMMAND-MODIFIED KEY.** Command-A and Command-C are key EQUIVALENTS
 * — the menu bar's business, resolved by `NSApplication` before a key ever reaches a text view — so inventing them
 * here would give a window two different answers to one keystroke. */
- (void)handleEvent:(NSEvent *)event
{
	NSString *chars;
	NSUInteger flags;
	BOOL shift;
	BOOL alt;
	unichar c;
	SEL command = NULL;

	if (_client == nil || event == nil || [event type] != NSKeyDown) {
		return;
	}
	/* **AND THE INPUT SOURCE SEES IT FIRST.** A source that consumes the event — composing through the client — ends
	 * the call; what it DECLINES falls through to the mapping below. */
	if (_inputSource != nil && [_inputSource handleEvent:event context:self]) {
		return;
	}
	chars = [event characters];
	if ([chars length] == 0) {
		return;
	}
	flags = [event modifierFlags];
	/* A COMMAND MODIFIER IS NOT READ. Command-A and Command-C are key EQUIVALENTS — the menu bar's business — and a
	 * window whose menu does not carry them should not have them invented by its text view. */
	if ((flags & NSCommandKeyMask) != 0) {
		return;
	}
	shift = ((flags & NSShiftKeyMask) != 0);
	alt = ((flags & NSAlternateKeyMask) != 0);
	c = [chars characterAtIndex:0];

	switch (c) {
	case NSUpArrowFunctionKey:
		/* **OPTION-UP AND OPTION-DOWN ARE THE PARAGRAPH'S**, which is the era's binding: a plain arrow moves by a
		 * line, and the modifier one goes to the paragraph's beginning or end. */
		if (alt) {
			command = shift ? @selector(moveToBeginningOfParagraphAndModifySelection:)
					: @selector(moveToBeginningOfParagraph:);
		} else {
			command = shift ? @selector(moveUpAndModifySelection:) : @selector(moveUp:);
		}
		break;
	case NSDownArrowFunctionKey:
		if (alt) {
			command = shift ? @selector(moveToEndOfParagraphAndModifySelection:)
					: @selector(moveToEndOfParagraph:);
		} else {
			command = shift ? @selector(moveDownAndModifySelection:) : @selector(moveDown:);
		}
		break;
	case NSPageUpFunctionKey:
		command = shift ? @selector(pageUpAndModifySelection:) : @selector(pageUp:);
		break;
	case NSPageDownFunctionKey:
		command = shift ? @selector(pageDownAndModifySelection:) : @selector(pageDown:);
		break;
	case NSLeftArrowFunctionKey:
		if (alt) {
			command = shift ? @selector(moveWordLeftAndModifySelection:) : @selector(moveWordLeft:);
		} else {
			command = shift ? @selector(moveLeftAndModifySelection:) : @selector(moveLeft:);
		}
		break;
	case NSRightArrowFunctionKey:
		if (alt) {
			command = shift ? @selector(moveWordRightAndModifySelection:) : @selector(moveWordRight:);
		} else {
			command = shift ? @selector(moveRightAndModifySelection:) : @selector(moveRight:);
		}
		break;
	case NSHomeFunctionKey:
		command = shift ? @selector(moveToBeginningOfLineAndModifySelection:) : @selector(moveToBeginningOfLine:);
		break;
	case NSEndFunctionKey:
		command = shift ? @selector(moveToEndOfLineAndModifySelection:) : @selector(moveToEndOfLine:);
		break;
	case NSDeleteFunctionKey:
		command = alt ? @selector(deleteWordForward:) : @selector(deleteForward:);
		break;
	case NSBackspaceCharacter:
	case NSDeleteCharacter:
		/* BOTH ARE BACKWARD DELETE, which is the keymap difference the constants record. */
		command = alt ? @selector(deleteWordBackward:) : @selector(deleteBackward:);
		break;
	case NSNewlineCharacter:
	case NSCarriageReturnCharacter:
	case NSEnterCharacter:
		command = @selector(insertNewline:);
		break;
	case NSTabCharacter:
		command = @selector(insertTab:);
		break;
	case NSBackTabCharacter:
		command = @selector(insertBacktab:);
		break;
	case 0x1B:	/* ESC — no constant of Apple's names it, so the code point stands with this note */
		command = @selector(cancelOperation:);
		break;
	default:
		break;
	}
	if (command != NULL) {
		[_client doCommandBySelector:command];
	} else if (c >= 0x20 && c != NSDeleteCharacter) {
		[_client insertText:chars];
	}
}

/* **AND THE COMPOSITION, TAKEN BACK THROUGH THE CLIENT.** The context is what owns the composition across keystrokes,
 * so it is the object a caller tells when the person abandons one — and the client is what actually holds the marked
 * text. */
- (void)discardMarkedText
{
	if (_inputSource != nil && [_inputSource respondsToSelector:@selector(discardComposition)]) {
		[_inputSource discardComposition];
	}
	if (_client != nil) {
		[_client unmarkText];
	}
}

/* THE CARET'S RECTANGLE HAS MOVED, WHICH IS WHAT A CANDIDATE WINDOW IS PLACED AT: the source that owns one is told
 * here, and a source with none answers nothing. */
- (void)invalidateCharacterCoordinates
{
	if (_inputSource != nil && [_inputSource respondsToSelector:@selector(invalidateCharacterCoordinates)]) {
		[_inputSource invalidateCharacterCoordinates];
	}
}

/* ---- AND THE EIGHT THE SWEEP ADDS ------------------------------------------------------------- */

/* **THE BUILDABLE LAYOUTS, IN THE ORDER A CALLER SHOULD SEE THEM.** Built once (the XKB data does not change under a
 * process) and ordered with the SELECTED one first: that is the selection's reader — a caller that takes the first source
 * gets the one that was chosen, and a menu built from this array leads with it. */
+ (NSArray *)keyboardInputSources
{
	static NSArray *sBuildable = nil;
	NSMutableArray *ordered;
	NSString *selected;
	NSInteger i;

	if (sBuildable == nil) {
		NSMutableArray *found = [NSMutableArray array];

		for (i = 0; i < FN_LAYOUT_COUNT; i++) {
			if (fn_layout_builds(fn_layouts[i].identifier)) {
				[found addObject:[NSString stringWithUTF8String:fn_layouts[i].identifier]];
			}
		}
		sBuildable = [found copy];
	}
	selected = [self selectedKeyboardInputSource];
	ordered = [NSMutableArray arrayWithCapacity:[sBuildable count]];
	if (selected != nil && [sBuildable containsObject:selected]) {
		[ordered addObject:selected];
	}
	for (i = 0; i < (NSInteger)[sBuildable count]; i++) {
		NSString *identifier = [sBuildable objectAtIndex:(NSUInteger)i];

		if (![identifier isEqualToString:selected]) {
			[ordered addObject:identifier];
		}
	}
	return ordered;
}

/* **THE SELECTION DEFAULTS TO THE ENVIRONMENT'S LAYOUT AND THEN TO THE FIRST BUILDABLE ONE.** `XKB_DEFAULT_LAYOUT` is the
 * same variable the keyboard layer reads for its keymap, so a session that started with `XKB_DEFAULT_LAYOUT=de` has a
 * selected input source that agrees with the keyboard it is typing on. A layout the environment names but this machine
 * cannot build is ignored rather than selected-and-broken. */
+ (NSString *)selectedKeyboardInputSource
{
	const char *fromEnvironment;

	if (fn_selectedLayout != nil) {
		return fn_selectedLayout;
	}
	fromEnvironment = getenv("XKB_DEFAULT_LAYOUT");
	if (fromEnvironment != NULL && fn_layout_builds(fromEnvironment)) {
		fn_selectedLayout = [[NSString stringWithUTF8String:fromEnvironment] retain];
		return fn_selectedLayout;
	}
	if (fn_layout_builds("us")) {
		fn_selectedLayout = [@"us" retain];
		return fn_selectedLayout;
	}
	{
		NSArray *buildable = [self keyboardInputSources];

		if ([buildable count] > 0) {
			fn_selectedLayout = [[buildable objectAtIndex:0] retain];
			return fn_selectedLayout;
		}
	}
	return nil;
}

/* **AND THE SETTER REFUSES A LAYOUT THIS MACHINE CANNOT BUILD, BY NAME.** Selecting one would leave the input source
 * pointing at a keymap nobody can compile; the caller is told which identifier was rejected and what it would have needed.
 * A nil identifier is the default rather than a refusal. */
+ (void)setSelectedKeyboardInputSource:(NSString *)identifier
{
	if (identifier == nil) {
		fn_selectedLayout = nil;
		return;
	}
	if (!fn_layout_builds([identifier UTF8String])) {
		fn_refuse_window("+[NSTextInputContext setSelectedKeyboardInputSource:]",
				 "a keyboard layout the installed XKB data can build (the identifier given names one this "
				 "machine has no keymap for)");
		return;
	}
	if (![identifier isEqualToString:fn_selectedLayout]) {
		[identifier retain];
		[fn_selectedLayout release];
		fn_selectedLayout = identifier;
	}
}

/* A NAME FOR A MENU. The table's answer for a layout it knows; the identifier itself for anything else, because a name
 * this file invented for "de_CH" would be a guess about a layout it has never looked at. */
+ (NSString *)localizedNameForInputSource:(NSString *)inputSourceIdentifier
{
	NSInteger i;

	if (inputSourceIdentifier == nil) {
		return @"";
	}
	for (i = 0; i < FN_LAYOUT_COUNT; i++) {
		if ([inputSourceIdentifier isEqualToString:[NSString stringWithUTF8String:fn_layouts[i].identifier]]) {
			return [NSString stringWithUTF8String:fn_layouts[i].localizedName];
		}
	}
	return inputSourceIdentifier;
}

/* THE TWO LIMITS, AND THE FIRST ONE'S READER IS THE LIST BELOW. */
- (BOOL)acceptsGlyphInfo
{
	return _acceptsGlyphInfo;
}

- (void)setAcceptsGlyphInfo:(BOOL)flag
{
	_acceptsGlyphInfo = flag ? YES : NO;
}

- (NSArray *)allowedInputSourceLocales
{
	/* **NIL AND THE SENTINEL BOTH MEAN "ANY"**, and a caller reading this door is handed the sentinel rather than nil —
	 * which is what makes the answer an ARRAY of locales either way, as Apple's is. */
	if (_allowedInputSourceLocales == nil) {
		return [NSArray arrayWithObject:NSAllowsAnyInputSource];
	}
	return _allowedInputSourceLocales;
}

- (void)setAllowedInputSourceLocales:(NSArray *)locales
{
	NSArray *copy = ([locales count] > 0) ? [locales copy] : nil;

	[_allowedInputSourceLocales release];
	_allowedInputSourceLocales = copy;
}

/* **ONE STOCK KEYBOARD WHEN NOTHING IS INSTALLED, AND THE INSTALLED METHOD WHEN ONE IS.** With no input method the list is
 * the KEYBOARD LAYOUTS this machine can build, narrowed by the context's locale list — so a context restricted to `de_DE`
 * offers German alone, and one that allows any locale offers them all with the selected layout first. */
- (NSArray *)textInputSources
{
	NSArray *buildable;
	NSArray *allowed;

	if (_inputSource != nil) {
		return [NSArray arrayWithObject:[_inputSource inputSourceIdentifier]];
	}
	buildable = [[self class] keyboardInputSources];
	allowed = [self allowedInputSourceLocales];
	if ([allowed containsObject:NSAllowsAnyInputSource]) {
		return buildable;
	}
	{
		NSMutableArray *matching = [NSMutableArray array];
		NSUInteger i;

		for (i = 0; i < [buildable count]; i++) {
			NSString *identifier = [buildable objectAtIndex:i];
			NSString *locale = fn_locale_for_layout(identifier);
			NSUInteger j;

			for (j = 0; j < [allowed count]; j++) {
				NSString *want = [allowed objectAtIndex:j];

				if ([locale isEqualToString:want] ||
				    [locale hasPrefix:[want stringByAppendingString:@"_"]]) {
					[matching addObject:identifier];
					break;
				}
			}
		}
		return matching;
	}
}

/* **AND THE SELECTED SOURCE IS THE IME WHEN ONE IS INSTALLED AND THE SELECTED LAYOUT WHEN NONE IS.** This used to answer
 * one placeholder ("AgoraKeyboard") for the single source the tier had; now that the layouts ARE the registry, the honest
 * answer for "which source am I typing with" is the selected layout — the same identifier `+selectedKeyboardInputSource`
 * names and the first entry `-textInputSources` lists. */
- (id)selectedInputSource
{
	if (_inputSource != nil) {
		return [_inputSource inputSourceIdentifier];
	}
	return [[self class] selectedKeyboardInputSource];
}

- (void)activate
{
	fn_currentInputContext = self;
	_active = YES;
}

- (void)deactivate
{
	if (fn_currentInputContext == self) {
		fn_currentInputContext = nil;
	}
	_active = NO;
}

- (BOOL)isActive
{
	return _active;
}

@end
