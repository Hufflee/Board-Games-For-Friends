extends SceneTree
## Свежий профиль: Net→BRRules→MatchMetrics→Store→экран и отдельный перезапуск.
## --audio-driver Dummy --path . --script res://tests/test_batch28_stats.gd
## STATS_READ=1 повторяет чтение в новом процессе с тем же тестовым APPDATA.

var checks := 0
var errors := 0
var net: Node
var expected: Dictionary = {}

func _init() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func frames(count: int = 5) -> void:
	for i in count:
		await process_frame

func same_counts(a: Dictionary, b: Dictionary) -> bool:
	# JSON читает числа как float; проверяем все ключи и точные численные значения.
	if a.size() != b.size():
		return false
	for face in a:
		if not b.has(face) or float(a[face]) != float(b[face]):
			return false
	return true

func own_dice() -> Dictionary:
	var dice: Dictionary = {}
	for event: Dictionary in net.brod.stats_rolls:
		if int(event.seat) != 0:
			continue
		for face in event.faces:
			dice[str(face)] = int(dice.get(str(face), 0)) + 1
	return dice

func screen(filter_game: String, label: String) -> void:
	var ui: Control = load("res://hub/player_stats_screen.gd").new()
	root.add_child(ui)
	await frames()
	var picker: OptionButton = ui.find_children("*", "OptionButton", true, false)[0]
	picker.select(ui._game_ids.find(filter_game))
	ui._filter = filter_game
	ui._rebuild()
	await frames()
	var body: VBoxContainer = ui._body
	var collection: Control = body.find_child("CoinsCollection", false, false)
	check(collection != null and collection == body.get_child(body.get_child_count() - 1), "Коллекция монет последняя: " + label)
	for row in collection.get_children():
		if row is HBoxContainer:
			var title: Control = row.get_child(0)
			var count: Control = row.get_child(1)
			var gap := count.global_position.x - title.get_global_rect().end.x
			check(gap >= 7.0 and gap <= 9.0, "Название и количество разделены8px: " + str((title as Label).text))
	var counts: Array = []
	for line in body.get_children():
		if line is HBoxContainer and line.get_child_count() == 3 and line.get_child(1) is ProgressBar:
			counts.append((line.get_child(2) as Label).text)
	check(counts.size() == expected.size(), "Экран выводит все учтённые грани: " + label)
	var ordered := PlayerStatsStore.sorted_dice({"dice": expected})
	for i in mini(counts.size(), ordered.size()):
		check(counts[i] == "%.1f%% · %d раз" % [ordered[i].percent, ordered[i].count], "Экран сохраняет число/проценты: " + label)
	if DisplayServer.get_name() != "headless":
		var scroll := body.get_parent() as ScrollContainer
		scroll.scroll_vertical = 100000
		await frames()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/shots/batch28_stats")
		root.get_texture().get_image().save_png("res://build/shots/batch28_stats/%s.png" % label)
	ui.queue_free()
	await frames()

func run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	if OS.get_environment("STATS_READ") == "1":
		expected = JSON.parse_string(FileAccess.get_file_as_string("user://stats_expected.json"))
		check(net.player_stats.summary("brodilka").dice == expected, "Новый процесс читает все броски с диска")
		check(net.player_stats.summary("brodilka").completed == 1, "Завершённая партия пережила перезапуск")
		await screen("brodilka", "restart-filtered")
	else:
		check(net.player_stats.summary().dice.is_empty(), "Изолированный профиль пуст")
		net.host_offline("brodilka")
		net.set_bots(1)
		check(net.start_game().is_empty(), "Бродилка запущена через Net")
		net.set_process(false)
		net.brod.rng.seed = 103
		check(net._game_obj() == net.brod, "Metrics получает именно BRRules")
		# Настоящий br_roll из стартовой фазы, не ручная запись stats_rolls.
		net.send_action("br_roll", {"as": 0})
		expected = own_dice()
		check(not expected.is_empty(), "BRRules записал настоящий бросок")
		check(net._match_metrics.snapshot(0).totals.dice == expected, "MatchMetrics сохранил личные грани")
		check(net.view.personal_stats.totals.dice == expected, "Net передал накопительный снимок")
		check(net.player_stats.summary("brodilka").dice == expected, "Store принял снимок Net")
		var previous := expected.duplicate(true)
		net._push_state()
		net._push_state()
		check(net.player_stats.summary("brodilka").dice == previous, "Повтор состояния не дублирует бросок")
		# Сокращаем путь до финиша только в fixture; победа — настоящим br_roll.
		var attempts := 0
		while net.brod.phase != "game_over" and attempts < 100:
			net.brod.pos[0] = BRBoard.finish()
			net.brod.turn = 0
			net.brod.phase = "roll"
			net.brod.prompt = {}
			net.send_action("br_roll", {"as": 0})
			attempts += 1
		check(net.brod.phase == "game_over", "Финишный бросок завершил партию")
		expected = own_dice()
		check(net._match_metrics.snapshot(0).totals.dice == expected, "Итоговый Metrics не потерял прошлые броски")
		check(net.player_stats.summary("brodilka").dice == expected, "После партии Store содержит все личные броски")
		check(net.player_stats.summary("brodilka").completed == 1, "Партия учтена ровно один раз")
		var reload_store := PlayerStatsStore.new()
		check(same_counts(reload_store.summary("brodilka").dice, expected), "Повторное чтение файла совпадает")
		check(not reload_store.consume(net.view.personal_stats), "Перезагруженный Store отвергает повтор итогового пакета")
		await screen("brodilka", "after-game-filtered")
		net.end_game()
		check(net.player_stats.summary("brodilka").dice == expected, "Возврат в лобби сохраняет броски")
		await screen("", "after-game-all")
		# Адресный клиентский снимок без настоящего транспорта: другой игрок учитывается отдельно.
		var logic := BRRules.new()
		logic.new_game([{"name": "Хост"}, {"name": "Клиент"}], 19)
		logic._set_roll([2, 6], 0)
		logic._set_roll([3, 4], 1)
		var metrics := MatchMetrics.new()
		metrics.observe("client-fixture", "brodilka", logic, [1, 2])
		var client_store := PlayerStatsStore.new("user://client-fixture.json")
		check(client_store.consume(metrics.snapshot(1)), "Адресный снимок клиента принят отдельным Store")
		check(client_store.summary("brodilka").dice == {"3": 1, "4": 1}, "Клиент не получает броски хоста")
		check(not client_store.consume(metrics.snapshot(1)), "Повтор клиентского снимка не удваивает броски")
		var client_reload := PlayerStatsStore.new("user://client-fixture.json")
		check(same_counts(client_reload.summary("brodilka").dice, {"3": 1, "4": 1}), "Клиентский файл сохраняет счётчики")
		logic.players[1]["bot"] = true
		metrics.observe("bot-fixture", "brodilka", logic, [1, 0])
		check(metrics.snapshot(1).is_empty(), "Отсутствующий/ботовый владелец не выдаёт личную статистику")
		var file := FileAccess.open("user://stats_expected.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(expected))
		file.close()
		net.leave()
	print("STATS FOLLOWUP: %d проверок, %d ошибок; dice=%s" % [checks, errors, JSON.stringify(expected)])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
