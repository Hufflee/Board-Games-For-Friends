class_name STJudge
extends RefCounted
## Локальная проверка ответа «Стиллиона»: нормализация, автоисправление опечаток (расстояние Левенштейна)
## и поиск в списке известных ответов вопроса (st_questions.gd). Если ответа в списке нет — решает jev (st_jev.gd).
## Проверка: godot --headless --path . --script res://tests/test_stillion.gd


## Нижний регистр, ё→е, без кавычек и знаков; дефисы и прочее — пробелы; пробелы схлопнуты.
static func normalize(text: String) -> String:
	var t := text.to_lower().replace("ё", "е")
	var out := ""
	for ch in t:
		var code := ch.unicode_at(0)
		var letter := (code >= 0x430 and code <= 0x44f) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		out += ch if letter else " "
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


## Сколько опечаток прощаем: короткие слова — точно, длиннее — 1–2 буквы.
static func allowed_typos(length: int) -> int:
	if length <= 3:
		return 0
	if length <= 6:
		return 1
	return 2


static func distance(a: String, b: String) -> int:
	if a == b:
		return 0
	var prev: Array[int] = []
	for j in b.length() + 1:
		prev.append(j)
	for i in a.length():
		var cur: Array[int] = [i + 1]
		for j in b.length():
			var cost := 0 if a[i] == b[j] else 1
			cur.append(mini(mini(cur[j] + 1, prev[j + 1] + 1), prev[j] + cost))
		prev = cur
	return prev[b.length()]


## Ищет ответ в списке вопроса. Возвращает {found, name, rarity, typo} или {found: false}.
## Точное совпадение — сразу; иначе ближайший вариант в пределах допустимых опечаток.
static func lookup(question: Dictionary, typed: String) -> Dictionary:
	var n := normalize(typed)
	if n.is_empty():
		return {"found": false}
	var best: Dictionary = {}
	var best_d := 999
	for a: Dictionary in question.answers:
		for alt: String in a.alts:
			if alt == n:
				return {"found": true, "name": a.name, "rarity": a.rarity, "typo": false}
			var d := distance(alt, n)
			if d <= allowed_typos(alt.length()) and d < best_d:
				best_d = d
				best = {"found": true, "name": a.name, "rarity": a.rarity, "typo": true}
	return best if not best.is_empty() else {"found": false}


## Ключ «уже называли» — нормализованное имя ответа (синонимы считаются одним ответом).
static func key(name: String) -> String:
	return normalize(name)


const _ROMAN := ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]


## Основа ответа без номера в конце: «dust 2», «gta v», «убить билла 2» → «dust», «gta», «убить билла».
## Ответы с одной основой — почти одно и то же, считаются одним ответом (не повторяются).
static func base(normalized: String) -> String:
	var words := normalized.split(" ", false)
	while words.size() > 1 and (words[-1].is_valid_int() or words[-1] in _ROMAN):
		words.remove_at(words.size() - 1)
	return " ".join(words)
