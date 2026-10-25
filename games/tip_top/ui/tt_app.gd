extends Control
## Корневой экран «Тип Топ». Одна сцена на две коробки: adult = false — базовая (14+), true — «Для взрослых» (18+).
## Отличаются колода тем и оформление; пати и сеть — общие (Net).

const TableScreen := preload("res://games/tip_top/ui/tt_table.gd")
const LobbyScreen := preload("res://games/tip_top/ui/tt_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

@export var adult := false

var screen: Control


func game_id() -> String:
	return "tip_top_18" if adult else "tip_top"


func title_text() -> String:
	return "ТИП ТОП 18+" if adult else "ТИП ТОП"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	TTStyle.adult = adult
	get_tree().root.theme = TTStyle.theme()
	Sfx.start_music()
	Sfx.set_playlist(["res://games/ready_set_bet/audio/happy_vibes.mp3", "res://games/hues_and_cues/audio/jrpg_piano.mp3"])
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.session_closed.connect(_on_closed)
	Net.party_game_changed.connect(_on_party_game)
	if Net.is_party() and Net.party_game != game_id() and not Net.lobby_view.is_empty():
		_go_hub()
	elif Net.in_game or not Net.view.is_empty():
		show_table()
	elif Net.in_session():
		show_lobby()
	else:
		show_menu()


func _set_screen(s: Control) -> void:
	if screen:
		screen.queue_free()
	screen = s
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(s)


func show_menu(message: String = "") -> void:
	var m := Control.new()
	m.add_child(TTStyle.Rays.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var col := TTStyle.vbox(14)
	col.custom_minimum_size.x = 600
	center.add_child(col)
	col.add_child(TTStyle.title("ТИП ТОП", 78))
	if adult:
		var badge := TTStyle.label(" ДЛЯ ВЗРОСЛЫХ · 18+ ", TTStyle.BODY, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "title")
		var bp := PanelContainer.new()
		bp.add_theme_stylebox_override("panel", TTStyle.box(Color("ec3f9c"), 10, TTStyle.INK, 3, 0.3))
		bp.add_child(badge)
		bp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(bp)
	var g := TTStyle.Gauge.new()
	g.custom_minimum_size = Vector2(420, 60)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(g)
	var sub := TTStyle.label("ВСЕГДА ЕСТЬ 10 ХОРОШИХ ПРИЧИН ГОВОРИТЬ ГЛУПОСТИ!", TTStyle.BODY, TTStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "title")
	sub.add_theme_color_override("font_outline_color", TTStyle.INK)
	sub.add_theme_constant_override("outline_size", 6)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var rp := TTStyle.bubble(12)
	rp.add_child(RoomPanel.make(game_id(), func(t, z): return TTStyle.button(t, z), func(t, z): return TTStyle.label(t, z, TTStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)))
	col.add_child(rp)
	var test := TTStyle.primary("Попробовать на одном компьютере", TTStyle.BODY)
	test.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	test.pressed.connect(func():
		Net.host_offline(game_id())
		Net.set_bots(3))
	col.add_child(test)
	var row := TTStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := TTStyle.button("Правила", TTStyle.BODY, 150)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := TTStyle.button("Настройки", TTStyle.BODY, 150)
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	col.add_child(row)
	var back := TTStyle.button("← К выбору игры", TTStyle.CAP)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := TTStyle.label(message, TTStyle.CAP, TTStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)
	_set_screen(m)


func show_lobby() -> void:
	var l := LobbyScreen.new()
	l.app = self
	_set_screen(l)


func show_table() -> void:
	var t := TableScreen.new()
	t.app = self
	_set_screen(t)


const RULES_TEXT := """[b]Цель.[/b] Кооператив: вся команда вместе проходит 5 раундов. В зоне единорога столько жетонов, сколько игроков. Если все жетоны окажутся у какашек — поражение. Остался хоть один единорог после 5-го раунда — победа.

[b]1. Тема.[/b] Капитан (по очереди) видит карту с двумя темами и выбирает одну. Тема — шкала «от … до …».

[b]2. Номера.[/b] Каждому, включая капитана, достаётся тайный номер от 1 до 10: 1 — первая крайность темы (зелёная / голубая), 10 — вторая (красная / розовая).

[b]3. Ответы.[/b] Все пишут ответ по своему номеру. Называть номер или намекать на него нельзя («Три поросёнка» для тройки — нельзя). Ответ не меняется.

[b]4. Порядок.[/b] Капитан раскладывает ответы на планшете от меньшего номера к большему: перетаскивайте их на планшет и меняйте местами сколько угодно (двойной клик — положить / убрать). Остальные видят раскладку вживую и могут подсказывать голосом. Когда готово — «Ответить»: номера открываются по очереди слева направо, и за каждый номер меньше предыдущего жетон уходит к какашкам.

[b]Экспертный вариант.[/b] Порядок любой, но каждой карте на планшете капитан называет номер (клик по карте — выбор номера). Ошибка стоит жетона. Свою карту капитан не выкладывает, а в конце команда угадывает его номер: угадали — жетон возвращается к единорогу.

[b]Итог.[/b] Одни какашки — полный провал; больше какашек — неплохо; поровну или больше единорогов — профессионалы; одни единороги — идеально!"""


func show_rules() -> void:
	var layer := Control.new()
	layer.z_index = 100  # правила доступны поверх окна паузы
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 140)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	layer.add_child(margin)
	var panel := TTStyle.bubble(24)
	margin.add_child(panel)
	var col := TTStyle.vbox(10)
	panel.add_child(col)
	col.add_child(TTStyle.label("ПРАВИЛА", TTStyle.H1, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := TTStyle.primary("Понятно", TTStyle.BODY, 160)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	var st := SettingsScreen.new()
	# окно настроек — в оформлении окна правил этой игры
	st.make_panel = func(): return TTStyle.bubble(24)
	st.make_title = func(t: String): return TTStyle.label(t.to_upper(), TTStyle.H1, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title")
	st.make_primary = func(t: String): return TTStyle.primary(t, TTStyle.BODY, 160)
	st.ink = TTStyle.INK
	add_child(st)


func back_to_hub() -> void:
	if Net.is_party() and Net.is_host():
		Net.return_to_party()
		return
	Net.leave()
	_go_hub()


func back_to_menu() -> void:
	if Net.is_party():
		back_to_hub()
		return
	Net.leave()
	show_menu()


func leave_party() -> void:
	Net.leave()
	_go_hub()


func _go_hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)


func _on_party_game(id: String) -> void:
	if id != game_id():
		_go_hub()


func _on_lobby_changed() -> void:
	if Net.is_party() and Net.party_game != game_id():
		_go_hub()
		return
	if not Net.in_game and not (screen is LobbyScreen) and Net.in_session() and Net.view.is_empty():
		show_lobby()


func _on_closed(reason: String) -> void:
	show_menu(reason)
