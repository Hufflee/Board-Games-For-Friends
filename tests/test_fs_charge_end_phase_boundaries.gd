## Конец хода: перезарядка до сброса, ответы, однократное продолжение и личность источника.
## Подготовленные состояния seed26; --headless --audio-driver Dummy --script res://tests/test_fs_charge_end_phase_boundaries.gd.
extends "res://tests/test_fs_charge_lifecycle_next.gd"

func three_players() -> FSRules:
	var g := FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}, {"name": "В"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.current = 0
	g.chars = [839, 839, 839]
	g.items = [[], [], []]
	g.hands = [[], [], []]
	g.hp = [20, 20, 20]
	g.max_hp = [20, 20, 20]
	g.monsters.clear()
	g.room = -1
	g.curses = [[], [], []]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g.phase = "turn"
	return g

func excess_hand(g: FSRules, count: int) -> void:
	g.hands[0].resize(count)
	g.hands[0].fill(475)

func discard_boundaries(id: int) -> void:
	var g := three_players()
	for owner: int in [0, 0, 2]:
		g._gain_item(owner, id)
		g.items[owner].back().tapped = true
	g._gain_item(0, 44)
	g.items[0][2].tapped = true
	g._gain_item(0, 56)
	var first: Dictionary = g.items[0][0]
	var second: Dictionary = g.items[0][1]
	var foreign: Dictionary = g.items[2][0]
	var counter: Dictionary = g.items[0][3]
	excess_hand(g, 12)
	check(g.action(0, "end"), "%d: настоящий конец хода" % id)
	check(g.phase == "priority" and first.tapped and second.tapped,
		"%d: зарядка ждёт разрешения в общем стеке, а не применяется при объявлении" % id)
	check(g.stack.filter(func(e: Dictionary) -> bool: return e.card == id).size() == 2,
		"%d: только две собственные копии создали обязательные эффекты" % id)
	check(not g.action(1, "end"), "%d: чужой end не закрывает очередь" % id)
	check(g.action(0, "end"), "%d: повторный end только разрешает уже созданную очередь" % id)
	g._finish_responses()
	check(g.phase == "discard" and g.current == 0, "%d: обязательный сброс ожидается до смены хода" % id)
	check(not first.tapped and not second.tapped and foreign.tapped and g.items[0][2].tapped,
		"%d: зарядились обе собственные копии, но не чужая и не44" % id)
	check(not g.get_view(0).players[0].items[0].tapped and not g.get_view(2).players[0].items[1].tapped,
		"%d: view отражает заряд до первого сброса" % id)
	check(counter.counters == 1, "%d: отдельный триггер конца56 применён один раз" % id)
	check(not g.action(0, "end"), "%d: повторный end во время сброса отклонён" % id)
	g._continue_stack()
	g._continue_stack()
	check(g.phase == "discard" and counter.counters == 1 and g.stack.is_empty(),
		"%d: повторные resume не создают новые триггеры" % id)
	check(not g.action(1, "discard", {"card": 475}), "%d: чужой сброс отклонён" % id)
	check(g.action(0, "discard", {"card": 475}), "%d: первый сброс12→11" % id)
	g._continue_stack()
	check(g.phase == "discard" and g.hands[0].size() == 11 and counter.counters == 1,
		"%d: частичный сброс и resume не повторяют конец хода" % id)
	check(g.action(0, "discard", {"card": 475}), "%d: второй сброс11→10" % id)
	check(g.current == 1 and g.phase == "turn" and foreign.tapped and counter.counters == 1,
		"%d: ход передан ровно один раз, чужой источник2 ещё не начинал ход" % id)
	check(not g.action(0, "discard", {"card": 475}), "%d: повторный старый discard не меняет следующий ход" % id)
	check(g.action(1, "end"), "%d: заканчивается следующий чужой ход" % id)
	g._finish_responses()
	check(g.current == 2 and not foreign.tapped, "%d: обычный старт владельца2 заряжает его источник" % id)

func retap_after_recharge() -> void:
	var g := three_players()
	# Ещё один триггер ниже зарядки сохраняет настоящее окно ответов после неё.
	g._gain_item(0, 56)
	g._gain_item(0, 824)
	var heart: Dictionary = g.items[0][1]
	heart.tapped = true
	excess_hand(g, 11)
	check(g.action(0, "end"), "824: начало конца хода")
	g._resolve_top()
	check(not heart.tapped and g.phase == "priority", "824: зарядка разрешилась до оставшегося триггера56")
	check(g.action(0, "activate", {"item": 1}), "824: законная повторная активация в окне ответов")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "prevent_damage", "target": 0, "amount": 1}), "824: выполнено предотвращение урона")
	check(g.action(0, "effect_done"), "824: ручная способность завершена")
	g._finish_responses()
	check(g.phase == "discard" and heart.tapped and g.items[0][0].counters == 1,
		"824: использованный после зарядки источник не заряжается повторно перед сбросом")
	g._continue_stack()
	check(heart.tapped and not g.action(0, "end"), "824: resume/end не создают вторую зарядку")
	check(g.action(0, "discard", {"card": 475}), "824: обязательный сброс завершён")
	check(g.current == 1 and heart.tapped, "824: завершение сброса также не заряжает использованное сердце")

func transfer_and_remove() -> void:
	var g := three_players()
	g._gain_item(0, 84)
	g._gain_item(0, 13)
	var source: Dictionary = g.items[0][0]
	source.tapped = true
	check(g.action(0, "end"), "84: зарядка поставлена до передачи")
	check(g.action(0, "activate", {"item": 1}), "84: ответ отдельной картой")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "give_item", "target": 2, "item": 0}), "84: источник передан настоящим give_item")
	check(g.action(0, "effect_done"), "84: передавшая способность завершена")
	g._finish_responses()
	check(g.current == 1 and not source.tapped and is_same(source, g.items[2][0]),
		"84: созданная зарядка нашла тот же источник у нового владельца до его собственного старта")
	g = three_players()
	g._gain_item(0, 84)
	g._gain_item(0, 13)
	source = g.items[0][0]
	source.tapped = true
	check(g.action(0, "end"), "84: зарядка поставлена до уничтожения")
	check(g.action(0, "activate", {"item": 1}), "84: ответ уничтожением")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "84: исходный объект ушёл из игры")
	# Подготовлена новая копия с тем же ID; она не является адресатом старого триггера.
	g._gain_item(0, 84)
	var replacement: Dictionary = g.items[0][1]
	check(g.action(0, "effect_done"), "84: уничтожившая способность завершена")
	check(g.action(0, "activate", {"item": 1}), "84: новая копия использована до старого триггера")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "peek_hand", "target": 1}), "84: новая копия выполняет просмотр")
	check(g.action(0, "effect_done"), "84: новая способность завершена")
	g._finish_responses()
	check(source.tapped and replacement.tapped and g.current == 1,
		"84: старый триггер не изменяет ушедший объект и новую копию с тем же ID")
	check(not g._source_item_in_play(source) and g._source_item_in_play(replacement), "Идентичность источника проверяется отдельно от ID")
	for id: int in [822, 824]:
		g = three_players()
		g._gain_item(0, id)
		manual(g)
		check(not g.action(0, "effect", {"op": "give_item", "target": 2, "item": 0}), "%d: обычная передача вечного предмета не обходится" % id)
		check(not g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "%d: обычное уничтожение вечного предмета не обходится" % id)

func _initialize() -> void:
	for id: int in [84, 822, 824]:
		discard_boundaries(id)
	retap_after_recharge()
	transfer_and_remove()
	print("CHARGE END PHASE BOUNDARIES: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
