extends Control
## Стол «Word Slamа»: сверху — слово (рассказчику) и часы, в центре — две подставки с карточками
## (в командах: «Подставка 1» — синие, «Подставка 2» — оранжевые; обе видны всем в тех же позициях,
## но карточки чужой команды закрыты серыми пластинами — в конце хода пластины падают),
## снизу — колода карточек рассказчика (4 категории) или строка догадок; справа — команды и догадки.
## Карточки — общие карты сборника (K12TableCard): перетащить на подставку, переставить, утащить — убрать,
## двойной клик — убрать, правый клик — указать на карточку.

const PerudoDieView := preload("res://games/perudo/ui/d6_view.gd")
const TEAM_NAMES := ["Синие", "Оранжевые"]
const TEAM_COLORS := [Color("5f7fbf"), Color("d9895a")]
const LEVEL_COLORS := {"green": Color("6fbf73"), "yellow": Color("e8c547"), "red": Color("e06a5a")}
const CARD_GAP := 8.0

var app: Node

var _v := {}
var _me := 0
var _as := 0  # на одном компьютере — за кого смотрим
var _top_bar: TopBar
var _score_row: HBoxContainer
var _timer_label: Label
var _timer_bar: ProgressBar
var _word_panel: PanelContainer
var _word_key := ""
var _shelves: Control  # область двух подставок; карточки — её дети
var _shelf_titles: Array = []
var _bottom: Control
var _bottom_key := ""
var _side_teams: VBoxContainer
var _feed: VBoxContainer
var _overlay: Control
var _overlay_key := ""

var _rows_key := -1  # для кого собраны _rows (команда смотрящего)
var _rows: Array = [[], []]  # карточки на подставке 1 и 2 (свою рассказчик правит локально, хост получает её)
var _cards := {}  # id -> K12TableCard
var _active_shelf := 0
var _chips := {}  # id -> кнопка в колоде
var _pointer_n := -1
var _round := -1
var _time_left := 0.0
var _time_stamp := 0
var _auto_deadline := 0
var _auto_label: Label
var _guess_edit: LineEdit
var _celebrated := false
var _last_tick := -1

# карточки чужой команды — под серыми пластинами; в конце хода пластины спрыгивают и падают вниз
var _falling: Array = []  # [{node, vel, spin}] — падающие пластины
var _fall_layer: Control
var _hold_overlay_until := 0  # окно итогов ждёт, пока пластины упадут


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(HCBackdrop.new())

	var top := HCStyle.hbox(14)
	top.name = "Top"
	add_child(top)
	_score_row = HCStyle.hbox(8)
	top.add_child(_score_row)
	var tbox := HCStyle.vbox(2)
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_label = HCStyle.label("", HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	tbox.add_child(_timer_label)
	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(220, 8)
	_timer_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for part in [["background", HCStyle.SURFACE_2], ["fill", HCStyle.SAGE]]:
		var sb := HCStyle.box(part[1], 4)
		sb.set_content_margin_all(0)  # тонкая полоска, а не пустая плашка
		_timer_bar.add_theme_stylebox_override(part[0], sb)
	_timer_bar.visible = false
	tbox.add_child(_timer_bar)
	top.add_child(tbox)
	_top_bar = TopBar.make(self, "Word Slam", func(t, z): return HCStyle.button(t, z), null, HCStyle.INK, HCStyle.font("bold"))
	var rules := HCStyle.button("Правила", HCStyle.CAP)
	rules.pressed.connect(func(): app.show_rules())
	_top_bar.actions.add_child(rules)
	var settings := HCStyle.button("Настройки", HCStyle.CAP)
	settings.pressed.connect(func(): app.show_settings())
	_top_bar.actions.add_child(settings)
	_top_bar.actions.add_child(ThemeToggle.make(func(t, z): return HCStyle.button(t, z), HCStyle.CAP))  # солнце / луна — тема
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = HCStyle.button("Завершить партию", HCStyle.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся к выбору игры, пати сохранится.", Net.return_to_party)
	elif Net.is_party():
		leave = HCStyle.button("Покинуть пати", HCStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave = HCStyle.button("Выйти", HCStyle.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	leave.theme_type_variation = "QuietButton"
	_top_bar.actions.add_child(leave)
	HCStyle.restyle_chat(_top_bar.chat)

	_word_panel = HCStyle.panel(12)
	add_child(_word_panel)
	_shelves = Control.new()
	_shelves.draw.connect(_draw_shelves)
	add_child(_shelves)
	for i in 2:
		var t := HCStyle.caption("Подставка %d" % (i + 1))
		_shelves.add_child(t)
		_shelf_titles.append(t)
	_bottom = HCStyle.panel(12)
	add_child(_bottom)

	var side := HCStyle.panel(14)
	side.name = "Side"
	var sv := HCStyle.vbox(8)
	side.add_child(sv)
	_side_teams = HCStyle.vbox(6)
	sv.add_child(_side_teams)
	sv.add_child(HCStyle.separator())
	sv.add_child(HCStyle.caption("Догадки"))
	var scroll := ScrollContainer.new()
	scroll.name = "FeedScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_feed = HCStyle.vbox(3)
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_feed)
	sv.add_child(scroll)
	add_child(side)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_fall_layer = Control.new()
	_fall_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fall_layer)
	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := HCStyle.label(t, HCStyle.CAP, HCStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
		b.add_theme_stylebox_override("normal", HCStyle.box(HCStyle.SURFACE, 14, HCStyle.LINE, 1, HCStyle.SHADOW, 10))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 240
		return b, Vector2(-590, 10))

	resized.connect(_layout)
	_layout()
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state(Net.view)


func _layout() -> void:
	var w := size.x
	var h := size.y
	var side_w := 280.0
	var main_w := w - side_w - 48.0
	var top := get_node("Top") as Control
	top.position = Vector2(18, TopBar.HEIGHT + 6)
	top.size = Vector2(w - 36, 40)
	_word_panel.position = Vector2(16, TopBar.HEIGHT + 56)
	_word_panel.size = Vector2(main_w, 84)
	_shelves.position = Vector2(16, TopBar.HEIGHT + 150)
	_shelves.size = Vector2(main_w, 236)
	for i in 2:
		(_shelf_titles[i] as Control).position = Vector2(i * (main_w * 0.5) + 14, 6)
	_bottom.position = Vector2(16, TopBar.HEIGHT + 396)
	_bottom.size = Vector2(main_w, h - TopBar.HEIGHT - 396 - 16)
	var side := get_node("Side") as Control
	side.position = Vector2(w - side_w - 16, TopBar.HEIGHT + 56)
	side.size = Vector2(side_w, h - TopBar.HEIGHT - 56 - 70)
	_overlay.size = size
	_fall_layer.size = size
	_layout_cards(false)


# --- Роли --------------------------------------------------------------------------

func _hotseat() -> bool:
	return _v.get("hotseat", false)


func _seat() -> int:
	return _as if _hotseat() else _me


func _name(s: int) -> String:
	return _v["players"][s]["name"]


func _solo() -> bool:
	return _v.get("mode", "teams") == "solo"


func _team(s: int) -> int:
	return int(_v["players"][s].get("team", 0))


func _key() -> int:
	return 0 if _solo() else _team(_seat())


func _am_storyteller() -> bool:
	return _v.get("storytellers", []).has(_seat())


func _send(kind: String, arg: Dictionary = {}) -> void:
	if _hotseat():
		arg["as"] = _seat()
	Net.send_action(kind, arg)


# --- Состояние ---------------------------------------------------------------------

func _on_state(v: Dictionary) -> void:
	var prev_phase: String = _v.get("phase", "")
	var prev_guesses: int = _v.get("guesses", []).size()
	_v = v
	_me = v["you"]
	_auto_deadline = Time.get_ticks_msec() + int(v.get("auto_in", 0)) * 1000
	_time_left = float(v.get("time_left", 0.0))
	_time_stamp = Time.get_ticks_msec()
	var phase: String = v["phase"]
	if int(v["round_no"]) != _round:
		_round = int(v["round_no"])
		_rows = [[], []]
		_pointer_n = -1
		if _hotseat():
			_as = v["storytellers"][0]
		Sfx.play("card_flip", -6)
		if phase == "word":
			_show_roll(int(v["roll"]))
	if phase == "play" and prev_phase == "word":
		Sfx.play("chips_big", -4)  # «ВОРД!» — «СЛЭМ!»
	if v["guesses"].size() > prev_guesses:
		Sfx.play("hover", -4, 0.1, 0.02)
	_top_bar.info.text = ("Доп. карта" if v["tiebreak"] else "Карта %d из %d" % [v["round_no"], v["total_cards"]])
	_update_scores()
	_update_side()
	_update_feed()
	var wkey := "%s/%d/%d/%d/%s/%s" % [phase, v["round_no"], v["roll"], _seat(), str(v["ready"]), v["word"]]
	if wkey != _word_key:
		_word_key = wkey
		_update_word_panel()
	# подставки: свою рассказчик правит локально, остальное — с хоста
	var server := _server_rows()
	var key_changed: bool = _key() != _rows_key
	_rows_key = _key()
	for sh in 2:
		var mine_editing: bool = _am_storyteller() and phase == "play" and _editable_shelf(sh) and not _rows[sh].is_empty()
		if not mine_editing or key_changed:
			_rows[sh] = server[sh].duplicate()
	_update_shelf_titles()
	_sync_cards(prev_phase == "play" and phase in ["round_result", "game_over"])
	_update_pointer()
	var bkey := "%s/%d/%d/%s" % [phase, v["round_no"], _seat(), str(_am_storyteller())]
	if bkey != _bottom_key:
		_bottom_key = bkey
		_update_bottom()
	_refresh_chips()
	var okey := "%s/%d/%s" % [phase, v["round_no"], ",".join(v.get("waiting", []))]
	if okey != _overlay_key:
		_overlay_key = okey
		var wait := (_hold_overlay_until - Time.get_ticks_msec()) / 1000.0
		if wait > 0.0:
			# сначала пусть все увидят, как пластины падают с карточек соперников
			get_tree().create_timer(wait).timeout.connect(func():
				if _overlay_key == okey:
					_update_overlay())
		else:
			_update_overlay()


func _update_scores() -> void:
	HCStyle.clear(_score_row)
	if _solo():
		var best := -1
		var leader := -1
		for s in _v["players"].size():
			if _v["scores"][s] > best:
				best = _v["scores"][s]
				leader = s
		_score_row.add_child(HCStyle.label("Лидер: %s — %d" % [_name(leader), best], HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		return
	for t in 2:
		var pill := PanelContainer.new()
		var sb := HCStyle.box(Color(TEAM_COLORS[t], 0.14), 16, TEAM_COLORS[t], 1)
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		pill.add_theme_stylebox_override("panel", sb)
		var row := HCStyle.hbox(8)
		row.add_child(HCStyle.label(TEAM_NAMES[t], HCStyle.CAP, TEAM_COLORS[t].darkened(0.25), HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		row.add_child(HCStyle.label(str(_v["scores"][t]), HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
		pill.add_child(row)
		_score_row.add_child(pill)


func _update_side() -> void:
	HCStyle.clear(_side_teams)
	var groups := [0] if _solo() else [0, 1]
	for t in groups:
		if not _solo():
			_side_teams.add_child(HCStyle.label(TEAM_NAMES[t], HCStyle.CAP, TEAM_COLORS[t].darkened(0.2), HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		for s in _v["players"].size():
			if not _solo() and _team(s) != t:
				continue
			var row := HCStyle.hbox(6)
			var st: bool = _v["storytellers"].has(s)
			var nm := PlayerTag.make_seat(_v["players"], s, _me, 14, HCStyle.INK if st else HCStyle.MUTED, (" ✎" if st else "") + (" (вы)" if s == _me and not _hotseat() else ""))
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.clip_text = true
			row.add_child(nm)
			if _solo():
				row.add_child(HCStyle.label(str(_v["scores"][s]), HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_RIGHT, "title"))
			if _hotseat():
				var b := HCStyle.button("я" if s == _as else "за него", HCStyle.CAP)
				UISel.pick(b, s == _as)
				var ss: int = s
				b.pressed.connect(func():
					_as = ss
					_word_key = ""
					_bottom_key = ""
					_on_state(_v))
				row.add_child(b)
			_side_teams.add_child(row)


func _update_feed() -> void:
	HCStyle.clear(_feed)
	var list: Array = _v["guesses"].duplicate()
	list.reverse()
	for g in list:
		var s: int = g["seat"]
		var col: Color = HCStyle.INK if _solo() else TEAM_COLORS[_team(s)].darkened(0.25)
		var l := HCStyle.label("%s: %s%s" % [_name(s), g["text"], "  ✓" if g["ok"] else ""], HCStyle.CAP, HCStyle.SAGE.darkened(0.2) if g["ok"] else col, HORIZONTAL_ALIGNMENT_LEFT, "bold" if g["ok"] else "regular")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 240
		_feed.add_child(l)
	if list.is_empty():
		_feed.add_child(HCStyle.label("Пока тихо", HCStyle.CAP, HCStyle.MUTED))


# --- Слово (у рассказчика) -----------------------------------------------------------

var _rolling := false


## Показательный бросок кубика в начале раунда: кубик кувыркается в центре и выпадает номер слова.
func _show_roll(value: int) -> void:
	_rolling = true
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 50
	add_child(layer)
	var die := PerudoDieView.new(1, 120)
	die.position = Vector2(size.x * 0.5 - 60, -140)
	layer.add_child(die)
	var cap := HCStyle.label("", HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "title")
	cap.size = Vector2(500, 50)
	cap.position = Vector2(size.x * 0.5 - 250, size.y * 0.42 + 80)
	cap.modulate.a = 0.0
	layer.add_child(cap)
	Sfx.play("die_throw", -4)
	var t := create_tween()
	t.set_parallel()
	t.tween_property(die, "position:y", size.y * 0.42 - 60, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_property(die, "rotation", TAU * 3 + randf_range(-0.2, 0.2), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(k: float): die.value = (int(k * 37) % 6) + 1, 0.0, 1.0, 0.85)
	t.set_parallel(false)
	t.tween_callback(func():
		die.value = value
		die.rotation = 0.0
		cap.text = "Слово № %d" % value
		Sfx.play("card_place", -4))
	t.tween_property(cap, "modulate:a", 1.0, 0.2)
	t.tween_interval(1.1)
	t.tween_property(layer, "modulate:a", 0.0, 0.35)
	t.tween_callback(func():
		layer.queue_free()
		_rolling = false
		_word_key = ""
		_update_word_panel())


func _update_word_panel() -> void:
	HCStyle.clear(_word_panel)
	var row := HCStyle.hbox(14)
	_word_panel.add_child(row)
	var phase: String = _v["phase"]
	if not _am_storyteller() or phase in ["round_result", "game_over"]:
		var st: Array = _v["storytellers"]
		var text := ""
		if phase == "word":
			text = "Рассказчики смотрят слово: %s" % ", ".join(st.map(func(s): return _name(s)))
		elif phase == "play":
			var mine := st.filter(func(s): return _solo() or _team(s) == _team(_seat()))
			text = "Рассказывает %s — угадывайте по карточкам!" % (_name(mine[0]) if not mine.is_empty() else "?")
		else:
			text = "Раунд окончен"
		var l := HCStyle.label(text, HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		return
	var card: Dictionary = _v["card"]
	if _rolling:
		row.add_child(HCStyle.label("Бросаем кубик — какое слово достанется?", HCStyle.BODY, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "medium"))
		return
	var die := PerudoDieView.new(int(_v["roll"]), 44)
	row.add_child(die)
	var col := HCStyle.vbox(0)
	col.add_child(HCStyle.caption("Ваше слово" + ((" · за %s" % _name(_seat())) if _hotseat() else "")))
	col.add_child(HCStyle.label(str(_v["word"]).to_upper(), HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	row.add_child(col)
	var words := HCStyle.vbox(0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var parts := []
	for i in card.get("words", []).size():
		parts.append(("%d — %s" % [i + 1, card["words"][i]]) if i + 1 != int(_v["roll"]) else "[b]%d — %s[/b]" % [i + 1, card["words"][i]])
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.custom_minimum_size.x = 320  # иначе при первой раскладке строка переносится по букве и растягивает панель
	rt.add_theme_font_size_override("normal_font_size", 11)
	rt.add_theme_font_size_override("bold_font_size", 11)
	rt.add_theme_color_override("default_color", HCStyle.MUTED)
	rt.text = "   ".join(parts)
	var lvl := HCStyle.caption({"green": "Вводная карта", "yellow": "Жёлтая карта", "red": "Красная карта"}.get(card.get("level", ""), ""), LEVEL_COLORS.get(card.get("level", ""), HCStyle.MUTED))
	words.add_child(lvl)
	words.add_child(rt)
	row.add_child(words)
	if phase == "word":
		var i: int = _v["storytellers"].find(_seat())
		var ready := HCStyle.primary("ВОРД!" if i == 0 else "СЛЭМ!", HCStyle.BODY, 110)
		ready.tooltip_text = "Готов рассказывать"
		ready.disabled = i < 0 or _v["ready"][i]
		ready.pressed.connect(func(): _send("ws_ready"))
		row.add_child(ready)
	elif phase == "play":
		if _solo():
			var g := HCStyle.vbox(2)
			g.add_child(HCStyle.label("Угадал голосом:", HCStyle.CAP, HCStyle.MUTED))
			var gr := HCStyle.hbox(4)
			for s in _v["players"].size():
				if s == _seat():
					continue
				var b := HCStyle.button(_name(s), HCStyle.CAP)
				var ss: int = s
				b.pressed.connect(func(): _send("ws_confirm", {"guesser": ss}))
				gr.add_child(b)
			g.add_child(gr)
			row.add_child(g)
		else:
			var ok := HCStyle.primary("Угадали!", HCStyle.BODY)
			ok.tooltip_text = "Команда назвала слово голосом"
			ok.pressed.connect(func(): _send("ws_confirm"))
			row.add_child(ok)


# --- Подставки и карточки -------------------------------------------------------------

func _draw_shelves() -> void:
	var w := _shelves.size.x * 0.5
	for i in 2:
		var r := Rect2(i * w + 4, 0, w - 8, _shelves.size.y)
		var active: bool = _am_storyteller() and _v.get("phase", "") == "play" and (i == _active_shelf if _solo() else i == _key())
		_shelves.draw_style_box(HCStyle.box(Color(HCStyle.CARD, 0.75), 16, HCStyle.SAGE if active else HCStyle.LINE, 2 if active else 1, HCStyle.SHADOW, 12), r)
		# «полка» — деревянная планка под каждым рядом
		var per := _per_row()
		for rr in 4:
			var y := 30.0 + rr * 50.0 + WSCardFace.SIZE.y + 2
			if y > r.end.y - 4:
				break
			_shelves.draw_rect(Rect2(r.position.x + 10, y, r.size.x - 20, 4), Color("e2d3bb"))
		if per <= 0:
			continue


# --- Подставки: чья какая, закрытые карточки ----------------------------------------

## Карточки обеих подставок с хоста. Команды: подставка t — все карточки команды t;
## один рассказчик: две его подставки.
func _server_rows() -> Array:
	var hv: Dictionary = _v.get("holders", {})
	if _solo():
		var r: Array = hv.get(0, hv.get("0", [[], []]))
		return [r[0].duplicate(), r[1].duplicate()]
	var out := [[], []]
	for t in 2:
		var r: Array = hv.get(t, hv.get(str(t), [[], []]))
		out[t] = r[0] + r[1]
	return out


## Может ли смотрящий рассказчик править эту подставку.
func _editable_shelf(sh: int) -> bool:
	return _solo() or sh == _key()


## Закрыта ли подставка серыми пластинами для смотрящего (чужая команда, ход ещё идёт).
func _covered_shelf(sh: int) -> bool:
	return not _solo() and sh != _key() and not _v.get("phase", "") in ["round_result", "game_over"]


func _update_shelf_titles() -> void:
	for i in 2:
		var t := _shelf_titles[i] as Label
		if _solo():
			t.text = "ПОДСТАВКА %d" % (i + 1)
			t.add_theme_color_override("font_color", HCStyle.MUTED)
		else:
			t.text = ("ПОДСТАВКА %d · «%s»" % [i + 1, TEAM_NAMES[i]]).to_upper() + (" — СКРЫТО ДО КОНЦА ХОДА" if _covered_shelf(i) else "")
			t.add_theme_color_override("font_color", TEAM_COLORS[i].darkened(0.15))


func _card_key(sh: int, id: String) -> String:
	return "%d|%s" % [sh, id]


func _make_cover() -> Control:
	var c := Control.new()
	c.size = WSCardFace.SIZE
	c.name = "Cover"
	c.mouse_filter = Control.MOUSE_FILTER_PASS  # для подсказки
	c.tooltip_text = "Карточка соперников — откроется в конце хода"
	var edge: Color = TEAM_COLORS[1 - _key()]
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size)
		c.draw_style_box(HCStyle.box(Color("bdb7ad"), 10, Color(edge, 0.8), 2, Color(0, 0, 0, 0.12), 3), r)
		# лёгкая штриховка «обратной стороны»
		for i in range(-2, 8):
			var x := i * 10.0
			c.draw_line(Vector2(x, r.size.y), Vector2(x + r.size.y, 0), Color(1, 1, 1, 0.14), 2.0, true))
	return c


## Пластины спрыгивают с карточек и падают вниз (гравитация); лица карточек уже открыты под ними.
func _drop_covers(covers: Array) -> void:
	var t := 0.0
	for c in covers:
		if not is_instance_valid(c):
			continue
		var gp: Vector2 = (c as Control).global_position
		c.get_parent().remove_child(c)
		_fall_layer.add_child(c)
		c.global_position = gp
		c.pivot_offset = (c as Control).size * 0.5
		c.set_meta("delay", t)
		t += 0.05
		_falling.append({"node": c, "vel": Vector2(randf_range(-160, 160), randf_range(-520, -380)), "spin": randf_range(-7.0, 7.0)})
	if not covers.is_empty():
		Sfx.play("card_shove", -6)
		_hold_overlay_until = Time.get_ticks_msec() + 1400


func _step_falling(delta: float) -> void:
	for f in _falling.duplicate():
		if not is_instance_valid(f["node"]):
			_falling.erase(f)
			continue
		var c: Control = f["node"]
		var d: float = c.get_meta("delay", 0.0)
		if d > 0.0:
			c.set_meta("delay", d - delta)
			continue
		f["vel"] += Vector2(0, 2200.0) * delta
		c.position += f["vel"] * delta
		c.rotation += f["spin"] * delta
		if c.position.y > size.y + 80.0:
			c.queue_free()
			_falling.erase(f)


func _per_row() -> int:
	return maxi(1, int((_shelves.size.x * 0.5 - 28.0) / (WSCardFace.SIZE.x + CARD_GAP)))


func _slot(shelf: int, i: int) -> Vector2:
	var per := _per_row()
	var w := _shelves.size.x * 0.5
	var x := shelf * w + 18.0 + (i % per) * (WSCardFace.SIZE.x + CARD_GAP) + WSCardFace.SIZE.x * 0.5
	var y := 30.0 + (i / per) * 50.0 + WSCardFace.SIZE.y * 0.5
	return Vector2(x, y)


func _sync_cards(revealing: bool = false) -> void:
	var want := {}
	var qn := 0
	for sh in 2:
		for k in _rows[sh].size():
			if str(_rows[sh][k]) == "?":
				_rows[sh][k] = "?%d" % qn  # закрытые карточки — у каждой свой ключ
				qn += 1
			want[_card_key(sh, _rows[sh][k])] = true
	var drop: Array = []
	for key in _cards.keys():
		if not want.has(key):
			var old: K12TableCard = _cards[key]
			var cov := old.get_node_or_null("Cover")
			if cov != null and revealing:
				drop.append(cov)
			old.queue_free()
			_cards.erase(key)
	var phase: String = _v.get("phase", "")
	for sh in 2:
		var editable: bool = _am_storyteller() and phase == "play" and _editable_shelf(sh)
		for k in _rows[sh].size():
			var id: String = _rows[sh][k]
			var key := _card_key(sh, id)
			if not _cards.has(key):
				var face_id := "?" if id.begins_with("?") else id
				var c := K12TableCard.new("ws_" + key, true, WSCardFace.new(face_id), WSCardFace.SIZE)
				_shelves.add_child(c)
				c.place(_slot(sh, k) + Vector2(0, -20))
				c.modulate.a = 0.0
				create_tween().tween_property(c, "modulate:a", 1.0, 0.2)
				_cards[key] = c
				_wire(c, id)
			var card: K12TableCard = _cards[key]
			card.draggable = editable
			# серая пластина поверх карточки чужой команды
			var cover := card.get_node_or_null("Cover")
			if _covered_shelf(sh) and cover == null:
				cover = _make_cover()
				cover.position = Vector2.ZERO  # лицо карточки занимает её целиком
				card.add_child(cover)
			elif not _covered_shelf(sh) and cover != null:
				if revealing:
					drop.append(cover)
				else:
					cover.queue_free()
	if not drop.is_empty():
		_drop_covers(drop)
	_layout_cards(true)
	_shelves.queue_redraw()


func _wire(c: K12TableCard, id: String) -> void:
	c.dropped.connect(func(card, at): _on_card_dropped(id, card, at))
	c.double_clicked.connect(func(_card):
		if _am_storyteller() and _v["phase"] == "play":
			_remove(id))
	c.right_clicked.connect(func(_card):
		if _am_storyteller() and _v["phase"] == "play":
			_send("ws_point", {"id": id}))
	c.clicked.connect(func(_card): _layout_cards(true))
	c.hovered.connect(func(card: K12TableCard, on: bool):
		if not card.dragging and card.draggable:
			card.move_to(card.center(), 0.0, 1.06 if on else 1.0, 0.1))


func _layout_cards(animate: bool) -> void:
	for sh in 2:
		for k in _rows[sh].size():
			var key := _card_key(sh, _rows[sh][k])
			if not _cards.has(key):
				continue
			var c: K12TableCard = _cards[key]
			if c.dragging:
				continue
			if animate:
				c.move_to(_slot(sh, k), 0.0, 1.0, 0.18)
			else:
				c.place(_slot(sh, k))


func _where(at: Vector2) -> Array:
	var area := Rect2(Vector2.ZERO, _shelves.size).grow(16)
	if not area.has_point(at):
		return [-1, -1]
	var sh := 0 if at.x < _shelves.size.x * 0.5 else 1
	var per := _per_row()
	var w := _shelves.size.x * 0.5
	var col := clampi(int((at.x - sh * w - 18.0) / (WSCardFace.SIZE.x + CARD_GAP) + 0.5), 0, per)
	var row := clampi(int((at.y - 30.0) / 50.0), 0, 3)
	return [sh, row * per + col]


func _on_card_dropped(id: String, card: K12TableCard, at: Vector2) -> void:
	var w := _where(at)
	var from := -1
	for sh in 2:
		if _editable_shelf(sh) and _rows[sh].has(id):
			from = sh
	if w[0] >= 0 and not _editable_shelf(w[0]):
		# на подставку чужой команды класть нельзя: карточка возвращается (новая — уходит в колоду)
		if from >= 0:
			_layout_cards(true)
			return
		w = [-1, -1]
	var cur_key := _card_key(from, id) if from >= 0 else id
	if from >= 0:
		_rows[from].erase(id)
	_cards.erase(cur_key)
	if w[0] < 0:
		var t := create_tween()
		t.tween_property(card, "modulate:a", 0.0, 0.15)
		t.tween_callback(card.queue_free)
		Sfx.play("card_slide", -8)
	else:
		if _rows[w[0]].size() >= WSRules.MAX_ON_HOLDER:
			if not _solo():
				_layout_cards(true)
				return
			w[0] = 1 - w[0]
		_rows[w[0]].insert(mini(w[1], _rows[w[0]].size()), id)
		_cards[_card_key(w[0], id)] = card
		_active_shelf = w[0]
		Sfx.play("card_place", -6)
	_push_rows()


func _remove(id: String) -> void:
	var key := ""
	for sh in 2:
		if _editable_shelf(sh) and _rows[sh].has(id):
			_rows[sh].erase(id)
			key = _card_key(sh, id)
	if _cards.has(key):
		var c: K12TableCard = _cards[key]
		_cards.erase(key)
		var t := create_tween()
		t.tween_property(c, "modulate:a", 0.0, 0.15)
		t.tween_callback(c.queue_free)
	Sfx.play("card_slide", -8)
	_push_rows()


func _push_rows() -> void:
	_layout_cards(true)
	_refresh_chips()
	_shelves.queue_redraw()
	if _solo():
		_send("ws_holders", {"rows": [_rows[0].duplicate(), _rows[1].duplicate()]})
	else:
		_send("ws_holders", {"rows": [_rows[_key()].duplicate(), []]})  # у команды — одна подставка


## Из колоды: начать перетаскивание новой карточки (короткий клик — в конец активной подставки).
func _grab_from_deck(id: String) -> void:
	if _own_has(id) or _cards.has(id) or not (_am_storyteller() and _v["phase"] == "play"):
		return
	var c := K12TableCard.new("ws_" + id, true, WSCardFace.new(id), WSCardFace.SIZE)
	c.draggable = true
	_shelves.add_child(c)
	c.place(_shelves.get_local_mouse_position())
	c.dragging = true
	c.z_index = 60
	_cards[id] = c
	_wire(c, id)
	c.clicked.connect(func(_card):
		# клик без перетаскивания — в конец активной подставки
		var sh := _active_shelf if _solo() else _key()
		if _solo() and _rows[sh].size() >= WSRules.MAX_ON_HOLDER:
			sh = 1 - sh
		if not _own_has(id) and _rows[sh].size() < WSRules.MAX_ON_HOLDER:
			_cards.erase(id)
			_rows[sh].append(id)
			_cards[_card_key(sh, id)] = c
			Sfx.play("card_place", -6)
			_push_rows(), CONNECT_ONE_SHOT)
	Sfx.play("card_flip", -10)


## Карточка уже на подставке смотрящего рассказчика (свои подставки).
func _own_has(id: String) -> bool:
	for sh in 2:
		if _editable_shelf(sh) and _rows[sh].has(id):
			return true
	return false


func _update_pointer() -> void:
	var p: Dictionary = _v.get("pointer", {})
	var mine: Dictionary = p.get(_key(), p.get(str(_key()), {}))
	if mine.is_empty() or int(mine["n"]) == _pointer_n:
		return
	var first: bool = _pointer_n < 0 and _v["phase"] != "play"
	_pointer_n = int(mine["n"])
	var pkey := ""
	for sh in 2:
		if _editable_shelf(sh) and _rows[sh].has(mine["id"]):
			pkey = _card_key(sh, mine["id"])
	if first or not _cards.has(pkey):
		return
	var face := (_cards[pkey] as K12TableCard).get_child(0) as WSCardFace
	if face == null:
		return
	Sfx.play("chip", -4)
	var t := create_tween()
	for k in 3:
		t.tween_property(face, "pointed", 1.0, 0.18)
		t.tween_property(face, "pointed", 0.3, 0.25)
	t.tween_property(face, "pointed", 0.0, 0.4)


# --- Низ: колода рассказчика / строка догадок -----------------------------------------

func _update_bottom() -> void:
	HCStyle.clear(_bottom)
	_chips.clear()
	_guess_edit = null
	var phase: String = _v["phase"]
	if _am_storyteller() and phase in ["word", "play"]:
		var cols := HCStyle.hbox(10)
		_bottom.add_child(cols)
		for cat in WSData.CATEGORIES:
			var col := HCStyle.vbox(4)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cap := HCStyle.caption(WSData.CATEGORY_NAMES[cat], WSCardFace.EDGES[cat].darkened(0.3))
			col.add_child(cap)
			var scroll := ScrollContainer.new()
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			flow.add_theme_constant_override("h_separation", 4)
			flow.add_theme_constant_override("v_separation", 4)
			scroll.add_child(flow)
			col.add_child(scroll)
			for i in WSData.STORY[cat].size():
				var id := "%s:%d" % [cat, i]
				var b := Button.new()
				b.text = WSData.STORY[cat][i]
				b.add_theme_font_size_override("font_size", 13)
				b.add_theme_font_override("font", HCStyle.font("bold"))
				var sb := HCStyle.box(WSCardFace.COLORS[cat], 8, WSCardFace.EDGES[cat], 1)
				sb.content_margin_left = 8
				sb.content_margin_right = 8
				sb.content_margin_top = 4
				sb.content_margin_bottom = 4
				b.add_theme_stylebox_override("normal", sb)
				var hsb := sb.duplicate() as StyleBoxFlat
				hsb.border_color = HCStyle.INK
				b.add_theme_stylebox_override("hover", hsb)
				b.add_theme_stylebox_override("pressed", hsb)
				var dsb := sb.duplicate() as StyleBoxFlat
				dsb.bg_color = Color(WSCardFace.COLORS[cat], 0.55 if HCStyle.dark else 0.35)  # на тёмном фоне бледная пастель сливалась
				dsb.border_color = Color(0, 0, 0, 0)  # неактивное слово — без рамки (в тёмной теме рамка светилась)
				b.add_theme_stylebox_override("disabled", dsb)
				b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
				# текст — тёмный, как на самих карточках, в любой теме (светлый на пастели в тёмной теме не читался)
				b.add_theme_color_override("font_color", HCStyle.INK_ART)
				b.add_theme_color_override("font_hover_color", HCStyle.INK_ART)
				b.add_theme_color_override("font_pressed_color", HCStyle.INK_ART)
				b.add_theme_color_override("font_disabled_color", Color(HCStyle.INK_ART, 0.6 if HCStyle.dark else 0.35))
				b.mouse_default_cursor_shape = Control.CURSOR_DRAG
				b.button_down.connect(func(): _grab_from_deck(id))
				flow.add_child(b)
				_chips[id] = b
			cols.add_child(col)
		_refresh_chips()
		return
	var col := HCStyle.vbox(10)
	_bottom.add_child(col)
	if phase == "play" and not _am_storyteller():
		col.add_child(HCStyle.label("Ваша догадка" + ((" (за %s)" % _name(_seat())) if _hotseat() else ""), HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		var row := HCStyle.hbox(8)
		_guess_edit = LineEdit.new()
		_guess_edit.placeholder_text = "Напишите слово и нажмите Enter (можно и голосом — рассказчик отметит)"
		_guess_edit.max_length = 60
		_guess_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_guess_edit.add_theme_font_size_override("font_size", 20)
		_guess_edit.text_submitted.connect(func(_t): _send_guess())
		row.add_child(_guess_edit)
		var go := HCStyle.primary("Отгадать", HCStyle.BODY)
		go.pressed.connect(_send_guess)
		row.add_child(go)
		col.add_child(row)
		col.add_child(HCStyle.label("Догадки обеих команд видны всем — как в настольной игре, где команды слышат друг друга.", HCStyle.CAP, HCStyle.MUTED))
		_guess_edit.grab_focus.call_deferred()
	elif phase == "word":
		col.add_child(HCStyle.label("Рассказчики выбирают слово. Сейчас начнётся: «ВОРД!» — «СЛЭМ!»", HCStyle.BODY, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "medium"))


func _send_guess() -> void:
	if _guess_edit == null or _guess_edit.text.strip_edges() == "":
		return
	_send("ws_guess", {"text": _guess_edit.text})
	_guess_edit.clear()


func _refresh_chips() -> void:
	for id in _chips:
		(_chips[id] as Button).disabled = _own_has(id) or _v.get("phase", "") != "play"


# --- Итоги и конец ------------------------------------------------------------------

func _update_overlay() -> void:
	HCStyle.clear(_overlay)
	_auto_label = null
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _v["phase"] in ["round_result", "game_over"]:
		return
	var dim := ColorRect.new()
	dim.color = Color(0.15, 0.13, 0.1, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var p := HCStyle.panel(24)
	p.custom_minimum_size = Vector2(640, 0)
	center.add_child(p)
	var col := HCStyle.vbox(10)
	p.add_child(col)
	if _v["phase"] == "game_over":
		var w: Array = _v["winners"]
		var title := ""
		if _solo():
			title = ("Победа: %s" if w.size() == 1 else "Делят победу: %s") % ", ".join(w.map(func(s): return _name(s)))
		else:
			title = "Победа: %s!" % TEAM_NAMES[w[0]] if w.size() == 1 else "Ничья!"
		col.add_child(HCStyle.title(title, HCStyle.H1))
		col.add_child(HCStyle.label("Счёт: " + (" : ".join(_v["scores"].map(func(x): return str(x)))), HCStyle.BODY, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
		if not _celebrated:
			_celebrated = true
			Sfx.victory()
		var row := HCStyle.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		if Net.is_host():
			var again := HCStyle.primary("Новая партия", HCStyle.BODY)
			again.pressed.connect(Net.end_game)
			row.add_child(again)
			var back := HCStyle.button("К выбору игры" if Net.is_party() else "В меню", HCStyle.BODY)
			back.pressed.connect(func(): app.back_to_menu())
			row.add_child(back)
		else:
			var leave := HCStyle.button("Покинуть пати", HCStyle.BODY)
			LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
			row.add_child(leave)
		col.add_child(row)
		return
	var r: Dictionary = _v["result"]
	var head := ""
	if int(r.get("winner", -1)) < 0:
		head = "Время вышло"
	elif _solo():
		head = "Угадал(а) %s!" % _name(r["winner"])
	else:
		head = "Угадали %s!" % TEAM_NAMES[r["team"]]
		Sfx.play("chips_win", -2)
	col.add_child(HCStyle.caption(head, HCStyle.SAGE if int(r.get("winner", -1)) >= 0 else HCStyle.CLAY))
	col.add_child(HCStyle.label(str(r.get("word", "")).to_upper(), HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	var hv: Dictionary = _v["holders"]
	for k in hv:
		var rows: Array = hv[k]
		var who := "Рассказ" if _solo() else "Рассказ команды «%s»" % TEAM_NAMES[int(k)]
		col.add_child(HCStyle.label(who + ":", HCStyle.CAP, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		for sh in 2:
			if rows[sh].is_empty():
				continue
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 4)
			for id in rows[sh]:
				var f := WSCardFace.new(id)
				f.custom_minimum_size = WSCardFace.SIZE * Vector2(0.85, 0.8)
				f.size = f.custom_minimum_size
				flow.add_child(f)
			col.add_child(flow)
	var brow := HCStyle.hbox(10)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	var next := HCStyle.primary("Дальше", HCStyle.BODY, 150)
	next.pressed.connect(func():
		next.disabled = true
		Net.send_action("next"))
	brow.add_child(next)
	_auto_label = HCStyle.label("", HCStyle.CAP, HCStyle.MUTED)
	brow.add_child(_auto_label)
	brow.add_child(ReadyDots.make(_v["players"], ReadyDots.pressed_next(_v)))
	col.add_child(brow)


func _process(_delta: float) -> void:
	if not _falling.is_empty():
		_step_falling(_delta)
	if _v.is_empty():
		return
	var phase: String = _v["phase"]
	var total := float(_v.get("time_total", 60.0))
	if phase == "play":
		var left := maxf(0.0, _time_left - (Time.get_ticks_msec() - _time_stamp) / 1000.0)
		if ceili(left) != _last_tick:
			_last_tick = ceili(left)
			Sfx.countdown(_last_tick)
		_timer_label.text = "⏳ %d:%02d" % [int(left) / 60, int(left) % 60]
		_timer_bar.value = left / total * 100.0
		_timer_bar.visible = true
		_timer_label.add_theme_color_override("font_color", HCStyle.CLAY if left < 15 else HCStyle.INK)
	else:
		_timer_label.text = ""
		_timer_bar.value = 0.0
		_timer_bar.visible = false  # нет отсчёта — нет и пустой полоски
	if _auto_label != null and is_instance_valid(_auto_label):
		var l := maxi(0, (_auto_deadline - Time.get_ticks_msec()) / 1000)
		var waiting: Array = _v.get("waiting", [])
		_auto_label.text = ("ждём: %s · " % ", ".join(waiting) if not waiting.is_empty() else "") + "сами через %d с" % l
