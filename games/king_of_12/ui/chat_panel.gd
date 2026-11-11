class_name K12ChatPanel
extends Control
## Чат экрана — теперь только «представитель» общего окна «Общение» (hub/comms_panel.gd, Net.chat.panel()).
## Игры по-прежнему создают K12ChatPanel в лобби и за столом и пользуются его `expanded`, `unread()`,
## `_input`, `docked_top`; само окно одно на всю игру, двигается и не пропадает при смене экрана.
## Пока на экране есть хотя бы один такой узел, работают Enter (писать в чат) и быстрые реплики 1–8.

const REACTIONS := ["Думаю...", "Блефую!", "Кидаю кость!", "Хитро!", "Ой…", "Мне повезёт!", "Удивительно!", "Эй, вы ещё здесь?"]

## Игрок пишет в чат прямо сейчас (окно раскрыто на чате и поле в фокусе). Присвоить true — раскрыть чат,
## false — свернуть. Игры проверяют это, чтобы не перехватывать клавиши у чата.
var expanded: bool:
	get:
		return _panel() != null and bool(_panel().call("chat_focused"))
	set(value):
		if not is_inside_tree():
			return  # лобби при создании просило «раскрыть» — общее окно остаётся таким, каким его оставил игрок
		if value:
			_panel().call("open_chat", false)
		elif bool(_panel().call("chat_open")):
			_panel().call("set_mode", 1)

var corner_margin := Vector2(14, 14)  # осталось для совместимости: окно само помнит своё место
var docked_top := false
var external_button := false
var quick_open := false

## Поле ввода общего окна (его черновик читают и возвращают игры при пересборке экрана).
var _input: LineEdit:
	get:
		return _panel().call("input_edit") if _panel() != null else null

var _counted := false


func _panel() -> Control:
	return Net.chat.panel() if is_instance_valid(Net.chat) else null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ZERO


func _enter_tree() -> void:
	if not _counted and _panel() != null:
		_counted = true
		_panel().set("proxies", int(_panel().get("proxies")) + 1)


func _exit_tree() -> void:
	if _counted and _panel() != null:
		_counted = false
		_panel().set("proxies", maxi(0, int(_panel().get("proxies")) - 1))


## Раскрыть окно «Общение» или свернуть его (кнопка «Общение» в верхней полосе).
func toggle() -> void:
	_panel().call("toggle")


func unread() -> int:
	return int(Net.chat.unread_total())


## Ряд кнопок быстрых реакций.
static func reactions_row() -> HBoxContainer:
	var row := K12UI.hbox(4)
	for r in REACTIONS:
		var b := K12UI.button(r, K12UI.CAP)
		b.pressed.connect(func(): Net.send_chat(r, "emote"))
		row.add_child(b)
	return row
