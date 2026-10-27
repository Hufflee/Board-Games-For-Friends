## Независимые границы UI27: настоящий Prefs.changed, мышь/реплика, lifecycle вступления.
## Графическая сцена, Dummy/свой APPDATA. Подготовленные значения явно отмечены; не полная партия.
extends "res://tests/test_batch27_ui.gd"

func theme_switch() -> Control:
	Prefs.theme_mode = "dark" if Prefs.theme_mode != "dark" else "light"
	Prefs.changed.emit()
	await settle()
	return get_tree().current_scene

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/batch27_ui/low-" + name + ".png")

func _run() -> void:
	Net.settings.hc_mode = "distorted"
	var app := await start_game("hues_and_cues")
	var table: Control = app.screen
	table._board.set_process(false)
	# Явный визуальный fixture в середине prepare, серверный ход не продвигаем таймером.
	table._board._process(1.5)
	var elapsed: float = table._board._reveal_elapsed
	var game: String = Net.game_id
	var round_no: int = Net.hues.round_no
	check(Net.hues.phase == "prepare" and table._board._reveal_active, "Crazy действительно в prepare до смены темы")
	app = await theme_switch()
	table = app.screen
	table._board.set_process(false)
	check(Net.game_id == game and Net.hues.round_no == round_no and Net.hues.phase == "prepare", "Тема не меняет серверную партию/раунд/prepare")
	check(table._board._reveal_active and table._board._distort_intro, "Crazy в подготовке сохраняет тип и активность анимации")
	check(table._board._reveal_elapsed >= elapsed and table._board._reveal_elapsed < elapsed + 1.0, "Prepare продолжился, не начался с нуля и не завершился мгновенно")
	# Реально завершаем визуальный процесс и штатную серверную prepare.
	table._board._process(10.0)
	check(Net.hues.finish_prepare(), "Штатный finish_prepare принят")
	Net._push_state()
	app = await theme_switch()
	table = app.screen
	table._board.set_process(false)
	check(not table._board._reveal_active and Net.hues.phase == "pick", "После завершения тема не перезапускает Crazy intro")
	# Подготовленный следующий раунд через родной метод правил; не заявляем полную сыгранную раздачу.
	Net.hues._start_round()
	Net._push_state()
	check(Net.hues.round_no == round_no + 1 and Net.hues.phase == "prepare", "Подготовлен следующий настоящий раунд")
	check(table._board._reveal_active and table._board._reveal_elapsed < 0.1, "Свежий раунд всё ещё начинает новую анимацию")
	check(table.distorted_resume.is_empty(), "Одноразовый resume предыдущего раунда израсходован")
	table._board._process(10.0)
	Net.hues.finish_prepare()
	Net._push_state()
	for mode: String in ["dark", "light"]:
		if Prefs.theme_mode != mode:
			Prefs.theme_mode = mode
			Prefs.changed.emit()
			await settle()
			app = get_tree().current_scene
			table = app.screen
		await click(table._top._chat_btn)
		check(table._top.chat.expanded, "Мышь открывает чат: " + mode)
		await click(table._top.chat._input)
		check(table._top.chat._input.has_focus(), "Мышь попадает в поле, не в доску: " + mode)
		await click(table._top.chat._quick_btn)
		check(table._top.chat.quick_open, "Мышь открывает быстрые фразы: " + mode)
		var phrase: Button = table._top.chat._quick.get_child(0)
		var before: int = Net.chat_log.size()
		await shot("chat-" + mode)
		await click(phrase)
		check(Net.chat_log.size() == before + 1, "Настоящий клик отправил ровно одну фразу: " + mode)
		if Net.chat_log.size() > before:
			check(Net.chat_log.back().kind == "emote" and Net.chat_log.back().text == "Думаю...", "Содержимое отправленной реплики правильное: " + mode)
		check(not table._top.chat.quick_open, "Фразы свернулись после отправки: " + mode)
		check(table._top.chat._log.get_parsed_text().contains("Думаю..."), "Реплика видна в журнале чата: " + mode)
		await click(table._top._chat_btn)
	await close_game(app)
	Net.settings.hc_mode = "normal"
	app = await start_game("hues_and_cues")
	table = app.screen
	check(table._board._reveal_active and not table._board._distort_intro, "Classic Hues сохраняет обычное вступление")
	table._board.set_process(false)
	table._board._process(10.0)
	app = await theme_switch()
	table = app.screen
	check(table._board._reveal_active and not table._board._distort_intro, "Classic после темы по-прежнему проигрывает обычное окрашивание")
	check(table._board._reveal_elapsed < 1.0, "Classic intro после темы новый, не Crazy resume")
	await close_game(app)
	app = await start_game("stillion")
	for i in 2:
		table = app.screen
		table.set_process(false)
		table._cannon.set_process(false)
		# Явный визуальный fixture посреди поворота; ни выстрел, ни игровой исход не подменяются.
		table._cannon._angle = 1.7
		table._cannon.aim = 2.4
		table._cannon._frame = 2
		table._cannon._old_frame = 1
		table._cannon._turn_blend = 0.65
		table._cannon._anger = 0.8
		table._answer.text = "Черновик low"
		var previous: Control = table
		Prefs.theme_mode = "dark" if Prefs.theme_mode != "dark" else "light"
		Prefs.changed.emit()
		table = app.screen
		table.set_process(false)
		table._cannon.set_process(false)
		check(table != previous, "Настоящий Prefs.changed пересобрал Stillion table")
		check(is_equal_approx(table._cannon._angle, 1.7) and is_equal_approx(table._cannon.aim, 2.4), "Prefs.changed сохраняет угол/цель в тот же кадр")
		check(table._cannon._frame == 2 and is_equal_approx(table._cannon._turn_blend, 0.65), "Prefs.changed сохраняет промежуточную стадию поворота")
		check(is_equal_approx(table._cannon._anger, 0.8) and table._answer.text == "Черновик low", "Сохранились выражение и черновик")
		table._cannon._process(0.1)
		check(table._cannon._angle > 1.7 and table._cannon._angle < 2.4, "После темы настоящий process продолжает поворот к цели")
		await shot("st-cannon-" + str(i))
	await close_game(app)
	print("BATCH27 LOW REVIEW: ", checks, " проверок, ", errors, " ошибок")
	await Sfx.request_quit(1 if errors else 0)
