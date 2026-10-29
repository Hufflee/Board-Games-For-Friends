extends "res://tests/test_room_watch29.gd"
## Отдельные границы возврата и одинаковых снимков; запуск как исходного runtime-теста.
func _unit() -> void:
	await super._unit()
	hub.set_process(false)
	net.set_process(false)
	var room: Node = hub._room
	room._editor_preferences = room._shelf_ids().duplicate(true)
	room._editor_preferences.reverse()
	room._editor_preference_geometry = {"cols": 3, "cups": 0}
	var preferences: Array = room._editor_preferences.duplicate(true)
	var geometry: Dictionary = room._editor_preference_geometry.duplicate(true)
	var own: Dictionary = room.public_snapshot()
	var remote: Dictionary = own.duplicate(true)
	remote.selected = "gloom"
	remote.editor = true
	net.mode = "enet"
	net.lobby_view = {"members": [{"peer": 1, "name": "Я", "kind": "host"}, {"peer": 2, "name": "Друг", "kind": "human"}, {"peer": 3, "name": "Другой", "kind": "human"}]}
	net.public_rooms = {2: remote.duplicate(true), 3: remote.duplicate(true)}
	hub._watch_room(2)
	check(room.focused != null and room.focused.game.id == "gloom", "Первый одинаковый снимок выбирает игру")
	hub._toggle_watch_follow(true)
	room.focus_id("brodilka")
	hub._toggle_watch_follow(false)
	check(room.focused != null and room.focused.game.id == "gloom", "Follow ON после локального выбора восстанавливает неизменённый выбор владельца")
	hub._toggle_watch_follow(true)
	room.focus_id("brodilka")
	hub._watch_room(3)
	check(hub._watch_peer == 3 and room.focused != null and room.focused.game.id == "gloom", "Переключение одинаковых снимков сбрасывает местный выбор")
	check(room.public_snapshot() == own, "После переключений публикуется только свой снимок")
	check(not room._editor_on, "Чужой editor true не открывает локальный редактор")
	hub._watch_home(false)
	check(room._editor_preferences == preferences and room._editor_preference_geometry == geometry, "Нестандартные preferred placements и геометрия сохранены")
	check(room.public_snapshot() == own, "После дома собственный снимок полностью восстановлен")
	net.mode = ""
	net.public_rooms.clear()

