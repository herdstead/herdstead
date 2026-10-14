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
# tools/test_split.gd, tools/test_close.gd, tools/test_spaces.gd and
# tools/test_launch_news.gd run offices
# as an operator, each against two fakes nothing else talks to, opening exactly
# what each case needs.
#
#   tools/run_tests.sh
#   GODOT=/path/to/godot PYTHON=python3.12 tools/run_tests.sh
#
# HERDSTEAD_SKIP_LOAD_CHECKS=1 skips the two load stages for a caller that ran
# them already. HERDSTEAD_SKIP_PYTHON_TESTS=1 likewise skips the Python checks
# when `make check` has just run test-art, test-tools and test-harness.
#
# SUITES="test_office_geometry test_lens" runs only the Godot suites named (by
# their script's name under tools/), each with its floor, marker and log gates
# as in a full run; no Python tests and only their own fakes. Unknown names
# fail before importing or starting anything. `make test-suite S=...` is the
# everyday spelling. TIER=quick is the quick tier,
# QUICK_SUITES below: the art layer and the world (plans, pods, geometry,
# people, walking, the lens), none of the HUD or the write boundary; `make
# check-quick` runs it. A suite left out is not checked: the full run (`make
# check`, CI) is still the gate before a push.
#
# CASE=test_name requires one explicit suite and runs just that exact case.
# Its FILTERED summary must name one case, never satisfy a full-suite floor.
# This is a diagnostic shortcut, not the suite's closing whole-run audit.
# Every case logs its start and duration; failed or unfinished cases get their
# own rerun commands beside the full-suite command and retained failure logs.
#
# SHARD=i/n partitions the full invocation list, round-robin, into n nonempty
# groups of whole suites. It cannot combine with SUITES, CASE or TIER. Each
# shard keeps the same floors, audits and fakes; Python contracts run separately.
# --list prints the selected suite names without importing or starting anything.
# Parallel shards need separate checkouts/runners, never a shared .godot cache.
#
# Needs Godot 4.6+ (StreamPeerUDS) and Python 3 with Pillow for asset checks.
set -u

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != --list ]; }; then
	echo "Usage: tools/run_tests.sh [--list] (SUITES, CASE, TIER or SHARD=i/n via environment)"
	exit 2
fi

GODOT="${GODOT:-godot}"
# Hard stop per Godot process, in case a case wedges despite its own waits.
RUN_TIMEOUT="${RUN_TIMEOUT:-120}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
started=$(date +%s)
if [ -x "$ROOT/.venv/bin/python" ]; then
	DEFAULT_PYTHON="$ROOT/.venv/bin/python"
else
	DEFAULT_PYTHON="python3"
fi
PYTHON="${PYTHON:-$DEFAULT_PYTHON}"

# Cases discover themselves (tools/test_base.gd), so nothing lists them.
# These floors are what each file runs today: a file that silently loses
# its cases fails here instead of staying green. Raise them as cases are added.
MIN_CASES_ART=26
MIN_CASES_CLIENT=52
MIN_CASES_MACHINE=34
MIN_CASES_INCREMENTAL=54
MIN_CASES_OFFICE_LAYOUT=51
MIN_CASES_OFFICE_MAP=23
MIN_CASES_OFFICE_SERVICE=16
# GEOMETRY 27 -> 25: its two row-wall sign and title cases went with the row
# walls (lane B2a); MAP's test_top_run_and_lane_gap_pieces_clear_... covers
# the furniture's clearance on the map now. 25 -> 29: the near row sits at the
# desk (the sitter over the near plane, the short legs behind the end chairs,
# the near paper and the near lamp in sight beside whoever sits there).
MIN_CASES_OFFICE_GEOMETRY=30
MIN_CASES_OFFICE_FRAMES=5
MIN_CASES_OFFICE_QUIET=8
MIN_CASES_DAY_LIGHT=8
MIN_CASES_OFFICE_RECONCILE=22
MIN_CASES_OFFICE_WALKING=33
MIN_CASES_OFFICE_RESTS=28
MIN_CASES_OFFICE_NAVIGATOR=26
# FLOORS (22 cases, tools/test_floors.gd) was retired with the FLOORS minimap and
# its signposts (lane B3): SPACE RAIL covered every one of its cases on the
# SPACES rail and the edge arrows, and added ten (40).
# SPACE RAIL 40 -> 20: the edge arrows' 20 cases moved, unchanged, to EDGE
# ARROWS (tools/test_edge_arrows.gd), so both files stay under gdlint's
# max-file-lines; the two floors still add up to 40.
MIN_CASES_SPACE_RAIL=20
MIN_CASES_EDGE_ARROWS=20
MIN_CASES_ATTENTION_STORE=28
MIN_CASES_AGENT_LIST=36
MIN_CASES_ATTENTION_INTEGRATION=19
MIN_CASES_FRAME_LOOP=9
MIN_CASES_PIXEL_PEOPLE=51
MIN_CASES_AVATAR_STUDIO=13
MIN_CASES_SAVED_LOOKS=16
MIN_CASES_COMMANDS=37
MIN_CASES_RAW_INPUT=14
MIN_CASES_ANSWERS=42
MIN_CASES_BUBBLES=24
MIN_CASES_MONITOR=36
MIN_CASES_TOP_BAR=27
MIN_CASES_STATE_LOG=21
MIN_CASES_NEWS_EVENTS=15
MIN_CASES_LENS=20
MIN_CASES_STRATEGIC=28
MIN_CASES_ALERTS=19
MIN_CASES_OVERVIEW=21
# LAUNCH 40 -> 44: three transitions of the card's launch state by real input (a
# cancelled confirm does not return with its screen, a click after the kinds
# change, a start that came up across cards with and without a look owed).
# and one more: the pick that follows a start is the office's, not the viewer's.
MIN_CASES_LAUNCH=44
MIN_CASES_PROMPT=12
MIN_CASES_SPLIT=16
MIN_CASES_CLOSE=15
MIN_CASES_SPACES=16
MIN_CASES_REFUSAL_LADDER=23
# The agent card's picture (CardPicture): pure tables, no scene and no herdr.
MIN_CASES_CARD_PICTURE=27
# How a start that is over is said across cards of its pane: four transitions
# by real input and the closing case, in a suite of its own because
# tools/test_launch.gd stands at gdlint's file cap.
MIN_CASES_LAUNCH_NEWS=5
# Where a desk's signal is and where a zone opens (lane RECT): DESK SIGNAL is
# the floor view's answers and the camera's pan rules, pure; DESK SIGNAL WIRING
# is the live office's reveal, zone opening, pointer and arrows against the
# numbers 6413cec left, through the paths that commit already had.
MIN_CASES_DESK_SIGNAL=12
MIN_CASES_DESK_SIGNAL_WIRING=9
MIN_CASES_PICK_FOLLOWS_WRITE=20

# The quick tier (TIER=quick): every suite that an art, world or geometry
# change can break and nothing a HUD or write-boundary change needs; about
# five minutes on a quiet machine with the gates before it, two of them the
# suites (measured 269 s / 110 s), and none of the suites that wait on
# wall-clock time with a fake herdr.
QUICK_SUITES="test_art test_office_incremental test_office_layout test_office_map test_office_service
test_office_navigator test_office_geometry test_office_frames test_office_quiet test_day_light
test_office_reconcile test_office_walking test_office_rests test_lens test_pixel_people test_desk_signal"
SUITES="${SUITES:-}"
CASE="${CASE:-}"
SHARD="${SHARD:-}"
if [ -n "$SHARD" ] && { [ -n "$SUITES" ] || [ -n "$CASE" ] || [ -n "${TIER:-}" ]; }; then
	echo "RUN_TESTS: SHARD cannot combine with SUITES, CASE or TIER"
	exit 2
fi
if [ -n "$CASE" ] && { [ -z "$SUITES" ] || [ -n "${TIER:-}" ]; }; then
	echo "RUN_TESTS: CASE requires one explicit suite and no TIER"
	exit 2
fi
if [ "${TIER:-}" = "quick" ]; then
	SUITES="$QUICK_SUITES"
elif [ -n "${TIER:-}" ]; then
	echo "RUN_TESTS: unknown TIER '$TIER' (only quick)"
	exit 2
fi
if [ -n "$SUITES" ]; then
	# read -a preserves literal names (no pathname expansion) and accepts tabs
	# as well as spaces. Join once so wanted() sees the same words as validation.
	read -r -a requested <<<"${SUITES//$'\n'/ }"
	if [ "${#requested[@]}" -eq 0 ]; then
		echo "RUN_TESTS: empty suite selection"
		exit 2
	fi
	if [ -n "$CASE" ] && [ "${#requested[@]}" -ne 1 ]; then
		echo "RUN_TESTS: CASE requires exactly one suite"
		exit 2
	fi
	SUITES="${requested[*]}"
fi

# Whether suite `$1` (a script name) runs: every one when SUITES is empty.
wanted() {
	[ -z "$SUITES" ] && return 0
	case " $SUITES " in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

# Only the current suite's fakes live at once. Record each PID immediately so
# even a failure while starting the second server reaps the first one.
SERVER_PIDS=""
stop_fakes() {
	local pid
	for pid in $SERVER_PIDS; do
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	done
	SERVER_PIDS=""
}

cleanup() {
	local result=$? saved log
	stop_fakes
	if [ "$result" -ne 0 ]; then
		saved="$ROOT/build/test-results/$(basename "$WORK")"
		if mkdir -p "$saved" && touch "$ROOT/build/.gdignore"; then
			for log in "$WORK"/*.log; do
				[ -f "$log" ] || continue
				cp "$log" "$saved/" || {
					echo "RUN_TESTS: could not save logs; kept work at $WORK"
					return
				}
			done
			echo "RUN_TESTS: logs saved to $saved"
		else
			echo "RUN_TESTS: could not save logs; kept work at $WORK"
			return
		fi
	fi
	rm -rf "$WORK"
}

# macOS has no timeout(1). The watchdog's output goes into the suite log too;
# the marker file lets the parent name a timeout without keeping a pipe open.
bounded() {
	local limit="${BOUND_SECONDS:-$RUN_TIMEOUT}"
	local expired="$WORK/timed-out"
	rm -f "$expired"
	"$@" &
	local pid=$!
	(
		trap 'kill "$nap" 2>/dev/null; exit 0' TERM
		sleep "$limit" &
		nap=$!
		wait "$nap"
		: >"$expired"
		kill -9 "$pid" 2>/dev/null
	) >/dev/null 2>&1 &
	local watchdog=$!
	wait "$pid"
	local result=$?
	kill "$watchdog" 2>/dev/null
	wait "$watchdog" 2>/dev/null
	if [ -f "$expired" ]; then
		echo "RUN_TESTS: killed after ${limit}s"
		return 124
	fi
	return "$result"
}

# Full suites keep their floors. A focused run instead proves exactly one
# requested case started, and exactly one finished in its FILTERED summary.
cases_floor() {
	local log="$1" marker="$2" floor="$3" selected="$4"
	local line count
	line="$(grep -m1 "^$marker \(OK\|FAILED\):" "$log" || true)"
	count="$(printf '%s' "$line" | sed -n 's/^.*: \([0-9][0-9]*\) cases.*$/\1/p')"
	if [ -n "$selected" ]; then
		if [ "$count" != 1 ] || [ "$(sed -n 's/^CASE_START //p' "$log")" != "$selected" ]; then
			echo "RUN_TESTS: $marker must run exactly '$selected'; reported ${count:-no} cases"
			return 1
		fi
		return 0
	fi
	if [ -z "$count" ] || [ "$count" -lt "$floor" ]; then
		echo "RUN_TESTS: $marker ran ${count:-no} cases, fewer than the $floor it must run"
		return 1
	fi
	return 0
}
# Start a fake herdr and wait until both of its sockets listen: the client
# connects synchronously on start.
start_fake() {
	"$PYTHON" "$ROOT/tools/fake_herdr.py" \
		--socket="$WORK/$1.sock" --control="$WORK/$1-ctl.sock" \
		--fixtures="$ROOT/tools/fixtures" >"$WORK/$1.log" 2>&1 &
	local pid=$!
	SERVER_PIDS="$SERVER_PIDS $pid"
	for _ in $(seq 1 100); do
		[ -S "$WORK/$1.sock" ] && [ -S "$WORK/$1-ctl.sock" ] && break
		kill -0 "$pid" 2>/dev/null || { echo "RUN_TESTS: fake herdr $1 died on start"; exit 2; }
		sleep 0.05
	done
	if [ ! -S "$WORK/$1.sock" ] || [ ! -S "$WORK/$1-ctl.sock" ]; then
		echo "RUN_TESTS: fake herdr $1 never came up"
		exit 2
	fi
}

# Keep the full-suite command too: a focused rerun cannot reproduce a closing
# audit's preceding cases or prove the rest of the suite still passes.
rerun_command() {
	# An explicit empty CASE also clears a filter exported by the caller.
	printf 'RUN_TESTS: rerun with GODOT=%q PYTHON=%q make -C %q test-suite S=%q CASE=%q\n' \
		"$GODOT" "$PYTHON" "$ROOT" "$1" "$2"
}

# run_suites is the one list: first collect its selected names without side
# effects, then run it. Selection never depends on parsing this shell source
# or on a second registry that could drift from the actual invocations.
run_scene_suite() {
	local script="$1" marker="$2" floor="$3"
	shift 3
	wanted "$script" || return 0
	if [ "$LIST_ONLY" = 1 ]; then
		SELECTED="$SELECTED $script"
		return 0
	fi
	if [ -n "$CASE" ]; then
		# Pure suites have no user-argument separator yet; connected ones do.
		[ "$#" -ne 0 ] || set -- --
		set -- "$@" "--case=$CASE"
		marker="$marker FILTERED"
	fi
	local log="$WORK/$script.log"
	echo "== $script"
	bounded "$GODOT" --headless --path "$ROOT" --script "tools/$script.gd" "$@" 2>&1 | tee "$log"
	local suite_status=${PIPESTATUS[0]}
	if grep -Eq 'SCRIPT ERROR|Parse Error' "$log"; then
		echo "RUN_TESTS: Godot reported a script error during $marker"
		[ "$suite_status" -eq 0 ] && suite_status=1
	fi
	if ! cases_floor "$log" "$marker" "$floor" "$CASE"; then
		[ "$suite_status" -eq 0 ] && suite_status=1
	fi
	if ! grep -q "^$marker OK" "$log"; then
		echo "RUN_TESTS: $marker did not finish successfully"
		[ "$suite_status" -eq 0 ] && suite_status=1
	fi
	# The client and machine suites must notice a closed peer before reading it.
	if { [ "$script" = test_client ] || [ "$script" = test_machines ]; } && grep -q '!is_open()' "$log"; then
		echo "RUN_TESTS: a client read a closed socket"
		[ "$suite_status" -eq 0 ] && suite_status=1
	fi
	if [ "$suite_status" -ne 0 ]; then
		rerun_command "$script" ""
		local unfinished failed name
		unfinished="$(awk '
			$1 == "CASE_START" { active = $2 }
			($1 == "PASS" || $1 == "FAIL") && $2 == active { active = "" }
			END { print active }
		' "$log")"
		# This names where execution stopped, not the cause of a process timeout.
		[ -z "$unfinished" ] || echo "RUN_TESTS: last unfinished case: $unfinished"
		if [ -n "$CASE" ]; then
			rerun_command "$script" "$CASE"
		else
			failed="$(awk '/^FAIL / { print $2 }' "$log")"
			for name in $failed $unfinished; do
				rerun_command "$script" "$name"
			done
		fi
	fi
	[ "$status" -eq 0 ] && status=$suite_status
}

# One socket for the client suite, an isolated pair for every other connected
# suite. All pairs retain their colliding pane ids, audit cases and timeouts.
run_connected_suite() {
	local script="$1" marker="$2" floor="$3" prefix="$4" limit="$5"
	shift 5
	wanted "$script" || return 0
	if [ "$LIST_ONLY" = 1 ]; then
		run_scene_suite "$script" "$marker" "$floor"
		return
	fi
	if [ "$script" = test_client ]; then
		start_fake "$prefix"
		run_scene_suite "$script" "$marker" "$floor" -- \
			--socket="$WORK/$prefix.sock" --control="$WORK/$prefix-ctl.sock"
	else
		start_fake "$prefix-a"
		start_fake "$prefix-b"
		# fake_ssh.py stands in for ssh, using this run's Python, never the user's ssh.
		printf '#!/usr/bin/env bash\nexec %q %q "$@"\n' \
			"$(command -v "$PYTHON")" "$ROOT/tools/fake_ssh.py" >"$WORK/ssh"
		chmod +x "$WORK/ssh"
		PYTHON="$PYTHON" BOUND_SECONDS="$limit" run_scene_suite "$script" "$marker" "$floor" -- \
			--socket-a="$WORK/$prefix-a.sock" --control-a="$WORK/$prefix-a-ctl.sock" \
			--socket-b="$WORK/$prefix-b.sock" --control-b="$WORK/$prefix-b-ctl.sock" \
			--work="$WORK" --ssh="$WORK/ssh" "$@"
	fi
	stop_fakes
}

run_suites() {
	run_scene_suite test_art "ART TESTS" "$MIN_CASES_ART" -- --work="$WORK"
	run_connected_suite test_client "TESTS" "$MIN_CASES_CLIENT" herdr "$RUN_TIMEOUT"
	run_connected_suite test_machines "MACHINE TESTS" "$MIN_CASES_MACHINE" machine "$RUN_TIMEOUT" --read-only
	# No herdr: these offices are fed snapshots directly and stay read-only.
	run_scene_suite test_office_incremental "INCREMENTAL TESTS" "$MIN_CASES_INCREMENTAL" -- --read-only \
		--socket="$WORK/nowhere.sock" --work="$WORK"
	run_scene_suite test_office_layout "OFFICE LAYOUT TESTS" "$MIN_CASES_OFFICE_LAYOUT"
	run_scene_suite test_office_map "OFFICE MAP TESTS" "$MIN_CASES_OFFICE_MAP"
	run_scene_suite test_office_service "OFFICE SERVICE TESTS" "$MIN_CASES_OFFICE_SERVICE"
	run_scene_suite test_office_navigator "OFFICE NAVIGATOR TESTS" "$MIN_CASES_OFFICE_NAVIGATOR"
	run_scene_suite test_office_geometry "OFFICE GEOMETRY TESTS" "$MIN_CASES_OFFICE_GEOMETRY" -- --work="$WORK"
	run_scene_suite test_office_frames "OFFICE FRAMES TESTS" "$MIN_CASES_OFFICE_FRAMES" -- --read-only \
		--socket="$WORK/frames-nowhere.sock" --work="$WORK"
	run_scene_suite test_office_quiet "QUIET REFRESH TESTS" "$MIN_CASES_OFFICE_QUIET" -- --read-only \
		--socket="$WORK/quiet-nowhere.sock" --work="$WORK"
	run_scene_suite test_day_light "DAY LIGHT TESTS" "$MIN_CASES_DAY_LIGHT" -- --read-only \
		--socket="$WORK/day-light-nowhere.sock" --work="$WORK"
	run_scene_suite test_office_reconcile "RECONCILE TESTS" "$MIN_CASES_OFFICE_RECONCILE" -- --read-only \
		--socket="$WORK/reconcile-nowhere.sock" --work="$WORK"
	run_scene_suite test_office_walking "WALKING TESTS" "$MIN_CASES_OFFICE_WALKING" -- --read-only \
		--socket="$WORK/walking-nowhere.sock" --work="$WORK"
	run_scene_suite test_office_rests "RESTS TESTS" "$MIN_CASES_OFFICE_RESTS" -- --read-only \
		--socket="$WORK/rests-nowhere.sock" --work="$WORK"
	run_scene_suite test_space_rail "SPACE RAIL TESTS" "$MIN_CASES_SPACE_RAIL" -- --read-only \
		--socket="$WORK/space-rail-nowhere.sock" --work="$WORK"
	run_scene_suite test_edge_arrows "EDGE ARROW TESTS" "$MIN_CASES_EDGE_ARROWS" -- --read-only \
		--socket="$WORK/edge-arrows-nowhere.sock" --work="$WORK"
	run_scene_suite test_attention_store "ATTENTION STORE TESTS" "$MIN_CASES_ATTENTION_STORE"
	run_scene_suite test_agent_list "AGENT LIST TESTS" "$MIN_CASES_AGENT_LIST" -- --work="$WORK"
	run_scene_suite test_attention_integration "ATTENTION INTEGRATION TESTS" "$MIN_CASES_ATTENTION_INTEGRATION" -- \
		--read-only --socket="$WORK/attention-nowhere.sock" --work="$WORK"
	run_scene_suite test_frame_loop "FRAME LOOP TESTS" "$MIN_CASES_FRAME_LOOP" -- --read-only \
		--socket="$WORK/frame-loop-nowhere.sock" --work="$WORK"
	# Manifests and saved looks live under WORK, never in the user's save directory.
	run_scene_suite test_pixel_people "PIXEL PEOPLE TESTS" "$MIN_CASES_PIXEL_PEOPLE" -- --work="$WORK"
	run_scene_suite test_avatar_studio "AVATAR STUDIO TESTS" "$MIN_CASES_AVATAR_STUDIO" -- --work="$WORK"
	run_scene_suite test_saved_looks "SAVED LOOKS TESTS" "$MIN_CASES_SAVED_LOOKS" -- --work="$WORK"
	# Real-input write suites keep their existing 300-second bounds and private pairs.
	run_connected_suite test_commands "COMMAND TESTS" "$MIN_CASES_COMMANDS" command 300
	run_connected_suite test_raw_input "RAW INPUT TESTS" "$MIN_CASES_RAW_INPUT" raw 300
	run_connected_suite test_answers "ANSWER TESTS" "$MIN_CASES_ANSWERS" answer 300
	run_connected_suite test_bubbles "BUBBLE TESTS" "$MIN_CASES_BUBBLES" bubble 300
	run_connected_suite test_monitor "MONITOR TESTS" "$MIN_CASES_MONITOR" monitor 300
	run_connected_suite test_overview "OVERVIEW TESTS" "$MIN_CASES_OVERVIEW" overview 300
	run_connected_suite test_launch "LAUNCH TESTS" "$MIN_CASES_LAUNCH" launch 300
	run_connected_suite test_prompt "PROMPT TESTS" "$MIN_CASES_PROMPT" prompt 300
	run_connected_suite test_split "SPLIT TESTS" "$MIN_CASES_SPLIT" split 300
	run_connected_suite test_close "CLOSE TESTS" "$MIN_CASES_CLOSE" close 300
	run_connected_suite test_spaces "SPACES TESTS" "$MIN_CASES_SPACES" spaces 300
	run_scene_suite test_top_bar "TOP BAR TESTS" "$MIN_CASES_TOP_BAR" -- --read-only \
		--socket="$WORK/top-bar-nowhere.sock" --work="$WORK"
	run_scene_suite test_state_log "STATE LOG TESTS" "$MIN_CASES_STATE_LOG" -- --read-only \
		--socket="$WORK/state-log-nowhere.sock" --work="$WORK"
	run_scene_suite test_news_events "NEWS EVENTS TESTS" "$MIN_CASES_NEWS_EVENTS" -- --read-only \
		--socket="$WORK/news-nowhere.sock" --work="$WORK"
	run_scene_suite test_lens "LENS TESTS" "$MIN_CASES_LENS" -- --read-only \
		--socket="$WORK/lens-nowhere.sock" --work="$WORK"
	run_scene_suite test_strategic "STRATEGIC TESTS" "$MIN_CASES_STRATEGIC" -- --read-only \
		--socket="$WORK/strategic-nowhere.sock" --work="$WORK"
	run_scene_suite test_alerts "ALERTS TESTS" "$MIN_CASES_ALERTS" -- --read-only \
		--socket="$WORK/alerts-nowhere.sock" --work="$WORK"
	run_scene_suite test_card_picture "CARD PICTURE TESTS" "$MIN_CASES_CARD_PICTURE"
	run_connected_suite test_launch_news "LAUNCH NEWS TESTS" "$MIN_CASES_LAUNCH_NEWS" news "$RUN_TIMEOUT"
	run_connected_suite test_refusal_ladder "REFUSAL LADDER TESTS" "$MIN_CASES_REFUSAL_LADDER" ladder 300
	run_scene_suite test_desk_signal "DESK SIGNAL TESTS" "$MIN_CASES_DESK_SIGNAL"
	run_scene_suite test_desk_signal_wiring "DESK SIGNAL WIRING TESTS" "$MIN_CASES_DESK_SIGNAL_WIRING" -- --read-only \
		--socket="$WORK/desk-signal-nowhere.sock" --work="$WORK"
	run_scene_suite test_pick_follows_write "PICK FOLLOWS WRITE TESTS" "$MIN_CASES_PICK_FOLLOWS_WRITE"
}

# Validate the entire selection before imports, Python tests or fake processes.
# The collection pass does not inspect or execute any GDScript.
WORK=""
SELECTED=""
LIST_ONLY=1
run_suites
if [ -n "$SHARD" ]; then
	if ! [[ "$SHARD" =~ ^[1-9][0-9]*/[1-9][0-9]*$ ]]; then
		echo "RUN_TESTS: SHARD must be i/n with positive decimal integers (no leading zeroes)"
		exit 2
	fi
	shard_index="${SHARD%/*}"
	shard_count="${SHARD#*/}"
	read -r -a all_suites <<<"$SELECTED"
	suite_count="${#all_suites[@]}"
	# Bound lengths before integer comparisons: huge inputs must not overflow
	# into valid shard numbers. No empty shards: empty SUITES means all suites.
	if [ "${#shard_index}" -gt "${#suite_count}" ] || [ "${#shard_count}" -gt "${#suite_count}" ] \
		|| [ "$shard_count" -gt "$suite_count" ] || [ "$shard_index" -gt "$shard_count" ]; then
		echo "RUN_TESTS: SHARD requires 1 <= i <= n <= $suite_count (the number of suites)"
		exit 2
	fi
	SELECTED=""
	ordinal=0
	for name in "${all_suites[@]}"; do
		if [ "$((ordinal % shard_count + 1))" -eq "$shard_index" ]; then
			SELECTED="$SELECTED $name"
		fi
		ordinal=$((ordinal + 1))
	done
	SUITES="${SELECTED# }"
	read -r -a requested <<<"$SUITES"
fi
if [ -n "$SUITES" ]; then
	for name in "${requested[@]}"; do
		case "$SELECTED " in
			*" $name "*) ;;
			*) echo "RUN_TESTS: unknown suite '$name'"; exit 2 ;;
		esac
	done
fi
for name in $SELECTED; do
	[ -f "$ROOT/tools/$name.gd" ] || { echo "RUN_TESTS: missing tools/$name.gd"; exit 2; }
done
if [ "${1:-}" = --list ]; then
	for name in $SELECTED; do printf '%s\n' "$name"; done
	exit 0
fi
if [ -n "$SHARD" ]; then
	echo "== shard $SHARD:$SELECTED"
elif [ -n "$SUITES" ]; then
	echo "== suites:$SELECTED"
fi

# Unix socket paths stop at ~104 bytes on macOS: keep them short, under /tmp.
WORK="$(mktemp -d /tmp/herdstead-test.XXXXXX)" || exit 2
trap cleanup EXIT
trap 'exit 130' INT TERM
status=0
LIST_ONLY=0

# A focused run is Godot-only. Full checks ran the Python targets already;
# plain `make test` retains the table, CLI and real-engine harness contracts.
if [ -z "$SUITES" ] && [ "${HERDSTEAD_SKIP_PYTHON_TESTS:-}" != 1 ]; then
	for script in test_table_assets test_dev_tools test_harness; do
		echo "== $script"
		GODOT="$GODOT" "$PYTHON" "$ROOT/tools/$script.py" -v 2>&1 | tee "$WORK/$script.log"
		[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
	done
fi

# class_name scripts and textures need a fresh import cache, even in focused runs.
GODOT="$GODOT" bash "$ROOT/tools/import_if_stale.sh" 2>&1 | tee "$WORK/import.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "RUN_TESTS: import failed"; exit 2; }
if [ "${HERDSTEAD_SKIP_LOAD_CHECKS:-}" = 1 ]; then
	echo "== script and pack load checks skipped (HERDSTEAD_SKIP_LOAD_CHECKS=1)"
else
	for stage in scripts packs; do
		echo "== check_$stage"
		bounded "$GODOT" --headless --path "$ROOT" --script "tools/check_$stage.gd" 2>&1 | tee "$WORK/$stage.log"
		stage_status=${PIPESTATUS[0]}
		marker="$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]')_OK"
		if grep -Eq 'SCRIPT ERROR|Parse Error' "$WORK/$stage.log" || ! grep -q "^$marker" "$WORK/$stage.log"; then
			echo "RUN_TESTS: check_$stage did not finish successfully"
			[ "$stage_status" -eq 0 ] && stage_status=1
		fi
		[ "$stage_status" -eq 0 ] || exit "$stage_status"
	done
fi

run_suites
echo "RUN_TESTS: exit $status in $(( $(date +%s) - started ))s"
exit "$status"
