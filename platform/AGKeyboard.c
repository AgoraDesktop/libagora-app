/*
 * AGKeyboard.c — xkbcommon in one place.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THE ONE OFFSET THAT IS EASY TO GET WRONG. Wayland's `wl_keyboard.key` carries a LINUX EVDEV key code.
 * xkbcommon's keymap is indexed by X11 key codes, which are the evdev code PLUS 8. So every translation
 * adds 8, and forgetting it does not fail — it answers the character for a DIFFERENT key, which looks like
 * a broken keyboard layout. It is written once, here, and the test asserts a known code.
 */

#include "AGKeyboard.h"

#include <stdlib.h>
#include <string.h>

#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>

/* Wayland's key codes are evdev; xkbcommon's are evdev + 8 (X11's historical offset). */
#define AG_EVDEV_TO_XKB(code) ((xkb_keycode_t)((code) + 8))

struct AGKeyboard {
	struct xkb_context *context;
	struct xkb_keymap *keymap;
	struct xkb_state *state;

	/* The modifier indices, resolved once per keymap: xkb_keymap_mod_get_index is a lookup, and the mask
	 * is wanted on every key event. */
	xkb_mod_index_t shift;
	xkb_mod_index_t control;
	xkb_mod_index_t alt;
	xkb_mod_index_t super;
	xkb_mod_index_t caps;
	xkb_mod_index_t num;
};

static void ag_keyboard_resolve_modifiers(AGKeyboard *keyboard)
{
	keyboard->shift = xkb_keymap_mod_get_index(keyboard->keymap, XKB_MOD_NAME_SHIFT);
	keyboard->control = xkb_keymap_mod_get_index(keyboard->keymap, XKB_MOD_NAME_CTRL);
	keyboard->alt = xkb_keymap_mod_get_index(keyboard->keymap, XKB_MOD_NAME_ALT);
	keyboard->super = xkb_keymap_mod_get_index(keyboard->keymap, XKB_MOD_NAME_LOGO);
	keyboard->caps = xkb_keymap_mod_get_index(keyboard->keymap, XKB_MOD_NAME_CAPS);
	keyboard->num = xkb_keymap_mod_get_index(keyboard->keymap, XKB_MOD_NAME_NUM);
}

AGKeyboard *AGKeyboardCreate(void)
{
	AGKeyboard *keyboard = calloc(1, sizeof *keyboard);

	if (keyboard == NULL) {
		return NULL;
	}
	keyboard->context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (keyboard->context == NULL) {
		free(keyboard);
		return NULL;
	}
	return keyboard;
}

void AGKeyboardDestroy(AGKeyboard *keyboard)
{
	if (keyboard == NULL) {
		return;
	}
	if (keyboard->state != NULL) {
		xkb_state_unref(keyboard->state);
	}
	if (keyboard->keymap != NULL) {
		xkb_keymap_unref(keyboard->keymap);
	}
	if (keyboard->context != NULL) {
		xkb_context_unref(keyboard->context);
	}
	free(keyboard);
}

int AGKeyboardUseDefaultKeymap(AGKeyboard *keyboard)
{
	struct xkb_keymap *keymap;

	if (keyboard == NULL || keyboard->context == NULL) {
		return -1;
	}
	keymap = xkb_keymap_new_from_names(keyboard->context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
	if (keymap == NULL) {
		return -1;
	}
	if (keyboard->state != NULL) {
		xkb_state_unref(keyboard->state);
	}
	if (keyboard->keymap != NULL) {
		xkb_keymap_unref(keyboard->keymap);
	}
	keyboard->keymap = keymap;
	keyboard->state = xkb_state_new(keymap);
	if (keyboard->state == NULL) {
		return -1;
	}
	ag_keyboard_resolve_modifiers(keyboard);
	return 0;
}

int AGKeyboardUseKeymapText(AGKeyboard *keyboard, const char *text, size_t size)
{
	struct xkb_keymap *keymap;

	if (keyboard == NULL || keyboard->context == NULL || text == NULL) {
		return -1;
	}
	/* THE SIZE IS PASSED EVEN THOUGH THE TEXT IS NUL-TERMINATED: the keymap arrives in an mmap'd file and
	 * the compositor's NUL is not guaranteed within the mapped region. */
	keymap = xkb_keymap_new_from_string(keyboard->context, text, XKB_KEYMAP_FORMAT_TEXT_V1,
					    XKB_KEYMAP_COMPILE_NO_FLAGS);
	if (keymap == NULL) {
		return -1;
	}
	if (keyboard->state != NULL) {
		xkb_state_unref(keyboard->state);
	}
	if (keyboard->keymap != NULL) {
		xkb_keymap_unref(keyboard->keymap);
	}
	keyboard->keymap = keymap;
	keyboard->state = xkb_state_new(keymap);
	if (keyboard->state == NULL) {
		return -1;
	}
	ag_keyboard_resolve_modifiers(keyboard);
	return 0;
}

void AGKeyboardSetModifiers(AGKeyboard *keyboard, uint32_t depressed, uint32_t latched, uint32_t locked,
			    uint32_t group)
{
	if (keyboard == NULL || keyboard->state == NULL) {
		return;
	}
	xkb_state_update_mask(keyboard->state, depressed, latched, locked, 0, 0, group);
}

uint32_t AGKeyboardModifiers(AGKeyboard *keyboard)
{
	xkb_mod_mask_t mods;
	uint32_t result = 0;

	if (keyboard == NULL || keyboard->state == NULL) {
		return 0;
	}
	mods = xkb_state_serialize_mods(keyboard->state,
					XKB_STATE_MODS_DEPRESSED | XKB_STATE_MODS_LATCHED | XKB_STATE_MODS_LOCKED);
	/* xkb_keymap_mod_get_index returns XKB_MOD_INVALID (0xffffffff) for a modifier the keymap has none of,
	 * and shifting by that is undefined -- hence the != XKB_MOD_INVALID guard on every one. */
	if (keyboard->shift != XKB_MOD_INVALID && (mods & (1u << keyboard->shift))) {
		result |= AGModifierShift;
	}
	if (keyboard->control != XKB_MOD_INVALID && (mods & (1u << keyboard->control))) {
		result |= AGModifierControl;
	}
	if (keyboard->alt != XKB_MOD_INVALID && (mods & (1u << keyboard->alt))) {
		result |= AGModifierAlt;
	}
	if (keyboard->super != XKB_MOD_INVALID && (mods & (1u << keyboard->super))) {
		result |= AGModifierSuper;
	}
	if (keyboard->caps != XKB_MOD_INVALID && (mods & (1u << keyboard->caps))) {
		result |= AGModifierCapsLock;
	}
	if (keyboard->num != XKB_MOD_INVALID && (mods & (1u << keyboard->num))) {
		result |= AGModifierNumLock;
	}
	return result;
}

int AGKeyboardKeyIsModifier(AGKeyboard *keyboard, uint32_t evdev_keycode)
{
	xkb_keysym_t sym;

	if (keyboard == NULL || keyboard->state == NULL) {
		return 0;
	}
	sym = xkb_state_key_get_one_sym(keyboard->state, AG_EVDEV_TO_XKB(evdev_keycode));
	/* THE MODIFIER KEYSYMS ARE ONE CONTIGUOUS RANGE plus a few that sit outside it: Shift_L (0xffe1) through
	 * Hyper_R (0xffee) covers Shift, Control, Meta and the Alt/Level keys; Num Lock (0xff7f) and the ISO
	 * group and level keys are the ones that are not in that block. Caps Lock IS in it, which is why it is not
	 * named again below. */
	if (sym >= XKB_KEY_Shift_L && sym <= XKB_KEY_Hyper_R) {
		return 1;
	}
	switch (sym) {
	case XKB_KEY_Num_Lock:
	case XKB_KEY_Mode_switch:
	case XKB_KEY_ISO_Level3_Shift:
	case XKB_KEY_ISO_Level5_Shift:
	case XKB_KEY_ISO_Next_Group:
	case XKB_KEY_ISO_Prev_Group:
	case XKB_KEY_ISO_First_Group:
	case XKB_KEY_ISO_Last_Group:
		return 1;
	default:
		return 0;
	}
}

int AGKeyboardTranslate(AGKeyboard *keyboard, uint32_t evdev_keycode, char *utf8, size_t size,
			uint32_t *modifiers)
{
	int written;

	if (size > 0) {
		utf8[0] = '\0';
	}
	if (keyboard == NULL || keyboard->state == NULL) {
		if (modifiers != NULL) {
			*modifiers = 0;
		}
		return 0;
	}
	if (modifiers != NULL) {
		*modifiers = AGKeyboardModifiers(keyboard);
	}
	if (size == 0) {
		return 0;
	}
	written = xkb_state_key_get_utf8(keyboard->state, AG_EVDEV_TO_XKB(evdev_keycode), utf8, size);
	return written > 0 ? written : 0;
}

int AGKeyboardKeyIsRepeatable(AGKeyboard *keyboard, uint32_t evdev_keycode)
{
	xkb_keysym_t sym;

	if (keyboard == NULL || keyboard->state == NULL) {
		return 0;
	}
	/* A MODIFIER FIRST, and by the same test the AppKit's `-flagsChanged:` uses: one definition of "this key is a
	 * modifier" is what keeps the two answers from disagreeing. */
	if (AGKeyboardKeyIsModifier(keyboard, evdev_keycode)) {
		return 0;
	}
	/* AND A KEY WITH NO SYMBOL DOES NOT REPEAT.** `XKB_KEY_NoSymbol` is the map's answer for a code it does not
	 * define, and repeating it would deliver a keystroke that stands for nothing. */
	sym = xkb_state_key_get_one_sym(keyboard->state, (xkb_keycode_t)(evdev_keycode + 8));
	return sym != XKB_KEY_NoSymbol;
}
