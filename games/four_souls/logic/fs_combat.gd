extends "res://games/four_souls/logic/fs_stack.gd"
## Four Souls, модуль правил: Бой, монстры, урон, PvP, награды и покупка.
## Часть цепочки fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules (FSRules — фасад).
## Отдельно не используется: состояние и вызовы общие через self.

func _damage_player(seat: int, amount: int, context: Dictionary = {}) -> void:
	_refresh_passive_stats()
	var combat: bool = context.get("combat", false)
	var face: int = context.get("value", 0)
	var immune := false
	for item: Dictionary in items[seat]:
		var id: int = item.id
		if (id == 514 and not combat) or (id == 72 and seat != current):
			immune = true
		if combat and ((id == 30 and face == 1) or (id == 31 and face == 2) or (id in [32, 92] and face == 3) or (id == 71 and face in [1, 6]) or (id == 112 and face == 4) or (id in [115, 893] and face == 1)):
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
func _purchase_cost(seat: int, slot: int) -> int:
	if slot == -1:
		return 10
	# Скидки: 229 −5, 473/76 −1, Членская карта 91 −4, Сделка Хранителя 889 −3, комната 771 −5.
	if room == 782 and int(souls[seat]) == int(souls.min()):
		return 0
	return maxi(0, 10 - 5 * _item_count(seat, 229) - _item_count(seat, 473) - _item_count(seat, 76) - 4 * _item_count(seat, 91) - 3 * _item_count(seat, 889) - (5 if room == 771 else 0))
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
	var base: int = int(monster.dc) + _monster_aura("stoney") + (1 if curses[current].has(705) else 0) + (1 if room == 765 else 0)
	base += PassiveRules.monster_health_bonus(monster, "dc")
	# Опознавательный знак: −X, где X — отставание владельца по душам от лидера.
	if _item_count(current, 75) > 0:
		base -= _item_count(current, 75) * maxi(0, int(souls.max()) - int(souls[current]))
	return PassiveRules.monster_evasion(base, items[current])

## Одна формула для урона промаха и показанной атаки, без залипания бонуса после лечения.
func _monster_attack(monster: Dictionary) -> int:
	return int(monster.at) + PassiveRules.monster_health_bonus(monster, "at") + _monster_aura("deathshead") + (1 if curses[current].has(737) else 0) + (1 if room == 818 else 0)
## Подтверждённая смерть или явная отмена заканчивает бой, сохраняя прочие способности стека.
## Не вызывать при одном лишь объявлении смерти: до её разрешения ещё возможно спасение.
func _end_battle() -> void:
	battle = -1
	battle_player = -1
	stack = stack.filter(func(effect): return effect.kind not in ["roll", "combat", "player_combat", "player_attack"])
	_after_stack = "turn"
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
			# Проклятый глаз: шестёрка — +3 боевого урона (до удвоений).
			effect.damage = int(effect.damage) + 3 * _item_count(current, 144)
			for i in _item_count(current, 74):
				effect.damage = int(effect.damage) * 2
		if int(monster.id) == 281:
			effect.damage = mini(1, int(effect.damage))
		var before_hp: int = monster.hp
		monster.hp = int(monster.hp) - int(effect.damage)
		if before_hp > 0 and int(monster.hp) <= 0:
			monster["lethal_attack_roll"] = value
			monster["slayer"] = int(effect.owner)
		# Соевое молоко: боевой урон монстру — ещё 1 урон каждому другому монстру.
		if int(effect.damage) > 0 and _item_count(current, 118) > 0:
			for other: Dictionary in monsters:
				if not is_same(other, monster):
					if int(other.hp) > 0 and int(other.hp) - _item_count(current, 118) <= 0:
						other["lethal_attack_roll"] = 0
					other["slayer"] = int(effect.owner)
					other.hp = int(other.hp) - _item_count(current, 118)
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
## Награда ищет свою карту: за время вложенного эффекта ряд мог сдвинуться или источник накрыли.
## Автоматические шаги фиксируются до операции; пассивы прерывают их и возвращают тот же resolving.
func _advance_auto_reward() -> void:
	if phase != "effect" or resolving.get("kind", "") != "reward" or not resolving.has("auto_reward"):
		return
	if not bool(resolving.get("death_text_done", false)) or bool(resolving.get("reward_ready", false)):
		return
	if resolving.has("spawn_card"):
		return
	if resolving.auto_reward.has("roll") or bool(resolving.auto_reward.get("return_roll", false)):
		resolving["requires_reward_roll"] = true
	if resolving.auto_reward.has("roll") and not resolving.has("reward_roll"):
		return
	var operations: Array = ["coins", "loot", "treasure", "item", "souls"]
	while phase == "effect" and int(resolving.get("reward_step", 0)) < operations.size():
		var step: int = int(resolving.reward_step)
		var op: String = operations[step]
		if op == "souls" and int(resolving.auto_reward.get("damage_choice", 0)) > 0 and not bool(resolving.get("reward_damage_done", false)):
			if not _reward_damage_targets().is_empty():
				resolving["reward_damage"] = true
				return
			resolving["reward_damage_done"] = true
		if op == "souls" and bool(resolving.auto_reward.get("soul_other", false)) and not resolving.has("soul_recipient"):
			var candidates: Array = []
			for candidate in players.size():
				if candidate != int(resolving.owner):
					candidates.append(candidate)
			resolving["reward_soul_targets"] = candidates
			return
		if op == "souls" and bool(resolving.auto_reward.get("return_roll", false)) and not resolving.has("reward_roll"):
			return
		if op == "souls" and bool(resolving.auto_reward.get("manual_post", false)) and not bool(resolving.get("post_text_done", false)):
			resolving["post_reward_wait"] = true
			return
		var amount: int = int(resolving.auto_reward.get(op, 0))
		if op == "item":
			amount = 1 if bool(resolving.auto_reward.get("self_item", false)) else 0
		if str(resolving.auto_reward.get("roll", "")) == op:
			amount = int(resolving.get("reward_roll", 0))
		if op in ["coins", "loot", "treasure"]:
			amount *= int(resolving.get("reward_multiplier", 1)) * reward_boost
		if op == "treasure":
			# Остаток уже умножен: возвращение из пассива не удваивает его повторно.
			amount = int(resolving.get("treasure_remaining", amount))
		var seat: int = int(resolving.owner) if op == "souls" else int(resolving.get("resource_recipient", resolving.owner))
		if op == "souls":
			seat = int(resolving.get("soul_recipient", seat))
		resolving.reward_step = step + 1
		if amount <= 0:
			continue
		_note("Награда автоматически: %s · %s · %d" % [name_of(seat), {"coins": "монеты", "loot": "добыча", "treasure": "сокровища", "item": "предмет", "souls": "души"}[op], amount])
		match op:
			"item":
				resolving["kept_as_item"] = true
				_gain_item(seat, int(resolving.card))
			"coins": _gain_coins(seat, amount)
			"loot": _draw_loot(seat, amount)
			"treasure":
				# Один предмет — один шаг: его входные пассивы разрешаются до следующего предмета.
				if amount > 1:
					resolving["treasure_remaining"] = amount - 1
					resolving.reward_step = step
				var id := _draw("treasure")
				if id >= 0:
					_gain_item(seat, id)
				else:
					resolving.reward_step = step + 1
			"souls":
				if room != 779 and not curses[seat].has(744) and not bool(resolving.get("return_to_deck", false)):
					resolving["kept_as_soul"] = true
					_gain_soul_card(seat, {"id": int(resolving.card), "value": amount})
		_check_bonuses()
		_check_win()
	if phase != "effect":
		return
	if bool(resolving.get("requires_reward_roll", false)) and not resolving.has("reward_roll"):
		return
	if bool(resolving.auto_reward.get("victory_most_souls", false)) and not resolving.has("reward_winner"):
		var candidates := _reward_win_targets()
		if candidates.size() == 1 or int(souls[int(resolving.owner)]) >= 4:
			resolving["reward_winner"] = int(resolving.owner) if int(souls[int(resolving.owner)]) >= 4 else int(candidates[0])
		else:
			resolving["reward_winners"] = candidates
			return
	resolving["reward_ready"] = true
	action(int(resolving.owner), "effect_done")

func _finish_monster_reward(effect: Dictionary) -> void:
	var slot := -1
	var parent: Dictionary = {}
	var dying: Dictionary = {}
	for index in monsters.size():
		var entry: Dictionary = monsters[index]
		var previous: Dictionary = {}
		while not entry.is_empty():
			if int(entry.id) == int(effect.card):
				slot = index
				parent = previous
				dying = entry
				break
			previous = entry
			entry = entry.get("under", {})
		if slot >= 0:
			break
	if slot < 0:
		# Повторный cleanup не должен заново класть уже снятую карту в сброс/колоду.
		_note("Награда: карта уже снята со стола — " + FSData.title(int(effect.card)))
		return
	if not bool(effect.get("kept_as_soul", false)) and not bool(effect.get("kept_as_item", false)):
		if bool(effect.get("return_to_deck", false)):
			decks.monster.append(int(effect.card))
			_note("Тряпочник возвращён на верх колоды")
		else:
			discards.monster.append(int(effect.card))
	var covered: Dictionary = dying.get("under", {})
	if not parent.is_empty():
		if not covered.is_empty():
			parent["under"] = covered
		else:
			parent.erase("under")
		return
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
		var fresh := {"id":id,"hp":_monster_hp(id),"dc":FSData.stat(id,"dc",4),"at":FSData.stat(id,"at",1)}
		if monsters.is_empty():
			# Пустой ряд монстров: открытая карта занимает новую ячейку, накрывать нечего.
			monsters.append(fresh)
			slot = 0
		else:
			var over: int = clampi(int(effect.get("over",0)),0,monsters.size()-1)
			fresh["under"] = monsters[over].duplicate(true)
			monsters[over] = fresh
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
	var monster := {"id":id, "hp":_monster_hp(id), "dc":FSData.stat(id,"dc",4), "at":FSData.stat(id,"at",1)}
	if slot >= 0 and slot < monsters.size(): monsters[slot] = monster
	else: monsters.append(monster)
func _expire_monster_modifiers(monster: Dictionary) -> void:
	monster.erase("last_attack_roll")
	monster.erase("lethal_attack_roll")
	monster.dc = int(monster.dc) - int(monster.get("temporary_dc", 0))
	monster.erase("temporary_dc")
	monster.at = int(monster.at) - int(monster.get("temporary_at", 0))
	monster.erase("temporary_at")
	if monster.has("under"):
		_expire_monster_modifiers(monster.under)
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
