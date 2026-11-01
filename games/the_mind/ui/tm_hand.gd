extends PrivateHand
## Общая механика руки и K12TableCard; лица числовых карт рисуются элементами UI.

const Style := preload("res://games/the_mind/ui/tm_style.gd")

func _ready() -> void:
	custom_minimum_size = Vector2(100, card_size.y + 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry: Dictionary in entries:
		var key := str(entry.key)
		if not order.has(key):
			order.append(key)
		var card := K12TableCard.new(key, true, Style.face(int(entry.value)), card_size)
		card.draggable = movable
		card.back_drawer = Style.back
		_cards[key] = card
		add_child(card)
		card.clicked.connect(func(_c):
			drag_ended.emit()
			chosen.emit(entry))
		card.hovered.connect(func(c, on): _on_hover(c, on, entry))
		card.drag_started.connect(func(_c):
			_preview_token += 1
			preview_closed.emit()
			drag_began.emit(entry))
		card.dropped.connect(_dropped)
	order = order.filter(func(key): return _cards.has(key))
	resized.connect(_layout)
	_layout.call_deferred()
