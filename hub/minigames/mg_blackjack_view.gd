extends VBoxContainer
## «Блэкджек» в окне «Общение»: дилер сверху, ваши карты крупно, остальные игроки списком, внизу ставка
## и действия. Наведение на любую руку — крупный просмотр её карт рядом. Снимок стола приходит от хоста
## (hub/minigames/mg_net.gd, правила — logic/mg_blackjack.gd); окно лишь шлёт действия room_act("blackjack", …).
## Кнопки и подписи — в стиле окна «Общение» (panel: _action, _label, px, цвета c_*).

const Blackjack := preload("res://hub/minigames/logic/mg_blackjack.gd")

var mg: Node
var panel: Node  # hub/comms_panel.gd — общие кнопки, подписи и масштаб
var id := ""
var _bet := 1
var _zoom: Control


class Hand:
	extends Control
	## Ряд карт (числа 0..51, -1 — закрытая), рисуется кодом: светлая карта, номинал и масть.
	var cards: Array = []
	var card_w := 30.0

	func _init(list: Array, width: float) -> void:
		cards = list
		card_w = width
		var h := width * 1.4
		var step := width * 0.62
		custom_minimum_size = Vector2(width + step * maxi(0, cards.size() - 1), h)

	func _draw() -> void:
		var h := card_w * 1.4
		var step := card_w * 0.62
		for i in cards.size():
			var r := Rect2(Vector2(i * step, 0), Vector2(card_w, h))
			var card: int = int(cards[i])
			var box := StyleBoxFlat.new()
			box.set_corner_radius_all(int(card_w * 0.12))
			box.shadow_color = Color(0, 0, 0, 0.35)
			box.shadow_size = 2
			box.shadow_offset = Vector2(0, 1)
			if card < 0:
				box.bg_color = Color("2b4a7a")
				box.border_color = Color("c9d6ee")
				box.set_border_width_all(maxi(1, int(card_w / 18.0)))
				draw_style_box(box, r)
				draw_rect(r.grow(-card_w * 0.18), Color(1, 1, 1, 0.12), false, 1.0)
				continue
			box.bg_color = Color("f7f2e7")
			box.border_color = Color("8c8578")
			box.set_border_width_all(1)
			draw_style_box(box, r)
			var red := card / 13 in [1, 2]
			var ink := Color("b3262c") if red else Color("1d1d24")
			var font := ThemeDB.fallback_font
			var rank: String = Blackjack.RANKS[card % 13]
			var suit: String = Blackjack.SUITS[card / 13]
			draw_string(font, r.position + Vector2(card_w * 0.1, card_w * 0.36), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, int(card_w * 0.34), ink)
			var big := int(card_w * 0.55)
			var sw := font.get_string_size(suit, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
			draw_string(font, r.position + Vector2((card_w - sw) * 0.5, h * 0.72), suit, HORIZONTAL_ALIGNMENT_LEFT, -1, big, ink)


func _ready() -> void:
	add_theme_constant_override("separation", _px(6))
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _px(n: float) -> int:
	return int(panel.px(n)) if panel != null else int(n)


func _state() -> Dictionary:
	if mg == null or not mg.sessions.has(id):
		return {}
	return mg.sessions[id].state


func _label(text: String, size: int, color: Color) -> Label:
	var l: Label = panel._label(text, size, color)
	return l


func _act(action: Dictionary) -> void:
	mg.room_act("blackjack", action)


## Перерисовать окно по свежему снимку (вызывает окно «Общение» при каждом изменении комнаты).
func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_close_zoom()
	var state := _state()
	var list: Array = state.get("list", [])
	if list.is_empty():
		add_child(_label("Садимся за стол…", 13, panel.c_muted))
		return
	var me: int = mg.my_peer()
	var mine: Dictionary = {}
	for row: Dictionary in list:
		if int(row.peer) == me:
			mine = row
	var phase := str(state.get("phase", "bet"))
	# дилер
	var dealer_row := HBoxContainer.new()
	dealer_row.add_theme_constant_override("separation", _px(8))
	add_child(dealer_row)
	var dealer_cards: Array = state.get("dealer", [])
	var dv := int(state.get("dealer_value", 0))
	dealer_row.add_child(_label("Дилер" + (" · %d" % dv if not dealer_cards.is_empty() else ""), 14, panel.c_ink))
	if not dealer_cards.is_empty():
		dealer_row.add_child(_zoomable(dealer_cards, 26.0, "Дилер · %d" % dv))
	add_child(_label(str(state.get("last", "")), 12, panel.c_muted))
	# мои карты крупно
	if not mine.is_empty():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", _px(2))
		add_child(box)
		var head := "Вы · фишек: %d" % int(mine.chips)
		if int(mine.bet) > 0:
			head += " · ставка %d" % int(mine.bet)
		box.add_child(_label(head, 14, panel.c_ink))
		var hand: Array = mine.get("hand", [])
		if not hand.is_empty():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", _px(8))
			box.add_child(row)
			row.add_child(_zoomable(hand, 40.0, "Ваши карты · %d" % int(mine.value)))
			row.add_child(_label("%d" % int(mine.value), 20, panel.c_ink))
		if str(mine.result) != "":
			var delta := int(mine.delta)
			var sign := "+" if delta > 0 else ""
			var color: Color = Color("6fd28b") if delta > 0 else (Color("ff7a6e") if delta < 0 else panel.c_muted)
			box.add_child(_label("%s · %s%d %s" % [mine.result, sign, delta, _chips_word(absi(delta))], 14, color))
	# остальные игроки
	var others := list.filter(func(r: Dictionary) -> bool: return int(r.peer) != me)
	if not others.is_empty():
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(scroll)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", _px(4))
		scroll.add_child(col)
		for row: Dictionary in others:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", _px(6))
			col.add_child(line)
			var nick := _label("%s · %d" % [str(row.name).left(12), int(row.chips)], 12, Net.color_of(int(row.color)).lightened(0.35))
			nick.custom_minimum_size.x = _px(96)
			nick.clip_text = true
			line.add_child(nick)
			var cards: Array = row.get("hand", [])
			if not cards.is_empty():
				line.add_child(_zoomable(cards, 20.0, "%s · %d" % [row.name, int(row.value)]))
			line.add_child(_label(_status_text(row), 12, panel.c_muted))
	else:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(spacer)
	_controls(mine, phase)


func _chips_word(n: int) -> String:
	if n % 10 == 1 and n % 100 != 11:
		return "фишка"
	if n % 10 in [2, 3, 4] and not n % 100 in [12, 13, 14]:
		return "фишки"
	return "фишек"


func _status_text(row: Dictionary) -> String:
	match str(row.status):
		"bet":
			return "ставит…"
		"ready":
			return "ставка %d" % int(row.bet)
		"play":
			return "%d · думает" % int(row.value)
		"stand":
			return "%d · хватит" % int(row.value)
		"bust":
			return "%d · перебор" % int(row.value)
		"blackjack":
			return "блэкджек!"
		"done":
			return "%s %+d" % [row.result, int(row.delta)]
		"wait":
			return "ждёт раздачи"
		"broke":
			return "без фишек"
	return ""


## Ставка и действия — компактно в одну-две строки.
func _controls(mine: Dictionary, phase: String) -> void:
	if mine.is_empty():
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", _px(6))
	row.add_theme_constant_override("v_separation", _px(6))
	add_child(row)
	var status := str(mine.status)
	if int(mine.chips) <= 0 and status in ["broke", "done", "bet"] and phase != "play":
		var again: Button = panel._action("Начать заново?", "Снова сесть за стол с одной фишкой", true)
		again.pressed.connect(func() -> void: _act({"restart": true}))
		row.add_child(again)
		return
	match status:
		"bet":
			_bet = clampi(_bet, 1, int(mine.chips))
			var minus: Button = panel._action("−", "Меньше")
			minus.disabled = _bet <= 1
			minus.pressed.connect(func() -> void:
				_bet = maxi(1, _bet - 1)
				refresh())
			row.add_child(minus)
			row.add_child(_label("%d" % _bet, 16, panel.c_ink))
			var plus: Button = panel._action("+", "Больше")
			plus.disabled = _bet >= int(mine.chips)
			plus.pressed.connect(func() -> void:
				_bet = mini(int(mine.chips), _bet + 1)
				refresh())
			row.add_child(plus)
			var go: Button = panel._action("Поставить %d" % _bet, "Ставка на эту раздачу", true)
			go.pressed.connect(func() -> void: _act({"bet": _bet}))
			row.add_child(go)
		"ready":
			row.add_child(_label("Ставка сделана — ждём остальных", 12, panel.c_muted))
		"play":
			var hit: Button = panel._action("Ещё", "Взять карту", true)
			hit.pressed.connect(func() -> void: _act({"hit": true}))
			row.add_child(hit)
			var stand: Button = panel._action("Хватит", "Больше не брать")
			stand.pressed.connect(func() -> void: _act({"stand": true}))
			row.add_child(stand)
			if (mine.hand as Array).size() == 2 and int(mine.chips) >= int(mine.bet) * 2:
				var dbl: Button = panel._action("Удвоить", "Удвоить ставку и взять ровно одну карту")
				dbl.pressed.connect(func() -> void: _act({"double": true}))
				row.add_child(dbl)
		"wait":
			row.add_child(_label("Вы сядете со следующей раздачи", 12, panel.c_muted))
		_:
			if phase == "done":
				var next: Button = panel._action("Новая раздача", "Сыграть ещё раз", true)
				next.pressed.connect(func() -> void: _act({"next": true}))
				row.add_child(next)
			elif phase == "dealer":
				row.add_child(_label("Дилер добирает карты…", 12, panel.c_muted))


## Рука, которая при наведении показывает свои карты крупно рядом.
func _zoomable(cards: Array, width: float, caption: String) -> Control:
	var hand := Hand.new(cards, float(_px(width)))
	hand.mouse_filter = Control.MOUSE_FILTER_STOP
	hand.mouse_default_cursor_shape = Control.CURSOR_HELP
	hand.mouse_entered.connect(_show_zoom.bind(hand, cards, caption))
	hand.mouse_exited.connect(_close_zoom)
	return hand


func _show_zoom(anchor: Control, cards: Array, caption: String) -> void:
	_close_zoom()
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", panel.flat(Color(0.08, 0.08, 0.12, 0.96), _px(10), _px(10)))
	box.z_as_relative = false
	box.z_index = 120
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	col.add_child(_label(caption, 14, Color.WHITE))
	var big := Hand.new(cards, float(_px(78)))
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(big)
	# окно «Общение» живёт в своём слое поверх экрана — просмотр кладём в тот же слой, поверх окна
	box.top_level = true
	panel.add_child(box)
	var at := anchor.get_global_rect()
	var size_guess := box.get_combined_minimum_size()
	var screen := get_viewport().get_visible_rect().size
	var x := clampf(at.position.x, 8.0, screen.x - size_guess.x - 8.0)
	var y := at.position.y - size_guess.y - 8.0
	if y < 8.0:
		y = at.end.y + 8.0
	box.global_position = Vector2(x, y)
	_zoom = box


func _close_zoom() -> void:
	if is_instance_valid(_zoom):
		_zoom.queue_free()
	_zoom = null


func _exit_tree() -> void:
	_close_zoom()
