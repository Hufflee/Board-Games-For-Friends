"""Проверки пакета 02.11: отдельный профиль, Dummy, полный лог и ограничение времени."""
import os
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = r'C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe'
OUT = ROOT / 'build/batch_20261102'
OUT.mkdir(parents=True, exist_ok=True)
run_id = uuid.uuid4().hex[:8]
failed = False
for index, resource in enumerate(sys.argv[1:]):
    name = Path(resource).stem
    profile = OUT / ('profile_' + uuid.uuid4().hex)
    profile.mkdir()
    env = dict(os.environ, APPDATA=str(profile))
    args = [GODOT, '--audio-driver', 'Dummy', '--path', str(ROOT)]
    if not resource.endswith('.tscn'):
        if os.environ.get('BATCH_WINDOW') != '1':
            args += ['--headless']
        args += ['--script']
    args += ['res://' + resource]
    log = OUT / (name + '_' + run_id + '_' + str(index) + '.log')
    try:
        result = subprocess.run(args, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=int(os.environ.get('BATCH_TIMEOUT', '180')))
        output = result.stdout.decode('utf-8', errors='replace')
        bad = result.returncode != 0 or 'SCRIPT ERROR' in output or '\nERROR:' in output
        print(name, result.returncode, 'ОШИБКИ' if bad else 'чистый лог', log.name, flush=True)
        print('\n'.join(output.splitlines()[-4:]), flush=True)
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or b'').decode('utf-8', errors='replace')
        bad = True
        print(name, 'ПРЕВЫШЕНО ВРЕМЯ', flush=True)
    log.write_text(output, encoding='utf-8')
    failed |= bad
sys.exit(1 if failed else 0)
