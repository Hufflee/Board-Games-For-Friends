class_name TurnClock
extends PanelContainer
## Часы хода: «⏱ 23 с», пока идёт ход с ограничением времени (настройка комнаты «Время на ход»).
## По истечении хост делает ход за задумавшегося игрока. Здесь же — строка настройки для лобби.

const OPTIONS := [0, 30, 60, 90, 120]
## Фазы, в которых тикают часы хода.
const PHASES := ["roll", "select", "sorcerer", "oracle", "pick_under", "bid", "card", "clue", "guess", "side", "pick", "cue1", "cue2", "guess1", "guess2", "vip", "theme", "answer", "order", "give", "respond"]

var _label: Label
var _deadline := 0
var _total := 0
var _last := -1
var _paused := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	add_theme_stylebox_override("panel", sb)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_label)
	visible = false
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state(Net.view)


func _on_state(v: Dictionary) -> void:
	_total = int(v.get("turn_total", 0))
	var on: bool = _total > 0 and (v.get("clock", false) or v.get("phase", "") in PHASES)  # clock — игра сама говорит, что часы идут
	visible = on
	_paused = bool(v.get("game_paused", false))
	if on:
		_deadline = Time.get_ticks_msec() + int(v.get("turn_left", 0)) * 1000


func _process(_delta: float) -> void:
	if not visible:
		return
	if _paused:
		_label.text = "⏸ пауза"
		_label.add_theme_color_override("font_color", Color.WHITE)
		return
	var left := maxi(0, int(ceil((_deadline - Time.get_ticks_msec()) / 1000.0)))
	_label.text = "⏱ %d с" % left
	if left != _last:
		_last = left
		Sfx.countdown(left)
	_label.add_theme_color_override("font_color", Color("ff8a7a") if left <= 10 else Color.WHITE)


## Часы в центре сверху родителя.
static func top_center(offset_y: float = 4.0) -> TurnClock:
	var c := TurnClock.new()
	c.set_anchors_preset(Control.PRESET_CENTER_TOP)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.offset_top = offset_y
	return c


## Часы справа сверху (под кнопками «Правила / Настройки / Выйти») — для столов, где в центре сверху сидит игрок.
static func top_right(offset_y: float = 70.0, offset_x: float = 16.0) -> TurnClock:
	var c := TurnClock.new()
	c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.offset_top = offset_y
	c.offset_right = -offset_x
	return c


## Строка настройки «Время на ход» для лобби. make_button(text, size) -> Button, make_label(text, size) -> Label.
static func settings_row(make_button: Callable, make_label: Callable) -> Control:
	var cur := int(Net.lobby_view.get("settings", {}).get("turn_time", 60))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if not Net.is_host():
		row.add_child(make_label.call("Время на ход: %s" % ("без ограничения" if cur <= 0 else "%d с" % cur), 15))
		return row
	row.add_child(make_label.call("Время на ход:", 15))
	for t in OPTIONS:
		var b: Button = make_button.call("∞" if t == 0 else "%d с" % t, 14)
		UISel.pick(b, cur == t)
		b.tooltip_text = "Без ограничения" if t == 0 else "Не успел — ход сделает программа"
		var tt: int = t
		b.pressed.connect(func(): Net.set_setting("turn_time", tt))
		row.add_child(b)
	return row
