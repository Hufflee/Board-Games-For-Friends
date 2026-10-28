extends RefCounted
## Отбор состояния транспорта без игровых данных/адресов/ключей и с ограничением размера.
static func safe_state(info: Dictionary) -> Dictionary:
	var out := {}
	for raw_key in info:
		var key := str(raw_key).to_lower()
		if not key in ["state", "connection_state", "end_reason", "end_debug", "description", "debug_description", "connection_description"]:
			continue
		var value: Variant = info[raw_key]
		if value is int or value is float or value is bool:
			out[str(raw_key)] = value
		elif value is String:
			out[str(raw_key)] = value.left(512)
	return out


static func safe_event(event: Dictionary) -> Dictionary:
	var out := {}
	for key in ["событие", "описание"]:
		if event.get(key) is String:
			out[key] = str(event[key]).left(512)
	for key in ["время_мс", "handle", "предыдущее_состояние", "код", "состояние"]:
		if event.get(key) is int:
			out[key] = event[key]
	if event.get("данные") is Dictionary:
		out["данные"] = safe_state(event.данные)
	return out
