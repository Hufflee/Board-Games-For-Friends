extends SceneTree
## Конструктор цепочек: вложенные ветви, undo, типы переменных и исполнение собранной игры.

const Document := preload("res://editor/ed_document.gd")
const Model := preload("res://editor/ed_logic_model.gd")
const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Blocks := preload("res://games/custom/logic/cg_blocks.gd")
const Debug := preload("res://editor/ed_debug.gd")
var count := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	count += 1
	if not ok:
		errors += 1
		push_error(text)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		quit(1)
		return
	var doc := Document.new()
	check(doc.create(), "Создан документ")
	var model := Model.new(doc)
	check(model.add_event("неизвестное") == -1 and doc.undo_stack.is_empty(), "Неизвестное событие не меняет документ")
	var score := model.add_variable("Очки", "number", "shared")
	var flag := model.add_variable("Флаг", "bool", "player")
	var text := model.add_variable("Текст", "text", "team")
	check(not score.is_empty() and not flag.is_empty() and not text.is_empty(), "Созданы три типа переменных в трёх областях")
	check(model.add_variable("", "number", "shared").is_empty() and model.add_variable("X", "неизвестное", "shared").is_empty(), "Неверная переменная не создаётся")
	var role := model.add_role("Судья")
	check(not role.is_empty() and doc.data.rules.roles.back().name == "Судья", "Добавлена роль")
	var phase := model.add_phase("Проверка")
	check(doc.data.rules.phases.has(phase) and doc.data.meta.phase_titles[phase] == "Проверка", "Фаза хранит стабильный ID отдельно от названия")
	check(model.rename_phase(phase, "Финал") and doc.data.meta.phase_titles[phase] == "Финал", "Переименование фазы сохраняет ID ссылок")
	check(model.move_phase(phase, -1) and doc.data.rules.phases[0] == phase and doc.undo(), "Перестановка фаз отменяется")
	var index := model.add_event("button")
	var root: Array = ["rules", "chains", index, "blocks"]
	check(doc.data.layout.custom and doc.data.rules.chains[index].event.id == "action_1", "Событие создаёт связанную кнопку интерфейса")
	var condition := model.add_block("if", root)
	var set_path := model.add_block("set", condition + ["then"])
	doc.set_value(set_path + ["var"], score)
	doc.set_value(set_path + ["value"], 7)
	var repeat := model.add_block("repeat", root)
	doc.set_value(repeat + ["count"], 3)
	var change := model.add_block("change", repeat + ["body"])
	doc.set_value(change + ["var"], score)
	doc.set_value(change + ["value"], 2)
	var win := model.add_block("win", root)
	check(doc.issues().errors.is_empty(), "Собранные вложенные цепочки корректны")
	var before: Dictionary = doc.data.duplicate(true)
	var moved := model.move(win, -1)
	check(moved.back() == 1 and doc.undo() and doc.data == before, "Перестановка блока отменяется без потери ветвей")
	check(model.remove(repeat) and doc.undo() and doc.data == before, "Удаление цикла отменяется вместе с телом")
	check(model.move(root + [999], -1) == root + [999], "Неверный индекс не обращается за границы")
	check(model.add_block("нет", root).is_empty() and model.add_block("log", ["meta"]).is_empty(), "Блок добавляется только в массив допустимой цепочки")
	var rules := Rules.new()
	check(rules.load_definition(doc.data).is_empty(), "Описание из редактора загружено ядром")
	check(rules.new_game([{"name": "А", "team": 0}, {"name": "Б", "team": 1}]).is_empty(), "Собранная игра запущена")
	var legal: Array = rules.legal_actions(0)
	var debug := Debug.new()
	debug.capture(rules)
	debug.capture(rules)
	check(debug.history.size() == 1 and not debug.back(rules), "Отладка не дублирует одно состояние и не отступает за начало")
	var initial_random: int = rules.rng.state
	check(not legal.is_empty(), "Созданная кнопка доступна действующему игроку")
	if not legal.is_empty():
		var action: Dictionary = legal[0].duplicate(true)
		action.revision = rules.state.revision
		check(rules.act(0, str(action.kind), action), "Цепочка исполнена по кнопке")
		check(rules.state.vars.shared[score] == 13 and rules.phase == "game_over" and rules.state.winners == [0], "Ветвь и три повтора дали 13 очков и победу игроку")
		debug.capture(rules)
		check(debug.describe(rules).contains("ПРОЙДЕННЫЕ БЛОКИ") and debug.describe(rules).contains("Очки") == false, "Отладка показывает трассу и значения по стабильным ID")
		check(debug.back(rules) and rules.phase != "game_over" and rules.state.vars.shared[score] == 0 and rules.rng.state == initial_random, "Шаг назад восстанавливает значения, фазу и RNG")
		check(not rules.act(0, str(action.kind), action), "Старое действие после шага назад отвергается")
		check(debug.restart(rules, true) and rules.rng.state == initial_random and rules.state.vars.shared[score] == 0, "Тот же расклад запускает партию с исходным seed")
		check(debug.history.size() == 1 and not debug.back(rules), "Перезапуск создаёт новую историю отладки")
		var old_seed: int = rules.rng.seed
		check(debug.restart(rules, false) and rules.rng.seed != old_seed, "Заново выбирает новый seed")
	# Для каждого пункта палитры обязательные гнёзда существуют ещё до редактирования.
	for op: String in Blocks.OPS:
		var block := model.default_block(op)
		for key: String in Blocks.OPS[op]:
			check(block.has(key), "У блока %s есть гнездо %s" % [op, key])
	check(doc.save(), "Игра из конструктора сохранена")
	print("EDITOR_LOGIC: %d проверок, ошибок %d" % [count, errors])
	quit(1 if errors else 0)
