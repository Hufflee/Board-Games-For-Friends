extends "res://games/four_souls/logic/fs_targets21_automation.gd"
## Число изменяется у конкретной физической карты. Золотой жетон хранится на предмете.
const NUMBER_OPS22 := {"coins": "монеты", "loot": "добыча", "treasure": "сокровища", "damage": "урон", "monster_damage": "урон", "heal": "лечение", "extra_loot": "розыгрыши добычи", "extra_attack": "атаки", "extra_buy": "покупки", "peek_deck": "просмотр карт"}

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	var owner: int = int(resolving.get("owner", current))
	if str(step.get("targets", "")) == "gold_items22":
		for index in items[owner].size():
			var source: Dictionary = items[owner][index]
			if not bool(source.eternal) and not is_same(source, resolving.source):
				out.append({"label": FSData.title(int(source.id)), "arg": {"op": "gold_token22", "target": owner, "item": index, "card": int(source.id)}})
	if str(step.get("targets", "")) == "number_targets22":
		for pending: Dictionary in stack:
			if str(pending.kind) == "loot" and int(pending.card) not in [500, 528]:
				var id: int = int(pending.card)
				var amount := _coin_loot_value22(pending)
				if amount > 0:
					_append_numbers22(out, pending, id, "", -1, "монеты", amount)
				elif CardAutomation.handles(pending):
					_plan_numbers22(out, pending, id, "", _automation_plan22(pending))
		for seat in active_seats():
			if _protected20(seat, owner):
				continue
			for source: Dictionary in items[seat]:
				var id: int = int(source.id)
				var effect := {"kind": "item", "card": id, "owner": seat, "source": source}
				if CardAutomation.handles(effect) and _item_kind20(source) in ["tap", "paid", "hybrid"]:
					_plan_numbers22(out, source, id, "", _automation_plan22(effect))
	return out

func _plan_numbers22(out: Array, source: Dictionary, id: int, context: String, plan: Array) -> void:
	for index in plan.size():
		var step: Dictionary = plan[index]
		if NUMBER_OPS22.has(str(step.op)) and step.has("amount"):
			_append_numbers22(out, source, id, context, index, str(NUMBER_OPS22[str(step.op)]), int(step.amount))

func _append_numbers22(out: Array, source: Dictionary, id: int, context: String, index: int, title: String, amount: int) -> void:
	if amount < 1 or amount > 6:
		return
	for change in [-1, 1]:
		if amount + change >= 1 and amount + change <= 6:
			out.append({"label": "%s · %s %d → %d" % [FSData.title(id), title, amount, amount + change], "arg": {"op": "edit_number22", "source": source, "card": id, "context": context, "index": index, "value": amount + change}})

func _apply_card_step(step: Dictionary) -> void:
	match str(step.op):
		"edit_number22":
			var source: Dictionary = step.source
			if int(source.get("number_turn22", -1)) != turn_serial:
				source["number_edits22"] = {}
			source["number_turn22"] = turn_serial
			var key := _number_key22(int(step.card), str(step.context), int(step.index))
			source.number_edits22[key] = int(step.value)
		"gold_token22":
			var source: Dictionary = items[int(step.target)][int(step.item)]
			source["gold_counters22"] = int(source.get("gold_counters22", 0)) + 1
			_refresh_passive_stats()
		"rainbow_roll22":
			if int(resolving.get("automation_roll", 0)) >= 4:
				_insert_card_steps([{"op": "rainbow_copy22", "targets": "copy_items14"}])
		"rainbow_copy22":
			if not bool(step.shop):
				resolving["copy_target21"] = items[int(step.target)][int(step.item)]
			var id: int = int(step.card) if bool(step.shop) else int(items[int(step.target)][int(step.item)].id)
			_copy_item14(id, false)
		_:
			super._apply_card_step(step)

func _number_key22(id: int, context: String, index: int) -> String:
	return "%d/%s/%d" % [id, context, index]

func _automation_plan22(effect: Dictionary) -> Array:
	var plan := super._automation_plan22(effect)
	var id: int = int(effect.card)
	var context: String = str(effect.get("automation_context", ""))
	for source: Dictionary in [effect.get("source", {}), effect]:
		if int(source.get("number_turn22", -1)) != turn_serial:
			continue
		for index in plan.size():
			var key := _number_key22(id, context, index)
			if source.number_edits22.has(key):
				plan[index]["amount"] = int(source.number_edits22[key])
	return plan

func _coin_loot_value22(effect: Dictionary) -> int:
	var amount := super._coin_loot_value22(effect)
	if amount > 0 and int(effect.get("number_turn22", -1)) == turn_serial:
		return int(effect.number_edits22.get(_number_key22(int(effect.card), "", -1), amount))
	return amount

func _gain_item(seat: int, id: int, eternal: bool = false) -> void:
	super._gain_item(seat, id, eternal)
	if _card_automation_enabled() and id == 502 and not _setting_up:
		_queue_packet15(seat, 502, items[seat].back(), "enter22")

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if _card_automation_enabled() and event == "turn_start":
		for source: Dictionary in _ability_items20(current):
			if int(source.id) == 534:
				_queue_packet15(current, 534, source, event, data)

func _refresh_passive_stats() -> void:
	if _card_automation_enabled():
		_sync_gold22()
	super._refresh_passive_stats()

func _sync_gold22() -> void:
	var marked: Array = []
	for inventory: Array in items:
		for source: Dictionary in inventory:
			if int(source.get("gold_counters22", 0)) > 0 and int(source.id) != 502 and not bool(source.get("gold_proxy22", false)):
				marked.append(source)
	for inventory: Array in items:
		for source: Dictionary in inventory:
			if int(source.id) != 502 and not bool(source.get("gold_proxy22", false)):
				continue
			if marked.is_empty():
				if bool(source.get("gold_proxy22", false)):
					source.id = 502
					source.erase("prototype_texts20")
				continue
			var model: Dictionary = marked[0]
			if not source.has("physical_id13"):
				source["physical_id13"] = 502
				source["copy_permanent14"] = true
			source["gold_proxy22"] = true
			source.id = int(model.id)
			if int(model.id) == 1:
				source["prototype_texts20"] = model.get("prototype_texts20", []).duplicate(true)
			else:
				source.erase("prototype_texts20")

func _restore_copy21(source: Dictionary) -> void:
	source.erase("gold_proxy22")
	super._restore_copy21(source)
