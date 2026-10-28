extends SceneTree
## Точное содержательное слово, канонизация, ограничения и прежние опечатки.
var checks := 0
var errors := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func q(names: Array) -> Dictionary:
	var answers := []
	for name: String in names:
		answers.append({"name": name, "alts": [STJudge.normalize(name)], "rarity": "u"})
	return {"answers": answers}
func _initialize() -> void:
	var city := q(["Новый Орлеан"])
	var answer := STJudge.lookup(city, "Орлеан")
	check(answer.found and answer.name == "Новый Орлеан" and answer.rarity == "u", "Одно содержательное слово принимает полный ответ и редкость")
	check(answer.partial and not answer.typo, "Это точная часть ответа, не опечатка")
	check(not STJudge.lookup(city, "Новый").found, "Общее слово не принимается отдельно")
	check(STJudge.lookup(city, "НОВЫЙ ОРЛЕАН!").found, "Полное точное имя сохраняется")
	check(not STJudge.lookup(city, "Орле").found, "Часть слова не считается точным словом")
	check(not STJudge.lookup(city, "Орлеанн").found, "Опечатка в отдельном слове не принимается как точная часть")
	check(STJudge.lookup(city, "Новый Орлеанн").found, "Прежнее исправление полного имени работает")
	check(STJudge.lookup(q(["Брюс Ли"]), "Ли").found, "Короткое содержательное имя допускается точно")
	check(STJudge.lookup(q(["Мастер и Маргарита"]), "Маргарита").found, "Три слова с союзом")
	check(not STJudge.lookup(q(["Побег из города будущего"]), "будущего").found, "Ограничение2–3слов")
	check(not STJudge.lookup(q(["Игра престолов"]), "игра").found, "Общее обозначение сущности не заменяет название")
	check(STJudge.lookup(q(["Новый"]), "Новый").found, "Стоп-слово является допустимым полным ответом")
	check(not STJudge.lookup(q(["Half Life 2"]), "2").found, "Отдельный номер не принимается")
	check(not STJudge.lookup(q(["The Last Guardian"]), "the").found, "Артикль не принимается")
	check(STJudge.lookup(q(["The Last Guardian"]), "guardian").found, "Английское содержательное слово")
	var ambiguous := STJudge.lookup(q(["Северная Каролина", "Южная Каролина"]), "Каролина")
	check(not ambiguous.found and ambiguous.ambiguous, "Несколько разных ответов проверяет Jev")
	check(STJudge.lookup(q(["Каролина", "Южная Каролина"]), "Каролина").name == "Каролина", "Полное точное совпадение имеет приоритет")
	check(STJudge.base(STJudge.key(str(answer.name))) == STJudge.base(STJudge.key("Новый Орлеан")), "Неполный и полный ответы имеют один ключ повторения")
	var series := {"answers": [{"name": "GTA IV", "alts": ["gta iv"], "rarity": "c"}, {"name": "GTA V", "alts": ["gta v"], "rarity": "e"}]}
	check(STJudge.lookup(series, "gta").rarity == "c", "Общее название серии не получает редкость её самой редкой части")
	check(not STJudge.lookup(q(["Game Night"]), "game").found, "Общее обозначение сущности на английском не заменяет название")
	print("СТИЛЛИОН ЧАСТЬ28: проверок=", checks, " ошибок=", errors)
	quit(1 if errors else 0)
