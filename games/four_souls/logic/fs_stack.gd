extends "res://games/four_souls/logic/fs_state.gd"
## Four Souls, модуль правил: Стек и окно ответов: пассивы, LIFO-разрешение, ручной эффект, перебросы.
## Часть цепочки fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules (FSRules — фасад).
## Отдельно не используется: состояние и вызовы общие через self.

## Обязательные триггеры идут в общий стек и разрешаются после окна ответов.
func _emit_passives(event: String, data: Dictionary = {}) -> void:
	if _setting_up:
		return
	_encounter_passives(event, data)
	_treasure12_passives(event, data)
	if _card_automation_enabled() and event in ["death", "monster_death"]:
		_egg_death("player" if event == "death" else "monster", int(data.get("seat", -1)) if event == "death" else int(data.get("card", -1)), int(data.get("killer", -1)))
	if _card_automation_enabled() and event == "turn_end" and _plan_c_owner >= 0:
		var controller: int = _plan_c_owner
		_plan_c_owner = -1
		_queue_passive(controller, 111, {}, [{"op": "trinket_automation", "amount": 1, "context": "turn_end", "data": {}}])
	if _card_automation_enabled() and event == "attack_roll" and int(data.get("value", 0)) in [1, 2]:
		for lemon: Dictionary in _lemon_effects:
			if int(lemon.turn) == turn_serial:
				_queue_passive(int(lemon.owner), 107, {}, [{"op": "trinket_automation", "amount": 1, "context": "lemon_roll", "data": data.duplicate(true)}])
	if event == "death":
		for delayed: Dictionary in _card_delayed:
			if int(delayed.turn) == turn_serial and int(delayed.target) == int(data.get("seat", -1)):
				for target in players.size():
					if target != int(delayed.target) and target != int(delayed.owner):
						_queue_passive(target, int(delayed.card), {}, [{"op": "damage", "amount": 2}])
	for seat in players.size():
		for item: Dictionary in _ability_items20(seat).duplicate():
			if _card_automation_enabled() and TrinketCards.event(int(item.id), seat, current, event, data):
				_queue_passive(seat, int(item.id), item, [{"op": "trinket_automation", "amount": 1, "context": event, "data": data.duplicate(true)}])
			if _card_automation_enabled() and TreasureCards.event(int(item.id), seat, current, event, data):
				_queue_passive(seat, int(item.id), item, [{"op": "trinket_automation", "amount": 1, "context": event, "data": data.duplicate(true)}])
			if _card_automation_enabled() and ActiveCards.event(int(item.id), seat, current, event, data):
				_queue_passive(seat, int(item.id), item, [{"op": "trinket_automation", "amount": 1, "context": event, "data": data.duplicate(true)}])
			if _card_automation_enabled() and SecondaryCards.event(int(item.id), seat, current, event, data):
				_queue_passive(seat, int(item.id), item, [{"op": "trinket_automation", "amount": 1, "context": event, "data": data.duplicate(true)}])
			if _card_automation_enabled() and int(item.id) in [87, 89, 97]:
				if int(item.id) == 87 and event == "death" and seat == int(data.get("seat", -1)):
					_queue_passive(seat, 87, item, [{"op": "counter", "amount": 2}])
				if int(item.id) == 89 and event in ["death", "monster_death"]:
					_queue_passive(seat, 89, item, [{"op": "counter", "amount": 1}])
				if int(item.id) == 89 and event == "turn_end" and seat == current and int(item.counters) >= 12:
					_queue_passive(seat, 89, item, [{"op": "ultra_soul", "amount": 1}])
				if int(item.id) == 97 and event == "monster_damage" and seat == int(data.get("seat", -1)):
					_queue_passive(seat, 97, item, [{"op": "temporary_attack", "amount": 1}])
			if int(item.id) == 40 and event == "turn_end" and seat == current:
				_queue_passive(seat, 40, item, [{"op": "card_automation", "amount": 1, "context": event}])
			var operations := PassiveRules.event_ops(self, seat, item, event, data)
			if not operations.is_empty():
				_queue_passive(seat, int(item.id), item, operations)
	# Комната — тоже источник обязательных срабатываний.
	for room_id in _native_rooms20():
		for pair: Array in PassiveRules.room_ops(self, int(room_id), event, data):
			_queue_passive(int(pair[0]), int(room_id), {}, pair[1])

func _egg_death(zone: String, target: int, killer: int) -> void:
	if target < 0 or (zone == "player" and target >= players.size()):
		return
	var count := _egg_count(zone, target)
	if count > 0:
		for owner in players.size():
			if zone == "player" and killer >= 0 and killer < players.size() and _item_count(owner, 100) > 0:
				_queue_passive(killer, 100, {}, [{"op": "loot", "amount": 1}])
			if _item_count(owner, 102) > 0:
				for recipient in players.size():
					if _egg_count("player", recipient) == 0:
						_queue_passive(recipient, 102, {}, [{"op": "coins", "amount": 2}])
	if zone == "player":
		_eggs_players[target] = {"white": 0, "red": 0, "black": 0}
	else:
		_eggs_monsters.erase(target)
	_refresh_passive_stats()
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
			"ultra_soul":
				if _source_item_in_play(effect.source) and int(effect.source.counters) >= 12 and not _room_has20(779) and not curses[seat].has(744):
					for holder in players.size():
						for index in range(items[holder].size() - 1, -1, -1):
							if is_same(items[holder][index], effect.source):
								var converted := _remove_item(holder, index, true)
								_gain_soul_card(seat, {"id": int(converted.id), "value": 1})
			"trinket_automation":
				_begin_resolving({"kind": "item", "card": int(effect.card), "owner": seat, "source": effect.source, "conditional": true, "automation_context": str(operation.context), "automation_data": operation.data})
				return
			"card_automation":
				if not _source_item_in_play(effect.source):
					continue
				_begin_resolving({"kind": "item", "card": int(effect.card), "owner": seat, "automation_context": str(operation.context)})
				return
			"counter": effect.source.counters = maxi(0, int(effect.source.counters) + amount)
			"counter_soul":
				if not _source_item_in_play(effect.source):
					continue
				effect.source.counters = int(effect.source.counters) + amount
				if int(effect.source.counters) >= 3:
					if bool(effect.source.get("room_item20", false)):
						_destroy_room20(effect.source, current, true)
						continue
					# Источник мог перейти другому игроку после постановки триггера.
					for holder in players.size():
						for index in items[holder].size():
							if is_same(items[holder][index], effect.source):
								var item := _remove_item(holder, index, true)
								_gain_soul_card(holder, {"id": int(item.id), "value": 1})
								_note("Друг: третий жетон превращает карту в душу")
								break
			"manual_card":
				# У обязательного триггера свой владелец; это не новый розыгрыш после10с.
				_begin_resolving({"kind": "item", "card": int(effect.card), "owner": seat, "conditional": true})
				return
			"coins": _gain_coins(seat, amount)
			"give_coin":
				var giver: int = operation["from"]
				var count := mini(int(coins[giver]), amount)
				_transfer_coins(giver, seat, count)
			"damage": _damage_player(seat, amount, {"attacker": -1})
			"skip_turn":
				skipped_turns[seat] = int(skipped_turns[seat]) + amount
			"loot": _draw_loot(seat, amount)
			"treasure":
				_give_treasures21(seat, amount)
			"kill_self": hp[seat] = 0
			"expand_shop":
				for i in amount:
					var card := _draw("treasure")
					if card >= 0:
						shop.append(card)
			"tap_character": character_ready[seat] = false
			"ready_character": character_ready[seat] = true
			"tap_all":
				for entry: Dictionary in items[seat]:
					entry.tapped = true
				character_ready[seat] = false
			"discard_loot":
				if amount > 0 and not hands[seat].is_empty():
					var resume: String = _after_stack if phase == "priority" else phase
					_push({"kind": "forced_discard", "owner": seat, "target": seat, "card": int(effect.card), "amount": amount}, resume)
			"loot_from_discard":
				for index in range(discards.loot.size() - 1, -1, -1):
					if str(FSData.card(int(discards.loot[index])).get("key", "")) in operation.keys:
						hands[seat].append(int(discards.loot.pop_at(index)))
						break
			"search_loot":
				# 10 верхних карт: подходящие — в руку, остальные — под низ колоды в прежнем порядке.
				var revealed: Array = decks.loot.slice(maxi(0, decks.loot.size() - 10))
				decks.loot.resize(decks.loot.size() - revealed.size())
				var rest: Array = []
				for id in revealed:
					if str(FSData.card(int(id)).get("key", "")) in operation.keys:
						hands[seat].append(int(id))
					else:
						rest.append(int(id))
				rest.append_array(decks.loot)
				decks.loot = rest
			"temporary_attack":
				attack[seat] = int(attack[seat]) + amount
				temporary_attack.append([seat, amount])
			"heal": hp[seat] = mini(int(max_hp[seat]), int(hp[seat]) + maxi(0, amount))
			"extra_attack":
				if seat == current:
					attack_left += maxi(0, amount); attacked = attack_left <= 0
			"recharge":
				if _source_item_in_play(effect.source):
					effect.source.tapped = false
	_refresh_passive_stats()
	_note("Пассив: %s · %s" % [name_of(seat), FSData.title(int(effect.card))])
	_continue_stack()
func _push(effect: Dictionary, resume: String) -> void:
	if phase != "priority": _after_stack = resume
	stack.append(effect); phase = "priority"; priority = (int(effect.owner) + 1) % players.size(); passes = 0
	_note(name_of(int(effect.owner)) + " → " + FSData.effect_title(effect))
func _continue_stack() -> void:
	if phase == "game_over":
		return
	# Маркер вложенного эффекта не ждёт ответов: внешний ручной эффект продолжается сразу
	# (если никто не умер — смерть разрешается раньше).
	if resolving.is_empty() and not stack.is_empty() and bool(stack.back().get("nested", false)) and _death_queue.is_empty() and not _new_death():
		_resolve_top()
		return
	if _after_stack == "effect" and not resolving.is_empty():
		phase = "priority" if stack.size() > _resolving_base else "effect"
		_advance_card_automation()
		_advance_auto_reward()
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
			_push({"kind":"monster_death","card":int(m.id),"owner":current,"slot":i,"monster_ref20":m},_after_stack)
			return
	if not stack.is_empty():
		phase = "priority"; passes = 0; priority = current
	else:
		phase = _after_stack
		if phase == "death" and not _death_queue.is_empty() and _prepare_penalty15(int(_death_queue[0])):
			return
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
	if effect.kind == "mushroom_counter20":
		_resolve_mushroom20(effect)
		return
	if effect.kind == "character_loot":
		var owner: int = int(effect.owner)
		_bonus_loot_plays[owner] = int(_bonus_loot_plays[owner]) + 1
		_note("%s активирует персонажа: дополнительный розыгрыш добычи" % name_of(owner))
		_continue_stack()
		return
	if effect.kind == "damage16":
		_resolve_damage16(effect)
		return
	if effect.kind == "resume_deaths":
		_resume_after_deaths()
		return
	if effect.kind == "resume_effect":
		resolving = effect.previous.effect
		_resolving_base = mini(int(effect.previous.get("base", stack.size())), stack.size())
		_after_stack = str(effect.previous.resume)
		peek = effect.previous.peek
		# Ответы, лежавшие над внешним эффектом до вложенного, ещё ждут закрытия.
		phase = "priority" if stack.size() > _resolving_base else "effect"
		_advance_card_automation()
		_advance_auto_reward()
		return
	if effect.kind == "passive":
		_resolve_passive(effect)
		return
	if effect.kind == "monster_death":
		var slot: int = int(effect.slot)
		if effect.has("monster_ref20"):
			slot = -1
			for index in monsters.size():
				if is_same(monsters[index], effect.monster_ref20):
					slot = index
					break
		if slot >= 0 and slot < monsters.size() and int(monsters[slot].id) == int(effect.card) and int(monsters[slot].hp) <= 0:
			if _replace_monster_death(slot):
				_continue_stack()
				return
			# Каменюка и Голова смерти гибнут от смерти другого открытого монстра.
			for other in monsters.size():
				if other != slot and _dies_with_other_monster(int(monsters[other].id)):
					monsters[other].hp = 0
			var reward := {"kind": "reward", "card": int(effect.card), "owner": current, "slot": slot, "monster_ref20": monsters[slot]}
			var printed := _printed_monster_reward(int(effect.card))
			if bool(monsters[slot].get("ambush_return20", false)):
				# Уход в промежуточную зону смерти заменён возвратом: физическая карта не становится душой/предметом.
				printed.erase("souls")
				printed.erase("self_item")
				printed.erase("victory_most_souls")
				if printed.is_empty():
					printed = {"coins": 0}
			if not printed.is_empty():
				for resource: String in ["coins", "loot"]:
					if printed.has(resource + "_per_counter"):
						printed[resource] = int(printed[resource + "_per_counter"]) * int(monsters[slot].get("counters", 0))
				reward["auto_reward"] = printed
				reward["reward_step"] = 0
				reward["resource_recipient"] = int(monsters[slot].get("slayer", current)) if bool(printed.get("recipient_slayer", false)) else current
				reward["death_text_done"] = not bool(printed.get("manual_death", false))
				if (printed.has("roll") or bool(printed.get("return_roll", false))) and bool(reward.death_text_done):
					reward["requires_reward_roll"] = true
				if bool(printed.get("double_lethal_six", false)) and int(monsters[slot].get("lethal_attack_roll", 0)) == 6:
					reward["reward_multiplier"] = 2
			_begin_resolving(reward)
			if int(effect.card) == 429 and not _card_automation_enabled():
				_prepare_peep_spawn()
			if int(effect.card) == 358:
				resolving["requires_reward_roll"] = true
			if int(effect.card) == 268:
				required_player_attacks += 1
			bonus_progress.monsters = int(bonus_progress.monsters) + 1
			if int(monsters[slot].get("slayer", current)) == current:
				_turn_kills += 1
			_emit_passives("monster_death", {"seat": int(monsters[slot].get("slayer", current)), "card": int(effect.card), "physical_id20": int(monsters[slot].get("physical_id20", monsters[slot].id))})
			_advance_auto_reward()
		else:
			if slot >= 0 and slot < monsters.size(): monsters[slot]["death_pending"] = false
			_continue_stack()
		return
	if effect.kind == "death":
		var dying: int = int(effect.owner)
		if _card_automation_enabled() and dying == current and hp[dying] <= 0 and not bool(effect.get("one_up_checked", false)):
			effect["one_up_checked"] = true
			for entry: Dictionary in items[dying]:
				if int(entry.id) == 142 and not bool(entry.eternal):
					stack.append(effect)
					_begin_resolving({"kind": "item", "card": 142, "owner": dying, "source": entry, "conditional": true, "automation_context": "would_die"})
					return
		if _card_automation_enabled() and hp[dying] <= 0:
			for entry: Dictionary in items[dying]:
				var marker := "collar14_%d" % int(entry.get("physical_id13", entry.id))
				if int(entry.id) == 210 and not bool(effect.get(marker, false)):
					effect[marker] = true
					stack.append(effect)
					_begin_resolving({"kind": "item", "card": 210, "owner": dying, "source": entry, "conditional": true, "automation_context": "would_die"})
					return
		if _card_automation_enabled() and hp[dying] <= 0 and not bool(effect.get("ankh_checked", false)) and _item_count(dying, 687) > 0:
			effect["ankh_checked"] = true
			stack.append(effect)
			_begin_resolving({"kind": "item", "card": 687, "owner": dying, "conditional": true, "automation_context": "would_die"})
			return
		if hp[dying] <= 0 and _save_player20(dying):
			_death_queue.erase(dying)
			_resume_after_deaths()
			return
		if hp[dying] <= 0 and _holy_saves.has(dying):
			var controller: int = int(_holy_saves[dying])
			_holy_saves.erase(dying)
			hp[dying] = 1
			_death_queue.erase(dying)
			_end_after_deaths = _end_after_deaths or controller == current
			_note("Святая карта предотвращает смерть: " + name_of(dying))
			_resume_after_deaths()
			return
		if hp[dying] <= 0:
			if (battle_player >= 0 and dying in [current, battle_player]) or (battle >= 0 and dying == current):
				_end_battle()
				_death_resume = "turn"
			phase = "death"
			bonus_progress.deaths = int(bonus_progress.deaths) + 1
			_emit_passives("death", {"seat": dying, "killer": int(_last_player_killer[dying])})
			if phase == "death":
				_prepare_penalty15(dying)
		else:
			_death_queue.erase(dying)
			_resume_after_deaths()
		return
	if effect.kind == "forced_discard":
		if _card_automation_enabled() and _item_count(int(effect.target), 523) > 0:
			_continue_stack()
			return
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
			_turn_attacks_started += 1
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
		if not bool(effect.get("suppress_passives", false)) and _intercept_roll12(effect, false): return
		last_roll = clampi(int(effect.value),1,6)
		if not bool(effect.get("suppress_passives", false)) and _intercept_missing_page(effect, last_roll):
			return
		var stack_before := stack.size()
		var attack_reroll: bool = _rerolls_attack(effect)
		if not attack_reroll and not bool(effect.get("passives_done", false)) and not bool(effect.get("suppress_passives", false)):
			_roll_passives(last_roll, int(effect.owner))
		if effect.has("reroll_index"):
			var index: int = _reroll_index(effect)
			if index >= 0:
				stack[index].value = last_roll
				stack[index].erase("final_value")
				stack[index].erase("bonus_applied17")
				stack[index]["passives_done"] = true
				# Сохраняем прежний маркер замены, но числовые триггеры атаки ещё впереди.
				if attack_reroll:
					stack[index]["attack_passives_pending"] = true
		var previous: Dictionary = paused_effects.pop_back()
		var restored: Dictionary = previous.effect
		if restored.has("automation_steps") and not effect.has("reroll_index"):
			restored["automation_roll"] = last_roll
		if restored.get("kind", "") == "reward" and (int(restored.get("card", -1)) == 358 or bool(restored.get("auto_reward", {}).get("return_roll", false))):
			restored["reward_roll"] = last_roll
			restored["return_to_deck"] = last_roll in [1, 6]
		elif restored.has("auto_reward") and bool(restored.get("requires_reward_roll", false)):
			restored["reward_roll"] = last_roll
		_after_stack = str(previous.resume)
		if stack.size() > stack_before:
			# Триггеры броска разрешаются первыми; эффект вернёт маркер (resolving пока пуст).
			stack.insert(stack_before, {"kind": "resume_effect", "owner": int(restored.owner), "previous": previous})
			phase = "priority"
		else:
			resolving = restored; peek = previous.peek
			_resolving_base = stack.size()
			phase = "effect"
		return
	if effect.kind == "roll":
		if _intercept_roll12(effect, true): return
		var trigger_start := stack.size()
		var roller: int = int(effect.owner)
		var ordinal: int = int(_turn_attack_rolls.get(roller, 0)) + 1
		if _card_automation_enabled() and ordinal == 1 and _item_count(roller, 98) > 0 and not bool(effect.get("marked_checked", false)):
			effect["marked_checked"] = true
			var token := _roll_token(effect)
			stack.append(effect)
			_begin_resolving({"kind": "item", "card": 98, "owner": roller, "conditional": true, "automation_context": "first_attack_roll", "automation_data": {"token": token}})
			return
		var modifiers: Dictionary = PassiveRules.attack_modifiers(items[roller], ordinal)
		if _card_automation_enabled():
			modifiers.roll_bonus = int(modifiers.roll_bonus) + _item_count(roller, 207) + _item_count(roller, 235) + (_item_count(roller, 228) if int(coins[roller]) == 0 else 0)
		last_roll = int(effect.get("final_value", PassiveRules.attack_roll(int(effect.value), modifiers)))
		if not bool(effect.get("suppress_passives", false)) and _intercept_missing_page(effect, last_roll):
			return
		if int(modifiers.roll_bonus) != 0:
			_note("Бросок атаки %s №%d: %d %+d → %d (итог)" %
				[name_of(roller), ordinal, int(effect.value), int(modifiers.roll_bonus), last_roll])
		if not bool(effect.get("passives_done", false)) or bool(effect.get("attack_passives_pending", false)):
			_roll_passives(last_roll, roller)
		# Считаем разрешившиеся броски атаки, включая промахи и перебросы через effect_roll.
		if _card_automation_enabled() and not effect.has("next_damage20"):
			effect["next_damage20"] = int(_next_attack_damage20.get(roller, 0))
			_next_attack_damage20.erase(roller)
		# Небоевой effect_roll сам по себе сюда не попадает; итог атаки учитывается один раз.
		_turn_attack_rolls[roller] = ordinal
		_emit_passives("attack_roll", {"seat": roller, "count": int(_turn_attack_rolls[roller]), "value": last_roll})
		# Как и прочие триггеры броска, бонус угля разрешится над combat.
		# Числовой урон текущей атаки фиксируется ниже до разрешения этого бонуса.
		if battle_player >= 0:
			if battle_player not in _player_attack_targets() or dead[current] or hp[current] <= 0:
				_continue_stack()
				return
			var hit_player: bool = PassiveRules.attack_hits(last_roll, _pvp_defense16(battle_player), modifiers)
			if not hit_player:
				_emit_passives("attack_miss", {"seat": roller})
			var player_damage: int = int(attack[roller] if hit_player else attack[battle_player]) + ((_item_count(roller, 652) + _item_count(roller, 221) + _item_count(roller, 254)) if _card_automation_enabled() and hit_player and ordinal == 1 else 0)
			if hit_player:
				player_damage += int(effect.get("next_damage20", 0))
			if _card_automation_enabled() and hit_player and _turn_attacks_started == 2:
				player_damage += 2 * _item_count(roller, 25)
			_push({"kind": "player_combat", "owner": roller, "card": 268, "target": battle_player,
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
		if int(m.id) == 273 and last_roll in effect.get("neighbor_faces15", []):
			hit = false
		var damage: int = int(attack[roller]) if hit else _monster_attack(m)
		if hit:
			damage += int(effect.get("next_damage20", 0))
		if _card_automation_enabled() and hit and ordinal == 1:
			damage += _item_count(roller, 652) + _item_count(roller, 221) + _item_count(roller, 254)
		if _card_automation_enabled() and hit and _turn_attacks_started == 2:
			damage += 2 * _item_count(roller, 25)
		if not hit:
			_emit_passives("attack_miss", {"seat": roller})
		if not hit and last_roll == 1 and FSData.card(int(m.id)).get("key", "") == "leaper":
			damage *= 2
		if _card_automation_enabled() and int(m.id) == 355 and last_roll == 1:
			var incoming := {"kind": "damage16", "owner": -1, "zone": "player", "target": roller, "damage": _monster_attack(m), "context": {"combat": true, "monster": 355, "value": last_roll}}
			stack.insert(trigger_start, incoming)
			trigger_start += 1
			hit = true
			damage = int(attack[roller])
		_push({"kind":"combat","owner":roller,"card":int(m.id),"hit":hit,"damage":damage,"value":last_roll},"battle_roll")
		# Урон от результата ждёт обязательных триггеров самого броска.
		stack.insert(trigger_start, stack.pop_back())
		return
	if not _card_automation_enabled() and effect.kind == "event" and int(effect.card) == 715:
		required_deck_attacks = maxi(required_deck_attacks, 2)
		attack_left = maxi(attack_left, required_deck_attacks - deck_attacks)
		attacked = attack_left <= 0
		discards.monster.append(715)
		_continue_stack()
		return
	var card := FSData.card(int(effect.card))
	var kind: String = str(card.lua.get("type", ""))
	if _card_automation_enabled() and effect.kind == "loot" and int(effect.card) == 475:
		_begin_resolving(effect)
	elif effect.kind == "loot" and int(effect.card) == 528:
		if bool(effect.get("boost_pending", false)):
			reward_boost = mini(1073741824, reward_boost * 2)
			if not bool(effect.get("loot_copy14", false)):
				discards.loot.append(528)
			_note("Счастливая монета: награды ×%d до конца хода" % reward_boost)
		else:
			# Монета сначала даёт ресурс; вложенные пассивы не теряют саму карту.
			var continuation := effect.duplicate(true)
			continuation["boost_pending"] = true
			continuation["nested"] = true
			stack.append(continuation)
			_gain_coins(int(effect.owner), 1)
		_continue_stack()
	elif effect.kind == "loot" and FSData.coin_loot_value(int(effect.card)) > 0:
		_gain_coins(int(effect.owner), FSData.coin_loot_value(int(effect.card)))
		if not bool(effect.get("loot_copy14", false)):
			discards.loot.append(int(effect.card))
		_continue_stack()
	elif effect.kind == "loot" and kind == "lsoul":
		if not bool(effect.get("loot_copy14", false)):
			_gain_soul_card(int(effect.owner), {"id": int(effect.card), "value": 1})
		_refresh_passive_stats()
		_continue_stack()
	elif effect.kind == "loot" and kind == "trinkets":
		_gain_item(int(effect.owner), int(effect.card))
		_continue_stack()
	else:
		_begin_resolving(effect)
## Ручной эффект начинает разрешаться. Если в этот момент уже идёт другой (ответ на ручной
## эффект), внешний ждёт под маркером resume_effect и вернётся, когда вложенный завершится.
func _begin_resolving(effect: Dictionary) -> void:
	if not resolving.is_empty():
		stack.append({"kind": "resume_effect", "owner": int(resolving.owner), "nested": true,
			"previous": {"effect": resolving, "resume": _after_stack, "peek": peek, "base": _resolving_base}})
		peek = {}
		_after_stack = "effect"
	# Своё продолжение эффект носит с собой: пассивы во время него переписывают _after_stack на "effect".
	if not effect.has("_resume"):
		effect["_resume"] = _after_stack
	resolving = effect
	_resolving_base = stack.size()
	phase = "effect"
func _finish_responses() -> void:
	var limit := 0
	while phase == "priority" and stack.size() > _response_floor() and limit < 500:
		_resolve_top(); limit += 1
	# Ответы на ручной эффект закрыты — возвращаемся к нему, не трогая внешний стек.
	if phase == "priority" and _response_floor() > 0 and stack.size() <= _resolving_base:
		phase = "effect"
	_advance_card_automation()
	_advance_auto_reward()
	if phase in ["effect","death","priority","discard_target","forced_discard"]: return
	var followup := next_action.duplicate(true)
	next_action = {}
	if not followup.is_empty() and phase != "game_over":
		action(int(followup.seat),str(followup.kind),followup.arg)
## Ниже этой высоты окно ответов не закрывается, пока идёт ручной эффект.
func _response_floor() -> int:
	return _resolving_base if _after_stack == "effect" and not resolving.is_empty() else 0
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
		if pending.has("booster_cards20"):
			_discard_booster20(pending)
		if pending.get("kind", "") == "loot" and not bool(pending.get("loot_copy14", false)) and not bool(pending.get("under_deck", false)) and not pending.has("given_to") and not bool(pending.get("kept_as_item", false)) and not bool(pending.get("deployed_monster20", false)):
			var id: int = pending.card
			if not discarded.has(id):
				discards.loot.append(id)
				discarded[id] = true
		elif pending.get("kind", "") == "event" and not bool(pending.get("attached", false)):
			discards.monster.append(int(pending.card))
	# Прерванная награда всё равно снимает умершего монстра (в сброс или уже в души).
	var rewarded := {}
	for pending: Dictionary in pending_effects:
		if pending.get("kind", "") != "reward" or rewarded.has(int(pending.card)):
			continue
		rewarded[int(pending.card)] = true
		var slot: int = int(pending.get("slot", -1))
		if slot >= 0 and slot < monsters.size() and int(monsters[slot].id) == int(pending.card):
			_finish_monster_reward(pending)
			_refill_pending = true
	stack.clear()
	paused_effects.clear()
	next_action = {}
	peek = {}
	battle = -1
## При немедленной победе ручные реакции больше не ждём, но полученная карта уже должна покинуть ряд.
func _cleanup_reward_cards() -> void:
	var pending: Array = stack.duplicate()
	if not resolving.is_empty():
		pending.append(resolving)
	for paused: Dictionary in paused_effects:
		pending.append(paused.effect)
	var seen := {}
	while not pending.is_empty():
		var effect: Dictionary = pending.pop_back()
		if effect.get("kind", "") == "resume_effect" and effect.has("previous"):
			pending.append(effect.previous.effect)
		if effect.get("kind", "") != "reward" or seen.has(int(effect.card)):
			continue
		if bool(effect.get("kept_as_soul", false)) or bool(effect.get("kept_as_item", false)):
			seen[int(effect.card)] = true
			_finish_monster_reward(effect)

func _pending_manual_passives() -> bool:
	return (
		phase == "priority"
		and _after_stack == "effect"
		and not resolving.is_empty()
		and stack.size() > _resolving_base
	)
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
	# Фруктовый пирог: одинаковый результат дважды подряд за ход перезаряжает его.
	if not _turn_faces.is_empty() and int(_turn_faces.back()) == value:
		for seat in players.size():
			for entry: Dictionary in items[seat]:
				if int(entry.id) == 120 and bool(entry.tapped):
					_queue_passive(seat, 120, entry, [PassiveRules.operation("recharge")])
	_turn_faces.append(value)
	# Монстры кладутся в стек раньше предметов; накрытые карты не в игре.
	for entry: Dictionary in monsters:
		var id: int = int(entry.id)
		if _card_automation_enabled() and id in [439, 440, 445]:
			continue
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
		if FSData.card(int(entry.id)).get("key", "") == "cursedtumor" and not (_card_automation_enabled() and int(entry.id) == 376):
			tumors += 1
	if tumors == 0:
		return
	_note("Проклятая опухоль: четвёрка наносит всем игрокам %d урона" % tumors)
	for seat in players.size():
		if not dead[seat]:
			_damage_player(seat, tumors)

## Замещение проверяется при разрешении смерти, до награды/души и триггеров убийства.
## 264 — именно Summer of Isaac: смертельный бросок6 убивает, иной источник спасает.
func _replace_monster_death(slot: int) -> bool:
	var monster: Dictionary = monsters[slot]
	var id: int = int(monster.id)
	if id == 299 or (id == 284 and int(monster.get("counters", 0)) < 2):
		monster["counters"] = int(monster.get("counters", 0)) + 1
		monster.hp = _monster_hp(id)
		monster.death_pending = false
		monster.erase("lethal_attack_roll")
		if id == 299 and int(monster.counters) >= 6:
			_finish_monster_reward({"card": id, "owner": current, "slot": slot})
		_queue_passive(current, id, {}, [PassiveRules.operation("treasure" if id == 284 else "coins", 1 if id == 284 else 6)])
		_note("Смерть предотвращена: %s · жетонов%d" % [FSData.title(id), int(monster.counters)])
		return true
	if id == 362 and int(monster.get("death_saved_turn", -1)) != turn_serial:
		monster["death_saved_turn"] = turn_serial
		monster.hp = 2
		monster.death_pending = false
		monster.erase("lethal_attack_roll")
		monster.dc = int(monster.dc) + (1 if _card_automation_enabled() else -1)
		monster.at = int(monster.at) - 1
		monster["temporary_dc"] = int(monster.get("temporary_dc", 0)) + (1 if _card_automation_enabled() else -1)
		monster["temporary_at"] = int(monster.get("temporary_at", 0)) - 1
		_note("Всадник: первая смерть хода предотвращена,2HP,+1защиты/−1атаки до конца хода")
		return true
	if int(monster.id) != 264 or int(monster.get("lethal_attack_roll", 0)) == 6:
		return false
	monster.hp = _monster_max15(monster)
	monster.death_pending = false
	monster.erase("lethal_attack_roll")
	monster.dc = int(monster.dc) + 1
	monster.at = int(monster.at) + 1
	monster["temporary_dc"] = int(monster.get("temporary_dc", 0)) + 1
	monster["temporary_at"] = int(monster.get("temporary_at", 0)) + 1
	_note("Всадник без головы: смерть предотвращена, полное здоровье, +1 защиты/атаки до конца хода")
	# Душевая ценность карты выдаётся при настоящей смерти, не входит в эту награду.
	_queue_passive(current, 264, monster, [PassiveRules.operation("treasure", 1)])
	return true
