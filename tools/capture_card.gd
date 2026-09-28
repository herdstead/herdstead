extends "res://tools/command_test_base.gd"
## `make capture`'s pictures of the agent card's answer mode (tools/capture.sh):
## a real office in a real window, as an operator against capture.sh's own fake
## herdr, driven by real input the way tools/test_commands.gd drives it. Every
## terminal text is one this script hands the fake, never a terminal's; every
## write goes to the fake. Nothing here runs in the product: the office itself
## has no way to put its card into a state without the input that leads there.
##
## godot --path . --script tools/capture_card.gd -- --socket-a=<fake> \
##     --control-a=<its control> --pack=res://assets/<id>/manifest.json \
##     --zoom=<n> --out=<dir> --tag=<name>
##
## Writes <out>/card-<state>-<tag>.png for each state below, then quits 0; a
## state that never comes about quits 1 naming it. Windowed only.

## The states, in the order they are staged.
const STATES: Array[String] = [
	"offered",
	"answer",
	"rows",
	"not-sent",
	"unknown",
	"line-refused",
	"start",
	"start-confirm",
	"start-no-prompt",
	"new",
	"close-confirm",
	"worktree"
]
const FIXTURE := "snapshot_floors"
## The blocked agent on the api floor, which herdr's focus starts on.
const BLOCKED := "api:p1"
## The idle agent next to it.
const IDLE := "api:p2"
## The shell at the same table.
const SHELL := "api:p3"

var _problems := PackedStringArray()


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for name: String in ["socket-a", "control-a", "pack", "zoom", "out", "tag"]:
		if not args.has(name):
			print("CAPTURE_CARD: missing --%s=" % name)
			quit(2)
			return
	_capture.call_deferred()


## Not a test run: no case discovery, no summary line.
func _marker() -> String:
	return "CARD CAPTURE"


func _capture() -> void:
	await process_frame
	# A window the OS made smaller than --resolution asked shows less, and
	# maybe at a lower even scale: not the picture this run is for.
	var clamped := CaptureDriver.window_problem(root, str(args.get("window", "")))
	if not clamped.is_empty():
		print("CAPTURE_CARD_FAILED: " + clamped)
		quit(1)
		return
	var zoom := int(args.zoom)
	var shown := OfficeScene.content_scale_for(root.size, zoom)
	if shown != zoom:
		print(
			(
				"CAPTURE_CARD_FAILED: the %dx%d window shows %dx, --zoom asked for %dx (did the OS shrink the window?)"
				% [root.size.x, root.size.y, shown, zoom]
			)
		)
		quit(1)
		return
	_ctl("control-a", "reset", {"fixture": FIXTURE})
	_ctl("control-a", "allow", {"methods": OPERABLE})
	var office := _office_here()
	await _until(func() -> bool: return office.fleet.live_count() == 1, "the fake herdr is live")
	var card := _card(office)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, BLOCKED)
	# 1. A blocked agent's whole question, answer mode open: every key on.
	_ctl("control-a", "set_preview", {"pane_id": BLOCKED, "source": "detection", "text": _question(8, false)})
	_ctl("control-a", "status", {"pane_id": BLOCKED, "agent_status": "blocked"})
	await _pick(office, key)
	# Picked, nothing pressed: the staff panel's one line (at every size).
	await _shoot("picked", func() -> bool: return office.picked_key == key)
	await _open_up(office)
	# 0. Picked and answerable, answer mode not open yet: the heading's chip.
	var hint: Button = card.get_node("%AnswerButton")
	await _shoot("offered", func() -> bool: return card.answer_offered() and hint.is_visible_in_tree())
	await _tap(KEY_ENTER)
	await _until(card.answering, "answer mode")
	await _shoot("answer", func() -> bool: return not _key_button(office, "Key1").disabled)
	# 2. 31 rows, one of them wider than the card: "12 of 31 rows · clipped".
	_ctl("control-a", "set_preview", {"pane_id": BLOCKED, "source": "detection", "text": _question(31, true)})
	await _shoot("rows", func() -> bool: return card.preview_caption() == "12 of 31 rows · clipped")
	# 3. The question changes between the press and the re-read: not sent.
	var changed := {"pane_id": BLOCKED, "source": "detection", "text": _question(31, true) + "> 3. Other\n"}
	_ctl("control-a", "next", {"action": "stage", "method": "pane.read", "id_suffix": ":check", "preview": changed})
	await _click_control(_key_button(office, "Key1"))
	await _shoot("not-sent", func() -> bool: return card.outcome_text().begins_with("Not sent: the terminal changed"))
	# 4. After a look, a key whose answer herdr cuts off halfway: unknown.
	_ctl("control-a", "set_preview", {"pane_id": BLOCKED, "source": "detection", "text": _question(8, false)})
	await _until(func() -> bool: return card.keys_refusal() == CommandRefusal.Reason.NONE, "looked again")
	_ctl("control-a", "next", {"action": "close_midreply", "method": "pane.send_keys"})
	await _click_control(_key_button(office, "Key2"))
	await _shoot("unknown", func() -> bool: return card.outcome_text() == "Unknown result: look first")
	# 5. The idle agent next door, a typed line with an invisible character in it.
	var idle := HerdrFleet.pane_key(HerdrFleet.LOCAL, IDLE)
	_ctl("control-a", "set_preview", {"pane_id": IDLE, "source": "recent_unwrapped", "text": _recent()})
	await _pick(office, idle)
	await _open_up(office)
	await _until(card.answer_offered, "the idle agent may take a line")
	await _tap(KEY_ENTER)
	await _until(card.answering, "answer mode on the idle agent")
	await _click_control(_reply_box(office))
	await _type("ship it" + char(0x200b) + " now")
	await _shoot("line-refused", func() -> bool: return card.outcome_text() == "Line: invisible character")
	# 6. The shell at the same table: START AGENT over an empty prompt, a kind per agent Local shows.
	var shell := HerdrFleet.pane_key(HerdrFleet.LOCAL, SHELL)
	var listing := "~/code/api $ ls\nDockerfile  src  tests\n"
	_ctl(
		"control-a",
		"set_preview",
		{"pane_id": SHELL, "source": "recent_unwrapped", "text": listing + "~/code/api $ \n"}
	)
	await _pick(office, shell)
	await _open_up(office)
	var kind: Button = card.get_node("%Kind0")
	var launch: Control = card.get_node("%Launch")
	await _shoot("start", func() -> bool: return launch.is_visible_in_tree() and not kind.disabled)
	# 7. A theme's prompt (oh-my-zsh): a first click only arms the confirm, and writes nothing.
	var themed := listing + "➜  api git:(main) ✗ \n"
	_ctl("control-a", "set_preview", {"pane_id": SHELL, "source": "recent_unwrapped", "text": themed})
	await _until(func() -> bool: return card.preview_text() == themed, "the themed prompt is shown")
	await _click_control(kind)
	var line: Control = card.get_node("%LaunchLine")
	await _shoot("start-confirm", func() -> bool: return line.is_visible_in_tree())
	# 8. Nothing whole to look at: every kind off, saying why in its tooltip.
	_ctl("control-a", "set_preview", {"pane_id": SHELL, "source": "recent_unwrapped", "text": "\n\n"})
	await _shoot("start-no-prompt", func() -> bool: return card.preview_text() == "\n\n" and kind.disabled)
	# 9. The claude at api:p1 working again: NEW PANE BESIDE CLAUDE, down for its
	# 80x80 pane. Not clicked. (Working, it takes no answer, so Enter opens the
	# card up rather than answer mode, and the block shows.)
	_ctl("control-a", "status", {"pane_id": BLOCKED, "agent_status": "working"})
	await _pick(office, key)
	await _open_up(office)
	var split: Button = card.get_node("%SplitButton")
	await _shoot("new", func() -> bool: return split.is_visible_in_tree() and not split.disabled)
	# 10. Close on the working claude: a first click arms the confirm with the
	# heavier words (nothing is sent; a second click would kill it).
	var closer: Button = card.get_node("%CloseButton")
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _shoot("close-confirm", func() -> bool: return closer.text == "Close · kills")
	# 11. The shell on the repo's own floor with a branch typed: Worktree offered.
	await _pick(office, shell)
	await _open_up(office)
	var box: LineEdit = card.get_node("%BranchBox")
	await _until(box.is_visible_in_tree, "the branch box")
	await _click_control(box)
	await _type("feature-x")
	var trees: Button = card.get_node("%WorktreeButton")
	await _shoot("worktree", func() -> bool: return box.text == "feature-x" and not trees.disabled)
	if not _problems.is_empty():
		for problem in _problems:
			print("CAPTURE_CARD_FAILED: " + problem)
		quit(1)
		return
	print("CAPTURE_CARD_OK: %s" % args.tag)
	quit(0)


## The office in this window, as an operator on the fake, sized the way the
## window and `--zoom=` make it.
func _office_here() -> OfficeDouble:
	var zoom := int(args.zoom)
	var window := Vector2(root.size)
	var scale := OfficeScene.content_scale_for(root.size, zoom)
	var office := OfficeDouble.new()
	office.test_screen = window / scale
	office.test_args = AppArgs.parse(
		PackedStringArray(["--socket=" + args["socket-a"], "--pack=" + args.pack, "--zoom=%d" % zoom])
	)
	office.manifest_path = args.pack
	office.remember_theme = false
	_offices.append(office)
	root.add_child(office)
	return office


## Pick the desk of `key` with a real click, on its floor.
func _pick(office: OfficeDouble, key: String) -> void:
	await _frames(4)
	await _click_visible_pane(office, key)
	await _until(func() -> bool: return office.picked_key == key, "picked " + key)


## The picked agent's card is the staff panel's one line until opened (at every
## size): Enter opens it up, as a viewer would, so it reads and shows the terminal.
func _open_up(office: OfficeDouble) -> void:
	if office.hud.card_compact():
		await _tap(KEY_ENTER)
		await _until(func() -> bool: return not office.hud.card_compact(), "the card opened up")


## Wait for `ready`, let the frame settle, and save it as card-<state>-<tag>.png.
func _shoot(state: String, ready: Callable) -> void:
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000)
	while not ready.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not ready.call():
		_problems.append("%s never came about" % state)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var path: String = args.out.path_join("card-%s-%s.png" % [state, args.tag])
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_problems.append("cannot save %s: %s" % [path, error_string(error)])
	else:
		print("CAPTURE_OK: " + path)


## A scripted question of `rows` rows, the last lines of it the choice; with
## `wide`, one of the rows the card shows far wider than the card.
static func _question(rows: int, wide: bool) -> String:
	var lines := PackedStringArray()
	for index in maxi(rows - 5, 0):
		lines.append("  context line %d of the diff" % (index + 1))
	if wide and lines.size() > 2:
		lines[lines.size() - 2] = "  " + "a very long command line that no card is wide enough to show ".repeat(3)
	lines.append_array(["Bash command: make capture", "Do you want to proceed?", "> 1. Yes", "  2. No", "  3. Tell me"])
	return "\n".join(lines) + "\n"


static func _recent() -> String:
	return "Done: the capture is in /tmp/shots.\n\n$ \n"
