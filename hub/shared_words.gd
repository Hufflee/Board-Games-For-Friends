class_name SharedWords
extends RefCounted
## Общий словарь 1000 нарицательных русских слов. Случайный выбор — ГСЧ хоста.
const PATH := "res://hub/data/shared_words.json"
static var _words: Array = []

static func all() -> Array:
	if _words.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Array:
			_words = parsed
	return _words.duplicate()

static func sample(rng: RandomNumberGenerator, count: int = 1) -> Array:
	var pool := all()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var old: String = pool[i]
		pool[i] = pool[j]
		pool[j] = old
	return pool.slice(0, clampi(count, 0, pool.size()))

static func pick(rng: RandomNumberGenerator) -> String:
	var pool := all()
	return str(pool[rng.randi_range(0, pool.size() - 1)]) if not pool.is_empty() else ""

static func cards(width: int) -> Array:
	var pool := all()
	var result: Array = []
	for offset in range(0, pool.size(), width):
		result.append(pool.slice(offset, offset + width))
	return result
