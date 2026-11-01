extends SceneTree
## «Перемешать игроков» (Net.settings.shuffle_seats): места тасуются при старте вместе с подключениями;
## настройки «по местам» (знающий Things in Rings) идут за игроком; Перудо не трогаем (своя рассадка).
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_seat_shuffle.gd
var checks := 0
var errors := 0
var net: Node


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", text)


func _start(game: String, bots: int, shuffle: bool, extra: Dictionary = {}) -> void:
	net.end_game()
	net.host_offline(game)
	net.set_bots(bots)
	net.set_setting("shuffle_seats", shuffle)
	for key: String in extra:
		net.set_setting(key, extra[key])
	var error: String = net.start_game()
	check(error.is_empty(), "%s: партия началась (%s)" % [game, error])


func _run() -> void:
	net = root.get_node("Net")
	net.my_name = "Хост"
	var seats := {}
	for i: int in 30:
		_start("poker", 5, true)
		var mine: int = net.seat_peers.find(1)
		check(mine >= 0 and str(net.pkr.players[mine].name) == "Хост", "покер: место хоста совпадает с его записью")
		seats[mine] = true
	check(seats.size() >= 3, "покер: место хоста при перемешивании меняется (%d разных)" % seats.size())
	_start("poker", 5, false)
	check(net.seat_peers.find(1) == 0, "без перемешивания хост — первое место")
	# Things in Rings: знающий выбран в лобби по месту входа — после перемешивания это тот же человек
	var moved := false
	for i: int in 20:
		_start("things_in_rings", 3, true, {"tr_knower": 0})
		var host_seat: int = net.seat_peers.find(1)
		check(int(net.tir.knower) == host_seat, "Things in Rings: знающий — тот же игрок после перемешивания")
		moved = moved or host_seat != 0
	check(moved, "Things in Rings: места действительно перемешивались")
	# Перудо — своя рассадка в партии, настройка не тасует
	_start("perudo", 4, true)
	check(net.seat_peers.find(1) == 0, "Перудо: порядок входа (рассадка — в самой партии)")
	net.end_game()
	print("ИТОГ: проверок %d, ошибок %d" % [checks, errors])
	quit(1 if errors > 0 else 0)
