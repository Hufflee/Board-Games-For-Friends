# Генерирует 4 варианта «голоса» быстрого чата (по 3 реплики) через ElevenLabs.
# Ключ берётся из окружения или из пользовательских переменных Windows (setx), не печатается.
import os, sys, winreg
from elevenlabs.client import ElevenLabs

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

key = os.environ.get("ELEVENLABS_API_KEY", "")
if not key.startswith("sk_"):
	with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
		key = winreg.QueryValueEx(k, "ELEVENLABS_API_KEY")[0]
if not key.startswith("sk_"):
	sys.exit("ключ не начинается с sk_")
client = ElevenLabs(api_key=key)

SFX = {
	"A": ("Cute tiny cartoon critter voice speaking gibberish babble, warm organic squeaky animal-like voice, video game character voice, dry close mic, no music. ", {
		"wow": ("Amazed and delighted rising 'ooh-wah!' in nonsense syllables.", 0.9),
		"oops": ("Short embarrassed falling 'oop...' nonsense syllable.", 0.6),
		"hey": ("Calling out 'hey-ya, bwee?' nonsense syllables with rising question intonation.", 1.1),
	}),
	"C": ("Warm soft human closed-mouth humming, gentle friendly voice, close mic, dry, no music. ", {
		"wow": ("Impressed rising 'mmm-hmm!' with a smile.", 0.9),
		"oops": ("Short sheepish falling 'mm...'.", 0.6),
		"hey": ("Two-note questioning 'hm-hmm?' calling for attention, rising intonation.", 1.0),
	}),
	"D": ("Cozy board game UI sound, soft wooden bubble bloops, marimba-like plucky tones, warm and round, short, no reverb. ", {
		"wow": ("Three bloops rising in pitch like a delighted 'wow'.", 0.8),
		"oops": ("Two bloops falling in pitch like a sheepish 'oops'.", 0.6),
		"hey": ("Quick chatty sequence of bloops ending on a rising questioning note like 'hey, you there?'.", 1.1),
	}),
}
# B — живые междометия человека без слов (у ключа нет прав на TTS, поэтому тоже звуковые эффекты)
B = ("Single young adult human voice, natural expressive wordless interjection, playful and warm, close mic, dry, no music, no words. ", {
	"wow": ("Genuinely amazed 'ooh!' rising, like seeing something cool.", 0.8),
	"oops": ("Short sheepish 'oh...' falling, like a small mistake.", 0.6),
	"hey": ("Questioning 'heyy?' with rising intonation, calling a friend who went quiet.", 0.9),
})

def save(name: str, chunks) -> None:
	path = os.path.join(OUT, name)
	with open(path, "wb") as f:
		for c in chunks:
			f.write(c)
	print("ok", name)

ONLY = sys.argv[2] if len(sys.argv) > 2 else ""
if ONLY == "B":
	SFX = {"B": B}
for variant, (base, lines) in SFX.items():
	for line, (text, dur) in lines.items():
		save(f"{variant}_{line}.mp3", client.text_to_sound_effects.convert(text=base + text, duration_seconds=dur, prompt_influence=0.6))

