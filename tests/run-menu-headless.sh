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

start=$(date +%s)
WAYLAND_DISPLAY="${SOCK}" timeout "${BUDGET}" "${BINARY}" 2>&1 | sed 's/^/  /'
rc=${PIPESTATUS[0]}
elapsed=$(( $(date +%s) - start ))
if [ "${rc}" -eq 124 ]; then
	echo "FAIL: the menu never finished drawing — ${BUDGET}s elapsed. THIS IS THE FONT-ENUMERATION SHAPE OF" >&2
	echo "      SLOW: a draw that asks for a UI font per cell per frame re-walks every font file on the host." >&2
	exit 1
fi
[ "${rc}" -eq 0 ] || { echo "FAIL: the menu demo exited ${rc}" >&2; exit 1; }
echo "  (note: the menu finished in ${elapsed}s)"

# THE SIGNAL WRITES THE SCREENSHOT: the exit trap would write it after the assertions that want it.
kill -TERM "${SPID}" 2>/dev/null
wait "${SPID}" 2>/dev/null
SPID=""
[ -f "${SHOT}" ] || { echo "FAIL: the server wrote no screenshot" >&2; exit 1; }

"$(dirname "$0")/menu_shot.py" "${SHOT}"
