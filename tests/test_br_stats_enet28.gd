extends SceneTree
## Настоящая ENet-пара: личные броски BR, Store после _win и чтение отдельнымпроцессом.
## BR_STATS_ROLE=host/client/reload; BR_STATS_DIR — свежаяпапка, BR_STATS_PORT — порт.
var net: Node
var checks := 0
var errors := 0
var folder := ""
var role := ""

func _init() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func wait_for(predicate: Callable, text: String) -> bool:
	var until := Time.get_ticks_msec() + 20000
	while not predicate.call() and Time.get_ticks_msec() < until:
		await process_frame
	var ok: bool = predicate.call()
	check(ok, text)
	return ok

func write(name: String, data: Dictionary) -> void:
	var path := folder.path_join(name + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(DirAccess.rename_absolute(path + ".tmp", path) == OK, "Атомарный тестовыймаркер " + name)

func read(name: String) -> Dictionary:
	var path := folder.path_join(name + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return result if result is Dictionary else {}

func same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for face in a:
		if not b.has(face) or float(a[face]) != float(b[face]):
			return false
	return true

func tally(faces: Array) -> Dictionary:
	var result: Dictionary = {}
	for face in faces:
		result[str(face)] = int(result.get(str(face), 0)) + 1
	return result

func actual_dice(seat: int) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in net.brod.stats_rolls:
		if int(event.seat) == seat:
			for face in event.faces:
				result[str(face)] = int(result.get(str(face), 0)) + 1
	return result

func host() -> void:
	check(net.host_enet(int(OS.get_environment("BR_STATS_PORT")), "brodilka") == OK, "Хост запустилENet")
	write("listening", {"pid": OS.get_process_id()})
	if not await wait_for(func(): return net.lobby_view.get("members", []).size() == 2, "Настоящийклиент вошёл"):
		return
	check(net.start_game().is_empty(), "Бродилка стартовала длядвухучастников")
	net.set_process(false)
	check(net._game_obj() == net.brod, "ОбъектMetrics —BRRules")
	net.brod.turn = 0
	net.brod.phase = "roll"
	net.brod.prompt = {}
	net.brod.rng.seed = 17
	net.send_action("br_roll")
	var own := actual_dice(0)
	check(not own.is_empty(), "Реальныйхостовыйbr_roll записан")
	check(same(net.player_stats.summary("brodilka").dice, own), "Хостсохранил толькосвойбросок")
	net.brod.turn = 1
	net.brod.phase = "roll"
	net.brod.prompt = {}
	net.brod.rng.seed = 103
	net._push_state()
	write("ready", {"host_dice": own})
	if not await wait_for(func(): return not read("rolled").is_empty(), "Клиентдождался своегоsnapshot/Store"):
		return
	var client := actual_dice(1)
	check(not client.is_empty(), "Серверполучил br_roll настоящегоклиента")
	check(same(read("rolled").dice, client), "КлиентскийStore совпал ссервернымисобытиями места1")
	check(same(net._match_metrics.snapshot(1).totals.dice, client), "АдресныйMetrics места1 точен")
	check(same(net.player_stats.summary("brodilka").dice, own), "Чужойбросок не примешалсякхосту")
	net._push_state()
	net._push_state()
	check(same(net.player_stats.summary("brodilka").dice, own), "Повторныеpush недублируютхоста")
	write("expected", {"host_dice": own, "client_dice": client})
	# Подготовленное завершение: проверяем доставкуитога, неестественнуюполнуюпартию.
	net.brod._win(1, "Тест сохранения личныхбросков")
	net._push_state()
	if not await wait_for(func(): return not read("finished").is_empty(), "Клиентсохранил game_over"):
		return
	check(net.brod.phase == "game_over" and net.is_host(), "Хостжив после штатнойпобеды")
	check(same(net.player_stats.summary("brodilka").dice, own), "Итогхоста сохраняет егограни")
	check(net.player_stats.summary("brodilka").completed == 1 and net.player_stats.summary("brodilka").wins == 0, "Хостполучилсвойисход")
	write("allow_leave", {"ok": true})
	if not await wait_for(func(): return not read("left").is_empty(), "Клиентштатновышел"):
		return
	check(net.mode == "enet" and net.is_host() and net.in_game and net.brod.phase == "game_over", "Клиентскийвыход несбрасываетживогохоста")
	write("host_done", {"dice": own, "phase": net.brod.phase})

func client() -> void:
	check(net.join_enet("127.0.0.1", int(OS.get_environment("BR_STATS_PORT"))) == OK, "Клиентначалподключение")
	if not await wait_for(func(): return not read("ready").is_empty() and net.view.get("phase", "") == "roll" and int(net.view.get("turn", -1)) == 1, "Клиент получилсвоюphase_roll"):
		return
	check(int(net.view.seat) == 1, "Адресноеместо клиента1")
	check(net.view.personal_stats.seat == 1, "Личныйsnapshot адресованклиенту")
	check(net.player_stats.summary("brodilka").dice.is_empty(), "Хостовыйбросок не записанвклиентскийStore")
	check(not read("ready").host_dice.is_empty(), "Контроль: хост к этомувремени уже бросал")
	net.send_action("br_roll")
	if not await wait_for(func(): return not net.view.get("personal_stats", {}).get("totals", {}).get("dice", {}).is_empty(), "Реальныйклиентскийbr_roll получилsnapshot"):
		return
	var expected := tally(net.view.last_roll)
	var saved: Dictionary = net.player_stats.summary("brodilka").dice
	check(same(saved, expected), "ClientStore равен толькосвоемуlast_roll")
	check(same(net.view.personal_stats.totals.dice, expected), "Snapshot не содержитчужихбросков")
	check(FileAccess.file_exists(net.player_stats.path), "ФайлStore существуетдозавершения")
	var fresh := PlayerStatsStore.new(net.player_stats.path)
	check(same(fresh.summary("brodilka").dice, expected), "Файлпрочитан отдельнымStore добоя")
	check(not fresh.consume(net.view.personal_stats), "Повтор snapshot недублируетсохранённыеброски")
	write("rolled", {"dice": expected, "path": net.player_stats.path})
	if not await wait_for(func(): return net.view.get("phase", "") == "game_over", "Клиент увиделитогпосле_win"):
		return
	check(same(net.player_stats.summary("brodilka").dice, expected), "После game_over все собственныеброски сохранены")
	check(net.player_stats.summary("brodilka").completed == 1 and net.player_stats.summary("brodilka").wins == 1, "Итогклиента победа, неитогхоста")
	fresh = PlayerStatsStore.new(net.player_stats.path)
	check(same(fresh.summary("brodilka").dice, expected), "Файлпослепобеды содержитграни")
	check(not fresh.consume(net.view.personal_stats), "Итоговыйповтор не меняетStore")
	write("finished", {"dice": expected, "completed": 1})
	if not await wait_for(func(): return not read("allow_leave").is_empty(), "Хостподтвердил завершение"):
		return
	net.leave()
	check(same(net.player_stats.summary("brodilka").dice, expected), "Добровольныйвыход сохраняетброски")
	write("left", {"dice": expected})
	write("reload", {"dice": expected, "store_path": net.player_stats.path})

func reload_store() -> void:
	var saved := read("reload")
	check(not saved.is_empty(), "Естьрезультатпредыдущегоклиентскогопроцесса")
	var expected: Dictionary = saved.get("dice", {})
	check(not expected.is_empty(), "Естьнепустойэталонсобственныхбросков")
	check(same(net.player_stats.summary("brodilka").dice, expected), "Новыйпроцесс Net.Store читаетвсеграни")
	var fresh := PlayerStatsStore.new(str(saved.get("store_path", PlayerStatsStore.PATH)))
	check(same(fresh.summary("brodilka").dice, expected), "ОтдельныйStore новогопроцесса совпадает")
	check(fresh.summary("brodilka").completed == 1 and fresh.summary("brodilka").wins == 1, "После перезапускасохраненаоднапобеда")
	check(same(fresh.summary().dice, expected), "Общаястатистика непотерялаБродилку")

func run() -> void:
	await process_frame
	net = root.get_node("Net")
	folder = OS.get_environment("BR_STATS_DIR")
	role = OS.get_environment("BR_STATS_ROLE")
	check(net.player_stats.summary().dice.is_empty() if role != "reload" else true, "Профильпустой кроме разрешённогоперечитывания")
	if role == "host":
		await host()
	elif role == "client":
		await client()
	else:
		reload_store()
	print("BR STATS ENET: role=%s checks=%d errors=%d" % [role, checks, errors])
	if role != "client":
		net.leave()
	await process_frame
	await root.get_node("Sfx").request_quit(1 if errors else 0)
