extends "res://games/four_souls/logic/fs_wildcard20_automation.gd"
## Лут468: дополнительные комнаты — физические карты без владельца и зоны предметов.
func _card_choices() -> Array:
	var out := super._card_choices()
	if str(_card_step().get("targets", "")) == "room_items20":
		for owner in players.size():
			for index in items[owner].size():
				var source: Dictionary = items[owner][index]
				if not bool(source.eternal) and not _protected20(owner, int(resolving.owner)):
					out.append({"label": name_of(owner) + " · " + FSData.title(int(source.id)), "arg": {"op": "make_room20", "target": owner, "item": index}})
		for index in shop.size():
			var id: int = int(shop[index])
			if id >= 0 and not bool(_eternal_shop15.get(id, false)):
				out.append({"label": "Магазин · " + FSData.title(id), "arg": {"op": "make_room20", "item": index, "shop": true}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var source: Dictionary = resolving.get("source", {})
	if str(step.op) == "make_room20":
		var saved_hp := hp.duplicate()
		if bool(step.get("shop", false)):
			var id: int = int(shop[int(step.item)])
			source = FSData.item_entry(id)
			if id == 5:
				source.counters = int(_shop_counters20.get(id, 3))
			_shop_counters20.erase(id)
			shop[int(step.item)] = _draw("treasure")
		else:
			source = _remove_item(int(step.target), int(step.item))
		source["room_item20"] = true
		_extra_rooms20.append(source)
		_refresh_passive_stats()
		for owner in players.size():
			hp[owner] = mini(int(max_hp[owner]), int(saved_hp[owner]))
		_note("Новая комната: " + FSData.title(int(source.id)))
	elif str(step.op) == "destroy_self" and bool(source.get("room_item20", false)):
		if not _destroy_room20(source, int(resolving.owner)):
			resolving.automation_step = resolving.automation_steps.size()
	else:
		super._apply_card_step(step)

func _ability_items20(owner: int) -> Array:
	var out: Array = items[owner].duplicate()
	if _card_automation_enabled() and owner == current:
		out.append_array(_extra_rooms20.filter(func(entry): return bool(entry.get("room_item20", false))))
	return out

func _activation_source20(owner: int, arg: Dictionary, room_source: bool = false) -> Dictionary:
	var index: int = int(arg.get("item", -1))
	if room_source:
		if owner != current or index < 0 or index >= _extra_rooms20.size() or not bool(_extra_rooms20[index].get("room_item20", false)):
			return {}
		return _extra_rooms20[index]
	return super._activation_source20(owner, arg)

func _source_item_in_play(source: Dictionary) -> bool:
	return _extra_rooms20.any(func(entry): return is_same(entry, source)) or super._source_item_in_play(source)

func _native_rooms20() -> Array:
	var out: Array = [room] if room >= 0 else []
	for source: Dictionary in _extra_rooms20:
		if not bool(source.get("room_item20", false)):
			out.append(int(source.id))
	return out

func _room_has20(id: int) -> bool:
	return id in _native_rooms20()

func _refresh_passive_stats() -> void:
	if hp.is_empty():
		return
	var saved_hp := hp.duplicate()
	for owner in players.size():
		var old: Vector2i = _converted_room_bonuses20.get(owner, Vector2i.ZERO)
		attack[owner] = maxi(0, int(attack[owner]) - old.x)
		max_hp[owner] = maxi(1, int(max_hp[owner]) - old.y)
	_converted_room_bonuses20.clear()
	super._refresh_passive_stats()
	if current >= 0 and current < players.size():
		var total := Vector2i.ZERO
		var cubes := _meat_count20(current)
		for source: Dictionary in _extra_rooms20:
			if bool(source.get("room_item20", false)):
				total += PassiveRules.stat_bonus(int(source.id), source, hands[current].size(), cubes)
				total.y += int(source.get("health_tokens15", 0))
		attack[current] = maxi(0, int(attack[current]) + total.x)
		max_hp[current] = maxi(1, int(max_hp[current]) + total.y)
		_converted_room_bonuses20[current] = total
	for owner in players.size():
		hp[owner] = mini(int(max_hp[owner]), int(saved_hp[owner]))

func _destroy_room20(source: Dictionary, owner: int, soul: bool = false) -> bool:
	var index := _extra_rooms20.find(source)
	if index < 0 or bool(source.get("eternal", false)):
		return false
	if int(source.id) == 518 and int(source.counters) == 0 and not soul:
		source.counters = 1
		return false
	var copied_id: int = int(source.id)
	_release_stored20(source)
	var physical: int = int(source.get("physical_id13", source.id))
	var fresh := _draw("room")
	if fresh >= 0:
		_extra_rooms20[index] = {"id": fresh}
		if fresh == 810:
			_reset_room_goals()
	else:
		_extra_rooms20.remove_at(index)
	if soul or copied_id == 243:
		_gain_soul_card(owner, {"id": physical, "value": 1})
	else:
		_discard_item(physical)
		if copied_id == 3:
			_draw_loot(current, 1)
		if copied_id == 505:
			_queue_passive(owner, copied_id, source, [PassiveRules.operation("treasure")])
		if copied_id in [474, 87]:
			_queue_passive(owner, copied_id, source, [{"op": "trinket_automation", "amount": 1, "context": "destroyed", "data": {"counters": int(source.counters)}}])
	_refresh_passive_stats()
	return true

func _familiar_targets15() -> Array:
	var out := super._familiar_targets15()
	for index in _extra_rooms20.size():
		var source: Dictionary = _extra_rooms20[index]
		if bool(source.get("room_item20", false)) and int(source.id) in [3, 275] and int(source.get("familiar_hp15", _monster_hp(int(source.id)))) > 0:
			out.append({"zone": "room20", "seat": -1, "index": index, "card": int(source.id)})
	return out

func _replace_monster_death(slot: int) -> bool:
	var monster: Dictionary = monsters[slot]
	if str(monster.get("virtual_zone15", "")) == "room20":
		var source: Dictionary = monster.virtual_ref15
		monsters.remove_at(slot)
		_end_battle()
		_destroy_room20(source, current)
		return true
	return super._replace_monster_death(slot)

func _replace_room20(index: int) -> bool:
	if index < 0:
		return false
	if index >= _extra_rooms20.size():
		return false
	var source: Dictionary = _extra_rooms20[index]
	if int(source.id) == 810 and not _goals_rewarded:
		return false
	_release_stored20(source)
	var id: int = int(source.get("physical_id13", source.id))
	discards[_stored_pile20(id)].append(id)
	var fresh := _draw("room")
	if fresh >= 0:
		_extra_rooms20[index] = {"id": fresh}
		if fresh == 810:
			_reset_room_goals()
	else:
		_extra_rooms20.remove_at(index)
	_note("Комната заменена")
	return true
