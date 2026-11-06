extends Node
## Синхронизация стикеров хаба внутри пати (узел /root/Net/Stickers, создаёт Net).
##
## У каждого участника свои данные (hub/stickers.gd: стикеры на коробках + доска, которую клеят друзья).
## Хозяин публикует их как и снимок шкафа: участник → хост (проверка) → всем. Наклеить/снять на чужой
## доске — запрос хосту: хост знает настоящего отправителя, подставляет его ключ автора и передаёт хозяину
## доски; хозяин сохраняет у себя и публикует новый снимок. Себе клеить нельзя, снять можно только своё.
## Без пати (или в офлайне) работает только локально.

signal changed(peer: int)  # обновились стикеры участника (0 — все сразу)
signal notice(text: String)  # короткое сообщение для подсказки хаба
signal poster_ready(hash: String)  # картинка плаката друга скачана

const POSTER_DIR := "user://posters/"  # свои картинки плакатов и скачанные у друзей (по хэшу)
const CHUNK := 48000

const Stickers := preload("res://hub/stickers.gd")

var rooms: Dictionary = {}  # peer → {"boxes": {...}, "board": [...]}, у хоста и всех клиентов
var local := {"boxes": {}, "board": []}  # свои данные (сохраняются на диск)
var _sent := {}
var _pending := false
var _clock := 0.0
var _known: Dictionary = {}  # хост: кому уже разослан полный набор
var _poster_bytes: Dictionary = {}  # хост: хэш → байты картинок плакатов участников
var _incoming: Dictionary = {}  # сборка кусков: ключ → {count, parts}
var _wanted: Dictionary = {}  # клиент: уже запрошенные хэши
var _uploaded: Dictionary = {}  # клиент: какие свои картинки уже отданы хосту в этой пати
var _textures: Dictionary = {}  # хэш → Texture2D
var _waiters: Dictionary = {}  # хост: хэш → кто ждёт картинку, которой у хоста ещё нет
var _pulled: Dictionary = {}  # хост: у кого уже попросили картинку (хэш → время запроса)


func _ready() -> void:
	name = "Stickers"
	local = Stickers.load_local()
	multiplayer.peer_disconnected.connect(_on_peer_gone)


func _net() -> Node:
	return get_parent()


func _party() -> bool:
	var net := _net()
	return net != null and net.is_party() and net.mode != "offline" and multiplayer.multiplayer_peer != null


func my_peer() -> int:
	return multiplayer.get_unique_id() if _party() else 1


## Данные комнаты участника; своя — всегда локальная копия.
func room_of(peer: int) -> Dictionary:
	if peer == 0 or peer == my_peer():
		return local
	return rooms.get(peer, {"boxes": {}, "board": []})


## Как меня видит хост: Steam ID, а без него — ник из списка пати (хост мог дописать к нему номер).
func my_author_key() -> String:
	var net := _net()
	var nick := str(net.my_name)
	for member: Dictionary in net.lobby_view.get("members", []):
		if int(member.get("peer", 0)) == my_peer():
			nick = str(member.get("name", nick))
	return Stickers.author_key(int(net.my_steam_id), nick)


# --- Свои коробки ---------------------------------------------------------------------

func box_stickers(game: String) -> Array:
	return local.boxes.get(game, [])


func add_box_sticker(game: String, sticker: String, u: float, v: float, r: float, face: int = 0) -> bool:
	var entry := Stickers.clean_box_sticker([sticker, u, v, r, 1.0, face])
	if entry.is_empty() or game.is_empty():
		return false
	var list: Array = local.boxes.get(game, [])
	if list.size() >= Stickers.BOX_MAX:
		notice.emit("На коробке уже %d стикеров — снимите один" % Stickers.BOX_MAX)
		return false
	list.append(entry)
	local.boxes[game] = list
	_local_changed()
	return true


## Сдвинуть/повернуть/изменить размер своего стикера на коробке. save=false — только показ (идёт перетаскивание).
func update_box_sticker(game: String, index: int, u: float, v: float, r: float, k: float, save: bool = true) -> void:
	var list: Array = local.boxes.get(game, [])
	if index < 0 or index >= list.size():
		return
	var face: int = int(list[index][5]) if (list[index] as Array).size() > 5 else 0  # сторона коробки не меняется
	var entry := Stickers.clean_box_sticker([list[index][0], u, v, r, k, face])
	if entry.is_empty():
		return
	list[index] = entry
	if save:
		_local_changed()
	else:
		changed.emit(my_peer())


# --- Плакаты комнаты -------------------------------------------------------------------

func _poster_list() -> Array:
	var list: Array = (local.get("posters", []) as Array).duplicate(true)
	while list.size() < Stickers.POSTERS:
		list.append([])
	return list


## Перевесили свой плакат (центр на задней стене, м).
func set_poster_pos(slot: int, center: Vector2) -> void:
	var list := _poster_list()
	var entry: Array = list[slot]
	list[slot] = [center.x, center.y, str(entry[2]) if entry.size() >= 3 else "", float(entry[3]) if entry.size() >= 4 else 1.0]
	local["posters"] = list
	_local_changed()


## Размер своего плаката: 1 — обычный, до POSTER_SCALE_MAX (вдвое больше).
func set_poster_scale(slot: int, center: Vector2, scale: float) -> void:
	var list := _poster_list()
	var entry: Array = list[slot]
	list[slot] = [center.x, center.y, str(entry[2]) if entry.size() >= 3 else "", clampf(scale, 1.0, Stickers.POSTER_SCALE_MAX)]
	local["posters"] = list
	_local_changed()


func poster_scale(peer: int, slot: int) -> float:
	var list: Array = room_of(peer).get("posters", [])
	if slot < list.size() and list[slot] is Array and (list[slot] as Array).size() >= 4:
		return float(list[slot][3])
	return 1.0


## Своя картинка на плакат: ужимаем до POSTER_MAX_SIDE, храним JPEG по хэшу, друзьям — через хоста.
func set_poster_picture(slot: int, image: Image, center: Vector2) -> String:
	if image == null or image.is_empty():
		return ""
	image.convert(Image.FORMAT_RGB8)
	var longest := maxi(image.get_width(), image.get_height())
	if longest > Stickers.POSTER_MAX_SIDE:
		var k := float(Stickers.POSTER_MAX_SIDE) / longest
		image.resize(maxi(1, roundi(image.get_width() * k)), maxi(1, roundi(image.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	var bytes := image.save_jpg_to_buffer(0.88)
	if bytes.size() > Stickers.POSTER_MAX_BYTES:
		bytes = image.save_jpg_to_buffer(0.7)
	var hash := _sha(bytes)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(POSTER_DIR))
	var file := FileAccess.open(POSTER_DIR + hash + ".jpg", FileAccess.WRITE)
	if file == null:
		notice.emit("Не удалось сохранить картинку плаката")
		return ""
	file.store_buffer(bytes)
	file.close()
	var list := _poster_list()
	var old: Array = list[slot]
	list[slot] = [center.x, center.y, hash, float(old[3]) if old.size() >= 4 else 1.0]
	local["posters"] = list
	_local_changed()
	_upload(hash)
	return hash


## Клиент полностью вошёл в пати: соединение есть и хост уже прислал список, где есть мы.
## Раньше картинку, поставленную до входа в пати, отправляли в момент подключения — хост её отбрасывал
## (ещё не знал игрока), а клиент считал её отправленной, и друзья так её и не видели.
func _joined() -> bool:
	if _net().is_host():
		return true
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	var me := multiplayer.get_unique_id()
	return (_net().lobby_view.get("members", []) as Array).any(func(member): return int(member.get("peer", 0)) == me)


## Хост: у кого из участников плакат с этим хэшем.
func _poster_owner(hash: String) -> int:
	for peer: Variant in rooms:
		for entry: Variant in (rooms[peer] as Dictionary).get("posters", []):
			if entry is Array and (entry as Array).size() >= 3 and str(entry[2]) == hash:
				return int(peer)
	return 0


## Хост: картинки нет — просим её у владельца плаката (не чаще раза в 5 с на картинку).
func _pull(hash: String) -> void:
	var owner := _poster_owner(hash)
	if owner <= 1 or _member(owner).is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_pulled.get(hash, -100000)) < 5000:
		return
	_pulled[hash] = now
	_rpc_poster_need.rpc_id(owner, hash)


## Картинка плаката по хэшу (своя или друга). Нет на диске — просим у хоста, придёт сигнал poster_ready.
func poster_texture(hash: String) -> Texture2D:
	if hash.is_empty():
		return null
	if _textures.has(hash):
		return _textures[hash]
	var bytes := _poster_file(hash)
	if bytes.is_empty() and _poster_bytes.has(hash):
		bytes = _poster_bytes[hash]
	if not bytes.is_empty():
		var texture := _texture(bytes)
		if texture != null:
			_textures[hash] = texture
		return texture
	if _party() and _net().is_host():
		_pull(hash)
	elif _party() and not _wanted.has(hash):
		_wanted[hash] = true
		_rpc_poster_want.rpc_id(1, hash)
	return null


func _poster_file(hash: String) -> PackedByteArray:
	var path := POSTER_DIR + hash + ".jpg"
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


static func _texture(bytes: PackedByteArray) -> Texture2D:
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK:
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Клиент отдаёт хосту картинку своего плаката (кусками) — хост раздаёт её тем, кто смотрит комнату.
func _upload(hash: String) -> void:
	if not _party() or _uploaded.has(hash) or not _joined():
		return
	var bytes := _poster_file(hash)
	if bytes.is_empty():
		return
	_uploaded[hash] = true
	if _net().is_host():
		_poster_bytes[hash] = bytes
		return
	var count := ceili(float(bytes.size()) / CHUNK)
	for i in count:
		_rpc_poster_upload.rpc_id(1, hash, i, count, bytes.slice(i * CHUNK, mini(bytes.size(), (i + 1) * CHUNK)))


func _collect(key: String, index: int, count: int, chunk: PackedByteArray) -> PackedByteArray:
	if count < 1 or count > ceili(float(Stickers.POSTER_MAX_BYTES) / CHUNK) + 1 or index < 0 or index >= count:
		return PackedByteArray()
	var entry: Dictionary = _incoming.get(key, {"count": count, "parts": {}})
	if int(entry.count) != count:
		entry = {"count": count, "parts": {}}
	entry.parts[index] = chunk
	_incoming[key] = entry
	if entry.parts.size() < count:
		return PackedByteArray()
	_incoming.erase(key)
	var bytes := PackedByteArray()
	for i in count:
		bytes.append_array(entry.parts[i])
	return bytes


@rpc("any_peer", "reliable")
func _rpc_poster_upload(hash: String, index: int, count: int, chunk: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _net().is_host() or _member(sender).is_empty() or hash.length() != 64:
		return
	var bytes := _collect("up:%d:%s" % [sender, hash], index, count, chunk)
	if bytes.is_empty() or bytes.size() > Stickers.POSTER_MAX_BYTES or _sha(bytes) != hash:
		return
	_poster_bytes[hash] = bytes
	_pulled.erase(hash)
	for waiter: int in _waiters.get(hash, []):
		if not _member(waiter).is_empty():
			_deliver(waiter, hash, bytes)
	_waiters.erase(hash)
	poster_ready.emit(hash)


func _deliver(peer: int, hash: String, bytes: PackedByteArray) -> void:
	var count := ceili(float(bytes.size()) / CHUNK)
	for i in count:
		_rpc_poster_deliver.rpc_id(peer, hash, i, count, bytes.slice(i * CHUNK, mini(bytes.size(), (i + 1) * CHUNK)))


## Хост просит у владельца его картинку (её у хоста нет, а друзья ждут).
@rpc("authority", "reliable")
func _rpc_poster_need(hash: String) -> void:
	_uploaded.erase(hash)
	_upload(hash)


@rpc("any_peer", "reliable")
func _rpc_poster_want(hash: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _net().is_host() or _member(sender).is_empty() or hash.length() != 64:
		return
	var bytes: PackedByteArray = _poster_bytes.get(hash, _poster_file(hash))
	if bytes.is_empty():
		# Картинки у хоста ещё нет — запомнить, кто ждёт, и попросить у владельца плаката.
		var list: Array = _waiters.get(hash, [])
		if not list.has(sender):
			list.append(sender)
		_waiters[hash] = list
		_pull(hash)
		return
	_deliver(sender, hash, bytes)


@rpc("authority", "reliable")
func _rpc_poster_deliver(hash: String, index: int, count: int, chunk: PackedByteArray) -> void:
	var bytes := _collect("down:" + hash, index, count, chunk)
	if bytes.is_empty() or bytes.size() > Stickers.POSTER_MAX_BYTES or _sha(bytes) != hash:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(POSTER_DIR))
	var file := FileAccess.open(POSTER_DIR + hash + ".jpg", FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()
	_wanted.erase(hash)
	_textures.erase(hash)
	poster_ready.emit(hash)


## Хозяин перевесил свою доску (центр на задней стене, м). Видят и друзья в режиме наблюдения.
func set_board_pos(pos: Vector2) -> void:
	var clamped := Stickers.clamp_board_pos(pos)
	local["pos"] = [clamped.x, clamped.y]
	_local_changed()


func board_pos(peer: int) -> Vector2:
	var pos: Array = room_of(peer).get("pos", [])
	return Vector2(float(pos[0]), float(pos[1])) if pos.size() == 2 else Stickers.BOARD_DEFAULT


func remove_box_sticker(game: String, index: int) -> void:
	var list: Array = local.boxes.get(game, [])
	if index < 0 or index >= list.size():
		return
	list.remove_at(index)
	if list.is_empty():
		local.boxes.erase(game)
	_local_changed()


# --- Доска друга ----------------------------------------------------------------------

## Наклеить стикер на доску участника owner (своя доска — нельзя).
func request_board_add(owner: int, sticker: String, u: float, v: float, r: float) -> bool:
	if not _party() or owner == my_peer() or owner <= 0:
		notice.emit("На свою доску клеить нельзя — её украшают друзья")
		return false
	if Stickers.clean_box_sticker([sticker, u, v, r]).is_empty():
		return false
	if my_board_stickers(owner).size() >= Stickers.BOARD_PER_AUTHOR:
		notice.emit("На одной доске — не больше %d ваших стикеров. Снимите или поправьте свои." % Stickers.BOARD_PER_AUTHOR)
		return false
	if _net().is_host():
		_host_add(1, owner, sticker, u, v, r)
	else:
		_rpc_add.rpc_id(1, owner, sticker, u, v, r)
	return true


func request_board_remove(owner: int, uid: String) -> void:
	if not _party() or owner == my_peer():
		return
	if _net().is_host():
		_host_remove(1, owner, uid)
	else:
		_rpc_remove.rpc_id(1, owner, uid)


## Изменить свой стикер на доске участника owner (место, поворот, размер).
func request_board_update(owner: int, uid: String, u: float, v: float, r: float, k: float) -> void:
	if not _party() or owner == my_peer() or Stickers.clean_box_sticker(["fire", u, v, r, k]).is_empty():
		return
	if _net().is_host():
		_host_update(1, owner, uid, u, v, r, k)
	else:
		_rpc_update.rpc_id(1, owner, uid, u, v, r, k)


## Мои стикеры на доске участника owner: [[uid, id стикера, u, v, r], ...].
func my_board_stickers(owner: int) -> Array:
	var key := my_author_key()
	return room_of(owner).board.filter(func(entry): return str(entry[5]) == key)


@rpc("any_peer", "reliable")
func _rpc_add(owner: int, sticker: String, u: float, v: float, r: float) -> void:
	if _net().is_host():
		_host_add(multiplayer.get_remote_sender_id(), owner, sticker, u, v, r)


@rpc("any_peer", "reliable")
func _rpc_update(owner: int, uid: String, u: float, v: float, r: float, k: float) -> void:
	if _net().is_host():
		_host_update(multiplayer.get_remote_sender_id(), owner, uid, u, v, r, k)


@rpc("any_peer", "reliable")
func _rpc_remove(owner: int, uid: String) -> void:
	if _net().is_host():
		_host_remove(multiplayer.get_remote_sender_id(), owner, uid)


func _member(peer: int) -> Dictionary:
	var members: Dictionary = _net().members
	return members.get(peer, {})


## Хост: отправитель — настоящий peer RPC, ключ автора берём из участников пати, не из запроса.
func _host_add(sender: int, owner: int, sticker: String, u: float, v: float, r: float) -> void:
	if sender == owner or _member(sender).is_empty() or _member(owner).is_empty():
		return
	var author: Dictionary = _member(sender)
	var key := Stickers.author_key(int(author.get("steam_id", 0)), str(author.get("name", "")))
	var nick := str(author.get("name", "Друг"))
	if owner == 1:
		_owner_add(key, nick, sticker, u, v, r)
	else:
		_rpc_owner_add.rpc_id(owner, key, nick, sticker, u, v, r)


func _host_remove(sender: int, owner: int, uid: String) -> void:
	if sender == owner or _member(sender).is_empty() or _member(owner).is_empty():
		return
	var author: Dictionary = _member(sender)
	var key := Stickers.author_key(int(author.get("steam_id", 0)), str(author.get("name", "")))
	if owner == 1:
		_owner_remove(key, uid)
	else:
		_rpc_owner_remove.rpc_id(owner, key, uid)


func _host_update(sender: int, owner: int, uid: String, u: float, v: float, r: float, k: float) -> void:
	if sender == owner or _member(sender).is_empty() or _member(owner).is_empty():
		return
	var author: Dictionary = _member(sender)
	var key := Stickers.author_key(int(author.get("steam_id", 0)), str(author.get("name", "")))
	if owner == 1:
		_owner_update(key, uid, u, v, r, k)
	else:
		_rpc_owner_update.rpc_id(owner, key, uid, u, v, r, k)


@rpc("authority", "reliable")
func _rpc_owner_update(key: String, uid: String, u: float, v: float, r: float, k: float) -> void:
	_owner_update(key, uid, u, v, r, k)


## Хозяин доски меняет стикер только по запросу его автора (ключ подставил хост).
func _owner_update(key: String, uid: String, u: float, v: float, r: float, k: float) -> void:
	for i in local.board.size():
		var entry: Array = local.board[i]
		if str(entry[0]) == uid and str(entry[5]) == key:
			var updated := Stickers.clean_board_sticker([entry[0], entry[1], u, v, r, entry[5], entry[6], k])
			if not updated.is_empty() and updated != entry:
				local.board[i] = updated
				_local_changed()
			return


@rpc("authority", "reliable")
func _rpc_owner_add(key: String, nick: String, sticker: String, u: float, v: float, r: float) -> void:
	_owner_add(key, nick, sticker, u, v, r)


@rpc("authority", "reliable")
func _rpc_owner_remove(key: String, uid: String) -> void:
	_owner_remove(key, uid)


## Хозяин доски: сам себе не клеит (ключ автора совпал со своим — отказ).
func _owner_add(key: String, nick: String, sticker: String, u: float, v: float, r: float) -> void:
	if key == my_author_key():
		return
	var uid := "%x%04x" % [int(Time.get_unix_time_from_system()), randi() % 0x10000]
	var entry := Stickers.clean_board_sticker([uid, sticker, u, v, r, key, nick, 1.0])
	if entry.is_empty():
		return
	# Не больше BOARD_PER_AUTHOR стикеров одного автора на этой доске (проверка у хозяина — она главная).
	if local.board.filter(func(item): return str(item[5]) == key).size() >= Stickers.BOARD_PER_AUTHOR:
		return
	local.board.append(entry)
	while local.board.size() > Stickers.BOARD_MAX:
		local.board.pop_front()
	notice.emit("%s наклеил(а) вам стикер «%s» на доску" % [nick, Stickers.title(sticker)])
	_local_changed()


func _owner_remove(key: String, uid: String) -> void:
	for i in local.board.size():
		var entry: Array = local.board[i]
		if str(entry[0]) == uid and str(entry[5]) == key:
			local.board.remove_at(i)
			_local_changed()
			return


# --- Публикация -----------------------------------------------------------------------

func _local_changed() -> void:
	Stickers.save_local(local)
	_pending = true
	changed.emit(my_peer())


func _process(delta: float) -> void:
	_clock += delta
	if _clock < 0.25:
		return
	_clock = 0.0
	var net := _net()
	if not _party():
		if not rooms.is_empty() or not _uploaded.is_empty():
			rooms.clear()
			_known.clear()
			_uploaded.clear()
			_wanted.clear()
			_poster_bytes.clear()
			_waiters.clear()
			_pulled.clear()
			_sent = {}
			changed.emit(0)
		return
	for entry: Variant in local.get("posters", []):
		if entry is Array and (entry as Array).size() == 3 and str(entry[2]) != "" and not _uploaded.has(str(entry[2])):
			_upload(str(entry[2]))
	if net.is_host():
		# Новым участникам — все известные снимки (свой тоже лежит в rooms[1]).
		for peer: Variant in net.members:
			if int(peer) == 1 or _known.has(peer):
				continue
			_known[peer] = true
			for owner: Variant in rooms:
				_rpc_room.rpc_id(int(peer), int(owner), rooms[owner])
	if _pending or local != _sent:
		_pending = false
		_sent = local.duplicate(true)
		if net.is_host():
			_store(1, _sent)
		elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_rpc_publish.rpc_id(1, _sent)


@rpc("any_peer", "reliable")
func _rpc_publish(snapshot: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _net().is_host() and not _member(sender).is_empty() and var_to_bytes(snapshot).size() <= 262144:
		_store(sender, Stickers.clean_public(snapshot))


func _store(peer: int, snapshot: Dictionary) -> void:
	if rooms.get(peer, {}) == snapshot:
		return
	rooms[peer] = snapshot.duplicate(true)
	changed.emit(peer)
	_rpc_room.rpc(peer, snapshot)


@rpc("authority", "reliable")
func _rpc_room(peer: int, snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		rooms.erase(peer)
	else:
		rooms[peer] = Stickers.clean_public(snapshot)
	changed.emit(peer)


func _on_peer_gone(peer: int) -> void:
	_known.erase(peer)
	if rooms.erase(peer):
		changed.emit(peer)
		if _net() != null and _net().is_host() and _party():
			_rpc_room.rpc(peer, {})
