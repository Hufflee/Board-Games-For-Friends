extends RefCounted
## Four Souls, модуль правил: Состояние партии, колоды, ресурсы и предметы. Низ цепочки модулей FSRules.
## Часть цепочки fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules (FSRules — фасад).
## Отдельно не используется: состояние и вызовы общие через self.
const PassiveRules = preload("res://games/four_souls/logic/fs_passives.gd")
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
## Высота стека в момент, когда resolving начал разрешаться: всё ниже — внешний контекст,
## всё выше — ответы и пассивы, возникшие во время ручного эффекта (их закрывает владелец эффекта).
var _resolving_base := 0
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
## Шов для тестов: если задан, возвращает грань кубика вместо случайной (FSScenario.roll).
var roll_source: Callable
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
## Результаты бросков текущего хода по порядку (Фруктовый пирог).
var _turn_faces: Array = []
## Убийства монстров текущим игроком за ход (Клещ: первое убийство).
var _turn_kills := 0
## Награду прервала смерть текущего игрока — пустую ячейку монстра добрать в начале следующего хода.
var _refill_pending := false

var bonus_progress := {"deaths": 0, "treasures": 0, "monsters": 0}


## Напечатанное здоровье монстра + комната 797 (всем монстрам +1 здоровье).
func _monster_hp(id: int) -> int:
	return FSData.stat(id, "hp", 1) + (1 if room == 797 else 0)

# --- Вызовы вверх по цепочке: реализация в модулях выше (переопределяется там) ---
func _finish_monster_reward(effect: Dictionary) -> void:
	pass
func _emit_passives(event: String, data: Dictionary = {}) -> void:
	pass
func _queue_passive(seat: int, id: int, source: Dictionary, operations: Array) -> void:
	pass
func _apply_combat(effect: Dictionary) -> void:
	pass
func _apply_player_combat(effect: Dictionary) -> void:
	pass
func _complete_purchase(effect: Dictionary) -> void:
	pass
func _damage_player(seat: int, amount: int, context: Dictionary = {}) -> void:
	pass
func _dies_with_other_monster(id: int) -> bool:
	return false
func _end_battle() -> void:
	pass
func _fill_monster(initial: bool = false, slot: int = -1) -> void:
	pass
func _monster_aura(key: String) -> int:
	return 0
func _monster_evasion(monster: Dictionary) -> int:
	return 0
func _player_attack_targets() -> Array:
	return []
func _prepare_peep_spawn() -> void:
	pass
func _start_attack(effect: Dictionary) -> void:
	pass
func _advance_start() -> void:
	pass
func _check_deaths() -> void:
	pass
func _end_turn() -> void:
	pass
func _new_death() -> bool:
	return false
func _resume_after_deaths() -> void:
	pass
func action(seat: int, kind: String, arg = null) -> bool:
	return false

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
	_resolving_base = 0
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
func _roll_die() -> int:
	return clampi(int(roll_source.call()), 1, 6) if roll_source.is_valid() else _rng.randi_range(1, 6)
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
	if id == 62:
		_queue_passive(seat, id, entry, [PassiveRules.operation("expand_shop", 2)])
	if PassiveRules.LOOT_SEARCH.has(id):
		_queue_passive(seat, id, entry, [{"op": "search_loot", "amount": 1, "keys": PassiveRules.LOOT_SEARCH[id]}])
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
func _item_count(seat: int, id: int) -> int:
	var count := 0
	for item: Dictionary in items[seat]:
		if int(item.id) == id:
			count += 1
	return count
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
