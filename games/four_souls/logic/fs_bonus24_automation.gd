extends "res://games/four_souls/logic/fs_packet22_automation.gd"
## Бонусные души ставят обязательное срабатывание в стек при выполнении условия.
func _check_bonuses() -> void:
	super._check_bonuses()
	if not _card_automation_enabled() or _setting_up or phase == "game_over":
		return
	for id: int in CardAutomation.Packet24.BONUSES:
		if id not in bonuses or id in claimed or _bonus_started24.has(id):
			continue
		var ready := false
		match id:
			692: ready = int(bonus_progress.deaths) >= 6
			693: ready = int(bonus_progress.treasures) >= 6
			694: ready = not souls.is_empty() and int(souls.max()) >= 3
			695: ready = items.any(func(inventory): return inventory.size() >= 4)
			696: ready = int(bonus_progress.monsters) >= 6
		if ready:
			_bonus_started24[id] = true
			_queue_packet15(current, id, {}, "bonus24")

func _card_choices() -> Array:
	var out := super._card_choices()
	if str(_card_step().get("targets", "")) != "bonus_seats24":
		return out
	var id: int = int(resolving.card)
	var values: Array = souls if id == 694 else items.map(func(inventory): return inventory.size())
	var least: int = int(values.min())
	for seat in active_seats():
		if int(values[seat]) == least:
			out.append({"label": name_of(seat), "arg": {"op": "bonus_seat24", "target": seat}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	if str(step.op) not in ["bonus_active24", "bonus_seat24"]:
		super._apply_card_step(step)
		return
	var id: int = int(resolving.card)
	var target: int = int(step.get("target", resolving.owner))
	if id in bonuses and id not in claimed and not _room_has20(779) and not curses[target].has(744):
		claimed.append(id)
		_gain_soul_card(target, {"id": id, "value": 1})
		_note(name_of(target) + " получает " + FSData.title(id), id)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled() or event != "death":
		return
	var victim: int = int(data.get("seat", -1))
	if victim >= 0 and curses[victim].has(749):
		for seat in players.size():
			if seat != victim:
				_queue_passive(seat, 749, {}, [PassiveRules.operation("treasure")])
