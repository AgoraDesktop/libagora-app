/*
 * AGKeyboard.h — an evdev key code and a compositor keymap, turned into text, modifiers and the key's own name.
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
 * to `utf8` (0 when the key produces no text — a modifier, an arrow, an F key). `*modifiers` always receives
 * the mask. `size` must be > 0. A key that types nothing is not a key that means nothing: ask
 * `AGKeyboardKeysym` below for which key it was. */
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

/* **THE KEYMAP'S NAME FOR THE KEY ITSELF.** `AGKeyboardTranslate` answers what a key TYPES, so it answers nothing at
 * all for a key that types nothing — an arrow, Home, an F key — and a caller that has to know WHICH key it was (a
 * terminal writing an escape sequence, a control that nudges with arrows, `NSEvent`'s 0xF700 command block) has only
 * two bad options without this: a table of evdev codes, which is right for one layout and wrong for the next; or a
 * guess from the empty text and the modifier mask, which cannot tell an up arrow from an F key.
 *
 * The answer is an `XKB_KEY_…` keysym — the layout's own vocabulary, where `XKB_KEY_Up` means "the key that goes up"
 * whatever the hardware calls it — and it is `0` (`XKB_KEY_NoSymbol`) when the map defines no symbol for the code.
 * The CURRENT modifier state is applied, so the keysym is the one the person is pressing rather than a list of the
 * key's levels.
 *
 * IT IS A SEPARATE DOOR FROM THE TRANSLATION for the same reason `AGKeyboardKeyIsModifier` is: the two questions have
 * different answers for the same key (Escape has a keysym AND types 0x1B; an arrow has a keysym and types nothing),
 * and a caller may want either alone. */
uint32_t AGKeyboardKeysym(AGKeyboard *keyboard, uint32_t evdev_keycode);

/* **DOES THIS KEY REPEAT WHEN HELD?** The keyboard's own answer, and the one a repeat generator has to ask: a
 * MODIFIER does not (holding Shift does not type Shift over and over), and neither does a key the map gives no symbol
 * to at all — a media key on a map that does not cover it, or a code the layout leaves undefined. Repeating those
 * would type characters nobody pressed. This is the xkb half of "honour repeat_info and xkb repeatability": the
 * rate and delay are the compositor's, the list of which keys may repeat is the keymap's. */
int AGKeyboardKeyIsRepeatable(AGKeyboard *keyboard, uint32_t evdev_keycode);

#ifdef __cplusplus
}
#endif

#endif /* AG_KEYBOARD_H */
