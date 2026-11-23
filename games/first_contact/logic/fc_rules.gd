class_name FCRules
extends RefCounted
## Раздача предметов, приватные цели и голосование «Первого контакта».
const FEATURES := ["Большое","Маленькое","Живое","Инструмент","Опасное","Круглое","Металл","Дерево","Камень","Человек","Власть","Ценность","Еда","Вода","Движение","Природа","Рукотворное","Мягкое","Твёрдое","Острое","Длинное","Тяжёлое","Место","Животное","Растение"]
const GLYPHS := ["△","○","◇","□","◐","◑","◒","◓","⊙","⊕","⊗","⊖","⌁","⌂","⌘","⌖","⌗","⋈","⋄","⊢","⊥","∩","∪","≋","×"]
var players: Array = []
var phase := "ask"
var turn := 0
var turn_no := 1
var serial := 0
var humans := 0
var aliens := 0
var goal := 3
var energy := 9
var low := false
var cards: Array = []
var language: Array = []
var targets: Array = []
var forbidden: Array = []
var owned := {}
var favor: Array[int] = []
var ballots := {}
var notes := {}
var teaching: Array = []
var examples: Array = []
var clue: Array = []
var last_votes := {}
var alien_turn := 0
var human_turn := 0
var teacher_turn := 0
var winner := -1
var opening := false
var previous_asks: Array = []

func new_game(seats: Array, config: Dictionary = {}) -> void:
	players = seats.duplicate(true)
	low = players.size() < 4
	# правила (стр. 2): игроки сами делятся на команды — инопланетян не больше 3, землян не больше 4.
	# config.aliens — выбор в лобби; 0 или вне допустимого — наименьшее возможное (владелец, 15.11)
	aliens = 1 if low else clampi(int(config.get("aliens", 0)), min_aliens(players.size()), max_aliens(players.size()))
	humans = players.size()-aliens
	goal = 8 if low else (5 if config.get("hard",false) else 3)
	cards = range(60)
	cards.shuffle()
	cards.resize(25)
	language = range(FEATURES.size())
	language.shuffle()
	var slots := range(25)
	slots.shuffle()
	for i in aliens:
		targets.append(slots.slice(i*goal,(i+1)*goal))
	if low:
		forbidden = slots.slice(goal,goal+4)
	favor.resize(humans)
	favor.fill(0)
	opening = bool(config.get("opening",false))
	if opening:
		phase = "opening"

## Допустимое число инопланетян при count игроках: землян не больше 4, инопланетян 1–3.
static func min_aliens(count: int) -> int:
	return 1 if count < 4 else maxi(1, count - 4)


static func max_aliens(count: int) -> int:
	return 1 if count < 4 else mini(3, count - 1)


func action(seat: int, kind: String, arg: Dictionary, host: bool) -> bool:
	if seat >= 0 and seat < humans and kind == "note_erase" and phase != "end":
		var feature := int(arg.get("feature", -1))
		var symbol := int(arg.get("symbol", -1))
		var row: Dictionary = notes.get(seat, {})
		if not row.has(feature) or int(row[feature]) != symbol:
			return false
		row.erase(feature)
		notes[seat] = row
		return true
	if seat >= 0 and seat < humans and kind == "note":
		var feature := int(arg.get("feature",-1))
		var symbol := int(arg.get("symbol",-1))
		if feature < 0 or feature >= FEATURES.size() or symbol < -1 or symbol >= GLYPHS.size() or phase == "end":
			return false
		var row: Dictionary = notes.get(seat,{})
		# К одному знаку можно записать несколько предположений (владелец, 22.11).
		if symbol < 0:
			row.erase(feature)
		else:
			row[feature] = symbol
		notes[seat] = row
		return true
	if int(arg.get("serial",-1)) != serial or phase == "end":
		return false
	if phase == "opening" and seat == turn and kind in ["opening", "skip_learning"]:
		if kind == "opening":
			var feature := int(arg.get("feature",-1))
			if feature < 0 or feature >= FEATURES.size() or feature in previous_asks:
				return false
			previous_asks.append(feature)
			teaching.append({"slots":[],"symbol":language[feature],"feature":feature})
		turn += 1
		if turn >= humans:
			opening = false
			phase = "ask"
			turn = 0
	elif phase == "ask" and seat == turn and kind == "skip_learning":
		_advance_learning()
	elif phase == "ask" and seat == turn and kind == "ask":
		var selected: Variant = arg.get("slots")
		if not selected is Array or selected.is_empty() or selected.size() > 5:
			return false
		var unique := {}
		for slot: Variant in selected:
			if not slot is int or slot < 0 or slot >= 25 or unique.has(slot):
				return false
			unique[slot] = true
		examples = selected.duplicate()
		phase = "teach"
		turn = humans + teacher_turn
	elif phase == "teach" and seat == turn and kind == "teach":
		var feature := int(arg.get("feature",-1))
		if feature < 0 or feature >= FEATURES.size():
			return false
		teaching.append({"slots":examples.duplicate(),"symbol":language[feature]})
		teacher_turn = (teacher_turn + 1) % aliens
		_advance_learning()
	elif phase == "clue" and seat == turn and kind == "clue":
		var signs: Variant = arg.get("signs")
		if not signs is Array or signs.is_empty() or signs.size() > FEATURES.size():
			return false
		clue = []
		for sign: Variant in signs:
			if not sign is int or absi(sign) > FEATURES.size() or sign == 0:
				return false
			clue.append({"symbol":language[absi(sign)-1],"negative":sign<0})
		ballots.clear()
		phase = "vote"
		turn = 0
	elif phase == "vote" and seat >= 0 and seat < humans and kind == "vote":
		if ballots.has(seat):
			return false
		var votes: Variant = arg.get("slots")
		if not votes is Array or votes.is_empty() or votes.size() > (2 if players.size() == 2 else 1):
			return false
		var unique := {}
		for slot: Variant in votes:
			if not slot is int or slot < 0 or slot >= 25 or owned.has(slot) or unique.has(slot):
				return false
			unique[slot] = true
		ballots[seat] = votes.duplicate()
		if ballots.size() < humans:
			turn = -1
			for i in humans:
				if not ballots.has(i):
					turn = i
					break
			return true
		_resolve()
	elif phase == "result" and host and kind == "next":
		if winner >= 0 or (low and energy < 0):
			phase = "end"
			turn = -1
		else:
			alien_turn += 1
			if alien_turn >= aliens:
				alien_turn = 0
				human_turn = 0
				turn_no += 1
				phase = "ask"
				turn = 0
			else:
				phase = "clue"
				turn = humans+alien_turn
	else:
		return false
	serial += 1
	return true


## Пропуск завершает только этот ход; первый круг по-прежнему посвящён обучению.
func _advance_learning() -> void:
	human_turn += 1
	phase = "ask" if human_turn < humans else "clue"
	turn = human_turn if phase == "ask" else humans + alien_turn
	if phase == "clue" and turn_no == 1:
		turn_no += 1
		human_turn = 0
		phase = "ask"
		turn = 0

func _resolve() -> void:
	last_votes = ballots.duplicate(true)
	for seat in ballots:
		for slot in ballots[seat]:
			if slot in targets[alien_turn]:
				favor[seat] += 1
				owned[slot] = alien_turn
			elif low and slot in forbidden:
				energy -= 1
	if owned.values().count(alien_turn) >= goal:
		winner = alien_turn+humans
	elif low:
		energy -= 1
	phase = "result"
	turn = -1

## Фазы с часами хода.
const TIMED := ["opening", "ask", "teach", "clue", "vote"]


## Время вышло — хост ходит за задумавшихся (владелец, 15.11): случайный пример, знак, подсказка
## одним знаком; в голосовании — случайный ещё не найденный предмет за всех, кто не проголосовал.
func timeout() -> bool:
	if phase not in TIMED:
		return false
	var free: Array = range(25).filter(func(s: int) -> bool: return not owned.has(s))
	match phase:
		"opening":
			var left: Array = range(FEATURES.size()).filter(func(f: int) -> bool: return f not in previous_asks)
			return action(turn, "opening", {"serial": serial, "feature": left.pick_random()}, false)
		"ask":
			return action(turn, "ask", {"serial": serial, "slots": [free.pick_random()]}, false)
		"teach":
			return action(turn, "teach", {"serial": serial, "feature": randi_range(0, FEATURES.size() - 1)}, false)
		"clue":
			return action(turn, "clue", {"serial": serial, "signs": [randi_range(1, FEATURES.size())]}, false)
		"vote":
			var acted := false
			for seat in humans:
				if phase == "vote" and not ballots.has(seat):
					acted = action(seat, "vote", {"serial": serial, "slots": [free.pick_random()]}, false) or acted
			return acted
	return false


func get_view(seat: int) -> Dictionary:
	var alien := seat >= humans and seat < players.size()
	var points: Array[int] = []
	for i in humans:
		var knowledge := 0
		var row: Dictionary = notes.get(i,{})
		for feature in row:
			if int(row[feature]) == language[feature]:
				knowledge += 1
		points.append(knowledge)
	return {"phase":phase,"serial":serial,"turn":turn,"seat":seat,"round":turn_no,"humans":humans,
		"alien":alien,"aliens":aliens,"active_alien":alien_turn,"names":players.map(func(x: Dictionary) -> String: return str(x.get("name","Игрок"))),
		"goal":goal,"energy":energy,"low":low,"cards":cards.duplicate(),"owned":owned.duplicate(),
		"targets":targets.duplicate(true) if alien else [],"forbidden":forbidden.duplicate() if alien else [],
		"language":language.duplicate() if alien or phase == "end" else [],"notes":notes.get(seat,{}).duplicate(),
		"examples":examples.duplicate(),"clue":clue.duplicate(true),"teaching":teaching.duplicate(true),
		"votes":last_votes.duplicate(true) if phase in ["result","end"] else {},"answered":ballots.keys(),
		"favor":favor.duplicate(),"knowledge":points if phase=="end" else [],"winner":winner}
