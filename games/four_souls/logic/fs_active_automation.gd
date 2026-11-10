extends "res://games/four_souls/logic/fs_treasure_automation.gd"
## Пакет10: выборы сокровищ и фиксированные таблицы. Клиент не задаёт величину эффекта.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	match str(step.get("targets", "")):
		"gift_players":
			for seat in active_seats():
				if seat not in resolving.get("gift_players", []):
					out.append({"label": "Добавить: " + name_of(seat), "arg": {"op": "gift_player", "target": seat}})
		"gift_cards":
			for id in peek.get("cards", []):
				for destination in ["top", "bottom"]:
					out.append({"label": ("Следующая сверху: " if destination == "top" else "Следующая снизу: ") + FSData.title(int(id)), "arg": {"op": "gift_arrange", "card": int(id), "destination": destination}})
		"pumpkin_cards", "xray_card":
			for id in peek.get("cards", []):
				out.append({"label": ("Получить: " if str(step.op) == "pumpkin_pick" else "Сбросить: ") + FSData.title(int(id)), "arg": {"op": str(step.op), "card": int(id)}})
		"shop_items":
			for index in shop.size():
				if int(shop[index]) >= 0:
					out.append({"label": FSData.title(int(shop[index])), "arg": {"op": "discard_shop", "item": index}})
		"tapped_items":
			for seat in active_seats():
				for index in items[seat].size():
					if bool(items[seat][index].tapped):
						out.append({"label": name_of(seat) + " · " + FSData.title(int(items[seat][index].id)), "arg": {"op": "gish_lock", "target": seat, "item": index}})
		"marked_faces":
			out.append({"label": "Изменить свой первый бросок атаки на5", "arg": {"op": "marked_set"}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var value: int = int(resolving.get("automation_roll", 0))
	var data: Dictionary = resolving.get("automation_data", {})
	match str(step.op):
		"gift_player":
			if not resolving.has("gift_players"):
				resolving["gift_players"] = []
			resolving.gift_players.append(int(step.target))
			_insert_card_steps([{"op": "gift_player", "targets": "gift_players", "optional": true}])
		"gift_peek":
			_apply_card_step({"op": "peek_deck", "deck": "treasure", "amount": resolving.get("gift_players", []).size()})
			if not peek.is_empty():
				peek["top_order"] = []
				peek["bottom_order"] = []
		"gift_arrange":
			peek.cards.erase(int(step.card))
			peek[str(step.destination) + "_order"].append(int(step.card))
			if peek.cards.is_empty():
				for id in peek.top_order + peek.bottom_order:
					decks.treasure.erase(int(id))
				for index in range(peek.top_order.size() - 1, -1, -1):
					decks.treasure.append(int(peek.top_order[index]))
				for index in range(peek.bottom_order.size() - 1, -1, -1):
					decks.treasure.push_front(int(peek.bottom_order[index]))
				peek = {}
			else:
				_insert_card_steps([{"op": "gift_arrange", "targets": "gift_cards"}])
		"gift_award":
			peek = {}
			var steps: Array = [{"op": "treasure", "amount": 1}]
			for target in resolving.get("gift_players", []):
				steps.append({"op": "treasure", "target": int(target), "amount": 1})
			_insert_card_steps(steps)
		"pumpkin_pick":
			var rest: Array = peek.cards.duplicate()
			for id in rest:
				decks.treasure.erase(int(id))
			rest.erase(int(step.card))
			_shuffle(rest)
			for id in rest:
				decks.treasure.push_front(int(id))
			peek = {}
			_gain_item(owner, int(step.card))
		"xray_discard":
			var deck: String = str(peek.deck)
			decks[deck].erase(int(step.card))
			discards[deck].append(int(step.card))
			peek = {}
		"tnt_result":
			_insert_card_steps([{"op": "damage", "amount": 1}] if value <= 2 else [{"op": "damage", "targets": "damage_targets", "amount": 1}])
		"dad_ring_result":
			if value >= 5:
				for slot in monsters.size():
					if int(monsters[slot].id) == int(data.card):
						_insert_card_steps([{"op": "temporary_monster_dc", "item": slot, "amount": -1}])
		"dollar_shop":
			var steps: Array = []
			for slot in shop.size():
				if int(shop[slot]) >= 0:
					steps.append({"op": "take_shop", "target": owner, "item": slot})
			_insert_card_steps(steps)
		"hallowed_take":
			if not discards.loot.is_empty():
				hands[owner].append(int(discards.loot.pop_back()))
		"chest_result":
			_insert_card_steps([{"op": "coins", "amount": 2}] if value <= 2 else [{"op": "loot", "amount": 2}, {"op": "hand_top", "targets": "own_hand_top", "amount": 1}] if value <= 4 else [{"op": "recharge_all", "target": owner}])
		"shadow_reward":
			_insert_card_steps([{"op": "coins", "amount": int(data.counters)}, {"op": "loot", "amount": int(data.counters)}])
		"milk_counter":
			for item: Dictionary in items[owner]:
				if int(item.id) == 93:
					item.counters = int(item.counters) + 1
					if int(item.counters) >= 3:
						item.counters = 0
						_insert_card_steps([{"op": "damage", "targets": "damage_targets", "amount": 1}])
					_refresh_passive_stats()
		"treatment_result":
			if value == 6:
				if not _room_has20(779) and not curses[owner].has(744) and discards.treasure.has(94):
					discards.treasure.erase(94)
					_gain_soul_card(owner, {"id": 94, "value": 1})
			else:
				_insert_card_steps([[{"op": "kill_player", "target": owner}], [{"op": "loot", "amount": 3}], [{"op": "coins", "amount": 9}], [{"op": "treasure", "amount": 1}], [{"op": "treasure", "amount": 2}]][value - 1])
		"pageant_result":
			_gain_coins(owner, value * 4)
		"gish_lock":
			items[int(step.target)][int(step.item)]["skip_recharge_once"] = true
		"marked_set":
			for effect: Dictionary in stack:
				if effect.kind == "roll" and _roll_token(effect) == int(data.token):
					effect.value = 5
					effect["final_value"] = 5
		_:
			super._apply_card_step(step)
