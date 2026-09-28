extends "res://tools/office_test_base.gd"
## Knowing something needs you while Herdstead is in the background: the
## window title's `(N)`, the one Dock bounce per stretch out of focus and the
## optional chime (OfficeAlerts), what rings them and what never does. Run
## through run_tests.sh, `--read-only`: none of it is a herdr method.
##
## godot --headless --path . --script tools/test_alerts.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the NEWS suite does. Headless is always focused, so every
## case says the window is out of focus through FramePacer.note_focused(), and
## headless never bounces or plays: what the alerts decided is `alerts.fired`.

## The grace a case waits for, where the grace itself is not what it tests.
const SHORT_GRACE := 150

## The fixture with nobody blocked: web:p1 and infra:p1 at work. Two done.
var calm: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for name: String in ["socket", "work"]:
		if not args.has(name):
			print("TEST_HARNESS_ERROR: missing --%s= (use tools/run_tests.sh)" % name)
			quit(2)
			return
	# Nothing here may reach the user's herdr, machines or forwards.
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("alerts-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var file: Dictionary = parsed
	fixture = _dict(file, "snapshot")
	calm = _with(_with(fixture, "web:p1", {"agent_status": "working"}), "infra:p1", {"agent_status": "working"})
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "ALERTS TESTS"


# --- helpers ------------------------------------------------------------------


## A live office on its own command line (`flags` after the suite's own), out
## of focus unless `focused`, told so before its first snapshot, which is
## `snapshot`. Its bounce waits `grace` milliseconds.
func _office(
	flags: Array[String] = [], snapshot: Dictionary = calm, focused := false, grace := SHORT_GRACE
) -> OfficeDouble:
	var line := PackedStringArray(["--read-only", "--socket=" + args.socket, "--work=" + args.work])
	line.append_array(PackedStringArray(flags))
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_screen = Vector2(SCREEN)
	office.test_args = AppArgs.parse(line)
	office.manifest_path = MANIFESTS[0]
	# Never read or write the user's settings file from a test.
	office.remember_theme = false
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	office.alerts.bounce_grace_msec = grace
	office.pacer.note_focused(focused)
	_feed(office, snapshot)
	await _frames(2)
	return office


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## The kinds of everything the office's alerts decided, oldest first.
func _kinds(office: OfficeDouble) -> Array[StringName]:
	return _fired_kinds(office.alerts)


func _fired_kinds(alerts: OfficeAlerts) -> Array[StringName]:
	var kinds: Array[StringName] = []
	for entry in alerts.fired:
		kinds.append(entry.kind)
	return kinds


func _count(office: OfficeDouble, kind: StringName) -> int:
	return _kinds(office).count(kind)


## Frames for at least `msec` of the clock the log stamps its events with.
func _wait_msec(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame
	await process_frame


## Past the short grace of every pending bounce.
func _past_grace() -> void:
	await _wait_msec(SHORT_GRACE + 100)


func _title() -> String:
	return root.title


## The top bar's BLOCKED number, as the viewer reads it.
func _bar_blocked(office: OfficeDouble) -> String:
	return office.hud.bar.counter(&"blocked").value_text()


# --- the bounce and the title -------------------------------------------------


## An agent blocked while the office is in the background: nothing before the
## real grace is over, then one bounce for it. The title leads with how many
## wait, the same number as the top bar's BLOCKED.
func test_blocked_while_unfocused_bounces_once_and_counts_in_the_title() -> void:
	var office := await _office([], calm, false, OfficeAlerts.BOUNCE_GRACE_MSEC)
	_eq(OfficeAlerts.BOUNCE_GRACE_MSEC, 3000, "three seconds of grace")
	_eq(_title(), "Herdstead · 2 UNREAD", "nobody waits: no count")
	var key := _pk("api:p2")
	_feed(office, _with(calm, "api:p2", {"agent_status": "blocked"}))
	await _wait_msec(1000)
	_eq(_kinds(office), [] as Array[StringName], "a second in, still inside the grace")
	await _wait_msec(OfficeAlerts.BOUNCE_GRACE_MSEC)
	_eq(_kinds(office), [OfficeAlerts.BOUNCE] as Array[StringName], "then one bounce")
	if office.alerts.fired.size() == 1:
		_eq(office.alerts.fired[0].pane_key, key, "for api:p2")
		_eq(office.alerts.fired[0].event_id, office.fleet.state_log().last_id(), "from its event")
	_check(_title().begins_with("(1) Herdstead"), "the title leads with the count: %s" % _title())
	_eq(_title(), "(1) Herdstead · 1 BLOCKED · 2 UNREAD", "and keeps the rest")
	_eq(_bar_blocked(office), "1", "the top bar's BLOCKED says the same number")
	_done(office)


## With the office in front of the viewer nothing rings, and the title still
## counts. Going to another app afterwards plays no backlog.
func test_nothing_fires_while_focused() -> void:
	var office := await _office(["--chime"], calm, true)
	var blocked := _with(calm, "api:p2", {"agent_status": "blocked"})
	_feed(office, blocked)
	_feed(office, _with(blocked, "data:p1", {"agent_status": "done"}))
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "no bounce and no chime while focused")
	_check(_title().begins_with("(1) Herdstead"), "the title counts whether or not focused: %s" % _title())
	office.pacer.note_focused(false)
	office.refresh()
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "out of focus later: nothing old rings")
	_done(office)


## The first snapshot of a connection is a baseline: the agents already blocked
## in it ring nothing, while the title counts them.
func test_the_first_snapshot_is_a_baseline() -> void:
	var office := await _office(["--chime"], fixture)
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "two blocked and two done at the start: nothing rings")
	_eq(_title(), "(2) Herdstead · 2 BLOCKED · 2 UNREAD", "the title counts them")
	_eq(_bar_blocked(office), "2", "as the top bar does")
	_done(office)


## Another agent run coming up blocked in a pane whose last run was blocked
## too is no change of state: nobody new waits, nothing rings. A new run that
## asks in a pane whose last run was at work is, and rings.
func test_a_new_run_blocked_where_the_last_was_blocked_is_no_change() -> void:
	var office := await _office(["--chime"], _with(calm, "api:p2", {"agent_status": "blocked"}))
	var ledger := office.fleet.state_log()
	var replaced := _with(calm, "api:p2", {"agent_status": "blocked", "terminal_id": "t-new"})
	_feed(office, replaced)
	var last: StateLog.Event = ledger.events().back()
	_eq(
		[last.kind, last.previous_state, last.state],
		[StateLog.Kind.REPLACED, "blocked", "blocked"],
		"another terminal in api:p2, blocked as the last one was"
	)
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "blocked to blocked: nothing rings")
	_feed(office, _with(replaced, "data:p1", {"agent_status": "blocked", "terminal_id": "t-other"}))
	last = ledger.events().back()
	_eq(
		[last.kind, last.previous_state, last.state],
		[StateLog.Kind.REPLACED, "working", "blocked"],
		"another terminal in data:p1, blocked where the last one worked"
	)
	await _past_grace()
	_eq(_kinds(office), [OfficeAlerts.CHIME_BLOCKED, OfficeAlerts.BOUNCE] as Array[StringName], "that one rings")
	_done(office)


## A machine that drops and comes back with agents blocked that were at work
## before is a baseline too: nobody saw them change.
func test_a_reconnect_is_a_baseline() -> void:
	var office := await _office(["--chime"])
	_set_online(office, false)
	_feed(office, _with(calm, "api:p2", {"agent_status": "blocked"}))
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "back online with a new blocked agent: nothing rings")
	_eq(_title(), "(1) Herdstead · 1 BLOCKED · 2 UNREAD", "the title counts it")
	_done(office)


## A machine that is offline rings nothing: a snapshot it no longer serves is
## not news, and one blocked just before it dropped does not bounce either.
func test_an_offline_machine_never_fires() -> void:
	var office := await _office(["--chime"])
	var blocked := _with(calm, "api:p2", {"agent_status": "blocked"})
	_set_online(office, false)
	_feed(office, blocked, false)
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "a snapshot while offline rings nothing")
	_eq(_title(), "Herdstead · OFFLINE", "the title says offline, no count")
	var again := await _office([], calm, false, 400)
	_feed(again, blocked)
	_set_online(again, false)
	again.refresh()
	await _wait_msec(500)
	_eq(_kinds(again), [] as Array[StringName], "blocked, then the machine drops inside the grace: no bounce")
	_done(office)
	_done(again)


# --- launches -----------------------------------------------------------------


## An agent that asks while herdr is still launching it counts as blocked
## and rings like any other.
func test_blocked_while_launching_fires() -> void:
	var office := await _office(["--chime"])
	var key := _pk("data:p2")
	_check(office.frame.pane(key).launching(), "data:p2 is launching")
	_feed(office, _with(calm, "data:p2", {"agent_status": "blocked"}))
	await _past_grace()
	_eq(
		_kinds(office),
		[OfficeAlerts.CHIME_BLOCKED, OfficeAlerts.BOUNCE] as Array[StringName],
		"a chime, then the bounce"
	)
	_check(
		office.alerts.fired.all(func(entry: OfficeAlerts.Fired) -> bool: return entry.pane_key == key), "for data:p2"
	)
	_eq(_title(), "(1) Herdstead · 1 BLOCKED · 2 UNREAD", "and the title counts it")
	_done(office)


## A launch that has not asked anything is nobody waiting: whatever herdr says
## of it meanwhile rings nothing and counts nothing.
func test_launching_without_blocked_does_not_fire() -> void:
	var office := await _office(["--chime"])
	var working := _with(calm, "data:p2", {"agent_status": "working"})
	_feed(office, working)
	_feed(office, _with(working, "data:p2", {"agent_status": "done"}))
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "working, then done, while launching: nothing")
	_eq(_title(), "Herdstead · 2 UNREAD", "and nothing counted")
	_done(office)


# --- one bounce ---------------------------------------------------------------


## Two agents blocked in one snapshot are one bounce.
func test_two_panes_in_one_snapshot_are_one_bounce() -> void:
	var office := await _office()
	_feed(office, _with(_with(calm, "api:p2", {"agent_status": "blocked"}), "data:p1", {"agent_status": "blocked"}))
	await _past_grace()
	_eq(_kinds(office), [OfficeAlerts.BOUNCE] as Array[StringName], "one bounce for two")
	_eq(_title(), "(2) Herdstead · 2 BLOCKED · 2 UNREAD", "both counted")
	_done(office)


## After one bounce the Dock is not asked again until the viewer has been back:
## a second agent blocked in the same stretch does not bounce, a third one
## after focus came and went does.
func test_a_bounce_waits_for_focus_to_come_back() -> void:
	var office := await _office()
	var one := _with(calm, "api:p2", {"agent_status": "blocked"})
	_feed(office, one)
	await _past_grace()
	_eq(_count(office, OfficeAlerts.BOUNCE), 1, "the first blocked bounces")
	var two := _with(one, "data:p1", {"agent_status": "blocked"})
	_feed(office, two)
	await _past_grace()
	_eq(_count(office, OfficeAlerts.BOUNCE), 1, "the second in the same stretch does not")
	office.pacer.note_focused(true)
	await _frames(2)
	office.pacer.note_focused(false)
	await _frames(2)
	_feed(office, _with(two, "infra:p3", {"agent_status": "blocked"}))
	await _past_grace()
	_eq(_count(office, OfficeAlerts.BOUNCE), 2, "after the viewer came back and left again, the third does")
	_done(office)


## An agent answered (or back at work) inside the grace never bounces, and
## neither does one that is back at work by the time the grace is over.
func test_answered_inside_the_grace_never_bounces() -> void:
	var office := await _office([], calm, false, 400)
	_feed(office, _with(calm, "api:p2", {"agent_status": "blocked"}))
	await _wait_msec(100)
	_feed(office, calm)
	await _wait_msec(500)
	_eq(_kinds(office), [] as Array[StringName], "blocked, answered 0.1 s later: no bounce")
	_feed(office, _with(calm, "api:p2", {"agent_status": "blocked"}))
	await _wait_msec(500)
	_eq(_kinds(office), [OfficeAlerts.BOUNCE] as Array[StringName], "blocked again and left waiting: the bounce")
	_done(office)


## herdr's own focused pane is the one the viewer has in the terminal: it
## neither bounces nor chimes. Another pane does both.
func test_herdr_focused_pane_does_not_bounce_or_chime() -> void:
	var office := await _office(["--chime"])
	_eq(office.frame.herdr_focus, _pk("api:p1"), "herdr has api:p1 in front")
	var asking := _with(calm, "api:p1", {"agent_status": "blocked"})
	_feed(office, asking)
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "herdr's focused pane blocked: nothing rings")
	_eq(_title(), "(1) Herdstead · 1 BLOCKED · 2 UNREAD", "though it counts")
	_feed(office, _with(asking, "api:p2", {"agent_status": "blocked"}))
	await _past_grace()
	_eq(_kinds(office), [OfficeAlerts.CHIME_BLOCKED, OfficeAlerts.BOUNCE] as Array[StringName], "another pane rings")
	_done(office)


# --- the chime ----------------------------------------------------------------


## A pane that flips between blocked and work chimes once in REPEAT_MSEC, and
## bounces once.
func test_a_flapping_pane_chimes_once_within_repeat() -> void:
	var office := await _office(["--chime"])
	_eq(OfficeAlerts.REPEAT_MSEC, 10000, "ten seconds per pane")
	var blocked := _with(calm, "api:p2", {"agent_status": "blocked"})
	for flap in 4:
		_feed(office, blocked)
		_feed(office, calm)
	_feed(office, blocked)
	await _past_grace()
	_eq(_count(office, OfficeAlerts.CHIME_BLOCKED), 1, "five times blocked: one chime")
	_eq(_count(office, OfficeAlerts.BOUNCE), 1, "and one bounce")
	_feed(office, _with(blocked, "data:p1", {"agent_status": "blocked"}))
	_eq(_count(office, OfficeAlerts.CHIME_BLOCKED), 2, "another pane chimes on its own")
	_done(office)


## A done agent chimes, the softer done tone, and never bounces; blocked and
## done in one snapshot are one chime, the blocked one.
func test_done_chimes_softly_and_never_bounces() -> void:
	var office := await _office(["--chime"])
	_eq(OfficeAlerts.DONE_DB, -8.0, "the done chime is 8 dB softer")
	_feed(office, _with(calm, "api:p2", {"agent_status": "done"}))
	await _past_grace()
	_eq(_kinds(office), [OfficeAlerts.CHIME_DONE] as Array[StringName], "done: the done chime, no bounce")
	_eq(_title(), "Herdstead · 3 UNREAD", "done stays the UNREAD suffix")
	var both := _with(_with(calm, "infra:p3", {"agent_status": "blocked"}), "data:p1", {"agent_status": "done"})
	_feed(office, both)
	await _past_grace()
	_eq(
		_kinds(office),
		[OfficeAlerts.CHIME_DONE, OfficeAlerts.CHIME_BLOCKED, OfficeAlerts.BOUNCE] as Array[StringName],
		"blocked and done together: one chime, the blocked one"
	)
	_done(office)


## Without `--chime` (and no remembered setting, which a test never reads)
## there is no chime, only the bounce.
func test_no_chime_without_the_flag() -> void:
	var office := await _office()
	_check(not office.alerts.options.chime, "the chime is off by default")
	_feed(office, _with(_with(calm, "api:p2", {"agent_status": "blocked"}), "data:p1", {"agent_status": "done"}))
	await _past_grace()
	_eq(_kinds(office), [OfficeAlerts.BOUNCE] as Array[StringName], "only the bounce")
	_done(office)


# --- switches -----------------------------------------------------------------


## A capture is silent: alerts built for one ring nothing, where the same
## alerts not silent would. (`--capture=` would run the capture driver here, so
## the alerts are built by hand on a live office's fleet.)
func test_capture_is_silent() -> void:
	var office := await _office()
	var out_of_focus := func() -> bool: return false
	var silent := OfficeAlerts.Options.new()
	silent.chime = true
	silent.silent = true
	var loud := OfficeAlerts.Options.new()
	loud.chime = true
	var quiet := OfficeAlerts.new(office.fleet, out_of_focus, silent)
	var control := OfficeAlerts.new(office.fleet, out_of_focus, loud)
	for alerts: OfficeAlerts in [quiet, control]:
		alerts.bounce_grace_msec = SHORT_GRACE
		office.add_child(alerts)
	_feed(office, _with(calm, "api:p2", {"agent_status": "blocked"}))
	quiet.take(office.frame)
	control.take(office.frame)
	await _past_grace()
	_eq(_fired_kinds(quiet), [] as Array[StringName], "silent: no bounce, no chime")
	_eq(
		_fired_kinds(control),
		[OfficeAlerts.CHIME_BLOCKED, OfficeAlerts.BOUNCE] as Array[StringName],
		"the same alerts not silent would ring"
	)
	_done(office)


## `--no-bounce` never bounces; `--no-title-count` writes today's title exactly.
func test_no_bounce_and_no_title_count_flags() -> void:
	var office := await _office(["--no-bounce", "--no-title-count"])
	_check(not office.alerts.options.bounce, "--no-bounce turns the bounce off")
	_feed(office, _with(calm, "api:p2", {"agent_status": "blocked"}))
	await _past_grace()
	_eq(_kinds(office), [] as Array[StringName], "no bounce")
	_eq(_title(), "Herdstead · 1 BLOCKED · 2 UNREAD", "and the title as it was before the count")
	_done(office)


## What turns the chime on by default: `[alerts] chime=true` in a settings file
## (here one the case writes in its own work directory, never user://); a
## missing file, a missing key, `false` or anything not a bool leaves it off.
func test_the_remembered_chime_is_a_true_bool_only() -> void:
	var path: String = args.work.path_join("alerts-settings.cfg")
	_check(not OfficeAlerts.remembered_chime(path), "no file: off")
	var values: Array = [true, false, "true", 1]
	var expected: Array[bool] = [true, false, false, false]
	for index in values.size():
		var settings := ConfigFile.new()
		settings.set_value("theme", "manifest_path", "res://assets/daylight/manifest.json")
		settings.set_value(OfficeAlerts.CHIME_SECTION, OfficeAlerts.CHIME_KEY, values[index])
		_eq(settings.save(path), OK, "the settings file is written")
		_eq(OfficeAlerts.remembered_chime(path), expected[index], "chime=%s" % var_to_str(values[index]))
	var other := ConfigFile.new()
	other.set_value("theme", "manifest_path", "res://assets/daylight/manifest.json")
	other.save(path)
	_check(not OfficeAlerts.remembered_chime(path), "no [alerts] section: off")
	_eq([OfficeAlerts.CHIME_SECTION, OfficeAlerts.CHIME_KEY], ["alerts", "chime"], "the key the manual names")
	DirAccess.remove_absolute(path)


## The chimes are short, begin and end on silence, and stay well below full scale.
func test_tone_is_short_and_click_free() -> void:
	var tones := {
		"blocked": [OfficeAlerts.BLOCKED_NOTES, OfficeAlerts.BLOCKED_NOTE_MSEC, 180],
		"done": [OfficeAlerts.DONE_NOTES, OfficeAlerts.DONE_NOTE_MSEC, 120],
	}
	_eq(OfficeAlerts.MIX_RATE, 22050, "22050 Hz")
	for which: String in tones:
		var spec: Array = tones[which]
		var source: Array = spec[0]
		var notes: Array[float] = []
		notes.assign(source)
		var note_msec: int = spec[1]
		var total_msec: int = spec[2]
		var stream := OfficeAlerts.tone(PackedFloat32Array(notes), note_msec)
		_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "%s: 16-bit" % which)
		_check(not stream.stereo, "%s: mono" % which)
		_eq(stream.mix_rate, 22050, "%s: at the mix rate" % which)
		var samples := stream.data.size() / 2
		var per_note := note_msec * 22050 / 1000
		_eq(samples, notes.size() * per_note, "%s: whole notes of %d ms" % [which, note_msec])
		_check(absi(samples - total_msec * 22050 / 1000) < notes.size(), "%s: %d ms of samples" % [which, total_msec])
		_eq(stream.data.decode_s16(0), 0, "%s: starts on silence" % which)
		_eq(stream.data.decode_s16(stream.data.size() - 2), 0, "%s: ends on silence" % which)
		var peak := 0
		for index in samples:
			peak = maxi(peak, absi(stream.data.decode_s16(index * 2)))
			if index % per_note == per_note - 1:
				_eq(stream.data.decode_s16(index * 2), 0, "%s: note %d ends on silence" % [which, index / per_note])
		_check(peak <= 16383, "%s: peak %d is at most half of full scale" % [which, peak])
		_check(peak > 3000, "%s: and audible (%d)" % [which, peak])
	_check(OfficeAlerts.BLOCKED_NOTES[1] > OfficeAlerts.BLOCKED_NOTES[0], "blocked rises")
	_check(OfficeAlerts.DONE_NOTES[0] < OfficeAlerts.BLOCKED_NOTES[0], "done is lower")
