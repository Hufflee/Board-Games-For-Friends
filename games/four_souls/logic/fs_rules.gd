class_name FSRules
extends RefCounted
const PassiveRules = preload("res://games/four_souls/logic/fs_passives.gd")
## Восемь мест и ручные эффекты оригинального стола. Хост ведёт колоды, приоритет,
## стек, бой, смерть и ресурсы; текст сложной карты выполняют люди через открытый журнал.
var players: Array = []
var dlc := false
var phase := "turn"
var current := 0
var priority := 0
var passes := 0
var next_action: Dictionary = {}
var stats_rolls: Array = []
var stats_risks: Array = []
var round_no := 1
var winner := -1
var revision := 0
var decks: Dictionary = {}
var discards: Dictionary = {}
var hands: Array = []
var items: Array = []
var chars: Array = []
var hp: Array = []
var max_hp: Array = []
var attack: Array = []
var coins: Array = []
var bank := 100
var souls: Array = []
var soul_cards: Array = []
var curses: Array = []
var character_ready: Array = []
var dead: Array = []
var free_loot := 1
var buy_left := 1
var attack_left := 1
var deck_attacks := 0
var required_deck_attacks := 0
var temporary_attack: Array = []
var _turn_attack_rolls: Dictionary = {}
var _next_roll_token: int = 0
var bought := false
var attacked := false
var monsters: Array = []
var monster_slots := 2
var shop: Array = []
var room := -1
var bonuses: Array = []
var claimed: Array = []
var stack: Array = []
var resolving: Dictionary = {}
var paused_effects: Array = []
var battle := -1
var battle_player := -1
var required_player_attacks := 0
var discard_choice: Dictionary = {}
var roll_no := 0
var last_roll := 0
var log: Array = []
var peek: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _after_stack := "turn"
var _death_queue: Array = []
var _death_resume := "turn"
var damage_shields: Array = []
var extra_turns: Array = []
var _ending_turn := false
var _discard_limit := 10
var _turn_resume := -1
var _end_after_deaths := false
var _end_discard_prepared := false
var _setting_up := false
var _room_bonuses: Array = []
var _character_attack_bonuses: Array = []
var _starting_choices: Array = []

func _advance_start() -> void:
	if not _starting_choices.is_empty():
		phase = "starting_item"
		_note("Эдем выбирает стартовый предмет")
	else:
		_begin_turn()
var bonus_progress := {"deaths": 0, "treasures": 0, "monsters": 0}

func _bonus_targets(id: int) -> Array:
	var result: Array = []
	var ready := false
	var least := 1000000
	if id in [692, 693, 696]:
		ready = int(bonus_progress[{692: "deaths", 693: "treasures", 696: "monsters"}[id]]) >= 6
	elif id == 694:
		for seat in players.size():
			ready = ready or int(souls[seat]) >= 2
			least = mini(least, int(souls[seat]))
	elif id == 695:
		for seat in players.size():
			ready = ready or items[seat].size() >= 4
			least = mini(least, items[seat].size())
	if ready:
		for seat in players.size():
			if room == 779 or curses[seat].has(744):
				continue
			if id == 694 and int(souls[seat]) != least:
				continue
			if id == 695 and items[seat].size() != least:
				continue
			result.append(seat)
	return result

## Обязательные триггеры идут в общий стек и разрешаются после окна ответов.
func _emit_passives(event: String, data: Dictionary = {}) -> void:
	if _setting_up:
		return
	for seat in players.size():
		for item: Dictionary in items[seat].duplicate():
			var operations := PassiveRules.event_ops(self, seat, item, event, data)
			if not operations.is_empty():
				_queue_passive(seat, int(item.id), item, operations)

func _queue_passive(seat: int, id: int, source: Dictionary, operations: Array) -> void:
	var resume: String = _after_stack if phase == "priority" else phase
	_push({"kind": "passive", "card": id, "owner": seat, "source": source, "operations": operations}, resume)

## Передача внутри игры сохраняет источник; уход и новая копия с тем же ID — другой объект.
func _source_item_in_play(source: Dictionary) -> bool:
	for inventory: Array in items:
		for entry: Dictionary in inventory:
			if is_same(entry, source):
				return true
	return false

func _resolve_passive(effect: Dictionary) -> void:
	var seat: int = effect.owner
	for operation: Dictionary in effect.operations:
		var amount: int = operation.amount
		match str(operation.op):
			"counter": effect.source.counters = maxi(0, int(effect.source.counters) + amount)
			"coins": _gain_coins(seat, amount)
			"give_coin":
				var giver: int = operation["from"]
				var count := mini(int(coins[giver]), amount)
				_gain_coins(giver, -count)
				_gain_coins(seat, count)
			"damage": _damage_player(seat, amount)
			"loot": _draw_loot(seat, amount)
			"treasure":
				for i in amount:
					var id := _draw("treasure")
					if id >= 0:
						_gain_item(seat, id)
			"kill_self": hp[seat] = 0
			"temporary_attack":
				attack[seat] = int(attack[seat]) + amount
				temporary_attack.append([seat, amount])
			"recharge":
				if _source_item_in_play(effect.source):
					effect.source.tapped = false
	_refresh_passive_stats()
	_note("Пассив: %s · %s" % [name_of(seat), FSData.title(int(effect.card))])
	_continue_stack()

## Бонус хранится у источника: передача и уничтожение не оставляют его у прежнего владельца.
func _refresh_passive_stats() -> void:
	while _room_bonuses.size() < players.size():
		_room_bonuses.append(Vector2i.ZERO)
	while _character_attack_bonuses.size() < players.size():
		_character_attack_bonuses.append(0)
	for seat in players.size():
		var character_bonus := 0
		if int(chars[seat]) == 884:
			character_bonus = 2 if int(souls[seat]) >= 3 else (1 if int(souls[seat]) > 0 else 0)
		attack[seat] = maxi(0, int(attack[seat]) + character_bonus - int(_character_attack_bonuses[seat]))
		_character_attack_bonuses[seat] = character_bonus
		var room_bonus := Vector2i(1 if room == 770 else 0, 1 if room == 769 else 0)
		attack[seat] = maxi(0, int(attack[seat]) + room_bonus.x - _room_bonuses[seat].x)
		max_hp[seat] = maxi(1, int(max_hp[seat]) + room_bonus.y - _room_bonuses[seat].y)
		_room_bonuses[seat] = room_bonus
		var meat_cubes := 0
		for entry: Dictionary in items[seat]:
			if int(entry.id) in [30, 31, 32]:
				meat_cubes += 1
		for entry: Dictionary in items[seat]:
			var bonus := PassiveRules.stat_bonus(int(entry.id), entry, hands[seat].size(), meat_cubes)
			attack[seat] = maxi(0, int(attack[seat]) + bonus.x - int(entry.get("_attack_bonus", 0)))
			max_hp[seat] = maxi(1, int(max_hp[seat]) + bonus.y - int(entry.get("_health_bonus", 0)))
			entry["_attack_bonus"] = bonus.x
			entry["_health_bonus"] = bonus.y
			hp[seat] = mini(int(hp[seat]), int(max_hp[seat]))

func _remove_item(seat: int, index: int) -> Dictionary:
	var entry: Dictionary = items[seat].pop_at(index)
	attack[seat] = maxi(0, int(attack[seat]) - int(entry.get("_attack_bonus", 0)))
	max_hp[seat] = maxi(1, int(max_hp[seat]) - int(entry.get("_health_bonus", 0)))
	hp[seat] = mini(int(hp[seat]), int(max_hp[seat]))
	entry.erase("_attack_bonus")
	entry.erase("_health_bonus")
	_refresh_passive_stats()
	return entry

func _gain_item(seat: int, id: int, eternal: bool = false) -> void:
	var entry := FSData.item_entry(id, eternal)
	if id == 58:
		entry.counters = hands[seat].size()
	items[seat].append(entry)
	if not _setting_up and FSData.card(id).kind == "treasure":
		bonus_progress.treasures = int(bonus_progress.treasures) + 1
	_refresh_passive_stats()
	if id == 16:
		_queue_passive(seat, id, entry, [PassiveRules.operation("loot")])
	if id in [69, 77]:
		_queue_passive(seat, id, entry, [PassiveRules.operation("coins", 14 if id == 69 else 9)])

func _destroy_item(seat: int, index: int) -> void:
	var item := _remove_item(seat, index)
	_discard_item(int(item.id))
	if int(item.id) == 505:
		_queue_passive(seat, 505, item, [PassiveRules.operation("treasure")])

## Брелоки остаются картами лута и после перехода в зону предметов.
func _discard_item(id: int) -> void:
	var kind := "loot" if FSData.card(id).get("kind", "") == "loot" else "treasure"
	discards[kind].append(id)

func _has_item(seat: int, key: String) -> int:
	var count := 0
	for entry: Dictionary in items[seat]:
		if FSData.card(int(entry.id)).get("key", "") == key:
			count += 1
	return count

func _damage_player(seat: int, amount: int, context: Dictionary = {}) -> void:
	_refresh_passive_stats()
	var combat: bool = context.get("combat", false)
	var face: int = context.get("value", 0)
	var immune := false
	for item: Dictionary in items[seat]:
		var id: int = item.id
		if (id == 514 and not combat) or (id == 72 and seat != current):
			immune = true
		if combat and ((id == 30 and face == 1) or (id == 31 and face == 2) or (id in [32, 92] and face == 3) or (id == 71 and face in [1, 6]) or (id == 112 and face == 4) or (id == 115 and face == 1)):
			immune = true
	if immune or amount <= 0:
		return
	amount += _item_count(seat, 214)
	if combat and face == 1:
		for i in _item_count(seat, 74):
			amount *= 2
	if _item_count(seat, 164) > 0:
		amount = mini(1, amount)
	# Полное предотвращение иммунитетом выше не расходует конечный запас жетонов.
	for item: Dictionary in items[seat]:
		if int(item.id) == 202 and int(item.counters) > 0 and amount > 0:
			var prevented := mini(amount, int(item.counters))
			item.counters = int(item.counters) - prevented
			amount -= prevented
			_note("Мёртвый кот предотвратил %d урона" % prevented)
	var blocked := mini(maxi(0, amount), int(damage_shields[seat]))
	damage_shields[seat] -= blocked
	hp[seat] = maxi(0, int(hp[seat]) - (maxi(0, amount) - blocked))
	if maxi(0, amount) > blocked:
		_emit_passives("damage", {"seat": seat, "amount": maxi(0, amount) - blocked})
	if blocked > 0:
		_note("Предотвращён урон: %s · %d" % [name_of(seat), blocked])

func _item_count(seat: int, id: int) -> int:
	var count := 0
	for item: Dictionary in items[seat]:
		if int(item.id) == id:
			count += 1
	return count

func _purchase_cost(seat: int, slot: int) -> int:
	if slot == -1:
		return 10
	return maxi(0, 10 - 5 * _item_count(seat, 229) - _item_count(seat, 473) - _item_count(seat, 76) - (5 if room == 771 else 0))

## Ауры учитывают только открытых живых монстров, а не накрытые карты.
func _monster_aura(key: String) -> int:
	var count := 0
	for entry: Dictionary in monsters:
		if int(entry.hp) > 0 and FSData.card(int(entry.id)).get("key", "") == key:
			count += 1
	return count

func _untargetable(id: int) -> bool:
	return id == 272 or _dies_with_other_monster(id)

## Запрет атаки сам по себе не означает гибель вслед за другим монстром.
func _dies_with_other_monster(id: int) -> bool:
	return FSData.card(id).get("key", "") in ["deathshead", "stoney"]

## Одна формула для видимой защиты и проверки попадания, без изменения исходного dc.
func _monster_evasion(monster: Dictionary) -> int:
	var base: int = int(monster.dc) + _monster_aura("stoney") + (1 if curses[current].has(705) else 0)
	return PassiveRules.monster_evasion(base, items[current])

## Только цели перебросов получают внутренний номер; сдвиг стека не меняет их личность.
func _roll_token(effect: Dictionary) -> int:
	if not effect.has("roll_token"):
		_next_roll_token += 1
		effect["roll_token"] = _next_roll_token
	return int(effect.roll_token)

## Индекс оставлен для прежних подготовленных запросов; привязанная цель ищется только по номеру.
func _reroll_index(effect: Dictionary) -> int:
	if effect.has("reroll_target_token"):
		for index: int in stack.size():
			if int(stack[index].get("roll_token", -1)) == int(effect.reroll_target_token):
				return index if stack[index].kind in ["roll", "effect_roll"] else -1
		return -1
	var index: int = int(effect.get("reroll_index", -1))
	return index if index >= 0 and index < stack.size() and stack[index].kind in ["roll", "effect_roll"] else -1

## Контекст атаки не теряется с её целью; цепочка перебросов не становится обычным броском.
func _rerolls_attack(effect: Dictionary) -> bool:
	var pending: Dictionary = effect
	var visited: Array[int] = []
	while true:
		if bool(pending.get("attack_reroll", false)):
			return true
		var index: int = _reroll_index(pending)
		if index < 0 or index in visited:
			return false
		visited.append(index)
		pending = stack[index]
		if pending.kind == "roll":
			return true
		if pending.kind != "effect_roll":
			return false
	return false

func _roll_passives(value: int, roller: int = -1) -> void:
	var roll_seat: int = current if roller < 0 else roller
	# Монстры кладутся в стек раньше предметов; накрытые карты не в игре.
	for entry: Dictionary in monsters:
		var id: int = int(entry.id)
		if id == 440 and value == 2:
			_queue_passive(roll_seat, id, {}, [PassiveRules.operation("damage", 2)])
		elif id == 445 and value == 4:
			_queue_passive(roll_seat, id, {}, [PassiveRules.operation("coins", 2)])
		elif id == 439 and value == 5:
			var resume: String = _after_stack if phase == "priority" else phase
			_push({"kind":"forced_discard","owner":roll_seat,"target":roll_seat,"card":id,"amount":1},resume)
	_emit_passives("roll", {"seat": roll_seat, "value": value})
	if value != 4:
		return
	# Карта остаётся открытой до завершения её награды: бросок награды тоже
	# вызывает напечатанный эффект. Ауры боевых характеристик по-прежнему только у живых.
	var tumors := 0
	for entry: Dictionary in monsters:
		if FSData.card(int(entry.id)).get("key", "") == "cursedtumor":
			tumors += 1
	if tumors == 0:
		return
	_note("Проклятая опухоль: четвёрка наносит всем игрокам %d урона" % tumors)
	for seat in players.size():
		if not dead[seat]:
			_damage_player(seat, tumors)

func _cancel_unresolved() -> void:
	var pending_effects: Array = stack.duplicate()
	if not resolving.is_empty():
		pending_effects.append(resolving)
	for paused: Dictionary in paused_effects:
		pending_effects.append(paused.effect)
	for pending: Dictionary in stack:
		if pending.get("kind", "") == "resume_effect":
			pending_effects.append(pending.previous.effect)
	var discarded := {}
	for pending: Dictionary in pending_effects:
		if pending.get("kind", "") == "loot" and not bool(pending.get("under_deck", false)):
			var id: int = pending.card
			if not discarded.has(id):
				discards.loot.append(id)
				discarded[id] = true
		elif pending.get("kind", "") == "event" and not bool(pending.get("attached", false)):
			discards.monster.append(int(pending.card))
	stack.clear()
	paused_effects.clear()
	next_action = {}
	peek = {}
	battle = -1

## Подтверждённая смерть или явная отмена заканчивает бой, сохраняя прочие способности стека.
## Не вызывать при одном лишь объявлении смерти: до её разрешения ещё возможно спасение.
func _end_battle() -> void:
	battle = -1
	battle_player = -1
	stack = stack.filter(func(effect): return effect.kind not in ["roll", "combat", "player_combat", "player_attack"])
	_after_stack = "turn"

## Окончание хода погибшего ждёт штрафов остальных одновременно погибших игроков.
func _resume_after_deaths() -> void:
	var pending_passives := stack.filter(func(effect): return effect.kind == "passive")
	if not pending_passives.is_empty():
		stack = stack.filter(func(effect): return effect.kind != "passive")
		stack.append({"kind": "resume_deaths", "owner": current})
		stack.append_array(pending_passives)
		phase = "priority"
		return
	if not _death_queue.is_empty():
		_push({"kind": "death", "owner": int(_death_queue[0])}, _death_resume)
	elif _end_after_deaths:
		_end_after_deaths = false
		_cancel_unresolved()
		resolving = {}
		_after_stack = "turn"
		_end_turn()
	else:
		_continue_stack()

func new_game(members: Array, expanded: bool = false, seed_value: int = 0) -> void:
	_turn_attack_rolls.clear()
	temporary_attack.clear()
	monster_slots = 2
	battle_player = -1
	required_player_attacks = 0
	discard_choice = {}
	deck_attacks = 0
	required_deck_attacks = 0
	players = members.duplicate(true)
	bank = 100 - 3 * players.size()
	dlc = expanded
	_rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()
	decks = {}; discards = {}; hands = []; items = []; chars = []; hp = []; max_hp = []; attack = []; coins = []; souls = []; soul_cards = []; curses = []; character_ready = []; dead = []
	monsters = []; shop = []; stack = []; log = []; claimed = []; resolving = {}; paused_effects = []; _death_queue = []
	phase = "turn"; _after_stack = "turn"; _death_resume = "turn"; peek = {}; current = 0; priority = 0; passes = 0; round_no = 1; winner = -1; revision = 0; room = -1; battle = -1; roll_no = 0; last_roll = 0
	next_action = {}
	damage_shields = []
	extra_turns = []
	_ending_turn = false
	_discard_limit = 10
	_turn_resume = -1
	_end_after_deaths = false
	stats_rolls.clear();stats_risks.clear()
	_setting_up = true
	_end_discard_prepared = false
	_room_bonuses.clear()
	_character_attack_bonuses.clear()
	_starting_choices.clear()
	bonus_progress = {"deaths": 0, "treasures": 0, "monsters": 0}
	for kind in ["loot", "treasure", "monster", "room"]:
		decks[kind] = FSData.pool(kind, dlc)
		if kind == "monster":
			decks[kind].append_array(FSData.pool("event", dlc))
		_shuffle(decks[kind]); discards[kind] = []
	bonuses = FSData.pool("bonus", dlc)
	var characters := FSData.characters(dlc).duplicate(true)
	_shuffle(characters)
	for seat in players.size():
		damage_shields.append(0)
		var chosen: Dictionary = characters.pop_back()
		chars.append(int(chosen.card))
		var health := PassiveRules.character_health(int(chosen.card))
		max_hp.append(health); hp.append(health); attack.append(1); coins.append(3); souls.append(0); character_ready.append(true); dead.append(false); hands.append([]); items.append([]); soul_cards.append([]); curses.append([])
		var eternal: int = int(chosen.item)
		if eternal < 0 and chosen.key == "eden":
			var options: Array = []
			for i in 3:
				var option := _draw("treasure")
				if option >= 0:
					options.append(option)
			if not options.is_empty():
				_starting_choices.append({"owner": seat, "cards": options})
		if eternal >= 0:
			# Вторая сторона ещё создаётся: общий пересчёт выполняется после раздачи всем.
			items[seat].append(FSData.item_entry(eternal, true))
		_draw_loot(seat, 5 if int(chosen.card) == 908 else 3, "setup")
		if chosen.key == "cain":
			current = seat
	for i in 2:
		shop.append(_draw("treasure"))
		_fill_monster(true)
	if dlc:
		room = _draw("room")
	_setting_up = false
	_refresh_passive_stats()
	_advance_start()
	_note("Новая партия · " + ("с DLC" if dlc else "базовый набор"))

func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var value = array[i]; array[i] = array[j]; array[j] = value
func _draw(kind: String) -> int:
	if decks[kind].is_empty() and not discards[kind].is_empty():
		decks[kind] = discards[kind].duplicate(); discards[kind] = []; _shuffle(decks[kind])
	return int(decks[kind].pop_back()) if not decks[kind].is_empty() else -1
func _draw_loot(seat: int, count: int, reason: String = "effect") -> void:
	if reason == "effect" and count > 0:
		count += _has_item(seat, "luckytoe")
	for i in count:
		var id := _draw("loot")
		if id >= 0: hands[seat].append(id)
func _gain_coins(seat: int, amount: int) -> void:
	if amount >= 0:
		if amount > 0:
			amount += _has_item(seat, "counterfeitpenny")
		var count := mini(amount,bank)
		coins[seat] += count; bank -= count
		if count > 0:
			_emit_passives("coins", {"seat": seat, "amount": count})
	else:
		if _item_count(seat, 523) > 0:
			return
		var count := mini(-amount,int(coins[seat]))
		coins[seat] -= count; bank += count

func _note(text: String) -> void:
	log.append(text)
	if log.size() > 150: log.pop_front()
func name_of(seat: int) -> String:
	return str(players[seat].name)
func actor() -> int:
	if phase == "forced_discard":
		return int(discard_choice.target)
	if phase == "starting_item" and not _starting_choices.is_empty():
		return int(_starting_choices[0].owner)
	if phase == "priority": return priority
	if phase == "effect":
		return int(resolving.get("reroll_request", {}).get("owner", resolving.owner))
	if phase == "death" and not _death_queue.is_empty(): return int(_death_queue[0])
	return current
func can_spectate() -> bool:
	return false
func spectator_seat() -> int:
	return -1
func _begin_turn() -> void:
	_turn_attack_rolls.clear()
	battle_player = -1
	required_player_attacks = 0
	discard_choice = {}
	_refresh_passive_stats()
	phase = "turn"; priority = current; free_loot = 1; bought = false; attacked = false; battle = -1
	buy_left = 1; attack_left = 1; temporary_attack = []
	deck_attacks = 0
	required_deck_attacks = 0
	character_ready[current] = _item_count(current, 138) == 0
	attack_left = 99 if _item_count(current, 117) > 0 else 1
	for id in [24, 25, 26, 254, 877]:
		attack_left += _item_count(current, id)
	buy_left += _item_count(current, 105) + _item_count(current, 173)
	free_loot += _item_count(current, 221) + _item_count(current, 226)
	for item: Dictionary in items[current]:
		if int(item.id) != 44:
			item.tapped = false
	_draw_loot(current, 1 + _has_item(current, "guppystail") + _has_item(current, "momscoinpurse") + _has_item(current, "momspurse") + (1 if room == 772 else 0), "step")
	if room == 766:
		_queue_passive(current, room, {}, [PassiveRules.operation("coins", 3)])
	if curses[current].has(707):
		_damage_player(current, 1)
	_emit_passives("turn_start")
	_note("Ход: " + name_of(current))
func _end_turn() -> void:
	if not _ending_turn:
		_ending_turn = true
		phase = "turn"
		_emit_passives("turn_end")
		if curses[current].has(709):
			_queue_passive(current, 709, {}, [PassiveRules.operation("coins", -4)])
		if phase == "priority":
			_after_stack = "end_turn"
			return
	if not _end_discard_prepared:
		_end_discard_prepared = true
		_discard_limit = mini(10, maxi(0, hands[current].size() - _has_item(current, "guppystail")))
		if curses[current].has(729):
			_discard_limit = mini(2, _discard_limit)
	if hands[current].size() > _discard_limit:
		phase = "discard"
		return
	for entry in temporary_attack: attack[int(entry[0])] = maxi(0,int(attack[int(entry[0])])-int(entry[1]))
	temporary_attack.clear()
	for seat in players.size(): hp[seat] = max_hp[seat]; dead[seat] = false
	damage_shields.fill(0)
	for monster: Dictionary in monsters:
		monster.hp = FSData.stat(int(monster.id), "hp", 1)
		_expire_monster_modifiers(monster)
	if not extra_turns.is_empty():
		if _turn_resume < 0:
			_turn_resume = (current + 1) % players.size()
		current = int(extra_turns.pop_front())
	else:
		current = _turn_resume if _turn_resume >= 0 else (current + 1) % players.size()
		_turn_resume = -1
		if current == 0: round_no += 1
	_ending_turn = false
	_end_discard_prepared = false
	_discard_limit = 10
	_begin_turn()
func _fill_monster(initial: bool = false, slot: int = -1) -> void:
	var skipped := []
	var id := _draw("monster")
	while id >= 0 and FSData.card(id).kind == "event" and initial:
		skipped.append(id); id = _draw("monster")
	for skip in skipped: decks.monster.push_front(skip)
	if id < 0: return
	if FSData.card(id).kind == "event":
		_push({"kind":"event", "card":id, "owner":current}, "refill")
		return
	var monster := {"id":id, "hp":FSData.stat(id,"hp",1), "dc":FSData.stat(id,"dc",4), "at":FSData.stat(id,"at",1)}
	if slot >= 0 and slot < monsters.size(): monsters[slot] = monster
	else: monsters.append(monster)

func _expire_monster_modifiers(monster: Dictionary) -> void:
	monster.erase("last_attack_roll")
	monster.dc = int(monster.dc) - int(monster.get("temporary_dc", 0))
	monster.erase("temporary_dc")
	if monster.has("under"):
		_expire_monster_modifiers(monster.under)
func _push(effect: Dictionary, resume: String) -> void:
	if phase != "priority": _after_stack = resume
	stack.append(effect); phase = "priority"; priority = (int(effect.owner) + 1) % players.size(); passes = 0
	_note(name_of(int(effect.owner)) + " → " + FSData.effect_title(effect))
func _continue_stack() -> void:
	if _after_stack == "effect" and not resolving.is_empty():
		phase = "priority" if not stack.is_empty() else "effect"
		return
	# Ответ после объявления смерти может спасти игрока до оплаты штрафа.
	if _after_stack == "death":
		for dying in _death_queue.duplicate():
			if hp[int(dying)] > 0:
				_death_queue.erase(dying)
		if _death_queue.is_empty():
			_after_stack = _death_resume
			if _end_after_deaths:
				_resume_after_deaths()
				return
	for i in monsters.size():
		var m: Dictionary = monsters[i]
		if int(m.hp) <= 0 and not bool(m.get("death_pending",false)):
			m["death_pending"] = true
			_push({"kind":"monster_death","card":int(m.id),"owner":current,"slot":i},_after_stack)
			return
	if not stack.is_empty():
		phase = "priority"; passes = 0; priority = current
	else:
		phase = _after_stack
		if phase == "starting_continue":
			_advance_start()
			return
		if phase == "end_turn":
			_check_deaths()
			if phase == "end_turn":
				_end_turn()
			return
		if phase == "refill":
			phase = "battle_roll" if battle >= 0 else "turn"
			while monsters.size() < monster_slots and phase in ["turn", "battle_roll"]:
				var before := monsters.size()
				_fill_monster()
				if monsters.size() == before and phase in ["turn", "battle_roll"]: break
	_check_deaths()
func _resolve_top() -> void:
	var effect: Dictionary = stack.pop_back()
	if effect.kind == "resume_deaths":
		_resume_after_deaths()
		return
	if effect.kind == "resume_effect":
		resolving = effect.previous.effect
		_after_stack = str(effect.previous.resume)
		peek = effect.previous.peek
		phase = "effect"
		return
	if effect.kind == "passive":
		_resolve_passive(effect)
		return
	if effect.kind == "monster_death":
		var slot: int = int(effect.slot)
		if slot >= 0 and slot < monsters.size() and int(monsters[slot].id) == int(effect.card) and int(monsters[slot].hp) <= 0:
			# Каменюка и Голова смерти гибнут от смерти другого открытого монстра.
			for other in monsters.size():
				if other != slot and _dies_with_other_monster(int(monsters[other].id)):
					monsters[other].hp = 0
			resolving = {"kind":"reward","card":int(effect.card),"owner":current,"slot":slot}; phase = "effect"
			if int(effect.card) == 429:
				_prepare_peep_spawn()
			if int(effect.card) == 358:
				resolving["requires_reward_roll"] = true
			if int(effect.card) == 268:
				required_player_attacks += 1
			bonus_progress.monsters = int(bonus_progress.monsters) + 1
			_emit_passives("monster_death", {"seat": int(monsters[slot].get("slayer", current)), "card": int(effect.card)})
		else:
			if slot >= 0 and slot < monsters.size(): monsters[slot]["death_pending"] = false
			_continue_stack()
		return
	if effect.kind == "death":
		var dying: int = int(effect.owner)
		if hp[dying] <= 0:
			if (battle_player >= 0 and dying in [current, battle_player]) or (battle >= 0 and dying == current):
				_end_battle()
				_death_resume = "turn"
			phase = "death"
			bonus_progress.deaths = int(bonus_progress.deaths) + 1
			_emit_passives("death", {"seat": dying})
		else:
			_death_queue.erase(dying)
			_resume_after_deaths()
		return
	if effect.kind == "forced_discard":
		discard_choice = effect.duplicate(true)
		discard_choice["remaining"] = mini(int(effect.amount), hands[int(effect.target)].size())
		if int(discard_choice.remaining) > 0:
			phase = "forced_discard"
		else:
			discard_choice = {}
			_continue_stack()
		return
	if effect.kind == "player_attack":
		var target: int = int(effect.target)
		if target in _player_attack_targets() and not dead[current] and hp[current] > 0:
			battle_player = target
			phase = "battle_roll"
			_after_stack = "battle_roll"
		else:
			_continue_stack()
		return
	if effect.kind == "player_combat":
		_apply_player_combat(effect)
		return
	if effect.kind == "attack":
		_start_attack(effect)
		return
	if effect.kind == "purchase":
		_complete_purchase(effect)
		return
	if effect.kind == "combat":
		_apply_combat(effect)
		return
	if effect.kind == "effect_roll":
		last_roll = clampi(int(effect.value),1,6)
		var stack_before := stack.size()
		var attack_reroll: bool = _rerolls_attack(effect)
		if not attack_reroll and not bool(effect.get("passives_done", false)):
			_roll_passives(last_roll, int(effect.owner))
		if effect.has("reroll_index"):
			var index: int = _reroll_index(effect)
			if index >= 0:
				stack[index].value = last_roll
				stack[index]["passives_done"] = true
				# Сохраняем прежний маркер замены, но числовые триггеры атаки ещё впереди.
				if attack_reroll:
					stack[index]["attack_passives_pending"] = true
		var previous: Dictionary = paused_effects.pop_back()
		resolving = previous.effect; _after_stack = str(previous.resume); peek = previous.peek
		if resolving.get("kind", "") == "reward" and int(resolving.get("card", -1)) == 358:
			resolving["reward_roll"] = last_roll
			resolving["return_to_deck"] = last_roll in [1, 6]
		if stack.size() > stack_before:
			stack.insert(stack_before, {"kind": "resume_effect", "owner": int(previous.effect.owner), "previous": previous})
			phase = "priority"
		else:
			phase = "effect"
		return
	if effect.kind == "roll":
		var trigger_start := stack.size()
		var roller: int = int(effect.owner)
		var ordinal: int = int(_turn_attack_rolls.get(roller, 0)) + 1
		var modifiers: Dictionary = PassiveRules.attack_modifiers(items[roller], ordinal)
		last_roll = PassiveRules.attack_roll(int(effect.value), modifiers)
		if int(modifiers.roll_bonus) != 0:
			_note("Бросок атаки %s №%d: %d %+d → %d (итог)" %
				[name_of(roller), ordinal, int(effect.value), int(modifiers.roll_bonus), last_roll])
		if not bool(effect.get("passives_done", false)) or bool(effect.get("attack_passives_pending", false)):
			_roll_passives(last_roll, roller)
		# Считаем разрешившиеся броски атаки, включая промахи и перебросы через effect_roll.
		# Небоевой effect_roll сам по себе сюда не попадает; итог атаки учитывается один раз.
		_turn_attack_rolls[roller] = ordinal
		_emit_passives("attack_roll", {"seat": roller, "count": int(_turn_attack_rolls[roller])})
		# Как и прочие триггеры броска, бонус угля разрешится над combat.
		# Числовой урон текущей атаки фиксируется ниже до разрешения этого бонуса.
		if battle_player >= 0:
			if battle_player not in _player_attack_targets() or dead[current] or hp[current] <= 0:
				_continue_stack()
				return
			var hit_player: bool = PassiveRules.attack_hits(last_roll, 4, modifiers)
			var player_damage: int = int(attack[current] if hit_player else attack[battle_player])
			_push({"kind": "player_combat", "owner": current, "card": 268, "target": battle_player,
				"hit": hit_player, "damage": player_damage, "value": last_roll}, "battle_roll")
			stack.insert(trigger_start, stack.pop_back())
			return
		if battle < 0 or battle >= monsters.size() or dead[current] or hp[current] <= 0:
			_continue_stack(); return
		var m: Dictionary = monsters[battle]
		var hit: bool = PassiveRules.attack_hits(last_roll, _monster_evasion(m), modifiers)
		if int(m.id) == 281:
			hit = hit and last_roll > int(m.get("last_attack_roll", 0))
			m["last_attack_roll"] = last_roll
		var damage: int = int(attack[current]) if hit else int(m.at) + _monster_aura("deathshead") + (1 if curses[current].has(737) else 0)
		if not hit and last_roll == 1 and FSData.card(int(m.id)).get("key", "") == "leaper":
			damage *= 2
		_push({"kind":"combat","owner":current,"card":int(m.id),"hit":hit,"damage":damage,"value":last_roll},"battle_roll")
		# Урон от результата ждёт обязательных триггеров самого броска.
		stack.insert(trigger_start, stack.pop_back())
		return
	if effect.kind == "event" and int(effect.card) == 715:
		required_deck_attacks = maxi(required_deck_attacks, 2)
		attack_left = maxi(attack_left, required_deck_attacks - deck_attacks)
		attacked = attack_left <= 0
		discards.monster.append(715)
		_note("Засада: осталось атак верха колоды — %d" % maxi(0, required_deck_attacks - deck_attacks))
		_continue_stack()
		return
	var card := FSData.card(int(effect.card))
	var kind: String = str(card.lua.get("type", ""))
	if effect.kind == "loot" and kind in ["1c", "2c", "3c", "4c", "5c"]:
		_gain_coins(int(effect.owner),int(kind.left(1)))
		discards.loot.append(int(effect.card)); _continue_stack()
	elif effect.kind == "loot" and kind == "lsoul":
		souls[int(effect.owner)] += 1
		soul_cards[int(effect.owner)].append({"id":int(effect.card),"value":1})
		_refresh_passive_stats()
		_continue_stack()
	elif effect.kind == "loot" and kind == "trinkets":
		_gain_item(int(effect.owner), int(effect.card))
		_continue_stack()
	else:
		resolving = effect
		phase = "effect"
func _check_deaths() -> void:
	if not _death_queue.is_empty() or phase in ["effect","death","game_over"]: return
	for seat in players.size():
		if hp[seat] <= 0 and not dead[seat]:
			_death_queue.append(seat)
	if not _death_queue.is_empty():
		_death_resume = _after_stack if phase == "priority" else phase
		_push({"kind": "death", "owner": int(_death_queue[0])}, _death_resume)
func _check_bonuses() -> void:
	for id in bonuses:
		if claimed.has(id): continue
		var key: String = FSData.card(int(id)).key
		for seat in players.size():
			if room == 779 or curses[seat].has(744):
				continue
			var guppy := 0
			for item in items[seat]:
				if str(FSData.card(int(item.id)).key).begins_with("guppy"): guppy += 1
			if key == "soulofgreed" and coins[seat] >= 25 or key == "soulofgluttony" and hands[seat].size() >= 10 or key == "soulofguppy" and guppy >= 2:
				claimed.append(id); souls[seat] += 1; soul_cards[seat].append({"id":int(id),"value":1}); _note(name_of(seat) + " получает " + FSData.title(int(id))); break
	_refresh_passive_stats()

func _check_win() -> void:
	for seat in players.size():
		if souls[seat] >= 4:
			winner = seat; phase = "game_over"; _note("Четыре души! Победитель: " + name_of(seat)); return
func _apply_combat(effect: Dictionary) -> void:
	if battle < 0 or battle >= monsters.size() or dead[current] or hp[current] <= 0:
		_continue_stack(); return
	var monster: Dictionary = monsters[battle]
	if int(monster.id) != int(effect.card): _continue_stack(); return
	var value: int = int(effect.get("value", last_roll))
	if int(monster.id) == 462 and value == 1:
		monster.hp = mini(FSData.stat(462, "hp", 4), int(monster.hp) + 2)
		_note("Чаб восстановил 2 здоровья")
	if bool(effect.hit) and int(monster.id) in [428, 441] and value == 6:
		effect.damage = 0
		_note("Шестёрка не наносит боевой урон этому монстру")
	stats_risks.append({"seat":current,"error":not bool(effect.hit) and int(effect.damage)>0})
	if bool(effect.hit):
		if int(effect.get("value", last_roll)) == 6:
			for i in _item_count(current, 74):
				effect.damage = int(effect.damage) * 2
		if int(monster.id) == 281:
			effect.damage = mini(1, int(effect.damage))
		monster.hp = int(monster.hp) - int(effect.damage)
		if int(effect.damage) > 0 and FSData.card(int(monster.id)).get("key", "") == "lust":
			_damage_player(current, 1)
		_note("Попадание · урон %d" % int(effect.damage))
	else:
		_damage_player(current, int(effect.damage), {"combat": true, "value": int(effect.get("value", last_roll))})
		_note("Промах · получен урон %d" % int(effect.damage))
	_after_stack = "battle_roll"
	_continue_stack()

func _player_attack_targets() -> Array:
	var targets: Array = []
	for seat in players.size():
		if seat != current and not dead[seat] and int(hp[seat]) > 0:
			targets.append(seat)
	return targets

func _required_player_remaining() -> int:
	return required_player_attacks if not _player_attack_targets().is_empty() else 0

func _apply_player_combat(effect: Dictionary) -> void:
	if battle_player < 0 or int(effect.target) != battle_player:
		_continue_stack()
		return
	if dead[current] or hp[current] <= 0 or battle_player not in _player_attack_targets():
		_continue_stack()
		return
	var victim: int = battle_player if bool(effect.hit) else current
	var damage: int = int(effect.damage)
	var value: int = int(effect.value)
	if bool(effect.hit) and value == 6:
		for i in _item_count(current, 74):
			damage *= 2
	stats_risks.append({"seat": current, "error": not bool(effect.hit) and damage > 0})
	_damage_player(victim, damage, {"combat": true, "value": value})
	_note("PvP: %s · %s · урон %d" % ["попадание" if bool(effect.hit) else "промах", name_of(victim), damage])
	_after_stack = "battle_roll"
	_continue_stack()

## Награда снимает умершую карту, не теряя живые карты над ней и под ней.
func _finish_monster_reward(effect: Dictionary) -> void:
	if not bool(effect.get("kept_as_soul", false)):
		if bool(effect.get("return_to_deck", false)):
			decks.monster.append(int(effect.card))
			_note("Тряпочник возвращён на верх колоды")
		else:
			discards.monster.append(int(effect.card))
	var slot: int = int(effect.get("slot", battle))
	if bool(effect.get("spawn_over_source", false)):
		var dying: Dictionary = monsters[slot].get("under", {})
		if dying.has("under"):
			monsters[slot]["under"] = dying.under
		else:
			monsters[slot].erase("under")
		return
	var covered: Dictionary = monsters[slot].get("under", {})
	if covered.is_empty():
		monsters.remove_at(slot)
	else:
		monsters[slot] = covered
	if battle == slot:
		battle = -1
		_after_stack = "refill"
		stack = stack.filter(func(entry): return entry.kind not in ["roll", "combat"])
	elif battle > slot and covered.is_empty():
		battle -= 1
	if covered.is_empty():
		_after_stack = "refill"

func _start_attack(effect: Dictionary) -> void:
	var slot: int = int(effect.slot)
	if slot == -1:
		var id := _draw("monster")
		if id < 0: _continue_stack(); return
		if FSData.card(id).kind == "event":
			_after_stack = "turn"; _push({"kind":"event","card":id,"owner":current},"turn"); return
		var over: int = clampi(int(effect.get("over",0)),0,monsters.size()-1)
		var underneath: Dictionary = monsters[over].duplicate(true)
		monsters[over] = {"id":id,"hp":FSData.stat(id,"hp",1),"dc":FSData.stat(id,"dc",4),"at":FSData.stat(id,"at",1),"under":underneath}
		slot = over
	if slot < 0 or slot >= monsters.size(): _continue_stack(); return
	if _untargetable(int(monsters[slot].id)):
		_continue_stack()
		return
	battle = slot; phase = "battle_roll"; _after_stack = "battle_roll"
	if int(monsters[slot].id) == 396:
		discard_choice = {"card": 396, "owner": current, "amount": 2}
		phase = "discard_target"

func _complete_purchase(effect: Dictionary) -> void:
	var seat: int = int(effect.owner)
	var slot: int = int(effect.slot)
	var price: int = effect.get("cost", _purchase_cost(seat, slot))
	if coins[seat] >= price:
		var id: int = _draw("treasure") if slot == -1 else (int(discards.treasure.pop_back()) if slot == -2 else int(shop[slot]))
		if id >= 0:
			coins[seat] -= price
			bank += price
			_gain_item(seat, id)
			if slot >= 0: shop[slot] = _draw("treasure")
			if _item_count(seat, 76) > 0:
				_queue_passive(seat, 76, {}, [PassiveRules.operation("coins", _item_count(seat, 76))])
			_note(name_of(seat) + " покупает " + FSData.title(id))
	_continue_stack()

func action(seat: int, kind: String, arg = null) -> bool:
	if seat < 0 or seat >= players.size() or phase == "game_over": return false
	# Следующая операция того же ручного эффекта сначала разрешает его пассивы.
	# Чужой ручной ответ не пропускаем: маршрут открыт только для стека пассивов.
	if _pending_manual_passives() and kind in ["effect", "effect_done", "effect_roll", "place_bloat"]:
		if seat != int(resolving.owner):
			return false
		_finish_responses()
		if phase == "effect":
			return action(seat, kind, arg)
		revision += 1
		return true
	if phase == "priority" and _after_stack == "starting_continue":
		if kind != "finish_start" or seat != current:
			return false
		_finish_responses()
		revision += 1
		return true
	_refresh_passive_stats()
	if seat != current and kind in ["loot", "activate"] and _item_count(current, 256) > 0:
		return false
	# Бросок ручной карты возвращает её владельцу, сохраняя уже отложенное действие.
	# Повторный захват кубика закрывает ответы, а не создаёт ещё один бросок.
	if phase == "priority" and kind == "effect_roll" and not paused_effects.is_empty():
		if seat != int(paused_effects.back().get("roller", paused_effects.back().effect.owner)): return false
		_finish_responses()
		revision += 1
		return true
	# Подтверждение штрафа сначала разрешает ответы на уже объявленную смерть.
	# Ручной ответ требует отдельного завершения; штраф сам по себе не применяется.
	if phase == "priority" and kind == "death" and not _death_queue.is_empty():
		if seat != int(_death_queue[0]):
			return false
		_finish_responses()
		revision += 1
		if phase == "death":
			return action(seat, kind, arg)
		return true
	# Выбор цели Гордыни мог прервать уже отложенный бросок.
	# Следующий жест только закрывает ответы на сброс, сохраняя исходный бросок.
	if phase == "priority" and kind == "roll" and seat == current and not next_action.is_empty() and stack.any(func(e): return e.kind == "forced_discard"):
		_finish_responses()
		revision += 1
		return true
	# Окно ответов открыто всем до следующего действия активного игрока.
	# Предыдущее действие и ответы сначала завершаются; ручной эффект не пропускается.
	if phase == "priority" and seat == current and kind in ["roll","attack","buy","end","room"] and next_action.is_empty():
		next_action = {"seat":seat,"kind":kind,"arg":arg}
		_finish_responses()
		revision += 1
		return true
	var a: Dictionary = arg if arg is Dictionary else {}
	var ok := false
	match kind:
		"discard_target":
			var target: int = int(a.get("target", -1))
			if phase != "discard_target" or seat != current or target < 0 or target >= players.size():
				return false
			var effect := discard_choice.duplicate(true)
			discard_choice = {}
			effect["kind"] = "forced_discard"
			effect["target"] = target
			_push(effect, "battle_roll")
			ok = true
		"forced_discard":
			var index: int = int(a.get("item", -1))
			if phase != "forced_discard" or seat != actor() or index < 0 or index >= hands[seat].size():
				return false
			discards.loot.append(hands[seat].pop_at(index))
			discard_choice.remaining = int(discard_choice.remaining) - 1
			_note(name_of(seat) + " сбрасывает карту лута: " + FSData.title(int(discard_choice.card)))
			if int(discard_choice.remaining) <= 0 or hands[seat].is_empty():
				discard_choice = {}
				_continue_stack()
				_finish_responses()
			ok = true
		"attack_player":
			var target: int = int(a.get("target", -1))
			if phase != "turn" or seat != current or battle >= 0 or battle_player >= 0 or required_player_attacks <= 0:
				return false
			if target not in _player_attack_targets() or dead[current] or hp[current] <= 0:
				return false
			required_player_attacks -= 1
			_push({"kind": "player_attack", "owner": current, "card": 268, "target": target}, "turn")
			ok = true
		"place_bloat":
			var slot: int = int(a.get("slot", -1))
			if phase != "effect" or seat != int(resolving.get("owner", -1)) or not resolving.has("spawn_card"):
				return false
			if slot not in _peep_spawn_slots():
				return false
			var id: int = int(resolving.spawn_card)
			if not decks.monster.has(id):
				return false
			decks.monster.erase(id)
			var entry := {"id": id, "hp": FSData.stat(id, "hp", 1), "dc": FSData.stat(id, "dc", 4), "at": FSData.stat(id, "at", 1)}
			if slot < monsters.size():
				entry["under"] = monsters[slot].duplicate(true)
				monsters[slot] = entry
			else:
				monsters.append(entry)
			_shuffle(decks.monster)
			if slot == int(resolving.get("slot", -1)):
				resolving["spawn_over_source"] = true
			resolving.erase("spawn_card")
			_note("Пип: Утопец выложен в ячейку %d" % (slot + 1))
			ok = true
		"choose_starting_item":
			if phase != "starting_item" or _starting_choices.is_empty() or seat != actor():
				return false
			var id: int = int(a.get("card", -1))
			if id not in _starting_choices[0].cards:
				return false
			var choice: Dictionary = _starting_choices.pop_front()
			var rest: Array = choice.cards.duplicate()
			rest.erase(id)
			for other in rest:
				decks.treasure.push_front(int(other))
			_gain_item(seat, id, true)
			if phase == "priority":
				_after_stack = "starting_continue"
			else:
				_advance_start()
			ok = true
		"monster_trigger":
			var slot: int = int(a.get("slot", -1))
			if phase in ["turn", "priority", "battle_roll", "death"] and not dead[seat] and slot >= 0 and slot < monsters.size():
				var resume: String = _after_stack if phase == "priority" else phase
				_push({"kind": "monster_trigger", "card": int(monsters[slot].id), "owner": seat, "slot": slot}, resume)
				ok = true
		"claim":
			var id: int = int(a.get("card",-1))
			if phase in ["turn","priority"] and bonuses.has(id) and not claimed.has(id):
				if room == 779 or curses[seat].has(744):
					return false
				var recipient := seat
				if id in [692, 693, 694, 695, 696]:
					recipient = int(a.get("target", seat))
					if seat != current or recipient not in _bonus_targets(id):
						return false
				var key: String = FSData.card(id).key
				if key == "soulofgreed" and coins[seat] < 25: return false
				if key == "soulofgluttony" and hands[seat].size() < 10: return false
				if key == "soulofguppy":
					var guppy := 0
					for item in items[seat]:
						if str(FSData.card(int(item.id)).key).begins_with("guppy"): guppy += 1
					if guppy < 2: return false
				claimed.append(id); souls[recipient] += 1; soul_cards[recipient].append({"id":int(id),"value":1}); _note(name_of(recipient) + " получает " + FSData.title(id)); ok = true
		"peek_take":
			var id: int = int(a.get("card",-1))
			if phase == "effect" and seat == int(resolving.owner) and int(peek.get("owner",-1)) == seat and id in peek.get("cards",[]):
				if not peek.has("deck"):
					return false
				var source: Array = decks[str(peek.deck)]
				if not source.has(id): return false
				var dest: String = str(a.get("dest",""))
				if not dest in ["top","bottom","hand","item","discard"]: return false
				source.erase(id); peek.cards.erase(id)
				match dest:
					"top": source.append(id)
					"bottom": source.push_front(id)
					"hand": hands[seat].append(id)
					"item": _gain_item(seat, id)
					"discard": discards[str(peek.deck)].append(id)
				_note(name_of(seat) + " перемещает просмотренную карту · " + {"top":"наверх колоды","bottom":"под низ колоды","hand":"в руку","item":"в предметы","discard":"в сброс"}.get(dest,dest)); ok = true

		"loot":
			if phase in ["turn","priority","battle_roll","death"] and not dead[seat] and a.get("card",-1) in hands[seat]:
				if seat!=current and FSData.response_kind(int(a.card))=="own_turn": return false
				if seat == current and free_loot > 0: free_loot -= 1
				elif character_ready[seat]: character_ready[seat] = false
				else: return false
				var resume: String = phase if phase != "priority" else _after_stack
				var id: int = int(a.card); hands[seat].erase(id); _push({"kind":"loot","card":id,"owner":seat}, resume); ok = true
		"activate":
			var i: int = int(a.get("item",-1))
			if phase in ["turn","priority","battle_roll","death"] and not dead[seat] and i >= 0 and i < items[seat].size():
				var item: Dictionary = items[seat][i]
				var tap := bool(a.get("tap", true))
				if tap and item.tapped: return false
				if tap: item.tapped = true
				var resume: String = phase if phase != "priority" else _after_stack
				_push({"kind":"item","card":int(item.id),"owner":seat},resume); ok = true
				_emit_passives("activate", {"seat": seat, "card": int(item.id)})
		"buy":
			var slot: int = int(a.get("slot",-2))
			var valid_slot: bool = a.has("slot") and slot >= -1 and slot < shop.size()
			valid_slot = valid_slot or (slot == -2 and a.has("slot") and _item_count(seat, 473) > 0 and not discards.treasure.is_empty())
			if phase == "turn" and seat == current and not bought and valid_slot and coins[seat] >= _purchase_cost(seat, slot):
				buy_left -= 1; bought = buy_left <= 0
				_push({"kind":"purchase","owner":seat,"slot":slot,"cost":_purchase_cost(seat, slot)},"turn"); ok = true
		"attack":
			var slot: int = int(a.get("slot",-2))
			if phase == "turn" and seat == current and not attacked and slot >= -1 and slot < monsters.size():
				if _required_player_remaining() > 0 and _forced_deck_remaining() == 0:
					return false
				if _forced_deck_remaining() > 0 and slot != -1:
					return false
				if slot >= 0 and _untargetable(int(monsters[slot].id)):
					return false
				attack_left -= 1; attacked = attack_left <= 0
				if slot == -1:
					deck_attacks += 1
				_push({"kind":"attack","owner":seat,"slot":slot,"over":int(a.get("over",0))},"turn"); ok = true
		"effect_roll":
			if phase == "effect" and seat == actor():
				if resolving.has("spawn_card"):
					return false
				var reroll_request: Dictionary = resolving.get("reroll_request", {})
				resolving.erase("reroll_request")
				last_roll = _rng.randi_range(1,6); roll_no += 1
				stats_rolls.append({"seat":seat,"faces":[last_roll]})
				paused_effects.append({"effect":resolving.duplicate(true),"resume":_after_stack,"peek":peek.duplicate(true),"roller":seat})
				resolving = {}; peek = {}
				var roll_effect := {"kind":"effect_roll","value":last_roll,"owner":seat}
				if not reroll_request.is_empty():
					roll_effect["reroll_index"] = int(reroll_request.index)
					if reroll_request.has("target_token"):
						roll_effect["reroll_target_token"] = int(reroll_request.target_token)
					roll_effect["attack_reroll"] = bool(reroll_request.get("attack", false)) or _rerolls_attack(roll_effect)
					var target_index: int = _reroll_index(roll_effect)
					if target_index >= 0:
						roll_effect["reroll_target_token"] = _roll_token(stack[target_index])
				_push(roll_effect,"effect"); ok = true
		"roll":
			if phase == "battle_roll" and seat == current:
				last_roll = _rng.randi_range(1,6); roll_no += 1
				stats_rolls.append({"seat":seat,"faces":[last_roll]})
				_push({"kind":"roll","value":last_roll,"owner":seat},"battle_roll"); ok = true
		"effect":
			if phase == "effect" and seat == int(resolving.owner): ok = _effect(a)
		"effect_done":
			if phase == "effect" and seat == int(resolving.owner):
				if bool(resolving.get("requires_reward_roll", false)) and not resolving.has("reward_roll"):
					return false
				if resolving.has("spawn_card"):
					return false
				if resolving.has("reroll_request"):
					return false
				if resolving.kind == "event" and str(FSData.card(int(resolving.card)).lua.get("type","")) == "curse" and not bool(resolving.get("attached",false)): return false
				var effect := resolving.duplicate(); resolving = {}; peek = {}
				if effect.kind == "loot" and not bool(effect.get("under_deck", false)):
					discards.loot.append(int(effect.card))
				if effect.kind == "event" and not bool(effect.get("attached",false)):
					discards.monster.append(int(effect.card))
				if effect.kind == "reward":
					_finish_monster_reward(effect)
				if bool(effect.get("refill_monsters", false)):
					_after_stack = "refill"
				if bool(effect.get("end_turn_after", false)):
					# Святой покров отменяет всё неразрешённое и завершает ход спасённого.
					_cancel_unresolved()
					_death_queue.erase(current)
					_end_after_deaths = true
					_resume_after_deaths()
				else:
					_continue_stack()
				ok = true
		"death":
			if phase == "death" and seat == actor():
				var loot: int = int(a.get("loot",-1)); var item: int = int(a.get("item",-1))
				var keep_resources: bool = _item_count(seat, 523) > 0
				var destroyable := []
				for i in items[seat].size():
					if not items[seat][i].eternal: destroyable.append(i)
				if not keep_resources and not hands[seat].is_empty() and not hands[seat].has(loot): return false
				if not destroyable.is_empty() and not destroyable.has(item): return false
				if not keep_resources and hands[seat].has(loot): hands[seat].erase(loot); discards.loot.append(loot)
				if item >= 0 and destroyable.has(item):
					_destroy_item(seat, item)
				if not keep_resources:
					_gain_coins(seat, -1)
				character_ready[seat] = false
				dead[seat] = true
				discards.monster.append_array(curses[seat]); curses[seat].clear()
				for card: Dictionary in items[seat]: card.tapped = true
				_death_queue.pop_front(); _note(name_of(seat) + " получает штраф за смерть")
				_end_after_deaths = _end_after_deaths or seat == current
				phase = _death_resume
				_emit_passives("after_death", {"seat": seat})
				_resume_after_deaths()
				ok = true
		"discard":
			var id: int = int(a.get("card",-1))
			if phase == "discard" and seat == current and hands[seat].has(id):
				hands[seat].erase(id); discards.loot.append(id); ok = true
				if hands[seat].size() <= _discard_limit: _end_turn()
		"end":
			if phase == "turn" and seat == current and _forced_deck_remaining() == 0 and _required_player_remaining() == 0:
				_end_turn()
				ok = true
		"trade":
			var target: int = int(a.get("target",-1)); var amount: int = int(a.get("amount",0))
			if phase in ["turn","priority"] and target >= 0 and target < players.size() and target != seat and amount > 0 and amount <= coins[seat]:
				coins[seat] -= amount; coins[target] += amount; _note("%s → %s: %d¢" % [name_of(seat),name_of(target),amount]); ok = true
		"room":
			if phase == "turn" and seat == current and dlc:
				if room >= 0: discards.room.append(room)
				room = _draw("room"); _note("Новая комната: " + FSData.title(room)); ok = true
	if ok:
		_refresh_passive_stats()
		revision += 1; _check_bonuses(); _check_win()
		if not next_action.is_empty() and kind in ["effect_done","death"]: _finish_responses()
	return ok

func _finish_responses() -> void:
	var limit := 0
	while phase == "priority" and not stack.is_empty() and limit < 500:
		_resolve_top(); limit += 1
	if phase in ["effect","death","priority","discard_target","forced_discard"]: return
	var followup := next_action.duplicate(true)
	next_action = {}
	if not followup.is_empty() and phase != "game_over":
		action(int(followup.seat),str(followup.kind),followup.arg)

func _effect(a: Dictionary) -> bool:
	if resolving.has("spawn_card"):
		return false
	if resolving.has("reroll_request"):
		return false
	var target: int = int(a.get("target",resolving.owner))
	var amount: int = clampi(int(a.get("amount",1)),-99,99)
	var op: String = str(a.get("op",""))
	if target < 0 or target >= players.size(): return false
	# Эти две операции адресуют кубик/монстра, а не игрока target: смена target не обходит защиту источника.
	var own_operation: bool = target == int(resolving.owner) or op in ["temporary_monster_dc", "roll"]
	if own_operation and PassiveRules.handled_operation(int(resolving.card), op) and (op not in ["coins", "counter"] or amount >= 0):
		_note("Этот эффект карты уже выполняется автоматически")
		return false
	match op:
		"pay_coins":
			if target != int(resolving.owner) or amount <= 0:
				return false
			var cost := maxi(0, amount - _item_count(target, 76))
			if int(coins[target]) < cost:
				return false
			coins[target] -= cost
			bank += cost
		"extra_turn":
			for i in clampi(amount, 1, 10):
				extra_turns.append(target)
		"self_underdeck":
			if resolving.kind != "loot" or bool(resolving.get("under_deck", false)):
				return false
			decks.loot.push_front(int(resolving.card))
			resolving["under_deck"] = true
		"give_item":
			var owner: int = int(resolving.owner)
			var index: int = int(a.get("item", -1))
			if target == owner or index < 0 or index >= items[owner].size():
				return false
			var chosen: Dictionary = items[owner][index]
			# Собственная напечатанная способность Мошны разрешает её передачу.
			# Обычная передача других вечных предметов по-прежнему запрещена.
			var sack_ability := int(chosen.id) == 69 and int(resolving.get("card", -1)) == 69
			if chosen.eternal and not sack_ability:
				return false
			items[target].append(_remove_item(owner, index))
		"peek_hand", "peek_hands":
			var revealed := []
			for seat in players.size():
				if op == "peek_hands" or seat == target:
					revealed.append({"seat": seat, "cards": hands[seat].duplicate()})
			peek = {"owner": int(resolving.owner), "hands": revealed}
		"prevent_damage":
			damage_shields[target] += maxi(0, amount)
		"coins": _gain_coins(target,amount)
		"loot": _draw_loot(target,clampi(amount,0,20))
		"damage": _damage_player(target, amount)
		"heal": hp[target] = mini(int(max_hp[target]),int(hp[target])+maxi(0,amount))
		"souls":
			if amount < 0 and not soul_cards[target].is_empty():
				_note("Для потери карты души выберите «Уничтожить карту души» и её индекс")
				return false
			if amount > 0 and (room == 779 or curses[target].has(744)):
				return false
			souls[target] = maxi(0,int(souls[target])+amount)
			if amount > 0 and resolving.kind == "reward" and not bool(resolving.get("kept_as_soul",false)):
				soul_cards[target].append({"id":int(resolving.card),"value":amount}); resolving["kept_as_soul"] = true
		"destroy_soul":
			var index: int = int(a.get("item", -1))
			if index < 0 or index >= soul_cards[target].size():
				return false
			var destroyed: Dictionary = soul_cards[target][index]
			var id: int = int(destroyed.id)
			# Душа персонажа не является отдельной уничтожаемой картой.
			# Предмет, уже ставший душой, теряет прежнюю вечность (например, Кость).
			if FSData.card(id).get("kind", "") == "character":
				return false
			soul_cards[target].remove_at(index)
			souls[target] = maxi(0, int(souls[target]) - int(destroyed.value))
			var pile: String = {"monster": "monster", "loot": "loot", "treasure": "treasure"}.get(str(FSData.card(id).get("kind", "")), "")
			if not pile.is_empty():
				discards[pile].append(id)
			_note("Уничтожена душа: %s · %s" % [name_of(target), FSData.title(id)])
		"steal_soul":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= soul_cards[target].size() or target == int(resolving.owner): return false
			var card: Dictionary = soul_cards[target].pop_at(i)
			souls[target] = maxi(0,int(souls[target])-int(card.value)); souls[int(resolving.owner)] += int(card.value)
			soul_cards[int(resolving.owner)].append(card)
		"attach_curse":
			if resolving.kind != "event" or str(FSData.card(int(resolving.card)).lua.get("type","")) != "curse" or bool(resolving.get("attached",false)): return false
			curses[target].append(int(resolving.card)); resolving["attached"] = true
		"attack":
			if target == int(resolving.owner) and PassiveRules.ATTACK.has(int(resolving.card)):
				_note("Постоянный бонус этой карты уже учтён")
				return false
			attack[target] = maxi(0,int(attack[target])+amount)
		"temporary_attack": attack[target] = maxi(0,int(attack[target])+amount); temporary_attack.append([target,amount])
		"extra_attack": attack_left += maxi(0,amount); attacked = attack_left <= 0
		"extra_buy": buy_left += maxi(0,amount); bought = buy_left <= 0
		"extra_loot": free_loot += maxi(0,amount)
		"max_hp":
			if target == int(resolving.owner) and PassiveRules.HEALTH.has(int(resolving.card)):
				_note("Постоянный бонус здоровья этой карты уже учтён")
				return false
			max_hp[target] = maxi(1,int(max_hp[target])+amount)
			hp[target] = mini(int(max_hp[target]),int(hp[target]))
		"expand_monsters":
			if amount < 1 or amount > 10:
				return false
			monster_slots += amount
			resolving["refill_monsters"] = true
		"treasure":
			for i in clampi(amount,0,10):
				var id := _draw("treasure")
				if id >= 0:
					_gain_item(target, id)
		"roll":
			var found := false
			for i in range(stack.size()-1,-1,-1):
				if stack[i].kind in ["roll","effect_roll"]: stack[i].value = clampi(int(stack[i].value)+amount,1,6); found = true; break
			if not found: return false
		"cancel":
			if stack.is_empty() or not stack.back().kind in ["loot","item","event","passive"]: return false
			var canceled: Dictionary = stack.pop_back()
			if canceled.get("kind") == "loot": discards.loot.append(int(canceled.card))
		"peek_loot", "peek_treasure", "peek_monster":
			var deck: String = op.trim_prefix("peek_")
			peek = {"owner":int(resolving.owner),"deck":deck,"cards":decks[deck].slice(maxi(0,decks[deck].size()-clampi(amount,1,10)))}
		"reroll":
			var found := false
			for i in range(stack.size()-1,-1,-1):
				if stack[i].kind in ["roll","effect_roll"]:
					# Результат появится только после жеста владельца исходного броска.
					resolving["reroll_request"] = {"owner": int(stack[i].owner), "index": i,
						"target_token": _roll_token(stack[i]), "attack": _rerolls_attack({"reroll_index": i})}
					found = true; break
			if not found: return false
		"prevent_death":
			hp[target] = maxi(1, int(hp[target]))
			dead[target] = false
			if target == current and FSData.card(int(resolving.card)).get("key", "") == "holymantle":
				resolving["end_turn_after"] = true
		"cancel_attack":
			if battle < 0 and battle_player < 0: return false
			_end_battle()
		"ready_character": character_ready[target] = true
		"steal":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size() or items[target][i].eternal: return false
			items[int(resolving.owner)].append(_remove_item(target, i))
		"counter":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size(): return false
			items[target][i].counters = maxi(0,int(items[target][i].counters)+amount)
		"recharge":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size(): return false
			if int(items[target][i].id) == 44 and int(resolving.get("card", -1)) != 44:
				return false
			items[target][i].tapped = false
		"deactivate":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= items[target].size():
				return false
			items[target][i].tapped = true
		"discard_loot", "give_loot":
			var owner: int = resolving.owner
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= hands[owner].size() or (op == "give_loot" and target == owner):
				return false
			var id: int = hands[owner].pop_at(i)
			if op == "give_loot":
				hands[target].append(id)
			else:
				discards.loot.append(id)
		"expand_shop":
			for i in clampi(amount, 0, 10):
				var id := _draw("treasure")
				if id >= 0:
					shop.append(id)
		"set_roll":
			var found := false
			for i in range(stack.size() - 1, -1, -1):
				if stack[i].kind in ["roll", "effect_roll"]:
					stack[i].value = clampi(amount, 1, 6)
					found = true
					break
			if not found:
				return false
		"reveal_hand":
			peek = {"owner": int(resolving.owner), "hands": [{"seat": target, "cards": hands[target].duplicate()}]}
		"swap_items":
			var owner: int = resolving.owner
			var own_index: int = int(a.get("item", -1))
			var other_index: int = int(a.get("other_item", 0))
			if owner == target or own_index < 0 or own_index >= items[owner].size() or other_index < 0 or other_index >= items[target].size():
				return false
			if items[owner][own_index].eternal or items[target][other_index].eternal:
				return false
			var own := _remove_item(owner, own_index)
			var other := _remove_item(target, other_index)
			items[owner].insert(own_index, other)
			items[target].insert(other_index, own)
		"item_to_soul":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= items[target].size() or items[target][i].eternal or room == 779 or curses[target].has(744):
				return false
			var item := _remove_item(target, i)
			souls[target] += 1
			soul_cards[target].append({"id": int(item.id), "value": 1})
		"temporary_monster_dc":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= monsters.size():
				return false
			monsters[i].dc = int(monsters[i].dc) + amount
			monsters[i]["temporary_dc"] = int(monsters[i].get("temporary_dc", 0)) + amount
		"discard_shop":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= shop.size():
				return false
			discards.treasure.append(int(shop[i]))
			shop[i] = _draw("treasure")
		"discard_monster":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= monsters.size() or i == battle:
				return false
			discards.monster.append(int(monsters[i].id))
			if monsters[i].has("under"):
				monsters[i] = monsters[i].under
			else:
				monsters.remove_at(i)
				if battle > i:
					battle -= 1
				_fill_monster()
		"destroy":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size() or items[target][i].eternal: return false
			_destroy_item(target, i)
		"monster_hp":
			var i: int = int(a.get("item",battle))
			if i < 0 or i >= monsters.size(): return false
			monsters[i].hp = int(monsters[i].hp)+amount
		"monster_damage":
			var i: int = int(a.get("item",battle))
			if i < 0 or i >= monsters.size(): return false
			var damage := maxi(0, amount)
			if int(monsters[i].id) == 281:
				damage = mini(1, damage)
			monsters[i].hp = int(monsters[i].hp) - damage
			monsters[i]["slayer"] = int(resolving.owner)
		_:
			return false
	var manual_titles := {
		"extra_turn": "дополнительный ход",
		"self_underdeck": "разыгранная карта под низ колоды",
		"give_item": "передача своего предмета",
		"peek_hand": "просмотр руки",
		"peek_hands": "просмотр рук всех игроков",
		"prevent_damage": "защита от следующего урона"
	}
	if manual_titles.has(op):
		_note("Эффект карты: %s · %s · %d" % [name_of(target), manual_titles[op], amount])
		return true
	_note("Эффект карты: %s · %s · %d" % [name_of(target), {"coins":"монеты","loot":"взять лут","damage":"урон","heal":"лечение","souls":"души","attack":"атака","max_hp":"здоровье","treasure":"сокровища","roll":"изменить бросок","reroll":"перебросить","cancel":"отмена","recharge":"перезарядка","destroy":"уничтожение","steal":"кража","counter":"счётчики","monster_damage":"урон монстру","peek_loot":"просмотр лута","peek_treasure":"просмотр сокровищ","peek_monster":"просмотр монстров","ready_character":"перезарядка персонажа","temporary_attack":"атака до конца хода","extra_attack":"добавить атаки","extra_buy":"добавить покупки","extra_loot":"добавить розыгрыш лута","monster_hp":"здоровье монстра","prevent_death":"предотвращение смерти","cancel_attack":"отмена атаки"}.get(op,op),amount])
	return true

func _forced_deck_remaining() -> int:
	if decks.monster.is_empty() and discards.monster.is_empty():
		return 0
	return maxi(0, required_deck_attacks - deck_attacks)

## Поиск относится к подтверждённой смерти. Карта остаётся в колоде до выбора места.
func _prepare_peep_spawn() -> void:
	for id: int in decks.monster:
		if str(FSData.card(id).get("key", "")) == "bloat":
			resolving["spawn_card"] = id
			return
	_shuffle(decks.monster)
	_note("Пип: в колоде монстров нет Утопца")

func _peep_spawn_slots() -> Array:
	var slots: Array = []
	if not resolving.has("spawn_card"):
		return slots
	for slot in mini(maxi(monster_slots, monsters.size()), monsters.size() + 1):
		if slot != battle:
			slots.append(slot)
	return slots

func _pending_manual_passives() -> bool:
	return (
		phase == "priority"
		and _after_stack == "effect"
		and not resolving.is_empty()
		and not stack.is_empty()
		and stack.all(func(entry): return entry.kind == "passive")
	)

func get_view(seat: int, _show_all: bool = false) -> Dictionary:
	var public := []
	for i in players.size():
		public.append({"name":players[i].name,"char":chars[i],"items":items[i].duplicate(true),"hp":hp[i],"max_hp":max_hp[i],"attack":attack[i],"coins":coins[i],"souls":souls[i],"hand_count":hands[i].size(),"souls_cards":soul_cards[i].duplicate(true),"curses":curses[i].duplicate(),"ready":character_ready[i],"dead":dead[i]})
		for owner in players.size():
			if owner != i and _item_count(owner, 128) > 0:
				public.back()["hand"] = hands[i].duplicate()
				break
	var counts := {}
	for key in decks: counts[key] = decks[key].size()
	# Служебные маркеры возврата содержат приватный peek и не передаются клиентам.
	var visible_stack: Array = []
	for entry: Dictionary in stack:
		if entry.kind in ["resume_effect", "resume_deaths"]:
			continue
		var public_entry := {}
		for key in ["kind", "owner", "card", "slot", "target", "value", "hit", "damage", "cost"]:
			if entry.has(key):
				public_entry[key] = entry[key]
		visible_stack.append(public_entry)
	var visible_monsters := monsters.duplicate(true)
	var bonus_targets := {}
	for id in bonuses:
		if int(id) in [692, 693, 694, 695, 696]:
			bonus_targets[int(id)] = _bonus_targets(int(id))
	for entry: Dictionary in visible_monsters:
		entry["untargetable"] = _untargetable(int(entry.id))
		entry.dc = _monster_evasion(entry)
		entry.at = int(entry.at) + _monster_aura("deathshead")
		if curses[current].has(737):
			entry.at += 1
	return {"players":public,"seat":seat,"discard_choice":discard_choice.duplicate(true),"battle_player":battle_player,"required_player_attacks":_required_player_remaining(),"player_attack_targets":_player_attack_targets(),"forced_deck_attacks":_forced_deck_remaining(),"spawn_slots":_peep_spawn_slots(),"effect_pending":_pending_manual_passives(),"starting_pending":phase=="priority" and _after_stack=="starting_continue","starting_options":_starting_choices[0].cards.duplicate() if phase=="starting_item" and not _starting_choices.is_empty() and seat==actor() else [],"phase":phase,"current":current,"actor":actor(),"round_no":round_no,"dlc":dlc,"hand":hands[seat].duplicate() if seat >= 0 and seat < players.size() else [],"monsters":visible_monsters,"shop":shop.duplicate(),"shop_price":_purchase_cost(seat if seat >= 0 else current,0),"discard_treasure":int(discards.treasure.back()) if seat >= 0 and _item_count(seat,473)>0 and not discards.treasure.is_empty() else -1,"room":room,"bonuses":bonuses.duplicate(),"bonus_targets":bonus_targets,"bonus_progress":bonus_progress.duplicate(),"claimed":claimed.duplicate(),"stack":visible_stack,"resolving":resolving.duplicate(),"battle":battle,"roll_no":roll_no,"last_roll":last_roll,"log":log.duplicate(),"winner":winner,"free_loot":free_loot,"bought":bought,"attacked":attacked,"counts":counts,"bank":bank,"revision":revision,"peek":peek.duplicate(true) if int(peek.get("owner",-2)) == seat else {},"death_actor":int(_death_queue[0]) if not _death_queue.is_empty() else -1,"discard_limit":_discard_limit}

