extends Node
## Автозагрузка Net: пати (подключение Steam / ENet / офлайн), лобби игры и хостовая партия.
##
## Пати — это само соединение и список друзей. Оно живёт, пока хост его не закроет:
## хост выбирает игру (select_game), завершает партию (end_game) или возвращает всех
## к выбору игры (return_to_party) — соединение и чат при этом сохраняются.
##
## Вся логика игры выполняется на хосте (peer 1). Клиенты шлют только действия
## через send_action() и получают своё состояние в state_changed.
## Доступ к Steam — только через Engine.get_singleton("Steam"): в редакторе Godot
## из Steam аддон GodotSteam не загружается, и код должен работать без него.

signal lobby_changed
signal state_changed(view: Dictionary)
signal game_started
signal game_ended  # партия закончена, все вернулись в лобби игры
signal party_game_changed(game_id: String)  # хост выбрал игру ("" — к выбору игры)
signal session_closed(reason: String)
signal status_changed(text: String)
signal chat_received(entry: Dictionary)
signal pause_changed
signal ghost_received(peer: int, data: Dictionary)  # «тень» чужого действия (фишку тащат) — без хоста-логики, только показать
signal steam_lobbies_changed

const ConnectionDiagnostics := preload("res://hub/connection_diagnostics.gd")
var last_disconnect: Dictionary = {}
var _steam_transport_events: Array[Dictionary] = []
var _leaving := false

const APP_ID := 480
const PORT := 24565
const MAX_PLAYERS := 8
const PARTY_CAPACITY := 10  # The Gang расширяет пати; пределы остальных игр сохраняются.
const LOBBY_TAG := "bgff_party"
const STEAM_LOBBY_FRIENDS_ONLY := 1
const STEAM_LOBBY_PUBLIC := 2
var bot_delay := 0.9  # пауза перед ходом бота
const AUTO_ROLL := 30.0  # человек не бросил кубик — бросаем за него
const REVEAL_SLACK := 20.0  # Оракул наступает во время вскрытия карт — даём время его досмотреть
const AUTO_PICK := 60.0  # победитель раунда долго не выбирает карту под кубик
## Цвета игроков: каждому случайный, клик по своему нику — сменить. По цвету видно, кто что сделал.
const PLAYER_COLORS := ["e6194b", "3cb44b", "f2c318", "4363d8", "f58231", "911eb4", "2ec4d6", "f032e6", "8fcf2b", "f59ac0", "2a9d8f", "9a6324", "34408f", "6fd6a8"]
const LOCAL_GAMES := ["wavelength", "dangerous_words", "hues_and_cues", "ready_set_bet", "word_slam", "tip_top", "tip_top_18", "not_a_hat", "gloom", "brodilka", "phantom_ink", "four_souls", "stillion", "the_gang"]  # офлайн — местные игроки, а не боты
const BOT_NAMES := ["Бот Аркадий", "Бот Варвара", "Бот Геннадий", "Бот Дарья", "Бот Евсей", "Бот Жанна", "Бот Захар"]

var auto_advance_time := 45.0  # через сколько секунд итог закрывается сам
var steam: Object = null
var steam_ok := false
var steam_error := ""
var my_name := "Игрок"
var mode := ""  # "", "offline", "enet", "steam"
var lobby_id := 0

# --- данные хоста ---
var members := {}  # peer_id -> {name}
var join_order: Array[int] = []
var bots := 0
var settings := {"deck_mode": "first", "manual": [], "promo": "", "tournament": true, "reveal_speed": "normal", "perudo_dice": 5, "perudo_maputo": true, "wl_mode": "teams", "wl_local_teams": [], "dw_rooms": "3-7", "dw_monster": "random", "dw_hard": false, "dw_curses": true, "dw_time": 60, "hc_laps": 0, "hc_free": false, "hc_mode": "classic", "rsb_speed": "normal", "ws_mode": "teams", "ws_cards": "standard", "ws_names": true, "ws_time": 60, "turn_time": 60, "tt_expert": false, "pi_roles": [], "fs_dlc": false, "st_bots": false, "st_lives": 3, "st_meter": 20, "st_casual": false}
var disconnected := {}  # место -> имя вылетевшего игрока (может вернуться)
var chat_log: Array = []
var last_join := {}  # куда подключались в последний раз — для «Вернуться в партию»
var my_steam_id := 0
var party_game := ""  # игра, выбранная хостом в пати ("" — пати на экране выбора игры)
var _create_game := ""  # какую игру выбрать сразу после создания пати
var game_id := ""
var tutorial := false
var _avatars := {}  # steam_id -> Texture2D
var rules: K12Rules = null  # «Дюжина короля»
var perudo: PerudoRules = null  # «Перудо»
var wavelength: WLRules = null  # «Длина волны»
var dwords: DWRules = null  # «Опасные слова»
var hues: HCRules = null  # «Оттенки и подсказки»
var rsb: RSBRules = null  # «На старт, ставки!»
var wslam: WSRules = null  # «Ворд Слэм»
var tiptop: TTRules = null  # «Тип Топ» (обе коробки)
var nothat: NHRules = null  # «Это не шляпа!»
var gloom: GLRules = null  # Gloom
var fours = null  # FSRules; без типа — Айзека может не быть в сборке (тогда он «Скоро»)
var gang = null  # TGRules: кооперативный покер, до10 игроков.
var tg_view_seat := 0
var fs_view_seat := 0
var stillion: STRules = null  # «Стиллион»
var _st_jev: STJev  # проверка незнакомых ответов нейросетью (только у хоста), своя на каждую партию
var _st_jev_for: STRules  # партия, к которой привязан _st_jev: вердикты старой партии не трогают новую
var _st_checking := -1  # номер ответа, отправленного в jev
var _st_verdict: Array = []  # вердикт, пришедший на паузе: [партия, no, ok, rarity] — применим после паузы
var _st_deck: Array = []  # колода вопросов на всю сессию лобби: не повторяются, пока хост не выйдет к выбору игры
var player_stats := PlayerStatsStore.new()
var _match_metrics := MatchMetrics.new()
var phantom: PIRules = null
var pi_view_seat := 0  # личный экран в локальной партии
var brod: BRRules = null  # «Большая бродилка»
var _rsb_roll_wait := 0.0
var rsb_go := false  # ведущий нажал «Начать гонку» — идёт отсчёт
var rsb_paused := false  # ведущий поставил гонку на паузу
var _rsb_go_at := 0.0
var _dw_turn_started := 0.0
var seat_peers: Array[int] = []  # место -> peer_id (0 = бот)
var ready_peers := {}
var in_game := false
var paused := false  # хост поставил партию на паузу: часы и ходы стоят
var _bot_wait := 0.0
var _phase_time := 0.0
var _stamp_turn := false  # после смены фазы — разослать состояние с новым временем хода
var _last_phase := ""

# --- данные клиента ---
var lobby_view := {}
var view := {}
var _client_start_pending := false
var _client_expected_match := ""

var _hosting_steam := false
var steam_public_lobbies: Array[Dictionary] = []
var steam_lobbies_loading := false
var steam_lobbies_error := ""
var _steam_lobby_refresh_again := false
var _steam_lobby_request := 0
var _steam_lobby_source: Object


func _ready() -> void:
	Diag.attach_net(self)
	settings["manual"] = K12Cards.FIRST_GAME.duplicate()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	add_child(load("res://hub/pause_layer.gd").new())  # пауза поверх любой игры
	add_child(load("res://hub/crash_report.gd").new())  # прошлый запуск вылетел — предложить отправить лог
	_init_steam()


func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		steam_error = "GodotSteam не загружен (в редакторе Godot из Steam это нормально — используйте собранную игру)."
		return
	steam = Engine.get_singleton("Steam")
	var r = steam.steamInitEx(APP_ID, true)
	var ok := false
	if typeof(r) == TYPE_DICTIONARY:
		ok = int(r.get("status", -1)) == 0
		if not ok:
			steam_error = "Steam не запущен или недоступен: %s" % r.get("verbal", r)
	else:
		ok = bool(r)
		if not ok:
			steam_error = "Steam не запущен или недоступен."
	steam_ok = ok
	if not ok:
		return
	my_name = steam.getPersonaName()
	my_steam_id = steam.getSteamID()
	player_stats = PlayerStatsStore.new("user://player_statistics_%d_v1.json"%my_steam_id)
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.join_requested.connect(_on_join_requested)
	steam.lobby_invite.connect(_on_lobby_invite)
	if steam.has_signal("network_connection_status_changed"):
		steam.connect("network_connection_status_changed", _on_steam_connection_status)
	if steam.has_signal("network_messages_session_failed"):
		steam.connect("network_messages_session_failed", _on_steam_message_failure)
	# Запуск по приглашению: +connect_lobby <id>
	var args := OS.get_cmdline_args()
	var i := args.find("+connect_lobby")
	if i >= 0 and i + 1 < args.size():
		join_steam.call_deferred(int(args[i + 1]))


func is_host() -> bool:
	return multiplayer.is_server()


func in_session() -> bool:
	return mode != ""


# =============================================================================
# Подключение
# =============================================================================

## game_id — игра, которую сразу выбрать в созданном пати ("" — остаться на экране выбора игры).
func host_offline(game_id: String = "king_of_12") -> void:
	leave()
	_create_game = game_id
	mode = "offline"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_host()
	party_game = _create_game
	bots = 1
	_broadcast_lobby()


func host_enet(port: int = PORT, game_id: String = "king_of_12") -> Error:
	leave()
	_create_game = game_id
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, PARTY_CAPACITY - 1)
	if err != OK:
		status_changed.emit("Не удалось открыть порт %d (ошибка %d)." % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	mode = "enet"
	_reset_host()
	party_game = _create_game
	_broadcast_lobby()
	return OK


func join_enet(address: String, port: int = PORT) -> Error:
	leave()
	last_join = {"mode": "enet", "ip": address}
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status_changed.emit("Не удалось подключиться (ошибка %d)." % err)
		return err
	multiplayer.multiplayer_peer = peer
	mode = "enet"
	status_changed.emit("Подключаемся к %s:%d…" % [address, port])
	return OK


func host_steam(game_id: String = "king_of_12") -> void:
	if not steam_ok:
		status_changed.emit(steam_error)
		return
	leave()
	_create_game = game_id
	_hosting_steam = true
	status_changed.emit("Создаём пати в Steam…")
	steam.createLobby(STEAM_LOBBY_PUBLIC, PARTY_CAPACITY)


func join_steam(id: int) -> void:
	if not steam_ok:
		status_changed.emit(steam_error)
		return
	if id <= 0:
		status_changed.emit("Неверный код лобби.")
		return
	leave()
	last_join = {"mode": "steam", "lobby": id}
	status_changed.emit("Входим в лобби…")
	steam.joinLobby(id)


## Окно приглашения друзей. Оверлей Steam не появляется, если игру запустили не из библиотеки Steam,
## поэтому список друзей — свой, внутри игры (кнопка оверлея там тоже есть, если он доступен).
func invite_friends() -> void:
	SteamInvite.open_panel()


## Друзья Steam: [{id, name, state, in_party}] — сначала те, кто в сети.
func steam_friends() -> Array:
	var list := []
	if not steam_ok:
		return list
	var in_party := {}
	for id in members:
		in_party[int(members[id].get("steam_id", 0))] = true
	for i in steam.getFriendCount(4):  # 4 — обычные друзья
		var fid: int = steam.getFriendByIndex(i, 4)
		list.append({"id": fid, "name": steam.getFriendPersonaName(fid), "state": steam.getFriendPersonaState(fid), "in_party": in_party.has(fid)})
	list.sort_custom(func(a, b):
		var oa: bool = int(a["state"]) != 0
		var ob: bool = int(b["state"]) != 0
		return oa and not ob or (oa == ob and str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0))
	return list


## Старые пати друзей доступны отдельно, в том числе friends-only. Код/приглашение работают как прежде.
func steam_friend_parties() -> Array:
	var list := []
	if not steam_ok:
		return list
	var app: int = steam.getAppID()
	for i in steam.getFriendCount(4):
		var fid: int = steam.getFriendByIndex(i, 4)
		var g: Dictionary = steam.getFriendGamePlayed(fid)
		var lobby := int(g.get("lobby", 0))
		if lobby != 0 and int(g.get("id", 0)) == app and lobby != lobby_id:
			list.append({"id": fid, "name": steam.getFriendPersonaName(fid), "lobby": lobby})
	list.sort_custom(func(a, b): return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return list


## Поиск Steam асинхронный. Повтор во время ожидания объединяется в один следующий refresh.
func request_steam_lobbies() -> bool:
	if not steam_ok or steam == null:
		steam_lobbies_loading = false
		steam_public_lobbies.clear()
		steam_lobbies_error = "Steam недоступен — запустите Steam и перезапустите игру."
		steam_lobbies_changed.emit()
		return false
	if steam_lobbies_loading and _steam_lobby_source == steam:
		_steam_lobby_refresh_again = true
		return true
	if _steam_lobby_source != steam:
		if is_instance_valid(_steam_lobby_source):
			var old_callback := _on_steam_lobby_list.bind(_steam_lobby_source)
			if _steam_lobby_source.is_connected("lobby_match_list", old_callback):
				_steam_lobby_source.disconnect("lobby_match_list", old_callback)
		_steam_lobby_source = steam
	var callback := _on_steam_lobby_list.bind(steam)
	if not steam.is_connected("lobby_match_list", callback):
		steam.connect("lobby_match_list", callback)
	_steam_lobby_request += 1
	_steam_lobby_refresh_again = false
	steam_lobbies_loading = true
	steam_lobbies_error = ""
	steam_lobbies_changed.emit()
	# Фильтры сбрасываются Steam после каждого запроса; 3 — весь мир, 0 — точное совпадение.
	steam.addRequestLobbyListDistanceFilter(3)
	steam.addRequestLobbyListStringFilter("game", LOBBY_TAG, 0)
	steam.addRequestLobbyListStringFilter("appid", str(steam.getAppID()), 0)
	steam.addRequestLobbyListResultCountFilter(5000)
	var request := _steam_lobby_request
	steam.requestLobbyList()
	get_tree().create_timer(25.0).timeout.connect(_on_steam_lobby_timeout.bind(request))
	return true


func _on_steam_lobby_timeout(request: int) -> void:
	if request != _steam_lobby_request or not steam_lobbies_loading:
		return
	steam_lobbies_loading = false
	_steam_lobby_refresh_again = false
	steam_lobbies_error = "Steam не ответил на поиск. Попробуйте обновить список."
	steam_lobbies_changed.emit()


func _on_steam_lobby_list(lobbies: Array, source: Object) -> void:
	if source != steam or not steam_lobbies_loading:
		return
	steam_lobbies_loading = false
	if _steam_lobby_refresh_again:
		request_steam_lobbies()
		return
	var found: Array[Dictionary] = []
	var seen := {}
	for value: Variant in lobbies:
		if not value is int or value <= 0 or value == lobby_id or seen.has(value):
			continue
		var id: int = value
		seen[id] = true
		if not _steam_public_lobby_matches(id):
			continue
		var count: int = steam.getNumLobbyMembers(id)
		var capacity: int = steam.getLobbyMemberLimit(id)
		var name: String = steam.getLobbyData(id, "host")
		name = name.replace("\n", " ").replace("\r", " ").strip_edges().left(64)
		found.append({"lobby": id, "name": name if not name.is_empty() else "Пати Steam",
			"members": maxi(0, count), "capacity": maxi(0, capacity),
			"full": capacity <= 0 or count >= capacity})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	steam_public_lobbies = found
	steam_lobbies_error = ""
	steam_lobbies_changed.emit()


func _steam_public_lobby_matches(id: int) -> bool:
	return steam.getLobbyData(id, "game") == LOBBY_TAG and steam.getLobbyData(id, "appid") == str(steam.getAppID())


## Вход именно из браузера: проверяем свежую вместимость, не меняя маршрут кода/приглашения.
func join_public_steam_lobby(id: int) -> bool:
	if not steam_ok or steam == null or steam_lobbies_loading:
		return false
	var listed := false
	for room: Dictionary in steam_public_lobbies:
		if room.lobby == id:
			listed = true
			break
	if not listed or not _steam_public_lobby_matches(id):
		status_changed.emit("Эта комната больше недоступна. Обновите список.")
		return false
	var capacity: int = steam.getLobbyMemberLimit(id)
	if capacity <= 0 or int(steam.getNumLobbyMembers(id)) >= capacity:
		status_changed.emit("В этой комнате нет свободных мест. Обновите список.")
		return false
	join_steam(id)
	return true


func invite_friend(friend_id: int) -> bool:
	if not steam_ok or lobby_id == 0:
		return false
	return bool(steam.inviteUserToLobby(lobby_id, friend_id))


## Входящее приглашение в лобби (игра запущена) — показываем плашку «Принять / Отклонить».
func _on_lobby_invite(inviter: int, lobby: int, _game: int) -> void:
	if lobby == lobby_id:
		return
	SteamInvite.show_incoming(steam.getFriendPersonaName(inviter), lobby)


func leave(reason: String = "Добровольный выход или смена подключения") -> void:
	if _leaving:
		return
	_leaving = true
	if not mode.is_empty():
		last_disconnect = {
			"причина": reason, "сеть_до_выхода": mode, "игра_до_выхода": party_game,
			"партия_до_выхода": game_id, "лобби_до_выхода": lobby_id,
			"роль_до_выхода": "хост" if is_host() else "клиент",
			"была_партия": in_game, "транспорт": _steam_transport_events.duplicate(true)
		}
		var peer := multiplayer.multiplayer_peer
		if peer != null:
			last_disconnect["тип_peer"] = peer.get_class()
			last_disconnect["статус_peer"] = peer.get_connection_status()
		Diag.mark("Соединение закрывается до очистки", last_disconnect)
	_client_start_pending = false
	_client_expected_match = ""
	gang = null
	tg_view_seat = 0
	fours = null
	phantom = null
	stillion = null
	_st_deck.clear()
	if steam_ok and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	_hosting_steam = false
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = ""
	party_game = ""
	in_game = false
	paused = false
	tutorial = false
	bot_delay = 0.9
	rules = null
	members.clear()
	join_order.clear()
	disconnected.clear()
	chat_log.clear()
	lobby_view = {}
	view = {}
	_steam_transport_events.clear()
	_leaving = false


## Только диагностика: Steam-событие само по себе не выгоняет участника из пати.
func _remember_steam_transport(event: Dictionary) -> void:
	if mode != "steam" or _leaving:
		return
	event["время_мс"] = Time.get_ticks_msec()
	_steam_transport_events.append(event)
	if _steam_transport_events.size() > 16:
		_steam_transport_events.pop_front()
	Diag.mark("Состояние Steam-соединения", event)


func _on_steam_connection_status(handle: int, connection: Dictionary, old_state: int) -> void:
	_remember_steam_transport({"событие": "network_connection_status_changed", "handle": handle,
		"предыдущее_состояние": old_state, "данные": ConnectionDiagnostics.safe_state(connection)})


func _on_steam_message_failure(reason: int, _remote_steam_id: int, state: int, debug_message: String) -> void:
	_remember_steam_transport({"событие": "network_messages_session_failed", "код": reason,
		"состояние": state, "описание": debug_message.left(512)})


func _reset_host() -> void:
	gang = null
	tg_view_seat = 0
	fours = null
	phantom = null
	stillion = null
	_st_deck.clear()
	members = {1: {"name": my_name, "steam_id": my_steam_id, "color": randi() % PLAYER_COLORS.size()}}
	disconnected.clear()
	join_order = [1]
	bots = 0
	in_game = false
	rules = null


# --- Steam callbacks ---------------------------------------------------------

func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		_hosting_steam = false
		status_changed.emit("Steam не создал лобби (код %d)." % result)
		return
	lobby_id = id
	_publish_steam_lobby(id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_host(0)
	if err != OK:
		status_changed.emit("Не удалось запустить хост Steam (ошибка %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	mode = "steam"
	_reset_host()
	party_game = _create_game
	_broadcast_lobby()


func _publish_steam_lobby(id: int) -> void:
	steam.setLobbyData(id, "game", LOBBY_TAG)
	steam.setLobbyData(id, "host", my_name)
	steam.setLobbyData(id, "appid", str(steam.getAppID()))
	steam.setLobbyJoinable(id, true)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if _hosting_steam:
		return  # хост тоже получает lobby_joined для своего лобби
	if response != 1:
		status_changed.emit("Не удалось войти в лобби (код %d). Лобби закрыто или полное." % response)
		return
	if steam.getLobbyData(id, "game") != LOBBY_TAG:
		steam.leaveLobby(id)
		status_changed.emit("Это лобби не от «Дюжины короля».")
		return
	var owner: int = steam.getLobbyOwner(id)
	if owner == steam.getSteamID():
		return
	lobby_id = id
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_client(owner, 0)
	if err != OK:
		status_changed.emit("Не удалось подключиться к хосту (ошибка %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	mode = "steam"
	status_changed.emit("Подключаемся к хосту…")


func _on_join_requested(id: int, _friend_id: int) -> void:
	join_steam(id)


# --- Multiplayer callbacks ---------------------------------------------------

func _on_connected_to_server() -> void:
	_dbg("connected")
	_rpc_hello.rpc_id(1, my_name, my_steam_id)


func _on_connection_failed() -> void:
	if _leaving or mode.is_empty():
		return
	leave("connection_failed: подключение не установлено")
	session_closed.emit("Не удалось подключиться к хосту.")


func _on_server_disconnected() -> void:
	if _leaving or mode.is_empty():
		return
	var was_playing := not view.is_empty()
	leave("server_disconnected: транспорт потерял связь с хостом")
	if was_playing:
		session_closed.emit("Связь с хостом потеряна. Если партия ещё идёт — нажмите «Вернуться в партию».")
	else:
		session_closed.emit("Хост покинул игру.")


## Повторно подключиться туда же, где были (после вылета).
func rejoin() -> void:
	match last_join.get("mode", ""):
		"steam":
			join_steam(int(last_join["lobby"]))
		"enet":
			join_enet(str(last_join["ip"]))


func _on_peer_connected(_id: int) -> void:
	pass  # ждём _rpc_hello с именем


func _on_peer_disconnected(id: int) -> void:
	if not mode.is_empty() and not _leaving:
		Diag.mark("Участник отключён транспортом", {"peer": id, "транспорт": _steam_transport_events.duplicate(true)})
	if not is_host() or not members.has(id):
		return
	var pname: String = members[id]["name"]
	members.erase(id)
	join_order.erase(id)
	ready_peers.erase(id)
	if in_game:
		var seat := seat_peers.find(id)
		if seat >= 0:
			seat_peers[seat] = 0
			disconnected[seat] = pname
			if phantom == null and fours == null and gang == null:
				_gp()[seat]["bot"] = true
				_gp()[seat]["name"] = pname + " (бот)"
			if gang != null:
				_system_chat("%s отключился. Пропущенный выбор за его место будет сделан случайно по таймеру. Он может вернуться в партию." % pname)
			else:
				_system_chat("%s отключился. Ждём его возвращения — место в этой игре нельзя заменить ботом." % pname if phantom != null or fours != null else "%s отключился — пока за него играет бот. Он может вернуться в партию." % pname)
		_push_state()
	else:
		_broadcast_lobby()


# =============================================================================
# Лобби
# =============================================================================

@rpc("any_peer", "reliable")
func _rpc_hello(player_name: String, steam_id: int = 0) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var nm := player_name.strip_edges().left(24)
	if in_game:
		var seat := -1
		for s in disconnected:
			if disconnected[s] == nm:
				seat = s
		if seat < 0:
			# новый друг в пати: подождёт конца партии и сядет за стол в следующей
			members[id] = {"name": nm, "steam_id": steam_id, "color": _free_color()}
			join_order.append(id)
			_system_chat("%s присоединился к пати и смотрит партию как зритель. Хост может посадить его за стол через «Паузу»." % nm)
			_broadcast_lobby()
			if mode != "offline":
				_rpc_started.rpc_id(id, party_game, game_id)  # зритель сразу видит стол
			_push_state()
			return
		# вернулся вылетевший игрок — отдаём ему его место
		members[id] = {"name": nm, "steam_id": steam_id, "color": _free_color()}
		join_order.append(id)
		disconnected.erase(seat)
		seat_peers[seat] = id
		_gp()[seat]["bot"] = false
		_gp()[seat]["name"] = nm
		# сначала — данные пати (какая игра выбрана): иначе вернувшийся остаётся в меню хаба,
		# хотя у всех он уже сидит за столом
		_broadcast_lobby()
		_rpc_started.rpc_id(id, party_game, game_id)
		_system_chat("%s вернулся в партию." % nm)
		_push_state()
		return
	if members.size() + bots >= PARTY_CAPACITY:
		if bots > 0:
			bots -= 1
		else:
			_rpc_kicked.rpc_id(id, "Лобби заполнено.")
			return
	members[id] = {"name": nm, "steam_id": steam_id, "color": _free_color()}
	join_order.append(id)
	_broadcast_lobby()


@rpc("authority", "reliable")
func _rpc_kicked(reason: String) -> void:
	leave("Исключение из пати: " + reason)
	session_closed.emit(reason)


func set_bots(n: int) -> void:
	if not is_host() or in_game:
		return
	var maximum: int = PARTY_CAPACITY if party_game == "the_gang" else MAX_PLAYERS
	bots = clampi(n, 0, maxi(0, maximum - members.size()))
	_broadcast_lobby()


func set_setting(key: String, value) -> void:
	if not is_host() or in_game:
		return
	settings[key] = value
	_broadcast_lobby()


func player_total() -> int:
	return members.size() + maxi(0, bots)


func lobby_code() -> String:
	if mode == "steam":
		return str(lobby_id)
	if mode == "enet":
		var ips := []
		for ip in IP.get_local_addresses():
			if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				ips.append(ip)
		return "%s, порт %d" % [", ".join(ips), PORT]
	return ""


func _broadcast_lobby() -> void:
	var list := []
	for id in join_order:
		list.append({"name": members[id]["name"], "kind": "host" if id == 1 else "player", "team": members[id].get("team", -1), "peer": id, "color": int(members[id].get("color", 0)), "suggest": members[id].get("suggest", "")})
	for i in bots:
		if party_game in LOCAL_GAMES:
			list.append({"name": "Игрок %d" % (i + 2), "kind": "local", "team": _local_team(i), "color": _local_color(i)})
		else:
			list.append({"name": BOT_NAMES[i % BOT_NAMES.size()], "kind": "bot", "color": _local_color(i)})
	var data := {
		"members": list,
		"settings": settings.duplicate(true),
		"mode": mode,
		"code": lobby_code(),
		"party_game": party_game,
		"in_game": in_game,
		"seated": seat_peers.duplicate() if in_game else [],
	}
	_apply_lobby(data)
	if mode != "offline":
		_rpc_lobby.rpc(data)


@rpc("authority", "reliable")
func _rpc_lobby(data: Dictionary) -> void:
	_apply_lobby(data)


func _apply_lobby(data: Dictionary) -> void:
	lobby_view = data
	var client := not is_host()
	var next_game := str(data.get("party_game", ""))
	var changed := client and next_game != party_game
	var previous_game := party_game
	# Удаление сцены deferred: до конца кадра её старые таблицы ещё подписаны на Net.
	if changed:
		_retire_game_receivers(previous_game, false, next_game)
	if client and (changed or (not bool(data.get("in_game", false)) and (in_game or not view.is_empty()))):
		_finish_session()
	if changed:
		party_game = next_game
		party_game_changed.emit(party_game)
		# Старой app позволен один выход в хаб; повторная смена в том же кадре её уже не вызывает.
		_retire_game_receivers(previous_game, true, next_game)
	lobby_changed.emit()


## Отключаем только UI уходящей игры; автозагрузки и подписчики транспорта остаются живы.
func _retire_game_receivers(previous_game: String, navigation: bool, next_game: String = "") -> void:
	var game := HubGames.by_id(previous_game)
	var paths: Array[String] = []
	if not game.is_empty():
		paths.append(str(game.get("scene", "")))
	# После disconnect Net.leave уже очистил party_game, но меню прежней игры ещё живо.
	var current := get_tree().current_scene
	var next_path := str(HubGames.by_id(next_game).get("scene", ""))
	if is_instance_valid(current):
		var current_path := current.scene_file_path
		if current_path.begins_with("res://games/") and current_path != next_path and not paths.has(current_path):
			paths.append(current_path)
	if paths.is_empty():
		return
	var signals := ["state_changed", "game_started", "game_ended", "lobby_changed", "pause_changed", "ghost_received", "chat_received", "status_changed", "session_closed"]
	if navigation:
		signals.append("party_game_changed")
	var retired := 0
	for signal_name: String in signals:
		for connection: Dictionary in get_signal_connection_list(signal_name):
			var callback: Callable = connection.callable
			var receiver := callback.get_object() as Node
			if not is_instance_valid(receiver):
				continue
			var node := receiver
			while is_instance_valid(node) and node != self:
				if paths.has(node.scene_file_path):
					if is_connected(signal_name, callback):
						disconnect(signal_name, callback)
						retired += 1
					break
				node = node.get_parent()
	if retired > 0:
		Diag.mark("Подписчики уходящей игры отключены", {"предыдущая_игра": previous_game, "подписок": retired})


## Итоговый набор карт по настройкам лобби (или пустой массив, если вручную выбрано не 7).
func build_deck() -> Array[String]:
	var deck: Array[String] = []
	match settings["deck_mode"]:
		"first":
			deck.append_array(K12Cards.FIRST_GAME)
		"random":
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			deck.append_array(K12Cards.random_deck(rng))
		"manual":
			for c in K12Cards.BASE:
				if settings["manual"].has(c):
					deck.append(c)
			if deck.size() != K12Cards.DECK_SIZE:
				return []
	if settings["promo"] != "":
		deck.append(settings["promo"])
	return deck


func start_game() -> String:
	Diag.mark("Запрошен запуск партии")
	if not is_host() or in_game:
		return "Начать может только хост."
	# Старое/неверное отрицательное значение добавочных мест не скрывает реальных участников.
	var added_players: int = maxi(0, bots)
	var total: int = members.size() + added_players
	var maximum := PARTY_CAPACITY if party_game == "the_gang" else MAX_PLAYERS
	var minimum := 3 if party_game == "the_gang" else 2
	if total < minimum or total > maximum:
		return "Нужно от %d до %d игроков." % [minimum, maximum]
	var deck: Array[String] = []
	if not party_game in ["perudo", "wavelength", "dangerous_words", "hues_and_cues", "ready_set_bet", "word_slam", "tip_top", "tip_top_18", "not_a_hat", "gloom", "brodilka", "phantom_ink", "four_souls", "stillion", "the_gang"]:
		deck = build_deck()
		if deck.is_empty():
			return "Вручную нужно отметить ровно %d карт." % K12Cards.DECK_SIZE
	var players := []
	seat_peers.clear()
	for id in join_order:
		players.append({"name": members[id]["name"], "bot": false, "steam_id": members[id].get("steam_id", 0), "team": members[id].get("team", -1), "color": int(members[id].get("color", 0))})
		seat_peers.append(id)
	for i in added_players:
		if party_game in LOCAL_GAMES:
			players.append({"name": "Игрок %d" % (i + 2), "bot": false, "local": true, "team": _local_team(i), "color": _local_color(i)})
		else:
			players.append({"name": BOT_NAMES[i % BOT_NAMES.size()], "bot": true, "color": _local_color(i)})
		seat_peers.append(0)
	game_id = "%d-%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	Diag.mark("Создание правил партии")
	# прошлая партия в этой пати могла быть другой игрой: сбрасываем ВСЕ правила, иначе _seat_view
	# возьмёт первое непустое (например, hues раньше wavelength) и стол получит чужое состояние
	rules = null
	perudo = null
	wavelength = null
	dwords = null
	hues = null
	rsb = null
	wslam = null
	tiptop = null
	nothat = null
	gloom = null
	brod = null
	phantom = null
	stillion = null
	fours = null
	gang = null
	tg_view_seat = 0
	if party_game == "the_gang":
		gang = load("res://games/the_gang/logic/tg_rules.gd").new()
		gang.new_game(players)
		auto_advance_time = 0.0
	elif party_game == "stillion":
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = null
		rsb = null
		wslam = null
		tiptop = null
		stillion = STRules.new()
		stillion.max_lives = clampi(int(settings.get("st_lives", STRules.MAX_LIVES)), 1, 9)
		stillion.meter_max = clampi(int(settings.get("st_meter", STRules.METER_MAX)), 4, 60)
		stillion.casual = bool(settings.get("st_casual", false))
		stillion.deck = _st_deck  # та же колода (по ссылке) — вопросы прошлых партий не повторяются
		stillion.new_game(players, bool(settings.get("st_bots", false)))
		stillion.external_check = STJev.available()
		_st_checking = -1
		auto_advance_time = 0.0
	elif party_game == "four_souls":
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = null
		rsb = null
		wslam = null
		tiptop = null
		fs_view_seat = 0
		fours = load("res://games/four_souls/logic/fs_rules.gd").new()
		fours.new_game(players, bool(settings.get("fs_dlc", false)))
		auto_advance_time = 0.0
	elif party_game == "phantom_ink":
		var pi_roles: Array = settings.get("pi_roles", [])
		if pi_roles.size() != players.size():
			pi_roles = PIData.default_roles(players.size())
		var pi_error := PIData.validate(pi_roles, players.size())
		if not pi_error.is_empty():
			return pi_error
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = null
		rsb = null
		wslam = null
		tiptop = null
		pi_view_seat = 0
		phantom = PIRules.new()
		phantom.new_game(players, pi_roles)
		auto_advance_time = 0.0
	elif party_game == "gloom":
		var gl_max := 4 if str(settings.get("gl_sets", "base")) == "base" else 5  # базовая коробка — до 4, пятый — с дополнениями
		if players.size() > gl_max:
			seat_peers.clear()
			return "В базовый Gloom играют от 2 до 4 человек — для пятого выберите карты с дополнениями или Gloomier." if gl_max == 4 else "В Gloom играют от 2 до 5 человек."
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = null
		rsb = null
		wslam = null
		tiptop = null
		gloom = GLRules.new()
		var gl_sets: Array = {"base": ["base"], "all": ["base", "ug", "ud"], "gm": ["gm"], "mix": ["base", "ug", "ud", "gm"]}.get(str(settings.get("gl_sets", "base")), ["base"])
		gloom.new_game(players, 0, gl_sets)
		auto_advance_time = 30.0
	elif party_game == "brodilka":
		if players.size() > BRRules.MAX_PLAYERS:
			seat_peers.clear()
			return "В «Большую бродилку» играют от 2 до %d человек." % BRRules.MAX_PLAYERS
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = null
		rsb = null
		wslam = null
		tiptop = null
		brod = BRRules.new()
		brod.new_game(players, 0, int(settings.get("br_start_coins", 0)))
	elif party_game == "not_a_hat":
		var each := int(settings.get("nh_cards", 1))
		if players.size() < 3 and each < 2 and mode != "offline":
			seat_peers.clear()
			return "Нужно от 3 игроков (для двоих — режим «по 2 подарка»)."
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = null
		rsb = null
		wslam = null
		tiptop = null
		nothat = NHRules.new()
		nothat.new_game(players, each)
		auto_advance_time = 30.0
	elif party_game in ["tip_top", "tip_top_18"]:
		if players.size() < 4 and mode != "offline":
			seat_peers.clear()
			return "Нужно от 4 до %d игроков." % MAX_PLAYERS
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = null
		rsb = null
		wslam = null
		tiptop = TTRules.new()
		tiptop.new_game(players, party_game == "tip_top_18", bool(settings.get("tt_expert", false)))
		auto_advance_time = 30.0
	elif party_game == "word_slam":
		var err := _start_ws(players)
		if err != "":
			seat_peers.clear()
			return err
	elif party_game == "ready_set_bet":
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = null
		rsb = RSBRules.new()
		rsb.new_game(players)
		_rsb_roll_wait = 0.0
		rsb_go = false
		rsb_paused = false
		auto_advance_time = 45.0
	elif party_game == "hues_and_cues":
		if players.size() < 2:
			seat_peers.clear()
			return "Нужно от 2 до %d игроков (вдвоём — кооператив)." % MAX_PLAYERS
		rules = null
		perudo = null
		wavelength = null
		dwords = null
		hues = HCRules.new()
		hues.new_game(players, int(settings.get("hc_laps", 0)), bool(settings.get("hc_free", false)), 0, players.size() == 2, str(settings.get("hc_mode", "classic")) == "distorted")
		auto_advance_time = 40.0
	elif party_game == "dangerous_words":
		var err := _start_dw(players)
		if err != "":
			seat_peers.clear()
			return err
	elif party_game == "wavelength":
		var err := _start_wavelength(players)
		if err != "":
			seat_peers.clear()
			return err
	elif party_game == "perudo":
		rules = null
		wavelength = null
		perudo = PerudoRules.new()
		perudo.new_game(players, int(settings.get("perudo_dice", 5)), bool(settings.get("perudo_maputo", true)))
		auto_advance_time = 25.0
	else:
		perudo = null
		wavelength = null
		rules = K12Rules.new()
		rules.new_game(players, deck, 0, bool(settings.get("tournament", true)))
		auto_advance_time = 45.0 + 2.0 * players.size()  # с запасом на поэтапное вскрытие карт
	in_game = true
	paused = false
	ready_peers.clear()
	_last_phase = ""
	if mode != "offline":
		_rpc_started.rpc(party_game, game_id)
	game_started.emit()
	_push_state()
	return ""


@rpc("authority", "reliable")
func _rpc_started(start_game_id: String = "", match_id: String = "") -> void:
	if not start_game_id.is_empty() and start_game_id != party_game:
		Diag.mark("Пропущена устаревшая команда запуска", {"игра_команды": start_game_id})
		return
	Diag.mark("Получена команда запуска от хоста", {"ожидаемая_партия": match_id})
	_dbg("started")
	_client_expected_match = match_id
	_client_start_pending = true
	in_game = true
	# Сначала нужен view новой партии. Иначе _ready нового стола читает старую схему из Net.view.
	if match_id.is_empty() or str(view.get("game_id", "")) != match_id:
		view = {}
	else:
		_deliver_client_start()


func _deliver_client_start() -> void:
	if not _client_start_pending or view.is_empty():
		return
	_client_start_pending = false
	game_started.emit()


# =============================================================================
# Партия
# =============================================================================

func send_action(kind: String, arg = null) -> void:
	_dbg("send %s %s" % [kind, arg])
	if is_host():
		_handle_action(1, kind, arg)
	else:
		_rpc_action.rpc_id(1, kind, arg)


@rpc("any_peer", "reliable")
func _rpc_action(kind: String, arg) -> void:
	if is_host():
		_handle_action(multiplayer.get_remote_sender_id(), kind, arg)


func _handle_action(peer: int, kind: String, arg) -> void:
	if not in_game or (rules == null and perudo == null and wavelength == null and dwords == null and hues == null and rsb == null and wslam == null and tiptop == null and nothat == null and gloom == null and brod == null and phantom == null and fours == null and stillion == null and gang == null):
		return
	var seat := seat_peers.find(peer)
	if seat < 0 or paused:
		return
	if gang != null:
		var tg_arg: Dictionary = arg if arg is Dictionary else {}
		if mode == "offline" and peer == 1:
			if kind == "view_seat":
				var requested := int(tg_arg.get("seat", -1))
				if requested >= 0 and requested < gang.players.size():
					tg_view_seat = requested
					_push_state()
				return
			seat = tg_view_seat
		if gang.action(seat, kind, tg_arg):
			_push_state()
		return
	if fours != null:
		if mode == "offline" and peer == 1:
			seat = fs_view_seat
		if fours.action(seat, kind, arg):
			_push_state()
		return
	if stillion != null:
		var sa: Dictionary = arg if arg is Dictionary else {}
		if mode == "offline" and sa.has("as"):
			seat = clampi(int(sa["as"]), 0, stillion.players.size() - 1)  # на одном компьютере — за того, в кого целится пушка
		if stillion.action(seat, kind, arg):
			_push_state()
		return
	if phantom != null:
		if mode == "offline" and peer == 1:
			seat = pi_view_seat
		if phantom.action(seat, kind, arg):
			_push_state()
		return
	if gloom != null:
		if _gl_action(peer, seat, kind, arg):
			_push_state()
		return
	if brod != null:
		if _br_action(seat, kind, arg):
			_push_state()
		return
	if nothat != null:
		if _nh_action(peer, seat, kind, arg):
			_push_state()
		return
	if tiptop != null:
		if _tt_action(peer, seat, kind, arg):
			_push_state()
		return
	if wslam != null:
		if _ws_action(peer, seat, kind, arg):
			_push_state()
		return
	if rsb != null:
		if _rsb_action(peer, seat, kind, arg):
			_push_state()
		return
	if hues != null:
		if _hc_action(peer, seat, kind, arg):
			_push_state()
		return
	if dwords != null:
		if _dw_action(peer, seat, kind, arg):
			_push_state()
		return
	if wavelength != null:
		if _wl_action(peer, seat, kind, arg):
			_push_state()
		return
	if perudo != null:
		if _perudo_action(peer, seat, kind, arg):
			_push_state()
		return
	var ok := false
	match kind:
		"roll":
			var vel: Dictionary = arg if arg is Dictionary else {}
			ok = rules.roll_die(seat, float(vel.get("vx", 0.0)), float(vel.get("vy", 0.0)))
		"oracle_roll":
			var vel: Dictionary = arg if arg is Dictionary else {}
			ok = rules.roll_oracle(seat, float(vel.get("vx", 0.0)), float(vel.get("vy", 0.0)))
		"select":
			ok = rules.selected[seat] == "" and rules.select_card(seat, str(arg))
		"unselect":
			ok = rules.unselect_card(seat)
		"face":
			ok = rules.choose_face(seat, int(arg))
		"under":
			ok = rules.pick_under(seat, str(arg))
		"next":
			if rules.phase in ["trick_result", "round_result"] and not ready_peers.has(peer):
				ready_peers[peer] = true
				_try_advance(false)
				ok = true
	if ok:
		_push_state()  # повторные и неверные действия игнорируем без рассылки


## Место выбыло из партии (игра сама говорит через is_out) — наблюдает, его «Дальше» не ждём.
func _seat_out(seat: int) -> bool:
	var g := _game_obj()
	return g != null and g.has_method("is_out") and bool(g.call("is_out", seat))


func _try_advance(force: bool) -> void:
	var waiting := []
	for s in seat_peers.size():
		var p := seat_peers[s]
		if p != 0 and not ready_peers.has(p) and not _seat_out(s):
			waiting.append(p)
	if force or waiting.is_empty():
		ready_peers.clear()
		if nothat != null:
			nothat.advance()
		elif tiptop != null:
			tiptop.advance()
		elif wslam != null:
			wslam.advance()
		elif rsb != null:
			rsb.advance()
		elif hues != null:
			hues.advance()
		elif dwords != null:
			dwords.advance()
		elif wavelength != null:
			wavelength.advance()
		elif perudo != null:
			perudo.advance()
		else:
			rules.advance()


func _process(delta: float) -> void:
	if not in_game or not is_host() or paused:
		return
	if _stamp_turn:
		# состояние ушло клиентам ещё со старым временем фазы — переотправляем с полным временем хода
		_stamp_turn = false
		_push_state()
	if gang != null:
		_tg_process(delta)
		return
	if fours != null:
		return
	if stillion != null:
		_st_process(delta)
		return
	if phantom != null:
		if phantom.tick(delta):
			_push_state()
		return
	if gloom != null:
		_gl_process(delta)
		return
	if brod != null:
		_br_process(delta)
		return
	if nothat != null:
		_nh_process(delta)
		return
	if tiptop != null:
		_tt_process(delta)
		return
	if wslam != null:
		_ws_process(delta)
		return
	if rsb != null:
		_rsb_process(delta)
		return
	if hues != null:
		_hc_process(delta)
		return
	if dwords != null:
		_dw_process(delta)
		return
	if wavelength != null:
		_wl_process(delta)
		return
	if perudo != null:
		_perudo_process(delta)
		return
	if rules == null:
		return
	if rules.phase != _last_phase:
		_last_phase = rules.phase
		_phase_time = 0.0
		_stamp_turn = true
		_bot_wait = 0.0
	_phase_time += delta
	match rules.phase:
		"roll", "select", "sorcerer", "oracle", "pick_under":
			if rules.phase in ["select", "sorcerer"] and _phase_time >= turn_limit():
				if K12Bot.act_all(rules, true):  # время на ход вышло — ходим за задумавшихся
					_push_state()
				return
			if rules.phase == "roll" and _phase_time >= minf(AUTO_ROLL, turn_limit()):
				for s in seat_peers.size():
					if not rules.rolled[s]:
						rules.roll_die(s, 0.0, -900.0)
				_push_state()
				return
			if rules.phase == "oracle" and _phase_time >= minf(AUTO_ROLL, turn_limit()) + REVEAL_SLACK:
				rules.roll_oracle(rules.pending["seat"], 0.0, -900.0)
				_push_state()
				return
			if rules.phase == "pick_under" and _phase_time >= minf(AUTO_PICK, turn_limit()):
				for s in rules.pending.get("seats", []).duplicate():
					if rules.phase == "pick_under":
						rules.pick_under(s, rules.hands[s][0])
				_push_state()
				return
			_bot_wait += delta
			if _bot_wait >= bot_delay:
				_bot_wait = 0.0
				if K12Bot.act_all(rules):
					_push_state()
		"trick_result", "round_result":
			if _phase_time >= auto_advance_time:
				_try_advance(true)
				_push_state()


func _push_state() -> void:
	if rules == null and perudo == null and wavelength == null and dwords == null and hues == null and rsb == null and wslam == null and tiptop == null and nothat == null and gloom == null and brod == null and phantom == null and fours == null and stillion == null and gang == null:
		return
	_match_metrics.observe(game_id,party_game,_game_obj(),seat_peers)
	var phase: String
	if gang != null:
		phase = gang.phase
	elif fours != null:
		phase = fours.phase
	elif stillion != null:
		phase = stillion.phase
	elif phantom != null:
		phase = phantom.phase
	elif gloom != null:
		phase = gloom.phase
	elif brod != null:
		phase = brod.phase
	elif nothat != null:
		phase = nothat.phase
	elif tiptop != null:
		phase = tiptop.phase
	elif wslam != null:
		phase = wslam.phase
	elif rsb != null:
		phase = rsb.phase
	elif hues != null:
		phase = hues.phase
	elif dwords != null:
		phase = dwords.phase
	elif wavelength != null:
		phase = wavelength.phase
	else:
		phase = perudo.phase if perudo != null else rules.phase
	var names := []
	if phase in ["trick_result", "round_result", "reveal", "turn_result", "results"]:
		for s in seat_peers.size():
			var p := seat_peers[s]
			if p != 0 and not ready_peers.has(p) and not _seat_out(s):
				names.append(_gp()[s]["name"])
	var same_phase := phase == _last_phase or ((perudo != null or wavelength != null or dwords != null or hues != null or rsb != null or wslam != null or tiptop != null or nothat != null or gloom != null or brod != null) and _last_phase.begins_with(phase + "/"))
	var left := maxf(0.0, auto_advance_time - _phase_time) if same_phase else auto_advance_time
	for s in seat_peers.size():
		var p := seat_peers[s]
		if p == 0:
			continue
		_send_view(p, _seat_view(s, names, left, mode == "offline"))
	# зрители видят стол глазами рядового игрока (не ведущего), без права действовать
	var specs := spectators()
	if not specs.is_empty() and not seat_peers.is_empty():
		var sv := _seat_view(-1 if phantom != null or fours != null or gang != null else _spectator_seat(), names, left, false)
		sv["spectator"] = true
		# что зритель может занять сам: место бота (с его прогрессом) или команду (прогресс общий)
		var bot_seats := []
		for st in free_seats():
			if bool(_gp()[int(st["seat"])].get("bot", false)):
				bot_seats.append(st)
		sv["free_seats"] = bot_seats
		var g := _game_obj()
		sv["join_teams"] = g.call("teams_for_join") if g != null and g.has_method("teams_for_join") else []
		for p in specs:
			_send_view(p, sv)


func _send_view(p: int, v: Dictionary) -> void:
	if p == 1:
		_apply_state(v)
	else:
		_rpc_state.rpc_id(p, v)


## Состояние стола для места s (show_all — на одном компьютере видно всё).
func _seat_view(s: int, names: Array, left: float, show_all: bool) -> Dictionary:
	var v: Dictionary
	if gang != null:
		v = gang.get_view(tg_view_seat if show_all else s)
		v["hotseat"] = show_all
		v["clock"] = gang.phase == "rank"
	elif fours != null:
		v = fours.get_view(fs_view_seat if show_all else s)
	elif stillion != null:
		v = stillion.get_view(s)
	elif phantom != null:
		v = phantom.get_view(pi_view_seat if show_all else s)
	elif gloom != null:
		v = gloom.get_view(s, show_all)
	elif brod != null:
		v = brod.get_view(s)
	elif nothat != null:
		v = nothat.get_view(s, false)  # игра на память — даже на одном компьютере ничего не подсматриваем
	elif tiptop != null:
		v = tiptop.get_view(s, show_all)
	elif wslam != null:
		v = wslam.get_view(s, show_all)
		v["time_total"] = _ws_time_total()
		v["time_left"] = _ws_time_left()
	elif rsb != null:
		v = rsb.get_view(s, show_all)
		v["roll_interval"] = _rsb_interval()
		v["rsb_go"] = rsb_go
		v["paused"] = rsb_paused
	elif hues != null:
		v = hues.get_view(s, show_all)
	elif dwords != null:
		v = dwords.get_view(s, show_all)
		v["time_total"] = _dw_time_total()
		v["time_left"] = _dw_time_left()
	elif wavelength != null:
		v = wavelength.get_view(s, show_all)
	elif perudo != null:
		v = perudo.get_view(s)
	else:
		v = rules.get_view(s)
	v["game"] = party_game
	v["waiting"] = names
	v["reveal_speed"] = settings.get("reveal_speed", "normal")
	v["game_id"] = game_id
	v["personal_stats"] = _match_metrics.snapshot(s)
	v["game_paused"] = paused
	v["tutorial"] = tutorial
	v["auto_in"] = int(left)
	var tl := turn_limit()
	v["turn_total"] = 0 if tl == INF else int(tl)
	v["turn_left"] = 0 if tl == INF else maxi(0, int(ceil(tl - _phase_time)))
	return v


# =============================================================================
# Зрители
# =============================================================================

## Участники пати, которые во время партии не сидят за столом (смотрят).
func spectators() -> Array:
	var out := []
	if not in_game or not is_host() or mode == "offline":
		return out
	for id in members:
		if not seat_peers.has(int(id)):
			out.append(int(id))
	return out


## Глазами какого места смотрит зритель: игра может назвать рядовое место (не ведущего с тайной).
func _spectator_seat() -> int:
	var g := _game_obj()
	if g != null and g.has_method("spectator_seat"):
		return clampi(int(g.call("spectator_seat")), 0, seat_peers.size() - 1)
	return 0


## Можно ли сейчас уйти в зрители (за место сядет бот). Игра может запретить (can_spectate).
func can_spectate() -> bool:
	if not in_game or mode == "offline" or not seat_peers.has(multiplayer.get_unique_id()):
		return false
	var g := _game_obj()
	return g == null or not g.has_method("can_spectate") or bool(g.call("can_spectate"))


## Игрок уходит из-за стола в зрители: за его место играет бот, вернуть может хост через «Паузу».
func become_spectator() -> void:
	if is_host():
		_make_spectator(1)
	else:
		_rpc_spectate.rpc_id(1)


@rpc("any_peer", "reliable")
func _rpc_spectate() -> void:
	if is_host():
		_make_spectator(multiplayer.get_remote_sender_id())


## Зритель сам садится: на место бота (seat ≥ 0) или в команду (team ≥ 0, только командные игры).
func spectator_join(seat: int, team: int) -> void:
	if is_host():
		_spectator_join(1, seat, team)
	else:
		_rpc_spectator_join.rpc_id(1, seat, team)


@rpc("any_peer", "reliable")
func _rpc_spectator_join(seat: int, team: int) -> void:
	if is_host():
		_spectator_join(multiplayer.get_remote_sender_id(), seat, team)


func _spectator_join(peer: int, seat: int, team: int) -> void:
	if not spectators().has(peer):
		return
	if seat >= 0:
		if seat < seat_peers.size() and seat_peers[seat] == 0 and bool(_gp()[seat].get("bot", false)):
			seat_member(peer, seat)
	elif team >= 0:
		var g := _game_obj()
		if g != null and g.has_method("teams_for_join") and (g.call("teams_for_join") as Array).has(team):
			seat_member(peer, -1, team)


func _make_spectator(peer: int) -> void:
	var seat := seat_peers.find(peer)
	if not in_game or seat < 0 or not members.has(peer):
		return
	var g := _game_obj()
	if g != null and g.has_method("can_spectate") and not bool(g.call("can_spectate")):
		return
	var nm: String = members[peer]["name"]
	seat_peers[seat] = 0
	ready_peers.erase(peer)
	_gp()[seat]["bot"] = true
	_gp()[seat]["name"] = nm + " (бот)"
	_system_chat("%s теперь зритель — за его место играет бот." % nm)
	_stamp_turn = true
	_push_state()


@rpc("authority", "reliable")
func _rpc_state(v: Dictionary) -> void:
	_apply_state(v)


func _apply_state(v: Dictionary) -> void:
	if not is_host():
		if v.has("game") and str(v.game) != party_game:
			Diag.mark("Пропущено состояние другой игры", {"игра_пакета": str(v.game)})
			return
		if not _client_expected_match.is_empty() and str(v.get("game_id", "")) != _client_expected_match:
			Diag.mark("Пропущено состояние прошлой партии", {"партия_пакета": str(v.get("game_id", ""))})
			return
		in_game = not v.is_empty()
		game_id = str(v.get("game_id", ""))
	if bool(v.get("game_paused", false)) != bool(view.get("game_paused", false)):
		pause_changed.emit.call_deferred()
	_dbg("state phase=%s trick=%s" % [v.get("phase"), v.get("trick_no")])
	view = v
	if not is_host():
		_deliver_client_start()
	if not bool(v.get("spectator",false)): player_stats.consume(v.get("personal_stats",{}))
	state_changed.emit(v)


## Аватарка Steam игрока (или null, пока Steam её не загрузил / без Steam).
func avatar(steam_id: int) -> Texture2D:
	if not steam_ok or steam_id == 0:
		return null
	if _avatars.has(steam_id):
		return _avatars[steam_id]
	var handle: int = steam.getMediumFriendAvatar(steam_id)
	if handle <= 0:
		steam.requestUserInformation(steam_id, false)
		return null
	var dims = steam.getImageSize(handle)
	var rgba = steam.getImageRGBA(handle)
	var w := 64
	var h := 64
	if typeof(dims) == TYPE_DICTIONARY:
		w = int(dims.get("width", 64))
		h = int(dims.get("height", 64))
	var buf: PackedByteArray = rgba.get("buffer", PackedByteArray()) if typeof(rgba) == TYPE_DICTIONARY else PackedByteArray()
	if buf.size() != w * h * 4:
		return null
	var tex := ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, buf))
	_avatars[steam_id] = tex
	return tex


# =============================================================================
# «Перудо» на хосте
# =============================================================================

const PERUDO_SHAKE := 15.0  # не потряс стакан — трясём за игрока
const PERUDO_TURN := 60.0  # долго думает — ход делает бот


## Игроки текущей партии (любой игры).
func _gp() -> Array:
	if gang != null:
		return gang.players
	if stillion != null:
		return stillion.players
	if fours != null:
		return fours.players
	if phantom != null:
		return phantom.players
	if gloom != null:
		return gloom.players
	if brod != null:
		return brod.players
	if nothat != null:
		return nothat.players
	if tiptop != null:
		return tiptop.players
	if wslam != null:
		return wslam.players
	if rsb != null:
		return rsb.players
	if hues != null:
		return hues.players
	if dwords != null:
		return dwords.players
	if wavelength != null:
		return wavelength.players
	return perudo.players if perudo != null else rules.players


func _perudo_action(peer: int, seat: int, kind: String, arg) -> bool:
	var a: Dictionary = arg if arg is Dictionary else {}
	match kind:
		"shake":
			return perudo.shake(seat)
		"shaking":
			return perudo.set_shaking(seat, bool(a.get("on", false)))
		"seat_shuffle":
			return peer == 1 and perudo.shuffle_order()  # рассадка — только хост
		"seat_begin":
			return peer == 1 and perudo.begin()
		"bid":
			return perudo.place_bid(seat, int(a.get("q", 0)), int(a.get("face", 0)), bool(a.get("maputo", false)))
		"challenge":
			return perudo.challenge(seat)
		"calza":
			return perudo.calza(seat)
		"next":
			if perudo.phase == "reveal" and not ready_peers.has(peer):
				ready_peers[peer] = true
				_try_advance(false)
				return true
	return false


func _perudo_process(delta: float) -> void:
	var key := "%s/%d/%d" % [perudo.phase, perudo.round_no, perudo.bids.size()]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_stamp_turn = true  # новая фаза — часы хода у всех с нуля
		_bot_wait = 0.0
	_phase_time += delta
	_bot_wait += delta
	match perudo.phase:
		"roll":
			var changed := false
			for s in seat_peers.size():
				if perudo.shaken[s]:
					continue
				var bot: bool = perudo.players[s].get("bot", false)
				var at := bot_delay * (0.5 + s * 0.3) + 0.9  # бот сначала трясёт стакан у всех на виду
				if bot and _bot_wait >= at - 0.9 and not perudo.shaking[s]:
					changed = perudo.set_shaking(s, true) or changed
				if (bot and _bot_wait >= at) or _phase_time >= PERUDO_SHAKE:
					changed = perudo.shake(s) or changed
			if changed:
				_push_state()
		"bid":
			var t := perudo.turn
			var bot: bool = perudo.players[t].get("bot", false)
			if (bot and _bot_wait >= bot_delay * 1.8) or _phase_time >= turn_limit():
				if PerudoBot.act(perudo, t):
					_push_state()
		"reveal":
			if _phase_time >= auto_advance_time:
				_try_advance(true)
				_push_state()


# =============================================================================
# «Длина волны» на хосте
# =============================================================================

## Время на ход из настроек комнаты (0 — без ограничения).
func turn_limit() -> float:
	if stillion != null:
		return INF  # время задаёт фитиль пушки
	if fours != null:
		return INF
	if phantom != null:
		return INF  # буквы и обсуждение не ограничены таймером
	var t := int(settings.get("turn_time", 60))
	if t <= 0 or rsb != null:  # Ready Set Bet: ходов нет — всё идёт вместе с гонкой, своего таймера не нужно
		return INF
	# Hues and Cues: ведущему на загадывание (выбор цвета и подсказки) — вдвое больше времени
	if hues != null and hues.phase in ["pick", "cue1", "cue2"]:
		return float(t) * 2.0
	# «Длина волны»: на выбор карточки — отдельно, половина времени на подсказку
	if wavelength != null and wavelength.phase == "card":
		return float(t) * 0.5
	return float(t)


## Цвет игрока по номеру из палитры.
static func color_of(index: int) -> Color:
	return Color(PLAYER_COLORS[posmod(index, PLAYER_COLORS.size())])


func _used_colors() -> Array:
	var used := []
	for id in members:
		used.append(int(members[id].get("color", -1)))
	for c in settings.get("local_colors", []):
		used.append(int(c))
	return used


## Случайный свободный цвет (если заняты все — любой, кроме avoid).
func _free_color(avoid: int = -1) -> int:
	var used := _used_colors()
	var free := []
	for i in PLAYER_COLORS.size():
		if not used.has(i) and i != avoid:
			free.append(i)
	if free.is_empty():
		var any := range(PLAYER_COLORS.size()).filter(func(i): return i != avoid)
		return any.pick_random()
	return free.pick_random()


## Цвет «местного» игрока или бота (хранится в настройках хоста).
func _local_color(i: int) -> int:
	var arr: Array = settings.get("local_colors", [])
	if i < arr.size():
		return int(arr[i])
	while arr.size() <= i:
		settings["local_colors"] = arr
		arr.append(_free_color())
	settings["local_colors"] = arr
	return int(arr[i])


## Сменить свой цвет на случайный (local_i ≥ 0 — хост меняет цвет «местного» игрока).
func reroll_color(local_i: int = -1) -> void:
	if is_host():
		_reroll_color(1, local_i)
	else:
		_rpc_reroll_color.rpc_id(1)


@rpc("any_peer", "reliable")
func _rpc_reroll_color() -> void:
	if is_host():
		_reroll_color(multiplayer.get_remote_sender_id(), -1)


func _reroll_color(peer: int, local_i: int) -> void:
	if in_game and party_game == "perudo":
		return  # в «Перудо» по цвету ника окрашены стакан и кости — во время партии не меняем
	var color := -1
	var seat := -1
	if local_i >= 0:
		var arr: Array = settings.get("local_colors", []).duplicate()
		while arr.size() <= local_i:
			arr.append(_free_color())
		arr[local_i] = _free_color(int(arr[local_i]))
		settings["local_colors"] = arr
		color = arr[local_i]
		seat = join_order.size() + local_i
	elif members.has(peer):
		members[peer]["color"] = _free_color(int(members[peer].get("color", -1)))
		color = members[peer]["color"]
		seat = seat_peers.find(peer)
	_broadcast_lobby()
	# идёт партия — цвет меняется и за столом
	if in_game and seat >= 0 and seat < _gp().size():
		_gp()[seat]["color"] = color
		_push_state()


## Команда «местного» игрока (игра на одном компьютере).
func _local_team(i: int) -> int:
	var arr: Array = settings.get("wl_local_teams", [])
	return int(arr[i]) if i < arr.size() else i % 2


## Игрок выбирает команду в лобби (0 — левое полушарие, 1 — правое).
func set_team(team: int) -> void:
	if is_host():
		_set_member_team(1, team)
	else:
		_rpc_set_team.rpc_id(1, team)


@rpc("any_peer", "reliable")
func _rpc_set_team(team: int) -> void:
	if is_host():
		_set_member_team(multiplayer.get_remote_sender_id(), team)


func _set_member_team(peer: int, team: int) -> void:
	if members.has(peer) and not in_game:
		members[peer]["team"] = clampi(team, 0, 1)
		_broadcast_lobby()


## Хост: команда «местного» игрока.
func set_local_team(i: int, team: int) -> void:
	if not is_host():
		return
	var arr: Array = settings.get("wl_local_teams", []).duplicate()
	while arr.size() <= i:
		arr.append(arr.size() % 2)
	arr[i] = clampi(team, 0, 1)
	set_setting("wl_local_teams", arr)


## Хост: перемешать команды поровну.
func shuffle_teams() -> void:
	if not is_host():
		return
	var all := []
	for id in join_order:
		all.append(["m", id])
	for i in bots:
		all.append(["l", i])
	all.shuffle()
	var local := []
	for i in bots:
		local.append(0)
	for k in all.size():
		var team := k % 2
		if all[k][0] == "m":
			members[all[k][1]]["team"] = team
		else:
			local[all[k][1]] = team
	settings["wl_local_teams"] = local
	_broadcast_lobby()


func _start_wavelength(players: Array) -> String:
	var coop: bool = settings.get("wl_mode", "teams") == "coop"
	if not coop:
		# кто не выбрал команду — в меньшую
		var sizes := [0, 0]
		for p in players:
			if p["team"] in [0, 1]:
				sizes[p["team"]] += 1
		for p in players:
			if not p["team"] in [0, 1]:
				p["team"] = 0 if sizes[0] <= sizes[1] else 1
				sizes[p["team"]] += 1
		if sizes[0] < 2 or sizes[1] < 2:
			return "В каждой команде нужно минимум 2 игрока (или выберите кооператив)."
	rules = null
	perudo = null
	wavelength = WLRules.new()
	wavelength.new_game(players, coop)
	auto_advance_time = 40.0
	return ""


func _wl_action(peer: int, seat: int, kind: String, arg) -> bool:
	var w := wavelength
	if mode == "offline":
		# на одном компьютере — действие от имени нужной роли
		match kind:
			"wl_side", "wl_clue":
				seat = w.psychic
			"wl_dial", "wl_lock":
				var g: Array = w.team_members(w.active_team).filter(func(x): return x != w.psychic)
				seat = g[0] if not g.is_empty() else seat
			"wl_lr":
				var o: Array = w.team_members(1 - w.active_team)
				seat = o[0] if not o.is_empty() else seat
	match kind:
		"wl_side":
			return w.choose_side(seat, int(arg))
		"wl_clue":
			return w.give_clue(seat, str(arg))
		"wl_dial":
			return w.move_dial(seat, float(arg))
		"wl_lock":
			return w.lock_dial(seat)
		"wl_lr":
			return w.choose_lr(seat, str(arg))
		"next":
			if w.phase == "reveal" and not ready_peers.has(peer):
				ready_peers[peer] = true
				_try_advance(false)
				return true
	return false


func _wl_process(delta: float) -> void:
	var key := "%s/%d" % [wavelength.phase, wavelength.turn_no]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_stamp_turn = true  # новая фаза — часы хода у всех с нуля
	_phase_time += delta
	var w := wavelength
	if w.phase in ["card", "clue", "guess", "side"] and _phase_time >= turn_limit():
		# время на ход вышло — действие за игрока
		var ok := false
		match w.phase:
			"card":
				ok = w.choose_side(w.psychic, 0)
			"clue":
				ok = w.give_clue(w.psychic, "(время вышло)")
			"guess":
				var g: Array = w.team_members(w.active_team).filter(func(x): return x != w.psychic)
				ok = not g.is_empty() and w.lock_dial(g[0])
			"side":
				var o: Array = w.team_members(1 - w.active_team)
				ok = not o.is_empty() and w.choose_lr(o[0], ["left", "right"].pick_random())
		if ok:
			_push_state()
		return
	if wavelength.phase == "reveal" and _phase_time >= auto_advance_time:
		_try_advance(true)
		_push_state()


# =============================================================================
# «Опасные слова» на хосте
# =============================================================================

const DW_READ_TIME := 3.0  # объясняющий читает слово, потом переворачиваются часы


func _start_dw(players: Array) -> String:
	var sizes := [0, 0]
	for p in players:
		if p["team"] in [0, 1]:
			sizes[p["team"]] += 1
	for p in players:
		if not p["team"] in [0, 1]:
			p["team"] = 0 if sizes[0] <= sizes[1] else 1
			sizes[p["team"]] += 1
	if sizes[0] < 2 or sizes[1] < 2:
		return "В каждой команде нужно минимум 2 игрока."
	var rooms: Array = [2, 4, 6, 8, 10] if settings.get("dw_rooms", "3-7") == "even" else [3, 4, 5, 6, 7]
	var monster: String = settings.get("dw_monster", "random")
	rules = null
	perudo = null
	wavelength = null
	dwords = DWRules.new()
	dwords.new_game(players, rooms, "" if monster == "random" else monster, bool(settings.get("dw_hard", false)), 0, bool(settings.get("dw_curses", true)), bool(settings.get("dw_curses_stay", false)))
	auto_advance_time = 30.0
	return ""


func _dw_time_total() -> float:
	return float(settings.get("dw_time", 60))


func _dw_time_left() -> float:
	if dwords == null:
		return 0.0
	if dwords.phase == "turn":
		return maxf(0.0, _dw_time_total() - _phase_time)
	if dwords.phase == "traps" and (dwords.has_curse(0, "scribbles") or dwords.has_curse(1, "scribbles")):
		return maxf(0.0, _dw_time_total() - _phase_time)
	return _dw_time_total()


func _dw_action(peer: int, seat: int, kind: String, arg) -> bool:
	var d := dwords
	var team: int = d.players[seat]["team"]
	if mode == "offline" and arg is Dictionary and arg.has("team"):
		team = int(arg["team"])  # тест на одном компьютере: действие от имени команды
	var a: Dictionary = arg if arg is Dictionary else {}
	match kind:
		"dw_traps":
			return d.set_traps(team, a.get("lines", []))
		"dw_cand", "dw_cand_del", "dw_vote", "dw_move":
			if int(d.players[seat]["team"]) != team:
				var m: Array = d.team_members(team)
				seat = m[0] if not m.is_empty() else seat  # тест на одном компьютере
			match kind:
				"dw_cand":
					return d.add_cand(team, seat, str(a.get("word", "")))
				"dw_cand_del":
					return d.del_cand(team, seat, int(a.get("i", -1)))
				"dw_move":
					return d.move_cand(team, int(a.get("i", -1)), int(a.get("to", 0))) >= 0
				_:
					return d.vote(team, seat, int(a.get("i", -1)))
		"dw_horror":
			return d.set_horror(team, int(a.get("i", -1)))
		"dw_ready":
			if mode == "offline":
				return d.set_ready(team, bool(a.get("on", true)))  # тест: одно нажатие за всю команду
			return d.vote_ready(team, seat, bool(a.get("on", true)), _dw_human_seats())
		"dw_start":
			# объясняющий открыл слово — время пошло
			if d.phase == "turn_ready" and (mode == "offline" or seat == d.explainer(d.turn_team)):
				return d.start_timer()
			return false
		"dw_defuse":
			return d.pick_defuse(team, int(a.get("n", 1)))
		"dw_guessed":
			if mode == "offline":
				seat = d.explainer(d.turn_team)
			return d.guessed(seat)
		"dw_trap":
			return d.trap_hit(team, int(a.get("line", -1)))
		"dw_violation":
			return d.violation(team)
		"dw_wrong":
			return d.wrong_guess(team)
		"dw_text":
			if mode == "offline":
				var g: Array = d.team_members(d.turn_team).filter(func(x): return x != d.explainer(d.turn_team))
				seat = g[0] if not g.is_empty() else seat
			return d.text_guess(seat, str(a.get("text", "")))
		"next":
			if d.phase in ["turn_result", "round_result"] and not ready_peers.has(peer):
				ready_peers[peer] = true
				_try_advance(false)
				return true
	return false


## Места живых игроков «Опасных слов» (вылетевшие помечены ботами и не голосуют).
func _dw_human_seats() -> Array:
	var out := []
	for s in dwords.players.size():
		if not dwords.players[s].get("bot", false):
			out.append(s)
	return out


func _dw_process(delta: float) -> void:
	var d := dwords
	var key := "%s/%d/%d" % [d.phase, d.round_no, d.turn_i]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_stamp_turn = true  # новая фаза — часы хода у всех с нуля
	var before := int(_phase_time)
	_phase_time += delta
	match d.phase:
		"defuse":
			# «Обезвреженная ловушка»: соперник не выбрал номер вовремя — случайная строка
			if _phase_time >= turn_limit():
				for t in 2:
					if d.phase == "defuse" and d.has_curse(t, "defuse") and d.crossed[t] < 0 and d.traps[t].size() > 0:
						d.pick_defuse(1 - t, randi_range(1, d.traps[t].size()))
				_push_state()
		"turn_ready":
			# объясняющий сам жмёт «Начать объяснение»; вылетел / задумался надолго — начинаем за него
			var exp_seat := d.explainer(d.turn_team)
			var gone: bool = d.players[exp_seat].get("bot", false)
			if (gone and _phase_time >= DW_READ_TIME) or _phase_time >= turn_limit():
				d.start_timer()
				_push_state()
		"turn":
			if _phase_time >= _dw_time_total():
				d.time_up()
				_push_state()
		"traps":
			# команда так и не нажала «Готово» (ушла / задумалась) — через 3 времени хода ловушки
			# фиксируются как есть, чтобы партия не встала
			if _phase_time >= turn_limit() * 3.0:
				for t in 2:
					if not d.ready[t] and d.phase == "traps":
						d.set_ready(t, true, true)
				_push_state()
				return
			# «Безумные каракули»: на ловушки против проклятой команды — время песочных часов
			for victim in 2:
				var writer := 1 - victim
				if d.has_curse(victim, "scribbles") and not d.ready[writer] and _phase_time >= _dw_time_total():
					d.set_ready(writer, true, true)
					_push_state()
		"turn_result", "round_result":
			if _phase_time >= auto_advance_time:
				_try_advance(true)
				_push_state()
	if int(_phase_time) != before and d.phase in ["turn", "traps"]:
		_push_state()  # раз в секунду — обновить песочные часы


# =============================================================================
# «Оттенки и подсказки» на хосте
# =============================================================================

func _hc_action(peer: int, seat: int, kind: String, arg) -> bool:
	var h := hues
	if mode == "offline":
		# на одном компьютере — действие от имени нужной роли
		if kind in ["hc_pick", "hc_cue", "hc_pass"]:
			seat = h.giver
		elif kind == "hc_place" and h.current_guesser() >= 0:
			seat = h.current_guesser()
	match kind:
		"hc_pick":
			return h.pick_color(seat, int(arg))
		"hc_cue":
			return h.give_cue(seat, str(arg))
		"hc_pass":
			return h.pass_cue(seat)
		"hc_place":
			return h.place(seat, int(arg))
		"hc_skip":
			return peer == 1 and h.skip()
		"next":
			if h.phase == "reveal" and not ready_peers.has(peer):
				ready_peers[peer] = true
				_try_advance(false)
				return true
	return false


func _hc_process(delta: float) -> void:
	var key := "%s/%d/%d" % [hues.phase, hues.round_no, hues.order_i]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_stamp_turn = true  # новая фаза — часы хода у всех с нуля
	_phase_time += delta
	if hues.phase == "prepare":
		if get_tree().get_first_node_in_group("scene_transition") != null:
			_phase_time = 0.0
			return
		if _phase_time >= HCRules.PREPARE_SECONDS:
			hues.finish_prepare()
			_push_state()
		return
	# вылетевший игрок (за него «бот»): его догадку пропускаем, а за ведущего — пас или пропуск раунда
	if _phase_time >= 1.5:
		var h := hues
		var g := h.current_guesser()
		if g >= 0 and h.players[g].get("bot", false):
			h.skip()
			_push_state()
		elif h.players[h.giver].get("bot", false) and h.phase in ["pick", "cue1", "cue2"]:
			if h.phase == "cue2":
				h.pass_cue(h.giver)
			else:
				h.skip_round()
			_push_state()
	if hues.phase in ["pick", "cue1", "cue2", "guess1", "guess2"] and _phase_time >= turn_limit():
		# время на ход вышло
		var h := hues
		match h.phase:
			"pick":
				h.pick_color(h.giver, h.card[0])
			"cue1":
				h.skip_round()
			"cue2":
				h.pass_cue(h.giver)
			_:
				h.skip()
		_push_state()
		return
	if hues.phase == "reveal" and _phase_time >= auto_advance_time:
		_try_advance(true)
		_push_state()


# =============================================================================
# «На старт, ставки!» на хосте
# =============================================================================

const RSB_COUNTDOWN := 4.0  # «На старт…» перед забегом
const RSB_VIP_TIME := 60.0  # не выбрал VIP-карту — берём первую


func _rsb_interval() -> float:
	return {"slow": 1.6, "normal": 1.15, "fast": 0.8}.get(settings.get("rsb_speed", "normal"), 1.15)


func _rsb_action(peer: int, seat: int, kind: String, arg) -> bool:
	var r := rsb
	var a: Dictionary = arg if arg is Dictionary else {}
	if mode == "offline" and a.has("as"):
		seat = clampi(int(a["as"]), 0, r.players.size() - 1)  # на одном компьютере — за любого игрока
	match kind:
		"rsb_begin":  # ведущий (хост) запускает забег
			if peer != 1 or r.phase != "start" or rsb_go:
				return false
			rsb_go = true
			_rsb_go_at = _phase_time
			return true
		"rsb_pause":
			if peer != 1 or r.phase != "race" or rsb_paused:
				return false
			rsb_paused = true
			return true
		"rsb_resume":
			if peer != 1 or not rsb_paused:
				return false
			rsb_paused = false
			_rsb_roll_wait = 0.0
			return true
		"rsb_step":  # следующий бросок вручную (на паузе)
			return peer == 1 and rsb_paused and r.roll()
		"rsb_bet":
			return r.place(seat, int(a.get("tok", -1)), str(a.get("spot", "")))
		"rsb_vip":
			return r.pick_vip(seat, int(a.get("i", -1)))
		"next":
			if r.phase == "results" and not ready_peers.has(peer):
				ready_peers[peer] = true
				_try_advance(false)
				return true
	return false


func _rsb_process(delta: float) -> void:
	var r := rsb
	var key := "%s/%d" % [r.phase, r.race_no]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_stamp_turn = true  # новая фаза — часы хода у всех с нуля
		_rsb_roll_wait = 0.0
	_phase_time += delta
	match r.phase:
		"start":
			if rsb_go and _phase_time - _rsb_go_at >= RSB_COUNTDOWN:
				rsb_go = false
				rsb_paused = false
				r.start_race()
				_push_state()
		"race":
			if rsb_paused:
				return
			_rsb_roll_wait += delta
			if _rsb_roll_wait >= _rsb_interval():
				_rsb_roll_wait = 0.0
				r.roll()
				_push_state()
		"results":
			if _phase_time >= auto_advance_time:
				_try_advance(true)
				_push_state()
		"vip":
			# вылетевшие (за них «бот») и задумавшиеся — берут первую карту
			var changed := false
			for s in r.players.size():
				if r.phase != "vip":
					break
				if not r.vip_hand[s].is_empty() and (r.players[s].get("bot", false) or _phase_time >= minf(RSB_VIP_TIME, turn_limit())):
					changed = r.pick_vip(s, 0) or changed
			if changed:
				_push_state()


# =============================================================================
# «Ворд Слэм» на хосте
# =============================================================================

func _start_ws(players: Array) -> String:
	phantom = null
	stillion = null
	var solo: bool = settings.get("ws_mode", "teams") == "solo"
	if not solo:
		var sizes := [0, 0]
		for p in players:
			if p["team"] in [0, 1]:
				sizes[p["team"]] += 1
		for p in players:
			if not p["team"] in [0, 1]:
				p["team"] = 0 if sizes[0] <= sizes[1] else 1
				sizes[p["team"]] += 1
		if sizes[0] < 2 or sizes[1] < 2:
			return "В каждой команде нужно минимум 2 игрока (или выберите «Один рассказчик»)."
	var intro: bool = settings.get("ws_cards", "standard") == "intro"
	var count := WSData.INTRO_CARDS if intro else WSData.standard_cards(players.size())
	rules = null
	perudo = null
	wavelength = null
	dwords = null
	hues = null
	rsb = null
	wslam = WSRules.new()
	wslam.new_game(players, solo, count, intro, bool(settings.get("ws_names", true)))
	auto_advance_time = 25.0
	return ""


func _ws_time_total() -> float:
	return float(settings.get("ws_time", 60))


func _ws_time_left() -> float:
	if wslam == null or wslam.phase != "play":
		return _ws_time_total()
	return maxf(0.0, _ws_time_total() - _phase_time)  # время на ход идёт с «СЛЭМ!»


func _ws_action(peer: int, seat: int, kind: String, arg) -> bool:
	var w := wslam
	var a: Dictionary = arg if arg is Dictionary else {}
	if mode == "offline" and a.has("as"):
		seat = clampi(int(a["as"]), 0, w.players.size() - 1)  # на одном компьютере — от имени нужного игрока
	match kind:
		"ws_reroll":
			return w.reroll(seat)
		"ws_ready":
			return w.set_ready(seat)
		"ws_holders":
			return w.set_holders(seat, a.get("rows", []))
		"ws_point":
			return w.point(seat, str(a.get("id", "")))
		"ws_guess":
			return w.guess(seat, str(a.get("text", "")))
		"ws_confirm":
			return w.confirm(seat, int(a.get("guesser", -1)))
		"next":
			if w.phase == "round_result" and not ready_peers.has(peer):
				ready_peers[peer] = true
				_try_advance(false)
				return true
	return false


func _ws_process(delta: float) -> void:
	var w := wslam
	var key := "%s/%d" % [w.phase, w.round_no]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_stamp_turn = true  # новая фаза — часы хода у всех с нуля
	var before := int(_phase_time)
	_phase_time += delta
	match w.phase:
		"word":
			# вылетевший рассказчик («бот») — готов сам; задумавшийся — по истечении времени хода
			var late := _phase_time >= turn_limit()
			var moved := false
			for s in w.storytellers:
				if w.players[s].get("bot", false) or late:
					moved = w.set_ready(s) or moved
			if moved:
				_push_state()
				return
		"play":
			if _ws_time_left() <= 0.0:
				w.time_up()
				_push_state()
				return
		"round_result":
			if _phase_time >= auto_advance_time:
				_try_advance(true)
				_push_state()
	if int(_phase_time) != before and w.phase == "play":
		_push_state()  # раз в секунду — часы


# =============================================================================
# «Это не шляпа!» на хосте
# =============================================================================

const NH_REVEAL := 4.0  # вскрытие подарка видно всем, потом проигравший идёт в магазин


func _nh_memo_time() -> float:
	return 4.0 + 1.5 * nothat.players.size() * nothat.start_cards


func _nh_action(peer: int, seat: int, kind: String, arg) -> bool:
	var n := nothat
	var a: Dictionary = arg if arg is Dictionary else {}
	if mode == "offline" and a.has("as"):
		seat = clampi(int(a["as"]), 0, n.players.size() - 1)  # на одном компьютере — от имени нужного игрока
	match kind:
		"nh_ready":
			if n.phase == "memorize" and (mode == "offline" or seat == n.giver):
				n.start_play()
				return true
		"nh_give":
			return n.give(seat, int(a.get("g", -1)))
		"nh_respond":
			return n.respond(seat, bool(a.get("accept", true)))
	return false


func _nh_process(delta: float) -> void:
	var n := nothat
	var key := "%s/%d" % [n.phase, n.turn_no]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_bot_wait = 0.0
		_stamp_turn = true
	_phase_time += delta
	_bot_wait += delta
	var changed := false
	match n.phase:
		"memorize":
			if _phase_time >= _nh_memo_time():
				n.start_play()
				changed = true
		"give":
			if n.players[n.giver].get("bot", false) and _bot_wait >= 1.6:
				n.auto_give()
				changed = true
			elif _phase_time >= turn_limit():
				n.auto_give()
				changed = true
		"respond":
			if n.players[n.receiver].get("bot", false) and _bot_wait >= 1.6:
				n.auto_respond(false)
				changed = true
			elif _phase_time >= turn_limit():
				n.auto_respond(true)  # молчание — знак согласия
				changed = true
		"reveal":
			if _phase_time >= NH_REVEAL:
				n.advance()
				changed = true
	if changed:
		_push_state()


# =============================================================================
# Gloom на хосте
# =============================================================================

const GL_REACT_MIN := 2.5  # окно ответа открывается всегда — по паузе не угадать, у кого «Второй шанс»
const GL_REACT_MAX := 12.0


func _gl_action(peer: int, seat: int, kind: String, arg) -> bool:
	var g := gloom
	var a: Dictionary = arg if arg is Dictionary else {}
	if mode == "offline" and a.has("as"):
		seat = clampi(int(a["as"]), 0, g.players.size() - 1)  # на одном компьютере — от имени нужного игрока
	match kind:
		"gl_trim":
			return g.trim(seat, int(a.get("c", -1)))
		"gl_draft":
			return g.draft(seat, int(a.get("id", -1)))
		"gl_play":
			return g.play(seat, int(a.get("card", -1)), int(a.get("target", -1)), a.get("extra", {}) if a.get("extra", {}) is Dictionary else {})
		"gl_discard_hand":
			return g.discard_hand(seat)
		"gl_skip_free":
			return g.skip_free(seat)
		"gl_end":
			return g.end_turn(seat)
		"gl_choose":
			return g.choose(seat, a.get("cards", []) if a.get("cards", []) is Array else [])
		"gl_pick":
			return g.pick(seat, int(a.get("v", -1)))
		"gl_claim":
			return g.claim(seat, int(a.get("st", -1)))
		"gl_respond":
			return g.respond(seat, bool(a.get("use", false)))
	return false


## «Большая бродилка»: br_roll, br_answer {i}, br_use {idx, target}, br_end; на одном компьютере — {as}.
func _br_action(seat: int, kind: String, arg) -> bool:
	var a: Dictionary = arg if arg is Dictionary else {}
	if mode == "offline" and a.has("as"):
		seat = clampi(int(a["as"]), 0, brod.players.size() - 1)  # на одном компьютере — от имени нужного игрока
	match kind:
		"br_roll":
			return brod.roll(seat)
		"br_answer":
			return brod.answer(seat, int(a.get("i", -1)))
		"br_use":
			return brod.use_card(seat, int(a.get("idx", -1)), int(a.get("target", -1)))
		"br_end":
			return brod.end_turn(seat)
	return false


## Чей сейчас ход/выбор; боты действуют с паузой, у людей по таймауту ходит бот.
func _br_process(delta: float) -> void:
	var b := brod
	var who: int = int(b.prompt.seat) if not b.prompt.is_empty() else b.turn
	var key := "%s/%d/%d/%d" % [b.phase, b.turn, who, b.log.size()]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_bot_wait = 0.0
		_stamp_turn = true
	_phase_time += delta
	_bot_wait += delta
	if b.phase == "game_over" or who < 0 or who >= b.players.size():
		return
	if _phase_time >= turn_limit() or (b.is_bot(who) and _bot_wait >= 0.9):
		if BRBot.act(b, who):
			_push_state()


func _gl_bot(s: int) -> bool:
	return s >= 0 and s < gloom.players.size() and gloom.players[s].get("bot", false)


func _gl_process(delta: float) -> void:
	var g := gloom
	var key := "%s/%d/%d/%d/%d" % [g.phase, g.turn_no, g.prompts.size(), g.trim_left.size(), g.draft_order.size()]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_bot_wait = 0.0
		_stamp_turn = true
	_phase_time += delta
	_bot_wait += delta
	var late := _phase_time >= turn_limit()
	var changed := false
	match g.phase:
		"trim":
			if late:
				g.auto_trim()
				changed = true
		"draft":
			if late or (_gl_bot(int(g.draft_order[0])) and _bot_wait >= 0.8):
				g.auto_draft()
				changed = true
		"play":
			if late or (_gl_bot(g.current) and _bot_wait >= 1.2):
				changed = g.end_turn(g.current)  # время вышло / игрок вылетел — ход заканчивается
		"prompt":
			if late or (_gl_bot(int(g.prompt().get("seat", -1))) and _bot_wait >= 1.0):
				g.auto_choose()
				changed = true
		"react":
			var open: Array = g.react["eligible"].filter(func(s): return not s in g.react["passed"] and not _gl_bot(s))
			if _phase_time >= GL_REACT_MAX or (open.is_empty() and _phase_time >= GL_REACT_MIN):
				g.finish_react()
				changed = true
	if changed:
		_push_state()


# =============================================================================
# «Тип Топ» на хосте
# =============================================================================

func _tt_action(peer: int, seat: int, kind: String, arg) -> bool:
	var t := tiptop
	var a: Dictionary = arg if arg is Dictionary else {}
	if mode == "offline" and a.has("as"):
		seat = clampi(int(a["as"]), 0, t.players.size() - 1)  # на одном компьютере — от имени нужного игрока
	match kind:
		"tt_theme":
			return t.pick_theme(seat, int(a.get("i", -1)))
		"tt_answer":
			return t.answer(seat, str(a.get("text", "")))
		"tt_place":
			return t.place(seat, int(a.get("target", -1)), int(a.get("called", -1)))
		"tt_arrange":
			return t.arrange(seat, a.get("order", []), a.get("calls", {}))
		"tt_commit":
			return t.commit(seat)
		"tt_guess":
			return t.guess_captain(seat, int(a.get("n", -1)))
		"next":
			if t.phase == "round_result" and not ready_peers.has(peer):
				ready_peers[peer] = true
				_try_advance(false)
				return true
	return false


func _tt_process(delta: float) -> void:
	var t := tiptop
	var key := "%s/%d" % [t.phase, t.round_no]  # ответы других не сбрасывают часы
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_stamp_turn = true  # новая фаза — часы хода у всех с нуля
		_bot_wait = 0.0
	_phase_time += delta
	_bot_wait += delta
	var late := _phase_time >= turn_limit()
	var cap_bot: bool = t.players[t.captain].get("bot", false)
	var changed := false
	match t.phase:
		"theme":
			if late or (cap_bot and _bot_wait > 1.0):
				changed = t.pick_theme(t.captain, randi() % 2)
		"answer":
			# вылетевшие («боты») отвечают заглушкой, время вышло — заглушка всем молчащим
			for s in t.players.size():
				if t.players[s].get("bot", false) and not t.answers.has(s):
					changed = t.answer(s, "(вылетел)") or changed
			if late and t.phase == "answer":
				t.force_answers()
				changed = true
		"order":
			if late or (cap_bot and _bot_wait > 1.5):
				t.force_commit()  # время вышло / капитан вылетел — раскладка уходит как есть
				changed = true
		"guess":
			if late:
				var other := (t.captain + 1) % t.players.size()
				changed = t.guess_captain(other, randi_range(1, 10))
		"round_result":
			if _phase_time >= auto_advance_time:
				_try_advance(true)
				changed = true
	if changed:
		_push_state()


# =============================================================================
# Пауза и новые игроки посреди партии
# =============================================================================

## Хост ставит партию на паузу / снимает: часы хода и таймеры стоят, ходы не принимаются.
func set_paused(on: bool) -> void:
	if not is_host() or not in_game or paused == on:
		return
	paused = on
	if not on:
		_stamp_turn = true  # часы у всех — с того же места, где остановились
	_system_chat("Хост поставил игру на паузу." if on else "Игра продолжается!")
	_push_state()
	pause_changed.emit()


## Правила текущей игры (любой).
func _game_obj() -> Object:
	for o in [gang, stillion, fours, phantom, brod, gloom, nothat, tiptop, wslam, rsb, hues, dwords, wavelength, perudo, rules]:
		if o != null:
			return o
	return null


## Друзья в пати, которые ещё не сидят за столом: [{peer, name}].
func waiting_members() -> Array:
	var out := []
	if not in_game or not is_host():
		return out
	for id in join_order:
		if not seat_peers.has(id):
			out.append({"peer": id, "name": members[id]["name"]})
	return out


## Места без живого игрока (бот / вылетевший / местный): [{seat, name}].
func free_seats() -> Array:
	var out := []
	if not in_game:
		return out
	for s in seat_peers.size():
		if seat_peers[s] == 0 and s < _gp().size():
			out.append({"seat": s, "name": str(_gp()[s]["name"])})
	return out


## Можно ли добавить в текущую партию ещё одно место.
func can_add_seat() -> bool:
	var g := _game_obj()
	return g != null and g.has_method("can_add_player") and g.can_add_player()


## Посадить друга из пати за стол: на свободное место seat (вместо бота) или новым игроком (seat = -1).
func seat_member(peer: int, seat: int, team: int = -1) -> String:
	if not is_host() or not in_game or not members.has(peer) or seat_peers.has(peer):
		return "Этого игрока нельзя посадить."
	var m: Dictionary = members[peer]
	var nm: String = m["name"]
	if seat >= 0:
		if seat >= seat_peers.size() or seat_peers[seat] != 0:
			return "Место уже занято."
		disconnected.erase(seat)
		seat_peers[seat] = peer
		var gp: Dictionary = _gp()[seat]
		gp["bot"] = false
		gp.erase("local")
		gp["name"] = nm
		gp["steam_id"] = m.get("steam_id", 0)
		gp["color"] = int(m.get("color", 0))
		_system_chat("%s садится за стол вместо бота." % nm)
	else:
		if not can_add_seat():
			return "В эту партию нельзя добавить игрока — только вместо бота."
		var p := {"name": nm, "bot": false, "steam_id": m.get("steam_id", 0), "team": team, "color": int(m.get("color", 0))}
		if not _game_obj().add_player(p):
			return "Не получилось добавить игрока."
		seat_peers.append(peer)
		_system_chat("%s присоединяется к партии!" % nm)
	if mode != "offline":
		_rpc_started.rpc_id(peer, party_game, game_id)
	_stamp_turn = true
	_push_state()
	return ""


# =============================================================================
# Пати: выбор игры, конец партии
# =============================================================================

func is_party() -> bool:
	return mode == "steam" or mode == "enet"


## Участник пати (не хост) предлагает игру — у его ника в пати появляется «Предлагает игру …».
func suggest_game(game_id: String) -> void:
	if is_host():
		_set_member_suggest(1, game_id)
	else:
		_rpc_suggest_game.rpc_id(1, game_id)


@rpc("any_peer", "reliable")
func _rpc_suggest_game(game_id: String) -> void:
	if is_host():
		_set_member_suggest(multiplayer.get_remote_sender_id(), game_id)


func _set_member_suggest(peer: int, game_id: String) -> void:
	if members.has(peer) and is_party():
		members[peer]["suggest"] = game_id.left(40)
		_broadcast_lobby()


## Хост выбирает игру — все участники пати переходят в её лобби.
func select_game(game_id: String) -> void:
	if not is_host():
		return
	if in_game:
		_finish_session()
	for id in members:
		members[id].erase("suggest")  # игра выбрана — предложения сбрасываются
	party_game = game_id
	_st_deck.clear()  # вышли к выбору игры — вопросы «Стиллиона» снова все
	_broadcast_lobby()
	party_game_changed.emit(game_id)


## Хост возвращает всех к выбору игры (пати сохраняется).
func return_to_party() -> void:
	select_game("")


## Хост завершает партию: все возвращаются в лобби текущей игры.
func end_game() -> void:
	if not is_host() or not in_game:
		return
	_finish_session()
	if mode != "offline":
		_rpc_end_game.rpc()
	game_ended.emit()
	_broadcast_lobby()


func _finish_session() -> void:
	_client_start_pending = false
	_client_expected_match = ""
	gang = null
	tg_view_seat = 0
	fours = null
	phantom = null
	stillion = null
	in_game = false
	paused = false
	rules = null
	perudo = null
	wavelength = null
	dwords = null
	hues = null
	rsb = null
	wslam = null
	tiptop = null
	nothat = null
	gloom = null
	brod = null
	ready_peers.clear()
	disconnected.clear()
	seat_peers.clear()
	view = {}


@rpc("authority", "reliable")
func _rpc_end_game() -> void:
	_finish_session()
	game_ended.emit()


# =============================================================================
# Чат и реакции
# =============================================================================

## kind: "chat" — сообщение, "emote" — быстрая реакция.
func send_chat(text: String, kind: String = "chat", team_only: bool = false) -> void:
	if team_only:
		kind = "team_emote" if kind == "emote" else "team"
	text = text.strip_edges().left(200)
	if text == "" or not in_session():
		return
	if is_host():
		_host_chat(1, text, kind)
	else:
		_rpc_chat_up.rpc_id(1, text, kind)


@rpc("any_peer", "reliable")
func _rpc_chat_up(text: String, kind: String) -> void:
	if is_host():
		_host_chat(multiplayer.get_remote_sender_id(), text, kind)


func _host_chat(peer: int, text: String, kind: String) -> void:
	text = text.strip_edges().left(200)
	if not members.has(peer) or text.is_empty() or kind not in ["chat", "emote", "team", "team_emote"]:
		return
	var private_team := kind in ["team", "team_emote"]
	var sender_team := chat_team(peer)
	if private_team and sender_team < 0:
		return
	if in_game:
		_match_metrics.observe(game_id,party_game,_game_obj(),seat_peers)
		var stats_seat := seat_peers.find(peer)
		_match_metrics.say(stats_seat, "emote" if kind in ["emote", "team_emote"] else "chat")
		var snapshot := _match_metrics.snapshot(stats_seat)
		if peer==1: player_stats.consume(snapshot)
		else: _rpc_personal_stats.rpc_id(peer,snapshot)
	var entry := {
		"name": members[peer]["name"] if members.has(peer) else "?",
		"color": PLAYER_COLORS[int(members[peer].get("color", 0))] if members.has(peer) else "",
		"seat": seat_peers.find(peer) if in_game else -1,
		"peer": peer,  # по нему чат берёт текущий цвет автора (цвет можно сменить посреди игры)
		"text": text,
		"kind": "emote" if kind in ["emote", "team_emote"] else "chat",
		"scope": "team" if private_team else "all",
		"team": sender_team if private_team else -1,
		"game_id": game_id,
		"voice": _voice_of(peer),  # реплики звучат голосом персонажа, закреплённого за игроком
	}
	if private_team:
		if chat_team(1) == sender_team:
			_apply_chat(entry)
		if mode != "offline":
			for recipient in join_order:
				if recipient != 1 and chat_team(int(recipient)) == sender_team:
					_rpc_chat_down.rpc_id(int(recipient), entry)
	else:
		_send_chat_entry(entry)


## Команда вычисляется хостом по реальной рассадке, клиентом — по своему представлению.
func chat_team(peer: int = -1) -> int:
	if not in_game or party_game not in ["wavelength", "word_slam", "dangerous_words", "phantom_ink"]:
		return -1
	if party_game == "word_slam" and settings.get("ws_mode", "teams") == "solo":
		return -1
	var seat: int
	var player_list: Array
	var role_list: Array = []
	if is_host() and peer >= 0:
		seat = seat_peers.find(peer)
		var game := _game_obj()
		if game == null:
			return -1
		player_list = game.players
		if party_game == "phantom_ink":
			role_list = game.roles
	else:
		seat = int(view.get("seat", view.get("you", -1)))
		player_list = view.get("players", [])
		role_list = view.get("roles", [])
	if seat < 0 or seat >= player_list.size():
		return -1
	if party_game == "phantom_ink":
		return int(int(role_list[seat]) / 2) if seat < role_list.size() else -1
	return int(player_list[seat].get("team", -1))


func chat_entry_visible(entry: Dictionary) -> bool:
	var session: String = game_id if is_host() else str(view.get("game_id", ""))
	return entry.get("scope", "all") != "team" or (in_game and str(entry.get("game_id", "")) == session and int(entry.get("team", -1)) == chat_team())


@rpc("authority", "reliable")
func _rpc_personal_stats(snapshot: Dictionary) -> void:
	player_stats.consume(snapshot)


## Голос персонажа для реплик: выдаётся игроку случайно из свободных (голоса в пати не повторяются)
## и держится за ним, пока он в пати (уходит — голос освобождается вместе с записью members).
func _voice_of(peer: int) -> String:
	if not members.has(peer):
		return ""
	var v := str(members[peer].get("voice", ""))
	if v != "":
		return v
	var used := []
	for id in members:
		used.append(str(members[id].get("voice", "")))
	var free := Sfx.VOICES.filter(func(x): return not used.has(x))
	v = free.pick_random() if not free.is_empty() else Sfx.VOICES.pick_random()
	members[peer]["voice"] = v
	return v


func _system_chat(text: String) -> void:
	_send_chat_entry({"name": "", "seat": -1, "text": text, "kind": "system"})


func _send_chat_entry(entry: Dictionary) -> void:
	_apply_chat(entry)
	if mode != "offline":
		_rpc_chat_down.rpc(entry)


@rpc("authority", "reliable")
func _rpc_chat_down(entry: Dictionary) -> void:
	_apply_chat(entry)


## Тень действия: что игрок делает прямо сейчас (тащит фишку и т. п.) — остальные видят полупрозрачную копию.
## Не влияет на партию, идёт без гарантии доставки (потерялась позиция — придёт следующая). В офлайне не нужна.
func send_ghost(data: Dictionary) -> void:
	if mode == "offline" or mode == "" or not in_session():
		return
	if is_host():
		_rpc_ghost_down.rpc(1, data)
	else:
		_rpc_ghost_up.rpc_id(1, data)


@rpc("any_peer", "unreliable_ordered")
func _rpc_ghost_up(data: Dictionary) -> void:
	if not is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	ghost_received.emit(from, data)
	for id in multiplayer.get_peers():
		if id != from:
			_rpc_ghost_down.rpc_id(id, from, data)


@rpc("authority", "unreliable_ordered")
func _rpc_ghost_down(from: int, data: Dictionary) -> void:
	if from != multiplayer.get_unique_id():
		ghost_received.emit(from, data)


func _apply_chat(entry: Dictionary) -> void:
	chat_log.append(entry)
	if chat_log.size() > 80:
		chat_log.pop_front()
	chat_received.emit(entry)


var _netlog := OS.get_cmdline_user_args().has("--netlog")


func _dbg(msg: String) -> void:
	if _netlog:
		print("[%s %d %.2f] %s" % [my_name, multiplayer.get_unique_id(), Time.get_ticks_msec() / 1000.0, msg])


## Локально переключаем закрытый экран; по сети чужие роли выбирать нельзя.
func pi_switch_seat(seat: int) -> void:
	if mode != "offline" or phantom == null or seat < 0 or seat >= phantom.players.size():
		return
	pi_view_seat = seat
	_push_state()


## Смена личного экрана Four Souls только за одним компьютером.
func fs_switch_seat(seat: int) -> void:
	if mode != "offline" or fours == null or seat < 0 or seat >= fours.players.size():
		return
	fs_view_seat = seat
	_push_state()


# =============================================================================
# «Стиллион» на хосте
# =============================================================================

## Тик правил; ответ не из списка вопроса — на проверку jev (пока проверяется, фитиль стоит).
func _st_process(delta: float) -> void:
	if paused:
		return
	if not _st_verdict.is_empty():
		var held: Array = _st_verdict
		_st_verdict = []
		if held[0] == stillion and stillion.resolve_external(int(held[1]), bool(held[2]), str(held[3])):
			_push_state()
	if stillion.tick(delta):
		_push_state()
	if stillion.phase == "check" and int(stillion.pending.get("no", -1)) != _st_checking:
		_st_checking = int(stillion.pending.no)
		if _st_jev == null or _st_jev_for != stillion:
			# новая партия — новый проверяющий; старый вместе с незавершёнными запросами удаляется
			if _st_jev != null:
				_st_jev.queue_free()
			_st_jev = STJev.new()
			_st_jev_for = stillion
			_st_verdict = []
			add_child(_st_jev)
			var game := stillion
			_st_jev.judged.connect(func(no: int, ok: bool, rarity: String): _st_judged(game, no, ok, rarity))
		_st_jev.check(_st_checking, stillion.question, str(stillion.pending.text), bool(stillion.pending.get("appeal", false)))


## Вердикт jev: только для своей партии; на паузе — откладываем до продолжения.
func _st_judged(game: STRules, no: int, ok: bool, rarity: String) -> void:
	if game != stillion or stillion == null:
		return
	if paused:
		_st_verdict = [game, no, ok, rarity]
		return
	if stillion.resolve_external(no, ok, rarity):
		_push_state()


## The Gang: один срок на раунд, случайный выбор только отсутствующих фишек.
func _tg_process(delta: float) -> void:
	var key := "%s/%d" % [gang.phase, gang.turn_no]
	if key != _last_phase:
		_last_phase = key
		_phase_time = 0.0
		_stamp_turn = true
	_phase_time += delta
	if gang.phase != "rank":
		return
	if _phase_time >= turn_limit():
		if gang.timeout():
			_push_state()
		return
	# Без общего лимита вылетевшие всё равно не блокируют живую команду.
	if turn_limit() == INF and _phase_time >= 60.0:
		var changed := false
		var current_round: int = gang.turn_no
		for seat in seat_peers.size():
			if gang.turn_no != current_round or gang.phase != "rank":
				break
			if seat_peers[seat] != 0 or mode == "offline":
				continue
			var tg_view: Dictionary = gang.get_view(seat)
			var assigned: Array = tg_view.get("chips", [])
			if int(assigned[seat]) != 0:
				continue
			var available: Array = []
			for value in range(1, seat_peers.size() + 1):
				if not assigned.has(value):
					available.append(value)
			if not available.is_empty():
				changed = gang.action(seat, "take", {"value": available.pick_random()}) or changed
		if changed:
			_push_state()
