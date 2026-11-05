extends SceneTree
## Контракты подготовки, приватности, номинаций и голосования Clocktower; способности ещё не покрыты.
## --headless --audio-driver Dummy --path . --script res://tests/test_blood_on_the_clocktower.gd.

const Rules := preload("res://games/blood_on_the_clocktower/logic/bc_rules.gd")
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("ОШИБКА: " + message)

func seats(count: int) -> Array:
	var result: Array = []
	for i in count:
		result.append({"name": "Игрок %d" % i, "color": i, "steam_id": 9900 + i, "secret": "НЕ ПЕРЕДАВАТЬ"})
	return result

func base(story: int = 0) -> Rules:
	var game := Rules.new()
	var error := game.new_game(seats(6), {"bc_storyteller": story,
		"bc_roles": ["washerwoman", "empath", "monk", "poisoner", "imp"],
		"bc_bluffs": ["chef", "soldier", "mayor"]}, 20261105)
	check(error.is_empty(), "Базовая подготовка: " + error)
	return game

func act(game: Rules, seat: int, kind: String, arg: Dictionary = {}) -> bool:
	var sent := arg.duplicate(true)
	sent["revision"] = game.public_revision
	return game.action(seat, kind, sent)

func _run() -> void:
	_catalog()
	_setup()
	_privacy()
	_choices()
	_votes()
	_simultaneous_hands()
	_public_whispers()
	_owner_rules_06()
	print("Clocktower: %d проверок, %d ошибок. Способности/Net/UI ещё не проверены." % [checks, failures])
	quit(1 if failures > 0 else 0)

func _catalog() -> void:
	check(Data.catalog().size() == 72, "Полный справочник 72 базовых ролей")
	for edition: String in Data.EDITIONS:
		for kind: String in ["townsfolk", "outsider", "minion", "demon"]:
			var expected := 13 if kind == "townsfolk" else (1 if edition == "tb" and kind == "demon" else 4)
			check(Data.roles(edition, kind).size() == expected, "Комплектность %s/%s" % [edition, kind])
		for card: Dictionary in Data.handbook(edition):
			check(not str(card.name).is_empty() and not str(card.text).is_empty() and card.page >= 2, "Русская памятка и ссылка альманаха: " + str(card.id))
	check(Data.handbook("tb", "Монах").size() == 1, "Поиск справочника на русском")
	check(Data.handbook("", "несуществующее").is_empty(), "Пустой поиск")

func _setup() -> void:
	var game := base(3)
	check(game.seats_in_circle() == [0, 1, 2, 4, 5], "Рассказчик исключён из круга и населения")
	check(game.alive_count() == 5 and game.alive_count(true) == 5, "Рассказчик не считается живым игроком")
	var existing := game.grimoire()
	check(not game.new_game(seats(6), {"bc_roles": []}).is_empty(), "Отказ пустого состава")
	check(game.grimoire() == existing, "Неудачная подготовка не уничтожает текущую партию")
	check(not game.validate_setup("tb", ["empath", "empath", "monk", "poisoner", "imp"], 5).is_empty(), "Нет повторных ролей")
	check(not game.validate_setup("tb", ["grandmother", "empath", "monk", "poisoner", "imp"], 5).is_empty(), "Роли другого сценария запрещены")
	check(not game.validate_setup("bmr", ["grandmother", "sailor", "chambermaid", "assassin", "po"], 5).is_empty(), "Сложные сценарии начинаются с семи игроков по PDF")
	check(game.validate_setup("tb", ["empath", "butler", "saint", "baron", "imp"], 5).is_empty(), "Барон заменяет двух горожан изгоями")
	for edition: String in Data.EDITIONS:
		for count in range(int(Data.EDITIONS[edition].minimum), 16):
			var selected: Array = []
			var buckets := ["townsfolk", "outsider", "minion", "demon"]
			# Без меняющих состав ролей, чтобы проверить саму таблицу населения.
			for i in 4:
				var pool := Data.roles(edition, buckets[i])
				for excluded: String in ["baron", "godfather", "fang_gu", "vigormortis"]:
					pool.erase(excluded)
				selected.append_array(pool.slice(0, int(Data.COUNTS[count][i])))
			check(game.validate_setup(edition, selected, count).is_empty(), "Население %s/%d" % [edition, count])
	var bad_seats := seats(6)
	bad_seats[1]["bot"] = true
	check(not game.new_game(bad_seats).is_empty(), "Бот не заменяет человека")
	var bad_bluffs := {"bc_roles": ["washerwoman", "empath", "monk", "poisoner", "imp"], "bc_bluffs": ["empath", "chef", "mayor"]}
	check(not game.new_game(seats(6), bad_bluffs).is_empty(), "Блеф не раскрывает роль, реально находящуюся в партии")
	var drunk := Rules.new()
	check(drunk.new_game(seats(7), {"bc_roles": ["washerwoman", "empath", "monk", "drunk", "poisoner", "imp"],
		"bc_drunk_role": "soldier", "bc_bluffs": ["chef", "mayor", "slayer"]}, 5).is_empty(), "Скрытая подставная роль Пьяницы")
	var drunk_seat := drunk.roles.find("drunk")
	check(drunk.get_view(drunk_seat).role == "soldier", "Пьянице показан горожанин")
	check(not drunk.get_view(drunk_seat).has("status"), "Пьянице не сообщено опьянение")
	var impossible_bluff := {"bc_roles": ["washerwoman", "empath", "monk", "drunk", "poisoner", "imp"],
		"bc_drunk_role": "soldier", "bc_bluffs": ["chef", "mayor", "soldier"]}
	check(not drunk.new_game(seats(7), impossible_bluff).is_empty(), "Подставная роль Пьяницы исключается из блефов")

func _privacy() -> void:
	var game := base()
	var before := game.get_view(-1)
	game.status[1] = {"poisoned": true, "demon_target": 4}
	game.alive[2] = false
	game.roles[3] = "spy"
	game.add_private(2, "ТАЙНА НОЧИ")
	var token := game.request_choice(2, "Выберите жертву", [1, 4])
	check(not token.is_empty(), "Адресный запрос создан")
	check(game.get_view(-1) == before, "Зритель не видит ночную смерть, яд, роли, запросы и рост счётчика")
	for seat in range(1, 6):
		var view := game.get_view(seat)
		for person: Dictionary in view.players:
			check(not person.has("role") and not person.has("side") and not person.has("status") and not person.has("steam_id") and not person.has("secret"), "Публичное место содержит только белый список")
		check(not view.has("grimoire"), "Гримуар не попал обычному игроку")
		check(view.has("request") == (seat == 2), "Запрос доступен только адресату")
		check(view.messages.has("ТАЙНА НОЧИ") == (seat == 2), "Ночное сообщение адресное")
	check(game.get_view(0).grimoire.size() == 5, "Рассказчик видит полный гримуар")
	var changed := game.get_view(0)
	changed.grimoire[0].status["tampered"] = true
	changed.players[1].name = "Взлом"
	check(not game.status[1].has("tampered") and game.players[1].name != "Взлом", "Изменение view не изменяет хост")
	game.dawn()
	check(not game.get_view(-1).players[2].alive, "Смерть объявлена только на рассвете")
	check(not JSON.stringify(game.get_view(-1)).contains("ТАЙНА НОЧИ"), "Сериализация публичного состояния не раскрывает ночной журнал")

func _choices() -> void:
	var game := base()
	var snapshot := game.get_view(-1)
	var token := game.request_choice(1, "Выбор", [{"target": 2}, {"target": 4}])
	check(not game.action(2, "private_reply", {"token": token, "index": 0}), "Чужой ответ запрещён")
	check(not game.action(1, "private_reply", {"token": "угаданный", "index": 0}), "Чужой/устаревший идентификатор запрещён")
	check(not game.action(1, "private_reply", {"token": token, "index": -1}), "Отрицательный вариант запрещён")
	check(not game.action(1, "private_reply", {"token": token, "index": 8}), "Вариант вне списка запрещён")
	check(not game.action(1, "private_reply", {"token": token, "index": 0.5}), "Дробный индекс не приводится к допустимому")
	check(game.action(1, "private_reply", {"token": token, "index": 1}), "Владелец выбрал допустимую цель")
	check(game.status[1].reply.target == 4, "Хост принимает только вариант из своего списка")
	check(not game.action(1, "private_reply", {"token": token, "index": 1}), "Повторный ответ не применяется")
	check(game.get_view(-1) == snapshot, "Приватный выбор не меняет публичные данные/ревизию")

func _votes() -> void:
	var game := base()
	game.dawn()
	check(not act(game, 1, "open_nominations", {"host": true}), "Поддельный флаг хоста не заменяет рассказчика")
	check(act(game, 0, "open_nominations"), "Рассказчик открывает номинации")
	check(not game.action(1, "nominate", {"target": 2, "revision": -1}), "Устаревшая номинация отклоняется")
	check(act(game, 1, "nominate", {"target": 2}), "Живой номинирует")
	check(not act(game, 3, "nominate", {"target": 4}), "Вторая номинация ждёт завершения первой")
	check(act(game, 0, "start_vote"), "После защиты начато голосование")
	check(game.vote_order.back() == 2 and not game.vote_order.has(0), "Номинант голосует последним, рассказчик не голосует")
	for seat: int in [1, 2, 3]:
		check(act(game, seat, "hand", {"raised": true}), "Можно голосовать за себя и другого")
	for step in 5:
		check(act(game, 0, "count_vote"), "Последовательный подсчёт")
	check(game.leader == 2 and game.high_vote == 3, "Порог половины пяти живых округляется вверх")
	check(not act(game, 1, "nominate", {"target": 4}), "Нельзя номинировать второй раз за день")
	check(not act(game, 3, "nominate", {"target": 2}), "Нельзя номинировать прежнего кандидата")
	check(act(game, 3, "nominate", {"target": 4}), "Следующая номинация")
	check(act(game, 0, "start_vote"), "Второе голосование")
	for seat: int in [1, 2, 3]:
		check(act(game, seat, "hand", {"raised": true}), "Живой может голосовать снова")
	for step in 5:
		act(game, 0, "count_vote")
	check(game.leader == -1 and game.high_vote == 3, "Равенство снимает лидера и сохраняет планку")
	check(act(game, 0, "close_day"), "Можно закончить день без казни")
	check(game.executed == -1 and game.phase == "dusk", "Ничья означает отсутствие казни")
	game.dawn()
	game.alive[5] = false
	game.announced_alive[5] = false
	act(game, 0, "open_nominations")
	check(not act(game, 5, "nominate", {"target": 1}), "Мёртвый не номинирует")
	act(game, 1, "nominate", {"target": 2})
	act(game, 0, "start_vote")
	check(act(game, 5, "hand", {"raised": true}), "Мёртвый может использовать последний голос")
	act(game, 3, "hand", {"raised": true})
	for step in 5:
		act(game, 0, "count_vote")
	check(not game.dead_votes[5] and game.leader == 2, "Потрачен ровно один голос мёртвого, порог из четырёх живых равен двум")
	act(game, 3, "nominate", {"target": 4})
	act(game, 0, "start_vote")
	check(not act(game, 5, "hand", {"raised": true}), "Второй голос мёртвого запрещён")
	for step in 5:
		act(game, 0, "count_vote")
	check(act(game, 0, "close_day"), "Казнь поставлена в очередь показа")
	check(game.alive[2] and not game.event.is_empty(), "До конца показа казни игрок жив")
	check(not game.tick(NAN), "Некорректное время не проводит событие")
	check(not game.tick(0.5) and game.alive[2], "Промежуточное время не меняет жизнь")
	check(game.tick(0.5) and not game.alive[2], "По завершении показа проведена казнь")
	var log_size := game.public_log.size()
	check(not game.tick(1000.0) and game.public_log.size() == log_size, "Повторный tick не повторяет казнь")

## 06.11, решение владельца: днём все видят, кто с кем шепчется, но не текст; ночью — ничего.
## 06.11, решения владельца: мёртвых не номинировать (кроме «Дурной луны»), ночные голоса зла,
## экран победы по кнопке хоста.
func _owner_rules_06() -> void:
	var game := base()
	game.dawn()
	game.alive[3] = false
	game.announced_alive[3] = false
	act(game, 0, "open_nominations")
	check(not act(game, 1, "nominate", {"target": 3}), "Мёртвого нельзя номинировать")
	check(act(game, 1, "nominate", {"target": 2}), "Живого номинировать можно")
	game.edition = "bmr"
	check(game.can_be_nominated(3), "В «Дурной луне» мёртвого можно номинировать (Зомбуул)")
	check(game.get_view(4).nominated == [2] and game.get_view(4).nominators == [1], "Кто номинирован сегодня — публично")
	# Голоса зла: 7 игроков без рассказчика, места 1..7.
	var big := Rules.new()
	var roles := ["washerwoman", "empath", "monk", "chef", "soldier", "poisoner", "imp"]
	check(big.new_game(seats(8), {"bc_roles": roles, "bc_bluffs": ["librarian", "mayor", "slayer"]}, 7).is_empty(), "Подготовка на 7 игроков")
	for i in roles.size():
		big.roles[i + 1] = roles[i]
		big.shown_roles[i + 1] = roles[i]
		big.sides[i + 1] = big.catalog[roles[i]].side
	check(not big.action(6, "evil_vote", {"target": 2}), "До начала ночи голосов зла нет")
	big.phase = "night"
	check(big.action(6, "evil_vote", {"target": 2}), "Приспешник голосует ночью")
	check(not big.action(7, "evil_vote", {"target": 3}), "Демон не голосует — он решает")
	check(not big.action(1, "evil_vote", {"target": 3}), "Добрый не голосует")
	check(not big.action(6, "evil_vote", {"target": 0}), "Рассказчик не цель")
	check(big.get_view(7).evil_votes == [{"from": 6, "target": 2}], "Демон видит голос приспешника")
	check(big.get_view(6).evil_vote_open and not big.get_view(7).evil_vote_open, "Кнопка голоса только у приспешника")
	check(not big.get_view(1).has("evil_votes") and not big.get_view(-1).has("evil_votes"), "Добрые и зрители не видят голосов зла")
	check(not big.get_view(0).has("evil_votes"), "Голоса не смешиваются с гримуаром рассказчика")
	big.alive[6] = false
	check(not big.action(6, "evil_vote", {"target": 3}), "Мёртвый приспешник не голосует")
	big.dawn()
	check(big.get_view(7).evil_votes.is_empty(), "Голоса сбрасываются с рассветом")
	var small := base()
	small.phase = "night"
	check(not small.action(4, "evil_vote", {"target": 1}), "При 5–6 игроках голосования нет")
	check(not small.get_view(4).has("evil_votes"), "При 5–6 игроках зло не узнаёт друг друга из голосов")
	check(not big.get_view(1).victory_open, "Экран победы закрыт до кнопки хоста")

func _public_whispers() -> void:
	var game := base()
	var log_size := game.public_log.size()
	check(game.action(1, "whisper", {"target": 0, "text": "Ночной вопрос"}), "Ночью можно написать рассказчику")
	check(game.public_log.size() == log_size and game.get_view(3).last_whisper.is_empty(), "Ночной разговор не виден")
	game.dawn()
	var revision := game.public_revision
	check(game.action(1, "whisper", {"target": 3, "text": "Я Прачка, секрет"}), "Днём игроки шепчутся")
	var outsider := game.get_view(5)
	check(outsider.last_whisper == [1, 3], "Посторонний видит пару собеседников")
	check(str(outsider.log.back()) == "Игрок 1 и Игрок 3 шепчутся.", "В журнале факт разговора: " + str(outsider.log.back()))
	check(not JSON.stringify(outsider).contains("секрет"), "Текст шёпота не уходит постороннему")
	check(str(game.get_view(3).messages.back()).contains("секрет"), "Адресат получил текст")
	check(game.public_revision == revision, "Шёпот не сдвигает ревизию и не отклоняет чужие действия")
	var size_after := game.public_log.size()
	check(game.action(3, "whisper", {"target": 1, "text": "Ответ"}), "Ответ в той же паре")
	check(game.public_log.size() == size_after, "Переписка той же пары не дублирует строку журнала")
	check(game.action(4, "whisper", {"target": 0, "text": "Вопрос по роли"}), "Игрок пишет рассказчику днём")
	check(str(game.public_log.back()) == "Игрок 4 говорит с рассказчиком.", "Разговор с рассказчиком тоже виден")
	check(game.get_view(2).last_whisper == [0, 4], "Пара с рассказчиком в публичном снимке")
	game.phase = "dusk"
	game.dawn()
	check(game.get_view(2).last_whisper.is_empty(), "Новый день сбрасывает отметку шёпота")

## Ревью 05.11: руки поднимают одновременно с одним и тем же view — ни одно нажатие не теряется.
func _simultaneous_hands() -> void:
	var game := base()
	game.dawn()
	act(game, 0, "open_nominations")
	act(game, 1, "nominate", {"target": 2})
	act(game, 0, "start_vote")
	var stale: int = game.public_revision
	for seat: int in [1, 3, 4]:
		check(game.action(seat, "hand", {"revision": stale, "raised": true}), "Одновременная рука места %d принята" % seat)
	check(game.hands[1] and game.hands[3] and game.hands[4], "Все три руки подняты")
	check(game.action(3, "hand", {"revision": stale, "raised": false}), "Руку можно опустить до подсчёта")
	check(game.action(3, "hand", {"revision": stale, "raised": true}), "И снова поднять")
	check(not game.action(0, "hand", {"raised": true}), "Рассказчик не голосует")
	check(not game.action(3, "hand", {"raised": "да"}), "Рука принимает только логическое значение")
	var first: int = game.vote_order[0]
	check(not game.action(0, "count_vote", {"voter": game.vote_order[1]}), "Подсчёт не того голосующего отклонён")
	check(not game.action(1, "count_vote", {"voter": first}), "Считает только рассказчик")
	check(game.action(0, "count_vote", {"voter": first, "revision": stale}), "Подсчёт по ожидаемому голосующему при устаревшей ревизии")
	check(not game.action(0, "count_vote", {"voter": first}), "Двойное нажатие не считает следующего игрока")
	check(not game.action(first, "hand", {"raised": not bool(game.hands[first])}), "После подсчёта руку не изменить")
	while game.phase == "voting":
		game.action(0, "count_vote", {"voter": game.vote_order[game.vote_cursor]})
	check(game.leader == 2 and game.high_vote == 3, "Засчитаны все три одновременные руки")
	check(not game.action(4, "hand", {"raised": true}), "Вне голосования рука не принимается")
