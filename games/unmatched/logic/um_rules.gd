extends RefCounted
## Хостовый ход Unmatched. Раздача и расстановка выполняются в UMSetup.

const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Piles := preload("res://hub/card_piles.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const CombatCards := preload("res://games/unmatched/logic/um_combat_cards.gd")
const Choice := preload("res://hub/player_choice.gd")
const Effects := preload("res://games/unmatched/logic/um_effects.gd")

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
var _boosted := false
var _next_request := 1
var _combat_cards: CombatCards
var _attack_pair: Array[Vector2i] = []
var _turn_spaces: Dictionary = {}
var last_combat: Dictionary = {}
var _held_attack: Dictionary = {}
var _action_count := 0
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

func _init(setup: Setup) -> void:
	game = setup


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
	if phase == Phase.FINISHED or not _has_fighters(seat):
		if phase != Phase.FINISHED:
			_finish_turn()
		return true
	_distance = _movement_distance()
	_moved.clear()
	_boosted = false
	phase = Phase.MANEUVER
	return true


func boost_maneuver(viewer: int, key: String) -> bool:
	if not _can_act(viewer, Phase.MANEUVER) or _boosted or not _moved.is_empty():
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
	var figure: Dictionary = game.fighters[seat][fighter]
	if figure.space < 0:
		return []
	return game.board.reachable(figure.space, _distance, seat % 2, _occupied())


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
	return distance


func move_in_maneuver(viewer: int, fighter: int, cell: int) -> bool:
	if cell not in maneuver_cells(viewer, fighter):
		return false
	var figure: Dictionary = game.fighters[seat][fighter]
	figure["walk"] = game.board.route(figure.space, cell, _distance, seat % 2, _occupied())
	_walk_serial += 1
	figure["walk_serial"] = _walk_serial
	figure.space = cell
	_moved[fighter] = true
	return true


func can_boost_maneuver() -> bool:
	return phase == Phase.MANEUVER and not _boosted and _moved.is_empty()


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
	if not _can_act(viewer, Phase.MANEUVER):
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
	_action_count += 1
	game.hands[seat].remove_at(index)
	phase = Phase.EFFECT_CHOICE
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
	game.discards[seat].append(card)
	if phase != Phase.FINISHED:
		if _has_fighters(seat):
			_end_action()
		else:
			_finish_turn()


func begin_attack(viewer: int, fighter: int, target_seat: int, target_fighter: int, key: String = "") -> bool:
	if not _ready_to_act(viewer) or target_seat % 2 == seat % 2:
		return false
	var source := _fighter_at(seat, fighter)
	var target := _fighter_at(target_seat, target_fighter)
	if source.is_empty() or target.is_empty() or not game.board.in_attack_range(source.space, target.space, source.ranged):
		return false
	var attacks := _combat_keys(seat, Catalog.Kind.ATTACK, source.is_hero)
	if attacks.is_empty() or (not key.is_empty() and key not in attacks):
		return false
	var defenses := _combat_keys(target_seat, Catalog.Kind.DEFENSE, target.is_hero)
	_attack_pair = [Vector2i(seat, fighter), Vector2i(target_seat, target_fighter)]
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
		"cards": _combat_cards.revealed(),
	}
	if phase == Phase.COMBAT_CHOICE and not request.is_empty() and game.controllers[request.hand] == viewer:
		view["choice"] = request
	return view


func choose_combat_card(viewer: int, answer: Dictionary) -> bool:
	if phase != Phase.COMBAT_CHOICE or not _combat_cards.choose(game.hands, game.controllers, viewer, answer):
		return false
	if not _combat_cards.pending().is_empty():
		if game.heroes[seat] == "arthur" and _attack_pair[0].y == 0:
			_offer_arthur_boost()
		return true
	phase = Phase.COMBAT_REVEAL
	return true


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
	during_events.clear()
	immediate_cue = {}
	_pace_combat = pace_animation
	var attack_effect: Dictionary = Effects.COMBAT.get(attack.definition, {})
	var defense_effect: Dictionary = Effects.COMBAT.get(defense.get("definition"), {})
	var attack_canceled: bool = defense_effect.get("cancel", false) and not attack_effect.get("uncancelable", false)
	var defense_canceled: bool = not attack_canceled and attack_effect.get("cancel", false)
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
		"canceled": [attack_canceled, defense_canceled], "values": [attack.value, defense.get("value", 0)], "modifiers": [0, 0],
		"ignore_defense": false, "reflect": false}
	if not _arthur_boost.is_empty() and not attack_canceled:
		combat.modifiers[0] = _arthur_boost.boost
	phase = Phase.EFFECT_CHOICE
	_effect_steps.append(_show_immediate.bind(combat, 1))
	_effect_steps.append(_show_immediate.bind(combat, 0))
	_effect_steps.append(_combat_during.bind(combat, 1))
	_effect_steps.append(_combat_during.bind(combat, 0))
	_effect_steps.append(_prepare_combat_impact.bind(combat, pace_animation))
	_run_effects()
	return true


func _show_immediate(combat: Dictionary, side: int) -> void:
	var effect: Dictionary = combat.effects[side]
	var swap: bool = effect.get("swap_patroclus", false) and _patroclus_alive(_attack_pair[side].x)
	var board: bool = swap or effect.has("archer_attack") or effect.has("discard_or_revive")
	if not _pace_combat or not (board or effect.has("cancel") or effect.has("discard_or_ignore")):
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
	var effect: Dictionary = combat.effects[side]
	var fighter := _attack_pair[side]
	var opponent := _attack_pair[1 - side]
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
	var base: int = combat.cards[side].value
	var discard_count: int = game.discards[fighter.x].size()
	combat.values[side] = _combat_value(fighter, opponent, combat.cards[side], combat.cards[1 - side], effect)
	var discarded := int(game.discards[fighter.x].size() > discard_count)
	if effect.get("random_boost", false):
		var cards := Piles.discard_random(game.hands[opponent.x], game.discards[opponent.x], 1, game.random)
		if not cards.is_empty():
			combat.modifiers[side] += maxi(0, cards[0].boost)
			discarded += 1
	if (combat.values[side] != base and not effect.get("reprise", false)) or discarded > 0:
		_remember_during(combat, side, "Сброшена 1 карта" if discarded > 0 else "Значение карты изменилось")
	if side == 1 and effect.get("prevent_damage", false):
		_remember_during(combat, side, "Боевой урон предотвращён")
	combat.values[side] += _fighter_combat_bonus(fighter, side == 0)
	if effect.get("boost", false):
		_offer_boost(combat, side, side)
	if effect.get("boost_enemy", false) and not combat.cards[1 - side].is_empty():
		_offer_boost(combat, 1 - side, side)
	if effect.get("adjust", false):
		_offer_choice(fighter.x, [-1, 1], true, "Измените значение карты",
			func(adjustment: int) -> void:
				combat.modifiers[side] += adjustment
				_remember_during(combat, side, "Значение карты изменилось"))
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
		combat.values[0] + combat.modifiers[0], combat.values[1] + combat.modifiers[1],
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
	if combat.ignore_defense:
		defense_value = 0
	var source: Dictionary = game.fighters[attacker.x][attacker.y]
	var target: Dictionary = game.fighters[defender.x][defender.y]
	attack_value += game.board.attack_bonus(source.space, target.space)
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
	var losses: Array = []
	for fighter: Vector2i in combat.health_before:
		var amount: int = combat.health_before[fighter] - game.fighters[fighter.x][fighter.y].health
		if amount > 0:
			losses.append({"fighter": fighter, "amount": amount})
	last_combat = {"id": _combat_serial, "losses": losses,
		"attack": attack, "defense": defense, "damage": damage, "attacker_won": attacker_won,
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
	for key: String in ["damage", "adjacent_target", "adjacent_damage", "splash", "clone_swap", "damage_path", "alice_options", "mirror_after", "discard_enemy"]:
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
		game.discards[defender.x].append(defense)
	if attack_effect.get("follow_up", false) and (not attack_effect.get("needs_defense", false) or not defense.is_empty()):
		if _begin_follow_up(attack, defense):
			return
	game.discards[attacker.x].append(_held_attack)
	_held_attack = {}
	if not _arthur_boost.is_empty():
		game.discards[attacker.x].append(_arthur_boost)
		_arthur_boost = {}
	_combat_cards = null
	immediate_cue = {}
	_attack_pair.clear()
	if phase != Phase.FINISHED:
		if _has_fighters(seat):
			_end_action()
		else:
			_finish_turn()


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
	var cells := _movement_cells(target, opponent, effect)
	_offer_cells(owner, Array(cells), not effect.get("mandatory_move", false), "Выберите клетку",
		func(cell: int) -> void:
			var figure: Dictionary = game.fighters[target.x][target.y]
			figure["walk"] = [] if effect.has("place") else game.board.route(
				figure.space, cell, effect.distance, target.x % 2, _occupied(), effect.get("through_enemies", false))
			_walk_serial += 1
			figure["walk_serial"] = _walk_serial
			figure.space = cell)


func _offer_group_move(owner: int, remaining: Array, effect: Dictionary) -> void:
	var options := remaining.filter(func(target: Vector2i) -> bool:
		return not _movement_cells(target, Vector2i(-1, -1), effect).is_empty())
	_offer_choice(owner, options, true, "Выберите следующего бойца",
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
	if target.is_empty():
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
	_combat_cards = CombatCards.new(_next_request, attacker.x, defender.x, [], defenses, follow_up)
	_combat_serial += 1
	_next_request += 2
	phase = Phase.COMBAT_CHOICE
	return true


func _combat_value(fighter: Vector2i, opponent: Vector2i, card: Dictionary, opposing_card: Dictionary, effect: Dictionary) -> int:
	var figure: Dictionary = game.fighters[fighter.x][fighter.y]
	var other: Dictionary = game.fighters[opponent.x][opponent.y]
	var value: int = card.value
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
	if effect.get("damage_path", false):
		_ride(Vector2i(fighter.x, 0))
	if effect.get("splash", false) and not figure.is_empty():
		var targets: Array[Vector2i] = []
		for place in game.heroes.size():
			if place % 2 == fighter.x % 2:
				continue
			for index in game.fighters[place].size():
				if game.board.adjacent(figure.space, game.fighters[place][index].space):
					targets.append(Vector2i(place, index))
		_damage_group(targets, 1)
	if effect.has("adjacent_damage") and not figure.is_empty() and game.board.adjacent(figure.space, game.fighters[opponent.x][opponent.y].space):
		_damage_redirectable(opponent, effect.adjacent_damage)
	if effect.get("mirror_after", false) and last_combat.attack_value == last_combat.defense_value:
		_draw(fighter.x, 1)
		if phase != Phase.FINISHED:
			_damage_redirectable(opponent, 2)
	if effect.get("morph", false):
		game.alice_large = not game.alice_large
	if not figure.is_empty() and effect.has("heal"):
		figure.health = mini(figure.max_health, figure.health + int(effect.heal))
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
	_draw(fighter.x, int(effect.get("draw", 0)) + (int(effect.get("win_draw", 0)) if won else 0))
	if _action_count == 3:
		_draw(fighter.x, int(effect.get("third_draw", 0)))
	if effect.get("discard_enemy", false):
		_offer_hand_discard(opponent.x, false, "Сбросьте карту",
			func(key: String) -> void: _discard_key(opponent.x, key))
	if effect.get("random_discard", false):
		Piles.discard_random(game.hands[opponent.x], game.discards[opponent.x], 1, game.random)
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


func _scheme_choice(fighter: Vector2i, effect: Dictionary) -> void:
	if phase == Phase.FINISHED:
		return
	var figure := _fighter_at(fighter.x, fighter.y)
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
			_offer_choice(fighter.x, opponents, false, "Выберите противника",
				func(place: int) -> void: _look_scheme(fighter.x, place, effect))


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
	var figure: Dictionary = game.fighters[fighter.x][fighter.y]
	_walk_serial += 1
	figure["walk_serial"] = _walk_serial
	figure["walk"] = path
	figure.space = cell
	var targets: Array[Vector2i] = []
	for enemy: Vector2i in passed:
		targets.append(enemy)
	_damage_group(targets, 1)


func _discard_key(place: int, key: String) -> void:
	var hand: Array = game.hands[place]
	for index in hand.size():
		if hand[index].key == key:
			Piles.discard(hand, index, game.discards[place])
			return


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
	if not _effect_request.is_empty():
		phase = Phase.EFFECT_CHOICE
		_effect_steps.append(_close_turn_start)
	else:
		_close_turn_start()


func _close_turn_start() -> void:
	if phase == Phase.FINISHED:
		return
	phase = Phase.ACTION


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
		_check_victory()
		if fighter.y == 1 and game.heroes[fighter.x] == "achilles" and phase != Phase.FINISHED:
			Piles.discard_random(game.hands[fighter.x], game.discards[fighter.x], 2, game.random)


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
	if actions_left > 0:
		phase = Phase.ACTION
	elif game.hands[seat].size() > HAND_LIMIT:
		phase = Phase.DISCARD
	else:
		_finish_turn()


func discard_to_limit(viewer: int, key: String) -> bool:
	if not _can_act(viewer, Phase.DISCARD):
		return false
	var index := _hand_index(key)
	if not Piles.discard(game.hands[seat], index, game.discards[seat]):
		return false
	if game.hands[seat].size() <= HAND_LIMIT:
		_finish_turn()
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
	_turn_spaces.clear()
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
	return phase == expected and game.pending().is_empty() and game.controllers[seat] == viewer


func _hand_index(key: String) -> int:
	for index in game.hands[seat].size():
		if game.hands[seat][index].key == key:
			return index
	return -1


static func _is_voyage(card: Dictionary) -> bool:
	return card.definition in ["sinbad:15", "sinbad:16", "sinbad:17", "sinbad:18", "sinbad:19", "sinbad:20", "sinbad:26"]
