extends "res://games/four_souls/logic/fs_choices21_automation.gd"
## Сроки копий70/80 и перенос уже выбранного текста Прототипа без повторного получения.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if str(step.get("targets", "")) == "copy_shop21":
		for index in shop.size():
			if int(shop[index]) >= 0:
				out.append({"label": FSData.title(int(shop[index])), "arg": {"op": "copy_shop21", "item": index, "card": int(shop[index])}})
	if str(step.get("targets", "")) == "copy_eternal21":
		var owner: int = int(resolving.owner)
		for index in items[owner].size():
			if bool(items[owner][index].eternal) and not is_same(items[owner][index], resolving.source):
				out.append({"label": FSData.title(int(items[owner][index].id)), "arg": {"op": "copy_eternal21", "target": owner, "item": index}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var source: Dictionary = resolving.get("source", {})
	var owner: int = int(resolving.get("owner", current))
	var op: String = str(step.op)
	if op in ["copy_passive13", "permanent_copy14", "copy_eternal21"] and not bool(step.get("shop", false)):
		resolving["copy_target21"] = items[int(step.target)][int(step.item)]
	if op == "copy_shop21":
		_copy_item14(int(step.card), true)
		source["copy_until_owner21"] = owner
		source["copy_until_turn21"] = turn_serial
		source.tapped = false
	elif op == "copy_eternal21":
		_copy_item14(int(items[int(step.target)][int(step.item)].id), true)
		source.eternal = false
	elif op == "copy_ability14":
		var target: Dictionary = FSData.item_entry(int(step.card)) if bool(step.shop) else items[int(step.target)][int(step.item)]
		var templates: Array = target.get("prototype_texts20", []).duplicate(true)
		_begin_resolving({"kind": "item", "card": int(target.id), "owner": owner, "source": source, "ability_copy14": true, "prototype_texts21": templates})
	else:
		super._apply_card_step(step)

func _copy_item14(id: int, permanent: bool) -> void:
	var source: Dictionary = resolving.source
	var target: Dictionary = resolving.get("copy_target21", {})
	if not source.has("prototype_before21"):
		source["prototype_before21"] = source.get("prototype_texts20", []).duplicate(true)
	var templates: Array = target.get("prototype_texts20", []).duplicate(true)
	super._copy_item14(id, permanent)
	if id == 1:
		source["prototype_texts20"] = templates
	else:
		source.erase("prototype_texts20")
	resolving.erase("copy_target21")

func _restore_copy21(source: Dictionary) -> void:
	if source.has("prototype_before21"):
		var templates: Array = source.prototype_before21
		if templates.is_empty():
			source.erase("prototype_texts20")
		else:
			source["prototype_texts20"] = templates
		source.erase("prototype_before21")
	source.id = int(source.get("physical_id13", source.id))
	source.erase("physical_id13")
	source.erase("copy_permanent14")
	source.erase("copy_until_owner21")
	source.erase("copy_until_turn21")

func _treasure12_passives(event: String, data: Dictionary) -> void:
	if _card_automation_enabled() and event == "turn_start":
		var sources: Array = _extra_rooms20.duplicate()
		for inventory: Array in items:
			sources.append_array(inventory)
		for source: Dictionary in sources:
			if source.has("copy_until_owner21") and int(source.copy_until_owner21) == current and int(source.copy_until_turn21) < turn_serial:
				_restore_copy21(source)
		_refresh_passive_stats()
	super._treasure12_passives(event, data)
	if _card_automation_enabled() and event == "turn_start":
		for source: Dictionary in _ability_items20(current):
			if int(source.id) == 70:
				_queue_packet15(current, 70, source, event, data)

func _tap_item14(id: int) -> bool:
	return false if id == 1 else super._tap_item14(id)
