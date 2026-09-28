class_name JsonText
extends RefCounted
## JSON text that any strict parser reads, whatever its strings hold: what
## Herdstead writes for herdr (HerdrClient.request_line()) and for its own saved
## looks (AgentCatalog). Neither owns it; both use the same one.

## What a JSON string must not carry raw, plus DEL: encode() writes each as
## a \u00XX escape. JSON.stringify() leaves most of them raw and writes 0x0B as
## `\v`, which is no JSON escape at all (measured on 4.7.2), so a request naming
## such a pane id was invalid JSON: herdr refused the subscription and the
## machine went offline for good. Compiled once; most text holds none of them.
static var _json_unsafe := RegEx.create_from_string("[\\x{0}-\\x{1f}\\x{7f}]")


## `value` as JSON that any strict parser accepts: what JSON.stringify() writes,
## except that every string goes through string(); compact, in the
## dictionaries' own key order. `full_precision` writes every float so it reads
## back as the same double (AgentCatalog's saved file).
static func encode(value: Variant, full_precision := false) -> String:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return string(str(value))
		TYPE_DICTIONARY:
			var data: Dictionary = value
			var members := PackedStringArray()
			for key: Variant in data:
				members.append(string(str(key)) + ":" + encode(data[key], full_precision))
			return "{" + ",".join(members) + "}"
		TYPE_ARRAY:
			var items: Array = value
			var encoded := PackedStringArray()
			for item: Variant in items:
				encoded.append(encode(item, full_precision))
			return "[" + ",".join(encoded) + "]"
		TYPE_PACKED_STRING_ARRAY:
			var texts: PackedStringArray = value
			var quoted := PackedStringArray()
			for text in texts:
				quoted.append(string(text))
			return "[" + ",".join(quoted) + "]"
	return JSON.stringify(value, "", false, full_precision)


## `text` as a JSON string literal: JSON.stringify()'s own quoting when nothing
## in it needs more, and otherwise every C0 character and DEL as \u00XX.
static func string(text: String) -> String:
	if _json_unsafe.search(text) == null:
		return JSON.stringify(text)
	var out := '"'
	for character in text:
		var code := character.unicode_at(0)
		if character == '"' or character == "\\":
			out += "\\" + character
		elif code < 0x20 or code == 0x7f:
			out += "\\u%04x" % code
		else:
			out += character
	return out + '"'
