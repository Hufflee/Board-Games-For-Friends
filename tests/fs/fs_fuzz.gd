extends RefCounted
## Four Souls, тесты: фаззер правил без UI. Случайные действия из FSLegal.candidates (с весами),
## после каждого — FSInvariants.check. При нарушении журнал действий автоматически укорачивается
## (выкидываем куски, пока ошибка воспроизводится), и пишется регресс-кейс в tests/fs/regress/.
## Запуск: tests/fs/run.gd -- --group fuzz [--games 500] [--seed 1] [--steps 800]
const FSCheck = preload("res://tests/fs/fs_check.gd")
const FSScenario = preload("res://tests/fs/fs_scenario.gd")
const FSInvariants = preload("res://games/four_souls/logic/fs_invariants.gd")

const Legal = preload("res://games/four_souls/logic/fs_legal.gd")
const REGRESS_DIR := "res://tests/fs/regress/"

const WEIGHTS := {"roll": 6.0, "death": 6.0, "discard": 6.0, "forced_discard": 6.0, "discard_target": 4.0,
	"choose_starting_item": 6.0, "effect_done": 5.0, "effect_roll": 2.0, "place_bloat": 4.0, "peek_take": 2.0,
	"attack": 3.0, "buy": 2.0, "end": 1.5, "attack_player": 3.0, "room": 0.3, "finish_start": 6.0,
	"loot": 1.0, "activate": 0.8, "effect": 0.25}

static func _store_failure(path: String, evidence: Dictionary) -> void:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	var status := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	assert(status == OK, "Не удалось сохранить свидетельство фаззера")

static func run(t: FSCheck, games: int, first_seed: int, max_steps: int, write_regress: bool, stop_on_failure: bool = false) -> Dictionary:
	var classes := {}
	var stats := {"games": 0, "finished": 0, "steps": 0, "failed": 0}
	for i in games:
		if i > 0 and i % 50 == 0:
			print("FS FUZZ: %d/%d партий, %d действий, %d нарушений" % [i, games, stats.steps, stats.failed])
		var game_seed: int = first_seed + i
		var rng := RandomNumberGenerator.new()
		rng.seed = game_seed * 7919 + 13
		var config := {"players": [2, 2, 3, 4, 4, 6, 8][rng.randi_range(0, 6)], "dlc": rng.randf() < 0.5, "seed": game_seed}
		var result := play(config, rng, max_steps)
		stats.games += 1
		stats.steps += int(result.steps)
		if bool(result.finished): stats.finished += 1
		if result.problem == "":
			continue
		stats.failed += 1
		print("FS FUZZ ОШИБКА: seed=%d, мест=%d, DLC=%s · %s" % [game_seed, int(config.players), str(config.dlc), result.problem])
		var failure_dir := "res://build/fs_tests/fuzz_failures/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(failure_dir))
		var evidence := {"config": config, "problem": result.problem, "steps": result.steps, "log": result.log}
		var evidence_path := failure_dir + "%d.json" % game_seed
		_store_failure(evidence_path, evidence)
		var key := _class_of(str(result.problem))
		if classes.has(key):
			classes[key].count += 1
			continue
		var short: Array = shrink(config, result.log, key)
		evidence["minimized"] = short
		_store_failure(evidence_path, evidence)
		classes[key] = {"count": 1, "config": config, "steps": short.size(), "problem": result.problem}
		var file := ""
		if write_regress:
			file = write_case(config, short, str(result.problem))
		t.errors.append("Фаззер: %s · сид %d, мест %d, DLC %s · укорочено до %d действий%s" %
			[result.problem, game_seed, int(config.players), str(config.dlc), short.size(), (" → " + file) if file != "" else ""])
		if stop_on_failure:
			break
	t.checks += int(stats.games)
	stats["classes"] = classes
	return stats

## Одна партия. log — принятые действия [место, вид, арг, грани кубика].
static func play(config: Dictionary, rng: RandomNumberGenerator, max_steps: int) -> Dictionary:
	var s := _start(config)
	var g := s.g
	var faces: Array = []
	g.roll_source = func() -> int:
		var face := rng.randi_range(1, 6)
		faces.append(face)
		return face
	var log: Array = []
	var problem := ""
	var steps := 0
	while steps < max_steps and g.phase != "game_over":
		var choice := _pick(g, rng)
		if choice.is_empty():
			problem = "Зависание: ни у одного места нет принятого действия (фаза %s)" % g.phase
			break
		faces.clear()
		var accepted := perform(g, int(choice.seat), str(choice.kind), choice.get("arg"))
		steps += 1
		if not accepted:
			continue
		log.append([int(choice.seat), str(choice.kind), choice.get("arg"), faces.duplicate()])
		var found := FSInvariants.check(g, false)
		if not found.is_empty():
			problem = "%s (после %s места %d)" % [found[0], str(choice.kind), int(choice.seat)]
			break
	return {"problem": problem, "log": log, "steps": steps, "finished": g.phase == "game_over"}

static func _start(config: Dictionary) -> FSScenario:
	var s := FSScenario.new(FSCheck.new())
	s.hang_check = false
	s.players(int(config.players)).dlc(bool(config.dlc)).with_seed(int(config.seed)).build()
	return s

## Случайное действие по весам; пробуем кандидатов на копии, пока одно не будет принято.
static func _pick(g: FSRules, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	for seat in g.players.size():
		for candidate: Dictionary in Legal.candidates(g, seat):
			var kind: String = str(candidate.kind)
			if kind == "effect" and str(candidate.arg.op) == "souls" and str(g.resolving.get("kind", "")) != "reward":
				continue
			var weight: float = float(WEIGHTS.get(kind, 1.0))
			# Душа за награду — чтобы партии доходили до победы и проверялся game_over.
			if kind == "effect" and str(candidate.arg.op) == "souls":
				weight = 6.0
			if seat != g.current and kind in ["loot", "activate"]:
				weight *= 0.3
			candidate["seat"] = seat
			candidate["w"] = weight
			pool.append(candidate)
	while not pool.is_empty():
		var total := 0.0
		for c: Dictionary in pool: total += float(c.w)
		var roll := rng.randf() * total
		var index := 0
		while index < pool.size() - 1 and roll > float(pool[index].w):
			roll -= float(pool[index].w); index += 1
		var chosen: Dictionary = pool.pop_at(index)
		var trial := g.clone()
		trial.roll_source = func() -> int: return 3
		if trial.action(int(chosen.seat), str(chosen.kind), chosen.get("arg")):
			return chosen
	if Legal.advance_clock(g.clone()):
		return {"seat": g.current, "kind": "_clock", "arg": null}
	return {}

## Служебные часы стенда не отправляются в сетевой action().
static func perform(g: FSRules, seat: int, kind: String, arg) -> bool:
	return Legal.advance_clock(g) if kind == "_clock" else g.action(seat, kind, arg)

## Повтор журнала с записанными гранями. Возвращает класс первой ошибки или "".
static func replay(config: Dictionary, log: Array) -> String:
	var s := _start(config)
	var g := s.g
	var queue: Array = []
	g.roll_source = func() -> int: return int(queue.pop_front()) if not queue.is_empty() else 3
	for entry: Array in log:
		queue.clear()
		queue.append_array(entry[3])
		if not perform(g, int(entry[0]), str(entry[1]), entry[2]):
			continue
		var found := FSInvariants.check(g, false)
		if not found.is_empty():
			return _class_of(found[0])
		if not _any_action(g):
			return _class_of("Зависание")
	return ""

static func _any_action(g: FSRules) -> bool:
	return g.phase == "game_over" or not _pick(g, RandomNumberGenerator.new()).is_empty()

## Укорачивание: выкидываем куски журнала, пока воспроизводится та же ошибка.
static func shrink(config: Dictionary, log: Array, key: String) -> Array:
	var current := log.duplicate()
	if replay(config, current) != key:
		return current
	var chunk: int = maxi(1, current.size() / 2)
	var budget := 60
	while chunk >= 1 and budget > 0:
		var i := 0
		var removed := false
		while i < current.size() and budget > 0:
			var candidate := current.slice(0, i) + current.slice(i + chunk)
			budget -= 1
			if replay(config, candidate) == key:
				current = candidate
				removed = true
			else:
				i += chunk
		if not removed:
			chunk /= 2
	# Оставляем только действия, которые реально принимаются при повторе.
	return _accepted_only(config, current)

static func _accepted_only(config: Dictionary, log: Array) -> Array:
	var s := _start(config)
	var g := s.g
	var queue: Array = []
	g.roll_source = func() -> int: return int(queue.pop_front()) if not queue.is_empty() else 3
	var out: Array = []
	for entry: Array in log:
		queue.clear()
		queue.append_array(entry[3])
		if perform(g, int(entry[0]), str(entry[1]), entry[2]):
			out.append(entry)
			if not FSInvariants.check(g, false).is_empty():
				break
	return out

## Класс ошибки без чисел: одинаковые нарушения с разными картами/местами — одна строка.
static func _class_of(problem: String) -> String:
	var text := problem.split(" (после ")[0]
	var regex := RegEx.create_from_string("\\d+|\\([^)]*\\)")
	return regex.sub(text, "#", true)

static func write_case(config: Dictionary, log: Array, problem: String) -> String:
	var steps: Array = []
	for entry: Array in log:
		if not entry[3].is_empty():
			steps.append(["roll"] + entry[3])
		var step: Array = ["ok", entry[0], entry[1]]
		if entry[2] != null:
			step.append(entry[2])
		steps.append(step)
	var name := "fuzz_%d_%d" % [int(config.seed), int(config.players)]
	var text := "extends RefCounted\n## Регресс фаззера (сгенерирован tests/fs/fs_fuzz.gd). Ошибка: %s\n" % problem.replace("\n", " ")
	text += "## Когда баг исправлен — убрать \"bug\" (кейс станет обычным) или удалить файл, если он дублирует кейс в cases/.\n"
	text += "const CASES := [{\n\t\"name\": %s,\n\t\"bug\": \"фаззер\",\n" % var_to_str(problem.left(120))
	text += "\t\"setup\": {\"players\": %d, \"dlc\": %s, \"seed\": %d},\n" % [int(config.players), str(config.dlc).to_lower(), int(config.seed)]
	text += "\t\"do\": [\n"
	for step in steps:
		text += "\t\t%s,\n" % var_to_str(step).replace("\n", " ")
	text += "\t],\n}]\n"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REGRESS_DIR))
	var path := REGRESS_DIR + name + ".gd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path
