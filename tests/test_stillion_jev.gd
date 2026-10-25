extends SceneTree
## Регрессия «Стиллиона» (ревью Codex): вердикт Jev старой партии не трогает новую; вердикт на паузе
## применяется только после продолжения и ровно один раз. Берём настоящий обработчик из net.gd
## (_st_process и всё, что ниже), сетевой транспорт заменяем заглушкой — без ключа и без запросов к API.
## Запуск: godot --headless --path . --script res://tests/test_stillion_jev.gd

var checks := 0
var failed := 0


func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ПРОВАЛ: " + msg)


func _initialize() -> void:
	call_deferred("_run")


func _rules(answer: String) -> STRules:
	var r := STRules.new()
	r.new_game([{"name": "А"}, {"name": "Б"}], false, 5)
	r.external_check = true
	r.phase = "fuse"
	r.submit(r.target, answer)
	return r


func _run() -> void:
	var source := FileAccess.get_file_as_string("res://games/king_of_12/net/net.gd")
	var method := source.substr(source.find("func _st_process(delta: float)"))
	method = method.replace("STJev.new()", "FakeJev.new()")
	var script := GDScript.new()
	script.source_code = """extends Node
class FakeJev extends Node:
	signal judged(no: int, ok: bool, rarity: String)
	var asked := 0
	func check(_no: int, _question: Dictionary, _answer: String) -> void:
		asked += 1
var paused := false
var stillion: STRules
var _st_checking := -1
var _st_jev: FakeJev
var _st_jev_for: STRules
var _st_verdict: Array = []
var pushes := 0
func _push_state() -> void:
	pushes += 1
""" + method
	check(script.reload() == OK, "обработчик из net.gd собирается")
	var host: Node = script.new()
	root.add_child(host)
	# 1) смена партии, пока старый запрос ещё в пути
	var old := _rules("старый неизвестный ответ")
	host.stillion = old
	host._st_process(0.0)
	check(old.phase == "check" and host._st_jev.asked == 1, "старый ответ ушёл на проверку")
	var old_jev: Node = host._st_jev
	var old_no: int = old.pending.no
	var fresh := _rules("другой неизвестный ответ")
	host.stillion = fresh
	host._st_checking = -1
	host._st_process(0.0)
	check(host._st_jev != old_jev, "у новой партии свой проверяющий")
	old_jev.judged.emit(old_no, true, "e")
	check(fresh.used.is_empty() and fresh.phase == "check", "вердикт старой партии не засчитал ответ новой")
	host._st_jev.judged.emit(int(fresh.pending.no), true, "u")
	check(fresh.used.size() == 1 and fresh.last.rarity == "u", "свой вердикт новой партии принят")
	# 2) пауза между запросом и вердиктом
	var held := _rules("ответ на паузе")
	host.stillion = held
	host._st_checking = -1
	host._st_process(0.0)
	host.paused = true
	host._st_jev.judged.emit(int(held.pending.no), true, "s")
	check(held.used.is_empty() and held.phase == "check", "на паузе вердикт не применяется")
	host._st_process(0.5)
	check(held.used.is_empty(), "пока пауза — не применяется и в тике")
	host.paused = false
	host._st_process(0.0)
	check(held.used.size() == 1 and held.phase != "check", "после паузы вердикт применён")
	host._st_jev.judged.emit(int(held.last.no), true, "s")
	host._st_process(0.0)
	check(held.used.size() == 1, "повторный вердикт не засчитывается дважды")
	print("СТИЛЛИОН JEV: %d проверок, ошибок: %d" % [checks, failed])
	quit(1 if failed > 0 else 0)
