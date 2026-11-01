class_name CGBlocks
extends RefCounted
## Каталог разрешённых блоков пользовательской игры. Никакой пользовательский код не выполняется.

const EVENTS := ["start", "round_start", "turn_start", "turn_end", "phase_enter", "phase_exit", "button", "card", "move", "rolled", "timeout"]
const SOUNDS := ["click", "card_place", "card_flip", "shuffle", "chip", "chips_win"]
const EXPRESSIONS := ["literal", "actor", "current", "leader", "next", "player", "players_count", "team", "round", "turn", "index", "answer", "card", "top", "zone", "count", "property", "var", "random", "add", "sub", "mul", "div", "min", "max", "eq", "ne", "lt", "le", "gt", "ge", "and", "or", "not", "has", "dice_sum", "dice_count", "dice_value"]
## Значения — обязательные поля; типизированные гнёзда UI строятся по этим именам.
const OPS := {
	"shuffle": ["zone"], "deal": ["from", "to", "count"], "draw": ["from", "to", "count"],
	"move": ["card", "to"], "open": ["card"], "close": ["card"], "show": ["card"], "collect": ["to"],
	"roll": ["count"], "roll_player": ["count", "player"], "next": [], "phase": ["phase"],
	"skip": ["player"], "eliminate": ["player"], "leader": ["player"],
	"ask_card": ["player", "zone"], "ask_player": ["player"], "ask_option": ["player", "options"],
	"ask_number": ["player", "min", "max"], "set": ["var", "value"], "change": ["var", "value"],
	"if": ["condition", "then"], "repeat": ["count", "body"], "each_player": ["body"], "each_card": ["zone", "body"],
	"wait": ["seconds"], "stop": [], "log": ["text"], "hint": ["text"], "sound": ["name"],
	"win": ["player"], "lose": [], "finish": ["var"],
}

static func category(op: String) -> String:
	if op in ["shuffle", "deal", "draw", "move", "open", "close", "show", "collect"]:
		return "Карты и зоны"
	if op.begins_with("ask"):
		return "Спросить"
	if op in ["roll", "roll_player"]:
		return "Кубики"
	if op in ["set", "change"]:
		return "Переменные"
	if op in ["if", "repeat", "each_player", "each_card", "wait", "stop"]:
		return "Управление"
	if op in ["win", "lose", "finish"]:
		return "Конец игры"
	return "Игроки и сообщения"

static func label(op: String) -> String:
	return {"start": "Начало игры", "round_start": "Начало раунда", "turn_start": "Начало хода", "turn_end": "Конец хода", "phase_enter": "Вход в фазу", "phase_exit": "Выход из фазы", "button": "Нажата кнопка", "card": "Выбрана карта", "rolled": "Кубики брошены", "timeout": "Время хода вышло",
		"shuffle": "Перемешать зону", "deal": "Раздать карты", "draw": "Взять карты", "move": "Переместить карту", "open": "Открыть карту", "close": "Закрыть карту", "show": "Показать карту", "collect": "Собрать карты", "roll": "Бросить кубики", "roll_player": "Попросить бросить кубики", "next": "Передать ход", "phase": "Перейти к фазе", "skip": "Пропустить ход", "eliminate": "Выбыть", "leader": "Назначить ведущего", "set": "Установить переменную", "change": "Изменить переменную", "if": "Если / иначе", "repeat": "Повторить", "each_player": "Для каждого игрока", "each_card": "Для каждой карты", "wait": "Подождать", "stop": "Закончить цепочку", "log": "Записать в журнал", "hint": "Показать подсказку", "sound": "Звук", "win": "Победа", "lose": "Поражение", "finish": "Итоги по очкам", "ask_card": "Выбрать карту", "ask_player": "Выбрать игрока", "ask_option": "Выбрать вариант", "ask_number": "Выбрать число"}.get(op, "Пустое действие")

static func event_label(kind: String) -> String:
	return "Компонент перенесён" if kind == "move" else label(kind)
