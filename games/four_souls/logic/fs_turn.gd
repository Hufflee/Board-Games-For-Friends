extends "res://games/four_souls/logic/fs_combat.gd"
## Four Souls, модуль правил: Ход, смерть, бонусные души, победа, кто действует.
## Часть цепочки fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules (FSRules — фасад).
## Отдельно не используется: состояние и вызовы общие через self.

func _advance_start() -> void:
	if not stack.is_empty():
		phase = "priority"
		_after_stack = "starting_continue"
		return
	if not _starting_choices.is_empty():
		phase = "starting_item"
		_note("Эдем выбирает стартовый предмет")
	else:
		_begin_turn()
func _begin_turn() -> void:
	# Пропущенный ход не даёт добор/перезарядку и не запускает его начало/конец.
	while int(skipped_turns[current]) > 0:
		skipped_turns[current] = int(skipped_turns[current]) - 1
		_note("%s пропускает ход" % name_of(current))
		_advance_turn_order()
	turn_serial += 1  # новый ход — часы чужих карт с нуля (FSRules.tick)
	_mandatory_attacks25 = 0
	_pvp_attacked25.clear()
	_room_extra_attack = 0
	_room_extra_attack_used = false
	_card_delayed.clear()
	_turn_damage_taken.fill(false)
	reward_boost = 1
	_turn_attack_rolls.clear()
	_turn_die_throws.clear()
	_turn_attacks_started = 0
	_turn_combat_seen.clear()
	_shop_buys_turn = 0
	_room_activations.clear()
	_room_loot_plays.clear()
	_forced_bosses.clear()
	_lust_pending.clear()
	_lust_victims.clear()
	_last_player_killer.fill(-1)
	_turn_faces.clear()
	_turn_kills = 0
	battle_player = -1
	required_player_attacks = 0
	discard_choice = {}
	_refresh_passive_stats()
	phase = "turn"; priority = current; free_loot = 1; bought = false; attacked = false; battle = -1
	# Новый ход больше не продолжает прежний end_turn/starting_continue после автоматического события.
	_after_stack = "turn"
	temporary_attack = []
	deck_attacks = 0
	required_deck_attacks = 0
	character_ready[current] = _item_count(current, 138) == 0
	_turn_allowances()
	# Комната 809 — обязательная атака верха колоды.
	if _room_has20(809):
		required_deck_attacks = 1
	var recharge_candidates: Array = []
	for item: Dictionary in items[current]:
		if bool(item.get("skip_recharge_once", false)):
			item.erase("skip_recharge_once")
			continue
		if int(item.id) != 44 and bool(item.tapped): recharge_candidates.append(int(item.id))
	if _card_automation_enabled() and recharge_candidates.size() > _recharge_limit(current):
		var source: int = 728 if curses[current].has(728) else 815
		_queue_passive(current, source, {}, [{"op": "trinket_automation", "amount": 1, "context": "recharge", "data": {"allowed": recharge_candidates}}])
		return
	else:
		for item: Dictionary in items[current]:
			if int(item.id) in recharge_candidates: item.tapped = false
	_complete_turn_start()

## Добор и начало хода ждут выбора ограниченной перезарядки.
func _complete_turn_start() -> void:
	if phase == "effect" and _refill_pending:
		resolving["refill_monsters"] = true
	_draw_loot(current, 1 + _has_item(current, "guppystail") + _has_item(current, "momscoinpurse") + _has_item(current, "momspurse") + (1 if _room_has20(772) else 0), "step")
	if _room_has20(766):
		_queue_passive(current, room, {}, [PassiveRules.operation("coins", 3)])
	# Ячейка, освобождённая прерванной наградой (_cancel_unresolved), добирается в начале хода.
	if _refill_pending and monsters.size() < monster_slots and phase == "turn":
		_after_stack = "refill"
		while monsters.size() < monster_slots and phase == "turn":
			var before := monsters.size()
			_fill_monster()
			if monsters.size() == before:
				break
		if phase == "turn":
			_after_stack = "turn"
	_refill_pending = false
	_emit_curses("turn_start")
	_emit_passives("turn_start")
	_note("Ход: " + name_of(current))
func _emit_curses(event: String) -> void:
	for id in curses[current].duplicate():
		var operations := PassiveRules.curse_ops(self, current, int(id), event)
		if not operations.is_empty():
			_queue_passive(current, int(id), {}, operations)

## Проклятие кровожадности: нельзя закончить ход, пока атака возможна.
func _must_attack() -> bool:
	if int(coins[current]) < _attack_tax(current): return false
	if not (curses[current].has(723) or _room_has20(781)) or attacked or attack_left <= 0 or battle >= 0:
		return false
	if not decks.monster.is_empty() or not discards.monster.is_empty():
		return true
	for monster: Dictionary in monsters:
		if not _untargetable(int(monster.id)):
			return true
	return false

## Лимиты хода текущего игрока: розыгрыш лута, покупки, атаки (с учётом предметов).
func _turn_allowances() -> void:
	free_loot = 1 + _item_count(current, 221) + _item_count(current, 226)
	buy_left = 1 + _item_count(current, 105) + _item_count(current, 173)
	attack_left = 99 if _item_count(current, 117) > 0 or items[current].any(func(item): return int(item.id) == 158 and int(item.counters) >= 25) else 1
	for id in [24, 25, 26, 254, 877]:
		attack_left += _item_count(current, id)
	if _room_has20(781):
		attack_left += 1
	_room_extra_attack = 1 if _room_has20(808) and not _room_extra_attack_used and int(souls[current]) == int(souls.min()) else 0
	attack_left += _room_extra_attack
func _end_turn() -> void:
	if not _ending_turn:
		_ending_turn = true
		phase = "turn"
		_emit_passives("turn_end")
		_emit_curses("turn_end")
		if phase == "priority":
			_after_stack = "end_turn"
			return
	if not _end_discard_prepared:
		_end_discard_prepared = true
		_discard_limit = mini(10, maxi(0, hands[current].size() - (_has_item(current, "guppystail") if _item_count(current, 523) == 0 else 0)))
		if curses[current].has(729):
			_discard_limit = mini(2, _discard_limit)
		_discard_limit = _maximum_hand20(current, _discard_limit)
	if hands[current].size() > _discard_limit:
		phase = "discard"
		return
	for entry in temporary_attack: attack[int(entry[0])] = maxi(0,int(attack[int(entry[0])])-int(entry[1]))
	temporary_attack.clear()
	for seat in players.size():
		max_hp[seat] = maxi(1, int(max_hp[seat]) - int(_turn_health_bonus[seat]))
	_turn_health_bonus.fill(0)
	_turn_roll_bonus.fill(0)
	_next_hit_shields.clear()
	_next_attack_damage20.clear()
	_turn_monster_dc.fill(0)
	_turn_monster_attack.fill(0)
	_holy_saves.clear()
	_shadow_penalty15.clear()
	_roll_punishments15.clear()
	_forced_regular16 = 0
	_next_attack_bonus17.clear()
	_next_any_attack_bonus17 = 0
	_optional_blind17 = 0
	_neighbor_faces15.clear()
	_team_queue15.clear()
	_team_source15.clear()
	_blank_copies14.clear()
	_forced_monsters14.clear()
	_double_draw13.clear()
	_unlimited_loot13.clear()
	for seat in players.size():
		for item: Dictionary in items[seat]:
			if item.has("physical_id13") and not bool(item.get("copy_permanent14", false)):
				_restore_copy21(item)
	_refresh_passive_stats()
	_red_candles.clear()
	_telepathy_faces.clear()
	_credit_free = false
	_gold_deck_attacks = false
	_forced_bosses.clear()
	_lust_pending.clear()
	_lust_victims.clear()
	_jail_owner = -1
	_era_face = 0
	_era_left = 0
	for index in range(_temporary_eternal.size() - 1, -1, -1):
		var temporary: Dictionary = _temporary_eternal[index]
		if _source_item_in_play(temporary.source):
			temporary.source.eternal = bool(temporary.eternal)
	_temporary_eternal.clear()
	for seat in players.size():
		hp[seat] = max_hp[seat]
		dead[seat] = false
		for item: Dictionary in items[seat]:
			item.erase("familiar_hp15")
		for soul: Dictionary in soul_cards[seat]:
			soul.erase("familiar_hp15")
	damage_shields.fill(0)
	_bonus_loot_plays.fill(0)
	_lemon_effects.clear()
	for monster: Dictionary in monsters:
		monster.erase("temporary_hp15")
		if int(monster.id) != 274:
			monster.hp = _monster_max15(monster)
		_expire_monster_modifiers(monster)
	_advance_turn_order()
	_ending_turn = false
	_end_discard_prepared = false
	_discard_limit = 10
	_begin_turn()

## Одна очередь для обычного перехода и пропуска, с сохранением места возврата из доп. ходов.
func _advance_turn_order() -> void:
	if not extra_turns.is_empty():
		if _turn_resume < 0:
			_turn_resume = (current + 1) % players.size()
		current = int(extra_turns.pop_front())
	else:
		current = _turn_resume if _turn_resume >= 0 else (current + 1) % players.size()
		_turn_resume = -1
		if current == 0: round_no += 1
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
func _new_death() -> bool:
	for seat in players.size():
		if hp[seat] <= 0 and not dead[seat]:
			return true
	return false
func _check_deaths() -> void:
	if not _death_queue.is_empty() or phase in ["effect","death","game_over"]: return
	for seat in players.size():
		if hp[seat] <= 0 and not dead[seat]:
			_death_queue.append(seat)
	if not _death_queue.is_empty():
		_death_resume = _after_stack if phase == "priority" else phase
		_push({"kind": "death", "owner": int(_death_queue[0])}, _death_resume)
func _check_bonuses() -> void:
	if phase == "game_over":
		return
	for id in bonuses:
		if claimed.has(id): continue
		var key: String = FSData.card(int(id)).key
		for seat in players.size():
			if _room_has20(779) or curses[seat].has(744):
				continue
			var guppy := 0
			for item in items[seat]:
				if str(FSData.card(int(item.id)).key).begins_with("guppy"): guppy += 1
			if key == "soulofgreed" and coins[seat] >= 25 or key == "soulofgluttony" and hands[seat].size() >= 10 or key == "soulofguppy" and guppy >= 2:
				claimed.append(id)
				_gain_soul_card(seat, {"id": int(id), "value": 1})
				_note(name_of(seat) + " получает " + FSData.title(int(id)))
				break
	_refresh_passive_stats()
func _check_win() -> void:
	if not resolving.is_empty() and int(resolving.get("card", -1)) == 285 and resolving.get("kind", "") == "reward" and not resolving.has("reward_winner"):
		return
	if phase == "game_over":
		return
	for seat in players.size():
		if souls[seat] >= 4:
			_cleanup_reward_cards()
			winner = seat; phase = "game_over"; _note("Четыре души! Победитель: " + name_of(seat)); return
func actor() -> int:
	if phase == "battle_roll":
		return _battle_roller15()
	if phase == "forced_discard":
		return int(discard_choice.target)
	if phase == "starting_item" and not _starting_choices.is_empty():
		return int(_starting_choices[0].owner)
	if phase == "priority": return priority
	if phase == "effect":
		return int(resolving.get("reroll_request", {}).get("owner", _card_choice_owner()))
	if phase == "death" and not _death_queue.is_empty(): return int(_death_queue[0])
	return current
func can_spectate() -> bool:
	return false
func spectator_seat() -> int:
	return -1
