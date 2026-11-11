extends "res://games/four_souls/logic/fs_encounter_automation.gd"
## Сокровища124–163: выбор владельца, подарки, замены бросков и автоматические пассивы.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	var chooser := _card_choice_owner()
	match str(step.get("targets", "")):
		"fixed_roll_faces":
			for index in stack.size():
				if stack[index].kind in ["roll", "effect_roll"]:
					for face in ([3] if int(resolving.card) == 126 else [1, 6]):
						out.append({"label": "%s · результат %d" % [name_of(int(stack[index].owner)), face], "arg": {"op": "set_roll12", "index": index, "face": face}})
		"cost_hand12":
			for index in hands[owner].size():
				out.append({"label": "Оплатить: " + FSData.title(int(hands[owner][index])), "arg": {"op": "cost_loot12", "item": index, "card": int(hands[owner][index])}})
		"wiz_targets":
			var data: Dictionary = resolving.automation_data
			for seat in active_seats():
				if str(data.get("damaged_zone", "")) != "player" or seat != int(data.get("damaged", -1)):
					out.append({"label": name_of(seat), "arg": {"op": "damage", "target": seat}})
			for slot in monsters.size():
				if str(data.get("damaged_zone", "")) != "monster" or int(monsters[slot].id) != int(data.get("damaged", -1)):
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "monster_damage", "item": slot}})
		"phd_adjustments":
			for amount in [-1, 0, 1]:
				out.append({"label": "Результат %d (%+d)" % [clampi(int(resolving.automation_data.value) + amount, 1, 6), amount], "arg": {"op": "phd_adjust", "amount": amount}})
		"giver_hand12":
			for index in hands[chooser].size():
				out.append({"label": "Отдать: " + FSData.title(int(hands[chooser][index])), "arg": {"op": str(step.op), "item": index, "card": int(hands[chooser][index])}})
		"giver_item12":
			for index in items[chooser].size():
				if not bool(items[chooser][index].eternal):
					out.append({"label": "Отдать: " + FSData.title(int(items[chooser][index].id)), "arg": {"op": "divorce_item", "item": index, "card": int(items[chooser][index].id)}})
		"own_souls12":
			for index in soul_cards[chooser].size():
				if FSData.card(int(soul_cards[chooser][index].id)).get("kind", "") != "character":
					out.append({"label": "Уничтожить: " + FSData.title(int(soul_cards[chooser][index].id)), "arg": {"op": "destroy_soul12", "item": index, "target": chooser, "card": int(soul_cards[chooser][index].id)}})
		"bug_items":
			var target: int = int(resolving.automation_data.seat)
			for index in items[target].size():
				if not bool(items[target][index].eternal):
					out.append({"label": FSData.title(int(items[target][index].id)), "arg": {"op": "reroll_item", "target": target, "item": index, "shop": false}})
		"candle_faces":
			for face in range(1, 7):
				out.append({"label": "Выбрать число %d" % face, "arg": {"op": "candle_face", "face": face}})
		"declared_monsters":
			var index := _pending_attack12(int(resolving.automation_data.token))
			if index >= 0:
				for slot in monsters.size():
					if int(monsters[slot].hp) > 0 and not _untargetable(int(monsters[slot].id)):
						out.append({"label": "Атаковать: " + FSData.title(int(monsters[slot].id)), "arg": {"op": "redirect_attack", "item": slot, "token": int(resolving.automation_data.token)}})
		"multi_faces12":
			for index in resolving.multi_faces.size():
				out.append({"label": "Кубик %d · %d" % [index + 1, int(resolving.multi_faces[index])], "arg": {"op": "multi_choose", "index": index}})
		"rainbow_modes":
			for mode in ["loot", "coins", "damage"]:
				out.append({"label": {"loot": "Каждый берёт 1 добычу", "coins": "Каждый получает 2¢", "damage": "Каждый получает 1 урона"}[mode], "arg": {"op": "rainbow_mode", "mode": mode}})
		"telepathy_options":
			out.append({"label": "Изменить результат на %d" % int(resolving.automation_data.face), "arg": {"op": "telepathy_use"}})
			out.append({"label": "Оставить выпавший результат", "arg": {"op": "skip_choice"}})
		"fly_yes":
			out.append({"label": "Перезарядить Умную муху", "arg": {"op": "fly_recharge"}})
		"fly_top_options":
			for mode in ["keep", "discard"]:
				out.append({"label": "Оставить сверху" if mode == "keep" else "Положить в сброс", "arg": {"op": "fly_top", "mode": mode}})
		"revealed_curses12":
			for id in peek.get("cards", []):
				if str(FSData.card(int(id)).get("lua", {}).get("type", "")) == "curse":
					out.append({"label": "Передать: " + FSData.title(int(id)), "arg": {"op": "candle_curse", "card": int(id)}})
		"candle_bottom_cards":
			for id in peek.get("cards", []):
				out.append({"label": "Следующая снизу: " + FSData.title(int(id)), "arg": {"op": "candle_bottom", "card": int(id)}})
		"donation_items12", "other_items12":
			for seat in active_seats():
				if str(step.targets) == "donation_items12" and seat != owner:
					continue
				for index in items[seat].size():
					var item: Dictionary = items[seat][index]
					if resolving.has("source") and is_same(item, resolving.source):
						continue
					if str(step.targets) == "donation_items12" and bool(item.eternal):
						continue
					if str(step.targets) == "other_items12" and int(item.id) == 44:
						continue
					out.append({"label": name_of(seat) + " · " + FSData.title(int(item.id)), "arg": {"op": str(step.op), "target": seat, "item": index, "card": int(item.id)}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var chooser := _card_choice_owner()
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"abaddon_die":
			hp[owner] = 0
		"cost_loot12":
			discards.loot.append(int(hands[owner].pop_at(int(step.item))))
			resolving["cost_paid12"] = true
		"declare_paid12":
			if bool(resolving.get("cost_paid12", false)):
				var resume: String = str(resolving.get("_resume", "turn"))
				_push({"kind": "item", "card": int(resolving.card), "owner": owner, "source": resolving.source}, resume)
				_room_activations[owner] = int(_room_activations.get(owner, 0)) + 1
				_emit_passives("activate", {"seat": owner, "card": int(resolving.card)})
		"athame_discard":
			var target: int = int(step.target)
			if not hands[target].is_empty():
				_push({"kind": "forced_discard", "owner": owner, "target": target, "card": 125, "amount": 2}, "effect")
		"set_roll12":
			var index: int = int(step.index)
			stack[index].value = int(step.face)
			if stack[index].kind == "roll":
				stack[index]["final_value"] = int(step.face)
		"krampus_result":
			_insert_card_steps([{"op": "encounter_damage_all", "amount": 1}] if value <= 3 else [{"op": "damage_monsters"}])
		"phd_adjust":
			_change_pending12(int(resolving.automation_data.token), int(resolving.automation_data.value) + int(step.amount), false)
		"divorce_target":
			resolving["choice_owner"] = int(step.target)
		"divorce_halves":
			_transfer_coins(chooser, owner, floori(float(coins[chooser]) / 2.0))
			resolving["divorce_left"] = floori(float(hands[chooser].size()) / 2.0)
			if int(resolving.divorce_left) > 0:
				_insert_card_steps([{"op": "divorce_hand", "targets": "giver_hand12"}])
		"divorce_hand":
			hands[owner].append(int(hands[chooser].pop_at(int(step.item))))
			resolving.divorce_left = int(resolving.divorce_left) - 1
			if int(resolving.divorce_left) > 0:
				_insert_card_steps([{"op": "divorce_hand", "targets": "giver_hand12"}])
		"divorce_item":
			items[owner].append(_remove_item(chooser, int(step.item)))
			resolving.erase("choice_owner")
		"forget_souls":
			var steps: Array = []
			for offset in players.size():
				steps.append({"op": "soul_owner12", "target": (owner + offset) % players.size()})
				steps.append({"op": "destroy_soul12", "targets": "own_souls12"})
			steps.append({"op": "restore_choice12"})
			_insert_card_steps(steps)
		"soul_owner12":
			resolving["choice_owner"] = int(step.target)
		"destroy_soul12":
			_effect({"op": "destroy_soul", "target": int(step.target), "item": int(step.item)})
		"restore_choice12":
			resolving.erase("choice_owner")
		"candle_face":
			_red_candles.append({"owner": owner, "face": int(step.face), "turn": turn_serial})
		"haunt_give":
			for index in items[owner].size():
				if is_same(items[owner][index], resolving.source):
					items[int(step.target)].append(_remove_item(owner, index))
					break
		"redirect_attack":
			var index := _pending_attack12(int(step.token))
			if index >= 0:
				stack[index].slot = int(step.item)
		"multi_arm":
			_multi_owners.append(owner)
		"multi_prepare":
			resolving["multi_faces"] = [int(resolving.automation_data.first)]
			resolving["multi_controller"] = owner
			resolving.owner = int(resolving.automation_data.roller)
		"multi_collect":
			resolving.multi_faces.append(value)
			if resolving.multi_faces.size() < 4:
				resolving.erase("automation_roll")
				_insert_card_steps([{"op": "auto_roll"}, {"op": "multi_collect"}])
			else:
				resolving["choice_owner"] = int(resolving.multi_controller)
				_insert_card_steps([{"op": "multi_choose", "targets": "multi_faces12"}])
		"multi_choose":
			var face: int = clampi(int(resolving.multi_faces[int(step.index)]) + int(resolving.automation_data.get("bonus", 0)), 1, 6)
			if _era_left > 0:
				_era_left -= 1
				face = _era_face
			_change_pending12(int(resolving.automation_data.token), face, false)
			resolving.owner = int(resolving.multi_controller)
			resolving.erase("choice_owner")
		"one_up_save":
			hp[owner] = int(max_hp[owner])
			_death_queue.erase(owner)
			if battle >= 0 or battle_player >= 0:
				_end_battle()
			# 07.11: атака отменена — продолжаем обычный ход, а не прежний «бросок атаки» без боя.
			resolving["_resume"] = "turn"
			_after_stack = "turn"
			stack = stack.filter(func(e): return str(e.kind) not in ["attack", "player_attack"])
			attack_left += 1
			attacked = false
		"rainbow_mode":
			var steps: Array = []
			for offset in players.size():
				steps.append({"op": str(step.mode), "target": (owner + offset) % players.size(), "amount": 2 if str(step.mode) == "coins" else 1})
			_insert_card_steps(steps)
		"cement_result":
			if value <= 3:
				_insert_card_steps([{"op": "damage", "targets": "damage_targets"}])
		"admiration_target":
			resolving["choice_owner"] = int(step.target)
		"admiration_gift":
			var id: int = int(hands[chooser].pop_at(int(step.item)))
			hands[owner].append(id)
			resolving["gift_loot12"] = id
			resolving.erase("choice_owner")
			peek = {"owner": owner, "cards": [id], "public": true}
		"admiration_play":
			var id: int = int(resolving.get("gift_loot12", -1))
			if _can_play_gift12(owner, id):
				hands[owner].erase(id)
				_push({"kind": "loot", "owner": owner, "card": id}, "effect")
				_room_loot_plays[owner] = int(_room_loot_plays.get(owner, 0)) + 1
				_emit_passives("loot_play", {"seat": owner, "card": id})
		"telepathy_store":
			_telepathy_faces[owner] = {"face": value, "turn": turn_serial}
		"telepathy_use":
			_change_pending12(int(resolving.automation_data.token), int(resolving.automation_data.face), true)
		"fly_recharge":
			if _source_item_in_play(resolving.source):
				resolving.source.tapped = false
		"fly_top":
			if not peek.get("cards", []).is_empty() and str(step.mode) == "discard":
				var id: int = int(peek.cards[0])
				decks[str(peek.deck)].erase(id)
				discards[str(peek.deck)].append(id)
			peek = {}
		"candle_reveal":
			peek = {"owner": owner, "deck": "monster", "cards": decks.monster.slice(maxi(0, decks.monster.size() - 6)), "public": true}
		"candle_curse":
			resolving["candle_curse"] = int(step.card)
			_insert_card_steps([{"op": "candle_assign", "targets": "players"}, {"op": "candle_curse", "targets": "revealed_curses12", "optional": true}])
		"candle_assign":
			var id: int = int(resolving.candle_curse)
			decks.monster.erase(id)
			peek.cards.erase(id)
			curses[int(step.target)].append(id)
		"candle_bottom":
			decks.monster.erase(int(step.card))
			decks.monster.push_front(int(step.card))
			peek.cards.erase(int(step.card))
			if peek.cards.is_empty():
				peek = {}
			else:
				_insert_card_steps([{"op": "candle_bottom", "targets": "candle_bottom_cards"}])
		"euthanasia_kill":
			for monster: Dictionary in monsters:
				if int(monster.id) == int(resolving.automation_data.card):
					monster.hp = 0
					monster["slayer"] = owner
		"d100_result":
			if value <= 2:
				_insert_card_steps([{"op": "loot", "amount": value}])
			elif value <= 4:
				_insert_card_steps([{"op": "coins", "amount": value}])
			elif value == 5:
				_grant_temporary_health(owner, 1)
			else:
				_insert_card_steps([{"op": "temporary_attack"}])
		"d4_inventory":
			var target: int = int(step.target)
			var steps: Array = []
			# Фиксируем исходные физические карты; новые предметы в этот список не попадают.
			for item: Dictionary in items[target]:
				if not bool(item.eternal):
					steps.append({"op": "d4_one", "target": target, "card": int(item.id)})
			_insert_card_steps(steps)
		"d4_one":
			var target: int = int(step.target)
			for index in items[target].size():
				if int(items[target][index].id) == int(step.card) and not bool(items[target][index].eternal):
					_apply_card_step({"op": "reroll_item", "target": target, "item": index, "shop": false})
					break
		"donation_item":
			resolving["donation_id"] = int(step.card)
		"donation_give":
			for index in items[owner].size():
				if int(items[owner][index].id) == int(resolving.donation_id) and not bool(items[owner][index].eternal):
					items[int(step.target)].append(_remove_item(owner, index))
					resolving["cost_paid12"] = true
					break
		"boomerang_take":
			var target: int = int(step.target)
			if not hands[target].is_empty():
				hands[owner].append(int(hands[target].pop_at(_rng.randi_range(0, hands[target].size() - 1))))
		_:
			super._apply_card_step(step)

func _pending_attack12(token: int) -> int:
	for index in stack.size():
		if stack[index].kind == "attack" and int(stack[index].get("attack_token", -1)) == token:
			return index
	return -1

func _change_pending12(token: int, face: int, final: bool) -> void:
	for effect: Dictionary in stack:
		if effect.kind in ["roll", "effect_roll"] and _roll_token(effect) == token:
			effect.value = clampi(face, 1, 6)
			if final and effect.kind == "roll":
				effect["final_value"] = effect.value
			else:
				effect.erase("final_value")
			return

func _can_play_gift12(owner: int, id: int) -> bool:
	if id < 0 or id not in hands[owner] or dead[owner]:
		return false
	if owner != current and FSData.response_kind(id) == "own_turn":
		return false
	if _room_has20(814) and int(_room_loot_plays.get(owner, 0)) >= 1:
		return false
	if id == 469 and not stack.any(func(e): return e.kind == "loot"):
		return false
	if id == 470 and _card_automation_enabled() and not _can_guard21(owner, id):
		return false
	if (id in CardAutomation.REROLL_LOOT or id == 621) and not stack.any(func(e): return e.kind in ["roll", "effect_roll"]):
		return false
	if id in CardAutomation.CANCEL_LOOT and not stack.any(func(e): return e.kind == "loot" or (e.kind == "item" and not bool(e.get("conditional", false)) and not e.has("automation_context"))):
		return false
	return true

func _intercept_roll12(effect: Dictionary, attack_roll: bool) -> bool:
	if not _card_automation_enabled():
		return false
	var roller: int = int(effect.owner)
	var token := _roll_token(effect)
	var id := -1
	var owner := roller
	var context := ""
	var data := {"token": token, "value": int(effect.value)}
	if not bool(effect.get("multi_checked12", false)):
		effect["multi_checked12"] = true
		if not _multi_owners.is_empty():
			owner = int(_multi_owners.pop_front())
			id = 140
			context = "multi_roll"
			data = {"token": token, "roller": roller, "first": int(effect.value), "bonus": int(effect.get("multi_bonus12", 0))}
	if id < 0 and not attack_roll and not _rerolls_attack(effect) and not bool(effect.get("phd_checked12", false)):
		effect["phd_checked12"] = true
		if _item_count(roller, 132) > 0:
			id = 132
			context = "nonattack_roll"
	if id < 0 and not bool(effect.get("telepathy_checked12", false)):
		effect["telepathy_checked12"] = true
		if _telepathy_faces.has(roller):
			var stored: Dictionary = _telepathy_faces[roller]
			_telepathy_faces.erase(roller)
			if int(stored.turn) == turn_serial:
				id = 149
				context = "next_roll"
				data["face"] = int(stored.face)
	if id < 0:
		return false
	stack.append(effect)
	_begin_resolving({"kind": "item", "card": id, "owner": owner, "conditional": true, "automation_context": context, "automation_data": data})
	return true

func _treasure12_passives(event: String, data: Dictionary) -> void:
	if not _card_automation_enabled():
		return
	if event == "roll":
		for candle: Dictionary in _red_candles.duplicate():
			if int(candle.turn) == turn_serial and int(candle.face) == int(data.get("value", 0)):
				_queue_passive(int(candle.owner), 136, {}, [{"op": "trinket_automation", "amount": 1, "context": "candle_roll", "data": data.duplicate(true)}])
	var abaddon_queued := false
	for owner in players.size():
		for entry: Dictionary in _ability_items20(owner).duplicate():
			var id: int = int(entry.id)
			var triggered := false
			var details := data.duplicate(true)
			match id:
				124:
					# Смертельный урон уже объявляет смерть. Абаддон превращает в неё
					# только несмертельный удар, иначе одна защита расходуется дважды.
					triggered = not abaddon_queued and event == "damage" and int(data.get("seat", -1)) == owner and hp[owner] > 0
					abaddon_queued = abaddon_queued or triggered
				147, 150:
					triggered = event == "damage" and int(data.get("seat", -1)) == owner
				127:
					triggered = event == "combat_monster_damage" and int(data.get("seat", -1)) == owner
					if triggered:
						details.merge({"damaged_zone": "monster", "damaged": int(data.card)}, true)
					if event == "damage" and bool(data.get("combat", false)) and int(data.get("attacker", -1)) == owner:
						triggered = true
						details.merge({"damaged_zone": "player", "damaged": int(data.seat)}, true)
				130:
					triggered = (event == "monster_damage" and int(data.get("seat", -1)) == owner) or (event == "damage" and int(data.get("attacker", -1)) == owner) or (event == "death" and int(data.get("killer", -1)) == owner) or (event == "monster_death" and int(data.get("seat", -1)) == owner)
				131, 149:
					triggered = event == "turn_start" and owner == current
				135:
					triggered = event == "roll" and int(data.get("value", 0)) == 1
				138:
					triggered = event == "death" and int(data.get("seat", -1)) == owner
				139:
					triggered = event == "attack_declared" and int(data.get("seat", -1)) != owner and int(data.get("slot", -1)) >= 0
				141:
					triggered = event == "roll" and int(data.get("value", 0)) == 2
				144:
					triggered = event == "attack_roll" and int(data.get("seat", -1)) == owner and int(data.get("value", 0)) == 1
				146:
					triggered = event == "attack_miss" and int(data.get("seat", -1)) == owner
				152:
					if event == "attack_roll" and int(data.get("seat", -1)) == owner and current == owner:
						triggered = int(entry.get("last_turn12", -1)) == turn_serial and int(entry.get("last_face12", -1)) == int(data.value) and battle >= 0
						entry["last_turn12"] = turn_serial
						entry["last_face12"] = int(data.value)
						if triggered:
							details["card"] = int(monsters[battle].id)
				153:
					triggered = event == "roll" and int(data.get("value", 0)) == 3
			if triggered:
				_queue_passive(owner, id, entry, [{"op": "trinket_automation", "amount": 1, "context": event, "data": details}])
