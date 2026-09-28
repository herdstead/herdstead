class_name TerminalKeys
extends RefCounted
## The terminal monitor's key map: one Godot key event, pressed while the
## monitor has the keyboard, as what raw mode sends for it. Pure: the monitor
## asks of() for every key event and batches what comes back; HerdrCommands
## checks every key name again at its send port (HerdrCommands.raw_key_refusal()).
##
## Printable characters are typed text (`pane.send_text`, never bracketed),
## taken from what the keyboard layout made of the key (`unicode`): this is
## typing, so an AZERTY `a` is an `a`. An input method's commit arrives the
## same way, as key events carrying the committed characters. Everything else
## is a key name in herdr's own spelling, from the table measured against
## herdr 0.9.0 (docs/WRITE_BOUNDARY.md §6): `enter`, `tab`, `shift+tab`, `backspace`, `esc`,
## arrows with Ctrl / Alt / Shift / Ctrl+Shift, `f1`–`f12`, `ctrl+<letter>`,
## `ctrl+[ \ ] ^ _ @`, `ctrl+space`, `alt+<printable>`, `alt+shift+<letter>`,
## `ctrl+alt+<letter>`, `shift+enter`, `ctrl+enter`, `alt+enter`. Home, End,
## PgUp, PgDn, Insert and Delete have no name herdr 0.9.0 takes (every spelling
## is `invalid_key`): they are refused here, and so is every chord outside the
## table, each with its reason for the status line. The Ctrl+] that closes the
## monitor and the paste chord never get here: the monitor takes them first.
## Key repeats (`echo`) are presses like any other: a terminal repeats a held key.

enum Kind {
	## Nothing to send and nothing to say: a release, or a modifier on its own.
	NONE,
	## A key name for `pane.send_keys`.
	KEY,
	## Characters for `pane.send_text`.
	TEXT,
	## Not sent; `reason` says why.
	REFUSED,
}

## Keys herdr 0.9.0 cannot be told to press (measured).
const UNREACHABLE: Array[Key] = [
	KEY_HOME,
	KEY_END,
	KEY_PAGEUP,
	KEY_PAGEDOWN,
	KEY_INSERT,
	KEY_DELETE,
	# The keypad's, with Num Lock off.
	KEY_KP_7,
	KEY_KP_1,
	KEY_KP_9,
	KEY_KP_3,
	KEY_KP_0,
	KEY_KP_PERIOD,
]
const ARROWS: Dictionary[Key, String] = {KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right"}
## Keys that are only modifiers: pressed alone they send nothing, and say nothing.
const MODIFIERS: Array[Key] = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]
## Ctrl with these sends the C0 control a terminal sends for them.
const CTRL_SYMBOLS: Dictionary[Key, String] = {
	KEY_BRACKETLEFT: "[",
	KEY_BACKSLASH: "\\",
	KEY_BRACKETRIGHT: "]",
	KEY_6: "^",
	KEY_ASCIICIRCUM: "^",
	KEY_MINUS: "_",
	KEY_UNDERSCORE: "_",
	KEY_2: "@",
	KEY_AT: "@",
}

var kind := Kind.NONE
## KEY: the key name (`ctrl+c`, `up`, `f5`).
var name := ""
## TEXT: the characters.
var text := ""
## REFUSED: why.
var reason := CommandRefusal.Reason.NONE


## What raw mode sends for `event`. A release sends nothing.
## `option_types` (a Mac, as the monitor passes it): Option with a key that makes
## a character types that character, the way Terminal.app and iTerm2 do by
## default (German Option+L is `@`, Option+7 is `|`); an Option chord that
## makes no character (a dead key: Option+U, then U types `ü`) sends nothing,
## and the composed character comes as text. Elsewhere Alt is always `alt+`.
static func of(event: InputEventKey, option_types := false) -> TerminalKeys:
	var mapped := TerminalKeys.new()
	if event == null or not event.pressed:
		return mapped
	var code := event.keycode
	if code in MODIFIERS:
		return mapped
	var ctrl := event.ctrl_pressed
	var alt := event.alt_pressed
	var shift := event.shift_pressed
	if event.meta_pressed:
		return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)
	if code in UNREACHABLE and event.unicode == 0:
		return _refused(CommandRefusal.Reason.KEY_UNREACHABLE)
	if ARROWS.has(code):
		var prefix := ""
		if ctrl and shift and not alt:
			prefix = "ctrl+shift+"
		elif ctrl and not alt and not shift:
			prefix = "ctrl+"
		elif alt and not ctrl and not shift:
			prefix = "alt+"
		elif shift and not ctrl and not alt:
			prefix = "shift+"
		elif ctrl or alt or shift:
			return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)
		return _key(prefix + ARROWS[code])
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			return _chord(
				{"": "enter", "shift": "shift+enter", "ctrl": "ctrl+enter", "alt": "alt+enter"}, ctrl, alt, shift
			)
		KEY_TAB:
			return _chord({"": "tab", "shift": "shift+tab"}, ctrl, alt, shift)
		KEY_BACKTAB:
			return _chord({"": "shift+tab", "shift": "shift+tab"}, ctrl, alt, shift)
		KEY_BACKSPACE:
			return _chord({"": "backspace"}, ctrl, alt, shift)
		KEY_ESCAPE:
			return _chord({"": "esc"}, ctrl, alt, shift)
	if code >= KEY_F1 and code <= KEY_F12:
		return _chord({"": "f%d" % (code - KEY_F1 + 1)}, ctrl, alt, shift)
	if code >= KEY_F13 and code <= KEY_F35:
		# herdr accepts f13 and sends nothing (measured): not worth a request.
		return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)
	if ctrl:
		return _control_chord(code, alt, shift)
	if alt and option_types:
		# A dead key (Option+U before `ü`) makes no character yet: nothing is
		# sent for it, and the composed character follows as its own event.
		return _text(char(event.unicode)) if _printable(event.unicode) else mapped
	if alt:
		return _alt_chord(code, shift)
	# Plain or shifted: what the layout made of the key, as text.
	if code == KEY_SPACE and event.unicode == 0:
		return _text(" ")
	var typed := event.unicode
	if _printable(typed):
		return _text(char(typed))
	if typed == 0 and code == KEY_NONE:
		return mapped
	return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)


## The name of the chord `names` has for the modifiers held ("" for none,
## "shift", "ctrl", "alt"), or KEY_UNSUPPORTED.
static func _chord(names: Dictionary, ctrl: bool, alt: bool, shift: bool) -> TerminalKeys:
	var held := PackedStringArray()
	if ctrl:
		held.append("ctrl")
	if alt:
		held.append("alt")
	if shift:
		held.append("shift")
	var wanted := "+".join(held)
	if names.has(wanted):
		return _key(str(names[wanted]))
	return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)


## Ctrl (and perhaps Alt) with a key: a letter by the layout's key, one of
## the C0 symbols, or Space.
static func _control_chord(code: Key, alt: bool, shift: bool) -> TerminalKeys:
	if shift:
		return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)
	if code >= KEY_A and code <= KEY_Z:
		var letter := char(code).to_lower()
		return _key(("ctrl+alt+" if alt else "ctrl+") + letter)
	if alt:
		return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)
	if code == KEY_SPACE:
		return _key("ctrl+space")
	if CTRL_SYMBOLS.has(code):
		return _key("ctrl+" + CTRL_SYMBOLS[code])
	return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)


## Alt with a key, as Meta: the layout's key. Never on a Mac (see of()): Esc
## then the key is the Meta workaround there.
static func _alt_chord(code: Key, shift: bool) -> TerminalKeys:
	if code >= KEY_A and code <= KEY_Z:
		var letter := char(code).to_lower()
		return _key(("alt+shift+" if shift else "alt+") + letter)
	if shift:
		return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)
	if code > 0x20 and code < 0x7F:
		return _key("alt+" + char(code))
	return _refused(CommandRefusal.Reason.KEY_UNSUPPORTED)


## A character a key may type: no control (C0, DEL, C1).
static func _printable(typed: int) -> bool:
	return typed >= 0x20 and typed != 0x7F and not (typed >= 0x80 and typed <= 0x9F)


static func _key(key_name: String) -> TerminalKeys:
	var mapped := TerminalKeys.new()
	mapped.kind = Kind.KEY
	mapped.name = key_name
	return mapped


static func _text(typed: String) -> TerminalKeys:
	var mapped := TerminalKeys.new()
	mapped.kind = Kind.TEXT
	mapped.text = typed
	return mapped


static func _refused(why: CommandRefusal.Reason) -> TerminalKeys:
	var mapped := TerminalKeys.new()
	mapped.kind = Kind.REFUSED
	mapped.reason = why
	return mapped
