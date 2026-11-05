"""Два изолированных процесса для tests/test_machi_koro_enet.gd; запуск из корня проекта."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
out = root / 'build/machi_koro_research/enet'
out.mkdir(parents=True, exist_ok=True)
for name in ['forged', 'received', 'foreign_stable']:
    marker = out / (name + '.txt')
    if marker.exists():
        marker.unlink()
godot = Path('C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe')
children = []
for role in ['host', 'client']:
    profile = out / ('profile_' + role)
    profile.mkdir(exist_ok=True)
    environment = dict(os.environ, APPDATA=str(profile), MK_ROLE=role)
    stream = (out / (role + '.log')).open('w', encoding='utf-8')
    command = [str(godot), '--headless', '--audio-driver', 'Dummy', '--path', str(root), '--log-file', str(out / (role + '_engine.log')), '--script', 'res://tests/test_machi_koro_enet.gd']
    process = subprocess.Popen(command, cwd=root, env=environment, stdout=stream, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    children.append((role, process, stream))
failed = False
try:
    for role, process, stream in children:
        result = process.wait(timeout=55)
        stream.flush()
        print(role, result)
        failed = failed or result != 0
finally:
    for role, process, stream in children:
        if process.poll() is None:
            process.terminate()
        stream.close()
for role, _, _ in children:
    content = (out / (role + '.log')).read_text(encoding='utf-8', errors='replace')
    for line in content.splitlines():
        if 'MK_ENET' in line or 'ОШИБКА:' in line or 'SCRIPT ERROR' in line:
            print(line)
    failed = failed or 'SCRIPT ERROR' in content or 'MK_ENET' not in content
raise SystemExit(1 if failed else 0)
