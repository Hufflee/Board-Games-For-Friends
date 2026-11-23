"""Сборка релизов с автообновлением: полная «база» и инкрементальные PCK-патчи.

Запуск из корня проекта (Godot — из CLAUDE.md, другой путь — env GODOT):
    python tools/release/release.py base 0.8.9            # полная версия: exe + base.pck + zip + latest.json
    python tools/release/release.py patch 0.8.10          # патч: только изменённое с прошлой версии
    python tools/release/release.py full 0.9.1.2 --patch-from 0.9.1   # полная сборка той же версии рядом с патчем
    python tools/release/release.py finalize              # перейти на эту полную сборку как на новую базу
    python tools/release/release.py status                # текущая база и цепочка патчей
    python tools/release/release.py publish 0.8.10        # выложить собранное на GitHub (gh release create)
    python tools/release/release.py serve                 # раздать текущую базу локально (проверка апдейтера)

Ключи base/patch: --title "0.8.10 — ..." (заголовок релиза), --no-bump (не трогать версию в
project.godot / export_presets.cfg), --local http://127.0.0.1:8765/ (ссылки в latest.json — на
локальный сервер, для проверки). patch --with-social — новый BGSocial.exe рядом с патчем.
patch --allow-project — изменения project.godot, которые патчу не
нужны (имя, иконка, папка данных та же): печатает их и собирает. publish — только с согласия владельца.

Две посылки одной версии (переход на новую базу без лишних загрузок):
1. `patch V` — патч к текущей линии (старые клиенты с exe этой линии берут его, как раньше);
   `full V --patch-from P` — полная сборка V (exe игры + BGSocial.exe; он же отдельным файлом — поле "social") в build/releases/V/ и поле "full"
   с "patch_from": P в манифесте. Новый клиент (update_client.gd с 0.9.1.2) качает патчи, только если
   его цепочка цела и не ниже P, иначе — полную сборку. `publish V` выкладывает патч, zip и манифест.
2. Позже `finalize`: текущей базой становится полная сборка V, старая линия уходит в "lines" манифеста
   (новые клиенты на старом exe дальше получают патчи; `patch` собирает их и для старых линий).
   Старый клиент на старом exe с этого момента скачает полную сборку — см. docs/UPDATE_MIGRATION.md.

Что где: build/releases/<база>/ — base.pck, zip базы, patch-<v>.pck, chain.json, fingerprint.json,
latest.json, notes-<v>.md. build/releases/current.txt — версия текущей базы.
Патч нельзя, если с базы изменились project.godot (кроме версии), версия Godot или GodotSteam —
тогда нужна новая база (команда base). Игра качает latest.json из последнего релиза:
https://github.com/<repo>/releases/latest/download/latest.json
"""
from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from functools import partial
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO = "Hufflee/Board-Games-For-Friends"
GODOT = os.environ.get("GODOT", r"C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe")
PRESET = "Windows"
OUT = ROOT / "build" / "releases"
EXE_DIR = ROOT / "build" / "windows"
# Что кладётся в zip базы (решение владельца: без КАК_ИГРАТЬ.md).
GAME_EXE = "BoardGameShelf.exe"
BASE_FILES = [GAME_EXE, "libgodotsteam.windows.template_release.x86_64.dll", "steam_api64.dll", "steam_appid.txt"]
# Второй exe — BGSocial (пресет «BGS Social», feature bgs_social, без арта и музыки игр): кладётся в
# полную сборку и отдельным файлом релиза — клиент докачивает его, если в папке игры его нет.
SOCIAL_PRESET = "BGS Social"
SOCIAL_EXE = "BGSocial.exe"
# Файлы, которые патч не может обновить (загружены до подключения патчей).
UNPATCHABLE = ["hub/update/updater.gd"]


def die(msg: str) -> None:
	print("ОШИБКА:", msg)
	sys.exit(1)


def sha256(path: Path) -> str:
	h = hashlib.sha256()
	with open(path, "rb") as f:
		for chunk in iter(lambda: f.read(4 << 20), b""):
			h.update(chunk)
	return h.hexdigest()


def read_json(path: Path, default):
	return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def write_json(path: Path, data) -> None:
	path.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")


def godot(*args: str) -> None:
	cmd = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), *args]
	print(">", " ".join(cmd))
	if subprocess.run(cmd).returncode != 0:
		die("Godot завершился с ошибкой")


def godot_version() -> str:
	return subprocess.run([GODOT, "--version"], capture_output=True, text=True).stdout.strip()


def project_version() -> str:
	m = re.search(r'^config/version="([^"]*)"', (ROOT / "project.godot").read_text(encoding="utf-8"), re.M)
	return m.group(1) if m else ""


def set_version(v: str) -> None:
	"""Поднять версию в project.godot и export_presets.cfg (file/product_version)."""
	pg = ROOT / "project.godot"
	text = pg.read_text(encoding="utf-8")
	pg.write_text(re.sub(r'^config/version="[^"]*"', f'config/version="{v}"', text, count=1, flags=re.M), encoding="utf-8")
	ep = ROOT / "export_presets.cfg"
	four = ".".join((v.split("-")[0].split(".") + ["0", "0", "0", "0"])[:4])
	text = ep.read_text(encoding="utf-8")
	text = re.sub(r'^application/(file|product)_version="[^"]*"', lambda m: f'application/{m.group(1)}_version="{four}"', text, flags=re.M)
	ep.write_text(text, encoding="utf-8")


def fingerprint() -> dict:
	"""То, что должно совпадать у базы и патча."""
	pg = (ROOT / "project.godot").read_text(encoding="utf-8")
	pg = re.sub(r'^config/version="[^"]*"\n?', "", pg, flags=re.M)
	steam = {}
	for p in sorted((ROOT / "addons" / "godotsteam").rglob("*")):
		if p.is_file() and (p.suffix in (".dll", ".gdextension") and not p.name.startswith("~")):
			steam[p.relative_to(ROOT).as_posix()] = sha256(p)
	unpatch = {f: sha256(ROOT / f) for f in UNPATCHABLE if (ROOT / f).exists()}
	return {"godot": godot_version(), "project": hashlib.sha256(pg.encode()).hexdigest(), "steam": steam, "unpatchable": unpatch}


def url_for(version: str, file: str, local: str) -> str:
	if local:
		return local.rstrip("/") + "/" + file
	return f"https://github.com/{REPO}/releases/download/v{version}/{file}"


def base_dir() -> Path:
	cur = OUT / "current.txt"
	if not cur.exists():
		die("нет текущей базы — сначала `release.py base <версия>`")
	return OUT / cur.read_text(encoding="utf-8").strip()


def line_entries(bdir: Path, local: str) -> tuple[dict, list]:
	"""База линии и её патчи со ссылками (каждый файл лежит в релизе своей версии)."""
	info = read_json(bdir / "base.json", {})
	base = dict(info, url=url_for(info["version"], info["file"], local))
	return base, [dict(p, url=url_for(p["version"], p["file"], local)) for p in read_json(bdir / "chain.json", [])]


def write_manifest(bdir: Path, local: str) -> dict:
	base, patches = line_entries(bdir, local)
	versions = [base["version"]] + [p["version"] for p in patches]
	m = {"format": 1, "version": "", "page": "", "base": base, "patches": patches}
	full = read_json(bdir / "full.json", {})
	if full:
		# Переход: полная сборка той же версии для установок, которым патчи не годятся.
		m["full"], _ = line_entries(OUT / full["dir"], local)
		m["patch_from"] = full["patch_from"]
		versions.append(m["full"]["version"])
	legacy = read_json(bdir / "legacy.json", {})
	if legacy:
		# После перехода: старые exe остаются на своих линиях (читает только новый клиент).
		m["lines"] = [{"base": base["version"], "patches": patches}]
		for d in legacy["lines"]:
			lb, lp = line_entries(OUT / d, local)
			m["lines"].append({"base": lb["version"], "patches": lp})
			versions += [p["version"] for p in lp]
		m["patch_from"] = legacy["patch_from"]
	for version in sorted(set(versions), key=version_key, reverse=True):
		social = read_json(OUT / version / "social.json", {})
		if social.get("version") == version:
			m["social"] = dict(social, url=url_for(version, social["file"], local))
			break
	latest = max(versions, key=version_key)
	m["version"] = latest
	m["page"] = f"https://github.com/{REPO}/releases/tag/v{latest}"
	write_json(bdir / "latest.json", m)
	return m


def notes_for(version: str) -> str:
	"""Раздел «## Версия X…» из hub/whats_new.md (или «В разработке», если версии ещё нет)."""
	text = (ROOT / "hub" / "whats_new.md").read_text(encoding="utf-8")
	for head in (rf"## Версия {re.escape(version)}\b[^\n]*", r"## В разработке[^\n]*"):
		m = re.search(head + r"\n(.*?)(?=\n## |\Z)", text, re.S)
		if m:
			return m.group(1).strip() + "\n"
	return ""


def describe_social(bdir: Path, version: str) -> None:
	exe = bdir / SOCIAL_EXE
	write_json(bdir / "social.json", {"version": version, "file": SOCIAL_EXE, "size": exe.stat().st_size, "sha256": sha256(exe)})


def build_patch_social(version: str) -> None:
	"""Собирает отдельный BGSocial.exe без смены базы игры."""
	if project_version() != version:
		die(f"в project.godot версия {project_version()}, а собираем BGSocial {version}")
	bdir = OUT / version
	bdir.mkdir(parents=True, exist_ok=True)
	with tempfile.TemporaryDirectory(prefix="social-", dir=bdir) as stage:
		exe = Path(stage) / SOCIAL_EXE
		godot("--export-release", SOCIAL_PRESET, str(exe))
		if not exe.is_file() or exe.stat().st_size == 0:
			die(f"Godot не создал {SOCIAL_EXE}")
		exe.replace(bdir / SOCIAL_EXE)
	describe_social(bdir, version)


def build_full(a) -> Path:
	"""Полная сборка: exe игры и BGSocial в build/windows, base.pck (основа будущих патчей) и zip в build/releases/<v>/."""
	v = a.version
	if not a.no_bump:
		set_version(v)
	if project_version() != v:
		die(f"в project.godot версия {project_version()}, а собираем {v}")
	bdir = OUT / v
	bdir.mkdir(parents=True, exist_ok=True)
	EXE_DIR.mkdir(parents=True, exist_ok=True)
	godot("--export-release", PRESET, str(EXE_DIR / GAME_EXE))
	godot("--export-release", SOCIAL_PRESET, str(EXE_DIR / SOCIAL_EXE))
	godot("--export-pack", PRESET, str(bdir / "base.pck"))
	zname = f"PartyWorld-{v}-Windows.zip"
	with zipfile.ZipFile(bdir / zname, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
		for f in BASE_FILES + [SOCIAL_EXE]:
			src = EXE_DIR / f
			if not src.exists():
				die(f"нет {src}")
			z.write(src, f)
	zp = bdir / zname
	write_json(bdir / "base.json", {"version": v, "file": zname, "size": zp.stat().st_size, "sha256": sha256(zp)})
	shutil.copy2(EXE_DIR / SOCIAL_EXE, bdir / SOCIAL_EXE)
	describe_social(bdir, v)
	write_json(bdir / "chain.json", [])
	write_json(bdir / "fingerprint.json", fingerprint())
	(bdir / f"notes-{v}.md").write_text(notes_for(v), encoding="utf-8")
	if a.title:
		write_json(bdir / f"title-{v}.json", a.title)
	print(f"Полная сборка {v}: {zp} ({zp.stat().st_size / 1048576:.1f} МБ)")
	return bdir


def cmd_base(a) -> None:
	bdir = build_full(a)
	(OUT / "current.txt").write_text(a.version, encoding="utf-8")
	write_manifest(bdir, a.local)
	print(f"База {a.version} готова. Выложить: release.py publish {a.version}")


def cmd_full(a) -> None:
	"""Полная сборка той же версии, что и последний патч текущей линии (переход на новую базу, шаг 1)."""
	cur = base_dir()
	chain = read_json(cur / "chain.json", [])
	if not chain or chain[-1]["version"] != a.version:
		die(f"сначала патч {a.version} к текущей линии (release.py patch {a.version}) — полная сборка идёт рядом с ним")
	if not a.patch_from:
		die("нужен --patch-from <версия>: с какой действующей версии обновлять патчами")
	a.no_bump = True  # версию уже поднял patch
	build_full(a)
	write_json(cur / "full.json", {"dir": a.version, "patch_from": a.patch_from})
	m = write_manifest(cur, a.local)
	print(f"В манифесте: патчи для цепочек от {a.patch_from}, остальным — полная сборка ({m['full']['size'] / 1048576:.1f} МБ).")


def cmd_finalize(a) -> None:
	"""Шаг 2: полная сборка становится базой, старая линия — в "lines" (для нового клиента)."""
	cur = base_dir()
	full = read_json(cur / "full.json", {})
	if not full:
		die("нет full.json — сначала release.py full <версия>")
	new = OUT / full["dir"]
	old = read_json(cur / "legacy.json", {"lines": []})["lines"]
	write_json(new / "legacy.json", {"lines": [cur.name] + old, "patch_from": full["patch_from"]})
	(OUT / "current.txt").write_text(full["dir"], encoding="utf-8")
	write_manifest(new, a.local)
	print(f"Текущая база — {full['dir']}; старые линии {[cur.name] + old} — в манифесте для нового клиента.")
	print("Манифест выкладывается со следующим релизом (release.py patch/publish) — порядок: docs/UPDATE_MIGRATION.md.")


def cmd_patch(a) -> None:
	v = a.version
	bdir = base_dir()
	info = read_json(bdir / "base.json", {})
	chain = read_json(bdir / "chain.json", [])
	prev = chain[-1]["version"] if chain else info["version"]
	if any(p["version"] == v for p in chain) or v == info["version"]:
		die(f"версия {v} уже есть в цепочке")
	if version_key(v) <= version_key(prev):
		die(f"версия {v} должна быть новее {prev}")
	old = read_json(bdir / "fingerprint.json", {})
	if not a.no_bump:
		set_version(v)
	now = fingerprint()
	for key, what in (("godot", "версия Godot"), ("project", "project.godot (autoload'ы, настройки)"), ("steam", "GodotSteam")):
		if old.get(key) != now.get(key):
			if key == "project" and a.allow_project:
				print("ВНИМАНИЕ: project.godot изменён с базы — у игроков на патчах эти настройки останутся от базы:")
				subprocess.run(["git", "--no-pager", "diff", "HEAD", "--", "project.godot"], cwd=ROOT)
				continue
			die(f"с базы {info['version']} изменилось: {what} — патчем не доставить, нужна полная версия (release.py base)")
	if old.get("unpatchable") != now.get("unpatchable"):
		print("ВНИМАНИЕ: изменён", ", ".join(UNPATCHABLE), "— у игроков он обновится только с новой базой.")
	packs = [bdir / "base.pck"] + [bdir / p["file"] for p in chain]
	for p in packs:
		if not p.exists():
			die(f"нет {p}")
	fname = f"patch-{v}.pck"
	godot("--export-patch", PRESET, str(bdir / fname), "--patches", ",".join(str(p) for p in packs))
	fp = bdir / fname
	if not fp.exists():
		die("Godot не создал патч")
	if a.with_social:
		build_patch_social(v)
	chain.append({"version": v, "file": fname, "size": fp.stat().st_size, "sha256": sha256(fp)})
	write_json(bdir / "chain.json", chain)
	# Старые линии (после finalize): тот же патч, но от их базы и цепочки — своё имя файла в релизе.
	for d in read_json(bdir / "legacy.json", {"lines": []})["lines"]:
		ldir = OUT / d
		lchain = read_json(ldir / "chain.json", [])
		lpacks = [ldir / "base.pck"] + [ldir / p["file"] for p in lchain]
		lname = f"patch-{v}-from-{d}.pck"
		godot("--export-patch", PRESET, str(ldir / lname), "--patches", ",".join(str(p) for p in lpacks))
		lchain.append({"version": v, "file": lname, "size": (ldir / lname).stat().st_size, "sha256": sha256(ldir / lname)})
		write_json(ldir / "chain.json", lchain)
		print(f"  для линии {d}: {lname} ({(ldir / lname).stat().st_size / 1048576:.2f} МБ)")
	(bdir / f"notes-{v}.md").write_text(notes_for(v), encoding="utf-8")
	if a.title:
		write_json(bdir / f"title-{v}.json", a.title)
	write_manifest(bdir, a.local)
	print(f"Патч {v} готов: {fp} ({fp.stat().st_size / 1048576:.2f} МБ). Выложить: release.py publish {v}")


def version_key(v: str) -> tuple:
	return tuple(int(x) for x in v.split("-")[0].split("."))


def cmd_publish(a) -> None:
	v = a.version
	bdir = base_dir()
	info = read_json(bdir / "base.json", {})
	chain = read_json(bdir / "chain.json", [])
	m = write_manifest(bdir, "")  # на GitHub — всегда ссылки GitHub
	if m["version"] != v:
		die(f"последняя собранная версия — {m['version']}, а не {v}")
	# Все файлы версии v: база или патч текущей линии, полная сборка рядом, патчи старых линий.
	assets = [bdir / info["file"]] if v == info["version"] else [bdir / p["file"] for p in chain if p["version"] == v]
	full = read_json(bdir / "full.json", {})
	if full and full["dir"] == v:
		assets.append(OUT / v / read_json(OUT / v / "base.json", {})["file"])
	if m.get("social", {}).get("version") == v:
		assets.append(OUT / v / SOCIAL_EXE)
	for d in read_json(bdir / "legacy.json", {"lines": []})["lines"]:
		assets += [OUT / d / p["file"] for p in read_json(OUT / d / "chain.json", []) if p["version"] == v]
	for f in assets:
		if not f.exists():
			die(f"нет {f}")
	title = read_json(bdir / f"title-{v}.json", f"{v}")
	cmd = ["gh", "release", "create", f"v{v}", *map(str, assets), str(bdir / "latest.json"), "--repo", REPO,
		"--title", title, "--notes-file", str(bdir / f"notes-{v}.md"), "--latest"]
	print(">", " ".join(cmd))
	if subprocess.run(cmd).returncode != 0:
		die("gh release create не прошёл")
	print(f"Опубликовано: https://github.com/{REPO}/releases/tag/v{v}")


def cmd_status(_a) -> None:
	bdir = base_dir()
	info = read_json(bdir / "base.json", {})
	print(f"База {info.get('version')}: {info.get('file')} ({info.get('size', 0) / 1048576:.1f} МБ)")
	full = read_json(bdir / "full.json", {})
	if full:
		print(f"  полная сборка {full['dir']} рядом, патчи — от {full['patch_from']}")
	for p in read_json(bdir / "chain.json", []):
		print(f"  патч {p['version']}: {p['file']} ({p['size'] / 1048576:.2f} МБ)")


def cmd_serve(a) -> None:
	bdir = base_dir()
	write_manifest(bdir, f"http://127.0.0.1:{a.port}/")
	print(f"Раздаю {bdir} на http://127.0.0.1:{a.port}/ — игра: PW_UPDATE_URL=http://127.0.0.1:{a.port}/latest.json")
	handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(bdir))
	http.server.ThreadingHTTPServer(("127.0.0.1", a.port), handler).serve_forever()


def main() -> None:
	sys.stdout.reconfigure(encoding="utf-8", errors="replace")
	ap = argparse.ArgumentParser(description="Релизы с автообновлением")
	sub = ap.add_subparsers(dest="cmd", required=True)
	for name, fn in (("base", cmd_base), ("patch", cmd_patch), ("full", cmd_full)):
		p = sub.add_parser(name)
		p.add_argument("version")
		p.add_argument("--title", default="")
		p.add_argument("--no-bump", action="store_true")
		p.add_argument("--local", default="")
		p.add_argument("--allow-project", action="store_true")
		p.add_argument("--patch-from", default="")
		if name == "patch":
			p.add_argument("--with-social", action="store_true",
						   help="добавить новую сборку BGSocial.exe рядом с патчем")
		p.set_defaults(fn=fn)
	p = sub.add_parser("finalize")
	p.add_argument("--local", default="")
	p.set_defaults(fn=cmd_finalize)
	p = sub.add_parser("publish")
	p.add_argument("version")
	p.set_defaults(fn=cmd_publish)
	sub.add_parser("status").set_defaults(fn=cmd_status)
	p = sub.add_parser("serve")
	p.add_argument("--port", type=int, default=8765)
	p.set_defaults(fn=cmd_serve)
	a = ap.parse_args()
	a.fn(a)


if __name__ == "__main__":
	main()
