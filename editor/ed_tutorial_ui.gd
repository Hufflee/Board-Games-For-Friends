extends RefCounted
## Экран вкладки «Обучение»: список уроков, шаги текущего урока, «Показать где» / «Сделать за меня».
## Данные и проверки шагов — editor/ed_tutorial.gd.
const Style := preload("res://games/custom/ui/cg_style.gd")
const Help := preload("res://editor/ed_help.gd")
const Tutorial := preload("res://editor/ed_tutorial.gd")

## Экран вкладки: слева — уроки и справка по вкладкам, в центре — шаги урока, справа — текущий шаг.
static func build(app: Control, tools: VBoxContainer, center: VBoxContainer, properties: VBoxContainer) -> void:
	tools.add_child(Style.heading("УРОКИ"))
	var words := Style.button("Игра про слова")
	words.name = "TutorialWords"
	if app._lesson == Tutorial.WORDS:
		words.add_theme_stylebox_override("normal", Style.box(Style.panel().lerp(Style.accent(), 0.24)))
	words.pressed.connect(func():
		app._lesson = Tutorial.WORDS
		app._render())
	tools.add_child(words)
	tools.add_child(Style.heading("ВКЛАДКИ"))
	tools.add_child(Style.label("Коротко о каждой:"))
	for index in 4:
		var topic := Style.button(str(Help.TOPICS[index].title))
		topic.tooltip_text = "Как устроена вкладка «%s»" % str(Help.TOPICS[index].title)
		topic.clip_text = true
		topic.pressed.connect(func(): app._help.show(app, index, func(): pass))
		tools.add_child(topic)
	var heading := Style.heading("ИГРА ПРО СЛОВА")
	center.add_child(heading)
	var intro := Style.label("Соберём «Объясни слово»: ходящий видит случайное слово из словаря и объясняет его, не называя. Угадали — ходящий получает очко, ход переходит дальше. Через три круга побеждает тот, у кого больше очков.\n\nКаждый шаг засчитывается сам, когда нужное появилось в игре. Не получается — «Показать где» откроет нужную вкладку, а «Сделать за меня» выполнит шаг.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(intro)
	if app._lesson != Tutorial.WORDS:
		var start := Style.primary("Начать урок")
		start.name = "TutorialStart"
		start.tooltip_text = "Урок пойдёт в этом проекте. Для чистого листа создайте новую игру в «Мои игры» → «Обучение»."
		start.pressed.connect(func():
			app._lesson = Tutorial.WORDS
			app._render())
		center.add_child(start)
		return
	var errors: Array = app.document.issues().errors
	var at := Tutorial.current(app.document.data, errors)
	var finished := 0
	for index in Tutorial.STEPS.size() - 1:
		if Tutorial.done(str(Tutorial.STEPS[index][0]), app.document.data):
			finished += 1
	center.add_child(Style.label("Готово шагов: %d из %d" % [finished, Tutorial.STEPS.size() - 1]))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	var list := Style.column(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for index in Tutorial.STEPS.size():
		var id := str(Tutorial.STEPS[index][0])
		var ok: bool = Tutorial.done(id, app.document.data) or id == "check" and at >= Tutorial.STEPS.size() - 1 and errors.is_empty() and app._lesson_played
		var row := Style.row(8)
		row.name = "TutorialStep_" + id
		var mark := Style.label("✓" if ok else ("●" if index == at else "○"))
		mark.custom_minimum_size.x = 24
		mark.add_theme_color_override("font_color", Style.accent() if ok or index == at else Style.ink().lerp(Style.bg(), 0.5))
		row.add_child(mark)
		var title := Style.label("%d. %s" % [index + 1, Tutorial.STEPS[index][2]])
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not ok and index != at:
			title.modulate.a = 0.6
		row.add_child(title)
		list.add_child(row)
	_step_panel(app, properties, mini(at, Tutorial.STEPS.size() - 1), errors)

static func _step_panel(app: Control, properties: VBoxContainer, at: int, errors: Array) -> void:
	var step: Array = Tutorial.STEPS[at]
	var id := str(step[0])
	properties.add_child(Style.heading("ШАГ %d" % (at + 1)))
	var title := Style.label(str(step[2]), 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	properties.add_child(title)
	var text := Style.label(str(step[3]))
	text.name = "TutorialStepText"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	properties.add_child(text)
	if id == "check":
		if not errors.is_empty():
			var note := Style.label("Сейчас ошибок: %d. Откройте «Ошибки» — у каждой есть подсказка." % errors.size())
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			properties.add_child(note)
		var play := Style.primary("Проверить игру")
		play.name = "TutorialPlay"
		play.disabled = not errors.is_empty()
		play.pressed.connect(func():
			app._lesson_played = true
			app._play())
		properties.add_child(play)
		return
	var where := Style.button("Показать где")
	where.name = "TutorialShow"
	where.pressed.connect(func(): show_where(app, id, int(step[1])))
	properties.add_child(where)
	var auto := Style.button("Сделать за меня")
	auto.name = "TutorialDo"
	auto.tooltip_text = "Редактор выполнит шаг сам. Отменяется кнопкой «Отмена»."
	auto.pressed.connect(func():
		app.document.replace(Tutorial.apply(id, app.document.data), "Урок: " + str(step[2]))
		app._render())
	properties.add_child(auto)

## Перейти туда, где делается шаг; урок остаётся в строке состояния.
static func show_where(app: Control, id: String, tab: int) -> void:
	if tab < 0:
		return
	if not await app._save():
		return
	app._tab = tab
	app._face_edit = false
	if id == "score":
		app._category = "resources"
	elif id == "dictionary":
		app._category = "decks"
	app._render()

## Строка состояния вне вкладки урока: какой шаг сейчас.
static func status(app: Control) -> String:
	if app._lesson != Tutorial.WORDS:
		return ""
	var at := Tutorial.current(app.document.data, app.document.issues().errors)
	if at == Tutorial.STEPS.size() - 1 and app._lesson_played:
		return "Урок пройден! Можно менять игру дальше."
	return "Урок · шаг %d: %s" % [at + 1, Tutorial.STEPS[at][2]]
