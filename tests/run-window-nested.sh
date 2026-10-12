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

# -----------------------------------------------------------------------------------------------------------
# THIS TAKES OVER THE DESKTOP'S POINTER WHILE IT RUNS, SO IT IS OPT-IN RATHER THAN PART OF A TEST RUN.
#
# `gnome-shell --nested` is a whole nested desktop session, and it grabs the HOST's pointer to route input into
# itself. On a real desktop that means the person at the keyboard loses their mouse buttons for as long as it
# lives -- measured: after a nested run the host was left with an ACTIVE POINTER GRAB (XGrabPointer answered
# AlreadyGrabbed, while the keyboard grab was free, which is exactly "the cursor moves and the buttons do
# nothing"). That is a bad neighbour for a script, so this one asks first.
# -----------------------------------------------------------------------------------------------------------
if [ "${AGORA_ALLOW_NESTED:-}" != "1" ]; then
	cat >&2 <<'WARN'
SKIP: the nested run takes over THIS DESKTOP's pointer while it lives, and a nested session that does not
      unwind leaves the host with a stuck pointer grab -- the cursor moves and the buttons stop working.
      Run it knowingly with:   AGORA_ALLOW_NESTED=1 $0 [args]
      (A stuck grab is cleared with Alt+F2, then r, then Enter -- it restarts GNOME Shell in place.)
WARN
	exit 77
fi
echo "NOTE: this run will take over the pointer of the desktop you are sitting at." >&2

for tool in gnome-shell import; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "SKIP: $tool is needed for this test" >&2
		exit 77
	fi
done

cleanup() {
	pkill -TERM -f -- "--wayland-display=${DISP}" 2>/dev/null
	[ -n "${CL:-}" ] && kill "${CL}" 2>/dev/null
	[ -n "${GS:-}" ] && kill -TERM "-${GS}" 2>/dev/null
	[ -n "${GS:-}" ] && kill "${GS}" 2>/dev/null
	sleep 1

	# AND THE ONE THING THAT MUST NOT BE LEFT BEHIND: a nested compositor still holding the host's pointer. The
	# kill above is by display name; THIS checks that it took, because a grab outlives the script that made it
	# and the machine it is left on is somebody's desktop. Escalate rather than hope.
	if pgrep -f -- "--wayland-display=${DISP}" >/dev/null 2>&1; then
		pkill -KILL -f -- "--wayland-display=${DISP}" 2>/dev/null
		sleep 1
		if pgrep -f -- "--wayland-display=${DISP}" >/dev/null 2>&1; then
			echo "WARNING: a nested compositor SURVIVED (wayland-display=${DISP}) and may hold the pointer." >&2
			echo "         Clear it with:  Alt+F2, then r, then Enter   (restarts GNOME Shell in place)." >&2
		fi
	fi
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
