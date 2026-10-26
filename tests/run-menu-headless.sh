#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# **THE DISPLAY PATH, ON A HEADLESS COMPOSITOR, IN ctest.** No desktop is needed: the menu's own window draws
# through `NSWindow -cg_drawFrame` into the compositor's framebuffer, and the compositor's screenshot is what is
# read back. That is the half no offscreen test can see.
#
# A BUDGET GUARDS THE HANG. `timeout` turns "never finishes" into a failing test with a name, because the last
# time this path was slow the symptom was a demo that simply never returned and nothing caught it.
#
# SKIPS (77) when there is no window server to run against: a component's tests must not need a sibling's build.
set -u

BINARY="${1:?usage: run-menu-headless.sh MENU-DEMO WINDOW-SERVER [SECONDS] [BUDGET]}"
SERVER="${2:?}"
SECONDS_UP="${3:-3}"
BUDGET="${4:-60}"
SHOT="${AGORA_SCREENSHOT:-/tmp/agora-menu-headless-$$.ppm}"
SOCK="agora-menu-headless-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"

[ -x "${SERVER}" ] || { echo "SKIP: no window server at ${SERVER}" >&2; exit 77; }

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
	[ -n "${AGORA_SCREENSHOT:-}" ] || rm -f "${SHOT}"
}
trap cleanup EXIT
rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock" "${SHOT}"

"${SERVER}" --backend headless --input none --socket "${SOCK}" --frames 1000000 \
	--width 640 --height 480 --screenshot "${SHOT}" >/dev/null 2>&1 &
SPID=$!
for _ in $(seq 1 50); do [ -S "${RUNTIME}/${SOCK}" ] && break; sleep 0.1; done
[ -S "${RUNTIME}/${SOCK}" ] || { echo "FAIL: the server never came up" >&2; exit 1; }

# **THE SERVER IS STOPPED WHILE THE MENU IS UP, WHICH IS THE ONLY MOMENT THE PICTURE IS THE PICTURE.** The screenshot is
# written at the server's shutdown from its last frame — and a client that has already left takes its window with it,
# because the compositor repaints the ground a destroyed surface covered. So the demo runs in the background and KEEPS
# THE MENU OPEN, the server is signalled once the menu has been drawn, and the demo is killed afterwards. The same order
# `window-server`'s own `run-headless.sh` records, and the reason its comment gives.
CLIENT_LOG="/tmp/agora-menu-headless-client-$$.log"
start=$(date +%s)
WAYLAND_DISPLAY="${SOCK}" "${BINARY}" --passes 100000 >"${CLIENT_LOG}" 2>&1 &
CPID=$!
# THE CLIENT SAYS WHEN THE MENU IS UP: the click it sends is a REQUEST, and the menu's own window is drawn on the frame
# callbacks its loop dispatches a few passes later. Waiting for that line is waiting for a fact rather than for a sleep.
for _ in $(seq 1 600); do
	grep -q "the menu is up" "${CLIENT_LOG}" 2>/dev/null && break
	sleep 0.05
done
elapsed=$(( $(date +%s) - start ))
if ! grep -q "the menu is up" "${CLIENT_LOG}" 2>/dev/null; then
	echo "FAIL: the menu never came up within ${elapsed}s. THIS IS THE FONT-ENUMERATION SHAPE OF" >&2
	echo "      SLOW: a draw that asks for a UI font per cell per frame re-walks every font file on the host." >&2
	kill "${CPID}" 2>/dev/null
	cat "${CLIENT_LOG}" >&2
	exit 1
fi
# ONE MORE FRAME, SO THE MENU'S OWN WINDOW IS COMPOSITED AND NOT ONLY ITS BAR'S.
sleep 0.5
kill -TERM "${SPID}" 2>/dev/null
wait "${SPID}" 2>/dev/null
SPID=""
kill "${CPID}" 2>/dev/null
wait "${CPID}" 2>/dev/null
rm -f "${CLIENT_LOG}"
echo "  (note: the menu was up after ${elapsed}s)"
[ -f "${SHOT}" ] || { echo "FAIL: the server wrote no screenshot" >&2; exit 1; }

"$(dirname "$0")/menu_shot.py" "${SHOT}"
