#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# The MENU, on a display, nested inside the desktop you are sitting at.
#
# **AGORA'S OWN WINDOW SERVER IS THE NESTED COMPOSITOR HERE, AND THAT IS DELIBERATE.** Its X11 backend opens an
# ordinary X window and GRABS NOTHING — no XGrabPointer, no XGrabKeyboard — so unlike a nested gnome-shell it
# cannot take the host's pointer away. The composited frame is photographed from the server's OWN framebuffer, so
# the picture is of what the compositor really put on its output.
#
# Usage: run-menu-nested.sh APPkit-menu-draw WINDOW-SERVER [SECONDS]
set -u

BINARY="${1:?usage: run-menu-nested.sh BINARY WINDOW-SERVER [SECONDS]}"
SERVER="${2:?}"
SECONDS_UP="${3:-4}"
SHOT="${AGORA_SCREENSHOT:-/tmp/agora-menu-nested.ppm}"
SOCK="agora-menu-nested-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
DISP="${DISPLAY:-:1}"

[ -x "${SERVER}" ] || { echo "SKIP: no window server at ${SERVER}" >&2; exit 77; }

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	[ -n "${CL:-}" ] && kill "${CL}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
}
trap cleanup EXIT
rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock" "${SHOT}"

DISPLAY="${DISP}" "${SERVER}" --backend x11 --input none --socket "${SOCK}" --frames 1000000 \
	--width 640 --height 480 --screenshot "${SHOT}" >/tmp/agora-menu-server.log 2>&1 &
SPID=$!
for _ in $(seq 1 50); do [ -S "${RUNTIME}/${SOCK}" ] && break; sleep 0.1; done
[ -S "${RUNTIME}/${SOCK}" ] || { echo "SKIP: the server never came up" >&2; cat /tmp/agora-menu-server.log >&2; exit 77; }
echo "NOTE: a nested window is open on ${DISP} — the server's own X11 window, which grabs nothing." >&2

WAYLAND_DISPLAY="${SOCK}" "${BINARY}" >/tmp/agora-menu-client.log 2>&1 &
CL=$!
sleep "${SECONDS_UP}"

# THE SIGNAL WRITES THE SCREENSHOT: it stops the loop and the ordinary exit path runs.
kill -TERM "${SPID}" 2>/dev/null
wait "${SPID}" 2>/dev/null
kill "${CL}" 2>/dev/null
SPID="" ; CL=""
cat /tmp/agora-menu-client.log
[ -f "${SHOT}" ] || { echo "FAIL: the server wrote no screenshot" >&2; exit 1; }
echo "shot: ${SHOT}"
