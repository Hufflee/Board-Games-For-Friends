extends SceneTree
## Публичный снимок и временная комната; RW_ROLE включает управляемый ENet-сценарий.
var PublicRoom: GDScript
var hub: Node
var net: Node
var checks := 0
var errors := 0
var command_id := -1
var role := ""
var out := "res://build/room_watch29"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	PublicRoom = load("res://hub/public_room.gd")
	role = OS.get_environment("RW_ROLE")
	hub = load("res://hub/hub.gd").new()
	root.add_child(hub)
	await create_timer(0.8).timeout
	if role == "visual":
		await _visual()
		return
	if role != "":
		net.my_name = role
		if role == "host":
			net.host_enet(24879, "")
		else:
			net.join_enet("127.0.0.1", 24879)
		# У каждого своя отличимая конфигурация и собственный файл.
		var poses: Dictionary = hub._room._box_modes.duplicate(true)
		poses["word_slam"] = 0 if role == "host" else 1
		hub._room._box_modes = poses
		hub._room._reflow(false)
		hub._room._save_shelf()
		while true:
			await create_timer(0.1).timeout
			await _command()
			_write_state()
	else:
		await _unit()
		print("ROOM_WATCH ", checks, "/", errors)
		hub.queue_free()
		await process_frame
		quit(1 if errors else 0)

func _unit() -> void:
	var room: Node = hub._room
	var own: Dictionary = room.public_snapshot()
	check(not own.is_empty(), "Собственный снимок проходит whitelist")
	var secret := own.duplicate(true)
	secret["hand"] = ["секрет"]
	secret.config["password"] = "секрет"
	var clean: Dictionary = PublicRoom.clean(secret)
	check(not clean.has("hand") and not clean.config.has("password"), "Тайные поля исключены")
	for mutate in ["bad_id", "nan", "inf", "rows", "duplicate", "pose", "type", "oversize", "selected"]:
		var bad := own.duplicate(true)
		match mutate:
			"bad_id": bad.placements[0][0] = "res://секрет"
			"nan": bad.config.width = NAN
			"inf": bad.config.height = INF
			"rows": bad.config.rows = 99
			"duplicate": bad.placements[0].append(bad.placements[0][0])
			"pose": bad.poses[bad.placements[0][0]] = 10
			"type": bad.config.width = "строка"
			"oversize": bad["secret"] = "x".repeat(20000)
			"selected": bad.selected = "нет_такой_игры"
		check(PublicRoom.clean(bad).is_empty(), "Отклонён снимок: " + mutate)
	room._save_shelf()
	var config: Dictionary = room._cabinet.duplicate(true)
	var prefs: Array = room._editor_preferences.duplicate(true)
	var geometry: Dictionary = room._editor_preference_geometry.duplicate(true)
	var before := FileAccess.get_sha256(ProjectSettings.globalize_path(ShelfConfig.FILE))
	var remote := own.duplicate(true)
	remote.poses.word_slam = 0
	remote.selected = "word_slam"
	remote.editor = true
	check(room.show_remote(remote), "Чужой снимок применён")
	check(room.focused.game.id == "word_slam" and not room._editor_on, "Выбор повторён, местный редактор закрыт")
	check(room.public_snapshot() == own, "Чужой снимок не перепубликуется")
	var variant: Dictionary = remote.duplicate(true)
	variant.selected = "tip_top"
	check(room.show_remote(variant) and room.focused.game.id == "tip_top", "Выбор варианта общей коробки повторяется")
	room.show_remote(remote)
	room.open_shelf_editor()
	check(not room._editor_on and room._save_shelf() == ERR_UNAUTHORIZED, "Запись и редактор заблокированы")
	room.remote_follow = false
	remote.selected = "gloom"
	check(room.show_remote(remote, false) and room.focused.game.id == "word_slam", "Отключение действий сохраняет местный выбор")
	room.return_home()
	check(room._cabinet == config and room._editor_preferences == prefs and room._editor_preference_geometry == geometry, "Домой восстанавливает исходные предпочтения")
	check(room._shelf_ids() == own.placements, "Все ID восстановлены")
	check(room.boxes.any(func(box): return box.game.get("id", "") == "tip_top_18"), "Домой восстанавливает собственный вариант коробки")
	check(FileAccess.get_sha256(ProjectSettings.globalize_path(ShelfConfig.FILE)) == before, "Чужая комната не записана на диск")
	# Прямой вызов RPC без авторизованного отправителя не принимается.
	net.host_enet(24880, "")
	net._rpc_publish_room(remote)
	check(net._room_pending.is_empty(), "Неавторизованный peer отклонён")
	net.publish_public_room(own)
	net.publish_public_room(remote)
	check(net._room_pending.size() == 1 and net._room_pending[1] == remote, "Частые изменения объединяются до последнего")
	net._flush_public_rooms(0.3)
	check(net.public_rooms.get(1, {}) == remote, "Финальный снимок доставлен после ограничения частоты")
	net.leave()
	check(net.public_rooms.is_empty() and net._room_pending.is_empty(), "Разрыв очищает снимки и очередь")

func _visual() -> void:
	# Изолированный макет пати для финального осмотра обеих тем; ENet проверен отдельно.
	hub.set_process(false)
	net.set_process(false)
	net.mode = "enet"
	net.lobby_view = {"members": [{"peer": 1, "name": "Моя комната", "kind": "host"}, {"peer": 2, "name": "Друг", "kind": "human"}], "mode": "enet"}
	net.public_rooms[2] = hub._room.public_snapshot()
	net.public_rooms[2].selected = "gloom"
	net.public_rooms[2].editor = true
	for mode in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = mode
		hub._rebuild()
		await process_frame
		await _click(hub.find_child("RoomEye2", true, false))
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/visual-%s.png" % mode)
		check(hub._watch_peer == 2 and hub._room.remote_view, "Глаз нажат через ввод мыши")
		await _click(hub.find_child("RoomHome", true, false))
		check(hub._watch_peer == 0 and not hub._room.remote_view, "Домик нажат через ввод мыши")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/home-%s.png" % mode)
	print("ROOM_VISUAL ", checks, "/", errors)
	net.mode = ""
	hub.queue_free()
	await process_frame
	quit(1 if errors else 0)

func _command() -> void:
	var path := out + "/" + role + "-command.json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("id", -1)) <= command_id:
		return
	command_id = int(data.id)
	match str(data.get("op", "")):
		"select": hub._room.focus_id(str(data.game))
		"pose":
			hub._room._box_modes["word_slam"] = int(data.value)
			hub._room._reflow(false)
		"geometry":
			hub._room.open_shelf_editor()
			var cfg: Dictionary = hub._room._cabinet.duplicate(true)
			cfg.width = float(cfg.width) + 0.01
			hub._room.request_shelf_geometry(cfg)
		"click_eye": await _click(hub.find_child("RoomEye%d" % int(data.peer), true, false))
		"click_home": await _click(hub.find_child("RoomHome", true, false))
		"click_follow": await _click(hub.find_child("RoomFollow", true, false))
		"click_box":
			for box in hub._room.boxes:
				if str(box.game.get("id", "")) == str(data.game):
					await _click_at(hub._room.camera.unproject_position(box.global_position))
		"shot":
			await create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out + "/" + str(data.file))
		"leave": net.leave()
		"quit":
			net.leave()
			quit()

func _click(control: Control) -> void:
	if control == null:
		push_error("Не найдена кнопка")
		return
	await _click_at(control.get_global_rect().get_center())

func _click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _write_state() -> void:
	var rooms := {}
	for peer in net.public_rooms:
		rooms[str(peer)] = net.public_rooms[peer]
	var state := {"id": command_id, "peer": multiplayer_id(), "rooms": rooms, "party": net.is_party(),
		"watch": hub._watch_peer, "follow": hub._watch_follow, "remote": hub._room.remote_view,
		"selected": str(hub._room.focused.game.get("id", "")) if hub._room.focused != null else "",
		"config": hub._room._cabinet, "placements": hub._room._shelf_ids(), "poses": hub._room._box_modes,
		"local_editor": hub._room._editor_on, "connection": root.get_multiplayer().multiplayer_peer.get_connection_status(), "members": net.members,
		"file_hash": FileAccess.get_sha256(ProjectSettings.globalize_path(ShelfConfig.FILE))}
	var path := out + "/" + role + "-state.json"
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func multiplayer_id() -> int:
	return root.get_multiplayer().get_unique_id()
