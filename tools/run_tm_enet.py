"""Запускает локальную ENet-проверку The Mind двумя изолированными процессами без звука."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path(r"C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe")
OUT = ROOT / "build/mind_tests"
OUT.mkdir(parents=True, exist_ok=True)
marker = OUT / "enet_client_attempt.txt"
marker.unlink(missing_ok=True)
tasks = []
for role in ("host", "client"):
    profile = OUT / ("enet_" + role)
    profile.mkdir(exist_ok=True)
    env = {**os.environ, "APPDATA": str(profile), "TM_ROLE": role}
    log = (OUT / ("enet_" + role + ".log")).open("w", encoding="utf-8")
    process = subprocess.Popen(
        [str(GODOT), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
         "--script", "res://tests/test_the_mind_net.gd"],
        cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    tasks.append((role, process, log))
failed = False
for role, process, log in tasks:
    try:
        code = process.wait(timeout=45)
    except subprocess.TimeoutExpired:
        process.kill()
        code = 1
    log.close()
    text = (OUT / ("enet_" + role + ".log")).read_text(encoding="utf-8")
    print("\n".join(line for line in text.splitlines() if "TM_ENET" in line or "ERROR" in line))
    failed |= code != 0 or "SCRIPT ERROR" in text or "TM_ENET" not in text
raise SystemExit(1 if failed else 0)
