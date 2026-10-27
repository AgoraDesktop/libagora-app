/*
 * AGInputMethod.m — the dead-key table, and the state it keeps between two keystrokes.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A DEAD KEY IS A COMPOSITION WITH ONE READING.** The first keystroke puts the accent in the store AS MARKED TEXT, so
 * the person sees it waiting and the caret sits after it; the second either REPLACES that mark with one composed
 * character (`NSTextView -insertText:` targets the marked range) or, when nothing composes, CONFIRMS the accent as a
 * literal and lets the standard key binding have the key. There is no candidate list because a dead key has nothing to
 * choose between — the table below is the whole vocabulary, and it is the Latin-1 accented set rather than an
 * invention.
 *
 * **AND THE KEY IS RECOGNISED BY ITS KEYSYM, WHICH IS THE ONLY THING THAT CAN NAME IT.** A dead key types NOTHING —
 * xkbcommon writes no bytes for `XKB_KEY_dead_acute` — so `NSEvent -characters` cannot say which accent it was or even
 * that it was one. `-cg_keysym` can and does, and it is what the keymap has always known: the accent that waits is the
 * spacing clone the keysym STANDS FOR (`0x00B4` for `dead_acute`), never a character the key emitted. The
 * characters-only reading is kept for an event with no keysym at all — a fabricated one — and it must not be used for a
 * real key: on a US keyboard `` ` `` is `XKB_KEY_grave` and types a character, so a view that took it for a dead accent
 * would make "`e" untypable.
 */
#import <AppKit/AGInputMethod.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSEvent.h>
#import <Foundation/NSString.h>

#include <xkbcommon/xkbcommon-keysyms.h>	/* XKB_KEY_dead_… — the layout's own name for a dead key */

/* **A DEAD KEY IS A KEYMAP FACT, SO IT IS READ FROM THE KEYMAP.** xkbcommon answers NO TEXT AT ALL for a dead key —
 * `xkb_state_key_get_utf8` on `XKB_KEY_dead_acute` writes zero bytes — so the only thing that distinguishes it from a
 * key the layout does not define is the SYMBOL the map gives it, and `NSEvent -cg_keysym` is where that symbol arrives
 * (the seam has carried it in `AGEvent.keysym` all along; AppKit used it to name the `0xF700` keys and dropped it for
 * every key that typed something). This table is the accents `fn_accents` below can compose, each named by the spacing
 * clone it is SHOWN as while it waits.
 *
 * **AND THE ASCII CHARACTERS ARE NOT IN IT, WHICH IS A FIX RATHER THAN AN OMISSION.** `fn_is_dead_key_clone` still
 * accepts `` ` `` and `^` — they are the spacing clones of `dead_grave` and `dead_circumflex` — but a US keyboard's
 * `` ` `` key is `XKB_KEY_grave`, an ORDINARY key, and a person typing "`e" must get "`e". Only a keymap that
 * really says `dead_grave` begins a composition, which is exactly the distinction this table can make and a
 * characters-only reading cannot. */
static unichar fn_dead_key_clone(unsigned int keysym)
{
	switch (keysym) {
	case XKB_KEY_dead_acute:	return 0x00B4;	/* ACUTE ACCENT */
	case XKB_KEY_dead_grave:	return 0x0060;	/* GRAVE ACCENT */
	case XKB_KEY_dead_circumflex:	return 0x005E;	/* CIRCUMFLEX ACCENT */
	case XKB_KEY_dead_tilde:	return 0x007E;	/* TILDE */
	case XKB_KEY_dead_diaeresis:	return 0x00A8;	/* DIAERESIS */
	case XKB_KEY_dead_cedilla:	return 0x00B8;	/* CEDILLA */
	default:			return 0;
	}
}

/* **THE SPACING CLONES, FOR AN EVENT THAT CARRIES NO KEYMAP AT ALL.** A fabricated event — every test that makes one with
 * `+keyEventWithType:` — has no keysym, and the same characters are the only evidence it offers of which accent it
 * meant. Kept because that is what such a caller can express, and confined to `keysym == 0` because the honest answer
 * for a REAL key is `fn_dead_key_clone` above: a layout that types `` ` `` from a key whose symbol is `grave` is not
 * dead, and this function would say it was. */
static BOOL fn_is_dead_key_clone(unichar c)
{
	switch (c) {
	case 0x00B4:	/* ACUTE ACCENT */
	case 0x0060:	/* GRAVE ACCENT */
	case 0x005E:	/* CIRCUMFLEX ACCENT */
	case 0x007E:	/* TILDE */
	case 0x00A8:	/* DIAERESIS */
	case 0x00B8:	/* CEDILLA */
		return YES;
	default:
		return NO;
	}
}

/* **AND THE TABLE: an accent, a letter, and what the two make.** */
typedef struct {
	unichar accent;
	unichar base;
	unichar composed;
} FNAccent;

static const FNAccent fn_accents[] = {
	{0x00B4, 'a', 0x00E1}, {0x00B4, 'e', 0x00E9}, {0x00B4, 'i', 0x00ED},
	{0x00B4, 'o', 0x00F3}, {0x00B4, 'u', 0x00FA}, {0x00B4, 'y', 0x00FD},
	{0x00B4, 'A', 0x00C1}, {0x00B4, 'E', 0x00C9}, {0x00B4, 'I', 0x00CD},
	{0x00B4, 'O', 0x00D3}, {0x00B4, 'U', 0x00DA}, {0x00B4, 'Y', 0x00DD},
	{0x00B4, 'c', 0x0107}, {0x00B4, 'C', 0x0106}, {0x00B4, 'n', 0x0144},
	{0x00B4, 'N', 0x0143}, {0x00B4, 's', 0x015B}, {0x00B4, 'S', 0x015A},
	{0x00B4, 'z', 0x017A}, {0x00B4, 'Z', 0x0179},
	{0x0060, 'a', 0x00E0}, {0x0060, 'e', 0x00E8}, {0x0060, 'i', 0x00EC},
	{0x0060, 'o', 0x00F2}, {0x0060, 'u', 0x00F9},
	{0x0060, 'A', 0x00C0}, {0x0060, 'E', 0x00C8}, {0x0060, 'I', 0x00CC},
	{0x0060, 'O', 0x00D2}, {0x0060, 'U', 0x00D9},
	{0x005E, 'a', 0x00E2}, {0x005E, 'e', 0x00EA}, {0x005E, 'i', 0x00EE},
	{0x005E, 'o', 0x00F4}, {0x005E, 'u', 0x00FB},
	{0x005E, 'A', 0x00C2}, {0x005E, 'E', 0x00CA}, {0x005E, 'I', 0x00CE},
	{0x005E, 'O', 0x00D4}, {0x005E, 'U', 0x00DB},
	{0x007E, 'a', 0x00E3}, {0x007E, 'n', 0x00F1}, {0x007E, 'o', 0x00F5},
	{0x007E, 'A', 0x00C3}, {0x007E, 'N', 0x00D1}, {0x007E, 'O', 0x00D5},
	{0x00A8, 'a', 0x00E4}, {0x00A8, 'e', 0x00EB}, {0x00A8, 'i', 0x00EF},
	{0x00A8, 'o', 0x00F6}, {0x00A8, 'u', 0x00FC}, {0x00A8, 'y', 0x00FF},
	{0x00A8, 'A', 0x00C4}, {0x00A8, 'E', 0x00CB}, {0x00A8, 'I', 0x00CF},
	{0x00A8, 'O', 0x00D6}, {0x00A8, 'U', 0x00DC}, {0x00A8, 'Y', 0x0178},
	/* THE CEDILLA, WHICH xkbcommon ALSO SPELLS AS A DEAD KEY (`XKB_KEY_dead_cedilla`, on the layouts that have one),
	 * so the table has to answer for it or pressing it would insert a bare accent and lose the letter. `ç`/`Ç` are
	 * Latin-1 and `ş`/`Ş` are the Turkish pair that shares the accent. */
	{0x00B8, 'c', 0x00E7}, {0x00B8, 'C', 0x00C7},
	{0x00B8, 's', 0x015F}, {0x00B8, 'S', 0x015E}
};

static unichar fn_compose(unichar accent, unichar base)
{
	NSUInteger i, count = sizeof(fn_accents) / sizeof(fn_accents[0]);

	for (i = 0; i < count; i++) {
		if (fn_accents[i].accent == accent && fn_accents[i].base == base) {
			return fn_accents[i].composed;
		}
	}
	return 0;
}

@implementation AGInputMethod

- (NSString *)inputSourceIdentifier
{
	return @"AgoraInputMethod";
}

- (BOOL)isComposing
{
	return _pending != 0;
}

- (unichar)pendingDeadKey
{
	return _pending;
}

/* **THE SOURCE'S OWN HALF OF A DISCARD.** The context clears the client's marked text; this forgets the accent, so the
 * next key does not compose into a composition that is already gone. */
- (void)discardComposition
{
	_pending = 0;
}

- (BOOL)handleEvent:(NSEvent *)event context:(NSTextInputContext *)context
{
	id <NSTextInput> client = [context client];
	NSString *chars;
	unsigned int keysym;
	unichar c = 0;
	unichar dead = 0;

	if (client == nil || event == nil || [event type] != NSKeyDown) {
		return NO;
	}
	/* A COMMAND OR CONTROL KEY IS THE MENU BAR'S, not this method's. */
	if (([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask)) != 0) {
		return NO;
	}
	chars = [event characters];
	if ([chars length] == 1) {
		c = [chars characterAtIndex:0];
	}
	/* ESCAPE TAKES AN UN-COMPOSED DEAD KEY BACK, which is what a person expects of a composition. */
	if (c == 0x1B) {
		if (_pending != 0) {
			_pending = 0;
			[client setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
			return YES;
		}
		return NO;
	}
	/* **WHICH KEY THIS WAS, ASKED OF THE KEYMAP FIRST AND OF THE CHARACTER ONLY WHEN THERE IS NO KEYMAP.** A dead key
	 * types nothing, so `-characters` cannot name it; `-cg_keysym` is the map's own name for the key and is the answer
	 * for real hardware. A fabricated event has no keysym at all, and for that case — and only that case — the spacing
	 * clone in `-characters` stands in, because it is the only evidence such a caller can offer. THE ORDER MATTERS:
	 * with a keysym present, a `` ` `` that the map calls `grave` is an ORDINARY key, and a text view that treated it
	 * as a dead `grave` accent would make "`e" untypable on a US keyboard. */
	keysym = [event cg_keysym];
	if (keysym != 0) {
		dead = fn_dead_key_clone(keysym);
	} else if (c != 0 && fn_is_dead_key_clone(c)) {
		dead = c;
	}
	if (dead != 0) {
		/* **A DEAD KEY WHILE ONE IS WAITING CONFIRMS THE OLD ONE AND BEGINS A NEW COMPOSITION.** The accent that was
		 * waiting had no letter to combine with — this key is not one — so it stands alone as a literal, and the
		 * person's second accent is what now waits. The alternative readings both lose a keystroke: composing the two
		 * accents with each other is not a thing, and dropping the first is a key the person pressed going missing. */
		if (_pending != 0) {
			NSString *accent = [NSString stringWithFormat:@"%C", _pending];

			_pending = 0;
			[client insertText:accent];
		}
		_pending = dead;
		[client setMarkedText:[NSString stringWithFormat:@"%C", dead] selectedRange:NSMakeRange(1, 0)];
		return YES;
	}
	if (_pending == 0) {
		return NO;
	}
	/* **A KEY THAT IS NOT A CHARACTER LEAVES THE COMPOSITION ALONE.** An arrow while an accent waits is the caret's
	 * business, and ending the composition for it would silently commit an accent the person did not ask for. */
	if (c == 0) {
		return NO;
	}
	/* **THE SECOND KEYSTROKE EITHER COMBINES — which CONFIRMS by replacing the marked accent — or does not, and then
	 * the accent stands alone and THIS key is left to the standard key binding.** */
	{
		unichar composed = fn_compose(_pending, c);

		if (composed != 0) {
			_pending = 0;
			[client insertText:[NSString stringWithFormat:@"%C", composed]];
			return YES;
		}
	}
	{
		NSString *accent = [NSString stringWithFormat:@"%C", _pending];

		_pending = 0;
		[client insertText:accent];
	}
	return NO;
}

@end
