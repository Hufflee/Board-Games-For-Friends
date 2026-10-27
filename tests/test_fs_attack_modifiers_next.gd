## Карты 34/36: ожидания с полных локальных карт и официальных правил, не из реализации.
## Подготовленные серверные состояния seed 26; значения ожидающих бросков заданы явно.
## --headless --audio-driver Dummy --script res://tests/test_fs_attack_modifiers_next.gd.
extends "res://tests/test_fs_mixed_next.gd"

var observations: Array = []

func arena(ids: Array, owner: int = 0, current: int = 0, dc: int = 4) -> FSRules:
	var g := clean()
	g.current = current
	g.hp = [100, 100]
	g.max_hp = [100, 100]
	g.attack = [1, 1]
	g.dead = [false, false]
	g._turn_attack_rolls.clear()
	g.temporary_attack.clear()
	g.battle = 0
	g.battle_player = -1
	# Сгусток без специального лечения Чаба на единице; HP/DC здесь тестовые, не печатные.
	g.monsters = [{"id": 450, "hp": 100, "dc": dc, "at": 1}]
	g.phase = "battle_roll"
	g._after_stack = "battle_roll"
	for id: int in ids:
		g._gain_item(owner, id)
	return g

## Настоящий action создаёт бросок; только его исходное значение заменено тестовой гранью.
func pending(g: FSRules, raw: int) -> bool:
	var accepted: bool = g.action(g.current, "roll", {})
	check(accepted, "Подготовка: action roll принят")
	if not accepted:
		return false
	if g.stack.is_empty() or g.stack.back().kind != "roll":
		check(false, "Подготовка: ожидающий бросок находится на вершине стека")
		return false
	g.stack.back().value = raw
	return true

func attack_result(g: FSRules, raw: int) -> Dictionary:
	var monster_before: int = g.monsters[0].hp
	var player_before: int = g.hp[g.current]
	if not pending(g, raw):
		return {"ошибка_подготовки": true}
	g._finish_responses()
	return {"итог": g.last_roll, "урон_монстру": monster_before - int(g.monsters[0].hp),
		"урон_игроку": player_before - int(g.hp[g.current])}

func expect_attack(g: FSRules, raw: int, value: int, hit: bool, label: String) -> void:
	var expected := {"итог": value, "урон_монстру": 1 if hit else 0, "урон_игроку": 0 if hit else 1}
	var actual := attack_result(g, raw)
	observations.append({"сценарий": label, "исходная_грань": raw, "ожидание": expected,
		"факт": actual, "совпало": expected == actual})
	print("МОДИФИКАТОРЫ: ", label, " | ожидание=", expected, " | факт=", actual)
	check(actual == expected, label)

func number_one() -> void:
	for current in 2:
		for face in range(1, 7):
			var own: bool = current == 0
			var hit: bool = face >= (3 if own else 4) and (not own or face not in [1, 6])
			expect_attack(arena([34], 0, current), face, face, hit,
				"34: владелец0, ход%d, грань%d" % [current, face])
	for face in range(1, 7):
		var g := arena([34], 0, 0, 1)
		expect_attack(g, face, face, face not in [1, 6], "34: базовая защита1, грань%d" % face)
		check(int(g.monsters[0].dc) == 1, "34: исходная защита1 не повреждается пересчётом")
	var g := arena([34])
	g._remove_item(0, 0)
	expect_attack(g, 3, 3, false, "34: уход источника отменяет снижение защиты")
	g = arena([34])
	g.items[1].append(g._remove_item(0, 0))
	expect_attack(g, 6, 6, true, "34: старый владелец после передачи больше не промахивается на6")
	g = arena([34], 0, 1)
	g.items[1].append(g._remove_item(0, 0))
	expect_attack(g, 3, 3, true, "34: снижение защиты в ход нового владельца")
	g = arena([34], 0, 1)
	g.items[1].append(g._remove_item(0, 0))
	expect_attack(g, 6, 6, false, "34: запрет6 относится к новому владельцу")

func seraphim() -> void:
	# Каждый порядковый номер проверяется в отдельной партии с собственной предысторией.
	# Отсутствие модификатора в ранних бросках не меняет число совершённых атак.
	for ordinal in range(1, 7):
		var g := arena([36])
		for previous in ordinal - 1:
			attack_result(g, 2)
		var value := 4 if ordinal in [1, 3, 5] else 3
		expect_attack(g, 3, value, ordinal in [1, 3, 5], "36: свой бросок%d" % ordinal)
	for face in range(1, 7):
		var value := mini(6, face + 1)
		expect_attack(arena([36]), face, value, value >= 4, "36: первый бросок, грань%d" % face)
		expect_attack(arena([36], 0, 1), face, face, face >= 4, "36: чужой бросок, грань%d" % face)
	var g := arena([36])
	for seat in 2:
		g.phase = "effect"
		g.resolving = {"kind": "item", "card": 13, "owner": seat}
		check(g.action(seat, "effect_roll", {}), "Подготовка: небоевой effect_roll игрока%d" % seat)
		g.stack.back().value = 3
		g._finish_responses()
		check(g.last_roll == 3, "36: небоевой бросок не получает бонус атаки")
	g.resolving = {}
	g.phase = "battle_roll"
	expect_attack(g, 3, 4, true, "36: после двух небоевых бросков атака всё ещё первая")
	g = arena([36])
	for i in 2:
		attack_result(g, 2)
	g._remove_item(0, 0)
	expect_attack(g, 3, 3, false, "36: уход перед третьим броском снимает модификатор")
	g = arena([36])
	for i in 2:
		attack_result(g, 2)
	g.items[1].append(g._remove_item(0, 0))
	expect_attack(g, 3, 3, false, "36: передача лишает прежнего владельца бонуса третьего")
	g.current = 1
	expect_attack(g, 3, 4, true, "36: новый владелец получает бонус своего первого броска")
	g = arena([])
	for i in 2:
		attack_result(g, 2)
	g._gain_item(0, 36)
	expect_attack(g, 3, 4, true, "36: получение после двух атак учитывает историю игрока")
	g = arena([36])
	attack_result(g, 2)
	g.battle = -1
	g._end_turn()
	g._finish_responses()
	g._end_turn()
	g._finish_responses()
	check(g.current == 0, "Подготовка: наступил новый собственный ход")
	g.battle = 0
	g.phase = "battle_roll"
	expect_attack(g, 3, 4, true, "36: новый ход начинает счёт с первого броска")
	# Статический бонус проверяется при разрешении: источник убран после постановки броска.
	g = arena([36])
	if pending(g, 3):
		g._remove_item(0, 0)
		g._finish_responses()
		check(g.last_roll == 3 and int(g.monsters[0].hp) == 100,
			"36: источник ушёл до разрешения, статический +1 не сохраняется в стеке")

func combination() -> void:
	# Вывод из правил итогового результата: исходная1 становится2; исходная5 становится6 и промахивается.
	for face in range(1, 7):
		var value := mini(6, face + 1)
		var hit: bool = value >= 3 and value not in [1, 6]
		expect_attack(arena([34, 36]), face, value, hit, "34+36: первый бросок, грань%d" % face)
	# Защита2 снижена до1: модифицированная1→2 попадает, запрет не проверяет исходную грань.
	expect_attack(arena([34, 36], 0, 0, 2), 1, 2, true, "34+36: исходная1 при защите2 попадает как итоговая2")

func _initialize() -> void:
	number_one()
	seraphim()
	combination()
	var output := FileAccess.open("res://build/fs_passive_registry/low-next-modifiers-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"наблюдения": observations, "проверки": checks, "ошибки": errors}, "\t"))
	output.close()
	print("ATTACK MODIFIERS NEXT: ", observations.size(), " сценариев, ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
