extends Control
## Самостоятельный фон Things in Rings без поля и карточек; подходит и для итогов.
const Style := preload("res://games/things_in_rings/ui/tr_style.gd")

func _ready() -> void:
	add_to_group("tr_backdrop")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

var _offset := Vector2.ZERO

func _process(delta: float) -> void:
	var target := (get_global_mouse_position() / size.max(Vector2.ONE) - Vector2(0.5, 0.5)) * 20.0
	_offset = _offset.lerp(target.limit_length(16.0), minf(1.0, delta * 4.0))
	queue_redraw()

func _draw() -> void:
	paint(self, size, _offset)

static func paint(surface: Control, dimensions: Vector2, offset: Vector2 = Vector2.ZERO) -> void:
	var bg := Color("211e29") if Prefs.dark_theme() else Color("e4d5bc")
	surface.draw_rect(Rect2(Vector2.ZERO, dimensions), bg)
	for i: int in 3:
		var center := Vector2(dimensions.x * (0.15 + i * 0.37), dimensions.y * (0.24 if i % 2 == 0 else 0.8))
		center += offset * (0.5 + i * 0.25)
		surface.draw_circle(center, dimensions.y * 0.34, Color(Style.RINGS[i], 0.055))
		surface.draw_arc(center + Vector2(3, 1), dimensions.y * 0.34, 0, TAU, 80, Color(Style.ink(), 0.035), 3, true)
