class_name PKRules
extends RefCounted
## «Покер»: техасский холдем без лимита на хосте, без UI. Режимы «Классика» и «Спортивный» (сессии по 14 раздач).
## Оценка рук — TGPoker (The Gang). Карты: id 0..51, масть = id / 13, значение = id % 13 + 2.
## Проверка: godot --headless --path . --script res://tests/test_poker.gd

const SB := 1
const BB := 2
const START := 100 * BB  # все начинают со 100 BB
const SESSION_HANDS := 14
const TURN_TIME := 30.0
const SHOW_TIME := 5.0  # вскрытие на столе, потом следующая раздача
const FOLD_SHOW_TIME := 2.5
const SESSION_TIME := 12.0  # итоги сессии, потом следующая
const Bot := preload("res://games/poker/logic/pk_bot.gd")
const STREETS := ["preflop", "flop", "turn", "river"]

var players: Array = []
var mode := "classic"
var phase := "hand"  # hand → showdown → … → session_end (спорт) → … → game_over; waiting — некому играть (классика)
var street := "preflop"
var stacks: Array = []
var hole: Array = []  # по 2 карты на место; [] — не в раздаче
var board: Array = []
var deck: Array = []
var button := -1
var sb_seat := -1
var bb_seat := -1
var to_act := -1
var bets: Array = []  # ставка на текущей улице
var totals: Array = []  # вклад в банк за раздачу
var folded: Array = []
var acted: Array = []
var locked: Array = []  # после неполного ва-банка: только колл или пас
var current_bet := 0
var min_raise := BB
var last_action: Array = []  # подпись под местом: «Колл 4», «Пас»…
var hand_no := 0  # раздача в сессии (спорт) или всего (классика)
var session_no := 1
var scores: Array = []  # победные очки (спорт)
var places: Array = []  # места прошлой сессии: [{seat, place, points}]
var bust_order: Array = []  # вылетевшие в сессии: [[seat, раздача, стек перед ней]]
var hand_start_stacks: Array = []
var rebuys: Array = []
var result: Dictionary = {}  # итог раздачи: {pots: [{amount, winners}], hands: {seat: name}, fold_win}
var winners: Array = []
var log: Array = []
var time_left := 0.0
var _bot_wait := 0.0
var revision := 0
var rng := RandomNumberGenerator.new()


func new_game(seats: Array, options: Dictionary = {}) -> String:
	if seats.size() < 2 or seats.size() > 8:
		return "Нужно от 2 до 8 игроков."
	players = seats.duplicate(true)
	mode = "sport" if str(options.get("mode", "classic")) == "sport" else "classic"
	if options.has("seed"):
		rng.seed = int(options.seed)
	else:
		rng.randomize()
	var n := players.size()
	stacks = _filled(START)
	scores = _filled(0)
	rebuys = _filled(0)
	button = rng.randi_range(0, n - 1)
	session_no = 1
	hand_no = 0
	places.clear()
	bust_order.clear()
	winners.clear()
	log.clear()
	phase = "hand"
	_start_hand()
	return ""


func _filled(value: Variant) -> Array:
	var a := []
	a.resize(players.size())
	a.fill(value)
	return a


## Сколько очков нужно для победы в спортивном режиме.
func target() -> int:
	return players.size() * 2 + 1


## Очки за место (1 — лучшее) при N игроках: N, N−1, …, 2, последнее — 0.
static func place_points(place: int, count: int) -> int:
	return 0 if place >= count else count - place + 1


## Места с фишками, которые играют следующую раздачу.
func active_seats() -> Array:
	var seats := []
	for seat: int in players.size():
		if int(stacks[seat]) > 0:
			seats.append(seat)
	return seats


func _next_active(from: int, pool: Array) -> int:
	for step: int in range(1, players.size() + 1):
		var seat := (from + step) % players.size()
		if pool.has(seat):
			return seat
	return -1


func _start_hand() -> void:
	var seats := active_seats()
	if seats.size() < 2:
		if mode == "sport":
			_end_session()
		else:
			phase = "waiting"
			to_act = -1
			revision += 1
		return
	phase = "hand"
	street = "preflop"
	hand_no += 1
	hand_start_stacks = stacks.duplicate()
	board.clear()
	result = {}
	hole = _filled([])
	bets = _filled(0)
	totals = _filled(0)
	folded = _filled(true)
	acted = _filled(false)
	locked = _filled(false)
	last_action = _filled("")
	for seat: int in seats:
		folded[seat] = false
	deck = range(52)
	for i: int in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	button = _next_active(button, seats)
	if seats.size() == 2:
		sb_seat = button
		bb_seat = _next_active(button, seats)
	else:
		sb_seat = _next_active(button, seats)
		bb_seat = _next_active(sb_seat, seats)
	_put(sb_seat, mini(SB, int(stacks[sb_seat])))
	_put(bb_seat, mini(BB, int(stacks[bb_seat])))
	last_action[sb_seat] = "Малый блайнд %d" % bets[sb_seat]
	last_action[bb_seat] = "Большой блайнд %d" % bets[bb_seat]
	current_bet = BB
	min_raise = BB
	for _round: int in 2:
		for k: int in seats.size():
			var seat: int = seats[(seats.find(sb_seat) + k) % seats.size()]
			hole[seat] = hole[seat] + [deck.pop_back()]
	_note("Раздача %d · кнопка у %s" % [hand_no, players[button].name])
	to_act = _next_to_act(bb_seat)
	time_left = TURN_TIME
	_bot_wait = _bot_delay()
	revision += 1
	if to_act < 0:
		_finish_street()


## Поставить фишки в банк (ограничено стеком).
func _put(seat: int, amount: int) -> void:
	var paid := mini(amount, int(stacks[seat]))
	stacks[seat] = int(stacks[seat]) - paid
	bets[seat] = int(bets[seat]) + paid
	totals[seat] = int(totals[seat]) + paid


func in_hand(seat: int) -> bool:
	return not bool(folded[seat]) and not hole[seat].is_empty()


func all_in(seat: int) -> bool:
	return in_hand(seat) and int(stacks[seat]) == 0


func pot() -> int:
	var sum := 0
	for amount: int in totals:
		sum += amount
	return sum


## Следующий после from, кому ещё надо ходить на этой улице; -1 — улица закрыта.
func _next_to_act(from: int) -> int:
	var able := 0
	for seat: int in players.size():
		if in_hand(seat) and not all_in(seat):
			able += 1
	for step: int in range(1, players.size() + 1):
		var seat := (from + step) % players.size()
		if not in_hand(seat) or all_in(seat):
			continue
		if not bool(acted[seat]) or int(bets[seat]) < current_bet:
			# один, кто может ходить, и ему нечего уравнивать — торговаться не с кем
			if able <= 1 and int(bets[seat]) >= current_bet:
				return -1
			return seat
	return -1


## Сколько месту нужно доставить, чтобы уравнять.
func to_call(seat: int) -> int:
	return mini(current_bet - int(bets[seat]), int(stacks[seat]))


## Минимальная ставка «до» для рейза (или ставки на пустой улице).
func min_raise_to(seat: int) -> int:
	return mini(current_bet + min_raise, int(bets[seat]) + int(stacks[seat]))


func max_raise_to(seat: int) -> int:
	return int(bets[seat]) + int(stacks[seat])


func can_raise(seat: int) -> bool:
	return not bool(locked[seat]) and int(stacks[seat]) > to_call(seat)


func fold(seat: int) -> bool:
	if phase != "hand" or seat != to_act:
		return false
	folded[seat] = true
	last_action[seat] = "Пас"
	_note("%s: пас" % players[seat].name)
	_after_action(seat)
	return true


func check_call(seat: int) -> bool:
	if phase != "hand" or seat != to_act:
		return false
	var need := to_call(seat)
	_put(seat, need)
	acted[seat] = true
	if need == 0:
		last_action[seat] = "Чек"
		_note("%s: чек" % players[seat].name)
	else:
		last_action[seat] = ("Ва-банк %d" if int(stacks[seat]) == 0 else "Колл %d") % bets[seat]
		_note("%s: колл %d" % [players[seat].name, need])
	_after_action(seat)
	return true


## Рейз (или ставка) до amount на этой улице. Меньше минимума можно только ва-банком.
func raise_to(seat: int, amount: int) -> bool:
	if phase != "hand" or seat != to_act or not can_raise(seat):
		return false
	var top := max_raise_to(seat)
	amount = mini(amount, top)
	if amount <= current_bet:
		return false
	if amount < current_bet + min_raise and amount < top:
		return false
	var increment := amount - current_bet
	_put(seat, amount - int(bets[seat]))
	if increment >= min_raise:
		min_raise = increment
		for other: int in players.size():
			acted[other] = false
			locked[other] = false
	else:
		# неполный ва-банк: кто уже ходил, может только уравнять или сбросить
		for other: int in players.size():
			if bool(acted[other]):
				locked[other] = true
	var opened := current_bet == 0
	current_bet = amount
	acted[seat] = true
	var verb := "Ставка" if opened else "Рейз до"
	last_action[seat] = "Ва-банк %d" % amount if int(stacks[seat]) == 0 else "%s %d" % [verb, amount]
	_note("%s: %s" % [players[seat].name, str(last_action[seat]).to_lower()])
	_after_action(seat)
	return true


func all_in_action(seat: int) -> bool:
	if phase != "hand" or seat != to_act:
		return false
	if can_raise(seat) and max_raise_to(seat) > current_bet:
		return raise_to(seat, max_raise_to(seat))
	return check_call(seat)


func _after_action(seat: int) -> void:
	revision += 1
	var alive := []
	for other: int in players.size():
		if in_hand(other):
			alive.append(other)
	if alive.size() == 1:
		_award_uncontested(alive[0])
		return
	to_act = _next_to_act(seat)
	time_left = TURN_TIME
	_bot_wait = _bot_delay()
	if to_act < 0:
		_finish_street()


func _finish_street() -> void:
	for seat: int in players.size():
		bets[seat] = 0
		acted[seat] = false
		locked[seat] = false
	current_bet = 0
	min_raise = BB
	var index := STREETS.find(street)
	if index >= 3:
		_showdown()
		return
	street = STREETS[index + 1]
	var amount := 3 if street == "flop" else 1
	for _i: int in amount:
		board.append(deck.pop_back())
	var cards := PackedStringArray()
	for card: int in board:
		cards.append(card_name(card))
	_note("%s: %s" % [{"flop": "Флоп", "turn": "Тёрн", "river": "Ривер"}[street], " ".join(cards)])
	for seat: int in players.size():
		if in_hand(seat) and not all_in(seat):
			last_action[seat] = ""
	to_act = _next_to_act(button)
	time_left = TURN_TIME
	_bot_wait = _bot_delay()
	revision += 1
	if to_act < 0:
		_finish_street()  # все в ва-банке — докладываем стол до ривера


func _award_uncontested(seat: int) -> void:
	var amount := pot()
	stacks[seat] = int(stacks[seat]) + amount
	result = {"pots": [{"amount": amount, "winners": [seat]}], "hands": {}, "fold_win": true}
	last_action[seat] = "Забирает %d" % amount
	_note("%s забирает банк %d" % [players[seat].name, amount])
	_close_hand(FOLD_SHOW_TIME)


func _showdown() -> void:
	var hands := {}
	var evals := {}
	for seat: int in players.size():
		if in_hand(seat):
			var best: Dictionary = TGPoker.evaluate(hole[seat] + board)
			evals[seat] = best
			hands[seat] = str(best.get("name", ""))
	var pots := side_pots()
	var shown := []
	for p: Dictionary in pots:
		var best_seats := []
		var best_eval: Dictionary = {}
		for seat: int in p.eligible:
			var e: Dictionary = evals[seat]
			var cmp := 1 if best_eval.is_empty() else TGPoker.compare(e, best_eval)
			if cmp > 0:
				best_eval = e
				best_seats = [seat]
			elif cmp == 0:
				best_seats.append(seat)
		# лишняя фишка — первому победителю слева от кнопки
		best_seats.sort_custom(func(a: int, b: int) -> bool:
			return (a - button - 1 + players.size()) % players.size() < (b - button - 1 + players.size()) % players.size())
		var share := int(p.amount) / best_seats.size()
		var odd := int(p.amount) % best_seats.size()
		for k: int in best_seats.size():
			stacks[best_seats[k]] = int(stacks[best_seats[k]]) + share + (1 if k < odd else 0)
		shown.append({"amount": p.amount, "winners": best_seats})
		var names := PackedStringArray()
		for seat: int in best_seats:
			names.append(str(players[seat].name))
		var pot_name := "Банк" if shown.size() == 1 else "Побочный банк"
		_note("%s %d: %s (%s)" % [pot_name, int(p.amount), ", ".join(names), hands[best_seats[0]]])
	for seat: int in players.size():
		if in_hand(seat):
			var won := 0
			for p: Dictionary in shown:
				if p.winners.has(seat):
					won += int(p.amount) / p.winners.size()
			last_action[seat] = ("Выиграл · " if won > 0 else "") + str(hands[seat])
	result = {"pots": shown, "hands": hands, "fold_win": false}
	_close_hand(SHOW_TIME)


## Банк и побочные банки по вкладам: [{amount, eligible}].
func side_pots() -> Array:
	var levels := []
	for seat: int in players.size():
		if int(totals[seat]) > 0 and in_hand(seat) and not levels.has(int(totals[seat])):
			levels.append(int(totals[seat]))
	levels.sort()
	var pots := []
	var previous := 0
	for level: int in levels:
		var amount := 0
		var eligible := []
		for seat: int in players.size():
			amount += clampi(int(totals[seat]), previous, level) - previous
			if in_hand(seat) and int(totals[seat]) >= level:
				eligible.append(seat)
		if amount > 0:
			if not pots.is_empty() and pots[-1].eligible == eligible:
				pots[-1].amount += amount
			else:
				pots.append({"amount": amount, "eligible": eligible})
		previous = level
	# вклады выше последнего уровня (сбросившие, переставившие) — в последний банк
	var rest := 0
	for seat: int in players.size():
		rest += maxi(0, int(totals[seat]) - previous)
	if rest > 0 and not pots.is_empty():
		pots[-1].amount += rest
	return pots


func _close_hand(show_time: float) -> void:
	phase = "showdown"
	to_act = -1
	# банк уже роздан — вклады обнуляем (сам банк для показа — в result)
	for seat: int in players.size():
		bets[seat] = 0
		totals[seat] = 0
	time_left = show_time
	for seat: int in players.size():
		if int(hand_start_stacks[seat]) > 0 and int(stacks[seat]) == 0:
			bust_order.append([seat, hand_no, int(hand_start_stacks[seat])])
			_note("%s без фишек" % players[seat].name)
	revision += 1


## После показа: следующая раздача, итоги сессии или ожидание.
func _after_showdown() -> void:
	if mode == "sport" and (hand_no >= SESSION_HANDS or active_seats().size() < 2):
		_end_session()
		return
	if mode == "classic":
		bust_order.clear()  # порядок вылета нужен только для мест спортивной сессии
		for seat: int in players.size():
			if int(stacks[seat]) == 0 and bool(players[seat].get("bot", false)):
				_rebuy(seat)
	_start_hand()


## Места сессии: живые по стеку, вылетевшие — ниже, по порядку вылета. Возвращает [{seat, place, points}].
func session_places() -> Array:
	var order := []
	for seat: int in players.size():
		var busted := -1
		for k: int in bust_order.size():
			if int(bust_order[k][0]) == seat:
				busted = k
		if busted < 0:
			order.append({"seat": seat, "key": [1, int(stacks[seat]), 0]})
		else:
			var entry: Array = bust_order[busted]
			order.append({"seat": seat, "key": [0, int(entry[1]), int(entry[2])]})
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		for i: int in 3:
			if a.key[i] != b.key[i]:
				return a.key[i] > b.key[i]
		return false)
	var out := []
	var count := players.size()
	for i: int in order.size():
		var place := i + 1
		if i > 0 and order[i].key == order[i - 1].key:
			place = int(out[i - 1].place)  # равный итог — общее место
		out.append({"seat": order[i].seat, "place": place, "points": place_points(place, count)})
	return out


func _end_session() -> void:
	places = session_places()
	for entry: Dictionary in places:
		scores[entry.seat] = int(scores[entry.seat]) + int(entry.points)
	_note("Итоги сессии %d" % session_no)
	var best := 0
	for seat: int in players.size():
		best = maxi(best, int(scores[seat]))
	if best >= target():
		winners.clear()
		for seat: int in players.size():
			if int(scores[seat]) == best:
				winners.append(seat)
		phase = "game_over"
		to_act = -1
	else:
		phase = "session_end"
		time_left = SESSION_TIME
	revision += 1


func _next_session() -> void:
	session_no += 1
	hand_no = 0
	bust_order.clear()
	stacks = _filled(START)
	_start_hand()


func _rebuy(seat: int) -> bool:
	if mode != "classic" or int(stacks[seat]) > 0 or (phase == "hand" and not hole[seat].is_empty() and not bool(folded[seat])):
		return false
	stacks[seat] = START
	rebuys[seat] = int(rebuys[seat]) + 1
	_note("%s садится заново со 100 BB" % players[seat].name)
	revision += 1
	if phase == "waiting":
		_start_hand()
	return true


## Итог классики: стек минус всё, что за него внесено.
func profit(seat: int) -> int:
	return int(stacks[seat]) - START * (1 + int(rebuys[seat]))


func _finish_classic() -> void:
	var best: int = -1000000000
	for seat: int in players.size():
		best = maxi(best, profit(seat))
	winners.clear()
	for seat: int in players.size():
		if profit(seat) == best:
			winners.append(seat)
	phase = "game_over"
	to_act = -1
	_note("Игра завершена")
	revision += 1


func _note(text: String) -> void:
	log.append(text)
	if log.size() > 60:
		log.pop_front()


func _bot_delay() -> float:
	return rng.randf_range(0.9, 2.0)


## Шаг времени на хосте: таймер хода, ходы ботов, пауза вскрытия. true — состояние изменилось.
func tick(delta: float) -> bool:
	match phase:
		"hand":
			if to_act < 0:
				return false
			if bool(players[to_act].get("bot", false)):
				_bot_wait -= delta
				if _bot_wait <= 0.0:
					_bot_move(to_act)
					return true
				return false
			time_left -= delta
			if time_left <= 0.0:
				var seat := to_act
				if to_call(seat) == 0:
					check_call(seat)
				else:
					fold(seat)
				return true
		"showdown":
			time_left -= delta
			if time_left <= 0.0:
				_after_showdown()
				return true
		"session_end":
			time_left -= delta
			if time_left <= 0.0:
				_next_session()
				return true
	return false


func _bot_move(seat: int) -> void:
	var move: Dictionary = Bot.decide(self, seat, rng)
	match str(move.get("kind", "fold")):
		"raise":
			if not raise_to(seat, int(move.get("amount", 0))):
				check_call(seat)
		"call":
			check_call(seat)
		_:
			if to_call(seat) == 0:
				check_call(seat)
			else:
				fold(seat)


## Действие игрока. host_authorized — от хоста (завершить игру, следующая сессия).
func action(seat: int, kind: String, payload: Variant, host_authorized: bool = false) -> bool:
	var data: Dictionary = payload if payload is Dictionary else {}
	match kind:
		"fold":
			return fold(seat)
		"call":
			return check_call(seat)
		"raise":
			return raise_to(seat, int(data.get("amount", 0)))
		"allin":
			return all_in_action(seat)
		"rebuy":
			return _rebuy(seat)
		"next":
			if host_authorized and phase == "session_end":
				_next_session()
				return true
			if host_authorized and phase == "showdown":
				_after_showdown()
				return true
		"finish":
			if host_authorized and mode == "classic" and phase != "game_over":
				_finish_classic()
				return true
	return false


static func card_name(id: int) -> String:
	const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "В", "Д", "К", "Т"]
	const SUITS := ["♣", "♠", "♦", "♥"]
	return RANKS[id % 13] + SUITS[int(id / 13)]


## Вид для места seat: свои карты, чужие — только на вскрытии.
func get_view(seat: int) -> Dictionary:
	var shown_holes := []
	for other: int in players.size():
		var visible: bool = other == seat or (phase == "showdown" and result.has("hands") and result.hands.has(other))
		shown_holes.append(hole[other].duplicate() if visible else ([-1, -1] if not hole[other].is_empty() and in_hand(other) else []))
	var me := {}
	if seat >= 0 and seat < players.size():
		me = {
			"to_call": to_call(seat) if phase == "hand" else 0,
			"min_raise_to": min_raise_to(seat) if phase == "hand" else 0,
			"max_raise_to": max_raise_to(seat) if phase == "hand" else 0,
			"can_raise": can_raise(seat) if phase == "hand" else false,
			"can_rebuy": mode == "classic" and int(stacks[seat]) == 0 and phase != "game_over",
			"hand_name": str(TGPoker.evaluate(hole[seat] + board).get("name", "")) if hole[seat].size() == 2 and board.size() >= 3 else "",
		}
	var profits := []
	for other: int in players.size():
		profits.append(profit(other))
	return {
		"players": players.duplicate(true), "you": seat, "mode": mode, "phase": phase, "street": street,
		"stacks": stacks.duplicate(), "bets": bets.duplicate(), "totals": totals.duplicate(), "folded": folded.duplicate(),
		"hole": shown_holes, "board": board.duplicate(), "pot": pot(), "button": button, "sb": sb_seat, "bb": bb_seat,
		"to_act": to_act, "current_bet": current_bet, "last_action": last_action.duplicate(), "me": me,
		"hand_no": hand_no, "session_hands": SESSION_HANDS, "session_no": session_no, "scores": scores.duplicate(),
		"target": target(), "places": places.duplicate(true), "rebuys": rebuys.duplicate(), "profits": profits,
		"result": result.duplicate(true), "winners": winners.duplicate(), "log": log.duplicate(),
		"time_left": time_left, "turn_time": TURN_TIME, "big_blind": BB, "revision": revision,
	}
