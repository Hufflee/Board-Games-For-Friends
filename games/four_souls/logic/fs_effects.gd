extends "res://games/four_souls/logic/fs_turn.gd"
## Four Souls, модуль правил: Ручные операции панели эффекта (_effect).
## Часть цепочки fs_state → fs_stack → fs_combat → fs_turn → fs_effects → fs_rules (FSRules — фасад).
## Отдельно не используется: состояние и вызовы общие через self.

func _effect(a: Dictionary) -> bool:
	if resolving.has("spawn_card"):
		return false
	if resolving.has("reroll_request"):
		return false
	var target: int = int(a.get("target",resolving.owner))
	var amount: int = clampi(int(a.get("amount",1)),-99,99)
	var op: String = str(a.get("op",""))
	if target < 0 or target >= players.size(): return false
	# Эти две операции адресуют кубик/монстра, а не игрока target: смена target не обходит защиту источника.
	var own_operation: bool = target == int(resolving.owner) or op in ["temporary_monster_dc", "roll"]
	if own_operation and PassiveRules.handled_operation(int(resolving.card), op) and (op not in ["coins", "counter"] or amount >= 0):
		_note("Этот эффект карты уже выполняется автоматически")
		return false
	match op:
		"pay_coins":
			if target != int(resolving.owner) or amount <= 0:
				return false
			var cost := maxi(0, amount - _item_count(target, 76))
			if int(coins[target]) < cost:
				return false
			coins[target] -= cost
			bank += cost
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
			if target == owner or index < 0 or index >= items[owner].size():
				return false
			var chosen: Dictionary = items[owner][index]
			# Собственная напечатанная способность Мошны разрешает её передачу.
			# Обычная передача других вечных предметов по-прежнему запрещена.
			var sack_ability := int(chosen.id) == 69 and int(resolving.get("card", -1)) == 69
			if chosen.eternal and not sack_ability:
				return false
			items[target].append(_remove_item(owner, index))
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
			# Душа — всегда карта: +души только забирают карту награды, −души — «Уничтожить карту души».
			if amount < 0:
				_note("Для потери карты души выберите «Уничтожить карту души» и её индекс")
				return false
			if room == 779 or curses[target].has(744):
				return false
			if resolving.kind != "reward" or bool(resolving.get("kept_as_soul", false)):
				_note("Душа без карты не начисляется: карту души даёт награда монстра")
				return false
			souls[target] = int(souls[target]) + amount
			soul_cards[target].append({"id":int(resolving.card),"value":amount}); resolving["kept_as_soul"] = true
		"destroy_soul":
			var index: int = int(a.get("item", -1))
			if index < 0 or index >= soul_cards[target].size():
				return false
			var destroyed: Dictionary = soul_cards[target][index]
			var id: int = int(destroyed.id)
			# Душа персонажа не является отдельной уничтожаемой картой.
			# Предмет, уже ставший душой, теряет прежнюю вечность (например, Кость).
			if FSData.card(id).get("kind", "") == "character":
				return false
			soul_cards[target].remove_at(index)
			souls[target] = maxi(0, int(souls[target]) - int(destroyed.value))
			var pile: String = {"monster": "monster", "loot": "loot", "treasure": "treasure"}.get(str(FSData.card(id).get("kind", "")), "")
			if not pile.is_empty():
				discards[pile].append(id)
			_note("Уничтожена душа: %s · %s" % [name_of(target), FSData.title(id)])
		"steal_soul":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= soul_cards[target].size() or target == int(resolving.owner): return false
			var card: Dictionary = soul_cards[target].pop_at(i)
			souls[target] = maxi(0,int(souls[target])-int(card.value)); souls[int(resolving.owner)] += int(card.value)
			soul_cards[int(resolving.owner)].append(card)
		"attach_curse":
			if resolving.kind != "event" or str(FSData.card(int(resolving.card)).lua.get("type","")) != "curse" or bool(resolving.get("attached",false)): return false
			curses[target].append(int(resolving.card)); resolving["attached"] = true
		"attack":
			if target == int(resolving.owner) and PassiveRules.ATTACK.has(int(resolving.card)):
				_note("Постоянный бонус этой карты уже учтён")
				return false
			attack[target] = maxi(0,int(attack[target])+amount)
		"temporary_attack": attack[target] = maxi(0,int(attack[target])+amount); temporary_attack.append([target,amount])
		"extra_attack": attack_left += maxi(0,amount); attacked = attack_left <= 0
		"extra_buy": buy_left += maxi(0,amount); bought = buy_left <= 0
		"extra_loot": free_loot += maxi(0,amount)
		"max_hp":
			if target == int(resolving.owner) and PassiveRules.HEALTH.has(int(resolving.card)):
				_note("Постоянный бонус здоровья этой карты уже учтён")
				return false
			max_hp[target] = maxi(1,int(max_hp[target])+amount)
			hp[target] = mini(int(max_hp[target]),int(hp[target]))
		"expand_monsters":
			if amount < 1 or amount > 10:
				return false
			monster_slots += amount
			resolving["refill_monsters"] = true
		"treasure":
			for i in clampi(amount,0,10):
				var id := _draw("treasure")
				if id >= 0:
					_gain_item(target, id)
		"roll":
			var found := false
			for i in range(stack.size()-1,-1,-1):
				if stack[i].kind in ["roll","effect_roll"]: stack[i].value = clampi(int(stack[i].value)+amount,1,6); found = true; break
			if not found: return false
		"cancel":
			if stack.is_empty() or not stack.back().kind in ["loot","item","event","passive"]: return false
			var canceled: Dictionary = stack.pop_back()
			_resolving_base = mini(_resolving_base, stack.size())
			if canceled.get("kind") == "loot": discards.loot.append(int(canceled.card))
		"peek_loot", "peek_treasure", "peek_monster":
			var deck: String = op.trim_prefix("peek_")
			peek = {"owner":int(resolving.owner),"deck":deck,"cards":decks[deck].slice(maxi(0,decks[deck].size()-clampi(amount,1,10)))}
		"reroll":
			var found := false
			for i in range(stack.size()-1,-1,-1):
				if stack[i].kind in ["roll","effect_roll"]:
					# Результат появится только после жеста владельца исходного броска.
					resolving["reroll_request"] = {"owner": int(stack[i].owner), "index": i,
						"target_token": _roll_token(stack[i]), "attack": _rerolls_attack({"reroll_index": i})}
					found = true; break
			if not found: return false
		"prevent_death":
			hp[target] = maxi(1, int(hp[target]))
			dead[target] = false
			if target == current and FSData.card(int(resolving.card)).get("key", "") == "holymantle":
				resolving["end_turn_after"] = true
		"cancel_attack":
			if battle < 0 and battle_player < 0: return false
			_end_battle()
			_resolving_base = mini(_resolving_base, stack.size())
			if str(resolving.get("_resume", "")) == "battle_roll":
				resolving["_resume"] = "turn"
		"ready_character": character_ready[target] = true
		"steal":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size() or items[target][i].eternal: return false
			items[int(resolving.owner)].append(_remove_item(target, i))
		"counter":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size(): return false
			items[target][i].counters = maxi(0,int(items[target][i].counters)+amount)
		"recharge":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size(): return false
			if int(items[target][i].id) == 44 and int(resolving.get("card", -1)) != 44:
				return false
			items[target][i].tapped = false
		"deactivate":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= items[target].size():
				return false
			items[target][i].tapped = true
		"discard_loot", "give_loot":
			var owner: int = resolving.owner
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= hands[owner].size() or (op == "give_loot" and target == owner):
				return false
			var id: int = hands[owner].pop_at(i)
			if op == "give_loot":
				hands[target].append(id)
			else:
				discards.loot.append(id)
		"expand_shop":
			for i in clampi(amount, 0, 10):
				var id := _draw("treasure")
				if id >= 0:
					shop.append(id)
		"set_roll":
			var found := false
			for i in range(stack.size() - 1, -1, -1):
				if stack[i].kind in ["roll", "effect_roll"]:
					stack[i].value = clampi(amount, 1, 6)
					found = true
					break
			if not found:
				return false
		"reveal_hand":
			peek = {"owner": int(resolving.owner), "hands": [{"seat": target, "cards": hands[target].duplicate()}]}
		"swap_items":
			var owner: int = resolving.owner
			var own_index: int = int(a.get("item", -1))
			var other_index: int = int(a.get("other_item", 0))
			if owner == target or own_index < 0 or own_index >= items[owner].size() or other_index < 0 or other_index >= items[target].size():
				return false
			if items[owner][own_index].eternal or items[target][other_index].eternal:
				return false
			var own := _remove_item(owner, own_index)
			var other := _remove_item(target, other_index)
			items[owner].insert(own_index, other)
			items[target].insert(other_index, own)
		"item_to_soul":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= items[target].size() or items[target][i].eternal or room == 779 or curses[target].has(744):
				return false
			var item := _remove_item(target, i)
			souls[target] += 1
			soul_cards[target].append({"id": int(item.id), "value": 1})
		"temporary_monster_dc":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= monsters.size():
				return false
			monsters[i].dc = int(monsters[i].dc) + amount
			monsters[i]["temporary_dc"] = int(monsters[i].get("temporary_dc", 0)) + amount
		"discard_shop":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= shop.size():
				return false
			discards.treasure.append(int(shop[i]))
			shop[i] = _draw("treasure")
		"discard_monster":
			var i: int = int(a.get("item", -1))
			if i < 0 or i >= monsters.size() or i == battle:
				return false
			discards.monster.append(int(monsters[i].id))
			if monsters[i].has("under"):
				monsters[i] = monsters[i].under
			else:
				monsters.remove_at(i)
				if battle > i:
					battle -= 1
				_fill_monster()
		"destroy":
			var i: int = int(a.get("item",-1))
			if i < 0 or i >= items[target].size() or items[target][i].eternal: return false
			_destroy_item(target, i)
		"monster_hp":
			var i: int = int(a.get("item",battle))
			if i < 0 or i >= monsters.size(): return false
			monsters[i].hp = int(monsters[i].hp)+amount
		"monster_damage":
			var i: int = int(a.get("item",battle))
			if i < 0 or i >= monsters.size(): return false
			var damage := maxi(0, amount)
			if int(monsters[i].id) == 281:
				damage = mini(1, damage)
			monsters[i].hp = int(monsters[i].hp) - damage
			monsters[i]["slayer"] = int(resolving.owner)
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
