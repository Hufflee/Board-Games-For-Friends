extends SceneTree
## Адресная проверка блокировки мини-игр в окнах ответа и проекции Four Souls.
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_minigame_response_lock.gd

var _checks := 0
var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_errors += 1
		printerr("ОШИБКА: " + message)


func _run() -> void:
	var net := root.get_node("Net")
	net.set_process(false)
	var rules: RefCounted = load("res://games/four_souls/logic/fs_rules.gd").new()
	rules.new_game([{"name": "Первый"}, {"name": "Второй"}], false, 42)
	load("res://tests/fs_test_setup.gd").finish(rules)
	rules.current = 0
	rules.phase = "turn"
	var view: Dictionary = rules.get_view(0)
	view.game = "four_souls"
	check(net._minigame_turn_active(0, view), "Основной ход Four Souls блокирует мини-игры")
	check(not net._minigame_turn_active(1, view), "Ожидающий игрок не заблокирован")
	rules._push({"kind": "roll", "value": 3, "owner": 0}, "turn")
	view = rules.get_view(rules.actor())
	view.game = "four_souls"
	check(view.phase == "priority" and view.response_window == 5.0, "Настоящая проекция публикует полное окно ответа 5 с")
	check(not net._minigame_turn_active(rules.actor(), view), "Ответ Four Souls не блокирует мини-игры")
	for total: float in [0.0, 5.0, 8.0, 8.01, 10.0]:
		view.response_window = total
		view.response_left28 = 1.0
		check(net._minigame_turn_active(rules.actor(), view) == (total <= 0.0 or total > 8.0), "Граница полной длительности ответа: %s с" % total)
	view.erase("response_window")
	check(net._minigame_turn_active(rules.actor(), view), "Неизвестная длительность сохраняет блокировку")
	view.response_window = 5.0
	view.starting_pending = true
	check(net._minigame_turn_active(rules.actor(), view), "Стартовый выбор не считается коротким ответом")
	for phase: String in ["starting_character", "starting_item", "effect", "forced_discard", "battle_roll", "death"]:
		view.phase = phase
		view.actor = 1
		check(net._minigame_turn_active(1, view), "Обязательная фаза Four Souls сохраняет блокировку: " + phase)
	rules.stack = [{"kind": "death", "owner": 0}]
	rules.phase = "priority"
	rules._after_stack = "turn"
	view = rules.get_view(rules.actor())
	view.game = "four_souls"
	check(view.response_window == 10.0, "Проекция окна смерти публикует полные 10 с")
	view.response_left28 = 2.0
	check(net._minigame_turn_active(rules.actor(), view), "Последние 2 с окна смерти остаются заблокированы")
	view = {"game": "gloom", "phase": "react", "react": {"can": [1]}, "turn_left": 1.0}
	check(net._minigame_turn_active(1, view), "Длинный ответ Gloom блокирует даже в последнюю секунду")
	view = {"game": "not_a_hat", "phase": "respond", "receiver": 1}
	for total: int in [0, 8, 9, 60]:
		net.settings.turn_time = total
		net._phase_time = 59.0
		check(net._minigame_turn_active(1, view) == (total != 8), "Ответ «Не та шляпа», полная длительность %d с" % total)
	net.colt = load("res://games/colt_express/logic/ce_rules.gd").new()
	net.colt.phase = "reaction"
	view = {"game": "colt_express", "phase": "reaction", "turn": 1}
	for total: int in [0, 8, 9, 60]:
		net.settings.turn_time = total
		check(net._minigame_turn_active(1, view) == (total != 8), "Ответ Кольт Экспресс, полная длительность %d с" % total)
	net.colt = null
	view = {"game": "king_of_12", "phase": "select", "players": [{}, {}]}
	net.settings.turn_time = 5
	check(net._minigame_turn_active(0, view), "Основной выбор сохраняет блокировку даже при таймере 5 с")
	print("Блокировка мини-игр: %d проверок, %d ошибок" % [_checks, _errors])
	quit(1 if _errors else 0)
