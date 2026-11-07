extends SceneTree
## Передача партии новому хосту: состояние каждой игры упаковывается и распаковывается без потерь.
## Для каждой игры: партия на одном компьютере, немного ходов ботов/таймаутов, упаковка → распаковка
## поверх Net, сравнение view каждого места до и после, затем партия идёт дальше без ошибок.
## godot --headless --audio-driver Dummy --path . --script res://tests/test_host_handoff.gd
const Handoff := preload("res://games/king_of_12/net/host_handoff.gd")
const GAMES := ["king_of_12", "perudo", "wavelength", "dangerous_words", "hues_and_cues", "ready_set_bet", "word_slam", "tip_top", "not_a_hat", "gloom", "brodilka", "phantom_ink", "four_souls", "stillion", "the_gang", "things_in_rings", "khorom", "the_mind", "poker", "machi_koro", "blood_on_the_clocktower"]
var fails := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("ОШИБКА: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _views(net: Node) -> Array:
	var out := []
	for s in net.seat_peers.size():
		# «time» — текущие часы (статистика партии), сравнивать незачем
		var v: Dictionary = net._seat_view(s, [], 0.0, true)
		out.append(_no_time(var_to_str(v)))
	return out


func _no_time(text: String) -> String:
	var re := RegEx.create_from_string("\"time\": [0-9]+")
	return re.sub(text, "\"time\": 0", true)


func _run() -> void:
	var net: Node = root.get_node("Net")
	var only := OS.get_environment("GAME")
	for g: String in GAMES:
		if only != "" and g != only:
			continue
		net.host_offline(g)
		net.set_bots(6 if g == "blood_on_the_clocktower" else 3)
		net.set_setting("turn_time", 30)
		var err: String = net.start_game()
		if not net.in_game:
			print("— ", g, ": партия не началась (", err, ")")
			continue
		Engine.time_scale = 20.0
		for i in 30:
			await process_frame
			await create_timer(0.05).timeout
		Engine.time_scale = 1.0
		var before := _views(net)
		var obj_before: Object = net._game_obj()
		var t := Time.get_ticks_msec()
		var bytes: PackedByteArray = Handoff.pack_net(net)
		var pack_ms := Time.get_ticks_msec() - t
		var vars: Dictionary = Handoff.unpack(bytes, self)
		Handoff.apply_net(net, vars)
		var after := _views(net)
		check(net._game_obj() != obj_before and net._game_obj() != null, g + ": объект правил заменён распакованным")
		var same := before == after
		if not same:
			for s in before.size():
				if before[s] != after[s]:
					var a: String = before[s]
					var b: String = after[s]
					var k := 0
					while k < mini(a.length(), b.length()) and a[k] == b[k]:
						k += 1
					print("   место ", s, " расходится: …", a.substr(maxi(0, k - 80), 160).replace("\n", " "), "\n   после: …", b.substr(maxi(0, k - 80), 160).replace("\n", " "))
					break
		check(same, g + ": view всех мест совпадает после передачи")
		print("· ", g, ": ", bytes.size() / 1024, " КБ, упаковка ", pack_ms, " мс, потеряно значений ", bytes.decode_u32(4), ", мест ", before.size())
		Engine.time_scale = 20.0
		for i in 20:
			await process_frame
			await create_timer(0.05).timeout
		Engine.time_scale = 1.0
		check(net.in_game, g + ": партия продолжается после передачи")
		net.leave()
		await process_frame
	print("ПЕРЕДАЧА ХОСТА: ", checks, " проверок, ", fails, " ошибок")
	quit(1 if fails > 0 else 0)
