extends RefCounted
## Four Souls, тесты: исполнитель карточных кейсов-таблиц (tests/fs/cases/*.gd, tests/fs/regress/*.gd).
## Файл кейсов — `extends RefCounted` с `const CASES := [ {...}, ... ]`. Строка кейса:
##   "name":  что проверяем (обязательно), "card": номер карты (для отчёта),
##   "setup": players, dlc, seed, room, current, character {место: карта}, hand {место: [id]},
##            items {место: [id или [id, {tapped: true}]]}, no_items [места], monsters {ячейка: id или [id, {hp, dc, at}]},
##            shop {ячейка: id}, curses {место: [id]}, souls {место: [id]}, deck_top {колода: [id]},
##            discard {колода: [id]}, setup_clear_monsters (ряд монстров пуст), coins {место: n}, hp {место: n}
##   "do":    ["ok", место, вид, арг?] · ["no", место, вид, арг?] · ["effect", место, op, {поля}]
##            ["roll", грань, ...] (следующие броски) · ["close"] (закрыть ответы) · ["expect", путь, значение]
##   "expect": {путь: значение} — пути FSScenario.value_at («coins.0», «zone.358», «phase»)
##   "bug":   «FS_BUGS #N» — известный баг: падение не валит прогон, прохождение — повод снять пометку.
const FSCheck = preload("res://tests/fs/fs_check.gd")
const FSScenario = preload("res://tests/fs/fs_scenario.gd")

## > 0 — печатать последние N шагов каждого упавшего кейса (флаг раннера --trace N).
static var trace := 0

static func describe(g: FSRules) -> String:
	var kinds: Array = []
	for e: Dictionary in g.stack: kinds.append("%s:%s" % [e.kind, e.get("card", e.get("value", ""))])
	return "фаза %s · после %s · текущий %d · actor %d · стек %s · resolving %s:%s · paused %d · deaths %s · next %s" % [g.phase, g._after_stack, g.current, g.actor() if not (g.phase == "effect" and g.resolving.is_empty()) else -1, kinds, g.resolving.get("kind", "-"), g.resolving.get("card", ""), g.paused_effects.size(), g._death_queue, g.next_action.get("kind", "-")]

static func run_file(t: FSCheck, path: String, known: Array) -> void:
	var script: GDScript = load(path)
	var cases: Array = script.get_script_constant_map().get("CASES", [])
	for c: Dictionary in cases:
		run_case(t, c, path.get_file(), known)

static func run_case(t: FSCheck, c: Dictionary, file: String, known: Array) -> void:
	var own := FSCheck.new()
	own.prefix = "%s · %s%s" % [file, ("[%d] " % int(c.card)) if c.has("card") else "", str(c.name)]
	var s := FSScenario.new(own)
	if bool(c.get("legacy_manual_rewards", false)):
		s.rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd"))
	var setup: Dictionary = c.get("setup", {})
	s.players(int(setup.get("players", 2))).dlc(bool(setup.get("dlc", false))).with_seed(int(setup.get("seed", 77)))
	for seat in setup.get("character", {}): s.character(int(seat), int(setup.character[seat]))
	if setup.has("room"): s.room(int(setup.room))
	if setup.has("current"): s.current(int(setup.current))
	for seat in setup.get("no_items", []): s.no_items(int(seat))
	for seat in setup.get("hand", {}): s.hand(int(seat), setup.hand[seat])
	for seat in setup.get("items", {}):
		for id in setup.items[seat]:
			if id is Array: s.item(int(seat), int(id[0]), id[1])
			else: s.item(int(seat), int(id))
	if bool(setup.get("setup_clear_monsters", false)):
		s.setup(func(game: FSRules) -> void:
			for m: Dictionary in game.monsters: game.discards.monster.append(int(m.id))
			game.monsters.clear())
	for slot in setup.get("monsters", {}):
		var m = setup.monsters[slot]
		if m is Array: s.monster(int(slot), int(m[0]), m[1] if m.size() > 1 else {})
		else: s.monster(int(slot), int(m))
	for slot in setup.get("shop", {}): s.shop(int(slot), int(setup.shop[slot]))
	for seat in setup.get("curses", {}):
		for id in setup.curses[seat]: s.curse(int(seat), int(id))
	for seat in setup.get("souls", {}):
		for id in setup.souls[seat]: s.soul(int(seat), int(id))
	for kind in setup.get("deck_top", {}): s.deck_top(str(kind), setup.deck_top[kind])
	for kind in setup.get("discard", {}): s.discard(str(kind), setup.discard[kind])
	for seat in setup.get("coins", {}): s.coins(int(seat), int(setup.coins[seat]))
	for seat in setup.get("hp", {}): s.hp(int(seat), int(setup.hp[seat]))
	s.build()
	var lines: Array = []
	for step: Array in c.get("do", []):
		match str(step[0]):
			"ok": s.ok(int(step[1]), str(step[2]), step[3] if step.size() > 3 else null)
			"no": s.no(int(step[1]), str(step[2]), step[3] if step.size() > 3 else null)
			"effect": s.effect(int(step[1]), str(step[2]), step[3] if step.size() > 3 else {})
			"choose": s.choose(int(step[1]), str(step[2]), step[3] if step.size() > 3 else {})
			"operation_panel": s.operation_panel(int(step[1]) if step.size() > 1 else 0)
			"roll": s.roll(int(step[1]), step.slice(2))
			"close": s.close()
			"expect": s.expect(str(step[1]), step[2], "шаг %s" % str(step))
			_: own.check(false, "Неизвестный шаг кейса: " + str(step))
		if trace > 0 and str(step[0]) != "roll":
			lines.append("%s → %s" % [str(step), describe(s.g)])
	var expect: Dictionary = c.get("expect", {})
	for path in expect:
		s.expect(str(path), expect[path])
	t.checks += own.checks
	if trace > 0 and not own.errors.is_empty():
		print("--- трасса %s (последние %d шагов)" % [own.prefix, trace])
		for line in lines.slice(maxi(0, lines.size() - trace)): print("  " + line)
	if c.has("bug"):
		if own.errors.is_empty():
			known.append("ПРОШЁЛ (снять пометку %s?): %s" % [c.bug, own.prefix])
		else:
			known.append("известный %s: %s — %s" % [c.bug, own.prefix, own.errors[0]])
	else:
		t.errors.append_array(own.errors)
