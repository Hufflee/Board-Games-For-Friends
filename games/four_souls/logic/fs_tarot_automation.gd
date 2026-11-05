extends "res://games/four_souls/logic/fs_automation.gd"
## Выборы и исполнение Таро. Общие ресурсы/урон/перебросы остаются штатными операциями.

func _grant_temporary_health(target: int, amount: int) -> void:
	max_hp[target] = int(max_hp[target]) + amount
	if not dead[target]:
		hp[target] = mini(int(max_hp[target]), int(hp[target]) + amount)
	_turn_health_bonus[target] = int(_turn_health_bonus[target]) + amount

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	match str(step.get("targets", "")):
		"set_roll_faces":
			for index in stack.size():
				if stack[index].kind in ["roll", "effect_roll"]:
					for face in range(1, 7):
						out.append({"label": "%s · результат %d" % [name_of(int(stack[index].owner)), face], "arg": {"op": "set_selected_roll", "index": index, "face": face}})
		"living_players":
			for seat in players.size():
				if not dead[seat] and int(hp[seat]) > 0:
					out.append({"label": name_of(seat), "arg": {"op": step.op, "target": seat}})
		"peek_cards":
			for id in peek.get("cards", []):
				out.append({"label": "Наверх: " + FSData.title(int(id)), "arg": {"op": "peek_keep_top", "card": int(id)}})
		"peek_groups":
			for group: Dictionary in peek.get("groups", []):
				out.append({"label": "Под низ: " + FSData.title(int(group.card)), "arg": {"op": "peek_bottom", "deck": str(group.deck), "card": int(group.card)}})
			out.append({"label": "Оставить остальные сверху и взять 2 добычи", "arg": {"op": "close_peek"}})
		"temperance_options":
			out.append({"label": "Получить 1 урона и 4¢", "arg": {"op": "temperance", "damage": 1, "coins": 4}})
			out.append({"label": "Получить 2 урона и 8¢", "arg": {"op": "temperance", "damage": 2, "coins": 8}})
		"own_destroy":
			for index in items[owner].size():
				if not bool(items[owner][index].eternal):
					out.append({"label": "Уничтожить: " + FSData.title(int(items[owner][index].id)), "arg": {"op": "devil_destroy", "item": index}})
		"steal_or_shop":
			for seat in players.size():
				if seat == owner:
					continue
				for index in items[seat].size():
					if not bool(items[seat][index].eternal):
						out.append({"label": name_of(seat) + " · " + FSData.title(int(items[seat][index].id)), "arg": {"op": "steal", "target": seat, "item": index}})
			for index in shop.size():
				if int(shop[index]) >= 0:
					out.append({"label": "Магазин · " + FSData.title(int(shop[index])), "arg": {"op": "take_shop", "target": owner, "item": index}})
	# Общий список damage_targets задаёт одинаковый набор целей; конкретная карта меняет действие.
	if str(step.get("targets", "")) == "damage_targets" and str(step.op) in ["priestess_target", "next_hit_shield"]:
		for choice: Dictionary in out:
			choice.arg["zone"] = "player" if choice.arg.op == "damage" else "monster"
			choice.arg["op"] = str(step.op)
			if choice.arg.zone == "monster":
				choice.arg["monster_id"] = int(monsters[int(choice.arg.item)].id)
		if str(step.op) == "next_hit_shield":
			var expanded: Array = []
			for choice: Dictionary in out:
				for amount in range(0, 3):
					var variant := choice.duplicate(true)
					variant.label = "%s · предотвратить %d" % [str(choice.label), amount]
					variant.arg["amount"] = amount
					expanded.append(variant)
			out = expanded
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"set_selected_roll":
			stack[int(step.index)].value = int(step.face)
			if stack[int(step.index)].kind == "roll":
				stack[int(step.index)]["final_value"] = int(step.face)
		"priestess_target":
			resolving["priestess_target"] = step.duplicate(true)
		"priestess_damage":
			var target: Dictionary = resolving.priestess_target
			if target.zone == "player":
				_insert_card_steps([{"op": "damage", "target": int(target.target), "amount": value}])
			else:
				for index in monsters.size():
					if int(monsters[index].id) == int(target.monster_id):
						_insert_card_steps([{"op": "monster_damage", "item": index, "amount": value}])
		"empress", "lovers", "chariot", "strength":
			var target: int = int(step.target)
			var kind: String = str(step.op)
			if kind in ["empress", "chariot", "strength"]:
				_insert_card_steps([{"op": "temporary_attack", "target": target, "amount": 1}])
			if kind == "empress":
				_turn_roll_bonus[target] = int(_turn_roll_bonus[target]) + 1
			if kind in ["lovers", "chariot"]:
				var amount := 2 if kind == "lovers" else 1
				_grant_temporary_health(target, amount)
			if kind == "strength" and target == current:
				attack_left += 1
				attacked = false
		"next_hit_shield":
			if int(step.amount) > 0:
				_next_hit_shields.append({"zone": str(step.zone), "target": int(step.target) if step.zone == "player" else int(step.monster_id), "amount": int(step.amount)})
		"peek_keep_top":
			var selected: int = int(step.card)
			var source: Array = decks[str(peek.deck)]
			var rest: Array = peek.cards.duplicate()
			rest.erase(selected)
			for id in peek.cards:
				source.erase(int(id))
			for index in range(rest.size() - 1, -1, -1):
				source.push_front(int(rest[index]))
			source.append(selected)
			peek = {}
		"peek_decks":
			peek = {"owner": owner, "groups": []}
			for deck in decks:
				if not decks[deck].is_empty():
					peek.groups.append({"deck": deck, "card": int(decks[deck].back())})
		"peek_bottom":
			var source: Array = decks[str(step.deck)]
			source.erase(int(step.card))
			source.push_front(int(step.card))
			peek.groups = peek.groups.filter(func(group): return str(group.deck) != str(step.deck))
			_insert_card_steps([{"op": "peek_bottom", "targets": "peek_groups"}])
		"justice":
			var target: int = int(step.target)
			_insert_card_steps([CardAutomation.op("loot", maxi(0, hands[target].size() - hands[owner].size())), CardAutomation.op("coins", maxi(0, int(coins[target]) - int(coins[owner])))])
		"wheel_result":
			_insert_card_steps([[CardAutomation.op("coins")], [CardAutomation.op("damage", 2)], [CardAutomation.op("loot", 3)], [CardAutomation.op("coins", -4)], [CardAutomation.op("coins", 5)], [CardAutomation.op("treasure")]][value - 1])
		"tower_result":
			var steps: Array = []
			if value in [3, 4]:
				for index in monsters.size():
					steps.append({"op": "monster_damage", "item": index, "amount": 1})
			else:
				for offset in players.size():
					var seat: int = (owner + offset) % players.size()
					steps.append({"op": "damage", "target": seat, "amount": 1 if value <= 2 else 2})
			_insert_card_steps(steps)
		"temperance":
			_insert_card_steps([CardAutomation.op("damage", int(step.damage)), CardAutomation.op("coins", int(step.coins))])
		"kill_player":
			hp[int(step.target)] = 0
			_last_player_killer[int(step.target)] = owner
		"fool_end":
			resolving["end_turn_after"] = true
		"devil_destroy":
			var item: Dictionary = items[owner][int(step.item)]
			_destroy_item(owner, int(step.item))
			var id: int = int(item.id)
			if discards.treasure.has(id) or discards.loot.has(id):
				_insert_card_steps([{"op": "steal", "targets": "steal_or_shop"}])
		_:
			super._apply_card_step(step)
