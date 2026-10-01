extends "res://tools/command_test_base.gd"
## New space and New worktree on the agent card: a click on New space
## sends one `workspace.create` with the pane's directory exactly as herdr
## sent it and `focus: false`, nothing else; a branch typed in the box and a
## click on Worktree send one `worktree.create` with the workspace as herdr
## spells it, the branch, the branch as label and `focus: false`, nothing
## else; the office then picks the new floor's shell. Every gate, by real
## input: a bad or changed directory, every bad branch (refused, never
## rewritten), a branch edited between press and release, a mezzanine as
## source, herdr's git refusals shown as one cleaned line, lost answers
## unknown and never resent, the audit's words, `--read-only`. An operator
## office against two fake herdrs of this suite's own. Run through
## tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_spaces.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## Every case first resets both fakes and opens only what it needs (_fakes()),
## and asserts the exact requests each fake received. The last case sums up
## both fakes: nothing reached them that no case opened.

## A git failure as herdr 0.9.0 forwards it, and a usage dump's size (docs/WRITE_BOUNDARY.md §6).
const GIT_TAKEN := (
	"Preparing worktree (checking out 'v1-a')\n"
	+ "fatal: 'v1-a' is already used by worktree at '/home/tester/.herdr/worktrees/herdstead/v1-a'\n"
	+ "hint: If you meant to create a worktree containing a new orphan branch\n"
	+ "hint: (branch with no commits) for this repository, you can do so\n"
)
const GIT_DUMP_CHARS := 2757
## Local's shell (alpha:p2) on the basic fixture; on the worktrees fixture the
## repo's own floor `hs` with its shell hs:p3, the mezzanine hud:p1, and the
## plain floor notes:p1.
var p2 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
var hs := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hs")
var hs_p3 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hs:p3")
var hud := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hud")
var hud_p1 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hud:p1")
var notes := HerdrFleet.pane_key(HerdrFleet.LOCAL, "notes")
var notes_p1 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "notes:p1")


func _marker() -> String:
	return "SPACES TESTS"


# --- pure ------------------------------------------------------------------------


## One line of git's stderr: the first `fatal:` or `error:` line, else the
## first line with anything on it; cleaned of control and direction
## characters, every grapheme cluster bounded, cut to the limit. Never a
## `hint:` line, never a path from another line.
func test_git_words_keeps_one_cleaned_line() -> void:
	_eq(
		GitWords.headline(GIT_TAKEN, 200),
		"fatal: 'v1-a' is already used by worktree at '/home/tester/.herdr/worktrees/herdstead/v1-a'",
		"the fatal line, not the one before, not the hints"
	)
	_eq(
		GitWords.headline("error: pathspec 'x' did not match\nhint: try again\n", 200),
		"error: pathspec 'x' did not match",
		"an error line"
	)
	_eq(
		GitWords.headline("\n  Preparing worktree (new branch 'b')  \n\n", 200),
		"Preparing worktree (new branch 'b')",
		"else the first line"
	)
	_eq(
		GitWords.headline("usage: git worktree add " + "x".repeat(GIT_DUMP_CHARS), 200).length(),
		200,
		"a usage dump is cut to the limit"
	)
	_eq(GitWords.headline("fatal: a\u0001b \u202ec\n", 200), "fatal: ab c", "control and direction characters out")
	var marks := "fatal: e" + "\u0301".repeat(40) + "!"
	_eq(GitWords.headline(marks, 200), "fatal: e!", "a long cluster keeps its base only")
	_eq(GitWords.headline("", 200), "", "nothing on any line")
	_eq(GitWords.headline(7, 200), "", "not text")


## The branch table: refused, never rewritten. Blank or with whitespace or an
## invisible character anywhere; over 64 bytes; a character outside the set;
## a shape git refuses; and what passes.
func test_branch_refusal_table() -> void:
	var blank := int(CommandRefusal.Reason.BRANCH_BLANK)
	var too_long := int(CommandRefusal.Reason.BRANCH_TOO_LONG)
	var chars := int(CommandRefusal.Reason.BRANCH_CHARS)
	var shape := int(CommandRefusal.Reason.BRANCH_SHAPE)
	var table: Dictionary[String, int] = {
		"": blank,
		" ": blank,
		"a b": blank,
		" a": blank,
		"a\t": blank,
		"a\nb": blank,
		"uni\u202ex": blank,
		"a\u200bb": blank,
		"x".repeat(65): too_long,
		"é".repeat(33): too_long,
		"bad$name": chars,
		"héllo": chars,
		"a:b": chars,
		"a~b": chars,
		"@": chars,
		"a..b": shape,
		"a//b": shape,
		"x.lock": shape,
		"a/x.lock/b": shape,
		"-x": shape,
		".x": shape,
		"a/.x": shape,
		"x/": shape,
		"x.": shape,
		"HEAD": shape,
		"refs/x": shape,
		"refs/heads/x": shape,
		"_x": shape,
		"/x": shape,
	}
	for text: String in table:
		_eq(int(HerdrCommands.branch_refusal(text)), table[text], "refused: %s" % text.c_escape())
	for text: String in ["v1-a", "feat/g4h", "a.b", "a_b", "9lives", "x".repeat(64), "A", "head", "refs", "a/b/c"]:
		_eq(HerdrCommands.branch_refusal(text), CommandRefusal.Reason.NONE, "allowed: " + text)
	_eq(int(HerdrFleet.branch_refusal("a b")), blank, "the fleet says the same")


## The snapshot says whether a pane's directory came as it is shown: absent,
## not text, holding a control character or a long cluster, or with edges to
## strip, it did not; and the flag signs the snapshot.
func test_the_snapshot_flags_a_clean_cwd() -> void:
	var raw := _raw()
	var clean := HerdrSnapshot.from_wire(raw)
	_eq([_cwd_of(clean, "alpha:p2"), _cwd_clean_of(clean, "alpha:p2")], ["/home/tester/alpha", true], "as sent")
	var odd := HerdrSnapshot.from_wire(_changed(raw, "alpha:p2", {"cwd": "/home/te\u0001ster/alpha"}))
	_eq(
		[_cwd_of(odd, "alpha:p2"), _cwd_clean_of(odd, "alpha:p2")], ["/home/tester/alpha", false], "a control character"
	)
	var padded := HerdrSnapshot.from_wire(_changed(raw, "alpha:p2", {"cwd": "/home/tester/alpha "}))
	_eq(_cwd_clean_of(padded, "alpha:p2"), false, "an edge to strip")
	var marked := HerdrSnapshot.from_wire(_changed(raw, "alpha:p2", {"cwd": "/home/e" + "\u0301".repeat(40)}))
	_eq(_cwd_clean_of(marked, "alpha:p2"), false, "a long cluster")
	var absent := HerdrSnapshot.from_wire(_changed(raw, "alpha:p2", {"cwd": null}))
	_eq([_cwd_of(absent, "alpha:p2"), _cwd_clean_of(absent, "alpha:p2")], ["", false], "absent")
	var numeric := HerdrSnapshot.from_wire(_changed(raw, "alpha:p2", {"cwd": 7}))
	_eq(_cwd_clean_of(numeric, "alpha:p2"), false, "not text")
	_check(clean.signature() != odd.signature(), "the flag is part of the signature")
	_eq(clean.wire_workspace_ids, PackedStringArray(["alpha", "bravo"]), "herdr's workspace ids, as sent")
	_eq(HerdrCommands.cwd_refusal("/home/tester"), CommandRefusal.Reason.NONE, "an absolute directory")
	_eq(HerdrCommands.cwd_refusal(""), CommandRefusal.Reason.CWD_UNKNOWN, "empty")
	_eq(HerdrCommands.cwd_refusal("work"), CommandRefusal.Reason.CWD_UNKNOWN, "relative")
	_eq(HerdrCommands.cwd_refusal("/a\u0001b"), CommandRefusal.Reason.CWD_UNCLEAN, "unclean")


## herdr's two result shapes read the same way: the new workspace's, tab's and
## root pane's ids (clean strings only), and for a worktree its path and branch.
func test_space_create_result_reads_both_shapes() -> void:
	var pane := {"pane_id": "w14:p1", "terminal_id": "term-w14-1", "workspace_id": "w14", "tab_id": "w14:t1"}
	var made := SpaceCreateResult.from_wire(
		{
			"type": "workspace_created",
			"workspace": {"workspace_id": "w14"},
			"tab": {"tab_id": "w14:t1"},
			"root_pane": pane
		}
	)
	_eq(
		[made.workspace_id, made.tab_id, made.pane_id, made.terminal_id, made.linked],
		["w14", "w14:t1", "w14:p1", "term-w14-1", false],
		""
	)
	var tree := (
		SpaceCreateResult
		. from_wire(
			{
				"type": "worktree_created",
				"workspace": {"workspace_id": "w15"},
				"tab": {"tab_id": "w15:t1"},
				"root_pane": {"pane_id": "w15:p1", "terminal_id": "t"},
				"worktree": {"path": "/x/v1-a", "branch": "v1-a\u0001"},
			}
		)
	)
	_eq(
		[tree.workspace_id, tree.pane_id, tree.linked, tree.worktree_path, tree.worktree_branch],
		["w15", "w15:p1", true, "/x/v1-a", "v1-a"],
		""
	)
	_eq(SpaceCreateResult.from_wire({"type": "pane_info", "pane": pane}), null, "another result")
	_eq(
		SpaceCreateResult.from_wire(
			{"type": "workspace_created", "workspace": {"workspace_id": "w\u00011"}, "root_pane": pane}
		),
		null,
		"an odd id"
	)
	_eq(
		SpaceCreateResult.from_wire(
			{"type": "workspace_created", "workspace": {"workspace_id": "w1"}, "root_pane": {}}
		),
		null,
		"no pane"
	)
	_eq(SpaceCreateResult.from_wire("no"), null, "not an object")


## The boundary itself: a space carries `cwd` and `focus: false`, a worktree
## `workspace_id`, `branch`, `label` and `focus: false`, nothing else; and on
## an empty herdr the first workspace is focused whatever was sent (the fake
## does as measured), which the office can only say.
func test_the_boundary_sends_exact_params_and_an_empty_herdr_focuses_the_first() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "workspace.create", "worktree.create"])
	var facts := _facts(args["socket-a"], _raw("snapshot_worktrees"))
	var commands := _boundary()
	var space := commands.submit(_aim(facts, "hs:p3").spacing("/home/tester/herdstead"), facts)
	_settle(commands, space, "the space")
	_eq(space.state, CommandTicket.State.ACCEPTED, "herdr made it")
	_eq(
		_asked("control-a", "workspace.create"),
		[{"cwd": "/home/tester/herdstead", "focus": false}],
		"cwd and focus, nothing else"
	)
	_eq([space.space.workspace_id, space.space.pane_id, space.space.linked], ["w6", "w6:p1", false], "the new ids")
	var entry: CommandAuditEntry = commands.write_log().back()
	_eq(
		[entry.method, entry.cwd_bytes, entry.summary],
		["workspace.create", 22, "workspace.create from hs:p3"],
		"audited by size"
	)
	_check(not "/home" in _entry_text(entry) and not "hud lane" in _entry_text(entry), "never the path")
	await _look(commands, facts, "hs:p3")
	var tree := commands.submit(_aim(facts, "hs:p3").branching("hs", "hs", "v1-a"), facts)
	_settle(commands, tree, "the worktree")
	_eq(tree.state, CommandTicket.State.ACCEPTED, "herdr made it")
	_eq(
		_asked("control-a", "worktree.create"),
		[{"workspace_id": "hs", "branch": "v1-a", "label": "v1-a", "focus": false}],
		"the four, nothing else: no path, no base, no cwd, no trust"
	)
	_eq([tree.space.workspace_id, tree.space.linked, tree.space.worktree_branch], ["w7", true, "v1-a"], "the new floor")
	entry = commands.write_log().back()
	_eq(
		[entry.method, entry.branch, entry.summary],
		["worktree.create", "v1-a", "worktree.create from hs:p3 branch v1-a"],
		"audited by branch"
	)
	_check(not "label" in entry.summary and not "/home" in _entry_text(entry), "never a label or a path")
	_eq(
		HerdrCommands.refusal(_aim(facts, "hud:p1").branching("hud", "hud", "b"), facts),
		CommandRefusal.Reason.MEZZANINE_SOURCE,
		"a mezzanine as source"
	)
	_eq(
		HerdrCommands.refusal(_aim(facts, "hs:p3").branching("hs", "hs", "a b"), facts),
		CommandRefusal.Reason.BRANCH_BLANK,
		"a bad branch"
	)
	_eq(
		HerdrCommands.refusal(_aim(facts, "hs:p3").branching("hs", "hs\u0001", "b"), facts),
		CommandRefusal.Reason.WIRE_ID_MISMATCH,
		"an odd workspace id"
	)
	_eq(
		HerdrCommands.refusal(_aim(facts, "hs:p3").branching("notes", "notes", "b"), facts),
		CommandRefusal.Reason.FLOOR_CHANGED,
		"another floor than the pane's"
	)
	var floorless := _raw("snapshot_worktrees")
	floorless["workspaces"] = _list(floorless, "workspaces").filter(
		func(record: Dictionary) -> bool: return record.get("workspace_id") != "hs"
	)
	var unlisted := _facts(args["socket-a"], floorless)
	_eq(
		HerdrCommands.refusal(_aim(unlisted, "hs:p3").branching("hs", "hs", "b"), unlisted),
		CommandRefusal.Reason.FLOOR_GONE,
		"a floor the snapshot does not list"
	)
	_eq(
		HerdrCommands.refusal(_aim(facts, "hs:p3").spacing("rel"), facts),
		CommandRefusal.Reason.CWD_UNKNOWN,
		"a relative directory"
	)
	_eq(
		HerdrCommands.refusal(_aim(facts, "hs:p3").spacing("/elsewhere"), facts),
		CommandRefusal.Reason.CWD_CHANGED,
		"not the pane's directory now"
	)
	# An empty herdr: the fake's snapshot has nothing, the office's facts still name the pane.
	var empty := _raw("snapshot_worktrees")
	for key: String in ["workspaces", "tabs", "panes", "layouts", "agents"]:
		empty[key] = []
	empty["focused_pane_id"] = null
	await _look(commands, facts, "hs:p3")
	_ctl("control-a", "set_snapshot", {"snapshot": empty})
	var first := commands.submit(_aim(facts, "hs:p3").spacing("/home/tester/herdstead"), facts)
	_settle(commands, first, "the first space of an empty herdr")
	_eq(first.state, CommandTicket.State.ACCEPTED, "made")
	_eq(
		_asked("control-a", "workspace.create").back(),
		{"cwd": "/home/tester/herdstead", "focus": false},
		"focus: false was sent"
	)
	_eq(
		_dict(_ctl("control-a", "stats"), "snapshot").get("focused_pane_id"),
		first.space.pane_id,
		"and herdr focused it regardless"
	)
	commands.free()


# --- the card ------------------------------------------------------------------------


## New space on a picked shell: one `workspace.create {cwd, focus: false}` with
## the pane's raw directory; the fake's new floor appears, herdr's focus
## stays, the office follows the root pane onto it (a pick across floors),
## whose card offers START AGENT; nothing is started.
func test_new_space_sends_cwd_and_no_focus_and_the_office_follows_onto_its_new_zone() -> void:
	var office := await _shell_local()
	var card := _card(office)
	var spacer := _space_button(office)
	await _until(func() -> bool: return spacer.is_visible_in_tree() and not spacer.disabled, "New space offered")
	_eq(spacer.text, "New space", "the button")
	_check(
		"/home/tester/alpha" in spacer.tooltip_text and "except on an empty herdr" in spacer.tooltip_text,
		"the tooltip: " + spacer.tooltip_text
	)
	_check(not "workspace.create" in spacer.tooltip_text, "and never names the method")
	_check(not _control(office, "ManageNote").is_visible_in_tree(), "no note while no branch is typed")
	var alpha := office.navigator.current_zone(office.frame)
	var world := office.world.get_instance_id()
	var w3 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "w3:p1")
	await _click_control(spacer)
	await _until(func() -> bool: return office.picked_key == w3, "the office picks the new zone's shell")
	_eq(
		_writes_seen("control-a"),
		PackedStringArray(["workspace.create /home/tester/alpha focus:false"]),
		"one space, no re-read"
	)
	_eq(
		_asked("control-a", "workspace.create"),
		[{"cwd": "/home/tester/alpha", "focus": false}],
		"cwd and focus, nothing else"
	)
	_eq(_dict(_ctl("control-a", "stats"), "snapshot").get("focused_pane_id"), "alpha:p1", "herdr's focus stays")
	await _until(
		func() -> bool:
			return office.navigator.current_zone(office.frame) == HerdrFleet.pane_key(HerdrFleet.LOCAL, "w3"),
		"its new zone current"
	)
	_check(office.navigator.current_zone(office.frame) != alpha, "another zone than the shell's")
	_eq([office.navigator.shown_key, office.world.get_instance_id()], [HerdrFleet.LOCAL, world], "on the same map")
	await _frames(2)
	_check(office.hud.world_rect().has_point(_desk_point(office, w3)), "panned: its desk in the world's room")
	await _until(func() -> bool: return _title(office) == "START AGENT", "its card: START AGENT")
	await _wait(1.0)
	_eq(_count("control-a", "agent.start"), 0, "nothing started")
	_eq(
		_writes_seen("control-a"),
		PackedStringArray(["workspace.create /home/tester/alpha focus:false"]),
		"and nothing more"
	)
	await _pick_local(office, "alpha:p2")
	await _until(func() -> bool: return card.outcome_text() == "New space w3", "back on the shell: the footer names it")
	_eq(_writes_seen("control-b"), PackedStringArray(), "bee heard nothing")


## A directory herdr would land in $HOME is refused on the card, with the
## reason: relative, empty, or spelled with a character the office does not
## show. And one that moved between the press and the release is refused at
## the release. Nothing is sent.
func test_a_bad_directory_is_refused_on_the_card_and_a_changed_one_at_the_release() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var spacer := _space_button(office)
	await _pick_local(office, "alpha:p2")
	await _until(func() -> bool: return spacer.is_visible_in_tree() and not spacer.disabled, "New space offered")
	var bad_directories: Dictionary[String, String] = {
		"work": "no absolute directory",
		"": "no absolute directory",
		"/home/te\u0001ster": "does not show",
	}
	for directory: String in bad_directories:
		var why := bad_directories[directory]
		_ctl("control-a", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p2", {"cwd": directory})})
		_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
		await _until(
			func() -> bool: return spacer.disabled and why in spacer.tooltip_text,
			"%s: off, and the tooltip says why: %s" % [directory.c_escape(), spacer.tooltip_text]
		)
		await _click_control(spacer)
		await _frames(3)
	_eq(_count("control-a", "workspace.create"), 0, "clicks on it sent nothing")
	_ctl("control-a", "set_snapshot", {"snapshot": _raw()})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return not spacer.disabled, "a good directory again: on")
	_half_click(spacer, true)
	await _frames(2)
	_ctl("control-a", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p2", {"cwd": "/home/tester/elsewhere"})})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.frame.pane(p2).cwd == "/home/tester/elsewhere", "the shell moved")
	_half_click(spacer, false)
	await _until(
		func() -> bool: return card.outcome_text() == "Not sent: the directory changed", "refused at the release"
	)
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing was sent")


## A branch typed and Worktree clicked on the repo's own floor: one
## `worktree.create {workspace_id, branch, label, focus: false}` with herdr's
## workspace id; the fake's mezzanine hangs under the parent in FLOORS, and
## the office follows onto it. A floor whose record has no `worktree` yet is
## offered too (herdr resolves the repo): its parent gains the field.
func test_new_worktree_sends_four_fields_and_the_mezzanine_hangs_under_its_parent() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "worktree.create"])
	_ctl("control-a", "set_repo", {"workspace_id": "notes", "repo_root": "/home/tester/notes"})
	var office := await _office_with(false, false)
	var card := _card(office)
	var trees := _worktree_button(office)
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(trees.is_visible_in_tree, "the worktree row")
	await _frames(3)
	_check(trees.disabled, "off until a branch is typed")
	_eq(trees.text, "Worktree", "the button")
	await _click_control(_branch_box(office))
	await _type("v1-a")
	_eq(_branch_box(office).text, "v1-a", "typed as it is")
	await _until(func() -> bool: return not trees.disabled, "a good branch: on")
	_eq(_manage_note(office), "New worktree: branch v1-a from this space", "the note names it")
	_check(
		"git hooks on Local" in trees.tooltip_text and "checks it out if it exists" in trees.tooltip_text,
		"the tooltip: " + trees.tooltip_text
	)
	_check(not "worktree.create" in trees.tooltip_text, "and never names the method")
	var chips_before := _chips(office)
	await _click_control(trees)
	var w6 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "w6:p1")
	await _until(func() -> bool: return office.picked_key == w6, "the office picks the new floor's shell")
	_eq(
		_writes_seen("control-a"), PackedStringArray(["worktree.create hs v1-a label:v1-a focus:false"]), "one worktree"
	)
	_eq(
		_asked("control-a", "worktree.create"),
		[{"workspace_id": "hs", "branch": "v1-a", "label": "v1-a", "focus": false}],
		"the four, nothing else"
	)
	await _until(
		func() -> bool: return "1C" in _chips(office), "the mezzanine hangs under 1F as 1C: %s" % [_chips(office)]
	)
	_eq(_chips(office).size(), chips_before.size() + 1, "one more floor")
	await _until(
		func() -> bool:
			return office.navigator.current_zone(office.frame) == HerdrFleet.pane_key(HerdrFleet.LOCAL, "w6"),
		"its zone current"
	)
	_eq(_dict(_ctl("control-a", "stats"), "snapshot").get("focused_pane_id"), "hs:p1", "herdr's focus stays")
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(func() -> bool: return card.outcome_text() == "New worktree v1-a → w6", "back: the footer names it")
	_eq(_branch_box(office).text, "", "the box is empty again: a branch never follows the card")
	# notes: no `worktree` in its record; herdr knows it is a repo.
	await _floor_pick(office, notes)
	await _click_visible_pane(office, notes_p1)
	await _open_panel(office)
	await _until(trees.is_visible_in_tree, "notes: the worktree row")
	await _click_control(_branch_box(office))
	await _type("b")
	await _until(func() -> bool: return not trees.disabled, "offered")
	await _click_control(trees)
	var w7 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "w7:p1")
	await _until(func() -> bool: return office.picked_key == w7, "picked")
	await _until(
		func() -> bool: return "4A" in _chips(office),
		"notes gained its worktree: a mezzanine 4A: %s" % [_chips(office)]
	)
	_eq(_count("control-a", "worktree.create"), 2, "two worktrees")


## Every bad branch, typed for real, is refused on the card with the reason,
## the box untouched, and nothing sent: blank, spaces, 65 bytes, a bad
## character, `..`, `.lock`, `-x`, `refs/`, `HEAD`, `@`, a direction
## override. Enter in the box sends nothing, and the office's keys are the
## box's while it has focus.
func test_every_bad_branch_is_refused_on_the_card_and_enter_sends_nothing() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "worktree.create"])
	var office := await _office_with(false, false)
	var trees := _worktree_button(office)
	var box := _branch_box(office)
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(trees.is_visible_in_tree, "the worktree row")
	await _click_control(box)
	_check(box.has_focus(), "the box takes the keyboard")
	await _type("s")
	_check(not office.hud.strategic_open(), "S typed in the box opens no strategic view")
	await _tap(KEY_BACKSPACE)
	_eq(box.text, "", "erased")
	var table: Dictionary[String, String] = {
		"a b": "type a branch name first",
		"é".repeat(33): "at most 64 bytes",
		"bad$name": "holds only letters",
		"a..b": "git would refuse",
		"x.lock": "git would refuse",
		"-x": "git would refuse",
		"refs/x": "git would refuse",
		"HEAD": "git would refuse",
		"@": "holds only letters",
		"uni\u202ex": "type a branch name first",
	}
	for text: String in table:
		var why := table[text]
		await _type(text)
		_eq(box.text, text, "typed as it is: " + text.c_escape())
		await _frames(2)
		_check(trees.disabled, "%s: off" % text.c_escape())
		_check(why in trees.tooltip_text, "%s: the tooltip says why: %s" % [text.c_escape(), trees.tooltip_text])
		_check(
			_manage_note(office).begins_with("Branch: "),
			"%s: the note says why: %s" % [text.c_escape(), _manage_note(office)]
		)
		await _tap(KEY_ENTER)
		await _click_control(trees)
		await _frames(2)
		_eq(box.text, text, "still as typed: " + text.c_escape())
		for _i in text.length():
			await _tap(KEY_BACKSPACE)
		_eq(box.text, "", "erased")
	_check(trees.disabled, "blank: off")
	_check("type a branch name first" in trees.tooltip_text, "and says so")
	await _tap(KEY_ENTER)
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing was sent")


## The branch box changing between the press and the release refuses the
## worktree: exactly the name aimed at the press goes, or nothing.
func test_a_branch_edited_between_press_and_release_is_refused() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "worktree.create"])
	var office := await _office_with(false, false)
	var card := _card(office)
	var trees := _worktree_button(office)
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(trees.is_visible_in_tree, "the worktree row")
	await _click_control(_branch_box(office))
	await _type("v1")
	await _until(func() -> bool: return not trees.disabled, "on")
	_half_click(trees, true)
	await _frames(2)
	await _type("-b")
	_half_click(trees, false)
	await _until(func() -> bool: return card.outcome_text() == "Not sent: the branch changed", "refused at the release")
	await _wait(0.5)
	_eq(_writes_seen("control-a"), PackedStringArray(), "nothing was sent")
	_eq(_branch_box(office).text, "v1-b", "the box keeps what was typed")


## A mezzanine is no source for a worktree: off, with the reason. And herdr's
## own refusals from the repo's floor are said in one cleaned line: a linked
## source, no git repo, and git's failure by its headline only (no `hint:`,
## no line before it, at most 200 characters), the headline in the tooltip;
## nothing retried.
func test_a_mezzanine_source_is_off_and_herdrs_git_refusals_show_one_line() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "worktree.create"])
	var office := await _office_with(false, false)
	var card := _card(office)
	var trees := _worktree_button(office)
	await _floor_pick(office, hud)
	await _click_visible_pane(office, hud_p1)
	await _open_panel(office)
	if card.answering():
		await _tap(KEY_ESCAPE)
	await _until(trees.is_visible_in_tree, "the worktree row on the mezzanine")
	await _click_control(_branch_box(office))
	await _type("b")
	await _frames(3)
	_check(trees.disabled, "off on a mezzanine")
	_check("linked worktree" in trees.tooltip_text, "the tooltip says why: " + trees.tooltip_text)
	await _click_control(trees)
	await _frames(2)
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(trees.is_visible_in_tree, "the repo's own floor")
	var outcome: Label = card.get_node("%Outcome")
	var codes := PackedStringArray(
		["linked_worktree_source", "not_git_worktree", "worktree_create_failed", "worktree_create_failed"]
	)
	var messages := PackedStringArray(
		[
			"New and open worktree actions start from the repo parent workspace.",
			"Herdr worktree actions require a workspace inside a Git work tree",
			GIT_TAKEN,
			"usage: git worktree add " + "x".repeat(GIT_DUMP_CHARS),
		]
	)
	var footers := PackedStringArray(
		[
			"herdr refused: start from the repo's own space",
			"herdr refused: not a git repo",
			"herdr refused: git: fatal: 'v1-a' is already used by worktree at '/home/tester/.herdr/worktrees/herdstead/v1-a'",
			"",
		]
	)
	for index in codes.size():
		_ctl("control-a", "set_worktree_result", {"code": codes[index], "message": messages[index]})
		await _click_control(_branch_box(office))
		await _type("v1-a")
		await _until(func() -> bool: return not trees.disabled, "%d: offered" % index)
		await _click_control(trees)
		await _until(func() -> bool: return card.outcome_text().begins_with("herdr refused"), "%d: refused" % index)
		if not footers[index].is_empty():
			_eq(card.outcome_text(), footers[index], "%d: the footer" % index)
		_check(not "hint:" in card.outcome_text() and not "Preparing" in card.outcome_text(), "%d: one line" % index)
		_check(
			card.outcome_text().length() <= 200 + "herdr refused: git: ".length(),
			"%d: bounded: %d" % [index, card.outcome_text().length()]
		)
		_check(codes[index] in outcome.tooltip_text, "%d: the code in the tooltip: %s" % [index, outcome.tooltip_text])
		_check(not "hint:" in outcome.tooltip_text, "%d: no hint there either" % index)
		_eq(_count("control-a", "worktree.create"), index + 1, "%d: sent once" % index)
		for _i in 4:
			await _tap(KEY_BACKSPACE)
		await _until(func() -> bool: return not _fleet_must_look(office), "%d: looked at" % index)
	await _wait(1.0)
	_eq(_count("control-a", "worktree.create"), codes.size(), "nothing retried")


## A space or a worktree herdr made but whose answer was lost: the footer
## says the snapshot is the only judge, the new floor shows, the office does
## not pick a shell it never learned of, and nothing is sent again.
func test_a_lost_space_or_worktree_answer_is_unknown_and_never_resent() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "workspace.create", "worktree.create"])
	var office := await _office_with(false, false)
	var card := _card(office)
	var spacer := _space_button(office)
	var trees := _worktree_button(office)
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(func() -> bool: return spacer.is_visible_in_tree() and not spacer.disabled, "New space offered")
	_ctl("control-a", "next", {"action": "execute_then_drop", "method": "workspace.create"})
	await _click_control(spacer)
	await _until(
		func() -> bool:
			return card.outcome_text() == "New space: no answer from herdr; if a new space appears, that is it.",
		"the footer: no answer"
	)
	var w6 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "w6")
	await _until(func() -> bool: return office.frame.find_zone(w6) != null, "the new floor shows")
	await _wait(1.0)
	_eq(office.picked_key, hs_p3, "not picked: the office never learned its id")
	_eq(_count("control-a", "workspace.create"), 1, "never sent again")
	await _until(func() -> bool: return not spacer.disabled, "looked at: offered again")
	await _click_control(_branch_box(office))
	await _type("v1-c")
	await _until(func() -> bool: return not trees.disabled, "a branch: Worktree on")
	_ctl("control-a", "next", {"action": "execute_then_drop", "method": "worktree.create"})
	await _click_control(trees)
	await _until(
		func() -> bool:
			return (
				card.outcome_text()
				== "New worktree: no answer from herdr; git may have run. If a new space appears, that is it."
			),
		"the footer: git may have run"
	)
	var w7 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "w7")
	await _until(func() -> bool: return office.frame.find_zone(w7) != null, "the new floor shows")
	await _wait(1.0)
	_eq(office.picked_key, hs_p3, "not picked")
	_eq(_count("control-a", "worktree.create"), 1, "never sent again")
	_eq(_writes_seen("control-b"), PackedStringArray(), "bee heard nothing")


## The viewer navigating while a new space is on its way is moving on (codex
## #5), even back to where they were: New space, then a real PageDown (a pan to
## bravo on the same map) and PageUp (alpha again) before a snapshot shows the
## new zone: its shell is not picked, the footer says so, and one space was made.
func test_a_new_space_is_not_picked_after_the_viewer_paged_away() -> void:
	var office := await _shell_local()
	var card := _card(office)
	var spacer := _space_button(office)
	await _until(func() -> bool: return spacer.is_visible_in_tree() and not spacer.disabled, "New space offered")
	var alpha := office.navigator.current_zone(office.frame)
	var picked := office.picked_key
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "delay", "method": "session.snapshot", "seconds": 2.5})
	await _click_control(spacer)
	await _until(func() -> bool: return card.outcome_text() == "New space w3", "herdr made w3")
	# The rail is ascending: bravo (2) is the row after alpha (1).
	await _navigate_key(office, KEY_PAGEDOWN)
	_eq(office.navigator.current_zone(office.frame), HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo"), "PageDown: bravo")
	await _navigate_key(office, KEY_PAGEUP)
	_eq(office.navigator.current_zone(office.frame), alpha, "PageUp: alpha again")
	var w3 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "w3")
	_check(office.frame.find_zone(w3) == null, "before any snapshot showed the new zone")
	await _until(func() -> bool: return office.frame.find_zone(w3) != null, "a snapshot shows it")
	await _wait(1.0)
	_eq(office.picked_key, picked, "its shell is not picked: the viewer navigated meanwhile")
	_eq(card.outcome_text(), "New space w3: not picked", "the footer says so")
	_eq(_count("control-a", "workspace.create"), 1, "one space made")
	_eq(_writes_seen("control-b"), PackedStringArray(), "bee heard nothing")


## A `--read-only` office offers neither: no rows, no box; a pick, a typed
## branch attempt and Enter ask nothing but the read-only three.
func test_read_only_offers_neither_and_writes_nothing() -> void:
	_fakes("snapshot_worktrees", [])
	var office := await _office_with(true, false)
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _tap(KEY_ENTER)
	await _frames(10)
	_check(not _control(office, "Launch").is_visible_in_tree(), "no block")
	_check(not _space_button(office).is_visible_in_tree(), "no New space")
	_check(not _branch_box(office).is_visible_in_tree(), "no branch box")
	await _type("v1-a")
	await _tap(KEY_ENTER)
	await _frames(3)
	for which: String in ["control-a", "control-b"]:
		_eq(_sequence(which), PackedStringArray(), "%s: nothing beyond the read-only three" % which)


## The audit of the three writes: a close keeps its scope and the state word,
## a space the directory's byte count, a worktree the branch; never a path,
## a label or git's text.
func test_the_audit_carries_scope_cwd_bytes_and_branch_and_never_a_path_or_label() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "pane.close", "workspace.create", "worktree.create"])
	_ctl("control-a", "set_worktree_result", {"code": "worktree_create_failed", "message": GIT_TAKEN})
	var office := await _office_with(false, false)
	var card := _card(office)
	var closer := _close_button(office)
	var spacer := _space_button(office)
	var trees := _worktree_button(office)
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(func() -> bool: return trees.is_visible_in_tree(), "the rows")
	await _click_control(_branch_box(office))
	await _type("v1-a")
	await _until(func() -> bool: return not trees.disabled, "Worktree on")
	await _click_control(trees)
	await _until(func() -> bool: return card.outcome_text().begins_with("herdr refused: git:"), "git refused")
	await _until(func() -> bool: return not spacer.disabled, "looked at")
	await _click_control(spacer)
	await _until(func() -> bool: return office.picked_key != hs_p3, "the space made and picked")
	await _floor_pick(office, hs)
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close on")
	await _click_control(closer)
	await _frames(2)
	await _click_control(closer)
	await _until(func() -> bool: return office.frame.pane(hs_p3) == null, "closed")
	var writes := office.fleet.write_log()
	_eq(writes.size(), 3, "three writes")
	var tree_entry := writes[0]
	_eq(
		[tree_entry.method, tree_entry.branch, tree_entry.summary, tree_entry.error_code],
		["worktree.create", "v1-a", "worktree.create from hs:p3 branch v1-a", "worktree_create_failed"],
		"the worktree"
	)
	var space_entry := writes[1]
	_eq(
		[space_entry.method, space_entry.cwd_bytes, space_entry.summary],
		["workspace.create", "/home/tester/herdstead".length(), "workspace.create from hs:p3"],
		"the space"
	)
	var close_entry := writes[2]
	_eq(
		[close_entry.method, close_entry.scope, close_entry.summary],
		["pane.close", "pane", "pane.close hs:p3 pane shell"],
		"the close"
	)
	for entry in writes:
		var text := _entry_text(entry)
		_check(not "/home" in text and not "worktrees" in text, "no path: " + text)
		_check(not "label" in text and not "fatal" in text and not "hint" in text, "no label, no git text: " + text)


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)


# --- helpers only these cases use ------------------------------------------------


func _close_button(office: OfficeDouble) -> Button:
	return office.hud.inspector.get_node("%CloseButton")


func _space_button(office: OfficeDouble) -> Button:
	return office.hud.inspector.get_node("%SpaceButton")


func _worktree_button(office: OfficeDouble) -> Button:
	return office.hud.inspector.get_node("%WorktreeButton")


func _branch_box(office: OfficeDouble) -> LineEdit:
	return office.hud.inspector.get_node("%BranchBox")


func _title(office: OfficeDouble) -> String:
	return (_control(office, "LaunchTitle") as Label).text


func _manage_note(office: OfficeDouble) -> String:
	var note: Label = _control(office, "ManageNote")
	return note.text if note.is_visible_in_tree() else ""


## The FLOORS column's chips, top to bottom (`5F`, `1A` …).
func _chips(office: OfficeDouble) -> Array:
	var minimap := office.hud.spaces
	return minimap.row_keys().map(
		func(key: String) -> String: return (minimap.row_for(key).get_node("%Number") as Label).text
	)


## Whether the picked pane still owes a look after its last write.
func _fleet_must_look(office: OfficeDouble) -> bool:
	return office.fleet.must_look(office.picked_key)


func _cwd_of(snapshot: HerdrSnapshot, pane_id: String) -> String:
	for pane in snapshot.panes:
		if pane.pane_id == pane_id:
			return pane.cwd
	return "?"


func _cwd_clean_of(snapshot: HerdrSnapshot, pane_id: String) -> bool:
	for pane in snapshot.panes:
		if pane.pane_id == pane_id:
			return pane.cwd_clean
	return false


## Right after fake `which` answered a snapshot poll: the next is
## HerdrClient.SNAPSHOT_INTERVAL away, so the next snapshot it is asked for
## is the one an event asks for (as tools/test_split.gd waits).
func _after_a_poll(which: String) -> void:
	var before := _count(which, "session.snapshot")
	await _until(func() -> bool: return _count(which, "session.snapshot") > before, "a snapshot poll")
	await _frames(2)
