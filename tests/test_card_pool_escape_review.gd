## Отдельный контроль настоящего ESC/ui_cancel при фокусе поиска и без него.
extends "res://tests/test_card_pool_review.gd"

func _run() -> void:
	Net.leave()
	var app: Control = load("res://games/brodilka/ui/main.tscn").instantiate()
	get_tree().root.add_child(app)
	get_tree().current_scene = app
	app.show_card_pool()
	await settle()
	var browser: Control = app.get_node("CardPool")
	await click(browser._query)
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	print("ESC PROBE action_ui_cancel=", event.is_action_pressed("ui_cancel"), " focus_before=", browser._query.has_focus())
	await escape()
	print("ESC PROBE first_closed=", not app.has_node("CardPool"))
	if app.has_node("CardPool"):
		print("ESC PROBE focus_after_first=", browser._query.has_focus())
		browser._query.release_focus()
		await escape()
		print("ESC PROBE after_release_closed=", not app.has_node("CardPool"))
	get_tree().current_scene = self
	app.queue_free()
	await settle()
	await Sfx.request_quit()
