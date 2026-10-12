/*
 * keyboard — evdev codes and a keymap, turned into text, with no compositor anywhere.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
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

/* Linux evdev codes, from <linux/input-event-codes.h>; spelled out so this file needs no kernel headers. */
#define KEY_ESC        1
#define KEY_1          2
#define KEY_A          30
#define KEY_LEFTSHIFT  42
#define KEY_SPACE      57

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

int main(void)
{
	struct xkb_rule_names names = { "evdev", "pc105", "us", "", NULL };
	struct xkb_context *context;
	struct xkb_keymap *keymap;
	xkb_mod_index_t shift_index, caps_index;
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
	if (shift_index == XKB_MOD_INVALID || caps_index == XKB_MOD_INVALID) {
		fprintf(stderr, "keyboard: the us keymap has no Shift or Lock modifier\n");
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

	/* AND A KEYMAP THAT IS GARBAGE IS REFUSED RATHER THAN CRASHING. */
	check(AGKeyboardUseKeymapText(keyboard, "this is not a keymap", 21) != 0,
	      "a keymap that does not compile is refused");

	AGKeyboardDestroy(keyboard);
	printf("\nkeyboard: %s\n", failures == 0 ? "all checks passed" : "FAILURES");
	return failures == 0 ? 0 : 1;
}
