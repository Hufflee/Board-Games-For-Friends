class_name HubGames
extends RefCounted
## Список настольных игр на стартовом экране. Новая игра = новая запись здесь.

const LIST := [
	{
		"id": "poker",
		"title": "Покер",
		"players": "2–8 игроков",
		"time": "30–60 минут",
		"description": "Техасский холдем под неоновыми огнями! «Классика» — раздачи без конца, проиграл — садись заново. «Спортивный» — сессии по 14 раздач и очки за места. Играйте с друзьями или с ботами.",
		"scene": "res://games/poker/ui/main.tscn",
		"color": Color("ff3fa4"),
		"thickness": 0.06,
	},
	{
		"id": "khorom",
		"title": "Хором!",
		"players": "3–8 игроков",
		"time": "20–30 минут",
		"description": "Пишите ответы на тему и ищите совпадения! «Хором» — очки за одинаковые ответы, «Белая ворона» — за редкие, «Блиц» — шесть тем на скорость. Ответы открываются по очереди.",
		"scene": "res://games/khorom/ui/main.tscn",
		"color": Color("e0794f"),
		"thickness": 0.06,
	},
	{
		"id": "things_in_rings",
		"title": "Things in Rings",
		"players": "2–6 игроков",
		"time": "20 минут",
		"description": "Находите тайные правила цветных колец! Знающий размещает подсказки, искатели раскладывают вещи по пересечениям. Вдвоём — кооператив; смысл проверяет живой игрок.",
		"scene": "res://games/things_in_rings/ui/main.tscn",
		"color": Color("cf765d"),
		"thickness": 0.06,
	},
	{
		"id": "the_gang",
		"title": "The Gang",
		"players": "3–10 игроков",
		"time": "20–30 минут",
		"description": "Кооперативный покер: оцените силу своей руки с помощью фишек, не раскрывая карты. Откройте три хранилища раньше третьей тревоги! Базовые правила для 3–10 игроков.",
		"scene": "res://games/the_gang/ui/main.tscn",
		"color": Color("6b3127"),
		"thickness": 0.06,
	},
	{
		"id": "king_of_12",
		"title": "Дюжина короля",
		"players": "2–8 игроков",
		"time": "20–40 минут",
		"description": "Бросьте двенадцатигранный кристалл и разыграйте союзников в закрытую. Одинаковые карты отменяют друг друга — перехитрите друзей и займите трон!",
		"scene": "res://games/king_of_12/ui/main.tscn",
		"cover_cards": ["knight", "lady", "sorcerer"],
	},
	{
		"id": "perudo",
		"title": "Перудо",
		"players": "2–8 игроков",
		"time": "15–30 минут",
		"description": "Кости лжеца: трясите стакан, тайком смотрите на свои кости и повышайте ставки — или крикните «Дудо!». Единицы — джокеры. Кто сохранит кости, тот и победит.",
		"scene": "res://games/perudo/ui/main.tscn",
		"cover_dice": [1, 6, 6, 3, 5],
	},
	{
		"id": "wavelength",
		"title": "Длина волны",
		"players": "2–8 игроков",
		"time": "30–45 минут",
		"description": "Телепат знает, где на шкале скрытая зона, и даёт подсказку: «Кофе» между «холодным» и «горячим». Команда двигает стрелку — насколько вы на одной волне?",
		"scene": "res://games/wavelength/ui/main.tscn",
		"cover_dial": true,
	},
	{
		"id": "dangerous_words",
		"title": "Опасные слова",
		"players": "4–8 игроков",
		"time": "30–45 минут",
		"description": "Жуткое подземелье: объясняйте слова голосом, обходя ловушки соперников, и одолейте монстра раньше другой команды!",
		"scene": "res://games/dangerous_words/ui/main.tscn",
		"cover_monsters": ["monster_vampire", "monster_mummy", "monster_troll"],
		"thickness": 0.0805,  # на 15 % шире обычной (0.07)
	},
	{
		"id": "hues_and_cues",
		"title": "Hues and Cues",
		"players": "2–8 игроков",
		"time": "30 минут",
		"description": "Опишите цвет одним словом, а потом двумя — друзья ставят фишки на поле из 480 оттенков. Чем ближе к загаданному, тем больше очков. Вдвоём — кооператив на общий счёт.",
		"scene": "res://games/hues_and_cues/ui/main.tscn",
		"cover_hues": true,
	},
	{
		"id": "ready_set_bet",
		"title": "Ready Set Bet",
		"players": "2–8 игроков",
		"time": "45–60 минут",
		"description": "Скачки в реальном времени: ставьте жетоны прямо во время забега — пораньше ради коэффициентов или в последний миг, пока не крикнули «Ставок больше нет!».",
		"scene": "res://games/ready_set_bet/ui/main.tscn",
		"cover_race": true,
	},
	{
		"id": "word_slam",
		"title": "Word Slam",
		"players": "3–8 игроков",
		"time": "30–45 минут",
		"description": "Объясните слово без единого звука — только карточками слов на подставках. Две команды отгадывают одно слово одновременно: кто быстрее?",
		"scene": "res://games/word_slam/ui/main.tscn",
		"cover_words": ["noun:31", "verb:0", "adj:20", "other:13", "noun:44"],
	},
	{
		"id": "tip_top",
		"title": "Тип Топ",
		"players": "4–8 игроков",
		"time": "30 минут",
		"description": "Кооператив: у каждого тайный номер от 1 до 10, все отвечают на тему с нужной силой, а капитан выстраивает ответы по порядку. Единороги или какашки?",
		"scene": "res://games/tip_top/ui/main.tscn",
		"variants": ["tip_top_18", "tip_top"],
		"variant_label": "Обычный",
	},
	{
		"id": "tip_top_18",
		"title": "Тип Топ. Для взрослых",
		"players": "4–8 игроков",
		"time": "30 минут",
		"description": "Тот же «Тип Топ», но темы — 18+: свидания, вечеринки, неловкие ситуации и чёрный юмор. Плюс экспертный вариант.",
		"scene": "res://games/tip_top/ui/main18.tscn",
		"variants": ["tip_top_18", "tip_top"],
		"variant_label": "Для взрослых",
	},
	{
		"id": "not_a_hat",
		"title": "Это не шляпа!",
		"players": "3–8 игроков",
		"time": "15 минут",
		"description": "Дарите подарки рубашкой вверх и называйте их вслух. Запомните, что у кого лежит, — или блефуйте! «Спасибо!» или «Это не шляпа!»?",
		"scene": "res://games/not_a_hat/ui/main.tscn",
		"color": Color("e5007e"),
		"thickness": 0.055,
	},
	{
		"id": "gloom",
		"title": "Gloom",
		"players": "2–4 игрока (5 — с дополнениями)",
		"time": "60 минут",
		"description": "Мрачная викторианская карточная игра: прозрачные карты несчастий складываются прямо на персонажей. Сведите свою семью в могилу самой несчастной — а чужим подарите счастливую жизнь.",
		"scene": "res://games/gloom/ui/main.tscn",
		"color": Color("6e1a22"),
		"variants": ["gloom", "gloomier"],
		"variant_label": "Gloom",
		"settings": {"gl_sets": "base"},
		"thickness": 0.07,  # толщина коробки (важнее пропорций торца)
	},
	{
		"id": "gloomier",
		"play_as": "gloom",  # та же игра, другой набор карт (настройка gl_sets)
		"title": "Gloomier: ночь в Хемлок-Холле",
		"players": "2–5 игроков",
		"time": "60 минут",
		"description": "Самостоятельное продолжение Gloom: все персонажи — обитатели Хемлок-Холла, каждый выбирает себе четверых. Гости переходят из семьи в семью, истории приносят бонусы.",
		"scene": "res://games/gloom/ui/main.tscn",
		"color": Color("4b2560"),
		"thickness": 0.07,
		"variants": ["gloom", "gloomier"],
		"variant_label": "Gloomier",
		"settings": {"gl_sets": "gm"},
	},
	{
		"id": "brodilka",
		"title": "Большая бродилка",
		"players": "2–8 игроков",
		"time": "30–40 минут",
		"description": "Нескучная ходилка для всей семьи: бросайте кубики, открывайте сундуки, закупайтесь в Лавке Джо и пакостите соседям картами «Тадам». Первым доберись до финиш-сейфа!",
		"scene": "res://games/brodilka/ui/main.tscn",
		"color": Color("1f6fb8"),
		"thickness": 0.07,
	},
	{
		"id": "phantom_ink",
		"title": "Призрачные чернила",
		"players": "4–8 игроков",
		"time": "15–30 минут",
		"description": "Два духа знают один тайный предмет. Задавайте вопросы, ловите подсказки по буквам и скажите «Тишина!», прежде чем соперники поймут слишком много.",
		"scene": "res://games/phantom_ink/ui/main.tscn",
		"color": Color("172826"),
		"thickness": 0.07,
	},
	{
		"id": "four_souls",
		"title": "The Binding of Isaac: Four Souls",
		"players": "2–8 игроков",
		"time": "60–120 минут",
		"description": "Лут, сокровища и опасные сделки в подвале Айзека. Первым соберите четыре души; помогайте друзьям или срывайте их планы. Расширенный набор DLC включается в комнате.",
		"scene": "res://games/four_souls/ui/main.tscn",
		"color": Color("5d3430"),
		"thickness": 0.07,
	},
	{
		"id": "stillion",
		"title": "Стиллион",
		"players": "2–8 игроков",
		"time": "10–20 минут",
		"description": "Чёрная пушка с глазами целится в вас и надувается. Успейте напечатать ответ на вопрос, пока она не выстрелила! Чем редче ответ, тем быстрее копится запасная жизнь.",
		"scene": "res://games/stillion/ui/main.tscn",
		"color": Color("1c1a17"),
		"thickness": 0.07,
	},
]

const HUB_SCENE := "res://hub/hub.tscn"


## Под каким id игру запускать (варианты одной игры — одна сцена и одна партия).
static func play_id(g: Dictionary) -> String:
	return str(g.get("play_as", g["id"]))


## Настройки комнаты, которые задаёт вариант игры (Gloom / Gloomier).
static func apply_settings(g: Dictionary) -> void:
	for k in g.get("settings", {}):
		Net.settings[k] = g["settings"][k]


## Игры нет в этой сборке (папка исключена из экспорта): коробка на полке есть, вместо «Играть» — «Скоро».
static func is_release_soon(g: Dictionary) -> bool:
	return not ResourceLoader.exists(str(g.get("scene", "")))


static func by_id(id: String) -> Dictionary:
	for g in LIST:
		if g["id"] == id:
			return g
	return {}
