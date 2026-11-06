extends "res://games/four_souls/logic/fs_events24_automation.gd"
## Поворот, цены и здоровье комнаты хранятся у физического слота.
const ACTIVE_ROOMS24 := [755, 759, 760, 761, 762, 775, 776, 780, 784, 785, 801, 805]

func _native_room_source24(index: int) -> Dictionary:
	if index == -1:
		if room < 0:
			return {}
		if int(_primary_room24.get("id", -1)) != room:
			_primary_room24 = {"id": room, "tapped": false, "counters": 0}
		return _primary_room24
	if index < 0 or index >= _extra_rooms20.size() or bool(_extra_rooms20[index].get("room_item20", false)):
		return {}
	return _extra_rooms20[index]

func _room_sale_tokens24() -> int:
	if not _card_automation_enabled():
		return 0
	var count := 0
	for index in range(-1, _extra_rooms20.size()):
		var source := _native_room_source24(index)
		if int(source.get("id", -1)) == 758:
			count += int(source.get("counters", 0))
	return count

func _must_buy24() -> bool:
	if _room_sale_tokens24() <= 0 or buy_left <= 0 or dead[current]:
		return false
	for slot in shop.size():
		if int(shop[slot]) >= 0 and int(coins[current]) >= _purchase_cost(current, slot):
			return true
	return false

func _can_activate_room24(seat: int, source: Dictionary) -> bool:
	if not _card_automation_enabled() or source.is_empty() or seat != current or dead[seat] or phase not in ["turn", "priority", "battle_roll", "death"]:
		return false
	if _room_has20(814) and int(_room_activations.get(seat, 0)) >= 1:
		return false
	match int(source.id):
		755: return not bool(source.get("tapped", false)) and not decks.treasure.is_empty()
		759: return int(hp[seat]) >= 2 and shop.any(func(id): return int(id) >= 0)
		760: return int(hp[seat]) >= 1
		761: return int(coins[seat]) >= 2
		762, 784, 801, 805: return int(coins[seat]) >= 3
		775, 776, 785: return not hands[seat].is_empty()
		780: return int(hp[seat]) >= 1
	return false

func _activate_native_room24(seat: int, index: int, expected: int = -1) -> bool:
	var source := _native_room_source24(index)
	if not _can_activate_room24(seat, source) or (expected >= 0 and int(source.id) != expected):
		return false
	var id: int = int(source.id)
	var coin_cost: int = 3 if id in [762, 784, 801, 805] else (2 if id == 761 else 0)
	var health_cost: int = 2 if id == 759 else (1 if id in [760, 780] else 0)
	coins[seat] = int(coins[seat]) - coin_cost
	bank += coin_cost
	hp[seat] = int(hp[seat]) - health_cost
	if id == 755:
		source["tapped"] = true
	var resume: String = _after_stack if phase == "priority" else phase
	var loot_cost: bool = id in [775, 776, 785]
	var effect := {"kind": "item", "card": id, "owner": seat, "source": source, "automation_context": "room_cost24" if loot_cost else "room_activate24", "_resume": resume}
	if loot_cost:
		_begin_resolving(effect)
		_advance_card_automation()
	else:
		_push(effect, resume)
		_room_activations[seat] = int(_room_activations.get(seat, 0)) + 1
	return true

func _can_attack_room24(seat: int, source: Dictionary) -> bool:
	return _card_automation_enabled() and not source.is_empty() and int(source.id) in [757, 778] and seat == current and phase == "turn" and not dead[seat] and not attacked and battle < 0 and battle_player < 0 and attack_left > _optional_blind17 and _required_player_remaining() == 0 and _forced_deck_remaining() == 0 and _forced_slots14().is_empty() and int(coins[seat]) >= _attack_tax(seat)

func _attack_native_room24(seat: int, index: int) -> bool:
	var source := _native_room_source24(index)
	if not _can_attack_room24(seat, source):
		return false
	if _prepare_attack24(seat):
		return true
	if not _pay_attack_tax(seat):
		return false
	var id: int = int(source.id)
	monsters.append({"id": id, "hp": int(source.get("familiar_hp15", FSData.stat(id, "hp", 4))), "dc": FSData.stat(id, "dc", 4), "at": 1, "virtual_zone15": "native_room24", "virtual_ref15": source, "virtual_owner15": -1})
	attack_left -= 1
	attacked = attack_left <= 0
	_next_attack_token += 1
	var slot := monsters.size() - 1
	_push({"kind": "attack", "owner": seat, "slot": slot, "attack_token": _next_attack_token}, "turn")
	_emit_passives("attack_declared", {"seat": seat, "slot": slot, "token": _next_attack_token})
	return true

func _native_room_actions24(seat: int) -> Array:
	var out: Array = []
	for index in range(-1, _extra_rooms20.size()):
		var source := _native_room_source24(index)
		if not source.is_empty() and int(source.id) in ACTIVE_ROOMS24 + [757, 778]:
			out.append({"index": index, "card": int(source.id), "activate": seat >= 0 and _can_activate_room24(seat, source), "attack": seat >= 0 and _can_attack_room24(seat, source), "hp": int(source.get("familiar_hp15", FSData.stat(int(source.id), "hp", 4))), "tapped": bool(source.get("tapped", false))})
	return out

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	var owner: int = int(resolving.get("owner", current))
	match str(step.get("targets", "")):
		"room_guppy24":
			for id in peek.get("cards", []):
				if str(FSData.card(int(id)).get("key", "")).begins_with("guppy"):
					out.append({"label": FSData.title(int(id)), "arg": {"op": "room_guppy24", "card": int(id)}})
		"room_hit24":
			out.append({"label": "Получить 4¢", "arg": {"op": "coins", "amount": 4}})
			out.append({"label": "Взять 1 добычу", "arg": {"op": "loot", "amount": 1}})
		"room_cancel24":
			if battle >= 0 and (int(resolving.card) != 757 or is_same(monsters[battle].get("virtual_ref15", {}), resolving.get("source", {}))):
				out.append({"label": "Отменить атаку", "arg": {"op": "room_cancel24"}})
		"room_clear24":
			out.append({"label": "Сбросить предметы магазина", "arg": {"op": "room_clear24", "mode": "shop"}})
			out.append({"label": "Сбросить монстров вне текущей атаки", "arg": {"op": "room_clear24", "mode": "monster"}})
		"room_peek24":
			if not decks.monster.is_empty():
				out.append({"label": "Посмотреть 3 карты монстров", "arg": {"op": "peek_deck", "deck": "monster", "amount": 3}})
		"room_owned24":
			for index in items[owner].size():
				if not bool(items[owner][index].eternal):
					out.append({"label": FSData.title(int(items[owner][index].id)), "arg": {"op": "reroll_item", "target": owner, "item": index}})
		"room_reroll24":
			var token: int = int(resolving.automation_data.token)
			for index in stack.size():
				if stack[index].kind in ["roll", "effect_roll"] and _roll_token(stack[index]) == token:
					out.append({"label": "Перебросить", "arg": {"op": "reroll", "roll_index": index}})
		"room_attack_choice24":
			for slot in range(-1, monsters.size()):
				for over in (range(maxi(1, monsters.size())) if slot < 0 else [0]):
					var arg := {"slot": slot, "over": int(over)}
					var label: String = "Атаковать верх колоды · слот %d" % (int(over) + 1) if slot < 0 else FSData.title(int(monsters[slot].id))
					_add_attack_choice24(out, owner, label, "attack", arg)
			for seat in _permitted_player_attack_targets():
				_add_attack_choice24(out, owner, name_of(int(seat)), "attack_player", {"target": seat})
			var familiars := _familiar_targets15()
			for index in familiars.size():
				_add_attack_choice24(out, owner, FSData.title(int(familiars[index].card)), "attack_familiar15", {"index": index})
			for index in range(-1, _extra_rooms20.size()):
				var source := _native_room_source24(index)
				if int(source.get("id", -1)) in [757, 778]:
					_add_attack_choice24(out, owner, FSData.title(int(source.id)), "room_attack24", {"index": index})
	return out

func _add_attack_choice24(out: Array, owner: int, label: String, kind: String, arg: Dictionary) -> void:
	var probe: RefCounted = call("clone")
	probe.phase = "turn"
	probe._attack_prepared24 = true
	if probe.action(owner, kind, arg):
		out.append({"label": label, "arg": {"op": "room_attack_choice24", "attack24": arg, "kind24": kind}})

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"room_guppy24":
			var id: int = int(step.card)
			decks.treasure.erase(id)
			peek.cards.erase(id)
			_gain_item(owner, id)
		"room_bottom24":
			_bottom_peek20()
		"room_cancel24":
			if battle >= 0:
				_end_battle()
				resolving["_resume"] = "turn"
		"room_clear24":
			if str(step.mode) == "monster":
				_flush_monsters24(true)
			else:
				for slot in shop.size():
					if int(shop[slot]) >= 0 and not bool(_eternal_shop15.get(int(shop[slot]), false)):
						var id: int = int(shop[slot])
						_discard_item(id)
						_shop_counters20.erase(id)
						shop[slot] = -1
				_refill_shop24()
		"room_fortune24":
			var face: int = int(resolving.get("automation_roll", 1))
			_draw_loot(owner, int([0, 0, 1, 2, 3, 6][face - 1]))
			if face == 6:
				_discard_native_room24(resolving.source)
		"room_attack_choice24":
			_attack_prepared24 = true
			next_action = {"seat": owner, "kind": str(step.kind24), "arg": step.attack24}
		"room_bomb_cost24":
			var card: int = int(hands[owner].pop_at(int(step.item)))
			discards.loot.append(card)
			var bomb: bool = str(FSData.card(card).get("key", "")).contains("bomb")
			resolving["room_bombs24"] = 3 if bomb else 1
			_room_activations[owner] = int(_room_activations.get(owner, 0)) + 1
			_insert_card_steps([{"op": "auto_roll"}, {"op": "room_bomb_result24"}])
		"room_bomb_result24":
			var face: int = int(resolving.get("automation_roll", 1))
			var steps: Array = [{"op": "damage", "targets": "damage_targets"}] if face <= 4 else [{"op": "damage", "target": owner}]
			resolving["room_bombs24"] = int(resolving.get("room_bombs24", 1)) - 1
			resolving.erase("automation_roll")
			if int(resolving.room_bombs24) > 0:
				steps.append_array([{"op": "auto_roll"}, {"op": "room_bomb_result24"}])
			_insert_card_steps(steps)
		_:
			super._apply_card_step(step)

func _prepare_attack24(seat: int) -> bool:
	if _attack_prepared24:
		_attack_prepared24 = false
		return false
	if not _card_automation_enabled() or not _room_has20(767):
		return false
	_begin_resolving({"kind": "item", "card": 767, "owner": seat, "conditional": true, "automation_context": "attack24", "_resume": "turn"})
	_advance_card_automation()
	return true

func _intercept_roll12(effect: Dictionary, attack_roll: bool) -> bool:
	if super._intercept_roll12(effect, attack_roll):
		return true
	if not _card_automation_enabled() or not _room_has20(768) or bool(effect.get("room_checked24", false)) or effect.has("reroll_index") or int(effect.value) not in [1, 6]:
		return false
	effect["room_checked24"] = true
	var token := _roll_token(effect)
	stack.append(effect)
	_begin_resolving({"kind": "item", "card": 768, "owner": int(effect.owner), "conditional": true, "automation_context": "roll24", "automation_data": {"token": token}})
	return true

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	if event == "attack_declared" and _room_has20(754):
		for seat in players.size():
			if seat != current and not dead[seat] and seat not in _coop_partners20:
				_coop_partners20.append(seat)
	if event == "attack_start" and bool(data.get("from_deck24", false)) and _room_has20(763):
		_queue_packet15(current, 763, {}, "room_blind24")
	if event == "monster_death" and _room_has20(756):
		_queue_passive(current, 756, {}, [PassiveRules.operation("coins", int(data.get("max_hp24", 0)))])
	if event == "object_damage20" and int(data.get("card", -1)) == 757 and str(data.get("zone", "")) == "native_room24" and battle >= 0:
		_queue_packet15(current, 757, monsters[battle].virtual_ref15, "room_hit24", data)
	if event == "turn_start":
		if _room_has20(773):
			_queue_packet15(current, 773, {}, event, data)
		for index in range(-1, _extra_rooms20.size()):
			var source := _native_room_source24(index)
			if int(source.get("id", -1)) == 758:
				source["counters"] = int(source.get("counters", 0)) + 1
			if int(source.get("id", -1)) in [757, 778]:
				source.erase("familiar_hp15")

func _refresh_passive_stats() -> void:
	super._refresh_passive_stats()
	if not _card_automation_enabled() or _setting_up:
		return
	for index in range(-1, _extra_rooms20.size()):
		var source := _native_room_source24(index)
		if source.is_empty() or bool(source.get("entered24", false)):
			continue
		source["entered24"] = true
		if int(source.id) == 755 and 690 not in bonuses and 690 not in claimed:
			bonuses.append(690)
		if int(source.id) == 758:
			for count in 2:
				shop.append(_draw("treasure"))

func _room_can_discard() -> bool:
	return (room != 758 or not shop.any(func(id): return int(id) >= 0)) and super._room_can_discard()

func _replace_room20(index: int) -> bool:
	var source := _native_room_source24(index)
	if int(source.get("id", -1)) == 758 and shop.any(func(id): return int(id) >= 0):
		return false
	var replaced := super._replace_room20(index)
	if replaced and int(source.get("id", -1)) == 758:
		_refill_shop24()
	return replaced

func _discard_native_room24(source: Dictionary, keep: bool = false) -> void:
	if is_same(source, _native_room_source24(-1)) and room >= 0:
		if not keep:
			discards.room.append(room)
		room = _draw("room")
		_primary_room24 = {}
		if room == 810:
			_reset_room_goals()
	else:
		for index in _extra_rooms20.size():
			if is_same(_extra_rooms20[index], source):
				if keep:
					var replacement := _draw("room")
					if replacement >= 0:
						_extra_rooms20[index] = {"id": replacement}
					else:
						_extra_rooms20.remove_at(index)
				else:
					_replace_room20(index)
				break
	_refresh_passive_stats()

func _replace_monster_death(slot: int) -> bool:
	var entry: Dictionary = monsters[slot]
	if str(entry.get("virtual_zone15", "")) == "native_room24":
		var source: Dictionary = entry.virtual_ref15
		var id: int = int(entry.id)
		var quantity: int = reward_boost * (2 if _room_has20(774) else 1)
		monsters.remove_at(slot)
		_end_battle()
		_discard_native_room24(source, id == 778)
		if id == 778:
			for seat in players.size():
				_give_treasures21(seat, quantity)
			_gain_soul_card(current, {"id": id, "value": 1})
		else:
			_give_treasures21(current, quantity)
		return true
	return super._replace_monster_death(slot)

func _monster_evasion(entry: Dictionary) -> int:
	return int(entry.dc) if str(entry.get("virtual_zone15", "")) == "native_room24" else super._monster_evasion(entry)

func _monster_attack(entry: Dictionary) -> int:
	return 1 if str(entry.get("virtual_zone15", "")) == "native_room24" else super._monster_attack(entry)

func _after_auto_reward16(effect: Dictionary) -> void:
	super._after_auto_reward16(effect)
	var owner: int = int(effect.get("team_reward24", -1))
	if owner >= 0:
		_award_partner24(effect, owner, 754)
	for partner in effect.get("sibling_reward26", []):
		_award_partner24(effect, int(partner), 863)

func _award_partner24(effect: Dictionary, owner: int, source_id: int) -> void:
	var printed: Dictionary = effect.get("auto_reward", {})
	var operations: Array = []
	for resource in ["coins", "loot", "treasure"]:
		var amount: int = int(effect.get("reward_roll", 0)) if str(printed.get("roll", "")) == resource else int(printed.get(resource, 0))
		amount *= reward_boost * int(effect.get("reward_multiplier", 1)) * (2 if _room_has20(774) else 1)
		if amount > 0:
			operations.append(PassiveRules.operation(resource, amount))
	if not operations.is_empty():
		_queue_passive(owner, source_id, {}, operations)
