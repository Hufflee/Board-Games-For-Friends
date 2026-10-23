shader_type canvas_item;
// Фон: тёплая бумага для рисования, мягкие цветные пятна и (painted = true) акварельные кляксы
// с тёмным краем, как у высохшей краски, и мелкими брызгами вокруг.

uniform vec3 base = vec3(0.957, 0.945, 0.922);
uniform float strength = 0.16;
uniform bool painted = false;
// Параллакс от мыши: -1…1 (0 — курсор в центре). Кляксы уходят против движения курсора, каждая на своей
// «глубине»; кляксы на стороне, противоположной курсору, чуть растут — как будто приближаются к экрану.
uniform vec2 parallax = vec2(0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 blob(vec2 uv, vec2 c, float r, vec3 col, vec3 acc) {
	float d = length(uv - c);
	float k = exp(-d * d / (r * r));
	return mix(acc, col, k * strength);
}

// Клякса: неровный край (угловые гармоники + шум), заливка светлее, край темнее.
vec3 splat(vec2 uv, vec2 c0, float r0, float seed, vec3 col, vec3 acc) {
	float depth = 0.7 + 0.6 * hash(vec2(seed, 1.3));  // ближе / дальше
	vec2 c = c0 - parallax * 0.035 * depth;
	vec2 from_mid = normalize(c0 - vec2(0.889, 0.5));
	float r = r0 * (1.0 + 0.16 * depth * max(0.0, dot(from_mid, -parallax)));
	vec2 d = uv - c;
	float ang = atan(d.y, d.x);
	vec2 dir = vec2(cos(ang), sin(ang));
	float rr = r * (1.0 + 0.07 * sin(ang * 3.0 + seed) + 0.05 * sin(ang * 7.0 + seed * 2.3)
		+ 0.6 * (fbm(dir * 2.2 + seed * 1.7) - 0.5) + 0.12 * (fbm(d * 18.0 + seed) - 0.5));
	float dist = length(d);
	float inside = smoothstep(rr, rr - 0.006, dist);
	float edge = smoothstep(rr - 0.035, rr - 0.004, dist) * inside;
	float wash = 0.32 + 0.18 * fbm(uv * 14.0 + seed);
	vec3 res = mix(acc, col, inside * wash);
	res = mix(res, col * 0.82, edge * 0.35);
	// брызги вокруг
	for (int k = 0; k < 7; k++) {
		float a = seed * 3.1 + float(k) * 2.39;
		float dd = r * (1.25 + 0.55 * hash(vec2(seed, float(k))));
		vec2 pc = c + vec2(cos(a), sin(a)) * dd;
		float pr = r * (0.05 + 0.08 * hash(vec2(float(k), seed)));
		float s = smoothstep(pr, pr - 0.004, length(uv - pc));
		res = mix(res, col, s * 0.5);
	}
	return res;
}

void fragment() {
	vec2 uv = UV;
	uv.x *= 16.0 / 9.0;
	float t = TIME * 0.035;
	vec3 c = base;
	vec2 far = parallax * 0.012;  // мягкие пятна — далеко, сдвигаются чуть-чуть
	uv -= far;
	c = blob(uv, vec2(0.25 + 0.06 * sin(t * 1.3), 0.2 + 0.05 * cos(t)), 0.42, vec3(0.98, 0.72, 0.55), c);
	c = blob(uv, vec2(1.5 + 0.07 * cos(t * 0.9), 0.25 + 0.06 * sin(t * 1.1)), 0.48, vec3(0.62, 0.72, 0.95), c);
	c = blob(uv, vec2(1.0 + 0.08 * sin(t * 0.7), 0.95 + 0.04 * cos(t * 1.7)), 0.5, vec3(0.6, 0.86, 0.74), c);
	c = blob(uv, vec2(0.35 + 0.05 * cos(t * 1.5), 0.95), 0.36, vec3(0.93, 0.68, 0.82), c);
	if (painted) {
		// фактура бумаги для акварели
		uv += far;  // бумага не двигается
		float paper = fbm(uv * 60.0) * 0.5 + fbm(uv * 180.0) * 0.5;
		c *= 0.975 + 0.05 * paper;
		c = splat(uv, vec2(0.10, 0.12), 0.075, 1.7, vec3(0.93, 0.36, 0.42), c);
		c = splat(uv, vec2(1.66, 0.10), 0.06, 4.2, vec3(0.30, 0.55, 0.88), c);
		c = splat(uv, vec2(1.70, 0.86), 0.09, 7.9, vec3(0.98, 0.76, 0.22), c);
		c = splat(uv, vec2(0.08, 0.88), 0.065, 2.8, vec3(0.36, 0.72, 0.48), c);
		c = splat(uv, vec2(0.92, 0.04), 0.04, 5.5, vec3(0.62, 0.40, 0.80), c);
		c = splat(uv, vec2(1.25, 0.97), 0.045, 9.1, vec3(0.96, 0.55, 0.25), c);
	}
	// лёгкое зерно бумаги
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) * 0.012;
	COLOR = vec4(c, 1.0);
}
