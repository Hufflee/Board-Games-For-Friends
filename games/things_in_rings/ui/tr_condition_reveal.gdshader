shader_type canvas_item;
// Те же растущие облачные пятна (effect 0), что в hub/scene_transition.gdshader.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
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
void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	vec2 q = vec2(UV.x * 0.655, UV.y) * 3.0;
	float m = fbm(q + vec2(p * 0.35, -p * 0.2));
	float reveal = 1.0 - smoothstep(p * 1.4 - 0.22, p * 1.4 - 0.10, m);
	if (p <= 0.0) { reveal = 0.0; }
	if (p >= 1.0) { reveal = 1.0; }
	COLOR.a *= reveal;
}
