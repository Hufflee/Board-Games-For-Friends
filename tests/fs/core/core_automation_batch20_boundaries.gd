extends "res://tests/fs/core/core_automation_batch19.gd"
## Фазз201113: обычная атака игрока не расходует обязательную слепую атаку.
func run(t: Check) -> void:
	var mark = _game(t, 28)
	mark.g.required_deck_attacks = 1
	mark.g.deck_attacks = 0
	mark.g.attack_left = 1
	mark.g.attacked = false
	t.check(mark.g._permitted_player_attack_targets().is_empty(), "Метка не предлагает PvP вместо обязательной слепой атаки")
	mark.no(0, "attack_player", {"target": 1}, "PvP не крадёт единственное разрешённое объявление")
	mark.ok(0, "attack", {"slot": -1})
	mark.close()
	t.equal(mark.g._forced_deck_remaining(), 0, "Обязательная слепая атака объявлена без зависания")
