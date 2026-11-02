extends "res://games/four_souls/logic/fs_combat.gd"
## Four Souls, модуль правил: Ход, смерть, бонусные души, победа, кто действует.
## Часть цепочки fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules (FSRules — фасад).
## Отдельно не используется: состояние и вызовы общие через self.

func _advance_start() -> void:
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
	reward_boost = 1
	_turn_attack_rolls.clear()
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
	if room == 809:
		required_deck_attacks = 1
	for item: Dictionary in items[current]:
		if int(item.id) != 44:
			item.tapped = false
	_draw_loot(current, 1 + _has_item(current, "guppystail") + _has_item(current, "momscoinpurse") + _has_item(current, "momspurse") + (1 if room == 772 else 0), "step")
	if room == 766:
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
	if not (curses[current].has(723) or room == 781) or attacked or attack_left <= 0 or battle >= 0:
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
	attack_left = 99 if _item_count(current, 117) > 0 else 1
	for id in [24, 25, 26, 254, 877]:
		attack_left += _item_count(current, id)
	if room == 781:
		attack_left += 1
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
		monster.hp = _monster_hp(int(monster.id))
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
			if room == 779 or curses[seat].has(744):
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
	if phase == "game_over":
		return
	for seat in players.size():
		if souls[seat] >= 4:
			_cleanup_reward_cards()
			winner = seat; phase = "game_over"; _note("Четыре души! Победитель: " + name_of(seat)); return
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
