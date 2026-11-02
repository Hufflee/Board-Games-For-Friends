"""ENet по localhost с реальной потерей UDP-пакетов между 2-й и 12-й секундами."""
import os
import select
import socket
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/batch_20261102'
GODOT = r'C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe'
marker = OUT / ('jitter_' + uuid.uuid4().hex + '.txt')
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('127.0.0.1', 23902))
host_addr = ('127.0.0.1', 23901)
client_addr = None
processes = []
started = None
dropped = 0
try:
    for role in ('host', 'client'):
        profile = OUT / ('jitter_profile_' + uuid.uuid4().hex)
        profile.mkdir(parents=True)
        log = (OUT / ('jitter_' + role + '.log')).open('w', encoding='utf-8')
        env = dict(os.environ, APPDATA=str(profile), JITTER_ROLE=role, JITTER_MARKER=str(marker))
        proc = subprocess.Popen([GODOT, '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT),
                                 'res://tools/_shot/transport_jitter.tscn'],
                                cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        processes.append((role, proc, log))
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline and any(proc.poll() is None for _, proc, _ in processes):
        if started is None and marker.exists():
            started = time.monotonic()
        if not select.select([sock], [], [], 0.05)[0]:
            continue
        data, address = sock.recvfrom(65535)
        destination = client_addr if address == host_addr else host_addr
        if address != host_addr:
            client_addr = address
        if started is not None and 2 <= time.monotonic() - started < 12:
            dropped += 1
            continue
        if destination:
            sock.sendto(data, destination)
finally:
    sock.close()
    for _, proc, log in processes:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        log.close()
failed = dropped == 0
for role, proc, _ in processes:
    text = (OUT / ('jitter_' + role + '.log')).read_text(encoding='utf-8')
    ok = proc.returncode == 0 and f'JITTER {role} OK' in text and 'SCRIPT ERROR' not in text and '\nERROR:' not in text
    print(role, 'OK' if ok else 'FAIL')
    failed |= not ok
print('Потеряно пакетов в десятисекундном провале:', dropped)
raise SystemExit(1 if failed else 0)
