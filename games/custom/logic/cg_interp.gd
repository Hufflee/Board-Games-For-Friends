class_name CGInterp
extends RefCounted
## Ограниченный интерпретатор JSON-блоков. Продолжение цепочки — только сериализуемые словари.

const Blocks := preload("res://games/custom/logic/cg_blocks.gd")
const STEP_LIMIT := 10000
const LOOP_LIMIT := 1000

static func number(r: Object, expression: Variant, ctx: Dictionary, depth: int = 0) -> float:
	var v: Variant = value(r, expression, ctx, depth)
	if not (v is int or v is float) or not is_finite(float(v)) or absf(float(v)) > 1000000000000.0:
		r.last_error = "В числовом гнезде требуется конечное число."
		return 0.0
	return float(v)

static func frames_snapshot(r: Object, frames: Array) -> Array:
	if frames.size() > 2048:
		r.last_error = "В ожидании слишком много незавершённых ветвей."
		return []
	var length := 0
	for frame: Dictionary in frames:
		length += JSON.stringify(frame).length()
		if length > 1024 * 1024:
			r.last_error = "Продолжение ожидания больше 1 МБ."
			return []
	return frames.duplicate(true)

static func value(r: Object, expression: Variant, ctx: Dictionary, depth: int = 0) -> Variant:
	if depth > 48:
		r.last_error = "Слишком глубокое выражение."
		return null
	if not expression is Dictionary:
		return expression
	var op := str(expression.get("op", ""))
	if op not in Blocks.EXPRESSIONS:
		r.last_error = "Неизвестное выражение %s." % op
		return null
	var a: Variant = null
	var b: Variant = null
	if expression.has("a"):
		a = value(r, expression.a, ctx, depth + 1)
	if op == "and" and not bool(a):
		return false
	if op == "or" and bool(a):
		return true
	if expression.has("b"):
		b = value(r, expression.b, ctx, depth + 1)
	match op:
		"literal": return expression.get("value")
		"dictionary_word":
			return preload("res://hub/shared_words.gd").pick(r.rng)
		"actor": return int(ctx.get("actor", 0))
		"current": return int(r.state.current)
		"leader": return int(r.state.leader)
		"next": return r.next_player(int(r.state.current))
		"players_count": return r.players.size()
		"round": return int(r.state.round)
		"turn": return int(r.state.turn_no)
		"index": return int(ctx.get("index", 0))
		"team":
			var seat := int(number(r, expression.get("player", {"op": "actor"}), ctx, depth + 1))
			if seat < 0 or seat >= r.players.size():
				r.last_error = "Игрок команды не найден."
				return -1
			return int(r.players[seat].get("team", 0))
		"player": return int(number(r, expression.get("index", 0), ctx, depth + 1))
		"answer": return ctx.get("answer")
		"card": return ctx.get("card", "")
		"zone":
			var id := str(expression.get("id", ""))
			var spec: Dictionary = r.zone_def(id)
			if spec.is_empty():
				r.last_error = "Зона %s не найдена." % id
				return ""
			if spec.get("owner", "shared") == "player":
				return "%s@%d" % [id, int(number(r, expression.get("player", {"op": "actor"}), ctx, depth + 1))]
			if spec.get("owner", "shared") == "team":
				return "%s#%d" % [id, int(number(r, expression.get("team", 0), ctx, depth + 1))]
			return id
		"count", "top", "has":
			var zone := str(value(r, expression.get("zone", ""), ctx, depth + 1))
			if not r.state.zones.has(zone):
				r.last_error = "Зона %s не найдена." % zone
				return null
			var cards: Array = r.state.zones[zone]
			if op == "count": return cards.size()
			if op == "top": return cards.back() if not cards.is_empty() else ""
			for id: String in cards:
				var card: Dictionary = r.state.cards[id]
				if _equal(card.data.get(str(expression.get("field", ""))), expression.get("equals")):
					return true
			return false
		"property":
			var id := str(value(r, expression.get("card", {"op": "card"}), ctx, depth + 1))
			if not r.state.cards.has(id):
				r.last_error = "Карта выражения не найдена."
				return null
			return r.state.cards[id].data.get(str(expression.get("field", "")))
		"var": return r.get_var(str(expression.get("id", "")), int(number(r, expression.get("player", {"op": "actor"}), ctx, depth + 1)))
		"random":
			if not (a is int or a is float) or not (b is int or b is float):
				r.last_error = "Границы случайного числа должны быть числами."
				return 0
			if not is_finite(float(a)) or not is_finite(float(b)) or absf(float(a)) > 2147483647 or absf(float(b)) > 2147483647:
				r.last_error = "Границы случайного числа слишком велики."
				return 0
			return r.rng.randi_range(int(a), int(b))
		"eq": return _equal(a, b)
		"ne": return not _equal(a, b)
		"and": return bool(a) and bool(b)
		"or": return bool(a) or bool(b)
		"not": return not bool(a)
		"dice_sum", "dice_count", "dice_value":
			var dice: Array = []
			if expression.has("player"):
				var seat := str(int(number(r, expression.player, ctx, depth + 1)))
				dice = r.state.dice.get(seat, {}).get("values", [])
			else:
				for roll: Dictionary in r.state.dice.values():
					dice.append_array(roll.get("values", []))
			if op == "dice_count": return dice.count(int(number(r, expression.get("face", 1), ctx, depth + 1)))
			if op == "dice_value":
				var index := int(number(r, expression.get("index", 0), ctx, depth + 1))
				return dice[index] if index >= 0 and index < dice.size() else 0
			var sum := 0
			for face: int in dice: sum += face
			return sum
	if not (a is int or a is float) or not (b is int or b is float):
		r.last_error = "Математика и сравнение требуют чисел."
		return null
	match op:
		"add": return a + b
		"sub": return a - b
		"mul": return a * b
		"div":
			if b == 0:
				r.last_error = "Деление на ноль."
				return null
			return float(a) / float(b)
		"min": return min(a, b)
		"max": return max(a, b)
		"lt": return a < b
		"le": return a <= b
		"gt": return a > b
		"ge": return a >= b
	return null

static func run(r: Object, frames: Array) -> String:
	while not frames.is_empty() and r.phase != "game_over" and r.last_error.is_empty():
		if frames.size() > 2048:
			r.last_error = "Слишком много вложенных ветвей."
			break
		r.steps += 1
		if r.steps > STEP_LIMIT:
			r.last_error = "Логика зациклилась: превышен предел шагов."
			break
		var frame: Dictionary = frames.back()
		if frame.has("event"):
			frames.pop_back()
			if frame.get("initial", false) and int(r.state.turn_no) != 1:
				continue
			var context: Dictionary = frame.context.duplicate(true)
			context.actor = int(r.state.current)
			frames.append_array(r.frames_for(str(frame.event), context))
			continue
		if int(frame.index) >= frame.blocks.size():
			frames.pop_back()
			continue
		var block: Dictionary = frame.blocks[int(frame.index)]
		frame.index = int(frame.index) + 1
		var ctx: Dictionary = frame.context
		var op := str(block.get("op", ""))
		if not Blocks.OPS.has(op):
			r.last_error = "Неизвестный блок %s." % op
			break
		for field: String in Blocks.OPS[op]:
			if not block.has(field): r.last_error = "Пустое гнездо %s." % field
		if not r.last_error.is_empty(): break
		r.state.trace.append(str(block.get("id", op)).left(128))
		if r.state.trace.size() > 200: r.state.trace.pop_front()
		match op:
			"shuffle":
				var zone := str(value(r, block.zone, ctx))
				if not r.state.zones.has(zone):
					r.last_error = "Зона перемешивания не найдена."
					continue
				var cards: Array = r.state.zones[zone]
				for i in range(cards.size() - 1, 0, -1):
					var j: int = r.rng.randi_range(0, i)
					var tmp: Variant = cards[i]
					cards[i] = cards[j]
					cards[j] = tmp
			"deal", "draw":
				var count := int(number(r, block.count, ctx))
				if count < 0 or count > 300:
					r.last_error = "Недопустимое число карт."
					continue
				var actors: Array = range(r.players.size()) if op == "deal" else [int(ctx.actor)]
				for who: int in actors:
					var sub := ctx.duplicate(true)
					sub.actor = who
					var source := str(value(r, block.from, sub))
					var target := str(value(r, block.to, sub))
					if not r.state.zones.has(source) or not r.state.zones.has(target) or r.state.zones[source].size() < count:
						r.last_error = "В зоне недостаточно карт для раздачи."
						break
					for i in count:
						var id: String = r.state.zones[source].back()
						r.move_card(id, target)
						ctx.card = id
			"move": r.move_card(str(value(r, block.card, ctx)), str(value(r, block.to, ctx)), str(block.get("position", "top")))
			"open", "close", "show":
				var id := str(value(r, block.card, ctx))
				if not r.state.cards.has(id):
					r.last_error = "Карта открытия не найдена."
				elif op == "show":
					var audience: Variant = value(r, block.get("for", "all"), ctx)
					var who := -1 if audience is String and audience == "all" else int(number(r, {"op": "literal", "value": audience}, ctx))
					r.state.reveals[id] = {"seconds": 2.0, "seat": who}
				elif op == "close":
					r.state.cards[id].face_up = false
					r.state.cards[id].visible_to = []
				else:
					var audience: Variant = value(r, block.get("for", "all"), ctx)
					if audience is String and audience == "all":
						r.state.cards[id].face_up = true
					else:
						var who := int(number(r, {"op": "literal", "value": audience}, ctx))
						if who >= 0 and who < r.players.size(): r.state.cards[id].visible_to.append(who)
			"collect":
				var destination := str(value(r, block.to, ctx))
				var deck := str(block.get("deck", ""))
				for id: String in r.state.cards:
					if deck.is_empty() or str(r.state.cards[id].deck) == deck:
						r.move_card(id, destination)
						r.state.cards[id].face_up = false
						r.state.cards[id].visible_to = []
			"set", "change":
				var who := int(number(r, block.get("player", {"op": "actor"}), ctx))
				var v: Variant = value(r, block.value, ctx)
				if op == "change":
					var old: Variant = r.get_var(str(block.var), who)
					if not (old is int or old is float) or not (v is int or v is float):
						r.last_error = "Изменить на число можно только числовую переменную."
						continue
					v += old
				r.set_var(str(block.var), who, v)
			"if":
				var nested: Array = block.get("then", []) if bool(value(r, block.condition, ctx)) else block.get("else", [])
				frames.append({"blocks": nested, "index": 0, "context": ctx.duplicate(true)})
			"repeat", "each_player", "each_card":
				var entries: Array = []
				if op == "repeat":
					var count := int(number(r, block.count, ctx))
					if count < 0 or count > LOOP_LIMIT:
						r.last_error = "Цикл не может превышать 1000 повторений."
						continue
					entries = range(count)
				elif op == "each_player": entries = range(r.players.size())
				else:
					var zone := str(value(r, block.zone, ctx))
					if not r.state.zones.has(zone):
						r.last_error = "Зона цикла не найдена."
						continue
					entries = r.state.zones[zone].duplicate()
				for i in range(entries.size() - 1, -1, -1):
					var sub := ctx.duplicate(true)
					sub.index = i
					if op == "each_player": sub.actor = entries[i]
					elif op == "each_card": sub.card = entries[i]
					frames.append({"blocks": block.body, "index": 0, "context": sub})
			"phase", "next":
				var sub := ctx.duplicate(true)
				sub.depth = int(ctx.get("depth", 0)) + 1
				if op == "phase":
					var end: Array = r.frames_for("phase_exit", sub)
					r.state.phase = str(block.phase)
					r.state["ready_seats"] = []
					r.reset_clock()
					frames.append_array(r.frames_for("phase_enter", sub))
					frames.append_array(end)
				else:
					if r.definition.rules.get("turn_mode", "circle") == "simultaneous":
						r.last_error = "В одновременной фазе используйте готовность всех вместо передачи хода."
						continue
					var end: Array = r.frames_for("turn_end", sub)
					var old := int(r.state.current)
					r.state.current = int(r.state.leader) if r.definition.rules.get("turn_mode", "circle") == "leader_only" else int(number(r, block.get("player", {"op": "next"}), ctx))
					for distance in range(1, r.players.size() + 1):
						var passed := posmod(old + distance, r.players.size())
						r.state.skips.erase(str(passed))
						if passed == int(r.state.current):
							break
					r.reset_clock()
					if int(r.state.current) < 0 or int(r.state.current) >= r.players.size():
						r.last_error = "Следующий игрок не найден."
						continue
					r.state.turn_no = int(r.state.turn_no) + 1
					sub.actor = int(r.state.current)
					frames.append_array(r.frames_for("turn_start", sub))
					var origin: int = int(r.state.leader) if r.definition.rules.get("turn_mode", "circle") == "leader_start" else 0
					if posmod(int(r.state.current) - origin, r.players.size()) <= posmod(old - origin, r.players.size()):
						r.state.round = int(r.state.round) + 1
						frames.append_array(r.frames_for("round_start", sub))
					frames.append_array(end)
			"skip", "eliminate", "leader":
				var who := int(number(r, block.player, ctx))
				if who < 0 or who >= r.players.size():
					r.last_error = "Игрок блока не найден."
				elif op == "leader":
					r.state.leader = who
					if r.definition.rules.get("turn_mode", "circle") == "leader_only":
						r.state.current = who
				elif op == "eliminate":
					r.players[who].eliminated = true
					if r.definition.rules.get("turn_mode", "circle") == "leader_only" and int(r.state.leader) == who:
						r.state.leader = r.next_player(who)
						r.state.current = int(r.state.leader)
				elif who == int(r.state.current):
					r.state.current = r.next_player(who)
					r.reset_clock()
				else:
					r.state.skips[str(who)] = true
			"roll", "roll_player":
				var who := int(number(r, block.get("player", {"op": "actor"}), ctx))
				var count := int(number(r, block.count, ctx))
				if count < 1 or count > 30 or who < 0 or who >= r.players.size():
					r.last_error = "Недопустимый набор кубиков."
					continue
				if op == "roll_player":
					var saved := frames_snapshot(r, frames)
					if not r.last_error.is_empty():
						continue
					r.state.pending = {"kind": "roll", "seat": who, "count": count, "visible": block.get("visible", "all"), "frames": saved, "context": ctx.duplicate(true)}
					return ""
				roll(r, who, count, str(block.get("visible", "all")))
				var rolled := ctx.duplicate(true)
				rolled.actor = who
				rolled.answer = r.state.dice[str(who)].values.duplicate()
				rolled.depth = int(ctx.get("depth", 0)) + 1
				frames.append_array(r.frames_for("rolled", rolled))
			"ask_card", "ask_player", "ask_option", "ask_number", "wait":
				var pending := {"kind": op, "seat": int(number(r, block.get("player", {"op": "actor"}), ctx)), "frames": frames_snapshot(r, frames), "context": ctx.duplicate(true)}
				if op == "ask_card":
					var zone := str(value(r, block.zone, ctx))
					if not r.state.zones.has(zone):
						r.last_error = "Зона выбора не найдена."
						continue
					pending.options = []
					for id: String in r.state.zones[zone]:
						if r.card_visible(id, int(pending.seat)):
							pending.options.append(id)
					if pending.options.is_empty():
						r.last_error = "В зоне нет доступных для выбора карт."
						continue
				elif op == "ask_player": pending.options = range(r.players.size())
				elif op == "ask_option":
					pending.options = value(r, block.options, ctx)
					if not pending.options is Array or pending.options.is_empty() or pending.options.size() > 300:
						r.last_error = "Нужен непустой список из не более 300 вариантов."
						continue
				elif op == "ask_number":
					pending.min = number(r, block.min, ctx)
					pending.max = number(r, block.max, ctx)
					if pending.min > pending.max:
						r.last_error = "Границы выбора числа перепутаны."
				else:
					pending.seat = -1
					pending.seconds = maxf(0.0, float(number(r, block.seconds, ctx)))
				if pending.seat >= r.players.size() or pending.seat < -1:
					r.last_error = "Игрок ожидания не найден."
					continue
				if op != "wait" and pending.seat < 0:
					r.last_error = "У выбора должен быть конкретный игрок."
					continue
				if not r.last_error.is_empty():
					continue
				r.state.pending = pending
				return ""
			"log":
				r.state.log.append(str(value(r, block.text, ctx)).left(4096))
				if r.state.log.size() > 200: r.state.log.pop_front()
			"hint":
				var audience: Variant = value(r, block.get("player", {"op": "actor"}), ctx)
				var who := -1 if audience is String and audience == "all" else int(number(r, {"op": "literal", "value": audience}, ctx))
				r.state.hints.append({"text": str(value(r, block.text, ctx)).left(4096), "seat": who})
				if r.state.hints.size() > 20:
					r.state.hints.pop_front()
			"sound":
				if str(block.name) not in Blocks.SOUNDS:
					r.last_error = "Выберите встроенный звук."
				else:
					r.state["sound_event"] = {"id": int(r.state.get("sound_event", {}).get("id", 0)) + 1, "name": str(block.name)}
			"stop": frames.clear()
			"win", "lose", "finish":
				var winners: Array = []
				if op == "win":
					var who: Variant = value(r, block.player, ctx)
					if who is String and who == "all":
						winners = range(r.players.size())
					elif who is int or who is float:
						if who < 0 or who >= r.players.size() or float(int(who)) != float(who):
							r.last_error = "Номер победителя должен быть целым и соответствовать месту."
						else:
							winners = [int(who)]
					else:
						r.last_error = "В блоке победы нужен игрок или «все»."
				elif op == "finish":
					var best: Variant = null
					for s in r.players.size():
						var owner: int = int(r.players[s].get("team", 0)) if r.var_def(str(block.var)).get("scope") == "team" else s
						var score: Variant = r.get_var(str(block.var), owner)
						if best == null or (score < best if block.get("mode", "max") == "min" else score > best):
							best = score
							winners = [s]
						elif score == best: winners.append(s)
				for who: int in winners:
					if who < 0 or who >= r.players.size(): r.last_error = "Победитель не найден."
				r.state.winners = winners
				r.state.phase = "game_over"
	return r.last_error

static func roll(r: Object, who: int, count: int, visibility: String) -> void:
	var dice: Array = []
	for i in count: dice.append(r.rng.randi_range(1, 6))
	r.state.dice[str(who)] = {"values": dice, "visible": visibility}

static func _equal(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return a == b
	return a == b if typeof(a) == typeof(b) else false

static func answer(r: Object, seat: int, kind: String, data: Dictionary) -> bool:
	var pending: Dictionary = r.state.pending
	if kind != "answer" or int(pending.get("seat", -2)) != seat:
		return false
	var supplied: Variant = data.get("value")
	match str(pending.kind):
		"ask_card", "ask_player", "ask_option":
			if not pending.get("options", []).has(supplied): return false
		"ask_number":
			if not (supplied is int or supplied is float) or supplied < pending.min or supplied > pending.max: return false
		"roll":
			# Клиент подтверждает жест, результат броска всегда выбирает хост.
			roll(r, seat, int(pending.count), str(pending.visible))
			supplied = r.state.dice[str(seat)].values.duplicate()
		_: return false
	var frames: Array = pending.frames.duplicate(true)
	for frame: Dictionary in frames:
		frame.context.answer = supplied
		if pending.kind == "ask_card": frame.context.card = supplied
	r.state.pending = {}
	if pending.kind == "roll":
		var ctx: Dictionary = pending.context.duplicate(true)
		ctx.actor = seat
		ctx.answer = supplied
		ctx.depth = int(ctx.get("depth", 0)) + 1
		frames.append_array(r.frames_for("rolled", ctx))
	return run(r, frames).is_empty()
