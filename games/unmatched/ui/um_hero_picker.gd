extends OptionButton
## Локальная сортировка списка героев. Смена порядка сохраняет выбранного героя и не отправляет действие.

signal hero_selected(hero: String)
signal sort_changed(by_complexity: bool)
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Complexity := preload("res://games/unmatched/logic/um_complexity.gd")
var by_complexity := false
var hero := ""
var _sort: Button
var _header_icon: Texture2D


func _ready() -> void:
	var blank := Image.create(1, 28, false, Image.FORMAT_RGBA8)
	_header_icon = ImageTexture.create_from_image(blank)
	_sort = Button.new()
	_sort.name = "HeroSort"
	_sort.custom_minimum_size = Vector2(44, 28)
	_sort.size = _sort.custom_minimum_size
	_sort.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_sort.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_popup().add_child(_sort)
	get_popup().hide_on_item_selection = false
	_sort.pressed.connect(toggle_sort)
	get_popup().about_to_popup.connect(_place_sort)
	get_popup().size_changed.connect(_place_sort)
	item_selected.connect(func(index: int) -> void:
		if index == 0:
			toggle_sort()
			return
		hero = get_item_metadata(index)
		text = Roster.HEROES[hero].name
		get_popup().hide()
		hero_selected.emit(hero))
	_rebuild()


func configure(selected: String, complexity_order: bool = false) -> void:
	hero = selected
	by_complexity = complexity_order
	if is_node_ready(): _rebuild()


func ordered_heroes() -> Array:
	var result: Array = Roster.HEROES.keys()
	result.sort_custom(func(first: String, second: String) -> bool:
		var a: int = Complexity.level(first)
		var b: int = Complexity.level(second)
		if by_complexity and a != b: return a < b
		return str(Roster.HEROES[first].name).naturalnocasecmp_to(str(Roster.HEROES[second].name)) < 0)
	return result


func toggle_sort() -> void:
	by_complexity = not by_complexity
	_rebuild()
	_place_sort()
	sort_changed.emit(by_complexity)


func _rebuild() -> void:
	clear()
	add_icon_item(_header_icon, "Персонажи")
	get_popup().set_item_as_radio_checkable(0, false)
	for key: String in ordered_heroes():
		add_item("%s · %s" % [Roster.HEROES[key].name, Complexity.label(key)])
		set_item_metadata(item_count - 1, key)
		if key == hero: select(item_count - 1)
	if Roster.HEROES.has(hero): text = Roster.HEROES[hero].name
	_sort.tooltip_text = "Сортировать по алфавиту" if by_complexity else "Сортировать по сложности"
	get_popup().set_item_tooltip(0, _sort.tooltip_text)
	_sort.icon = _sort_icon(by_complexity)
	_sort.expand_icon = false


func _place_sort() -> void:
	if is_instance_valid(_sort):
		_sort.position = Vector2(maxf(0.0, get_popup().size.x - _sort.size.x - 6.0), 4.0)


func _sort_icon(alphabet: bool) -> Texture2D:
	var color := get_theme_color("font_color", "Button").to_html(false)
	var mark := '<path fill-rule="evenodd" d="M1 13L5 2h3l4 11H9l-.7-2H4.7L4 13ZM5.4 8.5h2.2L6.5 5Z"/><path d="M1 16h11v2L5 23h7v3H1v-2l7-5H1Z"/>' if alphabet else '<path fill="none" stroke="#%s" stroke-width="1.8" d="M11 3L13.8 10.2L21.5 10.5L15.5 15.2L17.5 23L11 18.6L4.5 23L6.5 15.2L.5 10.5L8.2 10.2Z"/>' % color
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="36" height="28" fill="#%s">%s<path d="M28 4h3v15l3-3 2 2-6.5 7-6.5-7 2-2 3 3Z"/></svg>' % [color, mark]
	var picture := Image.new()
	picture.load_svg_from_string(svg)
	return ImageTexture.create_from_image(picture)
