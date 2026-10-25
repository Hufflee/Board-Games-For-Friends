extends Control
## Ипподром «Ready Set Bet»: трек и комментатор слева, поле ставок справа, лоток жетонов снизу.
## Ставка — двумя способами: перетащить жетон на ячейку или кликнуть по ячейке и выбрать жетон
## (либо сначала выбрать жетон в лотке, потом ячейку).

const PerudoDieView := preload("res://games/perudo/ui/d6_view.gd")

var app: Node

var _v := {}
var _me := 0
var _as := 0  # на одном компьютере — за кого ставим
var _track: RSBTrack
var _board: RSBBoard
var _top: TopBar
var _status_label: Label
var _ticker: Label
var _ticker_lines: Array = []
var _dice_box: HBoxContainer
var _players_box: VBoxContainer
var _tray: HBoxContainer
var _tray_money: Label
var _vip_strip: HBoxContainer
var _layer: Control  # перетаскивание, всплывающие окна
var _overlay: Control  # итоги / драфт / конец игры
var _overlay_key := ""
var _countdown: Label
var _host_bar: HBoxContainer
var _host_key := ""
var _zoom: Control  # увеличенная VIP-карта из своей ложи

var _drag := {}  # {tok, sprite, moved, start}
var _ghosts := {}  # peer -> {spr, seen}: фишка, которую соперник сейчас тащит (полупрозрачная тень)
var _ghost_sent := 0  # когда последний раз отправляли свою позицию (не чаще 20 раз в секунду)
var _selected_tok := -1
var _popup: Control
var _pending := {}  # spot -> спрайт летящего жетона (ждём подтверждения хоста)
var _last_roll_n := -1
var _auto_deadline := 0
var _auto_label: Label
var _celebrated := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(RSBStyle.Backdrop.new())

	_status_label = RSBStyle.label("", RSBStyle.CAP, RSBStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	add_child(_status_label)

	_track = RSBTrack.new()
	add_child(_track)
	_countdown = RSBStyle.title("", RSBStyle.H1, RSBStyle.GOLD)
	_countdown.add_theme_color_override("font_outline_color", RSBStyle.INK)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_countdown)

	var tick := RSBStyle.panel(Color("231a12"), RSBStyle.GOLD)
	tick.name = "Ticker"
	var trow := RSBStyle.hbox(10)
	tick.add_child(trow)
	_dice_box = RSBStyle.hbox(4)
	_dice_box.custom_minimum_size = Vector2(74, 34)
	trow.add_child(_dice_box)
	_ticker = RSBStyle.label("Дом готовит забег…", RSBStyle.CAP, RSBStyle.GOLD, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	_ticker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ticker.clip_text = true
	_ticker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	trow.add_child(_ticker)
	_host_bar = RSBStyle.hbox(4)
	trow.add_child(_host_bar)
	add_child(tick)

	var plist := RSBStyle.panel()
	plist.name = "Players"
	var pv := RSBStyle.vbox(2)
	plist.add_child(pv)
	_players_box = RSBStyle.vbox(1)
	pv.add_child(_players_box)
	add_child(plist)

	var buttons := RSBStyle.hbox(6)  # кнопки игры — в верхней полосе (TopBar)
	var rules := RSBStyle.button("Правила", RSBStyle.CAP)
	rules.pressed.connect(func(): app.show_rules())
	buttons.add_child(rules)
	var settings := RSBStyle.button("Настройки", RSBStyle.CAP)
	settings.pressed.connect(func(): app.show_settings())
	buttons.add_child(settings)
	buttons.add_child(ThemeToggle.make(func(t, z): return RSBStyle.button(t, z), RSBStyle.CAP))  # солнце / луна — тема
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = RSBStyle.button("Завершить партию", RSBStyle.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся в лобби игры, пати сохранится.", Net.end_game)
	elif Net.is_party():
		leave = RSBStyle.button("Покинуть пати", RSBStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave = RSBStyle.button("Выйти", RSBStyle.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	buttons.add_child(leave)

	_board = RSBBoard.new()
	_board.spot_clicked.connect(_on_spot_clicked)
	add_child(_board)

	var tray := RSBStyle.panel(RSBStyle.CREAM, RSBStyle.INK)
	tray.name = "Tray"
	var trv := RSBStyle.hbox(10)
	tray.add_child(trv)
	var mv := RSBStyle.vbox(-4)
	mv.add_child(RSBStyle.label("КАССА", RSBStyle.CAP, RSBStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	_tray_money = RSBStyle.label("$0", RSBStyle.H1, RSBStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, "title")
	mv.add_child(_tray_money)
	mv.custom_minimum_size.x = 74
	trv.add_child(mv)
	_tray = RSBStyle.hbox(4)
	trv.add_child(_tray)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trv.add_child(sp)
	_vip_strip = RSBStyle.hbox(4)
	trv.add_child(_vip_strip)
	add_child(tray)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)

	var chat_holder := Control.new()
	chat_holder.name = "ChatHolder"
	chat_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chat_holder)
	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := RSBStyle.label(t, RSBStyle.CAP, RSBStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "bold")
		b.add_theme_stylebox_override("normal", RSBStyle.box(RSBStyle.CREAM, 6, RSBStyle.RED, 2))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 240
		return b, Vector2(-1860, 860))  # над пустой частью списка игроков

	# фон полосы — фон игры (прозрачный); содержимое чуть ниже красных полос, нарисованных у верхнего края фона
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = Color(0, 0, 0, 0.0)
	bar_sb.border_color = Color(RSBStyle.INK, 0.18)
	bar_sb.content_margin_left = 16
	bar_sb.content_margin_right = 12
	bar_sb.content_margin_top = 13
	bar_sb.content_margin_bottom = 2
	_top = TopBar.make(self, "Ready Set Bet", func(t, z): return RSBStyle.button(t, z), bar_sb, RSBStyle.INK, RSBStyle.font("bold"))
	# монетка — в панели фишек, в самой правой ячейке
	_top.coin_at = func() -> Vector2:
		var tr := get_node_or_null("Tray") as Control
		if tr == null:
			return Vector2(-9999, -9999)
		var r := tr.get_global_rect()
		return Vector2(r.end.x - 44.0, r.get_center().y)
	for c in buttons.get_children():
		buttons.remove_child(c)
		_top.actions.add_child(c)
	RSBStyle.restyle_chat(_top.chat)

	resized.connect(_layout)
	_layout()
	Net.state_changed.connect(_on_state)
	Net.ghost_received.connect(_on_ghost)
	if not Net.view.is_empty():
		_on_state(Net.view)


func _layout() -> void:
	var w := size.x
	var h := size.y
	var left_w := 520.0
	var t0 := float(TopBar.HEIGHT)
	_status_label.position = Vector2(18, t0 + 8)
	_status_label.size = Vector2(left_w - 8, 24)
	_track.position = Vector2(18, t0 + 38)
	_track.size = Vector2(left_w - 8, 282)
	_countdown.position = _track.position
	_countdown.size = _track.size
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tick := get_node("Ticker") as Control
	tick.position = Vector2(14, t0 + 332)
	tick.size = Vector2(left_w, 50)
	var pl := get_node("Players") as Control
	pl.position = Vector2(14, t0 + 390)
	pl.size = Vector2(left_w, h - pl.position.y - 16)
	var chat_holder := get_node("ChatHolder") as Control
	chat_holder.position = pl.position
	chat_holder.size = pl.size + Vector2(0, 2)
	var bx := left_w + 30.0
	_board.position = Vector2(bx, t0 + 8)
	_board.size = Vector2(w - bx - 14, h - t0 - 8 - 100)
	var tray := get_node("Tray") as Control
	tray.position = Vector2(bx, h - 92)
	tray.size = Vector2(w - bx - 14, 80)
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	_layer.size = size


# --- Роли --------------------------------------------------------------------------

func _hotseat() -> bool:
	return _v.get("hotseat", false)


func _seat() -> int:
	return _as if _hotseat() else _me


func _name(s: int) -> String:
	return _v["players"][s]["name"]


# --- Состояние ---------------------------------------------------------------------

func _on_state(v: Dictionary) -> void:
	var prev_phase: String = _v.get("phase", "")
	var prev_bets: Dictionary = _v.get("bets", {})
	var prev_go: bool = _v.get("rsb_go", false)
	_v = v
	_me = v["you"]
	_auto_deadline = Time.get_ticks_msec() + int(v.get("auto_in", 0)) * 1000
	var phase: String = v["phase"]
	if _hotseat() and phase == "vip":
		for s in v["players"].size():
			if not v["vip_hand"][s].is_empty():
				_as = s
				break
	_top.info.text = "Забег %d из %d" % [v["race_no"], RSBData.RACES]
	_track.set_state(v, prev_phase == "race" or phase == "race")
	_board.set_view(v)
	_update_status(phase)
	_update_roll(v, prev_phase)
	_update_players()
	_update_tray()
	# подтверждённые ставки — убрать летящие жетоны
	for spot in _pending.keys():
		if v["bets"].has(spot) and v["bets"][spot].size() > prev_bets.get(spot, []).size() or phase != "race":
			var spr: Control = _pending[spot]
			if is_instance_valid(spr):
				spr.queue_free()
			_pending.erase(spot)
	if v["bets"].size() > prev_bets.size() or _count_bets(v["bets"]) > _count_bets(prev_bets):
		Sfx.play("chip", -2, 0.1)
	if phase != "race":
		_cancel_drag()
		_close_popup()
		_selected_tok = -1
	if phase == "start" and v.get("rsb_go", false) and not prev_go:
		_countdown_anim()
	var hkey := "%s/%s/%s" % [phase, v.get("rsb_go", false), v.get("paused", false)]
	if hkey != _host_key:
		_host_key = hkey
		_update_host_bar()
	if phase == "results" and prev_phase == "race":
		Sfx.play("chips_win", 0)
	var key := "%s/%d/%s/%d" % [phase, v["race_no"], ",".join(v.get("waiting", [])), _as]
	if phase == "vip":
		key += "/" + str(v["vip_hand"].map(func(h): return h.size()))
	if key != _overlay_key:
		_overlay_key = key
		_update_overlay()


func _count_bets(b: Dictionary) -> int:
	var n := 0
	for s in b:
		n += b[s].size()
	return n


func _update_status(phase: String) -> void:
	match phase:
		"start":
			_status_label.text = "Лошади у стартовых ворот" if _v.get("rsb_go", false) else "Изучите поле — ведущий скоро начнёт гонку"
			_status_label.add_theme_color_override("font_color", RSBStyle.INK)
		"race":
			if _v.get("paused", false):
				_status_label.text = "ПАУЗА · ставки принимаются"
				_status_label.add_theme_color_override("font_color", RSBStyle.RED)
			elif _v["no_more_bets"]:
				_status_label.text = "СТАВОК БОЛЬШЕ НЕТ!"
				_status_label.add_theme_color_override("font_color", RSBStyle.RED)
			else:
				_status_label.text = "Ставки принимаются · за линией: %d из 3" % _v["crossed"].size()
				_status_label.add_theme_color_override("font_color", RSBStyle.FELT)
		_:
			_status_label.text = "Забег окончен"
			_status_label.add_theme_color_override("font_color", RSBStyle.INK)


func _update_roll(v: Dictionary, prev_phase: String) -> void:
	var lr: Dictionary = v.get("last_roll", {})
	if v["phase"] == "start":
		_ticker_lines = []
		_ticker.text = "Лошади у стартовых ворот… На старт!" if v.get("rsb_go", false) else ("Все готовы? Жмите старт →" if Net.is_host() else "Ждём, когда ведущий начнёт гонку")
		RSBStyle.clear(_dice_box)
		_last_roll_n = -1
		return
	if lr.is_empty() or int(lr["n"]) == _last_roll_n:
		return
	_last_roll_n = int(lr["n"])
	RSBStyle.clear(_dice_box)
	for d in [lr["d1"], lr["d2"]]:
		var die := PerudoDieView.new(int(d), 32)
		_dice_box.add_child(die)
	var h: int = lr["horse"]
	var hn: String = RSBData.HORSES[h]
	var text := ""
	match int(lr["sum"]):
		2:
			text = "Змеиные глаза! "
		12:
			text = "Товарные вагоны! "
	if lr["bonus"]:
		text += "Бонус! %s прыгает на %d клетки!" % [hn, lr["move"]]
		Sfx.play("chips_soft", -2)
	else:
		text += "Выпало %d — %s вперёд." % [lr["sum"], hn]
		Sfx.play("die_hit", -14, 0.12, 0.05)
	if lr["crossed"]:
		text += " %s пересекла красную линию!" % hn
		Sfx.play("card_shove", -4)
	if lr["closed"]:
		text = "СТАВОК БОЛЬШЕ НЕТ! " + text
		Sfx.play("chips_big", 0)
	if v["phase"] == "results":
		text = "ФИНИШ! Побеждает %s!" % hn
	_ticker.text = text


func _update_players() -> void:
	RSBStyle.clear(_players_box)
	var order := range(_v["players"].size())
	order.sort_custom(func(a, b): return _v["money"][a] > _v["money"][b])
	for s in order:
		var row := RSBStyle.hbox(8)
		if _hotseat():
			# на одном компьютере: за кого ставим
			var b := RSBStyle.button("ставит" if s == _as else "за него", RSBStyle.CAP)
			UISel.pick(b, s == _as)
			b.custom_minimum_size.x = 64
			var ss: int = s
			b.pressed.connect(func():
				_as = ss
				_selected_tok = -1
				_update_tray()
				_update_players())
			row.add_child(b)
		var chip := RSBStyle.pic(RSBStyle.token_tex(s, 5, ""), Vector2(24, 24))
		row.add_child(chip)
		var nm := PlayerTag.make_seat(_v["players"], s, _me, 15, RSBStyle.INK, " (вы)" if s == _me and not _hotseat() else "")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(nm)
		var used := 0
		for t in _v["tokens"][s]:
			if t["used"]:
				used += 1
		row.add_child(RSBStyle.label("ставок %d/%d" % [used, _v["tokens"][s].size()], RSBStyle.CAP, RSBStyle.MUTED))
		var vipc: Array = _v["vips"][s]
		if not vipc.is_empty():
			var vl := RSBStyle.label("VIP×%d" % vipc.size(), RSBStyle.CAP, RSBStyle.RED, HORIZONTAL_ALIGNMENT_LEFT, "bold")
			vl.mouse_filter = Control.MOUSE_FILTER_STOP
			vl.tooltip_text = "\n".join(vipc.map(func(i): return RSBData.vip_title(RSBData.VIP[i]) + " — " + RSBData.vip_text(RSBData.VIP[i])))
			row.add_child(vl)
		var m := RSBStyle.label(RSBStyle.money(_v["money"][s]), RSBStyle.BODY, RSBStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT, "title")
		m.custom_minimum_size.x = 56
		row.add_child(m)
		_players_box.add_child(row)


# --- Лоток жетонов -------------------------------------------------------------------

func _update_tray() -> void:
	RSBStyle.clear(_tray)
	var s := _seat()
	_tray_money.text = RSBStyle.money(_v["money"][s])
	var toks: Array = _v["tokens"][s]
	for i in toks.size():
		var t: Dictionary = toks[i]
		var chip := TokenChip.new()
		chip.texture = RSBStyle.token_tex(s, t["v"], t["bonus"])
		chip.used = t["used"]
		chip.selected = i == _selected_tok
		chip.tooltip_text = _token_tip(t)
		var ii: int = i
		chip.grabbed.connect(func(at): _start_drag(ii, at))
		_tray.add_child(chip)
	RSBStyle.clear(_vip_strip)
	for c in _v["vips"][s]:
		var mini := Control.new()
		mini.custom_minimum_size = Vector2(44, 62)
		var face := RSBVipFace.new(c)
		face.scale = Vector2(44, 62) / RSBVipFace.SIZE
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini.add_child(face)
		var cc: int = c
		mini.mouse_filter = Control.MOUSE_FILTER_STOP
		mini.mouse_entered.connect(func(): _zoom_vip(cc, mini))
		mini.mouse_exited.connect(_unzoom_vip)
		_vip_strip.add_child(mini)


func _token_tip(t: Dictionary) -> String:
	var s := "Жетон «%d»: выигрыш = %d × коэффициент ячейки." % [t["v"], t["v"]]
	if t["bonus"] != "":
		var bl: int = RSBData.BONUS_TOKEN_LOSS[t["v"]]
		s += "\nБонус-жетон: " + ("отменяет штраф при проигрыше." if bl < 0 else ("при проигрыше ещё −$%d." % bl if bl > 0 else "без доп. штрафа."))
	if t["used"]:
		s += "\nУже на поле."
	else:
		s += "\nПеретащите на ячейку или кликните, чтобы выбрать."
	return s


## Можно ли положить жетон tok на ячейку (то же, что проверит хост).
func _can(tok: int, spot: String) -> bool:
	var s := _seat()
	if _v.get("phase", "") != "race" or tok < 0 or tok >= _v["tokens"][s].size() or _v["tokens"][s][tok]["used"]:
		return false
	if _board.spot_rect(spot) == Rect2():
		return false
	var has_vip := func(kind: String) -> Array:
		return _v["vips"][s].filter(func(i): return RSBData.VIP[i]["kind"] == kind)
	if _v["no_more_bets"] and (has_vip.call("late").is_empty() or _v["late_used"][s]):
		return false
	if spot.begins_with("ex_"):
		var card := spot.substr(0, spot.rfind("_"))
		for k in 3:
			for b in _v["bets"].get("%s_%d" % [card, k], []):
				if b["seat"] == s:
					return false
	var here: Array = _v["bets"].get(spot, [])
	if here.is_empty():
		return true
	if here.size() == 1 and here[0]["seat"] != s and not _v["piggy_used"][s]:
		var val: int = _v["tokens"][s][tok]["v"]
		for i in has_vip.call("piggy"):
			if RSBData.VIP[i]["value"] == val:
				return true
	return false


func _valid_spots(tok: int) -> Dictionary:
	var res := {}
	for spot in _board._rects:
		if _can(tok, spot):
			res[spot] = true
	return res


func _start_drag(tok: int, at: Vector2) -> void:
	if _v.get("phase", "") != "race" or _v["tokens"][_seat()][tok]["used"]:
		return
	_close_popup()
	var spr := ChipSprite.new(RSBStyle.token_tex(_seat(), _v["tokens"][_seat()][tok]["v"], _v["tokens"][_seat()][tok]["bonus"]))
	spr.position = at - spr.size / 2
	_layer.add_child(spr)
	_drag = {"tok": tok, "sprite": spr, "moved": false, "start": at}
	_board.highlight = _valid_spots(tok)
	_board.queue_redraw()
	Sfx.play("chips_soft", -10, 0.1)


func _input(event: InputEvent) -> void:
	if _drag.is_empty():
		return
	if event is InputEventMouseMotion:
		var spr: Control = _drag["sprite"]
		spr.position = event.position - spr.size / 2
		spr.rotation = clampf(event.relative.x * 0.02, -0.3, 0.3)
		_send_ghost(event.position, false)
		if event.position.distance_to(_drag["start"]) > 6.0:
			_drag["moved"] = true
		var local: Vector2 = _board.get_global_transform().affine_inverse() * event.position
		var s := _board.spot_at(local)
		if s != _board.hover:
			_board.hover = s
			_board.queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		get_viewport().set_input_as_handled()
		var tok: int = _drag["tok"]
		var spr: Control = _drag["sprite"]
		var moved: bool = _drag["moved"]
		_send_ghost(event.position, true)
		_drag = {}
		_board.highlight = {}
		_board.queue_redraw()
		if not moved:
			spr.queue_free()
			_selected_tok = -1 if _selected_tok == tok else tok
			_update_tray()
			if _selected_tok >= 0:
				_board.highlight = _valid_spots(tok)
				_board.queue_redraw()
			return
		var local: Vector2 = _board.get_global_transform().affine_inverse() * event.position
		var spot := _board.spot_at(local)
		if spot != "" and _can(tok, spot):
			_bet(tok, spot, spr)
		else:
			_fly_back(spr, tok)


func _cancel_drag() -> void:
	if _drag.is_empty():
		return
	_send_ghost(Vector2.ZERO, true)
	(_drag["sprite"] as Control).queue_free()
	_drag = {}
	_board.highlight = {}
	_board.queue_redraw()


## Своя фишка в руке — соперникам её тень: позиция в долях поля (у всех разный размер окна).
func _send_ghost(at: Vector2, done: bool) -> void:
	if _drag.is_empty() or _hotseat():
		return
	var now := Time.get_ticks_msec()
	if not done and now - _ghost_sent < 50:
		return
	_ghost_sent = now
	var local: Vector2 = _board.get_global_transform().affine_inverse() * at
	var t: Dictionary = _v["tokens"][_seat()][_drag["tok"]]
	Net.send_ghost({"g": "rsb", "seat": _seat(), "v": t["v"], "bonus": t["bonus"], "x": local.x / maxf(_board.size.x, 1.0), "y": local.y / maxf(_board.size.y, 1.0), "end": done})


func _on_ghost(peer: int, d: Dictionary) -> void:
	if str(d.get("g", "")) != "rsb" or _v.is_empty() or int(d.get("seat", -1)) == _seat():
		return
	var g: Dictionary = _ghosts.get(peer, {})
	if bool(d.get("end", false)):
		_drop_ghost(peer)
		return
	var at := _board.global_position + Vector2(float(d["x"]) * _board.size.x, float(d["y"]) * _board.size.y)
	if g.is_empty() or not is_instance_valid(g["spr"]):
		var spr := ChipSprite.new(RSBStyle.token_tex(int(d["seat"]), int(d["v"]), str(d["bonus"])))
		spr.modulate.a = 0.5
		spr.position = at - spr.size / 2
		_layer.add_child(spr)
		g = {"spr": spr}
		_ghosts[peer] = g
	var s: ChipSprite = g["spr"]
	g["seen"] = Time.get_ticks_msec()
	var tw := s.create_tween()
	tw.tween_property(s, "position", at - s.size / 2, 0.06)


func _drop_ghost(peer: int) -> void:
	var g: Dictionary = _ghosts.get(peer, {})
	_ghosts.erase(peer)
	if not g.is_empty() and is_instance_valid(g["spr"]):
		var s: Control = g["spr"]
		s.create_tween().tween_property(s, "modulate:a", 0.0, 0.2).finished.connect(s.queue_free)


func _expire_ghosts() -> void:
	# тень, о которой давно ничего не слышно (сообщение «отпустил» потерялось), гасим сама
	for peer in _ghosts.keys():
		if Time.get_ticks_msec() - int(_ghosts[peer].get("seen", 0)) > 1500:
			_drop_ghost(peer)


func _fly_back(spr: Control, tok: int) -> void:
	var target := spr.position
	if tok < _tray.get_child_count():
		var chip := _tray.get_child(tok) as Control
		target = chip.global_position + chip.size / 2 - spr.size / 2
	var t := create_tween().set_parallel()
	t.tween_property(spr, "position", target, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(spr, "scale", Vector2.ONE * 0.8, 0.22)
	t.chain().tween_callback(spr.queue_free)
	Sfx.play("card_slide", -10)


## Отправить ставку; жетон-спрайт «прилипает» к ячейке и ждёт подтверждения хоста.
func _bet(tok: int, spot: String, spr: Control = null) -> void:
	var r := _board.spot_rect(spot)
	var d := minf(r.size.x, r.size.y) * 0.92
	var target := _board.global_position + r.get_center() - Vector2(27, 27)
	if spr == null:
		var chip := _tray.get_child(tok) as Control
		spr = ChipSprite.new(RSBStyle.token_tex(_seat(), _v["tokens"][_seat()][tok]["v"], _v["tokens"][_seat()][tok]["bonus"]))
		spr.position = chip.global_position + chip.size / 2 - spr.size / 2
		_layer.add_child(spr)
	var t := create_tween()
	t.tween_property(spr, "position", target, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(spr, "rotation", 0.0, 0.16)
	t.parallel().tween_property(spr, "scale", Vector2.ONE * (d / 54.0) * 1.25, 0.16)
	t.tween_property(spr, "scale", Vector2.ONE * (d / 54.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(spr, "lift", 0.0, 0.14)  # жетон лёг на сукно — тень исчезает
	t.tween_interval(1.2)
	t.tween_callback(func():
		if is_instance_valid(spr):
			spr.queue_free())
	_pending[spot] = spr
	_selected_tok = -1
	var arg := {"tok": tok, "spot": spot}
	if _hotseat():
		arg["as"] = _as
	Net.send_action("rsb_bet", arg)


func _on_spot_clicked(spot: String, at: Vector2) -> void:
	if _v.get("phase", "") != "race":
		return
	if _selected_tok >= 0:
		if _can(_selected_tok, spot):
			_bet(_selected_tok, spot)
			_board.highlight = {}
			_board.queue_redraw()
		else:
			Sfx.play("card_shove", -10)
		return
	_open_popup(spot, at)


## Всплывающий выбор жетона для ячейки.
func _open_popup(spot: String, at: Vector2) -> void:
	_close_popup()
	var options := []
	var toks: Array = _v["tokens"][_seat()]
	for i in toks.size():
		if _can(i, spot):
			options.append(i)
	var p := RSBStyle.panel()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := RSBStyle.vbox(6)
	p.add_child(col)
	col.add_child(RSBStyle.label(_board.spot_info(spot)["title"], RSBStyle.CAP, RSBStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	if options.is_empty():
		col.add_child(RSBStyle.label("Сюда сейчас нельзя поставить.", RSBStyle.CAP, RSBStyle.RED))
	else:
		col.add_child(RSBStyle.label("Каким жетоном ставите?", RSBStyle.CAP, RSBStyle.MUTED))
		var row := RSBStyle.hbox(6)
		var info := _board.spot_info(spot)
		for i in options:
			var t: Dictionary = toks[i]
			var b := Button.new()
			b.icon = RSBStyle.token_tex(_seat(), t["v"], t["bonus"])
			b.expand_icon = true
			b.custom_minimum_size = Vector2(52, 52)
			b.tooltip_text = "Выигрыш $%d, проигрыш −$%d" % [int(t["v"]) * int(info["mult"]), info["loss"]]
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var ii: int = i
			b.pressed.connect(func():
				_close_popup()
				_bet(ii, spot))
			row.add_child(b)
		col.add_child(row)
	_layer.add_child(p)
	_popup = p
	p.reset_size.call_deferred()
	var pos := at + Vector2(12, -10)
	p.position = Vector2(clampf(pos.x, 8, size.x - 280), clampf(pos.y, 8, size.y - 130))
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _close_popup() -> void:
	if _popup and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _popup != null:
		_close_popup()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_popup()
		_selected_tok = -1
		_board.highlight = {}
		_board.queue_redraw()
		_update_tray()


# --- Управление гонкой (ведущий = хост) ----------------------------------------------

func _update_host_bar() -> void:
	RSBStyle.clear(_host_bar)
	if not Net.is_host():
		if _v.get("paused", false):
			_host_bar.add_child(RSBStyle.label("ПАУЗА", RSBStyle.CAP, RSBStyle.GOLD, HORIZONTAL_ALIGNMENT_LEFT, "title"))
		return
	match _v["phase"]:
		"start":
			if not _v.get("rsb_go", false):
				var go := RSBStyle.primary("Начать гонку", RSBStyle.CAP)
				go.pressed.connect(func(): Net.send_action("rsb_begin"))
				_host_bar.add_child(go)
		"race":
			if _v.get("paused", false):
				var step := RSBStyle.button("Следующий бросок", RSBStyle.CAP)
				step.pressed.connect(func(): Net.send_action("rsb_step"))
				_host_bar.add_child(step)
				var resume := RSBStyle.primary("Возобновить", RSBStyle.CAP)
				resume.pressed.connect(func(): Net.send_action("rsb_resume"))
				_host_bar.add_child(resume)
			else:
				var pause := RSBStyle.button("Пауза", RSBStyle.CAP)
				pause.pressed.connect(func(): Net.send_action("rsb_pause"))
				_host_bar.add_child(pause)


# --- VIP-карты своей ложи: при наведении — крупно в центре экрана ----------------------

func _zoom_vip(card: int, from: Control) -> void:
	_unzoom_vip()
	var face := RSBVipFace.new(card)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.pivot_offset = face.size / 2
	face.scale = Vector2.ONE * (from.size.x / face.size.x)
	face.position = from.global_position + from.size / 2 - face.size / 2
	_layer.add_child(face)
	_zoom = face
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(face, "position", size / 2 - face.size / 2, 0.22)
	t.tween_property(face, "scale", Vector2.ONE * 1.9, 0.22)
	Sfx.play("card_flip", -10)


func _unzoom_vip() -> void:
	if _zoom == null or not is_instance_valid(_zoom):
		_zoom = null
		return
	var face := _zoom
	_zoom = null
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(face, "scale", Vector2.ONE * 0.3, 0.16)
	t.tween_property(face, "modulate:a", 0.0, 0.16)
	t.chain().tween_callback(face.queue_free)


# --- Отсчёт, итоги, VIP, конец -----------------------------------------------------

func _countdown_anim() -> void:
	var t := create_tween()
	for word in ["НА СТАРТ…", "ВНИМАНИЕ…", "МАРШ!"]:
		t.tween_callback(func():
			_countdown.text = word
			_countdown.scale = Vector2.ONE
			Sfx.play("chip" if word != "МАРШ!" else "chips_big", -2))
		t.tween_interval(1.25)
	t.tween_callback(func(): _countdown.text = "")


func _update_overlay() -> void:
	RSBStyle.clear(_overlay)
	_auto_label = null
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match _v["phase"]:
		"results":
			_results_panel()
		"vip":
			_vip_panel()
		"game_over":
			_game_over_panel()


func _dim() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.06, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP


func _results_panel() -> void:
	var p := RSBStyle.panel()
	p.custom_minimum_size = Vector2(560, 0)
	_overlay.add_child(p)
	p.position = Vector2(_board.position.x + (_board.size.x - 560) * 0.5, _board.position.y + 60)
	var col := RSBStyle.vbox(8)
	p.add_child(col)
	var pl: Dictionary = _v["places"]
	col.add_child(RSBStyle.title("Финиш! Победа: %s" % RSBData.HORSES[pl["first"]], RSBStyle.H1))
	var seconds: Array = pl["second"].map(func(h): return RSBData.HORSES[h])
	var thirds: Array = pl["third"].map(func(h): return RSBData.HORSES[h])
	var tie := " (ничья — все вторые и третьи)" if seconds.size() >= 2 else ""
	col.add_child(RSBStyle.label("2-е место: %s%s · 3-е: %s" % [", ".join(seconds), tie, ", ".join(thirds)], RSBStyle.CAP, RSBStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var res: Dictionary = _v["result"]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	for hd in ["Игрок", "Выиграл", "Проиграл", "В кассе"]:
		grid.add_child(RSBStyle.label(hd, RSBStyle.CAP, RSBStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	for s in _v["players"].size():
		var r: Dictionary = res.get(s, res.get(str(s), {}))
		grid.add_child(RSBStyle.label(_name(s), RSBStyle.CAP, RSBStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		grid.add_child(RSBStyle.label("+$%d" % (int(r.get("won", 0)) + int(r.get("snake", 0))), RSBStyle.CAP, RSBStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		grid.add_child(RSBStyle.label("−$%d" % int(r.get("lost", 0)), RSBStyle.CAP, RSBStyle.RED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		grid.add_child(RSBStyle.label(RSBStyle.money(_v["money"][s]) + ("  +$6 утешительный" if r.get("comeback", false) else ""), RSBStyle.CAP, RSBStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	col.add_child(grid)
	var mine: Dictionary = res.get(_seat(), res.get(str(_seat()), {}))
	var lines: Array = mine.get("lines", [])
	if not lines.is_empty():
		col.add_child(RSBStyle.label("Ваши ставки:", RSBStyle.CAP, RSBStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		var txt := RichTextLabel.new()
		txt.bbcode_enabled = true
		txt.fit_content = true
		txt.add_theme_font_size_override("normal_font_size", 13)
		for l in lines.slice(0, 8):
			var c := "#1f5c36" if l["win"] else "#c8312b"
			txt.append_text("[color=%s]%s[/color]  «%d» — %s\n" % [c, ("+$%d" % l["delta"]) if l["win"] else ("−$%d" % -int(l["delta"])), l["v"], l["title"]])
		col.add_child(txt)
	var row := RSBStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var next := RSBStyle.primary("Дальше" if _v["race_no"] < RSBData.RACES else "К итогам", RSBStyle.BODY, 180)
	next.pressed.connect(func():
		next.disabled = true
		Net.send_action("next"))
	row.add_child(next)
	_auto_label = RSBStyle.label("", RSBStyle.CAP, RSBStyle.MUTED)
	row.add_child(_auto_label)
	row.add_child(ReadyDots.make(_v["players"], ReadyDots.pressed_next(_v)))
	col.add_child(row)


func _vip_panel() -> void:
	var s := _seat()
	var hand: Array = _v["vip_hand"][s]
	_dim()
	var col := RSBStyle.vbox(10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(col)
	var head := RSBStyle.title("VIP-ложа", RSBStyle.H1)
	col.add_child(head)
	if hand.is_empty() or hand[0] < 0:
		var waiting := []
		for k in _v["players"].size():
			if not _v["vip_hand"][k].is_empty():
				waiting.append(_name(k))
		col.add_child(RSBStyle.label("Вы выбрали карту. Ждём: %s" % ", ".join(waiting), RSBStyle.BODY, RSBStyle.CREAM, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
		return
	var who := ("Выбирает %s: " % _name(s)) if _hotseat() else ""
	col.add_child(RSBStyle.label(who + "перетащите карту в свою ложу или дважды кликните — вторая уйдёт в сброс.", RSBStyle.BODY, RSBStyle.CREAM, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	# карты — общая механика карт сборника (K12TableCard)
	var area := Control.new()
	area.custom_minimum_size = Vector2(640, 330)
	area.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(area)
	var zone := Panel.new()
	zone.add_theme_stylebox_override("panel", RSBStyle.box(Color(RSBStyle.FELT, 0.85), 10, RSBStyle.GOLD, 3))
	zone.position = Vector2(400, 40)
	zone.size = Vector2(220, 260)
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(zone)
	var zl := RSBStyle.label("ВАША ЛОЖА", RSBStyle.BODY, RSBStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER, "title")
	zl.position = Vector2(0, 112)
	zl.size = Vector2(220, 30)
	zone.add_child(zl)
	for i in hand.size():
		var c := K12TableCard.new("vip_%d" % hand[i], true, RSBVipFace.new(int(hand[i])), RSBVipFace.SIZE)
		c.back_drawer = RSBVipFace.draw_back
		c.draggable = true
		area.add_child(c)
		var home := Vector2(100 + i * 175, 170)
		c.place(home, (i - 0.5) * 0.08, 1.2)
		c.base_scale = 1.2
		var ii: int = i
		c.hovered.connect(func(card: K12TableCard, on: bool):
			if not card.dragging:
				card.move_to(card.center(), 0.0 if on else (ii - 0.5) * 0.08, 1.3 if on else 1.2, 0.12))
		c.double_clicked.connect(func(_card): _pick_vip(ii, c, zone))
		c.dropped.connect(func(card: K12TableCard, at: Vector2):
			if Rect2(zone.position, zone.size).grow(30).has_point(at):
				_pick_vip(ii, card, zone)
			else:
				card.move_to(home, (ii - 0.5) * 0.08, 1.2, 0.25)
				Sfx.play("card_slide", -8))
		c.clicked.connect(func(card: K12TableCard): card.move_to(home, (ii - 0.5) * 0.08, 1.2, 0.2))


func _pick_vip(i: int, card: K12TableCard, zone: Control) -> void:
	card.draggable = false
	card.move_to(zone.position + zone.size / 2, 0.0, 1.0, 0.25)
	Sfx.play("card_place", -2)
	var arg := {"i": i}
	if _hotseat():
		arg["as"] = _as
	Net.send_action("rsb_vip", arg)


func _game_over_panel() -> void:
	_dim()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var p := RSBStyle.panel()
	p.custom_minimum_size = Vector2(520, 0)
	center.add_child(p)
	var col := RSBStyle.vbox(10)
	p.add_child(col)
	var names: Array = _v["winners"].map(func(s): return _name(s))
	col.add_child(RSBStyle.title("Большой куш!", RSBStyle.H1))
	col.add_child(RSBStyle.label(("Победитель: %s" if names.size() == 1 else "Делят победу: %s") % ", ".join(names), RSBStyle.BODY, RSBStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "title"))
	var order := range(_v["players"].size())
	order.sort_custom(func(a, b): return _v["money"][a] > _v["money"][b])
	for k in order.size():
		var s: int = order[k]
		var row := RSBStyle.hbox(10)
		row.add_child(RSBStyle.label("%d." % (k + 1), RSBStyle.BODY, RSBStyle.MUTED))
		row.add_child(RSBStyle.pic(RSBStyle.token_tex(s, 5, ""), Vector2(24, 24)))
		var nl := RSBStyle.label(_name(s), RSBStyle.BODY, RSBStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold")
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		row.add_child(RSBStyle.label(RSBStyle.money(_v["money"][s]), RSBStyle.BODY, RSBStyle.MONEY, HORIZONTAL_ALIGNMENT_RIGHT, "title"))
		col.add_child(row)
	if not _celebrated:
		_celebrated = true
		Sfx.victory()
	var brow := RSBStyle.hbox(10)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	if Net.is_host():
		var again := RSBStyle.primary("Новая партия", RSBStyle.BODY)
		again.pressed.connect(Net.end_game)
		brow.add_child(again)
		var back := RSBStyle.button("К выбору игры" if Net.is_party() else "В меню", RSBStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
		brow.add_child(back)
	else:
		var leave := RSBStyle.button("Покинуть пати", RSBStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		brow.add_child(leave)
	col.add_child(brow)


func _process(_delta: float) -> void:
	if not _ghosts.is_empty():
		_expire_ghosts()
	if _auto_label != null and is_instance_valid(_auto_label):
		var left := maxi(0, (_auto_deadline - Time.get_ticks_msec()) / 1000)
		var waiting: Array = _v.get("waiting", [])
		_auto_label.text = ("ждём: %s · " % ", ".join(waiting) if not waiting.is_empty() else "") + "сами через %d с" % left


## Жетон, который несут над столом: под ним тень (lift 1 — высоко, 0 — лежит).
class ChipSprite:
	extends Control
	var texture: Texture2D
	var lift := 1.0:
		set(v):
			lift = v
			queue_redraw()

	func _init(t: Texture2D) -> void:
		texture = t
		size = Vector2(54, 54)
		pivot_offset = size / 2
		scale = Vector2(1.15, 1.15)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2
		if lift > 0.01:
			var off := Vector2(7, 11) * lift
			draw_circle(c + off, size.x * 0.52, Color(0, 0, 0, 0.12 * lift))
			draw_circle(c + off, size.x * 0.46, Color(0, 0, 0, 0.25 * lift))
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)


## Жетон в лотке: нажали — начинаем перетаскивание (короткий клик — выбрать жетон).
class TokenChip:
	extends Control
	signal grabbed(at: Vector2)
	var texture: Texture2D
	var used := false
	var selected := false
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(52, 52)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			queue_redraw())

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_ARROW if used else Control.CURSOR_DRAG

	func _gui_input(event: InputEvent) -> void:
		if used:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			grabbed.emit(event.global_position)
			accept_event()

	## Контейнер может вытянуть слот по высоте; сам жетон всегда остаётся круглым.
	func token_rect() -> Rect2:
		var diameter := maxf(0.0, minf(size.x, size.y) - 4.0)
		var extent := Vector2.ONE * diameter
		return Rect2((size - extent) * 0.5, extent)

	func _draw() -> void:
		var r := token_rect()
		var radius := r.size.x * 0.5
		if used:
			draw_circle(r.get_center(), radius, Color(0, 0, 0, 0.12))
			draw_texture_rect(texture, r, false, Color(1, 1, 1, 0.25))
			return
		if selected:
			draw_circle(r.get_center(), radius + 3.0, RSBStyle.GOLD)
		draw_circle(r.get_center() + Vector2(1.5, 2.5), radius, Color(0, 0, 0, 0.3))
		var lift := Vector2(0, -3) if _hover or selected else Vector2.ZERO
		draw_texture_rect(texture, Rect2(r.position + lift, r.size), false)
