class_name HCRules
extends RefCounted
## Движок правил «Оттенков и подсказок». Хост вызывает действия, клиенты получают get_view():
## карту и загаданный цвет видит только ведущий (до подсчёта).
##
## Фазы: pick (ведущий выбирает цвет) → cue1 (одно слово) → guess1 (по часовой) → cue2 (два слова или пас)
##       → guess2 (против часовой) → reveal → … → game_over

const MAX_TIEBREAK_ROUNDS := 8
## Кооператив вдвоём: ведущий и угадывающий меняются, очки обеих фишек — в общий счёт.
## 10 раундов, максимум 6 очков за раунд; цель 30 — в среднем по 3 за раунд (рамка вокруг цвета).
const COOP_ROUNDS := 10
const COOP_GOAL := 30

var players: Array = []  # [{name, ...}]
var scores: Array = []
var giver := -1
var first_giver := 0
var round_no := 0
var total_rounds := 0  # основных раундов (каждый ведущий 1 или 2 раза)
var tiebreak := false
var tiebreak_givers: Array = []  # в переигровке ведут те, кто не претендует на победу
var tiebreak_rounds := 0
var coop := false  # вдвоём — кооператив (COOP_GOAL)
var free_pick := false  # вариант для новичков: ведущий выбирает любую клетку
var card: Array = []  # 4 клетки карты
var target := -1
var cues: Array = []  # подсказки текущего раунда
var used_cues: Array = []  # все подсказки игры (повторять нельзя)
var history: Array = []  # [{giver, target, cues}]
var pieces: Array = []  # [{seat, cell, n}] — фишки на поле (n: первая или вторая догадка)
var order: Array = []  # очередь угадывающих в текущей фазе
var order_i := 0
var passed := false  # ведущий отказался от второй подсказки
var phase := "setup"
var result := {}
var winners: Array = []
var rng := RandomNumberGenerator.new()

static var _re: RegEx


## laps — сколько раз каждый будет ведущим (0 — по правилам: 3–6 игроков дважды, 7+ — один раз).
func new_game(player_list: Array, laps: int = 0, free: bool = false, seed_value: int = 0, coop_mode: bool = false) -> void:
	players = player_list.duplicate(true)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	if laps <= 0:
		laps = 2 if players.size() <= 6 else 1
	free_pick = free
	scores = []
	scores.resize(players.size())
	scores.fill(0)
	coop = coop_mode
	total_rounds = COOP_ROUNDS if coop else players.size() * laps
	first_giver = rng.randi_range(0, players.size() - 1)
	round_no = 0
	tiebreak = false
	tiebreak_givers = []
	tiebreak_rounds = 0
	used_cues = []
	history = []
	winners = []
	_start_round()


func _start_round() -> void:
	round_no += 1
	if tiebreak:
		giver = tiebreak_givers[tiebreak_rounds % tiebreak_givers.size()]
		tiebreak_rounds += 1
	else:
		giver = (first_giver + round_no - 1) % players.size()
	card = HCData.draw_card(rng)
	target = -1
	cues = []
	pieces = []
	order = []
	order_i = 0
	passed = false
	result = {}
	phase = "pick"


func pick_color(seat: int, cell: int) -> bool:
	if phase != "pick" or seat != giver:
		return false
	if not (free_pick and cell >= 0 and cell < HCData.COLS * HCData.ROWS) and not card.has(cell):
		return false
	target = cell
	phase = "cue1"
	return true


## Ошибка подсказки ("" — подсказка годится). Проверяется и у клиента, и на хосте.
static func check_cue(text: String, max_words: int, used: Array) -> String:
	var t := normalize(text)
	if t == "":
		return "Напишите подсказку."
	var words := t.split(" ", false)
	if words.size() > max_words:
		return "Нужно одно слово." if max_words == 1 else "Не больше двух слов."
	for ch in t:
		if ch >= "0" and ch <= "9":
			return "Без цифр и координат."
	if _re == null:
		_re = RegEx.new()
		_re.compile(HCData.FORBIDDEN_RE)
	for w in t.replace("-", " ").split(" ", false):
		if _re.search(w) != null or HCData.FORBIDDEN_EN.has(w):
			return "Нельзя называть базовые цвета: «%s»." % w
	if used.has(t):
		return "Эта подсказка уже звучала в игре."
	return ""


static func normalize(text: String) -> String:
	var t := text.strip_edges().to_lower()
	for ch in [".", ",", "!", "?", "«", "»", "\"", ";", ":"]:
		t = t.replace(ch, " ")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.strip_edges()


func give_cue(seat: int, text: String) -> bool:
	if seat != giver or not phase in ["cue1", "cue2"]:
		return false
	var max_words := 1 if phase == "cue1" else 2
	if check_cue(text, max_words, used_cues) != "":
		return false
	var t := normalize(text)
	cues.append(t)
	used_cues.append(t)
	order = _guess_order(phase == "cue2")
	order_i = 0
	phase = "guess1" if phase == "cue1" else "guess2"
	return true


func pass_cue(seat: int) -> bool:
	if seat != giver or phase != "cue2":
		return false
	passed = true
	_score()
	return true


## Порядок угадывающих: по часовой от ведущего, во второй раз — против часовой.
func _guess_order(reverse: bool) -> Array:
	var list := []
	for k in range(1, players.size()):
		list.append((giver + k) % players.size())
	if reverse:
		list.reverse()
	return list


func current_guesser() -> int:
	if not phase in ["guess1", "guess2"] or order_i >= order.size():
		return -1
	return order[order_i]


func occupied(cell: int) -> bool:
	for p in pieces:
		if p["cell"] == cell:
			return true
	return false


func place(seat: int, cell: int) -> bool:
	if seat != current_guesser() or cell < 0 or cell >= HCData.COLS * HCData.ROWS or occupied(cell):
		return false
	pieces.append({"seat": seat, "cell": cell, "n": 1 if phase == "guess1" else 2})
	_next_guesser()
	return true


## Пропустить ход игрока (вылетел из сети и т. п.).
func skip() -> bool:
	if current_guesser() < 0:
		return false
	_next_guesser()
	return true


func _next_guesser() -> void:
	order_i += 1
	if order_i < order.size():
		return
	if phase == "guess1":
		phase = "cue2"
	else:
		_score()


## Ведущий вылетел до подсказки — раунд без очков.
func skip_round() -> void:
	history.append({"giver": giver, "target": target, "cues": cues.duplicate()})
	var gained := []
	gained.resize(players.size())
	gained.fill(0)
	result = {"target": -1, "gained": gained, "giver_points": 0, "details": [], "passed": false, "skipped": true}
	phase = "reveal"


## Очки за фишку: 3 — точно, 2 — в рамке 3×3, 1 — вплотную к рамке.
static func points_for(target_cell: int, cell: int) -> int:
	var d := HCData.dist(target_cell, cell)
	return [3, 2, 1][d] if d <= 2 else 0


func _score() -> void:
	var gained := []
	gained.resize(players.size())
	gained.fill(0)
	var in_frame := 0
	var details := []
	for p in pieces:
		var pts := points_for(target, p["cell"])
		gained[p["seat"]] += pts
		if HCData.dist(target, p["cell"]) <= 1:
			in_frame += 1
		details.append({"seat": p["seat"], "cell": p["cell"], "pts": pts})
	var per_piece := 2 if players.size() == 3 else 1
	if coop:
		per_piece = 0  # в кооперативе всё идёт в общий счёт
	gained[giver] += in_frame * per_piece
	if coop:
		var team := 0
		for g in gained:
			team += int(g)
		for s in players.size():
			scores[s] += team  # у всех один общий счёт
	else:
		for s in players.size():
			scores[s] += gained[s]
	history.append({"giver": giver, "target": target, "cues": cues.duplicate()})
	result = {"target": target, "gained": gained, "giver_points": in_frame * per_piece, "details": details, "passed": passed}
	phase = "reveal"


func advance() -> void:
	if phase != "reveal":
		return
	if not tiebreak and round_no < total_rounds:
		_start_round()
		return
	if coop:
		winners = range(players.size()) if int(scores[0]) >= COOP_GOAL else []
		phase = "game_over"
		return
	var best: int = scores.max()
	var leaders := []
	for s in players.size():
		if scores[s] == best:
			leaders.append(s)
	if leaders.size() == 1 or tiebreak_rounds >= MAX_TIEBREAK_ROUNDS:
		winners = leaders
		phase = "game_over"
		return
	tiebreak_givers = []
	for s in players.size():
		if not leaders.has(s):
			tiebreak_givers.append(s)
	if tiebreak_givers.is_empty():
		winners = leaders  # все поровну — общая победа
		phase = "game_over"
		return
	tiebreak = true
	_start_round()


func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var secret := show_all or seat == giver
	return {
		"you": seat,
		"players": players.duplicate(true),
		"scores": scores.duplicate(),
		"giver": giver,
		"round_no": round_no,
		"total_rounds": total_rounds,
		"tiebreak": tiebreak,
		"free_pick": free_pick,
		"card": card.duplicate() if secret else [],
		"target": target if secret or phase in ["reveal", "game_over"] else -1,
		"cues": cues.duplicate(),
		"used_cues": used_cues.duplicate(),
		"history": history.duplicate(true),
		"pieces": pieces.duplicate(true),
		"order": order.duplicate(),
		"guesser": current_guesser(),
		"passed": passed,
		"phase": phase,
		"result": result.duplicate(true),
		"winners": winners.duplicate(),
		"hotseat": show_all,
		"coop": coop,
		"coop_goal": COOP_GOAL,
	}


# --- Новый игрок посреди партии ------------------------------------------------------

## Между раундами: новичок с нуля очков; партия удлиняется на его круги ведущего.
func can_add_player() -> bool:
	return phase == "reveal" and not tiebreak and not coop and players.size() < 10


func add_player(p: Dictionary) -> bool:
	if not can_add_player():
		return false
	var laps := maxi(1, total_rounds / maxi(1, players.size()))
	players.append(p.duplicate())
	scores.append(0)
	total_rounds += laps
	return true


## Зритель смотрит глазами рядового игрока — не ведущего (тот видит тайну).
func spectator_seat() -> int:
	for s in players.size():
		if s != giver:
			return s
	return 0
