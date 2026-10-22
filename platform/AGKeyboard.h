/*
 * AGKeyboard.h — an evdev key code and a compositor keymap, turned into text and modifiers.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS IS ITS OWN FILE, AND NOT PART OF THE WAYLAND BACKEND. Wayland sends KEY CODES, not characters:
 * `wl_keyboard.key` carries the Linux evdev code for a physical key (KEY_A is 30, wherever A happens to be
 * on the keyboard in use). Turning 30 into "a", "A" or nothing at all needs the keymap the compositor sent
 * and the modifier state at that instant — and that is xkbcommon's job, on a keyboard layout this program
 * must not guess.
 *
 * Splitting it out is what makes it TESTABLE. Everything below this line works with a keymap and a number;
 * nothing here needs a compositor, a seat, or a display, so `tests/keyboard.c` checks the translation
 * directly. That is the difference between "input compiles" and "input was measured".
 */

#ifndef AG_KEYBOARD_H
#define AG_KEYBOARD_H

#include <stddef.h>
#include <stdint.h>

#include "AGWindowServer.h"	/* AGModifier... */

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AGKeyboard AGKeyboard;

AGKeyboard *AGKeyboardCreate(void);
void AGKeyboardDestroy(AGKeyboard *keyboard);

/* Compile the system's default keymap — the same one a session would have. Needs no compositor, which is
 * what lets a test drive it; the backend uses it only as a fallback if the compositor never sends one. */
int AGKeyboardUseDefaultKeymap(AGKeyboard *keyboard);

/* Compile the keymap the compositor sent with `wl_keyboard.keymap` (format XKB_V1). 0 on success. */
int AGKeyboardUseKeymapText(AGKeyboard *keyboard, const char *text, size_t size);

/* Feed the compositor's `wl_keyboard.modifiers` state. */
void AGKeyboardSetModifiers(AGKeyboard *keyboard, uint32_t depressed, uint32_t latched, uint32_t locked,
			    uint32_t group);

/* Translate an evdev key code to UTF-8 and the CURRENT modifier mask. Returns the number of bytes written
 * to `utf8` (0 when the key produces no text — a modifier, an arrow, Escape). `*modifiers` always receives
 * the mask. `size` must be > 0. */
int AGKeyboardTranslate(AGKeyboard *keyboard, uint32_t evdev_keycode, char *utf8, size_t size,
			uint32_t *modifiers);

/* The modifier mask for the state last fed in. */
uint32_t AGKeyboardModifiers(AGKeyboard *keyboard);

/* IS THIS KEY A MODIFIER RATHER THAN A CHARACTER? Nonzero when the keymap says the key is one of the modifier
 * keysyms (Shift, Control, Alt, Super, Caps Lock, Num Lock, the ISO group and level keys). It is a separate
 * question because the ANSWER changes how an event is delivered rather than what it says: AppKit sends
 * `-flagsChanged:` for a modifier and `-keyDown:`/`-keyUp:` for everything else, so a tool that delivered
 * every key press as a key down would leave `-flagsChanged:` unreachable. */
int AGKeyboardKeyIsModifier(AGKeyboard *keyboard, uint32_t evdev_keycode);

#ifdef __cplusplus
}
#endif

#endif /* AG_KEYBOARD_H */
