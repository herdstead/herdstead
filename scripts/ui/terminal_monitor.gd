class_name TerminalMonitor
extends Control
## The terminal monitor (docs/WRITE_BOUNDARY.md §3): one pane's terminal, near full
## screen, live. It shows herdr's own screen, read about five times a second,
## and while it has the keyboard every key goes to that terminal: raw mode.
## It is HUD, not the world: nothing on the floor changes for it.
##
## Reads and writes go through the fleet's typed calls only (a CommandContext
## in, a CommandTicket out); this file names no herdr method.
##
## Reading. Only while the monitor is open, its machine online and current,
## and the window not minimized: every READ_FOCUSED seconds while the window
## has focus, every READ_UNFOCUSED without it, and at once plus
## FOLLOW_UP_MSEC later after each input request, so the echo shows without
## waiting for the next tick; never sooner than COST_FACTOR times what the
## last parse and draw took (next_read_delay()). At most one read is out at a time. herdr's
## `revision` is always 0, so a change is found by comparing the text, and the
## grid redraws only the rows that changed.
##
## Typing. Every key event while the monitor has the keyboard is a gesture:
## the key map (TerminalKeys) turns it into a key name or typed text; one
## frame's input becomes one request per run of the same kind, in order, and
## the fleet's queue keeps that order across requests. Esc goes to the
## terminal. Ctrl+] closes the monitor and is never sent; the paste chord
## (Cmd+V on macOS, Ctrl+Shift+V elsewhere) pastes the clipboard. No office
## key fires while the monitor is open. Nothing but a key event or a paste
## ever writes: reads, timers and refreshes never do.
##
## What it is aimed at is fixed when it opens: the machine and its generation,
## the pane, and its terminal id. Another agent or session in that terminal
## (an agent started in a shell, `/clear`) is the same terminal and input goes
## on. When the terminal changes (a new terminal id) or the pane closes, input
## stops and says so; typing resumes only after "Follow new terminal" or a
## reopen, and then only once a read of the new terminal is on screen.
## Closing drops whatever input is still queued: it is never sent.
## A machine that drops freezes the last screen, dimmed, and says OFFLINE
## (invariant 4); when it is back with the same terminal, input comes back once
## a fresh read is shown. In `--read-only` the office has no command boundary
## at all: the monitor opens, reads nothing, sends nothing, and says so.
##
## The mouse wheel scrolls a local view of the pane's recent output (at most
## HerdrCommands.SCROLLBACK_LINES_MAX lines, fetched when the wheel first
## turns); any key returns to the live screen. herdr's own scroll position is
## never touched. There is no cursor: herdr 0.9.0 does not report one.

## The monitor closed: its close button, or Ctrl+].
signal closed

enum Mode {
	## Closed.
	CLOSED,
	## Input goes to the terminal.
	LIVE,
	## Waiting for a read of the terminal aimed at: open, followed, reconnected.
	ARMING,
	## The machine is offline, stale, replaced or speaks an unknown protocol.
	OFFLINE,
	## The pane's terminal changed, or the pane closed: input stopped.
	STOPPED,
	## `--read-only`, or no fleet: nothing is read or sent.
	VIEW_ONLY,
}

## Seconds between reads with the window focused, and without.
const READ_FOCUSED := 0.2
const READ_UNFOCUSED := 1.0
## The second read after an input request, in milliseconds after it went.
const FOLLOW_UP_MSEC := 50
## Rows a wheel notch scrolls.
const WHEEL_ROWS := 3
const CURSOR_NOTE := "no cursor from herdr"
## The most cells the grid draws: a layout rect past it (the snapshot keeps up
## to HerdrSnapshot.MAX_RECT_CELLS a side) is drawn clipped to it, and the status line says so.
const GRID_MAX := Vector2i(400, 200)
## The next read waits at least this many times the last parse and draw.
const COST_FACTOR := 4.0

## Reads asked for and shown this opening, for tests and the perf probe.
var reads_asked := 0
var reads_shown := 0
## Where a paste reads the clipboard: DisplayServer.clipboard_get() unless a
## test hands it a Callable returning a String (a headless display server has
## no clipboard). Only the paste chord ever calls it.
var clipboard := Callable()

var _fleet: HerdrFleet
var _minimized := Callable()
var _mode := Mode.CLOSED
## What input and reads are aimed at (CommandContext.aimed()), and the pane shown.
var _target: CommandContext
var _pane: PaneModel
var _machine_label := ""
var _dimmed := false
var _binding := 0
var _window_focused := true
## The read out now, and when the next may start.
var _read_ticket: CommandTicket
var _next_read_in := 0.0
## Time.get_ticks_msec() of a follow-up read owed after input; -1 for none.
var _follow_up_at := -1
## Input taken this frame, in order: [true, key name] or [false, text].
var _batch: Array[Array] = []
## Tickets of input requests on their way, and when each was asked for.
var _sent_at: Dictionary[CommandTicket, int] = {}
var _latency_msec := -1
var _message := ""
var _message_detail := ""
## The last `visible` text shown, and the scrollback: its lines and how many
## rows up from the bottom the view is (0: live).
var _live_text := ""
var _scroll_lines := PackedStringArray()
var _scroll_offset := 0
var _scroll_wanted := false
var _switch_context: CommandContext
var _switch_ticket: CommandTicket
var _grid_note := ""
var _read_started_msec := -1000000
## STOPPED only: why input stopped (a new terminal offers "Follow"; a closed
## pane does not). Kept apart from the message, which later news may replace.
var _stopped_for := CommandRefusal.Reason.NONE


func _ready() -> void:
	visible = false
	var close: Button = %CloseButton
	close.pressed.connect(close_monitor)
	var follow: Button = %FollowButton
	follow.pressed.connect(_follow)
	var switch: Button = %SwitchButton
	switch.button_down.connect(_on_switch_down)
	switch.pressed.connect(_on_switch_pressed)
	var grid := grid_node()
	grid.gui_input.connect(_on_grid_input)
	set_process(false)


## Read and write through `fleet`; `minimized` answers whether the window is.
func connect_fleet(fleet: HerdrFleet, minimized: Callable) -> void:
	_fleet = fleet
	_minimized = minimized


## Take the pack's panel for the bezel.
func dress(pack: ArtPack) -> void:
	var bezel: HdPanel = %Bezel
	bezel.dress(pack)


func grid_node() -> TerminalMonitorGrid:
	return %Grid


func is_open() -> bool:
	return _mode != Mode.CLOSED


func mode() -> Mode:
	return _mode


## The composite key of the pane the monitor is aimed at; empty when closed.
func pane_key() -> String:
	return "" if _target == null or _mode == Mode.CLOSED else _target.pane_key


## What the monitor is aimed at now (for tests); null when closed.
func target() -> CommandContext:
	return null if _mode == Mode.CLOSED else _target


## The status line's texts, for tests and captures.
func live_text() -> String:
	var mark: Label = %LiveMark
	return mark.text


func message_text() -> String:
	var said: Label = %Message
	return said.text


## What the status says of a clamped grid; empty when herdr's size is drawn whole.
func grid_note() -> String:
	return _grid_note


## Whether the view shows scrollback rather than the live screen.
func scrolled_back() -> bool:
	return _scroll_offset > 0


func reading() -> bool:
	return _read_ticket != null


## Open on `context` (a CommandContext.aimed() target of the pane). One
## monitor at a time: while one is open this does nothing.
func open_monitor(context: CommandContext) -> void:
	if is_open() or context == null:
		return
	_binding += 1
	_target = context
	_pane = null
	_live_text = ""
	_scroll_lines = PackedStringArray()
	_scroll_offset = 0
	_scroll_wanted = false
	_batch.clear()
	_latency_msec = -1
	_message = ""
	_message_detail = ""
	_stopped_for = CommandRefusal.Reason.NONE
	# A read still out from before keeps the next from starting (one at a time).
	_next_read_in = 0.0
	_follow_up_at = -1
	reads_asked = 0
	reads_shown = 0
	_mode = Mode.VIEW_ONLY if _fleet == null or _fleet.read_only() else Mode.ARMING
	var size_now := Vector2i.ZERO if _fleet == null else _fleet.pane_size(context.pane_key)
	var grid := grid_node()
	_set_grid(size_now if size_now.x > 0 and size_now.y > 0 else Vector2i(80, 24))
	grid.show_text("")
	grid.dimmed = false
	_window_focused = _window_has_focus()
	visible = true
	set_process(true)
	grid.grab_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_IME):
		DisplayServer.window_set_ime_active(true)
	_judge()
	_show()


## Close: reads stop at once, a late answer is dropped, and input not yet
## handed to the fleet this frame is not sent.
func close_monitor() -> void:
	if not is_open():
		return
	_mode = Mode.CLOSED
	_binding += 1
	_batch.clear()
	# What is queued is not sent once nobody watches: the request out stays out.
	if _fleet != null and _target != null:
		_fleet.drop_input(_target.pane_key)
	_follow_up_at = -1
	visible = false
	set_process(false)
	var grid := grid_node()
	if grid.has_focus():
		grid.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_IME):
		DisplayServer.window_set_ime_active(false)
	closed.emit()


## The pane as the office's last refresh sees it (null: gone), its machine's
## label (empty with one machine) and whether that machine dropped.
func show_pane(pane: PaneModel, machine_label: String, dimmed: bool) -> void:
	if not is_open():
		return
	_pane = pane
	_machine_label = machine_label
	_dimmed = dimmed
	if _fleet != null and _target != null:
		var cells := _fleet.pane_size(_target.pane_key)
		if cells.x > 0 and cells.y > 0 and _mode != Mode.STOPPED:
			if _set_grid(cells):
				grid_node().show_text(_live_text)
	_judge()
	_show()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true
		if is_open():
			_next_read_in = minf(_next_read_in, READ_FOCUSED)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false


## Draw a `cells` grid, clamped to GRID_MAX; whether the drawn size changed.
func _set_grid(cells: Vector2i) -> bool:
	var drawn := cells.min(GRID_MAX)
	_grid_note = "" if drawn == cells else "%d×%d drawn as %d×%d" % [cells.x, cells.y, drawn.x, drawn.y]
	var grid := grid_node()
	if drawn.x == grid.screen.columns and drawn.y == grid.screen.rows:
		return false
	grid.set_grid(drawn.x, drawn.y)
	return true


## Seconds from one read's start to the next: the poll interval, or four
## times what the last parse and draw cost when that is longer, so a screen
## that is expensive to draw (a dense 400x200 one took about 0.2 s, measured)
## cannot keep the main thread busy between reads.
func next_read_delay() -> float:
	return maxf(read_interval(), COST_FACTOR * grid_node().last_cost_usec() / 1000000.0)


## Seconds between reads now: READ_FOCUSED with the window focused, else READ_UNFOCUSED.
func read_interval() -> float:
	return READ_FOCUSED if _window_focused else READ_UNFOCUSED


func _process(delta: float) -> void:
	_flush()
	# The interval runs from one read's start to the next, so a round trip does
	# not slow the rate down; a read still waits for the one before to end.
	_next_read_in -= delta
	if _read_ticket == null:
		# The echo after input is owed early, but never sooner than the cost allows.
		var since := (Time.get_ticks_msec() - _read_started_msec) / 1000.0
		var affordable := since >= COST_FACTOR * grid_node().last_cost_usec() / 1000000.0
		var owed := _follow_up_at >= 0 and Time.get_ticks_msec() >= _follow_up_at and affordable
		if (_next_read_in <= 0.0 or owed or _scroll_wanted) and _may_read():
			if owed:
				_follow_up_at = -1
			_start_read()
	_show_switch()


# --- reading --------------------------------------------------------------------


func _may_read() -> bool:
	if _fleet == null or _mode == Mode.VIEW_ONLY or _mode == Mode.CLOSED:
		return false
	if _minimized.is_valid() and _minimized.call():
		return false
	return _fleet.screen_refusal(_target) == CommandRefusal.Reason.NONE


func _start_read() -> void:
	var scrollback := _scroll_wanted
	_scroll_wanted = false
	var context := _target.screening(CommandContext.SOURCE_VISIBLE, 0)
	if scrollback:
		context = _target.screening(CommandContext.SOURCE_SCROLLBACK, HerdrCommands.SCROLLBACK_LINES_MAX)
	var ticket := _fleet.read_screen(context)
	reads_asked += 1
	_read_ticket = ticket
	_read_started_msec = Time.get_ticks_msec()
	_next_read_in = next_read_delay()
	ticket.finished.connect(_on_read_finished.bind(ticket, _binding), CONNECT_ONE_SHOT)


func _on_read_finished(ticket: CommandTicket, binding_then: int) -> void:
	if ticket == _read_ticket:
		_read_ticket = null
	# A read for an earlier opening, or for a terminal no longer aimed at, is dropped.
	if binding_then != _binding or not is_open():
		return
	if ticket.state != CommandTicket.State.ACCEPTED or ticket.screen == null:
		_judge()
		# Offline says so itself; a read that failed while online says why.
		if ticket.state != CommandTicket.State.REFUSED and _mode != Mode.OFFLINE and _mode != Mode.STOPPED:
			_say("Read failed: %s" % _failure(ticket), "The screen could not be read: " + _failure(ticket))
		_show()
		return
	if ticket.context.identity_key != _target.identity_key or ticket.context.generation != _target.generation:
		return
	if ticket.context.source == CommandContext.SOURCE_SCROLLBACK:
		# The past is not the terminal as it is: never a look (write-then-look).
		_scroll_lines = ticket.screen.text.split("\n")
		_show_scroll()
		return
	_live_text = ticket.screen.text
	reads_shown += 1
	if _scroll_offset == 0:
		grid_node().show_text(_live_text)
		# Only a screen on view is a look for the write-then-look rule.
		_fleet.preview_shown(ticket)
	if _mode == Mode.ARMING:
		_mode = Mode.LIVE
	_judge()
	_show()


# --- the state ------------------------------------------------------------------


## Where the monitor stands against what the fleet knows now.
func _judge() -> void:
	if _mode == Mode.CLOSED or _mode == Mode.VIEW_ONLY:
		return
	var reason := _fleet.input_refusal(_target)
	match reason:
		CommandRefusal.Reason.NONE:
			if _mode == Mode.OFFLINE:
				# Back with the same connection: live again once a read shows.
				_mode = Mode.ARMING
		CommandRefusal.Reason.IDENTITY_CHANGED, CommandRefusal.Reason.PANE_GONE, CommandRefusal.Reason.IDENTITY_UNKNOWN:
			_stop(reason)
		CommandRefusal.Reason.MACHINE_REPLACED:
			# Re-aimed only from a current snapshot: the one held across the
			# gap still names the old terminal, whatever holds the pane now.
			if _fleet.snapshot_is_current(_target.machine):
				_reaim()
			else:
				_go_offline(reason)
		_:
			_go_offline(reason)
	var grid := grid_node()
	grid.dimmed = _mode == Mode.OFFLINE or _mode == Mode.STOPPED or _dimmed


## The machine is offline, stale or not yet current again: the last screen
## stays, dimmed, and nothing is sent.
func _go_offline(reason: CommandRefusal.Reason) -> void:
	if _mode == Mode.STOPPED or _mode == Mode.OFFLINE:
		return
	_mode = Mode.OFFLINE
	_batch.clear()
	_say(
		"Offline: the last screen, frozen; nothing is sent",
		(
			"No input (%s): the last screen stays, dimmed, until the machine is current and its screen is read again."
			% CommandRefusal.text(reason)
		)
	)


## Input stops: the pane's terminal changed or the pane closed.
func _stop(reason: CommandRefusal.Reason) -> void:
	if _mode == Mode.STOPPED:
		return
	_mode = Mode.STOPPED
	_stopped_for = reason
	_batch.clear()
	if reason == CommandRefusal.Reason.PANE_GONE:
		_say("Pane closed: input stopped", "herdr no longer lists this pane. Close the monitor.")
	else:
		_say(
			"New terminal in this pane: input stopped", "Another terminal has this pane now. Follow it to type into it."
		)


## The machine reconnected or was replaced: aim again, at the same terminal
## only, and let input back in once a read of it is shown.
func _reaim() -> void:
	var fresh := _fleet.context_for(_target.pane_key, _binding)
	if fresh.generation == _target.generation:
		if _mode != Mode.STOPPED:
			_mode = Mode.OFFLINE
		return
	if fresh.wire_pane_id.is_empty():
		_stop(CommandRefusal.Reason.PANE_GONE)
		return
	if fresh.terminal_id != _target.terminal_id:
		_stop(CommandRefusal.Reason.IDENTITY_CHANGED)
		return
	_target = fresh
	_mode = Mode.ARMING


## "Follow new terminal": aim at whatever terminal holds the pane now.
func _follow() -> void:
	if _mode != Mode.STOPPED or _fleet == null:
		return
	var fresh := _fleet.context_for(_target.pane_key, _binding)
	if fresh.wire_pane_id.is_empty():
		return
	_binding += 1
	_target = fresh
	_mode = Mode.ARMING
	_stopped_for = CommandRefusal.Reason.NONE
	_next_read_in = 0.0
	_say("Following the new terminal", "Input comes back once its screen is shown.")
	_judge()
	_show()
	grid_node().grab_focus()


# --- input ----------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	_on_grid_input(event)


## Every key and wheel notch over the monitor. Keys are all taken, sent or not.
func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()
		_on_button(event as InputEventMouseButton)
	elif event is InputEventKey:
		accept_event()
		_on_key(event as InputEventKey)


## A wheel notch scrolls; any other button takes the keyboard back.
func _on_button(button: InputEventMouseButton) -> void:
	if not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll(WHEEL_ROWS)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll(-WHEEL_ROWS)
	else:
		grid_node().grab_focus()


## A key: Ctrl+] closes, the paste chord pastes, everything else goes through
## the key map into this frame's batch, or says why it cannot.
func _on_key(key: InputEventKey) -> void:
	if not key.pressed:
		return
	if key.is_action_pressed(&"monitor_close", true, true):
		close_monitor()
		return
	if _paste_chord(key):
		_paste()
		return
	var mapped := TerminalKeys.of(key, OS.get_name() == "macOS")
	if mapped.kind == TerminalKeys.Kind.NONE:
		return
	_to_live()
	if mapped.kind == TerminalKeys.Kind.REFUSED:
		_say("Not sent: " + CommandRefusal.text(mapped.reason), CommandRefusal.detail(mapped.reason))
		_show()
		return
	if not _input_open():
		_say_closed()
		return
	if mapped.kind == TerminalKeys.Kind.KEY:
		_batch.append([true, mapped.name])
	else:
		_batch.append([false, mapped.text])


## The paste chord of this system: Cmd+V on macOS, Ctrl+Shift+V elsewhere.
static func _paste_chord(key: InputEventKey) -> bool:
	if key.keycode != KEY_V or key.alt_pressed:
		return false
	if OS.get_name() == "macOS":
		return key.meta_pressed and not key.ctrl_pressed and not key.shift_pressed
	return key.ctrl_pressed and key.shift_pressed and not key.meta_pressed


func _input_open() -> bool:
	return _mode == Mode.LIVE and _fleet != null and not _fleet.read_only()


func _say_closed() -> void:
	match _mode:
		Mode.VIEW_ONLY:
			_say("Not sent: read-only", CommandRefusal.detail(CommandRefusal.Reason.READ_ONLY))
		Mode.OFFLINE:
			_say("Not sent: offline", "The machine is offline or not current: input is off until it is back.")
		Mode.STOPPED:
			pass
		_:
			_say("Not sent: waiting for the screen", "Input opens once a read of this terminal is shown.")
	_show()


## The clipboard, through the paste path: refused whole if it holds ESC or is too long.
func _paste() -> void:
	_to_live()
	if not _input_open():
		_say_closed()
		return
	_flush()
	var pasted := ""
	if clipboard.is_valid():
		var handed: Variant = clipboard.call()
		pasted = handed if handed is String else ""
	else:
		pasted = DisplayServer.clipboard_get()
	_submit(_target.pasting(pasted))


## Hand this frame's input to the fleet: one request per run of keys or of text, in order.
func _flush() -> void:
	if _batch.is_empty():
		return
	var batch := _batch.duplicate()
	_batch.clear()
	if not _input_open():
		_say_closed()
		return
	var keys := PackedStringArray()
	var text := ""
	for item: Array in batch:
		var is_key: bool = item[0]
		var value: String = item[1]
		if is_key:
			if not text.is_empty():
				_submit(_target.typing_text(text))
				text = ""
			keys.append(value)
		else:
			if not keys.is_empty():
				_submit(_target.typing_keys(keys))
				keys = PackedStringArray()
			text += value
	if not keys.is_empty():
		_submit(_target.typing_keys(keys))
	if not text.is_empty():
		_submit(_target.typing_text(text))


func _submit(context: CommandContext) -> void:
	var ticket: CommandTicket
	match context.kind:
		CommandContext.Kind.TYPE_KEYS:
			ticket = _fleet.type_keys(context)
		CommandContext.Kind.TYPE_TEXT:
			ticket = _fleet.type_text(context)
		_:
			ticket = _fleet.paste(context)
	_sent_at[ticket] = Time.get_ticks_msec()
	ticket.finished.connect(_on_input_finished.bind(ticket, _binding), CONNECT_ONE_SHOT)
	# The echo: a read at once, and one more a moment later.
	_next_read_in = 0.0
	_follow_up_at = Time.get_ticks_msec() + FOLLOW_UP_MSEC
	if ticket.is_finished():
		_on_input_finished(ticket, _binding)


func _on_input_finished(ticket: CommandTicket, binding_then: int) -> void:
	if not _sent_at.has(ticket):
		return
	var started: int = _sent_at[ticket]
	_sent_at.erase(ticket)
	if binding_then != _binding or not is_open():
		return
	if _mode == Mode.STOPPED:
		# Input queued before the terminal changed is refused at its turn; the
		# stop, and the way out of it, is still what the status line says.
		_show()
		return
	match ticket.state:
		CommandTicket.State.ACCEPTED:
			_latency_msec = Time.get_ticks_msec() - started
		CommandTicket.State.UNKNOWN:
			_say(
				"Unknown result: look at the screen",
				(
					(
						"An input went out but no usable answer came back (%s): herdr may have acted on it."
						% ticket.failure
					)
					+ " Nothing is resent; later keys still go."
				)
			)
		CommandTicket.State.REJECTED:
			_say("herdr refused (%s)" % ticket.error_code, "herdr refused an input: %s" % ticket.error_message)
		CommandTicket.State.REFUSED:
			_say("Not sent: " + CommandRefusal.text(ticket.refusal), CommandRefusal.detail(ticket.refusal))
			_judge()
		CommandTicket.State.CANCELLED:
			_say("Not sent: unreachable", "herdr's socket could not be reached, or the machine went first.")
	_show()


# --- scrollback -----------------------------------------------------------------


## Scroll `rows` up (negative: down) through the recent output; back to the
## live screen at the bottom. The first notch up fetches it.
func _scroll(rows: int) -> void:
	if _mode == Mode.CLOSED or _mode == Mode.VIEW_ONLY:
		return
	if _scroll_offset == 0:
		if rows <= 0:
			return
		# Fetched fresh each time the view leaves the live screen.
		_scroll_lines = PackedStringArray()
		_scroll_wanted = true
		_scroll_offset = rows
		_show()
		return
	_scroll_offset += rows
	if _scroll_offset <= 0:
		_to_live()
		return
	_show_scroll()


## Show the scrollback `_scroll_offset` rows up from its bottom, once it is here.
func _show_scroll() -> void:
	if _scroll_offset == 0 or _scroll_lines.is_empty():
		_show()
		return
	var rows := grid_node().screen.rows
	var most := _scroll_lines.size() - rows
	if most <= 0:
		# Nothing above what the screen already shows.
		_to_live()
		return
	_scroll_offset = clampi(_scroll_offset, 1, most)
	var start := _scroll_lines.size() - rows - _scroll_offset
	grid_node().show_lines(_scroll_lines.slice(start, start + rows))
	_show()


## Back to the live screen.
func _to_live() -> void:
	if _scroll_offset == 0:
		return
	_scroll_offset = 0
	_scroll_wanted = false
	grid_node().show_text(_live_text)
	_show()


# --- the switch -----------------------------------------------------------------


func _on_switch_down() -> void:
	_switch_context = null
	if _fleet == null or _mode == Mode.CLOSED or _mode == Mode.STOPPED:
		return
	# The switch keeps answer mode's whole identity: aimed at who is in the terminal now,
	# and only while it is still the terminal this monitor watches.
	var fresh := _fleet.context_for(_target.pane_key, _binding)
	if fresh.terminal_id == _target.terminal_id and fresh.generation == _target.generation:
		_switch_context = fresh.focusing()


func _on_switch_pressed() -> void:
	var context := _switch_context
	_switch_context = null
	if context == null or context.terminal_id != _target.terminal_id or not is_open():
		return
	var ticket := _fleet.focus_pane(context)
	_switch_ticket = ticket
	ticket.finished.connect(_on_switch_finished.bind(ticket), CONNECT_ONE_SHOT)
	_show_switch()


func _on_switch_finished(ticket: CommandTicket) -> void:
	if ticket == _switch_ticket:
		_switch_ticket = null
	if not is_open():
		return
	match ticket.state:
		CommandTicket.State.ACCEPTED:
			_say(
				"herdr switched here",
				"herdr switched its shared view to this pane, and this table's UNREAD is cleared."
			)
		CommandTicket.State.REJECTED:
			_say("herdr refused (%s)" % ticket.error_code, "herdr refused the switch: " + ticket.error_message)
		CommandTicket.State.REFUSED:
			_say("No switch: " + CommandRefusal.text(ticket.refusal), CommandRefusal.detail(ticket.refusal))
		CommandTicket.State.CANCELLED:
			_say("No switch: unreachable", "herdr's socket could not be reached.")
		_:
			_say("Unknown result: look first", "The switch went out but no usable answer came back.")
	_show()


func _show_switch() -> void:
	var button: Button = %SwitchButton
	var note: Label = %SwitchNote
	var offered := _fleet != null and not _fleet.read_only() and _target != null
	button.visible = offered
	note.visible = offered
	if not offered:
		return
	var reason := _fleet.can_operate(_target.pane_key)
	button.disabled = _switch_ticket != null or _mode == Mode.STOPPED or reason != CommandRefusal.Reason.NONE
	button.text = "Switch herdr here" if _machine_label.is_empty() else "Switch herdr on " + _machine_label
	button.tooltip_text = (
		"Switches the shared view of herdr to this pane: every terminal attached to it follows."
		+ "\nIt also clears UNREAD for every pane on this table, not just this one."
		+ ("" if reason == CommandRefusal.Reason.NONE else "\nOff now: " + CommandRefusal.detail(reason))
	)


# --- showing ----------------------------------------------------------------------


func _say(text: String, detail: String) -> void:
	_message = text
	_message_detail = detail


## Write the title and the status line into their labels.
func _show() -> void:
	if not is_open():
		return
	var title: Label = %Title
	title.text = _title()
	title.tooltip_text = title.text
	var mark: Label = %LiveMark
	var latency: Label = %Latency
	var said: Label = %Message
	var follow: Button = %FollowButton
	match _mode:
		Mode.LIVE:
			mark.text = "● LIVE INPUT"
		Mode.ARMING:
			mark.text = "○ CONNECTING"
		Mode.OFFLINE:
			mark.text = "○ OFFLINE"
		Mode.STOPPED:
			mark.text = "■ INPUT STOPPED"
		_:
			mark.text = "VIEW ONLY"
	mark.tooltip_text = _mark_detail()
	var notes := PackedStringArray()
	if _latency_msec >= 0:
		notes.append("rtt %d ms" % _latency_msec)
	if not _grid_note.is_empty():
		notes.append(_grid_note)
	latency.text = " · ".join(notes)
	var text := _message
	var detail := _message_detail
	if _mode == Mode.VIEW_ONLY:
		text = "Read-only: herdr's screen is not read, no input"
		detail = CommandRefusal.detail(CommandRefusal.Reason.READ_ONLY)
	elif scrolled_back():
		text = "Scrollback: %d rows up · any key returns" % _scroll_offset
	elif text.is_empty():
		text = CURSOR_NOTE
		detail = "herdr 0.9.0 does not report where the cursor is; programs that draw their own still show it."
	said.text = text
	said.tooltip_text = detail
	follow.visible = _mode == Mode.STOPPED and _stopped_for == CommandRefusal.Reason.IDENTITY_CHANGED


func _mark_detail() -> String:
	match _mode:
		Mode.LIVE:
			return "Every key you press goes to this terminal, Esc too. Ctrl+] closes the monitor."
		Mode.ARMING:
			return "Waiting for a read of this terminal before any key is sent."
		Mode.OFFLINE:
			return "The machine is offline or not current: the last screen stays, dimmed; nothing is sent."
		Mode.STOPPED:
			return "The terminal this monitor was aimed at is gone: nothing is sent."
	return "This office was started read-only: it reads nothing from the terminal and sends nothing."


func _title() -> String:
	var parts := PackedStringArray()
	if _pane == null:
		parts.append("Pane gone")
	else:
		parts.append(_pane.provider.to_upper() if not _pane.provider.is_empty() else "SHELL")
		var place := "%s / %s" % [_pane.workspace_label, _pane.tab_label]
		if not _machine_label.is_empty():
			place = _machine_label + " / " + place
		parts.append(place)
		parts.append(_pane.state)
		if _pane.state_since >= 0.0:
			var waited := int(Time.get_unix_time_from_system() - _pane.state_since)
			parts.append(_duration(maxi(0, waited)))
	return " · ".join(parts)


static func _duration(seconds: int) -> String:
	if seconds < 60:
		return "%ds" % seconds
	if seconds < 3600:
		return "%dm" % floori(seconds / 60.0)
	return "%dh %dm" % [floori(seconds / 3600.0), floori((seconds % 3600) / 60.0)]


static func _failure(ticket: CommandTicket) -> String:
	if ticket.state == CommandTicket.State.REJECTED:
		return "herdr refused (%s)" % ticket.error_code
	return ticket.failure if not ticket.failure.is_empty() else CommandTicket.state_name(ticket.state).to_lower()


func _window_has_focus() -> bool:
	if DisplayServer.get_name() == "headless":
		return _window_focused
	return DisplayServer.window_is_focused()
