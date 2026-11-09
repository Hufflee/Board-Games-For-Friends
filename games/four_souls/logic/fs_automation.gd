extends "res://games/four_souls/logic/fs_turn.gd"
## Хостовый исполнитель карточных последовательностей. Продолжение хранится в resolving,
## поэтому ответы, броски и вложенные пассивы используют штатный стек.
const CardAutomation := preload("res://games/four_souls/logic/fs_card_automation.gd")
var _automation_running := false
var _automation_internal := false
var _host_manual := false

func _card_automation_enabled() -> bool:
	return true

func _card_automation_active() -> bool:
	return not resolving.is_empty() and CardAutomation.handles(resolving)

func _advance_card_automation() -> void:
	if _automation_running or phase != "effect" or not _card_automation_active():
		return
	if resolving.has("reroll_request") or bool(resolving.get("automation_done", false)):
		return
	_automation_running = true
	if not resolving.has("automation_steps"):
		resolving["automation_steps"] = _automation_plan22(resolving)
		resolving["automation_step"] = 0
	var original: Dictionary = resolving
	while phase == "effect" and is_same(original, resolving):
		if resolving.has("reroll_request"):
			break
		var steps: Array = resolving.automation_steps
		var index: int = int(resolving.automation_step)
		if index >= steps.size():
			resolving["automation_done"] = true
			_automation_internal = true
			action(int(resolving.owner), "effect_done")
			_automation_internal = false
			break
		var step: Dictionary = steps[index]
		if step.has("targets"):
			if not _card_choices().is_empty():
				break
			resolving.automation_step = index + 1
			if bool(step.get("required", false)):
				resolving.automation_step = steps.size()
			continue
		if str(step.op) == "auto_roll":
			if not resolving.has("automation_roll"):
				break
			resolving.automation_step = index + 1
			continue
		if str(step.op) in ["read_peek", "order_peek"]:
			if not peek.is_empty():
				break
			resolving.automation_step = index + 1
			continue
		# До операции: вызванный пассив не сможет повторить уже выполненный шаг.
		resolving.automation_step = index + 1
		_apply_card_step(step)
	_automation_running = false
	# Завершение вложенной карты может синхронно вернуть другую resolving под тем же
	# защитным флагом. Сразу продолжаем её, иначе до следующего tick нет законного выбора.
	if phase == "effect" and _card_automation_active() and not is_same(original, resolving):
		_advance_card_automation()

func _card_step() -> Dictionary:
	if not _card_automation_active() or not resolving.has("automation_steps"):
		return {}
	var index: int = int(resolving.get("automation_step", 0))
	var steps: Array = resolving.automation_steps
	return steps[index] if index < steps.size() else {}

## Публичные подписи отделены от операций. Клиент посылает только индекс и revision.
func _card_choices() -> Array:
	var step := _card_step()
	var out: Array = []
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	var op: String = str(step.op)
	var amount: int = int(step.get("amount", 1))
	match str(step.get("targets", "")):
		"damage_targets":
			var targets: Array = []
			for seat in players.size():
				targets.append({"zone": "player", "target": seat})
			for slot in monsters.size():
				targets.append({"zone": "monster", "target": slot})
			for target: Dictionary in targets:
				out.append({"label": name_of(int(target.target)) if target.zone == "player" else FSData.title(int(monsters[int(target.target)].id)), "arg": {"op": "damage" if target.zone == "player" else "monster_damage", "target": int(target.target) if target.zone == "player" else owner, "item": int(target.target), "amount": amount}})
		"other_players":
			for seat in players.size():
				if seat != owner:
					out.append({"label": name_of(seat), "arg": {"op": op, "target": seat}})
		"cancelable_cards":
			for i in stack.size():
				var effect: Dictionary = stack[i]
				if effect.kind == "loot" or (effect.kind == "item" and not bool(effect.get("conditional", false)) and not effect.has("automation_context")):
					out.append({"label": FSData.title(int(effect.card)), "arg": {"op": "cancel_selected", "index": i}})
		"decks":
			for deck in decks:
				if not decks[deck].is_empty():
					out.append({"label": {"loot": "Добыча", "treasure": "Сокровища", "monster": "Монстры", "room": "Комнаты"}[deck], "arg": {"op": "peek_deck", "deck": deck, "amount": int(step.get("amount", 1))}})
		"players", "richest":
			var richest: int = int(coins.max())
			for seat in players.size():
				if str(step.targets) != "richest" or int(coins[seat]) == richest:
					out.append({"label": name_of(seat), "arg": {"op": op, "target": seat, "amount": amount}})
		"items":
			for seat in players.size():
				for i in items[seat].size():
					if int(items[seat][i].id) != 44 or int(resolving.card) == 44:
						out.append({"label": name_of(seat) + " · " + FSData.title(int(items[seat][i].id)), "arg": {"op": op, "target": seat, "item": i}})
		"other_souls":
			for seat in players.size():
				if seat == owner:
					continue
				for i in soul_cards[seat].size():
					var card: int = int(soul_cards[seat][i].id)
					if FSData.card(card).get("kind", "") != "character":
						out.append({"label": name_of(seat) + " · " + FSData.title(card), "arg": {"op": op, "target": seat, "item": i}})
		"rolls", "roll_modifiers":
			for i in stack.size():
				if stack[i].kind not in ["roll", "effect_roll"]:
					continue
				for change in ([-1, 1] if str(step.targets) == "roll_modifiers" else [0]):
					out.append({"label": "%s · %d%s" % [name_of(int(stack[i].owner)), int(stack[i].value), " · %+d" % change if change != 0 else ""], "arg": {"op": op, "roll_index": i, "amount": change}})
		"combatants":
			for seat in players.size():
				out.append({"label": name_of(seat), "arg": {"op": op, "target": seat, "amount": amount}})
			for slot in monsters.size():
				if int(monsters[slot].hp) > 0:
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "monster_temporary_attack", "item": slot, "amount": amount}})
		"own_hand":
			for i in hands[owner].size():
				out.append({"label": FSData.title(int(hands[owner][i])), "arg": {"op": op, "item": i}})
	if bool(step.get("optional", false)):
		out.append({"label": "Пропустить", "arg": {"op": "skip_choice"}})
	if op == "read_peek":
		out.append({"label": "Продолжить", "arg": {"op": "close_peek"}})
	if op == "order_peek":
		# 09.11 (владелец): понятно, куда ляжет карта — первая выбранная будет самой верхней.
		var place: int = (peek.get("order", []) as Array).size() + 1
		for id in peek.get("cards", []):
			var where := "1-я сверху (возьмут первой)" if place == 1 else "%d-я сверху" % place
			out.append({"label": "%s: %s" % [where, FSData.title(int(id))], "arg": {"op": "order_card", "card": int(id)}})
	return out

func _choose_card_effect(index: int) -> bool:
	var choices := _card_choices()
	if index < 0 or index >= choices.size():
		return false
	var step := _card_step()
	var arg: Dictionary = choices[index].arg
	if str(arg.op) == "order_card":
		var id: int = int(arg.card)
		peek.cards.erase(id)
		peek.order.append(id)
		if peek.cards.is_empty():
			var deck: String = str(peek.deck)
			for picked in peek.order:
				decks[deck].erase(int(picked))
			for i in range(peek.order.size() - 1, -1, -1):
				decks[deck].append(int(peek.order[i]))
			peek = {}
			resolving.automation_step = int(resolving.automation_step) + 1
	elif str(arg.op) == "close_peek":
		peek = {}
		resolving.automation_step = int(resolving.automation_step) + 1
	else:
		resolving.automation_step = int(resolving.automation_step) + 1
		if str(arg.op) != "skip_choice":
			_dispatch_card_choice21(arg)
		if str(step.get("targets", "")) in ["own_hand", "own_hand_top"] and int(step.get("amount", 1)) > 1:
			var rest := step.duplicate(true)
			rest.amount = int(rest.amount) - 1
			(resolving.automation_steps as Array).insert(int(resolving.automation_step), rest)
	_advance_card_automation()
	return true

func _dispatch_card_choice21(step: Dictionary) -> void:
	_apply_card_step(step)

func _automation_plan22(effect: Dictionary) -> Array:
	return CardAutomation.plan(int(effect.card), str(effect.get("automation_context", "")))

func _insert_card_steps(steps: Array) -> void:
	var index: int = int(resolving.automation_step)
	for i in range(steps.size() - 1, -1, -1):
		(resolving.automation_steps as Array).insert(index, steps[i])

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var op: String = str(step.op)
	var value: int = int(resolving.get("automation_roll", 0))
	match op:
		"recharge_all":
			var steps: Array = []
			var target: int = int(step.target)
			for i in items[target].size():
				if int(items[target][i].id) != 44:
					steps.append({"op": "recharge", "target": target, "item": i})
			_insert_card_steps(steps)
		"black_heart":
			var target: int = int(step.target)
			damage_shields[target] += 1
			_card_delayed.append({"card": int(resolving.card), "owner": owner, "target": target, "turn": turn_serial})
		"double_coins":
			_gain_coins(int(step.target), int(coins[int(step.target)]))
		"spades_loot":
			_draw_loot(owner, hands[int(step.target)].size())
		"cancel_selected":
			var canceled: Dictionary = stack.pop_at(int(step.index))
			_resolving_base = mini(_resolving_base, stack.size())
			if canceled.kind == "loot" and not bool(canceled.get("loot_copy14", false)):
				discards.loot.append(int(canceled.card))
		"fruit_result":
			if value == 1:
				_insert_card_steps([CardAutomation.op("loot")])
			elif value <= 3:
				_insert_card_steps([CardAutomation.op("coins")])
			else:
				_insert_card_steps([CardAutomation.choose("peek_deck", "decks"), CardAutomation.op("read_peek")])
		"sticky_result":
			_insert_card_steps([{"op": "self_give", "target": (owner + 1) % players.size()}] if value <= 3 else [CardAutomation.op("coins", 5)])
		"event_result":
			_insert_card_steps(_event_card_steps(int(resolving.card), value))
		"destroy_self":
			var destroyed := false
			for i in items[owner].size():
				if (int(items[owner][i].id) == int(resolving.card) or bool(resolving.get("ability_copy14", false))) and not bool(items[owner][i].eternal) and (not resolving.has("source") or is_same(items[owner][i], resolving.source)):
					_destroy_item(owner, i)
					destroyed = true
					break
			if not destroyed:
				resolving.automation_step = resolving.automation_steps.size()
		"damage_all":
			var steps: Array = []
			for offset in players.size():
				var seat: int = (owner + offset) % players.size()
				steps.append({"op": "damage", "target": seat, "amount": 1})
			_insert_card_steps(steps)
		"discard_slayer_hand":
			var slot: int = int(resolving.slot)
			var slayer: int = int(monsters[slot].get("slayer", owner))
			discards.loot.append_array(hands[slayer])
			hands[slayer].clear()
		"lose_all_coins":
			_gain_coins(int(step.target), -int(coins[int(step.target)]))
		"monster_temporary_attack":
			var m: Dictionary = monsters[int(step.item)]
			m.at = int(m.at) + int(step.amount)
			m["temporary_at"] = int(m.get("temporary_at", 0)) + int(step.amount)
		"force_deck_attack":
			required_deck_attacks = maxi(required_deck_attacks, deck_attacks + 1)
			attack_left = maxi(attack_left, 1)
			attacked = false
		"peek_deck":
			var deck: String = str(step.get("deck", "monster"))
			peek = {"owner": owner, "deck": deck, "cards": decks[deck].slice(maxi(0, decks[deck].size() - int(step.get("amount", 1)))), "order": []}
			if peek.cards.is_empty():
				peek = {}
		"reroll":
			var i: int = int(step.roll_index)
			resolving["reroll_request"] = {"owner": int(stack[i].owner), "index": i, "target_token": _roll_token(stack[i]), "attack": _rerolls_attack({"reroll_index": i})}
		"roll":
			var i: int = int(step.roll_index)
			stack[i].value = clampi(int(stack[i].value) + int(step.amount), 1, 6)
			_fx28({"kind": "roll", "seat": int(stack[i].owner), "amount": int(step.amount), "card": int(resolving.get("card", -1))})
			if stack[i].has("final_value"):
				stack[i].final_value = clampi(int(stack[i].final_value) + int(step.amount), 1, 6)
		_:
			_automation_internal = true
			_effect(step)
			_automation_internal = false
	_note("Автоматический эффект: " + FSData.title(int(resolving.get("card", -1))) + " · " + op)

func _event_card_steps(id: int, value: int) -> Array:
	match id:
		700:
			return [CardAutomation.op("loot")] if value <= 2 else [CardAutomation.op("coins", 3)] if value <= 4 else [CardAutomation.op("damage", 2)]
		703:
			if value == 1: return [CardAutomation.op("damage", 3)]
			if value <= 3: return [CardAutomation.choose("discard_loot", "own_hand", 2)]
			return [CardAutomation.op("coins", 7)] if value <= 5 else [CardAutomation.op("treasure")]
		719:
			return [CardAutomation.op("damage")] if value <= 2 else [CardAutomation.op("damage"), CardAutomation.op("loot")] if value <= 4 else [CardAutomation.op("damage"), CardAutomation.op("treasure")]
		727:
			return [CardAutomation.op("force_deck_attack")] if value <= 2 else [CardAutomation.op("loot", 3)] if value <= 4 else [CardAutomation.op("treasure")]
		730:
			return [{"op": "peek_deck", "deck": "monster", "amount": 3}, CardAutomation.op("order_peek"), CardAutomation.op("extra_attack")] if value <= 3 else [CardAutomation.op("damage")]
	return []
