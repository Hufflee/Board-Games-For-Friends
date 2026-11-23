extends SceneTree
## Оконная проверка особых стопок, ширины поля, полных имён и фишки Хайда в обеих темах.
const Match := preload("res://games/unmatched/logic/um_match.gd")
const Art := preload("res://games/unmatched/ui/um_card_art.gd")
var checks := 0
var errors := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var prefs := root.get_node("Prefs")
	prefs.window_mode = "windowed"
	prefs.resolution = "1280x720"
	for mode: String in ["light", "dark"]:
		prefs.theme_mode = mode
		prefs.apply()
		for heroes: Array in [["witches", "shakespeare"], ["titania", "hamlet"], ["oda", "tomoe"], ["jekyll_hyde", "dracula"]]:
			var session: RefCounted = Match.create("marmoreal", PackedStringArray(heroes), [{"name": "А"}, {"name": "Б"}], 12)
			var table: Control = load("res://games/unmatched/ui/table.tscn").instantiate()
			root.add_child(table)
			table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			table.present(session.get_view(0))
			for frame in 8: await process_frame
			check(table._fight_frame.size.x <= 466, "Особые стопки не расширяют правую панель · %s" % heroes[0])
			check(table._board.size.x >= 700 and table._board.size.y >= 200, "Поле сохраняет размеры при особых стопках")
			for index in 2:
				var row: Control = table._piles._rows.get_child(index)
				var name: Label = row.get_child(0)
				check(name.text == Match.Roster.HEROES[heroes[index]].name and not name.clip_text,
					"Полное имя героя показано с переносом")
				if heroes[index] in ["witches", "shakespeare", "titania"]:
					var special: Button = row.get_child(2)
					check(special.visible and special.global_position.y > name.global_position.y + name.size.y,
						"Особая стопка расположена под именем своего героя")
					check(special.get_global_rect().end.y < table._attack.global_position.y, "Бой расположен ниже особой стопки")
			if heroes[0] == "titania":
				for index in 6:
					check(Art.face(session.rules.bard.enchantment_card(index)) != null, "Изображение чар импортировано")
				table._set_preview(Art.face(session.rules.bard.enchantment_card(1)), "probe")
			if heroes[0] == "jekyll_hyde":
				check(session.get_view(0).fighters.any(func(figure: Dictionary) -> bool: return figure.seat == 0 and figure.token == "jekyll_hyde"), "Джекилл использует прежнюю фишку")
				session.rules.hyde = true
				var view: Dictionary = session.get_view(0)
				check(view.fighters.any(func(figure: Dictionary) -> bool: return figure.seat == 0 and figure.token == "hyde"), "Хайд использует отдельное лицо")
				table.present(view)
				check(Art.texture("res://games/unmatched/art/tokens/hyde.webp") != null, "Лицо Хайда загружается")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("res://build/shots/unmatched_expansion")
				root.get_texture().get_image().save_png("res://build/shots/unmatched_expansion/bard_%s_%s.png" % [heroes[0], mode])
			table.queue_free()
			await process_frame
			session.close()
	print("Unmatched, особые стопки и формы: %d проверок, %d ошибок" % [checks, errors])
	quit(int(errors > 0))


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
