extends SceneTree
## Прогон через Net и настоящий игровой интерфейс за одним компьютером.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var net: Node = root.get_node("Net")
	net.host_offline("colt_express")
	net.set_bots(2)
	net.set_setting("ce_horses",true)
	net.set_setting("ce_whiskey",true)
	net.set_setting("ce_sprites",true)
	net.set_setting("ce_cursed",OS.has_environment("CE_EXPANSIONS"))
	net.set_setting("ce_coach",OS.has_environment("CE_EXPANSIONS"))
	net.set_setting("ce_marshal",OS.has_environment("CE_EXPANSIONS"))
	net.set_setting("ce_time_car",OS.has_environment("CE_EXPANSIONS"))
	change_scene_to_file("res://games/colt_express/ui/main.tscn")
	await scene_changed
	var err: String = net.start_game()
	if not err.is_empty():
		printerr(err)
		quit(1)
		return
	var shot := false
	for i in 2000:
		var v: Dictionary = net.view
		var payload := {"serial":v.get("serial",-1)}
		var phase: String = v.get("phase","")
		if phase in ["select","mount","travel","plan","discard","choose","reserve","reflex","reaction"] and v.seat != v.turn:
			net.send_action("ce_view_seat",{"seat":v.turn})
			v = net.view
			if v.seat != v.turn:
				printerr("Не передано локальное место")
				quit(1)
				return
		match phase:
			"select":
				payload.id = v.board.bandits.size() - int(OS.has_environment("CE_EXPANSIONS"))
				net.send_action("select",payload)
			"mount":
				payload.land = true
				net.send_action("mount",payload)
			"travel":
				payload.car = 1
				net.send_action("travel",payload)
			"plan":
				var index: int = v.hand.find_custom(func(c: Dictionary) -> bool: return c.kind != "bullet" and not (v.steps[v.step] == "к" and c.kind in ["shoot","punch"]))
				payload.index = index
				net.send_action("play" if index >= 0 else "draw",payload)
			"choose","reaction":
				payload.index = 0
				net.send_action("choose",payload)
			"reserve","reflex","discard":
				net.send_action("keep",payload)
			"reveal":
				net.send_action("next",payload)
			"animate","replay","match_replay":
				if not shot and OS.has_environment("CE_SCREENSHOT") and phase == "animate" and v.clip.card.kind == "shoot" and v.clip.applied:
					shot = true
					await create_timer(0.28).timeout
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OS.get_environment("CE_SCREENSHOT"))
				net._process(2.0)
			"end":
				print("Кольт Экспресс: локальная партия через Net и стол завершена")
				current_scene.queue_free()
				await process_frame
				await process_frame
				quit(0)
				return
		await process_frame
	printerr("Партия не дошла до финала: ",net.view.get("phase",""))
	quit(1)
