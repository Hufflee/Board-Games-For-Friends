extends SceneTree
## Разовая отладка фазза (06.11): воспроизвести журнал build/fs_tests/fuzz_failures/<SEED>.json и показать состояние.
const Fuzz := preload("res://tests/fs/fs_fuzz.gd")
const Inv := preload("res://games/four_souls/logic/fs_invariants.gd")
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://build/fs_tests/fuzz_failures/" + OS.get_environment("SEED") + ".json"))
	var s = Fuzz._start(d.config)
	var g = s.g
	var queue: Array = []
	g.roll_source = func() -> int: return int(queue.pop_front()) if not queue.is_empty() else 3
	var i := 0
	for entry in d.log:
		queue.clear(); queue.append_array(entry[3])
		var before := [g.phase, str(g.resolving.get("kind", "")), int(g.resolving.get("card", -1)), g.stack.map(func(e): return [e.kind, e.get("card", e.get("value", ""))])]
		var ok = Fuzz.perform(g, int(entry[0]), str(entry[1]), entry[2])
		var found: Array = Inv.check(g, false)
		if not found.is_empty():
			print("ШАГ ", i, " ", entry, " до: ", before)
			print("ПРОБЛЕМА: ", found)
			print("после: phase ", g.phase, " resolving ", g.resolving.keys(), " card ", g.resolving.get("card", -1), " stack ", g.stack.map(func(e): return [e.kind, e.get("card", e.get("value", ""))]), " after ", g._after_stack)
			print("журнал: ", g.log.slice(-12))
			break
		i += 1
	print("КОНЕЦ шагов ", i, " phase ", g.phase, " resolving ", g.resolving.get("kind", ""), " card ", g.resolving.get("card", -1), " stack ", g.stack.map(func(e): return [e.kind, e.get("card", e.get("value", ""))]))
	print("журнал: ", g.log.slice(-10))
	print("проблемы с hang: ", Inv.check(g, true))
	quit()
