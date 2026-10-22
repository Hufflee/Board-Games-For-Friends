class_name AARules
extends RefCounted
## Движок «Алольского атлета» (по правилам Magical Athlete). 2–6 игроков.
## Драфт: в ряд выкладывают 2N гонщиков, игроки змейкой берут по одному, пока у каждого не будет 4.
## 4 гонки на 4 трассах. Перед гонкой все тайно выбирают гонщика (каждый — один раз за игру).
## Ход: бросок кубика — «основной ход», гонщик идёт на столько клеток. Умения меняют всё.
## Гонка кончается, когда финишировали двое: 1-е место — золото (3/4/4/5 очков), 2-е — серебро (1/2/2/3).
## Бронзовые клетки дают очки сразу. Обморок — пропуск следующего основного хода.
##
## Фазы: draft → pick → race (turn / prompt) → race_result → … → game_over.
## Выборы игрока по умениям — через prompt: {seat, kind, options:[{v, label}], ctx}.
## Реакции на чужих ходах (дуэли, «могу» на чужом ходу) решаются автоматически.

const DRAFT_EACH := 4

var players: Array = []
var rng := RandomNumberGenerator.new()
var phase := "setup"
var deck: Array = []  # колода гонщиков (id)
var line: Array = []  # драфт: выложенные гонщики
var draft_seq: Array = []  # очередь драфта (места)
var teams: Array = []  # места -> [id]
var used: Array = []  # места -> [id] уже бежавшие
var scores: Array = []
var bronze: Array = []  # места -> бронзовые очки (для показа)
var race_no := 0
var track := "mele"
var picks: Array = []  # места -> id выбранного гонщика ("" — ещё нет)
var forks: Array = []  # места -> {узел развилки: следующий узел}
var history: Array = []  # [{track, places: [место, …], racers: [id по местам]}]
var start_seat := 0

# гонка
var rc: Array = []  # места -> гонщик {id, power, pos, tripped, out, place, moved_first, ...}
var current := 0
var turn_no := 0
var finished: Array = []  # места в порядке финиша
var prompt := {}
var stage := ""  # этап хода: pre / roll / done
var pre_queue: Array = []  # оставшиеся умения перед основным ходом
var roll := 0  # бросок текущего основного хода
var rolled := false
var main_bonus := 0  # прибавка к основному ходу от умений перед ним
var skip_main := false
var extra_turn := false
var next_override := -1  # Картана
var turn_start_pos := 0
var log: Array = []
var last_roll := {}  # {seat, v, base} — для анимации
var _depth := 0  # защита от бесконечных цепочек умений

var _nodes: Array = []
var _prev: Array = []
var _dist: Array = []
var _corner: Array = []


# =============================================================================
# Подготовка
# =============================================================================

func new_game(player_list: Array, seed_value: int = 0) -> void:
	players = player_list.duplicate(true)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var n := players.size()
	deck = AAData.all_ids()
	_shuffle(deck)
	teams = []
	used = []
	scores = []
	bronze = []
	for s in n:
		teams.append([])
		used.append([])
		scores.append(0)
		bronze.append(0)
	line = []
	for i in 2 * n:
		line.append(deck.pop_back())
	start_seat = rng.randi_range(0, n - 1)
	draft_seq = []
	for rnd in DRAFT_EACH / 2:
		var first := (start_seat + rnd) % n
		var order := []
		for k in n:
			order.append((first + k) % n)
		draft_seq.append_array(order)
		var rev := order.duplicate()
		rev.reverse()
		draft_seq.append_array(rev)
	race_no = 0
	history = []
	log = []
	phase = "draft"


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func drafter() -> int:
	return int(draft_seq[0]) if phase == "draft" and not draft_seq.is_empty() else -1


func draft(seat: int, id: String) -> bool:
	if phase != "draft" or seat != drafter() or not id in line:
		return false
	line.erase(id)
	teams[seat].append(id)
	draft_seq.pop_front()
	_log(seat, "берёт гонщика: %s" % rname(id))
	if line.is_empty() and not draft_seq.is_empty():
		for i in 2 * players.size():
			if not deck.is_empty():
				line.append(deck.pop_back())
	if draft_seq.is_empty():
		_start_pick()
	return true


func auto_draft() -> void:
	if phase == "draft" and not line.is_empty():
		draft(drafter(), line[rng.randi_range(0, line.size() - 1)])


func _start_pick() -> void:
	track = AAData.TRACK_ORDER[race_no % 4]
	_load_track()
	picks = []
	forks = []
	for s in players.size():
		picks.append("")
		forks.append({})
	phase = "pick"


## Тайный выбор гонщика на гонку (+ куда сворачивать на развилках).
func pick(seat: int, id: String, fork_choice: Dictionary = {}) -> bool:
	if phase != "pick" or picks[seat] != "" or not id in teams[seat] or id in used[seat]:
		return false
	picks[seat] = id
	var fc := {}
	for f in fork_nodes():
		var opts: Array = _nodes[f]["next"]
		fc[f] = int(fork_choice.get(f, fork_choice.get(str(f), opts[rng.randi_range(0, opts.size() - 1)])))
		if not fc[f] in opts:
			fc[f] = opts[0]
	forks[seat] = fc
	if not picks.has(""):
		_start_race()
	return true


func auto_pick(seat: int) -> void:
	var left: Array = teams[seat].filter(func(x): return not x in used[seat])
	pick(seat, left[rng.randi_range(0, left.size() - 1)])


func fork_nodes() -> Array:
	var out := []
	for i in _nodes.size():
		if (_nodes[i]["next"] as Array).size() > 1:
			out.append(i)
	return out


# =============================================================================
# Трасса
# =============================================================================

func _load_track() -> void:
	_nodes = AATracks.DATA[track]["nodes"]
	var n := _nodes.size()
	_prev = []
	for i in n:
		_prev.append([])
	for i in n:
		for j in _nodes[i]["next"]:
			_prev[j].append(i)
	_dist = []
	_dist.resize(n)
	# расстояние до финиша: обратный обход (графы маленькие)
	for i in n:
		_dist[i] = 999
	var changed := true
	while changed:
		changed = false
		for i in n:
			var nx: Array = _nodes[i]["next"]
			var d := 1 if nx.is_empty() else 999
			for j in nx:
				d = mini(d, int(_dist[j]) + 1)
			if d < int(_dist[i]):
				_dist[i] = d
				changed = true
	_corner = []
	for i in n:
		var c := false
		if not _prev[i].is_empty() and (_nodes[i]["next"] as Array).size() == 1:
			var p: Dictionary = _nodes[_prev[i][0]]
			var q: Dictionary = _nodes[_nodes[i]["next"][0]]
			var a := Vector2(_nodes[i]["x"] - p["x"], _nodes[i]["y"] - p["y"]).normalized()
			var b := Vector2(q["x"] - _nodes[i]["x"], q["y"] - _nodes[i]["y"]).normalized()
			c = a.dot(b) < 0.5
		_corner.append(c)


## Расстояние до финиша (меньше — ближе). Старт -1, финиш -2.
func dist(pos: int) -> int:
	if pos == -2:
		return 0
	if pos == -1:
		return int(_dist[0]) + 1
	return int(_dist[pos])


func _next(seat: int, pos: int) -> int:
	if pos == -1:
		return 0
	var nx: Array = _nodes[pos]["next"]
	if nx.is_empty():
		return -2
	if nx.size() > 1:
		return int(forks[seat].get(pos, nx[0]))
	return int(nx[0])


func _back(seat: int, pos: int) -> int:
	if pos <= 0:
		return -1
	var pv: Array = _prev[pos]
	if pv.size() > 1:
		# слияние веток: назад — по своей ветке
		for p in pv:
			if _on_route(seat, p):
				return p
	return int(pv[0]) if not pv.is_empty() else -1


func _on_route(seat: int, node: int) -> bool:
	var p := -1
	for i in 200:
		p = _next(seat, p)
		if p == node:
			return true
		if p < 0:
			return false
	return false


func node_type(pos: int) -> String:
	return str(_nodes[pos]["t"]) if pos >= 0 else ""


# =============================================================================
# Гонка: служебное
# =============================================================================

func rname(id: String) -> String:
	return str(AAData.racer(id).get("name", id))


func pname(s: int) -> String:
	return players[s]["name"] if s >= 0 and s < players.size() else "?"


func _log(seat: int, text: String) -> void:
	log.append({"seat": seat, "race": race_no, "text": text})
	if log.size() > 120:
		log.pop_front()


func active(s: int) -> bool:
	return s >= 0 and s < rc.size() and not rc[s]["out"] and rc[s]["pos"] != -2


## Действующее умение гонщика (Мимикью копирует лидера).
func power(s: int) -> String:
	var p: String = rc[s]["power"]
	if p == "mimikyu":
		var lead := _leaders().filter(func(x): return x != s and rc[x]["power"] != "mimikyu")
		if not lead.is_empty():
			return str(rc[lead[0]]["power"])
	return p


func _has(s: int, pw: String) -> bool:
	return active(s) and power(s) == pw


## Места гонщиков с умением pw (кроме except).
func _with(pw: String, except: int = -99) -> Array:
	var out := []
	for s in rc.size():
		if s != except and _has(s, pw):
			out.append(s)
	return out


func _at(pos: int, except: int = -99) -> Array:
	var out := []
	for s in rc.size():
		if s != except and active(s) and rc[s]["pos"] == pos:
			out.append(s)
	return out


func _leaders() -> Array:
	var best := 9999
	var out := []
	for s in rc.size():
		if active(s):
			var d := dist(rc[s]["pos"])
			if d < best:
				best = d
				out = [s]
			elif d == best:
				out.append(s)
	return out


func _lasts() -> Array:
	var worst := -1
	var out := []
	for s in rc.size():
		if active(s):
			var d := dist(rc[s]["pos"])
			if d > worst:
				worst = d
				out = [s]
			elif d == worst:
				out.append(s)
	return out


## Место в гонке (1 — лидер) по расстоянию до финиша.
func rank(s: int) -> int:
	var d := dist(rc[s]["pos"])
	var r := 1
	for o in rc.size():
		if o != s and active(o) and dist(rc[o]["pos"]) < d:
			r += 1
	return r + finished.size()


## Сработало умение — Космог проходит 1.
func _fired(s: int, what: String = "") -> void:
	if what != "":
		_log(s, what)
	if _depth > 6:
		return
	for c in _with("cosmog", s):
		_depth += 1
		_move(c, 1, false, "Космог: чужое умение — +1")
		_depth -= 1


func _add_points(s: int, v: int, why: String) -> void:
	scores[s] = maxi(0, scores[s] + v)
	_log(s, "%s %+d очк." % [why, v])


func _faint(s: int, why: String = "") -> void:
	if not active(s) or rc[s]["tripped"]:
		return
	rc[s]["tripped"] = true
	_log(s, "%s — обморок%s" % [rname(rc[s]["id"]), (" (%s)" % why) if why != "" else ""])
	if _has(s, "pyukumuku") and _depth < 6:
		# «Нутро наружу»: тянет за собой лидера
		var t := _leaders().filter(func(x): return x != s)
		if not t.is_empty():
			_depth += 1
			_fired(s, "Пьюкумуку утаскивает за собой %s" % rname(rc[t[0]]["id"]))
			_faint(t[0], "Пьюкумуку")
			_depth -= 1


# =============================================================================
# Старт гонки
# =============================================================================

func _start_race() -> void:
	rc = []
	finished = []
	for s in players.size():
		var id: String = picks[s]
		used[s].append(id)
		rc.append({"id": id, "power": id, "pos": -1, "tripped": false, "out": false, "first_done": false,
			"minior_up": false, "naga": 0, "gum": {}, "sol": 0, "lunala": -1, "sensu": -1, "xurk": "",
			"tsar_used": false, "hug": -1, "steal": -1})
	phase = "race"
	turn_no = 0
	_log(-1, "Гонка %d: %s" % [race_no + 1, AAData.TRACKS[track]["name"]])
	for s in rc.size():
		_log(s, "выходит на старт: %s" % rname(rc[s]["id"]))
	# умения «перед гонкой»
	for s in rc.size():
		match rc[s]["power"]:
			"golisopod":
				_add_points(s, 4, "Голисопод: перед гонкой")
			"marowak", "necrozma":
				var pool := _prev_racers(rc[s]["power"] == "necrozma")
				if not pool.is_empty():
					var pick_id: String = pool[rng.randi_range(0, pool.size() - 1)]
					if not players[s].get("bot", false):
						_ask(s, "copy", pool.map(func(x): return {"v": x, "label": rname(x)}), {"src": rc[s]["power"]})
					else:
						rc[s]["power"] = pick_id
						_fired(s, "%s бежит с умением: %s" % [rname(rc[s]["id"]), rname(pick_id)])
			"silvally":
				var three := []
				for k in 3:
					if not deck.is_empty():
						three.append(deck.pop_back())
				if not three.is_empty():
					if players[s].get("bot", false):
						rc[s]["power"] = three[0]
						_fired(s, "Сильвалли: система RKS — %s" % rname(three[0]))
					else:
						_ask(s, "copy", three.map(func(x): return {"v": x, "label": rname(x)}), {"src": "silvally"})
	# первый ход — у первого игрока гонки (ходы запускает step())
	current = start_seat
	stage = "start"


func _prev_racers(winners: bool) -> Array:
	var out := []
	for h in history:
		var places: Array = h["places"]
		for s in h["racers"].size():
			var id: String = h["racers"][s]
			var won: bool = not places.is_empty() and places[0] == s
			if won == winners:
				out.append(id)
	return out


# =============================================================================
# Ход
# =============================================================================

func _begin_turn() -> void:
	if phase != "race":
		return
	stage = "turn"
	var guard := 0
	while not active(current):
		current = (current + 1) % rc.size()
		guard += 1
		if guard > rc.size():
			_end_race()
			return
	turn_no += 1
	var s := current
	var r: Dictionary = rc[s]
	turn_start_pos = r["pos"]
	roll = 0
	rolled = false
	main_bonus = 0
	skip_main = false
	extra_turn = false
	r["tsar_used"] = false
	r["naga"] = 0
	# Наганадел и Царина: «до моего следующего хода»
	if r["xurk"] != "" and not s in _lasts():
		r["xurk"] = ""
	# начало хода: блокады, обмороки, кражи
	if r["tripped"]:
		r["tripped"] = false
		skip_main = true
		_log(s, "%s приходит в себя — без основного хода" % rname(r["id"]))
	for k in _with("stakataka", s):
		if r["pos"] >= 0 and rc[k]["pos"] >= 0 and _next(s, r["pos"]) == rc[k]["pos"]:
			skip_main = true
			_fired(k, "Стакатака блокирует: %s пропускает основной ход" % rname(r["id"]))
	var others_alive := range(rc.size()).filter(func(o): return o != s and active(o)).size()
	if _has(s, "raichu") and _leaders() == [s] and r["pos"] != -1 and others_alive > 0:
		skip_main = true
		_fired(s, "Райчу один в лидерах — пропускает основной ход")
	if _has(s, "buzzwole"):
		for o in _at(r["pos"], s):
			if r["pos"] >= 0 and scores[o] > 0:
				scores[o] -= 1
				scores[s] += 1
				skip_main = true
				_fired(s, "Баззвол забирает очко у %s" % pname(o))
				break
	if _has(s, "dhelmise") and _lasts() == [s]:
		_add_points(s, 1, "Дельмайс один на последнем месте:")
		_fired(s)
	if _has(s, "lunala") and not r["first_done"] and r["lunala"] < 0:
		var opts := []
		for o in rc.size():
			if o != s:
				opts.append({"v": o, "label": rname(rc[o]["id"])})
		if players[s].get("bot", false):
			r["lunala"] = int(_leaders()[0]) if _leaders()[0] != s else int(opts[0]["v"])
			_fired(s, "Лунала предсказывает победу: %s" % rname(rc[r["lunala"]]["id"]))
		else:
			_ask(s, "lunala", opts, {})
			return
	_pre_main()


## Умения перед основным ходом (по очереди; у человека — вопросы).
func _pre_main() -> void:
	var s := current
	if skip_main:
		_end_turn()
		return
	pre_queue = []
	match power(s):
		"dugtrio", "lurantis", "hakamo_o", "oricorio_pom_pom", "magearna", "naganadel", "xurkitree", "zeraora", "oricorio_pa_u", "passimian", "solgaleo", "gumshoos":
			pre_queue.append(power(s))
		"oricorio_sensu":
			if not rc[s]["first_done"]:
				pre_queue.append("oricorio_sensu")
		"palossand":
			_palossand(s)
	stage = "pre"
	_next_pre()


func _next_pre() -> void:
	var s := current
	while not pre_queue.is_empty():
		var pw: String = pre_queue.pop_front()
		var q := _pre_question(s, pw)
		if q.is_empty():
			continue
		if players[s].get("bot", false):
			_pre_answer(s, pw, _bot_pre(s, pw, q))
			if phase != "race" or current != s:
				return
			if stage == "done":
				return
			continue
		_ask(s, "pre", q["options"], {"pw": pw, "q": q["text"]})
		return
	stage = "roll"
	if players[s].get("bot", false):
		do_roll(s)


## Вопрос по умению перед основным ходом: {text, options:[{v, label}]} или {} — если не к месту.
func _pre_question(s: int, pw: String) -> Dictionary:
	var r: Dictionary = rc[s]
	var no := {"v": "no", "label": "Не использовать"}
	match pw:
		"dugtrio":
			var opts := []
			for i in _nodes.size():
				if _at(i, s).size() == 2:
					opts.append({"v": i, "label": "Клетка %d" % (i + 1)})
			if opts.is_empty():
				return {}
			return {"text": "Дагтрио: перенестись на клетку с двумя гонщиками?", "options": opts + [no]}
		"lurantis":
			var opts := []
			for o in rc.size():
				if o != s and active(o) and rc[o]["pos"] != r["pos"]:
					opts.append({"v": o, "label": rname(rc[o]["id"])})
			if opts.is_empty() or r["pos"] < 0:
				return {}
			return {"text": "Лурантис: притянуть гонщика на свою клетку?", "options": opts + [no]}
		"hakamo_o":
			return {"text": "Хакамо-о: отодвинуть всех на 1 клетку от себя?", "options": [{"v": "yes", "label": "Да"}, no]}
		"oricorio_pom_pom":
			return {"text": "Пом-пом: последние проходят 2, а вы — 1?", "options": [{"v": "yes", "label": "Да"}, no]}
		"magearna":
			return {"text": "Магирна: загадать чёт или нечет?", "options": [{"v": "even", "label": "Чёт (+3)"}, {"v": "odd", "label": "Нечет (+3)"}, no]}
		"naganadel":
			return {"text": "Наганадел: назовите число — каждый раз, когда оно выпадет, +1 клетка", "options": [1, 2, 3, 4, 5, 6].map(func(x): return {"v": x, "label": str(x)})}
		"xurkitree":
			if _lasts() != [s]:
				return {}
			return {"text": "Ксуркитри: какой цвет клеток бьёт током?", "options": [["red", "Красный"], ["blue", "Синий"], ["green", "Зелёный"], ["yellow", "Жёлтый"], ["pink", "Розовый"]].map(func(c): return {"v": c[0], "label": c[1]}) + [no]}
		"zeraora":
			return {"text": "Зераора: не бросать кубик и пройти 5?", "options": [{"v": "yes", "label": "Пройти 5"}, {"v": "no", "label": "Бросить кубик"}]}
		"oricorio_pa_u":
			var opts := []
			for o in rc.size():
				if o != s and active(o) and rc[o]["pos"] != r["pos"]:
					opts.append({"v": o, "label": "Поменяться с: " + rname(rc[o]["id"])})
			if opts.is_empty():
				return {}
			return {"text": "Па-у: вместо броска поменяться местами?", "options": opts + [{"v": "no", "label": "Бросить кубик"}]}
		"passimian":
			var opts := []
			for o in rc.size():
				if o != s and active(o):
					opts.append({"v": o, "label": "Отдать ход: " + rname(rc[o]["id"])})
			if opts.is_empty():
				return {}
			return {"text": "Пассимиан: отдать основной ход и сразу получить ещё один?", "options": opts + [no]}
		"solgaleo":
			return {"text": "Солгалео: какое число выпадет? Угадаете — ещё один ход", "options": [1, 2, 3, 4, 5, 6].map(func(x): return {"v": x, "label": str(x)}) + [no]}
		"gumshoos":
			var opts := []
			for o in rc.size():
				if o != s and active(o):
					for v in [3, 4, 5, 6]:
						opts.append({"v": "%d:%d" % [o, v], "label": "%s — %d" % [rname(rc[o]["id"]), v]})
			if opts.is_empty():
				return {}
			return {"text": "Гамшус: угадайте бросок соперника", "options": opts + [no]}
		"oricorio_sensu":
			var opts := []
			for o in rc.size():
				if o != s and active(o):
					opts.append({"v": o, "label": rname(rc[o]["id"])})
			if opts.is_empty():
				return {}
			return {"text": "Сэнсу: выберите партнёра по танцу", "options": opts}
	return {}


func _bot_pre(s: int, pw: String, q: Dictionary) -> Variant:
	var opts: Array = q["options"]
	match pw:
		"zeraora":
			return "yes"
		"hakamo_o", "oricorio_pom_pom":
			return "yes" if rng.randf() < 0.6 else "no"
		"magearna":
			return ["even", "odd"][rng.randi() % 2] if rng.randf() < 0.7 else "no"
		"naganadel", "solgaleo":
			return rng.randi_range(1, 6)
		"lurantis":
			return "no" if rng.randf() < 0.5 else opts[0]["v"]
		"dugtrio":
			var best = "no"
			var bd := dist(rc[s]["pos"])
			for o in opts:
				if o["v"] is int and dist(int(o["v"])) < bd:
					best = o["v"]
					bd = dist(int(o["v"]))
			return best
		"oricorio_pa_u":
			var best = "no"
			var bd := dist(rc[s]["pos"]) - 3
			for o in opts:
				if o["v"] is int and dist(rc[o["v"]]["pos"]) < bd:
					best = o["v"]
					bd = dist(rc[o["v"]]["pos"])
			return best
		"passimian":
			return "no"
	return opts[rng.randi_range(0, opts.size() - 1)]["v"]


func _pre_answer(s: int, pw: String, v: Variant) -> void:
	if str(v) == "no":
		return
	var r: Dictionary = rc[s]
	match pw:
		"dugtrio":
			r["pos"] = int(v)
			_fired(s, "Дагтрио прорывает подкоп на клетку %d" % (int(v) + 1))
			_land(s, false)
		"lurantis":
			var o := int(v)
			rc[o]["pos"] = r["pos"]
			_fired(s, "Лурантис притягивает %s" % rname(rc[o]["id"]))
		"hakamo_o":
			var fw := 0
			for o in rc.size():
				if o != s and active(o) and rc[o]["pos"] >= 0:
					var ahead := dist(rc[o]["pos"]) < dist(r["pos"])
					if ahead:
						_move(o, 1, false, "")
						fw += 1
					elif rc[o]["pos"] != r["pos"]:
						_move(o, -1, false, "")
			main_bonus += fw
			_fired(s, "Хакамо-о звенит чешуёй: +%d к ходу" % fw)
		"oricorio_pom_pom":
			for o in _lasts():
				if o != s:
					_move(o, 2, false, "")
			_fired(s, "Пом-пом подбадривает последних")
			_move(s, 1, false, "")
		"magearna":
			r["mag"] = str(v)
		"naganadel":
			r["naga"] = int(v)
			_fired(s, "Наганадел называет число %d" % int(v))
		"xurkitree":
			r["xurk"] = str(v)
			_fired(s, "Ксуркитри: клетки цвета «%s» бьют током" % str(v))
		"zeraora":
			_fired(s, "Зераора: удар грома — 5 клеток")
			_main_move(s, 5, 5, true)
			stage = "done"
			_end_turn()
		"oricorio_pa_u":
			var o := int(v)
			var p: int = r["pos"]
			r["pos"] = rc[o]["pos"]
			rc[o]["pos"] = p
			r["first_done"] = true
			_fired(s, "Па-у меняется местами с %s" % rname(rc[o]["id"]))
			stage = "done"
			_end_turn()
		"passimian":
			var o := int(v)
			_fired(s, "Пассимиан отдаёт ход %s" % rname(rc[o]["id"]))
			var d := rng.randi_range(1, 6)
			_main_move(o, d, d, false)
		"solgaleo":
			r["sol"] = int(v)
		"gumshoos":
			var parts := str(v).split(":")
			r["gum"] = {"who": int(parts[0]), "v": int(parts[1])}
		"oricorio_sensu":
			r["sensu"] = int(v)


## Ответ игрока на вопрос.
func answer(seat: int, v: Variant) -> bool:
	if prompt.is_empty() or int(prompt["seat"]) != seat:
		return false
	var ok := false
	for o in prompt["options"]:
		if str(o["v"]) == str(v):
			v = o["v"]
			ok = true
	if not ok:
		return false
	var p := prompt
	prompt = {}
	match p["kind"]:
		"copy":
			rc[seat]["power"] = str(v)
			_fired(seat, "%s бежит с умением: %s" % [rname(rc[seat]["id"]), rname(str(v))])
			pass
		"lunala":
			rc[seat]["lunala"] = int(v)
			_fired(seat, "Лунала предсказывает победу: %s" % rname(rc[int(v)]["id"]))
			_pre_main()
		"pre":
			_pre_answer(seat, str(p["ctx"]["pw"]), v)
			if phase == "race" and stage == "pre" and current == seat:
				_next_pre()
		"reroll":
			if str(v) == "yes":
				_reroll(seat, str(p["ctx"]["why"]))
			else:
				_after_roll(seat)
		"post":
			_post_answer(seat, str(p["ctx"]["pw"]), v)
	return true


func _ask(seat: int, kind: String, options: Array, ctx: Dictionary) -> void:
	prompt = {"seat": seat, "kind": kind, "options": options, "ctx": ctx, "text": str(ctx.get("q", ""))}


func auto_answer() -> void:
	if prompt.is_empty():
		return
	var opts: Array = prompt["options"]
	var pick_v = opts[opts.size() - 1]["v"] if str(opts[opts.size() - 1]["v"]) == "no" else opts[rng.randi_range(0, opts.size() - 1)]["v"]
	answer(int(prompt["seat"]), pick_v)


# =============================================================================
# Бросок и основной ход
# =============================================================================

## Бросок кубика основного хода (d — заданный результат для тестов).
func do_roll(seat: int, d: int = 0) -> bool:
	if phase != "race" or seat != current or stage != "roll" or not prompt.is_empty():
		return false
	roll = d if d > 0 else rng.randi_range(1, 6)
	rolled = true
	rc[seat]["rerolls"] = 0
	last_roll = {"seat": seat, "v": roll}
	_log(seat, "%s бросает: %d" % [rname(rc[seat]["id"]), roll])
	_roll_options(seat)
	return true


## После броска: переброски (Салазл, Орангуру, Царина).
func _roll_options(seat: int) -> void:
	var r: Dictionary = rc[seat]
	# Царина впереди-сзади: заставляет перебросить
	for t in _with("tsareena", seat):
		if not rc[t]["tsar_used"] and dist(r["pos"]) < dist(rc[t]["pos"]) and roll >= 4:
			rc[t]["tsar_used"] = true
			_fired(t, "Царина приказывает перебросить")
			roll = rng.randi_range(1, 6)
			last_roll = {"seat": seat, "v": roll}
			_log(seat, "переброс: %d" % roll)
	var can := ""
	if power(seat) == "salazzle" and int(r.get("rerolls", 0)) < 2:
		can = "salazzle"
	elif not _with("oranguru").is_empty() and int(r.get("rerolls", 0)) < 1:
		can = "oranguru"
	if can != "":
		if players[seat].get("bot", false):
			if roll <= 2:
				_reroll(seat, can)
				return
		else:
			_ask(seat, "reroll", [{"v": "yes", "label": "Перебросить"}, {"v": "no", "label": "Оставить %d" % roll}], {"why": can, "q": "Выпало %d. Перебросить?" % roll})
			return
	_after_roll(seat)


func _reroll(seat: int, why: String) -> void:
	rc[seat]["rerolls"] = int(rc[seat].get("rerolls", 0)) + 1
	roll = rng.randi_range(1, 6)
	last_roll = {"seat": seat, "v": roll}
	_log(seat, "переброс: %d" % roll)
	if why == "oranguru":
		for o in _with("oranguru", seat):
			_move(o, 1, false, "Орангуру: +1 за чужой переброс")
	_roll_options(seat)


## Умения после броска (у человека — вопросы), затем ход.
func _after_roll(seat: int) -> void:
	var pw := power(seat)
	if pw == "celesteela" and roll <= 2:
		if players[seat].get("bot", false):
			_post_answer(seat, pw, "yes")
		else:
			_ask(seat, "post", [{"v": "yes", "label": "Пройти 4"}, {"v": "no", "label": "Оставить %d" % roll}], {"pw": pw, "q": "Селестила: пройти 4 вместо %d?" % roll})
		return
	if pw == "persian":
		if players[seat].get("bot", false):
			_post_answer(seat, pw, "yes" if roll >= 4 else "no")
		else:
			_ask(seat, "post", [{"v": "yes", "label": "Пройти %d и уснуть" % (roll * 2)}, {"v": "no", "label": "Пройти %d" % roll}], {"pw": pw, "q": "Персиан: удвоить ход?"})
		return
	if pw == "toucannon" and roll >= 5:
		var opts := []
		for o in rc.size():
			if o != seat and active(o):
				opts.append({"v": o, "label": rname(rc[o]["id"])})
		if not opts.is_empty():
			if players[seat].get("bot", false):
				_post_answer(seat, pw, _leaders().filter(func(x): return x != seat)[0] if not _leaders().filter(func(x): return x != seat).is_empty() else opts[0]["v"])
			else:
				_ask(seat, "post", opts + [{"v": "no", "label": "Никого"}], {"pw": pw, "q": "Тукэннон: кого оглушить?"})
			return
	_resolve_main(seat, roll)


func _post_answer(seat: int, pw: String, v: Variant) -> void:
	match pw:
		"celesteela":
			if str(v) == "yes":
				_fired(seat, "Селестила: доп. ускорение — 4")
				_resolve_main(seat, 4)
				return
		"persian":
			if str(v) == "yes":
				_fired(seat, "Персиан: двойной ход и сон")
				_resolve_main(seat, roll * 2)
				_faint(seat, "кошачья дрёма")
				return
		"toucannon":
			if str(v) != "no":
				_fired(seat, "Тукэннон: взрыв клюва")
				_faint(int(v), "Тукэннон")
	_resolve_main(seat, roll)


## Реакции на бросок и сам основной ход.
func _resolve_main(seat: int, value: int) -> void:
	var r: Dictionary = rc[seat]
	var base := roll
	# реакции других на выпавшее число
	for v in _with("vulpix", seat):
		if base == 6:
			_move(v, 2, false, "Вульпикс: снежное предупреждение")
	for n in _with("naganadel", seat):
		if int(rc[n]["naga"]) == base:
			_move(n, 1, false, "Наганадел: ядовитая инъекция")
	for g in _with("gumshoos", seat):
		var gm: Dictionary = rc[g]["gum"]
		if not gm.is_empty() and int(gm["who"]) == seat:
			rc[g]["gum"] = {}
			if int(gm["v"]) == base:
				rc[g]["gum_follow"] = seat
				_fired(g, "Гамшус угадал бросок!")
	for b in _with("oricorio_baile", seat):
		if not b in _leaders() and rng.randi_range(1, 6) == base:
			_move(b, base, false, "Байле: парный танец")
	var kart := _with("kartana")
	if base == 1 and not kart.is_empty():
		next_override = kart[0]
	if base == 1:
		for c in _with("charjabug", seat):
			_fired(c, "Чарджабаг: %s пропускает ход" % rname(r["id"]))
			_move(c, 1, false, "")
			_finish_main(seat)
			return
	# Голисопод: шестёрка — на старт
	if power(seat) == "golisopod" and base == 6:
		r["pos"] = -1
		_add_points(seat, -1, "Голисопод: запасной выход")
		_fired(seat)
		_finish_main(seat)
		return
	# Нигилего управляет чужим ходом
	var mover := seat
	if int(r["steal"]) >= 0 and active(int(r["steal"])):
		mover = int(r["steal"])
		r["steal"] = -1
		_fired(mover, "Нигилего ходит вместо %s" % rname(r["id"]))
	_main_move(mover, value, base, mover == seat)
	_finish_main(seat)


## Основной ход гонщика s на value клеток (с модификаторами умений).
func _main_move(s: int, value: int, base: int, own: bool) -> void:
	var r: Dictionary = rc[s]
	var n := value + main_bonus if own else value
	main_bonus = 0
	var pw := power(s)
	if not r["first_done"]:
		if pw in ["popplio", "rowlet", "litten"]:
			n += 4
			_fired(s, "%s: стартовый рывок +4" % rname(r["id"]))
		var tapu := {"tapu_bulu": "ula", "tapu_fini": "poni", "tapu_koko": "mele", "tapu_lele": "akala"}
		if tapu.get(pw, "") == track:
			n += 6
			_fired(s, "%s: страж острова +6" % rname(r["id"]))
	r["first_done"] = true
	if pw == "raichu":
		n += 2
	if pw == "minior":
		n += 1 if r["minior_up"] else -1
	if pw == "wishiwashi":
		n += 3 if _corners_before(s) < 4 else -1
	if pw == "magearna" and r.has("mag"):
		var even := base % 2 == 0
		if (r["mag"] == "even") == even:
			n += 3
			_fired(s, "Магирна угадала: +3")
		else:
			r.erase("mag")
			_fired(s, "Магирна ошиблась — назад на %d" % base)
			_move(s, -base, false, "")
			return
		r.erase("mag")
	for m in _with("muk", s):
		n -= 1
	for k in _with("rockruff"):
		if rc[k]["pos"] == r["pos"] and r["pos"] >= 0:
			n += 1
	if pw == "graveler" and base == 4:
		_fired(s, "Гравелер: камнепад")
		for o in rc.size():
			if o != s and active(o):
				_move(o, -1, false, "")
	# Сэнсу: чётный бросок у партнёра — иду я, нечётный у меня — идёт он
	for se in _with("oricorio_sensu"):
		var partner := int(rc[se]["sensu"])
		if partner == s and base % 2 == 0 and se != s:
			_move(se, base, false, "Сэнсу: обмен танцами")
		if se == s and base % 2 == 1 and partner >= 0 and active(partner):
			_move(partner, base, false, "Сэнсу: обмен танцами")
			return
	if base == 3:
		for mo in _with("morelull"):
			_fired(mo, "Сонные споры")
			_move(s, 3, true, "")
			_faint(s, "сонные споры")
			return
	n = maxi(0, n)
	_move(s, n, true, "", base)


func _corners_before(s: int) -> int:
	var k := 0
	var p := -1
	for i in 200:
		if p == rc[s]["pos"]:
			return k
		p = _next(s, p)
		if p < 0:
			return k
		if _corner[p]:
			k += 1
	return k


## После основного хода: Раттата, Гамшус, лишний ход, конец хода.
func _finish_main(seat: int) -> void:
	for g in _with("gumshoos", seat):
		if int(rc[g].get("gum_follow", -1)) == seat:
			rc[g]["gum_follow"] = -1
			if active(seat):
				rc[g]["pos"] = rc[seat]["pos"]
	var r: Dictionary = rc[seat]
	if power(seat) == "solgaleo" and int(r["sol"]) == roll and int(r["sol"]) > 0:
		extra_turn = true
		_fired(seat, "Солгалео угадал — ещё ход!")
	r["sol"] = 0
	stage = "done"
	_end_turn()


func _end_turn() -> void:
	if phase != "race" or not prompt.is_empty():
		return
	var s := current
	# Раттата: гонщик закончил ход рядом с местом, где начал
	if active(s) or rc[s]["pos"] == -2:
		var moved := absi(dist(rc[s]["pos"]) - dist(turn_start_pos))
		for k in _with("rattata", s):
			if moved <= 1:
				_move(k, 2, false, "Раттата: крысиная тактика")
	if _check_race_end():
		return
	if extra_turn and active(s):
		extra_turn = false
		stage = "start"
		return
	if next_override >= 0 and active(next_override) and next_override != s:
		current = next_override
	else:
		current = (s + 1) % rc.size()
	next_override = -1
	stage = "start"


## Хост: запустить очередной ход, если ничего не ждём. true — что-то произошло.
func step() -> bool:
	if phase == "race" and prompt.is_empty() and stage == "start":
		_begin_turn()
		return true
	return false


# =============================================================================
# Передвижение
# =============================================================================

## Сдвинуть гонщика на n клеток (n < 0 — назад). main — основной ход (для ворот, Экзеггутора и т. п.).
func _move(s: int, n: int, main: bool, why: String, base: int = 0) -> void:
	if not active(s) or n == 0 or phase != "race":
		return
	if why != "":
		if why.begins_with("Космог"):
			_log(s, why)
		else:
			_fired(s, why)
	var r: Dictionary = rc[s]
	# Бьюиер держит: нельзя уйти с клетки
	var hug := int(r["hug"])
	if hug >= 0 and active(hug) and rc[hug]["pos"] == r["pos"] and hug != s:
		_log(s, "%s в медвежьих объятиях — не двигается" % rname(r["id"]))
		return
	r["hug"] = -1
	var start: int = r["pos"]
	if n < 0:
		var p: int = start
		for i in -n:
			p = _back(s, p)
		r["pos"] = p
		if p != start:
			_land(s, false)
		return
	# Дрампа: финиш только точным броском (для других)
	if not _with("drampa", s).is_empty() and dist(start) < n:
		_log(s, "Дрампа: перелёт за финиш — %s стоит на месте" % rname(r["id"]))
		return
	var p: int = start
	var left := n
	var corner_skipped := false
	var passed := []
	while left > 0:
		var nx := _next(s, p)
		if nx == -2:
			p = -2
			break
		var others := _at(nx, s)
		# Кьютифлай перелетает занятые клетки
		if power(s) == "cutiefly" and not others.is_empty():
			passed.append_array(others)
			p = nx
			continue
		# Сэндшру срезает угол раз за ход
		if power(s) == "sandshrew" and _corner[nx] and not corner_skipped and left > 0:
			corner_skipped = true
			p = nx
			continue
		var cost := 1
		for a in others:
			if _has(a, "araquanid"):
				cost = 2
		if cost > left:
			break
		left -= cost
		# уходим с клетки p: обгон тех, кто на ней
		if p >= 0:
			for o in _at(p, s):
				if not o in passed:
					passed.append(o)
		p = nx
		if left > 0:
			# Экзеггутор: обойти можно только с 4+ на основном ходу
			var ex := others.filter(func(x): return _has(x, "exeggutor"))
			if not ex.is_empty() and (not main or base < 4):
				_fired(ex[0], "Экзеггутор: %s останавливается" % rname(r["id"]))
				break
			if node_type(p) == "gate6" and not (main and base == 6):
				_log(s, "Гора: дальше — только с шестёркой")
				break
	r["pos"] = p
	# обгоны
	for o in passed:
		if not active(o) or rc[o]["pos"] == p:
			continue
		if _has(o, "komala") and dist(p) < dist(rc[o]["pos"]):
			_fired(o, "Комала: %s падает" % rname(r["id"]))
			_faint(s, "Комала")
		if power(s) == "mudsdale" and dist(p) < dist(rc[o]["pos"]):
			_fired(s, "Мадсдейл лягает %s" % rname(rc[o]["id"]))
			_move(o, -2, false, "")
	# Комфи с исходной клетки следует за ушедшим
	if start >= 0 and p != start:
		for c in _with("comfey", s):
			if rc[c]["pos"] == start and dist(p) < dist(start):
				rc[c]["pos"] = p
				_fired(c, "Комфи следует за %s" % rname(r["id"]))
	if p == -2:
		_finish(s)
		return
	if p != start:
		_land(s, main, base)


## Остановка на клетке: клетка, соседи, умения.
func _land(s: int, main: bool, base: int = 0) -> void:
	if not active(s) or _depth > 8:
		return
	_depth += 1
	var r: Dictionary = rc[s]
	var p: int = r["pos"]
	# Бруксиш: основной ход на его клетку — столько же назад
	if main and p >= 0:
		for b in _at(p, s):
			if _has(b, "bruxish"):
				_fired(b, "Бруксиш гипнотизирует %s" % rname(r["id"]))
				r["pos"] = turn_start_pos
				_move(s, -maxi(base, 1), false, "")
				_depth -= 1
				return
	# Токсапекс: на его клетке стоять нельзя
	if p >= 0:
		for t in _at(p, s):
			if _has(t, "toxapex"):
				r["pos"] = _back(s, p)
				_fired(t, "Токсапекс: %s встаёт позади" % rname(r["id"]))
				_depth -= 1
				_land(s, false)
				return
	if p < 0:
		_depth -= 1
		return
	# клетка
	var t := node_type(p)
	var times := 2 if power(s) == "togedemaru" and t.begins_with("arrow") else 1
	if t == "faint":
		_faint(s, "клетка обморока")
	elif t.begins_with("chip"):
		var v := int(t.substr(4))
		_add_points(s, v, "Бронзовое очко:")
		bronze[s] += v
	elif t.begins_with("arrow"):
		var v := int(t.substr(5))
		if times == 2:
			_fired(s, "Тогедемару катится по стрелке дважды")
		for k in times:
			if active(s):
				_move(s, v, false, "")
		_depth -= 1
		return
	var col := str(_nodes[p]["c"])
	for x in _with("xurkitree", s):
		if col != "" and str(rc[x]["xurk"]) == col:
			_fired(x, "Ксуркитри: удар током")
			_faint(s, "ток")
	# соседи по клетке
	var others := _at(p, s)
	for o in others:
		if _has(o, "turtonator"):
			_fired(o, "Туртонатор: ловушка-панцирь")
			_faint(s, "Туртонатор")
		if _has(o, "minior") and not rc[o]["minior_up"]:
			rc[o]["minior_up"] = true
			_fired(o, "Минеор: щиты вниз — теперь +1")
		if _has(o, "bewear"):
			r["hug"] = o
			_fired(o, "Бьюиер обнимает %s" % rname(r["id"]))
		if _has(o, "crabominable"):
			_duel(o, s, "Крабоминабл: ДУЭЛЬ!", false)
		if _has(o, "blacephalon") and s in _leaders():
			_fired(o, "Блацефалон: взрыв мозга — оба на старт")
			r["pos"] = -1
			rc[o]["pos"] = -1
			_depth -= 1
			return
	if power(s) == "turtonator":
		for o in others:
			_fired(s, "Туртонатор встаёт на %s" % rname(rc[o]["id"]))
			_faint(o, "Туртонатор")
	if power(s) == "bewear":
		for o in others:
			rc[o]["hug"] = s
	if power(s) == "guzzlord" and others.size() == 1:
		rc[others[0]]["out"] = true
		_fired(s, "Газзлорд поглощает %s — выбывает" % rname(rc[others[0]]["id"]))
	if power(s) == "blacephalon" and not others.is_empty() and not s in _leaders():
		var t2: int = others[0]
		_fired(s, "Блацефалон: взрыв мозга — оба на старт")
		r["pos"] = -1
		rc[t2]["pos"] = -1
		_depth -= 1
		return
	if power(s) == "nihilego" and not others.is_empty():
		var t3: int = others[0]
		rc[t3]["steal"] = s
		_fired(s, "Нигилего захватывает %s" % rname(rc[t3]["id"]))
	if power(s) == "crabominable":
		for o in others:
			_duel(s, o, "Крабоминабл: ДУЭЛЬ!", false)
	if others.size() == 1:
		for ph in _with("pheramosa"):
			if ph != s and ph != others[0]:
				_move(ph, 2, false, "Ферамоса: жестокий шип")
	# Маршэдоу: прямо перед ним один гонщик
	if power(s) == "marshadow":
		var ahead := _next(s, p)
		if ahead >= 0 and _at(ahead, s).size() == 1:
			_duel(s, _at(ahead, s)[0], "Маршэдоу: бой с тенью!", true)
	# Мелтан: все на одной клетке
	for m in _with("meltan"):
		var all_same := true
		for o in rc.size():
			if active(o) and rc[o]["pos"] != rc[m]["pos"]:
				all_same = false
		if all_same and rc[m]["pos"] >= 0:
			_fired(m, "Мелтан: сборка — сразу первое место!")
			rc[m]["pos"] = -2
			_finish(m)
	_depth -= 1


## ДУЭЛЬ: оба бросают; ничья — в пользу a. faint_loser — проигравший падает в обморок (Маршэдоу).
func _duel(a: int, b: int, why: String, faint_loser: bool) -> void:
	if not active(a) or not active(b):
		return
	var ra := rng.randi_range(1, 6)
	var rb := rng.randi_range(1, 6)
	var win := a if ra >= rb else b
	var lose := b if win == a else a
	_fired(a, "%s %d : %d" % [why, ra, rb])
	_move(win, 2, false, "")
	if faint_loser:
		_faint(lose, "проиграл дуэль")


func _palossand(s: int) -> void:
	var p: int = rc[s]["pos"]
	if p < 0:
		return
	for o in rc.size():
		if o != s and active(o) and rc[o]["pos"] != p:
			_move(o, 1 if dist(rc[o]["pos"]) > dist(p) else -1, false, "")
	main_bonus += _at(p, s).size()
	_fired(s, "Палоссанд: песчаный вихрь")


# =============================================================================
# Финиш
# =============================================================================

func _finish(s: int) -> void:
	if s in finished:
		return
	rc[s]["pos"] = -2
	finished.append(s)
	_log(s, "%s финиширует %s!" % [rname(rc[s]["id"]), "первым" if finished.size() == 1 else "вторым"])
	# Лунала угадала победителя
	if finished.size() == 1:
		for l in _with("lunala"):
			if int(rc[l]["lunala"]) == s and l != s:
				_fired(l, "Лунала угадала! Гонка окончена")
				rc[l]["pos"] = -2
				finished.append(l)
	_check_race_end()


func _check_race_end() -> bool:
	if phase != "race":
		return true
	var alive := 0
	for s in rc.size():
		if active(s):
			alive += 1
	if finished.size() >= 2 or (alive == 0) or (finished.size() >= 1 and alive == 0):
		_end_race()
		return true
	if alive == 1 and finished.size() + alive < 2 and rc.size() > 1:
		_end_race()
		return true
	return false


func _end_race() -> void:
	if phase != "race":
		return
	var places := finished.slice(0, 2)
	if places.size() > 0:
		_add_points(places[0], AAData.GOLD[race_no % 4], "Золото за гонку:")
	if places.size() > 1:
		_add_points(places[1], AAData.SILVER[race_no % 4], "Серебро за гонку:")
	history.append({"track": track, "places": places, "racers": rc.map(func(r): return r["id"])})
	# следующую гонку начинает отставший
	var worst := -1
	var wd := -1
	for s in rc.size():
		var d := 999 if rc[s]["out"] else (0 if rc[s]["pos"] == -2 else dist(rc[s]["pos"]))
		if d > wd:
			wd = d
			worst = s
	start_seat = maxi(0, worst)
	prompt = {}
	phase = "race_result" if race_no < 3 else "game_over"


## Хост: после показа итогов гонки — следующая.
func advance() -> void:
	if phase != "race_result":
		return
	race_no += 1
	_start_pick()


func winners() -> Array:
	var best := -1
	for v in scores:
		best = maxi(best, int(v))
	var out := []
	for s in scores.size():
		if scores[s] == best:
			out.append(s)
	return out


# =============================================================================
# Вид для игрока
# =============================================================================

func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var pv := []
	for s in picks.size():
		pv.append(picks[s] if (phase != "pick" or s == seat or show_all) else ("?" if picks[s] != "" else ""))
	var tv := []
	for s in teams.size():
		tv.append(teams[s].duplicate() if (s == seat or show_all or phase in ["race_result", "game_over"]) else teams[s].map(func(_x): return "?"))
	var rv := []
	for s in rc.size():
		var r: Dictionary = rc[s]
		rv.append({"id": r["id"], "power": power(s) if active(s) else r["power"], "pos": r["pos"], "tripped": r["tripped"], "out": r["out"], "dist": dist(r["pos"]) if not r["out"] else 999})
	return {
		"you": seat,
		"players": players.duplicate(true),
		"phase": phase,
		"line": line.duplicate(),
		"drafter": drafter(),
		"teams": tv,
		"used": used.duplicate(true),
		"scores": scores.duplicate(),
		"race_no": race_no,
		"track": track,
		"picks": pv,
		"forks": fork_nodes(),
		"racers": rv,
		"current": current,
		"stage": stage,
		"finished": finished.duplicate(),
		"prompt": prompt.duplicate(true) if not prompt.is_empty() and (int(prompt["seat"]) == seat or show_all) else ({"seat": prompt["seat"], "kind": "wait"} if not prompt.is_empty() else {}),
		"last_roll": last_roll.duplicate(),
		"turn_no": turn_no,
		"history": history.duplicate(true),
		"log": log.duplicate(true),
		"winners": winners() if phase == "game_over" else [],
		"hotseat": show_all,
		"clock": phase in ["draft", "pick"] or (phase == "race" and (stage == "roll" or not prompt.is_empty())),
	}
