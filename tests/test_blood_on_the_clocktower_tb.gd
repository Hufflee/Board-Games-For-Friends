extends SceneTree
## Проверки 22 способностей «Назревает беда», ночного порядка и утечек.
## --headless --audio-driver Dummy --path . --script res://tests/test_blood_on_the_clocktower_tb.gd.

const Rules := preload("res://games/blood_on_the_clocktower/logic/bc_rules.gd")
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ОШИБКА: " + message)

func fixture(ids: Array = []) -> Rules:
	var game := Rules.new()
	var people: Array = []
	for i in 9:
		people.append({"name": "Место %d" % i, "color": i})
	var selected := ["washerwoman", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"]
	check(game.new_game(people, {"bc_roles": selected, "bc_bluffs": ["chef", "mayor", "librarian"]}, 21).is_empty(), "Подготовка фикстуры")
	if ids.is_empty():
		ids = selected
	# Управляемое положение после возможных смен ролей: популяция отдельно проверена тестом подготовки.
	for i in ids.size():
		game.roles[i + 1] = ids[i]
		game.shown_roles[i + 1] = ids[i]
		game.sides[i + 1] = game.catalog[ids[i]].side
	return game

func action(game: Rules, seat: int, kind: String, fields: Dictionary = {}) -> bool:
	var argument := fields.duplicate(true)
	argument["revision"] = game.public_revision
	return game.action(seat, kind, argument)

func respond(game: Rules, seat: int, index: int = 0) -> bool:
	if not game.requests.has(seat):
		return false
	return game.action(seat, "private_reply", {"token": game.requests[seat].token, "index": index})

func target_response(game: Rules, target: int) -> bool:
	var recipient := int(game.abilities.pending.get("recipient", -1))
	if not game.requests.has(recipient):
		return false
	var options: Array = game.requests[recipient].options
	for i in options.size():
		if int(options[i].get("target", -1)) == target:
			return respond(game, recipient, i)
	return false

func finish_night(game: Rules, poison_target: int = 6, demon_target: int = 6) -> void:
	for step in 80:
		if game.phase != "night":
			return
		var recipient := int(game.abilities.pending.get("recipient", -1))
		if recipient < 0:
			check(false, "Ночь не должна зависать без запроса")
			return
		var role := str(game.abilities.pending.get("role", ""))
		if role == "poisoner":
			check(target_response(game, poison_target), "Выбор Отравителя")
		elif role == "imp":
			check(target_response(game, demon_target), "Выбор Беса")
		else:
			check(respond(game, recipient), "Ответ на ночной запрос")
	check(false, "Ночная очередь должна завершаться")

func _run() -> void:
	_night()
	_health_and_protection()
	_information()
	_succession()
	_day_abilities()
	_full_games()
	print("Clocktower TB: %d проверок, %d ошибок." % [checks, failures])
	quit(1 if failures > 0 else 0)

func _night() -> void:
	var game := fixture()
	check(not action(game, 1, "begin_night", {"host": true}), "Только рассказчик начинает ночь")
	check(action(game, 0, "begin_night"), "Первая ночь запущена")
	check(game.requests.has(7), "Отравитель действует до информационных ролей")
	var public_before := game.get_view(-1)
	check(not game.get_view(2).has("request"), "Чужое пробуждение скрыто")
	var token := str(game.requests[7].token)
	check(not game.action(1, "private_reply", {"token": token, "index": 0}), "Нельзя выбрать яд за Отравителя")
	check(target_response(game, 2), "Отравлен Эмпат")
	check(game.get_view(-1) == public_before, "Переход ночного действующего не меняет публичный снимок")
	check(not game.action(7, "private_reply", {"token": token, "index": 0}), "Повторный ночной выбор отклонён")
	finish_night(game)
	check(game.phase == "discussion" and game.day == 1, "Первая ночь закончилась рассветом")
	check(game.private_log[8].size() == 1, "Бес получил имена приспешников и блефы при восьми игроках")
	check(game.private_log[7].size() == 1, "Приспешник получил команду")
	check(game.abilities.healthy(2) == false, "Яд сохранился на день")
	check(not JSON.stringify(game.get_view(3)).contains("Роли для блефа"), "Блефы не утекли доброму")
	game.phase = "dusk"
	check(action(game, 0, "begin_night"), "Следующая ночь запущена")
	finish_night(game, 6, 4)
	check(game.alive[4], "Солдат не погиб от Беса")
	check(game.status[2].get("poison_source", -1) == -1, "Прежний яд снят в сумерки")
	check(game.phase == "discussion" and game.day == 2, "Вторая ночь завершилась")
	var small := Rules.new()
	var people: Array = []
	for i in 6:
		people.append({"name": "Игрок %d" % i})
	check(small.new_game(people, {"bc_roles": ["chef", "empath", "soldier", "poisoner", "imp"], "bc_bluffs": ["monk", "mayor", "slayer"]}, 1).is_empty(), "Малый состав")
	action(small, 0, "begin_night")
	for s: int in small.seats_in_circle():
		if small.catalog[small.roles[s]].side == "evil":
			check(small.private_log[s].is_empty(), "При пяти игроках зло не получает командную информацию")

func _health_and_protection() -> void:
	var game := fixture()
	game.status[2]["poison_source"] = 7
	check(not game.abilities.healthy(2), "Здоровый Отравитель подавляет способность")
	game.status[7]["poison_source"] = 7
	check(not game.abilities.healthy(7), "Самоотравление сохраняется")
	check(game.abilities.healthy(2), "Отравленный Отравитель не поддерживает чужой яд")
	game.status[7].clear()
	game.alive[7] = false
	check(game.abilities.healthy(2), "Смерть Отравителя прекращает эффект")
	game.alive[7] = true
	game.roles[7] = "imp"
	check(game.abilities.healthy(2), "Смена роли Отравителя прекращает старый эффект")
	game = fixture()
	game.abilities.started = true
	game.phase = "night"
	game.status[1]["monk_source"] = 3
	game.abilities._kill(1, 8, "demon")
	check(game.alive[1], "Монах защищает от демона")
	game.status[3]["poison_source"] = 7
	game.abilities._kill(1, 8, "demon")
	check(not game.alive[1], "Отравленный Монах не защищает")
	game.abilities._kill(4, 8, "demon")
	check(game.alive[4], "Солдат защищён от демона")
	game.status[4]["poison_source"] = 7
	game.abilities._kill(4, 8, "demon")
	check(not game.alive[4], "Отравленный Солдат умирает")
	game = fixture(["mayor", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	game.phase = "night"
	game.abilities._kill(1, 8, "demon")
	check(game.requests.has(0) and game.alive[1], "Мэр ждёт решения рассказчика")
	check(target_response(game, 4), "Перенаправление на Солдата")
	check(game.alive[1] and game.alive[4], "При перенаправлении защита Солдата сохраняется")
	game.abilities._kill(1, 8, "demon")
	check(target_response(game, 2), "Перенаправление на обычного игрока")
	check(game.alive[1] and not game.alive[2], "Перенаправленная смерть применена системой")
	check(game.get_view(-1).players[2].alive, "Ночная смерть пока не объявлена")
	game.abilities._kill(1, 8, "demon")
	var dead_target_offered := false
	for option: Dictionary in game.requests[0].options:
		dead_target_offered = dead_target_offered or int(option.target) == 2
	check(not dead_target_offered, "Мэр по переданному альманаху перенаправляет только на живого игрока")

func _information() -> void:
	var game := fixture(["washerwoman", "librarian", "investigator", "chef", "empath", "recluse", "spy", "imp"])
	game.abilities._first_information(1, "washerwoman")
	for option: Dictionary in game.requests[0].options:
		check(not str(option.text).contains(" — Бес."), "Прачка не получает злую роль в здоровом состоянии")
	respond(game, 0)
	check(game.private_log[1].size() == 1 and game.private_log[2].is_empty(), "Информация Прачки адресная")
	game.abilities._first_information(2, "librarian")
	var zero := false
	for option: Dictionary in game.requests[0].options:
		zero = zero or option.text == "Изгоев в партии нет."
	check(zero, "Отшельник может зарегистрироваться злым: Библиотекарь может узнать ноль")
	respond(game, 0)
	game.abilities._first_information(3, "investigator")
	check(game.requests.has(0), "Рассказчик выбирает допустимое сообщение Следователю")
	respond(game, 0)
	check(game.abilities._side_options(7) == [true, false], "Шпион может определяться добрым")
	check(game.abilities._side_options(6) == [false, true], "Отшельник может определяться злым")
	check(game.abilities._demon_options(6).has(true), "Отшельник может определяться демоном")
	check(not game.abilities._demon_options(7).has(true), "Шпион не может определяться демоном")
	game.alive[6] = false
	check(game.abilities._demon_options(6).has(true), "Отшельник сохраняет регистрацию после смерти")
	game.abilities._spy(7)
	check(game.get_view(7).knowledge.grimoire.size() == 8, "Шпиону выдан приватный снимок гримуара")
	check(not game.get_view(6).has("knowledge") and not game.get_view(-1).has("knowledge"), "Снимок Шпиона не выдан другим")
	var spy_snapshot: Dictionary = game.get_view(7).knowledge
	spy_snapshot.grimoire[0].role = "подмена"
	check(game.get_view(7).knowledge.grimoire[0].role != "подмена", "Снимок Шпиона изолирован от клиента")
	game = fixture(["fortune_teller", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	game.abilities.red_herring = 4
	game.abilities._pair_selected(1, "fortune_teller", {"targets": [3, 4]})
	check(str(game.private_log[1].back()).ends_with("да."), "Ложный след Гадалки даёт да")
	game.abilities._pair_selected(1, "fortune_teller", {"targets": [2, 3]})
	check(str(game.private_log[1].back()).ends_with("нет."), "Обычные добрые цели Гадалки дают нет")
	game.abilities._pair_selected(1, "fortune_teller", {"targets": [8, 3]})
	check(str(game.private_log[1].back()).ends_with("да."), "Демон определяется Гадалкой")
	game = fixture(["ravenkeeper", "undertaker", "empath", "butler", "slayer", "saint", "poisoner", "imp"])
	game.phase = "night"
	game.abilities._kill(1, 8, "demon")
	game.abilities._wake(1, "ravenkeeper")
	check(game.requests.has(1), "Погибший ночью Хранитель просыпается")
	check(target_response(game, 8), "Хранитель выбрал демона")
	check(str(game.private_log[1].back()).contains("Бес"), "Хранитель узнал роль после смерти")
	game.execution_death = 6
	game.abilities._wake(2, "undertaker")
	check(str(game.private_log[2].back()).contains("Святой"), "Гробовщик узнаёт настоящую роль казнённого")
	game.abilities._wake(4, "butler")
	check(target_response(game, 2) and game.status[4].master == 2, "Дворецкий выбирает хозяина")
	game = fixture(["chef", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	check(game.abilities._chef_values() == [1], "Повар считает соседствующую пару злодеев")
	check(game.abilities._empath_values(1) == [1], "Эмпат учитывает соседей через край круга")
	game.alive[8] = false
	check(game.abilities._empath_values(1) == [1], "Эмпат пропускает мёртвого соседа")
	_information_hints()

## Ревью 05.11: рассказчик видит, почему у информации несколько вариантов; игроку пояснение не уходит.
func _information_hints() -> void:
	# Шпион (7) рядом с Бесом (8): здоровому Повару честны и 0, и 1.
	var game := fixture(["chef", "empath", "monk", "soldier", "slayer", "saint", "spy", "imp"])
	game.abilities._wake(1, "chef")
	check(game.requests.has(0) and game.requests[0].options.size() == 2, "Шпион рядом с Бесом даёт Повару два честных числа")
	var hint := str(game.requests[0].get("hint", ""))
	check(hint.contains("все варианты верны") and hint.contains("Шпион (Место 7) может определиться добрым"), "Подсказка называет Шпиона: " + hint)
	check(not JSON.stringify(game.get_view(1)).contains("Шпион (Место 7)"), "Подсказка не уходит Повару")
	check(not JSON.stringify(game.get_view(-1)).contains("может определиться"), "Подсказка не попадает в публичный снимок")
	respond(game, 0)
	# Отравленный Повар: любые числа и причина.
	game = fixture(["chef", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	game.status[1]["poison_source"] = 7
	game.abilities._wake(1, "chef")
	hint = str(game.requests[0].get("hint", ""))
	check(game.requests[0].options.size() == 9, "Отравленному Повару доступны все числа 0–8")
	check(hint.contains("Место 1 отравлен (Отравитель — Место 7)") and hint.contains("способность не работает"), "Подсказка называет яд: " + hint)
	respond(game, 0)
	# Пьяница, думающий что он Повар.
	game = fixture(["drunk", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	game.shown_roles[1] = "chef"
	game.abilities._wake(1, "chef")
	check(str(game.requests[0].get("hint", "")).contains("Место 1 на самом деле Пьяница"), "Подсказка называет Пьяницу")
	respond(game, 0)
	# Без регистраций и нарушений у Прачки много честных пар — подсказка без лишних ролей.
	game = fixture(["washerwoman", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	game.abilities._first_information(1, "washerwoman")
	hint = str(game.requests[0].get("hint", ""))
	check(hint == "Способность работает, все варианты верны — выберите любой.", "Подсказка без регистраций: " + hint)
	respond(game, 0)
	# Отравленный Шпион не может зарегистрироваться иначе — в подсказке его нет.
	game = fixture(["washerwoman", "empath", "monk", "soldier", "slayer", "saint", "spy", "imp"])
	game.roles[3] = "poisoner"
	game.status[7]["poison_source"] = 3
	game.abilities._first_information(1, "washerwoman")
	check(not str(game.requests[0].get("hint", "")).contains("Шпион"), "Отравленный Шпион не упоминается")

func _succession() -> void:
	var game := fixture(["washerwoman", "empath", "monk", "soldier", "slayer", "saint", "scarlet_woman", "imp"])
	game.abilities.started = true
	game.phase = "discussion"
	game.abilities.execute(8)
	check(game.roles[7] == "imp" and game.winner.is_empty(), "Алая женщина наследует демона при пяти или более живых")
	check(str(game.private_log[7].back()).contains("Бес"), "Новая роль сообщена только наследнице")
	check(not JSON.stringify(game.get_view(1)).contains("Теперь ваша роль"), "Наследование не раскрывается городу")
	game = fixture(["washerwoman", "empath", "monk", "soldier", "slayer", "saint", "scarlet_woman", "imp"])
	for s: int in [1, 2, 3, 4]:
		game.alive[s] = false
	game.abilities.execute(8)
	check(game.winner == "good" and game.roles[7] == "scarlet_woman", "При четырёх живых Алая женщина не наследует")
	game = fixture()
	game.phase = "night"
	game.abilities._kill(8, 8, "demon")
	check(game.requests.has(0) and game.winner.is_empty(), "Самоубийство Беса ждёт передачи до проверки победы")
	check(target_response(game, 7), "Передача Отравителю")
	check(game.roles[7] == "imp" and game.winner.is_empty(), "Приспешник стал Бесом без немедленной победы добра")
	check(game.alive[7] and not game.alive[8], "Старый Бес мёртв, новый жив")
	game = fixture()
	game.status[6]["poison_source"] = 7
	game.abilities._become_imp(7)
	check(game.abilities.healthy(6), "Передача роли Отравителю снимает его старый яд")

func _day_abilities() -> void:
	var game := fixture()
	game.abilities.started = true
	game.phase = "discussion"
	check(action(game, 5, "slay", {"target": 8}), "Истребитель объявляет выстрел")
	check(game.alive[8], "Демон жив до завершения показа выстрела")
	check(game.tick(1.0) and not game.alive[8] and game.winner == "good", "Выстрел автоматически убил демона после показа")
	check(game.public_log.count("Победа добра.") == 1, "Победа объявляется ровно один раз")
	check(not action(game, 5, "slay", {"target": 7}), "Повторное использование запрещено")
	game = fixture()
	game.abilities.started = true
	game.phase = "discussion"
	check(action(game, 2, "slay", {"target": 8}), "Любой живой может блефовать Истребителем")
	game.tick(1.0)
	check(game.alive[8], "Блеф не создаёт способность")
	check(game.public_log.has("Выстрел в Место 8: ничего не произошло."), "Неуспешный выстрел даёт одинаковую публичную обратную связь")
	check(game.get_view(3).players[2].slayer_shot, "Заявленный выстрел виден всем — повторно кнопку не показывать")
	check(not action(game, 2, "slay", {"target": 7}), "Блефующий тоже заявляет выстрел один раз")
	game = fixture()
	game.abilities.started = true
	game.phase = "discussion"
	game.status[5]["poison_source"] = 7
	check(action(game, 5, "slay", {"target": 8}), "Отравленный Истребитель может попытаться")
	game.tick(1.0)
	check(game.alive[8] and game.status[5].slayer_claimed, "Отравление не даёт убийства, но тратит одноразовую способность")
	check(game.public_log.back() == "Выстрел в Место 8: ничего не произошло.", "Отравленный Истребитель неотличим от блефа")
	game = fixture(["virgin", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	game.abilities.started = true
	game.phase = "nominations"
	check(action(game, 2, "nominate", {"target": 1}), "Горожанин номинирует Деву")
	check(not game.event.is_empty() and game.alive[2], "Способность Девы поставила казнь в очередь")
	game.tick(1.0)
	check(not game.alive[2] and game.executed == 2 and game.phase == "dusk", "Дева автоматически казнила номинирующего и закрыла день")
	game = fixture(["virgin", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	game.abilities.started = true
	game.phase = "nominations"
	check(action(game, 6, "nominate", {"target": 1}), "Изгой номинирует Деву")
	check(game.phase == "defense" and game.event.is_empty() and game.status[1].virgin_used, "Изгой не казнён, но способность Девы потрачена")
	game = fixture()
	game.abilities.execute(6)
	check(game.winner == "evil", "Казнь здорового Святого завершает игру поражением добра")
	game = fixture()
	game.status[6]["poison_source"] = 7
	game.abilities.execute(6)
	check(game.winner.is_empty(), "Казнь отравленного Святого не завершает игру")
	game = fixture()
	game.alive[6] = false
	game.abilities.execute(6)
	check(game.winner.is_empty() and game.execution_death == -1, "Казнь уже мёртвого Святого не вызывает повторной смерти")
	game = fixture(["mayor", "empath", "monk", "soldier", "slayer", "saint", "poisoner", "imp"])
	game.abilities.started = true
	game.phase = "dusk"
	for s: int in [2, 3, 4, 5, 6]:
		game.alive[s] = false
	game.abilities.dusk()
	check(game.winner == "good", "Мэр побеждает при трёх живых и отсутствии казни")

func _full_games() -> void:
	var covered: Dictionary = {}
	for seed_value in 88:
		var count := 5 + seed_value % 11
		var seed_rng := RandomNumberGenerator.new()
		seed_rng.seed = 71000 + seed_value
		var selected: Array = []
		var minions: Array = Data.roles("tb", "minion")
		_shuffle(minions, seed_rng)
		selected.append_array(minions.slice(0, int(Data.COUNTS[count][2])))
		selected.append("imp")
		var population: Array = Data.population(count, selected)
		var townsfolk: Array = Data.roles("tb", "townsfolk")
		var outsiders: Array = Data.roles("tb", "outsider")
		_shuffle(townsfolk, seed_rng)
		_shuffle(outsiders, seed_rng)
		selected.append_array(townsfolk.slice(0, int(population[0])))
		selected.append_array(outsiders.slice(0, int(population[1])))
		var fake := str(townsfolk[int(population[0])]) if selected.has("drunk") else ""
		var bluffs: Array = []
		for id: String in Data.roles("tb"):
			if Data.catalog()[id].side == "good" and not selected.has(id) and id != fake and bluffs.size() < 3:
				bluffs.append(id)
		var people: Array = []
		for i in count + 1:
			people.append({"name": "Игрок %d" % i})
		var game := Rules.new()
		var error := game.new_game(people, {"bc_roles": selected, "bc_drunk_role": fake, "bc_bluffs": bluffs}, seed_value)
		check(error.is_empty(), "Полная партия %d/%d: подготовка %s" % [seed_value, count, error])
		if not error.is_empty():
			continue
		for id: String in selected:
			covered[id] = true
		check(action(game, 0, "begin_night"), "Полная партия: запуск ночи")
		_drive_requests(game)
		for turn in 5:
			if game.phase == "game_over":
				break
			check(game.phase == "discussion", "После ночи начинается обсуждение")
			if game.phase != "discussion":
				break
			check(action(game, 0, "open_nominations"), "Полная партия: номинации")
			var demon := -1
			var nominator := -1
			for seat: int in game.seats_in_circle():
				if game.alive[seat]:
					nominator = seat
					if game.roles[seat] == "imp":
						demon = seat
			check(demon >= 0 and nominator >= 0, "Есть живой демон и номинирующий")
			if demon < 0 or nominator < 0:
				break
			check(action(game, nominator, "nominate", {"target": demon}), "Полная партия: номинация демона")
			check(action(game, 0, "start_vote"), "Полная партия: голосование")
			for seat: int in game.seats_in_circle():
				if game.alive[seat] or game.dead_votes[seat]:
					check(action(game, seat, "hand", {"raised": true}), "Полная партия: голос")
			for voter in count:
				check(action(game, 0, "count_vote"), "Полная партия: подсчёт")
			check(action(game, 0, "close_day"), "Полная партия: казнь")
			check(game.tick(1.0), "Полная партия: завершение показа казни")
			if game.phase == "game_over":
				break
			check(action(game, 0, "begin_night"), "Ночь после наследования демона")
			_drive_requests(game)
		check(game.phase == "game_over" and game.winner in ["good", "evil"], "Партия доиграна до настоящего результата")
		for seat in range(-1, count + 1):
			var view := game.get_view(seat)
			check(view.winner == game.winner, "Все места получили общий результат")
	check(covered.size() == 22, "88 партий включают все 22 роли сценария")

func _shuffle(items: Array, random: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var temp: Variant = items[i]
		items[i] = items[j]
		items[j] = temp

func _drive_requests(game: Rules) -> void:
	for step in 100:
		if game.phase != "night":
			return
		var recipient := int(game.abilities.pending.get("recipient", -1))
		if recipient < 0:
			check(false, "Полная партия: ночной планировщик завис")
			return
		var public_before := game.get_view(-1)
		check(respond(game, recipient), "Полная партия: допустимый ответ")
		if game.phase == "night":
			check(public_before == game.get_view(-1), "Полная партия: приватный шаг не изменил публичный снимок")
	check(false, "Полная партия: слишком длинная ночная очередь")
