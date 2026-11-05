extends "res://tests/test_fs_table_runtime.gd"
## Обязательный выбор отдающего душу: переключение места, просмотр и настоящий клик.
const Batch := preload("res://tests/fs/core/core_automation_batch18.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(15)
	table = current_scene.screen
	var s = Batch.new()._monster(Check.new(), 382)
	for id in [475, 414]:
		s._take(id)
		s.g._gain_soul_card(1, {"id": id, "value": 1})
	Batch.new()._trigger(s, "monster_death", {"seat": 0, "card": 382})
	s.choose(0, "soul_giver18", {"target": 1})
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(5)
	check(table._v.card_choices.is_empty(), "382 активный не получает выбор за другого игрока")
	table._switch(1)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(5)
	check(table._v.card_choices.size() == 2, "382 отдающему показаны обе его души")
	check(table._v.card_choice_previews == [475, 414], "382 карточные варианты имеют крупный просмотр")
	await click(find_button("Выбрать цель / вариант"))
	await frames(5)
	var pick := find_button(str(table._v.card_choices[0]))
	check(pick != null and not pick.disabled, "382 реальная кнопка выбора доступна отдающему")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/soul_giver18.png")
	await click(pick)
	await frames(5)
	check(s.g.souls == [1, 1, 0], "382 настоящий клик передал выбранную физическую душу")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS MONSTER18 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
