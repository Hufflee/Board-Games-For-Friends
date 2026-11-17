"""Лабораторная проверка выбора пакета обновления: патчи или полная сборка со сжатыми картами.

    python tools/release/test_update_select.py

Манифесты собирает сам release.py (write_manifest / cmd_finalize) в build/update_select/releases:
- transition.json — переходный (публикуется с 0.9.1.2): база 0.8.12 и цепочка как раньше + патч
  0.9.1.2, "full" — полная сборка 0.9.1.2, "patch_from": "0.9.1";
- final.json — после `finalize` и следующего патча 0.9.1.3: база — полная 0.9.1.2, старая линия
  0.8.12 — в "lines" (патч 0.9.1.3 для неё — отдельный файл).
Версии и имена файлов — из настоящей цепочки build/releases/0.8.12/chain.json, файлы — поддельные.
Клиенты: новый (hub/update/update_client.gd) и старые из git — exe 0.8.12 (ab48f7c2) и патчи
0.9.0.2–0.9.1.1 (b976a1d9). Godot — headless, звук выключен, свой APPDATA. Код выхода 1 при ошибке.
Отчёт: build/update_select/report.md (что клиент собирается скачать, с настоящими размерами).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "release"))
import release  # noqa: E402

WORK = ROOT / "build" / "update_select"
APPDATA = ROOT / "build" / "appdata_update_select"
REAL = ROOT / "build" / "releases" / "0.8.12"
LOCAL = "http://127.0.0.1:8767/"
OLD_EXE_COMMIT = "ab48f7c2"  # Release 0.8.12 — клиент внутри exe 0.8.12
OLD_PATCH_COMMIT = "b976a1d9"  # Release 0.9.1.1 — клиент из патчей 0.9.0.2–0.9.1.1
FULL = "PartyWorld-0.9.1.2-Windows.zip"


def fake(path: Path, text: str) -> dict:
	path.write_bytes((text + "\n").encode() * 64)
	return {"file": path.name, "size": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def build_manifests() -> tuple[list[str], dict]:
	release.OUT = WORK / "releases"
	old = release.OUT / "0.8.12"
	new = release.OUT / "0.9.1.2"
	old.mkdir(parents=True)
	new.mkdir(parents=True)
	# Настоящая цепочка до 0.9.1.1 (опубликованное) + патч 0.9.1.2.
	versions = [p["version"] for p in json.loads((REAL / "chain.json").read_text(encoding="utf-8")) if release.version_key(p["version"]) < (0, 9, 1, 2)] + ["0.9.1.2"]
	release.write_json(old / "base.json", dict(fake(old / "PartyWorld-0.8.12-Windows.zip", "base 0.8.12"), version="0.8.12"))
	fakes, chain = {}, []
	for v in versions:
		info = fake(old / f"patch-{v}.pck", "patch " + v)
		chain.append(dict(info, version=v))
		fakes[v] = dict(info, file=f"releases/0.8.12/{info['file']}")
	release.write_json(old / "chain.json", chain)
	# release.py full 0.9.1.2 --patch-from 0.9.1 (без экспорта): полная сборка рядом с патчем.
	release.write_json(new / "base.json", dict(fake(new / FULL, "full 0.9.1.2"), version="0.9.1.2"))
	release.write_json(new / "chain.json", [])
	release.write_json(new / "social.json", dict(fake(new / "BGSocial.exe", "social 0.9.1.2"), version="0.9.1.2"))
	release.write_json(old / "full.json", {"dir": "0.9.1.2", "patch_from": "0.9.1"})
	release.write_manifest(old, LOCAL)
	shutil.copy(old / "latest.json", WORK / "transition.json")
	# release.py finalize, затем patch 0.9.1.3 (для новой линии и для старой — своим файлом).
	(release.OUT / "current.txt").write_text("0.8.12", encoding="utf-8")
	release.cmd_finalize(argparse.Namespace(local=LOCAL))
	release.write_json(new / "chain.json", [dict(fake(new / "patch-0.9.1.3.pck", "patch 0.9.1.3 new"), version="0.9.1.3")])
	release.write_json(old / "chain.json", chain + [dict(fake(old / "patch-0.9.1.3-from-0.8.12.pck", "patch 0.9.1.3 old"), version="0.9.1.3")])
	release.write_manifest(new, LOCAL)
	shutil.copy(new / "latest.json", WORK / "final.json")
	(WORK / "fakes.json").write_text(json.dumps(fakes, indent="\t"), encoding="utf-8")
	return versions, fakes


def scenarios(versions: list[str]) -> list[dict]:
	def upto(v: str) -> list[str]:
		return versions[: versions.index(v) + 1]

	def P(*vs: str) -> str:
		return "patch:" + ",".join(f"patch-{v}.pck" for v in vs)

	FB = "base:" + FULL
	NONE = "нет:"
	L3 = "patch-0.9.1.3-from-0.8.12.pck"
	O812, O902, N = "старый 0.8.12", "старый 0.9.0.2+", "новый"
	return [
		{"name": "0.8.12 без патчей", "exe": "0.8.12", "chain": [],
			"expect": {O812: {"transition": P(*versions), "final": FB}, N: {"transition": FB, "final": FB}}},
		{"name": "0.9.0.8 поверх exe 0.8.12", "exe": "0.8.12", "chain": upto("0.9.0.8"),
			"expect": {O902: {"transition": P("0.9.1", "0.9.1.1", "0.9.1.2"), "final": FB}, N: {"transition": FB, "final": FB}}},
		{"name": "полная 0.9.0.8", "exe": "0.9.0.8", "chain": [],
			"expect": {O902: {"transition": P("0.9.1", "0.9.1.1", "0.9.1.2"), "final": FB}, N: {"transition": FB, "final": FB}}},
		{"name": "полная 0.9.1", "exe": "0.9.1", "chain": [],
			"expect": {O902: {"transition": P("0.9.1.1", "0.9.1.2"), "final": FB},
				N: {"transition": P("0.9.1.1", "0.9.1.2"), "final": P("0.9.1.1", "0.9.1.2") + "," + L3}}},
		{"name": "полная 0.9.1.1", "exe": "0.9.1.1", "chain": [],
			"expect": {O902: {"transition": P("0.9.1.2"), "final": FB}, N: {"transition": P("0.9.1.2"), "final": P("0.9.1.2") + "," + L3}}},
		{"name": "0.9.1 поверх exe 0.8.12", "exe": "0.8.12", "chain": upto("0.9.1"),
			"expect": {O902: {"transition": P("0.9.1.1", "0.9.1.2"), "final": FB},
				N: {"transition": P("0.9.1.1", "0.9.1.2"), "final": P("0.9.1.1", "0.9.1.2") + "," + L3}}},
		{"name": "0.9.1.1 поверх exe 0.8.12", "exe": "0.8.12", "chain": upto("0.9.1.1"),
			"expect": {O902: {"transition": P("0.9.1.2"), "final": FB}, N: {"transition": P("0.9.1.2"), "final": P("0.9.1.2") + "," + L3}}},
		{"name": "после перехода: 0.9.1.2 поверх exe 0.8.12", "exe": "0.8.12", "chain": upto("0.9.1.2"),
			"expect": {N: {"transition": NONE, "final": "patch:" + L3}}},
		{"name": "после перехода: полная 0.9.1 + патчи", "exe": "0.9.1", "chain": ["0.9.1.1", "0.9.1.2"],
			"expect": {N: {"transition": NONE, "final": "patch:" + L3}}},
		{"name": "полная 0.9.1.2 (новая)", "exe": "0.9.1.2", "chain": [],
			"expect": {N: {"transition": NONE, "final": P("0.9.1.3")}}},
		{"name": "0.9.1.1 поверх exe 0.8.12, нет BGSocial.exe", "exe": "0.8.12", "chain": upto("0.9.1.1"), "social": False,
			"expect": {O902: {"transition": P("0.9.1.2")}, N: {"transition": P("0.9.1.2") + ",BGSocial.exe", "final": P("0.9.1.2") + "," + L3 + ",BGSocial.exe"}}},
		{"name": "0.9.0.8 поверх exe 0.8.12, нет BGSocial.exe", "exe": "0.8.12", "chain": upto("0.9.0.8"), "social": False,
			"expect": {N: {"transition": FB}}},
		{"name": "после перехода, нет BGSocial.exe", "exe": "0.8.12", "chain": upto("0.9.1.2"), "social": False,
			"expect": {N: {"transition": "social:BGSocial.exe", "final": "patch:" + L3 + ",BGSocial.exe"}}},
		{"name": "нет звена 0.9.1.1: Updater обрезал цепочку", "exe": "0.8.12", "chain": upto("0.9.1"),
			"expect": {O902: {"transition": P("0.9.1.1", "0.9.1.2")}, N: {"transition": P("0.9.1.1", "0.9.1.2")}}},
		{"name": "нет файла 0.9.1.1 (удалён после запуска)", "exe": "0.8.12", "chain": upto("0.9.1.1"), "missing": ["0.9.1.1"],
			"expect": {O902: {"transition": P("0.9.1.2")}, N: {"transition": P("0.9.1.1", "0.9.1.2")}}},
		{"name": "нет звена 0.9.1: Updater обрезал цепочку", "exe": "0.8.12", "chain": upto("0.9.0.8"),
			"expect": {O902: {"transition": P("0.9.1", "0.9.1.1", "0.9.1.2")}, N: {"transition": FB}}},
		{"name": "нет файла 0.9.1 (удалён после запуска)", "exe": "0.8.12", "chain": upto("0.9.1.1"), "missing": ["0.9.1"],
			"expect": {N: {"transition": FB}}},
		{"name": "повреждено звено 0.9.1.1 (тот же размер)", "exe": "0.8.12", "chain": upto("0.9.1.1"), "corrupt": ["0.9.1.1"],
			"expect": {O902: {"transition": P("0.9.1.2")}, N: {"transition": P("0.9.1.1", "0.9.1.2")}}},
		{"name": "повреждено звено 0.9.1 (тот же размер)", "exe": "0.8.12", "chain": upto("0.9.1.1"), "corrupt": ["0.9.1"],
			"expect": {O902: {"transition": P("0.9.1.2")}, N: {"transition": FB}}},
		{"name": "подключено меньше, чем в state.json", "exe": "0.8.12", "chain": upto("0.9.1.1"), "loaded": upto("0.9.0.8"),
			"expect": {N: {"transition": FB}}},
	]


def real_sizes() -> dict:
	sizes = {p["file"]: p["size"] for p in json.loads((REAL / "chain.json").read_text(encoding="utf-8"))}
	for d in (ROOT / "build" / "releases").glob("*/"):
		for name in ("chain.json", "base.json"):
			data = release.read_json(d / name, [])
			for p in data if isinstance(data, list) else [data]:
				if p.get("file"):
					sizes[p["file"]] = p["size"]
	return sizes


def mb(n: int | None) -> str:
	return "?" if n is None else (f"{n / 1048576:.1f} МБ" if n >= 1048576 else f"{n / 1024:.0f} КБ")


def main() -> None:
	sys.stdout.reconfigure(encoding="utf-8", errors="replace")
	for target in (WORK, APPDATA):
		assert target.resolve().is_relative_to((ROOT / "build").resolve()), target
		shutil.rmtree(target, ignore_errors=True)
		target.mkdir(parents=True)
	versions, _ = build_manifests()
	for name, rev in (("0.8.12", OLD_EXE_COMMIT), ("0.9.0.2", OLD_PATCH_COMMIT)):
		src = subprocess.run(["git", "show", f"{rev}:hub/update/update_client.gd"], cwd=ROOT, capture_output=True, check=True).stdout
		(WORK / f"client_{name}.gd").write_bytes(src)
	sc = scenarios(versions)
	for s in sc:
		s["clients"] = list(s["expect"])
	(WORK / "scenarios.json").write_text(json.dumps(sc, ensure_ascii=False, indent="\t"), encoding="utf-8")
	env = dict(os.environ, UPD_DIR=str(WORK), APPDATA=str(APPDATA), PW_UPDATE_INSTALL_DIR=str(WORK))
	cmd = [release.GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", "res://tests/test_update_select.gd"]
	r = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
	sizes = real_sizes()
	rows = ["| Сценарий | Клиент | Манифест | Выбор | Файлы (настоящий размер) |", "|---|---|---|---|---|"]
	for line in r.stdout.splitlines():
		if line.startswith("ВЫБОР|"):
			_, name, client, man, kind, files = line.split("|")
			fl = [f for f in files.split(",") if f]
			total = sum(sizes.get(f, 0) for f in fl)
			desc = ", ".join(f"{f} ({mb(sizes.get(f))})" for f in fl) or "—"
			rows.append(f"| {name} | {client} | {man} | {kind} | {desc}{' = ' + mb(total) if len(fl) > 1 else ''} |")
		elif line.startswith(("ПРОВАЛ", "ИТОГ")) or "SCRIPT ERROR" in line or "Parse Error" in line:
			print(line)
	report = "\n".join(rows)
	(WORK / "report.md").write_text(report + "\n", encoding="utf-8")
	print(report)
	ok = r.returncode == 0 and "ИТОГ выбор пакета: OK" in r.stdout
	if not ok:
		print(r.stdout[-3000:], r.stderr[-2000:])
	print("ВСЁ OK" if ok else "ЕСТЬ ОШИБКИ")
	sys.exit(0 if ok else 1)


if __name__ == "__main__":
	main()
