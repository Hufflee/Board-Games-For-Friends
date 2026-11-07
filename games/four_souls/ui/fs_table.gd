extends Control
## Стол Four Souls: закрытая рука, открытые карты, приоритет и ручная панель эффектов.
const HealthBar := preload("res://games/four_souls/ui/fs_health.gd")
const PassiveRules := preload("res://games/four_souls/logic/fs_passives.gd")
const Packet26 := preload("res://games/four_souls/logic/fs_packet26_cards.gd")
const FX := preload("res://games/four_souls/ui/fs_fx.gd")
var _fx_layer28: Control  # слой всплывающих индикаторов поверх стола
var _fx_anchor28: Dictionary = {}  # ключ → узел текущей раскладки (игрок, монстр, магазин, карта)
var _fx_seen28 := -1  # номер последнего показанного события ленты fx28
var _fx_ready28 := false
var _rects28: Dictionary = {}  # прошлые экранные прямоугольники якорей (монстры, стопка) — откуда летят карты
var _feed_seen28 := -1  # последняя показанная запись ленты сброса
var _pile_shown28 := 0
var _response_bar28: ProgressBar  # таймер окна ответов (07.11)
var _response_label28: Label
var _response_left_at28 := 0  # верхняя карта стопки, уже показанная (её больше не прячем)
var _fly_seen28 := -1  # последний розыгрыш, показанный полётом через центр  # первое состояние уже принято (его события не проигрываются)
var app: Node
var _v: Dictionary = {}
var _body: VBoxContainer
var _top: TopBar
var _die: TossDie
var _preview: TextureRect
var _unlocked := -2
var _turn_seen := -1
## Заряд предметов и персонажа: «ключ» → разряжен ли (прошлое и текущее состояние) — для плавного перехода.
const CHARGE_SHADER := preload("res://games/four_souls/ui/fs_charge.gdshader")
const DISCHARGE_TIME := 0.35  # ч/б ложится быстро
const RECHARGE_TIME := 1.2  # цвет возвращается плавно
var _charge_prev := {}
## Своя рука переживает пересборку стола, если её карты не изменились: иначе на каждое чужое
## действие карты создавались заново и «прилетали» в руку, а начатое перетаскивание обрывалось.
var _own_fan: PrivateHand  # своя карта «в игре» (персонаж, вечные, брелки, предметы) — для тестов и совместимости
var _own_fans: Dictionary = {}  # ключ веера → PrivateHand: свои веера не пересоздаются от чужих обновлений
var _own_fan_sigs: Dictionary = {}
var _drag_resume: Dictionary = {}
var _played_seen := -1  # номер последнего показанного розыгрыша (для «прыжка» новой карты на стопку)
var _charge_now := {}  # чей ход уже видели: на новом ходу экран сам переходит к ходящему (один компьютер)
var _last_roll := -1
# Не отправляем второй запрос, пока хост не подтвердил изменение состояния.
var _roll_request_revision := -1
var _view_at := 0  # когда пришло состояние: часы окна чужих карт считаются от него
var _popup: Control
var _preview_token := 0
var _play_zone: PanelContainer
var _play_note: Label
var _drag_entry: Dictionary = {}
static var _hand_orders: Dictionary = {}
## Операции панели эффекта — общий список с сервером (fs_ops.gd): [op, подпись, поля].
const Support := preload("res://games/four_souls/logic/fs_support.gd")
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
	_fx_layer28 = Control.new()
	_fx_layer28.name = "FxLayer"
	_fx_layer28.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer28.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer28.z_index = 90
	add_child(_fx_layer28)
	_die = TossDie.new()
	_die.z_index = 30
	add_child(_die)
	_die.thrown.connect(_throw_die)
	# Хост не ответил на бросок — не держим кубик и запрос вечно; _process снова предложит бросок.
	_die.stalled.connect(func(): _roll_request_revision = -1)
	Net.state_changed.connect(_changed)
	_changed(Net.view)


## Таймер окна ответов: остаток с хоста минус время с прихода состояния.
func _tick_response28() -> void:
	if not is_instance_valid(_response_bar28):
		return
	var left := maxf(0.0, float(_v.get("response_left28", 0.0)) - (Time.get_ticks_msec() - _response_left_at28) / 1000.0)
	_response_bar28.value = left
	_response_label28.text = "Ответить: %.1f с" % left if left > 0.0 else "Ответы закрываются…"


## После возврата кубика состояние сети уже может ждать следующий бросок.
func _process(_delta: float) -> void:
	_tick_response28()
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
	if _v.get("resolving", {}).has("spawn_card"):
		return false
	if _roll_request_revision >= 0 or Net.paused or bool(_v.get("game_paused", false)):
		return false
	if int(_v.seat) < 0:
		return false
	if _v.phase == "effect" or bool(_v.get("effect_pending", false)):
		if bool(_v.get("card_automated", false)) and not bool(_v.get("card_roll_wait", false)) and not _v.resolving.has("reroll_request"):
			return false
		if _v.resolving.has("auto_reward") and not _v.resolving.has("reroll_request"):
			if _v.resolving.has("reward_roll") and not bool(_v.resolving.get("post_reward_wait", false)):
				return false
			if not bool(_v.resolving.get("requires_reward_roll", false)) and not bool(_v.resolving.get("post_reward_wait", false)) and not (bool(_v.resolving.auto_reward.get("manual_death", false)) and not bool(_v.resolving.get("death_text_done", false))):
				return false
		# Переброс делает владелец исходного кубика; автор ручной карты остаётся прежним.
		var roller: int = int(_v.resolving.get("reroll_request", {}).get("owner", _v.resolving.owner))
		return _v.seat == roller
	if _pending_effect_roll():
		return _v.seat == _v.stack.filter(func(e): return e.kind == "effect_roll").back().owner
	return (
		_v.seat == int(_v.get("battle_roller15", _v.current))
		and (
			_v.phase == "battle_roll"
			or (
				# 07.11: в настоящей партии бросать во время окна ответов нельзя — дождаться 5 с.
				not bool(_v.get("strict_responses28", false))
				and _v.phase == "priority"
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
	Net.send_action("effect_roll" if _v.phase == "effect" or bool(_v.get("effect_pending", false)) or _pending_effect_roll() else "roll")
	# Следующий бросок может сначала открыть ручной ответ/награду.
	# Он не должен держать общий кубик в бесконечном ожидании результата.
	if int(_v.roll_no)==before and _v.phase in ["effect","death","turn"]:
		_die.wait_for_roll()
		_die.draggable = _v.phase=="effect" and _v.seat==_v.actor
func _send(kind: String, arg = null) -> void:
	if is_instance_valid(_popup): _popup.queue_free(); _popup = null
	Net.send_action(kind,arg)
func _note(parent: Control,text: String, size_value: int = FSStyle.CAP) -> Label:
	var label := FSStyle.label(text,size_value); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(label)
	return label
func _button(parent: Control,text: String,kind: String,arg = null,primary: bool = false) -> Button:
	var b := FSStyle.primary(text) if primary else FSStyle.button(text,FSStyle.CAP)
	b.pressed.connect(func(): _send(kind,arg)); parent.add_child(b); return b
func _exit_tree() -> void:
	for fan: Variant in _own_fans.values():
		if is_instance_valid(fan) and (fan as Node).get_parent() == null:
			(fan as Node).free()  # снятая на время пересборки рука — не в дереве, сама не освободится


func _changed(view: Dictionary, received: bool = true) -> void:
	if view.is_empty():
		return
	if is_instance_valid(_popup) and _popup.has_meta("card_choice_revision") and int(_popup.get_meta("card_choice_revision")) != int(view.revision):
		_popup.queue_free()
		_popup = null
	_drag_resume = _drag_entry
	_end_card_drag()
	# За одним компьютером: начался ход другого игрока — экран сам переходит к нему (через экран
	# «Передайте экран…», чтобы не показать чужую руку). Ботов пропускаем — у них нет личного экрана.
	if Net.mode == "offline" and view.get("winner", -1) < 0:
		var current := int(view.get("current", -1))
		if current != _turn_seen:
			var first := _turn_seen == -1
			_turn_seen = current
			var players: Array = view.get("players", [])
			if not first and current >= 0 and current < players.size() and current != int(view.seat) and not bool((players[current] as Dictionary).get("bot", false)):
				_switch(current)
				return  # придёт состояние уже для ходящего
	var prev28: Dictionary = _v
	_v = view
	_fx_anchor28.clear()
	_show_fx28.call_deferred(prev28, view)
	_charge_prev = _charge_now
	_charge_now = _collect_charge(view)
	if received:
		_view_at = Time.get_ticks_msec()
	_schedule_off_turn_close()
	if int(view.revision) > _roll_request_revision:
		_roll_request_revision = -1
	for fan: Variant in _own_fans.values():
		if is_instance_valid(fan) and (fan as Node).get_parent() != null:
			(fan as Node).get_parent().remove_child(fan)  # не уничтожать вместе со столом — может пригодиться
	FSStyle.clear(_body)
	_hide_preview()
	_top.info.text = (
		"Победитель: " + str(view.players[int(view.winner)].name)
		if view.winner >= 0
		else "%s · ход %d" % [view.players[int(view.current)].name, view.round_no]
	)
	# 06.11 (владелец): верхняя полоса — выбор места (один компьютер) и бонусные души.
	var top_row28 := FSStyle.hbox(8)
	_body.add_child(top_row28)
	if Net.mode == "offline":
		var row := top_row28
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
					_changed(_v, false)
			)
			col.add_child(open)
			_die.visible = false
			return
	# 06.11 (владелец): панели всегда целиком, с верхней и нижней рамкой — прокручивается
	# только содержимое внутри панелей и центральной колонки, а не весь стол.
	var main := FSStyle.hbox(12)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(main)
	var players_panel := FSStyle.panel()
	players_panel.custom_minimum_size.x = 248
	main.add_child(players_panel)
	var player_scroll := ScrollContainer.new()
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
		_card(player_row, int(player.char), Vector2(40, 56), func(): _inventory(i), "c:%d" % i)
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
		if int(player.get("eggs", 0)) > 0:
			_note(details, "Жетоны-яйца: %d" % int(player.eggs))
		if bool(player.get("respawn_egg17", false)):
			_note(details, "Яйцо: возвращает монстра после смерти")
		if int(player.get("skipped_turns", 0)) > 0:
			_note(details, "Пропуск ходов: %d" % int(player.skipped_turns))
		var health := HealthBar.new(int(player.hp), int(player.max_hp))
		health.name = "Health"
		details.add_child(health)
		_fx_anchor28["p%d" % i] = player_row
		_fx_anchor28["ph%d" % i] = health
	var center_scroll := ScrollContainer.new()
	center_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(center_scroll)
	var center := FSStyle.vbox(4)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.add_child(center)
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
	_played_pile(monsters, view)
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
						and not bool(view.get("blind_only17", false))
						and (view.get("forced_monster_slots", []).is_empty() or i in view.forced_monster_slots)
						and int(view.get("forced_deck_attacks", 0)) == 0
						and int(view.get("required_player_attacks", 0)) == 0
						and not bool(m.get("untargetable", false))
					)
				)
		)
		var health := HealthBar.new(int(m.hp), maxi(int(m.hp), FSData.stat(int(m.id), "hp", 1)))
		health.name = "MonsterHealth%d" % i
		group.add_child(health)
		_fx_anchor28["m%d" % i] = group
		if int(m.hp) <= 0:
			FX.badge(group.get_child(0), "dead")
		elif _is_target28(view, i):
			FX.badge(group.get_child(0), "target")
		var stats := "%d+ · ⚔%d" % [m.dc, m.at]
		if int(m.get("counters", 0)) > 0:
			stats += " · ●%d" % int(m.counters)
		if int(m.get("eggs", 0)) > 0:
			stats += " · яйца:%d" % int(m.eggs)
		var stats_label := FSStyle.label(stats, FSStyle.CAP)
		stats_label.tooltip_text = "Жетоны на монстре: %d" % int(m.get("counters", 0))
		group.add_child(stats_label)
	_note(center, "МАГАЗИН · каждое сокровище %d¢" % int(view.get("shop_price", 10)), FSStyle.BODY)
	var market_scroll := ScrollContainer.new()
	market_scroll.custom_minimum_size.y = 160
	market_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	market_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(market_scroll)
	var shop_row := FSStyle.hbox(8)
	market_scroll.add_child(shop_row)
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
						"Купить · %d¢" % int(view.get("shop_price", 10)),
						"buy",
						{"slot": i},
						(
							view.phase in ["turn", "priority"]
							and view.seat == view.current
							and view.battle < 0
							and not view.bought
							and int(view.players[int(view.current)].coins) >= int(view.get("shop_price", 10))
						)
					)
			)
			var shop_card: Control = shop_row.get_child(shop_row.get_child_count() - 1)
			_fx_anchor28["s%d" % i] = shop_card
			if view.stack.any(func(e): return str(e.get("kind", "")) == "purchase" and int(e.get("slot", -2)) == i):
				FX.badge(shop_card, "buy")
	if int(view.get("loot_top20", -1)) >= 0:
		var loot_col := FSStyle.vbox(4)
		shop_row.add_child(loot_col)
		_note(loot_col, "ВЕРХ ДОБЫЧИ")
		_card(loot_col, int(view.loot_top20), Vector2(80, 104), func(): _card_dialog(int(view.loot_top20), "Сыграть верхнюю добычу", "loot_top20", {"card": int(view.loot_top20)}, bool(view.get("can_top_loot20", false)) and _can_play_hand()))
	if view.room >= 0:
		var room_col := FSStyle.vbox(4)
		shop_row.add_child(room_col)
		_note(room_col, "КОМНАТА")
		_card(
			room_col,
			int(view.room),
			Vector2(72, 100),
			func(): _native_room_dialog24(-1, int(view.room))
		)
	for index in view.get("extra_rooms20", []).size():
		var source: Dictionary = view.extra_rooms20[index]
		var room_col := FSStyle.vbox(4)
		shop_row.add_child(room_col)
		_note(room_col, "КОМНАТА %d" % (index + 2))
		_card(room_col, int(source.id), Vector2(80, 104), func(): _room_dialog20(index))
	var bonus_row := top_row28
	var open_souls: Array = view.bonuses.filter(func(id): return not view.claimed.has(id))
	if not open_souls.is_empty():
		var souls_caption := FSStyle.label("  БОНУСНЫЕ ДУШИ", FSStyle.CAP)
		souls_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bonus_row.add_child(souls_caption)
	for id in view.bonuses:
		if not view.claimed.has(id):
			var b := Button.new()
			b.custom_minimum_size = Vector2(34, 46)
			b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			b.add_theme_stylebox_override("hover", FSStyle.box(FSStyle.GOLD))
			var soul_image := TextureRect.new()
			soul_image.texture = FSData.texture(int(id))
			soul_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			soul_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			soul_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			soul_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_round_image(soul_image)
			b.add_child(soul_image)
			b.tooltip_text = FSData.title(int(id))
			b.pressed.connect(
				func():
					if int(id) in [692, 693, 694, 695, 696]:
						_bonus_dialog(int(id))
						return
					_card_dialog(
						int(id),
						"Забрать душу · условие выполнено",
						"claim",
						{"card": int(id)},
						view.seat >= 0 and view.phase in ["turn", "priority"]
					)
			)
			b.mouse_entered.connect(func(): _schedule_preview(int(id)))
			b.mouse_exited.connect(_hide_preview)
			bonus_row.add_child(b)
	# 07.11 (владелец): видимый таймер окна ответов — сколько секунд осталось, пока стек не разрешится сам.
	_response_bar28 = null
	if float(view.get("response_left28", -1.0)) >= 0.0:
		var timer_box := FSStyle.hbox(8)
		timer_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top_row28.add_child(timer_box)
		_response_label28 = FSStyle.label("", FSStyle.BODY)
		_response_label28.add_theme_color_override("font_color", FSStyle.GOLD.lightened(0.2))
		timer_box.add_child(_response_label28)
		_response_bar28 = ProgressBar.new()
		_response_bar28.show_percentage = false
		_response_bar28.custom_minimum_size = Vector2(160, 12)
		_response_bar28.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_response_bar28.max_value = float(view.get("response_window", 5.0))
		timer_box.add_child(_response_bar28)
		_response_left_at28 = Time.get_ticks_msec()
		_tick_response28()
	var side := FSStyle.panel()
	side.custom_minimum_size.x = 300
	main.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	var actions := FSStyle.vbox(12)
	actions.custom_minimum_size.x = 268
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(actions)
	_controls(actions)
	_hands(view)
	# Летящий/показывающий результат кубик не прячем, даже если фаза уже сменилась:
	# иначе чужой бросок, сразу разрешённый хостом, не было видно.
	_die.visible = (
		_die.is_busy()
		or view.phase in ["battle_roll", "effect"] or bool(view.get("effect_pending", false))
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
	if _last_roll < 0 and _die.state in ["idle", "waiting"]:
		_die.max_face = int(view.get("die_sides20", 6))
	if int(view.roll_no) > _last_roll:
		if _last_roll >= 0 and int(view.last_roll) > 0:
			_die.max_face = int(view.get("last_die_sides20", 6))
			# 07.11: кубик показывает выпавшую грань, итог с прибавками («Рак» и т.п.) — отдельной надписью.
			var raw: int = int(view.get("last_raw_die20", view.last_roll))
			var face: int = raw if _die.max_face == 8 or (raw >= 1 and raw <= 6) else int(view.last_roll)
			if int(view.last_roll) != face and _die.max_face != 8:
				var total: int = int(view.last_roll)
				get_tree().create_timer(0.9).timeout.connect(func():
					if is_instance_valid(_die) and is_instance_valid(_fx_layer28):
						FX.float_label(_fx_layer28, _die, "итог броска: %d" % total, FX.GLOW, 0, 24))
			if _die.state == "flying":
				_die.set_result(face)
			else:
				_die.throw(Vector2(-800, -250), face)
			# 07.11: чужой бросок виден всем, даже если хост уже разрешил его к приходу состояния
			# (видимость выше считалась до запуска броска — у остальных кубик оставался скрытым).
			_die.visible = true
		_last_roll = int(view.roll_no)
	elif _die.state in ["idle", "waiting"]:
		_die.max_face = int(view.get("die_sides20", 6))


## Окно своих карт в чужой ход (первые 10 с хода): сколько осталось по часам хоста.
func _off_turn_left() -> float:
	return maxf(0.0, float(_v.get("off_turn_left", 0.0)) - (Time.get_ticks_msec() - _view_at) / 1000.0)


func _off_turn_ok() -> bool:
	# 06.11: хост больше не ограничивает чужой ход по времени (off_turn_left = −1).
	# 06.11: в чужой ход — только в ответ, пока стек не разрешился (окно тишины хоста 5 с).
	if not bool(_v.get("strict_responses28", false)) or _v.seat == _v.current:
		return true
	return str(_v.get("phase", "")) == "death" or (str(_v.get("phase", "")) == "priority" and not (_v.get("stack", []) as Array).is_empty())


## Окно закрылось — пересобрать стол, чтобы карты и предметы погасли (новое состояние может не прийти).
func _schedule_off_turn_close() -> void:
	var left := _off_turn_left()
	if left <= 0.0 or _v.seat == _v.current:
		return
	var revision := int(_v.revision)
	get_tree().create_timer(left + 0.05, true, false, true).timeout.connect(func():
		if is_inside_tree() and int(_v.revision) == revision:
			_changed(_v, false))


func _can_play_hand() -> bool:
	if _v.seat < 0: return false
	if not _off_turn_ok(): return false
	if _v.phase == "discard": return _v.seat == _v.current
	return _v.phase in ["turn","priority","battle_roll","death"] and not _v.players[int(_v.seat)].dead and (bool(_v.get("unlimited_loot",false)) or _character_can_pay24() or int(_v.get("bonus_loot_plays", 0)) > 0 or _v.seat == _v.current and int(_v.free_loot) > 0)
func _hands(view: Dictionary) -> void:
	var row := FSStyle.hbox(20); row.name="PersonalCards"; _body.add_child(row)
	if view.seat != view.current:
		var opponent := FSStyle.vbox(2); opponent.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(opponent)
		var player: Dictionary = view.players[int(view.current)]
		_note(opponent,"%s · открытые предметы и закрытая рука" % player.name)
		var public_row := FSStyle.hbox(4); opponent.add_child(public_row)
		_card(public_row, int(player.char), Vector2(64, 86), func(): _card_dialog(int(player.char), "Закрыть просмотр", "", null, false), "c:%d" % int(view.current))
		for item: Dictionary in player.items:
			_card(public_row,int(item.id),Vector2(64,86),func(): _card_dialog(int(item.id),"Закрыть просмотр","",null,false),"i:%d:%d" % [int(view.current), int(item.id)])
		var backs: Array = []
		for i in int(player.hand_count):
			if player.has("hand"):
				backs.append({"key": "open:%d" % i, "id": int(player.hand[i]), "face_up": true})
			else:
				backs.append({"key":"back:%d"%i,"id":-1,"face_up":false,"back_drawer":FSData.draw_loot_back})
		_fan(public_row,backs,"opponent",false)
	if view.seat < 0: return
	var own := FSStyle.vbox(2); own.size_flags_horizontal=Control.SIZE_EXPAND_FILL; own.size_flags_stretch_ratio=1.35; row.add_child(own)
	# 06.11: персонаж, вечные карты, брелки и предметы — отдельно от руки лута, чтобы было видно, что они в игре.
	var split := FSStyle.hbox(24); split.size_flags_horizontal = Control.SIZE_EXPAND_FILL; own.add_child(split)
	var in_play := FSStyle.vbox(2); in_play.name = "InPlay"; in_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL; in_play.size_flags_stretch_ratio = 0.9; split.add_child(in_play)
	var loot_col := FSStyle.vbox(2); loot_col.name = "LootHand"; loot_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; split.add_child(loot_col)
	_note(loot_col, "РУКА · лут" if view.seat == view.current else "РУКА · справа — карты для ответов")
	var board: Array = []
	board.append({"key": "character:%d" % int(view.seat), "id": int(view.players[int(view.seat)].char), "character": true, "texture": FSData.texture(int(view.players[int(view.seat)].char)), "material": _charge_material("c:%d" % int(view.seat))})
	for i in view.players[int(view.seat)].items.size():
		var item: Dictionary = view.players[int(view.seat)].items[i]
		board.append({"key":"item:%d"%item.id,"id":int(item.id),"item":i,"starting":bool(item.eternal),"texture":FSData.texture(int(item.id)),"material":_charge_material("i:%d:%d" % [int(view.seat), int(item.id)])})
	var loot: Array = []
	if bool(view.get("can_top_loot20", false)) and int(view.get("loot_top20", -1)) >= 0:
		loot.append({"key": "top_loot:%d" % int(view.loot_top20), "id": int(view.loot_top20), "top_loot20": true, "texture": FSData.texture(int(view.loot_top20))})
	# 06.11: в чужой ход видна вся рука; карты для ответов (бомбы, бобы, осколки, сердца) — справа,
	# а те, что можно разыграть прямо сейчас по делу, подсвечены и нетерпеливо покачиваются.
	var off_turn28: bool = view.seat != view.current
	var ready28: Array = view.get("loot_moment28", [])
	var later28: Array = []
	for id in view.hand:
		var entry28 := {"key":"loot:%d"%id,"id":int(id),"texture":FSData.texture(int(id))}
		if off_turn28 and FSData.reactive_loot28(int(id)):
			entry28["reactive28"] = true
			entry28["ready28"] = int(id) in ready28
			later28.append(entry28)
		else:
			loot.append(entry28)
	loot.append_array(later28)
	_own_fan = _fan(in_play, board, "%d:board" % int(view.seat), true, Vector2(150, 219))
	if loot.is_empty():
		var empty := FSStyle.label("Карт лута нет", FSStyle.CAP)
		empty.modulate.a = 0.6
		loot_col.add_child(empty)
	else:
		_fan(loot_col, loot, str(view.seat), true)
func _fan(parent: Control, entries: Array, key: String, movable: bool, card_size := Vector2(192, 280)) -> PrivateHand:
	if movable:
		var sig := str([key, entries.map(func(e): return [e.get("key"), e.get("id"), e.get("face_up", true), e.get("item", -1), e.get("ready28", false), e.get("reactive28", false)]),
			_charge_now.hash(), _v.get("phase", ""), _v.get("current", -1), card_size])
		var cached: PrivateHand = _own_fans.get(key) if is_instance_valid(_own_fans.get(key)) else null
		if cached != null and cached.get_parent() == null and sig == str(_own_fan_sigs.get(key, "")):
			parent.add_child(cached)  # та же рука: карты не пересоздаются и не «прилетают»
			if not _drag_resume.is_empty() and cached._cards.values().any(func(c): return c.dragging):
				_begin_card_drag(_drag_resume)  # перетаскивание продолжается
			return cached
		if cached != null and cached.get_parent() == null:
			cached.queue_free()
		_own_fan_sigs[key] = sig
	var fan := PrivateHand.new()
	for entry: Dictionary in entries:
		if bool(entry.get("face_up", true)) and int(entry.get("id", -1)) >= 0 and not entry.has("texture"):
			entry["texture"] = FSData.texture(int(entry.id))
	fan.entries = entries
	fan.movable = movable
	fan.preview_delay = 0.375  # 06.11: вдвое быстрее
	if movable:
		fan.card_size = card_size
		fan.edge_peek = true
		fan.drag_began.connect(_begin_card_drag)
		fan.drag_ended.connect(_end_card_drag)
		fan.drop_action = _drop_card
	fan.order = (_hand_orders.get(key, []) as Array).duplicate()
	if entries.any(func(e): return bool(e.get("reactive28", false))):
		var keys28: Array = entries.map(func(e): return str(e.key))
		var ordered28: Array = fan.order.filter(func(k): return k in keys28)
		for k in keys28:
			if k not in ordered28:
				ordered28.append(k)
		var right28: Array = entries.filter(func(e): return bool(e.get("reactive28", false))).map(func(e): return str(e.key))
		fan.order = ordered28.filter(func(k): return k not in right28) + ordered28.filter(func(k): return k in right28)
	if movable and entries.any(func(e): return bool(e.get("character", false))):
		var character_key := "character:%d" % int(_v.seat)
		fan.order.erase(character_key)
		var beside := 0
		for entry: Dictionary in entries:
			if bool(entry.get("starting", false)):
				beside = maxi(0, fan.order.find(str(entry.key)))
				break
		fan.order.insert(beside, character_key)
	fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fan.chosen.connect(
		func(entry):
			if bool(entry.get("character", false)):
				_character_dialog()
			elif bool(entry.get("top_loot20", false)):
				_card_dialog(int(entry.id), "Сыграть верхнюю добычу", "loot_top20", {"card": int(entry.id)}, bool(_v.get("can_top_loot20", false)) and _can_play_hand())
			elif entry.has("item"):
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
	# Пометка относится только к открытому лицу: рубашка не раскрывает поддержку чужой карты.
	for entry: Dictionary in entries:
		if bool(entry.get("face_up", true)) and int(entry.get("id", -1)) >= 0:
			var card: K12TableCard = fan._cards[str(entry.key)]
			_support_badge(card._face, int(entry.id))
			if bool(entry.get("ready28", false)):
				FX.wiggle.call_deferred(card)
	if movable:
		# Высота задаётся после _ready общего компонента: за край уходит только низ карты.
		fan.custom_minimum_size.y = fan.card_size.y - 24
		_own_fans[key] = fan
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
	if bool(entry.get("character", false)):
		return _can_use_character()
	if bool(entry.get("top_loot20", false)):
		return int(entry.id) == int(_v.get("loot_top20", -1)) and bool(_v.get("can_top_loot20", false)) and _can_play_hand()
	if entry.has("item"):
		var index: int = int(entry.item)
		if int(_v.seat) < 0:
			return false
		var items: Array = _v.players[int(_v.seat)].items
		if index < 0 or index >= items.size():
			return false
		var ability := _item_kind20(items[index])
		if not _can_use_item():
			return false
		return (
			ability in ["paid", "hybrid", "conditional"] or ability == "tap" and _can_tap_item24(items[index])
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
	if bool(entry.get("character", false)):
		_send("character", null)
	elif bool(entry.get("top_loot20", false)):
		_send("loot_top20", {"card": int(entry.id)})
	elif entry.has("item"):
		var item: Dictionary = _v.players[int(_v.seat)].items[int(entry.item)]
		var ability := _item_kind20(item)
		if ability in ["hybrid", "conditional", "passive"] or int(item.id) == 70 or Packet26.PAID.has(int(item.id)):
			_item_dialog(int(entry.item))
		else:
			_send("activate", {"item": int(entry.item), "tap": ability == "tap"})
	else:
		_send("discard" if _v.phase == "discard" else "loot", {"card": int(entry.id)})
	return true


## 07.11: предметы (поворот/платно) в чужой ход — в любой момент; «только в ответ» — для добычи и персонажа.
func _can_use_item() -> bool:
	return _v.seat >= 0 and not _v.players[int(_v.seat)].dead and _v.phase in ["turn","priority","battle_roll","death"]
func _item_kind20(item: Dictionary) -> String:
	if int(item.id) == 1:
		return "tap" if item.get("prototype_texts20", []).any(func(text): return int(text.begin) == 2) else "passive"
	return FSData.item_response_kind(int(item.id))
func _can_use_character() -> bool:
	return _can_use_item() and _off_turn_ok() and _character_can_pay24()
func _character_can_pay24() -> bool:
	if int(_v.seat) < 0:
		return false
	var player: Dictionary = _v.players[int(_v.seat)]
	var price: int = int(_v.get("tap_price24", 0))
	return int(player.coins) >= price if price > 0 else bool(player.ready)
func _can_tap_item24(item: Dictionary) -> bool:
	var price: int = int(_v.get("tap_price24", 0))
	return int(_v.players[int(_v.seat)].coins) >= price + (3 if int(item.id) == 1 else 0) if price > 0 else not bool(item.tapped)
func _character_dialog() -> void:
	var player: Dictionary = _v.players[int(_v.seat)]
	var caption := "Заплатить 3¢ → ещё один розыгрыш добычи" if int(_v.get("tap_price24", 0)) > 0 else "Повернуть персонажа → ещё один розыгрыш добычи"
	if int(player.char) == 882:
		caption = "Заплатить 3¢ → выбрать способность" if int(_v.get("tap_price24", 0)) > 0 else "Повернуть персонажа → выбрать способность"
	var col := _card_dialog(int(player.char), caption, "character", null, _can_use_character())
	if bool(player.get("enigma_back26", false)):
		_note(col, "Энигма перевёрнут · здоровье 1 · атака 2")
	if _v.players[int(_v.seat)].items.any(func(item): return int(item.id) == 5):
		var mushroom := _button(col, "Повернуть персонажа → жетон Волшебного гриба", "mushroom_counter20", null)
		mushroom.disabled = not _can_use_character()
	if int(_v.get("spider_tokens15", 0)) > 0:
		var remove := _button(col, "Повернуть персонажа → убрать жетон паука", "remove_spider15", null)
		remove.disabled = not _can_use_character()
func _item_condition_button(parent: Control, index: int, id: int) -> Button:
	if id in [44, 50]:
		return _paid_button21(parent, index, _v.players[int(_v.seat)].items[index], "activate")
	if FSData.item_response_kind(id) not in ["paid", "hybrid"]:
		return null
	var button := _button(parent, "Оплатить способность", "activate", {"item": index, "tap": false})
	button.disabled = not _can_use_item()
	return button

func _paid_button21(parent: Control, index: int, source: Dictionary, action: String) -> Button:
	var battery: bool = int(source.id) == 44
	var button := _button(parent, "Заплатить 7¢ и перезарядить" if battery else "Сбросить 2 жетона и заменить 2 и 3 на 1", action, {"item": index, "ability": "paid"})
	var affordable: bool = int(_v.players[int(_v.seat)].coins) >= 7 if battery else int(source.counters) >= 2
	button.disabled = not _can_use_item() or not affordable or (action == "room_activate20" and _v.seat != _v.current)
	return button
func _item_dialog(index: int) -> void:
	var item: Dictionary = _v.players[int(_v.seat)].items[index]
	var ability := _item_kind20(item)
	var price: int = int(_v.get("tap_price24", 0))
	var caption := "Заплатить %d¢ → эффект" % (price + (3 if int(item.id) == 1 else 0)) if price > 0 else "Повернуть → эффект"
	var col := _card_dialog(int(item.id), caption, "activate", {"item": index, "tap": true}, _can_use_item() and _can_tap_item24(item) and ability in ["tap", "hybrid", "conditional"])
	if int(item.id) == 173:
		var inspect := _button(col, "Посмотреть верхнее сокровище", "inspect_item13")
		inspect.disabled = _v.seat != _v.current or _v.phase not in ["turn","priority","battle_roll","death"]
		col.move_child(inspect, col.get_child_count()-2)
	if int(item.id) == 843:
		for cost in [1, 2, 5]:
			var label: String = {1: "1 жетон → прибавить 1 к броску", 2: "2 жетона → нанести 1 урона", 5: "5 жетонов → стать душой"}[cost]
			var button := _button(col, label, "activate", {"item": index, "ability": "bone%d" % cost})
			button.disabled = not _can_use_item() or int(item.counters) < cost or (cost == 1 and not _v.stack.any(func(entry): return str(entry.kind) in ["roll", "effect_roll"]))
			col.move_child(button, col.get_child_count() - 2)
	elif Packet26.PAID.has(int(item.id)):
		_paid_buttons26(col, index, item, "activate")
	elif int(item.id) == 248:
		var kill := _button(col, "Сбросить 3 жетона → убить", "activate", {"item": index, "ability": "kill"})
		kill.disabled = not _can_use_item() or int(item.counters) < 3
		col.move_child(kill, col.get_child_count() - 2)
	elif ability in ["paid", "hybrid"]:
		var use := _item_condition_button(col, index, int(item.id))
		col.move_child(use, col.get_child_count() - 2)

func _paid_buttons26(col: VBoxContainer, index: int, item: Dictionary, action: String) -> void:
	var modes: Dictionary = Packet26.PAID.get(int(item.id), {})
	var seat: int = int(_v.seat)
	for mode in modes:
		var cost: Array = modes[mode]
		var label: String = "Заплатить %d¢" % int(cost[0]) if int(cost[0]) > 0 else ("Сбросить жетоны (%d)" % int(cost[1]) if int(cost[1]) > 0 else "Сбросить добычу (%d)" % int(cost[2]))
		if int(cost[0]) == 0 and int(cost[1]) == 0 and int(cost[2]) == 0:
			label = "Повернуть"
			if bool(item.get("tapped", false)) or bool(item.get("club_off28", false)):
				label = "Повёрнуто"
		var button := _button(col, label + " → " + str(cost[3]), action, {"item": index, "ability": mode})
		button.disabled = not _can_use_item() or int(_v.players[seat].coins) < int(cost[0]) or int(item.counters) < int(cost[1]) or _v.hand.size() < int(cost[2])
		if int(cost[2]) > 0 and _v.players[seat].items.any(func(entry): return int(entry.id) == 523):
			button.disabled = true
		if mode == "ibs_cancel26" and not _v.stack.any(func(entry): return str(entry.kind) in ["loot", "item"]):
			button.disabled = true
		if mode == "club_cancel28" and (bool(item.get("tapped", false)) or bool(item.get("club_off28", false)) or not _v.stack.any(func(entry): return str(entry.kind) in ["loot", "item"])):
			button.disabled = true
		col.move_child(button, col.get_child_count() - 2)

func _room_dialog20(index: int) -> void:
	var source: Dictionary = _v.extra_rooms20[index]
	if not bool(source.get("room_item20", false)):
		_native_room_dialog24(index, int(source.id))
		return
	var ability := _item_kind20(source) if bool(source.get("room_item20", false)) else "passive"
	var can_activate: bool = _v.seat == _v.current and _can_use_item() and ability in ["tap", "paid", "hybrid", "conditional"] and (ability == "paid" or not bool(source.get("tapped", false)))
	var col := _card_dialog(int(source.id), "Применить способность комнаты", "room_activate20", {"item": index}, can_activate)
	if int(source.id) in [44, 50] and bool(source.get("room_item20", false)):
		var paid := _paid_button21(col, index, source, "room_activate20")
		col.move_child(paid, col.get_child_count() - 2)
	elif Packet26.PAID.has(int(source.id)):
		_paid_buttons26(col, index, source, "room_activate20")
	var replace := _button(col, "Сменить эту комнату", "room", {"index": index})
	replace.disabled = _v.seat != _v.current or _v.phase != "turn"
	col.move_child(replace, col.get_child_count() - 2)
	if source.has("counters"):
		_note(col, "Жетонов: %d" % int(source.counters))

func _native_room_dialog24(index: int, id: int) -> void:
	var replace_arg: Variant = null if index < 0 else {"index": index}
	var can_replace: bool = _v.phase == "turn" and _v.seat == _v.current and bool(_v.dlc)
	if id == 758 and _v.shop.any(func(card): return int(card) >= 0):
		can_replace = false
	for entry: Dictionary in _v.get("native_room_actions24", []):
		if int(entry.index) != index:
			continue
		var attack_room: bool = id in [757, 778]
		var label: String = {755: "Повернуть → посмотреть сокровища", 757: "Атаковать комнату", 759: "Заплатить 2 здоровья → взять предмет", 760: "Заплатить 1 здоровье → получить 3¢", 761: "Заплатить 2¢ → выбрать сброс", 762: "Заплатить 3¢ → бросить кубик", 775: "Выбрать добычу для оплаты", 776: "Выбрать добычу для оплаты", 778: "Атаковать комнату", 780: "Заплатить 1 здоровье → бросить кубик", 784: "Заплатить 3¢ → бросить кубик", 785: "Выбрать добычу для оплаты", 801: "Заплатить 3¢ → бросить кубик", 805: "Заплатить 3¢ → бросить кубик"}.get(id, "Применить способность комнаты")
		var col := _card_dialog(id, label, "room_attack24" if attack_room else "room_activate24", {"index": index, "card": id}, bool(entry.attack) if attack_room else bool(entry.activate))
		var replace := _button(col, "Сменить комнату", "room", replace_arg)
		replace.disabled = not can_replace
		col.move_child(replace, col.get_child_count() - 2)
		return
	_card_dialog(id, "Сменить комнату", "room", replace_arg, can_replace)

func _switch(seat: int) -> void:
	_unlocked = -2; Net.fs_switch_seat(seat)
func _card(parent: Control,id: int,dimensions: Vector2,callback: Callable,charge_key: String = "") -> void:
	var button := Button.new(); button.custom_minimum_size = dimensions; button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("card_id", id)
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new()); button.add_theme_stylebox_override("hover",FSStyle.box(FSStyle.GOLD))
	var image := TextureRect.new(); image.texture = FSData.texture(id); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_round_image(image)
	if charge_key != "":
		image.material = _charge_material(charge_key)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); image.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(image)
	_support_badge(image, id)
	button.mouse_entered.connect(func(): _schedule_preview(id)); button.mouse_exited.connect(_hide_preview); button.pressed.connect(callback); parent.add_child(button)
	if charge_key != "":
		_fx_anchor28["k:" + charge_key] = button

## Компактная пометка до розыгрыша; подробная инструкция — рядом с крупным просмотром.
func _support_badge(parent: Control, id: int) -> void:
	var status := Support.status(id)
	if status == "auto":
		return
	var badge := FSStyle.label("Ч" if status == "partial" else "Р", FSStyle.CAP)
	badge.name = "CardSupportBadge"
	badge.position = Vector2(6, 6)
	badge.custom_minimum_size = Vector2(24, 24)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var background := FSStyle.box(FSStyle.COAL)
	background.set_content_margin_all(2)
	badge.add_theme_stylebox_override("normal", background)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(badge)

func _support_note(parent: Control, id: int, width: float) -> void:
	var status := Support.status(id)
	if status == "auto":
		return
	var text := ("Ч · Частично автоматически. " if status == "partial" else "Р · Вручную. ") + Support.hint(id)
	var note := FSStyle.label(text, FSStyle.CAP)
	note.name = "CardSupportHint"
	note.custom_minimum_size.x = width
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(note)

## Кто разряжен: повёрнутые предметы («i:место:id») и персонаж без заряда («c:место»).
func _collect_charge(view: Dictionary) -> Dictionary:
	var out := {}
	var players: Array = view.get("players", [])
	for seat in players.size():
		var p: Dictionary = players[seat]
		out["c:%d" % seat] = not bool(p.get("ready", true))
		for item: Dictionary in p.get("items", []):
			out["i:%d:%d" % [seat, int(item.id)]] = bool(item.get("tapped", false))
	return out


## Материал карты с зарядом: разряжена — ч/б; сменилось с прошлого состояния — плавный переход.
func _charge_material(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CHARGE_SHADER
	var now := bool(_charge_now.get(key, false))
	var was := bool(_charge_prev.get(key, now))
	var to := 1.0 if now else 0.0
	m.set_shader_parameter("gray", 1.0 if was else 0.0)
	if was != now:
		create_tween().tween_method(func(v: float): m.set_shader_parameter("gray", v), 1.0 - to, to,
			DISCHARGE_TIME if now else RECHARGE_TIME).set_trans(Tween.TRANS_SINE)
	return m


func _round_image(image: TextureRect) -> void:
	var corners := ShaderMaterial.new(); corners.shader=preload("res://hub/card_corners.gdshader"); image.material=corners
func _schedule_preview(id: int) -> void:
	_hide_preview()
	var token := _preview_token
	await get_tree().create_timer(0.375).timeout  # 06.11: вдвое быстрее
	if token == _preview_token:
		_show_preview(id)


func _show_preview(id: int) -> void:
	if preload("res://hub/card_magnifier.gd").offer(self):
		return
	if Net.paused or bool(_v.get("game_paused", false)):
		return
	_hide_preview()
	_preview = TextureRect.new(); _preview.texture = FSData.texture(id); _preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_round_image(_preview)
	_preview.position = Vector2(size.x*0.5-160,80); _preview.size = Vector2(320,minf(size.y-100,500)); _preview.mouse_filter = Control.MOUSE_FILTER_IGNORE; _preview.z_index = 70; add_child(_preview)  # 07.11: выше окон (65) — история сброса
	if Support.status(id) != "auto":
		var panel := FSStyle.panel()
		panel.name = "CardSupportPanel"
		panel.position = Vector2(332, 0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview.add_child(panel)
		_support_note(panel, id, 280)
func _hide_preview() -> void:
	_preview_token+=1
	if is_instance_valid(_preview): _preview.queue_free()
	_preview = null
## Стопка «СБРОС» (06.11): настоящий сброс всех колод — сверху последняя попавшая туда карта,
## под ней две предыдущие со сдвигом. Клик — история сброса партии.
func _played_pile(parent: Control, view: Dictionary) -> void:
	var feed: Array = view.get("discard_feed28", [])
	var col := FSStyle.vbox(4)
	col.name = "PlayedPile"
	parent.add_child(col)
	var caption := FSStyle.label("СБРОС", FSStyle.CAP)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caption)
	var pile := Control.new()
	pile.custom_minimum_size = Vector2(104 + 24, 128 + 12)
	pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pile)
	_fx_anchor28["pile"] = pile
	if feed.is_empty():
		var slot := Panel.new()
		var frame := FSStyle.box(Color(FSStyle.COAL, 0.35), Color(FSStyle.PAPER, 0.25))
		slot.add_theme_stylebox_override("panel", frame)
		slot.size = Vector2(104, 128)
		slot.position = Vector2(12, 0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pile.add_child(slot)
		var empty := FSStyle.label("пока пусто", FSStyle.CAP)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.6
		col.add_child(empty)
		return
	var shown := feed.slice(maxi(0, feed.size() - 3))
	for i in shown.size():
		var entry: Dictionary = shown[i]
		var depth := shown.size() - 1 - i  # 0 — верхняя карта
		var holder := Control.new()
		holder.position = Vector2(12 + depth * 8, depth * 6)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pile.add_child(holder)  # 07.11: старые добавляются раньше — новая карта рисуется сверху
		if depth == 0:
			_card(holder, int(entry.card), Vector2(104, 128), _played_history)
			var top: Control = holder.get_child(0)
			top.tooltip_text = "История сброса"
			if int(entry.get("n", 0)) > _pile_shown28 and _pile_shown28 >= 0 and _feed_seen28 >= 0:
				# карта ещё летит на стопку — показываем её после приземления
				top.modulate.a = 0.0
				var land := top.create_tween()
				land.tween_interval(1.95)  # 07.11: карта дольше в центре
				land.tween_property(top, "modulate:a", 1.0, 0.15)
			_pile_shown28 = int(entry.get("n", 0))  # 07.11: прятать до приземления один раз, не на каждой пересборке
		else:
			var image := TextureRect.new()
			image.texture = FSData.texture(int(entry.card))
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.size = Vector2(104, 128)
			image.modulate = Color(0.62, 0.58, 0.56)
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_round_image(image)
			holder.add_child(image)
	var count := FSStyle.label("%d карт" % feed.size() if feed.size() < 40 else "последние 40", FSStyle.CAP)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.modulate.a = 0.7
	col.add_child(count)


func _player_name(seat: int) -> String:
	var players: Array = _v.get("players", [])
	return str(players[seat].name) if seat >= 0 and seat < players.size() else "?"


func _play_kind_text(kind: String) -> String:
	return {"loot": "лут", "activate": "активация", "trigger": "условие"}.get(kind, kind)


## История сброса: новые сверху, у каждой карты — из какой колоды и на каком ходу.
func _played_history() -> void:
	var feed: Array = _v.get("discard_feed28", [])
	var col := _dialog()
	_note(col, "Сброс", FSStyle.H1)
	if feed.is_empty():
		_note(col, "Сброс пока пуст.")
		_close_button(col)
		return
	_note(col, "Последние %d карт в сбросе · наведите на карту, чтобы рассмотреть." % feed.size())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(size.x - 160, 760), minf(size.y - 260, 420))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(3, int(scroll.custom_minimum_size.x / 124.0))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	var piles := {"loot": "добыча", "treasure": "сокровища", "monster": "монстры", "room": "комнаты"}
	for index in range(feed.size() - 1, -1, -1):
		var entry: Dictionary = feed[index]
		var cell := FSStyle.vbox(4)
		grid.add_child(cell)
		_card(cell, int(entry.card), Vector2(104, 128), func(): _show_preview(int(entry.card)))
		var info := FSStyle.label("%s · ход %d" % [piles.get(str(entry.pile), str(entry.pile)), int(entry.get("round", 0))], FSStyle.CAP)
		info.custom_minimum_size.x = 104
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if index == feed.size() - 1:
			info.add_theme_color_override("font_color", FSStyle.GOLD.lightened(0.25))
		cell.add_child(info)
	_close_button(col)


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
	var image := TextureRect.new(); image.texture = FSData.texture(id); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(300, minf(size.y - 360, 330) if Support.status(id) != "auto" else minf(size.y - 240, 410))
	col.add_child(image)
	_round_image(image)
	_support_note(col, id, 460)
	var b := _button(col,caption,kind,arg,true); b.disabled = not enabled
	_close_button(col)
	return col
func _inventory(seat: int) -> void:
	var col := _dialog(); _note(col,str(_v.players[seat].name),FSStyle.H1)
	var row := FSStyle.hbox(8); col.add_child(row)
	_card(row,int(_v.players[seat].char),Vector2(120,165),func(): _show_preview(int(_v.players[seat].char)),"c:%d" % seat)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(500,220); scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; row.add_child(scroll)
	var item_row := FSStyle.hbox(8); scroll.add_child(item_row)
	for i in _v.players[seat].items.size():
		var item: Dictionary = _v.players[seat].items[i]
		var group := FSStyle.vbox(4); item_row.add_child(group)
		_card(group,int(item.id),Vector2(104,144),func(): _show_preview(int(item.id)),"i:%d:%d" % [seat, int(item.id)])
		_note(group,("Вечный · " if item.eternal else "") + ("Повёрнут" if item.tapped else "Готов") + " · %d" % int(item.counters))
		if not item.get("stored_cards20", []).is_empty():
			_note(group, "Карты под предметом")
			var stored := FSStyle.hbox(4)
			group.add_child(stored)
			for id in item.stored_cards20:
				_card(stored, int(id), Vector2(56, 76), func(): _show_preview(int(id)))
		if seat == _v.seat:
			var ability := _item_kind20(item)
			var use := _button(group,"Повернуть → эффект","activate",{"item":i,"tap":true})
			use.disabled = item.tapped or not _can_use_item() or not ability in ["tap","hybrid","conditional"]
			if Packet26.PAID.has(int(item.id)):
				var modes := FSStyle.button("Оплатить способность", FSStyle.CAP)
				modes.disabled = not _can_use_item()
				modes.pressed.connect(func(): _item_dialog(i))
				group.add_child(modes)
			else:
				_item_condition_button(group, i, int(item.id))
	var extra_scroll := ScrollContainer.new(); extra_scroll.custom_minimum_size = Vector2(500,108); extra_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; col.add_child(extra_scroll)
	var extra := FSStyle.hbox(8); extra_scroll.add_child(extra)
	for id in _v.players[seat].curses:
		_card(extra,int(id),Vector2(72,100),func(): _show_preview(int(id)))
	for soul in _v.players[seat].souls_cards:
		_card(extra,int(soul.id),Vector2(72,100),func(): _show_preview(int(soul.id)))
	for id in _v.players[seat].get("hand", []):
		_card(extra,int(id),Vector2(72,100),func(): _show_preview(int(id)))
	_close_button(col)
func _controls(col: Control) -> void:
	if bool(_v.get("starting_pending", false)):
		_note(col, "Завершите подготовку партии", FSStyle.H1)
		_note(col, "Применятся начальные свойства выбранного предмета, затем начнётся первый ход.")
		if _v.seat == _v.current:
			_button(col, "Начать первый ход", "finish_start", null, true)
		return
	if _v.phase == "starting_item":
		_note(col, "Предмет Эдема", FSStyle.H1)
		_note(col, "Выберите один из трёх. Он станет вечным; остальные вернутся под низ колоды.")
		if _v.seat == _v.actor:
			var choices := HFlowContainer.new()
			col.add_child(choices)
			for id in _v.get("starting_options", []):
				_card(choices, int(id), Vector2(80, 112), func(): _send("choose_starting_item", {"card": int(id)}))
		return
	if _v.phase in ["discard_target", "forced_discard"]:
		_note(col, FSData.title(int(_v.discard_choice.card)) + " · сброс лута", FSStyle.BODY)
		if _v.phase == "discard_target":
			_note(col, "Активный игрок выбирает, кто сбросит две карты.")
			if _v.seat == _v.current:
				for target in _v.players.size():
					_button(col, "Сбросить лут: " + str(_v.players[target].name), "discard_target", {"target": target})
		else:
			_note(col, "%s: осталось сбросить %d" % [_v.players[int(_v.actor)].name, int(_v.discard_choice.remaining)])
			if _v.seat == _v.actor:
				for index in _v.hand.size():
					var id: int = int(_v.hand[index])
					var discard_button := _button(col, "Сбросить №%d: %s" % [index + 1, FSData.title(id)], "forced_discard", {"item": index})
					discard_button.mouse_entered.connect(func(): _schedule_preview(id))
					discard_button.mouse_exited.connect(_hide_preview)
		return
	if _v.phase == "game_over":
		_note(col,"Четыре души!",FSStyle.H1); _note(col,"Победил «%s»" % _v.players[int(_v.winner)].name,FSStyle.BODY)
		if Net.is_host():
			var again := FSStyle.primary("Новая партия"); again.pressed.connect(Net.end_game); col.add_child(again)
		return
	_note(col,{"turn":"Ваши решения","priority":"Окно ответов","effect":"Выполнить эффект","battle_roll":"Бросок атаки","death":"Штраф за смерть","discard":"Сбросить до 10"}.get(_v.phase,_v.phase),FSStyle.BODY)
	_note(col,"Ход: " + str(_v.players[int(_v.current)].name) if _v.phase=="priority" else "Сейчас: " + str(_v.players[int(_v.actor)].name))
	_note(col,"В банке: %d¢" % int(_v.bank))
	if _v.seat >= 0 and _v.seat != _v.current and _v.phase != "game_over":
		_note(col, "Свои карты в чужой ход — только в ответ: пока стек не разрешился (5 с тишины)")
	if _v.seat >= 0 and int(_v.get("spider_tokens15", 0)) > 0 and _v.phase in ["turn", "priority", "battle_roll", "death"]:
		var spider := _button(col, "Повернуть персонажа → убрать паука", "remove_spider15")
		spider.disabled = not bool(_v.players[int(_v.seat)].ready)
	if _v.phase == "priority":
		for e in _v.stack:
			_note(col,FSData.effect_title(e))
		if bool(_v.get("strict_responses28", false)):
			_note(col,"Ответить можно %d с — таймер сверху; каждый ответ запускает его заново. Потом стек разрешится сам." % int(_v.get("response_window", 5)))
		else:
			_note(col,"Ответы — до следующего действия активного игрока; без ответов стек разрешится сам через %d с." % int(_v.get("response_window", 5)))
		if _v.stack.any(func(e): return e.kind in ["roll", "combat"]):
			_note(col, "Урон применится перед следующим броском, после ответов игроков.")
	if _v.phase == "priority" and int(_v.get("death_actor", -1)) == int(_v.seat) and _v.seat >= 0:
		_death_controls(col)
		return
	if bool(_v.get("effect_pending", false)):
		if _v.resolving.has("spawn_card"):
			_spawn_controls(col)
			return
		_note(col, FSData.title(int(_v.resolving.card)))
		_note(col, "Следующее действие по карте сначала разрешит сработавшие пассивы.")
		if _v.seat == int(_v.resolving.owner):
			_effect_controls(col)
		return
	if _v.phase in ["turn","priority"] and _v.seat == _v.current and _v.battle < 0 and int(_v.get("battle_player", -1)) < 0:
		if bool(_v.get("blind_only17", false)):
			_note(col, "Добавочная атака доступна только против колоды монстров.")
		_note(col,"Лут за ход: %d · персонаж %s" % [int(_v.free_loot),"готов" if _v.players[int(_v.seat)].ready else "повёрнут"])
		var required: int = int(_v.get("forced_deck_attacks", 0))
		var player_required: int = int(_v.get("required_player_attacks", 0))
		for index in _v.get("familiar_targets15", []).size():
			var target: Dictionary = _v.familiar_targets15[index]
			var familiar := _button(col, "Атаковать: " + FSData.title(int(target.card)) + " · " + str(_v.players[int(target.seat)].name), "attack_familiar15", {"index": index})
			familiar.disabled = _v.attacked or bool(_v.get("blind_only17", false)) or required > 0 or player_required > 0 or not _v.get("forced_monster_slots", []).is_empty()
		if not _v.get("player_attack_targets", []).is_empty() and _v.get("forced_monster_slots", []).is_empty():
			_note(col, "Атака игрока: выберите цель.")
			for target: int in _v.get("player_attack_targets", []):
				_button(col, "Атаковать игрока: " + str(_v.players[target].name) + " · %d+" % int(_v.get("player_attack_defense16", {}).get(target, 4)), "attack_player", {"target": target})
		if required > 0:
			_note(col, "Засада: ещё атак верха колоды — %d" % required)
		if not _v.get("forced_monster_slots", []).is_empty():
			_note(col, "Обязательная атака: выберите отмеченного монстра в ряду.")
		_button(col,"Закончить ход","end",null,true).disabled = required > 0 or player_required > 0 or not _v.get("forced_monster_slots", []).is_empty()
		var blind_attack := FSStyle.button("Атаковать верх колоды",FSStyle.CAP)
		blind_attack.disabled = not _v.get("forced_monster_slots", []).is_empty() or (_v.attacked and not bool(_v.get("gold_deck_attacks", false))) or (player_required > 0 and required == 0)
		blind_attack.pressed.connect(_choose_top_attack); col.add_child(blind_attack)
		var blind_price: int = int(_v.get("blind_price28", 10))
		_button(col,"Купить вслепую · %d¢" % blind_price,"buy",{"slot":-1}).disabled = _v.bought or int(_v.players[int(_v.seat)].coins) < blind_price
		if int(_v.get("discard_treasure", -1)) >= 0:
			_button(col, "Купить из сброса · %d¢" % int(_v.get("shop_price", 10)), "buy", {"slot": -2}).disabled = _v.bought
	elif _v.phase == "battle_roll":
		if int(_v.get("battle_player", -1)) >= 0:
			_note(col, "Атака: %s · защита4+" % str(_v.players[int(_v.battle_player)].name))
		_note(col,"Схватите кубик, потяните и отпустите, чтобы атаковать.")
	elif _v.phase == "effect":
		if _v.resolving.has("spawn_card"):
			_spawn_controls(col)
			return
		_note(col,FSData.title(int(_v.resolving.card)))
		if _v.resolving.kind == "reward":
			if bool(_v.resolving.get("post_reward_wait", false)):
				_note(col, "Ресурсы награды уже начислены. Выполните только текст после получения наград, затем продолжите.")
			else:
				_note(col, "Выполните только текст смерти. Напечатанная награда начислится автоматически после него." if _v.resolving.has("auto_reward") else "Начислите награды и души строго по убитой карте, затем завершите эффект.")
		var show := FSStyle.button("Прочитать карту",FSStyle.CAP); show.pressed.connect(func(): _show_preview(int(_v.resolving.card))); col.add_child(show)
		if _v.seat == _v.actor: _effect_controls(col)
	elif _v.phase == "death" and _v.seat == _v.actor: _death_controls(col)
	elif _v.phase == "discard": _note(col,"Нажимайте на лишние карты в руке, чтобы сбросить их.")
	if _v.seat >= 0 and _v.phase in ["turn","priority"]:
		var deal := FSStyle.button("Передать монеты",FSStyle.CAP); deal.pressed.connect(_trade); col.add_child(deal)
func _spawn_controls(col: Control) -> void:
	_note(col, "Разместите Утопца", FSStyle.BODY)
	_note(col, "Выберите ячейку вне боя. Живые нижние карты сохранятся.")
	if int(_v.seat) != int(_v.resolving.owner):
		_note(col, "Ждём выбора активного игрока.")
		return
	for slot: int in _v.get("spawn_slots", []):
		if slot < _v.monsters.size():
			_note(col, "Ячейка %d: %s" % [slot + 1, FSData.title(int(_v.monsters[slot].id))])
		_button(col, "Выложить Утопца · ячейка %d" % (slot + 1), "place_bloat", {"slot": slot})

func _effect_controls(col: Control) -> void:
	if bool(_v.get("card_automated", false)):
		_note(col, "Эффект выполняет игра. Выберите цель или вариант." if not _v.get("card_choices", []).is_empty() else "Бросьте кубик мышью." if bool(_v.get("card_roll_wait", false)) or _v.resolving.has("reroll_request") else "Эффект выполняется автоматически.")
		if not _v.get("card_choices", []).is_empty():
			var choose := FSStyle.primary("Выбрать цель / вариант")
			choose.pressed.connect(_card_choice_dialog)
			col.add_child(choose)
		return
	if _v.resolving.has("reward_soul_targets"):
		_note(col, "Выберите другого игрока: он получит эту карту души. Сокровища уже выданы активному игроку.")
		for target: int in _v.resolving.reward_soul_targets:
			_button(col, "Получает душу: " + str(_v.players[target].name), "reward_soul_target", {"target": target})
		return
	if bool(_v.resolving.get("reward_damage", false)):
		var damage: int = int(_v.resolving.auto_reward.damage_choice) * int(_v.get("reward_boost", 1))
		_note(col, "Выберите цель награды: %d урона." % damage)
		for target in _v.players.size():
			if not _v.players[target].dead and int(_v.players[target].hp) > 0:
				_button(col, "Урон игроку: " + str(_v.players[target].name), "reward_damage", {"zone": "player", "target": target})
		for slot in _v.monsters.size():
			if int(_v.monsters[slot].hp) > 0:
				_button(col, "Урон монстру: " + FSData.title(int(_v.monsters[slot].id)), "reward_damage", {"zone": "monster", "target": slot})
		return
	if _v.resolving.has("reward_winners"):
		_note(col, "Сердце Мамы: выберите победителя среди игроков с наибольшим количеством душ.")
		for target: int in _v.resolving.reward_winners:
			_button(col, "Побеждает: " + str(_v.players[target].name), "reward_winner", {"target": target})
		return
	if _v.resolving.has("auto_reward") and bool(_v.resolving.get("requires_reward_roll", false)) and not _v.resolving.has("reward_roll"):
		_note(col, "Добыча уже выдана. Бросьте кубик мышью: при1 или6 Тряпочник вернётся на верх колоды." if bool(_v.resolving.auto_reward.get("return_roll", false)) else "Бросьте кубик мышью. Игра автоматически начислит награду по итоговому результату; на бросок можно ответить.")
		return
	_note(col, "Нужно аварийное вмешательство. Хост может продолжить эффект через «Панель хоста».")
## Выбор в отдельном окне: кнопки не прячутся под нижней рукой.
func _card_choice_dialog() -> void:
	var col := _dialog()
	_popup.set_meta("card_choice_revision", int(_v.revision))
	_note(col, FSData.title(int(_v.resolving.card)), FSStyle.BODY)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(468, minf(440, maxf(160, size.y - 216)))
	col.add_child(scroll)
	var options := FSStyle.vbox(8)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(options)
	# 07.11 (владелец): просмотренные карты видны целиком — картинками, а не только названием.
	var peeked: Array = []
	for revealed: Dictionary in _v.peek.get("hands", []):
		peeked.append({"title": str(_v.players[int(revealed.seat)].name), "cards": revealed.cards})
	var deck_cards: Array = _v.peek.get("cards", []).filter(func(id): return int(id) not in _v.get("card_choice_previews", []))
	if not deck_cards.is_empty():
		peeked.append({"title": "", "cards": deck_cards})
	for group: Dictionary in peeked:
		if str(group.title) != "":
			_note(options, str(group.title))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		options.add_child(flow)
		for id in group.cards:
			_card(flow, int(id), Vector2(104, 146), func(): _show_preview(int(id)))
	for index in _v.get("card_choices", []).size():
		var card_id: int = int(_v.get("card_choice_previews", [])[index]) if index < _v.get("card_choice_previews", []).size() else -1
		var holder: Control = options
		if card_id >= 0:
			var line := FSStyle.hbox(8)
			options.add_child(line)
			_card(line, card_id, Vector2(64, 90), func(): _show_preview(card_id))
			holder = line
		var option := _button(holder, str(_v.card_choices[index]), "card_choice", {"index": index, "revision": int(_v.revision)})
		option.clip_text = true
		option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if card_id >= 0:
			option.mouse_entered.connect(func(): _schedule_preview(card_id))
			option.mouse_exited.connect(_hide_preview)
	_close_button(col)

func _death_controls(col: Control) -> void:
	_note(col,"До принятия штрафа игроки могут ответить лутом или способностью.")
	_note(col,"Потеряйте 1¢, одну карту лута и один невечный предмет.")
	var loot := OptionButton.new()
	for id in _v.hand: loot.add_item(FSData.title(int(id)),int(id))
	col.add_child(loot)
	var item := OptionButton.new()
	for i in _v.players[int(_v.seat)].items.size():
		var data: Dictionary = _v.players[int(_v.seat)].items[i]
		if not data.eternal and (int(_v.get("shadow_item15", -1)) < 0 or i == int(_v.shadow_item15)):
			item.add_item(FSData.title(int(data.id)), i)
	col.add_child(item)
	var pay := FSStyle.primary("Принять штраф")
	pay.pressed.connect(func(): _send("death",{"loot":loot.get_selected_id() if loot.item_count else -1,"item":item.get_selected_id() if item.item_count else -1})); col.add_child(pay)

func _trade() -> void:
	var col := _dialog(); _note(col,"Передать монеты",FSStyle.H1)
	var target := OptionButton.new()
	for i in _v.players.size():
		if i != _v.seat: target.add_item(str(_v.players[i].name),i)
	col.add_child(target)
	var amount := SpinBox.new(); amount.min_value = 1; amount.max_value = maxi(1,int(_v.players[int(_v.seat)].coins)); amount.value = 1; col.add_child(amount)
	var send := FSStyle.primary("Передать"); send.pressed.connect(func(): _send("trade",{"target":target.get_selected_id(),"amount":int(amount.value)})); col.add_child(send); _close_button(col)

func _bonus_dialog(id: int) -> void:
	var col := _dialog()
	_note(col, FSData.title(id), FSStyle.H1)
	_note(col, "Получателя выбирает активный игрок после выполнения условия карты.")
	var eligible: Array = _v.get("bonus_targets", {}).get(id, [])
	if eligible.is_empty():
		_note(col, "Условие ещё не выполнено или получение душ запрещено.")
	for seat in eligible:
		var button := _button(col, "Отдать душу · " + str(_v.players[int(seat)].name), "claim", {"card": id, "target": int(seat)})
		button.disabled = _v.seat != _v.current or _v.phase not in ["turn", "priority"]
	_close_button(col)
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
	return effect.kind in ["attack", "player_attack", "player_combat", "forced_discard", "roll", "combat", "effect_roll", "monster_death", "death", "monster_trigger"]


## Атакуемый монстр: текущий бой или объявленная атака в стеке.
func _is_target28(view: Dictionary, slot: int) -> bool:
	if int(view.get("battle", -1)) == slot:
		return true
	return view.get("stack", []).any(func(e): return str(e.get("kind", "")) == "attack" and int(e.get("slot", -2)) == slot)


## Индикаторы после перестройки стола: изменения ресурсов (по разнице состояний) и лента fx28 с хоста.
func _show_fx28(prev: Dictionary, view: Dictionary) -> void:
	var events: Array = view.get("fx28", [])
	var newest := _fx_seen28
	for entry: Dictionary in events:
		newest = maxi(newest, int(entry.get("n", -1)))
	if prev.is_empty() or not _fx_ready28:
		_fx_seen28 = newest  # первое состояние: старые события не проигрываем
		_fx_ready28 = true
		if is_inside_tree():
			await get_tree().process_frame
			await get_tree().process_frame
			_remember_rects28()
		return
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_same(view, _v):
		return  # пришло новое состояние — его индикаторы покажет следующий вызов
	for entry: Dictionary in events:
		if int(entry.get("n", -1)) <= _fx_seen28:
			continue
		match str(entry.get("kind", "")):
			"trigger":
				var node := _card_node28(int(entry.get("seat", -1)), int(entry.get("card", -1)))
				FX.flash(_fx_layer28, node)
			"roll":
				FX.float_text(_fx_layer28, _fx_anchor28.get("p%d" % int(entry.get("seat", -1))), int(entry.get("amount", 0)), " к броску", 3)
				if int(entry.get("card", -1)) >= 0:
					FX.float_text(_fx_layer28, _card_node28(int(entry.get("seat", -1)), int(entry.card)), int(entry.get("amount", 0)))
	_fx_seen28 = newest
	_diff_fx28(prev, view)
	_fly_cards28(prev, view)


## Полёт карт (06.11): разыгранная добыча — крупно в центре, затем на «СБРОС»; активация — в центре и гаснет;
## погибший монстр и прочие карты из ленты сброса летят со своего места на стопку.
func _fly_cards28(prev: Dictionary, view: Dictionary) -> void:
	var pile: Control = _fx_anchor28.get("pile")
	var pile_rect := Rect2()
	if is_instance_valid(pile):
		var r := pile.get_global_rect()
		pile_rect = Rect2(r.position + Vector2(12, 0), Vector2(104, 128))
	var flown := {}
	for entry: Dictionary in view.get("played", []):
		var no: int = int(entry.get("no", 0))
		if no <= _fly_seen28:
			continue
		var kind := str(entry.get("kind", ""))
		if kind == "loot":
			FX.fly_card(_fx_layer28, FSData.texture(int(entry.card)), Rect2(), pile_rect)
			flown[int(entry.card)] = true
		elif kind == "activate":
			FX.fly_card(_fx_layer28, FSData.texture(int(entry.card)), Rect2(), Rect2(), 1.0)
	var old_monsters: Array = prev.get("monsters", [])
	var now_ids: Array = view.get("monsters", []).map(func(m): return int(m.id))
	for entry: Dictionary in view.get("discard_feed28", []):
		if int(entry.get("n", 0)) <= _feed_seen28 or flown.has(int(entry.card)):
			continue
		for slot in old_monsters.size():
			if int(old_monsters[slot].id) == int(entry.card) and int(entry.card) not in now_ids and _rects28.has("m%d" % slot):
				FX.fly_card(_fx_layer28, FSData.texture(int(entry.card)), _rects28["m%d" % slot], pile_rect, 0.0)
				break
	_remember_rects28()


func _remember_rects28() -> void:
	_rects28.clear()
	for key in _fx_anchor28:
		var node: Control = _fx_anchor28[key]
		if is_instance_valid(node) and node.is_inside_tree():
			_rects28[key] = node.get_global_rect()
	var played: Array = _v.get("played", [])
	_fly_seen28 = int(played.back().get("no", 0)) if not played.is_empty() else maxi(_fly_seen28, 0)
	var feed: Array = _v.get("discard_feed28", [])
	_feed_seen28 = int(feed.back().get("n", 0)) if not feed.is_empty() else maxi(_feed_seen28, 0)


func _diff_fx28(prev: Dictionary, view: Dictionary) -> void:
	var before: Array = prev.get("players", [])
	var after: Array = view.get("players", [])
	for i in mini(before.size(), after.size()):
		var a: Dictionary = before[i]
		var b: Dictionary = after[i]
		var row: Control = _fx_anchor28.get("p%d" % i)
		var bar: Control = _fx_anchor28.get("ph%d" % i, row)
		var lane := 0
		if bool(b.get("dead", false)) and not bool(a.get("dead", false)):
			FX.float_label(_fx_layer28, row, "СМЕРТЬ", FX.BAD, 0, 26)
			FX.flash(_fx_layer28, row, FX.BAD)
			continue
		FX.float_text(_fx_layer28, bar, int(b.hp) - int(a.hp), " ХП", lane)
		if int(b.max_hp) != int(a.max_hp):
			lane += 1
			FX.float_text(_fx_layer28, bar, int(b.max_hp) - int(a.max_hp), " макс. ХП", lane)
		if int(b.attack) != int(a.attack):
			lane += 1
			FX.float_text(_fx_layer28, row, int(b.attack) - int(a.attack), " ⚔", lane)
		if int(b.coins) != int(a.coins):
			lane += 1
			FX.float_text(_fx_layer28, row, int(b.coins) - int(a.coins), "¢", lane)
		if int(b.souls) > int(a.souls):
			FX.float_label(_fx_layer28, row, "+%d душа" % (int(b.souls) - int(a.souls)), FX.GLOW, lane + 1, 24)
			FX.flash(_fx_layer28, row, FX.GLOW)
		elif int(b.souls) < int(a.souls):
			FX.float_label(_fx_layer28, row, "−%d душа" % (int(a.souls) - int(b.souls)), FX.BAD, lane + 1, 24)
		if int(b.get("hand_count", 0)) > int(a.get("hand_count", 0)):
			FX.float_label(_fx_layer28, row, "+%d добыча" % (int(b.hand_count) - int(a.hand_count)), Color(0.55, 0.8, 1.0), lane + 2, 18)
		if (b.get("items", []) as Array).size() > (a.get("items", []) as Array).size():
			FX.float_label(_fx_layer28, row, "+ предмет", Color(0.55, 0.8, 1.0), lane + 3, 18)
		if (b.get("curses", []) as Array).size() > (a.get("curses", []) as Array).size():
			FX.float_label(_fx_layer28, row, "проклятие!", Color(0.78, 0.5, 1.0), lane + 3, 20)
	var old_monsters: Array = prev.get("monsters", [])
	var new_monsters: Array = view.get("monsters", [])
	for slot in mini(old_monsters.size(), new_monsters.size()):
		var a: Dictionary = old_monsters[slot]
		var b: Dictionary = new_monsters[slot]
		if int(a.get("id", -1)) != int(b.get("id", -2)):
			continue
		var group: Control = _fx_anchor28.get("m%d" % slot)
		if int(b.hp) <= 0 and int(a.hp) > 0:
			FX.float_label(_fx_layer28, group, "УБИТ!", FX.GLOW, 0, 26)
			FX.flash(_fx_layer28, group, FX.BAD)
			continue
		FX.float_text(_fx_layer28, group, int(b.hp) - int(a.hp), " ХП")
		if int(b.get("at", 0)) != int(a.get("at", 0)):
			FX.float_text(_fx_layer28, group, int(b.at) - int(a.at), " ⚔", 1)
		if int(b.get("dc", 0)) != int(a.get("dc", 0)):
			FX.float_text(_fx_layer28, group, int(b.dc) - int(a.dc), " защита", 2)


## Узел сработавшей карты: свой ряд «В игре», открытые предметы ходящего, иначе — персонаж в списке игроков.
func _card_node28(seat: int, card: int) -> Control:
	if seat == int(_v.get("seat", -1)) and is_instance_valid(_own_fan):
		for key in ["item:%d" % card, "character:%d" % seat]:
			if _own_fan._cards.has(key) and (key.begins_with("item") or int(_v.players[seat].char) == card):
				return _own_fan._cards[key]
	var node: Control = _fx_anchor28.get("k:i:%d:%d" % [seat, card])
	if node == null:
		node = _fx_anchor28.get("k:c:%d" % seat)
	return node
