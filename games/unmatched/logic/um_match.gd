extends RefCounted
## Проекция партии для хоста, участника и зрителя. Закрытые операции и решения принадлежат правилам.

const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Setup := preload("res://games/unmatched/logic/um_setup.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Hand := preload("res://games/unmatched/logic/um_hand.gd")
const Piles := preload("res://games/unmatched/logic/um_piles.gd")
const SharedPiles := preload("res://hub/card_piles.gd")
const Maps := preload("res://games/unmatched/logic/um_maps.gd")
const DEFAULT_HEROES := ["alice", "achilles", "medusa", "yennenga"]
const DUPLICATE_HEROES := "Выбраны одинаковые персонажи, игра не может быть начата"
const REVEAL_SECONDS := 3.85
const DURING_SECONDS := 0.95
const BEFORE_IMPACT_SECONDS := 2.0

var arena: String
var players: Array
var game: Setup
var rules: Rules
var phase: String:
	get:
		if _draft_count > 0:
			return "unmatched/draft"
		return "game_over" if rules.phase == Rules.Phase.FINISHED else "unmatched/%s" % Rules.Phase.keys()[rules.phase].to_lower()
var _reveal_time := 0.0
var _journal: Array[String] = []
var _logged_combat: Dictionary = {}
var _scheme_notice: Dictionary = {}
var _seen_free_scheme := 0
var _draft_count := 0
var _draft_pool: Array = []
var _draft_offers: Array = []
var _draft_choices := PackedStringArray()


static func controllers_for(total: int, double_player: int = 1) -> PackedInt32Array:
	if total != 3:
		return PackedInt32Array(range(total))
	var owner := clampi(double_player, 0, 2)
	var others: Array = Array(range(3)).filter(func(index: int) -> bool: return index != owner)
	return PackedInt32Array([others[0], owner, others[1], owner])


static func create(field: String, heroes: PackedStringArray, participants: Array, seed_value: int, hero_mode: String = "free", double_player: int = 1) -> RefCounted:
	if participants.size() not in [2, 3, 4]:
		return null
	var owners := controllers_for(participants.size(), double_player)
	var selected: PackedStringArray = heroes
	if selected.size() != owners.size():
		selected = PackedStringArray(DEFAULT_HEROES.slice(0, owners.size()))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if hero_mode == "random":
		var pool := Roster.HEROES.keys()
		SharedPiles.shuffle(pool, rng)
		selected = PackedStringArray(pool.slice(0, owners.size()))
	elif hero_mode in ["pick2", "pick3"]:
		selected = PackedStringArray(DEFAULT_HEROES.slice(0, owners.size()))
	var setup: Setup
	if field == "random":
		var arenas := Maps.NAMES.keys().filter(func(id): return Maps.supports(id, owners.size()))
		SharedPiles.shuffle(arenas, rng)
		for arena: String in arenas:
			setup = Setup.create(arena, selected, owners, rng)
			if setup != null:
				field = arena
				break
	elif Maps.supports(field, owners.size()):
		setup = Setup.create(field, selected, owners, rng)
	if setup == null:
		return null
	var session := new(field, setup, participants)
	if hero_mode in ["pick2", "pick3"]:
		session._draft_count = 2 if hero_mode == "pick2" else 3
		session._draft_pool = Roster.HEROES.keys()
		session._offer_heroes()
	return session


static func has_duplicate_heroes(heroes: Array) -> bool:
	for hero: String in heroes:
		if heroes.count(hero) > 1:
			return true
	return false


func _init(field: String, setup: Setup, participants: Array) -> void:
	arena = field
	game = setup
	players = participants.duplicate(true)
	rules = Rules.new(game)
	rules.start_turn()


func close() -> void:
	rules.clear_choices()


func actor() -> int:
	if _draft_count > 0:
		return game.controllers[_draft_choices.size()]
	var place := rules.choosing_seat()
	return game.controllers[place] if place >= 0 else -1


func tick(delta: float) -> bool:
	if _draft_count > 0:
		return false
	if rules.combat_pause > 0.0:
		_reveal_time += delta
		if _reveal_time < rules.combat_pause:
			return false
		_reveal_time = 0.0
		rules.resume_combat()
		_record_combat()
		return true
	if rules.pending_impact.is_valid():
		_reveal_time += delta
		if _reveal_time < DURING_SECONDS * rules.during_events.size() + BEFORE_IMPACT_SECONDS:
			return false
		_reveal_time = 0.0
		rules.finish_combat_impact()
		_record_combat()
		return true
	if rules.phase != Rules.Phase.COMBAT_REVEAL:
		_reveal_time = 0.0
		return false
	_reveal_time += delta
	if _reveal_time < REVEAL_SECONDS:
		return false
	_reveal_time = 0.0
	var resolved := rules.resolve_combat(true)
	_record_combat()
	return resolved


func act(viewer: int, kind: String, action: Dictionary) -> bool:
	if _draft_count > 0:
		return kind == "draft_hero" and action.get("hero") is String and _choose_hero(viewer, action.hero)
	var active := rules.seat
	var ok := false
	var scheme_name := ""
	var played_scheme: Dictionary = {}
	match kind:
		"place":
			ok = action.get("cell") is int and game.place(viewer, action.cell)
			if ok:
				rules.start_turn()
		"size":
			ok = action.get("large") is bool and game.choose_size(viewer, action.large)
			if ok:
				rules.start_turn()
		"maneuver":
			if action.has("cell"):
				if action.get("fighter") is int and action.cell is int and action.cell in rules.maneuver_preview_cells(viewer, action.fighter):
					ok = rules.begin_maneuver(viewer)
					if ok:
						rules.move_in_maneuver(viewer, action.fighter, action.cell)
			else:
				ok = rules.begin_maneuver(viewer)
		"boost":
			ok = action.get("key") is String and rules.boost_maneuver(viewer, action.key)
		"move":
			ok = action.get("fighter") is int and action.get("cell") is int and rules.move_in_maneuver(viewer, action.fighter, action.cell)
		"end_maneuver":
			ok = rules.end_maneuver(viewer)
		"door":
			ok = action.get("fighter") is int and action.get("door") is int and rules.toggle_maneuver_door(viewer, action.fighter, action.door)
		"battlefield_item":
			ok = action.get("fighter") is int and action.get("item") is int and rules.use_battlefield_item(viewer, action.fighter, action.item)
		"discard":
			ok = action.get("key") is String and rules.discard_to_limit(viewer, action.key)
		"attack":
			var target: Variant = action.get("target")
			var key: Variant = action.get("key", "")
			ok = action.get("fighter") is int and target is Vector2i and key is String and rules.begin_attack(viewer, action.fighter, target.x, target.y, key)
		"scheme":
			if action.get("fighter") is int and action.get("key") is String:
				for card: Dictionary in game.hands[active]:
					if card.key == action.key:
						scheme_name = card.name
						played_scheme = card
						break
				ok = rules.play_scheme(viewer, action.fighter, action.key)
		"combat":
			ok = rules.choose_combat_card(viewer, action)
			if rules.phase == Rules.Phase.COMBAT_REVEAL:
				_reveal_time = 0.0
		"effect":
			ok = action.get("request") is int and rules.choose_effect(viewer, action.request, action.get("answer"))
	if ok:
		rules._run_effects()
		var free_scheme: Dictionary = rules.free_scheme_notice
		if int(free_scheme.get("id", 0)) > _seen_free_scheme:
			_seen_free_scheme = free_scheme.id
			_scheme_notice = {"id": int(_scheme_notice.get("id", 0)) + 1, "card": free_scheme.card}
			_log("Бесплатный приём · %s." % free_scheme.card.name)
		match kind:
			"battlefield_item":
				var item := Maps.Battlefields.card(action.item)
				_scheme_notice = {"id": int(_scheme_notice.get("id", 0)) + 1, "card": item}
				_log("Предмет поля · %s." % item.name)
			"maneuver":
				_log("%s выполняет манёвр." % Roster.HEROES[game.heroes[active]].name)
			"door":
				_log("Хеорот · дверь %s." % ("закрыта" if action.door in game.board.closed_doors else "открыта"))
			"scheme":
				_log("Приём: %s." % scheme_name)
				_scheme_notice = {"id": int(_scheme_notice.get("id", 0)) + 1, "card": played_scheme.duplicate(true)}
		_record_combat()
	return ok


func get_view(viewer: int, selected_hand: int = -1) -> Dictionary:
	if _draft_count > 0:
		return _draft_view(viewer)
	var setup := game.pending()
	var combat := rules.attack_view(viewer)
	var effect := rules.effect_view(viewer)
	var combat_request: Dictionary = combat.get("choice", {})
	var requested: int = combat_request.get("hand", effect.get("seat", rules.choosing_seat()))
	if requested < 0 or game.controllers[requested] != viewer:
		requested = selected_hand if selected_hand >= 0 and selected_hand < game.heroes.size() and game.controllers[selected_hand] == viewer else game.controllers.find(viewer)
	elif selected_hand >= 0 and selected_hand < game.heroes.size() and game.controllers[selected_hand] == viewer and combat_request.is_empty() and effect.is_empty():
		requested = selected_hand
	if viewer < 0:
		requested = -1
	var hand := Hand.view_for(game.hands, game.controllers, viewer, requested, combat_request, {}, game.heroes)
	var figures: Array = []
	var positions := {}
	for index in game.board.cell_count():
		positions[index] = game.board.position_for(index)
	for place in game.fighters.size():
		for index in game.fighters[place].size():
			var figure: Dictionary = game.fighters[place][index]
			if figure.space >= 0:
				figures.append({"seat": place, "fighter": index, "cell": figure.space,
					"token": _token(place, figure), "hero": figure.is_hero, "hp": figure.health,
					"at": game.board.position_for(figure.space), "name": _fighter_name(place, figure),
					"character": game.heroes[place], "walk": Array(figure.get("walk", [])).map(game.board.position_for),
					"walk_serial": figure.get("walk_serial", 0), "status": rules.hero_status(place) if figure.is_hero else ""})
	var targets := {}
	var moves := {}
	var attacks := {}
	var schemes := {}
	var controlled := game.controllers[rules.seat] == viewer
	var winners: Array = []
	if rules.winner >= 0:
		for place in game.heroes.size():
			var controller: int = game.controllers[place]
			if place % 2 == rules.winner and controller not in winners:
				winners.append(controller)
	if not setup.is_empty() and game.controllers[setup.seat] == viewer:
		for cell: int in setup.get("cells", []):
			targets[cell] = positions[cell]
	elif controlled and rules.phase == Rules.Phase.MANEUVER:
		for index in game.fighters[rules.seat].size():
			moves[index] = Array(rules.maneuver_cells(viewer, index))
	elif controlled and rules.phase == Rules.Phase.ACTION:
		for figure: Dictionary in figures:
			if figure.seat != rules.seat:
				continue
			var selected: Dictionary = game.fighters[rules.seat][figure.fighter]
			moves[figure.fighter] = Array(rules.maneuver_preview_cells(viewer, figure.fighter))
			var targets_for_fighter: Array = []
			var schemes_for_fighter: Array = []
			var has_attack := false
			for card: Dictionary in game.hands[rules.seat]:
				if rules.card_can_play(card, Catalog.Kind.SCHEME, selected.is_hero):
					schemes_for_fighter.append(card.duplicate(true))
				has_attack = has_attack or rules.card_can_play(card, Catalog.Kind.ATTACK, selected.is_hero)
			if has_attack:
				for target: Dictionary in figures:
					if target.seat % 2 != rules.seat % 2 and not rules.attack_keys_for(Vector2i(figure.seat, figure.fighter), target.cell).is_empty():
						targets_for_fighter.append(target.cell)
			attacks[figure.fighter] = targets_for_fighter
			schemes[figure.fighter] = schemes_for_fighter
	var doors: Array = []
	for door in game.board.doors.size():
		var center := Vector2.ZERO
		for edge: Vector2i in game.board.doors[door]:
			center += (game.board.position_for(edge.x) + game.board.position_for(edge.y)) * 0.5
		var allowed: Array[int] = []
		if controlled:
			for fighter in game.fighters[rules.seat].size():
				if door in rules.maneuver_doors(viewer, fighter):
					allowed.append(fighter)
		doors.append({"id": door, "at": center / game.board.doors[door].size(),
			"closed": door in game.board.closed_doors, "allowed": allowed})
	return {
		"phase": phase, "phase_title": "Победа команды %s" % ("А" if rules.winner == 0 else "Б") if rules.winner >= 0 else Roster.HEROES[game.heroes[setup.get("seat", rules.seat)]].name,
		"step": _step(setup), "arena": arena, "fighters": figures, "targets": targets, "positions": positions, "doors": doors,
		"active": rules.seat, "viewer": viewer, "actor": actor(), "phase_id": rules.phase, "actions_left": rules.actions_left,
		"actor_name": players[actor()].name if actor() >= 0 else "",
		"can_act": controlled and setup.is_empty(), "moves": moves, "attacks": attacks, "schemes": schemes,
		"boost_allowed": controlled and rules.can_boost_maneuver(),
		"maneuver_in_transit": controlled and rules.phase == Rules.Phase.MANEUVER and rules._maneuver_in_transit(),
		"setup": setup if not setup.is_empty() and game.controllers[setup.seat] == viewer else {},
		"hand": hand, "piles": _public_piles(), "effect": effect,
		"scheme_notice": _scheme_notice,
		"public_card_notice": rules.public_card_notice.duplicate(true),
		"form": "hyde" if rules.hyde else "jekyll",
		"fog": game.fog.map(func(cell: int) -> Vector2: return game.board.position_for(cell)),
		"battlefield_items": (rules.battlefield_items + rules.used_items).duplicate(true),
		"misery_notice": rules.misery_opened.duplicate(true),
		"active_miseries": rules.miseries.map(rules.misery_card),
		"combat": _public_combat(combat), "combat_outcome": _combat_outcome(), "clock": false, "turn": rules.seat,
		"players": players.duplicate(true), "winners": winners, "team": game.heroes.size() == 4,
		"journal": _journal.duplicate(),
	}


func _draft_view(viewer: int) -> Dictionary:
	var choosing := actor()
	return {
		"phase": phase, "phase_title": "Выбор персонажа", "step": "", "arena": arena,
		"fighters": [], "targets": {}, "positions": {}, "active": -1, "viewer": viewer,
		"actor": choosing, "actor_name": players[choosing].name, "phase_id": -1,
		"can_act": false, "moves": {}, "attacks": {}, "schemes": {},
		"setup": {}, "hand": Hand.view_for([], [], -1, -1, {}), "piles": [], "effect": {},
		"combat": {}, "clock": false, "players": players.duplicate(true),
		"draft": {"offers": _draft_offers.duplicate() if viewer == choosing else [],
			"remaining": game.heroes.size() - _draft_choices.size()},
	}


func _offer_heroes() -> void:
	SharedPiles.shuffle(_draft_pool, game.random)
	_draft_offers = _draft_pool.slice(0, _draft_count)


func _choose_hero(viewer: int, hero: String) -> bool:
	if viewer != actor() or hero not in _draft_offers:
		return false
	_draft_choices.append(hero)
	_draft_pool.erase(hero)
	if _draft_choices.size() == game.heroes.size():
		var next: Setup = Setup.create(arena, _draft_choices, game.controllers, game.random)
		rules.clear_choices()
		game = next
		rules = Rules.new(game)
		_draft_count = 0
		_draft_offers.clear()
		rules.start_turn()
	else:
		_offer_heroes()
	return true


func _fighter_name(place: int, fighter: Dictionary) -> String:
	if game.heroes[place] == "witches":
		return "Вещая сестра %d" % (game.fighters[place].find(fighter) + 1)
	var hero: Dictionary = Roster.HEROES[game.heroes[place]]
	return hero.name if fighter.is_hero else hero.sidekick.name


func _public_piles() -> Array:
	var piles := Piles.public_view(game.decks, game.discards, game.heroes, game.hands)
	for place in piles.size():
		piles[place].merge(rules.bard.special_pile(place))
	return piles


func _token(place: int, fighter: Dictionary) -> String:
	if fighter.is_hero and game.heroes[place] == "jekyll_hyde" and rules.hyde:
		return "hyde"
	if game.heroes[place] == "witches":
		return fighter.get("token", "witch_0")
	if fighter.is_hero:
		return game.heroes[place]
	if fighter.id == "archer":
		return "archer_%d" % fighter.health
	return fighter.id


func _step(setup: Dictionary) -> String:
	if not setup.is_empty():
		return "Расстановка"
	match rules.phase:
		Rules.Phase.ACTION:
			return "Действий: %d" % rules.actions_left
		Rules.Phase.MANEUVER:
			return "Манёвр"
		Rules.Phase.DISCARD:
			return "Сброс до семи"
		Rules.Phase.EFFECT_CHOICE:
			return "Выбор эффекта"
		Rules.Phase.COMBAT_CHOICE, Rules.Phase.COMBAT_REVEAL:
			return "Бой"
	return ""


func _public_combat(combat: Dictionary) -> Dictionary:
	if combat.is_empty():
		return {}
	var cards: Dictionary = combat.cards
	var attacker: Vector2i = combat.attacker
	var defender: Vector2i = combat.defender
	var result := {"id": combat.id, "attack_hero": game.heroes[attacker.x], "defense_hero": game.heroes[defender.x],
		"attacker": attacker, "defender": defender,
		"attack_name": _fighter_name(attacker.x, game.fighters[attacker.x][attacker.y]),
		"defense_name": _fighter_name(defender.x, game.fighters[defender.x][defender.y])}
	result["pending_reveal"] = combat.get("pending_reveal", false)
	result["attack_face_up"] = cards.get("attack", {}).get("definition", "") == "tomoe:12"
	if cards.is_empty():
		if combat.attack_sealed:
			result["attack"] = {"sealed": true}
	else:
		result["attack"] = cards.get("attack", {"sealed": true})
		result["defense"] = cards.get("defense", {})
		result["defense_face_up"] = cards.get("defense", {}).get("definition", "") == "sherlock:22"
		result["immediate"] = rules.immediate_cue.duplicate()
		result["board_focus"] = rules.board_focus or rules.has_combat_choice()
		if rules.pending_impact.is_valid():
			result["during"] = rules.during_events.duplicate(true)
	return result


func _combat_outcome() -> Dictionary:
	var combat: Dictionary = rules.last_combat
	if combat.is_empty():
		return {}
	var losses: Array = []
	for loss: Dictionary in combat.losses:
		var fighter: Vector2i = loss.fighter
		losses.append({"name": _fighter_name(fighter.x, game.fighters[fighter.x][fighter.y]), "amount": loss.amount})
	return {"id": combat.id, "hit": combat.attacker_won, "losses": losses, "board_after": combat.get("board_after", false),
		"values": combat.get("card_values", [combat.attack_value, combat.defense_value])}


func _record_combat() -> void:
	var combat: Dictionary = rules.last_combat
	if combat.is_empty() or is_same(combat, _logged_combat):
		return
	_logged_combat = combat
	var defense: Dictionary = combat.defense
	_log("%s / %s · боевой урон: %d." % [combat.attack.name, defense.get("name", "без защиты"), combat.damage])


func _log(line: String) -> void:
	_journal.append(line)
	if _journal.size() > 40:
		_journal.pop_front()
