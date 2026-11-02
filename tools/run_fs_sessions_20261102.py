"""Four Souls: база/DLC, поздний зритель, разрыв/возврат игрока и потеря хоста по ENet."""
import json
import os
import socket
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = r'C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe'
checks = 0

def wait(predicate, seconds=20):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            if predicate():
                return
        except (OSError, ValueError, KeyError, IndexError):
            pass
        time.sleep(.04)
    raise AssertionError('Превышено время ожидания сетевого состояния')

def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)

for dlc in (False, True):
    run = 'sessions02-' + uuid.uuid4().hex
    folder = ROOT / 'build/fs_acceptance' / run
    folder.mkdir(parents=True)
    processes = []
    commands = {role: 0 for role in ('host', 'client', 'spectator')}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]

    def snapshot(role):
        return json.loads((folder / (role + '-snapshot.json')).read_text(encoding='utf-8'))

    def launch(role):
        profile = folder / (role + '_profile')
        profile.mkdir()
        env = dict(os.environ, APPDATA=str(profile), FS_ROLE=role, FS_RUN=run, FS_PORT=str(port))
        log = (folder / (role + '.log')).open('w', encoding='utf-8')
        process = subprocess.Popen([GODOT, '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT),
                                    '--script', 'res://tests/fs_enet_acceptance.gd'],
                                   env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        processes.append((role, process, log))

    def send(role, kind, arg=None):
        commands[role] += 1
        temp = folder / (role + '-command.tmp')
        temp.write_text(json.dumps({'id': commands[role], 'kind': kind, 'arg': arg}), encoding='utf-8')
        temp.replace(folder / (role + '-command.json'))
        wait(lambda: snapshot(role)['command'] == commands[role])

    try:
        launch('host')
        wait(lambda: snapshot('host')['members'] == 1)
        send('host', 'settings', {'fs_dlc': dlc})
        launch('client')
        wait(lambda: snapshot('host')['members'] == 2)
        send('host', 'start')
        send('host', 'pause', True)
        wait(lambda: snapshot('client')['in_game'] and bool(snapshot('client')['view']))
        host, client = snapshot('host'), snapshot('client')
        check(host['view']['dlc'] == dlc and client['view']['dlc'] == dlc, 'Обе стороны согласовали набор DLC')
        hand = client['view']['hand']
        seat = client['view']['seat']
        check(hand == host['audit_hands'][seat], 'Клиент получил свою настоящую руку')
        check(all('hand' not in player for i, player in enumerate(client['view']['players']) if i != seat), 'Чужие руки закрыты')
        launch('spectator')
        wait(lambda: snapshot('spectator')['in_game'] and bool(snapshot('spectator')['view']))
        spectator = snapshot('spectator')['view']
        check(spectator['spectator'] and spectator['seat'] == -1 and not spectator['hand'], 'Поздний зритель не занял место и не получил руку')
        check(all('hand' not in player for player in spectator['players']), 'У зрителя нет чужих скрытых рук')
        send('client', 'leave')
        wait(lambda: str(seat) in snapshot('host')['disconnected'])
        check(snapshot('host')['audit_players'][seat]['bot'] is False, 'Отключившегося человека не заменяет бот')
        send('client', 'join')
        wait(lambda: snapshot('client')['in_game'] and snapshot('client')['view'].get('seat') == seat and not snapshot('host')['disconnected'])
        check(snapshot('client')['view']['hand'] == hand, 'После возврата сохранены место и карты')
        send('host', 'quit')
        wait(lambda: not snapshot('client')['in_game'] and snapshot('client')['mode'] == '')
        wait(lambda: not snapshot('spectator')['in_game'] and snapshot('spectator')['mode'] == '')
        check(True, 'Потеря хоста завершила сессию и у игрока, и у зрителя')
        print('FS SESSIONS', 'DLC' if dlc else 'BASE', 'OK', folder, flush=True)
    finally:
        for role, process, log in processes:
            if process.poll() is None:
                try:
                    send(role, 'quit')
                    process.wait(timeout=4)
                except (AssertionError, subprocess.TimeoutExpired):
                    process.kill()
                    process.wait()
            log.close()
            text = (folder / (role + '.log')).read_text(encoding='utf-8')
            check('SCRIPT ERROR' not in text, 'Нет ошибок GDScript: ' + role)
print('FS SESSIONS:', checks, 'проверок, 0 ошибок')
