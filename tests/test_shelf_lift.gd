extends SceneTree
## Шкаф: выделенная коробка выдвигается (место занимают соседи), поворот в «полёте», возврат и перенос,
## отмена в редакторе (Ctrl+Z).
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_shelf_lift.gd

var room: Node
var checks := 0
var errors := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: " + text)


func _initialize() -> void:
	_run.call_deferred()


func box_of(id: String) -> Node:
	for box in room.boxes:
		if room._shelf_id(box) == id:
			return box
	return null


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	room = load("res://hub/neon_room.gd").new()
	root.add_child(room)
	await create_timer(1).timeout
	var before: Array = room._shelf_ids().duplicate(true)
	var id := ""
	var cell := -1
	for r in before.size():
		for candidate: String in before[r]:
			var found: Node = box_of(candidate)
			if id == "" and (before[r] as Array).size() >= 3 and not found.is_figurine() and not found.is_cups():
				id = candidate
				cell = r
	check(id != "", "Нашлась коробка для проверки")
	var box: Node = box_of(id)
	var index: int = (before[cell] as Array).find(id)
	var mode_before := int(room._box_modes.get(id, 1))
	# выделение выдвигает коробку
	room._select_shelf_box(box)
	check(room._lift_box == box, "Выделенная коробка выдвинута")
	check(not (room._rows[cell] as Array).has(box), "Её место на полке освобождено для соседей")
	check(room._shelf_ids() == before or room._cabinet.get("neighbor_order", false), "В сохранении коробка числится на прежнем месте")
	check((room._shelf_ids()[cell] as Array).has(id), "Снимок шкафа не теряет выдвинутую коробку")
	var home_z: float = box.home.origin.z
	await create_timer(0.6).timeout
	check(box.position.z > home_z + 0.05, "Коробка висит перед полкой")
	# клик мимо — возврат на место
	room._clear_shelf_selection()
	check(room._lift_box == null and (room._rows[cell] as Array).find(box) == index, "Снятие выделения возвращает коробку на прежнее место")
	# поворот в полёте и перенос на другое место той же полки
	room._select_shelf_box(box)
	room._cycle_box_pose()
	check(int(room._box_modes.get(id, 1)) != mode_before and room._lift_box == box, "В полёте положение меняется, коробка остаётся выдвинутой")
	room._box_modes[id] = mode_before
	room._pressed_box = box
	room._start_drag()
	check(room._drag_box == box and room._lift_box == null, "Удержание выдвинутой коробки начинает перенос")
	room._drag_to = Vector2i(cell, 0)
	room._drag_cascade = []
	room._finish_drag(true)
	check((room._rows[cell] as Array).find(box) == 0, "Коробка поставлена на новое место")
	check(room._selected_box == null, "После установки выделение снято")
	# редактор: отмена
	room.open_shelf_editor()
	var draft: Array = room._shelf_ids().duplicate(true)
	check(not room.can_undo_shelf(), "В начале редактирования отменять нечего")
	room._select_shelf_box(box)
	room._pressed_box = box
	room._start_drag()
	room._drag_to = Vector2i(cell, (room._rows[cell] as Array).size())
	room._drag_cascade = []
	room._finish_drag(true)
	var moved: Array = room._shelf_ids().duplicate(true)
	check(moved != draft, "В редакторе коробка переставлена")
	await create_timer(0.7).timeout
	check(room.can_undo_shelf(), "После перестановки есть что отменить")
	room.undo_shelf_edit()
	check(room._shelf_ids() == draft, "Отмена возвращает прежнюю расстановку")
	check(not room.can_undo_shelf(), "Стопка отмены пуста")
	room.finish_shelf_editor(false)
	print("SHELF LIFT: проверок %d, ошибок %d" % [checks, errors])
	quit(1 if errors > 0 else 0)
