extends Control
## Стол «Алольского атлета»: слева — трасса с фишками гонщиков, справа — игроки и очки, панель действия
## (драфт / выбор гонщика / бросок / вопросы умений) и журнал гонки.
## Наведение на гонщика (фишку, карту, строку игрока) — крупная карта с умением.

var app: Node

const PerudoDieView := preload("res://games/perudo/ui/d6_view.gd")

var _v := {}
var _me := 0
var _track: TextureRect
var _tokens: Control  # фишки поверх трассы
var _side: VBoxContainer
var _score_box: VBoxContainer
var _panel: PanelContainer
var _panel_key := ""
var _log: RichTextLabel
var _preview: TextureRect
var _die: PerudoDie
var _rolling := false
var _last_roll_seen := -1
var _fork_choice := {}
var _celebrated := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(AAStyle.Backdrop.new())
	var tp := AAStyle.panel(6)
	tp.name = "TrackPanel"
	add_child(tp)
	_track = TextureRect.new()
	_track.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_track.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.add_child(_track)
	_tokens = Control.new()
	_tokens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tokens.draw.connect(_draw_tokens)
	add_child(_tokens)

	_side = AAStyle.vbox(8)
	add_child(_side)
	var top := AAStyle.hbox(6)
	top.alignment = BoxContainer.ALIGNMENT_END
	var rules := AAStyle.button("Правила", AAStyle.CAP)
	rules.pressed.connect(func(): app.show_rules())
	top.add_child(rules)
	var settings := AAStyle.button("Настройки", AAStyle.CAP)
	settings.pressed.connect(func(): app.show_settings())
	top.add_child(settings)
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = AAStyle.button("Завершить партию", AAStyle.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся в лобби игры, пати сохранится.", Net.end_game)
	elif Net.is_party():
		leave = AAStyle.button("Покинуть пати", AAStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		leave = AAStyle.button("Выйти", AAStyle.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	top.add_child(leave)
	_side.add_child(top)
	var sp := AAStyle.panel(10)
	_score_box = AAStyle.vbox(4)
	sp.add_child(_score_box)
	_side.add_child(sp)
	_panel = AAStyle.panel(12)
	_side.add_child(_panel)
	var lp := AAStyle.panel(8)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_font_size_override("bold_font_size", 12)
	_log.add_theme_color_override("default_color", AAStyle.INK)
	lp.add_child(_log)
	_side.add_child(lp)

	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_preview.z_index = 50
	add_child(_preview)

	add_child(TurnClock.top_center(6))
	var chat := K12ChatPanel.new()
	AAStyle.restyle_chat(chat)
	add_child(chat)
	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := AAStyle.label(t, AAStyle.CAP, AAStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
		b.add_theme_stylebox_override("normal", AAStyle.box(AAStyle.PAPER, 14, AAStyle.INK, 3, 0.25))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 220
		return b, Vector2(-260, 70))
	resized.connect(_layout)
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state.call_deferred(Net.view)


# --- Роли ---------------------------------------------------------------------------

func _hotseat() -> bool:
	return _v.get("hotseat", false) or Net.mode == "offline"


func _name(s: int) -> String:
	return _v["players"][s]["name"] if s >= 0 and s < _v["players"].size() else "?"


func _color(s: int) -> Color:
	return Net.color_of(int(_v["players"][s].get("color", s)))


## Кто действует за этим экраном (на одном компьютере — тот, от кого ждут хода).
func _actor() -> int:
	if not _hotseat():
		return int(_v["you"])
	match _v["phase"]:
		"draft":
			return int(_v["drafter"])
		"pick":
			var p: Array = _v["picks"]
			for s in p.size():
				if p[s] == "":
					return s
		"race":
			var pr: Dictionary = _v["prompt"]
			if not pr.is_empty():
				return int(pr["seat"])
			return int(_v["current"])
	return int(_v["you"])


func _send(kind: String, arg: Dictionary = {}) -> void:
	if _hotseat():
		arg["as"] = _actor()
	Net.send_action(kind, arg)


# --- Раскладка ----------------------------------------------------------------------

func _layout() -> void:
	var side_w := clampf(size.x * 0.36, 380, 470)
	var tp := get_node("TrackPanel") as Control
	var h := size.y - 24
	var w := minf(size.x - side_w - 36, h * 1.06)
	tp.position = Vector2(12, 12)
	tp.size = Vector2(w, h)
	_tokens.position = tp.position + Vector2(6, 6)
	_tokens.size = tp.size - Vector2(12, 12)
	_side.position = Vector2(size.x - side_w - 12, 8)
	_side.size = Vector2(side_w, size.y - 70)
	_tokens.queue_redraw()


## Прямоугольник картинки трассы внутри панели (с учётом «вписать с сохранением пропорций»).
func _img_rect() -> Rect2:
	var t := _track.texture
	if t == null:
		return Rect2(Vector2.ZERO, _tokens.size)
	var a := float(t.get_width()) / t.get_height()
	var s := _tokens.size
	var w := minf(s.x, s.y * a)
	var hh := w / a
	return Rect2((s - Vector2(w, hh)) * 0.5, Vector2(w, hh))


func _node_pos(i: int) -> Vector2:
	var r := _img_rect()
	var nodes: Array = AATracks.DATA[_v["track"]]["nodes"]
	if i == -2:
		var f: Vector2 = AATracks.DATA[_v["track"]]["finish"]
		return r.position + f * r.size
	if i == -1:
		var n0: Dictionary = nodes[0]
		var n1: Dictionary = nodes[1]
		var p0 := Vector2(n0["x"], n0["y"])
		var p1 := Vector2(n1["x"], n1["y"])
		return r.position + (p0 - (p1 - p0)) * r.size
	var n: Dictionary = nodes[i]
	return r.position + Vector2(n["x"], n["y"]) * r.size


func _draw_tokens() -> void:
	if _v.is_empty() or _v["racers"].is_empty() or not _v["phase"] in ["race", "race_result", "game_over"]:
		return
	var racers: Array = _v["racers"]
	var by_pos := {}
	for s in racers.size():
		if racers[s]["out"]:
			continue
		var p := int(racers[s]["pos"])
		if not by_pos.has(p):
			by_pos[p] = []
		by_pos[p].append(s)
	var cell := _img_rect().size.x * 0.075
	var rad := cell * 0.38
	for p in by_pos:
		var list: Array = by_pos[p]
		var c := _node_pos(int(p))
		for k in list.size():
			var s: int = list[k]
			var off := Vector2.ZERO
			if list.size() > 1:
				var a := TAU * k / list.size() - PI / 2
				off = Vector2(cos(a), sin(a)) * rad * 0.75
			var at := c + off
			var col := _color(s)
			var cur: bool = s == int(_v["current"]) and _v["phase"] == "race"
			_tokens.draw_circle(at, rad + (5 if cur else 3), AAStyle.ACCENT if cur else Color.BLACK)
			_tokens.draw_circle(at, rad + 1, col)
			var tex := AAStyle.tex("tokens/" + str(racers[s]["id"]))
			if tex:
				_tokens.draw_texture_rect(tex, Rect2(at - Vector2(rad, rad) * 0.95, Vector2(rad, rad) * 1.9), false)
			if racers[s]["tripped"]:
				var f := AAStyle.font("bold")
				_tokens.draw_string(f, at + Vector2(-rad, -rad - 2), "Zz", HORIZONTAL_ALIGNMENT_LEFT, -1, int(rad * 0.7), Color.WHITE)


# --- Состояние ----------------------------------------------------------------------

func _on_state(v: Dictionary) -> void:
	var prev := _v
	_v = v
	_me = _actor()
	var tr := str(v.get("track", "mele"))
	_track.texture = AAStyle.tex("tracks/" + AAData.TRACKS[tr]["img"])
	_update_scores()
	_update_log()
	var key := "%s/%d/%s/%s/%d/%s/%d/%s" % [v["phase"], v["race_no"], str(v["picks"]), str(v["prompt"]), int(v["current"]), str(v["stage"]), _me, str(v["line"])]
	if key != _panel_key:
		_panel_key = key
		_build_panel()
	var lr: Dictionary = v.get("last_roll", {})
	if not lr.is_empty() and int(v["turn_no"]) * 10 + int(lr.get("v", 0)) != _last_roll_seen:
		_last_roll_seen = int(v["turn_no"]) * 10 + int(lr.get("v", 0))
		if _die and is_instance_valid(_die):
			_die.value = int(lr["v"])
	if prev.get("turn_no", -1) != v.get("turn_no", -1):
		Sfx.play("card_place", -10)
	if v["phase"] == "game_over" and not _celebrated:
		_celebrated = true
		Sfx.victory()
	_layout.call_deferred()


func _update_scores() -> void:
	AAStyle.clear(_score_box)
	var head := AAStyle.hbox(6)
	var title := "Драфт гонщиков" if _v["phase"] == "draft" else "Гонка %d из 4 · %s" % [int(_v["race_no"]) + 1, AAData.TRACKS[_v["track"]]["name"]]
	head.add_child(AAStyle.label(title, AAStyle.BODY, AAStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	_score_box.add_child(head)
	for s in _v["players"].size():
		var row := AAStyle.hbox(6)
		var tag := PlayerTag.make_seat(_v["players"], s, int(_v["you"]), AAStyle.CAP, AAStyle.INK, "")
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tag)
		var racers: Array = _v["racers"]
		if _v["phase"] in ["race", "race_result", "game_over"] and s < racers.size():
			var rid := str(racers[s]["id"])
			var b := AAStyle.button(AAData.racer(rid).get("name", rid), AAStyle.CAP)
			b.focus_mode = Control.FOCUS_NONE
			b.mouse_entered.connect(func(): _show_card(rid, b))
			b.mouse_exited.connect(func(): _preview.visible = false)
			if str(racers[s]["power"]) != rid:
				b.tooltip_text = "Умение: " + AAData.racer(str(racers[s]["power"])).get("name", "")
			row.add_child(b)
			var st := ""
			if int(racers[s]["pos"]) == -2:
				st = "🏁 %d-е" % (int((_v["finished"] as Array).find(s)) + 1)
			elif racers[s]["out"]:
				st = "выбыл"
			elif racers[s]["tripped"]:
				st = "обморок"
			else:
				st = "до финиша %d" % int(racers[s]["dist"])
			row.add_child(AAStyle.label(st, AAStyle.CAP, AAStyle.MUTED))
		row.add_child(AAStyle.label("★ %d" % int(_v["scores"][s]), AAStyle.BODY, AAStyle.INK, HORIZONTAL_ALIGNMENT_RIGHT, true))
		_score_box.add_child(row)


func _update_log() -> void:
	var lines := []
	for e in (_v["log"] as Array).slice(-40):
		var s := int(e["seat"])
		if s >= 0 and s < _v["players"].size():
			lines.append("[color=#%s]●[/color] %s" % [_color(s).to_html(false), str(e["text"])])
		else:
			lines.append("[b]%s[/b]" % str(e["text"]))
	_log.text = "\n".join(lines)


func _show_card(id: String, near: Control) -> void:
	_preview.texture = AAStyle.tex("cards/" + id)
	var h := minf(size.y * 0.6, 420.0)
	_preview.size = Vector2(h * 480.0 / 672.0, h)
	var r := near.get_global_rect()
	_preview.position = Vector2(clampf(r.position.x - _preview.size.x - 12, 8, size.x - _preview.size.x - 8), clampf(r.position.y - h * 0.3, 8, size.y - h - 8))
	_preview.visible = true


# --- Панель действия -------------------------------------------------------------------

func _line(t: String, bold: bool = false, color: Color = AAStyle.INK) -> Label:
	var l := AAStyle.label(t, AAStyle.BODY if bold else AAStyle.CAP, color, HORIZONTAL_ALIGNMENT_LEFT, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	return l


## Ряд карт-гонщиков: щелчок — on_pick(id).
func _cards(ids: Array, on_pick: Callable, enabled: bool) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for id in ids:
		var tr := TextureRect.new()
		tr.texture = AAStyle.tex("cards/" + str(id)) if str(id) != "?" else AAStyle.tex("cards/back")
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(70, 98)
		var cid := str(id)
		if cid != "?":
			tr.mouse_entered.connect(func(): _show_card(cid, tr))
			tr.mouse_exited.connect(func(): _preview.visible = false)
		if enabled and cid != "?":
			tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			tr.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_preview.visible = false
					Sfx.play("card_place", -6)
					on_pick.call(cid))
		flow.add_child(tr)
	return flow


func _build_panel() -> void:
	AAStyle.clear(_panel)
	_die = null
	var col := AAStyle.vbox(8)
	_panel.add_child(col)
	var actor := _actor()
	var who := ("(за %s) " % _name(actor)) if _hotseat() else ""
	match str(_v["phase"]):
		"draft":
			var d := int(_v["drafter"])
			if d == actor:
				col.add_child(_line(who + "Ваш выбор: возьмите гонщика в команду", true))
				col.add_child(_cards(_v["line"], func(id): _send("aa_draft", {"id": id}), true))
			else:
				col.add_child(_line("Выбирает %s…" % _name(d), true))
				col.add_child(_cards(_v["line"], func(_id): pass, false))
			col.add_child(_line("Ваша команда:"))
			col.add_child(_cards(_v["teams"][actor], func(_id): pass, false))
		"pick":
			if str(_v["picks"][actor]) == "":
				col.add_child(_line(who + "Кто бежит гонку «%s»?" % AAData.TRACKS[_v["track"]]["name"], true))
				var forks: Array = _v["forks"]
				if not forks.is_empty():
					var fr := AAStyle.hbox(6)
					fr.add_child(_line("На развилке:"))
					for opt in [["0", "Длинная дорога"], ["1", "Короткий путь"]]:
						var b := AAStyle.button(opt[1], AAStyle.CAP)
						UISel.pick(b, str(_fork_choice.get("route", "0")) == opt[0])
						var o: String = opt[0]
						b.pressed.connect(func():
							_fork_choice["route"] = o
							_panel_key = ""
							_build_panel())
						fr.add_child(b)
					col.add_child(fr)
				var left: Array = (_v["teams"][actor] as Array).filter(func(x): return not x in _v["used"][actor])
				col.add_child(_cards(left, func(id): _send("aa_pick", {"id": id, "forks": _fork_payload()}), true))
			else:
				col.add_child(_line("Ждём выбора соперников…", true))
		"race":
			_build_race(col, who, actor)
		"race_result":
			var h: Array = _v["history"]
			var last: Dictionary = h[-1] if not h.is_empty() else {}
			var pl: Array = last.get("places", [])
			col.add_child(_line("Гонка окончена!", true))
			for k in pl.size():
				col.add_child(_line("%d-е место: %s (%s)" % [k + 1, _name(int(pl[k])), AAData.racer(str(last["racers"][int(pl[k])]))["name"]]))
			var nb := AAStyle.primary("Дальше", AAStyle.BODY, 160)
			nb.pressed.connect(func(): Net.send_action("next"))
			col.add_child(nb)
		"game_over":
			var w: Array = _v["winners"]
			col.add_child(AAStyle.label(("Победа: %s!" if w.size() == 1 else "Ничья: %s!") % ", ".join(w.map(func(s): return _name(int(s)))), AAStyle.H1, AAStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
			if Net.is_host():
				var again := AAStyle.primary("Новая партия", AAStyle.BODY, 180)
				again.pressed.connect(Net.end_game)
				col.add_child(again)


## Развилка: длинная дорога — первая ветка (обычно), короткий путь — вторая.
func _fork_payload() -> Dictionary:
	var out := {}
	var nodes: Array = AATracks.DATA[_v["track"]]["nodes"]
	for f in _v["forks"]:
		var nx: Array = nodes[int(f)]["next"]
		out[str(f)] = nx[mini(int(_fork_choice.get("route", "0")), nx.size() - 1)]
	return out


func _build_race(col: VBoxContainer, who: String, actor: int) -> void:
	var cur := int(_v["current"])
	var pr: Dictionary = _v["prompt"]
	var racers: Array = _v["racers"]
	var cur_name := str(AAData.racer(str(racers[cur]["id"])).get("name", "")) if cur < racers.size() else ""
	if not pr.is_empty() and str(pr.get("kind", "")) != "wait" and int(pr["seat"]) == actor:
		col.add_child(_line(who + str(pr.get("text", "Ваш выбор")) if str(pr.get("text", "")) != "" else who + "Выберите:", true))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for o in pr["options"]:
			var b := AAStyle.button(str(o["label"]), AAStyle.CAP)
			var val = o["v"]
			b.pressed.connect(func(): _send("aa_answer", {"v": val}))
			flow.add_child(b)
		col.add_child(flow)
		return
	if not pr.is_empty():
		col.add_child(_line("%s принимает решение…" % _name(int(pr["seat"])), true))
		return
	col.add_child(_line("Ходит %s — %s" % [_name(cur), cur_name], true))
	var row := AAStyle.hbox(12)
	_die = PerudoDieView.new(max(1, int(_v["last_roll"].get("v", 1))), 54)
	row.add_child(_die)
	if str(_v["stage"]) == "roll" and cur == actor:
		var rb := AAStyle.primary(who + "Бросить кубик", AAStyle.BODY, 200)
		rb.pressed.connect(func():
			rb.disabled = true
			_tumble()
			_send("aa_roll"))
		row.add_child(rb)
	elif str(_v["stage"]) == "roll":
		row.add_child(_line("бросает кубик…"))
	col.add_child(row)


func _tumble() -> void:
	if _die == null or not is_instance_valid(_die):
		return
	Sfx.play("die_throw", -4)
	var d := _die
	var t := create_tween()
	t.tween_method(func(k: float): d.value = (int(k * 29) % 6) + 1, 0.0, 1.0, 0.5)
	t.parallel().tween_property(d, "rotation", TAU * 2, 0.5).from(0.0)
