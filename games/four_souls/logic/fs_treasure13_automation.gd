extends "res://games/four_souls/logic/fs_treasure12_automation.gd"
## Пакет13: копия пассива, голосование, замены добора и условные выборы.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	var chooser := _card_choice_owner()
	match str(step.get("targets", "")):
		"gift_players13":
			for seat in players.size():
				out.append({"label":name_of(seat), "arg":{"op":"admiration_target", "target":seat}})
		"passive_items13", "vote_items13", "steal_players13", "cost_destroy13", "chosen_destroy13":
			for seat in players.size():
				if str(step.targets) == "steal_players13" and seat == owner:
					continue
				if str(step.targets) == "cost_destroy13" and seat != owner:
					continue
				if str(step.targets) == "chosen_destroy13" and seat != chooser:
					continue
				for index in items[seat].size():
					var item: Dictionary = items[seat][index]
					if str(step.targets) != "vote_items13" and bool(item.eternal):
						continue
					if str(step.targets) == "passive_items13" and (is_same(item, resolving.source) or FSData.item_response_kind(int(item.id)) not in ["passive", "conditional"]):
						continue
					out.append({"label":name_of(seat)+" · "+FSData.title(int(item.id)), "arg":{"op":str(step.op), "target":seat, "item":index, "card":int(item.get("physical_id13", item.id)), "shop":false}})
			if str(step.targets) in ["vote_items13", "passive_items13"]:
				for index in shop.size():
					if int(shop[index]) >= 0 and (str(step.targets) == "vote_items13" or (not _eternal_shop15.has(int(shop[index])) and FSData.item_response_kind(int(shop[index])) in ["passive", "conditional"])):
						out.append({"label":"Магазин · "+FSData.title(int(shop[index])), "arg":{"op":str(step.op), "item":index, "card":int(shop[index]), "shop":true}})
		"chaos_modes13":
			for mode in ["kill", "destroy"]:
				out.append({"label":"Убить игрока или монстра" if mode == "kill" else "Уничтожить предмет или душу", "arg":{"op":"chaos_mode13", "mode":mode}})
		"chaos_targets13":
			if str(resolving.chaos_mode13) == "kill":
				for seat in players.size():
					if not dead[seat]:
						out.append({"label":name_of(seat), "arg":{"op":"chaos_kill13", "target":seat}})
				for slot in monsters.size():
					if int(monsters[slot].hp)>0:
						out.append({"label":FSData.title(int(monsters[slot].id)), "arg":{"op":"chaos_monster13", "item":slot}})
			else:
				for seat in players.size():
					for index in items[seat].size():
						if not bool(items[seat][index].eternal):
							out.append({"label":FSData.title(int(items[seat][index].id)), "arg":{"op":"destroy", "target":seat, "item":index}})
					for index in soul_cards[seat].size():
						if FSData.card(int(soul_cards[seat][index].id)).get("kind", "") != "character":
							out.append({"label":"Душа · "+FSData.title(int(soul_cards[seat][index].id)), "arg":{"op":"destroy_soul", "target":seat, "item":index}})
			if int(resolving.card) == 181 and str(resolving.get("chaos_mode13", "")) == "destroy":
				for index in shop.size():
					if int(shop[index]) >= 0 and not _eternal_shop15.has(int(shop[index])):
						out.append({"label": "Магазин · " + FSData.title(int(shop[index])), "arg": {"op": "discard_shop", "item": index}})
		"recycle_hand13":
			for index in hands[owner].size():
				out.append({"label":"Сбросить: "+FSData.title(int(hands[owner][index])), "arg":{"op":"recycle_hand13", "item":index, "card":int(hands[owner][index])}})
		"discard_monsters13":
			for id in discards.monster:
				if FSData.card(int(id)).get("kind", "") == "monster":
					out.append({"label":FSData.title(int(id)), "arg":{"op":"monster_top13", "card":int(id)}})
		"shield_players13":
			for seat in players.size():
				out.append({"label":name_of(seat), "arg":{"op":"next_hit_shield", "zone":"player", "target":seat, "amount":2}})
		"damage_caps13":
			for seat in players.size():
				out.append({"label":name_of(seat), "arg":{"op":"damage_cap13", "zone":"player", "target":seat}})
			for monster: Dictionary in monsters:
				out.append({"label":FSData.title(int(monster.id)), "arg":{"op":"damage_cap13", "zone":"monster", "target":int(monster.id)}})
		"yes13":
			out.append({"label":"Применить способность", "arg":{"op":str(step.op)}})
		"crow_hand13":
			var target: int = int(resolving.automation_data.seat)
			for index in hands[target].size():
				out.append({"label":"Украсть: "+FSData.title(int(hands[target][index])), "arg":{"op":"crow_take13", "target":target, "item":index, "card":int(hands[target][index])}})
		"subtract_roll13":
			for index in stack.size():
				if stack[index].kind in ["roll", "effect_roll"]:
					for amount in [0, -1, -2]:
						out.append({"label":name_of(int(stack[index].owner))+" · %+d" % amount, "arg":{"op":"roll", "roll_index":index, "amount":amount}})
		"monsters":
			for index in monsters.size():
				out.append({"label":FSData.title(int(monsters[index].id)), "arg":{"op":"monster_damage", "item":index, "amount":1}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var chooser := _card_choice_owner()
	match str(step.op):
		"gift_only13":
			hands[owner].append(int(hands[chooser].pop_at(int(step.item))))
			resolving.erase("choice_owner")
		"double_draw13":
			_double_draw13[int(step.target)] = int(_double_draw13.get(int(step.target), 0))+1
		"copy_passive13":
			_copy_item14(int(step.card) if bool(step.shop) else int(items[int(step.target)][int(step.item)].id), false)
		"vote_prepare13":
			resolving["votes13"] = {}
			resolving["vote_seat13"] = 0
			resolving["choice_owner"] = owner
			_insert_card_steps([{"op":"vote_item13", "targets":"vote_items13"}])
		"vote_item13":
			var key := str(step.card)
			resolving.votes13[key] = int(resolving.votes13.get(key, 0))+1
			resolving.vote_seat13 = int(resolving.vote_seat13)+1
			if int(resolving.vote_seat13)<players.size():
				resolving["choice_owner"] = (owner+int(resolving.vote_seat13))%players.size()
				_insert_card_steps([{"op":"vote_item13", "targets":"vote_items13"}])
			else:
				resolving.erase("choice_owner")
				var most := 0
				var winners: Array = []
				for card in resolving.votes13:
					var count: int = int(resolving.votes13[card])
					if count>most:
						most = count
						winners = [int(card)]
					elif count == most:
						winners.append(int(card))
				if winners.size() == 1:
					_destroy_physical13(int(winners[0]))
		"destroy_cost13":
			var source: Dictionary = items[owner][int(step.item)]
			_destroy_item(owner, int(step.item))
			if not _source_item_in_play(source):
				resolving["cost_destroyed13"] = int(resolving.get("cost_destroyed13", 0))+1
				resolving["cost_paid12"] = int(resolving.cost_destroyed13) >= 2
			else:
				resolving.automation_step = resolving.automation_steps.size()
		"bag_result13":
			var value: int = int(resolving.automation_roll)
			if int(resolving.card) == 175:
				if value <= 2:
					_insert_card_steps([{"op":"loot"}])
				elif value <= 4:
					_insert_card_steps([{"op":"coins", "amount":4}])
			elif value <= 2:
				_insert_card_steps([{"op":"coins"}])
			elif value <= 4:
				_insert_card_steps([{"op":"loot"}])
			else:
				_grant_temporary_health(owner, 1)
		"piggy_reward13":
			if _source_item_in_play(resolving.source) and int(resolving.source.counters) >= 6:
				resolving.source.counters = int(resolving.source.counters)-6
				_insert_card_steps([{"op":"treasure"}])
		"random_destroy13":
			resolving["choice_owner"] = _rng.randi_range(0, players.size()-1)
			_note("Случайный игрок: "+name_of(_card_choice_owner()))
			_insert_card_steps([{"op":"chosen_destroy13", "targets":"chosen_destroy13"}, {"op":"restore_choice12"}])
		"chosen_destroy13":
			_destroy_item(chooser, int(step.item))
		"self_shield13":
			_next_hit_shields.append({"zone":"player", "target":owner, "amount":1})
		"chaos_mode13":
			resolving["chaos_mode13"] = str(step.mode)
			_insert_card_steps([{"op":"chaos_target13", "targets":"chaos_targets13"}])
		"chaos_kill13":
			hp[int(step.target)] = 0
		"chaos_monster13":
			monsters[int(step.item)].hp = 0
			monsters[int(step.item)]["slayer"] = owner
		"discard_tops13":
			for deck in decks:
				var id := _draw(str(deck))
				if id >= 0:
					discards[deck].append(id)
		"recycle_hand13":
			var before: int = hands[owner].size()
			_effect({"op":"discard_loot", "target":owner, "item":int(step.item)})
			if hands[owner].size()<before:
				resolving["recycle_count13"] = int(resolving.get("recycle_count13", 0))+1
			_insert_card_steps([{"op":"recycle_hand13", "targets":"recycle_hand13", "optional":true}])
		"recycle_draw13":
			_draw_loot(owner, int(resolving.get("recycle_count13", 0)))
		"compost_arm13":
			_compost_draws13 += 1
		"unlimited_loot13":
			_unlimited_loot13[owner] = true
		"pay_health13":
			if int(hp[owner])>0:
				hp[owner] = int(hp[owner])-1
			else:
				resolving.automation_step = resolving.automation_steps.size()
		"monster_top13":
			discards.monster.erase(int(step.card))
			decks.monster.append(int(step.card))
		"damage_cap13":
			_next_hit_shields.append({"zone":str(step.zone), "target":int(step.target), "cap":1, "amount":0})
		"roller_damage13":
			_insert_card_steps([{"op":"damage", "target":int(resolving.automation_data.seat), "amount":1}])
		"optional_loot13":
			resolving["drew13"] = true
			_draw_loot(owner, 1)
		"discard_if_drew13":
			if bool(resolving.get("drew13", false)):
				_insert_card_steps([{"op":"discard_loot", "targets":"own_hand"}])
		"crow_reveal13":
			var target: int = int(resolving.automation_data.seat)
			peek = {"owner":owner, "hands":[{"seat":target, "cards":hands[target].duplicate()}]}
			_insert_card_steps([{"op":"crow_take13", "targets":"crow_hand13"}])
		"crow_take13":
			hands[owner].append(int(hands[int(step.target)].pop_at(int(step.item))))
			peek = {}
		_:
			super._apply_card_step(step)

func _destroy_physical13(id: int) -> void:
	for seat in players.size():
		for index in items[seat].size():
			if int(items[seat][index].get("physical_id13", items[seat][index].id)) == id:
				if not bool(items[seat][index].eternal):
					_destroy_item(seat, index)
				return
	for index in shop.size():
		if int(shop[index]) == id and not _eternal_shop15.has(id):
			_effect({"op":"discard_shop", "item":index})
			return

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	for owner in players.size():
		for entry: Dictionary in _ability_items20(owner).duplicate():
			var id: int = int(entry.id)
			var triggered := false
			match id:
				194:
					triggered = event == "death" and int(data.get("seat", -1)) == owner
				176:
					triggered = event == "roll" and int(data.get("value", 0)) == 2
				177:
					triggered = event == "damage" and int(data.get("seat", -1)) == owner
				179:
					triggered = event == "turn_start" and current == owner
				182, 186, 187:
					triggered = event == "turn_end" and current == owner
				197:
					triggered = event == "roll" and int(data.get("value", 0)) == 6
				198:
					triggered = event == "roll" and int(data.get("value", 0)) == 4
				201:
					triggered = event == "roll" and int(data.get("value", 0)) == 3
				203:
					triggered = event == "roll" and int(data.get("value", 0)) == 1
			if triggered:
				_queue_passive(owner, id, entry, [{"op":"trinket_automation", "amount":1, "context":event, "data":data.duplicate(true)}])

func _copy_allowances13(seat: int) -> Vector3i:
	var extra_attacks := 98 if _item_count(seat, 117)>0 else 0
	for id in [24, 25, 26, 254, 877]:
		extra_attacks += _item_count(seat, id)
	return Vector3i(_item_count(seat, 221)+_item_count(seat, 226), _item_count(seat, 105)+_item_count(seat, 173), extra_attacks)
