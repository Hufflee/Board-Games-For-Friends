extends SceneTree
## Доска уиджи оставляет открытой активную подсказку на обеих половинах стола.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var board: Control = load("res://games/phantom_ink/ui/pi_ouija.gd").new()
	root.add_child(board)
	board._table_rect = Rect2(24, 112, 876, 580)
	var failures := 0
	var checks := 0
	for left in [24.0, 464.0]:
		for row in 8:
			var clue := Rect2(left, 192.0 + row * 49.0, 398.0, 44.0)
			board._clue_rect = clue
			var place: Rect2 = board.board_rect()
			checks += 1
			if not place.has_area() or not board._table_rect.encloses(place) or place.intersects(clue):
				failures += 1
				push_error("Доска перекрыла подсказку или вышла из кадра: %s" % clue)
	board.queue_free()
	await process_frame
	print("Уиджи: %d проверок, ошибок %d" % [checks, failures])
	quit(int(failures > 0))
