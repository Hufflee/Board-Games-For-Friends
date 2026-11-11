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
const ASK_EVERY := 4000

const PosterGif := preload("res://hub/poster_gif.gd")

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
var _textures: Dictionary = {}  # хэш → Texture2D или SpriteFrames
var _texture_order: Array[String] = []
var _failed: Dictionary = {}  # хэш → true: картинку не удалось показать
var _decoding: Dictionary = {}
var _wanted: Dictionary = {}
var _incoming: Dictionary = {}


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
	_incoming.clear()
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
	_incoming.clear()
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
	if image.length() == 64 and image.is_valid_hex_number(false) and _blobs.has(image):
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

static func is_gif(bytes: PackedByteArray) -> bool:
	return PosterGif.matches(bytes)


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
		var width := bytes.decode_u16(6)
		var height := bytes.decode_u16(8)
		if width > PosterGif.MAX_SIDE or height > PosterGif.MAX_SIDE:
			notice.emit("GIF слишком большой по размеру: сторона до %d px" % PosterGif.MAX_SIDE)
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


## Запомнить картинку и отдать её хосту. Возвращает хэш для сообщения.
func attach(bytes: PackedByteArray) -> String:
	if bytes.is_empty() or bytes.size() > MAX_IMAGE_BYTES:
		return ""
	var hash := _sha(bytes)
	_keep_blob(hash, bytes)
	if not _net().is_host():
		var count := ceili(float(bytes.size()) / CHUNK)
		for i in count:
			_rpc_blob_up.rpc_id(1, hash, i, count, bytes.slice(i * CHUNK, mini(bytes.size(), (i + 1) * CHUNK)))
	return hash


func _keep_blob(hash: String, bytes: PackedByteArray) -> void:
	_blob_order.erase(hash)
	_blob_order.append(hash)
	_blobs[hash] = bytes
	while _blob_order.size() > BLOBS:
		_blobs.erase(_blob_order.pop_front())


func _collect(key: String, index: int, count: int, chunk: PackedByteArray) -> PackedByteArray:
	if count < 1 or count > ceili(float(MAX_IMAGE_BYTES) / CHUNK) + 1 or index < 0 or index >= count or chunk.size() > CHUNK:
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
func _rpc_blob_up(hash: String, index: int, count: int, chunk: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _net().is_host() or _member(sender).is_empty() or hash.length() != 64:
		return
	var bytes := _collect("up:%d:%s" % [sender, hash], index, count, chunk)
	if bytes.is_empty() or bytes.size() > MAX_IMAGE_BYTES or _sha(bytes) != hash:
		return
	_keep_blob(hash, bytes)


@rpc("any_peer", "reliable")
func _rpc_blob_want(hash: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _net().is_host() or _member(sender).is_empty() or not _blobs.has(hash):
		return
	var bytes: PackedByteArray = _blobs[hash]
	var count := ceili(float(bytes.size()) / CHUNK)
	for i in count:
		_rpc_blob_down.rpc_id(sender, hash, i, count, bytes.slice(i * CHUNK, mini(bytes.size(), (i + 1) * CHUNK)))


@rpc("authority", "reliable")
func _rpc_blob_down(hash: String, index: int, count: int, chunk: PackedByteArray) -> void:
	var bytes := _collect("down:" + hash, index, count, chunk)
	if bytes.is_empty() or bytes.size() > MAX_IMAGE_BYTES or _sha(bytes) != hash:
		return
	_keep_blob(hash, bytes)
	_wanted.erase(hash)
	_decode(hash)


## Картинка сообщения: Texture2D, SpriteFrames (гифка) или null — ещё едет (придёт image_ready).
func image_texture(hash: String) -> Resource:
	if _textures.has(hash):
		return _textures[hash]
	if _failed.has(hash) or _decoding.has(hash):
		return null
	if _blobs.has(hash):
		_decode(hash)
		return _textures.get(hash)
	if not _net().is_host() and _net().in_session():
		var now := Time.get_ticks_msec()
		if now - int(_wanted.get(hash, -ASK_EVERY)) >= ASK_EVERY:
			_wanted[hash] = now
			_rpc_blob_want.rpc_id(1, hash)
	return null


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
		_decoded(hash, null)
		return
	image.generate_mipmaps()
	_decoded(hash, ImageTexture.create_from_image(image))


func _decode_gif(hash: String, bytes: PackedByteArray) -> void:
	var texture: Resource = PosterGif.texture(bytes)
	_decoded.call_deferred(hash, texture)


func _decoded(hash: String, texture: Resource) -> void:
	_decoding.erase(hash)
	if texture == null:
		_failed[hash] = true
	else:
		_texture_order.erase(hash)
		_texture_order.append(hash)
		_textures[hash] = texture
		while _texture_order.size() > TEXTURES:
			_textures.erase(_texture_order.pop_front())
	image_ready.emit(hash)
