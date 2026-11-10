extends "res://games/four_souls/logic/fs_treasure13_automation.gd"
## Сокровища206–245: замены бросков, обмен предметами и копии способностей.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	var category: String = str(step.get("targets", ""))
	var data: Dictionary = resolving.get("automation_data", {})
	if category in ["copy_items14", "tap_items14", "other_destroy14", "swap_own14", "roller_items14", "steal_any14"]:
		out = out.filter(func(choice): return str(choice.arg.op) == "skip_choice")
		if category == "roller_items14" and not resolving.has("swap_item14"):
			return out
		for seat in active_seats():
			if category == "swap_own14" and seat != owner:
				continue
			if category == "roller_items14" and seat != int(data.get("seat", -1)):
				continue
			for index in items[seat].size():
				var entry: Dictionary = items[seat][index]
				if bool(entry.eternal):
					continue
				if category in ["copy_items14", "tap_items14", "other_destroy14"] and is_same(entry, resolving.get("source", {})):
					continue
				if category == "tap_items14" and not (_item_kind20(entry) == "tap" if int(entry.id) == 1 else _tap_item14(int(entry.id))):
					continue
				if category == "roller_items14" and is_same(entry, resolving.get("swap_item14", {})):
					continue
				out.append({"label": name_of(seat) + " · " + FSData.title(int(entry.id)), "arg": {"op": str(step.op), "target": seat, "item": index, "card": int(entry.get("physical_id13", entry.id)), "shop": false}})
		if category in ["copy_items14", "tap_items14", "other_destroy14"]:
			for index in shop.size():
				var id: int = int(shop[index])
				if id >= 0 and not bool(_eternal_shop15.get(id, false)) and (category != "tap_items14" or _tap_item14(id)):
					out.append({"label": "Магазин · " + FSData.title(id), "arg": {"op": str(step.op), "item": index, "card": id, "shop": true}})
	match category:
		"activated_stack14":
			for index in stack.size():
				var entry: Dictionary = stack[index]
				if entry.kind == "item" and not bool(entry.get("conditional", false)) and not entry.has("automation_context"):
					out.append({"label": FSData.title(int(entry.card)), "arg": {"op": "cancel_ability14", "index": index}})
		"pending_reroll14":
			for index in stack.size():
				if int(stack[index].get("roll_token", -1)) == int(data.token):
					out.append({"label": "Перебросить 1", "arg": {"op": "reroll", "roll_index": index}})
		"plus_roll14", "nonattack_plus14":
			for index in stack.size():
				if stack[index].kind not in ["roll", "effect_roll"]:
					continue
				if category == "nonattack_plus14" and (stack[index].kind == "roll" or _rerolls_attack(stack[index])):
					continue
				for amount in ([1] if category == "plus_roll14" else [0, 1, 2]):
					out.append({"label": name_of(int(stack[index].owner)) + " · +%d" % amount, "arg": {"op": "roll", "roll_index": index, "amount": amount}})
		"bottom_options14":
			if not peek.is_empty():
				for mode in ["keep", "bottom"]:
					out.append({"label": "Оставить сверху" if mode == "keep" else "Положить под низ", "arg": {"op": "bottom_top14", "mode": mode}})
		"nonattacked14", "forced_monsters14":
			for slot in monsters.size():
				if category == "nonattacked14" and slot == battle:
					continue
				if int(monsters[slot].hp) > 0 and (category == "nonattacked14" or not _untargetable(int(monsters[slot].id))):
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": str(step.op), "item": slot}})
		"flush_modes14":
			for mode in ["monster", "treasure"]:
				out.append({"label": "Неатакуемые монстры" if mode == "monster" else "Предметы магазина", "arg": {"op": "flush_mode14", "mode": mode}})
		"shop_items":
			if int(resolving.card) == 222:
				if not resolving.has("original_shop14"):
					resolving["original_shop14"] = shop.duplicate()
				for choice: Dictionary in out:
					if choice.arg.has("item"):
						choice.arg.op = "discard_shop14"
				out = out.filter(func(choice): return str(choice.arg.op) == "skip_choice" or int(shop[int(choice.arg.item)]) in resolving.original_shop14)
	return out

func _tap_item14(id: int) -> bool:
	return FSData.item_response_kind(id) == "tap"

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"self_underdeck":
			if bool(resolving.get("loot_copy14", false)):
				resolving.automation_step = resolving.automation_steps.size()
			else:
				super._apply_card_step(step)
		"spider_result14":
			_insert_card_steps([{"op": "monster_damage", "targets": "monsters"}] if value <= 2 else [{"op": "damage", "targets": "players"}] if value <= 4 else [{"op": "damage", "target": owner}])
		"cancel_ability14":
			stack.remove_at(int(step.index))
			_resolving_base = mini(_resolving_base, stack.size())
		"collar_result14":
			if value <= 3:
				hp[owner] = 1
				_death_queue.erase(owner)
				if owner == current:
					resolving["end_turn_after"] = true
		"bottom_top14":
			if str(step.mode) == "bottom" and not peek.get("cards", []).is_empty():
				var id: int = int(peek.cards[0])
				decks[str(peek.deck)].erase(id)
				decks[str(peek.deck)].push_front(id)
			peek = {}
		"swap_own14":
			resolving["swap_item14"] = items[owner][int(step.item)]
		"swap_other14":
			if resolving.has("swap_item14"):
				_swap_items14(owner, resolving.swap_item14, int(step.target), items[int(step.target)][int(step.item)])
		"swap_source14":
			_swap_items14(owner, resolving.source, int(step.target), items[int(step.target)][int(step.item)])
		"replace_monster14":
			_effect({"op": "discard_monster", "item": int(step.item)})
		"slot_result14":
			if value <= 2:
				_draw_loot(owner, 1)
			elif value <= 4:
				_gain_coins(owner, 4)
		"permanent_copy14":
			_copy_item14(int(step.card) if bool(step.shop) else int(items[int(step.target)][int(step.item)].id), true)
		"copy_ability14":
			var id: int = int(step.card) if bool(step.shop) else int(items[int(step.target)][int(step.item)].id)
			_begin_resolving({"kind": "item", "card": id, "owner": owner, "source": resolving.source, "ability_copy14": true})
		"discard_shop14":
			_effect({"op": "discard_shop", "item": int(step.item)})
			_insert_card_steps([{"op": "discard_shop14", "targets": "shop_items", "optional": true}])
		"fart_result14":
			_insert_card_steps([{"op": "damage_others14"}] if value <= 3 else [{"op": "monster_damage", "targets": "monsters"}])
		"damage_others14":
			var steps: Array = []
			for seat in players.size():
				if seat != owner:
					steps.append({"op": "damage", "target": seat})
			_insert_card_steps(steps)
		"blank_arm14":
			_blank_copies14[owner] = int(_blank_copies14.get(owner, 0)) + 1
		"sacred_six14":
			_change_pending12(int(resolving.automation_data.token), 6, true)
		"flush_mode14":
			if str(step.mode) == "treasure":
				for index in shop.size():
					if int(shop[index]) >= 0:
						decks.treasure.push_front(int(shop[index]))
						shop[index] = _draw_shop_slot24()
			else:
				for slot in range(monsters.size() - 1, -1, -1):
					if slot != battle:
						_flush_monster14(slot)
		"force_monster14":
			_forced_monsters14.append(int(monsters[int(step.item)].id))
		"glass_destroy14":
			if bool(step.shop):
				_effect({"op": "discard_shop", "item": int(step.item)})
			else:
				_destroy_item(int(step.target), int(step.item))
		"glass_result14":
			if value == 6:
				if _source_item_in_play(resolving.source):
					resolving.source.tapped = false
			else:
				var source: Dictionary = resolving.source
				for index in items[owner].size():
					if is_same(items[owner][index], source) and not bool(source.eternal):
						_destroy_item(owner, index)
						if not _source_item_in_play(source):
							_draw_loot(owner, 2)
						break
		"roller_give14":
			resolving["choice_owner"] = int(resolving.automation_data.seat)
		"reveal_top14":
			if not peek.is_empty():
				peek["public"] = true
		_:
			super._apply_card_step(step)

func _copy_item14(id: int, permanent: bool) -> void:
	var source: Dictionary = resolving.source
	if not _source_item_in_play(source):
		return
	var before := _copy_allowances13(current)
	source["physical_id13"] = int(source.get("physical_id13", source.id))
	source.id = id
	if permanent:
		source["copy_permanent14"] = true
	_refresh_passive_stats()
	var change := _copy_allowances13(current) - before
	free_loot += change.x
	buy_left += change.y
	attack_left += change.z
	bought = buy_left <= 0
	attacked = attack_left <= 0

func _swap_items14(first: int, left: Dictionary, second: int, right: Dictionary) -> void:
	if is_same(left, right) or not _source_item_in_play(left) or not _source_item_in_play(right):
		return
	var before := _copy_allowances13(current)
	var li: int = items[first].find(left)
	var ri: int = items[second].find(right)
	if li < 0 or ri < 0:
		return
	items[first][li] = right
	items[second][ri] = left
	_refresh_passive_stats()
	var change := _copy_allowances13(current) - before
	free_loot += change.x
	buy_left += change.y
	attack_left += change.z
	bought = buy_left <= 0
	attacked = attack_left <= 0

func _flush_monster14(slot: int) -> void:
	var entry: Dictionary = monsters[slot]
	_put_monster20(entry, "bottom")
	_eggs_monsters.erase(int(entry.id))
	if not entry.get("under", {}).is_empty():
		monsters[slot] = entry.under
	else:
		monsters.remove_at(slot)
		if battle > slot:
			battle -= 1
		_fill_monster()

func _forced_slots14() -> Array:
	var out: Array = []
	if not _card_automation_enabled() or attacked or attack_left <= 0 or int(coins[current]) < _attack_tax(current):
		return out
	for slot in monsters.size():
		if int(monsters[slot].id) in _forced_monsters14 and int(monsters[slot].hp) > 0 and not _untargetable(int(monsters[slot].id)):
			out.append(slot)
	return out

func _encounter_must_attack() -> bool:
	return super._encounter_must_attack() or not _forced_slots14().is_empty()

func _intercept_missing_page(effect: Dictionary, value: int) -> bool:
	if _card_automation_enabled() and value == 1:
		for id in [232, 213]:
			for owner in players.size():
				if id == 232 and owner != int(effect.owner):
					continue
				for entry: Dictionary in items[owner]:
					var marker := "replacement14_%d_%d_%d" % [id, owner, int(entry.get("physical_id13", entry.id))]
					if int(entry.id) != id or bool(effect.get(marker, false)):
						continue
					effect[marker] = true
					var token := _roll_token(effect)
					stack.append(effect)
					_begin_resolving({"kind": "item", "card": id, "owner": owner, "source": entry, "conditional": true, "automation_context": "would_roll", "automation_data": {"token": token}})
					return true
	return super._intercept_missing_page(effect, value)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	if event == "attack_start" and data.has("card"):
		_forced_monsters14.erase(int(data.card))
	for owner in players.size():
		for entry: Dictionary in _ability_items20(owner).duplicate():
			var id: int = int(entry.id)
			var triggered := false
			match id:
				206:
					triggered = event == "attack_declared" and int(data.get("seat", -1)) == owner
				209:
					triggered = event == "damage" and int(data.get("seat", -1)) == owner and int(entry.get("first_damage14", -1)) != turn_serial
					if triggered:
						entry["first_damage14"] = turn_serial
				212:
					triggered = event == "roll" and int(data.get("value", 0)) == 2
				214:
					triggered = event == "death" and int(data.get("seat", -1)) == owner
				215:
					triggered = event == "roll" and int(data.get("value", 0)) == 5
				222:
					triggered = event == "turn_start" and current == owner
				225, 226:
					triggered = event == "damage" and int(data.get("seat", -1)) == owner
				230:
					triggered = event == "attack_roll" and int(data.get("seat", -1)) == owner and int(data.get("value", 0)) == 6
				234:
					triggered = event == "combat_monster_damage" and int(data.get("seat", -1)) == owner
				236:
					triggered = event == "turn_end" and current == owner
				242:
					triggered = event == "roll" and int(data.get("value", 0)) == 4
				245:
					triggered = event == "roll" and int(data.get("value", 0)) == 6
			if triggered:
				_queue_passive(owner, id, entry, [{"op": "trinket_automation", "amount": 1, "context": event, "data": data.duplicate(true)}])

func _copy_loot14(seat: int, id: int) -> void:
	if not _card_automation_enabled() or FSData.card(id).lua.get("type", "") in ["trinkets", "ambush"]:
		return
	var count: int = int(_blank_copies14.get(seat, 0))
	_blank_copies14.erase(seat)
	for index in count:
		stack.append({"kind": "loot", "card": id, "owner": seat, "loot_copy14": true})
