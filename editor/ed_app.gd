extends Control
## Оболочка редактора и первые инструменты компонентов. Запуск: res://editor/main.tscn.

const Style := preload("res://games/custom/ui/cg_style.gd")
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

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = Style.theme()
	var background := ColorRect.new()
	background.color = Style.bg()
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
		background.color = Style.bg()
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
	var titles := ["Коробка", "Интерфейс", "Логика", "Элементы"]
	for index in titles.size():
		var button := Style.button(titles[index])
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		if index == _tab:
			button.add_theme_stylebox_override("normal", Style.box(Style.panel().lightened(0.08)))
		button.pressed.connect(func():
			if not await _save():
				return
			_tab = index
			_render())
		tabs.add_child(button)
	var body := Style.row(16)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	_shell.add_child(body)
	var tool_scroll := ScrollContainer.new()
	tool_scroll.custom_minimum_size.x = 208
	tool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(tool_scroll)
	var tools := Style.column(8)
	tools.size_flags_horizontal = SIZE_EXPAND_FILL
	tools.custom_minimum_size.x = 160
	tool_scroll.add_child(tools)
	var center := Style.column(16)
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(center)
	var property_scroll := ScrollContainer.new()
	property_scroll.custom_minimum_size.x = 304
	body.add_child(property_scroll)
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
	_status = Style.label("")
	var status_row := Style.row(8)
	_shell.add_child(status_row)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.clip_text = true
	status_row.add_child(_status)
	if _help_tab != _tab:
		_help_tab = _tab
		_tab_tip = _help.tip(_tab)
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
	status_row.add_child(help)
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
			_render())
	row.add_child(create)
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
	var guides := CheckButton.new()
	guides.text = "Направляющие"
	guides.tooltip_text = "Привязка к краям и центрам видимых элементов. Alt временно отключает её; сетка 8 px сохраняется."
	guides.button_pressed = _layout_guides
	view_tools.add_child(guides)
	if document.data.layout.get("screens", []).is_empty():
		document.set_value(["layout", "screens"], [{"id": "main", "items": []}], "Создать экран")
	_layout_canvas = Canvas.new()
	_layout_canvas.zoom = _layout_zoom
	_layout_canvas.pan = _layout_pan
	_layout_canvas.guides_enabled = _layout_guides
	_layout_canvas.items = document.data.layout.screens[0].get("items", []).duplicate(true)
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
		copy.layout.screens[0].items[index]["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		copy.layout["custom"] = true
		document.replace(copy, "Расположение элемента")
		_status_text()
		_layout_properties(properties))
	for entry: Array in [["zone", "Зона"], ["hand", "Рука игрока"], ["self_panel", "Панель Я"], ["opponents", "Соперники"], ["teams", "Команды"], ["players", "Игроки"], ["button", "Кнопка"], ["counter", "Счётчик"], ["text", "Текст"], ["image", "Картинка"], ["dice_tray", "Лоток d6"], ["journal", "Журнал"], ["phase", "Фаза / ход"]]:
		var button := Style.button("+ " + str(entry[1]))
		button.pressed.connect(func(): _add_layout(str(entry[0]), str(entry[1])))
		tools.add_child(button)
	_layout_properties(properties)

func _add_layout(kind: String, title: String) -> void:
	var copy := document.data.duplicate(true)
	var items: Array = copy.layout.screens[0].items
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
	items.append(item)
	copy.layout["custom"] = true
	document.replace(copy, "Добавить элемент стола")
	_layout_selected = items.size() - 1
	_render()

func _layout_properties(properties: VBoxContainer) -> void:
	Style.clear(properties)
	_clipboard_controls(properties, "layout", ["layout", "screens", 0, "items"], _layout_selected)
	if _layout_selected < 0 or _layout_selected >= document.data.layout.screens[0].items.size():
		properties.add_child(Style.label("Выберите элемент на холсте"))
		return
	var item: Dictionary = document.data.layout.screens[0].items[_layout_selected]
	var path: Array = ["layout", "screens", 0, "items", _layout_selected]
	_text(properties, "Название", path + ["title"])
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
			copy.layout.screens[0].items[_layout_selected]["rect"] = next
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
		var target: Dictionary = copy.layout.screens[0].items[_layout_selected]
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
		"button":
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
		copy.layout.screens[0].items.remove_at(_layout_selected)
		document.replace(copy, "Удалить элемент стола")
		_layout_selected = -1
		_render())
	properties.add_child(remove)

func _logic(tools: VBoxContainer, center: VBoxContainer, properties: VBoxContainer) -> void:
	var logic := Logic.new()
	logic.setup(self, tools, center, properties)

func _elements(tools: VBoxContainer, center: VBoxContainer, properties: VBoxContainer) -> void:
	var face_decks: Array = document.data.elements.get("decks", [])
	if _face_edit and _category == "decks" and not face_decks.is_empty():
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
	for entry: Array in [["decks", "Колоды"], ["dice", "Кубики"], ["tokens", "Жетоны"], ["resources", "Ресурсы"]]:
		var category := Style.button(entry[1])
		category.pressed.connect(func():
			_category = entry[0]
			_deck = 0
			_render())
		tools.add_child(category)
	if _category != "decks":
		_components(tools, center, properties)
		return
	var decks: Array = document.data.elements.get("decks", [])
	_clipboard_controls(tools, "decks", ["elements", "decks"], _deck)
	tools.add_child(Style.heading("КОЛОДЫ"))
	for index in decks.size():
		var button := Style.button(str(decks[index].get("title", decks[index].id)))
		button.clip_text = true
		button.pressed.connect(func():
			_deck = index
			_render())
		tools.add_child(button)
	var add := Style.button("+ Колода")
	add.pressed.connect(func():
		document.add_deck()
		_deck = document.data.elements.decks.size() - 1
		_render())
	tools.add_child(add)
	if decks.is_empty():
		center.add_child(Style.heading("ДОБАВЬТЕ ПЕРВУЮ КОЛОДУ"))
		center.add_child(Style.label("Один шаблон и таблица с названием, свойствами и числом копий."))
		return
	_deck = clampi(_deck, 0, decks.size() - 1)
	var deck: Dictionary = decks[_deck]
	var face_editor := Style.button("Редактор лица карты")
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
		var card_size := Vector2(Definition.CARD_SIZES[clampi(int(deck.get("size", 3)) - 1, 0, 8)])
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
	var table := ScrollContainer.new()
	table.size_flags_vertical = SIZE_EXPAND_FILL
	table.size_flags_horizontal = SIZE_EXPAND_FILL
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
			next[field] = 0 if field_types.get(field) == "number" or old is int or old is float else (false if field_types.get(field) == "bool" else ("" if field_types.get(field) == "image" else "Новая карта"))
		copy.elements.decks[_deck].rows.append(next)
		document.replace(copy, "Добавить карту")
		_render())
	center.add_child(add_row)
	if not deck.has("title"):
		var copy := document.data.duplicate(true)
		copy.elements.decks[_deck].title = str(deck.id)
		document.replace(copy, "Название колоды")
	_text(properties, "Название колоды", ["elements", "decks", _deck, "title"])
	properties.add_child(Style.label("Размер карты"))
	var sizes := OptionButton.new()
	for title: String in ["Мини · 44×68", "Бридж · 57×89", "Стандарт · 63×88", "Большая · 70×110", "Макси · 80×120", "Квадрат · 70", "Квадрат · 100", "Квадрат · 60", "Квадрат · 45"]:
		sizes.add_item(title)
	sizes.select(clampi(int(deck.get("size", 3)) - 1, 0, 8))
	sizes.item_selected.connect(func(index: int):
		document.set_value(["elements", "decks", _deck, "size"], index + 1, "Размер карт")
		_render.call_deferred())
	properties.add_child(sizes)
	properties.add_child(Style.label("Колода"))
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
	for item: Array in [["Импорт CSV", _csv_dialog], ["Вставить таблицу", _paste], ["Добавить картинки", _images_dialog], ["Импорт шрифта", _font_dialog]]:
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
	var add := Style.button("+ Ресурс" if resources else ("+ Набор d6" if _category == "dice" else "+ Жетоны"))
	add.pressed.connect(_add_component)
	tools.add_child(add)
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
		_number(properties, "Кубиков d6", path + ["count"], 1, 30)
		_choice(properties, "Кому виден результат", path + ["visible"], ["Всем", "Бросавшему"], ["all", "owner"])
		center.add_child(Style.label("В игре нажмите «Бросить», потяните кубик и отпустите. Результат выбирает хост."))
		var die := TossDie.new()
		die.position = Vector2(160, 120)
		die.home = Vector2(192, 152)
		die.area = Rect2(0, 0, 480, 288)
		die.draggable = true
		var preview := Control.new()
		preview.custom_minimum_size = Vector2(400, 300)
		center.add_child(preview)
		preview.add_child(die)
		die.wait_for_roll()
		die.thrown.connect(func(_vel: Vector2): die.set_result(randi_range(1, 6)))
	else:
		_number(properties, "Количество", path + ["count"], 1, 300)
		_number(properties, "Номинал", path + ["value"], 0, 999999)
		_choice(properties, "Форма", path + ["shape"], ["Круг", "Квадрат", "Шестиугольник"], ["circle", "square", "hex"])
		var token := Style.TokenFace.new(entry)
		token.custom_minimum_size = Vector2(192, 192)
		token.size_flags_horizontal = SIZE_SHRINK_CENTER
		center.add_child(token)
		center.add_child(Style.label("Жетоны появятся на столе. Переносите их в свободные зоны."))
	var free := CheckButton.new()
	free.text = "Свободное управление"
	free.button_pressed = bool(entry.get("free", false))
	free.toggled.connect(func(value: bool):
		document.set_value(path + ["free"], value, "Ручное управление")
		_status_text())
	properties.add_child(free)

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
	var prefix := "resource" if resources else ("dice" if _category == "dice" else "token")
	var number := 1
	while entries.any(func(entry: Dictionary): return str(entry.id) == "%s_%d" % [prefix, number]):
		number += 1
	var entry := {"id": "%s_%d" % [prefix, number], "free": true}
	if resources:
		entry.merge({"title": "Ресурс", "type": "number", "scope": "player", "init": 0, "visible": "all"})
	elif _category == "dice":
		entry.merge({"title": "Набор d6", "count": 3, "visible": "owner"})
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
	if _tab == 1 and is_instance_valid(_layout_canvas):
		_layout_canvas.items = document.data.layout.screens[0].get("items", []).duplicate(true)
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
	var content := TextEdit.new()
	content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content.editable = false
	var report: Dictionary = document.issues()
	content.text = "ОШИБКИ\n" + ("Нет ошибок." if report.errors.is_empty() else "\n\n".join(report.errors))
	content.text += "\n\nПРЕДУПРЕЖДЕНИЯ\n" + ("Нет предупреждений." if report.warnings.is_empty() else "\n\n".join(report.warnings))
	window.add_child(content)
	window.close_requested.connect(window.queue_free)
	window.popup_centered()

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
		for caption: String in ["Текст", "Число", "Да / нет", "Рисунок"]:
			column_type.add_item(caption)
		var old_type := maxi(0, ["text", "number", "bool", "image"].find(str(columns[index].get("type", "text"))))
		column_type.select(old_type)
		column_type.item_selected.connect(func(next: int):
			var result: String = ElementsModel.new(document).change_column_type(_deck, index, ["text", "number", "bool", "image"][next])
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
	for text: String in ["Текст", "Число", "Да / нет", "Рисунок (хэш ассета)"]:
		type.add_item(text)
	col.add_child(type)
	col.add_child(message)
	var add := Style.button("Добавить свойство")
	add.pressed.connect(func():
		var result: String = ElementsModel.new(document).add_column(_deck, name_field.text, ["text", "number", "bool", "image"][type.selected])
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
