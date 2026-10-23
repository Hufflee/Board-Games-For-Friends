# Полный набор «голосов» быстрого чата: 10 персонажей × 10 реплик на выдуманном языке, ≤ 1.5 с (в среднем ~1 с).
# Реплики — TTS eleven_v3 стоковыми голосами,
# «камин» — тёплое хмыканье (Sound Effects). Всё выравнивается по громкости и пишется в WAV.
# Запуск: D:\AI\elevenlabs-mcp\venv\Scripts\python.exe -I gen_voices.py <папка> [персонаж | персонаж:реплика ...]
# Ключ — из ELEVENLABS_API_KEY или переменных пользователя Windows (setx), не печатается.
import os, sys, winreg
import numpy as np
import soundfile as sf
from elevenlabs.client import ElevenLabs

OUT = sys.argv[1]
ONLY = set(sys.argv[2:])


def wanted(cid: str, line: str) -> bool:
	return not ONLY or cid in ONLY or f"{cid}:{line}" in ONLY

RATE = 24000
os.makedirs(OUT, exist_ok=True)

# сначала переменная пользователя Windows (её меняет setx без перезапуска), потом окружение процесса
try:
	with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
		key = winreg.QueryValueEx(k, "ELEVENLABS_API_KEY")[0]
except OSError:
	key = os.environ.get("ELEVENLABS_API_KEY", "")
client = ElevenLabs(api_key=key)

# Выдуманный язык «таверны» — без созвучий с русским и английским:
# teyvo — думать, zolfi — обман, druvi — кость/бросок, zif — хитрый, nyel — неудача,
# lumi — удача, tavi — чудо, tolu — вы все, sola — ну/так, belu — хороший, tuna — игра.
# реплика: (текст, общий тег эмоции). Без отдельных «хм/хе/ха» перед словом — их v3 озвучивает будто другим голосом.
LINES = {
	"think": ("Teyvo... teyvo.", "[thoughtful]"),
	"bluff": ("Zolfi-ri!", "[confident]"),
	"roll": ("Druvi-dru!", "[excited]"),
	"sly": ("Zifa, zifa-ri.", "[sly]"),
	"oops": ("Ehh... nyel-vo.", "[sheepish]"),
	"hope": ("Lumi-sa!", "[hopeful]"),
	"wow": ("Ooh, tavi!", "[amazed]"),
	"hey": ("Psst, tolu-ve?", "[calling out]"),
	"any": ("Sola menni.", "[chatty]"),
	"gg": ("Belu-tuna!", "[warmly]"),
}

# персонаж: (стоковый голос ElevenLabs, тег манеры, высота: <1 — ниже, ресемплом)
# Voice Design через API — только на платном плане, библиотечные голоса — тоже; эти доступны бесплатно.
CHARS = {
	"buddy": ("iP95p4xoKVk53GoZ742B", "[warm]", 0.94),  # Chris
	"sailor": ("N2lVS1w4EtoT3dr4eOWO", "[gruff]", 0.92),  # Callum
	"scholar": ("SOYHLrjzK2X1ezoPC6cr", "[nervous]", 1.0),  # Harry
	"duchess": ("pFZP5JQG7iQjIQuC4Bku", "[haughty]", 1.0),  # Lily
	"giant": ("nPczCjzI2devNBz1zQrb", "[booming]", 0.96),  # Brian
	"grandpa": ("pqHfZKP75CvOlQylNhV4", "[cheerful]", 1.0),  # Bill
	"villain": ("pNInz6obpgDQGcFmaJgB", "[menacing]", 0.95),  # Adam
	"schemer": ("cjVigY5qzO86Huf0OWal", "[mischievous]", 0.97),  # Eric
	"soldier": ("onwK4e9ZLuTAKqWW03F9", "[commanding]", 0.9),  # Daniel
}

# «камин» — вежливый меланхолик у камина: хмыканье с закрытым ртом (Sound Effects, как вариант C)
FIREPLACE_BASE = "Warm soft closed-mouth humming of a polite melancholic middle-aged man relaxing by a fireplace, calm and gentle, occasionally a soft murmured syllable."
FIREPLACE_TAIL = " Single person, wordless, close mic, dry, no music, no background."
FIREPLACE = {
	"think": ("Slow thoughtful 'hmmm... mm' pondering, wavering pitch.", 1.3),
	"bluff": ("Quietly confident 'hm-hm!' with a soft knowing chuckle.", 1.0),
	"roll": ("Brisk encouraging 'mm-hm, hm!' rising.", 0.9),
	"sly": ("Amused low 'hmm-hm-hm' soft chuckle through the nose.", 1.1),
	"oops": ("Sheepish slow falling 'mm... hmm' that fades out gently, with a soft exhale at the end.", 1.2),
	"hope": ("Hopeful gentle rising 'mm-mm?' then a soft 'hm'.", 1.1),
	"wow": ("Impressed rising 'mmm-hmm!' with a quiet smile.", 0.9),
	"hey": ("Two-note questioning 'hm-hmm?' calling for attention, rising intonation.", 1.2),
	"any": ("Contented murmuring hum, a short melody-like 'mm-hm-mm'.", 1.2),
	"gg": ("Warm satisfied 'mmm-hm' with a soft pleased sigh.", 1.2),
}


def check_audio(data: bytes) -> bytes:
	if data[:15].lower().startswith(b"<!doctype") or data[:5].lower() == b"<html":
		sys.exit("ElevenLabs вернул страницу «Access restricted» вместо звука — доступ заблокирован по IP")
	return data


def process(pcm: bytes, pitch: float = 1.0) -> np.ndarray:
	x = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0
	if pitch != 1.0:  # ниже и чуть медленнее, как пластинка на меньшей скорости
		x = np.interp(np.arange(0, len(x) - 1, pitch), np.arange(len(x)), x).astype(np.float32)
	# обрезаем тишину по краям (порог −45 дБ), короткие фейды
	thr = 10 ** (-45 / 20)
	idx = np.where(np.abs(x) > thr)[0]
	if len(idx):
		x = x[max(0, idx[0] - RATE // 50): idx[-1] + RATE // 10]
	# паузы внутри реплики длиннее 90 мс ужимаем до 90 мс (окна по 10 мс тише −38 дБ)
	w = RATE // 100
	quiet = np.array([np.sqrt(np.mean(x[i:i + w] ** 2)) < 10 ** (-38 / 20) for i in range(0, len(x), w)])
	keep, run = [], 0
	for i, q in enumerate(quiet):
		run = run + 1 if q else 0
		if run <= 9:
			keep.append(x[i * w:(i + 1) * w])
	x = np.concatenate(keep) if keep else x
	f = min(len(x) // 4, RATE // 100)
	x[:f] *= np.linspace(0, 1, f)
	x[-f * 4:] *= np.linspace(1, 0, f * 4)
	# громкость: RMS озвученных кусков (окна 50 мс выше −40 дБ) → −20 дБFS, пик не выше −1 дБFS
	w = RATE // 20
	frames = [x[i:i + w] for i in range(0, len(x) - w, w)] or [x]
	rms = np.array([np.sqrt(np.mean(fr ** 2)) for fr in frames])
	voiced = rms[rms > 10 ** (-40 / 20)]
	level = np.sqrt(np.mean(voiced ** 2)) if len(voiced) else np.sqrt(np.mean(x ** 2))
	gain = 10 ** (-20 / 20) / max(level, 1e-6)
	gain = min(gain, 10 ** (-1 / 20) / max(np.max(np.abs(x)), 1e-6))
	return x * gain


MAX_LEN = 1.5


def fit(x: np.ndarray, max_len: float = MAX_LEN) -> np.ndarray:
	"""Длиннее max_len — ускоряем без смены высоты (WSOLA: окна 30 мс с подбором сдвига по корреляции)."""
	target = int(max_len * RATE)
	if len(x) <= target:
		return x
	rate = len(x) / target
	n, hop, tol = RATE * 3 // 100, RATE * 3 // 200, RATE // 200
	win = np.hanning(n).astype(np.float32)
	out = np.zeros(target + n, dtype=np.float32)
	norm = np.zeros(target + n, dtype=np.float32)
	prev = 0
	for k, o in enumerate(range(0, target, hop)):
		pos = int(o * rate)
		if k > 0:  # кусок, который естественно продолжает предыдущий
			ref = x[prev + hop: prev + hop + n]
			best, score = pos, -1e9
			for d in range(-tol, tol + 1, 4):
				c = pos + d
				if c < 0 or c + n > len(x) or len(ref) < n:
					continue
				sc = float(np.dot(ref, x[c:c + n]))
				if sc > score:
					best, score = c, sc
			pos = best
		seg = x[pos:pos + n]
		if len(seg) < n:
			break
		out[o:o + n] += seg * win
		norm[o:o + n] += win
		prev = pos
	y = out / np.maximum(norm, 1e-3)
	y = y[:target]
	f = RATE // 50
	y[-f:] *= np.linspace(1, 0, f)
	return y


def save_wav(name: str, x: np.ndarray) -> None:
	x = fit(x)
	sf.write(os.path.join(OUT, name), x, RATE, subtype="PCM_16")
	print("ok", name, f"{len(x) / RATE:.1f}s")


for line, (text, dur) in FIREPLACE.items():
	if wanted("fireplace", line):
		pcm = check_audio(b"".join(client.text_to_sound_effects.convert(
			text=FIREPLACE_BASE + " " + text + FIREPLACE_TAIL, duration_seconds=dur,
			prompt_influence=0.6, output_format="pcm_24000")))
		save_wav(f"fireplace_{line}.wav", process(pcm))

for cid, (vid, manner, pitch) in CHARS.items():
	for line, (text, emo) in LINES.items():
		if not wanted(cid, line):
			continue
		best = None
		for _ in range(4):  # длиннее MAX_LEN — пробуем ещё раз, берём самый короткий
			x = process(check_audio(b"".join(client.text_to_speech.convert(
				voice_id=vid, text=f"{manner}{emo} {text}", model_id="eleven_v3",
				output_format="pcm_24000", voice_settings={"stability": 1.0, "similarity_boost": 0.75, "speed": 1.1}))), pitch)
			if best is None or len(x) < len(best):
				best = x
			if len(best) <= MAX_LEN * RATE:
				break
		save_wav(f"{cid}_{line}.wav", best)
