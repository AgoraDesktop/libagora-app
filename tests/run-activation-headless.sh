# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later
# Portions of this file may derive from GNUstep; see THIRD-PARTY.md.

#!/bin/bash
# **ONLY THE ACTIVE APPLICATION'S MENUS SHOW, ON A HEADLESS COMPOSITOR.** Agora's own window server is the only
# one with a menu bar for an application to put its menus in, so this test needs the sibling's binary — and it
# SKIPS (77) when there is none, because a component's tests must not require another component's build.
set -u

BINARY="${1:?usage: run-activation-headless.sh APPkit-activation WINDOW-SERVER [SECONDS]}"
SERVER="${2:?}"
SECONDS_TO_RUN="${3:-3}"
SOCK="agora-activation-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
BUDGET="${BUDGET:-60}"

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
	>/dev/null 2>/tmp/agora-activation-server.log &
SPID=$!
for _ in $(seq 1 50); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
[ -S "${RUNTIME}/${SOCK}" ] || { echo "SKIP: the server never came up" >&2; exit 77; }

start=$(date +%s)
output=$(WAYLAND_DISPLAY="${SOCK}" timeout "${BUDGET}" "${BINARY}" 2>&1)
status=$?
elapsed=$(( $(date +%s) - start ))
printf '%s\n' "${output}"

kill -TERM "${SPID}" 2>/dev/null
wait "${SPID}" 2>/dev/null
SPID=""

if [ "${status}" -eq 124 ]; then
	echo "FAIL: the activation test never finished — ${BUDGET}s elapsed" >&2
	exit 1
fi
if [ "${status}" -ne 0 ]; then
	echo "FAIL: the activation test exited ${status}" >&2
	exit 1
fi
if ! printf '%s\n' "${output}" | grep -q "all checks passed"; then
	echo "FAIL: the activation test did not report all checks passed" >&2
	exit 1
fi
echo "  (note: the activation test finished in ${elapsed}s)"
exit 0
