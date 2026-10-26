#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: LGPL-3.0-or-later

# The AppKit against OUR window server on a scaled output, photographed.
#
# This is the client half of resolution independence and it needs both halves of the stack in the same test: the
# compositor has to report the output scale (fractional since protocol 9, via `agora_output.preferred_scale`), the
# client has to rasterise at that scale and declare the same fraction back, and the compositor then has to composite
# it 1:1. A synthetic event fixture cannot show any of that, so the server runs at a known `--scale` and the checker
# measures where a shape drawn at a known POINT actually landed. 2 and 1 exercise the integer path; 1.5 is the
# fractional one; and an optional sixth argument is a UI COMFORT FACTOR, which the compositor multiplies onto `--scale`
# — the case where the scale the client follows was decided partly by the person rather than wholly by the panel.
set -u

SERVER="${1:?usage: run-appkit-hidpi.sh SERVER BINARY PYTHON CHECKER}"
BINARY="${2:?}"
PYTHON="${3:?}"
CHECKER="${4:?}"

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SOCK="aws-hidpi-$$"
SHOT="/tmp/agora-hidpi-$$.ppm"
LOGICAL_W=800
LOGICAL_H=600
SCALE="${5:-2}"
# **AND THE USER'S COMFORT FACTOR, WHEN THE CASE IS ABOUT THAT.** The server multiplies it onto SCALE, so the client is
# told the PRODUCT and the checker measures against the product; empty means "nobody asked for one" and the server is
# left alone, which is every case that existed before the factor did.
UI="${6:-}"
if [ -n "${UI}" ]; then
	DEVICE_SCALE="$(awk "BEGIN { print ${SCALE} * ${UI} }")"
	UI_ARGS=(--ui-scale "${UI}")
else
	DEVICE_SCALE="${SCALE}"
	UI_ARGS=()
fi
WIN_X=50
WIN_Y=40
WIN_W=200
WIN_H=100

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock" "${SHOT}"

"${SERVER}" --backend headless --input none --socket "${SOCK}" \
	--width "${LOGICAL_W}" --height "${LOGICAL_H}" --scale "${SCALE}" "${UI_ARGS[@]}" \
	--frames 1000000 --screenshot "${SHOT}" >/dev/null 2>/tmp/agora-hidpi.log &
SPID=$!
for _ in $(seq 1 50); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${RUNTIME}/${SOCK}" ]; then
	echo "FAIL: the server never created its socket" >&2
	cat /tmp/agora-hidpi.log >&2
	exit 1
fi

# **THE SERVER IS STOPPED WHILE THE WINDOW IS STILL ON THE SCREEN, AND THAT ORDER IS THE TEST.** The screenshot is
# written at the server's shutdown from its last frame, so a client that has already gone takes its window with it: the
# compositor now repaints the pixels a destroyed surface was covering (a full redraw, and the right thing to do — the
# ground under a closed window is not something that surface ever damaged). So the client runs in the BACKGROUND with a
# budget rather than in the foreground, the server is signalled once the window has had time to paint, and the client is
# killed afterwards — the same order `window-server`'s own `run-headless.sh` records.
CLIENT_LOG="/tmp/agora-hidpi-client-$$.log"
WAYLAND_DISPLAY="${SOCK}" "${BINARY}" --seconds 10 \
	--x "${WIN_X}" --y "${WIN_Y}" --width "${WIN_W}" --height "${WIN_H}" >"${CLIENT_LOG}" 2>&1 &
CPID=$!
for _ in $(seq 1 100); do
	grep -q "appkit_hidpi: window" "${CLIENT_LOG}" 2>/dev/null && break
	sleep 0.05
done
# THE WINDOW HAS BEEN MADE; ONE FRAME'S WORTH OF PATIENCE AND IT IS ON THE GLASS.
sleep 0.6
kill -TERM "${SPID}" 2>/dev/null
wait "${SPID}" 2>/dev/null
kill "${CPID}" 2>/dev/null
wait "${CPID}" 2>/dev/null
head -4 "${CLIENT_LOG}"
if ! grep -q "appkit_hidpi: window" "${CLIENT_LOG}"; then
	echo "FAIL: the AppKit test never made its window" >&2
	cat "${CLIENT_LOG}" /tmp/agora-hidpi.log >&2
	exit 1
fi
rm -f "${CLIENT_LOG}"

if [ ! -f "${SHOT}" ]; then
	echo "FAIL: the server wrote no screenshot" >&2
	cat /tmp/agora-hidpi.log >&2
	exit 1
fi

"${PYTHON}" "${CHECKER}" "${SHOT}" "${DEVICE_SCALE}" "${WIN_X}" "${WIN_Y}" "${WIN_W}" "${WIN_H}"
