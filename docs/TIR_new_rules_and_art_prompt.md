# Things in Rings — новые условия и промт для своих карточек предметов

Одобрено владельцем 06.11.2026. Новые условия внесены в игру (`tools/tr_make_rule_cards.py`, id 224–247, 324–347, 424–447); промт для карточек предметов — раздел 4.

## 1. Разбор существующих условий (по 24 в каждой категории)

**Признак (Attribute)** — физические свойства самой вещи, их можно проверить, просто представив её.
- Размер и вес: «Имеет стандартный размер», «Обычно одного размера», «Можно держать одной рукой», «Весит больше стула», «Больше человека».
- Материал: древесина, пластик.
- Форма и поверхность: круглое или изогнутое, остриё, отверстия, пятна или полосы, одноцветное, блестящее, прозрачное, с надписями.
- Вода и огонь: держится на воде, не должно намокать, легко воспламеняется.
- Чувства: издаёт звук, ярко выраженный вкус.
- Состояние: живое, легко разрушить, легко очистить, больно, если упадёт.
- *Чего нет:* металла, стекла и ткани; мягкости; электричества; движущихся частей; съедобности; запаха; температуры; цвета (кроме «одноцветное»); вместимости; гибкости; света.

**Контекст (Context)** — отношение людей к вещи: где её встречают, кому она принадлежит, сколько стоит, сколько живёт, какие чувства вызывает.
- Места: дом, школа, офис, «это здание», улица, сельская местность, «в часе пути».
- Деньги: можно купить в магазине, дороже 100 $, есть только у богатых.
- Время: существовало до 1776 года, прослужит больше 100 лет, одноразовое.
- Люди: радует, все трогали, видят регулярно, миф или легенда, опасное, полезное, поможет выжить, можно в самолёт, создано человеком, встречается группами, легко найти.
- *Чего нет:* конкретных комнат (кухня, ванная), пляжа, города, больницы; детей и игр; подарков и праздников; изобретений последних 100 лет; сезонов и ночи; аренды и лицензий; редкого и коллекционного; дешёвого.

**Название (Word)** — свойства английского слова на карточке. Доля подходящих названий у оригинальных правил — от 19 % («ровно 5 букв») до 44 % («не больше 5 букв»), у «есть буква O» — 42 %.
- Длина: ≤5, ровно 5, 4–6, 6–8.
- Первая и последняя буква: A–M, N–Z, гласная или Y, согласная или Y, две согласные в конце.
- Конкретные буквы: O, R.
- Гласные: повторяющиеся, ≥2 разных, ровно 1, ≥2 подряд.
- Слоги: 1, 2.
- Повторы: удвоенная буква, повторяющаяся буква, первая буква встречается ещё раз.
- Сочетания: 3 согласные подряд, первые 2 буквы по алфавиту, составное слово.
- *Чего нет:* букв E/A/S/T/I/L/N, гласной в конце, длины от 7 букв, чётной длины, редких букв, чередования гласных и согласных, ≥3 слогов, окончаний.

## 2. Новые условия

Все новые условия закрывают пробелы из списка выше и не повторяют старые.

### Признак — 24 новых
| # | English | Русский |
|---|---|---|
| A1 | CONTAINS METAL | Содержит металл |
| A2 | CONTAINS GLASS | Содержит стекло |
| A3 | CONTAINS FABRIC OR CLOTH | Содержит ткань |
| A4 | SOFT TO THE TOUCH | Мягкое на ощупь |
| A5 | USES ELECTRICITY | Работает от электричества |
| A6 | HAS MOVING PARTS | Есть движущиеся части |
| A7 | HAS A HANDLE | Есть ручка |
| A8 | HAS LEGS OR WHEELS | Есть ноги или колёса |
| A9 | HAS EYES | Есть глаза |
| A10 | EDIBLE | Съедобное |
| A11 | HAS A NOTICEABLE SMELL | Имеет заметный запах |
| A12 | USUALLY WARM OR HOT | Обычно тёплое или горячее |
| A13 | USUALLY COLD | Обычно холодное |
| A14 | OFTEN RED, ORANGE OR YELLOW | Часто красное, оранжевое или жёлтое |
| A15 | OFTEN GREEN OR BLUE | Часто зелёное или синее |
| A16 | FITS IN A POCKET | Помещается в карман |
| A17 | MUCH LONGER THAN IT IS WIDE | Намного длиннее, чем шире |
| A18 | HAS A LID, DOOR OR COVER | Есть крышка, дверца или чехол |
| A19 | CAN HOLD WATER | Может удерживать воду |
| A20 | CAN BE FOLDED OR ROLLED UP | Можно сложить или свернуть |
| A21 | USUALLY COMES IN PAIRS | Обычно бывает парой |
| A22 | BENDS WITHOUT BREAKING | Гнётся и не ломается |
| A23 | GLOWS OR GIVES OFF LIGHT | Светится или даёт свет |
| A24 | SQUARE OR BOXY | Квадратное или в форме коробки |

### Контекст — 24 новых
| # | English | Русский |
|---|---|---|
| C1 | FOUND IN A KITCHEN | Встречается на кухне |
| C2 | FOUND IN A BATHROOM | Встречается в ванной |
| C3 | FOUND AT THE BEACH OR NEAR WATER | Встречается на пляже или у воды |
| C4 | FOUND IN A CITY CENTER | Встречается в центре города |
| C5 | FOUND IN A HOSPITAL | Встречается в больнице |
| C6 | YOU'D SEE IT IN A MUSEUM | Это можно увидеть в музее |
| C7 | CHILDREN PLAY WITH IT | С этим играют дети |
| C8 | USED IN SPORTS OR GAMES | Используется в спорте или играх |
| C9 | A GOOD GIFT | Хороший подарок |
| C10 | ASSOCIATED WITH A HOLIDAY | Связано с каким-то праздником |
| C11 | INVENTED IN THE LAST 100 YEARS | Изобретено за последние 100 лет |
| C12 | ASSOCIATED WITH WINTER | Связано с зимой |
| C13 | ASSOCIATED WITH NIGHT | Связано с ночью |
| C14 | MANY PEOPLE ARE AFRAID OF IT | Многие этого боятся |
| C15 | MOST PEOPLE HAVE NEVER SEEN ONE IN REAL LIFE | Большинство никогда не видели это вживую |
| C16 | PEOPLE COLLECT IT | Это коллекционируют |
| C17 | YOU CAN RENT IT | Это можно взять напрокат |
| C18 | NEEDS A LICENSE OR PERMISSION | Нужны права или разрешение |
| C19 | NEEDS REGULAR CARE | Требует регулярного ухода |
| C20 | USUALLY SHARED BY MANY PEOPLE | Обычно этим пользуются многие сразу |
| C21 | USUALLY BELONGS TO ONE PERSON | Обычно принадлежит одному человеку |
| C22 | USUALLY COSTS LESS THAN $5 | Обычно стоит меньше 5 долларов |
| C23 | YOU'D PACK IT FOR A VACATION | Это берут с собой в отпуск |
| C24 | PEOPLE OFTEN TAKE PHOTOS OF IT | Это часто фотографируют |

### Название — 24 новых (в скобках — доля из 270 нынешних названий)
| # | English | Русский | Доля |
|---|---|---|---|
| W1 | HAS AN “E” | В названии есть буква E | 52 % |
| W2 | HAS AN “A” | В названии есть буква A | 52 % |
| W3 | HAS AN “I” | В названии есть буква I | 33 % |
| W4 | HAS AN “S” | В названии есть буква S | 28 % |
| W5 | HAS A “T” | В названии есть буква T | 29 % |
| W6 | HAS AN “L” | В названии есть буква L | 31 % |
| W7 | HAS AN “N” | В названии есть буква N | 30 % |
| W8 | HAS A “P” OR “B” | В названии есть буква P или B | 36 % |
| W9 | HAS A “C” OR “K” | В названии есть буква C или K | 32 % |
| W10 | HAS A “J”, “K”, “Q”, “V”, “W”, “X” OR “Z” | В названии есть J, K, Q, V, W, X или Z | 31 % |
| W11 | ENDS WITH A VOWEL (NOT INCLUDING “Y”) | Название заканчивается гласной, без учёта Y | 25 % |
| W12 | 7 OR MORE LETTERS LONG | Название длиной от 7 букв | 38 % |
| W13 | HAS AN EVEN NUMBER OF LETTERS | В названии чётное число букв | 53 % |
| W14 | HAS EXACTLY 3 VOWELS | В названии ровно 3 гласные | 25 % |
| W15 | HAS 3 OR MORE DIFFERENT VOWELS | В названии 3 или больше разные гласные | 21 % |
| W16 | HAS 3 OR MORE SYLLABLES | В названии 3 слога или больше | ~25 % |
| W17 | STARTS WITH 2 CONSONANTS (E.G. STAR, CLOCK) | Название начинается с двух согласных (например STAR, CLOCK) | 23 % |
| W18 | FIRST AND LAST LETTERS ARE BOTH “A”–“M” | Первая и последняя буквы — обе от A до M | 31 % |
| W19 | LAST LETTER COMES LATER IN THE ALPHABET THAN THE FIRST | Последняя буква стоит в алфавите дальше первой | 54 % |
| W20 | NO LETTERS AFTER “S” IN THE ALPHABET | В названии нет букв дальше S по алфавиту | 46 % |
| W21 | HAS 2 ALPHABET NEIGHBORS SIDE BY SIDE (E.G. “ST”, “ED”) | В названии рядом стоят две соседние по алфавиту буквы (например ST, ED) | 30 % |
| W22 | VOWELS AND CONSONANTS ALTERNATE (E.G. BANANA) | Гласные и согласные чередуются (например BANANA) | 17 % |
| W23 | AT LEAST TWICE AS MANY CONSONANTS AS VOWELS | Согласных минимум вдвое больше, чем гласных | 50 % |
| W24 | ENDS WITH “ER”, “LE”, “ON”, “EL”, “ET”, “EN” OR “AN” | Оканчивается на ER, LE, ON, EL, ET, EN или AN | 20 % |

Доли посчитаны скриптом по текущим 270 названиям (Y — не гласная; MJÖLNIR = MJOLNIR, I.D. = ID). Для W16 доля оценочная, слоги на глаз. Условия дольше 50 % (W1, W2, W13, W19, W23) почти делят колоду пополам: в кольцах такие работают хуже. Если колода получится тяжёлой, их можно убрать первыми.

**Важно про язык.** Правила «Название» проверяют английское слово. Если надписи на карточках станут переключаемыми, то для русского языка нужен отдельный набор правил «Название», считанный по русским словам: слоги, буквы и длина у перевода другие. «Признак» и «Контекст» от языка не зависят.

## 3. Как устроены карточки предметов сейчас (по 10 изображениям)
- Портретная карта 2 : 3 (417×634), без рамки, фон — одна насыщенная заливка на весь лист. Встречаются оранжево-терракотовый, ярко-розовый, голубой (cyan) и королевский синий.
- Сверху по центру — название крупными комиксными прописными (белые с тёмной обводкой или чёрные). Оно занимает верхние ~20 % карты: там только фон. **В новых картинках этого текста не будет, место остаётся пустым.**
- Предмет один, крупный, в нижних ~75 % карты. Часто он срезан нижним или боковым краем, это даёт динамику.
- Рисунок комиксный: толстый чёрный контур тушью, плоская заливка, немного штриховки тушью для объёма. Вокруг предмета — белый «стикерный» ореол, отделяющий его от фона.
- Юмор в постановке: банан на античной колонне, облако в форме утки, молоток в замахе с линиями движения над гвоздём, чайник льёт чай. Предмет «играет», а не просто лежит.
- Размытость, мыльные края и «акварельные» пятна на части карточек — артефакты старого апскейла. Их в промт не переносить.

## 4. Промт для Codex (image gen)

Общий шаблон. `{THING}` — английское название, `{SCENE}` — одна короткая забавная постановка, `{BG}` — цвет фона. Чтобы колода была разнообразной, цвет лучше чередовать по списку.

```
Create a single portrait playing-card illustration, aspect ratio 2:3 (e.g. 1024x1536), full-bleed, no border, no frame, no rounded corners.

SUBJECT: one {THING}, clearly recognizable at a glance even at small size. Staging: {SCENE}. The object is the only hero of the card, large and bold, occupying the lower 75% of the card; it may be slightly cropped by the bottom or side edge for dynamism.

COMPOSITION: keep the TOP 22% of the card completely empty — only the flat background color, no objects, no effects, no sky details — this band is reserved for a title that will be added later in software. Centered composition, generous negative space, simple silhouette.

STYLE: playful hand-drawn comic / cartoon illustration, thick confident black ink outlines with slight hand-made wobble, flat saturated colors, light ink hatching or simple cel shading for volume, a few small motion lines or sparkle marks only when they add humor. A clean white sticker-like outline (6–10 px) around the main object to separate it from the background. Gentle visual humor: the object is doing something, posing or used in a funny but readable way. Crisp, sharp, clean edges, high detail in line work, print-quality.

BACKGROUND: one flat solid color, {BG}, no gradients, no texture, no pattern, no vignette, uniform across the whole card.

STRICTLY NO TEXT: no letters, no words, no numbers, no captions, no title, no labels, no logos, no brand names, no signatures, no watermarks, no speech bubbles with text, no fake writing. If the object normally carries writing (book, map, ticket, sign, keyboard, screen, flag, label), show it with blank shapes, simple lines or abstract squiggles that do not read as letters.

AVOID: photorealism, 3D render look, gradients, blur, soft airbrush, watercolor bleeding, noisy or muddy colors, JPEG artifacts, multiple unrelated objects, busy backgrounds, borders or card frames, drop shadows outside the object.
```

**Цвета фона `{BG}`** (чередовать, чтобы в руке не было двух одинаковых подряд):
`warm terracotta orange (#D9703A)`, `hot magenta pink (#F03C9E)`, `bright sky cyan (#2EC4EE)`, `royal blue (#2462B4)`, `sunny yellow (#F5C431)`, `grass green (#4CB648)`, `violet purple (#8A4FC8)`, `coral red (#EE5547)`.
Предмет не должен сливаться с фоном: жёлтый банан — не на жёлтом, синий кит — не на синем.

**Примеры `{SCENE}`:**
- HAMMER — mid-swing toward a nail, motion lines behind the head
- BANANA — proudly displayed on a small classical marble column like a museum piece
- CLOUD — a fluffy cloud shaped like a sleeping duck, a few small clouds around
- TEAPOT — tilted, pouring a stream of tea downward out of frame
- KEY — big shiny brass key floating at a jaunty angle, tiny sparkle
- DRAGON — small grumpy dragon sitting on a pile of bones, wings raised

Если Codex генерирует пачкой, для каждой карты подставлять только `{THING}`, `{SCENE}` и `{BG}`, остальной текст не менять: так стиль всей колоды останется единым.

## 4а. Единый промт: перерисовать каждую карточку предмета

Подстановок нет: Codex прикладывает к промту текущую карточку как образец и применяет один и тот же текст ко всем 270.

**Задание для Codex (обёртка):**
```
For every card in games/things_in_rings/logic/tr_catalog.json with "kind": "Thing", take the reference image games/things_in_rings/art/cards/<id>.webp and generate a new image with the prompt below (attach the reference image to each request). Save the result as PNG, 1024x1536, to games/things_in_rings/art/cards_new/<id>.png. Do not overwrite the original files. Skip ids that already exist in cards_new. After each batch of 20, make a contact sheet so the owner can review the style.
```

**Промт картинки (одинаковый для всех карточек):**
```
Redraw the attached reference card as a brand-new, original illustration in a clean, consistent style. The reference is only a guide for WHAT the object is, its main color and the idea of its pose; it is low quality and blurry — do not copy its blur, artifacts, line wobble or exact drawing.

OUTPUT: a single portrait card illustration, aspect ratio 2:3 (1024x1536), full-bleed, no border, no frame, no rounded corners.

SUBJECT: the same single object as in the reference, instantly recognizable even at small size. Keep the playful idea of the reference (e.g. an object in action, on a pedestal, with a funny shape), but you may simplify it. The object is large and bold, the only hero of the card, placed in the lower 75% of the card; it may be slightly cropped by the bottom or side edge.

COMPOSITION: the TOP 22% of the card must be completely empty — only the flat background color. Remove the title text from the reference entirely and do not put anything in its place; this band is reserved for a title added later in software.

STYLE: playful hand-drawn comic / cartoon illustration, thick confident black ink outlines, flat saturated colors, light ink hatching or simple cel shading for volume, small motion lines or sparkles only where they add humor. A clean white sticker-like outline (6–10 px) around the object separates it from the background. Crisp, sharp, clean edges, print quality.

BACKGROUND: one flat solid color matching the background color of the reference card (same hue, clean and saturated); if the object would blend into it, pick the nearest contrasting color from: terracotta orange #D9703A, magenta pink #F03C9E, sky cyan #2EC4EE, royal blue #2462B4, sunny yellow #F5C431, grass green #4CB648, violet #8A4FC8, coral red #EE5547. No gradients, no texture, no pattern, no vignette.

STRICTLY NO TEXT: no letters, words, numbers, captions, title, labels, logos, brand names, signatures, watermarks or fake writing anywhere. If the object normally carries writing (book, map, ticket, sign, keyboard, screen, flag, label), show blank shapes or abstract squiggles that do not read as letters.

AVOID: photorealism, 3D render look, gradients, blur, soft airbrush, watercolor bleeding, muddy colors, JPEG artifacts, extra unrelated objects, busy backgrounds, borders or card frames.
```

## 4б. Промт для карт условий (пустая рамка, текст пишет игра)

Сейчас новые карты условий нарисованы на рамке, взятой с оригинальных карт. Чтобы рамка была своей, нужны три пустых бланка, по одному на категорию. Текст условия игра или скрипт `tools/tr_make_rule_cards.py` печатает поверх. `{FRAME}` — цвет категории.

```
Create a single portrait playing-card front, aspect ratio 2:3 (e.g. 1024x1536), full-bleed, no rounded corners.

LAYOUT: a large blank off-white paper panel (#F2F1EC) fills the center of the card, about 78% of the width and 85% of the height, perfectly centered. Around it is a colored border in {FRAME}. The edge between the panel and the border is a hand-drawn zigzag of small flame-like or burst-like spikes pointing inward into the panel, drawn with a thick wobbly black ink line, evenly spaced along all four sides and rounding the corners.

BORDER STYLE: the colored border is painted in a loose comic / hand-drawn way: flat saturated color, slightly darker toward the outer edge, light brush texture, no patterns, no icons, no objects.

PANEL: completely empty, flat, clean, evenly lit, no texture, no lines, no shadows, no decorations — this area is reserved for text that will be added later in software.

STRICTLY NO TEXT: no letters, no words, no numbers, no symbols, no logos, no watermarks, no signatures anywhere on the card.

AVOID: photorealism, 3D look, gradients inside the panel, blur, JPEG artifacts, ornaments, extra frames, drop shadows, anything inside the white panel.
```

**Цвет `{FRAME}`** — один на категорию, чтобы карты различались с первого взгляда:
- «Признак» (Attribute): `warm red (#E0474C)`
- «Контекст» (Context): `grass green (#3FA34D)`
- «Название» (Word): `royal blue (#2F6FD0)`
(Новая схема цветов категорий, решение владельца 06.11: Признак — красный, Контекст — зелёный, Название — синий.)

Все три бланка лучше генерировать из одного запуска (то же зерно, тот же промт, меняется только `{FRAME}`), чтобы зубчатая рамка совпадала по форме. Готовые бланки положить в `games/things_in_rings/art/cards/blank_{attribute,word,context}.png`. В скрипте `tools/tr_make_rule_cards.py` взять их вместо оригинальных карт (функция `blank`), стирать текст тогда уже не нужно. Так можно перерисовать все 144 условия, включая оригинальные 72.

**Рубашки** (по желанию) — тот же стиль, без текста:
```
Create a portrait card back, aspect ratio 2:3, full-bleed. Background {FRAME}. Three large overlapping translucent circles (red, yellow, blue) like a Venn diagram, drawn in a loose hand-painted comic style with thick wobbly black ink outlines, the overlaps showing blended colors. Leave the top 20% empty for a title added later in software. Strictly no text, letters, numbers, logos or watermarks. No photorealism, no 3D look, no blur.
```

## 4в. Промт для новой коробки (хаб)

В хабе коробка состоит из трёх картинок: `hub/covers/things_in_rings_front.png` 900×1200, `_back.png` 900×1200 и `_spine.png` 168×1200. Название и надписи генератор рисует плохо, поэтому картинки генерируются **без текста** с пустыми местами под надписи. Надписи потом накладывает скрипт (как в `tools/cover_poker.py`), и их можно перевести. Цвета колец — по новой схеме: красный «Признак», зелёный «Контекст», синий «Название».

**Лицевая сторона:**
```
Board game box front cover illustration, portrait 3:4 (1200x1600), full-bleed, flat 2D, no box mockup, no perspective, no 3D.

CONCEPT: a playful sorting game about everyday things and secret rules. Center: three large overlapping rings forming a Venn diagram — a RED ring, a GREEN ring and a BLUE ring (red #E0474C, green #3FA34D, blue #2F6FD0), drawn as thick hand-inked hoops with wobbly black ink outlines; where they overlap, show the rings passing over and under each other. Inside and around the rings, 7–9 small cartoon objects are being sorted, each sitting in a different region (for example: a banana, a rubber duck, a key, a teapot, a little dragon, a balloon, a hammer, a cactus, a cloud), some tilted, one object mid-air as if being tossed into a ring. Small motion lines and sparkles for fun.

STYLE: playful hand-drawn comic / cartoon illustration, thick confident black ink outlines, flat saturated colors, light ink hatching, white sticker-like outlines around each object. Background: warm cream paper (#F4EEDF) with a very subtle dot texture, slightly torn hand-drawn paper edge near the card border.

TITLE SPACE: keep the TOP 28% of the cover empty — only the cream background — for a title added later in software. Keep a clean empty strip at the very bottom (8%) for a small tagline.

STRICTLY NO TEXT: no letters, words, numbers, logos, labels, signatures or watermarks anywhere. Objects with writing show blank shapes only.

AVOID: photorealism, 3D render, gradients, blur, JPEG artifacts, clutter, more than three rings, rings in other colors.
```

**Обратная сторона:**
```
Board game box back illustration, portrait 3:4 (1200x1600), flat 2D, same style as the front: playful hand-drawn comic, thick wobbly black ink outlines, flat saturated colors, warm cream paper background (#F4EEDF) with subtle dot texture and a torn hand-drawn paper edge.

CONTENT: three overlapping rings as a clean Venn diagram in the middle third of the image — RED (#E0474C), GREEN (#3FA34D) and BLUE (#2F6FD0) — thick hand-inked hoops, interlaced over and under. Inside the regions, 4–5 tiny cartoon objects with white sticker outlines. Leave the TOP 20% and BOTTOM 25% completely empty cream background for text added later in software.

STRICTLY NO TEXT: no letters, words, numbers, logos or watermarks. AVOID: photorealism, 3D, gradients, blur, clutter.
```

**Корешок:**
```
Board game box spine, very tall narrow strip, aspect ratio 1:7 (230x1600), flat 2D. Solid royal blue background (#2F6FD0) with a thin cream inner border (#F4EEDF) drawn as a slightly wobbly hand-inked line. At the very top a small red ring and at the very bottom a small green ring, both hand-inked with black outlines. The middle 80% stays completely empty for a vertical title added later in software. Strictly no text, letters, numbers or logos. No gradients, no 3D.
```

После генерации я ужму картинки до 900×1200 / 168×1200 и наложу надписи: на лицо — THINGS IN RINGS и слоган, на обратную сторону — русские строки, как сейчас.

## 5. Что понадобится потом в игре (не сделано)
- Название поверх картинки: в `TRData`/`tr_card.gd` рисовать подпись в верхней полосе своим шрифтом (крупные комиксные прописные, светлые с тёмной обводкой или наоборот, по яркости фона). Язык берётся из настройки, текст — из `tr_catalog.json` (`en`/`ru`). Сейчас название «впечатано» в картинку.
- Для русского языка — отдельный набор правил «Название» (см. выше).
