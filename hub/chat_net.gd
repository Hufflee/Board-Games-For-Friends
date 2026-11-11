extends Node
## Чат пати со вкладками (узел /root/Net/Chat, создаёт Net).
##
## Хранит разговоры между экранами: «Всем» (журнал Net), «Команда», личные с участниками пати.
## Всё идёт через хоста: он нумерует сообщения, пересылает личные только двум собеседникам,
## считает реакции и раздаёт картинки (по хэшу, кусками). Окно чата — games/king_of_12/ui/chat_panel.gd.
## Личные сообщения выключены, пока идёт партия «Крови на часовой башне» (там свой шёпот).

signal changed  # вкладки, непрочитанное, выбранная вкладка
signal entry_added(conv: String, entry: Dictionary)
signal reactions_changed(id: int)
signal image_ready(hash: String)
signal notice(text: String)

const EMOJI := ["👍", "👎", "😂", "😮", "😢", "😡", "🔥", "💖"]
const EMOJI_TIPS := ["Согласен", "Не согласен", "Смешно", "Ого", "Грустно", "Злюсь", "Огонь", "Нравится"]
const MAX_IMAGE_BYTES := 2 * 1024 * 1024
const IMAGE_SIDE := 1280
const IMAGE_ONLY := "🖼"  # текст сообщения, в котором только картинка
const CHUNK := 48000
const KEEP := 120  # сообщений в одном разговоре
const BLOBS := 24  # картинок в памяти
const TEXTURES := 10
const ASK_EVERY := 2500

const ChatGif := preload("res://hub/chat_gif.gd")
const WINDOW := 3  # кусков картинки в полёте
const STALL := 6000  # мс без новых кусков — загрузку начинаем заново
const PANEL_LAYER := 45

var convs: Dictionary = {}  # ключ → {key, peer, name, entries, unread, stamp, open, stale}
var current := "all"
var _view_frame := -10  # кадр, когда раскрытое окно чата последний раз отметилось
var reactions: Dictionary = {}  # id сообщения → {номер смайлика: [peer, ...]}

var _order := 0
var _team_game := ""
var _clock := 0.0
var _next_id := 1  # хост
var _audience: Dictionary = {}  # хост: id → кому видно сообщение ([] — всем)
var _blobs: Dictionary = {}  # хэш → байты картинки
var _blob_order: Array[String] = []
var _textures: Dictionary = {}  # хэш → {frames, delays}
var _texture_order: Array[String] = []
var _failed: Dictionary = {}  # хэш → true: картинку не удалось показать
var _decoding: Dictionary = {}
var _wanted: Dictionary = {}
var _offers: Dictionary = {}  # хост: хэш → приём картинки от автора
var _downloads: Dictionary = {}  # клиент: хэш → загрузка картинки с хоста
var _waiters: Dictionary = {}  # хост: хэш → кто ждёт картинку, которую автор ещё отдаёт
var _panel: Control


func _ready() -> void:
	name = "Chat"
	_ensure("all")
	_net().chat_received.connect(_on_net_chat)


func _net() -> Node:
	return get_parent()


func my_peer() -> int:
	var peer := multiplayer.multiplayer_peer
	return multiplayer.get_unique_id() if peer != null else 1


func _member(peer: int) -> Dictionary:
	var members: Dictionary = _net().members
	return members.get(peer, {})


# --- Разговоры -----------------------------------------------------------------------------

func _ensure(key: String) -> Dictionary:
	if not convs.has(key):
		convs[key] = {"key": key, "peer": int(key.trim_prefix("pm:")) if key.begins_with("pm:") else 0, "name": "",
			"entries": [], "unread": 0, "stamp": 0, "open": key == "all", "stale": false}
	return convs[key]


## Вкладки по порядку: «Всем», затем открытые — от самой свежей.
func tabs() -> Array[String]:
	var list: Array[String] = []
	for key: String in convs:
		if key == "all" or not bool(convs[key].open):
			continue
		if key == "team" and int(_net().chat_team()) < 0:
			continue
		list.append(key)
	list.sort_custom(func(a: String, b: String) -> bool: return int(convs[a].stamp) > int(convs[b].stamp))
	list.push_front("all")
	return list


func title_of(key: String) -> String:
	if key == "all":
		return "Всем"
	if key == "team":
		return "Команда"
	var conv: Dictionary = convs.get(key, {})
	var member := _member_view(int(conv.get("peer", 0)))
	if not member.is_empty() and not bool(conv.get("stale", false)):
		conv["name"] = str(member.get("name", ""))
	return str(conv.get("name", "Игрок"))


## Собеседник ещё в пати и ему можно писать.
func can_send(key: String) -> bool:
	if key == "all":
		return true
	if key == "team":
		return int(_net().chat_team()) >= 0
	var conv: Dictionary = convs.get(key, {})
	return pm_allowed() and not bool(conv.get("stale", false)) and not _member_view(int(conv.get("peer", 0))).is_empty()


## В партии «Крови на часовой башне» личные вкладки закрыты: там разговоры — часть игры.
func pm_allowed() -> bool:
	var net := _net()
	return not (bool(net.in_game) and str(net.party_game) == "blood_on_the_clocktower")


func _member_view(peer: int) -> Dictionary:
	if peer <= 0:
		return {}
	for member: Dictionary in _net().lobby_view.get("members", []):
		if int(member.get("peer", 0)) == peer and str(member.get("kind", "")) not in ["local", "bot"]:
			return member
	return {}


## Кому можно написать лично: [{peer, name, color}].
func pm_targets() -> Array:
	var list := []
	var me := my_peer()
	for member: Dictionary in _net().lobby_view.get("members", []):
		var peer := int(member.get("peer", 0))
		if peer > 0 and peer != me and str(member.get("kind", "")) not in ["local", "bot"]:
			list.append({"peer": peer, "name": str(member.get("name", "")), "color": int(member.get("color", 0))})
	return list


func open_conv(key: String) -> void:
	var conv := _ensure(key)
	if not bool(conv.open):
		conv.open = true
		_order += 1
		conv.stamp = _order
	select(key)


func open_pm(peer: int) -> void:
	if peer > 0 and peer != my_peer():
		open_conv("pm:%d" % peer)


func close_conv(key: String) -> void:
	if key == "all" or not convs.has(key):
		return
	convs[key].open = false
	convs[key].unread = 0
	if current == key:
		current = "all"
		mark_read("all")
	changed.emit()


func select(key: String) -> void:
	if not convs.has(key):
		return
	current = key
	mark_read(key)
	changed.emit()


func mark_read(key: String) -> void:
	if convs.has(key) and int(convs[key].unread) > 0:
		convs[key].unread = 0
		changed.emit()


## Раскрытое окно чата зовёт это каждый кадр: выбранная вкладка считается прочитанной.
func touch_view() -> void:
	_view_frame = Engine.get_process_frames()
	if int(convs[current].unread) > 0:
		mark_read(current)


func unread_total() -> int:
	var total := 0
	for key: String in convs:
		if bool(convs[key].open) or key == "all":
			total += int(convs[key].unread)
	return total


func find_entry(id: int) -> Dictionary:
	for key: String in convs:
		for entry: Dictionary in convs[key].entries:
			if int(entry.get("id", 0)) == id:
				return entry
	return {}


func _add(key: String, entry: Dictionary) -> void:
	var conv := _ensure(key)
	(conv.entries as Array).append(entry)
	if (conv.entries as Array).size() > KEEP:
		(conv.entries as Array).pop_front()
	var mine := int(entry.get("peer", 0)) == my_peer()
	if str(entry.get("kind", "")) != "system" or key != "all":
		_order += 1
		conv.stamp = _order
		conv.open = true
	var viewing := Engine.get_process_frames() - _view_frame <= 2
	if not mine and not (viewing and current == key):
		conv.unread = int(conv.unread) + 1
	entry_added.emit(key, entry)
	changed.emit()


func _on_net_chat(entry: Dictionary) -> void:
	if str(entry.get("scope", "all")) == "team":
		if not _net().chat_entry_visible(entry):
			return
		var game := str(entry.get("game_id", ""))
		if game != _team_game:
			_team_game = game
			_ensure("team").entries = []
		_add("team", entry)
	else:
		_add("all", entry)


func _process(delta: float) -> void:
	_clock += delta
	if _clock < 0.5:
		return
	_clock = 0.0
	var net := _net()
	if not net.in_session():
		if convs.size() > 1 or not (convs["all"].entries as Array).is_empty() or not _blobs.is_empty():
			_reset_all()
		return
	# после смены хоста номера участников новые: личные вкладки находят собеседника по нику
	for key: String in convs.keys():
		var conv: Dictionary = convs[key]
		if not bool(conv.get("stale", false)):
			continue
		for target: Dictionary in pm_targets():
			if str(target.name) == str(conv.name):
				_rekey(key, int(target.peer))
				break
	if current == "team" and int(net.chat_team()) < 0:
		select("all")


func _rekey(old_key: String, peer: int) -> void:
	var next_key := "pm:%d" % peer
	if convs.has(next_key) and next_key != old_key:
		return
	var conv: Dictionary = convs[old_key]
	convs.erase(old_key)
	conv.key = next_key
	conv.peer = peer
	conv.stale = false
	convs[next_key] = conv
	if current == old_key:
		current = next_key
	changed.emit()


func _reset_all() -> void:
	convs.clear()
	reactions.clear()
	_audience.clear()
	_blobs.clear()
	_blob_order.clear()
	_textures.clear()
	_texture_order.clear()
	_failed.clear()
	_wanted.clear()
	_offers.clear()
	_downloads.clear()
	_waiters.clear()
	_next_id = 1
	_order = 0
	current = "all"
	_ensure("all")
	changed.emit()


## Хост сменился: журналы остаются, но номера участников и права на реакции — заново.
func reset_party() -> void:
	var top := 0
	_audience.clear()
	for key: String in convs:
		var conv: Dictionary = convs[key]
		if key.begins_with("pm:"):
			conv.stale = true
		for entry: Dictionary in conv.entries:
			top = maxi(top, int(entry.get("id", 0)))
	_next_id = top + 1
	_wanted.clear()
	_offers.clear()
	_downloads.clear()
	_waiters.clear()
	changed.emit()


# --- Отправка ------------------------------------------------------------------------------

## conv — ключ вкладки; kind: "chat" или "emote"; extra: {"reply": {id, name, text}, "image": хэш}.
func send(conv: String, text: String, kind: String = "chat", extra: Dictionary = {}) -> void:
	var net := _net()
	text = text.strip_edges().left(200)
	if not net.in_session() or (text.is_empty() and not extra.has("image")):
		return
	if not can_send(conv):
		notice.emit("Сюда сейчас написать нельзя")
		return
	var scope := "pm" if conv.begins_with("pm:") else conv
	var to := int(convs[conv].peer) if scope == "pm" else 0
	if net.is_host():
		_host_send(my_peer(), scope, to, text, kind, extra)
	else:
		_rpc_send_up.rpc_id(1, scope, to, text, kind, extra)


@rpc("any_peer", "reliable")
func _rpc_send_up(scope: String, to: int, text: String, kind: String, extra: Dictionary) -> void:
	if _net().is_host():
		_host_send(multiplayer.get_remote_sender_id(), scope, to, text, kind, extra)


func _host_send(sender: int, scope: String, to: int, text: String, kind: String, extra: Dictionary) -> void:
	var net := _net()
	if kind not in ["chat", "emote"] or _member(sender).is_empty():
		return
	match scope:
		"all":
			net._host_chat(sender, text, kind, extra)
		"team":
			net._host_chat(sender, text, "team_emote" if kind == "emote" else "team", extra)
		"pm":
			_host_pm(sender, to, text, extra)


func _host_pm(sender: int, to: int, text: String, extra: Dictionary) -> void:
	var net := _net()
	var clean := clean_extra(extra)
	text = text.strip_edges().left(200)
	if text.is_empty() and clean.has("image"):
		text = IMAGE_ONLY
	if sender == to or text.is_empty() or _member(to).is_empty() or not pm_allowed():
		return
	var author := _member(sender)
	var entry := {
		"name": str(author.get("name", "?")),
		"color": net.PLAYER_COLORS[int(author.get("color", 0))],
		"seat": -1,
		"peer": sender,
		"to": to,
		"text": text,
		"kind": "chat",
		"scope": "pm",
		"voice": net._voice_of(sender),
	}
	entry.merge(clean)
	stamp(entry, [sender, to])
	for peer: int in [sender, to]:
		if peer == my_peer():
			_apply_pm(entry)
		else:
			_rpc_pm_down.rpc_id(peer, entry)


@rpc("authority", "reliable")
func _rpc_pm_down(entry: Dictionary) -> void:
	_apply_pm(entry)


func _apply_pm(entry: Dictionary) -> void:
	var me := my_peer()
	var other := int(entry.get("to", 0)) if int(entry.get("peer", 0)) == me else int(entry.get("peer", 0))
	if other <= 0:
		return
	var key := "pm:%d" % other
	var conv := _ensure(key)
	if int(entry.get("peer", 0)) != me:
		conv.name = str(entry.get("name", conv.name))
	_add(key, entry)
	if int(entry.get("peer", 0)) == me:
		select(key)


## Хост: номер сообщения и список тех, кто его видит (для реакций). audience [] — видят все.
func stamp(entry: Dictionary, audience: Array) -> void:
	if entry.has("id"):
		return
	entry["id"] = _next_id
	_audience[_next_id] = audience
	_next_id += 1
	if _audience.size() > 600:
		_audience.erase(_audience.keys()[0])


## Хост: проверенные дополнения к сообщению — цитата ответа и картинка.
func clean_extra(extra: Dictionary) -> Dictionary:
	var out := {}
	var reply: Variant = extra.get("reply")
	if reply is Dictionary:
		out["reply"] = {
			"id": int((reply as Dictionary).get("id", 0)),
			"name": str((reply as Dictionary).get("name", "")).left(40),
			"text": str((reply as Dictionary).get("text", "")).left(90),
		}
	var image := str(extra.get("image", ""))
	if image.length() == 64 and image.is_valid_hex_number(false) and (_blobs.has(image) or _offers.has(image)):
		out["image"] = image
	return out


# --- Реакции -------------------------------------------------------------------------------

func react(id: int, emoji: int) -> void:
	if id <= 0 or emoji < 0 or emoji >= EMOJI.size():
		return
	if _net().is_host():
		_host_react(my_peer(), id, emoji)
	else:
		_rpc_react_up.rpc_id(1, id, emoji)


@rpc("any_peer", "reliable")
func _rpc_react_up(id: int, emoji: int) -> void:
	if _net().is_host():
		_host_react(multiplayer.get_remote_sender_id(), id, emoji)


func _host_react(sender: int, id: int, emoji: int) -> void:
	if not _audience.has(id) or emoji < 0 or emoji >= EMOJI.size() or _member(sender).is_empty():
		return
	var audience: Array = _audience[id]
	if not audience.is_empty() and not audience.has(sender):
		return
	var map: Dictionary = reactions.get(id, {}).duplicate(true)
	var who: Array = map.get(emoji, [])
	if who.has(sender):
		who.erase(sender)
	else:
		who.append(sender)
	if who.is_empty():
		map.erase(emoji)
	else:
		map[emoji] = who
	var targets: Array = audience if not audience.is_empty() else _net().members.keys()
	for peer: Variant in targets:
		if int(peer) == my_peer():
			_apply_react(id, map)
		elif not _member(int(peer)).is_empty():
			_rpc_react_down.rpc_id(int(peer), id, map)


@rpc("authority", "reliable")
func _rpc_react_down(id: int, map: Dictionary) -> void:
	_apply_react(id, map)


func _apply_react(id: int, map: Dictionary) -> void:
	if map.is_empty():
		reactions.erase(id)
	else:
		reactions[id] = map
	if reactions.size() > 400:
		reactions.erase(reactions.keys()[0])
	reactions_changed.emit(id)


# --- Картинки ------------------------------------------------------------------------------
# Картинка едет кусками «по запросу»: получатель сам просит следующий кусок, когда пришёл предыдущий
# (в полёте не больше WINDOW кусков). Раньше все куски уходили разом и не помещались в очередь
# отправки Steam — крупные GIF у игроков так и не появлялись.

static func is_gif(bytes: PackedByteArray) -> bool:
	return ChatGif.matches(bytes)


static func _sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func _load_image(bytes: PackedByteArray) -> Image:
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes.size() < 12:
		return null
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xff and bytes[1] == 0xd8:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = image.load_webp_from_buffer(bytes)
	elif bytes[0] == 0x42 and bytes[1] == 0x4d:
		error = image.load_bmp_from_buffer(bytes)
	return image if error == OK and not image.is_empty() else null


## Файл с диска → байты для отправки (GIF как есть, остальное ужимается). Пусто — не подошёл.
func prepare_file(path: String) -> PackedByteArray:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		notice.emit("Не удалось прочитать файл")
		return PackedByteArray()
	if is_gif(bytes):
		if bytes.size() > MAX_IMAGE_BYTES:
			notice.emit("GIF больше 2 МБ — такой не отправить")
			return PackedByteArray()
		if bytes.decode_u16(6) > ChatGif.CANVAS_SIDE or bytes.decode_u16(8) > ChatGif.CANVAS_SIDE:
			notice.emit("GIF слишком большой по размеру: сторона до %d px" % ChatGif.CANVAS_SIDE)
			return PackedByteArray()
		return bytes
	var image := _load_image(bytes)
	if image == null:
		notice.emit("Подойдут PNG, JPG, WEBP, BMP и GIF")
		return PackedByteArray()
	return prepare_image(image)


func prepare_image(image: Image) -> PackedByteArray:
	if image == null or image.is_empty():
		return PackedByteArray()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8 if image.detect_alpha() != Image.ALPHA_NONE else Image.FORMAT_RGB8)
	var longest := maxi(image.get_width(), image.get_height())
	if longest > IMAGE_SIDE:
		var ratio := float(IMAGE_SIDE) / longest
		image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	var bytes := image.save_webp_to_buffer(true, 0.86)
	if bytes.size() > MAX_IMAGE_BYTES:
		bytes = image.save_webp_to_buffer(true, 0.6)
	if bytes.size() > MAX_IMAGE_BYTES:
		notice.emit("Картинка слишком тяжёлая даже после сжатия")
		return PackedByteArray()
	return bytes


static func _chunks(size: int) -> int:
	return ceili(float(size) / CHUNK)


static func _slice(bytes: PackedByteArray, index: int) -> PackedByteArray:
	return bytes.slice(index * CHUNK, mini(bytes.size(), (index + 1) * CHUNK))


## Запомнить картинку и предложить её хосту (он сам заберёт её по кускам). Возвращает хэш для сообщения.
func attach(bytes: PackedByteArray) -> String:
	if bytes.is_empty() or bytes.size() > MAX_IMAGE_BYTES:
		return ""
	var hash := _sha(bytes)
	_keep_blob(hash, bytes)
	if not _net().is_host():
		_rpc_blob_offer.rpc_id(1, hash, bytes.size())
	return hash


func _keep_blob(hash: String, bytes: PackedByteArray) -> void:
	_blob_order.erase(hash)
	_blob_order.append(hash)
	_blobs[hash] = bytes
	while _blob_order.size() > BLOBS:
		_blobs.erase(_blob_order.pop_front())


## Сборка по кускам: transfer = {size, count, parts, next, stamp}. Возвращает готовые байты или пусто.
func _take_part(transfer: Dictionary, index: int, chunk: PackedByteArray) -> PackedByteArray:
	var count := int(transfer.count)
	if index < 0 or index >= count or chunk.size() > CHUNK or chunk.is_empty():
		return PackedByteArray()
	transfer.parts[index] = chunk
	transfer.stamp = Time.get_ticks_msec()
	if (transfer.parts as Dictionary).size() < count:
		return PackedByteArray()
	var bytes := PackedByteArray()
	for i in count:
		bytes.append_array(transfer.parts[i])
	return bytes


static func _new_transfer(size: int) -> Dictionary:
	return {"size": size, "count": _chunks(size), "parts": {}, "next": 0, "stamp": Time.get_ticks_msec()}


@rpc("any_peer", "reliable")
func _rpc_blob_offer(hash: String, size: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _net().is_host() or _member(sender).is_empty() or hash.length() != 64 or size <= 0 or size > MAX_IMAGE_BYTES:
		return
	if _blobs.has(hash) or _offers.has(hash):
		return
	var transfer := _new_transfer(size)
	transfer["peer"] = sender
	_offers[hash] = transfer
	for i in mini(WINDOW, int(transfer.count)):
		transfer.next = i + 1
		_rpc_blob_pull.rpc_id(sender, hash, i)


## Хост просит у автора кусок его картинки.
@rpc("authority", "reliable")
func _rpc_blob_pull(hash: String, index: int) -> void:
	if _blobs.has(hash) and index >= 0 and index < _chunks((_blobs[hash] as PackedByteArray).size()):
		_rpc_blob_part.rpc_id(1, hash, index, _slice(_blobs[hash], index))


@rpc("any_peer", "reliable")
func _rpc_blob_part(hash: String, index: int, chunk: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _net().is_host() or not _offers.has(hash):
		return
	var transfer: Dictionary = _offers[hash]
	if int(transfer.peer) != sender:
		return
	var bytes := _take_part(transfer, index, chunk)
	if bytes.is_empty():
		if int(transfer.next) < int(transfer.count):
			transfer.next = int(transfer.next) + 1
			_rpc_blob_pull.rpc_id(sender, hash, int(transfer.next) - 1)
		return
	_offers.erase(hash)
	if bytes.size() != int(transfer.size) or _sha(bytes) != hash:
		return
	_keep_blob(hash, bytes)
	for waiter: Variant in _waiters.get(hash, []):
		if not _member(int(waiter)).is_empty():
			_rpc_blob_ready.rpc_id(int(waiter), hash, bytes.size())
	_waiters.erase(hash)
	image_ready.emit(hash)


@rpc("any_peer", "reliable")
func _rpc_blob_want(hash: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _net().is_host() or _member(sender).is_empty():
		return
	if _blobs.has(hash):
		_rpc_blob_ready.rpc_id(sender, hash, (_blobs[hash] as PackedByteArray).size())
	elif _offers.has(hash):
		var list: Array = _waiters.get(hash, [])
		if not list.has(sender):
			list.append(sender)
		_waiters[hash] = list


## Хост: картинка есть, можно забирать.
@rpc("authority", "reliable")
func _rpc_blob_ready(hash: String, size: int) -> void:
	if _blobs.has(hash) or size <= 0 or size > MAX_IMAGE_BYTES:
		return
	var transfer := _new_transfer(size)
	_downloads[hash] = transfer
	for i in mini(WINDOW, int(transfer.count)):
		transfer.next = i + 1
		_rpc_blob_get.rpc_id(1, hash, i)


@rpc("any_peer", "reliable")
func _rpc_blob_get(hash: String, index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _net().is_host() or _member(sender).is_empty() or not _blobs.has(hash):
		return
	if index >= 0 and index < _chunks((_blobs[hash] as PackedByteArray).size()):
		_rpc_blob_chunk.rpc_id(sender, hash, index, _slice(_blobs[hash], index))


@rpc("authority", "reliable")
func _rpc_blob_chunk(hash: String, index: int, chunk: PackedByteArray) -> void:
	if not _downloads.has(hash):
		return
	var transfer: Dictionary = _downloads[hash]
	var bytes := _take_part(transfer, index, chunk)
	if bytes.is_empty():
		if int(transfer.next) < int(transfer.count):
			transfer.next = int(transfer.next) + 1
			_rpc_blob_get.rpc_id(1, hash, int(transfer.next) - 1)
		return
	_downloads.erase(hash)
	if bytes.size() != int(transfer.size) or _sha(bytes) != hash:
		return
	_keep_blob(hash, bytes)
	_wanted.erase(hash)
	_decode(hash)


## Кадры картинки сообщения: {"frames": [Texture2D, ...], "delays": [...]}; пусто — ещё едет или
## разбирается (придёт image_ready). Пока картинки нет, окно чата зовёт это раз в пару секунд.
func image_frames(hash: String) -> Dictionary:
	if _textures.has(hash):
		return _textures[hash]
	if _failed.has(hash) or _decoding.has(hash):
		return {}
	if _blobs.has(hash):
		_decode(hash)
		return _textures.get(hash, {})
	if not _net().is_host() and _net().in_session():
		var now := Time.get_ticks_msec()
		if _downloads.has(hash):
			if now - int(_downloads[hash].stamp) < STALL:
				return {}
			_downloads.erase(hash)  # загрузка встала — начинаем заново
		if now - int(_wanted.get(hash, -ASK_EVERY)) >= ASK_EVERY:
			_wanted[hash] = now
			_rpc_blob_want.rpc_id(1, hash)
	return {}


func image_failed(hash: String) -> bool:
	return _failed.has(hash)


func _decode(hash: String) -> void:
	if _textures.has(hash) or _decoding.has(hash) or not _blobs.has(hash):
		return
	var bytes: PackedByteArray = _blobs[hash]
	if is_gif(bytes):
		# гифку разбираем в фоне: покадровая распаковка на GDScript занимает заметное время
		_decoding[hash] = true
		WorkerThreadPool.add_task(_decode_gif.bind(hash, bytes))
		return
	var image := _load_image(bytes)
	if image == null:
		_decoded(hash, {})
		return
	var images: Array[Image] = [image]
	_decoded(hash, {"images": images, "delays": PackedFloat32Array([1.0])})


func _decode_gif(hash: String, bytes: PackedByteArray) -> void:
	_decoded.call_deferred(hash, ChatGif.frames(bytes))


## Главный поток: из картинок — текстуры.
func _decoded(hash: String, data: Dictionary) -> void:
	_decoding.erase(hash)
	var images: Array = data.get("images", [])
	if images.is_empty():
		_failed[hash] = true
	else:
		var frames: Array[Texture2D] = []
		for image: Image in images:
			frames.append(ImageTexture.create_from_image(image))
		_texture_order.erase(hash)
		_texture_order.append(hash)
		_textures[hash] = {"frames": frames, "delays": data.get("delays", PackedFloat32Array())}
		while _texture_order.size() > TEXTURES:
			_textures.erase(_texture_order.pop_front())
	image_ready.emit(hash)


# --- Окно «Общение» ------------------------------------------------------------------------

## Одно окно на всю игру (hub/comms_panel.gd): живёт в своём слое поверх любого экрана.
func panel() -> Control:
	if is_instance_valid(_panel):
		return _panel
	var layer := CanvasLayer.new()
	layer.layer = PANEL_LAYER
	layer.name = "CommsLayer"
	layer.add_to_group("pause_allowed")
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_panel = load("res://hub/comms_panel.gd").new()
	root.add_child(_panel)
	get_tree().root.add_child.call_deferred(layer)
	return _panel
