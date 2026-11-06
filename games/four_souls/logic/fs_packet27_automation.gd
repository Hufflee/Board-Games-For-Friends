extends "res://games/four_souls/logic/fs_packet26_automation.gd"
## Последние стартовые предметы и их общие точки входа.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	match str(step.get("targets", "")):
		"gello_target27":
			if battle >= 0 and not monsters[battle].has("virtual_zone15") and int(monsters[battle].hp) > 0:
				out.append({"label": FSData.title(int(monsters[battle].id)), "arg": {"op": "gello_heal27", "item": battle}})
		"gello_damage27":
			for slot in monsters.size():
				if int(monsters[slot].hp) > 0 and not monsters[slot].has("virtual_zone15") and not is_same(monsters[slot], resolving.gello_source27):
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "monster_damage", "item": slot, "amount": int(step.amount)}})
		"bargain_accept27":
			out.append(_choice26("Получить 1¢", "bargain_answer27", "accept"))
			out.append(_choice26("Отказаться", "bargain_answer27", "decline"))
		"tar_modes27":
			out.append(_choice26("Предотвратить следующую 1 урона", "tar_mode27", "shield"))
			if stack.any(func(entry): return _can_copy_tar27(entry, owner)):
				out.append(_choice26("Скопировать чужую добычу", "tar_mode27", "copy"))
			for slot in monsters.size():
				if _can_discard_monster26(slot):
					out.append(_choice26("Сбросить неатакуемого монстра", "tar_mode27", "discard"))
					break
		"tar_cards27":
			for index in stack.size():
				if _can_copy_tar27(stack[index], owner):
					out.append({"label": FSData.title(int(stack[index].card)), "arg": {"op": "tar_copy27", "index": index}})
		"tar_monsters27":
			for slot in monsters.size():
				if _can_discard_monster26(slot):
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "discard_monster", "item": slot}})
		"squid_offer27":
			var source := _squid_target27()
			if _live_monster27(source):
				out.append(_choice26("Дать монстру +1 здоровье и +1 атаку", "squid_buff27", "accept"))
		"squid_accept27":
			out.append(_choice26("Объединиться для атаки", "squid_join27", "accept"))
			out.append(_choice26("Отказаться", "squid_join27", "decline"))
		"squid_items27":
			for slot in items[owner].size():
				if int(items[owner][slot].get("health_tokens15", 0)) == 0:
					out.append({"label": FSData.title(int(items[owner][slot].id)), "arg": {"op": "squid_token27", "item": slot}})
	if int(resolving.card) in CardAutomation.Packet27.ITEMS:
		return out.filter(func(choice): return _choice_target20(choice.arg, _card_choice_owner()))
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"gello_heal27":
			var source: Dictionary = monsters[int(step.item)]
			var healed: int = maxi(0, _monster_max15(source) - int(source.hp))
			source.hp = int(source.hp) + healed
			resolving["gello_source27"] = source
			var steps: Array = []
			if healed > 0:
				steps.append({"op": "monster_damage", "targets": "gello_damage27", "amount": healed})
			if owner != current:
				steps.append({"op": "pit_cancel25"})
			_insert_card_steps(steps)
		"bargain_start27":
			var steps: Array = []
			for offset in range(1, players.size()):
				steps.append({"op": "bargain_ask27", "seat": (owner + offset) % players.size()})
			steps.append({"op": "bargain_finish27"})
			_insert_card_steps(steps)
		"bargain_ask27":
			resolving["choice_owner"] = int(step.seat)
			_insert_card_steps([{"op": "bargain_answer27", "targets": "bargain_accept27"}])
		"bargain_answer27":
			var seat := _card_choice_owner()
			resolving.erase("choice_owner")
			if step.mode == "accept":
				resolving["bargain_count27"] = int(resolving.get("bargain_count27", 0)) + 1
				_gain_coins(seat, 1)
		"bargain_finish27":
			_gain_coins(owner, 1 + int(resolving.get("bargain_count27", 0)))
		"lemegeton_pending27":
			_lemegeton27[owner] = int(_lemegeton27.get(owner, 0)) + 1
		"revenant_flip27":
			var source: Dictionary = resolving.source
			if _source_item_in_play(source):
				_flip_revenant27(source, owner)
		"tar_mode27":
			match str(step.mode):
				"shield": damage_shields[owner] = int(damage_shields[owner]) + 1
				"copy": _insert_card_steps([{"op": "tar_copy27", "targets": "tar_cards27"}])
				"discard": _insert_card_steps([{"op": "discard_monster", "targets": "tar_monsters27"}])
		"tar_copy27":
			var id: int = int(stack[int(step.index)].card)
			_tar_copied27[id] = turn_serial
			_push({"kind": "loot", "card": id, "owner": owner, "loot_copy14": true}, "effect")
		"dna_result27":
			var source: Dictionary = resolving.source
			if not _source_item_in_play(source):
				return
			match int(resolving.automation_roll):
				1, 2:
					source.counters = 0
					source.erase("health_tokens15")
					source.erase("attack_tokens15")
				3, 4: source["health_tokens15"] = int(source.get("health_tokens15", 0)) + 1
				5, 6: source["attack_tokens15"] = int(source.get("attack_tokens15", 0)) + 1
			_refresh_passive_stats()
		"squid_buff27":
			var source := _squid_target27()
			if _live_monster27(source):
				source.hp = int(source.hp) + 1
				source.at = int(source.at) + 1
				source["temporary_hp15"] = int(source.get("temporary_hp15", 0)) + 1
				source["temporary_at"] = int(source.get("temporary_at", 0)) + 1
				source["squid_turn27"] = turn_serial
				_insert_card_steps([{"op": "squid_invite27", "targets": "other_players", "optional": true}])
		"squid_invite27":
			resolving["choice_owner"] = int(step.target)
			_insert_card_steps([{"op": "squid_join27", "targets": "squid_accept27"}])
		"squid_join27":
			var partner := _card_choice_owner()
			resolving.erase("choice_owner")
			if step.mode == "accept" and partner not in _coop_partners20 and not dead[partner] and int(hp[partner]) > 0:
				_coop_partners20.append(partner)
		"squid_token27":
			items[owner][int(step.item)]["health_tokens15"] = 1
			_refresh_passive_stats()
		_:
			super._apply_card_step(step)

func _live_monster27(source: Dictionary) -> bool:
	return int(source.get("hp", 0)) > 0 and monsters.any(func(entry): return is_same(entry, source))

func _squid_target27() -> Dictionary:
	if battle < 0 or int(monsters[battle].id) != int(resolving.automation_data.get("monster27", -1)):
		return {}
	return monsters[battle]

func _can_copy_tar27(entry: Dictionary, owner: int) -> bool:
	if entry.kind != "loot" or int(entry.owner) == owner or bool(entry.get("loot_copy14", false)):
		return false
	var id: int = int(entry.card)
	return int(_tar_copied27.get(id, -1)) != turn_serial and str(FSData.card(id).lua.get("type", "")) not in ["trinkets", "ambush"]

func _copy_loot14(seat: int, id: int) -> void:
	var count := stack.size()
	super._copy_loot14(seat, id)
	if stack.size() > count:
		_tar_copied27[id] = turn_serial

func _flip_revenant27(source: Dictionary, owner: int) -> void:
	if not bool(source.get("revenant27", false)):
		source["revenant27"] = true
		source.erase("familiar_hp15")
		return
	source.erase("revenant27")
	for entry: Dictionary in monsters:
		if is_same(entry.get("virtual_ref15", {}), source):
			_end_battle()
			if str(resolving.get("_resume", "")) == "battle_roll":
				resolving["_resume"] = "turn"
			break
	source.erase("familiar_hp15")
	_draw_loot(owner, 1)

func _familiar_targets15() -> Array:
	var out := super._familiar_targets15()
	if _card_automation_enabled():
		for seat in players.size():
			for index in items[seat].size():
				var source: Dictionary = items[seat][index]
				if int(source.id) == 897 and bool(source.get("revenant27", false)):
					out.append({"zone": "item", "seat": seat, "index": index, "card": 897})
	return out

func _monster_hp(id: int) -> int:
	return 2 if id == 897 else super._monster_hp(id)

func _replace_monster_death(slot: int) -> bool:
	var monster: Dictionary = monsters[slot]
	if _card_automation_enabled() and int(monster.id) == 897 and monster.has("virtual_ref15"):
		var source: Dictionary = monster.virtual_ref15
		var owner: int = int(monster.virtual_owner15)
		var roller: int = int(monster.get("slayer", current))
		_flip_revenant27(source, owner)
		_queue_passive(roller, 897, {}, [PassiveRules.operation("loot", 2 * reward_boost)])
		attack_left += 1
		attacked = false
		_after_stack = "turn"
		return true
	return super._replace_monster_death(slot)

func _apply_combat(effect: Dictionary) -> void:
	if _card_automation_enabled() and battle >= 0 and battle < monsters.size():
		var source: Dictionary = monsters[battle]
		if int(source.id) == int(effect.card):
			if int(source.get("squid_roll_turn27", -1)) != turn_serial:
				source["squid_roll_turn27"] = turn_serial
				source["squid_rollers27"] = []
			if int(effect.owner) not in source.squid_rollers27:
				source.squid_rollers27.append(int(effect.owner))
	super._apply_combat(effect)

func _draw_loot(seat: int, count: int, reason: String = "effect") -> void:
	var extra := _item_count(seat, 912) if _card_automation_enabled() and count > 0 and reason != "setup" else 0
	super._draw_loot(seat, count + extra, reason)

func _complete_turn_start() -> void:
	_tar_copied27.clear()
	if _card_automation_enabled() and _item_count(current, 912) > 0 and _item_count(current, 523) == 0:
		discards.loot.append_array(hands[current])
		hands[current].clear()
	super._complete_turn_start()

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	match event:
		"turn_start":
			for source: Dictionary in _ability_items20(current):
				if int(source.id) == 903:
					_queue_packet15(current, 903, source, event)
		"turn_end":
			var count: int = int(_lemegeton27.get(current, 0))
			_lemegeton27.erase(current)
			for index in count:
				_queue_packet15(current, 895, {}, event)
		"roll":
			if int(data.get("value", 0)) == 4:
				for seat in players.size():
					for source: Dictionary in _ability_items20(seat):
						if int(source.id) == 907 and bool(source.tapped):
							_queue_passive(seat, 907, source, [PassiveRules.operation("recharge")])
		"attack_start":
			if battle >= 0 and not monsters[battle].has("virtual_zone15"):
				for source: Dictionary in _ability_items20(current):
					if int(source.id) == 910:
						_queue_packet15(current, 910, source, event, {"monster27": int(monsters[battle].id)})
		"monster_death":
			var slot: int = int(data.get("slot27", -1))
			if slot >= 0:
				var source: Dictionary = monsters[slot]
				if int(source.get("squid_turn27", -1)) == turn_serial and int(source.get("squid_roll_turn27", -1)) == turn_serial:
					for seat in source.squid_rollers27:
						_queue_packet15(int(seat), 910, {}, "squid_reward27")
