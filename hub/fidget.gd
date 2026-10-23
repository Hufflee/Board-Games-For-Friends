class_name Fidget
extends Control
## Антистресс-монетка: её можно схватить и швырнуть (летит с трением, отскакивает от краёв экрана,
## схватил за край — закрутится), а щелчок подбрасывает её на месте: орёл или решка.
## Ничего не делает в игре — просто занять руки. Есть во всех играх (её создаёт PauseLayer).
## Вид — под игру (hub/art/coins, GAME_COINS): у части игр есть вариант для тёмной темы (_dark) и секретный (_secret).
## Смена темы — монетка сама подпрыгивает и в полёте, когда стоит ребром (картинки почти не видно), меняет облик.
## Секрет: 5 орлов подряд — на пятом подбросе облик так же в полёте меняется на секретный (и обратно), запоминается в Prefs.coin_secrets.

const R := 24.0  # радиус монеты
const FRICTION := 1.6  # затухание скорости в секунду
const BOUNCE := 0.62  # сколько скорости остаётся после удара о край
const MAX_SPEED := 3000.0

static var saved_pos := Vector2(-1, -1)
static var _scene_key := ""  # в какой игре монетка лежит: сцену перезагрузили (смена темы) — остаётся на месте
static var _was_docked := true
## Секрет: орлом вверх 5 раз подряд — монетка меняет облик на секретный (и обратно).
const SECRET_STREAK := 5
static var _heads := 0
static var _last_style := ""  # облик до перезагрузки сцены (смена темы) — новая монетка начинает в нём и меняется в полёте
var _pending := ""  # облик, в который монетка превратится в полёте, когда встанет ребром
var _pending_secret := false  # смена — из-за секрета (на приземлении — звук и «подпрыгивание»)
## Свои звуки монеты (hub/audio/coin, CC-BY — см. LICENSE.txt рядом): звон, падение; стук о край — bounce.wav (синтез).
const SND := "res://hub/audio/coin/"
var _snd: AudioStreamPlayer
var _bounce: AudioStreamPlayer  # стук о край экрана — отдельно, чтобы не обрывать звон
const VOLUME := 0.85  # все звуки монетки — на 15% тише
var _rope := 0.0  # от точки хвата до центра монеты: точка хвата — ось вращения
var _rot0 := 0.0
var _dir0 := 0.0
var _rot_samples: Array = []  # [время, угол] — скорость вращения при отпускании
const COINS := "res://hub/art/coins/"
## Монеты-картинки: [орёл, решка]. Остальные стили рисуются кодом.
const TEXTURES := {
	"doubloon": ["res://hub/art/coins/doubloon_front.png", "res://hub/art/coins/doubloon_back.png"],
	"doubloon_gold": ["res://hub/art/coins/doubloon_old_front.png", "res://hub/art/coins/doubloon_old_back.png"],  # секрет «Перудо»
	"gold": ["res://games/brodilka/art/cards/coin_crown.png", "res://games/brodilka/art/cards/coin_10.png"],
	"silver": ["res://hub/art/coins/gloom_front.png", "res://hub/art/coins/gloom_back.png"],
	"holo": ["res://hub/art/coins/wave_front.png", "res://hub/art/coins/wave_back.png"],  # «Длина волны»: синяя, мозг
	"hues": ["res://hub/art/coins/hues_front.png", "res://hub/art/coins/hues_back.png"],  # Hues and Cues: клякса
	"gold_dark": ["res://games/brodilka/art/cards/coin_crown.png", "res://games/brodilka/art/cards/coin_10.png"],
	# Монеты остальных игр (ComfyUI по образцу монет Перудо/Бродилки/Gloom). _dark — для тёмной темы,
	# _secret — секретный облик (переключатель появится позже, как у «Перудо»).
	"king_of_12": [COINS + "king_of_12_front.png", COINS + "king_of_12_back.png"],
	"king_of_12_secret": [COINS + "king_of_12_secret_front.png", COINS + "king_of_12_secret_back.png"],
	"dangerous_words": [COINS + "dangerous_words_front.png", COINS + "dangerous_words_back.png"],
	"dangerous_words_secret": [COINS + "dangerous_words_secret_front.png", COINS + "dangerous_words_secret_back.png"],
	"ready_set_bet": [COINS + "ready_set_bet_front.png", COINS + "ready_set_bet_back.png"],
	"ready_set_bet_secret": [COINS + "ready_set_bet_secret_front.png", COINS + "ready_set_bet_secret_back.png"],
	"ready_set_bet_dark": [COINS + "ready_set_bet_dark_front.png", COINS + "ready_set_bet_dark_back.png"],
	"ready_set_bet_dark_secret": [COINS + "ready_set_bet_dark_secret_front.png", COINS + "ready_set_bet_dark_secret_back.png"],
	"word_slam": [COINS + "word_slam_front.png", COINS + "word_slam_back.png"],
	"word_slam_secret": [COINS + "word_slam_secret_front.png", COINS + "word_slam_secret_back.png"],
	"word_slam_dark": [COINS + "word_slam_dark_front.png", COINS + "word_slam_dark_back.png"],
	"word_slam_dark_secret": [COINS + "word_slam_dark_secret_front.png", COINS + "word_slam_dark_secret_back.png"],
	"wavelength": [COINS + "wavelength_front.png", COINS + "wavelength_back.png"],
	"wavelength_secret": [COINS + "wavelength_secret_front.png", COINS + "wavelength_secret_back.png"],
	"wavelength_dark": [COINS + "wavelength_dark_front.png", COINS + "wavelength_dark_back.png"],
	"wavelength_dark_secret": [COINS + "wavelength_dark_secret_front.png", COINS + "wavelength_dark_secret_back.png"],
	"tip_top": [COINS + "tip_top_front.png", COINS + "tip_top_back.png"],
	"tip_top_secret": [COINS + "tip_top_secret_front.png", COINS + "tip_top_secret_back.png"],
	"tip_top_18": [COINS + "tip_top_18_front.png", COINS + "tip_top_18_back.png"],
	"tip_top_18_secret": [COINS + "tip_top_18_secret_front.png", COINS + "tip_top_18_secret_back.png"],
	"not_a_hat": [COINS + "not_a_hat_front.png", COINS + "not_a_hat_back.png"],
	"not_a_hat_secret": [COINS + "not_a_hat_secret_front.png", COINS + "not_a_hat_secret_back.png"],
}
## Игры со своей монетой (кроме Перудо/Бродилки/Gloom/Hues) и есть ли у неё вариант для тёмной темы.
## Порядок важен: tip_top_18 раньше tip_top.
const GAME_COINS := [["tip_top_18", false], ["tip_top", false], ["king_of_12", false], ["dangerous_words", false],
	["ready_set_bet", true], ["word_slam", true], ["wavelength", true], ["not_a_hat", false]]
static var _tex_cache := {}

var _vel := Vector2.ZERO
var _spin := 0.0  # вращение в плоскости экрана, рад/с
var _flip := 0.0  # переворот монеты (cos > 0 — орёл)
var _flip_speed := 0.0
var _lift := 0.0  # высота подброса: монета «приближается» (крупнее и тень дальше)
var _toss_t := -1.0  # время подброса (-1 — не в воздухе)
var _toss_target := 0.0  # на каком перевороте приземлится
var _holding := false
var _grab := Vector2.ZERO  # где схватили (от центра)
var _press_at := Vector2.ZERO
var _moved := false
var _samples: Array = []  # [время, позиция] — скорость броска по последним движениям
var _style := "neon"


func _ready() -> void:
	size = Vector2(R * 2 + 8, R * 2 + 8)
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Монетка: щёлкни — подбросить, схвати и брось — полетит"
	get_viewport().size_changed.connect(_keep_inside)
	_snd = AudioStreamPlayer.new()
	_snd.bus = "SFX"
	add_child(_snd)
	_bounce = AudioStreamPlayer.new()
	_bounce.bus = "SFX"
	_bounce.stream = load(SND + "bounce.wav")
	add_child(_bounce)
	visibility_changed.connect(func(): _refresh_style(false))
	Prefs.changed.connect(func(): _refresh_style(true))
	if _scene_key != "" and get_tree().current_scene and get_tree().current_scene.scene_file_path == _scene_key and _last_style != "":
		_style = _last_style  # та же игра перезагрузилась (смена темы): начинаем в старом облике
		_refresh_style.call_deferred(true)
	else:
		_refresh_style.call_deferred(false)  # монетка создаётся уже видимой — вид по игре выбираем сразу
	visibility_changed.connect(func():
		if visible and saved_pos.x < 0:
			_reset_pos.call_deferred())
	# новая игра (монетка создаётся заново в каждой сцене) — монетка начинает в своём гнезде;
	# та же игра (сцену перезагрузили при смене темы) — лежит там же, где лежала
	var sc := get_tree().current_scene
	var key := sc.scene_file_path if sc else ""
	if key != _scene_key or _was_docked:
		_scene_key = key
		saved_pos = Vector2(-1, -1)
	if saved_pos.x >= 0.0:
		position = saved_pos
	else:
		modulate.a = 0.0  # пока гнездо не встало на место — не видна (иначе мелькает в углу)
		_reset_pos.call_deferred()


## Ушли в хаб — следующая игра начнёт с монеткой в гнезде.
static func forget() -> void:
	_scene_key = ""
	saved_pos = Vector2(-1, -1)


func _reset_pos() -> void:
	var vs := get_viewport_rect().size
	var bar := get_tree().get_first_node_in_group("top_bar")
	if bar != null and bar.get("coin_dock") != null:
		var dock: Control = bar.coin_dock  # у стола с верхней полосой — в гнезде слева от часов
		# полоса раскладывается не сразу — ждём пару кадров, пока гнездо встанет на место
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(dock) and saved_pos.x < 0:
			position = dock.global_position + (dock.size - size) * 0.5
			_in_dock = true
		modulate.a = 1.0
		return
	position = Vector2(14, vs.y * 0.5 - size.y * 0.5)
	modulate.a = 1.0


func _keep_inside() -> void:
	var vs := get_viewport_rect().size
	position = position.clamp(Vector2.ZERO, vs - size)


## Вид монеты — по текущей игре, теме и секрету.
func _style_for() -> String:
	var g: String = Net.party_game
	if get_tree().current_scene:
		g += " " + get_tree().current_scene.scene_file_path
	g = g.replace("main18", "tip_top_18")  # «Тип Топ 18+» офлайн узнаём по сцене
	var key := _game_key()
	var secret: bool = Prefs.coin_secrets.get(key, false)
	if key == "perudo":
		return "doubloon_gold" if secret else "doubloon"
	for gc in GAME_COINS:
		if gc[0] == key:
			var st: String = key + ("_dark" if gc[1] and Prefs.dark_theme() else "")
			return st + "_secret" if secret and TEXTURES.has(st + "_secret") else st
	return "hues" if "hues_and_cues" in g else ("gold" if "brodilka" in g else ("silver" if "gloom" in g else "neon"))


## Ключ игры для секрета и монет: perudo / id из GAME_COINS / "" (у остальных секрета нет).
func _game_key() -> String:
	var g: String = Net.party_game
	if get_tree().current_scene:
		g += " " + get_tree().current_scene.scene_file_path
	g = g.replace("main18", "tip_top_18")
	if "perudo" in g:
		return "perudo"
	for gc in GAME_COINS:
		if gc[0] in g:
			return gc[0]
	return ""


## Обновить облик. animated — подбросить монетку и сменить облик в полёте (смена темы).
func _refresh_style(animated: bool) -> void:
	var want := _style_for()
	if want == _style or want == _pending:
		return
	if animated and is_visible_in_tree() and not _holding:
		_pending = want
		_pending_secret = false
		_toss()
		return
	_set_style(want)


func _set_style(st: String) -> void:
	_style = st
	_last_style = st
	queue_redraw()


## Секретный облик есть у этой игры?
func _has_secret() -> bool:
	var key := _game_key()
	if key == "perudo":
		return true
	for gc in GAME_COINS:
		if gc[0] == key:
			return TEXTURES.has(key + "_secret")
	return false


func _has_point(p: Vector2) -> bool:
	return p.distance_to(size * 0.5) <= R + 4


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		_holding = true
		_in_dock = false
		_moved = false
		_press_at = e.global_position
		var center := position + size * 0.5
		_grab = e.global_position - center  # точка хвата от центра (в экранных координатах)
		_rope = _grab.length()
		_rot0 = rotation
		_dir0 = (-_grab).angle()
		_vel = Vector2.ZERO
		_spin = 0.0
		_flip_speed = 0.0  # поймали — перестаёт кувыркаться и ложится плашмя (в _process)
		_toss_t = -1.0
		_lift = 0.0
		_samples = [[Time.get_ticks_msec(), e.global_position]]
		_rot_samples = [[Time.get_ticks_msec(), rotation]]
		_play("coins_%d.ogg" % randi_range(1, 2), -12)
		accept_event()


func _input(e: InputEvent) -> void:
	if not _holding:
		return
	if e is InputEventMouseMotion and not (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_release()  # отпускание кнопки кто-то перехватил — монетку всё равно отпускаем, без звука и броска
		return
	if e is InputEventMouseMotion:
		if e.global_position.distance_to(_press_at) > 5.0:
			_moved = true
		var vs := get_viewport_rect().size
		# монета висит на точке хвата: центр тянется за курсором на «верёвке» длиной _rope —
		# водишь курсором по кругу — монета вращается вокруг этой точки
		var m: Vector2 = e.global_position
		var center := position + size * 0.5
		var d := center - m
		if _rope > 3.0 and d.length() > 0.5:
			center = m + d.normalized() * _rope
			rotation = _rot0 + angle_difference(_dir0, d.angle())
		else:
			center = m - _grab
		position = (center - size * 0.5).clamp(Vector2.ZERO, vs - size)
		_rot_samples.append([Time.get_ticks_msec(), rotation])
		while _rot_samples.size() > 2 and Time.get_ticks_msec() - int(_rot_samples[0][0]) > 90:
			_rot_samples.pop_front()
		_samples.append([Time.get_ticks_msec(), e.global_position])
		while _samples.size() > 2 and Time.get_ticks_msec() - int(_samples[0][0]) > 90:
			_samples.pop_front()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		_holding = false
		if _moved:
			_throw()
			_try_dock()  # отпустили над гнездом без размаха — встаёт на место
		elif _has_point(get_global_transform().affine_inverse() * e.global_position):
			_toss()  # щелчок по самой монетке — подбросить
		saved_pos = position
		get_viewport().set_input_as_handled()


func _release() -> void:
	_holding = false
	saved_pos = position


## Бросок: скорость — по движению мыши за последние ~90 мс; схватил не за центр — закрутится.
func _throw() -> void:
	var a: Array = _samples[0]
	var b: Array = _samples[_samples.size() - 1]
	var dt := maxf(0.016, (int(b[0]) - int(a[0])) / 1000.0)
	_vel = ((b[1] as Vector2) - (a[1] as Vector2)) / dt
	_vel = _vel.limit_length(MAX_SPEED)
	# вращение — каким оно было в руке (крутили вокруг точки хвата)
	var ra: Array = _rot_samples[0]
	var rb: Array = _rot_samples[_rot_samples.size() - 1]
	var rdt := maxf(0.016, (int(rb[0]) - int(ra[0])) / 1000.0)
	_spin = clampf(angle_difference(float(ra[1]), float(rb[1])) / rdt, -40.0, 40.0)
	_flip_speed = _vel.length() * 0.02  # летит — кувыркается
	_play("coins_%d.ogg" % randi_range(3, 4), -10)


## Щелчок: подброс на месте — 0.9 с в воздухе, приземляется орлом или решкой.
func _toss() -> void:
	if _toss_t >= 0.0:
		return
	_toss_t = 0.0
	var half_turns := randi_range(6, 9)
	_toss_target = round(_flip / PI) * PI + half_turns * PI
	_play("coins_5.ogg", -8)
	if _pending == "" and cos(_toss_target) >= 0.0 and _heads + 1 >= SECRET_STREAK and _has_secret():
		var key := _game_key()
		Prefs.coin_secrets[key] = not Prefs.coin_secrets.get(key, false)
		Prefs.save()
		_pending = _style_for()
		_pending_secret = true


## Гнездо в верхней полосе (TopBar): медленно катится рядом / отпустили над ним — плавно встаёт на место.
const DOCK_RADIUS := 34.0
const DOCK_MAX_SPEED := 380.0  # быстрее — пролетает мимо
var _docking := false
var _dock_bar: Node  # чья полоса: пересоздали — новое гнездо ещё не на месте
var _dock_wait := 0
var _in_dock := false  # лежит в гнезде — едет вместе с ним (гнездо сдвигается, когда прячутся часы)


func _dock_center() -> Vector2:
	var bar := get_tree().get_first_node_in_group("top_bar")
	if bar == null or bar.get("coin_dock") == null:
		return Vector2(-9999, -9999)
	var dock: Control = bar.coin_dock
	return dock.global_position + dock.size * 0.5


func _try_dock() -> bool:
	var dc := _dock_center()
	if _docking or (position + size * 0.5).distance_to(dc) > DOCK_RADIUS or _vel.length() > DOCK_MAX_SPEED:
		return false
	_docking = true
	_vel = Vector2.ZERO
	_spin = 0.0
	_flip_speed = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(self, "position", dc - size * 0.5, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "rotation", 0.0, 0.25)
	t.tween_method(func(f: float):
		_flip = f
		queue_redraw(), _flip, round(_flip / PI) * PI, 0.25)
	t.chain().tween_callback(func():
		_docking = false
		_in_dock = true
		saved_pos = position
		_knock(-14.0))
	return true


func _process(delta: float) -> void:
	if not visible:
		return
	_was_docked = _in_dock
	if not Net.in_session() or Net.view.is_empty():
		visible = false  # вышли из партии — прячемся сразу, не дожидаясь PauseLayer
		_holding = false
		return
	# над картами стола (у них бывает поднятый z_index), но если поверх стола открыто окно
	# (правила, настройки — они добавляются в сцену после монетки) — не выше него
	var par := get_parent()
	if par:
		# стол пересоздали (смена темы и т. п.) и он встал поверх монетки — сразу встаём над ним
		var scr = par.get("screen")
		if scr is Node and (scr as Node).get_parent() == par and (scr as Node).get_index() > get_index():
			par.move_child(self, (scr as Node).get_index())
		var z := 0 if get_index() < par.get_child_count() - 1 else 50
		if z_index != z:
			z_index = z
	if not _holding and _toss_t < 0.0 and _vel.length_squared() > 1.0 and _try_dock():
		return
	if _in_dock and not _holding and not _docking and _toss_t < 0.0 and _vel.length_squared() <= 1.0:
		var dc := _dock_center()
		var bar := get_tree().get_first_node_in_group("top_bar")
		if bar != _dock_bar:
			_dock_bar = bar
			_dock_wait = 3  # стол пересобрали — новое гнездо пару кадров раскладывается, не прыгаем за ним
		if _dock_wait > 0:
			_dock_wait -= 1
		elif dc.x > -9000.0 and (position + size * 0.5).distance_to(dc) > 0.5:
			position = dc - size * 0.5
			saved_pos = position
	var dirty := false
	if _holding:
		var flat: float = round(_flip / PI) * PI
		if absf(_flip - flat) > 0.001:
			_flip = lerpf(_flip, flat, 1.0 - exp(-14.0 * delta))
			dirty = true
	if _toss_t >= 0.0:
		_toss_t += delta
		var k := clampf(_toss_t / 0.9, 0.0, 1.0)
		_lift = sin(k * PI)
		_flip = lerpf(_toss_target - 7.0 * PI, _toss_target, 1.0 - pow(1.0 - k, 2.0))
		# смена облика — в полёте, когда монета стоит ребром и картинки почти не видно
		if _pending != "" and k > 0.25 and absf(cos(_flip)) < 0.18:
			_set_style(_pending)
			_pending = ""
		if k >= 1.0:
			_toss_t = -1.0
			_lift = 0.0
			_flip = _toss_target
			_play("drop_%d.wav" % randi_range(1, 2), -8)
			if _pending != "":
				_set_style(_pending)  # не успела встать ребром — меняем на приземлении
				_pending = ""
			_count_heads(cos(_flip) >= 0.0)
		dirty = true
	if not _holding and (_vel.length_squared() > 1.0 or absf(_spin) > 0.05 or _flip_speed > 0.05):
		var vs := get_viewport_rect().size
		var p := position + _vel * delta
		var hit := false
		if p.x < 0.0 or p.x > vs.x - size.x:
			_vel.x = -_vel.x * BOUNCE
			_spin = -_spin * 0.8
			hit = true
		if p.y < 0.0 or p.y > vs.y - size.y:
			_vel.y = -_vel.y * BOUNCE
			_spin = -_spin * 0.8
			hit = true
		position = p.clamp(Vector2.ZERO, vs - size)
		if hit and _vel.length() > 60.0:
			_knock(lerpf(-22.0, -8.0, clampf(_vel.length() / 1500.0, 0.0, 1.0)))
		var damp := exp(-FRICTION * delta)
		_vel *= damp
		_spin *= exp(-1.2 * delta)
		rotation += _spin * delta
		_flip += _flip_speed * delta
		_flip_speed *= exp(-2.5 * delta)
		if _vel.length() < 8.0:
			_vel = Vector2.ZERO
		if _flip_speed < 0.3 and _toss_t < 0.0:
			_flip = lerpf(_flip, round(_flip / PI) * PI, 1.0 - exp(-8.0 * delta))  # ложится плашмя
			if _flip_speed < 0.05:
				_flip_speed = 0.0
		saved_pos = position
		dirty = true
	if dirty:
		queue_redraw()


## Подброс «Перудо» лёг черепом — копим серию; набрали — смена облика, смех пиратов и «подпрыгивание».
func _count_heads(heads: bool) -> void:
	_heads = _heads + 1 if heads else 0
	if not _pending_secret:
		return
	_pending_secret = false
	_heads = 0
	# секрет открыт (или закрыт): звук и мягкое «подпрыгивание»
	if _game_key() == "perudo":
		Sfx.play("pirate_laugh", -6, 0.05, 0.5)
	else:
		Sfx.play("chips_win", -6, 0.05, 0.3)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.5, 1.5), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _colors() -> Array:
	match _style:
		"doubloon", "doubloon_gold":
			return [Color("d9a43a"), Color("8a5a14"), Color("f6dc8a")]
		"gold":
			return [Color("f2c03a"), Color("a8741c"), Color("fff1b0")]
		"silver":
			return [Color("4a4c52"), Color("2a2c30"), Color("9fd8b4")]  # Gloom: тёмный камень
	return [Color("3fd6e8"), Color("1a5f8a"), Color("c8fbff")]


func _draw() -> void:
	var c := size * 0.5
	var cols := _colors()
	var face_w := absf(cos(_flip))  # сжатие по ширине — монета повёрнута ребром
	var heads := cos(_flip) >= 0.0
	var scale_up := 1.0 + _lift * 0.35
	# тень: при подбросе — дальше и бледнее
	# тень сужается вместе с монетой, когда та встаёт ребром
	draw_set_transform(c + Vector2(0, 4 + _lift * 14), 0.0, Vector2(maxf(face_w, 0.2) * scale_up, scale_up * 0.45))
	draw_circle(Vector2.ZERO, R, Color(0, 0, 0, 0.3 - _lift * 0.18))
	draw_set_transform(c - Vector2(0, _lift * 10), 0.0, Vector2(maxf(face_w, 0.08) * scale_up, scale_up))
	if TEXTURES.has(_style):
		var tex := _tex(TEXTURES[_style][0 if heads else 1])
		draw_circle(Vector2(0, 2.0), R, cols[1].darkened(0.4))  # ребро
		if tex:
			# «Дюжина короля» — та же монета, что в бродилке, но потемнее (под таверну)
			var tint := Color(0.72, 0.68, 0.6) if _style == "gold_dark" else Color.WHITE
			draw_texture_rect(tex, Rect2(Vector2(-R, -R), Vector2(R, R) * 2.0), false, tint)
		draw_set_transform(Vector2.ZERO)
		return
	# ребро — видно, когда монета повёрнута
	draw_circle(Vector2(0, 1.5), R, cols[1])
	draw_circle(Vector2.ZERO, R, cols[0])
	draw_arc(Vector2.ZERO, R - 1.5, 0, TAU, 32, cols[1], 2.0, true)
	draw_arc(Vector2.ZERO, R * 0.72, 0, TAU, 28, Color(cols[1], 0.7), 1.5, true)
	if _style == "neon":
		draw_arc(Vector2.ZERO, R + 2, 0, TAU, 32, Color(cols[2], 0.35), 3.0, true)
	if heads:
		# орёл: звезда
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			pts.append(Vector2(cos(a), sin(a)) * (R * 0.48 if i % 2 == 0 else R * 0.2))
		draw_colored_polygon(pts, cols[1])
	else:
		# решка: «1» как засечками отлитая цифра
		var f := ThemeDB.fallback_font
		var s := int(R * 1.05)
		var sz := f.get_string_size("1", HORIZONTAL_ALIGNMENT_CENTER, -1, s)
		draw_string(f, Vector2(-sz.x * 0.5, sz.y * 0.32), "1", HORIZONTAL_ALIGNMENT_CENTER, -1, s, cols[1])
	# блик
	draw_circle(Vector2(-R * 0.35, -R * 0.4), R * 0.18, Color(cols[2], 0.55))
	draw_set_transform(Vector2.ZERO)


static func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func _play(file: String, db: float) -> void:
	if Sfx.muted:
		return
	_snd.stream = load(SND + file)
	_snd.volume_db = db + linear_to_db(maxf(Sfx.volume * VOLUME, 0.001))
	_snd.pitch_scale = randf_range(0.92, 1.08)
	_snd.play()


## Лёгкий стук о край экрана (как о бортик); громкость — от силы удара.
func _knock(db: float) -> void:
	if Sfx.muted:
		return
	_bounce.volume_db = db + linear_to_db(maxf(Sfx.volume * VOLUME, 0.001))
	_bounce.pitch_scale = randf_range(0.9, 1.15)
	_bounce.play()
