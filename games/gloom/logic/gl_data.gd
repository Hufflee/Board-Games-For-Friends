class_name GLData
## Карты Gloom (второе издание) с дополнениями «Незваные гости» и «Неспокойные мертвецы» (русская версия).
## Картинки — games/gloom/art/cards: ch<i> — персонажи, g<i> — гости, st<i> — истории,
## d<i> — колода (модификаторы, события, смерти), back — рубашка. Только для личной игры с друзьями.
##
## t: M — модификатор, E — событие, D — безвременная смерть.
## pts: очки в трёх ячейках слева (верх / середина / низ), null — ячейка прозрачная.
## icons: иконки в трёх ячейках справа: "" — прозрачно, "blank" — глухой кружок (закрывает нижние),
##   "persist" — значок постоянного эффекта (нежить, гость): эффект живёт, пока он виден.
## fx: эффекты (см. GLRules). set: base / ug («Незваные гости») / ud («Неспокойные мертвецы») / gm (Gloomier).

const FAMILIES := [
	{"name": "Ферма Блэкуотер", "color": Color("4f8a3a")},
	{"name": "Замок Слогар", "color": Color("b8322a")},
	{"name": "Усадьба Хемлок", "color": Color("7b3f8f")},
	{"name": "Цирк уродов Дарка", "color": Color("d9822b")},
	{"name": "Хемлок-Холл", "color": Color("8e3fa0")},  # Gloomier: каждый выбирает 4 персонажей
]
const GLOOMIER := 4

const CHARS := [
	{"name": "Бальтазар", "family": 0},  # ch0
	{"name": "Энджел", "family": 0},  # ch1
	{"name": "Кузен Мордехай", "family": 0},  # ch2
	{"name": "Уильям Старк", "family": 0},  # ch3
	{"name": "Профессор Елена Слогар", "family": 1},  # ch4
	{"name": "Лорд Слогар", "family": 1},  # ch5
	{"name": "Грогар", "family": 1},  # ch6
	{"name": "Элиас И. Горр", "family": 1},  # ch7
	{"name": "Мелисса Слогар", "family": 1},  # ch8
	{"name": "Лола Веллингтон-Смит", "family": 2},  # ch9
	{"name": "Баттерфилд", "family": 2},  # ch10
	{"name": "Матушка Зарр", "family": 2},  # ch11
	{"name": "Близнецы", "family": 2},  # ch12
	{"name": "Лорд Веллингтон-Смит", "family": 2},  # ch13
	{"name": "Самсон О'Тул", "family": 3},  # ch14
	{"name": "Элиссандра Де'Виль", "family": 3},  # ch15
	{"name": "Дюймовочка", "family": 3},  # ch16
	{"name": "Мистер Хохотун", "family": 3},  # ch17
	{"name": "Дариус Дарк", "family": 3},  # ch18
	{"name": "Старая Мадам", "family": 0},  # ch19
	{"name": "Адрия Бовэ", "family": 4},  # ch20
	{"name": "Август Винтерс", "family": 4},  # ch21
	{"name": "Баттерфилд", "family": 4},  # ch22
	{"name": "Полковник", "family": 4},  # ch23
	{"name": "Эвелин Уай", "family": 4},  # ch24
	{"name": "Вдовствующая леди", "family": 4},  # ch25
	{"name": "Дайр Омен", "family": 4},  # ch26
	{"name": "Флетчер", "family": 4},  # ch27
	{"name": "Гарри Дрейк", "family": 4},  # ch28
	{"name": "Инспектор Джонсон", "family": 4},  # ch29
	{"name": "Дженни Найтингейл", "family": 4},  # ch30
	{"name": "Леди Лола", "family": 4},  # ch31
	{"name": "Лорд Веллингтон-Смит", "family": 4},  # ch32
	{"name": "Мадам Зора", "family": 4},  # ch33
	{"name": "Пруденс", "family": 4},  # ch34
	{"name": "Салли Тру", "family": 4},  # ch35
	{"name": "Сэр Бромли", "family": 4},  # ch36
	{"name": "Софи", "family": 4},  # ch37
	{"name": "Текс", "family": 4},  # ch38
	{"name": "Близнецы", "family": 4},  # ch39
]

const ICON_NAMES := {"beast": "Зверь", "skull": "Смерть", "heart": "Любовь", "goblet": "Кубок", "coin": "Деньги", "duck": "Утка", "magnifier": "Тайна", "dagger": "Убийство", "swirl": "Безумие"}

## Незваные гости: начинают без хозяина в центре стола и «следуют» (follows) за картами:
## "D" — за безвременной смертью, "icon:X" — за картой с иконкой X. Переходят в семью персонажа,
## на которого сыграли такую карту, со всеми своими картами.
const GUESTS := [
	{"name": "Скорбящая Вдова", "pts": [null, null, null], "icons": ["persist", "dagger", ""], "follows": "icon:dagger", "fx": ["no_heart_mods_on_family"], "set": "ug"},  # g0
	{"name": "Несчастный Холмс", "pts": [15, 15, 15], "icons": ["persist", "magnifier", ""], "follows": "D", "fx": [], "set": "ug"},  # g1
	{"name": "Бедные Родственники", "pts": [null, null, null], "icons": ["persist", "swirl", ""], "follows": "icon:coin", "fx": ["no_ud_on_self"], "set": "ug"},  # g2
	{"name": "Мерзкий Дядя", "pts": [null, null, null], "icons": ["persist", "goblet", ""], "follows": "icon:goblet", "fx": ["draw_from_opponent"], "set": "ug"},  # g3
	{"name": "Усатик", "pts": [-5, -5, -5], "icons": ["persist", "beast", ""], "follows": "", "fx": ["ud_second_on:skull,beast"], "set": "ug"},  # g4
	{"name": "Холостяк", "pts": [null, null, 10], "icons": ["persist", "", ""], "follows": "icon:heart", "fx": ["no_move_if_heart"], "set": "gm"},  # g5
	{"name": "Бальтазар", "pts": [10, null, null], "icons": ["persist", "beast", "goblet"], "follows": "icon:goblet", "fx": [], "set": "gm"},  # g6
	{"name": "Чёрная Кошка", "pts": [null, -10, 10], "icons": ["persist", "", "coin"], "follows": "icon:coin", "fx": ["draw_from_opponent"], "set": "gm"},  # g7
	{"name": "Бадди Бартлби", "pts": [10, 10, null], "icons": ["persist", "coin", "heart"], "follows": "icon:heart", "fx": ["final_per_family_icon:heart"], "set": "gm"},  # g8
	{"name": "Полковник", "pts": [10, 10, null], "icons": ["persist", "", ""], "follows": "icon:beast", "fx": ["no_beast_mods_on_family"], "set": "gm"},  # g9
	{"name": "Инспектор", "pts": [null, null, null], "icons": ["persist", "magnifier", ""], "follows": "icon:magnifier", "fx": ["no_ud_for_owner"], "set": "gm"},  # g10
	{"name": "Леди Лола", "pts": [null, null, null], "icons": ["persist", "", "heart"], "follows": "icon:heart,goblet", "fx": ["no_events"], "set": "gm"},  # g11
	{"name": "Безумный монах", "pts": [null, null, null], "icons": ["persist", "", "skull"], "follows": "icon:skull", "fx": ["no_ud_on_self"], "set": "gm"},  # g12
	{"name": "Мадам Зора", "pts": [null, null, -10], "icons": ["persist", "", "skull"], "follows": "D", "fx": ["first_mod_on_dead"], "set": "gm"},  # g13
	{"name": "Таинственная горничная", "pts": [null, null, -10], "icons": ["persist", "dagger", ""], "follows": "icon:magnifier", "fx": ["limit+per_family_icon:dagger"], "set": "gm"},  # g14
	{"name": "Профессор Уай", "pts": [null, null, -10], "icons": ["persist", "", ""], "follows": "icon:magnifier", "fx": ["draw_from_discard_one"], "set": "gm"},  # g15
	{"name": "Салли Тру", "pts": [10, 10, 10], "icons": ["persist", "magnifier", ""], "follows": "icon:dagger", "fx": ["limit+per_family_icon:magnifier"], "set": "gm"},  # g16
	{"name": "Близнецы", "pts": [null, null, 10], "icons": ["persist", "", "skull"], "follows": "icon:skull", "fx": [], "set": "gm"},  # g17
	{"name": "Злодей-камердинер", "pts": [null, null, null], "icons": ["persist", "dagger", ""], "follows": "icon:dagger", "fx": ["free_mod_start:dagger"], "set": "gm"},  # g18
]

## Истории: забирает действием тот, у чьей семьи (живые и мёртвые персонажи) видны иконки req
## (каждая — у отдельного персонажа); у владельца — больше нет. pts — очки в конце игры.
const STORIES := [
	{"name": "Сердце сплетника", "req": ["heart", "heart"], "pts": [null, null, null], "fx": ["ud_second"], "set": "ud"},  # st0
	{"name": "Холодильник доктора Кэлигари", "req": ["goblet", "goblet"], "pts": [null, null, null], "fx": ["limit+per_family_icon:goblet"], "set": "ud"},  # st1
	{"name": "Мрачные перспективы", "req": ["coin", "coin"], "pts": [null, null, null], "fx": ["draw_extra:1"], "set": "ud"},  # st2
	{"name": "Карикатура Дориана Грея", "req": ["skull", "skull"], "pts": [-20, null, null], "fx": ["opp_no_events_my_turn"], "set": "ud"},  # st3
	{"name": "Чуланчик доктора Моро", "req": ["beast", "beast"], "pts": [null, null, null], "fx": ["final_per_char:beast,duck"], "set": "ud"},  # st4
	{"name": "Алебастровый альбатрос", "req": ["coin"], "pts": [-20, null, null], "fx": ["limit+per_family_char:coin"], "set": "gm"},  # st5
	{"name": "Разбитое сердце", "req": ["heart"], "pts": [null, null, null], "fx": ["final_per_dead:heart:-15"], "set": "gm"},  # st6
	{"name": "Последнее дело", "req": ["magnifier"], "pts": [-10, null, null], "fx": ["free_mod_start:magnifier"], "set": "gm"},  # st7
	{"name": "Чёрный котёнок", "req": ["skull"], "pts": [-10, null, null], "fx": ["churn_on_mod:beast"], "set": "gm"},  # st8
	{"name": "Вот так ворон", "req": ["beast"], "pts": [-15, null, null], "fx": ["draw_on_mod:skull"], "set": "gm"},  # st9
	{"name": "Убийца", "req": ["dagger", "dagger"], "pts": [-10, null, null], "fx": ["ud_second_if:dagger"], "set": "gm"},  # st10
]
const STORY_MAX := 1  # одновременно — только одна история

const CARDS := [
	{"t": "E", "name": "Бурная ночка", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["stormy"], "set": "base"},  # d0
	{"t": "D", "name": "Сожран хорьками", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:beast"], "set": "base"},  # d1
	{"t": "M", "name": "Пышная свадьба", "pts": [0, null, 15], "icons": ["", "", "heart"], "fx": ["limit+1"], "set": "base"},  # d2
	{"t": "D", "name": "Не вернулся", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:beast"], "set": "base"},  # d3
	{"t": "M", "name": "Ужален ужами", "pts": [-10, -10, null], "icons": ["", "", "beast"], "fx": [], "set": "base"},  # d4
	{"t": "M", "name": "Встретил привидений", "pts": [-10, null, -20], "icons": ["", "", "skull"], "fx": ["discard:3"], "set": "base"},  # d5
	{"t": "D", "name": "Умер без забот", "pts": [0, 0, 0], "icons": ["blank", "", ""], "fx": [], "set": "base"},  # d6
	{"t": "M", "name": "Упал в колодец", "pts": [-10, null, null], "icons": ["", "", ""], "fx": ["free_ud_if_neg"], "set": "base"},  # d7
	{"t": "M", "name": "Заломан ламантином", "pts": [-20, null, null], "icons": ["", "", "beast"], "fx": ["skip_draw"], "set": "base"},  # d8
	{"t": "M", "name": "Старость не радость", "pts": [-20, null, null], "icons": ["", "", "skull"], "fx": ["right_discard_random:2"], "set": "base"},  # d9
	{"t": "M", "name": "Прятался от полтергейстов", "pts": [null, -10, -10], "icons": ["", "", "skull"], "fx": ["give_right:2"], "set": "base"},  # d10
	{"t": "M", "name": "Устроил пикник в парке", "pts": [10, 5, null], "icons": ["", "", "goblet"], "fx": ["draw:2"], "set": "base"},  # d11
	{"t": "M", "name": "Нашёл любовь у озера", "pts": [0, null, 15], "icons": ["", "", "heart"], "fx": ["limit+1"], "set": "base"},  # d12
	{"t": "M", "name": "Заколот дикобразами", "pts": [-10, -5, null], "icons": ["", "", "beast"], "fx": [], "set": "base"},  # d13
	{"t": "E", "name": "Неприятный сюрприз", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["remove_top_mod"], "set": "base"},  # d14
	{"t": "M", "name": "Проклят королевой", "pts": [null, -15, -20], "icons": ["", "", ""], "fx": ["discard_hand"], "set": "base"},  # d15
	{"t": "M", "name": "Расстроен поносом", "pts": [-15, -10, null], "icons": ["", "", "skull"], "fx": ["left_discard_random:2"], "set": "base"},  # d16
	{"t": "D", "name": "Умер старым и одиноким", "pts": [-15, null, null], "icons": ["blank", "", ""], "fx": ["not_on:heart"], "set": "base"},  # d17
	{"t": "E", "name": "Начать всё сначала", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["remove_all_mods"], "set": "base"},  # d18
	{"t": "M", "name": "Заразился туберкулёзом", "pts": [-15, null, -15], "icons": ["", "", "skull"], "fx": ["limit-1"], "set": "base"},  # d19
	{"t": "M", "name": "Застрял в поезде", "pts": [-20, null, null], "icons": ["", "", ""], "fx": ["no_events"], "set": "base"},  # d20
	{"t": "M", "name": "Заставили пить", "pts": [-15, null, null], "icons": ["", "", "goblet"], "fx": ["discard:1"], "set": "base"},  # d21
	{"t": "M", "name": "Очарован утятами", "pts": [10, 0, null], "icons": ["", "", "duck"], "fx": ["draw_per_icon:duck"], "set": "base"},  # d22
	{"t": "M", "name": "Ужаснулся пудингом", "pts": [-5, -5, null], "icons": ["", "", "goblet"], "fx": [], "set": "base"},  # d23
	{"t": "M", "name": "Покусан пчёлами", "pts": [null, -15, null], "icons": ["", "", "beast"], "fx": [], "set": "base"},  # d24
	{"t": "D", "name": "Выпил слишком много рома", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:goblet"], "set": "base"},  # d25
	{"t": "D", "name": "Убит наследником", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:heart,coin"], "set": "base"},  # d26
	{"t": "M", "name": "Отличился в покере", "pts": [15, null, null], "icons": ["", "", "coin"], "fx": ["draw:1"], "set": "base"},  # d27
	{"t": "M", "name": "Получил наследство", "pts": [null, 15, null], "icons": ["", "", "coin"], "fx": ["draw:2"], "set": "base"},  # d28
	{"t": "M", "name": "Напуган мышами", "pts": [null, -15, null], "icons": ["", "", "beast"], "fx": [], "set": "base"},  # d29
	{"t": "D", "name": "Сожжён на костре", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["ud_second"], "set": "base"},  # d30
	{"t": "M", "name": "Избран в парламент", "pts": [0, 15, null], "icons": ["", "", ""], "fx": ["draw:2"], "set": "base"},  # d31
	{"t": "E", "name": "Воображаемый друг", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["remove_living_char"], "set": "base"},  # d32
	{"t": "D", "name": "Разорван на куски", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:beast"], "set": "base"},  # d33
	{"t": "M", "name": "Обманут торговцем", "pts": [null, -10, null], "icons": ["", "", "coin"], "fx": ["give_right:1"], "set": "base"},  # d34
	{"t": "M", "name": "Порван пуделями", "pts": [-15, null, null], "icons": ["", "", "beast"], "fx": [], "set": "base"},  # d35
	{"t": "M", "name": "Опозорился на танцах", "pts": [null, -20, null], "icons": ["", "", "blank"], "fx": [], "set": "base"},  # d36
	{"t": "M", "name": "Обокрал мертвеца", "pts": [null, null, -15], "icons": ["", "", "coin"], "fx": [], "set": "base"},  # d37
	{"t": "E", "name": "Поворот судьбы", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["swap_top_mod_from_hand"], "set": "base"},  # d38
	{"t": "M", "name": "Оголодал в бурю", "pts": [-10, -10, null], "icons": ["", "", "goblet"], "fx": [], "set": "base"},  # d39
	{"t": "M", "name": "Назревший фурункул", "pts": [null, null, -10], "icons": ["", "", "skull"], "fx": ["give_right:1"], "set": "base"},  # d40
	{"t": "M", "name": "Прославился на пиру", "pts": [0, 10, null], "icons": ["", "", "goblet"], "fx": ["draw:2"], "set": "base"},  # d41
	{"t": "M", "name": "Переломал все кости", "pts": [-20, null, null], "icons": ["", "", ""], "fx": [], "set": "base"},  # d42
	{"t": "D", "name": "Задохнулся", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:beast"], "set": "base"},  # d43
	{"t": "M", "name": "Раздразнил тигров", "pts": [-20, -10, null], "icons": ["", "", "beast"], "fx": ["skip_draw"], "set": "base"},  # d44
	{"t": "M", "name": "Увлечён напитком", "pts": [0, 10, null], "icons": ["", "", "goblet"], "fx": ["discard:1"], "set": "base"},  # d45
	{"t": "E", "name": "Второй шанс", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["second_chance"], "set": "base"},  # d46
	{"t": "M", "name": "Мучался от язвы", "pts": [-15, null, -15], "icons": ["", "", "skull"], "fx": ["limit-1"], "set": "base"},  # d47
	{"t": "M", "name": "Покалечен кредиторами", "pts": [null, -20, null], "icons": ["", "", "coin"], "fx": ["right_take_random:2"], "set": "base"},  # d48
	{"t": "M", "name": "Стал почётным горожанином", "pts": [0, 15, null], "icons": ["", "", ""], "fx": ["limit+1"], "set": "base"},  # d49
	{"t": "D", "name": "Сожжён дотла", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:goblet"], "set": "base"},  # d50
	{"t": "D", "name": "Съеден изнутри", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:skull"], "set": "base"},  # d51
	{"t": "E", "name": "Напустить туману", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["cancel_event"], "set": "base"},  # d52
	{"t": "M", "name": "Ужасный отпуск", "pts": [null, -20, -20], "icons": ["", "", "heart"], "fx": ["discard_hand", "skip_draw"], "set": "base"},  # d53
	{"t": "M", "name": "Сошёл с ума", "pts": [-10, null, null], "icons": ["", "", "skull"], "fx": ["discard_per_mod"], "set": "base"},  # d54
	{"t": "M", "name": "Налакался рома", "pts": [-15, null, -10], "icons": ["", "", "goblet"], "fx": ["skip_draw"], "set": "base"},  # d55
	{"t": "D", "name": "Утонул в трясине", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:skull"], "set": "base"},  # d56
	{"t": "M", "name": "Испуган звуками топора", "pts": [-20, null, null], "icons": ["", "", "beast"], "fx": [], "set": "base"},  # d57
	{"t": "M", "name": "Избит бедняками", "pts": [-15, null, null], "icons": ["", "", ""], "fx": [], "set": "base"},  # d58
	{"t": "E", "name": "Трагическое недоразумение", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["swap_top_mods"], "set": "base"},  # d59
	{"t": "D", "name": "Упал с высоты", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:heart,coin"], "set": "base"},  # d60
	{"t": "D", "name": "Сгинул в тумане", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:skull"], "set": "base"},  # d61
	{"t": "M", "name": "Покорён цирком", "pts": [10, null, null], "icons": ["", "", "beast"], "fx": [], "set": "base"},  # d62
	{"t": "E", "name": "Пока смерть не разлучит нас", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["ud_from_discard"], "set": "base"},  # d63
	{"t": "M", "name": "Спал без забот", "pts": [null, 10, null], "icons": ["", "", "blank"], "fx": [], "set": "base"},  # d64
	{"t": "M", "name": "Упал в колодец", "pts": [null, -20, -20], "icons": ["", "", "heart"], "fx": ["free_ud_if_neg"], "set": "base"},  # d65
	{"t": "M", "name": "Попал в тюрьму", "pts": [-20, null, null], "icons": ["", "", ""], "fx": ["no_events"], "set": "base"},  # d66
	{"t": "D", "name": "Умер от отчаяния", "pts": [null, null, -15], "icons": ["blank", "", ""], "fx": ["discard_hand"], "set": "base"},  # d67
	{"t": "D", "name": "Стал начинкой пирога", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:goblet"], "set": "base"},  # d68
	{"t": "D", "name": "Столкнут с лестницы", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:heart,coin"], "set": "base"},  # d69
	{"t": "M", "name": "Благословлён епископом", "pts": [0, null, 20], "icons": ["", "", "heart"], "fx": ["refresh_hand"], "set": "base"},  # d70
	{"t": "D", "name": "Подавился костью", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:goblet"], "set": "base"},  # d71
	{"t": "D", "name": "Съеден медведями", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:beast"], "set": "base"},  # d72
	{"t": "M", "name": "Поражён гангреной", "pts": [-15, null, null], "icons": ["", "", "skull"], "fx": [], "set": "base"},  # d73
	{"t": "E", "name": "Корень всех зол", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["root_of_evil"], "set": "base"},  # d74
	{"t": "M", "name": "Нашёл личинок в мясе", "pts": [-15, null, null], "icons": ["", "", "goblet"], "fx": ["discard:1"], "set": "base"},  # d75
	{"t": "D", "name": "Умер от кори", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:skull"], "set": "base"},  # d76
	{"t": "M", "name": "Вовлечён в скандал", "pts": [null, -25, null], "icons": ["", "", ""], "fx": ["discard_hand"], "set": "base"},  # d77
	{"t": "M", "name": "Изгнан из общества", "pts": [-15, -15, -15], "icons": ["", "", ""], "fx": ["discard_hand", "skip_draw"], "set": "base"},  # d78
	{"t": "M", "name": "Сглазили цыгане", "pts": [-15, -15, null], "icons": ["", "", "skull"], "fx": ["limit-1"], "set": "base"},  # d79
	{"t": "M", "name": "Замучан детишками", "pts": [-10, null, null], "icons": ["", "", ""], "fx": [], "set": "base"},  # d80
	{"t": "M", "name": "Заболел оспой", "pts": [-15, -15, null], "icons": ["", "", "skull"], "fx": ["limit-1"], "set": "base"},  # d81
	{"t": "M", "name": "Овдовел на свадьбе", "pts": [null, null, -25], "icons": ["", "", "blank"], "fx": ["only_on:heart"], "set": "base"},  # d82
	{"t": "M", "name": "Вычеркнут из завещания", "pts": [null, -20, null], "icons": ["", "", "coin"], "fx": ["skip_draw"], "set": "base"},  # d83
	{"t": "M", "name": "Отравился лососем", "pts": [null, -10, null], "icons": ["", "", "goblet"], "fx": ["discard_per_mod"], "set": "base"},  # d84
	{"t": "M", "name": "Ошеломительно помолвлен", "pts": [0, null, 20], "icons": ["", "", "heart"], "fx": ["draw:2"], "set": "base"},  # d85
	{"t": "E", "name": "Старикам закон не писан", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra_plays:2"], "set": "base"},  # d86
	{"t": "M", "name": "Отлучён от церкви", "pts": [-10, null, -15], "icons": ["", "", "blank"], "fx": ["limit-1"], "set": "base"},  # d87
	{"t": "M", "name": "Единственный подозреваемый", "pts": [null, -15, null], "icons": ["", "dagger", ""], "fx": ["guests_uncontrolled"], "set": "ug"},  # d88 ug0
	{"t": "M", "name": "Истощён клещами", "pts": [-15, null, null], "icons": ["", "", ""], "fx": ["free_ud_if_icon:beast"], "set": "ug"},  # d89 ug1
	{"t": "M", "name": "Спасён грызунами", "pts": [15, 15, null], "icons": ["", "magnifier", "beast"], "fx": ["tuck_mods_without:beast"], "set": "ug"},  # d90 ug2
	{"t": "M", "name": "Уговорён попугаем", "pts": [null, -10, -15], "icons": ["", "duck", "beast"], "fx": ["left_plays_random_from_hand"], "set": "ug"},  # d91 ug3
	{"t": "M", "name": "Истерзан кошмарами", "pts": [null, null, -15], "icons": ["", "", "skull"], "fx": ["take_ud_from_discard"], "set": "ug"},  # d92 ug4
	{"t": "M", "name": "Одурманен морфием", "pts": [-15, null, -15], "icons": ["", "", "skull"], "fx": ["limit-1"], "set": "ug"},  # d93 ug5
	{"t": "M", "name": "Пожёван мастифами", "pts": [-20, null, null], "icons": ["", "", "beast"], "fx": [], "set": "ug"},  # d94 ug6
	{"t": "M", "name": "Ограблен квартирантами", "pts": [-10, -15, null], "icons": ["", "", "coin"], "fx": ["guests_uncontrolled"], "set": "ug"},  # d95 ug7
	{"t": "M", "name": "Унижен на приёме", "pts": [-15, -15, null], "icons": ["", "magnifier", "goblet"], "fx": ["opponents_take_random:1"], "set": "ug"},  # d96 ug8
	{"t": "M", "name": "Изнурён гостями", "pts": [-10, -10, null], "icons": ["", "", ""], "fx": ["take_uncontrolled_guest"], "set": "ug"},  # d97 ug9
	{"t": "M", "name": "Оштрафован федералами", "pts": [-15, -15, null], "icons": ["", "magnifier", "coin"], "fx": ["opponents_draw:1"], "set": "ug"},  # d98 ug10
	{"t": "M", "name": "Обречён из-за пьянства", "pts": [null, -15, null], "icons": ["", "", ""], "fx": ["free_ud_if_icon:goblet"], "set": "ug"},  # d99 ug11
	{"t": "M", "name": "Лишён десерта", "pts": [-5, -5, null], "icons": ["", "", "goblet"], "fx": [], "set": "ug"},  # d100 ug12
	{"t": "M", "name": "Объелся пампушек", "pts": [-10, null, null], "icons": ["", "", "goblet"], "fx": [], "set": "ug"},  # d101 ug13
	{"t": "M", "name": "Приговорён судом", "pts": [-10, -10, null], "icons": ["", "", ""], "fx": ["left_limit+1"], "set": "ug"},  # d102 ug14
	{"t": "M", "name": "Надут товарищем", "pts": [null, -15, -20], "icons": ["", "", ""], "fx": ["opponents_take_random:1"], "set": "ug"},  # d103 ug15
	{"t": "M", "name": "Пойман полицией", "pts": [-20, null, null], "icons": ["", "magnifier", ""], "fx": ["discard_events_from_hand"], "set": "ug"},  # d104 ug16
	{"t": "M", "name": "Обеспокоен банши", "pts": [null, null, -10], "icons": ["", "swirl", ""], "fx": ["free_ud_if_icon:skull"], "set": "ug"},  # d105 ug17
	{"t": "M", "name": "Решил посмотреть мир", "pts": [null, -20, null], "icons": ["", "", ""], "fx": ["becomes_guest"], "set": "ug"},  # d106 ug18
	{"t": "M", "name": "Поплохело на чаепитии", "pts": [-20, null, -20], "icons": ["", "", "goblet"], "fx": ["discard_hand"], "set": "ug"},  # d107 ug19
	{"t": "M", "name": "Зарезал незнакомца", "pts": [-20, null, null], "icons": ["", "dagger", ""], "fx": ["free_ud_on_guest"], "set": "ug"},  # d108 ug20
	{"t": "M", "name": "Угостил родственника", "pts": [null, 10, null], "icons": ["", "", ""], "fx": ["take_any_guest"], "set": "ug"},  # d109 ug21
	{"t": "M", "name": "Соблазнил любовницу", "pts": [0, null, 15], "icons": ["", "", "heart"], "fx": ["take_any_guest"], "set": "ug"},  # d110 ug22
	{"t": "M", "name": "Свидание в поезде", "pts": [0, null, 10], "icons": ["", "", "heart"], "fx": ["draw_per_icon:heart"], "set": "ug"},  # d111 ug23
	{"t": "M", "name": "Привёл нахлебника", "pts": [15, null, null], "icons": ["", "", ""], "fx": ["take_any_guest"], "set": "ug"},  # d112 ug24
	{"t": "M", "name": "Занял у контрабандиста", "pts": [-10, -15, null], "icons": ["", "", "coin"], "fx": ["opponents_limit+1"], "set": "ug"},  # d113 ug25
	{"t": "D", "name": "Убит трактирщиком", "pts": [null, null, null], "icons": ["blank", "dagger", ""], "fx": ["extra10_if_guest"], "set": "ug"},  # d114 ug26
	{"t": "D", "name": "Застрелен на дуэли", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:coin,heart"], "set": "ug"},  # d115 ug27
	{"t": "D", "name": "Перетёрт в кашицу", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:goblet"], "set": "ug"},  # d116 ug28
	{"t": "D", "name": "Последний раз видели на берегу", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:magnifier,dagger"], "set": "ug"},  # d117 ug29
	{"t": "D", "name": "Убит благими намерениями", "pts": [15, null, null], "icons": ["blank", "", ""], "fx": ["extra20:heart"], "set": "ug"},  # d118 ug30
	{"t": "D", "name": "Пал жертвой пожеланий", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:skull"], "set": "ug"},  # d119 ug31
	{"t": "D", "name": "Залёг на дно", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:beast"], "set": "ug"},  # d120 ug32
	{"t": "D", "name": "Ювелирно убит", "pts": [null, null, null], "icons": ["blank", "dagger", ""], "fx": ["left_limit+1_if_coin"], "set": "ug"},  # d121 ug33
	{"t": "E", "name": "Хлопоты путешественника", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["draw2_per_guest_play_any"], "set": "ug"},  # d122 ug34
	{"t": "E", "name": "Злонамеренный маскарад", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["swap_all_mods_with_guest"], "set": "ug"},  # d123 ug35
	{"t": "E", "name": "Подозрительный отъезд", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["remove_own_guest_cancel"], "set": "ug"},  # d124 ug36
	{"t": "E", "name": "Призрачное новоселье", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["take_guest_from_family"], "set": "ug"},  # d125 ug37
	{"t": "E", "name": "Ненадёжные друзья", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["move_guest_between"], "set": "ug"},  # d126 ug38
	{"t": "E", "name": "Вечеринка мертвеца", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["mod_on_dead"], "set": "ug"},  # d127 ug39
	{"t": "M", "name": "Отведал снадобья", "pts": [15, null, null], "icons": ["", "", "goblet"], "fx": ["take_event_from_discard"], "set": "ud"},  # d128 ud0
	{"t": "E", "name": "В два раза ярче", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["unlimited_plays_discard_each"], "set": "ud"},  # d129 ud1
	{"t": "M", "name": "Высмеян одноклассниками", "pts": [null, -20, null], "icons": ["", "magnifier", ""], "fx": ["left_discard_random_per_icon:magnifier"], "set": "ud"},  # d130 ud2
	{"t": "M", "name": "Проснулся уткой", "pts": [10, null, -10], "icons": ["persist", "duck", "beast"], "fx": ["undead", "always_icons:duck,beast"], "set": "ud"},  # d131 ud3
	{"t": "D", "name": "И всё же стало ещё хуже", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["take_random_each_opponent_if:goblet"], "set": "ud"},  # d132 ud4
	{"t": "M", "name": "Охотился на крестьян", "pts": [-10, -20, null], "icons": ["", "dagger", "goblet"], "fx": ["discard_hand", "take_random_each_opponent"], "set": "ud"},  # d133 ud5
	{"t": "D", "name": "Стал лёгкой закуской", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra20:goblet,beast"], "set": "ud"},  # d134 ud6
	{"t": "M", "name": "Предпочёл стать гулем", "pts": [null, 10, -10], "icons": ["persist", "", "skull"], "fx": ["undead", "draw_from_discard"], "set": "ud"},  # d135 ud7
	{"t": "D", "name": "Настигнут стаей", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["free_ud_this_turn_if:beast"], "set": "ud"},  # d136 ud8
	{"t": "M", "name": "Пугал горожан", "pts": [-15, null, null], "icons": ["", "dagger", ""], "fx": ["everyone_discard:1"], "set": "ud"},  # d137 ud9
	{"t": "M", "name": "Оживил родственника", "pts": [-15, -15, -15], "icons": ["", "", "skull"], "fx": ["revive_own_dead"], "set": "ud"},  # d138 ud10
	{"t": "M", "name": "Прятался от Хайда", "pts": [-30, -10, null], "icons": ["", "", "beast"], "fx": ["right_takes_chosen:1"], "set": "ud"},  # d139 ud11
	{"t": "M", "name": "Закусил пауками", "pts": [-5, null, -5], "icons": ["", "", "goblet"], "fx": [], "set": "ud"},  # d140 ud12
	{"t": "M", "name": "Навестил Ван Хельсинга", "pts": [null, null, 25], "icons": ["", "magnifier", "goblet"], "fx": ["discard_mod_from_undead"], "set": "ud"},  # d141 ud13
	{"t": "E", "name": "Пересадка мозга", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["swap_living_chars_with_opponent"], "set": "ud"},  # d142 ud14
	{"t": "E", "name": "Расхищение могил", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["play_event_or_undead_from_discard"], "set": "ud"},  # d143 ud15
	{"t": "E", "name": "Неожиданный поворот", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["claim_any_story_then_free_play"], "set": "ud"},  # d144 ud16
	{"t": "M", "name": "Стал кровососом", "pts": [-10, null, null], "icons": ["persist", "", "skull"], "fx": ["undead", "draw_one_from_chosen_opponent"], "set": "ud"},  # d145 ud17
	{"t": "M", "name": "Наплевал на закон", "pts": [null, -15, null], "icons": ["", "magnifier", ""], "fx": ["discard2_per_family_icon:magnifier"], "set": "ud"},  # d146 ud18
	{"t": "M", "name": "Создал монстра", "pts": [null, null, -15], "icons": ["", "", "beast"], "fx": ["right_free_mod_with:beast"], "set": "ud"},  # d147 ud19
	{"t": "D", "name": "Забрал всё с собой", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["limit+1_if:coin"], "set": "ud"},  # d148 ud20
	{"t": "M", "name": "Выпил с Дракулой", "pts": [-10, null, -25], "icons": ["", "", "goblet"], "fx": ["left_takes_chosen:1"], "set": "ud"},  # d149 ud21
	{"t": "M", "name": "Задержался в лагуне", "pts": [null, 0, 15], "icons": ["", "", "heart"], "fx": ["story_wild_icon"], "set": "ud"},  # d150 ud22
	{"t": "M", "name": "Не отдал душу", "pts": [0, null, -10], "icons": ["persist", "", "skull"], "fx": ["undead", "hand_protected"], "set": "ud"},  # d151 ud23
	{"t": "M", "name": "Воссоздан с картины", "pts": [null, -10, null], "icons": ["persist", "", "skull"], "fx": ["undead", "discard_to_remove_top"], "set": "ud"},  # d152 ud24
	{"t": "M", "name": "Изобрёл невидимость", "pts": [10, 10, 10], "icons": ["persist", "blank", "blank"], "fx": ["undead", "owner_only_mods"], "set": "ud"},  # d153 ud25
	{"t": "M", "name": "Мерцание в ночи", "pts": [0, null, 15], "icons": ["", "", "heart"], "fx": ["limit+1"], "set": "ud"},  # d154 ud26
	{"t": "M", "name": "Мастерски мумифицирован", "pts": [null, 10, -10], "icons": ["persist", "", "coin"], "fx": ["undead", "limit+per_family_icon:coin"], "set": "ud"},  # d155 ud27
	{"t": "M", "name": "Услышал зов сердца", "pts": [-15, -10, null], "icons": ["", "dagger", ""], "fx": ["discard2_per_family_icon:dagger"], "set": "ud"},  # d156 ud28
	{"t": "M", "name": "Любовь из пробирки", "pts": [null, 10, 10], "icons": ["", "", "heart"], "fx": ["limit+1"], "set": "ud"},  # d157 ud29
	{"t": "M", "name": "Похоронен заживо", "pts": [null, -10, null], "icons": ["", "dagger", "skull"], "fx": ["free_ud_if_neg"], "set": "ud"},  # d158 ud30
	{"t": "M", "name": "Свихнулся при свете луны", "pts": [-20, null, -20], "icons": ["", "", "beast"], "fx": ["discard2_per_family_icon:beast", "skip_draw"], "set": "ud"},  # d159 ud31
	{"t": "M", "name": "Увлечён рассчётами", "pts": [null, -25, -25], "icons": ["", "", "coin"], "fx": ["reveal2_remove_or_discard_hand"], "set": "ud"},  # d160 ud32
	{"t": "M", "name": "Свадьба с оборотнем", "pts": [-5, null, 20], "icons": ["", "beast", "heart"], "fx": ["draw_per_icon:beast"], "set": "ud"},  # d161 ud33
	{"t": "M", "name": "Одурачен призраком", "pts": [-15, null, null], "icons": ["", "", ""], "fx": ["discard_mod_below"], "set": "ud"},  # d162 ud34
	{"t": "M", "name": "Отобедал деканом", "pts": [0, 20, null], "icons": ["", "", "goblet"], "fx": ["take2_random_from_chosen"], "set": "ud"},  # d163 ud35
	{"t": "M", "name": "Влюбился в горбуна", "pts": [-15, -15, null], "icons": ["", "", "heart"], "fx": ["limit-1"], "set": "ud"},  # d164 ud36
	{"t": "M", "name": "Вылечен Франкенштейном", "pts": [-20, null, null], "icons": ["", "", ""], "fx": ["discard_mod_below"], "set": "ud"},  # d165 ud37
	{"t": "M", "name": "Подделал состояние", "pts": [null, -15, null], "icons": ["", "", "coin"], "fx": ["take_any_from_discard", "skip_draw"], "set": "ud"},  # d166 ud38
	{"t": "M", "name": "Уснул в сонной лощине", "pts": [10, null, null], "icons": ["", "", "blank"], "fx": ["refresh:2"], "set": "ud"},  # d167 ud39
	{"t": "M", "name": "Обеспокоен волками", "pts": [-10, null, null], "icons": ["", "", "beast"], "fx": ["free_ud_if_neg"], "set": "ud"},  # d168 ud40
	{"t": "D", "name": "Скончался от проклятия", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["others_give_events_if:skull"], "set": "ud"},  # d169 ud41
	{"t": "M", "name": "Отдыхал с вороном", "pts": [10, 10, null], "icons": ["", "", "duck"], "fx": ["draw2_per_family_icon:duck"], "set": "ud"},  # d170 ud42
	{"t": "E", "name": "Ужасающее предложение", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["swap_hands"], "set": "ud"},  # d171 ud43
	{"t": "M", "name": "Пролез через крипту", "pts": [-10, -10, null], "icons": ["", "dagger", "coin"], "fx": ["draw2_show_skull_beast_discard_hand"], "set": "ud"},  # d172 ud44
	{"t": "M", "name": "Потрёпан на колокольне", "pts": [-25, null, null], "icons": ["", "", "beast"], "fx": ["discard_per_family_icon:beast"], "set": "ud"},  # d173 ud45
	{"t": "E", "name": "Бич монстров", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["free_ud_or_remove_undead"], "set": "ud"},  # d174 ud46
	{"t": "E", "name": "Выпустить гончих", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["everyone_removes_own_char"], "set": "ud"},  # d175 ud47
	{"t": "M", "name": "Тискал котиков", "pts": [10, 0, null], "icons": ["", "blank", "beast"], "fx": ["draw:2"], "set": "gm"},  # d176 2500
	{"t": "M", "name": "Танцевал с герцогиней", "pts": [0, 15, null], "icons": ["", "", "heart"], "fx": ["limit+1"], "set": "gm"},  # d177 2501
	{"t": "M", "name": "Нашёл дневник", "pts": [0, null, 20], "icons": ["", "magnifier", ""], "fx": ["claim_any_story"], "set": "gm"},  # d178 2502
	{"t": "M", "name": "Подслушал врага", "pts": [0, 10, null], "icons": ["", "magnifier", "dagger"], "fx": ["take_left_2"], "set": "gm"},  # d179 2503
	{"t": "M", "name": "Насладился вторым завтраком", "pts": [10, null, null], "icons": ["", "blank", "goblet"], "fx": [], "set": "gm"},  # d180 2504
	{"t": "M", "name": "Нашёл ключ в будке", "pts": [15, null, null], "icons": ["", "magnifier", "beast"], "fx": ["draw_per_icon_then_trim:magnifier"], "set": "gm"},  # d181 2505
	{"t": "M", "name": "Восхитительно поужинал", "pts": [10, 5, null], "icons": ["", "heart", "goblet"], "fx": ["draw:2"], "set": "gm"},  # d182 2506
	{"t": "M", "name": "Целовался на кухне", "pts": [10, null, null], "icons": ["", "", "heart"], "fx": [], "set": "gm"},  # d183 2507
	{"t": "M", "name": "Женился на горничной", "pts": [0, null, 15], "icons": ["", "", "heart"], "fx": ["limit+1"], "set": "gm"},  # d184 2508
	{"t": "M", "name": "Закрутил роман с повесой", "pts": [0, 15, null], "icons": ["", "dagger", "heart"], "fx": ["limit+1"], "set": "gm"},  # d185 2509
	{"t": "M", "name": "Украл из кабинета", "pts": [null, 15, null], "icons": ["", "magnifier", "coin"], "fx": ["take_left_2"], "set": "gm"},  # d186 2510
	{"t": "M", "name": "Поймал вора", "pts": [0, null, 15], "icons": ["", "magnifier", "coin"], "fx": ["guest_uncontrolled_choose"], "set": "gm"},  # d187 2511
	{"t": "M", "name": "Нашёл улику", "pts": [null, 10, null], "icons": ["", "magnifier", ""], "fx": ["draw_per_icon_then_trim:magnifier"], "set": "gm"},  # d188 2512
	{"t": "M", "name": "Обручился с наследником", "pts": [0, null, 20], "icons": ["", "heart", "coin"], "fx": ["take_any_guest"], "set": "gm"},  # d189 2513
	{"t": "M", "name": "Съел плохое печенье", "pts": [-5, -5, null], "icons": ["", "", "goblet"], "fx": [], "set": "gm"},  # d190 2514
	{"t": "M", "name": "Привлёк внимание", "pts": [null, -10, null], "icons": ["", "magnifier", ""], "fx": ["discard_mod_below"], "set": "gm"},  # d191 2515
	{"t": "M", "name": "Подрался из-за бренди", "pts": [-20, -10, null], "icons": ["", "", "goblet"], "fx": ["others_take_random:1"], "set": "gm"},  # d192 2516
	{"t": "M", "name": "Подавился сыром", "pts": [-10, null, null], "icons": ["", "", "goblet"], "fx": ["free_ud_if_icon:dagger"], "set": "gm"},  # d193 2517
	{"t": "M", "name": "Опозорился перед графом", "pts": [null, -20, null], "icons": ["", "", "coin"], "fx": ["guests_uncontrolled"], "set": "gm"},  # d194 2518
	{"t": "M", "name": "Упал в кухонный лифт", "pts": [-20, null, null], "icons": ["", "", ""], "fx": [], "set": "gm"},  # d195 2519
	{"t": "M", "name": "Заблудился в библиотеке", "pts": [-5, -15, null], "icons": ["", "magnifier", ""], "fx": ["free_mod_with:dagger"], "set": "gm"},  # d196 2520
	{"t": "M", "name": "Переел мармелада", "pts": [-10, -5, null], "icons": ["", "", "goblet"], "fx": [], "set": "gm"},  # d197 2521
	{"t": "M", "name": "Тосковал по утраченной любви", "pts": [null, -10, -10], "icons": ["", "", "heart"], "fx": ["give_right_choice:1"], "set": "gm"},  # d198 2522
	{"t": "M", "name": "Уснул в гостиной", "pts": [-15, -15, -15], "icons": ["", "", "skull"], "fx": ["discard_hand", "skip_draw"], "set": "gm"},  # d199 2523
	{"t": "M", "name": "Не поладил с птицей", "pts": [-10, null, null], "icons": ["", "duck", "beast"], "fx": ["free_mod_with:dagger"], "set": "gm"},  # d200 2524
	{"t": "M", "name": "Сболтнул лишнего", "pts": [null, -10, null], "icons": ["", "dagger", ""], "fx": [], "set": "gm"},  # d201 2525
	{"t": "M", "name": "Увидел призрака в галерее", "pts": [-10, null, -20], "icons": ["", "", "skull"], "fx": ["discard_per_icon:skull"], "set": "gm"},  # d202 2526
	{"t": "M", "name": "Увидел нечто ужасное", "pts": [null, null, -25], "icons": ["", "dagger", "magnifier"], "fx": ["only_on:magnifier"], "set": "gm"},  # d203 2527
	{"t": "M", "name": "Поделился грустной историей", "pts": [-15, -10, null], "icons": ["", "", ""], "fx": ["stories_uncontrolled"], "set": "gm"},  # d204 2528
	{"t": "M", "name": "Донёс и получил швы", "pts": [-15, -20, null], "icons": ["", "dagger", "magnifier"], "fx": ["discard_per_icon:dagger"], "set": "gm"},  # d205 2529
	{"t": "M", "name": "Споткнулся на лестнице", "pts": [-10, null, null], "icons": ["", "", "skull"], "fx": ["free_ud_if_icon:dagger"], "set": "gm"},  # d206 2530
	{"t": "M", "name": "Яростно стошнило", "pts": [-15, null, null], "icons": ["", "", "skull"], "fx": [], "set": "gm"},  # d207 2531
	{"t": "M", "name": "Оказался самозванцем", "pts": [null, null, -10], "icons": ["", "dagger", "skull"], "fx": ["discard_other_mods"], "set": "gm"},  # d208 2532
	{"t": "M", "name": "Подвергся нападению на чердаке", "pts": [-20, null, null], "icons": ["", "dagger", ""], "fx": ["right_random_discard:2"], "set": "gm"},  # d209 2533
	{"t": "M", "name": "Покусан клопами", "pts": [-20, null, null], "icons": ["", "", "beast"], "fx": ["skip_draw"], "set": "gm"},  # d210 2534
	{"t": "M", "name": "Обожжён дворецким", "pts": [-15, null, null], "icons": ["", "", ""], "fx": ["free_mod_with:coin"], "set": "gm"},  # d211 2535
	{"t": "M", "name": "Загнан корги", "pts": [-10, null, null], "icons": ["", "", "beast"], "fx": ["free_ud_if_icon:dagger"], "set": "gm"},  # d212 2536
	{"t": "M", "name": "Впал в глубокую тоску", "pts": [null, -15, null], "icons": ["", "", "skull"], "fx": [], "set": "gm"},  # d213 2537
	{"t": "M", "name": "Заточён в темнице", "pts": [-20, null, null], "icons": ["", "blank", ""], "fx": ["no_events"], "set": "gm"},  # d214 2538
	{"t": "M", "name": "Изгнан герцогом", "pts": [-15, -15, null], "icons": ["", "blank", "coin"], "fx": ["limit-1"], "set": "gm"},  # d215 2539
	{"t": "M", "name": "Напуган куклой", "pts": [-10, null, -15], "icons": ["", "", "skull"], "fx": ["limit-1"], "set": "gm"},  # d216 2540
	{"t": "M", "name": "Обманут дебютанткой", "pts": [null, -20, null], "icons": ["", "magnifier", "coin"], "fx": ["discard_events_from_hand"], "set": "gm"},  # d217 2541
	{"t": "M", "name": "Отхлёстан лягушками", "pts": [-20, null, null], "icons": ["", "", "beast"], "fx": ["discard_events_from_hand"], "set": "gm"},  # d218 2542
	{"t": "M", "name": "Одурачен врагом", "pts": [null, -25, null], "icons": ["", "dagger", "magnifier"], "fx": ["discard_hand"], "set": "gm"},  # d219 2543
	{"t": "M", "name": "Забодан в беседке", "pts": [-20, null, null], "icons": ["", "dagger", "beast"], "fx": ["skip_draw"], "set": "gm"},  # d220 2544
	{"t": "M", "name": "В опасности в кладовой", "pts": [-15, null, -15], "icons": ["", "dagger", "goblet"], "fx": ["limit-1"], "set": "gm"},  # d221 2545
	{"t": "M", "name": "Оклеветан за мартини", "pts": [null, -15, null], "icons": ["", "", "goblet"], "fx": ["free_mod_with:skull"], "set": "gm"},  # d222 2546
	{"t": "M", "name": "Затюкан монахинями", "pts": [-15, null, null], "icons": ["", "", ""], "fx": [], "set": "gm"},  # d223 2547
	{"t": "M", "name": "Ограблен на скачках", "pts": [null, -20, null], "icons": ["", "", "beast"], "fx": ["left_random_discard:2"], "set": "gm"},  # d224 2548
	{"t": "M", "name": "Погублен слухами", "pts": [null, -15, -20], "icons": ["", "", ""], "fx": ["discard_hand"], "set": "gm"},  # d225 2549
	{"t": "M", "name": "Замечен на кладбище", "pts": [-15, null, -10], "icons": ["", "magnifier", "skull"], "fx": ["discard:1", "skip_draw"], "set": "gm"},  # d226 2550
	{"t": "M", "name": "Получил пощёчину от светской дамы", "pts": [-10, -10, null], "icons": ["", "", "coin"], "fx": ["guests_uncontrolled"], "set": "gm"},  # d227 2551
	{"t": "M", "name": "Заколот в конюшне", "pts": [-25, null, null], "icons": ["", "dagger", "beast"], "fx": ["discard_per_icon:dagger"], "set": "gm"},  # d228 2552
	{"t": "M", "name": "Вызван на спиритический сеанс", "pts": [null, null, -15], "icons": ["", "magnifier", "skull"], "fx": ["free_mod_with:skull"], "set": "gm"},  # d229 2553
	{"t": "M", "name": "Обобран и упал в обморок", "pts": [null, -20, -20], "icons": ["", "", "coin"], "fx": ["discard_hand", "skip_draw"], "set": "gm"},  # d230 2554
	{"t": "M", "name": "Заперт в сундуке", "pts": [-15, null, null], "icons": ["", "", "dagger"], "fx": [], "set": "gm"},  # d231 2555
	{"t": "M", "name": "Изведён нервами", "pts": [-15, null, -15], "icons": ["", "", "skull"], "fx": ["limit-1"], "set": "gm"},  # d232 2556
	{"t": "D", "name": "Убит котёнком", "pts": [10, null, null], "icons": ["blank", "", ""], "fx": ["ud_any_worth_if:beast"], "set": "gm"},  # d233 2557
	{"t": "D", "name": "Смертельно влюблён", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["ud_any_worth_if:heart"], "set": "gm"},  # d234 2558
	{"t": "D", "name": "Разбился на воздушном шаре", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["ud_second_if:dagger"], "set": "gm"},  # d235 2559
	{"t": "D", "name": "Отравлен при обрезке роз", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["ud_second_if:dagger"], "set": "gm"},  # d236 2560
	{"t": "D", "name": "Пал жертвой чумы", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:skull"], "set": "gm"},  # d237 2561
	{"t": "D", "name": "Слухи были туманны", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["mods_under_ud"], "set": "gm"},  # d238 2562
	{"t": "D", "name": "Ушёл на вершине", "pts": [null, 0, 0], "icons": ["blank", "", ""], "fx": ["draw_per_icon:coin"], "set": "gm"},  # d239 2563
	{"t": "D", "name": "Не заметил обрыва", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["ud_second_if:dagger"], "set": "gm"},  # d240 2564
	{"t": "D", "name": "Убит подсвечником", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["ud_second_if:dagger"], "set": "gm"},  # d241 2565
	{"t": "D", "name": "Не пережил скандала", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:magnifier"], "set": "gm"},  # d242 2566
	{"t": "D", "name": "Застрелен на охоте", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:dagger,beast"], "set": "gm"},  # d243 2567
	{"t": "D", "name": "Убит ради добычи", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:coin,dagger"], "set": "gm"},  # d244 2568
	{"t": "D", "name": "Зачах", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:skull"], "set": "gm"},  # d245 2600
	{"t": "D", "name": "Пущен на паштет", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:goblet"], "set": "gm"},  # d246 2601
	{"t": "D", "name": "Умер от любви", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:heart"], "set": "gm"},  # d247 2602
	{"t": "D", "name": "Неудачно блефовал", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:magnifier"], "set": "gm"},  # d248 2603
	{"t": "D", "name": "Совершил роковую ошибку", "pts": [null, null, -15], "icons": ["blank", "", ""], "fx": ["discard_hand"], "set": "gm"},  # d249 2604
	{"t": "D", "name": "Погиб из-за торта", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:goblet,dagger"], "set": "gm"},  # d250 2605
	{"t": "D", "name": "Найден в колодце", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["extra10:dagger,magnifier"], "set": "gm"},  # d251 2606
	{"t": "D", "name": "Начал попахивать", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["permanent"], "set": "gm"},  # d252 2607
	{"t": "E", "name": "Алиби", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["remove_all_mods"], "set": "gm"},  # d253 2628
	{"t": "E", "name": "Двойник", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["second_chance"], "set": "gm"},  # d254 2629
	{"t": "E", "name": "Волна преступлений", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["others_discard_family_icons:dagger,magnifier"], "set": "gm"},  # d255 2630
	{"t": "E", "name": "Драматический поворот", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["dramatic"], "set": "gm"},  # d256 2631
	{"t": "E", "name": "Двойная игра", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["swap_living_chars_with_opponent"], "set": "gm"},  # d257 2632
	{"t": "E", "name": "Опять сорвалось!", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["cancel_event"], "set": "gm"},  # d258 2633
	{"t": "E", "name": "Убийца наносит удар!", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["ud_from_discard:dagger"], "set": "gm"},  # d259 2634
	{"t": "E", "name": "Полуночный сюрприз", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["midnight"], "set": "gm"},  # d260 2635
	{"t": "E", "name": "Обознались", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["swap_top_mods"], "set": "gm"},  # d261 2636
	{"t": "E", "name": "Сюжетный поворот", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["plot_twist"], "set": "gm"},  # d262 2637
	{"t": "E", "name": "Кто убийца?", "pts": [null, null, null], "icons": ["blank", "", ""], "fx": ["whodunnit"], "set": "gm"},  # d263 2638
]

const SECOND_CHANCE := 46
const CANCEL_EVENT := 52
const IMAGINARY_FRIEND := 32
const SUSPICIOUS_EXIT := 124  # «Подозрительный отъезд» — ответ на любую карту (нужен свой гость)


static func card(i: int) -> Dictionary:
	return CARDS[i]


static func card_name(i: int) -> String:
	return CARDS[i]["name"] if i >= 0 and i < CARDS.size() else "?"


static func char_name(i: int) -> String:
	return CHARS[i]["name"] if i >= 0 and i < CHARS.size() else "?"


static func has_fx(i: int, prefix: String) -> bool:
	for f in CARDS[i]["fx"]:
		if str(f).begins_with(prefix):
			return true
	return false


## Аргумент эффекта: "draw:2" → "2".
static func fx_arg(i: int, prefix: String) -> String:
	return fx_arg_in(CARDS[i]["fx"], prefix)


static func fx_arg_in(fx: Array, prefix: String) -> String:
	for f in fx:
		if str(f).begins_with(prefix + ":"):
			return str(f).substr(prefix.length() + 1)
	return ""


## Сумма видимых очков карты (для подсказок «плюс — чужим, минус — своим»).
static func pts_sum(i: int) -> int:
	var s := 0
	for p in CARDS[i]["pts"]:
		s += int(p) if p != null else 0
	return s
