extends SceneTree
## Общие черновики UI, чужие действия GTW/First Contact, обучение и отдельные темы «Хором!».
## godot --headless --audio-driver Dummy --path . --script res://tests/test_batch22_games.gd
## BATCH22_SHOTS=1: оконный прогон с кадрами в build/shots/batch22/.

const LocalState := preload("res://hub/local_ui_state.gd")
const Contact := preload("res://games/first_contact/logic/fc_rules.gd")

var checks := 0
var failures := 0
var net: Node
var prefs: Node


class Form:
	extends Control
	var draft := ""
	var selected: Array[int] = []
	var holder: Control
	var input: LineEdit
	var builds := 0

	func rebuild() -> void:
		if is_instance_valid(holder):
			remove_child(holder)
			holder.queue_free()
		holder = Control.new()
		builds += 1
		holder.name = "Form%d" % builds
		add_child(holder)
		input = LineEdit.new()
		input.name = "Answer"
		input.set_meta("local_ui_key", "future.answer")
		input.text = draft
		holder.add_child(input)


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	net = root.get_node("Net")
	prefs = root.get_node("Prefs")
	root.size = Vector2i(1280, 720)
	_contact_rules()
	_topics()
	await _common_form()
	await _green_team()
	await _contact_ui()
	print("ПАКЕТ 22.11: %d проверок, %d ошибок" % [checks, failures])
	root.get_node("Sfx").request_quit(1 if failures else 0)


func _contact_rules() -> void:
	var game := Contact.new()
	game.new_game([{}, {}, {}, {}, {}], {"aliens": 2})
	for question in 6:
		check(game.action(game.turn, "ask", {"serial": game.serial, "slots": [0, 1]}, false), "Землянин задаёт вопрос")
		var teacher: int = game.humans + question % 2
		check(game.turn == teacher, "Инопланетяне отвечают по очереди между кругами")
		check(not game.action(game.humans + (question + 1) % 2, "teach", {"serial": game.serial, "feature": 0}, false), "Чужой инопланетянин не отвечает за назначенного")
		check(game.action(teacher, "teach", {"serial": game.serial, "feature": 0}, false), "Назначенный инопланетянин отвечает")
	check(game.phase == "clue", "После двух кругов обучения начинается подсказка")
	var skip := Contact.new()
	skip.new_game([{}, {}, {}, {}], {"aliens": 2})
	check(not skip.action(1, "skip_learning", {"serial": skip.serial}, false), "Чужой ход нельзя пропустить")
	check(skip.action(0, "skip_learning", {"serial": skip.serial}, false) and skip.turn == 1, "Пропуск завершает только текущий ход")
	check(skip.action(1, "skip_learning", {"serial": skip.serial}, false) and skip.turn == 0 and skip.turn_no == 2, "Новый круг снова доступен пропускавшим")
	check(not skip.action(0, "skip_learning", {"serial": skip.serial - 1}, false), "Устаревший пропуск отклоняется")
	for feature in [0, 1, 2]:
		check(skip.action(0, "note", {"feature": feature, "symbol": 4}, false), "К знаку добавляется отдельная гипотеза")
	check(skip.get_view(0).notes.size() == 3, "Три гипотезы одного знака сохраняются")
	check(skip.get_view(1).notes.is_empty(), "Личные гипотезы не раскрываются другому игроку")
	check(skip.action(0, "note_erase", {"feature": 1, "symbol": 4}, false), "Удаляется выбранная гипотеза")
	check(skip.get_view(0).notes.size() == 2 and skip.get_view(0).notes.has(0), "Удаление сохраняет остальные гипотезы")
	check(not skip.action(0, "note_erase", {"feature": 0, "symbol": 5}, false), "Неверная пара знака и гипотезы отклоняется")


func _topics() -> void:
	check(KHData.CROW.size() >= 50, "У Белой вороны собственный достаточный пул")
	for topic: String in KHData.CROW:
		check(not KHData.TOPICS.has(topic) and not KHData.BLITZ.has(topic), "Тема Белой вороны отделена: " + topic)
	var game := KHRules.new()
	game.new_game([{}, {}, {}], {"seed": 22})
	game.kind = "crow"
	game.host_new_theme()
	check(KHData.CROW.has(game.topics[0]), "Обычная смена темы берёт отдельный пул")
	var first: String = game.topics[0]
	game.host_new_theme()
	check(KHData.CROW.has(game.topics[0]) and game.topics[0] != first, "Повторная смена остаётся в пуле без повторов")
	game.round_no = 1
	game._start_round()
	check(game.kind == "crow" and KHData.CROW.has(game.topics[0]), "Новый раунд тоже использует отдельный пул")


func _common_form() -> void:
	var form := Form.new()
	root.add_child(form)
	current_scene = form
	var local := LocalState.new()
	local.update(form, ["match", 0, 1], {"draft": "", "selected": []}, form.rebuild)
	form.draft = "незаконченный ответ"
	form.input.text = form.draft
	form.input.caret_column = 5
	form.input.select(2, 5)
	form.input.grab_focus()
	form.selected.append(7)
	local.update(form, ["match", 0, 1], {"draft": "", "selected": []}, form.rebuild)
	check(form.input.text == "незаконченный ответ" and form.selected == [7], "Общая форма сохраняет черновик и типизированный выбор")
	check(form.input.has_focus() and form.input.caret_column == 5 and form.input.has_selection(), "Общая форма сохраняет фокус, курсор и выделение")
	var view := {"game_id": "match", "game": "будущая игра", "phase": "answer", "seat": 0, "round": 1}
	LocalState.network_update(self, view, view.duplicate(), func() -> void:
		form.rebuild()
		form.input.clear())
	check(form.input.text == "незаконченный ответ", "Общая сетевая страховка работает для неизвестной будущей игры")
	check(form.input.has_focus(), "Устойчивый ключ возвращает фокус под новым родителем")
	local.update(form, ["match", 1, 1], {"draft": "", "selected": []}, form.rebuild)
	check(form.input.text.is_empty() and form.selected.is_empty(), "Смена места очищает приватные черновики")
	form.queue_free()
	current_scene = null
	await process_frame


func _open(id: String, count: int) -> Node:
	net.host_offline(id)
	net.set_bots(count - 1)
	change_scene_to_file("res://games/" + id + "/ui/main.tscn")
	await scene_changed
	check(net.start_game().is_empty(), "Запуск " + id)
	await process_frame
	return current_scene


func _green_team() -> void:
	var app := await _open("green_team_wins", 3)
	net.green_team.cards[0] = "blank_00"
	net.gtw_seat = 0
	net._push_state()
	await process_frame
	app.edit.text = "мой незаконченный ответ"
	app.edit.text_changed.emit(app.edit.text)
	app.edit.caret_column = 4
	app.edit.grab_focus()
	check(net.green_team.action(1, "answer", {"round": 0, "answer": "кот"}, false), "Другой игрок GTW отвечает")
	net._push_state()
	await process_frame
	check(app.edit.text == "мой незаконченный ответ" and app.draft == app.edit.text, "Ввод GTW сохранён при настоящем чужом действии")
	check(app.edit.caret_column == 4 and app.edit.has_focus(), "Курсор GTW не прыгает в конец")
	await _themes_and_shots(app, "gtw")
	net.gtw_seat = 2
	net._push_state()
	check(app.draft.is_empty() and app.edit.text.is_empty(), "Смена игрока GTW скрывает предыдущий черновик")
	net.leave()
	await process_frame


func _contact_ui() -> void:
	net.settings.fc_aliens = 2
	var app := await _open("first_contact", 5)
	net.fc_seat = 0
	net._push_state()
	app._pick_card(2)
	var symbol := app.find_child("NoteSymbol", true, false) as OptionButton
	var feature := app.find_child("NoteFeature", true, false) as OptionButton
	symbol.select(6)
	feature.select(7)
	check(net.first_contact.action(1, "note", {"feature": 1, "symbol": 2}, false), "Другой землянин пишет личную заметку")
	net._push_state()
	check(app.selected == [2], "Выбранный пример сохранён при чужой заметке")
	symbol = app.find_child("NoteSymbol", true, false) as OptionButton
	feature = app.find_child("NoteFeature", true, false) as OptionButton
	check(symbol.selected == 6 and feature.selected == 7, "Списки заметок сохранены при пересборке формы")
	var changed: Dictionary = net.view.duplicate(true)
	changed.serial += 1
	app._draw_state(changed)
	check(app.selected == [2], "Общий serial не сбрасывает текущий выбор")
	await _themes_and_shots(app, "contact_human")
	net.send_action("skip_learning", {"serial": net.first_contact.serial})
	check(net.first_contact.turn == 1 and app.selected.is_empty(), "Пропуск через Net завершает ход и очищает выбор")
	net.fc_seat = net.first_contact.humans
	net._push_state()
	await _themes_and_shots(app, "contact_alien")
	check(not app.state.targets.is_empty() and app.state.get("aliens", 0) >= 1, "Инопланетянин видит задания и легенду игроков")
	net.first_contact.phase = "opening"
	net.first_contact.turn = 0
	net.fc_seat = 0
	net._push_state()
	var opening := app.find_child("OpeningFeature", true, false) as OptionButton
	opening.select(8)
	net.first_contact.action(1, "note", {"feature": 2, "symbol": 3}, false)
	net._push_state()
	opening = app.find_child("OpeningFeature", true, false) as OptionButton
	check(opening.selected == 8, "Чужая заметка не меняет выбранный признак нулевого хода")
	net.send_action("skip_learning", {"serial": net.first_contact.serial})
	check(net.first_contact.turn == 1 and net.first_contact.phase == "opening", "Нулевой ход тоже можно пропустить")
	net.leave()
	await process_frame


func _themes_and_shots(app: Node, title: String) -> void:
	var previous_fill := Color.TRANSPARENT
	for mode in ["light", "dark"]:
		prefs.theme_mode = mode
		prefs.changed.emit()
		await process_frame
		await process_frame
		var panel: Control = net.chat.panel()
		panel._repaint()
		var fill: Color = panel._button_fill()
		check(panel._button_fill().a > 0.1, "Передвижная кнопка имеет цвет игры: " + title + " " + mode)
		if mode == "dark":
			check(not fill.is_equal_approx(previous_fill), "Передвижная кнопка действительно меняет цвет с темой: " + title)
		previous_fill = fill
		check(not app.find_children("*", "ThemeToggle", true, false).is_empty(), "Штатная кнопка темы: " + title + " " + mode)
		if OS.has_environment("BATCH22_SHOTS"):
			app.top.set_menu_open(true)
			panel.set_mode(1)
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build/shots/batch22")
			root.get_texture().get_image().save_png("res://build/shots/batch22/%s_%s.png" % [title, mode])
