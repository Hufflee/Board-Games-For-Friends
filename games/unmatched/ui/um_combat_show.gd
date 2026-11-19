extends Control
## Показ открытого боя. Урон, очередность и результат уже определены хостом.

signal cards_revealed

const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const Style := preload("res://games/unmatched/ui/um_style.gd")
const Match := preload("res://games/unmatched/logic/um_match.gd")
const CARD_RATIO := 1.389
const READ_SECONDS := 3.0

var _attack: TextureRect
var _defense: TextureRect
var _note: Label
var _shade: ColorRect
var _current := 0
var _last_seen := 0
var _reveal_finished := false
var _read_finished := false
var _impact_started := false
var _during_started := false
var _during_playing := false
var _during := {}
var _immediate := {}
var _last_immediate := 0
var _playing_immediate := false
var _view_id := 0
var _board_focus := false
var _compact := false
var _layout_tween: Tween
var _dock: Rect2
var _slots: Array[Rect2] = []
var _center_positions: Array[Vector2] = []
var _show_post_board := false
var _impact_done := false
var _printed: Array[Dictionary] = []
var _value_labels: Array[Label] = []
var _queue: Array[Dictionary] = []
var _outcomes := {}
var _burst := 0.0
var _burst_center := Vector2.ZERO
var _burst_color := Color.WHITE
var _card_size: Vector2


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 85
	_shade = ColorRect.new()
	_shade.color = Color(0.09, 0.06, 0.10, 0.58)
	_shade.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_attack = _card()
	_defense = _card()
	for card in [_attack, _defense]:
		var value := Label.new()
		value.mouse_filter = MOUSE_FILTER_IGNORE
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.add_theme_font_override("font", Style.body_font())
		value.add_theme_color_override("font_outline_color", Color("131719"))
		value.add_theme_constant_override("outline_size", 4)
		card.add_child(value)
		_value_labels.append(value)
	_note = Label.new()
	_note.mouse_filter = MOUSE_FILTER_IGNORE
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_override("font", Style.body_font())
	_note.add_theme_font_size_override("font_size", 22)
	_note.add_theme_color_override("font_color", Color("fff3df"))
	_note.add_theme_color_override("font_outline_color", Color("251a20"))
	_note.add_theme_constant_override("outline_size", 9)
	add_child(_note)
	hide()


func present(combat: Dictionary, outcome: Dictionary, from_attack: Rect2, from_defense: Rect2, dock: Rect2) -> void:
	var id := int(combat.get("id", 0))
	_view_id = id
	_board_focus = combat.get("board_focus", false)
	_dock = dock
	_slots = [from_attack, from_defense]
	_shade.offset_right = minf(0.0, dock.position.x - global_position.x - size.x)
	if id > _last_seen and (combat.get("attack", {}) as Dictionary).has("face"):
		_last_seen = id
		_queue.append({"id": id, "combat": combat, "from_attack": from_attack, "from_defense": from_defense})
	var result := int(outcome.get("id", 0))
	var immediate: Dictionary = combat.get("immediate", {})
	var new_defense: Dictionary = combat.get("defense", {})
	if id == _current and _reveal_finished and not _impact_started and new_defense.has("face") and new_defense != _printed[1]:
		_printed[1] = new_defense
		_defense.texture = Art.face(new_defense)
		_value_labels[1].hide()
	if id == _current and _reveal_finished and new_defense.is_empty():
		_printed[1] = {}
		_defense.hide()
		_value_labels[1].hide()
	if int(immediate.get("id", 0)) > _last_immediate:
		_last_immediate = immediate.id
		if not _immediate.has(id):
			_immediate[id] = []
		_immediate[id].append(immediate)
	if id >= _current and combat.has("during") and not (id == _current and _during_started):
		_during[id] = combat.during
	if result >= _current and result > 0 and not (result == _current and _impact_started):
		_outcomes[result] = outcome
	if not visible:
		_next()
	_advance()


func faces_visible(id: int) -> bool:
	return id < _current or (id == _current and _reveal_finished)


func _card() -> TextureRect:
	var face := TextureRect.new()
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Art.round_corners(face)
	add_child(face)
	return face


func _next() -> void:
	if _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	_current = next.id
	_reveal_finished = false
	_read_finished = false
	_impact_started = false
	_impact_done = false
	_show_post_board = false
	_compact = false
	_during_started = false
	_during_playing = false
	for value in _value_labels:
		value.hide()
	_note.hide()
	_shade.modulate.a = 0.0
	show()
	var combat: Dictionary = next.combat
	var defense: Dictionary = combat.get("defense", {})
	_printed = [combat.attack, defense]
	var gap := size.x * 0.039
	var left_space := maxf(180.0, _dock.position.x - global_position.x)
	var width := minf(minf((size.x * 0.60 - gap) * 0.5, size.y * 0.69 / CARD_RATIO), (left_space - gap - 32.0) * 0.5)
	_card_size = Vector2(width, width * CARD_RATIO)
	var left := Vector2((left_space - width * 2.0 - gap) * 0.5, TopBar.HEIGHT + 24.0)
	var right := left + Vector2(width + gap, 0.0)
	_center_positions = [left, right]
	_prepare(_attack, next.from_attack, left, Art.back(combat.attack_hero))
	_prepare(_defense, next.from_defense, right, Art.back(combat.defense_hero))
	_defense.visible = not defense.is_empty()
	var travel := create_tween().set_parallel(true)
	travel.tween_property(_shade, "modulate:a", 1.0, 0.26)
	for card: TextureRect in [_attack, _defense]:
		var target := left if card == _attack else right
		travel.tween_property(card, "position", target, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		travel.tween_property(card, "size", _card_size, 0.26)
		travel.tween_property(card, "modulate:a", 1.0, 0.26)
	await travel.finished
	for card: TextureRect in [_attack, _defense]:
		if card.visible:
			var printed: Dictionary = combat.attack if card == _attack else defense
			await _flip(card, Art.face(printed))
	_reveal_finished = true
	cards_revealed.emit()
	await get_tree().create_timer(READ_SECONDS).timeout
	_read_finished = true
	_advance()


func _prepare(card: TextureRect, source: Rect2, destination: Vector2, texture: Texture2D) -> void:
	card.show()
	card.texture = texture
	card.scale = Vector2.ONE
	card.rotation = 0.0
	card.position = destination if Prefs.reduce_motion else get_global_transform_with_canvas().affine_inverse() * source.position
	card.size = _card_size if Prefs.reduce_motion else source.size
	card.pivot_offset = _card_size * 0.5
	card.modulate.a = 0.0 if Prefs.reduce_motion else 1.0


func _flip(card: TextureRect, face: Texture2D) -> void:
	var property := "modulate:a" if Prefs.reduce_motion else "scale:x"
	var flip := create_tween()
	flip.tween_property(card, property, 0.0, 0.12)
	flip.tween_callback(func(): card.texture = face)
	flip.tween_property(card, property, 1.0, 0.14)
	await flip.finished


func _advance() -> void:
	if not visible or not _read_finished or _during_playing or _playing_immediate or _layout_tween:
		return
	if _impact_started and not _impact_done:
		return
	if _immediate.has(_current):
		_play_immediate()
		return
	var show_board := _board_focus and _view_id == _current
	if _compact != show_board:
		_move_for_board(show_board)
		return
	if show_board:
		return
	if _impact_done:
		if _view_id != _current:
			_fade_combat()
		return
	if _during.has(_current):
		_play_during()
	elif _outcomes.has(_current):
		_impact()


func _move_for_board(compact: bool) -> void:
	_compact = compact
	_note.hide()
	var transform_to_local := get_global_transform_with_canvas().affine_inverse()
	var duration := 0.01 if Prefs.reduce_motion else 0.24
	_layout_tween = create_tween().set_parallel(true)
	for side in 2:
		var card := _attack if side == 0 else _defense
		if _impact_done:
			card.rotation = 0.0
			card.modulate.a = 1.0
		var scale_factor := minf(_slots[side].size.x / _card_size.x, _slots[side].size.y / _card_size.y)
		var compact_center := transform_to_local * _slots[side].get_center()
		var position := compact_center - _card_size * 0.5 if compact else _center_positions[side]
		_layout_tween.tween_property(card, "position", position, duration)
		_layout_tween.tween_property(card, "scale", Vector2.ONE * (scale_factor if compact else 1.0), duration)
	_layout_tween.tween_property(_shade, "modulate:a", 0.0 if compact else 1.0, duration)
	await _layout_tween.finished
	_layout_tween = null
	_advance()


func _play_immediate() -> void:
	_playing_immediate = true
	var events: Array = _immediate[_current]
	_immediate.erase(_current)
	for event: Dictionary in events:
		await _pulse(event, Art.IMMEDIATE_BOUNDS)
	_note.hide()
	_playing_immediate = false
	_advance()


func _play_during() -> void:
	_during_started = true
	_during_playing = true
	var events: Array = _during[_current]
	_during.erase(_current)
	for event: Dictionary in events:
		await _pulse(event, Art.DURING_BOUNDS)
	await get_tree().create_timer(Match.BEFORE_IMPACT_SECONDS).timeout
	_note.hide()
	_during_playing = false
	_advance()


func _pulse(event: Dictionary, regions: Dictionary) -> void:
	var card := _attack if event.side == 0 else _defense
	var printed: Dictionary = _printed[event.side]
	if card.texture != null and not printed.is_empty():
		var bounds: Vector2 = regions.get(printed.definition, Vector2(0.69, 0.92))
		var shown := _face_rect(card)
		var highlight := Panel.new()
		highlight.mouse_filter = MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1.0, 0.76, 0.24, 0.23)
		style.border_color = Color("f4cd76")
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		highlight.add_theme_stylebox_override("panel", style)
		card.add_child(highlight)
		highlight.position = shown.position + Vector2(shown.size.x * 0.08, shown.size.y * bounds.x)
		highlight.size = Vector2(shown.size.x * 0.86, shown.size.y * (bounds.y - bounds.x))
		await get_tree().create_timer(0.30).timeout
		_show_values(event.get("values", []))
		_show_note(event.message)
		await get_tree().create_timer(Match.DURING_SECONDS - 0.30).timeout
		highlight.queue_free()


func _face_rect(card: TextureRect) -> Rect2:
	var dimensions := card.texture.get_size()
	var scale_to_fit := minf(card.size.x / dimensions.x, card.size.y / dimensions.y)
	var image_size := dimensions * scale_to_fit
	return Rect2((card.size - image_size) * 0.5, image_size)


func _show_values(values: Array) -> void:
	for side in mini(values.size(), _printed.size()):
		var printed: Dictionary = _printed[side]
		var value := _value_labels[side]
		if printed.is_empty() or values[side] == printed.value:
			value.hide()
			continue
		var card := _attack if side == 0 else _defense
		if card.texture == null:
			continue
		var shown := _face_rect(card)
		var pad := StyleBoxFlat.new()
		const COLORS := [Color("a61d16"), Color("15547b"), Color("4a376d")]
		pad.bg_color = COLORS[clampi(int(printed.kind), 0, COLORS.size() - 1)]
		pad.set_corner_radius_all(3)
		value.add_theme_stylebox_override("normal", pad)
		value.add_theme_color_override("font_color", Color("94ff9e") if values[side] > printed.value else Color("ff8a89"))
		value.add_theme_font_size_override("font_size", maxi(12, roundi(shown.size.y * 0.073)))
		value.text = str(values[side])
		value.position = shown.position + shown.size * Vector2(0.075, 0.130)
		value.size = shown.size * Vector2(0.098, 0.076)
		value.show()


func _impact() -> void:
	if not _outcomes.has(_current):
		return
	_impact_started = true
	var outcome: Dictionary = _outcomes[_current]
	_show_post_board = outcome.get("board_after", false)
	_outcomes.erase(_current)
	_show_values(outcome.get("values", []))
	var hit: bool = outcome.hit
	var original := _attack.position
	var strike := _defense.position - Vector2(_card_size.x * 0.45, 0.0)
	if not Prefs.reduce_motion:
		var charge := create_tween()
		charge.tween_property(_attack, "position", strike, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await charge.finished
	var broken := _defense if hit and _defense.visible else _attack
	var burst := create_tween().set_parallel(true)
	if not Prefs.reduce_motion:
		if not hit:
			burst.tween_property(_attack, "position", strike.lerp(original, 0.37), 0.27).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		burst.tween_property(broken, "rotation", 0.14 if hit else -0.09, 0.24)
		burst.tween_property(broken, "scale", Vector2.ONE * (0.79 if hit else 0.88), 0.24)
		_burst_center = broken.position + _card_size * 0.5
		_burst_color = Color("f4a683") if hit else Color("eee2dd")
		burst.tween_method(_draw_burst, 0.01, 1.0, 0.46)
	burst.tween_property(broken, "modulate:a", 0.0, 0.30)
	_show_losses(outcome.losses)
	await burst.finished
	await get_tree().create_timer(0.52).timeout
	if _show_post_board:
		_impact_done = true
		_note.hide()
		_advance()
	else:
		_fade_combat()


func _fade_combat() -> void:
	if not _impact_done and _show_post_board:
		return
	_impact_done = false
	var fade := create_tween().set_parallel(true)
	for item: Control in [_attack, _defense, _note, _shade]:
		fade.tween_property(item, "modulate:a", 0.0, 0.18)
	await fade.finished
	_burst = 0.0
	queue_redraw()
	hide()
	cards_revealed.emit()
	_next()


func _show_losses(losses: Array) -> void:
	var lines := PackedStringArray()
	for loss: Dictionary in losses:
		lines.append("%s  −%d ОЗ" % [loss.name, loss.amount])
	_show_note("Защита выдержала" if lines.is_empty() else "\n".join(lines))


func _show_note(message: String) -> void:
	_note.text = message
	_note.modulate.a = 1.0
	_note.position = Vector2(_center_positions[0].x, _center_positions[0].y + _card_size.y + 14.0)
	_note.size = Vector2(_center_positions[1].x + _card_size.x - _center_positions[0].x, 0.0)
	_note.show()


func _draw_burst(progress: float) -> void:
	_burst = progress
	queue_redraw()


func _draw() -> void:
	if _burst <= 0.0 or _burst >= 1.0:
		return
	for i in 14:
		var direction := Vector2.from_angle(i * TAU / 14.0)
		var point := _burst_center + direction * (48.0 + _burst * (65.0 + (i % 3) * 12.0))
		draw_line(point, point + direction * lerpf(16.0, 3.0, _burst),
			Color(_burst_color, (1.0 - _burst) * 0.85), 3.0, true)
