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

## options.words: "simple" — 200 простых слов (IBSWords.SIMPLE), "shared" — общий словарь SharedWords.
func new_game(seats: Array, options: Dictionary = {}) -> void:
	players = seats.duplicate(true)
	words = preload("res://games/in_broad_strokes/logic/ibs_words.gd").pick(str(options.get("words", "simple")))
	words.shuffle()
	critic = randi_range(0,players.size()-1)
	_round()

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
		critic = (artist+1)%players.size()
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
		for pt: Vector2 in path:
			if not pt.is_finite() or pt.x < 0 or pt.y < 0 or pt.x > 1 or pt.y > 1:
				return false
	return true

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
