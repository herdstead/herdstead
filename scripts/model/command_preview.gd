class_name CommandPreview
extends RefCounted
## The terminal text a write was aimed at, frozen at the press: what the agent
## card showed, from which read, for which binding. An input command carries
## one (CommandContext.keying() / replying()), and HerdrCommands re-reads the
## same source right before it writes: only a re-read with the same cleaned
## text and the same byte count, not cut, lets the write go
## (docs/WRITE_BOUNDARY.md §1 rule 5). That narrows the window between seeing and sending; it never
## closes it: the screen can still change after the re-read.
##
## Immutable, like CommandContext: of() fills it in and every field refuses to
## be written after. Holds terminal text, so nothing here ever reaches a log or
## the audit: those keep `bytes` only.

## Composite pane key and PaneModel.identity_key() of the read.
var pane_key: String:
	get:
		return _pane_key
	set(_value):
		_refuse("pane_key")
var identity_key: String:
	get:
		return _identity_key
	set(_value):
		_refuse("identity_key")
## The card's binding version the read belonged to.
var binding: int:
	get:
		return _binding
	set(_value):
		_refuse("binding")
## The card's own sequence number of the read whose text was shown.
var read_seq: int:
	get:
		return _read_seq
	set(_value):
		_refuse("read_seq")
## herdr's read source and how many lines were asked for; the re-read asks the same.
var source: String:
	get:
		return _source
	set(_value):
		_refuse("source")
var lines: int:
	get:
		return _lines
	set(_value):
		_refuse("lines")
## The cleaned text (PaneReadResult.text).
var text: String:
	get:
		return _text
	set(_value):
		_refuse("text")
## UTF-8 bytes herdr sent, before any cut or cleaning (PaneReadResult.bytes).
var bytes: int:
	get:
		return _bytes
	set(_value):
		_refuse("bytes")
## herdr or this office cut the text: never a basis for a write.
var cut: bool:
	get:
		return _cut
	set(_value):
		_refuse("cut")

var _pane_key := ""
var _identity_key := ""
var _binding := 0
var _read_seq := 0
var _source := ""
var _lines := 0
var _text := ""
var _bytes := 0
var _cut := false


## What an accepted read showed, as sequence `seq` of its card; null for a
## ticket that is not an accepted read.
static func of(ticket: CommandTicket, seq: int) -> CommandPreview:
	if ticket == null or ticket.context == null or ticket.read == null:
		return null
	if ticket.context.kind != CommandContext.Kind.READ or ticket.state != CommandTicket.State.ACCEPTED:
		return null
	var frozen := CommandPreview.new()
	frozen._pane_key = ticket.context.pane_key
	frozen._identity_key = ticket.context.identity_key
	frozen._binding = ticket.context.binding
	frozen._read_seq = seq
	frozen._source = ticket.context.source
	frozen._lines = ticket.context.lines
	frozen._text = ticket.read.text
	frozen._bytes = ticket.read.bytes
	frozen._cut = ticket.read.cut or ticket.read.truncated
	return frozen


## Whether `read` shows exactly this: the same cleaned text and byte count,
## and neither of them cut.
func matches(read: PaneReadResult) -> bool:
	if read == null or _cut or read.cut or read.truncated:
		return false
	return read.bytes == _bytes and read.text == _text


func _refuse(field: String) -> void:
	push_error("CommandPreview is immutable; %s was not changed" % field)
