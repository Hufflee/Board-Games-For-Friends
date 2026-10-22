class_name K12Rules
extends RefCounted
## Движок правил «Дюжины короля». Ничего не знает об интерфейсе и сети:
## хост вызывает действия игроков, а клиенты получают get_view().
##
## Фазы: roll → select → (sorcerer) → (oracle) → trick_result → select … → (pick_under) → round_result → roll … → game_over
##
## Розыгрыш проходит по «этапам». В обычной игре этап один — все игроки.
## В турнире (5+ игроков) сначала этап каждой группы (второе место получает 1 ПО,
## победитель группы выходит в финал), затем финал победителей групп (2 и 1 ПО).
## Если в турнире раунд одновременно выиграли несколько игроков со второй картой под кубиком,
## они играют между собой переигровку из 4 розыгрышей (playoff).

const C := preload("res://games/king_of_12/logic/cards.gd")
const WIN_POINTS := 8
const ROUNDS_TO_WIN := 2
const PLAYOFF_TRICKS := 4
const GROUP_SIZES := {5: [2, 3], 6: [3, 3], 7: [3, 4], 8: [4, 4]}

var players: Array = []  # [{name: String, bot: bool}]
var deck: Array[String] = []
var hands: Array = []  # по местам: Array[String]
var discards: Array = []
var under: Array = []  # карты под кубиком (победы в раундах)
var faces: Array[int] = []
var values: Array[int] = []  # значения кубиков в последнем розыгрыше
var tokens: Array = []  # по местам: Array[int] из 1 и 2
var selected: Array[String] = []
var rolled: Array[bool] = []
var active: Array[bool] = []  # участвует ли место (в переигровке — только финалисты)
var throws: Array = []  # по местам: {id, vx, vy} — для анимации броска у всех игроков
var tournament := false
var playoff := false
var groups: Array = []  # группы мест в текущем раунде
var phase := "setup"
var pending := {}  # sorcerer: {seat, options}; oracle: {seat}; pick_under: {seat, seats}
var trick := {}  # итог последнего розыгрыша
var round_info := {}  # итог последнего раунда
var history: Array = []  # все розыгрыши партии
var round_history: Array = []  # итоги всех раундов
var round_no := 0
var trick_no := 0
var winner := -1
var rng := RandomNumberGenerator.new()

var _throw_seq := 0
var _played: Array[String] = []
var _stages: Array = []
var _stage_i := 0
var _work := {}  # текущий этап (может ждать выбора Чародея)
var _acc := {}  # итог розыгрыша, собираемый по этапам


func player_count() -> int:
	return players.size()


func player_name(seat: int) -> String:
	return players[seat]["name"]


func points(seat: int) -> int:
	var sum := 0
	for t in tokens[seat]:
		sum += t
	return sum


## Активные места по порядку.
func active_seats() -> Array:
	var list := []
	for s in player_count():
		if active[s]:
			list.append(s)
	return list


func new_game(player_list: Array, deck_cards: Array, seed_value: int = 0, tournament_mode: bool = false) -> void:
	players = player_list.duplicate(true)
	deck.assign(deck_cards)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var n := players.size()
	tournament = tournament_mode and n >= 5
	playoff = false
	hands = _empty_lists(n)
	discards = _empty_lists(n)
	under = _empty_lists(n)
	tokens = _empty_lists(n)
	faces.resize(n)
	values.resize(n)
	selected.resize(n)
	rolled.resize(n)
	active.resize(n)
	active.fill(true)
	throws = _empty_lists(n).map(func(_x): return {})
	history = []
	round_history = []
	round_no = 0
	winner = -1
	round_info = {}
	start_round()


func start_round() -> void:
	round_no += 1
	trick_no = 0
	trick = {}
	pending = {}
	for s in player_count():
		hands[s] = deck.filter(func(c): return not under[s].has(c))
		discards[s] = []
		tokens[s] = []
		selected[s] = ""
		rolled[s] = not active[s]
	groups = _make_groups()
	phase = "roll"


## Группы раунда: в турнире — случайный состав каждый раунд (игроки «пересаживаются»).
func _make_groups() -> Array:
	var seats := active_seats()
	if not tournament or playoff:
		return [seats]
	var order := seats.duplicate()
	C._shuffle(order, rng)
	var sizes: Array = GROUP_SIZES.get(order.size(), [])
	if sizes.is_empty():
		sizes = []
		var left := order.size()
		while left > 0:
			var k := 4 if left >= 8 or left == 4 else 3
			if left == 5:
				k = 3
			sizes.append(mini(k, left))
			left -= mini(k, left)
	var result := []
	var i := 0
	for size in sizes:
		var g := order.slice(i, i + size)
		g.sort()
		result.append(g)
		i += size
	return result


func group_of(seat: int) -> int:
	for i in groups.size():
		if groups[i].has(seat):
			return i
	return -1


## Игрок бросает кубик; vx, vy — скорость броска для анимации у всех.
func roll_die(seat: int, vx: float = 0.0, vy: float = 0.0) -> bool:
	if phase != "roll" or rolled[seat] or not active[seat]:
		return false
	faces[seat] = rng.randi_range(1, K12Dice.FACES)
	values[seat] = faces[seat]
	rolled[seat] = true
	_throw_seq += 1
	throws[seat] = {"id": _throw_seq, "vx": vx, "vy": vy}
	if not rolled.has(false):
		_start_trick()
	return true


func _start_trick() -> void:
	trick_no += 1
	for s in player_count():
		selected[s] = ""
		values[s] = faces[s]
	phase = "select"
	pending = {}
	trick = {}


# --- Действия игроков ---------------------------------------------------------

func select_card(seat: int, card: String) -> bool:
	if phase != "select" or not active[seat] or not hands[seat].has(card):
		return false
	selected[seat] = card
	for s in active_seats():
		if selected[s] == "":
			return true
	_resolve()
	return true


## Забрать выбранную карту обратно, пока не все выбрали.
func unselect_card(seat: int) -> bool:
	if phase != "select" or selected[seat] == "":
		return false
	selected[seat] = ""
	return true


func choose_face(seat: int, face: int) -> bool:
	if phase != "sorcerer" or pending.get("seat", -1) != seat:
		return false
	if not pending["options"].has(face):
		return false
	_chain(seat, "→%d" % face)
	faces[seat] = face
	_work["events"].append("%s (Чародей) поворачивает кубик на %d." % [player_name(seat), face])
	pending = {}
	if _mid_stage(_work):
		return true
	_end_stage(_work)
	_run_stages()
	return true


## Владелец Оракула сам перебрасывает кубик (vx, vy — для анимации броска у всех).
func roll_oracle(seat: int, vx: float = 0.0, vy: float = 0.0) -> bool:
	if phase != "oracle" or pending.get("seat", -1) != seat:
		return false
	faces[seat] = rng.randi_range(1, K12Dice.FACES)
	values[seat] = faces[seat]
	_throw_seq += 1
	throws[seat] = {"id": _throw_seq, "vx": vx, "vy": vy}
	_chain(seat, "переброс→%d" % faces[seat])
	_work["events"].append("%s (Оракул) перебрасывает кубик: %d." % [player_name(seat), faces[seat]])
	pending = {}
	_end_stage(_work)
	_run_stages()
	return true


func pick_under(seat: int, card: String) -> bool:
	if phase != "pick_under" or not pending.get("seats", []).has(seat) or not hands[seat].has(card):
		return false
	hands[seat].erase(card)
	under[seat].append(card)
	round_info["under_cards"][str(seat)] = card
	round_info["under_card"] = card
	pending["seats"].erase(seat)
	if not pending["seats"].is_empty():
		pending["seat"] = pending["seats"][0]
		return true
	pending = {}
	var champs := []
	for s in round_info["winners"]:
		if under[s].size() >= ROUNDS_TO_WIN:
			champs.append(s)
	if champs.size() == 1:
		_finish_game(champs[0])
	elif champs.size() > 1:
		_begin_playoff(champs)
	else:
		phase = "round_result"
	return true


## Хост вызывает, когда все посмотрели итог розыгрыша или раунда.
func advance() -> void:
	match phase:
		"trick_result":
			for s in active_seats():
				discards[s].append(trick["played"][s])
			if _round_over():
				_end_round()
			else:
				_start_trick()
		"round_result":
			start_round()


# --- Розыгрыш -----------------------------------------------------------------

func _resolve() -> void:
	var n := player_count()
	_played.assign(selected.duplicate())
	for s in active_seats():
		hands[s].erase(_played[s])
	_acc = {
		"card_cancelled": _fill(n, false),
		"suppressed": _fill(n, false),
		"dice_cancelled": _fill(n, false),
		"awards": _fill(n, 0),
		"faces_start": faces.duplicate(),
		"chains": _empty_lists(n),
		"events": [],
		"stages": [],
		"finalists": [],
		"winner": -1,
		"second": -1,
	}
	for s in active_seats():
		_acc["chains"][s] = [str(faces[s])]
	_stages = []
	for i in groups.size():
		_stages.append({"kind": "group", "index": i, "seats": groups[i].duplicate()})
	if tournament and not playoff:
		_stages.append({"kind": "final", "seats": []})
	_stage_i = 0
	_run_stages()


## Проходит этапы до конца или до паузы на выбор Чародея.
func _run_stages() -> void:
	while _stage_i < _stages.size():
		var st: Dictionary = _stages[_stage_i]
		_stage_i += 1
		if st["kind"] == "final":
			st["seats"] = _acc["finalists"].duplicate()
			if st["seats"].is_empty():
				continue
		if _begin_stage(st):
			return  # ждём Чародея
		if _mid_stage(_work):
			return  # ждём броска Оракула
		_end_stage(_work)
	_finish_trick()


func _stage_title(st: Dictionary) -> String:
	if st["kind"] == "final":
		return "— Финал победителей групп —"
	if groups.size() > 1:
		return "— Группа %d —" % (st["index"] + 1)
	return ""


## Отмена дублей, Леди, Торговцы, Смутьяны, Оборотень. true — ждём выбора Чародея.
func _begin_stage(st: Dictionary) -> bool:
	var seats: Array = st["seats"]
	var w := {"kind": st["kind"], "seats": seats, "card_cancelled": {}, "suppressed": {}, "events": []}
	var title := _stage_title(st)
	if title != "":
		w["events"].append(title)
	if st["kind"] == "final":
		w["events"].append("Карты победителей групп срабатывают снова: %s." % ", ".join(seats.map(player_name)))
		for s in seats:
			_chain(s, "| финал: %d" % faces[s])
	var counts := {}
	for s in seats:
		counts[_played[s]] = counts.get(_played[s], 0) + 1
	var dupes := []
	for s in seats:
		w["card_cancelled"][s] = counts[_played[s]] > 1
		w["suppressed"][s] = false
		if w["card_cancelled"][s] and not dupes.has(_played[s]):
			dupes.append(_played[s])
	for c in dupes:
		w["events"].append("Одинаковые карты «%s» отменены." % C.card_name(c))

	var lady := _seat_with(w, C.LADY, false)
	if lady >= 0:
		for s in seats:
			if s != lady and not w["card_cancelled"][s]:
				w["suppressed"][s] = true
		w["events"].append("%s: Леди отменяет эффекты всех остальных карт." % player_name(lady))

	if _seat_with(w, C.MERCHANTS) >= 0 and seats.size() > 1:
		var old := {}
		for s in seats:
			old[s] = faces[s]
		for i in seats.size():
			var to: int = seats[(i + 1) % seats.size()]
			faces[to] = old[seats[i]]
			_chain(to, "→%d" % faces[to])
		w["events"].append("Торговцы: все передают кубики игроку слева.")
	if _seat_with(w, C.TROUBLEMAKERS) >= 0:
		for s in seats:
			faces[s] = K12Dice.opposite(faces[s])
			_chain(s, "→%d" % faces[s])
		w["events"].append("Смутьяны: все кубики перевёрнуты.")
	var wolf := _seat_with(w, C.WEREWOLF)
	if wolf >= 0:
		faces[wolf] = K12Dice.opposite(faces[wolf])
		_chain(wolf, "→%d" % faces[wolf])
		w["events"].append("%s (Оборотень) переворачивает кубик: %d." % [player_name(wolf), faces[wolf]])

	_work = w
	var sorc := _seat_with(w, C.SORCERER)
	if sorc >= 0:
		# Порядок Смутьянов и Чародея не важен: соседи противоположной грани
		# противоположны соседям исходной, итоговый набор граней одинаков.
		phase = "sorcerer"
		pending = {"seat": sorc, "options": K12Dice.neighbors(faces[sorc])}
		return true
	return false


## Числовые эффекты; затем Оракул (последним). true — ждём, пока владелец Оракула бросит кубик.
func _mid_stage(w: Dictionary) -> bool:
	var seats: Array = w["seats"]
	for s in seats:
		values[s] = faces[s]
	for s in seats:
		if not _active(w, s):
			continue
		match _played[s]:
			C.ALCHEMIST:
				values[s] *= 2
				_chain(s, "×2")
				w["events"].append("%s (Алхимик): значение удвоено — %d." % [player_name(s), values[s]])
			C.ROBOT:
				values[s] += 7
				_chain(s, "+7")
				w["events"].append("%s (Робот): +7 — %d." % [player_name(s), values[s]])
			C.PARASITE:
				values[s] -= 7
				_chain(s, "−7")
				w["events"].append("%s (Паразит): −7 — %d." % [player_name(s), values[s]])
			C.GOLEM:
				values[s] = 12
				_chain(s, "Голем")
				w["events"].append("%s (Голем): значение 12." % player_name(s))
	var oracle := _seat_with(w, C.ORACLE)
	if oracle >= 0:
		_work = w
		phase = "oracle"
		pending = {"seat": oracle}
		return true
	return false


## Голем, сравнение и жетоны этапа.
func _end_stage(w: Dictionary) -> void:
	var seats: Array = w["seats"]
	var golem := _seat_with(w, C.GOLEM)
	if golem >= 0 and faces[golem] == 12:
		values[golem] = 1
		w["events"].append("%s (Голем): на грани тоже 12 — значение становится 1." % player_name(golem))
	for s in seats:
		_chain(s, "= %d" % values[s])

	var result := _compare(w)
	_steal_by_cancelled_ladies(w)
	for s in seats:
		_acc["dice_cancelled"][s] = result["cancelled"][s]
		if w["kind"] == "group":
			_acc["card_cancelled"][s] = w["card_cancelled"][s]
			_acc["suppressed"][s] = w["suppressed"][s]
	_acc["events"].append_array(w["events"])
	_acc["stages"].append({"kind": w["kind"], "seats": seats, "winner": result["winner"], "second": result["second"]})
	_work = {}


func _finish_trick() -> void:
	pending = {}
	var n := player_count()
	var chains := []
	for s in n:
		var parts: Array = _acc["chains"][s]
		chains.append(" ".join(parts) if parts.size() > 2 else "")
	trick = {
		"played": _played.duplicate(),
		"card_cancelled": _acc["card_cancelled"],
		"suppressed": _acc["suppressed"],
		"faces_start": _acc["faces_start"],
		"faces": faces.duplicate(),
		"values": values.duplicate(),
		"dice_cancelled": _acc["dice_cancelled"],
		"winner": _acc["winner"],
		"second": _acc["second"],
		"awards": _acc["awards"],
		"events": _acc["events"],
		"chains": chains,
		"stages": _acc["stages"],
		"finalists": _acc["finalists"],
	}
	history.append({
		"round": round_no,
		"trick": trick_no,
		"played": trick["played"],
		"card_cancelled": trick["card_cancelled"],
		"values": trick["values"],
		"awards": trick["awards"],
		"winner": trick["winner"],
		"second": trick["second"],
		"active": active.duplicate(),
	})
	phase = "trick_result"


func _compare(w: Dictionary) -> Dictionary:
	var seats: Array = w["seats"]
	var stage_vals := {}
	for s in seats:
		stage_vals[s] = values[s]
	var cancelled := _ties_map(stage_vals)
	var faun := _seat_with(w, C.FAUN)
	if faun >= 0 and cancelled[faun]:
		var others := []
		for s in seats:
			if s != faun:
				others.append(faces[s])
		for f in range(K12Dice.FACES, 0, -1):
			if not others.has(f):
				faces[faun] = f
				values[faun] = f
				stage_vals[faun] = f
				break
		_chain(faun, "Фавн→%d" % faces[faun])
		w["events"].append("%s (Фавн) избегает отмены: кубик повёрнут на %d." % [player_name(faun), faces[faun]])
		cancelled = _ties_map(stage_vals)
	var tied := []
	for s in seats:
		if cancelled[s]:
			tied.append(player_name(s))
	if not tied.is_empty():
		w["events"].append("Равные значения отменены: %s." % ", ".join(tied))

	var knight := _seat_with(w, C.KNIGHT) >= 0
	var remaining := []
	for s in seats:
		if not cancelled[s]:
			remaining.append(s)
	remaining.sort_custom(func(a, b): return values[a] < values[b] if knight else values[a] > values[b])
	var win: int = remaining[0] if remaining.size() > 0 else -1
	var second: int = remaining[1] if remaining.size() > 1 else -1
	if knight:
		w["events"].append("Рыцарь: побеждает наименьшее значение.")
	var collector := _seat_with(w, C.COLLECTOR)
	if collector >= 0 and cancelled[collector]:
		second = win
		win = collector
		w["events"].append("%s (Коллекционер): кубик отменён — становится победителем." % player_name(collector))

	if w["kind"] == "group" and tournament and not playoff:
		# турнир: второе место группы — 1 ПО, победитель группы идёт в финал
		if second >= 0:
			_award(second, 1, w, "%s — второе место в группе: +1 ПО.")
		if win >= 0:
			_acc["finalists"].append(win)
			w["events"].append("%s побеждает в группе и выходит в финал." % player_name(win))
		else:
			w["events"].append("В группе нет победителя.")
	else:
		var cheater := _seat_with(w, C.CHEATER) >= 0
		var win_pts := 1 if cheater else 2
		var second_pts := 2 if cheater else 1
		if cheater:
			w["events"].append("Шулер: победителю 1 ПО, второму месту 2 ПО.")
		if win >= 0:
			_award(win, win_pts, w, "%s побеждает в розыгрыше: +" + str(win_pts) + " ПО.")
		if second >= 0:
			_award(second, second_pts, w, "%s на втором месте: +" + str(second_pts) + " ПО.")
		if win < 0:
			w["events"].append("В этом розыгрыше нет победителя.")
		_acc["winner"] = win
		_acc["second"] = second
	var cancelled_list := _fill(player_count(), false)
	for s in seats:
		cancelled_list[s] = cancelled[s]
	return {"cancelled": cancelled_list, "winner": win, "second": second}


func _award(seat: int, pts: int, w: Dictionary, text: String) -> void:
	tokens[seat].append(pts)
	_acc["awards"][seat] += pts
	w["events"].append(text % player_name(seat))


## Леди, отменённая дублем: владелец с наименьшим значением забирает лучший жетон
## у владельца с наибольшим. При равных значениях не применяется.
func _steal_by_cancelled_ladies(w: Dictionary) -> void:
	var ladies := []
	for s in w["seats"]:
		if _played[s] == C.LADY and w["card_cancelled"][s]:
			ladies.append(s)
	if ladies.size() < 2:
		return
	ladies.sort_custom(func(a, b): return values[a] < values[b])
	var low: int = ladies[0]
	var high: int = ladies[-1]
	if values[low] == values[ladies[1]] or values[high] == values[ladies[-2]]:
		w["events"].append("Леди: у владельцев равные значения — эффект не применяется.")
		return
	if tokens[high].is_empty():
		w["events"].append("Леди: у %s нет жетонов — забирать нечего." % player_name(high))
		return
	var best: int = tokens[high].max()
	tokens[high].erase(best)
	tokens[low].append(best)
	w["events"].append("Леди: %s забирает жетон %d ПО у %s." % [player_name(low), best, player_name(high)])


# --- Конец раунда ---------------------------------------------------------------

func _round_over() -> bool:
	if playoff and trick_no >= PLAYOFF_TRICKS:
		return true
	for s in active_seats():
		if hands[s].size() <= 1 or points(s) >= WIN_POINTS:
			return true
	return false


func _end_round() -> void:
	var n := player_count()
	var sums: Array[int] = []
	for s in n:
		hands[s].append_array(discards[s])
		discards[s] = []
		hands[s] = deck.filter(func(c): return hands[s].has(c) and not under[s].has(c))
		sums.append(points(s))
	var cancelled := _fill(n, false)
	var winners := []
	for g in groups:
		var group_sums := {}
		for s in g:
			group_sums[s] = sums[s]
		var tie := _ties_map(group_sums)
		var best := -1
		for s in g:
			cancelled[s] = tie[s]
			if not tie[s] and (best < 0 or sums[s] > sums[best]):
				best = s
		if best >= 0:
			winners.append(best)
	round_info = {
		"round": round_no,
		"sums": sums,
		"cancelled": cancelled,
		"winners": winners,
		"winner": winners[0] if winners.size() > 0 else -1,
		"under_card": "",
		"under_cards": {},
		"groups": groups.duplicate(true),
		"playoff": playoff,
		"active": active.duplicate(),
	}
	round_history.append(round_info)
	if playoff:
		if winners.is_empty():
			phase = "round_result"  # переигровка без победителя — ещё одна
		else:
			_finish_game(winners[0])
		return
	if winners.is_empty():
		phase = "round_result"
	else:
		phase = "pick_under"
		pending = {"seat": winners[0], "seats": winners.duplicate()}


func _begin_playoff(champs: Array) -> void:
	playoff = true
	for s in player_count():
		active[s] = champs.has(s)
	round_info["playoff_next"] = champs.duplicate()
	phase = "round_result"


func _finish_game(seat: int) -> void:
	winner = seat
	phase = "game_over"


# --- Вспомогательное -------------------------------------------------------------

func _chain(seat: int, part: String) -> void:
	if not _acc.is_empty() and seat < _acc["chains"].size():
		_acc["chains"][seat].append(part)


func _active(w: Dictionary, s: int) -> bool:
	return not w["card_cancelled"][s] and not w["suppressed"][s]


## Место в текущем этапе, у которого действует карта card (или -1).
func _seat_with(w: Dictionary, card: String, need_active: bool = true) -> int:
	for s in w["seats"]:
		if _played[s] != card:
			continue
		if need_active and not _active(w, s):
			continue
		if not need_active and w["card_cancelled"][s]:
			continue
		return s
	return -1


## Отметка true у всех, чьё значение совпало с чьим-то ещё.
static func _ties(vals: Array) -> Array:
	var counts := {}
	for v in vals:
		counts[v] = counts.get(v, 0) + 1
	return vals.map(func(v): return counts[v] > 1)


## То же для словаря место → значение.
static func _ties_map(vals: Dictionary) -> Dictionary:
	var counts := {}
	for s in vals:
		counts[vals[s]] = counts.get(vals[s], 0) + 1
	var result := {}
	for s in vals:
		result[s] = counts[vals[s]] > 1
	return result


static func _fill(n: int, value) -> Array:
	var a := []
	a.resize(n)
	a.fill(value)
	return a


static func _empty_lists(n: int) -> Array:
	var a := []
	for i in n:
		a.append([])
	return a


## Состояние для конкретного игрока: чужой выбор карты скрыт до вскрытия.
func get_view(seat: int) -> Dictionary:
	var chosen := []
	for s in player_count():
		chosen.append(selected[s] != "")
	return {
		"you": seat,
		"players": players.duplicate(true),
		"deck": deck.duplicate(),
		"hands": hands.duplicate(true),
		"discards": discards.duplicate(true),
		"under": under.duplicate(true),
		"faces": faces.duplicate(),
		"values": values.duplicate(),
		"tokens": tokens.duplicate(true),
		"chosen": chosen,
		"played": selected.duplicate() if phase in ["sorcerer", "oracle", "trick_result"] else [],
		"rolled": rolled.duplicate(),
		"active": active.duplicate(),
		"throws": throws.duplicate(true),
		"my_selected": selected[seat] if seat >= 0 and seat < player_count() else "",
		"phase": phase,
		"pending": pending.duplicate(true),
		"trick": trick.duplicate(true),
		"round_info": round_info.duplicate(true),
		"history": history.duplicate(true),
		"round_history": round_history.duplicate(true),
		"tournament": tournament,
		"playoff": playoff,
		"groups": groups.duplicate(true),
		"round_no": round_no,
		"trick_no": trick_no,
		"winner": winner,
	}
