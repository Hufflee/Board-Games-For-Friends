"""Два изолированных тихих процесса Godot для ENet-исполнения JSON-игры и возврата игрока."""
from pathlib import Path
import os
import subprocess
import uuid
import sys

ROOT = Path(__file__).resolve().parents[1]
CUSTOM = '--custom' in sys.argv
OUT = ROOT / 'build/editor_stage2'
OUT.mkdir(parents=True, exist_ok=True)
GODOT = r'C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe'
for marker in ('attempt', 'offline_seen', 'resumed', 'resumed_client', 'done', 'package_ready_client', 'free_placed', 'free_seen',
               'turn_client_ready', 'turn_offline_seen', 'turn_phase_seen', 'turn_leader_attempt', 'turn_leader_seen'):
    (OUT / marker).unlink(missing_ok=True)
tasks = []
for role in ('host', 'client'):
    profile = OUT / ('enet_' + role + '_' + uuid.uuid4().hex)
    profile.mkdir()
    log = (OUT / ('enet_' + role + '.log')).open('w', encoding='utf-8')
    process = subprocess.Popen([GODOT, '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT), '--script', 'res://tests/test_custom_net.gd'],
                               cwd=ROOT, env={**os.environ, 'APPDATA': str(profile), 'CG_ROLE': role, 'CG_CUSTOM': '1' if CUSTOM else '0'}, stdout=log, stderr=subprocess.STDOUT,
                               creationflags=subprocess.CREATE_NO_WINDOW)
    tasks.append((role, process, log))
failed = False
for role, process, log in tasks:
    try:
        code = process.wait(timeout=65)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        code = 1
    log.close()
    text = (OUT / ('enet_' + role + '.log')).read_text(encoding='utf-8')
    print('\n'.join(line for line in text.splitlines() if 'CUSTOM_ENET' in line or 'ERROR' in line))
    failed |= code != 0 or 'ERROR' in text or 'CUSTOM_ENET' not in text or 'ошибок 0' not in text
raise SystemExit(int(failed))
