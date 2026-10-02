class_name SpaceRows
extends RefCounted
## One machine's section of the SPACES rail: its heading and its zones' rows.
##
## The rail knows no herdr and no fleet, so whether the machine is live arrives
## as a plain state the office decided.

var key := ""
var label := ""
## How the machine is answering: the heading's mark.
var state := MachineLiveness.State.LIVE
## Ascending by workspace number, the way the office projected them; the rail
## draws them in OfficeNavigator.section()'s order: ascending, each mezzanine
## right after its source.
var zones: Array[ZoneModel] = []
## Zone key -> what its sign's tooltip says (OfficeQuestionTips.sign_text()):
## repository, checkout, whose worktree. The row's tooltip says it too.
var tips: Dictionary[String, String] = {}


static func of(building: BuildingModel, live_state: MachineLiveness.State) -> SpaceRows:
	var rows := SpaceRows.new()
	rows.key = building.key
	rows.label = building.label
	rows.state = live_state
	rows.zones = building.zones
	for zone in building.zones:
		rows.tips[zone.key] = OfficeQuestionTips.sign_text(ZoneRef.new(building, zone))
	return rows
