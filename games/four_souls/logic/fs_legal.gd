extends RefCounted
## Four Souls: что сейчас можно сделать. Единый источник для анти-зависания, фаззера и UI.
## candidates() перечисляет правдоподобные действия по фазе, legal() оставляет только те,
## которые FSRules.action принимает на копии состояния (никакой второй копии правил).
## Ручные операции панели эффекта — короткое меню с аргументами по умолчанию.

## Операции панели, которые пробуются как «законные» (аргументы подставляются ниже).
const EFFECT_MENU := ["coins", "loot", "damage", "heal", "prevent_death", "cancel_attack", "roll",
	"reroll", "attach_curse", "souls", "monster_damage", "self_underdeck", "self_give", "recharge", "treasure", "take_shop", "skip_turn"]

static func legal(g: FSRules, seat: int) -> Array:
	var out: Array = []
	for candidate: Dictionary in candidates(g, seat):
		var trial := g.clone()
		# Внешний тестовый источник может иметь очередь/счётчик. Пробное действие
		# использует копию RNG и не расходует очередь исходной партии.
		trial.roll_source = Callable()
		if trial.action(seat, str(candidate.kind), candidate.get("arg")):
			out.append(candidate)
	return out

## Есть ли у кого-нибудь хоть одно законное действие (партия не зависла).
static func anyone_can_act(g: FSRules) -> bool:
	if g.phase == "game_over":
		return true
	var order: Array = [g.actor()]
	for seat in g.players.size():
		if seat not in order:
			order.append(seat)
	for seat: int in order:
		for candidate: Dictionary in candidates(g, seat):
			if g.clone().action(seat, str(candidate.kind), candidate.get("arg")):
				return true
	# Когда все ресурсы ответов исчерпаны, штатные часы хоста всё равно закрывают окно.
	# Это не клиентское действие и не право досрочно пропустить оставшиеся секунды.
	return advance_clock(g.clone())

static func advance_clock(g: FSRules) -> bool:
	if g.phase != "priority" or g.stack.is_empty() or g._after_stack == "starting_continue":
		return false
	g.tick(0.0)
	return g.tick(g.RESPONSE_WINDOW + 0.01)

static func _a(kind: String, arg = null) -> Dictionary:
	return {"kind": kind, "arg": arg}

static func candidates(g: FSRules, seat: int) -> Array:
	var out: Array = []
	if seat < 0 or seat >= g.players.size() or g.phase == "game_over":
		return out
	var is_current: bool = seat == g.current
	if g.phase in ["turn", "priority", "battle_roll", "death"] and not g.dead[seat] and bool(g.character_ready[seat]):
		out.append(_a("character"))
		if g._item_count(seat, 5) > 0:
			out.append(_a("mushroom_counter20"))
	if is_current and g._item_count(seat,173)>0: out.append(_a("inspect_item13"))
	match g.phase:
		"starting_item":
			if not g._starting_choices.is_empty():
				for id in g._starting_choices[0].cards:
					out.append(_a("choose_starting_item", {"card": int(id)}))
		"discard":
			for id in g.hands[seat]:
				out.append(_a("discard", {"card": int(id)}))
		"discard_target":
			for target in g.players.size():
				out.append(_a("discard_target", {"target": target}))
		"forced_discard":
			for index in g.hands[seat].size():
				out.append(_a("forced_discard", {"item": index}))
		"death":
			out.append(_a("death", _death_choice(g, seat)))
		"effect":
			for index in g._card_choices().size():
				out.append(_a("card_choice", {"index": index, "revision": g.revision}))
			for target in g.resolving.get("reward_soul_targets", []):
				out.append(_a("reward_soul_target", {"target": target}))
			if bool(g.resolving.get("reward_damage", false)):
				for target: Dictionary in g._reward_damage_targets():
					out.append(_a("reward_damage", target))
			for target in g.resolving.get("reward_winners", []):
				out.append(_a("reward_winner", {"target": target}))
			out.append(_a("effect_done"))
			out.append(_a("effect_roll"))
			for slot in g._peep_spawn_slots():
				out.append(_a("place_bloat", {"slot": slot}))
			for id in g.peek.get("cards", []):
				out.append(_a("peek_take", {"card": int(id), "dest": "discard"}))
			for op: String in EFFECT_MENU:
				out.append(_a("effect", _effect_arg(g, op)))
		"priority":
			if is_current:
				for kind in ["end", "roll"]:
					out.append(_a(kind))
				out.append(_a("finish_start"))
			out.append(_a("effect_roll"))
			out.append(_a("death", _death_choice(g, seat)))
			_add_responses(g, seat, out)
		"turn":
			if is_current:
				out.append(_a("end"))
				for slot in range(-1, g.monsters.size()):
					out.append(_a("attack", {"slot": slot}))
				for index in g._familiar_targets15().size():
					out.append(_a("attack_familiar15", {"index": index}))
				for slot in range(-2, g.shop.size()):
					out.append(_a("buy", {"slot": slot}))
				for target in g._permitted_player_attack_targets():
					out.append(_a("attack_player", {"target": target}))
				if g.dlc:
					out.append(_a("room"))
					for index in g._extra_rooms20.size():
						out.append(_a("room", {"index": index}))
			_add_responses(g, seat, out)
		"battle_roll":
			if seat == g.actor():
				out.append(_a("roll"))
			_add_responses(g, seat, out)
	return out

## Ответы, доступные в любой открытой фазе: лут и активация предметов.
static func _add_responses(g: FSRules, seat: int, out: Array) -> void:
	if int(g._top_loot20.get(seat, -1)) == g.turn_serial and not g.decks.loot.is_empty():
		out.append(_a("loot_top20"))
	if int(g._spider_tokens15.get(seat, 0)) > 0:
		out.append(_a("remove_spider15"))
	for id in g.hands[seat]:
		out.append(_a("loot", {"card": int(id)}))
	if seat == g.current:
		for index in g._extra_rooms20.size():
			out.append(_a("room_activate20", {"item": index}))
	for index in g.items[seat].size():
		if int(g.items[seat][index].id) == 248:
			out.append(_a("activate", {"item": index, "ability": "kill"}))
		if not bool(g.items[seat][index].tapped):
			out.append(_a("activate", {"item": index}))

## Штраф за смерть: первая карта лута и первый не вечный предмет (если есть).
static func _death_choice(g: FSRules, seat: int) -> Dictionary:
	var choice := {"loot": -1, "item": -1}
	if not g.hands[seat].is_empty():
		choice.loot = int(g.hands[seat][0])
	for index in g.items[seat].size():
		if not bool(g.items[seat][index].eternal):
			choice.item = index
			break
	return choice

static func _effect_arg(g: FSRules, op: String) -> Dictionary:
	var owner: int = int(g.resolving.get("owner", g.current))
	var arg := {"op": op, "target": owner, "amount": 1}
	match op:
		"self_give":
			arg["target"] = (owner + 1) % g.players.size()
		"monster_damage":
			arg["item"] = maxi(0, g.battle)
		"recharge", "take_shop":
			arg["item"] = 0
	return arg
