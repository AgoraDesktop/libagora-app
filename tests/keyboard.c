/*
 * keyboard — evdev codes and a keymap, turned into text, with no compositor anywhere.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHY THIS IS A TEST AND NOT A SMOKE RUN. Input cannot be exercised end to end here — a headless seat
 * advertises no keyboard, and typing into a nested compositor from a script is not reproducible — so the
 * part that CAN be measured is measured: a known keymap, fed the same way a compositor feeds it (as XKB
 * text), with known evdev codes.
 *
 * THE LAYOUT IS PINNED ON PURPOSE. The keymap is built for `evdev`/`pc105`/`us` rather than taken from the
 * environment, because "a produces a" is only an assertion on a known layout; on a Dvorak machine the
 * environment's answer would be different and the test would be reporting the layout, not the code.
 */

#include "AGKeyboard.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>	/* the names the keysym door answers in */

/* Linux evdev codes, from <linux/input-event-codes.h>; spelled out so this file needs no kernel headers. */
#define KEY_ESC        1
#define KEY_1          2
#define KEY_A          30
#define KEY_LEFTSHIFT  42
#define KEY_CAPSLOCK   58
#define KEY_SPACE      57
#define KEY_F1         59
#define KEY_UP         103
#define KEY_LEFT       105

static int failures;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		failures++;
	}
}

static int translate(AGKeyboard *keyboard, uint32_t code, const char *want)
{
	char text[8];
	uint32_t modifiers = 0;

	AGKeyboardTranslate(keyboard, code, text, sizeof text, &modifiers);
	printf("    evdev %-3u -> \"%s\"%s\n", code, text,
	       (modifiers & AGModifierShift) ? "  (shift)" : "");
	return strcmp(text, want) == 0;
}

static uint32_t translate_modifiers(AGKeyboard *keyboard, uint32_t code)
{
	char text[8];
	uint32_t modifiers = 0;

	AGKeyboardTranslate(keyboard, code, text, sizeof text, &modifiers);
	return modifiers;
}

/* THE SAME KEY WITH THE MODIFIERS OFF, and the line it prints shows the pair together on purpose: the two answers are
 * a claim about the same keystroke, so a reader can see `Ctrl+A` giving `0x01` one way and `a` the other. */
static int translate_plain(AGKeyboard *keyboard, uint32_t code, const char *want)
{
	char seen[8];
	char plain[8];
	uint32_t modifiers = 0;

	AGKeyboardTranslate(keyboard, code, seen, sizeof seen, NULL);
	AGKeyboardTranslateIgnoringModifiers(keyboard, code, plain, sizeof plain, &modifiers);
	printf("    evdev %-3u typed \"%s\" ignoring-modifiers \"%s\"\n", code, seen, plain);
	return strcmp(plain, want) == 0;
}

int main(void)
{
	struct xkb_rule_names names = { "evdev", "pc105", "us", "", NULL };
	struct xkb_context *context;
	struct xkb_keymap *keymap;
	xkb_mod_index_t shift_index, caps_index, ctrl_index;
	char *text;
	AGKeyboard *keyboard;

	setvbuf(stdout, NULL, _IONBF, 0);

	context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	keymap = context != NULL ? xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS)
				 : NULL;
	if (keymap == NULL) {
		fprintf(stderr, "keyboard: could not build the us keymap; is the xkb data installed?\n");
		return 2;
	}
	shift_index = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_SHIFT);
	caps_index = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_CAPS);
	ctrl_index = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_CTRL);
	if (shift_index == XKB_MOD_INVALID || caps_index == XKB_MOD_INVALID || ctrl_index == XKB_MOD_INVALID) {
		fprintf(stderr, "keyboard: the us keymap has no Shift, Lock or Control modifier\n");
		return 2;
	}

	/* THE COMPOSITOR'S FORM, NOT A CONVENIENCE ONE: wl_keyboard.keymap sends XKB text, and that is what is
	 * handed over here. */
	text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
	if (text == NULL) {
		fprintf(stderr, "keyboard: could not serialise the keymap\n");
		return 2;
	}
	keyboard = AGKeyboardCreate();
	check(keyboard != NULL, "a keyboard can be made");
	if (keyboard == NULL) {
		return 2;
	}
	check(AGKeyboardUseKeymapText(keyboard, text, strlen(text) + 1) == 0,
	      "the keymap text compiles (this is what wl_keyboard.keymap sends)");
	free(text);
	xkb_keymap_unref(keymap);
	xkb_context_unref(context);

	/* UNMODIFIED. */
	AGKeyboardSetModifiers(keyboard, 0, 0, 0, 0);
	check(translate(keyboard, KEY_A, "a"), "evdev 30 is \"a\"");
	check(translate(keyboard, KEY_1, "1"), "evdev 2 is \"1\"");
	check(translate(keyboard, KEY_SPACE, " "), "evdev 57 is a space");
	/* ESCAPE IS NOT EMPTY, AND THAT IS APPkit'S OWN ANSWER: the key produces U+001B, and `NSEvent`'s
	 * -characters for the Escape key is exactly that one byte. Asserting it was empty was this test's first
	 * false failure -- the code was right. */
	check(translate(keyboard, KEY_ESC, "\x1b"), "evdev 1 (Escape) is the ESC control character");
	check(translate(keyboard, KEY_LEFTSHIFT, ""), "evdev 42 (Shift) produces no text");
	check(translate_modifiers(keyboard, KEY_A) == 0, "no modifier is reported when none is down");

	/* SHIFT DOWN, through the compositor's own modifier mask. */
	AGKeyboardSetModifiers(keyboard, (uint32_t)1u << shift_index, 0, 0, 0);
	check(translate(keyboard, KEY_A, "A"), "shift makes evdev 30 \"A\"");
	check(translate(keyboard, KEY_1, "!"), "shift makes evdev 2 \"!\"");
	check((translate_modifiers(keyboard, KEY_A) & AGModifierShift) != 0,
	      "AGModifierShift is reported while shift is down");

	/* CAPS LOCK, which is a LOCKED modifier rather than a depressed one. */
	AGKeyboardSetModifiers(keyboard, 0, 0, (uint32_t)1u << caps_index, 0);
	check(translate(keyboard, KEY_A, "A"), "caps lock makes evdev 30 \"A\"");
	check((translate_modifiers(keyboard, KEY_A) & AGModifierCapsLock) != 0,
	      "AGModifierCapsLock is reported while caps lock is on");

	/* **AND THE SAME KEY WITH THE MODIFIERS OFF — what a key EQUIVALENT is matched on.** The interesting cases are the
	 * ones where the two answers DIFFER, so each is asserted on both doors: `Ctrl+A` types the control character and
	 * answers `a`; a locked Caps does not survive the masking, because `Cmd+C` with Caps on must still match a menu's
	 * `c`; and Shift is the one modifier the masking KEEPS, which is what lets an uppercase key equivalent work. */
	AGKeyboardSetModifiers(keyboard, 0, 0, 0, 0);
	check(translate_plain(keyboard, KEY_A, "a"), "unmodified, evdev 30 ignores modifiers to \"a\"");
	check(translate_plain(keyboard, KEY_1, "1"), "and evdev 2 to \"1\"");

	AGKeyboardSetModifiers(keyboard, (uint32_t)1u << ctrl_index, 0, 0, 0);
	check(translate(keyboard, KEY_A, "\x01"), "Control makes evdev 30 the control character");
	check(translate_plain(keyboard, KEY_A, "a"), "while ignoring the modifiers it is still \"a\"");
	check((translate_modifiers(keyboard, KEY_A) & AGModifierControl) != 0,
	      "and the mask it reports is the LIVE one, not the masked text");

	AGKeyboardSetModifiers(keyboard, (uint32_t)1u << ctrl_index, 0, 0, 0);
	check(translate_plain(keyboard, KEY_ESC, "\x1b"), "Escape keeps its ESC byte either way — it is not a modifier");

	AGKeyboardSetModifiers(keyboard, ((uint32_t)1u << ctrl_index) | ((uint32_t)1u << shift_index), 0, 0, 0);
	check(translate(keyboard, KEY_A, "\x01"), "Ctrl+Shift types the SAME control character as Ctrl alone");
	check(translate_plain(keyboard, KEY_A, "A"), "and only the ignoring-modifiers door says WHICH key it was: \"A\"");

	AGKeyboardSetModifiers(keyboard, 0, 0, (uint32_t)1u << caps_index, 0);
	check(translate(keyboard, KEY_A, "A"), "caps lock on types \"A\"");
	check(translate_plain(keyboard, KEY_A, "a"), "and the masking DROPS the lock, so a \"c\" menu item still matches");

	AGKeyboardSetModifiers(keyboard, 0, 0, 0, 0);
	check(translate_plain(keyboard, KEY_UP, ""), "an arrow has no text with the modifiers off either");
	check(translate_plain(keyboard, KEY_SPACE, " "), "and Space is a space");

	/* AND WHICH KEYS ARE MODIFIERS, which is a different question from what they type — the AppKit delivers a
	 * modifier as `-flagsChanged:` and everything else as `-keyDown:`, so a keymap that answered this wrongly
	 * would make every Shift press a keystroke. */
	check(AGKeyboardKeyIsModifier(keyboard, KEY_LEFTSHIFT) != 0, "evdev 42 (Shift) IS a modifier");
	check(AGKeyboardKeyIsModifier(keyboard, KEY_CAPSLOCK) != 0, "evdev 58 (Caps Lock) IS a modifier");
	check(AGKeyboardKeyIsModifier(keyboard, KEY_A) == 0, "evdev 30 (A) is NOT a modifier");
	check(AGKeyboardKeyIsModifier(keyboard, KEY_SPACE) == 0, "evdev 57 (Space) is NOT a modifier");

	/* **AND WHICH KEY IT IS, WHICH IS A THIRD QUESTION.** The translation above answers what a key TYPES, so it
	 * answers nothing for the keys that type nothing — and those are exactly the keys a terminal has to write an
	 * escape sequence for and a control has to move a selection with. `AGKeyboardKeysym` answers the LAYOUT's own
	 * name for the key: `XKB_KEY_Up` on every keyboard that has an up arrow, whatever evdev calls the switch. The
	 * assertions are by keysym NAME on both sides, so they say "this code is that key" rather than lucking into a
	 * number that happens to match. */
	AGKeyboardSetModifiers(keyboard, 0, 0, 0, 0);
	check(AGKeyboardKeysym(keyboard, KEY_A) == XKB_KEY_a,
	      "evdev 30 is XKB_KEY_a, the letter it types");
	check(AGKeyboardKeysym(keyboard, KEY_UP) == XKB_KEY_Up,
	      "evdev 103 is XKB_KEY_Up, and its text is empty");
	check(translate(keyboard, KEY_UP, ""),
	      "and an arrow TYPES nothing, which is why the keysym door exists");
	check(AGKeyboardKeysym(keyboard, KEY_LEFT) == XKB_KEY_Left, "evdev 105 is XKB_KEY_Left");
	check(AGKeyboardKeysym(keyboard, KEY_F1) == XKB_KEY_F1, "evdev 59 is XKB_KEY_F1");
	check(AGKeyboardKeysym(keyboard, KEY_LEFTSHIFT) == XKB_KEY_Shift_L,
	      "evdev 42 is XKB_KEY_Shift_L: a modifier HAS a keysym, which is why the two questions are separate doors");
	check(AGKeyboardKeysym(keyboard, 0x2ff) == 0,
	      "a code the keymap does not define has NO keysym (XKB_KEY_NoSymbol), not a stale one");

	/* THE MODIFIER STATE IS APPLIED, because the question is "which key is being pressed" and not "what could this
	 * key be": with Shift down the same code answers the SHIFTED keysym. A caller that wants the physical key has
	 * `keycode`, and one that wants the character has the translation. */
	AGKeyboardSetModifiers(keyboard, (uint32_t)1u << shift_index, 0, 0, 0);
	check(AGKeyboardKeysym(keyboard, KEY_A) == XKB_KEY_A,
	      "with Shift down evdev 30 answers XKB_KEY_A, the level actually being pressed");
	AGKeyboardSetModifiers(keyboard, 0, 0, 0, 0);

	/* **AND WHICH KEYS MAY REPEAT WHEN HELD** — the keymap's half of the repeat contract. The compositor owns the
	 * RATE and the DELAY (`wl_keyboard.repeat_info`); what a repeat is allowed to be at all is this, and getting it
	 * wrong types characters nobody pressed: a modifier repeating turns one Shift press into a stream of them, and a
	 * code the layout does not define has no character to repeat. */
	check(AGKeyboardKeyIsRepeatable(keyboard, KEY_A) != 0, "evdev 30 (A) DOES repeat when held");
	check(AGKeyboardKeyIsRepeatable(keyboard, KEY_SPACE) != 0, "and so does Space");
	check(AGKeyboardKeyIsRepeatable(keyboard, KEY_LEFTSHIFT) == 0, "a modifier does NOT repeat");
	check(AGKeyboardKeyIsRepeatable(keyboard, KEY_CAPSLOCK) == 0, "nor does Caps Lock");
	check(AGKeyboardKeyIsRepeatable(keyboard, 0x2ff) == 0,
	      "nor does a code the keymap does not define — repeating it would type nothing, over and over");

	/* AND A KEYMAP THAT IS GARBAGE IS REFUSED RATHER THAN CRASHING. */
	check(AGKeyboardUseKeymapText(keyboard, "this is not a keymap", 21) != 0,
	      "a keymap that does not compile is refused");

	AGKeyboardDestroy(keyboard);
	printf("\nkeyboard: %s\n", failures == 0 ? "all checks passed" : "FAILURES");
	return failures == 0 ? 0 : 1;
}
