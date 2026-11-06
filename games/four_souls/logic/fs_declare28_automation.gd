extends "res://games/four_souls/logic/fs_packet28_automation.gd"
## Объявление цели при розыгрыше (06.11) — только в спорной ситуации.
## Правила (foursouls.net/rules/the-stack): цели и вариант «выбери одно» выбираются, когда карта
## кладётся в стек. Движок обычно спрашивает цель при разрешении — это мешает картам отмены
## 72 «Обглоданный лист», 114 «Погоди, что?», 470 «Мега Боб!»: отмена не откатывала уже
## выполненную часть. Поэтому, если у другого игрока есть такая защита, первый выбор карты
## делается сразу при розыгрыше: цель объявлена → окно отмены → отмена снимает карту целиком,
## иначе при разрешении используется объявленная цель. В остальных партиях всё как раньше.

## Розыгрыш добычи или активация предмета: сразу после постановки в стек.
func _push(effect: Dictionary, resume: String) -> void:
	super._push(effect, resume)
	if _should_declare28(effect):
		_begin_declare28(effect)

func _should_declare28(effect: Dictionary) -> bool:
	if not _card_automation_enabled() or effect.has("declared28") or bool(effect.get("declare28", false)):
		return false
	var kind := str(effect.get("kind", ""))
	if kind == "loot":
		if bool(effect.get("loot_copy14", false)):
			return false
	elif kind != "item" or bool(effect.get("conditional", false)):
		return false
	if not CardAutomation.handles(effect):
		return false
	if _declare_index28(effect) < 0:
		return false  # цель зависит от предыдущего шага — прежний порядок
	return _guard_possible28(int(effect.owner), kind)

## Списки целей, которые не зависят от предыдущих шагов карты: их можно объявить заранее.
const STATIC_TARGETS28 := ["players", "other_players", "items", "other_souls", "damage_targets", "shield_players13"]

## Номер шага плана с первым выбором, который можно объявить при розыгрыше (−1 — нельзя).
func _declare_index28(effect: Dictionary) -> int:
	var plan: Array = CardAutomation.plan(int(effect.card), str(effect.get("automation_context", "")))
	for index in plan.size():
		var step: Dictionary = plan[index]
		if step.has("targets"):
			return index if index == 0 or str(step.targets) in STATIC_TARGETS28 else -1
	return -1

## Хоть у кого-то из других игроков есть чем отменить целевую карту.
func _guard_possible28(caster: int, kind: String) -> bool:
	for seat in players.size():
		if seat == caster:
			continue
		if 470 in hands[seat]:
			return true
		if _ability_items20(seat).any(func(entry): return int(entry.id) == 114 and not bool(entry.tapped)):
			return true
		if kind == "loot" and _item_count(seat, 72) > 0 and int(_first_target72.get(seat, -1)) != turn_serial:
			return true
	return false

func _begin_declare28(effect: Dictionary) -> void:
	var plan: Array = CardAutomation.plan(int(effect.card), str(effect.get("automation_context", "")))
	var first: Dictionary = plan[_declare_index28(effect)]
	effect["declared_op28"] = str(first.op)
	effect["declared_targets28"] = str(first.targets)
	var declare := effect.duplicate()
	for key in ["automation_steps", "automation_step", "automation_done", "_resume", "declared_op28", "declared_targets28"]:
		declare.erase(key)
	declare["declare28"] = true
	declare["declare_for28"] = effect
	declare["loot_copy14"] = true  # объявление — не физический розыгрыш: карта в сброс не уходит
	declare["automation_steps"] = [first.duplicate(true)]
	declare["automation_step"] = 0
	_note("%s объявляет цель: %s" % [name_of(int(effect.owner)), FSData.title(int(effect.card))])
	_begin_resolving(declare)
	_advance_card_automation()

## Чья цель в выбранном варианте: другой игрок, его предмет или его бросок.
func _target_owner28(arg: Dictionary, caster: int) -> Dictionary:
	var op := str(arg.get("op", ""))
	if arg.has("roll_index"):
		var index: int = int(arg.roll_index)
		if index >= 0 and index < stack.size() and str(stack[index].kind) in ["roll", "effect_roll"] and int(stack[index].owner) != caster:
			return {"seat": int(stack[index].owner), "zone": "roll"}
		return {}
	if bool(arg.get("shop", false)) or str(arg.get("zone", "")) in ["monster", "room"] or op.begins_with("monster_"):
		return {}
	var seat: int = int(arg.get("seat28", arg.get("target", -1)))
	if seat < 0 or seat >= players.size() or seat == caster:
		return {}
	return {"seat": seat, "zone": "item" if arg.has("item") else "player"}

func _dispatch_card_choice21(step: Dictionary) -> void:
	if bool(resolving.get("declare28", false)):
		_declare_choice28(step)
		return
	if bool(resolving.get("skip_window28", false)):
		resolving.erase("skip_window28")
		_apply_card_step(step)  # окно отмены уже было при розыгрыше
		return
	super._dispatch_card_choice21(step)

func _declare_choice28(step: Dictionary) -> void:
	var effect: Dictionary = resolving.declare_for28
	effect["declared28"] = step.duplicate(true)
	var caster: int = int(effect.owner)
	var target := _target_owner28(step, caster)
	if target.is_empty():
		return
	var defender: int = int(target.seat)
	var kind := str(effect.kind)
	var ward := kind == "loot" and _item_count(defender, 72) > 0 and int(_first_target72.get(defender, -1)) != turn_serial
	var deflect := str(target.zone) in ["item", "roll"] and _ability_items20(defender).any(func(source): return int(source.id) == 114 and not bool(source.tapped))
	var bean: bool = 470 in hands[defender]
	if not ward and not deflect and not bean:
		return
	_target_serial21 += 1
	_push({"kind": "target_window21", "owner": caster, "card": int(effect.card), "target": defender, "zone21": str(target.zone), "token21": _target_serial21, "parent21": effect, "step21": step, "predeclared28": true}, "effect")
	_note("Цель %s: %s — можно отменить" % [FSData.title(int(effect.card)), name_of(defender)])
	if ward:
		_first_target72[defender] = turn_serial
		_queue_packet15(defender, 72, {}, "target21", {"token21": _target_serial21})

## Отмена объявленной карты снимает её со стека целиком.
func _apply_card_step(step: Dictionary) -> void:
	if str(step.op) == "cancel_target21":
		var index: int = int(step.get("index", -1))
		if index >= 0 and index < stack.size() and bool(stack[index].get("predeclared28", false)):
			var pending: Dictionary = stack.pop_at(index)
			var parent: Dictionary = pending.parent21
			var at := -1
			for i in stack.size():
				if is_same(stack[i], parent):
					at = i
					break
			if at >= 0:
				stack.remove_at(at)
				if str(parent.kind) == "loot" and not bool(parent.get("loot_copy14", false)):
					discards.loot.append(int(parent.card))
			elif is_same(resolving.get("declare_for28", {}), parent):
				parent["canceled28"] = true
			_resolving_base = mini(_resolving_base, stack.size())
			_note("Отменено целиком: " + FSData.title(int(parent.card)))
			if int(resolving.card) == 470:
				_damage_player(int(pending.owner), 2, {"attacker": int(resolving.owner)})
			return
	super._apply_card_step(step)

## При разрешении объявленной карты первый выбор делается сам — той же целью.
func _advance_card_automation() -> void:
	super._advance_card_automation()
	if phase != "effect" or not _card_automation_active() or not resolving.has("declared28"):
		return
	var step := _card_step()
	if str(step.get("op", "")) != str(resolving.get("declared_op28", "")) or str(step.get("targets", "")) != str(resolving.get("declared_targets28", "")):
		return  # ещё не дошли до объявленного выбора (предыдущие шаги карты)
	var want: Dictionary = resolving.declared28
	resolving.erase("declared28")
	var choices := _card_choices()
	for index in choices.size():
		if _same_choice28(choices[index].arg, want):
			resolving["skip_window28"] = true
			_choose_card_effect(index)
			return
	_note("Объявленная цель больше недоступна — выберите заново")

func _same_choice28(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or str(a[key]) != str(b[key]):
			return false
	return true
