extends AspectRatioContainer
## Парные карточки героя: рубашка колоды слева, памятка героя справа.

const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const PAIR_RATIO := 1.48

var hero := ""
var _back: TextureRect
var _face: TextureRect


func _init() -> void:
	ratio = PAIR_RATIO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_back = _card("Back")
	_face = _card("Face")
	row.add_child(_back)
	row.add_child(_face)
	add_child(row)


func show_hero(key: String) -> void:
	hero = key
	_back.texture = Art.back(key)
	_face.texture = Art.reference_face(key)


func _card(node_name: String) -> TextureRect:
	var card := TextureRect.new()
	card.name = node_name
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Art.round_corners(card)
	return card
