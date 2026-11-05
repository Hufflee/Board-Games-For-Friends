extends RefCounted
## Регресс фазза44009: после вложенной автоматической карты внешняя сразу получает допустимые выборы.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func run(t: Check) -> void:
	var s := Scenario.new(t).players(2).dlc().current(0).character(0, 821).character(1, 821) \
		.no_items(0).no_items(1).hand(0, [497]).item(1, 834).monster(0, 427).build()
	s.g.bonuses.clear()
	s.g._begin_resolving({"kind": "item", "card": 834, "owner": 1})
	s._take(497)
	s.g._begin_resolving({"kind": "loot", "card": 497, "owner": 0})
	s.g._advance_card_automation()
	s.choose(0, "damage", {"target": 1})
	t.equal(s.g.resolving.get("card"), 834, "Внешняя карта вернулась после Бомбы")
	t.check(not s.g._card_choices().is_empty(), "Внешние варианты создаются в том же действии, без tick и нового жеста")
	t.check(not s.g.legal_actions(1).is_empty(), "Нет ложного зависания после вложенного эффекта")
	s.choose(1, "temporary_attack", {"target": 1})
	t.equal(s.g.attack[1], 2, "Возвращённая карта выполнила выбранное усиление")
	s.inv("Возврат к автоматической карте")
