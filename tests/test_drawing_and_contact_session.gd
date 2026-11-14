extends SceneTree
## Проверка запуска карт и планшетов через реальные сцены.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var net := root.get_node("Net")
	for id in ["in_broad_strokes","first_contact"]:
		net.call("host_offline",id)
		net.call("set_bots",2)
		change_scene_to_file("res://games/"+id+"/ui/main.tscn")
		await scene_changed
		var err: String = net.call("start_game")
		if not err.is_empty():
			printerr(err)
			quit(1)
			return
		await process_frame
		var v: Dictionary = net.get("view")
		var seat_action := "ibs_seat" if id == "in_broad_strokes" else "fc_seat"
		net.call("send_action",seat_action,{"seat":v.turn})
		v = net.get("view")
		if v.seat != v.turn:
			printerr("Не передан ход")
			quit(1)
			return
		if id == "in_broad_strokes":
			net.call("send_action","draw",{"serial":v.serial,"strokes":[PackedVector2Array([Vector2(.2,.2),Vector2(.8,.8)])]})
			await create_timer(.8).timeout
			v = net.get("view")
			if v.phase != "guess":
				printerr("Не завершено совмещение")
				quit(1)
				return
		else:
			net.call("send_action","ask",{"serial":v.serial,"slots":[0,1]})
			v = net.get("view")
			if v.phase != "teach":
				printerr("Не началось объяснение")
				quit(1)
				return
		if OS.has_environment("QUEUE_SHOTS"):
			var folder := OS.get_environment("QUEUE_SHOTS")
			var prefs := root.get_node("Prefs")
			for mode in ["light","dark"]:
				prefs.set("theme_mode",mode)
				prefs.emit_signal("changed")
				await process_frame
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				image.save_png(folder+"/"+id+"_"+mode+".png")
		current_scene.queue_free()
		await process_frame
		net.call("leave")
		await process_frame
	print("Две игры: локальный вход через Net и игровые переходы проверены")
	quit(0)
