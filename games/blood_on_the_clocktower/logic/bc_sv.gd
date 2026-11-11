extends "res://games/blood_on_the_clocktower/logic/bc_bmr.gd"
## «Секты и фиалки»: смены ролей, регистрации информации и решения рассказчика.

const FIRST_SV := ["philosopher", "snake_charmer", "evil_twin", "witch", "cerenovus", "clockmaker", "dreamer", "seamstress", "mathematician"]
const OTHER_SV := ["philosopher", "snake_charmer", "witch", "cerenovus", "pit_hag", "fang_gu", "vigormortis", "no_dashii", "vortox", "barber", "sage", "dreamer", "flowergirl", "town_crier", "oracle", "seamstress", "juggler", "mathematician"]
var fang_used := false
var arbitrary_deaths := false
var abnormal: Dictionary = {}
var demon_votes: Dictionary = {}
var minion_nominated := false
var resolving_twin_execution := false

func supports() -> bool:
	return g.edition == "sv"

func _order() -> Array:
	return FIRST_SV if night_no == 1 else OTHER_SV

func _initial_jobs() -> Array:
	return [{"op": "evil_info"}] if night_no == 1 else []

func _prepare_night() -> void:
	super._prepare_night()
	arbitrary_deaths = false
	for s: int in g.seats_in_circle():
		g.status[s].erase("witch_source")
		g.status[s].erase("mad_source")
		g.status[s].erase("mad_role")

func _nearest_townsfolk(center: int) -> Array:
	var circle: Array = g.seats_in_circle()
	var index := circle.find(center)
	var result: Array = []
	for direction: int in [-1, 1]:
		for distance in range(1, circle.size()):
			var target: int = circle[posmod(index + direction * distance, circle.size())]
			if g.catalog[g.roles[target]].type == "townsfolk":
				if not result.has(target):
					result.append(target)
				break
	return result

func healthy(seat: int, trail: Array = []) -> bool:
	if trail.has(seat):
		return true
	if not super.healthy(seat, trail) or bool(g.status[seat].get("snake_poison", false)):
		return false
	var next := trail.duplicate()
	next.append(seat)
	for source: int in g.seats_in_circle():
		if g.roles[source] == "no_dashii" and g.alive[source] and _nearest_townsfolk(source).has(seat) and healthy(source, next):
			return false
	for effect: Dictionary in g.status[seat].get("vig_poison", []):
		var source := int(effect.source)
		var minion := int(effect.minion)
		if g.alive[source] and g.roles[source] == "vigormortis" and g.catalog[g.roles[minion]].type == "minion" and healthy(source, next):
			return false
	for source: int in g.status[seat].get("sweet_sources", []):
		if g.roles[source] == "sweetheart" and (source == seat or healthy(source, next)):
			return false
	return true

func active(seat: int, role: String) -> bool:
	var source := int(g.status[seat].get("vig_source", -1))
	var retained: bool = source >= 0 and g.alive[source] and g.roles[source] == "vigormortis" and healthy(source) and g.catalog[g.roles[seat]].type == "minion"
	return (bool(g.alive[seat]) or retained) and str(g.roles[seat]) == role and healthy(seat)

func _vortox(actor: int) -> bool:
	if g.sides[actor] != "good":
		return false
	for s: int in g.seats_in_circle():
		if active(s, "vortox"):
			return true
	return false

func _allowed_information(actor: int, truthful: bool) -> bool:
	if _vortox(actor):
		return not truthful
	return truthful or not healthy(actor)

func _numeric(actor: int, truthful: Array, maximum: int, template: String) -> void:
	var options: Array = []
	for value in range(maximum + 1):
		var correct := truthful.has(value)
		if _allowed_information(actor, correct):
			var text := template % value
			options.append({"label": text, "text": text, "abnormal": not correct})
	_information(actor, options)

func _boolean_information(actor: int, truthful: Array, template: String) -> void:
	var options: Array = []
	for value: bool in [false, true]:
		var correct := truthful.has(value)
		if _allowed_information(actor, correct):
			var text := template % ("да" if value else "нет")
			options.append({"label": text, "text": text, "abnormal": not correct})
	_information(actor, options)

func _information(actor: int, options: Array) -> void:
	if options.size() == 1:
		_deliver(actor, options[0])
	elif not options.is_empty():
		_choice(g.storyteller, "Информация для %s · %s" % [g.players[actor].name, g.catalog[g.shown_roles[actor]].name], options,
			{"op": "sv_information", "actor": actor}, _information_hint(actor))

func _information_hint(actor: int) -> String:
	if _vortox(actor):
		return "В игре Вортокс: добрый игрок получает только ложную информацию — все варианты ложные."
	return super._information_hint(actor)

func _deliver(actor: int, selected: Dictionary) -> void:
	g.add_private(actor, str(selected.text))
	if bool(selected.get("abnormal", false)):
		abnormal[actor] = true

func _sv_roles(actor: int, operation: String, context: Dictionary = {}, good_only: bool = false, optional: bool = false) -> void:
	var options: Array = []
	if optional:
		options.append({"label": "Не использовать сейчас", "role": ""})
	for id: String in g.catalog:
		if g.catalog[id].edition == "sv" and (not good_only or g.catalog[id].side == "good"):
			options.append({"label": str(g.catalog[id].name), "role": id})
	var request := context.duplicate(true)
	request["op"] = operation
	request["actor"] = actor
	_choice(actor, "Выберите роль", options, request)

func _wake(actor: int, id: String) -> void:
	if g.roles[actor] != id:
		return
	if id == "sage":
		var killer := int(g.status[actor].get("sage_killer", -1))
		if killer >= 0:
			g.status[actor].erase("sage_killer")
			_sage_information(actor, killer)
		return
	if id == "barber":
		if bool(g.status[actor].get("barber_dead", false)):
			g.status[actor].erase("barber_dead")
			for s: int in g.seats_in_circle():
				if g.alive[s] and g.catalog[g.roles[s]].type == "demon":
					_ask_targets(s, "Парикмахер: выберите первую роль для обмена", "barber_first", false, true, _other_demons(s))
					break
		return
	if not g.alive[actor] and not active(actor, id):
		return
	if id in ["philosopher", "seamstress"] and bool(g.status[actor].get("once", false)):
		return
	match id:
		"philosopher":
			_sv_roles(actor, "philosopher", {}, true, true)
		"snake_charmer":
			_ask_targets(actor, "Заклинатель змей: выберите живого игрока", id, true)
		"witch":
			if g.alive_count() > 3:
				_ask_targets(actor, "Ведьма: выберите игрока", id)
		"cerenovus", "pit_hag", "dreamer":
			_ask_targets(actor, "Выберите игрока", id, false, false, [actor] if id == "dreamer" else [])
		"evil_twin":
			if not g.status[actor].has("twin"):
				var options: Array = []
				for s: int in g.seats_in_circle():
					if g.sides[s] != g.sides[actor]:
						options.append(_target_option(s))
				_choice(g.storyteller, "Выберите близнеца противоположной стороны", options, {"op": "twin", "actor": actor})
		"clockmaker":
			_numeric(actor, _clock_distances(), g.seats_in_circle().size() - 1, "Расстояние от демона до ближайшего приспешника: %d.")
		"mathematician":
			var total := abnormal.size() - (1 if abnormal.has(actor) else 0)
			_mathematician(actor, total)
		"flowergirl":
			_boolean_information(actor, [not demon_votes.is_empty()], "Демон голосовал сегодня: %s.")
		"town_crier":
			_boolean_information(actor, [minion_nominated], "Приспешник номинировал сегодня: %s.")
		"oracle":
			var total := 0
			for s: int in g.seats_in_circle():
				if not g.alive[s] and g.sides[s] == "evil":
					total += 1
			_numeric(actor, [total], g.seats_in_circle().size(), "Мёртвых злых игроков: %d.")
		"seamstress":
			_ask_targets(actor, "Швея: первая цель или отказ", "seam_first", false, true, [actor])
		"juggler":
			if g.status[actor].has("juggler_correct") and int(g.status[actor].get("juggler_night", -1)) == night_no:
				_numeric(actor, [int(g.status[actor].juggler_correct)], 5, "Верных предположений Жонглёра: %d.")
		"fang_gu", "vigormortis", "no_dashii", "vortox":
			_ask_targets(actor, "Выберите жертву", id)

func _resolve_targets(actor: int, id: String, targets: Array) -> void:
	var target := int(targets[0])
	if target < 0:
		return
	match id:
		"snake_charmer":
			if g.catalog[g.roles[target]].type == "demon":
				if active(actor, id):
					var demon_role := str(g.roles[target])
					_change_role(actor, demon_role, "evil")
					_change_role(target, "snake_charmer", "good")
					g.status[target]["snake_poison"] = true
				else:
					abnormal[actor] = true
		"witch":
			if active(actor, id):
				g.status[target]["witch_source"] = actor
			else:
				abnormal[actor] = true
		"cerenovus", "pit_hag":
			_sv_roles(actor, id, {"target": target}, id == "cerenovus")
		"dreamer":
			_dreamer(actor, target)
		"seam_first":
			g.status[actor]["seam_first"] = target
			_ask_targets(actor, "Швея: вторая цель", "seam_second", false, false, [actor, target])
		"seam_second":
			g.status[actor]["once"] = true
			var first := int(g.status[actor].seam_first)
			_boolean_information(actor, [g.sides[first] == g.sides[target]], "Выбранные игроки одной стороны: %s.")
		"barber_first":
			g.status[actor]["barber_first"] = target
			_ask_targets(actor, "Парикмахер: вторая роль", "barber_second", false, false, [target] + _other_demons(actor))
		"barber_second":
			var first := int(g.status[actor].barber_first)
			var old_role := str(g.roles[first])
			_change_role(first, str(g.roles[target]))
			_change_role(target, old_role)
		"fang_gu", "vigormortis", "no_dashii", "vortox":
			if not active(actor, id):
				if g.alive[target]:
					abnormal[actor] = true
				return
			if arbitrary_deaths:
				return
			if id == "fang_gu" and not fang_used and g.catalog[g.roles[target]].type == "outsider":
				fang_used = true
				_change_role(target, "fang_gu", "evil")
				_kill(actor, actor, "demon")
			else:
				_kill(target, actor, "demon")

func _receive_extra(context: Dictionary, selected: Variant) -> void:
	var actor := int(context.get("actor", -1))
	match str(context.op):
		"sv_information":
			_deliver(actor, selected)
		"philosopher":
			var id := str(selected.role)
			if id.is_empty():
				return
			g.status[actor]["once"] = true
			if not active(actor, "philosopher"):
				abnormal[actor] = true
				return
			var existing: Array = []
			for s: int in g.seats_in_circle():
				if s != actor and g.roles[s] == id:
					existing.append(s)
			if id != "philosopher":
				_change_role(actor, id)
			for target: int in existing:
				_add_drunk(target, actor, 1000000)
		"cerenovus":
			if active(actor, "cerenovus"):
				var target := int(context.target)
				g.status[target]["mad_source"] = actor
				g.status[target]["mad_role"] = selected.role
				g.add_private(target, "Цереновус требует убеждать остальных, что вы — %s, до следующих сумерек. Иначе рассказчик может вас казнить." % g.catalog[selected.role].name)
			else:
				abnormal[actor] = true
		"pit_hag":
			var id := str(selected.role)
			if g.roles.has(id):
				return
			if active(actor, "pit_hag"):
				_change_role(int(context.target), id)
				if g.catalog[id].type == "demon":
					arbitrary_deaths = true
					_insert_arbitrary()
			else:
				abnormal[actor] = true
		"twin":
			var target := int(selected.target)
			g.status[actor]["twin"] = target
			g.add_private(actor, "Ваш близнец — %s, его роль — %s." % [g.players[target].name, g.catalog[g.roles[target]].name])
			g.add_private(target, "Ваш близнец — %s, его роль — %s." % [g.players[actor].name, g.catalog[g.roles[actor]].name])
		"sweetheart":
			var target := int(selected.target)
			if not g.status[target].has("sweet_sources"):
				g.status[target]["sweet_sources"] = []
			g.status[target].sweet_sources.append(actor)
		"vig_poison":
			var target := int(selected.target)
			if not g.status[target].has("vig_poison"):
				g.status[target]["vig_poison"] = []
			g.status[target].vig_poison.append({"source": actor, "minion": int(context.minion)})
		"arbitrary":
			var target := int(selected.target)
			if target >= 0:
				_kill(target, -1, "pit_hag")
				if g.phase != "game_over":
					_ask_arbitrary()
		"klutz":
			var target := int(selected.target)
			g.public_log.append("%s заявляет выбор Растяпы: %s." % [g.players[actor].name, g.players[target].name])
			g.public_revision += 1
			if bool(g.status[actor].get("klutz_real", false)) and healthy(actor) and g.sides[target] == "evil":
				_win("evil" if g.sides[actor] == "good" else "good")
		"artist_truth":
			var truth := int(selected.value)
			if truth == 2:
				g.status[actor].erase("artist_waiting")
				g.add_private(actor, "Переформулируйте вопрос. Способность не потрачена.")
				return
			var options: Array = []
			for value: int in [0, 1, -1]:
				if _allowed_information(actor, value == truth):
					options.append({"label": _answer(value), "value": value})
			_choice(g.storyteller, "Ответ Художнику: " + str(context.question), options,
				{"op": "artist_answer", "actor": actor, "truth": truth, "question": context.question, "nonblocking": true})
		"artist_answer":
			g.status[actor]["once"] = true
			g.status[actor].erase("artist_waiting")
			g.add_private(actor, "Вопрос: %s\nОтвет: %s." % [str(context.question), _answer(int(selected.value))])
			if int(selected.value) != int(context.truth):
				abnormal[actor] = true
		"savant_first":
			_savant_second(actor, selected)
		"savant_second":
			var first: Dictionary = context.first
			var statements: Array[String] = [str(first.text), str(selected.text)]
			if g.rng.randi_range(0, 1) == 1:
				statements.reverse()
			g.add_private(actor, "Учёный:\n• %s\n• %s" % [statements[0], statements[1]])
			if int(first.truth) + int(selected.truth) != 1:
				abnormal[actor] = true
		_:
			super._receive_extra(context, selected)

func _change_role(target: int, id: String, side: String = "") -> void:
	g.roles[target] = id
	g.shown_roles[target] = id
	if not side.is_empty():
		g.sides[target] = side
	for key: String in ["once", "artist_waiting", "savant_day", "juggler_correct", "juggler_night", "twin", "klutz_notify", "klutz_real", "sage_killer"]:
		g.status[target].erase(key)
	if id == "juggler":
		g.status[target]["juggler_first_day"] = int(g.day) + (1 if g.phase == "night" else 0)
	g.add_private(target, "Теперь ваша роль — %s. Ваша сторона — %s." % [g.catalog[id].name, "добро" if g.sides[target] == "good" else "зло"])
	if id in ["clockmaker", "evil_twin"] and g.alive[target]:
		if g.phase == "night":
			if processed_slots.has(id) or not _order().has(id):
				jobs.push_front({"op": "wake", "actor": target, "role": id})
		else:
			g.status[target]["start_pending"] = true

## Парикмахер: «2 players (not another Demon)» — другие демоны недоступны, себя демон выбрать может.
func _other_demons(demon: int) -> Array:
	var result: Array = []
	for s: int in g.seats_in_circle():
		if s != demon and g.catalog[g.roles[s]].type == "demon":
			result.append(s)
	return result

## Математик: система считает нарушенные способности приблизительно (видит не все случаи),
## поэтому рассказчик всегда выбирает число сам; подсчёт системы — первым и в подсказке.
func _mathematician(actor: int, counted: int) -> void:
	var options: Array = []
	var template := "Способностей с нарушенным действием: %d."
	var maximum: int = g.seats_in_circle().size() - 1
	var order: Array = [counted]
	for value in range(maximum + 1):
		if value != counted: order.append(value)
	for value: int in order:
		var correct := value == counted
		if _vortox(actor) and correct:
			continue
		var text := template % value
		options.append({"label": text + (" — по подсчёту системы" if correct else ""), "text": text, "abnormal": not correct})
	var reason := super._information_hint(actor) if not healthy(actor) else ("В игре Вортокс: число должно быть ложным." if _vortox(actor) else "")
	var hint := "Система насчитала %d (сегодня: яд, опьянение, Вортокс и т. п.). Если знаете больше — выберите своё число." % counted
	_choice(g.storyteller, "Информация для %s · Математик" % g.players[actor].name, options, {"op": "sv_information", "actor": actor},
		hint + ("\n" + reason if not reason.is_empty() else ""))

func _clock_distances() -> Array:
	var circle: Array = g.seats_in_circle()
	var values: Array = []
	for a in circle.size():
		if g.catalog[g.roles[int(circle[a])]].type != "demon":
			continue
		var nearest := circle.size()
		for b in circle.size():
			if g.catalog[g.roles[int(circle[b])]].type == "minion":
				nearest = mini(nearest, mini(posmod(a - b, circle.size()), posmod(b - a, circle.size())))
		if not values.has(nearest):
			values.append(nearest)
	return values

func _dreamer(actor: int, target: int) -> void:
	var options: Array = []
	for good: String in g.catalog:
		if g.catalog[good].edition != "sv" or g.catalog[good].side != "good":
			continue
		for evil: String in g.catalog:
			if g.catalog[evil].edition != "sv" or g.catalog[evil].side != "evil":
				continue
			var truthful: bool = g.roles[target] in [good, evil]
			if _allowed_information(actor, truthful):
				var text := "%s — %s или %s." % [g.players[target].name, g.catalog[good].name, g.catalog[evil].name]
				options.append({"label": text, "text": text, "abnormal": not truthful})
	_information(actor, options)

func _sage_information(actor: int, killer: int) -> void:
	var options: Array = []
	var circle: Array = g.seats_in_circle()
	for a in circle.size():
		for b in range(a + 1, circle.size()):
			var left: int = circle[a]
			var right: int = circle[b]
			var correct: bool = killer in [left, right]
			if _allowed_information(actor, correct):
				var text := "%s или %s — убивший вас демон." % [g.players[left].name, g.players[right].name]
				options.append({"label": text, "text": text, "abnormal": not correct, "left": left, "right": right})
	_information(actor, options)

func _insert_arbitrary() -> void:
	for i in jobs.size():
		if jobs[i].get("op") == "slot" and jobs[i].get("role") == "barber":
			jobs.insert(i, {"op": "arbitrary_deaths"})
			return
	jobs.push_front({"op": "arbitrary_deaths"})

func _ask_arbitrary() -> void:
	var options: Array = [{"label": "Закончить выбор смертей", "target": -1}]
	for s: int in g.seats_in_circle():
		if g.alive[s]:
			options.append(_target_option(s))
	_choice(g.storyteller, "Ведьма создала демона: смерти этой ночи произвольны", options, {"op": "arbitrary"})

func _custom_job(job: Dictionary) -> void:
	if job.op == "arbitrary_deaths":
		_ask_arbitrary()
	elif job.op == "klutz_pick":
		var actor := int(job.actor)
		var options: Array = []
		for s: int in g.seats_in_circle():
			if g.alive[s]:
				options.append(_target_option(s))
		_choice(actor, "Растяпа: публично выберите живого игрока", options, {"op": "klutz", "actor": actor})
	elif job.op == "sweetheart_pick":
		var options: Array = []
		for s: int in g.seats_in_circle():
			options.append(_target_option(s))
		_choice(g.storyteller, "Милашка погибла: кто пьянеет?", options, {"op": "sweetheart", "actor": int(job.actor)})

func on_nominate(nominator: int, _target: int) -> void:
	if g.catalog[g.roles[nominator]].type == "minion":
		minion_nominated = true
	var source := int(g.status[nominator].get("witch_source", -1))
	if source >= 0 and g.alive_count() > 3:
		if active(source, "witch"):
			g.event = {"text": "Событие при номинации", "target": nominator}
			g.event_left = 1.0
			g._event_commit = {"op": "sv_witch", "target": nominator, "source": source}
		else:
			abnormal[source] = true

func on_vote(seat: int) -> void:
	if g.catalog[g.roles[seat]].type == "demon":
		demon_votes[seat] = true

func commit_extra(commit: Dictionary) -> void:
	if commit.get("op") == "sv_witch":
		_kill(int(commit.target), int(commit.source), "witch")
		_advance()
	elif commit.get("op") == "sv_execution":
		var at_night: bool = g.phase == "night"
		if at_night:
			_kill(int(commit.target), -1, "execution")
			g.announced_alive[int(commit.target)] = bool(g.alive[int(commit.target)])
			g.public_log.append("%s казнён ночью." % g.players[int(commit.target)].name)
		else:
			execute(int(commit.target))
		_advance()

func _kill(target: int, source: int, cause: String, redirect: bool = true) -> void:
	if not g.alive[target]:
		return
	var role := str(g.roles[target])
	var working := healthy(target)
	var during_day: bool = g.phase != "night"
	if cause == "demon" and source >= 0 and active(source, "vigormortis") and g.catalog[role].type == "minion":
		g.status[target]["vig_source"] = source
		var choices: Array = []
		for s: int in _nearest_townsfolk(target):
			choices.append(_target_option(s))
		_choice(g.storyteller, "Вигормортис: какой ближайший горожанин отравлен?", choices, {"op": "vig_poison", "actor": source, "minion": target})
	super._kill(target, source, cause, redirect)
	if role == "sage" and cause == "demon":
		g.status[target]["sage_killer"] = source
	if role == "barber" and working:
		g.status[target]["barber_dead"] = true
	if role == "sweetheart":
		if working:
			jobs.push_front({"op": "sweetheart_pick", "actor": target})
		else:
			abnormal[target] = true
	if role == "klutz":
		g.status[target]["klutz_notify"] = true
		g.status[target]["klutz_real"] = working
		if during_day and g.phase != "game_over":
			g.status[target].erase("klutz_notify")
			jobs.push_front({"op": "klutz_pick", "actor": target})
	if pending.get("recipient", -1) == target:
		g.requests.erase(target)
		pending.clear()

func execute(target: int) -> void:
	var loses := false
	for source: int in g.seats_in_circle():
		var twin := int(g.status[source].get("twin", -1))
		if active(source, "evil_twin") and target in [source, twin] and g.sides[target] == "good":
			loses = true
	if loses:
		g.executed = target
		resolving_twin_execution = true
		_kill(target, -1, "execution")
		resolving_twin_execution = false
		_win("evil")
	else:
		super.execute(target)

func dusk() -> void:
	for s: int in g.seats_in_circle():
		if active(s, "vortox") and g.executed < 0:
			_win("evil")
			return
	_check_win()

func _check_win() -> void:
	if not g.winner.is_empty() or resolving_twin_execution:
		return
	for source: int in g.seats_in_circle():
		var twin := int(g.status[source].get("twin", -1))
		if twin >= 0 and active(source, "evil_twin") and g.alive[source] and g.alive[twin]:
			if g.alive_count() <= 2:
				_win("evil")
			return
	super._check_win()

func _on_dawn() -> void:
	g.dawn()
	abnormal.clear()
	demon_votes.clear()
	minion_nominated = false
	for s: int in g.seats_in_circle():
		if bool(g.status[s].get("klutz_notify", false)):
			g.status[s].erase("klutz_notify")
			jobs.append({"op": "klutz_pick", "actor": s})

func _answer(value: int) -> String:
	return "Да" if value == 1 else ("Нет" if value == 0 else "Не знаю")

func private_action(seat: int, kind: String, arg: Dictionary) -> bool:
	if not started or seat == g.storyteller or not g.alive[seat] or not g.phase in ["discussion", "nominations", "defense", "voting"]:
		return false
	if kind == "artist" and g.shown_roles[seat] == "artist" and not g.status[seat].get("once", false) and not g.status[seat].get("artist_waiting", false):
		if not arg.get("text") is String or str(arg.text).strip_edges().is_empty() or str(arg.text).length() > 500:
			return false
		g.status[seat]["artist_waiting"] = true
		_choice(g.storyteller, "Истинный ответ на вопрос %s: %s" % [g.players[seat].name, str(arg.text)], [
			{"label": "Да", "value": 1}, {"label": "Нет", "value": 0}, {"label": "Не знаю", "value": -1}, {"label": "Нужно переформулировать", "value": 2}],
			{"op": "artist_truth", "actor": seat, "question": str(arg.text).strip_edges(), "nonblocking": true})
		return true
	if kind == "savant" and g.shown_roles[seat] == "savant" and int(g.status[seat].get("savant_day", -1)) != int(g.day):
		g.status[seat]["savant_day"] = int(g.day)
		var options := _facts()
		var allowed: Array = []
		for fact: Dictionary in options:
			if bool(fact.truth) == (not _vortox(seat)) or not healthy(seat) and not _vortox(seat):
				allowed.append(fact)
		_choice(g.storyteller, "Учёный: первое утверждение", allowed, {"op": "savant_first", "actor": seat, "nonblocking": true})
		return true
	return false

func _facts() -> Array:
	var result: Array = []
	for s: int in g.seats_in_circle():
		for id: String in g.catalog:
			if g.catalog[id].edition == "sv":
				var text := "%s — %s." % [g.players[s].name, g.catalog[id].name]
				result.append({"label": text, "text": text, "truth": g.roles[s] == id, "target": s, "role": id})
	return result

func _savant_second(actor: int, first: Dictionary) -> void:
	var options: Array = []
	for fact: Dictionary in _facts():
		if fact.text != first.text and (not bool(fact.truth) or not healthy(actor) and not _vortox(actor)):
			options.append(fact)
	_choice(g.storyteller, "Учёный: второе утверждение", options,
		{"op": "savant_second", "actor": actor, "first": first, "nonblocking": true})

func extra_action(seat: int, kind: String, arg: Dictionary) -> bool:
	if not started:
		return false
	if kind == "madness_execution" and seat == g.storyteller:
		var target: int = g._target(arg)
		if target < 0 or not g.alive[target]:
			return false
		var source := int(g.status[target].get("mad_source", -1))
		if not active(target, "mutant") and not (source >= 0 and active(source, "cerenovus")):
			return false
		if g.phase != "night" and g.executed >= 0:
			return false
		g.event = {"text": "Казнь: %s" % g.players[target].name, "target": target}
		g.event_left = 1.0
		g._event_commit = {"op": "sv_execution", "target": target}
		return true
	if kind == "juggle" and seat != g.storyteller and g.alive[seat] and g.phase in ["discussion", "nominations"]:
		if int(g.day) != int(g.status[seat].get("juggler_first_day", 1)) or g.status[seat].has("juggler_correct"):
			return false
		if not arg.get("guesses") is Array or arg.guesses.size() > 5:
			return false
		var correct := 0
		var lines: Array[String] = []
		for guess: Variant in arg.guesses:
			if not guess is Dictionary or not guess.get("target") is int or not guess.get("role") is String:
				return false
			var target := int(guess.target)
			var id := str(guess.role)
			if not g.seats_in_circle().has(target) or not g.catalog.has(id) or g.catalog[id].edition != "sv":
				return false
			if g.roles[target] == id:
				correct += 1
			lines.append("%s — %s" % [g.players[target].name, g.catalog[id].name])
		g.status[seat]["juggler_correct"] = correct
		g.status[seat]["juggler_night"] = night_no + 1
		g.public_log.append("Предположения Жонглёра %s: %s." % [g.players[seat].name, "; ".join(lines) if not lines.is_empty() else "нет"])
		return true
	return false
