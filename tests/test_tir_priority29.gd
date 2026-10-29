extends SceneTree
## Адресные проверки предложений, приватности, финальных переворотов и прав Net.
## Запуск: Godot --headless --audio-driver Dummy --path . --script res://tests/test_tir_priority29.gd

const Rules := preload("res://games/things_in_rings/logic/tr_rules.gd")
var checks := 0
var errors := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)


func game(ring_count: int = 3) -> Rules:
	var result := Rules.new()
	var categories: Array = ["Attribute", "Word", "Context"].slice(0, ring_count)
	check(result.new_game([{"name": "Хост"}, {"name": "Знающий"}, {"name": "Игрок"}], range(240),
		{"Attribute": [301, 302, 303], "Word": [201, 202, 203], "Context": [401, 402, 403]},
		{"rings": categories, "knower": 1}, 29) == "", "Партия создана")
	for category: String in categories:
		result.choose_rule(1, category, result.rule_choices[category][0])
	result.begin_clues(1)
	for _i: int in 3:
		result.clue(1, result.hands[1][0], 0)
	return result


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for count: int in [1, 2, 3]:
		for mask: int in (1 << count):
			var model := game(count)
			var card: int = model.hands[2][0]
			check(model.action(2, "place", {"revision": model.revision, "card": card, "mask": mask}), "Все области доступны")
			for seat: int in [-1, 0, 1, 2]:
				var view := model.get_view(seat)
				check(view.pending == {"card": card, "proposed": mask, "by": 2}, "Предложение видно всем до решения")
				check(view.secret_rules.size() == (count if seat == 1 else 0), "Предложение не раскрывает условия")
				check(view.hand == (model.hands[seat] if seat >= 0 else []), "Доставляется только своя рука")
			var detached := model.get_view(-1)
			detached.pending.clear()
			check(not model.pending.is_empty(), "Снимок не меняет модель")
			check(model.action(1, "judge", {"revision": model.revision, "mask": mask}), "Знающий подтверждает")
			check(model.get_view(-1).feedback.correct and model.get_view(-1).feedback.id == 1, "Успех получает публичный ID")
	var model := game()
	model.place(2, model.hands[2][0], 7)
	model.judge(1, 0)
	check(not model.get_view(-1).feedback.correct and model.feedback.id == 1, "Ошибка публикуется всем")
	model.place(0, model.hands[0][0], 1)
	model.judge(1, 1)
	check(model.feedback.id == 2 and model.feedback.correct, "ID увеличивается на каждое решение")
	var net: Node = load("res://tests/tir_priority_net_fixture.gd").new()
	root.add_child(net)
	net.set_process(false)
	net.mode = "enet"
	net.in_game = true
	net.paused = false
	net.party_game = "things_in_rings"
	net.seat_peers.assign([1, 2, 3])
	net.tir = model
	model._finish([0], "first_found")
	for seat: int in [-1, 0, 1, 2]:
		var view := model.get_view(seat)
		check(view.phase == "postgame" and view.winners.is_empty(), "Победители скрыты до команды хоста")
		check(view.condition_faces == [-1, -1, -1], "Финал начинается тремя рубашками у всех")
	check(not model.reveal_rules(1), "Старое массовое раскрытие закрыто")
	net._handle_action(1, "flip_condition", {"revision": model.revision, "ring": 0})
	check(model.revision == 0, "Хост без роли знающего не переворачивает")
	net._handle_action(2, "show_victory", {"revision": model.revision, "host_authorized": true})
	check(model.phase == "postgame" and model.revision == 0, "Знающий не подделывает право хоста")
	net._handle_action(2, "flip_condition", {"revision": model.revision, "ring": 1})
	check(model.revision == 1 and model.revealed_conditions == [false, true, false], "Знающий открывает одну выбранную карту")
	for view: Dictionary in net.delivered:
		check(view.condition_faces == [-1, model.secret_rules.Word, -1], "Открытая карта одинакова во всех снимках")
		check(view.secret_rules.size() == (3 if view.you == 1 else 1), "Неоткрытые карты остаются секретными")
	var late: Dictionary = net._seat_view(-1, [], 0.0, false)
	check(late.condition_faces == net.delivered.back().condition_faces, "Поздний зритель получает сохранённые перевороты")
	net._handle_action(2, "flip_condition", {"revision": 0, "ring": 0})
	net._handle_action(2, "flip_condition", {"revision": 1, "ring": 1})
	net._handle_action(2, "flip_condition", {"revision": 1, "ring": "0"})
	check(model.revision == 1, "Устаревший, повторный и нетипизированный перевороты отклонены")
	for index: int in [0, 2]:
		net._handle_action(2, "flip_condition", {"revision": model.revision, "ring": index})
	check(model.revealed and model.phase == "postgame", "Все перевороты сами не включают победу")
	net._handle_action(3, "show_victory", {"revision": model.revision})
	check(model.phase == "postgame", "Искатель также не включает победу")
	net._handle_action(1, "show_victory", {"revision": model.revision})
	check(model.phase == "game_over" and model.get_view(-1).winners == [0], "Хост включает объявление победителей")
	check(not model.action(1, "flip_condition", {"revision": model.revision, "ring": 0}), "Победный экран не принимает перевороты")
	var early := game(1)
	check(not early.action(1, "show_victory", {"revision": 0}, true), "Хост не завершает незавершённую партию")
	early._finish([], "deck_empty")
	check(early.action(0, "show_victory", {"revision": 0}, true), "Хост может закончить финал до раскрытия")
	check(early.get_view(-1).secret_rules.is_empty(), "Такой финал не раскрывает рубашки")
	net.tir = null
	net.queue_free()
	await process_frame
	print("TIR PRIORITY29: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
