## Тесты правил «Большой бродилки»: godot --headless --path . --script res://tests/test_brodilka.gd
extends SceneTree

var fails := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("ОШИБКА: ", msg)


func _players(n: int) -> Array:
	var a := []
	for i in n:
		a.append({name = "Бот %d" % i, bot = true})
	return a


func _init() -> void:
	# данные
	check(BRData.GOODBAD.size() == 19, "19 карт Хорошо/Плохо")
	for i in BRData.GOODBAD.size():
		check(ResourceLoader.exists(BRData.gb_image(i)), "картинка gb_%d" % i)
	for i in BRData.TADAM.size():
		check(ResourceLoader.exists(BRData.tadam_image(i)), "картинка tadam_%d" % i)
	for i in BRData.SHOP.size():
		check(ResourceLoader.exists(BRData.shop_image(i)), "картинка Лавки %d" % i)
	check(BRData.TADAM.size() == 16, "16 карт Тадам")
	check(BRData.SHOP.size() == 50, "50 карт Лавки: 10 из мода + 40 новых")
	var ids := {}
	for c in BRData.SHOP:
		check(not ids.has(c.id), "id карты Лавки не повторяется: " + c.id)
		ids[c.id] = true
	check(BRBoard.cell(0).t == "start" and BRBoard.cell(BRBoard.finish()).t == "finish", "поле: старт и финиш")
	for t in ["tele_y", "tele_g", "tele_p", "tele_b"]:
		var n := 0
		for c in BRBoard.cells():
			if c.t == t:
				n += 1
		check(n == 2, "по два телепорта " + t)

	# старт
	var r := BRRules.new()
	r.new_game(_players(3), 7)
	check(r.coins == [10, 10, 10] and r.phase == "roll", "старт: 10 монет, фаза броска")
	check(r.last_player() == -1, "все на старте — последнего нет")

	# монеты не уходят в минус
	r.coins[0] = 3
	r._lose(0, 10)
	check(r.coins[0] == 0, "монеты не ниже нуля")

	# телепорт
	var tp := -1
	for i in BRBoard.size():
		if BRBoard.cell(i).t == "tele_y":
			tp = i
			break
	check(BRBoard.tele_pair(tp) != tp and BRBoard.cell(BRBoard.tele_pair(tp)).t == "tele_y", "телепорт в пару")

	# монеты-ловушки: сколько положить, потом каждая — на выбранную клетку
	var tr := BRRules.new()
	tr.new_game(_players(2), 11)
	var tc := -1
	for i in BRData.GOODBAD.size():
		if str(BRData.GOODBAD[i].good.get("fx", "")) == "coin_traps":
			tc = i
	check(tc >= 0, "есть карта с монетами-ловушками")
	tr.coins[0] = 10
	tr._gb_fx(0, tc, true)
	check(tr.prompt.get("kind", "") == "pay", "ловушки: сначала — сколько монет")
	tr.answer(0, 2)
	check(tr.coins[0] == 8, "ловушки: две монеты списаны")
	check(tr.prompt.get("kind", "") == "trap", "ловушки: выбор клетки")
	var cells: Array = tr.prompt.data.cells
	tr.answer(0, cells.find(20) + 1)
	check(tr.traps.has(20) and int(tr.traps[20]) == 0, "ловушка на выбранной клетке 20")
	check(tr.prompt.get("kind", "") == "trap" and not (tr.prompt.data.cells as Array).has(20), "вторая ловушка: клетка 20 уже занята")
	tr.answer(0, 0)
	check(tr.traps.size() == 2, "вторая — случайно перед соперником")

	# новые карты Лавки
	var nc := BRRules.new()
	nc.new_game(_players(3), 21)
	check(nc.deck_shop.size() == 10 * BRData.SHOP_COPIES + 40, "колода Лавки: старые по %d, новые по 1" % BRData.SHOP_COPIES)
	var give := func(seat: int, id: String) -> void:
		nc.shop[seat].append(BRData.shop_index(id))
	# пассивные
	give.call(0, "backpack")
	check(nc.shop_max(0) == 4 and nc.shop_max(1) == 3, "рюкзак: 4 карты Лавки")
	give.call(1, "coupon")
	check(nc.shop_price(1) == 3 and nc.shop_price(0) == 5, "купон: покупка за 3")
	nc.coins[2] = 10
	give.call(2, "charm")
	nc.pos[2] = -1
	for i in BRBoard.size():
		if BRBoard.cell(i).t == "nooo":
			nc.pos[2] = i
			break
	if nc.pos[2] >= 0:
		nc._cell_fx(2)
		check(nc.coins[2] == 7, "оберег: «Нееет!» −3")
	give.call(1, "anchor")
	nc.pos[1] = 30
	nc._push_back(1, 5)
	check(nc.pos[1] == 30, "якорь: назад не сдвинуть")
	nc.pos[0] = 20
	nc._push_back(0, 5)
	check(nc.pos[0] == 15, "без якоря — назад")
	# активные: цели и эффекты
	nc.pos = [10, 14, 3]
	nc.stuck = [false, false, false]
	check(Array(BRRules.card_targets(0, "swap", nc.pos, nc.stuck, nc.shop, nc.coins)) == [1], "подменная шляпа: игрок в 4 клетках впереди")
	check(Array(BRRules.card_targets(0, "lasso", nc.pos, nc.stuck, nc.shop, nc.coins)) == [2], "лассо: игрок в 7 клетках позади")
	check(Array(BRRules.card_targets(0, "sling", nc.pos, nc.stuck, nc.shop, nc.coins)) == [1], "рогатка: ближайший впереди")
	check(BRRules.card_usable(0, "solvent", nc.pos, nc.stuck, nc.shop, nc.coins) == false, "растворитель — только на жвачке")
	nc.stuck[0] = true
	check(BRRules.card_usable(0, "solvent", nc.pos, nc.stuck, nc.shop, nc.coins), "на жвачке растворитель можно")
	nc.stuck[0] = false
	# сыграть «Пони» в свободной фазе
	nc.turn = 0
	nc.phase = "free"
	nc.prompt = {}
	nc.used.clear()
	nc.coins[0] = 10
	nc.shop[0] = [BRData.shop_index("pony")]
	check(nc.use_card(0, 0), "пони сыгран")
	check(nc.pos[0] == 14 and nc.coins[0] == 7, "пони: +4 клетки за 3 монеты")
	nc.shop[0] = [BRData.shop_index("powder")]
	nc.used.clear()
	nc.phase = "free"
	nc.coins[0] = 10
	nc.pos = [14, 16, 3]
	nc.shop[1] = []
	check(nc.use_card(0, 0), "бочка пороха сыграна")
	check(nc.pos[1] == 12 and nc.pos[2] == 3, "порох: рядом — на 4 назад, далёкий не задет")
	nc.shop[0] = [BRData.shop_index("shield")]
	nc._draw_gb(0, false, true)
	check(nc.shop[0].is_empty(), "щит ломается о «Плохо»")

	# случайные партии ботов до конца
	var ended := 0
	for g in 200:
		var b := BRRules.new()
		b.new_game(_players(2 + g % 7), 1000 + g)
		var steps := 0
		while b.phase != "game_over" and steps < 20000:
			var acted := false
			for s in b.player_count():
				if BRBot.act(b, s):
					acted = true
					break
			if not acted:
				check(false, "партия %d зависла: фаза %s, prompt %s" % [g, b.phase, b.prompt])
				break
			steps += 1
			for s in b.player_count():
				if b.coins[s] < 0 or b.pos[s] < 0 or b.pos[s] > BRBoard.finish() or (b.shop[s].size() > b.shop_max(s) and b.prompt.get("kind", "") != "discard"):
					check(false, "партия %d: неверное состояние места %d" % [g, s])
		if b.phase == "game_over":
			ended += 1
			check(b.winner >= 0, "есть победитель")
	check(ended == 200, "все 200 партий доиграны (%d)" % ended)

	print("Проверок: %d, ошибок: %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
