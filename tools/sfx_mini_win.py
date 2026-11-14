"""Короткий звук победы мини-игры и попадания в корзину (hub/audio/mini_win.wav), синтез, свой.
Быстрое восходящее арпеджио до5–ми5–соль5–до6 колокольчиком плюс тихие искорки сверху, ~0,9 с.
Запуск из корня проекта: python -I tools/sfx_mini_win.py"""
import math, random, struct, wave

SR = 44100
DUR = 0.9
NOTES = [(523.25, 0.0), (659.25, 0.07), (783.99, 0.14), (1046.5, 0.21)]  # частота, начало (с)

n = int(SR * DUR)
out = [0.0] * n
for k, (f, start) in enumerate(NOTES):
    s0 = int(start * SR)
    last = k == len(NOTES) - 1
    decay = 4.5 if last else 11.0  # верхняя нота звенит дольше
    for i in range(s0, n):
        t = (i - s0) / SR
        env = (1 - math.exp(-t * 160)) * math.exp(-t * decay)
        v = (math.sin(2 * math.pi * f * t)
             + 0.30 * math.sin(2 * math.pi * f * 2 * t) * math.exp(-t * 8)
             + 0.10 * math.sin(2 * math.pi * f * 3.01 * t) * math.exp(-t * 16))
        out[i] += v * env * (1.15 if last else 0.8)
# искорки: короткие высокие «динь» в хвосте
random.seed(7)
for j in range(6):
    start = 0.26 + j * 0.07 + random.uniform(-0.015, 0.015)
    f = random.choice([2093.0, 2349.3, 2637.0, 3136.0])
    s0 = int(start * SR)
    for i in range(s0, min(n, s0 + int(0.12 * SR))):
        t = (i - s0) / SR
        out[i] += 0.18 * math.sin(2 * math.pi * f * t) * (1 - math.exp(-t * 400)) * math.exp(-t * 38) * (1 - j * 0.1)
# мягкий хвост без щелчка в конце
fade = int(0.08 * SR)
for i in range(n - fade, n):
    out[i] *= (n - i) / fade
peak = max(abs(x) for x in out)
with wave.open('hub/audio/mini_win.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(x / peak * 0.6 * 32767)) for x in out))
print('hub/audio/mini_win.wav', round(DUR, 2), 's')
