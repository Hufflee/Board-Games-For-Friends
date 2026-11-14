extends RefCounted
## Мини-игра «Сапёр» (соло): правила без UI. Поле 16×16.
##   classic — обычный сапёр в один слой, 40 мин; открыты все клетки без мин — победа.
##   deep — бесконечный режим: под каждым слоем лежит следующий, у каждого свои мины и числа,
##     слои друг на друга не влияют. Клетка нижнего слоя видна, только если открытая клетка слоя над ней
##     пустая (без числа) или с числом, вокруг которого всё разминировано: соседи без мин открыты, на минах флажки. Если флажки слоя стоят
##     ровно на всех его минах (лишних нет) или открыты все его клетки без мин — слой пройден и сбрасывается
##     целиком, под ним открывается следующий. Мина — сразу конец; счёт — глубина: пройденные подряд сверху
##     слои + 1 (прошли первый — глубина 2; заглянуть глубже в одной клетке ничего не даёт).
## Действия: {"open": клетка} и {"flag": клетка} — к самому глубокому видимому слою в этой клетке.
## Мины слоя расставляются при первом открытии клетки в нём, на любом слое одинаково: эта клетка и соседи
## без мин (открывается пустая область), и слой без угадывания — мины перекладываются, пока поле не решается
## логикой от первой клетки (solvable), — никаких 50/50 в конце. Провал вглубь по пустым клеткам очков не даёт:
## глубина считается только по пройденным слоям.
## Тесты: godot --headless --path . --script res://tests/test_minigames.gd

const N := 16
const CELLS := N * N
const CLASSIC_MINES := 40
const GENERATE_TRIES := 400  # сколько раскладок перебрать в поисках решаемой без угадывания
const MAX_DEEP_MINES := 55  # гуще поле 16×16 без угадывания почти не бывает (замер tools/_mg_probe/mines_gen_bench.gd)


static func new_state(opts: Dictionary = {}) -> Dictionary:
	var mode := "deep" if str(opts.get("mode", "")) == "deep" else "classic"
	var seed_value := int(opts.get("seed", randi()))
	return {"game": "mines", "mode": mode, "seed": seed_value, "layers": [_new_layer(0, mode)], "turn": 0,
		"over": false, "winner": -1, "reason": "", "depth": 1, "moves": 0, "boom": [],
		"elapsed": 0.0, "paused": false}  # секундомер обычного сапёра (идёт с первого хода, ведёт mg_net)


## Секундомер обычного сапёра: «ММ:СС».
static func clock_text(seconds: float) -> String:
	var whole := int(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]


## Идёт ли секундомер: обычный сапёр, первый ход сделан, игра не окончена.
static func clock_running(state: Dictionary) -> bool:
	return str(state.get("mode", "")) == "classic" and int(state.get("moves", 0)) > 0 and not bool(state.get("over", false))


static func mines_for(index: int, mode: String) -> int:
	return CLASSIC_MINES if mode == "classic" else mini(CLASSIC_MINES + 3 * index, MAX_DEEP_MINES)


static func _new_layer(index: int, mode: String) -> Dictionary:
	var zeros := []
	zeros.resize(CELLS)
	zeros.fill(0)
	return {"count": mines_for(index, mode), "ready": false, "cleared": false,
		"mine": zeros.duplicate(), "num": zeros.duplicate(), "open": zeros.duplicate(), "flag": zeros.duplicate()}


static func neighbors(sq: int) -> Array[int]:
	var out: Array[int] = []
	var r := sq / N
	var c := sq % N
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var rr: int = r + dr
			var cc: int = c + dc
			if rr >= 0 and rr < N and cc >= 0 and cc < N:
				out.append(rr * N + cc)
	return out


static func layer(state: Dictionary, index: int) -> Dictionary:
	var layers: Array = state.layers
	while layers.size() <= index:
		layers.append(_new_layer(layers.size(), str(state.mode)))
	return layers[index]


## Сквозь открытую клетку слоя виден слой под ней.
static func see_through(lay: Dictionary, sq: int) -> bool:
	if bool(lay.cleared):
		return true
	if int(lay.open[sq]) == 0 or int(lay.mine[sq]) == 1:
		return false
	if int(lay.num[sq]) == 0:
		return true
	# число прозрачно, только когда вокруг всё разминировано: безопасные соседи открыты, на минах флажки
	for near: int in neighbors(sq):
		if int(lay.mine[near]) == 0 and int(lay.open[near]) == 0:
			return false
		if int(lay.mine[near]) == 1 and int(lay.flag[near]) == 0:
			return false
	return true


## Самый глубокий видимый слой в клетке (с ним и работают действия).
static func depth_at(state: Dictionary, sq: int) -> int:
	if str(state.mode) == "classic":
		return 0
	var d := 0
	while see_through(layer(state, d), sq):
		d += 1
	return d


## Верхний ещё не сброшенный слой.
static func top_layer(state: Dictionary) -> int:
	var d := 0
	while bool(layer(state, d).cleared):
		d += 1
	return d


## Сколько мин осталось найти на верхнем слое: мины минус любые флажки на нём.
static func mines_left(state: Dictionary) -> int:
	var lay := layer(state, top_layer(state))
	return int(lay.count) - int((lay.flag as Array).count(1))


static func _generate(state: Dictionary, index: int, safe: int) -> void:
	var lay := layer(state, index)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(state.seed) * 7919 + index * 104729
	var banned := {safe: true}
	for near: int in neighbors(safe):
		banned[near] = true  # первый клик слоя — пустая клетка: сразу открывается область
	var free: Array[int] = []
	for sq in CELLS:
		if not banned.has(sq):
			free.append(sq)
	# без угадывания: перекладываем мины, пока поле не решается логикой от первой клетки
	var mine := []
	for attempt in GENERATE_TRIES:
		for i in range(free.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var keep := free[i]
			free[i] = free[j]
			free[j] = keep
		mine.resize(CELLS)
		mine.fill(0)
		for i in mini(int(lay.count), free.size()):
			mine[free[i]] = 1
		if solvable(mine, safe):
			break
	lay.mine = mine
	lay.num = numbers(mine)
	lay.ready = true


static func numbers(mine: Array) -> Array:
	var out := []
	out.resize(CELLS)
	for sq in CELLS:
		var count := 0
		for near: int in neighbors(sq):
			count += int(mine[near])
		out[sq] = count
	return out


## Решается ли поле без угадывания, если первой открыта клетка start: простые правила по числу,
## сравнение пар соседних чисел (одно — часть другого) и общий счёт мин в конце.
static func solvable(mine: Array, start: int) -> bool:
	var num := numbers(mine)
	var total := int(mine.count(1))
	var known := []  # 0 — неизвестно, 1 — открыта, 2 — точно мина
	known.resize(CELLS)
	known.fill(0)
	var safe_left := [CELLS - total]
	_solver_open(known, num, mine, start, safe_left)
	while int(safe_left[0]) > 0:
		var changed := false
		var cons := {}  # клетка с числом → [неизвестные соседи, сколько среди них мин]
		for sq in CELLS:
			if int(known[sq]) != 1 or int(num[sq]) == 0:
				continue
			var unknown: Array[int] = []
			var need := int(num[sq])
			for near: int in neighbors(sq):
				if int(known[near]) == 0:
					unknown.append(near)
				elif int(known[near]) == 2:
					need -= 1
			if unknown.is_empty():
				continue
			if need == 0 or need == unknown.size():
				for cell: int in unknown:
					if need == 0:
						_solver_open(known, num, mine, cell, safe_left)
					else:
						known[cell] = 2
				changed = true
			else:
				cons[sq] = [unknown, need]
		if changed:
			continue
		# пары: неизвестные одного числа целиком внутри неизвестных соседнего
		for a: int in cons:
			var set_a: Array = cons[a][0]
			for b: int in cons:
				if a == b or absi(a / N - b / N) > 2 or absi(a % N - b % N) > 2:
					continue
				var set_b: Array = cons[b][0]
				if set_a.size() >= set_b.size() or not set_a.all(func(cell: int) -> bool: return set_b.has(cell)):
					continue
				var rest := set_b.filter(func(cell: int) -> bool: return not set_a.has(cell))
				var need := int(cons[b][1]) - int(cons[a][1])
				if need == 0 or need == rest.size():
					for cell: int in rest:
						if int(known[cell]) != 0:
							continue
						if need == 0:
							_solver_open(known, num, mine, cell, safe_left)
						else:
							known[cell] = 2
					changed = true
			if changed:
				break
		if changed:
			continue
		# общий счёт: найдены все мины — остальное безопасно; неизвестных столько, сколько мин осталось — все мины
		var unknown_count := int(known.count(0))
		var mines_left := total - int(known.count(2))
		if mines_left == 0 or mines_left == unknown_count:
			for sq in CELLS:
				if int(known[sq]) == 0:
					if mines_left == 0:
						_solver_open(known, num, mine, sq, safe_left)
					else:
						known[sq] = 2
			continue
		return false
	return true


static func _solver_open(known: Array, num: Array, mine: Array, start: int, safe_left: Array) -> void:
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var sq: int = stack.pop_back()
		if int(known[sq]) != 0 or int(mine[sq]) == 1:
			continue
		known[sq] = 1
		safe_left[0] = int(safe_left[0]) - 1
		if int(num[sq]) == 0:
			for near: int in neighbors(sq):
				if int(known[near]) == 0:
					stack.append(near)


## Ход: {"open": клетка} или {"flag": клетка}. Возвращает "" или причину отказа.
## "open" по открытому числу — открыть соседей, если вокруг столько же флажков (_chord).
static func apply(state: Dictionary, _seat: int, move: Dictionary) -> String:
	if bool(state.over):
		return "Игра окончена"
	var flagging := move.has("flag")
	var sq := int(move.get("flag" if flagging else "open", -1))
	if sq < 0 or sq >= CELLS:
		return "Нет такой клетки"
	var d := depth_at(state, sq)
	var lay := layer(state, d)
	if int(lay.open[sq]) == 1:
		if flagging or int(lay.num[sq]) == 0:
			return "Клетка уже открыта"
		return _chord(state, d, sq)
	state.moves = int(state.moves) + 1
	if flagging:
		lay.flag[sq] = 1 - int(lay.flag[sq])
		_check_cleared(state, d)
		_update_depth(state)
		return ""
	if int(lay.flag[sq]) == 1:
		return "Сначала снимите флажок"
	if not bool(lay.ready):
		_generate(state, d, sq)
	if int(lay.mine[sq]) == 1:
		_explode(state, d, sq)
		return ""
	_flood(lay, sq)
	_after_open(state, d)
	return ""


static func _explode(state: Dictionary, d: int, sq: int) -> void:
	layer(state, d).open[sq] = 1
	state.over = true
	state.boom = [d, sq]
	state.reason = "Мина! " + ("Глубина %d" % int(state.depth) if str(state.mode) == "deep" else "Попробуйте ещё раз")


## Нажатие на открытое число: флажков вокруг столько же, сколько число, — открываются все остальные
## закрытые соседи этого слоя, которые сейчас видны. Флажок стоял не там — откроется мина, конец игры.
static func _chord(state: Dictionary, d: int, sq: int) -> String:
	var lay := layer(state, d)
	var flags := 0
	var closed: Array[int] = []
	for near: int in neighbors(sq):
		if int(lay.flag[near]) == 1:
			flags += 1
		elif int(lay.open[near]) == 0 and depth_at(state, near) == d:
			closed.append(near)
	if flags != int(lay.num[sq]):
		return "Флажков вокруг %d, а число %d" % [flags, int(lay.num[sq])]
	if closed.is_empty():
		return "Вокруг всё открыто"
	state.moves = int(state.moves) + 1
	for near: int in closed:
		if int(lay.mine[near]) == 1:
			_explode(state, d, near)
			return ""
	for near: int in closed:
		_flood(lay, near)
	_after_open(state, d)
	return ""


static func _after_open(state: Dictionary, d: int) -> void:
	var lay := layer(state, d)
	if str(state.mode) == "classic":
		var safe_closed := 0
		for i in CELLS:
			if int(lay.mine[i]) == 0 and int(lay.open[i]) == 0:
				safe_closed += 1
		if safe_closed == 0:
			state.over = true
			state.winner = 0
			state.reason = "Поле разминировано!"
	else:
		_check_cleared(state, d)
		_update_depth(state)


static func _flood(lay: Dictionary, start: int) -> void:
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var sq: int = stack.pop_back()
		if int(lay.open[sq]) == 1 or int(lay.mine[sq]) == 1:
			continue
		lay.open[sq] = 1
		lay.flag[sq] = 0
		if int(lay.num[sq]) == 0:
			for near: int in neighbors(sq):
				if int(lay.open[near]) == 0 and int(lay.flag[near]) == 0:
					stack.append(near)


## Флажки ровно на всех минах слоя — слой сбрасывается.
static func _check_cleared(state: Dictionary, index: int) -> void:
	if str(state.mode) != "deep":
		return
	var lay := layer(state, index)
	if not bool(lay.ready) or bool(lay.cleared):
		return
	if lay.flag == lay.mine:
		lay.cleared = true  # флажки ровно на всех минах
		return
	for sq in CELLS:
		if int(lay.mine[sq]) == 0 and int(lay.open[sq]) == 0:
			return
	lay.cleared = true  # открыты все клетки без мин — слой пройден


## Глубина — сколько слоёв сверху пройдено подряд, плюс один: прошли первый — глубина 2.
## Заглянуть глубже в одной клетке ничего не даёт.
static func _update_depth(state: Dictionary) -> void:
	state.depth = maxi(int(state.depth), top_layer(state) + 1)
