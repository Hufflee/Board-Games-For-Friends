extends "res://games/four_souls/logic/fs_consumable_automation.gd"
## Брелоки: обязательные броски и выборы запускает событие, не кнопка ручного срабатывания.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if str(step.get("targets", "")) == "trinket_peek":
		out.append({"label": "Оставить сверху", "arg": {"op": "close_peek"}})
		if not peek.get("cards", []).is_empty():
			out.append({"label": "Положить под низ колоды", "arg": {"op": "trinket_bottom"}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var data: Dictionary = resolving.get("automation_data", {})
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"found_soul_give":
			for index in items[owner].size():
				if is_same(items[owner][index], resolving.source):
					items[int(step.target)].append(_remove_item(owner, index))
					_refresh_passive_stats()
					break
		"pink_eye_damage":
			if data.has("monster"):
				for slot in monsters.size():
					if int(monsters[slot].id) == int(data.monster):
						_insert_card_steps([{"op": "monster_damage", "item": slot, "amount": 1}])
			elif data.has("attacker"):
				_insert_card_steps([{"op": "damage", "target": int(data.attacker), "amount": 1}])
		"aaa_result":
			if value >= 4:
				_insert_card_steps([{"op": "recharge", "targets": "items"}])
		"poker_result":
			_gain_coins(owner, 1 if value <= 3 else int(data.amount) * 2, true, bool(data.get("equality_done", false)))
		"trinket_bottom":
			var deck: String = str(peek.deck)
			var id: int = int(peek.cards[0])
			decks[deck].erase(id)
			decks[deck].push_front(id)
			peek = {}
		"hairball_result":
			var damage: int = maxi(0, int(data.amount) - (1 if value == 6 else 0))
			var context: Dictionary = data.context.duplicate(true)
			context["prepared"] = true
			_damage_player(owner, damage, context)
		"ankh_result":
			if value == 6:
				hp[owner] = maxi(1, int(hp[owner]))
				resolving["end_turn_after"] = owner == current
		_:
			super._apply_card_step(step)
