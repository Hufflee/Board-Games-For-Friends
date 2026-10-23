## Поле «Большой бродилки»: дорожка как линейный список клеток от старта до финиш-сейфа.
## Перекрёсток — клетка, через которую дорожка проходит дважды (две записи с одним pos), «иди прямо» выходит само.
## Разметка — центры клеток, сняты по сетке на board.webp (поправить можно через tools/br_mark.gd).
class_name BRBoard
extends RefCounted

## Код клетки → тип (см. BRData.CELL_NAMES). Цвет red/green — у пустых клеток r/g.
const CODES := {
	"S": "start", ".": "empty", "r": "empty", "g": "empty", "C": "chest_good", "O": "chest_bad",
	"$": "shop", "T": "tadam", "Y": "tele_y", "G": "tele_g", "P": "tele_p", "B": "tele_b",
	"L": "lucky", "W": "tornado", "D": "tribute", "X": "duel", "V": "bike", "M": "mine",
	"N": "nooo", "K": "luck_die", "J": "gum", "+": "cross", "F": "finish",
}
const TRACK := "SVC$TC$r.CBTCCCgCPT$C$OB.CgrPrrOr.$.YCg.KgO$.TgYC$rCGgCr.LgTW$.gGgD.$.X.Cgr.$CC..$.MOOONrrrrrOOOOJF"
## Оттенок клетки → кубики: l — 1 кубик, g — 2 на выбор, b — 2 суммой. Пусто/короче TRACK — светлая.
const SHADE := "llllllllllllllllllllllllgggggggggglggggggggggggggggggggggggggggggggggbbbbbbbbbbbblbbbbbbbbbbbbbbbbb"
## Центры клеток в долях MapFull.jpg (1280×905): x — доля ширины MapFull (поле — 940 из 1280), y — доля высоты.
## Переразмечено 24.10.2026 по сетке на board.webp (все 99 клеток; раньше точки уезжали влево, местами — мимо дорожки).
const POS := [Vector2(0.2776, 0.9567), Vector2(0.2785, 0.9056), Vector2(0.2785, 0.8611), Vector2(0.2785, 0.8111), Vector2(0.2785, 0.7639), Vector2(0.2785, 0.7267), Vector2(0.2785, 0.6806), Vector2(0.2785, 0.6278), Vector2(0.2785, 0.5778), Vector2(0.2868, 0.5361), Vector2(0.2805, 0.4889), Vector2(0.2722, 0.4417), Vector2(0.2764, 0.3861), Vector2(0.3179, 0.3944), Vector2(0.3512, 0.4167), Vector2(0.3865, 0.4139), Vector2(0.4239, 0.4067), Vector2(0.4592, 0.3861), Vector2(0.4925, 0.3889), Vector2(0.5278, 0.3833), Vector2(0.5735, 0.4000), Vector2(0.5818, 0.4417), Vector2(0.5611, 0.4889), Vector2(0.5569, 0.5361), Vector2(0.5548, 0.5833), Vector2(0.5777, 0.6361), Vector2(0.5652, 0.6833), Vector2(0.5257, 0.6889), Vector2(0.4883, 0.6778), Vector2(0.4509, 0.6722), Vector2(0.4156, 0.6822), Vector2(0.3824, 0.6972), Vector2(0.3491, 0.6917), Vector2(0.3138, 0.6778), Vector2(0.2785, 0.6806), Vector2(0.2431, 0.6833), Vector2(0.2036, 0.6822), Vector2(0.1704, 0.6694), Vector2(0.1704, 0.6194), Vector2(0.1746, 0.5761), Vector2(0.1829, 0.5306), Vector2(0.1725, 0.4844), Vector2(0.1633, 0.4400), Vector2(0.1704, 0.3889), Vector2(0.1787, 0.3417), Vector2(0.1746, 0.2972), Vector2(0.2078, 0.2778), Vector2(0.2473, 0.3000), Vector2(0.2826, 0.3056), Vector2(0.3159, 0.2944), Vector2(0.3491, 0.2778), Vector2(0.3886, 0.2844), Vector2(0.4239, 0.2878), Vector2(0.4551, 0.2889), Vector2(0.4883, 0.2972), Vector2(0.5237, 0.2917), Vector2(0.5590, 0.2833), Vector2(0.5922, 0.2778), Vector2(0.6296, 0.2806), Vector2(0.6567, 0.3139), Vector2(0.6525, 0.3556), Vector2(0.6442, 0.3944), Vector2(0.6442, 0.4417), Vector2(0.6483, 0.4889), Vector2(0.6463, 0.5389), Vector2(0.6504, 0.5833), Vector2(0.6774, 0.6278), Vector2(0.6774, 0.6722), Vector2(0.6691, 0.7222), Vector2(0.6691, 0.7667), Vector2(0.6629, 0.8083), Vector2(0.6276, 0.8111), Vector2(0.5922, 0.8083), Vector2(0.5569, 0.8056), Vector2(0.5195, 0.8083), Vector2(0.4842, 0.8111), Vector2(0.4530, 0.8194), Vector2(0.4198, 0.8167), Vector2(0.3865, 0.8111), Vector2(0.3533, 0.8100), Vector2(0.3159, 0.8111), Vector2(0.2785, 0.8111), Vector2(0.2431, 0.8111), Vector2(0.1995, 0.8083), Vector2(0.1621, 0.8183), Vector2(0.1288, 0.8483), Vector2(0.0873, 0.8500), Vector2(0.0582, 0.8194), Vector2(0.0686, 0.7667), Vector2(0.0748, 0.7167), Vector2(0.0748, 0.6722), Vector2(0.0707, 0.6278), Vector2(0.0727, 0.5833), Vector2(0.0831, 0.5278), Vector2(0.0790, 0.4833), Vector2(0.0623, 0.4389), Vector2(0.0644, 0.3972), Vector2(0.0686, 0.3583), Vector2(0.0790, 0.3111)]

static var _cells: Array = []


## [{t, col, shade, pos}] по индексу дорожки.
static func cells() -> Array:
	if _cells.is_empty():
		for i in TRACK.length():
			var ch := TRACK[i]
			var col := "red" if ch == "r" else ("green" if ch == "g" else "")
			var sh := SHADE[i] if i < SHADE.length() else "l"
			_cells.append({t = CODES.get(ch, "empty"), col = col, shade = {"l": "light", "g": "grey", "b": "black"}[sh], pos = POS[i] if i < POS.size() else Vector2.ZERO})
	return _cells


static func size() -> int:
	return cells().size()


static func finish() -> int:
	return size() - 1


static func cell(i: int) -> Dictionary:
	return cells()[clampi(i, 0, finish())]


## Пара телепорта: другая клетка того же типа.
static func tele_pair(i: int) -> int:
	var t: String = cell(i).t
	for j in size():
		if j != i and cells()[j].t == t:
			return j
	return i


## Ближайшая клетка цвета col вперёд (dir 1) или назад (dir -1) от i; -1 — нет.
static func nearest(i: int, col: String, dir: int) -> int:
	var j := i + dir
	while j >= 0 and j <= finish():
		if cells()[j].col == col:
			return j
		j += dir
	return -1
