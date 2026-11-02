extends RefCounted
## Four Souls, тесты: построитель партии + драйвер действий. Заменяет разные make()/fixture().
##   var s := FSScenario.new(t).players(2).current(0).hand(1, [478]).item(0, 34) \
##   	.monster(0, 396, {"hp": 3}).coins(0, 5).build()
##   s.roll(6); s.ok(0, "attack", {"slot": 0}, "атака"); s.close(); s.expect("monsters.0.hp", 2)
## Карты переносятся из их текущих зон (ничего не создаётся из воздуха), после build()
## и после каждого действия вызывается FSInvariants.check.

const FSCheck = preload("res://tests/fs/fs_check.gd")
const FSScenario = preload("res://tests/fs/fs_scenario.gd")
const FSInvariants = preload("res://games/four_souls/logic/fs_invariants.gd")

var g: FSRules
var t: FSCheck
var hang_check := true
var _n := 2
var _dlc := false
var _seed := 77
var _ops: Array[Callable] = []
var _faces: Array = []
var _rules_type: GDScript = preload("res://games/four_souls/logic/fs_rules.gd")

func _init(check: FSCheck = null) -> void:
	t = check if check != null else FSCheck.new()

# --- построение ---

func rules_type(script: GDScript) -> FSScenario:
	_rules_type = script
	return self

func players(count: int) -> FSScenario:
	_n = count; return self
func dlc(on: bool = true) -> FSScenario:
	_dlc = on; return self
func with_seed(value: int) -> FSScenario:
	_seed = value; return self
func current(seat: int) -> FSScenario:
	_ops.append(func() -> void:
		g.current = seat; g.priority = seat
		g.character_ready[seat] = g._item_count(seat, 138) == 0)
	return self
## Персонаж по номеру карты: здоровье и вечный предмет заменяются.
func character(seat: int, card: int) -> FSScenario:
	_ops.append(func() -> void:
		var data: Dictionary = {}
		for entry: Dictionary in FSData.data().characters:
			if int(entry.card) == card: data = entry
		assert(not data.is_empty(), "Нет персонажа %d" % card)
		g.chars[seat] = card
		for i in range(g.items[seat].size() - 1, -1, -1):
			if bool(g.items[seat][i].eternal) and FSData.card(int(g.items[seat][i].id)).get("kind", "") == "eternal":
				g._remove_item(seat, i)
		g.max_hp[seat] = preload("res://games/four_souls/logic/fs_passives.gd").character_health(card); g.hp[seat] = g.max_hp[seat]
		if int(data.item) >= 0:
			g.items[seat].insert(0, FSData.item_entry(int(data.item), true)))
	return self
## Рука места становится ровно такой (прежние карты — под низ колоды лута).
func hand(seat: int, ids: Array) -> FSScenario:
	_ops.append(func() -> void:
		for id in g.hands[seat]: g.decks.loot.push_front(id)
		g.hands[seat].clear()
		for id in ids:
			_take(int(id)); g.hands[seat].append(int(id)))
	return self
func item(seat: int, id: int, fields: Dictionary = {}) -> FSScenario:
	_ops.append(func() -> void:
		_take(id); g._gain_item(seat, id)
		g.items[seat].back().merge(fields, true))
	return self
## Убрать все не вечные предметы места (в сброс сокровищ).
func no_items(seat: int) -> FSScenario:
	_ops.append(func() -> void:
		for i in range(g.items[seat].size() - 1, -1, -1):
			if not bool(g.items[seat][i].eternal):
				g._discard_item(int(g._remove_item(seat, i).id)))
	return self
func monster(slot: int, id: int, stats: Dictionary = {}) -> FSScenario:
	_ops.append(func() -> void:
		_take(id)
		var entry := {"id": id, "hp": FSData.stat(id, "hp", 1), "dc": FSData.stat(id, "dc", 4), "at": FSData.stat(id, "at", 1)}
		entry.merge(stats, true)
		if slot < g.monsters.size():
			var old: Dictionary = g.monsters[slot]
			while not old.is_empty():
				g.decks.monster.push_front(int(old.id)); old = old.get("under", {})
			g.monsters[slot] = entry
		else:
			g.monsters.append(entry))
	return self
func shop(slot: int, id: int) -> FSScenario:
	_ops.append(func() -> void:
		_take(id)
		if slot < g.shop.size():
			if int(g.shop[slot]) >= 0: g.decks.treasure.push_front(g.shop[slot])
			g.shop[slot] = id
		else:
			g.shop.append(id))
	return self
func curse(seat: int, id: int) -> FSScenario:
	_ops.append(func() -> void:
		_take(id); g.curses[seat].append(id))
	return self
## Карта в души места (значение 1).
func soul(seat: int, id: int) -> FSScenario:
	_ops.append(func() -> void:
		_take(id); g.soul_cards[seat].append({"id": id, "value": 1}); g.souls[seat] += 1)
	return self
## Карты наверх колоды (последняя в списке — самая верхняя).
func deck_top(kind: String, ids: Array) -> FSScenario:
	_ops.append(func() -> void:
		for id in ids:
			_take(int(id)); g.decks[kind].append(int(id)))
	return self
func discard(kind: String, ids: Array) -> FSScenario:
	_ops.append(func() -> void:
		for id in ids:
			_take(int(id)); g.discards[kind].append(int(id)))
	return self
## Текущая комната DLC (прежняя — в сброс комнат). Нужен .dlc().
func room(id: int) -> FSScenario:
	_ops.append(func() -> void:
		_take(id)
		if g.room >= 0: g.discards.room.append(g.room)
		g.room = id
		g._refresh_passive_stats())
	return self
func coins(seat: int, amount: int) -> FSScenario:
	_ops.append(func() -> void:
		var delta: int = amount - int(g.coins[seat])
		assert(g.bank >= delta, "В банке не хватает монет")
		g.bank -= delta; g.coins[seat] = amount)
	return self
func hp(seat: int, value: int) -> FSScenario:
	_ops.append(func() -> void: g.hp[seat] = value)
	return self
## Произвольная подготовка: func(g: FSRules) -> void.
func setup(callback: Callable) -> FSScenario:
	_ops.append(func() -> void: callback.call(g))
	return self

func build() -> FSScenario:
	g = _rules_type.new()
	var members: Array = []
	for i in _n:
		members.append({"name": ["Первый", "Второй", "Третий", "Четвёртый", "Пятый", "Шестой", "Седьмой", "Восьмой"][i]})
	g.new_game(members, _dlc, _seed)
	# Замыкание не удерживает Scenario → игру → то же замыкание.
	var faces := _faces
	var random := g._rng
	g.roll_source = func() -> int: return int(faces.pop_front()) if not faces.is_empty() else random.randi_range(1, 6)
	_finish_start()
	for op in _ops: op.call()
	_ops.clear()
	g._refresh_passive_stats()
	g._turn_allowances()
	if g.phase == "priority" and g.next_action.is_empty():
		g._finish_responses()
	inv("после build()")
	return self

func _finish_start() -> void:
	for i in 100:
		if g.phase == "starting_item":
			var seat := g.actor()
			g.action(seat, "choose_starting_item", {"card": int(g._starting_choices[0].cards[0])})
		elif g.phase == "priority":
			g._finish_responses()
		else:
			return

## Убрать карту из любой зоны (колоды, сбросы, руки, предметы, магазин, монстры).
func _take(id: int) -> void:
	for key in g.decks:
		if g.decks[key].has(id): g.decks[key].erase(id); return
	for key in g.discards:
		if g.discards[key].has(id): g.discards[key].erase(id); return
	for seat in g.players.size():
		if g.hands[seat].has(id): g.hands[seat].erase(id); return
		for i in g.items[seat].size():
			if int(g.items[seat][i].id) == id: g._remove_item(seat, i); return
	for i in g.shop.size():
		if int(g.shop[i]) == id: g.shop[i] = g._draw("treasure"); return
	for i in g.monsters.size():
		if int(g.monsters[i].id) == id:
			var under: Dictionary = g.monsters[i].get("under", {})
			if not under.is_empty(): g.monsters[i] = under
			else: g.monsters.remove_at(i); g._fill_monster(false, -1)
			return
	if g.room == id:
		g.room = g._draw("room"); return
	# Вечные предметы и персонажи не лежат в колодах — их можно выдавать без переноса.
	assert(not FSData.card(id).get("kind", "") in FSInvariants.PHYSICAL_KINDS, "Карта %d не найдена ни в одной зоне" % id)

# --- драйвер ---

## Следующие броски кубика (по порядку). Пустая очередь — обычный случайный бросок.
func roll(face: int, more: Array = []) -> FSScenario:
	_faces.append(face); _faces.append_array(more); return self

func ok(seat: int, kind: String, arg = null, message: String = "") -> bool:
	var before: int = g.revision
	var accepted := g.action(seat, kind, arg)
	var passed := t.check(accepted and g.revision != before, "%s: действие %s места %d принято%s" % [_label(message, kind), kind, seat, "" if accepted else " (отклонено, фаза " + g.phase + ")"])
	inv(_label(message, kind))
	return passed

func no(seat: int, kind: String, arg = null, message: String = "") -> bool:
	var before: int = g.revision
	var accepted := g.action(seat, kind, arg)
	var passed := t.check(not accepted and g.revision == before, "%s: действие %s места %d отклонено" % [_label(message, kind), kind, seat])
	inv(_label(message, kind))
	return passed

## Закрыть окно ответов (единственное место, знающее про _finish_responses).
func close(message: String = "закрыть ответы") -> FSScenario:
	g._finish_responses()
	g.revision += 1
	inv(message)
	return self

func effect(seat: int, op: String, fields: Dictionary = {}, message: String = "") -> bool:
	var arg := {"op": op}
	arg.merge(fields, true)
	return ok(seat, "effect", arg, message if message != "" else "операция " + op)

func expect(path: String, value, message: String = "") -> bool:
	return t.equal(value_at(path), value, message if message != "" else path)

func inv(where: String = "") -> void:
	for problem in FSInvariants.check(g, hang_check):
		t.check(false, "Инвариант [%s]: %s" % [where, problem])

func _label(message: String, kind: String) -> String:
	return message if message != "" else kind

## Значение по пути: «coins.0», «monsters.0.hp», «phase»; особые: «zone.ID», «hand_size.N», «item_ids.N», «size.поле».
func value_at(path: String):
	var parts := path.split(".")
	match parts[0]:
		"zone": return zone_of(int(parts[1]))
		"hand_size": return g.hands[int(parts[1])].size()
		"size": return g.get(parts[1]).size()
		"item_ids":
			var ids: Array = []
			for entry: Dictionary in g.items[int(parts[1])]: ids.append(int(entry.id))
			return ids
	var value = g.get(parts[0])
	for i in range(1, parts.size()):
		if value is Array:
			var index := int(parts[i])
			if index < 0 or index >= value.size(): return null
			value = value[index]
		elif value is Dictionary:
			value = value.get(parts[i], value.get(int(parts[i]), null)) if parts[i].is_valid_int() else value.get(parts[i])
		else:
			return null
	return value

## Где карта: «hand:1», «item:0», «soul:0», «curse:1», «monster:0», «shop», «room»,
## «deck:loot:top», «deck:loot», «discard:monster», «stack», «resolving», «нигде».
func zone_of(id: int) -> String:
	for key in g.decks:
		var deck: Array = g.decks[key]
		if deck.has(id):
			return "deck:%s:top" % key if int(deck.back()) == id else "deck:" + key
	for key in g.discards:
		if g.discards[key].has(id): return "discard:" + key
	for seat in g.players.size():
		if g.hands[seat].has(id): return "hand:%d" % seat
		for entry: Dictionary in g.items[seat]:
			if int(entry.id) == id: return "item:%d" % seat
		for entry: Dictionary in g.soul_cards[seat]:
			if int(entry.id) == id: return "soul:%d" % seat
		if g.curses[seat].has(id): return "curse:%d" % seat
	for slot in g.monsters.size():
		if int(g.monsters[slot].id) == id: return "monster:%d" % slot
	if g.shop.has(id): return "shop"
	if g.room == id: return "room"
	for effect: Dictionary in g.stack:
		if int(effect.get("card", -1)) == id: return "stack"
	if int(g.resolving.get("card", -1)) == id: return "resolving"
	return "нигде"
