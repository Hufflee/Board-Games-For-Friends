extends "res://tests/test_room_watch29.gd"
## Чужая пользовательская коробка, которой нет в библиотеке наблюдателя; свой шкаф возвращается без изменения.

func _unit() -> void:
	await super._unit()
	var room: Node = hub._room
	var own: Dictionary = room.public_snapshot()
	var before: Array = room.boxes.duplicate()
	var id := "custom:12345678-1234-4234-8234-123456789abc"
	var snapshot := own.duplicate(true)
	snapshot.custom[id] = {"title": "Игра друга", "size": [0.04, 0.14, 0.14]}
	snapshot.placements.back().append(id)
	snapshot.poses[id] = 0
	check(not PublicRoom.clean(snapshot).is_empty(), "Метаданные чужой коробки разрешены без ассетов и кода")
	check(room.show_remote(snapshot), "Наблюдение комнаты с неизвестной коробкой работает")
	check(room.boxes.size() == before.size() + 1 and room.boxes.any(func(box): return str(box.game.id) == id), "В комнате создана временная коробка с названием")
	check(room.public_snapshot() == own, "Чужая коробка не публикуется как своя")
	room.focus_id(id)
	check(room.show_remote(own), "Обновление без пользовательской коробки безопасно убирает выделенный временный объект")
	check(room.show_remote(snapshot), "Пользовательская коробка может появиться снова без выхода из наблюдения")
	room.return_home()
	check(room.boxes == before and room.public_snapshot() == own, "Возврат восстановил все свои объекты и расстановку")
	var malicious := snapshot.duplicate(true)
	malicious.custom[id].size[0] = INF
	check(PublicRoom.clean(malicious).is_empty(), "Сетевой размер коробки проверен")
	malicious = snapshot.duplicate(true)
	malicious.custom["res://project.godot"] = malicious.custom[id]
	check(PublicRoom.clean(malicious).is_empty(), "Сетевые ID не становятся путями ресурсов")
	var props := ConfigFile.new()
	props.load("user://room_props.cfg")
	room._use_room_prop("vcr")
	props.load("user://room_props.cfg")
	check(props.get_value("room", "vcr_time", "") == room.VCR_TIMES[room._vcr_time], "Выбранное время приставки сохранено локально")
	var now := Time.get_time_dict_from_system()
	room._update_alarm_clock()
	check(room._alarm_clock.text == "%02d:%02d" % [now.hour, now.minute], "Будильник показывает местное время компьютера")
	var clock_bounds: AABB = room._alarm_clock.get_aabb()
	check(clock_bounds.size.x <= 0.14 and clock_bounds.size.y <= 0.05, "Цифры укладываются в лицевую панель будильника")
	var folder := "res://build/shots/room_custom03/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	# Здесь только кадры уже проверенного состояния: сетевое соединение закрыто базовым тестом.
	hub.set_process(false)
	net.set_process(false)
	for theme: String in ["light", "dark"]:
		root.get_node("Prefs").set_value("theme_mode", theme)
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "home_" + theme + ".png")
		room.show_remote(snapshot)
		hub._watch_peer = 2
		room.focus_id(id)
		await create_timer(0.8).timeout
		check(room.remote_view and is_instance_valid(room.focused) and room.focused.game.id == id, "Чужая коробка действительно остаётся раскрытой на кадре")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "remote_" + theme + ".png")
		room.return_home()
		hub._watch_peer = 0
