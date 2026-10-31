extends SceneTree
## Тест панели хоста (HostTools): снимок → игра идёт с ботами → восстановление даёт то же состояние;
## отмена/повтор через Net; таймер. Запуск:
## godot --headless --audio-driver Dummy --path . --script res://tests/test_host_tools.gd

const GAMES := ["king_of_12", "perudo", "poker", "hues_and_cues", "brodilka", "gloom", "word_slam", "wavelength", "things_in_rings", "khorom", "not_a_hat", "tip_top", "dangerous_words", "ready_set_bet", "stillion", "the_gang", "phantom_ink"]

var _fails := 0
var _checks := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("ПРОВАЛ: ", msg)


func _init() -> void:
	_run.call_deferred()


func _state(g: Object) -> String:
	var tools: Script = load("res://games/king_of_12/net/host_tools.gd")
	return str(tools.call("snapshot", g))


func _run() -> void:
	await process_frame
	var net: Node = root.get_node("Net")
	for game: String in GAMES:
		net.host_offline(game)
		net.set_bots(3 if game != "the_gang" else 3)
		var err: String = net.start_game()
		if not err.is_empty():
			print("пропуск %s: %s" % [game, err])
			continue
		var g: Object = net._game_obj()
		check(g != null, game + ": есть правила")
		var before := _state(g)
		var tools: Object = net.host_tools
		var snap: Dictionary = tools.call("snapshot", g)
		# игра идёт сама (боты, таймеры)
		for i: int in 240:
			net._process(0.25)
		tools.call("restore", snap)
		check(_state(g) == before, game + ": восстановление снимка даёт прежнее состояние")
		# отмена через Net: снимок «до действия» + рассылка
		tools.before_action("test")
		var mid := _state(g)
		net._push_state()
		check(tools.can_undo(), game + ": после действия можно отменить")
		for i: int in 40:
			net._process(0.25)
		var after := _state(g)
		check(tools.undo(), game + ": отмена сработала")
		check(_state(g) == mid, game + ": отмена вернула состояние")
		check(tools.can_redo(), game + ": можно повторить")
		check(tools.redo(), game + ": повтор сработал")
		check(_state(g) == after, game + ": повтор вернул состояние после действия")
		var info: Dictionary = tools.info()
		check((info.players as Array).size() >= 2, game + ": панель видит игроков")
		tools.set_timer(false, 45)
		check(int(net.settings.get("tr_timer" if game == "things_in_rings" else "turn_time")) == 0, game + ": таймер выключен")
		tools.set_timer(true, 45)
		check(int(net.settings.get("tr_timer" if game == "things_in_rings" else "turn_time")) == 45, game + ": таймер 45 с")
		net.leave()
	print("HostTools: проверок %d, провалов %d" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
