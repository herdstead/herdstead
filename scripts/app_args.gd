class_name AppArgs
extends RefCounted
## The command line after `--`, read once for the four scenes — the office, the
## showroom, the pixel people showroom and the Avatar Studio — as
## `--name=value` options and bare `--name` flags. A repeated option takes its
## last value.
##
## Three parsers stay with what they configure and read `raw` themselves:
## HerdrClient (`--socket=`), MachineRoster (`--machine-socket=`) and FramePacer
## (`--fps=`). Tool scripts under tools/ keep their own.
##
## `--read-only` is the one flag also looked for before `--`: Godot keeps an
## argument it does not know in its own list, and an office told to be
## read-only must never run as an operator because the flag landed on the wrong
## side. A misspelling of it is refused outright (problems()), since guessing
## wrong would give the office a write it was told not to have.

## The one spelling of the read-only switch.
const READ_ONLY := "--read-only"
## What a flag may have been typed or pasted with in place of `-`: the Unicode
## hyphens and dashes (an editor turns `--` into an em dash), the minus sign,
## and the small and full-width hyphen-minus.
const DASHES := "-\u2010\u2011\u2012\u2013\u2014\u2015\u2212\ufe63\uff0d"

## Every argument as it was given, for those parsers.
var raw := PackedStringArray()
## The engine's own arguments (before `--`), for `--read-only` only.
var engine := PackedStringArray()
var _values: Dictionary[String, String] = {}
var _flags: Dictionary[String, bool] = {}


static func parse(arguments: PackedStringArray, engine_arguments := PackedStringArray()) -> AppArgs:
	var result := AppArgs.new()
	result.raw = arguments
	result.engine = engine_arguments
	for argument in arguments:
		if not argument.begins_with("--"):
			continue
		var cut := argument.find("=")
		if cut < 0:
			result._flags[argument.substr(2)] = true
		else:
			result._values[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	return result


## This process's own command line.
static func current() -> AppArgs:
	return parse(OS.get_cmdline_user_args(), OS.get_cmdline_args())


## Whether `--name=` was given, with any value, an empty one included.
func has(name: String) -> bool:
	return _values.has(name)


## The value of `--name=`, or `fallback` when it was not given.
func text(name: String, fallback := "") -> String:
	return _values[name] if _values.has(name) else fallback


## `--name=` as a whole number: String.to_int(), so a word reads as 0.
func number(name: String, fallback: int) -> int:
	return _values[name].to_int() if _values.has(name) else fallback


## `--name=` as a number with a fraction: String.to_float(), so a word reads as 0.
func decimal(name: String, fallback: float) -> float:
	return _values[name].to_float() if _values.has(name) else fallback


## Whether the bare flag `--name` was given (`--name=…` is an option, not this).
func flag(name: String) -> bool:
	return _flags.has(name)


## `--read-only`, after `--` or before it.
func read_only() -> bool:
	return READ_ONLY in raw or READ_ONLY in engine


## What on this command line must stop the office before it starts: an argument
## that looks like a try at `--read-only` but is not exactly it. Any run of
## dashes of any kind, then `read` in any case: `--readonly`, `--read-only=yes`,
## `--Read-Only`, `-read-only`, an em-dashed `read-only`. Empty when there is nothing.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	for argument in raw + engine:
		if argument != READ_ONLY and _tries_read_only(argument):
			found.append("%s is not %s; not guessing whether this office may write to herdr" % [argument, READ_ONLY])
	return found


static func _tries_read_only(argument: String) -> bool:
	var at := 0
	while at < argument.length() and DASHES.contains(argument[at]):
		at += 1
	return at > 0 and argument.substr(at).to_lower().begins_with("read")
