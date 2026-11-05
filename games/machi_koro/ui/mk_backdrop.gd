extends Control
## Город из стайлборда: дневная и ночная версии, без интерфейса внутри изображения.
const Art := preload("res://games/machi_koro/ui/mk_art.gd")
const Style := preload("res://games/machi_koro/ui/mk_style.gd")

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var path := "res://games/machi_koro/art/city_night.png" if Style.dark() else "res://games/machi_koro/art/city_day.png"
	var texture := Art.texture(path)
	if texture == null:
		draw_rect(Rect2(Vector2.ZERO, size), Style.background())
		return
	# Поднимаем панораму над картами; тихая нижняя часть заполняет остальной стол.
	draw_texture_rect(texture, Rect2(Vector2(0, -48), Vector2(size.x, size.y + 48)), false)
