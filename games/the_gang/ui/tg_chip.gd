extends Control
## Настоящая 2D-фишка из листа владельца; номинал читается и для мест7–10.

const SHEET := preload("res://hub/covers/the gang фишки.png")
var value := 1
var round_index := 0

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	resized.connect(queue_redraw)

func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var rect := Rect2(size * 0.5 - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	# На листе лицевые стороны1–4 идут парами рядов,5–6 — в правых столбцах.
	var shown := mini(value, 6)
	var pair_column := round_index % 2 if round_index < 2 else 1 - round_index % 2
	var column := round_index if shown <= 4 else 4 + pair_column
	var row := (shown - 1) * 2 if shown <= 4 else (shown - 5) * 4 + (round_index / 2) * 2
	var region := Rect2(Vector2(1 + column * 58.5, 51 + row * 58.7), Vector2(58, 58))
	# Круглая геометрия отсекает белые углы листа без нового ассета.
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	for step in 64:
		var direction := Vector2.from_angle(TAU * step / 64.0)
		points.append(rect.get_center() + direction * radius)
		uv.append((region.get_center() + direction * region.size * 0.5) / SHEET.get_size())
	draw_polygon(points, PackedColorArray([Color.WHITE]), uv, SHEET)
	# Единое цифровое обозначение не выдаёт6 звёзд за номиналы7–10.
	draw_circle(size * 0.5, radius * 0.64, TGStyle.ROUND_COLORS[round_index])
	var font := TGStyle.FONT
	var text := str(value)
	var font_size := int(radius * 0.8)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, size * 0.5 + Vector2(-width * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("18130d"))
