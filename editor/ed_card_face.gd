extends RefCounted
## Шаблон лица колоды: общий холст, привязки к таблице, слои и атомарные жесты.
const Style := preload("res://editor/ed_style.gd")
## Стиль игр — для предпросмотров того, что увидят игроки.
const Game := preload("res://games/custom/ui/cg_style.gd")

const Faces := preload("res://games/custom/logic/cg_faces.gd")
const Canvas := preload("res://editor/ed_card_canvas.gd")
const Reader := preload("res://games/custom/ui/cg_assets.gd")
const Assets := preload("res://editor/ed_assets.gd")
const Templates := preload("res://editor/ed_templates.gd")
var app: Control
var document: RefCounted
var deck_index := 0
var properties: VBoxContainer
var _list: VBoxContainer
var _canvas: Control
var _reader := Reader.new()

func _deck() -> Dictionary:
	return document.data.elements.decks[deck_index]

func _path() -> Array:
	return ["elements", "decks", deck_index, "face", "layers"]

func setup(owner: Control, tools: VBoxContainer, center: VBoxContainer, right: VBoxContainer, index: int) -> void:
	app = owner
	document = app.document
	deck_index = index
	properties = right
	var back := Style.button("К таблице карт")
	back.pressed.connect(func():
		app._face_edit = false
		app._render.call_deferred())
	tools.add_child(back)
	var templates := Style.primary("Шаблоны лица…")
	templates.name = "CardFaceTemplates"
	templates.tooltip_text = "Готовое лицо: число и масть, название с рисунком, слово, роль, цена, вопрос–ответ."
	templates.pressed.connect(_templates_dialog)
	tools.add_child(templates)
	tools.add_child(Style.heading("СЛОИ"))
	center.add_child(Style.heading("ШАБЛОН ЛИЦА КАРТЫ"))
	_reader.configure_document(document.data)
	if not _deck().get("face", {}).get("layers") is Array:
		var note := Style.label("Текущий вид пока использует простые привязки. Создайте слои, чтобы свободно расположить рисунки и текст на всех картах колоды.")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		center.add_child(note)
		var convert := Style.primary("Создать слои из текущего вида")
		convert.pressed.connect(_convert)
		center.add_child(convert)
		return
	var layers: Array = _deck().face.layers
	if app._face_layer >= layers.size():
		app._face_layer = layers.size() - 1
	var sample := OptionButton.new()
	sample.name = "CardFaceSampleRow"
	for row in _deck().rows.size():
		sample.add_item("Карта %d · %s" % [row + 1, Faces.text(_deck().rows[row].get("title", _deck().rows[row].get("rank", "")))])
	app._face_row = clampi(app._face_row, 0, maxi(0, _deck().rows.size() - 1))
	if sample.item_count > 0:
		sample.select(app._face_row)
	sample.disabled = sample.item_count == 0
	sample.item_selected.connect(func(row: int):
		app._face_row = row
		_refresh_canvas())
	center.add_child(sample)
	for entry: Array in [["fill", "+ Фигура"], ["frame", "+ Рамка"], ["text", "+ Текст"], ["image", "+ Рисунок"]]:
		var add := Style.button(entry[1])
		add.disabled = layers.size() >= 64
		add.pressed.connect(func(): _add(entry[0]))
		tools.add_child(add)
	_list = Style.column(8)
	tools.add_child(_list)
	_build_list()
	var clipboard := Style.column(8)
	clipboard.name = "CardFaceClipboard"
	tools.add_child(clipboard)
	app._clipboard_controls(clipboard, "face_layer", _path(), app._face_layer)
	_canvas = Canvas.new()
	_canvas.zoom = app._face_zoom
	_canvas.pan = app._face_pan
	center.add_child(_canvas)
	_canvas.selected.connect(func(selected: int):
		app._face_layer = selected
		_build_list()
		_properties())
	_canvas.transformed.connect(func(selected: int, rect: Array, rotation: float):
		var copy: Dictionary = document.data.duplicate(true)
		var layer: Dictionary = copy.elements.decks[deck_index].face.layers[selected]
		layer.rect = rect
		layer["rotation"] = rotation
		document.replace(copy, "Трансформировать слой карты")
		_refresh_canvas()
		_properties())
	_canvas.view_changed.connect(func(zoom: float, pan: Vector2):
		app._face_zoom = zoom
		app._face_pan = pan)
	_refresh_canvas()
	_properties()

## Окно «Шаблоны лица»: схема слоёв в пропорциях карты этой колоды; выбор — одна правка с отменой.
func _templates_dialog() -> void:
	var window := Window.new()
	window.name = "CardFaceTemplatesWindow"
	window.title = "Шаблоны лица карты"
	window.size = Vector2i(880, 600)
	window.theme = Style.theme()
	Style.window_surface(window)
	app.add_child(window)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -16
	window.add_child(scroll)
	var column := Style.column(12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var note := Style.label("Слои лица заменятся, фон и цвет карт останутся. Нужные свойства (колонки таблицы) добавятся сами — заполните их в таблице карт. Отменить — Ctrl+Z.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate.a = 0.8
	column.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	var size: Array = Faces.dimensions(_deck())
	var aspect := float(size[0]) / float(size[1])
	for template: Dictionary in Templates.FACES:
		var card := Button.new()
		card.name = "CardFaceTemplate_" + str(template.id)
		card.custom_minimum_size = Vector2(256, 300)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.draw.connect(func():
			var area := Rect2(Vector2(16, 16), Vector2(card.size.x - 32, card.size.y - 84))
			var shown := Vector2(area.size.y * aspect, area.size.y)
			if shown.x > area.size.x:
				shown = Vector2(area.size.x, area.size.x / aspect)
			var face := Rect2(area.position + (area.size - shown) * 0.5, shown)
			card.draw_style_box(Style.box(Color(Faces.paper(_deck())), 0), face)
			if template.frame:
				card.draw_rect(face.grow(-6), Color("30263f"), false, 2)
			for spec: Array in template.layers:
				var rect := Rect2(face.position + Vector2(spec[2], spec[3]) * face.size, Vector2(spec[4], spec[5]) * face.size)
				var tone := Color("30263f", 0.18) if spec[0] in ["text", "line"] else (Color("e0b84e") if spec[0] == "badge" else Color("6c8ca8", 0.45))
				card.draw_rect(rect, tone)
				if spec[0] == "text" and rect.size.y > 10:
					card.draw_string(Style.body_font(), rect.position + Vector2(2, minf(rect.size.y - 2, 12)), str(Templates.FACE_COLUMN_TITLES.get(spec[1], spec[1])), HORIZONTAL_ALIGNMENT_CENTER if spec[7] == "center" else HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 4, 10, Color("30263f"))
			card.draw_string(Style.head_font(), Vector2(16, card.size.y - 42), str(template.title), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 18, Style.ink())
			card.draw_string(Style.body_font(), Vector2(16, card.size.y - 18), str(template.hint), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 13, Color(Style.ink(), 0.7)))
		card.pressed.connect(func():
			var copy: Dictionary = document.data.duplicate(true)
			copy.elements.decks[deck_index] = Templates.apply_face(copy.elements.decks[deck_index], str(template.id))
			document.replace(copy, "Шаблон лица: " + str(template.title))
			app._message = "Лицо «%s». Заполните новые свойства в таблице карт." % template.title
			app._face_layer = copy.elements.decks[deck_index].face.layers.size() - 1
			window.queue_free()
			app._render.call_deferred())
		grid.add_child(card)
	window.close_requested.connect(window.queue_free)
	window.popup_centered()

func _convert() -> void:
	var copy: Dictionary = document.data.duplicate(true)
	var deck: Dictionary = copy.elements.decks[deck_index]
	deck["columns"] = Faces.columns(deck)
	if not deck.has("face"):
		deck["face"] = {}
	deck.face["layers"] = Faces.default_layers(deck)
	document.replace(copy, "Создать слои лица карты")
	app._face_layer = deck.face.layers.size() - 1
	app._render.call_deferred()

func _add(kind: String) -> void:
	var copy: Dictionary = document.data.duplicate(true)
	var layers: Array = copy.elements.decks[deck_index].face.layers
	if layers.size() >= 64:
		return
	var layer := {"kind": kind, "title": {"fill": "Фигура", "frame": "Рамка", "text": "Текст", "image": "Рисунок"}[kind],
		"rect": [48, 160, 320, 160], "field": "", "text": "Новый текст" if kind == "text" else "", "asset": "",
		"font_size": 64, "color": "#30263f" if kind in ["text", "frame"] else "#b7c9bd", "rotation": 0, "opacity": 1.0}
	if kind == "frame":
		# Рамка по умолчанию — по краю карты с отступом, внутри прозрачно.
		var size: Array = Faces.dimensions(copy.elements.decks[deck_index])
		layer.merge({"rect": [24, 24, int(size[0]) - 48, int(size[1]) - 48], "border": 16, "radius": 24, "fill": ""}, true)
	# Рамка — оформление: кладём сразу над фоном карты, чтобы текст и рисунки остались поверх.
	var at := 1 if kind == "frame" and not layers.is_empty() and Faces.is_card_background(layers[0], 0) else layers.size()
	layers.insert(at, layer)
	document.replace(copy, "Добавить слой карты")
	app._face_layer = at
	app._render.call_deferred()

func _refresh_canvas() -> void:
	_reader.configure_document(document.data)
	var row: Dictionary = _deck().rows[app._face_row] if app._face_row < _deck().rows.size() else {}
	_canvas.configure(_deck(), row, _reader, app._face_layer)
	app._status_text()

func _build_list() -> void:
	Style.clear(_list)
	var layers: Array = _deck().face.layers
	for index in range(layers.size() - 1, -1, -1):
		var button := Style.button(str(layers[index].get("title", layers[index].kind)))
		button.name = "CardFaceLayer%d" % index
		button.clip_text = true
		if index == app._face_layer:
			button.add_theme_stylebox_override("normal", Style.box(Style.panel().lerp(Style.accent(), 0.24)))
		button.pressed.connect(func():
			app._face_layer = index
			_canvas.selection = index
			_canvas._place()
			_build_list()
			_properties())
		_list.add_child(button)

func _commit(key: String, value: Variant) -> void:
	if app._face_layer < 0 or app._face_layer >= _deck().face.layers.size():
		return
	if not document.set_value(_path() + [app._face_layer, key], value, "Свойство слоя карты"):
		app._message = document.last_error
		app._status_text()
		return
	app._message = ""
	_refresh_canvas()

func _number(caption: String, value: float, minimum: float, maximum: float, step: float, callback: Callable) -> void:
	properties.add_child(Style.label(caption))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.value_changed.connect(callback)
	properties.add_child(spin)

func _choice(caption: String, labels: Array, values: Array, selected: Variant, callback: Callable) -> void:
	properties.add_child(Style.label(caption))
	var menu := OptionButton.new()
	menu.clip_text = true
	menu.fit_to_longest_item = false
	if caption == "Из колонки":
		menu.name = "CardFaceBinding"
	elif caption == "Фигура":
		menu.name = "CardFaceShape"
	for label: String in labels:
		menu.add_item(label)
	menu.select(maxi(0, values.find(selected)))
	menu.item_selected.connect(func(index: int): callback.call(values[index]))
	properties.add_child(menu)

func _properties() -> void:
	Style.clear(properties)
	properties.add_child(Style.heading("СЛОЙ КАРТЫ"))
	if app._face_layer < 0 or app._face_layer >= _deck().face.layers.size():
		properties.add_child(Style.label("Выберите слой слева или на карте."))
		return
	var layer: Dictionary = _deck().face.layers[app._face_layer]
	var name_field := LineEdit.new()
	name_field.text = str(layer.get("title", "Слой"))
	name_field.text_changed.connect(func(value: String):
		_commit("title", value)
		_build_list())
	properties.add_child(name_field)
	for key: String in ["visible", "locked"]:
		var flag := CheckBox.new()
		flag.text = "Виден" if key == "visible" else "Закрепить слой"
		flag.button_pressed = bool(layer.get(key, key == "visible"))
		flag.toggled.connect(func(value: bool):
			_commit(key, value)
			if key == "locked":
				_properties())
		properties.add_child(flag)
	if Faces.is_card_background(layer, app._face_layer):
		# Фон карты = «Цвет карт» колоды: одна настройка и в таблице, и здесь.
		properties.add_child(Style.label("Цвет карт колоды"))
		var paper := ColorPickerButton.new()
		paper.name = "CardFacePaper"
		paper.custom_minimum_size.y = 40
		paper.edit_alpha = false
		paper.color = Color.from_string(Faces.paper(_deck()), Color("ded7c8"))
		paper.popup_closed.connect(func():
			document.set_value(["elements", "decks", deck_index, "color"], "#" + paper.color.to_html(false), "Цвет карт")
			_refresh_canvas())
		properties.add_child(paper)
	if layer.get("locked", false):
		var note := Style.label("Снимите закрепление, чтобы менять слой.")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		properties.add_child(note)
		return
	if layer.kind in ["text", "image"]:
		var labels: Array = ["Своё значение"]
		var values: Array = [""]
		for column: Dictionary in Faces.columns(_deck()):
			if layer.kind == "image" and column.get("type", "text") != "image" or column.get("type", "text") == "color":
				continue
			labels.append(str(column.id))
			values.append(str(column.id))
		_choice("Из колонки", labels, values, layer.get("field", ""), func(value: String):
			_commit("field", value)
			_properties())
	if layer.kind == "text":
		if str(layer.get("field", "")).is_empty():
			var text := TextEdit.new()
			text.custom_minimum_size.y = 96
			text.text = str(layer.get("text", ""))
			text.text_changed.connect(func(): _commit("text", text.text))
			properties.add_child(text)
		_number("Размер текста", float(layer.get("font_size", 64)), 8, 512, 1, func(value: float): _commit("font_size", value))
		_choice("Выравнивание", ["Слева", "По центру", "Справа"], ["left", "center", "right"], layer.get("align", "left"), func(value: String): _commit("align", value))
		var fonts: Array = [""]
		var font_names: Array = ["Шрифт игры"]
		for hash_value: String in document.data.assets:
			if str(document.data.assets[hash_value].get("path", "")).begins_with("assets/fonts/"):
				fonts.append(hash_value)
				var caption := str(document.data.assets[hash_value].get("name", document.data.assets[hash_value].get("source", ""))).get_file()
				font_names.append(caption if not caption.is_empty() else "Свой шрифт %d" % fonts.size())
		_choice("Шрифт", font_names, fonts, layer.get("font", ""), func(value: String): _commit("font", value))
	elif layer.kind == "image" and str(layer.get("field", "")).is_empty():
		var hashes: Array = [""]
		var labels: Array = ["Не выбран"]
		for hash_value: String in document.data.assets:
			if str(document.data.assets[hash_value].get("path", "")).begins_with("assets/img/"):
				hashes.append(hash_value)
				var caption := str(document.data.assets[hash_value].get("name", document.data.assets[hash_value].get("source", ""))).get_file()
				labels.append(caption if not caption.is_empty() else "Рисунок %d" % hashes.size())
		_choice("Рисунок", labels, hashes, layer.get("asset", ""), func(value: String): _commit("asset", value))
		var import_button := Style.button("Добавить свою картинку")
		import_button.pressed.connect(func():
			app._with_notice(func(): app._dialog(PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Рисунок слоя"]), false, _import_image)))
		properties.add_child(import_button)
	elif layer.kind == "fill" and not Faces.is_card_background(layer, app._face_layer):
		_choice("Фигура", ["Прямоугольник", "Овал"], ["rect", "ellipse"], layer.get("shape", "rect"), func(value: String): _commit("shape", value))
	if layer.kind == "frame":
		properties.add_child(Style.label("Цвет рамки"))
		var color := ColorPickerButton.new()
		color.name = "CardFaceFrameColor"
		color.custom_minimum_size.y = 40
		color.color = Color.from_string(str(layer.get("color", "#30263f")), Color("30263f"))
		color.color_changed.connect(func(value: Color): _commit("color", "#" + value.to_html()))
		properties.add_child(color)
		_number("Толщина рамки", float(layer.get("border", 16)), 0, 512, 1, func(value: float): _commit("border", value))
		_number("Скругление углов", float(layer.get("radius", 24)), 0, 2048, 1, func(value: float): _commit("radius", value))
		var inside := str(layer.get("fill", ""))
		var filled := CheckBox.new()
		filled.name = "CardFaceFrameFilled"
		filled.text = "Закрасить внутри рамки"
		filled.button_pressed = not inside.is_empty()
		filled.toggled.connect(func(on: bool):
			_commit("fill", "#f3ecdc" if on else "")
			_properties())
		properties.add_child(filled)
		if not inside.is_empty():
			properties.add_child(Style.label("Цвет внутри рамки"))
			var fill := ColorPickerButton.new()
			fill.name = "CardFaceFrameFill"
			fill.custom_minimum_size.y = 40
			fill.color = Color.from_string(inside, Color("f3ecdc"))
			fill.color_changed.connect(func(value: Color): _commit("fill", "#" + value.to_html()))
			properties.add_child(fill)
	elif layer.kind != "image" and not Faces.is_card_background(layer, app._face_layer):
		var color := ColorPickerButton.new()
		color.custom_minimum_size.y = 40
		color.color = Color.from_string(str(layer.get("color", "#30263f")), Color("30263f"))
		color.color_changed.connect(func(value: Color): _commit("color", "#" + value.to_html()))
		properties.add_child(color)
	if layer.kind in ["fill", "frame", "text"] and not Faces.is_card_background(layer, app._face_layer):
		_color_source("color_field", "Цвет из колонки" if layer.kind != "frame" else "Цвет рамки из колонки", layer)
		if layer.kind == "frame" and not str(layer.get("fill", "")).is_empty():
			_color_source("fill_field", "Цвет внутри из колонки", layer)
	for index in 4:
		_number(["X", "Y", "Ширина", "Высота"][index], float(layer.rect[index]), -4096 if index < 2 else 8, 4096, 1, func(value: float):
			var rect: Array = _deck().face.layers[app._face_layer].rect.duplicate()
			rect[index] = value
			_commit("rect", rect))
	_number("Поворот", float(layer.get("rotation", 0)), -3600, 3600, 1, func(value: float): _commit("rotation", value))
	_number("Непрозрачность", float(layer.get("opacity", 1)), 0, 1, 0.05, func(value: float): _commit("opacity", value))
	var order := Style.row(8)
	properties.add_child(order)
	for direction: int in [-1, 1]:
		var button := Style.button("Ниже" if direction < 0 else "Выше")
		button.disabled = app._face_layer + direction < 0 or app._face_layer + direction >= _deck().face.layers.size()
		button.pressed.connect(func():
			var copy: Dictionary = document.data.duplicate(true)
			var layers: Array = copy.elements.decks[deck_index].face.layers
			var next: int = app._face_layer + direction
			var swap: Variant = layers[next]
			layers[next] = layers[app._face_layer]
			layers[app._face_layer] = swap
			document.replace(copy, "Порядок слоёв карты")
			app._face_layer = next
			app._render.call_deferred())
		order.add_child(button)
	var remove := Style.button("Удалить слой")
	remove.pressed.connect(func():
		var copy: Dictionary = document.data.duplicate(true)
		copy.elements.decks[deck_index].face.layers.remove_at(app._face_layer)
		document.replace(copy, "Удалить слой карты")
		app._face_layer = -1
		app._render.call_deferred())
	properties.add_child(remove)

func _import_image(path: String) -> void:
	var imported := Assets.import_image(str(document.data.id), path, app._source)
	app._message = str(imported.error)
	if not app._message.is_empty():
		app._status_text()
		return
	var copy: Dictionary = document.data.duplicate(true)
	copy.assets[imported.hash] = imported.asset
	var layer: Dictionary = copy.elements.decks[deck_index].face.layers[app._face_layer]
	layer["asset"] = imported.hash
	layer.rect[2] = imported.dimensions[0]
	layer.rect[3] = imported.dimensions[1]
	document.replace(copy, "Рисунок слоя карты")
	app._render.call_deferred()

## Выбор колонки-цвета: у каждой карты свой цвет слоя. Без колонок-цветов — подсказка, как её завести.
func _color_source(key: String, caption: String, layer: Dictionary) -> void:
	var labels: Array = ["Один цвет для всех карт"]
	var values: Array = [""]
	for column: Dictionary in Faces.columns(_deck()):
		if column.get("type", "text") == "color":
			labels.append(str(column.id))
			values.append(str(column.id))
	if values.size() == 1:
		if key == "color_field":
			var note := Style.label("Свой цвет у каждой карты: добавьте свойство типа «Цвет» в «Свойства карт / колонки».")
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.modulate.a = 0.75
			properties.add_child(note)
		return
	_choice(caption, labels, values, layer.get(key, ""), func(value: String):
		_commit(key, value)
		_properties())
