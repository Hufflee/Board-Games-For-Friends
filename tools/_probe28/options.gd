extends SceneTree
## Разовая проверка (07.11): «Больше вариантов» 105 куплена в свой ход — вторая покупка сразу.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _init() -> void:
	var t := Check.new()
	var s = Batch.new()._game(t, 40)
	var g = s.g
	g.coins[0] = 30
	s._take(105)
	g.shop[0] = 105
	print("до: покупок ", g.buy_left, " bought ", g.bought, " (1 — 24/25/26 уже?) атак ", g.attack_left)
	s.ok(0, "buy", {"slot": 0})
	s.close()
	for i in 3:
		if g.phase == "priority": s.close()
	print("после покупки 105: покупок ", g.buy_left, " bought ", g.bought, " предметы ", g.items[0].map(func(e): return int(e.id)), " фаза ", g.phase)
	print("вторая покупка принята: ", g.action(0, "buy", {"slot": 1}))
	quit()
