extends Control
## Просмотр публичного каталога карт без доступа к раздаче и текущим колодам.
## На странице загружаются только12 изображений, поиск и фильтры работают по метаданным.
const PAGE_SIZE := 12
const CORNERS := preload("res://hub/card_corners.gdshader")
var entries: Array = []
var _filtered: Array = []
var _page := 0
var _query: LineEdit
var _group: OptionButton
var _edition: OptionButton
var _grid: GridContainer
var _preview: TextureRect
var _caption: Label
var _count: Label
var _previous: Button
var _next: Button

static func open(parent: Control, title: String, cards: Array, panel_style: StyleBox) -> Control:
	var browser = load("res://hub/card_pool_browser.gd").new()
	browser.entries = cards
	browser.name = "CardPool"
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser.z_index = 120
	parent.add_child(browser)
	browser._build(title, panel_style)
	return browser

func _build(title: String, panel_style: StyleBox) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	margin.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 30)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(queue_free)
	heading.add_child(close)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 12)
	column.add_child(filters)
	_query = LineEdit.new()
	_query.placeholder_text = "Найти карту…"
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.text_changed.connect(func(_text): _filter())
	filters.add_child(_query)
	_group = OptionButton.new()
	_group.add_item("Все типы")
	var groups: Array = []
	for entry: Dictionary in entries:
		if not groups.has(entry.group):
			groups.append(entry.group)
	groups.sort()
	for group: String in groups:
		_group.add_item(group)
	_group.item_selected.connect(func(_index): _filter())
	filters.add_child(_group)
	_edition = OptionButton.new()
	for text in ["Все карты", "Базовые", "Дополнения"]:
		_edition.add_item(text)
	_edition.visible = entries.any(func(entry): return entry.has("base"))
	_edition.item_selected.connect(func(_index): _filter())
	filters.add_child(_edition)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 300
	body.add_child(detail)
	_preview = _image(Vector2(300, 370))
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_preview)
	_caption = Label.new()
	_caption.custom_minimum_size = Vector2(300, 54)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 18)
	detail.add_child(_caption)
	var rotate := Button.new()
	rotate.text = "Повернуть карту"
	rotate.pressed.connect(func():
		_preview.pivot_offset = _preview.size * 0.5
		_preview.rotation = 0.0 if _preview.rotation != 0.0 else PI)
	detail.add_child(rotate)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_previous = Button.new()
	_previous.text = "← Назад"
	_previous.pressed.connect(func(): _page -= 1; _render())
	footer.add_child(_previous)
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 14)
	footer.add_child(_count)
	_next = Button.new()
	_next.text = "Дальше →"
	_next.pressed.connect(func(): _page += 1; _render())
	footer.add_child(_next)
	_filter()

func _image(minimum: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.custom_minimum_size = minimum
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mask := ShaderMaterial.new()
	mask.shader = CORNERS
	image.material = mask
	return image

func _filter() -> void:
	var text := _query.text.strip_edges().to_lower()
	_filtered = entries.filter(func(entry):
		return (text.is_empty() or str(entry.title).to_lower().contains(text)) and (_group.selected == 0 or entry.group == _group.get_item_text(_group.selected)) and (_edition.selected == 0 or bool(entry.get("base", true)) == (_edition.selected == 1)))
	_page = 0
	_render()

func _render() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var pages := maxi(1, ceili(float(_filtered.size()) / PAGE_SIZE))
	_page = clampi(_page, 0, pages - 1)
	_previous.disabled = _page == 0
	_next.disabled = _page == pages - 1
	_count.text = "Карт: %d · Страница %d из %d · Каталог, не текущая колода" % [_filtered.size(), _page + 1, pages]
	_preview.texture = null
	_caption.text = "Ничего не найдено" if _filtered.is_empty() else "Наведите на карту или нажмите её"
	for index in range(_page * PAGE_SIZE, mini((_page + 1) * PAGE_SIZE, _filtered.size())):
		var entry: Dictionary = _filtered[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(144, 230)
		button.tooltip_text = ""  # вместо тултипа — крупный просмотр
		_grid.add_child(button)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(col)
		var image := _image(Vector2(144, 194))
		image.texture = load(entry.path)
		col.add_child(image)
		var label := Label.new()
		label.text = entry.title
		label.custom_minimum_size.x = 144
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", 14)
		col.add_child(label)
		var show_card := func():
			_preview.rotation = 0.0
			_preview.texture = image.texture
			_caption.text = entry.title
		button.mouse_entered.connect(show_card)
		button.pressed.connect(show_card)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
