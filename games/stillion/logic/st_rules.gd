class_name STRules
extends RefCounted
## Правила «Стиллиона» (без UI), выполняются на хосте. Игроки стоят по кругу вокруг пушки.
## Пушка наводится на игрока (aim), надувается (fuse): успел напечатать подходящий ответ — пушка
## сдувается и поворачивается к следующему по часовой стрелке; не успел — выстрел (boom), минус жизнь.
## Ответ сначала ищется в списке вопроса (STJudge); если его там нет — ответ уходит на проверку jev
## (phase check: фитиль на паузе), результат приходит в resolve_external().
## Вопрос меняется, когда на нём прошло QUESTION_TIME секунд или двое потеряли жизнь (при смене цели).
## Проверка: godot --headless --path . --script res://tests/test_stillion.gd

const MAX_LIVES := 3  # жизней по умолчанию (настройка st_lives)
const METER_MAX := 20  # шкала ответов по умолчанию (настройка st_meter): заполнилась — +1 жизнь и с нуля
const POINTS := {"c": 1, "s": 2, "u": 3, "e": 4}  # Общеизвестно / Школьник / Умник / Эрудит
const QUESTION_TIME := 20.0
const LOSSES_PER_QUESTION := 2
const AIM_TIME := 0.9  # пушка поворачивается к игроку
const BOOM_TIME := 1.8  # выстрел, дым, потеря жизни
const FUSE_START := 12.0  # фитиль в начале каждого вопроса
const FUSE_MIN := 5.0
const FUSE_STEP := 1.0  # каждый верный ответ на этот вопрос — фитиль короче; новый вопрос — снова FUSE_START
const NEW_Q_TIME := 2.2  # «Новый вопрос!»: пауза перед показом вопроса и фитиля
const CHECK_TIMEOUT := 8.0  # jev не ответил — ответ не засчитан

var players: Array = []  # {name, lives, meter, parts, alive, bot}; parts — редкости ответов на шкале по порядку
var max_lives := MAX_LIVES  # задать до new_game()
var meter_max := METER_MAX
var casual := false  # «обычные игроки»: редкость ответов на ступень выше (см. perceived())
var phase := "new_q"  # new_q / aim / fuse / check / boom / game_over
var target := 0
var question: Dictionary = {}  # {cat, text, answers}
var q_no := 0  # номер вопроса (для анимации смены)
var q_time := 0.0
var q_losses := 0
var used: Array = []  # уже названные на этом вопросе: {name, rarity, seat}
var fuse_len := FUSE_START
var fuse_t := 0.0
var phase_t := 0.0
var pending: Dictionary = {}  # ответ на проверке jev: {seat, text, no}
var last: Dictionary = {}  # последнее событие для стола: {kind, seat, name, rarity, typo, text, no}
var event_no := 0
var winner := -1
var revision := 0
var external_check := false  # хост подключил jev: незнакомые ответы проверяются им
var rng := RandomNumberGenerator.new()
## Колода вопросов (индексы STQuestions.all()): Net передаёт одну и ту же на всю сессию лобби,
## чтобы вопросы не повторялись между партиями; кончилась — перемешивается заново.
var deck: Array = []
var _bot_at := -1.0


func new_game(player_list: Array, use_bots: bool = false, seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	players.clear()
	for p: Dictionary in player_list:
		players.append({"name": str(p.get("name", "Игрок")), "lives": max_lives, "meter": 0, "parts": [], "alive": true,
			"last_answer": "", "bot": bool(p.get("bot", false)) or (use_bots and bool(p.get("local", false)))})
	winner = -1
	target = rng.randi_range(0, players.size() - 1)
	_new_question(target)


func player_count() -> int:
	return players.size()


func alive_count() -> int:
	var n := 0
	for p: Dictionary in players:
		if p.alive:
			n += 1
	return n


## Действия игроков (Net): st_answer {text}.
func action(seat: int, kind: String, arg) -> bool:
	var a: Dictionary = arg if arg is Dictionary else {}
	match kind:
		"st_answer":
			return submit(seat, str(a.get("text", "")))
	return false


## Игрок под прицелом прислал ответ.
func submit(seat: int, text: String) -> bool:
	if phase != "fuse" or seat != target or STJudge.normalize(text).is_empty():
		return false
	players[seat].last_answer = text.strip_edges().left(60)
	var found := STJudge.lookup(question, text)
	if found.found:
		if _is_used(found.name):
			_event("used", seat, {"name": found.name, "text": text})
			return true
		_accept(seat, found.name, found.rarity, found.typo, text)
		return true
	if external_check:
		phase = "check"
		phase_t = 0.0
		pending = {"seat": seat, "text": text, "no": event_no + 1}
		_bump()
		return true
	_event("wrong", seat, {"text": text})
	return true


## Вердикт jev по ответу, которого нет в списке: ok, редкость (c/s/u/e) и как показывать ответ.
func resolve_external(no: int, ok: bool, rarity: String = "s", name: String = "") -> bool:
	if phase != "check" or pending.is_empty() or int(pending.no) != no:
		return false
	var seat: int = pending.seat
	var text: String = pending.text
	pending = {}
	phase = "fuse"
	var shown := name if name != "" else text.strip_edges()
	if ok and _is_used(shown):
		_event("used", seat, {"name": shown, "text": text})
	elif ok:
		_accept(seat, shown, rarity if POINTS.has(rarity) else "s", false, text)
	else:
		_event("wrong", seat, {"text": text})
	return true


## Время идёт только на хосте. true — состояние изменилось (разослать).
func tick(delta: float) -> bool:
	if phase == "game_over":
		return false
	phase_t += delta
	match phase:
		"new_q":
			if phase_t >= NEW_Q_TIME:
				_aim(target)
				return true
		"aim":
			if phase_t >= AIM_TIME:
				phase = "fuse"
				phase_t = 0.0
				fuse_t = 0.0
				_plan_bot()
				_bump()
				return true
		"fuse":
			fuse_t += delta
			q_time += delta
			if _bot_at >= 0.0 and fuse_t >= _bot_at:
				_bot_at = -1.0
				_bot_answer()
				return true
			if fuse_t >= fuse_len:
				_boom()
				return true
		"check":
			if phase_t >= CHECK_TIMEOUT and not pending.is_empty():
				return resolve_external(int(pending.no), false)
		"boom":
			if phase_t >= BOOM_TIME:
				if alive_count() <= 1:
					_finish()
				else:
					_turn_to(_next_alive(target))
				return true
	return false


## Состояние для стола: тайн нет — все видят одно и то же.
func get_view(seat: int) -> Dictionary:
	var used_view: Array = []
	for u: Dictionary in used:
		used_view.append(u.duplicate())
	return {
		"game": "stillion", "seat": seat, "players": players.duplicate(true), "phase": phase, "target": target,
		# пока на экране «Новый вопрос!» — сам вопрос ещё не показываем никому
		"question": {"cat": "" if phase == "new_q" else question.get("cat", ""), "text": "" if phase == "new_q" else question.get("text", ""), "no": q_no},
		"q_left": maxf(0.0, QUESTION_TIME - q_time), "used": used_view,
		"fuse_len": fuse_len, "fuse_t": fuse_t, "checking": phase == "check",
		"last": last.duplicate(), "winner": winner, "revision": revision,
		"max_lives": max_lives, "meter_max": meter_max,
	}


# --- внутреннее -----------------------------------------------------------------------

## Редкость с учётом настройки «обычные игроки»: умник → эрудит, школьник → умник, а вторая половина
## общеизвестных ответов вопроса (список идёт от самых очевидных) → школьник. Ответы от jev — без списка: c не меняется.
func perceived(name: String, rarity: String) -> String:
	if not casual:
		return rarity
	match rarity:
		"u":
			return "e"
		"s":
			return "u"
		"c":
			var commons: Array = []
			for a: Dictionary in question.get("answers", []):
				if a.rarity == "c":
					commons.append(a.name)
			var i := commons.find(name)
			if i >= 0 and i >= ceili(commons.size() / 2.0):
				return "s"
	return rarity


func _accept(seat: int, name: String, rarity: String, typo: bool, text: String) -> void:
	players[seat].last_answer = text.strip_edges().left(60)
	rarity = perceived(name, rarity)
	used.append({"name": name, "rarity": rarity, "seat": seat})
	var p: Dictionary = players[seat]
	p.meter = int(p.meter) + int(POINTS[rarity])
	(p.parts as Array).append(rarity)
	var healed := false
	if int(p.meter) >= meter_max:
		p.meter = 0
		p.parts = []
		if int(p.lives) < max_lives:
			p.lives = int(p.lives) + 1
			healed = true
	fuse_len = maxf(FUSE_MIN, fuse_len - FUSE_STEP)
	_event("ok", seat, {"name": name, "rarity": rarity, "typo": typo, "text": text, "healed": healed})
	_turn_to(_next_alive(seat))


func _boom() -> void:
	var p: Dictionary = players[target]
	p.lives = int(p.lives) - 1
	if int(p.lives) <= 0:
		p.lives = 0
		p.alive = false
	q_losses += 1
	_bot_at = -1.0
	phase = "boom"
	phase_t = 0.0
	_event("boom", target, {"out": not p.alive})


## Пушка поворачивается к следующему; на смене цели — новый вопрос, если пора.
func _turn_to(seat: int) -> void:
	if q_time >= QUESTION_TIME or q_losses >= LOSSES_PER_QUESTION or _unused_left() == 0:
		_new_question(seat)
	else:
		_aim(seat)


## Смена вопроса: пауза «Новый вопрос!» (NEW_Q_TIME), фитиль — снова полный, потом наведение на seat.
func _new_question(seat: int) -> void:
	_next_question()
	target = seat
	phase = "new_q"
	phase_t = 0.0
	fuse_t = 0.0
	_bot_at = -1.0
	_bump()


func _aim(seat: int) -> void:
	target = seat
	phase = "aim"
	phase_t = 0.0
	fuse_t = 0.0
	_bot_at = -1.0
	_bump()


func _next_question() -> void:
	var all := STQuestions.all()
	if deck.is_empty():
		for i in all.size():
			deck.append(i)
		for i in range(deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t: int = deck[i]
			deck[i] = deck[j]
			deck[j] = t
		# новый круг не начинается с только что заданного вопроса
		var last := all.find(question)
		if deck.size() > 1 and int(deck.back()) == last:
			var t: int = deck[0]
			deck[0] = deck[deck.size() - 1]
			deck[deck.size() - 1] = t
	question = all[deck.pop_back()]
	fuse_len = FUSE_START
	q_no += 1
	q_time = 0.0
	q_losses = 0
	used.clear()


func _next_alive(from: int) -> int:
	for k in range(1, players.size() + 1):
		var s := (from + k) % players.size()
		if players[s].alive:
			return s
	return from


func _finish() -> void:
	phase = "game_over"
	winner = -1
	for s in players.size():
		if players[s].alive:
			winner = s
	_bump()


## Назван ли уже этот ответ — или почти такой же: синонимы одного ответа и ответы, отличающиеся
## только номером в конце (dust / dust 2, GTA IV / GTA V), считаются одним.
func _is_used(name: String) -> bool:
	var mine := _bases(name)
	for u: Dictionary in used:
		for b in _bases(str(u.name)):
			if mine.has(b):
				return true
	return false


## Основы всех написаний ответа (имя + синонимы из списка вопроса, если он там есть).
func _bases(name: String) -> Dictionary:
	var out := {}
	var k := STJudge.key(name)
	out[STJudge.base(k)] = true
	for a: Dictionary in question.get("answers", []):
		if STJudge.key(a.name) == k or (a.alts as Array).has(k):
			for alt: String in a.alts:
				out[STJudge.base(alt)] = true
	return out


func _unused_left() -> int:
	var n := 0
	for a: Dictionary in question.get("answers", []):
		if not _is_used(a.name):
			n += 1
	return n


## Бот под прицелом: через случайное время называет незанятый ответ (чаще — очевидный) или не успевает.
func _plan_bot() -> void:
	_bot_at = -1.0
	if not players[target].bot:
		return
	_bot_at = rng.randf_range(1.5, fuse_len * 0.95) if rng.randf() < 0.8 else fuse_len + 1.0


func _bot_answer() -> void:
	var weights := {"c": 6.0, "s": 3.0, "u": 1.2, "e": 0.4}
	var pool: Array = []
	var total := 0.0
	for a: Dictionary in question.answers:
		if not _is_used(a.name):
			pool.append(a)
			total += float(weights[a.rarity])
	if pool.is_empty():
		return  # ответов не осталось — бот ждёт выстрела
	var r := rng.randf() * total
	for a: Dictionary in pool:
		r -= float(weights[a.rarity])
		if r <= 0.0:
			_accept(target, a.name, a.rarity, false, a.name)
			return
	var a0: Dictionary = pool.back()
	_accept(target, a0.name, a0.rarity, false, a0.name)


func _event(kind: String, seat: int, extra: Dictionary) -> void:
	event_no += 1
	last = {"kind": kind, "seat": seat, "no": event_no}
	last.merge(extra)
	_bump()


func _bump() -> void:
	revision += 1
