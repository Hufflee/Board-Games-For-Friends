shader_type spatial;
render_mode unshaded;

uniform sampler2D front_city : source_color, filter_linear, repeat_disable;
uniform sampler2D side_city : source_color, filter_linear, repeat_disable;
uniform float side_view : hint_range(0.0, 1.0) = 0.0;

varying vec3 window_world;

void vertex() {
	window_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Дома находятся за стеклом. При взгляде сбоку виден соседний участок города.
	vec3 ray = window_world - CAMERA_POSITION_WORLD;
	vec2 parallax = clamp(ray.xy / max(abs(ray.z), 0.25), vec2(-2.5), vec2(2.5));
	vec2 uv = UV * vec2(0.57, 0.94) + vec2(0.085, 0.03);
	vec2 side_uv = uv + parallax * vec2(0.026, -0.055);
	vec3 front = texture(front_city, UV).rgb;
	vec3 side = texture(side_city, side_uv).rgb;
	ALBEDO = mix(front, side, side_view) * vec3(1.25, 1.1, 1.25);
}
