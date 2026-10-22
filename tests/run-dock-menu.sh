#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# **A TILE'S MENU, AGAINST AGORA'S OWN SERVER** — the round trip needs `agora_shell` version 6, so it runs against
# `window-server` and SKIPS (77) when there is none to run against.
#
# The probe is both ends of the conversation: the application (its own `-applicationDockMenu:`) and the Dock
# (`NSDockMenu`), which is what makes a two-process protocol assertable as a sequence.
set -u
BINARY="${1:?usage: run-dock-menu.sh PROBE WINDOW-SERVER}"
SERVER="${2:?}"
SOCK="agora-dock-menu-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
[ -x "${SERVER}" ] || { echo "SKIP: no window server at ${SERVER}" >&2; exit 77; }
cleanup() { [ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null; rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"; }
trap cleanup EXIT
rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
"${SERVER}" --backend headless --input none --socket "${SOCK}" --frames 1000000 --width 1280 --height 720 \
	>/dev/null 2>&1 &
SPID=$!
for _ in $(seq 1 50); do [ -S "${RUNTIME}/${SOCK}" ] && break; sleep 0.1; done
[ -S "${RUNTIME}/${SOCK}" ] || { echo "SKIP: the server never came up" >&2; exit 77; }
WAYLAND_DISPLAY="${SOCK}" timeout 30 "${BINARY}"
rc=$?
kill -TERM "${SPID}" 2>/dev/null; wait "${SPID}" 2>/dev/null; SPID=""
exit "${rc}"
