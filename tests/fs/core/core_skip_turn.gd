extends RefCounted
## Пропуск целого хода: без добора/перезарядки/триггеров; общая очередь с дополнительными ходами.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _prepare(t: Check, count: int = 3):
	var s := Scenario.new(t).players(count).dlc().current(0).item(0, 7).build()
	for seat in count:
		s.g.decks.loot.append_array(s.g.hands[seat])
		s.g.hands[seat].clear()
	s.g.phase = "effect"
	s.g.resolving = {"kind": "item", "card": 7, "owner": 0}
	return s

func run(t: Check) -> void:
	var s = _prepare(t)
	s.effect(0, "skip_turn", {"target": 1, "amount": 1})
	t.equal(s.g.get_view(2).players[1].skipped_turns, 1, "Ожидающий пропуск виден всем игрокам")
	s.no(1, "effect", {"op": "skip_turn", "target": 0, "amount": 1}, "Чужой игрок не назначает пропуск")
	s.no(0, "effect", {"op": "skip_turn", "target": 1, "amount": 0}, "Нулевой пропуск отклоняется")
	var hand: int = s.g.hands[1].size()
	for item: Dictionary in s.g.items[1]:
		item.tapped = true
	s.g.character_ready[1] = false
	var tapped: Array = s.g.items[1].map(func(item): return item.tapped)
	s.ok(0, "effect_done", null)
	s.close()
	s.ok(0, "end", null)
	s.close()
	t.equal(s.g.current, 2, "После места0 место1 пропущено целиком")
	t.equal(s.g.hands[1].size(), hand, "Пропущенный ход не добирает лут")
	t.equal(s.g.items[1].map(func(item): return item.tapped), tapped, "Пропущенный ход не меняет поворот предметов")
	t.check(not s.g.character_ready[1], "Пропущенный ход не перезаряжает персонажа")
	t.equal(s.g.skipped_turns[1], 0, "Однократный пропуск израсходован")
	s.inv("После пропуска")
	var extra = _prepare(t)
	extra.effect(0, "extra_turn", {"target": 1, "amount": 1})
	extra.effect(0, "skip_turn", {"target": 1, "amount": 1})
	extra.ok(0, "effect_done", null)
	extra.close()
	extra.ok(0, "end", null)
	extra.close()
	t.equal(extra.g.current, 1, "Пропущен дополнительный ход1, затем наступает обычный ход1")
	t.equal(extra.g._turn_resume, -1, "Очередь возврата из дополнительных ходов очищена")
	t.equal(extra.g.skipped_turns[1], 0, "Один пропуск не съедает и дополнительный, и обычный ход")
	var all_skipped = _prepare(t, 2)
	all_skipped.effect(0, "skip_turn", {"target": 0, "amount": 1})
	all_skipped.effect(0, "skip_turn", {"target": 1, "amount": 1})
	all_skipped.ok(0, "effect_done", null)
	all_skipped.close()
	all_skipped.ok(0, "end", null)
	all_skipped.close()
	t.equal(all_skipped.g.current, 1, "Одновременные пропуски обоих мест не зависают")
	t.equal(all_skipped.g.skipped_turns, [0, 0], "Оба отложенных пропуска израсходованы")
