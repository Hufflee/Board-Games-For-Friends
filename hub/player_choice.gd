extends RefCounted
## Проверяет ответы на выбор по сохранённому хостом списку вариантов.

static func request(seat: int, options: Array, optional: bool = false) -> Dictionary:
	return {"seat": seat, "options": options.duplicate(true), "optional": optional}


static func accepts(choice: Dictionary, seat: int, answer: Variant) -> bool:
	if seat < 0 or int(choice.get("seat", -1)) != seat:
		return false
	return (answer == null and bool(choice.get("optional", false))) or choice.get("options", []).has(answer)
