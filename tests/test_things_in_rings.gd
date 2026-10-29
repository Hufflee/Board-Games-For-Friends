extends SceneTree
## Чистые правила Things in Rings: обычная и кооперативная партии, права и приватность.

var checks := 0
var errors := 0
const Rules := preload("res://games/things_in_rings/logic/tr_rules.gd")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)


func make_game(count: int, coop: bool = false) -> Rules:
	var people := []
	for i: int in count:
		people.append({"name": "Игрок%d" % i})
	var game := Rules.new()
	check(game.new_game(people, range(240), {"Attribute": [300,301,302,303], "Word": [200,201,202,203], "Context": [400,401,402,403]}, {"coop": coop}, 29) == "", "Создана корректная партия")
	check(game.phase == "choose_rules" and game.hands[0].is_empty(), "Выбор до раздачи")
	check(not game.begin_clues(0), "Нельзя подтвердить без всех выборов")
	for category: String in game.rings:
		var candidates: Array = game.get_view(0).rule_choices[category]
		check(candidates.size() == 3 and candidates == game.get_view(0).rule_choices[category], "Три фиксированных кандидата")
		check(game.choose_rule(0, category, candidates[0]), "Правило из тройки выбрано")
	check(game.begin_clues(0), "Раздача после подтверждения")
	return game


func clues(game: Rules) -> void:
	var amount: int = game.players.size() if game.coop else 3
	for _i: int in amount:
		check(game.clue(game.knower, int(game.hands[game.knower][0]), 0), "Знающий положил начальную подсказку")


func _init() -> void:
	var standard := make_game(4)
	check(not standard.clue(1, int(standard.hands[1][0]), 0), "Искатель не кладёт начальную подсказку")
	check(standard.get_view(1).secret_rules.is_empty() and standard.get_view(-1).hand.is_empty(), "Правила и руки приватны")
	check(standard.get_view(0).secret_rules.size() == 2, "Знающий видит оба правила")
	clues(standard)
	check(standard.discarded.size() == 2 and standard.hands[0].is_empty(), "Остальные два предмета знающего сброшены")
	check(standard.actor() == 1, "Первый искатель следует за знающим по кругу")
	var original: int = standard.hands[1].size()
	check(not standard.place(2, int(standard.hands[2][0]), 0), "Чужой ход запрещён")
	check(not standard.place(1, int(standard.hands[1][0]), 4), "Несуществующая область запрещена")
	check(standard.place(1, int(standard.hands[1][0]), 3), "Искатель выбрал пересечение двух колец")
	check(not standard.place(1, int(standard.hands[1][0]), 0), "До проверки нельзя сыграть второй предмет")
	check(not standard.judge(1, 3), "Искатель не проверяет сам себя")
	check(standard.judge(0, 0), "Знающий исправил размещение")
	check(standard.current == 2 and standard.hands[1].size() == original and standard.board.back().mask == 0, "Ошибка даёт новый предмет и заканчивает ход, карта остаётся в верной области")
	check(not standard.judge(0, 0), "Повторная проверка не дублирует предмет")
	for i: int in 5:
		check(standard.place(2, int(standard.hands[2][0]), 1), "Правильный предмет играется из руки")
		check(standard.judge(0, 1), "Правильное размещение принято")
		if i < 4:
			check(standard.current == 2 and standard.phase == "place", "После успеха искатель продолжает тот же ход")
	check(standard.phase == "postgame" and standard.winners == [2], "Последний правильный предмет открывает обсуждение результата")
	check(standard.get_view(1).secret_rules.is_empty(), "Перед финальными догадками правила ещё скрыты")
	check(not standard.flip_condition(1, 0) and standard.flip_condition(0, 0) and standard.flip_condition(0, 1), "Поочерёдное раскрытие правил принадлежит знающему")
	check(standard.get_view(-1).secret_rules.size() == 2, "После раскрытия зритель видит правила")
	var cooperative := make_game(2)
	check(cooperative.coop and cooperative.hands[0].size() == 10, "Вдвоём автоматически кооператив, у знающего10предметов")
	clues(cooperative)
	for _i: int in 8:
		var card: int = cooperative.hands[1][0]
		check(cooperative.place(1, card, 0) and cooperative.judge(0, 1), "Ошибка заканчивает раунд единственного искателя")
		check(cooperative.phase == "knower_clue", "После раунда нужна одна новая подсказка")
		check(cooperative.clue(0, int(cooperative.hands[0][0]), 2), "Знающий использует следующий ограниченный предмет")
	check(cooperative.place(1, int(cooperative.hands[1][0]), 0) and cooperative.judge(0, 1), "Следующий раунд завершён ошибкой")
	check(cooperative.phase == "postgame" and cooperative.winners.is_empty() and cooperative.reason == "no_clue", "Нет подсказки — общий проигрыш с обсуждением")
	var win := make_game(3, true)
	clues(win)
	for seat: int in [1, 2]:
		for _i: int in 5:
			check(win.place(seat, int(win.hands[seat][0]), 0) and win.judge(0, 0), "Кооперативное правильное размещение")
	check(win.phase == "postgame" and win.winners == [0, 1, 2], "Пустые руки всех искателей дают общую победу до новой подсказки")
	var invalid := Rules.new()
	check(invalid.new_game([{}, {}, {}, {}, {}], range(240), {"Attribute": [300]}, {"rings": ["Attribute"], "coop": true}) != "", "В кооперативе не больше четырёх игроков")
	check(invalid.new_game([{}, {}], [1, 1], {"Attribute": [300]}, {"rings": ["Attribute"]}) != "", "ПовторныеID не принимаются")
	var manual := Rules.new()
	check(manual.new_game([{}, {}, {}], range(240), {"Word": [200, 201, 202]}, {"rings": ["Word"], "knower": 2}, 29) == "", "Подготовлен обязательный выбор знающим")
	check(manual.phase == "choose_rules" and manual.actor() == 2, "Выбор правил предшествует подсказкам")
	check(manual.get_view(0).rule_choices.is_empty() and manual.get_view(-1).secret_rules.is_empty(), "Выборы правил не передаются другим и зрителю")
	check(not manual.choose_rule(0, "Word", 201) and not manual.begin_clues(0), "Искатель не выбирает и не подтверждает правила")
	check(not manual.choose_rule(2, "Context", 201) and not manual.choose_rule(2, "Word", 999), "Нельзя выбрать правило из чужой категории или вне колоды")
	check(manual.choose_rule(2, "Word", 201) and manual.begin_clues(2), "Знающий выбрал и подтвердил правило")
	check(not manual.choose_rule(2, "Word", 200), "После начала подсказок правило неизменно")
	print("THINGS IN RINGS RULES: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
