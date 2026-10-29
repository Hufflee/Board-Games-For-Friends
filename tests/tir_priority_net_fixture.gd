extends "res://games/king_of_12/net/net.gd"
## Локальная доставка снимков для адресной проверки серверных прав без транспорта.

var delivered: Array = []


func _push_state() -> void:
	delivered.clear()
	for seat: int in seat_peers.size():
		delivered.append(_seat_view(seat, [], 0.0, mode == "offline"))
	delivered.append(_seat_view(-1, [], 0.0, false))
