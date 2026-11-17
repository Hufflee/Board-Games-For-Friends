extends SceneTree
## Проверка проекции, ответов и компонента руки Unmatched. Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_unmatched_hand.gd

const Hand := preload("res://games/unmatched/logic/um_hand.gd")
const CombatCards := preload("res://games/unmatched/logic/um_combat_cards.gd")
const Reveal := preload("res://hub/card_reveal.gd")
const Piles := preload("res://games/unmatched/logic/um_piles.gd")
var _checks := 0
var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var hands := [[_card("a1", "alice", 1), _card("a2", "alice", 1), _card("a3", "alice", 2)],
		[_card("m1", "medusa", 1)], [_card("y1", "yennenga", 3)], [_card("s1", "sinbad", 3)]]
	var controllers := PackedInt32Array([0, 1, 0, 2])
	var pending := {"id": 12, "hand": 0, "min": 0, "max": 1, "allowed": ["a1", "a2"],
		"prompt": "Выберите защиту", "pass_label": "Без защиты"}
	var heroes := PackedStringArray(["alice", "medusa", "yennenga", "sinbad"])
	var view := Hand.view_for(hands, controllers, 0, 0, pending, {}, heroes)
	_check(view.cards == hands[0] and view.owned == [0, 2] and view.counts == [3, 1, 1, 1], "Две свои руки, публичны только размеры остальных рук")
	var opponent := Hand.view_for(hands, controllers, 1, 0, pending)
	_check(opponent.cards.is_empty() and opponent.choice.is_empty(), "Запрос чужой руки не отдаёт карты и варианты")
	var reveals := {}
	Reveal.show(reveals, ["m1"], 0, 2.0)
	_check(Hand.view_for(hands, controllers, 0, 0, pending, reveals).shown == [hands[1][0]], "Карта показана адресату эффекта")
	_check(Hand.view_for(hands, controllers, -1, 0, pending, reveals).shown.is_empty(), "Зритель не видит частный показ")
	_check(Hand.accepts(hands, controllers, 0, pending, _answer(12, ["a2"])), "Хост различает одинаковые экземпляры")
	_check(Hand.accepts(hands, controllers, 0, pending, _answer(12, [])), "Допустимо отказаться от защиты")
	_check(not Hand.accepts(hands, controllers, 0, pending, _answer(11, ["a1"])), "Устаревший ответ отклонён")
	_check(not Hand.accepts(hands, controllers, 1, pending, _answer(12, ["a1"])), "Ответ не от контроллера отклонён")
	_check(not Hand.accepts(hands, controllers, 0, pending, _answer(12, ["m1"])), "Чужой экземпляр отклонён")
	_check(not Hand.accepts(hands, controllers, 0, pending, _answer(12, ["a3"])), "Неподходящая карта отклонена")
	var multi := {"id": 13, "hand": 0, "min": 2, "max": 2, "allowed": ["a1", "a2", "a3"]}
	_check(not Hand.accepts(hands, controllers, 0, multi, _answer(13, ["a1", "a1"])), "Нельзя выбрать экземпляр дважды")
	_check(Hand.accepts(hands, controllers, 0, multi, _answer(13, ["a2", "a1"])), "Можно выбрать два одинаковых лица")
	var battle := CombatCards.new(20, 0, 1, ["a1"], ["m1"])
	var defense := {"request": 21, "hand": 1, "cards": ["m1"]}
	_check(not battle.choose(hands, controllers, 1, defense), "Защиту нельзя подать до закрытой атаки")
	_check(battle.choose(hands, controllers, 0, _answer(20, ["a1"])) and battle.revealed().is_empty(), "Атака закрыта до защиты")
	var defending := Hand.view_for(hands, controllers, 1, 1, battle.pending())
	_check(not str(defending).contains("a1") and defending.choice.id == 21, "Вид защитника не содержит закрытую атаку")
	_check(battle.choose(hands, controllers, 1, defense), "Подходит карта защиты")
	_check(battle.revealed() == {"attack": hands[0][0], "defense": hands[1][0]}, "Лица раскрываются вместе после двух ответов")
	_check(not battle.choose(hands, controllers, 1, defense), "Повторный ответ после вскрытия отклонён")

	await _check_ui(hands, controllers, pending, view)
	await _check_piles()
	print("Unmatched hand: %d проверок, %d ошибок." % [_checks, _errors])
	quit(int(_errors != 0))


func _check_piles() -> void:
	var own := _card("own-discard", "alice", 1)
	var lower := _card("opponent-lower", "medusa", 2)
	var top := _card("opponent-top", "medusa", 1)
	var discards := [[own], [lower, top], []]
	var decks := [[_card("own-secret", "alice", 12)], [_card("opponent-next", "medusa", 22), _card("opponent-secret", "medusa", 18)], []]
	var heroes := PackedStringArray(["alice", "medusa", "yennenga"])
	var stacks := Piles.public_view(decks, discards, heroes)
	_check(stacks[0].deck_count == 1 and stacks[1].deck_count == 2 and stacks[2].deck_count == 0, "Открыты точные размеры колод, включая пустую")
	_check(stacks[1].deck == [{"hero": "medusa", "face": 18}, {"hero": "medusa", "face": 22}],
		"Состав колоды открыт по номерам изображений без ключей экземпляров")
	decks[1].reverse()
	_check(Piles.public_view(decks, discards, heroes) == stacks, "Публичный состав не зависит от порядка добора")
	decks[1].reverse()
	_check(stacks[0].discard == [own] and stacks[1].discard == [top, lower], "Оба сброса публичны, вершина первая")
	var script: GDScript = load("res://games/unmatched/ui/um_pile_view.gd")
	if not script.can_instantiate():
		_check(false, "Панель стопок компилируется")
		return
	var panel: Control = script.new()
	root.add_child(panel)
	panel.present(stacks)
	var shown: Array = []
	panel.preview_requested.connect(func(card: Dictionary): shown.append(card))
	_check(panel._rows.get_child_count() == 3 and panel._rows.get_child(1).get_child(1).text == "Колода 2", "На столе счётчик каждого героя")
	panel._rows.get_child(0).get_child(2).pressed.emit()
	_check(panel._browser.visible and panel._cards.get_child_count() == 1, "Открывается свой сброс")
	panel._rows.get_child(1).get_child(2).pressed.emit()
	_check(panel._cards.get_child_count() == 2, "Доступен весь сброс соперника")
	panel._cards.get_child(0).mouse_entered.emit()
	_check(shown == [top], "Наведение выдаёт верхнюю карту в общий просмотр")
	discards[1].pop_back()
	decks[1].pop_back()
	panel.present(Piles.public_view(decks, discards, heroes))
	_check(panel._browser.visible and panel._cards.get_child_count() == 1 and panel._rows.get_child(1).get_child(1).text == "Колода 1", "Открытая стопка и счётчик обновляются вместе")
	panel._rows.get_child(2).get_child(2).pressed.emit()
	_check(panel._empty.visible and not panel._scroll.visible, "У пустого сброса есть понятное состояние")
	panel._rows.get_child(0).get_child(1).pressed.emit()
	_check(panel._heading.text == "Колода · Алиса" and panel._cards.get_child_count() == 1, "Счётчик открывает свою колоду")
	panel._rows.get_child(1).get_child(1).pressed.emit()
	_check(panel._heading.text == "Колода · Медуза" and panel._cards.get_child_count() == 1, "Доступен просмотр колоды соперника")
	panel._cards.get_child(0).mouse_entered.emit()
	_check(shown.back() == {"hero": "medusa", "face": 22}, "Карта колоды направляется в крупный просмотр")
	decks[1].clear()
	panel.present(Piles.public_view(decks, discards, heroes))
	_check(panel._browser.visible and panel._empty.text == "Колода пуста" and panel._empty.visible, "Открытая колода обновляется при доборе последней карты")
	panel.queue_free()
	await process_frame


func _check_ui(hands: Array, controllers: PackedInt32Array, pending: Dictionary, view: Dictionary) -> void:
	var script: GDScript = load("res://games/unmatched/ui/um_hand_view.gd")
	if not script.can_instantiate():
		_check(false, "Компонент руки компилируется")
		return
	var ui: Control = script.new()
	root.size = Vector2i(1280, 720)
	root.add_child(ui)
	ui.dock_to_bottom()
	var sent: Array = []
	ui.submitted.connect(func(answer: Dictionary): sent.append(answer))
	ui.present(view)
	await process_frame
	if ui._fan.order.size() != 3:
		_check(false, "Загружены три текстуры руки")
		ui.queue_free()
		return
	_check(ui._confirm.text == "Без защиты" and ui._tabs.get_child_count() == 2, "Видны отказ от защиты и переключатель двух рук")
	_check(ui._tabs.get_child(0).icon != null, "Переключатель показывает портрет")
	var first: Control = ui._fan._cards["a1"]
	ui._fan._dropped(first, Vector2(ui._fan.size.x, 40))
	ui.present(Hand.view_for(hands, controllers, 0, 0, pending))
	_check(ui._fan.order == ["a2", "a3", "a1"] and ui._fan._cards["a1"] == first, "Перестановка и узел карты переживают новое состояние")
	ui._fan.chosen.emit({"key": "a3"})
	_check(ui._picked.is_empty(), "Недоступная карта не выбирается")
	ui._fan.chosen.emit({"key": "a2"})
	ui._confirm.pressed.emit()
	ui._confirm.pressed.emit()
	_check(sent == [_answer(12, ["a2"])], "Двойное подтверждение отправляет один ответ")
	ui.unlock()
	ui.drop_zone = Rect2(400, 200, 300, 200)
	_check(ui._drop({"key": "a1"}, Vector2(500, 300)) and sent.back() == _answer(12, ["a1"]), "Сброс в зоне боя подтверждает подходящую карту")
	ui.hide_for_handoff("Медуза")
	_check(ui._fan.order.is_empty() and ui._curtain.visible and not ui._preview.visible, "Перед передачей скрыты карта и просмотр")
	ui.present(Hand.view_for(hands, controllers, 1, 1, pending))
	_check(ui._fan.order.is_empty() and ui._curtain.visible, "Обновление состояния не раскрывает руку под экраном передачи")
	ui._curtain.pressed.emit()
	ui.present(Hand.view_for(hands, controllers, 1, 1, pending))
	_check(ui._fan.order == ["m1"] and not ui._curtain.visible, "После передачи доступна только новая рука")
	for i in range(3, 10):
		hands[0].append(_card("a%d" % (i + 1), "alice", i + 1))
	ui.present(Hand.view_for(hands, controllers, 0, 0, {}))
	await process_frame
	var left: Control = ui._fan._cards[ui._fan.order.front()]
	var right: Control = ui._fan._cards[ui._fan.order.back()]
	_check(ui._fan.order.size() == 10 and left.get_global_rect().position.x >= 0.0 and right.get_global_rect().end.x <= 1280.0,
		"Десять карт помещаются по ширине в 1280×720")
	var shown: float = (720.0 - right.get_global_rect().position.y) / ui._fan.card_size.y
	_check(shown >= 0.73 and shown <= 0.81 and right.get_global_rect().end.y > 720.0,
		"У нижнего края видно около трёх четвертей крупной карты")
	if OS.get_environment("UM_HAND_SHOTS") == "1" and DisplayServer.get_name() != "headless":
		await _take_shots(ui, hands, controllers)
	_check_sorting(ui)
	ui.queue_free()


func _check_sorting(ui: Control) -> void:
	var catalog := preload("res://games/unmatched/logic/um_catalog.gd")
	var deck := catalog.deck_for("arthur", 0)
	var cards := [deck[15], deck[19], deck[28], deck[18], deck[1], deck[26], deck[0], deck[13]]
	var expected := ["0:01", "0:27", "0:29", "0:14", "0:19", "0:02", "0:20", "0:16"]
	ui.present({"hand": 0, "cards": cards})
	_check(ui._fan.order == expected, "Начальная рука сортируется по типу, бойцу и убыванию печатного значения")
	var manual := ["0:16", "0:01", "0:20", "0:29"]
	ui._fan.order_changed.emit(manual)
	ui.present({"hand": 0, "cards": [deck[0], deck[19], deck[28], deck[15], deck[26]]})
	_check(ui._fan.order == ["0:16", "0:01", "0:27", "0:20", "0:29"],
		"Добор помещает новую карту в подходящий промежуток и сохраняет ручной порядок")
	ui._fan.order_changed.emit(["0:01", "0:27", "0:29", "0:20", "0:16"])
	ui.present({"hand": 0, "cards": [deck[0], deck[19], deck[28], deck[15], deck[26], deck[29]]})
	_check(ui._fan.order == ["0:01", "0:27", "0:29", "0:30", "0:20", "0:16"],
		"При равных значениях новая копия в отсортированной руке идёт после уже лежащей")


func _take_shots(ui: Control, hands: Array, controllers: PackedInt32Array) -> void:
	var path := ProjectSettings.globalize_path("res://build/shots/unmatched_hand")
	DirAccess.make_dir_recursive_absolute(path)
	var choice := {"id": 30, "hand": 0, "min": 2, "max": 2, "allowed": ["a1", "a2", "a4"], "prompt": "Сбросьте 2 карты"}
	ui.present(Hand.view_for(hands, controllers, 0, 0, choice, {}, ["alice", "medusa", "yennenga", "sinbad"]))
	ui._fan.chosen.emit({"key": "a1"})
	var entry: Dictionary = ui._fan._cards["a2"].get_meta("hand_entry")
	for mode in ["light", "dark"]:
		var dark: bool = mode == "dark"
		var theme := Theme.new()
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color("263038") if dark else Color("ede1cb")
		panel.content_margin_top = 8.0
		panel.content_margin_bottom = 8.0
		panel.content_margin_left = 8.0
		panel.content_margin_right = 8.0
		theme.set_stylebox("panel", "PanelContainer", panel)
		theme.set_color("font_color", "Label", Color("ebdfcf") if dark else Color("22242a"))
		ui.theme = theme
		RenderingServer.set_default_clear_color(Color("1b2228") if dark else Color("f1eadc"))
		ui._open_preview(entry)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_check(image.save_png(path.path_join(mode + ".png")) == OK, "Сохранён снимок при 1280×720: %s" % mode)


func _card(key: String, hero: String, face: int) -> Dictionary:
	return {"key": key, "hero": hero, "face": face}


func _answer(id: int, cards: Array) -> Dictionary:
	return {"request": id, "hand": 0, "cards": cards}


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_errors += 1
		push_error(message)
