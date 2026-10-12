#!/bin/bash
# The seam's PIXEL test: a nested compositor on the X11 desktop (so the window is visible), two captured
# screenshots a second apart, and inspect.py reads the pixels back out.
#
# WHY THIS IS SEPARATE FROM THE ctest. A headless run can only assert the frame COUNT — it composites
# nothing, so it cannot say whether the pixels reached an output. This one photographs the compositing that
# actually happened, which is the half a frame count cannot see. It needs a desktop and a screenshot tool,
# so it is a script a person runs, not a test the build runs.
#
# Usage: run-window-nested.sh BINARY
set -u

BINARY="${1:?usage: run-window-nested.sh BINARY}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DISP="agora-nested-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
export DISPLAY="${DISPLAY:-:1}"

for tool in gnome-shell import; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "SKIP: $tool is needed for this test" >&2
		exit 77
	fi
done

cleanup() {
	# The display name is the reliable handle: `setsid` forks when it is already a process-group leader, so
	# its pid is not always the group's, and a leaked compositor keeps a socket and a CPU.
	pkill -TERM -f -- "--wayland-display=${DISP}" 2>/dev/null
	[ -n "${CL:-}" ] && kill "${CL}" 2>/dev/null
	[ -n "${GS:-}" ] && kill -TERM "-${GS}" 2>/dev/null
	[ -n "${GS:-}" ] && kill "${GS}" 2>/dev/null
	rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock" /tmp/agora-window-A.png /tmp/agora-window-B.png

setsid dbus-run-session -- gnome-shell --nested --wayland --wayland-display="${DISP}" --no-x11 \
	>/tmp/agora-app-nested-compositor.log 2>&1 &
GS=$!
for _ in $(seq 1 60); do
	[ -S "${RUNTIME}/${DISP}" ] && break
	sleep 1
done
[ -S "${RUNTIME}/${DISP}" ] || { echo "SKIP: the nested compositor never came up" >&2; exit 77; }
sleep 6

WAYLAND_DISPLAY="${DISP}" "${BINARY}" --title "Agora AppKit" --width 720 --height 460 \
	>/tmp/agora-app-nested-window.log 2>&1 &
CL=$!
sleep 8

import -display "${DISPLAY}" -window root /tmp/agora-window-A.png
sleep 1.2
import -display "${DISPLAY}" -window root /tmp/agora-window-B.png
cat /tmp/agora-app-nested-window.log

python3 "${HERE}/inspect.py" /tmp/agora-window-A.png /tmp/agora-window-B.png
