shader_type spatial;
// Махровый новогодний ковёр (hub/rooms/winter_decor.gd): узор — картинка hub/art/winter/carpet.png,
// петли ворса — мелкий шум в цвете и в нормалях, углы прямые с чуть скруглённым кончиком, края «лохматые», у края ворс темнее.
render_mode cull_disabled, diffuse_lambert, specular_disabled;  // ворс свет не отражает

uniform sampler2D pattern : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 size_m = vec2(5.0, 3.5);  // размер ковра в метрах
uniform float corner = 0.05;  // углы прямые, только кончик чуть скруглён (владелец), м
uniform float loop_scale = 240.0;  // петель на метр

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 m = UV * size_m;
	vec2 q = abs(m - size_m * 0.5) - (size_m * 0.5 - vec2(corner));
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner;
	// лохматый край: ворсинки выбиваются на несколько миллиметров
	float fuzz = (vnoise(m * 220.0) - 0.5) * 0.014 + (vnoise(m * 35.0) - 0.5) * 0.012;
	if (sdf + fuzz > 0.0) {
		discard;
	}
	// петли ворса; вдали (крупный fwidth) шум гаснет, чтобы не рябило
	vec2 lp = m * loop_scale;
	float aa = clamp(1.6 - length(fwidth(lp)) * 1.2, 0.0, 1.0);
	float loops = mix(0.5, vnoise(lp), aa);
	float clumps = vnoise(m * 70.0 + 7.0);
	vec3 col = texture(pattern, UV).rgb;
	float shade = 0.8 + 0.3 * loops + 0.14 * (clumps - 0.5);
	shade *= mix(0.72, 1.0, smoothstep(0.0, 0.04, -sdf));
	ALBEDO = col * shade * 0.85;  // белая кайма у шкафа не должна светиться
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float e = 0.35 / loop_scale;
	float hx = vnoise((m + vec2(e, 0.0)) * loop_scale) - vnoise(lp);
	float hy = vnoise((m + vec2(0.0, e)) * loop_scale) - vnoise(lp);
	NORMAL_MAP = normalize(vec3(-hx * 1.4 * aa, -hy * 1.4 * aa, 1.0)) * 0.5 + 0.5;
}
