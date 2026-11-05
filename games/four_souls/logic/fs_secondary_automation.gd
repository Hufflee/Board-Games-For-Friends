extends "res://games/four_souls/logic/fs_active_automation.gd"
## Дополнительные двадцать карт пакета10. Все параметры берутся из хостового списка вариантов.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	match str(step.get("targets", "")):
		"egg_entities", "empty_egg_entities":
			for zone in ["player", "monster"]:
				for index in (players.size() if zone == "player" else monsters.size()):
					var target: int = index if zone == "player" else int(monsters[index].id)
					if str(step.targets) == "empty_egg_entities" and _egg_count(zone, target) > 0:
						continue
					out.append({"label": name_of(index) if zone == "player" else FSData.title(target), "arg": {"op": str(step.op), "zone": zone, "target": target}})
		"own_recharges":
			for index in items[owner].size():
				var id: int = int(items[owner][index].id)
				if id != 44 and id not in resolving.get("nine_picked", []):
					out.append({"label": FSData.title(id), "arg": {"op": "nine_recharge", "item": index, "remaining": int(step.remaining)}})
		"bible_modes":
			if curses.any(func(list: Array): return not list.is_empty()):
				out.append({"label": "Уничтожить проклятие", "arg": {"op": "dagaz_curse"}})
			if battle >= 0 or battle_player >= 0:
				out.append({"label": "Отменить свою атаку", "arg": {"op": "cancel_attack"}})
			for slot in monsters.size():
				if str(FSData.card(int(monsters[slot].id)).get("key", "")) in ["mom", "momsheart", "itlives"]:
					out.append({"label": "Убить: " + FSData.title(int(monsters[slot].id)), "arg": {"op": "bible_kill", "item": slot}})
		"peek_or_skip":
			out.append({"label": "Посмотреть2верхнихсокровища", "arg": {"op": "peek_deck", "deck": "treasure", "amount": 2}})
		"ouija_events":
			if monsters.size() > (1 if battle >= 0 else 0):
				for id in peek.get("cards", []):
					if FSData.card(int(id)).kind == "event":
						out.append({"label": FSData.title(int(id)), "arg": {"op": "ouija_choose", "card": int(id)}})
		"ouija_slots", "dad_key_slots":
			for slot in monsters.size():
				if slot != battle:
					var arg := {"op": "key_cover" if str(step.targets) == "dad_key_slots" else "ouija_place", "item": slot}
					if step.has("card"):
						arg["card"] = int(step.card)
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": arg})
		"cost_hand":
			for index in hands[owner].size():
				out.append({"label": "Оплатить картой: " + FSData.title(int(hands[owner][index])), "arg": {"op": "pay_loot_cost", "item": index}})
		"missing_roll":
			for index in stack.size():
				if stack[index].kind in ["roll", "effect_roll"] and _roll_token(stack[index]) == int(resolving.automation_data.token):
					out.append({"label": "Попросить перебросить5", "arg": {"op": "reroll", "roll_index": index}})
		"loot_play_counts":
			for amount in range(0, 3):
				out.append({"label": "Дополнительных розыгрышей: %d" % amount, "arg": {"op": "extra_loot", "target": owner, "amount": amount}})
		"attack_roll_bonuses":
			for index in stack.size():
				if stack[index].kind == "roll":
					for amount in range(0, 3):
						out.append({"label": "%s · прибавить%d" % [name_of(int(stack[index].owner)), amount], "arg": {"op": "roll", "roll_index": index, "amount": amount}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"white_egg":
			_place_egg("player", int(step.target), "white")
		"pay_loot_cost":
			discards.loot.append(int(hands[owner].pop_at(int(step.item))))
		"red_egg", "black_egg":
			_place_egg(str(step.zone), int(step.target), "red" if str(step.op) == "red_egg" else "black")
		"nine_recharge":
			if not resolving.has("nine_picked"):
				resolving["nine_picked"] = []
			resolving.nine_picked.append(int(items[owner][int(step.item)].id))
			_effect({"op": "recharge", "target": owner, "item": int(step.item)})
			if int(step.remaining) > 1:
				_insert_card_steps([{"op": "nine_recharge", "targets": "own_recharges", "optional": true, "remaining": int(step.remaining) - 1}])
		"bible_kill", "plan_c_monster":
			monsters[int(step.item)].hp = 0
			monsters[int(step.item)]["slayer"] = owner
			if str(step.op) == "plan_c_monster":
				_plan_c_owner = owner
		"ouija_peek":
			_apply_card_step({"op": "peek_deck", "deck": "monster", "amount": 4})
			if not peek.is_empty():
				peek["public"] = true
		"ouija_choose":
			_insert_card_steps([{"op": "ouija_place", "targets": "ouija_slots", "card": int(step.card)}])
		"ouija_place":
			decks.monster.erase(int(step.card))
			peek.cards.erase(int(step.card))
			_push({"kind": "event", "card": int(step.card), "owner": owner, "slot": int(step.item)}, "effect")
		"ouija_bottom":
			var rest: Array = peek.get("cards", []).duplicate()
			for id in rest:
				decks.monster.erase(int(id))
			_shuffle(rest)
			for id in rest:
				decks.monster.push_front(int(id))
			peek = {}
		"lemon_enable":
			_lemon_effects.append({"turn": turn_serial, "owner": owner})
		"knife_splash":
			var target: int = int(resolving.automation_data.card)
			var steps: Array = []
			for slot in monsters.size():
				if int(monsters[slot].id) != target:
					steps.append({"op": "monster_damage", "item": slot, "amount": 1})
			_insert_card_steps(steps)
		"bean_recharge":
			if value == 6:
				for index in items[owner].size():
					if int(items[owner][index].id) == 109:
						_effect({"op": "recharge", "target": owner, "item": index})
		"plan_c_kill_all":
			for seat in players.size():
				hp[seat] = 0
				_last_player_killer[seat] = owner
		"crooked_target":
			resolving["crooked_target"] = int(step.target)
		"crooked_result":
			var target: int = int(resolving.crooked_target)
			_gain_coins(target, int(coins[target]) if value <= 3 else -int(coins[target]))
		_:
			super._apply_card_step(step)

func _intercept_missing_page(effect: Dictionary, value: int) -> bool:
	if value != 5 or not _card_automation_enabled():
		return false
	for owner in players.size():
		if _item_count(owner, 116) == 0 or owner in effect.get("page_checked", []):
			continue
		if not effect.has("page_checked"):
			effect["page_checked"] = []
		effect.page_checked.append(owner)
		var token := _roll_token(effect)
		stack.append(effect)
		_begin_resolving({"kind": "item", "card": 116, "owner": owner, "conditional": true, "automation_context": "roll_five", "automation_data": {"token": token}})
		return true
	return false
