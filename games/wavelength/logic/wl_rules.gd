class_name WLRules
extends RefCounted
## Движок правил «Длины волны». Хост вызывает действия, клиенты получают get_view():
## положение цветной зоны видит только телепат (до вскрытия).
##
## Фазы: card (телепат выбирает сторону карточки) → clue (пишет подсказку) → guess (команда двигает стрелку)
##       → side (другая команда: левее/правее; в кооперативе пропускается) → reveal → … → game_over

const WIN := 10
const COOP_CARDS := 7
const COOP_GOAL := 16  # цель кооператива по шкале оригинала: «Вы победили!» (≈2,3 очка за карточку)
const BANDS := [[2.0, 4], [6.0, 3], [10.0, 2]]  # полуширина полосы → очки
const COOP_RESULTS := [
	[0, "Эта штука вообще работает?"], [4, "Попробуйте выключить и включить"], [7, "Разберитесь уже с механизмом!"],
	[10, "Неплохо! Ничего особенного, но неплохо!"], [13, "Почти!"], [16, "Вы победили!"],
	[19, "Да вы… на одной волне"], [22, "Высший разум"], [25, "Невероятно!!! (взрыв мозга)"],
]

var players: Array = []  # [{name, team}]
var coop := false
var scores := [0, 0]
var active_team := 0
var psychic := -1
var _psychic_turn := [0, 0]  # чья очередь быть телепатом в каждой команде
var deck: Array = []  # индексы карточек
var card: Array = []  # две пары текущей карточки
var side := -1  # выбранная телепатом пара
var target := 50.0  # центр цветной зоны (0…100)
var dial := 50.0  # стрелка
var clue := ""
var lr := ""  # выбор другой команды: "left" / "right"
var phase := "setup"
var result := {}
var turn_no := 0
var cards_left := 0  # кооператив
var tiebreak := {}  # {left: ходов осталось, gained: [a, b]}
var winner := -1  # команда-победитель (кооператив: 0)
var rng := RandomNumberGenerator.new()


func new_game(player_list: Array, coop_mode: bool, seed_value: int = 0) -> void:
	players = player_list.duplicate(true)
	coop = coop_mode
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	if coop:
		for p in players:
			p["team"] = 0
	deck = range(WLCards.card_count())
	_shuffle(deck)
	scores = [0, 0]  # вторая команда ходит второй — ей цель на 1 очко меньше (goal)
	active_team = 0
	_psychic_turn = [rng.randi_range(0, 7), rng.randi_range(0, 7)]
	cards_left = COOP_CARDS
	turn_no = 0
	winner = -1
	tiebreak = {}
	_start_turn()


func team_members(team: int) -> Array:
	var list := []
	for s in players.size():
		if players[s]["team"] == team:
			list.append(s)
	return list


func _start_turn() -> void:
	turn_no += 1
	var members := team_members(active_team)
	psychic = members[_psychic_turn[active_team] % members.size()]
	_psychic_turn[active_team] += 1
	if deck.is_empty():
		deck = range(WLCards.card_count())
		_shuffle(deck)
	card = WLCards.card(deck.pop_back())
	side = -1
	target = rng.randf_range(3.0, 97.0)
	dial = 50.0
	clue = ""
	lr = ""
	result = {}
	phase = "card"


# --- Действия -----------------------------------------------------------------

func choose_side(seat: int, i: int) -> bool:
	if phase != "card" or seat != psychic or i < 0 or i > 1:
		return false
	side = i
	phase = "clue"
	return true


func give_clue(seat: int, text: String) -> bool:
	text = text.strip_edges().left(80)
	if phase != "clue" or seat != psychic or text == "":
		return false
	clue = text
	phase = "guess"
	return true


## Двигать стрелку может любой из команды телепата (кроме него самого).
func move_dial(seat: int, value: float) -> bool:
	if phase != "guess" or not can_guess(seat):
		return false
	dial = clampf(value, 0.0, 100.0)
	return true


func lock_dial(seat: int) -> bool:
	if phase != "guess" or not can_guess(seat):
		return false
	if coop:
		_score()
	else:
		phase = "side"
	return true


func choose_lr(seat: int, choice: String) -> bool:
	if phase != "side" or players[seat]["team"] == active_team or not choice in ["left", "right"]:
		return false
	lr = choice
	_score()
	return true


func can_guess(seat: int) -> bool:
	return players[seat]["team"] == active_team and seat != psychic


static func points_for(target_v: float, dial_v: float) -> int:
	var d := absf(target_v - dial_v)
	for band in BANDS:
		if d <= band[0] + 0.0001:
			return band[1]
	return 0


func _score() -> void:
	var pts := points_for(target, dial)
	var other_pts := 0
	if coop:
		if pts == 4:
			pts = 3
			cards_left += 1  # попадание в центр — ещё одна карточка
		scores[0] += pts
		cards_left -= 1
	else:
		var center_left := target < dial
		var guessed := (lr == "left" and center_left) or (lr == "right" and not center_left)
		if guessed and pts < 4:
			other_pts = 1
		scores[active_team] += pts
		scores[1 - active_team] += other_pts
		if not tiebreak.is_empty():
			tiebreak["gained"][active_team] += pts
			tiebreak["gained"][1 - active_team] += other_pts
	result = {
		"points": pts,
		"other_points": other_pts,
		"bullseye": points_for(target, dial) == 4,
		"team": active_team,
		"lr": lr,
	}
	phase = "reveal"


## Хост вызывает, когда все посмотрели вскрытие.
func advance() -> void:
	if phase != "reveal":
		return
	if coop:
		if cards_left <= 0:
			winner = 0
			phase = "game_over"
			return
		_start_turn()
		return
	if not tiebreak.is_empty():
		tiebreak["left"] -= 1
		if tiebreak["left"] <= 0:
			var g: Array = tiebreak["gained"]
			if g[0] != g[1]:
				winner = 0 if g[0] > g[1] else 1
				phase = "game_over"
				return
			tiebreak = {"left": 2, "gained": [0, 0]}  # снова ничья — ещё по ходу
		active_team = 1 - active_team
		_start_turn()
		return
	# сравниваем, сколько осталось до своей цели (у второй команды она на 1 меньше)
	var a: int = scores[active_team] - goal(active_team)
	var b: int = scores[1 - active_team] - goal(1 - active_team)
	if a >= 0 or b >= 0:
		if a != b:
			winner = active_team if a > b else 1 - active_team
			phase = "game_over"
			return
		tiebreak = {"left": 2, "gained": [0, 0]}
		active_team = 1 - active_team
		_start_turn()
		return
	# правило догоняющего: 4 очка, но всё ещё отстаём — ходим снова (с новым телепатом)
	if result.get("points", 0) == 4 and a < b:
		result["catchup"] = true
		_start_turn()
		return
	active_team = 1 - active_team
	_start_turn()


## Сколько очков нужно команде для победы: второй (ходит второй) — на 1 меньше.
func goal(t: int) -> int:
	return WIN - 1 if t == 1 and not coop else WIN


## Следующая ступень шкалы кооператива: [очки, название] или [] если выше некуда.
static func coop_next(score: int) -> Array:
	for row in COOP_RESULTS:
		if score < row[0]:
			return row
	return []


static func coop_rating(score: int) -> String:
	var text: String = COOP_RESULTS[0][1]
	for row in COOP_RESULTS:
		if score >= row[0]:
			text = row[1]
	return text


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Состояние для игрока. show_all — режим «на одном компьютере» (зона прячется в интерфейсе).
func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var sees_target := show_all or seat == psychic or phase in ["reveal", "game_over"]
	return {
		"you": seat,
		"players": players.duplicate(true),
		"coop": coop,
		"scores": scores.duplicate(),
		"goals": [goal(0), goal(1)],
		"active_team": active_team,
		"psychic": psychic,
		"card": card.duplicate(true),
		"side": side,
		"target": target if sees_target else -1.0,
		"dial": dial,
		"clue": clue,
		"lr": lr,
		"phase": phase,
		"result": result.duplicate(),
		"turn_no": turn_no,
		"cards_left": cards_left,
		"tiebreak": not tiebreak.is_empty(),
		"winner": winner,
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
	q["team"] = 0 if coop else (int(p["team"]) if int(p.get("team", -1)) in [0, 1] else _smaller_team())
	players.append(q)
	return true


## Зритель смотрит глазами рядового игрока — не телепата (тот видит тайну).
func spectator_seat() -> int:
	for s in players.size():
		if s != psychic:
			return s
	return 0


## Командная игра: в какие команды зритель может войти сам (прогресс общий — он не начинает с нуля).
func teams_for_join() -> Array:
	return [0] if coop else [0, 1] if can_add_player() else []
