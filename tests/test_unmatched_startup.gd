extends SceneTree
## Переход из лобби к первому ходу Unmatched через Net.
## Запуск: godot --audio-driver Dummy --path . --script res://tests/test_unmatched_startup.gd.
## Добавьте --headless для теста без окна или UM_STARTUP_SHOTS=1 для кадров в 1280×720.

const Rules := preload("res://games/unmatched/logic/um_rules.gd")

var _checks := 0
var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var net := root.get_node("Net")
	var prefs := root.get_node("Prefs")
	var scene: PackedScene = load("res://games/unmatched/ui/main.tscn")
	if scene == null or not scene.can_instantiate():
		quit(1)
		return
	prefs.window_mode = "windowed"
	prefs.resolution = "1280x720"
	for graphics in [0, 1, 2]:
		var mode := "светлая" if graphics % 2 == 0 else "тёмная"
		prefs.theme_mode = "light" if graphics % 2 == 0 else "dark"
		prefs.graphics = graphics
		prefs.apply()
		print("Графика %d, тема %s" % [graphics, mode])
		net.host_offline("unmatched")
		net.set_setting("um_arena", "heorot")
		net.set_setting("um_hero_mode", "free")
		net.set_setting("um_heroes", ["medusa", "arthur"])
		var app: Control = scene.instantiate()
		root.add_child(app)
		await _frames()
		await _play_first_action(app, net, graphics)
		net.end_game()
		await _frames()
		_check(not net.in_game and app._screen.find_child("LobbyPreview", true, false) != null,
			"После завершения партии снова открывается лобби")
		app.queue_free()
		await process_frame
		net.leave()
	print("Unmatched, запуск: %d проверок, %d ошибок" % [_checks, _errors])
	quit(1 if _errors else 0)


func _play_first_action(app: Control, net: Node, graphics: int) -> void:
	# Обновление лобби и запуск приходят до выполнения отложенных вызовов.
	net.set_setting("um_arena", "marmoreal")
	var message: String = net.start_game()
	_check(message.is_empty() and net.in_game, "Хост начал партию после изменения арены")
	var table: Control = app._screen
	await _frames()
	var same_table: bool = is_instance_valid(table) and app._screen == table
	_check(same_table and app._playing, "Отложенное обновление лобби сохраняет стол открытым")
	if not same_table or not app._playing:
		return
	_check(table._state == net.view and net.view.get("arena") == "marmoreal",
		"Стол получил начальное состояние выбранной арены с хоста")
	_check_board(app, table)
	if net.view.get("handoff", false):
		net.send_action("handoff", {})
	_check(not net.view.get("setup", {}).is_empty(), "После передачи управления доступна стартовая расстановка")
	for step in 12:
		if net.view.get("handoff", false):
			net.send_action("handoff", {})
		var setup: Dictionary = net.view.get("setup", {})
		if setup.is_empty():
			break
		var cells: Array = setup.get("cells", [])
		if cells.is_empty():
			break
		net.send_action("place", {"cell": cells[0]})
	await _frames()
	var first_turn: bool = net.view.get("can_act", false) and net.view.get("phase_id") == Rules.Phase.ACTION
	_check(first_turn and app._screen == table and table._state == net.view,
		"Первый ход открывается на том же столе после расстановки")
	_check_board(app, table)
	if not first_turn:
		return
	var actions: Rect2 = table._actions.get_global_rect()
	var board: Rect2 = table._board.get_global_rect()
	_check(table._actions.visible and actions.has_area() and is_equal_approx(actions.position.x, board.position.x),
		"Кнопки первого хода выровнены по игровому полю")
	if OS.get_environment("UM_STARTUP_SHOTS") == "1" and DisplayServer.get_name() != "headless":
		await _shot(graphics)
	net.send_action("maneuver", {})
	await _frames()
	_check(net.view.get("phase_id") == Rules.Phase.MANEUVER and app._screen == table and table._state == net.view,
		"Первое действие обновляет тот же стол")
	_check_board(app, table)


func _check_board(app: Control, table: Control) -> void:
	var board: Control = table._board
	var field: Rect2 = board._field_rect()
	var title: Label = table._arena_title
	var title_rect := title.get_global_rect()
	var board_rect := board.get_global_rect()
	_check(board.is_visible_in_tree() and board._board != null and not board._figures.is_empty()
		and field.has_area() and app.get_global_rect().encloses(board_rect),
		"Поле с текстурой и фишками видно в пределах окна")
	_check(not title.text.is_empty() and title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
		and is_equal_approx(title_rect.get_center().x, board_rect.get_center().x)
		and title_rect.end.y <= board_rect.position.y, "Название арены находится по центру над полем")


func _frames() -> void:
	for frame in 4:
		await process_frame


func _shot(graphics: int) -> void:
	var path := ProjectSettings.globalize_path("res://build/shots/unmatched_startup")
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	var filename := path.path_join("first_turn_%d.png" % graphics)
	_check(root.get_texture().get_image().save_png(filename) == OK, "Сохранён кадр первого хода")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_errors += 1
		push_error(message)
