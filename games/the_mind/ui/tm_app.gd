extends Control
## Меню, лобби и окна Unspoken. Запуск: res://games/the_mind/ui/main.tscn.

const Style := preload("res://games/the_mind/ui/tm_style.gd")
const Table := preload("res://games/the_mind/ui/tm_table.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const RULES := """[b]Одна команда. Без слов и подсказок.[/b]
У каждого свои тайные числа. Выкладывайте их в общую стопку по возрастанию. Очереди нет: почувствовали момент — нажмите свою наименьшую карту. Нельзя сообщать числа, подавать сигналы и договариваться о счёте времени.

[b]Уровни.[/b] На уровне 1 у каждого одна карта, на уровне 2 — две, и так далее. Каждый уровень — новая раздача из всех 100 карт. Вдвоём нужно пройти 12 уровней, втроём — 10, вчетвером или впятером — 8, вшестером–восьмером — 6. Готовность всех запускает игру. «Стоп» позволяет остановиться и снова настроиться друг на друга.

[b]СТОП.[/b] Если у вас осталась карта ниже сыгранной в центре, нажмите «СТОП». До нажатия штрафа и сброса нет; следующие розыгрыши ждут остановки. После СТОП команда теряет одну жизнь, меньшие карты по очереди открываются с именами владельцев и уходят в открытый сброс справа. После готовности всех продолжаете тот же уровень. Потеряли последнюю жизнь — поражение. Для обычной паузы на синхронизацию есть «Собраться».

[b]Паника.[/b] Любой может предложить помощь. При единогласном согласии расходуется одна «Паника», каждый сбрасывает свою наименьшую карту лицом вверх. Пустые руки ничего не сбрасывают. После этого снова подтвердите готовность.

[b]Награды.[/b] Уровни 2, 5, 8 дают «Панику», 3, 6, 9 — жизнь. Не больше трёх «Паник» и пяти жизней. Начальные жизни равны числу игроков, но не больше пяти; «Паника» одна.

[b]Управление.[/b] Нажатие на карту или перенос в подсвеченный центр — разыграть. Перенос внутри руки — переставить карты. Сначала разыгрывается ваша наименьшая карта. Последний сыгравший подписан у стопки; карта анимированно ложится поверх предыдущей. Наведение на 1,5 секунды открывает крупный просмотр. На одном компьютере выбирайте место по имени и нажимайте «Показать мою руку»; остальные отворачиваются. Это режим для местных игроков, без ботов.

[b]Общий успех.[/b] Пройдите последний уровень раньше, чем закончатся жизни. Перерыв и отключение не дают автоматического согласия за игрока; хост может поставить игру на паузу или вернуть команду в лобби.

[b]Продолжить вслепую.[/b] После победы хост может нажать эту кнопку на экране итогов. Начинаете с первого уровня с оставшимися ресурсами. Карты ложатся рубашкой, порядок открывается только в конце уровня. Каждая карта ниже уже сыгранного максимума стоит одной жизни."""

var screen: Control
var _error: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = Style.theme()
	get_tree().root.theme = theme
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.lobby_changed.connect(_on_lobby)
	Net.session_closed.connect(show_menu)
	Net.party_game_changed.connect(_on_party)
	Prefs.changed.connect(_on_prefs)
	if Net.in_game and Net.party_game == "the_mind":
		show_table()
	elif Net.in_session() and Net.party_game == "the_mind":
		show_lobby()
	elif Net.in_session():
		_go_hub()
	else:
		show_menu()

func _set_screen(control: Control) -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = control
	screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(screen)

func _center() -> VBoxContainer:
	var root := Control.new()
	root.add_child(Style.Background.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 592
	center.add_child(panel)
	var col := Style.column(16)
	panel.add_child(col)
	_set_screen(root)
	return col

func show_menu(_text: String = "") -> void:
	var col := _center()
	col.add_child(Style.heading("UNSPOKEN", 48))
	col.add_child(Style.label("ОДНА КОМАНДА · 2–8 ИГРОКОВ · БЕЗ СЛОВ"))
	col.add_child(RoomPanel.make("the_mind", Style.button, Style.label))
	var local := Style.primary("Играть на одном компьютере")
	local.name = "LocalGame"
	local.pressed.connect(func():
		Net.host_offline("the_mind")
		Net.set_bots(1))
	col.add_child(local)
	var rules := Style.button("Правила")
	rules.pressed.connect(show_rules)
	col.add_child(rules)
	var back := Style.button("К выбору игры")
	back.pressed.connect(_go_hub)
	col.add_child(back)

func show_lobby() -> void:
	var col := _center()
	col.add_child(Style.heading("UNSPOKEN · КОМАНДА"))
	var members: Array = Net.lobby_view.get("members", [])
	var seats := GridContainer.new()
	seats.columns = 2 if members.size() > 4 else 1
	seats.add_theme_constant_override("h_separation", 24)
	seats.add_theme_constant_override("v_separation", 8)
	col.add_child(seats)
	for member: Dictionary in members:
		seats.add_child(PlayerTag.make(member, members, 16, Style.ink()))
	if Net.mode == "offline" and Net.is_host():
		var row := Style.row()
		var add := Style.button("+ Игрок")
		add.disabled = members.size() >= 8
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		row.add_child(add)
		var remove := Style.button("− Игрок")
		remove.disabled = members.size() <= 2
		remove.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		row.add_child(remove)
		col.add_child(row)
	col.add_child(Style.label("Без ботов и таймера. Не раскрывайте свои числа."))
	col.add_child(SeatShuffle.settings_row(Style.button, Style.label))
	var refs := Style.row()
	for item: Array in [["Правила", show_rules], ["Настройки", show_settings]]:
		var b := Style.button(item[0])
		b.pressed.connect(item[1])
		refs.add_child(b)
	col.add_child(refs)
	if Net.is_host():
		var start := Style.primary("Начать партию")
		start.name = "StartGame"
		start.disabled = members.size() < 2 or members.size() > 8
		start.pressed.connect(func(): _error.text = Net.start_game())
		col.add_child(start)
	else:
		col.add_child(Style.label("Ждём старта от хоста…"))
	var leave := Style.button("К выбору игры")
	LeaveGuard.wire(leave, "Выйти?", "Вернуться к выбору игры.", back_to_hub)
	col.add_child(leave)
	_error = Style.label("")
	col.add_child(_error)

func show_table() -> void:
	var table := Table.new()
	table.app = self
	_set_screen(table)

func popup(title: String, text: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.03, 0.08, 0.06, 0.85)
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.z_index = 110
	overlay.add_to_group("pause_allowed")
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = 72
	panel.offset_bottom = -40
	overlay.add_child(panel)
	var col := Style.column()
	panel.add_child(col)
	col.add_child(Style.heading(title))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = text
	body.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(body)
	var close := Style.primary("Понятно")
	close.pressed.connect(overlay.queue_free)
	col.add_child(close)

func show_rules() -> void:
	popup("ПРАВИЛА UNSPOKEN", RULES)

func show_settings() -> void:
	var settings := Settings.new()
	settings.make_panel = func(): return PanelContainer.new()
	settings.make_title = Style.heading
	settings.make_primary = Style.primary
	settings.ink = Style.ink()
	add_child(settings)

func back_to_hub() -> void:
	if Net.is_party() and Net.is_host():
		Net.return_to_party()
	else:
		Net.leave()
		_go_hub()

func _go_hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)

func _on_lobby() -> void:
	if Net.party_game == "the_mind" and not Net.in_game:
		show_lobby()

func _on_party(id: String) -> void:
	if id != "the_mind":
		_go_hub()

func _on_prefs() -> void:
	theme = Style.theme()
	get_tree().root.theme = theme
	if Net.in_game:
		show_table()
	elif Net.in_session():
		show_lobby()
	else:
		show_menu()
