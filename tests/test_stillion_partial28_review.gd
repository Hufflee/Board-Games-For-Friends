extends SceneTree
## Независимые границы частичного ответа; подготовленные вопросы, настоящие STJudge/STRules, без Net/Jev API.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func q(rows: Array) -> Dictionary:
	var answers := []
	for row: Array in rows:
		var alts := [STJudge.normalize(row[0])]
		if row.size() > 2:
			for alt: String in row[2]:
				alts.append(STJudge.normalize(alt))
		answers.append({"name": row[0], "rarity": row[1], "alts": alts})
	return {"cat": "Подготовленный тест", "text": "Тестовый вопрос", "answers": answers}

func rules(question: Dictionary) -> STRules:
	var game := STRules.new()
	game.new_game([{"name": "А"}, {"name": "Б"}, {"name": "В"}], false, 2801)
	# Только вопрос — fixture; переход к fuse проходит штатными tick.
	game.question = question.duplicate(true)
	game.external_check = true
	game.tick(STRules.NEW_Q_TIME)
	game.tick(STRules.AIM_TIME)
	check(game.phase == "fuse", "Подготовленный вопрос дошёл до fuse штатными tick")
	return game

func _initialize() -> void:
	var two := q([["Конёк-Горбунок", "u"]])
	for word in ["КОНЁК!", "горбунок", "конек"]:
		var result := STJudge.lookup(two, word)
		check(result.found and result.name == "Конёк-Горбунок" and result.get("partial", false), "Ё/дефис/пунктуация: " + word)
	var three := q([["Ромео и Джульетта", "s"]])
	check(STJudge.lookup(three, "Джульетта").found, "Содержательное слово трёхсловного имени с союзом")
	check(not STJudge.lookup(three, "и").found, "Союз не является самостоятельной частью")
	var four := q([["Гарри Поттер и тайник", "e"]])
	check(not STJudge.lookup(four, "Поттер").found, "Четыре слова не сокращаются выкидыванием союза")
	check(STJudge.lookup(four, "Гарри Поттер и тайник").found, "Полное четырёхсловное имя разрешено")
	check(not STJudge.lookup(q([["Красный северо-западный ветер", "u"]]), "ветер").found, "Дефис даёт четвёртое слово после нормализации")
	for word in ["новый", "или", "из", "страна", "movie", "country", "and", "the"]:
		var full := q([[word, "c"], [word + " кристаллик", "e"]])
		var exact := STJudge.lookup(full, word)
		check(exact.found and exact.name == word and not exact.typo, "Точный одиночный стоп-ответ разрешён: " + word)
		check(not STJudge.lookup(q([[word + " кристаллик", "e"]]), word).found, "Стоп-слово отдельно не определяет длинное имя: " + word)
	var priority := q([["Альфа Бета", "e"], ["Альфа", "c"]])
	var exact := STJudge.lookup(priority, "Альфа")
	check(exact.found and exact.name == "Альфа" and exact.rarity == "c" and not exact.get("partial", false), "Полное совпадение приоритетно независимо от позиции")
	var typo := STJudge.lookup(q([["Мастер и Маргарита", "u"]]), "Мастер и Маргаритта")
	check(typo.found and typo.typo, "Опечатка полного имени сохранена")
	var ambiguity := q([["Красная панда", "u"], ["Красная площадь", "c"], ["Резервный ответ", "s"]])
	var ambiguous := STJudge.lookup(ambiguity, "красная")
	check(not ambiguous.found and ambiguous.get("ambiguous", false), "Разные кандидаты оставляются Jev")
	var game := rules(ambiguity)
	var seat := game.target
	check(game.action(seat, "st_answer", {"text": "красная"}), "Неоднозначный ответ принимается на проверку")
	check(game.phase == "check" and game.pending.text == "красная" and game.used.is_empty() and game.players[seat].meter == 0, "До Jev нет произвольной канонизации или награды")
	var no := int(game.pending.no)
	check(game.resolve_external(no, true, "u", "Красная панда"), "Настоящий внешний вердикт разрешает неоднозначность")
	check(game.used.size() == 1 and game.used[0].name == "Красная панда" and game.players[seat].meter == 3, "Учтена выбранная Jev каноническая награда")
	check(not game.resolve_external(no, true, "e", "Красная площадь"), "Повторный вердикт не даёт вторую награду")
	var unique := q([["Новый Орлеан", "u"], ["Москва", "c"], ["Токио", "s"]])
	game = rules(unique)
	seat = game.target
	check(game.action(seat, "st_answer", {"text": "Орлеан"}), "Частичный ответ отправлен штатным action")
	check(game.last.kind == "ok" and game.last.name == "Новый Орлеан" and game.used.size() == 1 and game.players[seat].meter == 3, "Реальные used/last/meter содержат канонический частичный ответ")
	game.tick(STRules.AIM_TIME)
	var next := game.target
	var before: int = game.players[next].meter
	check(game.action(next, "st_answer", {"text": "НОВЫЙ ОРЛЕАН"}), "Полное имя после части проходит action")
	check(game.last.kind == "used" and game.phase == "fuse" and game.used.size() == 1 and game.players[next].meter == before, "Полное имя после части считается повтором без награды/Jev")
	game = rules(unique)
	game.action(game.target, "st_answer", {"text": "Новый Орлеан"})
	game.tick(STRules.AIM_TIME)
	game.action(game.target, "st_answer", {"text": "Орлеан"})
	check(game.last.kind == "used" and game.used.size() == 1, "Часть после полного имени также считается повтором")
	var series := q([["GTA V", "e"], ["GTA IV", "c"], ["GTA III", "s"], ["Тетрис", "s"]])
	var generic := STJudge.lookup(series, "gta")
	check(generic.found and generic.rarity == "c", "Порядок серии не выдаёт редкость первой дорогой части")
	check(STJudge.lookup(series, "GTA V").rarity == "e", "Полный номер сохраняет собственную редкость")
	game = rules(series)
	seat = game.target
	game.action(seat, "st_answer", {"text": "gta"})
	check(game.players[seat].meter == 1 and game.used[0].rarity == "c", "Общее имя серии начисляет минимальный реальный meter")
	game.tick(STRules.AIM_TIME)
	game.action(game.target, "st_answer", {"text": "GTA V"})
	check(game.last.kind == "used" and game.used.size() == 1, "Другая часть той же серии не даёт повторную награду")
	# У валидных альтернатив есть полное каноническое имя. Короткий alias известен лишь у дорогой части.
	var alias_series := q([["Grand Theft Auto V", "e", ["GTA V"]], ["Grand Theft Auto IV", "c"], ["Тетрис", "s"]])
	var alias_result := STJudge.lookup(alias_series, "gta")
	print("ALIAS_SERIES lookup=", JSON.stringify(alias_result))
	check(alias_result.found and alias_result.rarity == "c", "Ненумерованный alias серии не наследует ложную редкость единственной части с коротким alias")
	game = rules(alias_series)
	seat = game.target
	game.action(seat, "st_answer", {"text": "gta"})
	print("ALIAS_SERIES rules=", JSON.stringify({"last": game.last, "used": game.used, "meter": game.players[seat].meter}))
	check(game.players[seat].meter == 1 and game.used.size() == 1 and game.used[0].rarity == "c", "Ненумерованный alias через реальные STRules даёт1 очко минимальной редкости")
	print("СТИЛЛИОН LOW ЧАСТЬ28: проверок=", checks, " ошибок=", errors)
	quit(1 if errors else 0)
