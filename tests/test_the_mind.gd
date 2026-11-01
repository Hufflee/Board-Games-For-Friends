extends SceneTree
## Тесты правил и фазз The Mind: --headless --audio-driver Dummy --script res://tests/test_the_mind.gd.

const Rules := preload("res://games/the_mind/logic/tm_rules.gd")
var checks := 0
var failed := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed += 1
		push_error(message)

func game(n: int = 2, seed_value: int = 11) -> RefCounted:
	var r := Rules.new()
	var players: Array = []
	for i in n:
		players.append({"name": "Игрок %d" % i, "bot": false})
	check(r.new_game(players, seed_value).is_empty(), "Создание партии")
	return r

func act(r: RefCounted, seat: int, kind: String, data: Dictionary = {}) -> bool:
	data["revision"] = r.revision
	return r.action(seat, kind, data)

func focus(r: RefCounted) -> void:
	for i in r.players.size():
		check(act(r, i, "ready"), "Готовность места %d" % i)

func _init() -> void:
	var bad := Rules.new()
	check(not bad.new_game([]).is_empty(), "Пустая команда запрещена")
	var too_many: Array = []
	for i in 9:
		too_many.append({"name": "Игрок %d" % i})
	check(not bad.new_game(too_many).is_empty(), "Девять игроков запрещены")
	for n in range(2, 9):
		var r := game(n)
		check(r.lives == mini(n, 5) and r.panic == 1, "Начальные ресурсы")
		check(r.target == {2: 12, 3: 10, 4: 8, 5: 8, 6: 6, 7: 6, 8: 6}[n], "Число уровней")
		check(not act(r, -1, "ready"), "Зритель не действует")
		check(not act(r, n, "ready"), "Несуществующее место")
		check(not r.action(0, "ready", {"revision": -1}), "Устаревшее действие")
		check(not r.action(0, "ready", {"revision": "0"}), "Неверный тип ревизии")
		check(not r.action(0, "ready", []), "Неверный тип аргумента")
		check(not act(r, 0, "play", {"card": r.hands[0][0]}), "До готовности играть нельзя")
		var first_view: Dictionary = r.get_view(0)
		check(first_view.hand == r.hands[0], "Владелец получает свою руку")
		check(not first_view.has("hands"), "Нет всех рук в состоянии")
		check(r.get_view(-1).hand.is_empty(), "Зритель без руки")
		first_view.hand.clear()
		check(not r.hands[0].is_empty(), "Состояние не меняет правила")
		focus(r)
		check(r.phase == "play", "Все готовы — игра")
		check(act(r, 0, "refocus") and r.phase == "focus", "Свободная синхронизация")
		focus(r)
		check(act(r, 0, "panic"), "Паника для всей команды")
		for voter in range(1, n - 1):
			check(act(r, voter, "yes"), "Голос дополнительного участника")
		check(r.phase == "vote" and r.panic == 1, "Ждём согласия последнего участника")
		check(act(r, n - 1, "yes"), "Последний участник согласился")
		check(r.phase == "level_done" and r.panic == 0, "Паника сбросила минимум у всех участников")
	var r := game(3)
	r.hands = [[10, 20], [15, 30], [25, 40]]
	focus(r)
	check(not act(r, 0, "play", {"card": 20}), "Нельзя сыграть не минимум")
	check(not act(r, 1, "play", {"card": 10}), "Чужая карта запрещена")
	check(act(r, 2, "play", {"card": 25}), "Ошибочный глобальный порядок разрешает потерю жизни")
	check(r.lives == 3 and r.hands == [[10, 20], [15, 30], [40]], "До СТОП нет штрафа и сброса")
	check(not act(r, 2, "stop"), "Владелец большей карты не может нажать СТОП")
	check(not act(r, 1, "play", {"card": 15}), "До СТОП следующие карты блокируются")
	check(not act(r, 0, "panic"), "Ошибка не обходится Паникой")
	check(r.get_view(0).can_stop and not r.get_view(-1).can_stop, "Право СТОП только у владельца меньшей карты")
	check(act(r, 0, "stop"), "Владелец меньшей карты нажал СТОП")
	check(r.lives == 2 and r.phase == "focus", "Несколько пропущенных карт — одна жизнь")
	check(r.hands == [[], [30], [40]], "Сброшены все меньшие карты")
	check(r.discarded == [10, 20, 15], "Публичный сброс")
	check(r.get_view(-1).discard_info[0].seat == 0 and r.get_view(-1).discard_info[2].seat == 1, "Сброс содержит владельцев")
	check(r.get_view(-1).last_play.seat == 2, "Последний сыгравший виден всем")
	check(not act(r, 1, "stop"), "Повторный СТОП не отнимает ещё жизнь")
	focus(r)
	check(act(r, 1, "panic"), "Предложение Паники")
	check(r.panic == 1 and r.hands[1] == [30], "Нет списания до единогласия")
	check(act(r, 0, "yes") and act(r, 2, "no"), "Пустая рука голосует, отказ отменяет")
	check(r.phase == "play" and r.panic == 1, "Отказ сохраняет ресурс")
	check(act(r, 1, "panic"), "Новое голосование")
	check(act(r, 0, "yes") and act(r, 2, "yes"), "Единогласие")
	check(r.panic == 0 and r.phase == "level_done", "Паника очищает уровень")
	check(r.discarded == [10, 20, 15, 30, 40], "Паника открывает минимумы")
	check(not act(r, 2, "yes"), "Повторное согласие не расходует ресурс")
	r = game()
	r.hands = [[1], [10]]
	r.lives = 1
	focus(r)
	act(r, 1, "play", {"card": 10})
	check(r.lives == 1 and r.phase == "play", "Последняя жизнь ждёт СТОП")
	act(r, 0, "stop")
	check(r.phase == "game_over" and not r.won, "Последняя жизнь важнее пустых рук")
	check(not act(r, 0, "blind"), "После поражения вслепую нельзя")
	for current_level in range(1, 13):
		r = game()
		r.level = current_level
		r.lives = 2
		r.panic = 1
		r.hands = [[], []]
		r._check_level()
		check(r.lives == (3 if current_level in [3, 6, 9] else 2), "Жизнь только на уровнях наград")
		check(r.panic == (2 if current_level in [2, 5, 8] else 1), "Паника только на уровнях наград")
	r = game()
	r.hands = [[1], [2]]
	focus(r)
	r.panic = 0
	check(not act(r, 0, "panic"), "Нельзя предложить Панику без ресурса")
	var revision_before: int = r.revision
	check(act(r, 0, "play", {"card": 1}), "Разрешённая личная карта")
	check(not r.action(1, "play", {"revision": revision_before, "card": 2}), "Повтор старой ревизии отклонён")
	check(not r.can_spectate(), "Место нельзя отдать боту")
	r = game()
	r.blind = true
	r.lives = 4
	r.hands = [[50, 60], [10, 20]]
	focus(r)
	act(r, 0, "play", {"card": 50})
	act(r, 1, "play", {"card": 10})
	act(r, 0, "play", {"card": 60})
	act(r, 1, "play", {"card": 20})
	check(r.lives == 2 and r.get_view(0).pile == [50, 10, 60, 20], "Две ошибки вслепую и открытый итог")
	for n in range(2, 9):
		for seed_value in range(12):
			r = game(n, seed_value)
			var steps := 0
			while r.phase != "game_over" and steps < 1500:
				steps += 1
				if r.phase == "focus":
					focus(r)
				elif r.phase == "level_done":
					var old_level: int = r.level
					check(act(r, 0, "next"), "Следующий уровень")
					check(r.level == old_level + 1, "Уровень увеличен один раз")
					var dealt: Array = []
					for hand: Array in r.hands:
						check(hand.size() == r.level, "Размер руки по уровню")
						for value: int in hand:
							check(value >= 1 and value <= 100 and not dealt.has(value), "Уникальные числа 1–100")
							dealt.append(value)
					check(r.get_view(-1).hand.is_empty(), "Приватность зрителя после раздачи")
				elif r.phase == "play":
					var best := 101
					var seat := -1
					for i in n:
						if not r.hands[i].is_empty() and int(r.hands[i][0]) < best:
							best = r.hands[i][0]
							seat = i
					check(act(r, seat, "play", {"card": best}), "Розыгрыш возрастающей последовательности")
				check(r.lives >= 0 and r.lives <= 5 and r.panic >= 0 and r.panic <= 3, "Лимиты ресурсов")
			check(r.won and steps < 1500, "Партия до победы")
			var resources: Array = [r.lives, r.panic]
			check(act(r, 0, "blind"), "Продолжение вслепую")
			check(r.blind and r.level == 1 and r.lives == resources[0] and r.panic == resources[1], "Ресурсы после победы сохранены")
			r.hands = [[50], [10]]
			for extra in range(2, n):
				r.hands.append([])
			focus(r)
			act(r, 0, "play", {"card": 50})
			check(r.get_view(-1).pile.is_empty(), "Слепая стопка не раскрывается")
			check(r.get_view(-1).last_play.card == 0 and r.get_view(-1).events.back().card == 0, "Слепая анимация не раскрывает число")
			check(not str(r.log.back()).contains("50"), "Число не попало в журнал")
			act(r, 1, "play", {"card": 10})
			check(r.lives == resources[0] - 1 and r.phase == "level_done", "Проверка ошибки после вскрытия")
	r = game()
	r.blind = true
	var blind_steps := 0
	while r.phase != "game_over" and blind_steps < 1000:
		blind_steps += 1
		if r.phase == "focus":
			focus(r)
		elif r.phase == "level_done":
			act(r, 0, "next")
		else:
			var first := 101
			var who := -1
			for i in r.hands.size():
				if not r.hands[i].is_empty() and int(r.hands[i][0]) < first:
					first = r.hands[i][0]
					who = i
			check(act(r, who, "play", {"card": first}), "Полный слепой цикл")
			if r.phase == "play":
				check(r.get_view(-1).pile.is_empty(), "Стопка скрыта на каждом ходе")
	check(r.won and r.level == 12, "Победа после всех слепых уровней")
	check(not act(r, 0, "blind"), "Повторное продолжение слепой победы не создаёт цикл")
	print("The Mind: %d проверок, ошибок %d" % [checks, failed])
	quit(1 if failed else 0)
