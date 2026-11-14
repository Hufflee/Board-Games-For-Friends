class_name IBSRules
extends RefCounted
## Хостовые правила «В общих чертах».
var players: Array = []
var phase := "draw"
var turn := 0
var critic := 0
var artist := 0
var serial := 0
var remaining := 25
var attempts := 2
var score := 0
var word := ""
var words: Array = []
var layers: Array = []
var previous: Array = []
var guess := ""
var elapsed := 0.0
var critic_pool: Array = []  # кто ещё не был искусствоведом в этом круге (владелец, 15.11)

## options.words: "simple" — 200 простых слов (IBSWords.SIMPLE), "shared" — общий словарь SharedWords.
func new_game(seats: Array, options: Dictionary = {}) -> void:
	players = seats.duplicate(true)
	words = preload("res://games/in_broad_strokes/logic/ibs_words.gd").pick(str(options.get("words", "simple")))
	words.shuffle()
	# первый искусствовед — выбранный в лобби или случайный; дальше — случайно из тех, кто ещё не был им в круге
	var first := int(options.get("critic", -1))
	critic = first if first >= 0 and first < players.size() else randi_range(0, players.size() - 1)
	critic_pool = range(players.size()).filter(func(s: int) -> bool: return s != critic)
	_round()


## Следующий искусствовед: случайный из ещё не бывших в этом круге; круг закончился — все снова в пуле.
func _next_critic() -> void:
	if critic_pool.is_empty():
		critic_pool = range(players.size())  # новый круг — снова все
	# в начале нового круга не повторять того, кто угадывал последним
	var choices: Array = critic_pool.filter(func(s: int) -> bool: return s != critic)
	if choices.is_empty():
		choices = critic_pool
	critic = choices.pick_random()
	critic_pool.erase(critic)

func _round() -> void:
	if remaining == 0 or words.is_empty():
		phase = "end"
		return
	word = words.pop_back()
	artist = (critic+1)%players.size()
	turn = artist
	layers = []
	previous = []
	guess = ""
	phase = "draw"

func _finish(correct: bool) -> void:
	if correct:
		score += 1
	else:
		remaining = maxi(0,remaining-1)
	phase = "result"
	turn = -1

func action(seat: int, kind: String, arg: Dictionary, host: bool) -> bool:
	if int(arg.get("serial",-1)) != serial:
		return false
	if phase == "draw" and seat == artist and kind == "draw":
		var strokes: Variant = arg.get("strokes")
		if not _valid(strokes):
			return false
		previous = layers.duplicate()
		layers.append(strokes.duplicate(true))
		remaining -= 1
		attempts = 2
		elapsed = 0
		phase = "merge"
		turn = -1
	elif phase == "guess" and seat == critic and kind in ["guess","pass"]:
		guess = str(arg.get("word","")).strip_edges().left(80)
		if kind == "guess" and guess.is_empty():
			return false
		if kind == "guess" and guess.to_lower().replace("ё","е") == word.to_lower().replace("ё","е"):
			_finish(true)
		elif kind == "guess":
			phase = "judge"
			turn = artist
		else:
			_miss()
	elif phase == "judge" and seat == artist and kind in ["accept","reject"]:
		if kind == "accept":
			_finish(true)
		else:
			_miss()
	elif phase in ["draw","guess","judge"] and host and kind == "give_up":
		_finish(false)
	elif phase == "result" and host and kind == "next":
		_next_critic()
		_round()
	else:
		return false
	serial += 1
	return true

func _miss() -> void:
	attempts -= 1
	if attempts > 0:
		turn = critic
		phase = "guess"
	elif remaining <= 0:
		phase = "result"
		turn = -1
	else:
		artist = (artist+1)%players.size()
		if artist == critic:
			artist = (artist+1)%players.size()
		turn = artist
		phase = "draw"

func _valid(strokes: Variant) -> bool:
	if not strokes is Array or strokes.is_empty() or strokes.size() > 2:
		return false
	for path: Variant in strokes:
		if not path is PackedVector2Array or path.size() < 2 or path.size() > 192:
			return false
		if strokes.size() == 2 and path.size() != 2:
			return false
		if strokes.size() == 1 and path.size() > 2 and not curve_ok(path):
			return false
		for pt: Vector2 in path:
			if not pt.is_finite() or pt.x < 0 or pt.y < 0 or pt.x > 1 or pt.y > 1:
				return false
	return true

## Кривая гнётся только в одну сторону (правила: круг и спираль можно, «S» — нельзя).
## Повороты между соседними отрезками длиной от CURVE_STEP должны быть одного знака; мелкое дрожание
## руки (синус угла меньше CURVE_TOLERANCE) поворотом не считается. Той же функцией проверяет и стол.
const CURVE_STEP := 0.012
const CURVE_TOLERANCE := 0.15


static func curve_ok(path: PackedVector2Array) -> bool:
	var turn_sign := 0
	var anchor := path[0]
	var prev_dir := Vector2.ZERO
	for i in range(1, path.size()):
		var seg := path[i] - anchor
		if seg.length() < CURVE_STEP:
			continue
		var dir := seg.normalized()
		if prev_dir != Vector2.ZERO:
			var turn := prev_dir.cross(dir)
			if absf(turn) > CURVE_TOLERANCE:
				var s := 1 if turn > 0 else -1
				if turn_sign == 0:
					turn_sign = s
				elif s != turn_sign:
					return false
		prev_dir = dir
		anchor = path[i]
	return true


## Фазы с часами хода.
const TIMED := ["draw", "guess", "judge"]


## Время вышло (владелец, 15.11): художник не нарисовал — ход переходит следующему художнику (лист не
## тратится); искусствовед — пас; художник не решил — догадка не засчитывается.
func timeout() -> bool:
	match phase:
		"draw":
			artist = (artist + 1) % players.size()
			if artist == critic:
				artist = (artist + 1) % players.size()
			turn = artist
			serial += 1
			return true
		"guess":
			return action(critic, "pass", {"serial": serial}, false)
		"judge":
			return action(artist, "reject", {"serial": serial}, false)
	return false


func tick(delta: float) -> bool:
	if phase != "merge":
		return false
	elapsed += delta
	if elapsed < .7:
		return false
	phase = "guess"
	turn = critic
	serial += 1
	return true

func get_view(seat: int) -> Dictionary:
	var visible := (seat >= 0 and seat != critic) or phase in ["result","end"]
	return {"phase":phase,"turn":turn,"seat":seat,"serial":serial,"artist":artist,"critic":critic,
		"word":word if visible else "", "remaining":remaining,"score":score,"attempts":attempts,
		"guess":guess,"layers":layers.duplicate(true),"elapsed":elapsed if phase == "merge" else 0.0,
		"names":players.map(func(player: Dictionary) -> String: return str(player.get("name","Игрок")))}
