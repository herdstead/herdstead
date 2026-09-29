#!/usr/bin/env bash
# The one test entry point: Python asset tests -> every script and scene loads ->
# every art pack still dresses the scenes -> art layer tests -> fake herdr up ->
# Godot client tests -> machine tests against a second fake herdr -> incremental
# office tests -> the pure office suites (layout and plan cache, navigator) and
# the scene ones -> the write boundary's suite against two fake herdrs of its
# own -> tear down. Cases discover themselves; see tools/test_base.gd.
# Exits with the test status; nonzero also when Godot printed a SCRIPT ERROR.
#
# Every suite that builds an office but allows no write runs it `--read-only`:
# their fake herdrs refuse anything but ping, snapshot and subscribe and record
# it as a violation. Only tools/test_commands.gd, tools/test_raw_input.gd,
# tools/test_answers.gd, tools/test_bubbles.gd, tools/test_monitor.gd,
# tools/test_overview.gd, tools/test_launch.gd, tools/test_prompt.gd,
# tools/test_split.gd, tools/test_close.gd and tools/test_spaces.gd run offices
# as an operator, each against two fakes nothing else talks to, opening exactly
# what each case needs.
#
#   tools/run_tests.sh
#   GODOT=/path/to/godot PYTHON=python3.12 tools/run_tests.sh
#
# HERDSTEAD_SKIP_LOAD_CHECKS=1 skips the two load stages (every script and scene
# loads, every art pack dresses the scenes) for a caller that has just run them
# itself: `make check` and CI. Everything else still runs.
#
# Needs Godot 4.6+ (StreamPeerUDS) and Python 3 with Pillow for asset checks.
set -u

GODOT="${GODOT:-godot}"
# Hard stop for the whole Godot run, in case a case wedges despite its own waits.
RUN_TIMEOUT="${RUN_TIMEOUT:-120}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -x "$ROOT/.venv/bin/python" ]; then
	DEFAULT_PYTHON="$ROOT/.venv/bin/python"
else
	DEFAULT_PYTHON="python3"
fi
PYTHON="${PYTHON:-$DEFAULT_PYTHON}"

# Cases discover themselves (tools/test_base.gd), so nothing lists them.
# These floors are what each file runs today: a file that silently loses
# its cases fails here instead of staying green. Raise them as cases are added.
MIN_CASES_ART=22
MIN_CASES_CLIENT=52
MIN_CASES_MACHINE=33
MIN_CASES_INCREMENTAL=54
MIN_CASES_OFFICE_LAYOUT=50
MIN_CASES_OFFICE_SERVICE=14
MIN_CASES_OFFICE_GEOMETRY=22
MIN_CASES_OFFICE_FRAMES=5
MIN_CASES_OFFICE_QUIET=7
MIN_CASES_DAY_LIGHT=8
MIN_CASES_OFFICE_RECONCILE=16
MIN_CASES_OFFICE_WALKING=31
MIN_CASES_OFFICE_RESTS=27
MIN_CASES_OFFICE_NAVIGATOR=18
MIN_CASES_FLOORS=17
MIN_CASES_ATTENTION_STORE=28
MIN_CASES_AGENT_LIST=35
MIN_CASES_ATTENTION_INTEGRATION=19
MIN_CASES_FRAME_LOOP=9
MIN_CASES_PIXEL_PEOPLE=51
MIN_CASES_AVATAR_STUDIO=13
MIN_CASES_SAVED_LOOKS=16
MIN_CASES_COMMANDS=37
MIN_CASES_RAW_INPUT=14
MIN_CASES_ANSWERS=42
MIN_CASES_BUBBLES=23
MIN_CASES_MONITOR=36
MIN_CASES_TOP_BAR=26
MIN_CASES_STATE_LOG=21
MIN_CASES_NEWS_EVENTS=14
MIN_CASES_LENS=17
MIN_CASES_STRATEGIC=22
MIN_CASES_ALERTS=19
MIN_CASES_OVERVIEW=21
MIN_CASES_LAUNCH=40
MIN_CASES_PROMPT=12
MIN_CASES_SPLIT=14
MIN_CASES_CLOSE=15
MIN_CASES_SPACES=15

# Unix socket paths stop at ~104 bytes on macOS: keep them short, under /tmp.
WORK="$(mktemp -d /tmp/herdstead-test.XXXXXX)"
SERVER_PID=""
SERVER_B_PID=""
SERVER_C_PID=""
SERVER_D_PID=""
SERVER_E_PID=""
SERVER_F_PID=""
SERVER_G_PID=""
SERVER_H_PID=""
SERVER_I_PID=""
SERVER_J_PID=""
SERVER_K_PID=""
SERVER_L_PID=""
SERVER_M_PID=""
SERVER_N_PID=""
SERVER_O_PID=""
SERVER_P_PID=""
SERVER_Q_PID=""
SERVER_R_PID=""
SERVER_S_PID=""
SERVER_T_PID=""
SERVER_U_PID=""
SERVER_V_PID=""
SERVER_W_PID=""
SERVER_X_PID=""

cleanup() {
	for pid in "$SERVER_PID" "$SERVER_B_PID" "$SERVER_C_PID" "$SERVER_D_PID" "$SERVER_E_PID" "$SERVER_F_PID" \
		"$SERVER_G_PID" "$SERVER_H_PID" "$SERVER_I_PID" "$SERVER_J_PID" "$SERVER_K_PID" "$SERVER_L_PID" \
		"$SERVER_M_PID" "$SERVER_N_PID" "$SERVER_O_PID" "$SERVER_P_PID" "$SERVER_Q_PID" "$SERVER_R_PID" \
		"$SERVER_S_PID" "$SERVER_T_PID" "$SERVER_U_PID" "$SERVER_V_PID" "$SERVER_W_PID" "$SERVER_X_PID"; do
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
		fi
	done
	rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Run a command, killing it after RUN_TIMEOUT seconds. macOS has no timeout(1).
bounded() {
	# BOUND_SECONDS, while set, gives one slow suite a bound of its own.
	local limit="${BOUND_SECONDS:-$RUN_TIMEOUT}"
	"$@" &
	local pid=$!
	# Detached from stdout so a pipe reader never waits on it, and it takes its
	# sleep down with it when cancelled.
	(
		trap 'kill "$nap" 2>/dev/null; exit 0' TERM
		sleep "$limit" &
		nap=$!
		wait "$nap"
		echo "RUN_TESTS: killed after ${limit}s" >&2
		kill -9 "$pid" 2>/dev/null
	) >/dev/null 2>&1 &
	local watchdog=$!
	wait "$pid"
	local status=$?
	kill "$watchdog" 2>/dev/null
	wait "$watchdog" 2>/dev/null
	return "$status"
}

# Fail the run when a suite reports fewer cases than its floor, whatever it
# reports about them.
cases_floor() {
	local log="$1" marker="$2" floor="$3"
	local line count
	line="$(grep -m1 "^$marker \(OK\|FAILED\):" "$log" || true)"
	count="$(printf '%s' "$line" | sed -n 's/^.*: \([0-9][0-9]*\) cases.*$/\1/p')"
	if [ -z "$count" ] || [ "$count" -lt "$floor" ]; then
		echo "RUN_TESTS: $marker ran ${count:-no} cases, fewer than the $floor it must run"
		return 1
	fi
	return 0
}


echo "== Python table asset tests"
"$PYTHON" "$ROOT/tools/test_table_assets.py" -v || exit 1

# class_name scripts are unknown until imported, and Godot draws textures from
# its import cache: a fresh checkout has no .godot/, a merge that adds a class
# leaves the class cache behind, and `make art` leaves the cache behind assets/.
GODOT="$GODOT" bash "$ROOT/tools/import_if_stale.sh" || {
	echo "RUN_TESTS: import failed"
	exit 2
}

# Start a fake herdr and wait until both of its sockets listen: the client
# connects synchronously on start.
start_fake() {
	"$PYTHON" "$ROOT/tools/fake_herdr.py" \
		--socket="$WORK/$1.sock" --control="$WORK/$1-ctl.sock" \
		--fixtures="$ROOT/tools/fixtures" &
	local pid=$!
	for _ in $(seq 1 100); do
		[ -S "$WORK/$1.sock" ] && [ -S "$WORK/$1-ctl.sock" ] && break
		kill -0 "$pid" 2>/dev/null || { echo "RUN_TESTS: fake herdr $1 died on start"; exit 2; }
		sleep 0.05
	done
	if [ ! -S "$WORK/$1-ctl.sock" ]; then
		echo "RUN_TESTS: fake herdr $1 never came up"
		exit 2
	fi
	FAKE_PID=$pid
}

if [ "${HERDSTEAD_SKIP_LOAD_CHECKS:-}" = "1" ]; then
	echo "== script and pack load checks skipped (HERDSTEAD_SKIP_LOAD_CHECKS=1: the caller ran them)"
else
	# Nothing else loads a script no scene and no test references, so a broken one
	# would go unnoticed. Runs after the import, which the class cache needs.
	echo "== every script and scene loads"
	bounded "$GODOT" --headless --path "$ROOT" --script tools/check_scripts.gd 2>&1 | tee "$WORK/scripts.log"
	scripts_status=${PIPESTATUS[0]}
	if grep -q "SCRIPT ERROR" "$WORK/scripts.log"; then
		echo "RUN_TESTS: Godot reported a SCRIPT ERROR while loading the scripts"
		[ "$scripts_status" -eq 0 ] && scripts_status=1
	fi
	if ! grep -q "^SCRIPTS_OK" "$WORK/scripts.log" && [ "$scripts_status" -eq 0 ]; then
		echo "RUN_TESTS: the script check did not finish"
		scripts_status=1
	fi
	if [ "$scripts_status" -ne 0 ]; then
		echo "RUN_TESTS: exit $scripts_status"
		exit "$scripts_status"
	fi

	echo "== every art pack dresses the scenes"
	# The semantic IDs the scenes draw with live in scripts/art/art_contract.gd;
	# this loads every pack in assets/ and holds it to them.
	bounded "$GODOT" --headless --path "$ROOT" --script tools/check_packs.gd 2>&1 | tee "$WORK/packs.log"
	packs_status=${PIPESTATUS[0]}
	if grep -q "SCRIPT ERROR" "$WORK/packs.log"; then
		echo "RUN_TESTS: Godot reported a SCRIPT ERROR while checking the packs"
		[ "$packs_status" -eq 0 ] && packs_status=1
	fi
	if ! grep -q "^PACKS_OK" "$WORK/packs.log" && [ "$packs_status" -eq 0 ]; then
		echo "RUN_TESTS: the pack check did not finish"
		packs_status=1
	fi
	if [ "$packs_status" -ne 0 ]; then
		echo "RUN_TESTS: exit $packs_status"
		exit "$packs_status"
	fi
fi

echo "== art layer tests"
# No herdr: a pack is not a client, and its fixtures are written under $WORK.
bounded "$GODOT" --headless --path "$ROOT" --script tools/test_art.gd -- \
	--work="$WORK" 2>&1 | tee "$WORK/art.log"
art_status=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR" "$WORK/art.log"; then
	echo "RUN_TESTS: Godot reported a SCRIPT ERROR during the art tests"
	[ "$art_status" -eq 0 ] && art_status=1
fi
if ! cases_floor "$WORK/art.log" "ART TESTS" "$MIN_CASES_ART"; then
	[ "$art_status" -eq 0 ] && art_status=1
fi
if ! grep -q "^ART TESTS OK" "$WORK/art.log" && [ "$art_status" -eq 0 ]; then
	echo "RUN_TESTS: the art test run did not finish"
	art_status=1
fi

start_fake herdr
SERVER_PID=$FAKE_PID
# A second server stands in for a remote machine; its pane ids repeat the first's.
start_fake machine
SERVER_B_PID=$FAKE_PID

started=$(date +%s)
echo "== client + office tests"
bounded "$GODOT" --headless --path "$ROOT" --script tools/test_client.gd -- \
	--socket="$WORK/herdr.sock" --control="$WORK/herdr-ctl.sock" 2>&1 | tee "$WORK/tests.log"
status=${PIPESTATUS[0]}
[ "$status" -eq 0 ] && status=$art_status

# The client must notice a closed peer without reading it (engine: "!is_open()").
if grep -q '!is_open()' "$WORK/tests.log"; then
	echo "RUN_TESTS: the client read a closed socket"
	[ "$status" -eq 0 ] && status=1
fi
if grep -q "SCRIPT ERROR" "$WORK/tests.log"; then
	echo "RUN_TESTS: Godot reported a SCRIPT ERROR during the tests"
	[ "$status" -eq 0 ] && status=1
fi
if ! cases_floor "$WORK/tests.log" "TESTS" "$MIN_CASES_CLIENT"; then
	[ "$status" -eq 0 ] && status=1
fi
if ! grep -q "^TESTS OK" "$WORK/tests.log" && [ "$status" -eq 0 ]; then
	echo "RUN_TESTS: the test run did not finish"
	status=1
fi

echo "== machine tests"
# fake_ssh.py stands in for ssh; this wrapper runs it with the chosen Python.
printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$(command -v "$PYTHON")" "$ROOT/tools/fake_ssh.py" >"$WORK/ssh"
chmod +x "$WORK/ssh"
PYTHON="$PYTHON" bounded "$GODOT" --headless --path "$ROOT" --script tools/test_machines.gd -- --read-only \
	--socket-a="$WORK/herdr.sock" --control-a="$WORK/herdr-ctl.sock" \
	--socket-b="$WORK/machine.sock" --control-b="$WORK/machine-ctl.sock" \
	--work="$WORK" --ssh="$WORK/ssh" 2>&1 | tee "$WORK/machines.log"
machine_status=${PIPESTATUS[0]}
if grep -q '!is_open()' "$WORK/machines.log"; then
	echo "RUN_TESTS: a client read a closed socket during the machine tests"
	[ "$machine_status" -eq 0 ] && machine_status=1
fi
if grep -q "SCRIPT ERROR" "$WORK/machines.log"; then
	echo "RUN_TESTS: Godot reported a SCRIPT ERROR during the machine tests"
	[ "$machine_status" -eq 0 ] && machine_status=1
fi
if ! cases_floor "$WORK/machines.log" "MACHINE TESTS" "$MIN_CASES_MACHINE"; then
	[ "$machine_status" -eq 0 ] && machine_status=1
fi
if ! grep -q "^MACHINE TESTS OK" "$WORK/machines.log" && [ "$machine_status" -eq 0 ]; then
	echo "RUN_TESTS: the machine test run did not finish"
	machine_status=1
fi
[ "$status" -eq 0 ] && status=$machine_status

echo "== incremental office tests"
# No herdr here: the office's client is stopped and handed snapshots directly.
bounded "$GODOT" --headless --path "$ROOT" --script tools/test_office_incremental.gd -- --read-only \
	--socket="$WORK/nowhere.sock" --work="$WORK" 2>&1 | tee "$WORK/incremental.log"
incremental_status=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR" "$WORK/incremental.log"; then
	echo "RUN_TESTS: Godot reported a SCRIPT ERROR during the incremental office tests"
	[ "$incremental_status" -eq 0 ] && incremental_status=1
fi
if ! cases_floor "$WORK/incremental.log" "INCREMENTAL TESTS" "$MIN_CASES_INCREMENTAL"; then
	[ "$incremental_status" -eq 0 ] && incremental_status=1
fi
if ! grep -q "^INCREMENTAL TESTS OK" "$WORK/incremental.log" && [ "$incremental_status" -eq 0 ]; then
	echo "RUN_TESTS: the incremental office test run did not finish"
	incremental_status=1
fi
[ "$status" -eq 0 ] && status=$incremental_status

# Each suite below runs in its own bounded Godot. Godot can exit 0 on script
# errors: both log and marker remain gates, just like the existing suites above.
run_scene_suite() {
	local script="$1" marker="$2" floor="$3"
	shift 3
	local log="$WORK/$script.log"
	bounded "$GODOT" --headless --path "$ROOT" --script "tools/$script.gd" "$@" 2>&1 | tee "$log"
	local suite_status=${PIPESTATUS[0]}
	if grep -Eq 'SCRIPT ERROR|Parse Error' "$log"; then
		echo "RUN_TESTS: Godot reported a script error during $marker"
		[ "$suite_status" -eq 0 ] && suite_status=1
	fi
	if ! cases_floor "$log" "$marker" "$floor"; then
		[ "$suite_status" -eq 0 ] && suite_status=1
	fi
	if ! grep -q "^$marker OK" "$log"; then
		echo "RUN_TESTS: $marker did not finish successfully"
		[ "$suite_status" -eq 0 ] && suite_status=1
	fi
	[ "$status" -eq 0 ] && status=$suite_status
}

run_scene_suite test_office_layout "OFFICE LAYOUT TESTS" "$MIN_CASES_OFFICE_LAYOUT"
# The entry band's fixtures and who rests where: pure, no office.
run_scene_suite test_office_service "OFFICE SERVICE TESTS" "$MIN_CASES_OFFICE_SERVICE"
run_scene_suite test_office_navigator "OFFICE NAVIGATOR TESTS" "$MIN_CASES_OFFICE_NAVIGATOR"
run_scene_suite test_office_geometry "OFFICE GEOMETRY TESTS" "$MIN_CASES_OFFICE_GEOMETRY" -- --work="$WORK"
# The framed pictures on the row walls: pure placement, the shell that draws
# it, and the live office's frames through status, focus, selection and a drop.
run_scene_suite test_office_frames "OFFICE FRAMES TESTS" "$MIN_CASES_OFFICE_FRAMES" -- --read-only \
	--socket="$WORK/frames-nowhere.sock" --work="$WORK"
# What a refresh does not redo: one refresh per frame of fleet changes, and a
# quiet refresh on a kept plan (no placement signature, no structural pass, no lamp).
run_scene_suite test_office_quiet "QUIET REFRESH TESTS" "$MIN_CASES_OFFICE_QUIET" -- --read-only \
	--socket="$WORK/quiet-nowhere.sock" --work="$WORK"
# Day and night (DayLight) over the one pack: the curve, the clock, T, the bar.
run_scene_suite test_day_light "DAY LIGHT TESTS" "$MIN_CASES_DAY_LIGHT" -- --read-only \
	--socket="$WORK/day-light-nowhere.sock" --work="$WORK"
run_scene_suite test_office_reconcile "RECONCILE TESTS" "$MIN_CASES_OFFICE_RECONCILE" -- --read-only \
	--socket="$WORK/reconcile-nowhere.sock" --work="$WORK"
# People walking on the shown floor: arrivals, departures, to the pantry and back, cold
# passes, freezing, re-routing; offices fed like the incremental suite's.
run_scene_suite test_office_walking "WALKING TESTS" "$MIN_CASES_OFFICE_WALKING" -- --read-only \
	--socket="$WORK/walking-nowhere.sock" --work="$WORK"
# Who rests where: the seat with its bubble and its paper, the pantry.
run_scene_suite test_office_rests "RESTS TESTS" "$MIN_CASES_OFFICE_RESTS" -- --read-only \
	--socket="$WORK/rests-nowhere.sock" --work="$WORK"
# The left column's minimap and the signposts, and a mezzanine's plate, by real input.
run_scene_suite test_floors "FLOORS TESTS" "$MIN_CASES_FLOORS" -- --read-only \
	--socket="$WORK/floors-nowhere.sock" --work="$WORK"

run_scene_suite test_attention_store "ATTENTION STORE TESTS" "$MIN_CASES_ATTENTION_STORE"
run_scene_suite test_agent_list "AGENT LIST TESTS" "$MIN_CASES_AGENT_LIST" -- --work="$WORK"
run_scene_suite test_attention_integration "ATTENTION INTEGRATION TESTS" "$MIN_CASES_ATTENTION_INTEGRATION" -- \
	--read-only --socket="$WORK/attention-nowhere.sock" --work="$WORK"

# The live office's frame pacer and per-frame work; headless, so no pacing.
run_scene_suite test_frame_loop "FRAME LOOP TESTS" "$MIN_CASES_FRAME_LOOP" -- --read-only \
	--socket="$WORK/frame-loop-nowhere.sock" --work="$WORK"
# The pixel people: their family, the look and its saved file, prefab and
# standalone showroom; no herdr. Fixture manifests, copies of the sheets and
# every saved-looks file go under $WORK, never the user's.
run_scene_suite test_pixel_people "PIXEL PEOPLE TESTS" "$MIN_CASES_PIXEL_PEOPLE" -- --work="$WORK"
# The Avatar Studio through real input, saving under $WORK; a process of its
# own, because the studio sets the window's content scale.
run_scene_suite test_avatar_studio "AVATAR STUDIO TESTS" "$MIN_CASES_AVATAR_STUDIO" -- --work="$WORK"
# The saved looks file: a save that would lose or hide anything refuses, and
# says why. Every file it writes goes under $WORK, never the user's.
run_scene_suite test_saved_looks "SAVED LOOKS TESTS" "$MIN_CASES_SAVED_LOOKS" -- --work="$WORK"

# The write boundary, the agent card and `--read-only`, against two fake herdrs
# of its own whose pane ids collide. It closes by checking that those two saw
# only the requests its cases opened.
start_fake command-a
SERVER_C_PID=$FAKE_PID
start_fake command-b
SERVER_D_PID=$FAKE_PID
# About a minute here, in real time on real frames: its bound is its own, and
# generous, so a slower machine does not kill it halfway. The SSH case goes
# through the same fake_ssh wrapper as the machine tests.
BOUND_SECONDS=300
run_scene_suite test_commands "COMMAND TESTS" "$MIN_CASES_COMMANDS" -- \
	--socket-a="$WORK/command-a.sock" --control-a="$WORK/command-a-ctl.sock" \
	--socket-b="$WORK/command-b.sock" --control-b="$WORK/command-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# The terminal monitor's raw mode at the write boundary (docs/WRITE_BOUNDARY.md §3),
# against two more fakes of its own so that its closing check, like the one above, sees only what its own cases opened.
start_fake raw-a
SERVER_Q_PID=$FAKE_PID
start_fake raw-b
SERVER_R_PID=$FAKE_PID
run_scene_suite test_raw_input "RAW INPUT TESTS" "$MIN_CASES_RAW_INPUT" -- \
	--socket-a="$WORK/raw-a.sock" --control-a="$WORK/raw-a-ctl.sock" \
	--socket-b="$WORK/raw-b.sock" --control-b="$WORK/raw-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# Answer mode: the keys and the one line the agent card sends, against two
# more fakes of its own, so that its closing check, like the one above, sees
# only what its own cases opened. About two minutes on real frames.
start_fake answer-a
SERVER_E_PID=$FAKE_PID
start_fake answer-b
SERVER_F_PID=$FAKE_PID
run_scene_suite test_answers "ANSWER TESTS" "$MIN_CASES_ANSWERS" -- \
	--socket-a="$WORK/answer-a.sock" --control-a="$WORK/answer-a-ctl.sock" \
	--socket-b="$WORK/answer-b.sock" --control-b="$WORK/answer-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# The bubbles over blocked agents, and the clicks in the world and on the
# bar that open answer mode, against two more.
start_fake bubble-a
SERVER_S_PID=$FAKE_PID
start_fake bubble-b
SERVER_T_PID=$FAKE_PID
run_scene_suite test_bubbles "BUBBLE TESTS" "$MIN_CASES_BUBBLES" -- \
	--socket-a="$WORK/bubble-a.sock" --control-a="$WORK/bubble-a-ctl.sock" \
	--socket-b="$WORK/bubble-b.sock" --control-b="$WORK/bubble-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# The terminal monitor (docs/WRITE_BOUNDARY.md §3): its grid against the recorded dumps,
# and the monitor in an operator office, typed into by real input, against two
# more fakes of its own. Its raw-mode write gates are in test_raw_input above.
start_fake monitor-a
SERVER_G_PID=$FAKE_PID
start_fake monitor-b
SERVER_H_PID=$FAKE_PID
run_scene_suite test_monitor "MONITOR TESTS" "$MIN_CASES_MONITOR" -- \
	--socket-a="$WORK/monitor-a.sock" --control-a="$WORK/monitor-a-ctl.sock" \
	--socket-b="$WORK/monitor-b.sock" --control-b="$WORK/monitor-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# The OVERVIEW: its model and timeline, and the table in an operator
# office by real input, against two more fakes of its own; it writes nothing
# but the one key a case answers with through the staff panel under it.
start_fake overview-a
SERVER_I_PID=$FAKE_PID
start_fake overview-b
SERVER_J_PID=$FAKE_PID
run_scene_suite test_overview "OVERVIEW TESTS" "$MIN_CASES_OVERVIEW" -- \
	--socket-a="$WORK/overview-a.sock" --control-a="$WORK/overview-a-ctl.sock" \
	--socket-b="$WORK/overview-b.sock" --control-b="$WORK/overview-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# The launch writes at the boundary (agent.prompt, agent.start, pane.split),
# against two more fakes of its own.
start_fake launch-a
SERVER_K_PID=$FAKE_PID
start_fake launch-b
SERVER_L_PID=$FAKE_PID
run_scene_suite test_launch "LAUNCH TESTS" "$MIN_CASES_LAUNCH" -- \
	--socket-a="$WORK/launch-a.sock" --control-a="$WORK/launch-a-ctl.sock" \
	--socket-b="$WORK/launch-b.sock" --control-b="$WORK/launch-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# The one-line reply on the agent card, sent as herdr's own prompt: what the
# card says of it and every gate before it, by real input, against two more.
start_fake prompt-a
SERVER_M_PID=$FAKE_PID
start_fake prompt-b
SERVER_N_PID=$FAKE_PID
run_scene_suite test_prompt "PROMPT TESTS" "$MIN_CASES_PROMPT" -- \
	--socket-a="$WORK/prompt-a.sock" --control-a="$WORK/prompt-a-ctl.sock" \
	--socket-b="$WORK/prompt-b.sock" --control-b="$WORK/prompt-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# NEW PANE BESIDE on the agent card: the split, the pick of the new pane and
# every gate before it, by real input, against two more.
start_fake split-a
SERVER_O_PID=$FAKE_PID
start_fake split-b
SERVER_P_PID=$FAKE_PID
run_scene_suite test_split "SPLIT TESTS" "$MIN_CASES_SPLIT" -- \
	--socket-a="$WORK/split-a.sock" --control-a="$WORK/split-a-ctl.sock" \
	--socket-b="$WORK/split-b.sock" --control-b="$WORK/split-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# Close pane on the agent card: the two clicks, what goes with the pane,
# every gate before the one `pane.close`, by real input, against two more.
start_fake close-a
SERVER_U_PID=$FAKE_PID
start_fake close-b
SERVER_V_PID=$FAKE_PID
run_scene_suite test_close "CLOSE TESTS" "$MIN_CASES_CLOSE" -- \
	--socket-a="$WORK/close-a.sock" --control-a="$WORK/close-a-ctl.sock" \
	--socket-b="$WORK/close-b.sock" --control-b="$WORK/close-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"

# New space and New worktree on the agent card: the exact params, the
# branch and directory gates, git's refusals as one line, the pick of the new
# floor's shell, by real input, against two more.
start_fake spaces-a
SERVER_W_PID=$FAKE_PID
start_fake spaces-b
SERVER_X_PID=$FAKE_PID
run_scene_suite test_spaces "SPACES TESTS" "$MIN_CASES_SPACES" -- \
	--socket-a="$WORK/spaces-a.sock" --control-a="$WORK/spaces-a-ctl.sock" \
	--socket-b="$WORK/spaces-b.sock" --control-b="$WORK/spaces-b-ctl.sock" --work="$WORK" --ssh="$WORK/ssh"
unset BOUND_SECONDS

# The top bar's counters: counts, hover breakdowns, clicks and the list filter, by real input.
run_scene_suite test_top_bar "TOP BAR TESTS" "$MIN_CASES_TOP_BAR" -- --read-only \
	--socket="$WORK/top-bar-nowhere.sock" --work="$WORK"

# The state log: segments and events from the fleet's clients, by the log's rules.
run_scene_suite test_state_log "STATE LOG TESTS" "$MIN_CASES_STATE_LOG" -- --read-only \
	--socket="$WORK/state-log-nowhere.sock" --work="$WORK"

# NEWS and the drawer's EVENTS page: the log's events in herdr's words, by real input.
run_scene_suite test_news_events "NEWS EVENTS TESTS" "$MIN_CASES_NEWS_EVENTS" -- --read-only \
	--socket="$WORK/news-nowhere.sock" --work="$WORK"
# The info lens and the hover mark: hold L, hover a HUD row; by real input.
run_scene_suite test_lens "LENS TESTS" "$MIN_CASES_LENS" -- --read-only \
	--socket="$WORK/lens-nowhere.sock" --work="$WORK"
# The strategic view: `S`, the schematic's squares, clicks, the wheel; by real input.
run_scene_suite test_strategic "STRATEGIC TESTS" "$MIN_CASES_STRATEGIC" -- --read-only \
	--socket="$WORK/strategic-nowhere.sock" --work="$WORK"
# In the background: the title's (N), the one Dock bounce, the chime; headless, so decided, never rung.
run_scene_suite test_alerts "ALERTS TESTS" "$MIN_CASES_ALERTS" -- --read-only \
	--socket="$WORK/alerts-nowhere.sock" --work="$WORK"

echo "RUN_TESTS: exit $status in $(( $(date +%s) - started ))s"
exit "$status"
