extends SceneTree
## Полная локальная кооперативная партия через Net до проигрыша, без семантического бота.
var checks := 0
var errors := 0
var net: Node

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func act(seat: int, kind: String, payload: Dictionary = {}) -> void:
	net.send_action("view_seat", {"seat": seat})
	payload.revision = net.view.revision
	var before: int = net.view.revision
	net.send_action(kind, payload)
	check(net.view.revision == before + 1, "Локальное действие принято: " + kind)

func _run() -> void:
	net = root.get_node("Net")
	net.host_offline("things_in_rings")
	net.set_bots(1)
	net.set_setting("tr_rings", ["Word"])
	net.set_setting("tr_knower", 0)
	check(net.start_game() == "", "Два человека за одним компьютером")
	act(0, "choose_rule", {"category":"Word", "card":net.view.rule_choices.Word[0]})
	act(0, "begin_clues")
	for i: int in 2:
		act(0, "clue", {"card":net.view.hand[0], "mask":0})
	for round_number: int in 9:
		net.send_action("view_seat", {"seat":1})
		check(net.view.hand.size() == 5 and net.view.secret_rules.is_empty(), "У искателя своя рука и нет правил")
		act(1, "place", {"card":net.view.hand[0], "mask":0})
		act(0, "judge", {"mask":1})
		if round_number < 8:
			check(net.view.phase == "knower_clue", "После ошибки нужна новая подсказка")
			act(0, "clue", {"card":net.view.hand[0], "mask":round_number % 2})
	check(net.view.phase == "game_over" and net.view.reason == "no_clue" and net.view.winners.is_empty(), "Весь запас подсказок исчерпан — проигрыш без победителей")
	var result: Dictionary = load("res://hub/victory_result.gd").resolve("things_in_rings", net.view)
	check(result.finished and result.winners.is_empty() and result.team, "Общий экран понимает кооперативный проигрыш")
	check(net.view.board.size() == 19, "Все2+8подсказок и9попыток остаются в архиве")
	net.leave()
	await process_frame
	print("TIR LOCAL COOP: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
