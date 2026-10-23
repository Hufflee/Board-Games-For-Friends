# Кандидаты «голоса» быстрого чата

Замена роботического лепета `babble_<стиль>_<1..3>.wav` (`Sfx.babble()`). 4 варианта × 3 реплики:
`wow` — «Удивительно!», `oops` — «Ой…», `hey` — «Эй, вы ещё здесь?». Всё сделано ElevenLabs Sound Effects
(`text_to_sound_effects`, `prompt_influence=0.6`), длина 0.6–1.1 с. Промпт = общая часть варианта + строка реплики.

| | Вариант | Общая часть промпта | Чем отличается |
|---|---|---|---|
| **A** | Мультяшный зверёк-лепет | Cute tiny cartoon critter voice speaking gibberish babble, warm organic squeaky animal-like voice, video game character voice | Ближе всего к нынешнему Animal Crossing-лепету, но живой, «органический» голосок вместо синтеза |
| **B** | Живые междометия человека | Single young adult human voice, natural expressive wordless interjection, playful and warm | Настоящий человеческий голос: «ох!», «ой…», «эй?» — самый естественный, меньше всего «игрушечный» |
| **C** | Тёплое хмыканье | Warm soft human closed-mouth humming, gentle friendly voice | «Мм-хм!», «мм…», «хм-хмм?» с закрытым ртом — тихо, ненавязчиво, не надоедает при частых репликах |
| **D** | Уютные «пузырьки» | Cozy board game UI sound, soft wooden bubble bloops, marimba-like plucky tones | Без голоса вообще: деревянные «блупы» как у маримбы, интонация — высотой нот. Самый «настольный» |

Строки реплик:
- `wow` — amazed/delighted, rising («ooh-wah!» / «mmm-hmm!» / три ноты вверх)
- `oops` — sheepish, falling («oop…» / «mm…» / две ноты вниз)
- `hey` — questioning, rising, calling for attention («hey-ya, bwee?» / «hm-hmm?» / болтливая серия с вопросом в конце)

Точные промпты — в `gen_babble.py`. Запуск (ключ берётся из `ELEVENLABS_API_KEY` или из переменных пользователя Windows, не печатается):
`D:\AI\elevenlabs-mcp\venv\Scripts\python.exe -I gen_babble.py <папка> [B]`

## Персонажи (`characters/`, скрипт `gen_chars.py`)
Выбор пользователя: понравился C (вежливый меланхолик у камина), A — слишком детский, B — нормальный, но ниже.
Цель — 8 персонажей, у каждого свой голос. Пробники — 10 кандидатов по 3 реплики, из них выбрать 8:
01 fireplace (C, wow/hey — исходные C, oops перегенерирован длиннее), 02 buddy (B ниже, баритон), 03 granny,
04 sailor, 05 sunny (отклонён), 06 schemer, 07 sleepy, 08 scholar, 09 duchess, 10 giant; вторая партия по просьбе
пользователя: 11 grandpa (бодрый дед), 12 villain, 13 baritone (низкий, выше гиганта), 14 mumbler (мямлит), 15 soldier.
Промпты — в `gen_chars.py`.

Высота голоса у разных игроков по-прежнему задаётся в `Sfx.babble()` питчем, так что одного набора на вариант хватит.
Вариант B задумывался через TTS `eleven_v3`, но у текущего ключа нет права `text_to_speech` — сделан звуковыми эффектами.
