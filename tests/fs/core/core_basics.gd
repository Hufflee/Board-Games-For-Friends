extends RefCounted
## Основа: построитель, детерминированный кубик, клон, законные действия, инварианты ловят порчу.
const FSCheck = preload("res://tests/fs/fs_check.gd")
const FSScenario = preload("res://tests/fs/fs_scenario.gd")
const FSInvariants = preload("res://games/four_souls/logic/fs_invariants.gd")

func run(t: FSCheck) -> void:
	var s := FSScenario.new(t).players(2).current(0).no_items(0).monster(0, 344, {"hp": 2, "dc": 3}).build()
	t.equal(s.g.current, 0, "Текущий — место 0")
	t.check(not s.g.legal_actions(0).is_empty(), "У текущего игрока есть законные действия")
	t.check(s.g.legal_actions(1).all(func(a): return a.kind in ["loot", "activate"]), "У второго в начале хода — только ответы")
	# Детерминированный бросок: 6 — попадание, 1 — промах.
	s.roll(6)
	s.ok(0, "attack", {"slot": 0}, "атака монстра")
	s.g.legal_actions(0)
	s.ok(0, "roll", null, "бросок 6")
	t.equal(s.g.last_roll, 6, "Грань из очереди")
	s.close()
	s.expect("monsters.0.hp", 1, "Попадание снимает 1")
	# Клон независим.
	var copy := s.g.clone()
	t.check(not copy.roll_source.is_valid(), "Клон не держит внешний источник бросков оригинала")
	copy.coins[0] = 99
	t.check(int(s.g.coins[0]) != 99, "Клон не меняет оригинал")
	# Инварианты видят порчу.
	var broken := s.g.clone()
	broken.coins[0] += 1
	t.check(FSInvariants.check(broken, false).any(func(p): return p.begins_with("Монеты")), "Инвариант монет срабатывает")
	broken = s.g.clone()
	broken.hands[1].append(broken.hands[0][0] if not broken.hands[0].is_empty() else broken.decks.loot[0])
	t.check(FSInvariants.check(broken, false).any(func(p): return p.contains("нескольких зонах")), "Инвариант двойной карты срабатывает")
	broken = s.g.clone()
	broken.decks.loot.pop_back()
	t.check(FSInvariants.check(broken, false).any(func(p): return p.contains("потеряна")), "Инвариант потерянной карты срабатывает")
	broken = s.g.clone()
	broken.phase = "refill"
	t.check(FSInvariants.check(broken, true).any(func(p): return p.begins_with("Фаза")), "Служебная фаза — нарушение")
	# zone_of
	var id: int = int(s.g.hands[0][0])
	t.equal(s.zone_of(id), "hand:0", "zone_of находит карту в руке")
