extends Control
## «Покер»: меню, лобби и стол поверх общей пати Net. Техасский холдем, режимы «Классика» и «Спортивный».
## Запуск: сцена res://games/poker/ui/main.tscn (или из хаба).
const Style := preload("res://games/poker/ui/pk_style.gd")
const Lobby := preload("res://games/poker/ui/pk_lobby.gd")
const Table := preload("res://games/poker/ui/pk_table.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const GAME_ID := "poker"
## Лаунж-музыка CC0 — The Cynic Project; лицензия games/hues_and_cues/audio/LICENSE.txt.
const MUSIC := ["res://games/hues_and_cues/audio/calm_piano_vaporware.mp3",
	"res://games/hues_and_cues/audio/another_august.mp3"]
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
	col.add_child(Style.heading("ПОКЕР", 28, Style.PINK))
	col.add_child(Style.label("Техасский холдем без лимита · 100 BB на старте"))
	col.add_child(Style.label("2–8 игроков · «Классика» и «Спортивный»", 16, Style.muted()))
	var play := Style.button("Играть с ботами")
	play.theme_type_variation = "SelectedButton"
	play.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(3))
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
	panel.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 24, 16, Style.PINK))
	return panel


func show_rules() -> void:
	var layer := PanelContainer.new()
	layer.name = "RulesOverlay"
	layer.z_index = 110
	layer.position = (size - Vector2(760, 560)) * 0.5
	layer.size = Vector2(760, 560)
	layer.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 24, 16, Style.PINK))
	var col := Style.column(16)
	layer.add_child(col)
	col.add_child(Style.heading("Как играть", 28, Style.PINK))
	var text := RichTextLabel.new()
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.text = "Техасский холдем без лимита. У каждого 2 закрытые карты, на столе открываются 5 общих: флоп (3), тёрн и ривер. Лучшая пятёрка из семи карт забирает банк.\n\nБлайнды 1/2, все начинают со 100 BB (200 фишек). Ходы: пас, чек или колл, рейз (минимум — на размер прошлого повышения), ва-банк. Ставку можно ввести числом, подвинуть ползунком или нажать 2× / 3× / 4× от текущей ставки. На ход 30 секунд — потом чек или пас.\n\n«Классика»: раздачи без конца. Проиграли всё — «Сесть заново» со 100 BB (докупка учитывается в итоге). Хост может завершить игру — побеждает лучший итог.\n\n«Спортивный»: сессия из 14 раздач. Вылетевший ждёт конца сессии. По итогу места по стеку (вылетевшие ниже, по порядку вылета) приносят победные очки: N игроков — за 1-е место N, за 2-е N−1 … предпоследнее 2, последнее 0. Затем у всех снова 100 BB. Побеждает тот, кто первым наберёт 2N+1 очков (вчетвером — 9)."
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
