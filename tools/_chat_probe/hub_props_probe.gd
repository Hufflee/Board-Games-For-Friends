extends SceneTree
## Проверка кнопок редактора шкафа (11.11): новый плакат, мяч вкл/выкл, ещё одна доска друзей, крестики снятия.
## Снимки — build/shots/hub_props_*.png. Запускать только с пустым профилем (APPDATA), чтобы не тронуть настоящий:
## APPDATA=<пустая папка> godot --audio-driver Dummy --resolution 1280x720 --path . --script res://tools/_chat_probe/hub_props_probe.gd

const Stickers := preload("res://hub/stickers.gd")

var _fails := 0


func check(ok: bool, message: String) -> void:
	print(("OK   " if ok else "FAIL ") + message)
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _find(node: Node, method: String) -> Node:
	if node.has_method(method):
		return node
	for child: Node in node.get_children():
		var found := _find(child, method)
		if found != null:
			return found
	return null


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/shots/hub_props_%s.png" % name))


func _run() -> void:
	change_scene_to_file("res://hub/hub.tscn")
	await create_timer(3.0).timeout
	var room := _find(root, "add_friend_board")
	var st: Node = root.get_node("Net/Stickers")
	check(room != null, "комната найдена")
	if room == null:
		quit(1)
		return
	room.open_shelf_editor()
	await create_timer(1.5).timeout
	check(_find(root, "_sync_ball") != null and _find(root, "_sync_ball").find_child("EditorAddBoard", true, false) != null, "в редакторе есть значки плаката, мяча и доски")
	await _shot("editor")
	# Доски
	room.add_friend_board()
	room.add_friend_board()
	await create_timer(1.0).timeout
	check(room.boards.size() == 3 and st.board_ids(0) == [0, 1, 2], "добавлены две пустые доски (%s)" % [st.board_ids(0)])
	var b1: Node3D = room.boards.get(1)
	var b2: Node3D = room.boards.get(2)
	check(b1 != null and b2 != null and Vector2(b1.position.x, b1.position.y).distance_to(Vector2(b2.position.x, b2.position.y)) > 0.3, "новые доски висят в разных местах")
	check(b1 != null and not room.shelf_wall_rect().intersects(Rect2(Vector2(b1.position.x, b1.position.y) - room.BOARD_EXTENT / 2.0, room.BOARD_EXTENT)), "новая доска не на шкафу")
	# Плакат
	var slot: int = st.free_poster_slot()
	check(slot == 3, "свободный номер нового плаката — 3")
	var image := Image.create(400, 300, false, Image.FORMAT_RGB8)
	image.fill(Color("3fa0ff"))
	st.set_poster_picture(slot, image, room.free_wall_spot(Vector2(0.5, 0.4)))
	await create_timer(0.8).timeout
	check(room.posters[3].visible and not room.posters[4].visible, "новый плакат появился, следующих нет")
	# Мяч
	room.set_ball_enabled(false)
	var cfg := ConfigFile.new()
	cfg.load("user://room_props.cfg")
	check(not room._ball.visible and cfg.get_value("ball", "on", true) == false, "мяч выключен и это сохранено")
	await _shot("added")
	# Крестик над доской и над плакатом
	room.sticker_board = b1
	room.board_held.emit()
	room.poster_held.emit(3)
	await create_timer(0.4).timeout
	var cross: Control = root.find_child("BoardRemove", true, false)
	var poster_cross: Control = root.find_child("PosterRemove", true, false)
	check(cross != null and cross.visible, "крестик над доской виден")
	check(poster_cross != null and poster_cross.visible, "крестик над плакатом виден")
	await _shot("crosses")
	# Снятие: доска с эмодзи, плакат, основная доска
	st._owner_add("steam:5", "Друг", 0, "gg", 0.5, 0.5, 0.0)
	check(st.board_of(0, 0).size() == 1, "на основной доске стикер друга")
	st.remove_board(1)
	st.remove_poster(0)
	st.remove_poster(3)
	st.remove_board(0)
	await create_timer(0.8).timeout
	check(room.boards.keys() == [2], "остались только незатронутые доски (%s)" % [room.boards.keys()])
	check(not room.posters[0].visible and not room.posters[3].visible and room.posters[1].visible, "снятые плакаты скрыты, остальные висят")
	var saved := Stickers.load_local()
	check(saved.get("board_gone", false) and saved.board.is_empty(), "основная доска снята вместе со стикерами (и в файле)")
	check(Stickers.poster_slots(saved) == [1, 2], "в файле висят плакаты 1 и 2")
	var back: int = st.add_board(Vector2(-1.0, 1.5))
	check(back == 0 and st.board_of(0, 0).is_empty(), "новая доска встаёт на место основной — пустая")
	check(st.free_poster_slot() == 0, "снятый стандартный плакат освобождает номер 0")
	room.set_ball_enabled(true)
	check(room._ball.visible, "мяч вернулся")
	await create_timer(0.6).timeout
	await _shot("after")
	room.finish_shelf_editor(false)
	print("ИТОГ: ошибок ", _fails)
	quit(1 if _fails > 0 else 0)
