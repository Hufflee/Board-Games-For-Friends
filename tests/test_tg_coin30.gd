extends SceneTree
## Монеты The Gang и Things in Rings в антистрессе: в своей партии выбирается своя монета, обе стороны грузятся.
## Запуск: godot --path . --audio-driver Dummy --script res://tests/test_tg_coin30.gd  (кадры — build/tg30/coin_ingame_<игра>.png)

var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("ОШИБКА: ", msg)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for game in ["the_gang", "things_in_rings"]:
		await _coin(game)
	print("ИТОГ: ошибок ", _fails)
	quit(1 if _fails > 0 else 0)

func _coin(game: String) -> void:
	var net: Node = root.get_node("Net")
	net.party_game = game
	var bg := ColorRect.new()
	bg.color = Color("2b2118")
	bg.size = Vector2(320, 200)
	root.add_child(bg)
	var coin: Control = load("res://hub/fidget.gd").new()
	root.add_child(coin)
	for i in 10:
		await process_frame
	check(coin.call("_style_for") == game, "в %s своя монета, а не «%s»" % [game, coin.call("_style_for")])
	var fidget: GDScript = coin.get_script()
	for path in fidget.TEXTURES[game]:
		check(fidget._tex(path) != null, "картинка монеты грузится: " + path)
	check(fidget.COIN_REGIONS.has(game), "у листа %s есть области сторон" % game)
	coin.set_process(false)  # вне партии монетка прячется сама — для кадра держим её на виду
	coin.visible = true
	coin.call("_set_style", coin.call("_style_for"))  # без партии подброс-смена облика не идёт
	coin.modulate.a = 1.0
	coin.scale = Vector2.ONE * 2.0
	coin.position = Vector2(140, 60)
	for i in 20:
		await process_frame
	check(coin.get("_style") == game, "на экране монета " + game)
	coin.position = Vector2(140, 60)  # отложенная «посадка в гнездо» могла увести её к краю
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/tg30"))
	root.get_texture().get_image().save_png("res://build/tg30/coin_ingame_%s.png" % game)
	coin.queue_free()
	bg.queue_free()
	await process_frame
