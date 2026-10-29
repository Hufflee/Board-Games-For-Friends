extends SceneTree
## Адресный визуальный проход новых меню/лобби/служебных окон в обеих темах.
var errors := 0
var checks := 0

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func settle() -> void:
	for i: int in 5:
		await process_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/tir_game/" + label + ".png")

func _run() -> void:
	root.size = Vector2i(1280,720)
	var net := root.get_node("Net")
	for mode: String in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = mode
		var app: Control = load("res://games/things_in_rings/ui/main.tscn").instantiate()
		root.add_child(app)
		current_scene = app
		await settle()
		await shot("menu-" + mode)
		app.show_rules()
		await settle()
		var rules: Control = app.get_node("RulesOverlay")
		check(Rect2(Vector2.ZERO, Vector2(1280,720)).encloses(rules.get_global_rect()), "Правила полностью в720p")
		await shot("rules-" + mode)
		rules.queue_free()
		await settle()
		app.show_settings()
		await settle()
		await shot("settings-" + mode)
		for child: Node in app.get_children():
			if child.get_script() == load("res://games/king_of_12/ui/settings_screen.gd"):
				check(child.make_panel.is_valid() and child.ink == load("res://games/things_in_rings/ui/tr_style.gd").ink(), "Настройки оформлены стилем игры")
				child.queue_free()
		net.host_offline("things_in_rings")
		net.set_bots(1)
		for i: int in 5:
			net.set_setting("tr_knower", i % 2)
		await settle()
		check(app.screen.find_children("*", "K12ChatPanel", true, false).size() == 1, "Смена настроек лобби сохраняет одну панель чата")
		await shot("lobby-" + mode)
		app.queue_free()
		net.leave()
		await settle()
	print("TIR PRESENTATION: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
