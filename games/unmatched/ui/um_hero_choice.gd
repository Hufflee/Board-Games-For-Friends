extends Control
## Выбор стартового героя по образцу Four Souls: крупные карты над затемнённым столом.

signal chosen(hero: String)

const Style := preload("res://games/unmatched/ui/um_style.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Complexity := preload("res://games/unmatched/logic/um_complexity.gd")
const HeroCards := preload("res://games/unmatched/ui/um_hero_cards.gd")

var _title: Label
var _row: HBoxContainer
var _offers: Array = []
var _tiles: Array[Button] = []


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	z_index = 84
	var shade := ColorRect.new()
	shade.color = Color(0.10, 0.07, 0.10, 0.70)
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var group := VBoxContainer.new()
	group.mouse_filter = MOUSE_FILTER_IGNORE
	group.add_theme_constant_override("separation", 24)
	center.add_child(group)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", Style.TITLE)
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color("fff2e2"))
	group.add_child(_title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 24)
	group.add_child(_row)
	resized.connect(_size_tiles)
	hide()


func sync(offers: Array, remaining: int, waiting: String) -> void:
	_title.text = "Выберите персонажа" if not offers.is_empty() else "Выбирает %s · осталось %d" % [waiting, remaining]
	if _offers == offers:
		return
	_offers = offers.duplicate()
	for tile: Button in _tiles:
		_row.remove_child(tile)
		tile.queue_free()
	_tiles.clear()
	for hero: String in _offers:
		var tile := Button.new()
		tile.tooltip_text = Roster.HEROES[hero].name
		tile.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		var margin := MarginContainer.new()
		margin.mouse_filter = MOUSE_FILTER_IGNORE
		for side: String in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 12)
		var details := VBoxContainer.new()
		details.mouse_filter = MOUSE_FILTER_IGNORE
		details.add_theme_constant_override("separation", 4)
		margin.add_child(details)
		var ink := get_theme_color("font_color", "Button")
		var hero_name := Label.new()
		hero_name.name = "HeroName"
		hero_name.text = Roster.HEROES[hero].name
		hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hero_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hero_name.add_theme_font_override("font", Style.TITLE)
		hero_name.add_theme_font_size_override("font_size", 24)
		hero_name.add_theme_color_override("font_color", ink)
		details.add_child(hero_name)
		var difficulty := Label.new()
		difficulty.name = "HeroDifficulty"
		difficulty.text = Complexity.label(hero)
		difficulty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		difficulty.add_theme_font_size_override("font_size", 16)
		difficulty.add_theme_color_override("font_color", ink)
		details.add_child(difficulty)
		var cards := HeroCards.new()
		cards.name = "HeroCards"
		cards.show_hero(hero)
		cards.size_flags_vertical = SIZE_EXPAND_FILL
		details.add_child(cards)
		tile.add_child(margin)
		_row.add_child(tile)
		_tiles.append(tile)
		margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		tile.pressed.connect(func(): chosen.emit(hero))
		tile.mouse_entered.connect(_highlight.bind(tile))
		tile.mouse_exited.connect(_highlight.bind(null))
		tile.focus_entered.connect(_highlight.bind(tile))
		tile.focus_exited.connect(_highlight.bind(null))
	_size_tiles()


func _size_tiles() -> void:
	var columns := maxi(1, _tiles.size())
	var width := clampf(minf((size.x - 72.0 - 24.0 * (columns - 1)) / columns,
		(size.y - 180.0) * HeroCards.PAIR_RATIO), 172.0, 420.0)
	for tile: Button in _tiles:
		tile.custom_minimum_size = Vector2(width, width / HeroCards.PAIR_RATIO + 76.0)


func _highlight(current: Button) -> void:
	for tile: Button in _tiles:
		var cards := tile.find_child("HeroCards", true, false) as HeroCards
		cards.pivot_offset = cards.size * 0.5
		if tile.has_meta("hover_tween"):
			var previous: Tween = tile.get_meta("hover_tween")
			previous.kill()
		var active := tile == current
		tile.z_index = int(active)
		var tween := tile.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tile.set_meta("hover_tween", tween)
		tween.tween_property(cards, "scale", Vector2.ONE * (1.03 if active and not Prefs.reduce_motion else 1.0), 0.13)
		tween.tween_property(cards, "modulate", Color(0.75, 0.72, 0.71) if current != null and not active else Color.WHITE, 0.13)
