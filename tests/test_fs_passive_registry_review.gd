## Независимая сверка event_ops с исходником до рефакторинга и реальные регрессии 6/18.
## Запуск только после передачи medium: --headless --audio-driver Dummy --script res://tests/test_fs_passive_registry_review.gd.
extends "res://tests/test_fs_mixed_next.gd"

const GOLD := "res://backups/fs_passive_registry_2026-10-27/fs_passives.gd"
# Все карты старого event_ops, включая сложные ветки и контроль без пассива.
const CARD_IDS := [6, 18, 55, 85, 165, 231, 237, 830, 47, 184, 166, 190, 654, 838, 857, 42,
	45, 90, 56, 76, 161, 240, 250, 58, 180, 177, 223, 677, 124, 10, 137, 16]
const EVENTS := ["turn_start", "turn_end", "roll", "attack_roll", "damage", "monster_death",
	"death", "activate", "after_death", "coins", "чужое_событие"]
var reference: GDScript
var game_fields: Array[StringName] = []
var cases := 0
var positive_cards := {}

func load_reference() -> bool:
	var source := FileAccess.get_file_as_string(GOLD)
	check(not source.is_empty(), "Доступен золотой исходник до рефакторинга")
	if source.is_empty():
		return false
	var lines := source.split("\n")
	var removed := 0
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].strip_edges() == "class_name FSPassives":
			lines.remove_at(i)
			removed += 1
	check(removed == 1, "Удалена только единственная декларация глобального имени")
	if removed != 1:
		return false
	reference = GDScript.new()
	reference.source_code = "\n".join(lines)
	var status: Error = reference.reload()
	check(status == OK, "Анонимный золотой скрипт скомпилирован: %s" % status)
	return status == OK

## Снимаем все поля скрипта, а не только известные обработчику ресурсы.
func snapshot(g: FSRules) -> Dictionary:
	var result := {}
	for field: StringName in game_fields:
		var value: Variant = g.get(field)
		if value is RandomNumberGenerator:
			result[field] = {"seed": value.seed, "state": value.state}
		elif value is Dictionary or value is Array:
			result[field] = value.duplicate(true)
		else:
			result[field] = value
	return result

func payloads(event: String) -> Array:
	var result: Array = []
	for seat in 2:
		var values: Array = [1]
		if event == "roll":
			values = [1, 2, 3, 4, 5, 6]
		elif event == "attack_roll":
			values = [1, 2, 3, 4]
		elif event in ["coins", "damage"]:
			values = [0, 2, 3, 4]
		for value: int in values:
			result.append({"seat": seat, "value": value, "count": value, "amount": value})
	return result

func compare_case(g: FSRules, owner: int, item: Dictionary, event: String, data: Dictionary) -> void:
	cases += 1
	var label := "карта=%d владелец=%d ход=%d событие=%s данные=%s счётчики=%d погашен=%s" % [
		item.id, owner, g.current, event, data, item.counters, item.tapped]
	var before := snapshot(g)
	var item_before := item.duplicate(true)
	var data_before := data.duplicate(true)
	var expected: Array = reference.call("event_ops", g, owner, item, event, data)
	check(snapshot(g) == before and item == item_before and data == data_before,
		"Золотой обработчик чист: " + label)
	var actual: Array = FSPassives.event_ops(g, owner, item, event, data)
	check(actual == expected, "Точные операции и порядок: %s ожидание=%s факт=%s" % [label, expected, actual])
	check(snapshot(g) == before and item == item_before and data == data_before,
		"Новый обработчик не меняет game/item/data: " + label)
	if not expected.is_empty():
		positive_cards[int(item.id)] = true
	# Два живых результата должны быть независимы друг от друга и от реестра.
	var second: Array = FSPassives.event_ops(g, owner, item, event, data)
	check(second == expected, "Повторный вызов детерминирован: " + label)
	for op: Dictionary in actual:
		op["amount"] = -999
		op["проверка_ссылок"] = {"массив": [1, 2]}
	actual.append({"op": "проверка_массива"})
	check(second == expected, "Мутация первого результата не меняет второй: " + label)
	var third: Array = FSPassives.event_ops(g, owner, item, event, data)
	check(third == expected, "Мутация результата не портит будущие вызовы: " + label)
	check(snapshot(g) == before and item == item_before and data == data_before,
		"Результат не связан с game/item/data: " + label)

func differential() -> void:
	var g := clean()
	for property: Dictionary in g.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			game_fields.append(StringName(property.name))
	check(not game_fields.is_empty(), "Снимок охватывает поля FSRules")
	for id: int in CARD_IDS:
		check(not FSData.card(id).is_empty(), "Реальная карта существует: %d" % id)
		for owner in 2:
			for current in 2:
				g.current = current
				# 0..6 покрывают пороги 45, равенство/неравенство 58 и оба состояния tapped.
				for variant in 7:
					g.coins = [0, 0] if variant == 0 else [2, 4]
					g.souls = [[0, 0], [0, 2], [3, 1]][variant % 3].duplicate()
					var hand: Array = []
					hand.resize([0, 1, 5, 7, 8, 9, 2][variant])
					hand.fill(1)
					g.hands = [hand.duplicate(), hand.duplicate()]
					var item: Dictionary = FSData.item_entry(id, false)
					item.counters = variant
					for tapped: bool in [false, true]:
						item.tapped = tapped
						g.items = [[], []]
						g.items[owner].append(item)
						for event: String in EVENTS:
							for data: Dictionary in payloads(event):
								compare_case(g, owner, item, event, data)
	for id: int in CARD_IDS:
		if id != 16:
			check(positive_cards.has(id), "Есть положительный случай, а не только пустые массивы: %d" % id)

## Независимые ожидания правил из mixed_next; золотой скрипт здесь не участвует.
func real_rules() -> void:
	miner([2], 0, 20, false)
	miner([3], 0, 20, true)
	miner([2, 1], 0, 20, false)
	miner([3], 1, 20, false)
	miner([3], 0, 2, false)
	miner([4], 0, 3, true)
	miner([3], 0, 0, false)
	var g := clean()
	g._gain_item(0, 6)
	var source: Dictionary = g._remove_item(0, 0)
	source.tapped = true
	g._gain_coins(0, 3)
	g._finish_responses()
	check(source.tapped, "6: удалённый источник не перезаряжается")
	g.items[1].append(source)
	g._gain_coins(0, 3)
	g._finish_responses()
	check(source.tapped, "6: прежний владелец не перезаряжает переданный источник")
	g._gain_coins(1, 3)
	g._finish_responses()
	check(not source.tapped, "6: новый владелец перезаряжает источник")
	g = clean()
	g._gain_item(0, 18)
	g.battle = 0
	g.monsters = [{"id": 462, "hp": 100, "dc": 3, "at": 1}]
	for i in 3:
		g._roll_passives(6, 1)
		g._roll_passives(6, 0)
		g._finish_responses()
	check(g.attack[0] == 1, "18: чужие и обычные броски не считаются атаками")
	for i in range(1, 5):
		var before: int = g.monsters[0].hp
		roll(g)
		check(g.attack[0] == (1 if i < 3 else 2), "18: атака после броска %d" % i)
		check(before - int(g.monsters[0].hp) == (1 if i <= 3 else 2), "18: урон броска %d" % i)
	g.battle = -1
	g._end_turn()
	g._finish_responses()
	check(g.attack[0] == 1, "18: бонус снимается в конце хода")
	g._end_turn()
	g._finish_responses()
	g.battle = 0
	g.monsters[0].hp = 100
	for i in range(1, 4):
		roll(g)
		check(g.attack[0] == (1 if i < 3 else 2), "18: новый ход, бросок %d" % i)

func _initialize() -> void:
	if load_reference():
		differential()
		real_rules()
	print("РЕВЬЮ РЕЕСТРА: ", cases, " сравнений, ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
