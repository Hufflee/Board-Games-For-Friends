class_name EDCsv
extends RefCounted
## Таблица карт из CSV: кавычки, разделители, переносы внутри ячейки, колонка копий.

static func parse(text: String, separator: String = ",") -> Dictionary:
	if separator not in [",", ";", "\t"] or text.length() > 1024 * 1024:
		return {"error": "Неверный разделитель или таблица больше 1 МБ."}
	var lines: Array = []
	var row: Array = []
	var cell := ""
	var quoted := false
	var ended := false
	var index := 0
	text = text.trim_prefix("\ufeff").replace("\r\n", "\n").replace("\r", "\n")
	while index < text.length():
		var c := text[index]
		if c == "\"":
			if quoted and index + 1 < text.length() and text[index + 1] == "\"":
				cell += "\""
				index += 1
			elif quoted:
				quoted = false
				ended = true
			elif cell.is_empty() and not ended:
				quoted = true
			else:
				return {"error": "Кавычка внутри незаключённой ячейки."}
		elif not quoted and (c == separator or c == "\n"):
			row.append(cell)
			cell = ""
			ended = false
			if c == "\n":
				lines.append(row)
				row = []
		elif ended:
			return {"error": "После закрывающей кавычки нужен разделитель."}
		else:
			cell += c
		index += 1
	if quoted:
		return {"error": "Не закрыта кавычка в таблице."}
	if not cell.is_empty() or not row.is_empty():
		row.append(cell)
		lines.append(row)
	if lines.size() < 2 or lines.size() > 301:
		return {"error": "Таблице нужны заголовки и от 1 до 300 строк карт."}
	var headers: Array = lines.pop_front()
	if headers.size() > 64:
		return {"error": "В таблице не больше 64 колонок."}
	var columns: Array = []
	var seen := {}
	for header: String in headers:
		if header.strip_edges().is_empty() or seen.has(header):
			return {"error": "Заголовки должны быть заполнены и не повторяться."}
		seen[header] = true
		if header not in ["Копий", "copies"]:
			columns.append({"id": header, "type": "text"})
	var rows: Array = []
	var total := 0
	for line: Array in lines:
		if line.size() != headers.size():
			return {"error": "В строке не совпало число колонок."}
		var fields := {"copies": 1}
		for i in headers.size():
			var key := str(headers[i])
			if str(line[i]).length() > 4096:
				return {"error": "Ячейка таблицы длиннее 4096 символов."}
			if key in ["Копий", "copies"]:
				if not str(line[i]).is_valid_int() or int(line[i]) < 1 or int(line[i]) > 300:
					return {"error": "Копий должно быть от 1 до 300."}
				fields.copies = int(line[i])
			else:
				fields[key] = str(line[i])
		total += int(fields.copies)
		rows.append(fields)
	if total > 300:
		return {"error": "Таблица содержит больше 300 копий карт."}
	return {"error": "", "columns": columns, "rows": rows}
