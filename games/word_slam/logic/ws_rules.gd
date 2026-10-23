class_name WSRules
extends RefCounted
## Движок «Ворд Слэма». Рассказчики объясняют слово только карточками слов на двух подставках,
## отгадывающие пишут догадки. Хост ведёт часы (Net) и вызывает time_up().
##
## Фазы: word (рассказчики видят слово, можно перебросить, «Готов») → play (карточки, догадки, часы)
##       → round_result → … → game_over
## Режимы: teams — две команды и два рассказчика; solo — один рассказчик, остальные каждый за себя.

const MAX_ON_HOLDER := 12
const LOG_SIZE := 40

var players: Array = []  # [{name, team}]
var mode := "teams"
var names_on := true
var scores: Array = []  # teams: [синие, оранжевые]; solo: по игрокам
var won_cards: Array = []  # [{word, by}] — для итогов
var storytellers: Array = []  # teams: [рассказчик синих, оранжевых]; solo: [рассказчик]
var _turn: Array = [0, 0]  # чей черёд рассказывать в команде / по кругу
var hourglass_team := 0  # у кого часы (и кубик); другая команда тянет карту
var deck: Array = []
var total_cards := 0
var card := {}
var roll := 1
var word := ""
var ready: Array = []  # готовность рассказчиков («ВОРД!» — «СЛЭМ!»)
var holders := {}  # team (solo: 0) -> [[левая], [правая]] — id карточек «noun:5»
var pointer := {}  # team -> {id, n}
var flipped := false
var guesses: Array = []  # [{seat, text, ok}]
var round_no := 0
var result := {}
var tiebreak := false
var winners: Array = []  # teams: [команда]; solo: [места]
var phase := "setup"
var rng := RandomNumberGenerator.new()


func new_game(player_list: Array, solo: bool, card_count: int, intro: bool, with_names: bool, seed_value: int = 0) -> void:
	players = player_list.duplicate(true)
	mode = "solo" if solo else "teams"
	names_on = with_names and not intro
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	if solo:
		for p in players:
			p["team"] = 0
		scores = []
		scores.resize(players.size())
		scores.fill(0)
	else:
		scores = [0, 0]
	deck = WSData.build_deck(rng, card_count, intro)
	total_cards = card_count
	won_cards = []
	_turn = [rng.randi_range(0, 7), rng.randi_range(0, 7)]
	hourglass_team = rng.randi_range(0, 1)
	round_no = 0
	tiebreak = false
	winners = []
	_start_round()


func team_members(team: int) -> Array:
	var list := []
	for s in players.size():
		if players[s]["team"] == team:
			list.append(s)
	return list


func team_of(seat: int) -> int:
	return int(players[seat]["team"])


func is_storyteller(seat: int) -> bool:
	return storytellers.has(seat)


## Рассказчик, который тянет карту и может перебросить (у команды без часов).
func drawer() -> int:
	return storytellers[0] if mode == "solo" else storytellers[1 - hourglass_team]


func _start_round() -> void:
	round_no += 1
	if mode == "solo":
		storytellers = [_turn[0] % players.size()]
		_turn[0] += 1
	else:
		storytellers = []
		for t in 2:
			var m := team_members(t)
			storytellers.append(m[_turn[t] % m.size()])
			_turn[t] += 1
	if deck.is_empty():
		deck = WSData.build_deck(rng, 1, false)  # дополнительная карта при ничьей
	card = deck.pop_back()
	_roll()
	ready = []
	for s in storytellers:
		ready.append(false)
	holders = {}
	pointer = {}
	for t in (1 if mode == "solo" else 2):
		holders[t] = [[], []]
	flipped = false
	guesses = []
	result = {}
	phase = "word"


func _roll() -> void:
	roll = rng.randi_range(1, 6)
	while roll == 6 and not names_on:
		roll = rng.randi_range(1, 6)
	word = card["words"][roll - 1]


func reroll(seat: int) -> bool:
	if phase != "word" or seat != drawer():
		return false
	_roll()
	return true


func set_ready(seat: int) -> bool:
	var i := storytellers.find(seat)
	if phase != "word" or i < 0 or ready[i]:
		return false
	ready[i] = true
	if not ready.has(false):
		phase = "play"
		flipped = true  # время на ход идёт сразу (переворачивать часы не нужно)
	return true


func _team_key(seat: int) -> int:
	return 0 if mode == "solo" else team_of(seat)


## Рассказчик выкладывает карточки: rows = [левая подставка, правая подставка] (id «категория:номер»).
func set_holders(seat: int, rows: Array) -> bool:
	if phase != "play" or not is_storyteller(seat) or rows.size() != 2:
		return false
	var seen := {}
	var clean := []
	for row in rows:
		if not row is Array or row.size() > MAX_ON_HOLDER:
			return false
		var r := []
		for id in row:
			if not valid_card(str(id)) or seen.has(str(id)):
				return false
			seen[str(id)] = true
			r.append(str(id))
		clean.append(r)
	holders[_team_key(seat)] = clean
	return true


static func valid_card(id: String) -> bool:
	var p := id.split(":")
	if p.size() != 2 or not WSData.STORY.has(p[0]):
		return false
	var i := int(p[1])
	return i >= 0 and i < WSData.STORY[p[0]].size() and p[1] == str(i)


static func card_word(id: String) -> String:
	var p := id.split(":")
	return WSData.STORY[p[0]][int(p[1])]


func point(seat: int, id: String) -> bool:
	if phase != "play" or not is_storyteller(seat):
		return false
	var k := _team_key(seat)
	var on: bool = holders[k][0].has(id) or holders[k][1].has(id)
	if not on:
		return false
	pointer[k] = {"id": id, "n": int(pointer.get(k, {}).get("n", 0)) + 1}
	return true


## Команда с часами переворачивает их (в solo — рассказчик).
func flip(seat: int) -> bool:
	if phase != "play" or flipped:
		return false
	var holder: int = storytellers[0] if mode == "solo" else storytellers[hourglass_team]
	if seat >= 0 and seat != holder:
		return false
	flipped = true
	return true


func can_guess(seat: int) -> bool:
	if phase != "play" or is_storyteller(seat):
		return false
	var k := _team_key(seat)
	return not (holders[k][0].is_empty() and holders[k][1].is_empty())  # пока нет карточек — рано


func guess(seat: int, text: String) -> bool:
	if not can_guess(seat):
		return false
	var t := text.strip_edges().left(60)
	if t == "":
		return false
	var ok := DWRules.guess_matches(t.replace("-", " "), word.replace("-", " "))
	guesses.append({"seat": seat, "text": t, "ok": ok})
	if guesses.size() > LOG_SIZE:
		guesses.pop_front()
	if ok:
		_win(seat)
	return true


## Рассказчик подтверждает голосовую догадку. В solo — guesser: кто угадал.
func confirm(seat: int, guesser: int = -1) -> bool:
	if phase != "play" or not is_storyteller(seat):
		return false
	if mode == "solo":
		if guesser < 0 or guesser >= players.size() or guesser == seat:
			return false
		_win(guesser)
	else:
		var mates := team_members(team_of(seat)).filter(func(s): return s != seat)
		_win(mates[0] if not mates.is_empty() else seat)
	return true


func _win(seat: int) -> void:
	if mode == "solo":
		scores[seat] += 1
		scores[storytellers[0]] += 1
		result = {"winner": seat, "team": -1, "word": word}
	else:
		var t := team_of(seat)
		scores[t] += 1
		result = {"winner": seat, "team": t, "word": word}
	won_cards.append({"word": word, "by": result["team"] if mode == "teams" else seat})
	_end_round()


func time_up() -> void:
	if phase != "play":
		return
	result = {"winner": -1, "team": -1, "word": word}
	_end_round()


func _end_round() -> void:
	phase = "round_result"


func advance() -> void:
	if phase != "round_result":
		return
	if deck.is_empty():
		var best: int = scores.max()
		var leaders := []
		for i in scores.size():
			if scores[i] == best:
				leaders.append(i)
		if leaders.size() == 1 or round_no >= total_cards + 5:
			winners = leaders
			phase = "game_over"
			return
		tiebreak = true
	if mode == "teams":
		hourglass_team = 1 - hourglass_team
	_start_round()


func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var secret := show_all or is_storyteller(seat) or phase in ["round_result", "game_over"]
	var my_key := 0 if mode == "solo" else team_of(seat)
	var hv := {}
	for k in holders:
		var visible: bool = show_all or k == my_key or phase in ["round_result", "game_over"]
		hv[k] = holders[k].duplicate(true) if visible else [holders[k][0].map(func(_x): return "?"), holders[k][1].map(func(_x): return "?")]
	return {
		"you": seat,
		"players": players.duplicate(true),
		"mode": mode,
		"scores": scores.duplicate(),
		"storytellers": storytellers.duplicate(),
		"drawer": drawer(),
		"hourglass_team": hourglass_team,
		"card": card.duplicate(true) if secret else {},
		"roll": roll,
		"word": word if secret else "",
		"ready": ready.duplicate(),
		"holders": hv,
		"pointer": pointer.duplicate(true),
		"flipped": flipped,
		"guesses": guesses.duplicate(true),
		"round_no": round_no,
		"cards_left": deck.size(),
		"total_cards": total_cards,
		"result": result.duplicate(),
		"tiebreak": tiebreak,
		"winners": winners.duplicate(),
		"phase": phase,
		"hotseat": show_all,
	}


## Посреди партии (хост сажает друга из пати): новый игрок — в меньшую команду.
func _smaller_team() -> int:
	var a := 0
	var b := 0
	for p in players:
		if int(p.get("team", 0)) == 0:
			a += 1
		else:
			b += 1
	return 0 if a <= b else 1


func can_add_player() -> bool:
	return phase != "game_over" and players.size() < 12


func add_player(p: Dictionary) -> bool:
	if not can_add_player():
		return false
	var q := p.duplicate()
	if mode == "solo":
		q["team"] = 0
		scores.append(0)
	else:
		q["team"] = int(p["team"]) if int(p.get("team", -1)) in [0, 1] else _smaller_team()
	players.append(q)
	return true


## Зритель смотрит глазами рядового игрока — не рассказчика (тот видит тайну).
func spectator_seat() -> int:
	for s in players.size():
		if not storytellers.has(s):
			return s
	return 0


## Командная игра: в какие команды зритель может войти сам (прогресс общий — он не начинает с нуля).
func teams_for_join() -> Array:
	return ([] if mode == "solo" else [0, 1]) if can_add_player() else []
