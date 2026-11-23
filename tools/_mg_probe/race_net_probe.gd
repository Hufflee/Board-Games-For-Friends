extends SceneTree
## Два процесса ENet: вход в гонку, отсчёт, ввод гостя, финиши, другая трасса и выход.
## RACE_ROLE=host|client RACE_PORT=24731, отдельный APPDATA, --headless --audio-driver Dummy.

const Race := preload("res://hub/minigames/logic/mg_race.gd")
var net: Node
var mg: Node
var role := OS.get_environment("RACE_ROLE")
var errors := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		errors += 1
		printerr("ОШИБКА [%s]: %s" % [role, text])


func until(condition: Callable, text: String) -> bool:
	for i in 180:
		if condition.call():
			return true
		await create_timer(0.1).timeout
	check(false, "таймаут: " + text)
	return false


func snap() -> Dictionary:
	return mg.sessions.get("room_race", {}).get("state", {})


func _run() -> void:
	net = root.get_node("Net")
	mg = net.minigames
	net.my_name = "Хост" if role == "host" else "Гость"
	var port := int(OS.get_environment("RACE_PORT"))
	if role == "host":
		net.host_enet(port, "")
	else:
		net.join_enet("127.0.0.1", port)
	if not await until(func(): return mg.targets().size() == 1, "соединение"):
		quit(1)
		return
	mg.join_room("race")
	if not await until(func(): return snap().get("list", []).size() == 2, "оба игрока в комнате"):
		quit(1)
		return
	check(snap().phase == "countdown", "Вход второго игрока виден как отсчёт")
	var old_track := int(snap().track)
	if role == "host":
		var state: Dictionary = mg._rooms.race.state
		var guest := int(mg.targets()[0].peer)
		var initial: Vector2 = state.players[guest].pos
		await create_timer(0.4).timeout
		check((state.players[guest].pos as Vector2).distance_to(initial) < 0.0001, "Ввод гостя не двигает шарик до старта")
		state.until = float(state.time) + 0.3
		if not await until(func(): return state.phase == "race" and bool(state.players[guest].steer), "ввод гостя после старта"):
			quit(1)
			return
		check(bool(state.players[guest].steer), "Ненадёжный канал ввода доставляет управление именно гонке")
		# Довести гонщиков по всем точкам трёх кругов, сохраняя обычную сетевую рассылку.
		for peer: int in state.players:
			state.players[peer].u = 0.0
			state.players[peer].progress = 0.0
			state.players[peer].lap = 0
			for k in 3:
				for i in range(1, Race.SAMPLES + 1):
					Race._progress(state, peer, fposmod(float(i) / Race.SAMPLES, 1.0))
		mg._room_push("race")
		check(state.phase == "results", "После двух финишей хост завершает гонку")
	else:
		mg.room_act("race", {"aim": Race.track(old_track)[3], "on": true})
		if not await until(func(): return snap().get("phase", "") in ["race", "results"], "начало гонки"):
			quit(1)
			return
		mg.room_act("race", {"aim": Race.track(old_track)[3], "on": true})
		if not await until(func(): return snap().get("phase", "") == "results", "финиши"):
			quit(1)
			return
		check(snap().finish.size() == 2, "Гость получил обоих финишировавших")
	if not await until(func(): return int(snap().get("track", old_track)) != old_track, "другая трасса"):
		quit(1)
		return
	check(snap().phase == "countdown", "Новая трасса начинается с нового отсчёта")
	if role == "client":
		await create_timer(1.0).timeout
		mg.close("room_race")
		await create_timer(0.5).timeout
	else:
		await until(func(): return mg._rooms.race.state.players.size() == 1, "выход гостя")
		check(mg._rooms.race.state.phase == "solo", "После выхода гостя хост снова в соло")
	print("СЕТЬ ГОНКИ %s: %d проверок, %d ошибок" % [role, checks, errors])
	net.leave()
	quit(1 if errors else 0)
