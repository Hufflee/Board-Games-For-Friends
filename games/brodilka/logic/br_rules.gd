## Правила «Большой бродилки» без UI (docs/TZ_brodilka.md). Хост вызывает действия, клиенты получают get_view(seat).
## Ход — очередь задач (_queue): бросок → движение → эффект клетки → пассивные карты → свободная фаза → конец.
## Если задаче нужен выбор игрока, ставится prompt {seat, kind, options, text}, очередь ждёт answer().
## Тесты: godot --headless --path . --script res://tests/test_brodilka.gd
class_name BRRules
extends RefCounted

const START_COINS := 0
const MAX_PLAYERS := 8
const LOG_MAX := 30

var players: Array = []  # [{name, bot}]
var pos: Array[int] = []
var coins: Array[int] = []
var shop: Array = []  # по местам: Array[int] индексов BRData.SHOP
var skip: Array[int] = []  # сколько ходов пропустить
var extra: Array[int] = []  # сколько доп. ходов подряд
var stuck: Array[bool] = []  # на «Жвачке»
var traps := {}  # клетка → место, чья монета-ловушка
var tadam: Array[int] = [-1, -1, -1]  # ряд Тадам (индексы BRData.TADAM)
var deck_gb: Array[int] = []
var deck_shop: Array[int] = []
var deck_tadam: Array[int] = []
var disc_gb: Array[int] = []
var disc_shop: Array[int] = []
var disc_tadam: Array[int] = []

var phase := "setup"  # roll / prompt / free / game_over
var turn := 0
var prompt := {}  # {seat, kind, options:Array, text}
var last_roll: Array[int] = []
var roll_no := 0  # номер броска: стол бросает кубик только на новый номер (а не на каждое обновление)
var stats_rolls: Array = []
var last_card := {}  # {deck: gb/tadam/shop, id, side, no} — для анимации
var teleport := {}  # последний переход: вход и выход для двухэтапной анимации
var teleport_no := 0
var card_no := 0  # номер вытянутой карты: стол показывает карту крупно только на новый номер
var used: Array[String] = []  # активные карты Лавки, сыгранные в этом ходу
var winner := -1
var log: Array = []
var rng := RandomNumberGenerator.new()

var _queue: Array = []
var _moved := false  # фишка текущего игрока пошла вперёд в свой ход
var _rolled := false  # бросок в этом ходу уже был
var _ending := false  # идут эффекты «в конце хода»


func new_game(player_list: Array, seed_value: int = 0, start_coins: int = START_COINS) -> void:
	stats_rolls.clear()
	players = player_list.duplicate(true)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var n := players.size()
	pos.clear(); coins.clear(); shop.clear(); skip.clear(); extra.clear(); stuck.clear()
	for i in n:
		pos.append(0)
		coins.append(start_coins + 10)  # клетка «Старт»: получи 10
		shop.append([])
		skip.append(0)
		extra.append(0)
		stuck.append(false)
	deck_gb.clear(); deck_shop.clear(); deck_tadam.clear()
	for i in BRData.GOODBAD.size():
		for c in BRData.GOODBAD_COPIES:
			deck_gb.append(i)
	for i in BRData.SHOP.size():
		for c in int(BRData.SHOP[i].get("copies", BRData.SHOP_COPIES)):
			deck_shop.append(i)
	for i in BRData.TADAM.size():
		deck_tadam.append(i)
	_shuffle(deck_gb); _shuffle(deck_shop); _shuffle(deck_tadam)
	tadam = [-1, -1, -1]
	teleport = {}
	teleport_no = 0
	traps.clear()
	log.clear()
	winner = -1
	turn = 0
	_start_turn()


func player_count() -> int:
	return players.size()


func is_bot(seat: int) -> bool:
	return players[seat].get("bot", false)


func name_of(seat: int) -> String:
	return str(players[seat].get("name", "Игрок %d" % (seat + 1)))


## Новый игрок посреди партии — фишка на старт.
func can_add_player() -> bool:
	return phase != "game_over" and players.size() < MAX_PLAYERS


func add_player(p: Dictionary) -> void:
	players.append(p)
	pos.append(0); coins.append(10); shop.append([]); skip.append(0); extra.append(0); stuck.append(false)
	_log(players.size() - 1, "присоединяется к игре")


# ---------- состояние поля ----------

## Единственный последний (меньше всех продвинулся); -1 — ничья.
func last_player() -> int:
	var best := -1
	var tie := false
	for s in player_count():
		if best < 0 or pos[s] < pos[best]:
			best = s; tie = false
		elif pos[s] == pos[best]:
			tie = true
	return -1 if tie or player_count() < 2 else best


## Ближайший игрок впереди (в пределах lim клеток); -1 — нет.
func ahead_of(seat: int, lim: int = 999) -> int:
	var best := -1
	for s in player_count():
		if s != seat and pos[s] > pos[seat] and pos[s] - pos[seat] <= lim and (best < 0 or pos[s] < pos[best]):
			best = s
	return best


func others(seat: int) -> Array[int]:
	var r: Array[int] = []
	for s in player_count():
		if s != seat:
			r.append(s)
	return r


func has_shop(seat: int, id: String) -> bool:
	return shop[seat].has(BRData.shop_index(id))


## Сколько карт Лавки можно держать (Рюкзак — 4).
func shop_max(seat: int) -> int:
	return BRData.SHOP_MAX + (1 if has_shop(seat, "backpack") else 0)


## Цена покупки в Лавке (Купон — 3).
func shop_price(seat: int) -> int:
	return 3 if has_shop(seat, "coupon") else BRData.SHOP_PRICE


## Одноразовая карта сработала — в сброс.
func _spend_card(seat: int, id: String) -> void:
	var i: int = shop[seat].find(BRData.shop_index(id))
	if i >= 0:
		disc_shop.append(shop[seat][i])
		shop[seat].remove_at(i)


## Чужая карта/эффект двигает назад — Якорь держит.
func _push_back(seat: int, n: int) -> void:
	if has_shop(seat, "anchor"):
		_log(seat, "якорь: не сдвинуть назад")
		return
	_move(seat, -absi(n))


## Чужая карта переносит игрока на клетку to: назад Якорь не пускает.
func _pull_to(seat: int, to: int) -> void:
	if to < pos[seat] and has_shop(seat, "anchor"):
		_log(seat, "якорь: не сдвинуть назад")
		return
	_set_pos(seat, to)


## Ближайший телепорт впереди (клетка) или -1.
static func tele_ahead(from: int) -> int:
	for c in range(from + 1, BRBoard.finish()):
		if str(BRBoard.cell(c).t).begins_with("tele_"):
			return c
	return -1


func dice_count(seat: int) -> String:
	if stuck[seat] or BRBoard.cell(pos[seat]).t == "finish":
		return "finish"
	return BRBoard.cell(pos[seat]).shade


# ---------- ход ----------

func _start_turn() -> void:
	phase = "roll"
	prompt = {}
	used.clear()
	_moved = false
	_rolled = false
	_ending = false
	last_roll.clear()
	if skip[turn] > 0:
		skip[turn] -= 1
		_log(turn, "пропускает ход")
		if has_shop(turn, "tent"):
			_gain(turn, 4)
			_log(turn, "палатка: +4 монеты")
		_end_turn()
		return
	if has_shop(turn, "piggy"):
		_gain(turn, 1)
	var last := last_player()
	if last == turn:
		for t in _tadam_when("start"):
			_tadam_fx(t, turn)
	_run()
	if phase == "roll" and (stuck[turn] or BRBoard.cell(pos[turn]).t == "finish") and coins[turn] >= 5:
		_ask(turn, "boost", ["Без доплаты", "+1 за 5 монет"] + (["+2 за 10 монет"] if coins[turn] >= 10 else []), "Финиш-сейф: доплатить к броску?")


## Бросок кубиков текущим игроком (фаза roll).
func roll(seat: int) -> bool:
	if not prompt.is_empty() and prompt.get("kind", "") == "card_die":
		return answer(seat, 0)
	if phase != "roll" or seat != turn:
		return false
	_do_roll(0)
	return true


func _do_roll(boost: int) -> void:
	_rolled = true
	var mode := dice_count(turn)
	var a := rng.randi_range(1, 6)
	var b := rng.randi_range(1, 6)
	if has_shop(turn, "boots"):
		if a == 1: a = 3
		if b == 1: b = 3
	var bonus := 1 if has_shop(turn, "magic_die") else 0
	if mode == "finish":
		_set_roll([a])
		var v := a + boost + bonus
		_log(turn, "бросает на финиш-сейфе: %d%s" % [a, (" +%d" % (boost + bonus)) if boost + bonus > 0 else ""])
		if v >= 6:
			_win(turn, "пересекает финиш!")
		else:
			_end_turn()
		return
	if mode == "light" and not has_shop(turn, "fan"):
		_set_roll([a])
	else:
		_set_roll([a, b])
	_log(turn, "бросает: %s" % " и ".join(PackedStringArray(last_roll.map(func(x): return str(x)))))
	for t in _tadam_when("roll"):
		var fx: String = BRData.TADAM[t].fx
		if fx == "six_skip" and last_roll.has(6):
			skip[turn] += 1
			_log(turn, "Тадам: выпала шестёрка — пропустит ход")
		elif fx == "double_extra" and last_roll.size() == 2 and a == b:
			extra[turn] += 1
			_log(turn, "Тадам: дубль — ходит ещё раз")
	# куда идти, игрок показывает сам — щелчком по клетке (на серой клетке и с веером — одну из двух)
	var choices: Array = [a + bonus, b + bonus] if mode == "grey" or (mode == "light" and has_shop(turn, "fan")) else [(a + b if mode == "black" else a) + bonus]
	if choices.size() == 2 and choices[0] == choices[1]:
		choices = [choices[0]]
	var cells := choices.map(func(n): return clampi(pos[turn] + int(n), 0, BRBoard.finish()))
	_ask(turn, "die", choices.map(func(n): return str(n)),
		("Выбери кубик: нажми на одну из клеток" + (" (веер)" if mode == "light" else "")) if choices.size() == 2 else "Нажми на клетку, куда пойдёт персонаж",
		{cells = cells})


## Обычное движение в свой ход: идём, эффект клетки, пассивные карты.
func _walk(steps: int) -> void:
	_moved = true
	_move(turn, steps, true)
	_queue.push_back({k = "cell", seat = turn})
	_queue.push_back({k = "stop", seat = turn})
	_queue.push_back({k = "free"})
	_run()


## Перемещение фишки. own — сам идёт вперёд в свой ход (обгон по Тадам). Жвачка держит намертво.
func _move(seat: int, steps: int, own: bool = false) -> void:
	if stuck[seat] or steps == 0:
		return
	var from: int = pos[seat]
	var to := clampi(from + steps, 0, BRBoard.finish())
	# жвачка: остановился ровно на ней — застрял
	pos[seat] = to
	if own and steps > 0 and has_shop(seat, "sandals"):
		for s in others(seat):
			if pos[s] > from and pos[s] < to:
				_gain(seat, 1)
				_log(seat, "сандалии: обогнал %s — +1" % name_of(s))
	if own and steps > 0:
		for t in _tadam_when("pass"):
			for s in others(seat):
				if pos[s] > from and pos[s] < to:
					_pay(s, seat, int(BRData.TADAM[t].get("n", 3)))
					_log(seat, "обгоняет %s и забирает монеты" % name_of(s))


func _teleport(seat: int, entry: int) -> void:
	var exit := BRBoard.tele_pair(entry)
	_set_pos(seat, exit)
	teleport_no += 1
	teleport = {"seat": seat, "entry": entry, "exit": pos[seat], "no": teleport_no}


func _set_pos(seat: int, to: int) -> void:
	if not stuck[seat]:
		pos[seat] = clampi(to, 0, BRBoard.finish())


func end_turn(seat: int) -> bool:
	if phase != "free" or seat != turn:
		return false
	_end_turn()
	return true


func _end_turn() -> void:
	if phase == "game_over":
		return
	if not _ending and _moved and last_player() == turn and not _tadam_when("end").is_empty():
		_ending = true
		phase = "resolve"
		for t in _tadam_when("end"):
			_tadam_fx(t, turn)
		_queue.push_back({k = "next"})
		_run()
		return
	_next_turn()


func _next_turn() -> void:
	if phase == "game_over":
		return
	_queue.clear()
	if extra[turn] > 0 and skip[turn] == 0:
		extra[turn] -= 1
	else:
		turn = (turn + 1) % player_count()
	_start_turn()


func _win(seat: int, why: String) -> void:
	winner = seat
	phase = "game_over"
	prompt = {}
	_queue.clear()
	_log(seat, "ПОБЕДА — " + why)


# ---------- очередь задач ----------

func _run() -> void:
	while not _queue.is_empty() and phase != "game_over" and prompt.is_empty():
		var task: Dictionary = _queue.pop_front()
		_task(task)
	if prompt.is_empty() and phase != "game_over" and _queue.is_empty():
		phase = "free" if _rolled else "roll"


## Новый бросок кубика (в ход или от клетки/карты): запомнить грани и номер броска.
func _set_roll(faces: Array, roller: int = -1) -> void:
	last_roll.assign(faces)
	stats_rolls.append({"seat":turn if roller<0 else roller,"faces":faces.duplicate()})
	roll_no += 1


func _ask(seat: int, kind: String, options: Array, text: String, data: Dictionary = {}) -> void:
	prompt = {seat = seat, kind = kind, options = options, text = text, data = data}
	phase = "prompt"


## Клетки, куда можно положить монету-ловушку: любые между стартом и финишем, где ловушки ещё нет.
func trap_cells() -> Array:
	var res := []
	for c in range(1, BRBoard.finish()):
		if not traps.has(c):
			res.append(c)
	return res


## Ответ на prompt: индекс варианта.
func answer(seat: int, choice: int) -> bool:
	if prompt.is_empty() or seat != prompt.seat or choice < 0 or choice >= prompt.options.size():
		return false
	var p := prompt
	prompt = {}
	phase = "resolve"
	_resolve(p, choice)
	if prompt.is_empty() and phase == "resolve":
		_run()
	return true


func _task(t: Dictionary) -> void:
	var s: int = t.get("seat", turn)
	match t.k:
		"cell":
			_cell_fx(s)
		"trap_pick":
			var cells := trap_cells()
			if cells.is_empty():
				return
			_ask(s, "trap", ["Перед соперником (случайно)"] + cells.map(func(c): return str(c)),
				"Монета-ловушка (осталось %d): щёлкни клетку на поле" % int(t.get("left", 1)), {cells = cells})
		"stop":
			_stop_fx(s)
		"free":
			pass
		"next":
			_next_turn()
		"gb":
			_gb_fx(s, int(t.card), bool(t.good))
		"draw_gb":
			_draw_gb(s, bool(t.good))
		"shop":
			_shop_offer(s, int(t.get("n", 2)), bool(t.get("free", false)))
		"tornado_ask":
			if has_shop(s, "umbrella"):
				_ask(s, "tornado", ["Лететь в смерч", "Остаться (зонтик)"], "Смерч! Зонтик держит — лететь?", {cell = t.cell, free = true})
			elif coins[s] >= 10:
				_ask(s, "tornado", ["Лететь в смерч", "Откупиться (10 монет)"], "Смерч! Откупиться за 10 монет?", {cell = t.cell})
			else:
				_set_pos(s, int(t.cell))
		"duel":
			_ask(s, "duel_target", _names(others(s)), "Схватка: выбери соперника", {seats = others(s)})
		"duel_with":
			_duel(s, int(t.other))


# ---------- клетки ----------

func _cell_fx(s: int) -> void:
	var i: int = pos[s]
	if traps.has(i):
		traps.erase(i)
		skip[s] += 1
		_log(s, "попадает в монету-ловушку: пропустит ход")
		return
	var c := BRBoard.cell(i)
	match c.t:
		"start":
			_gain(s, 10)
		"chest_good":
			if has_shop(s, "nose"):
				_gain(s, 3)
				_log(s, "нюх кладоискателя: +3")
			_draw_gb(s, true)
		"chest_bad":
			if has_shop(s, "lucky_coin"):
				var lc := rng.randi_range(1, 6)
				_set_roll([lc],s)
				if lc >= 5:
					_log(s, "счастливая монетка: %d — «Хорошо» вместо «Плохо»" % lc)
					_draw_gb(s, true)
					return
				_log(s, "счастливая монетка: %d — не повезло" % lc)
			_draw_gb(s, false)
		"shop":
			_shop_offer(s, 2, false)
		"tadam":
			_draw_tadam(s)
		"tele_y", "tele_g", "tele_p", "tele_b":
			_teleport(s, i)
			_log(s, "телепортируется")
		"lucky":
			_log(s, "удачный расклад!")
			_queue.push_front({k = "shop", seat = s, n = 1, free = true})
			_queue.push_front({k = "draw_gb", seat = s, good = true})
			_draw_tadam(s)
			for o in others(s):
				_queue.push_back({k = "draw_gb", seat = o, good = false})
		"tornado":
			_log(s, "вызывает смерч!")
			var tasks := []
			for o in others(s):
				tasks.append({k = "tornado_ask", seat = o, cell = i})
			_queue = tasks + _queue
		"tribute":
			for o in others(s):
				var d := rng.randi_range(1, 6)
				if has_shop(o, "gold_tooth"):
					d = mini(d, 2)
				_pay(o, s, d)
				_log(o, "платит дань %d" % d)
		"duel":
			_queue.push_front({k = "duel", seat = s})
		"bike":
			_log(s, "едет на велосипеде +10")
			_move(s, 10)
			_queue.push_front({k = "cell", seat = s})
		"mine":
			var d := rng.randi_range(1, 6)
			_set_roll([d],s)
			if d == 1 and not has_shop(s, "helmet"):
				skip[s] += 1
				_log(s, "шахта: 1 — пропустит ход")
			elif d == 6:
				_win(s, "нашёл сокровище в шахте!")
			else:
				_log(s, "шахта: %d — +10 монет" % d)
				_gain(s, 10)
		"nooo":
			var nn := 3 if has_shop(s, "charm") else 10
			_log(s, "Нееет! −%d монет%s" % [nn, " (оберег)" if nn == 3 else ""])
			_lose(s, nn)
		"luck_die":
			var sum := 0
			for k in 3:
				sum += rng.randi_range(1, 6)
			_log(s, "кубик удачи: +%d" % sum)
			_move(s, sum)
		"gum":
			stuck[s] = true
			_log(s, "прилипает к жвачке — теперь бросает на финиш")


## Пассивные карты при остановке (цвет клетки, «пустая», общая клетка).
func _stop_fx(s: int) -> void:
	var c := BRBoard.cell(pos[s])
	var when := "stop_red" if c.col == "red" else ("stop_green" if c.col == "green" else "")
	if when == "stop_red" and has_shop(s, "horseshoe"):
		if not _tadam_when(when).is_empty():
			_log(s, "подкова: красная клетка не страшна")
	elif when != "":
		for t in _tadam_when(when):
			_tadam_fx(t, s)
	if c.col == "red" and has_shop(s, "magnet"):
		_gain(s, 5)
		_log(s, "денежный магнит: +5")
	if c.col == "green" and has_shop(s, "clover"):
		_gain(s, 4)
		_log(s, "клевер: +4")
	if c.t == "empty" and has_shop(s, "walkway") and not used.has("walkway"):
		used.append("walkway")
		_log(s, "траволатор: +4 клетки")
		_move(s, 4)
	for t in _tadam_when("share"):
		for o in others(s):
			if pos[o] == pos[s]:
				_queue.push_front({k = "duel_with", seat = s, other = o})
				break


# ---------- карты ----------

func _draw(deck: Array[int], disc: Array[int]) -> int:
	if deck.is_empty():
		deck.append_array(disc)
		disc.clear()
		_shuffle(deck)
	return deck.pop_back() if not deck.is_empty() else -1


## Карту из колоды игрок тянет сам: сначала просьба «Потяни карту…» (кнопка или клик по колоде).
const DECK_NAMES := {"good": "«Хорошо»", "bad": "«Плохо»", "tadam": "«Тадам»", "shop": "Лавки Джо"}


func _ask_draw(s: int, what: String, data: Dictionary) -> void:
	data["what"] = what
	if what == "shop":
		_ask(s, "draw", ["Открыть"], "Открой карты Лавки Джо", data)
		return
	_ask(s, "draw", ["Тянуть карту"], "Потяни карту " + str(DECK_NAMES[what]), data)


func _draw_gb(s: int, good: bool, drawn: bool = false) -> void:
	if not drawn:
		_ask_draw(s, "good" if good else "bad", {good = good})
		return
	var card := _draw(deck_gb, disc_gb)
	if card < 0:
		return
	disc_gb.append(card)
	card_no += 1
	last_card = {deck = "gb", id = card, side = "good" if good else "bad", seat = s, no = card_no}
	var side: Dictionary = BRData.GOODBAD[card].good if good else BRData.GOODBAD[card].bad
	_log(s, "%s: %s" % ["Хорошо" if good else "Плохо", side.text])
	if not good and has_shop(s, "shield"):
		_spend_card(s, "shield")
		_log(s, "щит: «Плохо» не действует (щит сломан)")
		return
	_gb_fx(s, card, good)


func _gb_fx(s: int, card: int, good: bool) -> void:
	var side: Dictionary = BRData.GOODBAD[card].good if good else BRData.GOODBAD[card].bad
	var n := int(side.get("n", 0))
	match str(side.fx):
		"none":
			pass
		"gain":
			_gain(s, n)
		"lose":
			_lose(s, n)
		"move":
			_move(s, n)
		"move_gain":
			_move(s, n); _gain(s, n)
		"all_lose":
			for o in player_count():
				_lose(o, n)
		"others_gain":
			for o in others(s):
				_gain(o, n)
		"others_gain_move":
			for o in others(s):
				_gain(o, n); _move(o, n)
		"others_move":
			for o in others(s):
				_move(o, n)
		"take_all":
			for o in others(s):
				_pay(o, s, n)
		"die_lose_or_back", "die_coins_or_move", "die_back":
			_ask(s, "card_die", ["Бросить кубик"], "Схвати кубик мышью и брось: " + str(side.text), {fx = str(side.fx)})
		"back_to_red":
			var r := BRBoard.nearest(pos[s], "red", -1)
			_set_pos(s, r if r >= 0 else pos[s] - 3)
		"fwd_to_green":
			var g := BRBoard.nearest(pos[s], "green", 1)
			_set_pos(s, g if g >= 0 else pos[s] + 3)
		"lose_shop_or_red":
			if shop[s].is_empty():
				var r := BRBoard.nearest(pos[s], "red", -1)
				_set_pos(s, r if r >= 0 else pos[s] - 3)
			else:
				_ask(s, "discard", _shop_names(s), "Сбрось свою карту Лавки", {mode = "discard"})
		"shop_tax":
			var keep: Array = []
			for c in shop[s]:
				if coins[s] >= n:
					coins[s] -= n
					keep.append(c)
				else:
					disc_shop.append(c)
			shop[s] = keep
		"all_keep_one":
			for o in player_count():
				while shop[o].size() > 1:
					disc_shop.append(shop[o].pop_back())
		"free_shop":
			_shop_offer(s, 2, true)
		"steal_shop_ahead":
			var vic := []
			for o in others(s):
				if pos[o] > pos[s] and not shop[o].is_empty():
					vic.append(o)
			if not vic.is_empty():
				_ask(s, "steal", _names(vic), "У кого забрать карту Лавки?", {seats = vic})
		"burn_shop":
			var vic := []
			for o in others(s):
				if not shop[o].is_empty():
					vic.append(o)
			if not vic.is_empty():
				_ask(s, "burn", _names(vic), "Чью карту Лавки сбросить?", {seats = vic})
		"take_from", "give_to", "target_lose", "target_gain", "target_bad", "target_double", "both_skip", "target_push":
			if player_count() < 2:
				return
			_ask(s, "target", _names(others(s)), side.text, {seats = others(s), fx = side.fx, n = n})
		"pay_move":
			var opts := []
			for k in mini(coins[s], n if n < 99 else 20) + 1:
				opts.append(str(k))
			_ask(s, "pay", opts, side.text, {fx = "pay_move", mult = 2 if n == 5 else 1})
		"pay_push_all":
			var opts := []
			for k in mini(coins[s], 20) + 1:
				opts.append(str(k))
			_ask(s, "pay", opts, side.text, {fx = "pay_push_all"})
		"pay_extra_turn":
			if coins[s] >= 2:
				_ask(s, "yesno", ["Нет", "Да, сбросить 2"], side.text, {fx = "pay_extra_turn"})
		"coin_traps":
			var opts := []
			for k in mini(coins[s], 3) + 1:
				opts.append(str(k))
			_ask(s, "pay", opts, "Сколько монет-ловушек положить? Клетки выберешь на поле.", {fx = "coin_traps"})
		"two_bad":
			_queue.push_front({k = "draw_gb", seat = s, good = false})
			_queue.push_front({k = "draw_gb", seat = s, good = false})
		"gain_per_behind":
			for o in others(s):
				if pos[o] < pos[s]:
					_gain(s, 1)
		"back_per_ahead":
			for o in others(s):
				if pos[o] > pos[s]:
					_move(s, -1)


func _draw_tadam(s: int, drawn: bool = false) -> void:
	if not drawn:
		_ask_draw(s, "tadam", {})
		return
	var card := _draw(deck_tadam, disc_tadam)
	if card < 0:
		return
	if tadam[2] >= 0:
		disc_tadam.append(tadam[2])
	tadam = [card, tadam[0], tadam[1]]
	card_no += 1
	last_card = {deck = "tadam", id = card, seat = s, no = card_no}
	_log(s, "ТАДАМ: " + str(BRData.TADAM[card].text))


func _tadam_when(when: String) -> Array[int]:
	var r: Array[int] = []
	for t in tadam:
		if t >= 0 and BRData.TADAM[t].when == when:
			r.append(t)
	return r


func _tadam_fx(t: int, s: int) -> void:
	var c: Dictionary = BRData.TADAM[t]
	var n := int(c.get("n", 0))
	match str(c.fx):
		"draw_good":
			_queue.push_back({k = "draw_gb", seat = s, good = true})
		"draw_bad":
			_queue.push_back({k = "draw_gb", seat = s, good = false})
		"gain":
			_gain(s, n)
		"move":
			_move(s, n)
			_cell_fx(s)
		"die_gain":
			_gain(s, rng.randi_range(1, 6))
		"lose_or_back":
			_ask(s, "yesno", ["Потерять %d монеты" % n, "%d клетки назад" % n], c.text, {fx = "lose_or_back", n = n})
		"give_all":
			var amount := 4 if player_count() == 2 else n
			for o in others(s):
				_pay(s, o, amount)
		"extra_turn":
			extra[s] += 1
		"free_shop":
			if shop[s].size() < shop_max(s):
				var c2 := _draw(deck_shop, disc_shop)
				if c2 >= 0:
					shop[s].append(c2)
		"duel":
			pass  # обрабатывается в _stop_fx


# ---------- Лавка Джо ----------

func _shop_offer(s: int, n: int, free: bool, drawn: bool = false) -> void:
	if n == 2 and has_shop(s, "spyglass"):
		n = 3
	if not drawn:
		_ask_draw(s, "shop", {n = n, free = free})
		return
	var offer := []
	for k in n:
		var c := _draw(deck_shop, disc_shop)
		if c >= 0:
			offer.append(c)
	if offer.is_empty():
		return
	if not free and coins[s] < shop_price(s):
		disc_shop.append_array(offer)
		_log(s, "в Лавке Джо, но не хватает монет")
		return
	var opts := ["Ничего не брать"]
	for c in offer:
		opts.append(str(BRData.SHOP[c].name))
	_ask(s, "buy", opts, "Лавка Джо: возьми карту" + ("" if free else " за %d монет" % shop_price(s)), {offer = offer, free = free})


func _shop_names(s: int) -> Array:
	var r := []
	for c in shop[s]:
		r.append(str(BRData.SHOP[c].name))
	return r


## Активная карта Лавки в свободной фазе. target — место (для карт с выбором игрока).
## Карты без выбора (на себя или на всех вокруг) — SELF_CARDS; цели считает card_targets — её же зовёт стол.
const SELF_CARDS := ["rocket", "kite", "map", "trumpet", "pony", "balloon", "bribe", "potion", "jetpack", "dice_bag", "powder", "magnet_big", "pocket_tp", "solvent"]


## Кого можно выбрать целью (по позициям, «Жвачке», картам Лавки и монетам) — общее для правил и стола.
static func card_targets(seat: int, id: String, p: Array, st: Array, shops: Array, cn: Array) -> Array[int]:
	var r: Array[int] = []
	var n := p.size()
	var ahead := -1
	for o in n:
		if o != seat and int(p[o]) > int(p[seat]) and (ahead < 0 or int(p[o]) < int(p[ahead])):
			ahead = o
	for o in n:
		if o == seat:
			continue
		var d: int = int(p[o]) - int(p[seat])
		var ok := false
		match id:
			"voodoo", "grenade", "sling", "squid":
				ok = o == ahead and (id == "squid" or not st[o])
			"hook", "harpoon":
				ok = d > 0 and d <= 10 and not (id == "harpoon" and st[o])
			"fate":
				ok = not st[o]
			"swap":
				ok = d > 0 and d <= 6 and not st[o] and not st[seat]
			"lasso":
				ok = d < 0 and d >= -10 and not st[o]
			"fingers":
				ok = absi(d) <= 1 and int(cn[o]) > 0
			"idol":
				ok = true
			"rod":
				ok = d > 0 and d <= 5 and not (shops[o] as Array).is_empty()
			"powder":
				ok = absi(d) <= 3 and not st[o]
			"magnet_big":
				ok = absi(d) <= 5 and d != 0 and not st[o]
		if ok:
			r.append(o)
	return r


## Карту можно сыграть (без учёта цены и «раз за ход»).
static func card_usable(seat: int, id: String, p: Array, st: Array, shops: Array, cn: Array) -> bool:
	match id:
		"powder", "magnet_big":
			return not card_targets(seat, id, p, st, shops, cn).is_empty()
		"pocket_tp":
			return not st[seat] and tele_ahead(int(p[seat])) >= 0
		"solvent":
			return st[seat]
		"rocket", "kite", "pony", "balloon", "jetpack":
			return not st[seat]
	if id in SELF_CARDS:
		return true
	return not card_targets(seat, id, p, st, shops, cn).is_empty()


func can_use(seat: int, idx: int) -> bool:
	if phase != "free" or seat != turn or idx < 0 or idx >= shop[seat].size():
		return false
	var c: Dictionary = BRData.SHOP[shop[seat][idx]]
	if c.kind != "active" or used.has(c.id) or coins[seat] < int(c.cost):
		return false
	return card_usable(seat, c.id, pos, stuck, shop, coins)


func use_targets(seat: int, id: String) -> Array[int]:
	if id in SELF_CARDS:
		return []
	return card_targets(seat, id, pos, stuck, shop, coins)


func use_card(seat: int, idx: int, target: int = -1) -> bool:
	if not can_use(seat, idx):
		return false
	var c: Dictionary = BRData.SHOP[shop[seat][idx]]
	var id: String = c.id
	var self_card: bool = id in SELF_CARDS
	var tg := use_targets(seat, id)
	if not self_card and not tg.has(target):
		target = tg[0]
	coins[seat] -= int(c.cost)
	used.append(id)
	_log(seat, "играет «%s»%s" % [c.name, (" на " + name_of(target)) if not self_card else ""])
	match id:
		"voodoo", "idol":
			_queue.push_back({k = "draw_gb", seat = target, good = false})
		"hook":
			_set_pos(seat, pos[target])
		"harpoon":
			_pull_to(target, pos[seat])
		"grenade":
			_push_back(target, 6)
		"sling":
			_push_back(target, 3)
		"rocket":
			_move(seat, 5)
		"fate":
			_push_back(target, 1 if player_count() <= 3 else 2)
		"swap":
			if has_shop(target, "anchor"):
				_log(target, "якорь: не сдвинуть назад")
			else:
				var mine: int = pos[seat]
				pos[seat] = pos[target]
				pos[target] = mine
		"lasso":
			_set_pos(target, pos[seat])
		"kite":
			var g := BRBoard.nearest(pos[seat], "green", 1)
			_set_pos(seat, g if g >= 0 else pos[seat] + 3)
		"powder":
			for o in card_targets(seat, id, pos, stuck, shop, coins):
				_push_back(o, 4)
		"fingers":
			_pay(target, seat, 3)
		"map":
			_queue.push_back({k = "draw_gb", seat = seat, good = true})
		"trumpet":
			for o in others(seat):
				_lose(o, 2)
		"pony":
			_move(seat, 4)
		"balloon":
			_move(seat, 8)
		"squid":
			skip[target] += 1
		"bribe":
			_queue.push_back({k = "shop", seat = seat, n = 1, free = true})
		"rod":
			var stolen: int = shop[target].pop_back()
			shop[seat].append(stolen)
			_log(seat, "вылавливает «%s»" % BRData.SHOP[stolen].name)
			if shop[seat].size() > shop_max(seat):
				_ask(seat, "discard", _shop_names(seat), "У тебя больше %d карт — сбрось одну" % shop_max(seat), {mode = "discard"})
		"potion":
			extra[seat] += 1
		"jetpack":
			_move(seat, 6)  # карты Лавки и так не включают клетку — ранец просто дальше ракеты
		"pocket_tp":
			var tp := tele_ahead(pos[seat])
			_teleport(seat, tp)
			_log(seat, "телепортируется")
		"solvent":
			stuck[seat] = false
			pos[seat] = BRBoard.finish()
			_spend_card(seat, "solvent")
			_log(seat, "отлипает от жвачки и встаёт на финиш-сейф")
		"dice_bag":
			var dd := rng.randi_range(1, 6)
			_set_roll([dd],seat)
			_gain(seat, dd)
			_log(seat, "мешок кубиков: +%d" % dd)
		"magnet_big":
			for o in card_targets(seat, id, pos, stuck, shop, coins):
				_pull_to(o, pos[seat])
	if prompt.is_empty():
		phase = "resolve"
	_queue.push_back({k = "free"})
	_run()
	return true


# ---------- схватка ----------

func _duel(s: int, o: int) -> void:
	var a := rng.randi_range(1, 6) + 2 + (2 if has_shop(s, "glove") else 0)
	var b := rng.randi_range(1, 6) + (2 if has_shop(o, "glove") else 0)
	_log(s, "схватка с %s: %d против %d" % [name_of(o), a, b])
	var w := s if a > b else o
	if a == b:
		var es := has_shop(s, "elephant")
		var eo := has_shop(o, "elephant")
		if es == eo:
			return
		w = s if es else o
		_log(w, "слон в кармане: ничья — победа")
	var l := o if w == s else s
	var opts := ["Забрать 10 монет", "Отправить на 10 клеток назад"]
	if not shop[l].is_empty():
		opts.append("Забрать карту Лавки")
	_ask(w, "duel_prize", opts, "Ты победил в схватке! Что забрать у %s?" % name_of(l), {loser = l})


# ---------- ответы ----------

func _resolve(p: Dictionary, ch: int) -> void:
	var s: int = p.seat
	var d: Dictionary = p.get("data", {})
	match p.kind:
		"draw":
			match str(d.what):
				"good", "bad":
					_draw_gb(s, bool(d.good), true)
				"tadam":
					_draw_tadam(s, true)
				"shop":
					_shop_offer(s, int(d.n), bool(d.free), true)
		"boost":
			var add := ch
			_lose(s, [0, 5, 10][ch])
			phase = "roll"
			_do_roll(add)
		"card_die":
			var result := rng.randi_range(1, 6)
			_set_roll([result],s)
			_log(s, "бросает кубик для карты: %d" % result)
			match str(d.fx):
				"die_coins_or_move":
					if result <= 3: _gain(s, 10)
					else: _move(s, 5)
				"die_lose_or_back":
					if result <= 3: _lose(s, 5)
					else: _move(s, -10)
				"die_back": _move(s, -result)
		"die":
			_walk(int(p.options[ch]))
		"buy":
			var offer: Array = d.offer
			if ch == 0:
				disc_shop.append_array(offer)
				return
			var card: int = offer[ch - 1]
			offer.remove_at(ch - 1)
			disc_shop.append_array(offer)
			if not d.free:
				_lose(s, shop_price(s))
				for o in others(s):
					if has_shop(o, "parrot"):
						_gain(o, 1)
						_log(o, "попугай: +1")
			shop[s].append(card)
			_log(s, "берёт «%s»" % BRData.SHOP[card].name)
			if shop[s].size() > shop_max(s):
				_ask(s, "discard", _shop_names(s), "У тебя больше %d карт — сбрось одну" % shop_max(s), {mode = "discard"})
		"discard":
			disc_shop.append(shop[s][ch])
			shop[s].remove_at(ch)
		"steal", "burn":
			var v: int = d.seats[ch]
			var c: int = shop[v].pop_back()
			if p.kind == "steal" and shop[s].size() < shop_max(s):
				shop[s].append(c)
			else:
				disc_shop.append(c)
		"target":
			var o: int = d.seats[ch]
			var n: int = d.n
			match str(d.fx):
				"take_from": _pay(o, s, n)
				"give_to": _pay(s, o, n)
				"target_lose": _lose(o, n)
				"target_gain": _gain(o, n)
				"target_bad": _queue.push_front({k = "draw_gb", seat = o, good = false})
				"target_double": extra[o] += 1
				"target_push":
					var dd := rng.randi_range(1, 6)
					_set_roll([dd],s)
					_move(o, dd)
					_log(o, "сдвинут вперёд на %d" % dd)
				"both_skip":
					skip[s] += 1
					if player_count() > 2:
						skip[o] += 1
		"pay":
			var k := ch
			_lose(s, k)
			match str(d.fx):
				"pay_move": _move(s, k * int(d.get("mult", 1)))
				"pay_push_all":
					for o in others(s):
						_push_back(o, k)
				"coin_traps":
					# каждую монету игрок кладёт сам — щелчком по клетке поля
					for j in k:
						_queue.push_front({k = "trap_pick", seat = s, left = k - j})
		"yesno":
			match str(d.fx):
				"pay_extra_turn":
					if ch == 1:
						_lose(s, 2)
						extra[s] += 1
				"lose_or_back":
					if ch == 0: _lose(s, int(d.n))
					else: _move(s, -int(d.n))
		"trap":
			var cells: Array = d.cells
			var cell: int
			if ch == 0:
				var opp := others(s)
				var o: int = opp[rng.randi() % opp.size()] if not opp.is_empty() else s
				cell = clampi(pos[o] + rng.randi_range(3, 9), 1, BRBoard.finish() - 1)
			else:
				cell = int(cells[ch - 1])
			traps[cell] = s
			_log(s, "кладёт монету-ловушку на клетку %d" % cell)
		"tornado":
			if ch == 1:
				if not d.get("free", false):
					_lose(s, 10)
				_log(s, "остаётся под зонтиком" if d.get("free", false) else "откупается от смерча")
			else:
				_set_pos(s, int(d.cell))
		"duel_target":
			_duel(s, int(d.seats[ch]))
		"duel_prize":
			var l: int = d.loser
			match ch:
				0: _pay(l, s, 10)
				1: _push_back(l, 10)
				2:
					var c: int = shop[l].pop_back()
					if shop[s].size() < shop_max(s):
						shop[s].append(c)
					else:
						disc_shop.append(c)


# ---------- монеты ----------

func _gain(s: int, n: int) -> void:
	coins[s] += n


func _lose(s: int, n: int) -> int:
	var k := mini(n, coins[s])
	coins[s] -= k
	return k


func _pay(from: int, to: int, n: int) -> void:
	coins[to] += _lose(from, n)


# ---------- служебное ----------

func _names(seats: Array) -> Array:
	return seats.map(func(x): return name_of(x))


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _log(seat: int, text: String) -> void:
	log.append({seat = seat, text = text})
	if log.size() > LOG_MAX:
		log.pop_front()


func get_view(seat: int) -> Dictionary:
	var pl := []
	for s in player_count():
		pl.append({name = name_of(s), bot = is_bot(s), pos = pos[s], coins = coins[s], shop = shop[s].duplicate(),
			skip = skip[s], stuck = stuck[s]})
	return {
		game = "brodilka", seat = seat, players = pl, turn = turn, phase = phase, winner = winner,
		tadam = tadam.duplicate(), traps = traps.keys(), last_roll = last_roll.duplicate(), roll_no = roll_no, last_card = last_card.duplicate(),
		dice = "light" if prompt.get("kind", "") == "card_die" else (dice_count(turn) if phase != "game_over" else ""), teleport = teleport.duplicate(),
		prompt = prompt.duplicate(true),  # тайн в игре нет — выбор видят все, отвечает prompt.seat
		waiting = int(prompt.seat) if not prompt.is_empty() else -1,
		used = used.duplicate(), log = log.duplicate(true), clock = phase != "game_over",
		decks = [deck_gb.size(), deck_shop.size(), deck_tadam.size()],
	}
