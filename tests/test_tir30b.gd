extends SceneTree
## Things in Rings, вторая пачка 30.10: лобби по центру, кнопки проверки только у знающего,
## «Исправить область» в любом порядке и перетаскиванием красной карты, без архива, «Вне колец» только слева,
## обводка карты до краёв. Запуск: godot --path . --audio-driver Dummy --script res://tests/test_tir30b.gd
## Кадры — build/tir30b/.
var checks := 0
var errors := 0
var net: Node
var app: Control
var previous_mouse := Vector2.ZERO

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", text)

func settle() -> void:
	for _i: int in 5:
		await process_frame

func motion(at: Vector2, held: bool = false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = at - previous_mouse
	previous_mouse = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(e)
	await settle()

func button_event(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)
	await settle()

func click_at(at: Vector2) -> void:
	await motion(at)
	await button_event(at, true)
	await button_event(at, false)

func click(node: Control) -> void:
	await click_at(node.get_global_rect().get_center())

func drag_to(node: Control, target: Vector2) -> void:
	var start := node.get_global_rect().get_center()
	await motion(start)
	await button_event(start, true)
	for i: int in range(1, 11):
		await motion(start.lerp(target, i / 10.0), true)
	await button_event(target, false)

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/tir30b/%s_%s.png" % [label, root.get_node("Prefs").theme_mode])

func screen_size(size: Vector2i) -> void:
	root.size = size
	root.content_scale_size = size
	await settle()

func field() -> Control:
	return app.screen.find_child("RingField", true, false)

## Довести партию до проверки знающим: ходит искатель, кладёт карту «вне колец».
func to_judge() -> void:
	for _i: int in 6:
		var rules = net.tir
		if rules.phase == "judge":
			break
		if rules.phase == "knower_clue":
			rules.clue(rules.knower, rules.hands[rules.knower][0], 0)
		elif rules.phase == "place":
			rules.place(rules.current, rules.hands[rules.current][0], 0)
		rules.revision += 1
	net._push_state()
	net.send_action("view_seat", {"seat": int(net.tir.current)})
	await settle()

func view_knower() -> void:
	net.send_action("view_seat", {"seat": int(net.tir.knower)})
	await settle()
	await create_timer(0.1).timeout

func region_point(mask: int) -> Vector2:
	var f := field()
	f._geometry()
	for y in range(8, int(f.size.y), 6):
		for x in range(8, int(f.size.x), 6):
			var at := Vector2(x, y)
			if f._mask(at) == mask:
				var near := true
				for d: Vector2 in [Vector2(18, 0), Vector2(-18, 0), Vector2(0, 18), Vector2(0, -18)]:
					if f._mask(at + d) != mask:
						near = false
				if near and f.get_child_count() >= 0 and not _over_card(f.global_position + at):
					return f.global_position + at
	return f.global_position

func _over_card(at: Vector2) -> bool:
	for child: Node in field().get_children():
		if child is Control and (child as Control).get_global_rect().grow(4).has_point(at):
			return true
	return false

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/tir30b"))
	net = root.get_node("Net")
	var theme_name := OS.get_environment("TIR_THEME")
	root.get_node("Prefs").theme_mode = theme_name if theme_name in ["light", "dark"] else "dark"
	net.host_offline("things_in_rings")
	net.set_bots(2)
	net.set_setting("tr_rings", ["Attribute", "Word", "Context"])
	app = load("res://games/things_in_rings/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	# 1. Лобби по центру на 1920×1080 и 1280×720.
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		await screen_size(size)
		var panel: Control = app.screen.find_child("LobbyPanel", true, false)
		check(panel != null, "у лобби есть панель")
		if panel:
			var off := panel.get_global_rect().get_center() - Vector2(size) * 0.5
			check(absf(off.x) < 4.0 and absf(off.y) < 4.0, "лобби по центру %s (сдвиг %s)" % [size, off])
		await shot("lobby_%d" % size.x)
	# 2. Партия: правила и три подсказки «вне колец».
	check(net.start_game() == "", "партия запускается")
	await settle()
	await create_timer(0.3).timeout
	var rules = net.tir
	for category: String in net.view.rings:
		rules.choose_rule(rules.knower, category, int(net.view.rule_choices[category][0]))
	rules.begin_clues(rules.knower)
	for _i: int in 3:
		rules.clue(rules.knower, rules.hands[rules.knower][0], 0)
	rules.revision += 1
	net._push_state()
	await settle()
	check(net.tir.phase == "place", "после трёх подсказок ход искателя")
	check(app.screen.find_child("Region0", true, false) == null and app.screen.find_child("Region1", true, false) == null, "архива областей нет")
	var archive_heading := false
	for label: Node in app.screen.find_children("*", "Label", true, false):
		if "АРХИВ" in str(label.text):
			archive_heading = true
	check(not archive_heading, "заголовка «Архив областей» нет")
	# 3. Кнопки проверки — только у знающего.
	await to_judge()
	check(net.tir.phase == "judge", "карта ждёт проверки")
	check(app.screen.find_child("JudgeConfirm", true, false) == null and app.screen.find_child("JudgeCorrect", true, false) == null, "искатель не видит кнопок проверки")
	await view_knower()
	var correct: Button = app.screen.find_child("JudgeCorrect", true, false)
	check(app.screen.find_child("JudgeConfirm", true, false) != null and correct != null, "знающий видит обе кнопки")
	check(correct != null and not correct.disabled, "«Исправить область» доступна сразу")
	await shot("judge_knower")
	# 4. Сначала кнопка, потом зона.
	var before: int = net.tir.board.size()
	await click(correct)
	await click_at(region_point(1))
	check(net.tir.board.size() == before + 1 and int(net.tir.board.back().mask) == 1, "кнопка → зона исправляет в выбранную зону")
	# 5. Сначала зона, потом кнопка.
	await to_judge()
	await view_knower()
	before = net.tir.board.size()
	await click_at(region_point(2))
	check(net.tir.board.size() == before, "клик по зоне без кнопки ничего не отправляет")
	await click(app.screen.find_child("JudgeCorrect", true, false))
	check(net.tir.board.size() == before + 1 and int(net.tir.board.back().mask) == 2, "зона → кнопка исправляет в выбранную зону")
	# 6. Перетаскивание красной карты знающим.
	await to_judge()
	await view_knower()
	await create_timer(0.2).timeout
	before = net.tir.board.size()
	var pending: Control = field().find_child("PendingCard", true, false)
	check(pending != null and bool(pending.get("judge_drag")), "красную карту знающий может тащить")
	check(pending != null and pending.find_child("PendingVeil", false, false) != null, "последняя карта накрыта красным окошком")
	check(pending != null and is_equal_approx(pending.modulate.a, 1.0), "карта не мигает прозрачностью")
	if pending:
		# Тот же путь, что у жеста Godot: данные переноса карты → приём полем в точке зоны.
		# (Эмуляция отпускания мыши в тесте даёт неверную позицию после смены размера окна.)
		var data: Variant = pending._get_drag_data(Vector2.ZERO)
		var local: Vector2 = region_point(4) - field().global_position
		check(field()._can_drop_data(local, data), "поле принимает красную карту от знающего")
		field()._drop_data(local, data)
		await settle()
	check(net.tir.board.size() == before + 1 and int(net.tir.board.back().mask) == 4, "перетаскивание красной карты = исправить (зона %s)" % (net.tir.board.back().mask if net.tir.board.size() > before else "—"))
	# Ещё две карты «вне колец» через «Верно · оставить» — всего пять слева.
	for _i: int in 2:
		if net.tir.phase in ["postgame", "game_over"]:
			break
		await to_judge()
		await view_knower()
		var confirm: Button = app.screen.find_child("JudgeConfirm", true, false)
		if confirm:
			await click(confirm)
	# 7. «Вне колец» — только слева, в том числе после нескольких карт.
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		await screen_size(size)
		await create_timer(0.1).timeout
		var f := field()
		f._geometry()
		var limit: float = f._outside_right()
		var outside := 0
		for entry: Dictionary in net.tir.board:
			if int(entry.mask) != 0:
				continue
			var card: Control = f.find_child("BoardCard%d" % int(entry.card), true, false)
			check(card != null, "карта вне колец %d на поле при %s" % [entry.card, size])
			if card:
				outside += 1
				check(card.position.x + card.size.x <= limit + 0.5, "карта %d вне колец слева от колец при %s" % [entry.card, size])
		check(outside >= 5, "на поле не меньше пяти карт вне колец (%d)" % outside)
		await shot("outside_%d" % size.x)
	# 8. Обводка карты касается всех четырёх краёв.
	var outline: Image = load("res://games/things_in_rings/art/card_outline.png").get_image()
	var w := outline.get_width()
	var h := outline.get_height()
	for at: Vector2i in [Vector2i(0, h / 2), Vector2i(w - 1, h / 2), Vector2i(w / 2, 0), Vector2i(w / 2, h - 1)]:
		check(outline.get_pixelv(at).a > 0.9, "обводка касается края в %s" % at)
	print("ИТОГ: проверок %d, ошибок %d" % [checks, errors])
	app.queue_free()
	net.leave()
	quit(1 if errors > 0 else 0)
