extends Control
## Стол «Перудо»: стаканы игроков по кругу, свои кости, ставка в центре, панель ставки,
## вскрытие с подсчётом. Состояние — из Net.view, действия — Net.send_action.

var app: Node

const NAMES_GEN := {1: "единиц", 2: "двоек", 3: "троек", 4: "четвёрок", 5: "пятёрок", 6: "шестёрок"}

var _v := {}
var _me := 0
var _n := 0

var _bg: K12Tavern
var _seats_layer: Control
var _table_layer: Control
var _ui: Control
var _overlay: Control
var _fx: Control

var _plates: Array = []
var _cups: Array = []
var _rows: Array = []  # место -> HBoxContainer с костями (вскрытие / свои)
var _my_dice: HBoxContainer
var _bid_box: PanelContainer
var _history: Label
var _banner: Label
var _panel: PanelContainer
var _qty := 1
var _face := 2
var _maputo := false
var _top: TopBar
var _next_btn_row: HBoxContainer
var _auto_label: Label
var _auto_deadline := 0

var _revealing := false
var _queued := {}
var _revealed_round := -1
var _reveal_tween: Tween
var _shaken_seen: Array = []
var _roll_label: Label  # «Трясите стаканы!» → «Отпускайте!» через секунду тряски
var _celebrated := false
var _scattering_me := false  # свои кости ещё летят по столу — ряд показываем после
var _bubbles := {}
var _log_panel: PanelContainer
var _log_text: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = K12Tavern.new(true)
	_bg.pirate = true  # стол — карта сокровищ, по краю канат
	add_child(_bg)
	add_child(PerudoPirateDecor.new())
	for nm in ["_seats_layer", "_table_layer", "_ui", "_overlay", "_fx"]:
		var l := Control.new()
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		set(nm, l)

	_top = TopBar.make(self, "Перудо", func(t, z): return K12UI.button(t, z), null, K12UI.CREAM, K12UI.font("bold"))
	var buttons := _top.actions
	var log_btn := K12UI.button("Журнал", K12UI.CAP)
	log_btn.tooltip_text = "Кто что ставил и нажимал"
	log_btn.pressed.connect(func():
		_log_panel.visible = not _log_panel.visible
		_update_log())
	buttons.add_child(log_btn)
	var rules := K12UI.button("Правила", K12UI.CAP)
	rules.pressed.connect(func(): app.show_rules())
	buttons.add_child(rules)
	var settings := K12UI.button("Настройки", K12UI.CAP)
	settings.pressed.connect(func(): app.show_settings())
	buttons.add_child(settings)
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = K12UI.button("Завершить партию", K12UI.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся к выбору игры, пати сохранится.", Net.return_to_party)
	elif Net.is_party():
		leave = K12UI.button("Покинуть пати", K12UI.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave = K12UI.button("Выйти", K12UI.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	buttons.add_child(leave)

	# текущая ставка и история
	_bid_box = K12UI.panel(Color(0.06, 0.12, 0.09, 0.9), 8, "small")
	_ui.add_child(_bid_box)
	# история ставок лежит прямо на пергаменте стола — тёмные «чернила» со светлой обводкой
	_history = K12UI.label("", K12UI.CAP, Color("3a2410"), HORIZONTAL_ALIGNMENT_CENTER)
	_history.add_theme_font_override("font", K12UI.font("bold"))
	_history.add_theme_color_override("font_outline_color", Color(0.96, 0.9, 0.76, 0.85))
	_history.add_theme_constant_override("outline_size", 4)
	_history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui.add_child(_history)
	_banner = K12UI.label("", K12UI.BODY, K12UI.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(_banner)

	_my_dice = K12UI.hbox(8)
	_table_layer.add_child(_my_dice)
	_panel = K12UI.panel(Color(0.08, 0.055, 0.035, 0.94), 8, "ornate")
	_ui.add_child(_panel)

	# журнал действий — по кнопке «Журнал», справа сверху под кнопками
	_log_panel = K12UI.panel(Color(0.07, 0.05, 0.035, 0.94), 10, "small")
	_log_panel.visible = false
	_log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_log_panel.offset_left = -330
	_log_panel.offset_right = -10
	_log_panel.offset_top = 48 + 4
	_log_panel.offset_bottom = 300
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.custom_minimum_size = Vector2(300, 230)
	_log_text.add_theme_font_size_override("normal_font_size", 13)
	_log_text.add_theme_font_size_override("bold_font_size", 13)
	_log_text.add_theme_color_override("default_color", K12UI.CREAM)
	_log_panel.add_child(_log_text)
	_ui.add_child(_log_panel)

	resized.connect(_layout)
	Net.state_changed.connect(_on_state)
	Net.chat_received.connect(_on_chat_bubble)
	if not Net.view.is_empty():
		_on_state.call_deferred(Net.view)


# --- Геометрия -------------------------------------------------------------------

func _cx() -> float:
	return size.x / 2.0 if size.x > 0 else 640.0


func _tc() -> Vector2:
	return Vector2(_cx(), K12Tavern.TABLE_Y)


## Угол места за столом: по порядку рассадки (order), «я» — всегда внизу.
func _angle(seat: int) -> float:
	var order: Array = _v.get("order", [])
	var p := order.find(seat) if order.size() == _n else seat
	var me := order.find(_me) if order.size() == _n else _me
	return deg_to_rad(90.0 + ((p - me + _n) % _n) * 360.0 / _n)


func _cup_pos(seat: int) -> Vector2:
	var a := _angle(seat)
	var r := _bg.felt_radii() * 0.7
	var p := _tc() + Vector2(cos(a) * r.x, sin(a) * r.y)
	if seat == _me:
		p.x -= 150
	return p


func _plate_rect(seat: int) -> Rect2:
	if seat == _me:
		return Rect2(10, size.y - 128, 230, 118)
	var sz := Vector2(200, 84)
	var a := _angle(seat)
	var c := _tc() + Vector2(cos(a) * K12Tavern.TABLE_RADII.x, sin(a) * K12Tavern.TABLE_RADII.y)
	var r := Rect2(c - sz / 2.0, sz)
	r.position.x = clampf(r.position.x, 8, size.x - sz.x - 8)
	r.position.y = clampf(r.position.y, TopBar.HEIGHT + 4, size.y - sz.y - 170)
	return r


func _layout() -> void:
	if _n == 0:
		return
	for s in _n:
		var r := _plate_rect(s)
		_plates[s].position = r.position
		_plates[s].size = r.size
		var cup: PerudoCup = _cups[s]
		cup.position = _cup_pos(s) - Vector2(cup.size.x / 2.0, cup.size.y - 6) + (Vector2(0, -cup.size.y * 0.9) if cup.lifted else Vector2.ZERO)
		var row: HBoxContainer = _rows[s]
		row.reset_size()
		row.position = _cup_pos(s) + Vector2(-row.size.x / 2.0, 6)
	_my_dice.reset_size()
	_my_dice.position = Vector2(_cx() - 40, _cup_pos(_me).y - 52)
	_bid_box.reset_size()
	_bid_box.position = _tc() + Vector2(-_bid_box.size.x / 2.0, -125)
	_history.size = Vector2(520, 40)
	_history.position = Vector2(_tc().x - 260, _bid_box.position.y + _bid_box.size.y + 4)
	_panel.reset_size()
	_panel.position = Vector2(_cx() - _panel.size.x / 2.0, size.y - _panel.size.y - 8)
	var reactions := _ui.get_node_or_null("Reactions") as Control
	if reactions:
		reactions.position = Vector2(10, TopBar.HEIGHT + 4)  # под полосой — не мешает панели ставки


# --- Состояние -------------------------------------------------------------------

func _update_log() -> void:
	if not _log_panel.visible or _v.is_empty():
		return
	var lines := []
	var last_round := -1
	for e in _v.get("log", []):
		if int(e["round"]) != last_round:
			last_round = int(e["round"])
			lines.append("[color=#a9c0b4]— Раунд %d —[/color]" % last_round)
		var s := int(e["seat"])
		if s < 0:
			lines.append("[i]%s[/i]" % str(e["text"]))
		else:
			var p: Dictionary = _v["players"][s]
			lines.append("[color=#%s][b]%s[/b][/color] %s" % [Net.color_of(int(p.get("color", 0))).to_html(false), str(p["name"]).replace("[", "("), str(e["text"])])
	_log_text.text = "
".join(lines)


func _on_state(v: Dictionary) -> void:
	if _revealing:
		_queued = v
		return
	_apply(v)


func _apply(v: Dictionary) -> void:
	_v = v
	_me = v["you"]
	_n = v["players"].size()
	_auto_deadline = Time.get_ticks_msec() + int(v.get("auto_in", 0)) * 1000
	if _cups.size() != _n:
		_build()
	var phase: String = v["phase"]
	if phase in ["reveal", "game_over"] and _revealed_round != int(v["round_no"]) and not v["reveal"].is_empty():
		_start_reveal()
		return
	_bid_box.visible = phase in ["roll", "bid"]
	_history.visible = phase in ["roll", "bid"]
	if phase == "roll":
		_new_round_visuals()
		_banner.text = ""
	_update_cups()
	_update_plates()
	_update_center()
	_update_panel()
	_update_overlay()
	_layout()
	_update_log()


func _build() -> void:
	for arr in [_plates, _cups, _rows]:
		for node in arr:
			node.queue_free()
	_plates.clear()
	_cups.clear()
	_rows.clear()
	_shaken_seen.clear()
	for s in _n:
		var p := K12UI.panel(Color(0.07, 0.05, 0.03, 0.88), 6, "small")
		_seats_layer.add_child(p)
		_plates.append(p)
		var cup := PerudoCup.new(76.0 if s == _me else 62.0)
		cup.color = _seat_color(s)
		_table_layer.add_child(cup)
		if s == _me:
			cup.grabbed.connect(func(): Net.send_action("shaking", {"on": true}))
			cup.shaken.connect(func():
				_shaken_seen[_me] = true
				_scatter_mine()
				Net.send_action("shake"))
		_cups.append(cup)
		var row := K12UI.hbox(3)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_table_layer.add_child(row)
		_rows.append(row)
		_shaken_seen.append(false)
	_layout()


func _new_round_visuals() -> void:
	for s in _n:
		var cup: PerudoCup = _cups[s]
		if cup.lifted:
			cup.lift(false)
		K12UI.clear(_rows[s])
		cup.visible = _v["counts"][s] > 0


func _update_cups() -> void:
	var phase: String = _v["phase"]
	for s in _n:
		var cup: PerudoCup = _cups[s]
		var shaken: bool = _v["shaken"][s]
		if shaken and not _shaken_seen[s] and phase == "roll":
			if s != _me:
				cup.wobble()
				get_tree().create_timer(0.4).timeout.connect(_scatter_hidden.bind(s))
			else:
				_scatter_mine()  # стакан встряхнулся автоматически
		_shaken_seen[s] = shaken
		if s != _me:
			cup.rattle(phase == "roll" and not shaken and bool(_v.get("shaking", [])[s] if s < _v.get("shaking", []).size() else false))
		cup.shakeable = phase == "roll" and s == _me and not shaken and _v["counts"][s] > 0
	# свои кости — после того как потряс стакан
	K12UI.clear(_my_dice)
	var mine: Array = _v["dice"][_me]
	if _v["counts"][_me] > 0 and phase != "game_over":
		if _scattering_me:
			pass  # кости ещё летят — ряд появится, когда они соберутся
		elif _v["shaken"][_me] or phase != "roll":
			for d in mine:
				_my_dice.add_child(PerudoDie.new(d, 46, _seat_color(_me)))
		else:
			_my_dice.add_child(K12UI.label("Зажмите стакан мышью и потрясите →", K12UI.BODY, K12UI.CREAM))


func _update_plates() -> void:
	var phase: String = _v["phase"]
	_top.info.text = "Раунд %d · Костей на столе: %d" % [_v["round_no"], _v["total"]] + ("  ·  ПАЛИФИКО" if _v["maputo"] else "")
	if _v["phase"] == "seating":
		_top.info.text = "Рассадка · игроков: %d" % _n
	for s in _n:
		var p: PanelContainer = _plates[s]
		K12UI.clear(p)
		var col := K12UI.vbox(2)
		p.add_child(col)
		var head := K12UI.hbox(6)
		head.add_child(K12Plate.Avatar.make(Net.avatar(int(_v["players"][s].get("steam_id", 0))), _v["players"][s]["name"]))
		var nm := PlayerTag.make_seat(_v["players"], s, _me, 16, K12UI.GOLD if s == _me else K12UI.CREAM, "  (вы)" if s == _me else "", false)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		col.add_child(head)
		var dice_row := K12UI.hbox(2)
		for i in int(_v["counts"][s]):
			dice_row.add_child(PerudoDie.new(0, 14, _seat_color(s)))
		if _v["counts"][s] == 0:
			dice_row.add_child(K12UI.label("выбыл", K12UI.CAP, K12UI.RED))
		col.add_child(dice_row)
		var st := ""
		var color := K12UI.MUTED
		if _v["counts"][s] > 0:
			match phase:
				"roll":
					st = "стакан встряхнут" if _v["shaken"][s] else "трясёт стакан…"
				"bid":
					if _v["turn"] == s:
						st = "думает над ставкой…"
						color = K12UI.GOLD
		if _v["players"][s].get("bot", false):
			st = "бот · " + st if st != "" else "бот"
		col.add_child(K12UI.label(st, K12UI.CAP, color))
		p.modulate = Color(1, 1, 1, 0.45) if _v["counts"][s] == 0 else Color.WHITE
		var turn_now: bool = phase == "bid" and _v["turn"] == s
		p.add_theme_stylebox_override("panel", K12UI.box(Color(0.12, 0.08, 0.03, 0.92) if turn_now else Color(0.07, 0.05, 0.03, 0.88), 6, K12UI.GOLD if turn_now else Color.TRANSPARENT, 2 if turn_now else 0))


## Ставка в центре: «Имя: N × [кость]», и история ставок раунда.
func _update_center() -> void:
	K12UI.clear(_bid_box)
	var bid: Dictionary = _v["bid"]
	var phase: String = _v["phase"]
	var col := K12UI.vbox(4)
	_bid_box.add_child(col)
	if bid.is_empty():
		var t := "Трясите стаканы!" if phase == "roll" else "%s начинает раунд" % _v["players"][_v["turn"]]["name"]
		var tl := K12UI.label(t, K12UI.BODY, K12UI.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		col.add_child(tl)
		_roll_label = tl if phase == "roll" else null
	else:
		col.add_child(K12UI.label("Ставка: " + _v["players"][bid["seat"]]["name"], K12UI.CAP, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		var row := K12UI.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var qty := K12UI.label(str(bid["q"]) + " ×", K12UI.H1, K12UI.GOLD)
		qty.add_theme_font_override("font", K12UI.font("bold"))
		row.add_child(qty)
		row.add_child(PerudoDie.new(bid["face"], 48, _seat_color(int(bid.get("seat", _me)))))
		col.add_child(row)
	if _v["maputo"]:
		col.add_child(K12UI.label("Палифико: единицы не джокеры, номинал не меняется", K12UI.CAP, K12UI.RED, HORIZONTAL_ALIGNMENT_CENTER))
	var bids: Array = _v["bids"]
	var parts := []
	for i in range(maxi(0, bids.size() - 6), bids.size() - 1):
		var b: Dictionary = bids[i]
		parts.append("%s: %d %s" % [_v["players"][b["seat"]]["name"], b["q"], NAMES_GEN[b["face"]]])
	_history.text = " → ".join(parts)


# --- Панель ставки ----------------------------------------------------------------

func _valid(q: int, face: int) -> bool:
	return PerudoRules.check_bid(_v["bid"], _v["bids"], _v["maputo"], _v["total"], q, face)


func _min_q(face: int) -> int:
	for q in range(1, int(_v["total"]) + 1):
		if _valid(q, face):
			return q
	return -1


func _update_panel() -> void:
	K12UI.clear(_panel)
	var phase: String = _v["phase"]
	var my_turn: bool = phase == "bid" and _v["turn"] == _me and _v["counts"][_me] > 0
	if phase == "reveal":
		_update_panel_reveal_done()
		return
	var col := K12UI.vbox(8)
	_panel.add_child(col)
	if phase == "seating":
		col.add_child(K12UI.label("Рассадка за столом: по кругу — и порядок ходов", K12UI.BODY, K12UI.CREAM, HORIZONTAL_ALIGNMENT_CENTER))
		if Net.is_host():
			var row := K12UI.hbox(10)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			var mix := K12UI.button("Перемешать игроков", K12UI.BODY)
			mix.pressed.connect(func():
				Sfx.play("card_shove", -4)
				Net.send_action("seat_shuffle"))
			row.add_child(mix)
			var go := K12UI.primary("Начать игру", K12UI.BODY, 200)
			go.theme_type_variation = "SelectedButton"
			go.pressed.connect(func(): Net.send_action("seat_begin"))
			row.add_child(go)
			col.add_child(row)
		else:
			col.add_child(K12UI.label("Хост рассаживает игроков…", K12UI.CAP, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		return
	if phase != "bid":
		col.add_child(K12UI.label("Встряхните стакан: зажмите его мышью, потрясите и отпустите." if phase == "roll" and not _v["shaken"][_me] and _v["counts"][_me] > 0 else "Ждём остальных…", K12UI.BODY, K12UI.CREAM, HORIZONTAL_ALIGNMENT_CENTER))
		return
	if not my_turn:
		var who: String = _v["players"][_v["turn"]]["name"]
		col.add_child(K12UI.label("Ходит %s…" % who if _v["counts"][_me] > 0 else "Вы выбыли — смотрите, кто победит. Ходит %s…" % who, K12UI.BODY, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		return
	if not _valid(_qty, _face):
		var mq := _min_q(_face)
		if mq < 0:
			for f in range(1, 7):
				if _min_q(f) > 0:
					_face = f
					break
			mq = _min_q(_face)
		_qty = maxi(mq, 1)
	col.add_child(K12UI.label("Ваш ход: ставка, «Дудо!» или «Калзак!»", K12UI.BODY, K12UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var row := K12UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var minus := K12UI.button("−", K12UI.BODY, 40)
	minus.pressed.connect(func():
		_qty = maxi(1, _qty - 1)
		_update_panel()
		_layout())
	row.add_child(minus)
	var qty := K12UI.label(str(_qty), K12UI.H1, K12UI.GOLD)
	qty.add_theme_font_override("font", K12UI.font("bold"))
	qty.custom_minimum_size.x = 34
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(qty)
	var plus := K12UI.button("+", K12UI.BODY, 40)
	plus.disabled = _qty >= int(_v["total"])
	plus.pressed.connect(func():
		_qty = mini(int(_v["total"]), _qty + 1)
		_update_panel()
		_layout())
	row.add_child(plus)
	row.add_child(K12UI.label("×", K12UI.H1, K12UI.CREAM))
	for f in range(1, 7):
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = f == _face
		b.custom_minimum_size = Vector2(54, 54)
		b.disabled = _min_q(f) < 0
		var d := PerudoDie.new(f, 38, _seat_color(_me))
		d.position = Vector2(8, 8)
		d.dim = b.disabled
		b.add_child(d)
		var face := f
		b.pressed.connect(func():
			_face = face
			if not _valid(_qty, _face):
				_qty = maxi(_min_q(_face), 1)
			_update_panel()
			_layout())
		row.add_child(b)
	col.add_child(row)
	var act := K12UI.hbox(10)
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	var place := K12UI.primary("Поставить: %d %s" % [_qty, NAMES_GEN[_face]], K12UI.BODY)
	place.disabled = not _valid(_qty, _face)
	place.pressed.connect(func():
		Sfx.play("chip")
		Net.send_action("bid", {"q": _qty, "face": _face, "maputo": _maputo and _v["can_maputo"]}))
	act.add_child(place)
	if not _v["bid"].is_empty():
		var dudo := K12UI.primary("Дудо!", K12UI.BODY)
		dudo.tooltip_text = "Не верю: на столе меньше, чем в ставке"
		dudo.add_theme_color_override("font_color", K12UI.RED)
		dudo.pressed.connect(func():
			Sfx.play("arr", -2)
			Net.send_action("challenge"))
		act.add_child(dudo)
		var calza := K12UI.button("Калзак!", K12UI.BODY)
		calza.tooltip_text = "Ставка верна ровно: угадаете — вернёте себе кость, нет — потеряете"
		calza.add_theme_color_override("font_color", K12UI.GREEN)
		calza.pressed.connect(func():
			Sfx.play("card_shove")
			Net.send_action("calza"))
		act.add_child(calza)
	if _v["can_maputo"]:
		var mp := CheckBox.new()
		mp.text = "Объявить Палифико"
		mp.button_pressed = _maputo
		mp.toggled.connect(func(on): _maputo = on)
		act.add_child(mp)
	col.add_child(act)


# --- Вскрытие ---------------------------------------------------------------------

func _start_reveal() -> void:
	_revealing = true
	_revealed_round = int(_v["round_no"])
	_bid_box.visible = false  # во время вскрытия ставка — в надписи по центру
	_history.visible = false
	var rv: Dictionary = _v["reveal"]
	_update_plates()
	_update_center()
	K12UI.clear(_panel)
	_panel.add_child(K12UI.label("Вскрытие… (клик — пропустить)", K12UI.BODY, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_layout()
	var bid: Dictionary = rv["bid"]
	var face_txt: String = NAMES_GEN[bid["face"]]
	var cry := "Калзак!" if rv.get("calza", false) else "Дудо!"
	_show_banner("%s: «%s» — на ставку «%d %s»" % [_v["players"][rv["challenger"]]["name"], cry, bid["q"], face_txt], K12UI.GREEN if rv.get("calza", false) else K12UI.RED)
	Sfx.play("arr", 0, 0.08)  # «Дудо!» / «Калзак!» — пиратский рык
	var t := create_tween()
	_reveal_tween = t
	t.tween_interval(1.2)
	t.tween_callback(_reveal_show_dice)
	t.tween_interval(0.6)
	var found := [0]
	for s in _n:
		for idx in rv["matches"][s]:
			var seat: int = s
			var i: int = idx
			t.tween_callback(func():
				found[0] += 1
				var row: HBoxContainer = _rows[seat]
				if i < row.get_child_count():
					var d: PerudoDie = row.get_child(i)
					d.highlight = Color(K12UI.GOLD, 0.95)
					var tw := d.create_tween()
					tw.tween_property(d, "scale", Vector2.ONE * 1.25, 0.08)
					tw.tween_property(d, "scale", Vector2.ONE, 0.1)
				Sfx.play("chip", -8, 0.1, 0.02)
				_show_banner("Найдено %s: %d из %d%s" % [face_txt, found[0], bid["q"], " (с единицами)" if rv["wild"] else ""], K12UI.CREAM))
			t.tween_interval(0.22)
	t.tween_interval(0.5)
	t.tween_callback(_reveal_result)
	t.tween_interval(2.0)
	t.tween_callback(_finish_reveal)


## Стаканы поднимаются, под ними — кости всех игроков.
func _reveal_show_dice() -> void:
	var rv: Dictionary = _v["reveal"]
	Sfx.play("die_shake", -4)
	for s in _n:
		if rv["dice"][s].size() > 0:
			_cups[s].lift(true)
			var row: HBoxContainer = _rows[s]
			K12UI.clear(row)
			for d in rv["dice"][s]:
				row.add_child(PerudoDie.new(d, 30 if s != _me else 34, _seat_color(s)))
	_layout()


func _reveal_result() -> void:
	var rv: Dictionary = _v["reveal"]
	var bid: Dictionary = rv["bid"]
	var ok: bool = rv["count"] >= bid["q"]
	var caller: String = _v["players"][rv["challenger"]]["name"]
	var text := ""
	if rv.get("calza", false):
		if rv["loser"] < 0:
			var gain_txt := ("%s возвращает себе кость" % caller) if rv["gained"] >= 0 else ("у %s и так полный стакан" % caller)
			text = "На столе ровно %d %s — Калзак удался!\n%s" % [rv["count"], NAMES_GEN[bid["face"]], gain_txt]
		else:
			text = "На столе %d %s — не ровно!\n%s теряет кость%s" % [rv["count"], NAMES_GEN[bid["face"]], caller, " и выбывает" if rv["eliminated"] else ""]
	else:
		var loser_name: String = _v["players"][rv["loser"]]["name"]
		text = "На столе %d %s — ставка %s!\n%s теряет кость%s" % [rv["count"], NAMES_GEN[bid["face"]], "сыграла" if ok else "не сыграла", loser_name, " и выбывает" if rv["eliminated"] else ""]
	_show_banner(text, K12UI.GOLD)
	if rv["loser"] < 0:
		Sfx.play("chips_win", -2)
		_fly_gain(rv["gained"])
		return
	Sfx.play("chips_big" if rv["loser"] != _me else "card_shove", -2)
	Sfx.play("pirate_laugh", -4, 0.06)  # кто-то потерял кость — пираты хохочут
	# потерянная кость улетает в центр стола
	var row: HBoxContainer = _rows[rv["loser"]]
	if row.get_child_count() > 0:
		var d: PerudoDie = row.get_child(row.get_child_count() - 1)
		var fly := PerudoDie.new(d.value, 34, d.color)
		_fx.add_child(fly)
		fly.global_position = d.global_position
		var tw := fly.create_tween()
		tw.tween_property(fly, "position", _tc() + Vector2(-17, 40), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(fly, "rotation", TAU, 0.7)
		tw.tween_property(fly, "modulate:a", 0.0, 0.6)
		tw.tween_callback(fly.queue_free)
		d.modulate.a = 0.2


## Калзак удался: кость прилетает из центра стола к игроку.
func _fly_gain(seat: int) -> void:
	if seat < 0:
		return
	var d := PerudoDie.new(1, 34, _seat_color(seat))
	_fx.add_child(d)
	d.position = _tc() + Vector2(-17, 40)
	var tw := d.create_tween()
	tw.tween_property(d, "position", _cup_pos(seat) - Vector2(17, 20), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(d, "rotation", -TAU, 0.7)
	tw.tween_property(d, "modulate:a", 0.0, 0.5)
	tw.tween_callback(d.queue_free)


func _finish_reveal() -> void:
	if not _revealing:
		return
	_revealing = false
	var nv := _queued if not _queued.is_empty() else _v
	_queued = {}
	_apply(nv)


## После вскрытия: «Далее» (хост переходит к следующему раунду, когда все нажали).
func _update_panel_reveal_done() -> void:
	K12UI.clear(_panel)
	if _v["phase"] != "reveal":
		return
	var row := K12UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var me_waiting: bool = _v.get("waiting", []).has(_v["players"][_me]["name"])
	var btn := K12UI.primary("Далее" if me_waiting else "Ждём остальных…", K12UI.BODY, 200)
	btn.disabled = not me_waiting
	btn.pressed.connect(func(): Net.send_action("next"))
	row.add_child(btn)
	_auto_label = K12UI.label("", K12UI.CAP, K12UI.MUTED)
	row.add_child(_auto_label)
	row.add_child(ReadyDots.make(_v["players"], ReadyDots.pressed_next(_v)))
	_panel.add_child(row)


func _process(_d: float) -> void:
	if is_instance_valid(_roll_label) and _me < _cups.size():
		var cup: PerudoCup = _cups[_me]
		var ready := cup.is_holding() and Time.get_ticks_msec() - cup.hold_ms >= 1000
		_roll_label.text = "Отпускайте!" if ready else "Трясите стаканы!"
	if is_instance_valid(_auto_label):
		_auto_label.text = "авто через %d с" % maxi(0, ceili((_auto_deadline - Time.get_ticks_msec()) / 1000.0))


func _input(event: InputEvent) -> void:
	if _revealing and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _reveal_tween:
			_reveal_tween.kill()
		_reveal_show_dice()
		var rv: Dictionary = _v["reveal"]
		for s in _n:
			var row: HBoxContainer = _rows[s]
			for idx in rv["matches"][s]:
				if idx < row.get_child_count():
					(row.get_child(idx) as PerudoDie).highlight = Color(K12UI.GOLD, 0.95)
		_reveal_result()
		_finish_reveal()


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.size = Vector2(560, 90)
	_banner.position = _tc() + Vector2(-280, -70)


# --- Финал ---------------------------------------------------------------------------

func _update_overlay() -> void:
	K12UI.clear(_overlay)
	if _v["phase"] != "game_over":
		return
	var w: int = _v["winner"]
	if not _celebrated:
		_celebrated = true
		Sfx.victory()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := K12UI.panel(Color(0.08, 0.055, 0.035, 0.96), 8, "double")
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var col := K12UI.vbox(14)
	panel.add_child(col)
	col.add_child(K12UI.title("Игра окончена", K12UI.H1))
	var text := "Вы победили — ваши кости пережили всех!" if w == _me else "%s побеждает — последний с костями!" % _v["players"][w]["name"]
	col.add_child(K12UI.label(text, K12UI.BODY, K12UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(K12UI.label("Раундов сыграно: %d" % _v["round_no"], K12UI.CAP, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var row := K12UI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if Net.is_host():
		var again := K12UI.primary("Новая партия", K12UI.BODY, 190)
		again.pressed.connect(Net.end_game)
		row.add_child(again)
		var back := K12UI.button("К выбору игры" if Net.is_party() else "В меню", K12UI.BODY, 190)
		back.pressed.connect(func(): app.back_to_menu())
		row.add_child(back)
	else:
		col.add_child(K12UI.label("Хост решает, что дальше.", K12UI.CAP, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		var leave := K12UI.button("Покинуть пати", K12UI.BODY, 190)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		row.add_child(leave)
	col.add_child(row)


# --- Кости разлетаются по столу после тряски -----------------------------------------

## Свои кости: вылетают из-под стакана, кувыркаются по сукну и собираются в ряд перед игроком.
func _scatter_mine() -> void:
	if _scattering_me or _v.is_empty():
		return
	var values: Array = _v["dice"][_me]
	if values.is_empty():
		return
	_scattering_me = true
	K12UI.clear(_my_dice)
	var targets := []
	for i in values.size():
		targets.append(Vector2(_cx() - 40 + i * 54, _cup_pos(_me).y - 52))
	_scatter(_me, values, targets, 46.0, func():
		_scattering_me = false
		_update_cups()
		_layout())


## Чужие кости — «пустые» (номиналы тайна): разлетаются и возвращаются под стакан.
func _scatter_hidden(seat: int) -> void:
	if _v.is_empty() or seat >= _n:
		return
	var n: int = _v["counts"][seat]
	var values := []
	for i in n:
		values.append(0)
	var back := []
	for i in n:
		back.append(_cup_pos(seat) - Vector2(15, 30))
	_scatter(seat, values, back, 30.0, Callable(), true)


func _scatter(seat: int, values: Array, targets: Array, side: float, on_done: Callable, fade_at_end: bool = false) -> void:
	var origin := _cup_pos(seat) - Vector2(side / 2.0, side + 10)
	var c := _tc()
	var r := _bg.felt_radii() * 0.86
	Sfx.play("die_throw", -2 if seat == _me else -10, 0.08, 0.05)
	for i in values.size():
		var d := PerudoDie.new(0, side, _seat_color(seat))
		_fx.add_child(d)
		d.position = origin
		var p := origin + Vector2.from_angle(randf() * TAU) * randf_range(90.0, 230.0)
		var q := (p + Vector2(side, side) / 2.0 - c) / r
		if q.length() > 1.0:
			p = c + q.normalized() * r * 0.95 - Vector2(side, side) / 2.0
		var fly := randf_range(0.5, 0.7)
		var final_value: int = values[i]
		var hidden := final_value == 0
		if hidden:
			d.modulate.a = 0.22  # кости соперников — почти прозрачные «призраки»
		var t := d.create_tween().set_parallel(true)
		t.tween_property(d, "position", p, fly).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(d, "rotation", randf_range(-1.0, 1.0) * TAU * 1.5, fly).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if not hidden:
			# грани мелькают и в конце полёта останавливаются ровно на выпавшей — без подмены после
			t.tween_method(func(k: float): d.value = 1 + (final_value - 1 + int((1.0 - k) * 23.0)) % 6, 0.0, 1.0, fly)
		t.chain().tween_callback(func(): Sfx.play("die_hit", -12 if seat == _me else -18, 0.15, 0.04))
		t.chain().tween_interval(0.35 + i * 0.06)
		t.chain().tween_property(d, "position", targets[i], 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(d, "rotation", 0.0, 0.45)
		if not hidden:
			t.tween_callback(func(): d.value = final_value)
		if fade_at_end:
			t.tween_property(d, "modulate:a", 0.0, 0.45)
		var last := i == values.size() - 1
		t.chain().tween_callback(func():
			d.queue_free()
			if last and on_done.is_valid():
				on_done.call())


# --- Реплики: пузыри над табличками ----------------------------------------------------

func _on_chat_bubble(entry: Dictionary) -> void:
	var s: int = entry.get("seat", -1)
	if s < 0 or s >= _n or _plates.is_empty():
		return
	if _bubbles.has(s) and is_instance_valid(_bubbles[s]):
		_bubbles[s].queue_free()
	var b := K12UI.label(str(entry["text"]).left(60), 15 if entry["kind"] == "emote" else 13, K12UI.INK, HORIZONTAL_ALIGNMENT_CENTER)
	b.add_theme_stylebox_override("normal", K12UI.box(Color("f6efdc"), 12, Color("8a6b45"), 2))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(150, 0)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(b)
	var rect := _plate_rect(s)
	b.position = Vector2(clampf(rect.get_center().x - 75, 4, size.x - 160), maxf(rect.position.y - 46, 4))
	b.pivot_offset = Vector2(75, 20)
	b.scale = Vector2.ONE * 0.4
	Sfx.play("hover", -6, 0.1, 0.1)
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.2)
	t.tween_property(b, "modulate:a", 0.0, 0.4)
	t.tween_callback(b.queue_free)
	_bubbles[s] = b


## Цвет стакана и костей игрока — цвет его ника (в партии он не меняется).
func _seat_color(seat: int) -> Color:
	var players: Array = _v.get("players", [])
	if seat < 0 or seat >= players.size():
		return PerudoCup.seat_color(seat)
	return Net.color_of(int(players[seat].get("color", 0)))
