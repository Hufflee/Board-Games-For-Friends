extends "res://games/four_souls/logic/fs_bill21_automation.gd"
## Группа21: чужой выбор на аукционе, просмотр добычи и монстр под предметом.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	var owner: int = int(resolving.get("owner", current))
	match str(step.get("targets", "")):
		"auction_shop21":
			for index in shop.size():
				if int(shop[index]) >= 0:
					out.append({"label": FSData.title(int(shop[index])), "arg": {"op": "auction_prepare21", "item": index, "card": int(shop[index])}})
		"auction_bids21":
			var bidder: int = int(resolving.choice_owner)
			out.append({"label": "Пас", "arg": {"op": "auction_bid21", "amount": 0}})
			for amount in range(int(resolving.auction_high21) + 1, int(coins[bidder]) + 1):
				out.append({"label": "Ставка %d¢" % amount, "arg": {"op": "auction_bid21", "amount": amount}})
		"loot_three21":
			for id in peek.get("cards", []):
				out.append({"label": FSData.title(int(id)), "arg": {"op": "loot_three21", "card": int(id)}})
		"held_monster21":
			for slot in monsters.size():
				var source: Dictionary = monsters[slot]
				if slot != battle and not source.has("virtual_zone15") and not bool(source.get("ambush_event20", false)):
					out.append({"label": FSData.title(int(source.id)), "arg": {"op": "hold_monster21", "item": slot}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var source: Dictionary = resolving.get("source", {})
	match str(step.op):
		"auction_prepare21":
			resolving["auction_card21"] = int(step.card)
			resolving["auction_high21"] = 0
			resolving["auction_winner21"] = -1
			resolving["auction_queue21"] = []
			for offset in range(1, players.size()):
				resolving.auction_queue21.append((owner + offset) % players.size())
			_next_auction21()
		"auction_bid21":
			var bidder: int = int(resolving.choice_owner)
			var amount: int = int(step.amount)
			resolving.auction_queue21.pop_front()
			if amount > 0:
				resolving.auction_high21 = amount
				resolving.auction_winner21 = bidder
				resolving.auction_queue21.clear()
				for offset in range(1, players.size()):
					var other := (bidder + offset) % players.size()
					if other != owner:
						resolving.auction_queue21.append(other)
				_note("%s: ставка%d¢" % [name_of(bidder), amount])
			_next_auction21()
		"loot_three21":
			var id: int = int(step.card)
			decks.loot.erase(id)
			peek.cards.erase(id)
			hands[owner].append(id)
			if not peek.cards.is_empty():
				_insert_card_steps([{"op": "loot_rest21", "targets": "other_players"}])
			else:
				peek = {}
		"loot_rest21":
			for id in peek.get("cards", []).duplicate():
				decks.loot.erase(int(id))
				hands[int(step.target)].append(int(id))
			peek = {}
		"held_mode21":
			if source.has("held_monster21"):
				resolving["placing_monster21"] = int(source.held_monster21)
				_insert_card_steps([{"op": "release_monster21", "targets": "place_monster21"}])
			else:
				_insert_card_steps([{"op": "hold_monster21", "targets": "held_monster21"}])
		"hold_monster21":
			var slot: int = int(step.item)
			var monster: Dictionary = monsters[slot]
			if bool(monster.get("ambush_return20", false)):
				_put_monster20(monster, "discard")
			else:
				var physical: int = int(monster.get("physical_id20", monster.id))
				source["held_monster21"] = physical
				if not source.has("stored_cards20"):
					source["stored_cards20"] = []
				source.stored_cards20.append(physical)
			_eggs_monsters.erase(int(monster.id))
			if monster.has("under"):
				monsters[slot] = monster.under
			else:
				monsters.remove_at(slot)
				if battle > slot:
					battle -= 1
				for pending: Dictionary in stack:
					if pending.kind == "attack" and int(pending.slot) > slot:
						pending.slot = int(pending.slot) - 1
			resolving["refill_monsters"] = true
		"release_monster21":
			var id: int = int(source.held_monster21)
			source.erase("held_monster21")
			source.stored_cards20.erase(id)
			_place_encounter_monster(id, int(step.item))
			_forced_monsters14.append(id)
			attack_left += 1
			attacked = false
		_:
			super._apply_card_step(step)

func _next_auction21() -> void:
	if not resolving.auction_queue21.is_empty():
		resolving["choice_owner"] = int(resolving.auction_queue21[0])
		_insert_card_steps([{"op": "auction_bid21", "targets": "auction_bids21"}])
		return
	resolving.erase("choice_owner")
	var winner: int = int(resolving.auction_winner21)
	var price: int = int(resolving.auction_high21)
	var slot := shop.find(int(resolving.auction_card21))
	if winner >= 0 and slot >= 0 and int(coins[winner]) >= price:
		_transfer_coins(winner, int(resolving.owner), price)
		_effect({"op": "take_shop", "target": winner, "item": slot})
