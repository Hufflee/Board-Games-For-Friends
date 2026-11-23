"""Регрессия клиентских черновиков в двух настоящих ENet-процессах."""
import os
from pathlib import Path
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
GODOT = Path("C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe")
OUTPUT = ROOT / "build" / f"batch22_enet_{time.time_ns()}"
OUTPUT.mkdir(parents=True)
failed = False

for game in ["green_team_wins", "first_contact"]:
    folder = OUTPUT / game
    folder.mkdir()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as available:
        available.bind(("127.0.0.1", 0))
        port = available.getsockname()[1]
    children = []
    try:
        for role in ["host", "client"]:
            profile = folder / f"profile_{role}"
            profile.mkdir()
            environment = dict(os.environ, APPDATA=str(profile), B22_ROLE=role,
                               B22_GAME=game, B22_FOLDER=str(folder), B22_PORT=str(port))
            stream = (folder / f"{role}.log").open("w", encoding="utf-8")
            command = [str(GODOT), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                       "--script", "res://tests/test_batch22_enet.gd"]
            process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=stream,
                                       stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            children.append((role, process, stream))
        for role, process, stream in children:
            code = process.wait(timeout=70)
            stream.flush()
            content = (folder / f"{role}.log").read_text(encoding="utf-8", errors="replace")
            for line in content.splitlines():
                if "B22_ENET" in line or "ERROR" in line:
                    print(line)
            failed |= code != 0 or "SCRIPT ERROR" in content or "B22_ENET" not in content
    finally:
        for _, process, stream in children:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            stream.close()

print("Журналы:", OUTPUT)
raise SystemExit(1 if failed else 0)
