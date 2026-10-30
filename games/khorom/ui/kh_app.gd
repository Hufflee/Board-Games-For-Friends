extends Control
## «Хором!»: меню, лобби и стол поверх общей пати Net.
const Style := preload("res://games/khorom/ui/kh_style.gd")
const Lobby := preload("res://games/khorom/ui/kh_lobby.gd")
const Table := preload("res://games/khorom/ui/kh_table.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const GAME_ID := "khorom"
## Спокойное пианино CC0 — The Cynic Project; лицензия games/hues_and_cues/audio/LICENSE.txt.
const MUSIC := ["res://games/hues_and_cues/audio/another_august.mp3",
	"res://games/hues_and_cues/audio/calm_piano_vaporware.mp3"]
var screen: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = Style.theme()
	theme = get_tree().root.theme
	var backdrop := Control.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.draw.connect(func(): Style.paint_backdrop(backdrop, backdrop.size))
	backdrop.resized.connect(backdrop.queue_redraw)
	add_child(backdrop)
	Sfx.set_playlist(MUSIC)
	Sfx.start_music()
	Net.lobby_changed.connect(_lobby_changed)
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.session_closed.connect(show_menu)
	Net.party_game_changed.connect(func(id: String):
		if id != GAME_ID:
			_go_hub())
	if Net.in_game and Net.party_game == GAME_ID:
		show_table()
	elif Net.in_session():
		show_lobby()
	else:
		show_menu()

func _set_screen(next: Control) -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = next
	next.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(next)

func show_menu(message: String = "") -> void:
	var page := CenterContainer.new()
	var col := Style.column(16)
	col.custom_minimum_size.x = 600
	page.add_child(col)
	col.add_child(Style.heading("ХОРОМ!"))
	col.add_child(Style.label("Пишите ответы на тему и ищите совпадения с друзьями"))
	col.add_child(Style.label("3–8 игроков · 6 раундов · «Хором», «Белая ворона», «Блиц»", 16, Style.muted()))
	var play := Style.button("За одним компьютером")
	play.theme_type_variation = "SelectedButton"
	play.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(2))
	col.add_child(play)
	col.add_child(RoomPanel.make(GAME_ID, Style.button, func(t, z): return Style.label(t, z)))
	var row := Style.row()
	for item: Array in [["Правила", show_rules], ["Настройки", show_settings], ["К выбору игры", back_to_hub]]:
		var b := Style.button(item[0])
		b.pressed.connect(item[1])
		row.add_child(b)
	col.add_child(row)
	col.add_child(Style.label(message, 16, Style.muted()))
	_set_screen(page)

func show_lobby() -> void:
	var page := Lobby.new()
	page.app = self
	_set_screen(page)

func show_table() -> void:
	var page := Table.new()
	page.app = self
	_set_screen(page)

func _lobby_changed() -> void:
	if Net.is_party() and Net.party_game != GAME_ID:
		_go_hub()
	elif not Net.in_game and Net.in_session() and not screen is Lobby:
		show_lobby()

func show_settings() -> void:
	var settings := Settings.new()
	settings.make_panel = _settings_panel
	settings.make_title = Style.heading
	settings.make_primary = Style.button
	settings.ink = Style.ink()
	add_child(settings)

func _settings_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box())
	return panel

func show_rules() -> void:
	var layer := PanelContainer.new()
	layer.name = "RulesOverlay"
	layer.z_index = 110
	layer.position = (size - Vector2(760, 540)) * 0.5
	layer.size = Vector2(760, 540)
	var col := Style.column(16)
	layer.add_child(col)
	col.add_child(Style.heading("Как играть"))
	var text := RichTextLabel.new()
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.text = "Каждый раунд — карточка с темой. Все одновременно пишут до 6 ответов в свой блокнот и жмут «Готов». Чужие ответы закрыты пластинками.\n\nОткрытие идёт по ходам. Начинает ведущий (он меняется каждый раунд): глазиком открывает свои ответы, затем ход у следующего. Если ваш скрытый ответ похож на уже открытый — он подсветится, и его можно открыть сразу, вне очереди.\n\n«Хором»: совпал ответ с чьим-то — нажмите «✓», +1 очко.\n«Белая ворона»: каждый открытый ответ сразу +1; совпал с чьим-то — нажмите «✕», очко пропадает.\n«Блиц»: шесть тем, по ответу на каждую, 60 секунд. Открываем по одной теме: ведущий, затем по кругу; следующую тему снова начинает ведущий. Очки — как в «Хороме».\n\nСовпадения решаете вы сами — синонимы на совести друзей. После последнего раунда побеждает тот, у кого больше очков."
	col.add_child(text)
	var close := Style.button("Закрыть")
	close.pressed.connect(layer.queue_free)
	col.add_child(close)
	add_child(layer)

func back_to_hub() -> void:
	if Net.is_party() and Net.is_host():
		Net.return_to_party()
	else:
		Net.leave()
		_go_hub()

func back_to_menu() -> void:
	if Net.is_party():
		back_to_hub()
	else:
		Net.leave()
		show_menu()

func _go_hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)
