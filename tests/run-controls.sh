#!/bin/bash
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

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
#        run-controls.sh --gallery       # the GUI gallery (every remaining view and control class) at startup
#        run-controls.sh --gallery-bottom # the gallery scrolled to the drawer and the panel buttons
#        run-controls.sh --gallery-drawer # the gallery with its NSDrawer open
#        run-controls.sh --gallery-bottom --print-sheet   # the print panel AS A SHEET, without a click
#        run-controls.sh --no-playground # the Controls window itself, without the text window on top
#        run-controls.sh "" 1200x820 --data
#
#        run-controls.sh --gdb --gallery-bottom   # the same, with the CLIENT UNDER GDB (interactive)
#        run-controls.sh --gdb-batch --gallery-bottom  # ... and a backtrace printed for you when it dies
#
# **--gdb IS THE DOOR FOR A CRASH IN THE DEMONSTRATION**, and it changes nothing about the session: the same
# compositor, the same arguments, the same window — the client is simply started as gdb's inferior, with the
# library path and the display already in its environment (a `gdb --args` run by hand misses both). `--gdb-batch`
# is the same run without a prompt: gdb runs the program, and when it dies the backtrace of every thread is
# printed and gdb exits, so the report is a copy of the terminal.
#
#     ./tests/run-controls.sh --gdb-batch --gallery-bottom        # then click the button that crashes
#
# Both flags are the LAUNCHER's and are removed before the rest is handed to the demonstration.
#
# **THE DEMO'S OWN ARGUMENTS ARE FORWARDED**, so the split view can be looked at without a second launcher:
# `--data` opens the Table & Outline window at startup, and anything the demonstration does not recognise is
# ignored by it. A first argument beginning with `-` is a DEMO argument, not a server path, so `run-controls.sh
# --data` needs no empty placeholders.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

# **THE LAUNCHER'S OWN FLAGS COME OUT OF THE ARGUMENTS FIRST**, so that every form below — the bare demo arguments
# and the SERVER/GEOM form alike — sees what it saw before these existed. A debugger is a property of how the
# client is STARTED, not something the demonstration is told about, and its arguments are forwarded to the program
# unchanged.
GDB_MODE="off"
LAUNCH_ARGS=()
for arg in "$@"; do
	case "${arg}" in
	--gdb)       GDB_MODE="interactive" ;;
	--gdb-batch) GDB_MODE="batch" ;;
	*)           LAUNCH_ARGS+=("${arg}") ;;
	esac
done
if [ ${#LAUNCH_ARGS[@]} -gt 0 ]; then
	set -- "${LAUNCH_ARGS[@]}"
else
	set --
fi

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

GDB_COMMANDS="${RUNTIME}/agora-controls-gdb-$$.gdb"

cleanup() {
	[ -n "${SPID:-}" ] && kill "${SPID}" 2>/dev/null
	rm -f "${RUNTIME}/${SOCK}" "${RUNTIME}/${SOCK}.lock" "${GDB_COMMANDS}"
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
#
# **AND THE DISPLAY IS EXPORTED RATHER THAN PREFIXED WHEN A DEBUGGER RUNS THE CLIENT.** `WAYLAND_DISPLAY=x prog`
# sets the variable for one command; with gdb in between, the variable would be set for GDB and the INFERIOR would
# inherit it — which works — but only because gdb passes its environment down. Saying it out loud here is what
# keeps a hand-run `gdb --args` (which misses the display AND the library path) from looking like the same thing.
export WAYLAND_DISPLAY="${SOCK}"

# THE CLIENT AND ITS ARGUMENTS IN ONE ARRAY, because both routes below need the same list and an empty array must
# not become an empty ARGUMENT: `${ARR[@]}` unquoted in an `if` is the shape that turns "no arguments" into one
# empty one, which the demonstration would read as a path.
CLIENT=("${BIN}")
if [ ${#DEMO_ARGS[@]} -gt 0 ]; then
	CLIENT+=("${DEMO_ARGS[@]}")
fi

run_client_directly() {
	"${CLIENT[@]}"
}

run_client_under_gdb() {
	local mode="$1"
	local gdb

	gdb="$(command -v gdb || true)"
	if [ -z "${gdb}" ]; then
		echo "--gdb needs gdb on PATH, and there is none; running the demonstration directly instead." >&2
		run_client_directly
		return
	fi
	# **THE COMMANDS ARE A FILE RATHER THAN A PILE OF `-ex`, BECAUSE ONE OF THEM IS A BLOCK.** A backtrace should be
	# printed when the inferior DIES and not when it leaves normally — and gdb's `if` is a multi-line construct that
	# a string of `-ex` arguments cannot spell (MEASURED: it answers "This command cannot be used at the top level").
	# `$_siginfo` is set only for a signal, which is exactly the question. A BROKEN PIPE IS NOT A CRASH: a client
	# whose compositor goes away is stopped by SIGPIPE, and a debugger that halted on it would hide the fault that
	# was actually being looked for.
	cat >"${GDB_COMMANDS}" <<'GDB'
set pagination off
handle SIGPIPE nostop noprint pass
run
if $_siginfo
  echo \n=== the client died: backtrace of every thread ===\n
  bt full
  thread apply all bt
end
GDB
	if [ "${mode}" = "batch" ]; then
		# **NO PROMPT, AND THE TRACE IS THE POINT.** The commands above run to the end, so a crash prints every
		# thread's stack — which is what a report needs, without a person having to type anything at the moment the
		# window dies — and a normal exit prints nothing at all.
		"${gdb}" -batch -x "${GDB_COMMANDS}" --args "${CLIENT[@]}"
	else
		echo "the client is starting under gdb. Reproduce the fault; if it dies, the backtrace is already printed and" >&2
		echo "\`thread apply all bt full\` repeats it. \`quit\` ends the client, and the compositor with this session." >&2
		"${gdb}" -x "${GDB_COMMANDS}" --args "${CLIENT[@]}"
	fi
}

if [ "${GDB_MODE}" != "off" ]; then
	run_client_under_gdb "${GDB_MODE}"
else
	run_client_directly
fi
