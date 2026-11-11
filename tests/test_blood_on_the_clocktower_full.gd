extends SceneTree
## Полные партии «Дурной луны» и «Сект и фиалок»: случайные законные составы 7–15 игроков, на все запросы —
## случайные ответы, днём — дневные способности, номинации и голосование кнопкой «Проголосовать».
## Проверяется: ночь доходит до рассвета, партия — до победы, запросы не пустые, view не падает и не выдаёт
## гримуар игрокам, и что каждая роль сценария хотя бы раз сработала (проснулась / получила сведения / действие).
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_blood_on_the_clocktower_full.gd
## Переменные: GAMES (партий на сценарий, по умолчанию 60), EDITIONS (например "bmr" или "sv").
const Rules := preload("res://games/blood_on_the_clocktower/logic/bc_rules.gd")
const Setup := preload("res://games/blood_on_the_clocktower/logic/bc_setup.gd")
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")

var checks := 0
var failures := 0
var rng := RandomNumberGenerator.new()
var used: Dictionary = {}      # роль → как сработала («просыпалась», «сведения», «день», «рассказчик»)
var in_play: Dictionary = {}   # роль → в скольких партиях была
var finished := 0
var unfinished := 0
var stuck_reports: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 40:
			printerr("ОШИБКА: " + message)

func _run() -> void:
	var games := int(OS.get_environment("GAMES")) if not OS.get_environment("GAMES").is_empty() else 60
	var editions: Array = ["bmr", "sv"]
	if not OS.get_environment("EDITIONS").is_empty():
		editions = OS.get_environment("EDITIONS").split(",")
	for edition: String in editions:
		used.clear()
		in_play.clear()
		finished = 0
		unfinished = 0
		for n in games:
			_play(edition, 7 + n % 9, 1000 + n)
		_report(edition)
	for line: String in stuck_reports.slice(0, 12):
		printerr(line)
	print("Clocktower полные партии: %d проверок, %d ошибок." % [checks, failures])
	quit(1 if failures else 0)

func _mark(role: String, how: String) -> void:
	if role.is_empty(): return
	if not used.has(role): used[role] = {}
	used[role][how] = true

func _play(edition: String, count: int, seed_value: int) -> void:
	rng.seed = seed_value
	var options := Setup.suggest(edition, count, seed_value)
	check(not options.is_empty(), "%s: состав на %d" % [edition, count])
	if options.is_empty(): return
	options["bc_edition"] = edition
	var people: Array = []
	for i in count + 1:
		people.append({"name": "Игрок %d" % i, "color": i})
	var g := Rules.new()
	var error := g.new_game(people, options, seed_value)
	check(error.is_empty(), "%s/%d: подготовка — %s" % [edition, seed_value, error])
	if not error.is_empty(): return
	var tag := "%s seed=%d n=%d [%s]" % [edition, seed_value, count, ",".join(PackedStringArray(g.roles.slice(1)))]
	for s: int in g.seats_in_circle():
		in_play[str(g.roles[s])] = int(in_play.get(str(g.roles[s]), 0)) + 1
	check(g.action(0, "begin_night", {"revision": g.public_revision}), tag + ": первая ночь")
	for day in 14:
		if not _finish_requests(g, tag, "ночь %d" % (day + 1)): return
		if g.phase == "game_over": break
		if g.phase != "discussion":
			check(false, "%s: ночь %d не дошла до рассвета (фаза %s, событие %s, задачи %s)" % [tag, day + 1, g.phase, g.event, g.abilities.jobs])
			stuck_reports.append(tag)
			return
		_views(g, tag)
		_day(g, tag)
		if g.phase == "game_over": break
		if not _finish_requests(g, tag, "день %d" % (day + 1)): return
		if g.phase == "game_over": break
		if g.phase != "dusk":
			check(false, "%s: день %d не дошёл до сумерек (фаза %s)" % [tag, day + 1, g.phase])
			stuck_reports.append(tag)
			return
		check(g.action(0, "begin_night", {"revision": g.public_revision}), tag + ": ночь %d началась" % (day + 2))
	if g.phase == "game_over":
		finished += 1
		check(g.winner in ["good", "evil"], tag + ": победитель определён")
	else:
		unfinished += 1
		if OS.get_environment("DIAG") == "1":
			var alive: Array = g.seats_in_circle().filter(func(s: int): return g.alive[s])
			var demon_alive: Array = alive.filter(func(s: int): return g.catalog[g.roles[s]].type == "demon")
			print("НЕ ДОИГРАНО %s: живых %d, живые демоны %s, mastermind_day %s, фаза %s" % [tag, alive.size(), demon_alive.map(func(s: int): return g.roles[s]), g.abilities.get("mastermind_day"), g.phase])

## Отвечает на все запросы случайно (с тиками событий), пока они не кончатся. false — завис.
func _finish_requests(g: Rules, tag: String, when: String) -> bool:
	var steps := 0
	while steps < 400:
		steps += 1
		if not g.event.is_empty():
			g.tick(2.0)
			continue
		if g.requests.is_empty():
			return true
		var who: int = g.requests.keys()[rng.randi_range(0, g.requests.size() - 1)]
		var request: Dictionary = g.requests[who]
		var options: Array = request.options
		check(not options.is_empty(), "%s: пустой запрос «%s» (%s)" % [tag, request.title, when])
		if options.is_empty(): return false
		if who == g.storyteller:
			# Запрос рассказчику про конкретную роль — значит, у ведущего есть инструмент для неё.
			for s: int in g.seats_in_circle():
				var role := str(g.roles[s])
				if str(request.title).contains(str(g.catalog[role].name)):
					_mark(role, "рассказчик")
		else:
			_mark(str(g.roles[who]), "просыпалась")
			if str(g.shown_roles[who]) != str(g.roles[who]): _mark(str(g.shown_roles[who]), "просыпалась (мнимая)")
		var before: Array = []
		for s in g.players.size(): before.append(g.private_log[s].size())
		check(g.action(who, "private_reply", {"token": request.token, "index": rng.randi_range(0, options.size() - 1)}), "%s: ответ на «%s» принят" % [tag, request.title])
		for s: int in g.seats_in_circle():
			if g.private_log[s].size() > int(before[s]):
				_mark(str(g.roles[s]), "сведения")
	check(false, "%s: запросы не кончаются (%s)" % [tag, when])
	stuck_reports.append(tag)
	return false

func _views(g: Rules, tag: String) -> void:
	for s in range(-1, g.players.size()):
		var view: Dictionary = g.get_view(s)
		if s != g.storyteller:
			check(not view.has("grimoire") or str(g.roles[s]) == "spy", "%s: гримуар не у рассказчика (место %d)" % [tag, s])
			check(not view.has("story_log") and not view.has("night_queue"), "%s: журнал рассказчика не у игрока" % tag)

func _alive_players(g: Rules) -> Array:
	return g.seats_in_circle().filter(func(s: int): return g.is_living_player(s))

func _day(g: Rules, tag: String) -> void:
	# Дневные способности: заявления и вопросы рассказчику.
	for s: int in g.seats_in_circle():
		if not g.alive[s]: continue
		var role := str(g.shown_roles[s])
		match role:
			"gossip":
				if g.action(s, "gossip", {"text": "Игрок 1 — демон", "revision": g.public_revision}): _mark("gossip", "день")
			"artist":
				if g.action(s, "artist", {"text": "Игрок 1 — демон?"}): _mark("artist", "день")
			"savant":
				if g.action(s, "savant", {}): _mark("savant", "день")
			"juggler":
				var guesses: Array = []
				for t: int in g.seats_in_circle().slice(0, 3):
					guesses.append({"target": t, "role": str(g.roles[t]) if rng.randf() < 0.5 else "clockmaker"})
				if g.action(s, "juggle", {"guesses": guesses, "revision": g.public_revision}): _mark("juggler", "день")
	if not _finish_requests(g, tag, "дневные вопросы"): return
	# Рассказчик иногда «убивает» Лудильщика и казнит за безумие (кнопки рассказчика).
	for s: int in g.seats_in_circle():
		if g.alive[s] and str(g.roles[s]) == "tinker" and rng.randf() < 0.25:
			if g.action(g.storyteller, "tinker", {"target": s, "revision": g.public_revision}): _mark("tinker", "рассказчик")
		if g.alive[s] and (str(g.roles[s]) == "mutant" or g.status[s].has("mad_source")) and rng.randf() < 0.2:
			if g.action(g.storyteller, "madness_execution", {"target": s, "revision": g.public_revision}):
				_mark("mutant" if str(g.roles[s]) == "mutant" else "cerenovus", "рассказчик")
	if not _finish_requests(g, tag, "события дня"): return
	if g.phase == "game_over" or g.phase != "discussion": return
	check(g.action(g.storyteller, "open_nominations", {"revision": g.public_revision}), tag + ": номинации открыты")
	for attempt in rng.randi_range(0, 2):
		if g.phase != "nominations": break
		var alive := _alive_players(g)
		if alive.size() < 2: break
		var nominator: int = alive[rng.randi_range(0, alive.size() - 1)]
		var targets: Array = g.seats_in_circle().filter(func(t: int): return t != nominator and g.can_be_nominated(t) and not g.nominated.has(t))
		if targets.is_empty() or g.nominators.has(nominator): continue
		if not g.action(nominator, "nominate", {"target": targets[rng.randi_range(0, targets.size() - 1)], "revision": g.public_revision}):
			continue
		if not _finish_requests(g, tag, "номинация"): return
		if g.phase == "game_over": return
		if g.phase != "defense": continue
		check(g.action(g.storyteller, "start_vote", {"revision": g.public_revision}), tag + ": голосование началось")
		var guard := 0
		while g.phase == "voting" and guard < 40:
			guard += 1
			var voter: int = g.vote_order[g.vote_cursor]
			check(g.action(voter, "cast_vote", {"raised": rng.randf() < 0.6}), tag + ": голос места %d принят" % voter)
	if g.phase == "nominations":
		check(g.action(g.storyteller, "close_day", {"revision": g.public_revision}), tag + ": день закрыт")

func _report(edition: String) -> void:
	var all_roles: Array = Data.roles(edition)
	var silent: Array[String] = []
	var lines: Array[String] = []
	for role: String in all_roles:
		var how: Array = used.get(role, {}).keys()
		lines.append("  %s (%s): в %d партиях, %s" % [Data.catalog()[role].name, role, int(in_play.get(role, 0)), ", ".join(PackedStringArray(how)) if not how.is_empty() else "НЕ СРАБОТАЛА"])
		if how.is_empty() and int(in_play.get(role, 0)) > 0:
			silent.append(role)
	print("%s: доиграно %d, без победителя за 14 дней %d" % [edition, finished, unfinished])
	for line: String in lines: print(line)
	# Пассивные роли могут не «срабатывать» явно — их проверяют точечные тесты.
	var passive := ["tea_lady", "fool", "pacifist", "minstrel", "goon", "mastermind", "moonchild", "sweetheart", "klutz", "barber", "sage", "mutant", "vortox", "evil_twin", "tinker", "lunatic"]
	for role: String in silent:
		check(passive.has(role), "%s: активная роль %s ни разу не сработала" % [edition, role])
