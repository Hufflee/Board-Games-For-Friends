extends SceneTree
## Разовая проверка (07.11): хост добавляет +1 к броску атаки в стеке через «Панель хоста» без эффекта.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _init() -> void:
	var t := Check.new()
	var s = Batch.new()._game(t, 40)
	var g = s.g
	g.monsters[0].dc = 4
	var hp0: int = int(g.monsters[0].hp)
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(3)
	s.ok(0, "roll")
	print("до: фаза ", g.phase, " стек ", g.stack.map(func(e): return [e.kind, e.get("value", "")]), " эффект пуст ", g.resolving.is_empty())
	print("хост +1: ", g.host_apply28(0, {"op": "roll", "target": 0, "amount": 1}))
	print("после: фаза ", g.phase, " стек ", g.stack.map(func(e): return [e.kind, e.get("value", "")]))
	for i in 5:
		if g.phase == "priority": s.close()
	print("hp монстра ", hp0, " -> ", g.monsters[0].hp, " журнал ", g.log.slice(-4), " ошибки ", t.errors.slice(0, 3))
	quit()
