class_name PerudoRules
extends RefCounted
## Движок правил «Перудо». Хост вызывает действия, клиенты получают get_view() — чужие кости скрыты до вскрытия.
##
## Фазы: roll (все трясут стаканы) → bid (ставки по кругу) → reveal (вскрытие) → roll … → game_over

const FACES := 6

var players: Array = []  # [{name, bot, steam_id}]
var dice: Array = []  # по местам: Array[int] значений костей
var counts: Array[int] = []  # сколько костей у игрока
var order: Array[int] = []  # порядок за столом по часовой (по нему и ходят)
var shaken: Array[bool] = []  # потряс ли стакан в этом раунде
var shaking: Array[bool] = []  # трясёт прямо сейчас (держит стакан) — другие видят, как стакан ходит ходуном
var phase := "setup"
var turn := -1  # чей ход в фазе bid
var bid := {}  # текущая ставка {q, face, seat}
var bids: Array = []  # ставки раунда
var maputo := false  # идёт раунд Палифико
var pal_next := -1  # у кого только что осталась одна кость — следующий раунд Палифико
var maputo_enabled := true
var dice_at_start := 5
var round_no := 0
var starter := 0  # кто начинает раунд
var reveal := {}  # итог вскрытия
var history: Array = []  # итоги всех раундов
var log: Array = []  # журнал действий: [{seat, text}] — кто что нажимал
var winner := -1
var rng := RandomNumberGenerator.new()


func player_count() -> int:
	return players.size()


func player_name(seat: int) -> String:
	return players[seat]["name"]


## Выбыл (костей не осталось) — наблюдает; сеть не ждёт от него «Дальше» (Net._seat_out).
func is_out(seat: int) -> bool:
	return not alive(seat)


func alive(seat: int) -> bool:
	return counts[seat] > 0


func total_dice() -> int:
	var t := 0
	for c in counts:
		t += c
	return t


func new_game(player_list: Array, start_dice: int = 5, maputo_on: bool = true, seed_value: int = 0) -> void:
	players = player_list.duplicate(true)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var n := players.size()
	counts.resize(n)
	dice_at_start = clampi(start_dice, 1, 6)
	counts.fill(dice_at_start)
	dice = []
	for s in n:
		dice.append([])
	shaken.resize(n)
	shaking.resize(n)
	maputo_enabled = maputo_on
	history = []
	log = []
	round_no = 0
	pal_next = -1
	winner = -1
	starter = rng.randi_range(0, n - 1)
	order = []
	for k in n:
		order.append(k)
	phase = "seating"  # сначала рассадка: хост может перемешать игроков, потом begin()


## Рассадка: перемешать порядок за столом (только до первого раунда).
func shuffle_order() -> bool:
	if phase != "seating":
		return false
	var before := order.duplicate()
	while order == before and order.size() > 1:
		for i in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t := order[i]
			order[i] = order[j]
			order[j] = t
	_log(-1, "Игроков пересадили: " + ", ".join(order.map(func(s): return player_name(s))))
	return true


## Рассадка закончена — первый раунд.
func begin() -> bool:
	if phase != "seating":
		return false
	start_round()
	return true


func start_round() -> void:
	round_no += 1
	bid = {}
	bids = []
	# Палифико наступает само: в раунде после того, как у игрока осталась последняя кость
	# (снова — если он вернул кость «Калзаком» и опять опустился до одной)
	maputo = pal_next >= 0 and alive(pal_next)
	if maputo:
		_log(pal_next, "Палифико! У игрока последняя кость: единицы не джокеры, номинал не меняется")
	pal_next = -1
	reveal = {}
	for s in player_count():
		dice[s] = []
		for i in counts[s]:
			dice[s].append(rng.randi_range(1, FACES))
		dice[s].sort()
		shaken[s] = not alive(s)
		shaking[s] = false
	if not alive(starter):
		starter = _next_alive(starter)
	turn = starter
	phase = "roll"


## Игрок потряс стакан (кости уже брошены хостом — это для анимации и порядка).
func shake(seat: int) -> bool:
	if phase != "roll" or shaken[seat]:
		return false
	shaken[seat] = true
	shaking[seat] = false
	_log(seat, "трясёт стакан")
	if not shaken.has(false):
		phase = "bid"
	return true


## Игрок взял стакан и трясёт (on) или отпустил — только до броска, только для анимации у остальных.
func set_shaking(seat: int, on: bool) -> bool:
	if phase != "roll" or seat < 0 or seat >= shaking.size() or shaken[seat] or shaking[seat] == on:
		return false
	shaking[seat] = on
	return true


## Палифико больше не объявляют — он наступает сам (pal_next). Оставлено для совместимости.
func can_maputo(_seat: int) -> bool:
	return false


## Допустима ли ставка q костей номинала face сейчас.
func can_bid(q: int, face: int, _declare_maputo: bool = false) -> bool:
	if phase != "bid":
		return false
	return check_bid(bid, bids, maputo, total_dice(), q, face)


## Та же проверка по данным из get_view() — для интерфейса клиента.
static func check_bid(bid: Dictionary, _bids: Array, maputo: bool, total: int, q: int, face: int) -> bool:
	if face < 1 or face > FACES or q < 1 or q > total:
		return false
	if bid.is_empty():
		return face != 1  # Первый номинал свободен, но единицы первым ходом запрещены.
	var pq: int = bid["q"]
	var pf: int = bid["face"]
	if maputo:
		return face == pf and q > pq
	if pf == 1 and face == 1:
		return q > pq
	if face == 1:
		return q >= ceili(pq / 2.0)  # переход на единицы: можно вдвое меньше
	if pf == 1:
		return q >= pq * 2 + 1

	# повышаешь номинал — количество то же; больше костей — номинал не выше прежнего
	if face > pf:
		return q == pq
	return q > pq


## Наименьшее допустимое количество для номинала (или -1, если номинал сейчас недоступен).
func min_quantity(face: int) -> int:
	for q in range(1, total_dice() + 1):
		if can_bid(q, face):
			return q
	return -1


func place_bid(seat: int, q: int, face: int, declare_maputo: bool = false) -> bool:
	if seat != turn or not can_bid(q, face):
		return false
	bid = {"q": q, "face": face, "seat": seat}
	bids.append(bid.duplicate())
	_log(seat, "ставка: %d × %s%s" % [q, "★" if face == 1 else str(face), ""])
	turn = _next_alive(seat)
	return true


## «Дудо!» (не верю) — вскрытие: меньше костей, чем в ставке, — кость теряет поставивший, иначе — сказавший «Дудо».
func challenge(seat: int) -> bool:
	return _reveal_bid(seat, false)


## «Калзак!» — ставка верна ровно. Угадал — возвращает себе кость (не больше, чем было на старте), нет — теряет кость.
func calza(seat: int) -> bool:
	if not can_calza(seat):
		return false
	return _reveal_bid(seat, true)


## «Калзак» доступен любому живому участнику, кроме автора текущей ставки.
func can_calza(seat: int) -> bool:
	return (
		phase == "bid" and not bid.is_empty() and seat >= 0 and seat < counts.size()
		and alive(seat) and int(bid["seat"]) != seat
	)


func _reveal_bid(seat: int, is_calza: bool) -> bool:
	if phase != "bid" or bid.is_empty() or seat < 0 or seat >= counts.size() or not alive(seat):
		return false
	if (is_calza and not can_calza(seat)) or (not is_calza and seat != turn):
		return false
	var face: int = bid["face"]
	var wild := face != 1 and not maputo
	var count := 0
	var matches := []  # по местам — индексы подходящих костей
	for s in player_count():
		var m := []
		for i in dice[s].size():
			var v: int = dice[s][i]
			if v == face or (wild and v == 1):
				m.append(i)
				count += 1
		matches.append(m)
	var bidder: int = bid["seat"]
	var loser: int = bidder if count < bid["q"] else seat
	var gained := -1
	if is_calza:
		loser = -1 if count == bid["q"] else seat
		if loser < 0 and counts[seat] < dice_at_start:
			gained = seat
	reveal = {
		"bid": bid.duplicate(),
		"challenger": seat,
		"bidder": bidder,
		"count": count,
		"wild": wild,
		"matches": matches,
		"dice": dice.duplicate(true),
		"loser": loser,
		"gained": gained,
		"calza": is_calza,
		"maputo": maputo,
	}
	_log(seat, "«Калзак!» (ровно)" if is_calza else "«Дудо!» (не верю)")
	var res := "Вскрытие: %d из %d — " % [count, bid["q"]]
	if is_calza:
		res += "%s угадал(а)%s" % [player_name(seat), ", +1 кость" if gained >= 0 else ""] if loser < 0 else "%s ошибся(лась), −1 кость" % player_name(seat)
	else:
		res += "%s теряет кость" % player_name(loser)
	_log(-1, res)
	if loser >= 0:
		counts[loser] -= 1
		if counts[loser] == 1 and maputo_enabled and _alive_count() > 2:
			pal_next = loser  # осталась последняя кость — следующий раунд (его он и начинает) — Палифико
	if gained >= 0:
		counts[gained] += 1
	reveal["eliminated"] = loser >= 0 and counts[loser] == 0
	history.append({"round": round_no, "bid": bid.duplicate(), "count": count, "loser": loser, "challenger": seat, "calza": is_calza})
	starter = loser if loser >= 0 else seat
	phase = "reveal"
	if _alive_count() <= 1:
		for s in player_count():
			if alive(s):
				winner = s
	return true


func _log(seat: int, text: String) -> void:
	log.append({"seat": seat, "round": round_no, "text": text})
	if log.size() > 80:
		log.pop_front()


## Хост вызывает, когда все посмотрели вскрытие.
func advance() -> void:
	if phase != "reveal":
		return
	if winner >= 0:
		phase = "game_over"
		return
	start_round()


func _next_alive(seat: int) -> int:
	var n := player_count()
	var k := order.find(seat)
	for i in range(1, n + 1):
		var s: int = order[(k + i) % n] if k >= 0 else (seat + i) % n
		if alive(s):
			return s
	return seat


func _alive_count() -> int:
	var c := 0
	for s in player_count():
		if alive(s):
			c += 1
	return c


## Состояние для игрока: свои кости видны всегда, чужие — только при вскрытии.
func get_view(seat: int) -> Dictionary:
	var shown := []
	for s in player_count():
		if s == seat or phase in ["reveal", "game_over"]:
			shown.append(dice[s].duplicate())
		else:
			shown.append([])
	return {
		"you": seat,
		"order": order.duplicate(),
		"players": players.duplicate(true),
		"counts": counts.duplicate(),
		"dice": shown,
		"shaken": shaken.duplicate(),
		"shaking": shaking.duplicate(),
		"phase": phase,
		"turn": turn,
		"bid": bid.duplicate(),
		"bids": bids.duplicate(true),
		"maputo": maputo,
		"can_maputo": can_maputo(seat) if seat >= 0 else false,
		"can_calza": can_calza(seat),
		"total": total_dice(),
		"round_no": round_no,
		"reveal": reveal.duplicate(true),
		"history": history.duplicate(true),
		"log": log.duplicate(true),
		"winner": winner,
	}
