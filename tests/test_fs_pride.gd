extends "res://tests/test_fs_passive_fixes.gd"
## Гордыня: выбор цели, приватный сброс, ответы и возврат к бою.
func ready() -> FSRules:
	var g := make()
	g.phase = "turn"
	g.resolving = {}
	g.stack.clear()
	g.next_action = {}
	g.monsters = [{"id":396,"hp":3,"dc":4,"at":1},{"id":450,"hp":3,"dc":4,"at":1}]
	g.hands = [[475,476,477],[478,479,480]]
	g.attacked = false
	g._after_stack = "turn"
	return g

func _initialize() -> void:
	var g := ready()
	check(g.action(0,"attack",{"slot":0}), "Атака Гордыни объявлена")
	check(g.action(0,"roll") and g.phase == "discard_target", "Первый бросок ждёт обязательный выбор цели")
	check(not g.action(1,"discard_target",{"target":0}), "Неактивный не выбирает цель")
	check(not g.action(0,"discard_target",{"target":9}), "Недопустимая цель отклонена")
	check(g.action(0,"discard_target",{"target":1}), "Активный выбрал другого игрока")
	check(g.phase == "priority" and g.stack.back().kind == "forced_discard", "До сброса доступны ответы")
	check(g.action(0,"roll"), "Отложенный бросок позволяет закрыть ответы на обязательный сброс")
	check(g.phase == "forced_discard" and g.actor() == 1, "После ответов карты выбирает их владелец")
	check(not g.get_view(0).players[1].has("hand") and g.get_view(0).hand == [475,476,477], "Чужие карты не раскрываются активному")
	check(not g.action(0,"forced_discard",{"item":0}), "Активный не сбрасывает чужую руку")
	check(not g.action(1,"forced_discard",{"item":9}), "Недопустимый индекс отклонён")
	check(not g.action(0,"roll"), "Нельзя бросить до обязательного сброса")
	check(g.action(1,"forced_discard",{"item":1}), "Владелец выбрал первую карту")
	check(g.hands[1] == [478,480] and g.discard_choice.remaining == 1, "Сброшена именно выбранная карта")
	check(g.action(1,"forced_discard",{"item":0}), "Владелец выбрал вторую карту")
	check(g.hands[1] == [480] and g.discards.loot.has(479) and g.discards.loot.has(478), "Обе карты в сбросе без чужого лута")
	check(g.roll_no == 1 and g.phase == "priority", "После выбора выполнен один отложенный бросок")
	check(not g.action(1,"forced_discard",{"item":0}), "Повтор не списывает третью карту")
	for count in [0,1,2]:
		g = ready()
		g.hands[1] = [478,479].slice(0,count)
		g.action(0,"attack",{"slot":0})
		g._finish_responses()
		g.action(0,"discard_target",{"target":1})
		g._finish_responses()
		for index in count:
			check(g.action(1,"forced_discard",{"item":0}), "Короткая рука: сброс доступной карты")
		check(g.hands[1].is_empty() and g.phase == "battle_roll", "Нет зависания при руке из " + str(count) + " карт")
	g = ready()
	g.decks.monster = [396]
	g.action(0,"attack",{"slot":-1,"over":1})
	g._finish_responses()
	check(g.phase == "discard_target" and g.battle == 1, "Гордыня с верха колоды тоже требует сброс")
	g.action(0,"discard_target",{"target":0})
	g._finish_responses()
	check(g.actor() == 0 and g.action(0,"forced_discard",{"item":0}), "Можно выбрать и собственную руку")
	g = ready()
	g.hands[1] = [475]
	g.action(0,"attack",{"slot":0})
	g._finish_responses()
	g.action(0,"discard_target",{"target":1})
	check(g.action(1,"loot",{"card":475}), "Цель может сыграть лут ответом до сброса")
	g._finish_responses()
	check(g.hands[1].is_empty() and g.phase == "battle_roll", "Сброс не запирает бой после расхода последней карты в ответ")
	g = ready()
	g.action(0,"attack",{"slot":0})
	g._finish_responses()
	g.new_game([{"name":"А"},{"name":"Б"}],false,26)
	check(g.discard_choice.is_empty(), "Новая партия не наследует обязательный выбор")
	print("PRIDE: ",checks," проверок, ",errors," ошибок")
	quit(1 if errors else 0)
