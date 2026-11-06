"""Процессы для tests/test_blood_on_the_clocktower_enet.gd: хост-рассказчик, 5 игроков, p5r (перезапуск
вылетевшего p5 с тем же профилем — p5 убивает себя сам, его код выхода не считается) и посторонний p6.
Запуск из корня проекта: python tools/run_bc_enet.py. Логи — build/claude_review/bc_enet/."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
out = root / 'build/claude_review/bc_enet'
out.mkdir(parents=True, exist_ok=True)
for marker in out.glob('*.txt'):
    marker.unlink()
godot = Path('C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe')
roles = ['host', 'p1', 'p2', 'p3', 'p4', 'p5', 'p5r', 'p6']
children = []
for role in roles:
    profile = out / ('profile_' + ('p5' if role == 'p5r' else role))
    profile.mkdir(exist_ok=True)
    environment = dict(os.environ, APPDATA=str(profile), BC_ROLE=role)
    stream = (out / (role + '.log')).open('w', encoding='utf-8')
    command = [str(godot), '--headless', '--audio-driver', 'Dummy', '--path', str(root),
               '--log-file', str(out / (role + '_engine.log')), '--script', 'res://tests/test_blood_on_the_clocktower_enet.gd']
    process = subprocess.Popen(command, cwd=root, env=environment, stdout=stream, stderr=subprocess.STDOUT,
                               creationflags=subprocess.CREATE_NO_WINDOW)
    children.append((role, process, stream))
failed = False
try:
    for role, process, stream in children:
        result = process.wait(timeout=330)
        stream.flush()
        print(role, result)
        failed = failed or (result != 0 and role != 'p5')
finally:
    for role, process, stream in children:
        if process.poll() is None:
            process.terminate()
        stream.close()
for role in roles:
    content = (out / (role + '.log')).read_text(encoding='utf-8', errors='replace')
    for line in content.splitlines():
        if 'BC_ENET' in line or 'ОШИБКА' in line or 'SCRIPT ERROR' in line or line.startswith('[p2]'):
            print(line)
    failed = failed or 'SCRIPT ERROR' in content or 'BC_ENET' not in content
raise SystemExit(1 if failed else 0)
