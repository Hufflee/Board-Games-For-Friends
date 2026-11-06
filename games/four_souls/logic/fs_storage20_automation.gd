extends "res://games/four_souls/logic/fs_coop20_automation.gd"
## Последняя Воля: физические карты штрафа под предметом, возврат и очистка при уходе.
func _card_choices() -> Array:
	var out := super._card_choices()
	var category: String = str(_card_step().get("targets", ""))
	if category == "will_modes20":
		if not resolving.source.get("stored_cards20", []).is_empty():
			out.append({"label": "Вернуть карту из-под предмета на верх её колоды", "arg": {"op": "will_mode20", "mode": "return"}})
		out.append({"label": "Получить по1¢за каждую карту под предметом", "arg": {"op": "will_mode20", "mode": "coins"}})
	if category == "will_cards20":
		for id in resolving.source.get("stored_cards20", []):
			out.append({"label": FSData.title(int(id)), "arg": {"op": "will_return20", "card": int(id)}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var source: Dictionary = resolving.get("source", {})
	match str(step.op):
		"will_mode20":
			if str(step.mode) == "return":
				_insert_card_steps([{"op": "will_return20", "targets": "will_cards20"}])
			else:
				_gain_coins(int(resolving.owner), source.get("stored_cards20", []).size())
		"will_store20":
			var id: int = int(resolving.automation_data.get("penalty_card20", -1))
			if id >= 0 and _source_item_in_play(source) and _take_penalty20(id):
				if not source.has("stored_cards20"):
					source["stored_cards20"] = []
				source.stored_cards20.append(id)
		"will_return20":
			var id: int = int(step.card)
			if id in source.get("stored_cards20", []):
				source.stored_cards20.erase(id)
				decks[_stored_pile20(id)].append(id)
		_:
			super._apply_card_step(step)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled() or event != "after_death":
		return
	for offset in range(players.size() - 1, -1, -1):
		var owner := (current + offset) % players.size()
		if owner == int(data.seat):
			continue
		for source: Dictionary in _ability_items20(owner).duplicate():
			if int(source.id) == 11:
				_queue_packet15(owner, 11, source, event, data)

func _stored_pile20(id: int) -> String:
	var kind: String = str(FSData.card(id).get("kind", ""))
	return "loot" if kind == "loot" else "room" if kind == "room" else "monster" if kind in ["monster", "event", "outside"] else "treasure"

func _take_penalty20(id: int) -> bool:
	for pile: Array in discards.values():
		if id in pile:
			pile.erase(id)
			return true
	for owner in players.size():
		for index in items[owner].size():
			if int(items[owner][index].get("physical_id13", items[owner][index].id)) == id:
				_remove_item(owner, index, true)
				return true
		for index in soul_cards[owner].size():
			if int(soul_cards[owner][index].id) == id:
				var soul: Dictionary = soul_cards[owner].pop_at(index)
				souls[owner] = int(souls[owner]) - int(soul.value)
				return true
	for index in shop.size():
		if int(shop[index]) == id:
			_eternal_shop15.erase(id)
			_shop_counters20.erase(id)
			shop[index] = _draw_shop_slot24()
			return true
	return false

func _release_stored20(source: Dictionary) -> void:
	if not source.has("stored_cards20"):
		return
	for id in source.get("stored_cards20", []):
		discards[_stored_pile20(int(id))].append(int(id))
	source["stored_cards20"] = []
