extends SceneTree
## Автотесты правил. Запуск:
## godot --headless --script res://tests/test_rules.gd

const C := preload("res://games/king_of_12/logic/cards.gd")

var failures := 0
var checks := 0


func _init() -> void:
	test_dice()
	test_die_geometry()
	test_roll_phase()
	test_unselect()
	test_pdf_example_duplicates_and_werewolf()
	test_knight()
	test_cheater()
	test_cheater_with_knight()
	test_numeric_cards()
	test_golem()
	test_lady_suppresses()
	test_lady_duplicate_steal()
	test_lady_duplicate_equal_values()
	test_merchants()
	test_troublemakers_and_sorcerer()
	test_oracle()
	test_collector()
	test_faun()
	test_round_end_by_points()
	test_round_winner_ties()
	test_game_over()
	test_tournament()
	test_tournament_bot_games()
	test_random_deck()
	test_bot_games()
	print("Проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


func make(faces: Array, n: int = -1) -> K12Rules:
	if n < 0:
		n = faces.size()
	var names := ["Лея", "Мия", "Том", "Боб"]
	var players := []
	for i in n:
		players.append({"name": names[i], "bot": false})
	var deck: Array[String] = []
	deck.append_array(C.BASE)
	deck.append_array(C.PROMO)
	var r := K12Rules.new()
	r.new_game(players, deck, 12345)
	for s in n:
		r.roll_die(s)
	r.faces.assign(faces)
	return r


func play(r: K12Rules, cards: Array) -> void:
	for s in cards.size():
		check(r.select_card(s, cards[s]), "select_card %s" % cards[s])


func test_dice() -> void:
	for f in range(1, 13):
		var nb := K12Dice.neighbors(f)
		check(nb.size() == 5, "у грани %d пять соседей" % f)
		check(not nb.has(f) and not nb.has(K12Dice.opposite(f)), "грань %d не соседствует с собой и противоположной" % f)
		for g in nb:
			check(K12Dice.neighbors(g).has(f), "соседство %d-%d симметрично" % [f, g])
		var opp_nb := K12Dice.neighbors(K12Dice.opposite(f))
		var mapped := nb.map(func(x): return 13 - x)
		mapped.sort()
		check(opp_nb == mapped, "соседи противоположной грани %d противоположны соседям" % f)


func test_die_geometry() -> void:
	var f := K12DieGeometry.faces()
	check(f.size() == 12, "у 3D-кубика 12 граней")
	for a in range(1, 13):
		check(f[a]["verts"].size() == 5, "грань %d — пятиугольник" % a)
		var geo_nb := []
		for b in range(1, 13):
			var d: float = f[a]["normal"].dot(f[b]["normal"])
			if absf(d - 1.0 / sqrt(5.0)) < 0.01:
				geo_nb.append(b)
			if b == 13 - a:
				check(d < -0.99, "3D: грань %d противоположна %d" % [a, b])
		geo_nb.sort()
		check(geo_nb == K12Dice.neighbors(a), "3D-соседи грани %d = %s, в правилах %s" % [a, geo_nb, K12Dice.neighbors(a)])
		var q := K12DieGeometry.orientation(a)
		check((q * f[a]["normal"]).distance_to(Vector3.BACK) < 0.001, "поворот на грань %d смотрит на камеру" % a)
		check((q * f[a]["up"]).distance_to(Vector3.UP) < 0.001, "число на грани %d стоит ровно" % a)


func test_roll_phase() -> void:
	var r := K12Rules.new()
	var deck: Array[String] = []
	deck.append_array(C.FIRST_GAME)
	r.new_game([{"name": "А"}, {"name": "Б"}], deck, 5)
	check(r.phase == "roll", "раунд начинается с броска")
	check(not r.select_card(0, C.KNIGHT), "до броска карту не выбрать")
	check(r.roll_die(0, 100, 50), "первый игрок бросил")
	check(not r.roll_die(0), "второй раз бросить нельзя")
	check(r.phase == "roll", "ждём второго игрока")
	check(r.throws[0]["vx"] == 100.0 and r.throws[0]["id"] > 0, "данные броска сохранены")
	check(r.roll_die(1), "второй игрок бросил")
	check(r.phase == "select", "после бросков — выбор карт")
	check(r.faces[0] >= 1 and r.faces[0] <= 12 and r.faces[1] >= 1 and r.faces[1] <= 12, "грани в пределах 1..12")


func test_unselect() -> void:
	var r := make([3, 5, 7])
	check(r.select_card(0, C.ROBOT), "выбор")
	check(r.unselect_card(0), "отмена выбора")
	check(r.selected[0] == "" and r.hands[0].has(C.ROBOT), "карта вернулась")
	check(not r.unselect_card(0), "нечего отменять")
	play(r, [C.ROBOT, C.ALCHEMIST, C.GOLEM])
	check(not r.unselect_card(0), "после вскрытия забрать нельзя")


func test_pdf_example_duplicates_and_werewolf() -> void:
	# Пример из правил: Лея 10, Мия 7, Том 3. Лея и Мия — Алхимик, Том — Оборотень.
	var r := make([10, 7, 3])
	play(r, [C.ALCHEMIST, C.ALCHEMIST, C.WEREWOLF])
	check(r.phase == "trick_result", "пример PDF: фаза trick_result")
	check(r.trick["card_cancelled"] == [true, true, false], "пример PDF: Алхимики отменены")
	check(r.faces[2] == 10, "пример PDF: Оборотень 3 → 10")
	check(r.trick["dice_cancelled"] == [true, false, true], "пример PDF: Лея и Том отменены")
	check(r.trick["winner"] == 1 and r.trick["second"] == -1, "пример PDF: Мия победила, второго места нет")
	check(r.tokens[1] == [2], "пример PDF: Мия получила 2 ПО")


func test_knight() -> void:
	var r := make([3, 7, 10])
	play(r, [C.KNIGHT, C.ROBOT, C.PARASITE])
	# Робот: 7+7=14, Паразит: 10-7=3 → равно Лее (3)
	check(r.values == [3, 14, 3], "Рыцарь: значения %s" % [r.values])
	check(r.trick["winner"] == 1, "Рыцарь: единственный оставшийся побеждает")
	var r2 := make([3, 7, 10])
	play(r2, [C.KNIGHT, C.GOLEM, C.SORCERER])
	r2.choose_face(2, K12Dice.neighbors(10)[0])
	var low := 0
	check(r2.trick["winner"] == low, "Рыцарь: побеждает наименьшее (3)")


func test_cheater() -> void:
	var r := make([3, 7, 10])
	play(r, [C.CHEATER, C.ROBOT, C.ALCHEMIST])
	# 3, 14, 20
	check(r.trick["winner"] == 2 and r.trick["second"] == 1, "Шулер: порядок мест")
	check(r.tokens[2] == [1] and r.tokens[1] == [2], "Шулер: 1 ПО победителю, 2 ПО второму")


func test_cheater_with_knight() -> void:
	var r := make([3, 7, 10, 5])
	play(r, [C.CHEATER, C.KNIGHT, C.ORACLE, C.LADY])
	# Леди одна — отменяет все эффекты, значения = грани
	check(r.values == [3, 7, 10, 5], "Леди отменила всё: %s" % [r.values])
	check(r.trick["winner"] == 2 and r.trick["second"] == 1, "без эффектов побеждает наибольшее")
	var r2 := make([3, 7, 10, 5])
	play(r2, [C.CHEATER, C.KNIGHT, C.ROBOT, C.ALCHEMIST])
	# 3, 7, 17, 10 → Рыцарь: 3 победа (1 ПО), 7 второе (2 ПО)
	check(r2.trick["winner"] == 0 and r2.trick["second"] == 1, "Шулер+Рыцарь: наименьшие")
	check(r2.tokens[0] == [1] and r2.tokens[1] == [2], "Шулер+Рыцарь: 1 и 2 ПО")


func test_numeric_cards() -> void:
	var r := make([4, 4, 4])
	play(r, [C.ALCHEMIST, C.ROBOT, C.PARASITE])
	check(r.values == [8, 11, -3], "Алхимик/Робот/Паразит: %s" % [r.values])
	check(r.faces == [4, 4, 4], "числовые карты не меняют грань")
	check(r.trick["winner"] == 1 and r.trick["second"] == 0, "наибольшее значение побеждает")


func test_golem() -> void:
	var r := make([5, 11])
	play(r, [C.GOLEM, C.ALCHEMIST])
	check(r.values == [12, 22], "Голем: 12")
	var r2 := make([12, 11])
	play(r2, [C.GOLEM, C.ROBOT])
	check(r2.values[0] == 1, "Голем на грани 12 → 1")
	var r3 := make([1, 11])
	play(r3, [C.GOLEM, C.TROUBLEMAKERS])
	check(r3.faces[0] == 12 and r3.values[0] == 1, "Голем: Смутьяны перевернули на 12 → 1")


func test_lady_suppresses() -> void:
	var r := make([5, 6, 7])
	play(r, [C.LADY, C.ROBOT, C.MERCHANTS])
	check(r.trick["suppressed"] == [false, true, true], "Леди подавляет остальные карты")
	check(r.values == [5, 6, 7] and r.faces == [5, 6, 7], "Леди: ни Робот, ни Торговцы не сработали")


func test_lady_duplicate_steal() -> void:
	# Мия и Том выложили Леди; у Мии значение меньше — она забирает лучший жетон Тома.
	var r := make([9, 2, 6])
	r.tokens[2] = [1, 2]
	play(r, [C.ROBOT, C.LADY, C.LADY])
	# Лея 16 (2 ПО), Том 6 (1 ПО), Мия 2
	check(r.tokens[2] == [1, 1], "Леди-дубль: у Тома забрали двойку, осталось %s" % [r.tokens[2]])
	check(r.tokens[1] == [2], "Леди-дубль: Мия получила 2 ПО")


func test_lady_duplicate_equal_values() -> void:
	var r := make([9, 6, 6])
	r.tokens[2] = [2]
	play(r, [C.ROBOT, C.LADY, C.LADY])
	check(r.tokens[1] == [] and r.tokens[2] == [2], "Леди-дубль при равных значениях не работает")


func test_merchants() -> void:
	var r := make([1, 2, 3, 4])
	play(r, [C.MERCHANTS, C.ROBOT, C.ALCHEMIST, C.GOLEM])
	check(r.faces == [4, 1, 2, 3], "Торговцы: кубики ушли влево (%s)" % [r.faces])
	check(r.values == [4, 8, 4, 12], "Торговцы, затем числовые эффекты: %s" % [r.values])
	check(r.trick["dice_cancelled"] == [true, false, true, false], "Торговцы: 4 и 4 отменены")


func test_troublemakers_and_sorcerer() -> void:
	var r := make([3, 5])
	play(r, [C.SORCERER, C.TROUBLEMAKERS])
	check(r.phase == "sorcerer", "Чародей ждёт выбора")
	check(r.pending["seat"] == 0, "выбирает Лея")
	check(r.pending["options"] == K12Dice.neighbors(10), "варианты — соседи перевёрнутой грани 10")
	check(not r.choose_face(1, r.pending["options"][0]), "чужой игрок не выбирает грань")
	check(not r.choose_face(0, 10), "нельзя выбрать несоседнюю грань")
	var f: int = r.pending["options"][-1]
	check(r.choose_face(0, f), "выбор грани принят")
	check(r.faces == [f, 8], "Смутьяны+Чародей: %s" % [r.faces])
	check(r.phase == "trick_result", "после выбора — итог розыгрыша")


func test_oracle() -> void:
	var r := make([5, 6])
	play(r, [C.ORACLE, C.ROBOT])
	check(r.phase == "oracle" and r.pending["seat"] == 0, "Оракул ждёт броска владельца")
	check(not r.roll_oracle(1), "чужой игрок не бросает за Оракула")
	check(r.roll_oracle(0, 100, -200), "владелец Оракула бросил")
	check(r.phase == "trick_result" and r.throws[0]["vx"] == 100.0, "после броска — итог розыгрыша")
	check(r.faces[0] >= 1 and r.faces[0] <= 12 and r.values[0] == r.faces[0], "Оракул: переброс")


func test_collector() -> void:
	var r := make([5, 5, 9])
	play(r, [C.COLLECTOR, C.ROBOT, C.ALCHEMIST])
	# 5, 12, 18 — никто не равен, Коллекционер не срабатывает
	check(r.trick["winner"] == 2 and r.trick["second"] == 1, "Коллекционер без отмены не действует")
	var r2 := make([5, 5, 9])
	play(r2, [C.COLLECTOR, C.KNIGHT, C.WEREWOLF])
	# 5, 5, 4 → Лея и Мия отменены; Рыцарь: победил бы Том; Коллекционер забирает победу
	check(r2.trick["winner"] == 0 and r2.trick["second"] == 2, "Коллекционер: победа, бывший победитель второй")
	check(r2.tokens[0] == [2] and r2.tokens[2] == [1], "Коллекционер: 2 и 1 ПО")


func test_faun() -> void:
	var r := make([7, 7, 12])
	play(r, [C.FAUN, C.GOLEM, C.ROBOT])
	# Фавн 7, Голем 12, Робот 19. Нет равенства.
	check(r.faces[0] == 7, "Фавн не срабатывает без отмены")
	var r2 := make([7, 7, 12])
	play(r2, [C.FAUN, C.KNIGHT, C.WEREWOLF])
	# 7, 7, 1: Фавн должен быть отменён → наибольшая грань, которой нет у других (у других 7 и 1) → 12
	check(r2.faces[0] == 12 and r2.values[0] == 12, "Фавн поворачивает на 12 (%s)" % [r2.faces])
	check(r2.trick["dice_cancelled"] == [false, false, false], "после Фавна никто не отменён")
	check(r2.trick["winner"] == 2 and r2.trick["second"] == 1, "Рыцарь: 1, затем 7")


func test_round_end_by_points() -> void:
	var r := make([3, 9])
	r.tokens[1] = [2, 2, 2]
	play(r, [C.ROBOT, C.ALCHEMIST])
	# 10 vs 18 → Мия +2 → 8 ПО
	r.advance()
	check(r.phase == "pick_under" and r.pending["seat"] == 1, "8 ПО завершают раунд, Мия выбирает карту")
	check(r.hands[1].size() == r.deck.size(), "карты вернулись в руку (%d из %d)" % [r.hands[1].size(), r.deck.size()])
	check(r.pick_under(1, C.ROBOT), "карта под кубик")
	r.advance()
	check(r.phase == "roll" and r.rolled == [false, false], "новый раунд — снова бросок")


func test_round_winner_ties() -> void:
	var r := make([1, 1, 1])
	r.tokens[0] = [1, 2]
	r.tokens[1] = [2, 2, 2]
	r.tokens[2] = [2, 2, 2]
	r.hands[0] = [C.ROBOT, C.KNIGHT]
	r.hands[1] = [C.LADY, C.KNIGHT]
	r.hands[2] = [C.LADY, C.KNIGHT]
	play(r, [C.ROBOT, C.LADY, C.LADY])
	# 8, 1, 1 → Лея +2 = 5; Мия и Том отменены; Лея — победитель, второго нет
	r.advance()
	check(r.round_info["cancelled"] == [false, true, true], "равные суммы ПО отменяются")
	check(r.round_info["winner"] == 0, "Лея выигрывает раунд")


func test_game_over() -> void:
	var r := make([3, 9])
	r.under[0] = [C.GOLEM]
	r.tokens[0] = [2, 2, 2]
	r.hands[0].erase(C.GOLEM)
	play(r, [C.ALCHEMIST, C.PARASITE])
	r.advance()
	check(r.phase == "pick_under", "Лея выбирает вторую карту")
	check(not r.pick_under(0, C.GOLEM), "нельзя положить карту, которой нет в руке")
	check(r.pick_under(0, C.ROBOT), "карта положена")
	check(r.phase == "game_over" and r.winner == 0, "две карты под кубиком — победа в игре")


func test_random_deck() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		var d := C.random_deck(rng)
		check(d.size() == 7 and d[0] == C.KNIGHT, "случайный набор: 7 карт с Рыцарем")
		check(d.filter(C.is_physical).size() >= 2, "случайный набор: ≥2 карты с символом")
		var uniq := {}
		for c in d:
			uniq[c] = true
		check(uniq.size() == 7, "случайный набор: без повторов")


func test_bot_games() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var finished := 0
	var games := 1500
	for g in games:
		var n := 2 + g % 3
		var players := []
		for i in n:
			players.append({"name": "Бот%d" % i, "bot": true})
		var deck: Array[String] = C.random_deck(rng)
		if g % 4 == 1:
			deck.append(C.COLLECTOR)
		elif g % 4 == 2:
			deck.append(C.FAUN)
		var r := K12Rules.new()
		r.new_game(players, deck, g + 1)
		var steps := 0
		while r.phase != "game_over" and steps < 5000:
			steps += 1
			if not K12Bot.act_all(r):
				r.advance()
			if r.phase == "select":
				for s in n:
					if r.hands[s].size() + r.under[s].size() + r.discards[s].size() != deck.size():
						check(false, "партия %d: потеряны карты" % g)
						steps = 99999
		if r.phase == "game_over":
			finished += 1
			check(r.under[r.winner].size() == 2, "победитель имеет 2 карты под кубиком")
	check(finished == games, "все партии ботов завершились (%d/%d)" % [finished, games])


func test_tournament() -> void:
	# Пример по мотивам PDF: 8 игроков, 4 группы по двое, в финале карты срабатывают снова.
	var names := ["Лея", "П1", "Том", "П3", "Боб", "П5", "Мия", "П7"]
	var players := []
	for nm in names:
		players.append({"name": nm})
	var deck: Array[String] = []
	deck.append_array(C.BASE)
	var r := K12Rules.new()
	r.new_game(players, deck, 777, true)
	check(r.tournament, "турнир включён для 8 игроков")
	check(r.groups.size() == 2 and r.groups[0].size() == 4, "8 игроков → группы 4/4")
	for s in 8:
		r.roll_die(s)
	r.groups = [[0, 1], [2, 3], [4, 5], [6, 7]]
	r.faces.assign([3, 1, 3, 5, 5, 1, 2, 6])
	play(r, [C.ROBOT, C.ROBOT, C.WEREWOLF, C.PARASITE, C.ALCHEMIST, C.ROBOT, C.ALCHEMIST, C.PARASITE])
	check(r.phase == "trick_result", "турнир: розыгрыш завершён")
	check(r.trick["finalists"] == [0, 2, 4, 6], "в финале победители групп: %s" % [r.trick["finalists"]])
	check(r.trick["card_cancelled"][0] and r.trick["card_cancelled"][1], "в группе 1 Роботы отменены")
	check(r.faces[2] == 3, "Оборотень Тома сработал дважды: 3 → 10 → 3")
	check(r.values[0] == 10, "в финале Робот Леи сработал: 3 + 7 = 10")
	check(r.trick["winner"] == 0 and r.trick["second"] == 4, "финал: Лея победила, Боб второй")
	var expect := [[2], [1], [], [1], [1], [1], [], [1]]
	for s in 8:
		check(r.tokens[s] == expect[s], "жетоны места %d: %s" % [s, r.tokens[s]])
	check(r.trick["chains"][2].contains("финал"), "цепочка значений Тома: %s" % r.trick["chains"][2])


func test_tournament_bot_games() -> void:
	var finished := 0
	var playoffs := 0
	var games := 300
	for g in games:
		var n := 5 + g % 4
		var players := []
		for i in n:
			players.append({"name": "Бот%d" % i, "bot": true})
		var deck: Array[String] = []
		deck.append_array(C.FIRST_GAME)
		var r := K12Rules.new()
		r.new_game(players, deck, g + 7, true)
		var steps := 0
		while r.phase != "game_over" and steps < 20000:
			steps += 1
			if r.playoff:
				playoffs += 1
			if not K12Bot.act_all(r):
				r.advance()
		if r.phase == "game_over":
			finished += 1
			check(r.under[r.winner].size() == 2, "турнир: у победителя 2 карты под кубиком")
	check(finished == games, "турнирные партии ботов завершились (%d/%d)" % [finished, games])
	print("переигровок встречено (шагов): %d" % playoffs)
