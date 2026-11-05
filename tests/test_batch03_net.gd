extends SceneTree
## Два реальных ENet-процесса: публичная неизвестная коробка и исключение из пати хостом.
var checks := 0
var errors := 0
const OUT := "res://build/batch03_net"
var net: Node
var closed := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors += 1; push_error(message)

func wait_for(test: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while not test.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.025).timeout
	check(test.call(), message)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	net = root.get_node("Net")
	var host := OS.get_environment("B03_ROLE") == "host"
	net.my_name = "Хост" if host else "Друг"
	if host:
		check(net.host_enet(23673, "") == OK, "Сервер пати открыт")
		await wait_for(func(): return net.members.size() == 2, "Друг вошёл в главное меню")
		var id := "custom:12345678-1234-4234-8234-123456789abc"
		var snapshot := {"config": {"rows": 1, "cols": 1, "cups": 0, "width": 1.0, "height": 0.4}, "placements": [["king_of_12", id]], "poses": {}, "custom": {id: {"title": "Моя игра", "size": [0.05, 0.2, 0.2]}}}
		net.publish_public_room(snapshot)
		await wait_for(func(): return FileAccess.file_exists(OUT + "/received"), "Друг получил комнату с пользовательской коробкой")
		net.kick_peer(1)
		check(net.members.has(1), "Хост не исключает себя")
		for peer: int in net.members.keys():
			if peer > 1: net.kick_peer(peer)
		await wait_for(func(): return net.members.size() == 1, "Исключённый участник удалён из пати")
	else:
		await create_timer(0.4).timeout
		net.session_closed.connect(func(reason: String): closed = reason)
		check(net.join_enet("127.0.0.1", 23673) == OK, "Подключение к пати")
		await wait_for(func(): return net.public_rooms.has(1), "Получен публичный снимок хоста")
		check(net.public_rooms.get(1, {}).get("custom", {}).size() == 1, "Неизвестная коробка прошла сетевую очистку")
		var marker := FileAccess.open(OUT + "/received", FileAccess.WRITE)
		marker.store_string("готово")
		marker.close()
		await wait_for(func(): return not closed.is_empty(), "Клиент получил завершение сессии после кика")
		check(not net.in_session(), "После исключения клиент свободен для новой пати")
	net.leave()
	print("BATCH03 NET %s: %d проверок, %d ошибок" % ["host" if host else "client", checks, errors])
	quit(1 if errors else 0)
