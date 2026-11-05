class_name MKRules
extends RefCounted
## Хостовые правила Мачи Коро, без UI/Net/Steam. Начисления применяются по завершении события.
## Запуск проверок: --headless --audio-driver Dummy --path . --script res://tests/test_machi_koro.gd.

const Data := preload("res://games/machi_koro/logic/mk_data.gd")
var cards: Dictionary = Data.catalog()
var players: Array = []
var cities: Array = []
var coins: Array = []
var built: Array = []
var reserve: Dictionary = {}
var deck: Array = []
var plus := false
var sharp := false
var limited := false
var phase := "setup"
var current := 0
var round_no := 1
var turn_no := 1
var revision := 0
var winner := -1
var dice: Array = []
var main_dice: Array = []
var result := 0
var throw_serial := 0
var rerolled := false
var event: Dictionary = {}
var event_left := 0.0
var event_serial := 0
var choice: Dictionary = {}
var jobs: Array = []
var log: Array = []
var next_uid := 1
var rng := RandomNumberGenerator.new()

func new_game(seats: Array, options: Dictionary = {}, seed_value: int = -1) -> String:
	if seats.size() < 2 or seats.size() > 5:
		return "Нужно от 2 до 5 игроков."
	players = seats.duplicate(true)
	for p: Dictionary in players:
		p["bot"] = false
	plus = bool(options.get("mk_plus", false))
	sharp = bool(options.get("mk_sharp", false))
	limited = bool(options.get("mk_limited", false))
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	cities.clear()
	coins.clear()
	built.clear()
	reserve.clear()
	deck.clear()
	jobs.clear()
	log.clear()
	event.clear()
	choice.clear()
	next_uid = 1
	revision = 0
	event_serial = 0
	throw_serial = 0
	winner = -1
	round_no = 1
	turn_no = 1
	for s in players.size():
		cities.append([])
		coins.append(3)
		built.append([])
		_add_card(s, "wheat")
		_add_card(s, "bakery")
	for id: String in cards:
		var card: Dictionary = cards[id]
		if card.set == "plus" and not plus or card.set == "sharp" and not sharp:
			continue
		if limited:
			for k in int(card.copies):
				deck.append(id)
		else:
			reserve[id] = int(card.copies)
	_shuffle(deck)
	_refill()
	current = rng.randi_range(0, players.size() - 1)
	_start_turn()
	return ""

func _shuffle(values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = values[i]
		values[i] = values[j]
		values[j] = tmp

func _refill() -> void:
	if not limited:
		return
	while reserve.size() < 10 and not deck.is_empty():
		var id: String = deck.pop_back()
		reserve[id] = int(reserve.get(id, 0)) + 1

func _add_card(seat: int, id: String) -> void:
	cities[seat].append({"uid": next_uid, "id": id, "closed": false, "fund": 0})
	next_uid += 1

func _start_turn() -> void:
	dice.clear()
	main_dice.clear()
	result = 0
	rerolled = false
	phase = "roll"
	_note("Ход %s" % players[current].name)

func player_count() -> int:
	return players.size()

func can_spectate() -> bool:
	return false  # Без ботов нельзя отдавать участвующее место автоматике.

func count_icon(seat: int, icon: String) -> int:
	var count := 0
	for instance: Dictionary in cities[seat]:
		if cards[instance.id].icon == icon:
			count += 1
	return count

func count_type(seat: int, id: String) -> int:
	var count := 0
	for instance: Dictionary in cities[seat]:
		if instance.id == id:
			count += 1
	return count

func action(seat: int, kind: String, data: Variant = {}) -> bool:
	if seat != current or seat < 0 or seat >= players.size() or not data is Dictionary:
		return false
	if not data.get("revision") is int or int(data.revision) != revision or not event.is_empty():
		return false
	var accepted := false
	match kind:
		"roll":
			if phase == "roll" and data.get("count") is int:
				var n: int = data.count
				if n == 1 or n == 2 and built[current].has("station"):
					_roll(n)
					accepted = true
			elif phase == "trawler":
				_roll_trawler()
				accepted = true
		"keep":
			if phase == "reroll":
				_after_dice()
				accepted = true
		"reroll":
			if phase == "reroll" and not rerolled:
				rerolled = true
				_roll(main_dice.size())
				accepted = true
		"harbor":
			if phase == "harbor" and data.get("add") is bool:
				if data.add:
					result += 2
					_note("Порт: +2 к результату, итог %d" % result)
				_resolve()
				accepted = true
		"choose":
			if phase == "choice" and data.get("index") is int:
				var index: int = data.index
				if index >= 0 and index < choice.options.size():
					_choose(choice.options[index].value)
					accepted = true
		"buy":
			if phase == "build" and data.get("card") is String:
				accepted = _buy(str(data.card))
		"landmark":
			if phase == "build" and data.get("card") is String:
				accepted = _build(str(data.card))
		"pass":
			if phase == "build":
				if built[current].has("airport"):
					_show("Аэропорт: отказ от строительства, +10 монет", [_money(-1, current, 10)], "end", "airport")
				else:
					_end_turn()
				accepted = true
	if accepted:
		revision += 1
	return accepted

func _roll(n: int) -> void:
	dice.clear()
	for k in n:
		dice.append(rng.randi_range(1, 6))
	main_dice = dice.duplicate()
	result = 0
	for value: int in dice:
		result += value
	throw_serial += 1
	_show("Бросок: %s = %d" % [str(dice), result], [], "dice", "", 2.2)

func _after_dice() -> void:
	if built[current].has("harbor") and result >= 10:
		phase = "harbor"
	else:
		_resolve()

func _resolve() -> void:
	jobs.clear()
	# Красные выплаты идут от ближайшего соперника против часовой стрелки.
	for step in range(1, players.size()):
		var seat := (current - step + players.size()) % players.size()
		_add_activations(seat, "red")
	for seat in players.size():
		_add_activations(seat, "blue")
	_add_activations(current, "green")
	_add_activations(current, "purple")
	jobs.append({"kind": "build"})
	_pump()

func _add_activations(seat: int, color: String) -> void:
	for instance: Dictionary in cities[seat]:
		var card: Dictionary = cards[instance.id]
		if card.color == color and card.rolls.has(result):
			jobs.append({"kind": "activate", "seat": seat, "uid": instance.uid})

func _pump() -> void:
	phase = "resolution"
	while event.is_empty() and phase == "resolution" and not jobs.is_empty():
		var job: Dictionary = jobs.pop_front()
		match str(job.kind):
			"activate":
				_activate(int(job.seat), int(job.uid))
			"build":
				if plus and int(coins[current]) == 0:
					_show("Ратуша: перед строительством +1 монета", [_money(-1, current, 1)], "build", "townhall")
				else:
					phase = "build"
			"end":
				_finish_turn()
			"invest":
				var instance := _instance(current, int(job.uid))
				if not instance.is_empty() and int(coins[current]) > 0:
					_ask("invest", "Вложить 1 монету в Венчурный фонд?", [{"value": true, "label": "Вложить 1 монету"}, {"value": false, "label": "Не вкладывать"}], {"uid": int(job.uid)})

func _instance(seat: int, uid: int) -> Dictionary:
	for instance: Dictionary in cities[seat]:
		if int(instance.uid) == uid:
			return instance
	return {}

func _activate(seat: int, uid: int) -> void:
	var instance := _instance(seat, uid)
	if instance.is_empty():
		return
	var id: String = instance.id
	var card: Dictionary = cards[id]
	if instance.closed:
		_show("%s: предприятие снова открыто, доход пропущен" % card.title, [{"op": "closed", "seat": seat, "uid": uid, "value": false}], "pump", id)
		return
	var amount: int = card.amount
	var mall := 1 if built[seat].has("mall") and card.icon in ["shop", "cup"] else 0
	var mutations: Array = []
	match str(card.op):
		"income":
			mutations.append(_money(-1, seat, amount + mall))
		"cow", "gear", "crop", "cup", "flower":
			mutations.append(_money(-1, seat, count_icon(seat, str(card.op)) * (amount + mall)))
		"corn", "general":
			if built[seat].size() <= 1:
				mutations.append(_money(-1, seat, amount + mall))
		"boat":
			if built[seat].has("harbor"):
				mutations.append(_money(-1, seat, amount))
		"trawler":
			if not built[seat].has("harbor"):
				return
			# Все подходящие Траулеры получают один общий дополнительный бросок.
			var owners: Array = [seat]
			var kept: Array = []
			for job: Dictionary in jobs:
				var other: Dictionary = _instance(int(job.get("seat", 0)), int(job.get("uid", -1))) if job.kind == "activate" else {}
				if not other.is_empty() and other.id == "trawler" and not other.closed and built[int(job.seat)].has("harbor"):
					owners.append(int(job.seat))
				else:
					kept.append(job)
			jobs = kept
			choice = {"owners": owners}
			phase = "trawler"
			return
		"charge", "sushi", "french", "club":
			if card.op == "sushi" and not built[seat].has("harbor"):
				return
			if card.op == "french" and built[current].size() < 2 or card.op == "club" and built[current].size() < 3:
				return
			mutations.append(_money(current, seat, int(coins[current]) if card.op == "club" else amount + mall))
		"loan":
			mutations.append(_money(seat, -1, amount))
		"winery":
			mutations.append(_money(-1, seat, amount * count_type(seat, "vineyard")))
			mutations.append({"op": "closed", "seat": seat, "uid": uid, "value": true})
		"beverage":
			var count := 0
			for s in players.size():
				count += count_icon(s, "cup")
			mutations.append(_money(-1, seat, count))
		"stadium", "publisher", "tax", "venture":
			for step in range(1, players.size()):
				var s := (seat - step + players.size()) % players.size()
				var due := amount
				if card.op == "publisher":
					due = count_icon(s, "shop") + count_icon(s, "cup")
				elif card.op == "tax":
					due = int(coins[s]) / 2 if int(coins[s]) >= 10 else 0
				elif card.op == "venture":
					due = int(instance.fund)
				mutations.append(_money(s, seat, due))
		"park":
			var total := 0
			for balance: int in coins:
				total += balance
			var each := ceili(float(total) / players.size())
			mutations.append({"op": "park", "value": each})
		"tv", "business", "shipping":
			var opts := _opponents()
			if card.op != "tv":
				opts.append({"value": -1, "label": "Отказаться"})
			_ask(str(card.op), "%s: выберите игрока" % card.title, opts, {"card": id, "uid": uid})
			return
		"demolition":
			var opts: Array = []
			for landmark: String in built[seat]:
				opts.append({"value": landmark, "label": Data.LANDMARKS[landmark].title})
			if opts.is_empty():
				return
			_ask("demolition", "Выберите достопримечательность для сноса", opts, {"card": id})
			return
		"cleaning":
			var opts: Array = []
			var seen: Array = []
			for city: Array in cities:
				for inst: Dictionary in city:
					if cards[inst.id].color != "purple" and not seen.has(inst.id):
						seen.append(inst.id)
						opts.append({"value": inst.id, "label": cards[inst.id].title})
			if opts.is_empty():
				return
			_ask("cleaning", "Какой тип предприятий временно закрыть?", opts, {"card": id})
			return
	if not mutations.is_empty():
		_show(str(card.title), mutations, "pump", id)

func _roll_trawler() -> void:
	dice = [rng.randi_range(1, 6), rng.randi_range(1, 6)]
	throw_serial += 1
	var sum: int = dice[0] + dice[1]
	var mutations: Array = []
	for seat: int in choice.owners:
		mutations.append(_money(-1, seat, sum))
	choice.clear()
	_show("Траулеры: отдельный бросок %s, доход %d за каждый" % [str(dice), sum], mutations, "pump", "trawler", 3.0)

func _opponents() -> Array:
	var opts: Array = []
	for s in players.size():
		if s != current:
			opts.append({"value": s, "label": str(players[s].name)})
	return opts

func _ask(kind: String, text: String, options: Array, context: Dictionary = {}) -> void:
	phase = "choice"
	choice = {"kind": kind, "text": text, "options": options, "context": context}

func _card_options(seat: int) -> Array:
	var opts: Array = []
	for instance: Dictionary in cities[seat]:
		if cards[instance.id].color != "purple":
			opts.append({"value": instance.uid, "label": "%s%s · №%d" % [cards[instance.id].title, " (закрыто)" if instance.closed else "", instance.uid]})
	return opts

func _choose(value: Variant) -> void:
	var kind: String = choice.kind
	var context: Dictionary = choice.context.duplicate(true)
	choice.clear()
	var mutations: Array = []
	match kind:
		"tv":
			mutations.append(_money(int(value), current, 5))
		"business", "shipping":
			if int(value) < 0:
				_pump()
				return
			context["target"] = int(value)
			var opts := _card_options(current)
			opts.append({"value": -1, "label": "Отказаться"})
			_ask(kind + "_own", "Выберите своё предприятие для передачи", opts, context)
			return
		"business_own", "shipping_own":
			if int(value) < 0:
				_pump()
				return
			context["own"] = int(value)
			if kind == "business_own":
				var opts := _card_options(int(context.target))
				opts.append({"value": -1, "label": "Отказаться"})
				_ask("business_other", "Выберите предприятие взамен", opts, context)
				return
			mutations.append({"op": "transfer", "from": current, "to": context.target, "uid": value})
			mutations.append(_money(-1, current, 4))
		"business_other":
			if int(value) < 0:
				_pump()
				return
			mutations.append({"op": "transfer", "from": current, "to": context.target, "uid": context.own})
			mutations.append({"op": "transfer", "from": context.target, "to": current, "uid": value})
		"demolition":
			mutations.append({"op": "landmark", "seat": current, "id": value, "value": false})
			mutations.append(_money(-1, current, 8))
		"cleaning":
			for s in players.size():
				var count := 0
				for instance: Dictionary in cities[s]:
					if instance.id == value and not instance.closed:
						count += 1
						mutations.append({"op": "closed", "seat": s, "uid": instance.uid, "value": true})
				if s != current:
					mutations.append(_money(s, current, count))
		"invest":
			if bool(value):
				mutations.append(_money(current, -1, 1))
				mutations.append({"op": "fund", "seat": current, "uid": context.uid})
			else:
				_pump()
				return
	_show("%s: выбор принят" % str(cards.get(context.get("card", "venture"), {}).get("title", "Эффект")), mutations, "pump", str(context.get("card", "venture")))

func _money(source: int, target: int, amount: int) -> Dictionary:
	var actual := maxi(0, amount)
	if source >= 0:
		actual = mini(actual, int(coins[source]))
	return {"op": "money", "from": source, "to": target, "amount": actual, "requested": amount}

func can_buy(id: String) -> bool:
	return phase == "build" and event.is_empty() and cards.has(id) and int(reserve.get(id, 0)) > 0 and int(coins[current]) >= int(cards[id].cost) and (cards[id].color != "purple" or count_type(current, id) == 0)

func _buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var mutations: Array = [_money(current, -1, int(cards[id].cost)), {"op": "buy", "seat": current, "id": id}]
	if id == "loan":
		# Бонус банка — отдельное событие после строительства, не от передачи карты.
		jobs = [{"kind": "end"}]
		_show("Строительство: %s" % cards[id].title, mutations, "loan", id)
	else:
		_show("Строительство: %s" % cards[id].title, mutations, "end", id)
	return true

func _build(id: String) -> bool:
	if not Data.landmarks(plus).has(id) or built[current].has(id) or int(coins[current]) < int(Data.LANDMARKS[id].cost):
		return false
	_show("Строительство: %s" % Data.LANDMARKS[id].title, [_money(current, -1, int(Data.LANDMARKS[id].cost)), {"op": "landmark", "seat": current, "id": id, "value": true}], "end", id)
	return true

func _end_turn() -> void:
	jobs.clear()
	for instance: Dictionary in cities[current]:
		if instance.id == "venture":
			jobs.append({"kind": "invest", "uid": instance.uid})
	jobs.append({"kind": "end"})
	_pump()

func _finish_turn() -> void:
	if built[current].has("amusement") and main_dice.size() == 2 and main_dice[0] == main_dice[1]:
		_note("Парк развлечений: ещё один ход")
	else:
		current = (current + 1) % players.size()
	turn_no += 1
	round_no = 1 + (turn_no - 1) / players.size()
	_start_turn()

func _show(text: String, mutations: Array, after: String, card: String = "", duration: float = 2.1) -> void:
	event_serial += 1
	var details: Array[String] = []
	for mutation: Dictionary in mutations:
		match str(mutation.op):
			"money":
				details.append(_money_text([mutation]).trim_prefix(" · "))
			"transfer":
				var instance := _instance(int(mutation.from), int(mutation.uid))
				details.append("%s: %s → %s" % [cards[instance.id].title if not instance.is_empty() else "Карта", players[int(mutation.from)].name, players[int(mutation.to)].name])
			"landmark":
				details.append(("Построить: " if mutation.value else "Снести: ") + str(Data.LANDMARKS[mutation.id].title))
			"closed":
				var instance := _instance(int(mutation.seat), int(mutation.uid))
				if not instance.is_empty():
					details.append("%s: %s" % [cards[instance.id].title, "временно закрыть" if mutation.value else "открыть без дохода"])
	duration += 0.3 * maxi(0, details.size() - 1)
	event_left = duration
	event = {"id": event_serial, "text": text, "detail": "\n".join(details), "card": card, "duration": duration, "mutations": mutations, "after": after}
	phase = "animation"

func tick(delta: float) -> bool:
	if event.is_empty() or delta <= 0.0 or not is_finite(delta):
		return false
	event_left = maxf(0.0, event_left - delta)
	if event_left > 0.0:
		return false
	var done := event.duplicate(true)
	event.clear()
	for mutation: Dictionary in done.mutations:
		_apply(mutation)
	_note(str(done.text) + _money_text(done.mutations))
	revision += 1
	if built[current].size() == Data.landmarks(plus).size():
		winner = current
		phase = "game_over"
		jobs.clear()
		return true
	match str(done.after):
		"dice":
			if built[current].has("radio") and not rerolled:
				phase = "reroll"
			else:
				_after_dice()
		"build":
			phase = "build"
		"end":
			_end_turn()
		"loan":
			_show("Кредитный банк: после строительства +5 монет", [_money(-1, current, 5)], "end", "loan")
		_:
			_pump()
	return true

func _apply(mutation: Dictionary) -> void:
	match str(mutation.op):
		"money":
			if int(mutation.from) >= 0:
				coins[int(mutation.from)] -= int(mutation.amount)
			if int(mutation.to) >= 0:
				coins[int(mutation.to)] += int(mutation.amount)
		"buy":
			reserve[mutation.id] -= 1
			if int(reserve[mutation.id]) == 0:
				reserve.erase(mutation.id)
			_add_card(int(mutation.seat), str(mutation.id))
			_refill()
		"landmark":
			if mutation.value:
				built[int(mutation.seat)].append(mutation.id)
			else:
				built[int(mutation.seat)].erase(mutation.id)
		"closed":
			var instance := _instance(int(mutation.seat), int(mutation.uid))
			if not instance.is_empty():
				instance.closed = mutation.value
		"transfer":
			var instance := _instance(int(mutation.from), int(mutation.uid))
			if not instance.is_empty():
				cities[int(mutation.from)].erase(instance)
				cities[int(mutation.to)].append(instance)
		"fund":
			var instance := _instance(int(mutation.seat), int(mutation.uid))
			if not instance.is_empty():
				instance.fund += 1
		"park":
			coins.fill(int(mutation.value))

func _money_text(mutations: Array) -> String:
	var parts: Array[String] = []
	for mutation: Dictionary in mutations:
		if mutation.op == "money":
			var source: String = "банк" if int(mutation.from) < 0 else str(players[int(mutation.from)].name)
			var target: String = "банк" if int(mutation.to) < 0 else str(players[int(mutation.to)].name)
			parts.append("%s → %s: %d%s" % [source, target, mutation.amount, " (из %d)" % mutation.requested if mutation.amount < mutation.requested else ""])
	return " · " + "; ".join(parts) if not parts.is_empty() else ""

func _note(text: String) -> void:
	log.append(text)
	if log.size() > 120:
		log.pop_front()

func get_view(seat: int) -> Dictionary:
	var shown_event := event.duplicate(true)
	shown_event.erase("after")
	return {"you": seat, "players": players.duplicate(true), "cities": cities.duplicate(true), "coins": coins.duplicate(), "built": built.duplicate(true), "reserve": reserve.duplicate(), "deck_count": deck.size(), "plus": plus, "sharp": sharp, "limited": limited, "phase": phase, "current": current, "turn": current, "round_no": round_no, "turn_no": turn_no, "revision": revision, "dice": dice.duplicate(), "main_dice": main_dice.duplicate(), "result": result, "throw_serial": throw_serial, "event": shown_event, "event_left": event_left, "choice": choice.duplicate(true), "log": log.duplicate(), "winner": winner, "clock": false}
