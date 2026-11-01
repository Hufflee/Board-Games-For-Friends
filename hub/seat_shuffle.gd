class_name SeatShuffle
extends RefCounted
## Настройка лобби «Перемешать игроков»: при старте партии места за столом (порядок ходов)
## выпадают случайно. Хранится в Net.settings["shuffle_seats"], тасует Net.start_game.


## Строка для лобби. make_button(text, size) -> Button, make_label(text, size) -> Label — в стиле игры.
static func settings_row(make_button: Callable, make_label: Callable) -> Control:
	var on := bool(Net.lobby_view.get("settings", {}).get("shuffle_seats", false))
	var row := HBoxContainer.new()
	row.name = "SeatShuffle"
	row.add_theme_constant_override("separation", 6)
	if not Net.is_host():
		row.add_child(make_label.call("Места: %s" % ("перемешаются при старте" if on else "по порядку входа"), 15))
		return row
	row.add_child(make_label.call("Места:", 15))
	for value: bool in [false, true]:
		var b: Button = make_button.call("Перемешать игроков" if value else "По порядку", 14)
		UISel.pick(b, on == value)
		b.tooltip_text = "Порядок мест и ходов — случайный при каждом старте" if value else "Места — в порядке входа в комнату"
		b.pressed.connect(func(): Net.set_setting("shuffle_seats", value))
		row.add_child(b)
	return row
