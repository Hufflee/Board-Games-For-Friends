extends RefCounted
## Хостовый ход Unmatched. Раздача и расстановка выполняются в UMSetup.

const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Piles := preload("res://hub/card_piles.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const CombatCards := preload("res://games/unmatched/logic/um_combat_cards.gd")
const Choice := preload("res://hub/player_choice.gd")
const Effects := preload("res://games/unmatched/logic/um_effects.gd")
const Battlefields := preload("res://games/unmatched/logic/um_battlefields.gd")

enum Phase { ACTION, MANEUVER, DISCARD, FINISHED, COMBAT_CHOICE, COMBAT_REVEAL, EFFECT_CHOICE }

const HAND_LIMIT := 7
const ACTIONS_PER_TURN := 2

var game: Setup
var seat := 0
var phase := Phase.ACTION
var actions_left := ACTIONS_PER_TURN
var winner := -1
var _moved: Dictionary = {}
var _distance := 0
var _door_fighter := -1
var _door_spent := 0
var _boosted := false
var _next_request := 1
var _combat_cards: CombatCards
var _attack_pair: Array[Vector2i] = []
var _turn_spaces: Dictionary = {}
var last_combat: Dictionary = {}
var _held_attack: Dictionary = {}
var _action_count := 0
var _won_this_turn := {}
const MISERIES := ["Тяжкий труд", "Горе", "Боль", "Невезение", "Надежда", "Алчность", "Смута"]
const MISERY_FEATHERS := [1, 0, 1, 2, 0, 1, 0]
var misery_pile: Array = []
var miseries: Array = []
var misery_opened := {}
var _misery_attack := 0
var doubloons := 2
var _revealed_override := {}
var _effect_steps: Array[Callable] = []
var _effect_request: Dictionary = {}
var _effect_apply: Callable
var _arthur_boost: Dictionary = {}
var _walk_serial := 0
var _combat_serial := 0
var during_events: Array[Dictionary] = []
var pending_impact := Callable()
var immediate_cue := {}
var board_focus := false
var combat_pause := 0.0
var _combat_continuation := Callable()
var _cue_serial := 0
var _pace_combat := false
var battlefield_items: Array[Dictionary] = []
var used_items: Array[Dictionary] = []
var _combat_items := {}
var _map_target := Vector2i(-1, -1)
var _danger_crossed := {}
var _free_scheme := false
var _item_choice_pending := false
var free_scheme_notice := {}

func _init(setup: Setup) -> void:
	game = setup
	var pool: Array = game.board.item_pool.duplicate()
	Piles.shuffle(pool, game.random)
	for index in pool.size():
		var slot: Array = game.board.item_slots[index]
		battlefield_items.append({"id": pool[index], "cell": int(slot[0]), "at": Vector2(slot[1], slot[2])})


func item_for(cell: int, combat: bool) -> Dictionary:
	for item: Dictionary in battlefield_items:
		if item.cell == cell and (Battlefields.ITEMS[item.id][2] > 0) == combat:
			return item
	return {}


func _consume_item(item: Dictionary) -> void:
	battlefield_items.erase(item)
	var used := item.duplicate()
	used["spent"] = true
	used_items.append(used)


func attack_in_range(fighter: Vector2i, cell: int) -> bool:
	var source := _fighter_at(fighter.x, fighter.y)
	return not source.is_empty() and source.space != cell and (
		fighter == _map_target or game.board.in_attack_range(source.space, cell, source.ranged))


func use_battlefield_item(viewer: int, fighter: int, id: int) -> bool:
	if not _ready_to_act(viewer):
		return false
	var source := _fighter_at(seat, fighter)
	if source.is_empty():
		return false
	var item := item_for(source.space, false)
	if item.is_empty() or item.id != id:
		return false
	_consume_item(item)
	actions_left -= 1
	_action_count += 1
	phase = Phase.EFFECT_CHOICE
	_apply_battlefield_item(Vector2i(seat, fighter), id)
	_effect_steps.append(_finish_combat_action)
	_run_effects()
	return true


func _apply_battlefield_item(fighter: Vector2i, id: int) -> void:
	var source := _fighter_at(fighter.x, fighter.y)
	if source.is_empty():
		return
	match id:
		1:
			_effect_move(fighter, Vector2i(-1, -1), {"move_group": "all", "distance": 1}, true)
		4:
			_offer_deck_scheme(fighter.x)
		5:
			_draw(fighter.x, 3)
			if phase != Phase.FINISHED:
				_offer_hand_discard(fighter.x, false, "Положите карту под свою колоду",
					func(key: String) -> void:
						for index in game.hands[fighter.x].size():
							if game.hands[fighter.x][index].key == key:
								Piles.transfer(game.hands[fighter.x], index, game.decks[fighter.x], 0)
								return)
		7:
			var targets: Array[Vector2i] = []
			for place in game.fighters.size():
				for index in game.fighters[place].size():
					if game.board.same_zone(source.space, game.fighters[place][index].space):
						targets.append(Vector2i(place, index))
			_damage_group(targets, 1)
		9:
			for place in game.heroes.size():
				for count in 2:
					_effect_steps.push_front(_item_discard.bind(place))
		11, 29:
			source.health = mini(source.max_health, source.health + (2 if id == 11 else 3))
			if id == 11:
				_draw(fighter.x, 1)
		15:
			actions_left += 1
			_offer_move(fighter, fighter.x, Vector2i(-1, -1), {"distance": 2})
		17:
			_offer_damage_target(fighter.x, source.space, false, false, 2)
		20:
			_map_target = fighter
		22:
			_after_combat(fighter, Vector2i(-1, -1), {"take_discard": []}, true)
		24:
			_offer_move(fighter, fighter.x, Vector2i(-1, -1), {"place": "anywhere", "mandatory_move": true})
		25:
			var keys: Array = game.hands[fighter.x].map(func(card: Dictionary) -> String: return card.key)
			for key: String in keys:
				_discard_key(fighter.x, key)
			_effect_steps.push_back(_draw.bind(fighter.x, 3))
		26:
			var choices: Array = Array(range(game.heroes.size())).filter(func(place: int) -> bool: return place % 2 != fighter.x % 2)
			_offer_seat_choice(fighter.x, choices, "Камера · выберите противника",
				func(place: int) -> void:
					_effect_steps.push_front(_draw.bind(fighter.x, 1))
					var shown: Array = game.hands[place]
					if not shown.is_empty():
						_offer_choice(fighter.x, ["confirm"], false, "Посмотрите руку противника", func(_a: String) -> void: pass, shown))
		30:
			_offer_seat_choice(fighter.x, Array(range(game.heroes.size())), "Зазум · выберите колоду",
				func(place: int) -> void: _order_deck_top(fighter.x, place, game.decks[place].slice(maxi(0, game.decks[place].size() - 3)), []))


func _item_discard(place: int) -> void:
	_offer_hand_discard(place, false, "Генератор ЭМИ · сбросьте карту", func(key: String) -> void: _discard_key(place, key))


func _order_deck_top(owner: int, place: int, remaining: Array, ordered: Array) -> void:
	if remaining.is_empty():
		var deck: Array = game.decks[place]
		deck.resize(deck.size() - ordered.size())
		for index in range(ordered.size() - 1, -1, -1):
			deck.append(ordered[index])
		return
	var keys: Array = remaining.map(func(card: Dictionary) -> String: return card.key)
	_offer_choice(owner, keys, false, "Зазум · выберите следующую карту сверху", func(key: String) -> void:
		for card: Dictionary in remaining:
			if card.key == key:
				remaining.erase(card)
				ordered.append(card)
				_order_deck_top(owner, place, remaining, ordered)
				return, remaining)


func _offer_deck_scheme(owner: int) -> void:
	var cards: Array = game.decks[owner].filter(func(card: Dictionary) -> bool:
		return card.kind == Catalog.S and game.fighters[owner].any(func(figure: Dictionary) -> bool:
			return figure.space >= 0 and Catalog.can_play(card, Catalog.S, figure.is_hero)))
	var keys: Array = cards.map(func(card: Dictionary) -> String: return card.key)
	if keys.is_empty():
		Piles.shuffle(game.decks[owner], game.random)
	_offer_choice(owner, keys, false, "Жаровня · выберите приём из колоды", func(key: String) -> void:
		for card: Dictionary in cards:
			if card.key != key:
				continue
			var fighters: Array = []
			for index in game.fighters[owner].size():
				var figure: Dictionary = game.fighters[owner][index]
				if figure.space >= 0 and Catalog.can_play(card, Catalog.S, figure.is_hero):
					fighters.append(Vector2i(owner, index))
			_offer_choice(owner, fighters, false, "Выберите бойца для бесплатного приёма", func(fighter: Vector2i) -> void:
				game.decks[owner].erase(card)
				Piles.shuffle(game.decks[owner], game.random)
				game.hands[owner].append(card)
				phase = Phase.ACTION
				actions_left += 1
				_effect_steps.erase(_finish_combat_action)
				_free_scheme = true
				free_scheme_notice = {"id": int(free_scheme_notice.get("id", 0)) + 1, "card": card.duplicate(true)}
				play_scheme(game.controllers[owner], fighter.y, key)
				_free_scheme = false)
			return, cards)


func clear_choices() -> void:
	pending_impact = Callable()
	during_events.clear()
	immediate_cue.clear()
	board_focus = false
	combat_pause = 0.0
	_combat_continuation = Callable()
	_effect_steps.clear()
	_effect_request.clear()
	_effect_apply = Callable()


func begin_maneuver(viewer: int) -> bool:
	if not _ready_to_act(viewer):
		return false
	actions_left -= 1
	_action_count += 1
	_draw(seat, 1)
	if not _has_fighters(seat):
		_end_action()
		return true
	_distance = _movement_distance()
	_moved.clear()
	_door_fighter = -1
	_door_spent = 0
	_boosted = false
	phase = Phase.MANEUVER
	return true


func boost_maneuver(viewer: int, key: String) -> bool:
	if not _can_act(viewer, Phase.MANEUVER) or not can_boost_maneuver():
		return false
	var index := _hand_index(key)
	if index < 0:
		return false
	var boost: int = game.hands[seat][index].boost
	if boost < 0:
		return false
	if game.heroes[seat] == "sinbad" and _is_voyage(game.hands[seat][index]):
		boost += 1
	Piles.discard(game.hands[seat], index, game.discards[seat])
	_distance += boost
	_boosted = true
	return true


func maneuver_cells(viewer: int, fighter: int) -> PackedInt32Array:
	if not _can_act(viewer, Phase.MANEUVER) or fighter < 0 or fighter >= game.fighters[seat].size() or _moved.has(fighter):
		return []
	if fighter != _door_fighter and _maneuver_in_transit():
		return []
	var figure: Dictionary = game.fighters[seat][fighter]
	if figure.space < 0:
		return []
	var remaining := _maneuver_remaining(fighter)
	var occupied := _occupied()
	var cells := game.board.reachable(figure.space, remaining, seat % 2, occupied)
	if game.board.doors.is_empty():
		return cells
	var previous := {}
	var waypoints := game.board.reachable(figure.space, remaining - 1, seat % 2, occupied, false, previous, true)
	for cell: int in waypoints:
		if not occupied.has(cell) or not _next_to_door(cell):
			continue
		var steps := 0
		var prior := cell
		while prior != figure.space:
			prior = previous[prior]
			steps += 1
		if not game.board.reachable(cell, remaining - steps, seat % 2, occupied).is_empty():
			cells.append(cell)
	return cells


func _next_to_door(cell: int) -> bool:
	for door in game.board.doors.size():
		if game.board.door_is_adjacent(door, cell):
			return true
	return false


func _maneuver_in_transit() -> bool:
	if _door_fighter < 0:
		return false
	var space: int = game.fighters[seat][_door_fighter].space
	if space < 0:
		return false
	var count := 0
	for place in game.fighters.size():
		for other: Dictionary in game.fighters[place]:
			count += int(other.space == space)
	return count > 1


func maneuver_doors(viewer: int, fighter: int) -> Array[int]:
	var options: Array[int] = []
	if not _can_act(viewer, Phase.MANEUVER):
		return options
	if fighter != _door_fighter and _maneuver_in_transit():
		return options
	var figure := _fighter_at(seat, fighter)
	if figure.is_empty():
		return options
	for door in game.board.doors.size():
		var cost := int(door in game.board.closed_doors)
		if not game.board.door_is_adjacent(door, figure.space) or cost > _maneuver_remaining(fighter) or (cost > 0 and _moved.has(fighter)):
			continue
		if _maneuver_in_transit():
			game.board.toggle_door(door)
			var exits := game.board.reachable(figure.space, _maneuver_remaining(fighter) - cost, seat % 2, _occupied())
			game.board.toggle_door(door)
			if exits.is_empty():
				continue
		options.append(door)
	return options


func toggle_maneuver_door(viewer: int, fighter: int, door: int) -> bool:
	if door not in maneuver_doors(viewer, fighter):
		return false
	var cost := int(door in game.board.closed_doors)
	game.board.toggle_door(door)
	if cost > 0:
		_track_door_fighter(fighter)
		_door_spent += cost
	return true


func _maneuver_remaining(fighter: int) -> int:
	return _distance - (_door_spent if _door_fighter == fighter else 0)


func _track_door_fighter(fighter: int) -> void:
	if _door_fighter == fighter:
		return
	if _door_fighter >= 0:
		_moved[_door_fighter] = true
	_door_fighter = fighter
	_door_spent = 0


func maneuver_preview_cells(viewer: int, fighter: int) -> PackedInt32Array:
	if not _can_act(viewer, Phase.ACTION):
		return []
	var figure := _fighter_at(seat, fighter)
	if figure.is_empty():
		return []
	return game.board.reachable(figure.space, _movement_distance(), seat % 2, _occupied())


func _movement_distance() -> int:
	var distance := int(Roster.HEROES[game.heroes[seat]].move)
	if game.heroes[seat] == "sinbad":
		distance += Piles.count_matching(game.discards[seat], _is_voyage)
	elif game.heroes[seat] == "loki":
		for place in game.heroes.size():
			if place % 2 != seat % 2:
				distance += Piles.count_matching(game.hands[place], _is_trick)
	return distance


func move_in_maneuver(viewer: int, fighter: int, cell: int) -> bool:
	if cell not in maneuver_cells(viewer, fighter):
		return false
	var figure: Dictionary = game.fighters[seat][fighter]
	var walk := game.board.route(figure.space, cell, _maneuver_remaining(fighter), seat % 2, _occupied(), false, not game.board.doors.is_empty())
	if game.board.doors.is_empty() and game.board.dangerous_paths.is_empty():
		_moved[fighter] = true
	else:
		_track_door_fighter(fighter)
		_door_spent += walk.size() - 1
	_walk_fighter(Vector2i(seat, fighter), walk)
	return true


func _walk_fighter(target: Vector2i, path: PackedInt32Array) -> void:
	var figure := _fighter_at(target.x, target.y)
	if figure.is_empty() or path.is_empty():
		return
	_walk_serial += 1
	figure["walk_serial"] = _walk_serial
	figure["walk"] = PackedInt32Array([path[0]])
	_continue_walk(target, path, 1)


func _continue_walk(target: Vector2i, path: PackedInt32Array, index: int) -> void:
	var figure := _fighter_at(target.x, target.y)
	if phase == Phase.FINISHED or figure.is_empty():
		return
	while index < path.size():
		var from := int(figure.space)
		figure.space = path[index]
		figure.walk.append(path[index])
		index += 1
		var edge := Vector2i(mini(from, figure.space), maxi(from, figure.space))
		if edge in game.board.dangerous_paths and not _danger_crossed.has(target):
			_danger_crossed[target] = true
			_effect_steps.push_front(_continue_walk.bind(target, path, index))
			_damage_redirectable(target, 1)
			return


func can_boost_maneuver() -> bool:
	return phase == Phase.MANEUVER and not _boosted and _moved.is_empty() and _door_fighter < 0


func hero_status(place: int) -> String:
	var group: Array = game.fighters[place]
	match game.heroes[place]:
		"alice":
			if not game.alice_size_selected():
				return ""
			return "Большая" if game.alice_large else "Маленькая"
		"achilles":
			return "В ярости" if not _patroclus_alive(place) else ""
		"sinbad":
			return "Путешествия: %d" % Piles.count_matching(game.discards[place], _is_voyage)
		"blackbeard":
			return "Дублоны: %d · в сундуке %d" % [doubloons, 3 - doubloons]
		"pandora":
			return "Открыто несчастий: %d" % miseries.size()
		"loki":
			var tricks := 0
			for opponent in game.heroes.size():
				if opponent % 2 != place % 2:
					tricks += Piles.count_matching(game.hands[opponent], _is_trick)
			return "Хитрости у противников: %d" % tricks
		"sun_wukong":
			return "Двойники: %d" % group.slice(1).filter(func(clone: Dictionary) -> bool: return clone.space >= 0).size()
		"yennenga":
			var protection := 0
			for archer: Dictionary in group.slice(1):
				if game.board.same_zone(group[0].space, archer.space):
					protection += int(archer.health)
			return "Защита лучников: %d" % protection
		"bloody_mary":
			if place == seat and _action_count == 2 and phase == Phase.ACTION and actions_left > 0:
				return "Следующее действие: 3-е"
			if place == seat and _action_count == 3 and phase not in [Phase.ACTION, Phase.FINISHED]:
				return "3-е действие"
	return ""


func end_maneuver(viewer: int) -> bool:
	if not _can_act(viewer, Phase.MANEUVER) or _maneuver_in_transit():
		return false
	_end_action()
	return true


func play_scheme(viewer: int, fighter: int, key: String) -> bool:
	if not _ready_to_act(viewer):
		return false
	var figure := _fighter_at(seat, fighter)
	var index := _hand_index(key)
	if figure.is_empty() or index < 0:
		return false
	var card: Dictionary = game.hands[seat][index]
	if not Catalog.can_play(card, Catalog.Kind.SCHEME, figure.is_hero) or not Effects.SCHEMES.has(card.definition):
		return false
	var effect: Dictionary = Effects.SCHEMES[card.definition]
	actions_left -= 1
	if not _free_scheme:
		_action_count += 1
	game.hands[seat].remove_at(index)
	phase = Phase.EFFECT_CHOICE
	if effect.get("draw_per_misery", false):
		_effect_steps.append(_draw.bind(seat, miseries.size()))
	_effect_steps.append(_effect_move.bind(Vector2i(seat, fighter), Vector2i(-1, -1), effect, true))
	_effect_steps.append(_scheme_choice.bind(Vector2i(seat, fighter), effect))
	_effect_steps.append(_finish_scheme.bind(card, effect))
	_run_effects()
	return true


func _finish_scheme(card: Dictionary, effect: Dictionary) -> void:
	if phase != Phase.FINISHED:
		if effect.get("heal_all", false):
			for figure: Dictionary in game.fighters[seat]:
				if figure.space >= 0:
					figure.health = mini(figure.max_health, figure.health + 1)
		_draw(seat, int(effect.get("draw", 0)))
	if phase != Phase.FINISHED:
		if effect.get("morph", false):
			game.alice_large = not game.alice_large
		if effect.get("clone_heal", false):
			var hero := _fighter_at(seat, 0)
			if not hero.is_empty():
				for clone: Dictionary in game.fighters[seat].slice(1):
					if clone.space >= 0:
						hero.health = mini(hero.max_health, hero.health + 1)
		actions_left += int(effect.get("actions", 0))
	_dispose_played(card, seat)
	if not _effect_request.is_empty():
		_effect_steps.push_front(_finish_combat_action)
		return
	if phase != Phase.FINISHED:
		_end_action()


func begin_attack(viewer: int, fighter: int, target_seat: int, target_fighter: int, key: String = "") -> bool:
	if not _ready_to_act(viewer) or target_seat % 2 == seat % 2:
		return false
	var source := _fighter_at(seat, fighter)
	var target := _fighter_at(target_seat, target_fighter)
	if source.is_empty() or target.is_empty() or not attack_in_range(Vector2i(seat, fighter), target.space):
		return false
	var attacks := _combat_keys(seat, Catalog.Kind.ATTACK, source.is_hero)
	if attacks.is_empty() or (not key.is_empty() and key not in attacks):
		return false
	var defenses := _combat_keys(target_seat, Catalog.Kind.DEFENSE, target.is_hero)
	_attack_pair = [Vector2i(seat, fighter), Vector2i(target_seat, target_fighter)]
	if _map_target == _attack_pair[0]:
		_map_target = Vector2i(-1, -1)
	_combat_items.clear()
	_combat_cards = CombatCards.new(_next_request, seat, target_seat, attacks, defenses)
	_combat_serial += 1
	_next_request += 2
	actions_left -= 1
	_action_count += 1
	phase = Phase.COMBAT_CHOICE
	if not key.is_empty():
		choose_combat_card(viewer, {"request": _next_request - 2, "hand": seat, "cards": [key]})
	return true


func attack_view(viewer: int) -> Dictionary:
	if _combat_cards == null:
		return {}
	var request := _combat_cards.pending()
	var view := {
		"id": _combat_serial,
		"attacker": _attack_pair[0],
		"defender": _attack_pair[1],
		"choosing": request.get("hand", -1),
		"attack_sealed": not _combat_cards.selected_attack_key().is_empty(),
		"cards": {} if _item_choice_pending else (_revealed_override if not _revealed_override.is_empty() else _combat_cards.revealed()),
	}
	if phase == Phase.COMBAT_CHOICE and not request.is_empty() and game.controllers[request.hand] == viewer:
		view["choice"] = request
	return view


func choose_combat_card(viewer: int, answer: Dictionary) -> bool:
	if phase != Phase.COMBAT_CHOICE:
		return false
	var submitted := _combat_cards.pending()
	if not _combat_cards.choose(game.hands, game.controllers, viewer, answer):
		return false
	var side := 0 if submitted.hand == _attack_pair[0].x else 1
	if not answer.cards.is_empty():
		var card: Dictionary = game.hands[submitted.hand].filter(func(c: Dictionary) -> bool: return c.key == answer.cards[0])[0]
		if _offer_combat_item(side, card):
			return true
	_finish_card_submission()
	return true


func _offer_combat_item(side: int, card: Dictionary) -> bool:
	var fighter := _attack_pair[side]
	var source := _fighter_at(fighter.x, fighter.y)
	var item := item_for(source.get("space", -1), true)
	if not item.is_empty():
		phase = Phase.EFFECT_CHOICE
		_item_choice_pending = true
		_effect_steps.push_front(_finish_card_submission)
		_offer_choice(fighter.x, ["use"], true, "Использовать «%s» в этом бою?" % Battlefields.ITEMS[item.id][0],
			func(_answer: String) -> void:
				_consume_item(item)
				_combat_items[side] = {"id": item.id, "before": false}
				if Effects.DURING_KEYS.any(func(effect: String) -> bool: return Effects.COMBAT.get(card.definition, {}).has(effect)):
					_offer_choice(fighter.x, ["item_first", "item_last"], false, "Порядок эффектов во время боя",
						func(order: String) -> void: _combat_items[side].before = order == "item_first"), [Battlefields.card(item.id)])
		return true
	return false


func _finish_card_submission() -> void:
	_item_choice_pending = false
	if not _combat_cards.pending().is_empty():
		phase = Phase.COMBAT_CHOICE
		if game.heroes[seat] == "arthur" and _attack_pair[0].y == 0:
			_offer_arthur_boost()
		return
	phase = Phase.COMBAT_REVEAL


func _offer_arthur_boost() -> void:
	var attack_key := _combat_cards.selected_attack_key()
	var cards := Piles.matching(game.hands[seat], func(card: Dictionary) -> bool: return card.key != attack_key and card.boost >= 0)
	var keys: Array = cards.map(func(card: Dictionary) -> String: return card.key)
	if keys.is_empty():
		return
	phase = Phase.EFFECT_CHOICE
	_offer_choice(seat, keys, true, "Усильте атаку короля Артура",
		func(key: String) -> void:
			for card: Dictionary in cards:
				if card.key == key:
					_arthur_boost = card
					return)
	_effect_steps.append(func() -> void: phase = Phase.COMBAT_CHOICE)


## Вызывает хост после показа карт. Если эффект ещё не реализован, состояние боя сохраняется.
func resolve_combat(pace_animation: bool = false) -> bool:
	if phase != Phase.COMBAT_REVEAL:
		return false
	var revealed := _combat_cards.revealed()
	var attack: Dictionary = revealed.attack
	var defense: Dictionary = revealed.defense
	return _begin_resolved_combat(attack, defense, pace_animation)


func _begin_resolved_combat(attack: Dictionary, defense: Dictionary, pace_animation: bool) -> bool:
	var parley_side := -1
	if defense.get("definition") == "blackbeard:16":
		parley_side = 1
	elif attack.get("definition") == "blackbeard:16" and not Effects.COMBAT.get(defense.get("definition"), {}).get("cancel", false):
		parley_side = 0
	if parley_side >= 0 and doubloons <= 1:
		phase = Phase.EFFECT_CHOICE
		_offer_ransom(_attack_pair[parley_side].x, 2, "Переговоры · заплатите 2 дублона, чтобы сохранить эффект",
			_resolve_combat_cards.bind(attack, defense, pace_animation, -1),
			_resolve_combat_cards.bind(attack, defense, pace_animation, parley_side))
		_run_effects()
		return true
	return _resolve_combat_cards(attack, defense, pace_animation, -1)


func _resolve_combat_cards(attack: Dictionary, defense: Dictionary, pace_animation: bool, paid_parley: int) -> bool:
	during_events.clear()
	immediate_cue = {}
	_pace_combat = pace_animation
	var attack_effect := _combat_effect(attack, _attack_pair[0].x)
	var defense_effect := _combat_effect(defense, _attack_pair[1].x)
	if attack_effect.get("god_mischief", false) and not _is_trick(defense):
		attack_effect["cancel"] = true
	if defense_effect.get("god_mischief", false) and not _is_trick(attack):
		defense_effect["cancel"] = true
	if paid_parley == 0:
		attack_effect = {}
	elif paid_parley == 1:
		defense_effect = {}
	var attack_canceled: bool = defense_effect.get("cancel", false) and not attack_effect.get("uncancelable", false)
	var defense_canceled: bool = not attack_canceled and attack_effect.get("cancel", false)
	# «Немедленно» защиты уже срабатывает до отмены атакующим (FAQ, стр. 69).
	var defense_immediate := defense_effect.duplicate(true)
	if not attack_canceled and not Effects.COMBAT.has(attack.definition):
		return false
	if not defense.is_empty() and not defense_canceled and not Effects.COMBAT.has(defense.definition):
		return false
	if attack_canceled:
		attack_effect = {}
	if defense_canceled:
		defense_effect = {}
	var attacker := _attack_pair[0]
	var defender := _attack_pair[1]
	if _held_attack.is_empty():
		_take_combat_card(attacker.x, attack.key)
		_held_attack = attack
	if not defense.is_empty():
		_take_combat_card(defender.x, defense.key)
	if not _arthur_boost.is_empty():
		_take_combat_card(attacker.x, _arthur_boost.key)
	var combat := {"cards": [attack, defense], "effects": [attack_effect, defense_effect],
		"immediate_effects": [attack_effect, defense_immediate],
		"canceled": [attack_canceled, defense_canceled], "values": [attack.value, defense.get("value", 0)], "modifiers": [0, 0],
		"ignore_defense": false, "reflect": false}
	if not _arthur_boost.is_empty() and not attack_canceled:
		combat.modifiers[0] = _arthur_boost.boost
	phase = Phase.EFFECT_CHOICE
	_effect_steps.append(_show_immediate.bind(combat, 1))
	_effect_steps.append(_show_immediate.bind(combat, 0))
	_effect_steps.append(_combat_item_during.bind(combat, 1, true))
	_effect_steps.append(_combat_during.bind(combat, 1))
	_effect_steps.append(_combat_item_during.bind(combat, 1, false))
	_effect_steps.append(_combat_item_during.bind(combat, 0, true))
	_effect_steps.append(_combat_during.bind(combat, 0))
	_effect_steps.append(_combat_item_during.bind(combat, 0, false))
	_effect_steps.append(_prepare_combat_impact.bind(combat, pace_animation))
	_run_effects()
	return true


func _combat_item_during(combat: Dictionary, side: int, before: bool) -> void:
	if phase == Phase.FINISHED or not _combat_items.has(side) or combat.cards[side].is_empty():
		return
	var item: Dictionary = _combat_items[side]
	if item.before != before or combat.canceled[side]:
		return
	combat.values[side] += int(Battlefields.ITEMS[item.id][2])
	_remember_during(combat, side, "%s · +%d" % [Battlefields.ITEMS[item.id][0], Battlefields.ITEMS[item.id][2]])


func _show_immediate(combat: Dictionary, side: int) -> void:
	var effect: Dictionary = combat.immediate_effects[side]
	var swap: bool = effect.get("swap_patroclus", false) and _patroclus_alive(_attack_pair[side].x)
	var board: bool = swap or effect.has("archer_attack") or effect.has("discard_or_revive") or effect.has("replace_enemy_card")
	if not _pace_combat or not (board or effect.has("cancel") or effect.has("discard_or_ignore")
			or effect.has("ransom_hand") or effect.has("ransom_random") or effect.has("god_mischief")):
		_combat_immediate(combat, side)
		return
	_cue_serial += 1
	var message := "Немедленный эффект"
	if effect.has("cancel") and combat.canceled[1 - side]:
		message = "Эффекты карты противника отменены"
	immediate_cue = {"id": _cue_serial, "side": side, "message": message}
	_pause_combat(0.95, _apply_immediate.bind(combat, side, board))


func _apply_immediate(combat: Dictionary, side: int, board: bool) -> void:
	if board:
		_effect_steps.push_front(_close_board_focus)
		_effect_steps.push_front(_combat_immediate.bind(combat, side))
		_open_board_focus()
	else:
		_combat_immediate(combat, side)


func _pause_combat(seconds: float, resume: Callable = Callable()) -> void:
	combat_pause = seconds
	_combat_continuation = resume


func resume_combat() -> void:
	var resume := _combat_continuation
	_combat_continuation = Callable()
	combat_pause = 0.0
	if resume.is_valid():
		resume.call()
	_run_effects()


func _open_board_focus() -> void:
	board_focus = true
	_pause_combat(0.28)


func _close_board_focus() -> void:
	if phase == Phase.FINISHED:
		board_focus = false
		return
	_pause_combat(1.20, func() -> void: board_focus = false)


func _combat_immediate(combat: Dictionary, side: int) -> void:
	var effect: Dictionary = combat.immediate_effects[side]
	var fighter := _attack_pair[side]
	var opponent := _attack_pair[1 - side]
	if effect.get("god_mischief", false) and _is_trick(combat.cards[1 - side]):
		combat["ignore_defense" if side == 0 else "ignore_attack"] = true
	if effect.get("ignore_defense", false) and side == 0:
		combat.ignore_defense = true
	if effect.get("ransom_hand", false):
		_offer_ransom(fighter.x, 1, "Заплатите дублон, чтобы сохранить руку",
			func() -> void: _pick_discard(fighter.x, opponent.x))
	if effect.get("ransom_random", false):
		_offer_ransom(fighter.x, 1, "Заплатите дублон, чтобы избежать случайного сброса",
			func() -> void: _random_hand_discard(opponent.x, 1))
	if effect.get("swap_patroclus", false) and _patroclus_alive(fighter.x):
		_offer_choice(fighter.x, [Vector2i(fighter.x, 1)], true, "Выберите Патрокла для обмена местами",
			func(_answer: Vector2i) -> void:
				var group: Array = game.fighters[fighter.x]
				var previous: int = group[0].space
				group[0].space = group[1].space
				group[1].space = previous
				_attack_pair[side] = Vector2i(fighter.x, 1))
	if effect.get("archer_attack", false):
		var archer := _inactive_sidekick(fighter.x)
		var target := _fighter_at(opponent.x, opponent.y)
		var cells := _free_in_zone(target.space)
		if archer < 0 or cells.is_empty():
			actions_left += 1
		else:
			_offer_choice(fighter.x, ["action", "archer"], false, "Получите действие или верните Лучника",
				func(answer: String) -> void:
					if answer == "action":
						actions_left += 1
					else:
						_offer_revive(fighter.x, archer, cells,
							func() -> void: _attack_pair[side] = Vector2i(fighter.x, archer)))
	if effect.get("discard_or_revive", false):
		var archer := _inactive_sidekick(fighter.x)
		var cells := _free_in_zone(game.fighters[fighter.x][0].space)
		_effect_steps.push_front(_discard_or_archer.bind(fighter.x, opponent.x, archer, cells))
	if effect.get("discard_or_ignore", false):
		combat.ignore_defense = true
		_offer_hand_discard(opponent.x, true, "Сбросьте карту, чтобы сохранить значение защиты",
			func(key: String) -> void:
				_discard_key(opponent.x, key)
				combat.ignore_defense = false)
	if side == 0 and effect.get("replace_enemy_card", false) and not combat.cards[1].is_empty():
		_replace_defense(combat)


## Защита уже выполнила «Немедленно». Новая карта не повторяет пройденный этап.
func _replace_defense(combat: Dictionary) -> void:
	var defender := _attack_pair[1]
	game.hands[defender.x].append(combat.cards[1])
	var shown: Array = game.hands[defender.x]
	var allowed := _combat_keys(defender.x, Catalog.Kind.DEFENSE, game.fighters[defender.x][defender.y].is_hero)
	if allowed.is_empty():
		_set_replacement_defense(combat, {})
		return
	_offer_choice(_attack_pair[0].x, allowed, false, "Поиск неприятностей · выберите карту защиты противника",
		func(key: String) -> void:
			for card: Dictionary in shown:
				if card.key == key:
					_take_combat_card(defender.x, key)
					_set_replacement_defense(combat, card)
					return, shown)


func _set_replacement_defense(combat: Dictionary, card: Dictionary) -> void:
	combat.cards[1] = card
	combat.effects[1] = _combat_effect(card, _attack_pair[1].x)
	combat.values[1] = card.get("value", 0)
	combat.canceled[1] = false
	_revealed_override = {"attack": combat.cards[0], "defense": card}


func _discard_or_archer(owner: int, opponent: int, archer: int, cells: Array) -> void:
	var discarded := [false]
	_effect_steps.push_front(func() -> void:
		if archer >= 0 and not discarded[0]:
			_offer_revive(owner, archer, cells))
	_offer_hand_discard(opponent, true, "Сбросьте карту или противник вернёт Лучника",
		func(key: String) -> void:
			_discard_key(opponent, key)
			discarded[0] = true)


func _combat_during(combat: Dictionary, side: int) -> void:
	if phase == Phase.FINISHED or combat.cards[side].is_empty():
		return
	var fighter := _attack_pair[side]
	var opponent := _attack_pair[1 - side]
	var effect: Dictionary = combat.effects[side]
	# Ранее применённое усиление входит в текущее значение и заменяется эффектом «становится равно».
	# Способность Артура постоянная: её прибавка сохраняется после такой замены (FAQ, стр. 8, 23, 42).
	var constant_boost: int = _arthur_boost.get("boost", 0) if side == 0 and not combat.canceled[0] else 0
	var base: int = combat.values[side] + combat.modifiers[side] - constant_boost
	combat.modifiers[side] = constant_boost
	var discard_count: int = game.discards[fighter.x].size()
	combat.values[side] = _combat_value(fighter, opponent, combat.cards[side], combat.cards[1 - side], effect, base)
	var discarded := int(game.discards[fighter.x].size() > discard_count)
	if effect.get("random_boost", false):
		var cards := _random_hand_discard(opponent.x, 1)
		if not cards.is_empty():
			combat.modifiers[side] += maxi(0, cards[0].boost)
			discarded += 1
	if (combat.values[side] != base and not effect.get("reprise", false)) or discarded > 0:
		var message := "Сброшена 1 карта" if discarded > 0 else "Значение карты изменилось"
		if effect.get("blind_boost", false) and discarded > 0:
			var top: Dictionary = game.discards[fighter.x].back()
			message = "Сброшена «%s» · усиление +%d" % [top.name, maxi(0, top.boost)]
		_remember_during(combat, side, message)
	if side == 1 and effect.get("prevent_damage", false):
		_remember_during(combat, side, "Боевой урон предотвращён")
	if side == 1 and effect.get("ignore_attack", false):
		combat["ignore_attack"] = true
		_remember_during(combat, side, "Значение карты атаки игнорируется")
	combat.values[side] += _fighter_combat_bonus(fighter, side == 0)
	if effect.get("boost", false) or (effect.get("boost_after_win", false) and _won_this_turn.has(fighter.x)):
		_offer_boost(combat, side, side)
	if effect.get("boost_enemy", false) and not combat.cards[1 - side].is_empty():
		_offer_boost(combat, 1 - side, side)
	if effect.get("adjust", false):
		_offer_choice(fighter.x, [-1, 1], true, "Измените значение карты",
			func(adjustment: int) -> void:
				combat.modifiers[side] += adjustment
				_remember_during(combat, side, "Значение карты изменилось"))
		_effect_request["modifier_choice"] = true
	if effect.get("reflect", false):
		_offer_choice(fighter.x, ["reflect"], true, "Перенаправьте боевой урон",
			func(_answer: String) -> void:
				combat.reflect = true
				_remember_during(combat, side, "Боевой урон перенаправлен"))
	if effect.get("sacrifice_patroclus", false):
		_offer_choice(fighter.x, ["sacrifice"], true, "Нанесите Патроклу 2 урона ради атаки 5",
			func(_answer: String) -> void:
				_damage(fighter, 2)
				combat.values[side] = 5)
	if effect.get("queen_anne", false):
		_queen_tribute(combat, side, _hostile_owners(fighter.x))
	if effect.get("sindri", false):
		var paid := [false]
		_effect_steps.push_front(func() -> void:
			if not paid[0]:
				var target := 1 - side
				combat.values[target] = maxi(0, combat.values[target] + combat.modifiers[target] - 3)
				combat.modifiers[target] = 0
				_remember_during(combat, side, "Значение карты противника уменьшено на 3"))
		_offer_hand_discard(opponent.x, true, "Пари с Синдри · сбросьте карту, чтобы сохранить значение",
			func(key: String) -> void:
				paid[0] = true
				_discard_key(opponent.x, key))
	if effect.get("laevateinn", false):
		_reveal_loki_card(combat, side, opponent.x)
	if effect.get("shapeshift", false):
		_offer_choice(fighter.x, ["strength", "action"], false, "Выберите эффект Оборотня",
			func(option: String) -> void:
				if option == "action":
					actions_left += 1
					_remember_during(combat, side, "Получено дополнительное действие")
				else:
					combat.modifiers[side] += game.hands[opponent.x].size()
					_remember_during(combat, side, "Добавлена сила за карты противника"))
	if effect.get("freyja", false) and not combat.cards[1 - side].is_empty():
		var first: int = combat.values[0] + combat.modifiers[0]
		var second: int = combat.values[1] + combat.modifiers[1]
		combat.values = [second, first]
		combat.modifiers = [0, 0]
		_remember_during(combat, side, "Значения карт поменялись местами")


func _offer_boost(combat: Dictionary, side: int, source: int) -> void:
	var owner := _attack_pair[side].x
	var cards := Piles.matching(game.hands[owner], func(card: Dictionary) -> bool: return card.boost >= 0)
	var keys: Array = cards.map(func(card: Dictionary) -> String: return card.key)
	_offer_choice(owner, keys, true, "Выберите карту для усиления",
		func(key: String) -> void:
			for card: Dictionary in cards:
				if card.key == key:
					combat.modifiers[side] += card.boost
					_discard_key(owner, key)
					_remember_during(combat, source, "Сброшена 1 карта для усиления")
					return)


func _remember_during(combat: Dictionary, source: int, message: String) -> void:
	during_events.append({"side": source, "message": message, "values": [
		combat.values[0] + combat.modifiers[0],
		combat.values[1] + combat.modifiers[1],
	]})


func _prepare_combat_impact(combat: Dictionary, pace_animation: bool) -> void:
	if pace_animation and not during_events.is_empty():
		pending_impact = _deal_combat_damage.bind(combat)
	else:
		_deal_combat_damage(combat)


func finish_combat_impact() -> void:
	var impact := pending_impact
	pending_impact = Callable()
	impact.call()
	_run_effects()


func _deal_combat_damage(combat: Dictionary) -> void:
	var attacker := _attack_pair[0]
	var defender := _attack_pair[1]
	var attack_value: int = combat.values[0] + combat.modifiers[0]
	var defense_value: int = combat.values[1] + combat.modifiers[1]
	var source: Dictionary = game.fighters[attacker.x][attacker.y]
	var target: Dictionary = game.fighters[defender.x][defender.y]
	attack_value += game.board.attack_bonus(source.space, target.space)
	combat["card_values"] = [attack_value, defense_value]
	if combat.get("ignore_attack", false):
		attack_value = 0
	if combat.ignore_defense:
		defense_value = 0
	var damage := 0 if combat.effects[1].get("prevent_damage", false) else maxi(0, attack_value - defense_value)
	var attacker_won: bool = damage > 0 and not combat.reflect
	var recipient := attacker if combat.reflect else defender
	var health_before := {}
	for place in game.fighters.size():
		for index in game.fighters[place].size():
			health_before[Vector2i(place, index)] = game.fighters[place][index].health
	combat["health_before"] = health_before
	_effect_steps.push_front(_after_combat_damage.bind(combat, damage, attack_value, defense_value, attacker_won))
	_damage_redirectable(recipient, damage)


func _after_combat_damage(combat: Dictionary, damage: int, attack_value: int, defense_value: int, attacker_won: bool) -> void:
	var attacker := _attack_pair[0]
	var defender := _attack_pair[1]
	var attack: Dictionary = combat.cards[0]
	var defense: Dictionary = combat.cards[1]
	var attack_effect: Dictionary = combat.effects[0]
	var defense_effect: Dictionary = combat.effects[1]
	_won_this_turn[(attacker if attacker_won else defender).x] = true
	var losses: Array = []
	for fighter: Vector2i in combat.health_before:
		var amount: int = combat.health_before[fighter] - game.fighters[fighter.x][fighter.y].health
		if amount > 0:
			losses.append({"fighter": fighter, "amount": amount})
			if fighter.y == 0 and game.heroes[fighter.x] == "blackbeard":
				doubloons = maxi(0, doubloons - 1)
	last_combat = {"id": _combat_serial, "losses": losses,
		"attack": attack, "defense": defense, "damage": damage, "attacker_won": attacker_won,
		"reflected": combat.reflect,
		"card_values": combat.card_values,
		"attack_value": attack_value, "defense_value": defense_value,
		"attack_canceled": combat.canceled[0], "defense_canceled": combat.canceled[1]}
	var board_after := _pace_combat and phase != Phase.FINISHED and (
		_uses_board_after(defense_effect, not attacker_won) or _uses_board_after(attack_effect, attacker_won))
	if board_after:
		last_combat["board_after"] = true
		_effect_steps.append(_pause_combat.bind(1.45, _open_board_focus))
	_effect_steps.append(_effect_move.bind(defender, attacker, defense_effect, not attacker_won))
	_effect_steps.append(_after_combat.bind(defender, attacker, defense_effect, not attacker_won))
	_effect_steps.append(_effect_move.bind(attacker, defender, attack_effect, attacker_won))
	_effect_steps.append(_after_combat.bind(attacker, defender, attack_effect, attacker_won))
	if board_after:
		_effect_steps.append(_close_board_focus)
	_effect_steps.append(_finish_combat.bind(attack, defense, attack_effect, attacker_won))


func _uses_board_after(effect: Dictionary, won: bool) -> bool:
	for key: String in ["place", "move", "move_group"]:
		if effect.has(key) and (won or not effect.has("win_move")):
			return true
	for key: String in ["damage", "adjacent_target", "adjacent_damage", "splash", "splash_all", "clone_swap", "damage_path", "alice_options", "mirror_after", "discard_enemy", "tooth_tail", "sea_dog", "ransom_pistols", "ransom_zone"]:
		if effect.has(key):
			return true
	return won and effect.has("win_damage")


func _finish_combat(attack: Dictionary, defense: Dictionary, attack_effect: Dictionary, attacker_won: bool) -> void:
	var attacker := _attack_pair[0]
	var defender := _attack_pair[1]
	var winning_fighter := attacker if attacker_won else defender
	if game.heroes[winning_fighter.x] == "achilles" and winning_fighter.y == 0 and not _patroclus_alive(winning_fighter.x):
		_draw(winning_fighter.x, 1)
	if not defense.is_empty():
		if attacker_won and not last_combat.defense_canceled and Effects.COMBAT.get(defense.definition, {}).get("return_defense_on_loss", false):
			game.hands[defender.x].append(defense)
		else:
			_dispose_played(defense, defender.x, attacker.x)
	if attack_effect.get("follow_up", false) and (not attack_effect.get("needs_defense", false) or not defense.is_empty()):
		_combat_items.clear()
		if _begin_follow_up(attack, defense):
			return
	_dispose_played(_held_attack, attacker.x, defender.x)
	_held_attack = {}
	if not _arthur_boost.is_empty():
		game.discards[attacker.x].append(_arthur_boost)
		_arthur_boost = {}
	_combat_cards = null
	immediate_cue = {}
	_revealed_override = {}
	if game.heroes[attacker.x] == "robin_hood":
		_effect_steps.push_front(_finish_combat_ability)
		_offer_move(attacker, attacker.x, defender, {"move": "self", "distance": 2})
		return
	_finish_combat_ability()


func _finish_combat_ability() -> void:
	var attacker := _attack_pair[0]
	_attack_pair.clear()
	if phase != Phase.FINISHED and game.heroes[attacker.x] == "chupacabra" and not _fighter_at(attacker.x, 0).is_empty():
		_offer_choice(attacker.x, ["draw"], true, "Голод во плоти · возьмите 1 карту",
			func(_answer: String) -> void: _draw(attacker.x, 1))
		_effect_steps.push_front(_finish_combat_action)
		return
	_finish_combat_action()


func _finish_combat_action() -> void:
	if phase != Phase.FINISHED:
		_end_action()


func effect_view(viewer: int) -> Dictionary:
	if _effect_request.is_empty() or game.controllers[_effect_request.seat] != viewer:
		return {}
	return _effect_request.duplicate(true)


func has_combat_choice() -> bool:
	return _combat_cards != null and not _effect_request.is_empty() and _combat_cards.pending().is_empty()


func choosing_seat() -> int:
	if not game.pending().is_empty():
		return game.pending().seat
	if not _effect_request.is_empty():
		return _effect_request.seat
	if phase == Phase.COMBAT_CHOICE:
		return _combat_cards.pending().hand
	if phase == Phase.COMBAT_REVEAL or phase == Phase.FINISHED or pending_impact.is_valid() or combat_pause > 0.0:
		return -1
	return seat


func choose_effect(viewer: int, request_id: int, answer: Variant) -> bool:
	var request := effect_view(viewer)
	if request.is_empty() or request.id != request_id or not Choice.accepts(request, request.seat, answer):
		return false
	var apply := _effect_apply
	_effect_request = {}
	_effect_apply = Callable()
	if answer != null:
		apply.call(answer)
	_run_effects()
	return true


func _run_effects() -> void:
	while not _effect_steps.is_empty() and _effect_request.is_empty() and combat_pause <= 0.0:
		var step: Callable = _effect_steps.pop_front()
		step.call()


func _offer_choice(place: int, options: Array, optional: bool, prompt: String, apply: Callable, shown: Array = []) -> void:
	if options.is_empty():
		return
	_effect_request = Choice.request(place, options, optional)
	_effect_request["id"] = _next_request
	_effect_request["prompt"] = prompt
	if not shown.is_empty():
		_effect_request["shown"] = shown.duplicate(true)
	_next_request += 1
	_effect_apply = apply


func _offer_seat_choice(place: int, options: Array, prompt: String, apply: Callable) -> void:
	_offer_choice(place, options, false, prompt, apply)
	if not options.is_empty():
		_effect_request["seat_choice"] = true
		var labels := {}
		for owner: int in options:
			labels[owner] = Roster.HEROES[game.heroes[owner]].name
		_effect_request["labels"] = labels


func _offer_cells(place: int, options: Array, optional: bool, prompt: String, apply: Callable) -> void:
	_offer_choice(place, options, optional, prompt, apply)
	if not options.is_empty():
		_effect_request["cells"] = true


func _offer_hand_discard(place: int, optional: bool, prompt: String, apply: Callable) -> void:
	var keys: Array = game.hands[place].map(func(card: Dictionary) -> String: return card.key)
	_offer_choice(place, keys, optional, prompt, apply)
	if not keys.is_empty():
		_effect_request["hand_discard"] = true


func _effect_move(fighter: Vector2i, opponent: Vector2i, effect: Dictionary, won: bool) -> void:
	if phase == Phase.FINISHED or (effect.get("win_move", false) and not won):
		return
	if effect.has("place"):
		_offer_move(fighter, fighter.x, opponent, effect)
		return
	if effect.get("move_any_enemy", false):
		var options: Array = []
		for place in game.fighters.size():
			if place % 2 == fighter.x % 2:
				continue
			for index in game.fighters[place].size():
				var target := Vector2i(place, index)
				if not _movement_cells(target, opponent, effect).is_empty():
					options.append(target)
		_offer_choice(fighter.x, options, true, "Выберите противника для перемещения",
			func(target: Vector2i) -> void: _offer_move(target, fighter.x, opponent, effect))
		return
	if effect.has("move_group"):
		var targets: Array = []
		for place in game.heroes.size():
			if effect.move_group != "all" and place != fighter.x:
				continue
			for index in game.fighters[place].size():
				if effect.move_group != "sidekicks" or index > 0:
					targets.append(Vector2i(place, index))
		_offer_group_move(fighter.x, targets, effect)
		return
	match effect.get("move", ""):
		"hero":
			_offer_move(Vector2i(fighter.x, 0), fighter.x, opponent, effect)
		"self":
			_offer_move(fighter, fighter.x, opponent, effect)
		"enemy":
			_offer_move(opponent, fighter.x, opponent, effect)
		"either":
			var options: Array = []
			for target: Vector2i in [fighter, opponent]:
				if not _movement_cells(target, opponent, effect).is_empty():
					options.append(target)
			_offer_choice(fighter.x, options, true, "Выберите бойца для перемещения",
				func(target: Vector2i) -> void: _offer_move(target, fighter.x, opponent, effect))


func _offer_move(target: Vector2i, owner: int, opponent: Vector2i, effect: Dictionary) -> void:
	if not game.board.dangerous_paths.is_empty() and not effect.has("place"):
		_offer_path_step(target, owner, effect.distance, effect.get("through_enemies", false))
		return
	var cells := _movement_cells(target, opponent, effect)
	_offer_cells(owner, Array(cells), not effect.get("mandatory_move", false), "Выберите клетку",
		func(cell: int) -> void:
			var figure: Dictionary = game.fighters[target.x][target.y]
			if effect.has("place"):
				figure["walk"] = []
				_walk_serial += 1
				figure["walk_serial"] = _walk_serial
				figure.space = cell
			else:
				_walk_fighter(target, game.board.route(figure.space, cell, effect.distance, target.x % 2,
					_occupied(), effect.get("through_enemies", false))))


func _offer_path_step(target: Vector2i, owner: int, remaining: int, through_enemies: bool) -> void:
	var figure := _fighter_at(target.x, target.y)
	if figure.is_empty() or remaining <= 0 or phase == Phase.FINISHED:
		return
	var occupied := _occupied()
	var options: Array = []
	for cell: int in game.board.movement_neighbors(figure.space):
		if occupied.has(cell):
			if (not through_enemies and occupied[cell] != target.x % 2) or remaining <= 1:
				continue
			if game.board.reachable(cell, remaining - 1, target.x % 2, occupied, through_enemies).is_empty():
				continue
		options.append(cell)
	var in_transit := game.fighters.any(func(group: Array) -> bool:
		return group.any(func(other: Dictionary) -> bool: return not is_same(other, figure) and other.space == figure.space))
	_offer_cells(owner, options, not in_transit, "Выберите следующий шаг · осталось %d" % remaining,
		func(cell: int) -> void:
			var path := PackedInt32Array([figure.space, cell])
			_effect_steps.push_front(_offer_path_step.bind(target, owner, remaining - 1, through_enemies))
			_walk_fighter(target, path))


func _offer_group_move(owner: int, remaining: Array, effect: Dictionary) -> void:
	var options := remaining.filter(func(target: Vector2i) -> bool:
		return not _movement_cells(target, Vector2i(-1, -1), effect).is_empty())
	var prompt := "Выберите следующего бойца · союзника или противника" if effect.move_group == "all" else "Выберите следующего бойца"
	_offer_choice(owner, options, true, prompt,
		func(target: Vector2i) -> void:
			remaining.erase(target)
			_effect_steps.push_front(_offer_group_move.bind(owner, remaining, effect))
			_offer_move(target, owner, Vector2i(-1, -1), effect))


func _movement_cells(target: Vector2i, opponent: Vector2i, effect: Dictionary) -> PackedInt32Array:
	var figure := _fighter_at(target.x, target.y)
	if figure.is_empty():
		return []
	var occupied := _occupied()
	if not effect.has("place"):
		return game.board.reachable(figure.space, effect.distance, target.x % 2, occupied, effect.get("through_enemies", false))
	var enemy := _fighter_at(opponent.x, opponent.y)
	var cells := PackedInt32Array()
	for cell in game.board.cell_count():
		if occupied.has(cell):
			continue
		if effect.place == "adjacent" and (enemy.is_empty() or not game.board.adjacent(enemy.space, cell)):
			continue
		if effect.place == "zone" and not game.board.same_zone(figure.space, cell):
			continue
		cells.append(cell)
	return cells


func _occupied() -> Dictionary:
	var occupied := {}
	for place in game.fighters.size():
		for other: Dictionary in game.fighters[place]:
			if other.space >= 0:
				occupied[other.space] = place % 2
	return occupied


func _begin_follow_up(attack: Dictionary, defense: Dictionary) -> bool:
	if phase == Phase.FINISHED:
		return false
	var attacker := _attack_pair[0]
	var defender := _attack_pair[1]
	var target := _fighter_at(defender.x, defender.y)
	if target.is_empty() or _fighter_at(attacker.x, attacker.y).is_empty():
		return false
	var follow_up := attack.duplicate(true)
	follow_up.definition = "follow_up"
	follow_up.name = attack.follow_up.name
	follow_up.value = attack.follow_up.value
	if attack.definition == "bloody_mary:07":
		follow_up.definition = "bloody_mary_reprise"
		follow_up["reprise_value"] = int(defense.get("value", 0))
	follow_up.erase("follow_up")
	var defenses := _combat_keys(defender.x, Catalog.Kind.DEFENSE, target.is_hero)
	immediate_cue = {}
	_revealed_override = {}
	_combat_cards = CombatCards.new(_next_request, attacker.x, defender.x, [], defenses, follow_up)
	_combat_serial += 1
	_next_request += 2
	phase = Phase.COMBAT_CHOICE
	_offer_combat_item(0, follow_up)
	return true


func _combat_value(fighter: Vector2i, opponent: Vector2i, card: Dictionary, opposing_card: Dictionary, effect: Dictionary, value: int) -> int:
	var figure: Dictionary = game.fighters[fighter.x][fighter.y]
	var other: Dictionary = game.fighters[opponent.x][opponent.y]
	var origin: int = _turn_spaces.get(fighter, -1)
	if effect.get("shift", false) and origin >= 0 and origin != figure.space:
		value = 5
	if effect.has("against_hero") and other.is_hero:
		value = effect.against_hero
	if effect.has("third") and _action_count == 3:
		value = effect.third
	if effect.has("zone_shift") and origin >= 0 and not game.board.same_zone(origin, figure.space):
		value = effect.zone_shift
	if effect.get("mirror_printed", false):
		value = opposing_card.get("value", 0)
	if effect.get("twice_printed", false):
		value = int(opposing_card.get("value", 0)) * 2
	if effect.get("per_misery", false):
		value += miseries.size()
	if effect.get("underhanded", false) and game.hands[opponent.x].size() > game.hands[fighter.x].size():
		value = 6
	if effect.get("per_enemy_trick", false):
		value += 3 * Piles.count_matching(game.hands[opponent.x], _is_trick)
	if effect.has("wounded_value") and figure.health <= 7:
		value = effect.wounded_value
	if effect.get("reprise", false):
		value = card.reprise_value
	if effect.has("far_archer") and not game.board.same_zone(figure.space, game.fighters[fighter.x][0].space):
		value = effect.far_archer
	if effect.get("enemy_zones", false):
		value += game.board.zones_for(other.space).size()
	if effect.get("flank", false):
		for ally: Dictionary in game.fighters[fighter.x]:
			if not is_same(ally, figure) and game.board.adjacent(ally.space, other.space):
				value += 1
	if effect.has("flank_value"):
		for place in game.fighters.size():
			if place % 2 == fighter.x % 2 and game.fighters[place].any(func(ally: Dictionary) -> bool:
					return not is_same(ally, figure) and game.board.adjacent(ally.space, other.space)):
				value = effect.flank_value
				break
	if effect.get("voyages", false):
		value += Piles.count_matching(game.discards[fighter.x], _is_voyage)
	if effect.get("blind_boost", false) and not game.decks[fighter.x].is_empty():
		var deck: Array = game.decks[fighter.x]
		var boost: int = deck[-1].boost
		Piles.transfer(deck, Piles.top_index(deck), game.discards[fighter.x])
		value += maxi(0, boost)
	return value


func _fighter_combat_bonus(fighter: Vector2i, attacking: bool) -> int:
	var figure: Dictionary = game.fighters[fighter.x][fighter.y]
	if attacking and figure.is_hero and game.heroes[fighter.x] == "achilles" and not _patroclus_alive(fighter.x):
		return 2
	if attacking and game.heroes[fighter.x] == "pandora":
		return _misery_attack
	if figure.is_hero and game.heroes[fighter.x] == "alice":
		if attacking and game.alice_large:
			return 2
		elif not attacking and not game.alice_large:
			return 1
	return 0


func _after_combat(fighter: Vector2i, opponent: Vector2i, effect: Dictionary, won: bool) -> void:
	if phase == Phase.FINISHED:
		return
	var damage := int(effect.get("damage", 0)) + (int(effect.get("win_damage", 0)) if won else 0)
	if damage > 0 and effect.has("self_damage"):
		_damage(fighter, effect.self_damage)
	_damage_redirectable(opponent, damage)
	if phase == Phase.FINISHED:
		return
	var figure := _fighter_at(fighter.x, fighter.y)
	if effect.has("adjacent_target") and not figure.is_empty():
		_offer_damage_target(fighter.x, figure.space, false, true, effect.adjacent_target)
	if effect.get("alice_options", false):
		_alice_options(fighter.x, ["draw", "heal", "place"], [])
	if effect.get("clone_swap", false) and fighter.y == 0 and not figure.is_empty():
		_clone_swap(fighter.x)
	if effect.get("tooth_tail", false) and not figure.is_empty():
		_offer_tooth_tail(fighter, [], 2)
	if effect.get("damage_path", false):
		_ride(Vector2i(fighter.x, 0))
	if (effect.get("splash", false) or effect.get("splash_all", false)) and (won or not effect.get("win_splash", false)) and not figure.is_empty():
		var targets: Array[Vector2i] = []
		for place in game.heroes.size():
			if place % 2 == fighter.x % 2 and not effect.get("splash_all", false):
				continue
			for index in game.fighters[place].size():
				if game.board.adjacent(figure.space, game.fighters[place][index].space):
					targets.append(Vector2i(place, index))
		_damage_group(targets, 1)
	if effect.has("adjacent_damage") and not figure.is_empty() and game.board.adjacent(figure.space, game.fighters[opponent.x][opponent.y].space):
		_damage_redirectable(opponent, effect.adjacent_damage)
	var card_values: Array = last_combat.get("card_values", [last_combat.get("attack_value", -1), last_combat.get("defense_value", -2)])
	if effect.get("mirror_after", false) and card_values[0] == card_values[1]:
		_draw(fighter.x, 1)
		if phase != Phase.FINISHED:
			_damage_redirectable(opponent, 2)
	if effect.get("morph", false):
		game.alice_large = not game.alice_large
	if not figure.is_empty():
		var heal := int(effect.get("heal", 0)) + (int(effect.get("win_heal", 0)) if won else 0)
		if figure.health <= 7 and effect.get("feeding", false):
			actions_left += int(fighter.x == seat)
			heal += 1
		figure.health = mini(figure.max_health, figure.health + heal)
	if effect.get("heal_per_misery", false):
		_heal_hero(fighter.x, miseries.size())
	if not figure.is_empty() and effect.has("third_heal") and _action_count == 3:
		figure.health = mini(figure.max_health, figure.health + int(effect.third_heal))
	if effect.get("grail", false) and not figure.is_empty() and figure.health <= 4:
		figure.health = 8
	if fighter.x == seat:
		actions_left += int(effect.get("actions", 0))
		if effect.get("patroclus_action", false) and _patroclus_alive(fighter.x):
			actions_left += 1
	if effect.get("opponent_action_on_loss", false) and not won and opponent.x == seat:
		actions_left += 1
	var draws := int(effect.get("draw", 0)) + (int(effect.get("win_draw", 0)) if won else 0)
	if effect.get("draw_combat_damage", false):
		draws += 0 if last_combat.get("reflected", false) else int(last_combat.damage)
	if effect.get("adjacent_draw", false) and not figure.is_empty():
		var target := _fighter_at(opponent.x, opponent.y)
		draws += int(not target.is_empty() and game.board.adjacent(figure.space, target.space))
	if effect.get("draw_on_trick", false):
		var other: Dictionary = last_combat.defense if fighter == _attack_pair[0] else last_combat.attack
		draws += int(_is_trick(other))
	_draw(fighter.x, draws)
	if phase == Phase.FINISHED:
		return
	if effect.get("revive_helper", false):
		var helper := _inactive_sidekick(fighter.x)
		var hero := _fighter_at(fighter.x, 0)
		if helper >= 0 and not hero.is_empty():
			_offer_revive(fighter.x, helper, _free_in_zone(hero.space))
	if _action_count == 3:
		_draw(fighter.x, int(effect.get("third_draw", 0)))
	if effect.get("discard_enemy", false):
		_offer_hand_discard(opponent.x, false, "Сбросьте карту",
			func(key: String) -> void: _discard_key(opponent.x, key))
	if effect.get("random_discard", false):
		_random_hand_discard(opponent.x, 1)
	if effect.get("return_voyages", false):
		var discard: Array = game.discards[fighter.x]
		for index in range(discard.size() - 1, -1, -1):
			if _is_voyage(discard[index]):
				Piles.transfer(discard, index, game.hands[fighter.x])
	if effect.has("take_discard"):
		var discard: Array = game.discards[fighter.x]
		var keys: Array = []
		for card: Dictionary in discard:
			if effect.take_discard.is_empty() or card.definition in effect.take_discard:
				keys.append(card.key)
		_offer_choice(fighter.x, keys, false, "Выберите карту из своего сброса",
			func(key: String) -> void:
				for index in discard.size():
					if discard[index].key == key:
						Piles.transfer(discard, index, game.hands[fighter.x])
						return, discard)
	if effect.get("look_discard_on_win", false) and won:
		var shown: Array = game.hands[opponent.x]
		var keys: Array = shown.map(func(card: Dictionary) -> String: return card.key)
		_offer_choice(fighter.x, keys, false, "Выберите карту противника для сброса",
			func(key: String) -> void: _discard_key(opponent.x, key), shown)
	if effect.get("look_enemy", false):
		var shown: Array = game.hands[opponent.x]
		if not shown.is_empty():
			_offer_choice(fighter.x, ["confirm"], false, "Посмотрите руку противника", func(_answer: String) -> void: pass, shown)
	if won and effect.get("discard_to_deck_on_win", false):
		var discard: Array = game.discards[fighter.x]
		var keys: Array = discard.map(func(card: Dictionary) -> String: return card.key)
		_offer_choice(fighter.x, keys, false, "Положите карту из сброса на верх колоды",
			func(key: String) -> void:
				for index in discard.size():
					if discard[index].key == key:
						Piles.transfer(discard, index, game.decks[fighter.x])
						return, discard)
	_pirate_after(fighter, effect)
	_loki_after(fighter, opponent, effect)


func _scheme_choice(fighter: Vector2i, effect: Dictionary) -> void:
	if effect.get("steal_rich", false):
		_draw(fighter.x, 1)
		if phase == Phase.FINISHED:
			return
		var opponents: Array = Array(range(game.heroes.size())).filter(func(place: int) -> bool: return place % 2 != fighter.x % 2)
		_offer_seat_choice(fighter.x, opponents, "Выберите противника",
			_steal_rich.bind(fighter.x))
	if effect.get("unsettle", false):
		_offer_unsettle(fighter)
	if phase == Phase.FINISHED:
		return
	var figure := _fighter_at(fighter.x, fighter.y)
	if effect.has("adjacent_target") and not figure.is_empty():
		_offer_damage_target(fighter.x, figure.space, false, true, effect.adjacent_target)
	if effect.get("plunder", false):
		doubloons = mini(3, doubloons + 1)
	if effect.get("scourge", false):
		_pirate_scourge(fighter.x)
	if effect.get("svadilfari", false):
		_svadilfari(fighter.x)
	if effect.has("zone_damage") and not figure.is_empty():
		_offer_damage_target(fighter.x, figure.space, effect.get("only_enemies", false), false, effect.zone_damage)
	if effect.get("spirits", false):
		var cells: Array = []
		for cell in game.board.cell_count():
			if game.board.same_zone(figure.space, cell):
				cells.append(cell)
		_offer_cells(fighter.x, cells, false, "Выберите ячейку в зоне Мерлина",
			func(cell: int) -> void:
				var neighbors: Array = []
				for other in game.board.cell_count():
					if game.board.adjacent(cell, other):
						neighbors.append(other)
				_offer_cells(fighter.x, neighbors, false, "Выберите вторую, смежную ячейку",
					func(second: int) -> void: _spirits_damage(fighter.x, [cell, second])))
	if effect.get("prophecy", false):
		_prophecy(fighter.x, Piles.peek(game.decks[fighter.x], 4), 2)
	if effect.get("excalibur", false):
		_offer_choice(fighter.x, ["deck", "discard"], false, "Где искать Экскалибур?",
			func(pile: String) -> void: _find_excalibur(fighter.x, pile))
	if effect.get("revive", false):
		var helper := _inactive_sidekick(fighter.x)
		if helper >= 0:
			_offer_revive(fighter.x, helper, _free_in_zone(game.fighters[fighter.x][0].space))
	if effect.get("blazing_gaze", false) or effect.get("steal_memory", false):
		var opponents: Array = []
		for place in game.heroes.size():
			if place % 2 != fighter.x % 2 and _has_fighters(place):
				opponents.append(place)
		if opponents.size() == 1:
			_look_scheme(fighter.x, opponents[0], effect)
		else:
			_offer_seat_choice(fighter.x, opponents, "Выберите противника",
				func(place: int) -> void: _look_scheme(fighter.x, place, effect))


func _steal_rich(opponent: int, owner: int) -> void:
	if game.hands[opponent].is_empty():
		_draw(owner, 1)
		return
	_offer_choice(opponent, ["discard", "draw"], false, "Сбросьте карту или дайте Робин Гуду взять ещё одну",
		func(answer: String) -> void:
			if answer == "draw":
				_draw(owner, 1)
			else:
				_offer_hand_discard(opponent, false, "Сбросьте карту", func(key: String) -> void: _discard_key(opponent, key)))
	_effect_request["labels"] = {"discard": "Сбросить карту", "draw": "Робин Гуд берёт ещё 1 карту"}


func _offer_damage_target(owner: int, origin: int, only_enemies: bool, adjacent: bool, damage: int, optional: bool = false) -> void:
	var targets: Array = []
	for place in game.heroes.size():
		if only_enemies and place % 2 == owner % 2:
			continue
		for index in game.fighters[place].size():
			var cell: int = game.fighters[place][index].space
			if (game.board.adjacent(origin, cell) if adjacent else game.board.same_zone(origin, cell)):
				targets.append(Vector2i(place, index))
	_offer_choice(owner, targets, optional, "Выберите бойца, который получит урон",
		func(target: Vector2i) -> void: _damage_redirectable(target, damage))


func _offer_tooth_tail(source: Vector2i, used: Array, remaining: int) -> void:
	var hero := _fighter_at(source.x, source.y)
	if remaining <= 0 or hero.is_empty() or phase == Phase.FINISHED:
		return
	var targets: Array = []
	for place in game.fighters.size():
		for index in game.fighters[place].size():
			var target := Vector2i(place, index)
			if target not in used and game.board.adjacent(hero.space, game.fighters[place][index].space):
				targets.append(target)
	_offer_choice(source.x, targets, true, "Зубы и хвост · выберите соседнего бойца",
		func(target: Vector2i) -> void:
			var before := _team_health(target.x)
			used.append(target)
			_effect_steps.push_front(func() -> void:
				if _team_health(target.x) < before:
					hero.health = mini(hero.max_health, hero.health + 1)
				_offer_tooth_tail(source, used, remaining - 1))
			_damage_redirectable(target, 1))


func _team_health(place: int) -> int:
	var total := 0
	for fighter: Dictionary in game.fighters[place]:
		total += int(fighter.health)
	return total


func _offer_unsettle(source: Vector2i) -> void:
	var origin: int = game.fighters[source.x][source.y].space
	var targets: Array = []
	for place in game.fighters.size():
		if place % 2 == source.x % 2:
			continue
		for index in game.fighters[place].size():
			if game.board.same_zone(origin, game.fighters[place][index].space):
				targets.append(Vector2i(place, index))
	_offer_choice(source.x, targets, false, "Испуг · выберите противника в вашей зоне",
		func(target: Vector2i) -> void:
			var count := [1]
			_effect_steps.push_front(func() -> void: _discard_requested(target.x, count[0]))
			_offer_choice(source.x, ["damage"], true, "Потеряйте 2 ОЗ, чтобы противник сбросил вторую карту",
				func(_answer: String) -> void:
					count[0] = 2
					_damage(source, 2)))


func _discard_requested(place: int, count: int) -> void:
	if count <= 0 or phase == Phase.FINISHED:
		return
	_offer_hand_discard(place, false, "Сбросьте карту",
		func(key: String) -> void:
			_discard_key(place, key)
			_discard_requested(place, count - 1))


func _hostile_owners(owner: int) -> Array:
	var places := []
	var controllers := []
	for place in game.heroes.size():
		if place % 2 != owner % 2 and _has_fighters(place) and game.controllers[place] not in controllers:
			places.append(place)
			controllers.append(game.controllers[place])
	return places


func _offer_ransom(owner: int, cost: int, prompt: String, unpaid: Callable, paid: Callable = Callable()) -> void:
	_ransom_replies(_hostile_owners(owner), cost, prompt, unpaid, paid)


func _ransom_replies(remaining: Array, cost: int, prompt: String, unpaid: Callable, paid: Callable) -> void:
	if phase == Phase.FINISHED:
		return
	if remaining.is_empty() or 3 - doubloons < cost:
		unpaid.call()
		return
	var place: int = remaining.pop_front()
	var accepted := [false]
	_effect_steps.push_front(func() -> void:
		if accepted[0]:
			if paid.is_valid():
				paid.call()
		else:
			_ransom_replies(remaining, cost, prompt, unpaid, paid))
	_offer_choice(place, ["pay"], true, prompt, func(_answer: String) -> void:
		doubloons += cost
		accepted[0] = true)


func _queen_tribute(combat: Dictionary, side: int, remaining: Array) -> void:
	if remaining.is_empty() or doubloons >= 3:
		return
	var place: int = remaining.pop_front()
	_effect_steps.push_front(_queen_tribute.bind(combat, side, remaining))
	_offer_choice(place, range(1, 4 - doubloons), true, "Месть королевы Анны · выберите число дублонов (−2 за каждый)",
		func(amount: int) -> void:
			doubloons += amount
			combat.modifiers[side] -= 2 * amount
			_remember_during(combat, side, "Потрачено дублонов: %d" % amount))


func _pick_discard(owner: int, opponent: int) -> void:
	var shown: Array = game.hands[opponent]
	_offer_choice(owner, shown.map(func(card: Dictionary) -> String: return card.key), false,
		"Выберите карту противника для сброса", func(key: String) -> void: _discard_key(opponent, key), shown)


func _pirate_after(fighter: Vector2i, effect: Dictionary) -> void:
	if game.heroes[fighter.x] != "blackbeard" or phase == Phase.FINISHED:
		return
	var hero := _fighter_at(fighter.x, 0)
	if hero.is_empty():
		return
	if effect.get("intimidate", false):
		for place in _hostile_owners(fighter.x):
			if game.fighters[place].any(func(other: Dictionary) -> bool: return game.board.adjacent(hero.space, other.space)):
				_heal_hero(fighter.x, 2)
				break
	if effect.get("sea_dog", false):
		_summon_helper(fighter.x, _free_in_zone(hero.space))
	if effect.get("ransom_action", false):
		_offer_ransom(fighter.x, 1, "Заплатите дублон, чтобы отменить дополнительное действие",
			func() -> void: actions_left += 1)
	if effect.get("ransom_pistols", false):
		_offer_ransom(fighter.x, 2, "Заплатите 2 дублона, чтобы избежать выстрела",
			func() -> void: _offer_damage_target(fighter.x, hero.space, true, false, 3))
	if effect.get("ransom_zone", false):
		_offer_ransom(fighter.x, 1, "Заплатите дублон, чтобы защититься от урона в зоне",
			func() -> void:
				var targets: Array[Vector2i] = []
				for place in game.fighters.size():
					if place % 2 != fighter.x % 2:
						for slot in game.fighters[place].size():
							if game.board.same_zone(hero.space, game.fighters[place][slot].space):
								targets.append(Vector2i(place, slot))
				_damage_group(targets, 1))


func _pirate_scourge(owner: int) -> void:
	var effects: Array[Callable] = [
		func() -> void: _heal_hero(owner, 2),
		func() -> void:
			var cells: Array = []
			var occupied := _occupied()
			for cell in game.board.cell_count():
				if not occupied.has(cell):
					cells.append(cell)
			_summon_helper(owner, cells),
		func() -> void: actions_left += 1,
	]
	var prompts := ["отменить лечение", "отменить призыв", "отменить дополнительное действие"]
	for index in range(effects.size() - 1, -1, -1):
		_effect_steps.push_front(_offer_ransom.bind(owner, 1, "Заплатите дублон, чтобы " + prompts[index], effects[index], Callable()))


static func _is_trick(card: Dictionary) -> bool:
	return card.get("hero") == "loki" and card.get("boost", 0) < 0


func _combat_effect(card: Dictionary, holder: int) -> Dictionary:
	if _is_trick(card) and game.heroes[holder] != "loki":
		match card.definition:
			"loki:03": return {"return_to_loki": true}
			"loki:11": return {"heal_loki": true}
			"loki:26": return {"trick_self_damage": true}
	return Effects.COMBAT.get(card.get("definition"), {}).duplicate()


func _dispose_played(card: Dictionary, holder: int, opponent: int = -1) -> void:
	if not _is_trick(card):
		game.discards[holder].append(card)
		return
	var loki: int = game.heroes.find("loki")
	if holder != loki:
		game.discards[loki].append(card)
	elif opponent >= 0:
		game.hands[opponent].append(card)
	else:
		var choices: Array = []
		for target in game.heroes.size():
			if target % 2 != holder % 2 and _has_fighters(target):
				choices.append(Vector2i(target, 0))
		if choices.size() == 1:
			game.hands[choices.front().x].append(card)
		elif choices.size() > 1 and phase != Phase.FINISHED:
			_offer_choice(holder, choices, false, "Выберите противника, который получит Хитрость",
				func(target: Vector2i) -> void: game.hands[target.x].append(card))
		else:
			game.discards[loki].append(card)


func _reveal_loki_card(combat: Dictionary, side: int, opponent: int) -> void:
	var slots: Array = game.hands[opponent].duplicate()
	Piles.shuffle(slots, game.random)
	var labels := {}
	for i in slots.size():
		labels[i] = "Карта %d%s" % [i + 1, " · Хитрость" if _is_trick(slots[i]) else ""]
	var owner := _attack_pair[side].x
	_offer_choice(owner, range(slots.size()), false, "Выберите рубашку карты противника",
		func(index: int) -> void:
			var card: Dictionary = slots[index]
			combat.modifiers[side] += maxi(0, card.boost)
			if _is_trick(card):
				var actual: int = game.hands[opponent].find(card)
				Piles.transfer(game.hands[opponent], actual, game.hands[owner])
			_remember_during(combat, side, "Открыта «%s» · усиление +%d" % [card.name, maxi(0, card.boost)]))
	if not slots.is_empty():
		_effect_request["labels"] = labels


func _loki_after(fighter: Vector2i, _opponent: Vector2i, effect: Dictionary) -> void:
	if phase == Phase.FINISHED:
		return
	var loki: int = game.heroes.find("loki")
	if effect.get("heal_loki", false):
		_heal_hero(loki, 3)
	if effect.get("return_to_loki", false) and not game.discards[loki].is_empty():
		Piles.transfer(game.discards[loki], game.discards[loki].size() - 1, game.hands[loki])
	if effect.get("trick_self_damage", false):
		_damage_redirectable(Vector2i(fighter.x, 0), 2)


func _svadilfari(holder: int) -> void:
	var loki: int = game.heroes.find("loki")
	if holder != loki:
		_pick_discard(loki, holder)
		return
	var origin: int = game.fighters[loki][0].space
	var occupied := _occupied()
	var free: Array = []
	var enemies: Array = []
	for cell in game.board.cell_count():
		if game.board.adjacent(origin, cell) and not occupied.has(cell):
			free.append(cell)
	if free.is_empty():
		return
	for place in game.fighters.size():
		if place % 2 != holder % 2:
			for index in game.fighters[place].size():
				if game.fighters[place][index].space >= 0:
					enemies.append(Vector2i(place, index))
	_offer_choice(holder, enemies, false, "Выберите бойца противника",
		func(target: Vector2i) -> void:
			_offer_cells(holder, free, false, "Поместите бойца рядом с Локи",
				func(cell: int) -> void: game.fighters[target.x][target.y].space = cell))


func _inactive_sidekick(owner: int) -> int:
	for index in range(1, game.fighters[owner].size()):
		if game.fighters[owner][index].space < 0:
			return index
	return -1


func _free_in_zone(origin: int) -> Array:
	var occupied := _occupied()
	var cells: Array = []
	for cell in game.board.cell_count():
		if not occupied.has(cell) and game.board.same_zone(origin, cell):
			cells.append(cell)
	return cells


func _offer_revive(owner: int, helper: int, cells: Array, after: Callable = Callable()) -> void:
	_offer_cells(owner, cells, false, "Выберите клетку для помощника",
		func(cell: int) -> void:
			var figure: Dictionary = game.fighters[owner][helper]
			figure.space = cell
			figure.health = figure.max_health
			if after.is_valid():
				after.call())


func _alice_options(owner: int, remaining: Array, chosen: Array) -> void:
	if phase == Phase.FINISHED:
		return
	if chosen.size() == 2:
		for index in range(chosen.size() - 1, -1, -1):
			_effect_steps.push_front(_apply_alice_option.bind(owner, chosen[index]))
		return
	_offer_choice(owner, remaining, false, "Выберите эффект Зазеркалья",
		func(option: String) -> void:
			remaining.erase(option)
			chosen.append(option)
			_alice_options(owner, remaining, chosen))


func _apply_alice_option(owner: int, option: String) -> void:
	if phase == Phase.FINISHED:
		return
	match option:
		"draw":
			_draw(owner, 2)
		"heal":
			var alice := _fighter_at(owner, 0)
			if not alice.is_empty():
				alice.health = mini(alice.max_health, alice.health + 3)
		"place":
			_offer_move(Vector2i(owner, 0), owner, Vector2i(-1, -1), {"place": "self", "mandatory_move": true})


func _spirits_damage(owner: int, cells: Array) -> void:
	var targets: Array[Vector2i] = []
	for place in game.heroes.size():
		if place % 2 == owner % 2:
			continue
		for index in game.fighters[place].size():
			var figure: Dictionary = game.fighters[place][index]
			if figure.space in cells:
				targets.append(Vector2i(place, index))
	_effect_steps.push_front(func() -> void:
		for target: Vector2i in targets:
			if game.fighters[target.x][target.y].health == 0:
				_draw(owner, 1)
				return)
	_damage_group(targets, 2)


func _prophecy(owner: int, remaining: Array, take: int) -> void:
	if remaining.is_empty():
		return
	var deck: Array = game.decks[owner]
	if remaining.size() == 1 and take <= 0:
		return
	var keys: Array = remaining.map(func(card: Dictionary) -> String: return card.key)
	_offer_choice(owner, keys, false, "Выберите карту в руку" if take > 0 else "Выберите верхнюю карту колоды",
		func(key: String) -> void:
			for index in deck.size():
				if deck[index].key != key:
					continue
				if take > 0:
					var card: Dictionary = deck[index]
					Piles.transfer(deck, index, game.hands[owner])
					remaining.erase(card)
					_prophecy(owner, remaining, take - 1)
				else:
					Piles.transfer(deck, index, deck)
				return, remaining)


func _find_excalibur(owner: int, pile: String) -> void:
	var source: Array = game.decks[owner] if pile == "deck" else game.discards[owner]
	for index in source.size():
		if source[index].definition == "arthur:01":
			Piles.transfer(source, index, game.hands[owner])
			break
	if pile == "deck":
		Piles.shuffle(source, game.random)


func _look_scheme(owner: int, opponent: int, effect: Dictionary) -> void:
	var hand: Array = game.hands[opponent]
	if hand.is_empty():
		if effect.get("blazing_gaze", false):
			_draw(owner, 1)
			_draw(opponent, 1)
		return
	var keys: Array = hand.map(func(card: Dictionary) -> String: return card.key)
	_offer_choice(owner, keys, false, "Выберите карту из руки противника",
		func(key: String) -> void:
			for index in hand.size():
				if hand[index].key != key:
					continue
				if effect.get("blazing_gaze", false):
					Piles.transfer(hand, index, game.decks[opponent], 0)
					_draw(owner, 1)
					_draw(opponent, 1)
				else:
					_memory_discard(opponent, hand[index])
				return, hand)


func _memory_discard(owner: int, card: Dictionary) -> void:
	_offer_choice(owner, ["discard", "damage"], false, "Сбросьте карту или получите урон",
		func(answer: String) -> void:
			if answer == "discard":
				_discard_key(owner, card.key)
			else:
				_damage_redirectable(Vector2i(owner, 0), maxi(0, card.boost)), [card])


func _clone_swap(owner: int) -> void:
	var hero := _fighter_at(owner, 0)
	var cells := _free_in_zone(hero.space)
	var helpers: Array = []
	var inactive := _inactive_sidekick(owner)
	if inactive >= 0:
		helpers.append(inactive)
	else:
		helpers.assign(range(1, game.fighters[owner].size()))
	if cells.is_empty():
		return
	var place_clone := func(helper: int) -> void:
		_offer_cells(owner, cells, false, "Выберите новое место Сунь Укуна",
			func(cell: int) -> void:
				var clone: Dictionary = game.fighters[owner][helper]
				clone.space = hero.space
				clone.health = clone.max_health
				hero.space = cell)
	if helpers.size() == 1:
		place_clone.call(helpers[0])
	else:
		_offer_choice(owner, _clone_targets(owner), false, "Выберите двойника на поле",
			func(target: Vector2i) -> void: place_clone.call(target.y))


func _clone_targets(owner: int) -> Array:
	var targets: Array = []
	for helper in range(1, game.fighters[owner].size()):
		targets.append(Vector2i(owner, helper))
	return targets


func _ride(fighter: Vector2i) -> void:
	var figure := _fighter_at(fighter.x, fighter.y)
	if not figure.is_empty():
		_ride_step(fighter, figure.space, figure.space, 5, {}, PackedInt32Array([figure.space]))


func _ride_step(fighter: Vector2i, origin: int, current: int, remaining: int, passed: Dictionary, path: PackedInt32Array) -> void:
	var occupied := _occupied()
	var can_stop := current == origin or not occupied.has(current)
	if remaining == 0:
		_finish_ride(fighter, current, passed, path)
		return
	var choices: Array = []
	if can_stop:
		choices.append(-1)
	for neighbor in game.board.cell_count():
		if not game.board.adjacent(current, neighbor):
			continue
		if occupied.has(neighbor) and neighbor != origin and remaining <= 1:
			continue
		if occupied.has(neighbor) and neighbor != origin:
			var dismount := occupied.duplicate()
			dismount.erase(origin)
			if game.board.reachable(neighbor, remaining - 1, fighter.x % 2, dismount, true).is_empty():
				continue
		choices.append(neighbor)
	_offer_cells(fighter.x, choices, false, "Выберите следующий шаг Йенненги",
		func(answer: int) -> void:
			if answer == -1:
				_finish_ride(fighter, current, passed, path)
				return
			for place in game.heroes.size():
				if place % 2 != fighter.x % 2:
					for index in game.fighters[place].size():
						if game.fighters[place][index].space == answer:
							passed[Vector2i(place, index)] = true
			path.append(answer)
			_ride_step(fighter, origin, answer, remaining - 1, passed, path))


func _finish_ride(fighter: Vector2i, cell: int, passed: Dictionary, path: PackedInt32Array) -> void:
	var targets: Array[Vector2i] = []
	for enemy: Vector2i in passed:
		targets.append(enemy)
	_effect_steps.push_front(_damage_group.bind(targets, 1))
	_walk_fighter(fighter, path)


func _discard_key(place: int, key: String) -> void:
	var hand: Array = game.hands[place]
	for index in hand.size():
		if hand[index].key == key:
			var card: Dictionary = hand[index]
			if _is_trick(card) and game.heroes[place] != "loki":
				hand.remove_at(index)
				var loki: int = game.heroes.find("loki")
				_effect_steps.push_front(_reclaim_trick.bind(loki, card))
			else:
				Piles.discard(hand, index, game.discards[place])
			return


func _random_hand_discard(place: int, count: int) -> Array:
	var cards: Array = []
	for i in mini(count, game.hands[place].size()):
		var card: Dictionary = game.hands[place][game.random.randi_range(0, game.hands[place].size() - 1)]
		cards.append(card)
		_discard_key(place, card.key)
	return cards


func _reclaim_trick(loki: int, card: Dictionary) -> void:
	if phase == Phase.FINISHED or _fighter_at(loki, 0).is_empty():
		game.discards[loki].append(card)
		return
	var piles := {"hand": game.hands[loki], "deck": game.decks[loki], "discard": game.discards[loki]}
	_offer_choice(loki, ["hand", "deck", "discard"], false, "Куда вернуть сброшенную Хитрость?",
		func(destination: String) -> void: piles[destination].append(card), [card])


func _take_combat_card(place: int, key: String) -> void:
	var hand: Array = game.hands[place]
	for index in hand.size():
		if hand[index].key == key:
			hand.remove_at(index)
			return


func _ready_to_act(viewer: int) -> bool:
	if not _can_act(viewer, Phase.ACTION):
		return false
	start_turn()
	return phase == Phase.ACTION


func start_turn() -> void:
	if phase != Phase.ACTION or not game.pending().is_empty():
		return
	if not _turn_spaces.is_empty():
		return
	for place in game.fighters.size():
		for index in game.fighters[place].size():
			_turn_spaces[Vector2i(place, index)] = game.fighters[place][index].space
	if game.heroes[seat] == "bloody_mary" and game.hands[seat].size() == 3:
		actions_left += 1
	var hero := _fighter_at(seat, 0)
	if not hero.is_empty():
		match game.heroes[seat]:
			"medusa":
				_offer_damage_target(seat, hero.space, true, false, 1, true)
			"sun_wukong":
				_offer_summon(hero)
			"blackbeard":
				if doubloons > 0:
					_offer_choice(seat, ["pay"], true, "Потратьте дублон, чтобы получить действие",
						func(_answer: String) -> void:
							doubloons -= 1
							actions_left += 1)
			"pandora":
				phase = Phase.EFFECT_CHOICE
				if misery_pile.is_empty():
					misery_pile = Array(range(MISERIES.size()))
					Piles.shuffle(misery_pile, game.random)
				_effect_steps.append(_close_turn_start)
				_reveal_misery(seat)
				_run_effects()
				return
	if not _effect_request.is_empty():
		phase = Phase.EFFECT_CHOICE
		_effect_steps.append(_close_turn_start)
	else:
		_close_turn_start()


func _close_turn_start() -> void:
	_check_victory()
	if phase == Phase.FINISHED:
		return
	phase = Phase.ACTION


func misery_card(index: int) -> Dictionary:
	return {"hero": "pandora", "face": 0, "misery": index + 1,
		"key": "misery:%d" % index, "name": MISERIES[index]}


func _reveal_misery(owner: int) -> void:
	var hero := _fighter_at(owner, 0)
	if phase == Phase.FINISHED or misery_pile.is_empty() or hero.is_empty():
		return
	var index: int = misery_pile.pop_back()
	miseries.append(index)
	misery_opened = {"id": int(misery_opened.get("id", 0)) + 1, "card": misery_card(index)}
	_effect_steps.push_front(_continue_miseries.bind(owner, index == 4))
	match index:
		0:
			_misery_attack += 1
		1:
			_summon_helper(owner, _free_in_zone(hero.space))
		2:
			var targets: Array[Vector2i] = []
			for place in game.fighters.size():
				if place % 2 != owner % 2:
					for slot in game.fighters[place].size():
						if game.board.adjacent(hero.space, game.fighters[place][slot].space):
							targets.append(Vector2i(place, slot))
			_damage_group(targets, 1)
		5:
			_draw(owner, 1)
		6:
			_offer_move(Vector2i(owner, 0), owner, Vector2i(-1, -1), {"distance": 1})


func _continue_miseries(owner: int, see_top: bool) -> void:
	if phase == Phase.FINISHED or _fighter_at(owner, 0).is_empty():
		return
	var feathers := 0
	for index: int in miseries:
		feathers += MISERY_FEATHERS[index]
	if feathers >= 3:
		_damage(Vector2i(owner, 0), miseries.size())
	elif not misery_pile.is_empty():
		var shown := [misery_card(misery_pile.back())] if see_top else []
		var prompt := "Ящик Пандоры · открыто %d, перьев %d" % [miseries.size(), feathers]
		if see_top:
			prompt = "Надежда · посмотрите следующее бедствие и решите, открывать ли его"
		_offer_choice(owner, ["reveal"], true, prompt,
			func(_answer: String) -> void: _reveal_misery(owner), shown)
		if see_top:
			_effect_request["misery_peek"] = true


func _summon_helper(owner: int, cells: Array) -> void:
	if cells.is_empty() or phase == Phase.FINISHED:
		return
	var helper := _inactive_sidekick(owner)
	if helper >= 0:
		_offer_revive(owner, helper, cells)
	else:
		var choices: Array = []
		for index in range(1, game.fighters[owner].size()):
			choices.append(Vector2i(owner, index))
		_offer_choice(owner, choices, false, "Выберите помощника для размещения",
			func(target: Vector2i) -> void: _offer_revive(owner, target.y, cells))


func _heal_hero(owner: int, amount: int) -> void:
	var hero := _fighter_at(owner, 0)
	if not hero.is_empty():
		hero.health = mini(hero.max_health, hero.health + amount)


func _offer_summon(hero: Dictionary) -> void:
	var cells: Array = []
	var occupied := _occupied()
	for cell in game.board.cell_count():
		if game.board.adjacent(hero.space, cell) and not occupied.has(cell):
			cells.append(cell)
	if cells.is_empty():
		return
	var owner := seat
	var inactive := _inactive_sidekick(owner)
	if inactive >= 0:
		_summon_cells(owner, inactive, cells)
	else:
		_offer_choice(owner, _clone_targets(owner), true, "Начало хода · выберите двойника на поле для нового призыва",
			func(target: Vector2i) -> void: _summon_cells(owner, target.y, cells))


func _summon_cells(owner: int, helper: int, cells: Array) -> void:
	_offer_cells(owner, cells, true, "Начало хода · размещение двойника за 1 ОЗ. Нажмите на подсвеченную клетку.",
		func(cell: int) -> void:
			_damage(Vector2i(owner, 0), 1)
			if phase != Phase.FINISHED and not _fighter_at(owner, 0).is_empty():
				var clone: Dictionary = game.fighters[owner][helper]
				clone.space = cell
				clone.health = clone.max_health)


func _damage(fighter: Vector2i, damage: int) -> void:
	var figure := _fighter_at(fighter.x, fighter.y)
	if figure.is_empty() or damage <= 0:
		return
	figure.health = maxi(0, figure.health - damage)
	if figure.health == 0:
		figure.space = -1
		if fighter.y == 1 and game.heroes[fighter.x] == "achilles" and phase != Phase.FINISHED:
			_random_hand_discard(fighter.x, 2)


func _damage_redirectable(fighter: Vector2i, damage: int, first_archer: int = 1) -> void:
	if phase == Phase.FINISHED or damage <= 0:
		return
	if fighter.y == 0 and game.heroes[fighter.x] == "yennenga":
		var hero := _fighter_at(fighter.x, 0)
		if hero.is_empty():
			return
		for index in range(first_archer, game.fighters[fighter.x].size()):
			var archer := _fighter_at(fighter.x, index)
			if archer.is_empty() or not game.board.same_zone(hero.space, archer.space):
				continue
			var maximum := mini(damage, archer.health)
			_offer_choice(fighter.x, range(maximum + 1), false, "Сколько урона перенести на лучника?",
				func(amount: int) -> void:
					_damage(Vector2i(fighter.x, index), amount)
					_damage_redirectable(fighter, damage - amount, index + 1))
			return
	_damage(fighter, damage)


func _damage_group(targets: Array[Vector2i], damage: int) -> void:
	var yennenga := Vector2i(-1, -1)
	for target: Vector2i in targets:
		if target.y == 0 and game.heroes[target.x] == "yennenga":
			yennenga = target
		else:
			_damage(target, damage)
	if yennenga.x >= 0:
		_damage_redirectable(yennenga, damage)


func _patroclus_alive(place: int) -> bool:
	return game.fighters[place][1].health > 0


func _combat_keys(place: int, kind: Catalog.Kind, is_hero: bool) -> Array[String]:
	var keys: Array[String] = []
	for card: Dictionary in game.hands[place]:
		if Catalog.can_play(card, kind, is_hero):
			keys.append(card.key)
	return keys


func _fighter_at(place: int, index: int) -> Dictionary:
	if place < 0 or place >= game.fighters.size() or index < 0 or index >= game.fighters[place].size():
		return {}
	var figure: Dictionary = game.fighters[place][index]
	return figure if figure.space >= 0 else {}


func _end_action() -> void:
	# FAQ, стр. 4: сначала завершаются все эффекты действия, затем определяется победитель.
	_check_victory()
	if phase == Phase.FINISHED:
		return
	if not _has_fighters(seat):
		_finish_turn()
		return
	if actions_left > 0:
		phase = Phase.ACTION
		return
	if game.heroes[seat] == "bigfoot" and _bigfoot_has_clear_zone():
		phase = Phase.EFFECT_CHOICE
		_effect_steps.push_front(_finish_hand)
		_offer_choice(seat, ["draw"], true, "Бигфут · взять карту в конце хода?",
			func(_answer: String) -> void: _draw(seat, 1))
		return
	_finish_hand()


func _bigfoot_has_clear_zone() -> bool:
	var hero := _fighter_at(seat, 0)
	if hero.is_empty():
		return false
	for place in game.heroes.size():
		if place % 2 == seat % 2:
			continue
		for enemy: Dictionary in game.fighters[place]:
			if game.board.same_zone(hero.space, enemy.space):
				return false
	return true


func _finish_hand() -> void:
	if phase == Phase.FINISHED:
		return
	if game.hands[seat].size() > HAND_LIMIT:
		phase = Phase.DISCARD
	else:
		_finish_turn()


func discard_to_limit(viewer: int, key: String) -> bool:
	if not _can_act(viewer, Phase.DISCARD):
		return false
	var index := _hand_index(key)
	if index < 0:
		return false
	_discard_key(seat, key)
	if game.hands[seat].size() <= HAND_LIMIT:
		_effect_steps.append(_finish_turn)
	_run_effects()
	return true


## Правило истощения применяется за каждую карту, которую требуется взять.
func _draw(place: int, count: int) -> void:
	for i in count:
		if phase == Phase.FINISHED:
			return
		if Piles.draw(game.decks[place], game.hands[place]):
			continue
		for index in game.fighters[place].size():
			_damage(Vector2i(place, index), 2)


func _finish_turn() -> void:
	var belt: PackedInt32Array = game.board.conveyor
	if not belt.is_empty():
		var last := _conveyor_rider(belt[-1])
		if not last.is_empty():
			var occupied := _occupied()
			var exits := Array(game.board.conveyor_exit).filter(func(cell: int) -> bool: return not occupied.has(cell))
			if not exits.is_empty():
				phase = Phase.EFFECT_CHOICE
				_effect_steps.push_front(_advance_conveyor)
				_offer_cells(last.seat, exits, false, "Конвейер · выберите свободную клетку склада подарков",
					func(cell: int) -> void: last.figure.space = cell)
				return
		_advance_conveyor()
		return
	_pass_turn()


func _conveyor_rider(cell: int) -> Dictionary:
	for place in game.fighters.size():
		for fighter: Dictionary in game.fighters[place]:
			if fighter.space == cell:
				return {"seat": place, "figure": fighter}
	return {}


func _advance_conveyor() -> void:
	var belt: PackedInt32Array = game.board.conveyor
	var occupied := _occupied()
	for i in range(belt.size() - 2, -1, -1):
		if not occupied.has(belt[i]) or occupied.has(belt[i + 1]):
			continue
		var moved: Dictionary = _conveyor_rider(belt[i]).figure
		moved.space = belt[i + 1]
		occupied[belt[i + 1]] = occupied[belt[i]]
		occupied.erase(belt[i])
	_pass_turn()


func _pass_turn() -> void:
	_check_victory()
	if phase == Phase.FINISHED:
		return
	_map_target = Vector2i(-1, -1)
	_danger_crossed.clear()
	if game.heroes[seat] == "pandora":
		misery_pile.append_array(miseries)
		Piles.shuffle(misery_pile, game.random)
		miseries.clear()
		_misery_attack = 0
	_turn_spaces.clear()
	_won_this_turn.clear()
	_action_count = 0
	for i in game.heroes.size():
		seat = (seat + 1) % game.heroes.size()
		if _has_fighters(seat):
			break
	actions_left = ACTIONS_PER_TURN
	phase = Phase.ACTION
	start_turn()


func _check_victory() -> void:
	var living := [false, false]
	for place in game.heroes.size():
		if game.fighters[place][0].health > 0:
			living[place % 2] = true
	if not (living[0] and living[1]):
		winner = (0 if living[0] else 1) if living[0] or living[1] else seat % 2
		phase = Phase.FINISHED


func _has_fighters(place: int) -> bool:
	for figure: Dictionary in game.fighters[place]:
		if figure.space >= 0:
			return true
	return false


func _can_act(viewer: int, expected: Phase) -> bool:
	return phase == expected and _effect_request.is_empty() and game.pending().is_empty() and game.controllers[seat] == viewer


func _hand_index(key: String) -> int:
	for index in game.hands[seat].size():
		if game.hands[seat][index].key == key:
			return index
	return -1


static func _is_voyage(card: Dictionary) -> bool:
	return card.definition in ["sinbad:15", "sinbad:16", "sinbad:17", "sinbad:18", "sinbad:19", "sinbad:20", "sinbad:26"]
