extends PanelContainer
## Автообновление, часть 3 — плашка в хабе над версией (правый нижний угол).
##
## Видна, только когда есть что сказать: доступно обновление, идёт загрузка, готово к перезапуску,
## ошибка или откат. Сама запускает тихую проверку (один раз за запуск, `UpdateClient.check`).

const Client := preload("res://hub/update/update_client.gd")

var _client: Node
var _shown := -1  # для какого состояния собрано содержимое
var _bar: ProgressBar
var _bytes: Label


func _ready() -> void:
	var sb := HubStyle.box(HubStyle.PANEL, 12, HubStyle.VIOLET, 2, 0.45)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size.x = 300
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -16
	offset_bottom = -40  # над строкой «Версия …»
	_client = Client.get_or_create(get_tree())
	_client.changed.connect(_refresh)
	_refresh()
	_client.check.call_deferred()


func _refresh() -> void:
	var st: int = _client.state
	if st == _shown:
		if st == Client.State.DOWNLOADING and is_instance_valid(_bar):
			_bar.value = _client.progress()
			_bytes.text = "%s из %s" % [_mb(_client.done_bytes), _mb(_client.total_bytes)]
		return
	_shown = st
	HubStyle.clear(self)
	_bar = null
	var note := ""
	if Updater.rolled_back != "":
		note = "Версия %s не запустилась — вернули прежнюю" % Updater.rolled_back
	var quiet := st in [Client.State.IDLE, Client.State.CHECKING, Client.State.NONE]
	visible = not quiet or note != ""
	if not visible:
		return
	var v := HubStyle.vbox(8)
	add_child(v)
	if note != "":
		v.add_child(_text(note, 13, HubStyle.MUTED))
	if quiet:
		return
	var full: bool = _client.kind == "base"
	match st:
		Client.State.AVAILABLE:
			v.add_child(HubStyle.label("Доступно обновление %s" % _client.target, 16, HubStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
			v.add_child(_text(("Полная версия, %s" if full else "Патч, %s") % _mb(_size()), 13, HubStyle.MUTED))
			v.add_child(_button(HubStyle.primary("Обновить", 16), _client.start))
		Client.State.MANUAL:
			v.add_child(HubStyle.label("Вышла версия %s" % _client.target, 16, HubStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
			v.add_child(_text("Папку игры нельзя изменить — скачайте архив со страницы релиза", 13, HubStyle.MUTED))
			v.add_child(_button(HubStyle.button("Открыть страницу", 15), _client.start))
		Client.State.DOWNLOADING:
			v.add_child(HubStyle.label("Загрузка %s…" % _client.target, 16, HubStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
			_bar = ProgressBar.new()
			_bar.max_value = 1.0
			_bar.show_percentage = false
			_bar.custom_minimum_size.y = 8
			_bar.add_theme_stylebox_override("background", HubStyle.box(Color(0.03, 0.02, 0.07, 0.9), 4, HubStyle.VIOLET.darkened(0.4), 1, 0.0))
			_bar.add_theme_stylebox_override("fill", HubStyle.box(HubStyle.PINK, 4, HubStyle.PINK, 0, 0.5))
			_bar.value = _client.progress()
			v.add_child(_bar)
			_bytes = _text("", 13, HubStyle.MUTED)
			_bytes.text = "%s из %s" % [_mb(_client.done_bytes), _mb(_client.total_bytes)]
			v.add_child(_bytes)
		Client.State.INSTALLING:
			v.add_child(HubStyle.label("Установка %s…" % _client.target, 16, HubStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		Client.State.READY:
			v.add_child(HubStyle.label("Обновление %s готово" % _client.target, 16, HubStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
			if Net.is_party():
				v.add_child(_text("После перезапуска пати придётся собрать заново", 13, HubStyle.MUTED))
			v.add_child(_button(HubStyle.primary("Перезапустить", 16), _client.restart))
		Client.State.FAILED:
			v.add_child(HubStyle.label("Не удалось обновить", 16, HubStyle.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
			v.add_child(_text(str(_client.error), 13, HubStyle.MUTED))
			v.add_child(_button(HubStyle.button("Повторить", 15), _client.start))


func _size() -> int:
	var n := 0
	for q: Dictionary in _client._queue:
		n += int(q["size"])
	return n


func _text(t: String, size: int, color: Color) -> Label:
	var l := HubStyle.label(t, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 268
	return l


func _button(b: Button, action: Callable) -> Button:
	b.pressed.connect(action)
	return b


static func _mb(bytes: int) -> String:
	if bytes < 1024 * 1024:
		return "%d КБ" % maxi(1, bytes / 1024)
	return "%.1f МБ" % (bytes / 1048576.0)
