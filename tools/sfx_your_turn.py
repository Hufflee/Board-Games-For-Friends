"""Сигнал «твой ход» (hub/audio/your_turn.wav): мягкий «динь-дон» ми5 → си5, синтез.
Запуск из корня проекта: python -I tools/sfx_your_turn.py"""
import math, struct, wave

SR = 44100
DUR = 0.75
NOTES = [(659.25, 0.0), (987.77, 0.11)]  # частота, начало (с)

n = int(SR * DUR)
out = [0.0] * n
for f, start in NOTES:
    s0 = int(start * SR)
    for i in range(s0, n):
        t = (i - s0) / SR
        env = (1 - math.exp(-t * 90)) * math.exp(-t * 6.5)  # мягкая атака, затухание колокольчика
        v = (math.sin(2 * math.pi * f * t)
             + 0.35 * math.sin(2 * math.pi * f * 2 * t) * math.exp(-t * 9)
             + 0.12 * math.sin(2 * math.pi * f * 3 * t) * math.exp(-t * 14))
        out[i] += v * env
peak = max(abs(x) for x in out)
with wave.open('hub/audio/your_turn.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', int(x / peak * 0.6 * 32767)) for x in out))
