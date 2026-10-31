extends Button
## Постоянная клавиша меню (нарисована Tab, работают и Tab, и Esc): контраст — от цвета текста стола.
var ink := Color(0.68, 0.69, 0.71)


func set_ink(table_ink: Color) -> void:
	var light_background := table_ink.get_luminance() < 0.5
	ink = Color.BLACK if light_background else Color(0.68, 0.69, 0.71)
	modulate.a = 0.8 if light_background else 0.2
	queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(58, 36)  # Tab длиннее Esc
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
	var label_size := font.get_string_size("Tab", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# как на настоящей клавише: «Tab» слева, стрелка «⇥» справа
	var arrow_w := 12.0
	var gap := 5.0
	var left := face_rect.get_center().x - (label_size.x + gap + arrow_w) * 0.5
	var baseline := Vector2(left, face_rect.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string(font, baseline, "Tab", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	var ay := face_rect.get_center().y
	var ax := left + label_size.x + gap
	draw_line(Vector2(ax, ay), Vector2(ax + arrow_w - 2, ay), ink, 1.5, true)
	draw_polyline(PackedVector2Array([Vector2(ax + arrow_w - 6, ay - 3.5), Vector2(ax + arrow_w - 2, ay), Vector2(ax + arrow_w - 6, ay + 3.5)]), ink, 1.5, true)
	draw_line(Vector2(ax + arrow_w, ay - 4.5), Vector2(ax + arrow_w, ay + 4.5), ink, 1.5, true)
