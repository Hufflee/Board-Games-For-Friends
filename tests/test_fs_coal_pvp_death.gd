extends "res://tests/test_fs_mixed_next.gd"
## Подготовленная PvP-регрессия: ответ Бомбой на третий бросок, смерть цели и штраф.
## Броски создаёт action, seed подбирается до броска; в стек результаты не внедряются.

func require_step(ok: bool, label: String) -> bool:
	print("ШАГ: ", label, " → ", ok)
	check(ok, label)
	return ok

func _initialize() -> void:
	var g := clean()
	g._gain_item(0, 18)
	g.hp = [10, 3]
	g.max_hp = [10, 3]
	g.hands = [[497], []]
	g.required_player_attacks = 1
	g.monsters = []
	if not require_step(g.action(0, "attack_player", {"target": 1}), "Допустимое объявление PvP после обязательства Завоевателя"):
		quit(2)
		return
	g._finish_responses()
	var rng := RandomNumberGenerator.new()
	var chosen := 0
	for candidate in range(1, 10000):
		rng.seed = candidate
		if rng.randi_range(1, 6) == 6:
			chosen = candidate
			break
	print("SEED=", chosen)
	for i in 2:
		g._rng.seed = chosen
		if not require_step(g.action(0, "roll", {}), "Обычный бросок атаки %d" % (i + 1)):
			quit(2)
			return
		g._finish_responses()
	if not require_step(g.hp[1] == 1 and g.attack[0] == 1, "После двух попаданий цель HP1, владелец ATK1"):
		quit(2)
		return
	g._rng.seed = chosen
	if not require_step(g.action(0, "roll", {}), "Третий бросок ожидает разрешения"):
		quit(2)
		return
	if not require_step(g.action(0, "loot", {"card": 497}), "Бомба разыграна ответом поверх броска"):
		quit(2)
		return
	g._resolve_top()
	if not require_step(g.phase == "effect" and g.resolving.card == 497,
		"Бомба разрешилась в обычную ручную панель"):
		quit(2)
		return
	if not require_step(g.action(0, "effect", {"op": "damage", "target": 1, "amount": 1}), "Бомба наносит цели 1 урона"):
		quit(2)
		return
	if not require_step(g.action(0, "effect_done", {}), "Обычное завершение Бомбы"):
		quit(2)
		return
	g._finish_responses()
	print("ДО ШТРАФА: ", {"phase": g.phase, "battle_player": g.battle_player, "stack": g.stack})
	if not require_step(g.phase == "death" and g.actor() == 1 and g.hp[1] == 0, "Настоящий штраф погибшей PvP-цели"):
		quit(2)
		return
	if not require_step(g.action(1, "death", {}), "Цель подтверждает штраф обычным действием"):
		quit(2)
		return
	g._finish_responses()
	print("ПОСЛЕ ШТРАФА: ", {"phase": g.phase, "battle_player": g.battle_player,
		"attack": g.attack, "roll_count": g._turn_attack_rolls, "stack": g.stack, "dead": g.dead})
	observe(g.attack[0] == 1, "18: отменённый смертью цели третий бросок не даёт бонус", g.attack[0])
	observe(int(g._turn_attack_rolls.get(0, 0)) == 2, "18: после смерти цели остаются два разрешённых броска", g._turn_attack_rolls)
	print("COAL PVP DEATH: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
