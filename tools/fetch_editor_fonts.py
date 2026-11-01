"""Скачать оговорённый OFL-набор только из закреплённого коммита google/fonts; бинарники не менять."""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from pathlib import Path
import json
import re
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'editor' / 'fonts' / 'extra'
FAMILIES = ('lobster', 'comfortaa', 'yesevaone', 'unbounded', 'amaticsc', 'badscript',
            'marckscript', 'neucha', 'seymourone', 'rubikglitch', 'rubikbeastly', 'pacifico', 'rubikwetpaint')


def fetch(url):
    with urlopen(Request(url, headers={'User-Agent': 'BoardGamesEditor/1.0'}), timeout=25) as response:
        result = response.read(12 * 1024 * 1024 + 1)
    if len(result) > 12 * 1024 * 1024:
        raise ValueError('Файл больше лимита 12 МБ')
    return result


def main():
    commit = json.loads(fetch('https://api.github.com/repos/google/fonts/commits/main'))['sha']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Неизвестный commit')

    def family(slug):
        # Повторный запуск не загружает уже проверенный файл того же коммита.
        cached = OUT / slug / 'SOURCE.json'
        if cached.is_file():
            source = json.loads(cached.read_text(encoding='utf-8'))
            font = cached.parent / 'font.ttf'
            if source.get('commit') == commit and font.is_file() and sha256(font.read_bytes()).hexdigest() == source.get('sha256'):
                return {'id': slug, **source}
        base = f'https://raw.githubusercontent.com/google/fonts/{commit}/ofl/{slug}/'
        metadata_bytes = fetch(base + 'METADATA.pb')
        metadata = metadata_bytes.decode('utf-8')
        if 'license: "OFL"' not in metadata or 'subsets: "cyrillic"' not in metadata:
            raise ValueError(f'{slug}: нет OFL/кириллицы в метаданных')
        filenames = re.findall(r'filename: "([^"]+\.ttf)"', metadata)
        filename = next((name for name in filenames if name.endswith('-Regular.ttf')), filenames[0])
        if not re.fullmatch(r'[A-Za-z0-9_\[\],.\-]+\.ttf', filename):
            raise ValueError('Небезопасное имя шрифта')
        license_bytes = fetch(base + 'OFL.txt')
        if b'SIL OPEN FONT LICENSE' not in license_bytes.upper():
            raise ValueError('Неизвестный текст лицензии')
        font_bytes = fetch(base + quote(filename))
        if font_bytes[:4] not in (b'\x00\x01\x00\x00', b'OTTO'):
            raise ValueError('Неизвестный заголовок шрифта')
        destination = OUT / slug
        destination.mkdir(parents=True, exist_ok=True)
        (destination / 'font.ttf').write_bytes(font_bytes)
        (destination / 'OFL.txt').write_bytes(license_bytes)
        (destination / 'METADATA.pb').write_bytes(metadata_bytes)
        source = {'family': re.search(r'^name: "([^"]+)"', metadata).group(1), 'commit': commit,
                  'url': base + quote(filename), 'original_filename': filename, 'sha256': sha256(font_bytes).hexdigest(),
                  'note': 'Бинарный файл не изменён; кириллица дополнительно проверяется в Godot.'}
        (destination / 'SOURCE.json').write_text(json.dumps(source, ensure_ascii=False, indent=2), encoding='utf-8')
        return {'id': slug, **source}

    with ThreadPoolExecutor(max_workers=4) as pool:
        families = list(pool.map(family, FAMILIES))
    (OUT / 'manifest.json').write_text(json.dumps(families, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'EDITOR_FONTS: {len(families)} семейств, commit {commit}')


if __name__ == '__main__':
    main()
