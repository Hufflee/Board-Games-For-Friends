"""Свой курсор игры: белые формы с тёмным контуром и мягкой тенью (по образцу владельца, 06.11).

Рисует hub/art/cursors/<размер>/<имя>.png и листы анимаций wait.png (крутящееся кольцо) и busy.png
(стрелка, по контуру которой бежит свет). Размеры 32 и 48 px; рисуем в 4× и уменьшаем — ровные края.
Запуск из корня: python -I tools/hub_cursors.py ; затем godot --headless --path . --import
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SS = 4  # суперсэмплинг
BASE = 32  # координаты фигур — в сетке 32×32
OUTLINE = (16, 30, 82, 255)  # тёмно-синий контур всех курсоров (просьба владельца 06.11)
FILL = (250, 250, 253, 255)
GLOW = (90, 205, 255)
FRAMES_WAIT = 12
FRAMES_BUSY = 16

# Стрелка: остриё слева сверху, мягкий «наконечник» как на образце.
ARROW = [(4.0, 2.5), (4.0, 20.5), (8.8, 16.6), (16.8, 16.4)]


def canvas(size):
	return Image.new("L", (size * SS, size * SS), 0)


def poly(mask, points, scale):
	ImageDraw.Draw(mask).polygon([(x * scale, y * scale) for x, y in points], fill=255)


def rounded(mask, radius):
	"""Мягкое скругление углов (размытие + порог): остриё стрелки остаётся острым, но не колючим."""
	return mask.filter(ImageFilter.GaussianBlur(radius * 0.8)).point(lambda v: 255 if v >= 128 else 0).filter(ImageFilter.GaussianBlur(0.6))


def compose(mask, size, outline_px=1.6, extra=None):
	"""Маска фигуры → курсор RGBA: тень, тёмный контур, белая заливка (+ дополнительные слои)."""
	k = size / BASE * SS
	grow = max(3, int(outline_px * k) | 1)
	outline = mask.filter(ImageFilter.MaxFilter(grow))
	out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
	shadow = outline.filter(ImageFilter.GaussianBlur(1.6 * k)).point(lambda a: int(a * 0.45))
	sh = Image.new("RGBA", mask.size, (0, 0, 0, 255))
	sh.putalpha(shadow)
	out.alpha_composite(sh, (int(0.6 * k), int(1.2 * k)))
	dark = Image.new("RGBA", mask.size, OUTLINE)
	dark.putalpha(outline)
	out.alpha_composite(dark)
	white = Image.new("RGBA", mask.size, FILL)
	white.putalpha(mask)
	out.alpha_composite(white)
	if extra is not None:
		extra(out, k)
	return out.resize((size, size), Image.LANCZOS)


def arrow_mask(size):
	k = size / BASE * SS
	m = canvas(size)
	poly(m, ARROW, k)
	return rounded(m, max(1, int(1.6 * k)))


def triangle(mask, center, direction, k, length=4.6, width=5.2):
	cx, cy = center
	dx, dy = direction
	px, py = -dy, dx
	tip = (cx + dx * length / 2, cy + dy * length / 2)
	b1 = (cx - dx * length / 2 + px * width / 2, cy - dy * length / 2 + py * width / 2)
	b2 = (cx - dx * length / 2 - px * width / 2, cy - dy * length / 2 - py * width / 2)
	poly(mask, [tip, b1, b2], k)


def arrows_mask(size, dirs, spread=8.5, rotate=0.0):
	k = size / BASE * SS
	m = canvas(size)
	for d in dirs:
		a = math.atan2(d[1], d[0]) + rotate
		v = (math.cos(a), math.sin(a))
		triangle(m, (16 + v[0] * spread, 16 + v[1] * spread), v, k)
	return rounded(m, max(1, int(0.5 * k)))


def ibeam_mask(size):
	k = size / BASE * SS
	m = canvas(size)
	d = ImageDraw.Draw(m)
	d.rounded_rectangle((14.9 * k, 6 * k, 17.1 * k, 26 * k), radius=1.1 * k, fill=255)
	return m


def cross_mask(size):
	k = size / BASE * SS
	m = canvas(size)
	d = ImageDraw.Draw(m)
	for a, b in (((15, 5), (17, 13)), ((15, 19), (17, 27)), ((5, 15), (13, 17)), ((19, 15), (27, 17))):
		d.rounded_rectangle((a[0] * k, a[1] * k, b[0] * k, b[1] * k), radius=k, fill=255)
	d.ellipse((15 * k, 15 * k, 17 * k, 17 * k), fill=255)
	return m


# Рука по референсу владельца (перерисована с нуля 06.11): один плавный контур по часовой стрелке от
# левого края указательного. Справа — плавный спуск трёх согнутых пальцев без рёбер, от большого пальца
# вниз — скругление внутрь к низу ладони.
HAND = [
	(10.7, 8.0), (11.1, 6.2), (12.3, 5.5), (13.5, 6.2), (13.9, 8.0),  # кончик указательного
	(13.95, 13.3), (16.3, 13.2), (19.2, 13.8), (21.7, 14.9), (23.2, 16.5),  # спуск согнутых пальцев (ниже)
	(23.6, 18.6), (23.4, 21.2), (22.5, 23.7), (20.6, 26.2), (18.0, 27.4),  # правый край и низ
	(15.0, 27.4), (12.9, 26.5), (11.4, 24.6), (10.3, 22.4),  # скругление снизу вверх к большому пальцу
	(8.6, 20.9), (6.6, 19.3), (5.5, 17.8), (5.9, 16.3), (7.3, 15.8), (9.1, 16.6), (10.65, 17.4),  # большой палец
	(10.65, 12.0),  # левый край указательного вниз
]


HAND_SCALE = 0.87
HAND_PIVOT = (14.5, 16.5)


def _catmull(points, steps=10):
	"""Сглаженный замкнутый контур через все точки (Catmull-Rom)."""
	out = []
	n = len(points)
	for i in range(n):
		p0, p1, p2, p3 = points[(i - 1) % n], points[i], points[(i + 1) % n], points[(i + 2) % n]
		for s in range(steps):
			t = s / steps
			t2, t3 = t * t, t * t * t
			out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
	return out


def hand_mask(size):
	"""Указывающая рука — один сглаженный силуэт без внутренних линий (контур HAND)."""
	k = size / BASE * SS
	m = canvas(size)
	# Общий размер руки — 87 % от исходного контура (просьба владельца 06.11), вокруг центра ладони.
	scaled = [(HAND_PIVOT[0] + (x - HAND_PIVOT[0]) * HAND_SCALE, HAND_PIVOT[1] + (y - HAND_PIVOT[1]) * HAND_SCALE) for x, y in HAND]
	poly(m, _catmull(scaled), k)
	return m.filter(ImageFilter.GaussianBlur(0.5 * k)).point(lambda v: 255 if v >= 128 else 0)


def badge_forbidden(out, k):
	d = ImageDraw.Draw(out)
	c, r = (24.5 * k, 24.5 * k), 5.6 * k
	d.ellipse((c[0] - r - 2.4 * k, c[1] - r - 2.4 * k, c[0] + r + 2.4 * k, c[1] + r + 2.4 * k), fill=OUTLINE)  # тёмно-синий контур значка
	d.ellipse((c[0] - r - k, c[1] - r - k, c[0] + r + k, c[1] + r + k), fill=(250, 250, 253, 255))
	d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), outline=(222, 30, 44, 255), width=int(1.7 * k))
	o = r * 0.7
	d.line((c[0] - o, c[1] - o, c[0] + o, c[1] + o), fill=(222, 30, 44, 255), width=int(1.7 * k))


def badge_help(out, k):
	d = ImageDraw.Draw(out)
	font = ImageFont.truetype(r"C:\Windows\Fonts\segoeuib.ttf", int(13 * k))
	d.text((24.5 * k, 23.5 * k), "?", font=font, fill=FILL, anchor="mm", stroke_width=int(1.6 * k), stroke_fill=OUTLINE)


def perimeter(points, steps=240):
	"""Точки по контуру многоугольника с равным шагом."""
	segs = []
	total = 0.0
	for i in range(len(points)):
		a, b = points[i], points[(i + 1) % len(points)]
		l = math.dist(a, b)
		segs.append((a, b, l))
		total += l
	out = []
	for s in range(steps):
		t = total * s / steps
		for a, b, l in segs:
			if t <= l:
				f = t / l if l else 0
				out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
				break
			t -= l
	return out


def busy_frame(size, frame):
	"""Стрелка, по контуру которой бежит голубой свет с затухающим хвостом."""
	k = size / BASE * SS
	m = arrow_mask(size)
	path = perimeter(ARROW)
	n = len(path)
	head = int(n * frame / FRAMES_BUSY)

	def light(out, kk):
		layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
		d = ImageDraw.Draw(layer)
		tail = int(n * 0.38)
		for j in range(tail):
			p = path[(head - j) % n]
			a = 1.0 - j / tail
			r = (1.25 + 0.4 * a) * kk
			d.ellipse((p[0] * kk - r, p[1] * kk - r, p[0] * kk + r, p[1] * kk + r), fill=GLOW + (int(255 * a),))
		glow = layer.filter(ImageFilter.GaussianBlur(0.9 * kk))
		out.alpha_composite(glow)
		out.alpha_composite(layer)
		inner = Image.new("RGBA", out.size, FILL)
		inner.putalpha(m.filter(ImageFilter.MinFilter(max(3, int(0.6 * kk) | 1))))
		out.alpha_composite(inner)

	return compose(m, size, extra=light)


def wait_frame(size, frame):
	"""Кольцо загрузки: тёмный обод, белое кольцо, по нему крутится голубая дуга."""
	k = size / BASE * SS
	m = canvas(size)
	d = ImageDraw.Draw(m)
	r_out, r_in = 11.5 * k, 6.8 * k
	c = 16 * k
	d.ellipse((c - r_out, c - r_out, c + r_out, c + r_out), fill=255)
	d.ellipse((c - r_in, c - r_in, c + r_in, c + r_in), fill=0)

	def arc(out, kk):
		layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
		ld = ImageDraw.Draw(layer)
		start = 360.0 * frame / FRAMES_WAIT
		width = int(3.6 * kk)
		rr = (r_out + r_in) / 2 + width / 2
		for j in range(24):
			a = 1.0 - j / 24
			ang = start - j * 9
			ld.arc((c - rr, c - rr, c + rr, c + rr), ang - 9, ang, fill=GLOW + (int(255 * a),), width=width)
		hole = Image.new("L", out.size, 0)
		ImageDraw.Draw(hole).ellipse((c - r_out + 0.8 * kk, c - r_out + 0.8 * kk, c + r_out - 0.8 * kk, c + r_out - 0.8 * kk), fill=255)
		ImageDraw.Draw(hole).ellipse((c - r_in - 0.8 * kk, c - r_in - 0.8 * kk, c + r_in + 0.8 * kk, c + r_in + 0.8 * kk), fill=0)
		layer.putalpha(ImageChops.multiply(layer.split()[3], hole))
		out.alpha_composite(layer)

	return compose(m, size, extra=arc)


def main():
	sys.stdout.reconfigure(encoding="utf-8")
	root = os.path.join("hub", "art", "cursors")
	for size in (32, 48):
		folder = os.path.join(root, str(size))
		os.makedirs(folder, exist_ok=True)
		shapes = {
			"arrow": compose(arrow_mask(size), size),
			"hand": compose(hand_mask(size), size),
			"ibeam": compose(ibeam_mask(size), size),
			"cross": compose(cross_mask(size), size),
			"move": compose(arrows_mask(size, [(0, -1), (0, 1), (-1, 0), (1, 0)]), size),
			"vsize": compose(arrows_mask(size, [(0, -1), (0, 1)], spread=7.5), size),
			"hsize": compose(arrows_mask(size, [(-1, 0), (1, 0)], spread=7.5), size),
			"bdiag": compose(arrows_mask(size, [(1, -1), (-1, 1)], spread=7.5), size),
			"fdiag": compose(arrows_mask(size, [(-1, -1), (1, 1)], spread=7.5), size),
			"forbidden": compose(arrow_mask(size), size, extra=badge_forbidden),
			"help": compose(arrow_mask(size), size, extra=badge_help),
		}
		for name, img in shapes.items():
			img.save(os.path.join(folder, name + ".png"))
		for name, count, draw in (("wait", FRAMES_WAIT, wait_frame), ("busy", FRAMES_BUSY, busy_frame)):
			sheet = Image.new("RGBA", (size * count, size), (0, 0, 0, 0))
			for f in range(count):
				sheet.alpha_composite(draw(size, f), (f * size, 0))
			sheet.save(os.path.join(folder, name + ".png"))
		print("курсоры", size)
	# Лист для просмотра (48 px, увеличено ×3) на шахматке.
	names = ["arrow", "move", "wait", "ibeam", "vsize", "hand", "forbidden", "help", "busy", "hsize", "bdiag", "cross"]
	cell = 48 * 3
	view = Image.new("RGBA", (cell * 6, cell * 2), (60, 60, 64, 255))
	dv = ImageDraw.Draw(view)
	for y in range(0, cell * 2, 24):
		for x in range(0, cell * 6, 24):
			if (x // 24 + y // 24) % 2:
				dv.rectangle((x, y, x + 23, y + 23), fill=(44, 44, 48, 255))
	for i, name in enumerate(names):
		img = Image.open(os.path.join(root, "48", name + ".png"))
		if img.width > 48:
			img = img.crop((48 * 2, 0, 48 * 3, 48))
		view.alpha_composite(img.resize((cell, cell), Image.NEAREST), ((i % 6) * cell, (i // 6) * cell))
	os.makedirs(os.path.join("build", "shots"), exist_ok=True)
	view.save(os.path.join("build", "shots", "cursors_sheet.png"))


if __name__ == "__main__":
	main()
