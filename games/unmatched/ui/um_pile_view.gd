extends VBoxContainer
## Счётчики и просмотр колод и сбросов. Стол подключает сигнал к общему просмотру карт.

signal preview_requested(card: Dictionary)
signal preview_closed

const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Piles := preload("res://hub/card_piles.gd")

var _rows: GridContainer
var _browser: PanelContainer
var _heading: Label
var _scroll: ScrollContainer
var _empty: Label
var _cards: GridContainer
var _piles: Array = []
var _opened := -1
var _opened_stack := "discard"
var _preview_rng := RandomNumberGenerator.new()
var float_browser := false
var columns := 1


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_rows = GridContainer.new()
	_rows.columns = columns
	_rows.add_theme_constant_override("h_separation", 8)
	_rows.add_theme_constant_override("v_separation", 8)
	add_child(_rows)
	_browser = PanelContainer.new()
	_browser.top_level = float_browser
	_browser.z_index = 12
	_browser.hide()
	add_child(_browser)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	_browser.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	_heading = Label.new()
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(_close)
	header.add_child(close)
	_empty = Label.new()
	_empty.text = "Сброс пуст"
	body.add_child(_empty)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 176)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_cards = GridContainer.new()
	_cards.columns = 3
	_cards.add_theme_constant_override("h_separation", 8)
	_cards.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_cards)
	_update_rows()


func present(piles: Array) -> void:
	var previous := _piles
	_piles = piles.duplicate(true)
	if not is_node_ready():
		return
	_update_rows()
	if _opened >= _piles.size():
		_close()
	elif _opened >= 0 and previous[_opened].get(_opened_stack, []) != _piles[_opened].get(_opened_stack, []):
		_fill_browser()


func _update_rows() -> void:
	while _rows.get_child_count() > _piles.size():
		var row := _rows.get_child(_rows.get_child_count() - 1)
		_rows.remove_child(row)
		row.queue_free()
	for seat in _piles.size():
		var row: HBoxContainer
		if seat >= _rows.get_child_count():
			row = HBoxContainer.new()
			row.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation", 8)
			var hero := Label.new()
			hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hero.clip_text = true
			hero.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.add_child(hero)
			var deck := Button.new()
			deck.pressed.connect(_open.bind(seat, "deck"))
			row.add_child(deck)
			var open := Button.new()
			open.pressed.connect(_open.bind(seat, "discard"))
			row.add_child(open)
			_rows.add_child(row)
		else:
			row = _rows.get_child(seat)
		var pile: Dictionary = _piles[seat]
		(row.get_child(0) as Label).text = _hero_name(seat)
		(row.get_child(0) as Label).tooltip_text = _hero_name(seat)
		(row.get_child(1) as Button).text = "Колода %d" % int(pile.deck_count)
		(row.get_child(2) as Button).text = "Сброс %d" % pile.discard.size()


func _hero_name(seat: int) -> String:
	return str(Roster.HEROES.get(_piles[seat].hero, {}).get("name", "Игрок %d" % (seat + 1)))


func _open(seat: int, stack: String) -> void:
	_opened = seat
	_opened_stack = stack
	_fill_browser()
	_browser.show()
	if float_browser:
		_browser.reset_size()
		_browser.global_position = Vector2(maxf(8.0, global_position.x - _browser.size.x - 8.0), global_position.y)


func _fill_browser() -> void:
	preview_closed.emit()
	var is_deck := _opened_stack == "deck"
	var title := "Колода" if is_deck else "Сброс"
	_heading.text = "%s · %s" % [title, _hero_name(_opened)]
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var cards: Array = _piles[_opened].get(_opened_stack, []).duplicate()
	if is_deck:
		Piles.shuffle(cards, _preview_rng)
	_empty.text = "Колода пуста" if is_deck else "Сброс пуст"
	_empty.visible = cards.is_empty()
	_scroll.visible = not cards.is_empty()
	_scroll.scroll_vertical = 0
	for card: Dictionary in cards:
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(72, 100)
		var poster := TextureRect.new()
		poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
		poster.texture = Art.face(card)
		Art.round_corners(poster)
		tile.add_child(poster)
		poster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
		tile.mouse_entered.connect(_preview.bind(card))
		tile.mouse_exited.connect(func(): preview_closed.emit())
		tile.focus_entered.connect(_preview.bind(card))
		tile.pressed.connect(_preview.bind(card))
		_cards.add_child(tile)


func _preview(card: Dictionary) -> void:
	preview_requested.emit(card.duplicate(true))


func _close() -> void:
	_opened = -1
	_browser.hide()
	preview_closed.emit()
