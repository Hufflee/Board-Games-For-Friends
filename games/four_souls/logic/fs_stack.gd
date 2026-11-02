extends "res://games/four_souls/logic/fs_state.gd"
## Four Souls, модуль правил: Стек и окно ответов: пассивы, LIFO-разрешение, ручной эффект, перебросы.
## Часть цепочки fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules (FSRules — фасад).
## Отдельно не используется: состояние и вызовы общие через self.

## Обязательные триггеры идут в общий стек и разрешаются после окна ответов.
func _emit_passives(event: String, data: Dictionary = {}) -> void:
	if _setting_up:
		return
	for seat in players.size():
		for item: Dictionary in items[seat].duplicate():
			var operations := PassiveRules.event_ops(self, seat, item, event, data)
			if not operations.is_empty():
				_queue_passive(seat, int(item.id), item, operations)
	# Комната — тоже источник обязательных срабатываний.
	if room >= 0:
		for pair: Array in PassiveRules.room_ops(self, room, event, data):
			_queue_passive(int(pair[0]), room, {}, pair[1])
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
			"counter_soul":
				if not _source_item_in_play(effect.source):
					continue
				effect.source.counters = int(effect.source.counters) + amount
				if int(effect.source.counters) >= 3:
					# Источник мог перейти другому игроку после постановки триггера.
					for holder in players.size():
						for index in items[holder].size():
							if is_same(items[holder][index], effect.source):
								var item := _remove_item(holder, index)
								_gain_soul_card(holder, {"id": int(item.id), "value": 1})
								_note("Друг: третий жетон превращает карту в душу")
								break
			"manual_card":
				# У обязательного триггера свой владелец; это не новый розыгрыш после10с.
				_begin_resolving({"kind": "item", "card": int(effect.card), "owner": seat})
				return
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
			"expand_shop":
				for i in amount:
					var card := _draw("treasure")
					if card >= 0:
						shop.append(card)
			"tap_character": character_ready[seat] = false
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
		_resolving_base = mini(int(effect.previous.get("base", stack.size())), stack.size())
		_after_stack = str(effect.previous.resume)
		peek = effect.previous.peek
		# Ответы, лежавшие над внешним эффектом до вложенного, ещё ждут закрытия.
		phase = "priority" if stack.size() > _resolving_base else "effect"
		_advance_auto_reward()
		return
	if effect.kind == "passive":
		_resolve_passive(effect)
		return
	if effect.kind == "monster_death":
		var slot: int = int(effect.slot)
		if slot >= 0 and slot < monsters.size() and int(monsters[slot].id) == int(effect.card) and int(monsters[slot].hp) <= 0:
			if _replace_monster_death(slot):
				_continue_stack()
				return
			# Каменюка и Голова смерти гибнут от смерти другого открытого монстра.
			for other in monsters.size():
				if other != slot and _dies_with_other_monster(int(monsters[other].id)):
					monsters[other].hp = 0
			var reward := {"kind": "reward", "card": int(effect.card), "owner": current, "slot": slot}
			var printed := _printed_monster_reward(int(effect.card))
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
			if int(effect.card) == 429:
				_prepare_peep_spawn()
			if int(effect.card) == 358:
				resolving["requires_reward_roll"] = true
			if int(effect.card) == 268:
				required_player_attacks += 1
			bonus_progress.monsters = int(bonus_progress.monsters) + 1
			if int(monsters[slot].get("slayer", current)) == current:
				_turn_kills += 1
			_emit_passives("monster_death", {"seat": int(monsters[slot].get("slayer", current)), "card": int(effect.card)})
			_advance_auto_reward()
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
		var restored: Dictionary = previous.effect
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
		var damage: int = int(attack[current]) if hit else _monster_attack(m)
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
	if effect.kind == "loot" and int(effect.card) == 528:
		if bool(effect.get("boost_pending", false)):
			reward_boost = mini(1073741824, reward_boost * 2)
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
		discards.loot.append(int(effect.card)); _continue_stack()
	elif effect.kind == "loot" and kind == "lsoul":
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
		if pending.get("kind", "") == "loot" and not bool(pending.get("under_deck", false)) and not pending.has("given_to"):
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
		monster.dc = int(monster.dc) - 1
		monster.at = int(monster.at) - 1
		monster["temporary_dc"] = int(monster.get("temporary_dc", 0)) - 1
		monster["temporary_at"] = int(monster.get("temporary_at", 0)) - 1
		_note("Всадник: первая смерть хода предотвращена,2HP и−1защиты/атаки до конца хода")
		return true
	if int(monster.id) != 264 or int(monster.get("lethal_attack_roll", 0)) == 6:
		return false
	monster.hp = _monster_hp(264)
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
