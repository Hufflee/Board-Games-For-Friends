"""Монеты Мачи Коро для антистресса: листы 1774×887, слева орёл (городок у горы с телебашней), справа решка (сакура на узоре волн).
Секретная — та же монета, «улучшенная»: ночной город с огнями и фейерверком, красная эмаль на ободе, золотая сакура на тёмном.
Палитра — дневной город игры: кремовая бумага, бирюзовая гора, красная башня, латунный обод, чернила тёмной бирюзы.
Ровные круги и узорный обод (уровень детали — как у монеты Clocktower), лёгкая «рисованность» только в мелочах; без глянца.
Запуск: python -I tools/coin_machi_koro.py [папка]  → по умолчанию hub/art/coins/machi_koro_coin.png и machi_koro_secret_coin.png
"""
import math
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, "tools")
from coin_common import SIZE, wobble, outline, jitter_line, new_layer, clip, volume, edge, save_sheet, preview

PAPER = (243, 234, 213)
PAPER_DARK = (226, 212, 184)
SKY = (226, 236, 228)
RIM = (208, 170, 96)
RIM_DARK = (166, 128, 66)
RIM_LIGHT = (228, 196, 128)
INK = (30, 60, 66)
TEAL = (66, 148, 150)
TEAL_DARK = (46, 116, 120)
SNOW = (250, 247, 238)
RED = (204, 84, 72)
RED_DARK = (160, 62, 56)
YELLOW = (232, 190, 92)
PINK = (236, 168, 178)
PINK_DARK = (204, 122, 138)
GREEN = (104, 156, 98)
GREEN_DARK = (74, 124, 76)
NIGHT = (34, 58, 78)
NIGHT_DARK = (24, 42, 58)
GOLD = (236, 196, 100)
W = SIZE * 0.008  # основная толщина линии
secret = False  # переключает палитру на секретную (ночь, эмаль, золото)


def circle(cx, cy, r, seed, amp=0.003, n=200):
	return wobble(cx, cy, r, seed, amp, n)


def poly(d, pts, fill, width=W):
	d.polygon(pts, fill=fill)
	outline(d, pts, INK, width)


def rect(x0, y0, x1, y1):
	return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def shine(art, radius=SIZE * 0.022, strength=1.0):
	"""Свечение секретной монеты: золотые, розовые и лунные пиксели размываются и «осветляют» (screen) соседний фон."""
	rgb = art.convert("RGB")
	src = rgb.load()
	mask = Image.new("L", art.size, 0)
	dst = mask.load()
	for y in range(0, art.height, 2):
		for x in range(0, art.width, 2):
			r, g, b = src[x, y]
			lit = (r > 220 and g > 180 and b < 140) or (r > 240 and g > 236 and b > 220) or (r > 225 and 150 < g < 185 and b > 160)
			if lit:
				dst[x, y] = 255
				if x + 1 < art.width:
					dst[x + 1, y] = 255
	halo = mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: min(255, int(v * 2.2 * strength)))
	color = Image.new("RGB", art.size, (255, 214, 120))
	light = Image.composite(color, Image.new("RGB", art.size, (0, 0, 0)), halo)
	out = ImageChops.screen(rgb, light).convert("RGBA")
	out.putalpha(art.split()[3])
	return out


def blank(seed):
	light_petal = (244, 214, 140) if secret else RIM_LIGHT
	"""Латунная монета: гурт, обод с чешуйками и бусинами, внутреннее кольцо с рисками, кремовое поле."""
	img = new_layer()
	c = SIZE / 2
	r = SIZE * 0.46
	edge(img, c, r, RIM_DARK, INK, seed, drop=0.024)
	d = ImageDraw.Draw(img)
	rim = circle(c, c, r, seed + 1)
	d.polygon(rim, fill=RIM)
	volume(img, rim, c, r, (250, 228, 170), (130, 92, 40), 55, seed + 20)
	d = ImageDraw.Draw(img)
	# Чешуйки-лепестки по ободу.
	n = 20
	for i in range(n):
		a = math.tau * (i + 0.5) / n
		x, y = c + math.cos(a) * r * 0.885, c + math.sin(a) * r * 0.885
		petal = []
		for k in range(24):
			t = math.tau * k / 24
			px, py = math.cos(t) * SIZE * 0.034, math.sin(t) * SIZE * 0.02
			petal.append((x + px * math.cos(a + math.pi / 2) - py * math.sin(a + math.pi / 2),
				y + px * math.sin(a + math.pi / 2) + py * math.cos(a + math.pi / 2)))
		d.polygon(petal, fill=light_petal)
		outline(d, petal, RIM_DARK, SIZE * 0.004)
		bead = (c + math.cos(a + math.pi / n) * r * 0.885, c + math.sin(a + math.pi / n) * r * 0.885)
		dot = circle(bead[0], bead[1], SIZE * 0.008, seed + 60 + i, 0.02, 24)
		d.polygon(dot, fill=RED if secret else RIM_DARK)
	outline(d, rim, INK, SIZE * 0.012)
	ring = circle(c, c, r * 0.78, seed + 2)
	d.polygon(ring, fill=RED if secret else RIM_DARK)
	outline(d, ring, INK, SIZE * 0.007)
	face = circle(c, c, r * 0.745, seed + 3)
	d.polygon(face, fill=PAPER)
	outline(d, face, INK, SIZE * 0.008)
	return img, face, c, r * 0.745


def ticks(img, c, r, seed, count=48):
	d = ImageDraw.Draw(img)
	for i in range(count):
		a = math.tau * i / count
		long = i % 4 == 0
		p = (c + math.cos(a) * r * 0.985, c + math.sin(a) * r * 0.985)
		q = (c + math.cos(a) * r * (0.92 if long else 0.95), c + math.sin(a) * r * (0.92 if long else 0.95))
		d.line([p, q], fill=INK if long else RIM_DARK, width=int(SIZE * (0.005 if long else 0.004)))


def cloud(d, x, y, s):
	pts = []
	for cx, cy, rr in ((x - s * 0.6, y, s * 0.42), (x, y - s * 0.22, s * 0.55), (x + s * 0.6, y, s * 0.4)):
		pts.append((cx, cy, rr))
	for cx, cy, rr in pts:
		d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=SNOW)
	d.rectangle((x - s * 0.6, y, x + s * 0.6, y + s * 0.4), fill=SNOW)
	for cx, cy, rr in pts:
		d.arc((cx - rr, cy - rr, cx + rr, cy + rr), 180, 360, fill=INK, width=int(SIZE * 0.005))
	d.line([(x - s * 1.02, y + s * 0.4), (x + s * 1.0, y + s * 0.4)], fill=INK, width=int(SIZE * 0.005))


def heads():
	img, face, c, fr = blank(21)
	art = new_layer()
	d = ImageDraw.Draw(art)
	d.rectangle((0, 0, SIZE, SIZE), fill=NIGHT if secret else SKY)
	if secret:
		heads_night(d, c, fr)
	else:
		heads_day(d, c, fr)
	heads_city(d, c, fr)
	if secret:
		art = shine(art, SIZE * 0.026, 1.6)
	img.alpha_composite(clip(art, face))
	d = ImageDraw.Draw(img)
	outline(d, face, INK, SIZE * 0.009)
	return img


def heads_night(d, c, fr):
	"""Луна, звёзды и фейерверк над горой."""
	mx, my = c - fr * 0.5, c - fr * 0.5
	poly(d, circle(mx, my, SIZE * 0.045, 5, 0.01, 60), SNOW, SIZE * 0.006)
	d.ellipse((mx + SIZE * 0.008, my - SIZE * 0.05, mx + SIZE * 0.07, my + SIZE * 0.025), fill=NIGHT)
	for i, (x, y, s) in enumerate(((c - fr * 0.1, c - fr * 0.78, 1.0), (c + fr * 0.15, c - fr * 0.6, 0.7), (c - fr * 0.75, c - fr * 0.15, 0.8),
			(c + fr * 0.75, c - fr * 0.25, 0.9), (c - fr * 0.3, c - fr * 0.45, 0.6), (c + fr * 0.6, c - fr * 0.05, 0.6))):
		from coin_common import star
		poly(d, star(x, y, SIZE * 0.016 * s, SIZE * 0.007 * s), GOLD, SIZE * 0.003)
	fx, fy = c + fr * 0.62, c - fr * 0.6
	for i in range(14):
		a = math.tau * i / 14
		col = (PINK, GOLD)[i % 2]
		jitter_line(d, (fx + math.cos(a) * SIZE * 0.018, fy + math.sin(a) * SIZE * 0.018),
			(fx + math.cos(a) * SIZE * 0.06, fy + math.sin(a) * SIZE * 0.06), SIZE * 0.006, col, 400 + i, 2)
		d.ellipse((fx + math.cos(a) * SIZE * 0.066 - 6, fy + math.sin(a) * SIZE * 0.066 - 6,
			fx + math.cos(a) * SIZE * 0.066 + 6, fy + math.sin(a) * SIZE * 0.066 + 6), fill=col)


def heads_day(d, c, fr):
	# Солнце с лучами.
	sx, sy = c - fr * 0.5, c - fr * 0.5
	for i in range(12):
		a = math.tau * i / 12
		jitter_line(d, (sx + math.cos(a) * SIZE * 0.05, sy + math.sin(a) * SIZE * 0.05),
			(sx + math.cos(a) * SIZE * 0.068, sy + math.sin(a) * SIZE * 0.068), SIZE * 0.005, YELLOW, 200 + i, 2)
	poly(d, circle(sx, sy, SIZE * 0.04, 5, 0.01, 60), YELLOW, SIZE * 0.006)
	cloud(d, c + fr * 0.55, c - fr * 0.62, SIZE * 0.045)
	cloud(d, c - fr * 0.05, c - fr * 0.78, SIZE * 0.032)


def heads_city(d, c, fr):
	# Гора со снежной шапкой.
	base = c + fr * 0.28
	peak = (c - fr * 0.12, c - fr * 0.5)
	mountain = [(c - fr * 1.05, base), (peak[0] - SIZE * 0.012, peak[1]), (peak[0] + SIZE * 0.012, peak[1]), (c + fr * 0.85, base)]
	poly(d, mountain, TEAL_DARK if secret else TEAL)
	# тень на правом склоне
	d.polygon([(peak[0] + SIZE * 0.012, peak[1]), (c + fr * 0.85, base), (c + fr * 0.15, base)], fill=NIGHT_DARK if secret else TEAL_DARK)
	outline(d, mountain, INK, W)
	cap_y = peak[1] + fr * 0.2
	left_x = peak[0] - (peak[1] - cap_y) / (peak[1] - base) * (peak[0] - mountain[0][0]) * -1
	k_left = (cap_y - peak[1]) / (base - peak[1])
	lx = peak[0] + (mountain[0][0] - peak[0]) * k_left
	rx = peak[0] + (mountain[3][0] - peak[0]) * k_left
	cap = [(peak[0] - SIZE * 0.012, peak[1]), (peak[0] + SIZE * 0.012, peak[1]), (rx, cap_y)]
	zig = 5
	for i in range(1, zig):
		t = i / zig
		cap.append((rx + (lx - rx) * t, cap_y + (SIZE * 0.022 if i % 2 else -SIZE * 0.004)))
	cap.append((lx, cap_y))
	poly(d, cap, SNOW, SIZE * 0.006)
	# Холмы и поле.
	hills = [(c - fr * 1.1, base + fr * 0.02)]
	for i in range(9):
		t = i / 8
		hills.append((c - fr * 1.1 + fr * 2.2 * t, base - fr * 0.04 * math.sin(t * math.pi * 3) - fr * 0.02))
	hills += [(c + fr * 1.1, c + fr * 1.1), (c - fr * 1.1, c + fr * 1.1)]
	poly(d, hills, GREEN_DARK if secret else GREEN)
	field = [(c - fr * 1.1, c + fr * 0.62), (c + fr * 1.1, c + fr * 0.55), (c + fr * 1.1, c + fr * 1.1), (c - fr * 1.1, c + fr * 1.1)]
	poly(d, field, RIM_DARK if secret else YELLOW)
	for i in range(9):
		x = c - fr * 0.9 + fr * 0.22 * i
		jitter_line(d, (x, c + fr * 0.66), (x - fr * 0.06, c + fr * 0.95), SIZE * 0.004, (120, 88, 44) if secret else RIM_DARK, 300 + i, 3)
	# Красная телебашня с решёткой.
	tx, top, foot = c + fr * 0.42, c - fr * 0.62, c + fr * 0.4
	half_foot, half_top = fr * 0.13, fr * 0.025
	legs_l = [(tx - half_foot, foot), (tx - half_top, top + fr * 0.12)]
	legs_r = [(tx + half_foot, foot), (tx + half_top, top + fr * 0.12)]
	body = [legs_l[0], legs_l[1], legs_r[1], legs_r[0]]
	d.polygon(body, fill=RED)
	# белые пояса
	for t0, t1 in ((0.35, 0.42), (0.68, 0.74)):
		y0, y1 = foot + (legs_l[1][1] - foot) * t0, foot + (legs_l[1][1] - foot) * t1
		h0 = half_foot + (half_top - half_foot) * t0
		h1 = half_foot + (half_top - half_foot) * t1
		d.polygon([(tx - h0, y0), (tx + h0, y0), (tx + h1, y1), (tx - h1, y1)], fill=SNOW)
	# решётка крестами
	steps = 6
	for i in range(steps):
		t0, t1 = i / steps, (i + 1) / steps
		y0, y1 = foot + (legs_l[1][1] - foot) * t0, foot + (legs_l[1][1] - foot) * t1
		h0 = half_foot + (half_top - half_foot) * t0
		h1 = half_foot + (half_top - half_foot) * t1
		d.line([(tx - h0, y0), (tx + h1, y1)], fill=RED_DARK, width=int(SIZE * 0.004))
		d.line([(tx + h0, y0), (tx - h1, y1)], fill=RED_DARK, width=int(SIZE * 0.004))
		d.line([(tx - h1, y1), (tx + h1, y1)], fill=INK, width=int(SIZE * 0.004))
	# арка между ногами
	d.pieslice((tx - half_foot * 0.55, foot - fr * 0.12, tx + half_foot * 0.55, foot + fr * 0.12), 180, 360, fill=NIGHT if secret else SKY)
	d.arc((tx - half_foot * 0.55, foot - fr * 0.12, tx + half_foot * 0.55, foot + fr * 0.12), 180, 360, fill=INK, width=int(W))
	outline(d, body, INK, W)
	deck = [(tx - fr * 0.06, top + fr * 0.1), (tx + fr * 0.06, top + fr * 0.1), (tx + fr * 0.045, top + fr * 0.16), (tx - fr * 0.045, top + fr * 0.16)]
	poly(d, deck, SNOW, SIZE * 0.006)
	poly(d, rect(tx - fr * 0.012, top - fr * 0.06, tx + fr * 0.012, top + fr * 0.1), RED, SIZE * 0.005)
	# Домики городка.
	def house(x, w, h, wall, roof):
		y = base + fr * 0.33
		poly(d, rect(x, y - h, x + w, y), wall, SIZE * 0.006)
		poly(d, [(x - w * 0.12, y - h), (x + w / 2, y - h - w * 0.45), (x + w * 1.12, y - h)], roof, SIZE * 0.006)
		poly(d, rect(x + w * 0.38, y - h * 0.45, x + w * 0.62, y), GOLD if secret else RIM_DARK, SIZE * 0.004)
	def block(x, w, h, wall):
		y = base + fr * 0.33
		poly(d, rect(x, y - h, x + w, y), wall, SIZE * 0.006)
		for row in range(int(h / (fr * 0.09))):
			for col in range(2):
				wx = x + w * (0.2 + col * 0.4)
				wy = y - h + fr * 0.04 + row * fr * 0.09
				d.rectangle((wx, wy, wx + w * 0.2, wy + fr * 0.045), fill=GOLD if secret else SKY, outline=INK, width=int(SIZE * 0.003))
	block(c - fr * 0.78, fr * 0.2, fr * 0.42, TEAL)
	house(c - fr * 0.52, fr * 0.2, fr * 0.16, SNOW, RED)
	house(c - fr * 0.24, fr * 0.22, fr * 0.2, YELLOW, TEAL_DARK)
	block(c + fr * 0.03, fr * 0.18, fr * 0.32, PAPER_DARK)
	# Деревья и сакура.
	def tree(x, s, color):
		y = base + fr * 0.33
		d.line([(x, y), (x, y - s * 0.6)], fill=INK, width=int(SIZE * 0.007))
		poly(d, circle(x, y - s * 0.75, s * 0.42, int(x) % 97, 0.05, 40), color, SIZE * 0.006)
	tree(c - fr * 0.95, fr * 0.24, GREEN_DARK)
	tree(c + fr * 0.7, fr * 0.26, PINK)
	tree(c + fr * 0.88, fr * 0.2, GREEN_DARK)
	if secret:
		# Фонарик на верхушке башни.
		tx, top = c + fr * 0.42, c - fr * 0.62
		poly(d, circle(tx, top - fr * 0.07, SIZE * 0.012, 7, 0.02, 30), GOLD, SIZE * 0.004)


fr_main = 1e9  # радиус поля монеты: крупный цветок на секретной — золотой


def blossom(d, x, y, s, rot, seed):
	"""Цветок сакуры: пять лепестков с выемкой, прожилки, тычинки."""
	for i in range(5):
		a = rot + math.tau * i / 5
		pts = [(x + math.cos(a) * s * 0.12, y + math.sin(a) * s * 0.12)]
		for k in range(31):
			t = k / 30
			ang = a + (t - 0.5) * 1.1
			rad = s * (0.2 + 0.8 * math.sin(math.pi * t) ** 0.3)
			if 0.43 < t < 0.57:
				rad -= s * 0.18 * (1 - abs(t - 0.5) / 0.07)
			pts.append((x + math.cos(ang) * rad, y + math.sin(ang) * rad))
		poly(d, pts, (GOLD if s > fr_main * 0.3 else PINK) if secret else PINK, max(2, s * 0.045))
		d.line([(x + math.cos(a) * s * 0.25, y + math.sin(a) * s * 0.25), (x + math.cos(a) * s * 0.62, y + math.sin(a) * s * 0.62)],
			fill=PINK_DARK, width=int(max(2, s * 0.03)))
	for i in range(5):
		a = rot + math.tau * (i + 0.5) / 5
		p = (x + math.cos(a) * s * 0.3, y + math.sin(a) * s * 0.3)
		d.line([(x, y), p], fill=RED_DARK, width=int(max(2, s * 0.025)))
		d.ellipse((p[0] - s * 0.05, p[1] - s * 0.05, p[0] + s * 0.05, p[1] + s * 0.05), fill=YELLOW, outline=INK, width=int(max(1, s * 0.015)))
	d.ellipse((x - s * 0.1, y - s * 0.1, x + s * 0.1, y + s * 0.1), fill=RED, outline=INK, width=int(max(2, s * 0.025)))


def tails():
	global fr_main
	img, face, c, fr = blank(37)
	fr_main = fr
	art = new_layer()
	d = ImageDraw.Draw(art)
	bg, wave = (NIGHT, NIGHT_DARK) if secret else (PAPER, PAPER_DARK)
	d.rectangle((0, 0, SIZE, SIZE), fill=bg)
	# Узор волн сэйгайха — чуть темнее бумаги.
	step = fr * 0.26
	row = 0
	y = c - fr * 1.1
	while y < c + fr * 1.3:
		x = c - fr * 1.2 + (step / 2 if row % 2 else 0)
		while x < c + fr * 1.3:
			for k in range(3, 0, -1):
				rr = step * 0.5 * k / 3
				d.pieslice((x - rr, y - rr, x + rr, y + rr), 180, 360, fill=bg if k % 2 else wave)
				d.arc((x - rr, y - rr, x + rr, y + rr), 180, 360, fill=RIM_DARK if secret else PAPER_DARK, width=int(SIZE * 0.003))
			x += step
		y += step * 0.25
		row += 1
	# Ветка с цветами.
	branch = [(c - fr * 0.95, c + fr * 0.55), (c - fr * 0.45, c + fr * 0.35), (c - fr * 0.05, c + fr * 0.32), (c + fr * 0.5, c + fr * 0.05), (c + fr * 0.95, c - fr * 0.1)]
	d.line(branch, fill=INK, width=int(SIZE * 0.03), joint="curve")
	d.line(branch, fill=(118, 82, 66), width=int(SIZE * 0.018), joint="curve")
	d.line([(c - fr * 0.05, c + fr * 0.32), (c + fr * 0.15, c + fr * 0.62)], fill=INK, width=int(SIZE * 0.02))
	d.line([(c - fr * 0.05, c + fr * 0.32), (c + fr * 0.15, c + fr * 0.62)], fill=(118, 82, 66), width=int(SIZE * 0.01))
	for x, y, s, rot in ((c + fr * 0.62, c + fr * 0.22, fr * 0.13, 0.4), (c - fr * 0.55, c + fr * 0.62, fr * 0.11, 1.1),
			(c + fr * 0.2, c + fr * 0.68, fr * 0.1, 0.9), (c + fr * 0.82, c - fr * 0.2, fr * 0.09, 0.2)):
		blossom(d, x, y, s, rot, 0)
	# Главный цветок.
	blossom(d, c - fr * 0.05, c - fr * 0.15, fr * 0.42, -math.pi / 2, 1)
	# Опавшие лепестки.
	for i, (x, y, a) in enumerate(((c - fr * 0.7, c - fr * 0.35, 0.5), (c - fr * 0.55, c - fr * 0.65, 2.0), (c + fr * 0.45, c - fr * 0.6, 1.2), (c + fr * 0.6, c + fr * 0.6, 2.6))):
		pts = [(x + math.cos(a + t) * fr * 0.05 * (1 if k % 2 else 0.5), y + math.sin(a + t) * fr * 0.05 * (1 if k % 2 else 0.5))
			for k, t in enumerate((0, 1.3, 2.4, 3.14, 3.9, 5.0))]
		poly(d, pts, PINK, SIZE * 0.004)
	if secret:
		art = shine(art, SIZE * 0.03)
	img.alpha_composite(clip(art, face))
	d = ImageDraw.Draw(img)
	outline(d, face, INK, SIZE * 0.009)
	return img


def main():
	global secret
	folder = sys.argv[1] if len(sys.argv) > 1 else "hub/art/coins"
	sheets = []
	for flag, name in ((False, "machi_koro_coin.png"), (True, "machi_koro_secret_coin.png")):
		secret = flag
		sheets.append(save_sheet(folder + "/" + name, heads(), tails()))
	preview(sheets, folder + "/machi_koro_coins_view.png")


if __name__ == "__main__":
	main()
