class_name TerminalText
extends RefCounted
## The bound every piece of terminal text takes where it enters the office
## (invariant 9): PaneReadResult (the card's preview) and ScreenReadResult (the
## terminal monitor) both pass their text through bound(), and TerminalScreen
## caps every cluster again after it strips SGR, which can join clusters the
## entry could not see as one.
##
## A grapheme cluster is remote input with no length of its own: 300 combining
## marks on one letter, a ZWJ family 250 people long, or a row of hearts joined
## by ZWJ are each one cluster, and shaping one took the engine from seconds to
## minutes (measured on Godot 4.7.2: `a` + 300 x U+0301 over
## 45 s, 250 x (man, ZWJ) over 45 s, 120 x (heart, VS16, ZWJ) over 45 s),
## freezing the whole office. A cluster over CLUSTER_MAX code points keeps its
## first code point, its base, and drops the rest: it is drawn as its base.
## The longest real clusters stay whole: a four-person family with skin tones is
## 7 code points, a flag 2, a letter with two accents 3.

## Code points a grapheme cluster may keep; one over it keeps only its base.
const CLUSTER_MAX := 8

## Text with no code point from U+0300 on has no cluster over one code point
## but CR LF: nothing to look at.
static var _plain := RegEx.create_from_string("^[\\x{0}-\\x{2ff}]*$")
static var _server: TextServer


## `text` with every grapheme cluster over CLUSTER_MAX code points cut to its base.
static func bound(text: String) -> String:
	if text.is_empty() or _plain.search(text) != null:
		return text
	var ends := breaks(text)
	var start := 0
	var long := false
	for end in ends:
		if end - start > CLUSTER_MAX:
			long = true
			break
		start = end
	if not long:
		return text
	var pieces := PackedStringArray()
	start = 0
	for end in ends:
		pieces.append(text.substr(start, 1 if end - start > CLUSTER_MAX else end - start))
		start = end
	return "".join(pieces)


## `cluster` cut to its base when it is over CLUSTER_MAX code points.
static func capped(cluster: String) -> String:
	return cluster.substr(0, 1) if cluster.length() > CLUSTER_MAX else cluster


## Where each grapheme cluster of `text` ends, from the TextServer; one per
## code point where it has no such data.
static func breaks(text: String) -> PackedInt32Array:
	if _server == null:
		_server = TextServerManager.get_primary_interface()
	var ends := PackedInt32Array()
	if not text.is_empty() and _server != null:
		ends = _server.string_get_character_breaks(text)
	if ends.is_empty() and not text.is_empty():
		for index in text.length():
			ends.append(index + 1)
	return ends
