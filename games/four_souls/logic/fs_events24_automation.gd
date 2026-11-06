extends "res://games/four_souls/logic/fs_bonus24_automation.gd"
## События24. Голоса748 не отправляются другим участникам до объявления результата.
func _card_choices() -> Array:
	var out := super._card_choices()
	var category: String = str(_card_step().get("targets", ""))
	match category:
		"guardian_depth24":
			for depth in range(mini(3, decks.monster.size()), decks.monster.size() + 1):
				out.append({"label": "Под %d верхних карт" % depth, "arg": {"op": "guardian_place24", "amount": depth}})
		"vote_cast24", "vote_guess24":
			var secret: bool = int(resolving.card) == 748
			for seat in players.size():
				if (secret and seat != current) or (not secret and seat != _card_choice_owner()):
					out.append({"label": name_of(seat), "arg": {"op": category, "target": seat}})
		"vote_tie24":
			for seat in resolving.vote_tied24:
				out.append({"label": name_of(int(seat)), "arg": {"op": "vote_choose24", "target": int(seat)}})
		"vote_soul24":
			var owner := _card_choice_owner()
			if not _room_has20(779) and not curses[owner].has(744):
				for seat in players.size():
					if seat == owner or _protected20(seat, owner):
						continue
					for index in soul_cards[seat].size():
						var id: int = int(soul_cards[seat][index].id)
						out.append({"label": name_of(seat) + " · " + FSData.title(id), "arg": {"op": "vote_soul24", "target": seat, "item": index, "card": id}})
		"event_token24":
			var seat := _card_choice_owner()
			var token: String = str(_card_step().token24)
			for index in items[seat].size():
				if token == "eternal" or not bool(items[seat][index].eternal):
					out.append({"label": FSData.title(int(items[seat][index].id)), "arg": {"op": "event_token24", "item": index, "token24": token}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"flush_monsters24":
			_flush_monsters24(false)
		"rotate_players24":
			_rotate_players24()
		"skull_item24":
			resolving["attached"] = true
			_gain_item(owner, 747)
		"skull_result24":
			_skull_result24(resolving.source, owner, int(resolving.get("automation_roll", 0)))
		"vote_prepare24":
			resolving["vote_queue24"] = []
			resolving["ballots24"] = {}
			for offset in range(1 if int(resolving.card) == 748 else 0, players.size()):
				resolving.vote_queue24.append((current + offset) % players.size())
			_next_vote24()
		"vote_cast24":
			var chosen: int = int(step.target)
			resolving.ballots24[chosen] = int(resolving.ballots24.get(chosen, 0)) + 1
			resolving.vote_queue24.pop_front()
			_next_vote24()
		"vote_guess24":
			var guilty: int = int(resolving.guilty24)
			_note("Виновен: " + name_of(guilty))
			if int(step.target) == guilty:
				hp[guilty] = 0
				_last_player_killer[guilty] = -1
				_give_treasures21(current, 1)
			else:
				_give_treasures21(guilty, 1)
				skipped_turns[current] = int(skipped_turns[current]) + 1
		"vote_choose24":
			_offer_vote_soul24(int(step.target))
		"vote_soul24":
			var seat: int = int(step.target)
			var soul: Dictionary = soul_cards[seat].pop_at(int(step.item))
			souls[seat] = int(souls[seat]) - int(soul.value)
			_gain_soul_card(_card_choice_owner(), soul, false)
		"crash_table24":
			for seat in players.size():
				for index in range(items[seat].size() - 1, -1, -1):
					if not bool(items[seat][index].eternal):
						_destroy_item(seat, index)
			for slot in shop.size():
				var id: int = int(shop[slot])
				if id >= 0 and not bool(_eternal_shop15.get(id, false)):
					_discard_item(id)
					_shop_counters20.erase(id)
					shop[slot] = -1
			_flush_monsters24(false)
			_flush_rooms24()
			for slot in shop.size():
				if int(shop[slot]) < 0:
					shop[slot] = _draw("treasure")
		"guardian_prepare24":
			if _guardian_resolved24:
				resolving["attached"] = true
				_gain_soul_card(owner, {"id": 751, "value": 1})
			else:
				_guardian_resolved24 = true
				_insert_card_steps([{"op": "guardian_place24", "targets": "guardian_depth24"}])
		"guardian_place24":
			resolving["attached"] = true
			decks.monster.insert(decks.monster.size() - int(step.amount), 751)
		"token_prepare24":
			var seats: Array = range(players.size())
			_shuffle(seats)
			resolving["token_queue24"] = seats.slice(0, mini(3, seats.size()))
			resolving["token_index24"] = 0
			_next_event_token24()
		"event_token24":
			var seat := _card_choice_owner()
			var source: Dictionary = items[seat][int(step.item)]
			match str(step.token24):
				"health": source["health_tokens15"] = int(source.get("health_tokens15", 0)) + 1
				"attack": source["attack_tokens15"] = int(source.get("attack_tokens15", 0)) + 1
				"eternal": source.eternal = true
			_refresh_passive_stats()
			_next_event_token24()
		_:
			super._apply_card_step(step)

func _next_vote24() -> void:
	if not resolving.vote_queue24.is_empty():
		resolving["choice_owner"] = int(resolving.vote_queue24[0])
		_insert_card_steps([{"op": "vote_cast24", "targets": "vote_cast24"}])
		return
	resolving.erase("choice_owner")
	if resolving.ballots24.is_empty():
		return
	var best: int = int(resolving.ballots24.values().max())
	var tied: Array = []
	for offset in players.size():
		var seat := (current + offset) % players.size()
		if int(resolving.ballots24.get(seat, 0)) == best:
			tied.append(seat)
	if int(resolving.card) == 748:
		# При равенстве тайных голосов виновным становится первый из равных по порядку хода.
		resolving["guilty24"] = int(tied[0])
		_insert_card_steps([{"op": "vote_guess24", "targets": "vote_guess24"}])
	elif tied.size() == 1:
		_offer_vote_soul24(int(tied[0]))
	else:
		resolving["vote_tied24"] = tied
		_insert_card_steps([{"op": "vote_choose24", "targets": "vote_tie24"}])

func _offer_vote_soul24(winner: int) -> void:
	resolving["choice_owner"] = winner
	_insert_card_steps([{"op": "vote_soul24", "targets": "vote_soul24", "optional": true}])

func _next_event_token24() -> void:
	while not resolving.token_queue24.is_empty():
		var seat: int = int(resolving.token_queue24.pop_front())
		var index: int = int(resolving.token_index24)
		resolving.token_index24 = index + 1
		if not items[seat].any(func(source): return index == 2 or not bool(source.eternal)):
			continue
		resolving["choice_owner"] = seat
		_insert_card_steps([{"op": "event_token24", "targets": "event_token24", "token24": ["health", "attack", "eternal"][index]}])
		return
	resolving.erase("choice_owner")

func _flush_monsters24(keep_attacked: bool) -> void:
	if not keep_attacked and battle >= 0:
		_end_battle()
	for slot in range(monsters.size() - 1, -1, -1):
		if slot == battle or monsters[slot].has("virtual_zone15"):
			continue
		var source: Dictionary = monsters[slot]
		_put_monster20(source, "discard")
		_eggs_monsters.erase(int(source.id))
		var under: Dictionary = source.get("under", {})
		for pending: Dictionary in stack:
			if pending.kind == "attack" and int(pending.slot) == slot:
				pending.slot = -2
			elif pending.kind == "attack" and under.is_empty() and int(pending.slot) > slot:
				pending.slot = int(pending.slot) - 1
		if under.is_empty():
			monsters.remove_at(slot)
			if battle > slot:
				battle -= 1
		else:
			monsters[slot] = under
	resolving["refill_monsters"] = true

func _flush_rooms24() -> void:
	if room >= 0 and _room_can_discard():
		discards.room.append(room)
		room = _draw("room")
		_primary_room24 = {}
		if room == 810:
			_reset_room_goals()
	for index in range(_extra_rooms20.size() - 1, -1, -1):
		_replace_room20(index)

func _rotate_players24() -> void:
	var count := players.size()
	var old_hands := hands.duplicate()
	var old_chars := chars.duplicate()
	var old_tokens := _character_tokens20.duplicate()
	var old_enigma := _enigma_back26.duplicate()
	var marked_damage: Array = []
	var eternals: Array = []
	for seat in count:
		marked_damage.append(int(max_hp[seat]) - int(hp[seat]))
		var moved: Array = []
		for index in range(items[seat].size() - 1, -1, -1):
			if bool(items[seat][index].eternal):
				moved.push_front(_remove_item(seat, index))
		eternals.append(moved)
	for seat in count:
		var from_right := (seat + 1) % count
		var from_left := posmod(seat - 1, count)
		hands[seat] = old_hands[from_left]
		chars[seat] = old_chars[from_right]
		_character_tokens20[seat] = int(old_tokens.get(from_right, 0))
		_enigma_back26[seat] = bool(old_enigma.get(from_right, false))
		max_hp[seat] = maxi(1, int(max_hp[seat]) + PassiveRules.character_health(int(chars[seat])) - PassiveRules.character_health(int(old_chars[seat])))
		character_ready[seat] = true
		for source: Dictionary in eternals[from_right]:
			if int(source.id) != 44:
				source.tapped = false
		items[seat] = eternals[from_right] + items[seat]
	_refresh_passive_stats()
	for seat in count:
		hp[seat] = maxi(0, int(max_hp[seat]) - int(marked_damage[seat])) if not dead[seat] else 0

func _skull_result24(source: Dictionary, owner: int, face: int) -> void:
	for holder in players.size():
		for index in items[holder].size():
			if not is_same(items[holder][index], source):
				continue
			if face <= 4:
				items[(holder + 1) % players.size()].append(_remove_item(holder, index))
			elif face == 5:
				if not bool(source.eternal):
					_destroy_item(holder, index)
			elif face == 6:
				var removed := _remove_item(holder, index, true)
				_gain_soul_card(holder, {"id": int(removed.id), "value": 1})
			_refresh_passive_stats()
			if face == 5:
				_damage_player(owner, 3, {"attacker": -1})
			return

func _refresh_passive_stats() -> void:
	super._refresh_passive_stats()
	if not _card_automation_enabled() or _setting_up:
		return
	for seat in items.size():
		for source: Dictionary in items[seat]:
			if int(source.get("physical_id13", source.id)) == 747 and int(source.get("skull_owner24", -1)) != seat:
				source["skull_owner24"] = seat
				_queue_packet15(seat, 747, source, "control24")
