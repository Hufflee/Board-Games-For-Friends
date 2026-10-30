extends TextureRect
## Открытая карта: перенос Godot, крупный просмотр и перевод через стол.
const Data := preload("res://games/things_in_rings/logic/tr_data.gd")
const Corners := preload("res://hub/card_corners.gdshader")
var table: Control
var card := -1
var movable := false
var judge_drag := false  # красная карта у знающего: перетащить в верную зону

func _ready() -> void:
	texture = Data.texture(card)
	var mask := ShaderMaterial.new()
	mask.shader = Corners
	material = mask
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	load("res://games/things_in_rings/ui/tr_style.gd").outline(self)
	mouse_entered.connect(func(): table.preview_card(card))
	mouse_exited.connect(func(): table.clear_preview())
	gui_input.connect(_clicked)

func _clicked(event: InputEvent) -> void:
	if movable and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		table.select_card(card)

func _get_drag_data(_at: Vector2) -> Variant:
	if not movable and not judge_drag:
		return null
	var picture := TextureRect.new()
	picture.texture = texture
	picture.material = material
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(88, 136)
	set_drag_preview(picture)
	if judge_drag:
		return {"tr_judge": card, "revision": table.view.revision, "seat": table.view.you}
	return {"tr_card": card, "revision": table.view.revision, "seat": table.view.you}
