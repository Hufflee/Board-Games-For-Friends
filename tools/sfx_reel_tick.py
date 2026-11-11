## Синтез щелчка трещотки кубомёта: hub/audio/reel_tick.wav (звучит на каждом ребре барабана).
## Запуск: python -I tools/sfx_reel_tick.py
import math, random, struct, wave, os
RATE = 44100
random.seed(7)
n = int(RATE * 0.07)
out = []
lp = 0.0
for i in range(n):
	t = i / RATE
	# щелчок язычка: короткий отфильтрованный шум
	noise = random.uniform(-1, 1)
	lp += (noise - lp) * 0.35
	click = lp * math.exp(-t / 0.0018) * 0.9
	# деревянно-латунный отзвук: две затухающие резонансные ноты и мягкое «тело»
	ring = (math.sin(2 * math.pi * 2350 * t) * 0.32 + math.sin(2 * math.pi * 3900 * t) * 0.14) * math.exp(-t / 0.012)
	body = math.sin(2 * math.pi * 520 * t) * 0.3 * math.exp(-t / 0.02)
	attack = min(1.0, i / (RATE * 0.0004))
	out.append((click + ring + body) * attack)
peak = max(abs(v) for v in out)
path = os.path.join(os.path.dirname(__file__), "..", "hub", "audio", "reel_tick.wav")
with wave.open(path, "wb") as w:
	w.setnchannels(1)
	w.setsampwidth(2)
	w.setframerate(RATE)
	w.writeframes(b"".join(struct.pack("<h", int(v / peak * 0.8 * 32767)) for v in out))
print("ok", path)
