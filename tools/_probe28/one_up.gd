extends SceneTree
## Разовая проверка (07.11): «Дополнительная жизнь» 142 при смертельном боевом уроне в своей атаке.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _init() -> void:
	var t := Check.new()
	var s = Batch.new()._game(t, 142)
	var g = s.g
	g.hp[0] = 1
	g.monsters[0].at = 3
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(1)
	s.ok(0, "roll")
	for i in 6:
		if g.phase == "priority":
			s.close()
	print("фаза ", g.phase, " бой ", g.battle, " hp ", g.hp[0], " мёртв ", g.dead[0], " атак ", g.attack_left, " предметов ", g.items[0].map(func(e): return int(e.id)), " resolving ", g.resolving.get("card", -1), " после ", g._after_stack)
	print("ошибки ", t.errors.slice(0, 5))
	print("можно атаковать ", g.action(0, "attack", {"slot": 1}), " фаза ", g.phase)
	quit()
