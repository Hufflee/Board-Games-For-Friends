shader_type spatial;
// Коробка «Coming soon»: по граням бегает белый шум, как на выключенном канале ЭЛТ-телевизора.
// Коробка остаётся объёмной: шум — в свечении, у рёбер (как у soft_box) нормаль загибается.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 half_size = vec3(0.5);
uniform float radius = 0.004;
uniform float grain = 140.0;  // зёрен на единицу UV
uniform float speed = 24.0;  // смен кадра в секунду
uniform float energy = 0.55;
uniform float hover = 0.0;
uniform float albedo_mul = 0.35;

varying vec3 lp;
varying vec3 ln;

// хэш без sin(): у sin() на больших аргументах теряется точность — через какое-то время
// работы игры шум «замирал» и превращался в полосы
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bend(float p, float h, float face_axis) {
	if (face_axis > 0.5) {
		return 0.0;
	}
	return clamp((abs(p) - (h - radius)) / radius, 0.0, 1.0);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 n = normalize(ln);
	vec3 a = abs(n);
	vec3 t = vec3(bend(lp.x, half_size.x, a.x), bend(lp.y, half_size.y, a.y), bend(lp.z, half_size.z, a.z));
	vec3 bent = normalize(n + sign(lp) * t * t * 1.6);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bent, 0.0)).xyz);
	// зерно в мировых единицах по двум осям грани — одинаковое на всех гранях
	vec2 uv = (a.x > 0.5) ? lp.zy : ((a.y > 0.5) ? lp.xz : lp.xy);
	float tm = mod(TIME, 600.0);  // время по кругу: номер кадра не растёт до огромных значений
	float frame = floor(tm * speed);
	vec2 cell = floor(uv * grain * 10.0);
	float v = hash(cell + vec2(mod(frame * 13.1, 977.0), mod(frame * 7.7, 983.0)));
	v = mix(v, hash(cell * 1.7 + mod(frame, 991.0)), 0.35);
	// полосы «срыва синхронизации»
	float band = smoothstep(0.96, 1.0, sin(uv.y * 40.0 + tm * 5.0)) * 0.25;
	float s = clamp(v * 1.15 - 0.1 + band, 0.0, 1.0);
	ALBEDO = vec3(s * albedo_mul);
	ROUGHNESS = 0.4;
	EMISSION = vec3(s) * (energy + hover * 0.6);
}
