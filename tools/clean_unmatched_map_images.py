"""Берёт чистые изображения схем арен без накладных T-Rex pins. Запуск из корня проекта."""

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, 'build/unmatched_faq/python_deps')
try:
    import pillow_avif  # Декодер исходников, которые сервер отдаёт как AVIF.
except ImportError:
    pass
from PIL import Image


ROOT = Path('build/unmatched_sources')


def main():
    spec = importlib.util.spec_from_file_location('maps', 'tools/compile_unmatched_workshop_maps.py')
    maps = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(maps)
    inventory = json.loads((ROOT / 'workshop_boards/index.json').read_text(encoding='utf-8'))
    sources = {}
    folder = ROOT / 'clean_maps'
    folder.mkdir(exist_ok=True)
    for identity in maps.NAMES:
        if identity in {'phone_booth', 'bathroom_stall', 'heorot', 'raptor_paddock'}:
            continue
        slug = maps.SLUGS.get(identity, identity.replace('_', '-'))
        page = (ROOT / 'workshop_map_graphs' / f'{slug}.html').read_text(encoding='utf-8')
        urls = re.findall(r'image:"(https://[^\"]+/maps/[^\"]+)"', page)
        if not urls:
            raise ValueError(f'Не найден оригинал поля {identity}')
        url = urls[-1]
        raw = folder / f'{identity}.webp'
        if not raw.exists():
            subprocess.run(['curl.exe', '-fsSL', '--max-time', '30', url, '-o', str(raw)], check=True)
        width, height = maps.read_art(identity, inventory[identity]).size
        inset = round(min(width, height) * .014)
        canvas = Image.new('RGB', (width, height), '#24333b')
        with Image.open(raw) as image:
            canvas.paste(image.convert('RGB').resize((width - 2 * inset, height - 2 * inset), Image.Resampling.LANCZOS), (inset, inset))
        canvas.save(ROOT / f'{identity}_clean.webp', quality=91, method=6)
        sources[identity] = url
        print(identity, flush=True)
    (folder / 'sources.json').write_text(json.dumps(sources, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
