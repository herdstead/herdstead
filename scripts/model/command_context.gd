class_name CommandContext
extends RefCounted
## One command aimed at one pane, fixed when it is aimed: at the gesture for a
## write, when the card binds a pane for a read. Every later stage checks this
## same object; nothing re-reads "what is selected now" to find a target.
##
## Immutable: HerdrFleet.context_for() fills it in, reading(), focusing(),
## keying(), replying(), screening(), typing_keys(), typing_text(), pasting(),
## starting(), splitting(), closing(), spacing() and branching() return new
## ones with a payload, and every field
## refuses to be written after. It names no herdr method: which method a Kind is
## sent as is HerdrCommands'. It does not judge its payload either: an input
## command's key or line is checked at the send port (HerdrCommands.refusal()).

enum Kind {
	## Only aimed: machine, connection and pane, no payload yet.
	TARGET,
	## Read the pane's terminal text (a read, not a write).
	READ,
	## Switch herdr's shared view to the pane (a write).
	FOCUS,
	## Press one key in the pane's terminal (a write): an approval key, or Esc.
	KEYS,
	## Type one line into the pane's terminal and press Enter (a write).
	LINE,
	## The terminal monitor's read of the pane's screen or recent output, with
	## its colours (a read, not a write).
	SCREEN,
	## The monitor's raw mode: keys pressed while it has the keyboard, in order
	## (a write). Any key of HerdrCommands' raw key map, to any pane.
	TYPE_KEYS,
	## The monitor's raw mode: characters typed, or an input method's commit,
	## sent as they are and never bracketed (a write).
	TYPE_TEXT,
	## The monitor's paste: text herdr brackets when the program asked for it (a write).
	PASTE,
	## Start an agent in the pane's shell (a write): herdr types the kind's
	## command and Enter into that terminal.
	START,
	## Split a new pane beside this one (a write).
	SPLIT,
	## Ask herdr how a start it is launching in the pane stands (a read, never
	## a gesture's: a start's watch asks it once, at its deadline). Bound to the
	## terminal only: the agent may have been recognised meanwhile.
	LAUNCH_CHECK,
	## Close the pane (a write): herdr ends its terminal at once, and with it the
	## tab or the workspace it was the last pane of (CloseScope).
	CLOSE,
	## Make a new workspace whose root shell starts in this pane's directory (a
	## write): a new floor, never focused by this office.
	SPACE,
	## Make a linked worktree of this pane's workspace on a branch (a write): git
	## runs on the machine, and a new floor opens on the checkout.
	WORKTREE,
}

## The two read sources the allowlist knows: what herdr's agent detection
## looks at (a blocked agent's question), and the recent output, unwrapped.
const SOURCE_DETECTION := "detection"
const SOURCE_RECENT := "recent_unwrapped"
## The monitor's two sources: the screen as it is now, and the recent output
## its local scrollback shows.
const SOURCE_VISIBLE := "visible"
const SOURCE_SCROLLBACK := "recent"

var kind: Kind:
	get:
		return _kind
	set(_value):
		_refuse("kind")
## The machine key the fleet knows the machine by.
var machine: String:
	get:
		return _machine
	set(_value):
		_refuse("machine")
## The machine's generation when this was aimed (see HerdrFleet.generation()):
## a replaced, re-enabled or reconnected machine has another one.
var generation: int:
	get:
		return _generation
	set(_value):
		_refuse("generation")
## Machine key and pane id together (HerdrFleet.pane_key).
var pane_key: String:
	get:
		return _pane_key
	set(_value):
		_refuse("pane_key")
## The pane id exactly as herdr spelled it; the one a request carries.
var wire_pane_id: String:
	get:
		return _wire_pane_id
	set(_value):
		_refuse("wire_pane_id")
## The pane id as the office cleaned it; the one the office draws.
var pane_id: String:
	get:
		return _pane_id
	set(_value):
		_refuse("pane_id")
## PaneModel.identity_key() of the pane when this was aimed.
var identity_key: String:
	get:
		return _identity_key
	set(_value):
		_refuse("identity_key")
## herdr's terminal id of the pane when this was aimed: all the monitor's raw
## mode and screen reads are bound to (docs/WRITE_BOUNDARY.md §3). Empty when unknown.
var terminal_id: String:
	get:
		return _terminal_id
	set(_value):
		_refuse("terminal_id")
## The card's binding version when this was aimed; the card drops what finishes
## for another.
var binding: int:
	get:
		return _binding
	set(_value):
		_refuse("binding")
## READ and SCREEN only: which of herdr's read sources.
var source: String:
	get:
		return _source
	set(_value):
		_refuse("source")
## READ and SCREEN only: how many lines to ask for (0: herdr's own default,
## the whole screen, for SCREEN's `visible`).
var lines: int:
	get:
		return _lines
	set(_value):
		_refuse("lines")

## KEYS only: the key's name as herdr spells it (`y`, `1`, `enter`, `esc`).
var key_name: String:
	get:
		return _key_name
	set(_value):
		_refuse("key_name")
## LINE only: the line, exactly as the viewer typed it; never logged or audited.
var line: String:
	get:
		return _line
	set(_value):
		_refuse("line")
## KEYS, LINE and START only: the terminal text the viewer saw when they pressed,
## frozen then. HerdrCommands re-reads the same source and writes only if it
## still reads the same; null refuses the write.
var seen: CommandPreview:
	get:
		return _seen
	set(_value):
		_refuse("seen")
## TYPE_KEYS only: the key names, in the order they were pressed (herdr's
## spelling, `ctrl+c`, `up`, `f5`). A copy: the context keeps its own.
var keys: PackedStringArray:
	get:
		return _keys.duplicate()
	set(_value):
		_refuse("keys")
## TYPE_TEXT and PASTE only: the text, exactly as typed or pasted; never
## logged or audited (the audit keeps its byte count).
var text: String:
	get:
		return _text
	set(_value):
		_refuse("text")
## START only: the agent kind to start, spelled as this machine's snapshot
## spells a detected agent (`claude`), and the name this office made for it
## (`claude-2`).
var agent_kind: String:
	get:
		return _agent_kind
	set(_value):
		_refuse("agent_kind")
var agent_name: String:
	get:
		return _agent_name
	set(_value):
		_refuse("agent_name")
## START only: the viewer confirmed, with a second click, a start after a
## last line that does not end like a prompt (PromptState.Kind.UNSURE). It
## never lets a start go without one (NO_PROMPT).
var confirmed: bool:
	get:
		return _confirmed
	set(_value):
		_refuse("confirmed")
## SPLIT only: where the new pane goes, `right` or `down`.
var direction: String:
	get:
		return _direction
	set(_value):
		_refuse("direction")
## CLOSE only: what closing the pane takes with it, as the snapshot read at
## the gesture gave it (its signature is checked again before the write).
var scope: CloseScope:
	get:
		return _scope
	set(_value):
		_refuse("scope")
## SPACE only: the directory the new workspace's shell starts in, the pane's
## `cwd` exactly as herdr sent it; never logged or audited (its byte count is).
var cwd: String:
	get:
		return _cwd
	set(_value):
		_refuse("cwd")
## WORKTREE only: the pane's workspace, as the office cleaned it and as herdr
## spelled it (the one a request carries), and the branch the viewer typed,
## exactly (the audit keeps it: it is the office's validated word).
var workspace_id: String:
	get:
		return _workspace_id
	set(_value):
		_refuse("workspace_id")
var wire_workspace_id: String:
	get:
		return _wire_workspace_id
	set(_value):
		_refuse("wire_workspace_id")
var branch: String:
	get:
		return _branch
	set(_value):
		_refuse("branch")

var _kind := Kind.TARGET
var _machine := ""
var _generation := -1
var _pane_key := ""
var _wire_pane_id := ""
var _pane_id := ""
var _identity_key := ""
var _terminal_id := ""
var _binding := 0
var _source := ""
var _lines := 0
var _key_name := ""
var _line := ""
var _seen: CommandPreview
var _keys := PackedStringArray()
var _text := ""
var _agent_kind := ""
var _agent_name := ""
var _confirmed := false
var _direction := ""
var _scope: CloseScope
var _cwd := ""
var _workspace_id := ""
var _wire_workspace_id := ""
var _branch := ""


## A context aimed at a pane, without a payload.
static func aimed(
	machine_key: String,
	machine_generation: int,
	key: String,
	wire_id: String,
	cleaned_id: String,
	identity: String,
	binding_version: int,
	terminal := ""
) -> CommandContext:
	var context := CommandContext.new()
	context._machine = machine_key
	context._generation = machine_generation
	context._pane_key = key
	context._wire_pane_id = wire_id
	context._pane_id = cleaned_id
	context._identity_key = identity
	context._binding = binding_version
	context._terminal_id = terminal
	return context


## The same target, to read `wanted_lines` lines of `read_source`.
func reading(read_source: String, wanted_lines: int) -> CommandContext:
	var context := _copy(Kind.READ)
	context._source = read_source
	context._lines = wanted_lines
	return context


## The same target, to switch herdr's view to it.
func focusing() -> CommandContext:
	return _copy(Kind.FOCUS)


## The same target, to press key `key` in its terminal, aimed at the terminal
## text `preview` the viewer saw.
func keying(key: String, preview: CommandPreview) -> CommandContext:
	var context := _copy(Kind.KEYS)
	context._key_name = key
	context._seen = preview
	return context


## The same target, to type `typed_line` and Enter in its terminal, aimed at
## the terminal text `preview` the viewer saw.
func replying(typed_line: String, preview: CommandPreview) -> CommandContext:
	var context := _copy(Kind.LINE)
	context._line = typed_line
	context._seen = preview
	return context


## The same target, for the terminal monitor to read `read_source`
## (SOURCE_VISIBLE or SOURCE_SCROLLBACK) with its colours; `wanted_lines` 0
## leaves the count to herdr.
func screening(read_source: String, wanted_lines: int) -> CommandContext:
	var context := _copy(Kind.SCREEN)
	context._source = read_source
	context._lines = wanted_lines
	return context


## The same target, to press `pressed` (key names, in order) in its terminal:
## the monitor's raw mode.
func typing_keys(pressed: PackedStringArray) -> CommandContext:
	var context := _copy(Kind.TYPE_KEYS)
	context._keys = pressed.duplicate()
	return context


## The same target, to type `typed` into its terminal as it is: the monitor's raw mode.
func typing_text(typed: String) -> CommandContext:
	var context := _copy(Kind.TYPE_TEXT)
	context._text = typed
	return context


## The same target, to paste `pasted` into its terminal: the monitor's paste.
func pasting(pasted: String) -> CommandContext:
	var context := _copy(Kind.PASTE)
	context._text = pasted
	return context


## The same target, to start an agent of kind `start_kind` named `start_name`
## in its shell, aimed at the terminal text `preview` the viewer saw;
## `sure_anyway` when the viewer confirmed a last line that does not read as a
## prompt.
func starting(start_kind: String, start_name: String, preview: CommandPreview, sure_anyway := false) -> CommandContext:
	var context := _copy(Kind.START)
	context._agent_kind = start_kind
	context._agent_name = start_name
	context._seen = preview
	context._confirmed = sure_anyway
	return context


## The same target, to split a new pane beside it, to the `towards` side
## (`right` or `down`).
func splitting(towards: String) -> CommandContext:
	var context := _copy(Kind.SPLIT)
	context._direction = towards
	return context


## The same target, to ask herdr how the start it is launching there stands.
func checking_launch() -> CommandContext:
	return _copy(Kind.LAUNCH_CHECK)


## The same target, to close it, taking `close_scope` (what the snapshot at
## the gesture said the close takes with it) with it.
func closing(close_scope: CloseScope) -> CommandContext:
	var context := _copy(Kind.CLOSE)
	context._scope = close_scope
	return context


## The same target, to make a new workspace whose shell starts in `directory`
## (the pane's cwd, exactly as herdr sent it).
func spacing(directory: String) -> CommandContext:
	var context := _copy(Kind.SPACE)
	context._cwd = directory
	return context


## The same target, to make a linked worktree of its workspace (`space_id` as
## the office cleaned it, `wire_space_id` as herdr spelled it) on `branch_name`.
func branching(space_id: String, wire_space_id: String, branch_name: String) -> CommandContext:
	var context := _copy(Kind.WORKTREE)
	context._workspace_id = space_id
	context._wire_workspace_id = wire_space_id
	context._branch = branch_name
	return context


## Whether this changes herdr: a write is single-flight per pane and never retried.
func is_write() -> bool:
	return (
		_kind == Kind.FOCUS
		or _kind == Kind.KEYS
		or _kind == Kind.LINE
		or _kind == Kind.START
		or _kind == Kind.SPLIT
		or _kind == Kind.CLOSE
		or _kind == Kind.SPACE
		or _kind == Kind.WORKTREE
		or is_raw()
	)


## Whether this is the monitor's raw input (keys, typed text or a paste): no
## key allowlist beyond the raw map, any pane, no re-read, queued in order.
func is_raw() -> bool:
	return _kind == Kind.TYPE_KEYS or _kind == Kind.TYPE_TEXT or _kind == Kind.PASTE


## How many input events a raw input counts for its pane's queue: one per key,
## one per character typed, one for a whole paste; 0 for everything else.
func events() -> int:
	match _kind:
		Kind.TYPE_KEYS:
			return _keys.size()
		Kind.TYPE_TEXT:
			return _text.length()
		Kind.PASTE:
			return 1
	return 0


func _copy(next_kind: Kind) -> CommandContext:
	var context := aimed(
		_machine, _generation, _pane_key, _wire_pane_id, _pane_id, _identity_key, _binding, _terminal_id
	)
	context._kind = next_kind
	return context


func _refuse(field: String) -> void:
	push_error("CommandContext is immutable; %s was not changed" % field)
