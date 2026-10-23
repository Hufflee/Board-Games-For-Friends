extends Control
## Корневой экран «Большой бродилки»: меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "brodilka"
const TableScreen := preload("res://games/brodilka/ui/br_table.gd")
const LobbyScreen := preload("res://games/brodilka/ui/br_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # поле и карты крупные — уменьшаем с мип-картами
	get_tree().root.theme = BRStyle.theme()
	Sfx.start_music()
	Sfx.set_playlist(BRStyle.MUSIC)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.session_closed.connect(_on_closed)
	Net.party_game_changed.connect(_on_party_game)
	if Net.is_party() and Net.party_game != GAME_ID and not Net.lobby_view.is_empty():
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
	m.add_child(BRStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var col := BRStyle.vbox(16)
	col.custom_minimum_size.x = 560
	center.add_child(col)
	var pawns := BRStyle.hbox(6)
	pawns.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in BRStyle.PAWN_COUNT:
		var tr := TextureRect.new()
		tr.texture = BRStyle.pawn_tex(i)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(84, 130)
		pawns.add_child(tr)
	col.add_child(pawns)
	col.add_child(BRStyle.title("БОЛЬШАЯ БРОДИЛКА", 52))
	var sub := BRStyle.label("Нескучная ходилка: бросай кубики, открывай сундуки, закупайся в Лавке Джо и первым доберись до финиш-сейфа.", BRStyle.BODY, BRStyle.PARCH, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var rp := BRStyle.panel(14)
	rp.add_child(RoomPanel.make(GAME_ID, func(t, z): return BRStyle.button(t, z), func(t, z): return BRStyle.label(t, z, BRStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)))
	col.add_child(rp)
	var test := BRStyle.primary("Играть на одном компьютере", BRStyle.BODY)
	test.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	test.tooltip_text = "Ходите по очереди за всех игроков"
	test.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(1))
	col.add_child(test)
	var row := BRStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := BRStyle.button("Правила", BRStyle.BODY, 150)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := BRStyle.button("Настройки", BRStyle.BODY, 150)
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	col.add_child(row)
	var back := BRStyle.button("← К выбору игры", BRStyle.CAP)
	back.theme_type_variation = "QuietButton"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := BRStyle.label(message, BRStyle.CAP, BRStyle.PARCH, HORIZONTAL_ALIGNMENT_CENTER)
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


const RULES_TEXT := """[b]Цель.[/b] Первым пересечь финиш: дойти до финиш-сейфа и выбросить на нём «6». Ещё один путь к победе — выбросить «6» в Шахте.

[b]Ход.[/b] Брось кубики и иди вперёд. Сколько кубиков — зависит от клетки, на которой стоишь:
• светлая — 1 кубик;
• серая — 2 кубика, выбери один из них;
• чёрная — 2 кубика, иди на сумму.
Потом срабатывает клетка, где ты остановился, а за ней — карты. Клетки действуют, только если ты остановился на них сам, двигаясь вперёд в свой ход.

[b]Клетки.[/b]
• [b]Закрытый сундук[/b] — тащи карту «Хорошо/Плохо», выполни сторону «Хорошо». [b]Открытый сундук[/b] — сторону «Плохо».
• [b]Лавка Джо[/b] — тащи 2 карты Лавки, одну можно купить за 5 монет. Больше 3 карт Лавки держать нельзя.
• [b]ТАДАМ[/b] — карта Тадам ложится в левую ячейку над полем, остальные сдвигаются вправо, крайняя уходит в сброс. Карты Тадам действуют на всех.
• [b]Телепорт[/b] — переносит на другой телепорт того же цвета.
• [b]Удачный расклад[/b] — тебе Хорошо, Лавка и Тадам, остальным по «Плохо».
• [b]Смерч[/b] — все персонажи летят сюда; можно откупиться за 10 монет.
• [b]Дань[/b] — каждый бросает кубик и платит тебе столько монет.
• [b]Схватка[/b] — выбери соперника, бросьте по кубику, у тебя +2. Победитель забирает 10 монет или карту Лавки, или отправляет проигравшего на 10 клеток назад.
• [b]Велосипед[/b] — 10 клеток вперёд. [b]Кубик удачи[/b] — 3 кубика, иди на сумму. [b]Нееет![/b] — потеряй 10 монет.
• [b]Шахта[/b] — кубик: 1 — пропусти ход, 2–5 — +10 монет, 6 — победа!
• [b]Жвачка[/b] — ты прилип и дальше не двигаешься, но бросаешь на финиш, как с финиш-сейфа.
• [b]Финиш-сейф[/b] — нужна «6». Перед броском можно доплатить 5 или 10 монет за +1 или +2.
• [b]Перекрёсток[/b] — иди прямо. [b]Красные и зелёные[/b] клетки пустые, пока их не «включат» карты.

[b]Карты Лавки[/b] лежат перед тобой и действуют каждый ход: одни сами (волшебный куб, клевер), другие по кнопке за 3 монеты (ракета, граната, крюк…).

[b]Если двое на одной клетке[/b] — никто из них не первый и не последний."""


func show_rules() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 160)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	layer.add_child(margin)
	var panel := BRStyle.panel(26)
	margin.add_child(panel)
	var col := BRStyle.vbox(10)
	panel.add_child(col)
	col.add_child(BRStyle.label("Правила", BRStyle.H1, BRStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", BRStyle.BODY)
	text.add_theme_font_size_override("bold_font_size", BRStyle.BODY)
	text.add_theme_constant_override("line_separation", 4)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := BRStyle.primary("Понятно", BRStyle.BODY, 160)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	add_child(SettingsScreen.new())


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


func _on_party_game(game_id: String) -> void:
	if game_id != GAME_ID:
		_go_hub()


func _on_lobby_changed() -> void:
	if Net.is_party() and Net.party_game != GAME_ID:
		_go_hub()
		return
	if not Net.in_game and not (screen is LobbyScreen) and Net.in_session() and Net.view.is_empty():
		show_lobby()


func _on_closed(reason: String) -> void:
	show_menu(reason)
