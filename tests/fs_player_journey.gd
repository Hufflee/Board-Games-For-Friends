extends SceneTree
## Полная партия через интерфейс без подмены игрового состояния.
## APPDATA должен быть изолирован. Сложные награды подтверждаются планом по прочитанной карте.
const OUT := "res://build/fs_acceptance/"
var app: Control
var table: Control
var net: Node
var steps := 0
var errors := 0
var rows: Array = []
var counts := {}
var log_file: FileAccess

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 3) -> void:
	for i in count:
		await process_frame

func note(action: String, expected: String, actual: String, ok: bool = true) -> void:
	var row := {"step": steps, "action": action, "expected": expected, "actual": actual, "ok": ok}
	rows.append(row)
	counts[action] = int(counts.get(action, 0)) + 1
	log_file.store_line(JSON.stringify(row))
	log_file.flush()
	if not ok:
		errors += 1
		push_error(action + ": " + actual)
	print("JOURNEY ", steps, " ", action, " -> ", actual)

func find_button(text: String) -> Button:
	for node: Button in root.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree() and not node.disabled:
			return node
	return null

func mouse(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	await frames(2)

func click(control: Control, corner: bool = false) -> bool:
	if not is_instance_valid(control):
		note("Доступность кнопки", "Нужное действие доступно", "Кнопка не найдена", false)
		return false
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await frames(3)
	var rect := control.get_global_rect()
	var at := rect.position + Vector2(12, 25) if corner else rect.get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await frames(2)
	# Карта при наведении поднимается; дождаться её новой позиции.
	if corner:
		await create_timer(0.18).timeout
		at = control.get_global_rect().position + Vector2(12, 25)
	await mouse(at, true)
	await mouse(at, false)
	return true

func press(text: String) -> bool:
	return await click(find_button(text))

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")

func unlock(seat: int) -> void:
	if int(table._v.seat) != seat:
		var selects := table.find_children("*", "OptionButton", true, false)
		# Первый переключатель — обычный hotseat-выбор игрока.
		var selector: OptionButton = selects[0]
		selector.select(seat)
		selector.item_selected.emit(seat)
		await frames()
	if find_button("Открыть мою руку") != null:
		await press("Открыть мою руку")
		await frames()

func own_fan() -> Control:
	for fan: Control in table.find_children("*", "Control", true, false):
		if fan.get_script() != null and fan.get_script().resource_path == "res://hub/private_hand.gd" and fan.movable:
			return fan
	return null

func play_loot(id: int) -> void:
	var before: int = table._v.revision
	var fan := own_fan()
	await click(fan._cards["loot:%d" % id], true)
	await press("Сыграть лут" if table._v.phase != "discard" else "Сбросить")
	note("Разыграть лут" if table._v.phase != "discard" else "Сбросить лишнюю карту",
		"Карта покидает руку, состояние обновляется", "%s; revision %d→%d" % [FSData.title(id), before, table._v.revision],
		int(table._v.revision) > before)

func roll() -> void:
	for i in 800:
		if table._die.visible and table._die.draggable and table._die.state == "waiting":
			break
		await process_frame
	if not table._die.draggable:
		note("Бросить кубик", "Разрешённый бросок доступен", "Кубик не вернулся: " + table._die.state, false)
		return
	var before: int = table._v.roll_no
	await mouse(table._die.center(), true)
	var motion := InputEventMouseMotion.new()
	motion.position = table._die.center() + Vector2(-85, -22)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await frames(2)
	await mouse(motion.position, false)
	note("Бросить кубик", "Один жест — один бросок, либо сначала ручной ответ/награда",
		"roll_no %d→%d; фаза %s; кубик %s" % [before, table._v.roll_no, table._v.phase, table._die.state],
		int(table._v.roll_no) == before + 1 or table._v.phase in ["effect", "death", "turn", "game_over"])
	if int(table._v.roll_no) == before + 1:
		var blocked: bool = not table._die.draggable
		await mouse(table._die.center(), true)
		await mouse(table._die.center(), false)
		note("Повторно нажать летящий кубик", "Второй бросок не отправлен",
			"roll_no=%d, блокировка=%s" % [table._v.roll_no, blocked], blocked and int(table._v.roll_no) == before + 1)

func choose_monster() -> int:
	var best := 0
	var score := INF
	for i in table._v.monsters.size():
		var monster: Dictionary = table._v.monsters[i]
		if FSData.card(int(monster.id)).key in ["stoney", "deathshead"]:
			continue
		var difficulty := float(monster.hp) * float(monster.at) / maxf(1, 7 - int(monster.dc))
		if difficulty < score:
			score = difficulty
			best = i
	return best

func attack() -> void:
	var slot := choose_monster()
	var health: Control = table.find_child("MonsterHealth%d" % slot, true, false)
	var id: int = table._v.monsters[slot].id
	await click(health.get_parent().get_child(0))
	await press("Атаковать")
	note("Атаковать открытого монстра", "Открывается окно ответов и доступен бросок",
		"%s; фаза %s" % [FSData.title(id), table._v.phase], table._v.phase == "priority")

func manual_effect() -> void:
	var effect: Dictionary = table._v.resolving.duplicate(true)
	var id: int = effect.card
	var request_path := OUT + "request.json"
	var reply_path := OUT + "reply.json"
	if FileAccess.file_exists(reply_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(reply_path))
	var request := FileAccess.open(request_path, FileAccess.WRITE)
	request.store_string(JSON.stringify({"step":steps,"effect":effect,"card":FSData.card(id),"view":table._v}))
	request.close()
	await press("Прочитать карту")
	await snap("manual-card")
	print("NEEDS CARD PLAN: ", steps, " ", id, " ", FSData.title(id), " ", effect.kind)
	while not FileAccess.file_exists(reply_path):
		await create_timer(0.3).timeout
	var plan: Array = JSON.parse_string(FileAccess.get_file_as_string(reply_path))
	table._hide_preview()
	for operation: Dictionary in plan:
		if bool(operation.get("roll", false)):
			await roll()
			while table._v.phase == "priority" and table._pending_effect_roll():
				await roll()
			note("Бросок по награде карты", "Результат получен жестом мыши", "Выпало %d" % int(table._v.last_roll))
			continue
		var options := table.find_children("*", "OptionButton", true, false)
		var target: OptionButton = options[options.size() - 2]
		var op: OptionButton = options[options.size() - 1]
		target.select(int(operation.get("target", table._v.actor)))
		for i in table.OPS.size():
			if table.OPS[i][0] == operation.op:
				op.select(i)
		var spins := table.find_children("*", "SpinBox", true, false)
		spins[0].value = int(table._v.last_roll) if operation.get("amount") is String and operation.amount == "last_roll" else int(operation.get("amount", 1))
		spins[1].value = int(operation.get("item", 0)) + 1
		var before: int = table._v.revision
		await press("Применить")
		note("Выполнить эффект по тексту карты", "Применяется выбранная операция без пропуска выбора",
			"%s: %s" % [FSData.title(id), JSON.stringify(operation)], table._v.revision > before)
		if table._v.phase == "game_over":
			break
	if table._v.phase == "effect":
		await press("Эффект выполнен")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(reply_path))

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.title = "FS ACCEPTANCE UI"
	var pid_file := FileAccess.open(OUT + "ui-pid.txt", FileAccess.WRITE)
	pid_file.store_string(str(OS.get_process_id()))
	pid_file.close()
	Engine.time_scale = 3.0
	Engine.max_fps = 60
	log_file = FileAccess.open(OUT + "ui-actions.jsonl", FileAccess.WRITE)
	net = root.get_node("Net")
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	app = current_scene
	await frames(10)
	root.size = Vector2i(1280, 720)
	await create_timer(0.4).timeout
	if find_button("Закрыть") != null:
		await press("Закрыть")
		await frames(5)
	await press("Играть на одном компьютере")
	await create_timer(0.6).timeout
	await snap("setup-local")
	print("SETUP MODE: ", net.mode, " LOBBY: ", net.lobby_view)
	if net.mode != "offline":
		await press("Играть на одном компьютере")
		await create_timer(0.6).timeout
	await press("− Игрок")
	await press("− Игрок")
	await press("Спуститься в подвал")
	await frames(15)
	table = app.screen
	note("Начать партию из меню", "Два игрока, 3 монеты, персонажи, стартовые руки и два монстра",
		"Игроков %d, монстров %d, магазин %d" % [table._v.players.size(), table._v.monsters.size(), table._v.shop.size()],
		table._v.players.size() == 2 and table._v.monsters.size() == 2 and table._v.shop.size() == 2)
	await unlock(int(table._v.actor))
	await snap("start")
	await press("Пауза")
	await create_timer(0.5).timeout
	note("Поставить паузу", "Стол на паузе, доступно продолжение", "Пауза=" + str(net.paused), net.paused)
	await press("Продолжить игру")
	await create_timer(0.5).timeout
	note("Продолжить игру", "Пауза снята", "Пауза=" + str(net.paused), not net.paused)
	while table._v.phase != "game_over" and steps < 1800 and errors == 0:
		steps += 1
		await unlock(int(table._v.current) if table._v.phase in ["turn", "priority", "battle_roll", "discard"] else int(table._v.actor))
		var view: Dictionary = table._v
		if steps % 10 == 0:
			await snap("latest")
		match str(view.phase):
			"turn", "priority":
				if view.phase == "priority" and (view.battle >= 0 or view.stack.any(func(e): return e.kind == "attack")):
					await roll()
				else:
					var loot := -1
					if int(view.free_loot) > 0 or bool(view.players[int(view.seat)].ready):
						for id in view.hand:
							if str(FSData.card(int(id)).lua.get("type", "")) in ["1c", "2c", "3c", "4c", "5c", "lsoul", "trinkets"]:
								loot = int(id)
								break
					if loot >= 0:
						await play_loot(loot)
					elif not view.bought and int(view.players[int(view.seat)].coins) >= 10 and view.phase == "turn" and view.claimed.has(689):
						await press("Купить вслепую · 10¢")
						note("Купить сокровище", "Покупка ждёт ответов", "Фаза: " + table._v.phase, table._v.phase == "priority")
					elif not view.attacked and view.claimed.has(689) and view.claimed.has(691):
						await attack()
					else:
						var before: int = view.current
						await press("Закончить ход")
						note("Закончить ход", "Ход передан или сначала разрешаются ответы/лишняя рука",
							"Игрок %d→%d, фаза %s" % [before, table._v.current, table._v.phase])
			"battle_roll":
				await roll()
			"effect":
				await manual_effect()
			"death":
				var seat: int = view.actor
				var money: int = view.players[seat].coins
				await press("Принять штраф")
				note("Принять штраф за смерть", "Потеря лута/невечного предмета/1 монеты, переход хода",
					"До: %d монет, после: %d; фаза %s" % [money, table._v.players[seat].coins, table._v.phase],
					table._v.players[seat].coins == maxi(0, money - 1))
			"discard":
				await play_loot(int(view.hand[0]))
			_:
				note("Продолжить партию", "Есть доступное действие", str(view.phase), false)
		await frames(3)
	await snap("finish" if table._v.phase == "game_over" else "failure")
	note("Завершить полноценную партию", "Победитель с четырьмя душами и кнопка новой партии",
		"Фаза %s, победитель %s, раунд %s, действий %d" % [table._v.phase, table._v.winner, table._v.round_no, steps],
		table._v.phase == "game_over" and table._v.winner >= 0 and find_button("Новая партия") != null)
	var output := FileAccess.open(OUT + "ui-summary.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"errors": errors,"steps":steps,"counts":counts,"final":table._v}, "\t"))
	output.close()
	print("UI JOURNEY FINISHED: ", steps, " / errors ", errors)
	quit(1 if errors else 0)
