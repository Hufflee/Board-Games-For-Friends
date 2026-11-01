extends SceneTree
## Ветка cg в Net: местные люди, приватность, пауза, переключение, финал и очистка правил.

var net: Node
var count := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	count += 1
	if not ok:
		errors += 1
		push_error(text)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	net = root.get_node("Net")
	for example: String in ["card_race", "higher_lower", "dice_bid"]:
		net.host_offline("cg")
		net.set_bots(7)
		net.set_setting("cg_example", example)
		check(net.start_game().is_empty(), "Пример запускается через Net")
		check(net.cg != null and net.mind == null and net.rules == null, "Выбраны только правила cg")
		check(net.cg.players.size() == 8 and not net.cg.players.any(func(p: Dictionary): return p.bot), "Восемь людей без ботов")
		check(net.view.game == "cg" and net.view.hotseat and net.view.seat == 0, "Офлайн view выбранного места")
		check(net.view.has("cg_layout") and net.view.cg_meta.title.length() > 0, "Стол получил раскладку и название")
		net.send_action("view_seat", {"seat": 7})
		check(net.view.seat == 7, "Переключение на восьмого игрока")
		check(not net.view.has("state") and not net.view.has("definition"), "Сырое состояние в view не передаётся")
		var steps := 0
		while net.cg.phase != "game_over" and steps < 240:
			steps += 1
			var seat: int = net.cg.state.current
			net.send_action("view_seat", {"seat": seat})
			var actions: Array = net.view.legal
			check(not actions.is_empty(), "Net перечислил допустимый ход")
			if actions.is_empty():
				break
			var action: Dictionary = actions[steps % actions.size()].duplicate(true)
			action.revision = net.view.revision
			var before: int = net.view.revision
			net.set_paused(true)
			net.send_action(str(action.kind), action)
			check(net.cg.state.revision == before, "На паузе действие не выполняется")
			net.set_paused(false)
			net.send_action(str(action.kind), action)
			check(net.view.revision == before + 1, "Действие хоста обновило адресный view")
		check(net.cg.phase == "game_over", "JSON-игра доиграна через Net")
		var result: Dictionary = preload("res://hub/victory_result.gd").resolve("cg", net.view)
		check(result.finished and not result.winners.is_empty(), "Общий экран финала знает победителей cg")
		net.end_game()
		check(net.cg == null and not net.in_game, "Возврат в лобби очищает cg")
		net.leave()
	net.host_offline("the_mind")
	net.set_bots(1)
	check(net.start_game().is_empty() and net.cg == null and net.mind != null, "После cg запускается другая игра без старых правил")
	net.leave()
	print("CUSTOM_NET_LOCAL: %d проверок, ошибок %d" % [count, errors])
	quit(1 if errors else 0)
