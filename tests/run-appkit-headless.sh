#!/bin/bash
# The AppKit's own test: a real NSWindow under a headless compositor. Exit 77 means SKIP, and the assertion is
# that the view was asked to draw at least once — which cannot happen until the compositor has configured the
# window, so a zero count means the whole path is broken rather than slow.
set -u

BINARY="${1:?usage: run-appkit-headless.sh BINARY [SECONDS]}"
SECONDS_TO_RUN="${2:-3}"
DISP="agora-appkit-$$"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"

if ! command -v gnome-shell >/dev/null 2>&1; then
	echo "SKIP: no Wayland compositor on this machine (gnome-shell not found)" >&2
	exit 77
fi

cleanup() {
	pkill -TERM -f -- "--wayland-display=${DISP}" 2>/dev/null
	[ -n "${GS:-}" ] && kill -TERM "-${GS}" 2>/dev/null
	[ -n "${GS:-}" ] && kill "${GS}" 2>/dev/null
	rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${DISP}" "${RUNTIME}/${DISP}.lock"

setsid timeout 90 dbus-run-session -- gnome-shell --headless --wayland \
	--wayland-display="${DISP}" --virtual-monitor 1280x720 >/tmp/agora-appkit-compositor.log 2>&1 &
GS=$!
for _ in $(seq 1 60); do
	[ -S "${RUNTIME}/${DISP}" ] && break
	sleep 1
done
if [ ! -S "${RUNTIME}/${DISP}" ]; then
	echo "SKIP: the compositor never created a socket" >&2
	exit 77
fi
sleep 3

output=$(WAYLAND_DISPLAY="${DISP}" "${BINARY}" --seconds "${SECONDS_TO_RUN}" 2>&1)
status=$?
echo "${output}"

if [ "${status}" -ne 0 ]; then
	echo "FAIL: the AppKit test exited ${status}" >&2
	exit 1
fi
drew=$(printf '%s\n' "${output}" | sed -n 's/.*drew \([0-9]*\) frame(s).*/\1/p' | tail -1)
if [ -z "${drew}" ] || [ "${drew}" -eq 0 ]; then
	echo "FAIL: the view was never asked to draw" >&2
	exit 1
fi
echo "ok: the AppKit drew ${drew} frame(s) through a real NSWindow"
exit 0
