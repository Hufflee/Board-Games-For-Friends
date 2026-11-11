shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 drift = vec2(0.0);

void fragment() {
	vec2 point = UV - vec2(0.27, 0.25) - drift * 2.0;
	float light = exp(-dot(point * vec2(1.5, 1.0), point * vec2(1.5, 1.0)) * 9.0);
	vec2 shadow = UV - vec2(0.88, 0.84) + drift;
	float shade = exp(-dot(shadow, shadow) * 8.0) * 0.13;
	COLOR = vec4(mix(tint.rgb, vec3(0.05, 0.07, 0.11), shade / max(shade + light * 0.14, 0.001)),
		shade + light * 0.14);
}
