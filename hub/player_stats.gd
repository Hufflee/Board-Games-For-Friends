class_name PlayerStatsStore
extends RefCounted
## Личная статистика: накопительные снимки хоста, защита от повторов, последние 100 результатов.
const PATH := "user://player_statistics_v1.json"
var path: String
var data: Dictionary = {"version": 1, "games": {}, "sessions": {}}


func _init(storage_path: String = PATH) -> void:
	path = storage_path
	if FileAccess.file_exists(path):
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if (
			loaded is Dictionary
			and loaded.get("version") == 1
			and loaded.get("games") is Dictionary
			and loaded.get("sessions") is Dictionary
		):
			data = loaded


static func empty_row() -> Dictionary:
	return {
		"completed": 0,
		"wins": 0,
		"unrated": 0,
		"decisions": 0,
		"errors": 0,
		"remarks": 0,
		"messages": 0,
		"emotes": 0,
		"dice": {},
		"history": []
	}


static func _canonical_totals(source: Dictionary) -> Dictionary:
	var out: Dictionary = {"result": str(source.get("result", "")), "dice": {}}
	for key in ["decisions", "errors", "remarks", "messages", "emotes"]:
		out[key] = int(source.get(key, 0))
	for face in source.get("dice", {}):
		out.dice[str(face)] = int(source.dice[face])
	return out


## Прибавляем только разницу накопительных счётчиков; повторный или старый пакет не меняет результат.
func consume(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or int(snapshot.get("seat", -1)) < 0:
		return false
	var uid: String = str(snapshot.id) + "/" + str(snapshot.seat)
	var game: String = str(snapshot.game)
	var totals: Dictionary = _canonical_totals(snapshot.totals)
	var old: Dictionary = _canonical_totals(data.sessions.get(uid, {}))
	for key in ["decisions", "errors", "remarks", "messages", "emotes"]:
		totals[key] = maxi(int(totals[key]), int(old[key]))
	for face in old.dice:
		totals.dice[face] = maxi(int(totals.dice.get(face, 0)), int(old.dice[face]))
	if str(old.result) != "":
		totals.result = old.result
	if old == totals:
		return false
	var row: Dictionary = data.games.get(game, empty_row())
	for key in ["decisions", "errors", "remarks", "messages", "emotes"]:
		row[key] = int(row[key]) + maxi(0, int(totals.get(key, 0)) - int(old.get(key, 0)))
	for face in totals.get("dice", {}):
		row.dice[str(face)] = (
			int(row.dice.get(str(face), 0))
			+ maxi(0, int(totals.dice[face]) - int(old.get("dice", {}).get(str(face), 0)))
		)
	var match_id: String = str(snapshot.get("match_id", snapshot.id))
	var finished: Dictionary = data.get("finished", {})
	if str(totals.get("result", "")) != "" and not finished.has(match_id):
		var won: bool = totals.result == "win"
		if totals.result == "unrated":
			row["unrated"] = int(row.get("unrated", 0)) + 1
		else:
			row.completed = int(row.completed) + 1
			row.wins = int(row.wins) + (1 if won else 0)
			data["sequence"] = int(data.get("sequence", 0)) + 1
			row.history.append(
				{
					"id": str(snapshot.id),
					"won": won,
					"time": int(snapshot.get("time", Time.get_unix_time_from_system())),
					"order": int(data.sequence)
				}
			)
			while row.history.size() > 100:
				row.history.pop_front()
		finished[match_id] = true
		data["finished"] = finished
	data.games[game] = row
	data.sessions[uid] = totals.duplicate(true)
	_save()
	return true


## Временный файл не позволяет оборванной записи повредить предыдущую статистику.
func _save() -> void:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("Не удалось сохранить статистику игрока")
		return
	file.store_string(JSON.stringify(data))
	file.close()
	var err := DirAccess.rename_absolute(path + ".tmp", path)
	if err != OK:
		push_error("Не удалось обновить файл статистики: %s" % error_string(err))


func summary(game: String = "") -> Dictionary:
	if game != "":
		return (data.games.get(game, empty_row()) as Dictionary).duplicate(true)
	var total := empty_row()
	for row: Dictionary in data.games.values():
		for key in ["completed", "wins", "unrated", "decisions", "errors", "remarks", "messages", "emotes"]:
			total[key] = int(total[key]) + int(row.get(key, 0))
		for face in row.dice:
			total.dice[face] = int(total.dice.get(face, 0)) + int(row.dice[face])
		total.history.append_array(row.history)
	total.history.sort_custom(func(a, b): return int(a.get("order", a.time)) < int(b.get("order", b.time)))
	total.history = total.history.slice(maxi(0, total.history.size() - 100))
	return total


static func sorted_dice(row: Dictionary) -> Array:
	var out: Array = []
	var count := 0
	for value in row.dice.values():
		count += int(value)
	for face in row.dice:
		out.append(
			{
				"face": int(face),
				"count": int(row.dice[face]),
				"percent": 100.0 * int(row.dice[face]) / maxi(1, count)
			}
		)
	out.sort_custom(
		func(a, b): return int(a.count) > int(b.count) if a.count != b.count else int(a.face) < int(b.face)
	)
	return out


static func graph_values(history: Array) -> Array:
	var out: Array = [0]
	for entry: Dictionary in history:
		out.append(int(out.back()) + (1 if entry.won else -1))
	return out
