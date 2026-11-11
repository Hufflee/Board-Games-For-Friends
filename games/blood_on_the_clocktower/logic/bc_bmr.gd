extends "res://games/blood_on_the_clocktower/logic/bc_abilities.gd"
## «Дурная луна»: ночные выборы, защиты, воскрешения и особые демоны по переданному альманаху.

const FIRST_BMR := ["sailor", "courtier", "godfather", "devils_advocate", "lunatic", "pukka", "grandmother", "chambermaid"]
const OTHER_BMR := ["sailor", "innkeeper", "courtier", "gambler", "devils_advocate", "exorcist", "lunatic", "zombuul", "pukka", "shabaloth", "po", "assassin", "godfather", "professor", "gossip", "moonchild", "chambermaid"]
var day_died := false
var outsider_died := false
var minstrel_sources: Array = []
var mastermind_source := -1
var mastermind_day := -1
var _many: Dictionary = {}

func supports() -> bool:
	return g.edition == "bmr"

func scheduled_role(seat: int) -> String:
	return "lunatic" if g.roles[seat] == "lunatic" else str(g.shown_roles[seat])

func _order() -> Array:
	return FIRST_BMR if night_no == 1 else OTHER_BMR

func _initial_jobs() -> Array:
	return [{"op": "lunatic_info"}, {"op": "evil_info"}] if night_no == 1 else []

func _prepare_night() -> void:
	super._prepare_night()
	for s: int in g.seats_in_circle():
		var kept: Array = []
		for effect: Dictionary in g.status[s].get("drunks", []):
			if int(effect.until) > night_no:
				kept.append(effect)
		g.status[s]["drunks"] = kept
		for key: String in ["innkeeper_source", "advocate_source", "exorcist_source", "woke", "goon_used"]:
			g.status[s].erase(key)
	for source: int in minstrel_sources:
		if active(source, "minstrel"):
			for s: int in g.seats_in_circle():
				if s != source:
					_add_drunk(s, source, 1)

func healthy(seat: int, trail: Array = []) -> bool:
	if not super.healthy(seat, trail):
		return false
	if trail.has(seat):
		return true
	var next := trail.duplicate()
	next.append(seat)
	var pukka := int(g.status[seat].get("pukka_source", -1))
	if pukka >= 0 and g.alive[pukka] and g.roles[pukka] == "pukka":
		if pukka == seat or healthy(pukka, next):
			return false
	for effect: Dictionary in g.status[seat].get("drunks", []):
		var source := int(effect.source)
		if int(effect.until) <= night_no or not g.alive[source] or g.roles[source] != effect.role:
			continue
		if source == seat or healthy(source, next):
			return false
	return true

func _add_drunk(target: int, source: int, nights: int) -> void:
	if not g.status[target].has("drunks"):
		g.status[target]["drunks"] = []
	g.status[target].drunks.append({"source": source, "role": str(g.roles[source]), "until": night_no + nights})

func counts_alive(seat: int) -> bool:
	return bool(g.alive[seat]) and not (g.roles[seat] == "zombuul" and bool(g.status[seat].get("zombuul_dead", false)))

func public_life(seat: int) -> bool:
	return counts_alive(seat)

func _custom_job(job: Dictionary) -> void:
	match str(job.op):
		"lunatic_info":
			var actor: int = g.roles.find("lunatic")
			if actor >= 0:
				g.status[actor]["woke"] = true
				var options: Array = []
				for s: int in g.seats_in_circle():
					if s != actor:
						options.append(_target_option(s))
				_choice(g.storyteller, "Лунатик: выберите мнимого приспешника", options,
					{"op": "lunatic_info", "actor": actor, "chosen": [], "count": int(g.Data.COUNTS[g.seats_in_circle().size()][2])})
		"moon_pick":
			_ask_targets(int(job.actor), "Дитя луны: публично выберите живого игрока", "moon_pick", true)
		"resurrect":
			_revive(int(job.target))

func _receive_extra(context: Dictionary, selected: Variant) -> void:
	var actor := int(context.get("actor", -1))
	match str(context.op):
		"lunatic_info":
			var chosen: Array = context.chosen.duplicate()
			chosen.append(int(selected.target))
			if chosen.size() < int(context.count):
				var options: Array = []
				for s: int in g.seats_in_circle():
					if s != actor and not chosen.has(s):
						options.append(_target_option(s))
				_choice(g.storyteller, "Лунатик: следующий мнимый приспешник", options,
					{"op": "lunatic_info", "actor": actor, "chosen": chosen, "count": context.count})
				return
			var fake_names: Array[String] = []
			for s: int in chosen:
				fake_names.append(str(g.players[s].name))
			g.add_private(actor, "Ваши приспешники: %s." % ", ".join(fake_names))
			var names: Array[String] = []
			for id: String in g.bluffs:
				names.append(str(g.catalog[id].name))
			g.add_private(actor, "Роли для блефа: %s." % ", ".join(names))
			for s: int in g.seats_in_circle():
				if g.catalog[g.roles[s]].type == "demon":
					g.add_private(s, "Лунатик — %s." % g.players[actor].name)
		"many":
			var targets: Array = context.targets.duplicate()
			targets.append(int(selected.target))
			if targets.size() < int(context.count):
				_ask_many(actor, str(context.role), int(context.count), targets, bool(context.get("living", false)))
			else:
				_resolve_targets(actor, str(context.role), targets)
		"bmr_target":
			_resolve_targets(actor, str(context.role), [int(selected.target)])
		"role_guess":
			if str(selected.role).is_empty():
				return
			g.status[actor]["once"] = true
			if active(actor, "courtier"):
				for s: int in g.seats_in_circle():
					if g.roles[s] == selected.role:
						_add_drunk(s, actor, 3)
		"gamble_role":
			if active(actor, "gambler") and g.roles[int(context.target)] != selected.role:
				_kill(actor, actor, "gambler")
		"drunk_choice":
			_add_drunk(int(selected.target), actor, 1)
		"grandchild":
			var child := int(selected.target)
			g.status[actor]["grandchild"] = child
			if healthy(actor):
				g.add_private(actor, "%s — %s." % [g.players[child].name, g.catalog[g.roles[child]].name])
			else:
				# Нарушенная способность: рассказчик называет любую добрую роль (ложь допустима).
				var options: Array = []
				for id: String in g.catalog:
					if g.catalog[id].edition == g.edition and g.catalog[id].side == "good":
						var text := "%s — %s." % [g.players[child].name, g.catalog[id].name]
						options.append({"label": text, "text": text})
				_information(actor, options)
		"godfather_info":
			g.add_private(actor, str(selected.text))
		"shabaloth_revive":
			if int(selected.target) >= 0:
				_revive(int(selected.target))
			if g.alive[actor] and not _exorcised(actor):
				_ask_many(actor, "shabaloth", 2)
				g.status[actor]["woke"] = true
		"pacifist":
			if not bool(selected.save):
				_kill(int(context.target), int(context.get("source", -1)), "execution", false)
		"gossip_truth":
			g.status[actor]["gossip_true"] = bool(selected.value)
		"gossip_kill":
			_kill(int(selected.target), actor, "gossip")
		"moon_pick":
			g.public_log.append("%s заявляет выбор Дитя луны: %s." % [g.players[actor].name, g.players[int(selected.target)].name])
			g.public_revision += 1
			g.status[actor]["moon_target"] = int(selected.target)
		"skip":
			if str(context.role) == "po":
				g.status[actor]["po_charged"] = true

func _ask_targets(actor: int, title: String, role: String, living: bool = false, optional: bool = false, excluded: Array = []) -> void:
	var options: Array = []
	if optional:
		options.append({"label": "Не использовать сейчас", "target": -1})
	for s: int in g.seats_in_circle():
		if excluded.has(s) or living and not counts_alive(s):
			continue
		options.append(_target_option(s))
	_choice(actor, title, options, {"op": "bmr_target", "actor": actor, "role": role})
	if role == "moon_pick" and not pending.is_empty():
		pending.op = "moon_pick"

func _ask_many(actor: int, role: String, count: int, selected: Array = [], living: bool = false) -> void:
	var options: Array = []
	for s: int in g.seats_in_circle():
		if not selected.has(s) and (not living or counts_alive(s)) and not (role == "chambermaid" and s == actor):
			options.append(_target_option(s))
	if options.is_empty():
		return
	_choice(actor, "Выбор %d из %d" % [selected.size() + 1, count], options,
		{"op": "many", "actor": actor, "role": role, "count": count, "targets": selected, "living": living})

func _wake(actor: int, id: String) -> void:
	if scheduled_role(actor) != id:
		return
	if id == "moonchild":
		var target := int(g.status[actor].get("moon_target", -1))
		g.status[actor].erase("moon_target")
		if target >= 0 and bool(g.status[actor].get("moon_real", false)) and healthy(actor) and g.sides[target] == "good":
			_kill(target, actor, "moonchild")
		return
	if not bool(g.alive[actor]):
		return
	if id in ["assassin", "professor", "courtier"] and bool(g.status[actor].get("once", false)):
		return
	if id == "godfather" and night_no > 1 and not outsider_died:
		return
	if id == "zombuul" and day_died:
		return
	if id in ["pukka", "shabaloth"]:
		_residual(actor, id)
		if not pending.is_empty() or not g.alive[actor] or g.phase == "game_over":
			return
	if g.catalog[g.roles[actor]].type == "demon" and _exorcised(actor):
		if id == "po":
			g.status[actor]["po_charged"] = true
		return
	match id:
		"sailor":
			_ask_targets(actor, "Моряк: выберите живого игрока", id, true)
		"devils_advocate":
			_ask_targets(actor, "Адвокат: выберите живого игрока", id, true, false, [int(g.status[actor].get("previous", -1))])
		"exorcist":
			_ask_targets(actor, "Экзорцист: выберите игрока", id, false, false, [int(g.status[actor].get("previous", -1))])
		"innkeeper":
			_ask_many(actor, id, 2)
		"chambermaid":
			if g.voting_population() - (1 if counts_alive(actor) else 0) < 2:
				return
			_ask_many(actor, id, 2, [], true)
		"courtier":
			_ask_roles(actor, "role_guess", true)
		"gambler":
			_ask_targets(actor, "Азартный игрок: выберите игрока", id)
		"assassin":
			_ask_targets(actor, "Ассасин: используете способность?", id, false, true)
		"professor":
			var excluded: Array = []
			for s: int in g.seats_in_circle():
				if counts_alive(s):
					excluded.append(s)
			_ask_targets(actor, "Профессор: выберите мёртвого игрока", id, false, true, excluded)
		"godfather":
			g.status[actor]["woke"] = true
			if night_no == 1:
				var names: Array[String] = []
				for s: int in g.seats_in_circle():
					if g.catalog[g.roles[s]].type == "outsider":
						names.append(str(g.catalog[g.roles[s]].name))
				g.add_private(actor, "Изгои в партии: %s." % (", ".join(names) if not names.is_empty() else "нет"))
			else:
				_ask_targets(actor, "Крёстный отец: выберите жертву", id)
		"grandmother":
			g.status[actor]["woke"] = true
			var options: Array = []
			for s: int in g.seats_in_circle():
				if g.sides[s] == "good" and s != actor:
					options.append(_target_option(s))
			_choice(g.storyteller, "Бабушка: выберите доброго внука", options, {"op": "grandchild", "actor": actor})
		"pukka", "zombuul":
			_ask_targets(actor, "Выберите жертву", id, night_no == 1)
		"shabaloth":
			_ask_many(actor, id, 2)
		"po":
			if bool(g.status[actor].get("po_charged", false)):
				_ask_many(actor, id, 3)
			else:
				_ask_targets(actor, "По: жертва или подготовка тройного убийства", id, false, true)
		"lunatic":
			var fake := str(g.shown_roles[actor])
			if night_no == 1 and fake != "pukka":
				return
			if fake == "zombuul" and day_died:
				return
			if fake == "shabaloth":
				_ask_many(actor, id, 2)
			elif fake == "po" and bool(g.status[actor].get("po_charged", false)):
				_ask_many(actor, id, 3)
			else:
				_ask_targets(actor, "Выберите жертву", id, false, fake == "po")
		"gossip":
			if active(actor, id) and bool(g.status[actor].get("gossip_true", false)):
				var options: Array = []
				for s: int in g.seats_in_circle():
					if g.alive[s] and not _cannot_die(s, "gossip"):
						options.append(_target_option(s))
				_choice(g.storyteller, "Сплетник: выберите игрока, который может погибнуть", options, {"op": "gossip_kill", "actor": actor})
		_:
			return
	if not pending.is_empty() and int(pending.recipient) == actor:
		g.status[actor]["woke"] = true

func _ask_roles(actor: int, operation: String, optional: bool = false, context: Dictionary = {}) -> void:
	var options: Array = []
	if optional:
		options.append({"label": "Не использовать сейчас", "role": ""})
	for id: String in g.catalog:
		if g.catalog[id].edition == g.edition:
			options.append({"label": str(g.catalog[id].name), "role": id})
	var request := context.duplicate(true)
	request["op"] = operation
	request["actor"] = actor
	_choice(actor, "Выберите роль", options, request)

func _goon(actor: int, targets: Array) -> bool:
	for target: int in targets:
		if active(target, "goon") and not bool(g.status[target].get("goon_used", false)):
			g.status[target]["goon_used"] = true
			g.sides[target] = g.sides[actor]
			g.add_private(target, "Ваша сторона: %s." % ("зло" if g.sides[target] == "evil" else "добро"))
			_add_drunk(actor, target, 1)
			return true
	return false

func _resolve_targets(actor: int, id: String, targets: Array) -> void:
	if targets[0] == -1:
		if id in ["po", "lunatic"]:
			g.status[actor]["po_charged"] = true
		return
	var initially_healthy := healthy(actor)
	var hit_goon := _goon(actor, targets)
	if id == "lunatic":
		g.status[actor]["po_charged"] = false
		var names: Array[String] = []
		for target: int in targets:
			names.append(str(g.players[target].name))
		for s: int in g.seats_in_circle():
			if g.catalog[g.roles[s]].type == "demon":
				g.add_private(s, "Лунатик выбрал: %s." % ", ".join(names))
		return
	if id == "gambler":
		_ask_roles(actor, "gamble_role", false, {"target": int(targets[0])})
		return
	if id == "chambermaid":
		var total := 0
		for target: int in targets:
			if bool(g.status[target].get("woke", false)):
				total += 1
		_numeric(actor, [total], 2, "Из выбранных игроков просыпались: %d.")
		return
	if id in ["professor", "assassin"]:
		g.status[actor]["once"] = true
	if id == "po":
		g.status[actor]["po_charged"] = false
	if id in ["exorcist", "devils_advocate"]:
		g.status[actor]["previous"] = int(targets[0])
	if not healthy(actor):
		if id == "assassin" and initially_healthy and hit_goon:
			_kill(int(targets[0]), actor, "assassin")
		return
	match id:
		"sailor", "innkeeper":
			var options: Array = []
			if id == "sailor":
				options.append(_target_option(actor))
			for target: int in targets:
				if id == "innkeeper":
					g.status[target]["innkeeper_source"] = actor
				if id != "sailor" or target != actor:
					options.append(_target_option(target))
			_choice(g.storyteller, "Кто пьянеет до сумерек?", options, {"op": "drunk_choice", "actor": actor})
		"exorcist":
			var target := int(targets[0])
			if g.catalog[g.roles[target]].type == "demon":
				g.status[target]["exorcist_source"] = actor
				g.add_private(target, "Экзорцист %s выбрал вас. Этой ночью вы не просыпаетесь для атаки." % g.players[actor].name)
		"devils_advocate":
			g.status[int(targets[0])]["advocate_source"] = actor
		"chambermaid":
			var total := 0
			for target: int in targets:
				if bool(g.status[target].get("woke", false)):
					total += 1
			_numeric(actor, [total], 2, "Из выбранных игроков просыпались: %d.")
		"professor":
			var target := int(targets[0])
			if g.catalog[g.roles[target]].type == "townsfolk":
				_revive(target)
		"pukka":
			g.status[int(targets[0])]["pukka_source"] = actor
			g.status[actor]["pukka_target"] = int(targets[0])
		"po", "shabaloth", "zombuul", "godfather", "assassin":
			if id == "shabaloth":
				g.status[actor]["last_eaten"] = targets.duplicate()
			for target: int in targets:
				if g.phase == "game_over":
					break
				_kill(target, actor, "assassin" if id == "assassin" else ("godfather" if id == "godfather" else "demon"))

func _residual(actor: int, id: String) -> void:
	if id == "pukka":
		var prior := int(g.status[actor].get("pukka_target", -1))
		if prior >= 0:
			if active(actor, id):
				_kill(prior, actor, "demon")
			g.status[prior].erase("pukka_source")
			g.status[actor].erase("pukka_target")
	elif id == "shabaloth" and active(actor, id):
		var options: Array = [{"label": "Никого не воскрешать", "target": -1}]
		for target: int in g.status[actor].get("last_eaten", []):
			if not g.alive[target]:
				options.append(_target_option(target))
		if options.size() > 1:
			_choice(g.storyteller, "Шабалот: можно вернуть одну прежнюю жертву", options, {"op": "shabaloth_revive", "actor": actor})

func _exorcised(actor: int) -> bool:
	var source := int(g.status[actor].get("exorcist_source", -1))
	return source >= 0 and active(source, "exorcist")

func _cannot_die(target: int, cause: String) -> bool:
	if cause == "assassin":
		return false
	if active(target, "sailor"):
		return true
	for s: int in g.seats_in_circle():
		if active(s, "tea_lady"):
			var neighbors: Array = g.living_neighbors(s)
			if neighbors.size() == 2 and neighbors.has(target) and g.sides[int(neighbors[0])] == "good" and g.sides[int(neighbors[1])] == "good":
				return true
	var source := int(g.status[target].get("innkeeper_source", -1))
	if g.phase == "night" and source >= 0 and active(source, "innkeeper"):
		return true
	source = int(g.status[target].get("advocate_source", -1))
	return cause == "execution" and source >= 0 and active(source, "devils_advocate")

func _kill(target: int, source: int, cause: String, redirect: bool = true) -> void:
	if not g.alive[target] or _cannot_die(target, cause):
		return
	if redirect and cause == "execution" and g.sides[target] == "good":
		for s: int in g.seats_in_circle():
			if active(s, "pacifist"):
				_choice(g.storyteller, "Пацифист: казнённый добрый игрок может выжить", [
					{"label": "Позволить погибнуть", "save": false}, {"label": "Спасти", "save": true}],
					{"op": "pacifist", "target": target, "source": source})
				return
	if cause != "assassin" and active(target, "fool") and not bool(g.status[target].get("fool_used", false)):
		g.status[target]["fool_used"] = true
		return
	if cause != "assassin" and active(target, "zombuul") and not bool(g.status[target].get("zombuul_dead", false)):
		g.status[target]["zombuul_dead"] = true
		if g.phase != "night":
			g.announced_alive[target] = false
			g.public_log.append("%s погиб." % g.players[target].name)
			day_died = true
		return
	var role := str(g.roles[target])
	var was_healthy := healthy(target)
	var during_day: bool = g.phase != "night"
	if role in ["pukka", "shabaloth", "po", "zombuul"] and cause == "execution":
		for s: int in g.seats_in_circle():
			if active(s, "mastermind"):
				mastermind_source = s
				mastermind_day = int(g.day) + 1
				break
	super._kill(target, source, cause, false)
	if during_day:
		day_died = true
		if g.catalog[role].type == "outsider":
			outsider_died = true
		if g.catalog[role].type == "minion":
			for s: int in g.seats_in_circle():
				if active(s, "minstrel") and not minstrel_sources.has(s):
					minstrel_sources.append(s)
	if role == "moonchild":
		g.status[target]["moon_notify"] = true
		g.status[target]["moon_real"] = was_healthy
		if during_day and g.phase != "game_over":
			g.status[target].erase("moon_notify")
			jobs.push_front({"op": "moon_pick", "actor": target})
	if cause == "demon":
		for s: int in g.seats_in_circle():
			if active(s, "grandmother") and int(g.status[s].get("grandchild", -1)) == target:
				_kill(s, s, "grandmother")

func _revive(target: int) -> void:
	if g.alive[target]:
		return
	g.alive[target] = true
	g.dead_votes[target] = true
	for key: String in ["once", "fool_used", "died_night"]:
		g.status[target].erase(key)
	if g.roles[target] == "grandmother":
		jobs.push_front({"op": "wake", "actor": target, "role": "grandmother"})

func execute(target: int) -> void:
	var final_day: bool = mastermind_day == int(g.day) and mastermind_source >= 0 and active(mastermind_source, "mastermind")
	super.execute(target)
	if final_day and g.winner.is_empty():
		_win("evil" if g.sides[target] == "good" else "good")

func dusk() -> void:
	if mastermind_day == int(g.day) and mastermind_source >= 0 and active(mastermind_source, "mastermind"):
		_win("good" if g.executed < 0 or g.sides[int(g.executed)] == "evil" else "evil")
	else:
		_check_win()

func _check_win() -> void:
	if not g.winner.is_empty():
		return
	if mastermind_day >= int(g.day) and mastermind_source >= 0 and active(mastermind_source, "mastermind"):
		return
	super._check_win()

func _on_dawn() -> void:
	g.dawn()
	day_died = false
	outsider_died = false
	minstrel_sources.clear()
	for s: int in g.seats_in_circle():
		g.status[s].erase("gossip_true")
		g.status[s].erase("gossip_claim_day")
		if bool(g.status[s].get("moon_notify", false)):
			g.status[s].erase("moon_notify")
			jobs.append({"op": "moon_pick", "actor": s})

func extra_action(seat: int, kind: String, arg: Dictionary) -> bool:
	if not started:
		return false
	if kind == "tinker" and seat == g.storyteller:
		var target: int = g._target(arg)
		if target >= 0 and active(target, "tinker"):
			if g.phase == "night":
				_kill(target, target, "tinker")
				_advance()
			else:
				g.event = {"text": "Событие в городе", "target": target}
				g.event_left = 1.0
				g._event_commit = {"op": "bmr_death", "target": target, "cause": "tinker"}
			return true
	if kind == "gossip" and seat != g.storyteller and counts_alive(seat) and g.phase in ["discussion", "nominations"]:
		if not arg.get("text") is String or str(arg.text).strip_edges().is_empty() or str(arg.text).length() > 500:
			return false
		if int(g.status[seat].get("gossip_claim_day", -1)) == int(g.day):
			return false
		g.status[seat]["gossip_claim_day"] = int(g.day)
		g.public_log.append("Сплетня %s: %s" % [g.players[seat].name, str(arg.text).strip_edges()])
		_choice(g.storyteller, "Оцените однозначность и истинность сплетни", [
			{"label": "Истинное однозначное утверждение", "value": true}, {"label": "Ложно или неоднозначно", "value": false}],
			{"op": "gossip_truth", "actor": seat})
		return true
	return false

func commit_extra(commit: Dictionary) -> void:
	if commit.get("op") == "bmr_death":
		_kill(int(commit.target), int(commit.target), str(commit.cause))
		_advance()
