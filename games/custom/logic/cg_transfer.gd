extends Node
## Передача ZIP от хоста частями по 48 КБ. RPC принимают только данные, кэш отделён от исходников.

const Package := preload("res://games/custom/logic/cg_package.gd")
const Library := preload("res://games/custom/logic/cg_library.gd")
var net: Node
var manifest: Dictionary = {}
var verified: Dictionary = {}
var progress: Dictionary = {}
var error := ""
var selected := ""
var _outgoing := PackedByteArray()
var _queue: Array = []
var _incoming := PackedByteArray()
var _incoming_hash := ""
var _clock := 0.0
var _idle := 0.0
var _requested := false

func reset() -> void:
	manifest = {}
	verified.clear()
	progress.clear()
	_queue.clear()
	_outgoing.clear()
	selected = ""
	error = ""
	_requested = false
	# Частично полученные байты остаются до следующего манифеста: тот же hash докачивается.

func prepare(id: String) -> void:
	reset()
	selected = id
	var built := Library.build_package(id)
	if not str(built.error).is_empty():
		error = str(built.error)
		return
	var definition := Library.load_game(id)
	manifest = {"uuid": id, "hash": built.hash, "size": built.size, "title": str(definition.meta.title), "roles": definition.rules.get("roles", [{"id": "leader", "name": "Ведущий"}, {"id": "player", "name": "Игрок"}]).duplicate(true)}
	_outgoing = FileAccess.get_file_as_bytes(built.path)
	verified[1] = str(built.hash)

func can_start() -> bool:
	if manifest.is_empty() or not error.is_empty():
		return false
	for peer: Variant in net.members:
		if verified.get(int(peer), "") != manifest.hash:
			return false
	return true

func receive_manifest(data: Dictionary) -> void:
	if net.is_host():
		return
	if data.is_empty():
		reset()
		return
	if not Library.uuid_valid(str(data.get("uuid", ""))) or not Package.hash_valid(str(data.get("hash", ""))) or not (data.get("size") is int or data.get("size") is float):
		error = "Хост прислал неверное описание пакета."
		return
	var roles: Variant = data.get("roles", [])
	if not roles is Array or roles.is_empty() or roles.size() > 16:
		error = "Неверные роли в описании пакета."
		return
	for role: Variant in roles:
		if not role is Dictionary or not role.get("id") is String or not role.get("name", "") is String or str(role.id).length() > 64 or str(role.get("name", "")).length() > 128:
			error = "Неверная роль в описании пакета."
			return
	var size_value := int(data.size)
	if not is_finite(float(data.size)) or float(size_value) != float(data.size) or size_value < 22 or size_value > Package.LIMIT:
		error = "Размер пакета хоста превышает лимит."
		return
	if manifest.get("hash") == data.hash and (_requested or verified.get(net.multiplayer.get_unique_id(), "") == data.hash):
		return
	manifest = data.duplicate(true)
	error = ""
	var cached := Library.cached(str(data.hash))
	if str(cached.error).is_empty():
		if cached.definition.get("id") != data.uuid:
			error = "Идентификатор игры не совпадает с пакетом."
			return
		verified[net.multiplayer.get_unique_id()] = str(data.hash)
		_rpc_ready.rpc_id(1, str(data.hash))
		return
	if _incoming_hash != data.hash:
		_incoming.clear()
		_incoming_hash = str(data.hash)
	if _incoming.size() > size_value:
		_incoming.clear()
	_requested = true
	_idle = 0.0
	_rpc_request.rpc_id(1, str(data.hash), _incoming.size())

@rpc("any_peer", "reliable")
func _rpc_request(hash_value: String, offset: int) -> void:
	if not net.is_host() or manifest.is_empty() or hash_value != manifest.hash:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not net.members.has(peer) or offset < 0 or offset > _outgoing.size() or offset % Package.CHUNK != 0:
		return
	for queued: Dictionary in _queue:
		if int(queued.peer) == peer:
			return
	verified.erase(peer)
	_queue.append({"peer": peer, "offset": offset})
	progress[peer] = offset

@rpc("authority", "reliable")
func _rpc_chunk(hash_value: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	if net.is_host():
		return
	var result := accept_chunk(hash_value, offset, total, bytes)
	if not result:
		return
	_idle = 0.0
	net.lobby_changed.emit()
	if _incoming.size() == total:
		var cached := Library.put_cache(hash_value, _incoming)
		_requested = false
		if not str(cached.error).is_empty():
			error = str(cached.error)
			_incoming.clear()
		elif cached.definition.get("id") != manifest.get("uuid"):
			error = "Идентификатор игры не совпадает с пакетом."
			_incoming.clear()
		else:
			verified[net.multiplayer.get_unique_id()] = hash_value
			_incoming.clear()
			_rpc_ready.rpc_id(1, hash_value)
		net.lobby_changed.emit()

func accept_chunk(hash_value: String, offset: int, total: int, bytes: PackedByteArray) -> bool:
	if manifest.is_empty() or not _requested or hash_value != manifest.get("hash") or total != int(manifest.get("size", 0)):
		return false
	if offset != _incoming.size() or offset < 0 or total > Package.LIMIT or bytes.is_empty() or bytes.size() != mini(Package.CHUNK, total - offset):
		return false
	_incoming.append_array(bytes)
	progress[1] = _incoming.size()
	return true

@rpc("any_peer", "reliable")
func _rpc_ready(hash_value: String) -> void:
	if not net.is_host() or manifest.is_empty() or hash_value != manifest.hash:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not net.members.has(peer):
		return
	verified[peer] = hash_value
	progress[peer] = int(manifest.size)
	net._broadcast_lobby()

func _process(delta: float) -> void:
	if net == null or manifest.is_empty():
		return
	if not net.is_host():
		if _requested:
			_idle += delta
			if _idle > 30:
				_requested = false
				error = "Загрузка остановилась. Переподключитесь для продолжения."
				net.lobby_changed.emit()
		return
	_clock += delta
	if _clock < 0.015 or _queue.is_empty():
		return
	_clock = 0.0
	var entry: Dictionary = _queue[0]
	var peer := int(entry.peer)
	var offset := int(entry.offset)
	if not net.members.has(peer) or offset >= _outgoing.size():
		_queue.pop_front()
		return
	var bytes := _outgoing.slice(offset, mini(offset + Package.CHUNK, _outgoing.size()))
	_rpc_chunk.rpc_id(peer, str(manifest.hash), offset, _outgoing.size(), bytes)
	entry.offset = offset + bytes.size()
	progress[peer] = int(entry.offset)
	if int(entry.offset) >= _outgoing.size():
		_queue.pop_front()
