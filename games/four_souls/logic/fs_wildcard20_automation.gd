extends "res://games/four_souls/logic/fs_storage20_automation.gd"
## Физическая карта Засады отделена от скопированного текста монстра.
func _card_choices() -> Array:
	var out := super._card_choices()
	var category: String = str(_card_step().get("targets", ""))
	if category == "ambush_slots20":
		for slot in mini(maxi(monster_slots, monsters.size()), monsters.size() + 1):
			if slot != battle and (slot >= monsters.size() or int(monsters[slot].id) not in [272, 279, 299, 312, 913, 914]):
				out.append({"label": "Слот монстров %d" % (slot + 1), "arg": {"op": "ambush_place20", "item": slot}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	match str(step.op):
		"ambush_place20":
			resolving["deployed_monster20"] = true
			_place_encounter_monster(467, int(step.item))
			_forced_monsters14.append(467)
			attack_left += 1
			attacked = false
		"ambush_copy20":
			var source: Dictionary = resolving.source
			if decks.monster.is_empty() or not monsters.any(func(entry): return is_same(entry, source)):
				return
			var id: int = int(decks.monster.back())
			var damage := maxi(0, _monster_max15(source) - int(source.hp))
			source["physical_id20"] = 467
			source["ambush_return20"] = true
			source.id = id
			if FSData.card(id).get("kind", "") == "event":
				# Копирование не является входом события в игру: его входные способности не повторяются.
				source["ambush_event20"] = true
				source.hp = 1
				source.dc = 99
				source.at = 0
				_end_battle()
			else:
				source.hp = maxi(0, _monster_max15(source) - damage)
				source.dc = FSData.stat(id, "dc", 4) + int(source.get("temporary_dc", 0))
				source.at = FSData.stat(id, "at", 1) + int(source.get("temporary_at", 0))
				if _untargetable(id):
					_end_battle()
			_note("Карта Монстра открывает и копирует: " + FSData.title(id))
		_:
			super._apply_card_step(step)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if _card_automation_enabled() and event == "attack_start" and battle >= 0 and battle < monsters.size() and int(monsters[battle].id) == 467:
		_queue_packet15(current, 467, monsters[battle], "copy20")

func _put_monster20(source: Dictionary, destination: String) -> void:
	if not _card_automation_enabled():
		super._put_monster20(source, destination)
		return
	var physical: int = int(source.get("physical_id20", source.id))
	if bool(source.get("ambush_return20", false)):
		hands[current].append(physical)
		_note("Карта Монстра возвращается в руку: " + name_of(current))
	elif destination == "bottom":
		decks.monster.push_front(physical)
	else:
		discards["loot" if FSData.card(physical).get("kind", "") == "loot" else "monster"].append(physical)

func _cover_monster20(source: Dictionary) -> Dictionary:
	if _card_automation_enabled() and bool(source.get("ambush_return20", false)):
		_put_monster20(source, "discard")
		return source.get("under", {})
	return source

func _same_monster20(source: Dictionary, data: Dictionary) -> bool:
	return int(source.get("physical_id20", source.id)) == int(data.get("physical_id20", data.get("card", -1)))

func _same_damage_source20(source: Dictionary, data: Dictionary) -> bool:
	return int(source.get("physical_id20", source.id)) == int(data.get("source_physical20", data.get("monster", -1)))

func _damage_player(seat: int, amount: int, context: Dictionary = {}) -> void:
	var adjusted := context.duplicate()
	var source: Dictionary = resolving.get("source", {})
	if context.has("monster") and not context.has("source_physical20") and source.has("physical_id20") and int(context.monster) == int(resolving.get("card", -1)):
		adjusted["source_physical20"] = int(source.physical_id20)
	super._damage_player(seat, amount, adjusted)

func _untargetable(id: int) -> bool:
	return super._untargetable(id) or monsters.any(func(entry): return int(entry.id) == id and bool(entry.get("ambush_event20", false)))

func _printed_monster_reward(id: int) -> Dictionary:
	return {"coins": 0} if id == 467 else super._printed_monster_reward(id)
