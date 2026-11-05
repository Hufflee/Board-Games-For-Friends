extends SceneTree
## Адресные проверки смен ролей, ложной информации и скрытых эффектов SV.
const Rules := preload("res://games/blood_on_the_clocktower/logic/bc_rules.gd")
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
	var initial := ["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "vortox"]
	check(g.new_game(people, {"bc_edition": "sv", "bc_roles": initial, "bc_bluffs": ["artist", "savant", "mutant"]}, 17).is_empty(), "Подготовка SV")
	if ids.is_empty():
		ids = ["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "fang_gu"]
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

func choose(g: Rules, key: String, value: Variant) -> bool:
	var recipient := int(g.abilities.pending.get("recipient", -1))
	if not g.requests.has(recipient):
		return false
	var options: Array = g.requests[recipient].options
	for i in options.size():
		if options[i].get(key) == value:
			return respond(g, i)
	return false

func act(g: Rules, seat: int, kind: String, args: Dictionary = {}) -> bool:
	var sent := args.duplicate(true)
	sent["revision"] = g.public_revision
	return g.action(seat, kind, sent)

func _run() -> void:
	_roles()
	_poison_and_death()
	_minions()
	_information()
	_private_day()
	_night()
	print("Clocktower SV: %d проверок, %d ошибок." % [checks, failures])
	quit(1 if failures > 0 else 0)

func _roles() -> void:
	var g := fixture()
	g.abilities._resolve_targets(3, "snake_charmer", [8])
	check(g.roles[3] == "fang_gu" and g.sides[3] == "evil", "Заклинатель змей стал злым демоном")
	check(g.roles[8] == "snake_charmer" and g.sides[8] == "good" and not g.abilities.healthy(8), "Бывший демон стал добрым отравленным Заклинателем")
	check(g.get_view(8).role == "snake_charmer" and not g.get_view(8).has("status"), "Новая роль адресная, яд отдельным полем не раскрывается")
	g = fixture(["philosopher", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "fang_gu"])
	g.abilities._wake(1, "philosopher")
	check(choose(g, "role", "dreamer"), "Философ выбрал Сновидца")
	check(g.roles[1] == "dreamer" and not g.abilities.healthy(2), "Философ получил роль, оригинальный Сновидец пьян")
	g.alive[1] = false
	check(g.abilities.healthy(2), "Смерть бывшего Философа снимает опьянение копии")
	g = fixture(["clockmaker", "dreamer", "philosopher", "mathematician", "seamstress", "sweetheart", "witch", "fang_gu"])
	g.abilities.processed_slots.append("clockmaker")
	g.abilities._wake(3, "philosopher")
	choose(g, "role", "clockmaker")
	check(g.private_log[3].size() >= 2, "Новая роль с начальной информацией действует сразу, даже после её слота")
	g = fixture(["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "barber", "witch", "fang_gu"])
	g.abilities._kill(6, 8, "demon")
	g.abilities._wake(6, "barber")
	check(choose(g, "target", 8), "По переданному альманаху Парикмахер разрешает демону выбрать себя")
	check(choose(g, "target", 1), "Вторая цель обмена")
	check(g.roles[8] == "clockmaker" and g.sides[8] == "evil" and g.roles[1] == "fang_gu" and g.sides[1] == "good", "Парикмахер меняет роли, но не стороны")
	g = fixture(["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "pit_hag", "fang_gu"])
	g.abilities._resolve_targets(7, "pit_hag", [2])
	choose(g, "role", "clockmaker")
	check(g.roles[2] == "dreamer", "Ведьма из ямы не создаёт повторную роль")
	g.abilities._resolve_targets(7, "pit_hag", [2])
	choose(g, "role", "oracle")
	check(g.roles[2] == "oracle" and g.sides[2] == "good", "Ведьма меняет роль без изменения стороны")
	g.abilities._resolve_targets(7, "pit_hag", [2])
	choose(g, "role", "no_dashii")
	check(g.roles[2] == "no_dashii" and g.sides[2] == "good" and g.abilities.arbitrary_deaths, "Создан добрый демон, открыт особый выбор смертей")
	check(choose(g, "target", -1), "Рассказчик может закончить особую ночь без смертей")
	check(g.alive[1] and g.alive[8], "Обычные атаки не навязываются произвольной ночи")

func _poison_and_death() -> void:
	var g := fixture(["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "no_dashii"])
	check(not g.abilities.healthy(1) and not g.abilities.healthy(5) and g.abilities.healthy(2), "Но Даши пропускает изгоев и приспешников")
	g.alive[5] = false
	check(not g.abilities.healthy(5) and g.abilities.healthy(4), "Мёртвый горожанин всё ещё ближайший для Но Даши")
	g.roles[5] = "barber"
	check(not g.abilities.healthy(4), "После смены типа ближайший отравленный горожанин пересчитан")
	g.alive[8] = false
	check(g.abilities.healthy(1), "Смерть Но Даши прекращает яд")
	g = fixture()
	g.abilities._resolve_targets(8, "fang_gu", [6])
	check(g.roles[6] == "fang_gu" and g.sides[6] == "evil" and not g.alive[8] and g.alive[6], "Фан Гу передал роль изгою вместо его смерти")
	check(g.abilities.fang_used and g.winner.is_empty(), "Передача не завершила игру и потрачена один раз")
	g.roles[1] = "mutant"
	g.abilities._resolve_targets(6, "fang_gu", [1])
	check(not g.alive[1] and g.roles[1] == "mutant", "Следующий изгой погибает без второй передачи")
	g = fixture()
	g.alive[6] = false
	g.abilities._resolve_targets(8, "fang_gu", [6])
	check(g.winner == "good" and not g.alive[6], "Фан Гу, выбравший мёртвого изгоя, оставляет всех демонов мёртвыми")
	g = fixture(["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "vigormortis"])
	g.abilities._resolve_targets(8, "vigormortis", [7])
	check(not g.alive[7] and g.abilities.active(7, "witch"), "Приспешник, убитый Вигормортисом, сохраняет способность")
	check(choose(g, "target", 5), "Выбран ближайший горожанин для яда Вигормортиса")
	check(not g.abilities.healthy(5), "Яд Вигормортиса применён")
	g.abilities._kill(8, -1, "pit_hag")
	check(g.abilities.healthy(5) and not g.abilities.active(7, "witch"), "Смерть Вигормортиса снимает оба эффекта")
	g = fixture()
	g.abilities._kill(6, 8, "demon")
	g.abilities._advance()
	check(choose(g, "target", 2), "Милашка: выбор опьяняемого")
	check(not g.abilities.healthy(2) and not g.alive[6], "Опьянение Милашки действует после её смерти")
	g = fixture(["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "sage", "witch", "fang_gu"])
	g.abilities._kill(6, 8, "demon")
	g.abilities._wake(6, "sage")
	check(g.requests.has(0), "Мудрец получает выбор допустимой информации рассказчиком")
	check(respond(g) and g.private_log[6].back().contains("демон"), "Мудрецу выдана информация после смерти")
	g = fixture(["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "klutz", "witch", "fang_gu"])
	g.abilities._kill(6, 8, "demon")
	g.abilities._on_dawn()
	g.abilities._advance()
	check(choose(g, "target", 7), "Растяпа выбрал злого игрока после объявления смерти")
	check(g.winner == "evil", "Растяпа автоматически проиграл своей команде")

func _minions() -> void:
	var g := fixture()
	g.phase = "nominations"
	g.abilities._resolve_targets(7, "witch", [2])
	check(act(g, 2, "nominate", {"target": 3}) and g.alive[2], "Проклятый номинировал, смерть ждёт показа")
	g.tick(1.0)
	check(not g.alive[2] and g.nominee == 3 and g.phase == "defense", "Проклятие убивает, но сохраняет номинацию")
	g = fixture()
	for s: int in [1, 2, 3, 4, 5]:
		g.alive[s] = false
	g.phase = "nominations"
	g.status[6]["witch_source"] = 7
	check(act(g, 6, "nominate", {"target": 8}) and g.event.is_empty(), "Ведьма не действует при трёх живых")
	g = fixture(["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "cerenovus", "fang_gu"])
	var before := g.get_view(-1)
	g.abilities._resolve_targets(7, "cerenovus", [2])
	choose(g, "role", "artist")
	check(g.roles[2] == "dreamer" and g.status[2].mad_role == "artist", "Цереновус требует притворяться, не меняя настоящую роль")
	check(g.get_view(-1) == before and g.private_log[2].back().contains("Цереновус"), "Требование безумия адресное")
	g.phase = "discussion"
	check(act(g, 0, "madness_execution", {"target": 2}), "Рассказчик применяет предусмотренную казнь за нарушение")
	g.tick(1.0)
	check(not g.alive[2] and g.executed == 2 and g.phase == "dusk", "Казнь за безумие исполняется системой и закрывает день")
	g = fixture(["clockmaker", "dreamer", "snake_charmer", "mathematician", "seamstress", "mutant", "evil_twin", "fang_gu"])
	g.abilities._wake(7, "evil_twin")
	choose(g, "target", 1)
	check(g.private_log[1].back().contains("близнец") and g.private_log[7].back().contains("Часовщик"), "Близнецы узнали друг друга и роли")
	check(g.private_log[2].is_empty(), "Остальным близнецы не раскрыты")
	g.phase = "discussion"
	g.abilities.execute(8)
	check(g.winner.is_empty(), "Демон погиб, но оба близнеца живы — добро ещё не победило")
	g.phase = "discussion"
	g.abilities.execute(1)
	check(g.winner == "evil", "Казнь доброго близнеца приносит победу злу даже после смерти демона")

func _information() -> void:
	var g := fixture()
	check(g.abilities._clock_distances() == [1], "Часовщик считает кратчайшее расстояние по кругу")
	g.abilities._dreamer(2, 8)
	for option: Dictionary in g.requests[0].options:
		check(not option.abnormal and option.text.contains("Фан Гу"), "Здоровый Сновидец всегда получает настоящую роль среди пары")
	respond(g)
	g.abilities._resolve_targets(5, "seam_first", [1])
	check(choose(g, "target", 8), "Швея выбрала вторую цель")
	check(g.status[5].once and g.private_log[5].back().ends_with("нет."), "Швея узнаёт разные стороны и тратит способность")
	g = fixture(["oracle", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "fang_gu"])
	g.alive[7] = false
	g.abilities._wake(1, "oracle")
	check(g.private_log[1].back().contains("1"), "Оракул считает мёртвых злых")
	g.abilities.abnormal = {2: true, 3: true, 4: true}
	g.abilities._wake(4, "mathematician")
	check(g.private_log[4].back().contains("2"), "Математик считает персонажей, исключая себя")
	g.abilities.on_vote(8)
	g.abilities._boolean_information(1, [not g.abilities.demon_votes.is_empty()], "Демон голосовал: %s.")
	check(g.private_log[1].back().ends_with("да."), "Голос демона записан для Цветочницы")
	g.abilities.on_nominate(7, 1)
	check(g.abilities.minion_nominated, "Номинация приспешника записана для Глашатая")
	g = fixture(["oracle", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "vortox"])
	g.alive[7] = false
	g.abilities._wake(1, "oracle")
	for option: Dictionary in g.requests[0].options:
		check(option.abnormal, "Вортокс исключает истинное число Оракула")
	respond(g)
	check(g.abilities.abnormal.has(1), "Ложная информация отмечена для Математика")
	g.abilities._add_drunk(1, 8, 1)
	g.abilities._wake(1, "oracle")
	for option: Dictionary in g.requests[0].options:
		check(option.abnormal, "Вортокс требует ложь даже от пьяного доброго игрока")
	respond(g)
	g.phase = "dusk"
	g.executed = -1
	g.abilities.dusk()
	check(g.winner == "evil", "Вортокс побеждает при отсутствии казни")

func _private_day() -> void:
	var g := fixture(["artist", "savant", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "vortox"])
	g.phase = "discussion"
	g.day = 1
	var before := g.get_view(-1)
	check(g.action(1, "artist", {"text": "Место 8 — демон?"}), "Художник задал приватный вопрос")
	check(g.get_view(-1) == before, "Запрос Художника не меняет публичную ревизию/фазу")
	check(act(g, 0, "open_nominations"), "Приватный вопрос не замораживает публичную игру")
	choose(g, "value", 1)
	check(choose(g, "value", 0), "Вортокс: при истинном да выбран ложный ответ нет")
	check(g.status[1].once and g.private_log[1].back().contains("Нет"), "Ответ Художнику доставлен приватно, способность потрачена")
	check(not g.action(1, "artist", {"text": "Ещё вопрос"}), "Повторное использование Художника отклонено")
	check(g.action(2, "savant", {}), "Учёный запросил дневные сведения")
	for option: Dictionary in g.requests[0].options:
		check(not option.truth, "При Вортоксе первое утверждение Учёного ложно")
	respond(g)
	for option: Dictionary in g.requests[0].options:
		check(not option.truth, "При Вортоксе второе утверждение Учёного ложно")
	respond(g)
	check(g.private_log[2].back().contains("Учёный") and g.private_log[3].is_empty(), "Пара утверждений выдана только Учёному")
	check(not g.action(2, "savant", {}), "Учёный получает одну пару за день")
	g = fixture(["juggler", "dreamer", "snake_charmer", "mathematician", "seamstress", "sweetheart", "witch", "fang_gu"])
	g.phase = "discussion"
	g.day = 1
	check(act(g, 1, "juggle", {"guesses": [{"target": 8, "role": "fang_gu"}, {"target": 7, "role": "witch"}]}), "Жонглёр публично сделал два предположения")
	check(g.status[1].juggler_correct == 2 and not JSON.stringify(g.get_view(-1)).contains("juggler_correct"), "Верность предположений пока скрыта")
	g.phase = "night"
	g.abilities.night_no = 2
	g.abilities._wake(1, "juggler")
	check(g.private_log[1].back().contains("2"), "Следующей ночью Жонглёр узнал результат")
	var size: int = g.private_log[1].size()
	g.abilities.night_no = 3
	g.abilities._wake(1, "juggler")
	check(g.private_log[1].size() == size, "Результат Жонглёра не повторяется каждую ночь")

func _night() -> void:
	var g := fixture()
	g.abilities.started = false
	g.abilities.night_no = 0
	g.phase = "first_night"
	check(act(g, 0, "begin_night"), "Запущена первая ночь SV")
	for step in 90:
		if g.phase != "night":
			break
		var before := g.get_view(-1)
		check(respond(g), "Допустимый ответ очереди SV")
		if g.phase == "night":
			check(before == g.get_view(-1), "Приватные шаги SV не меняют публичный снимок")
	check(g.phase == "discussion" and g.day == 1, "Первая ночь SV завершилась")
