extends SceneTree
## Адресные проверки «Дурной луны», особых смертей и скрытого состояния Зомбуула.
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
	var g := Rules.new()
	var people: Array = []
	for i in 9:
		people.append({"name": "Место %d" % i})
	var initial := ["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "assassin", "pukka"]
	check(g.new_game(people, {"bc_edition": "bmr", "bc_roles": initial, "bc_bluffs": ["professor", "fool", "minstrel"]}, 32).is_empty(), "Подготовка BMR")
	if ids.is_empty():
		ids = initial
	for i in ids.size():
		g.roles[i + 1] = ids[i]
		g.shown_roles[i + 1] = ids[i]
		g.sides[i + 1] = g.catalog[ids[i]].side
	g.abilities.started = true
	g.abilities.night_no = 1
	g.phase = "night"
	return g

func respond(g: Rules, index: int = 0) -> bool:
	var recipient := int(g.abilities.pending.get("recipient", -1))
	if not g.requests.has(recipient):
		return false
	return g.action(recipient, "private_reply", {"token": g.requests[recipient].token, "index": index})

func choose(g: Rules, field: String, value: Variant) -> bool:
	var recipient := int(g.abilities.pending.get("recipient", -1))
	if not g.requests.has(recipient):
		return false
	var options: Array = g.requests[recipient].options
	for i in options.size():
		if options[i].get(field) == value:
			return respond(g, i)
	return false

func act(g: Rules, seat: int, kind: String, args: Dictionary = {}) -> bool:
	var sent := args.duplicate(true)
	sent["revision"] = g.public_revision
	return g.action(seat, kind, sent)

func _run() -> void:
	_protection()
	_choices()
	_demons()
	_death_triggers()
	_nights()
	print("Clocktower BMR: %d проверок, %d ошибок." % [checks, failures])
	quit(1 if failures > 0 else 0)

func _protection() -> void:
	var g := fixture()
	g.abilities._kill(2, 8, "demon")
	check(g.alive[2], "Трезвый Моряк не погибает")
	g.abilities._resolve_targets(2, "sailor", [2])
	check(choose(g, "target", 2), "Моряк выбирает себя, пьян он сам")
	g.abilities._kill(2, 8, "demon")
	check(not g.alive[2], "Пьяный Моряк погибает")
	g = fixture(["tea_lady", "sailor", "chambermaid", "fool", "gambler", "tinker", "assassin", "pukka"])
	# Чайная дама между добрыми местами 2 и 4.
	g.roles[3] = "tea_lady"
	g.shown_roles[3] = "tea_lady"
	g.roles[1] = "grandmother"
	g.abilities._kill(4, 8, "demon")
	check(g.alive[4] and not g.status[4].get("fool_used", false), "Чайная дама спасает прежде расходования Шута")
	g.abilities._kill(4, 7, "assassin")
	check(not g.alive[4], "Ассасин обходит Чайную даму и Шута")
	g = fixture(["grandmother", "innkeeper", "chambermaid", "fool", "gambler", "tinker", "devils_advocate", "pukka"])
	g.abilities._resolve_targets(2, "innkeeper", [3, 4])
	check(choose(g, "target", 3), "Трактирщик: пьянеет один из выбранных")
	g.abilities._kill(4, 8, "demon")
	check(g.alive[4] and not g.status[4].get("fool_used", false), "Трактирщик защищает ночью без траты Шута")
	g.phase = "discussion"
	g.abilities._kill(4, 1, "gambler")
	check(g.alive[4] and g.status[4].fool_used, "Ночная защита закончилась днём, Шут использован")
	g.abilities._kill(4, 1, "gambler")
	check(not g.alive[4], "Вторая попытка убивает Шута")
	g = fixture(["grandmother", "courtier", "chambermaid", "fool", "gambler", "tinker", "devils_advocate", "pukka"])
	g.abilities._resolve_targets(7, "devils_advocate", [8])
	g.phase = "discussion"
	g.abilities.execute(8)
	check(g.alive[8] and g.executed == 8 and g.execution_death == -1, "Адвокат допускает казнь без смерти демона")
	g.abilities._wake(2, "courtier")
	check(choose(g, "role", ""), "Придворный может отложить способность")
	check(not g.status[2].get("once", false), "Отказ не тратит Придворного")
	g.abilities._wake(2, "courtier")
	check(choose(g, "role", "devils_advocate"), "Придворный выбрал роль Адвоката")
	check(not g.abilities.healthy(7), "Адвокат опьянён")
	g.abilities._kill(8, -1, "execution")
	check(not g.alive[8], "Подавление источника снимает защиту от казни")
	g = fixture(["grandmother", "courtier", "chambermaid", "fool", "gambler", "tinker", "devils_advocate", "pukka"])
	g.abilities._wake(2, "courtier")
	choose(g, "role", "pukka")
	check(not g.abilities.healthy(8), "Демон пьян сразу")
	g.abilities.night_no = 3
	check(not g.abilities.healthy(8), "Эффект действует третью ночь")
	g.abilities.night_no = 4
	check(g.abilities.healthy(8), "На четвёртой ночи эффект снят")
	g = fixture(["pacifist", "sailor", "chambermaid", "fool", "gambler", "tinker", "assassin", "pukka"])
	g.phase = "discussion"
	g.abilities.execute(3)
	check(g.requests.has(0), "Пацифист оставляет решение рассказчику")
	check(choose(g, "save", true) and g.alive[3] and g.executed == 3, "Пацифист спасает казнённого без отмены казни")

func _choices() -> void:
	var g := fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "goon", "assassin", "pukka"])
	g.abilities._resolve_targets(8, "pukka", [6])
	check(not g.abilities.healthy(8) and g.sides[6] == "evil", "Первый выбор Громилы опьяняет демона и меняет сторону Громилы")
	check(not g.status[6].has("pukka_source"), "Первый выбор Громилы не создаёт яд")
	g.abilities._resolve_targets(5, "gambler", [6])
	check(g.abilities.healthy(5), "Следующий выбравший Громилу не пьянеет")
	choose(g, "role", "goon")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "goon", "assassin", "pukka"])
	g.abilities._resolve_targets(7, "assassin", [6])
	check(not g.alive[6] and g.sides[6] == "evil", "Ассасин убивает Громилу, который всё же становится злым")
	g = fixture()
	g.abilities._wake(5, "gambler")
	choose(g, "target", 8)
	choose(g, "role", "pukka")
	check(g.alive[5] and g.private_log[5].is_empty(), "Правильная ставка Азартного игрока не даёт отдельного ответа")
	g.abilities._wake(5, "gambler")
	choose(g, "target", 8)
	choose(g, "role", "po")
	check(not g.alive[5], "Неправильная ставка Азартного игрока убивает его")
	g = fixture(["grandmother", "professor", "chambermaid", "exorcist", "gambler", "tinker", "assassin", "pukka"])
	g.alive[3] = false
	g.status[3]["once"] = true
	g.abilities._resolve_targets(2, "professor", [3])
	check(g.alive[3] and not g.status[3].has("once"), "Профессор воскрешает горожанина и возвращает способность")
	check(g.status[2].once, "Профессор потратил одноразовую способность")
	g = fixture()
	g.status[2]["woke"] = true
	g.status[4]["woke"] = true
	g.abilities._resolve_targets(3, "chambermaid", [2, 4])
	check(str(g.private_log[3].back()).contains("2"), "Горничная считает только просыпавшихся выбранных")
	g.abilities._add_drunk(3, 2, 1)
	g.abilities._resolve_targets(3, "chambermaid", [2, 4])
	check(g.requests.has(0) and g.requests[0].options.size() == 3, "Пьяной Горничной рассказчик выбирает ложное или верное число")

func _demons() -> void:
	var g := fixture()
	g.abilities._resolve_targets(8, "pukka", [5])
	check(not g.abilities.healthy(5) and g.alive[5], "Пукка сначала отравляет, не убивает")
	g.abilities._resolve_targets(4, "exorcist", [8])
	check(g.private_log[8].back().contains("Экзорцист"), "Демон узнаёт Экзорциста")
	g.abilities._wake(8, "pukka")
	check(not g.alive[5] and not g.requests.has(8), "Старая жертва Пукки погибает даже под Экзорцистом, нового выбора нет")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "assassin", "po"])
	g.abilities._resolve_targets(8, "po", [-1])
	check(g.status[8].po_charged, "По зарядил три убийства")
	g.abilities._resolve_targets(8, "po", [1, 3, 4])
	check(not g.alive[1] and not g.alive[3] and not g.alive[4] and not g.status[8].po_charged, "По последовательно убил троих и снял заряд")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "assassin", "po"])
	g.status[8]["exorcist_source"] = 4
	g.abilities._wake(8, "po")
	check(g.status[8].po_charged and not g.status[8].get("woke", false), "Экзорцист по переданному альманаху заряжает По без пробуждения")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "assassin", "shabaloth"])
	g.abilities._resolve_targets(8, "shabaloth", [3, 4])
	check(not g.alive[3] and not g.alive[4], "Шабалот убивает две выбранные цели")
	g.abilities._residual(8, "shabaloth")
	check(choose(g, "target", 3) and g.alive[3], "Шабалот возвращает прошлую жертву по выбору рассказчика")
	check(g.requests.has(8), "После воскрешения Шабалот выбирает новые цели")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "assassin", "zombuul"])
	g.phase = "discussion"
	g.abilities.execute(8)
	check(g.alive[8] and not g.announced_alive[8] and not g.is_living_player(8), "Первую смерть Зомбуула публика видит, но демон жив")
	check(g.voting_population() == 7 and g.alive_count() == 8, "Зомбуула исключают из публичного населения, а не из истинно живых")
	var public_view := g.get_view(1)
	check(not public_view.players[8].alive and not public_view.players[8].has("role"), "Обычному игроку не показано, что Зомбуул на самом деле жив")
	g.abilities.execute(8)
	check(not g.alive[8] and g.winner == "good", "Вторая смерть Зомбуула настоящая")

func _death_triggers() -> void:
	var g := fixture()
	g.status[1]["grandchild"] = 3
	g.abilities._kill(3, 8, "demon")
	check(not g.alive[1] and not g.alive[3], "Демон убил внука — Бабушка погибла")
	g = fixture(["grandmother", "minstrel", "chambermaid", "exorcist", "gambler", "tinker", "assassin", "pukka"])
	g.phase = "discussion"
	g.abilities._kill(7, 6, "tinker")
	check(g.abilities.minstrel_sources.has(2), "Менестрель реагирует на дневную смерть приспешника не только от казни")
	g.phase = "dusk"
	check(act(g, 0, "begin_night"), "Следующая ночь после Менестреля")
	check(not g.abilities.healthy(8) and g.abilities.healthy(2), "Менестрель опьяняет демона, но не себя")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "mastermind", "pukka"])
	g.day = 1
	g.phase = "discussion"
	g.abilities.execute(8)
	check(g.winner.is_empty() and g.abilities.mastermind_day == 2, "Кукловод откладывает исход после настоящей казни демона")
	g.day = 2
	g.phase = "discussion"
	g.abilities.execute(3)
	check(g.winner == "evil", "Казнь доброго в последний день Кукловода приносит победу злу")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "mastermind", "pukka"])
	g.day = 1
	g.phase = "discussion"
	g.abilities.execute(8)
	g.day = 2
	g.phase = "dusk"
	g.executed = -1
	g.abilities.dusk()
	check(g.winner == "good", "Пропуск казни в последний день Кукловода приносит победу добру")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "moonchild", "assassin", "pukka"])
	g.phase = "discussion"
	g.abilities.execute(6)
	check(g.requests.has(6), "Дитя луны после объявления смерти выбирает публичную цель")
	choose(g, "target", 3)
	g.phase = "night"
	g.abilities._wake(6, "moonchild")
	check(not g.alive[3], "Выбранный добрый погибает следующей ночью")
	g = fixture()
	g.phase = "discussion"
	check(act(g, 0, "tinker", {"target": 6}) and g.alive[6], "Лудильщик ожидает показа дневного события")
	g.tick(1.0)
	check(not g.alive[6], "Лудильщик погиб после показа")
	check(not act(g, 0, "tinker", {"target": 5}), "Кнопка Лудильщика не убивает произвольного игрока")
	g = fixture(["gossip", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "godfather", "pukka"])
	g.phase = "discussion"
	g.day = 1
	check(act(g, 1, "gossip", {"text": "Место 8 — демон"}), "Публичная сплетня записана")
	choose(g, "value", true)
	g.phase = "night"
	g.abilities._wake(1, "gossip")
	check(g.requests.has(0), "Истинная сплетня создаёт обязательный выбор жертвы")
	choose(g, "target", 3)
	check(not g.alive[3], "Система исполнила убийство по сплетне")
	g = fixture(["grandmother", "sailor", "chambermaid", "exorcist", "gambler", "tinker", "godfather", "pukka"])
	g.phase = "discussion"
	g.abilities._kill(6, 6, "tinker")
	check(g.abilities.outsider_died, "Дневная смерть изгоя отмечена для Крёстного отца")
	g.phase = "night"
	g.abilities.night_no = 2
	g.abilities._wake(7, "godfather")
	choose(g, "target", 3)
	check(not g.alive[3], "Крёстный отец исполнил ответное убийство")

func _nights() -> void:
	var g := fixture()
	g.abilities.started = false
	g.abilities.night_no = 0
	g.phase = "first_night"
	check(act(g, 0, "begin_night"), "Запуск первой ночи BMR")
	for step in 70:
		if g.phase != "night":
			break
		var before := g.get_view(-1)
		check(respond(g), "Первый допустимый ответ ночной очереди BMR")
		if g.phase == "night":
			check(before == g.get_view(-1), "Скрытая очередь BMR не меняет публичный снимок")
	check(g.phase == "discussion" and g.day == 1, "Первая ночь BMR закончена")
	check(g.status[8].get("woke", false), "Пукка просыпался в первую ночь")
