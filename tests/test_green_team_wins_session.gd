extends SceneTree
## Локальная партия через Net с проверкой интерфейса и 15 вопросов.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var net: Node = root.get_node("Net")
	net.host_offline("green_team_wins")
	net.set_bots(2)
	change_scene_to_file("res://games/green_team_wins/ui/main.tscn")
	await scene_changed
	var err: String = net.start_game()
	if not err.is_empty():
		printerr(err)
		quit(1)
		return
	var shot := false
	for i in 110:
		var v: Dictionary = net.view
		var data := {"round":v.get("round",-1)}
		match v.get("phase",""):
			"answer":
				if OS.has_environment("GTW_SCREENSHOT") and not shot:
					shot = true
					await process_frame
					var img: TextureRect = current_scene.find_children("*","TextureRect",true,false)[0]
					current_scene._show_preview(img)
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OS.get_environment("GTW_SCREENSHOT"))
				for s in v.names.size():
					if s not in v.answered:
						net.send_action("gtw_seat",{"seat":s})
						data.answer = "Кот" if str(v.card).begins_with("blank") else "1"
						net.send_action("answer",data)
						break
			"group":
				net.send_action("score",data)
			"result":
				net.send_action("next",data)
			"end":
				print("Green Team Wins: локальная партия через Net завершена")
				quit(0)
				return
		await process_frame
	printerr("Не дошли до финала")
	quit(1)
