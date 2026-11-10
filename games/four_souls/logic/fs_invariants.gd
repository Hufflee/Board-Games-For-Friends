extends RefCounted
## Four Souls: проверка целостности партии после любого действия (тесты, фаззер, debug-хост).
## check(g) возвращает список нарушений на русском; пустой список — всё в порядке.
## Запуск — из tests/fs/run.gd (FSScenario вызывает автоматически).

const PHASES := ["turn", "priority", "effect", "death", "battle_roll", "discard", "discard_target",
	"forced_discard", "starting_character", "starting_item", "game_over"]
## Колоды, карты которых физически перемещаются между зонами.
const PHYSICAL_KINDS := ["loot", "treasure", "monster", "event", "room"]

static var _pool_cache: Dictionary = {}

static func check(g: FSRules, hang_check: bool = true) -> Array[String]:
	var out: Array[String] = []
	var n: int = g.players.size()
	if g.skipped_turns.size() != n or g.skipped_turns.any(func(value): return int(value) < 0):
		out.append("Пропуски ходов: неверное число мест или отрицательный счётчик")
	# Монеты.
	var total: int = g.bank
	for seat in n:
		total += int(g.coins[seat])
		if int(g.coins[seat]) < 0:
			out.append("Монеты: у места %d отрицательно (%d)" % [seat, int(g.coins[seat])])
	if g.bank < 0:
		out.append("Монеты: банк отрицательный (%d)" % g.bank)
	if total != 100:
		out.append("Монеты: банк + у игроков = %d, а не 100" % total)
	# Здоровье и души.
	for seat in n:
		if int(g.hp[seat]) < 0 or int(g.hp[seat]) > int(g.max_hp[seat]):
			out.append("Здоровье: место %d — %d из %d" % [seat, int(g.hp[seat]), int(g.max_hp[seat])])
		var soul_value := 0
		for entry: Dictionary in g.soul_cards[seat]:
			soul_value += int(entry.value)
		if soul_value != int(g.souls[seat]):
			out.append("Души: место %d — счётчик %d, карты душ %d" % [seat, int(g.souls[seat]), soul_value])
	# Фаза и действующее лицо.
	if not g.phase in PHASES:
		out.append("Фаза: осталась служебная фаза «%s»" % g.phase)
	if g.phase == "effect" and g.resolving.is_empty():
		out.append("Фаза effect без разрешаемого эффекта")
		return out
	var who: int = g.actor()
	if who < 0 or who >= n:
		out.append("Действующее лицо: %d вне мест" % who)
	if g.current < 0 or g.current >= n:
		out.append("Текущий игрок: %d вне мест" % g.current)
	if g.battle >= g.monsters.size():
		out.append("Бой: ячейка %d, монстров %d" % [g.battle, g.monsters.size()])
	if g.phase == "priority" and g.stack.is_empty() and g.next_action.is_empty():
		out.append("Фаза priority при пустом стеке")
	out.append_array(_cards(g))
	out.append_array(_privacy(g))
	if hang_check and not preload("res://games/four_souls/logic/fs_legal.gd").anyone_can_act(g):
		out.append("Зависание: ни у одного места нет законного действия (фаза %s, actor %d)" % [g.phase, who])
	return out

## Каждая физическая карта ровно в одной зоне и ни одна не потеряна.
static func _cards(g: FSRules) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var where := {}
	var add := func(id, zone: String) -> void:
		var card := int(id)
		if card < 0 or not FSData.card(card).get("kind", "") in PHYSICAL_KINDS:
			return
		seen[card] = int(seen.get(card, 0)) + 1
		where[card] = str(where.get(card, "")) + (", " if where.has(card) else "") + zone
	for key in g.decks:
		for id in g.decks[key]: add.call(id, "колода " + key)
	for key in g.discards:
		for id in g.discards[key]: add.call(id, "сброс " + key)
	for seat in g.players.size():
		for id in g.hands[seat]: add.call(id, "рука %d" % seat)
		for entry: Dictionary in g.items[seat]:
			add.call(entry.get("physical_id13", entry.id), "предметы %d" % seat)
			for id in entry.get("stored_cards20", []):
				add.call(id, "под предметом %d" % int(entry.id))
		for entry: Dictionary in g.soul_cards[seat]: add.call(entry.id, "души %d" % seat)
		for id in g.curses[seat]: add.call(id, "проклятия %d" % seat)
	for slot in g.monsters.size():
		var entry: Dictionary = g.monsters[slot]
		var depth := 0
		while not entry.is_empty():
			if not entry.has("virtual_zone15"):
				add.call(entry.get("physical_id20", entry.id), "монстр %d/%d" % [slot, depth])
			entry = entry.get("under", {})
			depth += 1
	for id in g.shop: add.call(id, "магазин")
	if g.room >= 0: add.call(g.room, "комната")
	for entry: Dictionary in g._extra_rooms20:
		add.call(entry.get("physical_id13", entry.id), "дополнительная комната")
		for id in entry.get("stored_cards20", []):
			add.call(id, "под дополнительной комнатой")
	for choice: Dictionary in g._starting_choices:
		for id in choice.cards: add.call(id, "выбор Эдема")
	for id in g._outside_starters21:
		add.call(id, "заменённый стартовый предмет")
	# Карты внутри эффектов: лут в стеке и событие — физически вне колод.
	var held := {}
	for effect: Dictionary in _effects(g):
		var kind: String = str(effect.get("kind", ""))
		if effect.get("automation_data", {}).has("pending_soul16"):
			add.call(effect.automation_data.pending_soul16.id, "выбор получателя души")
		if kind == "loot" and not bool(effect.get("loot_copy14", false)) and not bool(effect.get("under_deck", false)) and not effect.has("given_to") and not bool(effect.get("kept_as_item", false)) and not bool(effect.get("deployed_monster20", false)):
			held[int(effect.card)] = true
		elif kind == "event" and not bool(effect.get("attached", false)):
			held[int(effect.card)] = true
	# Награда «оставлена душой» до завершения: карта ещё лежит в ячейке монстра.
	var allowed_twice := {}
	for effect: Dictionary in _effects(g):
		if str(effect.get("kind", "")) == "reward" and (bool(effect.get("kept_as_soul", false)) or bool(effect.get("kept_as_item", false))):
			allowed_twice[int(effect.card)] = true
		if str(effect.get("kind", "")) == "reward" and bool(effect.get("return_to_deck", false)):
			allowed_twice[int(effect.card)] = true
	for id in seen:
		var limit := 2 if allowed_twice.has(id) else 1
		if int(seen[id]) > limit or (held.has(id) and int(seen[id]) > 0):
			out.append("Карта %d (%s) в нескольких зонах: %s%s" % [id, FSData.title(id), where[id], " + эффект" if held.has(id) else ""])
	for id in _pool(g.dlc):
		if not seen.has(id) and not held.has(id):
			out.append("Карта %d (%s) потеряна — её нет ни в одной зоне" % [id, FSData.title(id)])
	return out

static func _effects(g: FSRules) -> Array:
	var list: Array = []
	for effect: Dictionary in g.stack:
		list.append(effect)
		if str(effect.get("kind", "")) == "resume_effect":
			list.append(effect.previous.effect)
	if not g.resolving.is_empty():
		list.append(g.resolving)
	for paused: Dictionary in g.paused_effects:
		list.append(paused.effect)
	return list

static func _pool(dlc: bool) -> Array:
	if not _pool_cache.has(dlc):
		var ids: Array = []
		for kind in PHYSICAL_KINDS:
			ids.append_array(FSData.pool(kind, dlc))
		_pool_cache[dlc] = ids
	return _pool_cache[dlc]

## Вид места не раскрывает чужие закрытые руки и чужой просмотр колоды.
static func _privacy(g: FSRules) -> Array[String]:
	var out: Array[String] = []
	for seat in g.players.size():
		var view: Dictionary = g.get_view(seat)
		if view.hand != g.hands[seat]:
			out.append("Приватность: место %d видит не свою руку" % seat)
		var public_reveal: bool = bool(g.peek.get("public", false)) and (int(g.resolving.get("card", -1)) in [106, 148, 151, 245, 725] or int(g.peek.get("source_card20", -1)) == 4) and not g.peek.has("hands")
		if not view.peek.is_empty() and int(view.peek.get("owner", -1)) != seat and not public_reveal:
			out.append("Приватность: место %d видит чужой просмотр" % seat)
		for other in g.players.size():
			if other == seat or not view.players[other].has("hand"):
				continue
			var x_ray := false
			for owner in g.players.size():
				if owner != other and g._item_count(owner, 128) > 0:
					x_ray = true
			if not x_ray:
				out.append("Приватность: место %d видит руку места %d без карты-рентгена" % [seat, other])
	return out
