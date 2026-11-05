extends "res://tests/fs/core/core_automation_batch17.gd"
## Копия сохраняет внутренние связи source/pending, не связывая две партии.
func run(t: Check) -> void:
	var s = _monster(t, 339)
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(6)
	s.ok(0, "roll")
	s.close()
	var copy = s.g.clone()
	t.equal(copy.actor(), s.g.actor(), "Копия сохраняет бросающего участника совместной атаки")
	t.check(is_same(copy._team_source15, copy.monsters[copy.battle]), "Источник командной атаки связан с монстром копии")
	t.check(not is_same(copy._team_source15, s.g._team_source15), "Копия не ссылается на исходного монстра")
	t.check(copy.legal_actions(copy.actor()).any(func(action): return action.kind == "roll"), "Бросок напарника виден среди законных действий")
	var source: Dictionary = s.g.items[0][0]
	var pending := {"kind": "damage16", "damage": 2, "owner": 0}
	s.g.stack = [pending]
	s.g.resolving = {"kind": "item", "card": 324, "owner": 0, "source": source, "automation_data": {"pending": pending}}
	s.g._temporary_eternal = [{"source": source, "eternal": true}]
	copy = s.g.clone()
	t.check(is_same(copy.resolving.source, copy.items[0][0]), "Пассив и предмет связаны внутри копии")
	t.check(is_same(copy._temporary_eternal[0].source, copy.items[0][0]), "Временная вечность связана с тем же предметом")
	copy.resolving.automation_data.pending.damage = 0
	t.equal(copy.stack[0].damage, 0, "Замещение урона меняет ожидающий эффект копии")
	t.equal(s.g.stack[0].damage, 2, "Замещение в копии не меняет исходный стек")
	var equal_a := {"id": 143}
	var equal_b := {"id": 143}
	var duplicated: Array = s.g._clone_container([equal_a, equal_b, equal_a], {})
	t.check(not is_same(duplicated[0], duplicated[1]), "Разные одинаковые словари не объединяются")
	t.check(is_same(duplicated[0], duplicated[2]), "Повторная ссылка на словарь остаётся общей")
