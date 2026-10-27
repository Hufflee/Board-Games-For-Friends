## Low: отмена/замена/удаление общего CardFlip, без Net/игровой логики.
extends SceneTree
var checks := 0
var errors := 0
var shown := true
var commits := 0
var gate := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var helper: Script = load("res://hub/card_flip.gd")
	var card := ColorRect.new()
	card.position = Vector2(80, 90)
	card.size = Vector2(120, 150)
	card.scale = Vector2(1.2, 0.9)
	card.rotation = 0.23
	card.pivot_offset = Vector2(17, 29)
	root.add_child(card)
	var flip: Node = helper.attach(card, func(up: bool): shown = up, true, true)
	flip.flipped.connect(func(_up: bool): commits += 1)
	var position := card.position
	var scale_before := card.scale
	var rotation := card.rotation
	var pivot := card.pivot_offset
	for progress in [0.25, 0.75]:
		flip.flip_to(false, 0.2)
		# Явная граница визуального прогресса; настоящий tween остаётся запущенным до cancel.
		flip._apply(progress)
		check(shown == (progress < 0.5), "Граница смены картинки до/после середины")
		flip.cancel()
		check(shown and flip.face_up and not flip.busy and not flip.dragging and flip.progress == 0.0, "Cancel возвращает исходную сторону и снимает busy")
		check(card.position == position and card.scale == scale_before and card.rotation == rotation and card.pivot_offset == pivot, "Cancel восстанавливает все4 transform поля")
		await create_timer(0.3).timeout
		check(commits == 0 and shown, "Убитый tween не вызывает старый commit после cancel")
	flip.flip_to(false, 0.2)
	flip._apply(0.75)
	flip.set_face(true)
	await create_timer(0.3).timeout
	check(shown and flip.face_up and commits == 0, "Set_face перебивает незавершённый flip без старого callback")
	flip.flip_to(false, 0.15)
	flip.flip_to(true, 0.15)
	await create_timer(0.25).timeout
	check(shown and not flip.busy and commits == 0, "Новая цель отменяет прежнюю, не коммитит старую сторону")
	flip.can_interact = func() -> bool: return gate
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(1, 50)
	press.global_position = card.get_global_transform() * press.position
	flip._gui_input(press)
	check(not flip.dragging and not flip.busy, "Guard false запрещает ручной захват")
	gate = true
	flip._gui_input(press)
	check(flip.dragging, "Guard true разрешает захват края")
	gate = false
	var motion := InputEventMouseMotion.new()
	flip._gui_input(motion)
	check(not flip.dragging and not flip.busy and shown, "Отзыв прав на следующем input отменяет drag")
	flip.interactive_enabled = false
	gate = true
	flip._gui_input(press)
	check(not flip.busy, "Manual=false запрещает жест независимо от guard")
	flip.flip_to(false, 0.1)
	await create_timer(0.2).timeout
	check(not shown and commits == 1, "Manual=false не запрещает автоматический NH-переворот")
	# Пересборка заменяет карту, не оставляя старый tween/callback.
	flip.flip_to(true, 0.2)
	card.queue_free()
	await process_frame
	await process_frame
	var count := commits
	var replacement := ColorRect.new()
	root.add_child(replacement)
	var next_shown := [false]
	var next: Node = helper.attach(replacement, func(up: bool): next_shown[0] = up, false, false)
	await create_timer(0.3).timeout
	check(not is_instance_valid(card) and commits == count and not next_shown[0], "Удалённая карта не вызывает старый callback и не меняет замену")
	next.flip_to(true, 0.1)
	await create_timer(0.2).timeout
	check(next_shown[0] and not next.busy, "Замена после удаления работает самостоятельно")
	replacement.queue_free()
	await process_frame
	print("CARD FLIP LOW: checks=", checks, " errors=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
