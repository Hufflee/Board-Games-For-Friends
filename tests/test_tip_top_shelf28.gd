extends SceneTree
## Хаб создаёт только18+, старое сохранение не возвращает лишнюю коробку.
var errors := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var order = load("res://hub/shelf_layout.gd")
	check(order.save_rows([["tip_top"], ["tip_top_18"], []]) == OK, "Старое сохранение подготовлено")
	var scene: PackedScene = load("res://hub/hub.tscn")
	var hub := scene.instantiate()
	root.add_child(hub)
	current_scene = hub
	await create_timer(1.0).timeout
	var room = hub.get("_room")
	var ordinary := 0
	var adult := 0
	for box in room.boxes:
		ordinary += int(box.game.id == "tip_top")
		adult += int(box.game.id == "tip_top_18")
	check(ordinary == 0, "Обычная коробка отсутствует даже при старом сохранении")
	check(adult == 1, "Ровно одна коробка18+")
	var games = load("res://hub/games.gd")
	check(games.by_id("tip_top_18").variants == ["tip_top_18", "tip_top"], "Обе версии доступны переключателем")
	check(ResourceLoader.exists(games.by_id("tip_top").scene), "Обычная версия остаётся доступна")
	for row in room.get("_rows"):
		for box in row:
			check(box.game.id != "tip_top", "Старая раскладка отфильтрована")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/batch28_hub/tip-top.png")
	hub.queue_free()
	await process_frame
	print("ТИПТОП28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
