class_name K12CardView
extends PanelContainer
## Карта: портрет, название, текст эффекта. В компактном виде — только портрет и название.

signal pressed(card: String)

var card := ""
var compact := false
var selected := false:
	set(v):
		selected = v
		_restyle()
var clickable := false:
	set(v):
		clickable = v
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW
var stamp := "":  # надпись поверх карты, например «ОТМЕНЕНА»
	set(v):
		stamp = v
		if _stamp_label:
			_stamp_label.text = v
			_stamp_label.visible = v != ""

var _hover := false
var _stamp_label: Label


func _init(card_id: String = "", is_compact: bool = false) -> void:
	card = card_id
	compact = is_compact


func _ready() -> void:
	custom_minimum_size = Vector2(80, 112) if compact else Vector2(138, 228)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hover = true; _restyle())
	mouse_exited.connect(func(): _hover = false; _restyle())
	var v := K12UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var head := K12UI.hbox(4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var title := K12UI.label(K12Cards.card_name(card), 13 if compact else 16, K12UI.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	head.add_child(title)
	if K12Cards.is_physical(card):
		var gem := K12UI.label("◆", 12 if compact else 15, K12UI.CRYSTAL_DARK)
		gem.tooltip_text = "Меняет грань кубика"
		head.add_child(gem)
	var pic := TextureRect.new()
	pic.texture = K12UI.art(card)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(0, 70 if compact else 88)
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	if not compact:
		var text := K12UI.label(K12Cards.card_text(card), 11, K12UI.INK)  # текст на самой карте — её «типографика», не UI
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(text)
	tooltip_text = "%s\n%s" % [K12Cards.card_name(card), K12Cards.card_text(card)]
	_stamp_label = K12UI.label(stamp, 13 if compact else 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_stamp_label.add_theme_stylebox_override("normal", K12UI.box(Color(K12UI.RED, 0.9), 4))
	_stamp_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_stamp_label.visible = stamp != ""
	_stamp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_stamp_label)
	_restyle()


func _restyle() -> void:
	var border := K12UI.GOLD if selected else (Color("c9a35a") if _hover and clickable else Color("8a6b45"))
	var sb := K12UI.box(K12UI.CREAM, 10, border, 4 if selected else 2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	if selected:
		sb.shadow_color = Color(K12UI.GOLD, 0.6)
		sb.shadow_size = 10
	add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(card)
		accept_event()
