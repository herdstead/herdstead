class_name OfficeSignposts
extends VBoxContainer
## The signposts over the world's top-right corner: one per other floor with
## agents blocked on it (the office's SignpostModel list), highest floor first,
## and a click on one shows that floor. The HUD hides them while no other floor
## is waiting, and on a world too narrow for them (OfficeHud.signposts_yield()).
##
## A fixed set of POSTS nodes in the scene: past that many floors the last post
## says `+N floors` instead. A refresh only writes text and visibility.

## A post was pressed; `key` is that floor's key.
signal floor_picked(key: String)
## The mouse came onto a post for floor `key` (`""` for the `+N floors` note),
## or left it (`""`).
signal floor_pointed(key: String)

## How many posts the scene holds.
const POSTS := 6


func _ready() -> void:
	for post in _posts():
		post.floor_picked.connect(func(key: String) -> void: floor_picked.emit(key))
		post.mouse_entered.connect(func() -> void: floor_pointed.emit(post.key()))
		post.mouse_exited.connect(func() -> void: floor_pointed.emit(""))


## Take the pack's art in every post; a theme switch rebuilds nothing.
func dress(art: ArtPack) -> void:
	for post in _posts():
		post.dress(art)


## Draw `posts`, in order. Up to POSTS of them each get a post; more, and the
## first POSTS - 1 do while the last one counts the rest. Whether the column
## shows at all is the HUD's (OfficeHud._fit_signposts()).
func show_posts(posts: Array[SignpostModel]) -> void:
	var drawn := _posts()
	var direct := posts.size() if posts.size() <= POSTS else POSTS - 1
	for index in drawn.size():
		var post := drawn[index]
		if index < direct:
			post.show_post(posts[index])
			post.visible = true
		elif index == direct and posts.size() > direct:
			var rest: Array[SignpostModel] = []
			rest.assign(posts.slice(direct))
			post.show_more(rest)
			post.visible = true
		elif post.visible:
			post.hide_post()


## The posts shown now, top to bottom.
func shown() -> Array[OfficeSignpost]:
	var found: Array[OfficeSignpost] = []
	for post in _posts():
		if post.visible:
			found.append(post)
	return found


func _posts() -> Array[OfficeSignpost]:
	var found: Array[OfficeSignpost] = []
	for child in get_children():
		if child is OfficeSignpost:
			found.append(child)
	return found
