extends SceneTree
## Локальный конфликт настоящего Luma fade и deferred-входа настоящего Hub, без сокетов.
## Dummy, свежий APPDATA; графика OpenGL. Headless дополнительно проверяет переход без эффекта.

var transition: Script
var net: Node
var checks := 0
var errors := 0
var paths: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	print("ПРОВЕРКА ПЕРЕХОДА: ", message, " = ", ok)
	if not ok:
		errors += 1


func _frames(count: int = 3) -> void:
	for i: int in count:
		await process_frame


func _wait_scene(path: String, seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			return true
		await process_frame
	return false


func _active_state(label: String) -> void:
	var active: Node = transition._active
	print("СОСТОЯНИЕ ", label, " ", JSON.stringify({
		"active": is_instance_valid(active), "path": active._path if is_instance_valid(active) else "",
		"scene_ready": active._scene_ready if is_instance_valid(active) else false,
		"switching": active._switching if is_instance_valid(active) else false,
		"scene": current_scene.scene_file_path if is_instance_valid(current_scene) else "",
		"leaving": current_scene.get("_leaving") if is_instance_valid(current_scene) and current_scene.has_method("_open_by_id") else false,
		"party_game": net.party_game, "in_game": net.in_game, "match": net.game_id
	}))


func _run() -> void:
	transition = load("res://hub/luma_wipe.gd")
	net = root.get_node("Net")
	net.set_process(false)
	# Реальные Hub/экраны, но готовое состояние без ходов и без транспорта.
	var games: Script = load("res://hub/games.gd")
	for id: String in ["wavelength", "hues_and_cues", "ready_set_bet"]:
		paths[id] = games.by_id(id).scene
	var source := Control.new()
	source.name = "ИсходныйЭкран"
	root.add_child(source)
	current_scene = source
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	check(transition.change_scene(paths.wavelength), "Исходный переход принят")
	check(await _wait_scene(paths.wavelength), "Исходная сцена открылась")
	await _frames()
	_active_state("перед возвратом")
	if DisplayServer.get_name() != "headless":
		check(is_instance_valid(transition._active), "Первый настоящий fade ещё активен")
	# Моделируем уже доставленные авторитетные метаданные перед созданием следующего Hub.
	net.mode = "enet"
	net.party_game = "hues_and_cues"
	net.in_game = true
	net.game_id = "проверка-свежая-партия"
	var rules: RefCounted = load("res://games/hues_and_cues/logic/hc_rules.gd").new()
	var players: Array = []
	for i: int in 4:
		players.append({"name": "Проверка" + str(i), "bot": false, "team": 0, "color": i})
	rules.new_game(players, 0, false, 271027)
	net.view = rules.get_view(1, false)
	net.view.merge({"game": "hues_and_cues", "game_id": net.game_id, "turn_total": 60,
		"turn_left": 60, "auto_in": 0, "clock": true, "game_paused": false}, true)
	change_scene_to_file("res://hub/hub.tscn")
	await _wait_scene("res://hub/hub.tscn")
	await _frames()
	_active_state("новый Hub после deferred")
	if DisplayServer.get_name() != "headless" and is_instance_valid(current_scene) and current_scene.has_method("_open_scene"):
		var hub: Node = current_scene
		if transition.has_method("is_running"):
			check(hub._leaving, "Принятый новый запрос не разблокировал старую коробку")
			hub._open_scene(games.by_id("wavelength"), true)
			check(transition._active._path == paths.hues_and_cues, "Обычный повторный запуск не подменил выбор хоста")
	check(await _wait_scene(paths.hues_and_cues), "Deferred Hub открыл последнюю игру несмотря на старый fade")
	_active_state("после ожидания Hues")
	# Вызов неизвестной сцены не должен отменять уже принятый переход.
	var before: Node = transition._active
	check(not transition.change_scene("res://несуществующая-сцена-проверки.tscn"), "Неизвестная сцена отвергнута")
	check(transition._active == before, "Отказ неизвестной сцены не заменил активный переход")
	if transition.has_method("is_running"):
		await _boundaries()
	net.mode = ""
	net.party_game = ""
	net.in_game = false
	if is_instance_valid(transition._active):
		transition._active.queue_free()
	await _frames()
	print("ПОСЛЕДНИЙ ПЕРЕХОД: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)


func _fixture(name: String) -> String:
	var node := Control.new()
	node.name = name
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	var path := "user://transition-" + name + ".tscn"
	ResourceSaver.save(packed, path)
	return path


func _boundaries() -> void:
	var first := _fixture("Первая")
	var second := _fixture("Вторая")
	var last := _fixture("Последняя")
	var context := {"party_game": net.party_game}
	check(transition.change_scene(first, context), "Следующий запрос пати принят")
	var active: Node = transition._active
	if is_instance_valid(active):
		active.set_process(false)
		var old_generation: int = active._generation
		check(transition.change_scene(second, context), "Запрос во время загрузки заменён")
		check(transition.change_scene(last, context), "Третий запрос во время загрузки заменён")
		var generation: int = active._generation
		check(transition.change_scene(last, context) and active._generation == generation, "Повтор актуального запроса идемпотентен")
		check(not transition.change_scene(first), "Обычный клик во время перехода отвергнут")
		active._switch_scene(old_generation)
		check(active._path == last and not active._scene_ready, "Устаревший deferred switch не изменил новую цель")
		check(active._rect.mouse_filter == Control.MOUSE_FILTER_STOP, "Слой перехода продолжает блокировать старый экран")
		active.set_process(true)
	else:
		check(transition.change_scene(second, context), "Headless принимает следующую сцену")
		check(transition.change_scene(last, context), "Headless принимает последнюю сцену")
	check(await _wait_scene(last), "Из нескольких запросов открылась последняя сцена")
	await _frames()
	if is_instance_valid(transition._active):
		check(transition.change_scene(first, context), "Начат переход для проверки настоящего async await")
		active = transition._active
		active.set_process(false)
		while ResourceLoader.load_threaded_get_status(first) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await process_frame
		active._switch_scene(active._generation)
		await scene_changed
		check(current_scene.scene_file_path == first, "Старый switch действительно дошёл до ожидания первого кадра")
		check(transition.change_scene(second, context), "Новая цель принята во время async ожидания старого switch")
		await _frames()
		check(active._path == second and not active._scene_ready, "Старый await не пометил новую сцену готовой")
		active.set_process(true)
		check(await _wait_scene(second), "После старого await открылась последняя цель")
		await _frames()
		active = transition._active
		active.set_process(false)
		var previous_generation: int = active._generation
		change_scene_to_file(first)
		await scene_changed
		check(transition.change_scene(second, context), "Повтор той же цели из нового исходного экрана принят")
		check(active._generation > previous_generation, "Повтор из другого экрана не ошибочно принят за дубль")
		active.set_process(true)
		check(await _wait_scene(second), "Та же выбранная игра повторно открылась из нового экрана")
		await _frames()
		last = second
	if is_instance_valid(transition._active):
		active = transition._active
		var old_generation: int = active._generation
		net.party_game = ""
		check(transition.cancel_party_request(), "Отмена выбора пати снимает свой переход")
		active._switch_scene(old_generation)
		check(not transition.is_running(), "Отменённое async-продолжение не восстановило переход")
		await _frames()
		check(current_scene.scene_file_path == last, "Отмена fade не переписала текущую сцену")
	net.party_game = ""
	net.mode = ""
	net.in_game = false
	net.view = {}
	check(transition.change_scene(first), "Самостоятельный переход после отмены разрешён")
	change_scene_to_file(second)
	check(await _wait_scene(second), "Внешний возврат заменил ещё не выполненный переход")
	await create_timer(0.3).timeout
	check(current_scene.scene_file_path == second, "Старый загрузчик не переписал внешний переход")
	check(not transition.is_running(), "Устаревший слой удалён после смены исходной сцены")
