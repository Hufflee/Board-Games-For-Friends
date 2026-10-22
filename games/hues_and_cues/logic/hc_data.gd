class_name HCData
extends RefCounted
## Данные «Оттенков и подсказок»: поле 30×16 (A–P × 1–30), цвета сняты с поля из PDF.

const COLS := 30
const ROWS := 16

const BOARD := [
	"612b0f", "6b2710", "752214", "841e19", "941e1d", "9e1b20", "af1e23", "c62127", "e01e26", "ed1b24", "ec1e24", "ed1c25", "ec1b2e", "ee1a3b", "ec1946", "e91754", "e51465", "e20f75", "d70f83", "d4148d", "c82791", "bb2d91", "b33394", "a83594", "9f3894", "933895", "8c3d98", "833d96", "7d3e99", "73419a",  # A
	"884b1f", "94441f", "9c3f20", "ad3f24", "b93825", "c62d27", "d62827", "e42024", "ed2225", "ee272a", "ee2932", "ed263b", "ed2041", "ed1f4d", "ed1c5e", "ec166e", "ed0f7c", "e90c8d", "db2a92", "cd3894", "bf3e98", "b43d97", "a93c97", "9e3e97", "963d97", "8d3d96", "843e97", "7d3e99", "723d97", "683b96",  # B
	"a66128", "ac5b26", "ba5a27", "c24e27", "cd4827", "d64027", "e23926", "ea3024", "ee362c", "ef3c40", "ef3f4c", "ee3b50", "ee3a5d", "ee3066", "ee3078", "ee2b87", "eb3196", "db4398", "cb489c", "bb4b9d", "b4499b", "a64799", "9e4599", "954398", "8c4299", "843d97", "7a3c97", "733c97", "663996", "5a3191",  # C
	"c9822a", "d78228", "dd7627", "e87824", "e66926", "ea5d25", "f1602b", "ef5533", "f04f3d", "ef5651", "f05d65", "f05e6b", "f05871", "f0537e", "ef4f8b", "f04f9d", "df55a0", "cd57a1", "be5ea5", "b658a2", "a554a1", "9b4e9e", "944c9e", "8d499e", "82449a", "7b4198", "6f3e99", "663795", "583393", "472e8a",  # D
	"e69c23", "f1991e", "f7921c", "f68c1e", "f68525", "f4782e", "f4773d", "f36e45", "f37052", "f27767", "f37674", "f37781", "f27789", "f27094", "f069a4", "e76fac", "d371ac", "c771ae", "bb71ae", "ac67aa", "9e5fa6", "9359a5", "8d54a3", "8451a0", "7a489d", "6f459b", "623e98", "583393", "492e8f", "342b84",  # E
	"feb415", "fcb122", "faab2c", "fbab3a", "faa741", "f9a34c", "f69755", "f78e5e", "f48864", "f58873", "f58f83", "f38f8f", "f48e99", "f48ca3", "f287b5", "e08dbb", "d18bbd", "c68cbe", "b982b9", "aa7ab6", "9c74b3", "9067ab", "865ea7", "7b59a6", "7251a2", "634a9e", "5a429a", "4c3293", "392f8f", "2c2978",  # F
	"fdc113", "fdc029", "fcb72c", "fcb43b", "fcb95e", "f9ab56", "faaa63", "f9a26d", "f7a279", "f7a085", "f69e94", "f69d99", "f59ea6", "f69baa", "f39dc2", "e1a5cb", "d0a6cc", "cdadd2", "b898c7", "a88bc1", "9a82bc", "8a76b5", "7f6eb2", "7265ad", "675ca8", "5954a4", "4f4ba0", "44419a", "313694", "2b2f86",  # G
	"fcd017", "fecd2a", "ffc82f", "fdc740", "fec649", "fdbf58", "fcbb5f", "fcb96b", "fbb379", "fab083", "f9ae8e", "f9b29e", "f5b6ad", "f5b5b5", "ecb5c8", "d8b7d6", "cdb8d9", "ccbddc", "b4a9d3", "a79fce", "8c8ac0", "8183c2", "7880be", "7380bf", "6d7cbd", "6c79bc", "6a78bc", "6877bc", "6576b8", "6674b8",  # H
	"fce118", "fcdc27", "fcd933", "fcd842", "fcde4c", "fed859", "fddb60", "fbd66b", "f5db7c", "f1e092", "ecdc9e", "e8e1b3", "e1e0c2", "dce1cb", "d2e0d3", "c6dde3", "c1d9f1", "c0d8f0", "a7c8e9", "99b9e0", "81a2d4", "769ed4", "7395cd", "6f8ac5", "688ac4", "6883c2", "6680bf", "6881bd", "6980be", "687dbd",  # I
	"f9ec24", "f9eb2a", "faeb36", "f9ee46", "f9f04d", "f9f25c", "f7f06b", "efee82", "e7eb8c", "dee99d", "d8e7ac", "d3e8bd", "d1e8cb", "cde9d3", "c7e6d6", "bbe5e4", "b3e2f2", "b2e2f6", "9edbf5", "87d6f7", "72c2ee", "6cb4e4", "68a9db", "66a6da", "6498d1", "6491ca", "638bc6", "6789c3", "6a87c0", "6d84bf",  # J
	"f6ef3c", "f6ef3f", "f5ee46", "f4ef4d", "f1ec5a", "ecec68", "e6e87a", "dfe784", "d6e485", "c8df8d", "bedd97", "b5dba2", "b4dbaf", "b0dab6", "addbc1", "aeddd7", "aaddde", "a8dde3", "99d8e7", "89d7ee", "68cdf5", "5fc8f4", "64bde8", "66b0e1", "65a4d9", "609bd1", "6396cd", "6891c9", "6c8dc6", "708ec6",  # K
	"f1ec21", "f0eb2d", "ebe932", "e9e838", "e5e643", "dce453", "d0df60", "bfda67", "b1d66d", "a8d377", "9fd07e", "98d089", "92ce98", "8dcd9b", "8ecfa7", "8dcfb3", "8ed1c0", "8bd1c6", "84cfcb", "7acdd3", "5ac7d6", "52c6e0", "3ec7ef", "46c0ee", "46b9e5", "59a9db", "66a0d3", "689cd0", "6e96ca", "7294c9",  # L
	"e0e320", "dbe127", "d6e12f", "cfdf37", "c8db43", "bad645", "aed24c", "9fcd51", "90c958", "85c65e", "79c469", "71c371", "70c27a", "6dc183", "6ec38a", "70c493", "70c59c", "73c7a6", "75c8ac", "6bc6b4", "52bfb5", "4fc2c2", "4ac4d0", "3dc6de", "34c2e6", "3eb8e6", "51afe0", "64a8d8", "66a4d3", "699ece",  # M
	"c2d82d", "bdd630", "b5d333", "abcf39", "a0cc39", "94c93d", "81c240", "79c143", "6dbc45", "5db545", "54b34b", "4db254", "46b859", "49b869", "50bb73", "57bd7b", "59bd7d", "5cbf88", "5fc08b", "60c092", "4eba95", "4bbfa9", "4bc0b4", "45c4c9", "40c6d4", "3bc4de", "3bbfe4", "4eb9e6", "5fb2dd", "66aad7",  # N
	"9ec439", "9ac43c", "94c23c", "88bf40", "7dbb42", "6db343", "63b144", "54a846", "4fa647", "409e46", "359d48", "30a346", "2aaa4b", "2ab149", "31b454", "37b65d", "42b864", "46b86e", "48ba70", "51bc76", "42b678", "44b98b", "48bea0", "46c2b2", "42c4c1", "48c8d0", "45c9dc", "46c4e1", "4ebfe4", "5cbde5",  # O
	"7ba541", "76a940", "6fa744", "65a243", "59a445", "4c9f45", "439845", "399645", "299144", "1e8943", "198b43", "149145", "159a47", "18a149", "1bab4a", "20b14c", "2cb34c", "33b555", "3ab65e", "3eb865", "2eb062", "34b679", "37bc8e", "38bf9e", "3bc2ae", "3cc6ba", "45c9c9", "4acad3", "51cae0", "56c8ea",  # P
]

## Базовые названия цветов (правила игры): корень + окончание прилагательного или «-ота», «-изна», «-ева», «-ь»…
const FORBIDDEN_RE := "^(красн|оранжев|ж[её]лт|зел[её]н|голуб|син|фиолетов|розов|коричнев|бел|ч[её]рн|сер)(ый|ий|ой|ая|яя|ое|ее|ые|ие|ого|его|ому|ему|ым|им|ыми|ими|ом|ем|ую|юю|ых|их|оват.*|еньк.*|ющ.*|е(ть|ет|ют|л|ла|ли).*|ота|оты|изна|изны|ева|евы|ь|и|ость|ости|ина)?$"
const FORBIDDEN_EN := ["red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "white", "black", "grey", "gray"]

## Цвета фишек игроков: спокойные, но различимые на любом участке поля (с белой обводкой).
const PIECE_COLORS := ["f2f2f2", "2b2b2b", "e4572e", "f3c64a", "4aa96c", "3d7dd8", "a05cc8", "ef8fb6"]
const PIECE_NAMES := ["Белый", "Чёрный", "Красный", "Жёлтый", "Зелёный", "Синий", "Фиолетовый", "Розовый"]


static func color(cell: int) -> Color:
	return Color(BOARD[cell])


static func cell(row: int, col: int) -> int:
	return row * COLS + col


## «K25» для клетки (строка K, столбец 25).
static func coord(cell_i: int) -> String:
	return "%s%d" % [char(65 + cell_i / COLS), cell_i % COLS + 1]


## Расстояние «по королю»: 0 — сама клетка, 1 — в рамке 3×3, 2 — вплотную к рамке.
static func dist(a: int, b: int) -> int:
	return maxi(absi(a / COLS - b / COLS), absi(a % COLS - b % COLS))


## Карта: 4 разных цвета, разбросанных по полю (по одному из каждой четверти).
static func draw_card(rng: RandomNumberGenerator) -> Array:
	var card := []
	for q in 4:
		var r0 := (q / 2) * 8
		var c0 := (q % 2) * 15
		card.append(cell(r0 + rng.randi_range(0, 7), c0 + rng.randi_range(0, 14)))
	card.shuffle()
	return card
