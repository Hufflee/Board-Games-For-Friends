## Поле «Большой бродилки»: дорожка как линейный список клеток от старта до финиш-сейфа.
## Перекрёсток — клетка, через которую дорожка проходит дважды (две записи с одним pos), «иди прямо» выходит само.
## Разметка — по MapFull.jpg (координаты на глаз по Map1–4; поправить можно через tools/br_mark.gd).
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
## Центры клеток в долях MapFull.jpg (1280×905).
const POS := [Vector2(0.2617, 0.9558), Vector2(0.2617, 0.9028), Vector2(0.2617, 0.8586), Vector2(0.2617, 0.8066), Vector2(0.2617, 0.7646), Vector2(0.2617, 0.7238), Vector2(0.2617, 0.6740), Vector2(0.2617, 0.6265), Vector2(0.2617, 0.5768), Vector2(0.2695, 0.5271), Vector2(0.2656, 0.4917), Vector2(0.2539, 0.4365), Vector2(0.2594, 0.3834), Vector2(0.2984, 0.3923), Vector2(0.3320, 0.4144), Vector2(0.3633, 0.4254), Vector2(0.4000, 0.4066), Vector2(0.4336, 0.3867), Vector2(0.4672, 0.3867), Vector2(0.4938, 0.3978), Vector2(0.5391, 0.3923), Vector2(0.5508, 0.4365), Vector2(0.5312, 0.4751), Vector2(0.5250, 0.5381), Vector2(0.5391, 0.5823), Vector2(0.5430, 0.6354), Vector2(0.5367, 0.6873), Vector2(0.5000, 0.6906), Vector2(0.4609, 0.6740), Vector2(0.4273, 0.6906), Vector2(0.3945, 0.6818), Vector2(0.3594, 0.6928), Vector2(0.3281, 0.6873), Vector2(0.2930, 0.6762), Vector2(0.2617, 0.6740), Vector2(0.2305, 0.6762), Vector2(0.1953, 0.6818), Vector2(0.1602, 0.6707), Vector2(0.1562, 0.6188), Vector2(0.1641, 0.5713), Vector2(0.1719, 0.5271), Vector2(0.1641, 0.4807), Vector2(0.1539, 0.4365), Vector2(0.1602, 0.3867), Vector2(0.1680, 0.3425), Vector2(0.1641, 0.2928), Vector2(0.1953, 0.2818), Vector2(0.2359, 0.3061), Vector2(0.2672, 0.3094), Vector2(0.2984, 0.2928), Vector2(0.3320, 0.2873), Vector2(0.3672, 0.2840), Vector2(0.3984, 0.2895), Vector2(0.4297, 0.2983), Vector2(0.4609, 0.3006), Vector2(0.4898, 0.3039), Vector2(0.5250, 0.2873), Vector2(0.5586, 0.2707), Vector2(0.5938, 0.2873), Vector2(0.6172, 0.3094), Vector2(0.6211, 0.3591), Vector2(0.6055, 0.3867), Vector2(0.6172, 0.4365), Vector2(0.6211, 0.4807), Vector2(0.6055, 0.5381), Vector2(0.6055, 0.5823), Vector2(0.6367, 0.6265), Vector2(0.6250, 0.6707), Vector2(0.6328, 0.7094), Vector2(0.6328, 0.7591), Vector2(0.6250, 0.8122), Vector2(0.5898, 0.8088), Vector2(0.5586, 0.8033), Vector2(0.5156, 0.7978), Vector2(0.4883, 0.8033), Vector2(0.4570, 0.8088), Vector2(0.4258, 0.8144), Vector2(0.3945, 0.8177), Vector2(0.3633, 0.8088), Vector2(0.3320, 0.8066), Vector2(0.3008, 0.8066), Vector2(0.2617, 0.8066), Vector2(0.2266, 0.8033), Vector2(0.1891, 0.8033), Vector2(0.1562, 0.8177), Vector2(0.1172, 0.8420), Vector2(0.0836, 0.8508), Vector2(0.0508, 0.8232), Vector2(0.0586, 0.7646), Vector2(0.0703, 0.7204), Vector2(0.0641, 0.6762), Vector2(0.0625, 0.6265), Vector2(0.0625, 0.5801), Vector2(0.0758, 0.5271), Vector2(0.0719, 0.4807), Vector2(0.0625, 0.4365), Vector2(0.0602, 0.3945), Vector2(0.0641, 0.3591), Vector2(0.0641, 0.3094)]

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
