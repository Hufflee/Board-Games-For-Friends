extends SceneTree
## Два процесса ENet: адресные руки, неподдельное место, отключение/возврат и полная JSON-партия.

const OUT := "res://build/editor_stage2"
const PORT := 23671
const Library := preload("res://games/custom/logic/cg_library.gd")
const Package := preload("res://games/custom/logic/cg_package.gd")
var role := OS.get_environment("CG_ROLE")
var custom := OS.get_environment("CG_CUSTOM") == "1"
var net: Node
var count := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	count += 1
	if not ok:
		errors += 1
		push_error(text)

func wait_until(test: Callable, text: String) -> void:
	var start := Time.get_ticks_msec()
	while not test.call() and Time.get_ticks_msec() - start < 12000:
		await create_timer(0.025).timeout
	check(bool(test.call()), text)

func mark(id: String) -> void:
	var file := FileAccess.open(OUT + "/" + id, FileAccess.WRITE)
	file.store_string("готово")

func send(action: Dictionary) -> void:
	var data := action.duplicate(true)
	data.revision = net.view.revision
	net.send_action(str(action.kind), data)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	net = root.get_node("Net")
	net.my_name = "Хост редактора" if role == "host" else "Друг редактора"
	if role == "host":
		var game := "cg"
		if custom:
			var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
			for zone: Dictionary in definition.layout.screens[0].items:
				if zone.get("id") == "table":
					zone["free"] = true
					zone["view"] = "free"
			var created := Library.create(definition)
			check(created.error.is_empty(), "Автор создал игру в своём профиле")
			var image := Image.create(512, 512, false, Image.FORMAT_RGB8)
			var rng := RandomNumberGenerator.new()
			rng.seed = 13
			for y in 512:
				for x in 512:
					image.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf()))
			var bytes := image.save_png_to_buffer()
			var hash_value := Package.sha(bytes)
			var directory := Library.folder(created.id) + "/assets/img"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			var file := FileAccess.open(directory + "/" + hash_value + ".png", FileAccess.WRITE)
			file.store_buffer(bytes)
			file.close()
			var with_asset: Dictionary = created.definition
			with_asset["assets"] = {hash_value: {"path": "assets/img/" + hash_value + ".png", "source": "Свой тестовый шум"}}
			check(Library.save(str(created.id), with_asset).error.is_empty(), "Исходный ассет зарегистрирован в проекте")
			game = "custom:" + str(created.id)
		check(net.host_enet(PORT, game) == OK, "Сервер cg запущен")
		await wait_until(func(): return net.members.size() == 2, "Друг подключился")
		if custom:
			check(int(net.cg_transfer.manifest.get("size", 0)) > Package.CHUNK, "Пакет требует несколько частей")
			await wait_until(func(): return net.members.size() == 2 and FileAccess.file_exists(OUT + "/package_ready_client") and net.cg_transfer.can_start(), "Клиент скачал и проверил пакет после обрыва")
		net.set_bots(0)
		net.set_setting("cg_example", "card_race")
		check(net.start_game().is_empty(), "Сетевая JSON-партия начата")
		await wait_until(func(): return FileAccess.file_exists(OUT + "/attempt"), "Клиент проверил подмену места")
		await create_timer(0.15).timeout
		check(net.cg.state.revision == 0 and net.cg.state.current == 0 and net.cg_view_seat == 0, "Клиент не может действовать за хоста")
		send(net.view.legal[0])
		await wait_until(func(): return net.cg.state.turn_no == 3, "Друг сыграл собственную карту")
		var hand: Array = net.cg.state.zones["hand@1"].duplicate()
		await wait_until(func(): return net.disconnected.has(1), "Отключение зарегистрировано")
		check(not net.cg.players[1].bot and net.cg.state.zones["hand@1"] == hand, "Место ждёт человека с прежними картами")
		mark("offline_seen")
		await wait_until(func(): return not net.disconnected.has(1) and net.members.size() == 2, "Друг вернул прежнее место")
		mark("resumed")
	else:
		if custom:
			check(Library.list().is_empty(), "До подключения у клиента нет авторской игры")
		await create_timer(0.5).timeout
		check(net.join_enet("127.0.0.1", PORT) == OK, "Подключение к cg")
		if custom:
			await wait_until(func(): return net.cg_transfer._incoming.size() >= Package.CHUNK and not net.cg_transfer.manifest.is_empty(), "Принята первая часть пакета")
			var partial: int = net.cg_transfer._incoming.size()
			check(partial < int(net.cg_transfer.manifest.size) and not net.in_game, "Игра ждёт загрузки пакета")
			net.leave()
			check(net.cg_transfer._incoming.size() == partial, "Части сохранены после обрыва")
			await create_timer(0.25).timeout
			check(net.join_enet("127.0.0.1", PORT) == OK, "Возврат во время загрузки")
			await wait_until(func(): return not net.cg_transfer.manifest.is_empty() and net.cg_transfer.verified.get(net.multiplayer.get_unique_id(), "") == net.cg_transfer.manifest.get("hash"), "Пакет докачан и проверен")
			mark("package_ready_client")
		await wait_until(func(): return net.is_custom_game(str(net.view.get("game", ""))) and net.view.get("zones", {}).has("hand@1"), "Получен адресный стол")
		if custom:
			var manifest: Dictionary = net.cg_transfer.manifest
			check(not manifest.is_empty() and Library.cached(str(manifest.hash)).error.is_empty(), "Клиент получил полный пакет по хэшу")
			check(Library.list().is_empty() and str(net.view.game).begins_with("custom:"), "Полученная игра только в кэше, не на полке клиента")
		check(net.view.seat == 1 and not net.view.hotseat, "Сетевой клиент имеет своё место")
		check(net.view.zones["hand@0"][0] == {"hidden": true} and net.view.zones["hand@1"][0].has("id"), "Чужие id/числа скрыты")
		check(net.view.legal.is_empty(), "В чужой ход действия отсутствуют")
		net.send_action("view_seat", {"seat": 0})
		net.send_action("card", {"id": "play", "card": net.view.zones["hand@1"][0].id, "as": 0, "revision": net.view.revision})
		mark("attempt")
		await wait_until(func(): return net.view.get("current") == 1 and not net.view.legal.is_empty(), "Хост передал ход")
		send(net.view.legal[0])
		await wait_until(func(): return net.view.get("turn_no") == 3, "Собственная карта подтверждена")
		var old_hand: Array = net.view.zones["hand@1"].duplicate(true)
		var match_id := str(net.view.game_id)
		net.leave()
		await wait_until(func(): return FileAccess.file_exists(OUT + "/offline_seen"), "Хост увидел отключение")
		check(net.join_enet("127.0.0.1", PORT) == OK, "Повторное подключение")
		await wait_until(func(): return net.view.get("game_id", "") == match_id, "Возвращена та же партия")
		check(net.view.seat == 1 and net.view.zones["hand@1"] == old_hand, "Та же рука и место после возврата")
		mark("resumed_client")
	await wait_until(func(): return FileAccess.file_exists(OUT + "/resumed_client"), "Клиент подтвердил восстановление")
	if custom:
		if role == "client":
			var actions: Array = net.view.legal.filter(func(action: Dictionary): return action.kind == "manual_place")
			check(not actions.is_empty(), "Хост разрешил свободное размещение компонента")
			if not actions.is_empty():
				var action: Dictionary = actions[0].duplicate(true)
				action.pos = [0.2, 0.7]
				send(action)
				await wait_until(func(): return net.view.zones.table.any(func(card: Dictionary): return card.get("pos") == [0.2, 0.7]), "Клиент получил подтверждённую координату с хоста")
			mark("free_placed")
			await wait_until(func(): return FileAccess.file_exists(OUT + "/free_seen"), "Хост подтвердил сетевую координату")
		else:
			await wait_until(func(): return FileAccess.file_exists(OUT + "/free_placed"), "Друг разместил компонент в свободной зоне")
			check(net.cg.state.cards.values().any(func(card: Dictionary): return card.get("pos") == [0.2, 0.7]), "Координата проверена и сохранена авторитетным хостом")
			mark("free_seen")
	var started := Time.get_ticks_msec()
	while net.view.get("phase") != "game_over" and Time.get_ticks_msec() - started < 12000:
		if net.view.get("current") == net.view.get("seat") and not net.view.get("legal", []).is_empty():
			send(net.view.legal[0])
		await create_timer(0.05).timeout
	check(net.view.get("phase") == "game_over" and not net.view.get("winners", []).is_empty(), "Полная партия завершена по ENet")
	if role == "client":
		mark("done")
	else:
		await wait_until(func(): return FileAccess.file_exists(OUT + "/done"), "Клиент получил финал")
	print("CUSTOM_ENET_%s: %d проверок, ошибок %d" % [role, count, errors])
	net.leave()
	quit(1 if errors else 0)
