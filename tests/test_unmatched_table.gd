extends SceneTree
## Стол Unmatched: рука, закрытый бой, сброс, поле и тема. Для кадров — UM_TABLE_SHOTS=1 и запуск в окне.

const Piles := preload("res://games/unmatched/logic/um_piles.gd")
const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Match := preload("res://games/unmatched/logic/um_match.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
var _checks := 0
var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://games/unmatched/ui/table.tscn")
	if packed == null or not packed.can_instantiate():
		quit(1)
		return
	var table: Control = packed.instantiate()
	root.add_child(table)
	table.wire_party_menu()
	if table.get("_board") == null:
		quit(1)
		return
	var prefs := root.get_node("Prefs")
	prefs.theme_mode = "light"
	var state := _example()
	table.present(state)
	await _frames()
	_check(table._board._board != null and table._board._figures.size() == 6, "Оригинальное поле и шесть фишек на столе")
	_check(not table._board.get_parent() is PanelContainer and not table._opponents is PanelContainer, "Поле и рубашки лежат на фоне без панелей")
	_check(table._hand._fan.order.size() == 7 and table._opponent_cards.get_child_count() == 5, "Своя рука и рубашки противника")
	var first: Control = table._hand._fan._cards[table._hand._fan.order.front()]
	_check(first.get_global_rect().position.x >= table._opponents.get_global_rect().end.x, "Своя рука не закрывает рубашки соперника")
	var alice_back: Texture2D = table._back_for("alice")
	_check(alice_back != table._card_back and table._attack.texture == alice_back and table._defense.texture == null, "Закрытая атака показывает оригинальную рубашку Алисы")
	_check(table._opponent_cards.get_child(0).texture == alice_back, "В руке соперника рубашки его героя")
	var unique_backs := {}
	for hero: String in Roster.HEROES:
		var texture := Art.back(hero)
		if texture != null:
			unique_backs[FileAccess.get_sha256("res://games/unmatched/art/backs/%s.webp" % hero)] = true
	_check(unique_backs.size() == Roster.HEROES.size(), "Все герои имеют разные читаемые рубашки")
	var preview_material: ShaderMaterial = table._preview.material
	var back_material: ShaderMaterial = table._attack.material
	_check(preview_material.shader == back_material.shader and float(preview_material.get_shader_parameter("outline_width")) == 0.0, "Крупный просмотр сохраняет сглаживание без контура")
	_check(back_material.get_shader_parameter("outline_width") == 1.5 and table._opponent_cards.get_child(0).material == back_material, "Контур есть у закрытых карт боя и руки")
	_check(table._board.outline_color == table._colors.rim and table._board._field_rect().position.y >= 1.99, "У поля есть цвет и место под обводку")
	var bar: StyleBoxFlat = table._top.get_theme_stylebox("panel")
	var stone: StyleBoxFlat = table._top.get_theme_stylebox("normal", "Button")
	_check(bar.bg_color.a == 0.0 and stone.border_width_bottom == 2 and stone.border_width_left == 0,
		"Верхняя полоса прозрачна, кнопки имеют латунную кромку снизу")
	table._attack.get_parent().mouse_entered.emit()
	_check(table._preview.texture == null, "Вначале нет приватного просмотра")
	var entry: Dictionary = table._hand._fan._cards["m-1"].get_meta("hand_entry")
	table._hand._fan._on_hover(table._hand._fan._cards["m-1"], true, entry)
	_check(table._preview.texture == entry.texture and not table._hand._preview.visible,
		"Наведение из руки открывает просмотр сразу, без ожидания кадра или таймера")
	table._hand._close_preview()
	_check(table._preview.texture == null, "Просмотр закрывается")
	var submitted: Array = []
	table.submitted.connect(func(answer: Dictionary): submitted.append(answer))
	table._reply.pressed.emit()
	_check(submitted == [{"request": 7, "hand": 1, "cards": []}], "Отказ от защиты отправляет заявку из стола")
	var pile_button: Button = table._piles._rows.get_child(0).get_child(2)
	var small_font := pile_button.get_theme_font("font") as FontVariation
	var weight := TextServerManager.get_primary_interface().name_to_tag("wght")
	_check(small_font != null and small_font.base_font.resource_path.ends_with("/Nunito-Variable.ttf")
		and small_font.variation_opentype.get(weight, 0) == 600 and table._top._chat_btn.get_theme_font("font") == small_font,
		"Сброс и Общение используют один мелкий шрифт Nunito")
	pile_button.pressed.emit()
	await _frames()
	table._piles._cards.get_child(0).mouse_entered.emit()
	_check(table._preview.texture != null and table._piles._browser.visible, "Сброс направляет лицо в панель, список остаётся открыт")
	_check(table._piles._browser.get_global_rect().end.x < table._preview_column.get_global_rect().position.x + 12, "Сброс оставляет увеличенную карту открытой")
	table._piles._close()
	var capture := OS.get_environment("UM_TABLE_SHOTS") == "1" and DisplayServer.get_name() != "headless"
	table._piles._rows.get_child(0).get_child(1).pressed.emit()
	await _frames()
	_check(table._piles._cards.get_child_count() == 24 and table._piles._scroll.get_v_scroll_bar().visible,
		"Колода открывается с прокруткой всех оставшихся карт")
	if capture:
		table._piles._cards.get_child(0).mouse_entered.emit()
		await _shot("deck_light")
	table._piles._close()
	table._board.zoom_by(4.0, table._board.size * 0.5)
	_check(table._board._zoom == 3.0, "Поле увеличивается до установленного предела")
	table._board.zoom_by(0.2, table._board.size * 0.5)
	_check(table._board._zoom == 1.0 and table._board._offset == Vector2.ZERO, "Уменьшение возвращает поле целиком")
	var chosen: Array = []
	table.target_pressed.connect(func(cell: int): chosen.append(cell))
	var field: Rect2 = table._board._field_rect()
	table._board._pick(field.position + state.targets[5] * field.size)
	_check(chosen == [5], "Клик по видимой цели отправляет номер клетки")
	_check(table._hand.drop_zone.size.x > 0.0 and table._fight_frame.get_global_rect().end.x <= 1280.0, "Стол и зона сброса помещаются в 1280×720")
	table._top.toggle_menu()
	await _frames()
	var options: Array = Array(table._top.actions.get_children()).filter(func(item): return item is Button and item.text == "Настройки")
	_check(options.size() == 1, "На верхней полосе есть кнопка настроек")
	var top_button: Button = table._top._chat_btn
	_check(is_equal_approx(top_button.size.y, table._top._esc_btn.size.y)
		and table._top._esc_btn.alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"Tab центрирован и совпадает по высоте с соседней кнопкой (%.1f / %.1f)" % [top_button.size.y, table._top._esc_btn.size.y])
	_check(is_equal_approx(table._arena_title.get_global_rect().get_center().x, table._board.get_global_rect().get_center().x),
		"Название арены расположено по центру поля")
	if capture:
		await create_timer(0.3).timeout
		table._hand._open_preview(entry)
		await _shot("marmoreal_light")
	await _check_info(table, false, capture)
	prefs.theme_mode = "dark"
	state.arena = "sarpedon"
	state.targets = {5: _point(378, 188)}
	var centers := [_point(220, 195), _point(294, 175), _point(77, 278), _point(448, 157), _point(401, 94), _point(325, 264)]
	for i in state.fighters.size():
		state.fighters[i].at = centers[i]
	table.present(state)
	await _frames()
	_check(table._arena == "sarpedon" and table._dark and table._backdrop.texture != null, "Смена арены и темы меняет поле и фон")
	if capture:
		table._hand._open_preview(entry)
		await _shot("sarpedon_dark")
		table._piles._rows.get_child(1).get_child(1).pressed.emit()
		await _frames()
		table._piles._cards.get_child(0).mouse_entered.emit()
		await _shot("deck_dark")
		table._piles._close()
	await _check_info(table, true, capture)
	var scheme := Catalog.deck_for("alice", 0)[10]
	table._show_scheme({"id": 1, "card": scheme})
	await _frames()
	if capture:
		await _shot("scheme_center")
	await create_timer(1.40).timeout
	_check(_same_texture(table._preview.texture, Art.face(scheme)) and table._preview_source == "scheme",
		"Приём перелетает из центра в слот просмотра")
	await _check_reported(table, capture)
	await _check_actions_and_combat(table, capture)
	await _check_helmet(table, capture)
	await _check_hand_discard(table)
	await _check_summon(table, capture)
	table.queue_free()
	await process_frame
	print("Unmatched table: %d проверок, %d ошибок." % [_checks, _errors])
	quit(int(_errors > 0))


func _check_reported(table: Control, capture: bool) -> void:
	var session: RefCounted = Match.create("marmoreal", ["pandora", "bloody_mary"], [{"name": "А"}, {"name": "Б"}], 6)
	session.rules.clear_choices()
	session.rules._turn_spaces.clear()
	session.rules.miseries.clear()
	session.rules.misery_pile = [2, 4]
	session.rules.phase = 0
	session.rules.start_turn()
	var state: Dictionary = session.get_view(0)
	table.present(state)
	await _frames()
	_check(_same_texture(table._preview.texture, Art.face(session.rules.misery_card(2))),
		"Надежда показывает Боль, а не перезаписывает её изображением Надежды")
	_check(state.active_miseries.size() == 1 and state.active_miseries[0].key == "misery:4"
		and table._miseries_button.visible, "Активные бедствия не содержат подсмотренную закрытую карту")
	table._set_preview(Art.face(Catalog.deck_for("loki", 0)[0]), "hand")
	table._miseries_button.pressed.emit()
	await _frames()
	_check(table._piles._cards.get_child_count() == 1 and table._piles._heading.text == "Активные бедствия этого хода",
		"Бедствия доступны отдельной кнопкой после просмотра другой карты")
	if capture:
		await _shot("active_miseries_dark")
	table._piles._close()
	var peek: Button = table._actions.get_child(0)
	peek.pressed.emit()
	_check(_same_texture(table._preview.texture, Art.face(session.rules.misery_card(2))), "Кнопка возвращает просмотр следующего бедствия Надежды")
	if capture:
		await _shot("hope_dark")
		root.get_node("Prefs").theme_mode = "light"
		table.present(state)
		await _frames()
		await _shot("hope_light")
		root.get_node("Prefs").theme_mode = "dark"
		table.present(state)
	var replies: Array = []
	var receive := func(kind: String, argument: Dictionary): replies.append([kind, argument])
	table.action_requested.connect(receive)
	for word: String in ["reflect", "draw", "discard", "reveal", "use", "pay", "strength", "item_first", "item_last", "confirm"]:
		state.effect = {"id": 840, "seat": 0, "options": [word], "optional": true, "prompt": "Проверка эффекта"}
		table.present(state)
		await _frames()
		var options: OptionButton = table._actions.get_child(0)
		_check(not options.get_item_text(0).is_empty() and options.get_item_text(0) != "<null>", "Непустая подпись варианта %s" % word)
		(table._actions.get_child(1) as Button).pressed.emit()
		_check(replies.back()[1].answer == word, "Кнопка отправляет выбранный вариант %s" % word)
	state.effect = {"id": 841, "seat": 0, "options": [1], "optional": true, "cells": true,
		"prompt": "Размещение помощника · выберите подсвеченную клетку"}
	table.present(state)
	await _frames()
	var skip: Button = table._actions.get_child(1)
	_check(skip.global_position.x < table._action_slot.global_position.x + 370
		and skip.get_global_rect().end.x < table._fight_frame.global_position.x, "Пропустить находится слева рядом с подсказкой")
	skip.pressed.emit()
	_check(replies.back()[1].answer == null and replies.back()[1].request == 841, "Пропуск отправляет null только как ответ, а не подпись")
	table.action_requested.disconnect(receive)
	state.active_miseries = []
	table.present(state)
	_check(not table._miseries_button.visible, "После завершения хода список активных бедствий очищается")
	session.close()


func _check_actions_and_combat(table: Control, capture: bool) -> void:
	var match_game: RefCounted = Match.create("marmoreal", ["bloody_mary", "sun_wukong"], [{"name": "А"}, {"name": "Б"}], 14)
	var game: RefCounted = match_game.game
	game.fighters[0][0].space = 4
	game.fighters[1][0].space = 5
	var attack := Catalog.deck_for("bloody_mary", 0)[4]
	var defense := Catalog.deck_for("sun_wukong", 1)[18]
	game.hands[0] = [attack]
	game.hands[1] = [defense]
	table.present(match_game.get_view(0))
	await _frames()
	_check(table._selection_label.text == "Кровавая Мэри · герой"
		and table._board._figures[1].attackable, "Выбранный герой подписан, противник в радиусе выделен красным")
	table._board_clicked(4)
	_check(table._maneuver_preview and game.hands[0].size() == 1 and game.decks[0].size() == 25,
		"Клик по своему бойцу показывает манёвр без добора")
	game.hands[0] = Catalog.deck_for("bloody_mary", 0).slice(0, 10)
	table.present(match_game.get_view(0))
	await _frames()
	var cancel: Button = table._actions.get_child(1)
	var corner := cancel.get_global_rect().end - Vector2(5, 4)
	_click_at(corner)
	_check(not table._maneuver_preview and game.decks[0].size() == 25, "Нижний угол кнопки над веером отменяет манёвр без добора")
	game.hands[0] = [attack]
	table.present(match_game.get_view(0))
	table._board.character_hovered.emit("bloody_mary")
	_check(table._preview.texture != null and table._preview_source == "character", "Наведение открывает оригинальную карту героя")
	_check(Art.reference_face("actions") != null, "Оригинальная памятка доступна")
	var interactions: Array = []
	table.action_requested.connect(func(kind: String, argument: Dictionary): interactions.append([kind, argument]))
	var field: Rect2 = table._board._field_rect()
	var target_position: Vector2 = field.position + (match_game.get_view(0).positions[5] as Vector2) * field.size
	_click_at(table._board.get_global_transform_with_canvas() * target_position)
	_check(interactions.size() == 1 and interactions[0][0] == "attack"
		and interactions[0][1] == {"fighter": 0, "target": Vector2i(1, 0), "key": ""},
		"Клик по красной фишке объявляет атаку без заранее выбранной карты")
	var click_attack: Dictionary = interactions[0][1] if interactions.size() == 1 else {}
	interactions.clear()
	table._hand._fan.drag_began.emit({"key": attack.key})
	_check(table._board.drop_highlight, "На поле зелёный индикатор при захвате допустимой карты")
	table._hand._drop({"key": attack.key}, table._board.get_global_transform_with_canvas() * field.get_center())
	table._hand._fan.drag_ended.emit()
	_check(not table._board.drop_highlight and table._staged_attack == attack.key, "Сброс на поле готовит атаку к выбору цели")
	table._board_clicked(5)
	_check(interactions.size() == 1 and interactions[0][0] == "attack" and interactions[0][1].key == attack.key, "Клик по красной цели отправляет выбранную карту")
	match_game.act(0, "attack", click_attack)
	var attack_request: Dictionary = match_game.get_view(0).hand.choice
	_check(not attack_request.is_empty(), "После клика хост предлагает атакующему выбрать карту")
	match_game.act(0, "combat", {"request": attack_request.get("id", -1), "hand": 0, "cards": [attack.key]})
	var request: Dictionary = match_game.get_view(1).hand.choice
	match_game.act(1, "combat", {"request": request.id, "hand": 1, "cards": [defense.key]})
	var revealed: Dictionary = match_game.get_view(0)
	table.present(revealed)
	_check(table._combat_show.visible and _same_texture(table._combat_show._attack.texture, Art.back("bloody_mary"))
		and _same_texture(table._combat_show._defense.texture, Art.back("sun_wukong")), "Обе карты летят в центр рубашками вверх")
	await create_timer(0.51).timeout
	_check(_same_texture(table._combat_show._attack.texture, Art.face(attack))
		and _same_texture(table._combat_show._defense.texture, Art.back("sun_wukong")), "Атака переворачивается раньше защиты")
	await create_timer(0.40).timeout
	_check(_same_texture(table._combat_show._defense.texture, Art.face(defense)), "После атаки переворачивается защита")
	var visual_span: float = table._combat_show._defense.position.x + table._combat_show._defense.size.x - table._combat_show._attack.position.x
	_check(absf(visual_span / table.size.x - 0.60) < 0.035 and table._combat_show._shade.modulate.a > 0.9,
		"Карты занимают около 60% ширины и фон затемнён")
	_check(table._combat_show._defense.get_global_rect().end.x < table._preview_column.global_position.x,
		"Открытая защита не перекрывает просмотр карты")
	if capture:
		await _shot("combat_reveal")
	match_game.tick(Match.REVEAL_SECONDS)
	table.present(match_game.get_view(0))
	await create_timer(0.55).timeout
	_check(not table._combat_show._impact_started, "После раскрытия игрок успевает прочитать карты")
	var deadline := Time.get_ticks_msec() + 4400
	while Time.get_ticks_msec() < deadline and not table._combat_show._note.visible:
		await process_frame
	await create_timer(0.28).timeout
	_check(table._combat_show._note.text == "Защита выдержала" and table._combat_show._attack.modulate.a < 0.3,
		"При блоке карта атаки отскакивает и рассеивается")
	var hit := revealed.duplicate(true)
	hit.combat.id = 2
	hit.combat.attack = Catalog.deck_for("bloody_mary", 0)[2]
	var modified := [hit.combat.attack.value + 2, maxi(0, defense.value - 1)]
	hit.combat.during = [{"side": 0, "message": "Сброшена 1 карта", "values": modified}]
	hit.combat_outcome = {"id": 2, "hit": true, "losses": [{"name": "Сунь Укун", "amount": 2}], "values": modified}
	table.present(hit)
	deadline = Time.get_ticks_msec() + 6200
	while Time.get_ticks_msec() < deadline:
		if table._combat_show._current == 2 and table._combat_show._note.visible:
			break
		await process_frame
	_check(table._combat_show._note.text == "Сброшена 1 карта" and not table._combat_show._impact_started,
		"Сначала эффект карты и его индикатор, без столкновения")
	var labels: Array = table._combat_show._value_labels
	_check(labels[0].text == str(modified[0]) and labels[0].get_theme_color("font_color") == Color("94ff9e")
		and labels[1].text == str(modified[1]) and labels[1].get_theme_color("font_color") == Color("ff8a89"),
		"На картах видны изменённые значения: усиление зелёным, снижение красным")
	if capture:
		await _shot("combat_during")
	await create_timer(2.40).timeout
	_check(not table._combat_show._impact_started, "Перед столкновением выдерживается пауза после эффекта")
	deadline = Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < deadline and not table._combat_show._impact_started:
		await process_frame
	await create_timer(0.23).timeout
	await create_timer(0.29).timeout
	_check(table._combat_show._note.text == "Сунь Укун  −2 ОЗ" and table._combat_show._defense.modulate.a < 0.25,
		"Попадание разрушает защиту и показывает потерянные ОЗ")
	if capture:
		await _shot("combat_hit")
	match_game.close()


func _same_texture(first: Texture2D, second: Texture2D) -> bool:
	return first != null and second != null and first.get_image().get_data() == second.get_image().get_data()


func _check_info(table: Control, journal: bool, capture: bool) -> void:
	var popup: PopupPanel
	if journal:
		table._state["journal"] = ["Медуза выполняет манёвр.", "Меткий выстрел / В шлеме Ахиллеса · боевой урон: 1."]
		popup = table._show_journal()
	else:
		popup = table._show_rules()
	await _frames()
	_check(is_instance_valid(popup) and popup.visible and popup.get_theme_stylebox("panel") is StyleBoxTexture
		and popup.theme == table.theme and popup.size.y < root.size.y, "Окно оформлено в палитре арены и помещается в экран")
	if is_instance_valid(popup):
		if capture:
			await _shot("journal_dark" if journal else "rules_light")
		popup.hide()
	await _frames()


func _check_helmet(table: Control, capture: bool) -> void:
	await _await_combat_end(table)
	var session: RefCounted = Match.create("marmoreal", ["medusa", "achilles"], [{"name": "А"}, {"name": "Б"}], 7)
	session.rules._combat_serial = 2
	while not session.game.pending().is_empty():
		var setup: Dictionary = session.game.pending()
		if not session.act(setup.seat, "place", {"cell": setup.cells[0]}):
			_check(false, "Расстановка для проверки шлема")
			return
	session.game.fighters[0][0].space = 4
	session.game.fighters[1][0].space = 5
	session.game.fighters[1][1].space = 6
	var attack := Catalog.deck_for("medusa", 0)[0]
	var helmet := Catalog.deck_for("achilles", 1)[22]
	session.game.hands[0] = [attack]
	session.game.hands[1] = [helmet]
	session.act(0, "attack", {"fighter": 0, "target": Vector2i(1, 0), "key": attack.key})
	var choice: Dictionary = session.get_view(1).hand.choice
	session.act(1, "combat", {"request": choice.get("id", -1), "hand": 1, "cards": [helmet.key]})
	table.present(session.get_view(1))
	await create_timer(Match.REVEAL_SECONDS).timeout
	session.tick(Match.REVEAL_SECONDS)
	var view: Dictionary = session.get_view(1)
	table.present(view)
	_check(view.effect.is_empty() and view.combat.get("immediate", {}).get("side") == 1,
		"До выбора хост показывает немедленный эффект защиты")
	await create_timer(0.40).timeout
	_check(table._combat_show._playing_immediate and table._combat_show._note.visible,
		"Печатный блок шлема подсвечен с индикатором")
	session.tick(0.95)
	table.present(session.get_view(1))
	session.tick(0.28)
	view = session.get_view(1)
	table.present(view)
	await create_timer(0.88).timeout
	_check(table._combat_show._attack.scale.x < 0.5 and table._combat_show._shade.modulate.a < 0.1,
		"При выборе Патрокла карты уменьшены и поле освещено")
	_check(table._attack.texture == null and table._defense.texture == null, "Под анимированными картами нет статических дубликатов")
	_check(table._combat_show._attack.get_global_rect().get_center().distance_to(table._attack.get_global_rect().get_center()) < 2.0
		and table._combat_show._defense.get_global_rect().get_center().distance_to(table._defense.get_global_rect().get_center()) < 2.0,
		"Уменьшенные карты занимают ячейки Атака и Защита")
	table._attack.get_parent().mouse_entered.emit()
	_check(table._preview.texture != null, "Наведение на перемещённую карту открывает большой просмотр")
	_check(view.effect.get("options", []) == [Vector2i(1, 1)] and table._actions.get_child_count() == 2,
		"Шлем предлагает Патрокла на поле и кнопку пропуска")
	if capture:
		await _shot("helmet_choice")
	var choose := func(kind: String, answer: Dictionary):
		if kind == "effect":
			session.act(1, kind, answer)
	table.action_requested.connect(choose)
	var field: Rect2 = table._board._field_rect()
	_click_at(table._board.get_global_transform_with_canvas() * (field.position + (view.positions[6] as Vector2) * field.size))
	table.action_requested.disconnect(choose)
	table.present(session.get_view(1))
	_check(session.game.fighters[1][0].space == 6 and session.game.fighters[1][1].space == 5,
		"Клик по Патроклу меняет бойцов местами")
	session.tick(1.20)
	table.present(session.get_view(1))
	await create_timer(0.38).timeout
	_check(not table._combat_show._compact and table._combat_show._attack.scale.x > 0.95,
		"Карты возвращаются к обычному размеру перед столкновением")
	session.close()


func _check_hand_discard(table: Control) -> void:
	await _await_combat_end(table)
	var session: RefCounted = Match.create("marmoreal", ["achilles", "medusa"], [{"name": "А"}, {"name": "Б"}], 9)
	session.rules._combat_serial = 3
	while not session.game.pending().is_empty():
		var setup: Dictionary = session.game.pending()
		if not session.act(setup.seat, "place", {"cell": setup.cells[0]}):
			_check(false, "Расстановка для проверки сброса")
			return
	session.game.fighters[0][0].space = 4
	session.game.fighters[1][1].space = 5
	var attack := Catalog.deck_for("achilles", 0)[7]
	var discard := Catalog.deck_for("achilles", 0)[22]
	var grip := Catalog.deck_for("medusa", 1)[14]
	session.game.hands[0] = [attack, discard]
	session.game.hands[1] = [grip]
	session.act(0, "attack", {"fighter": 0, "target": Vector2i(1, 1), "key": attack.key})
	var choice: Dictionary = session.get_view(1).hand.choice
	session.act(1, "combat", {"request": choice.get("id", -1), "hand": 1, "cards": [grip.key]})
	session.tick(Match.REVEAL_SECONDS)
	session.tick(1.45)
	session.tick(0.28)
	var view: Dictionary = session.get_view(0)
	table.present(view)
	await _frames()
	_check(view.effect.get("hand_discard", false) and table._hand._prompt.visible
		and table._hand._prompt.text == "Сбросьте карту" and not table._actions.visible,
		"Мёртвая хватка показывает подсказку над рукой без выпадающего списка")
	var submit := func(kind: String, answer: Dictionary):
		if kind == "effect":
			session.act(0, kind, answer)
	table.action_requested.connect(submit)
	table._hand._fan.drag_began.emit({"key": discard.key})
	_check(table._board.drop_highlight, "Поле подсвечивается при переносе карты для сброса")
	table._hand._drop({"key": discard.key}, table._hand.drop_zone.get_center())
	table._hand._fan.drag_ended.emit()
	table.action_requested.disconnect(submit)
	_check(discard in session.game.discards[0] and discard not in session.game.hands[0], "Перенос в центр поля сбрасывает ровно выбранную карту")
	session.tick(1.20)
	table.present(session.get_view(0))
	session.close()


func _check_summon(table: Control, capture: bool) -> void:
	await _await_combat_end(table)
	table._board.character_hovered.emit("")
	var match_game: RefCounted = Match.create("gardens", ["sun_wukong", "bloody_mary"], [{"name": "А"}, {"name": "Б"}], 12)
	var view: Dictionary = match_game.get_view(0)
	table.present(view)
	await _frames()
	var hint := table._actions.get_child(0) as Label
	_check(hint != null and "размещение двойника" in hint.text, "Призыв подписан прямо под полем")
	_check(table._actions.get_child_count() == 2 and table._actions.get_child(1).text == "Пропустить",
		"Для призыва нет списка номеров, доступен только пропуск")
	_check(table._target_cells.size() == 4 and view.fighters.size() == 2, "Первый ход начинается без двойников и с выбором четырёх клеток")
	if capture:
		await _shot("gardens_summon")
	table.action_requested.connect(func(kind: String, args: Dictionary): match_game.act(0, kind, args), CONNECT_ONE_SHOT)
	var cell: int = view.effect.options[0]
	table._board_clicked(cell)
	_check(match_game.game.fighters[0][0].health == 16 and match_game.game.fighters[0][1].space == cell,
		"Клик по полю призывает двойника за 1 ОЗ")
	match_game.close()


func _await_combat_end(table: Control) -> void:
	var show: Control = table._combat_show
	var deadline := Time.get_ticks_msec() + 6500
	while show.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not show.visible, "Показ боя завершается (бой %d, проекция %d, столкновение %s, ответы %s)" %
		[show._current, show._view_id, show._impact_started, show._outcomes.keys()])


func _click_at(at: Vector2) -> void:
	var hover := InputEventMouseMotion.new()
	hover.position = at
	hover.global_position = at
	root.push_input(hover, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = at
		click.global_position = at
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)


func _frames() -> void:
	for i in 8:
		await process_frame


func _example() -> Dictionary:
	var cards: Array = []
	for i in 7:
		cards.append({"key": "m-%d" % (i + 1), "hero": "medusa", "face": i + 1})
	var discards := [[{"key": "a-old", "hero": "alice", "face": 3}], [{"key": "m-old", "hero": "medusa", "face": 22}]]
	var decks := [Catalog.deck_for("alice", 0).slice(0, 24), Catalog.deck_for("medusa", 1).slice(0, 22)]
	var phase := {"id": 7, "allowed": ["m-1", "m-4"], "min": 0, "max": 1,
		"prompt": "Выберите карту защиты", "pass_label": "Без защиты"}
	var hand := {"hand": 1, "cards": cards, "choice": phase, "owned": [1], "counts": [5, 7]}
	var figures := []
	for item: Array in [["alice", 0, 10, _point(492, 191)], ["medusa", 1, 12, _point(584, 184)],
		["jabberwock", 0, 7, _point(398, 215)], ["harpy", 1, 1, _point(548, 253)],
		["harpy", 1, 1, _point(673, 237)], ["harpy", 1, 1, _point(460, 280)]]:
		figures.append({"token": item[0], "seat": item[1], "hp": item[2], "at": item[3], "hero": item[2] >= 10, "selected": item[2] >= 10})
	return {"arena": "marmoreal", "phase_title": "Защита Медузы", "step": "Ход 3 · действие 2 из 2",
		"hand": hand, "combat": {"attack": {"sealed": true}, "attack_hero": "alice", "attack_name": "Алиса", "defense_name": "Медуза"}, "fighters": figures,
		"targets": {5: _point(585, 185)}, "piles": Piles.public_view(decks, discards, PackedStringArray(["alice", "medusa"]))}


func _point(x: int, y: int) -> Vector2:
	return Vector2((x - 39) / 714.0, (y - 48) / 464.0)


func _shot(name: String) -> void:
	var path := ProjectSettings.globalize_path("res://build/shots/unmatched_table")
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(path.path_join(name + ".png")) == OK, "Сохранён кадр стола %s" % name)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_errors += 1
		push_error(message)
