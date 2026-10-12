#!/bin/bash
# The AppKit's PIXEL test: a real NSWindow inside a NESTED compositor on the desktop (so it is visible), two
# screenshots a second apart, read back by inspect.py. A headless run can only count frames; this one proves
# the pixels a real NSView drew reached an output.
set -u

BINARY="${1:?usage: run-appkit-nested.sh BINARY}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DISP="agora-appkit-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
export DISPLAY="${DISPLAY:-:1}"

for tool in gnome-shell import; do
	command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool is needed for this test" >&2; exit 77; }
done

cleanup() {
	pkill -TERM -f -- "--wayland-display=${DISP}" 2>/dev/null
	[ -n "${CL:-}" ] && kill "${CL}" 2>/dev/null
	[ -n "${GS:-}" ] && kill -TERM "-${GS}" 2>/dev/null
	[ -n "${GS:-}" ] && kill "${GS}" 2>/dev/null
	rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock" /tmp/agora-appkit-A.png /tmp/agora-appkit-B.png

setsid dbus-run-session -- gnome-shell --nested --wayland --wayland-display="${DISP}" --no-x11 \
	>/tmp/agora-appkit-nested-compositor.log 2>&1 &
GS=$!
for _ in $(seq 1 60); do
	[ -S "${RUNTIME}/${DISP}" ] && break
	sleep 1
done
[ -S "${RUNTIME}/${DISP}" ] || { echo "SKIP: the nested compositor never came up" >&2; exit 77; }
sleep 6

WAYLAND_DISPLAY="${DISP}" "${BINARY}" --seconds 20 --width 720 --height 460 \
	>/tmp/agora-appkit-nested-window.log 2>&1 &
CL=$!
sleep 10

import -display "${DISPLAY}" -window root /tmp/agora-appkit-A.png
sleep 1.2
import -display "${DISPLAY}" -window root /tmp/agora-appkit-B.png
cat /tmp/agora-appkit-nested-window.log

python3 "${HERE}/inspect.py" /tmp/agora-appkit-A.png /tmp/agora-appkit-B.png
