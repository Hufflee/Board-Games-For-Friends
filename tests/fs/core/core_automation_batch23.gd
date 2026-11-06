extends "res://tests/fs/core/core_automation_batch21.gd"
## Все39 напечатанных номиналов и различие получения монет и их передачи у675.
func run(t: Check) -> void:
	for group in [[666, 671, 1], [588, 596, 2], [597, 611, 3], [612, 620, 4]]:
		for id in range(int(group[0]), int(group[1]) + 1):
			t.equal(FSData.coin_loot_value(id), int(group[2]), "Монеты%d совпадают с текстом" % id)
	var counterfeit = _game(t, 675)
	_play21(counterfeit, 588)
	t.equal(counterfeit.g.coins[0], 11, "675 прибавляет1¢ к получению обычных монет")
	counterfeit.ok(1, "trade", {"target": 0, "amount": 2})
	t.equal(counterfeit.g.coins[0], 13, "675 не создаёт монету при передаче")
