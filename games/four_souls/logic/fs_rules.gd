class_name FSRules
extends RefCounted
## Восемь мест и ручные эффекты оригинального стола. Хост ведёт колоды, приоритет,
## стек, бой, смерть и ресурсы; текст сложной карты выполняют люди через открытый журнал.
var players: Array = []
var dlc := false
var phase := "turn"
var current := 0
var priority := 0
var passes := 0
var next_action: Dictionary = {}
var stats_rolls: Array = []
var stats_risks: Array = []
var round_no := 1
var winner := -1
var revision := 0
var decks: Dictionary = {}
var discards: Dictionary = {}
var hands: Array = []
var items: Array = []
var chars: Array = []
var hp: Array = []
var max_hp: Array = []
var attack: Array = []
var coins: Array = []
var bank := 100
var souls: Array = []
var soul_cards: Array = []
var curses: Array = []
var character_ready: Array = []
var dead: Array = []
var free_loot := 1
var buy_left := 1
var attack_left := 1
var temporary_attack: Array = []
var bought := false
var attacked := false
var monsters: Array = []
var shop: Array = []
var room := -1
var bonuses: Array = []
var claimed: Array = []
var stack: Array = []
var resolving: Dictionary = {}
var paused_effects: Array = []
var battle := -1
var roll_no := 0
var last_roll := 0
var log: Array = []
var peek: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _after_stack := "turn"
var _death_queue: Array = []
var _death_resume := "turn"
var damage_shields: Array = []
var extra_turns: Array = []
var _ending_turn := false
var _discard_limit := 10
var _turn_resume := -1
var _end_after_deaths := false

## Брелоки остаются картами лута и после перехода в зону предметов.
func _discard_item(id: int) -> void:
	var kind := "loot" if FSData.card(id).get("kind", "") == "loot" else "treasure"
	discards[kind].append(id)

func _has_item(seat: int, key: String) -> int:
	var count := 0
	for entry: Dictionary in items[seat]:
		if FSData.card(int(entry.id)).get("key", "") == key:
			count += 1
	return count

func _damage_player(seat: int, amount: int) -> void:
	var blocked := mini(maxi(0, amount), int(damage_shields[seat]))
	damage_shields[seat] -= blocked
	hp[seat] -= maxi(0, amount) - blocked
	if blocked > 0:
		_note("Предотвращён урон: %s · %d" % [name_of(seat), blocked])

## Ауры учитывают только открытых живых монстров, а не накрытые карты.
func _monster_aura(key: String) -> int:
	var count := 0
	for entry: Dictionary in monsters:
		if int(entry.hp) > 0 and FSData.card(int(entry.id)).get("key", "") == key:
			count += 1
	return count

func _untargetable(id: int) -> bool:
	return FSData.card(id).get("key", "") in ["deathshead", "stoney"]

func _roll_passives(value: int) -> void:
	if value != 4:
		return
	var tumors := _monster_aura("cursedtumor")
	if tumors == 0:
		return
	_note("Проклятая опухоль: четвёрка наносит всем игрокам %d урона" % tumors)
	for seat in players.size():
		if not dead[seat]:
			_damage_player(seat, tumors)

func _cancel_unresolved() -> void:
	var pending_effects: Array = stack.duplicate()
	for paused: Dictionary in paused_effects:
		pending_effects.append(paused.effect)
	for pending: Dictionary in pending_effects:
		if pending.get("kind", "") == "loot" and not bool(pending.get("under_deck", false)):
			discards.loot.append(int(pending.card))
		elif pending.get("kind", "") == "event" and not bool(pending.get("attached", false)):
			discards.monster.append(int(pending.card))
	stack.clear()
	paused_effects.clear()
	next_action = {}
	peek = {}
	battle = -1

## Окончание хода погибшего ждёт штрафов остальных одновременно погибших игроков.
func _resume_after_deaths() -> void:
	if not _death_queue.is_empty():
		_push({"kind": "death", "owner": int(_death_queue[0])}, _death_resume)
	elif _end_after_deaths:
		_end_after_deaths = false
		_cancel_unresolved()
		resolving = {}
		_after_stack = "turn"
		_end_turn()
	else:
		_continue_stack()

func new_game(members: Array, expanded: bool = false, seed_value: int = 0) -> void:
	players = members.duplicate(true)
	bank = 100 - 3 * players.size()
	dlc = expanded
	_rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()
	decks = {}; discards = {}; hands = []; items = []; chars = []; hp = []; max_hp = []; attack = []; coins = []; souls = []; soul_cards = []; curses = []; character_ready = []; dead = []
	monsters = []; shop = []; stack = []; log = []; claimed = []; resolving = {}; paused_effects = []; _death_queue = []
	phase = "turn"; _after_stack = "turn"; _death_resume = "turn"; peek = {}; current = 0; priority = 0; passes = 0; round_no = 1; winner = -1; revision = 0; room = -1; battle = -1; roll_no = 0; last_roll = 0
	next_action = {}
	damage_shields = []
	extra_turns = []
	_ending_turn = false
	_discard_limit = 10
	_turn_resume = -1
	_end_after_deaths = false
	stats_rolls.clear();stats_risks.clear()
	for kind in ["loot", "treasure", "monster", "room"]:
		decks[kind] = FSData.pool(kind, dlc)
		if kind == "monster":
			decks[kind].append_array(FSData.pool("event", dlc))
		_shuffle(decks[kind]); discards[kind] = []
	bonuses = FSData.pool("bonus", dlc)
	var characters := FSData.characters(dlc).duplicate(true)
	_shuffle(characters)
	for seat in players.size():
		damage_shields.append(0)
		var chosen: Dictionary = characters.pop_back()
		chars.append(int(chosen.card))
		var health := 1 if chosen.key == "lost" else 2
		max_hp.append(health); hp.append(health); attack.append(1); coins.append(3); souls.append(0); character_ready.append(true); dead.append(false); hands.append([]); items.append([]); soul_cards.append([]); curses.append([])
		var eternal: int = int(chosen.item)
		if eternal < 0:
			eternal = _draw("treasure")
		if eternal >= 0:
			items[seat].append({"id": eternal, "tapped": false, "eternal": true, "counters": 0})
		_draw_loot(seat, 3)
		if chosen.key == "cain":
			current = seat
	for i in 2:
		shop.append(_draw("treasure"))
		_fill_monster(true)
	if dlc:
		room = _draw("room")
	_begin_turn()
	_note("Новая партия · " + ("с DLC" if dlc else "базовый набор"))

func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var value = array[i]; array[i] = array[j]; array[j] = value
func _draw(kind: String) -> int:
	if decks[kind].is_empty() and not discards[kind].is_empty():
		decks[kind] = discards[kind].duplicate(); discards[kind] = []; _shuffle(decks[kind])
	return int(decks[kind].pop_back()) if not decks[kind].is_empty() else -1
func _draw_loot(seat: int, count: int) -> void:
	for i in count:
		var id := _draw("loot")
		if id >= 0: hands[seat].append(id)
func _gain_coins(seat: int, amount: int) -> void:
	if amount >= 0:
		var count := mini(amount,bank)
		coins[seat] += count; bank -= count
	else:
		var count := mini(-amount,int(coins[seat]))
		coins[seat] -= count; bank += count

func _note(text: String) -> void:
	log.append(text)
	if log.size() > 150: log.pop_front()
func name_of(seat: int) -> String:
	return str(players[seat].name)
func actor() -> int:
	if phase == "priority": return priority
	if phase == "effect":
		return int(resolving.get("reroll_request", {}).get("owner", resolving.owner))
	if phase == "death" and not _death_queue.is_empty(): return int(_death_queue[0])
	return current
func can_spectate() -> bool:
	return false
func spectator_seat() -> int:
	return -1
func _begin_turn() -> void:
	phase = "turn"; priority = current; free_loot = 1; bought = false; attacked = false; battle = -1
	buy_left = 1; attack_left = 1; temporary_attack = []
	character_ready[current] = true
	for item: Dictionary in items[current]: item.tapped = false
	_draw_loot(current, 1 + _has_item(current, "guppystail"))
	_note("Ход: " + name_of(current))
func _end_turn() -> void:
	if not _ending_turn:
		_ending_turn = true
		_discard_limit = mini(10, maxi(0, hands[current].size() - _has_item(current, "guppystail")))
	if hands[current].size() > _discard_limit:
		phase = "discard"
		return
	for entry: Dictionary in items[current]:
		if FSData.card(int(entry.id)).get("key", "") == "holymantle":
			entry.tapped = false
	for entry in temporary_attack: attack[int(entry[0])] = maxi(0,int(attack[int(entry[0])])-int(entry[1]))
	temporary_attack.clear()
	for seat in players.size(): hp[seat] = max_hp[seat]; dead[seat] = false
	damage_shields.fill(0)
	for monster: Dictionary in monsters: monster.hp = FSData.stat(int(monster.id), "hp", 1)
	if not extra_turns.is_empty():
		if _turn_resume < 0:
			_turn_resume = (current + 1) % players.size()
		current = int(extra_turns.pop_front())
	else:
		current = _turn_resume if _turn_resume >= 0 else (current + 1) % players.size()
		_turn_resume = -1
		if current == 0: round_no += 1
	_ending_turn = false
	_discard_limit = 10
	_begin_turn()
func _fill_monster(initial: bool = false, slot: int = -1) -> void:
	var skipped := []
	var id := _draw("monster")
	while id >= 0 and FSData.card(id).kind == "event" and initial:
		skipped.append(id); id = _draw("monster")
	for skip in skipped: decks.monster.push_front(skip)
	if id < 0: return
	if FSData.card(id).kind == "event":
		_push({"kind":"event", "card":id, "owner":current}, "refill")
		return
	var monster := {"id":id, "hp":FSData.stat(id,"hp",1), "dc":FSData.stat(id,"dc",4), "at":FSData.stat(id,"at",1)}
	if slot >= 0 and slot < monsters.size(): monsters[slot] = monster
	else: monsters.append(monster)
func _push(effect: Dictionary, resume: String) -> void:
	if phase != "priority": _after_stack = resume
	stack.append(effect); phase = "priority"; priority = (int(effect.owner) + 1) % players.size(); passes = 0
	_note(name_of(int(effect.owner)) + " → " + FSData.effect_title(effect))
func _continue_stack() -> void:
	# Ответ после объявления смерти может спасти игрока до оплаты штрафа.
	if _after_stack == "death":
		for dying in _death_queue.duplicate():
			if hp[int(dying)] > 0:
				_death_queue.erase(dying)
		if _death_queue.is_empty():
			_after_stack = _death_resume
			if _end_after_deaths:
				_resume_after_deaths()
				return
	for i in monsters.size():
		var m: Dictionary = monsters[i]
		if int(m.hp) <= 0 and not bool(m.get("death_pending",false)):
			m["death_pending"] = true
			_push({"kind":"monster_death","card":int(m.id),"owner":current,"slot":i},_after_stack)
			return
	if not stack.is_empty():
		phase = "priority"; passes = 0; priority = current
	else:
		phase = _after_stack
		if phase == "refill":
			phase = "battle_roll" if battle >= 0 else "turn"
			while monsters.size() < 2 and phase in ["turn", "battle_roll"]:
				var before := monsters.size()
				_fill_monster()
				if monsters.size() == before and phase in ["turn", "battle_roll"]: break
	_check_deaths()
func _resolve_top() -> void:
	var effect: Dictionary = stack.pop_back()
	if effect.kind == "monster_death":
		var slot: int = int(effect.slot)
		if slot >= 0 and slot < monsters.size() and int(monsters[slot].id) == int(effect.card) and int(monsters[slot].hp) <= 0:
			# Каменюка и Голова смерти гибнут от смерти другого открытого монстра.
			for other in monsters.size():
				if other != slot and _untargetable(int(monsters[other].id)):
					monsters[other].hp = 0
			resolving = {"kind":"reward","card":int(effect.card),"owner":current,"slot":slot}; phase = "effect"
		else:
			if slot >= 0 and slot < monsters.size(): monsters[slot]["death_pending"] = false
			_continue_stack()
		return
	if effect.kind == "death":
		var dying: int = int(effect.owner)
		if hp[dying] <= 0: phase = "death"
		else:
			_death_queue.erase(dying)
			_resume_after_deaths()
		return
	if effect.kind == "attack":
		_start_attack(effect)
		return
	if effect.kind == "purchase":
		_complete_purchase(effect)
		return
	if effect.kind == "combat":
		_apply_combat(effect)
		return
	if effect.kind == "effect_roll":
		last_roll = clampi(int(effect.value),1,6)
		if not bool(effect.get("passives_done", false)):
			_roll_passives(last_roll)
		if effect.has("reroll_index"):
			var index: int = int(effect.reroll_index)
			if index >= 0 and index < stack.size() and stack[index].kind in ["roll", "effect_roll"]:
				stack[index].value = last_roll
				stack[index]["passives_done"] = true
		var previous: Dictionary = paused_effects.pop_back()
		resolving = previous.effect; _after_stack = str(previous.resume); peek = previous.peek
		phase = "effect"
		return
	if effect.kind == "roll":
		last_roll = clampi(int(effect.value), 1, 6)
		if not bool(effect.get("passives_done", false)):
			_roll_passives(last_roll)
		if battle < 0 or battle >= monsters.size() or dead[current] or hp[current] <= 0:
			_continue_stack(); return
		var m: Dictionary = monsters[battle]
		var hit := last_roll >= int(m.dc) + _monster_aura("stoney")
		var damage: int = int(attack[current]) if hit else int(m.at) + _monster_aura("deathshead")
		if not hit and last_roll == 1 and FSData.card(int(m.id)).get("key", "") == "leaper":
			damage *= 2
		_push({"kind":"combat","owner":current,"card":int(m.id),"hit":hit,"damage":damage},"battle_roll")
		return
	var card := FSData.card(int(effect.card))
	var kind: String = str(card.lua.get("type", ""))
	if effect.kind == "loot" and kind in ["1c", "2c", "3c", "4c", "5c"]:
		_gain_coins(int(effect.owner),int(kind.left(1)))
		discards.loot.append(int(effect.card)); _continue_stack()
	elif effect.kind == "loot" and kind == "lsoul":
		souls[int(effect.owner)] += 1; soul_cards[int(effect.owner)].append({"id":int(effect.card),"value":1}); _continue_stack()
	elif effect.kind == "loot" and kind == "trinkets":
		items[int(effect.owner)].append({"id":int(effect.card),"tapped":false,"eternal":false,"counters":0}); _continue_stack()
	else:
		resolving = effect
		phase = "effect"
func _check_deaths() -> void:
	if not _death_queue.is_empty() or phase in ["effect","death","game_over"]: return
	for seat in players.size():
		if hp[seat] <= 0 and not dead[seat]:
			_death_queue.append(seat)
	if not _death_queue.is_empty():
		_death_resume = _after_stack if phase == "priority" else phase
		_push({"kind": "death", "owner": int(_death_queue[0])}, _death_resume)
func _check_bonuses() -> void:
	for id in bonuses:
		if claimed.has(id): continue
		var key: String = FSData.card(int(id)).key
		for seat in players.size():
			var guppy := 0
			for item in items[seat]:
				if str(FSData.card(int(item.id)).key).begins_with("guppy"): guppy += 1
			if key == "soulofgreed" and coins[seat] >= 25 or key == "soulofgluttony" and hands[seat].size() >= 10 or key == "soulofguppy" and guppy >= 2:
				claimed.append(id); souls[seat] += 1; soul_cards[seat].append({"id":int(id),"value":1}); _note(name_of(seat) + " получает " + FSData.title(int(id))); break

func _check_win() -> void:
	for seat in players.size():
		if souls[seat] >= 4:
			winner = seat; phase = "game_over"; _note("Четыре души! Победитель: " + name_of(seat)); return
func _apply_combat(effect: Dictionary) -> void:
	if battle < 0 or battle >= monsters.size() or dead[current] or hp[current] <= 0:
		_continue_stack(); return
	var monster: Dictionary = monsters[battle]
	if int(monster.id) != int(effect.card): _continue_stack(); return
	stats_risks.append({"seat":current,"error":not bool(effect.hit) and int(effect.damage)>0})
	if bool(effect.hit):
		monster.hp = int(monster.hp) - int(effect.damage)
		if int(effect.damage) > 0 and FSData.card(int(monster.id)).get("key", "") == "lust":
			_damage_player(current, 1)
		_note("Попадание · урон %d" % int(effect.damage))
	else:
		_damage_player(current, int(effect.damage))
		_note("Промах · получен урон %d" % int(effect.damage))
	_after_stack = "battle_roll"
	_continue_stack()

func _start_attack(effect: Dictionary) -> void:
	var slot: int = int(effect.slot)
	if slot == -1:
		var id := _draw("monster")
		if id < 0: _continue_stack(); return
		if FSData.card(id).kind == "event":
			_after_stack = "turn"; _push({"kind":"event","card":id,"owner":current},"turn"); return
		var over: int = clampi(int(effect.get("over",0)),0,monsters.size()-1)
		var underneath: Dictionary = monsters[over].duplicate(true)
		monsters[over] = {"id":id,"hp":FSData.stat(id,"hp",1),"dc":FSData.stat(id,"dc",4),"at":FSData.stat(id,"at",1),"under":underneath}
		slot = over
	if slot < 0 or slot >= monsters.size(): _continue_stack(); return
	if _untargetable(int(monsters[slot].id)):
		_continue_stack()
		return
	battle = slot; phase = "battle_roll"; _after_stack = "battle_roll"

func _complete_purchase(effect: Dictionary) -> void:
	var seat: int = int(effect.owner)
	var slot: int = int(effect.slot)
	if coins[seat] >= 10:
		var id: int = _draw("treasure") if slot == -1 else int(shop[slot])
		if id >= 0:
			coins[seat] -= 10; bank += 10; items[seat].append({"id":id,"tapped":false,"eternal":false,"counters":0})
			if slot >= 0: shop[slot] = _draw("treasure")
			_note(name_of(seat) + " покупает " + FSData.title(id))
	_continue_stack()

func action(seat: int, kind: String, arg = null) -> bool:
	if seat < 0 or seat >= players.size() or phase == "game_over": return false
	# Бросок ручной карты возвращает её владельцу, сохраняя уже отложенное действие.
	# Повторный захват кубика закрывает ответы, а не создаёт ещё один бросок.
	if phase == "priority" and kind == "effect_roll" and not paused_effects.is_empty():
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
		"monster_trigger":
			var slot: int = int(a.get("slot", -1))
			if phase in ["turn", "priority", "battle_roll", "death"] and not dead[seat] and slot >= 0 and slot < monsters.size():
				var resume: String = _after_stack if phase == "priority" else phase
				_push({"kind": "monster_trigger", "card": int(monsters[slot].id), "owner": seat, "slot": slot}, resume)
				ok = true
		"claim":
			var id: int = int(a.get("card",-1))
			if phase in ["turn","priority"] and bonuses.has(id) and not claimed.has(id):
				var key: String = FSData.card(id).key
				if key == "soulofgreed" and coins[seat] < 25: return false
				if key == "soulofgluttony" and hands[seat].size() < 10: return false
				if key == "soulofguppy":
					var guppy := 0
					for item in items[seat]:
						if str(FSData.card(int(item.id)).key).begins_with("guppy"): guppy += 1
					if guppy < 2: return false
				claimed.append(id); souls[seat] += 1; soul_cards[seat].append({"id":int(id),"value":1}); _note(name_of(seat) + " получает " + FSData.title(id)); ok = true
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
					"item": items[seat].append({"id":id,"tapped":false,"eternal":false,"counters":0})
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
		"buy":
			var slot: int = int(a.get("slot",-2))
			if phase == "turn" and seat == current and not bought and coins[seat] >= 10 and slot >= -1 and slot < shop.size():
				buy_left -= 1; bought = buy_left <= 0
				_push({"kind":"purchase","owner":seat,"slot":slot},"turn"); ok = true
		"attack":
			var slot: int = int(a.get("slot",-2))
			if phase == "turn" and seat == current and not attacked and slot >= -1 and slot < monsters.size():
				if slot >= 0 and _untargetable(int(monsters[slot].id)):
					return false
				attack_left -= 1; attacked = attack_left <= 0
				_push({"kind":"attack","owner":seat,"slot":slot,"over":int(a.get("over",0))},"turn"); ok = true
		"effect_roll":
			if phase == "effect" and seat == actor():
				var reroll_request: Dictionary = resolving.get("reroll_request", {})
				resolving.erase("reroll_request")
				last_roll = _rng.randi_range(1,6); roll_no += 1
				stats_rolls.append({"seat":seat,"faces":[last_roll]})
				paused_effects.append({"effect":resolving.duplicate(true),"resume":_after_stack,"peek":peek.duplicate(true),"roller":seat})
				resolving = {}; peek = {}
				var roll_effect := {"kind":"effect_roll","value":last_roll,"owner":seat}
				if not reroll_request.is_empty():
					roll_effect["reroll_index"] = int(reroll_request.index)
				_push(roll_effect,"effect"); ok = true
		"roll":
			if phase == "battle_roll" and seat == current:
				last_roll = _rng.randi_range(1,6); roll_no += 1
				stats_rolls.append({"seat":seat,"faces":[last_roll]})
				_push({"kind":"roll","value":last_roll,"owner":seat},"battle_roll"); ok = true
		"effect":
			if phase == "effect" and seat == int(resolving.owner): ok = _effect(a)
		"effect_done":
			if phase == "effect" and seat == int(resolving.owner):
				if resolving.has("reroll_request"):
					return false
				if resolving.kind == "event" and str(FSData.card(int(resolving.card)).lua.get("type","")) == "curse" and not bool(resolving.get("attached",false)): return false
				var effect := resolving.duplicate(); resolving = {}; peek = {}
				if effect.kind == "loot" and not bool(effect.get("under_deck", false)):
					discards.loot.append(int(effect.card))
				if effect.kind == "event" and not bool(effect.get("attached",false)):
					discards.monster.append(int(effect.card))
				if effect.kind == "reward":
					if not bool(effect.get("kept_as_soul",false)): discards.monster.append(int(effect.card))
					var slot: int = int(effect.get("slot",battle))
					var covered: Dictionary = monsters[slot].get("under",{})
					if covered.is_empty(): monsters.remove_at(slot)
					else: monsters[slot] = covered
					if battle == slot:
						battle = -1; _after_stack = "refill"
						stack = stack.filter(func(e): return not e.kind in ["roll","combat"])
					elif battle > slot and covered.is_empty(): battle -= 1
					# Предмет может убить монстра вне боя или в соседнем слоте.
					if covered.is_empty(): _after_stack = "refill"
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
				var destroyable := []
				for i in items[seat].size():
					if not items[seat][i].eternal: destroyable.append(i)
				if not hands[seat].is_empty() and not hands[seat].has(loot): return false
				if not destroyable.is_empty() and not destroyable.has(item): return false
				if hands[seat].has(loot): hands[seat].erase(loot); discards.loot.append(loot)
				if item >= 0 and destroyable.has(item):
					_discard_item(int(items[seat][item].id))
					items[seat].remove_at(item)
				_gain_coins(seat,-1); character_ready[seat] = false; dead[seat] = true
				discards.monster.append_array(curses[seat]); curses[seat].clear()
				for card: Dictionary in items[seat]: card.tapped = true
				_death_queue.pop_front(); _note(name_of(seat) + " получает штраф за смерть")
				_end_after_deaths = _end_after_deaths or seat == current
				phase = _death_resume
				_resume_after_deaths()
				ok = true
		"discard":
			var id: int = int(a.get("card",-1))
			if phase == "discard" and seat == current and hands[seat].has(id):
				hands[seat].erase(id); discards.loot.append(id); ok = true
				if hands[seat].size() <= _discard_limit: _end_turn()
		"end":
			if phase == "turn" and seat == current: _end_turn(); ok = true
		"trade":
			var target: int = int(a.get("target",-1)); var amount: int = int(a.get("amount",0))
			if phase in ["turn","priority"] and target >= 0 and target < players.size() and target != seat and amount > 0 and amount <= coins[seat]:
				coins[seat] -= amount; coins[target] += amount; _note("%s → %s: %d¢" % [name_of(seat),name_of(target),amount]); ok = true
		"room":
			if phase == "turn" and seat == current and dlc:
				if room >= 0: discards.room.append(room)
				room = _draw("room"); _note("Новая комната: " + FSData.title(room)); ok = true
	if ok:
		revision += 1; _check_bonuses(); _check_win()
		if not next_action.is_empty() and kind in ["effect_done","death"]: _finish_responses()
	return ok

func _finish_responses() -> void:
	var limit := 0
	while phase == "priority" and not stack.is_empty() and limit < 500:
		_resolve_top(); limit += 1
	if phase in ["effect","death"]: return
	var followup := next_action.duplicate(true)
	next_action = {}
	if not followup.is_empty() and phase != "game_over":
		action(int(followup.seat),str(followup.kind),followup.arg)

func _effect(a: Dictionary) -> bool:
	if resolving.has("reroll_request"):
		return false
	var target: int = int(a.get("target",resolving.owner))
	var amount: int = clampi(int(a.get("amount",1)),-99,99)
	var op: String = str(a.get("op",""))
	if target < 0 or target >= players.size(): return false
	match op:
		"extra_turn":
			for i in clampi(amount, 1, 10):
				extra_turns.append(target)
		"self_underdeck":
			if resolving.kind != "loot" or bool(resolving.get("under_deck", false)):
				return false
			decks.loot.push_front(int(resolving.card))
			resolving["under_deck"] = true
		"give_item":
			var owner: int = int(resolving.owner)
			var index: int = int(a.get("item", -1))
			if target == owner or index < 0 or index >= items[owner].size() or items[owner][index].eternal:
				return false
			items[target].append(items[owner].pop_at(index))
		"peek_hand", "peek_hands":
			var revealed := []
			for seat in players.size():
				if op == "peek_hands" or seat == target:
					revealed.append({"seat": seat, "cards": hands[seat].duplicate()})
			peek = {"owner": int(resolving.owner), "hands": revealed}
		"prevent_damage":
			damage_shields[target] += maxi(0, amount)
		"coins": _gain_coins(target,amount)
		"loot": _draw_loot(target,clampi(amount,0,20))
		"damage": _damage_player(target, amount)
		"heal": hp[target] = mini(int(max_hp[target]),int(hp[target])+maxi(0,amount))
		"souls":
			souls[target] = maxi(0,int(souls[target])+amount)
			if amount > 0 and resolving.kind == "reward" and not bool(resolving.get("kept_as_soul",false)):
				soul_cards[target].append({"id":int(resolving.card),"value":amount}); resolving["kept_as_soul"] = true
		"steal_soul":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= soul_cards[target].size() or target == int(resolving.owner): return false
			var card: Dictionary = soul_cards[target].pop_at(i)
			souls[target] = maxi(0,int(souls[target])-int(card.value)); souls[int(resolving.owner)] += int(card.value)
			soul_cards[int(resolving.owner)].append(card)
		"attach_curse":
			if resolving.kind != "event" or str(FSData.card(int(resolving.card)).lua.get("type","")) != "curse" or bool(resolving.get("attached",false)): return false
			curses[target].append(int(resolving.card)); resolving["attached"] = true
		"attack": attack[target] = maxi(0,int(attack[target])+amount)
		"temporary_attack": attack[target] = maxi(0,int(attack[target])+amount); temporary_attack.append([target,amount])
		"extra_attack": attack_left += maxi(0,amount); attacked = attack_left <= 0
		"extra_buy": buy_left += maxi(0,amount); bought = buy_left <= 0
		"extra_loot": free_loot += maxi(0,amount)
		"max_hp": max_hp[target] = maxi(1,int(max_hp[target])+amount); hp[target] = mini(int(max_hp[target]),int(hp[target]))
		"treasure":
			for i in clampi(amount,0,10):
				var id := _draw("treasure")
				if id >= 0: items[target].append({"id":id,"tapped":false,"eternal":false,"counters":0})
		"roll":
			var found := false
			for i in range(stack.size()-1,-1,-1):
				if stack[i].kind in ["roll","effect_roll"]: stack[i].value = clampi(int(stack[i].value)+amount,1,6); found = true; break
			if not found: return false
		"cancel":
			if stack.is_empty() or not stack.back().kind in ["loot","item","event"]: return false
			var canceled: Dictionary = stack.pop_back()
			if canceled.get("kind") == "loot": discards.loot.append(int(canceled.card))
		"peek_loot", "peek_treasure", "peek_monster":
			var deck: String = op.trim_prefix("peek_")
			peek = {"owner":int(resolving.owner),"deck":deck,"cards":decks[deck].slice(maxi(0,decks[deck].size()-clampi(amount,1,10)))}
		"reroll":
			var found := false
			for i in range(stack.size()-1,-1,-1):
				if stack[i].kind in ["roll","effect_roll"]:
					# Результат появится только после жеста владельца исходного броска.
					resolving["reroll_request"] = {"owner": int(stack[i].owner), "index": i}
					found = true; break
			if not found: return false
		"prevent_death":
			hp[target] = maxi(1, int(hp[target]))
			dead[target] = false
			if target == current and FSData.card(int(resolving.card)).get("key", "") == "holymantle":
				resolving["end_turn_after"] = true
		"cancel_attack":
			if battle < 0: return false
			battle = -1; _after_stack = "turn"
			stack = stack.filter(func(e): return not e.kind in ["roll","combat"])
		"ready_character": character_ready[target] = true
		"steal":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size() or items[target][i].eternal: return false
			items[int(resolving.owner)].append(items[target].pop_at(i))
		"counter":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size(): return false
			items[target][i].counters = maxi(0,int(items[target][i].counters)+amount)
		"recharge":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size(): return false
			items[target][i].tapped = false
		"destroy":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size() or items[target][i].eternal: return false
			_discard_item(int(items[target][i].id))
			items[target].remove_at(i)
		"monster_hp":
			var i: int = int(a.get("item",battle))
			if i < 0 or i >= monsters.size(): return false
			monsters[i].hp = int(monsters[i].hp)+amount
		"monster_damage":
			var i: int = int(a.get("item",battle))
			if i < 0 or i >= monsters.size(): return false
			monsters[i].hp = int(monsters[i].hp)-maxi(0,amount); monsters[i]["slayer"] = int(resolving.owner)
		_:
			return false
	var manual_titles := {
		"extra_turn": "дополнительный ход",
		"self_underdeck": "разыгранная карта под низ колоды",
		"give_item": "передача своего предмета",
		"peek_hand": "просмотр руки",
		"peek_hands": "просмотр рук всех игроков",
		"prevent_damage": "защита от следующего урона"
	}
	if manual_titles.has(op):
		_note("Эффект карты: %s · %s · %d" % [name_of(target), manual_titles[op], amount])
		return true
	_note("Эффект карты: %s · %s · %d" % [name_of(target), {"coins":"монеты","loot":"взять лут","damage":"урон","heal":"лечение","souls":"души","attack":"атака","max_hp":"здоровье","treasure":"сокровища","roll":"изменить бросок","reroll":"перебросить","cancel":"отмена","recharge":"перезарядка","destroy":"уничтожение","steal":"кража","counter":"счётчики","monster_damage":"урон монстру","peek_loot":"просмотр лута","peek_treasure":"просмотр сокровищ","peek_monster":"просмотр монстров","ready_character":"перезарядка персонажа","temporary_attack":"атака до конца хода","extra_attack":"добавить атаки","extra_buy":"добавить покупки","extra_loot":"добавить розыгрыш лута","monster_hp":"здоровье монстра","prevent_death":"предотвращение смерти","cancel_attack":"отмена атаки"}.get(op,op),amount])
	return true

func get_view(seat: int, _show_all: bool = false) -> Dictionary:
	var public := []
	for i in players.size():
		public.append({"name":players[i].name,"char":chars[i],"items":items[i].duplicate(true),"hp":hp[i],"max_hp":max_hp[i],"attack":attack[i],"coins":coins[i],"souls":souls[i],"hand_count":hands[i].size(),"souls_cards":soul_cards[i].duplicate(true),"curses":curses[i].duplicate(),"ready":character_ready[i],"dead":dead[i]})
	var counts := {}
	for key in decks: counts[key] = decks[key].size()
	var visible_monsters := monsters.duplicate(true)
	for entry: Dictionary in visible_monsters:
		entry["untargetable"] = _untargetable(int(entry.id))
		entry.dc = int(entry.dc) + _monster_aura("stoney")
		entry.at = int(entry.at) + _monster_aura("deathshead")
	return {"players":public,"seat":seat,"phase":phase,"current":current,"actor":actor(),"round_no":round_no,"dlc":dlc,"hand":hands[seat].duplicate() if seat >= 0 and seat < players.size() else [],"monsters":visible_monsters,"shop":shop.duplicate(),"room":room,"bonuses":bonuses.duplicate(),"claimed":claimed.duplicate(),"stack":stack.duplicate(true),"resolving":resolving.duplicate(),"battle":battle,"roll_no":roll_no,"last_roll":last_roll,"log":log.duplicate(),"winner":winner,"free_loot":free_loot,"bought":bought,"attacked":attacked,"counts":counts,"bank":bank,"revision":revision,"peek":peek.duplicate(true) if int(peek.get("owner",-2)) == seat else {},"death_actor":int(_death_queue[0]) if not _death_queue.is_empty() else -1,"discard_limit":_discard_limit}

