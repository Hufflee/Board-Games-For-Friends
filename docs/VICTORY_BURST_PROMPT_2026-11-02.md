# Вспышка победы 02.11: код и исторический промпт

Текущий вариант одиночной победы рисуется кодом: `hub/victory_burst.gd` и `hub/victory_burst.gdshader`. Квадратный PNG в этой ветке больше не рисуется. Два слоя неровной звезды, светлый серп сверху/тень снизу, кольцо лампочек, 20 затухающих лучей (оборот 50 с), тёплое свечение и 8 мерцающих искр. Палитра из акцента игры + золото, тема влияет на насыщенность/контур/свечение. Появление 0.6→1.08→1.0 за 0.5 с; при `Prefs.parallax=false` эффект полностью статичен.

Сначала владелец выбирает одиночную победу в двух темах; широкие варианты и окончательный перенос старого PNG — следующий этап. Прежний PNG пока остаётся только для нескольких победителей; резервная копия уже в `backups/victory_burst_code_20261102/`. Нового промпта ImageGen нет: генерация изображений для этой переделки не использовалась.

## История: прежний PNG

Встроенный ImageGen, прозрачный PNG `hub/art/victory_burst_20261102.png`. Используется общим экраном победы. Рисованный объём, мягкий свет сверху, края гуашью. Исходное изображение просмотрено; alpha сохранена, программно изображение не редактировалось.

Промпт:

> Create one game UI sprite: a large joyful irregular starburst / ink-splat badge for a board-game victory screen. Transparent background. No text, no symbols, no characters. Warm muted golden yellow with peach orange folded edges, hand-painted dimensional soft bevel, small organic imperfections, painterly gouache shading, subtle soft shadow under its lower edge. A broad quiet center to sit behind winner portraits; 10 to 12 asymmetrical short rounded points. Cheerful tactile illustrated volume, rich but restrained, neither flat vector nor glossy plastic. Single centered complete silhouette, square canvas with transparent margin, no surrounding sparkles or detached elements.
