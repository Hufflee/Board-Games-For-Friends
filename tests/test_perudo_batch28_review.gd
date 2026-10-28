extends "res://tests/test_perudo_batch28_ui.gd"
## Независимые границы low; helpers доставляют настоящие InputEvents. Dummy/свой APPDATA.

func four() -> PerudoRules:
	var r := PerudoRules.new()
	r.new_game([{"name":"А"},{"name":"Б"},{"name":"В"},{"name":"Г"}], 5, true, 2802)
	r.begin()
	for seat in 4:
		r.shake(seat)
	r.turn = 0
	return r

func run() -> void:
	await frames()
	var r := four()
	check(r.place_bid(0, 5, 4) and r.place_bid(1, 3, 1), "Штатный маршрут5 четвёрок→3 единицы")
	var before := r.get_view(2).duplicate(true)
	check(not r.place_bid(2, 6, 6) and r.get_view(2) == before, "Ровно2q отвергается без мутации состояния")
	check(r.place_bid(2, 7, 6), "Ровно2q+1 принимается")
	r = four()
	r.place_bid(0, r.total_dice(), 6)
	r.place_bid(1, 10, 1)
	check(r.min_quantity(2) == -1 and not r.can_bid(20, 2), "Выход из единиц сверх всего числа костей невозможен")
	before = r.get_view(1).duplicate(true)
	for seat in [-100, -1, 1, 4, 100]:
		check(not r.calza(seat) and r.get_view(1) == before, "Неверный/авторский calza не меняет состояние: %d" % seat)
	# Палифико возникает через настоящее вскрытие, не ручной переключатель maputo.
	r = four()
	r.counts.assign([5, 2, 4, 4])
	r.dice = [[2,2,2,2,2], [2,2], [2,2,2,2], [2,2,2,2]]
	r.place_bid(0, 1, 2)
	check(r.challenge(1) and r.counts[1] == 1 and r.pal_next == 1, "Потеря до1 кости запланировала Палифико")
	var old_round := r.round_no
	r.advance()
	check(r.round_no == old_round + 1 and r.maputo and r.turn == 1, "Следующий Палифико начинает потерявший кость")
	check(r.bid.is_empty() and r.bids.is_empty() and r.reveal.is_empty() and not r.can_calza(3), "Настоящий новый раунд очищает ставки/вскрытие/права calza")
	for seat in 4:
		r.shake(seat)
	check(not r.place_bid(1, 1, 1) and r.place_bid(1, 1, 3), "В Палифико первый1 запрещён, обычный3 разрешён")
	check(not r.can_bid(2, 1) and not r.can_bid(2, 4) and r.can_bid(2, 3), "Палифико удерживает первый обычный номинал")
	# Заданные грани явно fixture: все единицы, кроме одной тройки; проверяется отключение wild.
	r.dice = [[3,1,1,1,1], [1], [1,1,1,1], [1,1,1,1]]
	check(r.can_calza(3) and r.calza(3), "Живой3 может calza вне очереди2 в Палифико")
	check(r.reveal.count == 1 and not r.reveal.wild and r.counts[3] == 5, "Единицы не добавляются к тройке, кость получает именно заявитель")
	var histories := r.history.size()
	check(not r.calza(2) and r.history.size() == histories, "Поздний конкурентный calza не повторяет награду")
	r.advance()
	check(not r.maputo and r.bid.is_empty() and r.turn == 3, "Следующий обычный раунд не наследует Палифико и старую ставку")
	# UI: реальные таблица/кнопки, адресные подготовленные view как у автора; не сетевой транспорт.
	root.size = Vector2i(1280,720)
	net = root.get_node("Net")
	net.host_offline("perudo")
	net.set_bots(2)
	net.start_game()
	net.set_process(false)
	net.send_action("seat_begin")
	for seat in 3:
		net.perudo.shake(seat)
	net.perudo.turn = 0
	net._push_state()
	app = load("res://games/perudo/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(12)
	table = app.screen
	model = make()
	await apply_view()
	for face in range(2,7):
		table._face = face
		table._qty = 9
		model.round_no += 1
		await apply_view()
		check(table._qty == 1 and table._face == face, "Новый round_no сохраняет номинал%d и сбрасывает qty" % face)
		table._qty = 4
		await apply_view()
		check(table._qty == 4, "Повторный снимок не сбрасывает выбор номинала%d" % face)
	var other := model.get_view(0)
	other.game_id = "another-match-same-round"
	table._apply(other)
	await frames()
	check(table._qty == 1 and table._face == 6, "Новый game_id при том же round_no сбрасывает количество, сохраняя face6")
	model.turn = 1
	model.place_bid(1, 4, 4)
	model.turn = 0
	await apply_view()
	table._face = 4
	table._qty = 10
	table._update_panel()
	table._layout()
	await frames()
	await click(table.find_child("BidFace1", true, false))
	check(table._face == 1 and table._qty == 2, "Мышь: чётная ставка4 даёт минимум2 единицы, а не прежние10")
	model = make()
	model.counts[0] = 0
	model.dice[0] = []
	model.turn = 1
	model.place_bid(1, 1, 2)
	await apply_view(0)
	check(table.find_child("Calza", true, false) == null and not model.get_view(0).can_calza, "Выбывший не получает кнопку/серверное право calza")
	print("PERUDO LOW28: %d проверок, %d ошибок" % [checks, errors])
	net.leave()
	app.queue_free()
	await frames()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
