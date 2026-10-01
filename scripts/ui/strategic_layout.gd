class_name StrategicLayout
extends RefCounted
## Where the strategic view (`S`) draws each pod of a machine's map and each
## seat at it, for a room of a given size: a schematic, not a map. The map's
## zones are sections, in the SPACES rail's order; a section is a caption band
## naming its zone and then that zone's pod rows (FloorPlan's, in `index` order,
## empty rows left out) top to bottom, each row's pods left to right without
## the plan's gaps. A pod keeps only its columns and its two sides (far over
## near): no plan coordinate is scaled into the room.
##
## The sections flow down newspaper columns as tall as the room. A section that
## fits a column is kept whole: in the column it starts in when what is left of
## that holds it, else in the next. One taller than the room is split at a row
## boundary, and its caption is repeated at the top of each column it runs on
## into (`continued`). A column is as wide as its widest row or caption.
##
## fit() takes the largest cell of the ladder at which that flow fits the room;
## if nothing fits even at the smallest cell, it uses that cell, the shortest
## columns the width holds, and the view scrolls vertically. Pure: no node, no
## theme lookup; the view hands in the scene's ladder and the theme's measures
## (Rules).


## The measures a fit is made with, in units: the scene's cell ladder and the
## theme's `Strategic` constants (HudTheme._strategic()).
class Rules:
	extends RefCounted
	## Cell sizes to try, largest first.
	var cells := PackedInt32Array()
	## Inside a table's box, all round.
	var pad := 0
	## Between two boxes, across and down.
	var gap := 0
	## The band above a box its tab's name is written in.
	var caption := 0
	## Between a table's far row of seats and its near one.
	var divider := 0
	## Round a square inside its cell: the square is the cell less twice this.
	var ring := 0
	## The band above a section's first row its zone is named in.
	var section := 0


## One caption band of a section: over its first row, and again at the top of
## every further column a section taller than the room runs on into.
class Heading:
	extends RefCounted
	## Which section (its place in fit()'s `sections`).
	var section := 0
	## The band, as wide as its column.
	var rect := Rect2()
	## Not the section's first: the caption says so (`3 INFRA …`).
	var continued := false


## The cell every seat was given, in units.
var cell := 0
## Newspaper columns the rows were flowed into, and the most rows one holds.
var columns := 0
var per_column := 0
## The whole schematic's extent, from its top-left corner at (0, 0).
var size := Vector2.ZERO
## Nothing fitted the room even at the smallest cell: it is taller than the room.
var scrolls := false
## Every caption band, in reading order; none when fit() was given no sections.
var headings: Array[Heading] = []

var _rules: Rules
## Every table's box, row after row, left to right; `_first[row]` is where a
## row's tables start among them.
var _boxes: Array[Rect2] = []
var _first := PackedInt32Array()


## Lay out `rows` (per view row, each table's capacity in columns, left to
## right) in a room `room` units big, by `rules`. `sections` says how many of
## those rows, in order, each section holds, and `captions` how wide each
## section's caption is drawn (a column is never narrower than a caption in
## it); without `sections` the rows are one run with no caption band.
static func fit(
	rows: Array[PackedInt32Array],
	room: Vector2,
	rules: Rules,
	sections := PackedInt32Array(),
	captions := PackedFloat32Array()
) -> StrategicLayout:
	var ladder := rules.cells.duplicate()
	ladder.sort()
	ladder.reverse()
	if ladder.is_empty():
		ladder.append(1)
	var flow := Flow.new(rows, rules, sections, captions)
	if rows.is_empty():
		return flow.laid(ladder[0], room.y)
	for tried: int in ladder:
		var laid := flow.laid(tried, room.y)
		if laid.size.x <= room.x and laid.size.y <= room.y:
			return laid
	# Nothing fits: the smallest cell, and columns only as much taller than the
	# room as it takes for them to fit its width; one column when none does.
	var smallest := ladder[ladder.size() - 1]
	var step := flow.pitch(smallest)
	var tall := room.y
	var found := flow.laid(smallest, tall)
	while found.size.x > room.x and found.columns > 1:
		tall += step
		found = flow.laid(smallest, tall)
	found.scrolls = true
	return found


## Table `table` of row `row`'s box (its frame), from the schematic's corner.
func box(row: int, table: int) -> Rect2:
	var at := _index(row, table)
	return _boxes[at] if at >= 0 else Rect2()


## The band above that box its tab's name is written in, as wide as the box.
func caption_rect(row: int, table: int) -> Rect2:
	var framed := box(row, table)
	return Rect2(framed.position - Vector2(0, _rules.caption), Vector2(framed.size.x, _rules.caption))


## The cell of seat `column` on `side` (`far` or `near`) at that table.
func cell_rect(row: int, table: int, column: int, side: String) -> Rect2:
	var framed := box(row, table)
	if not framed.has_area():
		return Rect2()
	var down := 0 if side == "far" else cell + _rules.divider
	return Rect2(framed.position + Vector2(_rules.pad + column * cell, _rules.pad + down), Vector2.ONE * cell)


## The square drawn in that cell: the cell less its ring all round.
func seat_rect(row: int, table: int, column: int, side: String) -> Rect2:
	var whole := cell_rect(row, table, column, side)
	return whole.grow(-_rules.ring) if whole.has_area() else Rect2()


## The line between a table's two rows of seats: `divider` high, as wide as
## the seats inside the pad.
func divider_rect(row: int, table: int) -> Rect2:
	var framed := box(row, table)
	return Rect2(
		framed.position + Vector2(_rules.pad, _rules.pad + cell),
		Vector2(framed.size.x - 2.0 * _rules.pad, _rules.divider)
	)


## How many tables row `row` has.
func tables_in(row: int) -> int:
	if row < 0 or row >= _first.size():
		return 0
	var end := _boxes.size() if row + 1 >= _first.size() else _first[row + 1]
	return end - _first[row]


func _index(row: int, table: int) -> int:
	if row < 0 or row >= _first.size() or table < 0 or table >= tables_in(row):
		return -1
	return _first[row] + table


## One input flowed into columns, at any cell and column height: what fit()
## tries until one fits.
class Flow:
	extends RefCounted
	var _rows: Array[PackedInt32Array]
	var _rules: Rules
	## Rows per section, in order; one section of every row when fit() had none.
	var _sections := PackedInt32Array()
	var _captions := PackedFloat32Array()
	## Whether the sections have caption bands at all.
	var _captioned := false

	func _init(
		rows: Array[PackedInt32Array], rules: Rules, sections: PackedInt32Array, captions: PackedFloat32Array
	) -> void:
		_rows = rows
		_rules = rules
		_captioned = not sections.is_empty()
		_sections = sections if _captioned else PackedInt32Array([rows.size()])
		_captions = captions

	## From one row's top to the next one's, at cell `at_cell`.
	func pitch(at_cell: int) -> float:
		return _rules.caption + _box_height(at_cell) + _rules.gap

	## The rows flowed into columns `tall` units high, at cell `at_cell`. A
	## column always takes a caption with its first row, however short `tall` is.
	func laid(at_cell: int, tall: float) -> StrategicLayout:
		var made := StrategicLayout.new()
		made._rules = _rules
		made.cell = at_cell
		if _rows.is_empty():
			return made
		var band := float(_rules.section) if _captioned else 0.0
		var unit := _rules.caption + _box_height(at_cell)
		var pen := Pen.new()
		var row := 0
		for section in _sections.size():
			var count := mini(_sections[section], _rows.size() - row)
			if count <= 0:
				continue
			var wide := _captions[section] if section < _captions.size() else 0.0
			var whole := band + count * unit + (count - 1) * _rules.gap
			var start := pen.y + (_rules.gap if pen.rows > 0 else 0)
			# Kept whole when a column holds it; else it starts here only if a
			# first row still fits under its caption.
			var fits_here := start + whole <= tall
			var fits_some := whole <= tall
			var room_for_one := start + band + unit <= tall
			if pen.rows > 0 and not fits_here and (fits_some or not room_for_one):
				pen.next_column(made, _rules.gap)
				start = 0.0
			pen.head(made, section, start, band, wide, false)
			for index in count:
				var top := pen.y + (_rules.gap if index > 0 else 0)
				if index > 0 and top + unit > tall:
					pen.next_column(made, _rules.gap)
					pen.head(made, section, 0.0, band, wide, true)
					top = pen.y
				_place(made, pen, row, top + _rules.caption, at_cell)
				pen.y = top + unit
				pen.rows += 1
				row += 1
		pen.close(made)
		made.columns = pen.column + 1
		made.size = Vector2(pen.x + pen.widest, pen.bottom)
		return made

	## Row `row`'s boxes from the pen's column edge, their tops at `y`.
	func _place(made: StrategicLayout, pen: Pen, row: int, y: float, at_cell: int) -> void:
		made._first.append(made._boxes.size())
		var high := _box_height(at_cell)
		var left := pen.x
		for capacity in _rows[row]:
			var wide := capacity * at_cell + 2.0 * _rules.pad
			made._boxes.append(Rect2(left, y, wide, high))
			left += wide + _rules.gap
		pen.widest = maxf(pen.widest, left - _rules.gap - pen.x)
		pen.bottom = maxf(pen.bottom, y + high)

	func _box_height(at_cell: int) -> float:
		return 2.0 * at_cell + _rules.divider + 2.0 * _rules.pad


## Where a flow is writing: the column, how far down it, and what the column
## holds so far.
class Pen:
	extends RefCounted
	var column := 0
	## The column's left edge, and how far down it the next thing goes.
	var x := 0.0
	var y := 0.0
	## Rows placed in this column, its widest row or caption, and the lowest
	## box bottom of all columns.
	var rows := 0
	var widest := 0.0
	var bottom := 0.0
	## The caption bands of this column, widened to it when it closes.
	var _open: Array[Heading] = []

	## A caption band for `section` at `top` of this column; none when `band` is 0.
	func head(made: StrategicLayout, section: int, top: float, band: float, wide: float, continued: bool) -> void:
		y = top + band
		if band <= 0.0:
			return
		var heading := Heading.new()
		heading.section = section
		heading.rect = Rect2(x, top, 0.0, band)
		heading.continued = continued
		made.headings.append(heading)
		_open.append(heading)
		widest = maxf(widest, wide)
		bottom = maxf(bottom, y)

	## This column is done: its captions are as wide as it is.
	func close(made: StrategicLayout) -> void:
		for heading in _open:
			heading.rect.size.x = widest
		_open.clear()
		made.per_column = maxi(made.per_column, rows)

	func next_column(made: StrategicLayout, gap: float) -> void:
		close(made)
		x += widest + gap
		y = 0.0
		rows = 0
		widest = 0.0
		column += 1
