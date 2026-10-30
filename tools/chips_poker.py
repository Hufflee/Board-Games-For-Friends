"""«Покер»: спрайты фишек-визуала — 5 размеров кучи (1 фишка, столбик, два столбика, россыпь, гора).
Неоновые казино-фишки в перспективе 3/4, рисуются кодом (PIL), со сглаживанием через 4× и уменьшение.
Запуск: python -I tools/chips_poker.py  → games/poker/art/chips/pile_1..5.png
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = "games/poker/art/chips"
SS = 4  # суперсэмплинг
R = 22  # радиус фишки в итоговых пикселях
SQUASH = 0.42  # сплющивание эллипса (взгляд сверху под углом)
THICK = 5  # толщина фишки
COLORS = {
	"pink": (255, 63, 164),
	"cyan": (53, 224, 255),
	"gold": (255, 209, 102),
	"violet": (155, 92, 255),
	"ivory": (236, 228, 246),
}


def shade(color, k):
	return tuple(max(0, min(255, int(c * k))) for c in color)


def mix(a, b, t):
	return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def chip(draw, cx, cy, color):
	"""Одна фишка: верх — эллипс в (cx, cy), бок вниз на THICK."""
	r = R * SS
	ry = r * SQUASH
	th = THICK * SS
	side = shade(color, 0.55)
	# бок: эллипс снизу + прямоугольник
	draw.ellipse([cx - r, cy - ry + th, cx + r, cy + ry + th], fill=side)
	draw.rectangle([cx - r, cy, cx + r, cy + th], fill=side)
	# полосы на боку (видимая передняя половина)
	for k in range(4):
		a = math.pi * (k + 0.5) / 4
		x = cx - math.cos(a) * r
		w = r * 0.09 * max(0.25, math.sin(a))
		y0 = cy + math.sin(a) * ry
		draw.polygon([(x - w, y0), (x + w, y0), (x + w, y0 + th), (x - w, y0 + th)], fill=mix(color, (255, 255, 255), 0.75))
	# верх
	draw.ellipse([cx - r, cy - ry, cx + r, cy + ry], fill=color)
	# полосы по ободу сверху
	for k in range(8):
		a = math.tau * k / 8 + math.pi / 8
		pts = []
		for t in (-0.11, 0.11):
			for rr in (1.0, 0.8):
				pts.append((cx + math.cos(a + t) * r * rr, cy + math.sin(a + t) * ry * rr))
		draw.polygon([pts[0], pts[2], pts[3], pts[1]], fill=(250, 246, 255))
	# внутреннее кольцо и центр
	ir = r * 0.62
	draw.ellipse([cx - ir, cy - ir * SQUASH, cx + ir, cy + ir * SQUASH], outline=shade(color, 0.7), width=SS * 2)
	cr = r * 0.48
	draw.ellipse([cx - cr, cy - cr * SQUASH, cx + cr, cy + cr * SQUASH], fill=mix(color, (255, 255, 255), 0.35))
	# блик
	hr = r * 0.22
	draw.ellipse([cx - r * 0.45 - hr, cy - ry * 0.55 - hr * SQUASH, cx - r * 0.45 + hr, cy - ry * 0.55 + hr * SQUASH], fill=mix(color, (255, 255, 255), 0.6))


def stack(chips, x, base_y, count, palette, rng, lean=0.0):
	"""Столбик count фишек: координаты низа; возвращает фишки снизу вверх."""
	for i in range(count):
		jx = rng.uniform(-1.2, 1.2) + lean * i
		chips.append((x + jx, base_y - i * THICK, palette[i % len(palette)] if len(palette) > 1 else palette[0]))


def render(name, size, chips, glow):
	w, h = size
	img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
	# тень на сукне под кучей
	shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
	sd = ImageDraw.Draw(shadow)
	for x, y, _ in chips:
		sd.ellipse([(x - R * 1.05) * SS, (y + THICK - R * SQUASH * 0.9) * SS, (x + R * 1.05) * SS, (y + THICK + R * SQUASH * 1.3) * SS], fill=(0, 0, 0, 70))
	shadow = shadow.filter(ImageFilter.GaussianBlur(3 * SS))
	img.alpha_composite(shadow)
	if glow:
		g = Image.new("RGBA", img.size, (0, 0, 0, 0))
		gd = ImageDraw.Draw(g)
		for x, y, c in chips:
			gd.ellipse([(x - R * 1.1) * SS, (y - R * SQUASH * 1.2) * SS, (x + R * 1.1) * SS, (y + THICK + R * SQUASH * 1.2) * SS], fill=c + (60,))
		g = g.filter(ImageFilter.GaussianBlur(7 * SS))
		img.alpha_composite(g)
	draw = ImageDraw.Draw(img)
	# порядок добавления: дальние ряды раньше, в столбике снизу вверх
	for x, y, c in chips:
		chip(draw, x * SS, y * SS, c)
	img = img.resize((w, h), Image.LANCZOS)
	img.save(os.path.join(OUT, name))
	print("сохранено", name, img.size)


def main():
	os.makedirs(OUT, exist_ok=True)
	rng = random.Random(112)
	P, C, G, V, I = (COLORS[k] for k in ("pink", "cyan", "gold", "violet", "ivory"))
	# 1 — одна фишка
	chips = []
	stack(chips, 48, 46, 1, [P], rng)
	render("pile_1.png", (96, 72), chips, False)
	# 2 — столбик из 4
	chips = []
	stack(chips, 48, 62, 4, [P, P, C, P], rng)
	render("pile_2.png", (96, 88), chips, False)
	# 3 — два столбика
	chips = []
	stack(chips, 50, 66, 4, [C], rng)
	stack(chips, 88, 82, 7, [P], rng)
	render("pile_3.png", (140, 112), chips, False)
	# 4 — три столбика и россыпь
	chips = []
	stack(chips, 58, 74, 6, [V], rng)
	stack(chips, 104, 72, 9, [P], rng)
	stack(chips, 34, 100, 1, [G], rng)
	stack(chips, 80, 104, 5, [C], rng)
	stack(chips, 130, 106, 3, [G], rng)
	stack(chips, 150, 96, 1, [P], rng)
	render("pile_4.png", (184, 136), chips, True)
	# 5 — гора: ряды столбиков от дальних к ближним, в центре выше
	chips = []
	rows = [
		(70, [(70, 8, V), (114, 12, G), (158, 9, V), (202, 6, C)]),
		(96, [(48, 6, C), (92, 13, P), (136, 16, G), (180, 12, P), (224, 7, V)]),
		(124, [(70, 9, P), (114, 14, C), (158, 11, P), (202, 8, G)]),
		(150, [(40, 3, G), (92, 7, V), (136, 9, P), (180, 6, C), (232, 2, P)]),
	]
	for base, cols in rows:
		for x, n, col in cols:
			stack(chips, x + rng.uniform(-4, 4), base, n, [col], rng, lean=rng.uniform(-0.25, 0.25))
	for _ in range(7):
		chips.append((rng.uniform(26, 250), rng.uniform(160, 172), rng.choice([P, C, G, V, I])))
	render("pile_5.png", (276, 196), chips, True)


def card_back():
	"""Рубашка карты 420×582: ночное сукно, розовая неоновая рамка, голубая сетка ромбов, монограмма."""
	w, h = 420, 582
	img = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)
	d.rounded_rectangle([0, 0, w * 2 - 1, h * 2 - 1], radius=56, fill=(36, 16, 64, 255))
	lattice = Image.new("RGBA", img.size, (0, 0, 0, 0))
	ld = ImageDraw.Draw(lattice)
	step = 70
	for k in range(-h * 2 // step, w * 2 // step + h * 2 // step + 2):
		x = k * step
		ld.line([(x, 0), (x + h * 2, h * 2)], fill=COLORS["cyan"] + (60,), width=4)
		ld.line([(x, 0), (x - h * 2, h * 2)], fill=COLORS["cyan"] + (60,), width=4)
	mask = Image.new("L", img.size, 0)
	ImageDraw.Draw(mask).rounded_rectangle([60, 60, w * 2 - 61, h * 2 - 61], radius=36, fill=255)
	img.paste(lattice, (0, 0), mask)
	frame = Image.new("RGBA", img.size, (0, 0, 0, 0))
	ImageDraw.Draw(frame).rounded_rectangle([40, 40, w * 2 - 41, h * 2 - 41], radius=40, outline=COLORS["pink"] + (255,), width=14)
	img.alpha_composite(frame.filter(ImageFilter.GaussianBlur(14)))
	img.alpha_composite(frame)
	d = ImageDraw.Draw(img)
	cx, cy, r = w, h, 150
	d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(36, 16, 64, 255), outline=COLORS["gold"] + (255,), width=12)
	d.polygon([(cx, cy - 95), (cx + 70, cy), (cx, cy + 95), (cx - 70, cy)], fill=COLORS["pink"] + (255,))
	d.polygon([(cx, cy - 50), (cx + 36, cy), (cx, cy + 50), (cx - 36, cy)], fill=(255, 220, 240, 255))
	img = img.resize((w, h), Image.LANCZOS)
	img.save("games/poker/art/card_back.png")
	print("сохранено card_back.png")


if __name__ == "__main__":
	main()
	card_back()
