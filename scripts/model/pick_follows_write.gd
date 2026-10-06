class_name PickFollowsWrite
extends RefCounted
## Where the viewer's pick goes after a write this office sent: on to the agent
## its own start became (started()), and on to the new pane a split, a new space
## or a worktree from the card made (new_pane(), overdue()). A selection only,
## later: nothing here writes, reads a pane or asks herdr anything.
##
## Pure: static functions over values, with no node, no fleet, no HUD and no
## clock. An adapter (OfficeNewPaneFollow) gathers the facts, asks, and carries
## the Answer out; it keeps Answer.memory, hands it back with its next question
## and reads nothing in it but machine(). The fleet's facts come in as the
## values of three of its reads (HerdrFleet.launch_of(), last_write() and
## generation()), the navigator's as its picked_key, picked_identity and
## nav_revision, and the time as a number of milliseconds.
##
## Three questions, because the office has three moments: a refresh before its
## navigator settles (new_pane(): the pick it makes is the selection that
## settle sees), the same refresh once the selection is settled (started(): it
## is asked about the selected pane), and every frame between refreshes
## (overdue(): the wait runs out without a snapshot).

## Why an Answer says what it says.
enum Why {
	## started(): the pick goes on to the agent this office's start became.
	STARTED,
	## new_pane(): the pick goes to the new pane.
	NEW_PANE,
	## started(): no pane is selected, or the one selected is not the desk the
	## viewer picked (herdr's focus selects it).
	NOT_PICKED,
	## started(): the pane is still the terminal that was picked.
	STILL_PICKED,
	## started(): this run sent no start to the pane.
	NO_START,
	## started(): the start is not the pane's last write any more.
	WROTE_SINCE,
	## started(), new_pane(): the pane shows with another terminal than the one
	## the write named.
	OTHER_TERMINAL,
	## started(): an agent of another kind than the start named.
	OTHER_KIND,
	## started(): an agent herdr lists without the start's name.
	OTHER_NAME,
	## started(): the pick is neither the shell the start was aimed at nor a
	## pick carried here from it.
	NOT_FROM_START,
	## started(): the pick carried here already had its session: this is a
	## session after the first (`/clear`).
	LATER_SESSION,
	## new_pane(), overdue(): no new pane is waited for.
	NOTHING_AWAITED,
	## new_pane(), overdue(): no snapshot shows the new pane yet, and its wait
	## has not run out.
	WAITING,
	## new_pane(), overdue(): the wait ran out with no snapshot showing it.
	UNSEEN,
	## new_pane(): the viewer's pick is no longer the pane the write was sent from.
	OTHER_PICK,
	## new_pane(): the machine is on another connection than the write's.
	OTHER_CONNECTION,
	## new_pane(): the viewer navigated since the write, or is in answer mode.
	MOVED_ON,
}


## A new pane a write made, waited for until a snapshot shows it.
class Awaited:
	## Its composite key (HerdrFleet.pane_key), herdr's spelling of its id, and
	## the terminal herdr named for it.
	var key := ""
	var pane_id := ""
	var terminal_id := ""
	## The pane the write was sent from: the viewer's pick then.
	var from_key := ""
	## OfficeNavigator.nav_revision then: any navigation the viewer asks for
	## since (a zone picked, PageUp/PageDown, `N`, a counter, the list, NEWS,
	## EVENTS, ...) is the viewer moving on. Panning (a drag, the wheel, the
	## arrows) and herdr's focus moving are not.
	var nav_revision := 0
	## The machine's connection then (HerdrFleet.generation()).
	var generation := 0
	## When the wait runs out, on the adapter's clock.
	var until_msec := 0


## What the module remembers from one answer to the next. Never changed once
## made: an answer that remembers something else carries a new one, and one
## that changes nothing carries the one it was asked with.
class Memory:
	## PaneModel.identity_key() the pick was last carried to by started(), and
	## whether that identity had no session yet. Empty before the first; never
	## forgotten after (a pick that comes back to it is carried on as before).
	var carried := ""
	var carried_sessionless := false
	## The new pane waited for; null for none.
	var awaited: Awaited

	func _init(carried_to := "", sessionless := false, waited_for: Awaited = null) -> void:
		carried = carried_to
		carried_sessionless = sessionless
		awaited = waited_for

	## The machine whose connection new_pane() asks for (HerdrFleet.generation()):
	## the one the awaited pane is on; empty when none is waited for.
	func machine() -> String:
		return "" if awaited == null else HerdrFleet.split_key(awaited.key)[0]


## What the pick becomes, or that it does not change, and why.
class Answer:
	## What to hand back with the next question.
	var memory: Memory
	var why := Why.NOTHING_AWAITED
	## The pane the pick becomes; null when the pick does not change.
	var pane: PaneModel
	## started() only: the identity that pick is of (PaneModel.identity_key()).
	var identity := ""
	## The wait for a new pane ended without picking it, and the card says so
	## (`why` is UNSEEN, MOVED_ON or OTHER_TERMINAL): the pane the write was
	## sent from, and herdr's spelling of the new pane's id. Empty otherwise.
	var left_from := ""
	var left_pane_id := ""

	func _init(remembered: Memory, reason: Why) -> void:
		memory = remembered
		why = reason


## A write from pane `from_key` made a new pane `pane_id` (herdr's spelling)
## with terminal `terminal_id`, on its machine's connection `generation`, when
## the navigator's nav_revision was `nav_revision` and the clock read
## `now_msec`: the memory that waits `wait_msec` for a snapshot to show it. A
## new pane already waited for is forgotten, without a word.
static func new_pane_made(
	memory: Memory,
	from_key: String,
	pane_id: String,
	terminal_id: String,
	generation: int,
	nav_revision: int,
	now_msec: int,
	wait_msec: int
) -> Memory:
	var awaited := Awaited.new()
	awaited.key = HerdrFleet.pane_key(HerdrFleet.split_key(from_key)[0], pane_id)
	awaited.pane_id = pane_id
	awaited.terminal_id = terminal_id
	awaited.from_key = from_key
	awaited.nav_revision = nav_revision
	awaited.generation = generation
	awaited.until_msec = now_msec + wait_msec
	return Memory.new(memory.carried, memory.carried_sessionless, awaited)


## In a refresh, before the navigator settles. The new pane waited for is in
## `frame` with the terminal herdr named, on the same connection (`generation`
## is its machine's now, see Memory.machine()), and the viewer is still where
## the write left them (`picked_key` is the pane it was sent from, no
## navigation since, `answering` false): the pick becomes that pane
## (Answer.pane), and the wait is over. In this order: the wait ran out (as
## overdue() says); another pick, or another connection: the wait is over,
## without a word; a navigation (`nav_revision` moved) or answer mode: over,
## and the card says the viewer moved on; no snapshot shows the pane yet: the
## wait goes on; the pane with another terminal: over, and the card says so.
static func new_pane(
	memory: Memory,
	frame: OfficeFrame,
	picked_key: String,
	nav_revision: int,
	generation: int,
	answering: bool,
	now_msec: int
) -> Answer:
	var late := overdue(memory, now_msec)
	if late.why != Why.WAITING:
		return late
	var awaited := memory.awaited
	if picked_key != awaited.from_key:
		return _left(memory, Why.OTHER_PICK, false)
	if generation != awaited.generation:
		return _left(memory, Why.OTHER_CONNECTION, false)
	if nav_revision != awaited.nav_revision or answering:
		return _left(memory, Why.MOVED_ON, true)
	var pane := frame.pane(awaited.key)
	if pane == null:
		return late
	if pane.terminal_id != awaited.terminal_id:
		return _left(memory, Why.OTHER_TERMINAL, true)
	var answer := _left(memory, Why.NEW_PANE, false)
	answer.pane = pane
	return answer


## Every frame: the wait for a new pane ran out at `now_msec` with no snapshot
## showing it: it is over, and the card says so (UNSEEN). WAITING until then,
## NOTHING_AWAITED with none.
static func overdue(memory: Memory, now_msec: int) -> Answer:
	if memory.awaited == null:
		return Answer.new(memory, Why.NOTHING_AWAITED)
	if now_msec < memory.awaited.until_msec:
		return Answer.new(memory, Why.WAITING)
	return _left(memory, Why.UNSEEN, true)


## In a refresh, once the selection is settled on `pane` (null for none). A
## start from the card changes the picked pane's identity when herdr detects
## the agent, and again when the agent reports its first session: the same
## terminal, now with that agent in it. The viewer picked that shell and
## started this agent there, so the pick carries over to it (Answer.pane and
## Answer.identity), which keeps the card's answers to the agent open. Only
## this run's own start (`launch`, HerdrFleet.launch_of() of the pane) while it
## is the pane's last write (`last_write`, HerdrFleet.last_write(): the very
## ticket), in the same terminal, of the kind it named: from the shell the
## start was aimed at (herdr may not list the name yet), or on from a pick
## carried here before that has no session yet, to the agent under the start's
## own name. A session after the first (`/clear`), another kind, an agent herdr
## lists without that name, anything after another write: a new identity to
## pick again, as always, and the pick does not change.
static func started(
	memory: Memory,
	pane: PaneModel,
	picked_key: String,
	picked_identity: String,
	launch: LaunchWatch,
	last_write: CommandTicket
) -> Answer:
	if pane == null or picked_key != pane.key:
		return Answer.new(memory, Why.NOT_PICKED)
	if not picked_key.is_empty() and pane.identity_key() == picked_identity:
		return Answer.new(memory, Why.STILL_PICKED)
	if launch == null or launch.ticket == null:
		return Answer.new(memory, Why.NO_START)
	if last_write != launch.ticket:
		return Answer.new(memory, Why.WROTE_SINCE)
	if pane.terminal_id != launch.terminal_id:
		return Answer.new(memory, Why.OTHER_TERMINAL)
	if pane.provider != launch.kind:
		return Answer.new(memory, Why.OTHER_KIND)
	if picked_identity == launch.ticket.context.identity_key:
		if not pane.agent_name in ["", launch.name]:
			return Answer.new(memory, Why.OTHER_NAME)
	elif memory.carried.is_empty() or picked_identity != memory.carried:
		return Answer.new(memory, Why.NOT_FROM_START)
	elif not memory.carried_sessionless:
		return Answer.new(memory, Why.LATER_SESSION)
	elif pane.agent_name != launch.name:
		return Answer.new(memory, Why.OTHER_NAME)
	var identity := pane.identity_key()
	var sessionless := pane.session == null or pane.session.identity_key().is_empty()
	var answer := Answer.new(Memory.new(identity, sessionless, memory.awaited), Why.STARTED)
	answer.pane = pane
	answer.identity = identity
	return answer


## The wait for `memory`'s new pane is over, for `why`; `said` when the card
## says so.
static func _left(memory: Memory, why: Why, said: bool) -> Answer:
	var answer := Answer.new(Memory.new(memory.carried, memory.carried_sessionless), why)
	if said:
		answer.left_from = memory.awaited.from_key
		answer.left_pane_id = memory.awaited.pane_id
	return answer
