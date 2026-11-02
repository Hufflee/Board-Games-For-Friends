extends SceneTree
## Выход со стола в хаб освобождает правила/экран, в том числе при отложенном просмотре карты.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var net: Node = root.get_node("Net")
	for seats in [2, 8]:
		net.host_offline("four_souls")
		net.set_bots(seats - 1)
		net.set_setting("fs_dlc", seats == 8)
		check(net.start_game().is_empty(), "Запущена партия на %d мест" % seats)
		net.fs_switch_seat(1)
		var game_ref: WeakRef = weakref(net.fours)
		change_scene_to_file("res://games/four_souls/ui/main.tscn")
		await scene_changed
		await create_timer(0.25).timeout
		var app: Control = current_scene
		var table: Control = app.screen
		var table_ref: WeakRef = weakref(table)
		table._schedule_preview(int(net.fours.chars[0]))
		app.back_to_hub()
		await scene_changed
		# Остаться в хабе дольше окна чужих карт: проверить и запоздалый callback10с.
		await create_timer(11.0, true, false, true).timeout
		check(current_scene.scene_file_path == "res://hub/hub.tscn", "Возврат идёт в хаб, без заставки")
		check(net.fours == null and game_ref.get_ref() == null, "Правила партии освобождены после выхода")
		check(table_ref.get_ref() == null, "Стол освобождён вместе с отложенным просмотром")
	print("FS EXIT CLEANUP UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
