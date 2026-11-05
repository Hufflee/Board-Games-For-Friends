extends RefCounted
## Особые монеты: передача разыгранной карты, дополнительный бросок и чужая перезарядка.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _game(t: Check, card: int):
	return Scenario.new(t).players(2).dlc().current(0).character(0, 821).character(1, 821) \
		.no_items(0).no_items(1).hand(0, [card]).coins(0, 0).build()

func run(t: Check) -> void:
	var gift = _game(t, 506)
	gift.ok(0, "loot", {"card": 506})
	gift.close()
	gift.no(0, "effect", {"op": "self_give", "target": 0}, "Нельзя отдать сыгранную карту самому себе")
	gift.roll(2)
	gift.ok(0, "effect_roll")
	gift.close()
	t.equal(gift.zone_of(506), "hand:1", "Та же физическая карта переходит в чужую руку")
	gift.no(0, "effect", {"op": "self_give", "target": 1}, "Нельзя повторно передать уже перемещённую карту")
	gift.no(0, "effect", {"op": "self_underdeck"}, "Переданную карту нельзя ещё и положить под колоду")
	gift.no(0, "effect_done", null, "Автоматический эффект уже завершён")
	t.equal(gift.zone_of(506), "hand:1", "Завершение не отправляет переданную карту в сброс")
	gift.inv("Передача Липкого пятака")
	var cancel = _game(t, 506)
	cancel.ok(0, "loot", {"card": 506})
	cancel.close()
	cancel.roll(2)
	cancel.ok(0, "effect_roll")
	cancel.close()
	cancel.g._cancel_unresolved()
	cancel.g.resolving = {} # _cancel_unresolved вызывается штатно перед очисткой текущего эффекта.
	t.equal(cancel.zone_of(506), "hand:1", "Отмена остатка эффекта не дублирует переданную карту")
	cancel.inv("Отмена после передачи")
	var roll = _game(t, 476)
	roll.ok(0, "loot", {"card": 476})
	roll.close()
	roll.no(0, "effect", {"op": "coins", "amount": 1}, "Повтор автоматической выплаты запрещён")
	roll.roll(4)
	roll.ok(0, "effect_roll", null)
	roll.close()
	t.equal(roll.g.last_roll, 4, "После монеты доступен отдельный настоящий бросок")
	roll.no(0, "effect_done", null, "Карта завершена автоматически")
	t.equal(roll.g.coins[0], 1, "Ручной номинал не начисляется второй раз автоматически")
	var recharge = _game(t, 544)
	recharge.g.items[1][0].tapped = true
	recharge.ok(0, "loot", {"card": 544})
	recharge.close()
	var choices: Array = recharge.g._card_choices()
	for i in choices.size():
		if int(choices[i].arg.get("target", -1)) == 1:
			recharge.ok(0, "card_choice", {"index": i, "revision": recharge.g.revision})
			break
	t.check(not recharge.g.items[1][0].tapped, "Заряженный пенни позволяет перезарядить чужой предмет")
	recharge.inv("Чужая перезарядка")
