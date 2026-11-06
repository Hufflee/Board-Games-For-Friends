extends RefCounted
## Four Souls, модуль правил: Состояние партии, колоды, ресурсы и предметы. Низ цепочки модулей FSRules.
## Часть цепочки fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules (FSRules — фасад).
## Отдельно не используется: состояние и вызовы общие через self.
const PassiveRules = preload("res://games/four_souls/logic/fs_passives.gd")
const RewardData := preload("res://games/four_souls/logic/fs_reward_data.gd")
const TrinketCards := preload("res://games/four_souls/logic/fs_trinket_cards.gd")
const TreasureCards := preload("res://games/four_souls/logic/fs_treasure_cards.gd")
const ActiveCards := preload("res://games/four_souls/logic/fs_active_cards.gd")
const SecondaryCards := preload("res://games/four_souls/logic/fs_secondary_cards.gd")
var _next_attack_bonus17: Dictionary = {}
var _next_any_attack_bonus17 := 0
var _eggs_respawn17: Dictionary = {}
var _optional_blind17 := 0
var _gut_tokens16: Dictionary = {}
var _forced_regular16 := 0
var players: Array = []
var dlc := false
var phase := "turn"
var current := 0
var priority := 0
var passes := 0
var turn_serial := 0  # номер хода с начала партии (для часов окна чужих карт)
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
var reward_boost := 1 # Множитель напечатанных наград до конца текущего хода; души отдельно.
var souls: Array = []
var soul_cards: Array = []
var curses: Array = []
var character_ready: Array = []
var _nail_turn20 := -1
var _unicorn_turn20: Dictionary = {}
var _zero_hand20: Dictionary = {}
var _character_tokens20: Dictionary = {}
var _tumor_saves20: Dictionary = {}
var _next_attack_damage20: Dictionary = {}
var _shop_counters20: Dictionary = {}
var _d8_next20: Dictionary = {}
var _last_die_sides20 := 6
var _last_raw_die20 := 1
var _top_loot20: Dictionary = {}
var _forced_activation20 := false
var _coop_partners20: Array = []
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
## Сколько ближайших ходов каждого места пропускается целиком (включая дополнительные).
var skipped_turns: Array = []
var _ending_turn := false
var _discard_limit := 10
var _turn_resume := -1
var _end_after_deaths := false
var _end_discard_prepared := false
var _setting_up := false
var _room_bonuses: Array = []
var _extra_rooms20: Array = []
var _converted_room_bonuses20: Dictionary = {}
var _low_rolls21 := -1
var _outside_starters21: Array = []
var _first_target72: Dictionary = {}
var _target_serial21 := 0
var _bonus_started24: Dictionary = {}
var _guardian_resolved24 := false
var _primary_room24: Dictionary = {}
var _attack_prepared24 := false
var _mirror_turn25 := -1
var _mandatory_attacks25 := 0
var _pvp_attacked25: Dictionary = {}
var _room_extra_attack := 0 # Динамический дополнительный бой комнаты808 у текущего места.
var _room_extra_attack_used := false
var _card_delayed: Array = [] # Отложенные эффекты карт до конца текущего хода.
var _turn_roll_bonus: Array = []
var _turn_health_bonus: Array = []
var _next_hit_shields: Array = [] # Предотвращение одного следующего события, остаток не переносится.
var _temporary_eternal: Array = []
var _turn_damage_taken: Array = []
var _turn_monster_dc: Array = []
var _turn_monster_attack: Array = []
var _holy_saves: Dictionary = {} # Только следующая смерть до конца хода.
var _sibling_pending26: Array = []
var _sibling_reward26: Array = []
var _enigma_back26: Dictionary = {}
var _enigma_applied26: Dictionary = {}
var _lemegeton27: Dictionary = {}
var _tar_copied27: Dictionary = {}
var _credit_free := false
var _gold_deck_attacks := false
var _jail_owner := -1
var _era_face := 0
var _era_left := 0
var _turn_die_throws: Dictionary = {}
var _turn_attacks_started := 0
var _turn_combat_seen: Dictionary = {}
var _shop_buys_turn := 0
var _eggs_players: Array = []
var _eggs_monsters: Dictionary = {}
var _last_player_killer: Array = []
var _bonus_loot_plays: Array = []
var _lemon_effects: Array = []
var _forced_bosses: Array = []
var _lust_pending: Array = []
var _lust_victims: Dictionary = {}
var _shadow_penalty15: Dictionary = {}
var _crystal_predictions15: Array = []
var _spider_tokens15: Dictionary = {}
var _eternal_shop15: Dictionary = {}
var _roll_punishments15: Array = []
var _neighbor_faces15: Array = []
var _team_source15: Dictionary = {}
var _team_queue15: Array = []
var _blank_copies14: Dictionary = {}
var _forced_monsters14: Array = []
var _double_draw13: Dictionary = {}
var _compost_draws13 := 0
var _unlimited_loot13: Dictionary = {}
var _red_candles: Array = []
var _multi_owners: Array = []
var _multi_raw_bonus := 0
var _telepathy_faces: Dictionary = {}
var _next_attack_token := 0
var _room_activations: Dictionary = {}
var _room_loot_plays: Dictionary = {}
var _goals_counts := {"loot": 0, "monsters": 0, "gift": 0, "purchase": 0, "six": 0}
var _goals_rewarded := false
var _equality_running := false
var _plan_c_owner := -1
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
	return FSData.stat(id, "hp", 1) + (1 if _room_has20(797) else 0)

# --- Вызовы вверх по цепочке: реализация в модулях выше (переопределяется там) ---
func _finish_monster_reward(effect: Dictionary) -> void:
	pass
func _advance_auto_reward() -> void:
	pass
func _advance_card_automation() -> void:
	pass
func _card_automation_active() -> bool:
	return false
func _card_automation_enabled() -> bool:
	return true
func _treasure12_passives(_event: String, _data: Dictionary) -> void:
	pass
func _intercept_roll12(_effect: Dictionary, _attack: bool) -> bool:
	return false
func _intercept_missing_page(_effect: Dictionary, _value: int) -> bool:
	return false
func _card_choices() -> Array:
	return []
func _choose_card_effect(_index: int) -> bool:
	return false
func _card_choice_owner() -> int:
	return int(resolving.get("choice_owner", resolving.get("owner", current)))
func _can_guard21(_seat: int, _id: int) -> bool:
	return false
func _room_sale_tokens24() -> int:
	return 0
func _prepare_attack24(_seat: int) -> bool:
	return false
func _native_room_source24(_index: int) -> Dictionary:
	return {}
func _draw_shop_slot24() -> int:
	return -1 if _room_sale_tokens24() > 0 else _draw("treasure")
func _refill_shop24() -> void:
	for slot in shop.size():
		if int(shop[slot]) < 0:
			shop[slot] = _draw_shop_slot24()
func _must_buy24() -> bool:
	return false
func _tap_price24() -> int:
	return 3 if _card_automation_enabled() and _room_has20(756) else 0
func _character_can_pay24(seat: int) -> bool:
	var price := _tap_price24()
	return int(coins[seat]) >= price if price > 0 else bool(character_ready[seat])
func _pay_character24(seat: int) -> void:
	var price := _tap_price24()
	if price > 0:
		coins[seat] = int(coins[seat]) - price
		bank += price
	else:
		character_ready[seat] = false
func _effect(_argument: Dictionary) -> bool:
	return false
func _check_bonuses() -> void:
	pass
func _check_win() -> void:
	pass
func _printed_monster_reward(id: int) -> Dictionary:
	return RewardData.reward(id)
func _reward_win_targets() -> Array:
	var largest := 0
	for value: int in souls:
		largest = maxi(largest, value)
	var candidates: Array = []
	for seat in players.size():
		if int(souls[seat]) == largest:
			candidates.append(seat)
	return candidates
func _reward_damage_targets() -> Array:
	var candidates: Array = []
	for seat in players.size():
		if not dead[seat] and int(hp[seat]) > 0:
			candidates.append({"zone": "player", "target": seat})
	for slot in monsters.size():
		if int(monsters[slot].hp) > 0:
			candidates.append({"zone": "monster", "target": slot})
	return candidates
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
func _maximum_hand20(_seat: int, limit: int) -> int:
	return limit
func _save_player20(_seat: int) -> bool:
	return false
func _resolve_mushroom20(_effect: Dictionary) -> void:
	pass
func _start_stairway20(_seat: int) -> void:
	pass
func _discard_booster20(_effect: Dictionary) -> void:
	pass
func _release_stored20(_source: Dictionary) -> void:
	pass
func _put_monster20(source: Dictionary, destination: String) -> void:
	if destination == "bottom":
		decks.monster.push_front(int(source.id))
	else:
		discards.monster.append(int(source.id))
func _cover_monster20(source: Dictionary) -> Dictionary:
	return source
func _same_monster20(source: Dictionary, data: Dictionary) -> bool:
	return int(source.id) == int(data.get("card", -1))
func _same_damage_source20(source: Dictionary, data: Dictionary) -> bool:
	return int(source.id) == int(data.get("monster", -1))
func _ability_items20(owner: int) -> Array:
	return items[owner]
func _activation_source20(owner: int, arg: Dictionary, _room_source: bool = false) -> Dictionary:
	var index: int = int(arg.get("item", -1))
	return items[owner][index] if index >= 0 and index < items[owner].size() else {}
func _room_has20(id: int) -> bool:
	return room == id
func _native_rooms20() -> Array:
	return [room] if room >= 0 else []
func _replace_room20(_index: int) -> bool:
	return false
func _destroy_room20(_source: Dictionary, _owner: int, _soul: bool = false) -> bool:
	return false
func _restore_copy21(source: Dictionary) -> void:
	source.id = int(source.get("physical_id13", source.id))
	source.erase("physical_id13")
func _item_kind20(item: Dictionary) -> String:
	return FSData.item_response_kind(int(item.id))
func _treasure_amount21(seat: int, amount: int) -> int:
	return amount + (_item_count(seat, 52) if amount > 0 and _card_automation_enabled() else 0)
func _coin_loot_value22(effect: Dictionary) -> int:
	return FSData.coin_loot_value(int(effect.card))
func _give_treasures21(seat: int, amount: int) -> void:
	var count := _treasure_amount21(seat, amount)
	for index in count:
		var id := _draw("treasure")
		if id >= 0:
			_gain_item(seat, id)
func _dies_with_other_monster(id: int) -> bool:
	return false
func _end_battle() -> void:
	pass
func _monster_entered15(_entry: Dictionary) -> void:
	pass
func _prepare_penalty15(_seat: int) -> bool:
	return false
func _battle_roller15() -> int:
	return current
func _team_after_combat15(_roller: int) -> void:
	pass
func _replace_item_destroy15(_seat: int, _source: Dictionary) -> bool:
	return false
func _monster_max15(monster: Dictionary) -> int:
	return _monster_hp(int(monster.id))
func _copy_item14(_id: int, _permanent: bool) -> void:
	pass
func _fill_monster(initial: bool = false, slot: int = -1) -> void:
	pass
func _monster_aura(key: String) -> int:
	return 0
func _monster_evasion(monster: Dictionary) -> int:
	return 0
func _monster_attack(monster: Dictionary) -> int:
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
	_card_delayed.clear()
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
	_turn_roll_bonus = []
	_turn_health_bonus = []
	_next_hit_shields.clear()
	_temporary_eternal.clear()
	_turn_damage_taken = []
	_turn_monster_dc = []
	_turn_monster_attack = []
	_holy_saves.clear()
	_sibling_pending26.clear()
	_sibling_reward26.clear()
	_enigma_back26.clear()
	_enigma_applied26.clear()
	_lemegeton27.clear()
	_tar_copied27.clear()
	_low_rolls21 = -1
	_outside_starters21.clear()
	_first_target72.clear()
	_target_serial21 = 0
	_bonus_started24.clear()
	_guardian_resolved24 = false
	_primary_room24 = {}
	_attack_prepared24 = false
	_mirror_turn25 = -1
	_mandatory_attacks25 = 0
	_pvp_attacked25.clear()
	_extra_rooms20.clear()
	_converted_room_bonuses20.clear()
	_nail_turn20 = -1
	_unicorn_turn20.clear()
	_zero_hand20.clear()
	_character_tokens20.clear()
	_tumor_saves20.clear()
	_next_attack_damage20.clear()
	_shop_counters20.clear()
	_d8_next20.clear()
	_last_die_sides20 = 6
	_last_raw_die20 = 1
	_top_loot20.clear()
	_forced_activation20 = false
	_coop_partners20.clear()
	_credit_free = false
	_gold_deck_attacks = false
	_jail_owner = -1
	_era_face = 0
	_era_left = 0
	_turn_die_throws.clear()
	_turn_attacks_started = 0
	_turn_combat_seen.clear()
	_shop_buys_turn = 0
	_eggs_players.clear()
	_eggs_monsters.clear()
	_last_player_killer.clear()
	_bonus_loot_plays.clear()
	_lemon_effects.clear()
	_forced_bosses.clear()
	_lust_pending.clear()
	_lust_victims.clear()
	_shadow_penalty15.clear()
	_crystal_predictions15.clear()
	_spider_tokens15.clear()
	_gut_tokens16.clear()
	_next_attack_bonus17.clear()
	_next_any_attack_bonus17 = 0
	_eggs_respawn17.clear()
	_optional_blind17 = 0
	_forced_regular16 = 0
	_eternal_shop15.clear()
	_roll_punishments15.clear()
	_neighbor_faces15.clear()
	_team_source15.clear()
	_team_queue15.clear()
	_blank_copies14.clear()
	_forced_monsters14.clear()
	_double_draw13.clear()
	_compost_draws13 = 0
	_unlimited_loot13.clear()
	_red_candles.clear()
	_multi_owners.clear()
	_telepathy_faces.clear()
	_next_attack_token = 0
	_room_activations.clear()
	_room_loot_plays.clear()
	_reset_room_goals()
	_equality_running = false
	_plan_c_owner = -1
	extra_turns = []
	skipped_turns = []
	_ending_turn = false
	_discard_limit = 10
	_turn_resume = -1
	_end_after_deaths = false
	reward_boost = 1
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
		# 06.11 (владелец): частично автоматизированные карты временно не попадают в колоды настоящей партии.
		decks[kind] = decks[kind].filter(func(id): return int(id) not in excluded_cards28)
		_shuffle(decks[kind]); discards[kind] = []
	bonuses = FSData.pool("bonus", dlc)
	var characters := FSData.characters(dlc).duplicate(true)
	_shuffle(characters)
	for seat in players.size():
		damage_shields.append(0)
		_eggs_players.append({"white": 0, "red": 0, "black": 0})
		_last_player_killer.append(-1)
		_bonus_loot_plays.append(0)
		_turn_roll_bonus.append(0)
		_turn_health_bonus.append(0)
		_turn_damage_taken.append(false)
		_turn_monster_dc.append(0)
		_turn_monster_attack.append(0)
		skipped_turns.append(0)
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
			var starter := FSData.item_entry(eternal, true)
			starter["starter21"] = true
			items[seat].append(starter)
		_draw_loot(seat, 5 if int(chosen.card) == 908 else 3, "setup")
		if chosen.key == "cain":
			current = seat
	for i in 2:
		shop.append(_draw_shop_slot24())
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
		# 06.11 (владелец): сброс замешивается под низ колоды — ещё не виденные карты выходят раньше.
		var back: Array = discards[kind].duplicate(); discards[kind] = []; _shuffle(back)
		back.append_array(decks[kind])
		decks[kind] = back
		_note("Сброс замешан в колоду: " + {"loot": "добыча", "treasure": "сокровища", "monster": "монстры", "room": "комнаты"}.get(kind, kind))
	return int(decks[kind].pop_back()) if not decks[kind].is_empty() else -1
func _draw_loot(seat: int, count: int, reason: String = "effect") -> void:
	if reason == "effect" and count > 0:
		count += _has_item(seat, "luckytoe")
	count *= int(pow(2, int(_double_draw13.get(seat, 0))))
	var compost: bool = count > 0 and _compost_draws13 > 0
	if compost: _compost_draws13 -= 1
	for i in count:
		var id: int = int(discards.loot.pop_back()) if compost and not discards.loot.is_empty() else (-1 if compost else _draw("loot"))
		if id < 0:
			break
		hands[seat].append(id)
		if not _setting_up:
			_emit_passives("loot_draw", {"seat": seat, "card": id, "reason": reason})
func _gain_coins(seat: int, amount: int, poker_done: bool = false, equality_done: bool = false) -> void:
	if amount > 0 and _room_has20(807) and not _equality_running and not equality_done and _card_automation_enabled():
		_equality_running = true
		for offset in players.size():
			_gain_coins((seat + offset) % players.size(), amount, poker_done)
		_equality_running = false
		return
	if amount > 0 and seat == current and not poker_done and _card_automation_enabled():
		for item: Dictionary in items[seat]:
			if int(item.id) == 582 and int(item.get("poker_turn", -1)) != turn_serial:
				item["poker_turn"] = turn_serial
				_queue_passive(seat, 582, item, [{"op": "trinket_automation", "amount": 1, "context": "coins", "data": {"amount": amount, "equality_done": _equality_running or equality_done}}])
				return
	if amount > 0 and _card_automation_enabled():
		for item: Dictionary in items[seat]:
			if int(item.id) == 158:
				item.counters = int(item.counters) + amount
				_refresh_passive_stats()
				if seat == current and int(item.counters) >= 25: attack_left = maxi(attack_left, 99); attacked = false
				return
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
## Лента наглядных событий для стола (06.11): срабатывания пассивов и изменения бросков.
## Только показ: правила её не читают. Клиент показывает записи с номером больше последнего виденного.
## Карты, убранные из колод этой партии (Net задаёт FSData.PARTIAL_OFF28; тесты и фаззер — пусто).
var excluded_cards28: Array = []
## Ответы в чужой ход только пока стек не разрешился (окно тишины 5 с). Net включает для настоящей партии.
var strict_responses28 := false
var fx28: Array = []
var _fx_serial28 := 0
func _fx28(entry: Dictionary) -> void:
	_fx_serial28 += 1
	entry["n"] = _fx_serial28
	fx28.append(entry)
	if fx28.size() > 24:
		fx28 = fx28.slice(fx28.size() - 24)
func name_of(seat: int) -> String:
	return str(players[seat].name)
func _roll_die(seat: int = -1) -> int:
	var owner := current if seat < 0 else seat
	var sides := 8 if _card_automation_enabled() and _d8_next20.has(owner) else 6
	_d8_next20.erase(owner)
	var raw := clampi(int(roll_source.call()), 1, sides) if roll_source.is_valid() else _rng.randi_range(1, sides)
	_last_die_sides20 = sides
	_last_raw_die20 = raw
	if sides == 8:
		_note("D8: %s выбросил%d; результат по карте%d" % [name_of(owner), raw, mini(raw, 6)])
	return mini(raw, 6)

func _card_die(seat: int, attack_roll: bool = false) -> int:
	var count: int = int(_turn_die_throws.get(seat, 0))
	_turn_die_throws[seat] = count + 1
	_multi_raw_bonus = int(_turn_roll_bonus[seat]) + (_item_count(seat, 552) if count == 0 else 0)
	if count == 0 and _item_count(seat, 552) > 0:
		_fx28({"kind": "trigger", "seat": seat, "card": 552})
	if _multi_raw_bonus != 0:
		_fx28({"kind": "roll", "seat": seat, "amount": _multi_raw_bonus, "card": 552 if count == 0 and _item_count(seat, 552) > 0 else -1})
	if _card_automation_enabled() and (not _multi_owners.is_empty() or monsters.any(func(monster): return int(monster.id) == 328 and int(monster.hp) > 0) or (attack_roll and battle >= 0 and battle < monsters.size() and int(monsters[battle].id) == 258)):
		return _roll_die(seat)
	var face := clampi(_roll_die(seat) + _multi_raw_bonus, 1, 6)
	if _era_left > 0:
		_era_left -= 1
		face = _era_face
	return face

func _absorb_next_hit(zone: String, target: int, amount: int) -> int:
	if amount <= 0:
		return amount
	var prevented := 0
	var cap := amount
	for shield: Dictionary in _next_hit_shields.duplicate():
		if str(shield.zone) == zone and int(shield.target) == target:
			if shield.has("cap"): cap = mini(cap, int(shield.cap))
			prevented += int(shield.amount)
			_next_hit_shields.erase(shield)
	return maxi(0, cap - prevented)

## Получение контроля над физической картой души, включая перенос от другого игрока.
func _gain_soul_card(seat: int, card: Dictionary, gained: bool = true) -> void:
	if gained and (_room_has20(779) or curses[seat].has(744)):
		var pile: String = {"monster": "monster", "event": "monster", "loot": "loot", "treasure": "treasure", "room": "room"}.get(str(FSData.card(int(card.id)).get("kind", "")), "")
		if not pile.is_empty() and not discards[pile].has(int(card.id)): discards[pile].append(int(card.id))
		_note("Получение души запрещено: " + name_of(seat))
		return
	souls[seat] = int(souls[seat]) + int(card.value)
	soul_cards[seat].append(card)
	# Одна физическая карта может стоить несколько душ: триггеры учитывают всю ценность.
	for unit in maxi(0, int(card.value)):
		_emit_passives("soul_control", {"seat": seat, "card": int(card.id), "value": 1, "soul_value": int(card.value)})
		if gained:
			_emit_passives("soul_gain", {"seat": seat, "card": int(card.id), "value": 1})
	_refresh_passive_stats()

func _remove_item(seat: int, index: int, leaving: bool = false) -> Dictionary:
	var entry: Dictionary = items[seat].pop_at(index)
	if leaving:
		_release_stored20(entry)
	attack[seat] = maxi(0, int(attack[seat]) - int(entry.get("_attack_bonus", 0)))
	max_hp[seat] = maxi(1, int(max_hp[seat]) - int(entry.get("_health_bonus", 0)))
	hp[seat] = mini(int(hp[seat]), int(max_hp[seat]))
	if leaving and entry.has("physical_id13"):
		entry.id = int(entry.physical_id13)
		entry.erase("physical_id13")
		entry.erase("copy_permanent14")
	entry.erase("_attack_bonus")
	entry.erase("_health_bonus")
	_refresh_passive_stats()
	return entry
func _gain_item(seat: int, id: int, eternal: bool = false) -> void:
	var old_health: int = int(max_hp[seat])
	var entry := FSData.item_entry(id, eternal or bool(_eternal_shop15.get(id, false)))
	_eternal_shop15.erase(id)
	if id == 58:
		entry.counters = hands[seat].size()
	items[seat].append(entry)
	if not _setting_up and FSData.card(id).kind == "treasure":
		bonus_progress.treasures = int(bonus_progress.treasures) + 1
	_refresh_passive_stats()
	if not dead[seat] and int(max_hp[seat]) > old_health:
		hp[seat] = mini(int(max_hp[seat]), int(hp[seat]) + int(max_hp[seat]) - old_health)
	if id == 16:
		_queue_passive(seat, id, entry, [PassiveRules.operation("loot")])
	if id == 62:
		_queue_passive(seat, id, entry, [PassiveRules.operation("expand_shop", 2)])
	if PassiveRules.LOOT_SEARCH.has(id):
		_queue_passive(seat, id, entry, [{"op": "search_loot", "amount": 1, "keys": PassiveRules.LOOT_SEARCH[id]}])
	if id in [69, 77]:
		_queue_passive(seat, id, entry, [PassiveRules.operation("coins", 14 if id == 69 else 9)])
	if id == 14 and not _setting_up and _card_automation_enabled():
		_queue_passive(seat, id, entry, [{"op": "trinket_automation", "amount": 1, "context": "gain_item", "data": {}}])
func _destroy_item(seat: int, index: int) -> void:
	var source: Dictionary = items[seat][index]
	if _replace_item_destroy15(seat, source):
		return
	if int(source.id) == 518 and int(source.counters) == 0:
		source.counters = 1
		_refresh_passive_stats()
		_note("Пакет с обедом заменил уничтожение жетоном")
		return
	var destroyed_id: int = int(source.id)
	var item := _remove_item(seat, index, true)
	# Сундук заменяет уничтожение превращением: штраф уже выбрал этот предмет.
	# Повторно выбирать другую карту для того же штрафа не нужно.
	if destroyed_id == 243:
		_gain_soul_card(seat, {"id": int(item.id), "value": 1})
		_note(("Сундук уничтожен без получения души: " if _room_has20(779) or curses[seat].has(744) else "Сундук вместо уничтожения стал душой: ") + name_of(seat))
		return
	_discard_item(int(item.id))
	if destroyed_id == 505:
		_queue_passive(seat, 505, item, [PassiveRules.operation("treasure")])
	if destroyed_id == 474 and _card_automation_enabled():
		_queue_passive(seat, 474, item, [{"op": "trinket_automation", "amount": 1, "context": "destroyed", "data": {}}])
	if destroyed_id == 87 and _card_automation_enabled():
		_queue_passive(seat, 87, item, [{"op": "trinket_automation", "amount": 1, "context": "destroyed", "data": {"counters": int(item.counters)}}])
## Брелоки остаются картами лута и после перехода в зону предметов.
func _discard_item(id: int) -> void:
	var printed_kind: String = str(FSData.card(id).get("kind", ""))
	var kind := "loot" if printed_kind == "loot" else "monster" if printed_kind in ["monster", "event", "outside"] else "treasure"
	discards[kind].append(id)
func _has_item(seat: int, key: String) -> int:
	var count := 0
	for entry: Dictionary in _ability_items20(seat):
		if FSData.card(int(entry.id)).get("key", "") == key:
			count += 1
	return count
func _item_count(seat: int, id: int) -> int:
	var count := 0
	for item: Dictionary in _ability_items20(seat):
		if int(item.id) == id:
			count += 1
	return count

func _egg_count(zone: String, target: int) -> int:
	var marks: Dictionary = _eggs_players[target] if zone == "player" else _eggs_monsters.get(target, {})
	return int(marks.get("white", 0)) + int(marks.get("red", 0)) + int(marks.get("black", 0))

func _global_item_count(id: int) -> int:
	var count := 0
	for seat in players.size():
		count += _item_count(seat, id)
	return count

func _place_egg(zone: String, target: int, color: String) -> void:
	if zone == "monster" and not _eggs_monsters.has(target):
		_eggs_monsters[target] = {"white": 0, "red": 0, "black": 0}
	var marks: Dictionary = _eggs_players[target] if zone == "player" else _eggs_monsters[target]
	marks[color] = int(marks.get(color, 0)) + 1
	_refresh_passive_stats()
	_note("Положено яйцо: " + (name_of(target) if zone == "player" else FSData.title(target)))

func _permitted_player_attack_targets() -> Array:
	var out: Array = []
	if not _lust_pending.is_empty():
		for seat in _lust_pending:
			if int(seat) != current and not dead[int(seat)] and hp[int(seat)] > 0: out.append(int(seat))
		return out
	for seat in players.size():
		if seat != current and not dead[seat] and int(hp[seat]) > 0 and (required_player_attacks > 0 or (not attacked and attack_left > 0 and _global_item_count(100) > 0 and _egg_count("player", seat) > 0)):
			out.append(seat)
	return out
## Бонус хранится у источника: передача и уничтожение не оставляют его у прежнего владельца.
func _refresh_passive_stats() -> void:
	while _room_bonuses.size() < players.size():
		_room_bonuses.append(Vector2i.ZERO)
	while _character_attack_bonuses.size() < players.size():
		_character_attack_bonuses.append(0)
	for seat in players.size():
		var character_bonus: int = int(_character_tokens20.get(seat, 0))
		if int(chars[seat]) == 884:
			character_bonus += 2 if int(souls[seat]) >= 3 else (1 if int(souls[seat]) > 0 else 0)
		attack[seat] = maxi(0, int(attack[seat]) + character_bonus - int(_character_attack_bonuses[seat]))
		_character_attack_bonuses[seat] = character_bonus
		var room_bonus := Vector2i((1 if _room_has20(770) or (_room_has20(808) and int(souls[seat]) == int(souls.min())) else 0) + (_egg_count("player", seat) if _global_item_count(101) > 0 else 0), 1 if _room_has20(769) else 0)
		attack[seat] = maxi(0, int(attack[seat]) + room_bonus.x - _room_bonuses[seat].x)
		max_hp[seat] = maxi(1, int(max_hp[seat]) + room_bonus.y - _room_bonuses[seat].y)
		_room_bonuses[seat] = room_bonus
		var meat_cubes := 0
		for entry: Dictionary in items[seat]:
			if int(entry.id) in [30, 31, 32] or (_card_automation_enabled() and int(entry.id) == 89):
				meat_cubes += 1
		if _card_automation_enabled():
			for entry: Dictionary in soul_cards[seat]:
				if int(entry.id) in [30, 31, 32, 89]:
					meat_cubes += 1
		for entry: Dictionary in items[seat]:
			var bonus := PassiveRules.stat_bonus(int(entry.id), entry, hands[seat].size(), meat_cubes)
			bonus.x += int(entry.get("attack_tokens15", 0))
			bonus.y += int(entry.get("health_tokens15", 0))
			attack[seat] = maxi(0, int(attack[seat]) + bonus.x - int(entry.get("_attack_bonus", 0)))
			max_hp[seat] = maxi(1, int(max_hp[seat]) + bonus.y - int(entry.get("_health_bonus", 0)))
			entry["_attack_bonus"] = bonus.x
			entry["_health_bonus"] = bonus.y
		# Ограничиваем после всех источников, в том числе при пустом инвентаре.
		hp[seat] = mini(int(hp[seat]), int(max_hp[seat]))
	if not souls.is_empty():
		var additional := 1 if _room_has20(808) and not _room_extra_attack_used and int(souls[current]) == int(souls.min()) else 0
		if additional != _room_extra_attack:
			attack_left = maxi(0, attack_left + additional - _room_extra_attack)
			attacked = attack_left <= 0
		_room_extra_attack = additional
func _bonus_targets(id: int) -> Array:
	var result: Array = []
	if _card_automation_enabled() and id in [692, 693, 694, 695, 696]:
		return result
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
			if _room_has20(779) or curses[seat].has(744):
				continue
			if id == 694 and int(souls[seat]) != least:
				continue
			if id == 695 and items[seat].size() != least:
				continue
			result.append(seat)
	return result

## Передача монет не является получением монет из банка.
func _transfer_coins(giver: int, receiver: int, amount: int) -> void:
	var count := mini(maxi(0, amount), int(coins[giver]))
	coins[giver] = int(coins[giver]) - count
	coins[receiver] = int(coins[receiver]) + count
	if count > 0: _emit_passives("coin_give", {"seat": giver, "target": receiver, "amount": count})

func _reset_room_goals() -> void:
	_goals_counts = {"loot": 0, "monsters": 0, "gift": 0, "purchase": 0, "six": 0}
	_goals_rewarded = false

func _room_can_discard() -> bool:
	return not _card_automation_enabled() or room != 810 or _goals_rewarded

func _recharge_limit(seat: int) -> int:
	var limit: int = items[seat].size()
	if curses[seat].has(728): limit = 1
	if _room_has20(815):
		var most := 0
		for inventory: Array in items: most = maxi(most, inventory.size())
		if items[seat].size() == most: limit = mini(limit, 1)
	return limit

func _attack_tax(seat: int) -> int:
	if not _card_automation_enabled() or not _room_has20(804) or int(souls[seat]) == 0 or int(souls[seat]) != int(souls.max()): return 0
	return 2 * (players.size() - 1)

func _pay_attack_tax(seat: int) -> bool:
	var cost := _attack_tax(seat)
	if int(coins[seat]) < cost: return false
	if cost > 0:
		for other in players.size():
			if other != seat: _transfer_coins(seat, other, 2)
	return true

func _encounter_passives(_event: String, _data: Dictionary) -> void:
	pass

func _resolve_damage16(_effect: Dictionary) -> void:
	pass
func _after_auto_reward16(_effect: Dictionary) -> void:
	pass
func _death_item16(_seat: int, proposed: int) -> int:
	return proposed
func _pvp_defense16(_target: int) -> int:
	return 4

func _attack_target18(_source: Dictionary, _token: int) -> void:
	pass
func _damage_owner18() -> int:
	return int(resolving.get("owner", current))
