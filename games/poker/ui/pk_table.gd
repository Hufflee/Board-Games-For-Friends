extends Control
## «Покер»: стол. Неоновый овал с сукном, места по кругу (я — снизу), общие карты и банк в центре,
## ставки — кучами фишек-спрайтов перед местами (чем больше ставка, тем выше куча, до «горы»).
## Слева — сессия/итоги и журнал, снизу — панель ставки: поле ввода, ползунок, 2×/3×/4×, ва-банк.
const Style := preload("res://games/poker/ui/pk_style.gd")
const LEFT_W := 216.0
const GAP := 16.0
const ACTION_H := 76.0
const SEAT := Vector2(176, 62)
const SMALL_CARD := Vector2(44, 61)
const SHOW_CARD := Vector2(58, 80)
const BOARD_CARD := Vector2(70, 97)
const MY_CARD := Vector2(84, 116)
var app: Node
var view: Dictionary = {}
var _top: TopBar
var _felt: Control
var _side: VBoxContainer
var _log: VBoxContainer
var _cards_layer: Control
var _seats_layer: Control
var _piles: Control
var _action: PanelContainer
var _action_row: HBoxContainer
var _overlay: PanelContainer
var _preview: TextureRect
var _raise_edit: LineEdit
var _raise_slider: HSlider
var _raise_button: Button
var _raise_value := 0
var _center := Vector2.ZERO
var _radii := Vector2(300, 160)
var _time_left := 0.0
var _timer_bar: Control
var _dark := false
var _last_revision := -1
var _last_board := 0
var _last_phase := ""
var _finish: Button


func _ready() -> void:
	_dark = Prefs.dark_theme()
	_top = TopBar.make(self, "Покер", Style.button, null, Style.ink(), Style.HEAD)
	for item: Array in [["Правила", app.show_rules], ["Настройки", app.show_settings]]:
		var b := Style.button(item[0], 16)
		b.pressed.connect(item[1])
		_top.actions.add_child(b)
	_top.actions.add_child(ThemeToggle.make(Style.button, 16))
	if Net.is_host():
		_finish = Style.button("Завершить", 16)
		_finish.name = "FinishGame"
		_finish.tooltip_text = "Закончить партию: побеждает лучший итог"
		_finish.pressed.connect(func(): LeaveGuard.ask(self, "Завершить игру?", "Партия закончится, победит лучший итог по фишкам.", "Завершить", func(): Net.send_action("finish", {}), "Играть дальше"))
		_top.actions.add_child(_finish)
	Prefs.changed.connect(_theme_changed)
	var leave := Style.button("Выйти", 16)
	LeaveGuard.wire(leave, "Выйти?", "Вернуться к выбору игры.", app.back_to_hub)
	_top.actions.add_child(leave)
	_felt = Control.new()
	_felt.name = "Felt"
	_felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_felt.draw.connect(_draw_felt)
	add_child(_felt)
	_cards_layer = Control.new()
	_cards_layer.name = "Cards"
	_cards_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards_layer)
	_piles = Control.new()
	_piles.name = "Piles"
	_piles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_piles.draw.connect(_draw_piles)
	add_child(_piles)
	_seats_layer = Control.new()
	_seats_layer.name = "Seats"
	_seats_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seats_layer)
	var side_panel := PanelContainer.new()
	side_panel.name = "SidePanel"
	side_panel.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 14, 14))
	side_panel.position = Vector2(GAP, TopBar.HEIGHT + GAP)
	side_panel.custom_minimum_size = Vector2(LEFT_W, 0)
	add_child(side_panel)
	var side_col := Style.column(12)
	side_panel.add_child(side_col)
	_side = Style.column(6)
	side_col.add_child(_side)
	side_col.add_child(Style.section("Журнал"))
	_log = Style.column(2)
	_log.name = "Log"
	side_col.add_child(_log)
	_action = PanelContainer.new()
	_action.name = "ActionPanel"
	add_child(_action)
	_action_row = Style.row(8)
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action.add_child(_action_row)
	_timer_bar = Control.new()
	_timer_bar.name = "TurnTimer"
	_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_bar.draw.connect(_draw_timer)
	add_child(_timer_bar)
	_overlay = PanelContainer.new()
	_overlay.name = "SessionOverlay"
	_overlay.visible = false
	_overlay.z_index = 60
	_overlay.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 24, 18, Style.CYAN))
	add_child(_overlay)
	_preview = TextureRect.new()
	_preview.name = "CardPreview"
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_preview.size = Vector2(210, 291)
	_preview.z_index = 95
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	add_child(_preview)
	resized.connect(_layout)
	Net.state_changed.connect(_state)
	if not Net.view.is_empty():
		_state(Net.view)


func _theme_changed() -> void:
	if _dark == Prefs.dark_theme():
		return
	_dark = Prefs.dark_theme()
	get_tree().root.theme = Style.theme()
	app.theme = get_tree().root.theme
	app.show_table()


func _me() -> int:
	return int(view.get("you", -1))


func _state(next: Dictionary) -> void:
	if not next.has("stacks"):
		return
	var old_board := _last_board
	var old_phase := _last_phase
	view = next
	_time_left = float(view.get("time_left", 0.0))
	_last_board = view.board.size()
	_last_phase = str(view.phase)
	if int(view.get("revision", 0)) != _last_revision:
		_last_revision = int(view.get("revision", 0))
		_sounds(old_board, old_phase)
		_raise_value = int(view.me.get("min_raise_to", 0)) if not view.me.is_empty() else 0
	_layout()


func _sounds(old_board: int, old_phase: String) -> void:
	var phase := str(view.phase)
	if phase == "showdown" and old_phase == "hand":
		Sfx.play("chips_win", -4)
	elif view.board.size() > old_board:
		Sfx.play("card_flip", -6)
	elif phase == "hand" and old_phase != "hand":
		Sfx.play("card_shove", -6)
	elif phase == "hand":
		Sfx.play("chip", -8)


func _process(delta: float) -> void:
	if view.is_empty():
		return
	if str(view.phase) == "hand" and int(view.to_act) >= 0:
		_time_left = maxf(0.0, _time_left - delta)
		_timer_bar.queue_redraw()
	var text := ""
	match str(view.mode):
		"sport":
			text = "Сессия %d · раздача %d/%d" % [int(view.session_no), int(view.hand_no), int(view.session_hands)]
		_:
			text = "Раздача %d" % int(view.hand_no)
	if str(view.phase) == "game_over":
		text = "Итоги партии"
	_top.info.text = text


# ---------------------------------------------------------------- раскладка


## Позиция места на экране: я — снизу, остальные по часовой стрелке.
func _seat_pos(seat: int) -> Vector2:
	var n: int = view.players.size()
	var me := maxi(0, _me())
	var rel := (seat - me + n) % n
	var a := PI * 0.5 + TAU * rel / n
	return _center + Vector2(cos(a) * (_radii.x + 64.0), sin(a) * (_radii.y + 44.0))


func _layout() -> void:
	if view.is_empty() or not is_inside_tree():
		return
	var top := TopBar.HEIGHT + GAP
	var action_top := size.y - GAP - ACTION_H
	var region := Rect2(LEFT_W + GAP * 2, top, size.x - LEFT_W - GAP * 3, action_top - top - GAP)
	_center = region.get_center() + Vector2(0, 6)
	_radii = Vector2(clampf(region.size.x * 0.5 - 150.0, 220.0, 460.0), clampf(region.size.y * 0.5 - 92.0, 120.0, 240.0))
	for layer: Control in [_felt, _cards_layer, _piles, _seats_layer]:
		layer.position = Vector2.ZERO
		layer.size = size
	_felt.queue_redraw()
	_piles.queue_redraw()
	_build_seats()
	_build_cards()
	_build_side()
	_build_action()
	_action.reset_size()
	_action.position = Vector2(region.position.x + (region.size.x - _action.size.x) * 0.5, size.y - GAP - _action.size.y)
	_timer_bar.position = Vector2.ZERO
	_timer_bar.size = size
	_timer_bar.queue_redraw()
	_build_overlay()


# ---------------------------------------------------------------- сукно, банк, ставки


func _draw_felt() -> void:
	if view.is_empty():
		return
	var c := _center
	var r := _radii
	# бортик и сукно
	_ellipse(c + Vector2(0, 10), r + Vector2(34, 34), Color(0, 0, 0, 0.35))
	_ellipse(c, r + Vector2(30, 30), Style.RAIL)
	Style.neon_ellipse(_felt, c, r + Vector2(30, 30), Style.PINK, 3.0)
	_ellipse(c, r, Style.FELT)
	for k: int in 6:
		_ellipse(c, r * (0.9 - k * 0.13), Color(Style.FELT_CENTER, 0.18))
	Style.neon_ellipse(_felt, c, r - Vector2(10, 10), Style.CYAN, 1.5)
	# места под общие карты
	var board_rect := _board_rect()
	for i: int in 5:
		var slot := Rect2(board_rect.position + Vector2(i * (BOARD_CARD.x + 8), 0), BOARD_CARD)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.12)
		sb.border_color = Color(Style.CYAN, 0.28)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		_felt.draw_style_box(sb, slot)


## Фишки и метки — отдельным слоем поверх закрытых карт: куча ставки не прячется за рубашками.
func _draw_piles() -> void:
	if view.is_empty():
		return
	var c := _center
	var big: int = int(view.get("big_blind", 2))
	var phase := str(view.phase)
	# банк — над общими картами (без ставок текущей улицы — они лежат перед местами)
	var street_bets := 0
	for amount: int in view.bets:
		street_bets += amount
	var pot: int = int(view.pot) - street_bets
	if phase == "hand" and pot > 0:
		_pile(c + Vector2(0, -BOARD_CARD.y * 0.5 - 50), pot, big, 0.62, "Банк %d" % int(view.pot), Style.CYAN)
	# ставки перед местами
	for seat: int in view.players.size():
		var bet: int = int(view.bets[seat])
		if phase == "hand" and bet > 0:
			_pile(_bet_pos(seat), bet, big, 0.45, str(bet), Style.felt_ink())
	# итог раздачи: выигрыш кучей у победителя
	if phase == "showdown" and not view.result.is_empty():
		var won := {}
		for p: Dictionary in view.result.get("pots", []):
			var winners: Array = p.winners
			for seat: int in winners:
				won[seat] = int(won.get(seat, 0)) + int(p.amount) / winners.size()
		for seat: int in won:
			_pile(_bet_pos(seat), int(won[seat]), big, 0.6, "+%d" % int(won[seat]), Style.GOLD)
	# кнопка дилера и блайнды
	if phase in ["hand", "showdown"]:
		_disc(_marker_pos(int(view.button)), "D", Color("f7f1ff"), Color("2a1840"))
		if int(view.sb) >= 0 and int(view.sb) != int(view.button):
			_disc(_marker_pos(int(view.sb)), "SB", Color(Style.CYAN, 0.9), Color("10202a"))
		if int(view.bb) >= 0:
			_disc(_marker_pos(int(view.bb)), "BB", Color(Style.PINK, 0.95), Color("2a0618"))


func _ellipse(c: Vector2, r: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in 96:
		var a := TAU * i / 96.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	_felt.draw_colored_polygon(pts, color)


func _board_rect() -> Rect2:
	var w := BOARD_CARD.x * 5 + 8 * 4
	return Rect2(_center - Vector2(w * 0.5, BOARD_CARD.y * 0.5 - 6), Vector2(w, BOARD_CARD.y))


func _bet_pos(seat: int) -> Vector2:
	var p := _seat_pos(seat)
	if seat == maxi(0, _me()):
		return p.lerp(_center, 0.4) + Vector2(-160, 30)  # своя ставка — левее карт и ниже кучи соседа слева
	return p.lerp(_center, 0.5)


func _marker_pos(seat: int) -> Vector2:
	var p := _seat_pos(seat)
	if seat == maxi(0, _me()):
		return p + Vector2(SEAT.x * 0.5 + 20, -12)
	var toward := (_center - p).normalized()
	return p.lerp(_center, 0.3) + Vector2(-toward.y, toward.x) * 46.0


## Куча фишек: спрайт по размеру суммы, снизу — подпись на тёмной подложке.
func _pile(at: Vector2, amount: int, big: int, scale_k: float, caption: String, ink: Color) -> void:
	var tex := Style.pile_texture(amount, big)
	var sz := tex.get_size() * scale_k
	_piles.draw_texture_rect(tex, Rect2(at - Vector2(sz.x * 0.5, sz.y - 10), sz), false)
	var font := Style.weighted(Style.FONT, 800)
	var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var plate := Rect2(at + Vector2(-w * 0.5 - 8, 12), Vector2(w + 16, 20))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.02, 0.12, 0.72)
	sb.set_corner_radius_all(10)
	_piles.draw_style_box(sb, plate)
	_piles.draw_string(font, plate.position + Vector2(8, 15), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)


func _disc(at: Vector2, text: String, fill: Color, ink: Color) -> void:
	var radius := 13.0 if text.length() > 1 else 12.0
	_piles.draw_circle(at + Vector2(0, 2), radius, Color(0, 0, 0, 0.35))
	_piles.draw_circle(at, radius, fill)
	_piles.draw_arc(at, radius - 2.5, 0, TAU, 24, Color(ink, 0.35), 1.0, true)
	var font := Style.HEAD
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_piles.draw_string(font, at + Vector2(-w * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)


# ---------------------------------------------------------------- места


func _build_seats() -> void:
	Style.clear(_seats_layer)
	var phase := str(view.phase)
	var me := _me()
	for seat: int in view.players.size():
		var person: Dictionary = view.players[seat]
		var stack: int = int(view.stacks[seat])
		var turn: bool = phase == "hand" and int(view.to_act) == seat
		var folded: bool = bool(view.folded[seat])
		var out: bool = stack == 0 and (view.hole[seat] as Array).is_empty()
		var glow := Style.PINK if turn else (Style.GOLD if seat == me else Color.TRANSPARENT)
		var plate := PanelContainer.new()
		plate.name = "Seat%d" % seat
		plate.add_theme_stylebox_override("panel", Style.box(Color("221238") if seat != me else Color("2c1748"), 10, 12, glow))
		plate.custom_minimum_size = SEAT
		plate.size = SEAT
		plate.position = _seat_pos(seat) - SEAT * 0.5
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if (folded and phase == "hand") or out:
			plate.modulate = Color(1, 1, 1, 0.5)
		var col := Style.column(0)
		plate.add_child(col)
		var head := Style.row(6)
		var nick := Style.label(str(person.name), 16, Style.felt_ink())
		nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nick.clip_text = true
		head.add_child(nick)
		var chips := Style.heading(str(stack), 16, Style.GOLD)
		chips.name = "Stack"
		head.add_child(chips)
		col.add_child(head)
		var note := str(view.last_action[seat])
		if out:
			note = "выбыл до конца сессии" if str(view.mode) == "sport" else "без фишек"
		elif turn:
			note = "думает…"
		var sub := Style.label(note, 12, Style.PINK if turn else Color("c9b8e6"))
		sub.name = "LastAction"
		sub.clip_text = true
		col.add_child(sub)
		_seats_layer.add_child(plate)


func _draw_timer() -> void:
	if view.is_empty() or str(view.phase) != "hand" or int(view.to_act) < 0:
		return
	var seat: int = int(view.to_act)
	var p := _seat_pos(seat) + Vector2(-SEAT.x * 0.5 + 10, SEAT.y * 0.5 + 4)
	var k := clampf(_time_left / float(view.get("turn_time", 30.0)), 0.0, 1.0)
	_timer_bar.draw_rect(Rect2(p, Vector2(SEAT.x - 20, 4)), Color(0, 0, 0, 0.35))
	_timer_bar.draw_rect(Rect2(p, Vector2((SEAT.x - 20) * k, 4)), Style.PINK if k > 0.25 else Style.BAD)


# ---------------------------------------------------------------- карты


func _build_cards() -> void:
	Style.clear(_cards_layer)
	var me := _me()
	var showdown := str(view.phase) == "showdown"
	# общие карты
	var rect := _board_rect()
	for i: int in view.board.size():
		_card(int(view.board[i]), Rect2(rect.position + Vector2(i * (BOARD_CARD.x + 8), 0), BOARD_CARD), "Board%d" % i)
	# карты мест
	for seat: int in view.players.size():
		var cards: Array = view.hole[seat]
		if cards.is_empty():
			continue
		var p := _seat_pos(seat)
		if seat == me:
			# свои карты — веером над табличкой (соседние места при 6–8 игроках стоят вплотную справа и слева)
			var w := MY_CARD.x * 2 - 22
			var base := Vector2(p.x - w * 0.5, p.y - SEAT.y * 0.5 - MY_CARD.y + 18)
			for k: int in cards.size():
				var card := _card(int(cards[k]), Rect2(base + Vector2(k * (MY_CARD.x - 22), 0), MY_CARD), "Mine%d" % k)
				card.rotation = deg_to_rad(-5 + k * 10)
				if bool(view.folded[seat]):
					card.modulate = Color(1, 1, 1, 0.45)
			continue
		var revealed := int(cards[0]) >= 0
		var sz := SHOW_CARD if revealed and showdown else SMALL_CARD
		# карты не там, где куча ставки (она — по пути к центру): у верхних мест — справа от таблички,
		# у боковых и нижних — над табличкой
		var toward := (_center - p).normalized()
		var anchor := Vector2(p.x, p.y - SEAT.y * 0.5 - sz.y * 0.5 + 6)
		if toward.y > 0.5:
			anchor = Vector2(p.x + SEAT.x * 0.5 + sz.x + 2, p.y)
		for k: int in cards.size():
			var pos := anchor + Vector2(-sz.x + k * (sz.x - 14) + 6, -sz.y * 0.5)
			var card := _card(int(cards[k]), Rect2(pos, sz), "Hole%d_%d" % [seat, k])
			card.rotation = deg_to_rad(-6 + k * 12)


## Карта на столе; открытая — с крупным просмотром при наведении.
func _card(id: int, rect: Rect2, node_name: String) -> TextureRect:
	var card := TextureRect.new()
	card.name = node_name
	card.texture = Style.card_texture(id)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.position = rect.position
	card.size = rect.size
	card.pivot_offset = rect.size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_PASS if id >= 0 else Control.MOUSE_FILTER_IGNORE
	if id >= 0:
		card.mouse_entered.connect(func(): _show_preview(card))
		card.mouse_exited.connect(_preview.hide)
	_cards_layer.add_child(card)
	return card


func _show_preview(card: TextureRect) -> void:
	_preview.texture = card.texture
	var r := card.get_global_rect()
	var x := r.end.x + 12.0
	if x + _preview.size.x > size.x - 8.0:
		x = r.position.x - _preview.size.x - 12.0
	_preview.position = Vector2(x, clampf(r.position.y - 80.0, TopBar.HEIGHT + 8.0, size.y - _preview.size.y - 8.0))
	_preview.show()


# ---------------------------------------------------------------- боковая панель


func _build_side() -> void:
	Style.clear(_side)
	var people: Array = view.players
	var sport := str(view.mode) == "sport"
	if sport:
		_side.add_child(Style.section("Сессия %d · раздача %d/%d" % [int(view.session_no), int(view.hand_no), int(view.session_hands)]))
		_side.add_child(Style.label("Победа — %d очков" % int(view.target), 12, Style.muted()))
	else:
		_side.add_child(Style.section("Классика · раздача %d" % int(view.hand_no)))
		_side.add_child(Style.label("Итог = стек − докупки", 12, Style.muted()))
	var order := range(people.size())
	if sport:
		order.sort_custom(func(a: int, b: int) -> bool: return int(view.scores[a]) > int(view.scores[b]))
	else:
		order.sort_custom(func(a: int, b: int) -> bool: return int(view.profits[a]) > int(view.profits[b]))
	for seat: int in order:
		var line := Style.row(6)
		var nick := Style.label(str(people[seat].name), 16, Style.PINK if seat == _me() else Color.TRANSPARENT)
		nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nick.clip_text = true
		line.add_child(nick)
		if sport:
			line.add_child(Style.heading("%d" % int(view.scores[seat]), 16, Style.gold_ink()))
			line.add_child(Style.label("/%d" % int(view.target), 12, Style.muted()))
		else:
			var profit: int = int(view.profits[seat])
			var value := Style.heading("%+d" % profit, 16, Style.GOOD if profit > 0 else Style.BAD if profit < 0 else Style.muted())
			line.add_child(value)
			if int(view.rebuys[seat]) > 0:
				line.add_child(Style.label("×%d" % (int(view.rebuys[seat]) + 1), 12, Style.muted()))
		_side.add_child(line)
	Style.clear(_log)
	var entries: Array = view.log
	for i: int in range(maxi(0, entries.size() - 9), entries.size()):
		var entry := Style.label(str(entries[i]), 12, Style.muted() if i < entries.size() - 1 else Style.ink())
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.custom_minimum_size.x = LEFT_W - 28
		_log.add_child(entry)


# ---------------------------------------------------------------- панель ставки


func _build_action() -> void:
	Style.clear(_action_row)
	_raise_edit = null
	_raise_slider = null
	_raise_button = null
	var me := _me()
	var phase := str(view.phase)
	var mine: Dictionary = view.me
	var my_turn: bool = phase == "hand" and me >= 0 and int(view.to_act) == me
	_action.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 12, 16, Style.PINK if my_turn else Color.TRANSPARENT))
	if my_turn:
		_build_bet_controls(mine)
		return
	var text := _status_text()
	_action_row.add_child(Style.label(text, 16))
	if me >= 0 and bool(mine.get("can_rebuy", false)) and phase != "hand":
		var rebuy := Style.button("Сесть заново · 100 BB")
		rebuy.name = "Rebuy"
		rebuy.theme_type_variation = "SelectedButton"
		rebuy.pressed.connect(func(): Net.send_action("rebuy", {}))
		_action_row.add_child(rebuy)
	elif me >= 0 and bool(mine.get("can_rebuy", false)):
		_action_row.add_child(Style.label("· сесть заново можно после раздачи", 12, Style.muted()))
	if _finish != null:
		_finish.visible = str(view.mode) == "classic" and phase != "game_over"


func _status_text() -> String:
	var phase := str(view.phase)
	var people: Array = view.players
	var hand := str(view.me.get("hand_name", "")) if not view.me.is_empty() else ""
	var mine := " · у вас: %s" % hand if hand != "" else ""
	match phase:
		"hand":
			var seat: int = int(view.to_act)
			return ("Ходит %s" % people[seat].name if seat >= 0 else "Открываем карты…") + mine
		"showdown":
			var names := PackedStringArray()
			for p: Dictionary in view.result.get("pots", []):
				for seat: int in p.winners:
					if not names.has(str(people[seat].name)):
						names.append(str(people[seat].name))
			return "Банк забирает %s" % ", ".join(names)
		"session_end":
			return "Итоги сессии"
		"waiting":
			return "Ждём, пока кто-нибудь сядет заново"
		"game_over":
			return "Партия окончена"
	return ""


func _build_bet_controls(mine: Dictionary) -> void:
	var need: int = int(mine.get("to_call", 0))
	var low: int = int(mine.get("min_raise_to", 0))
	var high: int = int(mine.get("max_raise_to", 0))
	var can_raise: bool = bool(mine.get("can_raise", false))
	var fold := Style.button("Пас")
	fold.name = "Fold"
	fold.pressed.connect(func(): Net.send_action("fold", {}))
	_action_row.add_child(fold)
	var call_text := "Чек" if need == 0 else "Колл %d" % need
	if need > 0 and need >= high - int(view.bets[_me()]):
		call_text = "Колл · ва-банк %d" % need
	var call := Style.button(call_text)
	call.name = "Call"
	call.custom_minimum_size.x = 112
	call.pressed.connect(func(): Net.send_action("call", {}))
	if not can_raise:
		call.theme_type_variation = "SelectedButton"
	_action_row.add_child(call)
	if not can_raise:
		var hint := Style.label("повысить нельзя", 12, Style.muted())
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_action_row.add_child(hint)
		return
	var sep := VSeparator.new()
	_action_row.add_child(sep)
	_raise_value = clampi(_raise_value, low, high)
	_raise_edit = LineEdit.new()
	_raise_edit.name = "RaiseInput"
	_raise_edit.custom_minimum_size = Vector2(84, 40)
	_raise_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_raise_edit.max_length = 6
	_raise_edit.text = str(_raise_value)
	_raise_edit.tooltip_text = "Ставка «до» — от %d до %d" % [low, high]
	_raise_edit.text_changed.connect(func(t: String):
		if t.is_valid_int():
			_set_raise(int(t), false))
	_raise_edit.text_submitted.connect(func(_t: String): _send_raise())
	_raise_edit.focus_exited.connect(func():
		if is_instance_valid(_raise_edit):
			_raise_edit.text = str(_raise_value))
	_action_row.add_child(_raise_edit)
	_raise_slider = HSlider.new()
	_raise_slider.name = "RaiseSlider"
	_raise_slider.custom_minimum_size = Vector2(200, 40)
	_raise_slider.min_value = low
	_raise_slider.max_value = high
	_raise_slider.step = 1
	_raise_slider.value = _raise_value
	_raise_slider.focus_mode = Control.FOCUS_NONE
	_raise_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_raise_slider.value_changed.connect(func(v: float): _set_raise(int(v), true))
	_action_row.add_child(_raise_slider)
	# 2× / 3× / 4× от текущей ставки (нет ставки — от большого блайнда)
	var base: int = int(view.current_bet) if int(view.current_bet) > 0 else int(view.big_blind)
	for k: int in [2, 3, 4]:
		var mult := Style.button("%d×" % k, 16)
		mult.name = "Mult%d" % k
		mult.custom_minimum_size.x = 48
		mult.tooltip_text = "Поставить до %d" % clampi(base * k, low, high)
		mult.pressed.connect(func(): _set_raise(clampi(base * k, low, high), true))
		_action_row.add_child(mult)
	var allin := Style.button("Ва-банк", 16)
	allin.name = "AllIn"
	allin.pressed.connect(func(): _set_raise(high, true))
	_action_row.add_child(allin)
	_raise_button = Style.button("")
	_raise_button.name = "Raise"
	_raise_button.custom_minimum_size.x = 168
	_raise_button.theme_type_variation = "SelectedButton"
	_raise_button.pressed.connect(_send_raise)
	_action_row.add_child(_raise_button)
	_update_raise_button()


func _set_raise(value: int, sync_edit: bool) -> void:
	var mine: Dictionary = view.me
	var low: int = int(mine.get("min_raise_to", 0))
	var high: int = int(mine.get("max_raise_to", 0))
	_raise_value = clampi(value, low, high)
	if is_instance_valid(_raise_slider) and int(_raise_slider.value) != _raise_value:
		_raise_slider.set_value_no_signal(_raise_value)
	if sync_edit and is_instance_valid(_raise_edit):
		_raise_edit.text = str(_raise_value)
	_update_raise_button()


func _update_raise_button() -> void:
	if not is_instance_valid(_raise_button):
		return
	var high: int = int(view.me.get("max_raise_to", 0))
	if _raise_value >= high:
		_raise_button.text = "Ва-банк %d" % high
	elif int(view.current_bet) == 0:
		_raise_button.text = "Ставка %d" % _raise_value
	else:
		_raise_button.text = "Рейз до %d" % _raise_value


func _send_raise() -> void:
	var high: int = int(view.me.get("max_raise_to", 0))
	if _raise_value >= high:
		Net.send_action("allin", {})
	else:
		Net.send_action("raise", {"amount": _raise_value})
	Sfx.play("chips_big", -6)


# ---------------------------------------------------------------- итоги сессии


func _build_overlay() -> void:
	var phase := str(view.phase)
	_overlay.visible = phase == "session_end"
	if not _overlay.visible:
		return
	Style.clear(_overlay)
	var col := Style.column(12)
	_overlay.add_child(col)
	col.add_child(Style.heading("Итоги сессии %d" % int(view.session_no), 28, Style.CYAN))
	var people: Array = view.players
	for entry: Dictionary in view.places:
		var seat: int = int(entry.seat)
		var line := Style.row(12)
		line.add_child(Style.heading("%d." % int(entry.place), 16, Style.GOLD if int(entry.place) == 1 else Style.muted()))
		var nick := Style.label(str(people[seat].name), 16)
		nick.custom_minimum_size.x = 200
		line.add_child(nick)
		line.add_child(Style.label("+%d" % int(entry.points), 16, Style.GOOD if int(entry.points) > 0 else Style.muted()))
		var total := Style.heading("%d / %d" % [int(view.scores[seat]), int(view.target)], 16, Style.GOLD)
		total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(total)
		col.add_child(line)
	col.add_child(Style.label("Новая сессия — у всех снова 100 BB", 12, Style.muted()))
	if Net.is_host():
		var next := Style.button("Следующая сессия")
		next.name = "NextSession"
		next.theme_type_variation = "SelectedButton"
		next.pressed.connect(func(): Net.send_action("next", {}))
		col.add_child(next)
	_overlay.custom_minimum_size.x = 440
	_overlay.reset_size()
	_overlay.position = _center - _overlay.size * 0.5
