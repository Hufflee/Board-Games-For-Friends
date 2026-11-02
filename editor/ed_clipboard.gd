extends RefCounted
## Системный буфер редактора: JSON слоёв/компонентов/логики и необходимые проверенные ассеты.
const Library := preload("res://games/custom/logic/cg_library.gd")
const Package := preload("res://games/custom/logic/cg_package.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const LIMIT := 16 * 1024 * 1024

static func encode(document: RefCounted, kind: String, data: Dictionary) -> String:
	var assets := {}
	var serialized := JSON.stringify(data)
	for hash_value: String in document.data.get("assets", {}):
		if not serialized.contains(hash_value):
			continue
		var entry: Dictionary = document.data.assets[hash_value]
		var path := str(entry.get("path", ""))
		if not Package.path_valid(path) or not path.begins_with("assets/"):
			return ""
		var file := FileAccess.open(Library.folder(str(document.data.id)) + "/" + path, FileAccess.READ)
		if file == null or file.get_length() > Package.FONT_LIMIT:
			return ""
		var bytes := file.get_buffer(file.get_length())
		assets[hash_value] = {"meta": entry, "bytes": Marshalls.raw_to_base64(bytes)}
	var result := JSON.stringify({"editor_clipboard": 1, "kind": kind, "data": data, "assets": assets})
	return result if result.length() <= LIMIT else ""

static func decode(text: String) -> Dictionary:
	if text.length() > LIMIT:
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {}
	var result: Dictionary = parser.data
	if result.get("editor_clipboard") != 1 or not result.get("kind") is String or not result.get("data") is Dictionary or not result.get("assets") is Dictionary:
		return {}
	# Бинарные ассеты закодированы длинной base64-строкой и имеют отдельный предел.
	# Лимит4096 для обычного текста по-прежнему применяется к данным и метаданным.
	if not Definition._json_only({"kind": result.kind, "data": result.data}, 0) or result.assets.size() > 64:
		return {}
	var checked := {}
	for hash_value: String in result.assets:
		var entry: Variant = result.assets[hash_value]
		if not entry is Dictionary or not entry.get("meta") is Dictionary or not entry.get("bytes") is String:
			return {}
		if not Package.hash_valid(hash_value) or not Definition._json_only(entry.meta, 0):
			return {}
		var path := str(entry.meta.get("path", ""))
		var ext := path.get_extension()
		var dir := "fonts" if ext in ["ttf", "otf"] else "img"
		if ext not in ["png", "jpg", "webp", "ttf", "otf"] or path != "assets/" + dir + "/" + hash_value + "." + ext:
			return {}
		var bytes := Marshalls.base64_to_raw(entry.bytes)
		if bytes.size() > Package.FONT_LIMIT or Package.sha(bytes) != hash_value:
			return {}
		if dir == "img":
			var dimensions := Package.image_size(bytes, ext)
			if dimensions.x < 1 or dimensions.y < 1 or maxi(dimensions.x, dimensions.y) > 2048:
				return {}
			if Package.image_from_bytes(bytes, ext) == null:
				return {}
		elif bytes.size() < 12 or bytes.slice(0, 4) not in [PackedByteArray([0, 1, 0, 0]), "OTTO".to_ascii_buffer()]:
			return {}
		checked[hash_value] = {"meta": entry.meta, "bytes": bytes}
	result.assets = checked
	return result

static func paste(document: RefCounted, payload: Dictionary, kind: String, path: Array) -> String:
	if payload.is_empty() or payload.get("kind") != kind:
		return "В буфере нет подходящего элемента редактора."
	var copy: Dictionary = document.data.duplicate(true)
	if kind == "chain" and path != ["rules", "chains"]:
		return "Цепочку можно вставить только в список событий."
	if kind == "block" and not _block_array(copy, path):
		return "Выберите цепочку или ветвь для вставки блока."
	if kind == "face_layer" and (path.size() != 5 or path.slice(0, 2) != ["elements", "decks"] or path.slice(3) != ["face", "layers"]):
		return "Слой лица можно вставить только в шаблон карты."
	if not copy.has("assets"):
		copy.assets = {}
	var parent: Variant = copy
	for key: Variant in path:
		if parent is Array:
			if not key is int or key < 0 or key >= parent.size():
				return "Не найдена целевая коллекция."
		elif parent is Dictionary:
			if not parent.has(key):
				parent[key] = []
		else:
			return "Не найдена целевая коллекция."
		parent = parent[key]
	var limit := 64 if kind in ["layer", "face_layer"] else (200 if kind == "block" else 300)
	if not parent is Array or parent.size() >= limit:
		return "Достигнут предел элементов."
	var element: Dictionary = payload.data.duplicate(true)
	if kind in ["chain", "block"]:
		if not Definition.zone_references_valid(copy, element) or not _logic_references(copy, element):
			return "В этой игре нет нужной зоны, переменной, кнопки или подключённого словаря."
		var used := {}
		for chain: Dictionary in copy.rules.chains:
			_block_ids(chain.get("blocks", []), used, false)
		if kind == "chain":
			if not element.get("blocks") is Array or not element.get("event") is Dictionary:
				return "В буфере повреждённая цепочка."
			_block_ids(element.blocks, used, true)
		else:
			_block_ids([element], used, true)
	elif kind not in ["layer", "face_layer"]:
		var prefix := str(element.get("id", "element"))
		var number := 1
		while parent.any(func(item): return item.get("id") == prefix + "_copy" + str(number)):
			number += 1
		element.id = prefix + "_copy" + str(number)
	parent.append(element)
	for hash_value: String in payload.assets:
		copy.assets[hash_value] = payload.assets[hash_value].meta.duplicate(true)
	if not Definition.validate(copy).errors.is_empty():
		return "Элемент не подходит этой игре: проверьте связанные зоны и переменные."
	for hash_value: String in payload.assets:
		var entry: Dictionary = payload.assets[hash_value]
		var file_path := Library.folder(str(document.data.id)) + "/" + str(entry.meta.path)
		DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
		if Library._atomic_write(file_path, entry.bytes) != OK:
			return "Не удалось сохранить ассет из буфера."
	if not document.replace(copy, "Вставить из буфера"):
		return "Не удалось вставить элемент."
	return ""

## Гнёзда с выражениями и таблицы компонентов не являются массивами исполняемых блоков.
static func _block_array(data: Dictionary, path: Array) -> bool:
	if path.size() < 4 or path.slice(0, 2) != ["rules", "chains"] or not path[2] is int or path[3] != "blocks":
		return false
	var chains: Array = data.rules.chains
	if path[2] < 0 or path[2] >= chains.size():
		return false
	var current: Variant = chains[path[2]].get("blocks")
	var offset := 4
	while offset < path.size():
		if offset + 1 >= path.size() or not current is Array or not path[offset] is int:
			return false
		var index: int = path[offset]
		if index < 0 or index >= current.size() or path[offset + 1] not in ["then", "else", "body"]:
			return false
		if not current[index] is Dictionary:
			return false
		current = current[index].get(path[offset + 1])
		offset += 2
	return current is Array

## Меняем только идентификаторы исполняемых блоков, сохраняя ссылки выражений на зоны и переменные.
static func _block_ids(blocks: Array, used: Dictionary, renew: bool, next_id: int = 1) -> int:
	for value: Variant in blocks:
		if not value is Dictionary:
			continue
		var block: Dictionary = value
		if renew:
			while used.has("block_copy" + str(next_id)):
				next_id += 1
			block["id"] = "block_copy" + str(next_id)
			next_id += 1
		used[str(block.get("id", ""))] = true
		for branch: String in ["then", "else", "body"]:
			if block.get(branch) is Array:
				next_id = _block_ids(block[branch], used, renew, next_id)
	return next_id

static func _logic_references(data: Dictionary, value: Variant) -> bool:
	if value is Array:
		for entry: Variant in value:
			if not _logic_references(data, entry):
				return false
	elif value is Dictionary:
		var op := str(value.get("op", ""))
		if op == "literal":
			return true
		if op == "dictionary_word" and data.rules.get("dictionary", "") != "shared":
			return false
		if op == "var" or op in ["set", "change", "finish"]:
			var key: Variant = value.get("id", "") if op == "var" else value.get("var", "")
			if key is String and not data.rules.get("vars", []).any(func(entry): return entry.get("id") == key):
				return false
		if op == "zone":
			var found := false
			for screen: Dictionary in data.layout.screens:
				for item: Dictionary in screen.get("items", []):
					found = found or item.get("kind") == "zone" and item.get("id") == value.get("id")
			if not found:
				return false
		if value.get("type") == "button":
			var found := false
			for screen: Dictionary in data.layout.screens:
				for item: Dictionary in screen.get("items", []):
					found = found or item.get("kind") == "button" and item.get("action", item.get("id")) == value.get("id")
			if not found:
				return false
		for entry: Variant in value.values():
			if not _logic_references(data, entry):
				return false
	return true
