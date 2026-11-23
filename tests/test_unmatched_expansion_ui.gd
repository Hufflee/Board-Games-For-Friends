extends SceneTree
## Лобби, стол и подсветка эффектов шести героев Unmatched.
## Запуск: godot --audio-driver Dummy --path . --script res://tests/test_unmatched_expansion_ui.gd
## Для оконных кадров 1280×720 задайте UM_EXPANSION_SHOTS=1.

const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Complexity := preload("res://games/unmatched/logic/um_complexity.gd")
const MIST := ["jekyll_hyde", "invisible_man", "dracula", "sherlock"]
const MAGICIANS := ["houdini", "genie"]

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
	for hero: String in Roster.HEROES:
		_check(Complexity.CATEGORY.has(hero), "Оценка сложности из PDF есть для %s" % Roster.HEROES[hero].name)
	_check(Complexity.label("bigfoot") == "Сложность: ★☆☆☆☆" and Complexity.label("chupacabra") == "Сложность: ★★☆☆☆"
		and Complexity.label("tomoe") == "Сложность: ★★★☆☆" and Complexity.label("hamlet") == "Сложность: ★★★★☆"
		and Complexity.label("witches") == "Сложность: ★★★★★", "Пять категорий PDF отображаются пятью уровнями звёзд")
	for hero: String in MIST + MAGICIANS:
		var faces := 0
		for i in range(1, 31):
			faces += int(Art.face({"hero": hero, "face": i}) != null)
		_check(faces == 30 and Art.back(hero) != null and Art.reference_face(hero) != null,
			"Читаются лица, рубашка и памятка героя %s" % Roster.HEROES[hero].name)
	for heroes: Array in [MIST, MAGICIANS]:
		var mode := "light" if heroes == MIST else "dark"
		prefs.theme_mode = mode
		prefs.apply()
		net.host_offline("unmatched")
		net.set_bots(heroes.size() - 1)
		net.set_setting("um_arena", "marmoreal")
		net.set_setting("um_hero_mode", "free")
		net.set_setting("um_heroes", heroes)
		var app: Control = scene.instantiate()
		root.add_child(app)
		await _frames()
		await _check_lobby(app, heroes, mode)
		await _check_match(app, net, heroes, mode)
		app.queue_free()
		await process_frame
		net.leave()
	var offers := ["invisible_man", "shakespeare", "witches"]
	for mode in ["light", "dark"]:
		prefs.theme_mode = mode
		prefs.apply()
		for count in [2, 3]:
			await _check_draft(net, scene, offers.slice(0, count), mode)
	print("Unmatched, интерфейс новых героев: %d проверок, %d ошибок." % [_checks, _errors])
	quit(1 if _errors else 0)


func _check_lobby(app: Control, heroes: Array, mode: String) -> void:
	var options: Array[String] = ["Персонажи"]
	var ordered: Array = Roster.HEROES.keys()
	ordered.sort_custom(func(first: String, second: String) -> bool:
		return str(Roster.HEROES[first].name).naturalnocasecmp_to(str(Roster.HEROES[second].name)) < 0)
	for hero: String in ordered:
		options.append("%s · %s" % [Roster.HEROES[hero].name, Complexity.label(hero)])
	for i in heroes.size():
		var option := app.find_child("HeroSelect%d" % i, true, false) as OptionButton
		var difficulty := app.find_child("HeroDifficulty%d" % i, true, false) as Label
		if option == null or difficulty == null:
			_check(false, "Селектор лобби и его подпись существуют")
			continue
		var entries: Array[String] = []
		for index in option.item_count:
			entries.append(option.get_item_text(index))
		_check(entries == options and option.text == Roster.HEROES[heroes[i]].name
			and app.get_global_rect().encloses(option.get_global_rect()),
			"Полный список героев с оценками и имя выбранного героя: %s" % option.text)
		_check(difficulty.text == Complexity.label(heroes[i]), "Сложность видна при закрытом селекторе")
	await _check_sort(app.find_child("HeroSelect1", true, false), heroes[1], mode)
	var preview := app.find_child("LobbyPreview", true, false)
	var references := preview.get_child(2).get_children() if preview != null else []
	_check(references.size() == heroes.size(), "В лобби видны все пары карточек героев")
	if references.size() != heroes.size():
		return
	app._hide_hero_preview()
	await _shot("lobby_" + mode)
	if _capture_enabled():
		var selector := app.find_child("HeroSelect1", true, false) as OptionButton
		selector.show_popup()
		await _frames()
		await _shot("lobby_selector_" + mode)
		selector.get_popup().hide()
		await _frames()
	for i in references.size():
		_check_pair(references[i], heroes[i])
	var cards: Control = references[1]
	cards.mouse_entered.emit()
	await _frames()
	var zoom: Control = app._hero_preview
	_check(zoom.hero == cards.hero and zoom.size.y > cards.size.y
		and app.get_global_rect().encloses(zoom.get_global_rect()), "Наведение показывает крупную пару внутри окна")
	_check_pair(zoom, cards.hero)
	await _shot("hero_preview_" + mode)


func _check_sort(selector: OptionButton, hero: String, mode: String) -> void:
	var original: Array = selector.call("ordered_heroes")
	var changed := [false]
	selector.connect("hero_selected", func(_hero: String) -> void: changed[0] = true)
	selector.show_popup()
	await _frames()
	var popup := selector.get_popup()
	var button: Button = popup.get_node("HeroSort")
	_check(button.position.x > popup.size.x * 0.7 and button.position.y < 12, "Сортировка расположена справа сверху списка")
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		var at := button.position + button.size * 0.5
		if popup.is_embedded(): at += Vector2(popup.position)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.window_id = popup.get_window_id()
		Input.parse_input_event(motion)
		await process_frame
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = at
			event.global_position = at
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			event.window_id = popup.get_window_id()
			Input.parse_input_event(event)
			await process_frame
	await _frames()
	_check(selector.get("by_complexity") and button.tooltip_text == "Сортировать по алфавиту", "Нажатие звезды переключило список на сложность и значок A/Z")
	var previous := 0
	for key: String in selector.call("ordered_heroes"):
		var level := Complexity.level(key)
		_check(level >= previous, "Список отсортирован по возрастанию сложности")
		previous = level
	_check(selector.text == Roster.HEROES[hero].name and not changed[0], "Сортировка сохраняет выбор и не отправляет выбор персонажа")
	await _shot("lobby_sorted_complexity_" + mode)
	button.pressed.emit()
	_check(not selector.get("by_complexity") and selector.call("ordered_heroes") == original,
		"Кнопка A/Z возвращает алфавитный порядок")
	popup.hide()
	await _frames()


func _check_draft(net: Node, scene: PackedScene, offers: Array, mode: String) -> void:
	net.host_offline("unmatched")
	net.set_setting("um_arena", "marmoreal")
	net.set_setting("um_hero_mode", "pick%d" % offers.size())
	var app: Control = scene.instantiate()
	root.add_child(app)
	var message: String = net.start_game()
	_check(message.is_empty() and app._playing, "Открылась партия с выбором из %d героев" % offers.size())
	if app._playing:
		net.unmatched._draft_offers.assign(offers)
		net._push_state()
		if net.view.get("handoff", false):
			net.send_action("handoff", {})
		await _frames()
		var choice: Control = app._screen._hero_choice
		_check(choice.visible and choice._tiles.size() == offers.size(), "Показаны все варианты выбора героя")
		if choice._tiles.size() == offers.size():
			var previous := Rect2()
			for i in offers.size():
				var button: Button = choice._tiles[i]
				var bounds := button.get_global_rect()
				var difficulty := button.find_child("HeroDifficulty", true, false) as Label
				var title := button.find_child("HeroName", true, false) as Label
				_check(app.get_global_rect().encloses(bounds) and not bounds.intersects(previous),
					"Вариант %d полностью виден и не пересекается с соседним" % (i + 1))
				_check(title.text == Roster.HEROES[offers[i]].name and difficulty.text == Complexity.label(offers[i]),
					"Имя героя и сложность видны над парой карточек")
				_check_pair(button.find_child("HeroCards", true, false), offers[i])
				previous = bounds
			await _shot("draft%d_%s" % [offers.size(), mode])
			var last: Button = choice._tiles.back()
			var face := last.find_child("Face", true, false) as TextureRect
			var pointer := face.get_global_rect().get_center()
			for pressed: bool in [true, false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.position = pointer
				click.global_position = pointer
				click.pressed = pressed
				root.push_input(click, true)
			_check(offers.back() in net.unmatched._draft_choices, "Щелчок по памятке применяет выбранного героя на хосте")
	app.queue_free()
	await process_frame
	net.leave()


func _check_pair(cards: Control, hero: String) -> void:
	var back := cards.find_child("Back", true, false) as TextureRect
	var face := cards.find_child("Face", true, false) as TextureRect
	_check(back != null and face != null and back.texture != null and face.texture != null
		and back.texture.get_size() == Art.back(hero).get_size() and face.texture.get_size() == Art.reference_face(hero).get_size()
		and back.get_global_rect().end.x < face.global_position.x,
		"Рубашка слева, памятка справа у %s" % Roster.HEROES[hero].name)


func _check_match(app: Control, net: Node, heroes: Array, mode: String) -> void:
	var message: String = net.start_game()
	_check(message.is_empty() and app._playing, "Партия с новыми героями открыла стол")
	if not app._playing:
		return
	var table: Control = app._screen
	for step in 24:
		if net.view.get("handoff", false):
			net.send_action("handoff", {})
		var setup: Dictionary = net.view.get("setup", {})
		if setup.get("cells", []).is_empty():
			break
		net.send_action("place", {"cell": setup.cells[0]})
	await _frames()
	var board: Control = table._board
	for hero: String in heroes:
		_check(board._figures.any(func(figure: Dictionary) -> bool: return figure.token == hero)
			and Art.texture("res://games/unmatched/art/tokens/%s.webp" % hero) != null,
			"На поле есть фишка героя %s" % Roster.HEROES[hero].name)
	if heroes == MIST:
		_check(board.fog.size() == 3 and board.fog == net.view.fog, "На поле видны три жетона тумана от хоста")
		_check(board._figures.any(func(figure: Dictionary) -> bool: return figure.get("status") == "Доктор Джекилл"),
			"На поле показан начальный облик Джекилла")
		await _shot("table_light")
		var choice: Dictionary = net.view.get("effect", {})
		_check("hyde" in choice.get("options", []), "Доступен выбор облика Хайда")
		if "hyde" in choice.get("options", []):
			net.send_action("effect", {"request": choice.id, "answer": "hyde"})
			await _frames()
			_check(board._figures.any(func(figure: Dictionary) -> bool: return figure.get("status") == "Мистер Хайд"),
				"На поле показан новый облик Хайда")
			await _shot("hyde_light")
	else:
		await _shot("table_dark")
		await _check_highlights(table)


func _check_highlights(table: Control) -> void:
	var show: Control = table._combat_show
	var attack := {"hero": "houdini", "face": 3, "definition": "houdini:03", "value": 4}
	var defense := {"hero": "genie", "face": 3, "definition": "genie:03", "value": 1}
	var immediate := {"id": 1, "side": 0, "message": "Противник может усилить карту"}
	show.present({"id": 1, "attack": attack, "defense": defense, "attack_hero": "houdini", "defense_hero": "genie",
		"immediate": immediate, "during": [{"side": 0, "message": "Гудини может усилить карту"}]},
		{}, table._attack.get_global_rect(), table._defense.get_global_rect(), table._fight_frame.get_global_rect())
	await _check_highlight(show, "_playing_immediate", Vector2(360, 399), "immediate_dark")
	await _check_highlight(show, "_during_playing", Vector2(407, 448), "during_dark")


func _check_highlight(show: Control, phase: String, expected: Vector2, filename: String) -> void:
	var deadline := Time.get_ticks_msec() + 8500
	while not show.get(phase) and Time.get_ticks_msec() < deadline:
		await process_frame
	var card: TextureRect = show._attack
	var panel := card.get_child(-1) as Panel
	_check(show.get(phase) and panel != null, "Показ боя подсветил печатный эффект")
	if not show.get(phase) or panel == null:
		return
	var face: Rect2 = show._face_rect(card)
	var bounds := Vector2(panel.position.y, panel.position.y + panel.size.y)
	bounds = (bounds - Vector2.ONE * face.position.y) * float(card.texture.get_height()) / face.size.y
	_check(bounds.distance_to(expected) < 0.5, "Рамка совпадает с печатным блоком эффекта")
	await _shot(filename)


func _frames() -> void:
	for frame in 4:
		await process_frame


func _shot(filename: String) -> void:
	if not _capture_enabled():
		return
	var path := ProjectSettings.globalize_path("res://build/shots/unmatched_expansion")
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.get_size() == Vector2i(1280, 720), "Кадр сделан в 1280×720")
	_check(image.save_png(path.path_join(filename + ".png")) == OK, "Сохранён кадр %s" % filename)


func _capture_enabled() -> bool:
	return OS.get_environment("UM_EXPANSION_SHOTS") == "1" and DisplayServer.get_name() != "headless"


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_errors += 1
		push_error(message)
