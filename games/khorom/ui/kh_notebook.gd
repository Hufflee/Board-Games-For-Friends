extends Control
## «Хором!»: блокнот игрока на 6 строк. Свой — с полями ввода и кнопками «глазик» / «✓» («✕»);
## чужой — строки под пластинками (как в Word Slam), открытая строка — пластинка падает.
## Засчитанный ответ — полупрозрачная зелёная пластинка, снятый в «Белой вороне» — красная.
const Style := preload("res://games/khorom/ui/kh_style.gd")
const SIZE := Vector2(440, 440)
const TOP := 56.0
const ROW_H := 60.0
const PAD := 16.0
const BUTTONS := 84.0

signal write_row(row: int, text: String)
signal reveal_row(row: int)
signal mark_row(row: int)

var seat := -1
var mine := false
var kind := "chorus"
var topics: Array = []
var fall_layer: Control
var _title: Label
var _status: Label
var _edits: Array = []
var _texts: Array = []
var _topic_labels: Array = []
var _plates: Array = []
var _verdicts: Array = []
var _eyes: Array = []
var _marks: Array = []
var _timers: Array = []
var _similar: Array = []
var _active := false
var _falling: Array = []

func setup(owner_seat: int, is_mine: bool, round_kind: String, round_topics: Array) -> void:
	seat = owner_seat
	mine = is_mine
	kind = round_kind
	topics = round_topics.duplicate()
	name = "Notebook%d" % seat
	size = SIZE
	pivot_offset = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_PASS
	_title = Style.label("", 16)
	_title.add_theme_font_override("font", Style.weighted(Style.FONT, 800))
	_title.position = Vector2(PAD, 14)
	_title.size = Vector2(SIZE.x - PAD * 2 - 120, 24)
	_title.clip_text = true
	add_child(_title)
	_status = Style.label("", 12, Style.muted())
	_status.position = Vector2(SIZE.x - PAD - 120, 18)
	_status.size = Vector2(120, 20)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_status)
	for row: int in 6:
		var area := _answer_rect(row)
		var number := Style.label(str(row + 1), 12, Style.muted())
		number.position = Vector2(PAD, area.position.y + area.size.y - 22)
		add_child(number)
		var topic_label := Style.label(str(topics[row]) if kind == "blitz" and row < topics.size() else "", 12, Style.muted())
		topic_label.position = area.position + Vector2(4, 2)
		topic_label.size = Vector2(area.size.x, 16)
		topic_label.clip_text = true
		add_child(topic_label)
		_topic_labels.append(topic_label)
		var text_box := Rect2(area.position + Vector2(0, 18 if kind == "blitz" else 8), Vector2(area.size.x, area.size.y - (18 if kind == "blitz" else 8)))
		var text := Style.label("", 16)
		text.name = "Text%d" % row
		text.position = text_box.position + Vector2(4, 0)
		text.size = text_box.size - Vector2(4, 0)
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.clip_text = true
		add_child(text)
		_texts.append(text)
		var edit: LineEdit = null
		if mine:
			edit = LineEdit.new()
			edit.name = "Edit%d" % row
			edit.position = text_box.position
			edit.size = text_box.size
			edit.max_length = 40
			edit.placeholder_text = "ответ %d" % (row + 1)
			edit.add_theme_font_size_override("font_size", 16)
			var timer := Timer.new()
			timer.one_shot = true
			timer.wait_time = 0.35
			timer.timeout.connect(func(): write_row.emit(row, edit.text))
			add_child(timer)
			_timers.append(timer)
			edit.text_changed.connect(func(_t: String): timer.start())
			edit.text_submitted.connect(func(t: String):
				timer.stop()
				write_row.emit(row, t)
				if row + 1 < _edits.size() and is_instance_valid(_edits[row + 1]):
					_edits[row + 1].grab_focus())
			add_child(edit)
		_edits.append(edit)
		_plates.append(null)
		_verdicts.append(null)
		_similar.append(false)
		var eye := _icon_button("eye")
		eye.name = "Eye%d" % row
		eye.tooltip_text = "Показать ответ всем"
		eye.position = Vector2(SIZE.x - PAD - BUTTONS, area.position.y + (area.size.y - 34) * 0.5)
		eye.pressed.connect(func(): reveal_row.emit(row))
		add_child(eye)
		_eyes.append(eye)
		var mark := _icon_button("cross" if kind == "crow" else "check")
		mark.name = "Mark%d" % row
		mark.tooltip_text = "Совпало с чьим-то — снять очко" if kind == "crow" else "Совпало — получить очко"
		mark.position = Vector2(SIZE.x - PAD - 38, eye.position.y)
		mark.pressed.connect(func(): mark_row.emit(row))
		add_child(mark)
		_marks.append(mark)

func _answer_rect(row: int) -> Rect2:
	var x := PAD + 22.0
	return Rect2(Vector2(x, TOP + row * ROW_H + 4), Vector2(SIZE.x - x - PAD - BUTTONS - 8, ROW_H - 10))

## Обновить блокнот по виду хоста. info: title, status, editable, active, plates (закрывать чужие строки).
func apply(book: Dictionary, info: Dictionary) -> void:
	_title.text = str(info.get("title", ""))
	_status.text = str(info.get("status", ""))
	_active = bool(info.get("active", false))
	var editable := bool(info.get("editable", false))
	var plates := bool(info.get("plates", true))
	var rows: Array = book.get("rows", [])
	for row: int in mini(6, rows.size()):
		var data: Dictionary = rows[row]
		var text := str(data.get("text", ""))
		var open := bool(data.get("open", false))
		var edit: LineEdit = _edits[row]
		if edit != null:
			edit.visible = editable
			edit.editable = editable
			if not edit.has_focus() and edit.text != text and _timers[row].is_stopped():
				edit.text = text
		_texts[row].visible = edit == null or not editable
		_texts[row].text = text
		_similar[row] = bool(data.get("similar", false))
		# Пластинка: чужая заполненная и ещё не открытая строка.
		var covered := plates and not mine and bool(data.get("filled", false)) and not open
		if covered and _plates[row] == null:
			_plates[row] = _make_plate(row, Color("5d5865") if Style.dark() else Color("bdb7ad"), true)
		elif not covered and _plates[row] != null:
			_drop_plate(_plates[row])
			_plates[row] = null
		# Итог строки: зелёная (засчитано) или красная (снято) полупрозрачная пластинка.
		var verdict := open and bool(data.get("marked", false))
		if verdict and _verdicts[row] == null:
			_verdicts[row] = _make_plate(row, Color(Style.BAD if kind == "crow" else Style.GOOD, 0.38), false, 3.0)
			_verdicts[row].name = "Verdict%d" % row
			_verdicts[row].modulate.a = 0.7  # на 30% прозрачнее: и заливка, и обводка
		elif not verdict and _verdicts[row] != null:
			_verdicts[row].queue_free()
			_verdicts[row] = null
		_eyes[row].visible = mine and bool(data.get("eye", false))
		var can_mark := mine and open and not text.is_empty() and bool(info.get("marking", false))
		_marks[row].visible = can_mark
		_marks[row].set_meta("on", bool(data.get("marked", false)))
		_marks[row].queue_redraw()
	queue_redraw()

## grow — насколько пластинка шире строки: итог (зелёная/красная) ложится ровно на синюю рамку похожего ответа (grow 3).
func _make_plate(row: int, color: Color, striped: bool, grow: float = 0.0) -> Control:
	var area := _answer_rect(row).grow(grow)
	var plate := Control.new()
	plate.name = "Plate%d" % row
	plate.position = area.position
	plate.size = area.size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.draw.connect(func():
		var r := Rect2(Vector2.ZERO, plate.size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(10)
		sb.border_color = Color(color.darkened(0.3), 0.7 if striped else 0.9)
		sb.set_border_width_all(2)
		if striped:
			sb.shadow_color = Color(0, 0, 0, 0.14)
			sb.shadow_size = 3
		plate.draw_style_box(sb, r)
		if striped:
			# Штриховка «обратной стороны» — строго внутри пластинки.
			var h := r.size.y - 4.0
			for i: int in range(-int(h / 10.0) - 1, int(r.size.x / 10.0) + 1):
				var x := i * 10.0
				var from_x := maxf(x, 6.0)
				var to_x := minf(x + h, r.size.x - 6.0)
				if to_x > from_x:
					plate.draw_line(Vector2(from_x, 2.0 + h - (from_x - x)), Vector2(to_x, 2.0 + h - (to_x - x)), Color(1, 1, 1, 0.14), 2.0, true)
	)
	add_child(plate)
	return plate

## Пластинка спрыгивает и падает вниз (как в Word Slam); ответ под ней уже открыт.
func _drop_plate(plate: Control) -> void:
	if not is_instance_valid(plate):
		return
	if fall_layer == null or not is_inside_tree() or not is_visible_in_tree():
		plate.queue_free()
		return
	var at := plate.global_position
	var scale_now := get_global_transform().get_scale()
	remove_child(plate)
	fall_layer.add_child(plate)
	plate.global_position = at
	plate.scale = scale_now
	plate.pivot_offset = plate.size * 0.5
	_falling.append({"node": plate, "vel": Vector2(randf_range(-160, 160), randf_range(-520, -380)), "spin": randf_range(-7.0, 7.0)})
	Sfx.play("card_shove", -6)

func _process(delta: float) -> void:
	for f: Dictionary in _falling.duplicate():
		var plate: Control = f.node
		if not is_instance_valid(plate):
			_falling.erase(f)
			continue
		f.vel += Vector2(0, 2200.0) * delta
		plate.position += f.vel * delta
		plate.rotation += f.spin * delta
		if plate.position.y > fall_layer.size.y + 80.0:
			plate.queue_free()
			_falling.erase(f)

func _exit_tree() -> void:
	for f: Dictionary in _falling:
		if is_instance_valid(f.node):
			f.node.queue_free()
	_falling.clear()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	var sb := Style.box(Style.paper(), 16, 14)
	if _active:
		sb.border_color = Style.ACCENT
		sb.set_border_width_all(3)
	draw_style_box(sb, r)
	draw_line(Vector2(PAD, TOP - 6), Vector2(SIZE.x - PAD, TOP - 6), Color(Style.ink(), 0.15), 2.0)
	for row: int in 6:
		var area := _answer_rect(row)
		var y := area.position.y + area.size.y
		# блокнот уменьшен до дробного масштаба (~0,75): тонкая линия попадала между пикселями и пропадала
		# на части строк — толщина с запасом и сглаживание, чтобы на экране всегда был хотя бы пиксель
		draw_line(Vector2(PAD, y), Vector2(SIZE.x - PAD, y), Style.rule_line(), 1.5, true)
		if _similar[row]:
			var glow := StyleBoxFlat.new()
			glow.bg_color = Color(Style.MATCH, 0.12)
			glow.border_color = Style.MATCH
			glow.set_border_width_all(2)
			glow.set_corner_radius_all(10)
			draw_style_box(glow, area.grow(3))

func _icon_button(icon: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(34, 34)
	b.size = Vector2(34, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.draw.connect(func():
		var c := b.size * 0.5
		var on: bool = b.get_meta("on", false)
		var color := Style.ink()
		if icon == "check":
			color = Style.GOOD if on else Style.ink()
		elif icon == "cross":
			color = Style.BAD if on else Style.ink()
		if on:
			b.draw_circle(c, 15, Color(color, 0.22))
		if icon == "eye":
			b.draw_arc(c + Vector2(0, 4), 10, PI * 1.16, PI * 1.84, 20, color, 1.5, true)
			b.draw_arc(c + Vector2(0, -4), 10, PI * 0.16, PI * 0.84, 20, color, 1.5, true)
			b.draw_circle(c, 3, color)
		elif icon == "check":
			b.draw_polyline(PackedVector2Array([c + Vector2(-7, 0), c + Vector2(-2, 6), c + Vector2(8, -6)]), color, 2.5, true)
		else:
			b.draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), color, 2.5, true)
			b.draw_line(c + Vector2(6, -6), c + Vector2(-6, 6), color, 2.5, true)
	)
	return b
