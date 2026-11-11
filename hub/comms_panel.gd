extends "res://hub/float_panel.gd"
## Окно «Общение»: чат пати и мини-игры в одном плавающем окне. Одно на всю игру, живёт в своём слое
## поверх любого экрана (создаёт Net.chat.panel()), поэтому место, размер, черновик и вкладки не теряются.
##
## Вкладки: «Всем» всегда слева, дальше личные разговоры и «Команда» по свежести, затем партии мини-игр
## (ход соперника — партия встаёт первой среди партий и мигает), последняя — «Игры»: новая партия и приглашения.
## Клавиши: Z — чат, X — мини-игры (открыть / свернуть); Enter — писать в чат; 1–8 — быстрые реплики.
## Цвета берутся от текущей игры, свёрнутая кнопка — кнопка её верхней полосы.
## Наведение на сообщение — «ответить» и реакция; скрепка, Ctrl+V или перетаскивание файла — картинка/GIF.
## Поле мини-игры при наведении вырастает до обычного размера окна, если окно уменьшено (Настройки → Геймплей).
## Данные: Net.chat (hub/chat_net.gd) и Net.minigames (hub/minigames/mg_net.gd).

const Board := preload("res://hub/minigames/mg_board.gd")
const REACTIONS := ["Думаю...", "Блефую!", "Кидаю кость!", "Хитро!", "Ой…", "Мне повезёт!", "Удивительно!", "Эй, вы ещё здесь?"]
const ICONS := {"chess": "♙", "checkers": "◉", "go": "○"}
const SIDE_NAMES := {"chess": ["белые", "чёрные"], "checkers": ["белые", "чёрные"], "go": ["чёрные", "белые"]}
const EMOTE := Color("ffd479")
const SYSTEM := Color("b8c7c0")
const GAMES_TAB := "g:"
const LIFT := 0.14  # тёмная кнопка полосы: плавающая кнопка и полоса вкладок настолько светлее
const SHADE := 0.12  # светлая кнопка полосы: настолько темнее
const LOOKS_PATH := "user://comms_colors.cfg"
static var _looks := {}  # игра → [заливка кнопки «Общение», цвет её текста]

var view := "chat"  # что показано: "chat" или "mg"
var _add_button: Button  # «+» в шапке (личные/команда); в «Крови на часовой башне» скрыт
var proxies := 0  # сколько на экране чатов игр (K12ChatPanel): есть хоть один — работают Enter и реплики 1–8
var quick_open := false

var _chat: Node
var _mg: Node
var _chat_box: Control
var _game_box: Control
var _input: LineEdit
var _scroll: ScrollContainer
var _list: VBoxContainer
var _quick: HFlowContainer
var _quick_btn: Button
var _reply_bar: HBoxContainer
var _reply_label: Label
var _attach_bar: HBoxContainer
var _attach_label: Label
var _notice: Label
var _hover_bar: PanelContainer
var _hover_row: Control
var _emoji_open := false
var _menu: PanelContainer
var _viewer: Control
var _rows: Dictionary = {}  # id сообщения → плашка
var _reply: Dictionary = {}
var _pending_image := PackedByteArray()
var _stick := 0  # сколько кадров ещё прижимать прокрутку к низу
var _shown := ""
var _colors_key := ""
var _draft := ""
var _context_key := "?"
var _context_clock := 0.0
var _was_party := false
# мини-игры
var _board  # hub/minigames/mg_board.gd
var _status: Label
var _game_shown := "?"
var _pick_game := "chess"
var _pick_size := 9
var _resign_armed := false


func _init() -> void:
	if _looks.is_empty():
		_load_looks()
	# до входа в дерево окно уже спрашивают (watching, unread) — данные нужны сразу
	_chat = Net.chat
	_mg = Net.minigames


func _ready() -> void:
	key = "comms"
	title = "Общение"
	base_size = Vector2(340, 330)
	mode = Mode.CLOSED
	default_place = func(rect_size: Vector2, parent_size: Vector2) -> Vector2:
		return (parent_size - rect_size - Vector2(14, 14)).max(Vector2.ZERO)
	mini_factory = _make_mini
	var look := Theme.new()
	look.default_font = HubStyle.font("medium")
	theme = look
	set_palette(_accent())
	super._ready()
	tab_selected.connect(_on_tab)
	tab_closed.connect(_on_tab_closed)
	mode_changed.connect(_on_mode)
	_chat.changed.connect(_sync)
	_chat.entry_added.connect(_on_entry)
	_chat.reactions_changed.connect(_fill_chips)
	_chat.notice.connect(_say)
	_mg.changed.connect(_sync)
	_mg.notice.connect(_say)
	Net.lobby_changed.connect(_on_lobby)
	Net.state_changed.connect(func(_view: Dictionary): _sync())
	get_tree().root.files_dropped.connect(_on_files_dropped)
	_colors_key = _member_colors_key()
	_sync()


# --- Вид под текущую игру ------------------------------------------------------------------

func _accent() -> Color:
	var game := str(Net.party_game)
	if game != "" and Net.in_session():
		var entry: Dictionary = HubGames.by_id(game)
		if entry.get("color") is Color:
			return entry["color"]
	return HubStyle.VIOLET


func _top_bar() -> Node:
	return get_tree().get_first_node_in_group("top_bar") if is_inside_tree() else null


func _in_hub() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == "res://hub/hub.tscn"


## Свёрнутая кнопка — такая же, как кнопки верхней полосы текущей игры (в меню — как кнопки меню).
func _make_mini() -> Button:
	var made: Button = null
	var bar := _top_bar()
	if bar != null and bar.get("_make_button") is Callable and (bar.get("_make_button") as Callable).is_valid():
		var from_bar: Variant = (bar.get("_make_button") as Callable).call(title, 14)
		if from_bar is Button:
			made = from_bar
	if made == null and _in_hub():
		made = HubStyle.button(title, 15)
		made.theme = HubStyle.theme()
	var look := _scene_theme()
	if made == null and look != null and look.has_stylebox("normal", "Button"):
		# лобби: верхней полосы ещё нет, но тема игры уже стоит — обычная кнопка в ней выглядит как кнопки полосы
		made = Button.new()
		made.text = title
		made.add_theme_font_size_override("font_size", 14)
	if made != null and made.theme == null and look != null:
		made.theme = look  # окно живёт в своём слое и тему игры само не наследует
	return made


## Тема текущей игры: у верхней полосы, у сцены или у корня окна (игры ставят свою тему туда).
func _scene_theme() -> Theme:
	var node: Node = _top_bar()
	if node == null:
		node = get_tree().current_scene
	while node != null:
		if node is Control and (node as Control).theme != null:
			return (node as Control).theme
		if node is Window and (node as Window).theme != null:
			return (node as Window).theme
		node = node.get_parent()
	return null


## На экране есть кнопка, которой окно можно открыть снова; иначе крестик только сворачивает.
func _closing_mode() -> int:
	return Mode.CLOSED if _top_bar() != null or _in_hub() else Mode.MINI


## Цвета окна — от кнопки «Общение» верхней полосы: её заливка становится полосой вкладок, а фон ниже —
## тот же цвет, затемнённый и слегка прозрачный. Нет такой кнопки — от цвета игры.
func _repaint() -> void:
	rebuild_mini()
	var game := str(Net.party_game) if Net.in_session() else ""
	if _in_hub():
		game = "hub"
	var fill := _button_fill()
	var text := Color(0, 0, 0, 0)
	var edge := [Color(0, 0, 0, 0), 0, -1]  # обводка кнопки: цвет, ширина, скругление
	if fill.a > 0.0:
		text = _mini_button.get_theme_color("font_color")
		var box := _mini_button.get_theme_stylebox("normal")
		if box is StyleBoxFlat:
			var flat_box := box as StyleBoxFlat
			var width := maxi(maxi(flat_box.border_width_left, flat_box.border_width_top), maxi(flat_box.border_width_right, flat_box.border_width_bottom))
			if width > 0 and flat_box.border_color.a > 0.2:
				edge = [flat_box.border_color, mini(width, 5), clampi(flat_box.corner_radius_top_left, 0, 18)]
			else:
				edge = [Color(0, 0, 0, 0), 0, clampi(flat_box.corner_radius_top_left, 0, 18)]
		_remember_look(game, fill, text, edge)
	elif _looks.has(game):
		# кнопки сейчас не видно (лобби игры, чьи кнопки рисуются не темой) — берём цвет, увиденный раньше
		fill = _looks[game][0]
		text = _looks[game][1]
		if (_looks[game] as Array).size() >= 5:
			edge = [_looks[game][2], int(_looks[game][3]), int(_looks[game][4])]
	# у окна и плавающей кнопки та же обводка, что у кнопки «Общение» верхней полосы
	outline_color = edge[0]
	outline_width = int(edge[1])
	outline_radius = int(edge[2])
	if fill.a <= 0.0:
		set_palette(_accent())
		if _mini_button == null:
			rebuild_mini()
		return
	# Тёмная кнопка полосы → плавающая светлее, светлая → темнее: окно не сливается ни с полосой, ни с панелями игры.
	var tone := fill.lightened(LIFT) if fill.get_luminance() < 0.5 else fill.darkened(SHADE)
	if _mini_button != null:
		_lift_mini(tone, fill.get_luminance() < 0.5)
	set_palette_from_button(tone, text)
	if _mini_button == null:
		rebuild_mini()  # простая плашка красится палитрой окна


## Цвет кнопки «Общение» каждой игры запоминается: в лобби, где полосы ещё нет, окно красится сразу верно.
func _remember_look(game: String, fill: Color, text: Color, edge: Array) -> void:
	var entry := [fill, text, edge[0], edge[1], edge[2]]
	if _looks.has(game) and _looks[game] == entry:
		return
	_looks[game] = entry
	var saved := ConfigFile.new()
	for known: String in _looks:
		saved.set_value("looks", known if known != "" else "_", _looks[known])
	saved.save(LOOKS_PATH)


static func _load_looks() -> void:
	var saved := ConfigFile.new()
	if saved.load(LOOKS_PATH) != OK:
		return
	for known: String in saved.get_section_keys("looks"):
		var pair: Variant = saved.get_value("looks", known)
		if pair is Array and (pair as Array).size() >= 2 and pair[0] is Color and pair[1] is Color:
			_looks["" if known == "_" else known] = pair


## Перекрасить свёрнутую кнопку в тон: плоскому стилю — новая заливка, кнопке-картинке — подсветка целиком.
func _lift_mini(tone: Color, lighter: bool) -> void:
	var box := _mini_button.get_theme_stylebox("normal")
	if box is StyleBoxFlat:
		for state: String in ["normal", "hover", "pressed"]:
			var own := _mini_button.get_theme_stylebox(state)
			if own is StyleBoxFlat:
				var copy := (own as StyleBoxFlat).duplicate() as StyleBoxFlat
				if state == "normal":
					copy.bg_color = Color(tone.r, tone.g, tone.b, maxf(copy.bg_color.a, 0.92))
				else:
					copy.bg_color = copy.bg_color.lightened(LIFT) if lighter else copy.bg_color.darkened(SHADE)
				_mini_button.add_theme_stylebox_override(state, copy)
	else:
		var factor := 1.0 + LIFT if lighter else 1.0 - SHADE
		_mini_button.self_modulate = Color(factor, factor, factor)


## Заливка свёрнутой кнопки: цвет плоского стиля или средний цвет середины картинки. Прозрачный — не узнать.
func _button_fill() -> Color:
	if _mini_button == null or not is_instance_valid(_mini_button):
		return Color(0, 0, 0, 0)
	var box := _mini_button.get_theme_stylebox("normal")
	var tint := _mini_button.self_modulate
	if box is StyleBoxFlat:
		var flat_color: Color = (box as StyleBoxFlat).bg_color
		return Color(flat_color.r * tint.r, flat_color.g * tint.g, flat_color.b * tint.b, 1.0) if flat_color.a > 0.1 else Color(0, 0, 0, 0)
	if box is StyleBoxTexture and (box as StyleBoxTexture).texture != null:
		var image := (box as StyleBoxTexture).texture.get_image()
		if image == null or image.is_empty():
			return Color(0, 0, 0, 0)
		if image.is_compressed():
			image.decompress()
		var total := Color(0, 0, 0, 0)
		var count := 0
		for sy in 5:
			for sx in 5:
				var pixel := image.get_pixel(int(image.get_width() * (0.3 + sx * 0.1)), int(image.get_height() * (0.3 + sy * 0.1)))
				if pixel.a > 0.5:
					total += pixel
					count += 1
		if count == 0:
			return Color(0, 0, 0, 0)
		var shade: Color = (box as StyleBoxTexture).modulate_color
		return Color(total.r / count * shade.r * tint.r, total.g / count * shade.g * tint.g, total.b / count * shade.b * tint.b, 1.0)
	return Color(0, 0, 0, 0)


func _watch_context(delta: float) -> void:
	_context_clock += delta
	if _context_clock < 0.4:
		return
	_context_clock = 0.0
	var bar := _top_bar()
	var scene := get_tree().current_scene
	var look := _scene_theme()
	var now := "%s|%s|%s|%s|%s" % [Net.in_game, Net.party_game if Net.in_session() else "", bar.get_instance_id() if bar != null else 0,
		scene.get_instance_id() if scene != null else 0, look.get_instance_id() if look != null else 0]
	if now != _context_key:
		_context_key = now
		_repaint()
		_sync()
	var party: bool = Net.is_party()
	if party and not _was_party and mode == Mode.CLOSED:
		set_mode(Mode.MINI)  # вошли в пати — показать, что чат есть
	_was_party = party


# --- Что открыть ---------------------------------------------------------------------------

## «Кровь на часовой башне»: во время партии в «Общении» только мини-игры (у игры свой разговор с рассказчиком).
func _games_only() -> bool:
	return Net.in_session() and bool(Net.in_game) and str(Net.party_game) == "blood_on_the_clocktower"


func open_chat(focus: bool = false) -> void:
	if _games_only():
		open_games()
		return
	view = "chat"
	set_mode(Mode.OPEN)
	_sync()
	if focus and is_instance_valid(_input) and _input.editable:
		_input.grab_focus()


func toggle_chat() -> void:
	if _games_only():
		toggle_games()
		return
	if mode == Mode.OPEN and view == "chat":
		set_mode(Mode.MINI)
	else:
		open_chat()


func open_games() -> void:
	view = "mg"
	set_mode(Mode.OPEN)
	_sync()


## Кнопка «Общение» верхней полосы и главного меню: раскрыть окно на последней вкладке или свернуть.
func toggle() -> void:
	if mode == Mode.OPEN:
		set_mode(Mode.MINI)
	else:
		set_mode(Mode.OPEN)
		_sync()


func toggle_games() -> void:
	if mode == Mode.OPEN and view == "mg":
		set_mode(Mode.MINI)
	else:
		open_games()


## Что-то случилось (ход соперника, приглашение): закрытое окно показывается свёрнутой кнопкой с точкой.
func attention() -> void:
	if mode == Mode.CLOSED:
		set_mode(Mode.MINI)
	_sync()


func watching(id: String) -> bool:
	return mode == Mode.OPEN and view == "mg" and str(_mg.current) == id


func chat_focused() -> bool:
	return mode == Mode.OPEN and view == "chat" and is_instance_valid(_input) and _input.has_focus()


func chat_open() -> bool:
	return mode == Mode.OPEN and view == "chat"


func input_edit() -> LineEdit:
	return _input


func unread() -> int:
	return int(_chat.unread_total())


# --- Постройка -----------------------------------------------------------------------------

func _fill_header() -> void:
	var add := small_button("+", "Написать лично или команде")
	_add_button = add
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(_toggle_menu)
	header_extra.add_child(add)


func _build_body() -> void:
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	_rows.clear()
	_hover_row = null
	_board = null
	_game_shown = "?"
	_chat_box = Control.new()
	_chat_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(_chat_box)
	_game_box = Control.new()
	_game_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(_game_box)
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", px(12))
	_notice.add_theme_color_override("font_color", Color("ffd479"))
	_notice.add_theme_stylebox_override("normal", flat(Color(0.04, 0.04, 0.07, 0.94), px(6), px(6)))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	_notice.z_index = 2
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_notice)
	_build_chat()


func _build_chat() -> void:
	var pad := px(6)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = pad
	col.offset_right = -pad
	col.offset_top = px(5)
	col.offset_bottom = -pad
	col.add_theme_constant_override("separation", px(4))
	_chat_box.add_child(col)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", px(4))
	_scroll.add_child(_list)
	_reply_bar = HBoxContainer.new()
	_reply_bar.visible = false
	_reply_label = _label("", 12, c_muted)
	_reply_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reply_label.clip_text = true
	_reply_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_reply_bar.add_child(_reply_label)
	var reply_x := small_button("×", "Не отвечать")
	reply_x.pressed.connect(_set_reply.bind({}))
	_reply_bar.add_child(reply_x)
	col.add_child(_reply_bar)
	_attach_bar = HBoxContainer.new()
	_attach_bar.visible = false
	_attach_label = _label("", 12, c_muted)
	_attach_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attach_bar.add_child(_attach_label)
	var attach_x := small_button("×", "Убрать картинку")
	attach_x.pressed.connect(_set_pending.bind(PackedByteArray()))
	_attach_bar.add_child(attach_x)
	col.add_child(_attach_bar)
	_quick = HFlowContainer.new()
	_quick.add_theme_constant_override("h_separation", px(4))
	_quick.add_theme_constant_override("v_separation", px(4))
	_quick.visible = quick_open
	for index in REACTIONS.size():
		var phrase: String = REACTIONS[index]
		var b := small_button("%d. %s" % [index + 1, phrase], "Клавиша %d" % (index + 1))
		b.add_theme_stylebox_override("normal", flat(c_soft, px(8), px(4)))
		b.add_theme_color_override("font_color", c_ink)
		b.pressed.connect(func():
			_chat.send(_quick_conv(), phrase, "emote")
			quick_open = false
			_sync_quick())
		_quick.add_child(b)
	col.add_child(_quick)
	var in_row := HBoxContainer.new()
	in_row.add_theme_constant_override("separation", px(4))
	col.add_child(in_row)
	var clip := small_button("📎", "Картинка или GIF до 2 МБ (ещё: Ctrl+V и перетаскивание файла в окно)")
	clip.pressed.connect(_pick_file)
	in_row.add_child(clip)
	_input = LineEdit.new()
	_input.keep_editing_on_text_submit = true
	_input.max_length = 200
	_input.text = _draft
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", px(13))
	_input.add_theme_color_override("font_color", c_ink)
	_input.add_theme_color_override("font_placeholder_color", Color(c_muted, 0.75))
	var field := Color(c_bg.darkened(0.35), 1.0)
	_input.add_theme_stylebox_override("normal", flat(field, px(9), px(7), c_line))
	_input.add_theme_stylebox_override("focus", flat(field, px(9), px(7), c_accent))
	_input.add_theme_stylebox_override("read_only", flat(field, px(9), px(7), c_line))
	_input.caret_blink = true
	_input.caret_blink_interval = 0.375
	_input.add_theme_constant_override("caret_width", 2)
	_input.text_submitted.connect(_on_submit)
	_input.text_changed.connect(func(text: String):
		_draft = text
		_sync_caret())
	_input.gui_input.connect(_on_input_key)
	in_row.add_child(_input)
	_sync_caret()
	_quick_btn = small_button("Фразы", "Быстрые реплики одним нажатием (клавиши 1–8)")
	_quick_btn.pressed.connect(func():
		quick_open = not quick_open
		_sync_quick())
	in_row.add_child(_quick_btn)
	# панель действий над сообщением под курсором
	if is_instance_valid(_hover_bar):
		_hover_bar.queue_free()
	_hover_bar = PanelContainer.new()
	_hover_bar.add_theme_stylebox_override("panel", flat(c_head, px(9), px(2), c_line))
	_hover_bar.visible = false
	_hover_bar.z_index = 2
	add_child(_hover_bar)
	_sync_quick()
	_sync_bars()


func _rescale_body() -> void:
	if not _built:
		return
	_close_menu()
	_build_body()
	_shown = ""
	_sync()


func _label(text: String, font: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px(font))
	l.add_theme_color_override("font_color", color)
	return l


# --- Вкладки -------------------------------------------------------------------------------

func _on_tab(id: String) -> void:
	if id.begins_with("c:"):
		view = "chat"
		_chat.select(id.substr(2))
	else:
		view = "mg"
		_mg.select(id.substr(2))
	_sync()


func _on_tab_closed(id: String) -> void:
	if id.begins_with("c:"):
		_chat.close_conv(id.substr(2))
	else:
		_mg.close(id.substr(2))


func _sync() -> void:
	if not _built:
		return
	var games_only := _games_only()
	if games_only:
		view = "mg"
	if is_instance_valid(_add_button):
		_add_button.visible = not games_only
	var list := []
	for conv_key: String in ([] if games_only else _chat.tabs()):
		var conv: Dictionary = _chat.convs[conv_key]
		list.append({
			"id": "c:" + conv_key,
			"text": _chat.title_of(conv_key),
			"closable": conv_key != "all",
			"dot": int(conv.unread) > 0,
			"tip": "Личные сообщения" if conv_key.begins_with("pm:") else ("Видит только ваша команда" if conv_key == "team" else "Общий чат пати"),
		})
	var game_current := str(_mg.current)
	for id: String in _mg.order:
		var session: Dictionary = _mg.sessions[id]
		if mode == Mode.OPEN and view == "mg" and id == game_current:
			session.dot = false
		var rival := "за обоих" if bool(session.local) else str((session.names as Array)[1 - int(session.seat)])
		list.append({"id": "g:" + id, "text": "%s %s" % [ICONS.get(session.game, ""), rival], "closable": true, "dot": bool(session.dot),
			"tip": "%s · %s" % [_mg.title(str(session.game)), rival]})
	list.append({"id": GAMES_TAB, "text": "♙ Игры", "closable": false, "dot": not (_mg.invites_in as Array).is_empty(),
		"tip": "Мини-игры: новая партия и приглашения (клавиша X)"})
	var in_game_view := view == "mg"
	if in_game_view and not _mg.sessions.has(game_current):
		game_current = ""
	set_tabs(list, ("g:" + game_current) if in_game_view else ("c:" + str(_chat.current)))
	mini_dot = (unread() > 0 and not games_only) or int(_mg.dots()) > 0
	hover_zoom = base_size if in_game_view and game_current != "" else Vector2.ZERO
	_chat_box.visible = not in_game_view
	_game_box.visible = in_game_view
	if mode != Mode.OPEN:
		_apply()
		return
	if in_game_view:
		_hover_bar.visible = false
		if game_current == "":
			_show_lobby()
		else:
			_show_session(game_current)
	else:
		if _shown != str(_chat.current):
			_show_conv()
		_input.editable = _chat.can_send(str(_chat.current))
		_input.placeholder_text = "Сообщение…" if _input.editable else ("Вы не в пати" if not Net.in_session() else "Сюда сейчас написать нельзя")


func _show_conv() -> void:
	_shown = str(_chat.current)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_hover_row = null
	_set_reply({})
	var conv: Dictionary = _chat.convs.get(_shown, {})
	for entry: Dictionary in conv.get("entries", []):
		_append(entry)
	_stick = 4


func _toggle_menu() -> void:
	if is_instance_valid(_menu):
		_close_menu()
		return
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", flat(c_head, px(9), px(6), c_line))
	_menu.z_index = 3
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", px(2))
	_menu.add_child(col)
	var any := false
	if int(Net.chat_team()) >= 0:
		any = true
		var team := _menu_item("Команда", c_accent)
		team.pressed.connect(func():
			view = "chat"
			_chat.open_conv("team")
			_close_menu())
		col.add_child(team)
	if _chat.pm_allowed():
		for target: Dictionary in _chat.pm_targets():
			any = true
			var peer := int(target.peer)
			var item := _menu_item(str(target.name), Net.color_of(int(target.color)))
			item.pressed.connect(func():
				view = "chat"
				_chat.open_pm(peer)
				_close_menu()
				_input.grab_focus())
			col.add_child(item)
	if not any:
		var why := "В этой партии личные сообщения выключены" if not _chat.pm_allowed() else "В пати пока никого, кроме вас"
		col.add_child(_label(why, 12, c_muted))
	add_child(_menu)
	_menu.reset_size()
	_menu.position = Vector2(maxf(0.0, size.x - _menu.size.x - px(6)), head_height() + 2)


func _menu_item(text: String, color: Color) -> Button:
	var b := small_button(text, "")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", color.lightened(0.3))
	b.add_theme_color_override("font_hover_color", color.lightened(0.55))
	return b


func _close_menu() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


# --- Сообщения -----------------------------------------------------------------------------

func _on_entry(conv: String, entry: Dictionary) -> void:
	if conv == _shown and is_instance_valid(_list):
		var at_bottom := _scroll.scroll_vertical >= int(_scroll.get_v_scroll_bar().max_value - _scroll.size.y) - px(30)
		_append(entry)
		if at_bottom or int(entry.get("peer", 0)) == int(_chat.my_peer()):
			_stick = 4
	var kind := str(entry.get("kind", ""))
	if kind == "emote":
		Sfx.babble(str(entry["text"]), str(entry.get("voice", entry.get("name", ""))))  # реплика — голосом персонажа игрока
	elif kind != "system":
		Sfx.chat_voice(str(entry["text"]), str(entry.get("voice", entry.get("name", ""))))  # сообщение — голосом автора


func _member_colors_key() -> String:
	var parts := []
	for m: Dictionary in Net.lobby_view.get("members", []):
		parts.append("%s:%s" % [m.get("peer", 0), m.get("color", 0)])
	return ",".join(parts)


## Кто-то сменил цвет — перерисовываем журнал, чтобы и старые сообщения были нового цвета.
func _on_lobby() -> void:
	var colors := _member_colors_key()
	if colors != _colors_key:
		_colors_key = colors
		_shown = ""
	_sync()


## Текущий цвет автора: по peer из списка участников; если его там нет — цвет на момент отправки.
func _color_of(entry: Dictionary) -> String:
	var peer := int(entry.get("peer", 0))
	if peer != 0:
		for m: Dictionary in Net.lobby_view.get("members", []):
			if int(m.get("peer", -1)) == peer and m.get("kind", "") != "local" and m.get("kind", "") != "bot":
				return Net.color_of(int(m.get("color", 0))).lightened(0.3).to_html(false)
	var sent := str(entry.get("color", ""))
	return Color(sent).lightened(0.3).to_html(false) if sent != "" else c_ink.to_html(false)


static func _safe(text: String) -> String:
	return text.replace("[", "[lb]")


func _append(entry: Dictionary) -> void:
	var kind := str(entry.get("kind", "chat"))
	var id := int(entry.get("id", 0))
	var mine := int(entry.get("peer", 0)) == int(_chat.my_peer())
	var bubble := PanelContainer.new()
	bubble.set_meta("entry", entry)
	if kind == "system":
		bubble.add_theme_stylebox_override("panel", flat(Color(0, 0, 0, 0), 0, px(2)))
	else:
		# свои сообщения — в цвет акцента, чужие — на спокойной плашке
		bubble.add_theme_stylebox_override("panel", flat(Color(c_accent, 0.2) if mine else Color(c_soft, 0.75), px(9), px(6)))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", px(3))
	bubble.add_child(row)
	var reply: Dictionary = entry.get("reply", {})
	if not reply.is_empty():
		var quote := Button.new()
		quote.text = "↪ %s: %s" % [str(reply.get("name", "")), str(reply.get("text", ""))]
		quote.tooltip_text = "Перейти к сообщению"
		quote.alignment = HORIZONTAL_ALIGNMENT_LEFT
		quote.clip_text = true
		quote.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		quote.focus_mode = Control.FOCUS_NONE
		quote.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		quote.add_theme_font_size_override("font_size", px(11))
		quote.add_theme_color_override("font_color", c_muted)
		quote.add_theme_color_override("font_hover_color", c_ink)
		var quote_box := flat(Color(0, 0, 0, 0.22), px(5), px(4))
		quote_box.border_color = c_accent
		quote_box.border_width_left = 2
		for state: String in ["normal", "hover", "pressed"]:
			quote.add_theme_stylebox_override(state, quote_box)
		quote.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		quote.pressed.connect(_jump_to.bind(int(reply.get("id", 0))))
		row.add_child(quote)
	var text := _safe(str(entry.get("text", "")))
	var has_image := entry.has("image")
	if has_image and str(entry.get("text", "")) == str(_chat.IMAGE_ONLY):
		text = ""
	var who := "[color=#%s]%s[/color]" % [_color_of(entry), _safe(str(entry.get("name", "")))]
	var peer := int(entry.get("peer", 0))
	if peer > 0 and not mine and str(entry.get("scope", "all")) != "pm":
		who = "[url=pm:%d]%s[/url]" % [peer, who]  # щелчок по нику — личная вкладка
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.meta_underlined = false
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_theme_font_override("bold_font", HubStyle.font("bold"))
	for size_name: String in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		line.add_theme_font_size_override(size_name, px(13))
	match kind:
		"system":
			line.text = "[center][color=#%s][font_size=%d]%s[/font_size][/color][/center]" % [SYSTEM.to_html(false), px(12), text]
		"emote":
			line.text = "[b]%s[/b]  [color=#%s]%s[/color]" % [who, EMOTE.to_html(false), text]
		_:
			line.text = "[b]%s[/b]  [color=#%s]%s[/color]" % [who, c_ink.to_html(false), text]
	line.meta_clicked.connect(_on_meta)
	row.add_child(line)
	if has_image:
		var picture := ChatImage.new()
		picture.hash = str(entry["image"])
		picture.limit = Vector2(base_size.x * k - px(46), px(170))
		picture.clicked.connect(_open_viewer)
		row.add_child(picture)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", px(3))
	chips.add_theme_constant_override("v_separation", px(3))
	chips.visible = false
	row.add_child(chips)
	bubble.set_meta("chips", chips)
	_list.add_child(bubble)
	if id > 0:
		_rows[id] = bubble
		_fill_chips(id)
	if _list.get_child_count() > int(_chat.KEEP):
		var old := _list.get_child(0)
		_rows.erase(int((old.get_meta("entry") as Dictionary).get("id", 0)))
		_list.remove_child(old)
		old.queue_free()


func _on_meta(meta: Variant) -> void:
	var link := str(meta)
	if link.begins_with("pm:"):
		if _chat.pm_allowed():
			_chat.open_pm(int(link.trim_prefix("pm:")))
			_input.grab_focus()
		else:
			_say("В этой партии личные сообщения выключены")


func _fill_chips(id: int) -> void:
	var bubble: Control = _rows.get(id)
	if bubble == null or not is_instance_valid(bubble):
		return
	var chips: HFlowContainer = bubble.get_meta("chips")
	for child: Node in chips.get_children():
		chips.remove_child(child)
		child.queue_free()
	var map: Dictionary = _chat.reactions.get(id, {})
	chips.visible = not map.is_empty()
	var me := int(_chat.my_peer())
	var keys := map.keys()
	keys.sort()
	for emoji: Variant in keys:
		var who: Array = map[emoji]
		var mine := who.has(me)
		var chip := small_button("%s %d" % [_chat.EMOJI[int(emoji)], who.size()], _names(who))
		chip.add_theme_font_size_override("font_size", px(12))
		chip.add_theme_color_override("font_color", c_ink)
		chip.add_theme_stylebox_override("normal", flat(Color(c_accent, 0.35) if mine else Color(0, 0, 0, 0.25), px(9), px(3), c_accent if mine else Color(0, 0, 0, 0)))
		chip.pressed.connect(func(): _chat.react(id, int(emoji)))
		chips.add_child(chip)


func _names(peers: Array) -> String:
	var names := PackedStringArray()
	for peer: Variant in peers:
		for m: Dictionary in Net.lobby_view.get("members", []):
			if int(m.get("peer", 0)) == int(peer):
				names.append(str(m.get("name", "")))
	return ", ".join(names)


func _jump_to(id: int) -> void:
	var bubble: Control = _rows.get(id)
	if bubble == null or not is_instance_valid(bubble):
		_say("Это сообщение уже ушло из журнала")
		return
	_stick = 0
	_scroll.ensure_control_visible(bubble)
	bubble.modulate = Color(1.7, 1.7, 1.1)
	create_tween().tween_property(bubble, "modulate", Color.WHITE, 1.2)


func _set_reply(entry: Dictionary) -> void:
	_reply = entry
	_sync_bars()
	if not entry.is_empty() and is_instance_valid(_input):
		_input.grab_focus()


func _set_pending(bytes: PackedByteArray) -> void:
	_pending_image = bytes
	_sync_bars()


func _sync_bars() -> void:
	if _reply_bar == null:
		return
	_reply_bar.visible = not _reply.is_empty()
	if not _reply.is_empty():
		_reply_label.text = "↪ %s: %s" % [str(_reply.get("name", "")), str(_reply.get("text", ""))]
	_attach_bar.visible = not _pending_image.is_empty()
	if not _pending_image.is_empty():
		var gif: bool = _chat.is_gif(_pending_image)
		_attach_label.text = "📎 %s, %d КБ — Enter, чтобы отправить" % ["GIF" if gif else "Картинка", ceili(_pending_image.size() / 1024.0)]


func _say(text: String) -> void:
	if not is_instance_valid(_notice) or mode != Mode.OPEN:
		return
	_notice.text = text
	_notice.visible = true
	_notice.size = Vector2(body.size.x - px(16), 0)
	var stamp := Time.get_ticks_msec()
	_notice.set_meta("stamp", stamp)
	get_tree().create_timer(3.5).timeout.connect(func():
		if is_instance_valid(_notice) and int(_notice.get_meta("stamp", 0)) == stamp:
			_notice.visible = false)


# --- Ввод ----------------------------------------------------------------------------------

func _quick_conv() -> String:
	var now := str(_chat.current)
	return now if _chat.can_send(now) else "all"


func _on_submit(text: String) -> void:
	# Поглощаем Enter до синхронного Net: экран может пересоздаться.
	get_viewport().set_input_as_handled()
	var extra := {}
	if not _reply.is_empty():
		extra["reply"] = {"id": int(_reply.get("id", 0)), "name": str(_reply.get("name", "")), "text": _snippet(_reply)}
	if not _pending_image.is_empty():
		var hash: String = _chat.attach(_pending_image)
		if hash != "":
			extra["image"] = hash
	if text.strip_edges().is_empty() and not extra.has("image"):
		return
	_input.clear()
	_draft = ""
	_sync_caret()  # отправили — курсор пропадает до первого нового символа
	_input.grab_focus()
	_reply = {}
	_pending_image = PackedByteArray()
	_sync_bars()
	_chat.send(str(_chat.current), text, "chat", extra)


static func _snippet(entry: Dictionary) -> String:
	var text := str(entry.get("text", ""))
	if entry.has("image") and text == "🖼":
		text = "картинка"
	return text if text.length() <= 80 else text.left(77) + "…"


## Пустое поле — курсора нет (прозрачный); есть хоть один символ — курсор цвета акцента.
func _sync_caret() -> void:
	if _input.text.is_empty():
		_input.add_theme_color_override("caret_color", Color(0, 0, 0, 0))
	else:
		_input.add_theme_color_override("caret_color", c_accent)
		_input.caret_blink = true  # перезапуск мигания: после ввода курсор сразу виден


func _sync_quick() -> void:
	if _quick == null:
		return
	_quick.visible = quick_open
	_quick_btn.text = "Скрыть" if quick_open else "Фразы"


func _on_input_key(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and key_event.keycode == KEY_V and key_event.is_command_or_control_pressed():
		if DisplayServer.clipboard_has_image():
			var bytes: PackedByteArray = _chat.prepare_image(DisplayServer.clipboard_get_image())
			if not bytes.is_empty():
				_set_pending(bytes)
				_input.accept_event()


func _pick_file() -> void:
	var filters := PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.gif ; Картинки и GIF"])
	DisplayServer.file_dialog_show("Картинка для чата", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_file_picked)


func _on_file_picked(status: bool, paths: PackedStringArray, _filter: int) -> void:
	if status and not paths.is_empty():
		_take_file(paths[0])


func _on_files_dropped(files: PackedStringArray) -> void:
	if chat_open() and not files.is_empty() and Net.in_session():
		_take_file(files[0])


func _take_file(path: String) -> void:
	var bytes: PackedByteArray = _chat.prepare_file(path)
	if not bytes.is_empty():
		_set_pending(bytes)
		_input.grab_focus()


func _open_viewer(hash: String) -> void:
	if is_instance_valid(_viewer):
		_viewer.queue_free()
	var parent := get_parent() as Control
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			dim.queue_free())
	var picture := ChatImage.new()
	picture.hash = hash
	picture.limit = parent.size * 0.86
	picture.grow = true
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.centered_in = parent.size
	dim.add_child(picture)
	parent.add_child(dim)
	_viewer = dim


# --- Состояние окна и клавиши --------------------------------------------------------------

func _on_mode() -> void:
	_close_menu()
	if mode != Mode.OPEN:
		quick_open = false
		_sync_quick()
		if is_instance_valid(_input):
			_input.release_focus()
		_hover_bar.visible = false
	else:
		_stick = 4
	_sync()


func _process(delta: float) -> void:
	hover_zoom_on = bool(Prefs.minigame_zoom)
	super._process(delta)
	if not _built:
		return
	_watch_context(delta)
	if mode != Mode.OPEN:
		return
	if _notice.visible:
		_notice.position = Vector2(px(8), body.size.y - _notice.size.y - px(8))
	if view != "chat":
		return
	_chat.touch_view()
	# щелчок мимо меню «+» закрывает его
	if is_instance_valid(_menu) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse := get_global_mouse_position()
		if not _menu.get_global_rect().has_point(mouse) and not _head.get_global_rect().has_point(mouse):
			_close_menu()
	if _stick > 0:
		_stick -= 1
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	_track_hover()


## Сообщение под курсором получает кнопки «ответить» и «реакция».
func _track_hover() -> void:
	var mouse := get_global_mouse_position()
	var over_bar := _hover_bar.visible and _hover_bar.get_global_rect().grow(4).has_point(mouse)
	var row: Control = _hover_row if over_bar else null
	if row == null and _scroll.get_global_rect().has_point(mouse) and _hover_is_ours():
		for child: Node in _list.get_children():
			var candidate := child as Control
			if candidate.get_global_rect().has_point(mouse):
				var entry: Dictionary = candidate.get_meta("entry")
				if str(entry.get("kind", "")) != "system" and int(entry.get("id", 0)) > 0:
					row = candidate
				break
	if row != _hover_row:
		_hover_row = row
		_emoji_open = false
		_fill_hover_bar()
	_hover_bar.visible = row != null and is_instance_valid(row)
	if _hover_bar.visible:
		_hover_bar.reset_size()
		var rect := row.get_global_rect()
		var scroll_rect := _scroll.get_global_rect()
		var at := Vector2(rect.end.x - _hover_bar.size.x - px(4), rect.position.y - px(8))
		at.y = clampf(at.y, scroll_rect.position.y, scroll_rect.end.y - _hover_bar.size.y)
		at.x = maxf(at.x, scroll_rect.position.x)
		_hover_bar.global_position = at


func _fill_hover_bar() -> void:
	for child: Node in _hover_bar.get_children():
		_hover_bar.remove_child(child)
		child.queue_free()
	if _hover_row == null:
		return
	var entry: Dictionary = _hover_row.get_meta("entry")
	var id := int(entry.get("id", 0))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	_hover_bar.add_child(line)
	if _emoji_open:
		for index in (_chat.EMOJI as Array).size():
			var emoji := small_button(str(_chat.EMOJI[index]), str(_chat.EMOJI_TIPS[index]))
			emoji.add_theme_font_size_override("font_size", px(15))
			emoji.pressed.connect(func():
				_chat.react(id, index)
				_emoji_open = false
				_fill_hover_bar())
			line.add_child(emoji)
		return
	var answer := small_button("↩", "Ответить")
	answer.pressed.connect(_set_reply.bind(entry))
	line.add_child(answer)
	var smile := small_button("☺", "Реакция")
	smile.pressed.connect(func():
		_emoji_open = true
		_fill_hover_bar())
	line.add_child(smile)


func _unhandled_key_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null or not _built or not ke.pressed or ke.echo:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if ke.ctrl_pressed or ke.alt_pressed or ke.meta_pressed:
		return
	# Z — чат, X — мини-игры: по месту клавиши, раскладка не важна
	if ke.physical_keycode == KEY_Z and Net.in_session():
		toggle_chat()
		get_viewport().set_input_as_handled()
		return
	if ke.physical_keycode == KEY_X:
		toggle_games()
		get_viewport().set_input_as_handled()
		return
	if proxies <= 0 or not Net.in_session():
		return
	# 1–8 (и на цифровой панели) — быстрая реплика без открытия чата
	var n := -1
	if ke.keycode >= KEY_1 and ke.keycode <= KEY_9:
		n = ke.keycode - KEY_1
	elif ke.keycode >= KEY_KP_1 and ke.keycode <= KEY_KP_9:
		n = ke.keycode - KEY_KP_1
	if n >= 0 and n < REACTIONS.size():
		_chat.send(_quick_conv(), REACTIONS[n], "emote")
		get_viewport().set_input_as_handled()
		return
	if ke.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if chat_open():
			set_mode(Mode.MINI)
		else:
			open_chat(true)


# --- Мини-игры -----------------------------------------------------------------------------

func _clear_game() -> void:
	for child: Node in _game_box.get_children():
		_game_box.remove_child(child)
		child.queue_free()
	_board = null
	_status = null


func _text(text: String, font: int = 13, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := _label(text, font, c_ink if color.a == 0.0 else color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _action(text: String, tip: String, primary: bool = false) -> Button:
	var b := small_button(text, tip)
	var dark := Color(0.07, 0.06, 0.1)
	b.add_theme_color_override("font_color", dark if primary else c_ink)
	b.add_theme_color_override("font_hover_color", dark if primary else Color.WHITE)
	b.add_theme_stylebox_override("normal", flat(c_accent if primary else c_soft, px(8), px(6)))
	b.add_theme_stylebox_override("hover", flat(c_accent.lightened(0.15) if primary else c_soft.lightened(0.12), px(8), px(6)))
	b.add_theme_stylebox_override("pressed", flat(c_accent.darkened(0.15) if primary else c_soft.darkened(0.15), px(8), px(6)))
	return b


func _toggle_button(text: String, on: bool) -> Button:
	var b := _action(text, "")
	if on:
		b.add_theme_stylebox_override("normal", flat(Color(c_accent, 0.32), px(8), px(6), c_accent))
	return b


func _show_lobby() -> void:
	_game_shown = ""
	_clear_game()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = px(10)
	scroll.offset_top = px(8)
	scroll.offset_right = -px(6)
	scroll.offset_bottom = -px(8)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_game_box.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", px(8))
	scroll.add_child(col)
	for invite: Dictionary in _mg.invites_in:
		var row := HBoxContainer.new()
		var id := str(invite.id)
		var line := _text("%s зовёт: %s" % [str(invite.name), _mg._game_line(str(invite.game), invite.opts)])
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var yes := _action("Играть", "", true)
		yes.pressed.connect(func(): _mg.answer(id, true))
		row.add_child(yes)
		var no := _action("Нет", "Отказаться")
		no.pressed.connect(func(): _mg.answer(id, false))
		row.add_child(no)
		col.add_child(row)
	for invite: Dictionary in _mg.invites_out:
		var row := HBoxContainer.new()
		var id := str(invite.id)
		var line := _text("Ждём ответа: %s · %s" % [str(invite.name), _mg.title(str(invite.game))], 12, c_muted)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var cancel := _action("Отозвать", "")
		cancel.pressed.connect(func(): _mg.cancel_invite(id))
		row.add_child(cancel)
		col.add_child(row)
	col.add_child(_text("НОВАЯ ПАРТИЯ", 11, c_muted))
	var games := HFlowContainer.new()
	games.add_theme_constant_override("h_separation", px(6))
	games.add_theme_constant_override("v_separation", px(6))
	for game: String in _mg.GAMES:
		var b := _toggle_button("%s %s" % [ICONS[game], _mg.title(game)], game == _pick_game)
		b.pressed.connect(func():
			_pick_game = game
			_show_lobby())
		games.add_child(b)
	col.add_child(games)
	if _pick_game == "go":
		var sizes := HBoxContainer.new()
		sizes.add_theme_constant_override("separation", px(6))
		sizes.add_child(_text("Доска:", 12, c_muted))
		for board_size: int in [9, 13, 19]:
			var b := _toggle_button("%d×%d" % [board_size, board_size], board_size == _pick_size)
			b.pressed.connect(func():
				_pick_size = board_size
				_show_lobby())
			sizes.add_child(b)
		col.add_child(sizes)
	var opts := {"size": _pick_size} if _pick_game == "go" else {}
	var targets: Array = _mg.targets()
	if targets.is_empty():
		col.add_child(_text("Позвать некого: в пати пока только вы. Партии — один на один, времени на ход нет.", 12, c_muted))
	else:
		col.add_child(_text("Кого позвать (один на один, без времени на ход, сторона — по жребию):", 12, c_muted))
		var people := HFlowContainer.new()
		people.add_theme_constant_override("h_separation", px(6))
		people.add_theme_constant_override("v_separation", px(6))
		for target: Dictionary in targets:
			var peer := int(target.peer)
			var b := _action(str(target.name), "Пригласить")
			b.add_theme_color_override("font_color", Net.color_of(int(target.color)).lightened(0.4))
			b.pressed.connect(func(): _mg.invite(peer, _pick_game, opts))
			people.add_child(b)
		col.add_child(people)
	var solo := _action("Играть за обоих на этом компьютере", "Партия без сети: ходите за обе стороны по очереди")
	solo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	solo.pressed.connect(func(): _mg.start_local(_pick_game, opts))
	col.add_child(solo)


func _show_session(id: String) -> void:
	var session: Dictionary = _mg.sessions[id]
	if _game_shown != id or _board == null or not is_instance_valid(_board):
		_game_shown = id
		_resign_armed = false
		_clear_game()
		var col := VBoxContainer.new()
		col.name = "Col"
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = px(8)
		col.offset_right = -px(8)
		col.offset_top = px(4)
		col.offset_bottom = -px(8)
		col.add_theme_constant_override("separation", px(4))
		_game_box.add_child(col)
		var bar := HBoxContainer.new()
		bar.name = "Bar"
		bar.add_theme_constant_override("separation", px(4))
		col.add_child(bar)
		_status = Label.new()
		_status.add_theme_font_size_override("font_size", px(12))
		_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_status.clip_text = true
		_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bar.add_child(_status)
		_board = Board.new()
		_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_board.moved.connect(func(action: Dictionary): _mg.move(id, action))
		col.add_child(_board)
	_board.set_session(session)
	var state: Dictionary = session.state
	var seat := int(session.seat)
	var sides: Array = SIDE_NAMES[session.game]
	var over := bool(state.over)
	var my_turn := bool(session.local) or int(state.turn) == seat
	var text := ""
	var color := c_ink
	if over:
		var winner := int(state.winner)
		if winner == 2:
			text = str(state.reason)
		elif bool(session.local):
			text = "Победили %s. %s" % [sides[winner], str(state.reason)]
		else:
			text = ("Вы победили! " if winner == seat else "Вы проиграли. ") + str(state.reason)
			color = Color("9be3a0") if winner == seat else Color("f0a3a3")
	elif bool(session.gone):
		text = "Соперник закрыл партию"
		color = c_muted
	elif bool(session.local):
		text = "Ход: %s" % sides[int(state.turn)]
	else:
		text = ("Ваш ход · вы %s" % sides[seat]) if my_turn else ("Ходит соперник · вы %s" % sides[seat])
		color = c_accent.lightened(0.25) if my_turn else c_muted
	if not over and str(session.game) == "chess" and bool(state.get("check", false)):
		text += " · шах"
	if str(session.game) == "go" and not over:
		text += " · взято %d : %d" % [int(state.caps[0]), int(state.caps[1])]
	_status.text = text
	_status.tooltip_text = text
	_status.add_theme_color_override("font_color", color)
	# кнопки партии пересобираем по состоянию
	var bar := _game_box.get_node("Col/Bar") as HBoxContainer
	for child: Node in bar.get_children():
		if child != _status:
			bar.remove_child(child)
			child.queue_free()
	var playing := not over and not bool(session.gone)
	if playing and str(session.game) == "go":
		var pass_btn := small_button("Пас", "Пропустить ход. Два паса подряд — конец партии и подсчёт")
		pass_btn.disabled = not my_turn
		pass_btn.pressed.connect(func(): _mg.move(id, {"pass": true}))
		bar.add_child(pass_btn)
	if playing and not bool(session.local):
		var resign := small_button("Точно сдаться?" if _resign_armed else "Сдаться", "Признать поражение")
		resign.pressed.connect(func():
			if _resign_armed:
				_mg.move(id, {"resign": true})
			else:
				_resign_armed = true
				_show_session(id))
		bar.add_child(resign)
	if over or bool(session.gone):
		var again := small_button("Ещё раз", "Начать новую партию с тем же соперником")
		again.add_theme_color_override("font_color", c_accent)
		again.pressed.connect(func():
			if bool(session.local):
				_mg.close(id)
				_mg.start_local(str(session.game), session.opts)
			else:
				_mg.invite(int((session.peers as Array)[1 - seat]), str(session.game), session.opts))
		bar.add_child(again)


## Картинка или гифка сообщения: ждёт загрузку, вписывается в отведённое место, гифка играет, пока видна.
class ChatImage:
	extends Control

	signal clicked(hash: String)

	var hash := ""
	var limit := Vector2(300, 170)
	var grow := false  # крупный просмотр: можно растянуть больше исходного размера
	var centered_in := Vector2.ZERO  # крупный просмотр: размер экрана, по центру которого стоять
	var _frames: Array = []
	var _delays: PackedFloat32Array = []
	var _frame := 0
	var _clock := 0.0
	var _state := "wait"

	func _ready() -> void:
		custom_minimum_size = Vector2(minf(limit.x, 170.0), 44.0)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Открыть крупно" if centered_in == Vector2.ZERO else ""
		Net.chat.image_ready.connect(_on_ready)
		_take()

	func _on_ready(ready_hash: String) -> void:
		if ready_hash == hash and _state == "wait":
			_take()

	func _take() -> void:
		var data: Dictionary = Net.chat.image_frames(hash)
		if data.is_empty():
			if Net.chat.image_failed(hash):
				_state = "fail"
				queue_redraw()
			return
		_frames = data.get("frames", [])
		_delays = data.get("delays", PackedFloat32Array())
		if _frames.is_empty():
			_state = "fail"
			queue_redraw()
			return
		_state = "ok"
		var natural: Vector2 = (_frames[0] as Texture2D).get_size()
		var fit := minf(limit.x / natural.x, limit.y / natural.y)
		if not grow:
			fit = minf(1.0, fit)
		fit = minf(fit, 3.0)
		custom_minimum_size = (natural * fit).round()
		if centered_in != Vector2.ZERO:
			size = custom_minimum_size
			position = ((centered_in - size) * 0.5).round()
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_clock += delta
		if _state == "wait":
			if _clock >= 2.0:  # картинка ещё едет — напомнить о себе
				_clock = 0.0
				_take()
			return
		if _frames.size() < 2:
			set_process(false)
			return
		var wait := maxf(0.02, _delays[_frame] if _frame < _delays.size() else 0.1)
		if _clock >= wait:
			_clock = 0.0
			_frame = (_frame + 1) % _frames.size()
			queue_redraw()

	func _draw() -> void:
		if _state == "ok":
			draw_texture_rect(_frames[_frame], Rect2(Vector2.ZERO, custom_minimum_size), false)
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.07))
		var note := "Картинка загружается…" if _state == "wait" else "Картинку не удалось показать"
		draw_string(ThemeDB.fallback_font, Vector2(8, 26), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.86))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _state == "ok":
			clicked.emit(hash)
			accept_event()
