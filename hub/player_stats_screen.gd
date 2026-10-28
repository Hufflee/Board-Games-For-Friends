extends Control
## Личная статистика в неоновой стилистике главного меню.
var _body: VBoxContainer
var _filter := ""
var _graph_open := false
var _game_ids: Array = [""]


func _ready() -> void:
	z_index = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var panel := HubStyle.panel(HubStyle.CYAN)
	margin.add_child(panel)
	var col := HubStyle.vbox(14)
	panel.add_child(col)
	var head := HubStyle.hbox(16)
	col.add_child(head)
	var title := HubStyle.neon_label("СТАТИСТИКА ИГРОКА", 26, HubStyle.CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := HubStyle.button("Закрыть", 15)
	close.pressed.connect(queue_free)
	head.add_child(close)
	var select := OptionButton.new()
	select.add_item("Все игры")
	for game: Dictionary in HubGames.LIST:
		if _game_ids.has(str(game.id)):
			continue
		_game_ids.append(str(game.id))
		select.add_item(str(game.title))
	select.item_selected.connect(
		func(index):
			_filter = str(_game_ids[index])
			_rebuild()
	)
	col.add_child(select)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = HubStyle.vbox(16)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_rebuild()


func _label(text: String, color: Color = HubStyle.TEXT, font_size: int = 16) -> Label:
	var label := HubStyle.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _metric(parent: Control, title: String, value: String, detail: String, color: Color) -> void:
	var panel := HubStyle.panel(color)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var col := HubStyle.vbox(6)
	panel.add_child(col)
	col.add_child(_label(title, HubStyle.MUTED, 14))
	col.add_child(_label(value, color, 30))
	col.add_child(_label(detail, HubStyle.MUTED, 14))


## Общий ключ Gloom/Gloomier и отдельные варианты Тип Топа совпадают с Fidget.
static func coin_progress(game_id: String, secrets: Dictionary) -> Vector2i:
	var key := "perudo" if "perudo" in game_id else ""
	for mapping: Array in Fidget.GAME_COINS:
		if str(mapping[0]) in game_id:
			key = str(mapping[0])
			break
	var supported := key == "perudo" or Fidget.TEXTURES.has(key + "_secret")
	var total := 2 if supported else 1
	return Vector2i(2 if supported and bool(secrets.get(key, false)) else 1, total)


func _coins() -> void:
	var collection := HubStyle.vbox(8)
	collection.name = "CoinsCollection"
	_body.add_child(collection)
	collection.add_child(_label("МОНЕТЫ", HubStyle.CYAN, 19))
	for game: Dictionary in HubGames.LIST:
		if not _filter.is_empty() and str(game.id) != _filter:
			continue
		var progress := coin_progress(str(game.id), Prefs.coin_secrets)
		var color := Color("8ee6a0") if progress.x == progress.y else HubStyle.YELLOW
		var line := HubStyle.hbox(8)
		collection.add_child(line)
		line.add_child(HubStyle.label(str(game.title), 16, HubStyle.TEXT))
		line.add_child(HubStyle.label("%d/%d" % [progress.x, progress.y], 16, color))


func _rebuild() -> void:
	HubStyle.clear(_body)
	var row: Dictionary = Net.player_stats.summary(_filter)
	var metrics := HubStyle.hbox(14)
	_body.add_child(metrics)
	_metric(
		metrics,
		"ПОБЕДЫ",
		"%.1f%%" % (100.0 * int(row.wins) / int(row.completed)) if int(row.completed) > 0 else "—",
		"%d из %d партий с исходом" % [row.wins, row.completed],
		HubStyle.CYAN
	)
	_metric(
		metrics,
		"ОШИБКИ",
		"%.1f%%" % (100.0 * int(row.errors) / int(row.decisions)) if int(row.decisions) > 0 else "—",
		"%d ошибок · %d правильных решений" % [row.errors, int(row.decisions) - int(row.errors)],
		HubStyle.PINK
	)
	_metric(
		metrics,
		"РЕПЛИКИ",
		str(row.remarks),
		"%d сообщений · %d быстрых реплик" % [row.messages, row.emotes],
		HubStyle.YELLOW
	)
	var graph_button := HubStyle.button(
		("Скрыть график" if _graph_open else "График последних 100 партий") + " · %d" % row.history.size(), 16
	)
	graph_button.pressed.connect(
		func():
			_graph_open = not _graph_open
			_rebuild()
	)
	_body.add_child(graph_button)
	if _graph_open:
		_body.add_child(
			_label("Победа +1 · поражение −1 · слева старые партии, справа новые", HubStyle.MUTED, 14)
		)
		var graph := WinGraph.new()
		graph.history = row.history
		_body.add_child(graph)
	_body.add_child(_label("ВЫПАДЕНИЯ КУБИКОВ", HubStyle.CYAN, 19))
	var dice := PlayerStatsStore.sorted_dice(row)
	if dice.is_empty():
		_body.add_child(_label("Пока нет бросков.", HubStyle.MUTED))
	for entry: Dictionary in dice:
		var line := HubStyle.hbox(12)
		_body.add_child(line)
		var face := HubStyle.label(str(entry.face), 19, HubStyle.CYAN)
		face.custom_minimum_size.x = 36
		line.add_child(face)
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size.y = 18
		bar.max_value = 100
		bar.value = float(entry.percent)
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", HubStyle.box(HubStyle.BG, 5, HubStyle.VIOLET, 1, 0))
		bar.add_theme_stylebox_override("fill", HubStyle.box(HubStyle.CYAN, 5, HubStyle.CYAN, 0, 0))
		line.add_child(bar)
		var percent := HubStyle.label("%.1f%% · %d раз" % [entry.percent, entry.count], 15)
		percent.custom_minimum_size.x = 140
		line.add_child(percent)
	(
		_body
		. add_child(
			_label(
				"Ошибки считаются среди проверяемых рискованных решений: потеря кости в Перудо, боевого здоровья в Айзеке, штрафной подарок в «Это не шляпа!», потеря жетона капитаном в Тип Топе и выстрел после неуспешного ответа/молчания в Стиллионе. Решение без такой потери считается правильным. Чужой урон сам по себе не является вашей ошибкой.",
				HubStyle.MUTED,
				13
			)
		)
	)
	(
		_body
		. add_child(
			_label(
				"Статистика хранится на этом компьютере и собирается с момента добавления этой функции. Незавершённые партии не влияют на процент побед.",
				HubStyle.MUTED,
				13
			)
		)
	)
	if int(row.get("unrated", 0)) > 0:
		_body.add_child(
			_label(
				(
					"Ещё %d партий без победы/поражения: они не влияют на процент побед и график."
					% int(row.unrated)
				),
				HubStyle.MUTED,
				13
			)
		)
	_coins()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
