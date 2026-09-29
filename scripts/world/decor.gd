class_name OfficeDecor
extends StaticBody2D
## One piece of standing furniture on a floor: scenes/world/decor.tscn.
##
## Furniture, never a signal. A plant does not wilt, a cabinet does not count
## repositories, and nothing here ever reads a herdr field: where these stand
## follows only from the floor's own layout, so the same floor looks the same
## every time and a status change moves not one pixel of it.
##
## The origin is where the piece meets the floor, it goes in the floor's
## y-sorted root, and it carries a footprint on OfficeWorld.FURNITURE, because
## walking is already decided and a walker's feet have to be stopped by a
## cabinet exactly the way they are stopped by a table.

## The semantic id of the piece drawn here; empty until setup().
var piece := &""


## Stand `id` here. Refuses, draws nothing and answers false for a piece this
## prefab has no footprint for, or one the pack does not ship: this is the
## creation boundary, so no caller ends up with a body that blocks nothing.
func setup(art: ArtPack, id: StringName) -> bool:
	var image := art.prop_sprite(id)
	if image == null:
		push_error("OfficeDecor: this pack has no " + id)
		return false
	if footprint_of(art, id) == Vector2.ZERO:
		push_error("OfficeDecor: nothing here stands as " + id)
		return false
	piece = id
	var body: Sprite2D = $Body
	art.dress(body, art.sprite_texture(image), image.pivot)
	var size := footprint_of(art, id)
	var box := RectangleShape2D.new()
	box.size = size
	var shape: CollisionShape2D = $Footprint
	shape.shape = box
	shape.position = Vector2(0, -size.y / 2.0)
	return true


## Where this piece stands on the floor, in global coordinates: what a caller
## checks a seat's click target or a table's footprint against.
func footprint_rect() -> Rect2:
	var shape: CollisionShape2D = $Footprint
	var box: RectangleShape2D = shape.shape
	if box == null:
		return Rect2(global_position, Vector2.ZERO)
	return Rect2(shape.global_position - box.size / 2.0, box.size)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		collision_layer = OfficeWorld.FURNITURE


## What `id` stands on, in units, measured at its foot (its pack entry's `item`
## footprint, docs/ITEMS.md): the prefab's own geometry, the way the
## cross-section is the table's. The two counters of the entry band stand on
## their whole width, which the fixture planner lays the reception's queue
## slots and the pantry's spots out from. Zero for a piece that does not stand
## on the floor.
static func footprint_of(art: ArtPack, id: StringName) -> Vector2:
	var sprite := art.prop_sprite(id)
	if sprite == null or sprite.item == null or sprite.item.place != ItemSpec.PLACE_FLOOR:
		return Vector2.ZERO
	return sprite.item.footprint
