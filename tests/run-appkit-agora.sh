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
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"

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
	>/dev/null 2>/tmp/agora-appkit-agora-server.log &
SPID=$!
for _ in $(seq 1 50); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
[ -S "${RUNTIME}/${SOCK}" ] || { echo "SKIP: the server never came up" >&2; exit 77; }

output=$(WAYLAND_DISPLAY="${SOCK}" "${BINARY}" --seconds "${SECONDS_TO_RUN}" 2>&1)
status=$?
echo "${output}" | grep -E "appkit_window:"

line=$(printf '%s\n' "${output}" | grep -m1 "frame .* visibleFrame")
if [ -z "${line}" ]; then
	echo "FAIL: the client said nothing about the work area" >&2
	exit 1
fi
whole=$(printf '%s\n' "${line}" | sed -n 's/.*frame \([0-9.]*\)x\([0-9.]*\),.*/\2/p')
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
echo "ok: the work area reserves ${reserved} of ${whole} — the menu bar"
exit 0
