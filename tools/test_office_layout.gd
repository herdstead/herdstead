extends "res://tools/test_base.gd"
## Pure plans: historical seats, local growth, bounded floor coverage and paths.

## The widths a floor is first planned at in the shipped windows, narrowest to
## widest, and the stress floor at two of them.
const FURNISHED_WIDTHS: Array[int] = [11, 20, 32, 60]

var people: PixelPeople
## Made on first use by _pen().
var pen: OfficeDraw


func _initialize() -> void:
	people = PixelPeople.from_manifest(PixelPeople.MANIFEST)
	run_cases()


func _marker() -> String:
	return "OFFICE LAYOUT TESTS"


func _pane(key: String, x := -1, side := "far", order := -1) -> PaneModel:
	var pane := PaneModel.new()
	pane.key = key
	pane.pane_id = key
	pane.explicit_layout = x >= 0
	pane.table_x = x
	pane.side = side
	pane.layout_order = order
	return pane


func _room(key: String, count := 0, number := 0) -> RoomModel:
	var room := RoomModel.new()
	room.key = key
	room.tab_id = key
	room.number = number
	for index in count:
		room.panes.append(_pane("%s-%03d" % [key, index]))
	return room


func _floor(rooms: Array[RoomModel]) -> ZoneModel:
	var floor_model := ZoneModel.new()
	floor_model.key = "machine/workspace"
	floor_model.rooms = rooms
	return floor_model


## The pod rows of `plan`'s one zone (a map of one workspace).
func _rows(plan: FloorPlan) -> Array[RowPlan]:
	return plan.zones[0].rows


func _plan(floor_model: ZoneModel, previous: FloorPlan = null, policy: FloorLayoutPolicy = null) -> FloorPlan:
	var rules := policy if policy != null else FloorLayoutPolicy.new()
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	var result := OfficeFloorLayout.plan(MapModel.of(floor_model), previous, rules)
	_eq(result.problems, PackedStringArray(), "valid plan: " + "; ".join(result.problems))
	_check(result.plan != null, "plan returned")
	return result.plan


func test_projection_identity_and_missing_layout_are_tab_local() -> void:
	var snapshot := {
		"workspaces": [{"workspace_id": "w", "number": 1}],
		"tabs": [{"tab_id": "a", "workspace_id": "w", "number": 1}, {"tab_id": "b", "workspace_id": "w", "number": 2}],
		"panes":
		[
			{"pane_id": "a1", "tab_id": "a", "workspace_id": "w"},
			{"pane_id": "b1", "tab_id": "b", "workspace_id": "w"},
		],
		"layouts": []
	}
	var before := OfficeProjection.project(HerdrSnapshot.from_wire(snapshot), PackedStringArray(["unknown"]), "m")[0]
	var first := _plan(before)
	var panes: Array = snapshot.panes
	panes.insert(1, {"pane_id": "a2", "tab_id": "a", "workspace_id": "w"})
	var after := OfficeProjection.project(HerdrSnapshot.from_wire(snapshot), PackedStringArray(["unknown"]), "m")[0]
	var second := _plan(after, first)
	_eq(after.rooms[1].key, before.rooms[1].key, "tab identity stable")
	_eq(after.rooms[1].tab_id, "b", "tab id preserved")
	_eq(after.rooms[1].number, 2, "tab number preserved")
	_check(not after.rooms[1].panes[0].explicit_layout, "absence stays explicit")
	_eq(
		second.seat(HerdrFleet.pane_key("m", "b1")).geometry_signature(),
		first.seat(HerdrFleet.pane_key("m", "b1")).geometry_signature(),
		"other tab insertion cannot flip b1"
	)
	var remote := (
		OfficeProjection.project(HerdrSnapshot.from_wire(snapshot), PackedStringArray(["unknown"]), "remote")[0]
	)
	_check(remote.rooms[0].key != before.rooms[0].key, "machine participates in tab identity")


func test_projection_requires_matching_workspace_ownership() -> void:
	var raw := {
		"workspaces":
		[
			{"workspace_id": "B", "label": "Beta", "number": 2},
			{"workspace_id": "A", "label": "Alpha", "number": 1},
		],
		"tabs": [{"tab_id": "tab-A", "workspace_id": "A", "label": "Table A"}],
		"panes":
		[
			{
				"pane_id": "p",
				"workspace_id": "B",
				"tab_id": "tab-A",
				"agent": "codex",
				"agent_status": "blocked",
			}
		],
		"layouts": [{"tab_id": "tab-A", "panes": [{"pane_id": "p", "rect": {"x": 80, "y": 24}}]}],
	}
	var states := PackedStringArray(["blocked", "unknown"])
	var raw_pane: Dictionary = _list(raw, "panes")[0]
	# A conflict, a valid owner, a dangling owner and an absent owner all pass
	# through the real cleaning boundary. Layout evidence cannot resolve ownership.
	for owner: String in ["B", "A", "missing", ""]:
		raw_pane.workspace_id = owner
		var clean := HerdrSnapshot.from_wire(raw)
		var floors := OfficeProjection.project(clean, states, "local")
		var seated := 1 if owner == "A" else 0
		_eq(floors[0].pane_count(), seated, "only a matching workspace can seat the pane: " + owner)
		_eq(floors[0].agents, seated, "floor agent count follows seating: " + owner)
		_eq(floors[0].blocked, seated, "floor blocked count follows seating: " + owner)
		_eq(floors[1].pane_count(), 0, "no invented tab or seat on the pane's declared workspace")
		_eq(floors[1].blocked, 0, "the declared workspace does not acquire an unplaced count")
		var panes := OfficeProjection.panes_of(clean, states, "local")
		_eq(panes.size(), 1, "every pane remains available to attention")
		_eq(panes[0].workspace_id, owner, "do not silently rewrite the declared owner")
		var label := "Alpha" if owner == "A" else "Beta" if owner == "B" else ""
		_eq(panes[0].workspace_label, label, "attention keeps the declared workspace label")
		_eq(OfficeAttention.count(panes).blocked, 1, "machine attention includes the unplaced pane once")
		var detail := OfficeProjection.inspector_pane(clean, states, "local", "p")
		_check(detail != null, "unplaced details remain available")
		if detail != null:
			_eq(detail.workspace_id, owner, "inspector preserves declared owner")
			_eq(detail.workspace_label, label, "inspector and attention agree on label")
			_eq(detail.tab_label, "Table A", "inspector preserves the named tab")
		if seated == 1:
			var world_pane := floors[0].rooms[0].panes[0]
			_eq(world_pane.workspace_id, panes[0].workspace_id, "valid world and details agree on owner")
			_eq(world_pane.workspace_label, panes[0].workspace_label, "valid world and details agree on label")
	# Identical pane ids on two machines do not share placement or queue entries.
	raw_pane.workspace_id = "B"
	var local := OfficeProjection.building("local", "Local", HerdrSnapshot.from_wire(raw), states, false)
	raw_pane.workspace_id = "A"
	var remote := OfficeProjection.building("remote", "Remote", HerdrSnapshot.from_wire(raw), states, false)
	var buildings: Array[BuildingModel] = [local, remote]
	_eq(local.panes, 1, "building count retains its conflicting pane")
	_eq(OfficeProjection.floor_of(buildings, HerdrFleet.pane_key("local", "p")), "", "conflict is unlocatable")
	_eq(
		OfficeProjection.floor_of(buildings, HerdrFleet.pane_key("remote", "p")),
		HerdrFleet.pane_key("remote", "A"),
		"the remote legal control is still locatable"
	)
	_eq(
		OfficeProjection.attention_queue(buildings),
		[HerdrFleet.pane_key("remote", "p")],
		"the placed queue contains only the matching machine's pane"
	)
	# Missing referenced tab/workspace records also retain details, not world seats.
	for missing: String in ["tabs", "workspaces"]:
		var incomplete := raw.duplicate(true)
		incomplete[missing] = []
		var clean := HerdrSnapshot.from_wire(incomplete)
		var building := OfficeProjection.building("local", "Local", clean, states, false)
		_eq(OfficeProjection.floor_of([building], HerdrFleet.pane_key("local", "p")), "", missing + " absent")
		_eq(OfficeProjection.panes_of(clean, states).size(), 1, "missing records do not hide attention")
		_check(OfficeProjection.inspector_pane(clean, states, "local", "p") != null, "missing records retain details")


# --- worktree groups ------------------------------------------------------------


## A raw workspace; `repo_key` null gives it no worktree at all.
func _space(id: String, number: int, repo_key: Variant = null, linked := false) -> Dictionary:
	var space := {"workspace_id": id, "number": number, "label": id}
	if repo_key != null:
		space.worktree = {
			"repo_key": repo_key,
			"repo_name": "r",
			"checkout_path": "/t/" + id,
			"is_linked_worktree": linked,
		}
	return space


## The floors one machine's raw workspaces project to.
func _spaces(workspaces: Array, machine := "m") -> Array[ZoneModel]:
	return OfficeProjection.project(HerdrSnapshot.from_wire({"workspaces": workspaces}), PackedStringArray(), machine)


## [workspace id, level label, the parent's workspace id or "", index] per floor.
func _levels(floors: Array[ZoneModel], machine := "m") -> Array:
	var prefix := HerdrFleet.pane_key(machine, "")
	var rows: Array = []
	for floor_model in floors:
		(
			rows
			. append(
				[
					floor_model.key.trim_prefix(prefix),
					floor_model.level_label,
					floor_model.mezzanine_of.trim_prefix(prefix),
					floor_model.mezzanine_index,
				]
			)
		)
	return rows


## herdr hangs a linked worktree under the space it was made from; the office
## makes it a mezzanine of that floor: labelled after the source floor's number,
## lettered in herdr's workspace order, and in the tree order right below it.
## The floors themselves keep their order and their keys.
func test_linked_worktrees_are_mezzanines_of_their_source() -> void:
	# In snapshot order, not number order: the projection sorts by number.
	var floors := _spaces(
		[
			_space("c", 4, "R", true),
			_space("a", 3, "R"),
			_space("b", 6, "R", true),
			_space("x", 5),
			_space("e", 1, "R", true)
		]
	)
	_eq(
		_levels(floors),
		[["e", "3A", "a", 0], ["a", "3", "", -1], ["c", "3B", "a", 1], ["x", "5", "", -1], ["b", "3C", "a", 2]],
		"floors keep herdr's number order; each linked worktree hangs from its source floor"
	)
	_eq(
		_levels(OfficeProjection.floor_tree(floors)),
		[["a", "3", "", -1], ["e", "3A", "a", 0], ["c", "3B", "a", 1], ["b", "3C", "a", 2], ["x", "5", "", -1]],
		"tree order: the source floor, then its mezzanines"
	)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tools/fixtures/snapshot_worktrees.json")
	)
	var raw: Dictionary = parsed if parsed is Dictionary else {}
	var snapshot := HerdrSnapshot.from_wire(_dict(raw, "snapshot"))
	var building := OfficeProjection.building("m", "M", snapshot, PackedStringArray(), false)
	_eq(
		_levels(building.zones),
		[
			["hs", "1", "", -1],
			["hud", "1A", "hs", 0],
			["data", "1B", "hs", 1],
			["notes", "4", "", -1],
			["ops", "5", "", -1]
		],
		"the fixture: two worktrees under herdstead, notes has no worktree, ops lane has no source floor open"
	)
	_eq(_levels(building.zone_tree), _levels(building.zones), "already in tree order")
	var lobby := OfficeProjection.building("m", "M", HerdrSnapshot.new(), PackedStringArray(), false)
	_eq(lobby.zone_tree, lobby.zones, "a building of one lobby is its own tree")
	_eq(lobby.zones[0].level_label, "", "a lobby has no number")


## Several checkouts of one repository that are not linked worktrees: the lowest
## number is the source floor, the others stay floors of their own. A repeated
## workspace id is still one floor, and cannot hang anywhere.
func test_the_lowest_source_checkout_is_the_parent() -> void:
	var floors := _spaces(
		[_space("b", 5, "R"), _space("c", 3, "R", true), _space("a", 2, "R"), _space("a", 9, "R", true)]
	)
	_eq(
		_levels(floors),
		[["a", "2", "", -1], ["c", "2A", "a", 0], ["b", "5", "", -1]],
		"a (2) is the parent; b (5) is a clone of its own; the repeated a is dropped"
	)
	_eq(_levels(OfficeProjection.floor_tree(floors)), _levels(floors), "tree order")


## Linked worktrees whose source space is not open have no parent: they stay
## top-level floors, numbered as herdr numbers them.
func test_orphan_worktrees_stay_top_level() -> void:
	var floors := _spaces([_space("d", 4, "R", true), _space("c", 3, "R", true), _space("o", 1, "Other")])
	_eq(
		_levels(floors),
		[["o", "1", "", -1], ["c", "3", "", -1], ["d", "4", "", -1]],
		"no source floor, no mezzanine; another repository's floor is not theirs"
	)


## Workspaces without a worktree, or whose worktree names no repository key, are
## never grouped, not even with one another.
func test_workspaces_without_a_repository_key_are_untouched() -> void:
	var floors := _spaces(
		[_space("a", 1), _space("b", 2, ""), _space("c", 3, "", true), _space("d", 4, ["R"], true), _space("e", 5)]
	)
	_eq(
		_levels(floors),
		[["a", "1", "", -1], ["b", "2", "", -1], ["c", "3", "", -1], ["d", "4", "", -1], ["e", "5", "", -1]],
		"every floor its own number, none hanging"
	)
	_eq(_levels(OfficeProjection.floor_tree(floors)), _levels(floors), "and the tree is the floor order")


## A repository key is only meaningful on its own machine: the same key on two
## machines is two groups, and a mezzanine only ever hangs from its own building.
func test_worktree_groups_are_per_machine() -> void:
	var local := HerdrSnapshot.from_wire({"workspaces": [_space("a", 1, "R"), _space("b", 2, "R", true)]})
	var remote := HerdrSnapshot.from_wire({"workspaces": [_space("b", 2, "R", true), _space("c", 3, "R", true)]})
	var machines: Array[MachineView] = [
		MachineView.new("m", "M", local, false), MachineView.new("n", "N", remote, false)
	]
	var frame := OfficeProjection.frame(machines, PackedStringArray())
	_eq(_levels(frame.buildings[0].zones, "m"), [["a", "1", "", -1], ["b", "1A", "a", 0]], "one group on m")
	_eq(
		_levels(frame.buildings[1].zones, "n"),
		[["b", "2", "", -1], ["c", "3", "", -1]],
		"n's worktrees of the same key find no source floor on n"
	)
	_eq(frame.buildings[0].zones[1].mezzanine_of, HerdrFleet.pane_key("m", "a"), "the parent key is composite")


## Grouping follows every refresh: a source space opening turns its worktrees
## into mezzanines, closing it turns them back into floors of their own. Neither
## is geometry: the floor's plan input does not change.
func test_a_group_appears_and_disappears_across_refreshes() -> void:
	var lane := _space("b", 2, "R", true)
	var alone := _spaces([lane])
	_eq(_levels(alone), [["b", "2", "", -1]], "alone, a worktree is a floor")
	var grouped := _spaces([_space("a", 1, "R"), lane])
	_eq(_levels(grouped), [["a", "1", "", -1], ["b", "1A", "a", 0]], "its source space opens: a mezzanine")
	var closed := _spaces([lane, _space("c", 3)])
	_eq(_levels(closed), [["b", "2", "", -1], ["c", "3", "", -1]], "the source closes: a floor again")
	_eq(grouped[1].geometry_signature(), alone[0].geometry_signature(), "hanging is not geometry")
	_eq(closed[0].geometry_signature(), alone[0].geometry_signature(), "nor is falling back")


## Mezzanine letters count like spreadsheet columns: A..Z, then AA, AB, ...
func test_mezzanine_letters() -> void:
	var expected: Dictionary[int, String] = {
		0: "A", 1: "B", 25: "Z", 26: "AA", 27: "AB", 51: "AZ", 52: "BA", 701: "ZZ", 702: "AAA"
	}
	for index: int in expected:
		_eq(OfficeProjection.mezzanine_letters(index), expected[index], "mezzanine %d" % index)
	var spaces: Array = [_space("a", 7, "R")]
	for index in 28:
		spaces.append(_space("w%02d" % index, 10 + index, "R", true))
	var labels := _spaces(spaces).map(func(f: ZoneModel) -> String: return f.level_label)
	_eq(labels.slice(0, 3), ["7", "7A", "7B"], "the first children")
	_eq(labels.slice(26), ["7Z", "7AA", "7AB"], "past Z")


func test_empty_floor_and_empty_tab_have_real_bounds() -> void:
	var empty := _plan(_floor([]))
	_check(empty.floor_cells.size.y >= 12, "empty workspace has a real floor")
	_check(empty.entry_cells.has_area(), "empty workspace has an entrance")
	_eq(empty.desks.size(), 0, "no invented room")
	_eq(empty.render_bounds.size, Vector2(empty.floor_cells.size * 32), "same authority for bounds")
	var occupied := _plan(_floor([_room("empty")]))
	_eq(occupied.desk("empty").capacity, 2, "empty tab reserves two columns")
	_eq(occupied.desk("empty").seats.size(), 0, "no invented pane")


func test_missing_layout_survives_order_changes_and_new_panes() -> void:
	var room := _room("a", 5)
	var floor_model := _floor([room, _room("b", 2)])
	var first := _plan(floor_model)
	room.panes.reverse()
	room.panes.append(_pane("a-new"))
	floor_model.rooms.reverse()
	var next := _plan(floor_model, first)
	for placed in first.desks:
		for seat in placed.seats:
			_eq(
				next.seat(seat.pane_key).geometry_signature(),
				seat.geometry_signature(),
				"old missing-layout seat retained"
			)
	_eq(next.desk("b").origin, first.desk("b").origin, "unrelated desk stays")


func test_equivalent_terminal_resize_preserves_columns_and_gaps() -> void:
	var room := _room("a")
	room.panes = [_pane("a0", 0), _pane("a1", 40), _pane("a2", 80)]
	var floor_model := _floor([room])
	var first := _plan(floor_model)
	room.panes.remove_at(1)
	room.panes[1].table_x = 200
	var next := _plan(floor_model, first)
	_eq(next.seat("a0").column, 0, "left column")
	_eq(next.seat("a2").column, 2, "deletion leaves the old hole")
	_eq(next.desk("a").capacity, first.desk("a").capacity, "deletion cannot shrink")
	room.panes[0].table_x = 20
	room.panes[1].table_x = 800
	var resized := _plan(floor_model, next)
	_eq(resized.geometry_signature(), next.geometry_signature(), "numeric x alone is not geometry")


## One tab's floor projected from herdr's terminal rects, [pane id, x, y, width, height] each.
func _tiled(rects: Array) -> ZoneModel:
	var panes: Array = []
	var placed: Array = []
	for rect: Array in rects:
		panes.append({"pane_id": rect[0], "tab_id": "t", "workspace_id": "w"})
		placed.append({"pane_id": rect[0], "rect": {"x": rect[1], "y": rect[2], "width": rect[3], "height": rect[4]}})
	var raw := {
		"workspaces": [{"workspace_id": "w", "number": 1}],
		"tabs": [{"tab_id": "t", "workspace_id": "w", "number": 1}],
		"panes": panes,
		"layouts": [{"workspace_id": "w", "tab_id": "t", "panes": placed}],
	}
	return OfficeProjection.project(HerdrSnapshot.from_wire(raw), PackedStringArray(["unknown"]), "m")[0]


## PaneModel.desk_signature() by pane key.
func _desk_looks(floor_model: ZoneModel) -> Dictionary[String, String]:
	var looks: Dictionary[String, String] = {}
	for room in floor_model.rooms:
		for pane in room.panes:
			looks[pane.key] = pane.desk_signature()
	return looks


## A herdr client resize scales every terminal rect, its x and y included. The
## seat column is the rank of the x in its tab (OfficeProjection.layout_x()), so
## neither the floor's re-plan key nor a desk's re-furnish key changes; a pane
## that really moves to another column still changes both.
func test_a_resize_that_scales_every_rect_keeps_the_floor_and_desk_signatures() -> void:
	var before := _tiled([["p1", 0, 0, 80, 80], ["p2", 80, 0, 80, 40], ["p3", 80, 40, 80, 40]])
	var resized := _tiled([["p1", 0, 0, 100, 100], ["p2", 100, 0, 100, 50], ["p3", 100, 50, 100, 50]])
	_eq(resized.rooms[0].panes.size(), 3, "every pane is seated")
	_eq(resized.rooms[0].geometry_signature(), before.rooms[0].geometry_signature(), "the tab's seats are the same")
	_eq(resized.geometry_signature(), before.geometry_signature(), "so the floor is not planned again")
	_eq(_desk_looks(resized), _desk_looks(before), "and no desk is furnished again")
	var moved := _tiled([["p1", 0, 0, 80, 80], ["p2", 80, 0, 80, 40], ["p3", 160, 40, 80, 40]])
	_check(moved.geometry_signature() != before.geometry_signature(), "a pane in a new column re-plans the floor")
	var looks := _desk_looks(moved)
	var was := _desk_looks(before)
	var p3 := HerdrFleet.pane_key("m", "p3")
	_check(looks[p3] != was[p3], "and re-furnishes the desk that moved")
	looks.erase(p3)
	was.erase(p3)
	_eq(looks, was, "and no other desk")


func test_explicit_insertion_and_side_change_only_reseat_affected_tab() -> void:
	var room := _room("a")
	room.panes = [_pane("left", 0), _pane("right", 80)]
	var floor_model := _floor([room, _room("other", 2)])
	var first := _plan(floor_model)
	room.panes.append(_pane("middle", 40))
	room.panes[0].side = "near"
	var next := _plan(floor_model, first)
	_check(next.seat("left").column < next.seat("middle").column, "left relationship")
	_check(next.seat("middle").column < next.seat("right").column, "right relationship")
	_eq(next.seat("left").side, "near", "explicit side wins")
	_eq(next.desk("other").geometry_signature(), first.desk("other").geometry_signature(), "other tab untouched")


func test_missing_layout_conflict_retains_side_and_complex_rows_are_unique() -> void:
	var room := _room("a", 2)
	var floor_model := _floor([room])
	var first := _plan(floor_model)
	room.panes.append(_pane("explicit", 0, "far", 0))
	room.panes.append(_pane("extra", 0, "far", 1))
	var next := _plan(floor_model, first)
	_eq(next.seat("a-000").side, first.seat("a-000").side, "displaced historical side preserved")
	_eq(
		next.seat("a-001").geometry_signature(),
		first.seat("a-001").geometry_signature(),
		"unconflicted missing seat preserved"
	)
	_check(next.seat("extra").column != next.seat("explicit").column, "third terminal row receives extra column")
	_eq(next.desk("a").seats.size(), 4, "all panes retained")
	var result := OfficeFloorLayout.plan(MapModel.of(floor_model), first)
	_check(not result.diagnostics.is_empty(), "flattening is diagnosed")


func test_opposite_seat_and_room_labels_do_not_move_geometry() -> void:
	var room := _room("a")
	room.panes = [_pane("far", 0)]
	var floor_model := _floor([room, _room("b", 2)])
	var first := _plan(floor_model)
	room.panes.append(_pane("near", 0, "near"))
	var second := _plan(floor_model, first)
	_eq(second.desk("a").origin, first.desk("a").origin, "opposite seat does not shift table")
	_eq(second.desk("a").capacity, first.desk("a").capacity, "opposite seat does not grow table")
	var signature := floor_model.geometry_signature()
	room.label = "renamed"
	room.active = RoomModel.Active.NO
	room.panes[0].state = "done"
	room.panes[0].focused = true
	floor_model.label = "new workspace name"
	floor_model.worktree = "new checkout label"
	_eq(floor_model.geometry_signature(), signature, "display does not invalidate planning")
	_eq(_plan(floor_model, second).geometry_signature(), second.geometry_signature(), "same structure retains plan")


func test_growth_is_left_anchored_and_previous_plan_is_immutable() -> void:
	var room := _room("a", 4)
	var floor_model := _floor([room])
	var first := _plan(floor_model)
	var signature := first.geometry_signature()
	room.panes.append(_pane("new-column"))
	var next := _plan(floor_model, first)
	_eq(next.desk("a").origin, first.desk("a").origin, "growth leaves origin fixed")
	_eq(next.desk("a").capacity, 4, "capacity grows by two")
	for index in first.desk("a").capacity:
		_eq(
			next.desk("a").measure.columns[index],
			first.desk("a").measure.columns[index],
			"existing columns keep local x"
		)
	_eq(first.geometry_signature(), signature, "previous plan unchanged")


func test_deleted_groups_leave_reusable_holes_and_rows_never_shrink() -> void:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = 18
	var floor_model := _floor([_room("a", 2), _room("b", 2), _room("c", 2)])
	var first := _plan(floor_model, null, rules)
	floor_model.rooms.remove_at(0)
	var deleted := _plan(floor_model, first, rules)
	_eq(deleted.floor_cells, first.floor_cells, "no automatic floor shrink")
	_eq(deleted.desk("c").origin, first.desk("c").origin, "later row stays")
	floor_model.rooms.append(_room("new", 2, 9))
	var filled := _plan(floor_model, deleted, rules)
	_eq(filled.desk("new").reserved_cells, first.desk("a").reserved_cells, "new tab fills old hole")
	_eq(filled.floor_cells, first.floor_cells, "filling hole does not add a row")
	floor_model.rooms.clear()
	_eq(_plan(floor_model, filled, rules).floor_cells, first.floor_cells, "deleting all tabs keeps structural space")


func test_oversized_growth_moves_only_owner_and_keeps_row_exclusive() -> void:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = 18
	var a := _room("a", 2)
	var floor_model := _floor([a, _room("b", 2)])
	var first := _plan(floor_model, null, rules)
	# Forty panes: twenty desks, 21 cells, wider than the 14-cell bay (a pod
	# packs a column into one cell, so twenty panes no longer outgrow it).
	a.panes = _room("a", 40).panes
	var wider := _plan(floor_model, first, rules)
	_eq(wider.desk("b").origin, first.desk("b").origin, "other desk is fixed")
	_check(wider.desk("a").row != wider.desk("b").row, "growth leaves shared row")
	_eq(_rows(wider)[wider.desk("a").row].exclusive_tab_key, "a", "dedicated row ownership")
	_check(wider.main_corridor_cells.position.x > first.main_corridor_cells.position.x, "right corridor moves outward")
	_check(wider.lanes > first.lanes, "the map widened by whole lanes: %d -> %d" % [first.lanes, wider.lanes])
	floor_model.rooms.append(_room("huge", 80, 3))
	var widest := _plan(floor_model, wider, rules)
	floor_model.rooms.append(_room("small", 2, 4))
	var filled := _plan(floor_model, widest, rules)
	_check(filled.desk("small").row != filled.desk("a").row, "new global width cannot open exclusive row to others")
	_eq(filled.desk("a").origin, wider.desk("a").origin, "later widening keeps old wide table position")
	_eq(filled.desk("b").origin, first.desk("b").origin, "original neighbour still fixed")


func test_policy_width_resize_does_not_reflow_but_revision_does() -> void:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = 18
	var floor_model := _floor([_room("a", 2), _room("b", 2), _room("c", 2)])
	var first := _plan(floor_model, null, rules)
	rules.width_cells = 40
	var resized := _plan(floor_model, first, rules)
	_eq(resized.geometry_signature(), first.geometry_signature(), "viewport width only affects first plan")
	_eq(resized.lanes, first.lanes, "lanes are fixed at the first plan")
	rules.version += 1
	var revised := _plan(floor_model, resized, rules)
	# The map's width is a whole number of lanes (10L + 3): 40 cells give 3 lanes, 33 cells.
	_eq([revised.lanes, revised.initial_width_cells], [3, 33], "explicit policy revision replans")


func test_duplicate_identity_and_budget_fail_without_mutating_old_plan() -> void:
	var floor_model := _floor([_room("a", 2)])
	var first := _plan(floor_model)
	var signature := first.geometry_signature()
	floor_model.rooms.append(_room("a", 2))
	var duplicate := OfficeFloorLayout.plan(MapModel.of(floor_model), first)
	_eq(duplicate.plan, null, "duplicate tab cannot overwrite")
	_check(not duplicate.problems.is_empty(), "duplicate diagnosed")
	floor_model.rooms = [_room("a", 2), _room("b")]
	floor_model.rooms[1].panes.append(_pane("a-000"))
	_eq(OfficeFloorLayout.plan(MapModel.of(floor_model), first).plan, null, "duplicate pane cannot overwrite")
	floor_model.rooms = [_room("a", 200)]
	var rules := FloorLayoutPolicy.new()
	rules.max_width_cells = 40
	_eq(
		OfficeFloorLayout.plan(MapModel.of(floor_model), first, rules).plan,
		null,
		"width budget checked before expansion"
	)
	rules.max_width_cells = 512
	rules.max_floor_cells = 100
	_eq(OfficeFloorLayout.plan(MapModel.of(_floor([])), null, rules).plan, null, "empty floor also obeys budget")
	_eq(first.geometry_signature(), signature, "failures leave old plan untouched")


func test_geometric_validation_detects_blocked_approaches_and_overlap() -> void:
	var value := _plan(_floor([_room("a", 2), _room("b", 2)]))
	value.desks[0].measure.physical_rect = value.desks[0].measure.reserved_rect
	_check(not OfficeFloorLayout.validate(value).is_empty(), "floodfill rejects trapped approaches")
	var overlap := _plan(_floor([_room("a", 2), _room("b", 2)]))
	overlap.desks[1].reserved_cells = overlap.desks[0].reserved_cells
	_check(not OfficeFloorLayout.validate(overlap).is_empty(), "overlapping reservations rejected")


func test_seeded_incremental_sequence_preserves_unrelated_groups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260922
	var floor_model := _floor([_room("a", 2), _room("b", 2), _room("c", 2)])
	var value := _plan(floor_model)
	for iteration in 80:
		var index := rng.randi_range(0, floor_model.rooms.size() - 1)
		var room := floor_model.rooms[index]
		if room.panes.size() > 3 and rng.randi_range(0, 2) == 0:
			room.panes.remove_at(rng.randi_range(0, room.panes.size() - 1))
		else:
			room.panes.append(_pane("%s-new-%d" % [room.key, iteration]))
		var previous := value
		value = _plan(floor_model, previous)
		for other in previous.desks:
			if other.tab_key != room.key:
				_eq(
					value.desk(other.tab_key).geometry_signature(),
					other.geometry_signature(),
					"unrelated table stays through sequence"
				)
		for pane in room.panes:
			var old := previous.seat(pane.key)
			if old != null:
				_eq(
					value.seat(pane.key).geometry_signature(),
					old.geometry_signature(),
					"missing-layout history survives growth/removal"
				)
		_eq(_plan(floor_model, previous).geometry_signature(), value.geometry_signature(), "same inputs deterministic")


func test_actual_actor_measurements_constrain_paths_and_wall_projection() -> void:
	var floor_model := _floor([_room("a", 2)])
	var rules := FloorLayoutPolicy.new()
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	var normal := OfficeFloorLayout.plan(MapModel.of(floor_model), null, rules)
	_eq(normal.problems, PackedStringArray(), "real production footprint and canvas fit")
	_check(
		rules.actor_footprint.position.y < 0 and rules.actor_footprint.end.y == 0, "foot offset is read from the prefab"
	)
	rules.actor_footprint = Rect2(-100, -100, 200, 200)
	_check(
		not OfficeFloorLayout.plan(MapModel.of(floor_model), null, rules).problems.is_empty(),
		"large body cannot pass narrow approach"
	)
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = Rect2(-16, -300, 32, 302)
	_check(
		not OfficeFloorLayout.plan(MapModel.of(floor_model), null, rules).problems.is_empty(),
		"tall actor cannot float over Ground walls"
	)
	var missing_entry := _plan(_floor([]))
	missing_entry.entry_cells = Rect2i()
	_check(not OfficeFloorLayout.validate(missing_entry).is_empty(), "empty floor still requires an entrance")


func _decoration(key: String, bounds: Rect2) -> DecorPlacement:
	var decoration := DecorPlacement.new()
	decoration.key = key
	decoration.piece = &"plant"
	decoration.position = bounds.position
	decoration.footprint = bounds
	decoration.draw_rect = bounds
	return decoration


func test_decorations_are_validated_and_thin_obstacles_block_graph_edges() -> void:
	var rules := FloorLayoutPolicy.new()
	var value := _plan(_floor([_room("a", 2)]), null, rules)
	var signature := value.geometry_signature()
	var prop := _decoration("clear", Rect2(600, 300, 12, 8))
	value.decorations.append(prop)
	_eq(OfficeFloorLayout.validate(value, rules), PackedStringArray(), "unobstructed decoration accepted")
	_check(value.geometry_signature() != signature, "decorations participate in geometry signature")
	prop.footprint.position.x = value.main_corridor_cells.position.x * FloorLayoutPolicy.GRID + 8
	_check(
		"; ".join(OfficeFloorLayout.validate(value, rules)).contains("blocks a corridor"),
		"corridor obstruction diagnosed"
	)
	prop.footprint = value.desks[0].measure.physical_rect
	prop.footprint.position += value.desks[0].origin
	_check("; ".join(OfficeFloorLayout.validate(value, rules)).contains("table footprint"), "table overlap diagnosed")
	# A synthetic furniture-only profile isolates path geometry from labels.
	# Four thin barriers surround one approach without covering any grid centre.
	var trapped := _plan(_floor([_room("a", 2)]), null, rules)
	trapped.desks[0].measure.render_rect = trapped.desks[0].measure.physical_rect
	var target := trapped.desks[0].origin + trapped.desks[0].measure.approach_position(0, "far")
	var bars: Array[Rect2] = [
		Rect2(target + Vector2(-17, -17), Vector2(34, 2)),
		Rect2(target + Vector2(-17, 15), Vector2(34, 2)),
		Rect2(target + Vector2(-17, -15), Vector2(2, 30)),
		Rect2(target + Vector2(15, -15), Vector2(2, 30)),
	]
	for index in bars.size():
		trapped.decorations.append(_decoration("bar-%d" % index, bars[index]))
	var problems := OfficeFloorLayout.validate(trapped, rules)
	_check("; ".join(problems).contains("unreachable approach"), "thin between-centre obstacles really block the path")
	for problem in problems:
		_check(problem.begins_with("unreachable approach"), "fixture fails on connectivity, not unrelated bounds")


func test_budget_diagnostics_reject_input_before_seat_allocation() -> void:
	# The widest zone the 512-cell width budget allows is 50 lanes, 499 cells:
	# past its pad, 498 hold a pod of at most 496 columns (capacity is even; one
	# cell a column and the pod's passage cell). 1100 panes, 550 columns, do not.
	var too_wide := OfficeFloorLayout.plan(MapModel.of(_floor([_room("wide", 1100)])))
	_eq(too_wide.plan, null, "table cannot fit the measured width budget")
	_check(
		"; ".join(too_wide.problems).contains("tab exceeds measured width budget"),
		"width rejection occurs at the input boundary"
	)
	var too_many := OfficeFloorLayout.plan(MapModel.of(_floor([_room("a", 1500), _room("b", 1500), _room("c", 1500)])))
	_eq(too_many.plan, null, "too many panes rejected")
	_check(
		"; ".join(too_many.problems).contains("input exceeds pane budget"),
		"total input budget is independent of floor tile allocation"
	)


func test_empty_tabs_pay_for_real_render_allocations() -> void:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = 512
	var floor_model := _floor([])
	for index in 1000:
		floor_model.rooms.append(_room("empty-%04d" % index))
	var result := OfficeFloorLayout.plan(MapModel.of(floor_model), null, rules)
	_check(result.plan == null, "1000 empty tabs cannot allocate thousands of full vacant stations")
	_check(result.problems.has("floor exceeds desk node budget"), "empty tabs hit render, not input or cell budget")


func test_moving_panes_cannot_hide_retained_capacity() -> void:
	var rules := FloorLayoutPolicy.new()
	var first_room := _room("first", 500)
	var floor_model := _floor([first_room])
	var previous := _plan(floor_model, null, rules)
	var signature := previous.geometry_signature()
	var destination := _room("second")
	destination.panes = first_room.panes
	first_room.panes = []
	floor_model.rooms.append(destination)
	_eq(floor_model.pane_count(), 500, "migration does not increase the input pane count")
	var rejected := OfficeFloorLayout.plan(MapModel.of(floor_model), previous, rules)
	_check(rejected.plan == null, "both retained source columns and destination columns consume the budget")
	_check(rejected.problems.has("floor exceeds desk node budget"), "migration is rejected by render budget")
	_eq(previous.geometry_signature(), signature, "rejection leaves the last valid geometry and seats untouched")
	var cold := _plan(floor_model, null, rules)
	_eq(cold.desk("first").capacity, 2, "same current input without history is small enough")
	_eq(cold.desk("second").capacity, 250, "destination still seats every pane")


func test_desk_node_budget_boundary_includes_fixed_cost_and_both_sides() -> void:
	# One empty two-column pod (168) plus a four-column pod (310): 26 fixed
	# (the lens's wash among them) and 71 a column (a chip at each seat, a
	# stack of paper each, the lens line), as the geometry suite counts them.
	# Expected costs are independent of the implementation's accounting helper.
	var model := _floor([_room("empty"), _room("full", 8)])
	for limit: int in [477, 478, 479]:
		var rules := FloorLayoutPolicy.new()
		rules.max_desk_nodes = limit
		var result := OfficeFloorLayout.plan(MapModel.of(model), null, rules)
		_eq(result.plan != null, limit >= 478, "exact boundary is inclusive")
		if result.plan != null:
			_eq(result.plan.desk("empty").capacity, 2, "empty table reserves both pairs of seats")
			_eq(result.plan.desk("full").capacity, 4, "occupied table has four columns, not eight")
		else:
			_eq(result.problems, PackedStringArray(["floor exceeds desk node budget"]), "only allocation fails")
	for limit: int in [-1, 0, 1]:
		var rules := FloorLayoutPolicy.new()
		rules.max_desk_nodes = limit
		_eq(
			OfficeFloorLayout.plan(MapModel.of(_floor([])), null, rules).plan != null,
			limit > 0,
			"budget must be positive"
		)


func test_repeated_migrations_retain_seats_until_cumulative_budget_is_full() -> void:
	var rules := FloorLayoutPolicy.new()
	# An eight-column pod costs 26 + 71 * 8 = 594: four fit (2376), five
	# (2970) do not.
	rules.max_desk_nodes = 2800
	var model := _floor([])
	var panes := _room("traveller", 16).panes
	var previous := _plan(model, null, rules)
	for step in 5:
		for room in model.rooms:
			room.panes = []
		var destination := _room("tab-%d" % step, 0, step)
		destination.panes = panes
		model.rooms.append(destination)
		var result := OfficeFloorLayout.plan(MapModel.of(model), previous, rules)
		_eq(model.pane_count(), 16, "every step carries the same sixteen panes")
		if step == 4:
			_check(result.plan == null, "five retained eight-column pods cost 2970, not 2800")
			_eq(result.problems, PackedStringArray(["floor exceeds desk node budget"]), "cumulative refusal")
			_eq(previous.desks.size(), 4, "failed addition never mutates previous table membership")
			_check(previous.seat(panes[0].key) != null, "previous pane binding survives rejection")
			continue
		_eq(result.problems, PackedStringArray(), "four pods cost 2376 and fit")
		_check(result.plan != null, "migration within budget succeeds")
		if result.plan == null:
			return
		for placed in result.plan.desks:
			_eq(placed.capacity, 8, "empty historical desks never shrink")
			if previous != null and previous.desk(placed.tab_key) != null:
				_eq(placed.origin, previous.desk(placed.tab_key).origin, "historical row and origin stay fixed")
		previous = result.plan
	# Removing a tab releases its allocation, not the row or neighbouring desks.
	model.rooms.remove_at(0)
	var recovered := _plan(model, previous, rules)
	_eq(recovered.desk("tab-4").capacity, 8, "removing a real desk makes the pending migration fit")
	_eq(recovered.desk("tab-1").origin, previous.desk("tab-1").origin, "recovery does not compact neighbours")


func test_previous_empty_capacity_is_validated_against_current_budgets() -> void:
	var rules := FloorLayoutPolicy.new()
	rules.max_desk_nodes = 40000
	var model := _floor([_room("a", 500), _room("b", 500)])
	var full := _plan(model, null, rules)
	for room in model.rooms:
		room.panes.clear()
	var empty := _plan(model, full, rules)
	var signature := empty.geometry_signature()
	_eq(empty.desks[0].seats.size() + empty.desks[1].seats.size(), 0, "no current panes remain")
	_eq(empty.desks[0].capacity + empty.desks[1].capacity, 500, "1000 empty slots still exist")
	# Two 250-column pods: 2 * (26 + 71 * 250).
	for limit: int in [35551, 35552, 35553]:
		rules.max_desk_nodes = limit
		_eq(OfficeFloorLayout.validate(empty, rules).is_empty(), limit >= 35552, "old allocation boundary")
		_eq(
			OfficeFloorLayout.plan(MapModel.of(model), empty, rules).plan != null,
			limit >= 35552,
			"old input uses same budget"
		)
	_eq(empty.geometry_signature(), signature, "budget changes neither shrink nor reflow previous desks")
	rules.max_tables = 1
	_eq(
		OfficeFloorLayout.validate(empty, rules), PackedStringArray(["layout exceeds table budget"]), "old tabs bounded"
	)
	rules.max_tables = 1024
	rules.max_panes = 999
	_eq(OfficeFloorLayout.validate(full, rules), PackedStringArray(["layout exceeds pane budget"]), "old panes bounded")


func test_previous_plan_cannot_understate_its_render_allocation() -> void:
	var rules := FloorLayoutPolicy.new()
	var model := _floor([_room("a")])
	var previous := _plan(model, null, rules)
	for capacity: int in [-2, 3, 9223372036854775807]:
		previous.desks[0].capacity = capacity
		_eq(
			OfficeFloorLayout.validate(previous),
			PackedStringArray(["table capacity must be at least two and grow in pairs"]),
			"malformed capacity is rejected before arithmetic or allocation"
		)
	previous.desks[0].capacity = 2
	for width: float in [NAN, INF, 32000000.0]:
		previous.desks[0].measure.table_width = width
		_check(
			OfficeFloorLayout.validate(previous).has("table width or columns disagree with measured capacity"),
			"a two-column plan cannot request unbudgeted table modules"
		)
		_check(
			OfficeFloorLayout.plan(MapModel.of(model), previous, rules).plan == null,
			"forged measurement cannot be retained"
		)
	previous.desks[0].measure = OfficeTable.measure(2)
	previous.desks[0].measure.columns.append(176.0)
	_check(not OfficeFloorLayout.validate(previous).is_empty(), "extra measured columns cannot bypass capacity cost")


## A zone of two lanes (four twelve-pane pods, 7 cells each: four rows in one
## lane, so the zone takes two, two to a row): pod b, at x 9 of the first row,
## grows to twelve columns (13 cells). In place it would reach x 22, past the
## widest zone a 25-cell width budget allows (two lanes, to x 20); the left end
## of its row, which a's removal emptied, holds it.
func test_over_budget_in_place_growth_uses_a_valid_relocation() -> void:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = 25
	rules.max_width_cells = 25
	var growing := _room("b", 12, 1)
	var floor_model := _floor([_room("a", 12), growing, _room("c", 12, 2), _room("d", 12, 3)])
	var previous := _plan(floor_model, null, rules)
	_eq(previous.zones[0].lanes, 2, "a zone of two lanes")
	_eq(previous.desk("b").reserved_cells.position.x, 9, "b stands right of a, 8 cells into the zone")
	floor_model.rooms.remove_at(0)
	growing.panes = _room("b", 24).panes
	var result := OfficeFloorLayout.plan(MapModel.of(floor_model), previous, rules)
	_check(result.plan != null, "over-budget original anchor must not hide a valid placement")
	if result.plan == null:
		return
	_check(result.plan.floor_cells.size.x <= rules.max_width_cells, "relocation respects width budget")
	_check(result.plan.desk("b").origin.x < previous.desk("b").origin.x, "affected table reuses the empty left end")
	for tab: String in ["c", "d"]:
		_eq(
			result.plan.desk(tab).geometry_signature(),
			previous.desk(tab).geometry_signature(),
			"unrelated row remains fixed"
		)


# --- the plan cache and the decor planner -------------------------------------


## Puts one cabinet across the entrance band, which nobody can walk past.
class BlockingDecor:
	extends OfficeDecorPlanner

	func furnish(next: FloorPlan) -> void:
		var entrance := Rect2(
			next.entry_cells.position * FloorLayoutPolicy.GRID, next.entry_cells.size * FloorLayoutPolicy.GRID
		)
		var block := DecorPlacement.new()
		block.key = "block"
		block.piece = ArtContract.PROP_CABINET
		block.position = entrance.get_center()
		block.footprint = entrance
		block.draw_rect = entrance
		next.decorations.append(block)


## The shipped pack's pen, made once: the decor planner measures its props and
## the lettering on the walls with it.
func _pen() -> OfficeDraw:
	if pen == null:
		pen = OfficeDraw.new(ArtPack.from_manifest("res://assets/daylight/manifest.json"))
	return pen


## A floor model under its own key.
func _keyed(key: String, rooms: Array[RoomModel]) -> ZoneModel:
	var floor_model := _floor(rooms)
	floor_model.key = key
	return floor_model


## A workspace `key` numbered `number` with `rooms`: one zone of a map.
func _zoned(key: String, number: int, rooms: Array[RoomModel]) -> ZoneModel:
	var zone := _keyed(key, rooms)
	zone.number = number
	return zone


## A floor is planned once for each input it has: the same geometry, however
## new the model, reuses the plan and draws the newer model; a wider window does
## not reflow it; new geometry plans again, keeping what still fits.
func test_the_plan_cache_plans_each_input_once() -> void:
	var cache := FloorPlanCache.new()
	var first := cache.prepare(MapModel.of(_floor([_room("a", 2), _room("b", 1, 1)])), _pen(), 640.0)
	_check(first != null and cache.problems().is_empty(), "a valid floor is planned")
	_eq(cache.attempt_count(), 1, "once")
	var again := MapModel.of(_floor([_room("a", 2), _room("b", 1, 1)]))
	_eq(cache.prepare(again, _pen(), 640.0), first, "the same geometry in a new model reuses the plan")
	_eq(cache.attempt_count(), 1, "without planning again")
	_eq(cache.planned_model(again.key), again, "and the floor is drawn from the newer model")
	_eq(cache.prepare(again, _pen(), 1600.0), first, "a wider window does not reflow the floor")
	var grown := cache.prepare(MapModel.of(_floor([_room("a", 5), _room("b", 1, 1)])), _pen(), 640.0)
	_eq(cache.attempt_count(), 2, "new geometry is planned")
	_check(grown != first and grown.desk("a").capacity > first.desk("a").capacity, "into a new plan")
	_eq(grown.desk("b").geometry_signature(), first.desk("b").geometry_signature(), "which keeps what still fits")
	_eq(cache.plan(again.key), grown, "and the cache holds it")


## An input that cannot be planned keeps the last valid plan on screen, drawn
## from the model that plan was made for, and says why; the same failing input
## is not planned again, and a corrected one clears the diagnosis.
func test_the_plan_cache_keeps_the_last_valid_plan_while_the_input_is_invalid() -> void:
	var cache := FloorPlanCache.new()
	var valid := MapModel.of(_floor([_room("a", 2)]))
	var plan := cache.prepare(valid, _pen(), 640.0)
	var twice := MapModel.of(_floor([_room("a", 2)]))
	twice.rooms[0].panes.append(_pane(twice.rooms[0].panes[0].key))
	_eq(cache.prepare(twice, _pen(), 640.0), plan, "a repeated pane keeps the last valid plan")
	_check(not cache.problems().is_empty(), "and says why")
	_eq(cache.planned_model(valid.key), valid, "the floor is still drawn from the model that plan was made for")
	var attempts := cache.attempt_count()
	_eq(cache.prepare(twice, _pen(), 640.0), plan, "the same failing input again")
	_eq(cache.attempt_count(), attempts, "is not planned again")
	_check(not cache.problems().is_empty(), "and keeps its diagnosis")
	cache.prepare(MapModel.of(_floor([_room("a", 2)])), _pen(), 640.0)
	_check(cache.problems().is_empty(), "a corrected input clears it")
	_eq(cache.attempt_count(), attempts + 1, "planned once")


## A lobby is planned like any empty floor, walls, door, windows and walkways,
## and kept; but it lays out nothing herdr sent, so no layout diagnostic reports it.
func test_the_plan_cache_plans_a_lobby_apart_from_the_layout() -> void:
	var cache := FloorPlanCache.new()
	var lobby := MapModel.of(OfficeProjection.lobby("machine"))
	var plan := cache.prepare(lobby, _pen(), 640.0)
	_check(plan != null and plan.desks.is_empty() and plan.zones.is_empty(), "a lobby is an empty planned floor")
	_eq(plan.floor_key, lobby.key, "under its own key")
	_eq(OfficeFloorLayout.validate(plan, FloorLayoutPolicy.new()), PackedStringArray(), "with a walkable entrance")
	_eq([cache.plan(lobby.key), cache.attempt_count()], [null, 0], "and no layout diagnostic counts it")
	_eq(cache.problems(), PackedStringArray(), "or finds a problem with it")
	_eq(cache.prepare(MapModel.of(OfficeProjection.lobby("machine")), _pen(), 1600.0), plan, "it is planned once")
	cache.prune([])
	_check(cache.prepare(lobby, _pen(), 640.0) != plan, "a lobby that went away is planned afresh")


## Closing a workspace releases its plan and its history; another floor, only
## not shown, keeps both.
func test_pruning_releases_only_the_floors_that_went_away() -> void:
	var cache := FloorPlanCache.new()
	var kept := cache.prepare(MapModel.of(_keyed("machine/kept", [_room("a", 2)])), _pen(), 640.0)
	cache.prepare(MapModel.of(_keyed("machine/closed", [_room("b", 2)])), _pen(), 640.0)
	var kept_keys: Array[String] = ["machine/kept"]
	cache.prune(kept_keys)
	_eq(cache.plan("machine/closed"), null, "the closed floor's plan is released")
	_eq(cache.plan("machine/kept"), kept, "the other floor keeps its plan")
	var attempts := cache.attempt_count()
	cache.prepare(MapModel.of(_keyed("machine/closed", [_room("b", 2)])), _pen(), 640.0)
	_eq(cache.attempt_count(), attempts + 1, "and a floor that comes back is planned afresh")


## A map of one workspace plans exactly as that workspace does, under its key,
## and its plan places that one zone in real lanes: from lane 0, row 6, under
## its aisle row, as many lanes wide as its widest table needs (the map widens
## first when it has fewer), whole pod rows deep; every desk names the zone it
## stands in, stands right of its pad, and the zone holds every desk.
func test_a_one_zone_plan_places_its_zone_over_its_rows() -> void:
	var floor_model := _keyed("machine/one", [_room("a", 20), _room("b", 12, 1), _room("c", 24, 2)])
	var map := MapModel.of(floor_model)
	_eq([map.key, map.zones], [floor_model.key, [floor_model]], "a map wraps one zone under the workspace's key")
	_eq(map.geometry_signature(), floor_model.geometry_signature(), "and has that zone's geometry signature")
	_eq([map.rooms, map.pane_count()], [floor_model.rooms, floor_model.pane_count()], "its rooms and panes")
	floor_model.mezzanine_of = "machine/source"
	_eq(map.geometry_signature(), floor_model.geometry_signature(), "a mezzanine grouping is not geometry")
	# 640 units are 20 cells: one lane (10 + 3 = 13 cells). Table c has 4 columns,
	# 11 cells: two lanes' 18 inner cells hold it, one lane's 8 do not.
	var plan := FloorPlanCache.new().prepare(map, _pen(), 640.0)
	_check(plan != null and _rows(plan).size() > 1, "a valid plan of several rows")
	if plan == null:
		return
	_eq(plan.zones.size(), 1, "places one zone")
	var zone := plan.zones[0]
	_eq([zone.zone_key, plan.zone(floor_model.key), plan.zone("machine/other")], [plan.floor_key, zone, null], "by key")
	_eq([zone.first_lane, zone.lanes, plan.lanes], [0, 2, 2], "two lanes wide: the map widened to two first")
	_eq(plan.floor_cells.size.x, 23, "a map of two lanes is 10 * 2 + 3 cells wide")
	var pod := OfficeZoneLayout.pod_row_cells()
	_eq(zone.cells, Rect2i(1, 6, 19, pod * _rows(plan).size()), "from row 6, 19 cells wide, whole pod rows deep")
	_eq(zone.slot(), Rect2i(1, 5, 19, pod * _rows(plan).size() + 1), "under its aisle row")
	_eq(zone.initial_width_cells, 19, "first laid out that wide")
	for index in _rows(plan).size():
		_eq(_rows(plan)[index].band_cells, Rect2i(1, 6 + index * pod, 19, pod), "row %d is its band" % index)
	var desks := 0
	for row in zone.rows:
		desks += row.desks.size()
	_eq(desks, plan.desks.size(), "every desk stands in one of its rows")
	for placed in plan.desks:
		_eq(placed.zone_key, floor_model.key, "desk %s names its zone" % placed.tab_key)
		_check(zone.cells.encloses(placed.reserved_cells), "and stands inside it: %s" % placed.tab_key)
		_check(placed.reserved_cells.position.x >= zone.cells.position.x + 1, "right of the pad: %s" % placed.tab_key)


## The planners furnish a candidate before its one validation, the pantry and
## then the furniture: the same plan as validating the bare plan, furnishing it
## and validating it again, with half the flood fills. Three tables of one lane
## each leave the other lane's gap to furnish.
func test_a_furnished_plan_is_validated_once() -> void:
	var rules := FloorLayoutPolicy.new()
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	var floor_model := _floor([_room("a", 4), _room("b", 2, 1), _room("c", 2, 2)])
	var before := OfficeFloorValidation.validations
	var furnished := OfficeFloorLayout.plan(
		MapModel.of(floor_model), null, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(OfficeFloorValidation.validations - before, 1, "one validation, furniture and pantry included")
	_check(furnished.plan != null and not furnished.plan.decorations.is_empty(), "of a furnished floor")
	_check(furnished.plan != null and furnished.plan.pantry != null, "with its pantry")
	if furnished.plan == null:
		return
	before = OfficeFloorValidation.validations
	var bare := OfficeFloorLayout.plan(MapModel.of(floor_model), null, rules)
	OfficeFixturePlanner.new(_pen()).furnish(bare.plan)
	OfficeDecorPlanner.new(_pen()).furnish(bare.plan)
	_eq(
		OfficeFloorLayout.validate(bare.plan, rules),
		PackedStringArray(),
		"validating the bare plan, then the furnished"
	)
	_eq(OfficeFloorValidation.validations - before, 2, "takes two")
	_eq(furnished.plan.geometry_signature(), bare.plan.geometry_signature(), "for the same plan")


## Furniture is optional: a batch that would close the way to any seat is left
## out first, never a desk, and the pantry stays: the second validation is of
## the map with its pantry and without the furniture.
func test_furniture_that_closes_a_path_is_left_out() -> void:
	var rules := FloorLayoutPolicy.new()
	var before := OfficeFloorValidation.validations
	var result := OfficeFloorLayout.plan(
		MapModel.of(_floor([_room("a", 2)])), null, rules, BlockingDecor.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(result.problems, PackedStringArray(), "the floor is still valid")
	_check(result.plan != null and result.plan.desks.size() == 1, "with its desk")
	_check(result.plan != null and result.plan.decorations.is_empty(), "and without the furniture that blocked it")
	_check(result.plan != null and result.plan.pantry != null, "but with its pantry")
	_eq(OfficeFloorValidation.validations - before, 2, "which took a second validation")


## `map` (or a map of one workspace) planned `width` cells wide as the cache
## plans it: furnished, with its pantry, in one validation.
func _furnished(model: RefCounted, width: int) -> FloorPlan:
	var map := _map_of(model)
	var rules := _real_rules(width)
	var before := OfficeFloorValidation.validations
	var result := OfficeFloorLayout.plan(
		map, null, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(result.problems, PackedStringArray(), "%d cells: a valid floor: %s" % [width, "; ".join(result.problems)])
	_eq(OfficeFloorValidation.validations - before, 1, "%d cells: validated once, furniture included" % width)
	return result.plan


## The furniture of `plan` standing in `gap` (its "%02d/gap/%04d" keys).
func _gap_pieces(plan: FloorPlan, gap: OfficeDecorPlanner.LaneGap) -> Array[DecorPlacement]:
	var found: Array[DecorPlacement] = []
	for placed in plan.decorations:
		if not placed.key.begins_with("%02d/gap/" % gap.lane):
			continue
		var row := placed.key.get_slice("/", 2).to_int()
		if row >= gap.top and row < gap.end:
			found.append(placed)
	return found


## A map of three workspaces of different heights, side by side and stacked,
## which leaves lane gaps under the shorter ones. A twelve-pane pod (7 cells)
## fills a one-lane zone's pod row: two 2-pane pods (3 cells) would share one.
func _three_zones() -> MapModel:
	var zones: Array[ZoneModel] = [
		_zoned("machine/1", 1, [_room("a", 12), _room("b", 12, 1), _room("c", 12, 2)]),
		_zoned("machine/2", 2, [_room("d", 2)]),
		_zoned("machine/3", 3, [_room("e", 12), _room("f", 12, 1)]),
	]
	return MapModel.of_zones("machine", zones)


## Every lane gap of a furnished map, at every shipped width, on the stress map
## and on a map of several zones, stands its pieces (every two rows from the
## gap's second row), and the furnished map still validates in one pass, so none
## of it is dropped. The pieces close no walk: the only nodes they take that
## the bare map had are in the lanes' middle columns (the top-wall run stands in
## the wall's clearance row, which nobody walks anyway).
func test_every_lane_gap_stands_furniture_and_the_map_validates_once() -> void:
	var cases: Array[Array] = []
	for width in FURNISHED_WIDTHS:
		cases.append(["one table", _floor([_room("a", 2)]), width])
	cases.append(["two tables", _floor([_room("a", 4), _room("b", 2, 1)]), 32])
	cases.append(["three zones", _three_zones(), 32])
	cases.append(["stress", _stress_floor(), 20])
	cases.append(["stress", _stress_floor(), 32])
	var gaps_seen := 0
	for each in cases:
		var what: String = each[0]
		var width: int = each[2]
		var model: RefCounted = each[1]
		var plan := _furnished(model, width)
		if plan == null:
			continue
		var rules := _real_rules(width)
		var middles: Dictionary[int, bool] = {}
		for lane in plan.lanes:
			middles[rules.lane_x(lane) + floori(rules.zone_width_cells / 2.0)] = true
		for gap in OfficeDecorPlanner.lane_gaps(plan, rules):
			var pieces := _gap_pieces(plan, gap)
			gaps_seen += 1
			print(
				(
					"PIECES_PER_GAP %s %d cells lane %d rows %d..%d: %d"
					% [what, width, gap.lane, gap.top, gap.end, pieces.size()]
				)
			)
			_check(
				not pieces.is_empty(),
				"%s, %d cells: lane %d's gap at row %d stands furniture" % [what, width, gap.lane, gap.top]
			)
			for placed in pieces:
				var row := placed.key.get_slice("/", 2).to_int()
				_eq(
					(row - gap.top - 1) % OfficeShell.LANE_GAP_STEP_CELLS,
					0,
					"%s: %s on the gap's grid" % [what, placed.key]
				)
		var bare := OfficeFloorLayout.plan(_map_of(model), null, rules, null, OfficeFixturePlanner.new(_pen())).plan
		var open := _graph_of(bare, rules)
		var furnished := _graph_of(plan, rules)
		for y in plan.floor_cells.size.y:
			for x in plan.floor_cells.size.x:
				var cell := Vector2i(x, y)
				if not open.walkable(cell) or furnished.walkable(cell):
					continue
				_check(
					middles.has(x),
					"%s, %d cells: the furniture takes %s only in a lane's middle column" % [what, width, cell]
				)
	_check(gaps_seen >= 4, "the cases have lane gaps to furnish: %d" % gaps_seen)


## `model` as a map: itself, or a map of that one workspace.
func _map_of(model: RefCounted) -> MapModel:
	if model is MapModel:
		return model as MapModel
	return MapModel.of(model as ZoneModel)


## The top-wall run and the lane gaps stand on grids of the map itself, never
## on the tables: keyed by the run's grid step, or by the lane and the row, and
## where a zone grows the pieces that still fit keep their key and their place.
func test_the_top_run_and_lane_gaps_keep_their_place_when_a_zone_grows() -> void:
	var rules := _real_rules(32)
	var decor := OfficeDecorPlanner.new(_pen())
	var fixtures := OfficeFixturePlanner.new(_pen())
	var first := (
		OfficeFloorLayout
		. plan(MapModel.of(_floor([_room("a", 2), _room("b", 2, 1)])), null, rules, decor, fixtures)
		. plan
	)
	var grown_model := _floor([_room("a", 2), _room("b", 2, 1), _room("c", 2, 2)])
	var grown := OfficeFloorLayout.plan(MapModel.of(grown_model), first, rules, decor, fixtures).plan
	_check(first != null and grown != null, "both floors are planned")
	if first == null or grown == null:
		return
	_check(grown.zones[0].cells.size.y > first.zones[0].cells.size.y, "the zone grew down")
	var before: Dictionary[String, Vector2] = {}
	for placed in first.decorations:
		before[placed.key] = placed.position
		if placed.key.begins_with("top/"):
			_eq(placed.key, "top/%03d" % placed.key.get_slice("/", 1).to_int(), "keyed by the grid step: " + placed.key)
			_eq(
				placed.position.x,
				OfficeShell.TOP_RUN_FROM + placed.key.get_slice("/", 1).to_int() * OfficeShell.TOP_RUN_PITCH,
				"on the run's grid: " + placed.key
			)
		else:
			var lane := placed.key.get_slice("/", 0).to_int()
			var row := placed.key.get_slice("/", 2).to_int()
			_eq(placed.key, "%02d/gap/%04d" % [lane, row], "keyed by the lane and the row: " + placed.key)
			var middle := (rules.lane_x(lane) + floorf(rules.zone_width_cells / 2.0) + 0.5) * 32.0
			_eq(
				placed.position,
				Vector2(middle, (row + 1) * 32.0 - OfficeShell.LANE_GAP_FOOT),
				"in its lane's middle: " + placed.key
			)
	_check(before.keys().any(func(key: String) -> bool: return key.begins_with("top/")), "the top wall stands a run")
	_check(before.keys().any(func(key: String) -> bool: return "/gap/" in key), "and the other lane a gap's pieces")
	var kept := 0
	for placed in grown.decorations:
		if before.has(placed.key):
			kept += 1
			_eq(placed.position, before[placed.key], "a piece keeps its place: " + placed.key)
	_check(kept == before.size(), "every piece still fits the grown map: %d of %d" % [kept, before.size()])


## Plants and side tables take turns along a lane gap by the piece's number j
## (a side table at an odd one, else plant_at(j / 2): the plants take turns
## too; test_a_lane_gap_stands_both_plants_between_its_side_tables in the map
## suite pins a run of five), and the top-wall
## run's plants take the plant of their grid step (plant_at()), two kinds by
## the place's parity. Never a state, a tab or the time: the planner reads no
## herdr, so the place is all there is to go by. Every piece a furnished map
## stands is the one its key's place names, and a gap of two or more pieces
## reads as a plant and a side table, not a stamp.
func test_lane_gaps_alternate_plants_and_side_tables_by_place() -> void:
	var plant := &"plant"
	var plant_b := &"plant_b"
	_eq(OfficeDecorPlanner.plant_at(pen.art, 0), plant, "place 0 is the first plant")
	_eq(OfficeDecorPlanner.plant_at(pen.art, 1), plant_b, "place 1 is the other")
	_eq(OfficeDecorPlanner.plant_at(pen.art, 2), plant, "and they take turns")
	_eq(OfficeDecorPlanner.plant_at(pen.art, 7), plant_b, "by the place's parity")
	var both_kinds := 0
	var models: Array = [_floor([_room("a", 2), _room("b", 2, 1)]), _three_zones()]
	for width in FURNISHED_WIDTHS:
		for model: RefCounted in models:
			var plan := _furnished(model, width)
			if plan == null:
				continue
			for placed in plan.decorations:
				if placed.key.begins_with("top/"):
					var step := placed.key.get_slice("/", 1).to_int()
					_eq(
						placed.piece,
						OfficeDecorPlanner.plant_at(pen.art, step),
						"%s stands its step's plant" % placed.key
					)
			for gap in OfficeDecorPlanner.lane_gaps(plan, _real_rules(width)):
				var kinds: Dictionary[StringName, bool] = {}
				var pieces := _gap_pieces(plan, gap)
				for placed in pieces:
					var number := floori(
						float(placed.key.get_slice("/", 2).to_int() - gap.top - 1) / OfficeShell.LANE_GAP_STEP_CELLS
					)
					var wanted := (
						OfficeDecorPlanner.plant_at(pen.art, number >> 1)
						if number % 2 == 0
						else ArtContract.PROP_SIDE_TABLE
					)
					_eq(placed.piece, wanted, "%d cells: %s stands the piece of its place" % [width, placed.key])
					kinds[placed.piece] = true
				print(
					(
						"GAP_KINDS %d cells lane %d rows %d..%d: %d pieces, %s"
						% [width, gap.lane, gap.top, gap.end, pieces.size(), kinds.keys()]
					)
				)
				if pieces.size() >= 2:
					_check(
						kinds.has(ArtContract.PROP_SIDE_TABLE) and kinds.size() >= 2,
						"a gap of %d reads as a plant and a side table" % pieces.size()
					)
					both_kinds += 1
	_check(both_kinds > 0, "some gap stands both kinds")


## The top wall's base window run: WINDOW_SPACING apart from 64, skipping the
## door and anything over the pantry.
func _old_window_xs(plan: FloorPlan) -> Array[float]:
	var found: Array[float] = []
	var grid := float(FloorLayoutPolicy.GRID)
	var width := float(plan.floor_cells.size.x) * grid
	var door := OfficeShell.door(plan)
	var window := _pen().art.prop_sprite(ArtContract.PROP_WINDOW)
	for step in int(width / OfficeShell.WINDOW_SPACING):
		var at := OfficeShell.WINDOW_SPACING * (step + 0.5)
		if at < grid * 2 or at > width - grid * 2 or absf(at - door.x) < OfficeShell.WINDOW_CLEARANCE:
			continue
		var span := Rect2(at - window.pivot.x, 0, window.size.x, 1)
		var behind := false
		for fixture in plan.fixtures():
			behind = behind or span.intersects(Rect2(fixture.draw_rect.position.x, 0, fixture.draw_rect.size.x, 1))
		if not behind:
			found.append(at)
	return found


## The windows (OfficeShell.window_xs(), what the floor view draws) run
## WINDOW_SPACING apart, centred in the top wall between the pantry's drawing
## and WINDOW_CLEARANCE short of the lift door: the same gap at both ends, to
## the unit. None stands over the pantry, within WINDOW_CLEARANCE of the door or
## off the wall, and no shipped width has fewer windows than the base run. A
## map without a pantry keeps the base run.
func test_the_window_run_is_centred_between_the_pantry_and_the_door() -> void:
	var window := _pen().art.prop_sprite(ArtContract.PROP_WINDOW)
	var plans: Array[FloorPlan] = []
	for width in FURNISHED_WIDTHS:
		plans.append(_furnished(_floor([_room("a", 2)]), width))
	plans.append(_furnished(_stress_floor(), 20))
	for plan in plans:
		if plan == null:
			continue
		var width := plan.floor_cells.size.x
		var xs := OfficeShell.window_xs(plan, _pen())
		var old := _old_window_xs(plan)
		print("WINDOWS %d cells: %d -> %d %s" % [width, old.size(), xs.size(), xs])
		_check(xs.size() >= old.size(), "%d cells: no fewer windows than the base run (%d)" % [width, old.size()])
		_check(not xs.is_empty(), "%d cells: a window at all" % width)
		var door := OfficeShell.door(plan)
		var wall_end := float(width * FloorLayoutPolicy.GRID - FloorLayoutPolicy.GRID)
		for index in xs.size():
			var at := xs[index]
			var span := Rect2(at - window.pivot.x, 0, window.size.x, 1)
			_check(absf(at - door.x) >= OfficeShell.WINDOW_CLEARANCE, "%d cells: %d clears the door" % [width, at])
			_check(span.position.x >= FloorLayoutPolicy.GRID and span.end.x <= wall_end, "%d on the wall" % at)
			for fixture in plan.fixtures():
				_check(
					not span.intersects(Rect2(fixture.draw_rect.position.x, 0, fixture.draw_rect.size.x, 1)),
					"%d cells: %d is not over the %s" % [width, at, fixture.key]
				)
			if index > 0:
				_eq(at - xs[index - 1], OfficeShell.WINDOW_SPACING, "%d cells: evenly spaced" % width)
		if xs.is_empty() or plan.pantry == null:
			continue
		var left := xs[0] - window.pivot.x - plan.pantry.draw_rect.end.x
		var reach := door.x - OfficeShell.WINDOW_CLEARANCE + window.size.x - window.pivot.x
		var right := reach - (xs[xs.size() - 1] - window.pivot.x + window.size.x)
		_check(
			absf(left - right) <= 1.0, "%d cells: centred, %d on the left and %d on the right" % [width, left, right]
		)
	var lobby := OfficeFloorLayout.plan(MapModel.of(_floor([])), null, _real_rules(32)).plan
	_eq(OfficeShell.window_xs(lobby, _pen()), _old_window_xs(lobby), "a floor without a pantry keeps the base run")


# --- the walk graph (OfficeWalkGraph) ---------------------------------------------


## No node sits inside an obstacle and no edge enters one, every obstacle
## inflated by the real person: the feet for everything, the whole drawing for
## the Ground walls. A thin post between two clear centres, which the native
## AStarGrid2D steps straight through even with its points on the centres
## (docs/WORLD_MODEL.md, "Collision and walking"), takes that edge away and leaves both nodes.
func test_no_walk_graph_edge_enters_an_obstacle() -> void:
	# 32 cells: two lanes, so the top wall stands a plant (the pods leave the
	# one-lane stress map at 20 cells no furniture).
	var rules := _real_rules(32)
	var plan := OfficeFloorLayout.plan(MapModel.of(_stress_floor()), null, rules, OfficeDecorPlanner.new(_pen())).plan
	_check(plan != null and not plan.decorations.is_empty(), "a furnished stress floor to walk")
	if plan == null:
		return
	# A post across the edge between two clear centres of the walking lane.
	var left := Vector2i(plan.entry_cells.position.x + 3, plan.entry_cells.end.y - 1)
	var at := OfficeWalkGraph.centre(left) + Vector2(15, -4)
	plan.decorations.append(_decoration("post", Rect2(at, Vector2(2, 8))))
	var graph := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
	_check(graph.walkable(left) and graph.walkable(left + Vector2i.RIGHT), "the post covers neither centre")
	_check(not graph.linked(left, OfficeWalkGraph.RIGHT), "but no edge goes through it")
	_check(not graph.linked(left + Vector2i.RIGHT, OfficeWalkGraph.LEFT), "either way")
	var native := AStarGrid2D.new()
	native.region = Rect2i(Vector2i.ZERO, plan.floor_cells.size)
	native.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	native.update()
	for y in plan.floor_cells.size.y:
		for x in plan.floor_cells.size.x:
			native.set_point_solid(Vector2i(x, y), not graph.walkable(Vector2i(x, y)))
	_eq(native.get_id_path(left, left + Vector2i.RIGHT).size(), 2, "where the native grid steps straight through")
	var edges := 0
	for y in plan.floor_cells.size.y:
		for x in plan.floor_cells.size.x:
			var cell := Vector2i(x, y)
			if not graph.walkable(cell):
				continue
			var from := OfficeWalkGraph.centre(cell)
			for obstacle in graph.obstacles:
				if _enters(from, from, obstacle.rect):
					_fail("node %s is inside %s" % [cell, obstacle.rect])
			for direction: int in [OfficeWalkGraph.RIGHT, OfficeWalkGraph.DOWN]:
				if not graph.linked(cell, direction):
					continue
				edges += 1
				var to := OfficeWalkGraph.centre(cell + OfficeWalkGraph.STEPS[direction])
				for obstacle in graph.obstacles:
					if _enters(from, to, obstacle.rect):
						_fail("edge %s -> %s enters %s" % [from, to, obstacle.rect])
	var cells := plan.floor_cells.size.x * plan.floor_cells.size.y
	_check(edges * 2 > cells, "a floor's worth of edges was checked: %d over %d cells" % [edges, cells])


## Planning a floor builds its walk graph once, to validate it, and whoever
## walks that floor walks that very graph: what the validator reached is what
## the walkers reach, from the same door.
func test_the_validator_and_the_walkers_walk_one_graph() -> void:
	var cache := FloorPlanCache.new()
	var built := OfficeWalkGraph.builds
	var plan := cache.prepare(MapModel.of(_floor([_room("a", 4), _room("b", 2, 1), _room("c", 6, 2)])), _pen(), 640.0)
	_check(plan != null and cache.problems().is_empty(), "a valid floor")
	_eq(OfficeWalkGraph.builds - built, 1, "planning it builds one walk graph, to validate it")
	var feet := PixelPerson.footprint()
	var canvas := PixelPerson.drawing_rect(_pen().art.people)
	var walked := OfficeWalkGraph.of(plan, feet, canvas)
	_eq(OfficeWalkGraph.builds - built, 1, "the walkers of that floor take the validator's graph")
	_eq(OfficeWalkGraph.of(plan, feet, canvas), walked, "every time they ask")
	var approaches := 0
	var columns := 0
	for placed in plan.desks:
		columns += placed.capacity
		for column in placed.capacity:
			for side: String in OfficeTable.SIDES:
				var cell := OfficeWalkGraph.cell_of(placed.origin + placed.measure.approach_position(column, side))
				var route := walked.from_door(cell)
				_check(
					walked.reaches(cell) and not route.is_empty(),
					"%s %d %s is walked to" % [placed.tab_key, column, side]
				)
				approaches += 1
	_check(columns >= 8, "three tables of %d columns" % columns)
	_eq(approaches, columns * 2, "every approach of every column, both sides")


## The validator walks in from the lift door's threshold, as everyone does, not
## from wherever the entry band is open: a person who cannot step through the
## door is refused a floor even while most of the band beside it is open to them.
func test_the_validator_walks_in_from_the_door_not_the_entry_band() -> void:
	var lobby := _plan(_floor([]))
	var rules := FloorLayoutPolicy.new()
	rules.actor_footprint = PixelPerson.footprint()
	# So wide that the side wall's drawing keeps them off the door's lane.
	rules.actor_draw_rect = Rect2(-56, -46, 112, 48)
	var problems := OfficeFloorLayout.validate(lobby, rules)
	_check(
		problems.has("the lift door has no clear threshold"), "a door nobody can walk in through fails: %s" % [problems]
	)
	var graph := OfficeWalkGraph.build(lobby, rules.actor_footprint, rules.actor_draw_rect)
	var open := 0
	for x in range(lobby.entry_cells.position.x, lobby.entry_cells.end.x):
		open += 1 if graph.walkable(Vector2i(x, lobby.entry_cells.end.y - 1)) else 0
	_check(open * 2 > lobby.entry_cells.size.x, "though %d of the entry band's cells are open" % open)


## Every approach of the stress fixture's floor, 20 and 32 cells wide, is walked
## to from the door's threshold, and still is after two tables grow and the
## floor moves them.
func test_every_approach_is_walked_to_on_the_stress_floor_and_after_growth() -> void:
	for width: int in [20, 32]:
		var rules := _real_rules(width)
		var floor_model := _stress_floor()
		var first := OfficeFloorLayout.plan(MapModel.of(floor_model), null, rules, OfficeDecorPlanner.new(_pen()))
		_eq(first.problems, PackedStringArray(), "the stress floor %d cells wide is valid" % width)
		if first.plan == null:
			continue
		_every_approach_walked(first.plan, rules, "stress, %d cells" % width)
		for tab: int in [0, 7]:
			for extra in 4:
				var column := 4 + floori(extra / 2.0)
				floor_model.rooms[tab].panes.append(
					_pane("stress-%d-x%d" % [tab, extra], column, "far" if extra % 2 == 0 else "near", 8 + extra)
				)
		var grown := OfficeFloorLayout.plan(MapModel.of(floor_model), first.plan, rules, OfficeDecorPlanner.new(_pen()))
		_eq(grown.problems, PackedStringArray(), "and after growth")
		if grown.plan == null:
			continue
		_check(grown.plan.geometry_signature() != first.plan.geometry_signature(), "the floor really changed")
		_every_approach_walked(grown.plan, rules, "stress, %d cells, grown" % width)


## From a table's approach two legs go on, never diagonal: L-shaped to the spot
## a done worker stands on, and into the seat. On the far side the standing leg
## runs first in line with the seat, then across, and the seat leg straight in;
## on the near side both go across first, to the spot's column, so nobody walks
## through the chair: the seat leg is the standing leg and a sidestep into the
## seat. The validator walks both on the same obstacles. Only the far seat leg
## enters the table (the far seat is inside it), and only along itself: the
## table's entries, not the table's name. A post on a leg is a problem of its
## own, the other leg left clear; a post where a straight near leg would cut
## through the chair blocks nothing.
func test_the_seat_and_standing_legs_are_validated() -> void:
	var rules := _real_rules()
	var plan := _plan(_floor([_room("a", 2)]), null, rules)
	var placed := plan.desks[0]
	# A furniture-only profile: the table's drawing does not cover its legs.
	placed.measure.render_rect = placed.measure.physical_rect
	for side: String in OfficeTable.SIDES:
		var near := side == "near"
		var approach := placed.origin + placed.measure.approach_position(0, side)
		var standing := placed.origin + placed.measure.standing_position(0, side)
		var seat := placed.origin + placed.measure.seat_position(0, side)
		var corner := Vector2(standing.x, approach.y) if near else Vector2(approach.x, standing.y)
		var across := OfficeWalkGraph.leg_to_standing(approach, standing, near)
		_eq(across, PackedVector2Array([approach, corner, standing]), side + ": an L")
		var into := OfficeWalkGraph.leg_to_seat(approach, seat, standing, near)
		var expected := (
			PackedVector2Array([approach, corner, standing, seat]) if near else PackedVector2Array([approach, seat])
		)
		_eq(into, expected, side + (": across, up and a sidestep in" if near else ": straight in"))
		for leg: PackedVector2Array in [across, into]:
			for index in range(1, leg.size()):
				var step := leg[index] - leg[index - 1]
				_check(step.x == 0.0 or step.y == 0.0, "%s: every step is straight: %s" % [side, step])
				if near:
					_check(
						not (step.x == 0.0 and leg[index].x == seat.x),
						"%s: nothing runs up or down the chair's column: %s" % [side, leg]
					)
	var graph := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
	var far := placed.origin + placed.measure.approach_position(0, "far")
	var far_seat := placed.origin + placed.measure.seat_position(0, "far")
	var far_spot := placed.origin + placed.measure.standing_position(0, "far")
	var into_far := OfficeWalkGraph.leg_to_seat(far, far_seat, far_spot, false)
	_check(graph.clear_route(into_far), "the far seat leg enters its own table, along itself")
	var beside := PackedVector2Array([into_far[0] + Vector2(8, 0), into_far[1] + Vector2(8, 0)])
	_check(not graph.clear_route(beside), "and nothing else enters it, not even a step beside the leg")
	_check(
		not graph.clear(far, far_seat + Vector2(0, 8)),
		"and only along its own length: not on past the seat, still inside the table"
	)
	_eq(OfficeFloorLayout.validate(plan, rules), PackedStringArray(), "which the validator allows")
	# Between the corner (far standing row, -54) and the desk's far edge (-48).
	plan.decorations.append(_decoration("post", Rect2(Vector2(far.x - 2, placed.origin.y - 52), Vector2(4, 2))))
	_eq(
		OfficeFloorLayout.validate(plan, rules),
		PackedStringArray(["blocked seat leg: a column 0 far"]),
		"a post between the corner and the table blocks the far seat leg alone"
	)
	plan.decorations.clear()
	# On the step across (y -54, feet -58..-54), between the seat leg's feet
	# (x +-6) and the standing spot's (x+10..x+22).
	plan.decorations.append(_decoration("post", Rect2(Vector2(far.x + 7, placed.origin.y - 58), Vector2(2, 8))))
	_eq(
		OfficeFloorLayout.validate(plan, rules),
		PackedStringArray(["blocked standing leg: a column 0 far"]),
		"a post on the step across blocks the far standing leg alone"
	)
	var near := placed.origin + placed.measure.approach_position(0, "near")
	plan.decorations.clear()
	plan.decorations.append(_decoration("post", Rect2(Vector2(near.x - 2, placed.origin.y + 34), Vector2(4, 2))))
	_eq(
		OfficeFloorLayout.validate(plan, rules),
		PackedStringArray(),
		"a post in the near chair's column, where a straight leg would cut through, blocks nothing"
	)
	plan.decorations.clear()
	plan.decorations.append(_decoration("post", Rect2(Vector2(near.x + 11, placed.origin.y + 44), Vector2(2, 8))))
	_eq(
		OfficeFloorLayout.validate(plan, rules),
		PackedStringArray(["blocked standing leg: a column 0 near", "blocked seat leg: a column 0 near"]),
		"a post on the near step across blocks both near legs, which share it"
	)


## The lift door stands on the outer wall over the main corridor's left lane,
## wherever the floor's width puts that corridor, and its threshold leg runs
## straight down to the first cell centre clear of the wall's drawing.
func test_the_lift_door_stands_over_the_main_corridor() -> void:
	for width: int in [20, 32, 45]:
		var rules := _real_rules(width)
		var plan := _plan(_floor([_room("a", 2)]), null, rules)
		var corridor := plan.main_corridor_cells
		var door := OfficeShell.door(plan)
		_eq(door, Vector2(corridor.position.x * 32 + 16, OfficeShell.DOOR_FOOT), "%d cells: over the left lane" % width)
		var graph := _graph_of(plan, rules)
		_eq(graph.door, door, "%d cells: the graph walks in at it" % width)
		_eq(graph.threshold, Vector2(door.x, 112), "%d cells: to the first cell centre clear of the wall" % width)
		var clearance := graph.obstacles.filter(
			func(each: OfficeWalkGraph.Obstacle) -> bool:
				return (
					each.kind == OfficeWalkGraph.Kind.WALL_DRAWING and Rect2(door, Vector2.ZERO).intersects(each.rect)
				)
		)
		_check(not clearance.is_empty(), "%d cells: the door's foot is inside the wall's drawing clearance" % width)
		_check(not graph.inside(door), "%d cells: where the threshold leg lets it stand" % width)
		_check(graph.clear(door, graph.threshold), "and the leg is the way in through that clearance")
		_check(
			not graph.clear(door + Vector2(8, 0), graph.threshold + Vector2(8, 0)),
			"%d cells: which no step beside it is" % width
		)


## route_between() walks from whichever end is cheaper in all, the lead it has
## already walked included, not whichever is fewer steps away: an end two steps
## from the goal that has walked 200 units already loses to one six steps away
## that has walked none. And on a seeded run of goals, ends and leads, what it
## finds costs exactly what a plain breadth-first search from the goal says the
## cheapest end costs.
func test_route_between_walks_from_the_cheaper_end() -> void:
	var rules := _real_rules(20)
	var plan := _plan(_floor([_room("a", 2)]), null, rules)
	var graph := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
	var lane := plan.entry_cells.end.y - 1
	var goal := Vector2i(2, lane)
	var near := goal + Vector2i(2, 0)
	var far := goal + Vector2i(6, 0)
	for cell: Vector2i in [goal, near, far]:
		_check(graph.walkable(cell), "the walking lane is open at %s" % cell)
	var ends: Array[Vector2i] = [near, far]
	var found := graph.route_between(
		goal, ends, PackedFloat32Array([200.0, 0.0]), PackedInt32Array([-1, -1]), 100000, 1000
	)
	_eq(found.end, 1, "the end six steps away that has walked nothing beats the one two steps away that has walked 200")
	found = graph.route_between(goal, ends, PackedFloat32Array([0.0, 0.0]), PackedInt32Array([-1, -1]), 100000, 1000)
	_eq(found.end, 0, "with no leads the nearer end wins")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var open: Array[Vector2i] = []
	for y in graph.size.y:
		for x in graph.size.x:
			if graph.walkable(Vector2i(x, y)):
				open.append(Vector2i(x, y))
	var compared := 0
	for trial in 40:
		var target := open[rng.randi() % open.size()]
		var reference := _reference_distances(graph, target)
		var picks: Array[Vector2i] = []
		var leads := PackedFloat32Array()
		var headings := PackedInt32Array()
		for index in 1 + rng.randi() % 3:
			picks.append(open[rng.randi() % open.size()])
			leads.append(float(rng.randi() % 400))
			headings.append(-1)
		var cheapest := INF
		for index in picks.size():
			if reference.has(picks[index]):
				cheapest = minf(cheapest, reference[picks[index]] * 32.0 + leads[index])
		var result := graph.route_between(target, picks, leads, headings, 1000000, 100000)
		if cheapest == INF:
			_eq(result.end, -1, "trial %d: no end reached, none found" % trial)
			continue
		_check(result.end >= 0, "trial %d: an end is found" % trial)
		if result.end < 0:
			continue
		var cost: float = reference[picks[result.end]] * 32.0 + leads[result.end]
		_eq(cost, cheapest, "trial %d: the end it walks from is a cheapest one" % trial)
		_eq(result.points.size(), reference[picks[result.end]] + 1, "trial %d: by a shortest route" % trial)
		compared += 1
	_check(compared >= 30, "the search was compared %d times" % compared)


## Steps from `goal` to every node the graph links it to: a plain BFS over
## linked(), the reference route_between() is held to.
static func _reference_distances(graph: OfficeWalkGraph, goal: Vector2i) -> Dictionary[Vector2i, int]:
	var distance: Dictionary[Vector2i, int] = {goal: 0}
	var queue: Array[Vector2i] = [goal]
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction in 4:
			if graph.linked(cell, direction):
				var next: Vector2i = cell + OfficeWalkGraph.STEPS[direction]
				if not distance.has(next):
					distance[next] = distance[cell] + 1
					queue.append(next)
	return distance


func _real_rules(width := 32) -> FloorLayoutPolicy:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = width
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	return rules


func _graph_of(plan: FloorPlan, rules: FloorLayoutPolicy) -> OfficeWalkGraph:
	return OfficeWalkGraph.of(plan, rules.actor_footprint, rules.actor_draw_rect)


## The floor of tools/gen_stress_fixture.py's snapshot_stress80: ten tabs of
## eight agents, two to a column, far and near.
func _stress_floor() -> ZoneModel:
	var rooms: Array[RoomModel] = []
	for tab in 10:
		var room := _room("stress-%d" % tab, 0, tab + 1)
		for index in 8:
			var side := "far" if index % 2 == 0 else "near"
			room.panes.append(_pane("stress-%d-p%d" % [tab, index], floori(index / 2.0), side, index))
		rooms.append(room)
	return _floor(rooms)


## Every approach of `plan` is walked to from its door, through the threshold.
func _every_approach_walked(plan: FloorPlan, rules: FloorLayoutPolicy, where: String, least := 80) -> void:
	var graph := _graph_of(plan, rules)
	var count := 0
	for placed in plan.desks:
		for column in placed.capacity:
			for side: String in OfficeTable.SIDES:
				var approach := placed.origin + placed.measure.approach_position(column, side)
				var route := graph.from_door(OfficeWalkGraph.cell_of(approach))
				var named := "%s: %s %d %s" % [where, placed.tab_key, column, side]
				_check(
					route.size() >= 2 and route[0] == graph.door and route[1] == graph.threshold,
					named + " from the door"
				)
				if not route.is_empty():
					_eq(route[route.size() - 1], approach, named + " to the approach")
				count += 1
	_check(count >= least, "%s: every approach, %d of them" % [where, count])


## Whether the segment from `from` to `to` (a point when they are equal) has a
## point strictly inside `box`; touching its edge is not entering it.
static func _enters(from: Vector2, to: Vector2, box: Rect2) -> bool:
	var low := from.min(to)
	var high := from.max(to)
	var inside_x := low.x < box.end.x and high.x > box.position.x
	var inside_y := low.y < box.end.y and high.y > box.position.y
	if from.x == to.x:
		inside_x = from.x > box.position.x and from.x < box.end.x
	if from.y == to.y:
		inside_y = from.y > box.position.y and from.y < box.end.y
	return inside_x and inside_y
