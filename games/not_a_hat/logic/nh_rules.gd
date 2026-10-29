class_name NHRules
extends RefCounted
## Движок «Это не шляпа!». Игроки дарят друг другу подарки рубашкой вверх и называют их вслух —
## надо помнить, что у кого лежит, или блефовать.
##
## Карта: {g: номер подарка (NHData.GIFTS), dir: -1 влево / +1 вправо}.
## Перед каждым игроком — столбик карт рубашкой вверх: hands[s][0] — «старый» подарок (его и дарят),
## последний — «новый».
## Фазы: memorize (все смотрят на открытые подарки) → give (даритель называет подарок)
##   → respond (получатель: «Спасибо!» / «Это не …!») → [reveal — вскрытие] → give … → game_over

const MAX_PENALTY := 3

var players: Array = []
var hands: Array = []  # [[карта, …], …]
var penalties: Array = []  # [[номер подарка, …], …] — открытые штрафные карты
var shop: Array = []  # колода магазина; верхняя (последняя) лежит лицом вверх
var start_cards := 1
var phase := "setup"
var giver := 0
var receiver := -1
var card := {}  # подарок, который сейчас передают (или вскрыт)
var from_shop := false  # подарок только что взят из магазина (его видели все)
var claim := -1  # что назвал даритель
var reveal := {}  # {g, claim, loser, receiver, giver}
var turn_no := 0
var log: Array = []  # [{giver, receiver, claim, result}] — последние события
var rng := RandomNumberGenerator.new()
var stats_risks: Array = []


func new_game(player_list: Array, cards_each: int = 1, seed_value: int = 0) -> void:
	stats_risks.clear()
	players = player_list.duplicate(true)
	start_cards = clampi(cards_each, 1, 2)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_fill_shop()
	hands = []
	penalties = []
	for s in players.size():
		var h := []
		for k in start_cards:
			h.append(shop.pop_back())
		hands.append(h)
		penalties.append([])
	giver = rng.randi_range(0, players.size() - 1)
	log = []
	turn_no = 0
	phase = "memorize"


## Все запомнили свои стартовые подарки — первый игрок берёт подарок из магазина.
func start_play() -> void:
	if phase != "memorize":
		return
	_take_from_shop(giver)


func _fill_shop() -> void:
	shop = []
	for i in NHData.GIFTS.size():
		shop.append({"g": i, "dir": -1 if rng.randf() < 0.5 else 1})
	for i in range(shop.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = shop[i]
		shop[i] = shop[j]
		shop[j] = t


func _take_from_shop(s: int) -> void:
	if shop.is_empty():
		_fill_shop()  # магазин опустел — новая колода
	giver = s
	card = shop.pop_back()
	from_shop = true
	_begin_give()


func _begin_give() -> void:
	receiver = posmod(giver + int(card["dir"]), players.size())
	claim = -1
	turn_no += 1
	phase = "give"


## Даритель называет подарок.
func give(seat: int, gift: int) -> bool:
	if phase != "give" or seat != giver or gift < 0 or gift >= NHData.GIFTS.size():
		return false
	claim = gift
	phase = "respond"
	return true


## Получатель принимает («Спасибо!») или отказывается («Это не …!»).
func respond(seat: int, accept: bool) -> bool:
	if phase != "respond" or seat != receiver:
		return false
	if accept:
		stats_risks.append({"seat":giver,"error":false});stats_risks.append({"seat":receiver,"error":false})
		_log("accept")
		hands[receiver].append(card)  # новый подарок — сверху столбика
		# теперь он дарит свой «старый» подарок
		giver = receiver
		card = hands[giver].pop_front()
		from_shop = false
		_begin_give()
		return true
	var truth: bool = int(card["g"]) == claim
	var loser := receiver if truth else giver
	stats_risks.append({"seat":giver,"error":loser==giver});stats_risks.append({"seat":receiver,"error":loser==receiver})
	reveal = {"g": card["g"], "claim": claim, "loser": loser, "receiver": receiver, "giver": giver, "truth": truth}
	_log("truth" if truth else "lie")
	penalties[loser].append(card["g"])
	phase = "reveal"
	return true


## После вскрытия: проигравший берёт новый подарок из магазина и дарит его (или конец игры).
func advance() -> void:
	if phase != "reveal":
		return
	var loser: int = reveal["loser"]
	if penalties[loser].size() >= MAX_PENALTY:
		phase = "game_over"
		return
	_take_from_shop(loser)


func _log(result: String) -> void:
	log.append({"giver": giver, "receiver": receiver, "claim": claim, "result": result, "g": card.get("g", -1) if result != "accept" else -1})
	if log.size() > 12:
		log.pop_front()


func winners() -> Array:
	var best := 999
	for p in penalties:
		best = mini(best, p.size())
	var out := []
	for s in players.size():
		if penalties[s].size() == best:
			out.append(s)
	return out


## Ход за бота / задумавшегося: называет правду (хост знает карту) или изредка — случайный подарок.
func auto_give() -> void:
	if phase != "give":
		return
	var g: int = int(card["g"]) if rng.randf() < 0.85 else rng.randi_range(0, NHData.GIFTS.size() - 1)
	give(giver, g)


func auto_respond(timeout: bool) -> void:
	if phase != "respond":
		return
	var lie: bool = claim != int(card["g"])
	respond(receiver, timeout or not (lie and rng.randf() < 0.5))


func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var hv := []
	for s in hands.size():
		var col := []
		for c in hands[s]:
			# подарки на столе — рубашкой вверх: видна только стрелка (в памятке — лицом всем)
			col.append({"g": c["g"] if (phase in ["memorize", "game_over"] or show_all) else -1, "dir": c["dir"]})
		hv.append(col)
	var moving := {}
	if not card.is_empty():
		var open: bool = (from_shop and phase in ["give", "respond"]) or phase in ["reveal", "game_over"] or show_all
		moving = {"g": card["g"] if open else -1, "dir": card["dir"]}
	return {
		"you": seat,
		"players": players.duplicate(true),
		"hands": hv,
		"penalties": penalties.duplicate(true),
		"shop_top": int(shop[-1]["g"]) if not shop.is_empty() else -1,
		"shop_left": shop.size(),
		"phase": phase,
		"giver": giver,
		"receiver": receiver,
		"card": moving,
		"from_shop": from_shop,
		"claim": claim,
		"reveal": reveal.duplicate(),
		"turn_no": turn_no,
		"log": log.duplicate(true),
		"winners": winners() if phase == "game_over" else [],
		"max_penalty": MAX_PENALTY,
		"hotseat": show_all,
	}


# --- Новый игрок посреди партии ------------------------------------------------------

func can_add_player() -> bool:
	return phase != "game_over" and players.size() < 8


## Получает столбик подарков из магазина (их он ещё не видел — придётся блефовать).
func add_player(p: Dictionary) -> bool:
	if not can_add_player():
		return false
	players.append(p.duplicate())
	var h := []
	for k in start_cards:
		if shop.is_empty():
			_fill_shop()
		h.append(shop.pop_back())
	hands.append(h)
	penalties.append([])
	return true
