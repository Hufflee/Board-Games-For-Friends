extends Control
## Стол Four Souls: закрытая рука, открытые карты, приоритет и ручная панель эффектов.
const HealthBar := preload("res://games/four_souls/ui/fs_health.gd")
var app: Node
var _v: Dictionary = {}
var _body: VBoxContainer
var _top: TopBar
var _die: TossDie
var _preview: TextureRect
var _unlocked := -2
var _last_roll := -1
# Не отправляем второй запрос, пока хост не подтвердил изменение состояния.
var _roll_request_revision := -1
var _popup: Control
var _preview_token := 0
var _play_zone: PanelContainer
var _play_note: Label
var _drag_entry: Dictionary = {}
static var _hand_orders: Dictionary = {}
const EXTRA_OPS := [
	["extra_turn", "Дополнительный ход выбранному игроку"],
	["self_underdeck", "Эту карту лута — под низ колоды"],
	["give_item", "Передать свой предмет выбранному игроку"],
	["peek_hand", "Посмотреть руку выбранного игрока"],
	["peek_hands", "Посмотреть руки всех игроков"],
	["prevent_damage", "Предотвратить следующий урон в этом ходу"]
]
const OPS := [["coins","Монеты ±"],["loot","Взять лут"],["treasure","Получить сокровища"],["damage","Нанести урон игроку"],["heal","Восстановить здоровье"],["souls","Души ±"],["steal_soul","Украсть карту души"],["attach_curse","Передать проклятие"],["attack","Сила атаки ±"],["temporary_attack","Атака до конца хода ±"],["extra_attack","Дополнительные атаки"],["extra_buy","Дополнительные покупки"],["extra_loot","Дополнительный розыгрыш лута"],["max_hp","Максимум здоровья ±"],["roll","Изменить бросок ±"],["reroll","Перебросить кубик"],["cancel","Отменить карту в стеке"],["cancel_attack","Отменить атаку"],["prevent_death","Предотвратить смерть"],["destroy","Уничтожить предмет"],["steal","Украсть предмет"],["recharge","Перезарядить предмет"],["ready_character","Перезарядить персонажа"],["counter","Счётчики предмета ±"],["monster_damage","Урон монстру"],["monster_hp","Здоровье монстра ±"],["peek_loot","Посмотреть верх лута"],["peek_treasure","Посмотреть верх сокровищ"],["peek_monster","Посмотреть верх монстров"]]
func _ready() -> void:
	add_child(FSStyle.Backdrop.new())
	_top = TopBar.make(
		self,
		"Isaac · Four Souls",
		func(t, z): return FSStyle.button(t, z),
		null,
		FSStyle.ink(),
		FSStyle.font("title")
	)
	_top.chat.z_index = 80
	for entry in [
		["Правила", app.show_rules],
		["Настройки", app.show_settings],
		["Журнал", _journal],
		["Выйти", app.back_to_hub]
	]:
		var b := FSStyle.button(entry[0], FSStyle.CAP)
		if entry[0] == "Выйти":
			LeaveGuard.wire(b, "Выйти?", "Покинуть подвал?", entry[1])
		else:
			b.pressed.connect(entry[1])
		_top.actions.add_child(b)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 16
	margin.offset_right = -16
	margin.offset_top = TopBar.HEIGHT + 4
	margin.offset_bottom = -12
	add_child(margin)
	_body = FSStyle.vbox(8)
	margin.add_child(_body)
	_make_play_zone()
	_die = TossDie.new()
	_die.z_index = 30
	add_child(_die)
	_die.thrown.connect(_throw_die)
	Net.state_changed.connect(_changed)
	_changed(Net.view)


## После возврата кубика состояние сети уже может ждать следующий бросок.
func _process(_delta: float) -> void:
	if _v.is_empty() or not is_instance_valid(_die):
		return
	if (
		_die.visible
		and _can_roll_die()
		and _die.state == "idle"
		and not Net.paused
		and not bool(_v.get("game_paused", false))
	):
		_die.draggable = true
		_die.wait_for_roll()


func _can_roll_die() -> bool:
	if _roll_request_revision >= 0 or Net.paused or bool(_v.get("game_paused", false)):
		return false
	if int(_v.seat) < 0:
		return false
	if _v.phase == "effect":
		return _v.seat == _v.actor
	if _pending_effect_roll():
		return _v.seat == _v.stack.filter(func(e): return e.kind == "effect_roll").back().owner
	return (
		_v.seat == _v.current
		and (
			_v.phase == "battle_roll"
			or (
				_v.phase == "priority"
				and _v.stack.any(
					_is_roll_event
				)
			)
		)
	)



func _pending_effect_roll() -> bool:
	return _v.phase == "priority" and _v.stack.any(func(e): return e.kind == "effect_roll")


func _throw_die(_velocity: Vector2) -> void:
	if not _can_roll_die():
		return
	_roll_request_revision = int(_v.revision)
	_die.draggable = false
	var before: int = int(_v.roll_no)
	Net.send_action("effect_roll" if _v.phase == "effect" or _pending_effect_roll() else "roll")
	# Следующий бросок может сначала открыть ручной ответ/награду.
	# Он не должен держать общий кубик в бесконечном ожидании результата.
	if int(_v.roll_no)==before and _v.phase in ["effect","death","turn"]:
		_die.wait_for_roll()
		_die.draggable = _v.phase=="effect" and _v.seat==_v.actor
func _send(kind: String, arg = null) -> void:
	if is_instance_valid(_popup): _popup.queue_free(); _popup = null
	Net.send_action(kind,arg)
func _note(parent: Control,text: String, size_value: int = FSStyle.CAP) -> void:
	var label := FSStyle.label(text,size_value); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(label)
func _button(parent: Control,text: String,kind: String,arg = null,primary: bool = false) -> Button:
	var b := FSStyle.primary(text) if primary else FSStyle.button(text,FSStyle.CAP)
	b.pressed.connect(func(): _send(kind,arg)); parent.add_child(b); return b
func _changed(view: Dictionary) -> void:
	if view.is_empty():
		return
	_end_card_drag()
	_v = view
	if int(view.revision) > _roll_request_revision:
		_roll_request_revision = -1
	FSStyle.clear(_body)
	_hide_preview()
	_top.info.text = (
		"Победитель: " + str(view.players[int(view.winner)].name)
		if view.winner >= 0
		else "%s · ход %d" % [view.players[int(view.current)].name, view.round_no]
	)
	if Net.mode == "offline":
		var row := FSStyle.hbox(8)
		_body.add_child(row)
		var select := OptionButton.new()
		for player in view.players:
			select.add_item(str(player.name))
		select.select(int(view.seat))
		select.item_selected.connect(_switch)
		row.add_child(select)
		var pass_screen := FSStyle.button(
			"Передать экран: " + str(view.players[int(view.actor)].name), FSStyle.CAP
		)
		pass_screen.pressed.connect(func(): _switch(int(view.actor)))
		row.add_child(pass_screen)
		if _unlocked != int(view.seat):
			var center := CenterContainer.new()
			center.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_body.add_child(center)
			var panel := FSStyle.panel()
			panel.custom_minimum_size.x = minf(480, maxf(360, size.x - 64))
			center.add_child(panel)
			var col := FSStyle.vbox(24)
			panel.add_child(col)
			_note(col, "Передайте экран игроку «%s»" % view.players[int(view.seat)].name, FSStyle.H1)
			_note(col, "Остальные должны отвернуться: сейчас откроется личная рука.")
			var open := FSStyle.primary("Открыть мою руку")
			open.pressed.connect(
				func():
					_unlocked = int(view.seat)
					_changed(_v)
			)
			col.add_child(open)
			_die.visible = false
			return
	# Рука занимает нижнюю часть экрана; содержимое стола прокручивается на низких окнах.
	var main_scroll := ScrollContainer.new()
	main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(main_scroll)
	var main := FSStyle.hbox(12)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.add_child(main)
	var players_panel := FSStyle.panel()
	players_panel.custom_minimum_size.x = 248
	main.add_child(players_panel)
	var player_scroll := ScrollContainer.new()
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players_panel.add_child(player_scroll)
	var player_col := FSStyle.vbox(4)
	player_col.custom_minimum_size.x = 216
	player_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_scroll.add_child(player_col)
	for i in view.players.size():
		var player: Dictionary = view.players[i]
		var player_row := FSStyle.hbox(8)
		player_row.name = "Player%d" % i
		player_col.add_child(player_row)
		_card(player_row, int(player.char), Vector2(40, 56), func(): _inventory(i))
		var details := FSStyle.vbox(2)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_row.add_child(details)
		var button := FSStyle.button(
			(
				("→ " if i == view.current else "")
				+ str(player.name)
				+ ("\n⚔ %d · %d¢ · души: %d" % [player.attack, player.coins, player.souls])
			),
			FSStyle.CAP
		)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for state in ["normal", "hover", "pressed"]:
			var compact := FSStyle.box(
				FSStyle.surface().lerp(FSStyle.GOLD, 0.16) if i == view.current else FSStyle.surface()
			)
			compact.content_margin_top = 2
			compact.content_margin_bottom = 2
			button.add_theme_stylebox_override(state, compact)
		button.pressed.connect(func(): _inventory(i))
		details.add_child(button)
		var health := HealthBar.new(int(player.hp), int(player.max_hp))
		health.name = "Health"
		details.add_child(health)
	var center := FSStyle.vbox(4)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(center)
	_note(center, "МОНСТРЫ · %d в колоде" % int(view.counts.monster), FSStyle.BODY)
	var monsters := FSStyle.hbox(8)
	center.add_child(monsters)
	var monster_scroll := ScrollContainer.new()
	monster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	monster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	monsters.add_child(monster_scroll)
	monster_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var monster_row := FSStyle.hbox(8)
	monster_scroll.add_child(monster_row)
	for i in view.monsters.size():
		var m: Dictionary = view.monsters[i]
		var group := FSStyle.vbox(4)
		monster_row.add_child(group)
		_card(
			group,
			int(m.id),
			Vector2(104, 128),
			func():
				var dialog := _card_dialog(
					int(m.id),
					"Атаковать",
					"attack",
					{"slot": i},
					(
						view.phase in ["turn", "priority"]
						and view.seat == view.current
						and view.battle < 0
						and not view.attacked
						and not bool(m.get("untargetable", false))
					)
				)
				_add_monster_trigger(i, dialog)
		)
		var health := HealthBar.new(int(m.hp), maxi(int(m.hp), FSData.stat(int(m.id), "hp", 1)))
		health.name = "MonsterHealth%d" % i
		group.add_child(health)
		group.add_child(FSStyle.label("%d+  ·  ⚔ %d" % [m.dc, m.at], FSStyle.CAP))
	_note(center, "МАГАЗИН · каждое сокровище 10¢", FSStyle.BODY)
	var shop_row := FSStyle.hbox(8)
	center.add_child(shop_row)
	for i in view.shop.size():
		var id: int = int(view.shop[i])
		if id >= 0:
			_card(
				shop_row,
				id,
				Vector2(104, 128),
				func():
					_card_dialog(
						id,
						"Купить · 10¢",
						"buy",
						{"slot": i},
						(
							view.phase in ["turn", "priority"]
							and view.seat == view.current
							and view.battle < 0
							and not view.bought
							and int(view.players[int(view.current)].coins) >= 10
						)
					)
			)
	if view.room >= 0:
		var room_col := FSStyle.vbox(4)
		shop_row.add_child(room_col)
		_note(room_col, "КОМНАТА")
		_card(
			room_col,
			int(view.room),
			Vector2(72, 100),
			func():
				_card_dialog(
					int(view.room),
					"Сменить комнату",
					"room",
					null,
					view.phase == "turn" and view.seat == view.current
				)
		)
	var bonus_row := FSStyle.hbox(4)
	center.add_child(bonus_row)
	for id in view.bonuses:
		if not view.claimed.has(id):
			var b := FSStyle.button("◈", FSStyle.CAP)
			b.tooltip_text = FSData.title(int(id))
			b.pressed.connect(
				func():
					_card_dialog(
						int(id),
						"Забрать душу · условие выполнено",
						"claim",
						{"card": int(id)},
						view.seat >= 0 and view.phase in ["turn", "priority"]
					)
			)
			b.mouse_entered.connect(func(): _show_preview(int(id)))
			b.mouse_exited.connect(_hide_preview)
			bonus_row.add_child(b)
	var side := FSStyle.panel()
	side.custom_minimum_size.x = 300
	main.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var actions := FSStyle.vbox(12)
	actions.custom_minimum_size.x = 268
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(actions)
	_controls(actions)
	_hands(view)
	_die.visible = (
		view.phase in ["battle_roll", "effect"]
		or view.stack.any(
			_is_roll_event
		)
	)
	_die.home = Vector2(size.x * 0.58, size.y * 0.5)
	_die.area = Rect2(Vector2(220, 80), Vector2(maxf(200, size.x - 550), maxf(200, size.y - 240)))
	# Новое сетевое состояние не разрешает захват посреди полёта/возврата.
	_die.draggable = _can_roll_die() and _die.state in ["idle", "waiting"]
	if _die.draggable and _die.state == "idle":
		_die.wait_for_roll()
	if int(view.roll_no) > _last_roll:
		if _last_roll >= 0 and int(view.last_roll) > 0:
			if _die.state == "flying":
				_die.set_result(int(view.last_roll))
			else:
				_die.throw(Vector2(-800, -250), int(view.last_roll))
		_last_roll = int(view.roll_no)


func _can_play_hand() -> bool:
	if _v.seat < 0: return false
	if _v.phase == "discard": return _v.seat == _v.current
	return _v.phase in ["turn","priority","battle_roll","death"] and not _v.players[int(_v.seat)].dead and (bool(_v.players[int(_v.seat)].ready) or _v.seat == _v.current and int(_v.free_loot) > 0)
func _hands(view: Dictionary) -> void:
	var row := FSStyle.hbox(20); row.name="PersonalCards"; _body.add_child(row)
	if view.seat != view.current:
		var opponent := FSStyle.vbox(2); opponent.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(opponent)
		var player: Dictionary = view.players[int(view.current)]
		_note(opponent,"%s · открытые предметы и закрытая рука" % player.name)
		var public_row := FSStyle.hbox(4); opponent.add_child(public_row)
		for item: Dictionary in player.items:
			_card(public_row,int(item.id),Vector2(64,86),func(): _card_dialog(int(item.id),"Закрыть просмотр","",null,false))
		var backs: Array = []
		for i in int(player.hand_count): backs.append({"key":"back:%d"%i,"id":-1,"face_up":false,"back_drawer":FSData.draw_loot_back})
		_fan(public_row,backs,"opponent",false)
	if view.seat < 0: return
	var own := FSStyle.vbox(2); own.size_flags_horizontal=Control.SIZE_EXPAND_FILL; own.size_flags_stretch_ratio=1.35; row.add_child(own)
	_note(own,"ВАШИ КАРТЫ" if view.seat==view.current else "ВАШИ ОТВЕТНЫЕ КАРТЫ · лут и способности")
	var entries: Array = []
	for i in view.players[int(view.seat)].items.size():
		var item: Dictionary = view.players[int(view.seat)].items[i]
		if view.seat != view.current and FSData.item_response_kind(int(item.id)) in ["passive","none"]: continue
		entries.append({"key":"item:%d"%item.id,"id":int(item.id),"item":i,"texture":FSData.texture(int(item.id))})
	for id in view.hand:
		if view.seat!=view.current and FSData.response_kind(int(id))=="own_turn": continue
		entries.append({"key":"loot:%d"%id,"id":int(id),"texture":FSData.texture(int(id))})
	_fan(own,entries,str(view.seat),true)
func _fan(parent: Control, entries: Array, key: String, movable: bool) -> PrivateHand:
	var fan := PrivateHand.new()
	fan.entries = entries
	fan.movable = movable
	fan.preview_delay = 0.75
	if movable:
		fan.card_size = Vector2(192, 280)
		fan.edge_peek = true
		fan.drag_began.connect(_begin_card_drag)
		fan.drag_ended.connect(_end_card_drag)
		fan.drop_action = _drop_card
	fan.order = (_hand_orders.get(key, []) as Array).duplicate()
	fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fan.chosen.connect(
		func(entry):
			if entry.has("item"):
				_item_dialog(int(entry.item))
			else:
				_card_dialog(
					int(entry.id),
					"Сбросить" if _v.phase == "discard" else "Сыграть лут",
					"discard" if _v.phase == "discard" else "loot",
					{"card": int(entry.id)},
					_can_play_hand()
				)
	)
	fan.preview_requested.connect(func(entry): _show_preview(int(entry.id)))
	fan.preview_closed.connect(_hide_preview)
	fan.order_changed.connect(func(keys): _hand_orders[key] = keys)
	parent.add_child(fan)
	if movable:
		# Высота задаётся после _ready общего компонента: за край уходит только низ карты.
		fan.custom_minimum_size.y = fan.card_size.y - 24
	return fan


## Зона розыгрыша появляется только при захвате собственной карты; рука остаётся сортируемой.
func _make_play_zone() -> void:
	_play_zone = PanelContainer.new()
	_play_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_zone.z_index = 60
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.9, 0.35, 0.12)
	box.border_color = Color(0.35, 1.0, 0.45, 0.8)
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	_play_zone.add_theme_stylebox_override("panel", box)
	_play_note = FSStyle.label("Отпустите карту здесь", FSStyle.BODY)
	_play_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_play_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_play_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_zone.add_child(_play_note)
	add_child(_play_zone)
	_play_zone.visible = false
	resized.connect(_layout_play_zone)
	_layout_play_zone()


func _layout_play_zone() -> void:
	if not is_instance_valid(_play_zone):
		return
	_play_zone.position = Vector2(size.x * 0.36, TopBar.HEIGHT + 44)
	_play_zone.size = Vector2(size.x * 0.38, maxf(160, size.y - TopBar.HEIGHT - 280))


func _can_drop_entry(entry: Dictionary) -> bool:
	if entry.is_empty() or _v.is_empty() or Net.paused or bool(_v.get("game_paused", false)):
		return false
	if entry.has("item"):
		if not _can_use_item():
			return false
		var index: int = int(entry.item)
		var items: Array = _v.players[int(_v.seat)].items
		if index < 0 or index >= items.size():
			return false
		var ability := FSData.item_response_kind(int(items[index].id))
		return (
			ability in ["paid", "hybrid", "conditional"] or ability == "tap" and not bool(items[index].tapped)
		)
	return _can_play_hand()


func _begin_card_drag(entry: Dictionary) -> void:
	_hide_preview()
	_drag_entry = entry
	_layout_play_zone()
	_play_zone.visible = true
	_play_zone.modulate.a = 1.0 if _can_drop_entry(entry) else 0.45
	_play_note.text = (
		"Отпустите, чтобы применить карту" if _can_drop_entry(entry) else "Сейчас эту карту применить нельзя"
	)


func _end_card_drag() -> void:
	_drag_entry = {}
	if is_instance_valid(_play_zone):
		_play_zone.visible = false


## Сервер по-прежнему проверяет ход/ответ и ведёт стек. Сложные выборы не пропускаются.
func _drop_card(entry: Dictionary, screen: Vector2) -> bool:
	if (
		not is_instance_valid(_play_zone)
		or not _play_zone.visible
		or not _play_zone.get_global_rect().has_point(screen)
		or not _can_drop_entry(entry)
	):
		return false
	_end_card_drag()
	if entry.has("item"):
		var item: Dictionary = _v.players[int(_v.seat)].items[int(entry.item)]
		var ability := FSData.item_response_kind(int(item.id))
		if ability in ["hybrid", "conditional"]:
			_item_dialog(int(entry.item))
		else:
			_send("activate", {"item": int(entry.item), "tap": ability == "tap"})
	else:
		_send("discard" if _v.phase == "discard" else "loot", {"card": int(entry.id)})
	return true


func _can_use_item() -> bool:
	return _v.seat >= 0 and not _v.players[int(_v.seat)].dead and _v.phase in ["turn","priority","battle_roll","death"]
func _item_dialog(index: int) -> void:
	var item: Dictionary = _v.players[int(_v.seat)].items[index]
	var ability := FSData.item_response_kind(int(item.id))
	var col := _card_dialog(int(item.id),"Повернуть → эффект","activate",{"item":index,"tap":true},_can_use_item() and not item.tapped and ability in ["tap","hybrid","conditional"])
	var use := _button(col,"Оплатить способность" if ability in ["paid","hybrid"] else "Срабатывание по условию","activate",{"item":index,"tap":false})
	use.disabled = not _can_use_item() or ability=="tap"
	col.move_child(use,col.get_child_count()-2)
func _switch(seat: int) -> void:
	_unlocked = -2; Net.fs_switch_seat(seat)
func _card(parent: Control,id: int,dimensions: Vector2,callback: Callable) -> void:
	var button := Button.new(); button.custom_minimum_size = dimensions; button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new()); button.add_theme_stylebox_override("hover",FSStyle.box(FSStyle.GOLD))
	var image := TextureRect.new(); image.texture = FSData.texture(id); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_round_image(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); image.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(image)
	button.mouse_entered.connect(func(): _schedule_preview(id)); button.mouse_exited.connect(_hide_preview); button.pressed.connect(callback); parent.add_child(button)
func _round_image(image: TextureRect) -> void:
	var corners := ShaderMaterial.new(); corners.shader=preload("res://hub/card_corners.gdshader"); image.material=corners
func _schedule_preview(id: int) -> void:
	_hide_preview()
	var token := _preview_token
	await get_tree().create_timer(0.75).timeout
	if token == _preview_token:
		_show_preview(id)


func _show_preview(id: int) -> void:
	if Net.paused or bool(_v.get("game_paused", false)):
		return
	_hide_preview()
	_preview = TextureRect.new(); _preview.texture = FSData.texture(id); _preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_round_image(_preview)
	_preview.position = Vector2(size.x*0.5-160,80); _preview.size = Vector2(320,minf(size.y-100,500)); _preview.mouse_filter = Control.MOUSE_FILTER_IGNORE; _preview.z_index = 60; add_child(_preview)
func _hide_preview() -> void:
	_preview_token+=1
	if is_instance_valid(_preview): _preview.queue_free()
	_preview = null
func _dialog() -> VBoxContainer:
	if is_instance_valid(_popup): _popup.queue_free()
	_hide_preview(); _popup = Control.new(); _popup.z_index = 65; _popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_popup)
	var dim := ColorRect.new(); dim.color = Color(0,0,0,0.8); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _popup.add_child(dim)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _popup.add_child(center)
	var panel := FSStyle.panel(); panel.custom_minimum_size.x = 500; center.add_child(panel)
	var col := FSStyle.vbox(12); panel.add_child(col); return col
func _close_button(col: Control) -> void:
	var close := FSStyle.button("Закрыть",FSStyle.CAP); close.pressed.connect(func(): _popup.queue_free(); _popup=null); col.add_child(close)
func _card_dialog(id: int,caption: String,kind: String,arg,enabled: bool) -> VBoxContainer:
	var col := _dialog()
	_note(col,FSData.title(id),FSStyle.BODY)
	var image := TextureRect.new(); image.texture = FSData.texture(id); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image.custom_minimum_size = Vector2(300,minf(size.y-240,410)); col.add_child(image)
	_round_image(image)
	var b := _button(col,caption,kind,arg,true); b.disabled = not enabled
	_close_button(col)
	return col
func _inventory(seat: int) -> void:
	var col := _dialog(); _note(col,str(_v.players[seat].name),FSStyle.H1)
	var row := FSStyle.hbox(8); col.add_child(row)
	_card(row,int(_v.players[seat].char),Vector2(120,165),func(): _show_preview(int(_v.players[seat].char)))
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(500,220); scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; row.add_child(scroll)
	var item_row := FSStyle.hbox(8); scroll.add_child(item_row)
	for i in _v.players[seat].items.size():
		var item: Dictionary = _v.players[seat].items[i]
		var group := FSStyle.vbox(4); item_row.add_child(group)
		_card(group,int(item.id),Vector2(104,144),func(): _show_preview(int(item.id)))
		_note(group,("Вечный · " if item.eternal else "") + ("Повёрнут" if item.tapped else "Готов") + " · %d" % int(item.counters))
		if seat == _v.seat:
			var ability := FSData.item_response_kind(int(item.id))
			var use := _button(group,"Повернуть → эффект","activate",{"item":i,"tap":true})
			use.disabled = item.tapped or not _can_use_item() or not ability in ["tap","hybrid","conditional"]
			_button(group,"Оплатить способность" if ability in ["paid","hybrid"] else "Срабатывание по условию","activate",{"item":i,"tap":false}).disabled = not _can_use_item() or ability=="tap"
	var extra_scroll := ScrollContainer.new(); extra_scroll.custom_minimum_size = Vector2(500,108); extra_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; col.add_child(extra_scroll)
	var extra := FSStyle.hbox(8); extra_scroll.add_child(extra)
	for id in _v.players[seat].curses:
		_card(extra,int(id),Vector2(72,100),func(): _show_preview(int(id)))
	for soul in _v.players[seat].souls_cards:
		_card(extra,int(soul.id),Vector2(72,100),func(): _show_preview(int(soul.id)))
	_close_button(col)
func _controls(col: Control) -> void:
	if _v.phase == "game_over":
		_note(col,"Четыре души!",FSStyle.H1); _note(col,"Победил «%s»" % _v.players[int(_v.winner)].name,FSStyle.BODY)
		if Net.is_host():
			var again := FSStyle.primary("Новая партия"); again.pressed.connect(Net.end_game); col.add_child(again)
		return
	_note(col,{"turn":"Ваши решения","priority":"Окно ответов","effect":"Выполнить эффект","battle_roll":"Бросок атаки","death":"Штраф за смерть","discard":"Сбросить до 10"}.get(_v.phase,_v.phase),FSStyle.BODY)
	_note(col,"Ход: " + str(_v.players[int(_v.current)].name) if _v.phase=="priority" else "Сейчас: " + str(_v.players[int(_v.actor)].name))
	_note(col,"В банке: %d¢" % int(_v.bank))
	if _v.phase == "priority":
		for e in _v.stack:
			_note(col,FSData.effect_title(e))
		_note(col,"Любой игрок может ответить до следующего действия активного игрока.")
		if _v.stack.any(func(e): return e.kind in ["roll", "combat"]):
			_note(col, "Урон применится перед следующим броском, после ответов игроков.")
	if _v.phase == "priority" and int(_v.get("death_actor", -1)) == int(_v.seat) and _v.seat >= 0:
		_death_controls(col)
		return
	if _v.phase in ["turn","priority"] and _v.seat == _v.current and _v.battle < 0:
		_note(col,"Лут за ход: %d · персонаж %s" % [int(_v.free_loot),"готов" if _v.players[int(_v.seat)].ready else "повёрнут"])
		_button(col,"Закончить ход","end",null,true)
		var blind_attack := FSStyle.button("Атаковать верх колоды",FSStyle.CAP)
		blind_attack.disabled = _v.attacked
		blind_attack.pressed.connect(_choose_top_attack); col.add_child(blind_attack)
		_button(col,"Купить вслепую · 10¢","buy",{"slot":-1}).disabled = _v.bought
		_note(col,"Сложные эффекты и пассивные условия выполняют участники по тексту русской карты.")
	elif _v.phase == "battle_roll": _note(col,"Схватите кубик, потяните и отпустите, чтобы атаковать.")
	elif _v.phase == "effect":
		_note(col,FSData.title(int(_v.resolving.card)))
		if _v.resolving.kind == "reward": _note(col,"Начислите награды и души строго по убитой карте, затем завершите эффект.")
		var show := FSStyle.button("Прочитать карту",FSStyle.CAP); show.pressed.connect(func(): _show_preview(int(_v.resolving.card))); col.add_child(show)
		if _v.seat == _v.actor: _effect_controls(col)
	elif _v.phase == "death" and _v.seat == _v.actor: _death_controls(col)
	elif _v.phase == "discard": _note(col,"Нажимайте на лишние карты в руке, чтобы сбросить их.")
	if _v.seat >= 0 and _v.phase in ["turn","priority"]:
		var deal := FSStyle.button("Передать монеты",FSStyle.CAP); deal.pressed.connect(_trade); col.add_child(deal)
func _effect_controls(col: Control) -> void:
	_note(col,"Если карта требует бросок — бросьте кубик мышью. На него можно ответить.")
	if _v.resolving.has("reroll_request"):
		_note(col, "Вы управляете исходным броском. Перебросьте кубик мышью; затем эффект вернётся владельцу карты.")
		return
	if _v.resolving.kind == "monster_trigger":
		_note(col, "Выполните условие по тексту монстра вручную. Уже учтённые ауры и боевые эффекты повторять не нужно.")
	var target := OptionButton.new()
	for player in _v.players: target.add_item(str(player.name))
	target.select(int(_v.actor)); col.add_child(target)
	var op := OptionButton.new()
	var operations := OPS + EXTRA_OPS
	for entry in operations: op.add_item(entry[1])
	if _v.resolving.kind == "event" and str(FSData.card(int(_v.resolving.card)).lua.get("type","")) == "curse":
		for i in OPS.size():
			if OPS[i][0] == "attach_curse": op.select(i)
		_note(col,"Это проклятие: выберите игрока, передайте ему карту и завершите эффект.")
	col.add_child(op)
	var amount := SpinBox.new(); amount.min_value = -99; amount.max_value = 99; amount.value = 1; col.add_child(amount)
	_note(col,"Номер предмета / монстра / карты руки (слева направо); передача — свой предмет")
	var index := SpinBox.new(); index.min_value = 1; index.max_value = 99; index.value = 1; col.add_child(index)
	var apply := FSStyle.button("Применить",FSStyle.CAP)
	apply.pressed.connect(func(): _send("effect",{"target":target.selected,"op":operations[op.selected][0],"amount":int(amount.value),"item":int(index.value)-1})); col.add_child(apply)
	_button(col,"Эффект выполнен","effect_done",null,true)
	if not _v.peek.is_empty():
		_note(col,"Только вы видите просмотренные карты.")
		for revealed: Dictionary in _v.peek.get("hands", []):
			_note(col, str(_v.players[int(revealed.seat)].name))
			for id in revealed.cards:
				var hand_card := FSStyle.button(FSData.title(int(id)), FSStyle.CAP)
				col.add_child(hand_card)
				hand_card.mouse_entered.connect(func(): _show_preview(int(id)))
				hand_card.mouse_exited.connect(_hide_preview)
		for id in _v.peek.get("cards", []):
			var peek_card := FSStyle.button(FSData.title(int(id)),FSStyle.CAP); col.add_child(peek_card)
			peek_card.mouse_entered.connect(func(): _show_preview(int(id))); peek_card.mouse_exited.connect(_hide_preview)
			var row := FSStyle.hbox(4); col.add_child(row)
			for entry in [["↑","top"],["↓","bottom"],["Рука","hand"],["Предмет","item"],["Сброс","discard"]]: _button(row,entry[0],"peek_take",{"card":int(id),"dest":entry[1]})
func _death_controls(col: Control) -> void:
	_note(col,"До принятия штрафа игроки могут ответить лутом или способностью.")
	_note(col,"Потеряйте 1¢, одну карту лута и один невечный предмет.")
	var loot := OptionButton.new()
	for id in _v.hand: loot.add_item(FSData.title(int(id)),int(id))
	col.add_child(loot)
	var item := OptionButton.new()
	for i in _v.players[int(_v.seat)].items.size():
		var data: Dictionary = _v.players[int(_v.seat)].items[i]
		if not data.eternal: item.add_item(FSData.title(int(data.id)),i)
	col.add_child(item)
	var pay := FSStyle.primary("Принять штраф")
	pay.pressed.connect(func(): _send("death",{"loot":loot.get_selected_id() if loot.item_count else -1,"item":item.get_selected_id() if item.item_count else -1})); col.add_child(pay)

## Неизвестные пассивы монстра выполняются вручную по его тексту, как в TTS.
func _add_monster_trigger(slot: int, col: Control) -> void:
	var trigger := _button(col, "Срабатывание монстра · вручную", "monster_trigger", {"slot": slot})
	trigger.disabled = not _can_use_item()
	col.move_child(trigger, col.get_child_count() - 2)
func _trade() -> void:
	var col := _dialog(); _note(col,"Передать монеты",FSStyle.H1)
	var target := OptionButton.new()
	for i in _v.players.size():
		if i != _v.seat: target.add_item(str(_v.players[i].name),i)
	col.add_child(target)
	var amount := SpinBox.new(); amount.min_value = 1; amount.max_value = maxi(1,int(_v.players[int(_v.seat)].coins)); amount.value = 1; col.add_child(amount)
	var send := FSStyle.primary("Передать"); send.pressed.connect(func(): _send("trade",{"target":target.get_selected_id(),"amount":int(amount.value)})); col.add_child(send); _close_button(col)
func _journal() -> void:
	var col := _dialog(); _note(col,"Журнал подвала",FSStyle.H1)
	var text := RichTextLabel.new(); text.custom_minimum_size = Vector2(700,minf(450,size.y-200)); text.text = "\n".join(_v.log); col.add_child(text); _close_button(col)

func _choose_top_attack() -> void:
	var col := _dialog()
	_note(col,"Кого накроет новая карта?",FSStyle.H1)
	_note(col,"Если откроется монстр, положите его поверх одного из существующих. После победы нижний монстр снова станет доступен.")
	for i in _v.monsters.size():
		_button(col,FSData.title(int(_v.monsters[i].id)),"attack",{"slot":-1,"over":i})
	_close_button(col)


func _is_roll_event(effect: Dictionary) -> bool:
	return effect.kind in ["attack", "roll", "combat", "effect_roll", "monster_death", "death", "monster_trigger"]
