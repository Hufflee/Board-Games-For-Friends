extends "res://games/four_souls/logic/fs_monster20_automation.gd"
## Часть пакета20: пиромания, временная защита, PvP и пассивные мясные кубы.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if str(step.get("targets", "")) == "forced_items20":
		var owner: int = int(resolving.owner)
		for seat in active_seats():
			if seat == owner:
				continue
			for index in items[seat].size():
				var id: int = int(items[seat][index].id)
				var ability := _item_kind20(items[seat][index])
				if ability not in ["tap", "paid", "hybrid", "conditional"]:
					continue
				var variants: Array = [{"item": index, "tap": ability != "paid"}]
				if id == 248:
					variants.append({"item": index, "ability": "kill"})
				for arg: Dictionary in variants:
					if call("clone")._force_activate20(seat, arg):
						out.append({"label": name_of(seat) + " · " + FSData.title(id) + (" · 3 жетона" if arg.get("ability", "") == "kill" else ""), "arg": {"op": "force_activate20", "target": seat, "item": index, "activation": arg, "card": int(items[seat][index].get("physical_id13", id))}})
	if str(step.get("targets", "")) == "peek_discard20":
		for id in peek.get("cards", []):
			out.append({"label": "Сбросить: " + FSData.title(int(id)), "arg": {"op": "peek_discard20", "card": int(id)}})
		out.append({"label": "Оставшиеся положить обратно", "arg": {"op": "peek_order20"}})
	if str(step.get("targets", "")) == "booster_loot20":
		var owner: int = int(resolving.owner)
		for id in peek.get("cards", []):
			if int(id) in decks.loot:
				hands[owner].append(int(id))
				var allowed := _can_play_gift12(owner, int(id))
				hands[owner].pop_back()
				if allowed:
					out.append({"label": "Сыграть: " + FSData.title(int(id)), "arg": {"op": "booster_play20", "card": int(id)}})
	if str(step.get("targets", "")) == "karma_second20":
		for seat in active_seats():
			if seat != int(resolving.karma_first20):
				out.append({"label": name_of(seat), "arg": {"op": "karma_second20", "target": seat}})
	if str(step.get("targets", "")) == "karma_shop20":
		for index in shop.size():
			if int(shop[index]) >= 0:
				out.append({"label": FSData.title(int(shop[index])), "arg": {"op": "take_shop", "target": int(resolving.owner), "item": index, "card": int(shop[index]), "shop": true}})
	if str(step.get("targets", "")) == "stairway_slots20":
		var owner: int = int(resolving.owner)
		for slot in range(-2, shop.size()):
			if slot < 0 and _must_buy24():
				continue
			if (slot == -2 and (_item_count(owner, 473) <= 0 or discards.treasure.is_empty())) or (slot == -1 and decks.treasure.is_empty()) or (slot >= 0 and int(shop[slot]) < 0):
				continue
			if int(coins[owner]) >= _purchase_cost(owner, slot):
				out.append({"label": "Купить вслепую" if slot == -1 else "Купить из сброса" if slot == -2 else "Купить: " + FSData.title(int(shop[slot])), "arg": {"op": "stairway_buy20", "slot": slot}})
	if str(step.get("targets", "")) == "private_treasures20":
		for id in peek.get("cards", []):
			out.append({"label": FSData.title(int(id)), "arg": {"op": str(step.op), "card": int(id)}})
	if str(step.get("targets", "")) == "mushroom_modes20":
		for mode in ["attack", "shield"]:
			out.append({"label": "+1 атаки для следующего броска атаки" if mode == "attack" else "Предотвратить следующую 1 урона", "arg": {"op": "mushroom_mode20", "mode": mode}})
	if str(step.get("targets", "")) == "stairway_accept20" and not decks.treasure.is_empty():
		out.append({"label": "Посмотреть 7 верхних сокровищ", "arg": {"op": "peek_deck", "deck": "treasure", "amount": 7}})
	if str(step.get("targets", "")) == "mushrooms20":
		for owner in active_seats():
			for index in items[owner].size():
				if int(items[owner][index].id) == 5:
					out.append({"label": name_of(owner) + " · Волшебный гриб · %d жетонов" % int(items[owner][index].counters), "arg": {"op": "mushroom_counter20", "target": owner, "item": index, "card": 5, "shop": false}})
		for index in shop.size():
			if int(shop[index]) == 5:
				out.append({"label": "Магазин · Волшебный гриб · %d жетонов" % int(_shop_counters20.get(5, 3)), "arg": {"op": "mushroom_counter20", "item": index, "card": 5, "shop": true}})
	var chooser := _card_choice_owner() if _card_automation_active() else current
	return out.filter(func(choice): return _choice_target20(choice.arg, chooser))

func _protected20(target: int, chooser: int) -> bool:
	if not _card_automation_enabled() or target == chooser or target < 0 or target >= players.size():
		return false
	return _ability_items20(target).any(func(entry): return int(entry.id) == 9 and not bool(entry.tapped))

func _choice_target20(arg: Dictionary, chooser: int) -> bool:
	var op: String = str(arg.get("op", ""))
	if arg.has("target") and not bool(arg.get("shop", false)) and str(arg.get("zone", "player")) != "monster" and not op.begins_with("monster_"):
		if _protected20(int(arg.target), chooser):
			return false
	if arg.has("card"):
		var id: int = int(arg.card)
		for owner in players.size():
			if _protected20(owner, chooser) and (id in hands[owner] or items[owner].any(func(entry): return int(entry.get("physical_id13", entry.id)) == id) or soul_cards[owner].any(func(entry): return int(entry.id) == id)):
				return false
	if op == "monster_damage" and int(arg.get("item", -1)) >= 0 and int(arg.item) < monsters.size():
		var source: Dictionary = monsters[int(arg.item)]
		if source.has("virtual_zone15") or bool(source.get("ambush_event20", false)):
			return false
	return true

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"force_activate20":
			_force_activate20(int(step.target), step.activation)
		"peek_discard_prepare20":
			if not peek.is_empty():
				_insert_card_steps([{"op": "peek_discard20", "targets": "peek_discard20"}])
		"peek_discard20":
			var id: int = int(step.card)
			decks[str(peek.deck)].erase(id)
			peek.cards.erase(id)
			discards[str(peek.deck)].append(id)
			if peek.cards.is_empty():
				peek = {}
			else:
				_insert_card_steps([{"op": "peek_discard20", "targets": "peek_discard20"}])
		"peek_order20":
			_insert_card_steps([{"op": "order_peek"}])
		"top_loot20":
			_top_loot20[owner] = turn_serial
		"booster_reveal20":
			var cards: Array = decks.loot.slice(maxi(0, decks.loot.size() - 5))
			resolving["booster_cards20"] = cards.duplicate()
			peek = {"owner": owner, "deck": "loot", "cards": cards, "public": true, "source_card20": 4}
		"booster_play20":
			var id: int = int(step.card)
			decks.loot.erase(id)
			peek.cards.erase(id)
			resolving.booster_cards20.erase(id)
			if not peek.cards.is_empty():
				_insert_card_steps([{"op": "booster_play20", "targets": "booster_loot20", "optional": true}])
			_push({"kind": "loot", "owner": owner, "card": id}, "effect")
			_room_loot_plays[owner] = int(_room_loot_plays.get(owner, 0)) + 1
			_copy_loot14(owner, id)
			_emit_passives("loot_play", {"seat": owner, "card": id})
		"booster_done20":
			_discard_booster20(resolving)
			peek = {}
		"next_d8_20":
			_d8_next20[int(step.target)] = true
		"recharge_source20":
			if _source_item_in_play(resolving.source):
				resolving.source.tapped = false
		"karma_first20":
			resolving["karma_first20"] = int(step.target)
			_insert_card_steps([{"op": "karma_second20", "targets": "karma_second20"}, {"op": "karma_gifts20"}])
		"karma_second20":
			resolving["karma_second20"] = int(step.target)
		"karma_gifts20":
			if resolving.has("karma_second20"):
				_queue_packet15(int(resolving.karma_second20), 8, resolving.source, "gift20")
			_queue_packet15(int(resolving.karma_first20), 8, resolving.source, "gift20")
		"stairway_prepare20":
			var steps: Array = []
			for copy_index in _item_count(owner, 23):
				steps.append({"op": "peek_deck", "targets": "stairway_accept20", "deck": "treasure", "amount": 7, "optional": true})
				steps.append({"op": "order_peek"})
			steps.append({"op": "stairway_buy20", "targets": "stairway_slots20"})
			_insert_card_steps(steps)
		"stairway_buy20":
			buy_left -= 1
			bought = buy_left <= 0
			_push({"kind": "purchase", "owner": owner, "slot": int(step.slot), "cost": _purchase_cost(owner, int(step.slot))}, "effect")
		"mushroom_mode20":
			if str(step.mode) == "attack":
				_next_attack_damage20[owner] = int(_next_attack_damage20.get(owner, 0)) + 1
			else:
				damage_shields[owner] = int(damage_shields[owner]) + 1
		"mushroom_counter20":
			if bool(step.shop):
				_shop_counters20[5] = int(_shop_counters20.get(5, 3)) + 1
			else:
				var item: Dictionary = items[int(step.target)][int(step.item)]
				item.counters = int(item.counters) + 1
		"dataminer20":
			var value: int = int(resolving.automation_roll)
			match value:
				1, 5:
					for monster: Dictionary in monsters:
						if monster.has("virtual_zone15"):
							continue
						monster.at = int(monster.at) + (1 if value == 1 else 9) - _monster_attack(monster)
				2:
					_insert_card_steps([{"op": "destroy_self"}, {"op": "character_attack20"}])
				3:
					for seat in players.size():
						character_ready[seat] = false
						for source: Dictionary in items[seat]:
							source.tapped = true
					for monster: Dictionary in monsters:
						monster["tapped"] = true
				4:
					_zero_hand20[owner] = true
				6:
					_insert_card_steps([{"op": "destroy_self"}, {"op": "attack_nine20"}])
		"character_attack20":
			_character_tokens20[owner] = int(_character_tokens20.get(owner, 0)) + 1
			_refresh_passive_stats()
		"attack_nine20":
			var delta := 9 - int(attack[owner])
			attack[owner] = 9
			temporary_attack.append([owner, delta])
		"own_cancel20":
			if (battle >= 0 or battle_player >= 0) and (owner == current or owner == _battle_roller15()):
				_end_battle()
		"full_heal20":
			if not dead[owner]:
				hp[owner] = int(max_hp[owner])
		"source_counter20":
			if _source_item_in_play(resolving.source):
				resolving.source.counters = int(resolving.source.counters) + int(step.amount)
		"tumor_save20":
			_tumor_saves20[int(step.target)] = turn_serial
		"deck_take_prepare20":
			resolving["remaining_pick20"] = 2
			_insert_card_steps([{"op": "deck_take20", "targets": "private_treasures20"}])
		"deck_take20":
			var id: int = int(step.card)
			decks.treasure.erase(id)
			peek.cards.erase(id)
			resolving.remaining_pick20 = int(resolving.remaining_pick20) - 1
			if int(resolving.remaining_pick20) > 0 and not peek.cards.is_empty():
				_insert_card_steps([{"op": "deck_take20", "targets": "private_treasures20"}])
			else:
				_bottom_peek20()
			_gain_item(owner, id)
		"delirium_copy20":
			_note("Мелкий Делирий открывает: " + FSData.title(int(step.card)), int(step.card))
			_copy_item14(int(step.card), false)
			_bottom_peek20()
		"pyro_search20":
			var count := 0
			for id in decks.loot.duplicate():
				if count < 2 and FSData.card(int(id)).get("key", "") == "bomb":
					decks.loot.erase(int(id))
					hands[owner].append(int(id))
					count += 1
			_shuffle(decks.loot)
			_note("Пироманьяк: открыты и получены %d Бомбы" % count)
		"nail20":
			_nail_turn20 = turn_serial
		"unicorn20":
			_unicorn_turn20[owner] = turn_serial
		_:
			super._apply_card_step(step)

func _gain_item(seat: int, id: int, eternal: bool = false) -> void:
	super._gain_item(seat, id, eternal)
	if _card_automation_enabled() and id == 5 and _shop_counters20.has(5):
		for source: Dictionary in items[seat]:
			if int(source.id) == 5:
				source.counters = int(_shop_counters20[5])
				_shop_counters20.erase(5)
				break
	if _card_automation_enabled() and id == 17:
		for source: Dictionary in items[seat]:
			if int(source.id) == id:
				_queue_packet15(seat, id, source, "gain_item")
				break

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	if event == "turn_start":
		_zero_hand20.erase(current)
	for owner in players.size():
		for source: Dictionary in _ability_items20(owner).duplicate():
			if int(source.id) == 12 and event == "roll" and int(data.get("value", 0)) == 6:
				_queue_packet15(owner, 12, source, event, data)
			if int(source.id) == 8 and event == "soul_control" and int(data.get("seat", -1)) != owner:
				_queue_packet15(owner, 8, source, event, data)
			if int(source.id) in [13, 27] and event == "turn_start" and owner == current:
				_queue_packet15(owner, int(source.id), source, event, data)
	if event == "roll" and int(data.get("value", 0)) in [1, 2, 3] and int(_unicorn_turn20.get(int(data.get("seat", -1)), -1)) == turn_serial:
		_queue_packet15(int(data.seat), 29, {}, "roll", data)
	if event == "death" and int(data.get("killer", -1)) >= 0 and int(data.killer) != int(data.seat):
		for owner in players.size():
			for source: Dictionary in _ability_items20(owner).duplicate():
				if int(source.id) == 20:
					_queue_packet15(owner, 20, source, event, data)

func _damage_player(seat: int, amount: int, context: Dictionary = {}) -> void:
	var adjusted := context.duplicate()
	if _card_automation_enabled():
		if int(_unicorn_turn20.get(seat, -1)) == turn_serial:
			return
		if bool(context.get("combat", false)) and int(context.get("value", 0)) == 4 and _item_count(seat, 32) > 0 and _meat_count20(seat) >= 2:
			return
		if not bool(context.get("combat", false)) and not bool(context.get("pyro20", false)) and not bool(context.get("prepared", false)):
			var attacker: int = int(context.get("attacker", -1))
			if attacker >= 0 and attacker < players.size() and amount > 0:
				amount += _item_count(attacker, 17)
			adjusted["pyro20"] = true
	super._damage_player(seat, amount, adjusted)

func _meat_count20(seat: int) -> int:
	var count := 0
	for entry: Dictionary in items[seat] + soul_cards[seat]:
		if int(entry.id) in [30, 31, 32, 89]:
			count += 1
	return count

func _maximum_hand20(seat: int, limit: int) -> int:
	return 0 if _card_automation_enabled() and _zero_hand20.has(seat) else limit

func _save_player20(seat: int) -> bool:
	if not _card_automation_enabled() or int(_tumor_saves20.get(seat, -1)) != turn_serial:
		return false
	_tumor_saves20.erase(seat)
	hp[seat] = int(max_hp[seat])
	if (battle >= 0 or battle_player >= 0) and (seat == current or seat == _battle_roller15()):
		_queue_packet15(seat, 10, {}, "saved20")
	return true

func _bottom_peek20() -> void:
	var rest: Array = peek.get("cards", []).duplicate()
	for id in rest:
		decks.treasure.erase(int(id))
	_shuffle(rest)
	rest.append_array(decks.treasure)
	decks.treasure = rest
	peek = {}

func _resolve_mushroom20(effect: Dictionary) -> void:
	_begin_resolving({"kind": "item", "card": 5, "owner": int(effect.owner), "source": {}, "conditional": true, "automation_context": "character20"})
	_advance_card_automation()

func _start_stairway20(seat: int) -> void:
	var source: Dictionary = {}
	for entry: Dictionary in items[seat]:
		if int(entry.id) == 23:
			source = entry
			break
	_begin_resolving({"kind": "item", "card": 23, "owner": seat, "source": source, "conditional": true, "automation_context": "purchase", "_resume": "turn"})
	_advance_card_automation()

func _discard_booster20(effect: Dictionary) -> void:
	for id in effect.get("booster_cards20", []):
		if int(id) in decks.loot:
			decks.loot.erase(int(id))
			discards.loot.append(int(id))
	effect["booster_cards20"] = []

## Карта требует чужую активацию; добровольное10-секундное окно не отменяет её текст.
## Тюрьма,256,состояние предмета и настоящая цена по-прежнему проверяются action.
func _force_activate20(seat: int, arg: Dictionary) -> bool:
	var before_phase := phase
	var before_after := _after_stack
	var before_forced := _forced_activation20
	phase = "priority"
	_after_stack = "effect"
	_forced_activation20 = true
	var accepted := action(seat, "activate", arg)
	_forced_activation20 = before_forced
	if not accepted:
		phase = before_phase
		_after_stack = before_after
	return accepted

func _permitted_player_attack_targets() -> Array:
	if _card_automation_enabled() and _forced_deck_remaining() > 0 and _required_player_remaining() <= 0 and _lust_pending.is_empty():
		return []
	var out := super._permitted_player_attack_targets()
	if not _card_automation_enabled() or attacked or attack_left <= _optional_blind17 or not _lust_pending.is_empty():
		return out
	for seat in _player_attack_targets():
		if seat not in out and (_nail_turn20 == turn_serial or _item_count(current, 28) > 0 or _item_count(int(seat), 28) > 0):
			out.append(seat)
	return out

func _pvp_defense16(target: int) -> int:
	if _card_automation_enabled():
		if _nail_turn20 == turn_serial:
			return 4
		if _item_count(current, 28) > 0 or _item_count(target, 28) > 0:
			return 5
	return super._pvp_defense16(target)
