extends RefCounted
## Обычные тесты выбирают первую предложенную карту Эдема настоящим действием правил.
## Отдельные проверки выбора не вызывают этот помощник.
static func finish(game: FSRules) -> void:
	for i in 100:
		if game.phase == "starting_item":
			var seat := game.actor()
			var options: Array = game.get_view(seat).starting_options
			assert(not options.is_empty())
			assert(game.action(seat, "choose_starting_item", {"card": int(options[0])}))
		elif game.phase == "priority":
			game._finish_responses()
		else:
			return
	assert(false, "Начальный выбор не завершился")
