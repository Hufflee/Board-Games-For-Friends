## Узкий риск: Бомба убивает цель после постановки переброса, но до его разрешения.
## Подготовленный бой seed26, исходные грани заданы в стеке; типы событий не подменяются.
## Ожидание из правил Reroll/Fizzle: изменение исчезнувшего броска не создаёт отдельный бросок для пассивов.
## --headless --audio-driver Dummy --script res://tests/test_fs_attack_modifiers_cancel_reroll.gd.
extends "res://tests/test_fs_attack_modifiers_review.gd"

func _initialize() -> void:
	var g := fixture()
	g._gain_item(0, 36)
	g._gain_item(1, 165)
	g.monsters[0].hp = 1
	g.monsters.append({"id": 445, "hp": 20, "dc": 4, "at": 1})
	g.decks.monster = [450]
	g.hands = [[497], [515]]
	g.character_ready = [true, true]
	g.free_loot = 1
	if not queue_attack(g, 6):
		quit(1)
		return
	if not require(g.action(1, "loot", {"card": 515}), "Осколок515 отвечает на исходную атаку"):
		quit(1)
		return
	g._resolve_top()
	if not require(g.action(1, "effect", {"op": "reroll", "target": 0}), "Осколок запросил переброс"):
		quit(1)
		return
	if not require(g.action(0, "effect_roll", {}), "Владелец создал связанный effect_roll"):
		quit(1)
		return
	g.stack.back().value = 4
	if not require(g.action(0, "loot", {"card": 497}), "Бомба497 отвечает поверх связанного переброса"):
		quit(1)
		return
	g._resolve_top()
	if not require(g.resolving.get("card") == 497, "Бомба разрешается первой"):
		quit(1)
		return
	if not require(g.action(0, "effect", {"op": "monster_damage", "item": 0, "amount": 1}), "Бомба наносит цели оставшийся1 урон"):
		quit(1)
		return
	if not require(g.action(0, "effect_done", {}), "Бомба завершена"):
		quit(1)
		return
	g._finish_responses()
	if not require(g.phase == "effect" and g.resolving.get("kind") == "reward", "Открылась награда погибшего Сгустка"):
		quit(1)
		return
	# Напечатанная награда450 проверена по полной локальной карте:4 монеты, без души.
	if not require(g.action(0, "effect", {"op": "coins", "amount": 4}), "Выданы4 монеты настоящей награды450"):
		quit(1)
		return
	if not require(g.action(0, "effect_done", {}), "Награда завершена и исходная атака удалена"):
		quit(1)
		return
	g._finish_responses()
	print("ОТМЕНЁННЫЙ ПЕРЕБРОС: coins=", g.coins, " bank=", g.bank,
		" ordinal=", g._turn_attack_rolls, " resolving=", g.resolving, " stack=", g.stack)
	check(g.coins == [7, 3] and g.bank == 90, "После награды4 нет призрачной выплаты445/165 от осиротевшего переброса")
	check(g._turn_attack_rolls.is_empty(), "Исчезнувшая атака не разрешилась и не увеличила счёт")
	check(g.hp == [20, 20], "Призрачный бой не нанёс урон игрокам")
	check(g.phase == "effect" and g.resolving.get("card") == 515 and int(g.resolving.get("owner", -1)) == 1,
		"Сохранился возврат ручной способности Осколка правильному владельцу1")
	check(g.stack.all(func(entry): return entry.kind not in ["roll", "combat", "player_combat"]),
		"Удалённый исходный бросок не воскрес")
	print("ATTACK MODIFIERS CANCEL REROLL: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
