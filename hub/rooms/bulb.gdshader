shader_type spatial;
// Лампочка гирлянды зимней комнаты (hub/rooms/winter_decor.gd). Один материал — один цвет одной группы
// (ёлка / стены). Режимы «Переливы» и «По одному цвету» считает скрипт (lit, color_index), «Мигание» —
// сам шейдер: у каждой лампочки (MultiMesh, INSTANCE_CUSTOM.x) свой ритм, цвет сдвигается на каждом мигании.
// Время — общее TIME: одинаковый режим на ёлке и стенах мигает синхронно.

uniform vec3 palette[4];
uniform int base_index = 0;
uniform int color_index = 0;
uniform float lit = 1.0;  // яркость 0..1 для режимов скрипта
uniform float energy = 1.0;
uniform float blink = 0.0;  // 1 — мигание вразнобой

varying float seed;

void vertex() {
	seed = INSTANCE_CUSTOM.x;
}

void fragment() {
	float b = lit;
	int ci = color_index;
	if (blink > 0.5) {
		float period = 0.6 + seed * 0.7;
		float t = TIME + seed * 17.0;
		float ph = fract(t / period);
		b = 1.0;
		if (ph < 0.18) {
			b = 1.0 - ph / 0.18;
		} else if (ph < 0.36) {
			b = (ph - 0.18) / 0.18;
		}
		b = 0.03 + 0.97 * b * b;
		int cycle = int(floor(t / period + 0.82));  // новый цвет — в самой тёмной точке
		ci = (base_index + cycle + int(seed * 4.0)) % 4;
	}
	vec3 c = palette[ci];
	ALBEDO = c * mix(0.15, 1.0, b);  // погасшая лампочка теряет цвет
	EMISSION = c * energy * b;
	ROUGHNESS = 0.3;
}
