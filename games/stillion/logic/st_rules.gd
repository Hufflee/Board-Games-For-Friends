class_name STRules
extends RefCounted
## Правила «Стиллиона» (без UI), выполняются на хосте. Игроки стоят по кругу вокруг пушки.
## Раунд — одна тема («Страна», «Мороженое»…) и клавиатура из 24 букв. Пушка наводится на игрока и
## надувается (fuse): он называет ответ на тему на свободную букву — буква гаснет, пушка поворачивается
## к следующему по часовой стрелке. Не успел — выстрел (boom), минус жизнь, раунд закончен, новая тема.
## Буквы кончились — тоже новая тема (последний ответ ещё REVIEW_TIME можно оспорить).
## «Оспорить»: больше половины остальных живых игроков (1 на 1 — один) — ответ не засчитан, буква снова
## свободна, пушка возвращается к автору, время сначала. Оспорили второй раз подряд — автор проигрывает (выстрел).
## Устный режим (oral): игрок только жмёт букву мышью и говорит ответ вслух; проверяют оспариванием.
## Проверка: godot --headless --path . --script res://tests/test_stillion.gd

## Буквы клавиатуры: без й, ё, ю, э, ц, щ, ъ, ь, ы (ё в ответе считается за «е»).
const LETTERS := ["а", "б", "в", "г", "д", "е", "ж", "з", "и", "к", "л", "м", "н", "о", "п", "р", "с", "т", "у", "ф", "х", "ч", "ш", "я"]
const MAX_LIVES := 2  # жизней по умолчанию (настройка st_lives)
const ANSWER_TIME := 10.0  # время на ответ по умолчанию (настройка st_time)
const AIM_TIME := 0.9  # пушка поворачивается к игроку
const BOOM_TIME := 1.8  # выстрел, дым, потеря жизни
const NEW_Q_TIME := 2.2  # «Новая тема!»: пауза перед показом темы и фитиля
const REVIEW_TIME := 4.0  # буквы кончились: столько секунд ещё можно оспорить последний ответ

var players: Array = []  # {name, lives, alive, bot, last_answer}
var max_lives := MAX_LIVES  # задать до new_game()
var answer_time := ANSWER_TIME
var oral := false  # устный режим: ответ — нажатая буква, сам ответ говорят вслух
var hotseat := false  # один компьютер: «Оспорить» решает одно нажатие (решили вслух)
var phase := "new_q"  # new_q / aim / fuse / review / boom / game_over
var target := 0
var category: Dictionary = {}  # {cat, answers: [{name, alts, rarity}]}
var q_no := 0  # номер темы (для анимации смены)
var used: Array = []  # погасшие буквы раунда: {letter, name, seat}
var prev: Dictionary = {}  # последний засчитанный ответ, его можно оспорить: {seat, letter, name, retry}
var votes: Array = []  # места, нажавшие «Оспорить» по prev
var retry_seat := -1  # чей ответ только что оспорили: оспорят снова — проигрыш
var fuse_len := ANSWER_TIME
var fuse_t := 0.0
var phase_t := 0.0
var last: Dictionary = {}  # последнее событие для стола: {kind, seat, name, letter, no, …}
var event_no := 0
var winner := -1
var revision := 0
var rng := RandomNumberGenerator.new()
## Колода тем (индексы categories()): Net передаёт одну и ту же на всю сессию лобби,
## чтобы темы не повторялись между партиями; кончилась — перемешивается заново.
var deck: Array = []
var _bot_at := -1.0

static var _cats: Array = []


## Все темы: [{cat, hint, answers: [{name, alts: [норм. варианты], rarity}]}] из STCategories.TEXT.
## «Тема [подсказка]: …» — подсказка показывается под названием темы.
static func categories() -> Array:
	if not _cats.is_empty():
		return _cats
	for line: String in STCategories.TEXT.split("\n", false):
		var i := line.find(":")
		if i <= 0:
			continue
		var head := line.left(i).strip_edges()
		var hint := ""
		var h := head.find("[")
		if h > 0 and head.ends_with("]"):
			hint = head.substr(h + 1, head.length() - h - 2).strip_edges()
			head = head.left(h).strip_edges()
		var c := {"cat": head, "hint": hint, "answers": []}
		for raw: String in line.substr(i + 1).split(",", false):
			var alts: Array = []
			for v: String in raw.split("|", false):
				var n := STJudge.normalize(v)
				if n != "" and not alts.has(n):
					alts.append(n)
			if not alts.is_empty():
				(c.answers as Array).append({"name": raw.split("|")[0].strip_edges(), "alts": alts, "rarity": "c"})
		_cats.append(c)
	return _cats


func new_game(player_list: Array, use_bots: bool = false, seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	players.clear()
	for p: Dictionary in player_list:
		players.append({"name": str(p.get("name", "Игрок")), "lives": max_lives, "alive": true, "last_answer": "",
			"bot": bool(p.get("bot", false)) or (use_bots and bool(p.get("local", false)))})
	winner = -1
	_new_round(rng.randi_range(0, players.size() - 1))


func player_count() -> int:
	return players.size()


func alive_count() -> int:
	var n := 0
	for p: Dictionary in players:
		if p.alive:
			n += 1
	return n


## Действия игроков (Net): st_answer {text} (устно — {letter}), st_challenge.
func action(seat: int, kind: String, arg) -> bool:
	var a: Dictionary = arg if arg is Dictionary else {}
	match kind:
		"st_answer":
			if oral:
				return submit_letter(seat, str(a.get("letter", "")))
			return submit(seat, str(a.get("text", "")))
		"st_challenge":
			return challenge(seat)
	return false


## Игрок под прицелом напечатал ответ: засчитан, если первая буква есть на клавиатуре и ещё свободна.
func submit(seat: int, text: String) -> bool:
	if oral or phase != "fuse" or seat != target:
		return false
	var n := STJudge.normalize(text)
	if n.is_empty():
		return false
	var shown := text.strip_edges().left(40)
	var letter := n.left(1)
	if not LETTERS.has(letter):
		_event("wrong", seat, {"text": shown, "letter": letter, "why": "none"})
	elif letter_used(letter):
		_event("wrong", seat, {"text": shown, "letter": letter, "why": "used"})
	else:
		_accept(seat, letter, shown)
	return true


## Устный режим: игрок под прицелом нажал свободную букву (ответ сказал вслух).
func submit_letter(seat: int, letter: String) -> bool:
	letter = letter.to_lower()
	if not oral or phase != "fuse" or seat != target or not LETTERS.has(letter) or letter_used(letter):
		return false
	_accept(seat, letter, "")
	return true


func letter_used(letter: String) -> bool:
	for u: Dictionary in used:
		if u.letter == letter:
			return true
	return false


func letters_left() -> int:
	return LETTERS.size() - used.size()


## Сколько нажатий «Оспорить» нужно: больше половины живых людей, кроме автора (1 на 1 — одно); на одном компьютере — одно.
## Боты не оспаривают и в счёт не входят: ответы игроков по списку не проверяются, решают только люди.
func votes_needed() -> int:
	if prev.is_empty():
		return 0
	if hotseat:
		return 1
	var n := 0
	for s in players.size():
		if players[s].alive and not players[s].bot and s != int(prev.seat):
			n += 1
	return maxi(1, n / 2 + 1)


func can_challenge(seat: int) -> bool:
	if prev.is_empty() or not phase in ["aim", "fuse", "review"] or seat < 0 or seat >= players.size():
		return false
	if votes.has(seat) or (not hotseat and (not players[seat].alive or players[seat].bot)):
		return false
	return hotseat or seat != int(prev.seat)


## Нажали «Оспорить» на последний ответ. Набралось — ответ не засчитан.
func challenge(seat: int) -> bool:
	if not can_challenge(seat):
		return false
	votes.append(seat)
	if votes.size() >= votes_needed():
		_overturn()
	else:
		_event("vote", seat, {"of": int(prev.seat)})
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
			if _bot_at >= 0.0 and fuse_t >= _bot_at:
				_bot_at = -1.0
				_bot_answer()
				return true
			if fuse_t >= fuse_len:
				_boom(target)
				return true
		"review":
			if phase_t >= REVIEW_TIME:
				var from := int(prev.get("seat", target))
				_new_round(_next_alive(from))
				return true
		"boom":
			if phase_t >= BOOM_TIME:
				if alive_count() <= 1:
					_finish()
				else:
					_new_round(target if players[target].alive else _next_alive(target))
				return true
	return false


## Состояние для стола: тайн нет — все видят одно и то же.
func get_view(seat: int) -> Dictionary:
	var used_view: Array = []
	for u: Dictionary in used:
		used_view.append(u.duplicate())
	return {
		"game": "stillion", "seat": seat, "players": players.duplicate(true), "phase": phase, "target": target,
		# пока на экране «Новая тема!» — саму тему ещё не показываем никому
		"category": "" if phase == "new_q" else str(category.get("cat", "")),
		"hint": "" if phase == "new_q" else str(category.get("hint", "")), "q_no": q_no,
		"letters": LETTERS.duplicate(), "used": used_view,
		"prev": prev.duplicate(), "votes": votes.duplicate(), "votes_needed": votes_needed(),
		"can_challenge": can_challenge(seat), "retry_seat": retry_seat,
		"fuse_len": fuse_len, "fuse_t": fuse_t, "review_left": maxf(0.0, REVIEW_TIME - phase_t) if phase == "review" else 0.0,
		"oral": oral, "hotseat": hotseat,
		"last": last.duplicate(), "winner": winner, "revision": revision, "max_lives": max_lives,
	}


# --- внутреннее -----------------------------------------------------------------------


func _accept(seat: int, letter: String, name: String) -> void:
	_close_prev()
	used.append({"letter": letter, "name": name, "seat": seat})
	players[seat].last_answer = name if name != "" else "на «%s»" % letter.to_upper()
	prev = {"seat": seat, "letter": letter, "name": name, "retry": seat == retry_seat}
	votes = []
	_event("ok", seat, {"name": name, "letter": letter})
	if letters_left() <= 0:
		phase = "review"
		phase_t = 0.0
		_bot_at = -1.0
		_bump()
	else:
		_aim(_next_alive(seat))


## Окно оспаривания прошлого ответа закрылось без оспаривания.
func _close_prev() -> void:
	if not prev.is_empty() and bool(prev.retry):
		retry_seat = -1
	prev = {}
	votes = []


## Ответ оспорили: буква снова свободна, пушка возвращается к автору; второй раз подряд — выстрел.
func _overturn() -> void:
	var p := prev
	prev = {}
	votes = []
	for i in range(used.size() - 1, -1, -1):
		if used[i].letter == p.letter:
			used.remove_at(i)
	var s := int(p.seat)
	players[s].last_answer = ""
	if bool(p.retry):
		retry_seat = -1
		_boom(s, true)
		return
	retry_seat = s
	_event("challenged", s, {"name": p.name, "letter": p.letter})
	_aim(s)


func _boom(seat: int, challenged := false) -> void:
	target = seat
	var p: Dictionary = players[seat]
	p.lives = int(p.lives) - 1
	if int(p.lives) <= 0:
		p.lives = 0
		p.alive = false
	_close_prev()
	retry_seat = -1
	_bot_at = -1.0
	phase = "boom"
	phase_t = 0.0
	_event("boom", seat, {"out": not p.alive, "challenged": challenged})


## Новый раунд: новая тема, все буквы снова свободны; пауза «Новая тема!», потом наведение на seat.
func _new_round(seat: int) -> void:
	_close_prev()
	retry_seat = -1
	used.clear()
	_next_category()
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
	fuse_len = answer_time
	_bot_at = -1.0
	_bump()


func _next_category() -> void:
	var all := categories()
	if deck.is_empty():
		for i in all.size():
			deck.append(i)
		for i in range(deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t: int = deck[i]
			deck[i] = deck[j]
			deck[j] = t
		# новый круг не начинается с только что сыгранной темы
		var was := all.find(category)
		if deck.size() > 1 and int(deck.back()) == was:
			var t: int = deck[0]
			deck[0] = deck[deck.size() - 1]
			deck[deck.size() - 1] = t
	category = all[deck.pop_back()]
	fuse_len = answer_time
	q_no += 1


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


## Бот под прицелом: через случайное время называет ответ из списка темы на свободную букву или не успевает.
## Список нужен только ботам (на одном компьютере с «Добавленные — боты» и вместо отключившихся).
func _plan_bot() -> void:
	_bot_at = -1.0
	if not players[target].bot:
		return
	_bot_at = rng.randf_range(1.5, maxf(2.0, minf(fuse_len * 0.85, 6.0))) if rng.randf() < 0.85 else fuse_len + 1.0


func _bot_answer() -> void:
	var pool: Array = []
	for a: Dictionary in category.get("answers", []):
		var letter := str(a.alts[0]).left(1)
		if LETTERS.has(letter) and not letter_used(letter):
			pool.append(a)
	if pool.is_empty():
		return  # ничего не знает — ждёт выстрела
	var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	_accept(target, str(pick.alts[0]).left(1), "" if oral else str(pick.name))


func _event(kind: String, seat: int, extra: Dictionary) -> void:
	event_no += 1
	last = {"kind": kind, "seat": seat, "no": event_no}
	last.merge(extra)
	_bump()


func _bump() -> void:
	revision += 1


# --- Панель хоста (необязательные методы, вызывает Net на хосте) ---------------------------

## Жизни живого игрока (выбывшего не воскрешаем: очередь пушки уже без него).
func host_stats(seat: int) -> Array:
	if seat < 0 or seat >= players.size() or phase == "game_over" or not players[seat].alive:
		return []
	return [{"key": "lives", "label": "Жизни", "value": int(players[seat].lives), "min": 1, "max": maxi(max_lives, 9)}]


func host_set_stat(seat: int, key: String, value: int) -> bool:
	for stat: Dictionary in host_stats(seat):
		if str(stat.key) == key:
			players[seat].lives = clampi(value, int(stat.min), int(stat.max))
			_bump()
			return true
	return false


## Новая тема тому же игроку под прицелом (не во время выстрела).
func host_new_theme() -> bool:
	if not phase in ["new_q", "aim", "fuse", "review"]:
		return false
	_new_round(target)
	return true
