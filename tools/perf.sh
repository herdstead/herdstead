#!/usr/bin/env bash
# What the live office costs while it sits in a window: CPU, frame rate, node
# count, draw calls and the cost of one refresh, against a fake herdr serving
# synthetic sessions (tools/gen_stress_fixture.py). `make perf` runs it.
#
#   tools/perf.sh [--runs=3] [--figures] [--walks] [--hold=8] [--warmup=6]
#   GODOT=/path/to/godot tools/perf.sh --runs=5
#
# Scenarios: medium (3 floors, 36 panes), stress (1 floor, 10 tabs x 8 panes)
# and overview (the stress floor in a 3200x1600 window at 2x, zoomed out: the
# whole floor on screen, in a window a 3456-pixel-wide laptop display still
# holds; a display too small for it is said
# on a PERF_SHRUNK line under the summary); stress+overview (the stress floor
# with the OVERVIEW open over it, `--overview=open`: 80 rows and timelines;
# the `overview` scenario above is the zoomed-out floor, not this); stress+lens
# (the stress floor with the lens held, `--lens=held`: 80 lines, 10 washes,
# the furnishing dimmed, the lines rewritten every 0.25 s); stress+strategic
# (the stress floor under the strategic view, `--strategic=open`: 80 squares
# and 10 captions in one CanvasItem, drawn again each second while a wait
# shows); stress400, stress400+drawer and stress400+strategic (1 floor, 50 tabs
# x 8 panes: the world, the world with the agent list's drawer open,
# `--drawer=open`, so its 400 rows stay on the measured path while a closed
# drawer skips them, and the view over it);
# --figures adds 80 seated pixel people on their own, every one on screen; --walks
# adds the stress floor's people walking (tools/perf_probe.gd --walk=): 80 walk
# in at once, 40 are done at once (seated, with paper), a table grows
# under 80 walking in, and the window is minimized and restored mid-walk, and
# 40 go blocked (seated under bubbles) or idle at once, one
# of 40 blocked is answered again and again, and a table grows under 40
# blocked, each timed frame by frame from the
# snapshot that starts it, which the probe sets through the fake herdr's
# control socket. Every round
# runs each scenario twice, paced (the default) and with --fps=0 (uncapped, as
# before the pacer), and the rounds interleave, so drift lands on both columns.
# Each figure in the summary is the median over --runs rounds.
#
# Before every probe it waits until no other windowed Godot runs
# (tools/wait_for_screen.sh): a covered window can stop drawing on macOS. It
# imports the project first when Godot's import cache is behind assets/
# (tools/import_if_stale.sh).
#
# Windowed only, and part of neither `make check` nor CI: a headless run draws
# nothing, and CPU depends on the machine and on whatever else it is running.
# A focused window paces itself at 30 fps and one in the background at 12, so
# max_fps says which of the two a run measured. CPU is the Godot process's own
# time over --hold seconds: from /proc on Linux, from ps(1) elsewhere (macOS).
set -u

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -x "$ROOT/.venv/bin/python" ]; then
	DEFAULT_PYTHON="$ROOT/.venv/bin/python"
else
	DEFAULT_PYTHON="python3"
fi
PYTHON="${PYTHON:-$DEFAULT_PYTHON}"
RUNS=3
FIGURES=0
WALKS=0
HOLD=8
WARMUP=6
for argument in "$@"; do
	case "$argument" in
		--runs=*) RUNS="${argument#--runs=}" ;;
		--figures) FIGURES=1 ;;
		--walks) WALKS=1 ;;
		--hold=*) HOLD="${argument#--hold=}" ;;
		--warmup=*) WARMUP="${argument#--warmup=}" ;;
		*)
			echo "PERF: unknown argument $argument" >&2
			exit 2
			;;
	esac
done
for number in "$RUNS" "$HOLD" "$WARMUP"; do
	case "$number" in
		'' | *[!0-9]* | 0)
			echo "PERF: --runs, --hold and --warmup take whole numbers above 0" >&2
			exit 2
			;;
	esac
done
if [ "$(uname -s)" = "Linux" ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
	echo "PERF: needs a display; a headless run draws nothing to measure" >&2
	exit 2
fi

GODOT="$GODOT" bash "$ROOT/tools/import_if_stale.sh" || {
	echo "PERF: the project would not import" >&2
	exit 2
}

# Unix socket paths stop at ~104 bytes on macOS: keep them short, under /tmp.
WORK="$(mktemp -d /tmp/herdstead-perf.XXXXXX)"
SERVER_PID=""
GODOT_PID=""

stop() {
	if [ -n "$1" ] && kill -0 "$1" 2>/dev/null; then
		kill "$1" 2>/dev/null
		wait "$1" 2>/dev/null
	fi
}

cleanup() {
	stop "$GODOT_PID"
	stop "$SERVER_PID"
	rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

"$PYTHON" "$ROOT/tools/gen_stress_fixture.py" --output "$WORK/fixtures" >/dev/null || exit 2

# The CPU time a process has used so far, in seconds.
cpu_seconds() {
	if [ -r "/proc/$1/stat" ]; then
		awk -v tick="$(getconf CLK_TCK)" '{ print ($14 + $15) / tick }' "/proc/$1/stat"
	else
		# [[dd-]hh:]mm:ss.cc; nothing here runs for a day.
		ps -o time= -p "$1" | awk -F: '{ total = 0; for (i = 1; i <= NF; i++) total = total * 60 + $i; print total }'
	fi
}

# A fake herdr serving one generated fixture, up once both sockets listen.
start_fake() {
	rm -f "$WORK/herdr.sock" "$WORK/herdr-ctl.sock"
	"$PYTHON" "$ROOT/tools/fake_herdr.py" --socket="$WORK/herdr.sock" --control="$WORK/herdr-ctl.sock" \
		--fixtures="$WORK/fixtures" --fixture="$1" >/dev/null 2>&1 &
	SERVER_PID=$!
	for _ in $(seq 1 100); do
		[ -S "$WORK/herdr.sock" ] && [ -S "$WORK/herdr-ctl.sock" ] && return 0
		sleep 0.05
	done
	echo "PERF: fake herdr never came up" >&2
	return 1
}

# One probe run, into RESULT: `cpu=<percent>` and the probe's own fields. Not
# called in a subshell, so the traps above always know what to stop.
RESULT=""
measure() {
	local mode="$1" fixture="$2" pacing="$3" name="$4"
	local log="$WORK/probe.log"
	local args=(--warmup="$WARMUP" --hold="$((HOLD + 1))")
	# Engine arguments go before --script; the probe's own go after --.
	local engine=()
	if [ "$mode" = "walks" ]; then
		args+=(--mode=office --walk="$name" --control="$WORK/herdr-ctl.sock")
	elif [ "$mode" = "office-overview" ]; then
		args+=(--mode=office --overview=open)
	elif [ "$mode" = "office-lens" ]; then
		# The office reads the process's command line: `--lens=held` holds the
		# lens from the start, its lines ticking every 0.25 s.
		args+=(--mode=office --lens=held)
	elif [ "$mode" = "office-strategic" ]; then
		# The same way, `--strategic=open` opens the strategic view at start.
		args+=(--mode=office --strategic=open)
	elif [ "$mode" = "office-drawer" ]; then
		# `--drawer=open` starts with the agent list's drawer open (a closed
		# drawer renders no rows, so this is where their cost is measured).
		args+=(--mode=office --drawer=open)
	elif [ "$mode" = "overview" ]; then
		# The stress floor in a big window at the lowest zoom (2x): the whole
		# floor on screen, as zoom 1 showed it before.
		engine+=(--resolution 3200x1600)
		args+=(--mode=office --zoom=2)
	else
		args+=(--mode="$mode")
	fi
	if [ "$mode" = "office" ] || [ "$mode" = "walks" ] || [ "$mode" = "overview" ] || [ "$mode" = "office-overview" ] \
		|| [ "$mode" = "office-lens" ] || [ "$mode" = "office-strategic" ] || [ "$mode" = "office-drawer" ]; then
		start_fake "$fixture" || return 1
		# Read-only, like every baseline before the write boundary: the agent
		# card's terminal preview would add reads the older runs never made.
		# No Dock bounce: a measuring run sits in the background while the fake flips states.
		# A plain window: a measurement is taken in the window it asked for, never a maximized one.
		args+=(--socket="$WORK/herdr.sock" --pack=res://assets/daylight/manifest.json --read-only --no-bounce --window=plain)
	else
		args+=(--count=80)
	fi
	[ "$pacing" = "fps0" ] && args+=(--fps=0)
	GODOT="$GODOT" bash "$ROOT/tools/wait_for_screen.sh" || {
		echo "PERF: another windowed Godot never finished" >&2
		return 1
	}
	# Nothing here reaches the operator's own herdr, machines or SSH tunnels.
	HERDR_BIN_PATH="$WORK/no-herdr" HERDSTEAD_SOCKET_DIR="$WORK/socks" \
		"$GODOT" --path "$ROOT" ${engine[@]+"${engine[@]}"} --script tools/perf_probe.gd -- "${args[@]}" >"$log" 2>&1 &
	GODOT_PID=$!
	local ticks=0
	until grep -q '^PERF_HOLD' "$log"; do
		ticks=$((ticks + 1))
		if ! kill -0 "$GODOT_PID" 2>/dev/null || [ "$ticks" -gt $(((WARMUP + 30) * 5)) ]; then
			echo "PERF: the probe never settled:" >&2
			cat "$log" >&2
			return 1
		fi
		sleep 0.2
	done
	local before after
	before="$(cpu_seconds "$GODOT_PID")"
	sleep "$HOLD"
	after="$(cpu_seconds "$GODOT_PID")"
	ticks=0
	while kill -0 "$GODOT_PID" 2>/dev/null && [ "$ticks" -lt 300 ]; do
		ticks=$((ticks + 1))
		sleep 0.2
	done
	stop "$GODOT_PID"
	GODOT_PID=""
	stop "$SERVER_PID"
	SERVER_PID=""
	local result
	result="$(grep -m1 '^PERF_RESULT ' "$log")"
	if [ -z "$result" ] || grep -qE 'SCRIPT ERROR|Parse Error' "$log"; then
		echo "PERF: the probe failed:" >&2
		cat "$log" >&2
		return 1
	fi
	# A display too small for the window asked shrinks it, and the run measures
	# a smaller view: said under the summary, so the figure is never mistaken
	# for the one asked.
	if [ "${#engine[@]}" -gt 0 ] && [ "$(field "$result" window)" != "${engine[1]}" ]; then
		echo "$name asked for a ${engine[1]} window, the OS made it $(field "$result" window): its figures are for that smaller view" >>"$WORK/shrunk"
	fi
	RESULT="$(awk -v a="$before" -v b="$after" -v s="$HOLD" 'BEGIN { printf "cpu=%.1f", (b - a) / s * 100 }')"
	RESULT="$RESULT ${result#PERF_RESULT }"
}

# The value of `name=` in a line of fields.
field() {
	printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"
}

median() {
	sort -n | awk '{ v[NR] = $1 } END {
		if (NR == 0) print "-"
		else if (NR % 2) print v[(NR + 1) / 2]
		else print (v[NR / 2] + v[NR / 2 + 1]) / 2
	}'
}

# name, mode, fixture, then what it is
SCENARIOS=("medium office snapshot_medium 3 floors, 36 panes" "stress office snapshot_stress80 1 floor, 80 panes"
	"overview overview snapshot_stress80 the same, 3200x1600"
	"stress+overview office-overview snapshot_stress80 1 floor, 80 panes, OVERVIEW open"
	"stress+lens office-lens snapshot_stress80 1 floor, 80 panes, the lens held"
	"stress+strategic office-strategic snapshot_stress80 1 floor, 80 panes, the strategic view open"
	"stress400 office snapshot_stress400 1 floor, 400 panes"
	"stress400+drawer office-drawer snapshot_stress400 1 floor, 400 panes, the agent list's drawer open"
	"stress400+strategic office-strategic snapshot_stress400 1 floor, 400 panes, the strategic view open")
if [ "$FIGURES" -eq 1 ]; then
	SCENARIOS+=("actors80 actors - 80 pixel people")
fi
if [ "$WALKS" -eq 1 ]; then
	SCENARIOS+=(
		"arrivals walks snapshot_stress80_shells 80 walk in at once"
		"done40 walks snapshot_stress80_working 40 of 80 done at once, seated with paper"
		"growth walks snapshot_stress80_shells tab 0 grows under 80 walking in"
		"minimize walks snapshot_stress80_shells 80 walking in, minimized 2 s"
		"blocked40 walks snapshot_stress80_working 40 of 80 go blocked at once, 40 bubbles"
		"idle40 walks snapshot_stress80_working 40 of 80 go idle at once"
		"approve walks snapshot_stress80_working one of 40 blocked answered 8 times"
		"queuegrow walks snapshot_stress80_working tab 0 grows under 40 blocked"
	)
fi

: >"$WORK/results"
for round in $(seq 1 "$RUNS"); do
	for scenario in "${SCENARIOS[@]}"; do
		read -r name mode fixture _ <<<"$scenario"
		for pacing in paced fps0; do
			measure "$mode" "$fixture" "$pacing" "$name" || exit 1
			echo "run $round/$RUNS $name $pacing: $RESULT"
			echo "$name $pacing $RESULT" >>"$WORK/results"
		done
	done
done

# The median of field `$3` over the runs of scenario `$1` at pacing `$2`.
summary() {
	grep "^$1 $2 " "$WORK/results" | while read -r line; do field "$line" "$3"; done | median
}

echo
echo "PERF median of $RUNS rounds (paced = the default; fps0 = --fps=0, uncapped)"
printf '%-9s %-19s %6s %6s %10s %11s %10s %9s %9s %13s %8s %8s\n' scenario what shown nodes draw_calls texture_mib \
	refresh_ms cpu_paced fps_paced max_fps_paced cpu_fps0 fps_fps0
for scenario in "${SCENARIOS[@]}"; do
	read -r name mode _ what <<<"$scenario"
	[ "$mode" = "walks" ] && continue
	refresh="$(summary "$name" paced refresh_ms)"
	case "$refresh" in -*) refresh="-" ;; esac
	printf '%-9s %-19s %6s %6s %10s %11s %10s %8s%% %9s %13s %7s%% %8s\n' "$name" "$what" \
		"$(summary "$name" paced on_screen)" "$(summary "$name" paced nodes)" "$(summary "$name" paced draw_calls)" \
		"$(summary "$name" paced texture_mib)" "$refresh" \
		"$(summary "$name" paced cpu)" "$(summary "$name" paced fps)" "$(summary "$name" paced max_fps)" \
		"$(summary "$name" fps0 cpu)" "$(summary "$name" fps0 fps)"
done
if [ -s "$WORK/shrunk" ]; then
	sort -u "$WORK/shrunk" | sed 's/^/PERF_SHRUNK: /'
fi
[ "$WALKS" -eq 1 ] || exit 0

echo
echo "PERF walks, median of $RUNS rounds: frame times over the hold, which starts with the snapshot that starts"
echo "the walks. live = walking then; walked / kept / placed and pass_ms = that observation's presentation pass;"
echo "refresh_ms = frame start to the end of the office's refresh for it; step_ms = the longest process step;"
echo "settle_s = when the last walk ended."
printf '%-9s %-38s %4s %6s %4s %6s %7s %10s %7s %9s %9s %9s %9s %9s %9s %8s %7s\n' scenario what live walked kept \
	placed pass_ms refresh_ms step_ms p50_paced p95_paced max_paced p50_fps0 p95_fps0 max_fps0 settle_s max_fps
for scenario in "${SCENARIOS[@]}"; do
	read -r name mode _ what <<<"$scenario"
	[ "$mode" = "walks" ] || continue
	walk_refresh="$(summary "$name" paced walk_refresh_ms)"
	case "$walk_refresh" in -*) walk_refresh="-" ;; esac
	printf '%-9s %-38s %4s %6s %4s %6s %7s %10s %7s %9s %9s %9s %9s %9s %9s %8s %7s\n' "$name" "$what" \
		"$(summary "$name" paced live)" "$(summary "$name" paced walked)" "$(summary "$name" paced kept)" \
		"$(summary "$name" paced placed)" "$(summary "$name" paced pass_ms)" \
		"$walk_refresh" "$(summary "$name" paced step_ms)" \
		"$(summary "$name" paced p50_ms)" "$(summary "$name" paced p95_ms)" "$(summary "$name" paced max_ms)" \
		"$(summary "$name" fps0 p50_ms)" "$(summary "$name" fps0 p95_ms)" "$(summary "$name" fps0 max_ms)" \
		"$(summary "$name" paced settle_s)" "$(summary "$name" paced max_fps)"
	if [ "$name" = "minimize" ]; then
		echo "          minimized: $(summary "$name" paced minimized_frames) frames at max_fps $(summary "$name" paced minimized_fps) (paced), $(summary "$name" fps0 minimized_frames) frames at max_fps $(summary "$name" fps0 minimized_fps) (fps0); the window calls blocked $(summary "$name" paced minimize_call_ms) ms minimizing, $(summary "$name" paced restore_call_ms) ms restoring (paced)"
	fi
done
