extends RefCounted
## Four Souls: наглядные индикаторы стола (06.11).
## Всплывающие +N/−N, вспышка сработавшей карты, покачивание готовых к ответу карт,
## значки «цель атаки» и «покупка». Только показ — правила и сеть не трогает.
## Использует fs_table.gd: FX.float_text(layer, anchor, ...), FX.flash(layer, node), FX.wiggle(card), FX.badge(card, kind).

const GOOD := Color(0.35, 0.95, 0.45)
const BAD := Color(1.0, 0.38, 0.32)
const GLOW := Color(1.0, 0.82, 0.3)


## Число над элементом: плывёт вверх и тает (зелёное — прибавка, красное — убыль).
static func float_text(layer: Control, anchor: Control, amount: int, suffix: String = "", lane: int = 0) -> void:
	if amount == 0 or not is_instance_valid(layer) or not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
		return
	var label := Label.new()
	label.text = ("+%d" % amount if amount > 0 else "−%d" % absi(amount)) + suffix
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", GOOD if amount > 0 else BAD)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	var rect := anchor.get_global_rect()
	var origin := rect.position + Vector2(rect.size.x * 0.5 - 18, rect.size.y * 0.25 + lane * 24) - layer.get_global_rect().position
	label.position = origin
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", origin.y - 56, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


## Произвольная надпись («СМЕРТЬ», «+1 душа»): тот же подъём и таяние, свой цвет.
static func float_label(layer: Control, anchor: Control, text: String, color: Color, lane: int = 0, font_size: int = 22) -> void:
	if not is_instance_valid(layer) or not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	var rect := anchor.get_global_rect()
	var origin := rect.position + Vector2(8, rect.size.y * 0.2 + lane * 24) - layer.get_global_rect().position
	label.position = origin
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", origin.y - 60, 1.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 1.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


## Сработавшая карта: золотое свечение поверх неё, мягко гаснет.
static func flash(layer: Control, node: Control, tint: Color = GLOW) -> void:
	if not is_instance_valid(layer) or not is_instance_valid(node) or not node.is_visible_in_tree():
		return
	var glow := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint, 0.22)
	box.border_color = tint
	box.set_border_width_all(3)
	box.set_corner_radius_all(10)
	box.shadow_color = Color(tint, 0.75)
	box.shadow_size = 16
	glow.add_theme_stylebox_override("panel", box)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(glow)
	var rect := node.get_global_rect()
	glow.position = rect.position - layer.get_global_rect().position
	glow.size = rect.size
	glow.pivot_offset = rect.size * 0.5
	var tween := glow.create_tween()
	tween.tween_property(glow, "scale", Vector2(1.06, 1.06), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(glow, "scale", Vector2.ONE, 0.2)
	tween.tween_property(glow, "modulate:a", 0.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(glow.queue_free)


## Карту можно разыграть прямо сейчас: подсветка и нетерпеливое покачивание лица карты.
static func wiggle(card: Control) -> void:
	if not is_instance_valid(card):
		return
	var face: Control = card.get("_face")
	if face == null:
		return
	# 06.11: светящаяся окантовка точно по контуру нарисованной карты (не за её пределами).
	var glow := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = GLOW
	box.set_border_width_all(4)
	box.set_corner_radius_all(8)
	box.anti_aliasing = true
	glow.add_theme_stylebox_override("panel", box)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drawn := Rect2(Vector2.ZERO, face.size)
	var texture: Texture2D = face.get("texture") if "texture" in face else null
	if texture != null and texture.get_size().x > 0 and texture.get_size().y > 0 and face.size.x > 0:
		var fit := minf(face.size.x / texture.get_size().x, face.size.y / texture.get_size().y)
		var dims := texture.get_size() * fit
		drawn = Rect2((face.size - dims) * 0.5, dims)
	glow.position = drawn.position
	glow.size = drawn.size
	face.add_child(glow)
	face.pivot_offset = face.size * 0.5
	# 07.11: плавный подскок с покачиванием вместо мелкой дрожи. Фаза общая по часам: пересборка стола
	# не начинает движение заново, а при наведении/перетаскивании карта стоит ровно.
	var tween := face.create_tween().set_loops()
	var period := 0.0
	for step in [[-2.5, -9.0, 0.22], [2.5, -6.0, 0.24], [0.0, 0.0, 0.26]]:
		tween.tween_property(face, "rotation_degrees", step[0], step[2]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.parallel().tween_property(face, "position:y", step[1], step[2]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		period += float(step[2])
	tween.tween_interval(1.1)
	period += 1.1
	tween.custom_step(fmod(Time.get_ticks_msec() / 1000.0, period))
	var still := func(stop: bool) -> void:
		if not is_instance_valid(face):
			return
		if stop:
			tween.pause()
			face.rotation_degrees = 0.0
			face.position.y = 0.0
		else:
			tween.play()
	if card.has_signal("hovered"):
		card.hovered.connect(func(_c, on): still.call(on))
	if card.has_signal("drag_started"):
		card.drag_started.connect(func(_c): still.call(true))
	if card.has_signal("dropped"):
		card.dropped.connect(func(_c, _at): still.call(false))
	var pulse := glow.create_tween().set_loops()
	pulse.tween_property(glow, "modulate:a", 0.45, 0.6)
	pulse.tween_property(glow, "modulate:a", 1.0, 0.6)


## Значок на карте: "target" — мишень атакуемого монстра, "buy" — идёт покупка.
static func badge(card: Control, kind: String) -> void:
	if not is_instance_valid(card):
		return
	var mark := Marker.new()
	mark.kind = kind
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(mark)
	var tween := mark.create_tween().set_loops()
	tween.tween_property(mark, "modulate:a", 0.55, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mark, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


class Marker extends Control:
	var kind := "target"

	func _draw() -> void:
		var c := size * 0.5
		if kind == "dead":
			var red := Color(1.0, 0.22, 0.2)
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.0, 0.0, 0.35))
			var m := minf(size.x, size.y) * 0.22
			draw_line(Vector2(m, m + 26), size - Vector2(m, m), red, 5.0, true)
			draw_line(Vector2(size.x - m, m + 26), Vector2(m, size.y - m), red, 5.0, true)
			_caption("УМИРАЕТ", red)
		elif kind == "target":
			var red := Color(1.0, 0.25, 0.22)
			var r := minf(size.x, size.y) * 0.3
			draw_arc(c, r, 0, TAU, 40, red, 3.0, true)
			draw_arc(c, r * 0.55, 0, TAU, 32, red, 2.5, true)
			draw_circle(c, 3.5, red)
			for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + dir * r * 0.7, c + dir * r * 1.3, red, 3.0, true)
			_caption("ЦЕЛЬ", red)
		else:
			var gold := Color(1.0, 0.82, 0.3)
			var r := minf(size.x, size.y) * 0.17
			var coin := Vector2(size.x - r - 6, r + 30)
			draw_circle(coin, r, Color(gold, 0.95))
			draw_arc(coin, r, 0, TAU, 32, Color(0.35, 0.25, 0.05), 2.0, true)
			var font := get_theme_default_font()
			draw_string(font, coin + Vector2(-r * 0.45, r * 0.42), "¢", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 1.3), Color(0.3, 0.2, 0.04))
			draw_rect(Rect2(Vector2.ZERO, size), gold, false, 3.0)
			_caption("ПОКУПКА", gold)

	func _caption(text: String, color: Color) -> void:
		var font := get_theme_default_font()
		var fs := 14
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(Vector2((size.x - width) * 0.5 - 6, 4), Vector2(width + 12, 20))
		draw_rect(box, Color(0.06, 0.04, 0.04, 0.82))
		draw_string(font, box.position + Vector2(6, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Разыгранная карта: крупно в центре экрана, затем летит и ложится на стопку сброса.
## from_rect пустой — карта появляется в центре; to_rect пустой — гаснет на месте (активация предмета).
static func fly_card(layer: Control, texture: Texture2D, from_rect: Rect2, to_rect: Rect2, hold: float = 1.4) -> void:  # 07.11: вдвое дольше в центре
	if not is_instance_valid(layer) or texture == null:
		return
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var corners := ShaderMaterial.new()
	corners.shader = preload("res://hub/card_corners.gdshader")
	image.material = corners
	layer.add_child(image)
	var origin := layer.get_global_rect().position
	var big := Vector2(220, 300)
	var center := Rect2(layer.size * 0.5 - big * 0.5, big)
	var tween := image.create_tween()
	if from_rect.size == Vector2.ZERO:
		image.position = center.position + big * 0.1
		image.size = big * 0.8
		image.modulate.a = 0.0
		tween.set_parallel(true)
		tween.tween_property(image, "position", center.position, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(image, "size", big, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(image, "modulate:a", 1.0, 0.12)
		tween.set_parallel(false)
		tween.tween_interval(hold)
	else:
		image.position = from_rect.position - origin
		image.size = from_rect.size
	if to_rect.size == Vector2.ZERO:
		tween.tween_property(image, "modulate:a", 0.0, 0.35)
	else:
		tween.set_parallel(true)
		tween.tween_property(image, "position", to_rect.position - origin, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(image, "size", to_rect.size, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.set_parallel(false)
	tween.tween_callback(image.queue_free)
