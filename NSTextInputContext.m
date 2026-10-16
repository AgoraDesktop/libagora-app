/*
 * NSTextInputContext.m — the key binding, the composition's owner, and the one active context.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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

/* **THE ONE ACTIVE CONTEXT, SET BY `-activate:` AND CLEARED BY `-deactivate`.** A fresh process has none. */
static NSTextInputContext *fn_currentInputContext = nil;

/* THE ONE SOURCE THIS TIER HAS, named so a caller listing sources is told there IS a keyboard rather than nothing. */
static NSString *const FNInputSourceIdentifier = @"AgoraKeyboard";

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
 * and call the client's marked-text doors, and only what it declined would reach this mapping. */
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
		command = shift ? @selector(moveUpAndModifySelection:) : @selector(moveUp:);
		break;
	case NSDownArrowFunctionKey:
		command = shift ? @selector(moveDownAndModifySelection:) : @selector(moveDown:);
		break;
	case NSPageUpFunctionKey:
	case NSPageDownFunctionKey:
		/* NO PAGE MOVEMENT: a page is a viewport's height and this tier has no viewport — a clip view and its
		 * document height are a later slice, named rather than faked onto a line. */
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

/* THE CARET'S RECTANGLE HAS MOVED, WHICH IS WHAT A CANDIDATE WINDOW IS PLACED AT. There is no candidate window in
 * this tier, so there is nothing to move; the door exists because a caller that moves the caret calls it, and the
 * answer — "noted, nothing to do" — is the truthful one. */
- (void)invalidateCharacterCoordinates
{
}

/* ONE STOCK KEYBOARD WHEN NOTHING IS INSTALLED, AND THE INSTALLED METHOD WHEN ONE IS. */
- (NSArray *)textInputSources
{
	if (_inputSource != nil) {
		return [NSArray arrayWithObject:[_inputSource inputSourceIdentifier]];
	}
	return [NSArray arrayWithObject:FNInputSourceIdentifier];
}

- (id)selectedInputSource
{
	if (_inputSource != nil) {
		return [_inputSource inputSourceIdentifier];
	}
	return FNInputSourceIdentifier;
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
