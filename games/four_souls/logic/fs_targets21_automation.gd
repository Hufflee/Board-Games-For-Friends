extends "res://games/four_souls/logic/fs_copy21_automation.gd"
## Окно ответа на объявленную цель для72/114/470.
const ITEM_TARGETS21 := ["destroy", "steal", "recharge", "deactivate", "counter", "give_item", "item_to_soul", "heal_item", "typed_counter21", "counter_item21", "force_activate20", "mushroom_counter20", "make_room20", "battery_item21"]
const PLAYER_TARGETS21 := ["damage", "heal", "coins", "loot", "kill_player16", "tumor_save20", "discard_target18", "steal_soul", "steal_loot", "skip_turn", "take_shop", "prevent_death", "next_d8_20", "black_heart", "double_coins"]

func _dispatch_card_choice21(step: Dictionary) -> void:
	var target := _declared_target21(step)
	if target.is_empty() or not _card_automation_enabled() or str(resolving.kind) not in ["loot", "item"]:
		super._dispatch_card_choice21(step)
		return
	var defender: int = int(target.seat)
	var caster: int = int(resolving.owner)
	var ward := str(resolving.kind) == "loot" and caster != defender and _item_count(defender, 72) > 0 and int(_first_target72.get(defender, -1)) != turn_serial
	var can_deflect: bool = str(target.zone) in ["item", "roll"] and (str(resolving.kind) == "loot" or not bool(resolving.get("conditional", false))) and _ability_items20(defender).any(func(source): return int(source.id) == 114 and not bool(source.tapped))
	var has_loot: bool = 470 in hands[defender] or (int(_top_loot20.get(defender, -1)) == turn_serial and not decks.loot.is_empty() and int(decks.loot.back()) == 470)
	if not ward and not can_deflect and not has_loot:
		super._dispatch_card_choice21(step)
		return
	_target_serial21 += 1
	_push({"kind": "target_window21", "owner": caster, "card": int(resolving.card), "target": defender, "zone21": str(target.zone), "token21": _target_serial21, "parent21": resolving, "step21": step}, "effect")
	if ward:
		_first_target72[defender] = turn_serial
		_queue_packet15(defender, 72, {}, "target21", {"token21": _target_serial21})

func _declared_target21(step: Dictionary) -> Dictionary:
	if step.has("roll_index"):
		var index: int = int(step.roll_index)
		if index >= 0 and index < stack.size() and str(stack[index].kind) in ["roll", "effect_roll"]:
			return {"seat": int(stack[index].owner), "zone": "roll"}
	var seat: int = int(step.get("target", -1))
	if seat < 0 or seat >= players.size() or bool(step.get("shop", false)) or str(step.get("zone", "")) in ["monster", "room"]:
		return {}
	if str(step.op) in ITEM_TARGETS21:
		return {"seat": seat, "zone": "item"}
	if str(step.op) in PLAYER_TARGETS21:
		return {"seat": seat, "zone": "player"}
	return {}

func _guard_matches21(pending: Dictionary, seat: int, id: int, token: int = -1) -> bool:
	if str(pending.get("kind", "")) != "target_window21" or int(pending.target) != seat:
		return false
	if id == 72:
		return int(pending.token21) == token
	if id == 114:
		return str(pending.zone21) in ["item", "roll"] and (str(pending.parent21.kind) == "loot" or not bool(pending.parent21.get("conditional", false)))
	return id == 470

func _can_guard21(seat: int, id: int) -> bool:
	return stack.any(func(pending): return _guard_matches21(pending, seat, id))

func _card_choices() -> Array:
	var out := super._card_choices()
	if str(_card_step().get("targets", "")) == "guard_targets21":
		var owner: int = int(resolving.owner)
		var id: int = int(resolving.card)
		var token: int = int(resolving.get("automation_data", {}).get("token21", -1))
		for index in stack.size():
			var pending: Dictionary = stack[index]
			if _guard_matches21(pending, owner, id, token):
				out.append({"label": "Отменить: " + FSData.title(int(pending.card)), "arg": {"op": "cancel_target21", "index": index}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	if str(step.op) != "cancel_target21":
		super._apply_card_step(step)
		return
	var pending: Dictionary = stack.pop_at(int(step.index))
	var parent: Dictionary = pending.parent21
	parent.automation_step = parent.automation_steps.size()
	_resolving_base = mini(_resolving_base, stack.size())
	_note("Отменено: " + FSData.title(int(pending.card)))
	if int(resolving.card) == 470:
		_damage_player(int(pending.owner), 2, {"attacker": int(resolving.owner)})

func _resolve_top() -> void:
	if not stack.is_empty() and str(stack.back().kind) == "target_window21":
		var pending: Dictionary = stack.pop_back()
		if is_same(resolving, pending.parent21):
			phase = "effect"
			_apply_card_step(pending.step21)
		_continue_stack()
		return
	super._resolve_top()
