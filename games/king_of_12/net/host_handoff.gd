extends RefCounted
const SELF := "res://games/king_of_12/net/host_handoff.gd"
## Передача партии новому хосту (07.11): хост ушёл — партия продолжается у преемника.
## Хост раз в несколько секунд (и при уходе) упаковывает всё состояние партии из Net (объекты правил
## любой игры, места, таймеры) в байты и шлёт преемнику; тот, став хостом, распаковывает и продолжает.
## Упаковка общая для всех игр: объекты скриптов — по пути скрипта + переменные (общие ссылки и циклы
## сохраняются), узлы — путём в дереве, ресурсы — путём, генераторы случайных чисел — seed/state,
## типизированные массивы и словари — с типом. Чего упаковать нельзя (Callable, безымянные ресурсы) — null.
## Проверка: tests/test_host_handoff.gd.

## Переменные Net, которые не относятся к партии (соединение, лобби, узлы, кеши, личное).
const NET_SKIP := [
	"public_rooms", "_room_pending", "_room_sent", "_room_known", "_room_clock",
	"last_disconnect", "_steam_transport_events", "_leaving",
	"steam", "steam_ok", "_steam_initialized", "_steam_refresh_clock", "steam_error",
	"my_name", "mode", "lobby_id", "members", "join_order", "last_join", "my_steam_id", "_avatars",
	"cg_transfer", "stickers", "player_stats", "_match_metrics", "host_tools",
	"_st_jev", "_st_checking", "lobby_view", "view", "_client_start_pending", "_client_expected_match",
	"_hosting_steam", "_host_steam_id", "_enet_successor", "_migrating", "steam_public_lobbies",
	"steam_lobbies_loading", "steam_lobbies_error", "_steam_lobby_refresh_again", "_steam_lobby_request",
	"_steam_lobby_source", "_netlog", "_handoff", "_handoff_clock", "_handoff_dirty", "_handoff_seq",
	"_handoff_parts", "_create_game",
]

## Личные свойства объектов, которые не передаются (Clocktower: свой токен возврата пишется в файл игрока).
const OBJ_SKIP := ["resume_token", "_resume_token"]

var _ids := {}  # объект -> номер (упаковка)
var _objs := {}  # номер -> объект (распаковка)
var lost := 0  # сколько значений пришлось заменить на null


## Все переменные партии из Net → сжатые байты.
static func pack_net(net: Node) -> PackedByteArray:
	var h: RefCounted = load(SELF).new()
	var vars := {}
	for p: Dictionary in net.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and not NET_SKIP.has(str(p.name)):
			vars[str(p.name)] = h._enc(net.get(p.name))
	var raw := var_to_bytes(vars)
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, raw.size())
	out.encode_u32(4, h.lost)
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


## Байты → переменные Net (словарь имя → значение, уже с живыми объектами).
static func unpack(bytes: PackedByteArray, tree: SceneTree) -> Dictionary:
	if bytes.size() < 8:
		return {}
	var size := bytes.decode_u32(0)
	var raw := bytes.slice(8).decompress(size, FileAccess.COMPRESSION_ZSTD)
	var vars: Variant = bytes_to_var(raw)
	if typeof(vars) != TYPE_DICTIONARY:
		return {}
	var h: RefCounted = load(SELF).new()
	h._tree = tree
	var out := {}
	for name: String in vars:
		out[name] = h._dec(vars[name])
	return out


## Записать распакованное в Net (типизированные переменные — через set).
static func apply_net(net: Node, vars: Dictionary) -> void:
	for name: String in vars:
		net.set(name, vars[name])


var _tree: SceneTree


func _enc(v: Variant) -> Variant:
	match typeof(v):
		TYPE_OBJECT:
			return _enc_obj(v)
		TYPE_ARRAY:
			var arr: Array = v
			var items := []
			items.resize(arr.size())
			for i in arr.size():
				items[i] = _enc(arr[i])
			if not arr.is_typed():
				return items
			var script: Script = arr.get_typed_script()
			return {"__a": items, "t": arr.get_typed_builtin(), "c": str(arr.get_typed_class_name()), "s": script.resource_path if script != null else ""}
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var pairs := []
			for k: Variant in d:
				pairs.append([_enc(k), _enc(d[k])])
			var out := {"__d": pairs}
			if d.is_typed():
				var ks: Script = d.get_typed_key_script()
				var vs: Script = d.get_typed_value_script()
				out["kt"] = [d.get_typed_key_builtin(), str(d.get_typed_key_class_name()), ks.resource_path if ks != null else ""]
				out["vt"] = [d.get_typed_value_builtin(), str(d.get_typed_value_class_name()), vs.resource_path if vs != null else ""]
			return out
		TYPE_CALLABLE:
			if (v as Callable).is_valid():
				lost += 1
			return {"__call": true}  # у нового хоста — пустой Callable (подмены для тестов и т. п.)
		TYPE_SIGNAL, TYPE_RID:
			lost += 1
			return null
	return v


func _enc_obj(o: Object) -> Variant:
	if o == null or not is_instance_valid(o):
		return null
	if o is Node:
		return {"__node": str((o as Node).get_path()) if (o as Node).is_inside_tree() else ""}
	if o is WeakRef:
		return {"__weak": _enc((o as WeakRef).get_ref())}
	if o is RandomNumberGenerator:
		var rng := o as RandomNumberGenerator
		return {"__rng": [rng.seed, rng.state]}
	if o is Resource and not (o is Script):
		var path := (o as Resource).resource_path
		if path != "" and not path.contains("::"):
			return {"__res": path}
	var script: Script = o.get_script()
	if o is Script:
		return {"__res": (o as Script).resource_path}
	if script == null or script.resource_path == "":
		lost += 1
		return null
	if _ids.has(o):
		return {"__ref": _ids[o]}
	var id := _ids.size()
	_ids[o] = id
	var vars := {}
	for p: Dictionary in o.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and not OBJ_SKIP.has(str(p.name)):
			vars[str(p.name)] = _enc(o.get(p.name))
	return {"__obj": id, "s": script.resource_path, "v": vars}


func _dec(v: Variant) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var out := []
			for x: Variant in v:
				out.append(_dec(x))
			return out
		TYPE_DICTIONARY:
			return _dec_dict(v)
	return v


func _dec_dict(d: Dictionary) -> Variant:
	if d.has("__d"):
		var out := {}
		if d.has("kt"):
			var kt: Array = d["kt"]
			var vt: Array = d["vt"]
			out = Dictionary({}, int(kt[0]), StringName(kt[1]), _script(str(kt[2])), int(vt[0]), StringName(vt[1]), _script(str(vt[2])))
		for pair: Array in d["__d"]:
			out[_dec(pair[0])] = _dec(pair[1])
		return out
	if d.has("__a"):
		var items := []
		for x: Variant in d["__a"]:
			items.append(_dec(x))
		return Array(items, int(d["t"]), StringName(d["c"]), _script(str(d["s"])))
	if d.has("__ref"):
		return _objs.get(int(d["__ref"]))
	if d.has("__obj"):
		var script: Script = _script(str(d["s"]))
		var o: Object = _make(script)
		_objs[int(d["__obj"])] = o
		if o == null:
			return null
		var vars: Dictionary = d["v"]
		for name: String in vars:
			o.set(name, _dec(vars[name]))
		return o
	if d.has("__node"):
		var path := str(d["__node"])
		return _tree.root.get_node_or_null(path) if path != "" and _tree != null else null
	if d.has("__rng"):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(d["__rng"][0])
		rng.state = int(d["__rng"][1])
		return rng
	if d.has("__weak"):
		var target: Variant = _dec(d["__weak"])
		return weakref(target) if target is Object else WeakRef.new()
	if d.has("__call"):
		return Callable()
	if d.has("__res"):
		return load(str(d["__res"]))
	return null


func _script(path: String) -> Script:
	return load(path) as Script if path != "" else null


## Новый экземпляр скрипта: _init с обязательными аргументами получает null — переменные тут же перезапишутся.
func _make(script: Script) -> Object:
	if script == null:
		return null
	var need := 0
	for m: Dictionary in script.get_script_method_list():
		if str(m.name) == "_init":
			need = (m.args as Array).size() - (m.default_args as Array).size()
			break
	var args := []
	args.resize(need)
	return script.callv("new", args)
