"""Ассеты «книжного» гримуара Clocktower: разворот книги, кляксы, набросок часов и чернильные иконки ролей.
Всё рисуется процедурно (PIL), детерминированно по seed. Запуск из корня проекта:
    python tools/bc_grimoire_art.py
Результат: games/blood_on_the_clocktower/art/grimoire/*.png и art/roles_ink/*.png.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / 'games/blood_on_the_clocktower/art'
OUT = ART / 'grimoire'
INK = (43, 27, 18)          # бурые чернила
PAPER = (226, 205, 160)     # старый пергамент


def noise(size, scale, seed, lo=0, hi=255):
    """Мягкий шум: случайная маленькая картинка, растянутая и размытая."""
    rnd = random.Random(seed)
    w, h = max(2, size[0] // scale), max(2, size[1] // scale)
    small = Image.new('L', (w, h))
    small.putdata([rnd.randint(lo, hi) for _ in range(w * h)])
    return small.resize(size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(scale / 3))


def blot(size, seed, splatter=True):
    """Клякса: неровная капля из перекрывающихся кругов + брызги, края слегка размыты."""
    rnd = random.Random(seed)
    img = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(img)
    c = size / 2
    r = size * 0.22
    for _ in range(26):
        a = rnd.uniform(0, math.tau)
        dist = rnd.uniform(0, r * 0.7)
        rr = rnd.uniform(r * 0.35, r * 0.75)
        x, y = c + math.cos(a) * dist, c + math.sin(a) * dist
        d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=255)
    if splatter:
        for _ in range(rnd.randint(10, 18)):
            a = rnd.uniform(0, math.tau)
            dist = rnd.uniform(r * 1.1, size * 0.47)
            rr = rnd.uniform(1.5, size * 0.03)
            x, y = c + math.cos(a) * dist, c + math.sin(a) * dist
            d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=255)
            # «хвост» брызги к центру
            if rnd.random() < 0.4:
                x2, y2 = c + math.cos(a) * (dist - rr * 4), c + math.sin(a) * (dist - rr * 4)
                d.line((x, y, x2, y2), fill=255, width=max(1, int(rr * 0.7)))
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    # Внутри клякса чуть неравномерная — чернила подсыхают пятнами.
    inner = noise((size, size), 12, seed + 1, 190, 255)
    alpha = ImageChops.multiply(img, inner)
    out = Image.new('RGBA', (size, size), INK + (0,))
    out.putalpha(alpha)
    return out


def book(width=1600, height=1000, seed=7):
    rnd = random.Random(seed)
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    # Переплёт: тёмно-бордовая кожа с зерном.
    cover = Image.new('RGB', (width, height), (74, 28, 24))
    grain = noise((width, height), 3, seed, 0, 255)
    cover = Image.composite(Image.new('RGB', (width, height), (58, 20, 18)), cover, grain.point(lambda v: 90 if v > 150 else 0))
    mask = Image.new('L', (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=42, fill=255)
    img.paste(cover, (0, 0), mask)
    # Тиснёная рамка по краю обложки.
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((14, 14, width - 15, height - 15), radius=34, outline=(120, 70, 40, 160), width=3)
    # Страницы: две половины с отступом от края обложки; срез страниц — тонкие линии.
    m = 46
    gutter = width // 2
    pages = Image.new('RGB', (width, height), PAPER)
    fibres = noise((width, height), 2, seed + 2, 0, 255)
    blotches = noise((width, height), 60, seed + 3, 0, 255)
    pages = Image.composite(Image.new('RGB', (width, height), (205, 180, 132)), pages, blotches.point(lambda v: int(max(0, v - 135) * 0.8)))
    pages = Image.composite(Image.new('RGB', (width, height), (236, 220, 182)), pages, fibres.point(lambda v: 70 if v > 200 else 0))
    page_mask = Image.new('L', (width, height), 0)
    pd = ImageDraw.Draw(page_mask)
    # слегка выгнутые страницы — верх/низ дугой
    for side in (0, 1):
        x0 = m if side == 0 else gutter + 4
        x1 = gutter - 4 if side == 0 else width - m
        poly = []
        steps = 40
        for i in range(steps + 1):
            t = i / steps
            x = x0 + (x1 - x0) * t
            bow = math.sin(t * math.pi) * 10
            lift = (1 - t) * 14 if side == 1 else t * 14
            poly.append((x, m - bow + lift * 0.5))
        for i in range(steps, -1, -1):
            t = i / steps
            x = x0 + (x1 - x0) * t
            bow = math.sin(t * math.pi) * 10
            lift = (1 - t) * 14 if side == 1 else t * 14
            poly.append((x, height - m + bow - lift * 0.3))
        pd.polygon(poly, fill=255)
    img.paste(pages, (0, 0), page_mask)
    # Тень корешка и затемнение к краям страниц (объём).
    shade = Image.new('L', (width, height), 0)
    sd = ImageDraw.Draw(shade)
    for i in range(90):
        v = int(150 * (1 - i / 90) ** 2)
        sd.line((gutter - i, 0, gutter - i, height), fill=v)
        sd.line((gutter + i, 0, gutter + i, height), fill=v)
    for i in range(40):
        v = int(70 * (1 - i / 40) ** 2)
        sd.line((m + i, 0, m + i, height), fill=v)
        sd.line((width - m - i, 0, width - m - i, height), fill=v)
    # Старая бумага темнеет к углам и краям страниц.
    edge = Image.new('L', (width, height), 0)
    ed = ImageDraw.Draw(edge)
    for i in range(70):
        v = int(55 * (1 - i / 70) ** 1.6)
        ed.rectangle((m + i, m + i, width - m - i, height - m - i), outline=v)
    shade = ImageChops.lighter(shade, edge)
    shade = ImageChops.multiply(shade, page_mask)
    dark = Image.new('RGBA', (width, height), (60, 35, 20, 255))
    dark.putalpha(shade)
    img = Image.alpha_composite(img, dark)
    # Срез страниц: несколько тонких линий под краем.
    d = ImageDraw.Draw(img)
    for k in range(1, 6):
        c = (190 - k * 12, 165 - k * 12, 120 - k * 10, 255)
        d.line((m - k * 3, m + 30, m - k * 3, height - m - 30), fill=c, width=1)
        d.line((width - m + k * 3, m + 30, width - m + k * 3, height - m - 30), fill=c, width=1)
    # Кофейные круги и пара клякс прямо на бумаге.
    for _ in range(2):
        cx = rnd.randint(gutter + 120, width - 220)
        cy = rnd.randint(height - 300, height - 140)
        r = rnd.randint(55, 75)
        ring = Image.new('L', (width, height), 0)
        rd = ImageDraw.Draw(ring)
        rd.ellipse((cx - r, cy - r, cx + r, cy + r), outline=60, width=6)
        ring = ring.filter(ImageFilter.GaussianBlur(3))
        stain = Image.new('RGBA', (width, height), (120, 80, 40, 255))
        stain.putalpha(ImageChops.multiply(ring, page_mask))
        img = Image.alpha_composite(img, stain)
        break
    for i, (x, y, s) in enumerate([(gutter - 170, height - 150, 120), (width - m - 40, height // 2 + 60, 80), (gutter - 70, height // 2 - 40, 60)]):
        b = blot(s, seed + 10 + i)
        b.putalpha(b.getchannel('A').point(lambda v: int(v * 0.85)))
        img.alpha_composite(b, (x - s // 2, y - s // 2))
    # Нитки ляссе (закладки) у корешка.
    d = ImageDraw.Draw(img)
    d.line((gutter + 6, m - 20, gutter + 22, height - m + 60), fill=(120, 20, 30, 255), width=7)
    d.line((gutter + 8, m - 20, gutter + 24, height - m + 60), fill=(150, 35, 40, 255), width=2)
    return img


SUPER = 4  # сглаживание: рисуем крупнее, потом уменьшаем


def clock_sketch(size=360, seed=3):
    """Часы в SUPER раз крупнее с уменьшением — плавные края линий."""
    big = _clock_sketch(size * SUPER, seed, SUPER)
    return big.resize((size, size), Image.LANCZOS)


def _clock_sketch(size, seed, k):
    """Набросок часов башни чернилами: двойной круг, римские засечки, стрелки, лёгкая дрожь линий."""
    rnd = random.Random(seed)
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2

    def shaky_circle(r, width):
        pts = []
        # Плавная дрожь пера: две медленные волны, а не шум в каждой точке (иначе край «рубчатый»).
        ph1, ph2 = rnd.uniform(0, math.tau), rnd.uniform(0, math.tau)
        for i in range(361):
            a = i / 360 * math.tau
            rr = r + (math.sin(a * 3 + ph1) * 1.1 + math.sin(a * 7 + ph2) * 0.5) * k
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
        d.line(pts, fill=INK + (200,), width=width * k, joint='curve')

    shaky_circle(size * 0.45, 3)
    shaky_circle(size * 0.40, 2)
    for i in range(12):
        a = i / 12 * math.tau - math.pi / 2
        r1, r2 = size * 0.33, size * 0.39
        w = 4 if i % 3 == 0 else 2
        d.line((c + math.cos(a) * r1, c + math.sin(a) * r1, c + math.cos(a) * r2, c + math.sin(a) * r2), fill=INK + (210,), width=w * k)
    for i in range(60):
        a = i / 60 * math.tau
        r1 = size * 0.385
        x, y = c + math.cos(a) * r1, c + math.sin(a) * r1
        d.ellipse((x - k * 0.7, y - k * 0.7, x + k * 0.7, y + k * 0.7), fill=INK + (160,))
    # стрелки на «без пяти полночь»
    for angle, length, w in ((-math.pi / 2 - 0.45, 0.26, 5), (-math.pi / 2 - 0.05, 0.34, 3)):
        d.line((c, c, c + math.cos(angle) * size * length, c + math.sin(angle) * size * length), fill=INK + (230,), width=w * k)
    d.ellipse((c - 7 * k, c - 7 * k, c + 7 * k, c + 7 * k), fill=INK + (230,))
    return img.filter(ImageFilter.GaussianBlur(0.5 * k))


def moon_sketch(size=240, seed=5):
    """Месяц в SUPER раз крупнее с уменьшением — плавные края."""
    return _moon_sketch(size * SUPER, seed, SUPER).resize((size, size), Image.LANCZOS)


def _moon_sketch(size, seed, k):
    """Месяц и звёзды пером — набросок на полях."""
    rnd = random.Random(seed)
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    full = Image.new('L', (size, size), 0)
    ImageDraw.Draw(full).ellipse((size * 0.18, size * 0.18, size * 0.72, size * 0.72), fill=255)
    cut = Image.new('L', (size, size), 0)
    ImageDraw.Draw(cut).ellipse((size * 0.32, size * 0.1, size * 0.86, size * 0.64), fill=255)
    crescent = ImageChops.subtract(full, cut)
    outline = crescent.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(3 * k + (1 - k % 2)))
    hatch = Image.new('L', (size, size), 0)
    hd = ImageDraw.Draw(hatch)
    for step in range(-size, size, 7 * k):
        hd.line((step, size, step + size, 0), fill=150, width=k)
    lines = ImageChops.lighter(outline, ImageChops.multiply(hatch, crescent))
    img.putalpha(lines.filter(ImageFilter.GaussianBlur(0.4 * k)))
    ink = Image.new('RGBA', (size, size), INK + (255,))
    ink.putalpha(img.getchannel('A'))
    d = ImageDraw.Draw(ink)
    for _ in range(4):
        x, y = rnd.uniform(size * 0.6, size * 0.92), rnd.uniform(size * 0.55, size * 0.92)
        r = rnd.uniform(5, 10) * k
        for a in range(4):
            ang = a * math.pi / 4
            d.line((x - math.cos(ang) * r, y - math.sin(ang) * r, x + math.cos(ang) * r, y + math.sin(ang) * r), fill=INK + (200,), width=2 * k)
    return ink


def ink_icon(src: Path, dst: Path):
    """Иконка роли «чернилами»: тёмные бурые линии по яркости и прозрачности исходной гравюры."""
    im = Image.open(src).convert('RGBA')
    alpha = im.getchannel('A')
    lum = im.convert('L')
    # Тёмное в исходнике — гуще чернила; светлые блики почти прозрачны.
    density = lum.point(lambda v: int(255 - v * 0.75))
    a = ImageChops.multiply(alpha, density)
    bbox = alpha.getbbox()
    out = Image.new('RGBA', im.size, INK + (0,))
    out.putalpha(a.filter(ImageFilter.GaussianBlur(0.4)))
    if bbox:
        pad = 6
        bbox = (max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(im.width, bbox[2] + pad), min(im.height, bbox[3] + pad))
        out = out.crop(bbox)
        side = max(out.size)
        square = Image.new('RGBA', (side, side), INK + (0,))
        square.paste(out, ((side - out.width) // 2, (side - out.height) // 2))
        out = square.resize((160, 160), Image.LANCZOS)
    out.save(dst)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    book().save(OUT / 'book.png')
    for i in range(3):
        blot(220, 100 + i).save(OUT / ('blot_%d.png' % (i + 1)))
    clock_sketch().save(OUT / 'clock.png')
    moon_sketch().save(OUT / 'moon.png')
    ink = ART / 'roles_ink'
    ink.mkdir(exist_ok=True)
    count = 0
    for src in sorted((ART / 'roles').glob('*.png')):
        ink_icon(src, ink / src.name)
        count += 1
    print('book, 3 blots, clock, %d ink icons' % count)


if __name__ == '__main__':
    main()
