class_name TurnNameGlow
extends Control
## Общая подсветка ника того, кто ходит: ник «светится» — сам текст светлеет и получает голубое
## свечение вокруг букв, а позади — мягкая синяя дымка, к краям переходящая в цвет ника.
## Одинаково во всех играх. Выключение возвращает ник к прежнему цвету.
## Использование: TurnNameGlow.apply(label, active) — при каждом обновлении списка игроков.

const BLUE := Color("4aa3ff")
const TEXT_LIGHT := Color("e3f1ff")  # к нему светлеет текст ника на тёмном фоне
const TEXT_DARK := Color("1859c9")  # к нему уходит тёмный ник на светлом фоне
## Свои переопределения темы, которые подсветка меняет (на выключении — возвращаем как было).
const COLOR_KEYS := ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_shadow_color", "font_outline_color"]
const CONST_KEYS := ["shadow_offset_x", "shadow_offset_y", "shadow_outline_size", "outline_size"]
const PAD := Vector2(16, 6)  # насколько ореол выходит за первую/последнюю букву и сверху/снизу

var _tex: GradientTexture2D
var _ink := Color.WHITE


## Включить/выключить ореол у надписи с ником. Повторные вызовы дёшевы.
static func apply(label: Control, active: bool) -> void:
	if label == null:
		return
	var glow: TurnNameGlow = label.get_node_or_null("TurnNameGlow")
	if not active:
		if glow:
			glow.hide()
		_restore(label)
		return
	if glow == null:
		glow = TurnNameGlow.new()
		glow.name = "TurnNameGlow"
		label.add_child(glow)
	_save(label)
	var ink: Color = label.get_meta("tng_ink")
	_light_text(label, ink)
	glow.set_ink(ink)
	glow.show()
	glow.queue_redraw()  # текст ника мог смениться


## Запомнить свои переопределения ника (один раз, пока подсветка включена) и его цвет.
static func _save(label: Control) -> void:
	if label.has_meta("tng_saved"):
		return
	var saved := {}
	for key: String in COLOR_KEYS:
		saved["c:" + key] = label.get_theme_color(key) if label.has_theme_color_override(key) else null
	for key: String in CONST_KEYS:
		saved["k:" + key] = label.get_theme_constant(key) if label.has_theme_constant_override(key) else null
	if "clip_text" in label:
		saved["clip_text"] = label.get("clip_text")
		saved["overrun"] = label.get("text_overrun_behavior")
	label.set_meta("tng_saved", saved)
	label.set_meta("tng_ink", label.get_theme_color("font_color") if label is Label or label is Button else Color.WHITE)


static func _restore(label: Control) -> void:
	if not label.has_meta("tng_saved"):
		return
	var saved: Dictionary = label.get_meta("tng_saved")
	for key: String in COLOR_KEYS:
		if saved["c:" + key] == null:
			label.remove_theme_color_override(key)
		else:
			label.add_theme_color_override(key, saved["c:" + key])
	for key: String in CONST_KEYS:
		if saved["k:" + key] == null:
			label.remove_theme_constant_override(key)
		else:
			label.add_theme_constant_override(key, saved["k:" + key])
	if saved.has("clip_text"):
		label.set("clip_text", saved["clip_text"])
		label.set("text_overrun_behavior", saved["overrun"])
	label.remove_meta("tng_saved")
	label.remove_meta("tng_ink")


## Сам текст «светится»: светлее (с оттенком цвета ника) и с голубым свечением вокруг букв.
## У Label — размытая тень без сдвига, у кнопки-ника (PlayerTag) — полупрозрачная обводка.
static func _light_text(label: Control, ink: Color) -> void:
	# обрезка текста режет и дымку левее первой буквы: пока ник светится, длинный ник
	# не обрезается, а сокращается многоточием (в те же границы)
	if "clip_text" in label and bool(label.get("clip_text")):
		label.set("clip_text", false)
		if int(label.get("text_overrun_behavior")) == TextServer.OVERRUN_NO_TRIMMING:
			label.set("text_overrun_behavior", TextServer.OVERRUN_TRIM_ELLIPSIS)
	# светлый ник (тёмный фон) — светлеет; тёмный ник (светлый фон) — уходит в насыщенный синий,
	# иначе светлый текст на светлой панели теряется
	var lit := Color(ink, 1.0).lerp(TEXT_LIGHT, 0.6) if ink.get_luminance() >= 0.5 else Color(ink, 1.0).lerp(TEXT_DARK, 0.7)
	if label is Label:
		label.add_theme_color_override("font_color", lit)
		label.add_theme_color_override("font_shadow_color", Color(BLUE, 0.55))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 0)
		label.add_theme_constant_override("shadow_outline_size", 6)
	elif label is Button:
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			label.add_theme_color_override(key, lit)
		label.add_theme_color_override("font_outline_color", Color(BLUE, 0.45))
		label.add_theme_constant_override("outline_size", 5)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex = GradientTexture2D.new()
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(1.0, 0.5)
	# круг: левая половина — левый край дымки, правая — правый, середина тянется под текстом
	_tex.width = 64
	_tex.height = 64
	set_ink(Color.WHITE)


func set_ink(ink: Color) -> void:
	if ink.is_equal_approx(_ink) and _tex.gradient != null:
		return
	_ink = ink
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(BLUE, 0.62),
		Color(BLUE.lerp(Color(ink, 1.0), 0.45), 0.28),
		Color(ink, 0.0),
	])
	_tex.gradient = g
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var label := get_parent() as Label
	if label and not label.text.is_empty():
		# ореол — вокруг самого текста, а не всей ширины ячейки
		var font := label.get_theme_font("font")
		var fs := label.get_theme_font_size("font_size")
		var w := minf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, size.x)
		var x := 0.0
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			x = (size.x - w) * 0.5
		elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			x = size.x - w
		rect = Rect2(Vector2(x, 0), Vector2(w, size.y))
	var button := get_parent() as Button
	if button and not button.text.is_empty():
		# ник-кнопка (PlayerTag): ореол — только вокруг текста, кружок цвета слева не закрываем
		var font := button.get_theme_font("font")
		var fs := button.get_theme_font_size("font_size")
		var w := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := button.get_theme_stylebox("normal")
		var x := box.get_margin(SIDE_LEFT) if box else 0.0
		if button.icon:
			x += button.icon.get_width() + button.get_theme_constant("h_separation")
		if button.alignment == HORIZONTAL_ALIGNMENT_CENTER:
			x = (size.x - w) * 0.5
		w = minf(w, size.x - x)
		rect = Rect2(Vector2(x, 0), Vector2(w, size.y))
	_draw_stadium(rect)


## Дымка «таблеткой»: под всем текстом — полная сила (не тает к краям длинного ника),
## слева от первой и справа от последней буквы — круглые затухающие края шириной PAD.x.
func _draw_stadium(text_rect: Rect2) -> void:
	var top := text_rect.position.y - PAD.y
	var h := text_rect.size.y + PAD.y * 2.0
	var cap := PAD.x  # половина круга: центр ровно у края текста, к концу — тает
	var half := _tex.width * 0.5
	var x0 := text_rect.position.x
	var x1 := text_rect.end.x
	draw_texture_rect_region(_tex, Rect2(x0 - cap, top, cap, h), Rect2(0, 0, half, _tex.height))
	draw_texture_rect_region(_tex, Rect2(x0, top, maxf(0.0, x1 - x0), h), Rect2(half - 0.5, 0, 1, _tex.height))
	draw_texture_rect_region(_tex, Rect2(x1, top, cap, h), Rect2(half, 0, half, _tex.height))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
