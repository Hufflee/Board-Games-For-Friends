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
	"pawn_step": ["res://games/brodilka/audio/step_1.wav", "res://games/brodilka/audio/step_2.wav", "res://games/brodilka/audio/step_3.wav"],  # бродилка: персонаж стучит по полю (синтез)
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
var _quitting := false
var _playlist: Array = []  # полные пути; пусто — музыка таверны
var _repeat_left := 0  # короткий трек (луп) повторяем, чтобы музыка не менялась каждые 15 секунд
var _fade: Tween
## Поправки громкости треков (дБ), чтобы спокойные и резкие треки звучали ровно.
const TRACK_GAIN := {"pirate_indenture.wav": -4.0, "pirate_ship.ogg": 0.0}
const MUSIC_DB := -8.0
const MIN_TRACK_SEC := 90.0  # короткие лупы крутим, пока не наберётся столько
var _ambience: AudioStreamPlayer  # фоновый шум (море в «Перудо»), по кругу

var _theme_before := ""
var _theme_silent_until := 0
var played := {}  # счётчик проигранных звуков (для отладки)
var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _last := {}


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_theme_before = Prefs.theme_mode
	Prefs.changed.connect(func():
		if _theme_before != Prefs.theme_mode:
			_theme_before = Prefs.theme_mode
			_theme_silent_until = Time.get_ticks_msec() + 1000)
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


## Штатный выход: аудиосервер получает время отпустить Ogg до удаления дерева.
func request_quit(exit_code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	stop_audio()
	await get_tree().create_timer(0.1, true, false, true).timeout
	# На тяжёлом кадре таймер истекает раньше следующего обновления аудиосервера.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

## Синхронная часть завершения, также доступна тестам перед прямым SceneTree.quit.
func stop_audio() -> void:
	for tween in [_fade, _victory_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	for player in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	_cache.clear()


## Фоновая музыка (треки по кругу). Повторный вызов ничего не делает.
func start_music() -> void:
	if _quitting:
		return
	if _music_started:
		return
	_music_started = true
	_music_i = randi() % MUSIC.size()
	_next_track()


## Сменить музыку (у каждой игры может быть своя). Пустой список — музыка таверны.
func set_playlist(paths: Array) -> void:
	if _quitting:
		return
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
	if _quitting:
		return
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
	if _quitting:
		return
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
	if _quitting:
		return
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
const VICTORY_DB := -20.0  # тише музыки игры: тема громко сведена


func victory() -> void:
	if _quitting:
		return
	# одна партия — одна победная тема (стол мог пересоздаться: смена темы, переподключение)
	var gid := str(Net.view.get("game_id", ""))
	if gid != "" and gid == _victory_gid:
		return
	_victory_gid = gid
	stop_victory()
	if _victory == null:
		_victory = AudioStreamPlayer.new()  # свой плеер: его всегда можно остановить при выходе
		_victory.bus = "Music"
		add_child(_victory)
	_victory.stream = load(DIR + VICTORY)
	_victory.volume_db = VICTORY_DB
	_victory.play()
	_victory_tween = create_tween()
	_victory_tween.tween_property(_music, "volume_db", -26.0, 0.5)
	_victory_tween.tween_interval(6.0)
	_victory_tween.tween_property(_victory, "volume_db", -40.0, 2.5)  # тема затихает…
	_victory_tween.parallel().tween_property(_music, "volume_db", _cur_music_db(), 2.5)  # …и возвращается музыка игры
	_victory_tween.tween_callback(_victory.stop)


func stop_victory() -> void:
	if _victory_tween and _victory_tween.is_valid():
		_victory_tween.kill()
	if is_instance_valid(_victory):
		_victory.stop()
	if _music:
		_music.volume_db = _cur_music_db()


## Громкость текущего трека (с поправкой TRACK_GAIN).
func _cur_music_db() -> float:
	return _track_db(_music.stream.resource_path) if _music and _music.stream else MUSIC_DB

## Проиграть звук. vol_db — относительная громкость, min_gap — не чаще, чем раз в N секунд.
## «Бессвязная речь» к реплике (как в Animal Crossing): интонация — по смыслу реплики
## («Удивительно!» — восклицание, «Эй, вы ещё здесь?» — вопрос, «Думаю...» — задумчивое «хмм»),
## у каждого игрока свой тембр (по имени), и каждый раз чуть иначе.
const BABBLE_STYLE := {
	"Думаю...": "think", "Блефую!": "bluff", "Кидаю кость!": "roll", "Хитро!": "sly",
	"Ой…": "oops", "Мне повезёт!": "hope", "Удивительно!": "wow", "Эй, вы ещё здесь?": "hey",
}


## Голоса персонажей (ElevenLabs): voices/<голос>_<стиль>.wav. Выдаёт хост — Net._voice_of.
const VOICES := ["buddy", "duchess", "fireplace", "giant", "grandpa", "sailor", "schemer", "scholar", "soldier", "villain"]
var _voice_players := {}  # голос → плеер, который его сейчас проигрывает (новая реплика обрывает прежнюю)
const VOICE_DIR := "res://games/king_of_12/audio/voices/"


## Обычное сообщение чата — тоже голосом автора: «!» — восклицание, «?» — недоумение, иначе случайная реплика.
const CHAT_EXCLAIM := ["wow", "hope"]
const CHAT_PUZZLED := ["think", "oops"]
const CHAT_ANY := ["any", "think", "sly", "wow", "hope", "oops", "hey", "bluff"]


func chat_voice(text: String, voice: String) -> void:
	var t := text.strip_edges()
	var style: String = (CHAT_PUZZLED if t.ends_with("?") else (CHAT_EXCLAIM if t.ends_with("!") else CHAT_ANY)).pick_random()
	babble("", voice, style, -3.0)


func babble(text: String, voice: String, style: String = "", extra_db: float = 0.0) -> void:
	if _quitting:
		return
	if muted:
		return
	if style == "":
		style = BABBLE_STYLE.get(text, "any")
	if VOICES.has(voice):
		var vf := "%s%s_%s.wav" % [VOICE_DIR, voice, style]
		if not ResourceLoader.exists(vf):
			vf = "%s%s_any.wav" % [VOICE_DIR, voice]
		if not _cache.has(vf):
			_cache[vf] = load(vf)
		var prev: AudioStreamPlayer = _voice_players.get(voice)
		if is_instance_valid(prev) and prev.playing:
			prev.stop()  # тот же игрок сказал новую реплику — прежняя обрывается
		var vp := _free_player()
		_voice_players[voice] = vp
		vp.bus = "SFX"
		vp.stream = _cache[vf]
		vp.volume_db = -4.0 + extra_db + linear_to_db(maxf(volume * Prefs.chat_volume, 0.0001))  # ползунок «Чат» в настройках
		vp.pitch_scale = randf_range(0.98, 1.02)
		vp.play()
		return
	var file := "res://games/king_of_12/audio/babble_%s_%d.wav" % [style if ResourceLoader.exists("res://games/king_of_12/audio/babble_%s_1.wav" % style) else "any", randi_range(1, 3)]
	if not _cache.has(file):
		_cache[file] = load(file)
	var player := _free_player()
	player.bus = "SFX"
	player.stream = _cache[file]
	player.volume_db = -4.9 + linear_to_db(maxf(volume * Prefs.chat_volume, 0.0001))  # на 10% тише первой версии (-4 дБ)
	var base := 0.85 + float(absi(hash(voice)) % 100) / 100.0 * 0.4  # 0.85…1.25 — свой голос
	player.pitch_scale = base * randf_range(0.95, 1.05)
	player.play()


func play(sound: String, vol_db: float = 0.0, pitch_var: float = 0.06, min_gap: float = 0.04) -> void:
	if _quitting:
		return
	if sound in ["shuffle", "game_start", "card_flip"] and Time.get_ticks_msec() < _theme_silent_until:
		return
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
