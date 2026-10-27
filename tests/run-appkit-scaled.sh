#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: LGPL-3.0-or-later

# **THE APPKIT'S OWN TEST, AGAINST OUR COMPOSITOR AT A SCALE THAT IS NOT ONE.**
#
# `run-appkit-headless.sh` starts gnome-shell's virtual monitor, which is 1x, and every case it runs therefore measures
# a window whose POINTS and whose DEVICE PIXELS are the same number. That is the one scale at which a mistake in the
# units never shows: a damage rectangle, a copy, a buffer row — all of them are right by accident. This runner exists
# for the cases where the number matters, so it starts Agora's own window server with `--scale N` and hands the client
# an output whose scale is a fraction.
#
#   run-appkit-scaled.sh SERVER BINARY SCALE [EXPECTED-OUTPUT]
#
# No compositor to run (the server binary is not built) means SKIP — exit 77, which is the answer every runner in this
# suite gives when the other half of the stack is missing.
set -u

SERVER="${1:?usage: run-appkit-scaled.sh SERVER BINARY SCALE [EXPECTED-OUTPUT]}"
BINARY="${2:?}"
SCALE="${3:?}"
EXPECT="${4:-}"

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SOCK="aws-appkit-scaled-$$"
SERVER_LOG="/tmp/agora-appkit-scaled-server-$$.log"

if [ ! -x "${SERVER}" ]; then
	echo "SKIP: the window server's binary is not built (${SERVER})" >&2
	exit 77
fi

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock" "${SERVER_LOG}"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"

"${SERVER}" --backend headless --input none --socket "${SOCK}" \
	--width 800 --height 600 --scale "${SCALE}" --frames 1000000 >"${SERVER_LOG}" 2>&1 &
SPID=$!
for _ in $(seq 1 60); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${RUNTIME}/${SOCK}" ]; then
	echo "FAIL: the window server never created its socket at scale ${SCALE}" >&2
	cat "${SERVER_LOG}" >&2
	exit 1
fi

# THE INPUT IS THE RUN LOOP'S, so the case runs to its own end: these are probes that make a window, paint it,
# read the seam and print a verdict, not applications that stay. `--seconds` is passed for the ones that take it.
output=$(WAYLAND_DISPLAY="${SOCK}" "${BINARY}" --seconds 10 2>&1)
status=$?
echo "${output}"

if [ "${status}" -ne 0 ]; then
	echo "FAIL: the AppKit test exited ${status}" >&2
	exit 1
fi
if [ -n "${EXPECT}" ] && ! printf '%s\n' "${output}" | grep -q "${EXPECT}"; then
	echo "FAIL: the output did not contain '${EXPECT}'" >&2
	exit 1
fi
echo "ok: ${EXPECT:-(the AppKit test passed)} at scale ${SCALE}"
exit 0
