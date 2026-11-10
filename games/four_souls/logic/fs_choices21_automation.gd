extends "res://games/four_souls/logic/fs_bill21_automation.gd"
## Группа21: чужой выбор на аукционе, просмотр добычи и монстр под предметом.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	var owner: int = int(resolving.get("owner", current))
	match str(step.get("targets", "")):
		"auction_shop21":
			for index in shop.size():
				if int(shop[index]) >= 0:
					out.append({"label": FSData.title(int(shop[index])), "arg": {"op": "auction_prepare21", "item": index, "card": int(shop[index])}})
		"auction_bids21":
			var bidder: int = int(resolving.choice_owner)
			out.append({"label": "Пас", "arg": {"op": "auction_bid21", "amount": 0}})
			for amount in range(int(resolving.auction_high21) + 1, int(coins[bidder]) + 1):
				out.append({"label": "Ставка %d¢" % amount, "arg": {"op": "auction_bid21", "amount": amount}})
		"loot_three21":
			for id in peek.get("cards", []):
				out.append({"label": FSData.title(int(id)), "arg": {"op": "loot_three21", "card": int(id)}})
		"held_monster21":
			for slot in monsters.size():
				var source: Dictionary = monsters[slot]
				if slot != battle and not source.has("virtual_zone15") and not bool(source.get("ambush_event20", false)):
					out.append({"label": FSData.title(int(source.id)), "arg": {"op": "hold_monster21", "item": slot}})
		"typed_counters21":
			for seat in active_seats():
				for index in items[seat].size():
					_append_counter_choices21(out, items[seat][index], "item", index, seat)
			for slot in shop.size():
				var id: int = int(shop[slot])
				if id >= 0:
					_append_counter_choices21(out, {"id": id, "eternal": _eternal_shop15.has(id), "counters": int(_shop_counters20.get(id, FSData.item_entry(id).counters))}, "shop", slot)
			for slot in monsters.size():
				if not monsters[slot].has("virtual_zone15"):
					_append_counter_choices21(out, monsters[slot], "monster", slot)
					var eggs: Dictionary = _eggs_monsters.get(int(monsters[slot].id), {})
					for color in ["white", "red", "black"]:
						if int(eggs.get(color, 0)) > 0:
							_append_counter_delta21(out, int(monsters[slot].id), "monster_egg", slot, -1, color, {"white": "белое яйцо", "red": "красное яйцо", "black": "чёрное яйцо"}[color])
			for index in _extra_rooms20.size():
				_append_counter_choices21(out, _extra_rooms20[index], "room", index)
			_append_counter_choices21(out, _native_room_source24(-1), "primary_room", -1)
		"outside_characters21":
			for candidate: Dictionary in FSData.characters(dlc):
				var starter: int = int(candidate.item)
				var unavailable := starter in shop or _physical_in_play16(starter) or _extra_rooms20.any(func(entry): return int(entry.get("physical_id13", entry.id)) == starter)
				if int(candidate.card) not in chars and (starter < 0 or not unavailable):
					out.append({"label": FSData.title(int(candidate.card)), "arg": {"op": "replace_character21", "card": int(candidate.card), "starter": int(candidate.item)}})
		"eden_start21":
			for id in peek.get("cards", []):
				out.append({"label": FSData.title(int(id)), "arg": {"op": "eden_start21", "card": int(id)}})
	return out

func _append_counter_choices21(out: Array, source: Dictionary, zone: String, index: int, seat: int = -1) -> void:
	if source.is_empty() or bool(source.get("eternal", false)) or _protected20(seat, int(resolving.owner)):
		return
	for field in ["counters", "health_tokens15", "attack_tokens15", "gold_counters22"]:
		if int(source.get(field, 0)) <= 0:
			continue
		var title: String = {"counters": "жетон", "health_tokens15": "жетон здоровья", "attack_tokens15": "жетон атаки", "gold_counters22": "золотой жетон"}[field]
		_append_counter_delta21(out, int(source.id), zone, index, seat, field, title)

func _append_counter_delta21(out: Array, id: int, zone: String, index: int, seat: int, field: String, title: String) -> void:
	for change in [-1, 1]:
		out.append({"label": FSData.title(id) + " · " + ("+1 " if change > 0 else "−1 ") + title, "arg": {"op": "typed_counter21", "zone": zone, "item": index, "target": seat, "field": field, "amount": change}})

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var source: Dictionary = resolving.get("source", {})
	match str(step.op):
		"auction_prepare21":
			resolving["auction_card21"] = int(step.card)
			resolving["auction_high21"] = 0
			resolving["auction_winner21"] = -1
			resolving["auction_queue21"] = []
			for offset in range(1, players.size()):
				resolving.auction_queue21.append((owner + offset) % players.size())
			_next_auction21()
		"auction_bid21":
			var bidder: int = int(resolving.choice_owner)
			var amount: int = int(step.amount)
			resolving.auction_queue21.pop_front()
			if amount > 0:
				resolving.auction_high21 = amount
				resolving.auction_winner21 = bidder
				resolving.auction_queue21.clear()
				for offset in range(1, players.size()):
					var other := (bidder + offset) % players.size()
					if other != owner:
						resolving.auction_queue21.append(other)
				_note("%s: ставка%d¢" % [name_of(bidder), amount])
			_next_auction21()
		"loot_three21":
			var id: int = int(step.card)
			decks.loot.erase(id)
			peek.cards.erase(id)
			hands[owner].append(id)
			if not peek.cards.is_empty():
				_insert_card_steps([{"op": "loot_rest21", "targets": "other_players"}])
			else:
				peek = {}
		"loot_rest21":
			for id in peek.get("cards", []).duplicate():
				decks.loot.erase(int(id))
				hands[int(step.target)].append(int(id))
			peek = {}
		"held_mode21":
			if source.has("held_monster21"):
				resolving["placing_monster21"] = int(source.held_monster21)
				_insert_card_steps([{"op": "release_monster21", "targets": "place_monster21"}])
			else:
				_insert_card_steps([{"op": "hold_monster21", "targets": "held_monster21"}])
		"hold_monster21":
			var slot: int = int(step.item)
			var monster: Dictionary = monsters[slot]
			if bool(monster.get("ambush_return20", false)):
				_put_monster20(monster, "discard")
			else:
				var physical: int = int(monster.get("physical_id20", monster.id))
				source["held_monster21"] = physical
				if not source.has("stored_cards20"):
					source["stored_cards20"] = []
				source.stored_cards20.append(physical)
			_eggs_monsters.erase(int(monster.id))
			if monster.has("under"):
				monsters[slot] = monster.under
			else:
				monsters.remove_at(slot)
				if battle > slot:
					battle -= 1
				for pending: Dictionary in stack:
					if pending.kind == "attack" and int(pending.slot) >= slot:
						pending.slot = int(pending.slot) - 1 if int(pending.slot) > slot else -2
			resolving["refill_monsters"] = true
		"release_monster21":
			var id: int = int(source.held_monster21)
			source.erase("held_monster21")
			source.stored_cards20.erase(id)
			_place_encounter_monster(id, int(step.item))
			_forced_monsters14.append(id)
			attack_left += 1
			attacked = false
		"typed_counter21":
			var chosen: Dictionary
			var field: String = str(step.field)
			match str(step.zone):
				"item": chosen = items[int(step.target)][int(step.item)]
				"monster": chosen = monsters[int(step.item)]
				"monster_egg": chosen = _eggs_monsters[int(monsters[int(step.item)].id)]
				"primary_room": chosen = _native_room_source24(-1)
				"shop":
					var id: int = int(shop[int(step.item)])
					_shop_counters20[id] = int(_shop_counters20.get(id, FSData.item_entry(id).counters)) + int(step.amount)
					return
				_: chosen = _extra_rooms20[int(step.item)]
			chosen[field] = int(chosen[field]) + int(step.amount)
			if step.zone == "monster" and step.field == "health_tokens15":
				chosen.hp = clampi(int(chosen.hp) + int(step.amount), 0, _monster_max15(chosen))
			_refresh_passive_stats()
		"replace_character21":
			_replace_character21(owner, int(step.card), int(step.starter))
		"eden_start21":
			var id: int = int(step.card)
			decks.treasure.erase(id)
			peek = {}
			_add_starter21(owner, id)
		_:
			super._apply_card_step(step)

func _replace_character21(owner: int, id: int, starter: int) -> void:
	var previous: int = int(chars[owner])
	var damage: int = int(max_hp[owner]) - int(hp[owner])
	for index in items[owner].size():
		if bool(items[owner][index].get("starter21", index == 0 and bool(items[owner][index].eternal))):
			var old := _remove_item(owner, index, true)
			_outside_starters21.append(int(old.id))
			break
	chars[owner] = id
	character_ready[owner] = true
	_character_tokens20.erase(owner)
	max_hp[owner] = maxi(1, int(max_hp[owner]) + PassiveRules.character_health(id) - PassiveRules.character_health(previous))
	_refresh_passive_stats()
	hp[owner] = maxi(0, int(max_hp[owner]) - damage) if not dead[owner] else 0
	if starter >= 0:
		_add_starter21(owner, starter)
	elif str(FSData.card(id).get("key", "")) == "eden":
		_insert_card_steps([{"op": "peek_deck", "deck": "treasure", "amount": 3}, {"op": "eden_start21", "targets": "eden_start21"}])

func _add_starter21(owner: int, id: int) -> void:
	_remove_from_piles16(id)
	_outside_starters21.erase(id)
	_gain_item(owner, id, true)
	var starter: Dictionary = items[owner].pop_back()
	starter["starter21"] = true
	items[owner].push_front(starter)

func _next_auction21() -> void:
	if not resolving.auction_queue21.is_empty():
		resolving["choice_owner"] = int(resolving.auction_queue21[0])
		_insert_card_steps([{"op": "auction_bid21", "targets": "auction_bids21"}])
		return
	resolving.erase("choice_owner")
	var winner: int = int(resolving.auction_winner21)
	var price: int = int(resolving.auction_high21)
	var slot := shop.find(int(resolving.auction_card21))
	if winner >= 0 and slot >= 0 and int(coins[winner]) >= price:
		_transfer_coins(winner, int(resolving.owner), price)
		_effect({"op": "take_shop", "target": winner, "item": slot})
