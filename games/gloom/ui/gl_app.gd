extends Control
## Корневой экран Gloom: меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "gloom"
const TableScreen := preload("res://games/gloom/ui/gl_table.gd")
const LobbyScreen := preload("res://games/gloom/ui/gl_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # карты крупные — уменьшаем с мип-картами, без «каши»
	get_tree().root.theme = GLStyle.theme()
	Sfx.start_music()
	Sfx.set_playlist(GLStyle.MUSIC)
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
	m.add_child(GLStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var col := GLStyle.vbox(16)
	col.custom_minimum_size.x = 560
	center.add_child(col)
	var cards := GLStyle.hbox(14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in [["ch17", -8.0], ["back", 0.0], ["ch11", 8.0]]:
		var tr := TextureRect.new()
		tr.texture = GLStyle.tex(spec[0])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(110, 158)
		tr.pivot_offset = Vector2(55, 79)
		tr.rotation_degrees = spec[1]
		cards.add_child(tr)
	col.add_child(cards)
	col.add_child(GLStyle.title("GLOOM", 64))
	var sub := GLStyle.label("Сделайте свою семью самой несчастной на свете — и сведите её в могилу, пока соперники до неприличия счастливы.", GLStyle.BODY, GLStyle.BONE, HORIZONTAL_ALIGNMENT_CENTER, "italic")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var rp := GLStyle.panel(14)
	rp.add_child(RoomPanel.make(GAME_ID, func(t, z): return GLStyle.button(t, z), func(t, z): return GLStyle.label(t, z, GLStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)))
	col.add_child(rp)
	var test := GLStyle.primary("Попробовать на одном компьютере", GLStyle.BODY)
	test.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	test.tooltip_text = "Тест: вы ходите за всех игроков по очереди"
	test.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(1))
	col.add_child(test)
	var row := GLStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := GLStyle.button("Правила", GLStyle.BODY, 150)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := GLStyle.button("Настройки", GLStyle.BODY, 150)
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	col.add_child(row)
	var back := GLStyle.button("← К выбору игры", GLStyle.CAP)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := GLStyle.label(message, GLStyle.CAP, GLStyle.BONE, HORIZONTAL_ALIGNMENT_CENTER)
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


const RULES_TEXT := """[b]Цель.[/b] У каждого игрока — семья из пяти чудаков. Сделайте их как можно несчастнее и сведите в могилу, а чужим семьям устройте праздник жизни. Игра заканчивается, как только вымерла целая семья. Каждый складывает очки своих [b]мёртвых[/b] персонажей; побеждает самая [b]низкая[/b] сумма.

[b]Прозрачные карты.[/b] Карты кладут прямо на персонажа, одну поверх другой. Считается только то, что видно: в каждой из трёх ячеек слева — число с самой верхней карты, где оно есть. Иконка справа — тоже верхняя видимая. Текст с эффектом у всех карт на одном месте, поэтому постоянный эффект («пока виден этот текст») действует, только пока карта лежит сверху.

[b]Ход.[/b] Сделайте 2 действия, затем доберите карты до лимита (обычно 5; лишние не сбрасываются).
• [b]Модификатор[/b] — на любого живого персонажа, своего или чужого. Эффект срабатывает сразу и касается того, кто управляет персонажем.
• [b]Событие[/b] — эффект, затем карта уходит в сброс.
• [b]Безвременная смерть[/b] — только [b]первым[/b] действием и только на персонажа с отрицательным счётом. Мёртвый персонаж больше не меняется (почти).
• [b]Сбросить руку[/b] — новые карты придут только в конце хода.
• Можно пропустить действия.

[b]Ответ.[/b] «Второй шанс» отменяет только что сыгранную смерть, «Напустить туману» — событие. Когда кто-то играет смерть или событие, у всех есть несколько секунд, чтобы ответить.

[b]Четверо и пятеро.[/b] Вчетвером каждый откладывает одного персонажа. Впятером из отложенных собирается сборная семья для пятого игрока.

[b]Гости.[/b] (Дополнения и Gloomier.) Незваные гости начинают ничьими в центре стола. Каждый гость «следует» за картой — иконкой или смертью: когда такую карту играют на чьего-то персонажа, гость переезжает в его семью со всеми своими картами. На гостей можно играть карты как на обычных персонажей; их постоянный эффект (значок в правом верхнем углу) действует, пока значок виден.

[b]Истории.[/b] Действием можно забрать историю, если у вашей семьи (живых и мёртвых) видны нужные иконки. Отобрать её у другого игрока — если у вас таких иконок больше. Держать можно одну историю; её очки идут вам в конце игры.

[b]Нежить.[/b] Модификатор-нежить играют на мёртвого: смерть снимается, персонаж снова может получать карты, а его очки всё равно идут в итог.

[b]Gloomier.[/b] Ночь в Хемлок-Холле: все персонажи — из одного дома, каждый по очереди выбирает себе четверых. Набор и дополнения выбираются в лобби; можно смешать всё вместе.

[b]Как играть здесь.[/b] Перетащите карту из руки на персонажа или выберите карту щелчком, а потом персонажа. Наведите курсор на любую карту — она покажется крупно. Рассказывайте, как всё случилось: «Почему Бальтазара съели медведи?» — в этом половина удовольствия!"""


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
	var panel := GLStyle.panel(26)
	margin.add_child(panel)
	var col := GLStyle.vbox(10)
	panel.add_child(col)
	col.add_child(GLStyle.label("Правила", GLStyle.H1, GLStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", GLStyle.BODY)
	text.add_theme_font_size_override("bold_font_size", GLStyle.BODY)
	text.add_theme_constant_override("line_separation", 4)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := GLStyle.primary("Понятно", GLStyle.BODY, 160)
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
