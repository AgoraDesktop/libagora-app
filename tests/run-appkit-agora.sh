#!/bin/bash
# The AppKit against AGORA'S OWN WINDOW SERVER, which is the only compositor that can answer `-visibleFrame`:
# a stock one has no furniture to subtract and says the whole screen. What this asserts is the RESERVE — the
# difference between the two frames — and, with it, the y-flip between the seam's top-down coordinates and
# Cocoa's bottom-up ones, because a reserve at the top has to come out as a work area that starts at the SAME
# bottom edge and is shorter.
#
# SKIPS (77) when there is no window server to run against, because a component's tests must not require a
# sibling's build to be present.
set -u

BINARY="${1:?usage: run-appkit-agora.sh APPkit-window WINDOW-SERVER [SECONDS] [RESERVE]}"
SERVER="${2:?}"
SECONDS_TO_RUN="${3:-3}"
RESERVE="${4:-24}"
SOCK="agora-appkit-agora-$$"
# The server's screenshot, which is how the strip is looked at rather than argued about.
SHOT="${AGORA_SCREENSHOT:-/tmp/agora-appkit-agora-$$.ppm}"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"

if [ ! -x "${SERVER}" ]; then
	echo "SKIP: no window server at ${SERVER}" >&2
	exit 77
fi

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
	# ONLY THE DEFAULT ONE IS REMOVED: a caller that named a path is asking to look at it.
	[ -n "${AGORA_SCREENSHOT:-}" ] || rm -f "${SHOT}"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"

"${SERVER}" --backend headless --input none --socket "${SOCK}" --frames 1000000 --screenshot "${SHOT}" \
	>/dev/null 2>/tmp/agora-appkit-agora-server.log &
SPID=$!
for _ in $(seq 1 50); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
[ -S "${RUNTIME}/${SOCK}" ] || { echo "SKIP: the server never came up" >&2; exit 77; }

output=$(WAYLAND_DISPLAY="${SOCK}" "${BINARY}" --seconds "${SECONDS_TO_RUN}" 2>&1)
# **THE SERVER IS STOPPED BY SIGNAL BEFORE ANYTHING IS ASSERTED, WHICH IS WHAT WRITES THE SCREENSHOT**: the signal
# stops the loop and the ordinary exit path runs. Left to the exit trap the shot would be written after the
# assertions, which is useless to them.
kill -TERM "${SPID}" 2>/dev/null
wait "${SPID}" 2>/dev/null
SPID=""
status=$?
echo "${output}" | grep -E "appkit_(window|status):"

line=$(printf '%s\n' "${output}" | grep -m1 "frame .* visibleFrame")
if [ -z "${line}" ]; then
	echo "FAIL: the client said nothing about the work area" >&2
	exit 1
fi
whole=$(printf '%s\n' "${line}" | sed -n 's/.*frame \([0-9.]*\)x\([0-9.]*\),.*/\2/p')
# **AND THE OTHER DOOR ONTO THE RESERVE**: `NSStatusBar -thickness` is the same number by a different route, so the
# script asserts the SECOND as well — two answers that agree are worth more than one asserted twice.
thickness=$(printf '%s\n' "${output}" | sed -n 's/.*appkit_status: the bar is \([0-9.]*\) tall.*/\1/p')
work=$(printf '%s\n' "${line}" | sed -n 's/.*visibleFrame \([0-9.]*\)x\([0-9.]*\).*/\2/p')
if [ -z "${whole}" ] || [ -z "${work}" ]; then
	echo "FAIL: could not read the two frames out of '${line}'" >&2
	exit 1
fi
reserved=$(awk -v a="${whole}" -v b="${work}" 'BEGIN { printf "%d", a - b }')
if [ "${reserved}" != "${RESERVE}" ]; then
	echo "FAIL: the work area reserves ${reserved}, want ${RESERVE} (frame ${whole}, visibleFrame ${work})" >&2
	exit 1
fi

# AND THE STATUS, not only the numbers: an impossible work area fails the client itself.
if [ "${status}" -ne 0 ]; then
	echo "FAIL: the client exited ${status}" >&2
	exit 1
fi
if [ "${thickness}" != "${RESERVE}" ]; then
	echo "FAIL: NSStatusBar's thickness is '${thickness}', want ${RESERVE} — the two doors disagree" >&2
	exit 1
fi
echo "ok: the work area reserves ${reserved} of ${whole} — the menu bar"
echo "ok: and NSStatusBar -thickness agrees — ${thickness}, the same number by a second route"
exit 0
