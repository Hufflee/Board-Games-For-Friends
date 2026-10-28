extends SceneTree
## Единственная разрешённая дельта старого банка: сырок и три алиаса через настоящий lookup.
var checks := 0
var errors := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func _initialize() -> void:
	var rows := STQuestions.all().filter(func(q: Dictionary): return q.text == "Назовите молочный продукт")
	check(rows.size() == 1, "Исходный молочный вопрос единственный")
	if rows.size() == 1:
		for typed in ["творожный сырок", "сырок", "глазированный сырок"]:
			var found := STJudge.lookup(rows[0], typed)
			check(found.found and found.name == "творожный сырок" and found.rarity == "s" and not found.typo, "Разрешённый alias сохраняет канонизацию/s: " + typed)
	print("СЫРОК LOW28: проверок=", checks, " ошибок=", errors)
	quit(1 if errors else 0)
