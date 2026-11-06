extends "res://tests/test_fs_table_runtime.gd"
## 06.11 (владелец): в чужой ход свои карты — только в ответ на действие в стеке (окно тишины 5 с).
func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	net.fours.current = 0
	net.fours.phase = "turn"
	net.fours.hands[1] = [478]
	net.fours.character_ready[1] = true
	net.fs_switch_seat(1)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	table._view_at = Time.get_ticks_msec() - 11000
	# 06.11 (владелец): в чужой ход — только в ответ, пока в стеке что-то есть (5 с тишины).
	check(not table._off_turn_ok(), "Без действия в стеке своих карт в чужой ход нет")
	await click(find_button("Открыть мою руку"))
	await frames(5)
	net.fours._push({"kind": "roll", "value": 3, "owner": 0}, "turn")
	net._push_state()
	await frames(5)
	check(table._off_turn_ok() and table._can_play_hand(), "На бросок в стеке можно ответить лутом (поворот персонажа)")
	print("OFF TURN CLOCK UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
