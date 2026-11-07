extends RefCounted
## Хостовый планировщик способностей Clocktower. UI получает только адресные запросы.
## Первый пакет: сценарий «Назревает беда»; следующие сценарии добавляются отдельно.

const FIRST := ["poisoner", "spy", "washerwoman", "librarian", "investigator", "chef", "empath", "fortune_teller", "butler"]
const OTHER := ["poisoner", "monk", "spy", "imp", "ravenkeeper", "undertaker", "empath", "fortune_teller", "butler"]
var _game: WeakRef
var g: RefCounted:
	get:
		return _game.get_ref()
var started := false
var jobs: Array = []
var pending: Dictionary = {}
var red_herring := -1
var night_no := 0
var knowledge: Dictionary = {}
var waiting_choices: Array = []
var processed_slots: Array = []

func _init(game: RefCounted) -> void:
	_game = weakref(game)

func begin(seat: int) -> bool:
	if seat != g.storyteller or not supports() or not pending.is_empty() or not g.event.is_empty():
		return false
	if not g.phase in ["first_night", "dusk"]:
		return false
	if started and g.phase == "first_night":
		return false
	started = true
	night_no += 1
	g.phase = "night"
	_prepare_night()
	jobs.clear()
	processed_slots.clear()
	jobs.append_array(_initial_jobs())
	for id: String in _order():
		jobs.append({"op": "slot", "role": id})
	jobs.append({"op": "dawn"})
	_advance()
	return true

func supports() -> bool:
	return g.edition == "tb"

func _prepare_night() -> void:
	for s: int in g.seats_in_circle():
		g.status[s].erase("poison_source")
		g.status[s].erase("monk_source")
		g.status[s].erase("died_night")
		g.status[s].erase("raven_real")

func _initial_jobs() -> Array:
	var result: Array = []
	if night_no == 1:
		if g.roles.has("fortune_teller") or g.shown_roles.has("fortune_teller"):
			result.append({"op": "red_herring"})
		result.append({"op": "evil_info"})
	return result

func _order() -> Array:
	return FIRST if night_no == 1 else OTHER

func scheduled_role(seat: int) -> String:
	return str(g.shown_roles[seat])

func counts_alive(seat: int) -> bool:
	return bool(g.alive[seat])

func public_life(seat: int) -> bool:
	return bool(g.alive[seat])

func extra_action(_seat: int, _kind: String, _arg: Dictionary) -> bool:
	return false

func private_action(_seat: int, _kind: String, _arg: Dictionary) -> bool:
	return false

func on_vote(_seat: int) -> void:
	pass

func blocking_choice() -> bool:
	if not pending.is_empty() and not bool(pending.get("nonblocking", false)):
		return true
	for request: Dictionary in waiting_choices:
		if not bool(request.context.get("nonblocking", false)):
			return true
	return false

func commit_extra(_commit: Dictionary) -> void:
	pass

func _receive_extra(_context: Dictionary, _selected: Variant) -> void:
	pass

func _custom_job(_job: Dictionary) -> void:
	pass

func _on_dawn() -> void:
	g.dawn()

func healthy(seat: int, trail: Array = []) -> bool:
	if str(g.roles[seat]) == "drunk" or bool(g.status[seat].get("drunk", false)):
		return false
	var source := int(g.status[seat].get("poison_source", -1))
	if source < 0 or str(g.roles[source]) != "poisoner" or not bool(g.alive[source]):
		return true
	if source == seat:
		return false
	if trail.has(seat):
		return true
	var next := trail.duplicate()
	next.append(seat)
	return not healthy(source, next)

func active(seat: int, role: String) -> bool:
	return bool(g.alive[seat]) and str(g.roles[seat]) == role and healthy(seat)

func _choice(recipient: int, title: String, options: Array, context: Dictionary, hint: String = "") -> void:
	if options.is_empty():
		return
	if not pending.is_empty():
		waiting_choices.append({"recipient": recipient, "title": title, "options": options.duplicate(true),
			"context": context.duplicate(true), "hint": hint})
		return
	pending = context.duplicate(true)
	pending["recipient"] = recipient
	g.request_choice(recipient, title, options, hint)

func receive(recipient: int, selected: Variant) -> void:
	if pending.is_empty() or int(pending.recipient) != recipient:
		return
	var context := pending.duplicate(true)
	pending.clear()
	var actor := int(context.get("actor", -1))
	_note_choice(recipient, context, selected)
	match str(context.op):
		"red_herring":
			red_herring = int(selected.target)
		"information":
			g.add_private(actor, str(selected.text))
		"target":
			_target_selected(actor, str(context.role), selected)
		"pair":
			_pair_selected(actor, str(context.role), selected)
		"spy":
			knowledge[actor] = {"grimoire": selected.snapshot.duplicate(true)}
			g.add_private(actor, "Вы осмотрели гримуар этой ночью.")
		"mayor":
			_kill(int(selected.target), int(context.source), "demon", false)
		"starpass":
			_become_imp(int(selected.target))
			_check_win()
		"virgin":
			if bool(selected.value):
				_execution_event(actor)
		"slayer":
			if bool(selected.value):
				var was_alive := bool(g.alive[int(context.target)])
				_kill(int(context.target), actor, "slayer")
				if not was_alive or bool(g.alive[int(context.target)]):
					_slay_miss(int(context.target))
			else:
				_slay_miss(int(context.target))
			_check_win()
		_:
			_receive_extra(context, selected)
	_check_win()
	if pending.is_empty() and not waiting_choices.is_empty() and g.phase != "game_over":
		var deferred: Dictionary = waiting_choices.pop_front()
		_choice(int(deferred.recipient), str(deferred.title), deferred.options, deferred.context, str(deferred.get("hint", "")))
	_advance()

## Рассказчику — запись, что выбрал игрок (Гадалка, Монах, Отравитель…). Роль — та, которой игрок
## себя считает; у Пьяницы/Лунатика рядом настоящая.
func _note_choice(recipient: int, context: Dictionary, selected: Variant) -> void:
	if recipient == g.storyteller or recipient < 0:
		return
	var label := str(selected.get("label", selected.get("text", ""))) if selected is Dictionary else str(selected)
	var role_name := _story_role(recipient)
	var when := ("Ночь %d" % night_no) if g.phase in ["first_night", "night"] else ("День %d" % g.day)
	g.story_log.append("%s · %s (%s): %s" % [when, g.players[recipient].name, role_name, label])

## Роль для записей рассказчика: та, которой игрок себя считает, и настоящая, если отличается.
func _story_role(seat: int) -> String:
	var shown := str(g.shown_roles[seat])
	var role_name := str(g.catalog.get(shown, {}).get("name", shown))
	if shown != str(g.roles[seat]):
		role_name += ", на деле %s" % str(g.catalog.get(str(g.roles[seat]), {}).get("name", g.roles[seat]))
	return role_name

## Ночная очередь для рассказчика: кто сейчас выбирает и кто ещё не ходил этой ночью.
func night_queue() -> Array:
	var result: Array = []
	if not pending.is_empty():
		var who := int(pending.get("recipient", -1))
		if who >= 0 and who != g.storyteller:
			result.append({"seat": who, "role": scheduled_role(who), "now": true})
	for job: Dictionary in jobs:
		match str(job.get("op", "")):
			"wake":
				result.append({"seat": int(job.actor), "role": str(job.role), "now": false})
			"slot":
				for s: int in g.seats_in_circle():
					if scheduled_role(s) == str(job.role):
						result.append({"seat": s, "role": str(job.role), "now": false})
	return result

func _advance() -> void:
	while pending.is_empty() and g.event.is_empty() and not jobs.is_empty() and g.phase != "game_over":
		var job: Dictionary = jobs.pop_front()
		match str(job.op):
			"slot":
				processed_slots.append(str(job.role))
				var circle: Array = g.seats_in_circle()
				circle.reverse()
				for s: int in circle:
					if scheduled_role(s) == str(job.role):
						jobs.push_front({"op": "wake", "actor": s, "role": str(job.role)})
			"red_herring":
				var options: Array = []
				for s: int in g.seats_in_circle():
					if g.sides[s] == "good":
						options.append(_target_option(s))
				_choice(g.storyteller, "Выберите доброго игрока — ложный след Гадалки", options, {"op": "red_herring"})
			"evil_info":
				_evil_information()
			"wake":
				_wake(int(job.actor), str(job.role))
			"check_win":
				_check_win()
			"dawn":
				_on_dawn()
			_:
				_custom_job(job)

func _evil_information() -> void:
	if g.seats_in_circle().size() < 7:
		return
	var minions: Array[String] = []
	var demons: Array[String] = []
	for s: int in g.seats_in_circle():
		if g.catalog[g.roles[s]].type == "minion":
			minions.append(str(g.players[s].name))
		if g.catalog[g.roles[s]].type == "demon":
			demons.append(str(g.players[s].name))
	for s: int in g.seats_in_circle():
		if g.catalog[g.roles[s]].type == "minion":
			g.add_private(s, "Демон: %s. Приспешники: %s." % [", ".join(demons), ", ".join(minions)])
		elif g.catalog[g.roles[s]].type == "demon":
			var names: Array[String] = []
			for id: String in g.bluffs:
				names.append(str(g.catalog[id].name))
			g.add_private(s, "Приспешники: %s. Роли для блефа: %s." % [", ".join(minions), ", ".join(names)])

func _wake(actor: int, id: String) -> void:
	if str(g.shown_roles[actor]) != id:
		return
	if id == "ravenkeeper":
		if not bool(g.status[actor].get("died_night", false)):
			return
	elif not bool(g.alive[actor]):
		return
	match id:
		"poisoner", "monk", "imp", "butler", "ravenkeeper":
			var options: Array = []
			for s: int in g.seats_in_circle():
				if id in ["monk", "butler"] and s == actor:
					continue
				options.append(_target_option(s))
			_choice(actor, "Выберите игрока", options, {"op": "target", "actor": actor, "role": id})
		"fortune_teller":
			var options: Array = []
			var circle: Array = g.seats_in_circle()
			for a in circle.size():
				for b in range(a + 1, circle.size()):
					var left: int = circle[a]
					var right: int = circle[b]
					options.append({"label": "%s и %s" % [g.players[left].name, g.players[right].name], "targets": [left, right]})
			_choice(actor, "Гадалка: выберите двух игроков", options, {"op": "pair", "actor": actor, "role": id})
		"washerwoman", "librarian", "investigator":
			_first_information(actor, id)
		"chef":
			_numeric(actor, _chef_values(), g.seats_in_circle().size(), "Пар соседствующих злых игроков: %d.")
		"empath":
			_numeric(actor, _empath_values(actor), 2, "Среди ваших живых соседей злых: %d.")
		"undertaker":
			if int(g.execution_death) >= 0:
				_role_information(actor, int(g.execution_death), "Казнённый был: %s.")
			else:
				# По альманаху Гробовщик (и Пьяница в его роли) узнаёт только казнённого; ночная смерть — не повод.
				g.story_log.append("Ночь %d · %s (%s) не просыпается: сегодня никто не казнён." % [night_no, g.players[actor].name, _story_role(actor)])
		"spy":
			_spy(actor)

func _target_selected(actor: int, id: String, selected: Dictionary) -> void:
	var target := int(selected.target)
	match id:
		"poisoner":
			if active(actor, id):
				g.status[target]["poison_source"] = actor
		"monk":
			if active(actor, id):
				g.status[target]["monk_source"] = actor
		"butler":
			g.status[actor]["master"] = target
		"imp":
			if active(actor, id):
				_kill(target, actor, "demon")
		"ravenkeeper":
			_role_information(actor, target, "Вы узнали роль выбранного игрока: %s.")

func _pair_selected(actor: int, id: String, selected: Dictionary) -> void:
	if id != "fortune_teller":
		return
	var possible: Array = []
	for left: bool in _demon_options(int(selected.targets[0])):
		for right: bool in _demon_options(int(selected.targets[1])):
			var value: bool = left or right or selected.targets.has(red_herring)
			if not possible.has(value):
				possible.append(value)
	_boolean_information(actor, possible, "Среди выбранных игроков есть демон: %s.")

func _target_option(seat: int) -> Dictionary:
	return {"label": str(g.players[seat].name), "target": seat}

func _role_options(target: int) -> Array:
	var result: Array = [str(g.roles[target])]
	if not healthy(target):
		return result
	if g.roles[target] in ["spy", "recluse"]:
		for id: String in g.catalog:
			if g.catalog[id].edition != g.edition:
				continue
			if g.roles[target] == "spy" and g.catalog[id].side == "good" or g.roles[target] == "recluse" and g.catalog[id].side == "evil":
				result.append(id)
	return result

func _side_options(target: int) -> Array:
	var result: Array = [str(g.sides[target]) == "evil"]
	if healthy(target) and g.roles[target] in ["spy", "recluse"]:
		if not result.has(not bool(result[0])):
			result.append(not bool(result[0]))
	return result

func _demon_options(target: int) -> Array:
	var result: Array = []
	for id: String in _role_options(target):
		var value: bool = g.catalog[id].type == "demon"
		if not result.has(value):
			result.append(value)
	return result

func _first_information(actor: int, id: String) -> void:
	var kind: String = {"washerwoman": "townsfolk", "librarian": "outsider", "investigator": "minion"}[id]
	var options: Array = []
	var circle: Array = g.seats_in_circle()
	var impaired := not healthy(actor)
	var has_candidate := false
	for target: int in circle:
		for role: String in _role_options(target):
			if g.catalog[role].type == kind:
				has_candidate = true
	for a in circle.size():
		for b in range(a + 1, circle.size()):
			var left: int = circle[a]
			var right: int = circle[b]
			for role: String in g.catalog:
				if g.catalog[role].edition != g.edition or g.catalog[role].type != kind:
					continue
				if impaired or _role_options(left).has(role) or _role_options(right).has(role):
					var text := "%s или %s — %s." % [g.players[left].name, g.players[right].name, g.catalog[role].name]
					options.append({"label": text, "text": text, "left": left, "right": right, "role": role})
	if id == "librarian" and (impaired or not has_candidate or _can_hide_all_outsiders()):
		options.append({"label": "Изгоев нет", "text": "Изгоев в партии нет."})
	_information(actor, options)

func _can_hide_all_outsiders() -> bool:
	for s: int in g.seats_in_circle():
		if g.catalog[g.roles[s]].type == "outsider" and not (g.roles[s] == "recluse" and healthy(s)):
			return false
	return true

func _information(actor: int, options: Array) -> void:
	if options.size() == 1:
		g.add_private(actor, str(options[0].text))
	elif not options.is_empty():
		_choice(g.storyteller, "Информация для %s · %s" % [g.players[actor].name, g.catalog[g.shown_roles[actor]].name], options,
			{"op": "information", "actor": actor}, _information_hint(actor))

## Пояснение рассказчику, почему для информации несколько вариантов. Игроку не передаётся.
func _information_hint(actor: int) -> String:
	var reason := _impairment(actor)
	if not reason.is_empty():
		return "%s: способность не работает — можно дать любой вариант." % reason
	var text := "Способность работает, все варианты верны — выберите любой."
	var notes := _registration_notes()
	if not notes.is_empty():
		text += " Учтите: %s." % "; ".join(notes)
	return text

## Почему способность места не работает; пусто — здорова.
func _impairment(seat: int) -> String:
	if healthy(seat):
		return ""
	var who := str(g.players[seat].name)
	if str(g.roles[seat]) == "drunk":
		return "%s на самом деле Пьяница" % who
	var source := int(g.status[seat].get("poison_source", -1))
	if source >= 0 and str(g.roles[source]) == "poisoner" and bool(g.alive[source]):
		return "%s отравлен (Отравитель — %s)" % [who, g.players[source].name]
	if bool(g.status[seat].get("drunk", false)):
		return "%s пьян" % who
	return "%s пьян или отравлен" % who

## Роли в игре, которые рассказчик может зарегистрировать иначе (только с рабочей способностью).
func _registration_notes() -> Array[String]:
	var notes: Array[String] = []
	for s: int in g.seats_in_circle():
		if not healthy(s):
			continue
		if g.roles[s] == "spy":
			notes.append("Шпион (%s) может определиться добрым" % g.players[s].name)
		elif g.roles[s] == "recluse":
			notes.append("Отшельник (%s) может определиться злым" % g.players[s].name)
	return notes

func _numeric(actor: int, truthful: Array, maximum: int, template: String) -> void:
	var options: Array = []
	for value in range(maximum + 1):
		if not healthy(actor) or truthful.has(value):
			var text := template % value
			options.append({"label": text, "text": text})
	_information(actor, options)

func _boolean_information(actor: int, truthful: Array, template: String) -> void:
	var options: Array = []
	for value: bool in [false, true]:
		if not healthy(actor) or truthful.has(value):
			var text := template % ("да" if value else "нет")
			options.append({"label": text, "text": text})
	_information(actor, options)

func _role_information(actor: int, target: int, template: String) -> void:
	var options: Array = []
	for id: String in g.catalog:
		if g.catalog[id].edition != g.edition:
			continue
		if not healthy(actor) or _role_options(target).has(id):
			var text := template % str(g.catalog[id].name)
			options.append({"label": text, "text": text})
	_information(actor, options)

func _chef_values() -> Array:
	var circle: Array = g.seats_in_circle()
	var assignments: Array = [[]]
	for s: int in circle:
		var next: Array = []
		for prior: Array in assignments:
			for evil: bool in _side_options(s):
				var entry := prior.duplicate()
				entry.append(evil)
				next.append(entry)
		assignments = next
	var result: Array = []
	for assignment: Array in assignments:
		var count := 0
		for i in assignment.size():
			if assignment[i] and assignment[(i + 1) % assignment.size()]:
				count += 1
		if not result.has(count):
			result.append(count)
	return result

func _empath_values(actor: int) -> Array:
	var neighbors: Array = g.living_neighbors(actor)
	var result: Array = [0]
	for s: int in neighbors:
		var next: Array = []
		for prior: int in result:
			for evil: bool in _side_options(s):
				var value := prior + (1 if evil else 0)
				if not next.has(value):
					next.append(value)
		result = next
	return result

func _spy(actor: int) -> void:
	var actual: Array = g.grimoire()
	if healthy(actor):
		knowledge[actor] = {"grimoire": actual}
		g.add_private(actor, "Вы осмотрели гримуар этой ночью.")
		return
	var fake := actual.duplicate(true)
	for i in fake.size():
		fake[i].role = actual[(i + 1) % actual.size()].role
		fake[i].shown_role = fake[i].role
		fake[i].status = {}
	_choice(g.storyteller, "Нарушенная способность Шпиона: какой гримуар показать?", [
		{"label": "Настоящий гримуар", "snapshot": actual}, {"label": "Гримуар с переставленными ролями", "snapshot": fake}], {"op": "spy", "actor": actor})

func on_nominate(nominator: int, target: int) -> void:
	if not started or g.roles[target] != "virgin" or bool(g.status[target].get("virgin_used", false)):
		return
	g.status[target]["virgin_used"] = true
	if not active(target, "virgin"):
		return
	var possible: Array = []
	for id: String in _role_options(nominator):
		var value: bool = g.catalog[id].type == "townsfolk"
		if not possible.has(value):
			possible.append(value)
	if possible.size() == 1:
		if bool(possible[0]):
			_execution_event(nominator)
	else:
		_choice(g.storyteller, "Регистрация номинирующего при способности Девы", [
			{"label": "Определяется как горожанин", "value": true}, {"label": "Не определяется как горожанин", "value": false}], {"op": "virgin", "actor": nominator})

func _execution_event(target: int) -> void:
	g.event = {"text": "Казнь: %s" % g.players[target].name, "target": target}
	g.event_left = 1.0
	g._event_commit = {"op": "execution", "target": target}

func slay(actor: int, target: int) -> bool:
	if not started or not g.phase in ["discussion", "nominations", "defense", "voting"] or not g.alive[actor] or actor == g.storyteller:
		return false
	if not pending.is_empty() or not g.event.is_empty() or bool(g.status[actor].get("slayer_claimed", false)):
		return false
	g.status[actor]["slayer_claimed"] = true
	g.public_log.append("%s заявляет выстрел Истребителя в %s." % [g.players[actor].name, g.players[target].name])
	g.event = {"text": "%s заявляет выстрел в %s" % [g.players[actor].name, g.players[target].name], "target": target}
	g.event_left = 1.0
	g._event_commit = {"op": "slayer", "actor": actor, "target": target}
	return true

## Один и тот же текст при блефе, промахе и нарушенной способности — по альманаху «Ничего не произошло».
## Цель названа, чтобы итог читался без журнала.
func _slay_miss(target: int) -> void:
	g.public_log.append("Выстрел в %s: ничего не произошло." % g.players[target].name)

func complete_slay(actor: int, target: int) -> void:
	if not active(actor, "slayer"):
		_slay_miss(target)
		return
	var possible := _demon_options(target)
	if possible.size() == 1:
		if bool(possible[0]):
			var was_alive := bool(g.alive[target])
			_kill(target, actor, "slayer")
			if not was_alive or bool(g.alive[target]):
				_slay_miss(target)
		else:
			_slay_miss(target)
	else:
		_choice(g.storyteller, "Определяется ли цель Истребителя как демон?", [
			{"label": "Да", "value": true}, {"label": "Нет", "value": false}], {"op": "slayer", "actor": actor, "target": target})
	_check_win()

func execute(target: int) -> void:
	g.executed = target
	_kill(target, -1, "execution")
	if g.phase != "game_over":
		g.phase = "dusk"
		jobs.append({"op": "check_win"})
	_advance()

func _protected(target: int) -> bool:
	var source := int(g.status[target].get("monk_source", -1))
	return source >= 0 and active(source, "monk")

func _kill(target: int, source: int, cause: String, redirect: bool = true) -> void:
	if not bool(g.alive[target]):
		return
	if cause == "demon":
		if active(target, "soldier") or _protected(target):
			return
		if redirect and active(target, "mayor"):
			var options: Array = [_target_option(target)]
			options[0].label = "Мэр погибает сам"
			for s: int in g.seats_in_circle():
				if s != target and bool(g.alive[s]):
					options.append(_target_option(s))
			_choice(g.storyteller, "Мэр атакован ночью: можно перенаправить смерть", options,
				{"op": "mayor", "source": source})
			return
	var old_role := str(g.roles[target])
	var old_healthy := healthy(target)
	var before: int = g.alive_count()
	g.alive[target] = false
	if g.phase == "night":
		g.status[target]["died_night"] = true
		g.status[target]["raven_real"] = old_healthy
	else:
		g.announced_alive[target] = false
		g.public_log.append("%s погиб." % g.players[target].name)
	if cause == "execution":
		g.execution_death = target
		if old_role == "saint" and old_healthy:
			_win("evil" if g.sides[target] == "good" else "good")
			return
	if old_role == "imp":
		for s: int in g.seats_in_circle():
			if before >= 5 and active(s, "scarlet_woman"):
				_become_imp(s)
				_check_win()
				return
		if cause == "demon" and source == target and old_healthy:
			var options: Array = []
			for s: int in g.seats_in_circle():
				if g.alive[s] and g.catalog[g.roles[s]].type == "minion":
					options.append(_target_option(s))
			if not options.is_empty():
				_choice(g.storyteller, "Бес убил себя: выберите живого приспешника для передачи роли", options, {"op": "starpass"})
				return
	_check_win()

func _become_imp(seat: int) -> void:
	g.roles[seat] = "imp"
	g.shown_roles[seat] = "imp"
	g.add_private(seat, "Теперь ваша роль — Бес. Ваша сторона не изменилась.")

func dusk() -> void:
	if not started or g.phase != "dusk":
		return
	if g.executed < 0 and g.alive_count() == 3:
		for s: int in g.seats_in_circle():
			if active(s, "mayor"):
				_win("good")
				return
	_check_win()

func _check_win() -> void:
	if not str(g.winner).is_empty():
		return
	if not pending.is_empty() and pending.get("op") == "starpass":
		return
	var living_demon := false
	for s: int in g.seats_in_circle():
		if g.alive[s] and g.catalog[g.roles[s]].type == "demon":
			living_demon = true
	if not living_demon:
		_win("good")
	elif g.alive_count() <= 2:
		_win("evil")

func _win(side: String) -> void:
	if not str(g.winner).is_empty():
		return
	g.winner = side
	g.phase = "game_over"
	g.public_revision += 1
	g.requests.clear()
	pending.clear()
	waiting_choices.clear()
	jobs.clear()
	g.announced_alive = g.alive.duplicate()
	g.public_log.append("Победа добра." if side == "good" else "Победа зла.")
