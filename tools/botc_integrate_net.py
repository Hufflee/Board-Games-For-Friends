"""Адресное подключение Clocktower; перед записью проверяет маркеры текущего Net, не трогает другие блоки."""
from pathlib import Path
import sys
sys.stdout.reconfigure(encoding='utf-8')

root = Path(__file__).resolve().parents[1]
path = root / 'games/king_of_12/net/net.gd'
text = path.read_text(encoding='utf-8')
original_text = text
if 'var bc = null' in text:
    raise SystemExit('Clocktower уже подключён; повторное применение запрещено')


def replace(old, new, count=1):
    global text
    found = text.count(old)
    if found != count:
        raise RuntimeError(f'Маркер: ожидалось {count}, найдено {found}: {old[:100]!r}')
    text = text.replace(old, new)


replace('const PARTY_CAPACITY := 10', 'const NETWORK_CAPACITY := 16  # Clocktower: 15 игроков и отдельный рассказчик.\nconst PARTY_CAPACITY := 10')
replace('const LOCAL_GAMES := [', 'const LOCAL_GAMES := ["blood_on_the_clocktower", ')
replace('"6fd6a8"]', '"6fd6a8", "c47cba", "94a863"]')
replace('var settings := {', 'var settings := {"bc_edition": "tb", "bc_storyteller": 0, ')
replace('var mk = null', 'var bc = null  # Clocktower: правила на хосте, отдельные приватные view.\nvar bc_view_seat := 0\nvar bc_bridge: RefCounted = preload("res://games/blood_on_the_clocktower/logic/bc_session.gd").new(self)\nvar mk = null')
replace('peer.create_server(port, PARTY_CAPACITY - 1)', 'peer.create_server(port, NETWORK_CAPACITY - 1)')
replace('steam.createLobby(STEAM_LOBBY_PUBLIC, PARTY_CAPACITY)', 'steam.createLobby(STEAM_LOBBY_PUBLIC, NETWORK_CAPACITY)')
replace('\tmk = null\n', '\tmk = null\n\tbc = null\n\tbc_view_seat = 0\n\tbc_bridge.reset_match()\n', text.count('\tmk = null\n'))
replace('func _reset_host() -> void:\n', 'func _reset_host() -> void:\n\tbc_bridge.reset_lobby()\n')
replace('_rpc_hello.rpc_id(1, my_name, my_steam_id)', '_rpc_hello.rpc_id(1, my_name, my_steam_id, bc_bridge.resume_token)')
replace('func _rpc_hello(player_name: String, steam_id: int = 0) -> void:', 'func _rpc_hello(player_name: String, steam_id: int = 0, resume_key: String = "") -> void:')
replace('''		for s in disconnected:
			if disconnected[s] == nm:
				seat = s''', '''		if bc != null:
			seat = bc_bridge.resume_seat(resume_key)
		else:
			for s in disconnected:
				if disconnected[s] == nm:
					seat = s''')
replace('members.size() + bots >= PARTY_CAPACITY', 'members.size() + bots >= party_capacity()')
replace('var maximum: int = PARTY_CAPACITY if party_game == "the_gang" else MAX_PLAYERS', 'var maximum: int = NETWORK_CAPACITY if party_game == "blood_on_the_clocktower" else (PARTY_CAPACITY if party_game == "the_gang" else MAX_PLAYERS)')
replace('func _broadcast_lobby() -> void:\n', 'func _broadcast_lobby() -> void:\n\tbc_bridge.prepare_lobby()\n\tif mode == "steam" and is_host() and steam_ok and lobby_id != 0 and steam.has_method("setLobbyMemberLimit"):\n\t\tsteam.setLobbyMemberLimit(lobby_id, party_capacity())\n')
replace('"settings": settings.duplicate(true),', '"settings": bc_bridge.public_settings(),')
replace('''	if mode != "offline":
		_rpc_lobby.rpc(data)
''', '''	if mode != "offline":
		_rpc_lobby.rpc(data)
	bc_bridge.send_setup()
''')
replace('var minimum := 3 if party_game in ["the_gang", "khorom"] else 2', '''var minimum := 3 if party_game in ["the_gang", "khorom"] else 2
	if party_game == "blood_on_the_clocktower":
		maximum = NETWORK_CAPACITY
		minimum = int(bc_bridge.Data.EDITIONS.get(str(settings.get("bc_edition", "tb")), {"minimum": 5}).minimum) + 1''')
replace('not party_game in ["machi_koro",', 'not party_game in ["blood_on_the_clocktower", "machi_koro",')
replace('\telif party_game == "machi_koro":', '''	elif party_game == "blood_on_the_clocktower":
		var bc_error: String = bc_bridge.create(players)
		if not bc_error.is_empty():
			return bc_error
		auto_advance_time = 0.0
	elif party_game == "machi_koro":''')
replace(' and mk == null and cg == null', ' and mk == null and bc == null and cg == null', text.count(' and mk == null and cg == null'))
replace(' or mk != null or cg != null', ' or mk != null or bc != null or cg != null', text.count(' or mk != null or cg != null'))
replace('\thost_tools.before_action(kind)\n', '''	if bc != null:
		bc_bridge.handle_action(peer, seat, kind, arg)
		return
	host_tools.before_action(kind)
''')
replace('''	if mk != null:
		if mk.tick(delta):''', '''	if bc != null:
		if bc.tick(delta):
			_push_state()
		return
	if mk != null:
		if mk.tick(delta):''')
replace('\t_match_metrics.observe(game_id,party_game,_game_obj(),seat_peers)', '\tif bc == null:\n\t\t_match_metrics.observe(game_id,party_game,_game_obj(),seat_peers)', 2)
replace('''	elif mk != null:
		phase = mk.phase''', '''	elif bc != null:
		phase = bc.phase
	elif mk != null:
		phase = mk.phase''')
replace('''	elif mk != null:
		v = mk.get_view''', '''	elif bc != null:
		v = bc_bridge.view(s, show_all)
	elif mk != null:
		v = mk.get_view''')
replace('v["personal_stats"] = _match_metrics.snapshot(s)', 'v["personal_stats"] = {} if bc != null else _match_metrics.snapshot(s)')
replace('''	if bool(v.get("game_paused", false)) != bool(view.get("game_paused", false)):''', '''	if str(v.get("game", "")) == "blood_on_the_clocktower" and v.has("resume_token"):
		bc_bridge.resume_token = str(v.resume_token)
	if bool(v.get("game_paused", false)) != bool(view.get("game_paused", false)):''')
replace('''func _gp() -> Array:
''', '''func _gp() -> Array:
	if bc != null:
		return bc.players
''')
replace('''func turn_limit() -> float:
''', '''func turn_limit() -> float:
	if bc != null:
		return INF
''')
replace('for o in [cg, mk,', 'for o in [bc, cg, mk,')
text += '''

## Предел существующей пати не меняется у остальных игр.
func party_capacity() -> int:
	return NETWORK_CAPACITY if party_game == "blood_on_the_clocktower" else PARTY_CAPACITY

func bc_configure(options: Dictionary) -> void:
	var revision := int(bc_bridge.setup_view.get("revision", -1))
	if is_host():
		bc_bridge.configure(1, options, revision)
	else:
		_rpc_bc_configure.rpc_id(1, options, revision)

@rpc("any_peer", "reliable")
func _rpc_bc_configure(options: Dictionary, revision: int) -> void:
	if is_host():
		bc_bridge.configure(multiplayer.get_remote_sender_id(), options, revision)

@rpc("authority", "reliable")
func _rpc_bc_setup_data(packet: Dictionary) -> void:
	bc_bridge.receive_setup(packet)
'''
current = path.read_text(encoding='utf-8')
if current != original_text:
    raise RuntimeError('Net изменён другой сессией во время подготовки')
# Последняя проверка исключает запись поверх параллельных правок.
original = (root / 'backups/botc_integration_2026-11-05/net_before_write.gd')
original.write_text(current, encoding='utf-8')
path.write_text(text, encoding='utf-8')
print('Clocktower: Net подключён адресными заменами')
