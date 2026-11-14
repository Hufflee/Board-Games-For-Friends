class_name GTWRules
extends RefCounted
## Подсчёт большинства и приватные ответы Green Team Wins.

var players: Array = []
var phase := "answer"
var cards: Array[String] = []
var turn_no := 0
var answers: Dictionary = {}
var groups: Dictionary = {}
var green: Array[bool] = []
var score: Array[int] = []
var gain: Array[int] = []
var results: Array[int] = []

func new_game(seats: Array) -> void:
	players = seats.duplicate(true)
	for i in players.size():
		green.append(false)
		score.append(0)
		gain.append(0)
	for kind in ["three","two","blank"]:
		var numbers := range(70)
		numbers.shuffle()
		for i in range(5):
			cards.append("%s_%02d" % [kind,numbers[i]])
	cards.shuffle()

static func answer_key(raw: String) -> String:
	var normalized := raw.to_lower().replace("ё","е").strip_edges()
	for mark in [".",",","!","?","\"","«","»"]:
		normalized = normalized.replace(mark,"")
	return " ".join(normalized.split(" ",false))

func action(seat: int, kind: String, data: Dictionary, host: bool) -> bool:
	if int(data.get("round",-1)) != turn_no or phase == "end":
		return false
	if phase == "answer" and kind == "answer":
		if seat < 0 or seat >= players.size() or answers.has(seat):
			return false
		var value := str(data.get("answer","")).strip_edges()
		var id: String = cards[turn_no]
		if id.begins_with("blank"):
			if value.length() > 80 or answer_key(value).is_empty():
				return false
		elif not value in (["1","2","3"] if id.begins_with("three") else ["1","2"]):
			return false
		answers[seat] = value
		if answers.size() == players.size():
			for s: int in answers:
				groups[s] = answer_key(answers[s])
			if id.begins_with("blank"):
				phase = "group"
			else:
				_score()
		return true
	if phase == "group" and host:
		if kind == "merge":
			var from := int(data.get("from",-1))
			var into := int(data.get("into",-1))
			if not groups.has(from) or not groups.has(into) or groups[from] == groups[into]:
				return false
			var old: String = groups[from]
			for s: int in groups:
				if groups[s] == old:
					groups[s] = groups[into]
			return true
		if kind == "reset_groups":
			for s: int in answers:
				groups[s] = answer_key(answers[s])
			return true
		if kind == "score":
			_score()
			return true
	if phase == "result" and host and kind == "next":
		if turn_no == cards.size()-1:
			phase = "end"
			for s in score.size():
				if score[s] == score.max():
					results.append(s)
		else:
			phase = "answer"
			turn_no += 1
			answers.clear()
			groups.clear()
			gain.fill(0)
		return true
	return false

## Время на ответ вышло (владелец, 15.11): кто не ответил — случайный вариант карты; на карте с пропуском —
## «нет ответа» (у каждого свой, поэтому в большинство не попадает).
func timeout() -> bool:
	if phase != "answer":
		return false
	var id: String = cards[turn_no]
	var acted := false
	for s in players.size():
		if phase != "answer" or answers.has(s):
			continue
		var value := "нет ответа %d" % (s + 1) if id.begins_with("blank") else str(randi_range(1, 3 if id.begins_with("three") else 2))
		acted = action(s, "answer", {"round": turn_no, "answer": value}, false) or acted
	return acted


func _score() -> void:
	var counts: Dictionary = {}
	for answer: String in groups.values():
		counts[answer] = int(counts.get(answer,0))+1
	var highest: int = counts.values().max()
	var winning := counts.keys().filter(func(k: String) -> bool: return counts[k] == highest)
	for s in players.size():
		var stays := false
		if highest >= 2 and winning.has(groups[s]):
			stays = winning.size() == 1 or green[s]
		gain[s] = (2 if green[s] else 1) if stays else 0
		score[s] += gain[s]
		green[s] = stays
	phase = "result"

func get_view(seat: int) -> Dictionary:
	return {"phase":phase,"round":turn_no,"card":cards[turn_no],"seat":seat,
		"names":players.map(func(p: Dictionary) -> String: return str(p.get("name","Игрок"))),
		"answered":answers.keys(),"answers":{} if phase == "answer" else answers.duplicate(),
		"groups":{} if phase == "answer" else groups.duplicate(),"green":green.duplicate(),
		"scores":score.duplicate(),"gain":gain.duplicate(),"results":results.duplicate()}
