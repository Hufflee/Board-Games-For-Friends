extends SceneTree
## Регрессии 02.11: версия, словарь/приватность, cooldown и сохранение шкафа.
const Words := preload("res://hub/shared_words.gd")
const Mind := preload("res://games/the_mind/logic/tm_rules.gd")
const Phantom := preload("res://games/phantom_ink/logic/pi_rules.gd")
const Doc := preload("res://editor/ed_document.gd")
const Clip := preload("res://editor/ed_clipboard.gd")
const Rules := preload("res://games/custom/logic/cg_rules.gd")
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func act(r: RefCounted, seat: int, kind: String) -> bool:
	return r.action(seat, kind, {"revision": r.revision})

func _run() -> void:
	var words := Words.all()
	check(words.size() == 1000, "Ровно тысяча слов")
	var unique := {}
	for word: String in words:
		check(word == word.to_lower() and not word.contains(" ") and not unique.has(word), "Нарицательное уникальное однословное: " + word)
		unique[word] = true
	check(not words.has("Пушкин") and not words.has("гарри поттер"), "Нет имён собственных")
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var six := Words.sample(rng, 6)
	check(six.size() == 6 and six.all(func(word): return words.has(word)), "Шесть слов без повторов из общего словаря")
	var pi := Phantom.new()
	pi.new_game([{"name": "А"}, {"name": "Б"}, {"name": "В"}, {"name": "Г"}], [0, 1, 2, 3], 3)
	check(pi.get_view(0).object_words.is_empty() and pi.get_view(-1).object_words.is_empty(), "Слова скрыты от медиума и зрителя")
	check(pi.get_view(1).object_words == pi.get_view(3).object_words, "Оба духа видят одинаковые слова")
	check(pi.action(1, "object", 4) and pi.get_view(3).votes == [4, -1], "Другой дух видит поданный голос")
	check(pi.action(3, "object", 2) and pi.phase == "object", "Разные голоса не начинают партию")
	check(pi.action(3, "object", 4) and pi.object_slot == 4, "Совпавшие голоса выбрали слово")
	check(pi.get_view(0).votes.is_empty() and pi.get_view(0).object_words.is_empty(), "Выбранное слово осталось закрытым")
	var mind := Mind.new()
	mind.new_game([{"name": "А"}, {"name": "Б"}], 2)
	act(mind, 0, "ready")
	act(mind, 1, "ready")
	check(act(mind, 0, "refocus"), "Первый сбор сразу доступен")
	act(mind, 0, "ready")
	act(mind, 1, "ready")
	check(not act(mind, 1, "refocus"), "Другой игрок не обходит общую блокировку")
	mind.tick(14.99)
	check(not act(mind, 0, "refocus"), "До 15 секунд нельзя")
	mind.tick(0.02)
	check(act(mind, 1, "refocus"), "После 15 секунд можно")
	mind.hands = [[], [10]]
	mind._focus("Проверка пустой руки")
	check(mind.ready == [true, false], "Пустая рука готова автоматически")
	check(act(mind, 1, "ready") and mind.phase == "play", "Не ждём кнопку игрока без карт")
	mind.level = 2
	check(mind.get_view(0).level_reward.contains("Паника"), "Видна награда за второй уровень")
	mind.level = 3
	check(mind.get_view(0).level_reward.contains("жизнь"), "Видна награда за третий уровень")
	var updater: Node = root.get_node("Updater")
	var old_base: String = updater.base_version
	var old_version: String = updater.version
	updater.base_version = "0.8.8"
	updater.version = "0.8.10"
	var client: Node = load("res://hub/update/update_client.gd").new()
	root.add_child(client)
	for latest: String in ["0.8.9", "0.8.10"]:
		client._manifest = {"format": 1, "version": latest, "base": {"version": "0.8.8"}, "patches": [{"version": latest, "sha256": "иная цепочка"}]}
		client._plan()
		check(client.state == 2 and client._queue.is_empty(), "Та же/старая версия не предлагает обновляться: " + latest)
	client._manifest = {"format": 1, "version": "0.8.11", "base": {"version": "0.8.8"}, "patches": [{"version": "0.8.11", "sha256": "new"}]}
	client._plan()
	check(client.state == 3 and client.target == "0.8.11", "Новая версия предлагается")
	client.queue_free()
	updater.base_version = old_base
	updater.version = old_version
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	definition.rules["dictionary"] = "shared"
	definition.rules.vars.append({"id": "word", "scope": "shared", "type": "text", "init": "", "visible": "all"})
	definition.rules.chains.append({"event": {"type": "start", "by": "all"}, "blocks": [{"op": "set", "var": "word", "value": {"op": "dictionary_word"}}]})
	var r := Rules.new()
	check(r.load_definition(definition).is_empty(), "Игра со словарём валидна")
	check(r.new_game([{"name": "А"}, {"name": "Б"}], {"seed": 7}).is_empty(), "Игра запускается со словарём")
	check(words.has(r.state.vars.shared.word), "Хост выбрал настоящее слово в переменную")
	var clone := Rules.new()
	clone.load_definition(definition)
	clone.new_game([{"name": "А"}, {"name": "Б"}], {"seed": 7})
	check(clone.state.vars.shared.word == r.state.vars.shared.word, "Тот же seed выбирает то же слово")
	var doc := Doc.new()
	doc.create("card_race")
	doc.data["box"] = {"template": "square", "thickness": 0.06, "faces": {"front": [{"kind": "fill", "rect": [0, 0, 128, 128], "color": "#226688"}]}}
	var payload := Clip.decode(Clip.encode(doc, "layer", doc.data.box.faces.front[0]))
	check(not payload.is_empty(), "Слой сериализуется для системного буфера")
	check(Clip.paste(doc, payload, "layer", ["box", "faces", "front"]).is_empty() and doc.data.box.faces.front.size() == 2, "Слой вставлен отдельной копией")
	doc.undo()
	check(doc.data.box.faces.front.size() == 1, "Вставка отменяется одним шагом")
	check(Clip.decode('{"editor_clipboard":1,"kind":"layer","data":{},"assets":[]}').is_empty(), "Повреждённый буфер отклонён")
	var sizes := {"a": Vector3(0.08, 0.3, 0.3), "b": Vector3(0.07, 0.3, 0.3)}
	var cfg := {"rows": 2, "cols": 1, "width": 0.8, "height": 0.31, "cups": 1}
	var file := "user://batch_shelf.cfg"
	ShelfConfig.save_state(cfg, [["b"], ["a"]], {"a": 0, "b": 1}, file)
	sizes["custom:test"] = Vector3(0.06, 0.32, 0.24)
	var state := ShelfConfig.load_state(cfg, [["a"], ["b"]], sizes, file)
	check(state.ok, "Новая высокая авторская коробка помещена без сброса шкафа")
	if state.ok:
		check(state.placements[0].has("b") and state.placements[1].has("a") and state.poses.a == 0, "Положения и позы существующих коробок сохранены")
	print("BATCH02: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
