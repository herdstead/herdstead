class_name TerminalScreen
extends RefCounted
## A terminal's screen as the monitor draws it: `columns` x `rows` cells, each a
## grapheme cluster with its colours and attributes, parsed from what herdr's
## `pane.read` returns in `ansi` (ScreenReadResult.text). Pure: no node, no
## font; TerminalMonitorGrid draws it.
##
## herdr 0.9.0 normalises that text to SGR sequences and CRLF (measured), so
## this is an SGR state machine plus a line split: any other escape
## sequence is skipped whole, any other control dropped. The subset: 0, 1, 2,
## 3, 4, 7, 9, 21, 22, 23, 24, 27, 29, 30–37, 90–97, 39, 40–47, 100–107, 49,
## and 38 / 48 with `;5;n` or `;2;r;g;b`.
##
## Each row is kept as packed arrays, and a row is parsed again only when its
## text or the attributes it starts with changed: a screen where one line
## moved costs one line. A cell's width is its cluster's east_asian_width (2
## for Wide and Fullwidth, and for emoji presentation), clusters come from the
## TextServer (combining marks, ZWJ sequences, skin tones and flags are one
## cell each), and a wide cell's right half is a continuation that draws nothing.
## A cluster over TerminalText.CLUSTER_MAX code points is drawn as its base.

## Colours are ints: DEFAULT, a palette index 0–255, or RGB | RGB_FLAG.
const DEFAULT := -1
const RGB_FLAG := 0x1000000
## Cell flags.
const BOLD := 1
const DIM := 2
const ITALIC := 4
const UNDERLINE := 8
const REVERSE := 16
const STRIKE := 32
## The left half of a two-column cluster.
const WIDE := 64
## The right half of one: nothing is drawn there but its background.
const CONTINUATION := 128
## Columns a tab stops at.
const TAB := 8
## Wide and Fullwidth code points (Unicode 15 EastAsianWidth.txt, W and F),
## emoji with default emoji presentation included, as [first, last] pairs.
const WIDE_RANGES: Array[int] = [
	0x1100,
	0x115F,
	0x231A,
	0x231B,
	0x2329,
	0x232A,
	0x23E9,
	0x23EC,
	0x23F0,
	0x23F0,
	0x23F3,
	0x23F3,
	0x25FD,
	0x25FE,
	0x2614,
	0x2615,
	0x2648,
	0x2653,
	0x267F,
	0x267F,
	0x2693,
	0x2693,
	0x26A1,
	0x26A1,
	0x26AA,
	0x26AB,
	0x26BD,
	0x26BE,
	0x26C4,
	0x26C5,
	0x26CE,
	0x26CE,
	0x26D4,
	0x26D4,
	0x26EA,
	0x26EA,
	0x26F2,
	0x26F3,
	0x26F5,
	0x26F5,
	0x26FA,
	0x26FA,
	0x26FD,
	0x26FD,
	0x2705,
	0x2705,
	0x270A,
	0x270B,
	0x2728,
	0x2728,
	0x274C,
	0x274C,
	0x274E,
	0x274E,
	0x2753,
	0x2755,
	0x2757,
	0x2757,
	0x2795,
	0x2797,
	0x27B0,
	0x27B0,
	0x27BF,
	0x27BF,
	0x2B1B,
	0x2B1C,
	0x2B50,
	0x2B50,
	0x2B55,
	0x2B55,
	0x2E80,
	0x303E,
	0x3041,
	0x33FF,
	0x3400,
	0x4DBF,
	0x4E00,
	0x9FFF,
	0xA000,
	0xA4CF,
	0xA960,
	0xA97F,
	0xAC00,
	0xD7A3,
	0xF900,
	0xFAFF,
	0xFE10,
	0xFE19,
	0xFE30,
	0xFE6F,
	0xFF00,
	0xFF60,
	0xFFE0,
	0xFFE6,
	0x16FE0,
	0x18CFF,
	0x1B000,
	0x1B2FF,
	0x1F004,
	0x1F004,
	0x1F0CF,
	0x1F0CF,
	0x1F18E,
	0x1F18E,
	0x1F191,
	0x1F19A,
	0x1F1E6,
	0x1F1FF,
	0x1F200,
	0x1F251,
	0x1F260,
	0x1F265,
	0x1F300,
	0x1F320,
	0x1F32D,
	0x1F335,
	0x1F337,
	0x1F37C,
	0x1F37E,
	0x1F393,
	0x1F3A0,
	0x1F3CA,
	0x1F3CF,
	0x1F3D3,
	0x1F3E0,
	0x1F3F0,
	0x1F3F4,
	0x1F3F4,
	0x1F3F8,
	0x1F43E,
	0x1F440,
	0x1F440,
	0x1F442,
	0x1F4FC,
	0x1F4FF,
	0x1F53D,
	0x1F54B,
	0x1F54E,
	0x1F550,
	0x1F567,
	0x1F57A,
	0x1F57A,
	0x1F595,
	0x1F596,
	0x1F5A4,
	0x1F5A4,
	0x1F5FB,
	0x1F64F,
	0x1F680,
	0x1F6C5,
	0x1F6CC,
	0x1F6CC,
	0x1F6D0,
	0x1F6D2,
	0x1F6D5,
	0x1F6D7,
	0x1F6DC,
	0x1F6DF,
	0x1F6EB,
	0x1F6EC,
	0x1F6F4,
	0x1F6FC,
	0x1F7E0,
	0x1F7EB,
	0x1F7F0,
	0x1F7F0,
	0x1F90C,
	0x1F93A,
	0x1F93C,
	0x1F945,
	0x1F947,
	0x1F9FF,
	0x1FA70,
	0x1FAFF,
	0x20000,
	0x2FFFD,
	0x30000,
	0x3FFFD,
]
## The emoji presentation selector: a cluster holding it is two columns wide.
const VS16 := 0xFE0F

var columns := 0
var rows := 0
## Per row: what each cell draws ("" for a blank or a continuation).
var glyphs: Array[PackedStringArray] = []
var fg: Array[PackedInt32Array] = []
var bg: Array[PackedInt32Array] = []
var flags: Array[PackedInt32Array] = []
## Rows parsed again by the last set_lines() / set_text(), and in all.
var reparsed := 0
var reparsed_total := 0

## Per row: the text it was parsed from, and the attributes it started and
## ended with ("fg,bg,flags"): the row cache.
var _raw := PackedStringArray()
var _enter := PackedStringArray()
var _exit := PackedStringArray()


## The attributes text is drawn with while a row is parsed.
class Pen:
	var fore := DEFAULT
	var back := DEFAULT
	var marks := 0

	static func of(encoded: String) -> Pen:
		var parts := encoded.split(",")
		var pen := Pen.new()
		pen.fore = parts[0].to_int()
		pen.back = parts[1].to_int()
		pen.marks = parts[2].to_int()
		return pen

	func key() -> String:
		return "%d,%d,%d" % [fore, back, marks]


func _init(width := 80, height := 24) -> void:
	resize(width, height)


## Start over at `width` x `height` cells, every row blank and uncached.
func resize(width: int, height: int) -> void:
	columns = maxi(1, width)
	rows = maxi(1, height)
	glyphs.clear()
	fg.clear()
	bg.clear()
	flags.clear()
	_raw.clear()
	_enter.clear()
	_exit.clear()
	for _row in rows:
		var blank := PackedStringArray()
		blank.resize(columns)
		glyphs.append(blank)
		var colours := PackedInt32Array()
		colours.resize(columns)
		colours.fill(DEFAULT)
		fg.append(colours)
		bg.append(colours.duplicate())
		var none := PackedInt32Array()
		none.resize(columns)
		flags.append(none)
		# No attributes a row starts with read "": the first set_lines() parses every row.
		_raw.append("")
		_enter.append("")
		_exit.append(Pen.new().key())


## Show `ansi` (herdr's `visible` text): whether any row changed.
func set_text(ansi: String) -> bool:
	return set_lines(ansi.split("\n"))


## Show `lines` from the top, one per row, the rest blank: whether any row
## changed. Rows past the last line are blank; lines past the last row are not shown.
func set_lines(lines: PackedStringArray) -> bool:
	reparsed = 0
	var enter := Pen.new().key()
	for row in rows:
		var raw := lines[row] if row < lines.size() else ""
		if raw != _raw[row] or enter != _enter[row]:
			var pen := Pen.of(enter)
			_parse_row(row, raw, pen)
			_raw[row] = raw
			_enter[row] = enter
			_exit[row] = pen.key()
			reparsed += 1
		enter = _exit[row]
	reparsed_total += reparsed
	return reparsed > 0


## Row `row` as plain text: every cluster, continuations skipped, trailing
## blanks trimmed. For tests and the capture captions; never logged.
func row_text(row: int) -> String:
	if row < 0 or row >= rows:
		return ""
	var parts := PackedStringArray()
	for column in columns:
		if flags[row][column] & CONTINUATION:
			continue
		var glyph := glyphs[row][column]
		parts.append(" " if glyph.is_empty() else glyph)
	return "".join(parts).strip_edges(false, true)


## The column a cluster starts at in row `row`, or -1: where `glyph` sits.
func column_of(row: int, glyph: String) -> int:
	if row < 0 or row >= rows:
		return -1
	return glyphs[row].find(glyph)


## Columns `cluster` takes: 0, 1 or 2.
static func width_of(cluster: String) -> int:
	if cluster.is_empty():
		return 0
	var first := cluster.unicode_at(0)
	if first < 0x20:
		return 0
	if first < 0x300:
		return 1
	if _zero_width(first) and cluster.length() == 1:
		return 0
	for index in cluster.length():
		if cluster.unicode_at(index) == VS16:
			return 2
	return 2 if is_wide(first) else 1


## Whether code point `code` is Wide or Fullwidth.
static func is_wide(code: int) -> bool:
	if code < 0x1100:
		return false
	var low := 0
	var high := (WIDE_RANGES.size() >> 1) - 1
	while low <= high:
		var middle := (low + high) >> 1
		if code < WIDE_RANGES[middle * 2]:
			high = middle - 1
		elif code > WIDE_RANGES[middle * 2 + 1]:
			low = middle + 1
		else:
			return true
	return false


## Combining marks, joiners and selectors that take no column on their own.
static func _zero_width(code: int) -> bool:
	if code >= 0x300 and code <= 0x36F:
		return true
	if code >= 0x200B and code <= 0x200F:
		return true
	if code >= 0xFE00 and code <= 0xFE0F:
		return true
	if code >= 0x1AB0 and code <= 0x1AFF or code >= 0x1DC0 and code <= 0x1DFF or code >= 0x20D0 and code <= 0x20FF:
		return true
	return code >= 0xFE20 and code <= 0xFE2F or code >= 0x1F3FB and code <= 0x1F3FF or code >= 0xE0000


## Parse `raw` into row `row`, starting with the attributes of `pen`, which
## ends up holding the ones the row ends with.
func _parse_row(row: int, raw: String, pen: Pen) -> void:
	var cells := glyphs[row]
	var fore := fg[row]
	var back := bg[row]
	var marks := flags[row]
	cells.fill("")
	fore.fill(DEFAULT)
	back.fill(DEFAULT)
	marks.fill(0)
	# First the visible text and the attributes of each of its code points.
	var plain := PackedStringArray()
	var styles := PackedInt32Array()
	var column := 0
	var index := 0
	var length := raw.length()
	while index < length:
		var code := raw.unicode_at(index)
		if code == 0x1B:
			index = _escape(raw, index, pen)
			continue
		index += 1
		if code == 0x09:
			var stop := column - column % TAB + TAB
			while column < stop:
				plain.append(" ")
				styles.append_array([pen.fore, pen.back, pen.marks])
				column += 1
			continue
		if code < 0x20 or code == 0x7F:
			continue
		plain.append(char(code))
		styles.append_array([pen.fore, pen.back, pen.marks])
		column += 1
	# Then clusters onto columns.
	var text := "".join(plain)
	var ends := TerminalText.breaks(text)
	var at := 0
	var start := 0
	for end in ends:
		# Capped again here: SGR between cells no longer splits what it joins.
		var cluster := TerminalText.capped(text.substr(start, end - start))
		var style := start * 3
		start = end
		var width := width_of(cluster)
		if width == 0:
			continue
		if at + width > columns:
			break
		cells[at] = "" if cluster == " " else cluster
		fore[at] = styles[style]
		back[at] = styles[style + 1]
		marks[at] = styles[style + 2] | (WIDE if width == 2 else 0)
		if width == 2:
			back[at + 1] = styles[style + 1]
			marks[at + 1] = (styles[style + 2] & ~WIDE) | CONTINUATION
		at += width
	glyphs[row] = cells
	fg[row] = fore
	bg[row] = back
	flags[row] = marks


## Skip the escape sequence at `index` of `raw`, applying it to `state` when it
## is SGR; the index after it.
static func _escape(raw: String, index: int, pen: Pen) -> int:
	var length := raw.length()
	if index + 1 >= length or raw.unicode_at(index + 1) != 0x5B:
		# A lone ESC, or one that starts no CSI: dropped with the character after it.
		return mini(index + 2, length)
	var at := index + 2
	while at < length:
		var code := raw.unicode_at(at)
		if code >= 0x40 and code <= 0x7E:
			if code == 0x6D:
				_sgr(raw.substr(index + 2, at - index - 2), pen)
			return at + 1
		if code < 0x20 or code > 0x3F:
			# Not a CSI parameter or intermediate: the sequence is broken.
			return at
		at += 1
	return length


## Apply SGR parameters `params` ("1;38;5;208") to `pen`.
static func _sgr(params: String, pen: Pen) -> void:
	var parts := params.replace(":", ";").split(";")
	var at := 0
	while at < parts.size():
		var value := parts[at].to_int() if parts[at].is_valid_int() else 0
		at += 1
		match value:
			0:
				pen.fore = DEFAULT
				pen.back = DEFAULT
				pen.marks = 0
			1:
				pen.marks |= BOLD
			2:
				pen.marks |= DIM
			3:
				pen.marks |= ITALIC
			4, 21:
				pen.marks |= UNDERLINE
			7:
				pen.marks |= REVERSE
			9:
				pen.marks |= STRIKE
			22:
				pen.marks &= ~(BOLD | DIM)
			23:
				pen.marks &= ~ITALIC
			24:
				pen.marks &= ~UNDERLINE
			27:
				pen.marks &= ~REVERSE
			29:
				pen.marks &= ~STRIKE
			39:
				pen.fore = DEFAULT
			49:
				pen.back = DEFAULT
			38, 48:
				var colour := DEFAULT
				if at < parts.size() and parts[at] == "5" and at + 1 < parts.size():
					colour = clampi(parts[at + 1].to_int(), 0, 255)
					at += 2
				elif at < parts.size() and parts[at] == "2" and at + 3 < parts.size():
					var red := clampi(parts[at + 1].to_int(), 0, 255)
					var green := clampi(parts[at + 2].to_int(), 0, 255)
					var blue := clampi(parts[at + 3].to_int(), 0, 255)
					colour = RGB_FLAG | (red << 16) | (green << 8) | blue
					at += 4
				else:
					# A colour this parser cannot read: the rest of the sequence too.
					at = parts.size()
					continue
				if value == 38:
					pen.fore = colour
				else:
					pen.back = colour
			_:
				if value >= 30 and value <= 37:
					pen.fore = value - 30
				elif value >= 90 and value <= 97:
					pen.fore = value - 90 + 8
				elif value >= 40 and value <= 47:
					pen.back = value - 40
				elif value >= 100 and value <= 107:
					pen.back = value - 100 + 8
