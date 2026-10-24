#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: LGPL-3.0-or-later

# Two AppKit processes, one pasteboard: the ordinary `NSPasteboard` API on both sides, and the compositor's selection
# between them.
#
# **THE ASSERTION IS WHAT THE PUBLIC DOOR ANSWERS.** The owner declares a type and writes bytes with `-setData:forType:`;
# the reader asks with `-dataForType:` and must get those bytes back — across processes, through a pipe, with nothing of
# the payload passing through the compositor. The second half proves the distinction the design exists for: a type nobody
# offers answers `nil` rather than an empty paste.
set -u

SERVER="${1:?usage: run-pasteboard-remote.sh SERVER BINARY}"
BINARY="${2:?}"

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SOCK="aws-pboard-$$"
FAIL=0
PAYLOAD="copied in one process, pasted in another"

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	[ -n "${OPID:-}" ] && kill "${OPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"

"${SERVER}" --backend headless --input none --socket "${SOCK}" --frames 1000000 --idle-timeout 60 \
	>/dev/null 2>/tmp/agora-pasteboard.log &
SPID=$!
for _ in $(seq 1 50); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${RUNTIME}/${SOCK}" ]; then
	echo "FAIL: the server never created its socket" >&2
	cat /tmp/agora-pasteboard.log >&2
	exit 1
fi

WAYLAND_DISPLAY="${SOCK}" timeout 10 "${BINARY}" --offer "text/plain;charset=utf-8" --text "${PAYLOAD}" \
	>/dev/null 2>&1 &
OPID=$!
sleep 1

out=$(WAYLAND_DISPLAY="${SOCK}" timeout 8 "${BINARY}" --request "text/plain;charset=utf-8" 2>&1)
if [ "${out}" = "read ${PAYLOAD}" ]; then
	echo "  ok    a pasteboard written in one process is read in ANOTHER: '${PAYLOAD}'"
else
	echo "FAIL: the reader did not get the payload — got: ${out}" >&2
	FAIL=1
fi

out=$(WAYLAND_DISPLAY="${SOCK}" timeout 8 "${BINARY}" --request "image/png" --expect-none 2>&1)
if [ "${out}" = "absent yes" ]; then
	echo "  ok    a type nobody offers answers nil, and does not become an empty paste"
else
	echo "FAIL: expected nil for an absent type, got: ${out}" >&2
	FAIL=1
fi

kill "${OPID}" 2>/dev/null
wait "${OPID}" 2>/dev/null
OPID=""
sleep 0.5

out=$(WAYLAND_DISPLAY="${SOCK}" timeout 8 "${BINARY}" --request "text/plain;charset=utf-8" --expect-none 2>&1)
if [ "${out}" = "absent yes" ]; then
	echo "  ok    an owner that exits takes the selection with it — the promise the plan makes"
else
	echo "FAIL: a dead owner left a selection behind — got: ${out}" >&2
	FAIL=1
fi

exit "${FAIL}"
