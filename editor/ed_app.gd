extends Control
## Оболочка редактора и первые инструменты компонентов. Запуск: res://editor/main.tscn.

const Style := preload("res://editor/ed_style.gd")
## Стиль игр — для предпросмотров того, что увидят игроки.
const Game := preload("res://games/custom/ui/cg_style.gd")

const Document := preload("res://editor/ed_document.gd")
const Help := preload("res://editor/ed_help.gd")
const FaceEditor := preload("res://editor/ed_card_face.gd")
const Library := preload("res://games/custom/logic/cg_library.gd")
const Assets := preload("res://editor/ed_assets.gd")
const Csv := preload("res://editor/ed_csv.gd")
const Package := preload("res://games/custom/logic/cg_package.gd")
const Blocks := preload("res://games/custom/logic/cg_blocks.gd")
const Faces := preload("res://games/custom/logic/cg_faces.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const Canvas := preload("res://editor/ed_canvas.gd")
const Logic := preload("res://editor/ed_logic.gd")
const BoxEditor := preload("res://editor/ed_box.gd")
const BoxView := preload("res://editor/ed_box_view.gd")
const ElementsModel := preload("res://editor/ed_elements.gd")
const Issues := preload("res://editor/ed_issues.gd")
const Tutorial := preload("res://editor/ed_tutorial.gd")
const TutorialUI := preload("res://editor/ed_tutorial_ui.gd")
const BoardPreview := preload("res://editor/ed_board_preview.gd")
const TrackPreview := preload("res://editor/ed_track_preview.gd")
const Templates := preload("res://editor/ed_templates.gd")
## Подписи размеров по номеру в CGDef.CARD_SIZES (мм — как у настоящих карт).
const CARD_SIZE_TITLES := ["Мини · 44×68", "Бридж · 57×89", "Стандарт · 63×88", "Большая · 70×110", "Макси · 80×120", "Квадрат · 70", "Квадрат · 100", "Квадрат · 60", "Квадрат · 45",
	"Горизонтальная маленькая · 68×44", "Горизонтальная стандарт · 88×63", "Горизонтальная большая · 110×70"]
var document := Document.new()
var _editing := false
var _tab := 3
var _deck := 0
var _shell: VBoxContainer
var _status: Label
var _message := ""
var _sheet := ""
var _source := ""
var _undo_button: Button
var _redo_button: Button
var _heading: Label
var _category := "decks"
var _layout_selected := -1
var _layout_canvas: Control
var _layout_zoom := 1.0
var _layout_pan := Vector2.ZERO
var _layout_guides := true
var _logic_chain := -1
var _logic_path: Array = []
var _logic_target: Array = []
var _logic_phase := ""
var _logic_scroll := 0
var _logic_zoom := 1.0
var _logic_collapsed := {}
var _logic_phase_tools := false
var _box_view: Control
var _box_face := "front"
var _box_mode_3d := true
var _box_layer := -1
var _saving := false
var _baked_signature := ""
var _help := Help.new()
var _help_tab := -1
var _tab_tip := ""
var _help_done: LinkButton
var _face_edit := false
var _face_layer := -1
var _face_row := 0
var _face_zoom := 1.0
var _face_pan := Vector2.ZERO
## Панель свойств «Интерфейса» — для обновления после правки фона.
var _layout_props_box: VBoxContainer
## Предпросмотр «Игроков: N» на холсте «Интерфейса».
var _layout_players := 4
## Какой экран правится в «Интерфейсе»: 0 — общий, дальше — экраны ролей (layout.screens[i].role).
var _screen := 0
## Идущий урок вкладки «Обучение» ("" — нет) и была ли уже проверка игрой.
var _lesson := ""
var _lesson_played := false

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = Style.theme()
	# Фон «другого измерения»: градиент, сетка и дождь символов (ed_style.gd: Backdrop).
	var background := Style.Backdrop.new()
	background.name = "EditorBackdrop"
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	_shell = Style.column(16)
	margin.add_child(_shell)
	var autosave := Timer.new()
	autosave.wait_time = 60
	autosave.autostart = true
	autosave.timeout.connect(func():
		if _editing and document.dirty:
			await _save())
	add_child(autosave)
	Prefs.changed.connect(func():
		theme = Style.theme()
		background.refresh()
		_render())
	var remembered := str(Net.settings.get("cg_editor_id", ""))
	if Library.uuid_valid(remembered) and document.open(remembered):
		_editing = true
		_message = document.last_error
	_render()

func _reset_logic_navigation() -> void:
	_logic_chain = -1
	_logic_path = []
	_logic_target = []
	_logic_phase = ""
	_logic_scroll = 0
	_logic_zoom = 1.0
	_logic_collapsed.clear()
	_logic_phase_tools = false
	_face_edit = false
	_face_layer = -1
	_face_row = 0
	_face_zoom = 1.0
	_face_pan = Vector2.ZERO

func _render() -> void:
	if is_instance_valid(_layout_canvas):
		_layout_zoom = _layout_canvas.zoom
		_layout_pan = _layout_canvas.pan
	Style.clear(_shell)
	var header := Style.row(16)
	_shell.add_child(header)
	var back := Style.button("← Мои игры" if _editing else "← В хаб")
	back.pressed.connect(_back)
	header.add_child(back)
	var title := Style.heading(str(document.data.get("meta", {}).get("title", "РЕДАКТОР")) if _editing else "РЕДАКТОР")
	_heading = title
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.clip_text = true
	header.add_child(title)
	if not _editing:
		_library()
		return
	var undo := Style.button("↶ Отмена")
	_undo_button = undo
	undo.disabled = document.undo_stack.is_empty()
	undo.pressed.connect(func():
		document.undo()
		_render())
	header.add_child(undo)
	var redo := Style.button("↷ Повтор")
	_redo_button = redo
	redo.disabled = document.redo_stack.is_empty()
	redo.pressed.connect(func():
		document.redo()
		_render())
	header.add_child(redo)
	var issues := Style.button("Ошибки")
	issues.pressed.connect(_show_issues)
	header.add_child(issues)
	var test := Style.primary("Проверить")
	test.pressed.connect(_play)
	header.add_child(test)
	var tabs := Style.row()
	_shell.add_child(tabs)
	var titles := ["Коробка", "Интерфейс", "Логика", "Элементы", "Обучение"]
	for index in titles.size():
		var button := Style.button(titles[index])
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		if index == _tab:
			# Активная вкладка-«портал»: кромка акцентом и свечение.
			for state: String in ["normal", "hover"]:
				button.add_theme_stylebox_override(state, Style.glow_box(Color(Style.panel(), 0.9)))
		button.pressed.connect(func():
			if not await _save():
				return
			_tab = index
			_render())
		tabs.add_child(button)
	var body := Style.row(16)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	_shell.add_child(body)
	# Боковые панели — стекло с неоновой кромкой.
	var tool_glass := PanelContainer.new()
	tool_glass.name = "EditorToolsGlass"
	tool_glass.add_theme_stylebox_override("panel", Style.box(Style.panel(), 8))
	body.add_child(tool_glass)
	var tool_scroll := ScrollContainer.new()
	tool_scroll.custom_minimum_size.x = 208
	tool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tool_glass.add_child(tool_scroll)
	var tools := Style.column(8)
	tools.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.custom_minimum_size.x = 160
	tool_scroll.add_child(tools)
	var center := Style.column(16)
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(center)
	var property_scroll := ScrollContainer.new()
	property_scroll.custom_minimum_size.x = 304
	# Свойства только по вертикали: широкие выпадающие списки обрезаются, а не дают прокрутку вбок.
	property_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var property_glass := PanelContainer.new()
	property_glass.name = "EditorPropertiesGlass"
	property_glass.add_theme_stylebox_override("panel", Style.box(Style.panel(), 8))
	body.add_child(property_glass)
	property_glass.add_child(property_scroll)
	var properties := Style.column(8)
	properties.custom_minimum_size.x = 288
	property_scroll.add_child(properties)
	match _tab:
		0:
			var box_editor := BoxEditor.new()
			box_editor.setup(self, tools, center, properties)
		1: _layout(tools, center, properties)
		2: _logic(tools, center, properties)
		3: _elements(tools, center, properties)
		4: TutorialUI.build(self, tools, center, properties)
	_status = Style.label("")
	var status_row := Style.row(8)
	_shell.add_child(status_row)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.clip_text = true
	status_row.add_child(_status)
	if _help_tab != _tab:
		_help_tab = _tab
		_tab_tip = _help.tip(_tab) if _tab < 4 else ""
	_help_done = LinkButton.new()
	_help_done.name = "EditorHintDone"
	_help_done.text = "Понятно"
	_help_done.pressed.connect(_dismiss_help)
	status_row.add_child(_help_done)
	var help := LinkButton.new()
	help.name = "EditorHelpButton"
	help.text = "Справка"
	help.tooltip_text = "Как пользоваться этой вкладкой"
	help.pressed.connect(func(): _help.show(self, _tab, _dismiss_help))
	help.visible = _tab < 4
	status_row.add_child(help)
	if not _lesson.is_empty() and _tab != 4:
		var lesson := LinkButton.new()
		lesson.name = "EditorBackToLesson"
		lesson.text = "К уроку"
		lesson.pressed.connect(func():
			if await _save():
				_tab = 4
				_render())
		status_row.add_child(lesson)
	_status_text()

func _dismiss_help() -> void:
	_help.dismiss(_tab)
	_tab_tip = ""
	_status_text()

func _library() -> void:
	_shell.add_child(Style.label("Создавайте свою игру из компонентов и правил. Проекты сохраняются на этом компьютере."))
	var row := Style.row()
	_shell.add_child(row)
	var template := OptionButton.new()
	for text: String in ["Пустая песочница", "Карточная гонка", "Больше или меньше", "Ставка на кубики"]:
		template.add_item(text)
	row.add_child(template)
	var create := Style.primary("Новая игра")
	create.pressed.connect(func():
		if document.create(["blank", "card_race", "higher_lower", "dice_bid"][template.selected]):
			_editing = true
			_reset_logic_navigation()
			_deck = 0
			_tab = 3
			_lesson = ""
			_render())
	row.add_child(create)
	var from_kit := Style.button("Из шаблона…")
	from_kit.name = "LibraryKits"
	from_kit.tooltip_text = "Готовая игра по мотивам игр сборника: стол, фон, колода, правила, цвета и кнопки."
	from_kit.pressed.connect(_kits_dialog)
	row.add_child(from_kit)
	var tutorial := Style.button("Обучение: игра про слова")
	tutorial.name = "LibraryTutorial"
	tutorial.tooltip_text = "Новый пустой проект и пошаговый урок: соберёте «Объясни слово» со словарём."
	tutorial.pressed.connect(func():
		if document.create("blank"):
			_editing = true
			_reset_logic_navigation()
			_deck = 0
			_tab = 4
			_lesson = Tutorial.WORDS
			_lesson_played = false
			_render())
	row.add_child(tutorial)
	var import_button := Style.button("Открыть .pgame…")
	import_button.name = "LibraryImport"
	import_button.tooltip_text = "Добавить игру из файла .pgame (от друга или своей копии) — новой игрой в «Мои игры»"
	import_button.pressed.connect(func():
		_with_notice(func(): _dialog(PackedStringArray(["*.pgame ; Игра из редактора"]), false, func(path: String):
			var result := Library.import_game(path)
			_message = str(result.error) if not str(result.error).is_empty() else "Игра добавлена в «Мои игры»."
			_render.call_deferred())))
	row.add_child(import_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_shell.add_child(scroll)
	var list := Style.column(8)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	Library.invalidate()
	var games := Library.list()
	if games.is_empty():
		list.add_child(Style.heading("Здесь будут ваши игры"))
		list.add_child(Style.label("Начните с шаблона или пустого стола без правил."))
	for game: Dictionary in games:
		var row_item := Style.row(8)
		list.add_child(row_item)
		var thumbnail := TextureRect.new()
		thumbnail.texture = Library.cover_texture(str(game.uuid), "front")
		thumbnail.custom_minimum_size = Vector2(64, 64)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row_item.add_child(thumbnail)
		var button := Style.button(str(game.title) + "   ·   " + str(game.players))
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.clip_text = true
		button.pressed.connect(func():
			if document.open(str(game.uuid)):
				_editing = true
				_reset_logic_navigation()
				_message = document.last_error
				_deck = 0
				_render())
		row_item.add_child(button)
		var export := Style.button("Файлом")
		export.name = "LibraryExport"
		export.tooltip_text = "Сохранить игру файлом .pgame — его можно переслать другу или держать как копию"
		export.pressed.connect(func():
			_with_notice(func(): _save_dialog(str(game.title), func(path: String):
				var result := Library.export_game(str(game.uuid), path)
				_message = str(result.error) if not str(result.error).is_empty() else "Игра сохранена: %s (%d КБ)." % [str(result.path).get_file(), int(result.size) / 1024]
				_render.call_deferred())))
		row_item.add_child(export)
		var duplicate := Style.button("Копия")
		duplicate.tooltip_text = "Создать копию последней сохранённой версии с новой коробкой на полке"
		duplicate.pressed.connect(func():
			var result := Library.duplicate_game(str(game.uuid))
			_message = str(result.error)
			_render.call_deferred())
		row_item.add_child(duplicate)
		var remove := Style.button("Убрать")
		LeaveGuard.hold(remove, func():
			if Net.in_session() and Net.party_game == str(game.id):
				_message = "Сначала выйдите из пати этой игры."
			else:
				_message = Library.trash_game(str(game.uuid))
			_render.call_deferred(), "Убрать в локальную корзину проектов?")
		row_item.add_child(remove)
	if not _message.is_empty():
		_shell.add_child(Style.label(_message))

func _text(parent: Node, caption: String, path: Array) -> void:
	parent.add_child(Style.label(caption))
	var value: Variant = document.data
	for key: Variant in path:
		value = value.get(key, "") if value is Dictionary else value[key]
	var field := LineEdit.new()
	field.text = str(value)
	field.custom_minimum_size.y = 40
	field.text_changed.connect(func(text: String):
		_message = ""
		document.set_value(path, text, caption)
		if path == ["meta", "title"]:
			if is_instance_valid(_heading):
				_heading.text = text
		_status_text())
	parent.add_child(field)

func _number(parent: Node, caption: String, path: Array, minimum: float, maximum: float, step: float = 1) -> void:
	parent.add_child(Style.label(caption))
	var value: Variant = document.data
	for key: Variant in path:
		value = value.get(key, 0) if value is Dictionary else value[key]
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = step
	number.value = float(value)
	number.custom_minimum_size.y = 40
	number.value_changed.connect(func(next: float):
		_message = ""
		document.set_value(path, next, caption)
		_status_text())
	parent.add_child(number)

func _layout(tools: VBoxContainer, center: VBoxContainer, properties: VBoxContainer) -> void:
	center.add_child(Style.heading("РАСКЛАДКА СТОЛА"))
	center.add_child(Style.label("Колесо — масштаб · ПКМ — панорама · угол — размер · Alt — без направляющих"))
	var view := OptionButton.new()
	var perspectives: Array = ["all", "spectator"]
	var perspective_labels: Array = ["Смотреть как: все роли", "Зритель"]
	for role: Dictionary in document.data.rules.get("roles", []):
		perspectives.append("role:" + str(role.id))
		perspective_labels.append(str(role.get("name", role.id)))
	for caption: String in perspective_labels:
		view.add_item(caption)
	var view_tools := HBoxContainer.new()
	view_tools.add_theme_constant_override("separation", 8)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_tools.add_child(view)
	center.add_child(view_tools)
	var players_preview := OptionButton.new()
	players_preview.name = "LayoutPreviewPlayers"
	players_preview.tooltip_text = "Предпросмотр: сколько мест у полос «Игроки» и «Соперники»."
	var seats_range: Array = document.data.meta.get("players", [2, 8])
	for count in range(int(seats_range[0]), int(seats_range[1]) + 1):
		players_preview.add_item("Игроков: %d" % count, count)
	players_preview.select(maxi(0, players_preview.get_item_index(clampi(_layout_players, int(seats_range[0]), int(seats_range[1])))))
	view_tools.add_child(players_preview)
	var guides := CheckButton.new()
	guides.text = "Направляющие"
	guides.tooltip_text = "Привязка к краям и центрам видимых элементов. Alt временно отключает её; сетка 8 px сохраняется."
	guides.button_pressed = _layout_guides
	view_tools.add_child(guides)
	if document.data.layout.get("screens", []).is_empty():
		document.set_value(["layout", "screens"], [{"id": "main", "items": []}], "Создать экран")
	_screen = clampi(_screen, 0, document.data.layout.screens.size() - 1)
	_screen_tools(center)
	_layout_canvas = Canvas.new()
	_layout_canvas.zoom = _layout_zoom
	_layout_canvas.pan = _layout_pan
	_layout_canvas.guides_enabled = _layout_guides
	_layout_canvas.items = document.data.layout.screens[_screen].get("items", []).duplicate(true)
	_layout_canvas.board_zones = Definition.board_zone_ids(document.data)
	_layout_canvas.preview_players = players_preview.get_selected_id()
	players_preview.item_selected.connect(func(index: int):
		_layout_players = players_preview.get_item_id(index)
		_layout_canvas.preview_players = _layout_players
		_layout_canvas.queue_redraw())
	_layout_canvas.look = document.data.meta.get("look", {}).duplicate() if document.data.meta.get("look") is Dictionary else {}
	_sync_background()
	_layout_props_box = properties
	_layout_selected = mini(_layout_selected, _layout_canvas.items.size() - 1)
	_layout_canvas.selection = _layout_selected
	center.add_child(_layout_canvas)
	guides.toggled.connect(func(enabled: bool):
		_layout_guides = enabled
		_layout_canvas.guides_enabled = enabled
		_layout_canvas._guides.clear()
		_layout_canvas.queue_redraw())
	view.item_selected.connect(func(index: int):
		_layout_canvas.perspective = perspectives[index]
		_layout_canvas.queue_redraw())
	_layout_canvas.selected.connect(func(index: int):
		_layout_selected = index
		_layout_properties(properties))
	_layout_canvas.changed.connect(func(index: int, rect: Rect2):
		var copy := document.data.duplicate(true)
		copy.layout.screens[_screen].items[index]["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		copy.layout["custom"] = true
		document.replace(copy, "Расположение элемента")
		_status_text()
		_layout_properties(properties))
	var templates_button := Style.primary("Шаблоны стола…")
	templates_button.name = "LayoutTemplates"
	templates_button.tooltip_text = "Готовые раскладки по жанрам: карточная, объясни слово, кубики, ходилка…"
	templates_button.pressed.connect(_layout_templates_dialog)
	tools.add_child(templates_button)
	for entry: Array in [["zone", "Зона"], ["hand", "Рука игрока"], ["self_panel", "Панель Я"], ["opponents", "Соперники"], ["teams", "Команды"], ["players", "Игроки"], ["button", "Кнопка"], ["counter", "Счётчик"], ["text", "Текст"], ["image", "Картинка"], ["dice_tray", "Лоток d6"], ["journal", "Журнал"], ["phase", "Фаза / ход"], ["board", "Планшет"], ["track", "Поле-ходилка"]]:
		var button := Style.button("+ " + str(entry[1]))
		button.pressed.connect(func(): _add_layout(str(entry[0]), str(entry[1])))
		tools.add_child(button)
	_layout_properties(properties)

## Экраны: общий и экраны ролей (ТЗ: «Свой экран роли»). Экран роли — копия общей раскладки, которую
## можно перестроить целиком; игрок с этой ролью видит только его. Зоны — те же, что на общем экране.
func _screen_tools(center: VBoxContainer) -> void:
	var row := Style.row(8)
	row.name = "LayoutScreens"
	center.add_child(row)
	var roles := {}
	for role: Dictionary in document.data.rules.get("roles", []):
		roles[str(role.id)] = str(role.get("name", role.id))
	var picker := OptionButton.new()
	picker.name = "LayoutScreenPicker"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in document.data.layout.screens.size():
		var screen: Dictionary = document.data.layout.screens[index]
		picker.add_item("Общий экран" if not screen.has("role") else "Экран: %s" % roles.get(str(screen.role), str(screen.role)), index)
	picker.select(picker.get_item_index(_screen))
	picker.item_selected.connect(func(index: int):
		_screen = picker.get_item_id(index)
		_layout_selected = -1
		_render())
	row.add_child(picker)
	var taken := {}
	for screen: Dictionary in document.data.layout.screens:
		if screen.has("role"):
			taken[str(screen.role)] = true
	var add := MenuButton.new()
	add.name = "LayoutAddRoleScreen"
	add.text = "+ Экран роли"
	add.tooltip_text = "Отдельный экран для роли (например, ведущего): копия общего, перестройте как нужно."
	add.flat = false
	for role_id: String in roles:
		if not taken.has(role_id):
			add.get_popup().add_item(str(roles[role_id]))
			add.get_popup().set_item_metadata(add.get_popup().item_count - 1, role_id)
	add.disabled = add.get_popup().item_count == 0
	add.get_popup().index_pressed.connect(func(index: int): _add_role_screen(str(add.get_popup().get_item_metadata(index))))
	row.add_child(add)
	if _screen > 0:
		var remove := Style.button("Убрать экран")
		remove.name = "LayoutRemoveRoleScreen"
		remove.tooltip_text = "Роль снова будет видеть общий экран (Ctrl+Z вернёт)."
		remove.pressed.connect(func():
			var copy: Dictionary = document.data.duplicate(true)
			copy.layout.screens.remove_at(_screen)
			document.replace(copy, "Убрать экран роли")
			_screen = 0
			_layout_selected = -1
			_render())
		row.add_child(remove)
		var note := Style.label("Этот экран видит только роль «%s». Зоны те же, что на общем: здесь меняются их место и подпись." % roles.get(str(document.data.layout.screens[_screen].role), ""), 13)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.modulate.a = 0.75
		center.add_child(note)

func _add_role_screen(role_id: String) -> void:
	var copy: Dictionary = document.data.duplicate(true)
	var main: Dictionary = copy.layout.screens[0]
	var items: Array = main.get("items", []).duplicate(true)
	# Элементы, которые общий экран прячет от всех, кроме этой роли, на своём экране роли видны всегда.
	for item: Dictionary in items:
		if item.get("visible") is Array and item.visible.has("role:" + role_id):
			item["visible"] = ["all"]
	copy.layout.screens.append({"id": "role_" + role_id, "role": role_id, "items": items})
	copy.layout["custom"] = true
	document.replace(copy, "Экран роли")
	_screen = copy.layout.screens.size() - 1
	_layout_selected = -1
	_render()

## Холст получает фон стола и его картинку из документа.
func _sync_background() -> void:
	if not is_instance_valid(_layout_canvas):
		return
	var look: Dictionary = document.data.layout.get("background", {})
	_layout_canvas.background = look.duplicate(true)
	var reader = load("res://games/custom/ui/cg_assets.gd").new()
	reader.configure_document(document.data)
	_layout_canvas.background_texture = reader.image(str(look.get("image", ""))) if not str(look.get("image", "")).is_empty() else null
	_layout_canvas.queue_redraw()

## «Фон стола»: цвет, картинка, как вписать, затемнение. Виден, когда на холсте ничего не выбрано.
func _background_properties(properties: VBoxContainer) -> void:
	var look: Dictionary = document.data.layout.get("background", {})
	_look_properties(properties)
	properties.add_child(Style.heading("ФОН СТОЛА"))
	_background_presets(properties)
	var own_color := CheckBox.new()
	own_color.name = "TableBackgroundOwnColor"
	own_color.text = "Свой цвет фона"
	own_color.button_pressed = not str(look.get("color", "")).is_empty()
	own_color.toggled.connect(func(on: bool): _set_background("color", "#2c3b33" if on else ""))
	properties.add_child(own_color)
	if own_color.button_pressed:
		var picker := ColorPickerButton.new()
		picker.name = "TableBackgroundColor"
		picker.custom_minimum_size.y = 40
		picker.edit_alpha = false
		picker.color = Color.from_string(str(look.color), Style.bg())
		picker.popup_closed.connect(func(): _set_background("color", "#" + picker.color.to_html(false)))
		properties.add_child(picker)
	var labels: Array = ["Без картинки"]
	var values: Array = [""]
	for hash_value: String in document.data.get("assets", {}):
		var asset: Dictionary = document.data.assets[hash_value]
		if str(asset.get("path", "")).begins_with("assets/img/"):
			labels.append(str(asset.get("name", "Картинка %d" % labels.size())).get_file())
			values.append(hash_value)
	properties.add_child(Style.label("Картинка"))
	var image := OptionButton.new()
	image.name = "TableBackgroundImage"
	image.clip_text = true
	image.fit_to_longest_item = false
	for caption: String in labels:
		image.add_item(caption)
	image.select(maxi(0, values.find(str(look.get("image", "")))))
	image.item_selected.connect(func(index: int): _set_background("image", values[index]))
	properties.add_child(image)
	var import_button := Style.button("Загрузить картинку фона")
	import_button.pressed.connect(func():
		_with_notice(func(): _dialog(PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Фон стола"]), false, _import_background)))
	properties.add_child(import_button)
	if str(look.get("image", "")).is_empty():
		return
	properties.add_child(Style.label("Как вписать"))
	var fit := OptionButton.new()
	fit.name = "TableBackgroundFit"
	var fits: Array = ["cover", "stretch", "center", "tile"]
	for caption: String in ["Заполнить (обрезать края)", "Растянуть", "По центру целиком", "Плиткой"]:
		fit.add_item(caption)
	fit.select(maxi(0, fits.find(str(look.get("fit", "cover")))))
	fit.item_selected.connect(func(index: int): _set_background("fit", fits[index]))
	properties.add_child(fit)
	properties.add_child(Style.label("Затемнение — чтобы карты и текст читались"))
	var dim := HSlider.new()
	dim.name = "TableBackgroundDim"
	dim.min_value = 0
	dim.max_value = 0.9
	dim.step = 0.05
	dim.value = float(look.get("dim", 0))
	dim.custom_minimum_size.y = 32
	dim.drag_ended.connect(func(changed: bool):
		if changed:
			_set_background("dim", dim.value))
	properties.add_child(dim)

## Окно-галерея шаблонов: заголовок, пояснение, сетка карточек. Возвращает {window, grid, top}.
func _gallery(window_name: String, title: String, note_text: String, columns: int) -> Dictionary:
	var window := Window.new()
	window.name = window_name
	window.title = title
	window.size = Vector2i(880, 600)
	window.theme = Style.theme()
	Style.window_surface(window)
	add_child(window)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -16
	window.add_child(scroll)
	var column := Style.column(12)
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(column)
	var note := Style.label(note_text)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate.a = 0.8
	column.add_child(note)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	window.close_requested.connect(window.queue_free)
	return {"window": window, "grid": grid, "top": column}

## Карточка галереи: картинка (вписана целиком), подпись и строка «из какой игры».
func _gallery_card(name_value: String, size: Vector2, texture: Texture2D, title: String, hint: String, friends: bool) -> Button:
	var card := Button.new()
	card.name = name_value
	card.custom_minimum_size = size
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.tooltip_text = (Templates.FRIENDS_NOTE % hint) if friends else hint
	card.draw.connect(func():
		var area := Rect2(Vector2(12, 12), card.size - Vector2(24, 72))
		if texture != null:
			var fit := minf(area.size.x / texture.get_width(), area.size.y / texture.get_height())
			var shown := Vector2(texture.get_size()) * fit
			card.draw_texture_rect(texture, Rect2(area.position + (area.size - shown) * 0.5, shown), false)
		card.draw_string(Style.head_font(), Vector2(12, card.size.y - 38), title, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 24, 16, Style.ink())
		card.draw_string(Style.body_font(), Vector2(12, card.size.y - 16), hint + (" · для друзей" if friends else ""), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 24, 13, Color(Style.ink(), 0.7)))
	return card

## «Новая игра из шаблона»: карточки наборов (схема стола в цветах набора); выбор создаёт проект и собирает игру.
func _kits_dialog() -> void:
	var parts := _gallery("KitsWindow", "Новая игра из шаблона", "Готовая игра по мотивам игр сборника: раскладка стола, фон, колода с лицом и рубашкой, кубики или монеты, правила, цвета и кнопки. Потом всё меняется как обычно.", 2)
	var window: Window = parts.window
	var grid: GridContainer = parts.grid
	for spec: Dictionary in Templates.KITS:
		var card := Button.new()
		card.name = "Kit_" + str(spec.id)
		card.custom_minimum_size = Vector2(400, 232)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var look: Dictionary = Templates.entry_of(Templates.LOOKS, str(spec.get("look", "")))
		card.draw.connect(func():
			Style.set_game_look({"main": look.main, "accent": look.accent} if not look.is_empty() else {})
			_draw_layout_scheme(card, Templates.layout(str(spec.layout)))
			Style.set_game_look({})
			card.draw_rect(Rect2(Vector2(0, card.size.y - 56), Vector2(card.size.x, 56)), Style.panel())
			card.draw_string(Style.head_font(), Vector2(16, card.size.y - 32), str(spec.title), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 20, Style.ink())
			card.draw_string(Style.body_font(), Vector2(16, card.size.y - 10), "По мотивам «%s»" % spec.game, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 14, Color(Style.ink(), 0.7)))
		card.pressed.connect(func():
			window.queue_free()
			if not document.create("blank"):
				_message = document.last_error
				_status_text()
				return
			var result: Dictionary = Templates.apply_kit(document.data, str(spec.id))
			document.replace(result.data, "Игра из шаблона: " + str(spec.title))
			_message = ("Игра «%s» собрана. Проверьте её кнопкой «Проверить»." % spec.title) if str(result.error).is_empty() else str(result.error)
			_editing = true
			_reset_logic_navigation()
			_deck = 0
			_tab = 1
			_lesson = ""
			_render())
		grid.add_child(card)
	window.popup_centered()

## «Шаблоны правил»: готовые цепочки добавляются к вашим; нужные зоны, «Очки» и кнопки появляются сами.
func _rule_templates_dialog() -> void:
	var parts := _gallery("RuleTemplatesWindow", "Шаблоны правил", "Цепочки добавятся к вашим (свои не удаляются). Нужные зоны, ресурс «Очки» и кнопки найдутся в проекте или появятся на столе. Отменить — Ctrl+Z.", 2)
	var window: Window = parts.window
	var grid: GridContainer = parts.grid
	for template: Dictionary in Templates.RULES:
		var card := Button.new()
		card.name = "RuleTemplate_" + str(template.id)
		card.custom_minimum_size = Vector2(400, 112)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		card.draw.connect(func():
			card.draw_string(Style.head_font(), Vector2(16, 34), str(template.title), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 20, Style.ink())
			card.draw_multiline_string(Style.body_font(), Vector2(16, 60), str(template.hint), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 14, 2, Color(Style.ink(), 0.8))
			card.draw_string(Style.body_font(), Vector2(16, card.size.y - 12), "Как в: " + str(template.game), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 13, Color(Style.ink(), 0.6)))
		card.pressed.connect(func():
			var before: int = document.data.rules.get("chains", []).size()
			document.replace(Templates.apply_rules(document.data, str(template.id)), "Шаблон правил: " + str(template.title))
			_message = "«%s»: добавлено цепочек — %d. Отменить — Ctrl+Z." % [template.title, document.data.rules.get("chains", []).size() - before]
			_logic_chain = document.data.rules.get("chains", []).size() - 1
			window.queue_free()
			_render())
		grid.add_child(card)
	window.popup_centered()

## «Шаблоны рубашек»: нарисованные узоры и рубашки карт из игр сборника → рубашка текущей колоды.
func _back_templates_dialog() -> void:
	var parts := _gallery("BackTemplatesWindow", "Шаблоны рубашек", "Рубашка кладётся в картинки игры и сразу ставится колоде. Рубашки с пометкой «для друзей» — арт оригинальных игр: только для игры с друзьями, как и сами эти игры в сборнике. Отменить — Ctrl+Z.", 4)
	var window: Window = parts.window
	var grid: GridContainer = parts.grid
	var options: Array = []
	for look: Dictionary in Templates.DRAWN_BACKS:
		options.append({"kind": "drawn", "id": look.id, "title": str(look.title), "hint": "Узор", "friends": false, "texture": ImageTexture.create_from_image(Templates.drawn_back_image(str(look.id)))})
	for entry: Dictionary in Templates.available(Templates.GAME_BACKS):
		options.append({"kind": "game", "id": entry.id, "title": str(entry.title), "hint": str(entry.game), "friends": bool(entry.friends), "texture": load(str(entry.path))})
	for option: Dictionary in options:
		var card := _gallery_card("BackTemplate_" + str(option.id), Vector2(180, 280), option.texture, option.title, option.hint, option.friends)
		card.pressed.connect(func():
			var result: Dictionary = Templates.apply_back(document.data, _deck, str(option.kind), str(option.id))
			_message = str(result.error)
			if _message.is_empty():
				document.replace(result.data, "Рубашка: " + str(option.title))
				_message = "Рубашка «%s» — у колоды «%s»." % [option.title, str(document.data.elements.decks[_deck].get("title", ""))]
			window.queue_free()
			_render())
		grid.add_child(card)
	window.popup_centered()

## «Оформление игры»: цвета стола вместо темы приложения — готовые пары и свои основной цвет/акцент.
func _look_properties(properties: VBoxContainer) -> void:
	var look: Dictionary = document.data.meta.get("look", {}) if document.data.meta.get("look") is Dictionary else {}
	properties.add_child(Style.heading("ОФОРМЛЕНИЕ"))
	var note := Style.label("Цвета стола игры. «Как в сборнике» — светлая или тёмная тема игрока.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate.a = 0.75
	properties.add_child(note)
	var grid := GridContainer.new()
	grid.name = "LookPresets"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var options: Array = [{"id": "app", "title": "Как в сборнике", "main": "", "accent": ""}] + Templates.LOOKS
	for option: Dictionary in options:
		var button := Button.new()
		button.name = "LookPreset_" + str(option.id)
		button.tooltip_text = str(option.title)
		button.custom_minimum_size = Vector2(72, 56)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		var chosen: bool = str(look.get("main", "")) == str(option.main) and str(look.get("accent", "")) == str(option.accent)
		var preset_font: Font = load("res://editor/ed_fonts.gd").font(str(option.get("font", "")))
		button.draw.connect(func():
			var area := Rect2(Vector2(4, 4), button.size - Vector2(8, 26))
			if str(option.main).is_empty():
				button.draw_rect(Rect2(area.position, Vector2(area.size.x * 0.5, area.size.y)), Color("171322"))
				button.draw_rect(Rect2(area.position + Vector2(area.size.x * 0.5, 0), Vector2(area.size.x * 0.5, area.size.y)), Color("e9e5ef"))
			else:
				button.draw_rect(area, Color(str(option.main)))
				button.draw_circle(area.get_center(), area.size.y * 0.3, Color(str(option.accent)))
			if chosen:
				button.draw_rect(area.grow(2), Style.accent(), false, 3)
			button.draw_string(preset_font if preset_font != null else Style.body_font(), Vector2(4, button.size.y - 6), str(option.title), HORIZONTAL_ALIGNMENT_CENTER, button.size.x - 8, 12, Style.ink()))
		button.pressed.connect(func():
			var copy: Dictionary = document.data.duplicate(true)
			var kept: Variant = copy.meta.get("look", {}).get("buttons") if copy.meta.get("look") is Dictionary else null
			if str(option.main).is_empty():
				copy.meta.erase("look")
				if kept is Dictionary:
					copy.meta["look"] = {"buttons": kept}
			else:
				copy.meta["look"] = {"main": str(option.main), "accent": str(option.accent), "font": str(option.get("font", ""))}
				if kept is Dictionary:
					copy.meta.look["buttons"] = kept
			document.replace(copy, "Оформление: " + str(option.title))
			_render())
		grid.add_child(button)
	properties.add_child(grid)
	if look.has("main"):
		_look_colors(properties, look)
	_button_style_properties(properties, look)

## Пипетки цветов игры и шрифт заголовков (когда выбрано своё оформление).
func _look_colors(properties: VBoxContainer, look: Dictionary) -> void:
	for item: Array in [["main", "Основной цвет (фон стола)"], ["accent", "Акцент (главная кнопка, выделение)"]]:
		properties.add_child(Style.label(item[1]))
		var picker := ColorPickerButton.new()
		picker.name = "LookColor_" + str(item[0])
		picker.custom_minimum_size.y = 40
		picker.edit_alpha = false
		picker.color = Color(str(look.get(item[0], "#888888")))
		picker.popup_closed.connect(func():
			document.set_value(["meta", "look", item[0]], "#" + picker.color.to_html(false), "Цвет оформления")
			_render.call_deferred())
		properties.add_child(picker)
	properties.add_child(Style.label("Шрифт заголовков"))
	var fonts: GDScript = load("res://editor/ed_fonts.gd")
	var font_menu := OptionButton.new()
	font_menu.name = "LookFont"
	var font_ids: Array = [""] + fonts.IDS
	font_menu.add_item("Как в сборнике")
	for caption: String in fonts.NAMES:
		font_menu.add_item(caption)
	font_menu.select(maxi(0, font_ids.find(str(look.get("font", "")))))
	font_menu.item_selected.connect(func(index: int):
		document.set_value(["meta", "look", "font"], font_ids[index], "Шрифт заголовков")
		_render.call_deferred())
	properties.add_child(font_menu)

## «Кнопки»: вид всех кнопок игры, в том числе верхней полосы (Чат, Пауза, Выйти…) — только внешний вид.
func _button_style_properties(properties: VBoxContainer, look: Dictionary) -> void:
	var current: Dictionary = look.get("buttons", {}) if look.get("buttons") is Dictionary else {}
	properties.add_child(Style.heading("КНОПКИ"))
	var note := Style.label("Вид всех кнопок игры, и в верхней полосе тоже. Что делает кнопка, не меняется.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate.a = 0.75
	properties.add_child(note)
	var grid := GridContainer.new()
	grid.name = "ButtonPresets"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var options: Array = [{"id": "app", "title": "Как в сборнике", "game": "", "buttons": {}}] + Templates.BUTTON_STYLES
	for option: Dictionary in options:
		var sample := _styled_sample(look, option.buttons, str(option.title), false)
		sample.name = "ButtonPreset_" + str(option.id)
		sample.size_flags_horizontal = SIZE_EXPAND_FILL
		sample.tooltip_text = ("Как в «%s»" % option.game) if not str(option.game).is_empty() else str(option.title)
		if current == option.buttons or current.is_empty() and option.id == "app":
			sample.text = "✓ " + sample.text
		sample.pressed.connect(func(): _set_button_style(option.buttons.duplicate()))
		grid.add_child(sample)
	properties.add_child(grid)
	if current.is_empty():
		return
	properties.add_child(Style.label("Образец"))
	var preview := Style.row(8)
	preview.name = "ButtonPreview"
	preview.add_child(_styled_sample(look, current, "Кнопка", false))
	preview.add_child(_styled_sample(look, current, "Главная", true))
	properties.add_child(preview)
	for item: Array in [["fill", "Заливка"], ["text", "Цвет текста"], ["border", "Окантовка"]]:
		var line := Style.row(8)
		var own := CheckBox.new()
		own.name = "ButtonOwn_" + str(item[0])
		own.text = item[1]
		own.button_pressed = Color.html_is_valid(str(current.get(item[0], "")))
		own.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(own)
		var picker := ColorPickerButton.new()
		picker.name = "ButtonColor_" + str(item[0])
		picker.custom_minimum_size = Vector2(72, 36)
		picker.edit_alpha = false
		picker.disabled = not own.button_pressed
		picker.color = Color(str(current.get(item[0], ""))) if own.button_pressed else Style.panel()
		own.toggled.connect(func(on: bool): _set_button_value(item[0], ("#" + picker.color.to_html(false)) if on else ""))
		picker.popup_closed.connect(func(): _set_button_value(item[0], "#" + picker.color.to_html(false)))
		line.add_child(picker)
		properties.add_child(line)
	for item: Array in [["border_width", "Толщина окантовки", 0, 6], ["radius", "Скругление углов", 0, 28]]:
		properties.add_child(Style.label(item[1]))
		var slider := HSlider.new()
		slider.name = "ButtonValue_" + str(item[0])
		slider.min_value = item[2]
		slider.max_value = item[3]
		slider.step = 1
		slider.value = float(current.get(item[0], 1 if item[0] == "border_width" else 8))
		slider.custom_minimum_size.y = 32
		slider.drag_ended.connect(func(changed: bool):
			if changed:
				_set_button_value(item[0], int(slider.value)))
		properties.add_child(slider)
	properties.add_child(Style.label("Шрифт кнопок"))
	var fonts: GDScript = load("res://editor/ed_fonts.gd")
	var menu := OptionButton.new()
	menu.name = "ButtonFont"
	var ids: Array = [""] + fonts.IDS
	menu.add_item("Как в сборнике")
	for caption: String in fonts.NAMES:
		menu.add_item(caption)
	menu.select(maxi(0, ids.find(str(current.get("font", "")))))
	menu.item_selected.connect(func(index: int): _set_button_value("font", ids[index]))
	properties.add_child(menu)
	var shadow := CheckBox.new()
	shadow.name = "ButtonShadow"
	shadow.text = "Тень под кнопкой"
	shadow.button_pressed = bool(current.get("shadow", true))
	shadow.toggled.connect(func(on: bool): _set_button_value("shadow", on))
	properties.add_child(shadow)

## Кнопка-образец в стиле buttons (оформление игры включается только на время создания).
func _styled_sample(look: Dictionary, buttons: Dictionary, caption: String, main: bool) -> Button:
	var draft: Dictionary = look.duplicate(true)
	draft["buttons"] = buttons
	Game.set_game_look(draft)
	var sample := Game.primary(caption, 13) if main else Game.button(caption, 13)
	Game.set_game_look({})
	sample.clip_text = true
	return sample

func _set_button_style(buttons: Dictionary) -> void:
	var copy: Dictionary = document.data.duplicate(true)
	var look: Dictionary = copy.meta.get("look", {}) if copy.meta.get("look") is Dictionary else {}
	if buttons.is_empty():
		look.erase("buttons")
	else:
		look["buttons"] = buttons
	if look.is_empty():
		copy.meta.erase("look")
	else:
		copy.meta["look"] = look
	document.replace(copy, "Вид кнопок")
	_render()

func _set_button_value(key: String, value: Variant) -> void:
	var look: Dictionary = document.data.meta.get("look", {}) if document.data.meta.get("look") is Dictionary else {}
	var buttons: Dictionary = look.get("buttons", {}).duplicate() if look.get("buttons") is Dictionary else {}
	buttons[key] = value
	_set_button_style(buttons)

## «Готовые фоны» в панели фона: миниатюры плиток, клик — фон в ассеты игры и на стол.
func _background_presets(properties: VBoxContainer) -> void:
	properties.add_child(Style.label("Готовые фоны"))
	var grid := GridContainer.new()
	grid.name = "BackgroundPresets"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for look: Dictionary in Templates.BACKGROUNDS:
		var button := Button.new()
		button.name = "BackgroundPreset_" + str(look.id)
		button.tooltip_text = str(look.title)
		button.custom_minimum_size = Vector2(72, 56)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		var tile := ImageTexture.create_from_image(Templates.background_image(str(look.id)))
		button.draw.connect(func():
			var area := Rect2(Vector2(4, 4), button.size - Vector2(8, 8))
			button.draw_texture_rect_region(tile, area, Rect2(Vector2.ZERO, area.size)))
		button.pressed.connect(func():
			var result: Dictionary = Templates.apply_background(document.data, str(look.id))
			_message = str(result.error)
			if _message.is_empty():
				document.replace(result.data, "Готовый фон: " + str(look.title))
				_message = "Фон «%s» — меняйте цвет, затемнение и как вписать ниже." % look.title
				_sync_background()
			_status_text()
			if is_instance_valid(_layout_props_box):
				_layout_properties.call_deferred(_layout_props_box))
		grid.add_child(button)
	properties.add_child(grid)
	properties.add_child(Style.label("Фоны игр сборника"))
	var games := GridContainer.new()
	games.name = "GameBackgrounds"
	games.columns = 3
	games.add_theme_constant_override("h_separation", 8)
	games.add_theme_constant_override("v_separation", 8)
	for entry: Dictionary in Templates.available(Templates.GAME_BACKGROUNDS):
		var button := Button.new()
		button.name = "GameBackground_" + str(entry.id)
		button.tooltip_text = "%s — %s%s" % [entry.game, entry.title, "\n" + Templates.FRIENDS_NOTE % entry.game if entry.friends else ""]
		button.custom_minimum_size = Vector2(72, 56)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		var picture: Texture2D = load(str(entry.path))
		button.draw.connect(func():
			var area := Rect2(Vector2(4, 4), button.size - Vector2(8, 8))
			var fit := maxf(area.size.x / picture.get_width(), area.size.y / picture.get_height())
			var part := area.size / fit
			button.draw_texture_rect_region(picture, area, Rect2((Vector2(picture.get_size()) - part) * 0.5, part)))
		button.pressed.connect(func():
			var result: Dictionary = Templates.apply_game_background(document.data, str(entry.id))
			_message = str(result.error)
			if _message.is_empty():
				document.replace(result.data, "Фон игры: " + str(entry.title))
				_message = "Фон «%s» из игры «%s»." % [entry.title, entry.game]
				_sync_background()
			_status_text()
			if is_instance_valid(_layout_props_box):
				_layout_properties.call_deferred(_layout_props_box))
		games.add_child(button)
	properties.add_child(games)

## Окно «Шаблоны стола»: карточки со схемой раскладки; выбор переставляет элементы (одна правка, Ctrl+Z).
func _layout_templates_dialog() -> void:
	var window := Window.new()
	window.name = "LayoutTemplatesWindow"
	window.title = "Шаблоны стола"
	window.size = Vector2i(880, 600)
	window.theme = Style.theme()
	Style.window_surface(window)
	add_child(window)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -16
	window.add_child(scroll)
	var column := Style.column(12)
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(column)
	var note := Style.label("Раскладки — по мотивам столов игр сборника. Ваши зоны, кнопки и счётчики переставляются на места шаблона — колоды и правила продолжают работать. Недостающее добавляется. Отменить — Ctrl+Z.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate.a = 0.8
	column.add_child(note)
	var with_background := CheckBox.new()
	with_background.name = "LayoutTemplateWithBackground"
	with_background.text = "Вместе с фоном этой игры"
	with_background.button_pressed = true
	column.add_child(with_background)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for template: Dictionary in Templates.LAYOUTS:
		var card := Button.new()
		card.name = "LayoutTemplate_" + str(template.id)
		card.custom_minimum_size = Vector2(400, 232)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		card.draw.connect(func(): _draw_layout_scheme(card, template))
		card.pressed.connect(func():
			var next: Dictionary = Templates.apply_layout(document.data, str(template.id))
			var origin: Dictionary = Templates.LAYOUT_GAMES.get(str(template.id), {})
			_message = "Шаблон «%s» применён. Отменить — Ctrl+Z." % template.title
			if with_background.button_pressed and not Templates.entry_of(Templates.available(Templates.GAME_BACKGROUNDS), str(origin.get("bg", ""))).is_empty():
				var result: Dictionary = Templates.apply_game_background(next, str(origin.bg))
				if str(result.error).is_empty():
					next = result.data
				else:
					_message = str(result.error)
			document.replace(next, "Шаблон стола: " + str(template.title))
			_layout_selected = -1
			window.queue_free()
			_render())
		grid.add_child(card)
	window.close_requested.connect(window.queue_free)
	window.popup_centered()

## Схема раскладки на карточке шаблона: стол 1280×720 в уменьшенном виде, главная кнопка — акцентом.
func _draw_layout_scheme(card: Button, template: Dictionary) -> void:
	var area := Rect2(Vector2(16, 16), Vector2(card.size.x - 32, card.size.y - 72))
	var scale := minf(area.size.x / 1280.0, area.size.y / 720.0)
	var origin := area.position + (area.size - Vector2(1280, 720) * scale) * 0.5
	card.draw_rect(Rect2(origin, Vector2(1280, 720) * scale), Game.bg())
	card.draw_rect(Rect2(origin, Vector2(1280, 48) * scale), Game.panel().darkened(0.1))
	for slot: Dictionary in template.slots:
		var rect := Rect2(origin + Vector2(slot.rect[0], slot.rect[1]) * scale, Vector2(slot.rect[2], slot.rect[3]) * scale)
		var color := Game.accent() if slot.get("main", false) else (Game.panel().lerp(Game.ink(), 0.25) if slot.kind == "zone" else Game.panel().lerp(Game.ink(), 0.12))
		card.draw_rect(rect, color)
		if rect.size.x > 48 and rect.size.y > 14:
			card.draw_string(Style.body_font(), rect.position + Vector2(4, 12), str(slot.title), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 10, Game.ink())
	card.draw_string(Style.head_font(), Vector2(16, card.size.y - 34), str(template.title), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 20, Style.ink())
	var source_game: Dictionary = Templates.LAYOUT_GAMES.get(str(template.id), {})
	var game_line := ("По мотивам «%s» · " % source_game.game) if source_game.has("game") else ""
	card.draw_string(Style.body_font(), Vector2(16, card.size.y - 12), game_line + str(template.hint), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 14, Color(Style.ink(), 0.7))

func _set_background(key: String, value: Variant) -> void:
	var copy: Dictionary = document.data.duplicate(true)
	var look: Dictionary = copy.layout.get("background", {})
	look[key] = value
	copy.layout["background"] = look
	document.replace(copy, "Фон стола")
	_sync_background()
	if is_instance_valid(_layout_props_box):
		_layout_properties.call_deferred(_layout_props_box)

func _import_background(path: String) -> void:
	var imported := Assets.import_image(str(document.data.id), path, _source)
	_message = str(imported.error)
	if not _message.is_empty():
		_status_text()
		return
	var copy: Dictionary = document.data.duplicate(true)
	copy.assets[imported.hash] = imported.asset
	var look: Dictionary = copy.layout.get("background", {})
	look["image"] = imported.hash
	copy.layout["background"] = look
	document.replace(copy, "Картинка фона стола")
	_render()

func _add_layout(kind: String, title: String) -> void:
	var copy := document.data.duplicate(true)
	var items: Array = copy.layout.screens[_screen].items
	var number := 1
	while items.any(func(item: Dictionary): return str(item.get("id", "")) == "%s_%d" % [kind, number]):
		number += 1
	var item := {"kind": "zone" if kind == "hand" else kind, "id": "%s_%d" % [kind, number], "title": title, "visible": ["all"], "rect": [352, 192 + (items.size() % 4) * 64, 320, 96]}
	if kind in ["zone", "hand"]:
		item.merge({"owner": "player" if kind == "hand" else "shared", "view": "fan" if kind == "hand" else "row", "free": true})
		item.rect = [288, 400, 704, 192] if kind == "hand" else [352, 176, 320, 192]
	elif kind == "button":
		item["action"] = item.id
		item.rect[3] = 48
	elif kind == "text":
		item["text"] = "Новый текст"
	elif kind == "counter":
		var vars: Array = copy.rules.get("vars", [])
		item["var"] = str(vars[0].id) if not vars.is_empty() else ""
	elif kind == "players":
		item.rect = [24, 56, 1232, 96]
	elif kind == "self_panel":
		item.rect = [32, 424, 240, 160]
	elif kind == "opponents":
		item.rect = [24, 56, 1232, 112]
	elif kind == "teams":
		item.rect = [32, 176, 256, 192]
	elif kind == "dice_tray":
		item.rect = [32, 176, 1216, 320]
	elif kind == "track":
		item.title = "Поле"
		item.rect = [24, 64, 952, 560]
	elif kind == "board":
		var boards: Array = copy.elements.get("boards", [])
		item["board"] = str(boards[0].id) if not boards.is_empty() else ""
		item.title = "Мой планшет"
		item.rect = [32, 432, 480, 240]
	items.append(item)
	copy.layout["custom"] = true
	document.replace(copy, "Добавить элемент стола")
	_layout_selected = items.size() - 1
	_render()

func _layout_properties(properties: VBoxContainer) -> void:
	Style.clear(properties)
	_clipboard_controls(properties, "layout", ["layout", "screens", _screen, "items"], _layout_selected)
	if _layout_selected < 0 or _layout_selected >= document.data.layout.screens[_screen].items.size():
		properties.add_child(Style.label("Выберите элемент на холсте"))
		_background_properties(properties)
		return
	var item: Dictionary = document.data.layout.screens[_screen].items[_layout_selected]
	var path: Array = ["layout", "screens", _screen, "items", _layout_selected]
	_text(properties, "Название", path + ["title"])
	var conflicts: Dictionary = Definition.layout_conflicts(document.data.layout.screens[_screen].items, Definition.board_zone_ids(document.data))
	if conflicts.bad.has(_layout_selected):
		var reasons: Array[String] = []
		if conflicts.outside.has(_layout_selected):
			reasons.append("выходит за стол")
		for pair: Array in conflicts.pairs:
			if pair.has(_layout_selected):
				var other: int = pair[1] if pair[0] == _layout_selected else pair[0]
				reasons.append("перекрывает «%s»" % Definition.layout_title(document.data.layout.screens[_screen].items[other]))
		if conflicts.mains.size() > 1 and conflicts.mains.has(_layout_selected):
			reasons.append("главных кнопок несколько")
		var warning := Style.label("⚠ " + ", ".join(reasons) + ".")
		warning.name = "LayoutConflict"
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.add_theme_color_override("font_color", Color("e5484d"))
		properties.add_child(warning)
	var rect: Rect2 = _layout_canvas.item_rect(_layout_selected)
	var coordinates := [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var grid := GridContainer.new()
	grid.columns = 2
	properties.add_child(grid)
	for index in 4:
		var col := Style.column(4)
		col.add_child(Style.label(["X", "Y", "Ширина", "Высота"][index]))
		var number := SpinBox.new()
		number.min_value = 48 if index == 1 else (32 if index > 1 else 0)
		number.max_value = 1280 if index in [0, 2] else 720
		number.step = 8
		number.value = float(coordinates[index])
		number.custom_minimum_size.x = 128
		number.value_changed.connect(func(value: float):
			var current: Rect2 = _layout_canvas.item_rect(_layout_selected)
			var next := [current.position.x, current.position.y, current.size.x, current.size.y]
			next[index] = value
			var copy := document.data.duplicate(true)
			copy.layout.screens[_screen].items[_layout_selected]["rect"] = next
			copy.layout["custom"] = true
			document.replace(copy, "Геометрия элемента")
			_status_text())
		col.add_child(number)
		grid.add_child(col)
	var visibility_labels: Array = ["Всем", "Зрителю", "Никому"]
	var anchor_toggle := CheckButton.new()
	anchor_toggle.text = "Якоря окна"
	anchor_toggle.tooltip_text = "Сохранять отступ от края или центра в широком/высоком окне. Координаты задаются для1280×720."
	anchor_toggle.button_pressed = item.get("anchors") is Dictionary
	anchor_toggle.toggled.connect(func(enabled: bool):
		var copy: Dictionary = document.data.duplicate(true)
		var target: Dictionary = copy.layout.screens[_screen].items[_layout_selected]
		if enabled:
			target.anchors = {"x": "center", "y": "top"}
		else:
			target.erase("anchors")
		copy.layout["custom"] = true
		document.replace(copy, "Якоря элемента")
		_render.call_deferred())
	properties.add_child(anchor_toggle)
	if item.get("anchors") is Dictionary:
		_choice(properties, "По горизонтали", path + ["anchors", "x"], ["Слева", "По центру", "Справа", "Растянуть"], ["left", "center", "right", "stretch"])
		_choice(properties, "По вертикали", path + ["anchors", "y"], ["Сверху", "По центру", "Снизу", "Растянуть"], ["top", "center", "bottom", "stretch"])
	var visibility_values: Array = [["all"], ["spectator"], []]
	for role: Dictionary in document.data.rules.get("roles", []):
		visibility_labels.append(str(role.get("name", role.id)))
		visibility_values.append(["role:" + str(role.id)])
	_choice(properties, "Кому виден", path + ["visible"], visibility_labels, visibility_values)
	match str(item.kind):
		"zone" when _screen > 0:
			var shared_note := Style.label("Владелец, вид и правила зоны задаются на общем экране; здесь — только место и подпись.", 13)
			shared_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			shared_note.modulate.a = 0.75
			properties.add_child(shared_note)
		"zone":
			_choice(properties, "Владелец", path + ["owner"], ["Общая", "У каждого игрока", "У команды"], ["shared", "player", "team"])
			_choice(properties, "Вид зоны", path + ["view"], ["Ряд", "Колода", "Сброс", "Рука", "Сетка", "Свободная"], ["row", "pile", "discard", "fan", "grid", "free"])
			var free := CheckButton.new()
			free.text = "Свободное перемещение"
			free.button_pressed = item.get("free", false)
			free.toggled.connect(func(value: bool):
				document.set_value(path + ["free"], value, "Свободная зона")
				_status_text())
			properties.add_child(free)
		"text": _text(properties, "Текст", path + ["text"])
		"board":
			var labels: Array = []
			var values: Array = []
			for board: Dictionary in document.data.elements.get("boards", []):
				labels.append(str(board.get("title", board.id)))
				values.append(str(board.id))
			if not values.is_empty():
				_choice(properties, "Планшет", path + ["board"], labels, values)
				var note := Style.label("Каждый видит свой планшет: свои зоны, ресурсы и рамку своего цвета.")
				note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				note.modulate.a = 0.75
				properties.add_child(note)
			else:
				properties.add_child(Style.label("Создайте планшет во вкладке «Элементы»."))
		"button":
			var main := CheckBox.new()
			main.name = "LayoutButtonMain"
			main.text = "Главная кнопка (яркая)"
			main.tooltip_text = "Главная кнопка на экране одна — обычно снизу по центру. Остальные приглушены."
			main.button_pressed = bool(item.get("main", false))
			main.toggled.connect(func(on: bool):
				document.set_value(path + ["main"], on, "Главная кнопка")
				_render.call_deferred())
			properties.add_child(main)
			var labels: Array = []
			var values: Array = []
			for chain: Dictionary in document.data.rules.get("chains", []):
				var event: Dictionary = chain.get("event", {})
				if event.get("type") == "button" and not values.has(str(event.get("id", ""))):
					var id := str(event.get("id", ""))
					values.append(id)
					labels.append(str(document.data.meta.get("action_titles", {}).get(id, "Действие %d" % values.size())))
			if not values.is_empty():
				_choice(properties, "Действие", path + ["action"], labels, values)
			else:
				var hint := Style.label("Свяжите событие этой кнопки с цепочкой правил во вкладке «Логика».")
				hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				properties.add_child(hint)
		"counter":
			var labels: Array = []
			var values: Array = []
			for resource: Dictionary in document.data.rules.get("vars", []):
				labels.append(str(resource.get("title", resource.id)))
				values.append(str(resource.id))
			if not values.is_empty():
				_choice(properties, "Ресурс", path + ["var"], labels, values)
			else:
				properties.add_child(Style.label("Добавьте ресурс во вкладке «Элементы»."))
		"image":
			var labels: Array = []
			var values: Array = []
			for hash_value: String in document.data.get("assets", {}):
				var asset: Dictionary = document.data.assets[hash_value]
				if str(asset.get("path", "")).begins_with("assets/img/"):
					labels.append(str(asset.get("name", "Картинка %d" % (labels.size() + 1))))
					values.append(hash_value)
			if not values.is_empty():
				_choice(properties, "Изображение", path + ["asset"], labels, values)
			else:
				properties.add_child(Style.label("Сначала импортируйте изображение."))
	var remove := Style.button("Удалить элемент")
	remove.pressed.connect(func():
		var copy := document.data.duplicate(true)
		copy.layout.screens[_screen].items.remove_at(_layout_selected)
		document.replace(copy, "Удалить элемент стола")
		_layout_selected = -1
		_render())
	properties.add_child(remove)

func _logic(tools: VBoxContainer, center: VBoxContainer, properties: VBoxContainer) -> void:
	var logic := Logic.new()
	logic.setup(self, tools, center, properties)

func _elements(tools: VBoxContainer, center: VBoxContainer, properties: VBoxContainer) -> void:
	var face_decks: Array = document.data.elements.get("decks", [])
	if _face_edit and _category in ["decks", "cards"] and not face_decks.is_empty():
		_deck = clampi(_deck, 0, face_decks.size() - 1)
		FaceEditor.new().setup(self, tools, center, properties, _deck)
		return
	var dictionary := CheckBox.new()
	dictionary.text = "Словарь · 1000 слов"
	dictionary.tooltip_text = "Подключить общий словарь ответов к текстовым гнёздам логики."
	dictionary.button_pressed = document.data.rules.get("dictionary", "") == "shared"
	dictionary.toggled.connect(func(on: bool):
		document.set_value(["rules", "dictionary"], "shared" if on else "", "Словарь игры")
		_render.call_deferred())
	tools.add_child(dictionary)
	if dictionary.button_pressed:
		var help := Style.label("Логика → текстовое гнездо → Случайное слово. Сохраните его в текстовую переменную, чтобы всем досталось одно слово.")
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tools.add_child(help)
	for entry: Array in [["decks", "Колоды"], ["cards", "Карты"], ["dice", "Кубики"], ["tokens", "Жетоны"], ["resources", "Ресурсы"], ["boards", "Планшеты"], ["track", "Поле"]]:
		var category := Style.button(entry[1])
		category.name = "EditorCategory_" + entry[0]
		if entry[0] == _category:
			category.add_theme_stylebox_override("normal", Style.box(Style.panel().lerp(Style.accent(), 0.24)))
		category.pressed.connect(func():
			_category = entry[0]
			_deck = 0
			_render())
		tools.add_child(category)
	if _category == "track":
		_track_editor(tools, center, properties)
		return
	if _category not in ["decks", "cards"]:
		_components(tools, center, properties)
		return
	var decks: Array = document.data.elements.get("decks", [])
	# «Карты» — одиночные карты (single), «Колоды» — остальные; индекс _deck общий для обоих списков.
	var singles := _category == "cards"
	var shown: Array = []
	for index in decks.size():
		if bool(decks[index].get("single", false)) == singles:
			shown.append(index)
	if not shown.is_empty() and not shown.has(_deck):
		_deck = shown[0]
	_clipboard_controls(tools, "decks", ["elements", "decks"], _deck)
	tools.add_child(Style.heading("КАРТЫ" if singles else "КОЛОДЫ"))
	for index: int in shown:
		var button := Style.button(str(decks[index].get("title", decks[index].id)))
		if index == _deck:
			button.add_theme_stylebox_override("normal", Style.box(Style.panel().lerp(Style.accent(), 0.24)))
		button.clip_text = true
		button.pressed.connect(func():
			_deck = index
			_render())
		tools.add_child(button)
	var add := Style.button("+ Карта" if singles else "+ Колода")
	add.name = "EditorAddDeck"
	add.pressed.connect(func():
		document.add_deck(singles)
		_deck = document.data.elements.decks.size() - 1
		_render())
	tools.add_child(add)
	if not singles:
		# Наборы (ТЗ 3.5): готовая игральная колода с мастями и лицом «Число и масть».
		for count: int in [36, 52]:
			var standard := Style.button("+ Колода %d карт" % count)
			standard.name = "EditorAddDeck%d" % count
			standard.pressed.connect(func():
				document.add_deck(false)
				var copy: Dictionary = document.data.duplicate(true)
				var index: int = copy.elements.decks.size() - 1
				copy.elements.decks[index] = Templates.playing_deck(copy.elements.decks[index], count)
				document.replace(copy, "Колода %d карт" % count)
				_deck = index
				_render())
			tools.add_child(standard)
	if shown.is_empty():
		center.add_child(Style.heading("ДОБАВЬТЕ ПЕРВУЮ КАРТУ" if singles else "ДОБАВЬТЕ ПЕРВУЮ КОЛОДУ"))
		center.add_child(Style.label("Одна карта на столе: свой текст, рисунок, цвет и размер." if singles else "Один шаблон и таблица с названием, свойствами и числом копий."))
		return
	_deck = clampi(_deck, 0, decks.size() - 1)
	var deck: Dictionary = decks[_deck]
	var face_editor := Style.button("Рамки и слои карты")
	face_editor.tooltip_text = "Редактор лица карты: рамки, фигуры, текст и рисунки на всех картах колоды."
	face_editor.pressed.connect(func():
		_face_edit = true
		_face_layer = -1
		_render.call_deferred())
	tools.add_child(face_editor)
	center.add_child(Style.heading(str(deck.get("title", "КАРТЫ"))))
	if not deck.rows.is_empty():
		var display := Faces.fields(deck.rows[0], deck)
		var card := Style.CardFace.new(display)
		if display.has("layers"):
			var reader = load("res://games/custom/ui/cg_assets.gd").new()
			reader.configure_document(document.data)
			card.layer_reader = reader
		var card_size := Vector2(Definition.CARD_SIZES[clampi(int(deck.get("size", 3)) - 1, 0, Definition.CARD_SIZES.size() - 1)])
		card.custom_minimum_size = card_size * minf(192.0 / card_size.y, 224.0 / card_size.x)
		card.size_flags_horizontal = SIZE_SHRINK_CENTER
		var hash_value := str(display.get("art", ""))
		var asset: Dictionary = document.data.get("assets", {}).get(hash_value, {})
		var path := str(asset.get("path", ""))
		if Package.path_valid(path) and path.begins_with("assets/img/"):
			var bytes := Assets._read(Library.folder(str(document.data.id)) + "/" + path, Package.LIMIT)
			var image := Package.image_from_bytes(bytes, path.get_extension()) if Package.sha(bytes) == hash_value else null
			if image != null:
				card.art_texture = ImageTexture.create_from_image(image)
		var font_hash := str(display.get("font", ""))
		var font_asset: Dictionary = document.data.get("assets", {}).get(font_hash, {})
		var font_path := str(font_asset.get("path", ""))
		if Package.path_valid(font_path) and font_path.begins_with("assets/fonts/"):
			var font_bytes := Assets._read(Library.folder(str(document.data.id)) + "/" + font_path, Package.FONT_LIMIT)
			if Package.sha(font_bytes) == font_hash:
				var font := FontFile.new()
				font.data = font_bytes
				card.custom_font = font
		center.add_child(card)
	if singles:
		_single_fields(center, deck)
	var table := ScrollContainer.new()
	table.size_flags_vertical = SIZE_EXPAND_FILL
	table.size_flags_horizontal = SIZE_EXPAND_FILL
	table.visible = not singles
	center.add_child(table)
	var rows := Style.column(8)
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	table.add_child(rows)
	var fields: Array = []
	var field_types: Dictionary = {}
	for column: Dictionary in deck.get("columns", []):
		fields.append(str(column.id))
		field_types[str(column.id)] = str(column.get("type", "text"))
	if fields.is_empty():
		fields = ["rank"]
	var header_row := Style.row()
	rows.add_child(header_row)
	var number_header := Style.label("№")
	number_header.custom_minimum_size.x = 24
	header_row.add_child(number_header)
	for field: String in fields:
		var label := Style.label(field)
		label.custom_minimum_size.x = 112
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		header_row.add_child(label)
	var copies_header := Style.label("Копий")
	copies_header.custom_minimum_size.x = 128
	header_row.add_child(copies_header)
	for index in deck.rows.size():
		var row := Style.row()
		rows.add_child(row)
		var title := Style.label(str(index + 1))
		title.custom_minimum_size.x = 24
		row.add_child(title)
		for field: String in fields:
			if field_types.get(field) == "color":
				var swatch := ColorPickerButton.new()
				swatch.name = "CardCellColor"
				swatch.custom_minimum_size = Vector2(112, 40)
				swatch.size_flags_horizontal = SIZE_EXPAND_FILL
				swatch.edit_alpha = false
				swatch.color = Color.from_string(str(deck.rows[index].get(field, "#ffffff")), Color.WHITE)
				swatch.popup_closed.connect(func():
					document.set_value(["elements", "decks", _deck, "rows", index, field], "#" + swatch.color.to_html(false), "Цвет карты")
					_render.call_deferred())
				row.add_child(swatch)
				continue
			if field_types.get(field) == "bool":
				var flag := CheckBox.new()
				flag.custom_minimum_size.x = 112
				flag.size_flags_horizontal = SIZE_EXPAND_FILL
				flag.button_pressed = bool(deck.rows[index].get(field, false))
				flag.toggled.connect(func(value: bool):
					document.set_value(["elements", "decks", _deck, "rows", index, field], value, "Свойство карты")
					_status_text())
				row.add_child(flag)
				continue
			var cell := LineEdit.new()
			cell.text = Style.value_text(deck.rows[index].get(field, ""))
			cell.placeholder_text = field
			cell.size_flags_horizontal = SIZE_EXPAND_FILL
			cell.custom_minimum_size.x = 112
			var numeric: bool = field_types.get(field) == "number" or deck.rows[index].get(field) is int or deck.rows[index].get(field) is float
			cell.text_changed.connect(func(text: String):
				if numeric and not text.is_valid_float():
					_message = "В этом поле карты нужно число."
				else:
					_message = ""
					document.set_value(["elements", "decks", _deck, "rows", index, field], float(text) if numeric else text, "Поле карты")
				_status_text())
			row.add_child(cell)
		var copies := SpinBox.new()
		copies.min_value = 1
		copies.max_value = 300
		copies.value = float(deck.rows[index].get("copies", 1))
		copies.custom_minimum_size.x = 80
		copies.value_changed.connect(func(value: float):
			document.set_value(["elements", "decks", _deck, "rows", index, "copies"], int(value), "Копии карты")
			_status_text())
		row.add_child(copies)
		var remove_row := Style.button("×")
		remove_row.tooltip_text = "Удалить строку (можно отменить)"
		remove_row.pressed.connect(func():
			ElementsModel.new(document).remove_row(_deck, index)
			_render.call_deferred())
		row.add_child(remove_row)
	var add_row := Style.button("+ Карта")
	add_row.pressed.connect(func():
		var copy := document.data.duplicate(true)
		var next := {"title": "Новая карта", "copies": 1}
		for field: String in fields:
			var old: Variant = deck.rows[0].get(field) if not deck.rows.is_empty() else ""
			next[field] = 0 if field_types.get(field) == "number" or old is int or old is float else (false if field_types.get(field) == "bool" else ("" if field_types.get(field) == "image" else (str(old) if field_types.get(field) == "color" else "Новая карта")))
		copy.elements.decks[_deck].rows.append(next)
		document.replace(copy, "Добавить карту")
		_render())
	add_row.visible = not singles
	center.add_child(add_row)
	if not deck.has("title"):
		var copy := document.data.duplicate(true)
		copy.elements.decks[_deck].title = str(deck.id)
		document.replace(copy, "Название колоды")
	_text(properties, "Название карты" if singles else "Название колоды", ["elements", "decks", _deck, "title"])
	properties.add_child(Style.label("Размер карты"))
	var sizes := OptionButton.new()
	sizes.name = "EditorCardSize"
	sizes.clip_text = true
	sizes.fit_to_longest_item = false
	for title: String in CARD_SIZE_TITLES:
		sizes.add_item(title)
	sizes.select(clampi(int(deck.get("size", 3)) - 1, 0, Definition.CARD_SIZES.size() - 1))
	sizes.item_selected.connect(func(index: int):
		document.set_value(["elements", "decks", _deck, "size"], index + 1, "Размер карт")
		_render.call_deferred())
	properties.add_child(sizes)
	properties.add_child(Style.label("Цвет карт"))
	var paper := ColorPickerButton.new()
	paper.name = "EditorCardColor"
	paper.custom_minimum_size.y = 40
	paper.edit_alpha = false
	paper.color = Color.from_string(Faces.paper(deck), Color(Faces.PAPER))
	paper.tooltip_text = "Цвет бумаги всех карт. Цвет внутри рамок — в «Рамки и слои карты»."
	paper.popup_closed.connect(func():
		document.set_value(["elements", "decks", _deck, "color"], "#" + paper.color.to_html(false), "Цвет карт")
		_render.call_deferred())
	properties.add_child(paper)
	properties.add_child(Style.label("Чья карта" if singles else "Колода"))
	var owner := OptionButton.new()
	for label: String in ["Одна общая", "Отдельная у каждого игрока", "Отдельная у каждой команды"]:
		owner.add_item(label)
	owner.select(maxi(0, ["shared", "player", "team"].find(str(deck.get("owner", "shared")))))
	owner.item_selected.connect(func(index: int):
		ElementsModel.new(document).set_owner(_deck, ["shared", "player", "team"][index])
		_render.call_deferred())
	properties.add_child(owner)
	var zone_labels: Array = []
	var zone_ids: Array = []
	for screen: Dictionary in document.data.layout.screens:
		for item: Dictionary in screen.get("items", []):
			if item.get("kind") == "zone" and item.get("owner", "shared") == deck.get("owner", "shared"):
				zone_labels.append(str(item.get("title", item.id)))
				zone_ids.append(str(item.id))
	if not zone_ids.is_empty():
		_choice(properties, "Начальная зона", ["elements", "decks", _deck, "zone"], zone_labels, zone_ids)
	var columns_button := Style.button("Свойства карт / колонки")
	columns_button.pressed.connect(_columns_dialog)
	properties.add_child(columns_button)
	if deck.get("face", {}).get("layers") is Array:
		_text_layers(properties, deck)
	else:
		_face_bindings(properties, deck, fields)
	var back_button := Style.button("Импорт рубашки")
	back_button.pressed.connect(func():
		_with_notice(func(): _dialog(PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Рубашка карт"]), false, _import_back)))
	properties.add_child(back_button)
	var back_values: Array = [""]
	var back_labels: Array = ["Стандартная рубашка"]
	for hash_value: String in document.data.get("assets", {}):
		var entry: Dictionary = document.data.assets[hash_value]
		if str(entry.get("path", "")).begins_with("assets/img/"):
			back_values.append(hash_value)
			back_labels.append("Рисунок · " + hash_value.left(8))
	_choice(properties, "Рубашка колоды", ["elements", "decks", _deck, "back"], back_labels, back_values)
	var back_templates := Style.button("Шаблоны рубашек…")
	back_templates.name = "BackTemplates"
	back_templates.tooltip_text = "Рубашки карт из игр сборника и нарисованные узоры."
	back_templates.pressed.connect(_back_templates_dialog)
	properties.add_child(back_templates)
	for item: Array in [["Импорт CSV", _csv_dialog], ["Вставить таблицу", _paste], ["Добавить картинки", _images_dialog], ["Импорт шрифта", _font_dialog]]:
		if singles and item[0] != "Импорт шрифта":
			continue
		var button := Style.button(item[0])
		button.pressed.connect(item[1])
		properties.add_child(button)
	properties.add_child(Style.label("Источник / лицензия ассета"))
	var source := LineEdit.new()
	source.text = _source
	source.text_changed.connect(func(text: String): _source = text)
	properties.add_child(source)
	if not _sheet.is_empty() and document.data.get("assets", {}).has(_sheet):
		properties.add_child(Style.heading("НАРЕЗКА ЛИСТА"))
		var grid := Style.row()
		var controls: Array[SpinBox] = []
		for caption: String in ["Столбцы", "Строки", "Карт"]:
			var col := Style.column(4)
			col.add_child(Style.label(caption))
			var value := SpinBox.new()
			value.min_value = 1
			value.max_value = 300 if caption == "Карт" else 30
			value.value = 4 if caption == "Карт" else 2
			col.add_child(value)
			controls.append(value)
			grid.add_child(col)
		properties.add_child(grid)
		var slice := Style.button("Заменить карты нарезкой")
		slice.pressed.connect(func():
			var result := Assets.grid(str(document.data.id), document.data.assets[_sheet], int(controls[0].value), int(controls[1].value), int(controls[2].value))
			_message = str(result.error)
			if _message.is_empty():
				var copy := document.data.duplicate(true)
				copy.assets.merge(result.assets, true)
				copy.elements.decks[_deck].rows = result.rows
				document.replace(copy, "Нарезать лист карт")
			_render())
		properties.add_child(slice)

func _components(tools: VBoxContainer, center: VBoxContainer, properties: VBoxContainer) -> void:
	var resources := _category == "resources"
	var entries: Array = document.data.rules.get("vars", []) if resources else document.data.elements.get(_category, [])
	_clipboard_controls(tools, "resources" if resources else _category, ["rules", "vars"] if resources else ["elements", _category], _deck)
	var add := Style.button("+ Ресурс" if resources else {"dice": "+ Набор d6", "boards": "+ Планшет"}.get(_category, "+ Жетоны"))
	add.pressed.connect(_add_component)
	tools.add_child(add)
	if _category == "tokens":
		var coins := Style.button("+ Монеты 1 / 5 / 10")
		coins.name = "AddCoins"
		coins.pressed.connect(_add_coins)
		tools.add_child(coins)
		var marks := Style.button("+ Раны и очки")
		marks.name = "AddMarks"
		marks.pressed.connect(func(): _add_set([{"title": "Рана", "value": 1, "color": "#b3261e", "count": 30, "shape": "circle", "show_value": false}, {"title": "Очко", "value": 1, "color": "#e0b84e", "count": 30, "shape": "hex"}]))
		tools.add_child(marks)
	elif _category == "dice":
		var white := Style.button("+ 5 белых d6")
		white.name = "AddWhiteDice"
		white.pressed.connect(func(): _add_set([{"title": "5 белых d6", "count": 5, "color": "#ffffff", "pips": "#202020", "faces": "dots", "visible": "all"}]))
		tools.add_child(white)
	elif _category == "boards":
		var ready := Style.button("+ Планшет с 3 ячейками")
		ready.name = "AddReadyBoard"
		ready.pressed.connect(func():
			_add_component()
			var path: Array = ["elements", "boards", _deck]
			_add_board_cell(path, "zone")
			_add_board_cell(path, "zone")
			_add_board_cell(path, "counter")
			var copy: Dictionary = document.data.duplicate(true)
			var cells: Array = copy.elements.boards[_deck].cells
			cells[0].rect = [0.04, 0.12, 0.44, 0.6]
			cells[1].rect = [0.52, 0.12, 0.44, 0.6]
			cells[2].rect = [0.3, 0.78, 0.4, 0.16]
			document.replace(copy, "Планшет с 3 ячейками")
			_render())
		tools.add_child(ready)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var button := Style.button(str(entry.get("title", entry.id)))
		button.clip_text = true
		button.pressed.connect(func():
			_deck = index
			_render())
		tools.add_child(button)
	if entries.is_empty():
		center.add_child(Style.heading("ДОБАВЬТЕ КОМПОНЕНТ"))
		center.add_child(Style.label("Свободными компонентами игроки управляют без цепочек правил."))
		return
	_deck = clampi(_deck, 0, entries.size() - 1)
	var entry: Dictionary = entries[_deck]
	var path: Array = ["rules", "vars", _deck] if resources else ["elements", _category, _deck]
	if not entry.has("title"):
		document.set_value(path + ["title"], str(entry.id), "Название компонента")
		_render.call_deferred()
		return
	center.add_child(Style.heading(str(entry.title)))
	_text(properties, "Название", path + ["title"])
	if resources and entry.get("type", "number") != "number":
		center.add_child(Style.label("Эта переменная не является числовым ресурсом."))
		return
	if resources:
		_number(properties, "Начальное количество", path + ["init"], -999999, 999999)
		_choice(properties, "У кого ресурс", path + ["scope"], ["У каждого игрока", "Общий", "У команды"], ["player", "shared", "team"])
		_choice(properties, "Кому виден", path + ["visible"], ["Всем", "Владельцу"], ["all", "owner"])
		center.add_child(Style.heading("%s: %s" % [entry.title, Style.value_text(entry.get("init", 0))], 32))
	elif _category == "dice":
		_number(properties, "Кубиков в наборе", path + ["count"], 1, 30)
		_choice(properties, "Кому виден результат", path + ["visible"], ["Всем", "Бросавшему"], ["all", "owner"])
		center.add_child(Style.label("В игре нажмите «Бросить», потяните кубик и отпустите. Результат выбирает хост."))
		var sides_menu := OptionButton.new()
		sides_menu.name = "DiceSides"
		var sides_values := [4, 6, 8, 10, 12, 20]
		for value: int in sides_values:
			sides_menu.add_item("d%d" % value)
		sides_menu.select(maxi(0, sides_values.find(int(entry.get("sides", 6)))))
		sides_menu.item_selected.connect(func(index: int):
			var copy: Dictionary = document.data.duplicate(true)
			var target: Dictionary = copy.elements.dice[int(path[2])]
			target["sides"] = sides_values[index]
			# У d4–d20 грани только цифрами.
			if sides_values[index] != 6:
				target["faces"] = "numbers"
			document.replace(copy, "Граней у кубиков")
			_render.call_deferred())
		properties.add_child(Style.label("Граней"))
		properties.add_child(sides_menu)
		_dice_look(properties, center, entry, path)
		var die := TossDie.new()
		die.use_player_style = false
		die.allow_polyhedral = true
		die.max_face = int(entry.get("sides", 6))
		var reader = load("res://games/custom/ui/cg_assets.gd").new()
		reader.configure_document(document.data)
		Style.style_die(die._die, entry, reader, Net.color_of(0))
		die.position = Vector2(160, 120)
		die.home = Vector2(192, 152)
		die.area = Rect2(0, 0, 480, 288)
		die.draggable = true
		var preview := Control.new()
		preview.custom_minimum_size = Vector2(400, 300)
		center.add_child(preview)
		preview.add_child(die)
		die.wait_for_roll()
		die.thrown.connect(func(_vel: Vector2): die.set_result(randi_range(1, int(entry.get("sides", 6)))))
		die.name = "DicePreview"
	elif _category == "boards":
		_board_properties(properties, center, entry, path)
		return
	else:
		_token_properties(properties, center, entry, path)
	var free := CheckButton.new()
	free.text = "Свободное управление"
	free.button_pressed = bool(entry.get("free", false))
	free.toggled.connect(func(value: bool):
		document.set_value(path + ["free"], value, "Ручное управление")
		_status_text())
	properties.add_child(free)

## «Поле»: поле-ходилка — картинка, клетки по порядку (щелчок по картинке), метки клеток, кольцо, старт.
## Фишки игроков двигают блоки логики «Сдвинуть фишку» / «Поставить фишку на клетку».
var _track_cell := -1

func _track_editor(tools: VBoxContainer, center: VBoxContainer, properties: VBoxContainer) -> void:
	var track: Variant = document.data.elements.get("track")
	center.add_child(Style.heading("ПОЛЕ-ХОДИЛКА"))
	if not track is Dictionary:
		var hint := Style.label("Поле с дорожкой клеток и фишками игроков: картинка поля, клетки по порядку, метки («финиш», «бонус»). Фишки двигают блоки логики «Сдвинуть фишку» и «Поставить фишку на клетку».")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		center.add_child(hint)
		var create := Style.primary("Создать поле")
		create.name = "TrackCreate"
		create.pressed.connect(func():
			var copy: Dictionary = document.data.duplicate(true)
			copy.elements["track"] = {"image": "", "cells": [], "loop": false, "start": 0}
			if copy.layout.screens.is_empty():
				copy.layout.screens.append({"id": "main", "items": []})
			if not copy.layout.screens[0].items.any(func(item: Dictionary): return item.get("kind") == "track"):
				copy.layout.screens[0].items.append({"kind": "track", "id": "track_view", "title": "Поле", "visible": ["all"], "rect": [24, 64, 952, 560]})
				copy.layout["custom"] = true
			document.replace(copy, "Создать поле")
			_render())
		center.add_child(create)
		return
	var cells: Array = track.get("cells", [])
	_track_cell = clampi(_track_cell, -1, cells.size() - 1)
	var reader = load("res://games/custom/ui/cg_assets.gd").new()
	reader.configure_document(document.data)
	var preview := TrackPreview.new()
	preview.name = "TrackPreview"
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.track = track.duplicate(true)
	preview.selection = _track_cell
	preview.texture = reader.image(str(track.get("image", ""))) if not str(track.get("image", "")).is_empty() else null
	preview.added.connect(func(pos: Array):
		var copy: Dictionary = document.data.duplicate(true)
		copy.elements.track.cells.append({"pos": pos, "tag": ""})
		document.replace(copy, "Клетка поля")
		_track_cell = copy.elements.track.cells.size() - 1
		_render())
	preview.picked.connect(func(index: int):
		_track_cell = index
		_render.call_deferred())
	preview.moved.connect(func(index: int, pos: Array): document.set_value(["elements", "track", "cells", index, "pos"], pos, "Подвинуть клетку"))
	preview.removed.connect(func(index: int):
		var copy: Dictionary = document.data.duplicate(true)
		copy.elements.track.cells.remove_at(index)
		copy.elements.track["start"] = clampi(int(copy.elements.track.get("start", 0)), 0, maxi(0, copy.elements.track.cells.size() - 1))
		document.replace(copy, "Убрать клетку")
		_track_cell = -1
		_render())
	center.add_child(preview)
	var help := Style.label("Щелчок — новая клетка в конец дорожки, перетащить — подвинуть, правый щелчок — убрать. Оранжевая — старт. Клеток: %d." % cells.size(), 13)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate.a = 0.8
	center.add_child(help)
	# Свойства: картинка, кольцо, старт, метка выбранной клетки.
	properties.add_child(Style.label("Картинка поля"))
	var hashes: Array = [""]
	var labels: Array = ["Без картинки"]
	for hash_value: String in document.data.get("assets", {}):
		var asset: Dictionary = document.data.assets[hash_value]
		if str(asset.get("path", "")).begins_with("assets/img/"):
			hashes.append(hash_value)
			labels.append(str(asset.get("name", hash_value.left(8))).get_file())
	var image := OptionButton.new()
	image.name = "TrackImage"
	image.clip_text = true
	image.fit_to_longest_item = false
	for caption: String in labels:
		image.add_item(caption)
	image.select(maxi(0, hashes.find(str(track.get("image", "")))))
	image.item_selected.connect(func(index: int):
		document.set_value(["elements", "track", "image"], hashes[index], "Картинка поля")
		_render.call_deferred())
	properties.add_child(image)
	var upload := Style.button("Загрузить картинку поля")
	upload.pressed.connect(func():
		_with_notice(func(): _dialog(PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Поле"]), false, func(file: String):
			var imported := Assets.import_image(str(document.data.id), file, _source)
			_message = str(imported.error)
			if _message.is_empty():
				var copy: Dictionary = document.data.duplicate(true)
				copy.assets[imported.hash] = imported.asset
				copy.elements.track["image"] = imported.hash
				document.replace(copy, "Картинка поля")
			_render())))
	properties.add_child(upload)
	var loop := CheckBox.new()
	loop.name = "TrackLoop"
	loop.text = "Кольцо (после последней клетки — снова первая)"
	loop.button_pressed = bool(track.get("loop", false))
	loop.toggled.connect(func(on: bool):
		document.set_value(["elements", "track", "loop"], on, "Кольцо поля")
		_render.call_deferred())
	properties.add_child(loop)
	if cells.is_empty():
		return
	properties.add_child(Style.label("Старт — клетка №"))
	var start := SpinBox.new()
	start.name = "TrackStart"
	start.min_value = 0
	start.max_value = cells.size() - 1
	start.value = int(track.get("start", 0))
	start.value_changed.connect(func(value: float):
		document.set_value(["elements", "track", "start"], int(value), "Старт поля")
		_render.call_deferred())
	properties.add_child(start)
	if _track_cell >= 0:
		properties.add_child(Style.heading("КЛЕТКА %d" % _track_cell))
		properties.add_child(Style.label("Метка (для условий логики)"))
		var tag := LineEdit.new()
		tag.name = "TrackTag"
		tag.max_length = 32
		tag.placeholder_text = "например: финиш, бонус, ловушка"
		tag.text = str(cells[_track_cell].get("tag", ""))
		var index := _track_cell
		tag.text_submitted.connect(func(text: String):
			document.set_value(["elements", "track", "cells", index, "tag"], text.strip_edges(), "Метка клетки")
			_render.call_deferred())
		tag.focus_exited.connect(func():
			if tag.text.strip_edges() != str(document.data.elements.track.cells[index].get("tag", "")):
				document.set_value(["elements", "track", "cells", index, "tag"], tag.text.strip_edges(), "Метка клетки"))
		properties.add_child(tag)

## Планшет игрока: картинка, рамка цвета игрока, ячейки — личные зоны и счётчики ресурсов.
## Ячейки двигаются мышью на просмотре; новая ячейка-зона сама создаёт личную зону стола.
func _board_properties(properties: VBoxContainer, center: VBoxContainer, entry: Dictionary, path: Array) -> void:
	_token_image(properties, entry, path, "image", "Картинка планшета")
	var frame := CheckBox.new()
	frame.name = "BoardFrame"
	frame.text = "Рамка цвета игрока"
	frame.button_pressed = entry.get("frame", "player") == "player"
	frame.toggled.connect(func(on: bool):
		document.set_value(path + ["frame"], "player" if on else "none", "Рамка планшета")
		_render.call_deferred())
	properties.add_child(frame)
	properties.add_child(Style.heading("ЯЧЕЙКИ"))
	var add_zone := Style.button("+ Зона на планшете")
	add_zone.name = "BoardAddZone"
	add_zone.pressed.connect(func(): _add_board_cell(path, "zone"))
	properties.add_child(add_zone)
	var add_counter := Style.button("+ Счётчик ресурса")
	add_counter.name = "BoardAddCounter"
	add_counter.pressed.connect(func(): _add_board_cell(path, "counter"))
	properties.add_child(add_counter)
	var cells: Array = entry.get("cells", [])
	var zone_labels: Array = []
	var zone_values: Array = []
	var layout_items: Array = document.data.layout.screens[0].get("items", []) if not document.data.layout.screens.is_empty() else []
	for item: Dictionary in layout_items:
		if item.get("kind") == "zone":
			zone_labels.append(str(item.get("title", item.id)))
			zone_values.append(str(item.id))
	var var_labels: Array = []
	var var_values: Array = []
	for v: Dictionary in document.data.rules.get("vars", []):
		if v.get("scope", "shared") == "player":
			var_labels.append(str(v.get("title", v.id)))
			var_values.append(str(v.id))
	for index in cells.size():
		var cell: Dictionary = cells[index]
		var cell_path: Array = path + ["cells", index]
		var counter: bool = cell.get("kind") == "counter"
		properties.add_child(Style.label("%d. %s" % [index + 1, "Счётчик" if counter else "Зона"]))
		if counter:
			_choice(properties, "Ресурс", cell_path + ["ref"], var_labels, var_values)
			_text(properties, "Подпись", cell_path + ["title"])
		else:
			_choice(properties, "Зона", cell_path + ["ref"], zone_labels, zone_values)
		var remove := Style.button("Убрать ячейку")
		remove.pressed.connect(func():
			var copy: Dictionary = document.data.duplicate(true)
			copy.elements.boards[int(path[2])].cells.remove_at(index)
			document.replace(copy, "Убрать ячейку планшета")
			_render())
		properties.add_child(remove)
	var reader = load("res://games/custom/ui/cg_assets.gd").new()
	reader.configure_document(document.data)
	var preview := BoardPreview.new()
	preview.name = "BoardPreview"
	preview.board = entry.duplicate(true)
	preview.texture = reader.image(str(entry.get("image", ""))) if not str(entry.get("image", "")).is_empty() else null
	preview.tint = Net.color_of(0) if entry.get("frame", "player") == "player" else Color.TRANSPARENT
	preview.cell_changed.connect(func(index: int, rect: Array): document.set_value(path + ["cells", index, "rect"], rect, "Ячейка планшета"))
	center.add_child(preview)
	var help := Style.label("Перетащите ячейку мышью, уголок справа снизу — размер. Каждый игрок видит на столе свой планшет: карты его зон лежат прямо на нём, рамка — его цвета.")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(help)

## Новая ячейка: зона — новая личная зона стола «у каждого игрока»; счётчик — первый личный ресурс (или новый).
func _add_board_cell(path: Array, kind: String) -> void:
	var copy: Dictionary = document.data.duplicate(true)
	var board: Dictionary = copy.elements.boards[int(path[2])]
	var cells: Array = board.get("cells", [])
	var offset := 0.06 * (cells.size() % 6)
	var cell := {"kind": kind, "rect": [0.05 + offset, 0.1 + offset, 0.4, 0.4] if kind == "zone" else [0.6 + offset * 0.5, 0.05 + offset, 0.3, 0.16]}
	if kind == "zone":
		if copy.layout.screens.is_empty():
			copy.layout.screens.append({"id": "main", "items": []})
		var items: Array = copy.layout.screens[0].items
		var number := 1
		while items.any(func(item: Dictionary): return str(item.get("id", "")) == "board_zone_%d" % number):
			number += 1
		items.append({"kind": "zone", "id": "board_zone_%d" % number, "title": "Зона планшета %d" % number, "owner": "player", "view": "row", "free": true, "visible": ["all"], "rect": [544, 432, 320, 192]})
		cell["ref"] = "board_zone_%d" % number
	else:
		var vars: Array = copy.rules.get("vars", [])
		var found := ""
		var caption := "Ресурс"
		for v: Dictionary in vars:
			if v.get("scope", "shared") == "player" and v.get("type", "number") == "number":
				found = str(v.id)
				caption = str(v.get("title", v.id))
				break
		if found.is_empty():
			var number := 1
			while vars.any(func(v: Dictionary): return str(v.id) == "resource_%d" % number):
				number += 1
			found = "resource_%d" % number
			vars.append({"id": found, "title": "Ресурс", "type": "number", "scope": "player", "init": 0, "visible": "all", "free": true})
			copy.rules["vars"] = vars
		cell["ref"] = found
		cell["title"] = caption
	cells.append(cell)
	board["cells"] = cells
	document.replace(copy, "Ячейка планшета")
	_render()

## Жетоны и монеты: количество (или без ограничения), номинал, форма, цвет (свой / игрока / команды),
## картинка лица, оборот. Просмотр — лицо и оборот рядом.
func _token_properties(properties: VBoxContainer, center: VBoxContainer, entry: Dictionary, path: Array) -> void:
	_number(properties, "Количество", path + ["count"], 1, 300)
	var unlimited := CheckBox.new()
	unlimited.name = "TokenUnlimited"
	unlimited.text = "Без ограничения"
	unlimited.tooltip_text = "Взяли последний из запаса — там появляется новый."
	unlimited.button_pressed = bool(entry.get("unlimited", false))
	unlimited.toggled.connect(func(on: bool): document.set_value(path + ["unlimited"], on, "Жетоны без ограничения"))
	properties.add_child(unlimited)
	if int(entry.get("count", 1)) >= 20 or bool(entry.get("unlimited", false)):
		var hint := Style.label("Для подсчёта очков или денег удобнее ресурс — число у игрока (группа «Ресурсы»), а не горсть жетонов.")
		hint.name = "TokenResourceHint"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.modulate.a = 0.75
		properties.add_child(hint)
	_number(properties, "Номинал", path + ["value"], 0, 999999)
	var show_value := CheckBox.new()
	show_value.name = "TokenShowValue"
	show_value.text = "Писать номинал на жетоне"
	show_value.button_pressed = bool(entry.get("show_value", true))
	show_value.toggled.connect(func(on: bool):
		document.set_value(path + ["show_value"], on, "Номинал на жетоне")
		_render.call_deferred())
	properties.add_child(show_value)
	_choice(properties, "Форма", path + ["shape"], ["Круг", "Квадрат", "Шестиугольник", "Своя картинка"], ["circle", "square", "hex", "image"])
	properties.add_child(Style.label("Цвет"))
	var modes := ["own", "player", "team"]
	var current := str(entry.get("color", "#65cfcc"))
	var mode := current if current in ["player", "team"] else "own"
	var owner := OptionButton.new()
	owner.name = "TokenColorMode"
	for caption: String in ["Свой цвет", "Цвет игрока", "Цвет команды"]:
		owner.add_item(caption)
	owner.select(modes.find(mode))
	owner.item_selected.connect(func(index: int):
		document.set_value(path + ["color"], "#65cfcc" if index == 0 else modes[index], "Цвет жетона")
		_render.call_deferred())
	properties.add_child(owner)
	if mode == "own":
		var picker := ColorPickerButton.new()
		picker.name = "TokenColor"
		picker.custom_minimum_size.y = 40
		picker.edit_alpha = false
		picker.color = Color.from_string(current, Color("65cfcc"))
		picker.popup_closed.connect(func():
			document.set_value(path + ["color"], "#" + picker.color.to_html(false), "Цвет жетона")
			_render.call_deferred())
		properties.add_child(picker)
	else:
		var note := Style.label("Каждому %s свой набор жетонов в его цвете: %d шт. на %s." % ["игроку" if mode == "player" else "команде", int(entry.get("count", 1)), "игрока" if mode == "player" else "команду"])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.modulate.a = 0.75
		properties.add_child(note)
	_token_image(properties, entry, path, "image", "Картинка лица")
	var two_sided := CheckBox.new()
	two_sided.name = "TokenTwoSided"
	two_sided.text = "Двусторонний (можно перевернуть)"
	two_sided.button_pressed = bool(entry.get("two_sided", false))
	two_sided.toggled.connect(func(on: bool):
		document.set_value(path + ["two_sided"], on, "Двусторонний жетон")
		_render.call_deferred())
	properties.add_child(two_sided)
	if bool(entry.get("two_sided", false)):
		_token_image(properties, entry, path, "back", "Картинка оборота")
		var back_number := CheckBox.new()
		back_number.name = "TokenBackValue"
		back_number.text = "Свой номинал на обороте"
		back_number.button_pressed = entry.has("back_value")
		back_number.toggled.connect(func(on: bool):
			var copy: Dictionary = document.data.duplicate(true)
			var target: Dictionary = copy.elements.tokens[int(path[2])]
			if on:
				target["back_value"] = target.get("value", 1)
			else:
				target.erase("back_value")
			document.replace(copy, "Номинал оборота")
			_render.call_deferred())
		properties.add_child(back_number)
		if entry.has("back_value"):
			_number(properties, "Номинал оборота", path + ["back_value"], 0, 999999)
	# Просмотр: лицо (и оборот) крупно, в цвете первого игрока, если цвет по игроку.
	var reader = load("res://games/custom/ui/cg_assets.gd").new()
	reader.configure_document(document.data)
	var tint := Net.color_of(0) if mode != "own" else Color.TRANSPARENT
	var row := HBoxContainer.new()
	row.name = "TokenPreview"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	var sides: Array = [false, true] if bool(entry.get("two_sided", false)) else [false]
	for flipped: bool in sides:
		var data: Dictionary = entry.duplicate(true)
		if flipped:
			data["flipped"] = true
			if data.has("back_value"):
				data["value"] = data.back_value
		var side := VBoxContainer.new()
		var token := Style.TokenFace.new(data, reader, tint)
		token.custom_minimum_size = Vector2(192, 192)
		side.add_child(token)
		if sides.size() > 1:
			var caption := Style.label("Оборот" if flipped else "Лицо")
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			side.add_child(caption)
		row.add_child(side)
	center.add_child(row)
	center.add_child(Style.label("Жетоны появятся на столе. Переносите их в свободные зоны%s." % (", двусторонние переворачивайте" if bool(entry.get("two_sided", false)) else "")))

## Выбор картинки лица/оборота жетона из загруженных или загрузка новой.
func _token_image(properties: VBoxContainer, entry: Dictionary, path: Array, key: String, caption: String) -> void:
	properties.add_child(Style.label(caption))
	var hashes: Array = [""]
	var labels: Array = ["Без картинки"]
	for hash_value: String in document.data.get("assets", {}):
		var asset: Dictionary = document.data.assets[hash_value]
		if str(asset.get("path", "")).begins_with("assets/img/"):
			hashes.append(hash_value)
			var name_text := str(asset.get("name", asset.get("source", ""))).get_file()
			labels.append(name_text if not name_text.is_empty() else "Рисунок · " + hash_value.left(8))
	var menu := OptionButton.new()
	menu.name = "TokenImage_" + key
	menu.clip_text = true
	menu.fit_to_longest_item = false
	for label: String in labels:
		menu.add_item(label)
	menu.select(maxi(0, hashes.find(str(entry.get(key, "")))))
	menu.item_selected.connect(func(index: int):
		document.set_value(path + [key], hashes[index], caption)
		_render.call_deferred())
	properties.add_child(menu)
	var upload := Style.button("Загрузить…")
	upload.pressed.connect(func():
		_with_notice(func(): _dialog(PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; " + caption]), false, func(file: String): _import_token_image(file, path, key))))
	properties.add_child(upload)

func _import_token_image(file: String, path: Array, key: String) -> void:
	var imported := Assets.import_image(str(document.data.id), file, _source)
	_message = str(imported.error)
	if not _message.is_empty():
		_status_text()
		return
	var copy: Dictionary = document.data.duplicate(true)
	copy.assets[imported.hash] = imported.asset
	copy.elements[str(path[1])][int(path[2])][key] = imported.hash
	document.replace(copy, "Картинка элемента")
	_render()

## Набор компонентов текущей группы (кубики/жетоны): каждый — как «+», затем свои поля.
func _add_set(entries: Array) -> void:
	for fields: Dictionary in entries:
		_add_component()
		var copy: Dictionary = document.data.duplicate(true)
		copy.elements[_category][_deck].merge(fields, true)
		document.replace(copy, str(fields.title))
	_render()

## Готовый набор монет 1, 5 и 10 в общей зоне «Стол».
func _add_coins() -> void:
	for spec: Array in [[1, "#d9a441", 10], [5, "#b8c4cc", 6], [10, "#e0b84e", 4]]:
		_add_component()
		var copy: Dictionary = document.data.duplicate(true)
		var entry: Dictionary = copy.elements.tokens[_deck]
		entry.merge({"title": "Монета %d" % spec[0], "value": spec[0], "color": spec[1], "count": spec[2], "shape": "circle"}, true)
		document.replace(copy, "Монеты %d" % spec[0])
	_render()

## Вид набора кубиков: цвет корпуса и точек, грани точками / цифрами / своими картинками.
func _dice_look(properties: VBoxContainer, center: VBoxContainer, entry: Dictionary, path: Array) -> void:
	properties.add_child(Style.heading("ВИД КУБИКОВ"))
	properties.add_child(Style.label("Цвет кубика"))
	var owner_modes := ["own", "player", "team"]
	var current := str(entry.get("color", "#f3ead2"))
	var owner_mode := current if current in ["player", "team"] else "own"
	var owner := OptionButton.new()
	owner.name = "DiceColorMode"
	for caption: String in ["Свой цвет", "Цвет игрока", "Цвет команды"]:
		owner.add_item(caption)
	owner.select(owner_modes.find(owner_mode))
	owner.item_selected.connect(func(index: int):
		document.set_value(path + ["color"], "#f3ead2" if index == 0 else owner_modes[index], "Цвет кубика")
		_render.call_deferred())
	properties.add_child(owner)
	if owner_mode != "own":
		var note := Style.label("У каждого свой: цвет игрока из пати%s. В просмотре — пример." % ("" if owner_mode == "player" else ", у команды — цвет её первого игрока"))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.modulate.a = 0.75
		properties.add_child(note)
	for item: Array in [["color", "", "#f3ead2"], ["pips", "Цвет точек и цифр", "#7a1414"]]:
		if item[0] == "color" and owner_mode != "own":
			continue
		if not str(item[1]).is_empty():
			properties.add_child(Style.label(item[1]))
		var picker := ColorPickerButton.new()
		picker.name = "DiceColor_" + item[0]
		picker.custom_minimum_size.y = 40
		picker.edit_alpha = false
		picker.color = Color.from_string(str(entry.get(item[0], item[2])), Color(item[2]))
		picker.popup_closed.connect(func():
			document.set_value(path + [item[0]], "#" + picker.color.to_html(false), "Цвет кубика" if item[0] == "color" else str(item[1]))
			_render.call_deferred())
		properties.add_child(picker)
	properties.add_child(Style.label("Грани"))
	var faces := OptionButton.new()
	faces.name = "DiceFaces"
	for caption: String in ["Точки", "Цифры", "Свои картинки"]:
		faces.add_item(caption)
	var modes := ["dots", "numbers", "images"]
	faces.select(maxi(0, modes.find(str(entry.get("faces", "dots")))))
	faces.item_selected.connect(func(index: int):
		document.set_value(path + ["faces"], modes[index], "Грани кубиков")
		_render.call_deferred())
	properties.add_child(faces)
	if entry.get("faces", "dots") != "images":
		return
	var hashes: Array = [""]
	var labels: Array = ["Точки (как обычно)"]
	for hash_value: String in document.data.get("assets", {}):
		var asset: Dictionary = document.data.assets[hash_value]
		if str(asset.get("path", "")).begins_with("assets/img/"):
			hashes.append(hash_value)
			var caption := str(asset.get("name", asset.get("source", ""))).get_file()
			labels.append(caption if not caption.is_empty() else "Рисунок · " + hash_value.left(8))
	var images: Array = entry.get("images", []).duplicate()
	images.resize(6)
	for face in 6:
		properties.add_child(Style.label("Грань %d" % (face + 1)))
		var menu := OptionButton.new()
		menu.name = "DiceFaceImage%d" % (face + 1)
		menu.clip_text = true
		menu.fit_to_longest_item = false
		for label: String in labels:
			menu.add_item(label)
		menu.select(maxi(0, hashes.find(str(images[face]) if images[face] != null else "")))
		menu.item_selected.connect(func(index: int):
			var next: Array = images.map(func(value: Variant): return "" if value == null else str(value))
			next[face] = hashes[index]
			document.set_value(path + ["images"], next, "Картинка грани")
			_render.call_deferred())
		properties.add_child(menu)
	var import_button := Style.button("Добавить картинки граней")
	import_button.tooltip_text = "Импортируйте PNG/JPG, затем выберите картинку для каждой грани."
	import_button.pressed.connect(func():
		_with_notice(func(): _dialog(PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Грани кубика"]), true, _import_dice_images.bind(path))))
	properties.add_child(import_button)
	if hashes.size() == 1:
		var note := Style.label("Сначала добавьте картинки — кнопка ниже.")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		center.add_child(note)

func _clipboard_entries(path: Array) -> Array:
	var entries: Variant = document.data
	for key: Variant in path:
		if entries is Dictionary:
			entries = entries.get(key, [])
		elif entries is Array and key is int and key >= 0 and key < entries.size():
			entries = entries[key]
		else:
			return []
	return entries if entries is Array else []

func _clipboard_controls(parent: Node, kind: String, path: Array, index: int, paste_path: Array = []) -> void:
	var clipboard: GDScript = load("res://editor/ed_clipboard.gd")
	var entries: Array = _clipboard_entries(path)
	var row := Style.column(8)
	parent.add_child(row)
	var copy := Style.button("Копировать")
	if kind in ["chain", "block"]:
		copy.tooltip_text = "Копируется вся вложенная структура. Ссылки на зоны и ресурсы сохраняются."
	copy.disabled = index < 0 or index >= entries.size()
	copy.pressed.connect(func():
		# Поле свойства могло заменить document.data после отрисовки этой кнопки.
		var current: Array = _clipboard_entries(path)
		if index < 0 or index >= current.size():
			_message = "Выбранный элемент больше не существует."
			_status_text()
			return
		var text: String = clipboard.encode(document, kind, current[index])
		if text.is_empty():
			_message = "Не удалось скопировать: ассет недоступен или размер больше 16 МБ."
		else:
			DisplayServer.clipboard_set(text)
			_message = "Элемент скопирован в буфер обмена."
		_status_text())
	row.add_child(copy)
	var paste := Style.button("Вставить")
	if kind in ["chain", "block"]:
		paste.tooltip_text = "Для вставки в другую игру нужны зоны, ресурсы и кнопки с теми же именами."
	paste.pressed.connect(func():
		var payload: Dictionary = clipboard.decode(DisplayServer.clipboard_get())
		var destination: Array = path if paste_path.is_empty() else paste_path
		var result: String = clipboard.paste(document, payload, kind, destination)
		if result.is_empty() and kind == "chain":
			_logic_chain = document.data.rules.chains.size() - 1
			_logic_path = []
			_logic_target = []
			_logic_phase = ""
		elif result.is_empty() and kind == "block":
			var entries_after: Variant = document.data
			for key: Variant in destination:
				entries_after = entries_after[key]
			_logic_chain = int(destination[2])
			_logic_target = destination.duplicate()
			_logic_path = destination + [entries_after.size() - 1]
		elif result.is_empty() and kind == "face_layer":
			_face_layer = document.data.elements.decks[_deck].face.layers.size() - 1
		_message = "Элемент вставлен." if result.is_empty() else result
		_render.call_deferred())
	row.add_child(paste)

func _choice(parent: Node, caption: String, path: Array, labels: Array, values: Array) -> void:
	parent.add_child(Style.label(caption))
	var target: Variant = document.data
	for key: Variant in path.slice(0, path.size() - 1):
		target = target[key]
	var selected: Variant = target.get(path.back(), values[0])
	var choice := OptionButton.new()
	for text: String in labels:
		choice.add_item(text)
	choice.select(maxi(0, values.find(selected)))
	choice.item_selected.connect(func(index: int):
		document.set_value(path, values[index], caption)
		_render.call_deferred())
	parent.add_child(choice)

func _add_component() -> void:
	var copy := document.data.duplicate(true)
	var resources := _category == "resources"
	var entries: Array = copy.rules.get("vars", []) if resources else copy.elements.get(_category, [])
	var prefix: String = "resource" if resources else {"dice": "dice", "boards": "board"}.get(_category, "token")
	var number := 1
	while entries.any(func(entry: Dictionary): return str(entry.id) == "%s_%d" % [prefix, number]):
		number += 1
	var entry := {"id": "%s_%d" % [prefix, number], "free": true}
	if resources:
		entry.merge({"title": "Ресурс", "type": "number", "scope": "player", "init": 0, "visible": "all"})
	elif _category == "dice":
		entry.merge({"title": "Набор d6", "count": 3, "visible": "owner"})
	elif _category == "boards":
		entry.erase("free")
		entry.merge({"title": "Планшет", "image": "", "frame": "player", "cells": []})
		# Сразу кладём планшет на стол — «Интерфейс», снизу слева.
		if copy.layout.screens.is_empty():
			copy.layout.screens.append({"id": "main", "items": []})
		copy.layout.screens[0].items.append({"kind": "board", "id": "board_view_%d" % number, "title": "Мой планшет", "board": entry.id, "visible": ["all"], "rect": [32, 432, 480, 240]})
		copy.layout["custom"] = true
	else:
		entry.merge({"title": "Жетон", "count": 5, "value": 1, "shape": "circle", "zone": "table"})
		if copy.layout.screens.is_empty():
			copy.layout.screens.append({"id": "main", "items": []})
		var has_table := false
		for screen: Dictionary in copy.layout.screens:
			for item: Dictionary in screen.get("items", []):
				has_table = has_table or item.get("kind") == "zone" and item.get("id") == "table"
		if not has_table:
			copy.layout.screens[0].items.append({"kind": "zone", "id": "table", "title": "Стол", "owner": "shared", "view": "row", "free": true})
	entries.append(entry)
	if resources:
		copy.rules.vars = entries
	else:
		copy.elements[_category] = entries
	document.replace(copy, "Добавить компонент")
	_deck = entries.size() - 1
	_render()

func _status_text() -> void:
	if not is_instance_valid(_status):
		return
	var errors: Array = document.issues().errors
	_status.text = _message if not _message.is_empty() else ("Есть изменения" if document.dirty else ("Черновик сохранён" if document.draft else "Сохранено"))
	if _message.is_empty() and not _tab_tip.is_empty():
		_status.text = _tab_tip
	var lesson_status: String = TutorialUI.status(self)
	if _message.is_empty() and not lesson_status.is_empty() and _tab != 4:
		_status.text = lesson_status
	if is_instance_valid(_help_done):
		_help_done.visible = _message.is_empty() and not _tab_tip.is_empty()
	_status.text += " · Ошибок: %d" % errors.size()
	var warnings: Array = document.issues().warnings
	if not warnings.is_empty():
		_status.text += " · Предупреждений: %d" % warnings.size()
	if is_instance_valid(_undo_button):
		_undo_button.disabled = document.undo_stack.is_empty()
	if is_instance_valid(_redo_button):
		_redo_button.disabled = document.redo_stack.is_empty()
	if _tab == 1 and is_instance_valid(_layout_canvas) and _screen < document.data.layout.get("screens", []).size():
		_layout_canvas.items = document.data.layout.screens[_screen].get("items", []).duplicate(true)
		_layout_canvas.queue_redraw()
	if _tab == 0 and is_instance_valid(_box_view):
		_box_view.refresh()

func _save() -> bool:
	if not document.data.has("box"):
		var copy: Dictionary = document.data.duplicate(true)
		copy.box = {"template": "square", "thickness": 0.06, "faces": {}}
		document.replace(copy, "Добавить коробку проекта")
	var signature := JSON.stringify({"id": document.data.get("id"), "title": document.data.get("meta", {}).get("title"), "box": document.data.get("box", {})})
	if not document.dirty and signature == _baked_signature:
		return true
	if _saving:
		return false
	_saving = true
	if signature != _baked_signature and document.issues().errors.is_empty():
		var snapshot := Document.new()
		snapshot.data = document.data.duplicate(true)
		var baker := BoxView.new()
		baker.visible = false
		add_child(baker)
		baker.setup(snapshot, false)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if JSON.stringify(document.data) != JSON.stringify(snapshot.data):
			baker.queue_free()
			_saving = false
			_message = "Проект изменился во время сохранения. Сохраните ещё раз."
			_status_text()
			return false
		var bake_error: String = baker.bake_now()
		baker.queue_free()
		if not bake_error.is_empty():
			_saving = false
			_message = bake_error
			_status_text()
			return false
		_baked_signature = signature
	var ok := document.save()
	_saving = false
	_message = document.last_error
	_status_text()
	return ok

func _show_issues() -> void:
	var window := Window.new()
	window.title = "Проверка проекта"
	window.size = Vector2i(640, 480)
	window.theme = Style.theme()
	Style.window_surface(window)
	add_child(window)
	var scroll := ScrollContainer.new()
	scroll.name = "IssuesList"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -16
	window.add_child(scroll)
	var list := Style.column(8)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	var report: Dictionary = document.issues()
	for group: Array in [["ОШИБКИ", report.errors, "Нет ошибок."], ["ПРЕДУПРЕЖДЕНИЯ", report.warnings, "Нет предупреждений."]]:
		list.add_child(Style.heading(group[0]))
		if group[1].is_empty():
			list.add_child(Style.label(group[2]))
		for text: String in group[1]:
			list.add_child(_issue_row(text, group[0] == "ОШИБКИ", window))
	window.close_requested.connect(window.queue_free)
	window.popup_centered()

## Строка ошибки: значок, текст, «i» с подсказкой при наведении и переход на нужную вкладку.
func _issue_row(text: String, error: bool, window: Window) -> Control:
	var info: Dictionary = Issues.explain(text)
	var row := Style.row(8)
	row.name = "IssueRow"
	var mark := Style.label("●")
	mark.add_theme_color_override("font_color", Color("d0574f") if error else Color("d9a441"))
	row.add_child(mark)
	var label := Style.label(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	var box := Style.column(4)
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	row.remove_child(label)
	box.add_child(label)
	var explanation := Style.label(str(info.hint), 14)
	explanation.name = "IssueHintText"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate.a = 0.75
	explanation.visible = false
	box.add_child(explanation)
	row.add_child(box)
	var hint := Style.button("i")
	hint.name = "IssueHint"
	hint.custom_minimum_size = Vector2(32, 32)
	hint.tooltip_text = str(info.hint)
	hint.mouse_default_cursor_shape = Control.CURSOR_HELP
	hint.pressed.connect(func(): explanation.visible = not explanation.visible)
	row.add_child(hint)
	var tab := int(info.tab)
	if tab >= 0:
		var place: Dictionary = Issues.place(text, document.data)
		var go := Style.button(Issues.TAB_TITLES[tab])
		go.name = "IssueGo"
		go.tooltip_text = "Открыть вкладку «%s»" % Issues.TAB_TITLES[tab]
		go.pressed.connect(func():
			window.queue_free()
			if tab == _tab or await _save():
				_tab = tab
				_face_edit = false
				if int(place.chain) >= 0:
					_logic_chain = int(place.chain)
					_logic_path = []
					_logic_target = []
				if int(place.deck) >= 0:
					_deck = int(place.deck)
					_category = "cards" if document.data.elements.decks[_deck].get("single", false) else "decks"
				_render())
		row.add_child(go)
	return row

func _back() -> void:
	if _editing:
		if not await _save():
			return
		_editing = false
		_render()
	else:
		get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)

func _play() -> void:
	if Net.in_session():
		_message = "Локальная проверка доступна после выхода из текущего пати."
		_status_text()
		return
	if not await _save() or not document.issues().errors.is_empty():
		_message = "Исправьте ошибки проекта перед проверкой."
		_status_text()
		return
	Net.host_offline("custom:" + str(document.data.id))
	Net.set_bots(1)
	Net.settings["cg_editor_return"] = true
	Net.settings["cg_editor_id"] = str(document.data.id)
	get_tree().change_scene_to_file.call_deferred("res://games/custom/ui/main.tscn")

func _dialog(filters: PackedStringArray, many: bool, callback: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES if many else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = filters
	dialog.size = Vector2i(900, 560)
	add_child(dialog)
	if many:
		dialog.files_selected.connect(callback)
	else:
		dialog.file_selected.connect(callback)
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(func(_path: String): dialog.queue_free())
	dialog.files_selected.connect(func(_paths: PackedStringArray): dialog.queue_free())
	dialog.popup_centered()

## Системное окно «Сохранить как» (.pgame).
func _save_dialog(title: String, callback: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.pgame ; Игра из редактора"])
	dialog.current_file = title.validate_filename() + ".pgame"
	dialog.size = Vector2i(900, 560)
	add_child(dialog)
	dialog.file_selected.connect(callback)
	dialog.file_selected.connect(func(_path: String): dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _csv_dialog() -> void:
	_dialog(PackedStringArray(["*.csv ; Таблица CSV"]), false, func(path: String):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_length() <= 1024 * 1024:
			_apply_csv(file.get_as_text()))

func _paste() -> void:
	_apply_csv(DisplayServer.clipboard_get())

func _apply_csv(text: String) -> void:
	var first := text.get_slice("\n", 0)
	var delimiter := "\t" if first.contains("\t") else (";" if first.contains(";") else ",")
	var parsed := Csv.parse(text, delimiter)
	_message = str(parsed.error)
	if _message.is_empty():
		var copy := document.data.duplicate(true)
		copy.elements.decks[_deck].rows = parsed.rows
		copy.elements.decks[_deck].columns = parsed.columns
		document.replace(copy, "Импорт таблицы карт")
	_render()

func _with_notice(callback: Callable) -> void:
	var config := ConfigFile.new()
	config.load("user://editor.cfg")
	if config.get_value("imports", "notice", false):
		callback.call()
		return
	var notice := AcceptDialog.new()
	notice.title = "Изображения и шрифты"
	notice.dialog_text = "Используйте свои изображения или те, что можно свободно использовать. Шрифты часто нельзя распространять — проверьте лицензию. Источник можно указать справа."
	add_child(notice)
	notice.popup_centered(Vector2i(560, 180))
	notice.confirmed.connect(func():
		config.set_value("imports", "notice", true)
		config.save("user://editor.cfg")
		notice.queue_free()
		callback.call_deferred())

func _images_dialog() -> void:
	_with_notice(func(): _dialog(PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Изображения"]), true, _import_images))

func _import_images(paths: PackedStringArray) -> void:
	if paths.size() > 300:
		_message = "За один импорт не больше 300 карт."
		_status_text()
		return
	var copy := document.data.duplicate(true)
	if not copy.has("assets"):
		copy.assets = {}
	for path: String in paths:
		var result := Assets.import_image(str(copy.id), path, _source)
		if not str(result.error).is_empty():
			_message = str(result.error)
			break
		copy.assets[result.hash] = result.asset
		var title := path.get_file().get_basename()
		var next := {"title": title, "art": result.hash, "copies": 1}
		var columns: Array = copy.elements.decks[_deck].get("columns", [])
		if not columns.is_empty():
			next[str(columns[0].id)] = title
		copy.elements.decks[_deck].rows.append(next)
		_sheet = str(result.hash)
		if result.resized:
			_message = "Большие изображения уменьшены до 2048 px."
	document.replace(copy, "Добавить изображения карт")
	_render()

## Картинки граней по порядку выбора: первая — грань 1 и так далее, остальные грани не меняются.
func _import_dice_images(paths: PackedStringArray, path: Array) -> void:
	var copy := document.data.duplicate(true)
	if not copy.has("assets"):
		copy.assets = {}
	var target: Dictionary = copy.elements.dice[int(path[2])]
	var images: Array = target.get("images", []).duplicate()
	images.resize(6)
	for index in mini(paths.size(), 6):
		var result := Assets.import_image(str(copy.id), paths[index], _source)
		if not str(result.error).is_empty():
			_message = str(result.error)
			break
		copy.assets[result.hash] = result.asset
		images[index] = result.hash
	target["images"] = images.map(func(value: Variant): return "" if value == null else str(value))
	target["faces"] = "images"
	if paths.size() > 6:
		_message = "У кубика 6 граней: взяты первые 6 картинок."
	document.replace(copy, "Картинки граней кубика")
	_render()

func _font_dialog() -> void:
	_with_notice(_select_font)

func _import_back(path: String) -> void:
	var result := Assets.import_image(str(document.data.id), path, _source)
	_message = str(result.error)
	if _message.is_empty():
		var copy: Dictionary = document.data.duplicate(true)
		copy.assets[result.hash] = result.asset
		copy.elements.decks[_deck]["back"] = result.hash
		document.replace(copy, "Рубашка колоды")
	_render.call_deferred()

## Поля одиночной карты: каждое свойство — отдельное поле ввода вместо таблицы.
func _single_fields(parent: VBoxContainer, deck: Dictionary) -> void:
	if deck.rows.is_empty():
		return
	var row: Dictionary = deck.rows[0]
	for column: Dictionary in Faces.columns(deck):
		var field := str(column.id)
		var type := str(column.get("type", "text"))
		if type == "image":
			continue
		if type == "color":
			parent.add_child(Style.label(field))
			var swatch := ColorPickerButton.new()
			swatch.custom_minimum_size.y = 40
			swatch.edit_alpha = false
			swatch.color = Color.from_string(str(row.get(field, "#ffffff")), Color.WHITE)
			swatch.popup_closed.connect(func(): document.set_value(["elements", "decks", _deck, "rows", 0, field], "#" + swatch.color.to_html(false), "Цвет карты"))
			parent.add_child(swatch)
			continue
		parent.add_child(Style.label({"title": "Название", "text": "Текст карты", "rank": "Число"}.get(field, field)))
		if type == "bool":
			var flag := CheckBox.new()
			flag.button_pressed = bool(row.get(field, false))
			flag.toggled.connect(func(value: bool): document.set_value(["elements", "decks", _deck, "rows", 0, field], value, "Свойство карты"))
			parent.add_child(flag)
			continue
		if field == "text":
			var body := TextEdit.new()
			body.name = "SingleCardText"
			body.custom_minimum_size.y = 96
			body.text = Style.value_text(row.get(field, ""))
			body.text_changed.connect(func():
				document.set_value(["elements", "decks", _deck, "rows", 0, field], body.text, "Текст карты")
				_status_text())
			parent.add_child(body)
			continue
		var line := LineEdit.new()
		line.text = Style.value_text(row.get(field, ""))
		line.text_changed.connect(func(text: String):
			if type == "number" and not text.is_valid_float():
				_message = "В этом поле карты нужно число."
			else:
				_message = ""
				document.set_value(["elements", "decks", _deck, "rows", 0, field], float(text) if type == "number" else text, "Поле карты")
			_status_text())
		parent.add_child(line)

## «Текст на картах»: галочка у колонки = текстовый слой на лице, привязанный к этой колонке.
func _text_layers(parent: VBoxContainer, deck: Dictionary) -> void:
	parent.add_child(Style.heading("ТЕКСТ НА КАРТАХ"))
	var note := Style.label("Отметьте свойства, которые печатаются на каждой карте. Расположение и шрифт — в «Рамки и слои карты».")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)
	var layers: Array = deck.face.layers
	for column: Dictionary in Faces.columns(deck):
		if column.get("type", "text") in ["image", "color"]:
			continue
		var field := str(column.id)
		var bound := layers.any(func(layer: Dictionary): return layer.get("kind") == "text" and layer.get("field", "") == field)
		var flag := CheckBox.new()
		flag.name = "CardTextBinding_" + field
		flag.text = field
		flag.button_pressed = bound
		flag.toggled.connect(_toggle_text_layer.bind(field))
		parent.add_child(flag)

func _toggle_text_layer(on: bool, field: String) -> void:
	var copy: Dictionary = document.data.duplicate(true)
	var target: Array = copy.elements.decks[_deck].face.layers
	if on:
		var size: Array = Faces.dimensions(copy.elements.decks[_deck])
		var count := target.filter(func(layer: Dictionary): return layer.get("kind") == "text").size()
		var top := mini(32 + count * 96, int(size[1]) - 112)
		target.append({"kind": "text", "title": field, "field": field, "rect": [32, top, int(size[0]) - 64, 96],
			"text": "", "asset": "", "font_size": 64, "color": "#30263f", "rotation": 0, "opacity": 1.0, "align": "left"})
	else:
		for index in range(target.size() - 1, -1, -1):
			if target[index].get("kind") == "text" and target[index].get("field", "") == field:
				target.remove_at(index)
	document.replace(copy, "Текст на картах")
	_render.call_deferred()

func _face_bindings(parent: VBoxContainer, deck: Dictionary, fields: Array) -> void:
	parent.add_child(Style.heading("ШАБЛОН ЛИЦА"))
	for binding: Array in [["title", "Заголовок", "title"], ["value", "Число", "rank"], ["text", "Текст", "text"], ["art", "Рисунок", "art"]]:
		parent.add_child(Style.label(binding[1]))
		var selector := OptionButton.new()
		var values: Array = [""] + fields
		selector.add_item("Не показывать")
		for field: String in fields:
			selector.add_item(field)
		selector.select(maxi(0, values.find(deck.get("face", {}).get(binding[0], binding[2]))))
		selector.item_selected.connect(func(index: int):
			var copy: Dictionary = document.data.duplicate(true)
			var target: Dictionary = copy.elements.decks[_deck]
			if not target.has("face"):
				target.face = {}
			target.face[binding[0]] = values[index]
			document.replace(copy, "Привязка поля лица карты")
			_render.call_deferred())
		parent.add_child(selector)

func _columns_dialog() -> void:
	var popup := Window.new()
	popup.title = "Свойства карт"
	popup.size = Vector2i(560, 480)
	popup.theme = Style.theme()
	Style.window_surface(popup)
	add_child(popup)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -16
	popup.add_child(scroll)
	var col := Style.column(12)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(col)
	var columns: Array = document.data.elements.decks[_deck].get("columns", [])
	var message := Style.label("")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for index in columns.size():
		var row := Style.row(8)
		col.add_child(row)
		var label := Style.label(str(columns[index].id))
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(label)
		var column_type := OptionButton.new()
		for caption: String in ["Текст", "Число", "Да / нет", "Рисунок", "Цвет"]:
			column_type.add_item(caption)
		var old_type := maxi(0, ["text", "number", "bool", "image", "color"].find(str(columns[index].get("type", "text"))))
		column_type.select(old_type)
		column_type.item_selected.connect(func(next: int):
			var result: String = ElementsModel.new(document).change_column_type(_deck, index, ["text", "number", "bool", "image", "color"][next])
			message.text = result
			if result.is_empty():
				popup.queue_free()
				_render.call_deferred()
			else:
				column_type.select(old_type))
		row.add_child(column_type)
		var remove := Style.button("Удалить")
		remove.pressed.connect(func():
			ElementsModel.new(document).remove_column(_deck, index)
			popup.queue_free()
			_render.call_deferred())
		row.add_child(remove)
	col.add_child(Style.label("Имя свойства доступно блокам как поле карты."))
	var name_field := LineEdit.new()
	name_field.placeholder_text = "Например: сила"
	col.add_child(name_field)
	var type := OptionButton.new()
	for text: String in ["Текст", "Число", "Да / нет", "Рисунок (хэш ассета)", "Цвет"]:
		type.add_item(text)
	col.add_child(type)
	col.add_child(message)
	var add := Style.button("Добавить свойство")
	add.pressed.connect(func():
		var result: String = ElementsModel.new(document).add_column(_deck, name_field.text, ["text", "number", "bool", "image", "color"][type.selected])
		message.text = result
		if result.is_empty():
			popup.queue_free()
			_render.call_deferred())
	col.add_child(add)
	popup.close_requested.connect(popup.queue_free)
	popup.popup_centered()

func _select_font() -> void:
	_dialog(PackedStringArray(["*.ttf,*.otf ; Шрифты"]), false, func(path: String):
		var result := Assets.import_font(str(document.data.id), path, _source)
		_message = str(result.error)
		if _message.is_empty():
			var copy := document.data.duplicate(true)
			if not copy.has("assets"):
				copy.assets = {}
			copy.assets[result.hash] = result.asset
			var deck: Dictionary = copy.elements.decks[_deck]
			if not deck.has("face"):
				deck.face = {}
			deck.face.font = result.hash
			document.replace(copy, "Добавить шрифт")
			_message = "Шрифт применён к заголовкам карт этой колоды."
		_render())

func _exit_tree() -> void:
	if _editing and document.dirty:
		document.save()

func _unhandled_key_input(event: InputEvent) -> void:
	if not _editing or not event is InputEventKey or not event.pressed or not event.ctrl_pressed:
		return
	if event.keycode == KEY_Z:
		document.undo()
		_render()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Y:
		document.redo()
		_render()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()
