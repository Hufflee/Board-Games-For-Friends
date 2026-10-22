class_name TTRules
extends RefCounted
## Движок «Тип Топ» (кооператив). Хост вызывает действия, клиенты получают get_view():
## свой номер видит только сам игрок, выложенные номера — все.
##
## Фазы: theme (капитан выбирает тему) → answer (все пишут ответы) → order (капитан выкладывает ответы)
##       → [guess — эксперт: команда угадывает номер капитана] → round_result → … → game_over

const MAX_ANSWER := 80

var players: Array = []
var adult := false
var expert := false
var unicorns := 0
var poops := 0
var round_no := 0
var captain := 0
var first_captain := 0
var _cap_queue: Array = []  # капитаны текущего круга (случайный порядок, без повторов)
var deck: Array = []
var card: Array = []  # две темы [вопрос, от, до]
var theme := -1
var numbers := {}  # место -> номер 1–10 (тайно)
var answers := {}  # место -> текст ответа
var placed: Array = []  # места в порядке выкладки
var log: Array = []  # [{seat, number, called, ok}] — ход выкладки
var arrangement: Array = []  # раскладка капитана на планшете (до «Ответить»), места слева направо
var calls := {}  # эксперт: место -> номер, который капитан назвал для ответа
var guess := -1  # эксперт: догадка команды о номере капитана
var phase := "setup"
var result := {}
var won := false
var rng := RandomNumberGenerator.new()


func new_game(player_list: Array, adult_deck: bool, expert_mode: bool, seed_value: int = 0) -> void:
	players = player_list.duplicate(true)
	adult = adult_deck
	expert = expert_mode
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	deck = TTData.deck(adult, rng).slice(0, TTData.ROUNDS)
	unicorns = mini(players.size(), 8)
	poops = 0
	round_no = 0
	first_captain = rng.randi_range(0, players.size() - 1)
	_cap_queue = []
	captain = -1
	won = false
	_start_round()


func _start_round() -> void:
	round_no += 1
	# капитан — случайно, но пока все не побывали капитаном, никто не повторяется
	if _cap_queue.is_empty():
		_cap_queue = range(players.size())
		for i in range(_cap_queue.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = _cap_queue[i]
			_cap_queue[i] = _cap_queue[j]
			_cap_queue[j] = tmp
		if _cap_queue.size() > 1 and _cap_queue[0] == captain:
			_cap_queue.push_back(_cap_queue.pop_front())  # на стыке кругов — не тот же капитан подряд
	captain = _cap_queue.pop_front()
	card = deck[(round_no - 1) % deck.size()]
	theme = -1
	numbers = {}
	answers = {}
	placed = []
	log = []
	arrangement = []
	calls = {}
	guess = -1
	result = {}
	var nums := range(1, 11)
	for i in range(nums.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = nums[i]
		nums[i] = nums[j]
		nums[j] = t
	# капитан номер не получает и не отвечает (в эксперте номер у него есть — команда угадывает его в конце)
	var k := 0
	for s in players.size():
		if s == captain and not expert:
			continue
		numbers[s] = nums[k]
		k += 1
	phase = "theme"


func pick_theme(seat: int, i: int) -> bool:
	if phase != "theme" or seat != captain or i < 0 or i > 1:
		return false
	theme = i
	phase = "answer"
	return true


## Кто должен выложить ответ (капитан свой не пишет и не выкладывает).
func to_place() -> Array:
	var list := []
	for s in players.size():
		if s == captain:
			continue
		if not placed.has(s):
			list.append(s)
	return list


func answer(seat: int, text: String) -> bool:
	var t := text.strip_edges().left(MAX_ANSWER)
	if phase != "answer" or t == "" or answers.has(seat) or seat < 0 or seat >= players.size() or seat == captain:
		return false
	answers[seat] = t
	if answers.size() >= players.size() - 1:
		phase = "order"
	return true


## Капитан раскладывает ответы на планшете (можно сколько угодно раз менять). order — места слева направо;
## в эксперте ещё called_map: место -> названный номер.
func arrange(seat: int, order: Array, called_map: Dictionary = {}) -> bool:
	if phase != "order" or seat != captain:
		return false
	var allowed := to_place()
	var seen := {}
	var clean := []
	for x in order:
		var s := int(x)
		if not allowed.has(s) or seen.has(s):
			return false
		seen[s] = true
		clean.append(s)
	arrangement = clean
	var c := {}
	for k in called_map:
		var n := int(called_map[k])
		if seen.has(int(k)) and n >= 1 and n <= 10:
			c[int(k)] = n
	calls = c
	return true


## Готовая раскладка: все ответы на планшете (в эксперте — у каждого назван номер).
func can_commit() -> bool:
	if phase != "order" or arrangement.size() != to_place().size():
		return false
	if expert:
		for s in arrangement:
			if not calls.has(s):
				return false
	return true


## «Ответить»: ответы проверяются по раскладке слева направо (клиенты открывают номера по очереди).
func commit(seat: int) -> bool:
	if seat != captain or not can_commit():
		return false
	# раскрываются все карточки раскладки — даже если жетоны кончатся посередине (итог — после всех)
	_batch = true
	for s in arrangement.duplicate():
		place(seat, s, int(calls.get(s, -1)))
	_batch = false
	if unicorns == 0 and poops > 0:
		won = false
		result = {"lost": true}
		phase = "game_over"
	return true


## Время на ход вышло — раскладка дополняется как есть (недостающие — в конец, номера — случайно) и отправляется.
func force_commit() -> void:
	if phase != "order":
		return
	var order := arrangement.duplicate()
	for s in to_place():
		if not order.has(s):
			order.append(s)
	var c := calls.duplicate()
	for s in order:
		if not c.has(s):
			c[s] = rng.randi_range(1, 10)
	arrangement = order
	calls = c
	commit(captain)


## Время на ответ вышло — молчащим ставим заглушку.
func force_answers() -> void:
	if phase != "answer":
		return
	for s in players.size():
		if s != captain and not answers.has(s):
			answers[s] = "(промолчал)"
	phase = "order"


## Капитан выкладывает ответ игрока target. В эксперте — сперва называет номер called.
func place(seat: int, target: int, called: int = -1) -> bool:
	if phase != "order" or seat != captain or not to_place().has(target):
		return false
	if expert and (called < 1 or called > 10):
		return false
	var n: int = numbers[target]
	var ok := true
	if expert:
		ok = called == n
	elif not placed.is_empty():
		ok = n >= int(numbers[placed[-1]])
	placed.append(target)
	log.append({"seat": target, "number": n, "called": called, "ok": ok})
	if not ok:
		_lose_token()
		if phase == "game_over":
			return true
	if to_place().is_empty():
		if expert:
			phase = "guess"
		else:
			_end_round()
	return true


var _batch := false  # идёт проверка всей раскладки — поражение объявляем после неё


func _lose_token() -> void:
	if unicorns > 0:
		unicorns -= 1
		poops += 1
	if unicorns == 0 and not _batch:
		won = false
		result = {"lost": true}
		phase = "game_over"


## Эксперт: команда (любой не-капитан) называет номер капитана.
func guess_captain(seat: int, n: int) -> bool:
	if phase != "guess" or seat == captain or n < 1 or n > 10:
		return false
	guess = n
	if n == int(numbers[captain]) and poops > 0:
		poops -= 1
		unicorns += 1
	_end_round()
	return true


func _end_round() -> void:
	result = {"mistakes": log.filter(func(e): return not e["ok"]).size(), "guess": guess, "captain_number": numbers.get(captain, -1)}
	phase = "round_result"


func advance() -> void:
	if phase != "round_result":
		return
	if round_no >= TTData.ROUNDS:
		won = unicorns > 0
		phase = "game_over"
		return
	_start_round()


## Итог по таблице из правил: 0 — одни какашки … 3 — одни единороги.
func level() -> int:
	if unicorns == 0:
		return 0
	if poops == 0:
		return 3
	return 2 if unicorns >= poops else 1


func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var reveal := phase in ["round_result", "game_over"]
	var nums := {}
	for s in numbers:
		if show_all or s == seat or reveal or placed.has(s):
			nums[s] = numbers[s]
	var ans := {}
	for s in answers:
		ans[s] = answers[s] if phase != "answer" or s == seat or show_all else "…"
	return {
		"you": seat,
		"players": players.duplicate(true),
		"adult": adult,
		"expert": expert,
		"unicorns": unicorns,
		"poops": poops,
		"round_no": round_no,
		"rounds": TTData.ROUNDS,
		"captain": captain,
		"card": card.duplicate(true),
		"theme": theme,
		"numbers": nums,
		"answered": answers.keys(),
		"answers": ans,
		"placed": placed.duplicate(),
		"to_place": to_place(),
		"arrangement": arrangement.duplicate(),
		"calls": calls.duplicate(),
		"log": log.duplicate(true),
		"guess": guess,
		"phase": phase,
		"result": result.duplicate(),
		"won": won,
		"level": level(),
		"hotseat": show_all,
	}


# --- Новый игрок посреди партии ------------------------------------------------------

## Номера раздаются в начале раунда — новичок садится между раундами.
func can_add_player() -> bool:
	return phase == "round_result" and players.size() < 8


func add_player(p: Dictionary) -> bool:
	if not can_add_player():
		return false
	players.append(p.duplicate())
	return true
