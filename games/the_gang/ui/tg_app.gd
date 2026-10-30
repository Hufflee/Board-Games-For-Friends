extends Control
## Меню, лобби и стилизованные окна The Gang; сетевой транспорт общий Net.

const Table := preload("res://games/the_gang/ui/tg_table.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const RULES := """[b]Одна команда — одно ограбление.[/b] Откройте 3 хранилища раньше третьей тревоги. В одной команде от 3 до 10 игроков.

[b]Ваши карты — секрет.[/b] У каждого две личные карты. Не называйте их, не показывайте и не намекайте на комбинацию. Общайтесь оценкой силы руки через фишки. Блефовать не нужно!

[b]Четыре раунда.[/b] Префлоп: общих карт нет. Флоп: открываются 3. Тёрн и ривер: ещё по одной. В каждом раунде новый цвет фишек: белый, жёлтый, оранжевый, красный.

[b]Фишки.[/b] Чем больше звёзд, тем сильнее вы считаете свою руку относительно остальных. Очереди нет. Перетащите свободную или чужую фишку к своим картам, чтобы забрать её себе; прежний владелец останется без фишки. Ваша предыдущая фишка вернётся в центр. Можно перетащить свою фишку обратно в центр, но нельзя выдавать её другому. Когда фишки есть у всех, раунд сразу заканчивается.

[b]Вскрытие.[/b] После ривера руки открываются в порядке красных фишек: от 1 к старшей. Сравнивается лучшая комбинация ровно из 5 любых карт среди ваших 2 и 5 общих. Порядок должен идти от слабой к сильной; точное равенство допустимо. Любая ошибка даёт одну тревогу, правильный порядок — одно хранилище.

[b]Старшинство.[/b] Старшая карта → пара → две пары → тройка → стрит → флеш → фулл-хаус → каре → стрит-флеш. Роял-флеш — старший стрит-флеш. При равенстве учитываются все кикеры; масти равны. Туз может быть младшим в A2345 или старшим в 10JQKA, но не в KA234.

[b]Таймер.[/b] Лимит относится ко всему раунду. По его истечении отсутствующие фишки распределяются случайно, уже выбранные сохраняются. Если лимит выключен, отключившийся игрок получает свободную фишку после 60 секунд раунда. Полноценных ботов в базовой версии нет.

[b]Проверка на одном компьютере.[/b] Выбирайте место в верхнем списке. Сначала рука скрыта — потяните край каждой карты, чтобы открыть или закрыть её. Переключение места снова скрывает карты."""

var screen: Control
var _lobby_body: VBoxContainer
var _lobby_error: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = TGStyle.theme()
	Prefs.changed.connect(_on_prefs)
	Net.lobby_changed.connect(_on_lobby)
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.session_closed.connect(show_menu)
	Net.party_game_changed.connect(_on_party)
	if Net.in_session() and Net.party_game != "the_gang":
		_go_hub()
	elif Net.in_game:
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
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)

func _centered() -> VBoxContainer:
	var root_control := Control.new()
	root_control.add_child(TGStyle.Background.new())
	# Панель слева от кольца сейфа и правее угловых вееров: декор фона не перекрывается.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	center.offset_left = 112
	center.offset_right = 112 + 576
	root_control.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "LobbyPanel"
	panel.custom_minimum_size.x = 576
	panel.add_theme_stylebox_override("panel", _rounded_panel())
	center.add_child(panel)
	var col := TGStyle.column(12)
	panel.add_child(col)
	_set_screen(root_control)
	return col

## Панель лобби: крупное скругление и золотая обводка в тон коробке; сама не касается рамки фона.
func _rounded_panel() -> StyleBoxFlat:
	var sb := TGStyle.box(Color.TRANSPARENT, 24)
	sb.set_corner_radius_all(18)
	sb.border_color = Color(TGStyle.GOLD, 0.55)
	sb.set_border_width_all(2)
	sb.shadow_size = 12
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	return sb

func show_menu(message: String = "") -> void:
	var col := _centered()
	col.add_child(TGStyle.heading("THE GANG", 48))
	col.add_child(TGStyle.label("КООПЕРАТИВНЫЙ ПОКЕР · 3–10 ИГРОКОВ", 16, TGStyle.GOLD))
	col.add_child(RoomPanel.make("the_gang", TGStyle.button, TGStyle.label))
	var local := TGStyle.primary("Играть на одном компьютере")
	local.name = "LocalGame"
	local.pressed.connect(func():
		Net.host_offline("the_gang")
		Net.set_bots(2))
	col.add_child(local)
	var rules := TGStyle.button("Правила")
	rules.pressed.connect(show_rules)
	col.add_child(rules)
	var back := TGStyle.button("← К выбору игры")
	back.pressed.connect(_go_hub)
	col.add_child(back)
	if not message.is_empty():
		col.add_child(TGStyle.label(message, 16, TGStyle.GOLD))

func show_lobby() -> void:
	_lobby_body = _centered()
	_rebuild_lobby()

func _on_lobby() -> void:
	if Net.party_game != "the_gang" and Net.in_session():
		_go_hub()
	elif not Net.in_game:
		if not is_instance_valid(_lobby_body) or not _lobby_body.is_inside_tree():
			show_lobby()
		else:
			_rebuild_lobby()

func _rebuild_lobby() -> void:
	TGStyle.clear(_lobby_body)
	_lobby_body.add_child(TGStyle.heading("THE GANG · СОБИРАЕМ КОМАНДУ"))
	_lobby_body.add_child(TGStyle.label("Базовая игра · 3–10 мест · без ботов", 16, TGStyle.GOLD))
	var data: Dictionary = Net.lobby_view
	var members: Array = data.get("members", [])
	var member_grid := GridContainer.new()
	member_grid.columns = 2
	member_grid.add_theme_constant_override("h_separation", 24)
	_lobby_body.add_child(member_grid)
	for member: Dictionary in members:
		member_grid.add_child(PlayerTag.make(member, members, 16, TGStyle.INK))
	if Net.mode == "offline" and Net.is_host():
		var row := TGStyle.row()
		var add := TGStyle.button("+ Игрок")
		add.name = "AddPlayer"
		add.disabled = members.size() >= 10
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		row.add_child(add)
		var remove := TGStyle.button("− Игрок")
		remove.disabled = members.size() <= 3
		remove.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		row.add_child(remove)
		_lobby_body.add_child(row)
		var seats_hint := TGStyle.label("На столе переключайте места: чужие карты открываются только после выбора места.", 16, TGStyle.MUTED)
		seats_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lobby_body.add_child(seats_hint)
	_lobby_body.add_child(TurnClock.settings_row(TGStyle.button, TGStyle.label))
	var references := TGStyle.row()
	for entry in [["Правила", show_rules], ["Комбинации", show_poker_reference], ["Настройки", show_settings]]:
		var reference := TGStyle.button(entry[0])
		reference.pressed.connect(entry[1])
		references.add_child(reference)
	var chat := TGStyle.button("Чат")
	chat.pressed.connect(func():
		var panel := K12ChatPanel.new()
		panel.expanded = true
		screen.add_child(panel))
	references.add_child(chat)
	_lobby_body.add_child(references)
	if Net.is_host():
		var start := TGStyle.primary("Начать ограбление")
		start.name = "StartGame"
		start.disabled = members.size() < 3 or members.size() > 10
		start.pressed.connect(func():
			var error := Net.start_game()
			if not error.is_empty():
				_lobby_error.text = error)
		_lobby_body.add_child(start)
	else:
		_lobby_body.add_child(TGStyle.label("Ждём старта от хоста…"))
	var back := TGStyle.button("← К выбору игры")
	LeaveGuard.wire(back, "Выйти?", "Вы вернётесь к выбору игры.", back_to_hub)
	_lobby_body.add_child(back)
	_lobby_error = TGStyle.label("", 16, TGStyle.GOLD)
	_lobby_body.add_child(_lobby_error)

func show_table() -> void:
	var table := Table.new()
	table.app = self
	_set_screen(table)

func _popup(title: String, text: String) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.05, 0.06, 0.82)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 110
	add_child(overlay)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	overlay.add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := TGStyle.column()
	panel.add_child(col)
	col.add_child(TGStyle.heading(title))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = text
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var close := TGStyle.primary("Понятно")
	close.name = "CloseRules"
	close.pressed.connect(overlay.queue_free)
	col.add_child(close)
	return col

func show_rules() -> void:
	var col := _popup("ПРАВИЛА THE GANG", RULES)
	var reference := TGStyle.button("Памятка покерных комбинаций")
	reference.name = "PokerReference"
	reference.pressed.connect(show_poker_reference)
	col.add_child(reference)
	col.move_child(reference, col.get_child_count() - 2)

func show_poker_reference() -> void:
	var col := _popup("ПОКЕРНЫЕ КОМБИНАЦИИ", "")
	var body := col.get_child(1)
	col.remove_child(body)
	body.queue_free()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	col.move_child(scroll, 1)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var image := TextureRect.new()
	image.name = "PokerReferenceImage"
	image.texture = preload("res://hub/covers/poker combination.jpg")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(648, 1067)
	image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(image)

func show_settings() -> void:
	var settings := Settings.new()
	settings.make_panel = func(): return PanelContainer.new()
	settings.make_title = TGStyle.heading
	settings.make_primary = func(text: String):
		var close := TGStyle.primary(text)
		close.name = "CloseSettings"
		return close
	settings.ink = TGStyle.INK
	add_child(settings)

func back_to_hub() -> void:
	if Net.is_party() and Net.is_host():
		Net.return_to_party()
	else:
		Net.leave()
		_go_hub()

func _go_hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)

func _on_party(id: String) -> void:
	if id != "the_gang":
		_go_hub()

func _on_prefs() -> void:
	pass  # У The Gang одна тёмная тема; общая настройка не пересоздаёт стол.
