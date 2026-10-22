#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later
# Portions of this file may derive from GNUstep; see THIRD-PARTY.md.

# The drag image window against Agora's own headless window server.
#
# A floating, transparent, borderless window is a CLIENT-SIDE object here, so the probe can make one only where a
# connection exists. SKIPS (77) when the sibling's server is not built, because a component's tests must not require
# another component's build to be present.
set -u

BINARY="${1:?usage: run-drag-seam.sh DRAG-SEAM WINDOW-SERVER}"
SERVER="${2:?}"
SOCK="agora-drag-seam-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"

if [ ! -x "${SERVER}" ]; then
	echo "SKIP: no window server at ${SERVER}" >&2
	exit 77
fi

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
"${SERVER}" --backend headless --input none --socket "${SOCK}" --frames 1000000 \
	>/dev/null 2>/tmp/agora-drag-seam-server.log &
SPID=$!
for _ in $(seq 1 50); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${RUNTIME}/${SOCK}" ]; then
	echo "SKIP: the server never came up" >&2
	exit 77
fi

WAYLAND_DISPLAY="${SOCK}" "${BINARY}"
status=$?
exit "${status}"
