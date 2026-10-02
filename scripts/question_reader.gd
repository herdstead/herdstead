class_name OfficeQuestionReader
extends Node
## What a blocked agent asks, for the tooltip over its chip: one line of each
## pane's terminal, read through the fleet's typed read (HerdrFleet.context_for()
## and read_pane(), the same `pane.read` of the `detection` text the agent
## card's blocked preview asks for). herdr has no "question" field, so the line
## is an excerpt (excerpt()), never the question itself: that is on the card.
##
## Reading is not a gesture and never writes. Only the panes the office hands
## in are read: blocked ones on the shown map whose chip is on screen, on a
## machine that is live with a current snapshot; none while the terminal
## monitor or the OVERVIEW covers the world (office.gd then says none is live).
## One read at a time for the whole office (the card's own preview read is
## apart from it); the panes never read first, longest-waiting first, then the
## one read longest ago; and no pane
## is read again until REFRESH_SECONDS after its last read began, whatever that
## read brought: when a read began is forgotten only once that time has passed,
## never because the pane stopped being blocked, changed terminal or left the
## map shown, so a state that flaps or a map visited twice is not read
## again sooner. Nothing is read while the window is minimized, nor at all in
## read-only mode (the office then says so in the tooltip). A read here is never
## a look: nothing here tells the fleet a preview was shown, so it never turns
## writes back on after one ended (HerdrFleet.preview_shown() is the card's).
##
## Only the last excerpt of each pane is kept, with the terminal identity it
## was read for (PaneModel.identity_key()); a pane that stops being blocked,
## holds another terminal or session, or leaves the shown map loses it: a new
## block never shows the old question. Blocked again within REFRESH_SECONDS,
## it has no text until its next read is due.

## A pane's excerpt changed (a read came back with new text).
signal question_changed(key: String)

## No pane is read again sooner than this after its last read began.
const REFRESH_SECONDS := 10.0
## How many lines of the detection text one read asks for, as the card's does.
const LINES := 200
## The longest excerpt kept, in characters.
const EXCERPT_MAX := 120
## What the tooltip says instead of an excerpt: this office reads no pane, the
## pane has no excerpt (never read, not yet read again, or its machine dropped:
## nothing that promises a read is coming), or its asking line was empty.
const READ_ONLY_TEXT := "read-only"
const NOT_READ_TEXT := "Question not read yet"
const EMPTY_TEXT := "(no text)"


## One pane's last excerpt: which terminal it was read for, what it says, and
## when it came back (Time.get_ticks_msec()).
class Question:
	extends RefCounted
	var identity := ""
	var text := ""
	var read_msec := 0


## Whether this reader reads at all. The office turns it off for the tests that
## assert the exact request sequence of the card (OfficeScene._question_reads()).
var enabled := true
var _fleet: HerdrFleet
var _minimized: Callable
## Pane key -> the last excerpt read for it.
var _cache: Dictionary[String, Question] = {}
## Pane key -> when its last read began (Time.get_ticks_msec()), kept until
## REFRESH_SECONDS have passed, whatever became of the pane meanwhile.
var _started: Dictionary[String, int] = {}
## Pane key -> identity of every blocked pane the office last handed in.
var _blocked: Dictionary[String, String] = {}
## The one read in flight, or null.
var _ticket: CommandTicket


## `minimized` answers whether the window is minimized (FramePacer.is_minimized()).
func _init(fleet: HerdrFleet, minimized: Callable) -> void:
	_fleet = fleet
	_minimized = minimized
	name = "QuestionReader"


## The shown map as the office sees it now: every blocked pane on it, key to
## identity (`blocked`, which keeps their excerpts), the ones whose chip is on
## screen in wait order (`on_screen`, the only ones read), and whether the
## map's machine may be read (`live`: online, with a current snapshot). Starts
## a read when one is due.
func watch(blocked: Dictionary[String, String], on_screen: PackedStringArray, live: bool) -> void:
	_blocked = blocked.duplicate()
	for key: String in _cache.keys():
		if not _still(key, _cache[key].identity):
			_cache.erase(key)
	var now := Time.get_ticks_msec()
	var spacing := int(REFRESH_SECONDS * 1000.0)
	# A start is forgotten only once it no longer holds anything back, and a
	# blocked pane's is kept past that to rank it among those read longest ago.
	for key: String in _started.keys():
		if now - _started[key] >= spacing and not _blocked.has(key):
			_started.erase(key)
	if not enabled or _ticket != null or not live or _fleet == null or _fleet.read_only() or _is_minimized():
		return
	var next := ""
	for key in on_screen:
		if _blocked.has(key) and not _started.has(key):
			next = key
			break
	if next.is_empty():
		var oldest := now - spacing
		for key in on_screen:
			if _blocked.has(key) and _started.has(key) and _started[key] <= oldest:
				oldest = _started[key]
				next = key
	if not next.is_empty():
		_read(next, _blocked[next], now)


## The last excerpt of pane `key` if it was read for `identity`; null otherwise.
func question(key: String, identity: String) -> Question:
	var found: Question = _cache.get(key)
	return found if found != null and found.identity == identity else null


## Whether a read is on its way now.
func reading() -> bool:
	return _ticket != null


## The line of `text` (a pane's detection text) the tooltip says: every line
## trimmed of blanks and of box-drawing and block characters (U+2500–U+259F)
## at both ends, then the last one with a `?` in it, else the last one left
## that is not empty; at most EXCERPT_MAX characters. Empty for no such line.
static func excerpt(text: String) -> String:
	var asking := ""
	var last := ""
	for raw in text.split("\n"):
		var line := _trimmed(raw)
		if line.is_empty():
			continue
		last = line
		if line.contains("?"):
			asking = line
	return (last if asking.is_empty() else asking).left(EXCERPT_MAX)


static func _trimmed(line: String) -> String:
	var start := 0
	var end := line.length()
	while start < end and _edge(line.unicode_at(start)):
		start += 1
	while end > start and _edge(line.unicode_at(end - 1)):
		end -= 1
	return line.substr(start, end - start)


## Whitespace, or a box-drawing or block character.
static func _edge(code: int) -> bool:
	return (code >= 0x2500 and code <= 0x259F) or code <= 0x20 or code == 0xA0 or code == 0x3000


func _read(key: String, identity: String, now: int) -> void:
	_started[key] = now
	var context := _fleet.context_for(key, 0).reading(CommandContext.SOURCE_DETECTION, LINES)
	var ticket := _fleet.read_pane(context)
	_ticket = ticket
	# A ticket always finishes on a later frame, refused ones too
	# (CommandTicket.settle()), so connecting after the submit misses nothing.
	ticket.finished.connect(_on_read_finished.bind(ticket, key, identity), CONNECT_ONE_SHOT)


func _on_read_finished(ticket: CommandTicket, key: String, identity: String) -> void:
	if ticket == _ticket:
		_ticket = null
	# What came back for a pane that is no longer blocked with that terminal is dropped.
	if ticket.state != CommandTicket.State.ACCEPTED or ticket.read == null or not _still(key, identity):
		return
	var found := Question.new()
	found.identity = identity
	found.text = excerpt(ticket.read.text)
	found.read_msec = Time.get_ticks_msec()
	var was: Question = _cache.get(key)
	_cache[key] = found
	if was == null or was.text != found.text:
		question_changed.emit(key)


## Whether pane `key` is still blocked on the shown map with terminal `identity`.
func _still(key: String, identity: String) -> bool:
	return _blocked.has(key) and _blocked[key] == identity


func _is_minimized() -> bool:
	if not _minimized.is_valid():
		return false
	var answer: bool = _minimized.call()
	return answer
