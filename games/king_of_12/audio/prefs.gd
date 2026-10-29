extends Node
## Автозагрузка Prefs: настройки игрока (громкость, экран) и локальная статистика партий.

signal changed

const SETTINGS := "user://settings.cfg"
const STATS := "user://stats.cfg"

var muted := false
var music_volume := 0.45
var sfx_volume := 0.8
var fullscreen := false  # старая настройка — теперь window_mode
## Экран: windowed — окно, borderless — полный экран в окне (без рамки, быстро переключается alt+tab),
## exclusive — эксклюзивный полный экран.
var window_mode := "windowed"
var resolution := "1280x720"  # размер окна в оконном режиме
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440"]
var _applied_res := ""  # какой размер окна уже ставили — чтобы не сбрасывать окно, растянутое мышью
var ui_scale := 1.0
var _render_resolution := ""  # только явно выбранная растровая поверхность fullscreen
var tutorial_seen := false
var graphics := 2  # качество графики: 0 — низкое, 1 — среднее, 2 — высокое
var show_fps := false
var vsync := true
var fps_limit := 60  # 0 — без ограничения
var theme_mode := "light"  # оформление светлых игр: light / dark / system
var perudo_coin_secret := false  # старая настройка — теперь coin_secrets["perudo"]
var coin_secrets := {}  # игра → включён ли секретный облик монетки (5 орлов подряд — переключает)
var chat_volume := 0.85  # голоса реплик и сообщений чата (поверх «Звуков игры»)

const FPS_LIMITS := [60, 120, 144, 0]

## Масштаб отрисовки 3D (FSR) по качеству: интерфейс всегда в полном разрешении.
const SCALE_3D := [0.67, 0.8, 1.0]

var _fps_layer: CanvasLayer
var _fps_label: Label

var _recorded := {}  # ключи уже записанных розыгрышей/партий


func _ready() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		muted = cfg.get_value("audio", "muted", muted)
		music_volume = cfg.get_value("audio", "music", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		ui_scale = 1.0  # устаревший масштаб больше не влияет на интерфейс
		tutorial_seen = cfg.get_value("game", "tutorial_seen", tutorial_seen)
		graphics = cfg.get_value("video", "graphics", graphics)
		show_fps = cfg.get_value("video", "show_fps", show_fps)
		vsync = cfg.get_value("video", "vsync", vsync)
		fps_limit = cfg.get_value("video", "fps_limit", fps_limit)
		theme_mode = cfg.get_value("video", "theme_mode", theme_mode)
		window_mode = cfg.get_value("video", "window_mode", "borderless" if fullscreen else "windowed")
		resolution = cfg.get_value("video", "resolution", resolution)
		_render_resolution = cfg.get_value("video", "render_resolution", "")
		chat_volume = cfg.get_value("audio", "chat", chat_volume)
		perudo_coin_secret = cfg.get_value("game", "perudo_coin_secret", perudo_coin_secret)
		coin_secrets = cfg.get_value("game", "coin_secrets", {"perudo": true} if perudo_coin_secret else {})
	# громкость — сразу, до того как меню включит музыку; окно и графика — после старта сцены
	_apply_audio()
	apply.call_deferred()


func _apply_audio() -> void:
	AudioServer.set_bus_mute(0, muted)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_volume, 0.0001)))


## Окно и графику трогаем, только если они правда поменялись: лишняя смена режима окна
## или вертикальной синхронизации в полноэкранном режиме у некоторых видеокарт сворачивает игру.
func apply() -> void:
	_apply_audio()
	if not DisplayServer.get_name().begins_with("headless"):
		_apply_window()
	ui_scale = 1.0
	get_tree().root.content_scale_factor = 1.0
	# графика: вертикальная синхронизация, потолок кадров (видеокарта не греется зря), масштаб 3D-сцены со сглаживанием FSR
	var vs := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != vs:
		DisplayServer.window_set_vsync_mode(vs)
	Engine.max_fps = fps_limit
	var root := get_tree().root
	var sc: float = SCALE_3D[clampi(graphics, 0, 2)]
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if sc < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = sc
	# сглаживание краёв 3D: высокое — MSAA 4x, среднее — 2x, низкое — дешёвый FXAA
	var q := clampi(graphics, 0, 2)
	root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	_sync_fps()
	changed.emit()


func _apply_window() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	var want: int = {"borderless": DisplayServer.WINDOW_MODE_FULLSCREEN, "exclusive": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN}.get(window_mode, DisplayServer.WINDOW_MODE_WINDOWED)
	fullscreen = window_mode != "windowed"
	var windowed := want == DisplayServer.WINDOW_MODE_WINDOWED
	if mode != want and not (windowed and mode == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(want)
		if windowed:
			_applied_res = ""  # вышли из полного экрана — вернуть выбранный размер окна
	if windowed and resolution != _applied_res and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		_applied_res = resolution
		var p := resolution.split("x")
		var scr := DisplayServer.window_get_current_screen()
		var area := DisplayServer.screen_get_usable_rect(scr)
		var sz := Vector2i(int(p[0]), int(p[1])).min(area.size - Vector2i(16, 48))
		DisplayServer.window_set_size(sz)
		DisplayServer.window_set_position(area.position + (area.size - sz) / 2)
	var root := get_tree().root
	var render_size := _resolution_size(_render_resolution)
	if not windowed and render_size != Vector2i.ZERO:
		# Fullscreen-окно остаётся размером с монитор; меняется настоящая
		# растровая поверхность игры, включая 2D, а не множитель UI.
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = render_size
	else:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_size = Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width", 1280),
			ProjectSettings.get_setting("display/window/size/viewport_height", 720))


func _resolution_size(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var parsed := Vector2i(int(parts[0]), int(parts[1]))
	return parsed if parsed.x > 0 and parsed.y > 0 else Vector2i.ZERO


## Фактическая растровая поверхность игры, а не сохранённый размер окна.
func current_resolution() -> Vector2i:
	if get_tree().root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		return DisplayServer.window_get_size()
	return get_tree().root.get_texture().get_size()


## Счётчик кадров в углу экрана (настройка «Показывать FPS»).
func _sync_fps() -> void:
	if show_fps and _fps_layer == null:
		_fps_layer = CanvasLayer.new()
		_fps_layer.layer = 100
		_fps_label = Label.new()
		_fps_label.position = Vector2(6, 4)
		_fps_label.add_theme_font_size_override("font_size", 14)
		_fps_label.add_theme_color_override("font_color", Color("7dff8a"))
		_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_fps_label.add_theme_constant_override("outline_size", 4)
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps_layer.add_child(_fps_label)
		add_child(_fps_layer)
	elif not show_fps and _fps_layer != null:
		_fps_layer.queue_free()
		_fps_layer = null
		_fps_label = null


func _process(_d: float) -> void:
	if _fps_label:
		_fps_label.text = "FPS %d · %.1f мс" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "chat", chat_volume)
	cfg.set_value("game", "coin_secrets", coin_secrets)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("game", "tutorial_seen", tutorial_seen)
	cfg.set_value("video", "graphics", graphics)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "theme_mode", theme_mode)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "render_resolution", _render_resolution)
	cfg.save(SETTINGS)


## Тёмная тема для игр на светлом фоне (Hues and Cues, Word Slam, Длина волны, Ready Set Bet).
func dark_theme() -> bool:
	if theme_mode == "system":
		return DisplayServer.is_dark_mode()
	return theme_mode == "dark"


func set_value(key: String, value) -> void:
	if key == "resolution":
		_applied_res = ""
		if window_mode != "windowed":
			_render_resolution = str(value)
		elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	set(key, value)
	save()
	apply()


# --- Статистика ----------------------------------------------------------------

## После каждого розыгрыша: что сыграл я, выиграл ли, значение кубика.
func record_trick(view: Dictionary) -> void:
	var trick: Dictionary = view.get("trick", {})
	if trick.is_empty():
		return
	var key := "t/%s/%s/%s" % [view.get("game_id", ""), view["round_no"], view["trick_no"]]
	if _recorded.has(key):
		return
	_recorded[key] = true
	var me: int = view["you"]
	var card: String = trick["played"][me] if me < trick["played"].size() else ""
	if card == "":
		return
	var cfg := _stats()
	var cards: Dictionary = cfg.get_value("me", "cards", {})
	cards[card] = int(cards.get(card, 0)) + 1
	cfg.set_value("me", "cards", cards)
	cfg.set_value("me", "tricks", int(cfg.get_value("me", "tricks", 0)) + 1)
	if trick["winner"] == me:
		cfg.set_value("me", "tricks_won", int(cfg.get_value("me", "tricks_won", 0)) + 1)
	var val: int = trick["values"][me]
	if val > int(cfg.get_value("me", "best_value", -999)):
		cfg.set_value("me", "best_value", val)
		cfg.set_value("me", "best_value_card", card)
	cfg.save(STATS)


## В конце партии: игры, победы и выигранные раунды каждого участника.
func record_game(view: Dictionary) -> void:
	var key := "g/%s" % view.get("game_id", "")
	if _recorded.has(key):
		return
	_recorded[key] = true
	var cfg := _stats()
	var players: Dictionary = cfg.get_value("players", "list", {})
	for s in view["players"].size():
		var nm: String = str(view["players"][s]["name"]).trim_suffix(" (бот)")
		var row: Dictionary = players.get(nm, {"games": 0, "wins": 0, "rounds": 0, "bot": false})
		row["games"] += 1
		row["rounds"] += view["under"][s].size()
		row["bot"] = nm.begins_with("Бот ")
		if view["winner"] == s:
			row["wins"] += 1
		players[nm] = row
	cfg.set_value("players", "list", players)
	cfg.set_value("me", "games", int(cfg.get_value("me", "games", 0)) + 1)
	cfg.save(STATS)


func stats() -> ConfigFile:
	return _stats()


func _stats() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(STATS)
	return cfg
