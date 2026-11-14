extends Control
## Независимый заголовок лица предмета, вписанный в пустой верх иллюстрации.

const FONT := preload("res://games/things_in_rings/art/fonts/TIR-Press.ttf")
const Data := preload("res://games/things_in_rings/logic/tr_data.gd")

var title := ""

static func put(face: TextureRect, id: int) -> void:
	var layer := face.get_node_or_null("CardTitle") as Control
	if not Data.has_title_layer(id):
		if layer != null:
			layer.hide()
		return
	if layer == null:
		layer = load("res://games/things_in_rings/ui/tr_card_title.gd").new()
		layer.name = "CardTitle"
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.add_child(layer)
	layer.title = Data.card_name(id).to_upper()
	layer.show()
	layer.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if title.is_empty() or size.x < 1.0 or size.y < 1.0:
		return
	var face := get_parent() as TextureRect
	if face.texture == null:
		return
	var art := face.texture.get_size()
	art *= minf(size.x / art.x, size.y / art.y)
	var origin := (size - art) * 0.5
	var font_size := maxi(1, roundi(art.x * 0.151))
	var max_width := art.x * 0.89
	var width := FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if width > max_width:
		font_size = maxi(1, floori(font_size * max_width / width))
		width = FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (FONT.get_ascent(font_size) - FONT.get_descent(font_size)) * 0.5
	var start := origin + Vector2((art.x - width) * 0.5, art.y * 0.11 + baseline)
	draw_string_outline(FONT, start, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		maxi(1, roundi(font_size * 0.15)), Color("221b26"))
	draw_string(FONT, start, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("fff4df"))
