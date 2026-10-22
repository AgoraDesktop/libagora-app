#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# **THE PLACEMENT THAT NEEDS AN EDGE.** The conversion half of `menu_placement` is arithmetic and needs nothing; the
# clamp half needs a SCREEN to clamp against, and a screen is what a compositor describes. So this runs the same
# probe against Agora's own server and asserts the right-edge case actually ran — a skipped clamp must not be able to
# look like a passing one.
#
# SKIPS (77) when the sibling's server is not built, because a component's tests must not need it.
set -u

BINARY="${1:?usage: run-menu-placement.sh BINARY WINDOW-SERVER}"
SERVER="${2:?}"

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SOCK="agora-menu-placement-$$"
LOG="/tmp/agora-menu-placement-$$.log"

if [ ! -x "${SERVER}" ]; then
	echo "SKIP: no window server at ${SERVER}" >&2
	exit 77
fi

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	[ -n "${SPID:-}" ] && wait "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock" "${LOG}"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"

"${SERVER}" --backend headless --input none --socket "${SOCK}" --width 1280 --height 720 --frames 1000000 \
	--system-menu-icon hamburger >/dev/null 2>"${LOG}" &
SPID=$!
for _ in $(seq 1 50); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${RUNTIME}/${SOCK}" ]; then
	echo "SKIP: the server never created its socket" >&2
	exit 77
fi

output=$(WAYLAND_DISPLAY="${SOCK}" "${BINARY}" 2>&1)
status=$?
printf '%s\n' "${output}" | grep -E "menu at|\[ok\]|\[FAIL\]|\[skip\]"
if [ "${status}" -ne 0 ]; then
	echo "FAIL: the probe exited ${status}" >&2
	cat "${LOG}" >&2
	exit 1
fi
if ! printf '%s\n' "${output}" | grep -q "\[ok\] and it is moved left far enough"; then
	echo "FAIL: the right-edge clamp did not run — the probe skipped it" >&2
	exit 1
fi
exit 0
