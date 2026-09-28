class_name ScreenReadResult
extends RefCounted
## What herdr answered the terminal monitor's read with: a pane's screen
## (`visible`) or recent output (`recent`), with its colours. `from_wire()` is
## the one place that reads herdr's raw `pane_read` result for the monitor; the
## transport has already refused a reply line over its cap, so only a whole,
## bounded line ever reaches it.
##
## Terminal text is remote input (invariant 9) and never leaves this object for
## a log or the audit: those keep `source`, `bytes` and the two truncation
## flags only. Its grapheme clusters are bounded (TerminalText.bound()).
## herdr 0.9.0 normalises `ansi` to SGR sequences and CRLF
## (measured); everything else a terminal could act on is dropped here, and
## TerminalScreen interprets nothing but SGR.

## Decoded text over this many UTF-8 bytes keeps only its last this many: a
## 999-line `recent` measured about 72 KB.
const TEXT_MAX := 262144
## The format the monitor asks for, and the only one it takes back.
const FORMAT := "ansi"

## What from_wire() drops: C0 but ESC, CR, LF and TAB, DEL, C1, U+2028,
## U+2029 and the bidi controls U+202A–U+202E and U+2066–U+2069.
static var _control := RegEx.create_from_string(
	"[\\x{0}-\\x{8}\\x{b}\\x{c}\\x{e}-\\x{1a}\\x{1c}-\\x{1f}\\x{7f}-\\x{9f}\\x{2028}-\\x{202e}\\x{2066}-\\x{2069}]"
)

## The pane id herdr answered for, exactly as it spelled it.
var pane_id := ""
## `visible` or `recent`.
var source := ""
## The text with its SGR sequences, cleaned, at most TEXT_MAX UTF-8 bytes.
var text := ""
## herdr cut the text itself (its own `truncated`).
var truncated := false
## This office cut it: over TEXT_MAX, so only its tail is kept.
var cut := false
## UTF-8 bytes of the text as herdr sent it, before any cut or cleaning.
var bytes := 0
## herdr's `revision`; 0 in every read measured on 0.9.0, so nothing relies on it.
var revision := 0


## A `pane_read` result (the object under the reply's `result`) in `ansi`; null
## when it is not one, is another format, or names another pane than `wire_pane_id`.
static func from_wire(result: Variant, wire_pane_id: String) -> ScreenReadResult:
	if not result is Dictionary:
		return null
	var envelope: Dictionary = result
	if not envelope.get("read") is Dictionary:
		return null
	var read: Dictionary = envelope.get("read")
	if not read.get("pane_id") is String or not read.get("text") is String:
		return null
	var answered: String = read.get("pane_id")
	if answered != wire_pane_id:
		return null
	if read.get("format") != FORMAT:
		return null
	var parsed := ScreenReadResult.new()
	parsed.pane_id = answered
	parsed.source = MachineRoster.clean_text(read.get("source"))
	var flag: Variant = read.get("truncated")
	parsed.truncated = flag is bool and flag == true
	var number: Variant = read.get("revision")
	if number is float:
		var fraction: float = number
		if fraction >= 0.0 and fraction <= 9.0e15:
			parsed.revision = int(fraction)
	elif number is int:
		var whole: int = number
		parsed.revision = maxi(0, whole)
	var raw: String = read.get("text")
	var encoded := raw.to_utf8_buffer()
	parsed.bytes = encoded.size()
	if encoded.size() > TEXT_MAX:
		parsed.cut = true
		raw = PaneReadResult.tail(encoded, TEXT_MAX)
	parsed.text = TerminalText.bound(clean(raw))
	return parsed


## `raw` without the controls the monitor never interprets (see _control).
static func clean(raw: String) -> String:
	if _control.search(raw) == null:
		return raw
	return _control.sub(raw, "", true)
