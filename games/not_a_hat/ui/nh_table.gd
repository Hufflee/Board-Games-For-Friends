extends Control
## Стол «Это не шляпа!»: игроки по кругу, подарки рядом в порядке передачи
## и штрафные карты; в центре — магазин подарков; подарок в пути — между дарителем и получателем,
## рядом — облачко «У меня для тебя подарок: …». Внизу — действие игрока.

var app: Node

var _v := {}
var _me := 0
var _seats: Array = []  # Control на каждого игрока (табличка + столбик + штрафы)
var _shop: NHCard
var _shop_label: Label
var _moving: NHCard
var _moving_holder: Control
var _bubble: Label
var _panel: PanelContainer
var _panel_key := ""
var _layer: Control
var _last_turn := -1
var _celebrated := false
var _filter := ""
var _picker: GridContainer
var _top: TopBar
var _hand_cards: Dictionary = {}
var _visual_key := ""
var _motion: Tween
var _exchange: Tween
var _exchange_cards: Array[NHCard] = []
var _moving_destination := Vector2.ZERO
var _exchange_epoch := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(NHStyle.Backdrop.new())
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_shop = NHCard.new(-1, 1)
	_layer.add_child(_shop)
	_shop_label = NHStyle.label("", NHStyle.CAP, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	_layer.add_child(_shop_label)
	_moving = NHCard.new(-1, 1)
	_moving.visible = false
	_moving_holder = Control.new()
	_moving_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_moving_holder.z_index = 5
	_layer.add_child(_moving_holder)
	_moving_holder.add_child(_moving)
	_bubble = NHStyle.label("", NHStyle.BODY, NHStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	_bubble.add_theme_stylebox_override("normal", NHStyle.box(NHStyle.PAPER, 16, NHStyle.INK, 3, 0.25))
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.custom_minimum_size.x = 230
	_bubble.z_index = 6
	_bubble.visible = false
	_layer.add_child(_bubble)

	# общая верхняя полоса (TopBar): название, ход/фаза, часы, чат, кнопки игры
	_top = TopBar.make(self, "Это не шляпа!", func(t, z): return NHStyle.button(t, z), null, Color.WHITE, NHStyle.font("bold"))
	_top.z_index = 20  # стол поднимает свои слои (панель z=10) — полоса и чат поверх
	var rules := NHStyle.button("Правила", NHStyle.CAP)
	rules.pressed.connect(func(): app.show_rules())
	_top.actions.add_child(rules)
	var settings := NHStyle.button("Настройки", NHStyle.CAP)
	settings.pressed.connect(func(): app.show_settings())
	_top.actions.add_child(settings)
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = NHStyle.button("Завершить партию", NHStyle.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся к выбору игры, пати сохранится.", Net.return_to_party)
	elif Net.is_party():
		leave = NHStyle.button("Покинуть пати", NHStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		leave = NHStyle.button("Выйти", NHStyle.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	leave.theme_type_variation = "QuietButton"
	_top.actions.add_child(leave)
	NHStyle.restyle_chat(_top.chat)
	_top.chat.z_index = 21

	_panel = NHStyle.panel(14)
	_panel.z_index = 10
	add_child(_panel)

	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := NHStyle.label(t, NHStyle.CAP, NHStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
		b.add_theme_stylebox_override("normal", NHStyle.box(NHStyle.PAPER, 14, NHStyle.INK, 3, 0.25))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 240
		return b, Vector2(-270, 70))
	resized.connect(_layout)
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state.call_deferred(Net.view)


# --- Роли ---------------------------------------------------------------------------

func _hotseat() -> bool:
	return _v.get("hotseat", false) or Net.mode == "offline"


func _name(s: int) -> String:
	return _v["players"][s]["name"] if s >= 0 and s < _v["players"].size() else "?"


## Кто сейчас действует за этим экраном (на одном компьютере — тот, чья очередь).
func _actor() -> int:
	if not _hotseat():
		return _me
	match _v["phase"]:
		"give":
			return int(_v["giver"])
		"respond":
			return int(_v["receiver"])
	return _me


func _send(kind: String, arg: Dictionary = {}) -> void:
	if _hotseat():
		arg["as"] = _actor()
	Net.send_action(kind, arg)


# --- Раскладка ----------------------------------------------------------------------

func _center() -> Vector2:
	var bottom := size.y - 160.0
	if is_instance_valid(_panel):
		bottom = size.y - maxf(_panel.get_combined_minimum_size().y, 100.0) - 28.0
	return Vector2(size.x * 0.5 - 60, (TopBar.HEIGHT + 16.0 + bottom) * 0.5)


## Место игрока s на эллипсе: вы — внизу, по часовой стрелке дальше.
func _seat_pos(s: int) -> Vector2:
	var n: int = maxi(1, (_v.get("players", []) as Array).size())
	var k := posmod(s - _me, n)
	var a := PI / 2.0 - TAU * k / n  # против часовой: «вправо» (+1) от вас — справа на экране
	var r := Vector2(minf(size.x * 0.38, 560), maxf(24.0, _center().y - TopBar.HEIGHT - 88.0))
	return _center() + Vector2(cos(a) * r.x, sin(a) * r.y)


func _layout() -> void:
	if _v.is_empty():
		return
	for s in _seats.size():
		var c: Control = _seats[s]
		c.reset_size()
		c.position = _seat_pos(s) - c.size * 0.5
	_shop.position = _center() - NHStyle.CARD * 0.5
	_shop_label.position = _center() + Vector2(-80, NHStyle.CARD.y * 0.5 + 4)
	_shop_label.size = Vector2(160, 20)
	_panel.reset_size()
	_panel.position = Vector2(size.x * 0.5 - _panel.size.x * 0.5 - 60, size.y - _panel.size.y - 12)


# --- Состояние ----------------------------------------------------------------------

func _on_state(v: Dictionary) -> void:
	var prev: Dictionary = _v
	_v = v
	_me = v["you"]
	_top.info.text = _info_text()
	var visual_key := JSON.stringify([v.get("game_id", ""), v.you, v.phase, v.turn_no,
		v.hands, v.card, v.penalties, v.giver, v.receiver, v.claim, v.players,
		v.shop_top, v.shop_left, v.get("hotseat", false)])
	if visual_key == _visual_key:
		return
	_visual_key = visual_key
	_cancel_exchange()
	if is_instance_valid(_motion):
		_motion.kill()
	var old_positions := _hand_positions()
	var incoming_position := _moving_holder.position
	_shop.set_card(int(v["shop_top"]), 1)
	_shop.tooltip_text = "Магазин подарков: верхний подарок виден всем"
	_shop_label.text = "Магазин · %d" % int(v["shop_left"])
	var key := "%s/%d/%d/%d" % [v["phase"], v["turn_no"], v["claim"], _actor()]
	if key != _panel_key:
		_panel_key = key
		_build_panel()
	_build_seats(prev)
	_layout()
	_update_moving(prev)
	if _is_accept(prev):
		_animate_exchange(prev, old_positions, incoming_position)
	_layout.call_deferred()
	_sounds(prev)


func _info_text() -> String:
	match String(_v["phase"]):
		"give":
			return "Ход: %s дарит подарок" % _name(int(_v["giver"]))
		"respond":
			return "Ход: %s решает" % _name(int(_v["receiver"]))
		"reveal":
			return "Вскрываем подарок"
		"game_over":
			return "Игра окончена"
	return "Ход: %s" % _name(int(_v["giver"]))


func _sounds(prev: Dictionary) -> void:
	if prev.is_empty():
		return
	var ph: String = _v["phase"]
	if ph == prev.get("phase", "") and int(_v["turn_no"]) == int(prev.get("turn_no", -1)):
		return
	match ph:
		"give":
			Sfx.play("card_slide", -4)
		"respond":
			Sfx.play("card_place", -4)
		"reveal":
			Sfx.play("card_flip", 0)
			Sfx.play("card_shove", -2)
		"game_over":
			if not _celebrated:
				_celebrated = true
				Sfx.victory()


func _build_seats(prev: Dictionary) -> void:
	for c in _seats:
		c.queue_free()
	_seats.clear()
	_hand_cards.clear()
	var n: int = _v["players"].size()
	for s in n:
		var box := NHStyle.vbox(4)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var active: bool = s == int(_v["giver"]) and _v["phase"] in ["give", "respond"] or s == int(_v["receiver"]) and _v["phase"] == "respond"
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", NHStyle.box(NHStyle.ACCENT if active else NHStyle.PAPER, 10, NHStyle.INK, 3, 0.25))
		var trow := NHStyle.hbox(6)
		trow.add_child(PlayerTag.make_seat(_v["players"], s, _me, NHStyle.CAP, NHStyle.INK, " (вы)" if s == _me and not _hotseat() else ""))
		var pen: int = (_v["penalties"][s] as Array).size()
		var pl := NHStyle.label("✖" .repeat(pen) + "·".repeat(maxi(0, int(_v["max_penalty"]) - pen)), NHStyle.CAP, NHStyle.BAD if pen > 0 else NHStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
		pl.tooltip_text = "Штрафы: %d из %d" % [pen, int(_v["max_penalty"])]
		pl.mouse_filter = Control.MOUSE_FILTER_PASS
		trow.add_child(pl)
		tag.add_child(trow)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(tag)
		# Порядок слева направо совпадает с очередью правил: старый подарок передарят первым.
		var col := Control.new()
		var hand: Array = _v["hands"][s]
		var factor := 0.82 if n <= 6 else 0.68
		var width := NHStyle.CARD.x * factor
		col.custom_minimum_size = Vector2(hand.size() * (width + 8) - 8, NHStyle.CARD.y * factor + 20)
		col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cards: Array[NHCard] = []
		for k in hand.size():
			var cd: Dictionary = hand[k]
			var old_g := int(cd.g)
			if prev.get("phase", "") == "memorize" and _v.phase != "memorize":
				if s < prev.hands.size() and k < prev.hands[s].size():
					old_g = int(prev.hands[s][k].g)
			var card := NHCard.new(old_g, int(cd["dir"]))
			card.scale = Vector2.ONE * factor
			card.pivot_offset = Vector2.ZERO
			card.position = Vector2(k * (width + 8), 0)
			card.glow = 0.7 if k == 0 and s == int(_v.receiver) and _v.phase == "respond" else 0.0
			col.add_child(card)
			cards.append(card)
			var caption := NHStyle.label("Дальше" if k == 0 else "Новый", NHStyle.CAP, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
			caption.position = Vector2(k * (width + 8), NHStyle.CARD.y * factor + 3)
			caption.size = Vector2(width, 17)
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(caption)
		box.add_child(col)
		_hand_cards[s] = cards
		# штрафные карты — маленькие, лицом вверх
		var pens: Array = _v["penalties"][s]
		if not pens.is_empty():
			var prow := NHStyle.hbox(2)
			prow.alignment = BoxContainer.ALIGNMENT_CENTER
			for g in pens:
				var pc := NHCard.new(int(g), 1)
				pc.set_card(int(g), 1)
				pc.custom_minimum_size = NHStyle.CARD * 0.38
				pc.scale = Vector2.ONE * 0.38
				pc.pivot_offset = Vector2.ZERO
				var holder := Control.new()
				holder.custom_minimum_size = NHStyle.CARD * 0.38
				holder.add_child(pc)
				prow.add_child(holder)
			box.add_child(prow)
		_layer.add_child(box)
		_seats.append(box)
		for k in cards.size():
			cards[k].set_card(int(hand[k].g), int(hand[k].dir), cards[k].gift != int(hand[k].g))


## Подарок в пути: летит от дарителя к получателю, рядом — облачко с названием.
func _update_moving(prev: Dictionary) -> void:
	var ph: String = _v["phase"]
	var cd: Dictionary = _v["card"]
	_bubble.visible = false
	if not ph in ["give", "respond", "reveal"] or cd.is_empty():
		_moving.visible = false
		return
	var g := int(_v["giver"])
	var r := int(_v["receiver"])
	if ph == "reveal":
		g = int(_v["reveal"]["giver"])
		r = int(_v["reveal"]["receiver"])
	_moving.visible = true
	_moving.set_card(int(cd["g"]), int(cd["dir"]), not _is_accept(prev))
	_moving.glow = 1.0 if ph == "reveal" else 0.0
	# подарок в пути — на полпути между дарителем и получателем (не поверх магазина)
	var mid := _seat_pos(g).lerp(_seat_pos(r), 0.5)
	if mid.distance_to(_center()) < 150:
		mid = _center() + (mid - _center()).normalized() * 150 if mid != _center() else _center() + Vector2(170, 0)
	var from := _seat_pos(g).lerp(mid, 0.55)
	var to := _seat_pos(r).lerp(mid, 0.55)
	var target := (from if ph == "give" else to) - NHStyle.CARD * 0.5
	_moving_destination = target
	if int(_v["turn_no"]) != _last_turn and ph == "give":
		_last_turn = int(_v["turn_no"])
		var start := (_center() if _v["from_shop"] else _seat_pos(g)) - NHStyle.CARD * 0.5
		_moving_holder.position = start
		_moving_holder.scale = Vector2.ONE * 0.8
		var t := create_tween().set_parallel()
		_motion = t
		t.tween_property(_moving_holder, "position", target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(_moving_holder, "scale", Vector2.ONE, 0.35)
	elif ph == "respond" and prev.get("phase", "") == "give":
		_motion = create_tween()
		_motion.tween_property(_moving_holder, "position", target, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		_moving_holder.position = target
	if int(_v["claim"]) >= 0 and ph in ["respond", "reveal"]:
		_bubble.visible = true
		_bubble.text = "«У меня для тебя подарок: %s!»" % NHData.gift_name(int(_v["claim"]))
		_bubble.reset_size()
		var bp := _seat_pos(g).lerp(_center(), 0.15) + Vector2(-_bubble.size.x * 0.5, -NHStyle.CARD.y * 0.5 - _bubble.size.y - 30)
		_bubble.position = Vector2(clampf(bp.x, 8, size.x - _bubble.size.x - 300), clampf(bp.y, 60, size.y - 200))


func _hand_positions() -> Dictionary:
	var result := {}
	for seat: int in _hand_cards:
		var positions: Array[Vector2] = []
		for card: NHCard in _hand_cards[seat]:
			positions.append(_layer.get_global_transform().affine_inverse() * card.get_global_transform().origin)
		result[seat] = positions
	return result


func _is_accept(prev: Dictionary) -> bool:
	return prev.get("phase", "") == "respond" and _v.phase == "give" and not _v.from_shop \
		and int(_v.giver) == int(prev.receiver) and int(_v.turn_no) == int(prev.turn_no) + 1 \
		and prev.get("game_id", "") == _v.get("game_id", "")


func _exchange_sprite(card_data: Dictionary, at: Vector2, factor: Vector2) -> Control:
	var holder := Control.new()
	holder.position = at
	holder.scale = factor
	holder.z_index = 8
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(holder)
	var card := NHCard.new(int(card_data.g), int(card_data.dir))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(card)
	_exchange_cards.append(card)
	return holder


func _animate_exchange(prev: Dictionary, old_positions: Dictionary, incoming: Vector2) -> void:
	if is_instance_valid(_motion):
		_motion.kill()
	_moving.visible = false
	var epoch := _exchange_epoch
	# Контейнеры сначала раскладывают новые слоты; отдельные держатели двигаются независимо от flip.
	await get_tree().process_frame
	if epoch != _exchange_epoch:
		return
	var seat := int(prev.receiver)
	if not old_positions.has(seat) or not _hand_cards.has(seat):
		_moving.visible = true
		return
	var old_hand: Array = prev.hands[seat]
	var new_cards: Array = _hand_cards[seat]
	var destinations := _hand_positions()
	for card: NHCard in new_cards:
		card.visible = false
	var factor: Vector2 = new_cards[0].scale
	var accepted := _exchange_sprite(prev.card, incoming, Vector2.ONE)
	var outgoing := _exchange_sprite(old_hand[0], old_positions[seat][0], factor)
	var accepted_card: NHCard = accepted.get_child(0)
	var new_g := int(_v.hands[seat][-1].g)
	accepted_card.set_card(new_g, int(_v.hands[seat][-1].dir), true)
	_exchange = create_tween().set_parallel()
	_exchange.tween_property(accepted, "position", destinations[seat][-1], 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_exchange.tween_property(accepted, "scale", factor, 0.55)
	_exchange.tween_property(outgoing, "position", _moving_destination, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_exchange.tween_property(outgoing, "scale", Vector2.ONE, 0.55)
	if old_hand.size() > 1:
		var remaining := _exchange_sprite(old_hand[1], old_positions[seat][1], factor)
		_exchange.tween_property(remaining, "position", destinations[seat][0], 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_exchange.chain().tween_callback(_finish_exchange.bind(epoch))


func _finish_exchange(epoch: int) -> void:
	if epoch != _exchange_epoch:
		return
	_moving_holder.position = _moving_destination
	_moving_holder.scale = Vector2.ONE
	_moving.visible = true
	_cancel_exchange()


func _cancel_exchange() -> void:
	_exchange_epoch += 1
	if is_instance_valid(_exchange):
		_exchange.kill()
	for card: NHCard in _exchange_cards:
		if is_instance_valid(card):
			card.get_parent().queue_free()
	_exchange_cards.clear()
	for seat: int in _hand_cards:
		for card: NHCard in _hand_cards[seat]:
			if is_instance_valid(card):
				card.visible = true


func _exit_tree() -> void:
	_cancel_exchange()
	if is_instance_valid(_motion):
		_motion.kill()


# --- Нижняя панель: действие игрока -------------------------------------------------

func _build_panel() -> void:
	NHStyle.clear(_panel)
	_picker = null
	var col := NHStyle.vbox(8)
	_panel.add_child(col)
	var ph: String = _v["phase"]
	var actor := _actor()
	var g := int(_v["giver"])
	var r := int(_v["receiver"])
	match ph:
		"memorize":
			col.add_child(_line("Запомните, у кого какой подарок! Скоро их перевернут рубашкой вверх.", true))
			if Net.is_host() or _hotseat():
				var b := NHStyle.primary("Все запомнили — играем!", NHStyle.BODY)
				b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				b.pressed.connect(func(): _send("nh_ready"))
				col.add_child(b)
		"give":
			if actor == g:
				var who := ("(за %s) " % _name(g)) if _hotseat() else ""
				var what := "новый подарок из магазина" if _v["from_shop"] else "свой старый подарок (левую карту)"
				col.add_child(_line("%sВы дарите %s игроку %s. Что это за подарок?" % [who, what, _name(r)], true))
				_build_picker(col)
			else:
				col.add_child(_line("%s дарит подарок игроку %s…" % [_name(g), _name(r)], true))
		"respond":
			if actor == r:
				var claim := NHData.gift_name(int(_v["claim"]))
				col.add_child(_line("%s%s: «У меня для тебя подарок: %s!»" % [("(за %s) " % _name(r)) if _hotseat() else "", _name(g), claim], true))
				var row := NHStyle.hbox(14)
				row.alignment = BoxContainer.ALIGNMENT_CENTER
				var yes := NHStyle.primary("Спасибо!", NHStyle.BODY, 200)
				yes.tooltip_text = "Новый подарок займёт правое место, левый вы передарите дальше" if (_v.hands[r] as Array).size() > 1 else "Принять подарок и передарить прежний"
				yes.pressed.connect(func(): _send("nh_respond", {"accept": true}))
				row.add_child(yes)
				var no := NHStyle.button("Это не %s!" % claim.to_lower(), NHStyle.BODY, 200)
				no.tooltip_text = "Отказаться: подарок откроют, ошибившийся получит штраф"
				no.pressed.connect(func(): _send("nh_respond", {"accept": false}))
				row.add_child(no)
				col.add_child(row)
			else:
				col.add_child(_line("%s думает: принять подарок от %s?" % [_name(r), _name(g)], true))
		"reveal":
			var rv: Dictionary = _v["reveal"]
			var real := NHData.gift_name(int(rv["g"]))
			var claimed := NHData.gift_name(int(rv["claim"]))
			var txt := ""
			if rv["truth"]:
				txt = "Это правда %s! Ошибся %s — штраф." % [real.to_lower(), _name(int(rv["receiver"]))]
			else:
				txt = "Это не %s, а %s! Штраф получает %s." % [claimed.to_lower(), real.to_lower(), _name(int(rv["giver"]))]
			col.add_child(_line(txt, true, NHStyle.BAD))
			col.add_child(_line("%s берёт новый подарок из магазина." % _name(int(rv["loser"])), false))
		"game_over":
			var w: Array = _v["winners"]
			var names := w.map(func(s): return _name(int(s)))
			col.add_child(NHStyle.label(("Победа: %s!" if names.size() == 1 else "Победили: %s!") % ", ".join(names), NHStyle.H1, NHStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, true))
			var res := []
			for s in _v["players"].size():
				res.append("%s — %d" % [_name(s), (_v["penalties"][s] as Array).size()])
			col.add_child(_line("Штрафы: " + " · ".join(res), false))
			var row2 := NHStyle.hbox(12)
			row2.alignment = BoxContainer.ALIGNMENT_CENTER
			if Net.is_host():
				var again := NHStyle.primary("Новая партия", NHStyle.BODY, 190)
				again.pressed.connect(Net.end_game)
				row2.add_child(again)
				var back := NHStyle.button("К выбору игры" if Net.is_party() else "В меню", NHStyle.BODY, 190)
				back.pressed.connect(func(): app.back_to_menu())
				row2.add_child(back)
			else:
				var leave := NHStyle.button("Покинуть пати", NHStyle.BODY, 190)
				LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
				row2.add_child(leave)
			col.add_child(row2)
	_layout.call_deferred()


func _line(t: String, bold: bool, color: Color = NHStyle.INK) -> Label:
	var l := NHStyle.label(t, NHStyle.BODY, color, HORIZONTAL_ALIGNMENT_CENTER, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 700
	return l


## Выбор названия подарка: поиск + сетка всех подарков (картинка и подпись).
func _build_picker(col: VBoxContainer) -> void:
	var find := LineEdit.new()
	find.placeholder_text = "Поиск подарка: начните вводить название…"
	find.text = _filter
	find.custom_minimum_size.x = 700
	col.add_child(find)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 168)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picker = GridContainer.new()
	_picker.columns = 7
	_picker.add_theme_constant_override("h_separation", 4)
	_picker.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_picker)
	col.add_child(scroll)
	find.text_changed.connect(func(t):
		_filter = t
		_fill_picker())
	find.text_submitted.connect(func(_t):
		# Enter — первый подходящий подарок
		if _picker.get_child_count() > 0:
			(_picker.get_child(0) as Button).pressed.emit())
	_fill_picker()
	find.grab_focus.call_deferred()


func _fill_picker() -> void:
	if not is_instance_valid(_picker):
		return
	NHStyle.clear(_picker)
	var order := range(NHData.GIFTS.size())
	order.sort_custom(func(a, b): return NHData.gift_name(a) < NHData.gift_name(b))
	var f := _filter.strip_edges().to_lower()
	for i in order:
		var name := NHData.gift_name(i)
		if f != "" and not name.to_lower().contains(f):
			continue
		var b := Button.new()
		b.icon = NHStyle.icon(i)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = name
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_constant_override("icon_max_width", 30)
		b.custom_minimum_size = Vector2(92, 74)
		b.tooltip_text = name
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var gi: int = i
		b.pressed.connect(func():
			Sfx.play("card_place", -4)
			_filter = ""
			_send("nh_give", {"g": gi}))
		_picker.add_child(b)
