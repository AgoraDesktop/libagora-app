#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# The GPU seam against AGORA'S OWN WINDOW SERVER: a GL frame is rendered offscreen, read back, presented into a
# window, and the COMPOSITED screenshot is what gets asserted.
#
# WHY THE SCREENSHOT AND NOT ONLY THE CLIENT'S OWN VERDICT. The client verifies its readback — the four colours, so a
# flipped Y fails here — but a present path that wrote to the right place in the wrong buffer, or damaged a rectangle
# of zero size, would satisfy every check inside the process and still show a blue window. So the server writes the
# frame it actually composited and this script samples it. The two halves are the point: readback correct, present
# correct.
#
# THE WINDOW IS PLACED AT Y=32 so that it clears the menu bar's strip, and every sample is at least 16 device pixels
# inside the window so rounded corners and the shadow cannot reach it.
#
# SKIPS (77) when there is no window server to run against or no GPU context on this machine — a component's tests must
# not require a sibling's build, and a machine with no EGL device is not a failure of this code.
set -u

BINARY="${1:?usage: run-gl-present.sh BINARY WINDOW-SERVER [FRAMES]}"
SERVER="${2:?}"
FRAMES="${3:-20}"
SOCK="agora-gl-present-$$"
SHOT="${AGORA_SCREENSHOT:-/tmp/agora-gl-present-$$.ppm}"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SCREEN_W=320
SCREEN_H=240
WIN_W=200
WIN_H=120
WIN_Y=32

if [ ! -x "${SERVER}" ]; then
	echo "SKIP: no window server at ${SERVER}" >&2
	exit 77
fi
if ! command -v python3 >/dev/null 2>&1; then
	echo "SKIP: python3 is needed to read the screenshot" >&2
	exit 77
fi

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	[ -n "${SPID:-}" ] && wait "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"
	# ONLY THE DEFAULT ONE IS REMOVED: a caller that named a path is asking to look at it.
	[ -n "${AGORA_SCREENSHOT:-}" ] || rm -f "${SHOT}"
}
trap cleanup EXIT

rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock"

"${SERVER}" --backend headless --input none --socket "${SOCK}" --width "${SCREEN_W}" --height "${SCREEN_H}" \
	--frames 1000000 --screenshot "${SHOT}" >/dev/null 2>/tmp/agora-gl-present-server.log &
SPID=$!
for _ in $(seq 1 50); do
	[ -S "${RUNTIME}/${SOCK}" ] && break
	sleep 0.1
done
[ -S "${RUNTIME}/${SOCK}" ] || { echo "SKIP: the server never came up" >&2; exit 77; }

# **THE CLIENT STAYS ALIVE UNTIL THE SERVER IS STOPPED, AND THAT IS NOT A DETAIL.** The screenshot is written on the
# server's ordinary exit path, and a client that exits first destroys its window — so the last thing the server
# composites is the desktop, and a test that ran the client to completion would photograph an empty screen and call it
# a pass. MEASURED, in the first version of this script: 20 frames presented, every colour check inside the client
# green, and the screenshot a plain background. So the client is run in the background with an unending frame budget,
# this script waits for the readback line, and the SERVER is what ends the run.
LOG=/tmp/agora-gl-present-client-$$.log
WAYLAND_DISPLAY="${SOCK}" "${BINARY}" --x 0 --y "${WIN_Y}" --width "${WIN_W}" --height "${WIN_H}" \
	--frames 1000000 >"${LOG}" 2>&1 &
CPID=$!
for _ in $(seq 1 100); do
	grep -q "gl_present: readback ok" "${LOG}" 2>/dev/null && break
	kill -0 "${CPID}" 2>/dev/null || break
	sleep 0.1
done
# A few more frames, so the screenshot is a steady state and not the first present.
sleep 0.5

# **THE SERVER IS STOPPED BY SIGNAL BEFORE THE CLIENT'S OUTPUT IS READ, WHICH IS WHAT WRITES THE SCREENSHOT**: the
# signal stops the loop and the ordinary exit path runs. The client then sees its connection close, ends its own loop,
# and only then flushes the frame count this script asserts.
kill -TERM "${SPID}" 2>/dev/null
wait "${SPID}" 2>/dev/null
SPID=""
wait "${CPID}" 2>/dev/null
status=$?
output=$(cat "${LOG}" 2>/dev/null)
rm -f "${LOG}"

if ! printf '%s\n' "${output}" | grep -q "gl_present: readback ok"; then
	if printf '%s\n' "${output}" | grep -q "no GPU context"; then
		echo "SKIP: no GPU context on this machine" >&2
		exit 77
	fi
	echo "${output}" >&2
	echo "FAIL: the client never read a frame back" >&2
	exit 1
fi

echo "${output}"

if [ "${status}" -eq 77 ]; then
	echo "SKIP: no GPU context on this machine" >&2
	exit 77
fi
if [ "${status}" -ne 0 ]; then
	echo "FAIL: the client exited ${status}" >&2
	exit 1
fi
presented=$(printf '%s\n' "${output}" | sed -n 's/.*gl_present: \([0-9]*\) frame(s) presented/\1/p' | tail -1)
closed_after=$(printf '%s\n' "${output}" | sed -n 's/.*closed the connection after \([0-9]*\) frame(s)/\1/p' | tail -1)
frames=${presented:-${closed_after:-none}}
if [ "${frames}" = "none" ] || [ "${frames}" -lt 1 ]; then
	echo "FAIL: no frame reached the compositor" >&2
	exit 1
fi
if ! printf '%s\n' "${output}" | grep -q "gl_present: dmabuf round trip ok"; then
	# Not a failure: a driver with no export path still presents frames, and the client says so. The important
	# half — descriptor to picture — is asserted when the machine can do it.
	echo "note: this machine cannot export a texture to a descriptor; the import half went untested"
fi

python3 - "${SHOT}" "${WIN_W}" "${WIN_H}" "${WIN_Y}" <<'PY'
import sys

path, win_w, win_h, win_y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])

with open(path, 'rb') as handle:
    data = handle.read()

# A binary PPM: P6, then whitespace-separated fields, then ONE whitespace byte, then the pixels.
fields = []
at = 0
if data[:2] != b'P6':
    sys.exit(f'FAIL: {path} is not a binary PPM')
at = 2
while len(fields) < 3:
    while at < len(data) and data[at:at + 1].isspace():
        at += 1
    if data[at:at + 1] == b'#':
        while at < len(data) and data[at:at + 1] != b'\n':
            at += 1
        continue
    start = at
    while at < len(data) and not data[at:at + 1].isspace():
        at += 1
    fields.append(int(data[start:at]))
at += 1
width, height, _maxval = fields
pixels = data[at:]

def sample(x, y):
    index = (y * width + x) * 3
    return tuple(pixels[index:index + 3])

# The client's own layout, in its device pixels: a green bar 20 rows from the top, a yellow one 20 rows from the
# bottom, both 40x20 with a 16-pixel inset, on blue. The window's origin is (0, win_y) on this output.
def at_window(x, y):
    return sample(x, win_y + y)

checks = [
    ('the top bar', at_window(16 + 20, 20 + 10), (0, 255, 0)),
    ('below the top bar', at_window(16 + 20, 20 + 20 + 12), (0, 0, 255)),
    ('the bottom bar', at_window(win_w - 16 - 20, win_h - 20 - 10), (255, 255, 0)),
    ('the middle', at_window(win_w // 2, win_h // 2 - 4), (0, 0, 255)),
]
failed = False
for name, got, want in checks:
    if got != want:
        print(f'FAIL: {name} is {got} in the composited frame, want {want}', file=sys.stderr)
        failed = True
if failed:
    print(f'      (the screenshot is {path}, {width}x{height})', file=sys.stderr)
    sys.exit(1)
print('ok: the composited frame carries the GPU frame — green above, yellow below, blue elsewhere')
PY
check=$?
if [ "${check}" -ne 0 ]; then
	exit 1
fi

echo "ok: ${frames} GPU frame(s) reached the glass through the seam"
exit 0
