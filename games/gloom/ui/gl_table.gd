extends Control
## Стол Gloom. Сверху — семьи соперников, внизу слева — ваша семья, справа — рука.
## В середине: колода и сброс, панель действия, журнал «истории». Карту из руки перетаскивают на
## персонажа (или выбирают щелчком, затем персонажа). Наведение — крупный просмотр карты/стопки.

var app: Node


var _v := {}
var _me := 0  # чья семья внизу (на одном компьютере — того, кто сейчас действует)
var _board: Control  # семьи (пересобираются)
var _hand_layer: Control
var _hand := {}  # карта -> K12TableCard
var _order: Array = []  # порядок карт в руке (локальный, можно переставлять)
var _stacks := {}  # персонаж -> GLStack
var _card_scale := 1.0  # стол не влезает по высоте (5 игроков, гости и истории) — карты на столе мельче
var _scale_for := -1  # для какого числа соперников подобран масштаб
var _centre_low := false  # гости и истории — внизу рядом со своей семьёй (соперники заняли два ряда)
var _panel: PanelContainer
var _panel_key := ""
var _log: RichTextLabel
var _log_panel: PanelContainer
var _deck: TextureRect
var _deck_label: Label
var _discard: TextureRect
var _discard_bg: Panel
var _discard_label: Label
var _preview: Control
var _sel := -1  # выбранная карта руки
var _ev := {}  # выбор целей события: {t, t2, with, pick}
var _marked: Array = []  # отмеченные карты (сброс / передача)
var _drag := -1
var _celebrated := false
var _last_stack_sig := ""
var _hover_char := -1
var _top: TopBar


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(GLStyle.Backdrop.new())
	_board = Control.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)

	_deck = TextureRect.new()
	_deck.texture = GLStyle.tex("back")
	_deck.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_deck.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_deck.tooltip_text = "Колода"
	add_child(_deck)
	_deck_label = GLStyle.label("", GLStyle.CAP, GLStyle.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_deck_label)
	_discard_bg = Panel.new()
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(0.81, 0.79, 0.82, 0.14)
	glass.set_corner_radius_all(6)
	glass.shadow_color = Color(0, 0, 0, 0.4)
	glass.shadow_size = 6
	_discard_bg.add_theme_stylebox_override("panel", glass)
	_discard_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_discard_bg)
	_discard = TextureRect.new()
	_discard.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_discard.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_discard.tooltip_text = "Сброс — щёлкните, чтобы посмотреть все карты"
	_discard.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_discard.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_show_discard())
	add_child(_discard)
	_discard_label = GLStyle.label("", GLStyle.CAP, GLStyle.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_discard_label)

	_log_panel = GLStyle.dark_panel(10)
	var lcol := GLStyle.vbox(4)
	_log_panel.add_child(lcol)
	lcol.add_child(GLStyle.label("Хроника несчастий", GLStyle.CAP, GLStyle.BONE_DIM, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_color_override("default_color", GLStyle.BONE)
	_log.add_theme_font_size_override("normal_font_size", GLStyle.CAP)
	_log.add_theme_font_size_override("bold_font_size", GLStyle.CAP)
	lcol.add_child(_log)
	add_child(_log_panel)

	_panel = GLStyle.panel(14)
	_panel.z_index = 10
	add_child(_panel)

	_hand_layer = Control.new()
	_hand_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_layer.z_index = 20
	add_child(_hand_layer)

	_preview = Control.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.z_index = 60
	_preview.visible = false
	add_child(_preview)

	# верхняя полоса: название, ход, часы, чат и кнопки игры
	_top = TopBar.make(self, "Gloom", func(t, z): return GLStyle.button(t, z), null, GLStyle.BONE, GLStyle.font("bold"))
	_top.z_index = 40  # над столом и рукой (20), под крупным просмотром (60)
	_top.chat.z_index = 40
	GLStyle.restyle_chat(_top.chat)
	var rules := GLStyle.button("Правила", 14)
	rules.pressed.connect(func(): app.show_rules())
	_top.actions.add_child(rules)
	var settings := GLStyle.button("Настройки", 14)
	settings.pressed.connect(func(): app.show_settings())
	_top.actions.add_child(settings)
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = GLStyle.button("Завершить партию", 14)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся в лобби игры, пати сохранится.", Net.end_game)
	elif Net.is_party():
		leave = GLStyle.button("Покинуть пати", 14)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		leave = GLStyle.button("Выйти", 14)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	_top.actions.add_child(leave)
	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := GLStyle.label(t, GLStyle.CAP, GLStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
		b.add_theme_stylebox_override("normal", GLStyle.box(GLStyle.BONE, 6, GLStyle.INK, 2, 0.35))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 240
		return b, Vector2(-270, 70))
	resized.connect(_layout)
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state.call_deferred(Net.view)


# --- Роли -----------------------------------------------------------------------------

func _hotseat() -> bool:
	return _v.get("hotseat", false) or Net.mode == "offline"


func _name(s: int) -> String:
	return _v["players"][s]["name"] if s >= 0 and s < _v["players"].size() else "?"


## Кто сейчас действует за этим экраном (на одном компьютере — тот, от кого ждут хода).
func _actor() -> int:
	if not _hotseat():
		return int(_v["you"])
	match _v["phase"]:
		"trim":
			var tl: Array = _v["trim_left"]
			return int(tl[0]) if not tl.is_empty() else int(_v["current"])
		"draft":
			var dq: Array = _v.get("draft_order", [])
			return int(dq[0]) if not dq.is_empty() else int(_v["current"])
		"prompt":
			return int(_v["prompt"].get("seat", _v["current"]))
		"react":
			var can: Array = _v["react"].get("can", [])
			return int(can[0]) if not can.is_empty() else int(_v["current"])
	return int(_v["current"])


func _send(kind: String, arg: Dictionary = {}) -> void:
	if _hotseat():
		arg["as"] = _actor()
	Net.send_action(kind, arg)


func _my_turn() -> bool:
	return _v.get("phase", "") == "play" and int(_v["current"]) == _actor()


func _my_hand() -> Array:
	var h: Array = _v["hands"][_me] if _me < _v["hands"].size() else []
	return h


# --- Состояние ------------------------------------------------------------------------

func _on_state(v: Dictionary) -> void:
	var prev := _v
	_v = v
	_me = _actor()
	if not _my_turn():
		_sel = -1
		_ev = {}
	if not _my_hand().has(_sel):
		_sel = -1
		_ev = {}
	var pr: Dictionary = v.get("prompt", {})
	if v["phase"] != "prompt" or int(pr.get("seat", -1)) != _me:
		_marked.clear()
	_marked = _marked.filter(func(c): return _my_hand().has(c))
	_update_info()
	_build_board()
	_sync_hand()
	_update_piles()
	_update_log()
	_build_panel()
	_layout.call_deferred()
	_sounds(prev)


func _update_info() -> void:
	if _v.is_empty():
		return
	var ph: String = _v.get("phase", "")
	if ph == "game_over":
		_top.info.text = "Конец партии"
	else:
		_top.info.text = "Ход: %s" % _name(_actor())


func _sounds(prev: Dictionary) -> void:
	var sig := ""
	for ch in _v["chars"]:
		sig += "%d%s;" % [ch["stack"].size(), "d" if ch["dead"] else ""]
	if prev.is_empty():
		_last_stack_sig = sig
		return
	if sig != _last_stack_sig:
		if sig.count("d") > _last_stack_sig.count("d"):
			Sfx.play("card_shove", -2)
		else:
			Sfx.play("card_place", -4)
		_last_stack_sig = sig
	if _v["phase"] == "react" and prev.get("phase", "") != "react":
		Sfx.play("card_flip", -4)
	if _v["phase"] == "game_over" and not _celebrated:
		_celebrated = true
		Sfx.victory()


# --- Семьи -------------------------------------------------------------------------------

func _opponents() -> Array:
	var out := []
	var n: int = _v["players"].size()
	for k in range(1, n):
		out.append((_me + k) % n)
	return out


func _chars_of(s: int) -> Array:
	var out := []
	var cv: Array = _v["chars"]
	for c in cv.size():
		if int(cv[c]["owner"]) == s and not cv[c]["removed"]:
			out.append(c)
	return out


func _family_name(s: int) -> String:
	var f := int(_v["fam"][s])
	return GLData.FAMILIES[f]["name"] if f < GLData.FAMILIES.size() else "Сборная семья"


func _family_color(s: int) -> Color:
	var f := int(_v["fam"][s])
	return GLData.FAMILIES[f]["color"] if f < GLData.FAMILIES.size() else GLStyle.SILVER


func _build_board() -> void:
	GLStyle.clear(_board)
	_stacks.clear()
	if _v.get("phase", "") == "draft":
		return
	var opps := _opponents()
	if _scale_for != opps.size():
		_scale_for = opps.size()
		_card_scale = 1.0
	var small := (76.0 if opps.size() <= 2 else 58.0) * _card_scale
	for s in opps:
		_board.add_child(_family_box(s, small, false))
	_board.add_child(_family_box(_me, 100.0 * maxf(_card_scale, 0.8), true))
	var centre := _centre_box(small)
	if centre:
		_board.add_child(centre)


## Центр стола (дополнения): гости без хозяина и истории.
func _centre_box(w: float) -> Control:
	var guests := _chars_of(-1)
	var sts: Array = _v.get("stories", [])
	if guests.is_empty() and sts.is_empty():
		return null
	var p := GLStyle.dark_panel(8)
	p.set_meta("seat", -1)
	var row := GLStyle.hbox(10)
	p.add_child(row)
	if not guests.is_empty():
		var gcol := GLStyle.vbox(4)
		gcol.add_child(GLStyle.label("Гости без хозяина", GLStyle.CAP, GLStyle.BONE_DIM, HORIZONTAL_ALIGNMENT_LEFT, "title"))
		var gr := GLStyle.hbox(6)
		for c in guests:
			var st := GLStack.new(c, _v["chars"][c], w)
			st.picked.connect(_on_char_picked)
			st.hovered.connect(_on_char_hover)
			_stacks[c] = st
			gr.add_child(st)
		gcol.add_child(gr)
		row.add_child(gcol)
	if not sts.is_empty():
		var scol := GLStyle.vbox(4)
		scol.add_child(GLStyle.label("Истории", GLStyle.CAP, GLStyle.BONE_DIM, HORIZONTAL_ALIGNMENT_LEFT, "title"))
		var sr := GLStyle.hbox(6)
		for st in sts:
			sr.add_child(_story_card(st, w))
		scol.add_child(sr)
		row.add_child(scol)
	return p


## Карта истории: щелчок — забрать (если можно). Под ней — чья она.
func _story_card(st: Dictionary, w: float) -> Control:
	var id := int(st["id"])
	var col := GLStyle.vbox(2)
	var tr := TextureRect.new()
	tr.texture = GLStyle.tex("st%d" % id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(w, w * GLStyle.CARD.y / GLStyle.CARD.x)
	var data: Dictionary = GLData.STORIES[id]
	var req: Array = data["req"]
	tr.tooltip_text = "%s\nНужно в семье (живые или мёртвые): %s. Отобрать — нужно больше, чем у владельца." % [data["name"], ", ".join(req.map(func(ic): return "«%s»" % GLData.ICON_NAMES.get(ic, ic)))]
	var can: bool = st.get("can", false)
	if st.get("pick", false) and int(_v.get("prompt", {}).get("seat", -1)) == _actor():
		var pv := id if _v["prompt"]["kind"] == "pick_story" else 1000 + id
		tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tr.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_send("gl_pick", {"v": pv}))
		tr.modulate = Color(1.2, 1.1, 0.85)
	elif can:
		tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tr.tooltip_text += "\nЩёлкните, чтобы забрать (тратит действие)."
		tr.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_send("gl_claim", {"st": id}))
		tr.modulate = Color(1.15, 1.1, 0.9)
	tr.mouse_entered.connect(func(): _show_preview(tr, func(ci: CanvasItem, r: Rect2): ci.draw_texture_rect(GLStyle.tex("st%d" % id), r, false)))
	tr.mouse_exited.connect(func(): _preview.visible = false)
	col.add_child(tr)
	var o := int(st["owner"])
	col.add_child(GLStyle.label("забрать!" if can else (_name(o) if o >= 0 else "ничья"), GLStyle.CAP, GLStyle.BLOOD_LIGHT if can else GLStyle.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	return col


func _family_box(s: int, w: float, mine: bool) -> Control:
	var p := GLStyle.dark_panel(8)
	p.set_meta("seat", s)
	var active: bool = int(_v["current"]) == s and _v["phase"] in ["play", "prompt", "react"]
	var sb := GLStyle.box(Color(GLStyle.COAL, 0.85), 6, GLStyle.BLOOD_LIGHT if active else Color(GLStyle.SILVER, 0.45), 2 if active else 1, 0.35)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var col := GLStyle.vbox(5)
	p.add_child(col)
	var head := GLStyle.hbox(8)
	var you := " (вы)" if mine and not _hotseat() else ""
	head.add_child(PlayerTag.make_seat(_v["players"], s, int(_v["you"]), GLStyle.CAP, GLStyle.BONE, you))
	var fl := GLStyle.label("· " + _family_name(s), GLStyle.CAP, _family_color(s).lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT, "italic")
	head.add_child(fl)
	var info := "  ✋%d/%d" % [int(_v["hand_counts"][s]), int(_v["limits"][s])]
	if _v["skip_draw"][s]:
		info += " · без добора"
	var il := GLStyle.label(info, GLStyle.CAP, GLStyle.BONE_DIM)
	il.tooltip_text = "Карт в руке / лимит добора"
	il.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(il)
	var total := _family_total(s)
	if total != 0:
		var tl := GLStyle.label("  † %+d" % total, GLStyle.CAP, GLStyle.BLOOD_LIGHT)
		tl.tooltip_text = "Сумма очков мёртвых персонажей (чем меньше — тем лучше)"
		tl.mouse_filter = Control.MOUSE_FILTER_PASS
		head.add_child(tl)
	col.add_child(head)
	var owned: Array = (_v.get("stories", []) as Array).filter(func(x): return int(x["owner"]) == s)
	if not owned.is_empty():
		var sl := GLStyle.label("История: " + ", ".join(owned.map(func(x): return "«%s»" % GLData.STORIES[int(x["id"])]["name"])), GLStyle.CAP, GLStyle.OK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT, "italic")
		col.add_child(sl)
	var row := GLStyle.hbox(6)
	for c in _chars_of(s):
		var st := GLStack.new(c, _v["chars"][c], w)
		st.picked.connect(_on_char_picked)
		st.hovered.connect(_on_char_hover)
		_stacks[c] = st
		row.add_child(st)
	col.add_child(row)
	return p


func _family_total(s: int) -> int:
	var t := 0
	for c in _chars_of(s):
		if _v["chars"][c]["dead"] or _v["chars"][c].get("undead", false):
			t += int(_v["chars"][c]["worth"])
	return t


# --- Рука -------------------------------------------------------------------------------

func _sync_hand() -> void:
	var hand := _my_hand()
	for c in _hand.keys():
		if not hand.has(c):
			(_hand[c] as Node).queue_free()
			_hand.erase(c)
	_order = _order.filter(func(c): return hand.has(c))
	for c in hand:
		if not _order.has(c):
			_order.append(c)
		if not _hand.has(c):
			var face := GLCardFace.new(int(c))
			var tc := K12TableCard.new("gl_%d" % c, true, face, GLCardFace.SIZE)
			tc.draggable = true
			var cc: int = c
			tc.clicked.connect(func(_t): _on_hand_click(cc))
			tc.drag_started.connect(func(_t): _on_drag_start(cc))
			tc.dropped.connect(func(_t, at: Vector2): _on_drop(cc, at))
			tc.hovered.connect(func(_t, on: bool): _on_hand_hover(cc, on))
			_hand_layer.add_child(tc)
			tc.position = _deck.position if _deck.size.x > 0 else Vector2(size.x * 0.5, size.y)
			_hand[c] = tc
	for c in _hand:
		var face := (_hand[c] as K12TableCard).get_child(0) as GLCardFace
		if face:
			face.marked = _marked.has(c) or c == _sel or c == int(_ev.get("with", -1))


func _layout_hand() -> void:
	var n := _order.size()
	if n == 0:
		return
	var left := _hand_left()
	var right := size.x - 16.0
	var w := GLCardFace.SIZE.x
	var step := minf(w + 8.0, (right - left - w) / maxf(1.0, n - 1))
	var total := w + step * (n - 1)
	var x0 := right - total
	for i in n:
		var tc: K12TableCard = _hand[_order[i]]
		if tc.dragging:
			continue
		var lift := 18.0 if _order[i] == _sel else 0.0
		tc.z_index = i
		tc.move_to(Vector2(x0 + w * 0.5 + step * i, size.y - GLCardFace.SIZE.y * 0.5 - 12 - lift), 0.0, 1.0, 0.22)


func _hand_left() -> float:
	if _centre_low:
		for b in _board.get_children():
			if int(b.get_meta("seat", -2)) == -1:
				return b.position.x + b.size.x + 16.0
	var my := _my_box()
	return (my.position.x + my.size.x + 16.0) if my else size.x * 0.5


func _my_box() -> Control:
	for b in _board.get_children():
		if int(b.get_meta("seat", -1)) == _me:
			return b
	return null


# --- Раскладка --------------------------------------------------------------------------

func _layout() -> void:
	if _v.is_empty():
		return
	var drafting: bool = _v.get("phase", "") == "draft"
	_board.visible = not drafting
	for pile in [_deck, _deck_label, _discard, _discard_bg, _discard_label]:
		pile.visible = not drafting
	_log_panel.visible = not drafting
	if drafting:
		_panel.reset_size()
		_panel.position = Vector2((size.x - _panel.size.x) * 0.5, TopBar.HEIGHT + maxf(16.0, (size.y - TopBar.HEIGHT - _panel.size.y) * 0.5))
		_layout_hand()
		return
	_discard_bg.visible = not _v["discard"].is_empty()
	var opps := _opponents()
	var boxes := {}
	for b in _board.get_children():
		(b as Control).reset_size()
		boxes[int(b.get_meta("seat", -1))] = b
	# соперники сверху: в ряд столько, сколько влезает по ширине (обычно 2–3)
	var y := TopBar.HEIGHT + 8.0
	var rows: Array = []
	var cur: Array = []
	var cur_w := 0.0
	for s in opps:
		var bw: float = (boxes[s] as Control).size.x
		if not cur.is_empty() and cur_w + 14.0 + bw > size.x - 32.0:
			rows.append(cur)
			cur = []
			cur_w = 0.0
		cur_w += (14.0 if not cur.is_empty() else 0.0) + bw
		cur.append(s)
	if not cur.is_empty():
		rows.append(cur)
	# поровну по рядам: 4 соперника — 2 + 2, а не 3 + 1
	if rows.size() == 2 and opps.size() == 4:
		rows = [opps.slice(0, 2), opps.slice(2, 4)]
	for row: Array in rows:
		var tw := 0.0
		var th := 0.0
		for s in row:
			tw += (boxes[s] as Control).size.x
			th = maxf(th, (boxes[s] as Control).size.y)
		var gap := 14.0
		var x := (size.x - tw - gap * (row.size() - 1)) * 0.5
		for s in row:
			var b: Control = boxes[s]
			b.position = Vector2(x, y)
			x += b.size.x + gap
		y += th + 8
	var centre: Control = boxes.get(-1)
	var my: Control = boxes.get(_me)
	# соперники в два ряда — гостям и историям сверху места нет: кладём их внизу, справа от своей семьи
	_centre_low = centre != null and my != null and rows.size() >= 2
	if centre and not _centre_low:
		centre.position = Vector2((size.x - centre.size.x) * 0.5, y)
		y += centre.size.y + 8
	var top_end := y
	if my:
		my.position = Vector2(16, size.y - my.size.y - 12)
		if _centre_low:
			centre.position = Vector2(my.position.x + my.size.x + 14, size.y - centre.size.y - 12)
	var mid_top := top_end + 6
	var mid_bottom := (my.position.y if my else size.y - 200) - 8
	# середине нужно место под панель хода — иначе всё мельче и раскладываем заново
	_panel.reset_size()
	if mid_bottom - mid_top < _panel.size.y + 24.0 and _card_scale > 0.62:
		_card_scale -= 0.1
		_build_board()
		_layout.call_deferred()
		return
	# колода и сброс — слева посередине
	var ch := clampf(mid_bottom - mid_top - 24, 70, 150)
	var cw := ch * GLStyle.CARD.x / GLStyle.CARD.y
	_deck.size = Vector2(cw, ch)
	_deck.position = Vector2(20, mid_top)
	_deck_label.position = Vector2(20, mid_top + ch + 2)
	_deck_label.size = Vector2(cw, 36)
	_discard.size = Vector2(cw, ch)
	_discard.position = Vector2(30 + cw, mid_top)
	_discard_bg.size = _discard.size
	_discard_bg.position = _discard.position
	_discard_label.position = Vector2(30 + cw, mid_top + ch + 2)
	_discard_label.size = Vector2(cw, 36)
	# Во время набора семьи журнал пуст и не должен отнимать место у выбора персонажей.
	_log_panel.visible = _v.get("phase", "") != "draft"
	# журнал — справа посередине
	_log_panel.size = Vector2(minf(330, size.x * 0.26), maxf(90, mid_bottom - mid_top))
	_log_panel.position = Vector2(size.x - _log_panel.size.x - 16, mid_top)
	# панель действия — между ними
	_panel.reset_size()
	var px0 := 40 + cw * 2
	var px1 := _log_panel.position.x - 10 if _log_panel.visible else size.x - 16.0
	var py := mid_top + maxf(0, (mid_bottom - mid_top - _panel.size.y) * 0.5)
	py = minf(py, mid_bottom - _panel.size.y)  # не залезать на свою семью
	_panel.position = Vector2(px0 + maxf(0, (px1 - px0 - _panel.size.x) * 0.5), maxf(TopBar.HEIGHT + 8.0, py))
	_layout_hand()


func _update_piles() -> void:
	_deck_label.text = "Колода\n%d" % int(_v["deck_left"])
	var d: Array = _v["discard"]
	_discard.texture = GLStyle.card_tex(int(d[-1])) if not d.is_empty() else null
	_discard_bg.visible = not d.is_empty()
	_discard_label.text = "Сброс\n%d" % d.size()


func _update_log() -> void:
	var lines := []
	for e in _v["log"]:
		var s := int(e.get("seat", -1))
		var col := _family_color(s).lightened(0.35) if s >= 0 and s < _v["fam"].size() else GLStyle.BONE
		lines.append("[color=#%s]•[/color] %s" % [col.to_html(false), str(e["text"])])
	_log.text = "\n".join(lines)


# --- Цели и проверки на клиенте ------------------------------------------------------------

func _cd(card: int) -> Dictionary:
	return GLData.CARDS[card]


func _legal(card: int) -> Dictionary:
	return (_v.get("legal", {}) as Dictionary).get(card, {})


func _free_covers(card: int, t: int) -> bool:
	var fr: Dictionary = _v["free"]
	if fr.is_empty() or int(fr.get("left", 0)) <= 0:
		return false
	var list: Array = fr.get("cards", [])
	if not list.is_empty() and not list.has(card):
		return false
	if fr.get("ud_only", false) and _cd(card)["t"] != "D":
		return false
	var ft := int(fr.get("target", -1))
	return ft < 0 or ft == t


## Подходит ли персонаж c как цель (для события — на текущем шаге выбора). Список целей считает сервер.
func _valid_target(card: int, c: int) -> bool:
	if card < 0 or c < 0:
		return false
	var e := _legal(card)
	if e.has("t2") and int(_ev.get("t", -1)) >= 0:
		return c in (e["t2"] as Dictionary).get(int(_ev["t"]), [])
	if e.has("pick"):
		return int(_ev.get("pick", -1)) >= 0 and c in (e["pick"] as Dictionary).get(int(_ev["pick"]), [])
	if e.has("with") and int(_ev.get("t", -1)) >= 0:
		return false
	return c in e.get("t", [])


## Подсветка вариантов в выборе персонажа (prompt pick_char).
func _pick_options() -> Array:
	var pr: Dictionary = _v.get("prompt", {})
	if _v.get("phase", "") == "prompt" and pr.get("kind", "") == "pick_char" and int(pr["seat"]) == _actor():
		return pr["options"]
	return []


func _refresh_targets() -> void:
	var card := _drag if _drag >= 0 else _sel
	for c in _stacks:
		var st: GLStack = _stacks[c]
		st.highlight = 1.0 if (_my_turn() and _valid_target(card, c)) or c in _pick_options() else 0.0
		st.selected = c == int(_ev.get("t", -1)) or c == int(_ev.get("t2", -1))
	if _v["phase"] == "trim":
		var tl: Array = _v["trim_left"]
		for c in _stacks:
			(_stacks[c] as GLStack).highlight = 1.0 if (_actor() in tl and int(_v["chars"][c]["owner"]) == _actor()) else 0.0


# --- Ввод ---------------------------------------------------------------------------------

func _on_hand_click(card: int) -> void:
	_drag = -1  # нажатие без перетаскивания: drag_started был, dropped не будет — иначе пропадает крупный просмотр
	var pr: Dictionary = _v.get("prompt", {})
	if _v["phase"] == "prompt" and int(pr.get("seat", -1)) == _actor() and pr.get("kind", "") in ["discard", "give", "refresh"]:
		if _marked.has(card):
			_marked.erase(card)
		elif (pr["kind"] == "refresh" and int(pr["n"]) <= 0) or _marked.size() < int(pr["n"]):
			_marked.append(card)
		Sfx.play("card_slide", -8)
		_sync_hand()
		_build_panel()
		_layout.call_deferred()
		return
	if not _my_turn():
		return
	# шаг события «Поворот судьбы»: выбор модификатора из руки
	if _sel >= 0 and _legal(_sel).has("with") and int(_ev.get("t", -1)) >= 0 and card != _sel:
		if card in _legal(_sel)["with"]:
			_send("gl_play", {"card": _sel, "target": int(_ev["t"]), "extra": {"with": card}})
			_sel = -1
			_ev = {}
		return
	_sel = -1 if _sel == card else card
	_ev = {}
	Sfx.play("card_slide", -8)
	_sync_hand()
	_build_panel()
	_refresh_targets()
	_layout.call_deferred()


func _on_drag_start(card: int) -> void:
	_drag = card
	_refresh_targets()


func _on_drop(card: int, at: Vector2) -> void:
	_drag = -1
	var gp := _hand_layer.get_global_transform() * at
	var target := -1
	for c in _stacks:
		var st: GLStack = _stacks[c]
		if st.get_global_rect().grow(6).has_point(gp):
			target = c
			break
	if target >= 0 and _my_turn():
		var cd := _cd(card)
		if cd["t"] in ["M", "D"] and target in _legal(card).get("t", []):
			_send("gl_play", {"card": card, "target": target})
			_sel = -1
			_ev = {}
		elif cd["t"] == "E":
			_sel = card
			_ev = {}
			_on_char_picked(target)
	else:
		# перестановка в руке: куда бросили — туда и встаёт
		if gp.y > size.y - GLCardFace.SIZE.y - 40:
			var idx := _order.find(card)
			_order.remove_at(idx)
			var k := 0
			for i in _order.size():
				if (_hand[_order[i]] as K12TableCard).center().x < at.x:
					k = i + 1
			_order.insert(k, card)
		elif _my_turn() and _cd(card)["t"] == "E":
			_sel = card  # бросили событие на стол — выбираем его
			_ev = {}
	_sync_hand()
	_build_panel()
	_refresh_targets()
	_layout.call_deferred()


func _on_char_picked(c: int) -> void:
	var ph: String = _v["phase"]
	if ph == "trim":
		if _actor() in _v["trim_left"] and int(_v["chars"][c]["owner"]) == _actor():
			_send("gl_trim", {"c": c})
		return
	if c in _pick_options():
		_send("gl_pick", {"v": c})
		return
	if not _my_turn() or _sel < 0:
		return
	if not _valid_target(_sel, c):
		return
	var e := _legal(_sel)
	if e.has("t2"):
		if int(_ev.get("t", -1)) < 0:
			_ev["t"] = c  # дальше — второй персонаж
		else:
			_send("gl_play", {"card": _sel, "target": int(_ev["t"]), "extra": {"t2": c}})
			_sel = -1
			_ev = {}
	elif e.has("with"):
		_ev["t"] = c  # дальше — модификатор из руки
	elif e.has("pick"):
		_send("gl_play", {"card": _sel, "target": c, "extra": {"pick": int(_ev["pick"])}})
		_sel = -1
		_ev = {}
	elif _cd(_sel)["t"] == "E":
		_ev["t"] = c  # событие (красная карта) — цель выбрана, срабатывает по кнопке «Применить»
	else:
		_send("gl_play", {"card": _sel, "target": c})
		_sel = -1
		_ev = {}
	_sync_hand()
	_build_panel()
	_refresh_targets()
	_layout.call_deferred()


# --- Крупный просмотр -------------------------------------------------------------------

func _on_char_hover(c: int, on: bool) -> void:
	_hover_char = c if on else -1
	if on:
		_show_preview(_stacks[c], func(ci: CanvasItem, r: Rect2):
			var ch: Dictionary = _v["chars"][c]
			ci.draw_texture_rect(GLStyle.tex(str(ch.get("img", "ch%d" % int(ch["id"])))), r, false)
			for card in ch["stack"]:
				ci.draw_texture_rect(GLStyle.card_tex(int(card)), r, false))
	else:
		_preview.visible = false


func _on_hand_hover(card: int, on: bool) -> void:
	if on and _drag < 0:
		_show_preview(_hand[card], func(ci: CanvasItem, r: Rect2):
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.81, 0.79, 0.82, 0.14)
			sb.set_corner_radius_all(8)
			ci.draw_style_box(sb, r)
			ci.draw_texture_rect(GLStyle.card_tex(card), r, false))
	else:
		_preview.visible = false


func _show_preview(near: Control, drawer: Callable) -> void:
	for ch in _preview.get_children():
		ch.queue_free()
	var h := minf(size.y * 0.62, 440.0)
	var sz := Vector2(h * GLStyle.CARD.x / GLStyle.CARD.y, h)
	var pic := Control.new()
	pic.size = sz
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func():
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0)
		sh.shadow_color = Color(0, 0, 0, 0.6)
		sh.shadow_size = 18
		pic.draw_style_box(sh, Rect2(Vector2.ZERO, sz))
		drawer.call(pic, Rect2(Vector2.ZERO, sz)))
	_preview.add_child(pic)
	_preview.size = sz
	var r := near.get_global_rect()
	var x := r.end.x + 14 if r.get_center().x < size.x * 0.5 else r.position.x - sz.x - 14
	var y := clampf(r.get_center().y - sz.y * 0.5, 8, size.y - sz.y - 8)
	_preview.position = Vector2(clampf(x, 8, size.x - sz.x - 8), y)
	_preview.visible = true


## Окно со всеми картами сброса.
func _show_discard() -> void:
	var d: Array = _v.get("discard", [])
	if d.is_empty():
		return
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 70
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			layer.queue_free())
	layer.add_child(dim)
	var p := GLStyle.panel(16)
	p.position = Vector2(60, 50)
	p.size = size - Vector2(120, 100)
	layer.add_child(p)
	var col := GLStyle.vbox(8)
	p.add_child(col)
	col.add_child(GLStyle.label("Сброс · %d карт (сверху — последние)" % d.size(), GLStyle.BODY, GLStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(flow)
	for i in range(d.size() - 1, -1, -1):
		var f := GLCardFace.new(int(d[i]))
		f.mouse_filter = Control.MOUSE_FILTER_PASS
		f.tooltip_text = GLData.card_name(int(d[i]))
		flow.add_child(f)
	var close := GLStyle.button("Закрыть", GLStyle.BODY)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


# --- Панель действия -------------------------------------------------------------------

func _build_panel() -> void:
	GLStyle.clear(_panel)
	var col := GLStyle.vbox(8)
	_panel.add_child(col)
	var ph: String = _v["phase"]
	var actor := _actor()
	var cur := int(_v["current"])
	var who := ("(за %s) " % _name(actor)) if _hotseat() else ""
	match ph:
		"trim":
			if actor in _v["trim_left"]:
				col.add_child(_line(who + "Отложите одного персонажа: щёлкните по нему в своей семье.", true))
				if _v["players"].size() >= 5:
					col.add_child(_line("Из отложенных соберётся семья для пятого игрока.", false))
			else:
				col.add_child(_line("Остальные откладывают персонажей…", true))
		"draft":
			_build_draft(col, who)
		"play":
			if actor == cur:
				_build_turn(col, who)
			else:
				col.add_child(_line("Ходит %s · действий: %d" % [_name(cur), int(_v["plays_left"])], true))
		"prompt":
			_build_prompt(col, who)
		"react":
			_build_react(col, who)
		"game_over":
			_build_results(col)
	_refresh_targets()
	_layout.call_deferred()


## Gloomier: по очереди выбираем персонажей Хемлок-Холла (по 4 каждому).
func _build_draft(col: VBoxContainer, who: String) -> void:
	var dq: Array = _v.get("draft_order", [])
	if dq.is_empty():
		return
	var s := int(dq[0])
	if s != _actor():
		col.add_child(_line("%s выбирает персонажа…" % _name(s), true))
		return
	var picked: int = _v["chars"].filter(func(ch): return ch["kind"] == "char" and int(ch["owner"]) == s).size()
	col.add_child(_line(who + "Выберите персонажа · %d из 4" % (picked + 1), true))
	col.add_child(_line("Остальные вернутся в колоду и могут выпасть другим игрокам.", false))
	var flow := GLStyle.hbox(16)
	flow.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in _v.get("draft_options", []):
		var tr := TextureRect.new()
		tr.texture = GLStyle.tex("ch%d" % int(id))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(112, 161)
		tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tr.tooltip_text = GLData.char_name(int(id))
		var cid := int(id)
		tr.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_send("gl_draft", {"id": cid}))
		tr.mouse_entered.connect(func(): _show_preview(tr, func(ci: CanvasItem, r: Rect2): ci.draw_texture_rect(GLStyle.tex("ch%d" % cid), r, false)))
		tr.mouse_exited.connect(func(): _preview.visible = false)
		var option := GLStyle.vbox(4)
		option.add_child(tr)
		var name_label := GLStyle.label(GLData.char_name(cid), GLStyle.CAP, GLStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
		name_label.custom_minimum_size.x = 112
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		option.add_child(name_label)
		flow.add_child(option)
	col.add_child(flow)
	col.add_child(_line("Игровые карты будут розданы, когда все соберут семьи.", false))


func _build_turn(col: VBoxContainer, who: String) -> void:
	var left := int(_v["plays_left"])
	var head := "%sВаш ход · действий: %d" % [who, left]
	if left > 0 and bool(_v["ud_ok"]):
		head += " · можно сыграть смерть"
	col.add_child(_line(head, true))
	var fr: Dictionary = _v["free"]
	if not fr.is_empty():
		var fl: String
		if fr.get("ud_only", false):
			fl = "Бесплатно: безвременная смерть на этого персонажа."
		elif (fr.get("cards", []) as Array).is_empty():
			fl = "Бесплатных карт: %d." % int(fr.get("left", 0))
		else:
			fl = "Бесплатно можно сыграть: %s." % ", ".join((fr["cards"] as Array).map(func(c): return "«%s»" % GLData.card_name(int(c))))
		col.add_child(_line(fl, false, GLStyle.BLOOD))
	if _v["events_blocked"]:
		col.add_child(_line("Пока сверху лежит «Застрял в поезде» / «Попал в тюрьму», события играть нельзя.", false, GLStyle.MUTED))
	if _sel >= 0:
		col.add_child(_line(_hint_for(_sel), false, GLStyle.BLOOD))
		var cd := _cd(_sel)
		var e := _legal(_sel)
		if cd["t"] == "E":
			var s2 := _sel
			if e.has("modes"):
				var mr := GLStyle.hbox(8)
				mr.alignment = BoxContainer.ALIGNMENT_CENTER
				for m in [["free", "Бесплатная карта"], ["chaos", "Гости и истории — ничьи"]]:
					var mb := GLStyle.button(m[1], GLStyle.CAP)
					var mode: String = m[0]
					mb.pressed.connect(func():
						_send("gl_play", {"card": s2, "target": -1, "extra": {"mode": mode}})
						_sel = -1)
					mr.add_child(mb)
				col.add_child(mr)
			var simple: bool = e.has("t") and not (e.has("t2") or e.has("with") or e.has("pick") or e.has("go"))
			if simple:
				var tgt := int(_ev.get("t", -1))
				var ap := GLStyle.primary("Применить «%s»%s" % [cd["name"], (" → " + str(_v["chars"][tgt]["name"])) if tgt >= 0 else ""], GLStyle.BODY)
				ap.disabled = tgt < 0
				ap.tooltip_text = "Сначала выберите персонажа" if tgt < 0 else ""
				ap.pressed.connect(func():
					_send("gl_play", {"card": s2, "target": tgt})
					_sel = -1
					_ev = {})
				ap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				col.add_child(ap)
			if e.get("go", false):
				var go := GLStyle.primary("Применить «%s»" % cd["name"], GLStyle.BODY)
				go.pressed.connect(func():
					_send("gl_play", {"card": s2, "target": -1})
					_sel = -1)
				go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				col.add_child(go)
			if e.has("pick") and int(_ev.get("pick", -1)) < 0:
				col.add_child(_card_buttons((e["pick"] as Dictionary).keys(), func(c):
					_ev["pick"] = c
					_build_panel(), "В сбросе нет подходящих смертей."))
			if e.has("picks"):
				col.add_child(_card_buttons(e["picks"], func(c):
					_send("gl_play", {"card": s2, "target": -1, "extra": {"pick": c}})
					_sel = -1, "В сбросе нет подходящих карт."))
			if e.has("stories"):
				var row0 := HFlowContainer.new()
				for st in e["stories"]:
					var b := GLStyle.button("«%s»" % GLData.STORIES[int(st)]["name"], GLStyle.CAP)
					var sid := int(st)
					b.pressed.connect(func():
						_send("gl_play", {"card": s2, "target": -1, "extra": {"st": sid}})
						_sel = -1)
					row0.add_child(b)
				col.add_child(row0)
	else:
		col.add_child(_line("Перетащите карту на персонажа или щёлкните карту, а затем персонажа. Минусы — своим, плюсы — чужим.", false, GLStyle.MUTED))
	var row := GLStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if not fr.is_empty():
		var skip := GLStyle.button("Не играть бесплатную карту", GLStyle.CAP)
		skip.pressed.connect(func(): _send("gl_skip_free"))
		row.add_child(skip)
	var dh := GLStyle.button("Сбросить руку", GLStyle.CAP)
	dh.disabled = left <= 0 or _my_hand().is_empty()
	dh.tooltip_text = "Тратит действие; новые карты — только при доборе в конце хода"
	dh.theme_type_variation = "QuietButton"
	dh.pressed.connect(func():
		LeaveGuard.ask(dh, "Сбросить всю руку?", "Это действие. Новые карты придут при доборе в конце хода.", "Сбросить", func(): _send("gl_discard_hand"), "Оставить"))
	row.add_child(dh)
	var end := GLStyle.primary("Закончить ход", GLStyle.BODY, 180)
	end.pressed.connect(func():
		_sel = -1
		_ev = {}
		_send("gl_end"))
	row.add_child(end)
	col.add_child(row)


## Подсказка к выбранной карте.
func _hint_for(card: int) -> String:
	var cd := _cd(card)
	match cd["t"]:
		"M":
			return "«%s»: выберите живого персонажа." % cd["name"]
		"D":
			if not bool(_v["ud_ok"]) and not _free_covers(card, -1):
				return "Смерть — только первым действием хода."
			return "«%s»: выберите персонажа с отрицательным счётом." % cd["name"]
	var f: String = str(cd["fx"][0]).split(":")[0]
	match f:
		"stormy":
			return "Возьмите 4 карты, одну из них можно сыграть бесплатно, потом сбросьте лишнее до лимита."
		"root_of_evil":
			return "Возьмите по случайной карте у каждого соперника. С иконкой денег — их можно сразу сыграть бесплатно."
		"extra_plays":
			return "Ещё 2 действия в этом ходу, смерти — любым из них."
		"remove_top_mod":
			return "Выберите персонажа: верхний модификатор уйдёт в сброс."
		"remove_all_mods":
			return "Выберите персонажа: все модификаторы уйдут в сброс."
		"remove_living_char":
			return "Выберите живого персонажа — он уйдёт из игры."
		"swap_top_mod_from_hand":
			return "Выберите персонажа, затем модификатор из руки — он встанет вместо верхнего." if int(_ev.get("t", -1)) < 0 else "Теперь щёлкните модификатор у себя в руке."
		"swap_top_mods":
			return "Выберите двух персонажей — их верхние модификаторы поменяются." if int(_ev.get("t", -1)) < 0 else "Теперь второго персонажа."
		"ud_from_discard":
			return "Выберите смерть из сброса, затем персонажа с иконкой любви или отрицательным счётом." if int(_ev.get("pick", -1)) < 0 else "Теперь персонажа."
		"second_chance":
			return "Выберите мёртвого персонажа — смерть снимется, он оживёт. (Или держите карту, чтобы отменить чужую смерть.)"
		"cancel_event":
			return "Эту карту играют в ответ, когда кто-то разыгрывает событие."
		"remove_own_guest_cancel":
			return "Эту карту играют в ответ на любую карту: ваш гость уезжает, а карта отменяется."
		"unlimited_plays_discard_each":
			return "В этот ход играйте сколько угодно карт, но за каждую сбрасывайте карту с руки."
		"draw2_per_guest_play_any":
			return "Возьмите по 2 карты за каждого своего живого гостя и сыграйте сколько угодно из них бесплатно."
		"swap_all_mods_with_guest":
			return "Выберите живого персонажа, затем живого гостя — их модификаторы поменяются." if int(_ev.get("t", -1)) < 0 else "Теперь гостя."
		"take_guest_from_family":
			return "Выберите гостя из чужой семьи — он переедет к вам."
		"move_guest_between":
			return "Выберите живого гостя, затем любого персонажа семьи, куда он переедет." if int(_ev.get("t", -1)) < 0 else "Теперь персонажа семьи, куда переедет гость."
		"mod_on_dead":
			return "В этот ход один модификатор можно сыграть на мёртвого персонажа."
		"swap_living_chars_with_opponent":
			return "Выберите живого персонажа соперника, затем своего — они поменяются семьями." if int(_ev.get("t", -1)) < 0 else "Теперь своего персонажа."
		"play_event_or_undead_from_discard":
			return "Выберите в сбросе событие или модификатор-нежить — сыграете его бесплатно."
		"claim_any_story_then_free_play":
			return "Заберите любую историю без требований, затем сыграйте одну карту бесплатно."
		"swap_hands":
			return "Выберите персонажа соперника — обменяетесь с ним руками и возьмёте 2 карты."
		"free_ud_or_remove_undead":
			return "«Сыграть» — бесплатная безвременная смерть; или щёлкните нежить, чтобы убрать её из игры."
		"everyone_removes_own_char":
			return "Каждый игрок убирает из игры одного своего персонажа."
		"dramatic":
			return "Выберите: сыграть любую карту бесплатно (даже смерть) — или все гости и истории станут ничьими."
		"midnight":
			return "Возьмите 3 карты: модификаторы и смерти сразу лягут на вашу семью, остальное — в сброс."
		"plot_twist":
			return "Возьмите 3 карты и заберите историю или живого гостя."
		"whodunnit":
			return "Возьмите по карте за каждую лупу в семье, сыграйте одну бесплатно, затем сбросьте до лимита."
		"others_discard_family_icons":
			return "Остальные сбрасывают столько карт, сколько у вас в семье кинжалов или луп (что больше)."
	return ""


## Ряд кнопок с названиями карт (выбор из сброса).
func _card_buttons(cards: Array, on_pick: Callable, empty_text: String) -> Control:
	var row := HFlowContainer.new()
	row.custom_minimum_size.x = 520
	for c in cards:
		var b := GLStyle.button(GLData.card_name(int(c)), GLStyle.CAP)
		var cc := int(c)
		b.pressed.connect(func(): on_pick.call(cc))
		b.mouse_entered.connect(func(): _show_preview(b, func(ci: CanvasItem, r: Rect2):
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.81, 0.79, 0.82, 0.14)
			sb.set_corner_radius_all(8)
			ci.draw_style_box(sb, r)
			ci.draw_texture_rect(GLStyle.card_tex(cc), r, false)))
		b.mouse_exited.connect(func(): _preview.visible = false)
		row.add_child(b)
	if cards.is_empty() and empty_text != "":
		row.add_child(_line(empty_text, false, GLStyle.MUTED))
	return row


func _build_prompt(col: VBoxContainer, who: String) -> void:
	var pr: Dictionary = _v["prompt"]
	if pr.is_empty():
		return
	var s := int(pr["seat"])
	if s != _actor():
		col.add_child(_line("%s выбирает…" % _name(s), true))
		return
	if pr["kind"] in ["pick_char", "pick_discard", "pick_story"]:
		var what: String = {"plot": "Выберите историю или живого гостя — он перейдёт к вам.", "free_guest": "Выберите гостя — он станет ничьим.", "claim": "Выберите историю — она ваша без требований.", "take_guest": "Выберите гостя — он переедет в вашу семью.", "revive": "Выберите своего мёртвого персонажа — он оживёт.", "peel": "Выберите персонажа-нежить — верхний модификатор уйдёт в сброс.", "remove_char": "Выберите своего персонажа, который уйдёт из игры."}.get(str(pr.get("then", "")), "Выберите карту из сброса — она придёт вам в руку.")
		col.add_child(_line(who + what, true))
		if pr["kind"] == "pick_discard":
			col.add_child(_card_buttons(pr["options"], func(c): _send("gl_pick", {"v": c}), ""))
		if pr.get("optional", true):
			var skip := GLStyle.button("Не надо", GLStyle.CAP)
			skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			skip.pressed.connect(func(): _send("gl_pick", {"v": -1}))
			col.add_child(skip)
		return
	var n := int(pr["n"])
	var text := ""
	match pr["kind"]:
		"discard":
			text = "Сбросьте %d %s: щёлкните их в руке." % [n, _cards_word(n)]
		"give":
			text = "Отдайте %d %s игроку %s: щёлкните их в руке." % [n, _cards_word(n), _name(int(pr["to"]))]
		"refresh":
			text = ("Отметьте до %d карт для сброса (можно ни одной) — потом доберёте до лимита." % n) if n > 0 else "Отметьте карты, которые хотите сбросить (можно ни одной), — потом доберёте до лимита."
	col.add_child(_line(who + text, true))
	var ok := GLStyle.primary("Готово (%d)" % _marked.size() if pr["kind"] == "refresh" else "Готово · %d из %d" % [_marked.size(), n], GLStyle.BODY, 200)
	ok.disabled = pr["kind"] != "refresh" and _marked.size() != n
	if ok.disabled:
		ok.theme_type_variation = ""
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func():
		_send("gl_choose", {"cards": _marked.duplicate()})
		_marked.clear())
	col.add_child(ok)


func _cards_word(n: int) -> String:
	if n % 10 == 1 and n % 100 != 11:
		return "карту"
	if n % 10 in [2, 3, 4] and not n % 100 in [12, 13, 14]:
		return "карты"
	return "карт"


func _build_react(col: VBoxContainer, who: String) -> void:
	var rv: Dictionary = _v["react"]
	var card := int(rv["card"])
	var t := int(rv["target"])
	var what := "«%s»" % GLData.card_name(card)
	if t >= 0 and t < _v["chars"].size():
		what += " → " + str(_v["chars"][t].get("name", ""))
	col.add_child(_line("%s играет %s" % [_name(int(rv["actor"])), what], true))
	var can: Array = rv.get("can", [])
	if _actor() in can:
		var resp := GLData.card_name(int((rv.get("resp", {}) as Dictionary).get(_actor(), GLData.SECOND_CHANCE)))
		col.add_child(_line(who + "У вас есть «%s» — отменить?" % resp, false, GLStyle.BLOOD))
		var row := GLStyle.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var yes := GLStyle.primary("Отменить картой «%s»" % resp, GLStyle.BODY)
		yes.pressed.connect(func(): _send("gl_respond", {"use": true}))
		row.add_child(yes)
		var no := GLStyle.button("Пусть будет", GLStyle.BODY)
		no.pressed.connect(func(): _send("gl_respond", {"use": false}))
		row.add_child(no)
		col.add_child(row)
	else:
		col.add_child(_line("Можно ответить… несколько секунд.", false, GLStyle.MUTED))


func _build_results(col: VBoxContainer) -> void:
	var w: Array = _v["winners"]
	var names := w.map(func(s): return _name(int(s)))
	col.add_child(GLStyle.label(("Самая несчастная семья — %s!" if names.size() == 1 else "Ничья: %s!") % ", ".join(names), GLStyle.H1, GLStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "title"))
	var order := range(_v["players"].size())
	order.sort_custom(func(a, b): return int(_v["finals"][a]) < int(_v["finals"][b]))
	for s in order:
		col.add_child(_line("%s · %s: %+d" % [_name(s), _family_name(s), int(_v["finals"][s])], s in w))
	var row2 := GLStyle.hbox(12)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	if Net.is_host():
		var again := GLStyle.primary("Новая партия", GLStyle.BODY, 190)
		again.pressed.connect(Net.end_game)
		row2.add_child(again)
		var back := GLStyle.button("К выбору игры" if Net.is_party() else "В меню", GLStyle.BODY, 190)
		back.pressed.connect(func(): app.back_to_menu())
		row2.add_child(back)
	else:
		var leave := GLStyle.button("Покинуть пати", GLStyle.BODY, 190)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		row2.add_child(leave)
	col.add_child(row2)


func _line(t: String, bold: bool, color: Color = GLStyle.INK) -> Label:
	var l := GLStyle.label(t, GLStyle.BODY if bold else GLStyle.CAP, color, HORIZONTAL_ALIGNMENT_CENTER, "bold" if bold else "regular")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	return l
