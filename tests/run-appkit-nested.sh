#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later
# Portions of this file may derive from GNUstep; see THIRD-PARTY.md.

# The AppKit's PIXEL test: a real NSWindow inside a NESTED compositor on the desktop (so it is visible), two
# screenshots a second apart, read back by inspect.py. A headless run can only count frames; this one proves
# the pixels a real NSView drew reached an output.
set -u

BINARY="${1:?usage: run-appkit-nested.sh BINARY}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DISP="agora-appkit-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
export DISPLAY="${DISPLAY:-:1}"

# -----------------------------------------------------------------------------------------------------------
# THIS TAKES OVER THE DESKTOP'S POINTER WHILE IT RUNS, SO IT IS OPT-IN RATHER THAN PART OF A TEST RUN.
#
# `gnome-shell --nested` is a whole nested desktop session, and it grabs the HOST's pointer to route input into
# itself. On a real desktop that means the person at the keyboard loses their mouse buttons for as long as it
# lives -- measured: after a nested run the host was left with an ACTIVE POINTER GRAB (XGrabPointer answered
# AlreadyGrabbed, while the keyboard grab was free, which is exactly "the cursor moves and the buttons do
# nothing"). That is a bad neighbour for a script, so this one asks first.
# -----------------------------------------------------------------------------------------------------------
if [ "${AGORA_ALLOW_NESTED:-}" != "1" ]; then
	cat >&2 <<'WARN'
SKIP: the nested run takes over THIS DESKTOP's pointer while it lives, and a nested session that does not
      unwind leaves the host with a stuck pointer grab -- the cursor moves and the buttons stop working.
      Run it knowingly with:   AGORA_ALLOW_NESTED=1 $0 [args]
      (A stuck grab is cleared with Alt+F2, then r, then Enter -- it restarts GNOME Shell in place.)
WARN
	exit 77
fi
echo "NOTE: this run will take over the pointer of the desktop you are sitting at." >&2

for tool in gnome-shell import; do
	command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool is needed for this test" >&2; exit 77; }
done

cleanup() {
	pkill -TERM -f -- "--wayland-display=${DISP}" 2>/dev/null
	[ -n "${CL:-}" ] && kill "${CL}" 2>/dev/null
	[ -n "${GS:-}" ] && kill -TERM "-${GS}" 2>/dev/null
	[ -n "${GS:-}" ] && kill "${GS}" 2>/dev/null
	sleep 1

	# AND THE ONE THING THAT MUST NOT BE LEFT BEHIND: a nested compositor still holding the host's pointer. The
	# kill above is by display name; THIS checks that it took, because a grab outlives the script that made it
	# and the machine it is left on is somebody's desktop. Escalate rather than hope.
	if pgrep -f -- "--wayland-display=${DISP}" >/dev/null 2>&1; then
		pkill -KILL -f -- "--wayland-display=${DISP}" 2>/dev/null
		sleep 1
		if pgrep -f -- "--wayland-display=${DISP}" >/dev/null 2>&1; then
			echo "WARNING: a nested compositor SURVIVED (wayland-display=${DISP}) and may hold the pointer." >&2
			echo "         Clear it with:  Alt+F2, then r, then Enter   (restarts GNOME Shell in place)." >&2
		fi
	fi
	rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock" /tmp/agora-appkit-A.png /tmp/agora-appkit-B.png

setsid dbus-run-session -- gnome-shell --nested --wayland --wayland-display="${DISP}" --no-x11 \
	>/tmp/agora-appkit-nested-compositor.log 2>&1 &
GS=$!
for _ in $(seq 1 60); do
	[ -S "${RUNTIME}/${DISP}" ] && break
	sleep 1
done
[ -S "${RUNTIME}/${DISP}" ] || { echo "SKIP: the nested compositor never came up" >&2; exit 77; }
sleep 6

WAYLAND_DISPLAY="${DISP}" "${BINARY}" --seconds 20 --width 720 --height 460 \
	>/tmp/agora-appkit-nested-window.log 2>&1 &
CL=$!
sleep 10

import -display "${DISPLAY}" -window root /tmp/agora-appkit-A.png
sleep 1.2
import -display "${DISPLAY}" -window root /tmp/agora-appkit-B.png
cat /tmp/agora-appkit-nested-window.log

python3 "${HERE}/inspect.py" /tmp/agora-appkit-A.png /tmp/agora-appkit-B.png
