extends "res://games/four_souls/logic/fs_tarot_automation.gd"
## Руны/пилюли: условные таблицы, обязательный выбор другого игрока, превращение и переброс предметов.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	var op: String = str(step.op)
	match str(step.get("targets", "")):
		"berkano_shop":
			for index in shop.size():
				if int(shop[index]) >= 0:
					out.append({"label": FSData.title(int(shop[index])), "arg": {"op": "berkano_take", "item": index}})
		"all_destroyable":
			for seat in players.size():
				for index in items[seat].size():
					if not bool(items[seat][index].eternal):
						out.append({"label": name_of(seat) + " · " + FSData.title(int(items[seat][index].id)), "arg": {"op": op, "target": seat, "item": index, "shop": false}})
			for index in shop.size():
				if int(shop[index]) >= 0 and not _eternal_shop15.has(int(shop[index])):
					out.append({"label": "Магазин · " + FSData.title(int(shop[index])), "arg": {"op": op, "target": owner, "item": index, "shop": true}})
		"gift_items":
			var giver: int = _card_choice_owner()
			for index in items[giver].size():
				if not bool(items[giver][index].eternal):
					out.append({"label": "Отдать: " + FSData.title(int(items[giver][index].id)), "arg": {"op": "gift_item", "target": giver, "item": index}})
		"own_hand_top":
			for index in hands[owner].size():
				out.append({"label": "Наверх колоды: " + FSData.title(int(hands[owner][index])), "arg": {"op": "hand_top", "item": index}})
		"cancel_loot":
			for index in stack.size():
				if stack[index].kind == "loot":
					out.append({"label": FSData.title(int(stack[index].card)), "arg": {"op": "cancel_selected", "index": index}})
		"monsters":
			for index in monsters.size():
				out.append({"label": FSData.title(int(monsters[index].id)), "arg": {"op": op, "item": index, "amount": int(step.get("amount", 1))}})
		"monster_room_decks":
			for deck in ["monster", "room"]:
				if not decks[deck].is_empty():
					out.append({"label": "Монстры" if deck == "monster" else "Комнаты", "arg": {"op": "peek_deck", "deck": deck, "amount": 5}})
		"hagalaz_targets":
			if room >= 0:
				out.append({"label": "Сбросить комнату", "arg": {"op": "discard_room"}})
			for index in monsters.size():
				if index != battle:
					out.append({"label": "Сбросить: " + FSData.title(int(monsters[index].id)), "arg": {"op": "discard_monster", "item": index}})
		"dagaz_modes":
			if curses.any(func(list: Array): return not list.is_empty()):
				out.append({"label": "Уничтожить проклятие", "arg": {"op": "dagaz_curse"}})
			out.append({"label": "Предотвратить следующий 1 урон игроку", "arg": {"op": "dagaz_shield"}})
		"all_curses":
			for seat in players.size():
				for id in curses[seat]:
					out.append({"label": name_of(seat) + " · " + FSData.title(int(id)), "arg": {"op": "destroy_curse", "target": seat, "card": int(id)}})
		"curse_recipients":
			for seat in players.size():
				if seat != int(resolving.curse_from):
					out.append({"label": name_of(seat), "arg": {"op": "transfer_curse", "target": seat}})
	if str(step.get("targets", "")) == "own_destroy" and op == "reroll_item":
		for choice: Dictionary in out:
			choice.arg["op"] = "reroll_item"
			choice.arg["target"] = owner
			choice.arg["shop"] = false
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"start_roll":
			resolving.erase("automation_roll")
		"rune_result":
			_insert_card_steps(_rune_result_steps(int(resolving.card), int(resolving.automation_roll)))
		"random_gift":
			resolving["choice_owner"] = _rng.randi_range(0, players.size() - 1)
			_note("Пилюля: предмет отдаёт " + name_of(_card_choice_owner()))
		"gift_item":
			var giver: int = int(step.target)
			if giver != owner:
				items[owner].append(_remove_item(giver, int(step.item)))
			resolving.erase("choice_owner")
		"hand_top":
			decks.loot.append(int(hands[owner].pop_at(int(step.item))))
		"self_item":
			resolving["kept_as_item"] = true
			_gain_item(owner, int(resolving.card))
		"self_health":
			_grant_temporary_health(owner, int(step.get("amount", 1)))
		"self_roll_bonus":
			_turn_roll_bonus[owner] = int(_turn_roll_bonus[owner]) + int(step.get("amount", 1))
		"self_monster_dc":
			_turn_monster_dc[owner] = int(_turn_monster_dc[owner]) + int(step.amount)
		"self_monster_attack":
			_turn_monster_attack[owner] = int(_turn_monster_attack[owner]) + int(step.amount)
		"grant_eternal":
			for item: Dictionary in items[int(step.target)]:
				_temporary_eternal.append({"source": item, "eternal": bool(item.eternal)})
				item.eternal = true
		"berkano_destroy", "reroll_item":
			if bool(step.get("shop", false)):
				if _eternal_shop15.has(int(shop[int(step.item)])):
					return
				_effect({"op": "discard_shop", "item": int(step.item)})
			else:
				var target: int = int(step.target)
				var item: Dictionary = items[target][int(step.item)]
				_destroy_item(target, int(step.item))
				var id: int = int(item.id)
				if discards.treasure.has(id) or discards.loot.has(id):
					if str(step.op) == "reroll_item":
						_insert_card_steps([{"op": "treasure", "target": target, "amount": 1}])
					else:
						resolving["choice_owner"] = target
						_insert_card_steps([{"op": "take_shop", "targets": "berkano_shop"}])
		"reroll_item_id":
			for index in items[owner].size():
				if int(items[owner][index].id) == int(step.card) and not bool(items[owner][index].eternal):
					_apply_card_step({"op": "reroll_item", "target": owner, "item": index, "shop": false})
					break
		"berkano_take":
			_effect({"op": "take_shop", "target": _card_choice_owner(), "item": int(step.item)})
			resolving.erase("choice_owner")
		"discard_own_hand":
			if _item_count(owner, 523) == 0:
				discards.loot.append_array(hands[owner])
				hands[owner].clear()
		"discard_other_hands":
			var steps: Array = []
			for offset in range(1, players.size()):
				steps.append({"op": "forced_card_discard", "target": (owner + offset) % players.size(), "amount": 1})
			_insert_card_steps(steps)
		"forced_card_discard":
			var target: int = int(step.target)
			if not hands[target].is_empty():
				_push({"kind": "forced_discard", "owner": owner, "target": target, "card": int(resolving.card), "amount": 1}, "effect")
		"damage_monsters":
			var steps: Array = []
			for index in monsters.size():
				steps.append({"op": "monster_damage", "item": index, "amount": 1})
			_insert_card_steps(steps)
		"ace_diamonds":
			_gain_coins(owner, monsters.size() + hands[owner].size())
		"discard_room":
			if room >= 0 and _room_can_discard():
				discards.room.append(room)
				room = _draw("room")
				_reset_room_goals()
		"dagaz_curse":
			_insert_card_steps([{"op": "destroy_curse", "targets": "all_curses"}])
		"dagaz_shield":
			_insert_card_steps([{"op": "prevent_damage", "targets": "players", "amount": 1}])
		"destroy_curse":
			if int(step.card) == 744:
				resolving["curse_from"] = int(step.target)
				resolving["choice_owner"] = int(step.target)
				_insert_card_steps([{"op": "transfer_curse", "targets": "curse_recipients"}])
			else:
				curses[int(step.target)].erase(int(step.card))
				discards.monster.append(int(step.card))
		"transfer_curse":
			curses[int(resolving.curse_from)].erase(744)
			curses[int(step.target)].append(744)
			resolving.erase("choice_owner")
		_:
			super._apply_card_step(step)

func _rune_result_steps(id: int, face: int) -> Array:
	match id:
		478, 479:
			return [CardAutomation.op("self_item")] if face >= 5 else []
		520:
			return [CardAutomation.op("loot", 2), {"op": "hand_top", "targets": "own_hand_top", "amount": 3}] if face <= 2 else [CardAutomation.op("loot", 4), {"op": "hand_top", "targets": "own_hand_top", "amount": 1}] if face <= 4 else [CardAutomation.op("loot", 3)]
		521:
			return [CardAutomation.op("temporary_attack")] if face <= 2 else [CardAutomation.op("self_health")] if face <= 4 else [CardAutomation.op("damage")]
		551:
			return [{"op": "recharge_all", "target": int(resolving.owner)}] if face <= 2 else [CardAutomation.op("self_monster_dc", -1)] if face <= 4 else [CardAutomation.op("self_monster_attack", 2)]
		579:
			return [{"op": "cancel_selected", "targets": "cancel_loot"}] if face <= 2 else [CardAutomation.op("discard_other_hands")] if face <= 4 else []
		580:
			if face <= 4:
				return [{"op": "reroll_item", "targets": "own_destroy" if face <= 2 else "all_destroyable"}]
			var steps: Array = []
			for item: Dictionary in items[int(resolving.owner)].duplicate():
				if not bool(item.eternal):
					steps.append({"op": "reroll_item_id", "card": int(item.id)})
			return steps
		581:
			return [{"op": "damage", "targets": "players", "amount": 1}] if face <= 2 else [{"op": "monster_damage", "targets": "monsters", "amount": 1}] if face <= 4 else [CardAutomation.op("damage")]
		584:
			return [CardAutomation.op("damage_monsters")] if face <= 2 else [{"op": "reroll_item", "targets": "all_destroyable"}] if face <= 4 else [CardAutomation.op("discard_own_hand"), CardAutomation.op("loot", 3)]
		672:
			return [CardAutomation.op("coins", 4 if face <= 2 else 7 if face <= 4 else -4)]
		673:
			return [CardAutomation.op("self_roll_bonus")] if face <= 2 else [CardAutomation.op("self_health")] if face <= 4 else [CardAutomation.op("damage")]
		674:
			return [CardAutomation.op("loot", 1)] if face <= 2 else [CardAutomation.op("loot", 3)] if face <= 4 else [{"op": "discard_loot", "targets": "own_hand", "amount": 1}]
	return []
