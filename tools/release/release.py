"""Сборка релизов с автообновлением: полная «база» и инкрементальные PCK-патчи.

Запуск из корня проекта (Godot — из CLAUDE.md, другой путь — env GODOT):
    python tools/release/release.py base 0.8.9            # полная версия: exe + base.pck + zip + latest.json
    python tools/release/release.py patch 0.8.10          # патч: только изменённое с прошлой версии
    python tools/release/release.py status                # текущая база и цепочка патчей
    python tools/release/release.py publish 0.8.10        # выложить собранное на GitHub (gh release create)
    python tools/release/release.py serve                 # раздать текущую базу локально (проверка апдейтера)

Ключи base/patch: --title "0.8.10 — ..." (заголовок релиза), --no-bump (не трогать версию в
project.godot / export_presets.cfg), --local http://127.0.0.1:8765/ (ссылки в latest.json — на
локальный сервер, для проверки). publish — только с согласия владельца.

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
BASE_FILES = ["PartyWorld.exe", "libgodotsteam.windows.template_release.x86_64.dll", "steam_api64.dll", "steam_appid.txt"]
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


def write_manifest(bdir: Path, local: str) -> dict:
	info = read_json(bdir / "base.json", {})
	chain = read_json(bdir / "chain.json", [])
	base = dict(info)
	base["url"] = url_for(info["version"], info["file"], local)
	patches = [dict(p, url=url_for(p["version"], p["file"], local)) for p in chain]
	latest = chain[-1]["version"] if chain else info["version"]
	m = {
		"format": 1,
		"version": latest,
		"page": f"https://github.com/{REPO}/releases/tag/v{latest}",
		"base": base,
		"patches": patches,
	}
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


def cmd_base(a) -> None:
	v = a.version
	if not a.no_bump:
		set_version(v)
	if project_version() != v:
		die(f"в project.godot версия {project_version()}, а собираем {v}")
	bdir = OUT / v
	bdir.mkdir(parents=True, exist_ok=True)
	EXE_DIR.mkdir(parents=True, exist_ok=True)
	godot("--export-release", PRESET, str(EXE_DIR / "PartyWorld.exe"))
	godot("--export-pack", PRESET, str(bdir / "base.pck"))
	zname = f"PartyWorld-{v}-Windows.zip"
	with zipfile.ZipFile(bdir / zname, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
		for f in BASE_FILES:
			src = EXE_DIR / f
			if not src.exists():
				die(f"нет {src}")
			z.write(src, f)
	zp = bdir / zname
	write_json(bdir / "base.json", {"version": v, "file": zname, "size": zp.stat().st_size, "sha256": sha256(zp)})
	write_json(bdir / "chain.json", [])
	write_json(bdir / "fingerprint.json", fingerprint())
	(bdir / f"notes-{v}.md").write_text(notes_for(v), encoding="utf-8")
	(OUT / "current.txt").write_text(v, encoding="utf-8")
	write_manifest(bdir, a.local)
	if a.title:
		write_json(bdir / f"title-{v}.json", a.title)
	print(f"База {v} готова: {zp} ({zp.stat().st_size / 1048576:.1f} МБ). Выложить: release.py publish {v}")


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
	chain.append({"version": v, "file": fname, "size": fp.stat().st_size, "sha256": sha256(fp)})
	write_json(bdir / "chain.json", chain)
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
	asset = info["file"] if v == info["version"] else next(p["file"] for p in chain if p["version"] == v)
	title = read_json(bdir / f"title-{v}.json", f"{v}")
	cmd = ["gh", "release", "create", f"v{v}", str(bdir / asset), str(bdir / "latest.json"), "--repo", REPO,
		"--title", title, "--notes-file", str(bdir / f"notes-{v}.md"), "--latest"]
	print(">", " ".join(cmd))
	if subprocess.run(cmd).returncode != 0:
		die("gh release create не прошёл")
	print(f"Опубликовано: https://github.com/{REPO}/releases/tag/v{v}")


def cmd_status(_a) -> None:
	bdir = base_dir()
	info = read_json(bdir / "base.json", {})
	print(f"База {info.get('version')}: {info.get('file')} ({info.get('size', 0) / 1048576:.1f} МБ)")
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
	for name, fn in (("base", cmd_base), ("patch", cmd_patch)):
		p = sub.add_parser(name)
		p.add_argument("version")
		p.add_argument("--title", default="")
		p.add_argument("--no-bump", action="store_true")
		p.add_argument("--local", default="")
		p.set_defaults(fn=fn)
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
