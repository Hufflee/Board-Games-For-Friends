class_name PerudoRules
extends RefCounted
## Движок правил «Перудо». Хост вызывает действия, клиенты получают get_view() — чужие кости скрыты до вскрытия.
##
## Фазы: roll (все трясут стаканы) → bid (ставки по кругу) → reveal (вскрытие) → roll … → game_over

const FACES := 6

var players: Array = []  # [{name, bot, steam_id}]
var dice: Array = []  # по местам: Array[int] значений костей
var counts: Array[int] = []  # сколько костей у игрока
var shaken: Array[bool] = []  # потряс ли стакан в этом раунде
var phase := "setup"
var turn := -1  # чей ход в фазе bid
var bid := {}  # текущая ставка {q, face, seat}
var bids: Array = []  # ставки раунда
var maputo := false
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
	maputo_enabled = maputo_on
	history = []
	log = []
	round_no = 0
	winner = -1
	starter = rng.randi_range(0, n - 1)
	start_round()


func start_round() -> void:
	round_no += 1
	bid = {}
	bids = []
	maputo = false
	reveal = {}
	for s in player_count():
		dice[s] = []
		for i in counts[s]:
			dice[s].append(rng.randi_range(1, FACES))
		dice[s].sort()
		shaken[s] = not alive(s)
	if not alive(starter):
		starter = _next_alive(starter)
	turn = starter
	phase = "roll"


## Игрок потряс стакан (кости уже брошены хостом — это для анимации и порядка).
func shake(seat: int) -> bool:
	if phase != "roll" or shaken[seat]:
		return false
	shaken[seat] = true
	_log(seat, "трясёт стакан")
	if not shaken.has(false):
		phase = "bid"
	return true


## Может ли начинающий раунд объявить Мапуто.
func can_maputo(seat: int) -> bool:
	return maputo_enabled and phase == "bid" and bid.is_empty() and seat == turn and counts[seat] == 1 and _alive_count() > 2


## Допустима ли ставка q костей номинала face сейчас.
func can_bid(q: int, face: int, _declare_maputo: bool = false) -> bool:
	if phase != "bid":
		return false
	return check_bid(bid, bids, maputo, total_dice(), q, face)


## Та же проверка по данным из get_view() — для интерфейса клиента.
static func check_bid(bid: Dictionary, bids: Array, maputo: bool, total: int, q: int, face: int) -> bool:
	if face < 1 or face > FACES or q < 1 or q > total:
		return false
	if bid.is_empty():
		return true
	var pq: int = bid["q"]
	var pf: int = bid["face"]
	if maputo:
		return face == pf and q > pq
	if pf == 1 and face == 1:
		return q > pq
	if face == 1:
		return q >= ceili(pq / 2.0)  # переход на единицы: можно вдвое меньше
	if pf == 1:
		# с единиц на другой номинал: не меньше удвоенного и выше последней ставки «не на единицы»
		if q < pq * 2:
			return false
		var last := {}
		for i in range(bids.size() - 1, -1, -1):
			if bids[i]["face"] != 1:
				last = bids[i]
				break
		if last.is_empty():
			return true
		return q > last["q"] or (q == last["q"] and face > last["face"])
	return q > pq or (q == pq and face > pf)


## Наименьшее допустимое количество для номинала (или -1, если номинал сейчас недоступен).
func min_quantity(face: int) -> int:
	for q in range(1, total_dice() + 1):
		if can_bid(q, face):
			return q
	return -1


func place_bid(seat: int, q: int, face: int, declare_maputo: bool = false) -> bool:
	if seat != turn or not can_bid(q, face):
		return false
	if declare_maputo:
		if not can_maputo(seat):
			return false
		maputo = true
	bid = {"q": q, "face": face, "seat": seat}
	bids.append(bid.duplicate())
	_log(seat, "ставка: %d × %s%s" % [q, "★" if face == 1 else str(face), " (мапуто!)" if declare_maputo else ""])
	turn = _next_alive(seat)
	return true


## «Дудо!» (не верю) — вскрытие: меньше костей, чем в ставке, — кость теряет поставивший, иначе — сказавший «Дудо».
func challenge(seat: int) -> bool:
	return _reveal_bid(seat, false)


## «Калзак!» — ставка верна ровно. Угадал — возвращает себе кость (не больше, чем было на старте), нет — теряет кость.
func calza(seat: int) -> bool:
	if not bid.is_empty() and bid["seat"] == seat:
		return false
	return _reveal_bid(seat, true)


func _reveal_bid(seat: int, is_calza: bool) -> bool:
	if phase != "bid" or seat != turn or bid.is_empty():
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
	for i in range(1, n + 1):
		var s := (seat + i) % n
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
		"players": players.duplicate(true),
		"counts": counts.duplicate(),
		"dice": shown,
		"shaken": shaken.duplicate(),
		"phase": phase,
		"turn": turn,
		"bid": bid.duplicate(),
		"bids": bids.duplicate(true),
		"maputo": maputo,
		"can_maputo": can_maputo(seat) if seat >= 0 else false,
		"total": total_dice(),
		"round_no": round_no,
		"reveal": reveal.duplicate(true),
		"history": history.duplicate(true),
		"log": log.duplicate(true),
		"winner": winner,
	}
