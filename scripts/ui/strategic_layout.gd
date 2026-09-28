class_name StrategicLayout
extends RefCounted
## Where the strategic view (`S`) draws each table of a floor and each seat at
## it, for a room of a given size: a schematic, not a map. The floor plan's rows
## (FloorPlan.rows in `index` order, empty rows left out) run top to bottom,
## each row's tables left to right without the plan's gaps, and a table keeps
## only its columns and its two sides (far over near): no plan coordinate is
## scaled into the room. A floor with more rows than the room is tall wraps them
## into side-by-side columns, newspaper style, in order.
##
## fit() takes the largest cell of the ladder at which every row fits the room
## and, at that cell, the fewest newspaper columns; if nothing fits even at the
## smallest cell, it uses that cell, as many columns as the width holds, and
## the view scrolls vertically. Pure: no node, no theme lookup; the view hands
## in the scene's ladder and the theme's measures (Rules).


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


## The cell every seat was given, in units.
var cell := 0
## Newspaper columns the rows were wrapped into, and how many rows each holds.
var columns := 0
var per_column := 0
## The whole schematic's extent, from its top-left corner at (0, 0).
var size := Vector2.ZERO
## Nothing fitted the room even at the smallest cell: it is taller than the room.
var scrolls := false

var _rules: Rules
## Every table's box, row after row, left to right; `_first[row]` is where a
## row's tables start among them.
var _boxes: Array[Rect2] = []
var _first := PackedInt32Array()


## Lay out `rows` (per plan row, each table's capacity in columns, left to
## right) in a room `room` units big, by `rules`.
static func fit(rows: Array[PackedInt32Array], room: Vector2, rules: Rules) -> StrategicLayout:
	var ladder := rules.cells.duplicate()
	ladder.sort()
	ladder.reverse()
	if ladder.is_empty():
		ladder.append(1)
	if rows.is_empty():
		return _laid(rows, ladder[0], 0, rules, false)
	for tried: int in ladder:
		var height_room := room.y
		for wanted in range(1, rows.size() + 1):
			var per := ceili(rows.size() / float(wanted))
			var used := ceili(rows.size() / float(per))
			if _height(per, tried, rules) > height_room:
				continue
			if _width(rows, per, tried, rules) <= room.x:
				return _laid(rows, tried, used, rules, false)
	var smallest := ladder[ladder.size() - 1]
	var most := 1
	for wanted in range(rows.size(), 0, -1):
		var per := ceili(rows.size() / float(wanted))
		if _width(rows, per, smallest, rules) <= room.x:
			most = ceili(rows.size() / float(per))
			break
	return _laid(rows, smallest, most, rules, true)


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


static func _laid(rows: Array[PackedInt32Array], at_cell: int, used: int, rules: Rules, over: bool) -> StrategicLayout:
	var laid := StrategicLayout.new()
	laid._rules = rules
	laid.cell = at_cell
	laid.scrolls = over
	if rows.is_empty() or used <= 0:
		return laid
	var per := ceili(rows.size() / float(used))
	laid.per_column = per
	laid.columns = ceili(rows.size() / float(per))
	var high := _box_height(at_cell, rules)
	var x := 0.0
	var bottom := 0.0
	for column in laid.columns:
		var widest := 0.0
		for slot in per:
			var row := column * per + slot
			if row >= rows.size():
				break
			laid._first.append(laid._boxes.size())
			var y := slot * (rules.caption + high + rules.gap) + rules.caption
			var left := x
			for capacity in rows[row]:
				var wide := _box_width(capacity, at_cell, rules)
				laid._boxes.append(Rect2(left, y, wide, high))
				left += wide + rules.gap
			widest = maxf(widest, left - rules.gap - x)
			bottom = maxf(bottom, y + high)
		x += widest + rules.gap
	laid.size = Vector2(x - rules.gap, bottom)
	return laid


static func _box_width(capacity: int, at_cell: int, rules: Rules) -> float:
	return capacity * at_cell + 2.0 * rules.pad


static func _box_height(at_cell: int, rules: Rules) -> float:
	return 2.0 * at_cell + rules.divider + 2.0 * rules.pad


## `per` rows down a column, each a caption over a box, a gap between them.
static func _height(per: int, at_cell: int, rules: Rules) -> float:
	return per * (rules.caption + _box_height(at_cell, rules)) + (per - 1) * rules.gap


## Every column of `per` rows side by side, each as wide as its widest row.
static func _width(rows: Array[PackedInt32Array], per: int, at_cell: int, rules: Rules) -> float:
	var total := 0.0
	var column := 0
	while column * per < rows.size():
		var widest := 0.0
		for row in range(column * per, mini(rows.size(), (column + 1) * per)):
			var wide := -float(rules.gap)
			for capacity in rows[row]:
				wide += _box_width(capacity, at_cell, rules) + rules.gap
			widest = maxf(widest, wide)
		total += widest + (rules.gap if column > 0 else 0)
		column += 1
	return total
