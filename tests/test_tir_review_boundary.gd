extends SceneTree
## Адресные границы ревью: повтор лобби, чужой перенос, старый view и очистка перевода.
var checks := 0
var errors := 0
var net: Node
var app: Control

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func settle() -> void:
	for _i: int in 5:
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("things_in_rings")
	net.set_bots(2)
	app = load("res://games/things_in_rings/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	var chat_script: Script = load("res://games/king_of_12/ui/chat_panel.gd")
	for _i: int in 3:
		app.screen._rebuild()
		await settle()
	var chats := 0
	for child: Node in app.screen.get_children():
		if child.get_script() == chat_script:
			chats += 1
	check(chats == 1, "Повтор лобби сохраняет единственную панель чата")
	check(net.start_game() == "", "Запуск из проверенного лобби")
	await settle()
	for category: String in net.view.rings:
		var chosen: int = net.view.rule_choices[category][0]
		net.send_action("choose_rule", {"category": category, "card": chosen, "revision": net.view.revision})
	net.send_action("begin_clues", {"revision": net.view.revision})
	await settle()
	var table: Control = app.screen
	var field: Control = table.find_child("RingField", true, false)
	var id: int = net.view.hand[0]
	var drag := {"tr_card": id, "seat": net.view.you, "revision": net.view.revision}
	check(field._can_drop_data(Vector2.ZERO, drag), "Текущий перенос своего места разрешён")
	var stale: Dictionary = drag.duplicate()
	stale.revision -= 1
	check(not field._can_drop_data(Vector2.ZERO, stale), "Старая ревизия переноса запрещена")
	var other: Dictionary = drag.duplicate()
	other.seat = 1
	check(not field._can_drop_data(Vector2.ZERO, other), "Перенос другого места запрещён")
	table.preview_card(id)
	check(not table._translation.text.is_empty(), "Свою открытую карту можно перевести")
	net.send_action("view_seat", {"seat": 1})
	await settle()
	check(table._translation.text.is_empty() and table._picture.texture == null, "Смена места очищает перевод и большой просмотр")
	await create_timer(1.6).timeout
	check(table._translation.text.is_empty() and table._picture.texture == null, "Отложенный просмотр прежнего места не восстанавливает его секретную карту")
	check(net.view.secret_rules.is_empty() and net.view.rule_choices.is_empty(), "После смены места тайные правила отсутствуют")
	field = table.find_child("RingField", true, false)
	check(not field._can_drop_data(Vector2.ZERO, drag), "Снимок переноса прежнего места больше не действует")
	var before: int = net.view.revision
	table.drop_card(id, 0)
	check(net.view.revision == before, "Неактивное место не размещает чужую карту")
	var guard: Node = load("res://hub/pause_layer.gd").new()
	var action := Button.new()
	action.text = "Подтвердить область"
	check(not guard._spectator_allowed(action), "Без метки игровая кнопка зрителю запрещена")
	action.set_meta("spectator_read_only", false)
	check(not guard._spectator_allowed(action), "Ложная метка не разрешает кнопку")
	action.set_meta("spectator_read_only", true)
	check(guard._spectator_allowed(action), "Явная метка разрешает локальную кнопку архива")
	action.free()
	var wrapper := Control.new()
	wrapper.set_meta("spectator_read_only", true)
	var blocked := Button.new()
	blocked.text = "Подтвердить область"
	wrapper.add_child(blocked)
	check(not guard._spectator_allowed(blocked), "Метка произвольной панели не разрешает игровые кнопки")
	wrapper.free()
	guard.free()
	app.queue_free()
	net.leave()
	await settle()
	print("TIR REVIEW BOUNDARY: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
