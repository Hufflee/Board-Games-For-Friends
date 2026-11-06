extends "res://games/four_souls/logic/fs_packet27_automation.gd"
## Пакет 28: остаток стартовых предметов группы 27 — Бездна 891, Мёртвый груз 893,
## Классический кубик 899, Дубинка 905. Тексты — art/card_texts.json (сверены с изображениями).

## Дубинка без способностей: источник → место владельца; снимается в конце его хода.
func _ability_items20(owner: int) -> Array:
	var out := super._ability_items20(owner)
	if _card_automation_enabled():
		out = out.filter(func(entry): return not bool(entry.get("club_off28", false)))
	return out

func _activate_starter26(seat: int, source: Dictionary, mode: String) -> bool:
	var id: int = int(source.id)
	if _card_automation_enabled():
		match id:
			832:
				if discards.values().all(func(pile): return pile.is_empty()):
					return false
			865:
				if not items.any(func(row): return row.any(func(entry): return not bool(entry.eternal))):
					return false
			891:
				if not items[seat].any(func(entry): return not bool(entry.eternal)):
					return false
			893:
				if not stack.any(_dead_weight_can28):
					return false
			899:
				if not stack.any(func(entry): return str(entry.kind) in ["roll", "effect_roll"]):
					return false
			905:
				if bool(source.get("club_off28", false)):
					return false
				if mode == "club_cancel28":
					if bool(source.tapped) or not stack.any(_ibs_can_cancel26):
						return false
					if not super._activate_starter26(seat, source, mode):
						return false
					source.tapped = true
					return true
				if seat != current or not monsters.any(func(entry): return _can_discard_monster26(monsters.find(entry))):
					return false
	return super._activate_starter26(seat, source, mode)

## Срабатывающая способность монстра или невечного предмета (не персонажа, не комнаты, не проклятия).
func _dead_weight_can28(entry: Dictionary) -> bool:
	if str(entry.kind) not in ["passive", "item"]:
		return false
	if str(entry.kind) == "item" and not bool(entry.get("conditional", false)) and not entry.has("automation_context"):
		return false
	var kind: String = str(FSData.card(int(entry.get("card", -1))).get("kind", ""))
	return kind in ["monster", "treasure", "loot"] and not (kind == "loot" and str(entry.kind) != "passive")

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	match str(step.get("targets", "")):
		"abyss_items28":
			for index in items[owner].size():
				if not bool(items[owner][index].eternal):
					out.append({"label": "Уничтожить: " + FSData.title(int(items[owner][index].id)), "arg": {"op": "abyss_destroy28", "item": index}})
		"dead_weight28":
			for index in stack.size():
				if _dead_weight_can28(stack[index]):
					out.append({"label": "Отменить: " + FSData.title(int(stack[index].card)), "arg": {"op": "cancel_selected", "index": index}})
		"classic_rolls28":
			for index in stack.size():
				if str(stack[index].kind) in ["roll", "effect_roll"]:
					out.append({"label": "Бросок %s · %d" % [name_of(int(stack[index].owner)), int(stack[index].value)], "arg": {"op": "classic_pick28", "roll_index": index}})
		"classic_judges28":
			var roller: int = int(resolving.get("classic_roller28", owner))
			for seat in players.size():
				if seat != roller:
					out.append({"label": name_of(seat) + " выбирает результат", "arg": {"op": "classic_judge28", "target": seat}})
		"classic_faces28":
			var faces: Array = resolving.get("classic_faces28", [])
			for index in faces.size():
				out.append({"label": "Кубик %d · %d" % [index + 1, int(faces[index])], "arg": {"op": "classic_choose28", "item": index}})
		"club_monsters28":
			for slot in monsters.size():
				if _can_discard_monster26(slot):
					out.append({"label": "Под низ колоды: " + FSData.title(int(monsters[slot].id)), "arg": {"op": "club_bottom28", "item": slot}})
		"curse_decks28":
			for deck in ["loot", "treasure", "monster", "room"]:
				if decks.has(deck) and not decks[deck].is_empty():
					out.append({"label": "Сбросить верхнюю карту: " + str(DECK_NAMES28[deck]), "arg": {"op": "curse_mill28", "deck": deck}})
		"curse_discards28":
			for deck in ["loot", "treasure", "monster", "room"]:
				if discards.has(deck) and not discards[deck].is_empty():
					out.append({"label": "%s → на верх колоды: %s" % [FSData.title(int(discards[deck].back())), DECK_NAMES28[deck]], "arg": {"op": "curse_return28", "deck": deck, "card": int(discards[deck].back())}})
		"spindown_items28":
			for seat in players.size():
				for index in items[seat].size():
					if not bool(items[seat][index].eternal):
						out.append({"label": "%s · %s" % [name_of(seat), FSData.title(int(items[seat][index].id))], "arg": {"op": "spindown28", "seat28": seat, "item": index, "card": int(items[seat][index].id)}})
		"spindown_shop28":
			for slot in shop.size():
				if int(shop[slot]) >= 0:
					out.append({"label": "Украсть из магазина: " + FSData.title(int(shop[slot])), "arg": {"op": "take_shop", "target": _card_choice_owner(), "item": slot, "shop": true, "card": int(shop[slot])}})
		"loss_souls28":
			for index in soul_cards[owner].size():
				if _loss_eligible28(soul_cards[owner][index]):
					out.append({"label": "Уничтожить душу: " + FSData.title(int(soul_cards[owner][index].id)), "arg": {"op": "loss_soul28", "item": index}})
		"curse_pass28":
			for seat in players.size():
				if seat != owner:
					out.append({"label": "Отдать проклятие: " + name_of(seat), "arg": {"op": "curse_pass28", "target": seat}})
		"deeper_cards28":
			var seen := {}
			for id in discards.monster:
				if str(FSData.card(int(id)).get("kind", "")) == "monster" and not seen.has(int(id)):
					seen[int(id)] = true
					out.append({"label": "На верх колоды: " + FSData.title(int(id)), "arg": {"op": "deeper28", "card": int(id)}})
		"club_cancel28":
			for index in stack.size():
				if _ibs_can_cancel26(stack[index]):
					out.append({"label": "Отменить: " + FSData.title(int(stack[index].card)), "arg": {"op": "club_cancel28", "index": index}})
	# FAQ foursouls.net: нельзя выбрать мёртвого игрока целью урона (урон «всем» по-прежнему проходит).
	if _card_automation_enabled():
		out = out.filter(func(choice): return not (str(choice.arg.get("op", "")) == "damage" and choice.arg.has("target") and str(choice.arg.get("zone", "player")) == "player" and int(choice.arg.target) >= 0 and int(choice.arg.target) < players.size() and bool(dead[int(choice.arg.target)])))
		# FAQ: душа Потерянного прикреплена к персонажу — её нельзя украсть, сбросить или уничтожить.
		out = out.filter(func(choice): return not _attached_soul28(choice.arg))
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"abyss_destroy28":
			var index: int = int(step.item)
			if index < 0 or index >= items[owner].size() or bool(items[owner][index].eternal):
				return
			_destroy_item(owner, index)
			var source: Dictionary = resolving.get("source", {})
			if _source_item_in_play(source):
				source.counters = int(source.get("counters", 0)) + 1
			_refresh_passive_stats()
		"classic_pick28":
			var index: int = int(step.roll_index)
			if index < 0 or index >= stack.size() or str(stack[index].kind) not in ["roll", "effect_roll"]:
				resolving.automation_step = resolving.automation_steps.size()
				return
			var roll: Dictionary = stack[index]
			resolving["classic_token28"] = _roll_token(roll)
			resolving["classic_roller28"] = int(roll.owner)
			resolving["classic_bonus28"] = int(roll.get("multi_bonus12", 0))
			resolving["classic_faces28"] = []
			resolving["choice_owner"] = int(roll.owner)
		"classic_collect28":
			(resolving.classic_faces28 as Array).append(int(resolving.get("automation_roll", 1)))
			resolving.erase("automation_roll")
		"classic_judge28":
			resolving["choice_owner"] = int(step.target)
		"classic_choose28":
			var faces: Array = resolving.get("classic_faces28", [])
			var face: int = int(faces[int(step.item)]) + int(resolving.get("classic_bonus28", 0))
			_change_pending12(int(resolving.classic_token28), clampi(face, 1, 6), false)
			_note("Классический кубик: выбран результат %d" % clampi(face, 1, 6))
			resolving.erase("choice_owner")
		"club_bottom28":
			var slot: int = int(step.item)
			if slot < 0 or slot >= monsters.size() or not _can_discard_monster26(slot):
				return
			var removed: Dictionary = monsters[slot]
			_eggs_monsters.erase(int(removed.id))
			_put_monster20(removed, "bottom")
			if removed.has("under"):
				monsters[slot] = removed.under
			else:
				monsters.remove_at(slot)
				if battle > slot:
					battle -= 1
				_fill_monster()
		"club_cancel28":
			var index: int = int(step.index)
			if index < 0 or index >= stack.size():
				return
			var canceled: Dictionary = stack.pop_at(index)
			_resolving_base = mini(_resolving_base, stack.size())
			if canceled.kind == "loot" and not bool(canceled.get("loot_copy14", false)):
				discards.loot.append(int(canceled.card))
			_note("Дубинка отменила: " + FSData.title(int(canceled.card)))
			var source: Dictionary = resolving.get("source", {})
			if _source_item_in_play(source):
				source["club_off28"] = true
				source["club_owner28"] = owner
		"rkey28":
			var source: Dictionary = resolving.get("source", {})
			var index: int = items[owner].find(source)
			if index < 0 or bool(source.eternal):
				return
			_destroy_item(owner, index)
			if _source_item_in_play(source):
				return
			for seat in players.size():
				for at in range(soul_cards[seat].size() - 1, -1, -1):
					if _loss_eligible28(soul_cards[seat][at]):
						_destroy_soul28(seat, at)
			for seat in players.size():
				discards.loot.append_array(hands[seat])
				hands[seat].clear()
				_draw_loot(seat, 3)
			_note("Клавиша R: все души уничтожены, у всех новая рука из 3 добычи")
		"curse_mill28":
			var deck: String = str(step.deck)
			if decks.has(deck) and not decks[deck].is_empty():
				var id: int = int(decks[deck].pop_back())
				discards[deck].append(id)
				_note("Проклятие: верхняя карта колоды в сброс — " + FSData.title(id))
		"curse_return28":
			var deck: String = str(step.deck)
			if discards.has(deck) and not discards[deck].is_empty() and int(discards[deck].back()) == int(step.card):
				decks[deck].append(int(discards[deck].pop_back()))
				_note("Проклятие: %s возвращена на верх колоды" % FSData.title(int(step.card)))
		"spindown28":
			var seat: int = int(step.seat28)
			var index: int = int(step.item)
			if seat < 0 or seat >= players.size() or index < 0 or index >= items[seat].size() or bool(items[seat][index].eternal):
				resolving.automation_step = resolving.automation_steps.size()
				return
			var victim: Dictionary = items[seat][index]
			_destroy_item(seat, index)
			if _source_item_in_play(victim):
				resolving.automation_step = resolving.automation_steps.size()
				return
			resolving["choice_owner"] = seat
		"spindown_recharge28":
			var source: Dictionary = resolving.get("source", {})
			if int(resolving.get("automation_roll", 0)) >= 4 and _source_item_in_play(source):
				source.tapped = false
				_note("Кубик-счётчик перезаряжен")
		"loss_soul28":
			var index: int = int(step.item)
			if index >= 0 and index < soul_cards[owner].size() and _loss_eligible28(soul_cards[owner][index]):
				var title := FSData.title(int(soul_cards[owner][index].id))
				_destroy_soul28(owner, index)
				_note("Проклятие потери: %s теряет душу %s" % [name_of(owner), title])
		"curse_pass28":
			if curses[owner].has(744):
				curses[owner].erase(744)
				curses[int(step.target)].append(744)
				_note("Проклятие бездушия переходит к " + name_of(int(step.target)))
		"deeper_attack28":
			attack_left += 1
			attacked = false
		"deeper28":
			var id: int = int(step.card)
			if discards.monster.has(id):
				discards.monster.erase(id)
				decks.monster.append(id)
				_note("На верх колоды монстров: " + FSData.title(id))
				_insert_card_steps([{"op": "deeper28", "targets": "deeper_cards28", "optional": true}])
		_:
			if str(step.op) == "take_shop":
				resolving.erase("choice_owner")
			super._apply_card_step(step)

const DECK_NAMES28 := {"loot": "добыча", "treasure": "сокровища", "monster": "монстры", "room": "комнаты"}

func _attached_soul28(arg: Dictionary) -> bool:
	if not str(arg.get("op", "")).contains("soul") or not arg.has("target") or not arg.has("item"):
		return false
	var seat: int = int(arg.target)
	var index: int = int(arg.item)
	if seat < 0 or seat >= players.size() or index < 0 or index >= soul_cards[seat].size():
		return false
	return not _loss_eligible28(soul_cards[seat][index])

func _loss_eligible28(entry: Dictionary) -> bool:
	return not bool(entry.get("character_soul26", false)) and str(FSData.card(int(entry.id)).get("kind", "")) != "character"

## Уничтоженная душа уходит в сброс своей колоды; бонусная душа выходит из игры (FAQ).
func _destroy_soul28(seat: int, index: int) -> void:
	var lost: Dictionary = soul_cards[seat].pop_at(index)
	souls[seat] = maxi(0, int(souls[seat]) - int(lost.get("value", 1)))
	var pile: String = {"monster": "monster", "loot": "loot", "treasure": "treasure", "room": "room"}.get(str(FSData.card(int(lost.id)).get("kind", "")), "")
	if not pile.is_empty():
		discards[pile].append(int(lost.id))

## Терпилу (88) можно атаковать: здоровье 2, защита 5+, атака 1, награда 5¢ активному игроку.
func _familiar_targets15() -> Array:
	var out := super._familiar_targets15()
	if _card_automation_enabled():
		for seat in players.size():
			for index in items[seat].size():
				if int(items[seat][index].id) == 88:
					out.append({"zone": "item", "seat": seat, "index": index, "card": 88})
	return out

func _monster_hp(id: int) -> int:
	return 2 if id == 88 else super._monster_hp(id)

func _replace_monster_death(slot: int) -> bool:
	var monster: Dictionary = monsters[slot]
	if _card_automation_enabled() and int(monster.id) == 88 and monster.has("virtual_ref15"):
		var source: Dictionary = monster.virtual_ref15
		monsters.remove_at(slot)
		_end_battle()
		source.erase("familiar_hp15")
		_queue_passive(current, 88, {}, [PassiveRules.operation("coins", 5 * reward_boost)])
		return true
	return super._replace_monster_death(slot)

## Пассив, поставленный сразу после завершения эффекта (фаза ещё effect, resolving уже пуст —
## например награда напарнику 754/863 после награды монстра), продолжает прежний ход партии,
## а не «effect»: иначе после него стол оставался в фазе effect без эффекта (фазз seed 281128).
func _queue_passive(seat: int, id: int, source: Dictionary, operations: Array) -> void:
	if phase == "effect" and resolving.is_empty():
		_push({"kind": "passive", "card": id, "owner": seat, "source": source, "operations": operations}, _after_stack)
		return
	super._queue_passive(seat, id, source, operations)

## Во время своего хода награды монстров-не-боссов удвоены (каждая Дубинка — ×2).
func _begin_resolving(effect: Dictionary) -> void:
	if _card_automation_enabled() and str(effect.get("kind", "")) == "reward" and effect.has("auto_reward") and not bool(effect.get("club28", false)):
		effect["club28"] = true
		var monster_type: String = str(FSData.card(int(effect.get("card", -1))).get("lua", {}).get("type", ""))
		var clubs: int = _item_count(current, 905) if current >= 0 and current < players.size() else 0
		if monster_type != "boss" and clubs > 0:
			effect["reward_multiplier"] = int(effect.get("reward_multiplier", 1)) * int(pow(2, clubs))
	super._begin_resolving(effect)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	match event:
		"roll":
			if int(data.get("value", 0)) == 3 and not monsters.is_empty():
				for seat in players.size():
					for source: Dictionary in _ability_items20(seat):
						if int(source.id) == 65:
							_queue_packet15(seat, 65, source, "roll28")
		"turn_start":
			for source: Dictionary in _ability_items20(current):
				if int(source.id) == 832 and decks.values().any(func(pile): return not pile.is_empty()):
					_queue_packet15(current, 832, source, "turn_start")
		"turn_end":
			for source: Dictionary in _ability_items20(current):
				if int(source.id) == 865:
					_queue_packet15(current, 865, source, "turn_end")
	if event == "turn_end":
		_pre_lethal_hp.clear()
		for inventory: Array in items:
			for source: Dictionary in inventory:
				if bool(source.get("club_off28", false)) and int(source.get("club_owner28", -1)) == current:
					source.erase("club_off28")
					source.erase("club_owner28")
