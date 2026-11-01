extends RefCounted
## Инструменты граней коробки: слои, текст/картинки, трансформации и запекание в штатные covers.

const Style := preload("res://games/custom/ui/cg_style.gd")
const View := preload("res://editor/ed_box_view.gd")
const Assets := preload("res://editor/ed_assets.gd")
const Fonts := preload("res://editor/ed_fonts.gd")
var app: Control
var document: RefCounted
var preview: Control
var properties: VBoxContainer

func setup(owner: Control, tools: VBoxContainer, center: VBoxContainer, right: VBoxContainer) -> void:
	app = owner
	document = app.document
	properties = right
	if not document.data.has("box"):
		var copy: Dictionary = document.data.duplicate(true)
		copy.box = {"template": "square", "thickness": 0.06, "faces": {}}
		document.replace(copy, "Добавить коробку")
	center.add_child(Style.heading("КОРОБКА ИГРЫ"))
	center.add_child(Style.label("ПКМ — вращать 3D · колесо — приблизить · грани — редактировать слои"))
	var row := Style.row(8)
	center.add_child(row)
	for part: String in ["", "front", "back", "spine", "top"]:
		var button := Style.button({"": "3D", "front": "Лицо", "back": "Задник", "spine": "Корешок", "top": "Верх"}[part])
		button.pressed.connect(func():
			app._box_face = part if not part.is_empty() else app._box_face
			app._box_mode_3d = part.is_empty()
			app._box_layer = -1
			app._render.call_deferred())
		row.add_child(button)
	preview = View.new()
	center.add_child(preview)
	preview.setup(document)
	preview.layer_index = app._box_layer
	preview.layer_moved.connect(func(index: int, rect: Array):
		document.set_value(["box", "faces", app._box_face, index, "rect"], rect, "Переместить слой коробки")
		app._render.call_deferred())
	preview.show_face("" if app._box_mode_3d else app._box_face)
	app._box_view = preview
	for kind: String in ["fill", "text", "image"]:
		var add := Style.button("+ " + {"fill": "Заливка", "text": "Текст", "image": "Картинки"}[kind])
		add.pressed.connect(func():
			if kind == "image":
				app._with_notice(func(): app._dialog(PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Изображения"]), true, _import))
			else:
				add_layer(kind))
		tools.add_child(add)
	tools.add_child(Style.label("Слои · снизу вверх"))
	var layers: Array = document.data.box.get("faces", {}).get(app._box_face, [])
	for index in layers.size():
		var layer: Dictionary = layers[index]
		var button := Style.button(("◉ " if layer.get("visible", true) else "○ ") + str(layer.get("title", layer.get("kind", "Слой"))))
		button.clip_text = true
		button.pressed.connect(func():
			app._box_layer = index
			app._render.call_deferred())
		tools.add_child(button)
	var bake := Style.button("Запечь и сохранить")
	bake.pressed.connect(func():
		bake.disabled = true
		var result: String = await preview.bake()
		if result.is_empty():
			await app._save()
			app._message = "Четыре грани запечены. Коробка обновится при возвращении в хаб."
		else:
			app._message = result
		app._status_text()
		if is_instance_valid(bake):
			bake.disabled = false)
	tools.add_child(bake)
	if app._box_layer >= 0 and app._box_layer < layers.size():
		_layer_properties(layers[app._box_layer])
	else:
		_metadata()

func add_layer(kind: String, asset: String = "") -> void:
	var copy: Dictionary = document.data.duplicate(true)
	if not copy.box.has("faces"):
		copy.box.faces = {}
	if not copy.box.faces.has(app._box_face):
		copy.box.faces[app._box_face] = []
	if copy.box.faces[app._box_face].size() >= 64:
		app._message = "На одной грани не больше 64 слоёв."
		app._status_text()
		return
	var dimensions := View.face_size(copy, app._box_face)
	var layer := {"kind": kind, "title": {"fill": "Заливка", "text": "Текст", "image": "Картинка"}[kind], "rect": [0, 0, dimensions.x, dimensions.y], "visible": true, "locked": false, "opacity": 1.0, "rotation": 0, "color": "#30263f" if kind == "text" else "#b7c9bd", "brightness": 0.0, "contrast": 1.0, "saturation": 1.0, "exposure": 0.0, "hue": 0.0}
	if kind == "text":
		layer.merge({"text": str(copy.meta.title), "font_size": 96, "align": "center", "outline": 0})
		layer.rect = [32, dimensions.y * 0.3, dimensions.x - 64, dimensions.y * 0.6]
	if kind == "image":
		layer["asset"] = asset
	copy.box.faces[app._box_face].append(layer)
	document.replace(copy, "Добавить слой коробки")
	app._box_layer = copy.box.faces[app._box_face].size() - 1
	app._box_mode_3d = false
	app._render.call_deferred()

func _import(paths: PackedStringArray) -> void:
	if paths.size() > 32:
		app._message = "За один импорт не больше 32 слоёв."
		app._status_text()
		return
	for path: String in paths:
		var imported := Assets.import_image(str(document.data.id), path, app._source)
		if not str(imported.error).is_empty():
			app._message = str(imported.error)
			app._status_text()
			break
		var copy: Dictionary = document.data.duplicate(true)
		copy.assets[imported.hash] = imported.asset
		document.replace(copy, "Импорт рисунка коробки")
		add_layer("image", str(imported.hash))

func _metadata() -> void:
	app._text(properties, "Название", ["meta", "title"])
	app._text(properties, "Описание", ["meta", "description"])
	app._text(properties, "Время партии", ["meta", "time"])
	app._number(properties, "Игроков от", ["meta", "players", 0], 2, 8)
	app._number(properties, "Игроков до", ["meta", "players", 1], 2, 8)
	app._number(properties, "Толщина", ["box", "thickness"], 0.04, 0.12, 0.01)
	app._choice(properties, "Форма", ["box", "template"], ["Квадратная", "Высокая", "Широкая", "Малая карточная"], ["square", "tall", "wide", "small"])
	properties.add_child(Style.label("Источник / лицензия новых картинок"))
	var source := LineEdit.new()
	source.text = app._source
	source.text_changed.connect(func(value: String): app._source = value)
	properties.add_child(source)

func _layer_properties(layer: Dictionary) -> void:
	var path: Array = ["box", "faces", app._box_face, app._box_layer]
	app._text(properties, "Название слоя", path + ["title"])
	for key: String in ["visible", "locked"]:
		var check := CheckBox.new()
		check.text = "Виден" if key == "visible" else "Заблокирован"
		check.button_pressed = bool(layer.get(key, key == "visible"))
		check.toggled.connect(func(value: bool):
			document.set_value(path + [key], value, "Состояние слоя")
			app._render.call_deferred())
		properties.add_child(check)
	if not layer.get("locked", false):
		for key: String in ["flip_x", "flip_y", "gradient"]:
			if key == "gradient" and layer.get("kind") != "fill":
				continue
			var flag := CheckBox.new()
			flag.text = {"flip_x": "Отразить по горизонтали", "flip_y": "Отразить по вертикали", "gradient": "Градиентная заливка"}[key]
			flag.button_pressed = bool(layer.get(key, false))
			flag.toggled.connect(func(value: bool):
				document.set_value(path + [key], value, "Отражение / градиент")
				app._render.call_deferred())
			properties.add_child(flag)
		if layer.get("kind") == "text":
			properties.add_child(Style.label("Текст"))
			var content := TextEdit.new()
			content.custom_minimum_size.y = 112
			content.text = str(layer.get("text", ""))
			content.text_changed.connect(func():
				document.set_value(path + ["text"], content.text.left(4096), "Текст слоя")
				app._status_text())
			properties.add_child(content)
			app._number(properties, "Размер шрифта", path + ["font_size"], 8, 512)
			app._choice(properties, "Выравнивание", path + ["align"], ["По центру", "Слева"], ["center", "left"])
			app._number(properties, "Обводка", path + ["outline"], 0, 16)
			var shadow := CheckBox.new()
			shadow.text = "Мягкая тень текста"
			shadow.button_pressed = bool(layer.get("shadow", false))
			shadow.toggled.connect(func(value: bool):
				document.set_value(path + ["shadow"], value, "Тень текста")
				app._status_text())
			properties.add_child(shadow)
			var labels: Array = Fonts.NAMES.duplicate()
			var ids: Array = Fonts.IDS.duplicate()
			for hash_value: String in document.data.get("assets", {}):
				var entry: Dictionary = document.data.assets[hash_value]
				if str(entry.get("path", "")).get_extension() in ["ttf", "otf"]:
					labels.append("Свой шрифт · " + hash_value.left(8))
					ids.append(hash_value)
			app._choice(properties, "Шрифт", path + ["font"], labels, ids)
			var import_font := Style.button("Импортировать шрифт")
			import_font.pressed.connect(func():
				app._with_notice(func(): app._dialog(PackedStringArray(["*.ttf,*.otf ; Шрифты"]), false, func(file_path: String):
					var imported := Assets.import_font(str(document.data.id), file_path, app._source)
					if not str(imported.error).is_empty():
						app._message = str(imported.error)
						app._status_text()
						return
					var copy: Dictionary = document.data.duplicate(true)
					copy.assets[imported.hash] = imported.asset
					copy.box.faces[app._box_face][app._box_layer]["font"] = imported.hash
					document.replace(copy, "Шрифт слоя коробки")
					app._render.call_deferred())))
			properties.add_child(import_font)
		if layer.get("kind") in ["fill", "text"]:
			var color := ColorPickerButton.new()
			color.color = Color.from_string(str(layer.get("color", "#30263f")), Color("30263f"))
			color.color_changed.connect(func(value: Color):
				document.set_value(path + ["color"], "#" + value.to_html(), "Цвет слоя")
				app._status_text())
			properties.add_child(color)
		if layer.get("gradient", false):
			properties.add_child(Style.label("Второй цвет градиента"))
			var second := ColorPickerButton.new()
			second.color = Color.from_string(str(layer.get("color2", "#30263f")), Color("30263f"))
			second.color_changed.connect(func(value: Color):
				document.set_value(path + ["color2"], "#" + value.to_html(), "Второй цвет градиента")
				app._status_text())
			properties.add_child(second)
		properties.add_child(Style.label("Умножить на цвет"))
		var tint := ColorPickerButton.new()
		tint.color = Color.from_string(str(layer.get("tint", "#ffffff")), Color.WHITE)
		tint.color_changed.connect(func(value: Color):
			document.set_value(path + ["tint"], "#" + value.to_html(), "Затемнение цветом")
			app._status_text())
		properties.add_child(tint)
		for index in 4:
			app._number(properties, ["X", "Y", "Ширина", "Высота"][index], path + ["rect", index], -2048 if index < 2 else 8, 4096, 8)
		app._number(properties, "Поворот", path + ["rotation"], -180, 180, 15)
		app._number(properties, "Прозрачность", path + ["opacity"], 0, 1, 0.05)
		for correction: Array in [["brightness", "Яркость", -1, 1, 0.0], ["contrast", "Контраст", 0, 2, 1.0], ["saturation", "Насыщенность", 0, 2, 1.0], ["exposure", "Экспозиция", -2, 2, 0.0], ["hue", "Оттенок", -180, 180, 0.0]]:
			if layer.has(correction[0]):
				app._number(properties, correction[1], path + [correction[0]], correction[2], correction[3], 15 if correction[0] == "hue" else 0.05)
		var reset := Style.button("Сбросить коррекцию")
		reset.pressed.connect(func():
			var copy: Dictionary = document.data.duplicate(true)
			var target: Dictionary = copy.box.faces[app._box_face][app._box_layer]
			target.merge({"brightness": 0.0, "contrast": 1.0, "saturation": 1.0, "exposure": 0.0, "hue": 0.0, "opacity": 1.0, "tint": "#ffffff"}, true)
			document.replace(copy, "Сбросить коррекцию слоя")
			app._render.call_deferred())
		properties.add_child(reset)
	var row := Style.row(8)
	properties.add_child(row)
	for direction: int in [-1, 1]:
		var button := Style.button("↓ Ниже" if direction < 0 else "↑ Выше")
		button.disabled = bool(layer.get("locked", false))
		button.pressed.connect(func():
			var copy: Dictionary = document.data.duplicate(true)
			var array: Array = copy.box.faces[app._box_face]
			var index: int = app._box_layer
			var target := index + direction
			if target >= 0 and target < array.size():
				array[index] = array[target]
				array[target] = layer.duplicate(true)
				document.replace(copy, "Порядок слоёв")
				app._box_layer = target
				app._render.call_deferred())
		row.add_child(button)
	var remove := Style.button("Удалить слой")
	remove.disabled = bool(layer.get("locked", false))
	remove.pressed.connect(func():
		var copy: Dictionary = document.data.duplicate(true)
		copy.box.faces[app._box_face].remove_at(app._box_layer)
		document.replace(copy, "Удалить слой")
		app._box_layer = -1
		app._render.call_deferred())
	properties.add_child(remove)
