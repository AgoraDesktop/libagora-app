#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later
# Portions of this file may derive from GNUstep; see THIRD-PARTY.md.

# **THE MENU BAR'S USABLE REGION, AGAINST AGORA'S OWN SERVER** — the number an application cannot derive. It needs a
# compositor that speaks `agora_shell`, so it runs against `window-server` and SKIPS (77) without one.
set -u
BINARY="${1:?usage: run-menubar-area.sh PROBE WINDOW-SERVER}"
SERVER="${2:?}"
SOCK="agora-menubar-$$"
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
WAYLAND_DISPLAY="${SOCK}" timeout 20 "${BINARY}"
rc=$?
kill -TERM "${SPID}" 2>/dev/null; wait "${SPID}" 2>/dev/null; SPID=""
exit "${rc}"
