extends Control

const TextUI = preload("res://hub/ui_text.gd")
## Рука Cheat Poker, просмотр по наведению, перетаскивание и открытые заявки.

const Cards := preload("res://games/poker/logic/pk_cheat_cards.gd")
const Style := preload("res://games/poker/ui/pk_style.gd")
const ART_PATHS := {
	0: "res://games/poker/art/cheat/long_fingers_face.png",
	1: "res://games/poker/art/cheat/under_table.png",
	2: "res://games/poker/art/cheat/blind_swap.png",
	3: "res://games/poker/art/cheat/hypnosis.png",
	4: "res://games/poker/art/cheat/marked_back.png",
	5: "res://games/poker/art/cheat/dealer_mirror.png",
	6: "res://games/poker/art/cheat/forecast.png",
	7: "res://games/poker/art/cheat/substitution.png",
	9: "res://games/poker/art/cheat/ten_exchange.png",
	10: "res://games/poker/art/cheat/table_swap.png",
	11: "res://games/poker/art/cheat/spotlight.png",
	12: "res://games/poker/art/cheat/open_bluff.png",
	13: "res://games/poker/art/cheat/blind_draw.png",
	14: "res://games/poker/art/cheat/fresh_deck.png",
	15: "res://games/poker/art/cheat/shift_two.png",
	16: "res://games/poker/art/cheat/royal_guests.png",
	18: "res://games/poker/art/cheat/red_or_black.png",
	19: "res://games/poker/art/cheat/secret_display.png",
	20: "res://games/poker/art/cheat/lit_exchange.png",
	21: "res://games/poker/art/cheat/public_reveal.png",
	22: "res://games/poker/art/cheat/card_on_table.png",
	23: "res://games/poker/art/cheat/wanted_rank.png",
	24: "res://games/poker/art/cheat/black_door.png",
	25: "res://games/poker/art/cheat/red_door.png",
	27: "res://games/poker/art/cheat/loud_fold.png",
	28: "res://games/poker/art/cheat/portrait_gallery.png",
	29: "res://games/poker/art/cheat/gapped_straight.png",
	30: "res://games/poker/art/cheat/one_color.png",
}
const TITLE_FONT := preload("res://games/brodilka/art/fonts/Oswald-Variable.ttf")
const BODY_FONT := preload("res://games/king_of_12/art/fonts/AlegreyaSans-Bold.ttf")
const CORNERS := preload("res://hub/card_corners.gdshader")
const BACK := preload("res://games/poker/art/card_back.png")
const MINI := Vector2(120, 180)
const LARGE := Vector2(272, 408)
const TARGET_SIZE := Vector2(368, 176)
const HOVER_MS := 500
const CARD_PLUM := Color("281126")
const CARD_OUTLINE := Color("df9aff")
const CARD_GLOW := Color("b65eff74")
const TITLE_GLOW := Color("ef7c427f")
const CARD_GOLD := Color("ffd48a")
const CARD_INK := Color("fff4e6")

var _title_font := Style.weighted(TITLE_FONT, 650)
var _center := Vector2.ZERO
var _view: Dictionary = {}
var _state_key: Array = []
var _hand: Control
var _hand_cards: Array[Control] = []
var _hand_center := Vector2.ZERO
var _hand_step := 0.0
var _hand_motion: Tween
var _stage: Control
var _preview: Control
var _drag: Control
var _zone: PanelContainer
var _target: PanelContainer
var _hovered := -1
var _hover_started_ms := 0
var _pressed := -1
var _press_pos := Vector2.ZERO


## Сохраняет размеры карты при более длинном переводе.
class CardText extends Label:
	var max_font_size := 16
	var min_font_size := 10

	func _ready() -> void:
		_fit_text()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
			_fit_text.call_deferred()

	func _fit_text() -> void:
		var font := get_theme_font("font")
		var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		var localized := tr(text)
		var font_size := max_font_size
		while font_size > min_font_size:
			var extent := font.get_multiline_string_size(localized, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, -1, flags)
			if extent.y <= size.y - 2.0:
				break
			font_size -= 1
		add_theme_font_size_override("font_size", font_size)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	_stage = _layer()
	_stage.z_index = 16
	_hand = _layer()
	_preview = _layer()
	_preview.z_index = 20
	_drag = _layer()
	_drag.z_index = 21
	visible = false


func _layer() -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func sync(view: Dictionary, center: Vector2, viewport_size: Vector2, hand_right: float) -> void:
	visible = view.has("cheat")
	if not visible:
		return
	var data: Dictionary = view.cheat
	var first_reveal: bool = view.phase == "cheat_reveal" and _view.get("phase") != "cheat_reveal"
	var key := [view.session_no, view.hand_no, view.phase, view.street, view.get("game_paused", false), data, viewport_size, hand_right]
	_view = view
	_center = center
	size = viewport_size
	if key == _state_key:
		return
	_state_key = key
	_clear_input()
	Style.clear(_stage)
	if _hand_motion != null:
		_hand_motion.kill()
	_hand_cards.clear()
	Style.clear(_hand)
	_zone = null
	_target = null
	if view.phase == "cheat_pick":
		_build_pick(data)
	elif view.mode == "cheat_experimental" and view.phase == "hand" and not view.get("game_paused", false):
		_build_pick(data)
		if is_instance_valid(_zone):
			_zone.hide()
	elif view.phase == "cheat_reveal":
		_build_reveal(data.revealed, first_reveal)
	if not data.peeks.is_empty():
		var notes := Style.button("Подсмотренное · %d" % data.peeks.size(), 12)
		notes.position = Vector2(16, size.y - MINI.y * 0.7 - 76)
		notes.pressed.connect(_show_notes)
		_hand.add_child(notes)
	if int(view.you) >= 0:
		_build_hand(data.hand, hand_right)


func _build_hand(ids: Array, hand_right: float) -> void:
	_hand_step = PrivateHand.fan_step(MINI.x, hand_right - 24.0, ids.size())
	var span := MINI.x + _hand_step * maxi(0, ids.size() - 1)
	_hand_center = Vector2(16.0 + span * 0.5, size.y - MINI.y * 0.2 - 2.0)
	var caption := Style.section("Жульнические карты · %d" % ids.size())
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.position = Vector2(16, size.y - MINI.y * 0.7 - 54)
	caption.size.x = span
	_hand.add_child(caption)
	for index: int in ids.size():
		var id: int = ids[index]
		var tile := _face(id, MINI, false)
		tile.name = "CheatCard%d" % id
		tile.pivot_offset = MINI * 0.5
		tile.set_meta("cheat_id", id)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.mouse_default_cursor_shape = Control.CURSOR_DRAG if _view.cheat.options.has(id) else Control.CURSOR_POINTING_HAND
		tile.mouse_entered.connect(func(): _start_hover(id))
		tile.mouse_exited.connect(func():
			if _hovered == id:
				_start_hover(-1))
		tile.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if _view.cheat.options.has(id) and not is_instance_valid(_target):
					_pressed = id
					_press_pos = get_global_transform_with_canvas().affine_inverse() * (tile.get_global_transform_with_canvas() * event.position)
					_start_hover(-1)
					tile.accept_event())
		_hand.add_child(tile)
		_hand_cards.append(tile)
	_layout_hand(false)


func _layout_hand(animate: bool) -> void:
	if _hand_motion != null:
		_hand_motion.kill()
	if _hand_cards.is_empty():
		return
	if animate:
		_hand_motion = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for index: int in _hand_cards.size():
		var tile := _hand_cards[index]
		var offset := float(index) - float(_hand_cards.size() - 1) * 0.5
		var highlighted: bool = int(tile.get_meta("cheat_id")) == _hovered and _pressed < 0
		var position_on_fan := _hand_center + PrivateHand.fan_offset(offset, _hand_step, MINI.y, highlighted) - tile.pivot_offset
		var tilt := 0.0 if highlighted else PrivateHand.fan_angle(offset)
		var zoom := Vector2.ONE * (1.08 if highlighted else 1.0)
		tile.z_index = 12 if highlighted else index
		if animate:
			_hand_motion.tween_property(tile, "position", position_on_fan, 0.12)
			_hand_motion.tween_property(tile, "rotation", tilt, 0.12)
			_hand_motion.tween_property(tile, "scale", zoom, 0.12)
		else:
			tile.position = position_on_fan
			tile.rotation = tilt
			tile.scale = zoom
	_sync_hand_order.call_deferred()


func _sync_hand_order() -> void:
	if _hand_cards.is_empty():
		return
	var first := _hand.get_child_count() - _hand_cards.size()
	var highlighted: Control
	for index: int in _hand_cards.size():
		var tile := _hand_cards[index]
		_hand.move_child(tile, first + index)
		if int(tile.get_meta("cheat_id")) == _hovered:
			highlighted = tile
	if highlighted != null:
		_hand.move_child(highlighted, _hand.get_child_count() - 1)


func _build_pick(data: Dictionary) -> void:
	if data.options.is_empty() and int(data.played) < 0:
		return
	_zone = PanelContainer.new()
	_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone.add_theme_stylebox_override("panel", Style.box(Color("286d4dbb"), 16, 16, Style.GOOD))
	_zone.size = Vector2(256, 142)
	_zone.position = _center - _zone.size * 0.5
	_stage.add_child(_zone)
	var caption := Style.label("Карта выбрана" if int(data.played) >= 0 else "Перетащите карту сюда", 16)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone.add_child(caption)
	if int(data.played) >= 0:
		var back := _back(MINI)
		back.position = _center - MINI * 0.5
		_stage.add_child(back)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _build_reveal(entries: Array, animate: bool) -> void:
	var width := minf(96.0, (size.x - 256.0) / maxf(1.0, entries.size()) - 8.0)
	var span := entries.size() * (width + 8.0) - 8.0
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		var col := Style.column(4)
		col.position = Vector2(_center.x - span * 0.5 + index * (width + 8.0), _center.y - 104)
		col.custom_minimum_size.x = width
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(col)
		var player := Style.label(str(_view.players[entry.seat].name), 12, Style.ink())
		player.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player.custom_minimum_size.x = width
		player.clip_text = true
		TextUI.full_on_hover(player)
		col.add_child(player)
		var face := _face(int(entry.id), Vector2(width, width * 1.5), false)
		col.add_child(face)
		if animate:
			var back := _back(Vector2(width, width * 1.5))
			face.add_child(back)
			for part: Control in face.get_children():
				if part != back:
					part.modulate.a = 0.0
			face.pivot_offset.x = width * 0.5
			var flip := face.create_tween()
			flip.tween_property(face, "scale:x", 0.04, 0.18).set_delay(index * 0.08)
			flip.tween_callback(func():
				back.queue_free()
				for part: Control in face.get_children():
					if part != back:
						part.modulate.a = 1.0)
			flip.tween_property(face, "scale:x", 1.0, 0.18)
		var status := ""
		var color := Style.muted()
		match str(entry.status):
			"cancelled":
				status = "× Совпадение"
				color = Style.BAD
				face.modulate.a = 0.52
			"applied":
				status = "✓ Сработала"
				color = Style.GOOD
			"unavailable":
				status = "Без эффекта"
			_:
				status = "В очереди"
		col.add_child(Style.label(status, 12, color))
		face.mouse_filter = Control.MOUSE_FILTER_STOP
		face.mouse_entered.connect(func(): _start_hover(int(entry.id)))
		face.mouse_exited.connect(func(): _start_hover(-1))


func _start_hover(id: int) -> void:
	_hovered = id
	_hover_started_ms = Time.get_ticks_msec()
	Style.clear(_preview)
	_layout_hand(true)


func _process(_delta: float) -> void:
	if not visible:
		return
	if _pressed < 0 and _hovered >= 0 and _preview.get_child_count() == 0 and not is_instance_valid(_target):
		if Time.get_ticks_msec() - _hover_started_ms >= HOVER_MS:
			var face := _face(_hovered, LARGE, true)
			_preview.add_child(face)
			_preview.position = _center - face.size * 0.5
			face.resized.connect(func(): _preview.position = _center - face.size * 0.5)


func _input(event: InputEvent) -> void:
	if _pressed < 0:
		return
	if event is InputEventMouseMotion:
		var mouse: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if _drag.get_child_count() == 0 and mouse.distance_to(_press_pos) > 8.0:
			_drag.add_child(_face(_pressed, MINI * 1.35, false))
		if is_instance_valid(_zone) and _drag.get_child_count() > 0:
			_zone.show()
		_drag.position = mouse - MINI * 0.675
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
		return
	var mouse: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	var id := _pressed
	var dropped := _drag.get_child_count() > 0 and is_instance_valid(_zone) and _zone.get_rect().has_point(mouse)
	_clear_input()
	if dropped and _view.cheat.options.has(id):
		_choose_target(id)
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _pressed >= 0:
		_clear_input()


func _choose_target(id: int) -> void:
	var options: Array = _view.cheat.options[id]
	if options.size() == 1 and str(options[0].label).is_empty():
		_send(id, options[0].args)
		return
	_target = PanelContainer.new()
	_target.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 16, 16, Style.GOOD))
	_target.custom_minimum_size = TARGET_SIZE
	_target.position = _center - TARGET_SIZE * 0.5
	add_child(_target)
	var col := Style.column(8)
	_target.add_child(col)
	col.add_child(Style.heading(Cards.title(id), 16))
	var choice := OptionButton.new()
	choice.clip_text = true
	TextUI.full_on_hover(choice)
	choice.get_popup().max_size.y = 352
	choice.custom_minimum_size.x = TARGET_SIZE.x - 32
	for option: Dictionary in options:
		choice.add_item(option.label)
	choice.selected = 0
	col.add_child(choice)
	var buttons := Style.row(8)
	col.add_child(buttons)
	var send := Style.button("Разыграть", 16)
	send.theme_type_variation = "SelectedButton"
	send.pressed.connect(func(): _send(id, options[choice.selected].args))
	buttons.add_child(send)
	var back := Style.button("Назад", 16)
	back.pressed.connect(_close_target)
	buttons.add_child(back)


func _send(id: int, args: Array) -> void:
	var window: int = _view.cheat.window
	_close_target()
	Net.send_action("cheat_play", {"id": id, "args": args, "window": window})


func _close_target() -> void:
	if is_instance_valid(_target):
		remove_child(_target)
		_target.queue_free()
		_target = null


func _clear_input() -> void:
	if is_instance_valid(_zone) and _view.get("mode") == "cheat_experimental":
		_zone.hide()
	_pressed = -1
	_start_hover(-1)
	Style.clear(_drag)
	_close_target()


func _show_notes() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Видно только вам"
	dialog.dialog_text = "\n".join(_view.cheat.peeks)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(396, 160))


## Лицо карты: одна иллюстрированная поверхность и два переводимых слоя текста.
func _face(id: int, dimensions: Vector2, full: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = dimensions
	card.size = dimensions
	var radius := roundi(dimensions.x * 0.045)
	var box := Style.box(CARD_PLUM, 0, radius)
	box.set_border_width_all(0)
	box.shadow_color = CARD_GLOW
	box.shadow_size = 10 if full else 5
	box.shadow_offset = Vector2.ZERO
	card.add_theme_stylebox_override("panel", box)
	var face := Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(face)

	if ART_PATHS.has(id):
		var art := TextureRect.new()
		art.name = "CardIllustration"
		art.texture = load(ART_PATHS[id]) as Texture2D
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mask := ShaderMaterial.new()
		mask.shader = CORNERS
		art.material = mask
		face.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_card_text(face, "CardTitle", Cards.title(id), _title_font, CARD_GOLD, dimensions, 0.035, 0.22, 34 if full else 17)
	_card_text(face, "CardEffect", Cards.description(id), BODY_FONT, CARD_INK, dimensions, 0.69, 0.985, 20 if full else 10)
	# Контур поверх рисунка, чтобы край читался и на лицевой стороне, и в веере.
	var outline := Panel.new()
	outline.name = "CardOutline"
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.border_color = CARD_OUTLINE
	edge.set_border_width_all(3 if full else 2)
	edge.set_corner_radius_all(radius)
	outline.add_theme_stylebox_override("panel", edge)
	face.add_child(outline)
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return card


func _card_text(face: Control, node_name: String, value: String, font: Font, ink: Color,
		dimensions: Vector2, top: float, bottom: float, font_size: int) -> void:
	var label := CardText.new()
	label.name = node_name
	label.text = value
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	TextUI.full_on_hover(label)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.max_font_size = font_size
	label.min_font_size = maxi(6, roundi(font_size * 0.67))
	label.add_theme_color_override("font_color", ink)
	if node_name == "CardTitle":
		label.add_theme_color_override("font_shadow_color", TITLE_GLOW)
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 0)
		label.add_theme_constant_override("shadow_outline_size", 4 if font_size > 20 else 2)
	label.add_theme_constant_override("line_spacing", 0)
	label.position = Vector2(dimensions.x * 0.07, dimensions.y * top)
	label.size = Vector2(dimensions.x * 0.86, dimensions.y * (bottom - top))
	face.add_child(label)


func _back(dimensions: Vector2) -> TextureRect:
	var card := TextureRect.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.texture = BACK
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.size = dimensions
	return card
