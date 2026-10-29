extends "res://tests/test_focus29_remaining.gd"
## Адресный повтор неизменённых15проверок Тип Топ после исправления перехвата фокуса из чата.


func run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	await start("tip_top")
	await common()
	await stop()
	print("TT FOCUS29: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
