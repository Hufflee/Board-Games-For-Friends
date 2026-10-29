extends Control
## Стол «Тип Топ»: слева — планшет (шкала и жетоны единорога / какашек) и игроки, в центре — карта темы,
## ответы-«пузыри» и дорожка выкладки, справа — свой номер и поле ответа.
## Ответы — общие карты сборника (K12TableCard): капитан перетаскивает их на дорожку или кликает дважды.

var app: Node

var _v := {}
var _me := 0
var _as := 0  # на одном компьютере — за кого действуем
var _top: TopBar
var _tokens: Control
var _players_box: VBoxContainer
var _theme_panel: PanelContainer
var _theme_key := ""
var _right: VBoxContainer
var _right_key := ""
var _cards_layer: Control
var _track: Control
var _cards := {}  # место -> K12TableCard
var _arr: Array = []  # раскладка на планшете (у капитана — своя, до «Ответить»; у остальных — с хоста)
var _calls := {}  # эксперт: место -> номер, названный капитаном
var _selected := -1  # эксперт: карта, которой капитан называет номер
var _shown := {}  # места, у которых номер уже открыт на экране
var _revealing := false  # идёт поочерёдное открытие номеров
var _hidden_mistakes := 0  # ошибки, которые ещё не открыты (жетоны пока у единорога)
var _answer_edit: LineEdit
var _overlay: Control
var _overlay_key := ""
var _auto_label: Label
var _auto_deadline := 0
var _celebrated := false
var _round := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(TTStyle.Rays.new())

	_top = TopBar.make(self, "Тип Топ 18+" if TTStyle.adult else "Тип Топ", func(t, z): return TTStyle.button(t, z), null, TTStyle.WHITE, TTStyle.font("bold"))
	# монетка — под панелью игроков, у левого края (панель растёт с числом игроков — гнездо едет за ней)
	_top.coin_at = func() -> Vector2:
		var panel := _players_box.get_parent() as Control if _players_box else null
		if panel == null:
			return Vector2(-9999, -9999)
		var r := panel.get_global_rect()
		return Vector2(r.position.x + 30.0, r.end.y + 38.0)
	var buttons := _top.actions
	var rules := TTStyle.button("Правила", TTStyle.CAP)
	rules.pressed.connect(func(): app.show_rules())
	buttons.add_child(rules)
	var settings := TTStyle.button("Настройки", TTStyle.CAP)
	settings.pressed.connect(func(): app.show_settings())
	buttons.add_child(settings)
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = TTStyle.button("Завершить партию", TTStyle.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся к выбору игры, пати сохранится.", Net.return_to_party)
	elif Net.is_party():
		leave = TTStyle.button("Покинуть пати", TTStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave = TTStyle.button("Выйти", TTStyle.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	buttons.add_child(leave)

	# планшет
	var board := TTStyle.bubble(10)
	board.name = "Board"
	var bv := TTStyle.vbox(6)
	board.add_child(bv)
	var g := TTStyle.Gauge.new()
	g.custom_minimum_size = Vector2(250, 48)
	bv.add_child(g)
	_tokens = Control.new()
	_tokens.custom_minimum_size = Vector2(250, 92)
	_tokens.draw.connect(_draw_tokens)
	bv.add_child(_tokens)
	add_child(board)
	var plist := TTStyle.bubble(10)
	plist.name = "Players"
	_players_box = TTStyle.vbox(2)
	plist.add_child(_players_box)
	add_child(plist)

	_theme_panel = TTStyle.bubble(14)
	add_child(_theme_panel)
	_track = Control.new()
	_track.draw.connect(_draw_track)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_track)
	_cards_layer = Control.new()
	_cards_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards_layer)

	_right = TTStyle.vbox(10)
	add_child(_right)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	# реплики и сообщения чата — всплывающим окошком
	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := TTStyle.label(t, TTStyle.CAP, TTStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "bold")
		b.add_theme_stylebox_override("normal", TTStyle.box(TTStyle.WHITE, 14, TTStyle.INK, 3, 0.3))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 240
		return b, Vector2(-270, 300))

	resized.connect(_layout)
	_layout()
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state(Net.view)


func _layout() -> void:
	var w := size.x
	var h := size.y
	(get_node("Board") as Control).position = Vector2(14, 56)
	(get_node("Board") as Control).size = Vector2(278, 0)
	(get_node("Players") as Control).position = Vector2(14, 244)
	(get_node("Players") as Control).size = Vector2(278, 0)
	_theme_panel.position = Vector2(308, 56)
	_theme_panel.size = Vector2(w - 308 - 300, 0)
	_track.position = Vector2(308, h - 178)
	_track.size = Vector2(w - 308 - 300, 150)
	_cards_layer.position = Vector2.ZERO
	_cards_layer.size = size
	_right.position = Vector2(w - 284, 56)
	_right.size = Vector2(270, 0)
	_overlay.size = size
	_layout_cards()


# --- Роли ----------------------------------------------------------------------------

func _hotseat() -> bool:
	return _v.get("hotseat", false)


func _seat() -> int:
	return _as if _hotseat() else _me


func _name(s: int) -> String:
	return _v["players"][s]["name"]


func _color(s: int) -> Color:
	return Net.color_of(int(_v["players"][s].get("color", 0)))


func _am_captain() -> bool:
	return _hotseat() or _me == int(_v["captain"])


func _send(kind: String, arg: Dictionary = {}) -> void:
	if _hotseat():
		arg["as"] = _seat()
	Net.send_action(kind, arg)


# --- Состояние --------------------------------------------------------------------------

func _on_state(v: Dictionary) -> void:
	var prev_phase: String = _v.get("phase", "")
	var prev_poops: int = _v.get("poops", 0)
	_v = v
	_me = v["you"]
	TTStyle.adult = v["adult"]
	_auto_deadline = Time.get_ticks_msec() + int(v.get("auto_in", 0)) * 1000
	var phase: String = v["phase"]
	if int(v["round_no"]) != _round:
		_round = int(v["round_no"])
		_arr = []
		_calls = {}
		_selected = -1
		_shown = {}
		_revealing = false
		_hidden_mistakes = 0
		for c in _cards.values():
			(c as Node).queue_free()
		_cards.clear()
		Sfx.play("shuffle", -6)
	# на одном компьютере — за кого действуем по фазе
	if _hotseat():
		match phase:
			"theme", "order":
				_as = int(v["captain"])
			"answer":
				if (v["answered"] as Array).has(_as) or _as == int(v["captain"]):
					for s in v["players"].size():
						if s != int(v["captain"]) and not (v["answered"] as Array).has(s):
							_as = s
							break
			"guess":
				_as = (int(v["captain"]) + 1) % v["players"].size()
	if phase == "order":
		# у капитана раскладка своя (сервер её только хранит); остальные видят её вживую
		if not _am_captain() or _arr.is_empty():
			_arr = (v["arrangement"] as Array).duplicate()
			_calls = {}
			for k in v["calls"]:
				_calls[int(k)] = int(v["calls"][k])
	elif prev_phase == "order" and not (v["log"] as Array).is_empty():
		_start_reveal()
	elif int(v["poops"]) > prev_poops and not _revealing:
		Sfx.play("card_shove", 0)
	_top.info.text = "Раунд %d из %d" % [v["round_no"], v["rounds"]]
	_tokens.queue_redraw()
	_update_players()
	var tkey := "%s/%d/%d" % [phase, v["round_no"], v["theme"]]
	if tkey != _theme_key:
		_theme_key = tkey
		_update_theme()
	_sync_cards()
	var rkey := "%s/%d/%d/%s/%s/%s/%d" % [phase, v["round_no"], _seat(), str(v["answered"]), str(_arr), str(_calls), _selected]
	if rkey != _right_key:
		_right_key = rkey
		_update_right()
	var okey := "%s/%d/%s" % [phase, v["round_no"], ",".join(v.get("waiting", []))]
	if okey != _overlay_key and not _revealing:
		_overlay_key = okey
		_update_overlay()
	_track.queue_redraw()


func _draw_tokens() -> void:
	var u := TTStyle.tex("token_unicorn")
	var p := TTStyle.tex("token_poop")
	var f := TTStyle.font("bold")
	_tokens.draw_string(f, Vector2(0, 16), "Зона единорога", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TTStyle.INK)
	_tokens.draw_string(f, Vector2(0, 62), "Зона какашек", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TTStyle.INK)
	# пока номера открываются по очереди, жетоны переходят к какашкам по одному
	for i in int(_v.get("unicorns", 0)) + _hidden_mistakes:
		_tokens.draw_texture_rect(u, Rect2(Vector2(110 + i * 18, 0), Vector2(30, 30)), false)
	for i in int(_v.get("poops", 0)) - _hidden_mistakes:
		_tokens.draw_texture_rect(p, Rect2(Vector2(110 + i * 18, 46), Vector2(30, 30)), false)


func _update_players() -> void:
	TTStyle.clear(_players_box)
	_players_box.add_child(TTStyle.label("ИГРОКИ", TTStyle.CAP, Color(TTStyle.INK, 0.6), HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	for s in _v["players"].size():
		var row := TTStyle.hbox(6)
		var tag := PlayerTag.make_seat(_v["players"], s, _me, 15, TTStyle.INK, "  ★" if s == int(_v["captain"]) else "")
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tag)
		var st := ""
		if _v["phase"] == "answer":
			st = "капитан" if s == int(_v["captain"]) else ("✓" if (_v["answered"] as Array).has(s) else "пишет…")
		row.add_child(TTStyle.label(st, TTStyle.CAP, Color(TTStyle.INK, 0.6)))
		if _hotseat() and _v["phase"] == "answer" and s != int(_v["captain"]) and not (_v["answered"] as Array).has(s):
			var b := TTStyle.button("за него", TTStyle.CAP)
			UISel.pick(b, s == _as)
			var ss: int = s
			b.pressed.connect(func():
				_as = ss
				_right_key = ""
				_on_state(_v))
			row.add_child(b)
		_players_box.add_child(row)


# --- Карта темы ---------------------------------------------------------------------

func _update_theme() -> void:
	TTStyle.clear(_theme_panel)
	var col := TTStyle.vbox(8)
	_theme_panel.add_child(col)
	var card: Array = _v["card"]
	if _v["phase"] == "theme":
		if _am_captain():
			col.add_child(TTStyle.label("Вы капитан — выберите тему:" if not _hotseat() else "Капитан (%s) выбирает тему:" % _name(_v["captain"]), TTStyle.CAP, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
			for i in 2:
				var b := Button.new()
				b.custom_minimum_size = Vector2(0, 70)
				b.add_theme_stylebox_override("normal", TTStyle.box(Color("f4f4f4"), 12, TTStyle.INK, 3, 0.0))
				b.add_theme_stylebox_override("hover", TTStyle.box(TTStyle.accent().lightened(0.6), 12, TTStyle.INK, 3, 0.0))
				b.add_theme_stylebox_override("pressed", TTStyle.box(TTStyle.accent(), 12, TTStyle.INK, 3, 0.0))
				b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				var rt := _theme_text(card[i], 14)
				rt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				rt.offset_left = 12
				rt.offset_right = -12
				rt.offset_top = 8
				rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(rt)
				var ii: int = i
				b.pressed.connect(func(): _send("tt_theme", {"i": ii}))
				col.add_child(b)
		else:
			col.add_child(TTStyle.label("%s выбирает тему…" % _name(_v["captain"]), TTStyle.BODY, TTStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
		return
	col.add_child(_theme_text(card[int(_v["theme"])], 20))


func _theme_text(t: Array, fs: int) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.add_theme_font_override("normal_font", TTStyle.font("title"))
	rt.add_theme_font_size_override("normal_font_size", fs)
	rt.add_theme_color_override("default_color", TTStyle.INK)
	rt.text = TTStyle.theme_bbcode(t)
	return rt


# --- Ответы-карты и дорожка -------------------------------------------------------------

func _sync_cards() -> void:
	var phase: String = _v["phase"]
	if not phase in ["order", "guess", "round_result", "game_over"]:
		return
	var answers: Dictionary = _v["answers"]
	var editable: bool = phase == "order" and _am_captain()
	for key in answers:
		var s := int(key)
		if not _cards.has(s):
			var face := TTAnswerFace.new(_name(s), _color(s), str(answers[key]), -1)
			var c := K12TableCard.new("tt_%d" % s, true, face, TTAnswerFace.SIZE)
			_cards_layer.add_child(c)
			c.place(_track.position + Vector2(_track.size.x / 2.0, -60))
			_cards[s] = c
			var ss := s
			c.double_clicked.connect(func(_c): _toggle_on_board(ss))
			c.clicked.connect(func(_c): _select(ss))
			c.dropped.connect(func(_card: K12TableCard, at: Vector2): _drop(ss, at))
		var c2: K12TableCard = _cards[s]
		var f := c2.get_child(0) as TTAnswerFace
		var num: int = int(_v["numbers"].get(s, _v["numbers"].get(str(s), -1)))
		# номер — только когда до него дошло поочерёдное открытие (или после конца раунда)
		var show: bool = _shown.has(s) or (not _revealing and phase != "order" and (_v["placed"] as Array).has(s)) or (not _revealing and phase in ["round_result", "game_over"])
		if show and f.number < 0 and num > 0:
			f.number = num
		f.called = int(_calls.get(s, -1)) if _v["expert"] else -1
		f.selected = editable and s == _selected
		f.queue_redraw()
		c2.draggable = editable and (_v["to_place"] as Array).has(s)
	_layout_cards()


## Порядок карт на планшете: при раскладке — раскладка, после «Ответить» — порядок проверки.
func _board() -> Array:
	return _arr if _v["phase"] == "order" else (_v["placed"] as Array)


func _layout_cards() -> void:
	if _v.is_empty():
		return
	var board: Array = _board()
	var loose: Array = []
	for s in _cards:
		if not board.has(s):
			loose.append(s)
	loose.sort()
	# неразложенные ответы — сеткой посередине
	var area := Rect2(Vector2(308, 210), Vector2(size.x - 308 - 300, size.y - 210 - 190))
	var per_row := maxi(1, int(area.size.x / (TTAnswerFace.SIZE.x + 12)))
	for i in loose.size():
		var c: K12TableCard = _cards[loose[i]]
		if c.dragging:
			continue
		var col := i % per_row
		var row := i / per_row
		var n_in_row := mini(per_row, loose.size() - row * per_row)
		var x0 := area.position.x + (area.size.x - n_in_row * (TTAnswerFace.SIZE.x + 12)) / 2.0
		var p := Vector2(x0 + col * (TTAnswerFace.SIZE.x + 12) + TTAnswerFace.SIZE.x / 2.0, area.position.y + row * (TTAnswerFace.SIZE.y + 10) + TTAnswerFace.SIZE.y / 2.0)
		c.base_scale = 1.0
		c.move_to(p, 0.0, 1.0, 0.25)
	# на планшете — по порядку слева направо
	var sc := _board_scale()
	for i in board.size():
		var c: K12TableCard = _cards.get(int(board[i]))
		if c == null or c.dragging:
			continue
		c.base_scale = sc
		c.move_to(_slot_pos(i), 0.0, sc, 0.25)


func _board_scale() -> float:
	var k := maxi(1, maxi(_board().size(), (_v.get("to_place", []) as Array).size()))
	return minf(0.82, (_track.size.x - 20.0) / (k * (TTAnswerFace.SIZE.x + 8)))


func _slot_pos(i: int) -> Vector2:
	var sc := _board_scale()
	return _track.position + Vector2(14 + (i + 0.5) * (TTAnswerFace.SIZE.x + 8) * sc, _track.size.y / 2.0 + 8)


## Капитан бросил карту: на планшет — встаёт между соседями по горизонтали, мимо — убирается с планшета.
func _drop(s: int, at: Vector2) -> void:
	if _v["phase"] != "order" or not _am_captain():
		_layout_cards()
		return
	_arr.erase(s)
	if Rect2(_track.position, _track.size).grow(30).has_point(at):
		var idx := 0
		for i in _arr.size():
			if at.x > _slot_pos(i).x:
				idx = i + 1
		_arr.insert(idx, s)
		Sfx.play("card_place", -4)
	else:
		_calls.erase(s)
		Sfx.play("card_slide", -8)
	_push_arrangement()


func _toggle_on_board(s: int) -> void:
	if _v["phase"] != "order" or not _am_captain() or not (_v["to_place"] as Array).has(s):
		return
	if _arr.has(s):
		_arr.erase(s)
		_calls.erase(s)
	else:
		_arr.append(s)
	Sfx.play("card_place", -4)
	_push_arrangement()


## Эксперт: клик по карте на планшете — выбрать её и назвать номер справа.
func _select(s: int) -> void:
	if _v["phase"] == "order" and _am_captain() and _v["expert"] and _arr.has(s):
		_selected = -1 if _selected == s else s
		_on_state(_v)
	else:
		_layout_cards()


func _push_arrangement() -> void:
	var cm := {}
	for k in _calls:
		cm[k] = _calls[k]
	_send("tt_arrange", {"order": _arr.duplicate(), "calls": cm})
	_on_state(_v)


func _can_commit() -> bool:
	var need: Array = _v.get("to_place", [])
	if _arr.size() != need.size():
		return false
	if _v["expert"]:
		for s in _arr:
			if not _calls.has(s):
				return false
	return true


## После «Ответить»: номера открываются по очереди слева направо, жетоны уходят к какашкам по одному.
func _start_reveal() -> void:
	var log: Array = _v["log"]
	_revealing = true
	_shown = {}
	_hidden_mistakes = log.filter(func(e): return not e["ok"]).size()
	_selected = -1
	var t := create_tween()
	t.tween_interval(0.6)
	for e in log:
		var s: int = int(e["seat"])
		var ok: bool = e["ok"]
		var n: int = int(e["number"])
		t.tween_callback(func():
			_shown[s] = true
			if _cards.has(s):
				var f := (_cards[s] as K12TableCard).get_child(0) as TTAnswerFace
				f.number = n
				var pt := create_tween()
				pt.tween_property(f, "pop", 1.0, 0.12)
				pt.tween_property(f, "pop", 0.0, 0.25)
			Sfx.play("card_flip", -4)
			if not ok:
				_hidden_mistakes -= 1
				Sfx.play("card_shove", 0)
			_tokens.queue_redraw())
		t.tween_interval(1.0)
	t.tween_callback(func():
		_revealing = false
		_hidden_mistakes = 0
		_tokens.queue_redraw()
		_overlay_key = ""
		_on_state(_v))


func _draw_track() -> void:
	var r := Rect2(Vector2.ZERO, _track.size)
	_track.draw_style_box(TTStyle.box(Color(0, 0, 0, 0.22), 18, Color(1, 1, 1, 0.5), 3, 0.0), r)
	var f := TTStyle.font("title")
	var hint := "ПЛАНШЕТ: от меньшего номера к большему" if not _v.get("expert", false) else "ПЛАНШЕТ: разложите ответы и назовите номера"
	_track.draw_string(f, Vector2(14, 22), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	_track.draw_string(f, Vector2(r.size.x - 70, r.size.y - 10), "→", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.6))


# --- Правая колонка: свой номер, ответ, эксперт ------------------------------------------

func _update_right() -> void:
	# недописанный ответ переживает перестройку панели (её вызывают чужие ответы)
	var draft := ""
	var caret := 0
	var owner := get_viewport().gui_get_focus_owner()
	var continue_answer: bool = owner == null or owner == _answer_edit
	if is_instance_valid(_answer_edit):
		draft = _answer_edit.text
		caret = _answer_edit.caret_column
	TTStyle.clear(_right)
	_answer_edit = null
	var phase: String = _v["phase"]
	var s := _seat()
	var my_num: int = int(_v["numbers"].get(s, _v["numbers"].get(str(s), -1)))
	if phase in ["answer", "order", "guess"] and my_num > 0 and not (phase != "answer" and _hotseat()):
		_right.add_child(_number_card(my_num))
	match phase:
		"theme":
			_right.add_child(TTStyle.label("Сейчас раздадут номера…", TTStyle.CAP, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
		"answer":
			if s == int(_v["captain"]):
				var cl := TTStyle.label("Вы капитан: номера у вас нет. Ждите ответы — потом разложите их по порядку.", TTStyle.CAP, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "bold")
				cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_right.add_child(cl)
			elif not (_v["answered"] as Array).has(s):
				var p := TTStyle.bubble(10)
				var col := TTStyle.vbox(6)
				p.add_child(col)
				col.add_child(TTStyle.label("Ваш ответ" + ((" (%s)" % _name(s)) if _hotseat() else ""), TTStyle.CAP, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
				col.add_child(TTStyle.label("1 — от %s, 10 — до %s.\nНомер не называть!" % [_v["card"][_v["theme"]][1], _v["card"][_v["theme"]][2]], TTStyle.CAP, Color(TTStyle.INK, 0.7)))
				_answer_edit = LineEdit.new()
				_answer_edit.keep_editing_on_text_submit = true
				_answer_edit.max_length = TTRules.MAX_ANSWER
				_answer_edit.placeholder_text = "Например: «Кубик льда»"
				_answer_edit.text_submitted.connect(func(_t): _send_answer())
				_answer_edit.text = draft
				_answer_edit.caret_column = caret
				col.add_child(_answer_edit)
				var go := TTStyle.primary("Ответить", TTStyle.CAP)
				go.pressed.connect(_send_answer)
				col.add_child(go)
				_right.add_child(p)
				if continue_answer:
					_focus_answer_if_free.call_deferred(weakref(_answer_edit), _seat(), _round)
			else:
				_right.add_child(TTStyle.label("Ответ отправлен. Ждём остальных…", TTStyle.CAP, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
		"order":
			if _am_captain():
				var txt := "Перетащите ответы на планшет от меньшего номера к большему и меняйте их местами, сколько нужно. Двойной клик — положить / убрать."
				if _v["expert"]:
					txt = "Разложите ответы на планшете. Кликните по карте на планшете и назовите её номер."
				var l := TTStyle.label(txt, TTStyle.CAP, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "bold")
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_right.add_child(l)
				if _v["expert"] and _selected >= 0:
					_right.add_child(TTStyle.label("Номер для «%s»:" % _name(_selected), TTStyle.CAP, TTStyle.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
					_right.add_child(_number_grid(func(n):
						_calls[_selected] = n
						_selected = -1
						_push_arrangement(), int(_calls.get(_selected, -1))))
				var go := TTStyle.primary("Ответить", TTStyle.BODY)
				go.disabled = not _can_commit()
				go.tooltip_text = "" if _can_commit() else ("Положите на планшет все ответы" + (" и назовите каждому номер" if _v["expert"] else ""))
				go.pressed.connect(func():
					go.disabled = true
					Sfx.play("chips_big", -6)
					_send("tt_commit"))
				_right.add_child(go)
			else:
				var l := TTStyle.label("%s раскладывает ответы…" % _name(_v["captain"]), TTStyle.CAP, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "bold")
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_right.add_child(l)
		"guess":
			if _seat() != int(_v["captain"]):
				var l := TTStyle.label("Какой номер у капитана? Договоритесь и выберите вместе:", TTStyle.CAP, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "bold")
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_right.add_child(l)
				_right.add_child(_number_grid(func(n): _send("tt_guess", {"n": n}), -1))
			else:
				_right.add_child(TTStyle.label("Команда угадывает ваш номер…", TTStyle.CAP, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "bold"))


## Чужой ответ пересоздаёт панель, но не должен перетягивать ввод из чата или служебного окна.
func _focus_answer_if_free(reference: WeakRef, seat: int, round_no: int) -> void:
	var edit := reference.get_ref() as LineEdit
	if not is_instance_valid(edit) or edit != _answer_edit or not edit.is_visible_in_tree():
		return
	if is_queued_for_deletion() or _seat() != seat or _round != round_no or _v.get("phase", "") != "answer":
		return
	if Net.paused or bool(_v.get("game_paused", false)) or bool(_v.get("spectator", false)) or _top.chat.expanded:
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or owner == edit:
		edit.grab_focus()


func _send_answer() -> void:
	if _answer_edit == null or _answer_edit.text.strip_edges() == "":
		return
	# Net может удалить редактор синхронно: тот же Enter не должен затем открыть чат.
	get_viewport().set_input_as_handled()
	_send("tt_answer", {"text": _answer_edit.text})
	Sfx.play("card_place", -4)


func _number_card(n: int) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", TTStyle.box(TTStyle.lo_color().lerp(TTStyle.hi_color(), (n - 1) / 9.0), 16, TTStyle.INK, 4, 0.35))
	var v := TTStyle.vbox(0)
	p.add_child(v)
	v.add_child(TTStyle.label("ВАШ НОМЕР", TTStyle.CAP, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	var big := TTStyle.title(str(n), 64)
	v.add_child(big)
	return p


func _number_grid(on_pick: Callable, selected: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for n in range(1, 11):
		var b := TTStyle.button(str(n), TTStyle.BODY)
		b.custom_minimum_size = Vector2(46, 40)
		if n == selected:
			b.add_theme_stylebox_override("normal", TTStyle.box(TTStyle.accent(), 12, TTStyle.INK, 3, 0.0))
		var nn: int = n
		b.pressed.connect(func(): on_pick.call(nn))
		g.add_child(b)
	return g


# --- Итоги ------------------------------------------------------------------------

func _update_overlay() -> void:
	TTStyle.clear(_overlay)
	_auto_label = null
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var phase: String = _v["phase"]
	if not phase in ["round_result", "game_over"]:
		return
	var p := TTStyle.bubble(18)
	p.custom_minimum_size = Vector2(520, 0)
	_overlay.add_child(p)
	p.position = Vector2((size.x - 520) / 2.0, 250)
	var col := TTStyle.vbox(8)
	p.add_child(col)
	if phase == "round_result":
		var m: int = _v["result"].get("mistakes", 0)
		col.add_child(_dark_title("Без единой ошибки!" if m == 0 else "Ошибок: %d" % m, 24))
		if _v["expert"]:
			var g: int = _v["guess"]
			var cn: int = _v["result"].get("captain_number", 0)
			col.add_child(TTStyle.label("Номер капитана: %d — команда назвала %d%s" % [cn, g, " — угадали! Жетон вернулся к единорогу." if g == cn else ""], TTStyle.CAP, TTStyle.INK))
		col.add_child(TTStyle.label("Единорогов: %d · какашек: %d" % [_v["unicorns"], _v["poops"]], TTStyle.CAP, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		var row := TTStyle.hbox(10)
		var next := TTStyle.primary("Дальше", TTStyle.BODY, 150)
		next.pressed.connect(func():
			next.disabled = true
			Net.send_action("next"))
		row.add_child(next)
		_auto_label = TTStyle.label("", TTStyle.CAP, Color(TTStyle.INK, 0.6))
		row.add_child(_auto_label)
		row.add_child(ReadyDots.make(_v["players"], ReadyDots.pressed_next(_v)))
		col.add_child(row)
		return
	var texts := ["Это полный провал. Вы ведь только разогревались?", "Неплохо, но тренировка не помешает — в следующий раз точно получится!", "Вы настоящие профессионалы!", "Браво! Идеальный счёт! Попробуйте экспертный вариант!"]
	var lvl: int = _v["level"]
	col.add_child(_dark_title(["💩 Одни какашки", "Больше какашек", "Победа!", "🦄 Одни единороги!"][lvl], 26))
	var l := TTStyle.label(texts[lvl], TTStyle.CAP, TTStyle.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	col.add_child(TTStyle.label("Единорогов: %d · какашек: %d" % [_v["unicorns"], _v["poops"]], TTStyle.CAP, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	if _v["won"] and not _celebrated:
		_celebrated = true
		Sfx.victory()
	var brow := TTStyle.hbox(10)
	if Net.is_host():
		var again := TTStyle.primary("Новая партия", TTStyle.BODY)
		again.pressed.connect(Net.end_game)
		brow.add_child(again)
		var back := TTStyle.button("К выбору игры" if Net.is_party() else "В меню", TTStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
		brow.add_child(back)
	else:
		var leave := TTStyle.button("Покинуть пати", TTStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		brow.add_child(leave)
	col.add_child(brow)


func _dark_title(text: String, fs: int) -> Label:
	return TTStyle.label(text, fs, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title")


func _process(_delta: float) -> void:
	if _auto_label != null and is_instance_valid(_auto_label):
		var left := maxi(0, (_auto_deadline - Time.get_ticks_msec()) / 1000)
		var waiting: Array = _v.get("waiting", [])
		_auto_label.text = ("ждём: %s · " % ", ".join(waiting) if not waiting.is_empty() else "") + "сами через %d с" % left
