extends "res://games/four_souls/logic/fs_secondary_automation.gd"
## Исполнение событий и комнат пакета11; выборы формирует только хост.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty(): return out
	var owner: int = int(resolving.owner)
	match str(step.get("targets", "")):
		"devil_deals":
			for mode in 3:
				out.append({"label": ["Сбросить событие", "Взять 2 добычи и получить 1 урона", "Получить 2 урона и найти предмет Гаппи"][mode], "arg": {"op": "devil_deal", "mode": mode}})
		"guppy_deck":
			for id in decks.treasure:
				if str(FSData.card(int(id)).get("key", "")).begins_with("guppy"):
					out.append({"label": FSData.title(int(id)), "arg": {"op": "guppy_take", "card": int(id)}})
		"planetarium_yes":
			out.append({"label": "Получить 1 сокровище", "arg": {"op": "treasure"}})
		"limited_recharges":
			for index in items[owner].size():
				if int(items[owner][index].id) in resolving.automation_data.get("allowed", []) and bool(items[owner][index].tapped):
					out.append({"label": "Перезарядить: " + FSData.title(int(items[owner][index].id)), "arg": {"op": "recharge", "target": owner, "item": index}})
		"war_destroy":
			for index in items[owner].size():
				if not bool(items[owner][index].eternal):
					out.append({"label": "Уничтожить: " + FSData.title(int(items[owner][index].id)), "arg": {"op": "destroy", "target": owner, "item": index}})
		"other_living":
			for seat in players.size():
				if seat != owner and not dead[seat] and hp[seat] > 0:
					out.append({"label": name_of(seat), "arg": {"op": str(step.op), "target": seat}})
		"boss_rush_slots":
			var bosses: Array = resolving.get("bosses", [])
			if not bosses.is_empty():
				for slot in monsters.size():
					if slot != battle:
						out.append({"label": "%s поверх %s" % [FSData.title(int(bosses[0])), FSData.title(int(monsters[slot].id))], "arg": {"op": "boss_rush_place", "item": slot}})
		"replay_items":
			for index in items[owner].size():
				var item: Dictionary = items[owner][index]
				if not bool(item.eternal) and int(item.id) not in resolving.get("replayed", []):
					out.append({"label": "Заменить: " + FSData.title(int(item.id)), "arg": {"op": "replay_chosen", "item": index}})
		"betray_items", "betray_souls":
			var target: int = int(resolving.encounter_target)
			var entries: Array = items[target] if str(step.targets) == "betray_items" else soul_cards[target]
			for index in entries.size():
				if str(step.targets) == "betray_items" and bool(entries[index].eternal): continue
				out.append({"label": FSData.title(int(entries[index].id)), "arg": {"op": "steal" if str(step.targets) == "betray_items" else "steal_soul", "target": target, "item": index}})
		"barrel_entities":
			for seat in players.size():
				out.append({"label": name_of(seat), "arg": {"op": "barrel_target", "zone": "player", "target": seat}})
			for slot in monsters.size():
				out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "barrel_target", "zone": "monster", "target": int(monsters[slot].id)}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"recharge_finish_start": _complete_turn_start()
		"encounter_shop":
			for count in int(step.amount):
				var id := _draw("treasure")
				if id >= 0: shop.append(id)
		"ambush":
			required_deck_attacks = maxi(required_deck_attacks, 2)
			attack_left = maxi(attack_left, required_deck_attacks - deck_attacks)
			attacked = false
		"encounter_result": _insert_card_steps(_encounter_result(int(resolving.card), value))
		"devil_deal":
			if int(step.mode) == 1: _insert_card_steps([{"op": "loot", "amount": 2}, {"op": "damage"}])
			if int(step.mode) == 2: _insert_card_steps([{"op": "damage", "amount": 2}, {"op": "guppy_find"}])
		"guppy_find":
			_insert_card_steps([{"op": "guppy_take", "targets": "guppy_deck"}, {"op": "shuffle_treasure"}])
		"guppy_take":
			decks.treasure.erase(int(step.card))
			_gain_item(owner, int(step.card))
		"shuffle_treasure": _shuffle(decks.treasure)
		"encounter_damage_all":
			var steps: Array = []
			for offset in players.size(): steps.append({"op": "damage", "target": (owner + offset) % players.size(), "amount": int(step.amount)})
			_insert_card_steps(steps)
		"holy_chest_soul":
			if not _room_has20(779) and not curses[owner].has(744):
				resolving["attached"] = true
				_gain_soul_card(owner, {"id": int(resolving.card), "value": 1})
		"holy_chest_shield":
			damage_shields[owner] += 2
		"boss_rush_reveal":
			var bosses: Array = []
			# Без повторного перемешивания сброса: просматриваем конечную колоду.
			for index in range(decks.monster.size() - 1, -1, -1):
				var id: int = int(decks.monster[index])
				if str(FSData.card(id).get("lua", {}).get("type", "")) == "boss":
					bosses.append(id)
					if bosses.size() == 2: break
				else:
					discards.monster.append(int(decks.monster.pop_at(index)))
			resolving["bosses"] = bosses
			peek = {"owner": owner, "deck": "monster", "cards": bosses.duplicate(), "public": true}
		"boss_rush_place":
			var id: int = int(resolving.bosses.pop_front())
			peek.cards.erase(id)
			decks.monster.erase(id)
			_place_encounter_monster(id, int(step.item))
			_forced_bosses.append(id)
			if resolving.bosses.is_empty():
				peek = {}
				attack_left += 1
				attacked = false
		"pitfall": resolving["end_turn_after"] = true
		"replay_chosen":
			if not resolving.has("replayed"):
				resolving["replayed"] = items[owner].map(func(item: Dictionary): return int(item.id))
				resolving["replay_candidates"] = resolving.replayed.duplicate()
				resolving.replayed.clear()
			var id: int = int(items[owner][int(step.item)].id)
			resolving.replayed.append(id)
			_apply_card_step({"op": "reroll_item", "target": owner, "item": int(step.item), "shop": false})
			# Только исходные карты: вновь полученные предметы не выбираются повторно.
			for item: Dictionary in items[owner]:
				if int(item.id) not in resolving.replay_candidates: resolving.replayed.append(int(item.id))
			_insert_card_steps([{"op": "replay_chosen", "targets": "replay_items", "optional": true}])
		"overflow_start":
			var steps: Array = []
			for offset in players.size():
				steps.append({"op": "overflow_owner", "target": (owner + offset) % players.size()})
				steps.append({"op": "auto_roll"})
				steps.append({"op": "overflow_result"})
			steps.append({"op": "overflow_restore", "target": owner})
			_insert_card_steps(steps)
		"overflow_owner":
			resolving["overflow_original"] = int(resolving.get("overflow_original", owner))
			resolving.owner = int(step.target)
			resolving.erase("automation_roll")
		"overflow_result":
			if value <= 2: skipped_turns[owner] = int(skipped_turns[owner]) + 1
		"overflow_restore": resolving.owner = int(step.target)
		"betray_target": resolving["encounter_target"] = int(step.target)
		"betray_result":
			var target: int = int(resolving.encounter_target)
			if value <= 2: _transfer_coins(target, owner, mini(5, int(coins[target])))
			elif value <= 4:
				if not hands[target].is_empty(): hands[owner].append(int(hands[target].pop_at(_rng.randi_range(0, hands[target].size() - 1))))
			else: _insert_card_steps([{"op": "steal" if value == 5 else "steal_soul", "targets": "betray_items" if value == 5 else "betray_souls"}])
		"shadow_kill":
			var most := 0
			for inventory: Array in items: most = maxi(most, inventory.size())
			for seat in players.size():
				if items[seat].size() == most: hp[seat] = 0
		"event_bury":
			var index := maxi(0, decks.monster.size() - int(step.amount))
			decks.monster.insert(index, int(resolving.card))
			resolving["attached"] = true
		"lust_target":
			_lust_pending.append(int(step.target))
			_lust_victims[int(step.target)] = owner
		"double_treasure": _insert_card_steps([{"op": "treasure", "target": owner}, {"op": "treasure", "target": int(step.target)}])
		"barrel_target": resolving["barrel"] = step.duplicate(true)
		"barrel_result":
			var target: Dictionary = resolving.barrel
			var steps: Array = []
			if value <= 4: steps.append({"op": "damage", "target": owner, "amount": 2})
			if target.zone == "player": steps.append({"op": "damage", "target": int(target.target), "amount": 2 if value <= 4 else 4})
			else:
				for slot in monsters.size():
					if int(monsters[slot].id) == int(target.target): steps.append({"op": "monster_damage", "item": slot, "amount": 2 if value <= 4 else 4})
			_insert_card_steps(steps)
		"encounter_kill":
			hp[int(step.target)] = 0
			_last_player_killer[int(step.target)] = owner
		"splash_left":
			var source: int = int(resolving.automation_data.get("seat", owner))
			_damage_player((source + 1) % players.size(), 1, {"attacker": source, "splash": true})
		"goals_reward":
			var steps: Array = []
			for seat in players.size(): steps.append({"op": "treasure", "target": seat, "amount": 2})
			_insert_card_steps(steps)
		_: super._apply_card_step(step)

func _place_encounter_monster(id: int, slot: int) -> void:
	var fresh := {"id": id, "hp": _monster_hp(id), "dc": FSData.stat(id, "dc", 4), "at": FSData.stat(id, "at", 1)}
	_monster_entered15(fresh)
	if _card_automation_enabled() and id in [272, 279, 299, 312, 913, 914]:
		monsters.append(fresh)
		monster_slots = maxi(monster_slots, monsters.size())
		return
	if slot < monsters.size():
		_eggs_monsters.erase(int(monsters[slot].id))
		var covered := _cover_monster20(monsters[slot])
		if not covered.is_empty():
			fresh["under"] = covered.duplicate(true)
		monsters[slot] = fresh
	else: monsters.append(fresh)

func _encounter_result(id: int, face: int) -> Array:
	match id:
		699: return [{"op": "coins"}] if face <= 2 else [{"op": "loot", "amount": 2}] if face <= 4 else [{"op": "damage", "amount": 2}]
		701: return [{"op": "loot", "amount": 1 if face <= 2 else 2 if face <= 4 else 3}]
		702: return [{"op": "coins", "amount": 1 if face <= 2 else 3 if face <= 4 else 6}]
		704: return [{"op": "damage", "amount": 1 if face <= 3 else 2}] if face <= 5 else [{"op": "guppy_find"}]
		713: return [{"op": "treasure"}] if face <= 2 else [{"op": "coins", "amount": 5 if face <= 4 else 7}]
		714: return [{"op": "treasure"}] if face <= 2 else [{"op": "loot", "amount": 1 if face <= 4 else 2}]
		722: return [{"op": "holy_chest_shield"}, {"op": "extra_attack"}] if face <= 2 else [{"op": "coins", "amount": 7}] if face <= 5 else [{"op": "holy_chest_soul"}]
		726: return [{"op": "treasure", "amount": 2 if face == 1 else 1}] if face <= 3 else [{"op": "loot", "amount": 2}]
	return []

func _encounter_must_attack() -> bool:
	if int(coins[current]) < _attack_tax(current): return false
	if not _permitted_lust_targets().is_empty(): return true
	for id in _forced_bosses:
		if monsters.any(func(m): return int(m.id) == int(id) and int(m.hp) > 0): return true
	return false

func _permitted_lust_targets() -> Array:
	return _lust_pending.filter(func(seat): return int(seat) != current and not dead[int(seat)] and int(hp[int(seat)]) > 0)

func _encounter_passives(event: String, data: Dictionary) -> void:
	if not _card_automation_enabled(): return
	if _room_has20(803) and event == "turn_start": _queue_encounter(current, 803, event, data)
	if _room_has20(811) and event == "monster_death": _queue_encounter(int(data.get("seat", current)), 811, event, data)
	if _room_has20(813) and event == "death": _queue_encounter(int(data.seat), 813, event, data)
	if _room_has20(817) and event == "monster_damage" and int(data.get("amount", 0)) > 0 and int(data.get("seat", -1)) >= 0:
		_queue_encounter(int(data.get("seat", current)), 817, event, data)
	if event == "monster_death":
		for seat in players.size():
			if curses[seat].has(735): _queue_encounter(seat, 735, event, data)
	if _room_has20(810) and not _goals_rewarded:
		match event:
			"loot_play": _goals_counts.loot = int(_goals_counts.loot) + 1
			"monster_death": _goals_counts.monsters = int(_goals_counts.monsters) + 1
			"coin_give":
				if int(data.get("amount", 0)) >= 6: _goals_counts.gift = 1
			"purchase": _goals_counts.purchase = int(_goals_counts.purchase) + 1
			"roll":
				if int(data.get("value", 0)) == 6: _goals_counts.six = int(_goals_counts.six) + 1
		var complete := 0
		for key in _goals_counts:
			if int(_goals_counts[key]) >= int({"loot": 5, "monsters": 3, "gift": 1, "purchase": 3, "six": 3}[key]): complete += 1
		if complete >= 4:
			_goals_rewarded = true
			_queue_encounter(current, 810, "complete", {})

func _queue_encounter(owner: int, id: int, context: String, data: Dictionary) -> void:
	_queue_passive(owner, id, {}, [{"op": "trinket_automation", "amount": 1, "context": context, "data": data.duplicate(true)}])
