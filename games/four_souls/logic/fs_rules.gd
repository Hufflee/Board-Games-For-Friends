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
const OFF_TURN_KINDS := ["loot", "activate"]  # «разыграть свою карту» вне своего хода
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
	if kind in OFF_TURN_KINDS and not off_turn_open(seat):
		return false
	# Следующая операция того же ручного эффекта сначала разрешает его пассивы.
	# Чужой ручной ответ не пропускаем: маршрут открыт только для стека пассивов.
	if _pending_manual_passives() and kind in ["effect", "effect_done", "effect_roll", "place_bloat"]:
		if seat != int(resolving.owner):
			return false
		_finish_responses()
		if phase == "effect" and seat == int(resolving.get("owner", -1)):
			return action(seat, kind, arg)
		# Жест закрыл ответы, но теперь разрешается чужой (вложенный) ручной эффект.
		revision += 1
		return true
	if phase == "priority" and _after_stack == "starting_continue":
		if kind != "finish_start" or seat != current:
			return false
		_finish_responses()
		revision += 1
		return true
	_refresh_passive_stats()
	if seat != current and kind in ["loot", "activate"] and _item_count(current, 256) > 0:
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
	var ok := false
	match kind:
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
			var target: int = int(a.get("target", -1))
			if phase != "turn" or seat != current or battle >= 0 or battle_player >= 0 or required_player_attacks <= 0:
				return false
			if target not in _player_attack_targets() or dead[current] or hp[current] <= 0:
				return false
			required_player_attacks -= 1
			_push({"kind": "player_attack", "owner": current, "card": 268, "target": target}, "turn")
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
			var slot: int = int(a.get("slot", -1))
			if phase in ["turn", "priority", "battle_roll", "death"] and not dead[seat] and slot >= 0 and slot < monsters.size():
				var resume: String = _after_stack if phase == "priority" else phase
				_push({"kind": "monster_trigger", "card": int(monsters[slot].id), "owner": seat, "slot": slot}, resume)
				ok = true
		"claim":
			var id: int = int(a.get("card",-1))
			if phase in ["turn","priority"] and bonuses.has(id) and not claimed.has(id):
				if room == 779 or curses[seat].has(744):
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
				claimed.append(id); souls[recipient] += 1; soul_cards[recipient].append({"id":int(id),"value":1}); _note(name_of(recipient) + " получает " + FSData.title(id)); ok = true
		"peek_take":
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
			if phase in ["turn","priority","battle_roll","death"] and not dead[seat] and a.get("card",-1) in hands[seat]:
				if seat!=current and FSData.response_kind(int(a.card))=="own_turn": return false
				if seat == current and free_loot > 0: free_loot -= 1
				elif character_ready[seat]: character_ready[seat] = false
				else: return false
				var resume: String = phase if phase != "priority" else _after_stack
				var id: int = int(a.card); hands[seat].erase(id); _push({"kind":"loot","card":id,"owner":seat}, resume); ok = true
		"activate":
			var i: int = int(a.get("item",-1))
			if phase in ["turn","priority","battle_roll","death"] and not dead[seat] and i >= 0 and i < items[seat].size():
				var item: Dictionary = items[seat][i]
				var tap := bool(a.get("tap", true))
				if tap and item.tapped: return false
				if tap: item.tapped = true
				var resume: String = phase if phase != "priority" else _after_stack
				_push({"kind":"item","card":int(item.id),"owner":seat},resume); ok = true
				_emit_passives("activate", {"seat": seat, "card": int(item.id)})
		"buy":
			var slot: int = int(a.get("slot",-2))
			var valid_slot: bool = a.has("slot") and slot >= -1 and slot < shop.size()
			valid_slot = valid_slot or (slot == -2 and a.has("slot") and _item_count(seat, 473) > 0 and not discards.treasure.is_empty())
			if phase == "turn" and seat == current and not bought and valid_slot and coins[seat] >= _purchase_cost(seat, slot):
				buy_left -= 1; bought = buy_left <= 0
				_push({"kind":"purchase","owner":seat,"slot":slot,"cost":_purchase_cost(seat, slot)},"turn"); ok = true
		"attack":
			var slot: int = int(a.get("slot",-2))
			if phase == "turn" and seat == current and not attacked and slot >= -1 and slot < monsters.size():
				if _required_player_remaining() > 0 and _forced_deck_remaining() == 0:
					return false
				if _forced_deck_remaining() > 0 and slot != -1:
					return false
				if slot >= 0 and _untargetable(int(monsters[slot].id)):
					return false
				attack_left -= 1; attacked = attack_left <= 0
				if slot == -1:
					deck_attacks += 1
				_push({"kind":"attack","owner":seat,"slot":slot,"over":int(a.get("over",0))},"turn"); ok = true
		"effect_roll":
			if phase == "effect" and seat == actor():
				if resolving.has("spawn_card"):
					return false
				var reroll_request: Dictionary = resolving.get("reroll_request", {})
				resolving.erase("reroll_request")
				last_roll = _roll_die(); roll_no += 1
				stats_rolls.append({"seat":seat,"faces":[last_roll]})
				paused_effects.append({"effect":resolving.duplicate(true),"resume":_after_stack,"peek":peek.duplicate(true),"roller":seat})
				resolving = {}; peek = {}
				var roll_effect := {"kind":"effect_roll","value":last_roll,"owner":seat}
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
			if phase == "battle_roll" and seat == current:
				last_roll = _roll_die(); roll_no += 1
				stats_rolls.append({"seat":seat,"faces":[last_roll]})
				_push({"kind":"roll","value":last_roll,"owner":seat},"battle_roll"); ok = true
		"effect":
			if phase == "effect" and seat == int(resolving.owner): ok = _effect(a)
		"effect_done":
			if phase == "effect" and seat == int(resolving.owner):
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
				if effect.kind == "loot" and not bool(effect.get("under_deck", false)):
					discards.loot.append(int(effect.card))
				if effect.kind == "event" and not bool(effect.get("attached",false)):
					discards.monster.append(int(effect.card))
				if effect.kind == "reward":
					_finish_monster_reward(effect)
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
				var loot: int = int(a.get("loot",-1)); var item: int = int(a.get("item",-1))
				var keep_resources: bool = _item_count(seat, 523) > 0
				var destroyable := []
				for i in items[seat].size():
					if not items[seat][i].eternal: destroyable.append(i)
				if not keep_resources and not hands[seat].is_empty() and not hands[seat].has(loot): return false
				if not destroyable.is_empty() and not destroyable.has(item): return false
				if not keep_resources and hands[seat].has(loot): hands[seat].erase(loot); discards.loot.append(loot)
				if item >= 0 and destroyable.has(item):
					_destroy_item(seat, item)
				if not keep_resources:
					_gain_coins(seat, -1)
				character_ready[seat] = false
				dead[seat] = true
				if curses[seat].has(706):
					_curse_of_loss(seat)
				discards.monster.append_array(curses[seat]); curses[seat].clear()
				for card: Dictionary in items[seat]: card.tapped = true
				_death_queue.pop_front(); _note(name_of(seat) + " получает штраф за смерть")
				_end_after_deaths = _end_after_deaths or seat == current
				phase = _death_resume
				_emit_passives("after_death", {"seat": seat})
				_resume_after_deaths()
				ok = true
		"discard":
			var id: int = int(a.get("card",-1))
			if phase == "discard" and seat == current and hands[seat].has(id):
				hands[seat].erase(id); discards.loot.append(id); ok = true
				if hands[seat].size() <= _discard_limit: _end_turn()
		"end":
			if phase == "turn" and seat == current and _forced_deck_remaining() == 0 and _required_player_remaining() == 0 and not _must_attack():
				_end_turn()
				ok = true
		"trade":
			var target: int = int(a.get("target",-1)); var amount: int = int(a.get("amount",0))
			if phase in ["turn","priority"] and target >= 0 and target < players.size() and target != seat and amount > 0 and amount <= coins[seat]:
				coins[seat] -= amount; coins[target] += amount; _note("%s → %s: %d¢" % [name_of(seat),name_of(target),amount]); ok = true
		"room":
			if phase == "turn" and seat == current and dlc:
				if room >= 0: discards.room.append(room)
				room = _draw("room"); _note("Новая комната: " + FSData.title(room)); ok = true
	if ok:
		_refresh_passive_stats()
		revision += 1; _check_bonuses(); _check_win()
		if not next_action.is_empty() and kind in ["effect_done","death"]: _finish_responses()
	return ok
## Глубокая копия состояния для пробных действий (legal_actions, фаззер).
## Ссылки пассивов на предметы (source) в копии становятся отдельными словарями.
func clone() -> FSRules:
	var copy := FSRules.new()
	for property: Dictionary in get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var key: String = property.name
		var value = get(key)
		if value is Array or value is Dictionary:
			copy.set(key, value.duplicate(true))
		elif not value is Object:
			copy.set(key, value)
	copy._rng.seed = _rng.seed
	copy._rng.state = _rng.state
	copy.roll_source = roll_source
	return copy
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
	var public := []
	var off_turn_left := maxf(0.0, OFF_TURN_WINDOW - _turn_time())
	for i in players.size():
		public.append({"name":players[i].name,"char":chars[i],"items":items[i].duplicate(true),"hp":hp[i],"max_hp":max_hp[i],"attack":attack[i],"coins":coins[i],"souls":souls[i],"hand_count":hands[i].size(),"souls_cards":soul_cards[i].duplicate(true),"curses":curses[i].duplicate(),"ready":character_ready[i],"dead":dead[i]})
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
		entry["untargetable"] = _untargetable(int(entry.id))
		entry.dc = _monster_evasion(entry)
		entry.at = int(entry.at) + _monster_aura("deathshead") + (1 if room == 818 else 0)
		if curses[current].has(737):
			entry.at += 1
	return {"players":public,"seat":seat,"discard_choice":discard_choice.duplicate(true),"battle_player":battle_player,"required_player_attacks":_required_player_remaining(),"player_attack_targets":_player_attack_targets(),"forced_deck_attacks":_forced_deck_remaining(),"spawn_slots":_peep_spawn_slots(),"effect_pending":_pending_manual_passives(),"starting_pending":phase=="priority" and _after_stack=="starting_continue","starting_options":_starting_choices[0].cards.duplicate() if phase=="starting_item" and not _starting_choices.is_empty() and seat==actor() else [],"phase":phase,"current":current,"actor":actor(),"round_no":round_no,"dlc":dlc,"hand":hands[seat].duplicate() if seat >= 0 and seat < players.size() else [],"monsters":visible_monsters,"shop":shop.duplicate(),"shop_price":_purchase_cost(seat if seat >= 0 else current,0),"discard_treasure":int(discards.treasure.back()) if seat >= 0 and _item_count(seat,473)>0 and not discards.treasure.is_empty() else -1,"room":room,"bonuses":bonuses.duplicate(),"bonus_targets":bonus_targets,"bonus_progress":bonus_progress.duplicate(),"claimed":claimed.duplicate(),"stack":visible_stack,"resolving":resolving.duplicate(),"battle":battle,"roll_no":roll_no,"last_roll":last_roll,"log":log.duplicate(),"winner":winner,"free_loot":free_loot,"bought":bought,"attacked":attacked,"counts":counts,"bank":bank,"revision":revision,"peek":peek.duplicate(true) if int(peek.get("owner",-2)) == seat else {},"death_actor":int(_death_queue[0]) if not _death_queue.is_empty() else -1,"discard_limit":_discard_limit,"off_turn_left":off_turn_left,"response_window":RESPONSE_WINDOW}
