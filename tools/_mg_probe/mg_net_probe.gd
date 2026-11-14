extends SceneTree
## Двухпроцессная проверка новых мини-игр по ENet: «4 в ряд» по приглашению (ходы с обеих сторон, отказ
## чужого хода), комната «Шарики» (оба видят друг друга, тики идут, выход), комната «Звёздочки» (звезду ловит гость,
## очко засчитывает хост, второй нажавший опоздал).
## Запуск (два процесса, отдельные APPDATA):
##   PROBE_ROLE=host|client PROBE_PORT=24711 godot --headless --audio-driver Dummy --path . --script res://tools/_mg_probe/mg_net_probe.gd

var role := OS.get_environment("PROBE_ROLE")
var net: Node
var mg: Node
var failed := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failed += 1
		print("ОШИБКА[%s]: %s" % [role, msg])


func _initialize() -> void:
	boot.call_deferred()


func until(cond: Callable, what: String, seconds: float = 12.0) -> bool:
	var left := seconds
	while left > 0.0:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		left -= 0.1
	check(false, "не дождались: " + what)
	return false


func boot() -> void:
	net = root.get_node("Net")
	mg = net.minigames
	net.my_name = "Хост" if role == "host" else "Гость"
	var port := int(OS.get_environment("PROBE_PORT"))
	if role == "host":
		net.host_enet(port, "")
	else:
		net.join_enet("127.0.0.1", port)
	await until(func(): return mg.targets().size() == 1, "второй участник пати", 20.0)
	await create_timer(0.5).timeout
	if role == "client":
		await client()
	else:
		await host()
	print("PROBE %s: проверок %d, ошибок %d" % [role, checks, failed])
	await create_timer(1.0).timeout
	net.leave()
	quit(1 if failed > 0 else 0)


func c4_id() -> String:
	for id: String in mg.sessions:
		if str(mg.sessions[id].game) == "connect4":
			return id
	return ""


func room_list(game: String) -> Array:
	var session: Dictionary = mg.sessions.get(mg.room_id(game), {})
	return (session.get("state", {}) as Dictionary).get("list", [])


## Ходит, пока не настанет конец партии: каждый бросает в свой столбец (сиденье 0 — столбец 0, 1 — столбец 1).
func play_c4() -> void:
	while true:
		var id := c4_id()
		if id == "":
			return
		var session: Dictionary = mg.sessions[id]
		var state: Dictionary = session.state
		if bool(state.over):
			return
		if int(state.turn) == int(session.seat):
			var moves := int(state.moves)
			mg.move(id, {"col": int(session.seat)})
			await until(func(): return int(mg.sessions[c4_id()].state.moves) > moves, "свой ход вернулся от хоста")
		else:
			await create_timer(0.1).timeout


func client() -> void:
	mg.invite(1, "connect4")
	await until(func(): return c4_id() != "", "партия «4 в ряд» началась")
	var id := c4_id()
	var session: Dictionary = mg.sessions.get(id, {})
	if int(session.get("seat", 0)) != int((session.get("state", {}) as Dictionary).get("turn", 0)):
		var moves := int(session.state.moves)
		mg.move(id, {"col": 3})  # не мой ход — хост откажет
		await create_timer(0.6).timeout
		check(int(mg.sessions[id].state.moves) == moves, "4 в ряд: чужой ход отклонён хостом")
	await play_c4()
	var state: Dictionary = mg.sessions[c4_id()].state
	check(bool(state.over) and int(state.winner) in [0, 1], "4 в ряд: партия закончилась четвёркой")
	# шарики
	mg.join_room("balls")
	await until(func(): return room_list("balls").size() == 2, "в шариках двое")
	var seq_seen := {}
	for i in 20:
		var snap: Dictionary = mg.sessions[mg.room_id("balls")].state
		seq_seen[snap.get("left", 0.0)] = true
		await create_timer(0.1).timeout
	check(seq_seen.size() >= 5, "шарики: тики от хоста идут (%d разных снимков за 2 с)" % seq_seen.size())
	mg.room_act("balls", {"aim": Vector2(0.5, 0.0), "on": true})
	mg.room_act("balls", {"dash": true})
	await create_timer(0.5).timeout
	# звёздочки: ловит гость
	mg.join_room("stars")
	await until(func(): return room_list("stars").size() == 2, "в звёздочках двое")
	await until(func(): return not (mg.sessions[mg.room_id("stars")].state.star as Dictionary).is_empty(), "звезда появилась у гостя", 15.0)
	var star: Dictionary = mg.sessions[mg.room_id("stars")].state.star
	mg.room_act("stars", {"catch": int(star.id)})
	await until(func(): return room_list("stars").any(func(row: Array) -> bool: return int(row[0]) != 1 and int(row[3]) == 1), "очко гостю засчитано")
	await create_timer(1.0).timeout
	mg.close(mg.room_id("balls"))
	await create_timer(1.5).timeout


func host() -> void:
	await until(func(): return not (mg.invites_in as Array).is_empty(), "приглашение от гостя")
	mg.answer(str(mg.invites_in[0].id), true)
	await until(func(): return c4_id() != "", "партия «4 в ряд» у хоста")
	await play_c4()
	var state: Dictionary = mg.sessions[c4_id()].state
	check(bool(state.over), "4 в ряд: у хоста партия тоже закончилась")
	mg.join_room("balls")
	await until(func(): return room_list("balls").size() == 2, "в шариках двое (хост)")
	mg.join_room("stars")
	await until(func(): return room_list("stars").size() == 2, "в звёздочках двое (хост)")
	# первую звезду (номер 1) ловит гость; хост жмёт по ней после — опоздал
	await until(func(): return room_list("stars").any(func(row: Array) -> bool: return int(row[0]) != 1 and int(row[3]) == 1), "очко гостя видно хосту", 20.0)
	mg.room_act("stars", {"catch": 1})
	await create_timer(0.3).timeout
	var mine := room_list("stars").filter(func(row: Array) -> bool: return int(row[0]) == 1)
	check(not mine.is_empty() and int(mine[0][3]) == 0, "звёздочки: опоздавший хост без очка")
	await until(func(): return room_list("balls").size() == 1, "гость вышел из шариков")
