class_name BCRules
extends RefCounted
## Чистое ядро Clocktower: подготовка, адресные состояния, дневные номинации и голосование.
## Полная очередь способностей ещё в разработке; в хаб не подключать до её приёмки.
## Проверка: --headless --audio-driver Dummy --path . --script res://tests/test_blood_on_the_clocktower.gd.

const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
const Abilities := preload("res://games/blood_on_the_clocktower/logic/bc_abilities.gd")
const BMR := preload("res://games/blood_on_the_clocktower/logic/bc_bmr.gd")
const SV := preload("res://games/blood_on_the_clocktower/logic/bc_sv.gd")
var abilities: RefCounted
var catalog: Dictionary = Data.catalog()
var players: Array = []
var roles: Array = []
var shown_roles: Array = []
var sides: Array = []
var alive: Array = []
var announced_alive: Array = []
var dead_votes: Array = []
var private_log: Array = []
var status: Array = []
var storyteller := -1
var edition := "tb"
var phase := "setup"
var day := 0
var winner := ""
var public_revision := 0
var public_log: Array = []
var requests: Dictionary = {}
var nominated: Array = []
var nominators: Array = []
var nominee := -1
var nominator := -1
var hands: Array = []
var counted: Array = []
var vote_order: Array = []
var vote_cursor := 0
var vote_total := 0
var leader := -1
var high_vote := 0
var executed := -1
var execution_death := -1
var event: Dictionary = {}
var event_left := 0.0
var _event_commit: Dictionary = {}
var bluffs: Array = []
## Последняя дневная пара шёпота: все видят, кто с кем говорит, но не текст (как в живой игре).
var last_whisper: Array = []
## После победы роли раскрыты у всех, а экран победы хост открывает кнопкой (решение владельца 06.11).
var victory_open := false
## Домашнее правило: ночные голоса живых приспешников за жертву демона {место: цель}. Видят только злые.
var evil_votes: Dictionary = {}
var rng := RandomNumberGenerator.new()

func new_game(seats: Array, options: Dictionary = {}, seed_value: int = -1) -> String:
	var selected_edition := str(options.get("bc_edition", "tb"))
	if not Data.EDITIONS.has(selected_edition):
		return "Неизвестный сценарий."
	var count := seats.size() - 1
	if count < int(Data.EDITIONS[selected_edition].minimum) or count > 15:
		return "Для этого сценария нужно от %d до 15 игроков плюс рассказчик." % int(Data.EDITIONS[selected_edition].minimum)
	var story := int(options.get("bc_storyteller", 0))
	if story < 0 or story >= seats.size():
		return "Выберите отдельного рассказчика."
	for person: Variant in seats:
		if not person is Dictionary or bool(person.get("bot", false)):
			return "Все участники должны быть людьми."
	var selected: Array = options.get("bc_roles", [])
	var setup_error := validate_setup(selected_edition, selected, count, int(options.get("bc_godfather_delta", 0)))
	if not setup_error.is_empty():
		return setup_error
	var fake_drunk := str(options.get("bc_drunk_role", ""))
	if selected.has("drunk"):
		if not fake_drunk in Data.roles(selected_edition, "townsfolk") or selected.has(fake_drunk):
			return "Для Пьяницы нужна отсутствующая в составе роль горожанина."
	var fake_lunatic := str(options.get("bc_lunatic_role", ""))
	if selected.has("lunatic") and not fake_lunatic in Data.roles(selected_edition, "demon"):
		return "Для Лунатика выберите роль демона этого сценария."
	var chosen_bluffs: Array = options.get("bc_bluffs", [])
	if chosen_bluffs.size() != 3:
		return "Выберите три отсутствующие добрые роли для блефа демона."
	var unique_bluffs: Dictionary = {}
	for id: Variant in chosen_bluffs:
		if not id is String or not catalog.has(id) or catalog[id].edition != selected_edition:
			return "Блеф должен быть ролью выбранного сценария."
		if catalog[id].side != "good" or selected.has(id) or id == fake_drunk or unique_bluffs.has(id):
			return "Блефы должны быть разными отсутствующими добрыми ролями."
		unique_bluffs[id] = true
	# Ошибки подготовки выше не меняют уже существующую партию.
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	players = []
	for person: Dictionary in seats:
		players.append({"name": str(person.get("name", "Игрок")).left(64), "color": int(person.get("color", 0))})
	edition = selected_edition
	storyteller = story
	roles = []
	shown_roles = []
	sides = []
	alive = []
	announced_alive = []
	dead_votes = []
	private_log = []
	status = []
	hands = []
	var bag := selected.duplicate()
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var value: Variant = bag[i]
		bag[i] = bag[j]
		bag[j] = value
	for seat in players.size():
		var id := "" if seat == story else str(bag.pop_back())
		roles.append(id)
		shown_roles.append(fake_drunk if id == "drunk" else (fake_lunatic if id == "lunatic" else id))
		sides.append("" if id.is_empty() else str(catalog[id].side))
		alive.append(seat != story)
		announced_alive.append(seat != story)
		dead_votes.append(true)
		private_log.append([])
		status.append({})
		hands.append(false)
	bluffs = chosen_bluffs.duplicate()
	last_whisper.clear()
	phase = "first_night"
	day = 0
	winner = ""
	victory_open = false
	evil_votes.clear()
	public_revision = 0
	public_log.clear()
	requests.clear()
	nominated.clear()
	nominators.clear()
	event.clear()
	_event_commit.clear()
	event_left = 0.0
	leader = -1
	high_vote = 0
	executed = -1
	execution_death = -1
	nominee = -1
	nominator = -1
	vote_order.clear()
	counted.clear()
	vote_cursor = 0
	vote_total = 0
	abilities = SV.new(self) if edition == "sv" else (BMR.new(self) if edition == "bmr" else Abilities.new(self))
	return ""

func validate_setup(chosen_edition: String, selected: Array, count: int, godfather_delta: int = 0) -> String:
	if not Data.EDITIONS.has(chosen_edition) or not Data.COUNTS.has(count):
		return "Недопустимый сценарий или число игроков."
	if count < int(Data.EDITIONS[chosen_edition].minimum):
		return "Для этого сценария требуется больше игроков."
	if selected.size() != count:
		return "Число ролей должно совпадать с числом игроков без рассказчика."
	if selected.has("godfather") and not godfather_delta in [-1, 1]:
		return "Крёстный отец изменяет число изгоев на +1 или −1."
	var seen: Dictionary = {}
	var actual := [0, 0, 0, 0]
	for id: Variant in selected:
		if not id is String or not catalog.has(id) or catalog[id].edition != chosen_edition:
			return "В составе есть роль другого сценария или неизвестная роль."
		if seen.has(id):
			return "Роли при подготовке не повторяются."
		seen[id] = true
		actual[["townsfolk", "outsider", "minion", "demon"].find(catalog[id].type)] += 1
	if actual != Data.population(count, selected, godfather_delta):
		return "Состав не соответствует таблице населения и изменениям выбранных ролей."
	return ""

func seats_in_circle() -> Array:
	var result: Array = []
	for seat in players.size():
		if seat != storyteller:
			result.append(seat)
	return result

func living_neighbors(seat: int) -> Array:
	var circle := seats_in_circle()
	var index := circle.find(seat)
	if index < 0:
		return []
	var result: Array = []
	for direction: int in [-1, 1]:
		for step in range(1, circle.size()):
			var target: int = circle[posmod(index + direction * step, circle.size())]
			if is_living_player(target):
				result.append(target)
				break
	return result

func is_living_player(seat: int) -> bool:
	return bool(abilities.counts_alive(seat)) if abilities != null and abilities.started else bool(alive[seat])

func voting_population() -> int:
	var result := 0
	for seat: int in seats_in_circle():
		if is_living_player(seat):
			result += 1
	return result

func alive_count(public: bool = false) -> int:
	var source: Array = announced_alive if public else alive
	var count := 0
	for seat: int in seats_in_circle():
		if bool(source[seat]):
			count += 1
	return count

## Ночной планировщик вызывает рассвет после завершения всех способностей, не клиент.
func dawn() -> void:
	day += 1
	phase = "discussion"
	requests.clear()
	for seat: int in seats_in_circle():
		var current: bool = bool(abilities.public_life(seat)) if abilities != null and abilities.started else bool(alive[seat])
		if bool(announced_alive[seat]) != current:
			public_log.append("%s %s." % [players[seat].name, "жив" if current else "погиб"])
		announced_alive[seat] = current
	nominated.clear()
	nominators.clear()
	last_whisper.clear()
	evil_votes.clear()
	hands.fill(false)
	counted.clear()
	vote_order.clear()
	nominee = -1
	nominator = -1
	leader = -1
	high_vote = 0
	executed = -1
	execution_death = -1
	public_revision += 1

func action(seat: int, kind: String, arg: Variant = {}) -> bool:
	if seat < 0 or seat >= players.size() or not arg is Dictionary or not event.is_empty() or phase == "game_over":
		return false
	# Публичная ревизия не растёт от приватных ночных операций.
	if kind == "whisper":
		var recipient := _target(arg)
		if recipient < 0 or recipient == seat or not arg.get("text") is String:
			return false
		var message := str(arg.text).strip_edges()
		if message.is_empty() or message.length() > 500:
			return false
		if phase in ["first_night", "night"] and seat != storyteller and recipient != storyteller:
			return false
		add_private(recipient, "Лично от %s: %s" % [players[seat].name, message])
		add_private(seat, "Лично для %s: %s" % [players[recipient].name, message])
		if not phase in ["first_night", "night"]:
			_note_whisper(seat, recipient)
		return true
	if kind == "private_reply":
		return _private_reply(seat, arg)
	# Голос приспешника приватный: ревизию не трогает, видят только злые.
	if kind == "evil_vote":
		return _evil_vote(seat, arg)
	if abilities != null and kind in ["artist", "savant"]:
		return abilities.private_action(seat, kind, arg)
	# Рука и подсчёт не сверяют общую ревизию: при голосовании руки поднимают одновременно,
	# и первое принятое нажатие не должно молча отклонять остальные.
	if kind in ["hand", "count_vote"]:
		if abilities != null and abilities.blocking_choice():
			return false
		var accepted := _hand(seat, arg) if kind == "hand" else _count_request(seat, arg)
		if accepted:
			public_revision += 1
		return accepted
	if not arg.get("revision") is int or int(arg.revision) != public_revision:
		return false
	if abilities != null and seat == storyteller and kind in ["tinker", "madness_execution"]:
		var accepted: bool = abilities.extra_action(seat, kind, arg)
		if accepted and phase != "night":
			public_revision += 1
		return accepted
	if abilities != null and abilities.blocking_choice():
		return false
	var ok := false
	match kind:
		"begin_night":
			ok = abilities != null and abilities.begin(seat)
		"slay":
			var target := _target(arg)
			if target >= 0 and target != storyteller and abilities != null:
				ok = abilities.slay(seat, target)
		"open_nominations":
			if seat == storyteller and phase == "discussion":
				phase = "nominations"
				ok = true
		"nominate":
			if phase == "nominations" and seat != storyteller and is_living_player(seat) and not nominators.has(seat):
				var target := _target(arg)
				if target >= 0 and target != storyteller and not nominated.has(target) and can_be_nominated(target):
					nominator = seat
					nominee = target
					nominators.append(seat)
					nominated.append(target)
					phase = "defense"
					public_log.append("%s номинирует %s." % [players[seat].name, players[target].name])
					if abilities != null:
						abilities.on_nominate(seat, target)
					ok = true
		"start_vote":
			if seat == storyteller and phase == "defense":
				phase = "voting"
				hands.fill(false)
				counted.clear()
				vote_order = _order_after(nominee)
				vote_cursor = 0
				vote_total = 0
				ok = true
		"close_day":
			if seat == storyteller and phase == "nominations":
				if leader >= 0:
					event = {"text": "Казнь: %s" % players[leader].name, "target": leader}
					event_left = 1.0
					_event_commit = {"op": "execution", "target": leader}
				else:
					phase = "dusk"
					public_log.append("День завершился без казни.")
					if abilities != null:
						abilities.dusk()
				ok = true
		_:
			if abilities != null:
				ok = abilities.extra_action(seat, kind, arg)
	if ok:
		public_revision += 1
	return ok

## Днём шёпот виден всем как факт разговора, без текста. Строка в журнале — только при смене пары,
## чтобы переписка туда-обратно не засыпала журнал. Ревизию не трогаем: шёпот не должен
## отклонять одновременные номинации и голоса.
func _note_whisper(seat: int, recipient: int) -> void:
	var pair := [mini(seat, recipient), maxi(seat, recipient)]
	if pair == last_whisper:
		return
	last_whisper = pair
	if storyteller in pair:
		var player := recipient if seat == storyteller else seat
		public_log.append("%s говорит с рассказчиком." % players[player].name)
	else:
		public_log.append("%s и %s шепчутся." % [players[pair[0]].name, players[pair[1]].name])

## Владелец 06.11: мёртвых не номинировать (правила это разрешают). Исключение — «Дурная луна»:
## там Зомбуул после первой смерти выглядит мёртвым, и победить его можно только казнью «мёртвого».
func can_be_nominated(target: int) -> bool:
	return edition == "bmr" or bool(announced_alive[target])

## Ночное голосование приспешников — подсказка демону (домашнее правило, только 7+ игроков).
func evil_vote_open() -> bool:
	return phase == "night" and seats_in_circle().size() >= 7

func is_real_evil_team(seat: int) -> bool:
	if seat < 0 or seat >= roles.size() or seat == storyteller:
		return false
	return str(catalog[roles[seat]].type) in ["minion", "demon"]

func _evil_vote(seat: int, arg: Dictionary) -> bool:
	if not evil_vote_open() or not is_real_evil_team(seat) or str(catalog[roles[seat]].type) != "minion":
		return false
	if not is_living_player(seat):
		return false
	var target := _target(arg)
	if target < 0 or target == storyteller:
		return false
	evil_votes[seat] = target
	return true

func _target(arg: Dictionary) -> int:
	if not arg.get("target") is int:
		return -1
	var target := int(arg.target)
	return target if target >= 0 and target < players.size() else -1

func _order_after(seat: int) -> Array:
	var circle := seats_in_circle()
	var index := circle.find(seat)
	var result: Array = []
	for step in range(1, circle.size() + 1):
		result.append(circle[(index + step) % circle.size()])
	return result

## Рука — абсолютное значение («поднята»/«опущена»), поэтому повтор и устаревший view безопасны.
func _hand(seat: int, arg: Dictionary) -> bool:
	if phase != "voting" or seat == storyteller or counted.has(seat) or not arg.get("raised") is bool:
		return false
	if not is_living_player(seat) and not bool(dead_votes[seat]):
		return false
	hands[seat] = bool(arg.raised)
	return true

## Подсчёт сверяет ожидаемого голосующего: двойное нажатие не посчитает следующего игрока.
## Без поля voter — прежняя сверка общей ревизии.
func _count_request(seat: int, arg: Dictionary) -> bool:
	if seat != storyteller or phase != "voting" or vote_cursor >= vote_order.size():
		return false
	if arg.get("voter") is int:
		if int(arg.voter) != int(vote_order[vote_cursor]):
			return false
	elif not arg.get("revision") is int or int(arg.revision) != public_revision:
		return false
	_count_vote()
	return true

func _count_vote() -> void:
	var voter: int = vote_order[vote_cursor]
	counted.append(voter)
	if bool(hands[voter]) and (is_living_player(voter) or bool(dead_votes[voter])):
		vote_total += 1
		if abilities != null and abilities.started:
			abilities.on_vote(voter)
		if not is_living_player(voter):
			dead_votes[voter] = false
	vote_cursor += 1
	if vote_cursor < vote_order.size():
		return
	public_log.append("За %s: %d. Нужно не меньше %d." % [players[nominee].name, vote_total, ceili(voting_population() / 2.0)])
	if vote_total >= ceili(voting_population() / 2.0):
		if vote_total > high_vote:
			leader = nominee
			high_vote = vote_total
		elif vote_total == high_vote:
			leader = -1
	phase = "nominations"
	nominee = -1
	nominator = -1

## Изменение смерти только после показа. Защиты и триггеры должен обработать планировщик способностей.
func tick(delta: float) -> bool:
	if event.is_empty() or not is_finite(delta) or delta <= 0.0:
		return false
	event_left = maxf(0.0, event_left - delta)
	if event_left > 0.0:
		return false
	var commit := _event_commit.duplicate(true)
	_event_commit.clear()
	event.clear()
	if commit.get("op") == "execution":
		if abilities != null and abilities.started:
			abilities.execute(int(commit.target))
		else:
			executed = int(commit.target)
			if bool(alive[executed]):
				alive[executed] = false
				announced_alive[executed] = false
				execution_death = executed
			public_log.append("%s казнён." % players[executed].name)
			phase = "dusk"
	elif commit.get("op") == "slayer" and abilities != null:
		abilities.complete_slay(int(commit.actor), int(commit.target))
	elif abilities != null:
		abilities.commit_extra(commit)
	public_revision += 1
	return true

## Только хостовый планировщик создаёт адресный запрос. Клиент не задаёт список допустимых ответов.
## hint — пояснение адресату, почему вариантов несколько (рассказчику: регистрации, яд, Вортокс).
func request_choice(recipient: int, title: String, allowed: Array, hint: String = "") -> String:
	if recipient < 0 or recipient >= players.size() or allowed.is_empty() or requests.has(recipient):
		return ""
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	requests[recipient] = {"token": token, "title": title, "options": allowed.duplicate(true)}
	if not hint.is_empty():
		requests[recipient]["hint"] = hint
	return token

func _private_reply(seat: int, arg: Dictionary) -> bool:
	if not requests.has(seat) or not arg.get("token") is String or not arg.get("index") is int:
		return false
	var request: Dictionary = requests[seat]
	if str(arg.token) != str(request.token):
		return false
	var index := int(arg.index)
	if index < 0 or index >= request.options.size():
		return false
	# Очередь способностей прочитает ответ с хоста; публичное состояние не меняется.
	var selected: Variant = request.options[index].duplicate(true) if request.options[index] is Dictionary else request.options[index]
	requests.erase(seat)
	if abilities != null and not abilities.pending.is_empty():
		abilities.receive(seat, selected)
	else:
		status[seat]["reply"] = selected
	return true

func add_private(recipient: int, text: String) -> void:
	if recipient >= 0 and recipient < private_log.size():
		private_log[recipient].append(text)

## Белый список: никогда не копировать сырые роли/состояния в публичных игроков.
func get_view(seat: int) -> Dictionary:
	var public_players: Array = []
	for i in players.size():
		public_players.append({"name": players[i].name, "color": players[i].color, "storyteller": i == storyteller,
			"alive": bool(announced_alive[i]), "dead_vote": bool(dead_votes[i]), "hand": bool(hands[i]),
			# Заявленный выстрел Истребителя публичен; повторно заявить нельзя.
			"slayer_shot": bool(status[i].get("slayer_claimed", false))})
	var result := {"you": seat, "players": public_players, "edition": edition,
		"phase": "night" if phase in ["first_night", "night"] else phase,
		"day": day, "revision": public_revision, "log": public_log.duplicate(),
		"nominee": nominee, "nominator": nominator, "leader": leader, "high_vote": high_vote,
		"event": event.duplicate(true), "event_left": event_left, "winner": winner,
		"clock": false, "executed": executed, "last_whisper": last_whisper.duplicate(), "victory_open": victory_open,
		"nominated": nominated.duplicate(), "nominators": nominators.duplicate()}
	result["storyteller"] = storyteller
	if phase == "game_over":
		var winners: Array = []
		var revealed: Array = []
		for s: int in seats_in_circle():
			if sides[s] == winner:
				winners.append(s)
			revealed.append({"seat": s, "role": roles[s], "side": sides[s]})
		result["winners"] = winners
		result["revealed"] = revealed
	if phase == "voting":
		result["counted"] = counted.duplicate()
		result["vote_total"] = vote_total
		result["next_voter"] = int(vote_order[vote_cursor]) if vote_cursor < vote_order.size() else -1
	if seat >= 0 and seat < players.size():
		result["messages"] = private_log[seat].duplicate()
		if requests.has(seat):
			result["request"] = requests[seat].duplicate(true)
		if seat != storyteller:
			result["role"] = shown_roles[seat]
			result["side"] = "evil" if roles[seat] == "lunatic" else sides[seat]
			if abilities != null and abilities.knowledge.has(seat):
				result["knowledge"] = abilities.knowledge[seat].duplicate(true)
			if is_real_evil_team(seat) and seats_in_circle().size() >= 7:
				result["evil_vote_open"] = evil_vote_open() and str(catalog[roles[seat]].type) == "minion" and is_living_player(seat)
				var votes: Array = []
				for voter: int in evil_votes:
					votes.append({"from": voter, "target": int(evil_votes[voter])})
				result["evil_votes"] = votes
		if seat == storyteller:
			result["grimoire"] = grimoire()
	return result

func can_spectate() -> bool:
	return false

func grimoire() -> Array:
	var result: Array = []
	for seat: int in seats_in_circle():
		result.append({"seat": seat, "role": roles[seat], "shown_role": shown_roles[seat], "side": sides[seat],
			"alive": bool(alive[seat]), "status": status[seat].duplicate(true),
			"healthy": bool(abilities.healthy(seat)) if abilities != null else roles[seat] != "drunk"})
	return result
