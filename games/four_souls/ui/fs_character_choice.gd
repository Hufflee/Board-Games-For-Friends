extends Control
## Две пары стартовых карт над столом. Выбор подтверждает хост.

signal chosen(card: int)

const CARD_SHADER := preload("res://games/four_souls/ui/fs_charge.gdshader")
var _offers: Array = []
var _pairs: Array[Button] = []
var _title: Label


func _ready() -> void:
	name = "CharacterChoice"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.07, 0.06, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title = FSStyle.label("", FSStyle.H1, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	resized.connect(_layout)


func sync(offers: Array, remaining: int) -> void:
	_title.text = "Выберите персонажа" if not offers.is_empty() else "Осталось выбрать: %d" % remaining
	if _offers != offers:
		_offers = offers.duplicate(true)
		var previous := _pairs.duplicate()
		_pairs.clear()
		for pair: Button in previous:
			pair.hide()
			pair.queue_free()
		for offer: Dictionary in _offers:
			_add_pair(offer)
	_layout()


func _add_pair(offer: Dictionary) -> void:
	var pair := Button.new()
	var character := int(offer.card)
	pair.set_meta("character", character)
	pair.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pair.tooltip_text = FSData.title(character)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		pair.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(pair)
	_pairs.append(pair)
	var face := PanelContainer.new()
	face.name = "Cards"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := FSStyle.box(Color("#30231f"), Color("#8f6655"))
	frame.set_content_margin_all(8)
	face.add_theme_stylebox_override("panel", frame)
	pair.add_child(face)
	var cards := FSStyle.hbox(8)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(cards)
	_add_card(cards, character)
	_add_card(cards, int(offer.item))
	pair.pressed.connect(func(): chosen.emit(character))
	pair.mouse_entered.connect(func(): _highlight(pair))
	pair.mouse_exited.connect(func(): _highlight(pair if pair.has_focus() else null))
	pair.focus_entered.connect(func(): _highlight(pair))
	pair.focus_exited.connect(func(): _highlight(pair if pair.get_global_rect().has_point(get_global_mouse_position()) else null))


func _add_card(parent: Control, id: int) -> void:
	if id >= 0:
		var card := TextureRect.new()
		card.texture = FSData.texture(id)
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ink := ShaderMaterial.new()
		ink.shader = CARD_SHADER
		ink.set_shader_parameter("gray", 0.0)
		card.material = ink
		parent.add_child(card)
	else:
		var label := FSStyle.label("Эдем выберет\nвечный предмет\nпосле раздачи", FSStyle.CAP)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(label)


func _layout() -> void:
	var card_width := clampf(minf((size.x - 136.0) / 4.0, (size.y - 146.0) / 1.37), 56.0, 192.0)
	var pair_size := Vector2(card_width * 2.0 + 24.0, card_width * 1.37 + 16.0)
	var gap := 32.0
	var center := size * 0.5
	_title.position = Vector2(0, center.y - pair_size.y * 0.5 - 64.0) if not _pairs.is_empty() else Vector2(0, center.y - 20.0)
	_title.size = Vector2(size.x, 40.0)
	for index in _pairs.size():
		var pair := _pairs[index]
		pair.size = pair_size
		pair.position = center - pair_size * 0.5 + Vector2((index - 0.5) * (pair_size.x + gap), 0)
		var face := pair.get_node("Cards") as Control
		face.size = pair_size
		face.pivot_offset = pair_size * 0.5


func _process(_delta: float) -> void:
	if not visible:
		return
	var time := Time.get_ticks_msec() / 1000.0
	for index in _pairs.size():
		var pair := _pairs[index]
		var face := pair.get_node("Cards") as Control
		face.position.y = sin(time * 2.0 + index * PI) * 3.0 - (face.scale.x - 1.0) * 120.0


func _highlight(selected: Button) -> void:
	for pair in _pairs:
		var face := pair.get_node("Cards") as PanelContainer
		var previous: Tween = pair.get_meta("hover_tween") if pair.has_meta("hover_tween") else null
		if previous != null:
			previous.kill()
		var active := pair == selected
		pair.z_index = int(active)
		var frame := face.get_theme_stylebox("panel") as StyleBoxFlat
		var tween := pair.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pair.set_meta("hover_tween", tween)
		tween.tween_property(face, "scale", Vector2.ONE * (1.065 if active else 1.0), 0.18)
		tween.tween_property(frame, "border_color", Color("#f5c477") if active else Color("#8f6655"), 0.18)
		tween.tween_property(face, "modulate", Color("#ded2ca") if selected != null and not active else Color.WHITE, 0.18)
		for card: Control in face.get_child(0).get_children():
			if card.material is ShaderMaterial:
				var ink := card.material as ShaderMaterial
				tween.tween_method(
					func(value: float): ink.set_shader_parameter("gray", value),
					float(ink.get_shader_parameter("gray")),
					0.48 if selected != null and not active else 0.0,
					0.18
				)
