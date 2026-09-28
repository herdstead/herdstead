#!/usr/bin/env bash
# Wait until no other windowed Godot is running, then return: a Godot window
# that another one covers can stop drawing frames on macOS, and a capture or a
# perf probe that waits for a frame then hangs until its watchdog kills it.
# tools/capture.sh and tools/perf.sh call
# it before every windowed step, and `make walk-strips` before it starts.
# Headless Godot processes (tests, imports) draw nothing and are ignored.
#
#   tools/wait_for_screen.sh [--timeout=SECONDS]   (default 1800; 0 = only look once)
#
# Exit 0 when the screen is free, 1 when another windowed Godot still runs
# after the timeout (named on stderr). The binary is found by the basename of
# $GODOT (default godot). Polls every 2 seconds and says once that it waits.
set -u

GODOT="${GODOT:-godot}"
TIMEOUT=1800
for argument in "$@"; do
	case "$argument" in
		--timeout=*) TIMEOUT="${argument#--timeout=}" ;;
		*)
			echo "WAIT_FOR_SCREEN: unknown argument $argument" >&2
			exit 2
			;;
	esac
done
case "$TIMEOUT" in
	'' | *[!0-9]*)
		echo "WAIT_FOR_SCREEN: --timeout takes whole seconds" >&2
		exit 2
		;;
esac
NAME="$(basename "$GODOT")"

# The windowed Godot processes running now, one "pid args" line each.
windowed() {
	local pid args
	for pid in $(pgrep -x "$NAME" 2>/dev/null); do
		args="$(ps -o args= -p "$pid" 2>/dev/null)" || continue
		[ -n "$args" ] || continue
		case " $args " in
			*" --headless "*) ;;
			*) echo "$pid $args" ;;
		esac
	done
}

waited=0
said=0
while :; do
	others="$(windowed)"
	[ -z "$others" ] && exit 0
	if [ "$waited" -ge "$TIMEOUT" ]; then
		echo "WAIT_FOR_SCREEN: another windowed Godot still runs after ${TIMEOUT}s:" >&2
		printf '%s\n' "$others" | cut -c1-200 >&2
		exit 1
	fi
	if [ "$said" -eq 0 ]; then
		echo "WAIT_FOR_SCREEN: waiting for another windowed Godot to finish:"
		printf '%s\n' "$others" | cut -c1-200
		said=1
	fi
	sleep 2
	waited=$((waited + 2))
done
