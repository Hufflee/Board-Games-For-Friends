"""Докачка в двух действительно разных процессах, профиль общий и только внутри build."""
import os
import subprocess
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/batch_20261102"
OUT.mkdir(parents=True, exist_ok=True)
run_id = uuid.uuid4().hex[:8]
profile = OUT / ("profile_partial_" + run_id)
profile.mkdir()
env = dict(os.environ, APPDATA=str(profile))
godot = r"C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe"
failed = False
for mode in ("produce-partial", "consume-partial"):
    result = subprocess.run(
        [godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
         "--script", "res://tests/test_custom_partial.gd", "--", "--" + mode],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    output = result.stdout.decode("utf-8", errors="replace")
    log = OUT / ("custom_partial_" + run_id + "_" + mode + ".log")
    log.write_text(output, encoding="utf-8")
    bad = result.returncode != 0 or "SCRIPT ERROR" in output or "\nERROR:" in output
    print(mode, "ОШИБКИ" if bad else "чистый лог", log.name, flush=True)
    print("\n".join(output.splitlines()[-3:]), flush=True)
    failed |= bad
    if bad:
        break
raise SystemExit(1 if failed else 0)
