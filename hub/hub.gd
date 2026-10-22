extends Control
## Стартовый экран: неоновая ретро-комната (NeonRoom) со шкафом настольных игр и интерфейс поверх неё.
##
## Наведение на коробку в шкафу — она выезжает; клик — вылетает к игроку обложкой вперёд,
## справа — карточка игры («Играть» / «Играть всей пати»). Слева — пати с друзьями (создать / войти,
## участники, код, приглашение). Хост выбирает игру — все участники пати переходят в её лобби.
## Пати не распадается, когда хост возвращает всех сюда или меняет игру.

const MENU_MUSIC := ["res://hub/audio/mysterywave.mp3", "res://hub/audio/virtual_rush.mp3"]
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var _room: NeonRoom
var _ui: Control  # пати, кнопки, заголовок
var _card: Control  # карточка выбранной игры
var _status: Label
var _code: LineEdit
var _leaving := false
var _selected := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # клики мимо панелей — в 3D-комнату
	get_tree().root.theme = HubStyle.theme()
	Sfx.start_music()
	Sfx.set_playlist(MENU_MUSIC)  # синтвейв в духе неоновых 80-х
	# отладочные аргументы ведут сразу в игру
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			_open_scene(HubGames.LIST[0])
			return
	_room = NeonRoom.new()
	add_child(_room)
	_room.box_selected.connect(_on_box_selected)
	_room.box_released.connect(_on_box_released)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_card = Control.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	Net.lobby_changed.connect(_on_lobby)
	Net.party_game_changed.connect(_on_party_game)
	Net.session_closed.connect(_on_closed)
	Net.status_changed.connect(_set_status)
	_rebuild()


func _rebuild() -> void:
	if _leaving:
		return
	HubStyle.clear(_ui)
	# заголовок
	var head := HubStyle.vbox(0)
	head.position = Vector2(26, 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(HubStyle.neon_label("PARTY WORLD", 34, HubStyle.PINK))
	_ui.add_child(head)
	# пати слева
	var in_party := Net.is_party() and not Net.lobby_view.is_empty()
	var party := _party_panel() if in_party else _party_create_panel()
	party.position = Vector2(22, 112)
	_ui.add_child(party)
	# подсказка снизу по центру
	var hint := HubStyle.label("Выберите игру в шкафу — наведите и нажмите на коробку" if not in_party or Net.is_host() else "Игру запускает ведущий пати — откройте коробку и предложите ему свою", 14, HubStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.offset_top = -40
	hint.offset_bottom = -16
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(hint)
	# настройки и выход — справа сверху
	var top := HubStyle.hbox(8)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_left = -300
	top.offset_right = -20
	top.offset_top = 18
	top.alignment = BoxContainer.ALIGNMENT_END
	var settings := HubStyle.button("Настройки", 15)
	settings.pressed.connect(func(): add_child(SettingsScreen.new()))
	top.add_child(settings)
	var quit := HubStyle.button("Выход", 15)
	quit.pressed.connect(func(): get_tree().quit())
	top.add_child(quit)
	_ui.add_child(top)
	_status = HubStyle.label("", 14, HubStyle.YELLOW)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 280
	_status.position = Vector2(24, 660)
	_ui.add_child(_status)
	if in_party:
		var chat := K12ChatPanel.new()
		_ui.add_child(chat)
	if not _selected.is_empty():
		_show_card(_selected)


# --- Карточка выбранной игры ------------------------------------------------------------

func _on_box_selected(g: Dictionary) -> void:
	_selected = g
	_show_card(g)


func _on_box_released() -> void:
	_selected = {}
	HubStyle.clear(_card)


func _show_card(g: Dictionary, animate: bool = true) -> void:
	HubStyle.clear(_card)
	var p := HubStyle.panel(HubStyle.PINK)
	p.custom_minimum_size = Vector2(360, 0)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_right = -60
	p.offset_left = -420
	_card.add_child(p)
	var v := HubStyle.vbox(10)
	p.add_child(v)
	var t := HubStyle.neon_label(str(g["title"]).to_upper(), 26, HubStyle.PINK)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var meta := HubStyle.hbox(14)
	meta.add_child(HubStyle.label("👥 " + str(g["players"]), 15, HubStyle.CYAN, HORIZONTAL_ALIGNMENT_LEFT, "medium"))
	meta.add_child(HubStyle.label("⏱ " + str(g["time"]), 15, HubStyle.CYAN, HORIZONTAL_ALIGNMENT_LEFT, "medium"))
	v.add_child(meta)
	var d := HubStyle.label(str(g["description"]), 15, HubStyle.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 320
	v.add_child(d)
	# одна коробка — несколько версий игры (Тип Топ): переключатель под описанием
	var variants: Array = g.get("variants", [])
	if variants.size() > 1:
		var vrow := HubStyle.hbox(6)
		for id in variants:
			var vg := HubGames.by_id(id)
			var vb := HubStyle.button(str(vg.get("variant_label", vg.get("title", id))), 14)
			UISel.pick(vb, id == g["id"])
			vb.pressed.connect(func():
				_selected = vg
				if _room.focused:
					_room.focused.set_variant(vg)  # коробка меняется вместе с переключателем
				_show_card(vg, false))
			vrow.add_child(vb)
		v.add_child(vrow)
	var in_party := Net.is_party() and not Net.lobby_view.is_empty()
	var row := HubStyle.hbox(8)
	if in_party:
		if Net.is_host():
			var go := HubStyle.primary("Играть всей пати", 18)
			go.pressed.connect(func():
				HubGames.apply_settings(g)
				Net.select_game(HubGames.play_id(g)))
			row.add_child(go)
		else:
			# запустить может только ведущий — участник предлагает игру, предложение видно у его ника в пати
			var mine := _my_suggestion()
			var sug := HubStyle.primary("Предложено ✓" if mine == HubGames.play_id(g) else "Предложить ведущему", 16)
			sug.disabled = mine == HubGames.play_id(g)
			sug.tooltip_text = "Запускает игру ведущий пати — он увидит ваше предложение"
			sug.pressed.connect(func():
				Net.suggest_game(HubGames.play_id(g))
				sug.text = "Предложено ✓"
				sug.disabled = true)
			row.add_child(sug)
	else:
		var play := HubStyle.primary("Играть", 20, 160)
		play.pressed.connect(func(): _open_scene(g))
		row.add_child(play)
	var back := HubStyle.button("Назад", 15)
	back.pressed.connect(func(): _room.release())
	row.add_child(back)
	v.add_child(row)
	v.add_child(HubStyle.label("← → или колесо мыши — соседняя игра", 12, HubStyle.MUTED))
	if animate:
		p.modulate.a = 0.0
		create_tween().tween_property(p, "modulate:a", 1.0, 0.35).set_delay(0.3)


# --- Пати --------------------------------------------------------------------------

## Без пати: создать или войти.
func _party_create_panel() -> Control:
	var p := HubStyle.panel(HubStyle.CYAN)
	p.custom_minimum_size = Vector2(290, 0)
	var v := HubStyle.vbox(9)
	p.add_child(v)
	v.add_child(HubStyle.neon_label("PARTY", 18, HubStyle.CYAN))
	var hint := HubStyle.label("Соберитесь один раз — и играйте во что угодно: при смене игры пати не распадается.", 13, HubStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(250, 0)
	v.add_child(hint)
	v.add_child(HubStyle.label("Steam: " + Net.my_name if Net.steam_ok else "Steam недоступен — запустите Steam и перезапустите игру", 13, Color("7dffc8") if Net.steam_ok else HubStyle.MUTED))
	var create := HubStyle.primary("Создать пати (Steam)", 16)
	create.disabled = not Net.steam_ok
	create.pressed.connect(func(): Net.host_steam(""))
	v.add_child(create)
	var join_row := HubStyle.hbox(6)
	_code = LineEdit.new()
	_code.placeholder_text = "код пати"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_code)
	var join := HubStyle.button("Войти", 14)
	join.disabled = not Net.steam_ok
	join.pressed.connect(func(): Net.join_steam(int(_code.text.strip_edges())))
	join_row.add_child(join)
	v.add_child(join_row)
	if not Net.last_join.is_empty():
		var back := HubStyle.button("Вернуться в пати", 14)
		back.pressed.connect(Net.rejoin)
		v.add_child(back)
	return p


## В пати: друзья, приглашение, выход.
func _party_panel() -> Control:
	var data: Dictionary = Net.lobby_view
	var p := HubStyle.panel(HubStyle.CYAN)
	p.custom_minimum_size = Vector2(290, 0)
	var v := HubStyle.vbox(8)
	p.add_child(v)
	v.add_child(HubStyle.neon_label("PARTY", 18, HubStyle.CYAN))
	var humans: Array = data["members"].filter(func(m): return m["kind"] != "bot")
	v.add_child(HubStyle.label("Участники (%d/%d)" % [humans.size(), Net.MAX_PLAYERS], 13, HubStyle.MUTED))
	for m in humans:
		var row := HubStyle.hbox(6)
		row.add_child(PlayerTag.make(m, data["members"], 16, HubStyle.TEXT))
		if m["kind"] == "host":
			row.add_child(HubStyle.label("хост", 12, HubStyle.YELLOW))
		v.add_child(row)
		var sid := str(m.get("suggest", ""))
		if sid != "":
			var sl := HubStyle.label("Предлагает игру «%s»" % _game_title(sid), 12, HubStyle.PINK.lightened(0.3))
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sl.custom_minimum_size.x = 250
			v.add_child(sl)
	if data.get("code", "") != "":
		var code_row := HubStyle.hbox(6)
		code_row.add_child(HubStyle.label("Код:", 13, HubStyle.MUTED))
		var code := HubStyle.label(str(data["code"]), 13, HubStyle.YELLOW)
		code.clip_text = true
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_row.add_child(code)
		var copy := HubStyle.button("Копировать", 12)
		copy.pressed.connect(func(): DisplayServer.clipboard_set(str(data["code"]).split(",")[0]))
		code_row.add_child(copy)
		v.add_child(code_row)
	if data.get("mode", "") == "steam":
		var invite := HubStyle.primary("Пригласить друзей (Steam)", 14)
		invite.pressed.connect(Net.invite_friends)
		v.add_child(invite)
	var leave := HubStyle.button("Распустить пати" if Net.is_host() else "Покинуть пати", 14)
	leave.pressed.connect(func():
		LeaveGuard.ask(leave, "Распустить пати?" if Net.is_host() else "Покинуть пати?", "Все участники вернутся в главное меню." if Net.is_host() else "Вы выйдете из пати друзей.", leave.text, func():
			Net.leave()
			_rebuild()))
	v.add_child(leave)
	return p


func _game_title(id: String) -> String:
	for g in HubGames.LIST:
		if g["id"] == id:
			return g["title"]
	return id


func _my_suggestion() -> String:
	for m in Net.lobby_view.get("members", []):
		if int(m.get("peer", -1)) == multiplayer.get_unique_id():
			return str(m.get("suggest", ""))
	return ""


func _on_closed(reason: String) -> void:
	_rebuild()
	_set_status(reason)


func _set_status(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text


func _on_lobby() -> void:
	if Net.is_party() and Net.party_game != "":
		_open_by_id(Net.party_game)
	else:
		_rebuild()


func _on_party_game(game_id: String) -> void:
	if game_id != "":
		_open_by_id(game_id)
	else:
		_rebuild()


func _open_by_id(game_id: String) -> void:
	for g in HubGames.LIST:
		if g["id"] == game_id:
			_open_scene(g)


func _open_scene(g: Dictionary) -> void:
	if _leaving:
		return
	HubGames.apply_settings(g)
	_leaving = true
	Sfx.play("game_start", -4)
	get_tree().change_scene_to_file.call_deferred(g["scene"])
