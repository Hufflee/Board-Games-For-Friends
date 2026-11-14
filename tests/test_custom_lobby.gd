extends SceneTree
## Настройки автора в лобби: переменная «в лобби» получает значение хоста (число — в границах, да/нет),
## прочие переменные не меняются, описание пакета несёт список настроек, ошибки данных.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_custom_lobby.gd
const Session := preload("res://games/custom/logic/cg_session.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const Transfer := preload("res://games/custom/logic/cg_transfer.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func game() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	data.rules.vars.append({"id": "goal", "title": "Очков до победы", "scope": "shared", "type": "number", "init": 10, "lobby": true, "lobby_min": 5, "lobby_max": 30})
	data.rules.vars.append({"id": "hard", "title": "Сложный режим", "scope": "shared", "type": "bool", "init": false, "lobby": true})
	data.rules.vars.append({"id": "secret", "title": "Не в лобби", "scope": "shared", "type": "number", "init": 3})
	return data

func _run() -> void:
	var data := game()
	check(Definition.validate(data).errors.is_empty(), "Настройки лобби допустимы: %s" % str(Definition.validate(data).errors))
	var players: Array = [{"name": "А"}, {"name": "Б"}]
	var made: Dictionary = Session.create_definition(data, players, {"vars": {"goal": 25, "hard": true, "secret": 99}})
	check(str(made.error).is_empty(), "Партия с настройками")
	var rules: Object = made.rules
	check(int(rules.state.vars.shared.goal) == 25 and rules.state.vars.shared.hard == true, "Значения хоста стали начальными")
	check(int(rules.state.vars.shared.secret) == 3, "Переменная не из лобби не меняется")
	var clamped: Object = Session.create_definition(data, players, {"vars": {"goal": 100, "hard": "да"}}).rules
	check(int(clamped.state.vars.shared.goal) == 30 and clamped.state.vars.shared.hard == false, "Выход за границы обрезан, неверный тип — значение автора")
	var plain: Object = Session.create_definition(data, players, {}).rules
	check(int(plain.state.vars.shared.goal) == 10, "Без настроек — значение автора")
	var listed: Array = Transfer.lobby_options(data)
	check(listed.size() == 2 and listed[0].id == "goal" and int(listed[0].max) == 30 and listed[1].type == "bool", "Описание пакета несёт настройки: %s" % str(listed))
	var broken := game()
	broken.rules.vars[-1]["lobby"] = true
	broken.rules.vars[-1]["type"] = "text"
	broken.rules.vars[-1]["init"] = "x"
	broken.rules.vars[-3]["lobby_min"] = 20
	var report: Array = Definition.validate(broken).errors
	check(report.any(func(text: String): return text.contains("только число или да/нет")), "Текст в лобби — ошибка")
	check(report.any(func(text: String): return text.contains("не включают начальное")), "Границы без начального значения — ошибка")
	print("CUSTOM LOBBY: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
