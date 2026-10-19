#!/bin/bash
# The CONTROLS demonstration, on a display, nested inside the desktop you are sitting at — for LOOKING at and
# iterating on the window chrome and its theme, rather than for asserting anything.
#
# **AGORA'S OWN WINDOW SERVER IS THE NESTED COMPOSITOR, AND IT GRABS NOTHING.** Its X11 backend opens an ordinary
# X window — no `XGrabPointer`, no `XGrabKeyboard` — and `--input host` routes the pointer and keyboard that THIS
# WINDOW is given. So unlike a nested `gnome-shell` (`run-appkit-nested.sh`) it cannot take the desktop's pointer
# away, and it needs no opt-in gate: this is safe to run and leave open.
#
# **THE THEME IS THE DEMONSTRATION'S DEFAULT.** `appkit_controls_draw` points `AGORA_CHROME_THEME` at the tree's
# own `themes/` when a caller has not, so a theme placed there is what you see. `AGORA_CHROME_THEME` overrides it:
#
#     AGORA_CHROME_THEME=/path/to/theme ./tests/run-controls.sh
#
# Usage: run-controls.sh [WINDOW-SERVER] [WIDTHxHEIGHT] [DEMO-ARG...]
#        run-controls.sh --data          # the Table & Outline window at startup
#        run-controls.sh "" 1200x820 --data
#
# **THE DEMO'S OWN ARGUMENTS ARE FORWARDED**, so the split view can be looked at without a second launcher:
# `--data` opens the Table & Outline window at startup, and anything the demonstration does not recognise is
# ignored by it. A first argument beginning with `-` is a DEMO argument, not a server path, so `run-controls.sh
# --data` needs no empty placeholders.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
DEMO_ARGS=()
if [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; then
	SERVER="${HERE}/../../window-server/build/window-server"
	GEOM="900x600"
	DEMO_ARGS=("$@")
else
	SERVER="${1:-${HERE}/../../window-server/build/window-server}"
	GEOM="${2:-900x600}"
	if [ $# -ge 2 ]; then
		shift 2
	elif [ $# -eq 1 ]; then
		shift 1
	fi
	DEMO_ARGS=("$@")
fi
W="${GEOM%x*}"
H="${GEOM#*x}"
BIN="${HERE}/../build/tests/appkit_controls_draw"
SOCK="agora-controls-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
DISPLAY="${DISPLAY:-:1}"

# The AppKit and its Foundation live in the workspace's install prefix, and DT_RUNPATH is NOT inherited by a
# transitive dependency — so the client needs the prefix on its library path, the same reason the tests set it.
# **AND THE BUILD TREE COMES FIRST**, because the prefix also carries an INSTALLED `libagora-app.so`: without
# this the demonstration can load the old copy and miss the class it was just built to show. MEASURED in the
# tests, which had the same ordering bug and loaded the prefix's AppKit while testing the source tree.
BUILD_LIB="$(cd "${HERE}/../build" && pwd)"
PREFIX="$(cd "${HERE}/../.." && pwd)/build-prefix/lib"
export LD_LIBRARY_PATH="${BUILD_LIB}:${PREFIX}:${LD_LIBRARY_PATH:-}"

[ -x "${SERVER}" ] || { echo "no window server at ${SERVER}" >&2; exit 1; }
[ -x "${BIN}" ] || { echo "nothing to run at ${BIN} — build the AppKit first" >&2; exit 1; }

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
}
trap cleanup EXIT INT TERM
rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"

DISPLAY="${DISPLAY}" "${SERVER}" --backend x11 --input host --socket "${SOCK}" \
	--frames 1000000 --width "${W}" --height "${H}" >/tmp/agora-controls-server.log 2>&1 &
SPID=$!
for _ in $(seq 1 100); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
if [ ! -S "${RUNTIME}/${SOCK}" ]; then
	echo "the server never came up; /tmp/agora-controls-server.log:" >&2
	cat /tmp/agora-controls-server.log >&2
	exit 1
fi
echo "Agora's compositor is open on ${DISPLAY} as an ordinary window." >&2
echo "Close that window (or Ctrl-C here) to stop it." >&2

# IN THE FOREGROUND, so Ctrl-C reaches the client too and the trap runs when it exits. The client prints which
# theme resolved, its strip height, and the window's geometry — which is what iterating on a theme wants to see.
if [ ${#DEMO_ARGS[@]} -gt 0 ]; then
	WAYLAND_DISPLAY="${SOCK}" "${BIN}" "${DEMO_ARGS[@]}"
else
	WAYLAND_DISPLAY="${SOCK}" "${BIN}"
fi
