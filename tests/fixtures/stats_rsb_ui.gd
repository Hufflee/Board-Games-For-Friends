extends Node
## Регрессия монет и круглости жетонов; настоящий стол в 1280×720, обе темы.
const StatsScreen = preload("res://hub/player_stats_screen.gd")
const Table = preload("res://games/ready_set_bet/ui/rsb_table.gd")
var errors := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://build/shots/" + name + ".png"
	check(get_tree().root.get_texture().get_image().save_png(path) == OK, "Снимок сохранён: " + name)

func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var prefs = get_tree().root.get_node("Prefs")
	var net = get_tree().root.get_node("Net")
	for game: Dictionary in HubGames.LIST:
		var initial := StatsScreen.coin_progress(str(game.id), {})
		check(initial.x == 1 and initial.y == 2, "Обычная монета: " + str(game.id))
	check(StatsScreen.coin_progress("gloomier", {"gloom": true}) == Vector2i(2, 2), "Общий секрет Gloomier")
	check(StatsScreen.coin_progress("tip_top_18", {"tip_top": true}) == Vector2i(1, 2), "Тип Топ 18 отдельно")
	check(StatsScreen.coin_progress("tip_top_18", {"tip_top_18": true}) == Vector2i(2, 2), "Секрет Тип Топ 18")
	check(StatsScreen.coin_progress("perudo", {"perudo": true}) == Vector2i(2, 2), "Секрет Перудо")
	check(StatsScreen.coin_progress("unknown", {"": true}) == Vector2i(1, 1), "Нет выдуманного секрета")
	var probe = Table.TokenChip.new()
	for extent: Vector2 in [Vector2(52, 86), Vector2(96, 52), Vector2(52, 52)]:
		probe.size = extent
		var rect: Rect2 = probe.token_rect()
		check(is_equal_approx(rect.size.x, rect.size.y), "Квадратный рисунок в вытянутом слоте")
		check(rect.get_center().is_equal_approx(extent / 2), "Жетон центрирован")
	probe.free()
	prefs.coin_secrets = {"perudo": true, "gloom": true}
	for mode: String in ["light", "dark"]:
		prefs.theme_mode = mode
		get_tree().root.theme = HubStyle.theme()
		var stats = StatsScreen.new()
		get_tree().root.add_child(stats)
		await shot("stats-coins-" + mode)
		var select: OptionButton = stats.find_children("*", "OptionButton", true, false)[0]
		var index: int = stats._game_ids.find("gloomier")
		select.select(index)
		select.item_selected.emit(index)
		await shot("stats-coins-filter-" + mode)
		stats.queue_free()
		await get_tree().process_frame
		var app = load("res://games/ready_set_bet/ui/main.tscn").instantiate()
		get_tree().root.add_child(app)
		await get_tree().process_frame
		net.host_offline("ready_set_bet")
		net.set_bots(3)
		net.start_game()
		net.set_process(false)
		await get_tree().process_frame
		var rules := RSBRules.new()
		var players: Array = []
		for i in 4:
			players.append({"name": "Игрок %d" % (i + 1), "peer": 1, "bot": false})
		rules.new_game(players, 1234)
		rules.start_race()
		rules.place(0, 0, "s_0_0")
		app.screen._on_state(rules.get_view(0))
		await get_tree().process_frame
		await get_tree().process_frame
		for chip in app.screen._tray.get_children():
			var rect: Rect2 = chip.token_rect()
			check(is_equal_approx(rect.size.x, rect.size.y), "Настоящий лоток круглый: " + mode)
			var transform: Transform2D = chip.get_global_transform_with_canvas()
			check(is_equal_approx(transform.x.length(), transform.y.length()), "Нет растяжения осей: " + mode)
			print("ЛОТОК ", mode, " слот=", chip.size, " рисунок=", rect.size)
		await shot("rsb-round-table-" + mode)
		net.leave()
		net.set_process(true)
		app.queue_free()
		await get_tree().process_frame
	print("ПРОВЕРКИ ", checks, " ОШИБКИ ", errors)
	get_tree().quit(1 if errors else 0)



