class_name DWRules
extends RefCounted
## Движок «Опасных слов». Объясняют голосом; программа ведёт слова, ловушки, ходы, подземелье.
##
## Фазы раунда: traps (обе команды пишут ловушки) → (defuse: выбор номера для «Обезвреженной ловушки»)
##   → turn_ready (объясняющий читает слово) → turn (идёт время) → turn_result → … второй ход …
##   → round_result → traps … → game_over

const MAX_ROUNDS := 8
const BASE_GUESSES := 5

var players: Array = []  # [{name, team}]
var rooms: Array = []  # номера комнат по порядку, напр. [3, 4, 5, 6, 7]
var pos := [0, 0]  # индекс комнаты команды
var monster_pos := 4
var monster := "troll"
var hard := false
var curses := {}  # индекс комнаты -> id проклятия (закрыто, пока команда не начнёт там раунд)
var curse_deck: Array = []
var round_no := 0
var torch := [0, 0]  # чья очередь объяснять в команде
var tie_first := 0  # кто ходит первым при равенстве («сияющая книга»), меняется каждый раунд

var phase := "setup"
var secret := ["", ""]  # secret[t] — слово, которое объясняет команда t
var traps := [[], []]  # traps[t] — ловушки, которые команда t пишет ПРОТИВ соперника
var ready := [false, false]
var ready_votes := [[], []]  # кто из команды нажал «Готово — ловушки расставлены» (места)
var persistent_curses := false  # режим: проклятие комнаты действует каждый раунд, а не один раз
var horror := [-1, -1]  # horror[t] — номер строки «Слова ужаса» в списке команды t
## Общее поле команды: предложенные слова-ловушки и голоса — [{w, by, votes: [места]}].
## В ловушки попадают слова с наибольшим числом голосов.
var cands := [[], []]
var horror_cand := [-1, -1]  # какое предложение команда отметила «Словом ужаса»
const MAX_CANDS := 30
var crossed := [-1, -1]  # вычеркнутая строка (Обезвреженная ловушка)
var active_curses := [[], []]  # проклятия, действующие на команду в этом раунде
var fighting := [false, false]
var order: Array = []  # порядок ходов в раунде
var turn_i := 0
var turn_team := -1
var wrong := 0
var turn_log: Array = []  # итоги ходов раунда
var winners: Array = []
var monster_won := false
var start_pos := [0, 0]
var rng := RandomNumberGenerator.new()
var _deck: Array = []


func new_game(player_list: Array, room_list: Array = DWData.ROOMS_DEFAULT, monster_id: String = "", hard_mode: bool = false, seed_value: int = 0, use_curses: bool = true, curses_stay: bool = false) -> void:
	players = player_list.duplicate(true)
	persistent_curses = curses_stay
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	rooms = room_list.duplicate()
	pos = [0, 0]
	monster_pos = rooms.size() - 1
	var ids := DWData.MONSTERS.keys()
	monster = monster_id if monster_id != "" else ids[rng.randi_range(0, ids.size() - 1)]
	hard = hard_mode
	curse_deck = DWData.CURSES.keys()
	_shuffle(curse_deck)
	curses = {}
	if use_curses and rooms.size() >= 3:
		curses[1] = curse_deck.pop_back()
		curses[rooms.size() - 2] = curse_deck.pop_back()
	_deck = range(DWData.CARDS.size())
	_shuffle(_deck)
	round_no = 0
	torch = [rng.randi_range(0, 7), rng.randi_range(0, 7)]
	tie_first = 0
	winners = []
	monster_won = false
	_start_round()


func team_members(t: int) -> Array:
	var list := []
	for s in players.size():
		if players[s]["team"] == t:
			list.append(s)
	return list


func explainer(t: int) -> int:
	var m := team_members(t)
	return m[torch[t] % m.size()]


func _start_round() -> void:
	round_no += 1
	start_pos = pos.duplicate()
	traps = [[], []]
	ready = [false, false]
	ready_votes = [[], []]
	horror = [-1, -1]
	cands = [[], []]
	horror_cand = [-1, -1]
	crossed = [-1, -1]
	turn_log = []
	active_curses = [[], []]
	for t in 2:
		fighting[t] = pos[t] == monster_pos
		if curses.has(pos[t]):
			active_curses[t].append(curses[pos[t]])
		if fighting[t] and monster == "mummy":
			var n: int = DWData.MONSTERS["mummy"]["curses_hard" if hard else "curses"]
			for i in n:
				if not curse_deck.is_empty():
					active_curses[t].append(curse_deck.pop_back())
		secret[t] = _draw_word()
	phase = "traps"


func _draw_word() -> String:
	if _deck.is_empty():
		_deck = range(DWData.CARDS.size())
		_shuffle(_deck)
	var card: Array = DWData.CARDS[_deck.pop_back()]
	return card[rng.randi_range(0, card.size() - 1)]  # «книга выбирает одно из восьми»


func has_curse(t: int, id: String) -> bool:
	return active_curses[t].has(id)


## Сколько строк ловушек команда writer пишет против соперника.
func trap_lines(writer: int) -> int:
	var victim := 1 - writer
	if has_curse(victim, "scribbles"):
		return 10
	var n: int = rooms[pos[victim]]
	if fighting[victim] and monster == "vampire" and hard:
		n += DWData.MONSTERS["vampire"]["plus_traps_hard"]
	return n


## Можно ли в строке i (с нуля) записать два слова (Демон).
func double_line(writer: int, i: int) -> bool:
	var victim := 1 - writer
	if not (fighting[victim] and monster == "demon"):
		return false
	return hard or (i + 1) % 2 == 0


func max_guesses(t: int) -> int:
	if fighting[t]:
		var m: Dictionary = DWData.MONSTERS[monster]
		var key := "guesses_hard" if hard else "guesses"
		if m.has(key):
			return m[key]
	return BASE_GUESSES


# --- Фаза ловушек ---------------------------------------------------------------

## Команда обновляет свой список (строки; в строке «Демона» — «слово1 / слово2»).
func set_traps(t: int, lines: Array) -> bool:
	if phase != "traps" or ready[t]:
		return false
	var clean := []
	for i in mini(lines.size(), trap_lines(t)):
		clean.append(str(lines[i]).strip_edges().left(60))
	traps[t] = clean
	return true


## «Слово ужаса» — номер предложения в общем поле команды.
func set_horror(t: int, i: int) -> bool:
	if phase != "traps" or not has_curse(1 - t, "horror") or ready[t] or i < 0 or i >= cands[t].size():
		return false
	horror_cand[t] = i
	return true


## Игрок seat команды t предлагает слово-ловушку (и сразу голосует за него).
func add_cand(t: int, seat: int, word: String) -> bool:
	var w := word.strip_edges().left(40)
	if phase != "traps" or ready[t] or w == "" or cands[t].size() >= MAX_CANDS:
		return false
	for c in cands[t]:
		if str(c["w"]).to_lower() == w.to_lower():
			return false
	cands[t].append({"w": w, "by": seat, "votes": [seat]})
	return true


## Убрать своё предложение.
func del_cand(t: int, seat: int, i: int) -> bool:
	if phase != "traps" or ready[t] or i < 0 or i >= cands[t].size() or int(cands[t][i]["by"]) != seat:
		return false
	cands[t].remove_at(i)
	if horror_cand[t] == i:
		horror_cand[t] = -1
	elif horror_cand[t] > i:
		horror_cand[t] -= 1
	return true


## Голос за слово (повторный — снять голос).
func vote(t: int, seat: int, i: int) -> bool:
	if phase != "traps" or ready[t] or i < 0 or i >= cands[t].size():
		return false
	var votes: Array = cands[t][i]["votes"]
	if votes.has(seat):
		votes.erase(seat)
	else:
		votes.append(seat)
	return true


## Сколько слов нужно (строка «Демона» — два слова).
func words_needed(t: int) -> int:
	var n := 0
	for i in trap_lines(t):
		n += 2 if double_line(t, i) else 1
	return n


## Номера предложений по убыванию голосов; при равенстве — как расставили игроки перетаскиванием
## (move_cand переставляет сам список), новые — в конец своей группы.
func ranked(t: int) -> Array:
	var idx := range(cands[t].size())
	idx.sort_custom(func(a, b):
		var va: int = cands[t][a]["votes"].size()
		var vb: int = cands[t][b]["votes"].size()
		return va > vb or (va == vb and a < b))
	return idx


## Переставить слово i на место to (в общем порядке ranked). Слово остаётся среди слов с тем же числом
## голосов: ниже слов, у которых голосов меньше, не опускается (встаёт последним в своей группе), выше слов,
## у которых больше, не поднимается (встаёт первым в своей группе). Возвращает итоговое место или -1.
func move_cand(t: int, i: int, to: int) -> int:
	if phase != "traps" or ready[t] or i < 0 or i >= cands[t].size():
		return -1
	var order := ranked(t)
	order.erase(i)
	var mine: int = cands[t][i]["votes"].size()
	var more := 0  # слов с большим числом голосов — они выше
	var same := 0  # с тем же числом — своя группа
	for k in order:
		var n: int = cands[t][k]["votes"].size()
		if n > mine:
			more += 1
		elif n == mine:
			same += 1
	to = clampi(to, more, more + same)
	order.insert(to, i)
	# сам список переставляем в этом порядке (номер слова «ужаса» — следом)
	var h: int = horror_cand[t]
	cands[t] = order.map(func(k): return cands[t][k])
	if h >= 0:
		horror_cand[t] = order.find(h)
	return to


## Ловушки из общего поля: лучшие по голосам слова по строкам.
func _finalize_traps(t: int) -> void:
	var order := ranked(t)
	var lines := []
	var k := 0
	horror[t] = -1
	for i in trap_lines(t):
		if k >= order.size():
			break
		var parts := []
		for j in (2 if double_line(t, i) else 1):
			if k < order.size():
				if order[k] == horror_cand[t]:
					horror[t] = lines.size()
				parts.append(cands[t][order[k]]["w"])
				k += 1
		lines.append(" / ".join(parts))
	traps[t] = lines


func set_ready(t: int, on: bool, force: bool = false) -> bool:
	if phase != "traps":
		return false
	if on and cands[t].is_empty() and not force:
		# список записан напрямую (set_traps) — как раньше
		var filled: int = traps[t].filter(func(w): return w != "").size()
		if filled < (1 if has_curse(1 - t, "scribbles") else trap_lines(t)):
			return false
	elif on:
		var have: int = cands[t].size()
		if has_curse(1 - t, "scribbles") or force:
			if have < 1 and not force:
				return false
		elif have < words_needed(t):
			return false
		_finalize_traps(t)
		if traps[t].is_empty():
			traps[t] = ["—"]
	ready[t] = on
	if ready[0] and ready[1]:
		_after_traps()
	return true


## Голос игрока за готовность ловушек. Команда готова, когда проголосовали все её живые игроки
## (humans — места живых игроков; пустой список — как раньше, одно нажатие за всю команду).
func vote_ready(t: int, seat: int, on: bool, humans: Array = []) -> bool:
	if phase != "traps":
		return false
	if not on:
		ready_votes[t].erase(seat)
		return set_ready(t, false) if ready[t] else true
	if not ready_votes[t].has(seat):
		ready_votes[t].append(seat)
	var need := team_members(t).filter(func(s): return humans.is_empty() or humans.has(s))
	for s in need:
		if not ready_votes[t].has(s):
			return true  # ждём остальных из команды
	if not set_ready(t, true):
		ready_votes[t].erase(seat)  # слов не хватает — голос не засчитан
		return false
	return true


func _after_traps() -> void:
	for t in 2:
		if has_curse(t, "defuse") and traps[t].size() > 0:
			phase = "defuse"
			return
	_begin_turns()


## «Обезвреженная ловушка»: соперник называет номер — строка вычёркивается из списка проклятой команды.
func pick_defuse(picker: int, n: int) -> bool:
	if phase != "defuse":
		return false
	var cursed := 1 - picker
	if not has_curse(cursed, "defuse") or crossed[cursed] >= 0:
		return false
	crossed[cursed] = clampi(n - 1, 0, traps[cursed].size() - 1)
	for t in 2:
		if has_curse(t, "defuse") and crossed[t] < 0 and traps[t].size() > 0:
			return true
	_begin_turns()
	return true


func _begin_turns() -> void:
	if pos[0] != pos[1]:
		var lag := 0 if pos[0] < pos[1] else 1
		order = [lag, 1 - lag]
	else:
		order = [tie_first, 1 - tie_first]
	turn_i = 0
	_start_turn()


func _start_turn() -> void:
	turn_team = order[turn_i]
	wrong = 0
	phase = "turn_ready"


# --- Ход ----------------------------------------------------------------------

## Объясняющий прочитал слово — время пошло (хост вызывает через ~3 с).
func start_timer() -> bool:
	if phase != "turn_ready":
		return false
	phase = "turn"
	return true


## Объясняющий: «Отгадали!»
func guessed(seat: int) -> bool:
	if phase != "turn" or seat != explainer(turn_team):
		return false
	_end_turn(true, "guessed")
	return true


## Соперники: ловушка (line — номер строки, -1 если не указан).
func trap_hit(by_team: int, line: int = -1) -> bool:
	if phase != "turn" or by_team == turn_team:
		return false
	var back: bool = line >= 0 and line == horror[by_team]
	_end_turn(false, "horror" if back else "trap", line)
	return true


func violation(by_team: int) -> bool:
	if phase != "turn" or by_team == turn_team:
		return false
	_end_turn(false, "violation")
	return true


func wrong_guess(by_team: int) -> bool:
	if phase != "turn":
		return false
	wrong += 1
	if wrong >= max_guesses(turn_team):
		_end_turn(false, "guesses")
	return true


## Догадка текстом от игрока отгадывающей команды.
func text_guess(seat: int, text: String) -> bool:
	if phase != "turn" or players[seat]["team"] != turn_team or seat == explainer(turn_team):
		return false
	if guess_matches(text, secret[turn_team]):
		_end_turn(true, "guessed")
	else:
		wrong_guess(1 - turn_team)
	return true


func time_up() -> bool:
	if phase != "turn":
		return false
	_end_turn(false, "time")
	return true


func _end_turn(ok: bool, reason: String, line: int = -1) -> void:
	var t := turn_team
	var entry := {"team": t, "ok": ok, "reason": reason, "word": secret[t], "line": line, "wrong": wrong, "explainer": explainer(t)}
	if ok:
		if fighting[t]:
			winners.append(t)
		else:
			pos[t] = mini(pos[t] + 1, monster_pos)
	elif reason == "horror":
		pos[t] = maxi(pos[t] - 1, 0)
	turn_log.append(entry)
	phase = "turn_result"


## Хост: дальше (после итога хода / раунда).
func advance() -> void:
	match phase:
		"turn_result":
			turn_i += 1
			if turn_i < order.size():
				_start_turn()
			else:
				_end_round()
		"round_result":
			_start_round()


func _end_round() -> void:
	var advanced := false
	for e in turn_log:
		if e["ok"]:
			advanced = true
	var monster_moved := false
	if not winners.is_empty():
		phase = "game_over"
		return
	if not advanced and not fighting[0] and not fighting[1]:
		monster_pos = maxi(monster_pos - 1, 0)
		monster_moved = true
		_push_curse(monster_pos)
	# сыгранные проклятия сбрасываются (в режиме «проклятия не сгорают» — остаются в комнате)
	if not persistent_curses:
		for t in 2:
			if curses.has(start_pos[t]) and active_curses[t].has(curses[start_pos[t]]):
				curses.erase(start_pos[t])
	torch[0] += 1
	torch[1] += 1
	tie_first = 1 - tie_first
	if round_no >= MAX_ROUNDS:
		monster_won = true
		phase = "game_over"
		return
	phase = "round_result"
	turn_log.append({"monster_moved": monster_moved})


## Монстр вошёл в комнату с проклятием — проклятие сдвигается на комнату ближе (каскадом).
func _push_curse(i: int) -> void:
	if not curses.has(i) or i <= 0:
		return
	var id: String = curses[i]
	curses.erase(i)
	if curses.has(i - 1):
		_push_curse(i - 1)
	curses[i - 1] = id


# --- Догадки текстом: грубое сравнение по основе слова ----------------------------

const ENDINGS := ["иями", "ями", "ами", "ого", "его", "ому", "ему", "ыми", "ими", "ов", "ев", "ей", "ам", "ям", "ах", "ях", "ом", "ем", "ой", "ий", "ый", "ая", "яя", "ое", "ее", "ые", "ие", "ую", "юю", "а", "я", "о", "е", "ы", "и", "у", "ю", "ь", "й"]


static func stem(w: String) -> String:
	w = w.to_lower().replace("ё", "е").strip_edges()
	for e in ENDINGS:
		if w.length() > e.length() + 2 and w.ends_with(e):
			w = w.left(w.length() - e.length())
			break
	if w.length() > 3 and (w.ends_with("ь") or w.ends_with("й")):
		w = w.left(w.length() - 1)  # перья → пер(ь) → пер
	return w


static func _tokens(text: String) -> Array:
	var clean := ""
	for ch in text.to_lower().replace("ё", "е"):
		clean += ch if (ch >= "а" and ch <= "я") or ch == "-" else " "
	return Array(clean.split(" ", false)).map(func(x): return stem(x))


## Догадка верна, если в ней есть секретное слово (в любой форме).
static func guess_matches(guess: String, word: String) -> bool:
	var g := _tokens(guess)
	for part in _tokens(word):
		if not g.has(part):
			return false
	return true


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Что видит игрок seat. show_all — тестовый режим на одном компьютере.
func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var my_team: int = players[seat]["team"] if seat >= 0 else -1
	var secrets := ["", ""]
	var trap_view := [[], []]
	var cand_view := [[], []]
	for t in 2:
		var writer := 1 - t  # команда, которая знает слово команды t
		var is_explainer := seat == explainer(t)
		var my_turn_live: bool = phase in ["turn_ready", "turn"] and turn_team == t
		var done := _turn_done(t)
		if show_all or my_team == writer or done or (is_explainer and (my_turn_live)):
			secrets[t] = secret[t]
		# ловушки против команды t видны авторам, а после хода — всем
		if show_all or my_team == writer or done:
			trap_view[writer] = traps[writer].duplicate()
			cand_view[writer] = cands[writer].duplicate(true)
	var curse_board := {}
	for i in curses:
		curse_board[str(i)] = ""  # закрытые
	var active_names := [[], []]
	for t in 2:
		for id in active_curses[t]:
			active_names[t].append(id)
	return {
		"you": seat,
		"my_team": my_team,
		"players": players.duplicate(true),
		"rooms": rooms.duplicate(),
		"pos": pos.duplicate(),
		"monster_pos": monster_pos,
		"monster": monster,
		"hard": hard,
		"curse_rooms": curse_board,
		"active_curses": active_names,
		"fighting": fighting.duplicate(),
		"round_no": round_no,
		"phase": phase,
		"secret": secrets,
		"traps": trap_view,
		"cands": cand_view,
		"horror_cand": horror_cand.duplicate(),
		"words_needed": [words_needed(0), words_needed(1)],
		"trap_lines": [trap_lines(0), trap_lines(1)],
		"double_lines": [_doubles(0), _doubles(1)],
		"ready": ready.duplicate(),
		"ready_votes": ready_votes.duplicate(true),
		"curses_stay": persistent_curses,
		"horror": horror.duplicate(),
		"crossed": crossed.duplicate(),
		"order": order.duplicate(),
		"turn_team": turn_team,
		"explainers": [explainer(0), explainer(1)],
		"wrong": wrong,
		"max_guesses": [max_guesses(0), max_guesses(1)],
		"turn_log": turn_log.duplicate(true),
		"winners": winners.duplicate(),
		"monster_won": monster_won,
		"show_all": show_all,
	}


func _doubles(writer: int) -> Array:
	var list := []
	for i in trap_lines(writer):
		list.append(double_line(writer, i))
	return list


func _turn_done(t: int) -> bool:
	for e in turn_log:
		if e.get("team", -1) == t:
			return true
	return phase in ["round_result", "game_over"]


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


## Объясняющий считается по составу команды — новичок садится только между раундами.
func can_add_player() -> bool:
	return phase == "round_result" and players.size() < 12


func add_player(p: Dictionary) -> bool:
	if not can_add_player():
		return false
	var q := p.duplicate()
	q["team"] = int(p["team"]) if int(p.get("team", -1)) in [0, 1] else _smaller_team()
	players.append(q)
	return true


## Командная игра: в какие команды зритель может войти сам (прогресс общий — он не начинает с нуля).
func teams_for_join() -> Array:
	return [0, 1] if can_add_player() else []
