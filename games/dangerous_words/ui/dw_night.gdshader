shader_type canvas_item;
// Ночное небо подземелья: фиолетовый градиент, луна с ореолом, ползущий туман, лёгкое мерцание.

uniform vec2 rect_size = vec2(1280.0, 720.0);

// хэш без sin(): у sin() на больших координатах теряется точность — туман шёл «ступеньками»
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * rect_size;
	float t = TIME;
	vec3 top = vec3(0.10, 0.04, 0.17);
	vec3 bottom = vec3(0.03, 0.02, 0.06);
	vec3 col = mix(top, bottom, uv.y);
	// звёзды
	float s = step(0.997, hash(floor(p / 3.0))) * (0.5 + 0.5 * sin(t * 2.0 + hash(floor(p / 3.0)) * 30.0));
	col += vec3(s) * (1.0 - uv.y) * 0.8;
	// луна
	vec2 moon = vec2(rect_size.x * 0.86, rect_size.y * 0.16);
	float d = length(p - moon);
	col += vec3(0.95, 0.85, 0.6) * smoothstep(48.0, 44.0, d);
	col -= vec3(0.15, 0.12, 0.05) * smoothstep(48.0, 20.0, length(p - moon - vec2(12.0, -8.0))) * step(d, 48.0);
	col += vec3(1.0, 0.7, 0.3) * 0.25 * exp(-d / 120.0);
	// туман внизу
	float fog = fbm(vec2(uv.x * rect_size.x / 260.0 + t * 0.05, uv.y * rect_size.y / 140.0 - t * 0.02));
	float fog_mask = smoothstep(0.35, 1.0, uv.y);
	col = mix(col, vec3(0.45, 0.35, 0.6), fog * fog_mask * 0.45);
	// зелёное свечение снизу
	col += vec3(0.1, 0.35, 0.05) * pow(uv.y, 4.0) * (0.6 + 0.2 * sin(t * 1.3));
	// виньетка
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 1.1;
	// лёгкий дизеринг — без полос на плавных переходах тумана
	col += (hash(FRAGCOORD.xy + fract(t)) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
