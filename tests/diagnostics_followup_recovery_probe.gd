extends SceneTree
## Только собственный изолированный профиль: seed убивает себя после переполнения; verify/clean выходят штатно.
## Все запуски с Dummy; один и тот же --log-file дополнительно проверяет перезапись стандартного журнала.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var diag: Node = root.get_node("Diag")
	var mode := OS.get_cmdline_user_args()[0]
	if mode == "seed":
		print("ТЕСТ_ENGINE_PATH=", diag._engine_log())
		for i: int in 170:
			diag.sink.checkpoint("наполнение_" + str(i) + "x".repeat(15900), "публичный контекст")
		print("ENGINE_СЕАНС_ДО_KILL")
		diag.mark("FOLLOWUP_ПОСЛЕДНИЙ_ЭТАП", {"игра": "the_gang"})
		push_error("ОЖИДАЕМАЯ_RECOVERY_ПОСЛЕДНЯЯ_ОШИБКА")
		diag._process(5.0)
		print("СОБСТВЕННЫЙ_KILL_PID=", OS.get_process_id())
		OS.kill(OS.get_process_id())
		return
	var checks := 0
	var errors := 0
	if mode == "verify":
		var previous: Dictionary = diag.previous_session
		var report: String = diag.report_text(str(previous.get("log", "")))
		var conditions: Array[bool] = [
			not previous.is_empty(),
			int(previous.get("pid", 0)) != OS.get_process_id(),
			previous.get("stage") == "FOLLOWUP_ПОСЛЕДНИЙ_ЭТАП",
			report.contains("FOLLOWUP_ПОСЛЕДНИЙ_ЭТАП"),
			report.contains("ОЖИДАЕМАЯ_RECOVERY_ПОСЛЕДНЯЯ_ОШИБКА"),
			report.contains("diagnostics_followup_recovery_probe.gd"),
			report.contains("ENGINE_СЕАНС_ДО_KILL"),
			not report.contains("Предыдущий запуск не завершён штатно"),
			FileAccess.file_exists(str(previous.get("engine_snapshot", "")))
		]
		if OS.get_environment("DIAG_CUSTOM_LOG") == "1":
			conditions[6] = str(previous.get("engine_log", "")).is_empty()
			conditions[8] = report.contains("Журнал отсутствует.")
		for condition: bool in conditions:
			checks += 1
			if not condition:
				errors += 1
				print("ПРОВАЛ_RECOVERY_ПРОВЕРКА=", checks)
	else:
		checks += 1
		if not diag.previous_session.is_empty():
			errors += 1
	print("RECOVERY FOLLOWUP ", mode, ": проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
