class_name HerdrFleet
extends Node
## Every herdr machine the office shows: Local plus the roster's machines, each
## its own server with its own client and, for SSH machines, its own forward.
## Knows no rendering and hands out plain data only: machine keys, labels,
## typed snapshots (HerdrSnapshot), liveness and link status. No client, link or
## roster object leaves this node.
##
## Pane ids repeat across machines, so a pane is known by its machine key and
## pane id together (see pane_key).
##
## Commands (the agent card's terminal preview, its switch, its answers, its
## start of an agent in a shell and its split of a pane, and the terminal
## monitor's screen reads and raw input) go through the typed calls under
## "commands": a CommandContext in, a CommandTicket out.
## They reach HerdrCommands, which exists only when start() was not told the
## office is read-only; each is checked against what the fleet knows of its
## machine at that moment. Every machine carries a generation from one
## fleet-wide counter, renewed when it opens and on its own `connected`, so a
## context aimed before a replacement, a re-enable or a reconnect never matches.
##
## The log of every state segment and event this run saw (StateLog) is fed
## here, from each client's snapshots, status events and liveness, and read by
## the HUD through state_log(). The log records the client's clock (the
## StateClock state_since() reads); it keeps none of its own.

## A snapshot changed, the roster was applied, or an SSH link changed phase or detail.
signal changed
## The same roster key now names a different connection target or session.
## Emitted after the new site replaces the old one, before `changed`.
signal machine_replaced(key: String)
## Some client connected or disconnected.
signal liveness_changed

## How a machine is reached: the local herdr, a debug socket, or an SSH forward.
enum Kind { LOCAL, SOCKET, SSH }

## Machine key of the local herdr. Saved machines are `machine:<profile id>`
## and debug sockets `socket:<label>`, so none can collide with it.
const LOCAL := "local"
## Joins machine key and pane id; it cannot occur in either.
const KEY_SEPARATOR := "\u001f"

var _roster: MachineRoster
## One per shown machine, Local first.
var _sites: Array[Site] = []
## The last generation handed out; see generation().
var _generations := 0
## The write boundary; null until start() and, in read-only mode, for good.
var _commands: HerdrCommands
## What this run saw of every pane's state; see state_log().
var _log := StateLog.new()


## One shown machine: what the office calls it, what it connects to, and the
## client (and for SSH, the forward) doing that.
class Site:
	var key := ""
	var label := ""
	var kind := HerdrFleet.Kind.LOCAL
	## What it connects to. A rename keeps the site; a new target, session or
	## socket tears it down and opens a fresh one.
	var target := ""
	var session := ""
	var socket := ""
	var client: HerdrClient
	## Null for a machine without an SSH forward.
	var link: MachineLink
	## From the fleet-wide counter: a new value when the site opens and on each
	## `connected` of its own client.
	var generation := -1

	func config() -> String:
		return JSON.stringify([kind, target, session, socket])


## Local exists from the start, so an office drawn before `start()` already
## has its Local segment, offline.
func _init() -> void:
	name = "Fleet"
	var local := Site.new()
	local.key = LOCAL
	local.label = "Local"
	local.generation = _next_generation()
	local.client = _new_client(local)
	_sites = [local]


## Connect Local and start following the roster. Call once this node is in the
## tree: clients, links and the roster are its children and run on its frames.
## `without_writes` (`--read-only`) is decided here, before any client starts:
## such a fleet never constructs HerdrCommands, so nothing in it can send herdr
## more than `ping`, `session.snapshot` and `events.subscribe`.
func start(user_args: PackedStringArray, without_writes: bool) -> void:
	if not without_writes:
		_commands = HerdrCommands.new()
		# A start's deadline asks what the fleet knows of its machine then.
		_commands.machine_facts = _machine
		_commands.snapshot_wanted.connect(_on_snapshot_wanted)
		add_child(_commands)
	var client := _sites[0].client
	var socket_path := HerdrClient.resolve_socket_path(user_args)
	if without_writes:
		print("OFFICE_START: read-only herdr client on " + socket_path)
	else:
		print("OFFICE_START: operator herdr client on %s (may send %s)" % [socket_path, HerdrCommands.methods_text()])
	client.start(socket_path)
	for leftover in MachineLink.clean_leftovers():
		print("Removed a stale machine forward: " + leftover)
	_roster = MachineRoster.new()
	add_child(_roster)
	_roster.changed.connect(_sync_sites)
	_roster.start(user_args)


# --- keys ---------------------------------------------------------------------


## Both halves lose their control characters, so no id can smuggle in the
## separator and pose as a pane of another machine.
static func pane_key(machine: String, pane_id: String) -> String:
	return MachineRoster.clean_text(machine) + KEY_SEPARATOR + MachineRoster.clean_text(pane_id)


## [machine key, pane id]; a key without a separator is a Local pane id.
static func split_key(key: String) -> PackedStringArray:
	var cut := key.find(KEY_SEPARATOR)
	if cut < 0:
		return PackedStringArray([LOCAL, key])
	return PackedStringArray([key.substr(0, cut), key.substr(cut + KEY_SEPARATOR.length())])


# --- read ---------------------------------------------------------------------


## Machine keys, Local first, in the order the office stacks them.
func keys() -> PackedStringArray:
	var result := PackedStringArray()
	for site in _sites:
		result.append(site.key)
	return result


func size() -> int:
	return _sites.size()


func has(key: String) -> bool:
	return _site(key) != null


func label(key: String) -> String:
	var site := _site(key)
	return "" if site == null else site.label


## Machine key -> its snapshot, as the clients hold it now. Nothing is read
## again: these are the snapshots the clients cleaned once, when they arrived.
## They are the clients' own, patched in place by status events: read them only.
func views() -> Dictionary[String, HerdrSnapshot]:
	var result: Dictionary[String, HerdrSnapshot] = {}
	for site in _sites:
		result[site.key] = site.client.snapshot
	return result


## One machine's snapshot as its client holds it; an empty one for a machine not shown.
func snapshot(key: String) -> HerdrSnapshot:
	var site := _site(key)
	return HerdrSnapshot.new() if site == null else site.client.snapshot


## A live subscription still needs a complete snapshot from this connection.
func snapshot_is_current(key: String) -> bool:
	var site := _site(key)
	if site == null:
		return false
	return site.client.online and site.client.snapshot_current


## A disconnected machine or one waiting for its first fresh snapshot is stale.
func is_stale(key: String) -> bool:
	return not snapshot_is_current(key)


func live_count() -> int:
	var live := 0
	for site in _sites:
		live += 1 if site.client.online and site.client.snapshot_current else 0
	return live


## The SSH forward's phase; STOPPED for a machine without one.
func link_state(key: String) -> MachineLink.State:
	var site := _site(key)
	return MachineLink.State.STOPPED if site == null or site.link == null else site.link.state


## The SSH forward's last complaint; empty for a machine without one.
func link_error(key: String) -> String:
	var site := _site(key)
	return "" if site == null or site.link == null else site.link.last_error


## Unix time the machine's client last read a snapshot or applied a status
## event (HerdrClient.heard_at), kept across a drop; −1 when it never has, or
## for a machine not shown.
func heard_since(key: String) -> float:
	var site := _site(key)
	return -1.0 if site == null else site.client.heard_at


## Unix time the pane's status began, or -1 when unknown. A pane id is only
## unique within one machine; a machine not shown answers as Local.
func state_since(machine: String, pane_id: String) -> float:
	var site := _site(machine)
	if site == null:
		site = _sites[0]
	return site.client.state_since(pane_id)


## Every pane's state segments and the events between them since this office
## opened, as the fleet saw them: read it, never write it.
func state_log() -> StateLog:
	return _log


## Every machine has sent at least one snapshot.
func all_loaded() -> bool:
	return _sites.all(func(site: Site) -> bool: return not site.client.snapshot.is_empty())


## The machine's current generation, from one fleet-wide, increasing counter:
## renewed when the machine opens (a replaced or re-enabled machine is a new
## one) and on each `connected` of its own client. -1 for a machine not shown.
func generation(key: String) -> int:
	var site := _site(key)
	return -1 if site == null else site.generation


## The protocol the machine's connection announced; 0 while it has none.
func protocol(key: String) -> int:
	var site := _site(key)
	return 0 if site == null else site.client.protocol


# --- commands -----------------------------------------------------------------


## Whether this office was started without a write capability: no command of
## any kind is ever sent. True until start() says otherwise.
func read_only() -> bool:
	return _commands == null


## A context aimed at pane `key` as the fleet sees it now: its machine and that
## machine's generation, herdr's own spelling of the pane id and the cleaned one,
## and the pane's PaneModel.identity_key(). A key naming no machine or no pane
## still gets one; sending it is refused with the reason.
func context_for(key: String, binding: int) -> CommandContext:
	var parts := split_key(key)
	var site := _site(parts[0])
	if site == null:
		return CommandContext.aimed(parts[0], -1, key, "", parts[1], "", binding)
	var held := site.client.snapshot
	for index in held.panes.size():
		var pane := held.panes[index]
		if pane.pane_id == parts[1]:
			var identity := AgentSessionIdentity.runtime_key(pane.terminal_id, pane.agent, pane.agent_session)
			var wire := held.wire_pane_ids[index]
			return CommandContext.aimed(
				site.key, site.generation, key, wire, pane.pane_id, identity, binding, pane.terminal_id
			)
	return CommandContext.aimed(site.key, site.generation, key, "", parts[1], "", binding)


## Why a command of `kind` to pane `key` would be refused if it were asked for
## now, or NONE. A write (FOCUS, KEYS, LINE) also waits for an open write to
## that pane and for a look after the last one (LOOK_FIRST). KEYS and LINE are
## judged with a payload that always passes (`enter`, one letter) and without
## the terminal text a real press freezes: whether the pane may receive them.
func can_operate(key: String, kind := CommandContext.Kind.FOCUS) -> CommandRefusal.Reason:
	if _commands == null:
		return CommandRefusal.Reason.READ_ONLY
	var context := context_for(key, 0)
	match kind:
		CommandContext.Kind.FOCUS:
			context = context.focusing()
		CommandContext.Kind.KEYS:
			context = context.keying(HerdrCommands.LINE_ENTER, null)
		CommandContext.Kind.LINE:
			context = context.replying("x", null)
		_:
			context = context.reading(CommandContext.SOURCE_DETECTION, 1)
	var reason := HerdrCommands.refusal(context, _machine(context.machine))
	if reason == CommandRefusal.Reason.NONE:
		reason = _commands.blocker(context)
	return reason


## Why `text` cannot be sent as a line, or NONE (HerdrCommands.line_refusal()).
static func line_refusal(text: String) -> CommandRefusal.Reason:
	return HerdrCommands.line_refusal(text)


## The longest line, in UTF-8 bytes.
static func line_bytes_max() -> int:
	return HerdrCommands.LINE_BYTES_MAX


## Read the pane `context` (a READ, see CommandContext.reading()) aims at.
func read_pane(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.READ)


## Switch herdr's shared view to the pane `context` (a FOCUS) aims at. herdr
## marks every pane of that tab seen: each `done` there turns `idle`.
func focus_pane(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.FOCUS)


## Press one key (a KEYS, see CommandContext.keying()) in the terminal of the
## pane it aims at, if that terminal still reads as the viewer saw it.
func send_keys(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.KEYS)


## Type one line and Enter (a LINE, see CommandContext.replying()) into the
## terminal of the pane it aims at, if that terminal still reads as the viewer saw it.
func send_line(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.LINE)


## Start an agent (a START, see CommandContext.starting()) in the shell of the
## pane it aims at: herdr types the kind's command and Enter there, if that
## terminal still reads as the viewer saw it. An accepted ticket says herdr
## began typing; launch_outcome() says what came of it.
func start_agent(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.START)


## Split a new pane beside the pane `context` (a SPLIT, see
## CommandContext.splitting()) aims at, to the side it names. An accepted
## ticket carries the new pane's ids (CommandTicket.split).
func split_pane(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.SPLIT)


## Close the pane `context` (a CLOSE, see CommandContext.closing()) aims at:
## herdr ends its terminal at once, and its tab or workspace when it was the
## last pane there (the context's CloseScope says which). An accepted ticket
## says herdr took it; the next snapshot shows the pane gone.
func close_pane(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.CLOSE)


## Make a new workspace (a SPACE, see CommandContext.spacing()) whose shell
## starts in the directory of the pane it aims at. An accepted ticket carries
## the new workspace's and shell's ids (CommandTicket.space).
func create_space(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.SPACE)


## Make a linked worktree (a WORKTREE, see CommandContext.branching()) of the
## workspace of the pane it aims at, on the context's branch, in herdr's own
## worktree directory. An accepted ticket carries the new workspace's and
## shell's ids (CommandTicket.space).
func create_worktree(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.WORKTREE)


## What closing pane `key` takes with it, by its machine's current snapshot
## (CloseScope.of()); a missing scope for a pane or machine not shown.
func close_scope(key: String) -> CloseScope:
	var parts := split_key(key)
	return CloseScope.of(snapshot(parts[0]), parts[1])


## Why a close of pane `key` would be refused if it were asked for now, or
## NONE: the machine, the pane, its scope (never a worktree group's parent),
## an open write and a look owed. The card's own two clicks are not judged here.
func can_close(key: String) -> CommandRefusal.Reason:
	if _commands == null:
		return CommandRefusal.Reason.READ_ONLY
	var context := context_for(key, 0).closing(close_scope(key))
	var reason := HerdrCommands.refusal(context, _machine(context.machine))
	if reason == CommandRefusal.Reason.NONE:
		reason = _commands.blocker(context)
	return reason


## Why a new space from pane `key` would be refused if it were asked for now,
## or NONE: the machine, the pane, its directory (absolute, and spelled as
## herdr sent it), an open write and a look owed.
func can_space(key: String) -> CommandRefusal.Reason:
	if _commands == null:
		return CommandRefusal.Reason.READ_ONLY
	var context := context_for(key, 0).spacing(pane_cwd(key))
	var reason := HerdrCommands.refusal(context, _machine(context.machine))
	if reason == CommandRefusal.Reason.NONE:
		reason = _commands.blocker(context)
	return reason


## Why a new worktree from pane `key` would be refused if it were asked for
## now, or NONE: the machine, the pane, its workspace (listed once, not a
## linked worktree), an open write and a look owed. Judged with a branch that
## passes (`x`): whether the typed one does is branch_refusal()'s.
func can_worktree(key: String) -> CommandRefusal.Reason:
	if _commands == null:
		return CommandRefusal.Reason.READ_ONLY
	var context := worktree_context(key, 0, "x")
	var reason := HerdrCommands.refusal(context, _machine(context.machine))
	if reason == CommandRefusal.Reason.NONE:
		reason = _commands.blocker(context)
	return reason


## The directory of pane `key`'s shell, exactly as its machine's current
## snapshot carries it (HerdrSnapshot.Pane.cwd); empty for no such pane.
func pane_cwd(key: String) -> String:
	var parts := split_key(key)
	for pane in snapshot(parts[0]).panes:
		if pane.pane_id == parts[1]:
			return pane.cwd
	return ""


## A context to make a worktree of pane `key`'s workspace on `branch`: the
## workspace as the office cleaned it and as herdr spelled it (empty when the
## snapshot lists no such workspace: sending it is refused with the reason).
func worktree_context(key: String, binding: int, branch: String) -> CommandContext:
	var parts := split_key(key)
	var held := snapshot(parts[0])
	var space_id := ""
	for pane in held.panes:
		if pane.pane_id == parts[1]:
			space_id = pane.workspace_id
			break
	var wire := ""
	for index in held.workspaces.size():
		if held.workspaces[index].workspace_id == space_id:
			wire = held.wire_workspace_ids[index]
			break
	return context_for(key, binding).branching(space_id, wire, branch)


## Why `text` cannot be the branch of a new worktree, or NONE
## (HerdrCommands.branch_refusal(): refuses, never rewrites).
static func branch_refusal(text: String) -> CommandRefusal.Reason:
	return HerdrCommands.branch_refusal(text)


## The agent kinds a start on machine `key` may name: every kind its current
## snapshot shows detected, once each, sorted (HerdrCommands.kinds_of());
## none while the machine is offline or its snapshot not current.
func agent_kinds(key: String) -> PackedStringArray:
	if not snapshot_is_current(key):
		return PackedStringArray()
	return HerdrCommands.kinds_of(snapshot(key))


## The name the next start of `kind` on machine `key` gets: `<kind>-<n>`, the
## lowest n from 1 that no agent on its snapshot holds and no start this run
## sent there used (herdr may hold a lost answer's name too), except a start
## herdr gave up at its deadline (LaunchWatch.failed(): herdr freed that name);
## empty when HerdrCommands.NAME_TRIES_MAX are all taken, or `kind` is empty.
func next_agent_name(key: String, kind: String) -> String:
	if kind.is_empty():
		return ""
	var taken := HerdrCommands.names_of(snapshot(key))
	if _commands != null:
		taken.append_array(_commands.launch_names(key))
	for count in range(1, HerdrCommands.NAME_TRIES_MAX + 1):
		var candidate := "%s-%d" % [kind, count]
		if not candidate in taken:
			return candidate
	return ""


## Why a start of `kind` in pane `key` would be refused if it were asked for
## now, or NONE: the machine, the pane (a shell, not launching), the kind and
## the next name, an open write and a look owed (HerdrCommands.refusal() and
## blocker()). Judged without the terminal text a real press freezes: whether
## that ends at a prompt is prompt_state()'s.
func can_start(key: String, kind: String) -> CommandRefusal.Reason:
	if _commands == null:
		return CommandRefusal.Reason.READ_ONLY
	var context := context_for(key, 0)
	context = context.starting(kind, next_agent_name(context.machine, kind), null)
	var reason := HerdrCommands.refusal(context, _machine(context.machine))
	if reason == CommandRefusal.Reason.NONE:
		reason = _commands.blocker(context)
	return reason


## Why a split of pane `key` would be refused if it were asked for now, or
## NONE: the machine, the pane and its size (HerdrCommands.split_choice()), an
## open write and a look owed.
func can_split(key: String) -> CommandRefusal.Reason:
	if _commands == null:
		return CommandRefusal.Reason.READ_ONLY
	var context := context_for(key, 0)
	var side := split_direction(key)
	context = context.splitting(side if not side.is_empty() else HerdrCommands.SPLIT_DIRECTIONS[0])
	var reason := HerdrCommands.refusal(context, _machine(context.machine))
	if reason == CommandRefusal.Reason.NONE:
		reason = _commands.blocker(context)
	return reason


## The side pane `key` splits to now, `right` or `down`, by its shape in the
## machine's layout; empty when it does not split (can_split() says why).
func split_direction(key: String) -> String:
	var parts := split_key(key)
	return HerdrCommands.split_choice(snapshot(parts[0]), parts[1]).direction


## The last start sent to pane `key` this run; null with none, and in read-only mode.
func launch_of(key: String) -> LaunchWatch:
	return null if _commands == null else _commands.launch_of(key)


## How the last start sent to pane `key` is going, as the machine's current
## snapshot shows the pane now (LaunchWatch.judge()): GONE with no start, or no
## such pane; PENDING while the snapshot is not current (nothing to read it by).
func launch_outcome(key: String) -> LaunchWatch.Outcome:
	var watch := launch_of(key)
	if watch == null:
		return LaunchWatch.Outcome.GONE
	var parts := split_key(key)
	if not snapshot_is_current(parts[0]):
		return LaunchWatch.Outcome.PENDING
	var shown: HerdrSnapshot.Pane = null
	for pane in snapshot(parts[0]).panes:
		if pane.pane_id == parts[1]:
			shown = pane
			break
	# The boundary's clock, the one the watch's start was stamped on.
	return LaunchWatch.judge(watch, shown, _commands.now_msec(), HerdrCommands.LAUNCH_TIMEOUT_MSEC)


## Tests only: the boundary counts its milliseconds by `clock` (a Callable
## returning an int; see HerdrCommands.clock). Nothing in read-only mode.
func use_command_clock(clock: Callable) -> void:
	if _commands != null:
		_commands.clock = clock


## What the terminal text `preview` froze ends in, for a start (PromptState.of()).
static func prompt_state(preview: CommandPreview) -> PromptState:
	return PromptState.of(preview)


## Why a start cannot go after text that ends as `state` says, `confirmed` or
## not (HerdrCommands.prompt_refusal()).
static func prompt_refusal(state: PromptState, confirmed := false) -> CommandRefusal.Reason:
	return HerdrCommands.prompt_refusal(state, confirmed)


## Read the screen (`visible`) or recent output (`recent`) of the pane
## `context` (a SCREEN, see CommandContext.screening()) aims at, with its
## colours: the terminal monitor's read.
func read_screen(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.SCREEN)


## The terminal monitor's raw mode (docs/WRITE_BOUNDARY.md §3): press keys (a TYPE_KEYS,
## see CommandContext.typing_keys()) in the terminal of the pane it aims at,
## after whatever raw input to that pane is still waiting.
func type_keys(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.TYPE_KEYS)


## The same for typed characters (a TYPE_TEXT), sent as they are.
func type_text(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.TYPE_TEXT)


## The same for a paste (a PASTE), which herdr brackets when the program asked.
func paste(context: CommandContext) -> CommandTicket:
	return _submit(context, CommandContext.Kind.PASTE)


## Why raw input to the pane `target` (a context_for() context, as the monitor
## holds it) would be refused if it were typed now, or NONE: the machine, its
## generation, the pane and its terminal. What is queued does not count.
func input_refusal(target: CommandContext) -> CommandRefusal.Reason:
	if _commands == null:
		return CommandRefusal.Reason.READ_ONLY
	if target == null:
		return CommandRefusal.Reason.NOT_ALLOWED
	var probe := target.typing_keys(PackedStringArray([HerdrCommands.LINE_ENTER]))
	return HerdrCommands.refusal(probe, _machine(target.machine))


## Why the monitor's read of `target`'s screen would be refused now, or NONE.
func screen_refusal(target: CommandContext) -> CommandRefusal.Reason:
	if _commands == null:
		return CommandRefusal.Reason.READ_ONLY
	if target == null:
		return CommandRefusal.Reason.NOT_ALLOWED
	return HerdrCommands.refusal(target.screening(CommandContext.SOURCE_VISIBLE, 0), _machine(target.machine))


## The terminal monitor closed: every raw input still waiting for pane `key`
## ends CANCELLED and is never sent. One already on the wire goes on and ends
## as it ends.
func drop_input(key: String) -> void:
	if _commands != null:
		_commands.drop_raw(key)


## Raw input events still waiting for pane `key`; 0 in read-only mode.
func queued_input(key: String) -> int:
	return 0 if _commands == null else _commands.queued_events(key)


## The pane `key`'s terminal size in cells, width x height, as herdr's layout
## gives it (HerdrSnapshot.LayoutSlot); Vector2i.ZERO when unknown.
func pane_size(key: String) -> Vector2i:
	var parts := split_key(key)
	var site := _site(parts[0])
	if site == null:
		return Vector2i.ZERO
	var held := site.client.snapshot
	# Layout slots carry the pane id cleaned the same way the pane's own is.
	for layout in held.layouts:
		for slot in layout.panes:
			if slot.pane_id == parts[1]:
				return Vector2i(slot.width, slot.height)
	return Vector2i.ZERO


## The card or the monitor showed what `ticket` (an accepted READ or SCREEN)
## brought back: after a write, the look that turns that pane's writes back on
## (HerdrCommands.saw()).
func preview_shown(ticket: CommandTicket) -> void:
	if _commands != null:
		_commands.saw(ticket)


## The last write to pane `key`, whatever terminal holds it now; null with
## none. Kept by the boundary, so a card that left and came back still knows.
func last_write(key: String) -> CommandTicket:
	return null if _commands == null else _commands.last_write(key)


## Whether writes to pane `key` wait for a look at a fresh preview.
func must_look(key: String) -> bool:
	return false if _commands == null else _commands.must_look(key)


## This run's writes, oldest first; empty in read-only mode.
func write_log() -> Array[CommandAuditEntry]:
	if _commands == null:
		return []
	return _commands.write_log()


## This run's reads, oldest first; empty in read-only mode. No terminal text.
func read_log() -> Array[CommandAuditEntry]:
	if _commands == null:
		return []
	return _commands.read_log()


func _submit(context: CommandContext, kind: CommandContext.Kind) -> CommandTicket:
	if _commands == null:
		return CommandTicket.refused(context, CommandRefusal.Reason.READ_ONLY)
	if context == null or context.kind != kind:
		return CommandTicket.refused(context, CommandRefusal.Reason.NOT_ALLOWED)
	# An input command is checked again when its re-read comes back, against
	# what the fleet knows of the machine then, not this copy.
	return _commands.submit(context, _machine(context.machine), _machine.bind(context.machine))


## What HerdrCommands needs to know of machine `key` right now; null when no
## machine by that key is shown.
func _machine(key: String) -> HerdrCommands.Machine:
	var site := _site(key)
	if site == null:
		return null
	var facts := HerdrCommands.Machine.new()
	facts.key = site.key
	facts.generation = site.generation
	facts.online = site.client.online
	facts.current = site.client.snapshot_current
	facts.protocol = site.client.protocol
	facts.socket_path = site.client.socket_path
	facts.snapshot = site.client.snapshot
	return facts


## The boundary did something a snapshot of machine `key` will show (a start
## herdr took, a launch check that came back): its client fetches one now,
## not at its next poll. `session.snapshot` is one of the three reads the
## client always makes; nothing is written.
func _on_snapshot_wanted(key: String) -> void:
	var site := _site(key)
	if site != null:
		site.client.refresh_soon()


func _next_generation() -> int:
	_generations += 1
	return _generations


## Every open command of `site` settles: its connection is gone or replaced.
## Raw input still queued for it is refused for `why`.
func _settle(site: Site, why := CommandRefusal.Reason.MACHINE_OFFLINE) -> void:
	if _commands != null:
		_commands.settle_machine(site.key, why)


# --- machines -----------------------------------------------------------------


func _new_client(site: Site) -> HerdrClient:
	var herdr := HerdrClient.new()
	add_child(herdr)
	herdr.connected.connect(_on_connected.bind(site))
	herdr.disconnected.connect(_on_disconnected.bind(site))
	herdr.snapshot_changed.connect(_on_snapshot.bind(site))
	herdr.snapshot_repeated.connect(_note.bind(site))
	herdr.snapshot_readiness_changed.connect(_on_snapshot_readiness_changed.bind(site))
	return herdr


func _on_connected(site: Site) -> void:
	_note(site)
	# A new connection is a new generation: nothing aimed at the last one matches it.
	site.generation = _next_generation()
	# A client that got through its forward makes the link's last complaint history.
	for shown in _sites:
		if shown.link != null and shown.client.online:
			shown.link.clear_error()
	liveness_changed.emit()


func _on_disconnected(site: Site) -> void:
	_note(site)
	_settle(site)
	liveness_changed.emit()


func _on_snapshot_readiness_changed(site: Site) -> void:
	_note(site)
	# Same-content recovery must also unfreeze actors and restore live counts.
	liveness_changed.emit()


func _on_snapshot(_snapshot: HerdrSnapshot, site: Site) -> void:
	_note(site)
	changed.emit()


## Tell the log what `site` looks like now: online (connected, its snapshot
## current) with every pane and the start its client's clock gives it, or not.
## Called before each announcement, so whoever hears it reads the log as new;
## often twice for one change, which the log records once. A pane missing from
## this one snapshot is still handed in, marked, so its segment runs on.
func _note(site: Site) -> void:
	var now_msec := Time.get_ticks_msec()
	var now_unix := Time.get_unix_time_from_system()
	var online := site.client.online and site.client.snapshot_current
	var seen: Array[StateLog.Sighting] = []
	if online:
		var held := site.client.snapshot
		var clocks := site.client.state_clocks()
		var spaces: Dictionary[String, String] = {}
		for workspace in held.workspaces:
			spaces[workspace.workspace_id] = workspace.label
		var tabs: Dictionary[String, String] = {}
		for tab in held.tabs:
			tabs[tab.tab_id] = tab.label
		var listed: Dictionary[String, bool] = {}
		for pane in held.panes:
			listed[pane.pane_id] = true
			var sighting := StateLog.Sighting.new()
			sighting.pane_key = pane_key(site.key, pane.pane_id)
			sighting.status = pane.status()
			sighting.starting = pane.launch_pending
			sighting.agent = pane.agent
			sighting.terminal_id = pane.terminal_id
			sighting.agent_name = pane.agent_name
			sighting.space = spaces.get(pane.workspace_id, "")
			sighting.tab = tabs.get(pane.tab_id, "")
			var clock: HerdrClient.StateClock = clocks.get(pane.pane_id)
			if clock != null:
				sighting.identity = clock.identity
				sighting.since_unix = clock.since
				sighting.missing = clock.missing
			seen.append(sighting)
		for pane_id: String in clocks:
			var kept := clocks[pane_id]
			if kept.missing and not listed.has(pane_id):
				var away := StateLog.Sighting.new()
				away.pane_key = pane_key(site.key, pane_id)
				away.identity = kept.identity
				away.status = kept.status
				away.missing = true
				seen.append(away)
	_log.observe(site.key, site.label, online, seen, now_msec, now_unix)


## Machines to show, Local first, then debug sockets, then enabled saved machines
## in herdr's order, as sites not opened yet. A disabled or removed machine is
## simply absent.
func _wanted_sites() -> Array[Site]:
	var wanted: Array[Site] = []
	for entry in _roster.sockets:
		var debug := Site.new()
		debug.key = "socket:" + entry.label
		debug.label = entry.label
		debug.kind = Kind.SOCKET
		debug.socket = entry.socket
		wanted.append(debug)
	for machine in _roster.machines:
		if machine.enabled:
			var saved := Site.new()
			saved.key = machine.key
			saved.label = machine.label
			saved.kind = Kind.SSH
			saved.target = machine.target
			saved.session = machine.session
			wanted.append(saved)
	var unique: Array[Site] = []
	var seen := {LOCAL: true}
	for want in wanted:
		if not seen.has(want.key):
			seen[want.key] = true
			unique.append(want)
	return unique


## Apply the roster in place: unchanged machines keep their client and forward,
## changed ones (target, session, socket) are torn down and opened afresh.
func _sync_sites() -> void:
	var known: Dictionary[String, Site] = {}
	var replaced := PackedStringArray()
	for index in range(1, _sites.size()):
		known[_sites[index].key] = _sites[index]
	var next: Array[Site] = [_sites[0]]
	for want in _wanted_sites():
		# A rename is only a new plate; what it connects to is the config.
		var site: Site = known.get(want.key)
		known.erase(want.key)
		if site != null and site.config() == want.config():
			site.label = want.label
			next.append(site)
			continue
		if site != null:
			replaced.append(want.key)
			_close_site(site, CommandRefusal.Reason.MACHINE_REPLACED)
		next.append(_open_site(want))
	for site: Site in known.values():
		_close_site(site, CommandRefusal.Reason.MACHINE_GONE)
	_sites = next
	for key in replaced:
		machine_replaced.emit(key)
	changed.emit()


## Give a wanted site its client, and for SSH its forward, and start them.
func _open_site(site: Site) -> Site:
	site.generation = _next_generation()
	site.client = _new_client(site)
	if site.kind == Kind.SSH:
		var link := MachineLink.new()
		link.name = "Link"
		add_child(link)
		site.link = link
		link.state_changed.connect(_on_link_changed.bind(site))
		link.start(site.target, site.session)
		print(
			(
				"MACHINE_START: %s (ssh %s) on %s"
				% [site.label, site.target, link.local_socket if not link.local_socket.is_empty() else "-"]
			)
		)
		return site
	print("MACHINE_START: %s (socket) on %s" % [site.label, site.socket])
	site.client.start(site.socket)
	return site


## The client of an SSH machine connects only once its own ssh holds the local
## end: a file that merely exists at that path is nobody's promise. After that
## it rides out ssh restarts with its own reconnect.
func _on_link_changed(site: Site) -> void:
	if site.link.state == MachineLink.State.FORWARDING and site.client.socket_path.is_empty():
		site.client.start(site.link.local_socket)
	# A link reports while it is being opened, before its machine is listed;
	# `_sync_sites` announces the finished roster itself.
	if _sites.has(site):
		changed.emit()


## A machine replaced (its key reopens after this, see _sync_sites()) or gone:
## its commands settle, its connection stops, and the log lets its panes go.
func _close_site(site: Site, why: CommandRefusal.Reason) -> void:
	_settle(site, why)
	site.client.stop()
	site.client.queue_free()
	if site.link != null:
		site.link.stop()
		site.link.queue_free()
	_log.forget_machine(site.key, Time.get_ticks_msec(), Time.get_unix_time_from_system())


func _site(key: String) -> Site:
	for site in _sites:
		if site.key == key:
			return site
	return null
