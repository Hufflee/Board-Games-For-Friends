extends SceneTree
## Проверка восстановления журнала после принудительного завершения тестового процесса.
## Только с отдельным APPDATA: запускать -- seed, затем -- verify, затем -- clean.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var diag = root.get_node("Diag")
	var mode := OS.get_cmdline_user_args()[0]
	if mode == "seed":
		diag.mark("ПОСЛЕДНИЙ_ЭТАП_ПЕРЕД_ЗАВЕРШЕНИЕМ", {"игра": "stillion"})
		OS.kill(OS.get_process_id())
	elif mode == "verify":
		var deadline := Time.get_ticks_msec() + 16000
		while diag._native_pid > 0 and Time.get_ticks_msec() < deadline:
			await create_timer(0.1).timeout
		var old: Dictionary = diag.previous_session
		var text: String = diag.report_text(str(old.get("log", "")))
		var ok: bool = int(old.get("pid", 0)) != OS.get_process_id() and text.contains("ПОСЛЕДНИЙ_ЭТАП_ПЕРЕД_ЗАВЕРШЕНИЕМ")
		ok = ok and text.contains("stillion") and text.contains("=== Windows")
		ok = ok and not text.contains("Предыдущий запуск не завершён штатно")
		print("ВОССТАНОВЛЕНИЕ ПОСЛЕ ЗАВЕРШЕНИЯ: ", ok)
		quit(0 if ok else 1)
	else:
		var ok: bool = diag.previous_session.is_empty()
		print("ЧИСТЫЙ ПОВТОРНЫЙ ЗАПУСК: ", ok)
		quit(0 if ok else 1)
