extends SceneTree
## Минимальные отрицательные границы Store; отдельная fixture, не дополнительный сетевой прогон.
var checks := 0
var errors := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func _initialize() -> void:
	var store := PlayerStatsStore.new("user://low_guard_stats.json")
	check(not store.consume({}), "Пустой snapshot отвергнут")
	check(not store.consume({"seat":-1}), "Snapshot зрителя отвергнут до чтения остальных полей")
	check(not FileAccess.file_exists(store.path), "Отрицательные snapshot не создают файл")
	var snapshot := {"id":"low-guard", "game":"brodilka", "seat":1, "totals":{"dice":{"3":2,"4":1}, "result":"win"}}
	check(store.consume(snapshot), "Контроль: допустимый адресный snapshot сохранён")
	var before := FileAccess.get_file_as_string(store.path)
	var old := snapshot.duplicate(true)
	old.totals.dice = {"3":1}
	old.totals.result = ""
	check(not store.consume(old), "Старый snapshot не уменьшает счётчики и не отменяет итог")
	check(not store.consume(snapshot), "Повтор итогового snapshot не дублируется")
	check(store.summary("brodilka").dice == {"3":2,"4":1} and store.summary("brodilka").completed == 1 and store.summary("brodilka").wins == 1, "После отрицательных повторов сохранены все свои грани и одна победа")
	check(FileAccess.get_file_as_string(store.path) == before, "Отвергнутые повторы не переписывают файл")
	print("BR STATS LOW GUARDS: проверок=",checks," ошибок=",errors)
	quit(1 if errors else 0)
