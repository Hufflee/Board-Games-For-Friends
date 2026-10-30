extends SceneTree
## Узкая графическая проверка фона финала, маски аватара и настоящей верхней полосы.
## Godot --audio-driver Dummy --rendering-method gl_compatibility --script res://tests/test_victory30.gd
var checks := 0
var errors := 0
var net: Node
var screen: Control
var bar: Control

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("V30 ", "OK " if ok else "FAIL ", message)
	if not ok:
		errors += 1

func settle() -> void:
	await create_timer(0.25).timeout

func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await settle()

func capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://build/victory30/" + name + ".png")
	return image

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	var prefs: Node = root.get_node("Prefs")
	for game: String in ["perudo", "the_gang"]:
		for theme: String in ["light", "dark"]:
			prefs.theme_mode = theme
			net.host_offline(game)
			net.set_bots(3)
			check(net.start_game() == "", game + ": партия подготовлена")
			net.set_process(false)
			var rules: Object = net._game_obj()
			rules.phase = "game_over"
			if game == "perudo":
				rules.winner = 0
			else:
				rules.won = true
			# Контролируемый кеш с реальным артом проекта; Steam API не вызывается.
			var texture: Texture2D = load("res://games/brodilka/art/cards/pawn_3.png")
			net._avatars[123456] = texture
			var checker := Image.create(128, 64, false, Image.FORMAT_RGBA8)
			checker.fill(Color.RED)
			checker.fill_rect(Rect2i(32, 0, 64, 64), Color.GREEN)
			net._avatars[123457] = ImageTexture.create_from_image(checker)
			var rounded := Image.create(64, 64, false, Image.FORMAT_RGBA8)
			for y: int in 64:
				for x: int in 64:
					var edge := (Vector2(x, y) + Vector2.ONE * 0.5 - Vector2.ONE * 32).abs() - Vector2.ONE * 14
					var distance_to_edge := edge.max(Vector2.ZERO).length() + minf(maxf(edge.x, edge.y), 0.0) - 18
					rounded.set_pixel(x, y, Color(0, 1, 1, 1 if distance_to_edge < 0 else 0))
			net._avatars[123458] = ImageTexture.create_from_image(rounded)
			for seat: int in rules.players.size():
				rules.players[seat].steam_id = [123458, 123456, 123457, 0][seat]
			net.steam_ok = true
			net._push_state()
			var app: Control = load("res://games/" + game + "/ui/main.tscn").instantiate()
			root.add_child(app)
			current_scene = app
			await create_timer(0.6).timeout
			await settle()
			screen = app.screen.get_node("VictoryScreen")
			bar = app.screen._top
			var backdrop: Control = screen._backdrop
			check(backdrop.get_global_rect() == Rect2(0, 0, 1280, 720), "Фон покрывает весь экран вместе с полосой")
			check(bar._victory_backdrop and bar.get_theme_stylebox("panel") == bar._victory_panel, "Настоящая полоса прозрачна над финалом")
			check(bar.coin_dock.z_index > screen.z_index, "Гнездо монеты поверх фона")
			var coins: Array[Node] = app.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node.get_script() != null and node.get_script().resource_path == "res://hub/fidget.gd")
			check(coins.size() == 1 and coins[0].visible and coins[0].z_index > screen.z_index, "Одна настоящая видимая монетка поверх фона")
			for card: Control in screen._cards:
				var avatar: TextureRect = card.get_node("Avatar")
				check(avatar.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "Пропорциональная обрезка аватара без деформации")
				check((avatar.material as ShaderMaterial).get_shader_parameter("slot_size") == avatar.size, "Маска использует фактический размер слота")
			var id := game + "-" + theme
			var art: Control = backdrop.get_node_or_null("GameBackdrop")
			check(art != null and art.get_global_rect() == Rect2(0, 0, 1280, 720), "Фон игры (без поля) под всем экраном")
			var confetti := screen.get_node_or_null("Confetti")
			check(confetti is CPUParticles2D and (confetti as CPUParticles2D).direction.y > 0 and (confetti as CPUParticles2D).gravity.y > 0, "Конфетти летят вниз")
			# Движущиеся конфетти и параллакс мешают попиксельному сравнению кадров.
			if confetti:
				confetti.free()
			if art:
				art.set_process(false)
			var image := await capture(id + "-closed")
			var checker_avatar: TextureRect = screen._cards[2].get_node("Avatar")
			var rect := checker_avatar.get_global_rect()
			var center_color := image.get_pixelv(rect.get_center())
			var left_color := image.get_pixelv(rect.position + Vector2(2, rect.size.y * 0.5))
			var corner_color := image.get_pixelv(rect.position + Vector2.ONE)
			check(center_color.g > center_color.r + 0.3 and left_color.g > left_color.r + 0.3, "Прямоугольный UV fixture обрезан по центру, красные края за слотом")
			check(corner_color.g - corner_color.r < left_color.g - left_color.r - 0.2, "Маска убирает квадратные углы изображения")
			var alpha_avatar: TextureRect = screen._cards[0].get_node("Avatar")
			var inside := image.get_pixelv(alpha_avatar.global_position + Vector2.ONE * 4)
			check(alpha_avatar.texture is AtlasTexture and inside.g > 0.8 and inside.b > 0.8, "Исходные альфа-углы не оставляют зазор внутри маски слота")
			check(bar.title.get_theme_color("font_color").get_luminance() > 0.5 if game == "the_gang" or theme == "dark" else bar.title.get_theme_color("font_color").get_luminance() < 0.5, "Название контрастно новому фону")
			# Ядовитая подложка выявляет прозрачные участки поверх старого стола.
			var poison := ColorRect.new()
			poison.color = Color.MAGENTA
			poison.mouse_filter = Control.MOUSE_FILTER_IGNORE
			app.screen.add_child(poison)
			poison.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var poisoned := await capture(id + "-poison")
			var magenta := func(c: Color) -> bool: return c.r > 0.8 and c.b > 0.8 and c.g < 0.3
			check(not magenta.call(poisoned.get_pixel(1000, 16)) and not magenta.call(poisoned.get_pixel(1000, 500)), "Старый стол не просвечивает ни сверху, ни снизу")
			poison.queue_free()
			await click(bar._esc_btn)
			check(bar._menu_open and bar._drawer.is_visible_in_tree(), "Настоящий TopBar открывается поверх финала")
			await capture(id + "-open")
			await click(screen._buttons.get_node("ShowTable"))
			check(not backdrop.visible and not screen._surface.visible and screen._return.visible, "Настоящий клик показывает исходный стол")
			check(not bar._victory_backdrop and bar.get_theme_stylebox("panel") == bar._table_panel and bar.coin_dock.z_index == 0, "При просмотре возвращается оформление полосы и гнезда")
			await capture(id + "-table")
			await click(screen._return)
			check(backdrop.visible and screen._surface.visible and bar._victory_backdrop, "Настоящий возврат восстанавливает полный фон")
			await capture(id + "-return")
			screen.players[3].steam_id = 123459
			net._avatars[123459] = net._avatars[123458]
			screen._avatar_check_ms = 0
			screen._refresh_avatars()
			var late: Control = screen._cards[3]
			check(late.get_node("Avatar").texture is AtlasTexture and not late.get_node("Initials").visible, "Поздний кешированный альфа-аватар проходит ту же обрезку и заменяет инициалы")
			screen.sync({"phase": "bid"})
			check(not screen.visible and not bar._victory_backdrop, "Вне финала скрывается весь новый фон и восстанавливается полоса")
			screen.sync(net.view)
			check(screen.visible and bar._victory_backdrop, "Повторный финал восстанавливает общий фон")
			net.steam_ok = false
			net._avatars.erase(123456)
			net._avatars.erase(123457)
			net._avatars.erase(123458)
			net._avatars.erase(123459)
			app.queue_free()
			await process_frame
			net.leave()
			await settle()
	print("VICTORY30 ", checks, "/", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
