extends "res://games/four_souls/logic/fs_prototype20_automation.gd"
## Кооперативный Малыш: настоящий фамильяр и выбранные напарники против любого объекта.
func _apply_card_step(step: Dictionary) -> void:
	match str(step.op):
		"coop_partner20":
			if int(step.target) not in _coop_partners20:
				_coop_partners20.append(int(step.target))
		"familiar_reward20":
			_draw_loot(current, reward_boost)
		_:
			super._apply_card_step(step)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	if event == "attack_declared" and int(data.get("seat", -1)) == current:
		_coop_partners20.clear()
		for source: Dictionary in _ability_items20(current).duplicate():
			if int(source.id) == 3:
				_queue_packet15(current, 3, source, event, data)

func _team_after_combat15(roller: int) -> void:
	if not _card_automation_enabled() or _coop_partners20.is_empty():
		super._team_after_combat15(roller)
		return
	if battle_player >= 0 or (battle >= 0 and battle < monsters.size() and int(monsters[battle].id) not in [266, 335, 339]):
		if battle >= 0:
			_team_source15 = monsters[battle]
		if roller == current:
			_team_queue15 = _coop_partners20.duplicate()
		elif not _team_queue15.is_empty() and int(_team_queue15[0]) == roller:
			_team_queue15.pop_front()
	else:
		super._team_after_combat15(roller)
		if roller == current:
			for seat in _coop_partners20:
				if int(seat) not in _team_queue15:
					_team_queue15.append(int(seat))
	_team_queue15.sort_custom(func(left, right): return posmod(int(left) - current, players.size()) < posmod(int(right) - current, players.size()))

func _battle_roller15() -> int:
	if _card_automation_enabled() and battle_player >= 0 and not _coop_partners20.is_empty():
		while not _team_queue15.is_empty() and (dead[int(_team_queue15[0])] or int(hp[int(_team_queue15[0])]) <= 0):
			_team_queue15.pop_front()
		return int(_team_queue15[0]) if not _team_queue15.is_empty() else current
	return super._battle_roller15()

func _end_battle() -> void:
	super._end_battle()
	_coop_partners20.clear()

func _familiar_targets15() -> Array:
	var out := super._familiar_targets15()
	if _card_automation_enabled():
		for owner in players.size():
			for index in items[owner].size():
				if int(items[owner][index].id) == 3 and int(items[owner][index].get("familiar_hp15", 2)) > 0:
					out.append({"zone": "item", "seat": owner, "index": index, "card": 3})
	return out

func _replace_monster_death(slot: int) -> bool:
	var monster: Dictionary = monsters[slot]
	if _card_automation_enabled() and int(monster.id) == 3 and monster.has("virtual_ref15"):
		var source: Dictionary = monster.virtual_ref15
		for owner in players.size():
			for index in items[owner].size():
				if is_same(items[owner][index], source):
					if not bool(source.eternal):
						_destroy_item(owner, index)
					else:
						source["familiar_hp15"] = 0
		if monsters.any(func(entry): return is_same(entry, monster)):
			monsters.erase(monster)
			_end_battle()
		return true
	return super._replace_monster_death(slot)

func _destroy_item(seat: int, index: int) -> void:
	var source: Dictionary = items[seat][index]
	var familiar: bool = int(source.id) == 3
	super._destroy_item(seat, index)
	if _card_automation_enabled() and familiar and not _source_item_in_play(source):
		for slot in range(monsters.size() - 1, -1, -1):
			if is_same(monsters[slot].get("virtual_ref15", {}), source):
				monsters.remove_at(slot)
				if slot == battle:
					_end_battle()
				elif battle > slot:
					battle -= 1
		_queue_packet15(current, 3, {}, "destroyed20")

func _monster_hp(id: int) -> int:
	return 2 if _card_automation_enabled() and id == 3 else super._monster_hp(id)

func _monster_evasion(monster: Dictionary) -> int:
	if _card_automation_enabled() and int(monster.id) == 3 and monster.has("virtual_ref15"):
		return maxi(1, int(monster.dc))
	return super._monster_evasion(monster)

func _monster_attack(monster: Dictionary) -> int:
	if _card_automation_enabled() and int(monster.id) == 3 and monster.has("virtual_ref15"):
		return maxi(0, int(monster.at))
	return super._monster_attack(monster)
