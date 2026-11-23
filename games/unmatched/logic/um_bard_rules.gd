extends RefCounted
## Шекспир, Гамлет, Титания, сёстры и самураи. Подключается только к хостовым UMRules.
## Адресные проверки: tests/test_unmatched_bard_samurai.gd.

const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const Piles := preload("res://hub/card_piles.gd")
const ENCHANTMENTS := ["Чары жадности", "Чары любви", "Чары невидимости", "Чары ревности", "Чары рифмы", "Чары сна"]
const INGREDIENTS := ["snake", "lizard_leg", "bat"]
var _owner: WeakRef
var r: Variant:
	get: return _owner.get_ref()
var poem: Array = []
var cauldron: Array = []
var enchantment := -1
var enchantment_deck: Array = []
var enchantment_discard: Array = []
var not_to_be := false
var hurt: Dictionary = {}
var rooted: Dictionary = {}
var positions: Dictionary = {}
var _combat_damage := false
var _checking_moves := false
var _ending_turn := false
var returned: Dictionary = {}
var poem_opponent := Vector2i(-1, -1)
var blind_cards: Dictionary = {}
var turn_ended := false


func _init(owner: RefCounted) -> void:
	_owner = weakref(owner)
	if "titania" in r.game.heroes:
		enchantment_deck = Array(range(6))
		Piles.shuffle(enchantment_deck, r.game.random)


func hero_index(hero: String) -> int:
	return r.game.heroes.find(hero)


func alive_hero(place: int) -> bool:
	return r.game.fighters[place].any(func(figure: Dictionary) -> bool: return figure.is_hero and figure.health > 0)


func enchantment_card(index: int) -> Dictionary:
	return {"hero": "titania", "enchantment": index, "key": "enchantment:%d" % index, "name": ENCHANTMENTS[index]}


func status(place: int) -> String:
	match str(r.game.heroes[place]):
		"witches": return "Котёл: %d · ингредиентов %d" % [cauldron.size(), ingredients().size()]
		"shakespeare": return "Строка: %d / 10" % syllables()
		"hamlet": return "Не быть · атака +2" if not_to_be else "Быть · манёвр +1 карта"
		"titania": return ENCHANTMENTS[enchantment] if enchantment >= 0 else "Чары не открыты"
	return ""


func special_pile(place: int) -> Dictionary:
	match str(r.game.heroes[place]):
		"witches": return {"special": [{"hero": "witches", "cauldron_rules": true, "name": "Рецепты заклятий"}] + cauldron.duplicate(true), "special_name": "Котёл %d" % cauldron.size()}
		"shakespeare": return {"special": poem.duplicate(true), "special_name": "Строка %d/10" % syllables()}
		"titania":
			var cards: Array = []
			if enchantment >= 0:
				cards.append(enchantment_card(enchantment))
			for index: int in enchantment_discard:
				cards.append(enchantment_card(index))
			return {"special": cards, "special_name": "Чары"}
	return {}


func syllables() -> int:
	var total := 0
	for card: Dictionary in poem:
		total += int(card.get("syllables", 0))
	return total


func ingredients() -> Array:
	var result: Array = []
	for card: Dictionary in cauldron:
		var ingredient: String = card.get("ingredient", "")
		if not ingredient.is_empty() and ingredient not in result:
			result.append(ingredient)
	return result


func start_turn() -> void:
	_ending_turn = false
	var place: int = r.seat
	match str(r.game.heroes[place]):
		"hamlet":
			r._offer_choice(place, ["to_be", "not_to_be"], false, "Вопрос · быть или не быть?", _choose_question.bind(place))
			r._effect_request["labels"] = {"to_be": "Быть · дополнительный добор", "not_to_be": "Не быть · 2 урона и атака +2"}
		"titania":
			if enchantment < 0 and not enchantment_deck.is_empty():
				enchantment = enchantment_deck.pop_back()
				r._notice_card(enchantment_card(enchantment))


func _choose_question(answer: String, place: int) -> void:
	not_to_be = answer == "not_to_be"
	if not_to_be:
		r._offer_choice(place, own_fighters(place), false, "Не быть · выберите своего бойца для 2 урона",
			func(target: Vector2i) -> void: r._damage_redirectable(target, 2))


func own_fighters(place: int) -> Array:
	var result: Array = []
	for index in r.game.fighters[place].size():
		if not r._fighter_at(place, index).is_empty():
			result.append(Vector2i(place, index))
	return result


func encircled(owner: int, opponent: Vector2i) -> bool:
	var target: Dictionary = r._fighter_at(opponent.x, opponent.y)
	if target.is_empty():
		return false
	var count := 0
	for figure: Dictionary in r.game.fighters[owner]:
		count += int(r.game.board.adjacent(figure.space, target.space))
	return count >= 2


func bonus(fighter: Vector2i, attacking: bool) -> int:
	var amount := 0
	var oda := hero_index("oda")
	if oda >= 0 and fighter != Vector2i(oda, 0) and fighter.x % 2 == oda % 2:
		var leader: Dictionary = r._fighter_at(oda, 0)
		var target: Dictionary = r._fighter_at(fighter.x, fighter.y)
		if not leader.is_empty() and not target.is_empty() and r.game.board.same_zone(leader.space, target.space):
			amount += 1
	if attacking and r.game.heroes[fighter.x] == "hamlet" and fighter.y == 0 and not_to_be:
		amount += 2
	return amount


func capture_positions() -> void:
	if not positions.is_empty():
		return
	for place in r.game.fighters.size():
		for index in r.game.fighters[place].size():
			positions[Vector2i(place, index)] = r.game.fighters[place][index].space


## Проверяется каждый шаг маршрута и каждое завершённое помещение, в том числе снятие с поля.
func scan_moves() -> void:
	if _checking_moves:
		return
	_checking_moves = true
	var tomoe := hero_index("tomoe")
	var watcher: Dictionary = r._fighter_at(tomoe, 0) if tomoe >= 0 else {}
	var watcher_before: int = positions.get(Vector2i(tomoe, 0), watcher.get("space", -1))
	for place in r.game.fighters.size():
		for index in r.game.fighters[place].size():
			var key := Vector2i(place, index)
			var figure: Dictionary = r.game.fighters[place][index]
			var previous: int = positions.get(key, figure.space)
			if rooted.has(key) and figure.health > 0 and previous >= 0 and previous != figure.space:
				figure.space = previous
			positions[key] = figure.space
			if previous == figure.space or previous < 0 or watcher.is_empty() or not figure.is_hero or place % 2 == tomoe % 2:
				continue
			if r.game.board.same_zone(previous, watcher_before) and not r.game.board.same_zone(figure.space, watcher.space):
				if figure.space < 0 and figure.health > 0:
					figure.health -= 1
					damaged(key, 1)
				else:
					r._damage_redirectable(key, 1)
	_checking_moves = false


func damage_allowed(fighter: Vector2i, amount: int, combat: bool) -> bool:
	return not (r.game.heroes[fighter.x] == "titania" and enchantment == 5 and not combat and amount > 0)


func damaged(fighter: Vector2i, amount: int) -> void:
	if amount > 0:
		hurt[fighter] = true


func pass_turn() -> void:
	turn_ended = false
	rooted.clear()
	hurt.clear()
	positions.clear()


func discard_pile(place: int) -> Array:
	return cauldron if r.game.heroes[place] == "witches" else r.game.discards[place]


func dispose(card: Dictionary, holder: int) -> bool:
	match str(r.game.heroes[holder]):
		"witches":
			cauldron.append(card)
			return true
		"shakespeare":
			if turn_ended: return false
			poem.append(card)
			if syllables() >= 10:
				r._effect_steps.push_back(_complete_line.bind(holder, card, syllables() == 10))
			return true
	return false


func _complete_line(owner: int, card: Dictionary, exact: bool) -> void:
	r._effect_steps.push_front(_discard_line.bind(owner))
	if exact:
		line_effect(owner, card)


func _discard_line(owner: int) -> void:
	r.game.discards[owner].append_array(poem)
	poem.clear()


func discard_enchantment() -> bool:
	if enchantment < 0:
		return false
	enchantment_discard.append(enchantment)
	enchantment = -1
	return true


func on_maneuver() -> void:
	var place: int = r.seat
	if r.game.heroes[place] == "hamlet" and not not_to_be:
		r._draw(place, 1)
	if r.game.heroes[place] == "titania" and enchantment == 1:
		r._effect_steps.push_front(r._resume_maneuver)
		r.phase = r.Phase.EFFECT_CHOICE
		r._offer_choice(place, r._opposing_targets(place, -1), true, "Чары любви · переместите противника на 1 ячейку",
			func(target: Vector2i) -> void: r._offer_move(target, place, Vector2i(-1, -1), {"distance": 1}))


func before_end_turn() -> bool:
	if _ending_turn or r.game.heroes[r.seat] != "titania" or enchantment != 0:
		return false
	_ending_turn = true
	r.phase = r.Phase.EFFECT_CHOICE
	r._effect_steps.push_front(r._finish_hand)
	r._offer_choice(r.seat, ["draw"], true, "Чары жадности · взять карту в конце хода?",
		func(_answer: String) -> void: r._draw(r.seat, 1))
	return true


func immediate(combat: Dictionary, side: int) -> void:
	var id: String = combat.immediate_effects[side].get("bard_immediate", "")
	var fighter: Vector2i = r._attack_pair[side]
	var opponent: Vector2i = r._attack_pair[1 - side]
	match id:
		"tomoe:14":
			if r.game.fighters[opponent.x][opponent.y].is_hero:
				cancel(combat, side)
		"tomoe:17": rooted[fighter] = true
		"tomoe:19":
			r._offer_choice(fighter.x, adjacent(fighter, true), true, "Выберите смежного бойца для обмена местами",
				func(target: Vector2i) -> void: swap(fighter, target))
		"oda:01":
			if encircled(fighter.x, opponent): cancel(combat, side)
		"oda:07":
			var targets := adjacent(fighter, true).filter(func(target: Vector2i) -> bool: return target.x % 2 == fighter.x % 2)
			r._offer_choice(fighter.x, targets, true, "Обменяйтесь со смежным союзником · он защищается вместо вас",
				func(target: Vector2i) -> void:
					if swap(fighter, target): r._attack_pair[side] = target)
		"witches:01": cauldron_heal(fighter.x, 3)
		"witches:05": transfer_choice(fighter.x, r.game.discards[fighter.x], cauldron, false, "Положите карту из сброса в котёл")
		"witches:16":
			transfer_choice(fighter.x, r.game.discards[fighter.x], cauldron, false, "Верните карту из сброса в котёл")
		"titania:14":
			cancel(combat, side)
			combat.ignore_attack = true
			r.game.hands[r._combat_holders[0]].append(combat.cards[0])
			returned[combat.cards[0].key] = false
		"titania:16":
			if enchantment >= 0:
				r._offer_choice(fighter.x, ["discard"], true, "Сбросьте чары, чтобы отменить эффект противника",
					func(_answer: String) -> void:
						discard_enchantment()
						cancel(combat, side))


func during(combat: Dictionary, side: int) -> void:
	var id: String = combat.effects[side].get("bard_during", "")
	if id.is_empty(): return
	var fighter: Vector2i = r._attack_pair[side]
	var opponent: Vector2i = r._attack_pair[1 - side]
	match id:
		"oda:20":
			if encircled(fighter.x, opponent): combat.values[side] = 5 + bonus(fighter, side == 0)
		"oda:27":
			if encircled(fighter.x, opponent): combat["ignore_defense" if side == 0 else "ignore_attack"] = true
		"witches:07", "witches:22": combat.values[side] += ingredients().size()
		"witches:10":
			var zones: Array = []
			for target: Vector2i in own_fighters(fighter.x):
				for zone: Variant in r.game.board.zones_for(r.game.fighters[target.x][target.y].space):
					if zone not in zones: zones.append(zone)
			combat.values[side] = zones.size() + bonus(fighter, side == 0)
		"witches:19":
			if not r.game.decks[fighter.x].is_empty():
				var top: Dictionary = r.game.decks[fighter.x].back()
				r._notice_card(top)
				r._offer_choice(opponent.x, ["hand", "cauldron"], false, "Куда положить раскрытую карту сестёр?",
					func(answer: String) -> void:
						r.game.decks[fighter.x].pop_back()
						if answer == "hand": r.game.hands[fighter.x].append(top)
						else:
							cauldron.append(top)
							combat.modifiers[side] += maxi(0, top.boost)
						r._remember_during(combat, side, "Карта передана в руку" if answer == "hand" else "Усиление из котла"), [top])
		"shakespeare:05":
			for target: Vector2i in own_fighters(fighter.x):
				if is_adjacent(target, opponent): combat.values[side] += 1
		"shakespeare:17": combat.values[side] += poem.filter(func(card: Dictionary) -> bool: return card.definition == "shakespeare:17").size()
		"hamlet:16":
			if combat.cards[1 - side].get("kind", -1) == Catalog.Kind.VERSATILE:
				combat["ignore_defense" if side == 0 else "ignore_attack"] = true
		"hamlet:25": combat.values[side] = r.game.hands[fighter.x].size() + bonus(fighter, side == 0)
		"hamlet:27":
			if not r.game.decks[fighter.x].is_empty():
				var top: Dictionary = r.game.decks[fighter.x].pop_back()
				blind_cards[fighter] = top
				discard_pile(fighter.x).append(top)
				combat.values[side] += maxi(0, top.boost)
		"titania:09": combat.values[side] += enchantment_discard.size()
		"titania:28":
			if enchantment >= 0:
				r._offer_choice(fighter.x, ["discard"], true, "Сбросьте чары · значение карты станет 5",
					func(_answer: String) -> void:
						discard_enchantment()
						combat.values[side] = 5 + bonus(fighter, side == 0)
						combat.modifiers[side] = 0)
	r._remember_during(combat, side, "Эффект карты применён")


func after(fighter: Vector2i, opponent: Vector2i, effect: Dictionary, won: bool) -> void:
	var id: String = effect.get("bard_after", "")
	if id.is_empty(): return
	var owner := fighter.x
	var card: Dictionary = r.last_combat.attack if fighter == r._attack_pair[0] else r.last_combat.defense
	var enemy_card: Dictionary = r.last_combat.defense if fighter == r._attack_pair[0] else r.last_combat.attack
	match id:
		"tomoe:01":
			if is_adjacent(fighter, opponent):
				r._offer_hand_discard(owner, true, "Сбросьте карту, чтобы вернуть сыгранную атаку в руку",
					func(key: String) -> void:
						r._discard_key(owner, key)
						returned[card.key] = true)
		"tomoe:12", "hamlet:21":
			r.actions_left = 0
			turn_ended = true
		"tomoe:17":
			if is_adjacent(fighter, opponent):
				r._offer_hand_discard(opponent.x, false, "Сбросьте карту", func(key: String) -> void: r._discard_key(opponent.x, key, true))
		"tomoe:19":
			r._offer_choice(owner, adjacent(fighter), false, "Выберите смежного бойца для 1 урона", func(target: Vector2i) -> void: r._damage_redirectable(target, 1))
		"tomoe:21":
			r._draw(owner, 1)
			if not won: r._look_hand(owner, opponent.x, r._choose_enemy_discard.bind(owner, opponent.x))
		"tomoe:26":
			if r.game.fighters[opponent.x][opponent.y].is_hero:
				r._effect_steps.push_front(r._offer_move.bind(fighter, owner, opponent, {"place": "adjacent"}))
			r._offer_move(opponent, owner, fighter, {"distance": 3})
		"oda:07": r._damage_redirectable(opponent, 1)
		"oda:10":
			r._draw(owner, 1)
			r._effect_steps.push_front(r._offer_group_move.bind(owner, own_fighters(owner), {"move_group": "own", "distance": 2}))
		"oda:17":
			if encircled(owner, opponent): heal(fighter, 2)
		"witches:05":
			if won and not r.game.decks[owner].is_empty():
				var top: Dictionary = r.game.decks[owner].back()
				r._notice_card(top)
				r._offer_choice(owner, ["hand", "cauldron"], false, "Положите раскрытую карту в руку или котёл",
					func(answer: String) -> void:
						r.game.decks[owner].pop_back()
						if answer == "hand": r.game.hands[owner].append(top)
						else: cauldron.append(top), [top])
		"witches:13":
			var source: Dictionary = r._fighter_at(fighter.x, fighter.y)
			if not source.is_empty() and not r._fighter_at(opponent.x, opponent.y).is_empty() and not rooted.has(opponent):
				var cells: Array = Array(r._free_in_zone(source.space))
				var current: int = r.game.fighters[opponent.x][opponent.y].space
				if r.game.board.same_zone(source.space, current): cells.append(current)
				r._offer_cells(owner, cells, false, "Поместите противника в вашу зону", func(cell: int) -> void: r.game.fighters[opponent.x][opponent.y].space = cell)
		"witches:27": transfer_choice(owner, cauldron, r.game.hands[owner], false, "Возьмите карту из котла")
		"witches:29":
			var amount := 0
			for loss: Dictionary in r.last_combat.losses:
				if loss.fighter == fighter: amount += int(loss.amount)
			r._damage_redirectable(opponent, amount)
		"shakespeare:03":
			var source: Dictionary = r._fighter_at(owner, fighter.y)
			if not source.is_empty():
				var targets: Array[Vector2i] = []
				for target: Vector2i in all_fighters():
					if target != fighter and r.game.board.same_zone(source.space, r.game.fighters[target.x][target.y].space): targets.append(target)
				r._damage_group(targets, 1)
		"shakespeare:09": revive_actors(owner, false)
		"shakespeare:13":
			if not won: r._heal_hero(owner, 1)
		"shakespeare:25":
			if not poem.is_empty():
				var first: Dictionary = poem[0]
				r._offer_choice(owner, ["return"], true, "Вернуть первую карту строки в руку?", func(_answer: String) -> void:
					poem.pop_front()
					r.game.hands[owner].append(first), [first])
		"hamlet:04":
			if enemy_card.get("kind", -1) == Catalog.Kind.VERSATILE: r._damage_redirectable(opponent, 2)
		"hamlet:07":
			var cards: Array = r._random_hand_discard(opponent.x, 1)
			if won and not cards.is_empty(): r._heal_hero(owner, maxi(0, cards[0].boost))
		"hamlet:10":
			if hurt.has(Vector2i(owner, 0)): r._damage_redirectable(opponent, 1)
		"hamlet:13":
			if won: r._offer_move(opponent, owner, fighter, {"distance": int(r.last_combat.damage)})
			else: r._heal_hero(owner, 1)
		"hamlet:23":
			r._offer_choice(owner, [fighter, opponent].filter(func(target: Vector2i) -> bool: return not r._fighter_at(target.x, target.y).is_empty()), false,
				"Поместите бойца на любую ячейку · он не сможет перемещаться до конца хода",
				func(target: Vector2i) -> void:
					r._effect_steps.push_front(func() -> void: rooted[target] = true)
					r._offer_move(target, owner, Vector2i(-1, -1), {"place": "anywhere"}))
		"hamlet:25":
			if won: r._offer_hand_discard(opponent.x, false, "Сбросьте карту", func(key: String) -> void: r._discard_key(opponent.x, key, true))
		"hamlet:27":
			if not won and blind_cards.has(fighter):
				var top: Dictionary = blind_cards[fighter]
				if top in r.game.discards[owner]:
					r.game.discards[owner].erase(top)
					r.game.hands[owner].append(top)
		"titania:01":
			r._offer_choice(owner, ["damage"], true, "Нанести обоим участникам боя по 2 урона?", func(_answer: String) -> void:
				var targets: Array[Vector2i] = [fighter, opponent]
				r._damage_group(targets, 2))
		"titania:03":
			var cards: Array = enchantment_discard.map(enchantment_card)
			r._offer_choice(owner, cards.map(func(shown: Dictionary) -> String: return shown.key), false, "Уберите сброшенные чары под колоду чар", func(key: String) -> void:
				var index := int(key.get_slice(":", 1))
				enchantment_discard.erase(index)
				enchantment_deck.push_front(index), cards)
		"titania:11": r._offer_move(fighter, owner, Vector2i(owner, 0), {"place": "adjacent"})
		"titania:19":
			r._effect_steps.push_front(_enchant_place.bind(fighter))
			r._offer_move(fighter, owner, opponent, {"distance": 2})
		"titania:25":
			if enchantment < 0: r._draw(owner, 1)
			else:
				r._effect_steps.push_front(r._draw.bind(owner, 1))
				r._offer_choice(owner, ["discard"], true, "Сбросьте чары, чтобы взять ещё одну карту", func(_answer: String) -> void:
					discard_enchantment()
					r._draw(owner, 1))


func scheme(fighter: Vector2i, effect: Dictionary) -> void:
	var owner := fighter.x
	match str(effect.get("bard_scheme", "")):
		"tomoe:23":
			r._effect_steps.push_front(func() -> void:
				r._offer_choice(owner, ["heal", "action"], false, "Восстановите 2 ОЗ или получите действие", func(answer: String) -> void:
					if answer == "heal": heal(fighter, 2)
					else: r.actions_left += 1))
			r._offer_move(fighter, owner, Vector2i(-1, -1), {"distance": 3, "through_sidekicks": true})
		"oda:04": two_options(owner, ["heal", "draw", "action"], "oda")
		"oda:25":
			for target: Vector2i in all_fighters():
				if target.x % 2 != owner % 2 and encircled(owner, target): r._effect_steps.push_front(r._damage_redirectable.bind(target, 2))
		"witches:03": r._prophecy(owner, Piles.peek(r.game.decks[owner], 4), 2)
		"witches:25": brew(owner, ["snake_bat", "snake_lizard", "lizard_bat", "all"], 2, false)
		"hamlet:01": bottom_hand(owner, 0)
		"hamlet:29":
			r._offer_choice(owner, ["heal", "place"], false, "Восстановите 2 ОЗ или переместитесь и получите действие", func(answer: String) -> void:
				if answer == "heal": r._heal_hero(owner, 2)
				else:
					r.actions_left += 1
					r._offer_move(fighter, owner, Vector2i(-1, -1), {"place": "zone"}))
		"titania:05":
			r._offer_seat_choice(owner, r._hostile_owners(owner), "Выберите противника", func(target: int) -> void:
				r._look_hand(owner, target, shuffle_enemy.bind(owner, target)))
		"titania:07":
			var hero: Dictionary = r._fighter_at(owner, 0)
			if not hero.is_empty():
				r._offer_choice(owner, all_fighters().filter(func(target: Vector2i) -> bool: return r.game.board.same_zone(hero.space, r.game.fighters[target.x][target.y].space)), false,
					"Выберите бойца в зоне Титании для 2 урона", func(target: Vector2i) -> void: r._damage_redirectable(target, 2))
		"titania:22": two_options(owner, ["heal", "draw", "move"], "titania")


func line_effect(owner: int, card: Dictionary) -> void:
	match str(card.definition):
		"shakespeare:01":
			if r._fighter_at(owner, 0).is_empty() or rooted.has(Vector2i(owner, 0)): return
			var actors: Array = own_fighters(owner).filter(func(target: Vector2i) -> bool: return target.y > 0)
			var cells: Array = Array(range(r.game.board.cell_count())).filter(func(cell: int) -> bool:
				return (not r._occupied().has(cell) or cell == r.game.fighters[owner][0].space) and not actors.any(func(target: Vector2i) -> bool: return r.game.board.same_zone(cell, r.game.fighters[target.x][target.y].space)))
			r._offer_cells(owner, cells, false, "Завершение строки · поместите Шекспира в зону без ваших актёров", func(cell: int) -> void: r.game.fighters[owner][0].space = cell)
		"shakespeare:03", "shakespeare:07", "shakespeare:25": r._draw(owner, 1)
		"shakespeare:05": place_every_own(owner, own_fighters(owner))
		"shakespeare:09": revive_actors(owner, true)
		"shakespeare:11": r._offer_group_move(owner, all_fighters(), {"move_group": "all", "distance": 2})
		"shakespeare:13":
			r._draw(owner, 2)
			r._heal_hero(owner, 2)
		"shakespeare:15":
			r._offer_choice(owner, all_fighters().filter(func(target: Vector2i) -> bool: return target.x % 2 != owner % 2), false,
				"Завершение строки · 2 урона противнику", func(target: Vector2i) -> void: r._damage_redirectable(target, 2))
		"shakespeare:17": r._damage_redirectable(poem_opponent, maxi(0, poem.size() - 1))
		"shakespeare:22":
			poem.erase(card)
			r.game.hands[owner].append(card)
		"shakespeare:28":
			if r.seat == owner: r.actions_left += 2


func all_fighters() -> Array:
	var result: Array = []
	for owner in r.game.heroes.size(): result.append_array(own_fighters(owner))
	return result


func place_every_own(owner: int, remaining: Array) -> void:
	var options := remaining.filter(func(target: Vector2i) -> bool:
		return not rooted.has(target) and not r._fighter_at(target.x, target.y).is_empty())
	r._offer_choice(owner, options, false, "Завершение строки · поместите каждого своего бойца", func(target: Vector2i) -> void:
		var next := remaining.duplicate()
		next.erase(target)
		r._effect_steps.push_front(place_every_own.bind(owner, next))
		var cells: Array = Array(r._empty_cells())
		cells.append(r.game.fighters[target.x][target.y].space)
		r._offer_cells(owner, cells, false, "Выберите ячейку для бойца", func(cell: int) -> void: r.game.fighters[target.x][target.y].space = cell))


func heal(target: Vector2i, amount: int) -> void:
	var figure: Dictionary = r._fighter_at(target.x, target.y)
	if not figure.is_empty(): figure.health = mini(figure.max_health, figure.health + amount)


func is_adjacent(first: Vector2i, second: Vector2i) -> bool:
	var a: Dictionary = r._fighter_at(first.x, first.y)
	var b: Dictionary = r._fighter_at(second.x, second.y)
	return not a.is_empty() and not b.is_empty() and r.game.board.adjacent(a.space, b.space)


func adjacent(fighter: Vector2i, for_swap: bool = false) -> Array:
	return all_fighters().filter(func(target: Vector2i) -> bool:
		return target != fighter and is_adjacent(fighter, target) and (not for_swap or (not rooted.has(target) and not rooted.has(fighter))))


func swap(first: Vector2i, second: Vector2i) -> bool:
	if rooted.has(first) or rooted.has(second): return false
	var a: Dictionary = r._fighter_at(first.x, first.y)
	var b: Dictionary = r._fighter_at(second.x, second.y)
	if a.is_empty() or b.is_empty(): return false
	var previous: int = a.space
	a.space = b.space
	b.space = previous
	return true


func cancel(combat: Dictionary, side: int) -> void:
	var other := 1 - side
	if combat.effects[other].get("uncancelable", false): return
	combat.effects[other] = {}
	combat.canceled[other] = true
	if side == 1:
		# Условная отмена защиты выполняется раньше отмены атакующим.
		combat.effects[1] = combat.immediate_effects[1].duplicate(true)
		combat.canceled[1] = false
		combat.immediate_effects[0] = {}


func transfer_choice(owner: int, source: Array, target: Array, optional: bool, prompt: String, then: Callable = Callable()) -> void:
	r._offer_choice(owner, source.map(func(card: Dictionary) -> String: return card.key), optional, prompt, func(key: String) -> void:
		for index in source.size():
			if source[index].key == key:
				Piles.transfer(source, index, target)
				if then.is_valid(): then.call()
				return, source)


func cauldron_heal(owner: int, remaining: int) -> void:
	if remaining <= 0 or cauldron.is_empty(): return
	transfer_choice(owner, cauldron, r.game.discards[owner], true, "Сбросьте карту котла, чтобы восстановить бойцу 1 ОЗ", func() -> void:
		r._effect_steps.push_front(cauldron_heal.bind(owner, remaining - 1))
		r._offer_choice(owner, all_fighters(), false, "Выберите бойца для восстановления 1 ОЗ", func(target: Vector2i) -> void: heal(target, 1)))


func after_attack(attacker: Vector2i) -> bool:
	if turn_ended: return false
	if r.game.heroes[attacker.x] != "witches": return false
	var available: Array = []
	var present := ingredients()
	if "snake" in present and "bat" in present: available.append("snake_bat")
	if "snake" in present and "lizard_leg" in present: available.append("snake_lizard")
	if "lizard_leg" in present and "bat" in present: available.append("lizard_bat")
	if present.size() == 3: available.append("all")
	if available.is_empty(): return false
	brew(attacker.x, available, 1, true)
	return true


func brew(owner: int, available: Array, remaining: int, clear_pot: bool) -> void:
	if remaining <= 0: return
	r._offer_choice(owner, available, clear_pot, "Выберите заклятие", func(spell: String) -> void:
		if clear_pot: r._effect_steps.push_front(func() -> void:
			r.game.discards[owner].append_array(cauldron)
			cauldron.clear())
		if remaining > 1:
			var next := available.duplicate()
			next.erase(spell)
			r._effect_steps.push_front(brew.bind(owner, next, remaining - 1, false))
		match spell:
			"snake_bat":
				r._draw(owner, 1)
				r._offer_choice(owner, own_fighters(owner), false, "Восстановите своей сестре 1 ОЗ", func(target: Vector2i) -> void: heal(target, 1))
			"snake_lizard":
				r._offer_choice(owner, all_fighters(), false, "Переместите любого бойца на 3 ячейки", func(target: Vector2i) -> void: r._offer_move(target, owner, Vector2i(-1, -1), {"distance": 3}))
			"lizard_bat":
				var targets := all_fighters().filter(func(target: Vector2i) -> bool:
					return own_fighters(owner).any(func(own: Vector2i) -> bool: return r.game.board.same_zone(r.game.fighters[own.x][own.y].space, r.game.fighters[target.x][target.y].space)))
				r._offer_choice(owner, targets, false, "Нанесите 1 урона бойцу в зоне сестры", func(target: Vector2i) -> void: r._damage_redirectable(target, 1))
			"all": r.actions_left += 1
	)
	if not available.is_empty():
		r._effect_request["labels"] = {"snake_bat": "Змея + крыло · карта и 1 ОЗ", "snake_lizard": "Змея + лапа · перемещение 3", "lizard_bat": "Лапа + крыло · 1 урон", "all": "Три ингредиента · действие"}


func revive_actors(owner: int, all: bool) -> void:
	var hero: Dictionary = r._fighter_at(owner, 0)
	if hero.is_empty(): return
	if r._free_in_zone(hero.space).is_empty(): return
	var dead: Array = []
	for index in range(1, r.game.fighters[owner].size()):
		if r.game.fighters[owner][index].health == 0: dead.append(index)
	if dead.is_empty(): return
	r._offer_choice(owner, dead, false, "Верните актёра в зону Шекспира", func(index: int) -> void:
		if all: r._effect_steps.push_front(revive_actors.bind(owner, true))
		r._offer_revive(owner, index, r._free_in_zone(hero.space)))


func _enchant_place(fighter: Vector2i) -> void:
	if enchantment >= 0:
		r._offer_choice(fighter.x, ["discard"], true, "Сбросьте чары, чтобы поместить бойца на любую ячейку", func(_answer: String) -> void:
			discard_enchantment()
			r._offer_move(fighter, fighter.x, Vector2i(-1, -1), {"place": "anywhere"}))


func bottom_hand(owner: int, count: int) -> void:
	var keys: Array = r.game.hands[owner].map(func(card: Dictionary) -> String: return card.key)
	# Общий продолжатель выполняется и при пропуске выбора.
	var selected := [false]
	r._effect_steps.push_front(func() -> void:
		if not selected[0] and count > 0:
			r._offer_choice(owner, Array(range(count + 1)), false, "Сколько карт взять после обмена?", func(amount: int) -> void: r._draw(owner, amount)))
	r._offer_choice(owner, keys, true, "Уберите карты под колоду · затем возьмите столько же", func(key: String) -> void:
		selected[0] = true
		for index in r.game.hands[owner].size():
			if r.game.hands[owner][index].key == key:
				Piles.transfer(r.game.hands[owner], index, r.game.decks[owner], 0)
				bottom_hand(owner, count + 1)
				return)


func two_options(owner: int, options: Array, kind: String, remaining: int = 2) -> void:
	if remaining <= 0: return
	r._offer_choice(owner, options, false, "Выберите два разных эффекта · осталось %d" % remaining, func(answer: String) -> void:
		var next := options.duplicate()
		next.erase(answer)
		r._effect_steps.push_front(two_options.bind(owner, next, kind, remaining - 1))
		match answer:
			"draw": r._draw(owner, 2)
			"action": r.actions_left += 1
			"heal":
				if kind == "oda":
					for target: Vector2i in all_fighters():
						if target.x % 2 == owner % 2: heal(target, 1)
				else: r._offer_choice(owner, all_fighters(), false, "Восстановите любому бойцу 2 ОЗ", func(target: Vector2i) -> void: heal(target, 2))
			"move": two_moves(owner, all_fighters(), 2)
	)


func two_moves(owner: int, targets: Array, count: int) -> void:
	if count <= 0: return
	r._offer_choice(owner, targets, false, "Переместите двух разных бойцов на 2 ячейки", func(target: Vector2i) -> void:
		var next := targets.duplicate()
		next.erase(target)
		r._effect_steps.push_front(two_moves.bind(owner, next, count - 1))
		r._offer_move(target, owner, Vector2i(-1, -1), {"distance": 2}))


func shuffle_enemy(owner: int, target: int) -> void:
	transfer_choice(owner, r.game.hands[target], r.game.decks[target], false, "Замешайте карту противника в его колоду", func() -> void: Piles.shuffle(r.game.decks[target], r.game.random))
