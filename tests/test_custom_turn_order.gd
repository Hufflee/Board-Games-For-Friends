extends SceneTree
## Порядок ходов: ведущий, барьер готовности, ожидания, откат ошибок и восстановление снимка.
const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _definition(mode: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/higher_lower.json"))
	data.rules["turn_mode"] = mode
	data.rules.phases = ["setup", "play"]
	data.rules.vars = [{"id": "score", "type": "number", "scope": "shared", "init": 0}]
	data.rules.chains = [
		{"event": {"type": "button", "id": "inc"}, "blocks": [{"op": "change", "var": "score", "value": 1}]},
		{"event": {"type": "button", "id": "wait"}, "blocks": [{"op": "ask_number", "player": 0, "min": 1, "max": 5}]},
		{"event": {"type": "phase_exit", "phase": "setup"}, "blocks": [{"op": "log", "text": "exit-setup"}]},
		{"event": {"type": "phase_enter", "phase": "play"}, "blocks": [{"op": "log", "text": "enter-play"}]},
	]
	if mode != "simultaneous":
		data.rules.chains.append({"event": {"type": "button", "id": "pass"}, "blocks": [{"op": "next"}]})
	return data

func _game(mode: String) -> RefCounted:
	var g := Rules.new()
	check(g.load_definition(_definition(mode)).is_empty(), "Определение режима принято: " + mode)
	check(g.new_game([{"name": "А"}, {"name": "Б"}, {"name": "В"}], {"seed": 75, "leader": 2}).is_empty(), "Режим запущен: " + mode)
	return g

func _act(g: RefCounted, seat: int, kind: String, fields: Dictionary = {}) -> bool:
	var action := fields.duplicate(true)
	action["revision"] = int(g.state.revision)
	return g.act(seat, kind, action)

func _run() -> void:
	var circle = _game("circle")
	check(circle.state.current == 0, "Прежний режим начинает с первого места")
	var leader = _game("leader_start")
	check(leader.state.current == 2, "Круг начинается с ведущего")
	check(_act(leader, 2, "button", {"id": "pass"}) and leader.state.current == 0 and leader.state.round == 1, "Переход черезнулевое место ещё не завершает круг ведущего")
	check(_act(leader, 0, "button", {"id": "pass"}) and leader.state.current == 1 and leader.state.round == 1, "Круг продолжается")
	check(_act(leader, 1, "button", {"id": "pass"}) and leader.state.current == 2 and leader.state.round == 2, "Возврат к ведущему начинает следующий круг")
	var only = _game("leader_only")
	check(only.state.current == 2 and only.legal_actions(0).is_empty(), "Только ведущий начинает действия")
	check(not _act(only, 0, "button", {"id": "inc"}), "Чужое действие ведущего отклонено хостом")
	check(_act(only, 2, "button", {"id": "wait"}), "Ведущий может запросить ответ другого игрока")
	check(only.legal_actions(0).any(func(action): return action.kind == "answer"), "Ожидающий игрок может ответить в режиме ведущего")
	check(_act(only, 0, "answer", {"value": 3}), "Ответ другого места принят")
	check(_act(only, 2, "button", {"id": "pass"}) and only.state.current == 2, "Передача хода сохраняет режим ведущего")
	var sim = _game("simultaneous")
	check(sim.legal_actions(0).any(func(action): return action.kind == "ready"), "Любое живое место может подтвердить готовность")
	var stale: int = sim.state.revision
	check(_act(sim, 0, "ready"), "Первое место готово")
	check(sim.phase == "setup" and sim.get_view(-1).ready_seats == [0], "Готовность видна всем, фаза ждёт остальных")
	check(sim.legal_actions(0).size() == 1 and sim.legal_actions(0)[0].kind == "unready", "Готовый игрок может только изменить решение")
	check(not sim.act(1, "ready", {"revision": stale}), "Запоздавший пакет готовности не применяется")
	check(not _act(sim, 0, "button", {"id": "inc"}), "После готовности нельзя менять ход скрытым действием")
	check(_act(sim, 0, "unready") and _act(sim, 0, "button", {"id": "inc"}), "Отмена готовности возвращает действия")
	for seat in 3:
		check(_act(sim, seat, "ready"), "Готовность места%d" % seat)
	check(sim.phase == "play" and sim.state.ready_seats.is_empty() and sim.state.turn_no == 2, "Три готовности меняют фазу и очищают барьер")
	check(sim.state.log.slice(-2) == ["exit-setup", "enter-play"], "Выход из фазы выполняется перед входом")
	for seat in 3:
		check(_act(sim, seat, "ready"), "Готовность следующей фазы%d" % seat)
	check(sim.phase == "setup" and sim.state.round == 2, "Последняя фаза возвращается к первой нового раунда")
	check(_act(sim, 1, "ready"), "Частичная готовность перед сохранением")
	var saved: Dictionary = sim.save_state()
	var restored := Rules.new()
	check(restored.restore(saved).is_empty() and restored.state.ready_seats == [1], "Снимок сохраняет готовность")
	var bad := saved.duplicate(true)
	bad.state.ready_seats = [1, 1]
	check(not restored.restore(bad).is_empty() and restored.state.ready_seats == [1], "Дубли готовности отклоняются без изменения партии")
	bad = _definition("simultaneous")
	bad.rules.chains[0].blocks = [{"op": "if", "condition": true, "then": [{"op": "next"}]}]
	check(not Definition.validate(bad).errors.is_empty(), "Передача хода запрещена и во вложенном блоке одновременного режима")
	bad.rules.turn_mode = "несуществующий"
	check(not Definition.validate(bad).errors.is_empty(), "Неизвестный режим отклонён")
	var waiting = _game("simultaneous")
	check(_act(waiting, 0, "ready") and _act(waiting, 1, "button", {"id": "wait"}), "Ожидание может запросить ответ уже готового места")
	check(waiting.legal_actions(0).any(func(action): return action.kind == "answer"), "Готовность не запрещает обязательный ответ")
	check(_act(waiting, 0, "answer", {"value": 2}) and waiting.state.ready_seats == [0], "Ответ не сбрасывает частичную готовность")
	var eliminated = _game("simultaneous")
	eliminated.players[2].eliminated = true
	check(_act(eliminated, 0, "ready") and _act(eliminated, 1, "ready") and eliminated.phase == "play", "Выбывший игрок не удерживает общую фазу")
	var rollback = _game("simultaneous")
	rollback.definition.rules.chains.append({"event": {"type": "phase_enter", "phase": "play"}, "blocks": [{"op": "set", "var": "score", "value": {"op": "div", "a": 1, "b": 0}}]})
	check(_act(rollback, 0, "ready") and _act(rollback, 1, "ready"), "Подготовлена готовность перед ошибкой перехода")
	var before := JSON.stringify(rollback.save_state())
	check(not _act(rollback, 2, "ready"), "Ошибка цепочки входа отклоняет последнюю готовность")
	check(JSON.stringify(rollback.save_state()) == before, "Ошибка возвращает фазу, готовность и RNG без частичного перехода")
	only.definition.rules.chains.append({"event": {"type": "button", "id": "leader0"}, "blocks": [{"op": "leader", "player": 0}]})
	check(_act(only, 2, "button", {"id": "leader0"}) and only.state.current == 0 and only.legal_actions(2).is_empty(), "Назначение ведущего передаёт управление новому месту")
	only.definition.rules.chains.append({"event": {"type": "button", "id": "eliminate0"}, "blocks": [{"op": "eliminate", "player": 0}]})
	check(_act(only, 0, "button", {"id": "eliminate0"}) and only.state.leader == 1 and only.state.current == 1, "Выбывшего ведущего заменяет следующее живое место")
	print("CUSTOM TURN ORDER: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
