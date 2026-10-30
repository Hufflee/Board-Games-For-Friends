class_name KHMatch
extends RefCounted
## «Хором!»: похожи ли два ответа. Только подсказка игрокам — очки решают люди.
## Похожи, если совпал весь ответ с опечаткой или хотя бы одно слово (от 3 букв) с опечаткой/в другой форме.

## Нижний регистр, ё→е, знаки препинания — в пробелы, лишние пробелы убраны.
static func normalize(text: String) -> String:
	var low := text.to_lower().replace("ё", "е")
	var out := ""
	for i: int in low.length():
		var ch := low[i]
		var code := ch.unicode_at(0)
		var letter := (code >= 0x430 and code <= 0x44f) or (code >= 0x61 and code <= 0x7a) or (code >= 0x30 and code <= 0x39)
		out += ch if letter else " "
	var parts := PackedStringArray()
	for word: String in out.split(" ", false):
		parts.append(word)
	return " ".join(parts)

## Допустимое число опечаток для слова такой длины.
static func allowed(length: int) -> int:
	return 1 if length <= 5 else 2

static func distance(a: String, b: String) -> int:
	if a == b:
		return 0
	var previous := PackedInt32Array()
	for j: int in b.length() + 1:
		previous.append(j)
	for i: int in a.length():
		var current := PackedInt32Array([i + 1])
		for j: int in b.length():
			var cost := 0 if a[i] == b[j] else 1
			current.append(mini(mini(current[j] + 1, previous[j + 1] + 1), previous[j] + cost))
		previous = current
	return previous[b.length()]

## Одно слово: опечатка или другая грамматическая форма (общее начало без окончания в 1–3 буквы).
static func similar_words(a: String, b: String) -> bool:
	if a.length() < 3 or b.length() < 3:
		return a == b
	if distance(a, b) <= allowed(mini(a.length(), b.length())):
		return true
	var common := 0
	while common < mini(a.length(), b.length()) and a[common] == b[common]:
		common += 1
	# Общее начало от 4 букв: «собака» ~ «собаками», но не «кошка» ~ «кошмар».
	return common >= 4 and a.length() - common <= 3 and b.length() - common <= 3

static func similar(a: String, b: String) -> bool:
	var x := normalize(a)
	var y := normalize(b)
	if x.is_empty() or y.is_empty():
		return false
	if x == y or distance(x, y) <= allowed(mini(x.length(), y.length())):
		return true
	for left: String in x.split(" ", false):
		if left.length() < 3:
			continue
		for right: String in y.split(" ", false):
			if right.length() >= 3 and similar_words(left, right):
				return true
	return false
