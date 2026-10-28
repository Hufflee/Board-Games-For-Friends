## Настоящие InputEvents голосов Чернил/паузы. Только подготовленный UI, без сети.
## Graphical --audio-driver Dummy --script res://tests/test_phantom_ink_votes_ui_review.gd, свой APPDATA.
extends SceneTree
var net: Node
var app: Control
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func settle() -> void:
	await create_timer(0.18).timeout

func buttons(node: Node, target: String = "") -> Array[Button]:
	var result: Array[Button] = []
	if node is Button and node.is_visible_in_tree() and not node.is_queued_for_deletion():
		if (target == "vote" and node.tooltip_text == "Голосовать за вопрос / снять свой голос") or node.text == target:
			result.append(node)
	for child in node.get_children(): result.append_array(buttons(child, target))
	return result

func click(control: Control) -> void:
	check(control != null, "Цель настоящего клика существует")
	if control == null: return
	var at := control.get_global_rect().get_center()
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()

func seat(index: int) -> void:
	net.pi_switch_seat(index)
	await settle()
	var curtain := buttons(app, "Я готов · открыть мой экран")
	check(curtain.size() == 1, "Личный экран закрыт до подтверждения места")
	if curtain.size() == 1: await click(curtain[0])

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.my_name = "Тест медиума"
	net.host_offline("phantom_ink")
	net.set_bots(5)
	net.settings.pi_roles = [0, 0, 1, 2, 2, 3]
	check(net.start_game() == "", "Подготовлен настоящий стол с двумя медиумами на команду")
	net.set_process(false)
	# Воспроизводимый seed и штатный выбор предмета; ни подсказки, ни голосов заранее нет.
	net.phantom.new_game(net.phantom.players, [0, 0, 1, 2, 2, 3], 281028)
	check(net.phantom.action(2, "object", 0) and net.phantom.action(5, "object", 0), "Оба духа штатно выбрали предмет")
	net._push_state()
	app = load("res://games/phantom_ink/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	await seat(0)
	var hand: Array = net.phantom.hands[0].duplicate()
	var votes := buttons(app, "vote")
	check(votes.size() == 7, "Медиум видит7 настоящих кнопок голосования")
	if votes.size() != 7:
		await finish()
		return
	await click(votes[0])
	check(net.phantom.get_view(0).own_question_votes == [hand[0]], "Мышь отдала голос серверу")
	await click(buttons(app, "vote")[1])
	check(net.phantom.get_view(0).own_question_votes.size() == 2, "Второй голос принят мышью")
	var revision: int = net.phantom.revision
	await click(buttons(app, "vote")[2])
	check(net.phantom.revision == revision and net.phantom.get_view(0).own_question_votes.size() == 2, "Третий мышиный голос отклонён сервером")
	await click(buttons(app, "vote")[0])
	await click(buttons(app, "vote")[2])
	check(net.phantom.get_view(0).own_question_votes == [hand[1], hand[2]], "Мышью можно снять и сменить голос")
	await seat(1)
	check(buttons(app, "vote")[1].text == "♥ 1", "Второй медиум видит счётчик команды в UI")
	await click(buttons(app, "vote")[1])
	check(buttons(app, "vote")[1].text == "♥ 2" and buttons(app, "vote")[1].theme_type_variation == "PrimaryButton", "UI показывает общий счёт2 и выделяет свой голос")
	# Пауза штатная Net; проверяем и физический клик под overlay, и отказ серверного маршрута.
	net.set_paused(true)
	await settle()
	var before: Array = net.phantom.question_votes.duplicate(true)
	revision = net.phantom.revision
	await click(buttons(app, "vote")[0])
	check(net.phantom.question_votes == before and net.phantom.revision == revision, "Пауза блокирует настоящее нажатие голоса")
	net.send_action("question_vote", int(hand[0]))
	check(net.phantom.question_votes == before and net.phantom.revision == revision, "На паузе сервер тоже отклоняет действие")
	net.set_paused(false)
	await settle()
	await click(buttons(app, "vote")[0])
	check(net.phantom.get_view(1).own_question_votes.size() == 2, "После снятия паузы голос снова принимается")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/batch28_ink_votes/medium-view.png")
	await seat(2)
	check(buttons(app, "vote").is_empty() and net.view.question_votes.is_empty() and net.view.own_question_votes.is_empty(), "Дух не видит кнопки и закрытые счётчики")
	await seat(3)
	check(buttons(app, "vote").is_empty() and net.view.question_votes.is_empty(), "Другая команда не видит голосов активной команды")
	await seat(0)
	check(buttons(app, "vote")[1].text == "♥ 2" and net.view.own_question_votes == [hand[1], hand[2]], "Возврат места сохраняет общие счётчики и только свои голоса")
	await finish()

func finish() -> void:
	print("INK VOTES LOW UI: checks=", checks, " errors=", errors)
	net.leave()
	app.queue_free()
	current_scene = null
	await settle()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
