"""Два настоящих процесса ENet: --script путь к SceneTree-проверке Unmatched."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--script', default='res://tests/test_unmatched_bard_enet.gd')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
folder = root / 'build' / f'um095_enet_{time.time_ns()}'
folder.mkdir()
godot = 'C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe'
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
children = []
failed = False
try:
    for role in ['host', 'client']:
        profile = folder / role
        profile.mkdir()
        env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile / 'local'),
                   UM_ROLE=role, UM_PORT=str(port))
        stream = (folder / f'{role}.log').open('w', encoding='utf-8')
        process = subprocess.Popen([godot, '--headless', '--audio-driver', 'Dummy', '--path',
                                    str(root), '--script', args.script], cwd=root, env=env,
                                   stdout=stream, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        children.append((role, process, stream))
    for role, process, stream in children:
        code = process.wait(timeout=55)
        stream.flush()
        content = (folder / f'{role}.log').read_text(encoding='utf-8', errors='replace')
        for line in content.splitlines():
            if 'проверок,' in line or 'ERROR' in line:
                print(role, line)
        failed |= code != 0 or 'ERROR' in content or 'проверок,' not in content
finally:
    for role, process, stream in children:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        stream.close()
print('Журналы:', folder)
raise SystemExit(int(failed))
