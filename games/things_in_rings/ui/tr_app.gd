extends Control
## Things in Rings: меню, лобби и приватный стол, общая пати Net.
const Style := preload("res://games/things_in_rings/ui/tr_style.gd")
const Backdrop := preload("res://games/things_in_rings/ui/tr_backdrop.gd")
const Lobby := preload("res://games/things_in_rings/ui/tr_lobby.gd")
const Table := preload("res://games/things_in_rings/ui/tr_table.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const GAME_ID := "things_in_rings"
## Спокойное пианино CC0 — The Cynic Project; лицензия games/hues_and_cues/audio/LICENSE.txt.
const MUSIC := ["res://games/hues_and_cues/audio/calm_piano_vaporware.mp3",
	"res://games/hues_and_cues/audio/another_august.mp3"]
var screen: Control
var feedback_seen := {}
var final_seen := {}
var hand_orders := {}  # Локальная сортировка по game_id/месту, переживает смену темы.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = Style.theme()
	theme = get_tree().root.theme
	add_child(Backdrop.new())
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
	col.add_child(Style.heading("THINGS IN RINGS"))
	col.add_child(Style.label("Ищите тайные правила в пересечениях вещей"))
	col.add_child(Style.label("2–6 друзей · 1–3 кольца · вдвоём — кооператив", 16, Style.muted()))
	var play := Style.button("За одним компьютером")
	play.theme_type_variation = "SelectedButton"
	play.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(1))
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
	layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	layer.position = (size - Vector2(760, 520)) * 0.5
	layer.size = Vector2(760, 520)
	var col := Style.column(16)
	layer.add_child(col)
	col.add_child(Style.heading("Как играть"))
	var text := RichTextLabel.new()
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.text = "Знающий выбирает для каждого кольца одно из трёх секретных правил. Затем раздаются вещи. Знающий размещает 3 подсказки (в кооперативе — по числу игроков). Остальные его карты сбрасываются только в обычной игре.\n\nИскатель переносит вещь из руки в кольца или вне колец. Знающий подтверждает область или исправляет её. Верно — играйте снова; ошибка — доберите карту и передайте ход. Кто первым опустошит руку после верного ответа, победил. Смысл определяет человек.\n\nВдвоём — всегда кооператив (добровольно: 2–4). У знающего 10 вещей, после каждого круга искателей он даёт ещё подсказку. Пустые руки пропускаются. Все искатели без карт — общая победа. Подсказок больше нет — общий проигрыш.\n\nПосле финала угадайте правила вслух; знающий переворачивает каждое условие отдельно. Хост нажимает «Экран победы», когда все готовы. Если при штрафе исчерпана общая колода, партия технически завершается без победителя. Правила «Название» относятся к английскому названию; русский перевод — справочный."
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
