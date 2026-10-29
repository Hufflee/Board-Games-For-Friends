extends SceneTree
## Узкая проверка зрителя и повторного финального снимка. Запуск с Dummy и отдельным APPDATA.

var checks := 0
var errors := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _run() -> void:
	await process_frame
	var net: Node = root.get_node("Net")
	net.set_process(false)
	net.host_offline("not_a_hat")
	net.set_bots(3)
	check(net.start_game() == "", "Подготовлена партия")
	var rules = net.nothat
	rules.new_game(rules.players, 2, 291030)
	rules.start_play()
	for phase: String in ["give", "respond", "reveal"]:
		rules.phase = phase
		var hidden := true
		for hand: Array in rules.get_view(-1, false).hands:
			for card: Dictionary in hand:
				hidden = hidden and int(card.g) == -1
		check(hidden, "Зритель не получает лица в фазе " + phase)
	rules.phase = "game_over"
	var view: Dictionary = rules.get_view(-1, false)
	check(view.hands == rules.hands, "Зритель получает все лица в конце")
	view.hands[0][0].g = -999
	check(rules.get_view(-1, false).hands == rules.hands, "Изменение снимка не меняет правила")
	net._push_state()
	var app: Control = load("res://games/not_a_hat/ui/main.tscn").instantiate()
	root.add_child(app)
	await create_timer(0.1).timeout
	var table: Control = app.screen
	view = rules.get_view(-1, false)
	table._on_state(view)
	var first: Control = table._hand_cards[0][0]
	check(first.gift == int(rules.hands[0][0].g), "Поздний зритель сразу видит лицо")
	table._on_state(view.duplicate(true))
	check(table._hand_cards[0][0] == first, "Повторный снимок не пересоздаёт карту")
	check(not first._flip.busy, "Повторный снимок не запускает переворот")
	app.queue_free()
	await process_frame
	net.leave()
	print("BATCH29 BOUNDARIES: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
