"""Саундтрек Four Souls: games/four_souls/audio/basement_theme.ogg из исходного mp3.
Громкость — RMS −15 dBFS (как музыка Gloom, без перегруза), тишина по краям обрезана,
плавный вход 4 с и затухание 6 с — чтобы повтор по кругу не обрывался резко.
Запуск из корня проекта: python -I tools/fs_music.py "путь/к/scary music.mp3" """
import sys
import av
import numpy as np

SRC = sys.argv[1]
OUT = "games/four_souls/audio/basement_theme.ogg"
RATE = 44100
TARGET_RMS_DB = -15.0
FADE_IN = 4.0
FADE_OUT = 6.0
SILENCE_DB = -50.0


def load(path: str) -> np.ndarray:
	c = av.open(path)
	rs = av.AudioResampler(format="fltp", layout="stereo", rate=RATE)
	chunks = []
	for fr in c.decode(c.streams.audio[0]):
		chunks += [f.to_ndarray() for f in rs.resample(fr)]
	chunks += [f.to_ndarray() for f in rs.resample(None)]
	return np.concatenate(chunks, axis=1).astype(np.float32)


a = load(SRC)
# тишина по краям
loud = np.where(np.abs(a).max(axis=0) > 10 ** (SILENCE_DB / 20))[0]
a = a[:, loud[0]:loud[-1] + 1]
# громкость
rms = np.sqrt(np.mean(a ** 2))
a *= 10 ** ((TARGET_RMS_DB - 20 * np.log10(rms)) / 20)
peak = np.abs(a).max()
if peak > 0.97:
	a *= 0.97 / peak  # без перегруза
# вход и затухание (синусоида — без «щелчка» на стыке)
n_in, n_out = int(FADE_IN * RATE), int(FADE_OUT * RATE)
a[:, :n_in] *= np.sin(np.linspace(0, np.pi / 2, n_in)) ** 2
a[:, -n_out:] *= np.cos(np.linspace(0, np.pi / 2, n_out)) ** 2
# ogg vorbis
out = av.open(OUT, "w")
st = out.add_stream("libvorbis", rate=RATE)
st.layout = "stereo"
st.bit_rate = 160000
step = 4096
for i in range(0, a.shape[1], step):
	fr = av.AudioFrame.from_ndarray(np.ascontiguousarray(a[:, i:i + step]), format="fltp", layout="stereo")
	fr.sample_rate = RATE
	for p in st.encode(fr):
		out.mux(p)
for p in st.encode(None):
	out.mux(p)
out.close()
print(f"{OUT}: {a.shape[1] / RATE:.1f} с, RMS {20 * np.log10(np.sqrt(np.mean(a ** 2))):.1f} dBFS, пик {20 * np.log10(np.abs(a).max()):.1f} dBFS")
