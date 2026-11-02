extends RefCounted
## Короткое обучение четырём вкладкам; отметки прочтения локальные, не входят в пакет игры.
const Style := preload("res://games/custom/ui/cg_style.gd")
const PATH := "user://editor_help.cfg"
const TOPICS := [
	{"title": "Коробка", "tip": "Коробка: добавьте слой и настройте его справа. Справка — здесь же.",
	"text": "Выберите грань коробки и добавьте картинку, текст или цветной слой. Своя картинка выбирается через проводник Windows.\n\nПереносите изображение мышью, меняйте размер за углы и поворачивайте ручкой. Список слоёв задаёт, что находится сверху. Слой можно скопировать в буфер и вставить на другую грань.\n\nПроверьте коробку в объёмном виде. При сохранении редактор запечёт грани для вашей полки."},
	{"title": "Интерфейс", "tip": "Интерфейс: разместите зоны, затем задайте владельца и видимость справа.",
	"text": "Добавьте зону, руку игрока или кнопку слева. Выбирайте элементы на холсте, переносите и меняйте размер. Колесо приближает, средняя или правая кнопка двигает поле.\n\nУ зоны укажите владельца: общая, у каждого игрока или у команды. Настройте вид и видимость; переключатель просмотра помогает проверить, что увидят разные участники.\n\nКнопка связывается с событием в логике по своему идентификатору. Общие действия стола остаются в верхней полосе."},
	{"title": "Логика", "tip": "Логика: добавьте событие, выберите его и соберите действия из палитры слева.",
	"text": "Начните с события: начало игры, нажатие кнопки или выбор карты. Добавляйте действия слева; выбранный блок настраивается справа. Условие или цикл содержат свои ветви.\n\nСтрелка в шапке сворачивает цепочку, кнопки масштаба и мини-карта помогают в больших правилах. Буфер копирует цепочки целиком или блок с ветвями; отсутствующие зоны и переменные нужно сначала создать в этой игре.\n\nВ «Переменные и роли» задаются ресурсы и порядок ходов. Можно подключить общий словарь и выбирать случайное слово. «Проверить» запускает локальную игру за всех; «Ошибки» объясняет, что мешает запуску."},
	{"title": "Элементы", "tip": "Элементы: создайте колоду или кубики; строки таблицы становятся картами игры.",
	"text": "Создайте колоду и заполните таблицу: одна строка описывает карту, число копий задаёт тираж. Названия столбцов используются в правилах как свойства карты.\n\nВыберите размер, оформление лица и рубашку. Для личной или командной колоды настройте владельца и подходящую начальную зону. Таблицу можно импортировать из CSV.\n\nДля простого прототипа доступны кубики d6, жетоны и ресурсы. Сохраните проект и используйте «Проверить», чтобы пройти настоящий ход до подключения друзей."},
]
var _config := ConfigFile.new()

func _init() -> void:
	_config.load(PATH)

func tip(tab: int) -> String:
	return "" if bool(_config.get_value("seen", str(tab), false)) else str(TOPICS[clampi(tab, 0, 3)].tip)

func dismiss(tab: int) -> void:
	_config.set_value("seen", str(tab), true)
	_config.save(PATH)

func show(owner: Control, tab: int, closed: Callable) -> void:
	if owner.has_node("EditorHelpOverlay"):
		return
	var topic: Dictionary = TOPICS[clampi(tab, 0, 3)]
	var overlay := ColorRect.new()
	overlay.name = "EditorHelpOverlay"
	overlay.color = Color(Style.bg(), 0.8)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200
	owner.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 400)
	panel.add_theme_stylebox_override("panel", Style.box(Style.panel(), 16))
	center.add_child(panel)
	var col := Style.column(16)
	panel.add_child(col)
	col.add_child(Style.heading("КАК ПОЛЬЗОВАТЬСЯ · " + str(topic.title).to_upper()))
	var text := Style.label(str(topic.text))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 592
	col.add_child(text)
	var done := Style.primary("Понятно")
	col.add_child(done)
	var close := func():
		dismiss(tab)
		overlay.queue_free()
		closed.call()
	done.pressed.connect(close)
	overlay.focus_mode = Control.FOCUS_ALL
	overlay.gui_input.connect(func(event: InputEvent):
		if event.is_action_pressed("ui_cancel"):
			close.call()
			overlay.accept_event())
	done.grab_focus()
