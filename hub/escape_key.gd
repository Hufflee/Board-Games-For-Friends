extends Button
## Постоянная клавиша Esc: контраст определяется реальным цветом текста стола.
var ink := Color(0.68, 0.69, 0.71)


func set_ink(table_ink: Color) -> void:
	var light_background := table_ink.get_luminance() < 0.5
	ink = Color.BLACK if light_background else Color(0.68, 0.69, 0.71)
	modulate.a = 0.8 if light_background else 0.2
	queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(36, 36)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	modulate.a = 0.2
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var inset := Vector2(3, 2) if not is_pressed() else Vector2(3, 4)
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color(0.5, 0.5, 0.5, 0.12)
	outer.border_color = ink
	outer.set_border_width_all(2)
	outer.set_corner_radius_all(8)
	draw_style_box(outer, Rect2(Vector2(2, 2), size - Vector2(4, 4)))
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.5, 0.5, 0.5, 0.08)
	face.border_color = ink
	face.set_border_width_all(2)
	face.set_corner_radius_all(6)
	var face_rect := Rect2(Vector2(7, 2) + inset - Vector2(3, 2), size - Vector2(14, 12))
	draw_style_box(face, face_rect)
	draw_line(Vector2(3, size.y - 7), face_rect.position + Vector2(1, face_rect.size.y - 2), ink, 2, true)
	draw_line(Vector2(size.x - 3, size.y - 7), face_rect.end - Vector2(1, 2), ink, 2, true)
	var font := get_theme_font("font")
	var font_size := 11
	var label_size := font.get_string_size("Esc", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := face_rect.get_center() + Vector2(-label_size.x * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string(font, baseline, "Esc", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
