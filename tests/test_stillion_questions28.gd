extends SceneTree
## Состав новых120 вопросов; старые данные защищены SHA256 исходного TEXT.
## --headless --audio-driver Dummy --path . --script res://tests/test_stillion_questions28.gd

const OLD_LENGTH := 43945
const OLD_SHA256 := "f713a12d3f1a8b411ff9998835ddaf491d7ce848844cb45d98598e98c0480419"
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	var questions := STQuestions.all()
	check(questions.size() == 240, "Ровно240 вопросов")
	check(STQuestions.categories().size() == 10, "Ровно10 прежних категорий")
	var before_import := STQuestions.TEXT.replace("\r\n", "\n").replace(", творожный сырок|сырок|глазированный сырок", "")
	check(before_import.substr(0, OLD_LENGTH).sha256_text() == OLD_SHA256, "Старые120 вопросов неизменны, кроме проверенного импорта сырка")
	var categories: Dictionary = {}
	var added: Dictionary = {}
	var seen: Dictionary = {}
	var total_answers := 0
	for index in questions.size():
		var question: Dictionary = questions[index]
		categories[question.cat] = int(categories.get(question.cat, 0)) + 1
		var key := STJudge.normalize(str(question.text))
		if index < 120:
			seen[key] = true
			continue
		check(not seen.has(key), "Новый вопрос не повторяет прежний/новый: " + str(question.text))
		seen[key] = true
		added[question.cat] = int(added.get(question.cat, 0)) + 1
		check(question.answers.size() >= 8, "Не меньше8 разных базовых ответов: " + str(question.text))
		var names: Dictionary = {}
		var aliases: Dictionary = {}
		var rarity: Dictionary = {}
		for answer: Dictionary in question.answers:
			total_answers += 1
			check(answer.rarity in ["c", "s", "u", "e"], "Допустимая редкость")
			rarity[answer.rarity] = int(rarity.get(answer.rarity, 0)) + 1
			var name := STJudge.normalize(str(answer.name))
			check(not name.is_empty() and not names.has(name), "Разные непустые ответы: " + str(question.text))
			names[name] = true
			check(not str(answer.name).ends_with("?"), "Спорный черновик не стал ответом")
			for alias in answer.alts:
				check(not aliases.has(alias) or aliases[alias] == name, "Синоним не выдаётся за другой ответ")
				aliases[alias] = name
			lexical(question, str(answer.name))
		check(int(rarity.get("c", 0)) >= 2, "Есть минимум2 очевидных fallback")
		check(rarity.size() == 4, "Формат содержит все4 уровня fallback")
		check(not (str(question.text) + str(question.answers)).to_lower().contains("футбол"), "Новый набор без футбола")
	for category in STQuestions.categories():
		check(int(categories.get(category, 0)) == 24, "Всего24 в категории " + str(category))
		check(int(added.get(category, 0)) == 12, "Добавлено ровно12 в категории " + str(category))
	# Замкнутые эталонные наборы дополнительно проверяем целиком.
	exact(questions, "Назовите одну из восьми планет Солнечной системы", ["земля", "марс", "венера", "юпитер", "меркурий", "сатурн", "уран", "нептун"])
	exact(questions, "Назовите тип фигуры в стандартном наборе сёги, до превращения", ["король", "ладья", "слон", "золотой генерал", "серебряный генерал", "конь", "копьё", "пешка"])
	exact(questions, "Назовите минерал, служащий эталоном в шкале твёрдости Мооса", ["алмаз", "кварц", "тальк", "гипс", "кальцит", "флюорит", "апатит", "ортоклаз", "топаз", "корунд"])
	print("ST QUESTIONS28: %d проверок, %d ошибок; новых вопросов120, базовых ответов%d" % [checks, errors, total_answers])
	quit(1 if errors else 0)

func exact(questions: Array, text: String, expected: Array) -> void:
	var matches := questions.filter(func(q: Dictionary): return q.text == text)
	check(matches.size() == 1, "Эталонный вопрос единственный: " + text)
	if matches.size() != 1:
		return
	var names: Array = []
	for answer: Dictionary in matches[0].answers:
		names.append(str(answer.name))
	names.sort()
	var sorted := expected.duplicate()
	sorted.sort()
	check(names == sorted, "Замкнутый набор совпадает: " + text)

func lexical(question: Dictionary, word: String) -> void:
	var text := str(question.text)
	var lower := word.to_lower()
	if text == "Назовите русское существительное, начинающееся на «АВТО»":
		check(lower.begins_with("авто"), "Начало АВТО")
	elif text == "Назовите русское существительное с сочетанием букв «СЧ»":
		check(lower.contains("сч"), "Сочетание СЧ")
	elif text == "Назовите русское существительное, в котором подряд стоят две «Н»":
		check(lower.contains("нн"), "Две Н")
	elif text == "Назовите русское слово, начинающееся с приставки «БЕЗ-»":
		check(lower.begins_with("без"), "Начало БЕЗ")
	elif text == "Назовите русское существительное, оканчивающееся на «-МЯ»":
		check(lower.ends_with("мя"), "Окончание МЯ")
	elif text == "Назовите русское прилагательное, начинающееся на «ТРЁХ-»":
		check(lower.begins_with("трёх"), "Начало ТРЁХ")
	elif text == "Назовите русское слово, в котором подряд стоят две «С»":
		check(lower.contains("сс"), "Две С")
	elif text == "Назовите русское существительное на «-ЦИЯ»":
		check(lower.ends_with("ция"), "Окончание ЦИЯ")
	elif text == "Назовите русское слово с сочетанием букв «ДЦ»":
		check(lower.contains("дц"), "Сочетание ДЦ")
	elif text == "Назовите английское прилагательное с суффиксом «-LESS»":
		check(lower.ends_with("less"), "Суффикс LESS")
	elif text == "Назовите английское существительное, оканчивающееся на «-TION»":
		check(lower.ends_with("tion"), "Окончание TION")
	elif text == "Назовите английское слово с двумя «E» подряд":
		check(lower.contains("ee"), "Две английские E")
	elif text == "Назовите английское название животного ровно из трёх букв":
		check(lower.length() == 3, "Ровно3 английские буквы")
	elif text == "Назовите государство Африки, чьё русское название начинается на «М» или «Б»":
		check(lower.begins_with("м") or lower.begins_with("б"), "Начало М или Б")
	elif text == "Назовите европейскую столицу с русским названием, оканчивающимся на «А»":
		check(lower.ends_with("а"), "Столица на А")
	elif text == "Назовите столицу независимого государства, чьё русское название начинается на «К»":
		check(lower.begins_with("к"), "Столица на К")
