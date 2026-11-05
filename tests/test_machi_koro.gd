extends SceneTree
## Чистые правила и последовательность событий Мачи Коро. Запуск: --headless --audio-driver Dummy --script res://tests/test_machi_koro.gd.

const Rules := preload("res://games/machi_koro/logic/mk_rules.gd")
const Data := preload("res://games/machi_koro/logic/mk_data.gd")
var checks := 0
var failures := 0

func _init() -> void:
	_catalog()
	_setup()
	_payments()
	_choices()
	_closed()
	_landmarks()
	_special()
	_fuzz()
	print("Мачи Коро: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ОШИБКА: " + message)

func make(options: Dictionary = {}, n: int = 3):
	var r := Rules.new()
	var players: Array = []
	for s in n:
		players.append({"name": "Игрок %d" % s, "color": s})
	check(r.new_game(players, options, 42).is_empty(), "подготовка")
	r.current = 0
	return r

func send(r, kind: String, data: Dictionary = {}) -> bool:
	var payload := data.duplicate(true)
	payload.revision = r.revision
	return r.action(r.current, kind, payload)

func finish(r) -> void:
	var guard := 0
	while not r.event.is_empty() and guard < 200:
		guard += 1
		r.tick(100.0)
	check(guard < 200, "очередь показов завершается")

func empty(r) -> void:
	for s in r.players.size():
		r.cities[s].clear()
		r.built[s].clear()
		r.coins[s] = 0
	r.jobs.clear()
	r.event.clear()
	r.choice.clear()
	r.current = 0

func activate(r, result: int) -> void:
	r.result = result
	r.main_dice = [result]
	r._resolve()
	finish(r)

func _catalog() -> void:
	var all: Dictionary = Data.catalog()
	check(all.size() == 38, "ровно 38 видов предприятий трёх наборов")
	var count := {"base": 0, "plus": 0, "sharp": 0}
	var copies := count.duplicate()
	for card: Dictionary in all.values():
		count[card.set] += 1
		copies[card.set] += int(card.copies)
		check(not card.text.is_empty() and card.cost >= 0 and not card.rolls.is_empty(), "полные данные %s" % card.id)
	check(count == {"base": 15, "plus": 10, "sharp": 13}, "типы по PDF: 15/10/13")
	check(copies == {"base": 87, "plus": 58, "sharp": 75}, "резерв по PDF: 87/58/75")
	check(not all.has("conference") and not all.has("bank") and not all.has("aquapark"), "лишние карты TTS исключены")
	check(Data.LANDMARKS.amusement.cost == 16 and Data.LANDMARKS.radio.cost == 22, "исправлены перепутанные достопримечательности TTS")

func _setup() -> void:
	for plus in [false, true]:
		for sharp in [false, true]:
			for limited in [false, true]:
				var r = make({"mk_plus": plus, "mk_sharp": sharp, "mk_limited": limited})
				var copies := 0
				for count: int in r.reserve.values():
					copies += count
				check(copies + r.deck.size() == 87 + (58 if plus else 0) + (75 if sharp else 0), "состав резерва не зависит от раскладки")
				check(r.coins == [3, 3, 3] and r.cities[0].size() == 2, "стартовые 3 монеты и две карты")
				check(not r.get_view(-1).has("deck") and not r.get_view(1).has("jobs"), "не раскрывается порядок закрытой колоды и внутренняя очередь")
				if limited:
					check(r.reserve.size() == 10, "случайный рынок из 10 типов")
	var r = make()
	check(not r.action(1, "roll", {"count": 1, "revision": r.revision}), "чужое место не бросает")
	check(not send(r, "roll", {"count": 2}), "два кубика без вокзала запрещены")
	check(not r.action(0, "roll", {"count": 1}), "нужна ревизия")
	check(send(r, "roll", {"count": 1}), "разрешённый бросок")
	check(not send(r, "roll", {"count": 1}), "повтор во время анимации запрещён")
	finish(r)

func _payments() -> void:
	var r = make()
	empty(r)
	r._add_card(1, "cafe")
	r._add_card(2, "cafe")
	r._add_card(2, "cafe")
	r._add_card(0, "bakery")
	r.coins[0] = 2
	r.result = 3
	r._resolve()
	check(r.coins == [2, 0, 0], "до анимации деньги не меняются")
	var event_id: int = r.event.id
	r.tick(0.5)
	check(r.coins == [2, 0, 0] and r.event.id == event_id, "часть анимации не начисляет деньги")
	r.tick(100)
	check(r.coins == [1, 0, 1], "первым платим месту 2 против часовой стрелки; новый эффект не проглатывает остаток delta")
	finish(r)
	check(r.coins == [1, 0, 2], "сначала две выплаты, затем пекарня; недоплата месту 1 списана")
	var balance: Array = r.coins.duplicate()
	check(not r.tick(100) and r.coins == balance, "завершённое событие не начисляется повторно")
	empty(r)
	r._add_card(0, "flowershop")
	for k in 3:
		r._add_card(0, "flower")
	r.built[0].append("mall")
	activate(r, 6)
	check(r.coins[0] == 6, "Торговый центр: по 2 за каждый из трёх Цветников")
	empty(r)
	r._add_card(0, "loan")
	r._add_card(0, "flowershop")
	r._add_card(0, "flower")
	activate(r, 6)
	check(r.coins[0] >= 0, "оплата банку не создаёт отрицательных монет")

func _choices() -> void:
	var r = make({"mk_sharp": true})
	empty(r)
	r._add_card(0, "tv")
	r.coins[1] = 3
	activate(r, 6)
	check(r.phase == "choice" and r.coins[1] == 3, "Телецентр ждёт выбора, ничего не списывается")
	check(not send(r, "choose", {"index": 99}), "нет выбора вне допустимых вариантов")
	check(send(r, "choose", {"index": 0}), "выбор другого игрока")
	check(r.coins[1] == 3, "выбор не начисляет до показа")
	finish(r)
	check(r.coins == [3, 0, 0], "после анимации Телецентр переводит имеющиеся 3 из 5")
	empty(r)
	r._add_card(0, "business")
	r._add_card(0, "wheat")
	r._add_card(1, "loan")
	r.cities[1][0].closed = true
	activate(r, 6)
	send(r, "choose", {"index": 0})
	check(r.choice.options.size() == 2, "своё фиолетовое предприятие не предлагается на обмен")
	send(r, "choose", {"index": 0})
	send(r, "choose", {"index": 0})
	finish(r)
	check(r.count_type(0, "loan") == 1 and r.count_type(1, "wheat") == 1, "обе карты обменялись автоматически")
	check(r.cities[0][1].closed and r.coins[0] == 0, "закрытие сохраняется, кредит при передаче не начисляется")
	empty(r)
	r._add_card(0, "shipping")
	activate(r, 9)
	send(r, "choose", {"index": 0})
	send(r, "choose", {"index": 0})
	finish(r)
	check(r.cities[0].is_empty() and r.count_type(1, "shipping") == 1 and r.coins == [4, 0, 0], "компания может передать себя; доход получает прежний владелец")

func _closed() -> void:
	var r = make({"mk_sharp": true})
	empty(r)
	r._add_card(0, "cleaning")
	r._add_card(1, "wheat")
	r._add_card(1, "wheat")
	r.cities[1][1].closed = true
	r.coins[1] = 5
	activate(r, 8)
	send(r, "choose", {"index": 0})
	finish(r)
	check(r.coins == [1, 4, 0] and r.cities[1][0].closed, "Клининг берёт монету только за вновь закрытую карту")
	activate(r, 1)
	check(not r.cities[1][0].closed and not r.cities[1][1].closed and r.coins[1] == 4, "закрытые карты открываются вместо дохода")
	activate(r, 1)
	check(r.coins[1] == 6, "в следующий раз обе карты дают доход")
	empty(r)
	r._add_card(0, "winery")
	r._add_card(0, "vineyard")
	r.cities[0][1].closed = true
	activate(r, 9)
	check(r.coins[0] == 6 and r.cities[0][0].closed, "Винный завод учитывает закрытый Виноградник и сам закрывается")

func _landmarks() -> void:
	var r = make({"mk_plus": true, "mk_sharp": true})
	empty(r)
	r._add_card(0, "demolition")
	r._add_card(0, "demolition")
	r.built[0].append("station")
	activate(r, 4)
	check(r.phase == "choice" and r.choice.options.size() == 1, "снос обязателен, Ратуши среди целей нет")
	send(r, "choose", {"index": 0})
	finish(r)
	check(r.built[0].is_empty() and r.coins[0] == 8, "одна достопримечательность даёт только 8, а не 16")
	empty(r)
	activate(r, 2)
	check(r.coins[0] == 1 and r.phase == "build", "Ратуша срабатывает после доходов при нуле")
	r.coins[0] = 100
	r.built[0] = ["station", "mall", "amusement", "radio", "harbor"]
	check(send(r, "landmark", {"card": "airport"}), "строительство последней достопримечательности")
	check(r.winner == -1 and r.coins[0] == 100, "победа и списание ждут завершения строительства")
	finish(r)
	check(r.winner == 0 and r.phase == "game_over" and r.coins[0] == 70, "победа сразу после шестой постройки")

func _special() -> void:
	var r = make({"mk_plus": true, "mk_sharp": true})
	empty(r)
	r._add_card(0, "park")
	r.coins = [1, 2, 1]
	activate(r, 11)
	check(r.coins == [2, 2, 2], "Парк раздаёт поровну, недостающее добавляет банк")
	empty(r)
	r._add_card(0, "tax")
	r._add_card(1, "mine")
	r.coins = [0, 6, 21]
	activate(r, 9)
	check(r.coins == [15, 6, 11], "Налоговая после синих доходов, половина округляется вниз")
	empty(r)
	r._add_card(0, "trawler")
	r._add_card(0, "trawler")
	r._add_card(1, "trawler")
	r.built[0].append("harbor")
	r.built[1].append("harbor")
	r.built[0].append("amusement")
	r.main_dice = [6, 6]
	r.result = 12
	r._resolve()
	check(r.phase == "trawler", "Траулер требует отдельного жеста броска")
	send(r, "roll")
	var total: int = r.dice[0] + r.dice[1]
	finish(r)
	check(r.coins == [total * 2, total, 0], "один бросок оплачивает все подходящие Траулеры")
	check(r.main_dice == [6, 6] and r.result == 12, "дополнительный бросок не меняет основной")
	empty(r)
	r.phase = "build"
	r.coins[0] = 0
	check(send(r, "buy", {"card": "loan"}), "нулевая стоимость кредитного банка")
	check(r.coins[0] == 0, "нет бонуса до анимации строительства")
	r.tick(100)
	check(r.count_type(0, "loan") == 1 and r.coins[0] == 0, "банк построен; его бонус — следующим событием")
	finish(r)
	check(r.coins[0] == 5, "после показа бонуса банк дал 5")

func _fuzz() -> void:
	for game in 24:
		var r = make({"mk_plus": game % 2 == 0, "mk_sharp": game % 3 != 0, "mk_limited": game % 2 != 0}, 2 + game % 4)
		r.rng.seed = game + 50
		var steps := 0
		while r.winner < 0 and steps < 24000:
			steps += 1
			if not r.event.is_empty():
				r.tick(100)
			elif r.phase in ["roll", "trawler"]:
				send(r, "roll", {"count": 2 if r.built[r.current].has("station") else 1})
			elif r.phase == "reroll":
				send(r, "keep")
			elif r.phase == "harbor":
				send(r, "harbor", {"add": false})
			elif r.phase == "choice":
				# Драйвер теста, не бот игры: выбирает допустимый вариант без стратегии.
				send(r, "choose", {"index": r.rng.randi_range(0, r.choice.options.size() - 1)})
			elif r.phase == "build":
				var done := false
				for id: String in Data.landmarks(r.plus):
					if not r.built[r.current].has(id) and r.coins[r.current] >= Data.LANDMARKS[id].cost:
						done = send(r, "landmark", {"card": id})
						break
				if not done:
					var options: Array = []
					for id: String in r.reserve:
						if r.can_buy(id):
							options.append(id)
					if not options.is_empty() and r.rng.randf() < 0.5:
						send(r, "buy", {"card": options[r.rng.randi_range(0, options.size() - 1)]})
					else:
						send(r, "pass")
			else:
				check(false, "зависшая фаза %s" % r.phase)
				break
			for balance: int in r.coins:
				if balance < 0:
					check(false, "отрицательные деньги в партии %d" % game)
					break
		check(r.winner >= 0, "полная партия %d завершилась за %d шагов" % [game, steps])
