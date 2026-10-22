class_name NHData
extends RefCounted
## Подарки «Это не шляпа!»: [id картинки, название]. Картинки — art/gifts/<id>.svg (Tabler Icons, MIT; шляпа — своя).

const GIFTS := [
	["hat", "Шляпа"], ["chef-hat", "Поварской колпак"], ["crown", "Корона"], ["tie", "Галстук"],
	["shirt", "Футболка"], ["sock", "Носок"], ["shoe", "Ботинок"], ["jacket", "Куртка"],
	["sunglasses", "Очки"], ["umbrella", "Зонтик"], ["clock", "Будильник"], ["piano", "Пианино"],
	["microphone", "Микрофон"], ["headphones", "Наушники"], ["bell", "Колокольчик"], ["camera", "Фотоаппарат"],
	["device-gamepad", "Геймпад"], ["robot", "Робот"], ["rocket", "Ракета"], ["ufo", "НЛО"],
	["car", "Машинка"], ["truck", "Грузовик"], ["bike", "Велосипед"], ["skateboard", "Скейт"],
	["sailboat", "Кораблик"], ["plane", "Самолёт"], ["helicopter", "Вертолёт"], ["train", "Поезд"],
	["horse-toy", "Лошадка"], ["balloon", "Воздушный шарик"], ["dice", "Кубик"], ["book", "Книга"],
	["pencil", "Карандаш"], ["scissors", "Ножницы"], ["key", "Ключ"], ["lamp", "Лампа"],
	["candle", "Свеча"], ["magnet", "Магнит"], ["compass", "Компас"], ["hammer", "Молоток"],
	["axe", "Топор"], ["shovel", "Лопата"], ["bucket", "Ведро"], ["brush", "Кисточка"],
	["wand", "Волшебная палочка"], ["anchor", "Якорь"], ["trophy", "Кубок"], ["diamond", "Бриллиант"],
	["teapot", "Чайник"], ["cup", "Чашка"], ["glass-cocktail", "Коктейль"], ["bottle", "Бутылка"],
	["tools-kitchen-2", "Вилка и нож"], ["pizza", "Пицца"], ["cake", "Торт"], ["cookie", "Печенье"],
	["candy", "Конфета"], ["lollipop", "Леденец"], ["ice-cream", "Мороженое"], ["burger", "Бургер"],
	["cheese", "Сыр"], ["carrot", "Морковка"], ["apple", "Яблоко"], ["cherry", "Вишня"],
	["lemon", "Лимон"], ["pepper", "Перец"], ["mushroom", "Гриб"], ["egg-fried", "Яичница"],
	["bread", "Хлеб"], ["fish", "Рыба"], ["bone", "Косточка"], ["cactus", "Кактус"],
	["flower", "Цветок"], ["plant", "Росток"], ["tree", "Дерево"], ["clover", "Клевер"],
	["feather", "Перо"], ["butterfly", "Бабочка"], ["cat", "Кошка"], ["dog", "Собака"],
	["pig", "Свинка"], ["deer", "Олень"], ["ghost", "Привидение"], ["snowman", "Снеговик"],
	["pumpkin-scary", "Тыква"], ["sun", "Солнце"], ["moon", "Луна"], ["star", "Звезда"],
	["heart", "Сердечко"], ["tent", "Палатка"], ["gift", "Подарок"],
]


static func gift_name(i: int) -> String:
	return GIFTS[i][1] if i >= 0 and i < GIFTS.size() else "?"


static func gift_icon(i: int) -> String:
	return GIFTS[i][0] if i >= 0 and i < GIFTS.size() else ""
