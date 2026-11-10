extends "res://games/four_souls/logic/fs_trinket_automation.gd"
## Сокровища: передача самого источника, сброс и выбор урона пассивов.

func _card_choices() -> Array:
	var out := super._card_choices()
	if str(_card_step().get("targets", "")) == "brimstone_targets":
		for slot in monsters.size():
			out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "monster_damage", "item": slot, "amount": 1}})
		for seat in active_seats():
			if seat != int(resolving.owner):
				out.append({"label": name_of(seat), "arg": {"op": "damage", "target": seat, "amount": 1}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"give_source":
			for index in items[owner].size():
				if int(items[owner][index].id) == int(resolving.card):
					items[int(step.target)].append(_remove_item(owner, index))
					_refresh_passive_stats()
					break
		"penny_counter":
			for item: Dictionary in items[owner]:
				if int(item.id) == 77:
					item.counters = int(item.counters) + 1
					_gain_coins(owner, int(item.counters))
					break
		"sack_discard":
			_insert_card_steps([{"op": "discard_loot", "targets": "own_hand", "amount": 1}] if not hands[owner].is_empty() and _item_count(owner, 523) == 0 else [{"op": "damage", "amount": 2}])
		_:
			super._apply_card_step(step)
