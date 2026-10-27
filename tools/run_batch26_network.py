"""Четыре процесса Godot, изолированные профили, ограниченное время выполнения."""
import os
from pathlib import Path
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = r"C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe"
OUT = ROOT / "build/batch26_network"
OUT.mkdir(parents=True, exist_ok=True)
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
processes = []
try:
    for role in ["host", "a", "b", "c"]:
        profile = OUT / role
        profile.mkdir(exist_ok=True)
        env = dict(os.environ, APPDATA=str(profile), BATCH_ROLE=role, BATCH_PORT=str(port))
        log = (OUT / f"{role}.log").open("w", encoding="utf-8")
        process = subprocess.Popen([GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                                    "res://tests/test_batch26_network.tscn"], env=env, stdout=log, stderr=log)
        processes.append((role, process, log))
        time.sleep(0.6)
    for role, process, log in processes:
        print(role, process.wait(timeout=55))
finally:
    for role, process, log in processes:
        if process.poll() is None:
            process.kill()
            process.wait()
        log.close()
for role, _, _ in processes:
    for line in (OUT / f"{role}.log").read_text(encoding="utf-8", errors="replace").splitlines():
        if "NETWORK" in line or "ERROR" in line:
            print(role, line)
