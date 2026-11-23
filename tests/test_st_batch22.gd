extends SceneTree
## Регрессия таймера «Стиллиона».
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_st_batch22.gd

var _checks := 0
var _failures := 0


func _init() -> void:
	var fixed := _new_game(false)
	_check(not STRules.new().accelerating, "Ускорение выключено по умолчанию")
	fixed.submit(fixed.target, "Абрикос")
	_check(_has_time(fixed, 10.0), "При выключенном ускорении после ответа остаётся 10 секунд")

	var game := _new_game(true)
	_check(_has_time(game, 10.0), "Первый ответ получает полное время")
	game.oral = true
	game.submit_letter(game.target, "ц")
	_check(_has_time(game, 10.0 / 1.05), "Дополнительная буква ускоряет время для следующего игрока")
	game.tick(STRules.AIM_TIME)
	_check(not game.submit_letter(game.target, "ц") and _has_time(game, 10.0 / 1.05), "Отклонённый ответ на занятую букву не ускоряет фитиль")
	game.challenge(game.target)
	_check(game.used.is_empty() and _has_time(game, 10.0), "Оспоренный ответ освобождает букву и возвращает прежнее время")
	game.oral = false
	for i in 22:
		game.tick(STRules.AIM_TIME)
		game.submit(game.target, STRules.MAIN_LETTERS[i] + "тест")
		_check(_has_time(game, 10.0 / (1.0 + minf(i + 1, 20) / 20.0)), "Фитиль после %d ответов" % (i + 1))
	game.tick(STRules.AIM_TIME)
	game.submit(game.target, "Абрикос")
	_check(game.used.size() == 22 and _has_time(game, 5.0), "Отклонённый ответ на занятую букву не учитывается")
	game.tick(4.99)
	_check(game.phase == "fuse", "Перед ускоренным сроком выстрела ещё нет")
	game.tick(0.02)
	_check(game.phase == "boom", "По истечении ускоренного срока пушка стреляет")
	game.tick(STRules.BOOM_TIME)
	_check(game.phase == "new_q" and game.used.is_empty() and _has_time(game, 10.0), "После выстрела новая тема сбрасывает ускорение")
	game.tick(STRules.NEW_Q_TIME)
	game.tick(STRules.AIM_TIME)
	game.submit(game.target, "Банан")
	game.host_new_theme()
	_check(game.phase == "new_q" and game.used.is_empty() and _has_time(game, 10.0), "Смена темы через панель хоста сбрасывает ускорение")
	print("STILLION TIMER: %d проверок, %d ошибок" % [_checks, _failures])
	quit(1 if _failures else 0)


func _new_game(accelerate: bool) -> STRules:
	var game := STRules.new()
	game.accelerating = accelerate
	game.new_game([{"name": "Аня"}, {"name": "Ваня"}], false, 5)
	game.tick(STRules.NEW_Q_TIME)
	game.tick(STRules.AIM_TIME)
	return game


func _has_time(game: STRules, seconds: float) -> bool:
	return is_equal_approx(game.fuse_len, seconds) and is_equal_approx(float(game.get_view(0).fuse_len), seconds)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("ПРОВАЛ: " + message)
