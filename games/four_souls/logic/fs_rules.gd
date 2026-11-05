class_name FSRules
extends "res://games/four_souls/logic/fs_effects.gd"
## Восемь мест и ручные эффекты оригинального стола. Хост ведёт колоды, приоритет,
## стек, бой, смерть и ресурсы; текст сложной карты выполняют люди через открытый журнал.
## Фасад: action()/get_view()/clone()/legal_actions(). Цепочка модулей (снизу вверх):
## fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules. Поведение не менялось при делении 31.10.
## Время (tick с хоста): окно ответов закрывается само через RESPONSE_WINDOW — урон, лечение и смерть
## применяются без ожидания следующего действия; свои карты в чужой ход — только первые OFF_TURN_WINDOW с.

const RESPONSE_WINDOW := 5.0  # тихое окно ответов (никто не добавил карту) — стек разрешается сам
const OFF_TURN_WINDOW := 10.0  # в чужой ход лут и предметы — только в первые столько секунд хода
const OFF_TURN_KINDS := ["character", "mushroom_counter20", "loot_top20", "remove_spider15", "loot", "activate"]  # «разыграть свою карту» вне своего хода
var turn_elapsed := 0.0  # секунд с начала текущего хода (считает хост в tick)
var _quiet := 0.0
var _quiet_revision := -1
var _turn_seen := -1  # номер хода, к которому относится turn_elapsed


## Хост: шаг времени. true — состояние изменилось (окно ответов закрылось само).
func tick(delta: float) -> bool:
	if _turn_seen != turn_serial:
		_turn_seen = turn_serial
		turn_elapsed = 0.0
	turn_elapsed += delta
	if phase == "effect":
		var before_revision := revision
		var before_effect := resolving.hash()
		_advance_card_automation()
		if revision != before_revision:
			return true
		if resolving.hash() != before_effect:
			revision += 1
			return true
	if phase != "priority" or stack.is_empty() or _after_stack == "starting_continue":
		_quiet = 0.0
		_quiet_revision = revision
		return false
	if revision != _quiet_revision:
		_quiet_revision = revision  # кто-то ответил — окно снова открыто полностью
		_quiet = 0.0
		return false
	_quiet += delta
	if _quiet < RESPONSE_WINDOW:
		return false
	_quiet = 0.0
	var before := [phase, stack.size(), resolving.size()]
	_finish_responses()
	if before == [phase, stack.size(), resolving.size()]:
		return false
	revision += 1
	_check_bonuses()
	_check_win()
	_quiet_revision = revision
	return true


## Можно ли месту разыграть свою карту сейчас: в свой ход — всегда, в чужой — первые 10 с хода.
func off_turn_open(seat: int) -> bool:
	return seat == current or _turn_time() <= OFF_TURN_WINDOW


## Секунд с начала хода; ход только что сменился, а tick ещё не шёл — ноль.
func _turn_time() -> float:
	return turn_elapsed if _turn_seen == turn_serial else 0.0


func action(seat: int, kind: String, arg = null) -> bool:
	if seat < 0 or seat >= players.size() or phase == "game_over": return false
	if kind in OFF_TURN_KINDS and not off_turn_open(seat) and not _forced_activation20:
		return false
	if kind in OFF_TURN_KINDS and _jail_owner >= 0 and seat != _jail_owner:
		return false
	# Следующая операция того же ручного эффекта сначала разрешает его пассивы.
	# Чужой ручной ответ не пропускаем: маршрут открыт только для стека пассивов.
	if _pending_manual_passives() and kind in ["effect", "effect_done", "effect_roll", "place_bloat"]:
		if seat != int(resolving.owner):
			return false
		var original_effect: Dictionary = resolving
		_finish_responses()
		if phase == "effect" and seat == int(resolving.get("owner", -1)) and is_same(original_effect, resolving):
			return action(seat, kind, arg)
		# Жест закрыл ответы, но теперь разрешается чужой (вложенный) ручной эффект.
		revision += 1
		_check_bonuses()
		_check_win()
		return true
	if phase == "priority" and _after_stack == "starting_continue":
		if kind != "finish_start" or seat != current:
			return false
		_finish_responses()
		revision += 1
		return true
	_refresh_passive_stats()
	if seat != current and kind in ["character", "mushroom_counter20", "loot_top20", "loot", "activate"] and _item_count(current, 256) > 0:
		return false
	# Бросок ручной карты возвращает её владельцу, сохраняя уже отложенное действие.
	# Повторный захват кубика закрывает ответы, а не создаёт ещё один бросок.
	if phase == "priority" and kind == "effect_roll" and not paused_effects.is_empty() and resolving.is_empty():
		if seat != int(paused_effects.back().get("roller", paused_effects.back().effect.owner)): return false
		_finish_responses()
		revision += 1
		return true
	# Подтверждение штрафа сначала разрешает ответы на уже объявленную смерть.
	# Ручной ответ требует отдельного завершения; штраф сам по себе не применяется.
	if phase == "priority" and kind == "death" and not _death_queue.is_empty():
		if seat != int(_death_queue[0]):
			return false
		_finish_responses()
		revision += 1
		if phase == "death":
			return action(seat, kind, arg)
		return true
	# Выбор цели Гордыни мог прервать уже отложенный бросок.
	# Следующий жест только закрывает ответы на сброс, сохраняя исходный бросок.
	if phase == "priority" and kind == "roll" and seat == current and not next_action.is_empty() and stack.any(func(e): return e.kind == "forced_discard"):
		_finish_responses()
		revision += 1
		return true
	# Окно ответов открыто всем до следующего действия активного игрока.
	# Предыдущее действие и ответы сначала завершаются; ручной эффект не пропускается.
	if phase == "priority" and seat == current and kind in ["roll","attack","buy","end","room"] and next_action.is_empty():
		next_action = {"seat":seat,"kind":kind,"arg":arg}
		_finish_responses()
		revision += 1
		return true
	var a: Dictionary = arg if arg is Dictionary else {}
	var from_top20 := kind == "loot_top20"
	if from_top20:
		if not _card_automation_enabled() or int(_top_loot20.get(seat, -1)) != turn_serial or decks.loot.is_empty():
			return false
		if a.has("card") and int(a.card) != int(decks.loot.back()):
			return false
		a = {"card": int(decks.loot.back())}
		kind = "loot"
	var ok := false
	match kind:
		"card_choice":
			if phase != "effect" or seat != _card_choice_owner() or int(a.get("revision", -1)) != revision:
				return false
			ok = _choose_card_effect(int(a.get("index", -1)))
		"reward_soul_target":
			var target: int = int(a.get("target", -1))
			if phase != "effect" or seat != int(resolving.get("owner", -1)) or target not in resolving.get("reward_soul_targets", []):
				return false
			resolving["soul_recipient"] = target
			resolving.erase("reward_soul_targets")
			_advance_auto_reward()
			ok = true
		"reward_damage":
			if phase != "effect" or seat != int(resolving.get("owner", -1)) or not bool(resolving.get("reward_damage", false)):
				return false
			var chosen := {"zone": str(a.get("zone", "")), "target": int(a.get("target", -1))}
			if chosen not in _reward_damage_targets():
				return false
			resolving["reward_damage_done"] = true
			resolving.erase("reward_damage")
			var damage: int = int(resolving.auto_reward.damage_choice) * reward_boost
			ok = _effect({"op": "damage" if chosen.zone == "player" else "monster_damage", "target": chosen.target if chosen.zone == "player" else seat, "item": chosen.target, "amount": damage})
			_advance_auto_reward()
		"reward_winner":
			var target: int = int(a.get("target", -1))
			if phase != "effect" or seat != int(resolving.get("owner", -1)) or not resolving.has("reward_winners") or target not in _reward_win_targets():
				return false
			resolving["reward_winner"] = target
			resolving.erase("reward_winners")
			_advance_auto_reward()
			ok = true
		"discard_target":
			var target: int = int(a.get("target", -1))
			if phase != "discard_target" or seat != current or target < 0 or target >= players.size():
				return false
			var effect := discard_choice.duplicate(true)
			discard_choice = {}
			effect["kind"] = "forced_discard"
			effect["target"] = target
			_push(effect, "battle_roll")
			ok = true
		"forced_discard":
			var index: int = int(a.get("item", -1))
			if phase != "forced_discard" or seat != actor() or index < 0 or index >= hands[seat].size():
				return false
			discards.loot.append(hands[seat].pop_at(index))
			discard_choice.remaining = int(discard_choice.remaining) - 1
			_note(name_of(seat) + " сбрасывает карту лута: " + FSData.title(int(discard_choice.card)))
			if int(discard_choice.remaining) <= 0 or hands[seat].is_empty():
				discard_choice = {}
				_continue_stack()
				_finish_responses()
			ok = true
		"attack_player":
			if not _forced_slots14().is_empty():
				return false
			var target: int = int(a.get("target", -1))
			if phase != "turn" or seat != current or battle >= 0 or battle_player >= 0 or target not in _permitted_player_attack_targets():
				return false
			if target not in _player_attack_targets() or dead[current] or hp[current] <= 0:
				return false
			if not _pay_attack_tax(seat): return false
			if target in _lust_pending:
				_lust_pending.erase(target)
			elif required_player_attacks > 0:
				required_player_attacks -= 1
			else:
				attack_left -= 1
				attacked = attack_left <= 0
			_push({"kind": "player_attack", "owner": current, "card": 268, "target": target}, "turn")
			if _card_automation_enabled():
				_next_attack_token += 1
				_emit_passives("attack_declared", {"seat": seat, "slot": -2, "target": target, "token": _next_attack_token})
			ok = true
		"place_bloat":
			var slot: int = int(a.get("slot", -1))
			if phase != "effect" or seat != int(resolving.get("owner", -1)) or not resolving.has("spawn_card"):
				return false
			if slot not in _peep_spawn_slots():
				return false
			var id: int = int(resolving.spawn_card)
			if not decks.monster.has(id):
				return false
			decks.monster.erase(id)
			var entry := {"id": id, "hp": _monster_hp(id), "dc": FSData.stat(id, "dc", 4), "at": FSData.stat(id, "at", 1)}
			if slot < monsters.size():
				entry["under"] = monsters[slot].duplicate(true)
				monsters[slot] = entry
			else:
				monsters.append(entry)
			_shuffle(decks.monster)
			if slot == int(resolving.get("slot", -1)):
				resolving["spawn_over_source"] = true
			resolving.erase("spawn_card")
			_note("Пип: Утопец выложен в ячейку %d" % (slot + 1))
			ok = true
		"choose_starting_item":
			if phase != "starting_item" or _starting_choices.is_empty() or seat != actor():
				return false
			var id: int = int(a.get("card", -1))
			if id not in _starting_choices[0].cards:
				return false
			var choice: Dictionary = _starting_choices.pop_front()
			var rest: Array = choice.cards.duplicate()
			rest.erase(id)
			for other in rest:
				decks.treasure.push_front(int(other))
			_gain_item(seat, id, true)
			if phase == "priority":
				_after_stack = "starting_continue"
			else:
				_advance_start()
			ok = true
		"monster_trigger":
			if _card_automation_enabled() and int(a.get("slot", -1)) >= 0 and int(a.get("slot", -1)) < monsters.size() and (int(monsters[int(a.slot)].id) in CardAutomation.Packet15.IDS or int(monsters[int(a.slot)].id) in CardAutomation.Monster16.IDS or int(monsters[int(a.slot)].id) in CardAutomation.Monster17.IDS or int(monsters[int(a.slot)].id) in CardAutomation.Monster18.IDS or int(monsters[int(a.slot)].id) in CardAutomation.Monster19.IDS or int(monsters[int(a.slot)].id) in CardAutomation.Monster20.IDS):
				return false
			var slot: int = int(a.get("slot", -1))
			if phase in ["turn", "priority", "battle_roll", "death"] and not dead[seat] and slot >= 0 and slot < monsters.size():
				var resume: String = _after_stack if phase == "priority" else phase
				_push({"kind": "monster_trigger", "card": int(monsters[slot].id), "owner": seat, "slot": slot}, resume)
				ok = true
		"claim":
			var id: int = int(a.get("card",-1))
			if phase in ["turn","priority"] and bonuses.has(id) and not claimed.has(id):
				if _room_has20(779) or curses[seat].has(744):
					return false
				var recipient := seat
				if id in [692, 693, 694, 695, 696]:
					recipient = int(a.get("target", seat))
					if seat != current or recipient not in _bonus_targets(id):
						return false
				var key: String = FSData.card(id).key
				if key == "soulofgreed" and coins[seat] < 25: return false
				if key == "soulofgluttony" and hands[seat].size() < 10: return false
				if key == "soulofguppy":
					var guppy := 0
					for item in items[seat]:
						if str(FSData.card(int(item.id)).key).begins_with("guppy"): guppy += 1
					if guppy < 2: return false
				claimed.append(id)
				_gain_soul_card(recipient, {"id": int(id), "value": 1})
				_note(name_of(recipient) + " получает " + FSData.title(id))
				ok = true
		"peek_take":
			if _card_automation_active() and not _host_manual:
				return false
			var id: int = int(a.get("card",-1))
			if phase == "effect" and seat == int(resolving.owner) and int(peek.get("owner",-1)) == seat and id in peek.get("cards",[]):
				if not peek.has("deck"):
					return false
				var source: Array = decks[str(peek.deck)]
				if not source.has(id): return false
				var dest: String = str(a.get("dest",""))
				if not dest in ["top","bottom","hand","item","discard"]: return false
				source.erase(id); peek.cards.erase(id)
				match dest:
					"top": source.append(id)
					"bottom": source.push_front(id)
					"hand": hands[seat].append(id)
					"item": _gain_item(seat, id)
					"discard": discards[str(peek.deck)].append(id)
				_note(name_of(seat) + " перемещает просмотренную карту · " + {"top":"наверх колоды","bottom":"под низ колоды","hand":"в руку","item":"в предметы","discard":"в сброс"}.get(dest,dest)); ok = true

		"loot":
			if _card_automation_enabled() and int(a.get("card", -1)) == 469 and not stack.any(func(e): return e.kind == "loot"):
				return false
			if _card_automation_enabled() and (int(a.get("card", -1)) in CardAutomation.REROLL_LOOT or int(a.get("card", -1)) == 621) and not stack.any(func(e): return e.kind in ["roll", "effect_roll"]):
				return false
			if _card_automation_enabled() and int(a.get("card", -1)) in CardAutomation.CANCEL_LOOT and not stack.any(func(e): return e.kind == "loot" or (e.kind == "item" and not bool(e.get("conditional", false)) and not e.has("automation_context"))):
				return false
			if phase in ["turn","priority","battle_roll","death"] and not dead[seat] and (from_top20 or a.get("card",-1) in hands[seat]):
				if _card_automation_enabled() and _room_has20(814) and int(_room_loot_plays.get(seat, 0)) >= 1: return false
				if seat!=current and FSData.response_kind(int(a.card))=="own_turn": return false
				if bool(_unlimited_loot13.get(seat, false)): pass
				elif seat == current and free_loot > 0: free_loot -= 1
				elif int(_bonus_loot_plays[seat]) > 0: _bonus_loot_plays[seat] = int(_bonus_loot_plays[seat]) - 1
				elif character_ready[seat]:
					if _card_automation_enabled() and _room_has20(814) and int(_room_activations.get(seat, 0)) >= 1: return false
					character_ready[seat] = false
					_room_activations[seat] = int(_room_activations.get(seat, 0)) + 1
				else: return false
				var resume: String = phase if phase != "priority" else _after_stack
				var id: int = int(a.card)
				if from_top20:
					decks.loot.pop_back()
				else:
					hands[seat].erase(id)
				_push({"kind":"loot","card":id,"owner":seat}, resume)
				ok = true
				_room_loot_plays[seat] = int(_room_loot_plays.get(seat, 0)) + 1
				_copy_loot14(seat, id)
				_emit_passives("loot_play", {"seat": seat, "card": id})
		"character":
			if phase not in ["turn", "priority", "battle_roll", "death"] or dead[seat] or not bool(character_ready[seat]):
				return false
			if _room_has20(814) and int(_room_activations.get(seat, 0)) >= 1:
				return false
			character_ready[seat] = false
			_room_activations[seat] = int(_room_activations.get(seat, 0)) + 1
			_push({"kind": "character_loot", "card": int(chars[seat]), "owner": seat}, _after_stack if phase == "priority" else phase)
			ok = true
		"mushroom_counter20":
			if phase not in ["turn", "priority", "battle_roll", "death"] or dead[seat] or not bool(character_ready[seat]) or _item_count(seat, 5) <= 0:
				return false
			if _room_has20(814) and int(_room_activations.get(seat, 0)) >= 1:
				return false
			character_ready[seat] = false
			_room_activations[seat] = int(_room_activations.get(seat, 0)) + 1
			_push({"kind": "mushroom_counter20", "card": int(chars[seat]), "owner": seat}, _after_stack if phase == "priority" else phase)
			ok = true
		"remove_spider15":
			if phase not in ["turn", "priority", "battle_roll", "death"] or dead[seat] or not bool(character_ready[seat]) or int(_spider_tokens15.get(seat, 0)) <= 0:
				return false
			if seat != current and (not off_turn_open(seat) or _item_count(current, 256) > 0):
				return false
			if _room_has20(814) and int(_room_activations.get(seat, 0)) >= 1:
				return false
			character_ready[seat] = false
			_room_activations[seat] = int(_room_activations.get(seat, 0)) + 1
			_spider_tokens15[seat] = int(_spider_tokens15[seat]) - 1
			ok = true
		"attack_familiar15":
			ok = _attack_familiar15(seat, int(a.get("index", -1)))
		"inspect_item13":
			if seat != current or _item_count(seat, 173) == 0 or phase not in ["turn", "priority", "battle_roll", "death"]: return false
			_begin_resolving({"kind":"item","card":173,"owner":seat,"conditional":true,"automation_context":"inspect","_resume":_after_stack if phase=="priority" else phase})
			_advance_card_automation(); ok = true
		"activate", "room_activate20":
			if _card_automation_enabled() and _room_has20(814) and int(_room_activations.get(seat, 0)) >= 1: return false
			var item := _activation_source20(seat, a, kind == "room_activate20")
			if phase in ["turn","priority","battle_roll","death"] and not dead[seat] and not item.is_empty():
				var id21: int = int(item.id)
				var paid21: bool = id21 in [44, 50] and str(a.get("ability", "")) == "paid"
				if _card_automation_enabled() and id21 in CardAutomation.Packet21.IDS:
					if id21 not in CardAutomation.Packet21.ACTIVATED:
						return false
					if id21 == 63 and (battle >= 0 or battle_player >= 0):
						return false
					if (id21 == 35 and int(hp[seat]) < 1) or (id21 == 42 and int(item.counters) < 6) or (id21 == 47 and int(item.counters) < 1) or (id21 == 55 and int(item.counters) < 3) or (id21 == 50 and paid21 and int(item.counters) < 2):
						return false
					if (id21 == 48 and int(coins[seat]) < 4) or (id21 == 44 and paid21 and int(coins[seat]) < 7):
						return false
				if _card_automation_enabled() and int(item.id) == 1 and (_item_kind20(item) != "tap" or int(coins[seat]) < 3):
					return false
				if _card_automation_enabled() and int(item.id) == 5 and int(item.counters) <= 0:
					return false
				if _card_automation_enabled() and int(item.id) == 10 and int(item.counters) < 2:
					return false
				if _card_automation_enabled() and int(item.id) in CardAutomation.Treasure20.IDS and int(item.id) not in CardAutomation.Treasure20.ACTIVATED:
					return false
				if _card_automation_enabled() and int(item.id) in TrinketCards.IDS:
					return false
				if _card_automation_enabled() and int(item.id) in TreasureCards.IDS and int(item.id) not in [38, 69, 77]:
					return false
				if _card_automation_enabled() and int(item.id) in ActiveCards.IDS and int(item.id) not in ActiveCards.ACTIVATED:
					return false
				if _card_automation_enabled() and int(item.id) in SecondaryCards.IDS and int(item.id) not in SecondaryCards.ACTIVATED:
					return false
				if _card_automation_enabled() and int(item.id) == 123 and not stack.any(func(e): return e.kind == "roll"):
					return false
				if _card_automation_enabled() and int(item.id) == 110 and hands[seat].is_empty():
					return false
				if _card_automation_enabled() and int(item.id) in CardAutomation.Treasure12.IDS and int(item.id) not in CardAutomation.Treasure12.ACTIVATED: return false
				if _card_automation_enabled() and int(item.id) in CardAutomation.Treasure13.IDS and int(item.id) not in CardAutomation.Treasure13.ACTIVATED: return false
				if _card_automation_enabled() and int(item.id) in CardAutomation.Treasure14.IDS and int(item.id) not in CardAutomation.Treasure14.ACTIVATED:
					return false
				if _card_automation_enabled() and int(item.id) in [216, 219] and int(coins[seat]) < (3 if int(item.id) == 216 else 10):
					return false
				if _card_automation_enabled() and int(item.id) == 217 and hands[seat].is_empty():
					return false
				if _card_automation_enabled() and int(item.id) in [233, 244] and not stack.any(func(e): return e.kind in ["roll", "effect_roll"] and (int(item.id) == 233 or (e.kind != "roll" and not _rerolls_attack(e)))):
					return false
				if _card_automation_enabled() and int(item.id) == 208 and not stack.any(func(e): return e.kind == "item" and not bool(e.get("conditional", false)) and not e.has("automation_context")):
					return false
				if _card_automation_enabled() and int(item.id) == 241 and shop.all(func(id): return int(id) < 0) and not items.any(func(row): return row.any(func(entry): return not is_same(entry, item) and not bool(entry.eternal))):
					return false
				if _card_automation_enabled() and int(item.id) == 171 and items[seat].filter(func(e): return not bool(e.eternal)).size() < 2: return false
				if _card_automation_enabled() and int(item.id) == 178 and int(coins[seat]) < 5: return false
				if _card_automation_enabled() and int(item.id) == 180 and int(item.counters) < 1: return false
				if _card_automation_enabled() and int(item.id) == 204 and not stack.any(func(e): return e.kind in ["roll","effect_roll"]): return false
				if _card_automation_enabled() and int(item.id) in [126, 162] and not stack.any(func(e): return e.kind in ["roll", "effect_roll"]): return false
				if _card_automation_enabled() and int(item.id) == 125 and hands[seat].is_empty(): return false
				if _card_automation_enabled() and int(item.id) == 157 and not items[seat].any(func(e): return int(e.id) != 157 and not bool(e.eternal)): return false
				if _card_automation_enabled() and int(item.id) == 160 and int(coins[seat]) < 4: return false
				if _card_automation_enabled() and int(item.id) in CardAutomation.Packet15.IDS and int(item.id) not in CardAutomation.Packet15.ACTIVATED:
					return false
				if _card_automation_enabled() and int(item.id) == 252 and stack.any(func(e): return e.kind in ["roll", "effect_roll"]):
					return false
				var kill_mode15 := _card_automation_enabled() and int(item.id) == 248 and str(a.get("ability", "")) == "kill"
				if kill_mode15 and int(item.counters) < 3:
					return false
				var tap := bool(a.get("tap", true))
				if _card_automation_enabled() and id21 in CardAutomation.Packet21.IDS:
					tap = id21 not in [35, 42, 48, 55] and not paid21
				if _card_automation_enabled() and int(item.id) == 1:
					tap = true
				if _card_automation_enabled() and int(item.id) in [5, 10]:
					tap = false
				if _card_automation_enabled() and int(item.id) in CardAutomation.Treasure14.ACTIVATED:
					tap = int(item.id) not in [216, 217, 219]
				if _card_automation_enabled() and int(item.id) in CardAutomation.Treasure12.ACTIVATED: tap = int(item.id) not in [125, 157, 160]
				if _card_automation_enabled() and int(item.id) in CardAutomation.Treasure13.ACTIVATED: tap = int(item.id) not in [171,178,180]
				if _card_automation_enabled() and int(item.id) in CardAutomation.Packet15.ACTIVATED:
					tap = not kill_mode15
				if tap and item.tapped: return false
				if _card_automation_enabled() and int(item.id) in [101, 119]:
					var cost := 5 if int(item.id) == 101 else 3
					if int(coins[seat]) < cost:
						return false
					coins[seat] = int(coins[seat]) - cost
					bank += cost
				if _card_automation_enabled() and int(item.id) == 85:
					if int(item.counters) < 3 or discards.loot.is_empty():
						return false
					item.counters = int(item.counters) - 3
				if _card_automation_enabled() and int(item.id) == 69:
					if int(coins[seat]) < 4:
						return false
					coins[seat] = int(coins[seat]) - 4
					bank += 4
				if kill_mode15:
					item.counters = int(item.counters) - 3
				if _card_automation_enabled() and int(item.id) == 10:
					item.counters = int(item.counters) - 2
				if _card_automation_enabled() and int(item.id) == 5:
					item.counters = int(item.counters) - 1
				if _card_automation_enabled() and int(item.id) == 1:
					coins[seat] = int(coins[seat]) - 3
					bank += 3
				if _card_automation_enabled() and id21 in CardAutomation.Packet21.IDS:
					if id21 == 35:
						hp[seat] = int(hp[seat]) - 1
					if id21 in [42, 55] or (id21 == 50 and paid21):
						item.counters = int(item.counters) - (6 if id21 == 42 else 3 if id21 == 55 else 2)
					var cost21 := 4 if id21 == 48 else 7 if id21 == 44 and paid21 else 0
					coins[seat] = int(coins[seat]) - cost21
					bank += cost21
				if tap: item.tapped = true
				var resume: String = phase if phase != "priority" else _after_stack
				if _card_automation_enabled() and int(item.id) in [125, 157, 171, 217]:
					_begin_resolving({"kind": "item", "card": int(item.id), "owner": seat, "source": item, "automation_context": "activation_cost", "_resume": resume})
					_advance_card_automation()
				else:
					if _card_automation_enabled() and int(item.id) in [216, 219]:
						var paid := 3 if int(item.id) == 216 else 10
						coins[seat] = int(coins[seat]) - paid
						bank += paid
					if _card_automation_enabled() and int(item.id) == 178:
						coins[seat] = int(coins[seat])-5; bank += 5
					if _card_automation_enabled() and int(item.id) == 180: item.counters = int(item.counters)-1
					if _card_automation_enabled() and int(item.id) == 160:
						coins[seat] = int(coins[seat]) - 4; bank += 4
					var activated := {"kind":"item","card":int(item.id),"owner":seat,"source":item}
					if paid21:
						activated["automation_context"] = "paid21"
					if kill_mode15:
						activated["automation_context"] = "paid15"
					_push(activated, resume)
					_room_activations[seat] = int(_room_activations.get(seat, 0)) + 1
					_emit_passives("activate", {"seat": seat, "card": int(item.id)})
				ok = true
		"item_trigger":
			var index: int = int(a.get("item", -1))
			if phase in ["turn", "priority", "battle_roll", "death"] and index >= 0 and index < items[seat].size():
				var id: int = int(items[seat][index].id)
				if not FSData.manual_item_trigger(id) or (_card_automation_enabled() and (id in CardAutomation.Treasure12.IDS or id in CardAutomation.Treasure13.IDS or id in CardAutomation.Treasure14.IDS or id in CardAutomation.Packet15.IDS or id in CardAutomation.Treasure20.IDS or id in CardAutomation.Packet21.IDS)):
					return false
				# Условие текста подтверждают люди; это не новая активация и не поворот.
				var resume: String = _after_stack if phase == "priority" else phase
				_push({"kind": "item", "card": id, "owner": seat, "conditional": true}, resume)
				ok = true
		"buy":
			var slot: int = int(a.get("slot",-2))
			var valid_slot: bool = a.has("slot") and slot >= -1 and slot < shop.size()
			valid_slot = valid_slot or (slot == -2 and a.has("slot") and _item_count(seat, 473) > 0 and not discards.treasure.is_empty())
			if phase == "turn" and seat == current and not bought and valid_slot and coins[seat] >= _purchase_cost(seat, slot):
				if _card_automation_enabled() and _item_count(seat, 23) > 0:
					_start_stairway20(seat)
				else:
					buy_left -= 1
					bought = buy_left <= 0
					_push({"kind":"purchase","owner":seat,"slot":slot,"cost":_purchase_cost(seat, slot)},"turn")
				ok = true
		"attack":
			if not _forced_slots14().is_empty() and int(a.get("slot", -1)) not in _forced_slots14():
				return false
			var slot: int = int(a.get("slot",-2))
			if _card_automation_enabled() and slot >= 0 and attack_left <= _optional_blind17:
				return false
			if phase == "turn" and seat == current and (not attacked or (_gold_deck_attacks and slot == -1)) and slot >= -1 and slot < monsters.size():
				if _required_player_remaining() > 0 and _forced_deck_remaining() == 0:
					return false
				if _forced_deck_remaining() > 0 and slot != -1:
					return false
				if slot >= 0 and _untargetable(int(monsters[slot].id)):
					return false
				var forced_boss_available := _forced_bosses.any(func(id): return monsters.any(func(m): return int(m.id) == int(id) and hp[seat] > 0))
				if forced_boss_available and (slot < 0 or int(monsters[slot].id) not in _forced_bosses): return false
				if not _lust_pending.is_empty(): return false
				if slot == -1 and not monsters.is_empty():
					var over: int = clampi(int(a.get("over", 0)), 0, monsters.size() - 1)
					if int(monsters[over].id) in [272, 279, 299, 312, 913, 914] or monsters[over].has("virtual_zone15"):
						return false
				if not _pay_attack_tax(seat): return false
				if forced_boss_available: _forced_bosses.clear()
				if _room_extra_attack > 0 and attack_left == 1 and not (_gold_deck_attacks and slot == -1):
					_room_extra_attack_used = true
					_room_extra_attack = 0
				if not (_gold_deck_attacks and slot == -1):
					attack_left -= 1
				attacked = attack_left <= 0
				if slot == -1:
					deck_attacks += 1
				_next_attack_token += 1
				_push({"kind":"attack","owner":seat,"slot":slot,"over":int(a.get("over",0)), "attack_token": _next_attack_token},"turn"); ok = true
				_emit_passives("attack_declared", {"seat": seat, "slot": slot, "token": _next_attack_token})
		"effect_roll":
			if phase == "effect" and seat == actor():
				if _card_automation_active() and not resolving.has("reroll_request") and str(_card_step().get("op", "")) != "auto_roll":
					return false
				if not resolving.has("reroll_request") and resolving.has("auto_reward") and not bool(resolving.get("requires_reward_roll", false)) and not bool(resolving.get("post_reward_wait", false)) and not (bool(resolving.auto_reward.get("manual_death", false)) and not bool(resolving.get("death_text_done", false))):
					return false
				if not resolving.has("reroll_request") and resolving.has("auto_reward") and resolving.has("reward_roll") and not bool(resolving.get("post_reward_wait", false)):
					return false
				if resolving.has("spawn_card"):
					return false
				var reroll_request: Dictionary = resolving.get("reroll_request", {})
				resolving.erase("reroll_request")
				var multi_subroll: bool = (int(resolving.get("card", -1)) == 140 and str(resolving.get("automation_context", "")) == "multi_roll") or (int(resolving.get("card", -1)) == 258 and str(resolving.get("automation_context", "")) == "minimum") or (int(resolving.get("card", -1)) == 328 and str(resolving.get("automation_context", "")) == "double17")
				last_roll = _roll_die(seat) if multi_subroll else _card_die(seat, bool(reroll_request.get("attack", false)))
				roll_no += 1
				stats_rolls.append({"seat":seat,"faces":[last_roll]})
				paused_effects.append({"effect":resolving,"resume":_after_stack,"peek":peek.duplicate(true),"roller":seat})
				resolving = {}; peek = {}
				var roll_effect := {"kind":"effect_roll","value":last_roll,"owner":seat, "multi_bonus12": _multi_raw_bonus, "suppress_passives": multi_subroll}
				if not reroll_request.is_empty():
					roll_effect["reroll_index"] = int(reroll_request.index)
					if reroll_request.has("target_token"):
						roll_effect["reroll_target_token"] = int(reroll_request.target_token)
					roll_effect["attack_reroll"] = bool(reroll_request.get("attack", false)) or _rerolls_attack(roll_effect)
					var target_index: int = _reroll_index(roll_effect)
					if target_index >= 0:
						roll_effect["reroll_target_token"] = _roll_token(stack[target_index])
				_push(roll_effect,"effect"); ok = true
		"roll":
			if phase == "battle_roll" and seat == _battle_roller15():
				if _prepare_neighbors15():
					ok = true
				else:
					last_roll = _card_die(seat, true)
					roll_no += 1
					stats_rolls.append({"seat": seat, "faces": [last_roll]})
					_push({"kind": "roll", "value": last_roll, "owner": seat, "multi_bonus12": _multi_raw_bonus}, "battle_roll")
					ok = true
		"effect":
			if phase == "effect" and seat == int(resolving.owner) and (not _card_automation_active() or _host_manual): ok = _effect(a)
		"effect_done":
			if phase == "effect" and seat == int(resolving.owner):
				if _card_automation_active() and not _automation_internal and not _host_manual and not bool(resolving.get("automation_done", false)):
					return false
				if resolving.has("reward_winners") or resolving.has("reward_soul_targets") or resolving.has("reward_damage"):
					return false
				if resolving.has("spawn_card") or resolving.has("reroll_request"):
					return false
				if resolving.has("auto_reward") and not bool(resolving.get("reward_ready", false)):
					if bool(resolving.get("death_text_done", false)) and bool(resolving.get("requires_reward_roll", false)) and not resolving.has("reward_roll"):
						return false
					if bool(resolving.get("post_reward_wait", false)):
						resolving["post_text_done"] = true
						resolving.erase("post_reward_wait")
					else:
						resolving["death_text_done"] = true
					_advance_auto_reward()
					revision += 1
					_check_bonuses()
					_check_win()
					return true
				if bool(resolving.get("requires_reward_roll", false)) and not resolving.has("reward_roll"):
					return false
				if resolving.has("spawn_card"):
					return false
				if resolving.has("reroll_request"):
					return false
				if resolving.kind == "event" and str(FSData.card(int(resolving.card)).lua.get("type","")) == "curse" and not bool(resolving.get("attached",false)): return false
				var effect := resolving.duplicate(); resolving = {}; peek = {}
				if effect.has("_resume"):
					_after_stack = str(effect._resume)
				if effect.kind == "loot" and not bool(effect.get("loot_copy14", false)) and not bool(effect.get("under_deck", false)) and not effect.has("given_to") and not bool(effect.get("kept_as_item", false)) and not bool(effect.get("deployed_monster20", false)):
					discards.loot.append(int(effect.card))
				if effect.kind == "event" and not bool(effect.get("attached",false)):
					discards.monster.append(int(effect.card))
				if effect.kind == "reward":
					_finish_monster_reward(effect)
					_after_auto_reward16(effect)
					if effect.has("reward_winner"):
						winner = int(effect.reward_winner)
						phase = "game_over"
						_note("Сердце Мамы: победитель — " + name_of(winner))
						revision += 1
						return true
				if bool(effect.get("refill_monsters", false)):
					_after_stack = "refill"
				if bool(effect.get("end_turn_after", false)):
					# Святой покров отменяет всё неразрешённое и завершает ход спасённого.
					_cancel_unresolved()
					_death_queue.erase(current)
					_end_after_deaths = true
					_resume_after_deaths()
				else:
					_continue_stack()
				ok = true
		"death":
			if phase == "death" and seat == actor():
				var loot: int = int(a.get("loot", -1))
				var item: int = int(a.get("item", -1))
				var shadow: Dictionary = _shadow_penalty15.get(seat, {})
				if not shadow.is_empty() and not shadow.item.is_empty():
					item = items[seat].find(shadow.item)
				var keep_resources: bool = _item_count(seat, 523) > 0
				var penalty_card20 := -1
				var destroyable := []
				for i in items[seat].size():
					if not items[seat][i].eternal: destroyable.append(i)
				if not keep_resources and not hands[seat].is_empty() and not hands[seat].has(loot): return false
				item = _death_item16(seat, item)
				if not destroyable.is_empty() and not destroyable.has(item): return false
				if not keep_resources and hands[seat].has(loot):
					hands[seat].erase(loot)
					if not shadow.is_empty():
						hands[int(shadow.receiver)].append(loot)
					else:
						discards.loot.append(loot)
				if item >= 0 and destroyable.has(item):
					penalty_card20 = int(items[seat][item].get("physical_id13", items[seat][item].id))
					if _lust_victims.has(seat):
						var receiver: int = int(_lust_victims[seat])
						items[receiver].append(_remove_item(seat, item))
					elif _card_automation_enabled() and monsters.any(func(m): return int(m.id) == 272):
						var moved := _remove_item(seat, item, true)
						shop.append(int(moved.id))
					else:
						_destroy_item(seat, item)
				if not keep_resources:
					if not shadow.is_empty():
						_transfer_coins(seat, int(shadow.receiver), 1)
					else:
						_gain_coins(seat, -1)
				_shadow_penalty15.erase(seat)
				character_ready[seat] = false
				dead[seat] = true
				if curses[seat].has(706):
					_curse_of_loss(seat)
				discards.monster.append_array(curses[seat]); curses[seat].clear()
				for card: Dictionary in items[seat]: card.tapped = true
				_death_queue.pop_front(); _note(name_of(seat) + " получает штраф за смерть")
				_end_after_deaths = _end_after_deaths or seat == current
				phase = _death_resume
				_emit_passives("after_death", {"seat": seat, "penalty_card20": penalty_card20})
				_resume_after_deaths()
				ok = true
		"discard":
			var id: int = int(a.get("card",-1))
			if phase == "discard" and seat == current and hands[seat].has(id):
				hands[seat].erase(id); discards.loot.append(id); ok = true
				if hands[seat].size() <= _discard_limit: _end_turn()
		"end":
			if phase == "turn" and seat == current and _forced_deck_remaining() == 0 and _required_player_remaining() == 0 and not _must_attack() and not _encounter_must_attack():
				_end_turn()
				ok = true
		"trade":
			var target: int = int(a.get("target",-1)); var amount: int = int(a.get("amount",0))
			if phase in ["turn","priority"] and target >= 0 and target < players.size() and target != seat and amount > 0 and amount <= coins[seat]:
				_transfer_coins(seat, target, amount); _note("%s → %s: %d¢" % [name_of(seat),name_of(target),amount]); ok = true
		"room":
			if phase == "turn" and seat == current and dlc and (a.has("index") or _room_can_discard()):
				if a.has("index"):
					ok = _replace_room20(int(a.index))
				else:
					if room >= 0:
						discards.room.append(room)
					room = _draw("room")
					if room == 810:
						_reset_room_goals()
					_note("Новая комната: " + FSData.title(room))
					ok = true
	if ok:
		_refresh_passive_stats()
		revision += 1; _check_bonuses(); _check_win()
		if not next_action.is_empty() and kind in ["effect_done","death"]: _finish_responses()
	return ok
## Глубокая копия состояния для пробных действий (legal_actions, фаззер).
## Общие ссылки source/pending сохраняются внутри копии, отдельно от исходной партии.
func clone() -> FSRules:
	var copy: FSRules = get_script().new()
	var memo: Dictionary = {}
	for property: Dictionary in get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var key: String = property.name
		var value = get(key)
		if value is Array or value is Dictionary:
			copy.set(key, _clone_container(value, memo))
		elif not value is Object:
			copy.set(key, value)
	copy._rng.seed = _rng.seed
	copy._rng.state = _rng.state
	# Внешнее замыкание нельзя скопировать: оно может расходовать очередь исходной игры.
	# Все пробные клоны используют собственную копию RNG, включая anyone_can_act и фаззер.
	copy.roll_source = Callable()
	return copy

## Глубокое копирование с сохранением связей. Хеш задаёт корзину, is_same различает
## разные контейнеры с одинаковым содержимым; поиск не сравнивает все карты партии.
func _clone_container(value: Variant, memo: Dictionary) -> Variant:
	if not (value is Array or value is Dictionary):
		return value
	var fingerprint: int = hash(value)
	var bucket: Array = memo.get(fingerprint, [])
	for pair: Array in bucket:
		if is_same(pair[0], value):
			return pair[1]
	var copied: Variant = value.duplicate(false)
	bucket.append([value, copied])
	memo[fingerprint] = bucket
	if value is Array:
		for index in value.size():
			copied[index] = _clone_container(value[index], memo)
	else:
		for key in value:
			copied[key] = _clone_container(value[key], memo)
	return copied

## Единый источник «что сейчас можно»: кандидаты, принятые пробным действием на копии.
func legal_actions(seat: int) -> Array:
	return preload("res://games/four_souls/logic/fs_legal.gd").legal(self, seat)
## Проклятие потери: при смерти уничтожить одну свою душу — самую дешёвую, при равенстве последнюю.
func _curse_of_loss(seat: int) -> void:
	var chosen := -1
	for index in soul_cards[seat].size():
		var entry: Dictionary = soul_cards[seat][index]
		if FSData.card(int(entry.id)).get("kind", "") == "character":
			continue
		if chosen < 0 or int(entry.value) <= int(soul_cards[seat][chosen].value):
			chosen = index
	if chosen < 0:
		return
	var lost: Dictionary = soul_cards[seat].pop_at(chosen)
	souls[seat] = maxi(0, int(souls[seat]) - int(lost.value))
	var pile: String = {"monster": "monster", "loot": "loot", "treasure": "treasure"}.get(str(FSData.card(int(lost.id)).get("kind", "")), "")
	if not pile.is_empty():
		discards[pile].append(int(lost.id))
	_note("Проклятие потери: %s теряет душу %s" % [name_of(seat), FSData.title(int(lost.id))])

func get_view(seat: int, _show_all: bool = false) -> Dictionary:
	var card_choices: Array = []
	var card_choice_previews: Array = []
	if phase == "effect" and seat == _card_choice_owner():
		for choice: Dictionary in _card_choices():
			card_choices.append(str(choice.label))
			card_choice_previews.append(int(choice.arg.get("card", -1)))
	var public := []
	var off_turn_left := maxf(0.0, OFF_TURN_WINDOW - _turn_time())
	for i in players.size():
		public.append({"name":players[i].name,"char":chars[i],"items":items[i].duplicate(true),"hp":hp[i],"max_hp":max_hp[i],"attack":attack[i],"coins":coins[i],"souls":souls[i],"hand_count":hands[i].size(),"souls_cards":soul_cards[i].duplicate(true),"curses":curses[i].duplicate(),"ready":character_ready[i],"dead":dead[i], "respawn_egg17":_eggs_respawn17.has(i)})
		public.back()["eggs"] = _egg_count("player", i)
		public.back()["skipped_turns"] = int(skipped_turns[i])
		for owner in players.size():
			if owner != i and _item_count(owner, 128) > 0:
				public.back()["hand"] = hands[i].duplicate()
				break
	var counts := {}
	for key in decks: counts[key] = decks[key].size()
	# Служебные маркеры возврата содержат приватный peek и не передаются клиентам.
	var visible_stack: Array = []
	for entry: Dictionary in stack:
		if entry.kind in ["resume_effect", "resume_deaths"]:
			continue
		var public_entry := {}
		for key in ["kind", "owner", "card", "slot", "target", "value", "hit", "damage", "cost"]:
			if entry.has(key):
				public_entry[key] = entry[key]
		visible_stack.append(public_entry)
	var visible_monsters := monsters.duplicate(true)
	var bonus_targets := {}
	for id in bonuses:
		if int(id) in [692, 693, 694, 695, 696]:
			bonus_targets[int(id)] = _bonus_targets(int(id))
	for entry: Dictionary in visible_monsters:
		entry["eggs"] = _egg_count("monster", int(entry.id))
		entry["untargetable"] = _untargetable(int(entry.id))
		entry.dc = _monster_evasion(entry)
		entry.at = _monster_attack(entry)
	return {"extra_rooms20": _extra_rooms20.duplicate(true), "loot_top20": int(decks.loot.back()) if not decks.loot.is_empty() and _top_loot20.values().has(turn_serial) else -1, "can_top_loot20": int(_top_loot20.get(seat, -1)) == turn_serial, "die_sides20": 8 if _d8_next20.has(actor()) else 6, "last_die_sides20": _last_die_sides20, "last_raw_die20": _last_raw_die20, "battle_roller15": _battle_roller15(), "shadow_item15": items[seat].find(_shadow_penalty15[seat].item) if _shadow_penalty15.has(seat) and not _shadow_penalty15[seat].item.is_empty() else -1, "spider_tokens15": int(_spider_tokens15.get(seat, 0)), "familiar_targets15": _familiar_targets15(), "player_attack_defense16": _player_defenses17(), "blind_only17": attack_left > 0 and attack_left <= _optional_blind17, "forced_monster_slots": _forced_slots14(), "unlimited_loot":bool(_unlimited_loot13.get(seat,false)),"card_choice_previews":card_choice_previews,"card_choices":card_choices,"card_automated":_card_automation_active(),"card_roll_wait":str(_card_step().get("op", "")) == "auto_roll" and not resolving.has("automation_roll"),"players":public,"seat":seat,"discard_choice":discard_choice.duplicate(true),"battle_player":battle_player,"required_player_attacks":_required_player_remaining(),"player_attack_targets":_permitted_player_attack_targets(),"forced_deck_attacks":_forced_deck_remaining(),"spawn_slots":_peep_spawn_slots(),"effect_pending":_pending_manual_passives(),"starting_pending":phase=="priority" and _after_stack=="starting_continue","starting_options":_starting_choices[0].cards.duplicate() if phase=="starting_item" and not _starting_choices.is_empty() and seat==actor() else [],"phase":phase,"current":current,"actor":actor(),"round_no":round_no,"dlc":dlc,"hand":hands[seat].duplicate() if seat >= 0 and seat < players.size() else [],"monsters":visible_monsters,"shop":shop.duplicate(),"shop_price":_purchase_cost(seat if seat >= 0 else current,0),"discard_treasure":int(discards.treasure.back()) if seat >= 0 and _item_count(seat,473)>0 and not discards.treasure.is_empty() else -1,"room":room,"bonuses":bonuses.duplicate(),"bonus_targets":bonus_targets,"bonus_progress":bonus_progress.duplicate(),"claimed":claimed.duplicate(),"stack":visible_stack,"resolving":resolving.duplicate(),"battle":battle,"roll_no":roll_no,"last_roll":last_roll,"log":log.duplicate(),"winner":winner,"free_loot":free_loot,"bonus_loot_plays":int(_bonus_loot_plays[seat]) if seat >= 0 else 0,"gold_deck_attacks":_gold_deck_attacks,"bought":bought,"attacked":attacked,"counts":counts,"bank":bank,"reward_boost":reward_boost,"revision":revision,"peek":peek.duplicate(true) if int(peek.get("owner",-2)) == seat or bool(peek.get("public", false)) else {},"death_actor":int(_death_queue[0]) if not _death_queue.is_empty() else -1,"discard_limit":_discard_limit,"off_turn_left":off_turn_left,"response_window":RESPONSE_WINDOW}
