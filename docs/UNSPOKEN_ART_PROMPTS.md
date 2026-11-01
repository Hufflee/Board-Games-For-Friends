# Unspoken — обновление арта 01.11.2026

## Уточнение для 8 игроков

На коробке заменено только число участников «2–4» на «2–8». Встроенный ImageGen, исходный лист — утверждённая коробка, итоговый путь тот же `hub/covers/unspoken_wrap.png`, размер 1448×1086 и границы атласа сохранены.

```text
Make an extremely precise text-only edit to this already approved game box texture atlas. Change ONLY the tiny player-count text at the bottom of the LEFT/front panel from '2–4' to '2–8', matching the existing font, size, spacing, ink color and baseline. Preserve absolutely everything else pixel-for-pixel where possible: the UNSPOKEN titles, all illustrations, all Russian captions, 20 MIN, palette, grain, the front/spine/back vertical panel boundaries and exact original 1448x1086 canvas dimensions. Do not redesign, redraw, move, resize or add any other element. This image is used as an atlas with exact panel regions, so unchanged dimensions and panel alignment are essential.
```

Встроенный ImageGen. Фон создан редактированием прежнего `diner.png`, коробка — по новому фону как референсу палитры и стиля.

Результаты: `games/the_mind/art/diner.png`, `hub/covers/unspoken_wrap.png`. Грани коробки — AtlasTexture `hub/covers/the_mind_{front,back,spine,top}.tres`; исходный лист не нарезался и не перерисовывался кодом. Предыдущий фон сохранён в `backups/unspoken_20261101/diner.png`.

## Фон — полный промпт

```text
Edit this game background by simplifying it substantially, preserving its composition, deep green / amber / warm ivory palette, 1960s roadside atmosphere, upper scenic band and large empty lower playing area. Make it feel deliberately designed and hand drawn, like a restrained two- or three-ink mid-century screenprinted poster. Reduce the scene to ONE simple dark-green vintage car silhouette at the left edge, ONE low diner silhouette at the right edge, THREE palm silhouettes total, ONE smooth mountain shape and ONE flat sun disk. Remove the second car, all telephone poles and wires, tiny houses, window grids, car trim, reflections, scattered bushes, clouds and busy texture. The diner has a single blank sign, no text. Use large flat color shapes with a few imperfect hand-painted edges, almost no internal detail, only a subtle uniform paper grain. Upper scenery uses about 30% of image height. Keep the lower 65% almost uniform quiet dark green, clean and empty for gameplay. No cards, interface, text or borders. Do not add objects. Not photorealistic, not detailed digital concept art, no dense brush noise, no artificial weathering. Landscape 1536x1024.
```

## Коробка — полный промпт

```text
Create original FLAT PRINT ARTWORK for a small card game box titled 'UNSPOKEN'. One landscape image 2048x1536, divided into exactly THREE contiguous vertical panels with no gaps: FRONT x=0..895 (896x1536), SPINE x=896..1151 (256x1536), BACK x=1152..2047 (896x1536). Panel boundaries are exactly vertical at x=896 and x=1152. These are actual 2D texture panels, NOT a photograph or 3D box mockup, no perspective, no shadows outside artwork, no guides, no crop marks. Style: very restrained early 1960s screenprinted graphic design, flat dark petroleum green #183D35, warm ivory #E5D6B8, muted amber #D69B49, subtle uniform paper grain. Large simple shapes and generous empty space; no tiny decorative details, no noisy weathering. FRONT: dominant large perfectly legible bold condensed uppercase title 'UNSPOKEN' across upper portion, ivory on green. Below, a simple amber sun disk, ONE palm silhouette and ONE simplified long vintage car silhouette near a low horizon; a small fan of THREE ivory number cards with '12', '34', '56' in dark green, integrated into the poster composition. Exact short bottom line 'ОДНА КОМАНДА. БЕЗ СЛОВ.' and tiny simple '2–4   •   20 MIN' only. SPINE: solid deep green with large ivory 'UNSPOKEN' rotated 90 degrees, a small amber sun disk at an end, no other text. BACK: visually coordinated deep green and amber, heading 'UNSPOKEN' at top, three simple abstract overlapping wave arcs and three small ivory cards '12', '34', '56' lower down, broad negative space; exact bottom line 'ПОЧУВСТВУЙТЕ МОМЕНТ'. No publisher logos, barcodes, rabbit, ninja star, product photographs, fake small print, invented credits or extra text. Hand-designed poster appearance, simple clean silhouettes. Colors and period mood match the provided simplified background, but the image is a box texture wrap, not a game scene.
```
