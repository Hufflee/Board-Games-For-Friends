"""Текстуры зимней комнаты хаба (hub/rooms/winter_decor.gd, hub/rooms/arrivals.gd).

stocking.png — красный войлок носка с белыми снежинками, ёлочками и точками (по референсу владельца);
cuff.png     — белая вязаная резинка отворота носка;
carpet.png   — узор новогоднего ковра: рисунок по краям, середина спокойная (её закрывает игрок);
wrap.png     — подарочная бумага для новой игры в зимней комнате;
ball.png     — мяч-попрыгун зимой: красный, со снежинкой с двух сторон;
fur.png      — белый мех опушки колпаков;
felt.png     — красный войлок колпаков и бантов (как у носков);
hat.png      — ткань колпака со складками-тенями;
tape.png     — пластик кассет.
Запуск из корня проекта:  python -I tools/winter_art.py   → hub/art/winter/
После — импорт ресурсов Godot: godot --headless --path . --import
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join("hub", "art", "winter")
WHITE = (246, 242, 238, 255)


def noise_layer(size, amount, seed, blur=0.6):
	rnd = random.Random(seed)
	img = Image.new("L", size)
	img.putdata([rnd.randint(128 - amount, 128 + amount) for _ in range(size[0] * size[1])])
	return img.filter(ImageFilter.GaussianBlur(blur))


def tint(base, noise, strength=1.0):
	"""Фактура ткани: светлее/темнее по шуму."""
	r, g, b = base[:3]
	out = Image.new("RGBA", noise.size)
	px = []
	for n in noise.getdata():
		k = 1.0 + (n - 128) / 128.0 * 0.18 * strength
		px.append((min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k)), 255))
	out.putdata(px)
	return out


def snowflake(d, cx, cy, r, color, width):
	for i in range(6):
		a = math.radians(i * 60 + 90)
		dx, dy = math.cos(a), math.sin(a)
		d.line((cx, cy, cx + dx * r, cy + dy * r), fill=color, width=width)
		for at, arm in ((0.5, 0.32), (0.75, 0.22)):
			px, py = cx + dx * r * at, cy + dy * r * at
			for side in (-1, 1):
				b = a + side * math.radians(42)
				d.line((px, py, px + math.cos(b) * r * arm, py + math.sin(b) * r * arm), fill=color, width=max(1, width - 1))
	d.ellipse((cx - width, cy - width, cx + width, cy + width), fill=color)


def fir(d, cx, cy, h, color):
	"""Ёлочка-силуэт: три яруса треугольников и ствол."""
	w = h * 0.62
	for k in range(3):
		top = cy - h / 2 + k * h * 0.22
		bottom = top + h * 0.42
		half = w * (0.32 + k * 0.17)
		d.polygon([(cx, top), (cx - half, bottom), (cx + half, bottom)], fill=color)
	d.rectangle((cx - h * 0.05, cy + h * 0.3, cx + h * 0.05, cy + h * 0.45), fill=color)


def star(d, cx, cy, r, color):
	pts = []
	for i in range(10):
		rr = r if i % 2 == 0 else r * 0.45
		a = math.radians(i * 36 - 90)
		pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
	d.polygon(pts, fill=color)


def scatter(size, count, min_gap, seed, margin=0):
	rnd = random.Random(seed)
	pts = []
	tries = 0
	while len(pts) < count and tries < 20000:
		tries += 1
		p = (rnd.uniform(margin, size - margin), rnd.uniform(margin, size - margin))
		if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 > min_gap ** 2 for q in pts):
			pts.append(p)
	return pts


def stocking():
	s = 1024  # рисуем вдвое крупнее, потом уменьшаем — гладкие края
	img = tint((168, 28, 42), noise_layer((s, s), 60, 3, 0.8), 1.0)
	d = ImageDraw.Draw(img)
	rnd = random.Random(11)
	for i, (x, y) in enumerate(scatter(s, 26, 150, 5, 40)):
		kind = i % 4
		if kind == 0:
			snowflake(d, x, y, rnd.uniform(46, 62), WHITE, 9)
		elif kind == 1:
			fir(d, x, y, rnd.uniform(100, 130), WHITE)
		elif kind == 2:
			star(d, x, y, rnd.uniform(18, 24), WHITE)
		else:
			r = rnd.uniform(9, 13)
			d.ellipse((x - r, y - r, x + r, y + r), fill=WHITE)
	return img.resize((512, 512), Image.LANCZOS)


def cuff():
	w, h = 256, 128
	img = Image.new("RGBA", (w, h), WHITE)
	px = img.load()
	n = noise_layer((w, h), 40, 7, 0.5).load()
	for x in range(w):
		rib = 0.5 + 0.5 * math.cos(x / w * math.tau * 16)  # 16 рубчиков
		for y in range(h):
			k = 0.8 + 0.2 * rib + (n[x, y] - 128) / 128.0 * 0.05
			px[x, y] = (int(246 * k), int(242 * k), int(238 * k), 255)
	return img


def carpet():
	w, h = 2048, 1434  # пропорции ковра 5,0 × 3,5 м; рисуем крупно и уменьшаем
	red = (164, 26, 40)
	img = tint(red, noise_layer((w, h), 30, 9, 1.5), 0.6)
	d = ImageDraw.Draw(img)
	green = (24, 96, 62, 255)
	gold = (226, 176, 74, 255)
	# по краям — полосы: белая, зелёная, золотой шнур
	b = 70
	d.rectangle((0, 0, w, h), outline=WHITE, width=b)
	d.rectangle((b, b, w - b, h - b), outline=green, width=60)
	d.rectangle((b + 60, b + 60, w - b - 60, h - b - 60), outline=gold, width=10)
	# бордюр: чередуем ёлочки и снежинки по периметру
	inset = b + 60 + 90
	step = 180
	for k, x in enumerate(range(inset + 40, w - inset, step)):
		for y in (inset, h - inset):
			if k % 2 == 0:
				fir(d, x, y, 120, WHITE)
			else:
				snowflake(d, x, y, 50, WHITE, 9)
	for k, y in enumerate(range(inset + step, h - inset - step // 2, step)):
		for x in (inset, w - inset):
			if k % 2 == 0:
				snowflake(d, x, y, 50, WHITE, 9)
			else:
				fir(d, x, y, 120, WHITE)
	# вторая рамка — белый зигзаг
	z = inset + 110
	for x0, y0, x1, y1 in ((z, z, w - z, z), (z, h - z, w - z, h - z)):
		pts = [(x, y0 + (18 if (x // 36) % 2 else -18)) for x in range(x0, x1 + 1, 36)]
		d.line(pts, fill=WHITE, width=10)
	for x0 in (z, w - z):
		pts = [(x0 + (18 if (y // 36) % 2 else -18), y) for y in range(z, h - z + 1, 36)]
		d.line(pts, fill=WHITE, width=10)
	# середина спокойная: редкие маленькие звёздочки и тонкий ромб в центре
	for x, y in scatter(min(w, h), 14, 220, 13, 0):
		cx = z + 80 + x / min(w, h) * (w - 2 * z - 160)
		cy = z + 80 + y / min(w, h) * (h - 2 * z - 160)
		star(d, cx, cy, 16, (232, 196, 120, 160))
	cx, cy = w / 2, h / 2
	d.polygon([(cx, cy - 170), (cx + 260, cy), (cx, cy + 170), (cx - 260, cy)], outline=(232, 196, 120, 200), width=8)
	snowflake(d, cx, cy, 80, WHITE, 10)
	return img.resize((1024, 717), Image.LANCZOS)


def wrap():
	s = 1024
	img = tint((22, 98, 64), noise_layer((s, s), 30, 17, 1.0), 0.5)
	d = ImageDraw.Draw(img)
	# диагональные тонкие полоски и снежинки ровной сеткой со сдвигом
	for k in range(-s, 2 * s, 128):
		d.line((k, 0, k + s, s), fill=(36, 120, 80, 255), width=26)
	for row in range(5):
		for col in range(5):
			x = col * 205 + (102 if row % 2 else 0) + 50
			y = row * 205 + 100
			if (row + col) % 2 == 0:
				snowflake(d, x % s, y, 58, WHITE, 10)
			else:
				star(d, x % s, y, 30, (236, 190, 80, 255))
	return img.resize((512, 512), Image.LANCZOS)


def ball():
	"""Мяч-попрыгун зимой: красная резина, по снежинке с двух сторон (развёртка: ширина = 2 × высота)."""
	w, h = 1024, 512
	img = tint((196, 24, 40), noise_layer((w, h), 18, 21, 1.2), 0.5)
	d = ImageDraw.Draw(img)
	for cx in (w * 0.25, w * 0.75):
		snowflake(d, cx, h * 0.5, 120, WHITE, 16)
	return img.resize((512, 256), Image.LANCZOS)


def felt():
	"""Красный войлок колпака и бантов — та же фактура, что у носка, без рисунка."""
	return tint((176, 26, 40), noise_layer((256, 256), 60, 41, 0.8), 1.0)


def hat():
	"""Ткань колпака в плоском 2D-стиле: ровная заливка и несколько крупных теней там, куда свет не попадает.
	Развёртка трубки колпака: u — вокруг (края картинки u = 0 и 1 — нижняя сторона: под свисающим верхом,
	снизу перегиба, у помпона), v — от опушки (верх картинки) к кончику (низ)."""
	w, h = 512, 512
	red = (196, 24, 43, 255)
	shadow = (138, 14, 30, 255)
	deep = (108, 10, 24, 255)
	light = (220, 50, 64, 255)
	img = Image.new("RGBA", (w, h), red)
	d = ImageDraw.Draw(img)
	# 1) нижняя сторона по всей длине: от опушки узкая, к кончику шире (верх свисает и закрывает свет)
	left, right = [], []
	for k in range(17):
		v = 0.12 + k * 0.88 / 16
		half = (0.1 + 0.2 * v) * w + 10 * math.sin(k * 1.7)
		left.append((half, v * h))
		right.append((w - half, v * h))
	d.polygon([(0, 0.12 * h)] + left + [(0, h)], fill=shadow)
	d.polygon([(w, 0.12 * h)] + right + [(w, h)], fill=shadow)
	# 2) у помпона — глубокая тень вокруг кончика
	d.polygon([(0, 0.86 * h)] + [(x, 0.86 * h + 10 * math.sin(x / w * math.tau * 2)) for x in range(0, w + 1, 32)] + [(w, h), (0, h)], fill=deep)
	# 3) под меховой опушкой
	d.rectangle((0, 0, w, 0.06 * h), fill=deep)
	# 4) спереди (u ≈ 0,3…0,7) — несколько небольших теней-клиньев от опушки: ткань собрана у меха
	for u, width, length in ((0.34, 34, 0.17), (0.5, 40, 0.22), (0.64, 30, 0.14)):
		x = u * w
		d.polygon([(x - width / 2, 0.06 * h), (x + width / 2, 0.06 * h), (x + 4, (0.06 + length) * h)], fill=shadow)
	return img


def tape():
	"""Кассета (коробка VHS) — ровная светлая заливка, цвет даёт материал (плоский стиль)."""
	return Image.new("RGBA", (16, 16), (255, 255, 255, 255))


def fur():
	"""Белый мех опушки колпака: мелкие светлые и тёмные ворсинки."""
	s = 256
	img = Image.new("RGBA", (s, s), (238, 234, 230, 255))
	d = ImageDraw.Draw(img)
	rnd = random.Random(31)
	for _ in range(5000):
		x, y = rnd.uniform(0, s), rnd.uniform(0, s)
		a = rnd.uniform(0, math.tau)
		ln = rnd.uniform(3, 9)
		v = rnd.randint(200, 255)
		d.line((x, y, x + math.cos(a) * ln, y + math.sin(a) * ln), fill=(v, v - 3, v - 6, 255), width=1)
	return img.filter(ImageFilter.GaussianBlur(0.4))


def main():
	os.makedirs(OUT, exist_ok=True)
	stocking().save(os.path.join(OUT, "stocking.png"))
	cuff().save(os.path.join(OUT, "cuff.png"))
	carpet().save(os.path.join(OUT, "carpet.png"))
	wrap().save(os.path.join(OUT, "wrap.png"))
	ball().save(os.path.join(OUT, "ball.png"))
	fur().save(os.path.join(OUT, "fur.png"))
	felt().save(os.path.join(OUT, "felt.png"))
	hat().save(os.path.join(OUT, "hat.png"))
	tape().save(os.path.join(OUT, "tape.png"))
	print("ok", OUT)


if __name__ == "__main__":
	main()
