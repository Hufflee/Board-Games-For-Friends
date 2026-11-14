shader_type spatial;
render_mode unshaded;

uniform sampler2D front_city : source_color, filter_linear, repeat_disable;
uniform sampler2D side_city : source_color, filter_linear, repeat_disable;
uniform float side_view : hint_range(0.0, 1.0) = 0.0;
// Зимняя комната (hub/rooms): падающий снег, сугроб снаружи на отливе, иней по углам стекла.
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float window_aspect = 1.3;

varying vec3 window_world;

void vertex() {
	window_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Один слой снежинок: сетка ячеек, в части ячеек — снежинка со своим сдвигом, размером и покачиванием.
float flakes(vec2 uv, float scale, float speed, float seed, vec2 shift) {
	vec2 p = uv * scale + shift;
	p.y -= TIME * speed;
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(cell + seed);
	if (h < 0.45) {
		return 0.0;
	}
	vec2 offs = (vec2(hash(cell + seed + 1.7), hash(cell + seed + 9.3)) - 0.5) * 0.6;
	offs.x += sin(TIME * (0.6 + h) + h * 40.0) * 0.18;
	float r = mix(0.07, 0.16, hash(cell + seed + 4.1));
	float d = length(f - offs);
	return smoothstep(r, r * 0.35, d) * mix(0.55, 1.0, h);
}

void fragment() {
	// Дома находятся за стеклом. При взгляде сбоку виден соседний участок города.
	vec3 ray = window_world - CAMERA_POSITION_WORLD;
	vec2 parallax = clamp(ray.xy / max(abs(ray.z), 0.25), vec2(-2.5), vec2(2.5));
	vec2 uv = UV * vec2(0.57, 0.94) + vec2(0.085, 0.03);
	vec2 side_uv = uv + parallax * vec2(0.026, -0.055);
	vec3 front = texture(front_city, UV).rgb;
	vec3 side = texture(side_city, side_uv).rgb;
	vec3 color = mix(front, side, side_view) * vec3(1.25, 1.1, 1.25);
	if (snow > 0.0) {
		vec2 suv = UV * vec2(window_aspect, 1.0);
		// три слоя: дальние мелкие и медленные, ближние крупные; параллакс — глубина
		float s = flakes(suv, 34.0, 0.9, 3.0, parallax * vec2(0.6, -0.4)) * 0.55;
		s += flakes(suv, 20.0, 0.75, 11.0, parallax * vec2(1.2, -0.8)) * 0.8;
		s += flakes(suv, 11.0, 0.55, 23.0, parallax * vec2(2.4, -1.6));
		// сугроб на внешнем отливе: волнистый край у нижней кромки
		float edge = 0.925 + 0.018 * sin(UV.x * 21.0) + 0.012 * sin(UV.x * 7.0 + 1.3);
		float drift = smoothstep(edge - 0.006, edge + 0.004, UV.y);
		// иней по углам
		vec2 q = (UV - 0.5) * vec2(1.0, 1.15);
		float frost = smoothstep(0.5, 0.78, length(q)) * (0.55 + 0.45 * hash(floor(UV * 90.0)));
		vec3 white = vec3(0.92, 0.95, 1.05);
		color = mix(color, color * 0.9 + vec3(0.06, 0.07, 0.12), snow * 0.5);  // зимний воздух чуть холоднее
		color = mix(color, white, clamp(s, 0.0, 1.0) * snow);
		color = mix(color, white * vec3(0.86, 0.9, 1.0), drift * snow);
		color = mix(color, vec3(0.78, 0.86, 1.0), frost * 0.45 * snow);
	}
	ALBEDO = color;
}
