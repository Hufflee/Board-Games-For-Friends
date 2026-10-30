class_name KHRules
extends RefCounted
## «Хором!»: чистые правила на хосте. Раунды «Хором» / «Белая ворона» / «Блиц», блокнот на 6 строк,
## открытие ответов по ходам (ведущий первый), очки отмечают сами игроки («✓» / «✕»).
## Тесты: godot --headless --path . --script res://tests/test_khorom.gd

const SLOTS := 6
const MAX_TEXT := 40
const BLITZ_TIME := 60.0
const MIN_PLAYERS := 3
const MAX_PLAYERS := 8

var players: Array = []
var banked: Array = []  # очки прошлых раундов
var total_rounds := 6
var timer := 90  # секунд на письмо, 0 — без ограничения
var round_no := 0
var first_leader := 0
var leader := 0
var kind := "chorus"
var topics: Array = []  # одна тема или 6 тем блица
var phase := "write"  # write → reveal → round_end → … → game_over
var answers: Array = []  # [место][строка] — текст
var revealed: Array = []
var marked: Array = []
var ready: Array = []
var turn_index := 0  # позиция в очереди от ведущего
var blitz_row := 0
var time_left := 0.0
var winners: Array = []
var revision := 0
var _used_topics: Array = []
var _used_blitz: Array = []
var _rng := RandomNumberGenerator.new()


func new_game(seats: Array, options: Dictionary = {}) -> String:
	if seats.size() < MIN_PLAYERS or seats.size() > MAX_PLAYERS:
		return "Нужно от %d до %d игроков." % [MIN_PLAYERS, MAX_PLAYERS]
	players = seats.duplicate(true)
	total_rounds = clampi(int(options.get("rounds", 6)), 1, 30)
	timer = maxi(0, int(options.get("timer", 90)))
	if options.has("seed"):
		_rng.seed = int(options.seed)
	else:
		_rng.randomize()
	first_leader = int(options.get("leader", 0)) % players.size()
	banked.clear()
	for _i: int in players.size():
		banked.append(0)
	round_no = 0
	winners.clear()
	_start_round()
	return ""


func _start_round() -> void:
	kind = KHData.KINDS[round_no % KHData.KINDS.size()]
	leader = (first_leader + round_no) % players.size()
	topics = _draw(KHData.BLITZ, _used_blitz, SLOTS) if kind == "blitz" else _draw(KHData.TOPICS, _used_topics, 1)
	answers.clear()
	revealed.clear()
	marked.clear()
	ready.clear()
	for _i: int in players.size():
		var empty := []
		var no := []
		for _row: int in SLOTS:
			empty.append("")
			no.append(false)
		answers.append(empty)
		revealed.append(no.duplicate())
		marked.append(no.duplicate())
		ready.append(false)
	turn_index = 0
	blitz_row = 0
	time_left = (BLITZ_TIME if kind == "blitz" else float(timer)) if timer > 0 else 0.0
	phase = "write"


## Темы без повторов в партии; если пул кончился — начинаем его заново.
func _draw(pool: Array, used: Array, amount: int) -> Array:
	var free := []
	for topic: String in pool:
		if not used.has(topic):
			free.append(topic)
	if free.size() < amount:
		used.clear()
		free = pool.duplicate()
	var picked := []
	for _i: int in amount:
		var topic: String = free.pop_at(_rng.randi_range(0, free.size() - 1))
		picked.append(topic)
		used.append(topic)
	return picked


func seat_at(index: int) -> int:
	return (leader + index) % players.size()

func turn() -> int:
	return seat_at(turn_index) if phase == "reveal" else -1

func _hidden(seat: int, row: int) -> bool:
	return not str(answers[seat][row]).is_empty() and not revealed[seat][row]

func _has_hidden(seat: int) -> bool:
	for row: int in SLOTS:
		if _hidden(seat, row):
			return true
	return false

func filled(seat: int) -> int:
	var amount := 0
	for row: int in SLOTS:
		if not str(answers[seat][row]).is_empty():
			amount += 1
	return amount


## Очки текущего раунда: «Хором»/«Блиц» — отмеченные «✓»; «Белая ворона» — открытые минус отмеченные «✕».
func round_points(seat: int) -> int:
	var points := 0
	for row: int in SLOTS:
		if str(answers[seat][row]).is_empty() or not revealed[seat][row]:
			continue
		if kind == "crow":
			points += 0 if marked[seat][row] else 1
		elif marked[seat][row]:
			points += 1
	return points

func score(seat: int) -> int:
	return int(banked[seat]) + (round_points(seat) if phase in ["reveal", "round_end"] else 0)


## Похож ли ответ на чей-то уже открытый (в блице — на ту же тему).
func similar_open(seat: int, row: int) -> bool:
	var text := str(answers[seat][row])
	if text.is_empty():
		return false
	for other: int in players.size():
		if other == seat:
			continue
		for other_row: int in SLOTS:
			if kind == "blitz" and other_row != row:
				continue
			if revealed[other][other_row] and KHMatch.similar(text, str(answers[other][other_row])):
				return true
	return false

func can_reveal(seat: int, row: int) -> bool:
	if phase != "reveal" or seat < 0 or seat >= players.size() or row < 0 or row >= SLOTS or not _hidden(seat, row):
		return false
	if seat == turn() and (kind != "blitz" or row == blitz_row):
		return true
	return similar_open(seat, row)  # похожий ответ можно открыть вне очереди


func write(seat: int, row: int, text: String) -> bool:
	if phase != "write" or seat < 0 or seat >= players.size() or row < 0 or row >= SLOTS or ready[seat]:
		return false
	answers[seat][row] = text.strip_edges().left(MAX_TEXT)
	return true

func set_ready(seat: int, on: bool) -> bool:
	if phase != "write" or seat < 0 or seat >= players.size() or ready[seat] == on:
		return false
	ready[seat] = on
	if on and not ready.has(false):
		_start_reveal()
	return true

func _start_reveal() -> void:
	phase = "reveal"
	turn_index = 0
	blitz_row = 0
	time_left = 0.0
	_advance()

## Ход переходит сам, когда у активного не осталось скрытых ответов в текущей очереди.
func _advance() -> void:
	var n := players.size()
	if kind != "blitz":
		while turn_index < n and not _has_hidden(seat_at(turn_index)):
			turn_index += 1
		if turn_index >= n:
			phase = "round_end"
		return
	while true:
		if turn_index >= n:
			turn_index = 0
			blitz_row += 1
		if blitz_row >= SLOTS:
			phase = "round_end"
			return
		if _hidden(seat_at(turn_index), blitz_row):
			return
		turn_index += 1

func reveal(seat: int, row: int) -> bool:
	if not can_reveal(seat, row):
		return false
	revealed[seat][row] = true
	_advance()
	return true

## Не открывать оставшееся: ход дальше (в блице — только эта тема).
func pass_turn(seat: int) -> bool:
	if phase != "reveal" or seat != turn():
		return false
	turn_index += 1
	_advance()
	return true

func mark(seat: int, row: int) -> bool:
	if not phase in ["reveal", "round_end"] or seat < 0 or seat >= players.size() or row < 0 or row >= SLOTS:
		return false
	if str(answers[seat][row]).is_empty() or not revealed[seat][row]:
		return false
	marked[seat][row] = not marked[seat][row]
	return true

func next_round(host_authorized: bool) -> bool:
	if phase != "round_end" or not host_authorized:
		return false
	for seat: int in players.size():
		banked[seat] = int(banked[seat]) + round_points(seat)
	round_no += 1
	if round_no >= total_rounds:
		phase = "game_over"
		var best := -1
		for seat: int in players.size():
			best = maxi(best, int(banked[seat]))
		winners.clear()
		for seat: int in players.size():
			if int(banked[seat]) == best:
				winners.append(seat)
		return true
	_start_round()
	return true

## Время письма вышло — сразу к открытию. Возвращает true, если фаза сменилась.
func tick(delta: float) -> bool:
	if phase != "write" or time_left <= 0.0:
		return false
	time_left -= delta
	if time_left > 0.0:
		return false
	time_left = 0.0
	for seat: int in players.size():
		ready[seat] = true
	_start_reveal()
	revision += 1
	return true


func action(seat: int, action_kind: String, payload: Variant, host_authorized: bool = false) -> bool:
	if not payload is Dictionary:
		return false
	# Письмо идёт у всех одновременно — устаревшая ревизия ему не мешает; ходы открытия её проверяют.
	if not action_kind in ["write", "ready", "unready"] and (not payload.get("revision") is int or payload.revision != revision):
		return false
	if payload.has("row") and not payload.row is int:
		return false
	var row := int(payload.get("row", -1))
	var accepted := false
	match action_kind:
		"write":
			accepted = payload.get("text") is String and write(seat, row, payload.text)
		"ready":
			accepted = set_ready(seat, true)
		"unready":
			accepted = set_ready(seat, false)
		"reveal":
			accepted = reveal(seat, row)
		"mark":
			accepted = mark(seat, row)
		"pass":
			accepted = pass_turn(seat)
		"next":
			accepted = next_round(host_authorized)
	if accepted:
		revision += 1
	return accepted


## Вид для места: свои ответы целиком; у чужих — только заполненные строки и уже открытые тексты.
func get_view(seat: int) -> Dictionary:
	var books := []
	for owner: int in players.size():
		var rows := []
		for row: int in SLOTS:
			var text := str(answers[owner][row])
			var open: bool = revealed[owner][row]
			var mine := owner == seat
			rows.append({
				"filled": not text.is_empty(),
				"text": text if mine or open or phase == "game_over" else "",
				"open": open,
				"marked": marked[owner][row],
				"eye": mine and can_reveal(owner, row),
				"similar": (mine or open) and similar_open(owner, row) if phase != "write" else false,
			})
		books.append({"rows": rows, "filled": filled(owner), "ready": ready[owner] if phase == "write" else true,
			"points": round_points(owner) if phase in ["reveal", "round_end"] else 0})
	var scores := []
	for owner: int in players.size():
		scores.append(score(owner))
	return {"players": players.duplicate(true), "you": seat, "phase": phase, "kind": kind,
		"kind_name": KHData.KIND_NAMES[kind], "topics": topics.duplicate(), "leader": leader,
		"turn": turn(), "blitz_row": blitz_row, "round_no": round_no, "total_rounds": total_rounds,
		"time_left": time_left, "timer": timer, "books": books, "scores": scores,
		"winners": winners.duplicate(), "revision": revision}
