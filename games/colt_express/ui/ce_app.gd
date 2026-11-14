extends Control
## Меню, лобби и стол «Кольт Экспресс». Запуск через хаб или main.tscn.
## Вид — CEStyle (вестерн-плакат, docs/styleboard_colt_express_western.png): строка «что делать»
## над поездом, поезд, строка бандитов, внизу рука / выбор / кадр действия, справа раунд и очередь карт.
## Логика партии — на хосте (CERules); стол только показывает view и шлёт действия через Net.

const Rules := preload("res://games/colt_express/logic/ce_rules.gd")
const Train := preload("res://games/colt_express/ui/ce_train.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
## Скругление карт по ассету (в картинке угол уже скруглён и залит белым — общий шейдер оставлял белые уголки).
const CORNERS := preload("res://games/colt_express/ui/ce_card_corners.gdshader")
const ART := "res://games/colt_express/art/"
## Цвет бандита по его миплу — точки на мини-картах очереди и в строке бандитов.
const BANDIT_COLORS := [Color("b65446"), Color("42748a"), Color("657c55"), Color("59625d"), Color("ddd0ae"), Color("906b96"), Color("d5a953"), Color("d5a953")]
const STEP_NAMES := {"о": "Открыто", "т": "Тоннель", "д": "Двойной", "н": "Обратно", "в": "Суматоха", "к": "Тряска"}
const STEP_HINTS := {
	"о": "Открытый ход: карты кладутся лицом вверх",
	"т": "Тоннель: карты кладутся рубашкой вверх",
	"д": "Двойной ход: каждый играет по две карты",
	"н": "Обратный порядок: ход идёт против часовой",
	"в": "Суматоха",
	"к": "Тряска: нельзя играть выстрел и удар",
}
const PHASES := {"travel": "Путешествие во времени", "mount": "Атака верхом", "select": "Выбор бандитов", "plan": "Планирование", "discard": "Сохранение руки", "reveal": "Ограбление", "choose": "Ограбление", "reaction": "Ограбление", "reserve": "Карты на следующий раунд", "reflex": "Рефлекторное действие", "animate": "Ограбление", "replay": "Повтор раунда", "match_replay": "Повтор партии", "end": "Итоги"}
const HAND_PHASES := ["plan", "discard", "reserve", "reflex"]
## Способности бандитов (ТЗ, п. 5) — подсказка в фазе выбора.
const ABILITIES := [
	["Туко", "Стреляет сквозь крышу — в бандита на другом уровне своего вагона"],
	["Док", "Начинает каждый раунд с семью картами вместо шести"],
	["Шейенна", "Ударом сразу забирает выбитый кошелёк"],
	["Джанго", "Выстрел отбрасывает цель на вагон назад"],
	["Призрак", "Первую карту раунда может сыграть закрытой"],
	["Белла", "В неё нельзя стрелять и бить, если есть другая цель"],
]
const RULES_TEXT := """[b]Цель.[/b] Пять раундов грабим поезд. Побеждает самый богатый бандит. В обычной партии тот, кто выпустил больше всех пуль, получает ещё $1000. При равенстве выигрывает получивший меньше пуль.

[b]Планирование.[/b] По очереди сыграйте карту действия — перетащите её из руки на поезд — или возьмите три карты. Шаги раунда показаны справа: в [i]тоннеле[/i] карты кладутся рубашкой вверх, в [i]двойном ходе[/i] играют по две карты, в [i]обратном порядке[/i] ход идёт в другую сторону.

[b]Ограбление.[/b] Сыгранные карты исполняются по очереди. Хост открывает каждую кнопкой «Следующее действие», цель и направление выбирает владелец карты. Пока идут действия, поезд мчится — пейзаж летит назад.

[b]Действия.[/b] Перемещение: в салоне — на соседний вагон, по крыше — на 1–3 вагона. Смена уровня — с крыши в салон и обратно. Добыча — взять жетон на своём уровне. Удар — выбить добычу и толкнуть бандита. Выстрел — в салоне в соседний вагон, по крыше — в ближайшего на линии; попадание кладёт пулю в колоду цели. Маршал выгоняет бандитов на крышу и даёт им пулю.

[b]Конец раунда.[/b] Срабатывает событие карты раунда. После раунда все действия повторяются подряд, после пятого — повтор всей партии и итоги."""

var screen: Control
var top: TopBar
var board: Control
var inset: Control
var banner_chip: PanelContainer
var banner_text: Label
var roster: HBoxContainer
var hand_area: VBoxContainer
var stage: PanelContainer
var preview_slot: PanelContainer
var controls: VBoxContainer
var side: VBoxContainer
var error: Label
var view: Dictionary = {}
var clip_key := ""
var action_hand: PrivateHand
var hidden_play := false
var hand_serial := -1
var clip_time := 0.0
var audio: AudioStreamPlayer
var _mini_preview: PanelContainer
var _pile_key := ""  # последняя открытая верхняя карта стопки — для анимации переворота
var _audio_pending := false  # звук действия — когда пройдёт пауза переворота
var _textures := {}


class Wall:
	extends Control
	## Фон экрана: едва заметные доски станционной стены.
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), CEStyle.c("bg"))
		var x := 0.0
		var i := 0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), CEStyle.c("plank"), 2)
			x += 46.0 + float((i * 37) % 23)
			i += 1


class MiniCard:
	extends Control
	## Мини-карта очереди: лицо (картинка со скруглением по ассету) или рубашка + точка цвета бандита;
	## текущая — в латунной рамке.
	var texture: Texture2D
	var owner_color := Color.TRANSPARENT
	var face_down := false
	var current := false

	func _ready() -> void:
		if not face_down and texture != null:
			var face := TextureRect.new()
			face.texture = texture
			face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			face.stretch_mode = TextureRect.STRETCH_SCALE
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var mat := ShaderMaterial.new()
			mat.shader = CORNERS
			face.material = mat
			add_child(face)
			face.position = Vector2(0, 4)
			face.size = custom_minimum_size - Vector2(0, 4)
		var dot := Dot.new()
		dot.color = owner_color
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)
		dot.position = Vector2(custom_minimum_size.x - 12, 0)
		dot.size = Vector2(12, 12)

	func _draw() -> void:
		var r := Rect2(Vector2(0, 4), size - Vector2(0, 4))
		if current:
			var frame := StyleBoxFlat.new()
			frame.bg_color = CEStyle.c("brass")
			frame.set_corner_radius_all(6)
			draw_style_box(frame, r.grow(3))
		if face_down or texture == null:
			CEStyle.draw_card_back(self, r)


class PlayedPile:
	extends Control
	## Общая стопка сыгранных карт (правила, стр. 3): в планировании карты ложатся лицом вверх
	## поверх предыдущей (в тоннеле и у Призрака — рубашкой); в грабеже стопка перевёрнута рубашкой
	## вверх, сверху — первая сыгранная. «Следующее действие» переворачивает верхнюю карту.
	var face: Texture2D  # null — сверху рубашка
	var below := 0  # сколько карт под верхней
	var flip := 1.0  # 0 → 1: переворот верхней карты (рубашка → лицо)
	var _face_rect: TextureRect

	func _ready() -> void:
		_face_rect = TextureRect.new()
		_face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_face_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = CORNERS
		_face_rect.material = mat
		add_child(_face_rect)

	func card_rect() -> Rect2:
		var depth := mini(below, 5) * 3.0
		var h := size.y - depth
		var w := h * 410.0 / 577.0
		return Rect2(Vector2((size.x - w) / 2, 0), Vector2(w, h))

	func _process(delta: float) -> void:
		if flip < 1.0:
			flip = minf(1.0, flip + delta / 0.45)
			queue_redraw()

	func _draw() -> void:
		var r := card_rect()
		for k in range(mini(below, 5), 0, -1):
			var under := Rect2(r.position + Vector2(0, k * 3.0), r.size)
			CEStyle.draw_card_back(self, under)
		# переворот: первая половина — сужается рубашка, вторая — расширяется лицо
		var showing_face := face != null and flip >= 0.5
		var squeeze := absf(cos(flip * PI)) if face != null else 1.0
		var w := r.size.x * maxf(0.02, squeeze)
		var top := Rect2(Vector2(r.get_center().x - w / 2, r.position.y), Vector2(w, r.size.y))
		if not showing_face:
			CEStyle.draw_card_back(self, top)
		if is_instance_valid(_face_rect):
			_face_rect.visible = showing_face
			_face_rect.texture = face
			_face_rect.position = top.position
			_face_rect.size = top.size


class Dot:
	extends Control
	## Точка цвета бандита в углу мини-карты.
	var color := Color.TRANSPARENT

	func _draw() -> void:
		if color.a > 0:
			draw_circle(size / 2, 6, CEStyle.c("panel"))
			draw_circle(size / 2, 4.5, color)


func _ready() -> void:
	Net.lobby_changed.connect(_lobby_changed)
	Net.game_started.connect(_show_table)
	Net.game_ended.connect(_show_lobby)
	Net.session_closed.connect(_show_menu)
	Net.party_game_changed.connect(_party_changed)
	Net.state_changed.connect(_update)
	Prefs.changed.connect(_theme_changed)
	if Net.in_game:
		_show_table()
	elif Net.in_session():
		_show_lobby()
	else:
		_show_menu()


func _theme_changed() -> void:
	if Net.in_game:
		_show_table()
	elif Net.in_session():
		_show_lobby()
	else:
		_show_menu()


func _party_changed(_id: String) -> void:
	if Net.party_game != "colt_express":
		_to_hub()


func _lobby_changed() -> void:
	if Net.in_session() and not Net.in_game and Net.party_game == "colt_express":
		_show_lobby()


func _base() -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = CEStyle.make_theme()
	var wall := Wall.new()
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(wall)
	wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Кнопка игры. kind: "primary" — одна главная на экране, "secondary", "quiet".
func _button(caption: String, font_size: int = CEStyle.BODY, kind: String = "secondary") -> Button:
	var btn := Button.new()
	btn.text = caption
	CEStyle.style_button(btn, kind, font_size)
	btn.custom_minimum_size.y = 40
	return btn


func _label(caption: String, font_size: int = CEStyle.BODY, kind: String = "regular", color_key: String = "ink") -> Label:
	return CEStyle.label(caption, font_size, kind, color_key)


func _wrap(lb: Label) -> Label:
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lb


func _add_button(parent: Node, caption: String, callback: Callable, kind: String = "secondary") -> Button:
	var btn := _button(caption, CEStyle.BODY, kind)
	parent.add_child(btn)
	btn.pressed.connect(callback)
	return btn


func _room_button(caption: String, font_size: int = CEStyle.BODY) -> Button:
	return _button(caption, font_size)


## Кнопки верхней полосы — тихие, в стиле игры.
func _bar_button(caption: String, font_size: int = 14) -> Button:
	return _button(caption, font_size, "quiet")


func _room_label(caption: String, font_size: int) -> Label:
	return _label(caption, font_size)


func _poster(pad: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", CEStyle.poster(pad))
	return p


func _tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


func _card_image(texture: Texture2D, minimum: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = texture
	image.custom_minimum_size = minimum
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var corners := ShaderMaterial.new()
	corners.shader = CORNERS
	image.material = corners
	return image


# --- Меню и лобби ------------------------------------------------------------

func _show_menu(_message: String = "") -> void:
	_base()
	var center := CenterContainer.new()
	screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 460
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	col.add_child(CEStyle.heading("Кольт Экспресс", 44))
	col.add_child(_label("Ограбление поезда на 2–6 бандитов", CEStyle.BODY, "regular", "muted"))
	col.add_child(RoomPanel.make("colt_express", _room_button, _room_label))
	_add_button(col, "Проверка на одном компьютере", func() -> void:
		Net.host_offline("colt_express")
		Net.set_bots(2))
	var back := _button("В хаб", CEStyle.BODY, "quiet")
	col.add_child(back)
	back.pressed.connect(_to_hub)


func _show_lobby() -> void:
	_base()
	var margin := MarginContainer.new()
	screen.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side_name in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side_name, 64)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.add_child(CEStyle.heading("Кольт Экспресс", 44))
	head.add_child(_label("Лобби · ограбление поезда на 2–6 бандитов", CEStyle.BODY, "regular", "muted"))
	page.add_child(head)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var host := Net.is_host()
	var members: Array = Net.lobby_view.get("members", [])
	# слева: бандиты и вид фигурок
	var left := _poster(16)
	left.custom_minimum_size.x = 360
	body.add_child(left)
	var lc := VBoxContainer.new()
	lc.add_theme_constant_override("separation", 8)
	left.add_child(lc)
	lc.add_child(CEStyle.heading("Бандиты · %d из 6" % members.size(), 18))
	var ink := CEStyle.c("ink")
	for member: Dictionary in members:
		lc.add_child(PlayerTag.make(member, members, CEStyle.BODY, ink))
	if host:
		if Net.mode == "offline":
			var players := HBoxContainer.new()
			players.add_theme_constant_override("separation", 8)
			lc.add_child(players)
			_add_button(players, "− Игрок", func() -> void: Net.set_bots(Net.bots - 1)).disabled = members.size() <= 2
			_add_button(players, "+ Игрок", func() -> void: Net.set_bots(Net.bots + 1)).disabled = members.size() >= 6
		else:
			_add_button(lc, "Пригласить друзей", Net.invite_friends)
	lc.add_child(HSeparator.new())
	lc.add_child(CEStyle.heading("Фигурки на поезде", 16))
	var looks := HBoxContainer.new()
	looks.add_theme_constant_override("separation", 8)
	lc.add_child(looks)
	var sprites: bool = Net.settings.get("ce_sprites", false)
	for i in 2:
		var pick := _choice_card(["Миплы", "Персонажи"][i], "", sprites == (i == 1), not host)
		var icon := TextureRect.new()
		icon.texture = _tex(ART + ("meeple_0.png" if i == 0 else "character_0.png"))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(56, 56)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var texts: VBoxContainer = pick.get_child(0).get_child(0)
		texts.add_child(icon)
		texts.move_child(icon, 0)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.custom_minimum_size.y = 100
		pick.pressed.connect(func() -> void: Net.set_setting("ce_sprites", i == 1))
		looks.add_child(pick)
	# справа: дополнения карточками
	var right := _poster(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 10)
	right.add_child(rc)
	rc.add_child(CEStyle.heading("Дополнения", 18))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rc.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var modules := [
		["ce_horses", "Лошади", "Скачите рядом с поездом"], ["ce_whiskey", "Виски", "Фляги дают лишнее действие"],
		["ce_time_car", "Машина времени", "Тайный выбор вагона"], ["ce_coach", "Дилижанс", "Охранник и заложники"],
		["ce_prison", "Тюремный вагон", "Сообщники за решёткой"], ["ce_marshal", "Маршал за игрока", "Один играет за закон · от 3"],
		["ce_cursed", "Проклятая добыча", "Добыча с подвохом"], ["ce_teams", "Команды по двое", "Только на 4 или 6"]]
	for module: Array in modules:
		var key: String = module[0]
		var on := bool(Net.settings.get(key, false))
		var locked: bool = (key == "ce_marshal" and members.size() < 3) or (key == "ce_teams" and (not members.size() in [4, 6] or Net.settings.get("ce_marshal", false)))
		var card := _choice_card(module[1], module[2], on, not host or locked)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 64
		card.pressed.connect(func() -> void: Net.set_setting(key, not on))
		grid.add_child(card)
	# низ: тихий выход слева, главная кнопка
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	page.add_child(foot)
	var back := _button("В хаб", CEStyle.BODY, "quiet")
	back.custom_minimum_size.x = 360
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	foot.add_child(back)
	LeaveGuard.wire(back, "Выйти из лобби?", "Вы вернётесь в хаб.", _to_hub)
	if host:
		var start := _button("Начать ограбление", 20, "primary")
		start.custom_minimum_size = Vector2(320, 56)
		start.disabled = not members.size() in range(2, 7)
		start.pressed.connect(func() -> void: error.text = Net.start_game())
		foot.add_child(start)
	else:
		var wait := _label("Ждём, когда хост начнёт ограбление", CEStyle.BODY, "bold", "muted")
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(wait)
	error = _label("", CEStyle.CAP, "regular", "accent")
	error.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(error)


## Карточка-переключатель лобби: название, подпись, выбранная — латунная рамка и подложка.
## Вместо CheckButton: ползунок в тёмной теме почти не виден.
func _choice_card(title: String, caption: String, on: bool, locked: bool) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_pressed = on
	card.disabled = locked
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := CEStyle.inset(10)
		var selected: bool = state in ["pressed", "hover_pressed"] or (state == "disabled" and on)
		if selected:
			box.bg_color = Color(CEStyle.c("brass"), 0.18)
			box.border_color = CEStyle.c("brass")
			box.set_border_width_all(2)
		if state in ["hover", "hover_pressed"]:
			box.bg_color = box.bg_color.lightened(0.05)
		if state == "disabled":
			box.bg_color = Color(box.bg_color, box.bg_color.a * 0.6)
		card.add_theme_stylebox_override(state, box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	card.add_child(row)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var name_label := _label(title, 16, "bold", "ink" if not locked or on else "muted")
	texts.add_child(name_label)
	if caption != "":
		texts.add_child(_label(caption, 13, "regular", "muted"))
	var badge := _label("ВКЛ" if on else "ВЫКЛ", 13, "bold", "brass" if on else "muted")
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if caption != "":
		row.add_child(badge)
	else:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return card


func _to_hub() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://hub/hub.tscn")


# --- Стол ----------------------------------------------------------------------

func _show_table() -> void:
	_base()
	top = TopBar.make(screen, "Кольт Экспресс", _bar_button, null, CEStyle.c("ink"), CEStyle.font("title"))
	top.info.add_theme_font_override("font", CEStyle.font("title"))
	_add_button(top.actions, "Правила", _rules, "quiet")
	_add_button(top.actions, "Настройки", _settings, "quiet")
	_add_button(top.actions, "Тема", _toggle_theme, "quiet")
	var exit := _button("Выйти", 14, "quiet")
	top.actions.add_child(exit)
	LeaveGuard.wire(exit, "Выйти из партии?", "Вы вернётесь в хаб.", _to_hub)
	var margin := MarginContainer.new()
	screen.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_top = TopBar.HEIGHT + 8.0
	margin.offset_left = 24
	margin.offset_right = -24
	margin.offset_bottom = -8
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	margin.add_child(main)
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 8)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(table)
	# строка «что делать»
	var banner := _poster(10)
	table.add_child(banner)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	banner.add_child(brow)
	banner_chip = PanelContainer.new()
	banner_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_chip.add_child(CEStyle.heading("", 17, "accent_ink"))
	brow.add_child(banner_chip)
	banner_text = _label("", CEStyle.BODY, "bold")
	banner_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	brow.add_child(banner_text)
	# поезд
	var frame := _poster(0)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true
	table.add_child(frame)
	board = Train.new()
	board.custom_minimum_size.y = 240
	frame.add_child(board)
	# бандиты
	roster = HBoxContainer.new()
	roster.add_theme_constant_override("separation", 8)
	roster.custom_minimum_size.y = 56
	table.add_child(roster)
	# низ: рука или сцена + колонка действий
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.custom_minimum_size.y = 220
	table.add_child(bottom)
	hand_area = VBoxContainer.new()
	hand_area.add_theme_constant_override("separation", 0)
	hand_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(hand_area)
	hand_area.add_child(CEStyle.heading("Ваша рука", CEStyle.CAP, "muted"))
	# рука «в руке»: карты на 25 % крупнее прежних 112×158, нижняя четверть уходит за край экрана
	# (владелец, 14.11). Держатель занимает место в раскладке, сама рука свисает из него вниз.
	var hand_holder := Control.new()
	hand_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_area.add_child(hand_holder)
	action_hand = PrivateHand.new()
	action_hand.card_size = Vector2(140, 198)
	action_hand.preview_delay = 0.25
	action_hand.drop_action = _drop_on_train
	action_hand.preview_requested.connect(_preview_action)
	action_hand.preview_closed.connect(_close_action_preview)
	hand_holder.add_child(action_hand)
	hand_holder.resized.connect(_place_hand.bind(hand_holder))
	stage = _poster(14)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(stage)
	preview_slot = _poster(8)
	preview_slot.custom_minimum_size.x = 156
	bottom.add_child(preview_slot)
	controls = VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.custom_minimum_size.x = 176
	bottom.add_child(controls)
	inset = Train.new()
	inset.detail = true
	inset.custom_minimum_size = Vector2(260, 150)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# правая панель
	var right := _poster(16)
	right.custom_minimum_size.x = 304
	main.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	side = VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(side)
	audio = AudioStreamPlayer.new()
	audio.bus = "SFX"
	screen.add_child(audio)
	if not Net.view.is_empty():
		_update(Net.view)


## Рука свисает из держателя: низ карты — на четверть её высоты ниже края экрана.
## PrivateHand ставит центр карты на card_size.y / 2 + 10 от своего верха.
func _place_hand(holder: Control) -> void:
	var card_h := action_hand.card_size.y
	var screen_bottom := screen.get_global_rect().end.y
	var top_y := screen_bottom + card_h * 0.25 - card_h - 10.0 - holder.get_global_rect().position.y
	action_hand.position = Vector2(0, top_y)
	action_hand.size = Vector2(holder.size.x, card_h + 18.0)


func _toggle_theme() -> void:
	Prefs.theme_mode = "light" if Prefs.dark_theme() else "dark"
	Prefs.save()
	Prefs.changed.emit()


## Окно поверх стола в стиле игры (правила).
func _popup(title: String, text: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.08, 0.05, 0.03, 0.7)
	overlay.z_index = 110
	overlay.add_to_group("pause_allowed")
	screen.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := _poster(24)
	overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 160
	panel.offset_right = -160
	panel.offset_top = 64
	panel.offset_bottom = -40
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(CEStyle.heading(title, CEStyle.H1))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = text
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("normal_font", CEStyle.font("regular"))
	body.add_theme_font_override("bold_font", CEStyle.font("bold"))
	body.add_theme_font_size_override("normal_font_size", CEStyle.BODY)
	body.add_theme_font_size_override("bold_font_size", CEStyle.BODY)
	body.add_theme_font_size_override("italics_font_size", CEStyle.BODY)
	body.add_theme_color_override("default_color", CEStyle.c("ink"))
	col.add_child(body)
	var close := _button("Понятно", CEStyle.BODY, "primary")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size.x = 200
	close.pressed.connect(overlay.queue_free)
	col.add_child(close)


func _rules() -> void:
	_popup("Правила «Кольт Экспресс»", RULES_TEXT)


func _settings() -> void:
	var settings := Settings.new()
	settings.make_panel = func() -> PanelContainer: return _poster(24)
	settings.make_title = func(text: String) -> Control: return CEStyle.heading(text, CEStyle.H1)
	settings.make_primary = func(text: String) -> Button: return _button(text, CEStyle.BODY, "primary")
	settings.ink = CEStyle.c("ink")
	add_child(settings)


func _send(kind: String, values: Dictionary = {}) -> void:
	values["serial"] = view.get("serial", -1)
	Net.send_action(kind, values)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _player(seat: int) -> String:
	var names: Array = view.get("seat_names", [])
	if seat >= 0 and seat < names.size():
		var info: Variant = names[seat]
		if info is Dictionary:
			return str(info.get("name", "Игрок %d" % (seat + 1)))
		return str(info)
	return "Игрок %d" % (seat + 1)


func _caption(card: Dictionary) -> String:
	var kind: String = card.get("kind", "")
	if kind == "event":
		return Rules.EVENTS.get(card.event, "Событие")
	if kind == "hidden":
		return "Закрытая карта"
	return Rules.ACTIONS.get(kind, "")


func _character_name(id: int) -> String:
	return "Маршал" if id == 6 else ("Мэй" if id == 7 else Rules.NAMES[id])


## Бандит(ы) игрока за местом seat — имя для подсказок («Док», «Туко и Белла»).
func _bandits_of(seat: int) -> String:
	var names: Array[String] = []
	for b: Dictionary in view.get("board", {}).get("bandits", []):
		if int(b.seat) == seat and int(b.id) != 6:
			names.append(_character_name(b.id))
	return " и ".join(names)


func _set_banner(chip: String, text: String, kind: String) -> void:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4)
	box.set_content_margin_all(4)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.bg_color = CEStyle.c("accent") if kind == "mine" else (CEStyle.c("brass") if kind == "watch" else CEStyle.c("inset"))
	banner_chip.add_theme_stylebox_override("panel", box)
	var chip_label: Label = banner_chip.get_child(0)
	chip_label.text = chip.to_upper()
	chip_label.add_theme_color_override("font_color", CEStyle.c("accent_ink") if kind != "idle" else CEStyle.c("muted"))
	banner_chip.visible = chip != ""
	banner_text.text = text


func _update(state: Dictionary) -> void:
	view = state
	if not is_instance_valid(controls) or not controls.is_inside_tree():
		return
	var phase: String = view.get("phase", "select")
	var active: int = view.get("turn", -1)
	var mine: bool = active == int(view.get("seat", -1)) and not view.get("spectator", false)
	top.info.text = ("Раунд %d из 5 · " % view.round if view.round > 0 else "") + PHASES.get(phase, phase)
	if phase == "match_replay":
		top.info.text = "Повтор партии · раунд %d из 5" % view.replay_round
	if hand_serial != int(view.serial):
		hand_serial = int(view.serial)
		hidden_play = false
	var clip: Dictionary = view.get("clip", {})
	var key := "%s/%s/%s" % [phase, view.get("replay_round", 0), clip.get("serial", -1)]
	if not clip.is_empty() and key != clip_key:
		clip_time = float(view.get("progress", 0))
		_audio_pending = true
	clip_key = key
	_present_clip()
	_update_banner(phase, active, mine)
	_update_roster(active)
	_update_side(phase)
	_update_bottom(phase, active, mine)


func _update_banner(phase: String, active: int, mine: bool) -> void:
	var who := _player(active)
	var card: Dictionary = view.get("card", {})
	var card_text := _caption(card) + (" · " + _character_name(card.id) if int(card.get("id", -1)) >= 0 else "")
	var queue: Array = view.get("queue", [])
	var progress := "Действие %d из %d" % [mini(int(view.get("cursor", 0)) + 1, maxi(1, queue.size())), maxi(1, queue.size())]
	var hotseat_wait: bool = active >= 0 and not mine and view.get("hotseat", false)
	match phase:
		"select":
			if mine:
				_set_banner("Ваш ход", "Выберите своего бандита", "mine")
			else:
				_set_banner("Ходит", "Бандита выбирает " + who, "watch")
		"travel":
			_set_banner("Ваш ход" if mine else "Ходит", "Выберите, где появиться из машины времени" if mine else who + " выбирает, где появиться", "mine" if mine else "watch")
		"mount":
			if view.get("can_mount", false):
				_set_banner("Ваш ход", "Верхом: войдите в вагон %d или скачите дальше" % view.mount_car, "mine")
			else:
				_set_banner("Ждём", "Всадники выбирают, где войти в поезд", "watch")
		"plan":
			var step: String = STEP_NAMES.get(view.steps[view.step], "")
			if mine:
				var hint := "Перетащите карту на поезд — или возьмите 3 карты"
				if view.steps[view.step] == "т":
					hint = "Тоннель: карта ляжет рубашкой вверх — перетащите её на поезд или возьмите 3 карты"
				_set_banner("Ваш ход", hint, "mine")
			else:
				_set_banner("Ходит", "%s (%s) планирует · шаг «%s»" % [who, _bandits_of(active), step], "watch")
		"discard":
			_set_banner("Ваш ход" if mine else "Ходит", "Сбросьте лишние карты: перетащите на поезд, затем «Готово»" if mine else who + " сохраняет руку", "mine" if mine else "watch")
		"reserve":
			_set_banner("Ваш ход" if mine else "Ходит", ("Отложите карты на следующий раунд (можно ещё %d) и нажмите «Готово»" % view.reserve_left) if mine else who + " откладывает карты", "mine" if mine else "watch")
		"reflex":
			_set_banner("Ваш ход" if mine else "Ходит", "Рефлекторное действие: сыграйте карту или пропустите" if mine else who + " решает, ответить ли", "mine" if mine else "watch")
		"reveal":
			# карта ещё лежит рубашкой вверх — не показываем, что на ней
			var event_next: bool = view.card.get("kind", "") == "event"
			if Net.is_host():
				_set_banner(progress, ("Событие раунда" if event_next else "Верхняя карта стопки") + " — нажмите «Следующее действие»", "mine")
			else:
				_set_banner(progress, "Хост переворачивает верхнюю карту стопки", "watch")
		"choose", "reaction":
			if mine:
				_set_banner("Ваш выбор", card_text + ": выберите вариант внизу", "mine")
			else:
				_set_banner(progress, "%s выбирает: %s" % [who, card_text], "watch")
		"animate":
			_set_banner(progress, card_text, "watch")
		"replay":
			_set_banner("Повтор", "Весь раунд подряд — смотрите, что произошло", "watch")
		"match_replay":
			_set_banner("Повтор партии", "Раунд %d из 5" % view.replay_round, "watch")
		"end":
			_set_banner("Итоги", "Ограбление окончено", "watch")
		_:
			_set_banner("", PHASES.get(phase, phase), "idle")
	if hotseat_wait and phase in ["select", "mount", "travel", "plan", "discard", "choose", "reaction", "reserve", "reflex"]:
		_set_banner("Передайте ход", "Следующим ходит %s — передайте ему управление (кнопка справа внизу)" % who, "mine")


## Строка бандитов: портрет, бандит и игрок, пули в барабане, добыча. У того, чей ход, — латунная рамка.
func _update_roster(active: int) -> void:
	_clear(roster)
	for b: Dictionary in view.board.bandits:
		var id: int = b.id
		var seat: int = b.seat
		var me: bool = seat == int(view.get("seat", -1)) and not view.get("spectator", false)
		var panel := PanelContainer.new()
		var box := CEStyle.poster(8)
		if seat == active:
			box.border_color = CEStyle.c("brass")
			box.set_border_width_all(3)
		panel.add_theme_stylebox_override("panel", box)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		roster.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var face := TextureRect.new()
		face.texture = _tex(ART + ("character_%d.png" % id if id < 6 else "meeple_%d.png" % id))
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(36, 40)
		row.add_child(face)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", -3)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(names)
		var title := _label(_character_name(id) + (" · вы" if me else ""), 15, "bold")
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names.add_child(title)
		var player := _label(_player(seat), 13, "regular", "muted")
		player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names.add_child(player)
		var stats := VBoxContainer.new()
		stats.add_theme_constant_override("separation", -3)
		row.add_child(stats)
		var ammo: int = b.get("ammo", 0)
		var pips := _label("●".repeat(mini(ammo, 6)) + "○".repeat(maxi(0, 6 - ammo)) if ammo <= 6 else "● × %d" % ammo, 12, "regular", "muted")
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pips.tooltip_text = "Пули в барабане: %d" % ammo
		pips.mouse_filter = Control.MOUSE_FILTER_PASS
		stats.add_child(pips)
		var loot_text := "мешков: %d" % int(b.get("bags", 0))
		if me:
			var total := 0
			for item: Dictionary in view.get("bag", []):
				total += int(item.value)
			loot_text = "$ %d" % total
		var loot := _label(loot_text, 13, "bold")
		loot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.add_child(loot)


## Общая стопка сыгранных карт справа. Переворот проигрывается, когда меняется верхняя открытая карта.
func _add_pile(phase: String) -> void:
	var queue: Array = view.get("queue", [])
	var cursor: int = view.get("cursor", 0)
	var title := ""
	var caption := ""
	var face: Texture2D = null
	var below := 0
	var face_key := ""
	if phase in HAND_PHASES:
		if queue.is_empty():
			return
		var last: Dictionary = queue.back()
		title = "Сыграно в раунде"
		caption = "%d карт · сверху последняя%s" % [queue.size(), " (закрытая)" if last.get("kind", "") == "hidden" else ""]
		if last.get("kind", "") != "hidden":
			face = _action_texture(last)
		below = queue.size() - 1
	elif phase == "reveal":
		var left := queue.size() - cursor
		if left <= 0:
			return
		title = "Стопка действий"
		caption = "Рубашкой вверх · осталось %d · хост переворачивает верхнюю" % left
		below = left - 1
	elif phase in ["choose", "reaction", "animate", "replay", "match_replay"]:
		var card: Dictionary = view.get("clip", {}).get("card", view.get("card", {})) if phase in ["animate", "replay", "match_replay"] else view.get("card", {})
		if card.is_empty() or not Rules.ACTIONS.has(card.get("kind", "")):
			return
		title = "Стопка действий" if phase in ["choose", "reaction", "animate"] else "Повтор"
		face = _action_texture(card)
		below = maxi(0, queue.size() - cursor - 1) if phase in ["choose", "reaction", "animate"] else 0
		caption = "Открыта: %s · %s" % [_caption(card), _character_name(card.id)] if int(card.get("id", -1)) >= 0 else _caption(card)
		face_key = "%s/%s/%s/%s" % [view.round, cursor, card.get("kind", ""), card.get("id", -1)]
	else:
		return
	side.add_child(HSeparator.new())
	side.add_child(CEStyle.heading(title, 16))
	var pile := PlayedPile.new()
	pile.custom_minimum_size = Vector2(264, 172)
	pile.face = face
	pile.below = below
	# переворот — только когда открылась новая карта (а не при каждом обновлении view)
	if face_key != "" and face_key != _pile_key and phase in ["choose", "reaction", "animate"]:
		pile.flip = 0.0
	_pile_key = face_key if face_key != "" else _pile_key
	if face != null:
		pile.mouse_entered.connect(_show_pile_preview.bind(pile))
		pile.mouse_exited.connect(_close_mini_preview)
	side.add_child(pile)
	side.add_child(_wrap(_label(caption, 13, "regular", "muted")))


func _show_pile_preview(pile: PlayedPile) -> void:
	_close_mini_preview()
	_mini_preview = _poster(8)
	_mini_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_preview.z_index = 95
	_mini_preview.add_child(_card_image(pile.face, Vector2(200, 282)))
	screen.add_child(_mini_preview)
	var at := pile.get_global_rect()
	_mini_preview.position = Vector2(at.position.x - 236, clampf(at.position.y - 40, TopBar.HEIGHT + 8, screen.size.y - 310))


## Правая панель: раунд, шаги, сыгранные карты, заложники, цели маршала, кнопка хоста.
func _update_side(phase: String) -> void:
	_close_mini_preview()
	_clear(side)
	if view.round > 0:
		side.add_child(CEStyle.heading("Раунд %d из 5" % (view.replay_round if phase == "match_replay" else view.round), 20))
		var round_art := TextureRect.new()
		round_art.texture = _tex(ART + "round_%d.webp" % view.round_card)
		round_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		round_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		round_art.custom_minimum_size = Vector2(264, 120)
		side.add_child(round_art)
		var steps := str(view.get("steps", ""))  # строка кодов шагов раунда, напр. «отод»
		if not steps.is_empty():
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			row.add_theme_constant_override("v_separation", 6)
			side.add_child(row)
			var current: int = view.step if phase in ["plan", "discard"] else steps.length()
			for i in steps.length():
				var chip := PanelContainer.new()
				var box := StyleBoxFlat.new()
				box.set_corner_radius_all(4)
				box.set_content_margin_all(4)
				box.content_margin_left = 6
				box.content_margin_right = 6
				box.bg_color = CEStyle.c("brass") if i == current else (CEStyle.c("inset") if i > current else Color(CEStyle.c("inset"), 0.5))
				chip.add_theme_stylebox_override("panel", box)
				chip.add_child(_label(STEP_NAMES.get(steps[i], "?"), 12, "bold", "accent_ink" if i == current else ("ink" if i > current else "muted")))
				row.add_child(chip)
			if phase == "plan":
				side.add_child(_wrap(_label(STEP_HINTS.get(steps[view.step], ""), 13, "regular", "muted")))
	if phase == "select":
		side.add_child(CEStyle.heading("Способности", 20))
		for ability: Array in ABILITIES:
			side.add_child(_label(ability[0], 15, "bold"))
			side.add_child(_wrap(_label(ability[1], 13, "regular", "muted")))
	_add_pile(phase)
	for actor: Dictionary in view.board.bandits:
		var h: int = actor.get("hostage", -1)
		if h >= 0:
			side.add_child(_label("%s · %s" % [_character_name(actor.id), Rules.HOSTAGES[h]], 14))
	var goals: Array = view.get("marshal_goals", [])
	if not goals.is_empty():
		side.add_child(HSeparator.new())
		side.add_child(CEStyle.heading("Цели маршала", 16))
		for goal: Variant in goals:
			var title: String = ("Арестовать " + _character_name(goal)) if goal is int else {"brawler": "Сохранить карту драки", "mail": "Вернуть сумку", "keys": "Вернуть двух сообщников", "cylinder": "Опустошить барабан", "dodge": "Уклониться от пуль", "all_hit": "Попасть в каждого бандита", "four_hits": "Попасть четырежды в одного бандита"}.get(goal, "")
			side.add_child(_wrap(_label(title, 14)))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	if phase == "reveal":
		if Net.is_host():
			_add_button(side, "Следующее действие", func() -> void: _send("next"), "primary")
		else:
			side.add_child(_wrap(_label("Следующее действие откроет хост", 13, "regular", "muted")))
	if phase == "end" and Net.is_host():
		_add_button(side, "В лобби", Net.end_game, "primary")


## Низ стола: рука в фазах карт, иначе — сцена (выбор, кадр действия, итоги) и колонка кнопок.
func _update_bottom(phase: String, active: int, mine: bool) -> void:
	var show_hand: bool = not view.hand.is_empty() and phase in HAND_PHASES
	hand_area.visible = show_hand
	preview_slot.visible = show_hand
	stage.visible = not show_hand
	if show_hand:
		_sync_hand()
		_preview_placeholder()
	else:
		_close_action_preview()
	if is_instance_valid(inset.get_parent()):
		inset.get_parent().remove_child(inset)
	_clear(stage)
	_clear(controls)
	if active >= 0 and not mine and view.get("hotseat", false) and phase in ["select", "mount", "travel", "plan", "discard", "choose", "reaction", "reserve", "reflex"]:
		var pass_btn := _add_button(controls, "Передать · " + _player(active), func() -> void: _send("ce_view_seat", {"seat": active}), "primary")
		pass_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	match phase:
		"select":
			_stage_select(mine)
		"travel":
			_stage_travel(mine)
		"mount":
			_stage_mount()
		"choose", "reaction":
			_stage_card(mine)
		"reveal", "animate", "replay", "match_replay":
			_stage_card(false)
		"end":
			_stage_end()
	if phase in HAND_PHASES and mine:
		_hand_controls(phase)
	controls.visible = controls.get_child_count() > 0 or show_hand
	if not show_hand and stage.get_child_count() == 0:
		var wait := _label("Ждём: " + _player(active) if active >= 0 else "", CEStyle.BODY, "bold", "muted")
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stage.add_child(wait)


func _stage_select(mine: bool) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	stage.add_child(col)
	col.add_child(CEStyle.heading("Бандиты" if mine else "Выбор бандитов", 18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var ids := range(Rules.NAMES.size())
	if view.board.get("prison", false):
		ids.append(7)
	for i: int in ids:
		var taken: bool = view.board.bandits.any(func(b: Dictionary) -> bool: return b.id == i)
		var card := _choice_card(_character_name(i), "", taken, taken or not mine)
		var icon := TextureRect.new()
		icon.texture = _tex(ART + ("character_%d.png" if view.sprites and i < 6 else "meeple_%d.png") % i)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(60, 90)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inner: HBoxContainer = card.get_child(0)
		var holder := VBoxContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.alignment = BoxContainer.ALIGNMENT_CENTER
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_child(holder)
		var texts: Control = inner.get_child(0)
		inner.remove_child(texts)
		holder.add_child(icon)
		holder.add_child(texts)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = "Занят" if taken else ""
		if mine and not taken:
			card.pressed.connect(func() -> void: _send("select", {"id": i}))
		row.add_child(card)


func _stage_travel(mine: bool) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	stage.add_child(col)
	col.add_child(CEStyle.heading("Машина времени", 18))
	if not mine:
		col.add_child(_label("Игрок выбирает тайно", CEStyle.BODY, "regular", "muted"))
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	col.add_child(row)
	for car in range(view.cars + 1):
		_add_button(row, "Паровоз" if car == 0 else "Вагон %d" % car, func() -> void: _send("travel", {"car": car}))


func _stage_mount() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	stage.add_child(col)
	col.add_child(CEStyle.heading("Атака верхом", 18))
	if not view.get("can_mount", false):
		col.add_child(_label("Ждём остальных всадников", CEStyle.BODY, "regular", "muted"))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_add_button(row, "Войти в вагон %d" % view.mount_car, func() -> void: _send("mount", {"land": true}), "primary")
	if view.mount_car > 1:
		_add_button(row, "Скакать дальше", func() -> void: _send("mount", {"land": false}))


## Раскрытая карта крупно + выбор владельца (choose/reaction) или кадр действия (врезка).
func _stage_card(choosing: bool) -> void:
	var card: Dictionary = view.get("card", {})
	var clip: Dictionary = view.get("clip", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	stage.add_child(row)
	if view.phase == "reveal" and card.get("kind", "") != "event":
		# до переворота карту не показываем: рубашка, как верх стопки справа
		var back := PlayedPile.new()
		back.custom_minimum_size = Vector2(124, 176)
		row.add_child(back)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 8)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(CEStyle.heading("Верхняя карта стопки", CEStyle.H1))
		info.add_child(_wrap(_label("Карта лежит рубашкой вверх. «Следующее действие» перевернёт её, через 2 секунды действие разыграется на поезде.", CEStyle.BODY, "regular", "muted")))
		return
	if Rules.ACTIONS.has(card.get("kind", "")):
		row.add_child(_card_image(_action_texture(card), Vector2(124, 176)))
	elif card.get("kind", "") == "event" and view.round_card >= 0:
		row.add_child(_card_image(_tex(ART + "round_%d.webp" % view.round_card), Vector2(176, 128)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if not card.is_empty():
		var who := " · " + _character_name(card.id) if int(card.get("id", -1)) >= 0 else ""
		col.add_child(CEStyle.heading(_caption(card) + who, CEStyle.H1))
	if choosing:
		col.add_child(_label("Выберите вариант:", CEStyle.BODY, "regular", "muted"))
		var options := HFlowContainer.new()
		options.add_theme_constant_override("h_separation", 10)
		options.add_theme_constant_override("v_separation", 10)
		col.add_child(options)
		for i in view.options.size():
			var choice: Dictionary = view.options[i]
			var btn := _add_button(options, choice.label, func() -> void: _send("choose", {"index": i}))
			btn.custom_minimum_size = Vector2(160, 48)
		return
	if not clip.is_empty():
		if not clip.get("applied", true):
			col.add_child(_label("Действие невозможно — нет допустимой цели", CEStyle.BODY, "bold", "accent"))
		col.add_child(inset)
		inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	elif view.phase == "reveal":
		col.add_child(_wrap(_label("Карта лежит рубашкой вверх. «Следующее действие» перевернёт её, через 2 секунды действие разыграется на поезде.", CEStyle.BODY, "regular", "muted")))


func _stage_end() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	stage.add_child(col)
	col.add_child(CEStyle.heading("Итоги ограбления", CEStyle.H1))
	var results: Array = view.get("results", []).duplicate()
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("score", 0)) > int(b.get("score", 0)))
	for i in results.size():
		var result: Dictionary = results[i]
		var text := ""
		if result.has("team"):
			text = "%s · команда %d · $%d" % [_player(result.seat), result.team, result.score]
		elif result.has("marshal_goals"):
			text = "%s · маршал · целей %d из 5" % [_player(result.seat), result.marshal_goals]
		else:
			text = "%s · $%d · пуль получено: %d" % [_player(result.seat), result.score, result.received]
		if result.get("co_winner", false):
			text += " · победа вместе с маршалом"
		col.add_child(_label(("★ " if i == 0 else "   ") + text, CEStyle.BODY, "bold" if i == 0 else "regular", "ink" if i == 0 else "muted"))


## Кнопки фазы карт справа от руки: взять три (вторичная — главное действие тут перетаскивание).
func _hand_controls(phase: String) -> void:
	if phase == "plan":
		var draw := _add_button(controls, "Взять 3 карты", func() -> void: _send("draw"))
		draw.disabled = view.flask_plays > 0
		draw.custom_minimum_size.y = 48
		if view.can_draw_idea and view.flask_plays == 0:
			_add_button(controls, "Взять «Блестящую идею»", func() -> void: _send("draw_idea")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for flask: Dictionary in view.flasks:
			_add_button(controls, "%s · %d" % ["Старый виски" if flask.old else "Виски", flask.uses], func() -> void: _send("flask", {"index": flask.index}))
		if view.step == 0 and view.hand.any(func(c: Dictionary) -> bool: return c.id == 4):
			var hide := _button("Скрыть карту Призрака", 14)
			hide.toggle_mode = true
			hide.button_pressed = hidden_play
			hide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hide.toggled.connect(func(on: bool) -> void:
				hidden_play = on
				hide.text = ("✓ " if on else "") + "Скрыть карту Призрака")
			hide.text = ("✓ " if hidden_play else "") + "Скрыть карту Призрака"
			controls.add_child(hide)
	else:
		_add_button(controls, "Пропустить" if phase == "reflex" else "Готово", func() -> void: _send("keep"), "primary").custom_minimum_size.y = 48


func _sync_hand() -> void:
	var cards: Array = []
	var copies := {}
	for i in view.hand.size():
		var card: Dictionary = view.hand[i]
		var base := "%s/%s" % [card.id, card.kind]
		var copy: int = copies.get(base, 0)
		copies[base] = copy + 1
		cards.append({
			"key": "%d/%s/%d" % [view.seat, base, copy],
			"index": i,
			"serial": view.serial,
			"texture": _action_texture(card),
			"material": _corner_material(),
			"card": card
		})
	action_hand.sync_cards(cards, action_hand.order)


var _hand_material: ShaderMaterial


func _corner_material() -> ShaderMaterial:
	if _hand_material == null:
		_hand_material = ShaderMaterial.new()
		_hand_material.shader = CORNERS
	return _hand_material


func _action_texture(card: Dictionary) -> Texture2D:
	return _tex(ART + "action_%d_%s.webp" % [card.id, card.kind])


func _drop_on_train(entry: Dictionary, point: Vector2) -> bool:
	if entry.is_empty() or not Rect2(Vector2.ZERO, board.size).has_point(board.get_global_transform_with_canvas().affine_inverse() * point):
		return false
	var phase: String = view.phase
	if view.seat != view.turn or view.get("spectator", false) or phase not in HAND_PHASES:
		return false
	var kind: String = entry.card.kind
	if phase in ["plan", "reflex"] and kind == "bullet":
		return false
	if phase == "reserve" and view.reserve_left == 0:
		return false
	if phase == "plan" and view.steps[view.step] == "к" and kind in ["shoot", "punch"]:
		return false
	_submit_drop.call_deferred(entry.serial, phase, entry.index, hidden_play)
	return true


func _submit_drop(serial: int, phase: String, index: int, hidden: bool) -> void:
	if serial == view.serial and phase == view.phase and view.seat == view.turn:
		_send("play" if phase == "plan" else phase, {"index": index, "hidden": hidden})


## Крупный просмотр карты руки — в постоянном окошке справа от руки (не перекрывает поезд).
func _preview_action(entry: Dictionary) -> void:
	_clear(preview_slot)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_slot.add_child(col)
	col.add_child(_card_image(entry.texture, Vector2(140, 150)))
	col.add_child(CEStyle.heading(_caption(entry.card), 17))
	var hint := _wrap(_label(_action_hint(entry.card.kind), 12, "regular", "muted"))
	hint.custom_minimum_size.x = 140
	col.add_child(hint)


func _close_action_preview() -> void:
	if is_instance_valid(preview_slot) and preview_slot.visible:
		_preview_placeholder()


func _preview_placeholder() -> void:
	_clear(preview_slot)
	var tip := _wrap(_label("Наведите на карту, чтобы рассмотреть её", 13, "regular", "muted"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.custom_minimum_size.x = 140
	preview_slot.add_child(tip)


func _action_hint(kind: String) -> String:
	return {
		"move": "В салоне — на соседний вагон, по крыше — на 1–3",
		"level": "С крыши в салон или обратно",
		"shoot": "Пуля в колоду бандита в зоне выстрела",
		"punch": "Выбить добычу и толкнуть бандита",
		"loot": "Взять жетон на своём уровне",
		"marshal": "Сдвинуть маршала на соседний вагон",
		"bullet": "Пуля — бесполезная карта в руке",
		"ride": "Пересесть на лошадь или с неё",
		"idea": "Карта сообщника",
		"capture": "Арест бандита маршалом",
		"move_plus": "Перемещение с бонусом",
		"level_plus": "Смена уровня с бонусом",
	}.get(kind, "")


## Крупный просмотр мини-карты очереди — слева от правой панели.
func _show_mini_preview(small: MiniCard, queued: Dictionary) -> void:
	_close_mini_preview()
	_mini_preview = _poster(8)
	_mini_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_preview.z_index = 95
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_preview.add_child(col)
	col.add_child(_card_image(small.texture, Vector2(156, 220)))
	var id: int = queued.get("id", -1)
	col.add_child(CEStyle.heading(_caption(queued), 17))
	if id >= 0:
		col.add_child(_label(_character_name(id), 14, "regular", "muted"))
	screen.add_child(_mini_preview)
	var at := small.get_global_rect()
	_mini_preview.position = Vector2(at.position.x - 196, clampf(at.position.y - 80, TopBar.HEIGHT + 8, screen.size.y - 300))


func _close_mini_preview() -> void:
	if is_instance_valid(_mini_preview):
		_mini_preview.queue_free()
	_mini_preview = null


func _process(delta: float) -> void:
	if not is_instance_valid(board) or not board.is_inside_tree() or view.get("clip", {}).is_empty() or Net.paused:
		return
	clip_time += delta
	# пока показываются действия, поезд мчится: пейзаж едет; в выборе и в паузе переворота — стоит (владелец, 14.11)
	if _anim_time() >= 0.0:
		board.scroll += delta * CEStyle.SCROLL_SPEED
	_present_clip()


## Время анимации действия: после переворота карты хост ждёт FLIP_LEAD секунд (clip.lead), только потом поезд движется.
func _anim_time() -> float:
	var clip: Dictionary = view.get("clip", {})
	return clip_time - (float(clip.get("lead", 0.0)) if view.get("phase", "") == "animate" else 0.0)


func _present_clip() -> void:
	var t := _anim_time()
	board.present(view, maxf(0.0, t))
	inset.present(view, maxf(0.0, t))
	if _audio_pending and t >= 0.0 and not view.get("clip", {}).is_empty():
		_audio_pending = false
		_play_audio(view.clip)


func _play_audio(clip: Dictionary) -> void:
	if not clip.get("applied", false):
		return
	var kind: String = clip.card.kind
	var path := ART + "%s.wav" % kind
	if ResourceLoader.exists(path):
		audio.stream = load(path)
		audio.play()
