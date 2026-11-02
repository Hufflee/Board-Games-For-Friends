"""Локальная проверка автообновления: поддельные манифесты + HTTP-сервер + этапы tests/test_updater.gd.

    python tools/release/test_updater.py

Каждый этап — отдельный запуск Godot (патчи подключаются только при старте). Свой APPDATA
в build/appdata_update (стирается в начале), звук выключен. Код выхода 1 при ошибке.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT", r"C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe")
WORK = ROOT / "build" / "update_test"
APPDATA = ROOT / "build" / "appdata_update"
PORT = 8766


def sha(p: Path) -> str:
	return hashlib.sha256(p.read_bytes()).hexdigest()


def entry(version: str, file: str, sum_: str | None = None) -> dict:
	p = WORK / file
	return {"version": version, "url": f"http://127.0.0.1:{PORT}/{file}", "size": p.stat().st_size, "sha256": sum_ or sha(p)}


def manifest(name: str, base: dict, patches: list, version: str) -> None:
	m = {"format": 1, "version": version, "page": "https://example.invalid/", "base": base, "patches": patches}
	(WORK / name).write_text(json.dumps(m, ensure_ascii=False, indent="\t"), encoding="utf-8")


def run(stage: str, url: str = "", extra: dict | None = None) -> bool:
	env = dict(os.environ, PW_UPDATER="1", UPD_STAGE=stage, UPD_DIR=str(WORK), APPDATA=str(APPDATA))
	base_ver = next(l.split('"')[1] for l in (ROOT / "project.godot").read_text(encoding="utf-8").splitlines() if l.startswith("config/version="))
	major, minor, patch = map(int, base_ver.split('.'))
	env.update(UPD_TEST_BASE=base_ver, UPD_TEST_PATCH1=f"{major}.{minor}.{patch+1}", UPD_TEST_PATCH2=f"{major}.{minor}.{patch+2}")
	if url:
		env["PW_UPDATE_URL"] = f"http://127.0.0.1:{PORT}/{url}"
	env.update(extra or {})
	cmd = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", "res://tests/test_updater.gd"]
	r = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
	lines = [l for l in r.stdout.splitlines() if l.startswith(("== ", "ПРОВАЛ", "ИТОГ", "[update]")) or "ERROR" in l]
	print("\n".join(lines))
	return r.returncode == 0 and any(l.startswith("ИТОГ") and l.endswith("OK") for l in lines)


def main() -> None:
	for target in (WORK, APPDATA):
		assert target.resolve().is_relative_to((ROOT / "build").resolve()), target
	shutil.rmtree(WORK, ignore_errors=True)
	shutil.rmtree(APPDATA, ignore_errors=True)
	WORK.mkdir(parents=True, exist_ok=True)
	APPDATA.mkdir(parents=True, exist_ok=True)
	ok = run("prep")
	# База — та же, что у проекта (0.8.8 из project.godot), поэтому предлагаются патчи.
	base_ver = next(l.split('"')[1] for l in (ROOT / "project.godot").read_text(encoding="utf-8").splitlines() if l.startswith("config/version="))
	major, minor, patch = map(int, base_ver.split('.'))
	v1, v2 = f"{major}.{minor}.{patch+1}", f"{major}.{minor}.{patch+2}"
	(WORK / "fake-base.zip").write_bytes(b"not used")
	base = entry(base_ver, "fake-base.zip")
	manifest("latest.json", base, [entry(v1, f"patch-{v1}.pck"), entry(v2, f"patch-{v2}.pck")], v2)
	manifest("latest_bad.json", base, [entry(v2, f"patch-{v2}.pck", "0" * 64)], v2)
	# Новая база 0.9.0: zip с «exe» и «dll» в папке (проверка снятия общего префикса).
	with zipfile.ZipFile(WORK / "PartyWorld-0.9.0-Windows.zip", "w") as z:
		z.writestr("PartyWorld/PartyWorld.exe", "new exe")
		z.writestr("PartyWorld/steam_api64.dll", "new dll")
	manifest("latest_base.json", entry("0.9.0", "PartyWorld-0.9.0-Windows.zip"), [], "0.9.0")
	inst = WORK / "install"
	inst.mkdir()
	(inst / "PartyWorld.exe").write_text("old exe")
	(inst / "steam_api64.dll").write_text("old dll")

	# Сервер — отдельным процессом: встроенный в этот процесс зависал после первой загрузки.
	srv = subprocess.Popen([sys.executable, "-m", "http.server", str(PORT), "--bind", "127.0.0.1", "--directory", str(WORK)],
		stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
	time.sleep(1.0)
	try:
		ok = run("download", "latest.json") and ok
		ok = run("verify", "latest.json") and ok
		ok = run("arm_rollback") and ok
		ok = run("rollback") and ok
		ok = run("corrupt", "latest_bad.json") and ok
		ok = run("base", "latest_base.json", {"PW_UPDATE_INSTALL_DIR": str(inst)}) and ok
	finally:
		srv.kill()
	print("ВСЁ OK" if ok else "ЕСТЬ ОШИБКИ")
	sys.exit(0 if ok else 1)


if __name__ == "__main__":
	main()
