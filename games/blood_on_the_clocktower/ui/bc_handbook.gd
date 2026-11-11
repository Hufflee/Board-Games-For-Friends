extends Control
## Общедоступный справочник Clocktower: получает только каталог, без состояния партии.
## Отдельное окно для будущей кнопки «Справочник». Проверка: tests/test_blood_on_the_clocktower_ui.gd.

signal closed
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
const Style := preload("res://games/blood_on_the_clocktower/ui/bc_style.gd")
const Art := preload("res://games/blood_on_the_clocktower/ui/bc_art.gd")
var edition := "tb"
var query := ""
var _cards: GridContainer
var _tabs: Dictionary = {}
var _search: LineEdit
var _count: Label
var _scroll: ScrollContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	var background := ColorRect.new()
	background.color = Style.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	var title := Style.label("Справочник", Style.H1, Style.INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Style.button("Закрыть", Style.SMALL)
	close.name = "Close"
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)
	var description := Style.label("Все возможные роли. Этот список не раскрывает скрытый состав вашей партии.", Style.SMALL, Style.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for id: String in Data.EDITIONS:
		var tab := Style.button(str(Data.EDITIONS[id].name))
		tab.name = "Edition_" + id
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_edition.bind(id))
		tabs.add_child(tab)
		_tabs[id] = tab
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 16)
	column.add_child(search_row)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Поиск: роль, способность, отравление…"
	_search.max_length = 100
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_search_changed)
	search_row.add_child(_search)
	_count = Style.label("", Style.SMALL, Style.MUTED)
	search_row.add_child(_count)
	_scroll = ScrollContainer.new()
	_scroll.name = "RolesScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_cards = GridContainer.new()
	_cards.name = "RoleCards"
	_cards.columns = 2
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 16)
	_cards.add_theme_constant_override("v_separation", 16)
	_scroll.add_child(_cards)
	var reminder := Style.label(
		"Смерть не раскрывает роль. Мёртвый может говорить и имеет один последний голос.\n" +
		"Номинируют только живые, по одному разу в день. При равенстве лидеров казнь не происходит.\n" +
		"Отравление даёт гарантированную дезинформацию. При опьянении рассказчик решает, дать верную или ложную информацию.",
		Style.SMALL, Style.MUTED)
	reminder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(reminder)
	resized.connect(_layout)
	_layout()
	_rebuild()

func _select_edition(id: String) -> void:
	edition = id
	query = ""
	_search.text = ""
	_scroll.scroll_vertical = 0
	_rebuild()

func _search_changed(text: String) -> void:
	query = text
	_scroll.scroll_vertical = 0
	_rebuild()

func _layout() -> void:
	if _cards != null:
		_cards.columns = 2 if size.x >= 1000 else 1

func _rebuild() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for id: String in _tabs:
		var tab: Button = _tabs[id]
		var fill := Style.ACCENT if id == edition else Style.PANEL
		tab.add_theme_stylebox_override("normal", Style.box(fill))
		tab.add_theme_stylebox_override("hover", Style.box(fill.lightened(0.08)))
	var cards: Array = Data.handbook(edition, query)
	_count.text = "%d ролей" % cards.size()
	if cards.is_empty():
		_cards.add_child(Style.label("Ничего не найдено. Измените запрос.", Style.BODY, Style.MUTED))
	for card: Dictionary in cards:
		var panel := PanelContainer.new()
		panel.name = "Role_" + str(card.id)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", Style.box())
		_cards.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		panel.add_child(row)
		var icon := TextureRect.new()
		icon.name = "RoleIcon"
		icon.texture = Art.role(str(card.id))
		icon.custom_minimum_size = Vector2(64, 64)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var heading := Style.label(str(card.name), Style.BODY, Style.INK, true)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(heading)
		column.add_child(Style.label(str(Data.TYPES[card.type]), Style.SMALL, Style.MUTED))
		var text := Style.label(str(card.text))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(text)
