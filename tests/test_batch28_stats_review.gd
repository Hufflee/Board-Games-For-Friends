extends SceneTree
## Узкие фильтры/последняя коллекция и чистота UI. Только синтетические локальные снимки Store, не сеть.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func frames() -> void:
	for index in 5:
		await process_frame

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	var net: Node = root.get_node("Net")
	var store: RefCounted = net.player_stats
	for row: Array in [["brodilka", {"1": 1, "6": 3}], ["perudo", {"2": 2}]]:
		check(store.consume({"id": "low-ui-" + row[0], "game": row[0], "seat": 0, "totals": {"dice": row[1]}}), "Подготовлен локальный снимок " + row[0])
	var data_before: Dictionary = store.data.duplicate(true)
	var file_before := FileAccess.get_file_as_string(store.path)
	var secrets_before: Dictionary = root.get_node("Prefs").coin_secrets.duplicate(true)
	var ui: Control = load("res://hub/player_stats_screen.gd").new()
	root.add_child(ui)
	await frames()
	var picker: OptionButton = ui.find_children("*", "OptionButton", true, false)[0]
	for game: String in ["brodilka", "perudo", "phantom_ink", ""]:
		var selected: int = ui._game_ids.find(game)
		check(selected >= 0, "Фильтр доступен: " + game)
		# Штатный сигнал выбора OptionButton; не заменяем фильтрацию собственной логикой.
		picker.select(selected)
		picker.item_selected.emit(selected)
		await frames()
		check(ui._filter == game, "Сигнал выбора применяет фильтр: " + game)
		var collection: Control = ui._body.get_node("CoinsCollection")
		check(collection == ui._body.get_child(ui._body.get_child_count() - 1), "Коллекция последняя при фильтре: " + game)
		var pairs := collection.get_child_count() - 1
		check(pairs == (ui._game_ids.size() - 1 if game.is_empty() else 1), "Нет чужих/потерянных пар монет: " + game)
		for pair in collection.get_children():
			if pair is HBoxContainer:
				var title: Label = pair.get_child(0)
				var count: Label = pair.get_child(1)
				check(is_equal_approx(count.global_position.x - title.get_global_rect().end.x, 8.0), "Реальный зазор8px: " + title.text)
		var faces := []
		var counts_by_filter := {"brodilka": {"1": 1, "6": 3}, "perudo": {"2": 2}, "phantom_ink": {}, "": {"1": 1, "2": 2, "6": 3}}
		var expected_counts: Dictionary = counts_by_filter[game]
		var total := 0
		for count in expected_counts.values():
			total += int(count)
		for line in ui._body.get_children():
			if line is HBoxContainer and line.get_child_count() == 3 and line.get_child(1) is ProgressBar:
				var face := str(line.get_child(0).text)
				faces.append(face)
				var count := int(expected_counts.get(face, -1))
				var percent := 100.0 * count / total if total else 0.0
				check(count >= 0 and line.get_child(2).text == "%.1f%% · %d раз" % [percent, count], "Количество/процент соответствуют фильтру: " + game + "/" + face)
		# Требование — полнота/изоляция граней, не порядок: Store показывает сначала частые.
		faces.sort()
		var expected := {"brodilka": ["1", "6"], "perudo": ["2"], "phantom_ink": [], "": ["1", "2", "6"]}
		check(faces == expected[game], "Реальные строки граней соответствуют фильтру: " + game)
	check(store.data == data_before, "Чтение и фильтры не мутируют Store.data")
	check(FileAccess.get_file_as_string(store.path) == file_before, "UI не переписывает файл статистики")
	check(root.get_node("Prefs").coin_secrets == secrets_before, "Показ коллекции не меняет секреты Prefs")
	ui.queue_free()
	await frames()
	print("STATS LOW: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
