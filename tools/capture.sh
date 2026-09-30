#!/usr/bin/env bash
# PNGs of what the project looks like right now: the showroom,
# the pixel people showroom at 2x and 4x, the live office against a fake herdr
# at zoom 2 and zoom 4 (and with the drawer open, `--drawer=open`, every run
# starting with it closed), the agent list in its flat and tree views
# at 2x, 4x and the 480x320 minimum, and with three machines (one of them
# dropped, one with worktree mezzanines), the NEWS strip and the drawer's
# EVENTS page after a run of state changes (`--drawer=events`, office-events-*
# at 2x and the minimum), an agent starting in a shell as herdr's snapshot
# shows it (office-starting-*, 2x, 4x and the minimum) and one that blocks before its
# launch is over (office-blocked-start-*), the agent list's
# History group after that run (list-history-*), the drawer's two pages with
# few rows (no scroll bar) and with more than they hold (the thin bar:
# drawer-few-* / drawer-scroll-*, 2x, 4x and the minimum), the agent card as an operator with
# scripted terminal text (working and blocked) at zoom 2 and 4, its answer mode
# (tools/capture_card.gd, by real input: picked (the staff panel's one line, at every size),
# offered and open on a blocked agent, 12 of 31 rows
# clipped, not sent, unknown result, a refused line; START AGENT on a shell and
# NEW PANE BESIDE on an agent; Close armed on a working agent and a branch typed
# for a worktree) at 2x and 4x
# and at the 480x320 minimum; and the left column's FLOORS minimap with the signposts on the
# worktrees fixture (mezzanines shown), beside a machine that drops mid-run and
# one that never answers, at 2x, 4x and the minimum; and the
# OVERVIEW (`--overview=open`): the showroom's two-hour mock, and
# the live office's while a run of state changes lands, at 2x, 4x and the minimum.
# The lens held (`--lens=held`, office-lens-*: 2x, 4x and the minimum) and the
# hover mark on a desk and on another floor's FLOORS row (`--point=`, office-point-*).
# The strategic view (`--strategic=open`, office-strategic-*): the 80-pane stress
# floor at 2x, 4x and the minimum, and the lens's stage at 2x.
#
# Zoom is even only (OfficeScene.content_scale_for): the default 1920x960
# window holds 2x and nothing more, so every 4x picture runs in a 1920x1280
# window, and the 480x320 minimum is a 960x640 window at 2x. A display too
# small for the window a shot asks shrinks it, and maybe its scale with it:
# every capture checks the window it got against --resolution (CaptureDriver)
# and the office, card and monitor ones the scale they show against --zoom,
# and quit non-zero, so that shot fails with CAPTURE_FAILED instead of saving
# a smaller picture.
# CI uploads them on every PR, so a visual change carries its own picture.
#
# The office and agent list pictures run `--read-only`: a screenshot never
# carries terminal text. Only the card pictures run as an operator, and what
# their preview shows is text this script hands the fake, never a terminal's;
# the answer-mode pictures write to that fake, and to nothing else.
#
#   tools/capture.sh [OUT_DIR]          (default build/captures)
#   GODOT=/path/to/godot tools/capture.sh /tmp/shots
#   DWELL=8 CAPTURE_MARGIN=120 tools/capture.sh /tmp/shots
#
# Never --headless: capturing needs a real viewport (a headless capture never
# finishes, measured on 4.7.2). On a machine without a display (CI), this
# wraps Godot in xvfb-run, which needs `xvfb` installed.
# No step can hang the run: each Godot is killed once it outlives its own
# --wait= by CAPTURE_MARGIN seconds. A killed step is tried once more (said on
# a CAPTURE_RETRY line; a step whose fake herdr it disturbs sets that fake up
# again first), and a second hang fails the run naming its picture. Before
# every step, and before staging its fake herdr, it waits until no other
# windowed Godot runs (tools/wait_for_screen.sh): a covered window can stop
# drawing on macOS, and a step waiting for its frame then hangs. It
# imports the project first when Godot's import cache is behind assets/
# (tools/import_if_stale.sh), so a picture never shows textures from before
# the last `make art`.
# The fake herdr it starts is always stopped again, and so is a Godot still
# running, including on Ctrl-C.
#
# The same views on every machine: the office is pinned to the daylight
# pack (`--pack=` beats the remembered theme) and pointed at a herdr, a machine
# list and a forward directory that do not exist outside this run, so nothing
# here reaches the operator's own herdr, machines or SSH tunnels.
set -u

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/captures}"
case "$OUT" in
	/*) ;;
	*) OUT="$PWD/$OUT" ;;
esac
# How long the office waits for herdr's first snapshot before it captures.
DWELL="${DWELL:-4}"
# What a step may take beyond its own --wait= before the watchdog kills it:
# Godot starting, CaptureDriver's wait for the scene (8 s at most) and the frame
# it saves. Generous: a software renderer on CI starts slowly.
CAPTURE_MARGIN="${CAPTURE_MARGIN:-60}"
case "$CAPTURE_MARGIN" in
	'' | *[!0-9]*)
		echo "CAPTURE: CAPTURE_MARGIN is whole seconds, not '$CAPTURE_MARGIN'"
		exit 2
		;;
esac
# Which pictures: `all` (the default), or `ci`: the showroom, the pixel
# people and the live office at 2x and 4x, what a change looks like within
# CI's time (about half a minute there; the whole set takes over ten), and the
# office at night at 2x.
CAPTURE_SET="${CAPTURE_SET:-all}"
case "$CAPTURE_SET" in
	all | ci) ;;
	*)
		echo "CAPTURE: CAPTURE_SET is all or ci, not '$CAPTURE_SET'"
		exit 2
		;;
esac

if [ -x "$ROOT/.venv/bin/python" ]; then
	DEFAULT_PYTHON="$ROOT/.venv/bin/python"
else
	DEFAULT_PYTHON="python3"
fi
PYTHON="${PYTHON:-$DEFAULT_PYTHON}"

GODOT="$GODOT" bash "$ROOT/tools/import_if_stale.sh" || {
	echo "CAPTURE_FAILED: the project would not import"
	exit 2
}

# Unix socket paths stop at ~104 bytes on macOS: keep them short, under /tmp.
WORK="$(mktemp -d /tmp/herdstead-capture.XXXXXX)"
SERVER_PID=""
# The second fake herdr of the floors pictures: a machine that drops.
BEE_PID=""
# The agent list's two extra machines (see below).
LANES_PID=""
FAR_PID=""
# The fake herdr serving the 80-pane stress floor (the drawer's scroll bar).
STRESS_PID=""
# The Godot step running now and its watchdog; empty between steps.
GODOT_PID=""
WATCHDOG_PID=""

# Kill a step at once: the process and whatever it started. xvfb-run is a
# shell script that leaves its Godot and its Xvfb running when only it dies.
kill_step() {
	pkill -KILL -P "$1" 2>/dev/null
	kill -KILL "$1" 2>/dev/null
}

cleanup() {
	# A step runs in the background, where Ctrl-C does not reach it: stop it here.
	if [ -n "$WATCHDOG_PID" ]; then
		kill "$WATCHDOG_PID" 2>/dev/null
		wait "$WATCHDOG_PID" 2>/dev/null
	fi
	if [ -n "$GODOT_PID" ]; then
		kill_step "$GODOT_PID"
		wait "$GODOT_PID" 2>/dev/null
	fi
	for pid in "$SERVER_PID" "$BEE_PID" "$LANES_PID" "$FAR_PID" "$STRESS_PID"; do
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
		fi
	done
	rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# One Godot step. A headless Linux box has no display; xvfb-run gives Godot
# one. Everywhere else (macOS, or a Linux desktop) Godot opens a real window.
# macOS has no timeout(1), so a watchdog in the background (the one
# tools/run_tests.sh bounds its suites with) kills the step once it outlives
# its own --wait= by CAPTURE_MARGIN seconds. Either way a failed step ends the
# run here, naming the picture it was for: a scene that cannot write its
# picture quits non-zero, and the missing-PNG check below would catch it too,
# but only after every other step.
godot_run() {
	local shot="Godot" dwell=0 argument window="" previous=""
	for argument in "$@"; do
		case "$argument" in
			--capture=*) shot="$(basename "${argument#--capture=}")" ;;
			--wait=*) dwell="${argument#--wait=}" ;;
		esac
		[ "$previous" = "--resolution" ] && window="$argument"
		previous="$argument"
	done
	# The engine keeps --resolution to itself: hand the capture the size it
	# asked for, so it can refuse a window the OS made smaller (CaptureDriver).
	if [ -n "$window" ]; then
		set -- "$@" --window="$window"
	fi
	# CaptureDriver reads a --wait= that is not a number as 0; so does this.
	case "$dwell" in
		'' | *[!0-9.]*) dwell=0 ;;
	esac
	# Whole seconds for sleep, in base 10 whatever the zeros: a fraction rounds up.
	local whole="${dwell%%.*}"
	whole=$((10#${whole:-0}))
	case "$dwell" in
		*.*[1-9]*) whole=$((whole + 1)) ;;
	esac
	local limit=$((whole + 10#$CAPTURE_MARGIN))
	local attempt status
	for attempt in 1 2; do
		# Wait for the screen before staging: a stage can start its own clock
		# (stage_events pushes its changes once the office subscribes, or after
		# 30 s whatever happened), and a wait behind another window would spend
		# that clock before this Godot even opens.
		GODOT="$GODOT" bash "$ROOT/tools/wait_for_screen.sh" || {
			echo "CAPTURE_FAILED: $shot: another windowed Godot never finished"
			exit 1
		}
		# A step that stages a fake herdr (CAPTURE_PREPARE names the function)
		# stages it again for every attempt.
		if [ -n "${CAPTURE_PREPARE:-}" ]; then
			"$CAPTURE_PREPARE"
		fi
		godot_attempt "$limit" "$@"
		status=$?
		if [ "$status" -eq 124 ] && [ "$attempt" -eq 1 ]; then
			echo "CAPTURE_RETRY: $shot: Godot still running after ${limit}s (--wait=$dwell plus ${CAPTURE_MARGIN}s); killed it, trying once more"
			continue
		fi
		break
	done
	if [ "$status" -eq 124 ]; then
		echo "CAPTURE_FAILED: $shot: Godot still running after ${limit}s (--wait=$dwell plus ${CAPTURE_MARGIN}s), twice; killed it"
		exit 1
	fi
	if [ "$status" -ne 0 ]; then
		echo "CAPTURE_FAILED: $shot: Godot exited $status"
		exit "$status"
	fi
}

# One Godot run of a step, killed after `$1` seconds: its exit status, or 124
# when the watchdog killed it.
godot_attempt() {
	local limit="$1"
	shift
	rm -f "$WORK/overdue"
	if [ "$(uname -s)" = "Linux" ] && [ -z "${DISPLAY:-}" ]; then
		xvfb-run -a "$GODOT" --display-driver x11 --audio-driver Dummy "$@" &
	else
		"$GODOT" "$@" &
	fi
	GODOT_PID=$!
	# Detached from stdout so nothing waits on it, and it takes its sleep down
	# with it when cancelled.
	(
		trap 'kill "$nap" 2>/dev/null; exit 0' TERM
		sleep "$limit" &
		nap=$!
		wait "$nap"
		: >"$WORK/overdue"
		kill_step "$GODOT_PID"
	) >/dev/null 2>&1 &
	WATCHDOG_PID=$!
	wait "$GODOT_PID"
	local status=$?
	GODOT_PID=""
	kill "$WATCHDOG_PID" 2>/dev/null
	wait "$WATCHDOG_PID" 2>/dev/null
	WATCHDOG_PID=""
	if [ -e "$WORK/overdue" ]; then
		return 124
	fi
	return "$status"
}

mkdir -p "$OUT"
SHOTS="preview-daylight.png office-zoom2.png office-zoom4.png office-drawer-open-zoom2.png"
# The same office at night (`--light=night`, DayLight), 2x, 4x and the 480x320 minimum.
SHOTS="$SHOTS office-night-zoom2.png office-night-zoom4.png office-night-min.png"
# NEWS and the drawer's EVENTS page after a run of status changes, 2x and the 480x320 minimum.
SHOTS="$SHOTS office-events-zoom2.png office-events-min.png"
# An agent starting in the shell api:p3: walking in from the door under the hourglass, 2x, 4x and the minimum.
SHOTS="$SHOTS office-starting-zoom2.png office-starting-zoom4.png office-starting-min.png"
# A start that asks at once: hand up, bubble with its wait, the blocked badge, 2x, 4x and the minimum.
SHOTS="$SHOTS office-blocked-start-zoom2.png office-blocked-start-zoom4.png office-blocked-start-min.png"
# The agent list's History unfolded after that run of changes, and the drawer's
# two pages with few rows and with more than they hold: 2x, 4x and the minimum.
for scale in zoom2 zoom4 min; do
	SHOTS="$SHOTS list-history-$scale.png"
	for page in agents events; do
		SHOTS="$SHOTS drawer-few-$page-$scale.png drawer-scroll-$page-$scale.png"
	done
done
# The agent list: flat (raised with --attention) and tree, per pack and scale.
LIST_TAGS="daylight-zoom2 daylight-zoom4 daylight-min"
for tag in $LIST_TAGS; do
	SHOTS="$SHOTS list-flat-$tag.png list-tree-$tag.png"
done
SHOTS="$SHOTS list-machines-flat-zoom2.png list-machines-tree-zoom2.png list-machines-tree-zoom4.png"
SHOTS="$SHOTS card-working-zoom2.png card-working-zoom4.png card-blocked-zoom2.png card-blocked-zoom4.png"
# Answer mode and the START AGENT block: every state of tools/capture_card.gd, per pack and scale.
CARD_TAGS="daylight-zoom2 daylight-zoom4 daylight-min"
for tag in $CARD_TAGS; do
	for state in picked offered answer rows not-sent unknown line-refused start start-confirm start-no-prompt new close-confirm worktree; do
		SHOTS="$SHOTS card-$state-$tag.png"
	done
done
# The terminal monitor (tools/capture_monitor.gd): the recorded screens, an
# unknown result, offline and read-only, per pack and scale.
for tag in $CARD_TAGS; do
	for state in claude codex vim torture unknown offline view-only; do
		SHOTS="$SHOTS monitor-$state-$tag.png"
	done
done
# The minimap on the mezzanine 1A, and on 1F with the signpost down to 1A:
# per pack, 2x, 4x and the 480x320 minimum.
for pack in daylight; do
	for scale in zoom2 zoom4 min; do
		SHOTS="$SHOTS floors-$pack-$scale.png floors-signposts-$pack-$scale.png"
	done
done
# The pixel people showroom at 2x and 4x. Listed here so an old picture is
# removed first and a missing one fails the run.
SHOTS="$SHOTS people-zoom2.png people-zoom4.png"
# The OVERVIEW: the showroom's mock log per pack, the live office per scale.
SHOTS="$SHOTS preview-overview-daylight.png"
SHOTS="$SHOTS office-overview-zoom2.png office-overview-zoom4.png office-overview-min.png"
# The lens held (`--lens=held`) over a stage with blocked and done since
# before the office watched, working, idle in the pantry and a shell: 2x, 4x, the
# minimum; and the hover mark (`--point=`) on a desk and on another
# floor's FLOORS row, 2x.
SHOTS="$SHOTS office-lens-zoom2.png office-lens-zoom4.png office-lens-min.png"
SHOTS="$SHOTS office-point-zoom2.png office-point-floor-zoom2.png"
# The strategic view (`--strategic=open`) on the 80-pane stress floor at 2x,
# 4x and the minimum, and on the lens's stage (a `+` wait, idle, done, a shell).
SHOTS="$SHOTS office-strategic-zoom2.png office-strategic-zoom4.png office-strategic-min.png"
SHOTS="$SHOTS office-strategic-floors-zoom2.png"
if [ "$CAPTURE_SET" = ci ]; then
	SHOTS="preview-daylight.png people-zoom2.png people-zoom4.png office-zoom2.png office-zoom4.png office-night-zoom2.png"
fi
for shot in $SHOTS; do
	rm -f "$OUT/$shot"
done

# Godot exits 0 even when it drew nothing, so the pictures are the check: a
# capture step that quietly produces no PNG is the failure this step exists for.
finish() {
	local missing=""
	for shot in $SHOTS; do
		[ -s "$OUT/$shot" ] || missing="$missing $shot"
	done
	if [ -n "$missing" ]; then
		echo "CAPTURE_FAILED: no picture for$missing"
		exit 1
	fi
	echo "CAPTURE_OK: $OUT"
	ls -l "$OUT"
	exit 0
}

echo "== showroom"
godot_run --path "$ROOT" scenes/preview.tscn -- --capture="$OUT/preview-daylight.png"
# The overview over the showroom, fed a two-hour mock state log (preview.gd).
if [ "$CAPTURE_SET" = all ]; then
	for pack in daylight; do
		godot_run --path "$ROOT" scenes/preview.tscn -- --pack=res://assets/$pack/manifest.json \
			--overview=open --capture="$OUT/preview-overview-$pack.png"
	done
fi

echo "== pixel people showroom"
# Every catalog agent in its own look, one screen pixel per pixel times --zoom.
for zoom in 2 4; do
	godot_run --path "$ROOT" scenes/people_showroom.tscn -- --zoom="$zoom" --capture="$OUT/people-zoom$zoom.png"
done

echo "== live office against a fake herdr"
# One JSON command on the fake's control socket (see tools/fake_herdr.py).
ctl() {
	ctl_at "$WORK/herdr-ctl.sock" "$1" "$2"
}
# The same, on the control socket `$1`.
ctl_at() {
	"$PYTHON" - "$1" "$2" "$3" <<'PY' || exit 2
import json, socket, sys
conn = socket.socket(socket.AF_UNIX)
conn.connect(sys.argv[1])
conn.sendall((json.dumps({"cmd": sys.argv[2], "args": json.loads(sys.argv[3])}) + "\n").encode())
answer = json.loads(conn.makefile().readline())
if not answer.get("ok"):
    sys.exit("CAPTURE: fake herdr refused %s: %s" % (sys.argv[2], answer))
PY
}
"$PYTHON" "$ROOT/tools/fake_herdr.py" \
	--socket="$WORK/herdr.sock" --control="$WORK/herdr-ctl.sock" \
	--fixtures="$ROOT/tools/fixtures" --fixture=snapshot_floors &
SERVER_PID=$!
for _ in $(seq 1 100); do
	[ -S "$WORK/herdr.sock" ] && break
	kill -0 "$SERVER_PID" 2>/dev/null || { echo "CAPTURE: fake herdr died on start"; exit 2; }
	sleep 0.05
done
if [ ! -S "$WORK/herdr.sock" ]; then
	echo "CAPTURE: fake herdr never came up"
	exit 2
fi

# No herdr binary to ask for machines, and no directory to open a forward in.
export HERDR_BIN_PATH="$WORK/no-herdr"
export HERDSTEAD_SOCKET_DIR="$WORK/socks"
# The 4x shots need a 1920x1280 window: the default 1920x960 one holds only 2x.
window_for() {
	if [ "$1" = 4 ]; then
		echo "--resolution 1920x1280"
	fi
}
for zoom in 2 4; do
	# shellcheck disable=SC2046
	godot_run --path "$ROOT" $(window_for "$zoom") -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" \
		--wait="$DWELL" --capture="$OUT/office-zoom$zoom.png"
done
# At night: the world darker and cooler, the lamps harder, the night window.
for view in "zoom2 2" "zoom4 4 --resolution 1920x1280" "min 2 --resolution 960x640"; do
	read -r shot zoom window <<<"$view"
	if [ "$CAPTURE_SET" = ci ] && [ "$shot" != zoom2 ]; then
		continue
	fi
	# shellcheck disable=SC2086
	godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" --light=night \
		--wait="$DWELL" --capture="$OUT/office-night-$shot.png"
done
[ "$CAPTURE_SET" = ci ] && finish
# The agent list's drawer open (every run starts with it closed to its tab):
# the world gives the column its room, the floor keeps the plan it has for the tab.
godot_run --path "$ROOT" -- --socket="$WORK/herdr.sock" --read-only \
	--pack=res://assets/daylight/manifest.json --zoom=2 --drawer=open \
	--wait="$DWELL" --capture="$OUT/office-drawer-open-zoom2.png"
# A run of status changes on Local, pushed once the office has subscribed (a
# change before its first snapshot would be its baseline, not news), so NEWS
# and EVENTS have something to say. Staged again for every attempt of a picture.
EVENTS_PID=""
EVENT_CHANGES=("api:p1 blocked" "web:p2 working" "api:p4 done" "infra:p3 blocked" "api:p1 working")
EVENT_GAP=0.7
stage_events() {
	if [ -n "$EVENTS_PID" ]; then
		kill "$EVENTS_PID" 2>/dev/null
		wait "$EVENTS_PID" 2>/dev/null
	fi
	ctl reset '{"fixture": "snapshot_floors"}'
	(
		"$PYTHON" - "$WORK/herdr-ctl.sock" <<'PY'
import json, socket, sys, time
deadline = time.time() + 30
while time.time() < deadline:
    try:
        conn = socket.socket(socket.AF_UNIX)
        conn.connect(sys.argv[1])
        conn.sendall((json.dumps({"cmd": "stats", "args": {}}) + "\n").encode())
        answer = json.loads(conn.makefile().readline())
        conn.close()
        if answer.get("result", answer).get("subscribe_count", 0) >= 1:
            break
    except (OSError, ValueError, AttributeError):
        pass
    time.sleep(0.2)
PY
		sleep 1
		for change in "${EVENT_CHANGES[@]}"; do
			read -r pane state <<<"$change"
			ctl status "{\"pane_id\": \"$pane\", \"agent_status\": \"$state\"}"
			sleep "$EVENT_GAP"
		done
	) &
	EVENTS_PID=$!
}
for scale in zoom2 min; do
	window=""
	[ "$scale" = "min" ] && window="--resolution 960x640"
	# shellcheck disable=SC2086
	CAPTURE_PREPARE=stage_events godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom=2 --drawer=events \
		--wait=6 --capture="$OUT/office-events-$scale.png"
	wait "$EVENTS_PID" 2>/dev/null
	EVENTS_PID=""
done
# The shots after these read the fixture as it was.
ctl reset '{"fixture": "snapshot_floors"}'
# A start herdr accepted in the shell api:p3, as the next snapshot shows it: an
# agent record named claude-2 and still launching, no kind detected yet. Set
# 1.5 s after the office subscribed, with a status event 0.7 s later so it asks
# for that snapshot (a read-only office: nothing is sent to the fake).
LAUNCH_PID=""
stage_launch() {
	if [ -n "$LAUNCH_PID" ]; then
		kill "$LAUNCH_PID" 2>/dev/null
		wait "$LAUNCH_PID" 2>/dev/null
	fi
	ctl reset '{"fixture": "snapshot_floors"}'
	(
		"$PYTHON" - "$WORK/herdr-ctl.sock" "$ROOT/tools/fixtures/snapshot_floors.json" <<'PY'
import json, socket, sys, time


def ctl(cmd, args):
    conn = socket.socket(socket.AF_UNIX)
    conn.connect(sys.argv[1])
    conn.sendall((json.dumps({"cmd": cmd, "args": args}) + "\n").encode())
    answer = json.loads(conn.makefile().readline())
    conn.close()
    return answer.get("result", answer)


deadline = time.time() + 30
while time.time() < deadline:
    try:
        if ctl("stats", {}).get("subscribe_count", 0) >= 1:
            break
    except (OSError, ValueError, AttributeError):
        pass
    time.sleep(0.2)
time.sleep(1.5)
with open(sys.argv[2], encoding="utf-8") as source:
    snapshot = json.load(source)["snapshot"]
shell = next(pane for pane in snapshot["panes"] if pane["pane_id"] == "api:p3")
record = {field: shell.get(field) for field in ("pane_id", "workspace_id", "tab_id", "terminal_id", "cwd")}
record.update({"name": "claude-2", "launch_pending": True, "agent_status": "unknown", "state_change_seq": 0})
snapshot.setdefault("agents", []).append(record)
ctl("set_snapshot", {"snapshot": snapshot})
time.sleep(0.7)
ctl("status", {"pane_id": "api:p3", "agent_status": "unknown"})
PY
	) &
	LAUNCH_PID=$!
}
for scale in zoom2 zoom4 min; do
	zoom="${scale#zoom}"
	window="$(window_for "$zoom")"
	if [ "$scale" = "min" ]; then
		window="--resolution 960x640"
		zoom=2
	fi
	# shellcheck disable=SC2086
	CAPTURE_PREPARE=stage_launch godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" \
		--wait=4 --capture="$OUT/office-starting-$scale.png"
	wait "$LAUNCH_PID" 2>/dev/null
	LAUNCH_PID=""
done
# A start that asks at once (blocked comes first): claude-2
# comes up in api:p3 as claude, still launching, and blocks 0.7 s later, a
# status event the office watches (so its wait has a known start). web:p1 and
# infra:p1 are at work here, so it is the one agent blocked and NEXT names it;
# the picture waits for the worker to walk in from the door and sit down.
stage_blocked_start() {
	if [ -n "$LAUNCH_PID" ]; then
		kill "$LAUNCH_PID" 2>/dev/null
		wait "$LAUNCH_PID" 2>/dev/null
	fi
	ctl reset '{"fixture": "snapshot_floors"}'
	(
		"$PYTHON" - "$WORK/herdr-ctl.sock" "$ROOT/tools/fixtures/snapshot_floors.json" <<'PY'
import json, socket, sys, time


def ctl(cmd, args):
    conn = socket.socket(socket.AF_UNIX)
    conn.connect(sys.argv[1])
    conn.sendall((json.dumps({"cmd": cmd, "args": args}) + "\n").encode())
    answer = json.loads(conn.makefile().readline())
    conn.close()
    return answer.get("result", answer)


deadline = time.time() + 30
while time.time() < deadline:
    try:
        if ctl("stats", {}).get("subscribe_count", 0) >= 1:
            break
    except (OSError, ValueError, AttributeError):
        pass
    time.sleep(0.2)
time.sleep(1.5)
with open(sys.argv[2], encoding="utf-8") as source:
    snapshot = json.load(source)["snapshot"]
for pane in snapshot["panes"] + snapshot.get("agents", []):
    if pane.get("pane_id") in ("web:p1", "infra:p1"):
        pane["agent_status"] = "working"
shell = next(pane for pane in snapshot["panes"] if pane["pane_id"] == "api:p3")
shell.update({"agent": "claude", "agent_status": "unknown"})
# herdr's focus on it, so the office frames its desk and the card shows it.
snapshot.update({"focused_pane_id": "api:p3", "focused_tab_id": shell["tab_id"], "focused_workspace_id": "api"})
record = {field: shell.get(field) for field in ("pane_id", "workspace_id", "tab_id", "terminal_id", "cwd")}
record.update({"agent": "claude", "name": "claude-2", "launch_pending": True, "agent_status": "unknown"})
record["state_change_seq"] = 0
snapshot.setdefault("agents", []).append(record)
ctl("set_snapshot", {"snapshot": snapshot})
time.sleep(0.7)
ctl("status", {"pane_id": "api:p3", "agent_status": "blocked"})
PY
	) &
	LAUNCH_PID=$!
}
for scale in zoom2 zoom4 min; do
	zoom="${scale#zoom}"
	window="$(window_for "$zoom")"
	if [ "$scale" = "min" ]; then
		window="--resolution 960x640"
		zoom=2
	fi
	# shellcheck disable=SC2086
	CAPTURE_PREPARE=stage_blocked_start godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" \
		--read-only --pack=res://assets/daylight/manifest.json --zoom="$zoom" \
		--wait=12 --capture="$OUT/office-blocked-start-$scale.png"
	wait "$LAUNCH_PID" 2>/dev/null
	LAUNCH_PID=""
done
ctl reset '{"fixture": "snapshot_floors"}'

echo "== the drawer: History, and its two pages with few rows and with many"
# `--list=history` folds every group of the flat list but History: the lines
# the run of changes above leaves (api:p1 and web:p2 stopped waiting).
for scale in zoom2 zoom4 min; do
	zoom="${scale#zoom}"
	window="$(window_for "$zoom")"
	if [ "$scale" = "min" ]; then
		window="--resolution 960x640"
		zoom=2
	fi
	# shellcheck disable=SC2086
	CAPTURE_PREPARE=stage_events godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" --list=history --drawer=open \
		--wait=6 --capture="$OUT/list-history-$scale.png"
	wait "$EVENTS_PID" 2>/dev/null
	EVENTS_PID=""
done
# Few rows: the basic fixture's four panes on AGENTS; on EVENTS only Local
# coming online. No bar shows, and the rows keep its room.
ctl reset '{"fixture": "snapshot_basic"}'
for scale in zoom2 zoom4 min; do
	zoom="${scale#zoom}"
	window="$(window_for "$zoom")"
	if [ "$scale" = "min" ]; then
		window="--resolution 960x640"
		zoom=2
	fi
	# shellcheck disable=SC2086
	godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" --drawer=open \
		--wait="$DWELL" --capture="$OUT/drawer-few-agents-$scale.png"
	# shellcheck disable=SC2086
	godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" --drawer=events \
		--wait="$DWELL" --capture="$OUT/drawer-few-events-$scale.png"
done
ctl reset '{"fixture": "snapshot_floors"}'
# More than they hold: the 80-pane stress floor on AGENTS (its own fake), and a
# run of eighteen changes on EVENTS. The thin bar shows at the pages' right.
"$PYTHON" "$ROOT/tools/gen_stress_fixture.py" --output "$WORK/stress" >/dev/null || exit 2
"$PYTHON" "$ROOT/tools/fake_herdr.py" \
	--socket="$WORK/stress.sock" --control="$WORK/stress-ctl.sock" \
	--fixtures="$WORK/stress" --fixture=snapshot_stress80 &
STRESS_PID=$!
for _ in $(seq 1 100); do
	[ -S "$WORK/stress.sock" ] && break
	sleep 0.05
done
EVENT_CHANGES=()
for _ in 1 2 3; do
	EVENT_CHANGES+=("api:p1 blocked" "web:p2 working" "api:p4 done" "api:p1 working" "web:p2 done" "api:p4 working")
done
EVENT_GAP=0.3
for scale in zoom2 zoom4 min; do
	zoom="${scale#zoom}"
	window="$(window_for "$zoom")"
	if [ "$scale" = "min" ]; then
		window="--resolution 960x640"
		zoom=2
	fi
	# shellcheck disable=SC2086
	godot_run --path "$ROOT" $window -- --socket="$WORK/stress.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" --drawer=open \
		--wait="$DWELL" --capture="$OUT/drawer-scroll-agents-$scale.png"
	# shellcheck disable=SC2086
	CAPTURE_PREPARE=stage_events godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" --drawer=events \
		--wait=9 --capture="$OUT/drawer-scroll-events-$scale.png"
	wait "$EVENTS_PID" 2>/dev/null
	EVENTS_PID=""
done
# The strategic view over the same stress floor: every one of the 80 squares.
for view in "zoom2 2 daylight" "zoom4 4 daylight --resolution 1920x1280" "min 2 daylight --resolution 960x640"; do
	read -r shot zoom pack window <<<"$view"
	# shellcheck disable=SC2086
	godot_run --path "$ROOT" $window -- --socket="$WORK/stress.sock" --read-only \
		--pack=res://assets/$pack/manifest.json --zoom="$zoom" --strategic=open \
		--wait="$DWELL" --capture="$OUT/office-strategic-$shot.png"
done
kill "$STRESS_PID" 2>/dev/null
wait "$STRESS_PID" 2>/dev/null
STRESS_PID=""
EVENT_CHANGES=("api:p1 blocked" "web:p2 working" "api:p4 done" "infra:p3 blocked" "api:p1 working")
EVENT_GAP=0.7
ctl reset '{"fixture": "snapshot_floors"}'

echo "== the agent list, flat and tree, against the same fake herdr"
# The minimum is a 960x640 window at 2x: the 480x320 screen, as is 4x in the
# 1920x1280 window. The staff panel along the bottom is its one line at every
# size. The flat shots hold the keyboard (--attention), the tree shots not;
# every list shot opens the drawer, which every run starts closed.
for pack in daylight; do
	for scale in zoom2 zoom4 min; do
		zoom="${scale#zoom}"
		window="$(window_for "$zoom")"
		if [ "$scale" = "min" ]; then
			window="--resolution 960x640"
			zoom=2
		fi
		# shellcheck disable=SC2086
		godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
			--pack=res://assets/$pack/manifest.json --zoom="$zoom" --attention \
			--wait="$DWELL" --capture="$OUT/list-flat-$pack-$scale.png"
		# shellcheck disable=SC2086
		godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
			--pack=res://assets/$pack/manifest.json --zoom="$zoom" --list=tree --drawer=open \
			--wait="$DWELL" --capture="$OUT/list-tree-$pack-$scale.png"
	done
done

echo "== the agent list with three machines: one with worktree mezzanines, one dropped"
# Two more fakes: "lanes" serves the worktrees fixture and stays up; "far"
# serves the floors fixture and is stopped a second after it has answered its
# first snapshot (asked on its control socket, so a slow start cannot beat it),
# so the pictures show a machine that was live and dropped: grey, frozen,
# counted as nobody.
start_machine() {
	"$PYTHON" "$ROOT/tools/fake_herdr.py" \
		--socket="$WORK/$1.sock" --control="$WORK/$1-ctl.sock" \
		--fixtures="$ROOT/tools/fixtures" --fixture="$2" &
	MACHINE_PID=$!
	for _ in $(seq 1 100); do
		[ -S "$WORK/$1.sock" ] && break
		sleep 0.05
	done
}
start_machine lanes snapshot_worktrees
LANES_PID=$MACHINE_PID
# far, up again for every attempt of a picture, and stopped a second after
# it has answered its first snapshot.
stage_far() {
	if [ -n "$FAR_PID" ]; then
		kill "$FAR_PID" 2>/dev/null
		wait "$FAR_PID" 2>/dev/null
	fi
	rm -f "$WORK/far.sock" "$WORK/far-ctl.sock"
	start_machine far snapshot_floors
	FAR_PID=$MACHINE_PID
	(
		"$PYTHON" - "$WORK/far-ctl.sock" <<'PY'
import json, socket, sys, time
deadline = time.time() + 30
while time.time() < deadline:
    try:
        conn = socket.socket(socket.AF_UNIX)
        conn.connect(sys.argv[1])
        conn.sendall((json.dumps({"cmd": "stats", "args": {}}) + "\n").encode())
        answer = json.loads(conn.makefile().readline())
        conn.close()
        if answer.get("result", answer).get("snapshot_count", 0) >= 1:
            break
    except (OSError, ValueError, AttributeError):
        pass
    time.sleep(0.2)
PY
		sleep 1
		kill "$FAR_PID" 2>/dev/null
	) &
}
for shot in flat-zoom2 tree-zoom2 tree-zoom4; do
	view="${shot%-zoom*}"
	zoom="${shot#*-zoom}"
	# A tall window, so the list reaches down to the dropped machine; 4x needs
	# it 1920 wide.
	resolution=1600x1800
	[ "$zoom" = 4 ] && resolution=1920x1800
	CAPTURE_PREPARE=stage_far godot_run --path "$ROOT" --resolution "$resolution" -- --socket="$WORK/herdr.sock" --read-only \
		--machine-socket=lanes="$WORK/lanes.sock" --machine-socket=far="$WORK/far.sock" \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" --list="$view" --drawer=open \
		--wait=8 --capture="$OUT/list-machines-$shot.png"
	kill "$FAR_PID" 2>/dev/null
	wait "$FAR_PID" 2>/dev/null
	FAR_PID=""
done
kill "$LANES_PID" 2>/dev/null
wait "$LANES_PID" 2>/dev/null

echo "== the agent card as an operator, against the same fake herdr"
# Reads only: no picture clicks anything, so the one write stays closed.
ctl allow '{"methods": ["pane.read"]}'
ctl set_preview '{"pane_id": "api:p1", "source": "recent_unwrapped", "text": "$ make check\n== every script and scene loads\nSCRIPTS_OK: 133 scripts, 25 scenes\n== client + office tests\nTESTS OK: 50 cases, 411 checks, 0 failures\n== machine tests\nMACHINE TESTS OK: 28 cases, 612 checks\n== the write boundary (a long line the card clips, never wraps)\nCOMMAND TESTS OK: 28 cases\n--read-only builds no write boundary\nRUN_TESTS: exit 0 in 136s\n$ git status --short\n M scripts/herdr_fleet.gd\n"}'
ctl set_preview '{"pane_id": "api:p1", "source": "detection", "text": "Bash command\n\n  make capture OUT=/tmp/shots\n  Screenshot the office\n\nDo you want to proceed?\n> 1. Yes\n  2. Yes, and do not ask again\n  3. No, and tell Claude what to do\n"}'
for state in working blocked; do
	if [ "$state" = "blocked" ]; then
		# herdr's own focus is on api:p1; the card follows it and reads detection.
		ctl status '{"pane_id": "api:p1", "agent_status": "blocked"}'
	fi
	for zoom in 2 4; do
		# shellcheck disable=SC2046
		godot_run --path "$ROOT" $(window_for "$zoom") -- --socket="$WORK/herdr.sock" \
			--pack=res://assets/daylight/manifest.json --zoom="$zoom" \
			--wait="$DWELL" --capture="$OUT/card-$state-zoom$zoom.png"
	done
done

echo "== the agent card's answer mode, by real input, against the same fake herdr"
# tools/capture_card.gd resets the fake to the floors fixture, opens exactly
# the methods the card needs, and stages each state the way the tests do. The
# minimum is a 960x640 window at 2x: the 480x320 screen the HUD must fit.
for pack in daylight; do
	for zoom in 2 4; do
		# shellcheck disable=SC2046
		godot_run --path "$ROOT" $(window_for "$zoom") --script tools/capture_card.gd -- --wait=30 \
			--socket-a="$WORK/herdr.sock" --control-a="$WORK/herdr-ctl.sock" \
			--pack=res://assets/$pack/manifest.json --zoom="$zoom" --out="$OUT" --tag="$pack-zoom$zoom"
	done
	godot_run --path "$ROOT" --resolution 960x640 --script tools/capture_card.gd -- --wait=30 \
		--socket-a="$WORK/herdr.sock" --control-a="$WORK/herdr-ctl.sock" \
		--pack=res://assets/$pack/manifest.json --zoom=2 --out="$OUT" --tag="$pack-min"
done

echo "== the terminal monitor, by real input, against the same fake herdr"
# tools/capture_monitor.gd resets the fake to the floors fixture with one pane
# at 120x40, opens the monitor from the card, and shows the recorded dumps; its
# only writes are to the fake. The same scales as the card.
for pack in daylight; do
	for zoom in 2 4; do
		# shellcheck disable=SC2046
		godot_run --path "$ROOT" $(window_for "$zoom") --script tools/capture_monitor.gd -- --wait=40 \
			--socket-a="$WORK/herdr.sock" --control-a="$WORK/herdr-ctl.sock" \
			--pack=res://assets/$pack/manifest.json --zoom="$zoom" --out="$OUT" --tag="$pack-zoom$zoom"
	done
	godot_run --path "$ROOT" --resolution 960x640 --script tools/capture_monitor.gd -- --wait=40 \
		--socket-a="$WORK/herdr.sock" --control-a="$WORK/herdr-ctl.sock" \
		--pack=res://assets/$pack/manifest.json --zoom=2 --out="$OUT" --tag="$pack-min"
done

echo "== the minimap and the signposts: mezzanines, a machine that drops and one that never answers"
# Local serves the worktrees fixture. floors-* show floor 2, the mezzanine 1A
# (its plate names the checkout and its source); floors-signposts-* show floor
# 1, herdstead, with 1A and 1B hung below it, and since 1A has a blocked agent
# a signpost points down to it. bee serves the floors fixture and vanishes a few seconds in, while the office
# still waits for gone (a socket nobody listens on, so it waits its whole
# READY_TIMEOUT): the picture shows bee's last floors dimmed and frozen.
ctl reset '{"fixture": "snapshot_worktrees"}'
"$PYTHON" "$ROOT/tools/fake_herdr.py" \
	--socket="$WORK/bee.sock" --control="$WORK/bee-ctl.sock" \
	--fixtures="$ROOT/tools/fixtures" --fixture=snapshot_floors &
BEE_PID=$!
for _ in $(seq 1 100); do
	[ -S "$WORK/bee.sock" ] && break
	kill -0 "$BEE_PID" 2>/dev/null || { echo "CAPTURE: the second fake herdr died on start"; exit 2; }
	sleep 0.05
done
# bee, back and serving floors for every attempt, and gone again 5 s later.
DROPPER=""
stage_bee() {
	if [ -n "$DROPPER" ]; then
		wait "$DROPPER" 2>/dev/null
	fi
	ctl_at "$WORK/bee-ctl.sock" appear '{}'
	ctl_at "$WORK/bee-ctl.sock" reset '{"fixture": "snapshot_floors"}'
	(sleep 5 && ctl_at "$WORK/bee-ctl.sock" vanish '{}') &
	DROPPER=$!
}
floors() {
	local shot="$1" floor="$2" pack="$3" scale="$4" zoom=2
	shift 4
	[ "$scale" = zoom4 ] && zoom=4
	CAPTURE_PREPARE=stage_bee godot_run --path "$ROOT" "$@" -- --socket="$WORK/herdr.sock" --read-only \
		--machine-socket=bee="$WORK/bee.sock" --machine-socket=gone="$WORK/nobody.sock" \
		--pack=res://assets/$pack/manifest.json --zoom="$zoom" --space="$floor" \
		--wait=1.5 --capture="$OUT/$shot-$pack-$scale.png"
	wait "$DROPPER"
	DROPPER=""
}
for pack in daylight; do
	for view in "floors 2" "floors-signposts 1"; do
		read -r shot floor <<<"$view"
		floors "$shot" "$floor" "$pack" zoom2
		floors "$shot" "$floor" "$pack" zoom4 --resolution 1920x1280
		floors "$shot" "$floor" "$pack" min --resolution 960x640
	done
done

echo "== the overview over the live office, against the same fake herdr"
# A run of state changes lands while it is open (stage_events, above): the
# table's rows move and its timelines split.
EVENTS_PID=""
for view in "zoom2 2" "zoom4 4 --resolution 1920x1280" "min 2 --resolution 960x640"; do
	read -r shot zoom window <<<"$view"
	# shellcheck disable=SC2086
	CAPTURE_PREPARE=stage_events godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom="$zoom" --overview=open \
		--wait=6 --capture="$OUT/office-overview-$shot.png"
	wait "$EVENTS_PID" 2>/dev/null
	EVENTS_PID=""
done

echo "== the lens (hold L) and the hover mark, against the same fake herdr"
# Local's floor api as the office first sees it: api:p1 blocked and api:p4 done
# before it watched (their lines say `+`), a new api:p5 working at api:p4's
# table, api:p2 idle (in the pantry), api:p3 a shell.
stage_lens() {
	ctl reset '{"fixture": "snapshot_floors"}'
	"$PYTHON" - "$WORK/herdr-ctl.sock" "$ROOT/tools/fixtures/snapshot_floors.json" <<'PY' || exit 2
import json, socket, sys

with open(sys.argv[2], encoding="utf-8") as source:
    snapshot = json.load(source)["snapshot"]
for field in ("panes", "agents"):
    for record in snapshot[field]:
        if record["pane_id"] == "api:p1":
            record["agent_status"] = "blocked"
        if record["pane_id"] == "api:p4":
            record["agent_status"] = "done"
    template = next(record for record in snapshot[field] if record["pane_id"] == "api:p4")
    added = dict(template)
    added.update({"pane_id": "api:p5", "agent": "claude", "agent_status": "working", "terminal_id": "term-api-p5"})
    snapshot[field].append(added)
conn = socket.socket(socket.AF_UNIX)
conn.connect(sys.argv[1])
conn.sendall((json.dumps({"cmd": "set_snapshot", "args": {"snapshot": snapshot}}) + "\n").encode())
conn.makefile().readline()
conn.close()
PY
}
for view in "zoom2 2 daylight" "zoom4 4 daylight --resolution 1920x1280" "min 2 daylight --resolution 960x640"; do
	read -r shot zoom pack window <<<"$view"
	# shellcheck disable=SC2086
	CAPTURE_PREPARE=stage_lens godot_run --path "$ROOT" $window -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/$pack/manifest.json --zoom="$zoom" --lens=held \
		--wait="$DWELL" --capture="$OUT/office-lens-$shot.png"
done
# The hover mark on api:p4's desk; web:p1, on another floor, marks web's FLOORS row.
for view in "point api:p4" "point-floor web:p1"; do
	read -r shot key <<<"$view"
	CAPTURE_PREPARE=stage_lens godot_run --path "$ROOT" -- --socket="$WORK/herdr.sock" --read-only \
		--pack=res://assets/daylight/manifest.json --zoom=2 --point="$key" \
		--wait="$DWELL" --capture="$OUT/office-$shot-zoom2.png"
done
# The strategic view over that stage: api's two tables, a `+` wait, idle, done and a shell.
CAPTURE_PREPARE=stage_lens godot_run --path "$ROOT" -- --socket="$WORK/herdr.sock" --read-only \
	--pack=res://assets/daylight/manifest.json --zoom=2 --strategic=open \
	--wait="$DWELL" --capture="$OUT/office-strategic-floors-zoom2.png"
ctl reset '{"fixture": "snapshot_floors"}'
finish
