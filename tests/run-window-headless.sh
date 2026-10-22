#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later
# Portions of this file may derive from GNUstep; see THIRD-PARTY.md.

# Runs the seam's window test against a HEADLESS Wayland compositor and asserts the frame count.
#
# WHY A HEADLESS COMPOSITOR IS THE TEST AND A NESTED ONE IS NOT: a nested compositor needs the desktop and a
# human to see it, so it cannot be a `ctest`. Headless mutter can: it needs `--virtual-monitor`, or it has no
# output to composite and presents zero frames (a protocol-correct client, a silent zero, and the reason
# that flag is on the command line).
#
# Exit 77 means SKIP (no compositor on this machine); 0 means the frame count was exact.
set -u

BINARY="${1:?usage: run-window-headless.sh BINARY [FRAMES]}"
FRAMES="${2:-60}"
DISP="agora-ctest-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"

if ! command -v gnome-shell >/dev/null 2>&1; then
	echo "SKIP: no Wayland compositor on this machine (gnome-shell not found)" >&2
	exit 77
fi

cleanup() {
	# THE PROCESS-GROUP KILL ALONE IS NOT ENOUGH, AND THAT WAS MEASURED: `setsid` forks when it is already
	# a process-group leader, so its pid is not always the group's, and a leaked compositor keeps a socket
	# and a CPU for its whole `timeout`. The command line carries the display name, which is unique to this
	# run, so that is the reliable handle.
	pkill -TERM -f -- "--wayland-display=${DISP}" 2>/dev/null
	[ -n "${GS:-}" ] && kill -TERM "-${GS}" 2>/dev/null
	[ -n "${GS:-}" ] && kill "${GS}" 2>/dev/null
	rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock"

# A PRIVATE SESSION BUS: gnome-shell claims names the user's own shell already owns, and `dbus-run-session`
# is what keeps the test from disturbing the running desktop.
if command -v dbus-run-session >/dev/null 2>&1; then
	setsid timeout 90 dbus-run-session -- gnome-shell --headless --wayland \
		--wayland-display="${DISP}" --virtual-monitor 1280x720 >/tmp/agora-app-ctest-compositor.log 2>&1 &
	GS=$!
else
	echo "SKIP: dbus-run-session is needed to start a private compositor" >&2
	exit 77
fi

for _ in $(seq 1 60); do
	[ -S "${RUNTIME}/${DISP}" ] && break
	sleep 1
done
if [ ! -S "${RUNTIME}/${DISP}" ]; then
	echo "SKIP: the compositor never created a socket" >&2
	exit 77
fi
sleep 3

output=$(WAYLAND_DISPLAY="${DISP}" "${BINARY}" --frames "${FRAMES}" 2>&1)
status=$?
echo "${output}"

presented=$(printf '%s\n' "${output}" | sed -n 's/.*: \([0-9]*\) frame(s) presented/\1/p' | tail -1)
if [ "${status}" -ne 0 ]; then
	echo "FAIL: the client exited ${status}" >&2
	exit 1
fi
if [ "${presented}" != "${FRAMES}" ]; then
	echo "FAIL: presented ${presented:-none} frames, wanted ${FRAMES}" >&2
	exit 1
fi
echo "ok: ${presented} frames presented"
exit 0
