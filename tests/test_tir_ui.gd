extends SceneTree
## Реальный ввод Things in Rings 1280×720: выбор, drag, перевод, полный локальный цикл и финал.
var checks := 0
var errors := 0
var net: Node
var app: Control
var previous_mouse := Vector2.ZERO
var blocked_pressed := false

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func settle() -> void:
	for _i: int in 5:
		await process_frame

func click(node: Control) -> void:
	await click_at(node.get_global_rect().get_center())

func motion(at: Vector2, held: bool = false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = at - previous_mouse
	previous_mouse = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(e)
	await settle()

func click_at(at: Vector2) -> void:
	await motion(at)
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.global_position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		Input.parse_input_event(e)
		await settle()

func drag(card: Control, field: Control) -> void:
	await drag_to(card, field.global_position + Vector2(24, 260))

func drag_to(card: Control, target: Vector2) -> void:
	await create_timer(0.18).timeout
	var start := card.get_global_rect().get_center()
	await motion(start)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = start
	press.global_position = start
	Input.parse_input_event(press)
	await settle()
	for i: int in range(1, 9):
		await motion(start.lerp(target, i / 8.0), true)
	check(bool(card.get("dragging")), "Общая карта начала реальный перенос: %s -> %s" % [card.name, target])
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = target
	release.global_position = target
	release.pressed = false
	Input.parse_input_event(release)
	await settle()

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/tir_game/" + label + ".png")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	net = root.get_node("Net")
	root.get_node("Prefs").theme_mode = "light"
	net.host_offline("things_in_rings")
	net.set_bots(2)
	net.set_setting("tr_rings", ["Attribute", "Word", "Context"])
	check(net.start_game() == "", "Запуск партии из Net")
	app = load("res://games/things_in_rings/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	await create_timer(0.3).timeout
	var fidget: Node = null
	for child: Node in app.get_children():
		if child.get_script() == load("res://hub/fidget.gd"):
			fidget = child
	check(fidget != null and fidget.get("_style") == "king_of_12", "Фактическая монета использует K12")
	check(load("res://hub/art/coins/king_of_12_front.png") is Texture2D, "Спрайт K12 загружается")
	check(fidget != null and fidget._tex("res://hub/art/coins/king_of_12_front.png") is Texture2D, "Реальный Fidget использует загруженный спрайт")
	check(is_instance_valid(app.screen), "Приложение создало стол")
	check(root.get_node("Sfx").get("_playlist") == app.MUSIC, "Приложение задаёт свой спокойный CC0 playlist")
	for category: String in net.view.rings:
		var id: int = net.view.rule_choices[category][0]
		await motion(app.screen.find_child("Rule%d" % id, true, false).get_global_rect().get_center())
		check(app.screen.get("_translation").text == load("res://games/things_in_rings/logic/tr_data.gd").translation(id), "Наведение на правило показывает его перевод")
		check(app.screen.get("_picture").texture == null, "Крупный просмотр правила не появляется немедленно")
		await click(app.screen.find_child("Rule%d" % id, true, false))
	check(net.view.secret_rules.size() == 3, "Настоящие клики выбрали три правила")
	if net.view.secret_rules.size() != 3:
		quit(1)
		return
	await screenshot("choices-light")
	await click(app.screen.find_child("BeginClues", true, false))
	check(net.view.phase == "setup_clues" and net.view.hand.size() == 5, "Клик подтверждения раздал вещи")
	await create_timer(0.2).timeout
	var hand: Control = app.screen.find_child("PrivateHand", true, false)
	var original_order: Array = hand.order.duplicate()
	var first_key: String = str(original_order[0])
	var hand_card: Control = hand._cards[first_key]
	var baseline_y: float = hand_card.position.y
	check(hand._cards[str(original_order[1])].position.x - hand_card.position.x < hand_card.size.x, "Личная рука перекрывает соседние карты")
	await motion(hand_card.get_global_rect().get_center())
	check(not app.screen.get("_translation").text.is_empty() and app.screen.get("_picture").texture == null, "Перевод руки сразу, крупное изображение ждёт")
	await create_timer(0.2).timeout
	check(hand_card.position.y < baseline_y - 8, "Наведённая карта слегка поднимается")
	await create_timer(1.0).timeout
	check(app.screen.get("_picture").texture == null, "До1.5секунд крупный просмотр скрыт")
	await create_timer(0.45).timeout
	check(app.screen.get("_picture").texture != null, "После1.5секунд непрерывного hover есть крупный просмотр")
	var before_sort: int = net.view.revision
	await drag_to(hand_card, hand.global_position + Vector2(hand.size.x - 8, 80))
	var sorted_order: Array = hand.order.duplicate()
	check(sorted_order != original_order and sorted_order.back() == first_key and net.view.revision == before_sort, "Реальный drag сортирует руку локально")
	net._push_state()
	await settle()
	hand = app.screen.find_child("PrivateHand", true, false)
	check(hand.order == sorted_order, "Порядок сохраняется при повторном view")
	await click(app.screen.find_child("Seat1", true, false))
	await click(app.screen.find_child("Seat0", true, false))
	hand = app.screen.find_child("PrivateHand", true, false)
	check(hand.order == sorted_order, "Порядок своего места сохраняется после переключения мест")
	await drag_to(hand._cards[first_key], Vector2(1100, 640))
	check(net.view.hand.size() == 5 and net.view.revision == before_sort, "Отпущенная вне поля карта остаётся в руке")
	var card: Control = app.screen.find_child("Card%d" % net.view.hand[0], true, false)
	var field: Control = app.screen.find_child("RingField", true, false)
	var center: float = field.size.x * 0.5
	var targets := [Vector2(24,260), Vector2(center-124,90), Vector2(center+124,90),
		Vector2(center,75), Vector2(center,280), Vector2(center-70,200), Vector2(center+70,200), Vector2(center,160)]
	for mask: int in 8:
		check(field.mask_at(targets[mask]) == mask, "Доступна геометрическая область " + str(mask))
	await motion(card.get_global_rect().get_center())
	check(not app.screen.get("_translation").text.is_empty(), "Наведение показывает русский перевод")
	check(is_equal_approx(app.screen.get("_translation").get_theme_color("font_color").a, 0.8), "Перевод alpha0.8")
	await create_timer(1.55).timeout
	await screenshot("table-light")
	await motion(Vector2(1000, 48))
	check(app.screen.get("_translation").text.is_empty(), "Уход мыши очищает перевод")
	await drag(card, field)
	check(net.view.board.size() == 1, "Реальный drag разместил подсказку")
	if net.view.board.size() != 1:
		quit(1)
		return
	check(app.screen.get("_translation").text.is_empty(), "Новый view очищает перевод")
	app.screen._theme()
	await settle()
	card = app.screen.find_child("Card%d" % net.view.hand[0], true, false)
	await motion(card.get_global_rect().get_center())
	check(not app.screen.get("_translation").text.is_empty(), "Перевод читается и в тёмной теме")
	await create_timer(1.55).timeout
	await screenshot("table-dark")
	for _i: int in 2:
		card = app.screen.find_child("Card%d" % net.view.hand[0], true, false)
		await click(card)
		await click_at(app.screen.find_child("RingField", true, false).global_position + Vector2(24, 260))
	check(net.view.phase == "place", "Три подсказки запускают ход искателя")
	await click(app.screen.find_child("Seat1", true, false))
	check(net.view.you == 1 and net.view.secret_rules.is_empty(), "Смена места не раскрывает правила")
	for i: int in 5:
		card = app.screen.find_child("Card%d" % net.view.hand[0], true, false)
		await click(card)
		await click_at(app.screen.find_child("RingField", true, false).global_position + Vector2(24, 260))
		check(net.view.phase == "judge", "Карта искателя ждёт человеческого решения")
		await click(app.screen.find_child("Seat0", true, false))
		await click(app.screen.find_child("JudgeConfirm", true, false))
		if i < 4:
			await click(app.screen.find_child("Seat1", true, false))
	check(net.view.phase == "game_over" and net.view.winners == [1], "Полный цикл реальных кликов до обычной победы")
	await screenshot("victory")
	await click(app.screen.find_child("ShowTable", true, false))
	check(not app.screen.find_child("VictorySurface", true, false).visible, "Можно вернуться к архиву стола")
	var reveal: Button = null
	for button: Node in app.screen.find_children("*", "Button", true, false):
		if button.text == "Раскрыть правила":
			reveal = button
	await click(reveal)
	check(net.view.revealed, "Знающий явно раскрывает правила после финала")
	var result: Dictionary = load("res://hub/victory_result.gd").resolve("things_in_rings", net.view)
	check(result.winners == [1] and not result.team, "VictoryResult победитель искатель")
	var spectator: Dictionary = net.tir.get_view(-1)
	spectator["spectator"] = true
	spectator["game"] = "things_in_rings"
	spectator["game_id"] = net.game_id
	var revision_before: int = net.tir.revision
	net._apply_state(spectator)
	await settle()
	await click(app.screen.find_child("Region1", true, false))
	check(app.screen.get("_archive") == 1 and net.tir.revision == revision_before, "Зритель открывает архив без игрового действия")
	var blocked := Button.new()
	blocked.text = "Запрещённое действие"
	blocked.position = Vector2(500, 600)
	blocked.size = Vector2(220, 40)
	blocked.pressed.connect(func(): blocked_pressed = true)
	app.screen.add_child(blocked)
	await click(blocked)
	check(not blocked_pressed and net.tir.revision == revision_before, "Зритель по-прежнему не нажимает обычные игровые кнопки")
	app.queue_free()
	net.leave()
	await settle()
	print("TIR UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
