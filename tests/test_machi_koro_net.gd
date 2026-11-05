extends SceneTree
## Контракт локального Net и отмены событий Мачи Коро. Запуск: --headless --audio-driver Dummy --script res://tests/test_machi_koro_net.gd.

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ОШИБКА NET: " + message)

func _run() -> void:
	var net: Node = root.get_node("Net")
	net.host_offline("machi_koro")
	net.set_bots(5)
	check(not net.start_game().is_empty(), "шесть мест не обходят предел 5")
	net.set_bots(4)
	check(net.start_game().is_empty(), "пять мест запускаются")
	check(net.mk != null and net.view.hotseat and net.view.you == net.mk.current, "локальный экран принадлежит текущему месту")
	for player: Dictionary in net.mk.players:
		check(not player.bot, "местный игрок не бот")
	check(not net.mk.can_spectate() and not net.can_spectate(), "нет передачи места несуществующему боту")
	check(not bool(net.host_tools.info().timer_supported) and net.turn_limit() == INF, "нет фиктивного таймера")
	net.mk.phase = "build"
	net.mk.coins[net.mk.current] = 8
	net.mk.revision += 1
	net._push_state()
	var seat: int = net.mk.current
	var before: int = net.mk.count_type(seat, "bakery")
	net.send_action("buy", {"card": "bakery", "revision": net.mk.revision})
	check(not net.mk.event.is_empty() and net.mk.coins[seat] == 8, "покупка пока только запланирована")
	check(net.host_tools.undo(), "отмена запланированной покупки")
	check(net.mk.event.is_empty() and net.mk.coins[seat] == 8 and net.mk.count_type(seat, "bakery") == before, "отмена вернула исходное состояние")
	check(net.host_tools.redo(), "повтор события")
	check(not net.mk.event.is_empty(), "повтор восстановил событие, а не сразу начислил")
	net.mk.tick(100)
	check(net.mk.coins[seat] == 7 and net.mk.count_type(seat, "bakery") == before + 1, "повторённая покупка применена один раз")
	net.return_to_party()
	check(net.mk == null and not net.in_game, "возврат в пати очищает игру")
	net.host_offline("perudo")
	net.set_bots(1)
	check(net.start_game().is_empty() and net.perudo != null and net.mk == null, "другая игра получила только свои правила")
	net.host_offline("machi_koro")
	net.set_bots(1)
	check(net.start_game().is_empty() and net.perudo == null and net.mk != null, "переход обратно не сохраняет старый движок")
	var revision: int = net.mk.revision
	net._handle_action(333333, "roll", {"count": 1, "revision": revision})
	check(net.mk.revision == revision, "неизвестный peer не может действовать")
	net.leave()
	check(net.mk == null, "выход очищает Мачи Коро")
	print("MK_NET: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)
