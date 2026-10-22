extends Node
## Автозагрузка Sfx: короткие звуки игры (Kenney, CC0). Sfx.play("card_place").
## Каждое событие — набор вариантов, выбирается случайный, с лёгким разбросом высоты.
## Здесь же фоновая музыка таверны (OpenGameArt, CC0). Звучит всегда ровно одна мелодия.

const DIR := "res://games/king_of_12/audio/"
const SOUNDS := {
	"die_grab": ["dice-grab-1", "dice-grab-2"],
	"die_shake": ["dice-shake-1"],
	"die_throw": ["die-throw-1", "die-throw-2", "die-throw-3"],
	"die_hit": ["die-throw-4", "die-throw-2"],
	"card_place": ["card-place-1", "card-place-2", "card-place-3", "card-place-4"],
	"card_slide": ["card-slide-1", "card-slide-2", "card-slide-3", "card-slide-4"],
	"card_shove": ["card-shove-1", "card-shove-2"],
	"card_flip": ["card-fan-1", "card-fan-2"],
	"shuffle": ["card-shuffle"],
	"game_start": ["cards-pack-open-1"],
	"chip": ["chip-lay-1", "chip-lay-2", "chip-lay-3"],
	"chips_soft": ["chips-collide-1", "chips-collide-2"],
	"chips_win": ["chips-stack-1", "chips-stack-2"],
	"chips_big": ["chips-handle-1", "chips-handle-2"],
	"click": ["click1", "click3"],  # click2 слишком громкий
	"tick": ["tick"],  # отсчёт последних секунд (сгенерирован, свой)
	"tick_high": ["tick_high"],
	# «Перудо» (пиратский стол): полные пути — свои файлы игры
	"pirate_laugh": ["res://games/perudo/audio/laugh_1.mp3", "res://games/perudo/audio/laugh_2.mp3", "res://games/perudo/audio/laugh_3.mp3", "res://games/perudo/audio/laugh_4.mp3", "res://games/perudo/audio/laugh_6.mp3"],
	"arr": ["res://games/perudo/audio/arr.wav"],
	"hover": ["rollover2"],  # rollover1 убран — неприятный щелчок
}
const POOL := 12
const MUSIC := ["music/tavern_old_tower_inn.mp3", "music/tavern_bards_tale.mp3"]
const VICTORY := "music/victory.mp3"

var muted: bool:
	get:
		return Prefs.muted
var volume := 1.0
var _music: AudioStreamPlayer
var _music_i := 0
var _music_started := false
var _playlist: Array = []  # полные пути; пусто — музыка таверны
var _repeat_left := 0  # короткий трек (луп) повторяем, чтобы музыка не менялась каждые 15 секунд
var _fade: Tween
## Поправки громкости треков (дБ), чтобы спокойные и резкие треки звучали ровно.
const TRACK_GAIN := {"pirate_indenture.wav": -4.0, "pirate_ship.ogg": 0.0}
const MUSIC_DB := -8.0
const MIN_TRACK_SEC := 90.0  # короткие лупы крутим, пока не наберётся столько
var _ambience: AudioStreamPlayer  # фоновый шум (море в «Перудо»), по кругу

var played := {}  # счётчик проигранных звуков (для отладки)
var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _last := {}


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.finished.connect(_on_track_end)
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Music"
	add_child(_ambience)
	# победная тема не должна доигрывать в лобби / другой игре
	if get_tree().has_signal("scene_changed"):
		get_tree().connect("scene_changed", stop_victory)
	Net.game_ended.connect(stop_victory)
	Net.session_closed.connect(func(_r): stop_victory())


## Фоновая музыка (треки по кругу). Повторный вызов ничего не делает.
func start_music() -> void:
	if _music_started:
		return
	_music_started = true
	_music_i = randi() % MUSIC.size()
	_next_track()


## Сменить музыку (у каждой игры может быть своя). Пустой список — музыка таверны.
func set_playlist(paths: Array) -> void:
	set_ambience("")  # фон — только у игры, которая сама его включила (после set_playlist)
	if paths == _playlist:
		return
	_playlist = paths.duplicate()
	_music_started = true
	_music_i = 0
	if _music.playing:
		_fade_out_then(_next_track)  # смена игры — плавно
	else:
		_next_track()


## Фоновый шум по кругу ("" — выключить).
func set_ambience(path: String, vol_db: float = -16.0) -> void:
	if path == "":
		_ambience.stop()
		_ambience.stream = null
		return
	if _ambience.playing and _ambience.stream and _ambience.stream.resource_path == path:
		return
	var st: AudioStream = load(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	_ambience.stream = st
	_ambience.volume_db = vol_db
	_ambience.play()


func _on_track_end() -> void:
	if _repeat_left > 0:
		_repeat_left -= 1
		_music.play()  # тот же луп ещё раз — без смены настроения
		return
	_next_track()


func _fade_out_then(next: Callable) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_music, "volume_db", -40.0, 1.2).set_trans(Tween.TRANS_SINE)
	_fade.tween_callback(next)


func _track_db(path: String) -> float:
	return MUSIC_DB + float(TRACK_GAIN.get(path.get_file(), 0.0))


func _next_track() -> void:
	var list: Array = _playlist if not _playlist.is_empty() else MUSIC.map(func(m): return DIR + m)
	var path: String = list[_music_i % list.size()]
	_music.stream = load(path)
	_music_i += 1
	var length := _music.stream.get_length() if _music.stream else 0.0
	_repeat_left = int(ceil(MIN_TRACK_SEC / length)) - 1 if length > 1.0 and length < MIN_TRACK_SEC else 0
	# новый трек входит плавно
	if _fade:
		_fade.kill()
	_music.volume_db = -30.0
	_music.play()
	_fade = create_tween()
	_fade.tween_property(_music, "volume_db", _track_db(path), 2.5).set_trans(Tween.TRANS_SINE)


## Победная тема: тише остальной музыки, музыка игры приглушается и возвращается после.
## Обрывается при выходе в лобби / другую игру / меню (stop_victory).
var _victory: AudioStreamPlayer
var _victory_tween: Tween


var _victory_gid := ""  # партия, для которой тема уже звучала


func victory() -> void:
	# одна партия — одна победная тема (стол мог пересоздаться: смена темы, переподключение)
	var gid := str(Net.view.get("game_id", ""))
	if gid != "" and gid == _victory_gid:
		return
	_victory_gid = gid
	stop_victory()
	var p := _free_player()
	p.bus = "Music"
	p.stream = load(DIR + VICTORY)
	p.volume_db = -12.0
	p.pitch_scale = 1.0
	p.play()
	_victory = p
	_victory_tween = create_tween()
	_victory_tween.tween_property(_music, "volume_db", -24.0, 0.5)
	_victory_tween.tween_interval(6.0)
	_victory_tween.tween_property(_music, "volume_db", MUSIC_DB, 2.0)
	_victory_tween.tween_callback(func(): p.bus = "SFX")


func stop_victory() -> void:
	if _victory_tween and _victory_tween.is_valid():
		_victory_tween.kill()
	if is_instance_valid(_victory) and _victory.playing and _victory.bus == "Music":
		_victory.stop()
		_victory.bus = "SFX"
	_victory = null
	if _music:
		_music.volume_db = -8.0

## Проиграть звук. vol_db — относительная громкость, min_gap — не чаще, чем раз в N секунд.
## «Бессвязная речь» к реплике (как в Animal Crossing): интонация — по смыслу реплики
## («Удивительно!» — восклицание, «Эй, вы ещё здесь?» — вопрос, «Думаю...» — задумчивое «хмм»),
## у каждого игрока свой тембр (по имени), и каждый раз чуть иначе.
const BABBLE_STYLE := {
	"Думаю...": "think", "Блефую!": "bluff", "Кидаю кость!": "roll", "Хитро!": "sly",
	"Ой…": "oops", "Мне повезёт!": "hope", "Удивительно!": "wow", "Эй, вы ещё здесь?": "hey",
}


func babble(text: String, voice: String) -> void:
	if muted:
		return
	var file := "res://games/king_of_12/audio/babble_%s_%d.wav" % [BABBLE_STYLE.get(text, "any"), randi_range(1, 3)]
	if not _cache.has(file):
		_cache[file] = load(file)
	var player := _free_player()
	player.bus = "SFX"
	player.stream = _cache[file]
	player.volume_db = -4.9 + linear_to_db(volume)  # на 10% тише первой версии (-4 дБ)
	var base := 0.85 + float(absi(hash(voice)) % 100) / 100.0 * 0.4  # 0.85…1.25 — свой голос
	player.pitch_scale = base * randf_range(0.95, 1.05)
	player.play()


func play(sound: String, vol_db: float = 0.0, pitch_var: float = 0.06, min_gap: float = 0.04) -> void:
	if muted or not SOUNDS.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound, -10.0)) < min_gap:
		return
	_last[sound] = now
	var file: String = SOUNDS[sound].pick_random()
	if not _cache.has(file):
		_cache[file] = load(file if file.begins_with("res://") else DIR + file + ".ogg")
	var player := _free_player()
	player.bus = "SFX"
	player.stream = _cache[file]
	player.volume_db = vol_db + linear_to_db(volume)
	player.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	player.play()
	played[sound] = played.get(sound, 0) + 1


## Отсчёт последних 15 секунд таймера: тик каждую секунду, последние 5 — выше.
func countdown(seconds_left: int) -> void:
	if seconds_left >= 1 and seconds_left <= 15:
		play("tick_high" if seconds_left <= 5 else "tick", -4 if seconds_left <= 5 else -8, 0.0, 0.3)


func set_muted(on: bool) -> void:
	Prefs.set_value("muted", on)


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	var oldest: AudioStreamPlayer = _players.pop_front()
	_players.append(oldest)
	return oldest
