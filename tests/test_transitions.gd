extends SceneTree
## Проверяет случайный порядок переходов: godot --headless --path . --script res://tests/test_transitions.gd
var Transition: GDScript
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	Transition = load("res://hub/luma_wipe.gd")
	Transition._bag.clear()
	Transition._last_effect = -1
	var last := -1
	var orders := {}
	for cycle in 40:
		var seen := {}
		var order := ""
		for i in Transition.EFFECTS.size():
			var effect: int = Transition.next_effect()
			check(effect >= 0 and effect < Transition.EFFECTS.size(), "Неверный номер перехода")
			check(effect != last, "Повтор перехода подряд")
			check(not seen.has(effect), "Один переход выпал дважды за цикл")
			seen[effect] = true
			order += str(effect)
			last = effect
		check(seen.size() == Transition.EFFECTS.size(), "Пропущен эффект в цикле")
		orders[order] = true
	check(orders.size() > 1, "Порядок переходов не перемешивается")
	check(Transition.DURATIONS.size() == Transition.EFFECTS.size(), "Не для всех переходов задана длительность")
	check(Transition.EFFECTS.size() == 6, "Должно остаться шесть переходов")
	for removed in ["morph_cut", "zoom_through", "dip_to_black"]:
		check(not Transition.EFFECTS.has(removed), "Удалённый переход остался в списке: " + removed)
	check(Transition.SHADER_EFFECTS == [0, 1, 3, 5, 6, 8], "Нарушено соответствие оставшихся эффектов веткам шейдера")
	print("Переходы: ", checks, " проверок, ошибок: ", failures)
	quit(1 if failures else 0)
