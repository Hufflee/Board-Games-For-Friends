"""Сжимает WebP-карты Four Souls без изменения размеров; исходники сохраняет в backups.
Повторный запуск всегда использует оригинал, не накапливая потери перекодирования.
"""
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
import json
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "games/four_souls/art/cards"
BACKUP = ROOT / "backups/fs_cards_original_2026-10-26"


def optimize(path):
    original = BACKUP / path.name
    source = original if original.exists() else path
    original_size = source.stat().st_size
    with Image.open(source) as image:
        dimensions = image.size
        output = BytesIO()
        image.save(output, format="WEBP", quality=85, method=6)
    data = output.getvalue()
    if len(data) < original_size:
        if not original.exists():
            shutil.copy2(path, original)
        if path.read_bytes() != data:
            temp = path.with_suffix(".webp.tmp")
            temp.write_bytes(data)
            temp.replace(path)
    with Image.open(path) as result:
        assert result.size == dimensions, path.name
        result.load()
    return original_size, path.stat().st_size


def main():
    BACKUP.mkdir(parents=True, exist_ok=True)
    (BACKUP / ".gdignore").touch()
    paths = sorted(CARDS.glob("*.webp"))
    before = after = 0
    with ThreadPoolExecutor(max_workers=4) as pool:
        for index, sizes in enumerate(pool.map(optimize, paths), 1):
            before += sizes[0]
            after += sizes[1]
            if index % 100 == 0:
                print(f"{index}/{len(paths)}", flush=True)
    report = {"cards": len(paths), "bytes_before": before, "bytes_after": after,
              "saved_percent": round((1 - after / before) * 100, 2), "quality": 85,
              "dimensions_preserved": True, "backup": str(BACKUP)}
    (ROOT / "build/fs_cards_optimization.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
