extends "res://games/king_of_12/net/net.gd"
## Тестовый транспорт: штатные Net.dispatch/view, без сокетов и без пользовательских файлов.
var delivered: Array = []

func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	pass

func _send_view(peer: int, value: Dictionary) -> void:
	delivered.append({"peer": peer, "value": value.duplicate(true)})
