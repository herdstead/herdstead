class_name PaneReadResult
extends RefCounted
## What herdr answered a terminal read with, as the agent card shows it.
## `from_wire()` is the one place that reads herdr's raw `pane_read` result;
## the transport has already refused a reply line over its cap, so only a whole,
## bounded line ever reaches it.
##
## Terminal text is remote input (invariant 9): its grapheme clusters are
## bounded (TerminalText.bound()), and it never leaves this object for a log or
## the audit: those keep `source`, `lines`, `bytes` and the two
## truncation flags only.

## Decoded text over this many UTF-8 bytes keeps only its last this many.
const TEXT_MAX := 65536

## What from_wire() drops: MachineRoster.clean_text()'s set minus `\n` and
## `\t`, which a terminal row needs (C0 but those two, DEL, C1, U+2028, U+2029
## and the bidi controls U+202A–U+202E and U+2066–U+2069, which could reorder
## what a row shows).
static var _control := RegEx.create_from_string(
	"[\\x{0}-\\x{8}\\x{b}-\\x{1f}\\x{7f}-\\x{9f}\\x{2028}-\\x{202e}\\x{2066}-\\x{2069}]"
)

## The pane id herdr answered for, exactly as it spelled it.
var pane_id := ""
## Which of herdr's sources this is: `detection` or `recent_unwrapped`.
var source := ""
## The text, cleaned, at most TEXT_MAX UTF-8 bytes.
var text := ""
## herdr cut the text itself (its own `truncated`).
var truncated := false
## This office cut it: the decoded text was over TEXT_MAX, so only its tail is kept.
var cut := false
## UTF-8 bytes of the text as herdr sent it, before any cut or cleaning.
var bytes := 0


## A `pane_read` result (the object under the reply's `result`) as the card
## reads it; null when it is not one, or names another pane than `wire_pane_id`.
static func from_wire(result: Variant, wire_pane_id: String) -> PaneReadResult:
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
	var parsed := PaneReadResult.new()
	parsed.pane_id = answered
	parsed.source = MachineRoster.clean_text(read.get("source"))
	var flag: Variant = read.get("truncated")
	parsed.truncated = flag is bool and flag == true
	var raw: String = read.get("text")
	var encoded := raw.to_utf8_buffer()
	parsed.bytes = encoded.size()
	if encoded.size() > TEXT_MAX:
		parsed.cut = true
		raw = tail(encoded, TEXT_MAX)
	parsed.text = TerminalText.bound(clean(raw))
	return parsed


## `raw` without the controls this office never shows (see _control).
static func clean(raw: String) -> String:
	if _control.search(raw) == null:
		return raw
	return _control.sub(raw, "", true)


## The last `limit` bytes of UTF-8 `encoded`, decoded, starting at a character
## boundary: continuation bytes (0b10xxxxxx) a cut lands in are skipped.
static func tail(encoded: PackedByteArray, limit: int) -> String:
	if encoded.size() <= limit:
		return encoded.get_string_from_utf8()
	var start := encoded.size() - limit
	while start < encoded.size() and (encoded[start] & 0xC0) == 0x80:
		start += 1
	return encoded.slice(start).get_string_from_utf8()
