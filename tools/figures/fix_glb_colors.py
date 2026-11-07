"""Чистка цветовых дефектов у моделей из Tripo AI (glb с одной текстурой-атласом).

Генератор закрашивает места, которых не видел на своих ракурсах (макушка, подмышки, низ, щели),
ровным серым (~128,128,128), а на стыках UV-островов в текстуру подтекает серый фон и чужие цвета.
Скрипт для каждого треугольника смотрит его кусок текстуры:
  * серые «непрокрашенные» тексели заменяет цветом самого треугольника, а если он почти весь серый —
    цветом соседних треугольников по сетке (растекание по соседям);
  * треугольник, резко чужой по цвету всем соседям (пятно с другой части модели), перекрашивает в цвет соседей;
  * --base Y — всё ниже доли высоты Y (подставка) красит одним чистым цветом (--base-color);
  * края островов растягивает наружу, чтобы при фильтрации текстуры на швах не было серой каймы.
Результат — новый glb с PNG-текстурой и отладочная картинка (что перекрашено — пурпурным).

python tools/figures/fix_glb_colors.py in.glb out.glb [--base 0.06] [--base-color e8e6ee] [--grey 0.07]
"""
import argparse
import io
import json
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.stdout.reconfigure(encoding="utf-8")


def load_glb(path):
	data = open(path, "rb").read()
	assert data[:4] == b"glTF"
	off = 12
	js = bn = None
	while off < len(data):
		length, kind = struct.unpack_from("<II", data, off)
		chunk = data[off + 8: off + 8 + length]
		if kind == 0x4E4F534A:
			js = json.loads(chunk)
		else:
			bn = bytearray(chunk)
		off += 8 + length
	return js, bn


def accessor(js, bn, index):
	acc = js["accessors"][index]
	view = js["bufferViews"][acc["bufferView"]]
	comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
	dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[acc["componentType"]]
	start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
	stride = view.get("byteStride", 0)
	item = np.dtype(dtype).itemsize * comps
	if stride and stride != item:
		raw = np.frombuffer(bytes(bn[start: start + stride * acc["count"]]), dtype=np.uint8).reshape(acc["count"], stride)[:, :item]
		return np.frombuffer(raw.tobytes(), dtype=dtype).reshape(acc["count"], comps)
	arr = np.frombuffer(bytes(bn[start: start + item * acc["count"]]), dtype=dtype)
	return arr.reshape(acc["count"], comps) if comps > 1 else arr


def save_glb(path, js, bn):
	while len(bn) % 4:
		bn.append(0)
	js["buffers"][0]["byteLength"] = len(bn)
	text = json.dumps(js, ensure_ascii=False).encode("utf-8")
	while len(text) % 4:
		text += b" "
	total = 12 + 8 + len(text) + 8 + len(bn)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, total))
		f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
		f.write(struct.pack("<II", len(bn), 0x004E4942) + bytes(bn))


def visibility(pos, tris, elevations=(0.0, 0.2)):
	"""Для каждой грани: насколько прямо и без заслона её видно с 24 ракурсов (0..1)."""
	a = pos[tris[:, 0]]
	b = pos[tris[:, 1]]
	c = pos[tris[:, 2]]
	normal = np.cross(b - a, c - a)
	normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-12)
	center = (a + b + c) / 3.0
	size = np.abs(pos).max()
	origin = center + normal * size * 1e-3
	e1 = b - a
	e2 = c - a
	best = np.zeros(len(tris))
	for elev in elevations:
		for k in range(12):
			az = k * np.pi / 6.0
			to_cam = np.array([np.sin(az) * np.cos(elev), np.sin(elev), np.cos(az) * np.cos(elev)])
			facing = normal @ to_cam
			blocked = np.zeros(len(tris), dtype=bool)
			cand = np.where(facing > 0.05)[0]
			pvec = np.cross(to_cam, e2)
			det = (e1 * pvec).sum(1)
			ok = np.abs(det) > 1e-12
			inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
			for chunk in np.array_split(cand, max(1, len(cand) // 300)):
				tvec = origin[chunk][:, None, :] - a[None, :, :]
				u = (tvec * pvec[None]).sum(2) * inv[None]
				qvec = np.cross(tvec, e1[None])
				v = (qvec * to_cam).sum(2) * inv[None]
				t = (qvec * e2[None]).sum(2) * inv[None]
				hit = ok[None] & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > size * 1e-4)
				blocked[chunk] = hit.any(1)
			score = np.where(blocked, 0.0, np.maximum(facing, 0.0))
			best = np.maximum(best, score)
	return best


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("src")
	ap.add_argument("dst")
	ap.add_argument("--grey", type=float, default=0.07, help="насыщенность, ниже которой серое считается непрокрашенным")
	ap.add_argument("--grey-min", type=int, default=96)
	ap.add_argument("--grey-max", type=int, default=150)
	ap.add_argument("--hidden-max", type=int, default=238, help="на плохо видимых гранях серое до этой яркости — тоже непрокрашенное")
	ap.add_argument("--seen", type=float, default=0.35, help="порог видимости грани с ракурсов генератора")
	ap.add_argument("--base", type=float, default=0.0, help="доля высоты снизу — подставка одним цветом")
	ap.add_argument("--base-color", default="")
	ap.add_argument("--washed-seen", type=float, default=0.8, help="грань видна сбоку хуже этого — проверять на выцветание")
	ap.add_argument("--washed-radius", type=float, default=0.08, help="радиус соседства для выцветших граней (доля высоты)")
	ap.add_argument("--foreign", type=float, default=110.0, help="плохо видимая грань чужого цвета (дальше этого от соседей) — в цвет соседей")
	ap.add_argument("--outlier", type=float, default=95.0, help="насколько цвет треугольника должен отличаться от всех соседей")
	args = ap.parse_args()

	js, bn = load_glb(args.src)
	prim = js["meshes"][0]["primitives"][0]
	pos = accessor(js, bn, prim["attributes"]["POSITION"]).astype(np.float64)
	uv = accessor(js, bn, prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
	tris = accessor(js, bn, prim["indices"]).astype(np.int64).reshape(-1, 3)
	image_index = js["textures"][js["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]
	view = js["bufferViews"][js["images"][image_index]["bufferView"]]
	tex = Image.open(io.BytesIO(bytes(bn[view.get("byteOffset", 0): view.get("byteOffset", 0) + view["byteLength"]]))).convert("RGB")
	W, H = tex.size
	img = np.asarray(tex).astype(np.int32).copy()
	n = len(tris)

	# 1. Карта «какой треугольник в каком текселе».
	idmap = Image.new("I", (W, H), 0)
	draw = ImageDraw.Draw(idmap)
	for t in range(n):
		pts = [(float(uv[v, 0] * W), float(uv[v, 1] * H)) for v in tris[t]]
		draw.polygon(pts, fill=t + 1, outline=t + 1)
	ids = np.asarray(idmap).astype(np.int64)
	inside = ids > 0

	# 2. Видимость граней с ракурсов генератора (кольцо вокруг модели, горизонт и чуть сверху):
	# что генератор не видел, он закрасил серым — там серое любой яркости считаем непрокрашенным.
	seen = visibility(pos, tris)
	hidden = np.zeros(n + 1, dtype=bool)
	hidden[1:] = seen < args.seen
	print("плохо видимых граней", int(hidden.sum()))
	mx = img.max(2)
	mn = img.min(2)
	sat = (mx - mn) / np.maximum(mx, 1)
	narrow = (sat < args.grey) & (mx >= args.grey_min) & (mx <= args.grey_max)
	wide = (sat < args.grey * 1.6) & (mx >= args.grey_min) & (mx <= args.hidden_max)
	grey = inside & np.where(hidden[ids], wide, narrow)

	# 3. Цвет каждого треугольника: медиана непрокрашенных-не-серых текселей.
	flat = ids[inside]
	cols = img[inside]
	good = ~grey[inside]
	count_all = np.bincount(flat, minlength=n + 1)
	count_good = np.bincount(flat[good], minlength=n + 1)
	color = np.zeros((n + 1, 3))
	order = np.argsort(flat[good], kind="stable")
	sorted_ids = flat[good][order]
	sorted_cols = cols[good][order]
	bounds = np.searchsorted(sorted_ids, np.arange(n + 2))
	for t in range(1, n + 1):
		a, b = bounds[t], bounds[t + 1]
		if b > a:
			color[t] = np.median(sorted_cols[a:b], axis=0)
	known = (count_good >= np.maximum(4, count_all * 0.35))
	known[0] = False
	# треугольник без текселей (слишком мелкий в UV) — по центру
	for t in range(1, n + 1):
		if count_all[t] == 0:
			c = uv[tris[t - 1]].mean(0)
			x, y = min(W - 1, int(c[0] * W)), min(H - 1, int(c[1] * H))
			px = img[y, x]
			s = (px.max() - px.min()) / max(1, px.max())
			if not (s < args.grey and args.grey_min <= px.max() <= args.grey_max):
				color[t] = px
				known[t] = True

	# 4. Соседи по сетке (вершины сварены по положению: швы UV их разделяют).
	key = np.round(pos / (np.abs(pos).max() * 1e-5)).astype(np.int64)
	_, weld = np.unique(key, axis=0, return_inverse=True)
	weld = weld.reshape(-1)
	edges = {}
	for t in range(n):
		w = weld[tris[t]]
		for i in range(3):
			e = (min(w[i], w[(i + 1) % 3]), max(w[i], w[(i + 1) % 3]))
			edges.setdefault(e, []).append(t + 1)
	neigh = [set() for _ in range(n + 1)]
	for ts in edges.values():
		for a in ts:
			for b in ts:
				if a != b:
					neigh[a].add(b)

	# 5. Подставка.
	repaint = np.zeros(n + 1, dtype=bool)
	height = pos[:, 1].max() - pos[:, 1].min()
	if args.base > 0:
		low = pos[:, 1].min() + height * args.base
		base = np.zeros(n + 1, dtype=bool)
		base[1:] = pos[tris, 1].max(1) <= low
		if args.base_color:
			base_rgb = np.array([int(args.base_color[i:i + 2], 16) for i in (0, 2, 4)], dtype=float)
		else:
			base_rgb = np.median(color[base & known], axis=0)
		color[base] = base_rgb
		known[base] = True
		repaint |= base
		print("подставка: треугольников", int(base.sum()), "цвет", base_rgb.astype(int))

	# 6. Чужие пятна: цвет далёк от всех соседей, а соседи между собой похожи.
	for t in range(1, n + 1):
		if not known[t] or repaint[t]:
			continue
		ns = [m for m in neigh[t] if known[m]]
		if len(ns) < 2:
			continue
		d = [np.linalg.norm(color[t] - color[m]) for m in ns]
		if min(d) > args.outlier and seen[t - 1] < 0.9:  # хорошо видимые одиночные детали (заколка, глаз) не трогаем
			known[t] = False
	# 6б. Выцветшие грани: сбоку видно плохо (макушка, верх плеч, носки), а хорошо видимые грани рядом
	# заметно насыщеннее — генератор смешал их цвет с серым. Тёмные детали (< 120) не трогаем.
	seen_h = np.zeros(n + 1)
	seen_h[1:] = visibility(pos, tris, (0.0,))
	centers = np.zeros((n + 1, 3))
	centers[1:] = pos[tris].mean(1)
	csat = np.zeros(n + 1)
	cval = color.max(1)
	csat = (color.max(1) - color.min(1)) / np.maximum(color.max(1), 1)
	well = known & (seen_h >= args.washed_seen)
	well[0] = False
	well_ids = np.where(well)[0]
	radius = height * args.washed_radius
	washed = 0
	locked = repaint.copy()  # подставка и прочее, перекрашенное раньше, не трогаем
	for t in [t for _ in range(2) for t in range(1, n + 1)]:  # два прохода: перекрашенные становятся опорой
		if not known[t] or locked[t] or (repaint[t] and t in well_ids) or seen_h[t] >= args.washed_seen or cval[t] < 120:
			continue
		d = np.linalg.norm(centers[well_ids] - centers[t], axis=1)
		near = well_ids[d < radius]
		if len(near) < 3:
			continue
		ref = np.median(color[near], axis=0)
		ref_sat = (ref.max() - ref.min()) / max(1.0, ref.max())
		foreign = np.linalg.norm(color[t] - ref) > args.foreign and len(near) >= 5
		if foreign or (ref_sat >= 0.25 and csat[t] < ref_sat * 0.75 and ref_sat - csat[t] > 0.1):
			# цвет — от хорошо видимых граней рядом (соседи по сетке сами могут быть выцветшими)
			color[t] = ref
			repaint[t] = True
			csat[t] = ref_sat
			washed += 1
			if t not in well_ids:
				well_ids = np.append(well_ids, t)
	print("выцветших граней", washed)
	outliers = int(sum(1 for t in range(1, n + 1) if not known[t] and count_good[t] >= max(4, count_all[t] * 0.35)))

	# 7. Неизвестные — растекание цвета соседей.
	unknown = [t for t in range(1, n + 1) if not known[t]]
	print("треугольников", n, "непрокрашенных/чужих", len(unknown), "(чужих пятен", outliers, ")")
	pending = set(unknown)
	for _ in range(200):
		if not pending:
			break
		done = []
		for t in pending:
			ns = [m for m in neigh[t] if known[m]]
			if ns:
				color[t] = np.median([color[m] for m in ns], axis=0)
				done.append(t)
		if not done:
			break
		for t in done:
			known[t] = True
			repaint[t] = True
			pending.discard(t)

	# 8. Перекраска текселей: целиком у перекрашенных треугольников, только серое — у остальных.
	tri_of = ids
	fill = color[tri_of].astype(np.int32)
	whole = repaint[tri_of] & inside
	# внутри насыщенного треугольника, плохо видимого сбоку, — выцветшие тексели (серые разводы на волосах)
	tsat = (color.max(1) - color.min(1)) / np.maximum(color.max(1), 1)
	pale = inside & (seen_h[tri_of] < args.washed_seen + 0.1) & (tsat[tri_of] >= 0.3) & (sat < tsat[tri_of] * 0.45) & (mx >= 110)
	mask = whole | grey | pale
	out = img.copy()
	out[mask] = fill[mask]
	debug = img.copy()
	debug[mask] = (255, 0, 255)

	# 9. Края островов — наружу на 8 текселей (без серой каймы на швах).
	filled = inside.copy()
	for _ in range(8):
		grow = np.zeros_like(filled)
		acc = np.zeros_like(out)
		cnt = np.zeros(filled.shape, dtype=np.int32)
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			sh = np.roll(np.roll(filled, dy, 0), dx, 1)
			src = np.roll(np.roll(out, dy, 0), dx, 1)
			add = sh & ~filled
			acc[add] += src[add]
			cnt[add] += 1
			grow |= add
		out[grow] = acc[grow] // cnt[grow][:, None]
		filled |= grow

	result = Image.fromarray(out.clip(0, 255).astype(np.uint8))
	Image.fromarray(debug.clip(0, 255).astype(np.uint8)).resize((1024, 1024)).save(args.dst.replace(".glb", "_debug.png"))
	buf = io.BytesIO()
	result.save(buf, "PNG", optimize=True)
	png = buf.getvalue()
	while len(bn) % 4:
		bn.append(0)
	js["bufferViews"].append({"buffer": 0, "byteOffset": len(bn), "byteLength": len(png)})
	bn.extend(png)
	js["images"][image_index] = {"bufferView": len(js["bufferViews"]) - 1, "mimeType": "image/png"}
	save_glb(args.dst, js, bn)
	print("перекрашено текселей", int(mask.sum()), "→", args.dst)


if __name__ == "__main__":
	main()
