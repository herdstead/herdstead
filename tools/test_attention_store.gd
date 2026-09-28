extends "res://tools/test_base.gd"
## Pure public-API lifecycle tests; never connects to Herdr.


func _initialize() -> void:
	run_cases.call_deferred()


func _marker() -> String:
	return "ATTENTION STORE TESTS"


func _pane(machine := "local", pane_id := "pane", state := "working") -> PaneModel:
	var pane := PaneModel.new()
	pane.pane_id = pane_id
	pane.key = HerdrFleet.pane_key(machine, pane_id)
	pane.terminal_id = "terminal-" + pane_id
	pane.provider = "claude"
	pane.state = state
	pane.workspace_id = "workspace"
	pane.tab_id = "tab"
	pane.workspace_label = "Project"
	pane.tab_label = "Main"
	pane.label = "Worker"
	return pane


func _observe(store: AttentionStore, panes: Array[PaneModel], now_msec := 1000) -> bool:
	return store.observe("local", "This Mac", panes, true, now_msec, 100000.0 + now_msec / 1000.0)


## The live record that began last.
func _newest(store: AttentionStore) -> AttentionItem:
	var live := store.active()
	return null if live.is_empty() else live[live.size() - 1]


func _projected_pane(identity_fields: Dictionary, machine := "local") -> PaneModel:
	var raw := {"pane_id": "reused", "agent": "claude", "agent_status": "blocked", "label": "Original worker"}
	raw.merge(identity_fields, true)
	return (
		OfficeProjection
		. panes_of(
			HerdrSnapshot.from_wire({"panes": [raw]}), PackedStringArray(["working", "blocked", "done"]), machine
		)[0]
	)


func test_first_snapshot_is_baseline_and_metadata_does_not_make_events() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_check(_observe(store, [pane]), "first complete snapshot accepted")
	var item := store.current(1000)[0]
	_check(item.baseline and item.active and item.available, "baseline is current but is not a new event")
	_eq(item.since_msec, -1, "baseline has no fabricated wait start")
	_eq(item.observed_at, -1.0, "baseline has no fabricated event date")
	pane.terminal_title = "Updated title"
	pane.workspace_label = "Renamed project"
	pane.tab_label = "Renamed tab"
	_check(_observe(store, [pane], 2000), "metadata refresh accepted")
	_eq(store.active().size(), 1, "same event plus repeated snapshot deduplicates")
	_eq(store.current(2000)[0], item, "same episode object survives metadata")
	_eq(item.title, "Worker", "explicit pane name takes priority over changing terminal title")
	_eq(item.workspace_label, "Renamed project", "workspace label refreshes")
	_eq(item.tab_label, "Renamed tab", "tab label refreshes")
	_eq(item.workspace_key, HerdrFleet.pane_key("local", "workspace"), "workspace is machine scoped")


func test_first_seen_pane_on_an_online_machine_has_unknown_start() -> void:
	var store := AttentionStore.new()
	_observe(store, [])
	var pane := _pane("local", "new", "blocked")
	_observe(store, [pane], 2000)
	var item := store.current(2000)[0]
	_check(item.baseline, "new pane has no previously observed working state")
	_eq(item.since_msec, -1, "new pane's wait may have started before discovery")
	_eq(item.observed_at, -1.0, "new pane is not a locally witnessed transition")
	pane.state = "working"
	_observe(store, [pane], 3000)
	pane.state = "blocked"
	_observe(store, [pane], 4000)
	var transition := store.current(4000)[0]
	_check(not transition.baseline, "later observed transition has a known local start")
	_eq(transition.since_msec, 4000, "only actual observed transition starts timer")


func test_closed_unknown_identity_never_revives_when_ids_are_reused() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "reused", "blocked")
	pane.terminal_id = ""
	_observe(store, [pane])
	var closed := store.current(1000)[0]
	_observe(store, [], 2000)
	_check(not closed.available, "close revokes old record")
	pane.label = "Different worker with unknown identity"
	_observe(store, [pane], 3000)
	var fresh := store.current(3000)[0]
	_check(fresh.id != closed.id, "reappearance is a separate episode")
	_check(not closed.available, "old unknown identity never regains a target")
	_eq(closed.title, "Worker", "retired record keeps its own final metadata")
	_check(fresh.available and fresh.baseline, "new appearance is inspectable but start remains unknown")
	_observe(store, [pane], 4000)
	_check(not closed.available, "repeated snapshots cannot revive retired record")


func test_removed_machine_records_never_revive_when_readded() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var removed := store.current(1000)[0]
	store.retain_machines(PackedStringArray())
	_check(not removed.available, "remove revokes every old target")
	_observe(store, [pane], 3000)
	var fresh := store.current(3000)[0]
	_check(fresh.id != removed.id and fresh.baseline, "re-added machine starts with a fresh baseline")
	_check(not removed.available, "matching machine/pane/terminal cannot revive removed history")
	_check(store.find(removed.id) == null, "the removed record left the store; a held one cannot locate")


func test_replaced_terminal_never_revives_when_old_identity_returns() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var replaced := store.current(1000)[0]
	var old_terminal := pane.terminal_id
	pane.terminal_id = "new-terminal"
	_observe(store, [pane], 2000)
	pane.terminal_id = old_terminal
	_observe(store, [pane], 3000)
	var returned := store.current(3000)[0]
	_check(returned.available and returned.id != replaced.id, "returning identity gets its own baseline")
	_check(not replaced.available, "previously replaced record remains permanently unavailable")
	_eq(store.active(), [returned] as Array[AttentionItem], "only the returning incarnation is live")
	_check(store.find(replaced.id) == null, "the replaced ones left the store")


func test_observed_rounds_resolve_and_reenter_without_reusing_dismissal() -> void:
	var store := AttentionStore.new()
	var pane := _pane()
	_observe(store, [pane])
	pane.state = "blocked"
	_observe(store, [pane], 2000)
	var first := store.current(2000)[0]
	_check(not first.baseline, "transition after baseline is locally observed")
	_eq(first.since_msec, 2000, "wait is measured by monotonic observation")
	_eq(first.observed_at, 100002.0, "wall time only describes when locally observed")
	_check(store.set_hidden(first.id, true), "hide this episode locally")
	_observe(store, [pane], 2100)
	_eq(store.active(), [first] as Array[AttentionItem], "repeating same blocked state makes no event")
	pane.state = "working"
	_observe(store, [pane], 3000)
	_check(not first.active and first.retired, "a resolved round ends: what it was is the StateLog's to tell")
	pane.state = "blocked"
	_observe(store, [pane], 4000)
	var next := store.current(4000)[0]
	_check(next.id != first.id and not next.hidden, "new round has independent dismissal")
	_eq(store.active(), [next] as Array[AttentionItem], "only the new round is live")


func test_done_is_an_attention_state_and_starting_is_not() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "done")
	pane.starting = true
	_observe(store, [pane])
	_eq(store.current(1000).size(), 0, "starting never masquerades as done")
	pane.starting = false
	_observe(store, [pane], 2000)
	var done := store.current(2000)[0]
	_eq(done.state, "done", "record uses Herdr's attention state without claiming success")
	pane.state = "idle"
	_observe(store, [pane], 3000)
	_check(not done.active and done.retired, "seen idle resolves done; History (the StateLog) keeps what it was")
	pane.state = "blocked"
	pane.provider = ""
	_observe(store, [pane], 4000)
	_eq(store.current(4000).size(), 0, "plain shells do not create agent attention")


func test_leaving_launch_does_not_invent_a_wait_start() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	pane.starting = true
	_observe(store, [pane])
	pane.starting = false
	_observe(store, [pane], 2000)
	var first := store.current(2000)[0]
	_check(first.baseline, "first stable state after starting is a baseline")
	_eq(first.since_msec, -1, "starting state cannot establish wait continuity")
	_eq(first.observed_at, -1.0, "completion of launch is not a witnessed attention transition")
	pane.state = "working"
	_observe(store, [pane], 3000)
	pane.state = "blocked"
	_observe(store, [pane], 4000)
	var timed := store.current(4000)[0]
	_check(not timed.baseline, "later stable identity transition is observed")
	_eq(timed.since_msec, 4000, "later observed transition can be timed")
	pane.starting = true
	_observe(store, [pane], 5000)
	# Blocked comes first: a launch does not end the record; a blocked agent
	# herdr relaunches is still asking, so its record and its wait run on.
	_eq(store.current(5000).size(), 1, "a blocked agent stays attention while herdr relaunches it")
	pane.starting = false
	_observe(store, [pane], 6000)
	_eq(store.current(6000)[0].since_msec, 4000, "its record never ended: the same wait, from 4000, no new baseline")


func test_missing_terminal_identity_keeps_transition_time_unknown() -> void:
	var store := AttentionStore.new()
	var pane := _pane()
	pane.terminal_id = ""
	_observe(store, [pane])
	pane.state = "blocked"
	_observe(store, [pane], 2000)
	var item := store.current(2000)[0]
	_check(item.baseline and item.available, "unknown identity is inspectable but has no continuity claim")
	_eq(item.since_msec, -1, "pane id alone cannot establish a wait clock")
	_eq(item.observed_at, -1.0, "missing identity cannot establish a verified local transition")
	pane.state = "working"
	_observe(store, [pane], 3000)
	pane.state = "blocked"
	_observe(store, [pane], 4000)
	_check(store.current(4000)[0].baseline, "later apparent transitions still lack verifiable identity")
	pane.terminal_id = "identified-terminal"
	_observe(store, [pane], 5000)
	_check(store.current(5000)[0].baseline, "newly available identity starts as a baseline")
	pane.state = "working"
	_observe(store, [pane], 6000)
	pane.state = "blocked"
	_observe(store, [pane], 7000)
	_eq(store.current(7000)[0].since_msec, 7000, "only later stable identity transitions acquire a clock")


func test_same_pane_id_on_two_machines_stays_independent() -> void:
	var store := AttentionStore.new()
	var local := _pane("local", "same", "blocked")
	var remote := _pane("remote", "same", "blocked")
	_observe(store, [local])
	_check(store.observe("remote", "Server", [remote], true, 1000, 10.0), "remote baseline accepted")
	var items := store.current(1000)
	_eq(items.size(), 2, "duplicate raw id across machines is legitimate")
	_check(items[0].id != items[1].id, "episode IDs are distinct")
	_check(items[0].pane_key != items[1].pane_key, "navigation identities are machine scoped")
	local.state = "working"
	_observe(store, [local], 2000)
	_eq(store.current(2000)[0].machine_key, "remote", "one machine cannot resolve another's item")


func test_terminal_and_session_replacement_invalidate_old_targets() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var old := store.current(1000)[0]
	pane.terminal_id = "replacement-terminal"
	_observe(store, [pane], 2000)
	var replacement := store.current(2000)[0]
	_check(not old.active and not old.available, "old terminal target is revoked")
	_check(replacement.id != old.id and replacement.baseline, "unknown start of replacement is a baseline")
	var session := AgentSessionIdentity.new()
	session.source = "hook"
	session.provider = "claude"
	session.kind = "id"
	session.value = "session-two"
	pane.session = session
	_observe(store, [pane], 3000)
	var resumed := store.current(3000)[0]
	_check(not replacement.available and resumed.id != replacement.id, "session replacement revokes old target")
	_eq(store.active(), [resumed] as Array[AttentionItem], "each distinct identity has one baseline, one live")
	session.source = "another-reporter"
	_observe(store, [pane], 4000)
	_eq(store.current(4000)[0], resumed, "report source is not session identity")


func test_offline_leaves_history_and_reconnect_does_not_invent_transition() -> void:
	var store := AttentionStore.new()
	var pane := _pane()
	_observe(store, [pane])
	pane.state = "blocked"
	_observe(store, [pane], 2000)
	var item := store.current(2000)[0]
	_check(store.observe("local", "This Mac", [], false, 3000, 10.0), "offline snapshot accepted")
	_eq(store.current(3000).size(), 0, "offline is not current actionable attention")
	_check(item.stale and not item.available, "offline target unavailable")
	_eq(item.since_msec, -1, "continuity across disconnection is unknown")
	_observe(store, [pane], 4000)
	_eq(store.current(4000)[0], item, "same visible state after gap reuses episode")
	_eq(store.active(), [item] as Array[AttentionItem], "gap does not fabricate a second event")
	_check(item.baseline and not item.stale and item.available, "reconnect is a current baseline")
	_eq(item.observed_at, 100002.0, "earlier actual observation is retained as history")
	_eq(item.since_msec, -1, "reconnect does not claim continuously blocked")


func test_reconnect_with_changed_state_records_only_new_baseline() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var old := store.current(1000)[0]
	store.observe("local", "This Mac", [pane], false, 2000, 20.0)
	pane.state = "done"
	_observe(store, [pane], 5000)
	var baseline := store.current(5000)[0]
	_check(not old.active and old.retired, "the old state's record ends; the StateLog keeps what it was")
	_check(baseline.baseline and baseline.state == "done", "only observed final status becomes baseline")
	_eq(baseline.since_msec, -1, "no intermediate work or done time inferred")
	_eq(baseline.observed_at, -1.0, "no fabricated event timestamp")
	_eq(store.active(), [baseline] as Array[AttentionItem], "no guessed intermediate episodes")


func test_unverifiable_reconnect_does_not_revive_or_inherit_local_dismissal() -> void:
	for fields: Dictionary in [
		{},
		{"terminal_id": 42, "agent_session": "session"},
		{"terminal_id": "term\u0007", "agent_session": {"agent": "claude", "kind": "session_id", "value": ""}},
		{"agent_session": {"agent": "codex", "kind": "session_id", "value": "native-session"}},
		{"agent_session": {"agent": "claude", "value": "native-session"}},
		{"agent_session": {"agent": "claude", "kind": "session_id", "value": "session\u0007"}},
	]:
		var store := AttentionStore.new()
		var remote := _projected_pane(fields, "remote")
		store.observe("remote", "Server", [remote], true, 1000, 10.0)
		var remote_item := store.current(1000)[0]
		var pane := _projected_pane(fields)
		_check(pane.terminal_id.is_empty() and pane.session == null, "boundary rejects unusable runtime identity")
		_observe(store, [pane])
		var old := _newest(store)
		store.set_hidden(old.id, true)
		store.snooze(old.id, 60.0, 1000)
		_observe(store, [pane], 1500)
		_eq(store.active().size(), 2, "uninterrupted unknown snapshot still deduplicates")
		store.observe("local", "This Mac", [], false, 2000, 20.0)
		pane = _projected_pane(fields)
		pane.label = "New worker while disconnected"
		_observe(store, [pane], 3000)
		var fresh := _newest(store)
		_check(fresh.id != old.id and fresh.active and fresh.available, "reconnect creates a separate usable baseline")
		_check(fresh.baseline and fresh.since_msec == -1 and fresh.observed_at == -1.0, "gap cannot invent event times")
		_check(not fresh.hidden and fresh.snoozed_until_msec == 0, "new baseline inherits neither hide nor snooze")
		_check(old.retired and not old.active and not old.available, "old target is revoked")
		_eq(old.title, "Original worker", "old history cannot acquire replacement metadata")
		_eq(store.current(3000).size(), 2, "new local baseline and unaffected remote both need attention")
		_check(remote_item.active and remote_item.available and not remote_item.retired, "same remote ID is isolated")
		_observe(store, [pane], 4000)
		_eq(store.active().size(), 2, "repeated online snapshots do not duplicate the new baseline")
		_check(
			not old.available and old.hidden and old.is_snoozed(4000),
			"retired history never revives or loses local choices"
		)


func test_verified_terminal_or_native_session_preserves_reconnect_dismissal() -> void:
	for fields: Dictionary in [
		{"terminal_id": "known-terminal"},
		{"agent_session": {"source": "hook", "agent": "claude", "kind": "session_id", "value": "native-session"}},
	]:
		var store := AttentionStore.new()
		var pane := _projected_pane(fields)
		_observe(store, [pane])
		var item := store.active()[0]
		store.set_hidden(item.id, true)
		store.snooze(item.id, 60.0, 1000)
		store.observe("local", "This Mac", [], false, 2000, 20.0)
		pane = _projected_pane(fields)
		if pane.session != null:
			pane.session.source = "screen"
		pane.label = "Same session, renamed"
		_observe(store, [pane], 3000)
		_eq(store.active().size(), 1, "known identity with unchanged state creates no new event")
		_eq(store.active()[0], item, "terminal ID or native session alone can establish identity")
		_check(item.available and not item.retired and not item.stale, "verified reconnect restores safe details")
		_check(item.hidden and item.snoozed_until_msec == 61000, "verified session retains its local choices")
		_eq(item.title, "Same session, renamed", "proven identity allows metadata refresh")
		_eq(store.current(3000).size(), 0, "verified hidden and snoozed item remains suppressed")
		store.set_hidden(item.id, false)
		store.snooze(item.id, 0.0, 3000)
		_eq(store.current(3000)[0], item, "local restore reveals the original record")
		_check(item.baseline and item.since_msec == -1, "verified identity does not prove continuous wait duration")


func test_native_session_replacement_without_terminal_never_revives_old_identity() -> void:
	var fields := {"agent_session": {"agent": "claude", "kind": "session_id", "value": "first"}}
	var store := AttentionStore.new()
	var pane := _projected_pane(fields)
	_observe(store, [pane])
	var old := store.active()[0]
	store.set_hidden(old.id, true)
	store.observe("local", "This Mac", [], false, 2000, 20.0)
	pane = _projected_pane(fields)
	pane.session.value = "second"
	_observe(store, [pane], 3000)
	_check(old.retired and not old.available, "different native session revokes old target even without terminal")
	_check(not store.current(3000)[0].hidden, "replacement session does not inherit dismissal")
	store.observe("local", "This Mac", [], false, 4000, 40.0)
	pane = _projected_pane(fields)
	_observe(store, [pane], 5000)
	_eq(store.active().size(), 1, "returning native identity starts another baseline")
	_check(not old.available and store.current(5000)[0].id != old.id, "retired native identity cannot revive")


func test_invalid_complete_snapshot_disables_machine_without_partial_changes() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var original := store.current(1000)[0]
	var extra := _pane("local", "extra", "done")
	_check(not _observe(store, [extra, pane, pane], 2000), "duplicate pane rejects whole batch")
	_eq(store.current(2000).size(), 0, "invalid batch cannot leave misleading live queue")
	_eq(store.active(), [original] as Array[AttentionItem], "invalid extra pane was not partially recorded")
	_check(original.stale and not original.available, "last valid item becomes unknown")
	_observe(store, [pane], 3000)
	_eq(store.current(3000)[0], original, "next valid snapshot is a baseline of last valid identity")
	var wrong_machine := _pane("remote", "foreign", "done")
	_check(not _observe(store, [wrong_machine], 4000), "cross-machine key cannot contaminate another machine")
	_check(not _observe(store, [null], 5000), "null typed element safely rejected")
	_eq(store.active(), [original] as Array[AttentionItem], "invalid values create no record")


func test_closed_panes_and_removed_machines_cannot_be_located() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var closed := store.current(1000)[0]
	_observe(store, [], 2000)
	_check(not closed.active and not closed.available, "empty complete snapshot closes pane")
	var remote := _pane("remote", "pane", "done")
	store.observe("remote", "Server", [remote], true, 3000, 10.0)
	var removed := store.current(3000)[0]
	store.retain_machines(PackedStringArray(["local"]))
	_check(not removed.active and not removed.available and removed.stale, "removal leaves only stale history")
	_eq(store.current(3000).size(), 0, "removed machine cannot remain live")
	_check(
		store.find(closed.id) == null and store.find(removed.id) == null, "closed and removed records leave the store"
	)
	store.observe("remote", "Server", [remote], true, 4000, 20.0)
	_check(store.current(4000)[0].baseline, "re-added machine starts from fresh baseline")


func test_hide_restore_and_snooze_are_local_to_the_episode() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var item := store.current(1000)[0]
	_check(store.set_hidden(item.id, true), "hide accepted")
	_eq(store.current(1000).size(), 0, "hidden item absent from queue")
	_eq(store.active(), [item] as Array[AttentionItem], "hidden item remains recoverable")
	_check(store.set_hidden(item.id, false), "restore accepted")
	_check(store.snooze(item.id, 5.0, 1000), "snooze accepted")
	_eq(store.current(5999).size(), 0, "snooze lasts until exact monotonic deadline")
	_check(item.is_snoozed(5999), "public item reports snooze")
	_eq(store.current(6000)[0], item, "deadline restores original item")
	_check(not item.is_snoozed(6000), "deadline is exclusive")
	_eq(store.active(), [item] as Array[AttentionItem], "snooze expiration is not another event")
	_check(not store.set_hidden("missing", true), "unknown hide has explicit failure")
	_check(not store.snooze("missing", 5.0, 7000), "unknown snooze has explicit failure")


func test_snooze_uses_monotonic_time_not_wall_clock_and_never_rewinds() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var item := store.current(1000)[0]
	store.snooze(item.id, 5.0, 1000)
	store.observe("local", "This Mac", [pane], true, 2000, 1.0)
	_eq(store.current(2000).size(), 0, "wall clock moving backward cannot expire snooze")
	store.observe("local", "This Mac", [pane], true, 3000, 999999999.0)
	_eq(store.current(3000).size(), 0, "wall clock leap cannot expire snooze")
	_eq(store.current(6000).size(), 1, "monotonic clock expires snooze")
	_eq(store.current(2000).size(), 1, "stale caller clock cannot reactivate expired snooze")
	_check(not store.snooze(item.id, INF, 6000), "infinite duration rejected")
	_check(not store.snooze(item.id, -1.0, 6000), "negative duration rejected")
	_check(store.snooze(item.id, 0.0, 6000), "zero explicitly cancels snooze")
	_eq(item.snoozed_until_msec, 0, "cancel deadline cleared")
	_check(not store.snooze(item.id, 86401.0, 6000), "duration is bounded to one day")
	_check(not store.snooze(item.id, 1.0, 9223372036854775807), "deadline cannot overflow signed integer")
	_eq(store.current(6000).size(), 1, "rejected snooze cannot advance store clock")
	store.snooze(item.id, 10.0, 6000)
	pane.state = "working"
	_observe(store, [pane], 7000)
	# History lines have no Resume: an ended record has left the store.
	_check(not store.snooze(item.id, 0.0, 7000), "a resolved record is no longer the store's to resume")
	_check(store.find(item.id) == null, "it left the store")


func test_current_priority_known_wait_age_and_stable_ties() -> void:
	var store := AttentionStore.new()
	var baseline := _pane("local", "a", "blocked")
	var first := _pane("local", "b")
	var second := _pane("local", "c")
	var done := _pane("local", "d", "done")
	_observe(store, [done, second, first, baseline])
	first.state = "blocked"
	_observe(store, [first, second, done, baseline], 2000)
	second.state = "blocked"
	_observe(store, [second, baseline, first, done], 3000)
	var items := store.current(4000)
	_eq(items[0].pane_key, first.key, "oldest known blocked wait first")
	_eq(items[1].pane_key, second.key, "next known blocked wait second")
	_eq(items[2].pane_key, baseline.key, "unknown duration follows known waits")
	_eq(items[3].state, "done", "blocked takes priority over done")
	var other := AttentionStore.new()
	_observe(other, [baseline, second, first, done])
	var tied := other.current(1000)
	_eq(tied[0].pane_key, baseline.key, "simultaneous baseline IDs independent of input order")
	_eq(tied[1].pane_key, first.key, "stable pane order assigns stable tie order")


## A record leaves the store the moment it ends, marked first, so a reference
## held elsewhere reads it as over and cannot act on it.
func test_ended_records_leave_the_store_but_a_held_reference_reads_retired() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	var item := store.current(1000)[0]
	_eq(store.active(), [item] as Array[AttentionItem], "the blocked episode is live")
	pane.state = "working"
	_observe(store, [pane], 2000)
	_eq(store.active().size(), 0, "working ends it: nothing live")
	_check(store.find(item.id) == null, "and the store no longer has it")
	_check(not item.active and not item.available and item.retired, "the held reference reads it over")
	_check(not store.snooze(item.id, 5.0, 2000), "Snooze has nothing to act on")
	_check(not store.set_hidden(item.id, true), "nor Hide")
	_check(not item.hidden and item.snoozed_until_msec == 0, "the held reference is untouched")


## active() is every live episode, the ones current() leaves out for being
## hidden or snoozed included, in the order they began: what a row's Snooze and
## Hide act on.
func test_active_includes_hidden_and_snoozed_records() -> void:
	var store := AttentionStore.new()
	var first := _pane("local", "a", "blocked")
	var second := _pane("local", "b", "done")
	_observe(store, [first, second])
	var hidden := store.current(1000)[0]
	var snoozed := store.current(1000)[1]
	_check(store.set_hidden(hidden.id, true), "hide one")
	_check(store.snooze(snoozed.id, 60.0, 1000), "snooze the other")
	_eq(store.current(1000).size(), 0, "current() shows neither")
	_eq(store.active(), [hidden, snoozed] as Array[AttentionItem], "active() has both")
	store.observe("local", "This Mac", [], false, 2000, 20.0)
	_eq(store.active().size(), 2, "offline leaves them live, stale")
	_check(hidden.stale and snoozed.stale, "stale")


func test_invalid_observation_clock_never_leaves_live_attention() -> void:
	var store := AttentionStore.new()
	var pane := _pane("local", "pane", "blocked")
	_observe(store, [pane])
	_check(not store.observe("local", "This Mac", [pane], true, 2000, NAN), "invalid wall time rejected")
	_eq(store.current(2000).size(), 0, "invalid observation is not live")
	_observe(store, [pane], 3000)
	_check(not store.observe("local", "This Mac", [pane], true, -1, 10.0), "negative monotonic time rejected")
	_eq(store.current(3000).size(), 0, "invalid monotonic observation is not live")
	_eq(store.active().size(), 1, "invalid timestamps do not create a record")


# --- the metadata pass looks at a pane's own records ---------------------------


## `count` panes on `machine`, every `every`th one blocked (the rest working).
func _crowd(count: int, every: int, machine := "local") -> Array[PaneModel]:
	var result: Array[PaneModel] = []
	for index in count:
		result.append(_pane(machine, "pane-%02d" % index, "blocked" if index % every == 0 else "working"))
	return result


func _rename(panes: Array[PaneModel], name: String) -> void:
	for pane in panes:
		pane.label = "%s %s" % [name, pane.pane_id]


## The live record of pane `key`, or null.
func _record(store: AttentionStore, key: String) -> AttentionItem:
	for item in store.active():
		if item.pane_key == key:
			return item
	return null


## One observation of `panes` on `machine`, and how many live records its
## metadata pass looked at: never more than the panes plus the live records.
func _visits(store: AttentionStore, machine: String, panes: Array[PaneModel], now_msec: int) -> int:
	var before := store.metadata_visits
	store.observe(machine, machine.capitalize(), panes, true, now_msec, 100000.0 + now_msec / 1000.0)
	var visits := store.metadata_visits - before
	_check(
		visits <= panes.size() + store.active().size(),
		"%d panes and %d records: %d visits" % [panes.size(), store.active().size(), visits]
	)
	return visits


## N panes, every other one waiting: a refresh's metadata pass looks at each
## pane's own live records, not at every live record once per pane (40 x 20 before).
func test_the_metadata_pass_looks_only_at_each_pane_s_own_records() -> void:
	var store := AttentionStore.new()
	var panes := _crowd(40, 2)
	_observe(store, panes)
	_eq(store.active().size(), 20, "twenty of forty panes wait")
	_rename(panes, "Renamed")
	_eq(_visits(store, "local", panes, 2000), 20, "each waiting pane's one record, once")
	var names: Dictionary[String, String] = {}
	for pane in panes:
		names[pane.key] = pane.label
	var titles := 0
	for item in store.active():
		if item.title == names[item.pane_key]:
			titles += 1
	_eq(titles, 20, "and every record took its pane's new name")
	_eq(store.current(2000).size(), 20, "the queue is the same twenty")


## Snoozed and hidden records are still their pane's: the pass keeps finding
## them and they keep their metadata, while the queue leaves them out.
func test_snoozed_and_hidden_records_keep_their_metadata() -> void:
	var store := AttentionStore.new()
	var panes := _crowd(8, 1)
	_observe(store, panes)
	var snoozed := _record(store, panes[0].key)
	var hidden := _record(store, panes[1].key)
	_check(store.snooze(snoozed.id, 60.0, 1000) and store.set_hidden(hidden.id, true), "snooze one, hide another")
	_rename(panes, "Later")
	_visits(store, "local", panes, 2000)
	_eq([snoozed.title, hidden.title], ["Later pane-00", "Later pane-01"], "both took the new names")
	_eq(store.active().size(), 8, "every episode is still live")
	_eq(store.current(2000).size(), 6, "the queue leaves the snoozed and the hidden out")
	_check(store.snooze(snoozed.id, 0.0, 2000) and store.set_hidden(hidden.id, false), "resume and restore")
	_rename(panes, "Again")
	_visits(store, "local", panes, 3000)
	_eq(store.current(3000).size(), 8, "both back in the queue")
	_eq([_record(store, panes[0].key), _record(store, panes[1].key)], [snoozed, hidden], "as the same records")
	_eq([snoozed.title, hidden.title], ["Again pane-00", "Again pane-01"], "still followed by the pass")


## A replaced terminal and a closed pane leave nothing behind for the pass: the
## old records keep their last metadata, the new ones take their pane's.
func test_replaced_and_closed_panes_leave_nothing_for_the_metadata_pass() -> void:
	var store := AttentionStore.new()
	var panes := _crowd(8, 1)
	_observe(store, panes)
	var replaced := _record(store, panes[0].key)
	var closed := _record(store, panes[1].key)
	panes[0].terminal_id = "new-terminal"
	var open: Array[PaneModel] = panes.duplicate()
	open.remove_at(1)
	_visits(store, "local", open, 2000)
	var fresh := _record(store, panes[0].key)
	_check(fresh != null and fresh != replaced and fresh.available, "the new terminal has its own record")
	_check(_record(store, panes[1].key) == null, "the closed pane has none")
	_eq(store.active().size(), 7, "seven live records")
	_rename(panes, "Renamed")
	_visits(store, "local", open, 3000)
	_eq(fresh.title, "Renamed pane-00", "the new record takes the new name")
	_eq([replaced.title, closed.title], ["Worker", "Worker"], "the ended ones keep their last")
	_check(not replaced.available and not closed.available, "and stay unavailable")
	_visits(store, "local", panes, 4000)
	var reopened := _record(store, panes[1].key)
	_check(reopened != null and reopened != closed and reopened.baseline, "a reopened pane starts a new record")
	_eq(reopened.title, "Renamed pane-01", "with its pane's metadata")
	_check(not closed.available, "the closed one stays unavailable")
	_eq(store.active().size(), 8, "eight live records again")


## A retired machine's records leave the pass with it: its re-added panes get
## fresh records, and the old ones keep their last metadata.
func test_a_retired_machine_leaves_nothing_for_the_metadata_pass() -> void:
	var store := AttentionStore.new()
	var local := _crowd(6, 1)
	var remote := _crowd(6, 1, "remote")
	_visits(store, "local", local, 1000)
	_visits(store, "remote", remote, 1000)
	_eq(store.active().size(), 12, "six records on each machine")
	var gone := _record(store, remote[0].key)
	store.retire_machine("remote")
	_eq(store.active().size(), 6, "retiring one leaves the other's six")
	_rename(local, "Local")
	_rename(remote, "Remote")
	_visits(store, "local", local, 2000)
	_eq(_record(store, local[0].key).title, "Local pane-00", "the kept machine's records follow their panes")
	_visits(store, "remote", remote, 3000)
	var fresh := _record(store, remote[0].key)
	_check(fresh != null and fresh != gone and fresh.baseline, "the re-added machine starts fresh records")
	_eq(fresh.title, "Remote pane-00", "with the panes' metadata")
	_eq(gone.title, "Worker", "the retired one keeps its last")
	_check(not gone.available and store.find(gone.id) == null, "and left the store")
	_eq(store.active().size(), 12, "twelve live records again")
