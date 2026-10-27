class_name STJev
extends Node
## Проверка ответов «Стиллиона» нейросетью Jev (Typesafe AI, System One): POST https://api.typesafe.ai/v1/systemone.
## Работает только у хоста. Ключ — у каждого свой: user://stillion.cfg [jev] key (вводится в лобби)
## или переменная окружения TYPESAFE_API_KEY. В проект и экспорт ключ не попадает.
## Один запрос — два вопроса к модели: верен ли ответ (опечатки прощаются) и насколько он редкий.

signal judged(no: int, ok: bool, rarity: String)

const URL := "https://api.typesafe.ai/v1/systemone"
const CFG := "user://stillion.cfg"
## Ответы не из списка, которые jev засчитал: по строке JSON на ответ. Разработчик проверяет их
## и переносит верные в st_questions.gd (сам файл на Windows: %APPDATA%/Godot/app_userdata/<имя проекта>/).
const NEW_ANSWERS := "user://stillion_new_answers.jsonl"
const MODEL := "jev-latest"
const TIMEOUT := 7.0
## Редкость от Jev — на ступень выше: прогон всех ответов из списков (docs/stillion_jev_check.md) показал,
## что Jev оценивает ответы примерно на ступень «проще», чем списки (её common в среднем ≈ наш «школьник»).
const RARITY_KEYS := {"common": "s", "school": "u", "smart": "e", "erudite": "e"}
## Порог «верно»: при 0,5 Jev отклоняла 8,6% верных ответов из списков; при 0,4 — 6,2%,
## а неверных (ответы на соседние вопросы) принимает 5% вместо 3,4%.
const OK_THRESHOLD := 0.4


static func api_key() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		var k := str(cfg.get_value("jev", "key", "")).strip_edges()
		if k != "":
			return k
	return OS.get_environment("TYPESAFE_API_KEY").strip_edges()


static func save_key(key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("jev", "key", key.strip_edges())
	cfg.save(CFG)


static func available() -> bool:
	return api_key() != ""


## Тело запроса — отдельно, чтобы его можно было проверить в тестах без сети.
static func request_body(question: Dictionary, answer: String, appeal: bool = false) -> Dictionary:
	var english := str(question.get("cat", "")) == "Английский язык"
	var body := {
		"model": MODEL,
		"state": {
			"quiz_category": question.get("cat", ""),
			"quiz_question": question.get("text", ""),
			"player_answer": answer,
		},
		"questions": {
			"correct": {
				"type": "noul",
				"instructions": "Is the player's answer a correct answer to this quiz question? The quiz is in Russian%s. Accept small spelling mistakes, missing or extra letters, ё/е, transliteration and well-known short names. Reject jokes, answers that only partly fit, and anything not matching the question." % (" and the answer must be an English word" if english else ""),
			},
			"rarity": {
				"type": "choice",
				"instructions": "If the answer is correct, how obvious is it for an average Russian-speaking adult?",
				"criteria": {
					"common": "One of the first answers almost everyone would give.",
					"school": "A reasonable answer that a school student would know.",
					"smart": "Needs good general knowledge; most people would not think of it.",
					"erudite": "Rare, expert-level answer.",
				},
			},
		},
	}
	if appeal:
		body.state["review_mode"] = "independent detailed appeal"
		body.questions.correct.instructions += " This is an appeal of a rejected answer. Re-evaluate independently and carefully: verify every factual constraint of the question, alternative names and transliterations, spelling corrections, regional terminology, and reasonable everyday interpretations. An earlier rejection is not evidence. Accept if the answer meets the question; reject if it contradicts a factual constraint. Do not accept merely because the player appealed."
	return body


## Разбор ответа API: noul может прийти как bool, число-вероятность или словарь с вероятностями.
static func parse(data) -> Dictionary:
	if not data is Dictionary or not (data as Dictionary).has("answers"):
		return {"ok": false, "error": true}
	var ans: Dictionary = data.answers
	var ok := false
	var p := -1.0  # вероятность «верно», если jev её прислал
	var c = ans.get("correct", {})
	var v = c.get("noul") if c is Dictionary else c
	if v is bool:
		ok = v
	elif v is float or v is int:
		p = float(v)
		ok = p >= OK_THRESHOLD
	elif v is Dictionary:
		p = float(v.get("yes", v.get("true", 0.0)))
		ok = p >= OK_THRESHOLD
	var r = ans.get("rarity", {})
	var choice = r.get("choice") if r is Dictionary else r
	if choice is Dictionary:  # {label: вероятность}
		var best := ""
		var best_p := -1.0
		for k in choice:
			if float(choice[k]) > best_p:
				best_p = float(choice[k])
				best = str(k)
		choice = best
	return {"ok": ok, "p": p, "jev": str(choice), "rarity": RARITY_KEYS.get(str(choice), "s"), "error": false}


## Дописать засчитанный jev ответ в NEW_ANSWERS (для пополнения списков).
static func log_new_answer(question: Dictionary, answer: String, verdict: Dictionary, path: String = NEW_ANSWERS) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Стиллион: не удалось записать %s" % path)
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"time": Time.get_datetime_string_from_system(), "version": str(ProjectSettings.get_setting("application/config/version", "")),
		"cat": question.get("cat", ""), "question": question.get("text", ""), "answer": answer.strip_edges(),
		"p": verdict.get("p", -1.0), "jev": verdict.get("jev", ""), "rarity": verdict.get("rarity", ""),
	}))


## Отправить ответ на проверку; результат — сигнал judged(no, ok, rarity). Ошибка сети — не засчитано.
func check(no: int, question: Dictionary, answer: String, appeal: bool = false) -> void:
	var key := api_key()
	if key == "":
		judged.emit(no, false, "s")
		return
	var http := HTTPRequest.new()
	http.timeout = 18.0 if appeal else TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			push_warning("Стиллион: jev не ответил (%d / HTTP %d)" % [result, code])
			judged.emit(no, false, "s")
			return
		var verdict := parse(JSON.parse_string(body.get_string_from_utf8()))
		if bool(verdict.ok):
			log_new_answer(question, answer, verdict)
		judged.emit(no, bool(verdict.ok), str(verdict.rarity)))
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + key])
	var err := http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body(question, answer, appeal)))
	if err != OK:
		http.queue_free()
		judged.emit(no, false, "s")
