class_name StatusBadge
extends Sprite2D
## The mark that says a pane needs a human: the badge over a seat, the two icons
## on a minimap row, a signpost's and the inspector's portrait badge are all this node.
##
## What OfficeAttention has to know to step a badge — whose machine, which pane,
## which state — are typed fields here, and the pulse itself is one call: the
## badge is the only place that knows how a lift in density-1 units becomes a
## texture-pixel `offset`, because the pack's pivot lives in that same offset
## and it is applied before the node's own scale.

## Every badge the attention clock steps; the badge joins and leaves it itself.
const GROUP := &"office_badges"

## The machine whose connection freezes this badge. Empty while it pulses for
## nobody, which is also when it is out of GROUP.
var machine := ""
## The pane this badge sits over; empty on a minimap icon, which stands for a
## whole floor rather than one seat.
var pane_id := ""
## The herdr state being waited on, `&""` while the badge pulses for nobody.
var state := &""
## Where the pack's pivot puts this badge. Every pulse moves from here, never
## over it: writing a bare lift into `offset` once dropped every badge by the
## pivot's whole height.
var rest_offset := Vector2.ZERO
## The label beside this badge saying how long its agent has been waiting (an
## agent list row's tail); the attention clock writes it on the same beat as
## the inspector's. A minimap icon stands for a whole floor, which nobody is
## waiting on, so not every badge has one, and every writer checks.
var wait: Label
## A seat's badge says the same in the chip on its blocked agent's tag row
## (OfficeBubble: the wait, in the compact form), on the same beat.
var bubble: OfficeBubble


## Draw `art`'s `id` sprite and take the pivot it declares as this badge's rest.
## Whether the badge is shown, and whether it pulses, are the caller's to say.
func show_badge(art: ArtPack, id: StringName) -> void:
	var image := art.ui_sprite(id)
	art.dress(self, art.sprite_texture(image), image.pivot)
	rest_offset = offset


## No badge here at all: hidden, out of the pulse, and still dressed by the pack
## so a badge that comes back is this same node with the same scale and filter.
func clear(art: ArtPack) -> void:
	stop_pulsing()
	art.dress(self, null)
	rest_offset = offset
	visible = false


## Pulse for `for_pane` on `for_machine`, in `for_state`. A minimap icon
## stands for a floor rather than a seat and passes an empty pane.
func pulse_for(for_machine: String, for_pane: String, for_state: StringName) -> void:
	machine = for_machine
	pane_id = for_pane
	state = for_state
	# Only a blocked agent is being waited on; any other state takes the number
	# away now rather than on the clock's next beat.
	if for_state != ArtContract.STATE_BLOCKED:
		show_wait(-1.0)
	if not is_in_group(GROUP):
		add_to_group(GROUP)


## Nobody is waiting on this badge: it keeps its art and stops being stepped.
func stop_pulsing() -> void:
	machine = ""
	pane_id = ""
	state = &""
	show_wait(-1.0)
	if is_in_group(GROUP):
		remove_from_group(GROUP)


## How long this badge's agent has been waiting, `seconds`, or below 0 for no
## number at all (OfficeAttention.format_duration() writes nothing for it).
## The label only ever changes its text, never its visibility: an empty label
## draws nothing, and a node that came and went would make an in-place update
## differ from a rebuild of the same data. The chip hides its frame the same way.
func show_wait(seconds: float) -> void:
	var text := OfficeAttention.format_duration(seconds)
	if is_instance_valid(wait) and wait.text != text:
		wait.text = text
	if is_instance_valid(bubble):
		bubble.show_wait(seconds)


## Raise the badge `units` density-1 units above its rest. Offset is applied
## before scale, so the lift is turned into this art family's own pixels here;
## no caller has to know the pack's density.
func lift(units: float) -> void:
	var target := rest_offset + Vector2(0, units / scale.y)
	if offset != target:
		offset = target
