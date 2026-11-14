extends RefCounted
## Бот пользовательской игры (ТЗ редактора, этап «после MVP» №2): случайный допустимый ход.
## Берёт действия из правил (legal_actions) — ответ на вопрос, кнопку, карту, готовность; ручные действия
## свободных зон (перевернуть, перетасовать, переложить) — только если других нет.
## Тест: tests/test_custom_bot.gd

## Выбрать ход места seat: {kind, data} или {} — ходить нечего.
static func choose(rules: Object, seat: int, rng: RandomNumberGenerator) -> Dictionary:
	var legal: Array = rules.legal_actions(seat)
	if legal.is_empty():
		return {}
	var main: Array = legal.filter(func(action: Dictionary): return not str(action.get("kind", "")).begins_with("manual_"))
	var pool: Array = main if not main.is_empty() else legal
	var action: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var data: Dictionary = action.duplicate(true)
	data.erase("kind")
	if action.kind == "answer":
		var pending: Dictionary = rules.state.get("pending", {})
		match str(pending.get("kind", "")):
			"ask_card", "ask_player", "ask_option":
				var options: Array = pending.get("options", [])
				if options.is_empty():
					return {}
				data = {"value": options[rng.randi_range(0, options.size() - 1)]}
			"ask_number":
				data = {"value": rng.randi_range(int(ceilf(float(pending.get("min", 0)))), int(floorf(float(pending.get("max", 0)))))}
			"roll":
				data = {"value": []}
			_:
				return {}
	data["revision"] = rules.state.get("revision", 0)
	return {"kind": str(action.kind), "data": data}
