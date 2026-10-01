class_name HerdrCommands
extends Node
## The write boundary: the only place that sends herdr anything beyond `ping`,
## `session.snapshot` and `events.subscribe`. Knows no rendering, and is not
## constructed at all in read-only mode (HerdrFleet.start()).
##
## Allowlist: `pane.read` (the card: source `detection` or
## `recent_unwrapped`, format `text`, ANSI stripped, 1 to 200 lines; the
## terminal monitor: source `visible`, or `recent` with 1 to 999 lines, format
## `ansi`, not stripped), `pane.focus`, `pane.send_keys` (answer mode: one key
## of KEY_NAMES; the monitor's raw mode: keys of the raw key map, see
## raw_key_refusal()), `pane.send_input` (the monitor: a paste),
## `pane.send_text` (the monitor: typed text), `agent.prompt` (answer mode:
## one line to an idle or done agent, `target` and `text` only: herdr types it
## and Enter itself), `agent.start` (a shell: `name`, `kind` and `pane_id`
## only, after its recent output was read again and ends at a prompt) and
## `pane.split` (`target_pane_id`, `direction` and `focus: false`, always all
## three, the side the pane's shape gives, never under SPLIT_MIN_COLS columns or
## SPLIT_MIN_ROWS rows a side) and `agent.get` (a read, `target` only: once per
## start this office sent, at its deadline, while the snapshot still shows that
## launch pending; see _check_launches()), `pane.close` (`pane_id` only, after
## the card's two clicks: what the close takes with it, CloseScope, must read
## the same as at the first click), `workspace.create` (`cwd` and `focus:
## false` only: the pane's directory exactly as herdr sent it, absolute) and
## `worktree.create` (`workspace_id`, `branch`, `label` = the branch and
## `focus: false`, always all four, never a `path`, `base` or `cwd`: the branch
## as branch_refusal() lets it through, never rewritten). Anything else is
## refused before a socket is opened, and so is every command refusal() finds a reason against. No file
## under scripts/ but this one names a herdr method outside the three read-only
## ones (tools/test_commands.gd holds that).
##
## Its own transport. A command never goes through HerdrClient's request list,
## where a failed channel takes the machine offline: a command that fails ends
## its own ticket and nothing else. Each request opens its own StreamPeerUDS to
## its machine's socket (herdr answers one request per connection), reads with
## its own line cap and timeout, and is matched to its ticket by request id. A
## write is never retried, and only one write per pane is ever open.
##
## An input command (keys, a line, or a start) is one ticket for two requests, and its
## pane's write slot is taken at the gesture, before either. First the terminal
## source the viewer saw is read again; then, in the frame that re-read comes
## back, every check runs once more against what the fleet knows then, the text
## is compared with the text frozen at the press (CommandPreview), and only if
## nothing stands against it is the write opened and started. herdr has no
## "send if the screen still reads so": this narrows the window between seeing
## and sending to about two round trips, and never closes it
## (docs/WRITE_BOUNDARY.md §1 rule 5). After any write to a pane that was under way ends, whatever the
## outcome (accepted, rejected, unknown, cancelled, or refused after its
## re-read), every write to that pane stays off until the card has shown a
## preview read asked for at least LOOK_DELAY_MSEC after that end (saw()). A
## write refused at the gesture never touched the pane and asks for no look.
##
## Raw mode (the terminal monitor, docs/WRITE_BOUNDARY.md §3, which revises §1
## for this path only). Every key event and paste the monitor takes while it has the
## keyboard is a gesture of its own: no key allowlist beyond the raw map, any
## pane (a shell too) in any state, no re-read, and no look between writes. Its
## writes still come only from gestures and still bind machine, generation,
## pane and terminal (refusal() checks them for every raw input, at the
## gesture and again right before it is written). Raw input and the monitor's
## reads are bound to the pane's terminal id alone, not to the agent or session
## in it: answer mode and the switch keep the whole PaneModel.identity_key().
## So, as in a real terminal, typeahead queued behind a hung request can land in
## a program that took the terminal over meanwhile (a shell command ended and
## an agent started): the viewer typed it against the one before. Accepted by
## design (docs/WRITE_BOUNDARY.md §3, which revises §1 rule 3 for raw mode); new keys after it are gestures
## against what is on screen. They wait in their
## pane's own queue, in order, bounded to RAW_QUEUE_EVENTS events (the newest
## is refused QUEUE_FULL; nothing queued is dropped): one request is open per
## pane, the next starts only when it is over (whatever the outcome: a lost
## answer is UNKNOWN, never resent, and what comes after still goes) and no
## sooner than RAW_INTERVAL_MSEC after the one before (about 60 a second). A
## raw input that cannot be written when its turn comes (machine offline,
## stale, replaced, protocol unknown, pane or terminal changed) is refused with
## that reason, and so is every one queued behind it for that pane. A paste
## holding ESC or a C1 control, or over PASTE_BYTES_MAX, is refused, never cut.
## Answer mode is untouched: a raw write occupies the pane's write
## slot like any write, and the look it owes applies to answer mode's writes (the
## monitor's own screen reads count as looks, saw()).
##
## Audit: every command, refused ones included, gets an entry in one of two
## bounded in-memory rings, writes and reads apart so that reads, which the card
## makes every second or three, never push a write out. No terminal text is
## kept, and no line's text: a line keeps its byte count. Raw input keeps its
## category (keys, text or paste), event count and byte count: never a key's
## name, never a character.

## Emitted when a snapshot of machine `machine` would show what a command just
## did: a start herdr took (a launch shows in snapshots only, and herdr sends no
## event for it until it recognises the agent, measured), or a launch check that
## came back (herdr drops a launch it gave up at that moment). HerdrFleet asks
## that machine's client for a snapshot at once; nothing is written.
signal snapshot_wanted(machine: String)

## Wire protocols this boundary was verified against (herdr 0.9.0).
const PROTOCOLS: Array[int] = [22]
const READ_SOURCES: Array[String] = [CommandContext.SOURCE_DETECTION, CommandContext.SOURCE_RECENT]
const READ_FORMAT := "text"
const READ_LINES_MAX := 200
## The monitor's read: its two sources, its format, and the most lines of
## `recent` it asks for (herdr answers up to 999, about 72 KB, measured).
const SCREEN_SOURCES: Array[String] = [CommandContext.SOURCE_VISIBLE, CommandContext.SOURCE_SCROLLBACK]
const SCREEN_FORMAT := "ansi"
const SCROLLBACK_LINES_MAX := 999
## Raw mode's named keys, as herdr 0.9.0 spells them (measured): alone, and
## the chords raw_key_refusal() builds on them.
const RAW_NAMED: Array[String] = [
	"enter",
	"tab",
	"backspace",
	"esc",
	"space",
	"up",
	"down",
	"left",
	"right",
	"f1",
	"f2",
	"f3",
	"f4",
	"f5",
	"f6",
	"f7",
	"f8",
	"f9",
	"f10",
	"f11",
	"f12",
]
const RAW_ARROWS: Array[String] = ["up", "down", "left", "right"]
const RAW_ARROW_PREFIXES: Array[String] = ["ctrl+", "alt+", "shift+", "ctrl+shift+"]
const RAW_CHORDS: Array[String] = ["shift+tab", "shift+enter", "ctrl+enter", "alt+enter", "ctrl+space"]
## What Ctrl sends a C0 control for besides the letters.
const RAW_CTRL_SYMBOLS := "[\\]^_@"
## Names herdr 0.9.0 has no key for (every spelling is `invalid_key`, measured):
## refused by name with KEY_UNREACHABLE, so the viewer is told why.
const RAW_UNREACHABLE: Array[String] = ["home", "end", "pageup", "pagedown", "insert", "delete"]
## One raw request's text: typed characters, and a paste. Longer is refused, never cut.
const TEXT_BYTES_MAX := 4096
const PASTE_BYTES_MAX := 65536
## Input events a pane's raw queue holds, not counting the request open.
const RAW_QUEUE_EVENTS := 256
## The least time between the starts of two raw requests to one pane: about
## 60 a second.
const RAW_INTERVAL_MSEC := 17
## The only keys pane.send_keys ever carries, compared exactly: herdr itself
## accepts many more (`C-c`, `ctrl+c`, `tab`, arrows, capitals …; measured on
## 0.9.0), so this list is the only guard. `esc` is for the card's named
## "Send Esc" button only.
const KEY_NAMES: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "y", "n", "enter", "esc"]
## A key every probe of a key-carrying command can hold (HerdrFleet.can_operate()).
const LINE_ENTER := "enter"
## The longest line, in UTF-8 bytes: longer is refused, never cut.
const LINE_BYTES_MAX := 1024
## The agent states each input may go to (HerdrSnapshot.Pane.status()).
const ASKING_STATES: Array[String] = ["blocked"]
const REPLY_STATES: Array[String] = ["idle", "done"]
## Longest reply line each method may send, in bytes; a longer one fails its
## command as UNKNOWN (never as an empty result) and nothing else.
const READ_LINE_MAX := 1048576
const FOCUS_LINE_MAX := 4096
const INPUT_LINE_MAX := 4096
## herdr 0.9.0 answers these with at most about 560 bytes (errors 319, measured).
const PROMPT_LINE_MAX := 4096
const START_LINE_MAX := 4096
const SPLIT_LINE_MAX := 4096
## A close answers `{"type":"ok"}` (39 bytes, measured); a space or a worktree
## the new workspace, tab and pane (0.8 to 1.6 KB); a git failure is git's
## stderr, 2.9 KB seen (a usage dump).
const CLOSE_LINE_MAX := 4096
const SPACE_LINE_MAX := 16384
const WORKTREE_LINE_MAX := 16384
## Seconds from queueing to a whole answer. A prompt's answer comes once herdr
## has typed the text and, about 300 ms later, Enter (measured).
const READ_TIMEOUT := 5.0
const FOCUS_TIMEOUT := 5.0
const INPUT_TIMEOUT := 5.0
const START_TIMEOUT := 5.0
const SPLIT_TIMEOUT := 5.0
const CLOSE_TIMEOUT := 5.0
const SPACE_TIMEOUT := 5.0
## herdr runs git before it answers (synchronous; 914 ms cold on a small repo,
## measured; a big one is not): a whole answer, or an unknown result.
const WORKTREE_TIMEOUT := 30.0
## The longest branch name a worktree may be made on, in UTF-8 bytes; the
## characters it may hold, and the shapes git refuses (branch_refusal()).
const BRANCH_BYTES_MAX := 64
const BRANCH_CHARS_PATTERN := "^[A-Za-z0-9._/-]+$"
## A launch check's answer: an agent record, about 520 bytes (measured).
const LAUNCH_CHECK_LINE_MAX := 4096
const LAUNCH_CHECK_TIMEOUT := 5.0
## The least a split may leave on either side, in cells: herdr itself splits
## down to 0x0 (measured).
const SPLIT_MIN_COLS := 40
const SPLIT_MIN_ROWS := 10
## The sides a pane splits to (herdr 0.9.0 has no other).
const SPLIT_DIRECTIONS: Array[String] = ["right", "down"]
## How long a start may stay undetected before its watch says so (LaunchWatch).
const LAUNCH_TIMEOUT_MSEC := LaunchWatch.TIMEOUT_MSEC
## How long after a start ended another start to that pane waits, whatever
## the snapshot says: one snapshot interval (HerdrClient.SNAPSHOT_INTERVAL).
## herdr answers a start before any snapshot shows it: until one does, the
## card must not offer the start again (herdr itself would answer
## agent_pane_busy, measured).
const LAUNCH_GRACE_MSEC := 5000
## Starts remembered for their watch and their names; the oldest goes first.
const LAUNCHES_MAX := 64
## How many `<kind>-<n>` names a start tries before there is no free one.
const NAME_TRIES_MAX := 999
## herdr's own rule for an agent's name (`invalid_agent_name`, measured), and
## this office's for a kind it sends.
const NAME_PATTERN := "^[a-z][a-z0-9_-]{0,31}$"
## How much of the office's own words (a kind, a name) the audit keeps.
const WORD_TEXT_MAX := 40
## After a write to a pane ends, a preview read counts as the look that turns
## its writes back on only if it was asked for this many milliseconds later.
const LOOK_DELAY_MSEC := 500
## The re-read of an input command carries its ticket's request id plus this.
const CHECK_SUFFIX := ":check"
const AUDIT_WRITES := 64
const AUDIT_READS := 64
## Panes whose last write is remembered for LOOK_FIRST; the oldest goes first.
const LOOKS_MAX := 256
## herdr's error text is remote free text; the ticket keeps this much of it.
const ERROR_TEXT_MAX := 200
## How much of a refused key's name the audit keeps.
const KEY_TEXT_MAX := 16

const _METHODS: Dictionary[CommandContext.Kind, String] = {
	CommandContext.Kind.READ: "pane.read",
	CommandContext.Kind.FOCUS: "pane.focus",
	CommandContext.Kind.KEYS: "pane.send_keys",
	CommandContext.Kind.LINE: "agent.prompt",
	CommandContext.Kind.SCREEN: "pane.read",
	CommandContext.Kind.TYPE_KEYS: "pane.send_keys",
	CommandContext.Kind.TYPE_TEXT: "pane.send_text",
	CommandContext.Kind.PASTE: "pane.send_input",
	CommandContext.Kind.START: "agent.start",
	CommandContext.Kind.SPLIT: "pane.split",
	CommandContext.Kind.LAUNCH_CHECK: "agent.get",
	CommandContext.Kind.CLOSE: "pane.close",
	CommandContext.Kind.SPACE: "workspace.create",
	CommandContext.Kind.WORKTREE: "worktree.create",
}

static var _name_rule := RegEx.create_from_string(NAME_PATTERN)
static var _branch_chars := RegEx.create_from_string(BRANCH_CHARS_PATTERN)

## Where the look rule (LOOK_DELAY_MSEC) reads its milliseconds: Time.get_ticks_msec()
## unless a test hands it a Callable returning an int, so that "asked for
## 0.5 s after the write ended" never depends on how fast a machine runs.
## Nothing else here reads it: timeouts count frame time.
var clock := Callable()
## Answers what the fleet knows of machine `key` now (a Machine, or null): a
## start's watch asks it at the deadline, to decide its one launch check.
## Unset (a boundary on its own in a test), no launch check is ever sent.
var machine_facts := Callable()

var _channels: Array[Channel] = []
## Channels opened while _process() walks _channels; it takes them on after.
var _spawned: Array[Channel] = []
## Composite pane key -> the write open for it (single flight).
var _writing: Dictionary[String, CommandTicket] = {}
## Composite pane key -> the last write to that pane, and whether a preview
## has been shown since. Keyed by the pane alone, not its terminal: a write can
## change the pane's agent session (`/clear`), and the look it owes is owed all
## the same.
var _looks: Dictionary[String, Look] = {}
var _next_id := 0
var _writes: Array[CommandAuditEntry] = []
var _reads: Array[CommandAuditEntry] = []
## Composite pane key -> its raw input queue, while it holds anything.
var _lanes: Dictionary[String, Lane] = {}
## Composite pane key -> when its last raw request started (_msec()), kept
## apart from the queue, which empties while a request is still out, and
## forgotten once RAW_INTERVAL_MSEC have passed.
var _paced: Dictionary[String, int] = {}
## pump() is walking _channels: a channel opened now waits in _spawned.
var _pumping := false
## Composite pane key -> the last start sent to that pane (accepted, or its
## answer lost), newest last, at most LAUNCHES_MAX.
var _launches: Dictionary[String, LaunchWatch] = {}


## What HerdrFleet knows of one machine at the moment a command is queued.
class Machine:
	var key := ""
	var generation := -1
	var online := false
	var current := false
	var protocol := 0
	var socket_path := ""
	var snapshot: HerdrSnapshot


## One request on its own connection.
class Channel:
	var ticket: CommandTicket
	var entry: CommandAuditEntry
	var peer: StreamPeerUDS
	var reader: HerdrClient.LineReader
	var payload := PackedByteArray()
	var written := 0
	var left := 0.0
	## The re-read of an input command: its bytes are a read, never the write.
	var check := false
	## The re-read's context (source and lines of the text seen at the press).
	var reading: CommandContext
	## Answers what the fleet knows of the machine now (a Machine, or null).
	var facts := Callable()


## One raw input waiting for its turn.
class Pending:
	var ticket: CommandTicket
	var entry: CommandAuditEntry
	## Answers what the fleet knows of the machine when its turn comes.
	var facts := Callable()


## The side a pane splits to, as its shape gives it, or why it does not split.
class SplitChoice:
	## `right` or `down`; empty when `reason` is not NONE.
	var direction := ""
	var reason := CommandRefusal.Reason.NONE


## One pane's raw input queue, oldest first, and how many events it holds.
class Lane:
	var queue: Array[Pending] = []
	var events := 0


## The last write to one pane.
class Look:
	var ticket: CommandTicket
	var settled_msec := 0
	var looked := false


func _init() -> void:
	name = "Commands"
	set_process(false)


## The methods this boundary may send, for the office's startup line.
static func methods_text() -> String:
	var names := PackedStringArray()
	for kind: CommandContext.Kind in _METHODS:
		if not _METHODS[kind] in names:
			names.append(_METHODS[kind])
	return ", ".join(names)


## Why `context` must not be sent to `machine` (null: the machine is gone), or
## NONE: its payload, its machine and connection, its pane and terminal, and for
## an input command whether that pane may receive it now. Pure; submit(), the
## check after an input command's re-read and HerdrFleet.can_operate() all ask
## it. What the viewer saw (seen_refusal()) and what is open or unlooked for
## the pane (blocker()) are asked apart.
static func refusal(context: CommandContext, machine: Machine) -> CommandRefusal.Reason:
	if context == null:
		return CommandRefusal.Reason.NOT_ALLOWED
	var payload := _payload_refusal(context)
	if payload != CommandRefusal.Reason.NONE:
		return payload
	if machine == null:
		return CommandRefusal.Reason.MACHINE_GONE
	if machine.generation != context.generation:
		return CommandRefusal.Reason.MACHINE_REPLACED
	if not machine.online:
		return CommandRefusal.Reason.MACHINE_OFFLINE
	if not machine.current or machine.snapshot == null:
		return CommandRefusal.Reason.SNAPSHOT_NOT_CURRENT
	if not machine.protocol in PROTOCOLS:
		return CommandRefusal.Reason.UNKNOWN_PROTOCOL
	var snapshot := machine.snapshot
	var index := -1
	var same_id := 0
	for at in snapshot.panes.size():
		if snapshot.panes[at].pane_id == context.pane_id:
			same_id += 1
			if index < 0:
				index = at
	if index < 0:
		return CommandRefusal.Reason.PANE_GONE
	# Two of herdr's ids that clean to the same one, or one listed twice: no
	# request could say which pane it means.
	if same_id > 1 or snapshot.wire_pane_ids.count(context.wire_pane_id) > 1:
		return CommandRefusal.Reason.WIRE_ID_DUPLICATE
	var wire := snapshot.wire_pane_ids[index]
	if wire != context.wire_pane_id or wire != context.pane_id:
		return CommandRefusal.Reason.WIRE_ID_MISMATCH
	var pane := snapshot.panes[index]
	if pane.terminal_id.is_empty():
		return CommandRefusal.Reason.IDENTITY_UNKNOWN
	if context.is_raw() or context.kind in [CommandContext.Kind.SCREEN, CommandContext.Kind.LAUNCH_CHECK]:
		# The monitor watches a live terminal: another agent or session in it
		# (`/clear`, an agent started in a shell) is still the terminal being
		# typed into. Only a new terminal is another target (docs/WRITE_BOUNDARY.md §3).
		if pane.terminal_id != context.terminal_id:
			return CommandRefusal.Reason.IDENTITY_CHANGED
	elif AgentSessionIdentity.runtime_key(pane.terminal_id, pane.agent, pane.agent_session) != context.identity_key:
		return CommandRefusal.Reason.IDENTITY_CHANGED
	if context.kind == CommandContext.Kind.KEYS or context.kind == CommandContext.Kind.LINE:
		return _recipient_refusal(context.kind, pane)
	if context.kind == CommandContext.Kind.START:
		# Only a shell: herdr types the kind's command into it.
		if not pane.agent.is_empty():
			return CommandRefusal.Reason.NOT_A_SHELL
		if pane.launch_pending:
			return CommandRefusal.Reason.AGENT_STARTING
		if not context.agent_kind in kinds_of(snapshot):
			return CommandRefusal.Reason.KIND_UNKNOWN
		if context.agent_name in names_of(snapshot):
			return CommandRefusal.Reason.NAME_TAKEN
	if context.kind == CommandContext.Kind.SPLIT:
		var choice := split_choice(snapshot, context.pane_id)
		if choice.reason != CommandRefusal.Reason.NONE:
			return choice.reason
		# The side chosen at the gesture must still be the one the shape gives.
		if choice.direction != context.direction:
			return CommandRefusal.Reason.DIRECTION_INVALID
	if context.kind == CommandContext.Kind.CLOSE:
		# What the close takes with it, read again now: the parent of an open
		# worktree group is never closed from here; anything else that changed
		# since the first click (a pane joined the tab, the agent's state moved)
		# is another close than the one confirmed.
		var now := CloseScope.of(snapshot, context.pane_id)
		if now.group_parent:
			return CommandRefusal.Reason.GROUP_PARENT
		if context.scope == null or now.signature() != context.scope.signature():
			return CommandRefusal.Reason.SCOPE_CHANGED
	if context.kind == CommandContext.Kind.SPACE:
		# The directory goes back to herdr as it came: a shell that moved since
		# the press would start the new space somewhere else than shown.
		if not pane.cwd_clean:
			return CommandRefusal.Reason.CWD_UNCLEAN
		if pane.cwd != context.cwd:
			return CommandRefusal.Reason.CWD_CHANGED
	if context.kind == CommandContext.Kind.WORKTREE:
		return _source_refusal(context, snapshot, pane)
	return CommandRefusal.Reason.NONE


## refusal()'s part for a worktree: the pane still stands in the workspace
## aimed at, that workspace is listed once, spelled by herdr as the office
## reads it, and is not itself a linked worktree (herdr answers
## linked_worktree_source; measured).
static func _source_refusal(
	context: CommandContext, snapshot: HerdrSnapshot, pane: HerdrSnapshot.Pane
) -> CommandRefusal.Reason:
	if pane.workspace_id != context.workspace_id:
		return CommandRefusal.Reason.FLOOR_CHANGED
	var index := -1
	var same_id := 0
	for at in snapshot.workspaces.size():
		if snapshot.workspaces[at].workspace_id == context.workspace_id:
			same_id += 1
			if index < 0:
				index = at
	if index < 0:
		return CommandRefusal.Reason.FLOOR_GONE
	if same_id > 1 or snapshot.wire_workspace_ids.count(context.wire_workspace_id) > 1:
		return CommandRefusal.Reason.WIRE_ID_DUPLICATE
	var wire := snapshot.wire_workspace_ids[index]
	if wire != context.wire_workspace_id or wire != context.workspace_id:
		return CommandRefusal.Reason.WIRE_ID_MISMATCH
	var tree := snapshot.workspaces[index].worktree
	if tree != null and tree.is_linked_worktree:
		return CommandRefusal.Reason.MEZZANINE_SOURCE
	return CommandRefusal.Reason.NONE


## Why `text` cannot be the branch of a new worktree, or NONE. Pure; refuses,
## never rewrites: empty or holding whitespace anywhere (BRANCH_BLANK, no
## trimming), over BRANCH_BYTES_MAX bytes (BRANCH_TOO_LONG), a character
## outside `[A-Za-z0-9._/-]` (BRANCH_CHARS), or a shape git refuses
## (BRANCH_SHAPE: a first character that is not a letter or digit, `..`,
## `//`, a segment starting with `.` or ending in `.lock`, ending in `/` or
## `.`, `HEAD`, or `refs/…`; `@` is outside the character set already). herdr
## checks nothing but emptiness and
## takes `refs/heads/x`, `@` and a direction override (measured); git's own
## refusal comes back as free text.
static func branch_refusal(text: String) -> CommandRefusal.Reason:
	if text.is_empty():
		return CommandRefusal.Reason.BRANCH_BLANK
	for index in text.length():
		var code := text.unicode_at(index)
		if _control(code) or _blank(code) or _invisible(code):
			return CommandRefusal.Reason.BRANCH_BLANK
	if text.length() > BRANCH_BYTES_MAX or text.to_utf8_buffer().size() > BRANCH_BYTES_MAX:
		return CommandRefusal.Reason.BRANCH_TOO_LONG
	var chars := _branch_chars.search(text)
	if chars == null or chars.get_string() != text:
		return CommandRefusal.Reason.BRANCH_CHARS
	var first := text.unicode_at(0)
	var digit := first >= 0x30 and first <= 0x39
	var letter := (first >= 0x41 and first <= 0x5A) or (first >= 0x61 and first <= 0x7A)
	if not digit and not letter:
		return CommandRefusal.Reason.BRANCH_SHAPE
	if text.contains("..") or text.contains("//") or text.ends_with("/") or text.ends_with("."):
		return CommandRefusal.Reason.BRANCH_SHAPE
	if text == "HEAD" or text.begins_with("refs/"):
		return CommandRefusal.Reason.BRANCH_SHAPE
	for segment in text.split("/"):
		if segment.begins_with(".") or segment.ends_with(".lock"):
			return CommandRefusal.Reason.BRANCH_SHAPE
	return CommandRefusal.Reason.NONE


## Why `directory` cannot be where a new space starts, or NONE: empty or not
## absolute (CWD_UNKNOWN: herdr lands any bad directory in $HOME, silently,
## measured), or spelled with characters the office does not show
## (CWD_UNCLEAN: cleaning or bounding would change it). Pure; the snapshot's
## own flag (Pane.cwd_clean) is checked at refusal() besides.
static func cwd_refusal(directory: String) -> CommandRefusal.Reason:
	if directory.is_empty() or not directory.begins_with("/"):
		return CommandRefusal.Reason.CWD_UNKNOWN
	if directory != TerminalText.bound(MachineRoster.clean_text(directory)):
		return CommandRefusal.Reason.CWD_UNCLEAN
	return CommandRefusal.Reason.NONE


## Why the terminal text an input command was aimed at cannot be its basis, or
## NONE: none was frozen, it belongs to another pane, terminal or card binding,
## it was cut, or it comes from another source than the input needs (answer
## keys: the whole `detection` text, READ_LINES_MAX lines; a line or a start:
## the recent output). A start also needs that text to end at a prompt
## (prompt_refusal()). Pure. NONE for every other kind.
static func seen_refusal(context: CommandContext) -> CommandRefusal.Reason:
	if context == null:
		return CommandRefusal.Reason.NOT_ALLOWED
	if not context.kind in [CommandContext.Kind.KEYS, CommandContext.Kind.LINE, CommandContext.Kind.START]:
		return CommandRefusal.Reason.NONE
	var seen := context.seen
	if seen == null or seen.cut:
		return CommandRefusal.Reason.UNSEEN
	if seen.pane_key != context.pane_key or seen.identity_key != context.identity_key:
		return CommandRefusal.Reason.UNSEEN
	if seen.binding != context.binding:
		return CommandRefusal.Reason.UNSEEN
	if context.kind == CommandContext.Kind.KEYS:
		if seen.source != CommandContext.SOURCE_DETECTION or seen.lines != READ_LINES_MAX:
			return CommandRefusal.Reason.UNSEEN
	elif seen.source != CommandContext.SOURCE_RECENT or seen.lines < 1 or seen.lines > READ_LINES_MAX:
		return CommandRefusal.Reason.UNSEEN
	if context.kind == CommandContext.Kind.START:
		return prompt_refusal(PromptState.of(seen), context.confirmed)
	return CommandRefusal.Reason.NONE


## Why a start cannot go after terminal text that ends as `state` says, or
## NONE: after a prompt (PLAIN); after a last line that ends otherwise
## (UNSURE) only once the viewer confirmed it (`confirmed`); never after
## nothing whole to look at (NO_PROMPT), confirmed or not.
static func prompt_refusal(state: PromptState, confirmed := false) -> CommandRefusal.Reason:
	if state == null or state.kind == PromptState.Kind.NO_PROMPT:
		return CommandRefusal.Reason.NO_PROMPT
	if state.kind == PromptState.Kind.UNSURE and not confirmed:
		return CommandRefusal.Reason.PROMPT_UNSURE
	return CommandRefusal.Reason.NONE


## What `text` (a whole recent output) ends in, for a start (PromptState.of_text()).
static func prompt_state(text: String) -> PromptState:
	return PromptState.of_text(text)


## Why `kind` cannot be the kind of a start, or NONE: it must be spelled as
## NAME_PATTERN says (herdr takes any case; this office sends the snapshot's
## lowercase spelling only).
static func kind_refusal(kind: String) -> CommandRefusal.Reason:
	return CommandRefusal.Reason.NONE if _named_so(kind) else CommandRefusal.Reason.KIND_INVALID


## Why `agent_name` cannot name a started agent, or NONE (NAME_PATTERN, herdr's own rule).
static func name_refusal(agent_name: String) -> CommandRefusal.Reason:
	return CommandRefusal.Reason.NONE if _named_so(agent_name) else CommandRefusal.Reason.NAME_INVALID


## Every agent kind `snapshot` shows detected, once each, sorted, and only
## those kind_refusal() lets through: the kinds a start may name there.
static func kinds_of(snapshot: HerdrSnapshot) -> PackedStringArray:
	var kinds := PackedStringArray()
	if snapshot == null:
		return kinds
	for pane in snapshot.panes:
		if (
			not pane.agent.is_empty()
			and not pane.agent in kinds
			and kind_refusal(pane.agent) == CommandRefusal.Reason.NONE
		):
			kinds.append(pane.agent)
	kinds.sort()
	return kinds


## Every agent name `snapshot` shows (herdr's `name` of an agent record that
## describes its pane), launching ones included: a start must not reuse one.
static func names_of(snapshot: HerdrSnapshot) -> PackedStringArray:
	var names := PackedStringArray()
	if snapshot == null:
		return names
	for pane in snapshot.panes:
		if not pane.agent_name.is_empty() and not pane.agent_name in names:
			names.append(pane.agent_name)
	return names


## The side pane `pane_id` (the office's cleaned id) of `snapshot` splits to,
## by its terminal rect in herdr's layout: right when it is at least twice as
## wide as it is high, else down, and the other side when that one would leave
## under SPLIT_MIN_COLS columns or SPLIT_MIN_ROWS rows and the other would not.
## PANE_TOO_SMALL when neither side fits, SIZE_UNKNOWN when the layout gives
## the pane no size.
static func split_choice(snapshot: HerdrSnapshot, pane_id: String) -> SplitChoice:
	var choice := SplitChoice.new()
	var width := 0
	var height := 0
	if snapshot != null:
		for layout in snapshot.layouts:
			for slot in layout.panes:
				if slot.pane_id == pane_id and width == 0:
					width = slot.width
					height = slot.height
	if width <= 0 or height <= 0:
		choice.reason = CommandRefusal.Reason.SIZE_UNKNOWN
		return choice
	# Each half keeps floor(side / 2) cells: at least the minimum when the
	# side is twice it.
	var right := width >= 2 * SPLIT_MIN_COLS
	var down := height >= 2 * SPLIT_MIN_ROWS
	var wide := width >= 2 * height
	if (wide and right) or (not down and right):
		choice.direction = "right"
	elif down:
		choice.direction = "down"
	else:
		choice.reason = CommandRefusal.Reason.PANE_TOO_SMALL
	return choice


## Why `key_name` cannot be pressed in raw mode, or NONE: it must be one of
## the table measured against herdr 0.9.0, spelled exactly as herdr does (lowercase, `+` between):
## a printable ASCII character, a named key (RAW_NAMED), an arrow with Ctrl,
## Alt, Shift or Ctrl+Shift, `ctrl+` a letter or one of `[ \ ] ^ _ @`,
## `ctrl+alt+` a letter, `alt+` a printable character but a capital,
## `alt+shift+` a letter, or one of RAW_CHORDS. herdr takes far more
## (measured): this is the guard.
static func raw_key_refusal(key_name: String) -> CommandRefusal.Reason:
	if key_name in RAW_UNREACHABLE:
		return CommandRefusal.Reason.KEY_UNREACHABLE
	if key_name.length() == 1:
		return CommandRefusal.Reason.NONE if _printable(key_name) else CommandRefusal.Reason.KEY_UNSUPPORTED
	if key_name in RAW_NAMED or key_name in RAW_CHORDS:
		return CommandRefusal.Reason.NONE
	for prefix in RAW_ARROW_PREFIXES:
		if key_name.begins_with(prefix) and key_name.trim_prefix(prefix) in RAW_ARROWS:
			return CommandRefusal.Reason.NONE
	for prefix: String in ["ctrl+alt+", "alt+shift+"]:
		if key_name.begins_with(prefix):
			return (
				CommandRefusal.Reason.NONE
				if _letter(key_name.trim_prefix(prefix))
				else CommandRefusal.Reason.KEY_UNSUPPORTED
			)
	if key_name.begins_with("ctrl+"):
		var held := key_name.trim_prefix("ctrl+")
		var control := _letter(held) or (held.length() == 1 and RAW_CTRL_SYMBOLS.contains(held))
		return CommandRefusal.Reason.NONE if control else CommandRefusal.Reason.KEY_UNSUPPORTED
	if key_name.begins_with("alt+"):
		var meta := key_name.trim_prefix("alt+")
		var sendable := meta.length() == 1 and _printable(meta) and not (meta >= "A" and meta <= "Z")
		return CommandRefusal.Reason.NONE if sendable else CommandRefusal.Reason.KEY_UNSUPPORTED
	return CommandRefusal.Reason.KEY_UNSUPPORTED


## Why `typed` cannot be typed into a terminal in raw mode, or NONE: empty,
## over TEXT_BYTES_MAX bytes, or holding a control character (C0, DEL, C1:
## those keys are sent by name) or a broken one. Never rewritten.
static func text_refusal(typed: String) -> CommandRefusal.Reason:
	if typed.is_empty():
		return CommandRefusal.Reason.INPUT_EMPTY
	if typed.length() > TEXT_BYTES_MAX:
		return CommandRefusal.Reason.TEXT_TOO_LONG
	for index in typed.length():
		var code := typed.unicode_at(index)
		if _broken(code):
			return CommandRefusal.Reason.TEXT_BROKEN
		if code < 0x20 or (code >= 0x7F and code <= 0x9F):
			return CommandRefusal.Reason.TEXT_CONTROL
	if typed.to_utf8_buffer().size() > TEXT_BYTES_MAX:
		return CommandRefusal.Reason.TEXT_TOO_LONG
	return CommandRefusal.Reason.NONE


## Why `pasted` cannot be pasted, or NONE: empty, over PASTE_BYTES_MAX bytes,
## holding ESC or a C1 control (either can end herdr's bracketed paste early,
## and what follows would arrive as typed input), a broken character, another
## control a terminal acts on without bracketed paste (the one-line reply's _control() set but
## tab, newline and carriage return: Ctrl-C, Ctrl-U, Ctrl-Z, DEL, U+2028,
## U+2029 …), or a direction control (_direction(), the bidi part of the one-line reply's
## _invisible() set: what the viewer sees would not be what the shell reads).
## Zero-width joiners stay: emoji need them. Refused whole, never cut or
## rewritten. Newlines and tabs are pasted as they are.
static func paste_refusal(pasted: String) -> CommandRefusal.Reason:
	if pasted.is_empty():
		return CommandRefusal.Reason.INPUT_EMPTY
	if pasted.length() > PASTE_BYTES_MAX:
		return CommandRefusal.Reason.PASTE_TOO_LONG
	for index in pasted.length():
		var code := pasted.unicode_at(index)
		if code == 0x1B or (code >= 0x80 and code <= 0x9F):
			return CommandRefusal.Reason.PASTE_ESCAPE
		if _broken(code):
			return CommandRefusal.Reason.TEXT_BROKEN
		# The one-line reply's set (_control) but the three a paste is made of.
		if _control(code) and code != 0x09 and code != 0x0A and code != 0x0D:
			return CommandRefusal.Reason.PASTE_CONTROL
		if _direction(code):
			return CommandRefusal.Reason.PASTE_INVISIBLE
	if pasted.to_utf8_buffer().size() > PASTE_BYTES_MAX:
		return CommandRefusal.Reason.PASTE_TOO_LONG
	return CommandRefusal.Reason.NONE


## Why `text` cannot be sent as one line, or NONE. Nothing is ever rewritten to
## make it pass: a line is sent exactly as typed, or not at all.
static func line_refusal(text: String) -> CommandRefusal.Reason:
	# Every character is at least one byte: a longer string is over at once,
	# however much of it there is.
	if text.length() > LINE_BYTES_MAX:
		return CommandRefusal.Reason.LINE_TOO_LONG
	var blank := true
	for index in text.length():
		var code := text.unicode_at(index)
		if _broken(code):
			return CommandRefusal.Reason.LINE_BROKEN
		if _control(code):
			return CommandRefusal.Reason.LINE_CONTROL
		if _invisible(code):
			return CommandRefusal.Reason.LINE_INVISIBLE
		if not _blank(code):
			blank = false
	if text.to_utf8_buffer().size() > LINE_BYTES_MAX:
		return CommandRefusal.Reason.LINE_TOO_LONG
	if blank:
		return CommandRefusal.Reason.LINE_BLANK
	return CommandRefusal.Reason.NONE


## Whether a write to `pane_key` is still open, or raw input to it still waits.
func writing(pane_key: String) -> bool:
	return _writing.has(pane_key) or _lanes.has(pane_key)


## Raw input events waiting in `pane_key`'s queue, not counting the request open.
func queued_events(pane_key: String) -> int:
	var lane: Lane = _lanes.get(pane_key)
	return 0 if lane == null else lane.events


## Whether the last write to pane `pane_key` ended and no preview read asked
## for LOOK_DELAY_MSEC after that has been shown yet. Whatever terminal, agent
## or session holds the pane now: the write may be what changed them.
func must_look(pane_key: String) -> bool:
	var look: Look = _looks.get(pane_key)
	return look != null and not look.looked


## The last write to pane `pane_key`, final; null when there was none this run
## (or it was forgotten, LOOKS_MAX panes ago).
func last_write(pane_key: String) -> CommandTicket:
	var look: Look = _looks.get(pane_key)
	return null if look == null else look.ticket


## The last start sent to pane `pane_key` (accepted, or its answer lost); null
## when there was none this run (or it was forgotten, LAUNCHES_MAX starts ago).
func launch_of(pane_key: String) -> LaunchWatch:
	return _launches.get(pane_key)


## The names of every start this run sent to machine `machine` and still
## remembers: herdr may hold each of them, a lost answer's too. Not a start
## herdr gave up at the deadline (LaunchWatch.failed()): it freed that name.
func launch_names(machine: String) -> PackedStringArray:
	var names := PackedStringArray()
	for watch: LaunchWatch in _launches.values():
		if watch.machine == machine and not watch.failed() and not watch.name in names:
			names.append(watch.name)
	return names


## What stands against any write to `context`'s pane right now: one still
## open (IN_FLIGHT), or one that ended with no look since (LOOK_FIRST); for a
## start, also a start to that pane that ended less than LAUNCH_GRACE_MSEC ago
## (AGENT_STARTING: the snapshot may not show it yet), or a name a start this run already sent to its machine (NAME_TAKEN:
## herdr may hold it while no snapshot shows it; not one herdr gave up). NONE for
## a read, and for raw input, which waits its turn in its pane's queue and owes
## no look (docs/WRITE_BOUNDARY.md §3 revises §1 rule 5 for it): only a full queue stands
## against it (QUEUE_FULL).
func blocker(context: CommandContext) -> CommandRefusal.Reason:
	if context == null or not context.is_write():
		return CommandRefusal.Reason.NONE
	if context.is_raw():
		var over := queued_events(context.pane_key) + context.events() > RAW_QUEUE_EVENTS
		return CommandRefusal.Reason.QUEUE_FULL if over else CommandRefusal.Reason.NONE
	if writing(context.pane_key):
		return CommandRefusal.Reason.IN_FLIGHT
	if must_look(context.pane_key):
		return CommandRefusal.Reason.LOOK_FIRST
	if context.kind == CommandContext.Kind.START:
		return _launch_blocker(context)
	return CommandRefusal.Reason.NONE


## blocker()'s part for a start: one to its pane that ended less than
## LAUNCH_GRACE_MSEC ago, or a name this run already sent to its machine
## (launch_names(): not one herdr gave up).
func _launch_blocker(context: CommandContext) -> CommandRefusal.Reason:
	var watch: LaunchWatch = _launches.get(context.pane_key)
	if watch != null and _msec() - watch.ended_msec < LAUNCH_GRACE_MSEC:
		return CommandRefusal.Reason.AGENT_STARTING
	if context.agent_name in launch_names(context.machine):
		return CommandRefusal.Reason.NAME_TAKEN
	return CommandRefusal.Reason.NONE


## The agent card or the terminal monitor showed what `ticket` (an accepted
## READ or SCREEN) brought back. If it
## was asked for LOOK_DELAY_MSEC or more after the last write to its pane
## ended, that write has been looked at: writes to the pane are on again.
## Anything else changes nothing; a read of whatever terminal holds the pane
## counts, and nothing earlier does.
func saw(ticket: CommandTicket) -> void:
	if ticket == null or ticket.context == null:
		return
	if ticket.context.kind != CommandContext.Kind.READ and ticket.context.kind != CommandContext.Kind.SCREEN:
		return
	if ticket.state != CommandTicket.State.ACCEPTED:
		return
	var look: Look = _looks.get(ticket.context.pane_key)
	if look != null and ticket.queued_msec >= look.settled_msec + LOOK_DELAY_MSEC:
		look.looked = true


## Refuse `context`, or queue it for `machine` (what the fleet knows of its
## machine now; null when that machine is gone). A refused ticket comes back
## already settled. A queued read, focus or split is written on the next frame,
## with nothing looking at the snapshot again in between. An input command
## (KEYS, LINE, START) takes its pane's write slot now, then re-reads the text its viewer saw;
## `facts` answers what the fleet knows of the machine when that re-read comes
## back (a Machine, or null), and without it the write is refused then. The
## re-read narrows the window between seeing and sending; it never closes it.
func submit(context: CommandContext, machine: Machine, facts := Callable()) -> CommandTicket:
	var ticket := CommandTicket.new(context)
	_next_id += 1
	ticket.request_id = "herdstead-%d" % _next_id
	ticket.queued_msec = _msec()
	var entry := _audit(ticket, machine)
	var reason := refusal(context, machine)
	if reason == CommandRefusal.Reason.NONE:
		reason = seen_refusal(context)
	if reason == CommandRefusal.Reason.NONE:
		reason = blocker(context)
	if reason != CommandRefusal.Reason.NONE:
		ticket.refuse(reason)
		entry.refusal = CommandRefusal.name_of(reason)
		# Refused at the gesture: nothing was under way, nothing to look at.
		_record(ticket, entry, false)
		return ticket
	if context.is_raw():
		_enqueue(ticket, entry, facts)
		return ticket
	var input := context.kind in [CommandContext.Kind.KEYS, CommandContext.Kind.LINE, CommandContext.Kind.START]
	if context.is_write():
		# The slot is taken at the gesture: a second press inside the re-read
		# window finds it taken, whatever it asks for.
		_writing[context.pane_key] = ticket
	var peer := HerdrClient.open_peer(machine.socket_path)
	if peer == null:
		ticket.settle(CommandTicket.State.CANCELLED, "herdr's socket is not there")
		_record(ticket, entry)
		return ticket
	entry.record(CommandTicket.state_name(CommandTicket.State.UNSENT), _now())
	var channel := Channel.new()
	channel.ticket = ticket
	channel.entry = entry
	channel.peer = peer
	if input:
		channel.check = true
		channel.facts = facts
		channel.reading = context.reading(context.seen.source, context.seen.lines)
		channel.reader = HerdrClient.LineReader.new(READ_LINE_MAX)
		channel.left = READ_TIMEOUT
		channel.payload = HerdrClient.request_line(
			ticket.request_id + CHECK_SUFFIX, _METHODS[CommandContext.Kind.READ], _params(channel.reading)
		)
	else:
		channel.reader = HerdrClient.LineReader.new(_line_max(context.kind))
		channel.left = _timeout(context.kind)
		channel.payload = HerdrClient.request_line(ticket.request_id, _METHODS[context.kind], _params(context))
	_open(channel)
	return ticket


## Settle every open command of machine `key`, which closed, dropped or was
## replaced: UNKNOWN once a byte of its write went out, CANCELLED before (an
## input command still re-reading has written nothing). Nothing is ever left
## SENT. Raw input still queued for its panes is refused for `why`
## (MACHINE_OFFLINE when it dropped, MACHINE_REPLACED or MACHINE_GONE when it
## was closed), and none of it is kept for a reconnect.
func settle_machine(key: String, why := CommandRefusal.Reason.MACHINE_OFFLINE) -> void:
	var kept: Array[Channel] = []
	for channel in _channels:
		if channel.ticket.context.machine == key:
			_end(channel, "its machine went away", true)
		else:
			kept.append(channel)
	_channels = kept
	for pane_key: String in _lanes.keys():
		var lane: Lane = _lanes[pane_key]
		if not lane.queue.is_empty() and lane.queue[0].ticket.context.machine == key:
			_refuse_lane(pane_key, why)


## Requests queued or on the wire right now.
func open_count() -> int:
	return _channels.size()


## This run's writes, oldest first, at most AUDIT_WRITES.
func write_log() -> Array[CommandAuditEntry]:
	return _writes.duplicate()


## This run's reads, oldest first, at most AUDIT_READS. No terminal text.
func read_log() -> Array[CommandAuditEntry]:
	return _reads.duplicate()


func _process(delta: float) -> void:
	pump(delta)


## Move every open request along by `delta` seconds: what _process() does each
## frame. Public so that a test can drive a boundary outside the tree on its
## own clock, the way tools/client_test_base.gd drives a client.
func pump(delta: float) -> void:
	_pumping = true
	var kept: Array[Channel] = []
	for channel in _channels:
		if _pump(channel, delta):
			kept.append(channel)
	_pumping = false
	kept.append_array(_spawned)
	_spawned.clear()
	_channels = kept
	# Raw input whose turn came, now that the request before it may be over.
	_drain()
	_check_launches()
	if _channels.is_empty() and _lanes.is_empty() and not _awaiting_deadline():
		set_process(false)


## Every start whose deadline (LAUNCH_TIMEOUT_MSEC from when it was asked for)
## passed with its launch check undecided, once its machine is online with a
## current snapshot: when that snapshot still shows the launch pending in the
## same terminal under the same name, ONE read asks herdr how it stands (and
## herdr, asked, gives up a launch its own timeout ran out on); otherwise none
## is needed. A machine gone, or replaced (another generation), is not asked:
## the start reads NOT_CHECKED. Decided once per start, whatever the answer: never asked again,
## and no write ever follows from it. A launch this office did not start is
## never asked about.
func _check_launches() -> void:
	if not machine_facts.is_valid():
		return
	var now := _msec()
	for watch: LaunchWatch in _launches.values():
		if watch.decided or now - watch.started_msec < LAUNCH_TIMEOUT_MSEC:
			continue
		var known: Variant = machine_facts.call(watch.machine)
		var machine: Machine = known if known is Machine else null
		if machine == null or machine.generation != watch.ticket.context.generation:
			# Gone, or another connection by now: nothing to ask it about.
			watch.decided = true
			watch.unchecked = true
			continue
		if not machine.online or not machine.current or machine.snapshot == null:
			continue
		watch.decided = true
		if _still_launching(machine.snapshot, watch):
			watch.check = submit(watch.ticket.context.checking_launch(), machine)


## Whether `snapshot` shows `watch`'s launch still pending: its pane, its
## terminal, its name, launch_pending.
static func _still_launching(snapshot: HerdrSnapshot, watch: LaunchWatch) -> bool:
	var pane_id := watch.ticket.context.pane_id
	for pane in snapshot.panes:
		if pane.pane_id == pane_id:
			return pane.launch_pending and pane.terminal_id == watch.terminal_id and pane.agent_name == watch.name
	return false


## Whether a start's deadline is still to come (or its machine to be seen):
## the boundary keeps pumping for it.
func _awaiting_deadline() -> bool:
	if not machine_facts.is_valid():
		return false
	for watch: LaunchWatch in _launches.values():
		if not watch.decided:
			return true
	return false


func _exit_tree() -> void:
	# A boundary leaving the tree takes its connections with it, and its queues.
	for channel in _channels:
		_end(channel, "the office closed", true)
	_channels.clear()
	for pane_key: String in _lanes.keys():
		var lane: Lane = _lanes[pane_key]
		for pending in lane.queue:
			pending.ticket.settle(CommandTicket.State.CANCELLED, "the office closed")
			_record(pending.ticket, pending.entry, false)
	_lanes.clear()


# --- transport ------------------------------------------------------------------


## Start moving `channel` along: on the next pump, or at the end of this one
## when pump() is running now.
func _open(channel: Channel) -> void:
	if _pumping:
		_spawned.append(channel)
	else:
		_channels.append(channel)
	set_process(true)


## Queue raw input `ticket` (already checked at its gesture) behind whatever its
## pane already has, and send it now if its turn has come.
func _enqueue(ticket: CommandTicket, entry: CommandAuditEntry, facts: Callable) -> void:
	var key := ticket.context.pane_key
	var lane: Lane = _lanes.get(key)
	if lane == null:
		lane = Lane.new()
		_lanes[key] = lane
	var pending := Pending.new()
	pending.ticket = ticket
	pending.entry = entry
	pending.facts = facts
	lane.queue.append(pending)
	lane.events += ticket.context.events()
	entry.record(CommandTicket.state_name(CommandTicket.State.UNSENT), _now())
	set_process(true)
	_drain()


## Start the head of every pane's raw queue whose turn has come: nothing of
## that pane is open, and RAW_INTERVAL_MSEC have passed since its last start.
## Every one of them was a gesture when it was queued; this only keeps them in
## order and paced. Nothing here makes a write up.
func _drain() -> void:
	var now := _msec()
	for key: String in _paced.keys():
		if now - _paced[key] >= RAW_INTERVAL_MSEC:
			_paced.erase(key)
	for key: String in _lanes.keys():
		var lane: Lane = _lanes[key]
		while not lane.queue.is_empty() and not _writing.has(key):
			if _paced.has(key) and now - _paced[key] < RAW_INTERVAL_MSEC:
				break
			var pending: Pending = lane.queue.pop_front()
			lane.events -= pending.ticket.context.events()
			# Refused: with it goes what was aimed alike; the rest goes on.
			_start_raw(pending, now)
		if lane.queue.is_empty() and _lanes.get(key) == lane:
			_lanes.erase(key)


## Check raw input `pending` once more, against what the fleet knows now, and
## open its request. False when it was refused, and with it every input queued
## behind it that was aimed alike (same generation and terminal); input aimed
## at the pane's new terminal stays queued and is judged on its own.
func _start_raw(pending: Pending, now: int) -> bool:
	var ticket := pending.ticket
	var context := ticket.context
	var machine: Machine = null
	if pending.facts.is_valid():
		var known: Variant = pending.facts.call()
		if known is Machine:
			machine = known
	var reason := refusal(context, machine)
	if reason != CommandRefusal.Reason.NONE:
		ticket.refuse(reason)
		pending.entry.refusal = CommandRefusal.name_of(reason)
		_record(ticket, pending.entry, false)
		_refuse_lane(context.pane_key, reason, context)
		return false
	var peer := HerdrClient.open_peer(machine.socket_path)
	if peer == null:
		ticket.settle(CommandTicket.State.CANCELLED, "herdr's socket is not there")
		_record(ticket, pending.entry, false)
		return true
	_paced[context.pane_key] = now
	_writing[context.pane_key] = ticket
	var channel := Channel.new()
	channel.ticket = ticket
	channel.entry = pending.entry
	channel.peer = peer
	channel.reader = HerdrClient.LineReader.new(_line_max(context.kind))
	channel.left = _timeout(context.kind)
	channel.payload = HerdrClient.request_line(ticket.request_id, _METHODS[context.kind], _params(context))
	_open(channel)
	return true


## The terminal monitor closed: everything still queued for pane `pane_key`
## ends CANCELLED, oldest first, and none of it is ever written. The request
## already on the wire, if any, goes on and settles as it settles.
func drop_raw(pane_key: String) -> void:
	var lane: Lane = _lanes.get(pane_key)
	if lane == null:
		return
	var waiting := lane.queue.duplicate()
	lane.queue.clear()
	lane.events = 0
	_lanes.erase(pane_key)
	for pending: Pending in waiting:
		pending.ticket.settle(CommandTicket.State.CANCELLED, "the monitor closed")
		_record(pending.ticket, pending.entry, false)


## Refuse everything still queued for pane `pane_key`, for `reason`, oldest
## first. None of it was written.
## With `like`, only what was aimed like it (same generation and terminal).
func _refuse_lane(pane_key: String, reason: CommandRefusal.Reason, like: CommandContext = null) -> void:
	var lane: Lane = _lanes.get(pane_key)
	if lane == null:
		return
	var waiting: Array[Pending] = []
	var kept: Array[Pending] = []
	for pending in lane.queue:
		var aimed := pending.ticket.context
		if like == null or (aimed.generation == like.generation and aimed.terminal_id == like.terminal_id):
			waiting.append(pending)
		else:
			kept.append(pending)
	lane.queue = kept
	lane.events = 0
	for pending in kept:
		lane.events += pending.ticket.context.events()
	if kept.is_empty():
		_lanes.erase(pane_key)
	for pending: Pending in waiting:
		pending.ticket.refuse(reason)
		pending.entry.refusal = CommandRefusal.name_of(reason)
		_record(pending.ticket, pending.entry, false)


## Move one request along; false once it is over.
func _pump(channel: Channel, delta: float) -> bool:
	channel.peer.poll()
	var status := channel.peer.get_status()
	var why := _write(channel, status)
	if why.is_empty():
		# Always drain before judging the status: herdr answers and closes within
		# one poll, and the peer stays connected until those bytes are read.
		var lines := channel.reader.pull(channel.peer)
		if not lines.is_empty():
			if channel.check:
				var send := _rechecked(channel, lines[0])
				# The write starts in the frame its re-read was judged in.
				if send != null and _pump(send, 0.0):
					_spawned.append(send)
			else:
				_answer(channel, lines[0])
			return false
		why = _trouble(channel, status, delta)
	if why.is_empty():
		return true
	_end(channel, why)
	return false


## Write what is left of the request. A write is SENT from its first byte on;
## a re-read's bytes never make it so. What went wrong writing it, or empty.
func _write(channel: Channel, status: StreamPeerSocket.Status) -> String:
	if status != StreamPeerSocket.STATUS_CONNECTED or channel.written >= channel.payload.size():
		return ""
	var put: Array = channel.peer.put_partial_data(channel.payload.slice(channel.written))
	var error: int = put[0]
	var count: int = put[1]
	if count > 0:
		channel.written += count
		if not channel.check and channel.ticket.state == CommandTicket.State.UNSENT:
			channel.ticket.settle(CommandTicket.State.SENT)
			channel.entry.record(CommandTicket.state_name(CommandTicket.State.SENT), _now())
	return "" if error == OK else "the request could not be written"


## Why the request is over with no answer, or empty while one may still come.
func _trouble(channel: Channel, status: StreamPeerSocket.Status, delta: float) -> String:
	if channel.reader.overflow:
		return "the answer was longer than %d bytes" % channel.reader.cap
	channel.left -= delta
	if status == StreamPeerSocket.STATUS_ERROR:
		return "the connection failed"
	if status == StreamPeerSocket.STATUS_NONE and channel.written > 0:
		return "herdr closed the connection without answering"
	if channel.left <= 0.0:
		return "no answer in time"
	return ""


## The reply envelope for `request_id` in `line`, or why there is none: a
## Dictionary on success, a String saying what was wrong otherwise.
static func _envelope(line: String, request_id: String) -> Variant:
	# Never JSON.parse_string(): it would echo part of a malformed read, which is
	# terminal text, into the log.
	var message: Variant = HerdrClient.parse_line(line)
	if not message is Dictionary:
		return "an unreadable answer"
	var envelope: Dictionary = message
	if MachineRoster.clean_text(envelope.get("id")) != request_id:
		return "an answer to another request"
	return envelope


## A whole reply line for `channel`'s command.
func _answer(channel: Channel, line: String) -> void:
	var ticket := channel.ticket
	var parsed: Variant = _envelope(line, ticket.request_id)
	if parsed is String:
		var why: String = parsed
		_end(channel, why)
		return
	var envelope: Dictionary = parsed
	if envelope.has("error"):
		var detail: Dictionary = envelope.get("error") if envelope.get("error") is Dictionary else {}
		ticket.error_code = MachineRoster.clean_text(detail.get("code")).left(ERROR_TEXT_MAX)
		ticket.rejection = CommandRejection.of(ticket.error_code)
		# Remote free text (a taken name's answer carries a remote path): every
		# grapheme cluster bounded, like every remote string shown (invariant 9).
		if ticket.context.kind == CommandContext.Kind.WORKTREE:
			# git's stderr: several lines with paths and hints; one line of it.
			ticket.error_message = GitWords.headline(detail.get("message"), ERROR_TEXT_MAX)
		else:
			ticket.error_message = (TerminalText.bound(MachineRoster.clean_text(detail.get("message"))).left(
				ERROR_TEXT_MAX
			))
		channel.entry.error_code = ticket.error_code
		_close(channel, CommandTicket.State.REJECTED)
		return
	if not envelope.get("result") is Dictionary:
		_end(channel, "an answer without a result")
		return
	var unread := _take_result(channel, envelope.get("result"))
	if not unread.is_empty():
		# A write's result that cannot be read: herdr may have done it all the same.
		_end(channel, unread)
		return
	# The other writes (focus, keys, a prompt, input, text, a close): the schema pins no
	# result variant this office reads (herdr 0.9.0 answers `{"type":"ok"}`,
	# and a prompt `agent_prompted` with the agent's state before it), so any
	# result object is accepted. It says herdr took the request, never that the
	# agent acted on it.
	_close(channel, CommandTicket.State.ACCEPTED)


## Read the result `channel`'s command got into its ticket and its audit entry:
## a read's text, the monitor's screen, a split's new pane, a start's agent.
## Why it could not be read, or empty (also for a write whose result is not read).
func _take_result(channel: Channel, result: Variant) -> String:
	var ticket := channel.ticket
	var wire := ticket.context.wire_pane_id
	var unread := ""
	match ticket.context.kind:
		CommandContext.Kind.SCREEN:
			ticket.screen = ScreenReadResult.from_wire(result, wire)
			if ticket.screen == null:
				unread = "an unreadable screen"
			else:
				_note_read(channel.entry, ticket.screen.bytes, ticket.screen.truncated, ticket.screen.cut)
		CommandContext.Kind.READ:
			ticket.read = PaneReadResult.from_wire(result, wire)
			if ticket.read == null:
				unread = "an unreadable read result"
			else:
				_note_read(channel.entry, ticket.read.bytes, ticket.read.truncated, ticket.read.cut)
		CommandContext.Kind.SPLIT:
			ticket.split = PaneSplitResult.from_wire(result, wire)
			if ticket.split == null:
				unread = "an unreadable split result"
		CommandContext.Kind.START:
			ticket.launch = AgentStartResult.from_wire(result, wire)
			if ticket.launch == null:
				unread = "an unreadable start result"
		CommandContext.Kind.LAUNCH_CHECK:
			ticket.agent_info = AgentInfoResult.from_wire(result, wire)
			if ticket.agent_info == null:
				unread = "an unreadable agent"
		CommandContext.Kind.SPACE, CommandContext.Kind.WORKTREE:
			ticket.space = SpaceCreateResult.from_wire(result)
			if ticket.space == null:
				unread = "an unreadable workspace result"
	return unread


## What a read brought back, for its audit entry: sizes and flags, never text.
static func _note_read(entry: CommandAuditEntry, bytes: int, truncated: bool, cut: bool) -> void:
	entry.bytes = bytes
	entry.truncated = truncated
	entry.cut = cut
	entry.summary += (
		" -> %d bytes%s%s" % [bytes, ", truncated by herdr" if truncated else "", ", cut here" if cut else ""]
	)


## An input command's re-read came back: judge it, and hand back the write's
## own channel when nothing stands against it (null when the ticket is over).
func _rechecked(channel: Channel, line: String) -> Channel:
	channel.peer.disconnect_from_host()
	var ticket := channel.ticket
	var parsed: Variant = _envelope(line, ticket.request_id + CHECK_SUFFIX)
	if parsed is String:
		var why: String = parsed
		_recheck_failed(channel, why)
		return null
	var envelope: Dictionary = parsed
	if envelope.has("error"):
		var detail: Dictionary = envelope.get("error") if envelope.get("error") is Dictionary else {}
		_recheck_failed(
			channel, "herdr refused the re-read (%s)" % MachineRoster.clean_text(detail.get("code")).left(64)
		)
		return null
	var read := PaneReadResult.from_wire(envelope.get("result"), ticket.context.wire_pane_id)
	if read == null:
		_recheck_failed(channel, "an unreadable re-read")
		return null
	return _judge(channel, read)


## Every check once more, with what the fleet knows now, then the comparison;
## the write's channel, opened, or null with the ticket refused or cancelled.
func _judge(channel: Channel, read: PaneReadResult) -> Channel:
	var ticket := channel.ticket
	var context := ticket.context
	var entry := channel.entry
	var matched := context.seen != null and context.seen.matches(read)
	ticket.recheck_bytes = read.bytes
	ticket.recheck_matched = matched
	entry.recheck_bytes = read.bytes
	entry.recheck_matched = matched
	var machine: Machine = null
	if channel.facts.is_valid():
		var now: Variant = channel.facts.call()
		if now is Machine:
			machine = now
	var reason := refusal(context, machine)
	if reason == CommandRefusal.Reason.NONE:
		reason = seen_refusal(context)
	if reason == CommandRefusal.Reason.NONE and _writing.get(context.pane_key) != ticket:
		reason = CommandRefusal.Reason.IN_FLIGHT
	if reason == CommandRefusal.Reason.NONE and (read.cut or read.truncated):
		reason = CommandRefusal.Reason.SCREEN_CUT
	if reason == CommandRefusal.Reason.NONE and not matched:
		reason = CommandRefusal.Reason.SCREEN_CHANGED
	if reason == CommandRefusal.Reason.NONE and context.kind == CommandContext.Kind.START:
		# The re-read matched the text frozen at the press, so this reads the
		# same; kept so that what is sent after is plainly what was judged.
		reason = prompt_refusal(PromptState.of_text(read.text), context.confirmed)
	if reason != CommandRefusal.Reason.NONE:
		ticket.refuse(reason)
		entry.refusal = CommandRefusal.name_of(reason)
		_record(ticket, entry)
		return null
	var peer := HerdrClient.open_peer(machine.socket_path)
	if peer == null:
		ticket.settle(CommandTicket.State.CANCELLED, "herdr's socket is not there")
		_record(ticket, entry)
		return null
	var send := Channel.new()
	send.ticket = ticket
	send.entry = entry
	send.peer = peer
	send.reader = HerdrClient.LineReader.new(_line_max(context.kind))
	send.left = _timeout(context.kind)
	send.payload = HerdrClient.request_line(ticket.request_id, _METHODS[context.kind], _params(context))
	return send


## The re-read brought no text to compare: nothing is written.
func _recheck_failed(channel: Channel, why: String) -> void:
	channel.peer.disconnect_from_host()
	channel.ticket.failure = why
	channel.ticket.refuse(CommandRefusal.Reason.RECHECK_FAILED)
	channel.entry.refusal = CommandRefusal.name_of(CommandRefusal.Reason.RECHECK_FAILED)
	_record(channel.ticket, channel.entry)


## Settle a request that failed. A read or a write: UNKNOWN once its first byte
## went out, CANCELLED before that. An input command's re-read (nothing of the
## write has gone out): CANCELLED when its machine went (`gone`), refused as
## RECHECK_FAILED otherwise.
func _end(channel: Channel, why: String, gone := false) -> void:
	if channel.check:
		if gone:
			channel.ticket.failure = why
			_close(channel, CommandTicket.State.CANCELLED)
		else:
			_recheck_failed(channel, why)
		return
	var sent := channel.written > 0
	channel.ticket.failure = why
	_close(channel, CommandTicket.State.UNKNOWN if sent else CommandTicket.State.CANCELLED)


func _close(channel: Channel, state: CommandTicket.State) -> void:
	channel.peer.disconnect_from_host()
	channel.ticket.settle(state)
	_record(channel.ticket, channel.entry)


## The ticket is final: its pane is free for the next write, the audit has its
## last state, and a write that was under way (`queued`: it passed the checks
## at the gesture), whatever became of it, has to be looked at before the next
## one to that pane. A write refused at the gesture never touched the pane.
func _record(ticket: CommandTicket, entry: CommandAuditEntry, queued := true) -> void:
	entry.record(CommandTicket.state_name(ticket.state), _now())
	var context := ticket.context
	var key := context.pane_key if context != null else ""
	if _writing.get(key) == ticket:
		_writing.erase(key)
	if queued and context != null and context.is_write() and ticket.is_finished():
		var look := Look.new()
		look.ticket = ticket
		look.settled_msec = _msec()
		# Erased first so that the newest is always last, and the oldest goes first.
		_looks.erase(context.pane_key)
		_looks[context.pane_key] = look
		while _looks.size() > LOOKS_MAX:
			_looks.erase(_looks.keys()[0])
	if context != null and context.kind == CommandContext.Kind.START:
		# Accepted, or sent with its answer lost: either way herdr may be
		# typing into the shell, and may hold the name.
		if ticket.state == CommandTicket.State.ACCEPTED or ticket.state == CommandTicket.State.UNKNOWN:
			_remember_launch(ticket)
			snapshot_wanted.emit(context.machine)
	if context != null and context.kind == CommandContext.Kind.LAUNCH_CHECK and ticket.is_finished():
		snapshot_wanted.emit(context.machine)
	var floors := [CommandContext.Kind.CLOSE, CommandContext.Kind.SPACE, CommandContext.Kind.WORKTREE]
	if context != null and context.kind in floors and ticket.state == CommandTicket.State.ACCEPTED:
		# The pane is gone, or a space is new: the next snapshot shows it.
		snapshot_wanted.emit(context.machine)


## Remember the start `ticket` for its pane's watch and its name, newest last.
func _remember_launch(ticket: CommandTicket) -> void:
	var context := ticket.context
	var watch := LaunchWatch.new()
	watch.pane_key = context.pane_key
	watch.machine = context.machine
	watch.name = context.agent_name
	watch.kind = context.agent_kind
	watch.terminal_id = context.terminal_id
	watch.started_msec = ticket.queued_msec
	watch.ended_msec = _msec()
	watch.ticket = ticket
	_launches.erase(context.pane_key)
	_launches[context.pane_key] = watch
	while _launches.size() > LAUNCHES_MAX:
		_launches.erase(_launches.keys()[0])
	if machine_facts.is_valid():
		# Pumped until its deadline is decided.
		set_process(true)


# --- payloads -----------------------------------------------------------------


static func _payload_refusal(context: CommandContext) -> CommandRefusal.Reason:
	match context.kind:
		CommandContext.Kind.READ:
			var fine := context.source in READ_SOURCES and context.lines >= 1 and context.lines <= READ_LINES_MAX
			return CommandRefusal.Reason.NONE if fine else CommandRefusal.Reason.NOT_ALLOWED
		CommandContext.Kind.FOCUS:
			return CommandRefusal.Reason.NONE
		CommandContext.Kind.KEYS:
			# Exact: `Y`, `Enter`, `escape`, `C-c` and `ctrl+c` are all refused here.
			return (
				CommandRefusal.Reason.NONE if context.key_name in KEY_NAMES else CommandRefusal.Reason.KEY_NOT_ALLOWED
			)
		CommandContext.Kind.LINE:
			return line_refusal(context.line)
		CommandContext.Kind.SCREEN:
			if context.source == CommandContext.SOURCE_VISIBLE:
				return CommandRefusal.Reason.NONE if context.lines == 0 else CommandRefusal.Reason.NOT_ALLOWED
			var scrollback := context.lines >= 1 and context.lines <= SCROLLBACK_LINES_MAX
			var fine_screen := context.source == CommandContext.SOURCE_SCROLLBACK and scrollback
			return CommandRefusal.Reason.NONE if fine_screen else CommandRefusal.Reason.NOT_ALLOWED
		CommandContext.Kind.TYPE_KEYS:
			var pressed := context.keys
			if pressed.is_empty():
				return CommandRefusal.Reason.INPUT_EMPTY
			if pressed.size() > RAW_QUEUE_EVENTS:
				return CommandRefusal.Reason.QUEUE_FULL
			for key_name in pressed:
				var why := raw_key_refusal(key_name)
				if why != CommandRefusal.Reason.NONE:
					return why
			return CommandRefusal.Reason.NONE
		CommandContext.Kind.TYPE_TEXT:
			return text_refusal(context.text)
		CommandContext.Kind.PASTE:
			return paste_refusal(context.text)
		CommandContext.Kind.START:
			var kind := kind_refusal(context.agent_kind)
			return kind if kind != CommandRefusal.Reason.NONE else name_refusal(context.agent_name)
		CommandContext.Kind.SPLIT:
			var fine_side := context.direction in SPLIT_DIRECTIONS
			return CommandRefusal.Reason.NONE if fine_side else CommandRefusal.Reason.DIRECTION_INVALID
		CommandContext.Kind.LAUNCH_CHECK:
			return CommandRefusal.Reason.NONE
		CommandContext.Kind.CLOSE:
			var scoped := context.scope != null and not context.scope.missing
			return CommandRefusal.Reason.NONE if scoped else CommandRefusal.Reason.SCOPE_CHANGED
		CommandContext.Kind.SPACE:
			return cwd_refusal(context.cwd)
		CommandContext.Kind.WORKTREE:
			return branch_refusal(context.branch)
	return CommandRefusal.Reason.NOT_ALLOWED


## Whether `pane` may receive an input of `kind` now: an agent herdr detected
## (never a shell); blocked for answer keys, even while herdr is still
## launching it (an agent can ask a question, a trust prompt, before herdr
## calls it ready); idle or done for a line, and not still launching.
static func _recipient_refusal(kind: CommandContext.Kind, pane: HerdrSnapshot.Pane) -> CommandRefusal.Reason:
	if pane.agent.is_empty():
		return CommandRefusal.Reason.NOT_AN_AGENT
	var status := pane.status()
	if kind == CommandContext.Kind.KEYS:
		return CommandRefusal.Reason.NONE if status in ASKING_STATES else CommandRefusal.Reason.NOT_ASKING
	if pane.launch_pending:
		return CommandRefusal.Reason.AGENT_STARTING
	if status in ASKING_STATES:
		return CommandRefusal.Reason.AGENT_ASKING
	return CommandRefusal.Reason.NONE if status in REPLY_STATES else CommandRefusal.Reason.AGENT_BUSY


static func _params(context: CommandContext) -> Dictionary:
	match context.kind:
		CommandContext.Kind.READ:
			return {
				"pane_id": context.wire_pane_id,
				"source": context.source,
				"format": READ_FORMAT,
				"strip_ansi": true,
				"lines": context.lines,
			}
		CommandContext.Kind.KEYS:
			return {"pane_id": context.wire_pane_id, "keys": [context.key_name]}
		CommandContext.Kind.LINE:
			# No `keys`: herdr types Enter itself, about 300 ms after the text.
			# No `wait`: its answer would wait for the agent to finish.
			return {"target": context.wire_pane_id, "text": context.line}
		CommandContext.Kind.START:
			# No `args` (a command line typed into a shell) and no `timeout_ms`
			# (herdr 0.9.0 checks it and ignores it, measured).
			return {"name": context.agent_name, "kind": context.agent_kind, "pane_id": context.wire_pane_id}
		CommandContext.Kind.SPLIT:
			# All three, always: without a target herdr splits the shared focus,
			# and `focus` would move it. No `cwd`: the new pane starts where the
			# old one's shell is (a bad one lands in $HOME, measured).
			return {"target_pane_id": context.wire_pane_id, "direction": context.direction, "focus": false}
		CommandContext.Kind.LAUNCH_CHECK:
			# herdr's own spelling of the pane id, never the name: a name can be
			# someone else's by then.
			return {"target": context.wire_pane_id}
		CommandContext.Kind.SCREEN:
			var screen := {
				"pane_id": context.wire_pane_id,
				"source": context.source,
				"format": SCREEN_FORMAT,
				"strip_ansi": false,
			}
			if context.lines > 0:
				screen["lines"] = context.lines
			return screen
		CommandContext.Kind.TYPE_KEYS:
			return {"pane_id": context.wire_pane_id, "keys": Array(context.keys)}
		CommandContext.Kind.TYPE_TEXT, CommandContext.Kind.PASTE:
			# No `keys`: a paste is the text alone, bracketed by herdr when the program asked.
			return {"pane_id": context.wire_pane_id, "text": context.text}
		CommandContext.Kind.CLOSE:
			return {"pane_id": context.wire_pane_id}
		CommandContext.Kind.SPACE:
			# `cwd` and `focus`, always both: without `cwd` herdr follows its own
			# focused pane; `focus: true` would move the shared view. No `label`
			# (herdr names it after the directory), no `env`, no source workspace.
			return {"cwd": context.cwd, "focus": false}
		CommandContext.Kind.WORKTREE:
			# All four, always: no `path` (herdr's configured directory), no
			# `base` (the checkout's HEAD), no `cwd`, no `trust_repository`.
			return {
				"workspace_id": context.wire_workspace_id,
				"branch": context.branch,
				"label": context.branch,
				"focus": false,
			}
	return {"pane_id": context.wire_pane_id}


## C0 (tab, LF, CR, ESC …), DEL, C1 (NEL …), and the line and paragraph separators.
static func _control(code: int) -> bool:
	return code < 0x20 or (code >= 0x7F and code <= 0x9F) or code == 0x2028 or code == 0x2029


## Characters that draw nothing or reorder what is drawn: what the viewer sees
## would not be what the terminal gets. The spec's set (U+200B–U+200F,
## U+202A–U+202E, U+2060–U+2064, U+2066–U+2069, U+061C, U+FEFF) and the rest of
## the same kind: the soft hyphen, the combining grapheme joiner, the Hangul
## and Khmer fillers, the Mongolian selectors, the deprecated format controls
## U+206A–U+206F, interlinear annotation marks and the tag characters.
static func _invisible(code: int) -> bool:
	if code == 0x00AD or code == 0x034F or code == 0x061C or code == 0x115F or code == 0x1160:
		return true
	if code == 0x17B4 or code == 0x17B5 or code == 0x3164 or code == 0xFEFF or code == 0xFFA0:
		return true
	if (code >= 0x180B and code <= 0x180F) or (code >= 0x200B and code <= 0x200F):
		return true
	if (code >= 0x202A and code <= 0x202E) or (code >= 0x2060 and code <= 0x206F):
		return true
	return (code >= 0xFFF9 and code <= 0xFFFB) or (code >= 0xE0000 and code <= 0xE007F)


## What cannot be the character that was typed: U+FFFD (Godot's stand-in for
## an invalid surrogate), a lone surrogate, a noncharacter, or past U+10FFFF.
static func _broken(code: int) -> bool:
	if code == 0xFFFD or (code >= 0xD800 and code <= 0xDFFF) or code > 0x10FFFF or code < 0:
		return true
	return (code >= 0xFDD0 and code <= 0xFDEF) or (code & 0xFFFE) == 0xFFFE


## The direction controls: ALM, LRM, RLM, the embeddings and overrides
## U+202A–U+202E and the isolates U+2066–U+2069.
static func _direction(code: int) -> bool:
	if code == 0x061C or code == 0x200E or code == 0x200F:
		return true
	return (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069)


## One printable ASCII character, space excluded.
static func _printable(character: String) -> bool:
	var code := character.unicode_at(0)
	return code > 0x20 and code < 0x7F


## One lowercase ASCII letter.
static func _letter(character: String) -> bool:
	return character.length() == 1 and character >= "a" and character <= "z"


## Whitespace, which a line cannot consist of alone.
static func _blank(code: int) -> bool:
	if code == 0x20 or code == 0xA0 or code == 0x1680 or code == 0x202F or code == 0x205F:
		return true
	return code == 0x3000 or code == 0x2800 or (code >= 0x2000 and code <= 0x200A)


# --- audit --------------------------------------------------------------------


func _audit(ticket: CommandTicket, machine: Machine) -> CommandAuditEntry:
	var context := ticket.context
	var entry := CommandAuditEntry.new()
	entry.at = _now()
	entry.request_id = ticket.request_id
	var write := context == null or context.is_write()
	if context != null:
		# Everything here is the office's own cleaned spelling, never herdr's wire
		# id: this runs before refusal(), so a context whose wire id carries
		# control or bidi characters is audited too, and must not smuggle them in.
		var pane_id := MachineRoster.clean_text(context.pane_id)
		entry.machine = MachineRoster.clean_text(context.machine)
		entry.generation = context.generation
		entry.pane_key = HerdrFleet.pane_key(context.machine, context.pane_id)
		if _METHODS.has(context.kind):
			entry.method = _METHODS[context.kind]
		entry.summary = "%s %s" % [entry.method if not entry.method.is_empty() else "?", pane_id]
		match context.kind:
			CommandContext.Kind.READ:
				entry.source = context.source
				entry.lines = context.lines
				entry.summary += " %s %d lines" % [context.source, context.lines]
			CommandContext.Kind.KEYS:
				# A key name is this office's own word; a refused one is kept only
				# cleaned and short.
				entry.key_name = MachineRoster.clean_text(context.key_name).left(KEY_TEXT_MAX)
				entry.summary += " key " + entry.key_name
			CommandContext.Kind.LINE:
				# Never the line itself: only how long it is.
				entry.line_bytes = context.line.to_utf8_buffer().size()
				entry.summary += " line of %d bytes" % entry.line_bytes
			CommandContext.Kind.SCREEN:
				entry.source = context.source
				entry.lines = context.lines
				entry.summary += " %s ansi" % context.source
			CommandContext.Kind.TYPE_KEYS:
				# How many keys, never which: key names can spell out what was typed.
				entry.category = "keys"
				entry.events = context.events()
				entry.summary += " %d keys" % entry.events
			CommandContext.Kind.TYPE_TEXT, CommandContext.Kind.PASTE:
				entry.category = "text" if context.kind == CommandContext.Kind.TYPE_TEXT else "paste"
				entry.events = context.events()
				entry.text_bytes = context.text.to_utf8_buffer().size()
				entry.summary += " %s of %d bytes" % [entry.category, entry.text_bytes]
			CommandContext.Kind.START:
				# The office's own words, cleaned and short: a refused one too.
				entry.agent_kind = MachineRoster.clean_text(context.agent_kind).left(WORD_TEXT_MAX)
				entry.agent_name = MachineRoster.clean_text(context.agent_name).left(WORD_TEXT_MAX)
				entry.summary += " %s as %s" % [entry.agent_kind, entry.agent_name]
			CommandContext.Kind.SPLIT:
				entry.direction = MachineRoster.clean_text(context.direction).left(WORD_TEXT_MAX)
				entry.summary += " " + entry.direction
			CommandContext.Kind.CLOSE:
				# What goes with the pane, and its state word: the office's own.
				if context.scope != null:
					entry.scope = context.scope.kind()
					var state := MachineRoster.clean_text(context.scope.state).left(WORD_TEXT_MAX)
					entry.summary += " %s %s" % [entry.scope, state]
			CommandContext.Kind.SPACE:
				# Never the directory: only how long it is.
				entry.cwd_bytes = context.cwd.to_utf8_buffer().size()
				entry.summary = "%s from %s" % [entry.method, pane_id]
			CommandContext.Kind.WORKTREE:
				# The branch is the office's validated word (a refused one is kept
				# cleaned and short); never the label or a path.
				entry.branch = MachineRoster.clean_text(context.branch).left(BRANCH_BYTES_MAX)
				entry.summary = "%s from %s branch %s" % [entry.method, pane_id, entry.branch]
	if machine != null and entry.machine.is_empty():
		entry.machine = machine.key
	var ring := _writes if write else _reads
	ring.append(entry)
	var limit := AUDIT_WRITES if write else AUDIT_READS
	while ring.size() > limit:
		ring.pop_front()
	return entry


## The longest answer line `kind` may get, in bytes.
static func _line_max(kind: CommandContext.Kind) -> int:
	match kind:
		CommandContext.Kind.READ, CommandContext.Kind.SCREEN:
			return READ_LINE_MAX
		CommandContext.Kind.FOCUS:
			return FOCUS_LINE_MAX
		CommandContext.Kind.LINE:
			return PROMPT_LINE_MAX
		CommandContext.Kind.START:
			return START_LINE_MAX
		CommandContext.Kind.SPLIT:
			return SPLIT_LINE_MAX
		CommandContext.Kind.LAUNCH_CHECK:
			return LAUNCH_CHECK_LINE_MAX
		CommandContext.Kind.CLOSE:
			return CLOSE_LINE_MAX
		CommandContext.Kind.SPACE:
			return SPACE_LINE_MAX
		CommandContext.Kind.WORKTREE:
			return WORKTREE_LINE_MAX
	return INPUT_LINE_MAX


## Seconds `kind` may take from queueing to a whole answer.
static func _timeout(kind: CommandContext.Kind) -> float:
	match kind:
		CommandContext.Kind.READ, CommandContext.Kind.SCREEN:
			return READ_TIMEOUT
		CommandContext.Kind.FOCUS:
			return FOCUS_TIMEOUT
		CommandContext.Kind.START:
			return START_TIMEOUT
		CommandContext.Kind.SPLIT:
			return SPLIT_TIMEOUT
		CommandContext.Kind.LAUNCH_CHECK:
			return LAUNCH_CHECK_TIMEOUT
		CommandContext.Kind.CLOSE:
			return CLOSE_TIMEOUT
		CommandContext.Kind.SPACE:
			return SPACE_TIMEOUT
		CommandContext.Kind.WORKTREE:
			return WORKTREE_TIMEOUT
	return INPUT_TIMEOUT


## Spelled as NAME_PATTERN says, the whole of it (PCRE's `$` also matches
## before a final newline).
static func _named_so(word: String) -> bool:
	var found := _name_rule.search(word)
	return found != null and found.get_string() == word


static func _now() -> float:
	return Time.get_unix_time_from_system()


## The milliseconds this boundary counts by: its `clock`, or
## Time.get_ticks_msec(). A start's watch is judged on it (LaunchWatch.started_msec).
func now_msec() -> int:
	return _msec()


func _msec() -> int:
	if clock.is_valid():
		var now: Variant = clock.call()
		if now is int:
			return now
	return Time.get_ticks_msec()
