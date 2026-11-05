"""Источники Clocktower: только данные TTS, без исполнения Lua. Запуск: python tools/botc_sources.py."""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/botc_research'
SOURCE = Path('C:/Users/rabin/Documents/My Games/Tabletop Simulator/Mods/Workshop/1749093601.json')
NAMES = {
    'Trouble Brewing Almanac': 'trouble_brewing',
    'Bad Moon Rising Almanac': 'bad_moon_rising',
    'Sects & Violets Almanac': 'sects_and_violets',
    'Travelers & Fabled Almanac': 'travelers_fabled',
}


def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = json.loads(SOURCE.read_text(encoding='utf-8-sig'))
    manifest = []
    scripts = []
    for obj in walk(data):
        name = obj.get('Nickname', '')
        lua = obj.get('LuaScript', '')
        if lua:
            scripts.append({'name': name or 'Global', 'guid': obj.get('GUID', 'global'), 'source': lua})
        if name not in NAMES or 'CustomPDF' not in obj:
            continue
        url = obj['CustomPDF']['PDFUrl']
        path = OUT / (NAMES[name] + '.pdf')
        if not path.exists():
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=60) as response:
                content = response.read()
            if not content.startswith(b'%PDF'):
                raise ValueError('Ответ не PDF: ' + name)
            path.write_bytes(content)
        manifest.append({'name': name, 'url': url, 'file': path.name,
                         'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    (OUT / 'lua_reference.json').write_text(json.dumps(scripts, ensure_ascii=False, indent=2), encoding='utf-8')
    print('PDF:', len(manifest), 'справочных скриптов:', len(scripts))


if __name__ == '__main__':
    main()
