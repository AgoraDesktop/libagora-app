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
# Usage: run-controls.sh [WINDOW-SERVER] [WIDTHxHEIGHT]
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SERVER="${1:-${HERE}/../../window-server/build/window-server}"
GEOM="${2:-900x600}"
W="${GEOM%x*}"
H="${GEOM#*x}"
BIN="${HERE}/../build/tests/appkit_controls_draw"
SOCK="agora-controls-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
DISPLAY="${DISPLAY:-:1}"

# The AppKit and its Foundation live in the workspace's install prefix, and DT_RUNPATH is NOT inherited by a
# transitive dependency — so the client needs the prefix on its library path, the same reason the tests set it.
PREFIX="$(cd "${HERE}/../.." && pwd)/build-prefix/lib"
export LD_LIBRARY_PATH="${PREFIX}:${LD_LIBRARY_PATH:-}"

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
WAYLAND_DISPLAY="${SOCK}" "${BIN}"
