extends Control
## Окно статистики: победы друзей, мои любимые карты и рекорды (хранится на этом компьютере).


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := K12UI.panel(Color(0.08, 0.055, 0.035, 0.97), 8, "double")
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var col := K12UI.vbox(10)
	panel.add_child(col)
	col.add_child(K12UI.title("Статистика", K12UI.H1))
	var cfg := Prefs.stats()

	var me_games := int(cfg.get_value("me", "games", 0))
	var tricks := int(cfg.get_value("me", "tricks", 0))
	var won := int(cfg.get_value("me", "tricks_won", 0))
	col.add_child(K12UI.label("Вы сыграли партий: %d · розыгрышей: %d · выиграли розыгрышей: %d" % [me_games, tricks, won], K12UI.BODY))
	if cfg.has_section_key("me", "best_value"):
		col.add_child(K12UI.label("Рекорд значения кубика: %d (карта «%s»)" % [cfg.get_value("me", "best_value"), K12Cards.card_name(cfg.get_value("me", "best_value_card", K12Cards.KNIGHT))], K12UI.BODY))
	var cards: Dictionary = cfg.get_value("me", "cards", {})
	if not cards.is_empty():
		var keys := cards.keys()
		keys.sort_custom(func(a, b): return cards[a] > cards[b])
		var fav := K12UI.hbox(8)
		fav.add_child(K12UI.label("Любимые карты:", K12UI.BODY, K12UI.GOLD))
		for i in mini(3, keys.size()):
			var cv := K12CardView.new(keys[i], true)
			cv.tooltip_text = "Сыграна %d раз" % cards[keys[i]]
			fav.add_child(cv)
			fav.add_child(K12UI.label("×%d" % cards[keys[i]], K12UI.BODY))
		col.add_child(fav)

	col.add_child(K12UI.label("Игроки", K12UI.BODY, K12UI.GOLD))
	var players: Dictionary = cfg.get_value("players", "list", {})
	if players.is_empty():
		col.add_child(K12UI.label("Пока нет сыгранных партий.", K12UI.CAP, K12UI.MUTED))
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 24)
		for h in ["Игрок", "Партий", "Побед", "Раундов"]:
			grid.add_child(K12UI.label(h, K12UI.CAP, K12UI.MUTED))
		var names := players.keys()
		names.sort_custom(func(a, b): return players[a]["wins"] > players[b]["wins"])
		for nm in names:
			var row: Dictionary = players[nm]
			grid.add_child(K12UI.label(nm, K12UI.BODY, K12UI.MUTED if row.get("bot", false) else K12UI.CREAM))
			grid.add_child(K12UI.label(str(row["games"]), K12UI.BODY))
			grid.add_child(K12UI.label(str(row["wins"]), K12UI.BODY, K12UI.GOLD))
			grid.add_child(K12UI.label(str(row["rounds"]), K12UI.BODY))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, mini(260, 26 * (names.size() + 1)))
		scroll.add_child(grid)
		col.add_child(scroll)

	var close := K12UI.button("Закрыть", K12UI.BODY, 200)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	col.add_child(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
