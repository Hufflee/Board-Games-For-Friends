shader_type spatial;
// «Мягкий» параллелепипед для мебели комнаты: скруглённые кромки (нормаль плавно загибается у рёбер —
// свет ложится как на настоящую фаску), процедурная фактура (дерево / пластик / ткань), лак, кубиковые точки.
// half_size — половина размера BoxMesh, radius — радиус скругления кромки.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 half_size = vec3(0.5);
uniform float radius = 0.02;
uniform vec4 albedo : source_color = vec4(0.2, 0.15, 0.3, 1.0);
uniform vec4 albedo2 : source_color = vec4(0.12, 0.08, 0.2, 1.0);  // тёмные волокна / ворс
uniform float grain = 0.0;  // 0 — гладко, 1 — выраженная фактура
uniform vec3 grain_dir = vec3(0.0, 1.0, 0.0);  // вдоль чего идут волокна
uniform float grain_scale = 40.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.0;
uniform float edge_shade = 0.18;  // лёгкое затемнение в самом углу (контактная тень)
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform sampler2D pips_tex : hint_default_black, filter_linear_mipmap;  // маска точек (кубики)
uniform float use_pips = 0.0;
uniform vec4 pip_color : source_color = vec4(1.0);

varying vec3 lp;
varying vec3 ln;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// вклад одной оси в загиб нормали у кромки
float bend(float p, float h, float face_axis) {
	if (face_axis > 0.5) {
		return 0.0;
	}
	float d = abs(p) - (h - radius);
	return clamp(d / max(radius, 0.0001), 0.0, 1.0);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 n = normalize(ln);
	vec3 a = abs(n);
	float tx = bend(lp.x, half_size.x, a.x);
	float ty = bend(lp.y, half_size.y, a.y);
	float tz = bend(lp.z, half_size.z, a.z);
	vec3 t = vec3(tx, ty, tz);
	vec3 ts = t * t * (3.0 - 2.0 * t);
	vec3 bent = normalize(n + sign(lp) * ts * 1.6);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bent, 0.0)).xyz);

	// фактура: вытянутый вдоль волокон шум
	vec3 q = lp * (vec3(1.0) - grain_dir * 0.93) * grain_scale;
	float g = noise(q + noise(lp * 6.0) * 2.5) * 0.7 + noise(q * 3.1) * 0.3;
	vec3 col = mix(albedo.rgb, albedo2.rgb, smoothstep(0.25, 0.85, g) * grain);
	if (use_pips > 0.5) {
		col = mix(col, pip_color.rgb, texture(pips_tex, UV).r);
	}
	float corner = max(max(tx, ty), tz);
	col *= 1.0 - edge_shade * corner * corner;
	ALBEDO = col;
	ROUGHNESS = clamp(roughness + (g - 0.5) * 0.15 * grain, 0.0, 1.0);
	METALLIC = metallic;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = 0.12;
	EMISSION = emission_color.rgb * emission_energy;
}
