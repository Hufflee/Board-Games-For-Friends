shader_type canvas_item;
render_mode unshaded;
// Девять переходов. Снимок хаба сверху, живая новая сцена — из экранной текстуры.
uniform sampler2D old_screen : filter_linear_mipmap, repeat_disable;
uniform sampler2D new_screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D box_screen : filter_linear_mipmap, repeat_disable;
uniform int effect = 0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.7778;
uniform float seed = 0.0;
uniform vec2 focus = vec2(0.5);
uniform bool has_box = false;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031 + seed);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, amplitude = 0.55;
	mat2 rotation = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 4; i++) {
		v += noise(p) * amplitude;
		p = rotation * p + vec2(5.2, 1.3);
		amplitude *= 0.48;
	}
	return v;
}
// Явное размытие работает одинаково в Forward+ и Compatibility, без истории mip-кадров экрана.
vec3 old_at(vec2 uv, float blur) {
	uv = clamp(uv, vec2(0.001), vec2(0.999));
	if (blur < 0.01) { return textureLod(old_screen, uv, 0.0).rgb; }
	vec2 radius = vec2((exp2(blur) - 1.0) * 0.55) / vec2(textureSize(old_screen, 0));
	vec3 color = vec3(0.0);
	float total = 0.0;
	// Диск Фогеля: плотные выборки без видимых копий букв при сильном блюре.
	for (int i = 0; i < 48; i++) {
		float fraction = (float(i) + 0.5) / 48.0;
		float angle = float(i) * 2.399963;
		vec2 offset = vec2(cos(angle), sin(angle)) * sqrt(fraction) * radius;
		float weight = exp(-fraction * 2.0);
		color += textureLod(old_screen, clamp(uv + offset, vec2(0.001), vec2(0.999)), 0.0).rgb * weight;
		total += weight;
	}
	return color / total;
}
vec3 new_at(vec2 uv, float blur) {
	uv = clamp(uv, vec2(0.001), vec2(0.999));
	if (blur < 0.01) { return textureLod(new_screen, uv, 0.0).rgb; }
	vec2 radius = vec2((exp2(blur) - 1.0) * 0.55) / vec2(textureSize(new_screen, 0));
	vec3 color = vec3(0.0);
	float total = 0.0;
	// Диск Фогеля: плотные выборки без видимых копий букв при сильном блюре.
	for (int i = 0; i < 48; i++) {
		float fraction = (float(i) + 0.5) / 48.0;
		float angle = float(i) * 2.399963;
		vec2 offset = vec2(cos(angle), sin(angle)) * sqrt(fraction) * radius;
		float weight = exp(-fraction * 2.0);
		color += textureLod(new_screen, clamp(uv + offset, vec2(0.001), vec2(0.999)), 0.0).rgb * weight;
		total += weight;
	}
	return color / total;
}
void fragment() {
	vec2 uv = UV;
	float p = clamp(progress, 0.0, 1.0);
	vec3 old_color = old_at(uv, 0.0);
	vec3 new_color = new_at(uv, 0.0);
	vec3 color = old_color;
	if (effect == 0) { // прежние мягкие облачные пятна
		vec2 q = vec2(uv.x * aspect, uv.y) * 3.0;
		float m = fbm(q + vec2(p * 0.35, -p * 0.2));
		float reveal = 1.0 - smoothstep(p * 1.4 - 0.22, p * 1.4 - 0.10, m);
		color = mix(old_at(uv, p * 4.5), new_color, reveal);
	} else if (effect == 1) { // мягкая градиентная шторка
		float axis = mix(uv.x, 1.0 - uv.x, step(0.5, seed));
		axis += (uv.y - 0.5) * 0.16;
		float reveal = 1.0 - smoothstep(p * 1.5 - 0.30, p * 1.5 - 0.06, axis);
		color = mix(old_color, new_color, reveal);
	} else if (effect == 2) { // затемнение до чёрного и проявление
		float out_fade = smoothstep(0.0, 0.46, p);
		float in_fade = smoothstep(0.54, 1.0, p);
		color = p < 0.5 ? old_color * (1.0 - out_fade) : new_color * in_fade;
	} else if (effect == 3) { // растворение с блюром обоих экранов
		float blur = sin(p * 3.141593) * 5.5;
		color = mix(old_at(uv, blur), new_at(uv, blur), p);
	} else if (effect == 4) { // пролёт: хаб растёт, окно игры расширяется из коробки
		vec2 old_uv = focus + (uv - focus) / (1.0 + 7.0 * p * p);
		float scale = mix(0.025, 1.0, smoothstep(0.12, 1.0, p));
		vec2 center = mix(focus, vec2(0.5), smoothstep(0.15, 0.85, p));
		vec2 next_uv = (uv - center) / scale + vec2(0.5);
		float border = max(abs(next_uv.x - 0.5), abs(next_uv.y - 0.5));
		float window = (1.0 - smoothstep(0.495, 0.505, border)) * smoothstep(0.02, 0.17, p);
		window = mix(window, 1.0, smoothstep(0.97, 1.0, p));
		color = mix(old_at(old_uv, sin(p * 3.141593) * 2.0), new_at(next_uv, 0.0), window);
	} else if (effect == 5) { // перекрёстный зум с радиальным размытием
		vec3 a = vec3(0.0), b = vec3(0.0);
		float streak = sin(p * 3.141593) * 0.18;
		for (int i = 0; i < 9; i++) {
			float offset = (float(i) / 8.0 - 0.5) * streak;
			vec2 old_uv = focus + (uv - focus) / (1.0 + p * 0.8 + offset);
			vec2 new_uv = vec2(0.5) + (uv - vec2(0.5)) / (0.72 + p * 0.28 + offset);
			a += old_at(old_uv, 0.0) / 9.0;
			b += new_at(new_uv, 0.0) / 9.0;
		}
		color = mix(a, b, p);
	} else if (effect == 6) { // дымная волна с завихрениями вдоль края
		vec2 q = vec2(uv.x * aspect, uv.y);
		float smoke = fbm(q * 5.0 + vec2(-p * 1.3, p * 0.7));
		float front = uv.x + (smoke - 0.5) * 0.55;
		float reveal = 1.0 - smoothstep(p * 1.75 - 0.42, p * 1.75 - 0.18, front);
		float edge = 4.0 * reveal * (1.0 - reveal);
		color = mix(old_at(uv, edge * 3.0), new_at(uv, edge * 2.0), reveal);
		color = mix(color, vec3(0.42, 0.44, 0.49), edge * 0.32);
	} else if (effect == 7) { // morph cut: настоящая коробка сохраняется над новой сценой
		float background = smoothstep(0.0, 0.44, p);
		color = mix(old_at(uv, background * 3.0), new_color, background);
		if (has_box) {
			float dissolve = smoothstep(0.52, 1.0, p);
			float scale = 1.0 + 0.045 * smoothstep(0.44, 1.0, p);
			vec2 box_uv = focus + (uv - focus) / scale;
			vec4 box = textureLod(box_screen, box_uv, dissolve * 5.5);
			color = mix(color, box.rgb, box.a * (1.0 - dissolve));
		}
	} else { // чернильное пятно растекается от коробки, край мелкий и рваный
		vec2 q = (uv - focus) * vec2(aspect, 1.0);
		float fibers = fbm(q * 24.0);
		float ink = length(q) + (fbm(q * 6.0) - 0.5) * 0.22 + (fibers - 0.5) * 0.065;
		float radius = mix(-0.25, 2.5, p);
		float reveal = 1.0 - smoothstep(radius - 0.028, radius + 0.028, ink);
		color = mix(old_color, new_color, reveal);
		color *= 1.0 - 0.18 * (4.0 * reveal * (1.0 - reveal));
	}
	// Точные крайние кадры: без вспышки при создании и удалении слоя.
	if (p <= 0.0) { color = old_color; }
	if (p >= 1.0) { color = new_color; }
	COLOR = vec4(color, 1.0);
}
