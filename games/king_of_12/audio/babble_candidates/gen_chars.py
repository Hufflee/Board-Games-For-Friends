# Пробники «персонажей» быстрого чата: у каждого свой голос без слов, 3 реплики (wow / oops / hey).
# Запуск: D:\AI\elevenlabs-mcp\venv\Scripts\python.exe -I gen_chars.py <папка> [id персонажа ...]
# Ключ — из ELEVENLABS_API_KEY или переменных пользователя Windows (setx), не печатается.
import os, sys, winreg
from elevenlabs.client import ElevenLabs

OUT = sys.argv[1]
ONLY = set(sys.argv[2:])
os.makedirs(OUT, exist_ok=True)

# сначала переменная пользователя Windows (её меняет setx без перезапуска), потом окружение процесса
try:
	with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
		key = winreg.QueryValueEx(k, "ELEVENLABS_API_KEY")[0]
except OSError:
	key = os.environ.get("ELEVENLABS_API_KEY", "")
if not key.startswith("sk_"):
	sys.exit("ключ не начинается с sk_")
client = ElevenLabs(api_key=key)

TAIL = " Single person, wordless vocal sound only, no words, close mic, dry, no music, no background."

# id: (общая часть, {реплика: (строка, длительность)})
CHARS = {
	"01_fireplace": ("Warm soft closed-mouth humming of a polite melancholic middle-aged man, calm and gentle.", {
		"wow": ("Impressed rising 'mmm-hmm!' with a quiet smile.", 0.9),
		"oops": ("Sheepish slow falling 'mm... hmm' that fades out gently, with a soft exhale at the end.", 1.2),
		"hey": ("Two-note questioning 'hm-hmm?' calling for attention, rising intonation.", 1.0),
	}),
	"02_buddy": ("Natural expressive interjection of a friendly adult man with a low warm baritone voice, relaxed and good-natured.", {
		"wow": ("Genuinely amazed low 'ohh!' rising, like seeing something cool.", 0.9),
		"oops": ("Short sheepish low 'oh...' falling, like a small mistake, with a little laugh.", 1.0),
		"hey": ("Low questioning 'heyy?' with rising intonation, calling a friend who went quiet.", 1.0),
	}),
	"03_granny": ("Soft airy voice of a kind elderly grandmother, gentle and caring.", {
		"wow": ("Delighted soft 'oh my!' gasp with a warm little chuckle.", 1.0),
		"oops": ("Gentle tutting 'tsk-tsk, ohh...' falling, forgiving.", 1.2),
		"hey": ("Sweet questioning 'hmm? yoo-hoo?' rising, calling softly.", 1.1),
	}),
	"04_sailor": ("Gruff raspy voice of an old sea captain, rough but good-humored.", {
		"wow": ("Impressed gruff 'harr!' with a throaty chuckle.", 0.9),
		"oops": ("Annoyed low grumble 'hrrmph...' falling.", 1.0),
		"hey": ("Gruff questioning 'oi?' then 'hrm?' rising, demanding attention.", 1.0),
	}),
	"05_sunny": ("Bright cheerful voice of an energetic young adult woman, upbeat and expressive, not childish.", {
		"wow": ("Excited bright 'ooh!' with a delighted giggle.", 0.9),
		"oops": ("Embarrassed 'ah-ah...' falling into a nervous little laugh.", 1.0),
		"hey": ("Playful sing-song questioning 'heyy-ey?' rising.", 1.0),
	}),
	"06_schemer": ("Smooth low voice of a sly cunning schemer, smug and mischievous.", {
		"wow": ("Impressed smug low 'heh-heh-heh' chuckle.", 1.0),
		"oops": ("Displeased hiss through teeth 'tsss... hm' falling.", 1.0),
		"hey": ("Sly drawn-out questioning 'hmmm?' rising, suspicious.", 1.0),
	}),
	"07_sleepy": ("Lazy drowsy voice of a sleepy relaxed young man, slow and mellow.", {
		"wow": ("Slow lazy impressed 'whoaa...' with a yawn-like tone.", 1.1),
		"oops": ("Long tired sigh 'ehhh...' falling.", 1.2),
		"hey": ("Drowsy drawn-out questioning 'mmh? hmm?' rising.", 1.1),
	}),
	"08_scholar": ("Nervous breathy voice of an anxious bookish young scholar, quick and fidgety.", {
		"wow": ("Surprised quick 'oh! ah!' gasp, fascinated.", 0.8),
		"oops": ("Flustered stammering 'ah- ah- uh...' falling.", 1.0),
		"hey": ("Timid hesitant questioning 'um? uh...?' rising.", 1.0),
	}),
	"09_duchess": ("Cool refined voice of a haughty aristocratic lady, dignified and elegant.", {
		"wow": ("Mildly impressed elegant 'ohh~' rising, slightly surprised.", 1.0),
		"oops": ("Disdainful short 'hmph!' and a small sigh.", 1.0),
		"hey": ("Impatient questioning 'ahem?' rising, demanding attention.", 1.0),
	}),
	"10_giant": ("Deep booming voice of a big jolly giant man, hearty and loud.", {
		"wow": ("Hearty booming 'ho-ho!' belly laugh.", 1.0),
		"oops": ("Deep embarrassed 'uh-oh...' rumbling, falling.", 1.1),
		"hey": ("Deep booming questioning 'hmm? heyy?' rising.", 1.1),
	}),
	"11_grandpa": ("Lively cheerful voice of an energetic jolly old grandpa, slightly creaky but full of energy.", {
		"wow": ("Delighted lively 'oho-ho!' with a cheeky cackle.", 1.0),
		"oops": ("Good-humored 'ehh-heh-heh...' falling, laughing at himself.", 1.1),
		"hey": ("Spry questioning 'eh? ehh?' rising, nudging for attention.", 1.0),
	}),
	"12_villain": ("Dark menacing voice of a theatrical evil villain, low and sinister.", {
		"wow": ("Sinister pleased low 'mwa-ha-ha' evil chuckle.", 1.1),
		"oops": ("Irritated low snarl 'grrr... hmph' falling.", 1.1),
		"hey": ("Cold menacing drawn-out questioning 'hmmm?' rising.", 1.1),
	}),
	"13_baritone": ("Calm deep baritone voice of a sturdy confident man, low but not booming, steady and warm.", {
		"wow": ("Impressed low 'ohh-ho!' rising, approving.", 0.9),
		"oops": ("Low rueful 'ohh... hm' falling, calm.", 1.1),
		"hey": ("Low questioning 'hm? hey?' rising, steady.", 1.0),
	}),
	"14_mumbler": ("Quiet unsure voice of a shy insecure young man, mumbling under his breath, hesitant.", {
		"wow": ("Quiet hesitant impressed 'oh... wow-hm' mumbled.", 1.0),
		"oops": ("Embarrassed mumbled 'uh... mm... sorry-hm' trailing off.", 1.2),
		"hey": ("Timid mumbling 'um... hm?' barely rising.", 1.1),
	}),
	"15_soldier": ("Firm crisp voice of a disciplined soldier, short clipped strict sounds, commanding.", {
		"wow": ("Sharp approving 'hah!' clipped and firm.", 0.7),
		"oops": ("Curt displeased 'tch! hm.' clipped.", 0.8),
		"hey": ("Sharp commanding 'hey! oi!' firm and loud.", 0.8),
	}),
}

for cid, (base, lines) in CHARS.items():
	if ONLY and cid not in ONLY:
		continue
	for line, (text, dur) in lines.items():
		name = f"{cid}_{line}.mp3"
		audio = b"".join(client.text_to_sound_effects.convert(text=base + " " + text + TAIL, duration_seconds=dur, prompt_influence=0.6))
		# при блокировке по региону сервер отдаёт HTML-страницу вместо mp3
		if audio[:15].lower().startswith(b"<!doctype") or audio[:5].lower() == b"<html":
			sys.exit("ElevenLabs вернул страницу «Access restricted» вместо звука — доступ заблокирован по IP")
		with open(os.path.join(OUT, name), "wb") as f:
			f.write(audio)
		print("ok", name)
