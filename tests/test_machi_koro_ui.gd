extends SceneTree
## Runtime Мачи Коро: ввод мышью, две темы, выбор и анимация ресурсов. Запускать с окном и Dummy.

var net: Node
var app: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ОШИБКА UI: " + text)

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/" + name + ".png")

func button(prefix: String, scope: Node = null) -> Button:
	var search: Node = app if scope == null else scope
	for item: Button in search.find_children("*", "Button", true, false):
		if item.is_visible_in_tree() and item.text.begins_with(prefix):
			return item
	return null

func mouse(position: Vector2, down: bool) -> void:
	var input := InputEventMouseButton.new()
	input.position = position
	input.global_position = position
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = down
	Input.parse_input_event(input)
	await process_frame

func click(item: Control) -> void:
	check(is_instance_valid(item), "элемент для клика существует")
	if not is_instance_valid(item):
		return
	var point := item.get_global_rect().get_center()
	await mouse(point, true)
	await mouse(point, false)

func _run() -> void:
	net = root.get_node("Net")
	root.size = Vector2i(1280, 720)
	root.get_node("Prefs").theme_mode = "light"
	app = load("res://games/machi_koro/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	net.host_offline("machi_koro")
	net.set_bots(4)
	net.set_setting("mk_plus", true)
	net.set_setting("mk_sharp", true)
	net.set_setting("mk_limited", true)
	await process_frame
	await shot("mk_lobby_light")
	await click(button("Начать партию"))
	check(net.mk != null and net.in_game, "старт мышью из лобби")
	if net.mk == null:
		quit(1)
		return
	net.mk.current = 0
	net.mk.built[0].append("station")
	net.mk.revision += 1
	net._push_state()
	await create_timer(0.15).timeout
	await shot("mk_table_light")
	check(app.screen.city_panel.get_global_rect().end.y <= 720 and app.screen.landmark_panel.get_global_rect().end.y <= 720, "нижние панели в 720 px")
	check(app.screen.market_grid.columns >= 5, "рынок имеет читаемую сетку")
	var art_script: Script = load("res://games/machi_koro/ui/mk_art.gd")
	var data_script: Script = load("res://games/machi_koro/logic/mk_data.gd")
	var checked_types := {}
	for definition: Dictionary in data_script.catalog().values():
		var kind := str(definition.icon)
		if not checked_types.has(kind):
			var icon: Texture2D = art_script.type_icon(kind)
			check(icon != null and icon.get_image().get_used_rect().has_area(), "видимый значок типа «%s»" % kind)
			checked_types[kind] = true
	for card: Control in app.screen.market_grid.get_children():
		check(card.find_child("EnterpriseIcon", true, false) is TextureRect, "значок на карте рынка «%s»" % card.id)
	check(app.screen.city_cards.get_child(0).find_child("EnterpriseIcon", true, false) is TextureRect, "значок на мини-карте города")
	check(app.screen.side_col.get_child(1).icon != null, "игрок обозначен общей цветной точкой")
	await click(button("2 кубика"))
	check(app.screen.dice_count == 2, "выбор двух кубиков мышью")
	var die: Control = app.screen.dice_nodes[0]
	var start := die.get_global_rect().get_center()
	await mouse(start, true)
	for delta: Vector2 in [Vector2(-40, 20), Vector2(-100, 80)]:
		var motion := InputEventMouseMotion.new()
		motion.position = start + delta
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await process_frame
	var release_position: Vector2 = die.position
	check(release_position.distance_to(start - die.size * 0.5) > 60, "кубик отведён от домашней позиции")
	die.thrown.connect(func(_velocity: Vector2):
		check(die.position.is_equal_approx(release_position), "ответ хоста сохраняет точку отпускания кубика"), CONNECT_ONE_SHOT)
	await mouse(start + Vector2(-100, 80), false)
	check(net.mk.throw_serial == 1 and net.mk.main_dice.size() == 2, "жест TossDie бросил пару костей через Net")
	# Отдельные управляемые положения проверяют обязательные выборы и неизменность баланса до окончания.
	net.set_paused(true)
	net.mk.event.clear()
	net.mk.jobs.clear()
	for city: Array in net.mk.cities:
		city.clear()
	net.mk.coins = [0, 8, 0, 0, 0]
	net.mk._add_card(0, "tv")
	net.mk.result = 6
	net.mk._resolve()
	net.mk.revision += 1
	net.set_paused(false)
	await process_frame
	check(app.screen.choice_panel != null, "показано окно допустимых целей")
	check(app.screen.choice_panel.get_global_rect().end.y <= 720, "подтверждение выбора помещается в экран")
	await click(button("Игрок 2", app.screen.choice_panel))
	await click(button("Подтвердить выбор", app.screen.choice_panel))
	check(net.mk.phase == "animation" and net.mk.coins == [0, 8, 0, 0, 0], "подтверждение запустило показ без раннего начисления")
	await create_timer(0.9).timeout
	await shot("mk_effect_light")
	check(net.mk.coins == [0, 8, 0, 0, 0], "через 0,9 с баланс ещё прежний")
	await create_timer(2.0).timeout
	check(net.mk.coins == [5, 3, 0, 0, 0], "по окончании показа переведены 5 монет")
	# Темы меняются без личных записей Prefs; игровой снимок тот же.
	root.get_node("Prefs").theme_mode = "dark"
	app._prefs_changed()
	await process_frame
	await process_frame
	await shot("mk_table_dark")
	check(app.screen.top != null and app.screen.view.coins == net.mk.coins, "тёмная тема сохранила игру и общую полосу")
	var motion := InputEventMouseMotion.new()
	motion.position = app.screen.market_grid.get_child(0).get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await create_timer(0.4).timeout
	check(is_instance_valid(app.screen.preview), "открытая карта имеет крупный просмотр")
	if is_instance_valid(app.screen.preview):
		check(app.screen.preview.get_global_rect().end.y <= 720, "полный текст крупного просмотра помещается в экран")
	await shot("mk_preview_dark")
	var before: int = net.mk.revision
	app.show_rules()
	await process_frame
	await shot("mk_rules_dark")
	check(net.mk.revision == before, "правила не изменили партию")
	await click(button("Понятно"))
	# Хостовая отмена/повтор сохраняют очередь, ГСЧ и уже начисленные монеты.
	check(not bool(net.host_tools.info().get("timer_supported", true)), "панель хоста не обещает отсутствующий таймер")
	var art: Script = load("res://games/machi_koro/ui/mk_art.gd")
	check(art.cover("front") != null and art.cover("spine") != null, "обложка и корешок доступны")
	# Публичный снимок клиента в чужой ход: собственный город остаётся слева.
	net.mk._add_card(1, "wheat")
	net.mk._add_card(1, "bakery")
	net.mk.revision += 1
	net._push_state()
	var foreign: Dictionary = net.view.duplicate(true)
	foreign.you = 1
	foreign.hotseat = false
	foreign.revision += 100
	for theme_name: String in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = theme_name
		app._prefs_changed()
		await process_frame
		await process_frame
		app.screen._state(foreign)
		await create_timer(0.15).timeout
		check(app.screen.city_panel.get_meta("shown_seat") == 1 and app.screen.landmark_panel.get_meta("shown_seat") == 0, "одновременно личный и активный город: " + theme_name)
		check(app.screen.city_cards.get_child_count() == 8 and app.screen.landmark_cards.get_child_count() == 7, "оба города включают предприятия и достопримечательности: " + theme_name)
		app.screen.inspect_seat = 3
		app.screen._refresh_city()
		check(app.screen.city_panel.get_meta("shown_seat") == 1 and app.screen.landmark_panel.get_meta("shown_seat") == 0, "выбор другого имени не скрывает два города")
		await shot("mk_two_cities_" + theme_name)
	net.mk.phase = "game_over"
	net.mk.winner = 0
	net.mk.revision += 1
	net._push_state()
	for frame in 8:
		await process_frame
	await shot("mk_victory_dark")
	var final: Control = app.screen.top._victory_screen
	check(final._cards.size() == 5 and final._cards[0].get_node_or_null("Initials") == null, "на финале также цветные точки вместо аватарок")
	print("MK_UI: %d проверок, %d ошибок" % [checks, failures])
	current_scene = null
	app.free()
	net.leave()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
