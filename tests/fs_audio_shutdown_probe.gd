extends SceneTree
## Диагностика освобождения Ogg: Dummy, отдельный профиль; FS_STOP_AUDIO=1 останавливает до выхода.
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var sfx := root.get_node("Sfx")
	sfx.set_playlist(["res://games/gloom/audio/death_waltz.ogg"])
	await create_timer(0.25).timeout
	if OS.get_environment("FS_STOP_AUDIO") == "1":
		sfx._music.stop()
		sfx._music.stream = null
	print("AUDIO SHUTDOWN stop=",OS.get_environment("FS_STOP_AUDIO"))
	if OS.get_environment("FS_GRACEFUL_AUDIO") in ["1","2"]:
		sfx.play("die_grab")
		if OS.get_environment("FS_PAUSED_EXIT") == "1":
			paused = true
		if OS.get_environment("FS_GRACEFUL_AUDIO") == "2":
			root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		else:
			sfx.request_quit()
		sfx.request_quit() # Повторное нажатие не создаёт второй таймер выхода.
		var stopping: bool = sfx._quitting
		var stopped: bool = not sfx._music.playing and sfx._music.stream == null
		sfx.start_music()
		sfx.set_playlist(["res://games/gloom/audio/death_waltz.ogg"])
		sfx.play("die_throw")
		var restart_blocked: bool = sfx._music.stream == null
		print("AUDIO EXIT CHECKS stopping=",stopping," stopped=",stopped," restart_blocked=",restart_blocked)
		assert(stopping and stopped and restart_blocked)
		await process_frame
	else:
		quit()
