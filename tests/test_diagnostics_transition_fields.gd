extends SceneTree
## Разрешены только типизированные технические метаданные перехода, не payload/секреты.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var diag := root.get_node("Diag")
	var checks := 0
	var errors := 0
	var known := {"предыдущая_игра": "wavelength", "игра_команды": "hues_and_cues", "игра_пакета": "wavelength", "партия_пакета": "old-1", "ожидаемая_партия": "new-2", "подписок": 17, "поколение": 2}
	var filtered: Dictionary = diag._safe_details(known)
	for key: String in known:
		checks += 1
		if filtered.get(key) != known[key]:
			errors += 1
			push_error("Не сохранено разрешённое поле: " + key)
	var wrong := {"предыдущая_игра": {"hand": [1, 2]}, "ожидаемая_партия": ["тайное"], "подписок": "ключ", "поколение": -1, "payload": {"api_key": "тест"}, "chat": "тест"}
	filtered = diag._safe_details(wrong)
	checks += 1
	if not filtered.is_empty():
		errors += 1
		push_error("Неверные типы или произвольные данные попали в детали перехода")
	print("DIAG TRANSITION FIELDS: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
