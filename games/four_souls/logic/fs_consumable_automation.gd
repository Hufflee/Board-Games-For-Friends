extends "res://games/four_souls/logic/fs_rune_automation.gd"
## Одноразовые карты: выбор без произвольных операций, возврат добычи, души и замена монстров.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	match str(step.get("targets", "")):
		"pending_loot":
			for index in stack.size():
				if stack[index].kind == "loot":
					out.append({"label": FSData.title(int(stack[index].card)), "arg": {"op": str(step.op), "index": index}})
		"key_modes":
			out.append({"label": "Активному игроку: ещё одна атака", "arg": {"op": "extra_attack", "target": current, "amount": 1}})
			if not decks.monster.is_empty() or not discards.monster.is_empty():
				for slot in monsters.size():
					if slot != battle:
						out.append({"label": "Открыть монстра поверх: " + FSData.title(int(monsters[slot].id)), "arg": {"op": "key_cover", "item": slot}})
		"most_souls":
			for seat in players.size():
				if int(souls[seat]) == int(souls.max()):
					out.append({"label": name_of(seat), "arg": {"op": "judgement_player", "target": seat}})
		"chosen_souls":
			var target: int = _card_choice_owner()
			for index in soul_cards[target].size():
				var id: int = int(soul_cards[target][index].id)
				if FSData.card(id).get("kind", "") != "character":
					out.append({"label": "Уничтожить: " + FSData.title(id), "arg": {"op": "judgement_soul", "target": target, "item": index}})
		"joker_hand":
			var target: int = int(resolving.joker_player)
			for index in hands[target].size():
				var id: int = int(hands[target][index])
				out.append({"label": "Украсть: " + FSData.title(id), "arg": {"op": "joker_take", "target": target, "item": index, "card": id}})
		"discarded_monsters":
			for id in discards.monster:
				if FSData.card(int(id)).get("kind", "") == "monster":
					out.append({"label": FSData.title(int(id)), "arg": {"op": "note_monster", "card": int(id), "remaining": int(step.remaining)}})
		"note_slots":
			for slot in monsters.size():
				if slot != battle:
					out.append({"label": "Положить поверх: " + FSData.title(int(monsters[slot].id)), "arg": {"op": "note_place", "item": slot, "card": int(step.card), "remaining": int(step.remaining)}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"bean_return":
			var canceled: Dictionary = stack.pop_at(int(step.index))
			_resolving_base = mini(_resolving_base, stack.size())
			hands[owner].append(int(canceled.card))
		"era_walk":
			_era_face = int(resolving.automation_roll)
			_era_left = 4
		"key_cover":
			var id := _draw("monster")
			if id >= 0:
				if FSData.card(id).kind == "event":
					_push({"kind": "event", "card": id, "owner": owner}, "effect")
				else:
					_cover_consumable_monster(id, int(step.item))
		"note_monster":
			_insert_card_steps([{"op": "note_place", "targets": "note_slots", "card": int(step.card), "remaining": int(step.remaining)}])
		"note_place":
			var id: int = int(step.card)
			var slot: int = int(step.item)
			if discards.monster.has(id):
				discards.monster.erase(id)
				_cover_consumable_monster(id, slot)
				if int(step.remaining) > 1:
					_insert_card_steps([{"op": "note_monster", "targets": "discarded_monsters", "optional": true, "remaining": int(step.remaining) - 1}])
		"emergency_contact":
			if battle >= 0:
				var slot: int = battle
				var removed: Dictionary = monsters[slot]
				_eggs_monsters.erase(int(removed.id))
				_end_battle()
				_put_monster20(removed, "bottom")
				if removed.has("under"):
					monsters[slot] = removed.under
				else:
					_eggs_monsters.erase(int(monsters[slot].id))
					monsters.remove_at(slot)
					resolving["refill_monsters"] = true
				resolving["_resume"] = "turn"
				_after_stack = "turn"
		"joker_player":
			resolving["joker_player"] = int(step.target)
			peek = {"owner": owner, "hands": [{"seat": int(step.target), "cards": hands[int(step.target)].duplicate()}]}
		"joker_take":
			if int(step.target) != owner:
				hands[owner].append(int(hands[int(step.target)].pop_at(int(step.item))))
			peek = {}
		"jera":
			_draw_loot(owner, hands[owner].size())
		"credit_card":
			_credit_free = true
		"holy_card":
			_holy_saves[int(step.target)] = owner
		"gold_key":
			_gold_deck_attacks = true
		"jail_card":
			_jail_owner = owner
		"judgement_player":
			resolving["choice_owner"] = int(step.target)
		"judgement_soul":
			_effect({"op": "destroy_soul", "target": int(step.target), "item": int(step.item)})
			resolving.erase("choice_owner")
		"blank_rune":
			var face: int = int(resolving.automation_roll)
			var steps: Array = []
			for offset in players.size():
				steps.append({"op": "damage" if face == 3 else "loot" if face in [2, 5] else "coins", "target": (owner + offset) % players.size(), "amount": {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6}[face]})
			_insert_card_steps(steps)
		"ehwaz":
			var ids: Array = []
			for slot in monsters.size():
				if slot != battle:
					ids.append(int(monsters[slot].id))
			for id in ids:
				_insert_card_steps([{"op": "ehwaz_replace", "card": id}])
		"ehwaz_replace":
			for slot in monsters.size():
				if slot != battle and int(monsters[slot].id) == int(step.card):
					var previous: Dictionary = monsters[slot].get("under", {})
					discards.monster.append(int(step.card))
					var id := _draw("monster")
					if id >= 0 and FSData.card(id).kind != "event":
						var fresh := {"id": id, "hp": _monster_hp(id), "dc": FSData.stat(id, "dc", 4), "at": FSData.stat(id, "at", 1)}
						if not previous.is_empty():
							fresh["under"] = previous
						monsters[slot] = fresh
					else:
						if previous.is_empty():
							_eggs_monsters.erase(int(monsters[slot].id))
							monsters.remove_at(slot)
							if battle > slot:
								battle -= 1
							resolving["refill_monsters"] = true
						else:
							monsters[slot] = previous
						if id >= 0:
							_push({"kind": "event", "card": id, "owner": owner}, "effect")
					break
		_:
			super._apply_card_step(step)

func _cover_consumable_monster(id: int, slot: int) -> void:
	monsters[slot] = {"id": id, "hp": _monster_hp(id), "dc": FSData.stat(id, "dc", 4), "at": FSData.stat(id, "at", 1), "under": monsters[slot]}
